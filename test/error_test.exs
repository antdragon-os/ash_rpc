defmodule AshRpc.ErrorTest do
  use ExUnit.Case, async: true

  alias AshRpc.Error.Error

  test "builds trpc error for generic error" do
    err = %RuntimeError{message: "boom"}
    trpc = AshRpc.Error.Error.to_trpc_error(err)

    assert is_map(trpc)
    assert is_integer(trpc.code)
    assert is_binary(trpc.message)
    assert is_map(trpc.data)
    assert is_integer(trpc.data.httpStatus)
  end

  test "maps not found to 404 classification" do
    nf = Ash.Error.Query.NotFound.exception(resource: Ash.Resource, primary_key: [id: 1])
    trpc = Error.to_trpc_error(nf)

    assert 404 == trpc.data.httpStatus
    assert String.match?(trpc.message, ~r/not/i)
  end
end
