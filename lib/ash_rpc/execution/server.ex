defmodule AshRpc.Execution.Server do
  @moduledoc false

  alias AshRpc.Output.Transformer

  defstruct transformer: AshRpc.Output.Transformer.Identity,
            before: [],
            after: [],
            on_error: [],
            middlewares: []

  @type middleware_fun :: (map, fun -> {:ok, term} | {:error, term})

  @type t :: %__MODULE__{
          transformer: module,
          before: list((map -> map)),
          after: list((map, term -> term)),
          on_error: list((map, term -> term)),
          middlewares: list(middleware_fun | module())
        }

  @spec new(Keyword.t()) :: t
  def new(opts \\ []) do
    %__MODULE__{
      transformer: Keyword.get(opts, :transformer, AshRpc.Output.Transformer.Identity),
      before: Keyword.get(opts, :before, []),
      after: Keyword.get(opts, :after, []),
      on_error: Keyword.get(opts, :on_error, []),
      middlewares: Keyword.get(opts, :middlewares, [])
    }
  end

  @doc """
  Execute a single tRPC call and return the standard envelope and HTTP status.

  The `resolver` is a function that accepts the `ctx` map and returns `{:ok, data}` or `{:error, err}`.
  """
  @spec handle_single(t, map, (map -> {:ok, term} | {:error, term})) :: {map, pos_integer}
  def handle_single(%__MODULE__{} = server, ctx, resolver) when is_function(resolver, 1) do
    ctx = run_before(server, ctx)

    result = execute_with_middlewares(server, ctx, resolver)

    case result do
      {:ok, {data, subject}} ->
        plain = AshRpc.Util.Util.to_plain(data) |> format_field_names()
        # prefer captured subject when available - pass subject as result for metadata
        meta = build_metadata(Map.put(ctx, :__subject, subject), subject)

        # Add cursor info from the original subject (before processing)
        enhanced_meta = add_cursor_info(meta, subject, ctx)

        # Handle paginated results - put pagination info in meta
        payload =
          case plain do
            %{"results" => results} = page_data when is_list(results) ->
              # Extract pagination metadata and merge it with meta
              page_meta = Map.drop(page_data, ["results"])
              combined_meta = Map.merge(enhanced_meta, page_meta)
              %{"result" => results, "meta" => combined_meta}

            other_data ->
              %{"result" => other_data, "meta" => enhanced_meta}
          end

        encoded = payload |> Transformer.encode(server.transformer)
        encoded = run_after(server, ctx, encoded)
        envelope = %{id: ctx.id || 0, result: %{type: "data", data: encoded}}
        {envelope, 200}

      {:ok, data} ->
        plain = AshRpc.Util.Util.to_plain(data) |> format_field_names()
        # Compute metadata from the original result (struct), not the plain map,
        # so procedures can access things like result.__metadata__
        meta = build_metadata(ctx, data)

        # Add cursor info from the original data
        enhanced_meta = add_cursor_info(meta, data, ctx)

        # Handle paginated results - put pagination info in meta
        payload =
          case plain do
            %{"results" => results} = page_data when is_list(results) ->
              # Extract pagination metadata and merge it with meta
              page_meta = Map.drop(page_data, ["results"])
              combined_meta = Map.merge(enhanced_meta, page_meta)
              %{"result" => results, "meta" => combined_meta}

            other_data ->
              %{"result" => other_data, "meta" => enhanced_meta}
          end

        encoded = payload |> Transformer.encode(server.transformer)
        encoded = run_after(server, ctx, encoded)
        envelope = %{id: ctx.id || 0, result: %{type: "data", data: encoded}}
        {envelope, 200}

      {:error, err} ->
        err = run_on_error(server, ctx, err)
        error_shape = attach_path(AshRpc.Error.Error.to_trpc_error(err, ctx), ctx)
        {%{id: ctx.id || 0, error: error_shape}, 200}
    end
  end

  @doc "Execute a tRPC batch: always returns 200 with per-item envelopes"
  @spec handle_batch(t, list(map), (map -> {:ok, term} | {:error, term})) :: {list(map), 200}
  def handle_batch(%__MODULE__{} = server, calls, resolver) do
    results =
      Enum.map(calls, fn ctx ->
        {envelope, _status} = handle_single(server, ctx, resolver)
        envelope
      end)

    {results, 200}
  end

  defp run_before(%__MODULE__{before: hooks}, ctx) do
    Enum.reduce(hooks, ctx, fn hook, acc ->
      try do
        hook.(acc)
      rescue
        _ -> acc
      end
    end)
  end

  defp run_after(%__MODULE__{after: hooks}, ctx, data) do
    Enum.reduce(hooks, data, fn hook, acc ->
      try do
        hook.(ctx, acc)
      rescue
        _ -> acc
      end
    end)
  end

  defp run_on_error(%__MODULE__{on_error: hooks}, ctx, err) do
    Enum.reduce(hooks, err, fn hook, acc ->
      try do
        hook.(ctx, acc)
      rescue
        _ -> acc
      end
    end)
  end

  defp execute_with_middlewares(%__MODULE__{} = server, ctx, resolver) do
    base = fn final_ctx ->
      try do
        resolver.(final_ctx)
      rescue
        e -> {:error, e}
      end
    end

    chain = build_chain(server.middlewares, base)
    chain.(ctx)
  end

  defp build_chain([], base), do: base

  defp build_chain([mw | rest], base) do
    next = build_chain(rest, base)

    fn ctx ->
      case normalize_middleware(mw) do
        {:fun, fun} -> safe_call(fun, ctx, next)
        {:mod, mod} -> safe_call(&mod.call/2, ctx, next)
      end
    end
  end

  defp normalize_middleware(fun) when is_function(fun, 2), do: {:fun, fun}
  defp normalize_middleware(mod) when is_atom(mod), do: {:mod, mod}

  defp safe_call(fun, ctx, next) do
    try do
      fun.(ctx, next)
    rescue
      e -> {:error, e}
    end
  end

  # Status codes are kept 200 to match tRPC HTTP link expectations

  defp attach_path(%{data: data} = error, %{procedure: path}) when is_binary(path) do
    %{error | data: Map.put_new(data, :path, path)}
  end

  defp attach_path(error, _ctx), do: error

  defp format_field_names(data) do
    formatter = AshRpc.Config.Config.output_field_formatter()

    case data do
      %{} = map ->
        map
        |> Enum.map(fn {k, v} ->
          key =
            case k do
              a when is_atom(a) -> AshRpc.Input.FieldFormatter.format_field(a, formatter)
              s when is_binary(s) -> AshRpc.Input.FieldFormatter.format_field(s, formatter)
              other -> other
            end

          {key, format_field_names(v)}
        end)
        |> Map.new()

      list when is_list(list) ->
        Enum.map(list, &format_field_names/1)

      other ->
        other
    end
  end

  defp build_metadata(%{procedure: proc} = ctx, result) when is_binary(proc) do
    with parts <- String.split(proc, "."),
         {:ok, resource, proc_name} <- resolve_proc_for_meta(ctx, parts),
         %AshRpc.Dsl.Procedure{metadata: fun} when is_function(fun, 3) <-
           find_proc(resource, proc_name) do
      subject = Map.get(ctx, :__subject)
      safe_meta(fun, subject, result, ctx)
    else
      _ -> %{}
    end
  end

  defp build_metadata(_ctx, _result), do: %{}

  defp resolve_proc_for_meta(%{resources: resources}, [res_seg, action_seg]) do
    case AshRpc.Util.Util.find_resource_by_segment(resources, res_seg) do
      nil -> :error
      resource -> {:ok, resource, String.to_atom(action_seg |> Macro.underscore())}
    end
  end

  defp resolve_proc_for_meta(%{domains: domains}, [dom_seg, res_seg, action_seg]) do
    with domain when not is_nil(domain) <-
           Enum.find(domains, fn d -> AshRpc.Util.Util.domain_segment(d) == dom_seg end),
         resource when not is_nil(resource) <-
           AshRpc.Util.Util.find_resource_by_segment(Ash.Domain.Info.resources(domain), res_seg) do
      {:ok, resource, String.to_atom(action_seg |> Macro.underscore())}
    else
      _ -> :error
    end
  end

  defp resolve_proc_for_meta(_, _), do: :error

  defp find_proc(resource, external_name_atom) do
    AshRpc.Dsl.Info.find_procedure(resource, external_name_atom)
  end

  defp safe_meta(fun, subject, result, ctx) do
    try do
      case fun.(subject, result, ctx) do
        %{} = meta -> meta
        _ -> %{}
      end
    rescue
      _ -> %{}
    end
  end

  defp add_cursor_info(meta, data, _ctx) do
    case data do
      %Ash.Page.Keyset{} = page ->
        # Extract cursor information for keyset pagination
        next_cursor = if page.more?, do: List.last(page.results), else: nil
        cursor_value = if next_cursor, do: extract_cursor_value(next_cursor), else: nil

        Map.merge(meta, %{
          "nextCursor" => cursor_value,
          "hasNextPage" => page.more? || false
        })

      %Ash.Page.Offset{} = page ->
        # For offset pagination, provide comprehensive navigation metadata
        current_page = div(page.offset, page.limit) + 1
        total_pages = if page.count, do: ceil(page.count / page.limit), else: nil

        navigation_meta = %{
          "hasMore" => page.more? || false,
          "hasPrevious" => page.offset > 0,
          "currentPage" => current_page,
          "nextPage" => if(page.more?, do: current_page + 1, else: nil),
          "previousPage" => if(page.offset > 0, do: current_page - 1, else: nil)
        }

        # Add total pages if count is available
        navigation_meta =
          if total_pages do
            Map.put(navigation_meta, "totalPages", total_pages)
          else
            navigation_meta
          end

        Map.merge(meta, navigation_meta)

      _ ->
        # Not a paginated result, return meta as-is
        meta
    end
  end

  defp extract_cursor_value(record) do
    # Try to extract cursor value from the record
    # For Ash keyset pagination, the cursor is in __metadata__.keyset
    case record do
      %{__metadata__: %{keyset: keyset}} when not is_nil(keyset) ->
        keyset

      %{id: id} when not is_nil(id) ->
        # Fallback to ID-based cursor
        to_string(id)

      _ ->
        nil
    end
  end
end
