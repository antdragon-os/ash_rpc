defmodule AshRpc.Input.FieldFormatter do
  @moduledoc false

  alias AshRpc.Config.Config

  # Public API

  def parse_input_fields(data, formatter \\ Config.input_field_formatter())

  def parse_input_fields(map, formatter) when is_map(map) do
    map
    |> Enum.map(fn {k, v} ->
      {parse_input_field(k, formatter), parse_input_fields(v, formatter)}
    end)
    |> Map.new()
  end

  def parse_input_fields(list, formatter) when is_list(list) do
    Enum.map(list, &parse_input_fields(&1, formatter))
  end

  def parse_input_fields(other, _formatter), do: other

  def parse_input_field(key, formatter \\ Config.input_field_formatter()) do
    cond do
      is_atom(key) ->
        key

      is_binary(key) ->
        case formatter do
          :camel_case ->
            key |> Macro.underscore()

          :pascal_case ->
            key |> Macro.underscore()

          :snake_case ->
            key

          {mod, fun} when is_atom(mod) and is_atom(fun) ->
            apply(mod, fun, [key])

          {mod, fun, extra} when is_atom(mod) and is_atom(fun) and is_list(extra) ->
            apply(mod, fun, [key | extra])

          _ ->
            key |> Macro.underscore()
        end
        |> then(&String.to_atom/1)

      true ->
        key
    end
  end

  def format_field(key, formatter \\ Config.output_field_formatter()) do
    cond do
      is_atom(key) ->
        key
        |> Atom.to_string()
        |> format_string_field(formatter)

      is_binary(key) ->
        format_string_field(key, formatter)

      true ->
        key
    end
  end

  defp format_string_field(str, formatter) do
    case formatter do
      :camel_case ->
        # snake_case to camelCase
        str
        |> String.split("_")
        |> Enum.reduce({true, ""}, fn part, {first?, acc} ->
          piece = if first?, do: part, else: String.capitalize(part)
          {false, acc <> piece}
        end)
        |> elem(1)

      :pascal_case ->
        str
        |> String.split("_")
        |> Enum.map_join("", &String.capitalize/1)

      :snake_case ->
        Macro.underscore(str)

      {mod, fun} when is_atom(mod) and is_atom(fun) ->
        apply(mod, fun, [str])

      {mod, fun, extra} when is_atom(mod) and is_atom(fun) and is_list(extra) ->
        apply(mod, fun, [str | extra])

      _ ->
        str
    end
  end
end
