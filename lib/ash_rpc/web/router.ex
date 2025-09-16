defmodule AshRpc.Web.Router do
  @moduledoc """
  Use this module to expose Ash actions as tRPC-compatible procedures.

  Example:

      defmodule MyAppWeb.TrpcRouter do
        use AshRpc.Web.Router, domains: [MyApp.Accounts, MyApp.Billing]
      end

  Mount in Phoenix:

      # in your Phoenix router
      forward "/trpc", MyAppWeb.TrpcRouter
  """
  defmacro __using__(opts) do
    opts = Macro.expand_literals(opts, __CALLER__)

    quote bind_quoted: [opts: opts] do
      use Plug.Router
      use Plug.ErrorHandler
      @opts opts
      @domains List.wrap(@opts[:domain] || @opts[:domains])
      @opts Keyword.put(@opts, :domains, @domains)
      @opts Map.new(@opts)

      def domains, do: @domains

      plug(:match)

      plug(Plug.Parsers,
        parsers: [:json],
        pass: ["application/json"],
        json_decoder: Jason
      )

      plug(:dispatch)

      forward "/", to: AshRpc.Web.Controller, init_opts: @opts

      # Ensure parse errors and other exceptions return tRPC-compatible envelopes
      def handle_errors(conn, %{reason: %Plug.Parsers.ParseError{} = err}) do
        error = AshRpc.Error.Error.to_trpc_error(err)

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{id: 0, error: error}))
      end

      def handle_errors(conn, %{reason: %Jason.DecodeError{} = err}) do
        error = AshRpc.Error.Error.to_trpc_error(err)

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{id: 0, error: error}))
      end

      # Fallback for any other exceptions: return a valid tRPC envelope so the client can transform
      def handle_errors(conn, %{reason: reason}) do
        error = AshRpc.Error.Error.to_trpc_error(reason)
        body = build_envelope_or_batch(conn, error)

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> send_resp(200, body)
      end

      defp build_envelope_or_batch(conn, error) do
        conn = Plug.Conn.fetch_query_params(conn)
        is_batch = conn.query_params["batch"] == "1"

        case {is_batch, conn.path_info} do
          {true, [seg | _]} when is_binary(seg) ->
            count = seg |> String.split(",") |> length()
            results = for id <- 0..(count - 1), do: %{id: id, error: error}
            Jason.encode!(results)

          _ ->
            Jason.encode!(%{id: 0, error: error})
        end
      end
    end
  end
end
