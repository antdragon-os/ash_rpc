# Migration & Troubleshooting Guide

This guide covers migrating from other API solutions to AshRpc, common troubleshooting scenarios, and performance optimization techniques.

> ⚠️ **EXPERIMENTAL WARNING**: AshRpc is still in early development and considered highly experimental. Breaking changes may occur frequently without notice. We strongly advise against using this package in production environments until it reaches a stable release (v1.0.0+).

## Migration Guides

### From Phoenix Context + JSON API

#### Step 1: Assess Current Implementation

```elixir
# Before: Phoenix Context + Controller
defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller

  def index(conn, params) do
    page = params["page"] || 1
    limit = params["limit"] || 20

    users = MyApp.Accounts.list_users(
      page: page,
      limit: limit,
      filters: params["filters"]
    )

    render(conn, "index.json", users: users)
  end

  def create(conn, %{"user" => user_params}) do
    case MyApp.Accounts.create_user(user_params) do
      {:ok, user} ->
        conn
        |> put_status(:created)
        |> render("show.json", user: user)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render("error.json", changeset: changeset)
    end
  end
end
```

#### Step 2: Convert to Ash Resources

```elixir
# After: Ash Resource with AshRpc
defmodule MyApp.Accounts.User do
  use Ash.Resource,
    extensions: [AshRpc],
    domain: MyApp.Accounts

  # ... attributes, relationships, actions

  ash_rpc do
    expose [:read, :create, :update, :destroy]

    query :read do
      filterable true
      sortable true
      selectable true
      paginatable true
    end
  end
end
```

#### Step 3: Update Frontend Calls

```typescript
// Before: REST API calls
const response = await fetch("/api/users", {
  method: "GET",
  headers: { "Content-Type": "application/json" },
});
const users = await response.json();

// After: tRPC calls
const { result: users } = await client.accounts.user.read.query({
  page: { limit: 20, offset: 0 },
});
```

### From GraphQL

#### Converting GraphQL Schemas to AshRpc

```graphql
# GraphQL Schema
type User {
  id: ID!
  email: String!
  name: String!
  posts: [Post!]!
}

type Query {
  users(limit: Int, offset: Int): [User!]!
  user(id: ID!): User
}

type Mutation {
  createUser(email: String!, name: String!): User!
  updateUser(id: ID!, email: String, name: String): User!
}
```

```elixir
# Equivalent AshRpc Resource
defmodule MyApp.Accounts.User do
  use Ash.Resource,
    extensions: [AshRpc],
    domain: MyApp.Accounts

  attributes do
    uuid_primary_key :id
    attribute :email, :string, allow_nil?: false
    attribute :name, :string, allow_nil?: false
  end

  relationships do
    has_many :posts, MyApp.Blog.Post
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    read :get do
      argument :id, :uuid, allow_nil?: false
      get? true
      filter expr(id == ^arg(:id))
    end
  end

  ash_rpc do
    expose [:read, :create, :update, :destroy]

    query :read do
      filterable true
      sortable true
      selectable true
      paginatable true
      relationships [:posts]
    end

    query :get, :get do
      filterable false
      selectable true
      relationships [:posts]
    end
  end
end
```

#### Handling GraphQL-specific Patterns

```elixir
# GraphQL nested queries -> AshRpc relationships
query :user_with_posts, :read do
  argument :id, :uuid, allow_nil?: false
  filter expr(id == ^arg(:id))

  # Pre-load relationships
  relationships [:posts]
end

# Frontend usage
const user = await client.accounts.user.user_with_posts.query({
  id: "user-id",
  select: ["id", "name", "email", { posts: ["title", "content"] }]
});
```

### From REST API Libraries

#### Converting from Tesla/HTTPoison

```elixir
# Before: Custom HTTP client
defmodule MyApp.ApiClient do
  use Tesla

  def list_users(params) do
    get("/users", query: params)
  end

  def create_user(user_data) do
    post("/users", user_data)
  end
end

# After: AshRpc (no custom client needed)
defmodule MyAppWeb.TrpcRouter do
  use AshRpc.Router, domains: [MyApp.Accounts]
end
```

