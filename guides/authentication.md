# Authentication & Authorization Guide

This guide covers authentication and authorization in AshRpc applications, including integration with AshAuthentication and custom authentication strategies.

> ⚠️ **EXPERIMENTAL WARNING**: AshRpc is still in early development and considered highly experimental. Breaking changes may occur frequently without notice. We strongly advise against using this package in production environments until it reaches a stable release (v1.0.0+).

## Overview

AshRpc integrates seamlessly with Ash's authorization system and supports various authentication methods:

- **Bearer Token Authentication** (recommended)
- **Session-based Authentication**
- **API Key Authentication**
- **Custom Authentication Strategies**

## AshAuthentication Integration

AshAuthentication provides a complete authentication solution that works out-of-the-box with AshRpc.

### Setup

First, ensure you have AshAuthentication configured in your application:

```elixir
# mix.exs
defp deps do
  [
    {:ash_authentication, "~> 3.0"},
    {:ash_authentication_phoenix, "~> 1.0"},
    # ... other deps
  ]
end
```

### Router Configuration

Configure your Phoenix router with authentication pipelines:

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  use AshAuthentication.Phoenix.Router

  # Public tRPC pipeline (no auth required)
  pipeline :ash_rpc_public do
    plug :accepts, ["json"]
  end

  # Authenticated tRPC pipeline
  pipeline :ash_rpc do
    plug :accepts, ["json"]
    plug :load_from_session  # Load user from session
    plug :retrieve_from_bearer  # Extract JWT from Authorization header
    plug :set_actor, :user      # Set current user as actor
  end

  # Admin-only pipeline
  pipeline :ash_rpc_admin do
    plug :accepts, ["json"]
    plug :retrieve_from_bearer
    plug :set_actor, :user
    plug :require_admin  # Custom plug to check admin role
  end

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
      pipe_through :ash_rpc_admin
      forward "/", MyAppWeb.AdminTrpcRouter
    end
  end

  # AshAuthentication routes
  scope "/" do
    pipe_through [:browser, :require_authenticated_user]
    ash_authentication_live_session :authenticated_user
  end

  scope "/" do
    pipe_through :browser
    ash_authentication_live_session :public
  end
end
```

### User Resource Configuration

Configure your User resource with AshAuthentication:

```elixir
defmodule MyApp.Accounts.User do
  use Ash.Resource,
    extensions: [AshAuthentication, AshRpc],
    domain: MyApp.Accounts

  # AshAuthentication configuration
  authentication do
    strategies do
      password :password do
        identity_field :email
        hashed_password_field :hashed_password
      end
    end

    tokens do
      enabled? true
      token_resource MyApp.Accounts.Token
      signing_secret MyApp.Secrets.signing_secret()
    end
  end

  # AshRpc configuration
  ash_rpc do
    expose [:read, :register_with_password, :sign_in_with_password]

    mutation :register, :register_with_password do
      metadata fn _subject, user, _ctx ->
        %{user_id: user.id, token: user.__metadata__.token}
      end
    end

    mutation :login, :sign_in_with_password do
      metadata fn _subject, user, _ctx ->
        %{user_id: user.id, token: user.__metadata__.token}
      end
    end
  end

  # Resource attributes and actions...
  attributes do
    uuid_primary_key :id
    attribute :email, :string, allow_nil?: false
    attribute :hashed_password, :string, allow_nil?: false
    attribute :role, :atom, default: :user, constraints: [one_of: [:user, :admin]]
  end

  actions do
    # Authentication actions provided by AshAuthentication
    defaults [:read, :create, :update]

    create :register_with_password do
      argument :password, :string, allow_nil?: false
      change AshAuthentication.GenerateTokenChange
      change AshAuthentication.HashPasswordChange
    end

    action :sign_in_with_password do
      argument :password, :string, allow_nil?: false
      run AshAuthentication.Strategy.Password.SignInChange
    end
  end

  # Authorization policies
  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if relates_to_actor_via(:self)
    end

    policy action_type(:update) do
      authorize_if relates_to_actor_via(:self)
    end
  end
end
```

## Frontend Authentication

### tRPC Client Setup with Authentication

```typescript
// client.ts
import { createTRPCClient, httpBatchLink } from "@trpc/client";
import type { AppRouter } from "./generated/trpc";

