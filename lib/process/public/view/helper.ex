defmodule Helix.Process.Public.View.Process.Helper do
  @moduledoc """
  Helper functions for `ProcessView` and `ProcessViewable`.
  """

  import HELL.MacroHelpers

  alias Helix.Entity.Model.Entity
  alias Helix.Server.Model.Server
  alias Helix.Process.Model.Process
  alias Helix.Process.Public.View.Process, as: ProcessView

  @spec default_process_render(Process.t, :partial) ::
    ProcessView.partial_process
  @spec default_process_render(Process.t, :full) ::
    ProcessView.full_process
  @doc """
  Most of the time, the process will want to render the default process for both
  `:local` and `:remote` contexts. If that's the case, simply call
  `default_process_render/2` and carry on.
  """
  def default_process_render(process, :partial),
    do: default_process_common(process)
  def default_process_render(process, :full) do
    connection_id = process.connection_id && to_string(process.connection_id)

    %{
      gateway_id: to_string(process.gateway_id),
      connection_id: connection_id,
      state: to_string(process.state),
      allocated: process.allocated,
      priority: process.priority,
      creation_time: to_string(process.creation_time)
    }
    |> Map.merge(default_process_common(process))
  end

  @spec get_default_scope(term, Process.t, Server.id, Entity.id) ::
    ProcessView.scopes
  def get_default_scope(_, %{gateway_id: server}, server, _),
    do: :full
  def get_default_scope(_, %{source_entity_id: entity}, _, entity),
    do: :full
  def get_default_scope(_, _, _, _),
    do: :partial

  @spec default_process_common(Process.t) ::
    partial_process_data :: term
  docp """
  This helper method renders process stuff which is common to both contexts
  (remote and local).
  """
  defp default_process_common(process) do
    file_id = process.file_id && to_string(process.file_id)
    network_id = process.network_id && to_string(process.network_id)

    %{
      process_id: to_string(process.process_id),
      target_server_id: to_string(process.target_server_id),
      file_id: file_id,
      network_id: network_id,
      process_type: to_string(process.process_type)
    }
  end
end