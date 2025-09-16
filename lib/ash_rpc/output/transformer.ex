defmodule AshRpc.Output.Transformer do
  @moduledoc false

  @callback encode(term) :: term
  @callback decode(term) :: term

  defmodule Identity do
    @behaviour AshRpc.Output.Transformer
    @impl true
    def encode(term), do: term
    @impl true
    def decode(term), do: term
  end

  @spec encode(term, module) :: term
  def encode(term, transformer \\ Identity) do
    try do
      transformer.encode(term)
    rescue
      _ -> term
    end
  end

  @spec decode(term, module) :: term
  def decode(term, transformer \\ Identity) do
    try do
      transformer.decode(term)
    rescue
      _ -> term
    end
  end
end
