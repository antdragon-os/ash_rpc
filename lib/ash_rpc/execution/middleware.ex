defmodule AshRpc.Execution.Middleware do
  @moduledoc """
  Middleware interface for AshRpc TRPC server.

  A middleware receives the current `ctx` and a `next` function. It should
  return either `{:ok, data}` or `{:error, err}`.

  Example:

      defmodule MyMiddleware do
        @behaviour AshRpc.Middleware
        @impl true
        def call(ctx, next) do
          ctx = Map.put(ctx, :started_at, System.system_time(:millisecond))
          next.(ctx)
        end
      end

  You can also use a plain 2-arity function: `fn ctx, next -> next.(ctx) end`.
  """

  @callback call(map(), (map() -> {:ok, term()} | {:error, term()})) ::
              {:ok, term()} | {:error, term()}
end
