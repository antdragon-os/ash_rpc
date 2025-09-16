# AshRpc

**Expose Ash Resource actions over tRPC with a Plug-compatible router/controller, robust error handling, subscriptions, and schema tooling.**

AshRpc is a comprehensive bridge between [Ash Framework](https://ash-hq.org) and [tRPC](https://trpc.io), enabling you to expose your Ash resources as type-safe, performant tRPC endpoints. It provides seamless integration with Phoenix applications, automatic TypeScript generation, and advanced features like real-time subscriptions, field selection, and batching.

> ⚠️ **EXPERIMENTAL WARNING**: This package is still in early development and considered highly experimental. Breaking changes may occur frequently without notice. We strongly advise against using this package in production environments until it reaches a stable release (v1.0.0+). Use at your own risk for development and testing purposes only.

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Backend Setup](#backend-setup)
- [Frontend Integration](#frontend-integration)
- [Authentication](#authentication)
- [Advanced Features](#advanced-features)
- [API Reference](#api-reference)
- [Examples](#examples)
- [Contributing](#contributing)

## Features

### 🚀 **Core Features**

- **Simple Setup**: One-line router configuration with `use AshRpc.Router`
- **Spark DSL**: Declarative exposure of Ash resource actions
- **tRPC Compliance**: Full tRPC specification support with proper envelopes
- **Error Handling**: Robust, structured error responses with detailed validation messages
- **Type Safety**: Automatic TypeScript generation for end-to-end type safety

### 🔧 **Advanced Capabilities**

- **Batching**: Efficient request batching with `?batch=1` support
- **Subscriptions**: Real-time broadcasting via Phoenix.PubSub
- **Field Selection**: Dynamic field selection with include/exclude semantics
- **Filtering & Sorting**: Rich query capabilities with complex filter expressions
- **Pagination**: Offset and keyset pagination with automatic detection
- **Relationships**: Nested relationship loading with query options

### 🛠 **Developer Experience**

- **Auto-Generation**: TypeScript types and Zod schemas from your Ash resources
- **IntelliSense**: Full IDE support with generated type definitions

## Quick Start

### 1. Install AshRpc

```bash
# If you have Igniter installed (recommended)
mix igniter.install ash_rpc

# Or manually install
mix deps.get
mix ash_rpc.install
```

This creates your tRPC router and configures your Phoenix router.

### 2. Configure Your Resources

```elixir
defmodule MyApp.Accounts.User do
  use Ash.Resource, extensions: [AshRpc]

  ash_rpc do
    expose [:read, :create, :update]

    query :read do
      filterable true
      sortable true
      selectable true
      paginatable true
    end

    mutation :create, :create do
      metadata fn _subject, user, _ctx ->
        %{user_id: user.id}
      end
    end
  end

  # ... rest of your resource
end
```

### 3. Update Your Router

```elixir
defmodule MyAppWeb.TrpcRouter do
  use AshRpc.Router, domains: [MyApp.Accounts, MyApp.Billing]
end
```

### 4. Generate Types

```bash
mix ash_rpc.gen --output=./frontend/generated --zod
```

### 5. Use in Frontend

```typescript
import { createTRPCClient, httpBatchLink } from "@trpc/client";
import type { AppRouter } from "./generated/trpc";

const client = createTRPCClient<AppRouter>({
  links: [httpBatchLink({ url: "/trpc" })],
});

// Type-safe API calls
const users = await client.accounts.user.read.query({
  filter: { email: { eq: "user@example.com" } },
  select: ["id", "email", "name"],
  page: { limit: 10, offset: 0 },
});
```

## Installation

### Add Dependencies

Add `ash_rpc` to your `mix.exs`:

```elixir
defp deps do
  [
    {:ash_rpc, "~> 0.1"},
    # Recommended for type generation
    # For authentication (optional)
    {:ash_authentication, "~> 3.0"},
  ]
end
```

### Install AshRpc

Run the installer to set up your Phoenix application:

```bash
mix deps.get
mix ash_rpc.install
```

This will:

- Generate `MyAppWeb.TrpcRouter` module
- Add tRPC pipeline to your Phoenix router
- Configure route forwarding to `/trpc`

### Manual Setup (Alternative)

If you prefer manual setup, create the router manually:

```elixir
# lib/my_app_web/trpc_router.ex
defmodule MyAppWeb.TrpcRouter do
  use AshRpc.Router, domains: [MyApp.Accounts]
end

# router.ex
scope "/trpc" do
  pipe_through :ash_rpc
  forward "/", MyAppWeb.TrpcRouter
end
```

## Backend Setup

### Router Configuration

```elixir
defmodule MyAppWeb.TrpcRouter do
  use AshRpc.Router,
    domains: [MyApp.Accounts, MyApp.Billing, MyApp.Notifications],
    # Optional: Custom transformer for input/output processing
    transformer: MyApp.TrpcTransformer,
    # Optional: Before hooks
    before: [MyApp.TrpcHooks.Logging],
    # Optional: After hooks
    after: [MyApp.TrpcHooks.Metrics],
    # Optional: Context creation function
    create_context: &MyApp.TrpcContext.create/1
end
```

### Resource Configuration

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

    # Configure query procedures
    query :read do
      filterable true      # Allow client-side filtering
      sortable true        # Allow client-side sorting
      selectable true      # Allow client-side field selection
      paginatable true     # Allow client-side pagination

      # Custom relationship loading
      relationships [:posts, :comments]
    end

    query :by_email, :read do
      # Custom procedure name for specific action
      filterable false
      selectable true
    end

    # Configure mutation procedures
    mutation :create, :create do
      metadata fn _subject, user, _ctx ->
        %{user_id: user.id, created_at: user.inserted_at}
      end
    end

    mutation :register, :register_with_password do
      metadata fn _subject, user, _ctx ->
        %{token: user.__metadata__.token}
      end
    end
  end

  # ... resource definition
end
```

### DSL Reference

#### `ash_rpc` Block Options

- `expose`: List of actions to expose (`:all` or specific action names)
- `resource_name`: Override the default resource segment name
- `methods`: Override default method mappings (`[read: :query, create: :mutation]`)

#### Query Configuration

```elixir
query :read do
  filterable true        # Enable filtering (default: true)
  sortable true         # Enable sorting (default: true)
  selectable true       # Enable field selection (default: true)
  paginatable true      # Enable pagination (default: true)
  relationships [:posts] # Allow loading specific relationships
end
```

#### Mutation Configuration

```elixir
mutation :create, :create do
  metadata fn subject, result, ctx ->
    # Return custom metadata in response
    %{created_by: subject.id, timestamp: DateTime.utc_now()}
  end
end
```

## Authentication

AshRpc integrates seamlessly with AshAuthentication for secure API access.

### Setup Authentication

```elixir
# In your Phoenix router
pipeline :ash_rpc do
  plug :accepts, ["json"]
  plug :retrieve_from_bearer  # Extract token from Authorization header
  plug :set_actor, :user      # Set current user as actor
end

scope "/trpc" do
  pipe_through :ash_rpc
  forward "/", MyAppWeb.TrpcRouter
end
```

### Client Authentication

```typescript
// Include token in requests
const client = createTRPCClient<AppRouter>({
  links: [
    httpBatchLink({
      url: "/trpc",
      headers() {
        const token = getAuthToken();
        return token ? { Authorization: `Bearer ${token}` } : {};
      },
    }),
  ],
});
```

### Authorization

AshRpc respects Ash's authorization rules. Configure policies on your resources:

```elixir
defmodule MyApp.Accounts.User do
  # ... resource setup

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if relates_to_actor_via(:self)
    end
  end
end
```

## Frontend Integration

### tRPC Client Setup

```typescript
// client.ts
import { createTRPCClient, httpBatchLink } from "@trpc/client";
import type { AppRouter } from "./generated/trpc";

export function createClient(token?: string) {
  return createTRPCClient<AppRouter>({
    links: [
      httpBatchLink({
        url: "/trpc",
        headers: token ? { Authorization: `Bearer ${token}` } : {},
      }),
    ],
  });
}
```

### React Integration

```tsx
// App.tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { createTRPCReact } from "@trpc/react-query";
import type { AppRouter } from "./generated/trpc";

export const trpc = createTRPCReact<AppRouter>();
const queryClient = new QueryClient();

function App() {
  return (
    <trpc.Provider client={createClient()} queryClient={queryClient}>
      <QueryClientProvider client={queryClient}>
        <MyComponent />
      </QueryClientProvider>
    </trpc.Provider>
  );
}
```

### Usage Examples

```tsx
// UserList.tsx
import { trpc } from "./trpc";

function UserList() {
  const { data: users, isLoading } = trpc.accounts.user.read.useQuery({
    filter: { role: { eq: "admin" } },
    select: ["id", "email", "name"],
    sort: { insertedAt: "desc" },
    page: { limit: 20, offset: 0 },
  });

  if (isLoading) return <div>Loading...</div>;

  return (
    <div>
      {users?.result.map((user) => (
        <div key={user.id}>{user.name}</div>
      ))}
    </div>
  );
}
```

### Mutation Examples

```tsx
// CreateUser.tsx
import { trpc } from "./trpc";

function CreateUser() {
  const createUser = trpc.accounts.user.create.useMutation();

  const handleSubmit = async (data: FormData) => {
    try {
      const result = await createUser.mutateAsync({
        email: data.email,
        password: data.password,
        name: data.name,
      });

      console.log("Created user:", result.result);
      console.log("Metadata:", result.meta);
    } catch (error) {
      console.error("Failed to create user:", error);
    }
  };

  return <form onSubmit={handleSubmit}>{/* form fields */}</form>;
}
```

## Advanced Features

### Batching

AshRpc supports request batching for improved performance:

```typescript
// Automatic batching with httpBatchLink
const client = createTRPCClient<AppRouter>({
  links: [httpBatchLink({ url: "/trpc" })],
});

// Multiple queries batched automatically
const [users, posts] = await Promise.all([
  client.accounts.user.read.query({ limit: 10 }),
  client.blog.post.read.query({ limit: 10 }),
]);
```

### Field Selection

Dynamically select which fields to return:

```typescript
// Include specific fields
const users = await client.accounts.user.read.query({
  select: ["id", "email", "name"],
});

// Exclude fields with "-"
const users = await client.accounts.user.read.query({
  select: ["-password", "-insertedAt"],
});

// Nested field selection
const posts = await client.blog.post.read.query({
  select: [
    "id",
    "title",
    { author: ["name", "email"] },
    { comments: ["content", "-insertedAt"] },
  ],
});
```

### Filtering & Sorting

Rich query capabilities:

```typescript
// Complex filtering
const users = await client.accounts.user.read.query({
  filter: {
    and: [
      { email: { like: "%@company.com" } },
      { or: [{ role: { eq: "admin" } }, { role: { eq: "manager" } }] },
    ],
  },
  sort: { insertedAt: "desc" },
});
```

### Pagination

Support for both offset and keyset pagination:

```typescript
// Offset pagination
const users = await client.accounts.user.read.query({
  page: {
    type: "offset",
    limit: 20,
    offset: 40,
    count: true, // Include total count
  },
});

// Keyset pagination (recommended for large datasets)
const users = await client.accounts.user.read.query({
  page: {
    type: "keyset",
    limit: 20,
    after: "cursor_value",
    before: "cursor_value",
  },
});
```

### Subscriptions

Real-time updates via Phoenix channels:

```typescript
// Backend: Enable subscriptions on resource
trpc do
  expose [:read, :create]
  subscribe [:create]  # Broadcast on create actions
end

// Frontend: Subscribe to changes
const subscription = trpc.accounts.user.onCreate.subscribe(undefined, {
  onData: (data) => {
    console.log("New user created:", data);
  },
});
```

## TypeScript Generation

### Generate Types

```bash
# Generate TypeScript types
mix ash_rpc.gen --output=./frontend/generated

# Generate with Zod schemas
mix ash_rpc.gen --output=./frontend/generated --zod
```

### Generated Files

- `trpc.d.ts`: TypeScript types for your tRPC router
- `trpc.zod.ts`: Zod schemas for client-side validation (optional)

### Usage

```typescript
import type { AppRouter } from "./generated/trpc";
import * as schemas from "./generated/trpc.zod";

// Full type safety
const client = createTRPCClient<AppRouter>();

// Client-side validation
const userSchema = schemas.AccountsUserCreateSchema;
const validated = userSchema.parse(formData);
```

## Error Handling

AshRpc provides comprehensive error handling with detailed messages:

```typescript
try {
  await client.accounts.user.create.mutate({
    email: "invalid-email", // Missing password
  });
} catch (error: any) {
  // error.shape?.message - High-level message
  // error.data?.details - Array of detailed error objects
  console.log(error.shape?.message); // "Validation failed"

  error.data?.details.forEach((detail) => {
    console.log(detail.message); // "password is required"
    console.log(detail.code); // "field_validation_error"
    console.log(detail.pointer); // "password"
  });
}
```

## API Reference

### Router Module

```elixir
defmodule AshRpc.Router do
  @moduledoc """
  Main router module for exposing Ash resources via tRPC.

  ## Options
  - `domains`: List of Ash domain modules to expose
  - `transformer`: Custom input/output transformer module
  - `before`: List of modules to run before request processing
  - `after`: List of modules to run after request processing
  - `create_context`: Function to create request context
  """
end
```

### DSL Module

```elixir
defmodule AshRpc do
  @moduledoc """
  Spark DSL extension for configuring tRPC exposure on Ash resources.

  ## DSL Structure
  ash_rpc do
    expose [:action1, :action2]
    resource_name "custom_name"

    query :action do
      filterable true
      sortable true
      selectable true
      paginatable true
      relationships [:rel1, :rel2]
    end

    mutation :action do
      metadata fn subject, result, ctx -> %{key: value} end
    end
  end
  """
end
```

## Examples

### Complete User Management System

See the `examples/` directory for complete implementations including:

- User registration and authentication
- Role-based access control
- File uploads with progress tracking
- Real-time notifications
- Advanced querying with relationships

### Quick Examples

#### Basic CRUD Operations

```elixir
# Resource
defmodule MyApp.Blog.Post do
  use Ash.Resource, extensions: [AshRpc]

  ash_rpc do
    expose [:read, :create, :update, :destroy]

    query :read do
      filterable true
      sortable true
      selectable true
      paginatable true
      relationships [:author, :comments]
    end
  end
end

# Frontend usage
const posts = await client.blog.post.read.query({
  filter: { published: { eq: true } },
  sort: { publishedAt: "desc" },
  select: ["id", "title", "content", { author: ["name"] }],
  page: { limit: 10 }
});
```

#### Advanced Filtering

```typescript
// Complex queries with relationships
const posts = await client.blog.post.read.query({
  filter: {
    and: [
      { published: { eq: true } },
      { author: { name: { like: "John%" } } },
      {
        or: [
          { tags: { contains: "elixir" } },
          { tags: { contains: "phoenix" } },
        ],
      },
    ],
  },
  load: [
    { author: { filter: { active: { eq: true } } } },
    { comments: { sort: { insertedAt: "desc" }, limit: 5 } },
  ],
});
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Run the test suite: `mix test`
6. Submit a pull request

### Development Setup

```bash
git clone https://github.com/ash-project/ash_rpc.git
cd ash_rpc
mix deps.get
mix test
```

### Documentation

Documentation is generated with ExDoc. To build locally:

```bash
mix docs
open doc/index.html
```

## License

Apache 2.0 - see `LICENSE`.

## Support

- **Issues**: [GitHub Issues](https://github.com/antdragon-os/ash_rpc/issues)
- **Discussions**: [GitHub Discussions](https://github.com/antdragon-os/ash_rpc/discussions)
- **Documentation**: [HexDocs](https://hexdocs.pm/ash_rpc)

---

Built with ❤️ using [Ash Framework](https://ash-hq.org) and [tRPC](https://trpc.io)
