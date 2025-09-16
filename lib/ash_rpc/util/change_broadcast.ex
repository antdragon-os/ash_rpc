defmodule AshRpc.Util.ChangeBroadcast do
  @moduledoc """
  Change that broadcasts a TRPC subscription event after a successful action.

  Usage in a resource:

      changes do
        change AshRpc.Change.Broadcast,
          pubsub: MyApp.PubSub,
          procedure: "user.read",
          input: &__MODULE__.input_from_result/2
      end

  Options
  - `:pubsub` (required): Your Phoenix PubSub module.
  - `:procedure` (optional): The TRPC procedure name to notify. Defaults to `<segment>.read`.
  - `:input` (optional): `fn result, changeset -> map` to derive the subscription input filter.
      Defaults to the primary key values of `result`.
  - `:event` (optional): `:next | :complete | :error` – defaults to `:next`.

  Notes
  - This is transport-agnostic. Publish messages to your transport layer of
    choice so subscribed clients receive updates for matching `{procedure, input}`.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, _ctx) do
    # Use Changeset.after_action to attach the broadcast callback
    Ash.Changeset.after_action(changeset, fn changeset, result ->
      pubsub = Keyword.fetch!(opts, :pubsub)
      procedure = Keyword.get(opts, :procedure, default_procedure(changeset.resource))
      input_fun = Keyword.get(opts, :input, &__MODULE__.default_input/2)
      event = Keyword.get(opts, :event, :next)

      input = input_fun.(result, changeset)
      ctx = %{procedure: procedure, input: input}

      case event do
        :next ->
          AshRpc.Util.Subscriptions.broadcast_next(pubsub, ctx, result)

        :complete ->
          AshRpc.Util.Subscriptions.broadcast_complete(pubsub, ctx)

        {:error, err} ->
          AshRpc.Util.Subscriptions.broadcast_error(pubsub, ctx, err)

        :error ->
          AshRpc.Util.Subscriptions.broadcast_error(pubsub, ctx, %Ash.Error.Unknown{
            errors: [error: "unknown"]
          })
      end

      {:ok, result}
    end)
  end

  @doc "Default: derive input from the primary key fields of the result"
  def default_input(result, changeset) do
    resource = changeset.resource
    pks = Ash.Resource.Info.primary_key(resource)

    Enum.reduce(pks, %{}, fn key, acc ->
      case Map.fetch(result, key) do
        {:ok, val} -> Map.put(acc, key, val)
        :error -> acc
      end
    end)
  end

  defp default_procedure(resource) do
    seg =
      resource
      |> Module.split()
      |> List.last()
      |> Macro.underscore()

    seg <> ".read"
  end
end
