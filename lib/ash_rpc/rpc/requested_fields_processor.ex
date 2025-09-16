defmodule AshRpc.Rpc.RequestedFieldsProcessor do
  @moduledoc false

  # Ported from ash_typescript: processes requested fields and returns {select, load, template}

  # Normalizes unified `select` input supporting strings with + / - modifiers
  # and nested relationship maps into the internal requested_fields structure
  # expected by `process/3`.
  def normalize_select(resource, _action_name, select_list) when is_list(select_list) do
    formatter = AshRpc.Config.Config.input_field_formatter()

    {adds, removes, plains, nested_maps} =
      Enum.reduce(select_list, {MapSet.new(), MapSet.new(), MapSet.new(), %{}}, fn item,
                                                                                   {add_acc,
                                                                                    rem_acc,
                                                                                    plain_acc,
                                                                                    nest} ->
        case item do
          s when is_binary(s) ->
            cond do
              String.starts_with?(s, "-") ->
                name = String.trim_leading(s, "-")
                atom = AshRpc.Input.FieldFormatter.parse_input_field(name, formatter)
                {add_acc, MapSet.put(rem_acc, atom), plain_acc, nest}

              String.starts_with?(s, "+") ->
                name = String.trim_leading(s, "+")
                atom = AshRpc.Input.FieldFormatter.parse_input_field(name, formatter)
                {MapSet.put(add_acc, atom), rem_acc, plain_acc, nest}

              true ->
                atom = AshRpc.Input.FieldFormatter.parse_input_field(s, formatter)
                {add_acc, rem_acc, MapSet.put(plain_acc, atom), nest}
            end

          a when is_atom(a) ->
            {add_acc, rem_acc, MapSet.put(plain_acc, a), nest}

          %{} = m ->
            # Normalize nested selections per-relationship
            normalized =
              Enum.reduce(m, %{}, fn {k, v}, acc ->
                rel_atom =
                  case k do
                    k when is_binary(k) ->
                      AshRpc.Input.FieldFormatter.parse_input_field(k, formatter)

                    k when is_atom(k) ->
                      k
                  end

                rel = Ash.Resource.Info.relationship(resource, rel_atom)

                nested =
                  if rel && is_list(v) do
                    normalize_select(rel.destination, :read, v)
                  else
                    List.wrap(v)
                    |> atomize_requested_fields()
                  end

                Map.update(acc, rel_atom, nested, fn existing -> existing ++ nested end)
              end)

            {add_acc, rem_acc, plain_acc, deep_merge_nested(nest, normalized)}

          _ ->
            {add_acc, rem_acc, plain_acc, nest}
        end
      end)

    has_negatives? = MapSet.size(removes) > 0
    explicit_mode? = MapSet.size(plains) > 0 or map_size(nested_maps) > 0

    base_fields =
      if has_negatives? and not explicit_mode? do
        # Baseline only includes attributes. Calculations/aggregates are NOT auto-included.
        (Ash.Resource.Info.public_attributes(resource) || [])
        |> Enum.map(& &1.name)
        |> MapSet.new()
      else
        MapSet.new()
      end

    final_flat =
      cond do
        explicit_mode? ->
          plains
          |> MapSet.union(adds)
          |> MapSet.to_list()

        has_negatives? ->
          base_fields
          |> MapSet.difference(removes)
          |> MapSet.union(adds)
          |> MapSet.to_list()

        true ->
          # Toggle mode with only '+' - include all attributes plus adds
          (Ash.Resource.Info.public_attributes(resource) || [])
          |> Enum.map(& &1.name)
          |> MapSet.new()
          |> MapSet.union(adds)
          |> MapSet.to_list()
      end

    nested_list =
      nested_maps
      |> Enum.map(fn {rel, fields} -> {rel, fields} end)

    final_flat ++ nested_list
  end

  def normalize_select(_resource, _action_name, other),
    do: other |> List.wrap() |> atomize_requested_fields()

  defp deep_merge_nested(left, right) do
    Map.merge(left, right, fn _k, v1, v2 -> v1 ++ v2 end)
  end

  def atomize_requested_fields(requested_fields) when is_list(requested_fields) do
    formatter = AshRpc.Config.Config.input_field_formatter()
    Enum.map(requested_fields, &atomize_field(&1, formatter))
  end

  def process(resource, action_name, requested_fields) do
    action = Ash.Resource.Info.action(resource, action_name)
    if is_nil(action), do: throw({:action_not_found, action_name})

    return_type = determine_return_type(resource, action)
    {select, load, template} = process_fields_for_type(return_type, requested_fields, [])
    {:ok, {select, load, format_extraction_template(template)}}
  catch
    error_tuple -> {:error, error_tuple}
  end

  defp determine_return_type(resource, action) do
    case action.type do
      type when type in [:read, :create, :update, :destroy] ->
        case type do
          :read ->
            if action.get?, do: {:resource, resource}, else: {:array, {:resource, resource}}

          _ ->
            {:resource, resource}
        end

      :action ->
        case action.returns do
          nil -> :any
          return_type -> {:ash_type, return_type, action.constraints || []}
        end
    end
  end

  defp process_fields_for_type(return_type, requested_fields, path) do
    case return_type do
      {:resource, resource} ->
        process_resource_fields(resource, requested_fields, path)

      {:array, {:resource, resource}} ->
        process_resource_fields(resource, requested_fields, path)

      {:ash_type, Ash.Type.Map, constraints} ->
        process_map_fields(constraints, requested_fields, path)

      {:ash_type, Ash.Type.Keyword, constraints} ->
        process_map_fields(constraints, requested_fields, path)

      {:ash_type, Ash.Type.Tuple, constraints} ->
        process_tuple_fields(constraints, requested_fields, path)

      {:ash_type, {:array, inner_type}, constraints} ->
        array_constraints = Keyword.get(constraints, :items, [])
        inner_return_type = {:ash_type, inner_type, array_constraints}
        process_fields_for_type(inner_return_type, requested_fields, path)

      {:ash_type, Ash.Type.Struct, constraints} ->
        case Keyword.get(constraints, :instance_of) do
          resource_module when is_atom(resource_module) ->
            process_resource_fields(resource_module, requested_fields, path)

          _ ->
            process_generic_fields(requested_fields, path)
        end

      :any ->
        process_generic_fields(requested_fields, path)

      {:ash_type, type, constraints} when is_atom(type) ->
        _ = %{type: type, constraints: constraints}
        process_generic_fields(requested_fields, path)
    end
  end

  defp process_generic_fields(requested_fields, path) do
    check_for_duplicate_fields(requested_fields, path)
    {[], [], requested_fields}
  end

  defp process_resource_fields(resource, requested_fields, path) do
    check_for_duplicate_fields(requested_fields, path)

    Enum.reduce(requested_fields, {[], [], []}, fn field, {select, load, template} ->
      case field do
        field_name when is_atom(field_name) ->
          case classify_field(resource, field_name, path) do
            :attribute -> {select ++ [field_name], load, template ++ [field_name]}
            :calculation -> {select, load ++ [field_name], template ++ [field_name]}
            :aggregate -> {select, load ++ [field_name], template ++ [field_name]}
            :relationship -> {select, load ++ [field_name], template ++ [field_name]}
            :tuple -> throw_requires(path, field_name, :tuple)
            :typed_struct -> throw_requires(path, field_name, :typed_struct)
            :union_attribute -> throw_requires(path, field_name, :union_attribute)
            :embedded_resource -> throw_requires(path, field_name, :embedded_resource)
            :embedded_resource_array -> throw_requires(path, field_name, :embedded_resource_array)
            {:error, :not_found} -> throw_unknown(resource, path, field_name)
          end

        {field_name, nested_fields} ->
          case classify_field(resource, field_name, path) do
            :relationship ->
              process_relationship(
                resource,
                field_name,
                nested_fields,
                path,
                select,
                load,
                template
              )

            :embedded_resource ->
              process_embedded_resource(
                resource,
                field_name,
                nested_fields,
                path,
                select,
                load,
                template
              )

            :embedded_resource_array ->
              process_embedded_resource(
                resource,
                field_name,
                nested_fields,
                path,
                select,
                load,
                template
              )

            :calculation ->
              throw_invalid_nesting(path, field_name)

            :calculation_with_args ->
              process_calculation_with_args(
                resource,
                field_name,
                nested_fields,
                path,
                select,
                load,
                template
              )

            :complex_aggregate ->
              process_complex_aggregate(
                resource,
                field_name,
                nested_fields,
                path,
                select,
                load,
                template
              )

            :tuple ->
              process_tuple_type(
                resource,
                field_name,
                nested_fields,
                path,
                select,
                load,
                template
              )

            :typed_struct ->
              process_typed_struct(
                resource,
                field_name,
                nested_fields,
                path,
                select,
                load,
                template
              )

            :union_attribute ->
              process_union_attribute(
                resource,
                field_name,
                nested_fields,
                path,
                select,
                load,
                template
              )

            {:error, :not_found} ->
              throw_unknown(resource, path, field_name)

            _ ->
              throw_invalid_simple(path, field_name)
          end

        %{} = field_map ->
          Enum.reduce(field_map, {select, load, template}, fn {fname, nested}, {s, l, t} ->
            case classify_field(resource, fname, path) do
              :relationship ->
                process_relationship(resource, fname, nested, path, s, l, t)

              :embedded_resource ->
                process_embedded_resource(resource, fname, nested, path, s, l, t)

              :embedded_resource_array ->
                process_embedded_resource(resource, fname, nested, path, s, l, t)

              :tuple ->
                process_tuple_type(resource, fname, nested, path, s, l, t)

              :typed_struct ->
                process_typed_struct(resource, fname, nested, path, s, l, t)

              :union_attribute ->
                process_union_attribute(resource, fname, nested, path, s, l, t)

              :calculation_with_args ->
                process_calculation_with_args(resource, fname, nested, path, s, l, t)

              :complex_aggregate ->
                process_complex_aggregate(resource, fname, nested, path, s, l, t)

              :aggregate ->
                throw_invalid_aggregate(path, fname)

              :attribute ->
                throw_field_no_nesting(path, fname)

              {:error, :not_found} ->
                throw_unknown(resource, path, fname)
            end
          end)
      end
    end)
  end

  defp process_map_fields(constraints, requested_fields, path) do
    check_for_duplicate_fields(requested_fields, path)
    field_specs = Keyword.get(constraints, :fields, [])

    Enum.reduce(requested_fields, {[], [], []}, fn field, {select, load, template} ->
      case field do
        field_name when is_atom(field_name) ->
          if Keyword.has_key?(field_specs, field_name),
            do: {select, load, template ++ [field_name]},
            else: throw_unknown("map", path, field_name)

        %{} = field_map ->
          Enum.reduce(field_map, {select, load, template}, fn {fname, nested}, {s, l, t} ->
            if Keyword.has_key?(field_specs, fname) do
              field_spec = Keyword.get(field_specs, fname)
              field_type = Keyword.get(field_spec, :type)
              field_constraints = Keyword.get(field_spec, :constraints, [])
              field_return_type = {:ash_type, field_type, field_constraints}
              new_path = path ++ [fname]

              {_ns, _nl, nested_template} =
                process_fields_for_type(field_return_type, nested, new_path)

              {s, l, t ++ [{fname, nested_template}]}
            else
              throw_unknown("map", path, fname)
            end
          end)
      end
    end)
  end

  defp process_tuple_type(resource, field_name, nested_fields, path, select, load, template) do
    validate_non_empty_fields(nested_fields, field_name, path, "Type")
    attribute = Ash.Resource.Info.attribute(resource, field_name)
    new_path = path ++ [field_name]

    {[], [], template_items} =
      process_tuple_fields(attribute.constraints, nested_fields, new_path)

    {select ++ [field_name], load, template ++ [{field_name, template_items}]}
  end

  defp process_tuple_fields(constraints, requested_fields, path) do
    check_for_duplicate_fields(requested_fields, path)
    field_specs = Keyword.get(constraints, :fields, [])
    field_order = Enum.map(field_specs, fn {name, _} -> name end)

    Enum.reduce(requested_fields, {[], [], []}, fn spec, {s, l, t} ->
      case spec do
        field_name when is_atom(field_name) ->
          index = Enum.find_index(field_order, &(&1 == field_name))
          if is_nil(index), do: throw_unknown("tuple", path, field_name)
          {s, l, t ++ [%{field_name: field_name, index: index}]}

        {field_name, _nested} ->
          throw_invalid_tuple(path, field_name)

        %{} = field_map ->
          Enum.reduce(field_map, {s, l, t}, fn {fname, _nested}, _acc ->
            _ = fname
            throw_invalid_tuple(path, fname)
          end)
      end
    end)
  end

  defp process_relationship(resource, field_name, nested_fields, path, select, load, template) do
    validate_non_empty_fields(nested_fields, field_name, path, "Relationship")

    rel =
      Ash.Resource.Info.relationship(resource, field_name) ||
        throw_unknown(resource, path, field_name)

    new_path = path ++ [field_name]

    {_ns, nested_load, nested_template} =
      process_resource_fields(rel.destination, nested_fields, new_path)

    new_load =
      if nested_load != [] do
        load ++ [{field_name, nested_load}]
      else
        load ++ [field_name]
      end

    {select, new_load, template ++ [{field_name, nested_template}]}
  end

  defp process_embedded_resource(
         resource,
         field_name,
         nested_fields,
         path,
         select,
         load,
         template
       ) do
    validate_non_empty_fields(nested_fields, field_name, path, "EmbeddedResource")
    attribute = Ash.Resource.Info.attribute(resource, field_name)
    embedded_resource = extract_embedded_resource_type(attribute.type)
    new_path = path ++ [field_name]

    {_ns, nested_load, nested_template} =
      process_resource_fields(embedded_resource, nested_fields, new_path)

    new_select = select ++ [field_name]
    new_load = if nested_load != [], do: load ++ [{field_name, nested_load}], else: load
    {new_select, new_load, template ++ [{field_name, nested_template}]}
  end

  defp extract_embedded_resource_type({:array, embedded_resource}), do: embedded_resource
  defp extract_embedded_resource_type(embedded_resource), do: embedded_resource

  defp process_typed_struct(resource, field_name, nested_fields, path, select, load, template) do
    validate_non_empty_fields(nested_fields, field_name, path, "TypedStruct")
    attribute = Ash.Resource.Info.attribute(resource, field_name)
    field_specs = Keyword.get(attribute.constraints, :fields, [])
    new_path = path ++ [field_name]
    {_names, template_items} = process_typed_struct_fields(nested_fields, field_specs, new_path)
    {select ++ [field_name], load, template ++ [{field_name, template_items}]}
  end

  defp process_typed_struct_fields(requested_fields, field_specs, path) do
    check_for_duplicate_fields(requested_fields, path)

    Enum.reduce(requested_fields, {[], []}, fn field, {names, template} ->
      case field do
        field_atom when is_atom(field_atom) or is_binary(field_atom) ->
          field_atom =
            if is_binary(field_atom), do: String.to_existing_atom(field_atom), else: field_atom

          if Keyword.has_key?(field_specs, field_atom),
            do: {names ++ [field_atom], template ++ [field_atom]},
            else: throw_unknown("typed_struct", path, field_atom)

        %{} = field_map ->
          Enum.reduce(field_map, {names, template}, fn {fname, nested}, {n, t} ->
            if Keyword.has_key?(field_specs, fname) do
              field_spec = Keyword.get(field_specs, fname)
              field_type = Keyword.get(field_spec, :type)
              field_constraints = Keyword.get(field_spec, :constraints, [])
              field_return_type = {:ash_type, field_type, field_constraints}
              new_path = path ++ [fname]

              {_ns, _nl, nested_template} =
                process_fields_for_type(field_return_type, nested, new_path)

              {n ++ [fname], t ++ [{fname, nested_template}]}
            else
              throw_unknown("typed_struct", path, fname)
            end
          end)
      end
    end)
  end

  defp process_union_attribute(resource, field_name, nested_fields, path, select, load, template) do
    normalized_fields =
      case nested_fields do
        %{} = field_map when map_size(field_map) > 0 -> [field_map]
        fields when is_list(fields) -> fields
        _ -> nested_fields
      end

    validate_non_empty_fields(normalized_fields, field_name, path, "Union")
    check_for_duplicate_fields(normalized_fields, path ++ [field_name])

    attribute = Ash.Resource.Info.attribute(resource, field_name)
    union_types = get_union_types(attribute)

    {load_items, template_items} =
      Enum.reduce(normalized_fields, {[], []}, fn field_item, {load_acc, template_acc} ->
        case field_item do
          member when is_atom(member) ->
            if Keyword.has_key?(union_types, member) do
              member_config = Keyword.get(union_types, member)
              member_return_type = union_member_to_return_type(member_config)

              case member_return_type do
                {:ash_type, map_like, constraints}
                when map_like in [Ash.Type.Map, Ash.Type.Keyword, Ash.Type.Tuple] ->
                  field_specs = Keyword.get(constraints, :fields, [])

                  if field_specs != [],
                    do: throw_requires(path ++ [field_name], member, :complex_type),
                    else: {load_acc, template_acc ++ [member]}

                {:ash_type, _type, _} ->
                  {load_acc, template_acc ++ [member]}

                {:resource, _} ->
                  throw_requires(path ++ [field_name], member, :complex_type)
              end
            else
              throw_unknown("union_attribute", path ++ [field_name], member)
            end

          %{} = member_map ->
            Enum.reduce(member_map, {load_acc, template_acc}, fn {member, member_fields},
                                                                 {l_acc, t_acc} ->
              if Keyword.has_key?(union_types, member) do
                member_config = Keyword.get(union_types, member)
                member_return_type = union_member_to_return_type(member_config)
                new_path = path ++ [field_name, member]

                {_ns, nested_load, nested_template} =
                  process_fields_for_type(member_return_type, member_fields, new_path)

                combined_load_fields =
                  case member_return_type do
                    {:resource, _} -> nested_load
                    _ -> []
                  end

                if combined_load_fields != [] do
                  {l_acc ++ [{member, combined_load_fields}], t_acc ++ [{member, nested_template}]}
                else
                  {l_acc, t_acc ++ [{member, nested_template}]}
                end
              else
                throw_unknown("union_attribute", path ++ [field_name], member)
              end
            end)

          _ ->
            throw_invalid_union(path, field_name)
        end
      end)

    new_select = select ++ [field_name]
    new_load = if load_items != [], do: load ++ [{field_name, load_items}], else: load
    {new_select, new_load, template ++ [{field_name, template_items}]}
  end

  defp process_calculation_with_args(
         _resource,
         field_name,
         nested_fields,
         path,
         select,
         load,
         template
       ) do
    valid? =
      case nested_fields do
        %{} = m -> Map.has_key?(m, :args) or Map.has_key?(m, "args")
        list when is_list(list) -> Enum.any?(list, &is_map/1)
        _ -> false
      end

    unless valid? do
      throw_invalid_nesting(path, field_name)
    end

    {select ++ [field_name], load, template ++ [field_name]}
  end

  defp process_complex_aggregate(
         _resource,
         field_name,
         nested_fields,
         path,
         select,
         load,
         template
       ) do
    validate_non_empty_fields(nested_fields, field_name, path, "Aggregate")

    {_, _, nested_template} =
      process_generic_fields(List.wrap(nested_fields), path ++ [field_name])

    {select, load ++ [field_name], template ++ [{field_name, nested_template}]}
  end

  defp throw_invalid_union(path, field_name),
    do: throw({:invalid_union_field_format, build_field_path(path, field_name)})

  defp get_union_types(attribute) do
    case attribute.type do
      Ash.Type.Union ->
        Keyword.get(attribute.constraints, :types, [])

      {:array, Ash.Type.Union} ->
        items_constraints = Keyword.get(attribute.constraints, :items, [])
        Keyword.get(items_constraints, :types, [])
    end
  end

  defp union_member_to_return_type(member_config) do
    case member_config do
      {:resource, res} -> {:resource, res}
      {:type, type, constraints} -> {:ash_type, type, constraints || []}
      _ -> :any
    end
  end

  defp classify_field(resource, field_name, _path) do
    cond do
      Ash.Resource.Info.attribute(resource, field_name) ->
        attribute = Ash.Resource.Info.attribute(resource, field_name)
        classify_ash_type(attribute.type, attribute, match?({:array, _}, attribute.type))

      calc = Ash.Resource.Info.calculation(resource, field_name) ->
        if accepts_arguments?(calc), do: :calculation_with_args, else: :calculation

      agg = Ash.Resource.Info.aggregate(resource, field_name) ->
        if agg.kind in [:first, :list], do: :complex_aggregate, else: :aggregate

      Ash.Resource.Info.relationship(resource, field_name) ->
        :relationship

      true ->
        {:error, :not_found}
    end
  end

  defp classify_ash_type(type_module, attribute, is_array) do
    cond do
      type_module == Ash.Type.Union ->
        :union_attribute

      is_embedded?(type_module) ->
        if is_array, do: :embedded_resource_array, else: :embedded_resource

      type_module == Ash.Type.Tuple ->
        :tuple

      is_typed_struct?(attribute) ->
        :typed_struct

      type_module in [Ash.Type.Keyword, Ash.Type.Tuple] ->
        :typed_struct

      true ->
        :attribute
    end
  end

  defp accepts_arguments?(calculation) do
    case calculation.arguments do
      [] -> false
      nil -> false
      args when is_list(args) -> length(args) > 0
    end
  end

  defp is_embedded?(type),
    do: Ash.Resource.Info.resource?(type) and Ash.Resource.Info.embedded?(type)

  defp is_typed_struct?(attribute) do
    constraints = attribute.constraints || []

    with true <- Keyword.has_key?(constraints, :fields),
         true <- Keyword.has_key?(constraints, :instance_of),
         instance_of when is_atom(instance_of) <- Keyword.get(constraints, :instance_of) do
      true
    else
      _ -> false
    end
  end

  defp validate_non_empty_fields(nested_fields, field_name, path, kind) do
    valid =
      (is_list(nested_fields) and nested_fields != []) or
        (is_map(nested_fields) and map_size(nested_fields) > 0)

    unless valid, do: throw({:invalid_field_selection, kind, build_field_path(path, field_name)})
  end

  defp check_for_duplicate_fields(fields, path) do
    field_names =
      Enum.flat_map(fields, fn field ->
        case field do
          field_name when is_atom(field_name) ->
            [field_name]

          field_name when is_binary(field_name) ->
            try do
              [String.to_existing_atom(field_name)]
            rescue
              _ -> throw({:invalid_field_type, field_name, path})
            end

          %{} = field_map ->
            Map.keys(field_map)

          {fname, _} ->
            [fname]

          invalid_field ->
            throw({:invalid_field_type, invalid_field, path})
        end
      end)

    duplicate_fields =
      field_names
      |> Enum.frequencies()
      |> Enum.filter(fn {_f, c} -> c > 1 end)
      |> Enum.map(fn {f, _} -> f end)

    if duplicate_fields != [] do
      duplicate_field = hd(duplicate_fields)
      throw({:duplicate_field, duplicate_field, build_field_path(path, duplicate_field)})
    end
  end

  defp build_field_path(path, field_name) do
    all_parts = path ++ [field_name]
    formatter = AshRpc.Config.Config.output_field_formatter()

    case all_parts do
      [single] ->
        AshRpc.Input.FieldFormatter.format_field(single, formatter)

      [first | rest] ->
        formatted_first = AshRpc.Input.FieldFormatter.format_field(first, formatter)

        formatted_rest =
          Enum.map_join(rest, ".", &AshRpc.Input.FieldFormatter.format_field(&1, formatter))

        formatted_first <> "." <> formatted_rest

      _ ->
        to_string(field_name)
    end
  end

  defp throw_requires(path, field_name, type),
    do: throw({:requires_field_selection, type, build_field_path(path, field_name)})

  defp throw_unknown(resource, path, field_name),
    do: throw({:unknown_field, field_name, resource, build_field_path(path, field_name)})

  defp throw_invalid_nesting(path, field_name),
    do: throw({:invalid_calculation_args, field_name, build_field_path(path, field_name)})

  defp throw_invalid_simple(path, field_name),
    do:
      throw(
        {:invalid_field_selection, field_name, :simple_field, build_field_path(path, field_name)}
      )

  defp throw_invalid_aggregate(path, field_name),
    do:
      throw({:invalid_field_selection, field_name, :aggregate, build_field_path(path, field_name)})

  defp throw_field_no_nesting(path, field_name),
    do: throw({:field_does_not_support_nesting, build_field_path(path, field_name)})

  defp throw_invalid_tuple(path, field_name),
    do: throw({:invalid_field_selection, field_name, :tuple, build_field_path(path, field_name)})

  defp atomize_field(field, formatter) do
    case field do
      field_name when is_binary(field_name) ->
        AshRpc.Input.FieldFormatter.parse_input_field(field_name, formatter)

      field_name when is_atom(field_name) ->
        field_name

      %{} = field_map ->
        Enum.into(field_map, %{}, fn {key, value} ->
          atom_key =
            case key do
              k when is_binary(k) -> AshRpc.Input.FieldFormatter.parse_input_field(k, formatter)
              k when is_atom(k) -> k
            end

          {atom_key, atomize_field_value(value, formatter)}
        end)

      other ->
        other
    end
  end

  defp atomize_field_value(value, formatter) do
    case value do
      list when is_list(list) -> Enum.map(list, &atomize_field(&1, formatter))
      %{} = map -> atomize_field(map, formatter)
      primitive -> primitive
    end
  end

  defp format_extraction_template(template) do
    {atoms, keyword_pairs} =
      Enum.reduce(template, {[], []}, fn item, {atoms, kw_pairs} ->
        case item do
          {key, value} when is_atom(key) and is_map(value) ->
            {atoms, kw_pairs ++ [{key, value}]}

          {key, value} when is_atom(key) ->
            {atoms, kw_pairs ++ [{key, format_extraction_template(value)}]}

          atom when is_atom(atom) ->
            {atoms ++ [atom], kw_pairs}

          other ->
            {atoms ++ [other], kw_pairs}
        end
      end)

    atoms ++ keyword_pairs
  end
end
