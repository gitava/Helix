defmodule HELM.Software.Module.Role.Controller do
  import Ecto.Query

  alias HELM.Software.Repo
  alias HELM.Software.Module.Role.Schema, as: ModuleRoleSchema

  def create(role, type) do
    %{module_role: role,
      file_type: type}
    |> ModuleRoleSchema.create_changeset()
    |> Repo.insert()
  end

  def find(role, type) do
    case Repo.get_by(ModuleRoleSchema, module_role: role, file_type: type) do
      nil -> {:error, :notfound}
      res -> {:ok, res}
    end
  end

  def delete(role, type) do
    case find(role, type) do
      {:ok, file} -> Repo.delete(file)
      error -> error
    end
  end
end