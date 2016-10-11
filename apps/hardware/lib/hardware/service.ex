defmodule HELM.Hardware.Service do
  use GenServer

  alias HELM.Hardware
  alias HELF.Broker

  alias HELM.Hardware.Motherboard.Controller, as: MoboCtrl
  alias HELM.Hardware.Motherboard.Slot.Controller, as: MoboSlotCtrl
  alias HELM.Hardware.Component.Controller, as: CompCtrl
  alias HELM.Hardware.Component.Spec.Controller, as: CompSpecCtrl
  alias HELM.Hardware.Component.Type.Controller, as: CompTypeCtrl

  def start_link(state \\ []) do
    GenServer.start_link(__MODULE__, state, name: :hardware_service)
  end

  def init(_args) do
    Broker.subscribe(:hardware_service, "hardware:get", call:
      fn pid,_,params,timeout ->
        response = GenServer.call(pid, {:get, params}, timeout)
        {:reply, response}
      end)

    {:ok, %{}}
  end

  def handle_call({:get, {:motherboard, id}}, _from, state) do
    response = MoboCtrl.find(id)
    {:reply, response, state}
  end

  def handle_call({:get, {:motherboard_slot, id}}, _from, state) do
    response = MoboSlotCtrl.find(id)
    {:reply, response, state}
  end

  def handle_call({:get, {:component, id}}, _from, state) do
    response = CompCtrl.find(id)
    {:reply, response, state}
  end

  def handle_call({:get, {:component_spec, id}}, _from, state) do
    response = CompSpecCtrl.find(id)
    {:reply, response, state}
  end

  def handle_call({:get, :component_types}, _from, state) do
    response = CompTypeCtrl.all()
    {:reply, response, state}
  end
end
