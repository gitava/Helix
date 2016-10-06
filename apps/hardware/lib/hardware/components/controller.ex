defmodule HELM.Hardware.Component.Controller do
  import Ecto.Query

  alias HELF.{Broker, Error}
  alias HELM.Hardware
  alias HELM.Hardware.Component

  def new(component_type, spec_id) do
    %{component_type: component_type, spec_id: spec_id}
    |> Component.Schema.create_changeset
    |> do_new_component
  end

  defp do_new_component(changeset) do
    case Hardware.Repo.insert(changeset) do
      {:ok, schema} ->
        Broker.cast("event:component:created", changeset.changes.component_id)
        {:ok, schema}
      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
