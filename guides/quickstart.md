# Installation & Setup Guide

This guide provides detailed instructions for installing and configuring AshRpc in your Phoenix application.

> ⚠️ **EXPERIMENTAL WARNING**: AshRpc is still in early development and considered highly experimental. Breaking changes may occur frequently without notice. We strongly advise against using this package in production environments until it reaches a stable release (v1.0.0+).

## Prerequisites

Before installing AshRpc, ensure you have:

- **Elixir 1.15+**
- **Phoenix 1.7+**
- **Ash Framework 3.0+** (already configured in your application)
- **PostgreSQL** or another supported database

## Installation Options

### Option 1: Automated Installation (Recommended)

The easiest way to get started is using the automated installer:

```bash
# Add ash_rpc to your dependencies using Igniter (if installed)
mix igniter.install ash_rpc

# Or manually add to your mix.exs:
# {:ash_rpc, "~> 0.1"}

# Install dependencies
mix deps.get

# Run the installer
mix ash_rpc.install
```

The installer will:

- ✅ Generate `MyAppWeb.TrpcRouter` module
- ✅ Add tRPC pipeline to your Phoenix router
- ✅ Configure route forwarding to `/trpc`
- ✅ Format generated files

### Option 2: Manual Installation

For more control over the installation process:

#### Step 1: Add Dependencies

Add AshRpc to your `mix.exs`:

```elixir
defp deps do
  [
    ...,
    {:ash_rpc, "~> 0.1"},
  ]
end
```

#### Step 2: Install Dependencies

```bash
mix deps.get
```

#### Step 3: Create tRPC Router

Create a new file `lib/my_app_web/trpc_router.ex`:

```elixir
defmodule MyAppWeb.TrpcRouter do
  use AshRpc.Router,
    domains: [MyApp.Accounts, MyApp.Billing],
    # Optional: Custom transformer for input/output processing
    transformer: AshRpc.Output.Transformer.Identity,
    # Optional: Before hooks
    before: [],
    # Optional: After hooks
    after: [],
    # Optional: Context creation function
    create_context: &AshRpc.Web.Controller.default_context/1
end
```

#### Step 4: Configure Phoenix Router

Add the tRPC pipeline and routes to your `lib/my_app_web/router.ex`:

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  # ... existing pipelines

  # tRPC pipeline - JSON only
  pipeline :ash_rpc do
    plug :accepts, ["json"]
    # Add authentication plugs here if needed
    # plug :retrieve_from_bearer
    # plug :set_actor, :user
  end

  # ... existing routes

  # Mount tRPC under the :trpc pipeline
  scope "/trpc" do
    pipe_through :ash_rpc
    forward "/", MyAppWeb.TrpcRouter
  end
end
```

## Configuration Options

### Router Options

```elixir
defmodule MyAppWeb.TrpcRouter do
  use AshRpc.Router,
    # Required: Domains to expose
    domains: [MyApp.Accounts, MyApp.Billing, MyApp.Notifications],

    # Optional: Custom input/output transformer
    transformer: MyApp.TrpcTransformer,

    # Optional: Before request hooks
    before: [MyApp.TrpcHooks.Logging, MyApp.TrpcHooks.Metrics],

    # Optional: After request hooks
    after: [MyApp.TrpcHooks.Audit],

    # Optional: Custom context creation function
    create_context: &MyApp.TrpcContext.create/1,

    # Optional: Custom middlewares
    middlewares: [MyApp.TrpcMiddleware.Auth, MyApp.TrpcMiddleware.Cache]
end
```

### Custom Hooks

Create custom hooks for request processing:

```elixir
# lib/my_app/trpc_hooks/logging.ex
defmodule MyApp.TrpcHooks.Logging do
  @behaviour AshRpc.Execution.Middleware

  @impl true
  def before_request(ctx) do
    Logger.info("tRPC request: #{ctx.procedure}")
    ctx
  end

  @impl true
  def after_request(ctx, result) do
    Logger.info("tRPC response: #{ctx.procedure} - #{result.status}")
    result
  end
end
```

### Custom Context

Create custom context for requests:

```elixir
# lib/my_app/trpc_context.ex
defmodule MyApp.TrpcContext do
  def create(%Plug.Conn{} = conn) do
    %{
      actor: conn.assigns[:current_user],
      tenant: conn.assigns[:current_tenant],
      request_id: Logger.metadata()[:request_id],
      user_agent: get_user_agent(conn),
      ip_address: get_ip_address(conn)
    }
  end

  defp get_user_agent(conn) do
    conn
    |> Plug.Conn.get_req_header("user-agent")
    |> List.first()
  end

  defp get_ip_address(conn) do
    conn.remote_ip
    |> :inet.ntoa()
    |> to_string()
  end
