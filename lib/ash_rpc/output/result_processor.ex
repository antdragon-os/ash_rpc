defmodule AshRpc.Output.ResultProcessor do
  @moduledoc false

  @spec process(term(), list()) :: term()
  def process(result, extraction_template) do
    case result do
      %Ash.Page.Offset{results: results} = page ->
        processed_results = extract_list_fields(results, extraction_template)

        # Only include essential pagination metadata
        %{
          results: processed_results,
          has_more: page.more? || false,
          limit: page.limit,
          offset: page.offset,
          count: page.count,
          type: :offset
        }

      %Ash.Page.Keyset{results: results} = page ->
        processed_results = extract_list_fields(results, extraction_template)

        # Only include essential pagination metadata
        %{
          results: processed_results,
          has_more: page.more? || false,
          limit: page.limit,
          type: :keyset
        }

      [] ->
        []

      result when is_list(result) ->
        if Keyword.keyword?(result) do
          extract_single_result(result, extraction_template)
        else
          extract_list_fields(result, extraction_template)
        end

      result ->
        extract_single_result(result, extraction_template)
    end
  end

  defp extract_list_fields(results, extraction_template) do
    if extraction_template == [] and Enum.any?(results, &(not is_map(&1))) do
      Enum.map(results, &normalize_value_for_json/1)
    else
      Enum.map(results, &extract_single_result(&1, extraction_template))
    end
  end

  defp extract_single_result(data, extraction_template) when is_list(extraction_template) do
    is_tuple = is_tuple(data)

    normalized_data =
      cond do
        is_tuple -> convert_tuple_to_map(data, extraction_template)
        Keyword.keyword?(data) -> Map.new(data)
        true -> normalize_data(data)
      end

    if is_tuple do
      normalized_data
    else
      Enum.reduce(extraction_template, %{}, fn field_spec, acc ->
        case field_spec do
          field_atom when is_atom(field_atom) ->
            extract_simple_field(normalized_data, field_atom, acc)

          {field_atom, nested_template} when is_atom(field_atom) and is_list(nested_template) ->
            extract_nested_field(normalized_data, field_atom, nested_template, acc)

          _ ->
            acc
        end
      end)
    end
  end

  defp extract_single_result(data, _template), do: normalize_data(data)

  defp extract_simple_field(normalized_data, field_atom, acc) do
    case Map.get(normalized_data, field_atom) do
      %Ash.ForbiddenField{} -> Map.put(acc, field_atom, nil)
      %Ash.NotLoaded{} -> acc
      value -> Map.put(acc, field_atom, normalize_value_for_json(value))
    end
  end

  defp extract_nested_field(normalized_data, field_atom, nested_template, acc) do
    nested_data = Map.get(normalized_data, field_atom)

    case nested_data do
      %Ash.ForbiddenField{} ->
        Map.put(acc, field_atom, nil)

      %Ash.NotLoaded{} ->
        acc

      nil ->
        Map.put(acc, field_atom, nil)

      nested_data ->
        nested_result = extract_nested_data(nested_data, nested_template)
        Map.put(acc, field_atom, nested_result)
    end
  end

  defp normalize_data(data) do
    case data do
      %_struct{} = struct_data ->
        # Convert struct to map but preserve __metadata__ if it exists
        base_map = Map.from_struct(struct_data)

        # Check if the original struct has __metadata__ and preserve it
        case Map.get(struct_data, :__metadata__) do
          nil -> base_map
          metadata -> Map.put(base_map, :__metadata__, metadata)
        end

      other ->
        other
    end
  end

  defp convert_tuple_to_map(tuple, extraction_template) do
    tuple_values = Tuple.to_list(tuple)

    Enum.reduce(extraction_template, %{}, fn %{field_name: field_name, index: index}, acc ->
      value = Enum.at(tuple_values, index)
      Map.put(acc, field_name, value)
    end)
  end

  def normalize_value_for_json(nil), do: nil

  def normalize_value_for_json(value) do
    case value do
      %Ash.Union{type: type_name, value: union_value} ->
        type_key = to_string(type_name)
        normalized_value = normalize_value_for_json(union_value)
        %{type_key => normalized_value}

      %DateTime{} = dt ->
        DateTime.to_iso8601(dt)

      %Date{} = date ->
        Date.to_iso8601(date)

      %Time{} = time ->
        Time.to_iso8601(time)

      %NaiveDateTime{} = ndt ->
        NaiveDateTime.to_iso8601(ndt)

      %Decimal{} = decimal ->
        Decimal.to_string(decimal)

      %Ash.CiString{} = ci_string ->
        to_string(ci_string)

      atom when is_atom(atom) and not is_nil(atom) and not is_boolean(atom) ->
        Atom.to_string(atom)

      %_struct{} = struct_data ->
        struct_data
        |> Map.from_struct()
        |> Enum.reduce(%{}, fn {key, val}, acc ->
          Map.put(acc, key, normalize_value_for_json(val))
        end)

      list when is_list(list) ->
        if Keyword.keyword?(list) do
          Enum.reduce(list, %{}, fn {key, val}, acc ->
            Map.put(acc, to_string(key), normalize_value_for_json(val))
          end)
        else
          Enum.map(list, &normalize_value_for_json/1)
        end

      map when is_map(map) and not is_struct(map) ->
        Enum.reduce(map, %{}, fn {key, val}, acc ->
          Map.put(acc, key, normalize_value_for_json(val))
        end)

      primitive ->
        primitive
    end
  end

  defp extract_nested_data(data, template) do
    case data do
      %Ash.ForbiddenField{} ->
        nil

      %Ash.NotLoaded{} ->
        nil

      nil ->
        nil

      list when is_list(list) and length(list) > 0 ->
        if Keyword.keyword?(list) do
          keyword_map = Enum.into(list, %{})
          extract_single_result(keyword_map, template)
        else
          Enum.map(list, fn item ->
            case item do
              %Ash.ForbiddenField{} ->
                nil

              %Ash.NotLoaded{} ->
                nil

              nil ->
                nil

              %Ash.Union{type: active_type, value: union_value} ->
                extract_union_fields(active_type, union_value, template)

              valid_item ->
                # This is the key fix - always call extract_single_result with template
                extract_single_result(valid_item, template)
            end
          end)
        end

      list when is_list(list) ->
        []

      %Ash.Union{type: active_type, value: union_value} ->
        extract_union_fields(active_type, union_value, template)

      single_item ->
        extract_single_result(single_item, template)
    end
  end

  defp extract_union_fields(active_type, union_value, template) do
    Enum.reduce(template, %{}, fn member_spec, acc ->
      case member_spec do
        member_atom when is_atom(member_atom) ->
          if member_atom == active_type,
            do: Map.put(acc, member_atom, normalize_value_for_json(union_value)),
            else: acc

        {member_atom, member_template} when is_atom(member_atom) ->
          if member_atom == active_type do
            extracted_fields = extract_single_result(union_value, member_template)
            Map.put(acc, member_atom, extracted_fields)
          else
            acc
          end

        _ ->
          acc
      end
    end)
  end
end
