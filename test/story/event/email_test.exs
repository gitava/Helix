defmodule Helix.Story.Event.EmailTest do

  use Helix.Test.Case.Integration

  alias Helix.Event.Notificable

  alias Helix.Test.Channel.Setup, as: ChannelSetup
  alias Helix.Test.Event.Setup, as: EventSetup

  describe "Notificable.whom_to_notify/1" do
    test "notifies only the player" do
      event = EventSetup.Story.email_sent()

      notify = Notificable.whom_to_notify(event)
      assert notify == %{account: event.entity_id}
    end
  end

  describe "Notificable.generate_payload/2" do
    test "generates the payload" do
      socket = ChannelSetup.mock_account_socket()

      event = EventSetup.Story.email_sent()

      assert {:ok, data} = Notificable.generate_payload(event, socket)

      assert data.step == to_string(event.step.name)
      assert data.email_id == event.email.id
      assert is_binary(data.contact_id)
      assert data.meta
      assert data.replies
      assert is_float(data.timestamp)

      assert "story_email_sent" == Notificable.get_event_name(event)
    end
  end
end
