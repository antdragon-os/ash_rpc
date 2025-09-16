defmodule AshRpc.TypeScript.ZodGenerator do
  @moduledoc """
  Generates Zod schemas from Ash resources for client-side validation.
  """

  alias AshRpc.TypeScript.ResourceUtils

  @doc """
  Generates Zod schemas for all resources in the given domain.
  """
  def generate_domain_schemas(domain) do
    resources = Ash.Domain.Info.resources(domain)

    resources
    |> Enum.filter(&ResourceUtils.exposed_resource?/1)
    |> Enum.flat_map(fn res ->
      seg = ResourceUtils.resource_segment(res)
      procedures = ResourceUtils.safe_procedures(res)

      specs =
        if procedures == [] do
          res
          |> Ash.Resource.Info.actions()
          |> Enum.filter(&ResourceUtils.exposed_action?(res, &1))
          |> Enum.map(fn act ->
            %{name: act.name, action: act.name, method: method_override_or_default(res, act)}
          end)
        else
          Enum.map(procedures, fn p ->
            %{name: p.name, action: p.action, method: p.method}
          end)
        end

      action_schemas =
        Enum.map(specs, fn spec ->
          act = Ash.Resource.Info.action(res, spec.action)

          if act do
            generate_zod_schema(res, act, spec.name, spec.method)
          else
            nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      embedded_schemas = generate_zod_schemas_for_embedded_resources([])

      ["// Resource: #{inspect(res)} (#{seg})\n", action_schemas, "\n", embedded_schemas]
    end)
  end

  @doc """
  Generates Zod schemas for a single resource (used for nested structure).
  """
  def generate_domain_schemas_for_resource(resource) do
    procedures = ResourceUtils.safe_procedures(resource)

    specs =
      if procedures == [] do
        resource
        |> Ash.Resource.Info.actions()
        |> Enum.filter(&ResourceUtils.exposed_action?(resource, &1))
        |> Enum.map(fn act ->
          %{name: act.name, action: act.name, method: method_override_or_default(resource, act)}
        end)
      else
        Enum.map(procedures, fn p ->
          %{name: p.name, action: p.action, method: p.method}
        end)
      end

    Enum.map(specs, fn spec ->
      act = Ash.Resource.Info.action(resource, spec.action)

      if act do
        schema = generate_zod_schema(resource, act, spec.name, spec.method)
        if schema do
          "#{Macro.camelize(to_string(spec.name))}InputSchema: #{schema}"
        else
          nil
        end
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Generates Zod schema for a specific action.
  """
  def generate_zod_schema(resource, act, action_name, method \\ nil) do
    schema_name = "#{Macro.camelize(to_string(action_name))}InputSchema"

    # Use method override if provided, otherwise fall back to action type
    method_to_check = method || case act.type do
      :read -> :query
      :create -> :mutation
      :update -> :mutation
      :destroy -> :mutation
      :action -> :mutation
      _ -> :mutation
    end

    # Skip query operations - only generate schemas for mutations
    case method_to_check do
      :query ->
        nil  # Skip query operations

      :mutation ->
        generate_input_schema_only(resource, act, schema_name)
    end
  end

  @doc """
  Generates Zod schemas for embedded resources.
  """
  def generate_zod_schemas_for_embedded_resources(embedded_resources) do
    # For now, return empty - embedded resource support can be added later
    embedded_resources
    |> Enum.map(fn _embedded ->
      "// Embedded resource schemas would go here"
    end)
    |> Enum.join("\n")
  end

  # Private functions for generating different action types
  # Read operations are skipped - no schema generation

  defp generate_input_schema_only(resource, act, _schema_name) do
    # Get the field definitions without the z.object wrapper
    fields = case act.type do
      :read -> get_action_field_definitions(resource, act)  # Read actions can have arguments too
      :create -> get_create_field_definitions(resource, act)
      :update -> get_update_field_definitions(resource, act)
      :destroy -> get_destroy_field_definitions(resource, act)
      :action -> get_action_field_definitions(resource, act)
    end

    if fields == [] do
      "z.object({})"
    else
      field_lines = Enum.join(fields, ",\n  ")
      "z.object({\n  #{field_lines}\n})"
    end
  end


  # Helper functions to get field definitions without z.object wrapper

  defp get_create_field_definitions(resource, act) do
    args = act.arguments || []
    accepted_attrs = Map.get(act, :accept) || []

    arg_fields = Enum.map(args, fn arg ->
      type = zod_type_with_validation(arg.type, arg.name)
      optional = if arg.allow_nil?, do: ".optional()", else: ""
      "#{arg.name}: #{type}#{optional}"
    end)

    attr_fields = if accepted_attrs == [] do
      []
    else
      accepted_attrs
      |> Enum.map(fn attr_name ->
        case Ash.Resource.Info.attribute(resource, attr_name) do
          nil -> nil
          attr ->
            type = zod_type_with_validation(attr.type, attr_name)
            optional = if attr.allow_nil?, do: ".optional()", else: ""
            "#{attr_name}: #{type}#{optional}"
        end
      end)
      |> Enum.reject(&is_nil/1)
    end

    arg_fields ++ attr_fields
  end

  defp get_update_field_definitions(resource, act) do
    args = act.arguments || []
    accepted_attrs = Map.get(act, :accept) || []

    arg_fields = Enum.map(args, fn arg ->
      type = zod_type_with_validation(arg.type, arg.name)
      optional = if arg.allow_nil?, do: ".optional()", else: ""
      "#{arg.name}: #{type}#{optional}"
    end)

    attr_fields = if accepted_attrs == [] do
      []
    else
      accepted_attrs
      |> Enum.map(fn attr_name ->
        case Ash.Resource.Info.attribute(resource, attr_name) do
          nil -> nil
          attr ->
            type = zod_type_with_validation(attr.type, attr_name)
            # Updates make all fields optional
            "#{attr_name}: #{type}.optional()"
        end
      end)
      |> Enum.reject(&is_nil/1)
    end

    # Primary keys are always required for updates
    pk_fields = resource
                |> Ash.Resource.Info.primary_key()
                |> Enum.map(fn pk_name ->
                  case Ash.Resource.Info.attribute(resource, pk_name) do
                    nil -> nil
                    attr ->
                      type = zod_type_with_validation(attr.type, pk_name)
                      "#{pk_name}: #{type}"
                  end
                end)
                |> Enum.reject(&is_nil/1)

    arg_fields ++ attr_fields ++ pk_fields
  end

  defp get_destroy_field_definitions(resource, act) do
    args = act.arguments || []

    arg_fields = Enum.map(args, fn arg ->
      type = zod_type_with_validation(arg.type, arg.name)
      optional = if arg.allow_nil?, do: ".optional()", else: ""
      "#{arg.name}: #{type}#{optional}"
    end)

    # Primary keys are always required for destroy
    pk_fields = resource
                |> Ash.Resource.Info.primary_key()
                |> Enum.map(fn pk_name ->
                  case Ash.Resource.Info.attribute(resource, pk_name) do
                    nil -> nil
                    attr ->
                      type = zod_type_with_validation(attr.type, pk_name)
                      "#{pk_name}: #{type}"
                  end
                end)
                |> Enum.reject(&is_nil/1)

    arg_fields ++ pk_fields
  end

  defp get_action_field_definitions(_resource, act) do
    args = act.arguments || []

    Enum.map(args, fn arg ->
      type = zod_type_with_validation(arg.type, arg.name)
      optional = if arg.allow_nil?, do: ".optional()", else: ""
      "#{arg.name}: #{type}#{optional}"
    end)
  end

  # Read operations are skipped - no input schema generation needed




  # Type conversion utilities with smart validation
  defp zod_type_with_validation(type, field_name) do
    base_type = zod_type(type)

    # Add smart validations based on field name (using current Zod API)
    field_name_str = to_string(field_name)

    cond do
      # Password fields
      String.contains?(field_name_str, "password") ->
        "#{base_type}.min(1)"

      # Email fields - use regex instead of deprecated .email()
      String.contains?(field_name_str, "email") and (type in [:string, String, Ash.Type.String, :ci_string, Ash.Type.CiString]) ->
        "#{base_type}.regex(/^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$/)"  # Basic email regex

      # Name fields
      String.contains?(field_name_str, "name") and type in [:string, String, Ash.Type.String, :ci_string, Ash.Type.CiString] ->
        "#{base_type}.min(1)"

      # URL fields
      String.contains?(field_name_str, "url") ->
        "#{base_type}.url()"

      # Phone fields
      String.contains?(field_name_str, "phone") ->
        "#{base_type}.regex(/^[+]?[\\d\\s\\-\\(\\)]+$/)"

      # Username fields
      String.contains?(field_name_str, "username") and type in [:string, String, Ash.Type.String, :ci_string, Ash.Type.CiString] ->
        "#{base_type}.min(3).max(50)"

      # Description fields
      String.contains?(field_name_str, "description") and type in [:string, String, Ash.Type.String, :ci_string, Ash.Type.CiString] ->
        "#{base_type}.max(1000)"

      # Title fields
      String.contains?(field_name_str, "title") and type in [:string, String, Ash.Type.String, :ci_string, Ash.Type.CiString] ->
        "#{base_type}.min(1).max(255)"

      # Age fields
      String.contains?(field_name_str, "age") and type in [:integer, Integer, Ash.Type.Integer] ->
        "#{base_type}.min(0).max(150)"

      # Price/cost fields
      (String.contains?(field_name_str, "price") or String.contains?(field_name_str, "cost")) and type in [:float, Float, Ash.Type.Float] ->
        "#{base_type}.min(0)"

      # Quantity fields
      String.contains?(field_name_str, "quantity") and type in [:integer, Integer, Ash.Type.Integer] ->
        "#{base_type}.min(0)"

      # Percentage fields
      String.contains?(field_name_str, "percent") and type in [:float, Float, Ash.Type.Float] ->
        "#{base_type}.min(0).max(100)"

      # IP address fields
      String.contains?(field_name_str, "ip") ->
        "#{base_type}.regex(/^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$/)"

      # Postal code fields
      String.contains?(field_name_str, "postal") or String.contains?(field_name_str, "zip") ->
        "#{base_type}.regex(/^\\d{5}(-\\d{4})?$/)"  # US postal code format

      # Date fields - could use z.date() if parsing dates
      type in [:date, Date, Ash.Type.Date] and (String.contains?(field_name_str, "birth") or String.contains?(field_name_str, "dob")) ->
        "#{base_type}.regex(/^\\d{4}-\\d{2}-\\d{2}$/)"  # ISO date format

      # Time fields
      type in [:time, Time, Ash.Type.Time] ->
        "#{base_type}.regex(/^\\d{2}:\\d{2}(:\\d{2})?$/)"  # HH:MM or HH:MM:SS format

      # Datetime fields
      type in [:datetime, NaiveDateTime, Ash.Type.NaiveDatetime] ->
        "#{base_type}.regex(/^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}(:\\d{2})?(\\.\\d{3})?(Z|[+-]\\d{2}:\\d{2})?$/)"  # ISO datetime format

      true ->
        base_type
    end
  end

  # Type conversion utilities - using current Zod API
  defp zod_type(type) do
    cond do
      type in [:string, String, Ash.Type.String, :ci_string, Ash.Type.CiString] ->
        "z.string()"

      type in [:integer, Integer, Ash.Type.Integer] ->
        "z.number().int()"

      type in [:float, Float, Ash.Type.Float] ->
        "z.number()"

      type in [:boolean, Boolean, Ash.Type.Boolean] ->
        "z.boolean()"

      type in [:date, Date, Ash.Type.Date] ->
        "z.string()"

      type in [:time, Time, Ash.Type.Time] ->
        "z.string()"

      type in [:datetime, NaiveDateTime, Ash.Type.NaiveDatetime] ->
        "z.string()"

      type in [:uuid, Ash.Type.UUID] ->
        "z.uuid()"  # Use z.uuid() instead of z.string().uuid()

      type in [:map, Map, Ash.Type.Map] ->
        "z.record(z.unknown())"

      function_exported?(Ash.Resource.Info, :resource?, 1) and Ash.Resource.Info.resource?(type) ->
        "z.record(z.unknown())"

      # Array types
      is_list(type) and is_tuple(type) ->
        case type do
          {:array, element_type} -> "z.array(#{zod_type(element_type)})"
          _ -> "z.array(z.unknown())"
        end

      is_list(type) ->
        "z.array(z.unknown())"

      # Union types (if Ash supports them)
      is_tuple(type) and elem(type, 0) == :union ->
        # Handle union types if available
        "z.union([z.string(), z.number()])"

      # Enum types
      is_atom(type) and String.starts_with?(to_string(type), "Elixir.") ->
        # If it's an enum module, we could potentially generate z.enum()
        # For now, default to string
        "z.string()"

      true ->
        "z.string()"  # Default to string
    end
  end

  defp method_override_or_default(resource, act) do
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
end
