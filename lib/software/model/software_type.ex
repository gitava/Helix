defmodule Helix.Software.Model.SoftwareType do

  use Ecto.Schema

  alias HELL.Constant

  @type t :: %__MODULE__{
    software_type: type,
    extension: String.t
  }

  @type type ::
    :cracker
    | :exploit
    | :firewall
    | :hasher
    | :log_forger
    | :log_recover
    | :encryptor
    | :decryptor
    | :anymap
    | :crypto_key

  # TODO: Add module types once file_module refactor is done

  # TODO: Software macro:
  # software \
  #   type: :cracker,
  #   extension: ".crc",
  #   modules: [:bruteforce, :overflow]

  @primary_key false
  schema "software_types" do
    field :software_type, Constant,
      primary_key: true

    field :extension, :string
  end

  @doc false
  def possible_types do
    %{
      text: %{
        extension: "txt",
        modules: []
      },
      cracker: %{
        extension: "crc",
        modules: [:bruteforce, :overflow]
      },
      exploit: %{
        extension: "exp",
        modules: [:ftp, :ssh]
      },
      firewall: %{
        extension: "fwl",
        modules: [:fwl_active, :fwl_passive]
      },
      hasher: %{
        extension: "hash",
        modules: [:password]
      },
      log_forger: %{
        extension: "logf",
        modules: [:log_create, :log_edit]
      },
      log_recover: %{
        extension: "logr",
        modules: [:log_recover]
      },
      encryptor: %{
        extension: "enc",
        modules: [
          :encrypt_file,
          :encrypt_log,
          :encrypt_connection,
          :encrypt_process
        ]
      },
      decryptor: %{
        extension: "dec",
        modules: [
          :decrypt_file,
          :decrypt_log,
          :decrypt_connection,
          :decrypt_process
        ]
      },
      anymap: %{
        extension: "map",
        modules: [:map_geo, :map_net]
      },
      crypto_key: %{
        extension: "key",
        modules: []
      }
    }
  end
end
