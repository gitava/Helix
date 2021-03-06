defmodule Helix.Server.Action.Motherboard.Update do

  import HELL.Macros

  alias Helix.Network.Action.Network, as: NetworkAction
  alias Helix.Network.Model.Network
  alias Helix.Network.Query.Network, as: NetworkQuery
  alias Helix.Server.Action.Component, as: ComponentAction
  alias Helix.Server.Model.Component
  alias Helix.Server.Model.Motherboard
  alias Helix.Server.Internal.Motherboard, as: MotherboardInternal
  alias Helix.Server.Query.Component, as: ComponentQuery
  alias Helix.Server.Query.Motherboard, as: MotherboardQuery
  alias Helix.Server.Repo, as: ServerRepo

  @internet_id NetworkQuery.internet().network_id

  @type motherboard_data ::
    %{
      mobo: Component.mobo,
      components: [update_component],
      network_connections: [update_nc]
    }

  @type update_component :: {Component.pluggable, Motherboard.slot_id}
  @type update_nc ::
    %{
      nic_id: Component.id,
      network_id: Network.id,
      ip: Network.ip,
      network_connection: Network.Connection.t
    }

  @spec detach(Motherboard.t) ::
    :ok
  @doc """
  Detaches the `motherboard`.
  """
  def detach(motherboard = %Motherboard{}) do
    MotherboardInternal.unlink_all(motherboard)

    # Network configuration is asynchronous
    hespawn fn ->
      motherboard
      |> MotherboardQuery.get_nics()
      |> Enum.each(fn nic ->
        nc = NetworkQuery.Connection.fetch_by_nic(nic.component_id)

        if nc do
          perform_network_op({:nilify_nic, nc})
        end
      end)
    end

    :ok
  end

  @spec update(Motherboard.t | nil, motherboard_data, [Network.Connection.t]) ::
    {:ok, Motherboard.t, [term]}
  @doc """
  Updates the motherboard.

  First parameter is the current motherboard. If `nil`, a motherboard is being
  attached to a server that was currently without motherboard.

  Updating a motherboard is - as of now - quite naive: we simply unlink all
  existing components and then link what was specified by the user.
  """
  def update(nil, mobo_data, entity_ncs) do
    {:ok, new_mobo} =
      MotherboardInternal.setup(mobo_data.mobo, mobo_data.components)

    # Network configuration is asynchronous
    hespawn fn ->
      update_network_connections(mobo_data, entity_ncs)
    end

    {:ok, new_mobo, []}
  end

  def update(
    motherboard,
    mobo_data,
    entity_ncs)
  do
    {:ok, {:ok, new_mobo}} =
      ServerRepo.transaction fn ->
        MotherboardInternal.unlink_all(motherboard)
        MotherboardInternal.setup(mobo_data.mobo, mobo_data.components)
      end

    # Network configuration is asynchronous
    hespawn fn ->
      update_network_connections(mobo_data, entity_ncs)
    end

    {:ok, new_mobo, []}
  end

  @spec update_network_connections(motherboard_data, [Network.Connection.t]) ::
    term
  docp """
  Iterates through the player's network connections (NCs), as well as all NCs
  assigned to the new motherboard configuration.

  This iteration detects which (if any) NC should be updated, either because it
  was previously attached to the motherboard and was removed, or because it was
  not previously attached to any mobo but now it is.
  """
  defp update_network_connections(mobo_data, entity_ncs) do
    ncs = mobo_data.network_connections

    entity_ncs

    # Get the required operations we may have to do on NetworkConnections...
    |> Enum.reduce([], fn nc, acc ->
        cond do
          # The NIC already has an NC attached to it
          mobo_nc = has_nic?(ncs, nc.nic_id) ->
            # The given NC is the same as before; we don't have to do anything
            if nc == mobo_nc.network_connection do
              acc

            # There will be a new NC attached to this NIC, so we have to
            # remove the previous NC reference to this NIC, as it's no longer
            # used. Certainly we'll also have to update the new NC to point
            # to this NIC. That's done on another iteration at :set_nic below
            else
              acc ++ [{:nilify_nic, nc}]
            end

          # TODO: What if NIP is in use? Henforce!
          # The current NC nic is not in use, but its nip is being assigned.
          # This means the NC will start being used, so we need to link it to
          # the underlying NIC.
          mobo_nc = has_nip?(ncs, nc.network_id, nc.ip) ->
            acc ++ [{:set_nic, nc, mobo_nc.nic_id}]

          # This NC is not modified at all by the mobo update
          true ->
            acc
        end
      end)

    # Perform those NetworkConnection operations
    |> Enum.each(&perform_network_op/1)
  end

  @spec has_nic?([update_nc], Component.id) ::
    boolean
  defp has_nic?(ncs, nic_id),
    do: Enum.find(ncs, &(&1.nic_id == nic_id))

  @spec has_nip?([update_nc], Network.id, Network.ip) ::
    boolean
  defp has_nip?(ncs, network_id, ip),
    do: Enum.find(ncs, &(&1.network_id == network_id and &1.ip == ip))

  @typep network_op_input ::
    {:nilify_nic, Network.Connection.t}
    | {:set_nic, Network.Connection.t, Component.id}

  @spec perform_network_op(network_op_input) ::
    term
  defp perform_network_op({:nilify_nic, nc = %Network.Connection{}}),
    do: {:ok, _} = NetworkAction.Connection.update_nic(nc, nil)
  defp perform_network_op({:set_nic, nc = %Network.Connection{}, nic_id}) do
    nic = ComponentQuery.fetch(nic_id)

    {:ok, _} = NetworkAction.Connection.update_nic(nc, nic)

    # Update the NIC custom
    # Note that by default the NIC is assumed to belong to the internet, that's
    # why we'll only update it in case it's on a different network.
    unless nc.network_id == @internet_id do
      ComponentAction.NIC.update_network_id(nic, nc.network_id)
    end
  end
end
