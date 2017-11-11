defmodule Helix.Test.Channel.Setup do

  import Phoenix.ChannelTest

  alias Helix.Websocket
  alias Helix.Account.Model.Account
  alias Helix.Account.Query.Account, as: AccountQuery
  alias Helix.Account.Websocket.Channel.Account, as: AccountChannel
  alias Helix.Entity.Model.Entity
  alias Helix.Network.Model.Network
  alias Helix.Server.Model.Server
  alias Helix.Server.Query.Server, as: ServerQuery
  alias Helix.Server.Websocket.Channel.Server, as: ServerChannel

  alias HELL.TestHelper.Random
  alias Helix.Test.Account.Setup, as: AccountSetup
  alias Helix.Test.Cache.Helper, as: CacheHelper
  alias Helix.Test.Entity.Setup, as: EntitySetup
  alias Helix.Test.Network.Helper, as: NetworkHelper
  alias Helix.Test.Server.Setup, as: ServerSetup
  alias Helix.Test.Software.Setup, as: SoftwareSetup
  alias Helix.Test.Channel.Helper, as: ChannelHelper

  @endpoint Helix.Endpoint

  @internet_id NetworkHelper.internet_id()

  @doc """
  - account: Specify which account to generate the socket to
  - entity_id: Specify entity ID that socket should be generated to.
  - with_server: Whether to generate an account with server. Defaults to true.

  Related: Account.t, Server.t (when `with_server` is true)
  """
  def create_socket(opts \\ [with_server: true]) do
    {account, related} =
      cond do
        opts[:with_server] ->
          AccountSetup.account([with_server: true])

        opts[:entity_id] ->
          account_id = Account.ID.cast!(to_string(opts[:entity_id]))
          account = AccountQuery.fetch(account_id)
          {account, %{}}

        opts[:account] ->
          {opts[:account], %{}}

        true ->
          AccountSetup.account()
      end

    {token, _} = AccountSetup.token([account: account])

    params =
      %{
        token: token,
        client: "web2"
      }

    {:ok, socket} = connect(Websocket, params)

    related =
      related
      |> Map.merge(%{account: account})
      |> Map.merge(%{token: token})

    {socket, related}
  end

  @doc """
  - account_id: Specify channel to join. Creates a new account if none is set.
  - socket: Specify which socket to use. Generates a new one if not set.

  If `socket` is given, an `account_id` must be set as well. Same for the
  reverse case (if `account_id` is defined, a `socket` must be given.

  Related: Account.id, Entity.id
  """
  def join_account(opts \\ []) do
    acc_without_socket = not is_nil(opts[:account_id]) and is_nil(opts[:socket])
    socket_without_acc = is_nil(opts[:account_id]) and not is_nil(opts[:socket])

    if acc_without_socket or socket_without_acc do
      raise "You must specify both :account_id and :socket"
    end

    {socket, account_id, socket_related} =
      if opts[:socket] do
        {opts[:socket], opts[:account_id], %{}}
      else
        {socket, related} = create_socket()

        {socket, related.account.account_id, related}
      end

    topic = "account:" <> to_string(account_id)

    {:ok, _, socket} = subscribe_and_join(socket, AccountChannel, topic, %{})

    related = %{
      account_id: account_id,
      entity_id: Entity.ID.cast!(to_string(account_id))
    }
    |> Map.merge(socket_related)

    {socket, related}
  end

  @doc """
  - socket: Whether to reuse an existing socket.
  - own_server: Whether joining player's own server. No destination is created.
  - destination_id: Specify destination server.
  - network_id: Specify network id. Not used if `own_server`
  - counter: Specify counter (used by ServerWebsocketChannelState). Default is 0
  - bounces: List of bounces between each server. Not used if `own_server`.
    Expected type: [Server.id]
  - gateway_files: Whether to generate random files on gateway. Defaults to
    false.
  - destination_files: Whether to generate random files on destination. Defaults
    to false.

  Related:
    Account.t, \
    gateway :: Server.t, \
    destination :: Server.t | nil, \
    destination_files :: [SoftwareSetup.file] | nil, \
    gateway_files :: [SoftwareSetup.file] | nil, \
    gateway_ip :: Network.ip, \
    destination_ip :: Network.ip | nil
  """
  def join_server(opts \\ []) do
    {socket, %{account: account, server: gateway}} =
      if opts[:socket] do
        gateway = opts[:socket].assigns.gateway.server_id |> ServerQuery.fetch()

        {opts[:socket], %{account: nil, server: gateway}}
      else
        create_socket()
      end

    local? = Keyword.get(opts, :own_server, false)

    {join, destination} =
      if local? do
        join = get_join_data(opts, gateway)

        {join, nil}
      else
        destination = ServerSetup.create_or_fetch(opts[:destination_id])

        join = get_join_data(opts, gateway, destination)

        {join, destination}
      end

    {:ok, _, socket} =
      subscribe_and_join(socket, ServerChannel, join.topic, join.params)

    gateway_files = generate_files(opts[:gateway_files], gateway.server_id)

    gateway_related = %{
      account: account,
      gateway: gateway,
      gateway_ip: join.gateway_ip,
      gateway_files: gateway_files,
    }

    destination_related =
      if local? do
        %{}
      else
        destination_files =
          generate_files(opts[:destination_files], destination.server_id)

        %{
          destination: destination,
          destination_ip: join.destination_ip,
          destination_files: destination_files
        }
      end

    related = Map.merge(gateway_related, destination_related)

    CacheHelper.sync_test()

    {socket, related}
  end

  defp get_join_data(opts, gateway = %Server{}, destination = %Server{}) do
    network_id = Keyword.get(opts, :network_id, @internet_id)

    gateway_ip = ServerQuery.get_ip(gateway.server_id, network_id)
    destination_ip = ServerQuery.get_ip(destination.server_id, network_id)

    counter =
      opts
      |> Keyword.get(:counter, 0)
      |> to_string()

    params = %{"gateway_ip" => gateway_ip, "password" => destination.password}

    topic = ChannelHelper.server_topic_name(network_id, destination_ip, counter)

    %{
      topic: topic,
      gateway_ip: gateway_ip,
      destination_ip: destination_ip,
      network_id: network_id,
      params: params
    }
  end

  defp get_join_data(_opts, gateway) do
    %{
      topic: ChannelHelper.server_topic_name(gateway.server_id),
      params: %{},
      gateway_ip: nil
    }
  end

  defp generate_files(condition, server_id) do
    if condition do
      file_opts = [file_opts: [server_id: server_id]]
      SoftwareSetup.random_files!(file_opts)
    else
      nil
    end
  end

  @doc """
  Opts:
  - gateway_id
  - gateway_ip
  - gateway_entity_id
  - destination_id
  - destination_ip
  - destination_entity_id
  - network_id
  - access_type: Inferred if not set
  - own_server: Force socket to represent own server channel. Defaults to false.
  - counter: Defaults to 0.
  """
  def mock_server_socket(opts \\ []) do
    gateway_id = Access.get(opts, :gateway_id, ServerSetup.id())
    gateway_ip = Keyword.get(opts, :gateway_ip, Random.ipv4())
    gateway_entity_id = Access.get(opts, :gateway_entity_id, EntitySetup.id())

    {destination_id, destination_ip, destination_entity_id} =
      if opts[:own_server] do
        {gateway_id, gateway_ip, gateway_entity_id}
      else
        server_id = Access.get(opts, :destination_id, ServerSetup.id())
        server_ip = Keyword.get(opts, :server_ip, Random.ipv4())
        entity_id = Access.get(opts, :destination_entity_id, EntitySetup.id())

        {server_id, server_ip, entity_id}
      end

    access_type =
      cond do
        opts[:access_type] ->
          opts[:access_type]

        gateway_id == destination_id ->
          :local

        true ->
          :remote
      end

    network_id = Keyword.get(opts, :network_id, Network.ID.generate())
    counter = Keyword.get(opts, :counter, 0)
    meta = %{
      access_type: access_type,
      network_id: network_id,
      counter: counter
    }

    assigns = %{
      gateway: %{
        server_id: gateway_id,
        ip: gateway_ip,
        entity_id: gateway_entity_id
      },
      destination: %{
        server_id: destination_id,
        ip: destination_ip,
        entity_id: destination_entity_id
      },
      meta: meta
    }

    %{assigns: assigns}
  end

  @doc """
  Opts:
  - die
  """
  def mock_account_socket(_opts \\ []) do
    assigns = %{}

    %{assigns: assigns}
  end
end