## Troubleshooting

### Common Issues

#### 1. Router Not Found

**Error**: `UndefinedFunctionError: function MyAppWeb.TrpcRouter.init/1 is undefined`

**Solution**:

```bash
# Ensure router is compiled
mix compile

# Check for syntax errors
mix compile --warnings-as-errors

# Verify router file exists
ls lib/my_app_web/trpc_router.ex
```

#### 2. Resource Not Exposed

**Error**: `AshRpc.Error: Resource MyApp.Accounts.User not exposed`

**Cause**: Missing `ash_rpc do` block or incorrect module path.

**Solution**:

```elixir
defmodule MyApp.Accounts.User do
  use Ash.Resource, extensions: [AshRpc]

  ash_rpc do
    expose [:read]
  end
end
```

#### 3. Domain Not Found

**Error**: `Ash.Error.Invalid: Domain MyApp.Accounts not found`

**Solutions**:

```elixir
# 1. Check domain exists and is properly defined
defmodule MyApp.Accounts do
  use Ash.Domain, resources: [MyApp.Accounts.User]
end

# 2. Verify router configuration
defmodule MyAppWeb.TrpcRouter do
  use AshRpc.Router, domains: [MyApp.Accounts]  # Correct module name
end

# 3. Check for typos in domain name
```

#### 4. Authentication Errors

**Error**: `Ash.Error.Forbidden: Access denied`

**Debug Steps**:

```elixir
# 1. Check if user is authenticated
IO.inspect(conn.assigns[:current_user], label: "Current User")

# 2. Verify token extraction
IO.inspect(Plug.Conn.get_req_header(conn, "authorization"), label: "Auth Header")

# 3. Check policy configuration
defmodule MyApp.Accounts.User do
  policies do
    policy action_type(:read) do
      authorize_if actor_present()  # Ensure user is authenticated
    end
  end
end
```

#### 5. TypeScript Generation Issues

**Error**: `mix ash_rpc.codegen` fails with module not found

**Solutions**:

```bash
# 1. Ensure all modules are compiled
mix compile

# 2. Check for syntax errors
mix compile 2>&1 | grep error

# 3. Verify domain modules exist
mix run -e "MyApp.Accounts"

# 4. Check output directory permissions
mkdir -p frontend/generated
```

### Performance Issues

#### Slow Query Performance

**Symptoms**: API responses are slow, especially with large datasets.

**Solutions**:

1. **Add Database Indexes**:

```elixir
# migration
def change do
  create index(:users, [:email])
  create index(:posts, [:published_at])
  create index(:users, [:inserted_at])
end
```

2. **Optimize Ash Queries**:

```elixir
# Resource optimization
actions do
  read :list do
    prepare build(limit: 50)  # Default limit
    prepare filter(expr(active == true))  # Pre-filter
  end
end
```

3. **Use Pagination**:

```typescript
// Always use pagination for large datasets
const users = await client.accounts.user.read.query({
  page: { limit: 20, offset: 0 },
  sort: { insertedAt: "desc" },
});
```

#### Memory Issues

**Symptoms**: Application runs out of memory with large result sets.

**Solutions**:

1. **Stream Large Results**:

```elixir
actions do
  read :export do
    run fn _input, _ctx ->
      # Use streams for large exports
      MyApp.Repo.transaction(fn ->
        MyApp.Accounts.User
        |> Ash.Query.stream()
        |> Stream.map(&process_user/1)
        |> Enum.to_list()
      end)
    end
  end
end
```

2. **Limit Field Selection**:

```typescript
// Only select needed fields
const users = await client.accounts.user.read.query({
  select: ["id", "email", "name"], // Not all fields
  page: { limit: 100 },
});
```

3. **Use Keyset Pagination**:

```typescript
// More memory efficient than offset
const users = await client.accounts.user.read.query({
  page: {
    type: "keyset",
    limit: 100,
    after: lastCursor,
  },
});
```

### Network Issues

#### Connection Timeouts

**Symptoms**: Requests timeout, especially on slow connections.

**Solutions**:

1. **Configure Timeouts**:

