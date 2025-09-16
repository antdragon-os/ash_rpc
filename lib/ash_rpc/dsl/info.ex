defmodule AshRpc.Dsl.Info do
  @moduledoc false
  alias Spark.Dsl.Extension

  def expose(resource) do
    Extension.get_opt(resource, [:ash_rpc], :expose, nil, true)
  rescue
    _ -> nil
  end

  def resource_name(resource) do
    Extension.get_opt(resource, [:ash_rpc], :resource_name, nil, true)
  rescue
    _ -> nil
  end

  def exposed?(resource, action_name) do
    case expose(resource) do
      nil -> false
      :all -> true
      list when is_list(list) -> action_name in list
      _ -> false
    end
  end

  def method_override(resource, action_name) do
    methods =
      try do
        Extension.get_opt(resource, [:ash_rpc], :methods, [], true)
      rescue
        _ -> []
      end

    case Enum.find(methods, fn {k, _v} -> k == action_name end) do
      {_, v} when v in [:query, :mutation] -> v
      _ -> nil
    end
  end

  def procedures(resource) do
    try do
      Spark.Dsl.Extension.get_entities(resource, [:ash_rpc])
      |> Enum.filter(&match?(%AshRpc.Dsl.Procedure{}, &1))
    rescue
      _ -> []
    end
  end

  def find_procedure(resource, external_name_atom) do
    procedures(resource)
    |> Enum.find(fn %AshRpc.Dsl.Procedure{name: name} -> name == external_name_atom end)
  end
end
