# Error Handling Guide

This guide covers comprehensive error handling in AshRpc applications, including error formats, handling strategies, debugging techniques, and best practices for providing excellent user experiences.

> ⚠️ **EXPERIMENTAL WARNING**: AshRpc is still in early development and considered highly experimental. Breaking changes may occur frequently without notice. We strongly advise against using this package in production environments until it reaches a stable release (v1.0.0+).

## Error Response Format

### tRPC Error Structure

AshRpc returns tRPC-compliant error envelopes with detailed information:

```typescript
interface TRPCError {
  code: number; // HTTP status code
  message: string; // High-level error message
  data: {
    code: string; // Specific error code
    httpStatus: number; // HTTP status code
    details?: Array<{
      // Detailed error breakdown
      message: string; // Specific error message
      code: string; // Error type code
      pointer?: string; // Field/attribute pointer
      field?: string; // Field name (legacy)
    }>;
  };
}
```

### Example Error Response

```json
{
  "id": 1,
  "error": {
    "code": -32600,
    "message": "Validation failed",
    "data": {
      "code": "VALIDATION_ERROR",
      "httpStatus": 400,
      "details": [
        {
          "message": "Email is required",
          "code": "missing_required_parameter",
          "pointer": "email"
        },
        {
          "message": "Password must be at least 8 characters",
          "code": "field_validation_error",
          "pointer": "password"
        }
      ]
    }
  }
}
```

## Error Types

### Validation Errors

Field-level validation errors with specific details:

```typescript
// Backend: Ash validation
defmodule MyApp.Accounts.User do
  attributes do
    attribute :email, :string do
      constraints [format: ~r/@/]
      allow_nil? false
    end

    attribute :password, :string do
      constraints [min_length: 8]
      allow_nil? false
    end
  end
end

// Frontend: Error handling
try {
  await client.accounts.user.create.mutate({
    email: "invalid-email",
    password: "123"
  });
} catch (error: any) {
  // Handle validation errors
  error.shape?.data?.details?.forEach(detail => {
    if (detail.pointer === "email") {
      setEmailError(detail.message);
    } else if (detail.pointer === "password") {
      setPasswordError(detail.message);
    }
  });
}
```

### Authentication Errors

Handle authentication and authorization failures:

```typescript
// UNAUTHORIZED (401)
{
  "error": {
    "code": -32001,
    "message": "Authentication required",
    "data": {
      "code": "UNAUTHORIZED",
      "httpStatus": 401
    }
  }
}

// FORBIDDEN (403)
{
  "error": {
    "code": -32003,
    "message": "Access denied",
    "data": {
      "code": "FORBIDDEN",
      "httpStatus": 403
    }
  }
}
```

### Not Found Errors

Resource not found scenarios:

```typescript
// NOT_FOUND (404)
{
  "error": {
    "code": -32004,
    "message": "User not found",
    "data": {
      "code": "NOT_FOUND",
      "httpStatus": 404
    }
  }
}
```

### Server Errors

Internal server errors and unexpected failures:

```typescript
// INTERNAL_SERVER_ERROR (500)
{
  "error": {
    "code": -32603,
    "message": "Internal server error",
    "data": {
      "code": "INTERNAL_SERVER_ERROR",
      "httpStatus": 500
    }
  }
}
```

## Frontend Error Handling

### Global Error Handler

Set up global error handling for your tRPC client:

```typescript
// lib/trpc.ts
import { createTRPCClient, httpBatchLink } from "@trpc/client";
import { toast } from "react-hot-toast";

export const client = createTRPCClient<AppRouter>({
  links: [
    httpBatchLink({
      url: "/trpc",
      // Global error handler
      fetch: async (url, options) => {
        const response = await fetch(url, options);

        if (response.status === 401) {
          // Clear invalid token
          localStorage.removeItem("auth_token");
          // Redirect to login
          window.location.href = "/login";
          return response;
        }

        if (!response.ok) {
          const errorData = await response
            .clone()
            .json()
            .catch(() => ({}));
          const error = errorData.error;

          if (error) {
            // Handle different error types
            switch (error.data?.code) {
              case "VALIDATION_ERROR":
                // Don't show toast for validation errors (handled by forms)
                break;

              case "FORBIDDEN":
                toast.error("You don't have permission to perform this action");
                break;

              case "NOT_FOUND":
                toast.error("The requested resource was not found");
                break;

              default:
                toast.error(error.message || "Something went wrong");
            }
          }
        }

        return response;
      },
    }),
  ],
});
```

