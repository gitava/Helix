defmodule HELM.Software.Storage.Drive.Schema do
  use Ecto.Schema

  import Ecto.Changeset

  alias HELM.Software.Storage.Schema, as: StorageSchema
  alias Ecto.Changeset

  @primary_key false
  @creation_fields ~w/drive_id storage_id/a

  schema "storage_drives" do
    field :drive_id, :integer, primary_key: true

    belongs_to :storages, StorageSchema,
      foreign_key: :storage_id,
      references: :storage_id,
      type: :string,
      primary_key: true

    timestamps
  end

  def create_changeset(params) do
    %__MODULE__{}
    |> cast(params, @creation_fields)
    |> unique_constraint(:storage_id)
  end
end
