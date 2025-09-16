defmodule AshRpc.Util.NotifierSubscriber do
  @moduledoc """
  Generic Phoenix.PubSub subscriber that turns your domain events into
  TRPC subscription broadcasts via `AshRpc.Util.Subscriptions`.

  This does not depend on Ash.Notifier directly; instead you provide the
  PubSub topics and a mapper function that converts your event messages
  to `{kind, ctx, payload}` tuples where:

    * `kind` is one of `:next | :error | :complete`
    * `ctx` is `%{procedure: "res.proc", input: %{...}}`
    * `payload` is the payload to send (data or error)

  Example:

      children = [
        {AshRpc.NotifierSubscriber,
          pubsub: MyApp.PubSub,
          topics: ["accounts:user"],
          mapper: &MyApp.TRPCMapper.map/1
        }
      ]

      defmodule MyApp.TRPCMapper do
        def map({:user, :updated, user}) do
          {:next, %{procedure: "user.read", input: %{id: user.id}}, user}
        end
        def map(_), do: :ignore
      end

  Options:
    * `:pubsub` (required) - your Phoenix PubSub module
    * `:topics` (required) - list of topics to subscribe to
    * `:mapper` (required) - `fn event -> :ignore | {kind, ctx, payload}`

  """
  use GenServer

  @type option :: {:pubsub, module()} | {:topics, [binary()]} | {:mapper, (term() -> term())}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name))
  end

  @impl true
  def init(opts) do
    pubsub = Keyword.fetch!(opts, :pubsub)
    topics = Keyword.fetch!(opts, :topics)
    mapper = Keyword.fetch!(opts, :mapper)

    Enum.each(topics, &Phoenix.PubSub.subscribe(pubsub, &1))
    {:ok, %{pubsub: pubsub, mapper: mapper}}
  end

  @impl true
  def handle_info(message, state) do
    case state.mapper.(message) do
      :ignore ->
        {:noreply, state}

      {:next, ctx, data} ->
        AshRpc.Util.Subscriptions.broadcast_next(state.pubsub, ctx, data)
        {:noreply, state}

      {:error, ctx, error} ->
        AshRpc.Util.Subscriptions.broadcast_error(state.pubsub, ctx, error)
        {:noreply, state}

      {:complete, ctx} ->
        AshRpc.Util.Subscriptions.broadcast_complete(state.pubsub, ctx)
        {:noreply, state}

      other ->
        # Unrecognized mapping; ignore
        _ = other
        {:noreply, state}
    end
  end
end
