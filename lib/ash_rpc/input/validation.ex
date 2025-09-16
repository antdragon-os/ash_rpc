defmodule AshRpc.Input.Validation do
  @moduledoc false

  # Validate an action's input without executing side effects.
  # Returns %{success: boolean, errors: list}
  def validate_action(resource, action, input, opts) do
    case action.type do
      :read -> validate_read_action(resource, action, input, opts)
      t when t in [:update, :destroy] -> validate_update_or_destroy(resource, action, input, opts)
      :create -> validate_via_form(resource, action, input, opts)
      :action -> validate_via_form(resource, action, input, opts)
    end
  end

  defp validate_read_action(resource, action, input, opts) do
    query = resource |> Ash.Query.for_read(action.name, input, opts)

    case query do
      %Ash.Query{errors: []} -> %{success: true}
      %Ash.Query{errors: errors} -> %{success: false, errors: format_errors(errors)}
      _ -> %{success: true}
    end
  rescue
    e -> %{success: false, errors: [%{message: Exception.message(e)}]}
  end

  defp validate_update_or_destroy(resource, action, input, opts) do
    pk = Ash.Resource.Info.primary_key(resource)
    identifier = Map.take(input, pk) |> Map.to_list()

    with {:ok, record} <- Ash.get(resource, identifier, opts) do
      validate_form(record, action.name, input, opts)
    else
      {:error, err} -> %{success: false, errors: format_nested(err)}
    end
  end

  defp validate_via_form(resource, action, input, opts) do
    validate_form(resource, action.name, input, opts)
  end

  defp validate_form(record_or_resource, action_name, input, opts) do
    form_errors =
      record_or_resource
      |> AshPhoenix.Form.for_action(action_name, opts)
      |> AshPhoenix.Form.validate(input)
      |> AshPhoenix.Form.errors()

    if Enum.empty?(form_errors) do
      %{success: true}
    else
      %{success: false, errors: Enum.map(form_errors, &format_form_error/1)}
    end
  end

  defp format_form_error({field, messages}) do
    %{field: to_string(field), errors: List.wrap(messages) |> Enum.map(&to_string/1)}
  end

  defp format_errors(errors) do
    Enum.map(errors, fn e -> %{message: Exception.message(e)} end)
  end

  defp format_nested(e) do
    cond do
      is_map(e) and Map.has_key?(e, :errors) and is_list(e.errors) ->
        Enum.map(e.errors, fn inner ->
          %{message: safe_message(inner)}
        end)

      true ->
        [%{message: safe_message(e)}]
    end
  end

  defp safe_message(err) do
    try do
      Exception.message(err)
    rescue
      _ -> inspect(err)
    end
  end
end
