defmodule AshRpc.Input.QueryBuilder do
  @moduledoc """
  Elegant query building with functional patterns and pattern matching.
  Transforms input parameters into properly configured Ash queries.
  """

  alias AshRpc.{Input.PaginationBuilder, Input.FieldSelector}

  @type query_options :: %{
          filter: map() | nil,
          sort: map() | nil,
          select: list() | nil,
          page: map() | nil,
          load: list() | nil
        }

  @type build_result :: {:ok, Ash.Query.t(), any()} | {:error, term()}

  @doc """
  Builds a complete Ash query from resource, action, input and options.
  Returns {:ok, query, extraction_template} or {:error, reason}
  """
  @spec build(Ash.Resource.t(), Ash.Resource.Actions.action(), map(), query_options(), map()) ::
          build_result()
  def build(resource, action, base_input, query_opts, ctx) do
    with {:ok, base_query} <- build_base_query(resource, action, base_input, ctx),
         {:ok, query_with_selection, template} <-
           apply_field_selection(base_query, resource, action, query_opts),
         {:ok, query_with_filters} <- apply_filters(query_with_selection, query_opts),
         {:ok, query_with_sorts} <- apply_sorts(query_with_filters, query_opts),
         {:ok, query_with_loads} <- apply_loads(query_with_sorts, query_opts),
         {:ok, final_query} <- apply_pagination(query_with_loads, query_opts) do
      {:ok, final_query, template}
    end
  end

  # Private functions using pattern matching

  defp build_base_query(resource, action, base_input, ctx) do
    try do
      query = Ash.Query.for_read(resource, action.name, base_input, ash_opts(ctx))
      {:ok, query}
    rescue
      error -> {:error, error}
    end
  end

  defp apply_field_selection(query, resource, _action, %{select: nil, load: load_opts}) do
    # No explicit select - use all public fields
    case FieldSelector.build_default_template(resource, load_opts) do
      {:ok, template} ->
        {:ok, query, template}

      error ->
        error
    end
  end

  defp apply_field_selection(query, resource, action, %{select: select_spec})
       when is_list(select_spec) do
    case FieldSelector.process_selection(resource, action.name, select_spec) do
      {:ok, {select, load, template}} ->
        query
        |> maybe_apply_select(select)
        |> maybe_apply_load(load)
        |> then(&{:ok, &1, template})

      error ->
        error
    end
  end

  defp apply_field_selection(query, resource, _action, _opts) do
    # Fallback - no selection applied
    case FieldSelector.build_default_template(resource, nil) do
      {:ok, template} -> {:ok, query, template}
      error -> error
    end
  end

  defp apply_filters(query, %{filter: nil}), do: {:ok, query}

  defp apply_filters(query, %{filter: filter_map}) when is_map(filter_map) do
    try do
      # Process filter map: camelCase → snake_case, null → is_nil
      normalized_filter =
        filter_map
        |> normalize_filter_keys()
        |> convert_custom_predicates()

      filtered_query = Ash.Query.filter_input(query, normalized_filter)
      {:ok, filtered_query}
    rescue
      error -> {:error, {:filter_error, error}}
    end
  end

  defp apply_filters(query, _), do: {:ok, query}

  defp apply_sorts(query, %{sort: nil}), do: {:ok, query}

  defp apply_sorts(query, %{sort: sort_map}) when is_map(sort_map) do
    try do
      # Convert sort map to the format Ash expects: [{:field_name, :asc/:desc}]
      sort_expressions =
        Enum.map(sort_map, fn {field, direction} ->
          field_atom = field |> Macro.underscore() |> String.to_atom()
          direction_atom = if direction in ["desc", :desc], do: :desc, else: :asc
          {field_atom, direction_atom}
        end)

      sorted_query = Ash.Query.sort(query, sort_expressions)
      {:ok, sorted_query}
    rescue
      error -> {:error, {:sort_error, error}}
    end
  end

  defp apply_sorts(query, _), do: {:ok, query}

  defp apply_loads(query, %{load: nil}), do: {:ok, query}

  defp apply_loads(query, %{load: load_list}) when is_list(load_list) do
    try do
      # Convert camelCase load names to snake_case atoms
      processed_loads =
        Enum.map(load_list, fn
          field when is_binary(field) -> AshRpc.Util.Util.camel_to_snake(field)
          field when is_atom(field) -> field
          other -> other
        end)

      loaded_query = Ash.Query.load(query, processed_loads)
      {:ok, loaded_query}
    rescue
      error -> {:error, {:load_error, error}}
    end
  end

  defp apply_loads(query, %{load: single_load}) do
    apply_loads(query, %{load: [single_load]})
  end

  defp apply_loads(query, _), do: {:ok, query}

  defp apply_pagination(query, %{page: nil}), do: {:ok, query}

  defp apply_pagination(query, %{page: page_opts}) when is_map(page_opts) do
    PaginationBuilder.apply(query, page_opts)
  end

  defp apply_pagination(query, %{page: limit}) when is_integer(limit) do
    PaginationBuilder.apply(query, %{"limit" => limit})
  end

  defp apply_pagination(query, _), do: {:ok, query}

  # Helper functions

  defp maybe_apply_select(query, nil), do: query
  defp maybe_apply_select(query, select_fields), do: Ash.Query.select(query, select_fields)

  defp maybe_apply_load(query, []), do: query
  defp maybe_apply_load(query, load_fields), do: Ash.Query.load(query, load_fields)

  defp ash_opts(ctx) do
    base_opts = [
      actor: Map.get(ctx, :actor),
      authorize?: Map.get(ctx, :authorize?, true),
      tenant: Map.get(ctx, :tenant)
    ]

    # Add authentication context if present
    auth_context = Map.get(ctx, :private, %{}) |> Map.get(:ash_authentication?, false)

    if auth_context do
      Keyword.put(base_opts, :context, %{private: %{ash_authentication?: true}})
    else
      base_opts
    end
  end

  # Filter processing helpers (from legacy executor)

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

  # Generic map handler - convert nil values to is_nil predicates
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
end
