# Frontend Integration Guide

This comprehensive guide covers integrating AshRpc with modern frontend frameworks, including React, Vue, Svelte, and vanilla JavaScript. It includes advanced patterns, error handling, authentication, and performance optimization.

> ⚠️ **EXPERIMENTAL WARNING**: AshRpc is still in early development and considered highly experimental. Breaking changes may occur frequently without notice. We strongly advise against using this package in production environments until it reaches a stable release (v1.0.0+).

## Prerequisites

Before integrating AshRpc with your frontend:

1. **Generate TypeScript Types**:

   ```bash
   mix ash_rpc.gen --output=./frontend/generated --zod
   ```

2. **Install Dependencies**:
   ```bash
   npm install @trpc/client @tanstack/react-query zod
   # For React
   npm install @trpc/react-query
   # For Next.js
   npm install next
   ```

## Core Concepts

### tRPC Client Setup

```typescript
// lib/trpc.ts
import { createTRPCClient, httpBatchLink, loggerLink } from "@trpc/client";
import { createTRPCReact } from "@trpc/react-query";
import { QueryClient } from "@tanstack/react-query";
import type { AppRouter } from "../generated/trpc";

// Query client for React Query
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60 * 5, // 5 minutes
      retry: (failureCount, error: any) => {
        // Don't retry on auth errors
        if (error?.data?.code === "UNAUTHORIZED") return false;
        return failureCount < 3;
      },
    },
  },
});

// tRPC client factory
export function createClient(token?: string) {
  return createTRPCClient<AppRouter>({
    links: [
      // Logger for development
      ...(process.env.NODE_ENV === "development" ? [loggerLink()] : []),

      // Main HTTP link with batching
      httpBatchLink({
        url: "/trpc",
        headers: token ? { Authorization: `Bearer ${token}` } : {},

        // Handle auth errors globally
        async fetch(url, options) {
          const response = await fetch(url, options);

          if (response.status === 401) {
            // Clear invalid token
            localStorage.removeItem("auth_token");
            // Redirect to login
            window.location.href = "/login";
          }

          return response;
        },
      }),
    ],
  });
}

// React hooks
export const trpc = createTRPCReact<AppRouter>();
```

### Authentication Context

```tsx
// contexts/AuthContext.tsx
import React, {
  createContext,
  useContext,
  useState,
  useEffect,
  ReactNode,
} from "react";
import { createClient, trpc } from "../lib/trpc";

interface AuthContextType {
  token: string | null;
  user: any | null;
  login: (email: string, password: string) => Promise<void>;
  register: (userData: any) => Promise<void>;
  logout: () => void;
  isLoading: boolean;
}

const AuthContext = createContext<AuthContextType | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [token, setToken] = useState<string | null>(() =>
    typeof window !== "undefined" ? localStorage.getItem("auth_token") : null
  );
  const [user, setUser] = useState<any>(null);
  const [isLoading, setIsLoading] = useState(true);

  // Create client with current token
  const client = createClient(token || undefined);

  // Load user profile on mount
  useEffect(() => {
    if (token) {
      client.accounts.user.read
        .query({ select: ["id", "email", "name"] })
        .then(({ result }) => {
          setUser(result[0] || null);
        })
        .catch(() => {
          // Token invalid, clear it
          setToken(null);
          localStorage.removeItem("auth_token");
        })
        .finally(() => setIsLoading(false));
    } else {
      setIsLoading(false);
    }
  }, [token, client]);

  const login = async (email: string, password: string) => {
    const result = await client.accounts.user.login.mutate({ email, password });
    const newToken = result.meta.token;

    setToken(newToken);
    localStorage.setItem("auth_token", newToken);
  };

  const register = async (userData: any) => {
    const result = await client.accounts.user.register.mutate(userData);
    const newToken = result.meta.token;

    setToken(newToken);
    localStorage.setItem("auth_token", newToken);
  };

  const logout = () => {
    setToken(null);
    setUser(null);
    localStorage.removeItem("auth_token");
  };

  return (
    <AuthContext.Provider
      value={{
        token,
        user,
        login,
        register,
        logout,
        isLoading,
      }}
    >
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

## Data Fetching Patterns

### Basic Queries

```tsx
// components/UserList.tsx
import { trpc } from "../lib/trpc";

function UserList() {
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(0);

  const { data, isLoading, error } = trpc.accounts.user.read.useQuery({
    filter: search ? { email: { like: `%${search}%` } } : undefined,
    sort: { insertedAt: "desc" },
    select: ["id", "email", "name", "insertedAt"],
    page: { limit: 20, offset: page * 20 },
  });

  if (isLoading) return <div>Loading...</div>;

  if (error) {
    return (
      <div className="error">
        Error: {error.shape?.message || "Something went wrong"}
      </div>
    );
  }

  return (
    <div>
      <input
        type="text"
        placeholder="Search users..."
        value={search}
        onChange={(e) => setSearch(e.target.value)}
      />

      {data?.result.map((user) => (
        <div key={user.id} className="user-card">
          <h3>{user.name}</h3>
          <p>{user.email}</p>
          <small>{new Date(user.insertedAt).toLocaleDateString()}</small>
        </div>
      ))}

      <div className="pagination">
        <button disabled={page === 0} onClick={() => setPage((p) => p - 1)}>
          Previous
        </button>
        <span>Page {page + 1}</span>
        <button
          disabled={!data?.meta.hasMore}
          onClick={() => setPage((p) => p + 1)}
        >
          Next
        </button>
      </div>
    </div>
  );
}
```

### Mutations with Optimistic Updates

```tsx
// components/CreateUser.tsx
import { trpc } from "../lib/trpc";

