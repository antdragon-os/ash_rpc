defmodule AshRpc.Error.Error do
  @moduledoc """
  Clean, independent error handling for AshRpc.

  Converts various error types into tRPC-compatible error responses
  without depending on ash_json_api or other external error systems.

  Based on the proven approach from ash_typescript.
  """

  alias AshRpc.Error.{ErrorBuilder, Codes}

  @type trpc_error :: %{
          required(:code) => integer(),
          required(:message) => String.t(),
          required(:data) => %{
            required(:code) => String.t(),
            required(:httpStatus) => pos_integer(),
            optional(:details) => list(map())
          }
        }

  @doc """
  Converts any error into a tRPC-compatible error response.

  This is the main entry point for error handling in AshRpc.
  Uses ErrorBuilder to create detailed, actionable error messages.
  """
  @spec to_trpc_error(term(), map()) :: trpc_error()
  def to_trpc_error(error, _ctx \\ %{}) do
    # Use our clean ErrorBuilder to create structured error response
    error_response = ErrorBuilder.build_error_response(error)

    # Map the structured error to tRPC format
    {trpc_code, http_status} = map_error_to_codes(error_response.type, error)

    # Flatten the structure for easier frontend consumption
    base_data = %{
      code: error_response.type,
      httpStatus: http_status
    }

    # Add form errors directly to the data root if they exist
    # Use 'formErrors' for clarity - this field only appears when there are validation errors
    data =
      if Map.has_key?(error_response, :form) do
        Map.put(base_data, :formErrors, error_response.form)
      else
        base_data
      end

    # Add minimal details for debugging (without redundant form data)
    debug_details = Map.drop(error_response, [:form])
    data = Map.put(data, :details, [debug_details])

    # Use a more generic message when form errors are present
    final_message =
      if Map.has_key?(error_response, :form) do
        "Validation failed"
      else
        error_response.message
      end

    %{
      code: trpc_code,
      message: final_message,
      data: data
    }
  end

  # Maps error types to tRPC codes and HTTP status codes.
  # This provides a clean mapping without depending on external systems.
  defp map_error_to_codes(error_type, original_error) do
    case error_type do
      # Field validation errors
      "action_not_found" -> {Codes.to_jsonrpc(:bad_request), 400}
      "unknown_field" -> {Codes.to_jsonrpc(:bad_request), 400}
      "invalid_field" -> {Codes.to_jsonrpc(:bad_request), 400}
      "requires_field_selection" -> {Codes.to_jsonrpc(:bad_request), 400}
      "invalid_field_selection" -> {Codes.to_jsonrpc(:bad_request), 400}
      "duplicate_field" -> {Codes.to_jsonrpc(:bad_request), 400}
      "field_validation_error" -> {Codes.to_jsonrpc(:bad_request), 400}
      "missing_required_parameter" -> {Codes.to_jsonrpc(:bad_request), 400}
      "field_does_not_support_nesting" -> {Codes.to_jsonrpc(:bad_request), 400}
      "calculation_requires_args" -> {Codes.to_jsonrpc(:bad_request), 400}
      "invalid_calculation_args" -> {Codes.to_jsonrpc(:bad_request), 400}
      "invalid_union_field_format" -> {Codes.to_jsonrpc(:bad_request), 400}
      "invalid_field_type" -> {Codes.to_jsonrpc(:bad_request), 400}
      "unsupported_field_combination" -> {Codes.to_jsonrpc(:bad_request), 400}
      # Authentication & Authorization
      "forbidden" -> {Codes.to_jsonrpc(:forbidden), 403}
      "unauthorized" -> {Codes.to_jsonrpc(:unauthorized), 401}
      "tenant_required" -> {Codes.to_jsonrpc(:bad_request), 400}
      # Resource errors
      "not_found" -> {Codes.to_jsonrpc(:not_found), 404}
      # Ash framework errors - inspect the original error for better classification
      "ash_error" -> map_ash_error_to_codes(original_error)
      # Generic fallback
      "unknown_error" -> {Codes.to_jsonrpc(:internal_server_error), 500}
      _ -> {Codes.to_jsonrpc(:internal_server_error), 500}
    end
  end

  defp map_ash_error_to_codes(ash_error) do
    case ash_error do
      %Ash.Error.Forbidden{} -> {Codes.to_jsonrpc(:forbidden), 403}
      %Ash.Error.Query.NotFound{} -> {Codes.to_jsonrpc(:not_found), 404}
      %Ash.Error.Invalid{} -> {Codes.to_jsonrpc(:bad_request), 400}
      %{class: :forbidden} -> {Codes.to_jsonrpc(:forbidden), 403}
      %{class: :invalid} -> {Codes.to_jsonrpc(:bad_request), 400}
      _ -> {Codes.to_jsonrpc(:internal_server_error), 500}
    end
  end
end
