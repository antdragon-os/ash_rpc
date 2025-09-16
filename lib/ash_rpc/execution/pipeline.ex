defmodule AshRpc.Execution.Pipeline do
  @moduledoc """
  Implements the four-stage pipeline for AshRpc processing:
  1. parse_request/3 - Parse and validate input with fail-fast
  2. execute_ash_action/1 - Execute Ash operations
  3. process_result/2 - Apply field selection
  4. format_output/1 - Format for client consumption

  Based on the proven architecture from ash_typescript, adapted for tRPC.
  """

  alias AshRpc.{Util.Request, Input.FieldFormatter, Config.Config}
  alias AshRpc.Rpc.RequestedFieldsProcessor

  @doc """
  Stage 1: Parse and validate request.

  Converts raw request parameters into a structured Request with validated fields.
  Fails fast on any invalid input - no permissive modes.
  """
  @spec parse_request(map(), map(), keyword()) :: {:ok, Request.t()} | {:error, term()}
  def parse_request(ctx, input, opts \\ []) do
    validation_mode? = Keyword.get(opts, :validation_mode?, false)
    input_formatter = Config.input_field_formatter()
    normalized_input = FieldFormatter.parse_input_fields(input, input_formatter)

    with {:ok, {resource, action}} <- discover_action(ctx),
         :ok <-
           validate_required_parameters_for_action_type(normalized_input, action, validation_mode?),
         {select, load, template} <-
           parse_field_selection(normalized_input[:select], resource, action),
         {:ok, parsed_input} <- parse_action_input(normalized_input, action, resource),
         {:ok, pagination} <- parse_pagination(normalized_input) do
      formatted_sort = format_sort_string(normalized_input[:sort], input_formatter)

      request =
        Request.new(%{
          resource: resource,
          action: action,
          tenant: normalized_input[:tenant] || get_tenant_from_ctx(ctx),
          actor: get_actor_from_ctx(ctx),
          context: get_context_from_ctx(ctx) || %{},
          select: select,
          load: load,
          extraction_template: template,
          input: parsed_input,
          primary_key: normalized_input[:primary_key],
          filter: normalized_input[:filter],
          sort: formatted_sort,
          pagination: pagination
        })

      {:ok, request}
    else
      error -> error
    end
  end

  @doc """
  Stage 2: Execute Ash action using the parsed request.

  Builds the appropriate Ash query/changeset and executes it.
  Returns the raw Ash result for further processing.
  """
  @spec execute_ash_action(Request.t()) :: {:ok, term()} | {:error, term()}
  def execute_ash_action(%Request{} = request) do
    opts = [
      actor: request.actor,
      tenant: request.tenant,
      context: request.context
    ]

    case request.action.type do
      :read ->
        execute_read_action(request, opts)

      :create ->
        execute_create_action(request, opts)

      :update ->
        execute_update_action(request, opts)

      :destroy ->
        execute_destroy_action(request, opts)

      :action ->
        execute_generic_action(request, opts)
    end
  end

  @doc """
  Stage 3: Process result using the extraction template.

  Applies field selection to the Ash result using the pre-computed template.
  Performance-optimized single-pass filtering.
  """
  @spec process_result(term(), Request.t()) :: {:ok, term()} | {:error, term()}
  def process_result(ash_result, %Request{} = request) do
    case ash_result do
      {:ok, result} when is_list(result) or is_map(result) or is_tuple(result) ->
        filtered = AshRpc.Output.ResultProcessor.process(result, request.extraction_template)
        {:ok, filtered}

      {:error, error} ->
        {:error, error}

      primitive_value ->
        {:ok, AshRpc.Output.ResultProcessor.normalize_value_for_json(primitive_value)}
    end
  end

  @doc """
  Stage 4: Format output for client consumption.

  Applies output field formatting and final response structure.
  """
  @spec format_output(term()) :: term()
  def format_output(filtered_result) do
    formatter = Config.output_field_formatter()
    format_field_names(filtered_result, formatter)
  end

  # Private functions for action discovery and execution

  defp discover_action(ctx) do
    procedure = Map.get(ctx, :procedure)

    # Use the existing resolve_for_ctx function from the executor
    case AshRpc.Execution.Executor.resolve_for_ctx(ctx, procedure) do
      {:ok, resource, action, _method_override} ->
        {:ok, {resource, action}}

      :invalid_path ->
        {:error, {:action_not_found, procedure}}

      _other ->
        {:error, {:action_not_found, procedure}}
    end
  end

  defp validate_required_parameters_for_action_type(_params, _action, _validation_mode?) do
    # In ash_rpc, all parameters are optional:
    # - 'select' is optional (if not provided, selects all public fields)
    # - 'load' is optional (if not provided, no associations are loaded)
    # - 'filter', 'sort', etc. are all optional
    # This is different from ash_typescript which requires 'fields'
    :ok
  end

  defp parse_field_selection(nil, _resource, _action) do
    # When no select is provided, don't filter - return all data
    # This matches the original executor behavior
    {nil, [], nil}
  end

  defp parse_field_selection(select_list, resource, action) when is_list(select_list) do
    # When select is explicitly provided, process it
    requested_fields = RequestedFieldsProcessor.atomize_requested_fields(select_list)

    case RequestedFieldsProcessor.process(resource, action.name, requested_fields) do
      {:ok, {select, load, template}} -> {select, load, template}
      # Fall back to no filtering on error
      {:error, _} -> {nil, [], nil}
    end
  end

  defp parse_field_selection(_other, _resource, _action) do
    # Invalid select format - fall back to no filtering
    {nil, [], nil}
  end

  defp parse_action_input(params, action, resource) do
    # Extract action arguments and accepted attributes
    arg_names = (action.arguments || []) |> Enum.map(& &1.name)

    # Only Create/Update actions have 'accept' field, Read actions don't
    accepted =
      case action.type do
        t when t in [:create, :update] -> (action.accept || []) |> List.wrap()
        _ -> []
      end

    pk_names = Ash.Resource.Info.primary_key(resource)

    allowed_keys =
      case action.type do
        t when t in [:update, :destroy] -> arg_names ++ accepted ++ pk_names
        _ -> arg_names ++ accepted
      end

    input =
      Enum.reduce(allowed_keys, %{}, fn key, acc ->
        case Map.get(params, key) do
          nil -> acc
          value -> Map.put(acc, key, value)
        end
      end)

    {:ok, input}
  end

  defp parse_pagination(params) do
    page_params = %{}

    page_params =
      if Map.has_key?(params, :page) do
        case params[:page] do
          %{} = page_map -> Map.merge(page_params, page_map)
          _ -> page_params
        end
      else
        page_params
      end

    # Add individual pagination parameters
    page_params =
      Enum.reduce([:limit, :offset, :after, :before, :count], page_params, fn key, acc ->
        case Map.get(params, key) do
          nil -> acc
          value -> Map.put(acc, key, value)
        end
      end)

    if map_size(page_params) == 0 do
      {:ok, nil}
    else
      {:ok, page_params}
    end
  end

  defp format_sort_string(nil, _formatter), do: nil

  defp format_sort_string(sort, formatter) when is_binary(sort) do
    sort
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn field_spec ->
      case field_spec do
        "--" <> field_name ->
          ("--" <> FieldFormatter.parse_input_field(field_name, formatter)) |> to_string()

        "++" <> field_name ->
          ("++" <> FieldFormatter.parse_input_field(field_name, formatter)) |> to_string()

        "-" <> field_name ->
          ("-" <> FieldFormatter.parse_input_field(field_name, formatter)) |> to_string()

        "+" <> field_name ->
          ("+" <> FieldFormatter.parse_input_field(field_name, formatter)) |> to_string()

        field_name ->
          FieldFormatter.parse_input_field(field_name, formatter) |> to_string()
      end
    end)
    |> Enum.join(",")
  end

  defp format_sort_string(sort, _formatter), do: sort

  # Action execution functions

  defp execute_read_action(%Request{} = request, opts) do
    query =
      request.resource
      |> Ash.Query.for_read(request.action.name, request.input, opts)
      |> apply_select(request.select)
      |> apply_load(request.load)
      |> apply_filter(request.filter)
      |> apply_sort(request.sort)
      |> apply_pagination(request.pagination)

    case Ash.read(query, opts) do
      {:ok, result} ->
        # Handle get? actions specially
        if request.action.get? do
          case result do
            %Ash.Page.Offset{results: [record | _]} -> {:ok, record}
            %Ash.Page.Keyset{results: [record | _]} -> {:ok, record}
            [record | _] -> {:ok, record}
            record -> {:ok, record}
            _ -> {:ok, nil}
          end
        else
          {:ok, result}
        end

      {:error, error} ->
        # Handle forbidden read errors gracefully
        if forbidden_read_error?(error) do
          if request.action.get? do
            {:ok, nil}
          else
            {:ok, []}
          end
        else
          {:error, error}
        end
    end
  end

  defp execute_create_action(%Request{} = request, opts) do
    request.resource
    |> Ash.Changeset.for_create(request.action.name, request.input, opts)
    |> apply_changeset_select(request.select)
    |> apply_changeset_load(request.load)
    |> Ash.create(opts)
  end

  defp execute_update_action(%Request{} = request, opts) do
    with {:ok, record} <- Ash.get(request.resource, request.primary_key, opts) do
      record
      |> Ash.Changeset.for_update(request.action.name, request.input, opts)
      |> apply_changeset_select(request.select)
      |> apply_changeset_load(request.load)
      |> Ash.update(opts)
    end
  end

  defp execute_destroy_action(%Request{} = request, opts) do
    with {:ok, record} <- Ash.get(request.resource, request.primary_key, opts) do
      record
      |> Ash.Changeset.for_destroy(request.action.name, request.input, opts)
      |> Ash.destroy(opts)
      |> case do
        :ok -> {:ok, %{}}
        error -> error
      end
    end
  end

  defp execute_generic_action(%Request{} = request, opts) do
    action_result =
      request.resource
      |> Ash.ActionInput.for_action(request.action.name, request.input, opts)
      |> Ash.run_action()

    case action_result do
      {:ok, result} ->
        # Check if the action returns a resource type that supports loading
        returns_resource? =
          case determine_action_return_type(request.action) do
            {:resource, _} -> true
            {:array_of_resource, _} -> true
            _ -> false
          end

        if returns_resource? and not Enum.empty?(request.load) do
          Ash.load(result, request.load, opts)
        else
          action_result
        end

      :ok ->
        {:ok, %{}}

      _ ->
        action_result
    end
  end

  # Query/changeset helper functions

  defp apply_select(query, nil), do: query
  defp apply_select(query, []), do: query
  defp apply_select(query, select), do: Ash.Query.select(query, select)

  defp apply_load(query, nil), do: query
  defp apply_load(query, []), do: query
  defp apply_load(query, load), do: Ash.Query.load(query, load)

  defp apply_filter(query, nil), do: query
  defp apply_filter(query, filter), do: Ash.Query.filter_input(query, filter)

  defp apply_sort(query, nil), do: query
  defp apply_sort(query, sort), do: Ash.Query.sort_input(query, sort)

  defp apply_pagination(query, nil), do: Ash.Query.page(query, nil)
  defp apply_pagination(query, page), do: Ash.Query.page(query, page)

  defp apply_changeset_select(changeset, nil), do: changeset
  defp apply_changeset_select(changeset, []), do: changeset
  defp apply_changeset_select(changeset, select), do: Ash.Changeset.select(changeset, select)

  defp apply_changeset_load(changeset, nil), do: changeset
  defp apply_changeset_load(changeset, []), do: changeset
  defp apply_changeset_load(changeset, load), do: Ash.Changeset.load(changeset, load)

  # Context helper functions

  defp get_tenant_from_ctx(ctx) do
    case ctx do
      %{conn: conn} when not is_nil(conn) -> Ash.PlugHelpers.get_tenant(conn)
      _ -> nil
    end
  end

  defp get_actor_from_ctx(ctx) do
    case ctx do
      %{conn: conn} when not is_nil(conn) -> Ash.PlugHelpers.get_actor(conn)
      _ -> nil
    end
  end

  defp get_context_from_ctx(ctx) do
    case ctx do
      %{conn: conn} when not is_nil(conn) -> Ash.PlugHelpers.get_context(conn)
      _ -> nil
    end
  end

  # Utility functions


  defp forbidden_read_error?(%Ash.Error.Forbidden{}), do: true
  defp forbidden_read_error?(%{class: :forbidden}), do: true
  defp forbidden_read_error?(_), do: false

  defp determine_action_return_type(action) do
    case action.returns do
      nil ->
        :any

      return_type when is_atom(return_type) ->
        # Check if it's a resource
        if Ash.Resource.Info.resource?(return_type) do
          {:resource, return_type}
        else
          {:ash_type, return_type}
        end

      {:array, inner_type} when is_atom(inner_type) ->
        if Ash.Resource.Info.resource?(inner_type) do
          {:array_of_resource, inner_type}
        else
          {:ash_type, {:array, inner_type}}
        end

      return_type ->
        {:ash_type, return_type}
    end
  end

  defp format_field_names(data, formatter) do
    case data do
      %{} = map ->
        Enum.into(map, %{}, fn {key, value} ->
          formatted_key = FieldFormatter.format_field(key, formatter)
          formatted_value = format_field_names(value, formatter)
          {formatted_key, formatted_value}
        end)

      list when is_list(list) ->
        Enum.map(list, &format_field_names(&1, formatter))

      other ->
        other
    end
  end
end