### Form-Level Error Handling

Handle validation errors in forms:

```tsx
// components/UserForm.tsx
import { useState } from "react";
import { trpc } from "../lib/trpc";

function UserForm() {
  const [formData, setFormData] = useState({
    email: "",
    password: "",
    name: "",
  });

  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});
  const [generalError, setGeneralError] = useState("");

  const createUser = trpc.accounts.user.create.useMutation({
    onError: (error) => {
      setFieldErrors({});
      setGeneralError("");

      const details = error.shape?.data?.details || [];

      details.forEach((detail: any) => {
        if (detail.pointer) {
          // Field-specific error
          setFieldErrors((prev) => ({
            ...prev,
            [detail.pointer]: detail.message,
          }));
        } else {
          // General error
          setGeneralError(detail.message);
        }
      });

      // Fallback for high-level error message
      if (details.length === 0) {
        setGeneralError(error.shape?.message || "An error occurred");
      }
    },
  });

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setFieldErrors({});
    setGeneralError("");

    try {
      await createUser.mutateAsync(formData);
      // Success handling
    } catch (error) {
      // Error already handled in onError
    }
  };

  return (
    <form onSubmit={handleSubmit}>
      {generalError && (
        <div className="error general-error">{generalError}</div>
      )}

      <div>
        <label>Email</label>
        <input
          type="email"
          value={formData.email}
          onChange={(e) =>
            setFormData((prev) => ({
              ...prev,
              email: e.target.value,
            }))
          }
          className={fieldErrors.email ? "error" : ""}
        />
        {fieldErrors.email && (
          <span className="field-error">{fieldErrors.email}</span>
        )}
      </div>

      <div>
        <label>Password</label>
        <input
          type="password"
          value={formData.password}
          onChange={(e) =>
            setFormData((prev) => ({
              ...prev,
              password: e.target.value,
            }))
          }
          className={fieldErrors.password ? "error" : ""}
        />
        {fieldErrors.password && (
          <span className="field-error">{fieldErrors.password}</span>
        )}
      </div>

      <button type="submit" disabled={createUser.isLoading}>
        {createUser.isLoading ? "Creating..." : "Create User"}
      </button>
    </form>
  );
}
```

### Error Boundaries

Create React error boundaries for tRPC errors:

