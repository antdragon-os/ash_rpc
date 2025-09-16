defmodule AshRpc.Util.Helpers do
  @moduledoc false

  def snake_to_pascal_case(snake) when is_atom(snake) do
    snake |> Atom.to_string() |> snake_to_pascal_case()
  end

  def snake_to_pascal_case(snake) when is_binary(snake) do
    snake
    |> String.split("_")
    |> Enum.with_index()
    |> Enum.map_join(fn {part, _} -> String.capitalize(part) end)
  end

  def snake_to_camel_case(snake) when is_atom(snake) do
    snake |> Atom.to_string() |> snake_to_camel_case()
  end

  def snake_to_camel_case(snake) when is_binary(snake) do
    snake
    |> String.split("_")
    |> Enum.with_index()
    |> Enum.map_join(fn
      {part, 0} -> String.downcase(part)
      {part, _} -> String.capitalize(part)
    end)
  end

  def camel_to_snake_case(camel) when is_binary(camel) do
    camel
    |> String.replace(~r/([a-z\d])([A-Z])/, "\\1_\\2")
    |> String.replace(~r/([a-z])(\d+)/, "\\1_\\2")
    |> String.replace(~r/(\d+)([a-z])/, "\\1_\\2")
    |> String.replace(~r/(\d+)([A-Z])/, "\\1_\\2")
    |> String.replace(~r/([A-Z])(\d+)/, "\\1_\\2")
    |> String.downcase()
  end

  def camel_to_snake_case(camel) when is_atom(camel) do
    camel |> Atom.to_string() |> camel_to_snake_case()
  end

  def pascal_to_snake_case(pascal) when is_atom(pascal) do
    pascal |> Atom.to_string() |> pascal_to_snake_case()
  end

  def pascal_to_snake_case(pascal) when is_binary(pascal) do
    pascal
    |> String.replace(~r/([a-z\d])([A-Z])/, "\\1_\\2")
    |> String.replace(~r/([a-z])(\d+)/, "\\1_\\2")
    |> String.replace(~r/(\d+)([a-z])/, "\\1_\\2")
    |> String.replace(~r/(\d+)([A-Z])/, "\\1_\\2")
    |> String.replace(~r/([A-Z])(\d+)/, "\\1_\\2")
    |> String.downcase()
    |> String.trim_leading("_")
  end

  def format_output_field(field_name) do
    AshRpc.Input.FieldFormatter.format_field(
      field_name,
      AshRpc.Config.Config.output_field_formatter()
    )
  end

  def formatted_results_field, do: format_output_field(:results)
  def formatted_has_more_field, do: format_output_field(:has_more)
  def formatted_limit_field, do: format_output_field(:limit)
  def formatted_offset_field, do: format_output_field(:offset)
  def formatted_after_field, do: format_output_field(:after)
  def formatted_before_field, do: format_output_field(:before)
  def formatted_previous_page_field, do: format_output_field(:previous_page)
  def formatted_next_page_field, do: format_output_field(:next_page)
  def formatted_error_type_field, do: format_output_field(:type)
  def formatted_error_message_field, do: format_output_field(:message)
  def formatted_error_field_path_field, do: format_output_field(:field_path)
  def formatted_error_details_field, do: format_output_field(:details)
  def formatted_args_field, do: format_output_field(:args)
  def formatted_fields_field, do: format_output_field(:fields)
  def formatted_page_field, do: format_output_field(:page)
end