end
```

## Resource Configuration

### Basic Resource Setup

Configure your Ash resources to expose actions via tRPC:

```elixir
defmodule MyApp.Accounts.User do
  use Ash.Resource,
    extensions: [AshRpc],
    domain: MyApp.Accounts

  # ... resource attributes, actions, etc.

  ash_rpc do
    # Optional: Expose actions (only needed if not using query/mutation entities below)
    # expose [:read, :create, :update, :destroy]

    # Configure specific procedures with advanced features
    query :read do
      filterable true
      sortable true
      selectable true
      paginatable true
    end

    mutation :create
    mutation :update
    mutation :destroy

    # Custom resource name (defaults to module name)
    resource_name "user"

    # Configure method overrides
    methods: [read: :query, create: :mutation]
  end
end
```

### Advanced Query Configuration

```elixir
ash_rpc do
  expose [:read, :create, :search]

  # Configure read queries
  query :read do
    filterable true      # Allow client-side filtering
    sortable true        # Allow client-side sorting
    selectable true      # Allow client-side field selection
    paginatable true     # Allow client-side pagination
    relationships [:posts, :comments, :profile]
  end

  # Custom query for specific use case
  query :search, :read do
    filterable true
    selectable false  # Disable field selection for search
    relationships []  # No relationships for search
  end

  # Configure mutations
  mutation :create, :create do
    metadata fn _subject, user, _ctx ->
      %{user_id: user.id, created_at: user.inserted_at}
    end
  end

  mutation :register, :register_with_password do
    metadata fn _subject, user, _ctx ->
      %{token: user.__metadata__.token, user_id: user.id}
    end
  end
end
```

## Testing the Installation

### 1. Verify Router Setup

Start your Phoenix server:

```bash
mix phx.server
```

### 2. Test Health Check

Make a simple HTTP request to verify the router is working:

```bash
curl -X POST http://localhost:4000/trpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"query","params":{}}'
```

You should receive a tRPC-compatible response.

### 3. Configure Resources

Add tRPC configuration to at least one resource:

```elixir
defmodule MyApp.Accounts.User do
  use Ash.Resource, extensions: [AshRpc]

  ash_rpc do
    expose [:read]
  end

  # ... rest of resource
end
```

### 4. Test Resource Endpoint

```bash
curl -X POST http://localhost:4000/trpc/accounts.user.read \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"query","params":{}}'
```

## Troubleshooting

### Common Issues

#### 1. Router Not Found Error

**Error**: `UndefinedFunctionError: function MyAppWeb.TrpcRouter.init/1 is undefined`

**Solution**: Ensure the router module is properly defined and compiled:

```bash
mix compile
mix phx.server
```

#### 2. Domain Not Found Error

**Error**: `Ash.Error.Invalid: Domain MyApp.Accounts not found`

**Solution**: Verify the domain is correctly configured in your router:

```elixir
# Check domain exists
MyApp.Accounts

# Verify router configuration
defmodule MyAppWeb.TrpcRouter do
  use AshRpc.Router, domains: [MyApp.Accounts]  # Correct module name
end
```

#### 3. Resource Not Exposed Error

**Error**: `AshRpc.Error: Resource MyApp.Accounts.User not exposed`

**Solution**: Add tRPC configuration to your resource:

```elixir
defmodule MyApp.Accounts.User do
  use Ash.Resource, extensions: [AshRpc]

  ash_rpc do
    expose [:read]  # Add this block
  end
end
```

#### 4. Authentication Issues

**Error**: `Ash.Error.Forbidden: Access denied`

**Solution**: Configure authentication in your router pipeline:

```elixir
pipeline :ash_rpc do
  plug :accepts, ["json"]
  plug :retrieve_from_bearer  # Add this
  plug :set_actor, :user      # Add this
end
```

### Debug Mode

Enable detailed logging for troubleshooting:

```elixir
# config/dev.exs
config :logger, level: :debug

config :ash_rpc, debug: true
```

## Next Steps

Once installation is complete:

1. **Generate TypeScript Types**:

   ```bash
   mix ash_rpc.codegen --output=./frontend/generated --zod
   ```

2. **Set Up Authentication** (see [Authentication Guide](authentication.md))

## Support

If you encounter issues during installation:

- Check the [troubleshooting section](#troubleshooting) above
- Open an issue on [GitHub](https://github.com/antdragon-os/ash_rpc/issues)
- Join the discussion on [GitHub Discussions](https://github.com/antdragon-os/ash_rpc/discussions)
