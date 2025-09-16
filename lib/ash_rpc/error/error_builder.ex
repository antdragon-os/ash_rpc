defmodule AshRpc.Error.ErrorBuilder do
  @moduledoc """
  Comprehensive error handling and message generation for the AshRpc pipeline.

  Provides clear, actionable error messages for all failure modes with
  detailed context for debugging and client consumption.

  Based on the proven architecture from ash_typescript.
  """

  @doc """
  Builds a detailed error response from various error types.

  Converts internal error tuples into structured error responses
  with clear messages and debugging context.
  """
  @spec build_error_response(term()) :: map()
  def build_error_response(error) do
    case error do
      # Action discovery errors
      {:action_not_found, action_name} ->
        %{
          type: "action_not_found",
          message: "RPC action '#{action_name}' not found",
          details: %{
            action_name: action_name,
            suggestion: "Check that the action is properly configured in your resource"
          }
        }

      # Tenant resolution errors
      {:tenant_required, resource} ->
        %{
          type: "tenant_required",
          message: "Tenant parameter is required for multitenant resource #{inspect(resource)}",
          details: %{
            resource: inspect(resource),
            suggestion: "Add a 'tenant' parameter to your request"
          }
        }

      # Field validation errors
      {:invalid_fields, field_error} ->
        build_error_response(field_error)

      # Direct field error from RequestedFieldsProcessor
      %{type: :invalid_field, field: field_name} ->
        %{
          type: "invalid_field",
          message: "Invalid field '#{field_name}'",
          field: field_name
        }

      # === FIELD VALIDATION ERRORS WITH FIELD PATHS ===

      # Unknown field errors
      {:unknown_field, _field_atom, "map", field_path} ->
        %{
          type: "unknown_field",
          message: "Unknown field '#{field_path}' in map type",
          field: field_path,
          suggestion: "Check the available fields for this map type"
        }

      {:unknown_field, _field_atom, "tuple", field_path} ->
        %{
          type: "unknown_field",
          message: "Unknown field '#{field_path}' in tuple type",
          field: field_path,
          suggestion: "Check the available fields for this tuple type"
        }

      {:unknown_field, _field_atom, "typed_struct", field_path} ->
        %{
          type: "unknown_field",
          message: "Unknown field '#{field_path}' in typed struct",
          field: field_path,
          suggestion: "Check the available fields for this typed struct"
        }

      {:unknown_field, _field_atom, "union_attribute", field_path} ->
        %{
          type: "unknown_field",
          message: "Unknown union member '#{field_path}'",
          field: field_path,
          suggestion: "Check the available union members for this field"
        }

      {:unknown_field, field_atom, resource, field_path} ->
        %{
          type: "unknown_field",
          message: "Unknown field '#{field_path}' on resource #{inspect(resource)}",
          field: field_path,
          resource: inspect(resource),
          field_name: field_atom,
          suggestion:
            "Check the available public fields, relationships, calculations, and aggregates"
        }

      # Field selection requirement errors
      {:requires_field_selection, field_type, field_path} ->
        type_description = format_field_type_description(field_type)

        %{
          type: "requires_field_selection",
          message: "#{type_description} '#{field_path}' requires field selection",
          field: field_path,
          field_type: field_type,
          suggestion: "Provide a select array to specify which nested fields to include"
        }

      # Invalid field selection errors
      {:invalid_field_selection, field_name, :simple_field, field_path} ->
        %{
          type: "invalid_field_selection",
          message:
            "Field '#{field_path}' is a simple field and doesn't support nested field selection",
          field: field_path,
          field_name: field_name,
          suggestion: "Remove the nested field specification for simple fields"
        }

      {:invalid_field_selection, field_name, :aggregate, field_path} ->
        %{
          type: "invalid_field_selection",
          message:
            "Aggregate '#{field_path}' returns a primitive type and doesn't support nested field selection",
          field: field_path,
          field_name: field_name,
          suggestion: "Remove the nested field specification for primitive aggregates"
        }

      {:invalid_field_selection, field_name, :calculation, field_path} ->
        %{
          type: "invalid_field_selection",
          message:
            "Calculation '#{field_path}' returns a primitive type and doesn't support field selection",
          field: field_path,
          field_name: field_name,
          suggestion: "Remove the select parameter for primitive calculations"
        }

      {:invalid_field_selection, field_name, :tuple, field_path} ->
        %{
          type: "invalid_field_selection",
          message:
            "Tuple field '#{field_path}' doesn't support nested field selection in this context",
          field: field_path,
          field_name: field_name,
          suggestion: "Use simple field names for tuple field selection"
        }

      {:invalid_field_selection, kind, field_path} ->
        %{
          type: "invalid_field_selection",
          message: "Invalid field selection for #{kind} at '#{field_path}'",
          field: field_path,
          field_type: kind
        }

      # Calculation argument errors
      {:calculation_requires_args, field_name, field_path} ->
        %{
          type: "calculation_requires_args",
          message: "Calculation '#{field_path}' requires arguments",
          field: field_path,
          field_name: field_name,
          suggestion: "Provide arguments using the format: {\"#{field_name}\": {\"args\": {...}}}"
        }

      {:invalid_calculation_args, field_name, field_path} ->
        %{
          type: "invalid_calculation_args",
          message: "Invalid arguments format for calculation '#{field_path}'",
          field: field_path,
          field_name: field_name,
          suggestion: "Use the format: {\"#{field_name}\": {\"args\": {...}, \"select\": [...]}}"
        }

      # Field nesting errors
      {:field_does_not_support_nesting, field_path} ->
        %{
          type: "field_does_not_support_nesting",
          message: "Field '#{field_path}' does not support nested field selection",
          field: field_path,
          suggestion: "Remove the nested field specification for this field"
        }

      # Duplicate field errors
      {:duplicate_field, field_name, field_path} ->
        %{
          type: "duplicate_field",
          message: "Duplicate field '#{field_name}' in field selection at '#{field_path}'",
          field: field_path,
          field_name: field_name,
          suggestion: "Remove duplicate field specifications"
        }

      # Union field format errors
      {:invalid_union_field_format, field_path} ->
        %{
          type: "invalid_union_field_format",
          message: "Invalid union field format at '#{field_path}'",
          field: field_path,
          suggestion: "Use format: [:member_name] or {\"member_name\": [\"field1\", \"field2\"]}"
        }

      # Field type errors
      {:invalid_field_type, field_value, path} ->
        %{
          type: "invalid_field_type",
          message: "Invalid field type '#{inspect(field_value)}' at path '#{format_path(path)}'",
          field_value: inspect(field_value),
          path: format_path(path),
          suggestion: "Field names should be strings or atoms"
        }

      # Unsupported field combination errors
      {:unsupported_field_combination, field_type, field_name, field_value, field_path} ->
        %{
          type: "unsupported_field_combination",
          message:
            "Unsupported field combination for #{field_type} '#{field_name}' at '#{field_path}'",
          field: field_path,
          field_name: field_name,
          field_type: field_type,
          field_value: inspect(field_value),
          suggestion: "Check the supported field selection format for this field type"
        }

      # Missing required parameter errors
      {:missing_required_parameter, param_name} ->
        %{
          type: "missing_required_parameter",
          message: "Missing required parameter '#{param_name}'",
          parameter: param_name,
          suggestion: "Add the required parameter to your request"
        }

      # === ASH FRAMEWORK ERRORS ===

      # NotFound errors
      %Ash.Error.Query.NotFound{} = not_found_error ->
        %{
          type: "not_found",
          message: Exception.message(not_found_error),
          details: %{
            resource: not_found_error.resource,
            primary_key: not_found_error.primary_key
          }
        }

      # Forbidden errors
      %Ash.Error.Forbidden{} = forbidden_error ->
        %{
          type: "forbidden",
          message: Exception.message(forbidden_error),
          details: %{
            resource: "unknown",
            action: "unknown"
          }
        }

      # Invalid errors with nested errors
      %Ash.Error.Invalid{errors: errors} = invalid_error when is_list(errors) ->
        case Enum.find(errors, &is_struct(&1, Ash.Error.Query.NotFound)) do
          %Ash.Error.Query.NotFound{} = not_found_error ->
            build_error_response(not_found_error)

          _ ->
            build_ash_error_response(invalid_error)
        end

      # Check for NotFound errors nested inside other Ash errors
      %{class: :invalid, errors: errors} = ash_error when is_list(errors) ->
        case Enum.find(errors, &is_struct(&1, Ash.Error.Query.NotFound)) do
          %Ash.Error.Query.NotFound{} = not_found_error ->
            %{
              type: "not_found",
              message: Exception.message(not_found_error),
              details: %{
                resource: not_found_error.resource,
                primary_key: not_found_error.primary_key
              }
            }

          _ ->
            build_ash_error_response(ash_error)
        end

      # Generic Ash errors
      %{class: _class} = ash_error ->
        build_ash_error_response(ash_error)

      # === FALLBACK ERROR HANDLERS ===

      {field_error_type, _} when is_atom(field_error_type) ->
        %{
          type: "field_validation_error",
          message: "Field validation error: #{field_error_type}",
          details: %{
            error: inspect(error)
          }
        }

      other ->
        %{
          type: "unknown_error",
          message: "An unexpected error occurred",
          details: %{
            error: inspect(other)
          }
        }
    end
  end

  # Extract form validation errors from Ash errors for structured frontend consumption
  defp extract_form_validation_errors(errors) when is_list(errors) do
    errors
    |> Enum.flat_map(&flatten_nested_errors/1)
    |> Enum.filter(fn error ->
      # Look for common Ash validation error types
      is_struct(error, Ash.Error.Changes.InvalidAttribute) or
        is_struct(error, Ash.Error.Changes.InvalidChanges) or
        is_struct(error, Ash.Error.Changes.InvalidArgument) or
        is_struct(error, Ash.Error.Changes.Required) or
        (is_map(error) and Map.get(error, :field))
    end)
    |> Enum.reduce(%{}, fn error, acc ->
      field_name = extract_field_name(error)
      error_message = extract_clean_error_message(error)

      # Group errors by field name
      Map.update(acc, field_name, [error_message], &(&1 ++ [error_message]))
    end)
  end

  # Flatten nested errors from InvalidChanges structures
  defp flatten_nested_errors(%Ash.Error.Changes.InvalidChanges{} = error) do
    # Try to access nested errors through available fields
    nested_errors = Map.get(error, :errors) || Map.get(error, :changes) || []
    fields = Map.get(error, :fields)

    cond do
      # If there are nested errors, flatten them
      is_list(nested_errors) and length(nested_errors) > 0 ->
        [error] ++ Enum.flat_map(nested_errors, &flatten_nested_errors/1)

      # If there are field-specific errors, convert them to InvalidAttribute errors
      is_map(fields) and map_size(fields) > 0 ->
        field_errors =
          Enum.flat_map(fields, fn {field, messages} ->
            message_list = if is_list(messages), do: messages, else: [messages]

            Enum.map(message_list, fn message ->
              %Ash.Error.Changes.InvalidAttribute{
                field: field,
                message: message
              }
            end)
          end)

        field_errors ++ [error]

      # No nested errors, just return the error
      true ->
        [error]
    end
  end

  defp flatten_nested_errors(error), do: [error]

  # Extract clean validation message from Ash errors using proper Ash API
  defp extract_clean_error_message(error) when is_struct(error) do
    cond do
      # For Ash validation errors, use the error's message field directly
      # This avoids the verbose breadcrumbs from Exception.message/1
      function_exported?(error.__struct__, :message, 0) and Map.has_key?(error, :message) ->
        case error.message do
          msg when is_binary(msg) and msg != "" ->
            msg
            |> String.trim()
            |> String.trim_trailing(".")

          _ ->
            # If message is empty, try the full exception message
            Exception.message(error)
            |> extract_clean_message_from_string()
        end

      # Handle InvalidChanges errors that might have nested errors
      is_struct(error, Ash.Error.Changes.InvalidChanges) ->
        # Try to access nested errors through the struct's fields
        # Different Ash versions might have different field names
        nested_errors = Map.get(error, :errors) || Map.get(error, :changes) || []
        fields = Map.get(error, :fields)

        cond do
          # If there are nested errors, extract their messages
          is_list(nested_errors) and length(nested_errors) > 0 ->
            nested_messages = Enum.map(nested_errors, &extract_nested_error_message/1)
            Enum.join(nested_messages, "; ")

          # If there are field-specific errors, extract them
          is_map(fields) and map_size(fields) > 0 ->
            field_messages =
              Enum.map(fields, fn {field, messages} ->
                if is_list(messages) do
                  "#{field}: #{Enum.join(messages, ", ")}"
                else
                  "#{field}: #{messages}"
                end
              end)

            Enum.join(field_messages, "; ")

          # Fallback to the error's message or exception message
          true ->
            if Map.get(error, :message) && Map.get(error, :message) != "" do
              Map.get(error, :message)
            else
              Exception.message(error)
              |> extract_clean_message_from_string()
            end
        end

      # Fallback to Exception.message for other error types
      true ->
        Exception.message(error)
        |> extract_clean_message_from_string()
    end
  end

  defp extract_clean_error_message(error), do: Exception.message(error)

  # Extract message from nested errors within InvalidChanges
  defp extract_nested_error_message(error) when is_struct(error) do
    cond do
      # Check for message field first
      Map.has_key?(error, :message) and is_binary(error.message) ->
        error.message

      # Handle specific validation error types
      is_struct(error, Ash.Error.Changes.InvalidAttribute) ->
        field = Map.get(error, :field, "unknown_field")
        "Invalid value for #{field}"

      is_struct(error, Ash.Error.Changes.Required) ->
        field = Map.get(error, :field, "unknown_field")
        "#{field} is required"

      # Try Exception.message as fallback
      true ->
        Exception.message(error)
    end
  end

  defp extract_nested_error_message(error), do: inspect(error)

  # Extract clean message from string (fallback for non-Ash errors)
  defp extract_clean_message_from_string(message) when is_binary(message) do
    # For Ash errors, look for the actual validation message pattern
    case Regex.run(~r/Invalid value provided for [^:]+: ([^\n\.]+)/, message) do
      [_, clean_message] ->
        clean_message
        |> String.trim()

      _ ->
        # Look for other Ash error patterns
        case Regex.run(~r/: ([^\n\.]+)(?:\.|\n)/, message) do
          [_, clean_message] -> String.trim(clean_message)
          _ -> message
        end
    end
  end

  defp extract_field_name(%{field: field}) when not is_nil(field), do: to_string(field)
  defp extract_field_name(%{attribute: attr}) when not is_nil(attr), do: to_string(attr)
  defp extract_field_name(%{argument: arg}) when not is_nil(arg), do: to_string(arg)
  defp extract_field_name(_), do: "general"

  # Check if errors contain form validation errors that should be structured
  defp has_form_validation_errors?(errors) when is_list(errors) do
    Enum.any?(errors, fn error ->
      is_struct(error, Ash.Error.Changes.InvalidAttribute) or
        is_struct(error, Ash.Error.Changes.InvalidChanges) or
        is_struct(error, Ash.Error.Changes.InvalidArgument) or
        (is_map(error) and Map.get(error, :field))
    end)
  end

  defp has_form_validation_errors?(_), do: false

  # Build error responses for Ash framework errors
  defp build_ash_error_response(ash_error) when is_exception(ash_error) do
    # Extract form validation errors if they exist
    form_errors =
      if has_form_validation_errors?(ash_error.errors || []) do
        extract_form_validation_errors(ash_error.errors)
      else
        %{}
      end

    base_response = %{
      type: "ash_error",
      message: extract_clean_error_message(ash_error),
      details: %{
        class: ash_error.class,
        errors: serialize_nested_errors(ash_error.errors || []),
        path: ash_error.path || []
      }
    }

    # Add form validation structure if we have form errors
    if map_size(form_errors) > 0 do
      Map.put(base_response, :form, form_errors)
    else
      base_response
    end
  end

  defp build_ash_error_response(ash_error) do
    %{
      type: "ash_error",
      message: inspect(ash_error),
      details: %{
        error: inspect(ash_error)
      }
    }
  end

  defp serialize_nested_errors(errors) when is_list(errors) do
    Enum.map(errors, &serialize_single_error/1)
  end

  defp serialize_single_error(error) when is_exception(error) do
    %{
      type: error.__struct__ |> Module.split() |> List.last(),
      message: extract_clean_error_message(error)
    }
  end

  defp serialize_single_error(error) do
    %{
      type: "unknown",
      message: inspect(error)
    }
  end

  defp format_field_type_description(field_type) do
    case field_type do
      :relationship -> "Relationship"
      :embedded_resource -> "Embedded resource"
      :embedded_resource_array -> "Embedded resource array"
      :calculation_complex -> "Complex calculation"
      :complex_aggregate -> "Complex aggregate"
      :tuple -> "Tuple"
      :typed_struct -> "Typed struct"
      :union_attribute -> "Union attribute"
      :complex_type -> "Complex type"
      _ -> "Field"
    end
  end

  defp format_path([]), do: "root"

  defp format_path(path) when is_list(path) do
    Enum.join(path, ".")
  end

  defp format_path(path), do: to_string(path)
end
