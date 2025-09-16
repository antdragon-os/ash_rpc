# API Reference

This comprehensive API reference covers all modules, functions, and configuration options available in AshRpc.

> ⚠️ **EXPERIMENTAL WARNING**: AshRpc is still in early development and considered highly experimental. Breaking changes may occur frequently without notice. We strongly advise against using this package in production environments until it reaches a stable release (v1.0.0+).

## Core Modules

## AshRpc.Router

Main router module for exposing Ash resources via tRPC.

```elixir
defmodule AshRpc.Router do
  @moduledoc """
  Plug-compatible router for tRPC endpoints.

  ## Usage

      defmodule MyAppWeb.TrpcRouter do
        use AshRpc.Router, domains: [MyApp.Accounts, MyApp.Billing]
      end
  """

  defmacro __using__(opts) do
    # Implementation details...
  end
end
```

### Options

- `domains` (required): List of Ash domain modules to expose
- `transformer`: Custom input/output transformer module
- `before`: List of middleware modules to run before request processing
- `after`: List of middleware modules to run after request processing
- `create_context`: Function to create custom request context
- `middlewares`: List of middleware modules for request processing
- `batch_max_size`: Maximum requests per batch (default: 50)
- `batch_timeout`: Batch timeout in milliseconds (default: 100)
- `debug`: Enable debug mode with detailed error information

### Example

```elixir
defmodule MyAppWeb.TrpcRouter do
  use AshRpc.Router,
    domains: [MyApp.Accounts, MyApp.Billing],
    transformer: MyApp.TrpcTransformer,
    before: [MyApp.TrpcHooks.Logging],
    after: [MyApp.TrpcHooks.Metrics],
    create_context: &MyApp.TrpcContext.create/1,
    middlewares: [MyApp.TrpcMiddleware.Auth],
    batch_max_size: 100,
    debug: Mix.env() == :dev
end
```

## AshRpc

Spark DSL extension for configuring tRPC exposure on Ash resources.

```elixir
defmodule AshRpc do
  @moduledoc """
  DSL extension for Ash resources to expose actions via tRPC.

  ## Usage

      defmodule MyApp.Accounts.User do
        use Ash.Resource, extensions: [AshRpc]

        ash_rpc do
          expose [:read, :create, :update, :destroy]
        end
      end
  """
end
```

### DSL Functions

#### `expose/1`

Specify which actions to expose via tRPC. **Optional** when using `query` or `mutation` entities.

When you define `query` or `mutation` entities in the `trpc` block, those actions are automatically exposed. Use `expose` only when you want to expose actions without defining specific procedure configurations, or to expose additional actions.

```elixir
# Expose specific actions (without procedure configuration)
expose [:read, :create, :update]

# Expose all actions
expose :all

# Exclude specific actions
expose [:all, except: [:destroy]]

# When using query/mutation entities, expose is optional:
ash_rpc do
  query :read do
    filterable true
  end
  mutation :create
  # These are automatically exposed, no need for expose: [:read, :create]
end
```

#### `resource_name/1`

Override the default resource segment name.

```elixir
# Default: "user" (based on module name)
# Override:
resource_name "account"
```

#### `methods/1`

Override default method mappings.

```elixir
methods [
  read: :query,        # Default
  create: :mutation,   # Default
  custom_action: :query
]
```

#### `query/2`

Configure a query procedure.

```elixir
query :read do
  filterable true      # Enable filtering (default: true)
  sortable true        # Enable sorting (default: true)
  selectable true      # Enable field selection (default: true)
  paginatable true     # Enable pagination (default: true)
  relationships [:posts, :comments]  # Loadable relationships
end

query :search, :read do
  filterable true
  selectable false
  relationships []
end
```

#### `mutation/2`

Configure a mutation procedure.