```tsx
// components/TrpcErrorBoundary.tsx
import React from "react";
import { toast } from "react-hot-toast";

interface TrpcErrorInfo {
  error: {
    code: number;
    message: string;
    data: {
      code: string;
      details?: Array<{
        message: string;
        code: string;
        pointer?: string;
      }>;
    };
  };
  procedure: string;
  input: unknown;
}

interface Props {
  children: React.ReactNode;
  fallback?: (error: TrpcErrorInfo) => React.ReactNode;
}

class TrpcErrorBoundary extends React.Component<
  Props,
  { hasError: boolean; errorInfo?: TrpcErrorInfo }
> {
  constructor(props: Props) {
    super(props);
    this.state = { hasError: false };
  }

  static getDerivedStateFromError(error: any): any {
    // Check if it's a tRPC error
    if (error?.shape?.data?.code) {
      return {
        hasError: true,
        errorInfo: {
          error: error.shape,
          procedure: error.meta?.procedure || "unknown",
          input: error.meta?.input,
        },
      };
    }

    // Re-throw non-tRPC errors
    throw error;
  }

  componentDidCatch(error: any, errorInfo: any) {
    // Log error details
    console.error("tRPC Error Boundary:", {
      error: error.shape,
      procedure: this.state.errorInfo?.procedure,
      componentStack: errorInfo.componentStack,
    });

    // Report to error tracking service
    // reportError(error, { procedure: this.state.errorInfo?.procedure });
  }

  render() {
    if (this.state.hasError && this.state.errorInfo) {
      if (this.props.fallback) {
        return this.props.fallback(this.state.errorInfo);
      }

      return (
        <div className="error-boundary">
          <h3>Something went wrong</h3>
          <p>Procedure: {this.state.errorInfo.procedure}</p>
          <p>{this.state.errorInfo.error.message}</p>
          <button
            onClick={() =>
              this.setState({ hasError: false, errorInfo: undefined })
            }
          >
            Try again
          </button>
        </div>
      );
    }

    return this.props.children;
  }
}

// Usage
function App() {
  return (
    <TrpcErrorBoundary
      fallback={(errorInfo) => (
        <div className="error-fallback">
          <h2>API Error</h2>
          <p>Failed to execute: {errorInfo.procedure}</p>
          <p>{errorInfo.error.message}</p>
          <button onClick={() => window.location.reload()}>Reload Page</button>
        </div>
      )}
    >
      <MyApp />
    </TrpcErrorBoundary>
  );
}
```

### Retry Logic

Implement intelligent retry strategies:

```typescript
// lib/trpc.ts
import { RetryDelayFn } from "@trpc/client";

const customRetryDelay: RetryDelayFn = (attemptIndex, error) => {
  // Don't retry validation errors
  if (error?.data?.code === "VALIDATION_ERROR") {
    return false;
  }

  // Don't retry auth errors
  if (error?.data?.code === "UNAUTHORIZED") {
    return false;
  }

  // Don't retry forbidden errors
  if (error?.data?.code === "FORBIDDEN") {
    return false;
  }

  // Exponential backoff for server errors
  const baseDelay = 1000; // 1 second
  const maxDelay = 30000; // 30 seconds
  const delay = Math.min(baseDelay * Math.pow(2, attemptIndex), maxDelay);

  // Add jitter to prevent thundering herd
  return delay + Math.random() * 1000;
};

export const client = createTRPCClient<AppRouter>({
  links: [
    httpBatchLink({
      url: "/trpc",
    }),
  ],
  // Global retry configuration
  default: {
    retryDelay: customRetryDelay,
    retries: 3,
  },
});
```

## Backend Error Handling

### Custom Error Types

Create custom error types for your application:

```elixir
# lib/my_app/errors.ex
defmodule MyApp.Errors do
  defmodule PaymentRequired do
    defexception [:message, :details]

    @impl true
    def to_trpc_error(error) do
      %{
        code: -32002,
        message: error.message || "Payment required",
        data: %{
          code: "PAYMENT_REQUIRED",
          httpStatus: 402,
          details: error.details || []
        }
      }
    end
  end

  defmodule RateLimited do
    defexception [:message, :retry_after]

    @impl true
    def to_trpc_error(error) do
      %{
        code: -32005,
        message: error.message || "Rate limit exceeded",
        data: %{
          code: "RATE_LIMITED",
          httpStatus: 429,
          retry_after: error.retry_after,
          details: [%{message: "Too many requests", code: "rate_limited"}]
        }
      }
    end
  end
end
```

### Error Transformation

Transform Ash errors into user-friendly messages:

```elixir
# lib/my_app/error_handler.ex
defmodule MyApp.ErrorHandler do
  @behaviour AshRpc.ErrorHandler

  @impl true
  def transform_error(error, context) do
    case error do
      %Ash.Error.Invalid{errors: errors} ->
        # Transform validation errors
        transformed_errors = Enum.map(errors, &transform_validation_error/1)

        %{
          code: -32600,
          message: "Validation failed",
          data: %{
            code: "VALIDATION_ERROR",
            httpStatus: 400,
            details: transformed_errors
          }
        }

      %Ash.Error.Forbidden{} ->
        %{
          code: -32003,
          message: "Access denied",
          data: %{
            code: "FORBIDDEN",
            httpStatus: 403,
            details: [%{message: "You don't have permission to perform this action"}]
          }
        }

      %Ash.Error.Query.NotFound{} ->
        %{
          code: -32004,
          message: "Resource not found",
          data: %{
            code: "NOT_FOUND",
            httpStatus: 404,
            details: [%{message: "The requested resource could not be found"}]
          }
        }

      _ ->
        # Generic error handling
        Logger.error("Unexpected error", %{error: error, context: context})

        %{
          code: -32603,
          message: "Internal server error",
          data: %{
            code: "INTERNAL_SERVER_ERROR",
            httpStatus: 500,
            details: [%{message: "An unexpected error occurred"}]
          }
        }
    end
  end

  defp transform_validation_error(error) do
    case error do
      %{field: field, message: message} ->
        %{
          message: message,
          code: "field_validation_error",
          pointer: to_string(field)
        }

      %{message: message} ->
        %{
          message: message,
          code: "validation_error"
        }
    end
  end
end
```

### Middleware for Error Handling

Create middleware to handle errors consistently:

```elixir
# lib/my_app/middleware/error_middleware.ex
defmodule MyApp.Middleware.ErrorMiddleware do
  @behaviour AshRpc.Execution.Middleware

  @impl true
  def before_request(ctx) do
    ctx
  end

  @impl true
  def after_request(ctx, result) do
    case result do
      {:error, error} ->
        # Log detailed error information
        Logger.error("API Error", %{
          procedure: ctx.procedure,
          error: inspect(error),
          actor: ctx.actor && ctx.actor.id,
          input: ctx.input,
          timestamp: DateTime.utc_now()
        })

        # Transform error for client
        {:error, MyApp.ErrorHandler.transform_error(error, ctx)}

      _ ->
        result
    end
  end
end

# Add to router
defmodule MyAppWeb.TrpcRouter do
  use AshRpc.Router,
    domains: [MyApp.Accounts],
    middlewares: [MyApp.Middleware.ErrorMiddleware]
end
```

## Debugging Errors

### Development Error Mode

Enable detailed error information in development:

```elixir
# config/dev.exs
config :ash_rpc, debug: true

# Router configuration
defmodule MyAppWeb.TrpcRouter do
  use AshRpc.Router,
    domains: [MyApp.Accounts],
    debug: true  # Include stack traces in development
end
```

### Error Logging

Comprehensive error logging for debugging:

```elixir
# lib/my_app/error_logger.ex
defmodule MyApp.ErrorLogger do
  require Logger

  def log_error(error, context) do
    Logger.error("AshRpc Error", %{
      error_type: error.__struct__,
      message: error.message,
      procedure: context.procedure,
      actor: context.actor && context.actor.id,
      input: inspect(context.input),
      stacktrace: __STACKTRACE__,
      timestamp: DateTime.utc_now()
    })
  end

  def log_validation_errors(errors, context) do
    Enum.each(errors, fn error ->
      Logger.warning("Validation Error", %{
        field: error.field,
        message: error.message,
        procedure: context.procedure,
        actor: context.actor && context.actor.id,
        timestamp: DateTime.utc_now()
      })
    end)
  end
end
```

### Client-Side Debugging

Debug tRPC requests and responses:

```typescript
// lib/trpc.ts
import { createTRPCClient, httpBatchLink, loggerLink } from "@trpc/client";

export const client = createTRPCClient<AppRouter>({
  links: [
    // Logger for development
    ...(process.env.NODE_ENV === "development"
      ? [
          loggerLink({
            colorMode: "ansi",
            enabled: (opts) =>
              opts.direction === "down" && opts.result instanceof Error,
          }),
        ]
      : []),

    httpBatchLink({
      url: "/trpc",
      // Log all requests in development
      fetch:
        process.env.NODE_ENV === "development"
          ? async (url, options) => {
              console.log("🚀 tRPC Request:", url, options);
              const start = Date.now();
              const response = await fetch(url, options);
              const duration = Date.now() - start;
              console.log(
                "✅ tRPC Response:",
                response.status,
                `(${duration}ms)`
              );
              return response;
            }
          : fetch,
    }),
  ],
});
```

