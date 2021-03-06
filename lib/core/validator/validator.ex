defmodule Helix.Core.Validator do

  @type input_type ::
    :password
    | :hostname

  @regex_hostname ~r/^[a-zA-Z0-9-_.@#]{1,20}$/

  @spec validate_input(input :: String.t, input_type, opts :: term) ::
    {:ok, validated_input :: String.t}
    | :error
  @doc """
  This is a generic function meant to validate external input that does not
  conform to a specific shape or format (like internal IDs or IP addresses).

  The `element` argument identifies what the input is supposed to represent, and
  we leverage this information to customize the validation for different kinds
  of input.
  """
  def validate_input(input, type, opts \\ [])

  def validate_input(input, :password, _) do
    {:ok, input}  # Validation itself is TODO :-)
  end

  def validate_input(input, :hostname, _),
    do: validate_hostname(input)

  defp validate_hostname(v) when not is_binary(v),
    do: :error
  defp validate_hostname(v) do
    if Regex.match?(@regex_hostname, v) do
      {:ok, v}
    else
      :error
    end
  end
end
