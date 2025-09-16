defmodule AshRpc.Config.Config do
  @moduledoc false

  # Formatter used when parsing incoming client field names (e.g., camelCase → snake_case)
  def input_field_formatter do
    Application.get_env(:ash_rpc, :input_field_formatter, :camel_case)
  end

  # Formatter used when formatting field names for output/messages
  def output_field_formatter do
    Application.get_env(:ash_rpc, :output_field_formatter, :camel_case)
  end
end
