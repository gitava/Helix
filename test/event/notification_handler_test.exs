defmodule Helix.Event.NotificationHandlerTest do

  use Helix.Test.Case.Integration

  import Phoenix.ChannelTest
  import Helix.Test.Case.ID
  import Helix.Test.Event.Macros

  alias Helix.Process.Query.Process, as: ProcessQuery

  alias Helix.Test.Channel.Setup, as: ChannelSetup
  alias Helix.Test.Process.TOPHelper
  alias Helix.Test.Server.Helper, as: ServerHelper
  alias Helix.Test.Server.Setup, as: ServerSetup
  alias Helix.Test.Software.Setup, as: SoftwareSetup
  alias Helix.Test.Event.Helper, as: EventHelper
  alias Helix.Test.Event.Setup, as: EventSetup

  @moduletag :driver

  # Behold, adventurer! The tests below are meant to ensure
  # `notification_handler/1` works correctly under the hood, as well as Phoenix
  # behavior of intercepting and filtering out an event.
  # It is not mean to extensively test all events. For this, refer to the
  # specific event's test file.
  # As such, we use `ProcessCreatedEvent` here merely as an example. Peace.
  describe "notification_handler/1" do
    test "notifies gateway that a process was created (single-server)" do
      {_socket, %{gateway: gateway}} =
        ChannelSetup.join_server([own_server: true])

      event = EventSetup.Process.created(gateway.server_id)

      # Process happens on the same server
      assert event.gateway_id == event.target_id

      EventHelper.emit(event)

      # Broadcast is before inspecting the event with `handle_out`, so this
      # isn't the final output to the client
      assert_broadcast "event", internal_broadcast
      assert_event internal_broadcast, event

      # Now that's what the client actually receives.
      assert_push "event", notification
      assert notification.event == "process_created"

      # Make sure all we need is on the process return
      assert_id notification.data.process_id, event.process.process_id
      assert notification.data.type == event.process.type |> to_string()
      assert_id notification.data.file_id, event.process.file_id
      assert_id notification.data.connection_id, event.process.connection_id
      assert_id notification.data.network_id, event.process.network_id
      assert notification.data.target_ip
      assert notification.data.source_ip

      # Event id was generated
      assert notification.meta.event_id
      assert is_binary(notification.meta.event_id)

      # No process ID
      refute notification.meta.process_id
    end

    test "multi-server" do
      {socket, %{gateway: gateway, destination: destination}} =
        ChannelSetup.join_server()

      # Filter out the usual `LogCreatedEvent` after remote server join
      assert_broadcast "event", _

      gateway_entity_id = socket.assigns.gateway.entity_id
      destination_entity_id = socket.assigns.destination.entity_id

      event =
        EventSetup.Process.created(gateway.server_id, destination.server_id)

      # Process happens on two different servers
      refute event.gateway_id == event.target_id

      EventHelper.emit(event)

      # Broadcast is before inspecting the event with `handle_out`, so this
      # isn't the final output to the client
      assert_broadcast "event", internal_broadcast
      assert_event internal_broadcast, event

      # Now that's what the client actually receives.
      assert_push "event", notification
      assert notification.event == "process_created"

      # Make sure all we need is on the process return
      assert_id notification.data.process_id, event.process.process_id
      assert notification.data.type == event.process.type |> to_string()
      assert_id notification.data.file_id, event.process.file_id
      assert_id notification.data.connection_id, event.process.connection_id
      assert_id notification.data.network_id, event.process.network_id
      assert notification.data.target_ip
      assert notification.data.source_ip

      # Event id was generated
      assert notification.meta.event_id
      assert is_binary(notification.meta.event_id)

      # No process id
      refute notification.meta.process_id
    end

    # This test is meant to verify that, on process completion, all events
    # coming out from the process have the `process_id` added to the event's
    # `__meta__`. Sadly, current TOP interface does not allow for an easy
    # testing of this, so this test is done at a much higher level. Revisit
    # these tests once TOP gets rewritten (#291).
    test "inheritance of process id" do
      {socket, %{gateway: gateway, account: account}} =
          ChannelSetup.join_server([own_server: true])

      # Ensure we are listening to events on the Account channel too.
      ChannelSetup.join_account(
        [account_id: account.account_id, socket: socket])

      {target, _} = ServerSetup.server()

      target_nip = ServerHelper.get_nip(target)

      SoftwareSetup.file([type: :cracker, server_id: gateway.server_id])

      params = %{
        network_id: to_string(target_nip.network_id),
        ip: target_nip.ip,
        bounces: []
      }

      # Start the Bruteforce attack
      ref = push socket, "cracker.bruteforce", params

      # Wait for response
      assert_reply ref, :ok, response, 300

      # The response includes the Bruteforce process information
      assert response.data.process_id

      # Wait for generic ProcessCreatedEvent
      assert_push "event", _top_recalcado_event
      assert_push "event", process_created_event
      assert process_created_event.event == "process_created"

      # Let's cheat and finish the process right now
      process = ProcessQuery.fetch(response.data.process_id)
      process_id = process.process_id
      TOPHelper.force_completion(process)

      # Intercept Helix internal events.
      # Note these events won't (necessarily) go out to the Client, they will
      # be intercepted and may be filtered out if they do not implement the
      # Notificable protocol.
      # We are getting them here so we can inspect the actual metadata of
      # both `ProcessCompletedEvent` and `PasswordAcquiredEvent`
      assert_broadcast "event", _top_recalcado_event
      assert_broadcast "event", _process_created_t
      assert_broadcast "event", _process_created_f
      assert_broadcast "event", server_password_acquired_event
      assert_broadcast "event", process_completed_event

      # They have the process IDs!
      assert process_id == process_completed_event.__meta__.process_id
      assert process_id == server_password_acquired_event.__meta__.process_id

      # We'll receive the PasswordAcquiredEvent
      assert_push "event", password_acquired_event
      assert password_acquired_event.event == "server_password_acquired"

      # Which has a valid `process_id` on the event metadata!
      assert to_string(process_id) == password_acquired_event.meta.process_id

      # And if `ServerPasswordAcquiredEvent` has the process_id, then
      # `BruteforceProcessedEvent` have it as well, and as such TOP should be
      # working for all kinds of events.

      # Soon we'll receive the generic ProcessCompletedEvent
      assert_push "event", process_conclusion_event
      assert process_conclusion_event.event == "process_completed"

      # As long as we are here, let's test that the metadata sent to the client
      # has been converted to JSON-friendly strings
      assert to_string(process_id) == process_conclusion_event.meta.process_id
    end
  end
end
