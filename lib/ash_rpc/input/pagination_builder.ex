defmodule AshRpc.Input.PaginationBuilder do
  @moduledoc """
  Elegant pagination handling with pattern matching.
  Supports both offset-based and keyset (cursor) pagination.
  """

  @type pagination_type :: :offset | :keyset
  @type page_options :: %{
          optional(String.t() | atom()) => any()
        }
  @type apply_result :: {:ok, Ash.Query.t()} | {:error, term()}

  @doc """
  Applies pagination to a query based on page options.
  Automatically detects pagination strategy and applies appropriate options.
  Supports validation for infinite queries (keyset only).
  """
  @spec apply(Ash.Query.t(), page_options()) :: apply_result()

  def apply(query, page_opts) when is_map(page_opts) do
    # Check for explicit type first
    explicit_type = Map.get(page_opts, "type") || Map.get(page_opts, :type)

    case explicit_type do
      "offset" ->
        # Explicit offset type - always use offset pagination
        {:ok, :offset, opts} = detect_pagination_type(page_opts)
        apply_offset_pagination(query, opts)

      "keyset" ->
        # Explicit keyset type - always use keyset pagination
        {:ok, :keyset, opts} = detect_pagination_type(page_opts)
        apply_keyset_pagination(query, opts)

      nil ->
        # No explicit type - default to keyset pagination
        opts = normalize_keyset_options(page_opts)
        apply_keyset_pagination(query, opts)

      _ ->
        # Invalid type
        {:error,
         {:invalid_pagination,
          "Invalid pagination type '#{explicit_type}'. Use 'offset' or 'keyset'."}}
    end
  end

  def apply(query, page_opts) when is_integer(page_opts) do
    # Simple limit-only pagination defaults to keyset
    apply_keyset_pagination(query, %{limit: page_opts})
  end

  def apply(query, _), do: {:ok, query}

  # Pattern matching for pagination type detection with explicit type field
  # Priority: explicit type > auto-detection > default to keyset

  defp detect_pagination_type(%{"type" => "offset"} = page_opts) do
    # Explicit offset type - always use offset pagination
    {:ok, :offset, normalize_offset_options(page_opts)}
  end

  defp detect_pagination_type(%{type: "offset"} = page_opts) do
    # Explicit offset type - always use offset pagination
    {:ok, :offset, normalize_offset_options(page_opts)}
  end

  defp detect_pagination_type(%{"type" => "keyset"} = page_opts) do
    # Explicit keyset type - always use keyset pagination
    {:ok, :keyset, normalize_keyset_options(page_opts)}
  end

  defp detect_pagination_type(%{type: "keyset"} = page_opts) do
    # Explicit keyset type - always use keyset pagination
    {:ok, :keyset, normalize_keyset_options(page_opts)}
  end

  # Auto-detection fallbacks (when no explicit type is provided)
  defp detect_pagination_type(%{"offset" => _} = page_opts)
       when not is_map_key(page_opts, "after") and not is_map_key(page_opts, "before") do
    {:ok, :offset, normalize_offset_options(page_opts)}
  end

  defp detect_pagination_type(%{offset: _} = page_opts)
       when not is_map_key(page_opts, :after) and not is_map_key(page_opts, :before) do
    {:ok, :offset, normalize_offset_options(page_opts)}
  end

  defp detect_pagination_type(page_opts)
       when is_map_key(page_opts, "after") or is_map_key(page_opts, "before") or
              is_map_key(page_opts, :after) or is_map_key(page_opts, :before) do
    {:ok, :keyset, normalize_keyset_options(page_opts)}
  end

  defp detect_pagination_type(_page_opts) do
    # Default to keyset pagination when no explicit type or detection criteria
    {:ok, :keyset, normalize_keyset_options(%{})}
  end

  # Offset pagination pattern matching

  defp apply_offset_pagination(query, opts) do
    try do
      paginated_query = Ash.Query.page(query, build_offset_keyword_list(opts))
      {:ok, paginated_query}
    rescue
      error -> {:error, {:pagination_error, error}}
    end
  end

  defp build_offset_keyword_list(%{limit: limit, offset: offset, count: count}) do
    [limit: limit, offset: offset, count: count]
  end

  defp build_offset_keyword_list(%{limit: limit, offset: offset}) do
    [limit: limit, offset: offset]
  end

  defp build_offset_keyword_list(%{limit: limit, count: count}) do
    [limit: limit, offset: 0, count: count]
  end

  defp build_offset_keyword_list(%{limit: limit}) do
    [limit: limit, offset: 0]
  end

  # Keyset pagination pattern matching

  defp apply_keyset_pagination(query, opts) do
    try do
      paginated_query = Ash.Query.page(query, build_keyset_keyword_list(opts))
      {:ok, paginated_query}
    rescue
      error -> {:error, {:pagination_error, error}}
    end
  end

  defp build_keyset_keyword_list(%{
         limit: limit,
         after: after_cursor,
         before: before_cursor,
         count: count
       }) do
    [limit: limit, after: after_cursor, before: before_cursor, count: count]
  end

  defp build_keyset_keyword_list(%{limit: limit, after: after_cursor, count: count}) do
    [limit: limit, after: after_cursor, count: count]
  end

  defp build_keyset_keyword_list(%{limit: limit, before: before_cursor, count: count}) do
    [limit: limit, before: before_cursor, count: count]
  end

  defp build_keyset_keyword_list(%{limit: limit, after: after_cursor}) do
    [limit: limit, after: after_cursor]
  end

  defp build_keyset_keyword_list(%{limit: limit, before: before_cursor}) do
    [limit: limit, before: before_cursor]
  end

  defp build_keyset_keyword_list(%{limit: limit, count: count}) do
    [limit: limit, count: count]
  end

  defp build_keyset_keyword_list(%{limit: limit}) do
    [limit: limit]
  end

  defp build_keyset_keyword_list(_) do
    # Default limit
    [limit: 20]
  end

  # Option normalization with pattern matching

  defp normalize_offset_options(page_opts) do
    # Support both offset and page-based offset pagination
    limit = extract_integer(page_opts, ["limit", :limit], 20)

    # Calculate offset from either explicit offset or page number
    offset =
      case find_value(page_opts, ["page", :page]) do
        nil ->
          # Use explicit offset
          extract_integer(page_opts, ["offset", :offset], 0)

        page_num when is_integer(page_num) and page_num > 0 ->
          # Convert page number to offset (1-based page)
          (page_num - 1) * limit

        page_str when is_binary(page_str) ->
          # Convert string page number to offset
          page_num = String.to_integer(page_str)
          if page_num > 0, do: (page_num - 1) * limit, else: 0

        _ ->
          0
      end

    %{
      limit: limit,
      offset: offset,
      count: extract_boolean(page_opts, ["count", :count], false)
    }
  end

  defp normalize_keyset_options(page_opts) do
    base = %{
      limit: extract_integer(page_opts, ["limit", :limit], 20),
      count: extract_boolean(page_opts, ["count", :count], false)
    }

    base
    |> maybe_put_cursor(:after, page_opts, ["after", :after])
    |> maybe_put_cursor(:before, page_opts, ["before", :before])
  end

  # Helper functions with pattern matching

  defp extract_integer(map, keys, default) do
    case find_value(map, keys) do
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
      _ -> default
    end
  end

  defp extract_boolean(map, keys, default) do
    case find_value(map, keys) do
      value when is_boolean(value) -> value
      "true" -> true
      "false" -> false
      _ -> default
    end
  end

  defp find_value(map, [key | rest]) do
    case Map.get(map, key) do
      nil -> find_value(map, rest)
      value -> value
    end
  end

  defp find_value(_, []), do: nil

  defp maybe_put_cursor(map, cursor_key, page_opts, search_keys) do
    case find_value(page_opts, search_keys) do
      nil -> map
      cursor -> Map.put(map, cursor_key, cursor)
    end
  end
end
