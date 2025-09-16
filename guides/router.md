# Backend Configuration Guide

This guide covers the backend configuration of AshRpc, including router setup, resource exposure, and advanced configuration options.

> ⚠️ **EXPERIMENTAL WARNING**: AshRpc is still in early development and considered highly experimental. Breaking changes may occur frequently without notice. We strongly advise against using this package in production environments until it reaches a stable release (v1.0.0+).

## Router Configuration

### Basic Router Setup

The main entry point for AshRpc is the router module:

```elixir
defmodule MyAppWeb.TrpcRouter do
  use AshRpc.Router,
    domains: [MyApp.Accounts, MyApp.Billing, MyApp.Notifications]
end
```

Mount it in your Phoenix router:

```elixir
# In your Phoenix router
scope "/trpc" do
  pipe_through :ash_rpc
  forward "/", MyAppWeb.TrpcRouter
end
```

### Router Options

The router accepts several configuration options:

```elixir
defmodule MyAppWeb.TrpcRouter do
  use AshRpc.Router,
    # Required: List of Ash domains to expose
    domains: [MyApp.Accounts, MyApp.Billing],

    # Optional: Custom input/output transformer
    transformer: MyApp.TrpcTransformer,

    # Optional: Before request hooks
    before: [MyApp.TrpcHooks.Logging],

    # Optional: After request hooks
    after: [MyApp.TrpcHooks.Metrics],

    # Optional: Custom context creation function
    create_context: &MyApp.TrpcContext.create/1,

    # Optional: Custom middlewares
    middlewares: [MyApp.TrpcMiddleware.Auth]
end
```

### Phoenix Pipeline Configuration

Configure the tRPC pipeline in your Phoenix router:

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  # tRPC pipeline - JSON only with authentication
  pipeline :ash_rpc do
    plug :accepts, ["json"]
    plug :retrieve_from_bearer  # Extract JWT from Authorization header
    plug :set_actor, :user      # Set current user as actor
  end

  # Alternative: tRPC pipeline without authentication
  pipeline :ash_rpc_public do
    plug :accepts, ["json"]
  end

  # Mount tRPC endpoints
  scope "/trpc" do
    pipe_through :ash_rpc
    forward "/", MyAppWeb.TrpcRouter
  end

  # Public tRPC endpoints (no auth required)
  scope "/trpc/public" do
    pipe_through :ash_rpc_public
    forward "/", MyAppWeb.PublicTrpcRouter
  end
end
```

## Resource Configuration

### Basic Resource Exposure

Configure your Ash resources to expose actions via tRPC:

```elixir
defmodule MyApp.Accounts.User do
  use Ash.Resource,
    extensions: [AshRpc],
    domain: MyApp.Accounts

  ash_rpc do
    # Expose specific actions
    expose [:read, :create, :update, :destroy]

    # Or expose all actions
    # expose :all

    # Custom resource name (defaults to module name)
    resource_name "user"
  end

  # ... rest of resource definition
end
```

### DSL Reference

#### `trpc` Block Options

- `expose`: Actions to expose (`:all` or list of action names)
- `resource_name`: Override default resource segment name
- `methods`: Override default method mappings (`[read: :query, create: :mutation]`)

#### Query Configuration

```elixir
query :read do
  filterable true        # Enable filtering (default: true)
  sortable true         # Enable sorting (default: true)
  selectable true       # Enable field selection (default: true)
  paginatable true      # Enable pagination (default: true)
  relationships [:posts, :comments]  # Loadable relationships
end

# Custom procedure name
query :search, :read do
  filterable true
  selectable false
  relationships []
end
```

#### Mutation Configuration

```elixir
mutation :create, :create do
  metadata fn subject, result, ctx ->
    %{created_by: subject.id, timestamp: DateTime.utc_now()}
  end
end

# Custom procedure name
mutation :register, :register_with_password do
  metadata fn _subject, user, _ctx ->
    %{token: user.__metadata__.token}
  end
end
```

## Advanced Configuration

### Custom Transformers

Create custom input/output transformers:

```elixir
# lib/my_app/trpc_transformer.ex
defmodule MyApp.TrpcTransformer do
  @behaviour AshRpc.Output.Transformer

  @impl true
  def decode_input(input, _ctx) do
    # Transform input before processing
    input
    |> AshRpc.Output.Transformer.decode()
    |> transform_keys()
  end

  @impl true
  def encode_output(output, _ctx) do
    # Transform output before sending
    output
    |> transform_response()
    |> AshRpc.Output.Transformer.encode()
  end

  defp transform_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      {transform_key(k), transform_value(v)}
    end)
  end

  defp transform_key(key) when is_binary(key) do
    # Convert camelCase to snake_case
    key
    |> String.replace(~r/([A-Z])/, "_\\1")
    |> String.downcase()
  end

  defp transform_value(value) when is_map(value) do
    transform_keys(value)
  end

  defp transform_value(value), do: value

  defp transform_response(%{result: result} = response) do
    %{response | result: transform_keys(result)}
  end

  defp transform_response(response), do: response
end
```

## Multiple Routers

Create separate routers for different API versions or access levels:

```elixir
# Public API router
defmodule MyAppWeb.PublicTrpcRouter do
  use AshRpc.Router, domains: [MyApp.Public]
end

# Admin API router
defmodule MyAppWeb.AdminTrpcRouter do
  use AshRpc.Router, domains: [MyApp.Admin]
end

# Internal API router
defmodule MyAppWeb.InternalTrpcRouter do
  use AshRpc.Router,
    domains: [MyApp.Internal],
    # Different transformer for internal use
    transformer: MyApp.InternalTrpcTransformer
end
```

Configure them in your Phoenix router:

```elixir
scope "/trpc" do
  # Public endpoints
  scope "/public" do
    pipe_through :ash_rpc_public
    forward "/", MyAppWeb.PublicTrpcRouter
  end

  # Authenticated endpoints
  scope "/api" do
    pipe_through :ash_rpc
    forward "/", MyAppWeb.TrpcRouter
  end

  # Admin endpoints
  scope "/admin" do
    pipe_through [:trpc, :require_admin]
    forward "/", MyAppWeb.AdminTrpcRouter
  end

  # Internal endpoints (not exposed publicly)
  scope "/internal" do
    pipe_through [:trpc, :require_internal]
    forward "/", MyAppWeb.InternalTrpcRouter
  end
end
```