function CreateUserForm() {
  const [formData, setFormData] = useState({
    email: "",
    password: "",
    name: "",
  });

  // Get query client for cache manipulation
  const queryClient = trpc.useContext();

  const createUser = trpc.accounts.user.create.useMutation({
    onMutate: async (newUser) => {
      // Cancel outgoing refetches
      await queryClient.accounts.user.read.cancel();

      // Snapshot previous value
      const previousUsers = queryClient.accounts.user.read.getData();

      // Optimistically update cache
      queryClient.accounts.user.read.setData(undefined, (old) => ({
        ...old,
        result: [
          ...(old?.result || []),
          {
            ...newUser,
            id: "temp-" + Date.now(), // Temporary ID
            insertedAt: new Date().toISOString(),
          },
        ],
      }));

      return { previousUsers };
    },

    onError: (err, newUser, context) => {
      // Revert cache on error
      if (context?.previousUsers) {
        queryClient.accounts.user.read.setData(
          undefined,
          context.previousUsers
        );
      }
    },

    onSettled: () => {
      // Refetch to ensure cache consistency
      queryClient.accounts.user.read.invalidate();
    },
  });

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    try {
      await createUser.mutateAsync(formData);
      setFormData({ email: "", password: "", name: "" });
      // Success handled by optimistic update
    } catch (error: any) {
      console.error("Failed to create user:", error.shape?.message);
    }
  };

  return (
    <form onSubmit={handleSubmit}>
      <input
        type="email"
        placeholder="Email"
        value={formData.email}
        onChange={(e) =>
          setFormData((prev) => ({ ...prev, email: e.target.value }))
        }
        required
      />
      <input
        type="password"
        placeholder="Password"
        value={formData.password}
        onChange={(e) =>
          setFormData((prev) => ({ ...prev, password: e.target.value }))
        }
        required
      />
      <input
        type="text"
        placeholder="Name"
        value={formData.name}
        onChange={(e) =>
          setFormData((prev) => ({ ...prev, name: e.target.value }))
        }
        required
      />
      <button type="submit" disabled={createUser.isLoading}>
        {createUser.isLoading ? "Creating..." : "Create User"}
      </button>
    </form>
  );
}
```

### Advanced Features

#### Real-time Subscriptions

```tsx
// components/NotificationList.tsx
import { trpc } from "../lib/trpc";

function NotificationList() {
  const [notifications, setNotifications] = useState([]);

  // Subscribe to new notifications
  trpc.notifications.notification.onCreate.useSubscription(undefined, {
    onData: (data) => {
      setNotifications((prev) => [data, ...prev]);
    },
  });

  return (
    <div className="notifications">
      {notifications.map((notification) => (
        <div key={notification.id} className="notification">
          {notification.message}
        </div>
      ))}
    </div>
  );
}
```

#### Form Validation with Zod

```tsx
// components/UserForm.tsx
import { z } from "zod";
import * as schemas from "../generated/trpc.zod";

const userSchema = schemas.AccountsUserCreateSchema.extend({
  confirmPassword: z.string(),
}).refine((data) => data.password === data.confirmPassword, {
  message: "Passwords don't match",
  path: ["confirmPassword"],
});

function UserForm() {
  const [formData, setFormData] = useState({});
  const [errors, setErrors] = useState({});

  const createUser = trpc.accounts.user.create.useMutation();

  const handleSubmit = async (e) => {
    e.preventDefault();

    try {
      const validatedData = userSchema.parse(formData);
      await createUser.mutateAsync(validatedData);
    } catch (error) {
      if (error.name === "ZodError") {
        const fieldErrors = {};
        error.errors.forEach((err) => {
          fieldErrors[err.path[0]] = err.message;
        });
        setErrors(fieldErrors);
      }
    }
  };

  return (
    <form onSubmit={handleSubmit}>
      <input
        type="email"
        placeholder="Email"
        value={formData.email || ""}
        onChange={(e) =>
          setFormData((prev) => ({ ...prev, email: e.target.value }))
        }
      />
      {errors.email && <span className="error">{errors.email}</span>}

      <button type="submit" disabled={createUser.isLoading}>
        {createUser.isLoading ? "Creating..." : "Create User"}
      </button>
    </form>
  );
}
```

## Framework-Specific Integrations

### Next.js Integration

```tsx
// pages/_app.tsx
import { withTRPC } from "@trpc/next";
import { createClient } from "../lib/trpc";

function MyApp({ Component, pageProps }) {
  return <Component {...pageProps} />;
}

export default withTRPC({
  config() {
    return {
      url: "/trpc",
    };
  },
  ssr: true,
})(MyApp);
```

### Vue.js Integration

```typescript
// composables/useTrpc.ts
import { computed } from "vue";
import { useQuery, useMutation } from "@tanstack/vue-query";

export function useUsers() {
  return useQuery({
    queryKey: ["users"],
    queryFn: () => client.accounts.user.read.query(),
  });
}
```

### Error Handling

```typescript
// Global error handler
trpc.createClient({
  onError: (error) => {
    if (error.data?.code === "UNAUTHORIZED") {
      window.location.href = "/login";
    }
  },
});
```

This guide provides comprehensive patterns for integrating AshRpc with modern frontend frameworks, including advanced features like optimistic updates, real-time subscriptions, and robust error handling.