```elixir
mutation :create, :create do
  metadata fn subject, result, ctx ->
    %{user_id: result.id, created_at: result.inserted_at}
  end
end

mutation :register, :register_with_password do
  metadata fn _subject, user, _ctx ->
    %{token: user.__metadata__.token}
  end
end
```

## AshRpc.Web.Controller

Handles HTTP requests and converts them to tRPC format.

```elixir
defmodule AshRpc.Web.Controller do
  @moduledoc """
  Main controller for processing tRPC requests.

  This module handles:
  - Request parsing and validation
  - Batch request processing
  - Error handling and formatting
  - Response serialization
  """
end
```

### Functions

#### `call/2`

Main entry point for request processing.

```elixir
def call(%Plug.Conn{} = conn, opts) do
  # Process tRPC request
  # Returns {:ok, result} or {:error, error}
end
```

#### `init/1`

Initialize controller with options.

```elixir
def init(opts) do
  # Validate and normalize options
  opts
end
```

## AshRpc.Execution

Handles the execution of tRPC procedures.

### AshRpc.Execution.Executor

Executes Ash actions based on tRPC requests.

```elixir
defmodule AshRpc.Execution.Executor do
  @moduledoc """
  Executes Ash actions based on parsed tRPC requests.
  """

  @spec run(map()) :: {:ok, result} | {:error, error}
  def run(ctx) do
    # Execute the Ash action
    # Handle authorization
    # Apply transformations
  end

  @spec build_ctx(map(), [module()], String.t(), String.t() | nil, map(), Plug.Conn.t()) :: map()
  def build_ctx(base_ctx, resources, domains, procedure, method, input, conn) do
    # Build execution context
    # Extract parameters
    # Set up authorization
  end
end
```

### AshRpc.Execution.Server

Manages the execution lifecycle and middleware.

```elixir
defmodule AshRpc.Execution.Server do
  @moduledoc """
  Manages request execution with middleware support.
  """

  @spec handle_single(map(), function()) :: {:ok, response} | {:error, error}
  def handle_single(server, ctx, executor_fn) do
    # Execute single request with middleware
  end

  @spec handle_batch(map(), [map()], function()) :: {:ok, [response]} | {:error, error}
  def handle_batch(server, ctxs, executor_fn) do
    # Execute batch requests with middleware
  end
end
```

### AshRpc.Execution.Middleware

Behaviour for request processing middleware.

```elixir
defmodule AshRpc.Execution.Middleware do
  @moduledoc """
  Behaviour for request processing middleware.

  Middleware can intercept requests at different stages:
  - Before request processing
  - After request processing
  - On error
  """

  @callback before_request(map()) :: map()
  @callback after_request(map(), term()) :: term()
end
```

## AshRpc.Error

Error handling and formatting.

### AshRpc.Error.Error

Main error handling module.

```elixir
defmodule AshRpc.Error.Error do
  @moduledoc """
  Converts various error types into tRPC-compatible error responses.
  """

  @type trpc_error :: %{
    code: integer(),
    message: String.t(),
    data: %{
      code: String.t(),
      httpStatus: pos_integer(),
      details: [map()]
    }
  }

  @spec to_trpc_error(term(), map()) :: trpc_error()
  def to_trpc_error(error, ctx \\ %{}) do
    # Convert error to tRPC format
    # Add context information
    # Format error details
  end
end
```

### AshRpc.Error.ErrorBuilder

Builds detailed error responses.

```elixir
defmodule AshRpc.Error.ErrorBuilder do
  @moduledoc """
  Builds structured error responses from various error types.
  """

  @spec build_error_response(term()) :: map()
  def build_error_response(error) do
    # Analyze error type
    # Extract relevant information
    # Build structured response
  end
end
```

### AshRpc.Error.Codes

tRPC error code mappings.

