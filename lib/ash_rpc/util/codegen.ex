defmodule AshRpc.Util.Codegen do
  @moduledoc false

  alias AshRpc.{Input.FieldFormatter, Config.Config}

  def format_output_field(name) do
    FieldFormatter.format_field(name, Config.output_field_formatter())
  end

  def build_resource_type_name(resource) when is_atom(resource) do
    resource
    |> Module.split()
    |> List.last()
    |> Macro.camelize()
  end

  def find_embedded_resources(resources) do
    resources
    |> Enum.flat_map(&extract_embedded_from_resource/1)
    |> Enum.uniq()
  end

  defp extract_embedded_from_resource(resource) do
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Enum.flat_map(fn attr ->
      case attr.type do
        {:array, t} -> if embedded?(t), do: [t], else: []
        t -> if embedded?(t), do: [t], else: []
      end
    end)
  end

  def embedded?(module) when is_atom(module) do
    function_exported?(Ash.Resource.Info, :resource?, 1) and
      Ash.Resource.Info.resource?(module) and Ash.Resource.Info.embedded?(module)
  end

  def embedded?(_), do: false
end