## Error Monitoring

### Sentry Integration

Send errors to Sentry for monitoring:

```typescript
// lib/trpc.ts
import * as Sentry from "@sentry/browser";

export const client = createTRPCClient<AppRouter>({
  links: [
    httpBatchLink({
      url: "/trpc",
      fetch: async (url, options) => {
        try {
          const response = await fetch(url, options);

          if (!response.ok) {
            const errorData = await response
              .clone()
              .json()
              .catch(() => ({}));

            // Send to Sentry
            Sentry.captureException(new Error("tRPC Error"), {
              tags: {
                procedure: extractProcedure(url),
                status: response.status,
              },
              extra: {
                url,
                errorData,
                requestHeaders: options?.headers,
              },
            });
          }

          return response;
        } catch (error) {
          Sentry.captureException(error, {
            tags: {
              type: "network_error",
            },
            extra: {
              url,
            },
          });
          throw error;
        }
      },
    }),
  ],
});

function extractProcedure(url: string): string {
  // Extract procedure name from URL
  const match = url.match(/\/trpc\/([^?]+)/);
  return match ? match[1] : "unknown";
}
```

### Backend Monitoring

Monitor errors on the backend:

```elixir
# lib/my_app/error_monitor.ex
defmodule MyApp.ErrorMonitor do
  @behaviour AshRpc.Execution.Middleware

  @impl true
  def before_request(ctx) do
    ctx
  end

  @impl true
  def after_request(ctx, result) do
    case result do
      {:error, error} ->
        # Send to error monitoring service
        Task.async(fn ->
          MyApp.Monitoring.report_error(%{
            procedure: ctx.procedure,
            error: error,
            actor: ctx.actor,
            input: ctx.input,
            timestamp: DateTime.utc_now(),
            user_agent: get_user_agent(ctx.conn),
            ip: get_ip(ctx.conn)
          })
        end)

      _ ->
        :ok
    end

    result
  end

  defp get_user_agent(conn) do
    conn |> Plug.Conn.get_req_header("user-agent") |> List.first()
  end

  defp get_ip(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end
end
```

## Error Recovery Patterns

### Automatic Retry

Implement automatic retry for transient errors:

```typescript
// Custom retry link
import { retryLink } from "@trpc/client";

export const client = createTRPCClient<AppRouter>({
  links: [
    retryLink({
      attempts: (opts) => {
        const { error, type } = opts;

        // Don't retry mutations
        if (type === "mutation") return 1;

        // Don't retry auth errors
        if (error?.data?.code === "UNAUTHORIZED") return 1;

        // Retry network errors
        if (error?.data?.code === "INTERNAL_SERVER_ERROR") return 3;

        return 1;
      },
      delay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 30000),
    }),

    httpBatchLink({ url: "/trpc" }),
  ],
});
```

### Graceful Degradation

Handle service unavailability gracefully:

```typescript
// lib/trpc.ts
export const client = createTRPCClient<AppRouter>({
  links: [
    httpBatchLink({
      url: "/trpc",
      fetch: async (url, options) => {
        try {
          return await fetch(url, options);
        } catch (error) {
          // Network error - try fallback endpoint
          if (process.env.NODE_ENV === "production") {
            try {
              const fallbackUrl = url.replace("/trpc", "/api/fallback/trpc");
              return await fetch(fallbackUrl, options);
            } catch (fallbackError) {
              // Both primary and fallback failed
              throw error;
            }
          }

          throw error;
        }
      },
    }),
  ],
});
```

