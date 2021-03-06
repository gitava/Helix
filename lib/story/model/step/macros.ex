# credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
defmodule Helix.Story.Model.Step.Macros do
  @moduledoc """
  Macros for the Step DSL.

  You probably don't want to mess with this module directly. Read the Steppable
  documentation instead.
  """

  import HELL.Macros

  alias HELL.Constant
  alias HELL.Utils
  alias Helix.Entity.Model.Entity
  alias Helix.Story.Model.Step
  alias Helix.Story.Action.Story, as: StoryAction

  alias Helix.Story.Event.Reply.Sent, as: StoryReplySentEvent
  alias Helix.Story.Event.Step.ActionRequested, as: StepActionRequestedEvent

  defmacro step(name, contact \\ nil, do: block) do
    quote location: :keep do
      defmodule unquote(name) do
        @moduledoc false

        require Helix.Story.Model.Step

        Helix.Story.Model.Step.register()

        defimpl Helix.Story.Model.Steppable do
          @moduledoc false

          alias Helix.Event

          @emails Module.get_attribute(__MODULE__, :emails) || %{}
          @contact get_contact(unquote(contact), __MODULE__)
          @step_name Helix.Story.Model.Step.get_name(unquote(name))
          @set false

          unquote(block)

          # Most steps do not have a "fail" option. Those who do must manually
          # implement this protocol function.
          @doc false
          def fail(_step),
            do: raise "Undefined fail handler at #{inspect unquote(__MODULE__)}"

          # Catch-all for unhandled events, otherwise any unexpected event would
          # thrown an exception here.
          @doc false
          def handle_event(step, _event, _meta),
            do: {:noop, step, []}

          @doc false
          def format_meta(%{meta: meta}),
            do: meta

          @doc false
          def get_contact(_),
            do: @contact

          # Unlocked replies only
          @doc false
          def get_replies(_step, email_id) do
            case Map.get(@emails, email_id) do
              email = %{} ->
                email.replies
              nil ->
                []
            end
          end

          @spec handle_callback(Step.callback_action, Entity.id) ::
            {:ok, [Event.t]}
          defp handle_callback(action, entity_id) when not is_tuple(action),
            do: handle_callback({action, []}, entity_id)

          @spec handle_callback({Step.callback_action, [Event.t]}, Entity.id) ::
            {:ok, [Event.t]}
          defp handle_callback({action, events}, entity_id) do
            request_action = StepActionRequestedEvent.new(action, entity_id)

            {:ok, events ++ [request_action]}
          end

          @doc false
          callback :callback_complete do
            :complete
          end

          @doc false
          callback :callback_fail do
            :fail
          end

          @doc false
          callback :callback_regenerate do
            :regenerate
          end
        end
      end
    end
  end

  @doc """
  Generates a callback ready to be executed as a response for some element that
  is being listened through `story_listen`.
  """
  defmacro callback(
    name,
    event \\ quote(do: _),
    meta \\ quote(do: _),
    do: block)
  do
    quote do

      def unquote(name)(var!(event) = unquote(event), m = unquote(meta)) do
        step_entity_id = m["step_entity_id"] |> Entity.ID.cast!()

        var!(event)  # Mark as used

        unquote(block)
        |> handle_callback(step_entity_id)
      end

    end
  end

  defmacro story_listen(element_id, events, do: action) do

    quote do
      callback_name = Utils.concat_atom(:callback_, unquote(action))

      story_listen(unquote(element_id), unquote(events), callback_name)
    end

  end

  @doc """
  Executes `callback` when `event` happens over `element_id`.

  It's a wrapper for `Core.Listener`.
  """
  defmacro story_listen(element_id, events, callback) do
    macro = has_macro?(__CALLER__, Helix.Core.Listener)
    import_block = macro && [] ||  quote(do: import Helix.Core.Listener)

    quote do

      unquote(import_block)

      listen unquote(element_id), unquote(events), unquote(callback),
        owner_id: var!(step).entity_id,
        subscriber: @step_name,
        meta: %{step_entity_id: var!(step).entity_id}

    end
  end

  defmacro format_meta(do: block) do
    quote do

      def format_meta(%{meta: empty_map}) when empty_map ==  %{},
        do: %{}

      def format_meta(%{meta: meta}) do
        var!(meta) = HELL.MapUtils.atomize_keys(meta)
        unquote(block)
      end

    end
  end

  defmacro next_step(next_step_module) do
    quote do
      # unless Code.ensure_compiled?(unquote(next_step_module)) do
      #   raise "The step #{inspect unquote(next_step_module)} does not exist"
      # end
      # Verification above is only possible if
      #   1 - We manage to verify on a second round of compilation; OR
      #   2 - We can force the `step_module` to be compiled first; OR
      #   3 - We store each step on a separate file; OR
      #   4 - We sort steps.ex from the last to the first step.
      # I don't want neither 3 or 4. Waiting for a cool hack on 1 or 2.

      @doc """
      Returns the next step module name.
      """
      def next_step(_),
        do: Helix.Story.Model.Step.get_name(unquote(next_step_module))
    end
  end

  defmacro email(email_id, opts \\ []) do
    prev_emails = get_emails(__CALLER__) || %{}
    email = add_email(email_id, opts)

    emails = Map.merge(prev_emails, email)

    set_emails(__CALLER__, emails)
  end

  defmacro send_email(step, email_id, email_meta \\ quote(do: %{})) do
    emails = get_emails(__CALLER__) || %{}

    unless email_exists?(emails, email_id) do
      raise \
        "cant send email #{inspect email_id} on step " <>
        "#{inspect __CALLER__.module}; undefined"
    end

    quote do
      {:ok, events} =
        StoryAction.send_email(
          unquote(step), unquote(email_id), unquote(email_meta)
        )

      events
    end
  end

  @doc """
  Filters any events (handled by StoryHandler), performing the requested action.
  """
  defmacro filter(step, event, meta, opts) do
    quote do

      @doc false
      def handle_event(step = unquote(step), unquote(event), unquote(meta)) do
        unquote(
          case opts do
            [do: block] ->
              block

            [send: email_id] ->
              quote do
                event =
                  send_email \
                    step,
                    unquote(email_id),
                    Keyword.get(unquote(opts), :meta, %{})

                {:noop, step, event}
              end

            :complete ->
              quote do
                {:complete, step, []}
              end

            [fail: true] ->
              quote do
                {:fail, step, []}
              end
          end
        )
      end

    end
  end

  defmacro on_reply(reply_id, opts) do
    # Emails that can receive this reply
    emails = get_emails(__CALLER__)
    valid_emails = get_emails_with_reply(emails, reply_id)

    for email <- valid_emails do
      quote do

        filter(
          step,
          %StoryReplySentEvent{
            reply: %{id: unquote(reply_id)},
            reply_to: unquote(email)
          },
          _,
          unquote(opts)
        )

      end
    end
  end

  @doc """
  Below macro is required so the elixir compiler does not complain about the
  module attribute not being used.
  """
  defmacro contact(contact_name) do
    quote do
      @contact unquote(contact_name)
    end
  end

  @spec get_contact(String.t | Constant.t | nil, module :: term) ::
    contact :: Step.contact
  @doc """
  If the given contact is a string or atom, then the `step` explicitly specified
  a contact. On the other hand, if it's not a string/atom (defaults to `nil`),
  then no contact was specified at the step level. In this case, we'll fall back
  to the contact defined for the mission. This is the most common scenario.
  """
  def get_contact(contact, _) when is_binary(contact),
    do: String.to_atom(contact)
  def get_contact(contact, _) when not is_nil(contact),
    do: contact
  def get_contact(_, step_module) do
    mission_contact =
      step_module
      |> Module.split()
      |> Enum.drop(4)  # Remove protocol namespace
      |> Enum.drop(-1)  # Get parent
      |> Module.concat()
      |> Module.get_attribute(:contact)

    if is_nil(mission_contact),
      do: raise "No contact for top-level mission at #{inspect step_module}"

    get_contact(mission_contact, step_module)
  end

  @spec add_email(Step.email_id, term) ::
    Step.emails
  docp """
  Given an email id and its options, convert it to the internal format defined
  by `Step.emails`, which is a map using `email_id` as lookup key.
  """
  defp add_email(email_id, opts) do
    metadata = %{
      id: email_id,
      replies: Utils.ensure_list(opts[:reply]),
      locked: Utils.ensure_list(opts[:locked])
    }

    Map.put(%{}, email_id, metadata)
  end

  @spec get_emails_with_reply(Step.emails, Step.reply_id) ::
    [Step.email_id]
  docp """
  Helper used to identify all emails that can receive the given `reply_id`.

  It is used to generate the `handle_event` filter by the `on_reply` macro,
  ensuring that only the subset of (emails that expect reply_id) are pattern
  matched against.
  """
  defp get_emails_with_reply(emails, reply_id) do
    Enum.reduce(emails, [], fn {id, email}, acc ->
      cond do
        Enum.member?(email.replies, reply_id) ->
          acc ++ [id]
        Enum.member?(email.locked, reply_id) ->
          acc ++ [id]
        true ->
          acc
      end
    end)
  end

  @spec email_exists?(Step.emails, Step.email_id) ::
    boolean
  docp """
  Helper to check whether the given email has been defined
  """
  defp email_exists?(emails, email_id),
    do: Map.get(emails, email_id, false) && true

  @spec get_emails(Macro.Env.t) ::
    Step.emails
    | nil
  docp """
  Helper to read the module attribute `emails`
  """
  defp get_emails(%Macro.Env{module: module}),
    do: Module.get_attribute(module, :emails)

  @spec set_emails(Macro.Env.t, Step.emails) ::
    :ok
  docp """
  Helper to set the module attribute `emails`
  """
  defp set_emails(%Macro.Env{module: module}, emails),
    do: Module.put_attribute(module, :emails, emails)

  @spec has_macro?(Macro.Env.t, module) ::
    boolean
  docp """
  Helper that checks whether the given module has already been imported
  """
  defp has_macro?(env, macro),
    do: Enum.any?(env.macros, fn {module, _} -> module == macro end)
end
