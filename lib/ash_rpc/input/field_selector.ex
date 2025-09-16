defmodule AshRpc.Input.FieldSelector do
  @moduledoc """
  Elegant field selection with pattern matching.
  Handles select, load, and extraction template generation.
  """

  alias AshRpc.Rpc.RequestedFieldsProcessor

  @type field_selection :: list() | nil
  @type selection_result :: {:ok, {list() | nil, list(), list()}} | {:error, term()}
  @type template_result :: {:ok, list()} | {:error, term()}

  @doc """
  Processes field selection and returns {select, load, template} tuple.
  """
  @spec process_selection(Ash.Resource.t(), atom(), field_selection()) :: selection_result()
  def process_selection(resource, action_name, select_fields) when is_list(select_fields) do
    try do
      atomized_fields = RequestedFieldsProcessor.atomize_requested_fields(select_fields)

      case RequestedFieldsProcessor.process(resource, action_name, atomized_fields) do
        {:ok, result} -> {:ok, result}
        {:error, _} = error -> error
      end
    rescue
      error -> {:error, {:field_selection_error, error}}
    end
  end

  def process_selection(_resource, _action_name, nil) do
    {:ok, {nil, [], []}}
  end

  def process_selection(_resource, _action_name, _invalid) do
    {:error, :invalid_field_selection}
  end

  @doc """
  Builds default template with all public fields when no selection is provided.
  """
  @spec build_default_template(Ash.Resource.t(), list() | nil) :: template_result()
  def build_default_template(resource, load_opts) do
    try do
      template = build_public_fields_template(resource, load_opts)
      {:ok, template}
    rescue
      error -> {:error, {:template_error, error}}
    end
  end

  # Private functions with pattern matching

  defp build_public_fields_template(resource, load_opts) do
    public_attrs = get_public_attributes(resource)
    public_calcs = get_public_calculations(resource)
    public_aggs = get_public_aggregates(resource)

    # Create nested templates for loaded relationships
    relationship_templates = build_relationship_templates(resource, load_opts)

    # Combine all public fields with relationship templates
    (public_attrs ++ public_calcs ++ public_aggs ++ relationship_templates)
    |> Enum.uniq()
  end

  defp get_public_attributes(resource) do
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Enum.map(& &1.name)
  end

  defp get_public_calculations(resource) do
    resource
    |> Ash.Resource.Info.public_calculations()
    |> Enum.map(& &1.name)
  end

  defp get_public_aggregates(resource) do
    resource
    |> Ash.Resource.Info.public_aggregates()
    |> Enum.map(& &1.name)
  end

  # Load field normalization with pattern matching


  @doc """
  Validates that requested fields exist on the resource.
  """
  @spec validate_fields(Ash.Resource.t(), list()) :: :ok | {:error, term()}
  def validate_fields(resource, requested_fields) when is_list(requested_fields) do
    available_fields = get_all_available_fields(resource)

    case find_invalid_fields(requested_fields, available_fields) do
      [] -> :ok
      invalid -> {:error, {:invalid_fields, invalid}}
    end
  end

  def validate_fields(_resource, _), do: :ok

  defp get_all_available_fields(resource) do
    attrs = get_public_attributes(resource)
    calcs = get_public_calculations(resource)
    aggs = get_public_aggregates(resource)
    relationships = get_public_relationships(resource)

    attrs ++ calcs ++ aggs ++ relationships
  end

  defp get_public_relationships(resource) do
    resource
    |> Ash.Resource.Info.public_relationships()
    |> Enum.map(& &1.name)
  end

  defp find_invalid_fields(requested, available) do
    requested
    |> Enum.reject(&(&1 in available))
  end

  # Build nested templates for loaded relationships
  defp build_relationship_templates(_resource, nil), do: []
  defp build_relationship_templates(_resource, []), do: []

  defp build_relationship_templates(resource, load_opts) when is_list(load_opts) do
    Enum.flat_map(load_opts, fn load_field ->
      build_relationship_template(resource, load_field)
    end)
  end

  defp build_relationship_templates(resource, single_load) do
    build_relationship_template(resource, single_load)
  end

  defp build_relationship_template(resource, field) when is_binary(field) do
    # Convert camelCase to snake_case atom
    field_atom = AshRpc.Util.Util.camel_to_snake(field)
    build_relationship_template(resource, field_atom)
  end

  defp build_relationship_template(resource, field_atom) when is_atom(field_atom) do
    case Ash.Resource.Info.relationship(resource, field_atom) do
      nil ->
        # Not a relationship, just include as regular field
        [field_atom]

      rel ->
        # It's a relationship, create nested template with all public fields of destination
        destination_attrs = get_public_attributes(rel.destination)
        destination_calcs = get_public_calculations(rel.destination)
        destination_aggs = get_public_aggregates(rel.destination)
        nested_template = destination_attrs ++ destination_calcs ++ destination_aggs

        [{field_atom, nested_template}]
    end
  end

  defp build_relationship_template(_resource, _other), do: []
end
