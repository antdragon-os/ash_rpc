defmodule AshRpc.TypeScript.SchemaGenerator do
  @moduledoc """
  Generates TypeScript schemas and type definitions from Ash resources.
  """

  alias AshRpc.TypeScript.TypeUtils

  @doc """
  Generates the complete resource schema definition.
  """
  def generate_resource_schema_definition(resource) do
    schema_name = resource_schema_name(resource)

    # Get primitive field definitions (attributes, calculations, aggregates)
    primitive_attrs = safe_public_attributes(resource)
    primitive_calcs = safe_public_calculations(resource)
    primitive_aggs = safe_public_aggregates(resource)

    # Generate primitive field names union for __primitiveFields
    primitive_field_names =
      (primitive_attrs |> Enum.map(& &1.name)) ++
      (primitive_calcs |> Enum.map(& &1.name)) ++
      (primitive_aggs |> Enum.map(& &1.name))

    primitive_fields_union =
      primitive_field_names
      |> Enum.map(&TypeUtils.camelize_lower/1)
      |> Enum.map(&"\"#{&1}\"")
      |> Enum.join(" | ")

    primitive_fields_union = if primitive_fields_union == "", do: "never", else: primitive_fields_union

    # Generate field definitions for the schema
    field_defs = []

    # Add primitive attribute fields
    attr_defs = Enum.map(primitive_attrs, fn attr ->
      name = TypeUtils.camelize_lower(attr.name)
      type = TypeUtils.ts_type(attr.type)
      "  #{name}: #{type};"
    end)
    field_defs = field_defs ++ attr_defs

    # Add calculation fields
    calc_defs = Enum.map(primitive_calcs, fn calc ->
      name = TypeUtils.camelize_lower(calc.name)
      return_type = TypeUtils.ts_type(calc.type)
      "  #{name}: #{return_type};"
    end)
    field_defs = field_defs ++ calc_defs

    # Add aggregate fields
    agg_defs = Enum.map(primitive_aggs, fn agg ->
      name = TypeUtils.camelize_lower(agg.name)
      # Aggregates return the field type they're aggregating
      field_type = case agg.field do
        nil -> "number" # count aggregate
        field_name ->
          case Ash.Resource.Info.attribute(resource, field_name) do
            nil -> "any"
            attr -> TypeUtils.ts_type(attr.type)
          end
      end
      "  #{name}: #{field_type};"
    end)
    field_defs = field_defs ++ agg_defs

    # Add relationship fields with proper metadata for type inference
    rel_defs = Enum.map(safe_public_relationships(resource), fn rel ->
      name = TypeUtils.camelize_lower(rel.name)
      dest_schema = resource_schema_name(rel.destination)

      case rel.cardinality do
        :one ->
          nullable = if rel.allow_nil?, do: " | null", else: ""
          "  #{name}: {\n    __type: \"Relationship\";\n    __resource: #{dest_schema};\n    __array: false;\n  }#{nullable};"
        :many ->
          "  #{name}: {\n    __type: \"Relationship\";\n    __resource: #{dest_schema};\n    __array: true;\n  };"
      end
    end)
    field_defs = field_defs ++ rel_defs

    # Combine all field definitions
    all_fields = [
      "  __type: \"#{resource}\";",
      "  __primitiveFields: #{primitive_fields_union};"
    ] ++ field_defs

    """
    type #{schema_name} = {
    #{Enum.join(all_fields, "\n")}
    };
    """
  end

  @doc """
  Generates the fields alias for a resource.
  """
  def generate_fields_alias(resource) do
    alias_name = fields_alias_name(resource)

    base_names =
      (safe_public_attributes(resource) |> Enum.map(& &1.name)) ++
        (safe_public_calculations(resource) |> Enum.map(& &1.name)) ++
        (safe_public_aggregates(resource) |> Enum.map(& &1.name))

    base_union =
      base_names
      |> Enum.map(&TypeUtils.camelize_lower/1)
      |> Enum.map(&"\"#{&1}\"")
      |> Enum.join(" | ")

    rels = safe_public_relationships(resource)

    rel_union =
      Enum.map(rels, fn rel ->
        rel_name = TypeUtils.camelize_lower(rel.name)
        dest_alias = fields_alias_name(rel.destination)
        "{ #{rel_name}: #{dest_alias}[] }"
      end)
      |> Enum.join(" | ")

    parts = Enum.reject([base_union, rel_union], &(&1 == ""))
    union = if parts == [], do: "never", else: Enum.join(parts, " | ")

    "type #{alias_name} = #{union};"
  end

  @doc """
  Generates the nested query alias for a resource.
  """
  def generate_nested_query_alias(resource) do
    alias_name = nested_query_alias_name(resource)
    select_t = TypeUtils.ts_select_type(resource)
    sort_t = TypeUtils.ts_sort_type(resource)
    shape = TypeUtils.ts_shape_inline(resource)
    _fields_alias = fields_alias_name(resource)

    # For nested we allow resource-specific select semantics (including +/- strings)
    "type #{alias_name} = { filter?: AshFilter<#{shape}>; sort?: #{sort_t}; select?: #{select_t}; page?: { limit?: number; offset?: number; after?: string }; load?: (string | Record<string, any>)[] };"
  end

  @doc """
  Generates the resource shape with fields for type inference.
  """
  def resource_shape_with_fields(resource) do
    fields_alias = fields_alias_name(resource)
    schema_name = resource_schema_name(resource)

    "InferSelectedResult<#{schema_name}, #{fields_alias}[]>"
  end

  @doc """
  Gets the resource schema name for a resource.
  """
  def resource_schema_name(resource) do
    mod = resource |> Module.split() |> Enum.join("_")
    "ResourceSchema_" <> mod
  end

  @doc """
  Gets the fields alias name for a resource.
  """
  def fields_alias_name(resource) do
    mod = resource |> Module.split() |> Enum.join("_")
    "Fields_" <> mod
  end

  @doc """
  Gets the nested query alias name for a resource.
  """
  def nested_query_alias_name(resource) do
    mod = resource |> Module.split() |> Enum.join("_")
    "NestedQuery_" <> mod
  end

  # Helper functions for safe resource inspection
  defp safe_public_attributes(resource) do
    try do
      Ash.Resource.Info.public_attributes(resource)
    rescue
      _ -> []
    end
  end

  defp safe_public_calculations(resource) do
    try do
      Ash.Resource.Info.public_calculations(resource)
    rescue
      _ -> []
    end
  end

  defp safe_public_aggregates(resource) do
    try do
      Ash.Resource.Info.public_aggregates(resource)
    rescue
      _ -> []
    end
  end

  defp safe_public_relationships(resource) do
    try do
      Ash.Resource.Info.public_relationships(resource)
    rescue
      _ -> []
    end
  end
end
