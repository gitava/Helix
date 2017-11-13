defmodule Helix.Test.Story.Setup do

  alias Helix.Entity.Model.Entity
  alias Helix.Story.Action.Story, as: StoryAction
  alias Helix.Story.Internal.Email, as: EmailInternal
  alias Helix.Story.Internal.Step, as: StepInternal
  alias Helix.Story.Model.Step
  alias Helix.Story.Model.Steppable
  alias Helix.Story.Model.StoryEmail
  alias Helix.Story.Model.StoryStep
  alias Helix.Story.Repo, as: StoryRepo

  alias HELL.TestHelper.Random
  alias Helix.Test.Story.StepHelper, as: StoryStepHelper

  @doc """
  - entity_id - Fake entity ID is generated by default
  - name - Must be used with `meta`. Defaults to random step from FakeStep
  - meta - Must be used with `name`. Defaults to random step from FakeStep

  Related: Entity.id
  """
  def step(opts \\ []) do
    {name, meta} =
      if is_nil(opts[:name]) and is_nil(opts[:meta]) do
        %{name: name, meta: meta} = StoryStepHelper.random_step()
        {name, meta}
      else
        opts[:name] && opts[:meta]
        && {opts[:name], opts[:meta]}
        || raise "You need to specify either both `name` and `meta`, or none"
      end

    entity_id = Keyword.get(opts, :entity_id, Entity.ID.generate())

    step = Step.fetch(name, entity_id, meta)

    related = %{
      entity_id: entity_id
    }

    {step, related}
  end

  @doc """
  See doc on `fake_story_step/1`
  """
  def story_step(opts \\ []) do
    {_, related = %{step: step}} = fake_story_step(opts)

    # Save the step on DB and run its `setup`
    {:ok, _} = StoryAction.proceed_step(step)
    {:ok, _, _} = Steppable.setup(step, %{})

    %{entry: inserted} = StepInternal.fetch_current_step(step.entity_id)
    {inserted, related}
  end

  @doc """
  Opts:
  - entity_id. Fake entity ID is generated by default.
  - name - Must be used with `meta`. Defaults to random step from FakeStep
  - meta - Must be used with `name`. Defaults to random step from FakeStep
  - emails_sent - Defaults to none
  - allowed_replies - Defaults to none

  Related: Entity.id, (Step.t(struct) if given step name is valid)
  """
  def fake_story_step(opts \\ []) do
    {name, meta} =
      if is_nil(opts[:name]) and is_nil(opts[:meta]) do
        %{name: name, meta: meta} = StoryStepHelper.random_step()
        {name, meta}
      else
        opts[:name] && opts[:meta]
        && {opts[:name], opts[:meta]}
        || raise "You need to specify either both `name` and `meta`, or none"
      end

    entity_id = Keyword.get(opts, :entity_id, Entity.ID.generate())

    emails_sent = Keyword.get(opts, :emails_sent, [])
    allowed_replies = Keyword.get(opts, :allowed_replies, [])

    story_step =
      %StoryStep{
        entity_id: entity_id,
        step_name: name,
        meta: meta,
        emails_sent: emails_sent,
        allowed_replies: allowed_replies
      }

    step = Step.fetch(name, entity_id, meta)

    related = %{
      step: step,
      entity_id: entity_id
    }

    {story_step, related}
  end

  @doc """
  Opts:

  - entity_id: Set the steps' entity_id. Defaults to a fake generated ID.

  {prev_step :: Step.t, next_step :: Step.t, Related (Entity.id)}
  """
  def step_sequence(opts \\ []) do
    entity = Keyword.get(opts, :entity_id, Entity.ID.generate())

    {prev_step, _} =
      step(name: :fake_steps@test_one, meta: %{step: :one}, entity_id: entity)

    {next_step, _} =
      step(name: :fake_steps@test_two, meta: %{step: :two}, entity_id: entity)

    # Add `entity_id` to the current step (`prev_step`)
    {:ok, _} = StepInternal.proceed(prev_step)

    related = %{
      entity_id: entity
    }

    {prev_step, next_step, related}
  end

  @doc """
  See doc on `fake_story_email/1`
  """
  def story_email(opts \\ []) do
    {entry, related} = fake_story_email(opts)
    {:ok, inserted} = StoryRepo.insert(entry)
    {inserted, related}
  end

  @doc """
  Opts:

  - entity_id: Set entity id. Defaults to a fake generated id.
  - contact_id: Set contact id. Defaults to the one from FakeSteps mission
  - email: Specify list of emails to be saved. Defaults to list of size 1. Use
    `emails/1` to generate a valid list, or `email/1` to generate a single one.
  - email_total: Specify number of emails to be created. Defaults to 1.
 
  Related: %{}
  """
  def fake_story_email(opts \\ []) do
    entity_id = Keyword.get(opts, :entity_id, Entity.ID.generate())
    contact_id = Keyword.get(opts, :contact_id, StoryStepHelper.get_contact())
    email_total = Keyword.get(opts, :email_total, 1)
    emails = Keyword.get(opts, :emails, fake_emails(total: email_total))

    entry =
      %StoryEmail{
        entity_id: entity_id,
        contact_id: contact_id,
        emails: emails
      }

    {entry, %{}}
  end

  @doc """
  Opts:

  - total: Specify total of emails to be generated. Defaults to 4.
  """
  def fake_emails(opts \\ []) do
    total = Keyword.get(opts, :total, 4)

    1..total
    |> Enum.map(fn _ -> fake_email!() end)
  end

  @doc """
  Ignores related. See doc on `email/1`
  """
  def fake_email!(opts \\ []) do
    {email, _} = fake_email(opts)
    email
  end

  @doc """
  - id: Specify email id. Defaults to random string.
  - meta: Specify email meta. Defaults to empty map.
  - sender: Specify email sender. Must be either `:player` or `:contact`.
    Defaults to any of the two.
  - timestamp: Specify timestamp. Defaults to "now".

  Related: %{}
  """
  def fake_email(opts \\ []) do
    id = Keyword.get(opts, :id, Random.string(min: 4, max: 8))
    meta = Keyword.get(opts, :meta, %{})
    sender = Keyword.get(opts, :sender, Enum.random([:player, :contact]))
    timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now())

    email =
      %{
        id: id,
        meta: meta,
        sender: sender,
        timestamp: timestamp
      }

    {email, %{}}
  end

  @doc """
  Related: Step.t(struct), Entity.id, contact_id :: Step.contact, Step.email_id
  """
  def send_email(_opts \\ []) do
    {step, %{entity_id: entity_id}} = step()

    email_id = Random.string(min: 4, max: 8)
    email_meta = %{}

    {:ok, story_email, _} = EmailInternal.send_email(step, email_id, email_meta)

    related = %{
      step: step,
      email_id: email_id,
      entity_id: entity_id,
      contact_id: story_email.contact_id
    }

    {story_email, related}
  end

  @doc """
  Opts:

  - entity_id: Specify entity id

  Related: Entity.id, [Step.contact], [StoryEmail.email]
  """
  def lots_of_emails_and_contacts(opts \\ []) do
    entity = Keyword.get(opts, :entity_id, Entity.ID.generate())

    c1 = :contact_1
    c2 = :contact_2
    c3 = :contact_3

    c1_emails = fake_emails(total: 5)
    c2_emails = fake_emails(total: 3)
    c3_emails = fake_emails(total: 1)

    {e1, _} = story_email(entity_id: entity, contact_id: c1, emails: c1_emails)
    {e2, _} = story_email(entity_id: entity, contact_id: c2, emails: c2_emails)
    {e3, _} = story_email(entity_id: entity, contact_id: c3, emails: c3_emails)

    related = %{
      entity_id: entity,
      contacts: [c1, c2, c3],
      emails: [c1_emails, c2_emails, c3_emails]
    }

    formatted_output =
      [e1, e2, e3]
      |> Enum.map(&sort_emails/1)

    {formatted_output, related}
  end

  defp sort_emails(entry) do
    emails =
      entry.emails
      |> Enum.sort(&(&2.timestamp >= &1.timestamp))

    %{entry| emails: emails}
  end
end