export function createAuthenticatedClient(token?: string) {
  return createTRPCClient<AppRouter>({
    links: [
      httpBatchLink({
        url: "/trpc",
        headers: token ? { Authorization: `Bearer ${token}` } : {},
      }),
    ],
  });
}

// Auth context provider
import { createContext, useContext, useState, ReactNode } from "react";

interface AuthContextType {
  token: string | null;
  login: (email: string, password: string) => Promise<void>;
  logout: () => void;
  client: ReturnType<typeof createAuthenticatedClient>;
}

const AuthContext = createContext<AuthContextType | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [token, setToken] = useState<string | null>(
    localStorage.getItem("auth_token")
  );

  const client = createAuthenticatedClient(token || undefined);

  const login = async (email: string, password: string) => {
    const publicClient = createAuthenticatedClient();

    const result = await publicClient.accounts.user.login.mutate({
      email,
      password,
    });

    const newToken = result.meta.token;
    setToken(newToken);
    localStorage.setItem("auth_token", newToken);
  };

  const logout = () => {
    setToken(null);
    localStorage.removeItem("auth_token");
  };

  return (
    <AuthContext.Provider value={{ token, login, logout, client }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error("useAuth must be used within an AuthProvider");
  }
  return context;
}
```

### Registration and Login Components

```tsx
// Register.tsx
import { useAuth } from "./AuthContext";

function RegisterForm() {
  const { client } = useAuth();
  const [formData, setFormData] = useState({
    email: "",
    password: "",
    name: "",
  });

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    try {
      const result = await client.accounts.user.register.mutate(formData);

      // Registration successful
      console.log("User created:", result.result);
      console.log("Token:", result.meta.token);

      // Optionally auto-login after registration
      // await login(formData.email, formData.password);
    } catch (error: any) {
      console.error("Registration failed:", error.shape?.message);
    }
  };

  return (
    <form onSubmit={handleSubmit}>
      <input
        type="email"
        value={formData.email}
        onChange={(e) =>
          setFormData((prev) => ({ ...prev, email: e.target.value }))
        }
        placeholder="Email"
        required
      />
      <input
        type="password"
        value={formData.password}
        onChange={(e) =>
          setFormData((prev) => ({ ...prev, password: e.target.value }))
        }
        placeholder="Password"
        required
      />
      <input
        type="text"
        value={formData.name}
        onChange={(e) =>
          setFormData((prev) => ({ ...prev, name: e.target.value }))
        }
        placeholder="Name"
        required
      />
      <button type="submit">Register</button>
    </form>
  );
}

// Login.tsx
import { useAuth } from "./AuthContext";

function LoginForm() {
  const { login } = useAuth();
  const [credentials, setCredentials] = useState({
    email: "",
    password: "",
  });

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    try {
      await login(credentials.email, credentials.password);
      // Redirect to dashboard or home page
    } catch (error: any) {
      console.error("Login failed:", error.shape?.message);
    }
  };

  return (
    <form onSubmit={handleSubmit}>
      <input
        type="email"
        value={credentials.email}
        onChange={(e) =>
          setCredentials((prev) => ({ ...prev, email: e.target.value }))
        }
        placeholder="Email"
        required
      />
      <input
        type="password"
        value={credentials.password}
        onChange={(e) =>
          setCredentials((prev) => ({ ...prev, password: e.target.value }))
        }
        placeholder="Password"
        required
      />
      <button type="submit">Login</button>
    </form>
  );
}
```

## Custom Authentication Strategies

### API Key Authentication

Create a custom authentication strategy for API keys:

```elixir
# lib/my_app/plugs/api_key_auth.ex
defmodule MyApp.Plugs.ApiKeyAuth do
  import Plug.Conn
  alias MyApp.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> api_key] <- get_req_header(conn, "authorization"),
         {:ok, user} <- Accounts.get_user_by_api_key(api_key) do
      assign(conn, :current_user, user)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "Invalid API key"})
        |> halt()
    end
  end
end

# Router configuration
pipeline :ash_rpc_api_key do
  plug :accepts, ["json"]
  plug MyApp.Plugs.ApiKeyAuth
  plug :set_actor, :user
end
```

### Session-based Authentication

For traditional web applications with session management:

```elixir
# lib/my_app/plugs/session_auth.ex
defmodule MyApp.Plugs.SessionAuth do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :user_id) do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "Not authenticated"})
        |> halt()

      user_id ->
        # Load user from database
        case MyApp.Accounts.get_user(user_id) do
          {:ok, user} ->
            assign(conn, :current_user, user)

          {:error, _} ->
            conn
            |> delete_session(:user_id)
            |> put_status(:unauthorized)
            |> Phoenix.Controller.json(%{error: "User not found"})
            |> halt()
        end
    end
  end