```typescript
const client = createTRPCClient({
  links: [
    httpBatchLink({
      url: "/trpc",
      fetch: (url, options) =>
        fetch(url, {
          ...options,
          signal: AbortSignal.timeout(30000), // 30 second timeout
        }),
    }),
  ],
});
```

2. **Implement Retry Logic**:

```typescript
const client = createTRPCClient({
  links: [
    retryLink({
      attempts: 3,
      delay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 30000),
    }),
    httpBatchLink({ url: "/trpc" }),
  ],
});
```

#### CORS Issues

**Symptoms**: Browser blocks requests due to CORS policy.

**Solution**:

```elixir
# router.ex
pipeline :ash_rpc do
  plug :accepts, ["json"]
  plug CORSPlug,
    origin: ["https://myapp.com", "https://app.myapp.com"],
    methods: ["GET", "POST"],
    headers: ["authorization", "content-type"],
    credentials: true
end
```

### Type Safety Issues

#### TypeScript Compilation Errors

**Symptoms**: TypeScript complains about type mismatches.

**Solutions**:

1. **Regenerate Types**:

```bash
mix ash_rpc.codegen --output=./frontend/generated --zod
```

2. **Check for API Changes**:

```typescript
// Ensure frontend types match backend
const user = await client.accounts.user.read.query();
// TypeScript will catch type mismatches here
```

3. **Handle Optional Fields**:

```typescript
// Backend: field might be nil
attribute :description, :string

// Frontend: handle optional fields
const users = await client.accounts.user.read.query({
  select: ["id", "name", "description"]
});

users.result.forEach(user => {
  // description might be null
  console.log(user.description?.toUpperCase());
});
```

## Debugging Techniques

### Enable Debug Logging

```elixir
# config/dev.exs
config :logger, level: :debug

config :ash_rpc, debug: true

# Phoenix debug logging
config :phoenix, :debug_errors, true
```

### Inspect Request Flow

```elixir
# Add logging middleware
defmodule MyApp.TrpcDebugMiddleware do
  @behaviour AshRpc.Execution.Middleware

  @impl true
  def before_request(ctx) do
    Logger.debug("tRPC Request",
      procedure: ctx.procedure,
      actor: ctx.actor && ctx.actor.id,
      input: inspect(ctx.input)
    )
    ctx
  end

  @impl true
  def after_request(ctx, result) do
    Logger.debug("tRPC Response",
      procedure: ctx.procedure,
      status: result.status,
      result_size: result |> inspect() |> byte_size()
    )
    result
  end
end

# Add to router
use AshRpc.Router,
  domains: [MyApp.Accounts],
  middlewares: [MyApp.TrpcDebugMiddleware]
```

### Frontend Debugging

```typescript
// Enable tRPC devtools
import { createTRPCClient } from "@trpc/client";

const client = createTRPCClient({
  links: [
    // Add logger link for development
    loggerLink({
      enabled: (opts) => process.env.NODE_ENV === "development",
    }),
    httpBatchLink({ url: "/trpc" }),
  ],
});

// Debug specific requests
const users = await client.accounts.user.read.query();
console.log("Users response:", users);

// Handle errors with detailed logging
try {
  await client.accounts.user.create.mutate(userData);
} catch (error: any) {
  console.error("Detailed error:", {
    message: error.shape?.message,
    code: error.shape?.data?.code,
    details: error.shape?.data?.details,
  });
}
```

## Performance Optimization

### Database Optimization

1. **Add Proper Indexes**:

```elixir
# migration
def change do
  # Single column indexes
  create index(:users, [:email])
  create index(:posts, [:published_at])

  # Composite indexes
  create index(:users, [:tenant_id, :email])
  create index(:posts, [:author_id, :published_at])

  # Partial indexes
  create index(:posts, [:published_at], where: "published = true")
end
```

2. **Optimize Queries**:

```elixir
# Resource with optimized actions
actions do
  read :list do
    # Pre-load commonly accessed relationships
    prepare build(load: [:author, :tags])

    # Add database-specific optimizations
    prepare build(distinct: true)
  end
end
```

### Caching Strategies

