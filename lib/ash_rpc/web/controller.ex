defmodule AshRpc.Web.Controller do
  @moduledoc false
  import Plug.Conn
  alias AshRpc.Execution.Executor

  def init(opts), do: opts

  def call(%Plug.Conn{method: "POST"} = conn, opts) do
    domains = List.wrap(opts[:domain] || opts[:domains])
    transformer = opts[:transformer] || AshRpc.Output.Transformer.Identity
    resources = Enum.flat_map(domains, &Ash.Domain.Info.resources/1)
    create_context = Map.get(opts, :create_context)

    base_ctx =
      case create_context do
        fun when is_function(fun, 1) ->
          fun.(conn)

        _ ->
          %{}
      end

    # Store domains in base_ctx for downstream resolution
    base_ctx = Map.put(base_ctx, :__domains, domains)

    server =
      AshRpc.Execution.Server.new(
        transformer: transformer,
        before: Map.get(opts, :before, []),
        after: Map.get(opts, :after, []),
        on_error: Map.get(opts, :on_error, []),
        middlewares: Map.get(opts, :middlewares, [])
      )

    path_info = conn.path_info || []
    body = conn.body_params

    case {path_info, body} do
      # Official tRPC style
      {[multi], %{} = map} when is_binary(multi) ->
        if String.contains?(multi, ",") do
          procedures = String.split(multi, ",")

          calls =
            procedures
            |> Enum.with_index()
            |> Enum.map(fn {proc, idx} ->
              key = Integer.to_string(idx)
              item = Map.get(map, key, %{})
              %{id: idx, path: proc, input: parse_input(item)}
            end)

          {results, status} = process_batch_official(server, calls, resources, conn, base_ctx)
          send_json(conn, status, results)
        else
          proc = if String.contains?(multi, "."), do: multi, else: map["path"] || multi

          input =
            if Map.has_key?(map, "0") do
              parsed = parse_input(Map.get(map, "0") || %{})
              parsed
            else
              parse_input(map)
            end

          IO.puts("DEBUG CONTROLLER: Final input before process_single_official: #{inspect(input)}")

          {result, status} =
            process_single_official(server, proc, input, resources, conn, base_ctx)

          send_json(conn, status, result)
        end

      # Official tRPC single: /trpc/a.b with body {json: input} or {input: input}
      {[seg], %{} = single} when is_binary(seg) ->
        proc = if String.contains?(seg, "."), do: seg, else: single["path"] || seg
        # Support official single-batch style: {"0": {json|input}}
        input =
          if Map.has_key?(single, "0") do
            parse_input(Map.get(single, "0") || %{})
          else
            parse_input(single)
          end

        {result, status} = process_single_official(server, proc, input, resources, conn, base_ctx)
        send_json(conn, status, result)

      # Our custom batch via array body
      {[], list} when is_list(list) ->
        {results, status} = process_batch(server, list, resources, conn, base_ctx)
        send_json(conn, status, results)

      # Fallback: use `path` inside the body if present
      {_any, %{} = single} ->
        procedure = single["path"] || single["procedure"]
        {result, status} = process_single(server, procedure, single, resources, conn, base_ctx)
        send_json(conn, status, result)

      {_any, list} when is_list(list) ->
        {results, status} = process_batch(server, list, resources, conn, base_ctx)
        send_json(conn, status, results)

      _ ->
        error =
          AshRpc.Error.Error.to_trpc_error(%Ash.Error.Invalid{errors: [message: "Invalid request"]})

        send_json(conn, 200, %{id: 0, error: error})
    end
  end

  def call(conn, _opts) do
    send_resp(conn, 405, "Method Not Allowed")
  end

  defp process_single(_server, nil, _single, _resources, _conn, _base_ctx) do
    error = AshRpc.Error.Error.to_trpc_error(%Ash.Error.Invalid{errors: [message: "Missing path"]})
    # tRPC transports errors inside a 200 response; include envelope with error
    {%{id: 0, error: error}, 200}
  end

  defp process_single(server, procedure, single, resources, conn, base_ctx) do
    id = Map.get(single, "id")
    method = Map.get(single, "method")
    params = Map.get(single, "params", %{})
    input = Map.get(params, "input", %{})

    input =
      input |> AshRpc.Output.Transformer.decode(server.transformer) |> AshRpc.Util.Util.snake_keys()

    doms = Map.get(base_ctx, :__domains) || []

    ctx =
      Executor.build_ctx(
        Map.put(base_ctx, :id, id),
        resources,
        doms,
        procedure,
        method,
        input,
        conn
      )

    AshRpc.Execution.Server.handle_single(server, ctx, &Executor.run/1)
  end

  defp process_batch(server, list, resources, conn, base_ctx) do
    results =
      Enum.map(list, fn call ->
        id = call["id"]
        method = call["method"]
        procedure = call["path"] || call["procedure"]
        input = get_in(call, ["params", "input"]) || %{}

        input =
          input
          |> AshRpc.Output.Transformer.decode(server.transformer)
          |> AshRpc.Util.Util.snake_keys()

        doms = Map.get(base_ctx, :__domains) || []

        ctx =
          Executor.build_ctx(
            Map.put(base_ctx, :id, id),
            resources,
            doms,
            procedure,
            method,
            input,
            conn
          )

        {envelope, _status} = AshRpc.Execution.Server.handle_single(server, ctx, &Executor.run/1)
        envelope
      end)

    # tRPC batches should return 200 always; individual items carry error data
    {results, 200}
  end

  defp process_single_official(server, procedure, input, resources, conn, base_ctx) do
    input =
      (input || %{})
      |> AshRpc.Output.Transformer.decode(server.transformer)
      |> AshRpc.Util.Util.snake_keys()

    doms = Map.get(base_ctx, :__domains) || []

    ctx =
      Executor.build_ctx(Map.put(base_ctx, :id, 0), resources, doms, procedure, nil, input, conn)

    AshRpc.Execution.Server.handle_single(server, ctx, &Executor.run/1)
  end

  defp process_batch_official(server, calls, resources, conn, base_ctx) do
    calls =
      Enum.map(calls, fn c ->
        Map.update!(
          c,
          :input,
          &((&1 || %{})
            |> AshRpc.Output.Transformer.decode(server.transformer)
            |> AshRpc.Util.Util.snake_keys())
        )
      end)

    doms = Map.get(base_ctx, :__domains) || []

    ctxs =
      Enum.map(calls, fn c ->
        Executor.build_ctx(
          Map.put(base_ctx, :id, c.id),
          resources,
          doms,
          c.path,
          nil,
          c.input,
          conn
        )
      end)

    AshRpc.Execution.Server.handle_batch(server, ctxs, &Executor.run/1)
  end

  # Execution now handled via Executor

  defp parse_input(%{"json" => json}) when is_map(json) do
    json
  end

  defp parse_input(%{"input" => input}) when is_map(input) do
    input
  end

  defp parse_input(map) when is_map(map) do
    map
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
