defmodule AshRpc.Execution.Executor do
  @moduledoc false

  alias AshRpc.Dsl.Info

  # Public API

  @spec build_ctx(
          map(),
          list(module()),
          list(module()),
          String.t(),
          String.t() | nil,
          map(),
          term()
        ) :: map()
  def build_ctx(base_ctx, resources, domains, procedure, method, input, conn_or_nil) do
    ctx =
      base_ctx
      |> Map.merge(%{
        id: Map.get(base_ctx, :id, 0),
        resources: resources,
        domains: domains,
        procedure: procedure,
        method: method,
        input: input,
        conn: conn_or_nil
      })

    case resolve_for_ctx(resources, procedure) do
      {:ok, resource, action, method_override} ->
        Map.merge(ctx, %{
          resource: resource,
          action: action,
          action_type: action.type,
          method_override: method_override
        })

      _ ->
        ctx
    end
  end

  @spec run(map()) :: {:ok, term()} | {:error, term()}
  def run(%{procedure: procedure} = ctx) when is_binary(procedure) do
    with {:ok, resource, action, method_override} <- resolve_for_ctx(ctx, procedure),
         :ok <- ensure_exposed(resource, action),
         :ok <- validate_with_override_value(action, ctx.method, method_override),
         input <- normalize_input(resource, action, ctx.input) do
      # Validation-only mode: if validate_only flag is present, validate and return
      case Map.get(input, "validate_only") || Map.get(input, :validate_only) do
        true ->
          result =
            AshRpc.Input.Validation.validate_action(
              resource,
              action,
              Map.drop(input, ["validate_only", :validate_only]),
              merge_context_opt(ash_opts(ctx), resource, action)
            )

          {:ok, result}

        _ ->
          do_run(resource, action, input, ctx)
      end
    else
      {:error, error} ->
        {:error, error}

      :invalid_path ->
        {:error, %Ash.Error.Invalid{errors: [message: "Invalid procedure path: #{procedure}"]}}
    end
  end

  def run(_ctx) do
    {:error, %Ash.Error.Invalid{errors: [message: "Invalid procedure path"]}}
  end

  # Internal

  defp validate_with_override_value(action, method, override) do
    cond do
      is_nil(method) ->
        :ok

      override in [:query, :mutation] ->
        if method == to_string(override),
          do: :ok,
          else: {:error, %Ash.Error.Invalid{errors: [message: "Invalid method for action"]}}

      true ->
        validate_method(action.type, method)
    end
  end

  def resolve_for_ctx(ctx, procedure) when is_map(ctx) do
    resources = Map.get(ctx, :resources, [])
    domains = Map.get(ctx, :domains, [])
    parts = String.split(procedure, ".")

    case parts do
      [res_seg, action_seg] ->
        with resource when not is_nil(resource) <-
               AshRpc.Util.Util.find_resource_by_segment(resources, res_seg),
             external_name <- AshRpc.Util.Util.camel_to_snake(action_seg),
             {action, method_override} <- resolve_action_and_method(resource, external_name),
             true <- not is_nil(action) do
          {:ok, resource, action, method_override}
        else
          _ -> :invalid_path
        end

      [dom_seg, res_seg, action_seg] ->
        with domain when not is_nil(domain) <-
               Enum.find(domains, fn d -> AshRpc.Util.Util.domain_segment(d) == dom_seg end),
             domain_resources <- Ash.Domain.Info.resources(domain),
             resource when not is_nil(resource) <-
               AshRpc.Util.Util.find_resource_by_segment(domain_resources, res_seg),
             external_name <- AshRpc.Util.Util.camel_to_snake(action_seg),
             {action, method_override} <- resolve_action_and_method(resource, external_name),
             true <- not is_nil(action) do
          {:ok, resource, action, method_override}
        else
          _ -> :invalid_path
        end

      _ ->
        :invalid_path
    end
  end

  def resolve_for_ctx(_ctx, _procedure), do: :invalid_path

  defp resolve_action_and_method(resource, external_name) do
    if Code.ensure_loaded?(Info) do
      case Info.find_procedure(resource, external_name) do
        %AshRpc.Dsl.Procedure{action: action_name, method: method} ->
          action = Ash.Resource.Info.action(resource, action_name)
          if action, do: {action, method}, else: {nil, nil}

        nil ->
          action = Ash.Resource.Info.action(resource, external_name)
          {action, nil}
      end
    else
      action = Ash.Resource.Info.action(resource, external_name)
      {action, nil}
    end
  end

  defp normalize_input(resource, action, input) when is_map(input) do
    # Debug action.arguments

    arg_atoms =
      try do
        (action.arguments || []) |> Enum.map(& &1.name)
      rescue
        _error ->
          []
      end

    pk_atoms =
      try do
        Ash.Resource.Info.primary_key(resource)
      rescue
        _error ->
          []
      end

    accepted =
      try do
        (Map.get(action, :accept) || []) |> List.wrap()
      rescue
        _error ->
          []
      end

    base = arg_atoms ++ accepted

    include_list =
      case action.type do
        t when t in [:update, :destroy] ->
          base ++ pk_atoms ++ ["validate_only"]

        :read ->
          # For read actions, also include query options that will be extracted later
          query_options = [
            "filter",
            "sort",
            "select",
            "page",
            "load",
            "cursor",
            "nextCursor",
            "validate_only"
          ]

          combined = base ++ query_options
          combined

        _ ->
          base ++ ["validate_only"]
      end

    result =
      try do
        Enum.reduce(include_list, %{}, fn key, acc ->
          val =
            cond do
              Map.has_key?(input, key) ->
                Map.get(input, key)

              is_atom(key) and Map.has_key?(input, Atom.to_string(key)) ->
                Map.get(input, Atom.to_string(key))

              true ->
                nil
            end

          if is_nil(val) do
            acc
          else
            Map.put(acc, key, val)
          end
        end)
      rescue
        error ->
          raise error
      end

    result
  end

  defp normalize_input(_resource, _action, other), do: other

  defp ensure_exposed(resource, action) do
    if is_nil(action) do
      {:error, Ash.Error.Invalid.NoSuchAction.exception(resource: resource, action: nil)}
    else
      if Code.ensure_loaded?(Info) do
        procs = Info.procedures(resource)

        cond do
          procs != [] and
              Enum.any?(procs, fn %AshRpc.Dsl.Procedure{action: a} -> a == action.name end) ->
            :ok

          Info.exposed?(resource, action.name) ->
            :ok

          function_exported?(resource, :__trpc_exposed__, 0) ->
            case resource.__trpc_exposed__() do
              :all ->
                :ok

              list when is_list(list) ->
                if action.name in list,
                  do: :ok,
                  else:
                    {:error,
                     Ash.Error.Invalid.NoSuchAction.exception(
                       resource: resource,
                       action: action.name
                     )}

              _ ->
                {:error,
                 Ash.Error.Invalid.NoSuchAction.exception(resource: resource, action: action.name)}
            end

          true ->
            {:error,
             Ash.Error.Invalid.NoSuchAction.exception(resource: resource, action: action.name)}
        end
      else
        :ok
      end
    end
  end

  defp do_run(resource, %{type: :read} = action, input, ctx) do
    IO.puts("DEBUG do_run: input = #{inspect(input)}")

    # Use elegant InputProcessor for query options extraction
    case AshRpc.Input.InputProcessor.process(resource, action, input) do
      {:ok, base_input, query_opts} ->
        IO.puts(
          "DEBUG InputProcessor: base_input = #{inspect(base_input)}, query_opts = #{inspect(query_opts)}"
        )

        execute_read_action(resource, action, base_input, query_opts, ctx)

      {:error, error} ->
        IO.puts("DEBUG InputProcessor failed: #{inspect(error)}")
        # Fallback to legacy processing for compatibility
        {base_input, query_opts} = extract_query_options(input)

        IO.puts(
          "DEBUG Legacy: base_input = #{inspect(base_input)}, query_opts = #{inspect(query_opts)}"
        )

        execute_read_action(resource, action, base_input, query_opts, ctx)
    end
  end

  defp do_run(resource, %{type: :action} = action, input, ctx) do
    input =
      (input || %{})
      |> convert_keyword_tuple_inputs(resource, action)

    subject =
      resource
      |> Ash.ActionInput.new()
      |> Ash.ActionInput.set_context(auth_context(resource, action))
      |> Ash.ActionInput.for_action(
        action.name,
        input,
        merge_context_opt(ash_opts(ctx), resource, action)
      )

    # If select was provided for actions with structured returns, we will post-process the result.
    select_spec = get_in(ctx, [:input, "select"]) || get_in(ctx, [:input, :select])

    extraction_template =
      case select_spec do
        nil ->
          nil

        select_list ->
          requested_fields =
            AshRpc.Rpc.RequestedFieldsProcessor.normalize_select(
              resource,
              action.name,
              List.wrap(select_list)
            )

          case AshRpc.Rpc.RequestedFieldsProcessor.process(
                 resource,
                 action.name,
                 requested_fields
               ) do
            {:ok, {_, _load, template}} -> template
            _ -> nil
          end
      end

    case Ash.run_action(subject) do
      {:ok, result} ->
        processed =
          case extraction_template do
            nil -> result
            template -> AshRpc.Output.ResultProcessor.process(result, template)
          end

        {:ok, {processed, subject}}

      {:error, error} ->
        {:error, error}
    end
  end

  defp do_run(resource, %{type: :create} = action, input, ctx) do
    converted_input = (input || %{}) |> convert_keyword_tuple_inputs(resource, action)
    # Selection for create
    {select, load, template} =
      case get_in(ctx, [:input, "select"]) || get_in(ctx, [:input, :select]) do
        nil ->
          {nil, nil, nil}

        select_list ->
          requested_fields =
            AshRpc.Rpc.RequestedFieldsProcessor.normalize_select(
              resource,
              action.name,
              List.wrap(select_list)
            )

          case AshRpc.Rpc.RequestedFieldsProcessor.process(
                 resource,
                 action.name,
                 requested_fields
               ) do
            {:ok, {s, l, t}} -> {s, l, t}
            _ -> {nil, nil, nil}
          end
      end

    subject =
      resource
      |> Ash.Changeset.new()
      |> Ash.Changeset.set_context(auth_context(resource, action))
      |> Ash.Changeset.for_create(
        action.name,
        converted_input || %{},
        merge_context_opt(ash_opts(ctx), resource, action)
      )
      |> then(fn cs ->
        cs = if select, do: Ash.Changeset.select(cs, select), else: cs
        if load, do: Ash.Changeset.load(cs, load), else: cs
      end)

    case Ash.create(subject, merge_context_opt(ash_opts(ctx), resource, action)) do
      {:ok, result} ->
        processed =
          if template, do: AshRpc.Output.ResultProcessor.process(result, template), else: result

        {:ok, {processed, subject}}

      {:error, error} ->
        {:error, error}
    end
  end

  defp do_run(resource, %{type: :update} = action, input, ctx) do
    converted_input = (input || %{}) |> convert_keyword_tuple_inputs(resource, action)

    {select, load, template} =
      case get_in(ctx, [:input, "select"]) || get_in(ctx, [:input, :select]) do
        nil ->
          {nil, nil, nil}

        select_list ->
          requested_fields =
            AshRpc.Rpc.RequestedFieldsProcessor.normalize_select(
              resource,
              action.name,
              List.wrap(select_list)
            )

          case AshRpc.Rpc.RequestedFieldsProcessor.process(
                 resource,
                 action.name,
                 requested_fields
               ) do
            {:ok, {s, l, t}} -> {s, l, t}
            _ -> {nil, nil, nil}
          end
      end

    with {:ok, record} <- fetch_record(resource, converted_input || %{}, ctx),
         subject <- Ash.Changeset.new(record),
         subject <- Ash.Changeset.set_context(subject, auth_context(resource, action)),
         subject <-
           Ash.Changeset.for_update(
             subject,
             action.name,
             Map.drop(converted_input, ["id" | Ash.Resource.Info.primary_key(resource)]),
             merge_context_opt(ash_opts(ctx), resource, action)
           ),
         subject <- if(select, do: Ash.Changeset.select(subject, select), else: subject),
         subject <- if(load, do: Ash.Changeset.load(subject, load), else: subject),
         {:ok, result} <- Ash.update(subject, merge_context_opt(ash_opts(ctx), resource, action)) do
      processed =
        if template, do: AshRpc.Output.ResultProcessor.process(result, template), else: result

      {:ok, {processed, subject}}
    else
      {:error, error} -> {:error, error}
    end
  end

  defp do_run(resource, %{type: :destroy} = action, input, ctx) do
    with {:ok, record} <- fetch_record(resource, input || %{}, ctx),
         subject <- Ash.Changeset.new(record),
         subject <- Ash.Changeset.set_context(subject, auth_context(resource, action)),
         allowed_args <- Enum.map(action.arguments || [], & &1.name),
         cs_input <- Map.take(input || %{}, allowed_args),
         subject <-
           Ash.Changeset.for_destroy(
             subject,
             action.name,
             cs_input,
             merge_context_opt([error?: true] ++ ash_opts(ctx), resource, action)
           ) do
      case Ash.destroy(subject, merge_context_opt(ash_opts(ctx), resource, action)) do
        :ok -> {:ok, {%{}, subject}}
        {:ok, _} -> {:ok, {%{}, subject}}
        {:error, error} -> {:error, error}
      end
    end
  end

  defp fetch_record(resource, input, ctx) do
    pk = Ash.Resource.Info.primary_key(resource)

    cond do
      is_binary(Map.get(input, "id")) or is_integer(Map.get(input, "id")) ->
        case Ash.get(resource, Map.get(input, "id"), ash_opts(ctx)) do
          {:ok, nil} -> {:error, Ash.Error.Query.NotFound.exception()}
          other -> other
        end

      Enum.all?(pk, &Map.has_key?(input, &1)) ->
        case Ash.get(resource, Map.take(input, pk), ash_opts(ctx)) do
          {:ok, nil} -> {:error, Ash.Error.Query.NotFound.exception()}
          other -> other
        end

      true ->
        {:error, %Ash.Error.Invalid{errors: [message: "Missing identifier for update/destroy"]}}
    end
  end

  defp execute_read_action(resource, action, base_input, query_opts, ctx) do
    # Get procedure configuration
    procedure = get_procedure_config(resource, action.name)

    # Try elegant QueryBuilder first, fallback to legacy if needed
    case AshRpc.Input.QueryBuilder.build(resource, action, base_input, query_opts, ctx) do
      {:ok, query, extraction_template} ->
        execute_ash_read_query(query, resource, action, ctx, extraction_template)

      {:error, _error} ->
        # Fallback to legacy query building
        execute_read_action_legacy(resource, action, base_input, query_opts, ctx, procedure)
    end
  end

  defp execute_read_action_legacy(resource, action, base_input, query_opts, ctx, procedure) do
    # Build base query (legacy)
    query =
      resource
      |> Ash.Query.for_read(
        action.name,
        base_input,
        merge_context_opt(ash_opts(ctx), resource, action)
      )

    # Selection (advanced). Always process to get extraction template
    {query, extraction_template} =
      case Map.get(query_opts, :select) do
        nil ->
          # No explicit select - create template with all public fields
          public_attrs = Ash.Resource.Info.public_attributes(resource) |> Enum.map(& &1.name)
          public_calcs = Ash.Resource.Info.public_calculations(resource) |> Enum.map(& &1.name)
          public_aggs = Ash.Resource.Info.public_aggregates(resource) |> Enum.map(& &1.name)

          # Create template with all public fields
          all_public_fields = public_attrs ++ public_calcs ++ public_aggs

          # Handle any explicit loads from query options
          {q, template_with_loads} =
            case Map.get(query_opts, :load) do
              nil ->
                # Load calculations and aggregates if any
                non_attr_fields = public_calcs ++ public_aggs

                query_with_loads =
                  if non_attr_fields != [], do: Ash.Query.load(query, non_attr_fields), else: query

                {query_with_loads, all_public_fields}

              load_list when is_list(load_list) ->
                # Convert camelCase load names to snake_case atoms
                processed_loads =
                  Enum.map(load_list, fn
                    field when is_binary(field) -> AshRpc.Util.Util.camel_to_snake(field)
                    field when is_atom(field) -> field
                    other -> other
                  end)

                query_with_loads = Ash.Query.load(query, processed_loads)
                # Add loaded relationships to template
                template_with_relationships = all_public_fields ++ processed_loads
                {query_with_loads, template_with_relationships}

              single_load ->
                processed_load =
                  case single_load do
                    field when is_binary(field) -> AshRpc.Util.Util.camel_to_snake(field)
                    field when is_atom(field) -> field
                    other -> other
                  end

                query_with_loads = Ash.Query.load(query, [processed_load])
                # Add loaded relationship to template
                template_with_relationship = all_public_fields ++ [processed_load]
                {query_with_loads, template_with_relationship}
            end

          # Template with all public fields + loaded relationships
          {q, template_with_loads}

        select_spec ->
          requested_fields =
            AshRpc.Rpc.RequestedFieldsProcessor.normalize_select(
              resource,
              action.name,
              List.wrap(select_spec)
            )

          case AshRpc.Rpc.RequestedFieldsProcessor.process(
                 resource,
                 action.name,
                 requested_fields
               ) do
            {:ok, {select, load, template}} ->
              # Only apply non-relationship loads here (e.g., calculations). Relationships must be loaded via qopts.load
              non_rel_load = filter_non_relationship_loads(resource, List.wrap(load))
              q = query
              q = if select != nil and select != [], do: Ash.Query.select(q, select), else: q
              q = if non_rel_load != [], do: Ash.Query.load(q, non_rel_load), else: q

              # Ensure template includes any explicitly requested loads (relationships) when not present in select
              augmented_template =
                augment_template_with_loads(template, resource, Map.get(query_opts, :load))

              {q, augmented_template}

            {:error, _reason} ->
              {query, nil}
          end
      end

    # Apply advanced query features
    query = apply_query_features(query, query_opts, procedure, resource)

    case Ash.read(query, merge_context_opt(ash_opts(ctx), resource, action)) do
      {:ok, result} ->
        # Always use extraction template to ensure consistent field filtering
        {processed, subject_for_metadata} =
          if Map.get(action, :get?, false) do
            case result do
              %Ash.Page.Offset{results: [record | _]} ->
                {AshRpc.Output.ResultProcessor.process(record, extraction_template), record}

              %Ash.Page.Keyset{results: [record | _]} ->
                {AshRpc.Output.ResultProcessor.process(record, extraction_template), record}

              [record | _] ->
                {AshRpc.Output.ResultProcessor.process(record, extraction_template), record}

              record ->
                {AshRpc.Output.ResultProcessor.process(record, extraction_template), record}
            end
          else
            {AshRpc.Output.ResultProcessor.process(result, extraction_template), result}
          end

        {:ok, {processed, subject_for_metadata}}

      {:error, error} ->
        if forbidden_read_error?(error) do
          if Map.get(action, :get?, false) do
            {:ok, nil}
          else
            {:ok, []}
          end
        else
          {:error, error}
        end
    end
  end

  defp forbidden_read_error?(%Ash.Error.Forbidden{}), do: true
  defp forbidden_read_error?(%Ash.Error.Forbidden.Policy{}), do: true
  defp forbidden_read_error?(%Ash.Error.Forbidden.ForbiddenField{}), do: true

  defp forbidden_read_error?(%Ash.Error.Unknown{} = err) do
    msg =
      err.errors
      |> List.wrap()
      |> Enum.map(&Map.get(&1, :error))
      |> Enum.join("\n")
      |> String.downcase()

    String.contains?(msg, "forbidden") or String.contains?(msg, "ash.policy")
  end

  defp forbidden_read_error?(_), do: false

  defp validate_method(_type, nil), do: :ok

  defp validate_method(type, method) when method in ["query", "mutation"] do
    expected = default_expected_method(type)

    if method == expected,
      do: :ok,
      else: {:error, %Ash.Error.Invalid{errors: [message: "Invalid method for action"]}}
  end

  defp validate_method(_type, _method), do: :ok

  defp default_expected_method(:read), do: "query"
  defp default_expected_method(:create), do: "mutation"
  defp default_expected_method(:update), do: "mutation"
  defp default_expected_method(:destroy), do: "mutation"
  defp default_expected_method(:action), do: "query"

  defp ash_opts(%{conn: %Plug.Conn{} = conn}) do
    opts = []

    # Prefer reading the actor from Plug private via Ash.PlugHelpers
    actor = Ash.PlugHelpers.get_actor(conn)

    opts =
      case actor do
        nil -> opts
        actor -> Keyword.put(opts, :actor, actor)
      end

    case Plug.Conn.get_req_header(conn, "x-tenant") do
      [tenant | _] -> Keyword.put(opts, :tenant, tenant)
      _ -> opts
    end
  end

  defp ash_opts(ctx) do
    opts = []

    opts =
      case Map.get(ctx, :actor) do
        nil -> opts
        actor -> Keyword.put(opts, :actor, actor)
      end

    case Map.get(ctx, :tenant) do
      nil -> opts
      tenant -> Keyword.put(opts, :tenant, tenant)
    end
  end

  defp merge_context_opt(opts, resource, action) do
    ctx = auth_context(resource, action)

    if map_size(ctx) == 0 do
      opts
    else
      Keyword.update(opts, :context, ctx, &Map.merge(&1, ctx))
    end
  end

  # Elegant query execution with pattern matching
  defp execute_ash_read_query(query, resource, action, ctx, extraction_template) do
    case Ash.read(query, merge_context_opt(ash_opts(ctx), resource, action)) do
      {:ok, result} ->
        # Always use extraction template to ensure consistent field filtering
        {processed, subject_for_metadata} = process_read_result(result, action, extraction_template)
        {:ok, {processed, subject_for_metadata}}

      {:error, error} ->
        handle_read_error(error, action)
    end
  end

  defp process_read_result(result, action, extraction_template) do
    if Map.get(action, :get?, false) do
      case result do
        %Ash.Page.Offset{results: [record | _]} ->
          {AshRpc.Output.ResultProcessor.process(record, extraction_template), record}

        %Ash.Page.Keyset{results: [record | _]} ->
          {AshRpc.Output.ResultProcessor.process(record, extraction_template), record}

        [record | _] ->
          {AshRpc.Output.ResultProcessor.process(record, extraction_template), record}

        record ->
          {AshRpc.Output.ResultProcessor.process(record, extraction_template), record}
      end
    else
      {AshRpc.Output.ResultProcessor.process(result, extraction_template), result}
    end
  end

  defp handle_read_error(error, action) do
    if forbidden_read_error?(error) do
      if Map.get(action, :get?, false) do
        {:ok, nil}
      else
        {:ok, []}
      end
    else
      {:error, error}
    end
  end

  defp auth_context(resource, action) do
    if uses_auth?(resource) and auth_action?(action) do
      %{private: %{ash_authentication?: true}}
    else
      %{}
    end
  end

  defp uses_auth?(resource) do
    Enum.any?(Ash.Resource.Info.extensions(resource), &(&1 == AshAuthentication))
  end

  defp auth_action?(action) do
    action.name in [
      :register_with_password,
      :sign_in_with_password,
      :sign_in_with_token,
      :request_password_reset_token,
      :reset_password_with_token
    ]
  end

  # Advanced Query Features

  # Extract query options from input parameters (filter/sort/select/page/load)
  defp extract_query_options(input) when is_map(input) do
    # Extract special query options including cursor
    base_input =
      Map.drop(input, ["filter", "sort", "select", "page", "load", "cursor", "nextCursor"])

    # Handle cursor parameter - merge it into page if provided
    page = Map.get(input, "page") || %{}
    cursor = Map.get(input, "cursor") || Map.get(input, "nextCursor")

    final_page =
      if cursor do
        Map.put(page, "after", cursor)
      else
        page
      end

    final_page = if map_size(final_page) == 0, do: nil, else: final_page

    query_opts = %{
      filter: Map.get(input, "filter"),
      sort: Map.get(input, "sort"),
      select: Map.get(input, "select"),
      page: final_page,
      load: Map.get(input, "load")
    }

    {base_input, query_opts}
  end

  defp extract_query_options(input), do: {input, %{}}

  defp get_procedure_config(resource, action_name) do
    if Code.ensure_loaded?(AshRpc.Dsl.Info) do
      case AshRpc.Dsl.Info.find_procedure(resource, action_name) do
        %AshRpc.Dsl.Procedure{} = proc ->
          proc

        _ ->
          %AshRpc.Dsl.Procedure{
            filterable: true,
            sortable: true,
            selectable: true,
            paginatable: true
          }
      end
    else
      %AshRpc.Dsl.Procedure{filterable: true, sortable: true, selectable: true, paginatable: true}
    end
  end

  defp apply_query_features(query, query_opts, procedure, resource) do
    query
    |> apply_filter(query_opts.filter, procedure.filterable)
    |> apply_sort(query_opts.sort, procedure.sortable)
    |> apply_pagination(query_opts.page, procedure.paginatable)
    |> apply_relationships(query_opts.load, procedure.relationships, resource)
  end

  defp apply_filter(query, filter, enabled?) when enabled? and not is_nil(filter) do
    # Accept both camelCase and snake_case operators and field names
    # - Convert filter map keys (fields) to snake_case atoms
    # - Convert custom operators to Ash-compatible ones

    normalized_filter =
      filter
      |> normalize_filter_keys()
      |> convert_custom_predicates()

    try do
      Ash.Query.filter_input(query, normalized_filter)
    rescue
      _error ->
        query
    end
  end

  defp apply_filter(query, _filter, _enabled?), do: query

  # Normalize top-level and nested filter keys to snake_case atoms for fields
  defp normalize_filter_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} ->
      new_key =
        cond do
          is_atom(k) -> k
          is_binary(k) -> String.to_atom(Macro.underscore(k))
          true -> k
        end

      {new_key, normalize_filter_keys(v)}
    end)
    |> Map.new()
  end

  defp normalize_filter_keys(list) when is_list(list),
    do: Enum.map(list, &normalize_filter_keys/1)

  defp normalize_filter_keys(other), do: other

  # Convert custom predicates to Ash-compatible ones
  defp convert_custom_predicates(list) when is_list(list),
    do: Enum.map(list, &convert_custom_predicates/1)

  defp convert_custom_predicates(%{ilike: value} = _predicate) do
    # Convert ilike to a case-insensitive like using fragments
    # For now, fall back to eq since ilike might not be available
    %{eq: value}
  end

  defp convert_custom_predicates(%{contains: value} = _predicate) do
    # Convert contains to a like pattern
    # For now, fall back to eq since contains might not be available
    %{eq: value}
  end

  defp convert_custom_predicates(%{startsWith: value} = _predicate) do
    # For now, fall back to eq
    %{eq: value}
  end

  defp convert_custom_predicates(%{endsWith: value} = _predicate) do
    # For now, fall back to eq
    %{eq: value}
  end

  defp convert_custom_predicates(%{like: value} = _predicate) do
    # For now, fall back to eq since like might not be available
    %{eq: value}
  end

  # Generic map handler must come last
  defp convert_custom_predicates(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} ->
      # Convert nil values to is_nil predicates
      case v do
        nil -> {k, %{is_nil: true}}
        other -> {k, convert_custom_predicates(other)}
      end
    end)
    |> Map.new()
  end

  # Fallback
  defp convert_custom_predicates(other), do: other

  defp apply_sort(query, sort, enabled?) when enabled? and not is_nil(sort) do
    sort_expressions =
      cond do
        is_binary(sort) ->
          # String sort syntax, e.g. "--startDate,+title"
          format_sort_string(sort)

        is_map(sort) ->
          Enum.map(sort, fn {field, direction} ->
            field_atom = field |> Macro.underscore() |> String.to_atom()
            direction_atom = if direction in ["desc", :desc], do: :desc, else: :asc
            {field_atom, direction_atom}
          end)

        is_list(sort) ->
          Enum.map(sort, fn
            {field, direction} ->
              field_atom = field |> to_string() |> Macro.underscore() |> String.to_atom()
              direction_atom = if direction in ["desc", :desc], do: :desc, else: :asc
              {field_atom, direction_atom}

            other ->
              other
          end)

        true ->
          []
      end

    try do
      Ash.Query.sort(query, sort_expressions)
    rescue
      _ -> query
    end
  end

  defp apply_sort(query, _sort, _enabled?), do: query

  defp apply_pagination(query, page, enabled?) when enabled? and not is_nil(page) do
    result =
      cond do
        is_map(page) ->
          # Detect pagination strategy based on parameters
          has_offset = Map.has_key?(page, "offset") || Map.has_key?(page, :offset)

          has_cursor =
            Map.has_key?(page, "after") || Map.has_key?(page, :after) ||
              Map.has_key?(page, "before") || Map.has_key?(page, :before)

          cond do
            has_offset && !has_cursor ->
              # Offset-based pagination
              limit_str = Map.get(page, "limit") || Map.get(page, :limit) || 20
              offset_str = Map.get(page, "offset") || Map.get(page, :offset) || 0
              count = Map.get(page, "count") || Map.get(page, :count) || false

              limit = if is_binary(limit_str), do: String.to_integer(limit_str), else: limit_str
              offset = if is_binary(offset_str), do: String.to_integer(offset_str), else: offset_str

              page_opts = [limit: limit, offset: offset]
              page_opts = if count, do: Keyword.put(page_opts, :count, true), else: page_opts

              Ash.Query.page(query, page_opts)

            has_cursor || !has_offset ->
              # Cursor-based pagination (default when no offset specified)
              after_cursor = Map.get(page, "after") || Map.get(page, :after)
              before_cursor = Map.get(page, "before") || Map.get(page, :before)
              limit_str = Map.get(page, "limit") || Map.get(page, :limit) || 20
              count = Map.get(page, "count") || Map.get(page, :count) || false

              limit = if is_binary(limit_str), do: String.to_integer(limit_str), else: limit_str

              page_opts = [limit: limit]

              page_opts =
                if after_cursor, do: Keyword.put(page_opts, :after, after_cursor), else: page_opts

              page_opts =
                if before_cursor,
                  do: Keyword.put(page_opts, :before, before_cursor),
                  else: page_opts

              page_opts = if count, do: Keyword.put(page_opts, :count, true), else: page_opts

              Ash.Query.page(query, page_opts)

            true ->
              query
          end

        is_integer(page) ->
          # Simple limit-only pagination, use keyset by default
          Ash.Query.page(query, limit: page)

        true ->
          query
      end

    result
  end

  defp apply_pagination(query, _page, _enabled?), do: query

  defp apply_relationships(query, load, allowed_relationships, resource) when not is_nil(load) do
    # Build a mixed load spec that can include simple atoms and {rel, %Ash.Query{}} tuples
    allowed =
      if is_list(allowed_relationships) and allowed_relationships != [] do
        allowed_relationships
      else
        resource
        |> Ash.Resource.Info.public_relationships()
        |> Enum.map(& &1.name)
      end

    load_specs = build_load_specs(resource, load, allowed)

    try do
      Ash.Query.load(query, load_specs)
    rescue
      _ -> query
    end
  end

  defp apply_relationships(query, _load, _allowed, _resource), do: query

  defp build_load_specs(resource, load, allowed) do
    load
    |> List.wrap()
    |> Enum.flat_map(fn
      rel when is_binary(rel) or is_atom(rel) ->
        rel_atom = normalize_rel_name(rel)
        if rel_atom in allowed, do: [rel_atom], else: []

      %{} = map ->
        Enum.flat_map(map, fn {k, v} ->
          rel_atom = normalize_rel_name(k)

          if rel_atom in allowed do
            try do
              [{rel_atom, build_nested_query_for_rel(resource, rel_atom, v)}]
            rescue
              _ -> []
            end
          else
            []
          end
        end)

      _other ->
        []
    end)
  end

  defp filter_non_relationship_loads(resource, load_items) do
    Enum.reject(load_items, fn
      item when is_atom(item) ->
        not is_nil(Ash.Resource.Info.relationship(resource, item))

      {item, _nested} when is_atom(item) ->
        not is_nil(Ash.Resource.Info.relationship(resource, item))

      _ ->
        false
    end)
  end

  defp augment_template_with_loads(template, resource, load) do
    load_specs = List.wrap(load)

    load_specs
    |> Enum.reduce(template || [], fn load_spec, acc ->
      case load_spec do
        rel when is_binary(rel) or is_atom(rel) ->
          rel_atom = normalize_rel_name(rel)
          add_relationship_to_template(acc, resource, rel_atom, nil)

        %{} = nested_load ->
          Enum.reduce(nested_load, acc, fn {rel, sub_load}, acc ->
            rel_atom = normalize_rel_name(rel)
            add_relationship_to_template(acc, resource, rel_atom, sub_load)
          end)

        _ ->
          acc
      end
    end)
  end

  defp add_relationship_to_template(template, resource, rel_atom, sub_load) do
    relationship = Ash.Resource.Info.relationship(resource, rel_atom)

    if relationship do
      # Check if relationship is already in template
      already_in_template =
        Enum.any?(template, fn
          {k, _} when k == rel_atom -> true
          k when is_atom(k) and k == rel_atom -> true
          _ -> false
        end)

      if already_in_template do
        template
      else
        # Create nested template for the relationship
        nested_template = create_nested_template(relationship.destination, sub_load)
        template ++ [{rel_atom, nested_template}]
      end
    else
      template
    end
  end

  defp create_nested_template(resource, _sub_load) do
    # For nested relationships, when no explicit select is provided,
    # we want ALL public fields (attributes, calculations, aggregates)
    # This mimics what happens when you query the resource directly without select

    # Get all public fields
    attributes = Ash.Resource.Info.public_attributes(resource) |> Enum.map(& &1.name)
    calculations = Ash.Resource.Info.public_calculations(resource) |> Enum.map(& &1.name)
    aggregates = Ash.Resource.Info.public_aggregates(resource) |> Enum.map(& &1.name)

    # Combine all public fields into template
    attributes ++ calculations ++ aggregates
  end

  defp normalize_rel_name(rel) when is_atom(rel), do: rel

  defp normalize_rel_name(rel) when is_binary(rel),
    do: rel |> Macro.underscore() |> String.to_atom()

  defp build_nested_query_for_rel(resource, rel_atom, nested_opts) do
    with rel when not is_nil(rel) <- Ash.Resource.Info.relationship(resource, rel_atom),
         dest when is_atom(dest) <- rel.destination do
      base = Ash.Query.new(dest)
      {_base_input, qopts} = extract_query_options(nested_opts)

      # Apply nested selection if provided
      {base, _template} =
        case Map.get(qopts, :select) do
          nil ->
            {base, nil}

          select_spec ->
            requested =
              AshRpc.Rpc.RequestedFieldsProcessor.normalize_select(
                dest,
                :read,
                List.wrap(select_spec)
              )

            case AshRpc.Rpc.RequestedFieldsProcessor.process(dest, :read, requested) do
              {:ok, {select, load, template}} ->
                q = base
                q = if select != nil and select != [], do: Ash.Query.select(q, select), else: q
                q = if load != nil and load != [], do: Ash.Query.load(q, load), else: q
                {q, template}

              _ ->
                {base, nil}
            end
        end

      base
      |> apply_filter(qopts.filter, true)
      |> apply_sort(qopts.sort, true)
      |> apply_pagination(qopts.page, true)
      |> apply_relationships(qopts.load, nil, dest)
    else
      _ -> Ash.Query.new(resource)
    end
  end

  # Sort string parser inspired by ash_typescript's format_sort_string
  defp format_sort_string(sort_string) when is_binary(sort_string) do
    sort_string
    |> String.split(",")
    |> Enum.map(fn field_with_mod ->
      {dir, name} =
        case field_with_mod do
          "++" <> field_name -> {:asc, field_name}
          "--" <> field_name -> {:desc, field_name}
          "+" <> field_name -> {:asc, field_name}
          "-" <> field_name -> {:desc, field_name}
          field_name -> {:asc, field_name}
        end

      field_atom = field_with_mod_to_atom(name)
      {field_atom, dir}
    end)
  end

  defp field_with_mod_to_atom(name) do
    name |> AshRpc.Input.FieldFormatter.parse_input_field() |> to_string() |> String.to_atom()
  end

  # Convert map inputs to keyword/tuple when action argument/attribute expects them
  defp convert_keyword_tuple_inputs(input, resource, action) when is_map(input) do
    Enum.reduce(input, %{}, fn {key, value}, acc ->
      case find_input_type(key, resource, action) do
        {:tuple, constraints} when is_map(value) ->
          Map.put(acc, key, convert_map_to_tuple(value, constraints))

        {:keyword, constraints} when is_map(value) ->
          Map.put(acc, key, convert_map_to_keyword(value, constraints))

        _ ->
          Map.put(acc, key, value)
      end
    end)
  end

  defp convert_keyword_tuple_inputs(other, _resource, _action), do: other

  defp find_input_type(field_name, resource, action) do
    field_atom =
      cond do
        is_atom(field_name) ->
          field_name

        is_binary(field_name) ->
          try do
            String.to_existing_atom(field_name)
          rescue
            _ -> nil
          end

        true ->
          nil
      end

    if field_atom do
      attribute = Ash.Resource.Info.attribute(resource, field_atom)

      case attribute do
        %{type: Ash.Type.Tuple, constraints: constraints} ->
          {:tuple, constraints}

        %{type: Ash.Type.Keyword, constraints: constraints} ->
          {:keyword, constraints}

        _ ->
          case Enum.find(action.arguments || [], &(&1.name == field_atom)) do
            %{type: Ash.Type.Tuple, constraints: constraints} -> {:tuple, constraints}
            %{type: Ash.Type.Keyword, constraints: constraints} -> {:keyword, constraints}
            _ -> :other
          end
      end
    else
      :other
    end
  end

  defp convert_map_to_tuple(value, constraints) when is_map(value) do
    field_constraints = Keyword.get(constraints || [], :fields, [])
    field_order = Enum.map(field_constraints, fn {field_name, _} -> field_name end)

    tuple_values =
      Enum.map(field_order, fn field_name ->
        atom_key = field_name
        string_key = if is_atom(field_name), do: Atom.to_string(field_name), else: field_name
        Map.get(value, atom_key) || Map.get(value, string_key)
      end)

    List.to_tuple(tuple_values)
  end

  defp convert_map_to_tuple(value, _constraints), do: value

  defp convert_map_to_keyword(value, constraints) when is_map(value) do
    field_constraints = Keyword.get(constraints || [], :fields, [])
    allowed_fields = field_constraints |> Enum.map(fn {n, _} -> n end) |> MapSet.new()

    Enum.reduce(value, [], fn {key, val}, kw ->
      atom_key =
        cond do
          is_atom(key) ->
            key

          is_binary(key) ->
            try do
              String.to_existing_atom(key)
            rescue
              _ ->
                raise ArgumentError,
                      "Invalid keyword field: #{inspect(key)}. Allowed fields: #{inspect(MapSet.to_list(allowed_fields))}"
            end

          true ->
            key
        end

      unless MapSet.member?(allowed_fields, atom_key) do
        raise ArgumentError,
              "Invalid keyword field: #{inspect(atom_key)}. Allowed fields: #{inspect(MapSet.to_list(allowed_fields))}"
      end

      Keyword.put(kw, atom_key, val)
    end)
  end

  defp convert_map_to_keyword(value, _constraints), do: value
end
