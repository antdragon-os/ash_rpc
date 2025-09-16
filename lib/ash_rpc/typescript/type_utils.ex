defmodule AshRpc.TypeScript.TypeUtils do
  @moduledoc """
  Utility functions for TypeScript type conversion and generation.
  """

  @doc """
  Converts Elixir types to TypeScript types.
  """
  def ts_type(type) when is_atom(type) do
    cond do
      type in [:string, String, Ash.Type.String] ->
        "string"

      type in [:ci_string, Ash.Type.CiString] ->
        "string"

      type in [:uuid, :binary_id, Ecto.UUID, Ash.Type.UUID] ->
        "string"

      type in [:integer, Integer, Ash.Type.Integer] ->
        "number"

      type in [:float, Float, Ash.Type.Float] ->
        "number"

      type in [:decimal, Decimal, Ash.Type.Decimal] ->
        "number"

      type in [:boolean, Boolean, Ash.Type.Boolean] ->
        "boolean"

      type in [:map, Map, Ash.Type.Map] ->
        "Record<string, unknown>"

      type in [:atom, Ash.Type.Atom] ->
        "string"

      type in [:date, Date, Ash.Type.Date] ->
        "string"

      type in [:time, Time, Ash.Type.Time] ->
        "string"

      type in [:datetime, NaiveDateTime, Ash.Type.NaiveDatetime] ->
        "string"

      type in [
        :utc_datetime,
        :utc_datetime_usec,
        DateTime,
        Ash.Type.UtcDatetime,
        Ash.Type.UtcDatetimeUsec
      ] ->
        "string"

      function_exported?(Ash.Resource.Info, :resource?, 1) and Ash.Resource.Info.resource?(type) ->
        ts_resource_shape(type)

      function_exported?(type, :storage_type, 0) ->
        ts_type(type.storage_type())

      true ->
        "unknown"
    end
  end

  def ts_type({:array, inner}), do: ts_type(inner) <> "[]"
  def ts_type({:map, _inner}), do: "Record<string, unknown>"
  def ts_type(_), do: "unknown"

  @doc """
  Generates action input types with query options.
  """
  def ts_action_input_with_query(resource, act, spec) do
    base_input = ts_action_input(resource, act)

    # For read actions, add query options if enabled
    if act.type == :read && Map.get(spec, :method) == :query do
      # Check if this is an infinite query (array return type)
      is_infinite_query =
        case act.type do
          :read -> !Map.get(act, :get?, false) && Map.get(spec, :paginatable, true)
          _ -> false
        end

      query_fields = ts_query_options(resource, spec, is_infinite_query)

      if query_fields != [] do
        if base_input == "void" do
          "{ #{Enum.join(query_fields, "; ")} }"
        else
          # Remove closing brace, add query fields, then close
          String.replace(
            base_input,
            ~r/ }$/,
            "; #{Enum.join(query_fields, "; ")} }"
          )
        end
      else
        base_input
      end
    else
      base_input
    end
  end

  @doc """
  Generates action input types.
  """
  def ts_action_input(resource, act) do
    args = act.arguments || []

    arg_fields =
      Enum.map(args, fn a ->
        optional = if a.allow_nil?, do: "?", else: ""
        "#{a.name}#{optional}: #{ts_type(a.type)}"
      end)

    attr_fields =
      case act.type do
        t when t in [:create, :update] ->
          accepted = Map.get(act, :accept) || []
          attrs = if accepted == [], do: [], else: accepted

          attrs
          |> Enum.map(fn name -> Ash.Resource.Info.attribute(resource, name) end)
          |> Enum.reject(&is_nil/1)
          |> Enum.map(fn a ->
            opt =
              case act.type do
                # updates: all accepted attrs optional
                :update -> "?"
                _ -> if a.allow_nil?, do: "?", else: ""
              end

            "#{a.name}#{opt}: #{ts_type(a.type)}"
          end)

        _ ->
          []
      end

    pk_fields =
      case act.type do
        t when t in [:update, :destroy] ->
          pks = Ash.Resource.Info.primary_key(resource)

          pks
          |> Enum.map(fn name -> Ash.Resource.Info.attribute(resource, name) end)
          |> Enum.reject(&is_nil/1)
          |> Enum.map(fn a ->
            # primary keys are required
            "#{a.name}: #{ts_type(a.type)}"
          end)

        _ ->
          []
      end

    parts = (arg_fields ++ attr_fields ++ pk_fields) |> Enum.uniq()
    if parts == [], do: "void", else: "{ #{Enum.join(parts, "; ")} }"
  end

  @doc """
  Generates query options for read actions.
  """
  def ts_query_options(resource, spec, _is_infinite_query \\ false) do
    opts = []

    # Filter option
    opts =
      if Map.get(spec, :filterable, true) do
        shape = ts_shape_inline(resource)
        opts ++ ["filter?: AshFilter<#{shape}>"]
      else
        opts
      end

    # Sort option
    opts =
      if Map.get(spec, :sortable, true) do
        sort_type = ts_sort_type(resource)
        opts ++ ["sort?: #{sort_type}"]
      else
        opts
      end

    # Select option
    opts =
      if Map.get(spec, :selectable, true) do
        select_type = ts_select_type(resource)
        opts ++ ["select?: #{select_type}"]
      else
        opts
      end

    # Page option - use unified AshPage type with discriminated unions
    opts =
      if Map.get(spec, :paginatable, true) do
        opts ++ ["page?: AshPage", "cursor?: AshCursor"]
      else
        opts
      end

    # Load option
    relationships = Map.get(spec, :relationships)

    opts =
      if relationships && relationships != [] do
        rel_infos =
          Enum.flat_map(relationships, fn rel_name ->
            case Ash.Resource.Info.relationship(resource, rel_name) do
              nil -> []
              rel -> [rel]
            end
          end)

        unions =
          Enum.map(rel_infos, fn rel ->
            rel_ts = camelize_lower(rel.name)
            dest = rel.destination
            nested_type = ts_nested_query_alias_name(dest)
            # either a simple string name, or an object with nested query options
            nested = "'#{rel_ts}' | { #{rel_ts}: #{nested_type} }"
            nested
          end)
          |> Enum.join(" | ")

        opts ++ ["load?: (#{unions})[]"]
      else
        # If no specific relationships configured, allow any string
        opts ++ ["load?: string[]"]
      end

    opts
  end

  @doc """
  Generates the resource shape inline (for filter types).
  """
  def ts_shape_inline(resource) do
    attrs =
      try do
        Ash.Resource.Info.public_attributes(resource)
      rescue
        _ -> []
      end

    fields =
      Enum.map(attrs, fn a ->
        base_type = ts_type(a.type)
        type = if a.allow_nil?, do: "#{base_type} | null", else: base_type
        "#{ts_field_name(a.name)}: #{type}"
      end)

    if fields == [] do
      "Record<string, unknown>"
    else
      "{ #{Enum.join(fields, "; ")} }"
    end
  end

  @doc """
  Generates sort type for a resource.
  """
  def ts_sort_type(resource) do
    # Get public attributes for the resource
    public_attrs =
      try do
        Ash.Resource.Info.public_attributes(resource)
      rescue
        _ -> []
      end

    # Create sort fields for each attribute, converting to camelCase
    sort_fields =
      Enum.map(public_attrs, fn attr ->
        # Convert snake_case to camelCase for TypeScript (lowercase first letter)
        pascal_case = attr.name |> Atom.to_string() |> Macro.camelize()

        field_name =
          String.downcase(String.first(pascal_case) || "") <>
            String.slice(pascal_case, 1, String.length(pascal_case) - 1)

        "#{field_name}?: 'asc' | 'desc'"
      end)

    if sort_fields == [] do
      "Record<string, 'asc' | 'desc'>"
    else
      "{ #{Enum.join(sort_fields, "; ")} }"
    end
  end

  @doc """
  Generates select type for a resource.
  """
  def ts_select_type(resource) do
    # Use resource-specific fields alias with +/- modifiers on string fields
    fields_alias = AshRpc.TypeScript.SchemaGenerator.fields_alias_name(resource)
    "WithModifiers<#{fields_alias}>[]"
  end

  @doc """
  Gets nested query alias name for a resource.
  """
  def ts_nested_query_alias_name(resource) do
    mod = resource |> Module.split() |> Enum.join("_")
    "NestedQuery_" <> mod
  end

  @doc """
  Gets method override or default for a resource action.
  """
  def method_override_or_default(resource, act) do
    override =
      try do
        AshRpc.Dsl.Info.method_override(resource, act.name)
      rescue
        _ -> nil
      end

    cond do
      override in [:query, :mutation] -> override
      act.type in [:create, :update, :destroy] -> :mutation
      true -> :query
    end
  end

  @doc """
  Converts field names to camelCase.
  """
  def camelize_lower(name) do
    str = name |> to_string() |> Macro.camelize()
    String.replace_prefix(str, String.first(str) || "", String.downcase(String.first(str) || ""))
  end

  @doc """
  Converts field names for TypeScript.
  """
  def ts_field_name(name) when is_atom(name) do
    str = name |> Atom.to_string() |> Macro.camelize()
    String.downcase(String.first(str) || "") <> String.slice(str, 1, String.length(str) - 1)
  end

  @doc """
  Generates legacy resource shape (for backward compatibility).
  """
  def ts_resource_shape(resource) do
    attrs =
      try do
        Ash.Resource.Info.public_attributes(resource)
      rescue
        _ -> []
      end

    calcs =
      try do
        Ash.Resource.Info.public_calculations(resource)
      rescue
        _ -> []
      end

    aggs =
      try do
        Ash.Resource.Info.public_aggregates(resource)
      rescue
        _ -> []
      end

    attr_fields =
      Enum.map(attrs, fn a ->
        opt = if a.allow_nil?, do: "?", else: ""
        "#{ts_field_name(a.name)}#{opt}: #{ts_type(a.type)}"
      end)

    calc_fields =
      Enum.map(calcs, fn c ->
        # Calculations may not be loaded unless selected; mark optional
        "#{ts_field_name(c.name)}?: #{ts_type(c.type)}"
      end)

    agg_fields =
      Enum.map(aggs, fn a ->
        "#{ts_field_name(a.name)}?: #{ts_aggregate_type(resource, a)}"
      end)

    fields = Enum.join(attr_fields ++ calc_fields ++ agg_fields, "; ")
    if fields == "", do: "Record<string, unknown>", else: "{ #{fields} }"
  end

  @doc """
  Generates aggregate type for a resource aggregate.
  """
  def ts_aggregate_type(resource, agg) do
    case agg.kind do
      :count ->
        "number"

      :sum ->
        "number"

      :avg ->
        "number"

      :min ->
        "unknown"

      :max ->
        "unknown"

      :exists ->
        "boolean"

      :first ->
        ts_type(type_for_field_via_path(resource, agg.relationship_path, agg.field))

      :last ->
        ts_type(type_for_field_via_path(resource, agg.relationship_path, agg.field))

      :list ->
        ts_type(type_for_field_via_path(resource, agg.relationship_path, agg.field)) <> "[]"

      _ ->
        "unknown"
    end
  end

  @doc """
  Gets type for field via relationship path.
  """
  def type_for_field_via_path(resource, path, field) do
    dest =
      Enum.reduce(path || [], resource, fn rel_name, acc_res ->
        case Ash.Resource.Info.relationship(acc_res, rel_name) do
          %{destination: dest} -> dest
          _ -> acc_res
        end
      end)

    case Ash.Resource.Info.attribute(dest, field) do
      %{type: t} -> t
      _ -> :unknown
    end
  end
end