```elixir
defmodule AshRpc.Error.Codes do
  @moduledoc """
  Provides mappings between error types and tRPC error codes.
  """

  @spec to_jsonrpc(atom()) :: integer()
  def to_jsonrpc(:bad_request), do: -32600
  def to_jsonrpc(:unauthorized), do: -32001
  def to_jsonrpc(:forbidden), do: -32003
  def to_jsonrpc(:not_found), do: -32004
  def to_jsonrpc(:internal_server_error), do: -32603
end
```

## AshRpc.Output

Output processing and formatting.

### AshRpc.Output.Transformer

Handles input/output transformations.

```elixir
defmodule AshRpc.Output.Transformer do
  @moduledoc """
  Behaviour for input/output transformations.
  """

  @callback decode_input(term(), map()) :: term()
  @callback encode_output(term(), map()) :: term()
end
```

### AshRpc.Output.Transformer.Identity

Default transformer with no modifications.

```elixir
defmodule AshRpc.Output.Transformer.Identity do
  @behaviour AshRpc.Output.Transformer

  @impl true
  def decode_input(input, _ctx), do: input

  @impl true
  def encode_output(output, _ctx), do: output
end
```

### AshRpc.Output.ResultProcessor

Processes query and mutation results.

```elixir
defmodule AshRpc.Output.ResultProcessor do
  @moduledoc """
  Processes and formats query/mutation results.
  """

  @spec process_result(term(), map()) :: term()
  def process_result(result, ctx) do
    # Apply metadata functions
    # Transform result format
    # Handle pagination
  end
end
```

### AshRpc.Output.ZodSchemaGenerator

Generates Zod schemas for TypeScript validation.

```elixir
defmodule AshRpc.Output.ZodSchemaGenerator do
  @moduledoc """
  Generates Zod schemas from Ash resource definitions.
  """

  @spec generate_zod_schema(module(), Ash.Resource.Action.t(), String.t()) :: String.t()
  def generate_zod_schema(resource, action, procedure_name) do
    # Analyze resource and action
    # Generate Zod schema string
    # Handle nested relationships
  end

  @spec generate_zod_schemas_for_embedded_resources([module()]) :: String.t()
  def generate_zod_schemas_for_embedded_resources(resources) do
    # Generate schemas for embedded resources
  end
end
```

## AshRpc.Input

Input processing and validation.

### AshRpc.Input.InputProcessor

Processes and validates input parameters.

```elixir
defmodule AshRpc.Input.InputProcessor do
  @moduledoc """
  Processes and validates input parameters for Ash actions.
  """

  @spec process_input(map(), map()) :: {:ok, map()} | {:error, term()}
  def process_input(input, ctx) do
    # Validate input structure
    # Transform parameter names
    # Apply defaults
  end
end
```

### AshRpc.Input.FieldSelector

Handles field selection logic.

```elixir
defmodule AshRpc.Input.FieldSelector do
  @moduledoc """
  Processes field selection parameters.
  """

  @spec parse_select(String.t() | [String.t()]) :: {:ok, map()} | {:error, term()}
  def parse_select(select) do
    # Parse field selection syntax
    # Handle include/exclude logic
    # Validate field names
  end
end
```

### AshRpc.Input.QueryBuilder

Builds Ash queries from tRPC parameters.

```elixir
defmodule AshRpc.Input.QueryBuilder do
  @moduledoc """
  Builds Ash queries from tRPC request parameters.
  """

  @spec build_query(map(), map()) :: Ash.Query.t()
  def build_query(params, ctx) do
    # Apply filters
    # Add sorting
    # Set pagination
    # Select fields
    # Load relationships
  end
end
```

### AshRpc.Input.PaginationBuilder

Handles pagination parameter processing.

```elixir
defmodule AshRpc.Input.PaginationBuilder do
  @moduledoc """
  Processes pagination parameters for different strategies.
  """

  @spec build_pagination(map()) :: {:ok, map()} | {:error, term()}
  def build_pagination(params) do
    # Determine pagination strategy
    # Validate parameters
    # Build pagination options
  end
end
```

### AshRpc.Input.Validation