end

# Router configuration
pipeline :ash_rpc_session do
  plug :accepts, ["json"]
  plug MyApp.Plugs.SessionAuth
  plug :set_actor, :user
end
```

## Authorization Policies

### Resource-level Authorization

Configure authorization policies on your Ash resources:

```elixir
defmodule MyApp.Blog.Post do
  use Ash.Resource,
    extensions: [AshRpc],
    domain: MyApp.Blog

  ash_rpc do
    expose [:read, :create, :update, :destroy]
  end

  policies do
    # Anyone can read published posts
    policy action_type(:read) do
      authorize_if expr(published == true)
      authorize_if actor_attribute_equals(:role, :admin)
    end

    # Only authenticated users can create posts
    policy action(:create) do
      authorize_if actor_present()
    end

    # Users can only update their own posts
    policy action(:update) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if relates_to_actor_via([:author])
    end

    # Only admins can delete posts
    policy action(:destroy) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end
end
```

### Field-level Authorization

Control access to specific fields:

```elixir
defmodule MyApp.Accounts.User do
  # ... resource setup

  field_policies do
    field_policy :email do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if relates_to_actor_via(:self)
    end

    field_policy :salary do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy [:hashed_password, :reset_token] do
      # Never show sensitive fields
      forbid_if always()
    end
  end
end
```

### Custom Authorization Logic

Implement custom authorization checks:

```elixir
defmodule MyApp.PolicyHelpers do
  use Ash.Policy.Authorizer

  def can_access_tenant?(actor, tenant_id) do
    # Check if user has access to specific tenant
    case actor do
      %{role: :admin} -> true
      %{tenant_id: ^tenant_id} -> true
      _ -> false
    end
  end

  def is_account_owner?(actor, account_id) do
    # Check if user owns the account
    MyApp.Accounts.user_owns_account?(actor.id, account_id)
  end
end

# Use in policies
policy action(:update) do
  authorize_if {MyApp.PolicyHelpers, :can_access_tenant?, [:actor, :tenant_id]}
  authorize_if {MyApp.PolicyHelpers, :is_account_owner?, [:actor, :account_id]}
end
```

## Multi-tenant Applications

### Tenant-scoped Authentication

For multi-tenant applications, scope authentication to specific tenants:

```elixir
# lib/my_app/plugs/tenant_auth.ex
defmodule MyApp.Plugs.TenantAuth do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- MyApp.Auth.verify_token(token),
         {:ok, tenant} <- MyApp.Tenants.get_tenant(claims["tenant_id"]),
         {:ok, user} <- MyApp.Accounts.get_user_by_tenant(claims["user_id"], tenant.id) do

      conn
      |> assign(:current_user, user)
      |> assign(:current_tenant, tenant)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "Invalid authentication"})
        |> halt()
    end
  end
end

# Router configuration
pipeline :ash_rpc_tenant do
  plug :accepts, ["json"]
  plug MyApp.Plugs.TenantAuth
  plug :set_actor, :user
  plug :set_tenant, :tenant  # Custom plug to set tenant context
end
```

### Tenant Context in Resources

Use tenant context in your resource policies:

```elixir
defmodule MyApp.Blog.Post do
  # ... resource setup

  policies do
    policy action_type(:read) do
      # User must belong to the same tenant as the post
      authorize_if expr(tenant_id == ^actor(:current_tenant).id)
    end

    policy action(:create) do
      authorize_if actor_present()
      # Automatically set tenant_id from context
      change set_attribute(:tenant_id, actor(:current_tenant).id)
    end
  end
