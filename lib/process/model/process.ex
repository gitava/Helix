defmodule Helix.Process.Model.Process do
  @moduledoc """
  The Process model is responsible for persisting all in-game processes.

  Compared to other models within the Process service, this model is quite
  simple and straightforward. Other than the usual model responsibilities (like
  ensuring the data is stored correctly and providing ways to query the data),
  it plays a major role when formatting the process before giving it back to
  whoever asked for it.
  """

  use Ecto.Schema
  use HELL.ID, field: :process_id, meta: [0x0021]

  import Ecto.Changeset
  import HELL.Macros

  alias Ecto.Changeset
  alias HELL.Constant
  alias HELL.MapUtils
  alias HELL.NaiveStruct
  alias Helix.Entity.Model.Entity
  alias Helix.Network.Model.Connection
  alias Helix.Network.Model.Network
  alias Helix.Server.Model.Server
  alias Helix.Software.Model.File
  alias Helix.Process.Model.Processable
  alias Helix.Process.Model.TOP
  alias __MODULE__, as: Process

  @type t ::
    %__MODULE__{
      process_id: id,
      gateway_id: Server.id,
      source_entity_id: Entity.id,
      target_id: Server.id,
      file_id: File.id | nil,
      connection_id: Connection.id | nil,
      network_id: Network.id | nil,
      data: term,
      type: type,
      priority: term,
      l_allocated: Process.Resources.t | nil,
      r_allocated: Process.Resources.t | nil,
      r_limit: limit,
      l_limit: limit,
      l_reserved: Process.Resources.t,
      r_reserved: Process.Resources.t,
      last_checkpoint_time: DateTime.t,
      static: static,
      l_dynamic: dynamic,
      r_dynamic: dynamic,
      local?: boolean | nil,
      next_allocation: Process.Resources.t | nil,
      state: state | nil,
      creation_time: DateTime.t,
      time_left: non_neg_integer | nil,
      completion_date: DateTime.t | nil
    }

  @typep limit :: Process.Resources.t | %{}

  @type type ::
    :file_upload
    | :file_download
    | :cracker_bruteforce
    | :cracker_overflow

  @typedoc """
  List of signals a process may receive during its lifetime.

  # Process lifecycle signals

  The processes below are related to the lifecycle of a process.

  ## SIGTERM

  Process reached its objective. Handled by Processable's `on_completion`.
  This callback must be implemented by the process.

  Note that, despite the name, it has no similarities with UNIX's SIGTERM.

  Most common action is to `:delete` the process. `:find_next_target` is also a
  valid option, depending on the Process behaviour.

  ## SIGKILL

  Signal sent when the process was asked to terminate. Must be accompanied by a
  `kill_reason`. Note that when a process is completed, it is killed with reason
  `:completed`.

  Default action is to delete the process.

  ## SIGSTOP

  Signal sent when the user requested the process to be paused.

  Default action is to pause the process.

  ## SIGCONT

  Signal sent when the user requested the process to be resumed.

  Default action is to resume the process.

  ## SIGPRIO

  Signal sent when the user changed the priority of the process.

  Default action is to `:renice`, i.e. change the process' priority.

  # Object-related signals

  The signals below are meant to notify the process that one of the objects the
  process is using or modifying has changed.

  Note that these signals are NOT sent to the process that originated them. See
  `TOPHandler.filter_self_message/2` for context.

  ## SIGCONND

  Signal sent when the Process underlying `connection_id` was closed.

  Default action is to send itself a SIGKILL with `:connection_closed` reason.

  ## SIGFILED

  Signal sent when the Process underlying `file_id` was deleted.

  Default action is to send itself a SIGKILL with `:file_deleted` reason.
  """
  @type signal ::
    :SIGTERM
    | :SIGKILL
    | :SIGSTOP
    | :SIGCONT
    | :SIGPRIO
    | :SIGCONND
    | :SIGFILED

  @typedoc """
  Valid params for each type of signal.
  """
  @type signal_params ::
    %{reason: kill_reason}
    | %{priority: term}
    | %{connection: Connection.t}
    | %{file: File.t}

  @typedoc """
  Valid reasons for which a Process may be killed.
  """
  @type kill_reason ::
    :completed
    | :killed
    | :connection_closed
    | :file_deleted

  @type changeset :: %Changeset{data: %__MODULE__{}}

  @type creation_params :: %{
    :gateway_id => Server.id,
    :source_entity_id => Entity.id,
    :target_id => Server.id,
    :data => Processable.t,
    :type => type,
    :network_id => Network.id | nil,
    :file_id => File.id | nil,
    :connection_id => Connection.id | nil,
    :objective => map,
    :l_dynamic => dynamic,
    :r_dynamic => dynamic,
    :static => static,
  }

  @creation_fields [
    :gateway_id,
    :source_entity_id,
    :target_id,
    :file_id,
    :network_id,
    :connection_id,
    :data,
    :type,
    :objective,
    :static,
    :l_dynamic,
    :r_dynamic,
    :l_limit,
    :r_limit
  ]

  @required_fields [
    :gateway_id,
    :source_entity_id,
    :target_id,
    :data,
    :type,
    :objective,
    :static,
    :priority,
    :l_dynamic,
    :priority
  ]

  @type state ::
    :waiting_allocation
    | :running
    | :paused

  @type time_left :: float

  @type resource :: Process.Resources.resource

  @type dynamic :: [resource]

  @type static ::
    %{
      paused: static_usage,
      running: static_usage
    }
    | %{}

  @typep static_usage ::
    %{
      cpu: number,
      ram: number,
      dlk: number,
      ulk: number
    }
    | %{}

  # Similar to `task_struct` on `sched.h` ;-)
  @primary_key false
  schema "processes" do
    field :process_id, ID,
      primary_key: true

    ### Identifiers

    # The gateway that started the process
    field :gateway_id, Server.ID

    # The entity that started the process
    field :source_entity_id, Entity.ID

    # The server where the target object of this process action is
    field :target_id, Server.ID

    ### Custom keys

    # Which file (if any) is the relevant target of this process
    field :file_id, File.ID

    # Which network (if any) is this process bound to
    field :network_id, Network.ID

    # Which connection (if any) is the transport method for this process
    field :connection_id, Connection.ID

    ### Helix.Process required data

    # Data used by the specific implementation for side-effects generation
    field :data, NaiveStruct

    # The process type identifier
    field :type, Constant

    # Process priority.
    field :priority, :integer,
      default: 3

    ### Resource usage information

    # Amount of resources required in order to consider the process completed.
    field :objective, :map

    # Amount of resources that this process has already processed.
    field :processed, :map

    # Amount of resources that this process has allocated to it
    field :l_allocated, :map,
      virtual: true
    field :r_allocated, :map,
      virtual: true

    # Limitations
    field :r_limit, :map,
      default: %{}
    field :l_limit, :map,
      default: %{}

    field :l_reserved, :map,
      default: %{}
    field :r_reserved, :map,
      default: %{}

    # Date when the process was last simulated during a `TOPAction.recalque/2`
    field :last_checkpoint_time, :utc_datetime

    # Static amount of resources used by the process
    field :static, :map

    # List of dynamically allocated resources
    field :l_dynamic, {:array, Constant}
    field :r_dynamic, {:array, Constant},
      default: []

    ### Metadata

    # Used internally by Allocator to identify whether the process is local (it
    # was started on this server) or remote (started somewhere else, and targets
    # the current server).
    field :local?, :boolean,
      virtual: true

    # Used by the Scheduler to accurately forecast the process, taking into
    # consideration both the current allocation (`allocated`) and the next
    # allocation, as defined by the Allocator.
    field :next_allocation, :map,
      virtual: true

    # Process state (`:running`, `:stopped`). Used internally for an easier
    # abstraction over `priority` (which is used to define the process state)
    field :state, Constant,
      virtual: true

    field :creation_time, :utc_datetime

    # Estimated time left for completion of the process. Seconds.
    field :time_left, :float,
      virtual: true

    # Estimated progress percentage (resources processed / total objective)
    field :percentage, :float,
      virtual: true,
      default: 0.0

    # Estimated completion date for the process.
    field :completion_date, :utc_datetime,
      virtual: true
  end

  @spec create_changeset(creation_params) ::
    changeset
  @doc """
  Creates the changeset of a process, casting the expected fields and putting
  the defaults (like creation time).

  This is the moment a process is born.
  """
  def create_changeset(params) do
    %__MODULE__{}
    |> cast(params, @creation_fields)
    |> validate_required(@required_fields)
    |> put_defaults()
  end

  @spec format(raw_process :: t) ::
    t
  @doc """
  Converts the retrieved process from the Database into TOP's internal format.
  Notably, it:

  - Adds virtual data (derived data not stored on DB).
  - Converts the Processable (defined at `process_data`) into Helix internal
  format, by using the `after_read_hook/1` implemented by each Processable
  - Converts all resources (objective, limit, reserved etc) into Helix format.
  - Infers the actual process usage, based on what was reserved for it.
  - Estimates the completion date and time left
  """
  def format(process = %Process{}) do
    formatted_data = Processable.after_read_hook(process.data)

    process
    |> Map.replace(:state, get_state(process))
    |> Map.replace(:data, formatted_data)
    |> format_resources()
    |> infer_usage()
    |> estimate_duration()
  end

  @spec get_dynamic(t) ::
    [resource]
  @doc """
  Context-aware getter for the list of resources the process is supposed to
  allocate dynamically.
  """
  def get_dynamic(%{local?: true, l_dynamic: dynamic}),
    do: dynamic
  def get_dynamic(%{local?: false, r_dynamic: dynamic}),
    do: dynamic

  @spec get_limit(t) ::
    limit
  @doc """
  Context-aware getter for the limits of a process' resource consumption.
  """
  def get_limit(%{local?: true, l_limit: limit}),
    do: limit
  def get_limit(%{local?: false, r_limit: limit}),
    do: limit

  @spec get_last_update(t) ::
    DateTime.t
  @doc """
  Returns the last time the process was updated. It may be either the creation
  time or the `last_checkpoint_time`, whichever came first.
  """
  def get_last_update(p = %{last_checkpoint_time: nil}),
    do: p.creation_time
  def get_last_update(%{last_checkpoint_time: last_checkpoint_time}),
    do: last_checkpoint_time

  @spec infer_usage(t) ::
    t
  @doc """
  Based on what resources the process can allocate locally and remotely, and
  considering its limitations, infer the actual amount of resources the process
  will allocate, both locally and remotely.

  Mind you, this function is where all the hard work of the TOP, Scheduler and
  Allocator yields its final result: how many resources a process has allocated
  to itself.
  """
  def infer_usage(process) do
    l_alloc = Process.Resources.min(process.l_limit, process.l_reserved)
    r_alloc = Process.Resources.min(process.r_limit, process.r_reserved)

    {l_alloc, r_alloc} =
      # Assumes that, if remote allocation was not defined, then the process is
      # oblivious to the remote server's resources
      if r_alloc == %{} do
        {l_alloc, Process.Resources.initial()}

      # On the other hand, if there are remote allocations/limitations, we'll
      # immediately mirror its resources and potentially limit the local
      # allocation
      else
        mirrored_transfer_resources =
          r_alloc
          |> Process.Resources.mirror()
          |> Map.drop([:cpu, :ram])

        l_alloc = Process.Resources.min(mirrored_transfer_resources, l_alloc)

        {l_alloc, r_alloc}
      end

    %{process|
      l_allocated: l_alloc |> Process.Resources.prepare(),
      r_allocated: r_alloc |> Process.Resources.prepare()
    }
  end

  @spec estimate_duration(t) ::
    t
  defp estimate_duration(process = %Process{}) do
    {simulated_process, time_left} = TOP.Scheduler.estimate_completion(process)

    percentage = estimate_percentage(simulated_process)

    completion_date =
      if time_left == :infinity do
        nil
      else
        previous_update = get_last_update(process)

        ms_left =
          time_left
          |> Kernel.*(1000)  # From second to millisecond
          |> trunc()

        previous_update
        |> DateTime.to_unix(:millisecond)
        |> Kernel.+(ms_left)
        |> DateTime.from_unix!(:millisecond)
      end

    process
    |> Map.replace(:completion_date, completion_date)
    |> Map.replace(:time_left, time_left)
    |> Map.replace(:percentage, percentage)
  end

  docp """
  First line divides the total objective by the amount processed. This is pretty
  much all we need to estimate the percentage.... HOWEVER, we need to ignore
  resources that are not used, and the remainder (pun intended) of this function
  is meant to filter out unwanted data. Plus, in case there are multiple
  resources allocated, it chooses the one that have the least progress so far.
  """
  defp estimate_percentage(process = %Process{}) do
    elapsed_percentage =
      Process.Resources.div(process.processed, process.objective)

    # Returns all resources that have some objective. Filters out resources that
    # are not required in order to complete the process
    objectives =
      process.objective
      |> Process.Resources.map(&(&1 > 0))
      |> Enum.reject(fn {_res, val} -> val == false || val == %{} end)
      |> Enum.reduce([], fn {res, _}, acc -> acc ++ [res] end)

    # For each resource that is part of the objective, get the corresponding
    # div result (first line of this function). If the result is higher than 0,
    # it means the `processed` is empty and the `objective` got merged during
    # the division. This is actually a bug, but one we've chosen to live with.
    objectives
    |> Enum.reduce([], fn res, acc ->
      # Ensures we are returning the actual progress; NOT the merged objective
      filter_merged = fn _, v -> (v == 0.0 || v > 1) && 0.0 || v end

      elapsed =
        Process.Resources.call(
          res, elapsed_percentage[res], :reduce, [0, filter_merged]
        )

      acc ++ [elapsed]
    end)
    |> Enum.sort()
    |> List.first()
  end

  @spec format_resources(t) ::
    t
  defp format_resources(process = %Process{}) do
    process
    |> format_objective()
    |> format_processed()
    |> format_static()
    |> format_limits()
    |> format_reserved()
  end

  @spec format_objective(t) ::
    t
  defp format_objective(p = %{objective: objective}),
    do: %{p| objective: Process.Resources.format(objective)}

  @spec format_processed(t) ::
    t
  defp format_processed(p = %{processed: nil}),
    do: p
  defp format_processed(p = %{processed: processed}),
    do: %{p| processed: Process.Resources.format(processed)}

  @spec format_static(t) ::
    t
  defp format_static(p = %{static: static}) do
    static = MapUtils.atomize_keys(static)

    %{p| static: static}
  end

  @spec format_limits(t) ::
    t
  defp format_limits(p) do
    l_limit =
      p.l_limit
      |> Process.Resources.format()
      |> Process.Resources.reject_empty()

    r_limit =
      p.r_limit
      |> Process.Resources.format()
      |> Process.Resources.reject_empty()

    %{p|
      l_limit: l_limit,
      r_limit: r_limit
    }
  end

  @spec format_reserved(t) ::
    t
  defp format_reserved(p) do
    %{p|
      l_reserved: Process.Resources.format(p.l_reserved),
      r_reserved: Process.Resources.format(p.r_reserved)
    }
  end

  @spec get_state(t) ::
    state
  defp get_state(%{priority: 0}),
    do: :paused
  defp get_state(process) do
    if process.l_reserved == %{} do
      :waiting_allocation
    else
      :running
    end
  end

  @spec put_defaults(changeset) ::
    changeset
  defp put_defaults(changeset) do
    changeset
    |> put_change(:creation_time, DateTime.utc_now())
  end

  defmodule Query do

    import Ecto.Query

    alias Ecto.Queryable
    alias Helix.Software.Model.File
    alias Helix.Network.Model.Connection
    alias Helix.Network.Model.Network
    alias Helix.Server.Model.Server
    alias Helix.Process.Model.Process

    @spec by_id(Queryable.t, Process.idtb) ::
      Queryable.t
    def by_id(query \\ Process, id),
      do: where(query, [p], p.process_id == ^id)

    @spec on_server(Queryable.t, Server.idt) ::
      Queryable.t
    def on_server(query \\ Process, server_id) do
      query
      |> where([p], p.gateway_id == ^server_id)
      |> or_where([p], p.target_id == ^server_id)
    end

    @spec by_gateway(Queryable.t, Server.idtb) ::
      Queryable.t
    def by_gateway(query \\ Process, id),
      do: where(query, [p], p.gateway_id == ^id)

    @spec by_target(Queryable.t, Server.idtb) ::
      Queryable.t
    def by_target(query \\ Process, id),
      do: where(query, [p], p.target_id == ^id)

    @spec by_file(Queryable.t, File.idtb) ::
      Queryable.t
    def by_file(query \\ Process, id),
      do: where(query, [p], p.file_id == ^id)

    @spec by_network(Queryable.t, Network.idtb) ::
      Queryable.t
    def by_network(query \\ Process, id),
      do: where(query, [p], p.network_id == ^id)

    @spec by_connection(Queryable.t, Connection.id) ::
      Queryable.t
    def by_connection(query \\ Process, id),
      do: where(query, [p], p.connection_id == ^id)

    @spec by_type(Queryable.t, Process.type) ::
      Queryable.t
    def by_type(query \\ Process, type),
      do: where(query, [p], p.type == ^type)

    @spec by_state(Queryable.t, :running | :paused) ::
      Queryable.t
    def by_state(query, :running),
      do: where(query, [p], p.priority > 1)
    def by_state(query, :paused),
      do: where(query, [p], p.priority == 0)
  end
end
