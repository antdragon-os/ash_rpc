defmodule AshRpc.Util.Subscriptions do
  @moduledoc """
  Helpers for topic derivation and broadcasting TRPC subscription messages.

  This module is transport-agnostic and can be wired into any transport that
  listens for PubSub events and forwards them to clients.
  """

  @type pubsub :: module()

  @spec topic_for(map()) :: String.t()
  def topic_for(%{procedure: procedure, input: input}) when is_binary(procedure) do
    hash = :erlang.phash2(input)
    "trpc:" <> procedure <> ":" <> Integer.to_string(hash)
  end

  def topic_for(%{procedure: procedure}) when is_binary(procedure) do
    "trpc:" <> procedure
  end

  def topic_for(_), do: "trpc:unknown"

  @spec broadcast_next(pubsub, map(), term()) :: :ok
  def broadcast_next(pubsub, ctx, data) do
    topic = topic_for(ctx)
    Phoenix.PubSub.broadcast(pubsub, topic, {:trpc, :next, topic, data, ctx})
  end

  @spec broadcast_error(pubsub, map(), term()) :: :ok
  def broadcast_error(pubsub, ctx, error) do
    topic = topic_for(ctx)
    Phoenix.PubSub.broadcast(pubsub, topic, {:trpc, :error, topic, error, ctx})
  end

  @spec broadcast_complete(pubsub, map()) :: :ok
  def broadcast_complete(pubsub, ctx) do
    topic = topic_for(ctx)
    Phoenix.PubSub.broadcast(pubsub, topic, {:trpc, :complete, topic, ctx})
  end
end
