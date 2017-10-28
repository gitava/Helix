defmodule Helix.Test.Process.Data.Setup do
  @moduledoc """
  Attention! If you want integrated data, ensured to exist on all domains,
  use the corresponding `FlowSetup`, like `SoftwareFlowSetup`.

  Data generated here has the correct format, with the correct types, but by
  default generates only fake data.

  It's possible to specify real data with custom opts, but you'd need to ensure
  you've also specified the correct data for the process itself.
  (For instance, a valid FileTransferProcess would need a valid `storage_id`
  passed as data parameter, but also a valid `connection_id` and `file_id`
  passed as parameter for the process itself.)

  This is prone to error and, as such, you should use `*FlowSetup` instead.
  """

  alias Helix.Network.Model.Connection
  alias Helix.Log.Model.Log
  alias Helix.Server.Model.Server
  alias Helix.Software.Model.File
  alias Helix.Software.Model.Storage

  # Processes
  alias Helix.Software.Process.Cracker.Bruteforce, as: CrackerBruteforce
  alias Helix.Software.Model.SoftwareType.LogForge
  alias Helix.Software.Process.File.Transfer, as: FileTransferProcess

  alias HELL.TestHelper.Random
  alias Helix.Test.Log.Helper, as: LogHelper
  alias Helix.Test.Process.Helper.TOP, as: TOPHelper

  @doc """
  Chooses a random implementation and uses it. Beware that `data_opts`, used by
  `custom/3`, is always an empty list when called from `random/1`.
  """
  def random(meta) do
    custom_implementations()
    |> Enum.take_random(1)
    |> List.first()
    |> custom([], meta)
  end

  @doc """
  Opts for file_download:
  - type: Connection type. Either `:download` or `:pftp_download`.
  - storage_id: Set storage_id.
  """
  def custom(:file_download, data_opts, meta) do
    meta =
      if meta.gateway_id == meta.target_server_id do
        %{meta| target_server_id: Server.ID.generate()}
      else
        meta
      end

    connection_id = meta.connection_id || Connection.ID.generate()
    file_id = meta.file_id || File.ID.generate()

    connection_type = Keyword.get(data_opts, :type, :download)
    storage_id = Keyword.get(data_opts, :storage_id, Storage.ID.generate())

    data = %FileTransferProcess{
      type: :download,
      destination_storage_id: storage_id,
      connection_type: connection_type
    }

    meta = %{meta| file_id: file_id, connection_id: connection_id}

    objective =
      TOPHelper.Resources.objective(dlk: 500, network_id: meta.network_id)

    resources =
      %{
        dynamic: [:dlk],
        static: TOPHelper.Resources.random_static(),
        objective: objective
      }

    {:file_download, data, meta, resources}
  end

  @doc """
  Opts for file_upload:
  - storage_id: Set storage_id.
  """
  def custom(:file_upload, data_opts, meta) do
    target_id = meta.gateway_id == meta.target_server_id || Server.ID.generate()
    connection_id = meta.connection_id || Connection.ID.generate()
    file_id = meta.file_id || File.ID.generate()

    storage_id = Keyword.get(data_opts, :storage_id, Storage.ID.generate())

    data = %FileTransferProcess{
      type: :upload,
      destination_storage_id: storage_id,
      connection_type: :ftp
    }

    meta =
      %{meta|
        file_id: file_id,
        connection_id: connection_id,
        target_server_id: target_id
       }

    objective =
      TOPHelper.Resources.objective(ulk: 500, network_id: meta.network_id)

    resources =
      %{
        dynamic: [:ulk],
        objective: objective,
        static: TOPHelper.Resources.random_static()
      }

    {:file_upload, data, meta, resources}
  end

  @doc """
  Opts for bruteforce:
  - target_server_ip: Set target server IP.
  - real_ip: Whether to use the server real IP. Defaults to false.

  All others are automatically derived from process meta data.
  """
  def custom(:bruteforce, data_opts, meta) do
    target_server_ip =
      cond do
        data_opts[:target_server_ip] ->
          data_opts[:target_server_ip]
        data_opts[:real_ip] ->
          raise "todo"
        true ->
          Random.ipv4()
      end

    data = CrackerBruteforce.new(%{target_server_ip: target_server_ip})

    resources =
      %{
        dynamic: [:cpu],
        static: TOPHelper.Resources.random_static(),
        objective: TOPHelper.Resources.objective(cpu: 500)
      }

    {:cracker_bruteforce, data, meta, resources}
  end

  @doc """
  Opts for forge:
  - operation: :edit | :create. Defaults to :edit.
  - target_log_id: Which log to edit. Won't generate a real one.
  - message: Revision message.
  
  All others are automatically derived from process meta data.
  """
  def custom(:forge, data_opts, meta) do
    target_server_id = meta.target_server_id
    target_log_id = Keyword.get(data_opts, :target_log_id, Log.ID.generate())
    entity_id = meta.source_entity_id
    operation = Keyword.get(data_opts, :operation, :edit)
    message = LogHelper.random_message()
    version = 100

    data =
      %LogForge{
        target_server_id: target_server_id,
        entity_id: entity_id,
        operation: operation,
        message: message,
        version: version
      }

    data =
      if operation == :edit do
        Map.merge(data, %{target_log_id: target_log_id})
      else
        data
      end

    resources =
      %{
        dynamic: [:cpu],
        static: TOPHelper.Resources.random_static(),
        objective: TOPHelper.Resources.objective(cpu: 500)
      }

    {:log_forger, data, meta, resources}
  end

  defp custom_implementations do
    ~w/
      bruteforce
      forge
      file_download
    /a
  end
end
