defmodule AshRpc.Dsl.Procedure do
  @moduledoc false
  defstruct [
    :name,
    :action,
    :method,
    :metadata,
    :filterable,
    :sortable,
    :selectable,
    :paginatable,
    :relationships
  ]

  @spec transform(%__MODULE__{}) :: {:ok, %__MODULE__{}}
  def transform(%__MODULE__{} = procedure) do
    updated =
      procedure
      |> ensure_action()

    {:ok, updated}
  end

  defp ensure_action(%__MODULE__{action: nil, name: name} = procedure) do
    %{procedure | action: name}
  end

  defp ensure_action(procedure), do: procedure
end