Input validation utilities.

```elixir
defmodule AshRpc.Input.Validation do
  @moduledoc """
  Input validation utilities and helpers.
  """

  @spec validate_params(map(), map()) :: {:ok, map()} | {:error, [term()]}
  def validate_params(params, schema) do
    # Validate against schema
    # Check required fields
    # Validate field types
  end
end
```

## AshRpc.Util

Utility modules.

### AshRpc.Util.Request

Request parsing and processing utilities.

```elixir
defmodule AshRpc.Util.Request do
  @moduledoc """
  Utilities for parsing and processing HTTP requests.
  """

  @spec parse_body(Plug.Conn.t()) :: {:ok, map()} | {:error, term()}
  def parse_body(conn) do
    # Parse request body
    # Handle different content types
    # Validate JSON structure
  end

  @spec extract_procedure(String.t()) :: {:ok, map()} | {:error, term()}
  def extract_procedure(path) do
    # Extract domain, resource, action from path
    # Validate procedure format
  end
end
```

### AshRpc.Util.Subscriptions

Subscription management utilities.

```elixir
defmodule AshRpc.Util.Subscriptions do
  @moduledoc """
  Utilities for managing real-time subscriptions.
  """

  @spec topic_for_resource(module(), Ash.Resource.record()) :: String.t()
  def topic_for_resource(resource, record) do
    # Generate topic name for resource
    # Include relevant identifiers
  end

  @spec broadcast_change(atom(), String.t(), term()) :: :ok
  def broadcast_change(pubsub, topic, data) do
    # Broadcast change to subscribers
    # Handle pubsub adapter
  end
end
```

### AshRpc.Util.Codegen

Code generation utilities.

```elixir
defmodule AshRpc.Util.Codegen do
  @moduledoc """
  Utilities for generating TypeScript types and schemas.
  """

  @spec generate_typescript_types([module()]) :: String.t()
  def generate_typescript_types(domains) do
    # Generate TypeScript type definitions
    # Include all procedures and types
  end

  @spec generate_zod_schemas([module()]) :: String.t()
  def generate_zod_schemas(domains) do
    # Generate Zod validation schemas
    # Include input/output schemas
  end
end
```

## Mix Tasks

### mix ash_rpc.install

Installs AshRpc into a Phoenix application.

```bash
mix ash_rpc.install
```

**What it does:**

- Creates `MyAppWeb.TrpcRouter` module
- Adds tRPC pipeline to Phoenix router
- Configures route forwarding to `/trpc`
- Formats generated files

### mix ash_rpc.codegen

Generates TypeScript types and Zod schemas.

```bash
# Generate types only
mix ash_rpc.codegen --output=./frontend/generated

# Generate types and Zod schemas
mix ash_rpc.codegen --output=./frontend/generated --zod

# Generate for specific domains
mix ash_rpc.codegen --output=./frontend/generated --domains=MyApp.Accounts,MyApp.Billing
```

**Options:**

- `--output` (required): Output directory for generated files
- `--domains` (optional): Comma-separated list of domain modules
- `--zod` (optional): Generate Zod validation schemas

## Configuration Options

### Application Configuration

```elixir
# config/config.exs
config :ash_rpc,
  debug: false,
  batch_max_size: 50,
  batch_timeout: 100
```

### Router Configuration Options

```elixir
# Complete router configuration
defmodule MyAppWeb.TrpcRouter do
  use AshRpc.Router,
    # Required
    domains: [MyApp.Accounts, MyApp.Billing],

    # Optional
    transformer: MyApp.TrpcTransformer,
    before: [MyApp.TrpcHooks.Logging],
    after: [MyApp.TrpcHooks.Metrics],
    create_context: &MyApp.TrpcContext.create/1,
    middlewares: [MyApp.TrpcMiddleware.Auth],
    batch_max_size: 100,
    batch_timeout: 200,
    debug: Mix.env() == :dev
end
```

