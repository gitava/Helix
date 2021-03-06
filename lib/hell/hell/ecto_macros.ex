defmodule HELL.Ecto.Macros do

  @doc """
  Syntactic-sugar for our way-too-common Query module
  """
  defmacro query(do: block) do
    quote do

      defmodule Query do
        @moduledoc false

        import Ecto.Query

        alias Ecto.Queryable
        alias unquote(__CALLER__.module)

        unquote(block)
      end

    end
  end
end
