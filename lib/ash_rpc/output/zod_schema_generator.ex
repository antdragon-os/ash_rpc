defmodule AshRpc.Output.ZodSchemaGenerator do
  @moduledoc false

  import AshRpc.Util.Helpers

  def get_zod_type(type_and_constraints, context \\ nil)
  def get_zod_type(:count, _), do: "z.number().int()"
  def get_zod_type(:sum, _), do: "z.number()"
  def get_zod_type(:exists, _), do: "z.boolean()"
  def get_zod_type(:avg, _), do: "z.number()"
  def get_zod_type(:min, _), do: "z.any()"
  def get_zod_type(:max, _), do: "z.any()"
  def get_zod_type(:first, _), do: "z.any()"
  def get_zod_type(:last, _), do: "z.any()"
  def get_zod_type(:list, _), do: "z.array(z.any())"
  def get_zod_type(:custom, _), do: "z.any()"
  def get_zod_type(:integer, _), do: "z.number().int()"
  def get_zod_type(%{type: nil}, _), do: "z.null()"
  def get_zod_type(%{type: :sum}, _), do: "z.number()"
  def get_zod_type(%{type: :count}, _), do: "z.number().int()"
  def get_zod_type(%{type: :map}, _), do: "z.record(z.string(), z.any())"

  def get_zod_type(%{type: Ash.Type.Atom, constraints: constraints}, _) when constraints != [] do
    case Keyword.get(constraints, :one_of) do
      nil -> "z.string()"
      values -> "z.enum([" <> Enum.map_join(values, ", ", &"\"#{to_string(&1)}\"") <> "])"
    end
  end

  def get_zod_type(%{type: Ash.Type.Atom}, _), do: "z.string()"
  def get_zod_type(%{type: Ash.Type.String, allow_nil?: false}, _), do: "z.string().min(1)"
  def get_zod_type(%{type: Ash.Type.String}, _), do: "z.string()"
  def get_zod_type(%{type: Ash.Type.CiString}, _), do: "z.string()"
  def get_zod_type(%{type: Ash.Type.Integer}, _), do: "z.number().int()"
  def get_zod_type(%{type: Ash.Type.Float}, _), do: "z.number()"
  def get_zod_type(%{type: Ash.Type.Decimal}, _), do: "z.string()"
  def get_zod_type(%{type: Ash.Type.Boolean}, _), do: "z.boolean()"
  def get_zod_type(%{type: Ash.Type.UUID, allow_nil?: true}, _), do: "z.uuid().nullable()"
  def get_zod_type(%{type: Ash.Type.UUID}, _), do: "z.uuid()"
  def get_zod_type(%{type: Ash.Type.UUIDv7, allow_nil?: true}, _), do: "z.uuid().nullable()"
  def get_zod_type(%{type: Ash.Type.UUIDv7}, _), do: "z.uuid()"
  def get_zod_type(%{type: Ash.Type.Date}, _), do: "z.iso.date()"
  def get_zod_type(%{type: Ash.Type.Time}, _), do: "z.string().time()"
  def get_zod_type(%{type: Ash.Type.TimeUsec}, _), do: "z.string().time()"
  def get_zod_type(%{type: Ash.Type.UtcDatetime}, _), do: "z.iso.datetime()"
  def get_zod_type(%{type: Ash.Type.UtcDatetimeUsec}, _), do: "z.iso.datetime()"
  def get_zod_type(%{type: Ash.Type.DateTime}, _), do: "z.iso.datetime()"
  def get_zod_type(%{type: Ash.Type.NaiveDatetime}, _), do: "z.iso.datetime()"
  def get_zod_type(%{type: Ash.Type.Duration}, _), do: "z.string()"
  def get_zod_type(%{type: Ash.Type.DurationName}, _), do: "z.string()"
  def get_zod_type(%{type: Ash.Type.Binary}, _), do: "z.string()"
  def get_zod_type(%{type: Ash.Type.UrlEncodedBinary}, _), do: "z.string()"
  def get_zod_type(%{type: Ash.Type.File}, _), do: "z.any()"
  def get_zod_type(%{type: Ash.Type.Function}, _), do: "z.function()"
  def get_zod_type(%{type: Ash.Type.Term}, _), do: "z.any()"
  def get_zod_type(%{type: Ash.Type.Vector}, _), do: "z.array(z.number())"
  def get_zod_type(%{type: Ash.Type.Module}, _), do: "z.string()"

  def get_zod_type(%{type: Ash.Type.Map, constraints: constraints}, context)
      when constraints != [] do
    case Keyword.get(constraints, :fields) do
      nil -> "z.record(z.string(), z.any())"
      fields -> build_zod_object_type(fields, context)
    end
  end

  def get_zod_type(%{type: Ash.Type.Map}, _), do: "z.record(z.string(), z.any())"

  def get_zod_type(%{type: Ash.Type.Keyword, constraints: constraints}, context)
      when constraints != [] do
    case Keyword.get(constraints, :fields) do
      nil -> "z.record(z.string(), z.any())"
      fields -> build_zod_object_type(fields, context)
    end
  end

  def get_zod_type(%{type: Ash.Type.Keyword}, _), do: "z.record(z.string(), z.any())"

  def get_zod_type(%{type: Ash.Type.Tuple, constraints: constraints}, context) do
    case Keyword.get(constraints, :fields) do
      nil -> "z.record(z.string(), z.any())"
      fields -> build_zod_object_type(fields, context)
    end
  end

  def get_zod_type(%{type: Ash.Type.Struct, constraints: constraints}, context) do
    instance_of = Keyword.get(constraints, :instance_of)
    fields = Keyword.get(constraints, :fields)

    cond do
      fields != nil ->
        build_zod_object_type(fields, context)

      instance_of && Ash.Resource.Info.resource?(instance_of) ->
        build_resource_type_name(instance_of) <> "ZodSchema"

      true ->
        "z.record(z.string(), z.any())"
    end
  end

  def get_zod_type(%{type: {:array, inner}}, context) do
    inner_zod = get_zod_type(%{type: inner, constraints: []}, context)
    "z.array(#{inner_zod})"
  end

  def get_zod_type(%{type: type, constraints: constraints} = attr, context) do
    cond do
      function_exported?(type, :typescript_type_name, 0) and
          Spark.implements_behaviour?(type, Ash.Type) ->
        "z.string()"

      Ash.Resource.Info.resource?(type) ->
        build_resource_type_name(type) <> "ZodSchema"

      Ash.Type.NewType.new_type?(type) ->
        sub_constraints = Ash.Type.NewType.constraints(type, constraints)
        subtype = Ash.Type.NewType.subtype_of(type)
        get_zod_type(%{attr | type: subtype, constraints: sub_constraints}, context)

      Spark.implements_behaviour?(type, Ash.Type.Enum) ->
        "z.enum([" <> Enum.map_join(type.values(), ", ", &"\"#{to_string(&1)}\"") <> "])"

      true ->
        "z.any()"
    end
  end

  def generate_zod_schema(resource, action, rpc_action_name) do
    if action_has_input?(resource, action) do
      schema_name = format_output_field("#{rpc_action_name}_ZodSchema")

      zod_field_defs =
        case action.type do
          :read ->
            if action.arguments != [] do
              Enum.map(action.arguments, &arg_to_field/1)
            else
              []
            end

          :create ->
            accepts = Ash.Resource.Info.action(resource, action.name).accept || []
            args = action.arguments

            if accepts != [] or args != [] do
              Enum.map(accepts, fn field_name ->
                attr_to_field(Ash.Resource.Info.attribute(resource, field_name))
              end) ++
                Enum.map(args, &arg_to_field/1)
            else
              []
            end

          action_type when action_type in [:update, :destroy] ->
            if action.accept != [] or action.arguments != [] do
              Enum.map(action.accept, fn field_name ->
                attr_to_field(Ash.Resource.Info.attribute(resource, field_name))
              end) ++
                Enum.map(action.arguments, &arg_to_field/1)
            else
              []
            end

          :action ->
            if action.arguments != [] do
              Enum.map(action.arguments, &arg_to_field/1)
            else
              []
            end
        end

      field_lines = Enum.map(zod_field_defs, fn {name, zt} -> "  #{name}: #{zt}," end)

      """
      export const #{schema_name} = z.object({
      #{Enum.join(field_lines, "\n")}
      });
      """
    else
      ""
    end
  end

  def generate_zod_schemas_for_embedded_resources(embedded_resources) do
    if embedded_resources != [] do
      schemas =
        embedded_resources |> Enum.map_join("\n\n", &generate_zod_schema_for_embedded_resource/1)

      """
      // ============================
      // Zod Schemas for Embedded Resources
      // ============================

      #{schemas}
      """
    else
      ""
    end
  end

  def generate_zod_schema_for_embedded_resource(resource) do
    resource_name = build_resource_type_name(resource)

    zod_fields =
      resource
      |> Ash.Resource.Info.public_attributes()
      |> Enum.map_join("\n", fn attr ->
        formatted_name = format_output_field(attr.name)
        zt = get_zod_type(attr)
        zt = if attr.allow_nil? || attr.default != nil, do: "#{zt}.optional()", else: zt
        "  #{formatted_name}: #{zt},"
      end)

    """
    export const #{resource_name}ZodSchema = z.object({
    #{zod_fields}
    });
    """
  end

  defp build_zod_object_type(fields, context) do
    field_schemas =
      fields
      |> Enum.map_join(", ", fn {field_name, field_config} ->
        field_type = Keyword.get(field_config, :type, :string)
        field_constraints = Keyword.get(field_config, :constraints, [])
        allow_nil = Keyword.get(field_config, :allow_nil?, false)
        zt = get_zod_type(%{type: field_type, constraints: field_constraints}, context)
        zt = if allow_nil, do: "#{zt}.optional()", else: zt
        "#{format_output_field(field_name)}: #{zt}"
      end)

    "z.object({ #{field_schemas} })"
  end

  defp arg_to_field(arg) do
    formatted_arg = format_output_field(arg.name)
    zt = get_zod_type(arg)
    zt = if arg.allow_nil? || arg.default != nil, do: "#{zt}.optional()", else: zt
    {formatted_arg, zt}
  end

  defp attr_to_field(attr) do
    formatted = format_output_field(attr.name)
    zt = get_zod_type(attr)
    zt = if attr.allow_nil? || attr.default != nil, do: "#{zt}.optional()", else: zt
    {formatted, zt}
  end

  defp action_has_input?(resource, action) do
    case action.type do
      :read ->
        action.arguments != []

      :create ->
        (Ash.Resource.Info.action(resource, action.name).accept || []) != [] or
          action.arguments != []

      action_type when action_type in [:update, :destroy] ->
        action.accept != [] or action.arguments != []

      :action ->
        action.arguments != []
    end
  end

  def build_resource_type_name(resource) do
    resource |> Module.split() |> List.last() |> Macro.camelize()
  end
end