### Phoenix Pipeline Options

```elixir
# config/prod.exs
config :my_app, MyAppWeb.Endpoint,
  # tRPC specific configuration
  trpc: [
    batch_enabled: true,
    max_batch_size: 100,
    timeout: 30000
  ]
```

## Type Definitions

### Context Map

```elixir
@type context :: %{
  actor: Ash.Resource.record() | nil,
  tenant: term() | nil,
  domains: [module()],
  procedure: String.t(),
  input: map(),
  conn: Plug.Conn.t(),
  start_time: integer(),
  optional(atom()) => term()
}
```

### Middleware Behaviour

```elixir
defmodule MyMiddleware do
  @behaviour AshRpc.Execution.Middleware

  @impl true
  def before_request(ctx) do
    # Modify context before processing
    ctx
  end

  @impl true
  def after_request(ctx, result) do
    # Modify result after processing
    result
  end
end
```

### Transformer Behaviour

```elixir
defmodule MyTransformer do
  @behaviour AshRpc.Output.Transformer

  @impl true
  def decode_input(input, ctx) do
    # Transform input before processing
    input
  end

  @impl true
  def encode_output(output, ctx) do
    # Transform output before sending
    output
  end
end
```

### Error Handler Behaviour

```elixir
defmodule MyErrorHandler do
  @behaviour AshRpc.ErrorHandler

  @impl true
  def transform_error(error, context) do
    # Transform error to tRPC format
    # Add custom error handling logic
  end
end
```

## Generated TypeScript Types

### AppRouter

```typescript
export declare const appRouter: BuiltRouter<
  {
    ctx: Record<string, unknown>;
    meta: object;
    errorShape: TRPCErrorShape;
    transformer: true;
  },
  DeclarativeRouterRecord
>;
```

### Procedure Types

```typescript
// Query procedures
type AccountsUserRead = TRPCQueryProcedure<{
  input: {
    filter?: AshFilter<User>;
    sort?: AshSort;
    select?: AshSelect;
    page?: AshPage;
    load?: string[];
  };
  output: AshQueryResponse<User>;
}>;

// Mutation procedures
type AccountsUserCreate = TRPCMutationProcedure<{
  input: {
    email: string;
    password: string;
    name: string;
  };
  output: {
    result: User;
    meta: { userId: string; createdAt: string };
  };
}>;
```

### Filter Types

```typescript
type AshFieldOps<T> =
  | T
  | {
      eq?: T;
      neq?: T;
      gt?: T;
      lt?: T;
      gte?: T;
      lte?: T;
      like?: string;
      ilike?: string;
      in?: T[];
      contains?: T;
    };

type AshFilter<Shape> = Partial<{
  [K in keyof Shape]: AshFieldOps<Shape[K]>;
}> & {
  and?: AshFilter<Shape>[];
  or?: AshFilter<Shape>[];
  not?: AshFilter<Shape>;
};
```

### Pagination Types

```typescript
type AshPage =
  | { type: "offset"; limit?: number; offset?: number; count?: boolean }
  | { type: "keyset"; limit?: number; after?: AshCursor; before?: AshCursor };

type AshCursor = string;
```

### Response Types

```typescript
interface AshQueryResponse<T = unknown> {
  result: T;
  meta: Record<string, unknown>;
}

interface AshPaginatedQueryResponse<T = unknown> {
  result: T;
  meta: {
    limit: number;
    offset?: number;
    hasMore?: boolean;
    hasPrevious?: boolean;
    currentPage?: number;
    nextPage?: number | null;
    previousPage?: number | null;
    totalPages?: number | null;
    count?: number | null;
    nextCursor?: AshCursor;
    hasNextPage?: boolean;
    type: "offset" | "keyset";
  } & Record<string, unknown>;
}
```

This comprehensive API reference provides detailed documentation for all AshRpc modules, functions, and configuration options.
