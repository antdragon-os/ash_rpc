defmodule AshRpc.Error.Codes do
  @moduledoc false

  @type t ::
          :parse_error
          | :bad_request
          | :not_found
          | :timeout
          | :conflict
          | :precondition_failed
          | :payload_too_large
          | :forbidden
          | :unauthorized
          | :method_not_supported
          | :too_many_requests
          | :client_closed_request
          | :internal_server_error

  @doc "Map a tRPC error atom to HTTP status"
  @spec to_http(t) :: pos_integer
  def to_http(:parse_error), do: 400
  def to_http(:bad_request), do: 400
  def to_http(:not_found), do: 404
  def to_http(:timeout), do: 504
  def to_http(:conflict), do: 409
  def to_http(:precondition_failed), do: 412
  def to_http(:payload_too_large), do: 413
  def to_http(:forbidden), do: 403
  def to_http(:unauthorized), do: 401
  def to_http(:method_not_supported), do: 405
  def to_http(:too_many_requests), do: 429
  def to_http(:client_closed_request), do: 499
  def to_http(:internal_server_error), do: 500

  @doc "Return tRPC string code for a given atom"
  @spec to_string_code(t) :: String.t()
  def to_string_code(:parse_error), do: "PARSE_ERROR"
  def to_string_code(:bad_request), do: "BAD_REQUEST"
  def to_string_code(:not_found), do: "NOT_FOUND"
  def to_string_code(:timeout), do: "TIMEOUT"
  def to_string_code(:conflict), do: "CONFLICT"
  def to_string_code(:precondition_failed), do: "PRECONDITION_FAILED"
  def to_string_code(:payload_too_large), do: "PAYLOAD_TOO_LARGE"
  def to_string_code(:forbidden), do: "FORBIDDEN"
  def to_string_code(:unauthorized), do: "UNAUTHORIZED"
  def to_string_code(:method_not_supported), do: "METHOD_NOT_SUPPORTED"
  def to_string_code(:too_many_requests), do: "TOO_MANY_REQUESTS"
  def to_string_code(:client_closed_request), do: "CLIENT_CLOSED_REQUEST"
  def to_string_code(:internal_server_error), do: "INTERNAL_SERVER_ERROR"

  @doc "Map a tRPC error atom to JSON-RPC error code"
  @spec to_jsonrpc(t) :: integer
  def to_jsonrpc(:parse_error), do: -32700
  def to_jsonrpc(:bad_request), do: -32600
  def to_jsonrpc(:not_found), do: -32601
  def to_jsonrpc(:timeout), do: -32000
  def to_jsonrpc(:conflict), do: -32000
  def to_jsonrpc(:precondition_failed), do: -32000
  def to_jsonrpc(:payload_too_large), do: -32000
  def to_jsonrpc(:forbidden), do: -32000
  def to_jsonrpc(:unauthorized), do: -32000
  def to_jsonrpc(:method_not_supported), do: -32601
  def to_jsonrpc(:too_many_requests), do: -32000
  def to_jsonrpc(:client_closed_request), do: -32000
  def to_jsonrpc(:internal_server_error), do: -32603
end
