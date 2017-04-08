defmodule Helix.Account.WS.Routes do

  alias Helix.Account.WS.Controller.Account, as: AccountController

  # Note that this is somewhat a hack to allow us to break our request-response
  # channel into several parts (one on each domain). So this code will be
  # executed inside the "requests" channel and thus must follow Phoenix
  # Channel's callback interface:
  # https://hexdocs.pm/phoenix/Phoenix.Channel.html#c:handle_in/3

  def handle_in("account.logout", _params, socket) do
    AccountController.logout(socket.assigns, %{})

    # Logout will blacklist the token and stop the socket, so, this only makes
    # sense
    {:stop, :normal, socket}
  end

  def handle_in(_, _, socket) do
    {:reply, :error, socket}
  end
end

defmodule Helix.Account.WS.PublicRoutes do

  alias Helix.Account.WS.Controller.Account, as: AccountController

  # Note that this is somewhat a hack to allow us to break our request-response
  # channel into several parts (one on each domain). So this code will be
  # executed inside the "requests" channel and thus must follow Phoenix
  # Channel's callback interface:
  # https://hexdocs.pm/phoenix/Phoenix.Channel.html#c:handle_in/3

  def handle_in("account.create", params, socket) do
    response = AccountController.register(socket.assigns, params)

    {:reply, response, socket}
  end

  def handle_in("account.login", params, socket) do
    response = AccountController.login(socket.assigns, params)

    {:reply, response, socket}
  end

  def handle_in(_, _, socket) do
    {:reply, :error, socket}
  end
end