1. **Browser Caching**:

```typescript
const client = createTRPCClient({
  links: [
    httpBatchLink({
      url: "/trpc",
      headers: {
        "Cache-Control": "max-age=300", // 5 minute browser cache
      },
    }),
  ],
});
```

2. **React Query Caching**:

```typescript
// Configure query client
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 5 * 60 * 1000, // 5 minutes
      cacheTime: 10 * 60 * 1000, // 10 minutes
    },
  },
});
```

3. **Server-side Caching**:

```elixir
# Add caching middleware
defmodule MyApp.CacheMiddleware do
  @behaviour AshRpc.Execution.Middleware

  @impl true
  def before_request(ctx) do
    # Check cache for read queries
    if cacheable?(ctx) do
      case get_cache(cache_key(ctx)) do
        nil -> ctx
        cached -> throw({:cached_response, cached})
      end
    else
      ctx
    end
  end

  @impl true
  def after_request(ctx, result) do
    # Cache successful responses
    if cacheable?(ctx) && success?(result) do
      put_cache(cache_key(ctx), result, ttl: 300)
    end
    result
  end

  defp cacheable?(ctx), do: ctx.method == :query
  defp cache_key(ctx), do: "#{ctx.procedure}:#{inspect(ctx.input)}"
end
```

### Connection Optimization

1. **HTTP/2 Support**:

```elixir
# config/prod.exs
config :my_app, MyAppWeb.Endpoint,
  http: [port: 4000],
  https: [
    port: 443,
    cipher_suite: :strong,
    keyfile: "/path/to/key.pem",
    certfile: "/path/to/cert.pem"
  ],
  force_ssl: [rewrite_on: [:x_forwarded_proto]]
```

2. **Connection Pooling**:

```elixir
# config/prod.exs
config :my_app, MyApp.Repo,
  pool_size: 20,
  queue_target: 500,
  queue_interval: 1000
```

### Monitoring and Metrics

```elixir
# Add telemetry
:telemetry.attach(
  "ash-rpc-metrics",
  [:ash_rpc, :request, :start],
  &MyApp.Metrics.handle_request_start/4,
  nil
)

:telemetry.attach(
  "ash-rpc-metrics-stop",
  [:ash_rpc, :request, :stop],
  &MyApp.Metrics.handle_request_stop/4,
  nil
)

# Metrics handler
defmodule MyApp.Metrics do
  def handle_request_start(_event, measurements, metadata, _config) do
    # Record request start
    :prometheus_histogram.observe(:trpc_request_duration, [:start], measurements.value)
  end

  def handle_request_stop(_event, measurements, metadata, _config) do
    duration = measurements.value
    procedure = metadata.procedure

    # Record metrics
    :prometheus_histogram.observe(:trpc_request_duration, [procedure], duration)
    :prometheus_counter.inc(:trpc_requests_total, [procedure])
  end
end
```

## Migration Checklist

### Pre-Migration

- [ ] Backup existing database
- [ ] Document current API endpoints
- [ ] Identify client applications that need updates
- [ ] Plan rollback strategy
- [ ] Set up monitoring for new endpoints

### During Migration

- [ ] Deploy AshRpc alongside existing API
- [ ] Update client applications gradually
- [ ] Monitor performance and error rates
- [ ] Test authentication and authorization
- [ ] Validate data consistency

### Post-Migration

- [ ] Remove old API endpoints
- [ ] Update documentation
- [ ] Train team on new patterns
- [ ] Monitor for any remaining issues

### Rollback Plan

```elixir
# Keep old API endpoints during migration
scope "/api/v1" do
  pipe_through :api
  resources "/users", MyAppWeb.UserController
end

# New tRPC endpoints
scope "/trpc" do
  pipe_through :ash_rpc
  forward "/", MyAppWeb.TrpcRouter
end

# Gradual migration
# 1. Deploy both APIs
# 2. Update clients to use tRPC
# 3. Monitor for issues
# 4. Remove old API when confident
```

This comprehensive migration and troubleshooting guide provides everything needed to successfully migrate to AshRpc and handle any issues that may arise during development and production use.
