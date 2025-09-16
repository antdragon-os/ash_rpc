defmodule AshRpc.Input.InputProcessor do
  @moduledoc """
  Elegant input processing with pattern matching and validation.
  Handles input normalization, query option extraction, and cursor processing.
  """

  @type raw_input :: map()
  @type processed_input :: map()
  @type query_options :: %{
          filter: map() | nil,
          sort: map() | nil,
          select: list() | nil,
          page: map() | nil,
          load: list() | nil
        }
  @type processing_result :: {:ok, processed_input(), query_options()} | {:error, term()}

  @query_option_keys ["filter", "sort", "select", "page", "load", "cursor", "nextCursor"]

  @doc """
  Processes raw input into normalized input and query options.
  Handles cursor merging and input validation.
  """
  @spec process(Ash.Resource.t(), Ash.Resource.Actions.action(), raw_input()) :: processing_result()
  def process(resource, action, raw_input) when is_map(raw_input) do
    with {:ok, normalized_input} <- normalize_input(resource, action, raw_input),
         {:ok, base_input, query_opts} <- extract_query_options(normalized_input) do
      {:ok, base_input, query_opts}
    end
  end

  def process(_resource, _action, invalid_input) do
    {:error, {:invalid_input, invalid_input}}
  end

  # Input normalization with pattern matching

  defp normalize_input(resource, %{type: action_type} = action, input) when is_map(input) do
    try do
      include_list = build_include_list(resource, action_type, action)
      normalized = normalize_fields(input, include_list)
      {:ok, normalized}
    rescue
      error -> {:error, {:normalization_error, error}}
    end
  end

  defp normalize_input(_resource, _action, input) do
    {:ok, input}
  end

  # Pattern matching for action types

  defp build_include_list(resource, :read, action) do
    base_fields = get_base_fields(resource, action)
    query_options = @query_option_keys ++ ["validate_only"]
    base_fields ++ query_options
  end

  defp build_include_list(resource, action_type, _action) when action_type in [:update, :destroy] do
    base_fields = get_base_fields(resource)
    pk_fields = get_primary_key_fields(resource)
    base_fields ++ pk_fields ++ ["validate_only"]
  end

  defp build_include_list(resource, _action_type, _action) do
    get_base_fields(resource) ++ ["validate_only"]
  end

  defp get_base_fields(_resource, action) do
    try do
      # Get action arguments (like search) and accepted fields
      arg_names = (action.arguments || []) |> Enum.map(& &1.name) |> Enum.map(&Atom.to_string/1)
      accepted = (Map.get(action, :accept) || []) |> List.wrap() |> Enum.map(&Atom.to_string/1)
      arg_names ++ accepted
    rescue
      _ -> []
    end
  end

  defp get_base_fields(_resource) do
    []
  end

  defp get_primary_key_fields(resource) do
    resource
    |> Ash.Resource.Info.primary_key()
    |> Enum.map(&Atom.to_string/1)
  end

  defp normalize_fields(input, include_list) do
    Enum.reduce(include_list, %{}, fn key, acc ->
      case find_field_value(input, key) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  # Field value extraction with pattern matching

  defp find_field_value(input, key) when is_binary(key) do
    cond do
      Map.has_key?(input, key) -> Map.get(input, key)
      Map.has_key?(input, String.to_atom(key)) -> Map.get(input, String.to_atom(key))
      true -> nil
    end
  end

  defp find_field_value(input, key) when is_atom(key) do
    cond do
      Map.has_key?(input, key) -> Map.get(input, key)
      Map.has_key?(input, Atom.to_string(key)) -> Map.get(input, Atom.to_string(key))
      true -> nil
    end
  end

  # Query options extraction with pattern matching

  defp extract_query_options(input) when is_map(input) do
    try do
      {base_input, query_opts} = split_input_and_options(input)
      enhanced_query_opts = process_cursor_options(query_opts)
      {:ok, base_input, enhanced_query_opts}
    rescue
      error -> {:error, {:extraction_error, error}}
    end
  end

  defp extract_query_options(input) do
    {:ok, input, %{}}
  end

  defp split_input_and_options(input) do
    base_input = Map.drop(input, @query_option_keys)

    query_opts = %{
      filter: Map.get(input, "filter"),
      sort: Map.get(input, "sort"),
      select: Map.get(input, "select"),
      page: extract_page_options(input),
      load: Map.get(input, "load")
    }

    {base_input, query_opts}
  end

  # Cursor processing with pattern matching

  defp extract_page_options(input) do
    base_page = Map.get(input, "page") || %{}
    cursor = Map.get(input, "cursor") || Map.get(input, "nextCursor")

    case {base_page, cursor} do
      {page, nil} when map_size(page) == 0 -> nil
      {page, nil} -> page
      {page, cursor_value} -> Map.put(page, "after", cursor_value)
    end
  end

  defp process_cursor_options(%{page: nil} = opts), do: opts

  defp process_cursor_options(%{page: page} = opts) when map_size(page) == 0 do
    Map.put(opts, :page, nil)
  end

  defp process_cursor_options(opts), do: opts

  @doc """
  Validates input against action requirements.
  """
  @spec validate_input(Ash.Resource.Actions.action(), processed_input()) :: :ok | {:error, term()}
  def validate_input(%{type: :read}, _input), do: :ok

  def validate_input(%{type: action_type} = action, input) when action_type in [:create, :update] do
    case validate_required_fields(action, input) do
      :ok -> validate_accepted_fields(action, input)
      error -> error
    end
  end

  def validate_input(_action, _input), do: :ok

  # Validation with pattern matching

  defp validate_required_fields(%{arguments: arguments}, input) do
    required_args = Enum.filter(arguments, &(&1.allow_nil? == false))

    case find_missing_required_fields(required_args, input) do
      [] -> :ok
      missing -> {:error, {:missing_required_fields, missing}}
    end
  end

  defp validate_required_fields(_action, _input), do: :ok

  defp validate_accepted_fields(%{accept: accept}, input) when is_list(accept) do
    input_keys = Map.keys(input) |> Enum.map(&ensure_atom/1)

    case Enum.reject(input_keys, &(&1 in accept)) do
      [] -> :ok
      invalid -> {:error, {:invalid_fields, invalid}}
    end
  end

  defp validate_accepted_fields(_action, _input), do: :ok

  defp find_missing_required_fields(required_args, input) do
    Enum.reduce(required_args, [], fn arg, missing ->
      arg_name = arg.name

      if has_field?(input, arg_name) do
        missing
      else
        [arg_name | missing]
      end
    end)
  end

  defp has_field?(input, field_name) when is_atom(field_name) do
    Map.has_key?(input, field_name) || Map.has_key?(input, Atom.to_string(field_name))
  end

  defp ensure_atom(value) when is_atom(value), do: value
  defp ensure_atom(value) when is_binary(value), do: String.to_atom(value)
  defp ensure_atom(value), do: value
end
