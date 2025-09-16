defmodule AshRpc.Util.Util do
  @moduledoc false
  require Ash.Resource.Info

  @spec resource_segment(module()) :: String.t()
  def resource_segment(resource) when is_atom(resource) do
    case resource_name_override(resource) do
      nil ->
        resource
        |> Module.split()
        |> List.last()
        |> Macro.underscore()

      name ->
        name
    end
  end

  defp resource_name_override(resource) do
    if Code.ensure_loaded?(AshRpc.Dsl.Info) do
      AshRpc.Dsl.Info.resource_name(resource)
    else
      nil
    end
  end

  @spec find_resource_by_segment([module()], String.t()) :: module() | nil
  def find_resource_by_segment(resources, segment) do
    Enum.find(resources, fn res -> resource_segment(res) == segment end)
  end

  @spec domain_segment(module()) :: String.t()
  def domain_segment(domain) when is_atom(domain) do
    domain
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end

  @spec camel_to_snake(String.t()) :: atom()
  def camel_to_snake(name) when is_binary(name) do
    name
    |> Macro.underscore()
    |> String.to_atom()
  end

  @spec snake_keys(term()) :: term()
  def snake_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} ->
      key =
        case k do
          k when is_binary(k) -> Macro.underscore(k)
          k when is_atom(k) -> k |> to_string() |> Macro.underscore()
          other -> to_string(other)
        end

      {key, snake_keys(v)}
    end)
    |> Map.new()
  end

  def snake_keys(list) when is_list(list), do: Enum.map(list, &snake_keys/1)
  def snake_keys(other), do: other

  @spec to_plain(any()) :: any()
  # First, normalize common scalar structs so they don't get expanded
  def to_plain(%Ash.CiString{} = ci), do: to_string(ci)
  def to_plain(%Decimal{} = dec), do: Decimal.to_string(dec)
  def to_plain(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def to_plain(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  def to_plain(%Date{} = d), do: Date.to_iso8601(d)
  def to_plain(%Time{} = t), do: Time.to_iso8601(t)

  # Ash pages → lists of plain
  def to_plain(%Ash.Page.Keyset{results: results}), do: Enum.map(results, &to_plain/1)
  def to_plain(%Ash.Page.Offset{results: results}), do: Enum.map(results, &to_plain/1)

  # Lists
  def to_plain(list) when is_list(list), do: Enum.map(list, &to_plain/1)

  # Ash resources or other structs → plain maps, recursively
  def to_plain(%{__struct__: struct} = record) when is_atom(struct) do
    # If it's an Ash resource, only include public attributes + PK by default
    if function_exported?(Ash.Resource.Info, :resource?, 1) && Ash.Resource.Info.resource?(struct) do
      attrs = Ash.Resource.Info.public_attributes(struct) |> Enum.map(& &1.name)
      rels = Ash.Resource.Info.public_relationships(struct) |> Enum.map(& &1.name)
      pk = Ash.Resource.Info.primary_key(struct)

      record
      |> Map.from_struct()
      |> Map.take(Enum.uniq(pk ++ attrs ++ rels))
      # Drop not-loaded attributes entirely so unselected fields are not returned
      |> Enum.reject(fn {_k, v} -> match?(%Ash.NotLoaded{}, v) end)
      |> Enum.map(fn {k, v} -> {k, to_plain(v)} end)
      |> Map.new()
    else
      record
      |> Map.from_struct()
      |> Enum.reject(fn {_k, v} -> match?(%Ash.NotLoaded{}, v) end)
      |> Enum.map(fn {k, v} -> {k, to_plain(v)} end)
      |> Map.new()
    end
  end

  # Plain maps
  def to_plain(map) when is_map(map) do
    map
    |> Enum.reject(fn {_k, v} -> match?(%Ash.NotLoaded{}, v) end)
    |> Map.new(fn {k, v} -> {k, to_plain(v)} end)
  end

  # Everything else
  def to_plain(other), do: other
end
