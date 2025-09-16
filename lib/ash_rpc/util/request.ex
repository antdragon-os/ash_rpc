defmodule AshRpc.Util.Request do
  @moduledoc """
  Represents a parsed and validated RPC request.

  This struct contains all the information needed to execute an Ash action,
  including the resource, action, input parameters, field selection, and
  execution context.

  Based on the proven architecture from ash_typescript.
  """

  @type t :: %__MODULE__{
          resource: module(),
          action: Ash.Resource.Actions.action(),
          tenant: term(),
          actor: term(),
          context: map(),
          select: list(atom()) | nil,
          load: list() | nil,
          extraction_template: list() | nil,
          input: map(),
          primary_key: term() | nil,
          filter: term() | nil,
          sort: term() | nil,
          pagination: map() | nil
        }

  defstruct [
    :resource,
    :action,
    :tenant,
    :actor,
    :context,
    :select,
    :load,
    :extraction_template,
    :input,
    :primary_key,
    :filter,
    :sort,
    :pagination
  ]

  @doc """
  Creates a new Request struct with the given parameters.

  ## Parameters
  - `params` - Map containing request parameters

  ## Returns
  - `%Request{}` - A new Request struct

  ## Examples

      iex> Request.new(%{
      ...>   resource: MyApp.Todo,
      ...>   action: %Ash.Resource.Actions.Read{name: :read},
      ...>   input: %{},
      ...>   select: [:id, :title],
      ...>   load: [],
      ...>   extraction_template: [:id, :title]
      ...> })
      %Request{resource: MyApp.Todo, action: %Ash.Resource.Actions.Read{...}, ...}
  """
  @spec new(map()) :: t()
  def new(params) when is_map(params) do
    struct(__MODULE__, params)
  end

  @doc """
  Validates that a Request struct has all required fields.

  ## Parameters
  - `request` - The Request struct to validate

  ## Returns
  - `:ok` - If the request is valid
  - `{:error, reason}` - If validation fails
  """
  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = request) do
    cond do
      is_nil(request.resource) ->
        {:error, {:missing_required_field, :resource}}

      is_nil(request.action) ->
        {:error, {:missing_required_field, :action}}

      is_nil(request.input) ->
        {:error, {:missing_required_field, :input}}

      true ->
        :ok
    end
  end

  def validate(_) do
    {:error, {:invalid_request_type}}
  end
end