end
```

## Security Best Practices

### Token Management

Implement proper token lifecycle management:

```elixir
# Token refresh endpoint
mutation :refresh_token, :refresh_token do
  argument :refresh_token, :string, allow_nil?: false

  run fn input, _ctx ->
    case MyApp.Auth.refresh_token(input.refresh_token) do
      {:ok, tokens} ->
        {:ok, %{access_token: tokens.access, refresh_token: tokens.refresh}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

# Frontend token refresh logic
const refreshToken = async () => {
  try {
    const response = await publicClient.auth.refreshToken.mutate({
      refreshToken: getRefreshToken(),
    });

    setAccessToken(response.access_token);
    setRefreshToken(response.refresh_token);
  } catch (error) {
    logout();
  }
};
```

### Rate Limiting

Implement rate limiting to prevent abuse:

```elixir
# lib/my_app/plugs/rate_limit.ex
defmodule MyApp.Plugs.RateLimit do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    max_requests = opts[:max_requests] || 100
    window_seconds = opts[:window_seconds] || 60
    key = rate_limit_key(conn)

    case Hammer.check_rate(key, max_requests, window_seconds * 1000) do
      {:allow, _count} ->
        conn

      {:deny, _count} ->
        conn
        |> put_status(:too_many_requests)
        |> put_resp_header("retry-after", to_string(window_seconds))
        |> Phoenix.Controller.json(%{error: "Rate limit exceeded"})
        |> halt()
    end
  end

  defp rate_limit_key(conn) do
    # Use IP address and user ID for rate limiting
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    user_id = conn.assigns[:current_user] && conn.assigns[:current_user].id
    "#{ip}:#{user_id || "anonymous"}"
  end
end

# Apply to router
pipeline :ash_rpc do
  plug :accepts, ["json"]
  plug MyApp.Plugs.RateLimit, max_requests: 1000, window_seconds: 60
  plug :retrieve_from_bearer
  plug :set_actor, :user
end
```

### Audit Logging

Log authentication and authorization events:

```elixir
# lib/my_app/trpc_hooks/audit.ex
defmodule MyApp.TrpcHooks.Audit do
  @behaviour AshRpc.Execution.Middleware

  require Logger

  @impl true
  def before_request(ctx) do
    Logger.info("tRPC request",
      procedure: ctx.procedure,
      actor: ctx.actor && ctx.actor.id,
      ip: get_ip(ctx.conn),
      user_agent: get_user_agent(ctx.conn)
    )
    ctx
  end

  @impl true
  def after_request(ctx, result) do
    case result do
      {:error, error} ->
        Logger.warn("tRPC error",
          procedure: ctx.procedure,
          actor: ctx.actor && ctx.actor.id,
          error: inspect(error),
          ip: get_ip(ctx.conn)
        )

      _ ->
        Logger.info("tRPC success",
          procedure: ctx.procedure,
          actor: ctx.actor && ctx.actor.id,
          ip: get_ip(ctx.conn)
        )
    end

    result
  end

  defp get_ip(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end

  defp get_user_agent(conn) do
    conn |> Plug.Conn.get_req_header("user-agent") |> List.first()
  end
end

# Add to router
use AshRpc.Router,
  domains: [MyApp.Accounts],
  after: [MyApp.TrpcHooks.Audit]
```

## Testing Authentication

### Unit Tests

Test authentication logic:

```elixir
# test/my_app/accounts/user_test.exs
defmodule MyApp.Accounts.UserTest do
  use MyApp.DataCase

  test "user can only read their own profile" do
    user1 = create_user()
    user2 = create_user()

    # User1 should be able to read their own profile
    assert {:ok, _} = Ash.read(User, actor: user1, filter: [id: user1.id])

    # User1 should not be able to read user2's profile
    assert {:error, _} = Ash.read(User, actor: user1, filter: [id: user2.id])
  end
end
```

### Integration Tests

Test complete authentication flows:

```elixir
# test/my_app_web/trpc_router_test.exs
defmodule MyAppWeb.TrpcRouterTest do
  use MyAppWeb.ConnCase, async: true

  test "authenticated user can access protected endpoints" do
    user = create_user()
    token = generate_token_for_user(user)

    conn = build_conn()
           |> put_req_header("authorization", "Bearer #{token}")
           |> post("/trpc/accounts.user.read", %{"input" => %{}})

    assert json_response(conn, 200)
    assert %{"result" => [%{"id" => user.id}]} = json_response(conn, 200)
  end

  test "unauthenticated user cannot access protected endpoints" do
    conn = post(build_conn(), "/trpc/accounts.user.read", %{"input" => %{}})

    assert json_response(conn, 200)
    assert %{"error" => %{"code" => "UNAUTHORIZED"}} = json_response(conn, 200)
  end
end
```

This comprehensive authentication guide covers all aspects of securing your AshRpc application, from basic token authentication to advanced multi-tenant authorization and security best practices.
