defmodule Cldr.Map do
  @moduledoc """
  Helper functions for transforming maps, keys and values.
  """

  @doc """
  Convert map string camelCase keys to underscore_keys
  """
  def underscore_keys(nil), do: nil

  def underscore_keys(map = %{}) do
    map
    |> Enum.map(fn {k, v} -> {Macro.underscore(k), underscore_keys(v)} end)
    |> Enum.map(fn {k, v} -> {String.replace(k, "-", "_"), v} end)
    |> Enum.into(%{})
  end

  # Walk the list and atomize the keys of
  # of any map members
  def underscore_keys([head | rest]) do
    [underscore_keys(head) | underscore_keys(rest)]
  end

  def underscore_keys(not_a_map) do
    not_a_map
  end

  @doc """
  Convert map string keys to :atom keys
  """
  def atomize_keys(nil), do: nil

  # Structs don't do enumerable and anyway the keys are already
  # atoms
  def atomize_keys(struct = %{__struct__: _}) do
    struct
  end

  def atomize_keys(map = %{}) do
    map
    |> Enum.map(fn {k, v} -> {atomize_key(k), atomize_keys(v)} end)
    |> Enum.into(%{})
  end

  # Walk the list and atomize the keys of
  # of any map members
  def atomize_keys([head | rest]) do
    [atomize_keys(head) | atomize_keys(rest)]
  end

  def atomize_keys(not_a_map) do
    not_a_map
  end

  def atomize_key(key) when is_binary(key) do
    String.to_atom(key)
  end

  def atomize_key(key) when is_atom(key) do
    key
  end

  @doc """
  Convert map atom keys to strings
  """
  def stringify_keys(nil), do: nil

  def stringify_keys(map = %{}) do
    map
    |> Enum.map(fn {k, v} -> {Atom.to_string(k), stringify_keys(v)} end)
    |> Enum.into(%{})
  end

  # Walk the list and atomize the keys of
  # of any map members
  def stringify_keys([head | rest]) do
    [stringify_keys(head) | stringify_keys(rest)]
  end

  def stringify_keys(not_a_map) do
    not_a_map
  end

  @doc """
  Returns the result of deep merging a list of maps
  """
  def merge_map_list([h | []]) do
    h
  end

  def merge_map_list([h | t]) do
    deep_merge(h, merge_map_list(t))
  end

  def merge_map_list([]) do
    []
  end

  @doc """
  Deep merge two maps
  """
  def deep_merge(left, right) do
    Map.merge(left, right, &deep_resolve/3)
  end

  # Key exists in both maps, and both values are maps as well.
  # These can be merged recursively.
  defp deep_resolve(_key, left = %{}, right = %{}) do
    deep_merge(left, right)
  end

  # Key exists in both maps, but at least one of the values is
  # NOT a map. We fall back to standard merge behavior, preferring
  # the value on the right.
  defp deep_resolve(_key, _left, right) do
    right
  end

  def delete_in(%{} = map, keys) when is_list(keys) do
    Enum.reject(map, fn {k, _v} -> k in keys end)
    |> Enum.map(fn {k, v} -> {k, delete_in(v, keys)} end)
    |> Enum.into(%{})
  end

  def delete_in(map, keys) when is_list(map) and is_binary(keys) do
    delete_in(map, [keys])
  end

  def delete_in(map, keys) when is_list(map) do
    Enum.reject(map, fn {k, _v} -> k in keys end)
    |> Enum.map(fn {k, v} -> {k, delete_in(v, keys)} end)
  end

  def delete_in(%{} = map, keys) when is_binary(keys) do
    delete_in(map, [keys])
  end



  def delete_in(other, _keys) do
    other
  end
end