### Offline Support

Handle offline scenarios:

```typescript
// lib/offline_manager.ts
import { toast } from "react-hot-toast";

class OfflineManager {
  private isOnline = navigator.onLine;
  private queue: Array<{
    procedure: string;
    input: any;
    resolve: (value: any) => void;
    reject: (error: any) => void;
  }> = [];

  constructor() {
    window.addEventListener("online", this.handleOnline.bind(this));
    window.addEventListener("offline", this.handleOffline.bind(this));
  }

  private handleOnline() {
    this.isOnline = true;
    toast.success("Connection restored");

    // Process queued requests
    this.processQueue();
  }

  private handleOffline() {
    this.isOnline = false;
    toast.error(
      "You're offline. Changes will be synced when connection is restored."
    );
  }

  async executeRequest<T>(
    procedure: string,
    input: any,
    requestFn: () => Promise<T>
  ): Promise<T> {
    if (!this.isOnline) {
      return new Promise((resolve, reject) => {
        this.queue.push({
          procedure,
          input,
          resolve,
          reject,
        });
      });
    }

    return requestFn();
  }

  private async processQueue() {
    while (this.queue.length > 0) {
      const item = this.queue.shift();
      if (!item) break;

      try {
        const result = await this.executeActualRequest(
          item.procedure,
          item.input
        );
        item.resolve(result);
      } catch (error) {
        item.reject(error);
      }
    }
  }

  private async executeActualRequest(procedure: string, input: any) {
    // Execute the actual tRPC request
    const [domain, resource, action] = procedure.split(".");
    return client[domain][resource][action].mutate(input);
  }
}

export const offlineManager = new OfflineManager();
```

## Best Practices

### Error Messages

Write user-friendly error messages:

```elixir
# Bad
"Invalid input: email must match pattern"

# Good
"Please enter a valid email address"
```

### Error Codes

Use consistent error codes:

```elixir
# Define error codes
defmodule MyApp.ErrorCodes do
  @validation_error "VALIDATION_ERROR"
  @authentication_error "AUTHENTICATION_ERROR"
  @authorization_error "AUTHORIZATION_ERROR"
  @not_found_error "NOT_FOUND_ERROR"
  @server_error "SERVER_ERROR"

  # Helper functions
  def validation_error(message, field) do
    %{
      code: @validation_error,
      message: message,
      pointer: field
    }
  end
end
```

### Error Documentation

Document expected errors for each endpoint:

```typescript
/**
 * Creates a new user account
 *
 * @throws {VALIDATION_ERROR} When email or password is invalid
 * @throws {UNAUTHORIZED} When user is not authenticated
 * @throws {FORBIDDEN} When user lacks permission
 * @throws {CONFLICT} When email already exists
 */
export const createUser = client.accounts.user.create.mutate;
```

### Testing Error Scenarios

Test error handling thoroughly:

```typescript
// __tests__/error_handling.test.tsx
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { rest } from "msw";
import { setupServer } from "msw/node";
import UserForm from "../components/UserForm";

const server = setupServer(
  rest.post("/trpc/accounts.user.create", (req, res, ctx) => {
    return res(
      ctx.status(400),
      ctx.json({
        error: {
          code: -32600,
          message: "Validation failed",
          data: {
            code: "VALIDATION_ERROR",
            httpStatus: 400,
            details: [
              {
                message: "Email is required",
                code: "missing_required_parameter",
                pointer: "email",
              },
            ],
          },
        },
      })
    );
  })
);

beforeAll(() => server.listen());
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

test("shows validation errors", async () => {
  render(<UserForm />);

  const submitButton = screen.getByRole("button", { name: /create user/i });
  await userEvent.click(submitButton);

  await waitFor(() => {
    expect(screen.getByText("Email is required")).toBeInTheDocument();
  });
});
```

This comprehensive error handling guide provides everything you need to handle errors gracefully in your AshRpc applications, from basic error catching to advanced monitoring and recovery strategies.
