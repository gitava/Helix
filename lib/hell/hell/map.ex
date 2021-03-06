defmodule HELL.MapUtils do
  @moduledoc """
  Excerpt from https://gist.github.com/kipcole9/0bd4c6fb6109bfec9955f785087f53fb
  """

  @doc """
  Convert map string keys to :atom keys
  """
  # Structs don't do enumerable and anyway the keys are already
  # atoms
  def atomize_keys(struct = %_{}),
    do: struct
  def atomize_keys(map = %{}) do
    map
    |> Enum.map(fn
      {k, v} when is_atom(k) ->
        {k, atomize_keys(v)}
      {k, v} ->
        {String.to_existing_atom(k), atomize_keys(v)}
    end)
    |> :maps.from_list()
  end

  # Walk the list and atomize the keys of
  # of any map members
  def atomize_keys([head | rest]) do
    [atomize_keys(head) | atomize_keys(rest)]
  end

  def atomize_keys(not_a_map) do
    not_a_map
  end

  @doc """
  Performs a "naive" deep merge of a map, i.e. it applies `fun/2` on the first
  nesting of maps `a` and `b`. Would require some changes for an arbitrarily
  large deep merge.

  Notice it wipes away any structs! If you need something more robust, check
  https://github.com/PragTob/deep_merge
  """
  def naive_deep_merge(a, b, fun) do
    Map.merge(a, b, fn _, subA, subB ->
      Map.merge(subA, subB, fn _, vA, vB -> fun.(vA, vB) end)
    end)
  end
end
