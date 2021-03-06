# TODO: This whole module needs to be rewritten with the new Process interface.
defmodule Helix.Software.Model.SoftwareType.LogForge do

  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Changeset
  alias HELL.Constant
  alias Helix.Entity.Model.Entity
  alias Helix.Log.Model.Log
  alias Helix.Server.Model.Server
  alias Helix.Software.Model.File

  # TODO: Remove `entity_id` and `version` when `Balance` module is implemented
  @type t :: %__MODULE__{
    target_log_id: Log.id | nil,
    target_id: Server.id | nil,
    entity_id: Entity.id,
    operation: :edit | :create,
    message: String.t,
    version: pos_integer
  }

  @type create_params ::
    %{
      :entity_id => Entity.idtb,
      :operation => :edit | :create,
      :message => String.t,
      optional(:target_id) => Server.idtb,
      optional(:target_log_id) => Log.idtb,
      optional(atom) => any
    }

  @edit_revision_cost 10_000
  @edit_version_cost 150
  @create_version_cost 400

  @primary_key false
  embedded_schema do
    field :target_log_id, Log.ID
    field :entity_id, Entity.ID
    field :target_id, Server.ID

    field :operation, Constant

    field :message, :string
    field :version, :integer
  end

  @spec create(File.t, create_params) ::
    {:ok, t}
    | {:error, Changeset.t}
  def create(file, params) do
    %__MODULE__{}
    |> cast(params, [:entity_id, :operation, :message])
    |> validate_required([:entity_id, :operation])
    |> validate_inclusion(:operation, [:edit, :create])
    |> cast_modules(file, params)
    |> format_return()
  end

  @spec edit_objective(t, Log.t, non_neg_integer) ::
    %{cpu: pos_integer}
  def edit_objective(data = %{operation: :edit}, target_log, revision_count) do
    revision_cost = if data.entity_id == target_log.entity_id do
      factorial(revision_count) * @edit_revision_cost
    else
      factorial(revision_count + 1) * @edit_revision_cost
    end

    version_cost = data.version * @edit_version_cost

    %{cpu: revision_cost + version_cost}
  end

  @spec create_objective(t) ::
    %{cpu: pos_integer}
  def create_objective(data = %{operation: :create}) do
    %{cpu: data.version * @create_version_cost}
  end

  @spec cast_modules(Changeset.t, File.t, create_params) ::
    Changeset.t
  defp cast_modules(changeset, file, params) do
    case get_change(changeset, :operation) do
      :create ->
        changeset
        |> cast(%{version: file.modules.log_create.version}, [:version])
        |> cast(params, [:target_id])
        |> validate_required([:target_id, :version])
        |> validate_number(:version, greater_than: 0)
      :edit ->
        changeset
        |> cast(%{version: file.modules.log_edit.version}, [:version])
        |> cast(params, [:target_log_id])
        |> validate_required([:target_log_id, :version])
        |> validate_number(:version, greater_than: 0)
      _ ->
        # Changeset should already be invalid
        changeset
    end
  end

  @spec format_return(Changeset.t) ::
    {:ok, t}
    | {:error, Changeset.t}
  defp format_return(changeset = %{valid?: true}),
    do: {:ok, apply_changes(changeset)}
  defp format_return(changeset),
    do: {:error, changeset}

  @spec factorial(non_neg_integer) ::
    non_neg_integer
  defp factorial(n),
    do: Enum.reduce(1..n, &(&1 * &2))

  defimpl Helix.Process.Model.Processable do

    alias Ecto.Changeset
    alias Helix.Entity.Model.Entity
    alias Helix.Log.Model.Log
    alias Helix.Server.Model.Server
    alias Helix.Software.Model.SoftwareType.LogForge, as: LogForgeProcess
    alias Helix.Software.Event.LogForge.LogEdit.Processed,
      as: LogEditProcessedEvent
    alias Helix.Software.Event.LogForge.LogCreate.Processed,
      as: LogCreateProcessedEvent

    @ram_base_factor 5
    @ram_sqrt_factor 50

    def dynamic_resources(_),
      do: [:cpu]

    def minimum(%{version: v}),
      do: %{
        paused: %{
          ram: v * @ram_base_factor + trunc(:math.sqrt(v) * @ram_sqrt_factor)
        },
        running: %{
          ram: v * @ram_base_factor + trunc(:math.sqrt(v) * @ram_sqrt_factor)
        }
    }

    def kill(_, _, _),
      do: {:delete, []}

    def complete(data, _process) do
      event = conclusion_event(data)

      {:delete, [event]}
    end

    def connection_closed(_, _, _) do
      {:delete, []}
    end

    def state_change(_, process, _, _),
      do: {process, []}

    def conclusion(data, process),
      do: state_change(data, process, :running, :complete)

    defp conclusion_event(data = %{operation: :edit}),
      do: LogEditProcessedEvent.new(data)

    defp conclusion_event(data = %{operation: :create}),
      do: LogCreateProcessedEvent.new(data)

    def after_read_hook(data) do
      target_log_id = data.target_log_id && Log.ID.cast!(data.target_log_id)

      %LogForgeProcess{
        entity_id: Entity.ID.cast!(data.entity_id),
        target_log_id: target_log_id,
        target_id: Server.ID.cast!(data.target_id),
        operation: String.to_existing_atom(data.operation),
        message: data.message,
        version: data.version
      }
    end
  end

  defimpl Helix.Process.Public.View.ProcessViewable do

    alias Helix.Log.Model.Log
    alias Helix.Process.Model.Process
    alias Helix.Process.Public.View.Process, as: ProcessView
    alias Helix.Process.Public.View.Process.Helper, as: ProcessViewHelper

    @type data ::
      %{
        optional(:target_log_id) => String.t
      }

    def get_scope(data, process, server, entity),
      do: ProcessViewHelper.get_default_scope(data, process, server, entity)

    @spec render(term, Process.t, ProcessView.scopes) ::
      {ProcessView.full_process | ProcessView.partial_process, data}
    def render(data, process, scope) do
      base = take_data_from_process(process, scope)
      complement = take_complement_from_data(data, scope)

      {base, complement}
    end

    defp take_complement_from_data(data = %_{operation: :edit}, _),
      do: %{target_log_id: to_string(data.target_log_id)}
    defp take_complement_from_data(%_{operation: :create}, _),
      do: %{}

    defp take_data_from_process(process, scope),
      do: ProcessViewHelper.default_process_render(process, scope)
  end
end
