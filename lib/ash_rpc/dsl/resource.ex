defmodule AshRpc.Dsl.Resource do
  @moduledoc """
  Minimal opt-in for exposing Ash resource actions to Ash RPC.

  Usage in a resource module:

      use AshRpc.Dsl.Resource, expose: [:read, :register_with_password]

  Then the Ash RPC router will only allow calling the listed actions
  on that resource. Use `:all` to expose every action.
  """

  defmacro __using__(opts) do
    exposures = opts[:expose] || :all

    quote do
      @doc false
      def __trpc_exposed__, do: unquote(Macro.escape(exposures))
    end
  end
end
