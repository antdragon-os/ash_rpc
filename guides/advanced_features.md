# Advanced Features Guide

This guide covers AshRpc's advanced features including request batching, real-time subscriptions, advanced querying, performance optimization, and enterprise-grade capabilities.

> ⚠️ **EXPERIMENTAL WARNING**: AshRpc is still in early development and considered highly experimental. Breaking changes may occur frequently without notice. We strongly advise against using this package in production environments until it reaches a stable release (v1.0.0+).

## Request Batching

### Automatic Batching

AshRpc supports automatic request batching to reduce network overhead:

```typescript
// Client-side batching with httpBatchLink
import { createTRPCClient, httpBatchLink } from "@trpc/client";

const client = createTRPCClient<AppRouter>({
  links: [
    httpBatchLink({
      url: "/trpc",
      // Batching is enabled by default
    }),
  ],
});

// Multiple queries are automatically batched
const [users, posts, comments] = await Promise.all([
  client.accounts.user.read.query({ limit: 10 }),
  client.blog.post.read.query({ limit: 10 }),
  client.blog.comment.read.query({ limit: 10 }),
]);
```

### Manual Batching

For more control, use manual batching:

```typescript
// Create a batch client
const batchClient = createTRPCClient<AppRouter>({
  links: [
    httpBatchLink({
      url: "/trpc?batch=1", // Explicit batch mode
    }),
  ],
});

// All requests in this context are batched
const results = await Promise.all([
  batchClient.accounts.user.read.query({ filter: { role: { eq: "admin" } } }),
  batchClient.accounts.user.read.query({ filter: { role: { eq: "user" } } }),
  batchClient.blog.post.read.query({ limit: 5 }),
]);
```

### Batch Size Optimization

Configure batch size limits:

```elixir
# Router configuration
defmodule MyAppWeb.TrpcRouter do
  use AshRpc.Router,
    domains: [MyApp.Accounts],
    batch_max_size: 50,  # Maximum requests per batch
    batch_timeout: 100   # Milliseconds to wait for batch completion
end
```

## Real-Time Subscriptions

### Phoenix Channel Subscriptions

AshRpc integrates with Phoenix PubSub for real-time updates:

```elixir
# Backend: Enable subscriptions on resource
defmodule MyApp.Blog.Post do
  use Ash.Resource, extensions: [AshRpc]

  ash_rpc do
    expose [:read, :create, :update]
    # Enable real-time broadcasting
    subscribe [:create, :update, :destroy]
  end
end

# Router configuration
defmodule MyAppWeb.TrpcRouter do
  use AshRpc.Router,
    domains: [MyApp.Blog],
    # Configure PubSub
    pubsub: MyApp.PubSub,
    # Subscription topics
    subscription_topics: %{
      "blog:post" => ["create", "update", "destroy"]
    }
end
```

### Frontend Subscription Client

Subscribe to real-time updates:

```typescript
// Subscription client setup
import { createTRPCSubscriptionClient } from "@trpc/client";

const subscriptionClient = createTRPCSubscriptionClient({
  url: "/trpc",
  connectionParams: () => ({
    Authorization: `Bearer ${token}`,
  }),
});

// Subscribe to post changes
const subscription = client.blog.post.onCreate.subscribe(undefined, {
  onData: (data) => {
    console.log("New post created:", data);
    // Update UI with new post
    queryClient.setQueryData(["blog", "post"], (old) => ({
      ...old,
      result: [data, ...(old?.result || [])],
    }));
  },
  onError: (error) => {
    console.error("Subscription error:", error);
  },
});

// Clean up subscription
subscription.unsubscribe();
```

### Custom Subscription Topics

Create custom subscription topics:

```elixir
# Custom topic derivation
defmodule MyApp.TrpcSubscriptions do
  @behaviour AshRpc.Subscriptions

  @impl true
  def topic_for_action(resource, action, record) do
    case {resource, action.name} do
      {MyApp.Blog.Post, :create} ->
        "blog:posts:#{record.user_id}"

      {MyApp.Blog.Comment, :create} ->
        "blog:post:#{record.post_id}:comments"

      _ ->
        "#{resource |> Module.split() |> Enum.join(":")}:#{action.name}"
    end
  end

  @impl true
  def broadcast_changes(changes, pubsub) do
    Enum.each(changes, fn {topic, data} ->
      Phoenix.PubSub.broadcast(pubsub, topic, data)
    end)
  end
end

# Configure in router
defmodule MyAppWeb.TrpcRouter do
  use AshRpc.Router,
    domains: [MyApp.Blog],
    subscriptions: MyApp.TrpcSubscriptions
end
```

## Advanced Querying

### Complex Filtering

AshRpc supports complex filter expressions:

```typescript
// Boolean logic
const users = await client.accounts.user.read.query({
  filter: {
    and: [
      { email: { like: "%@company.com" } },
      {
        or: [{ role: { eq: "admin" } }, { role: { eq: "manager" } }],
      },
      { not: { isActive: { eq: false } } },
    ],
  },
});

// Nested relationships
const posts = await client.blog.post.read.query({
  filter: {
    author: {
      and: [{ name: { like: "John%" } }, { isActive: { eq: true } }],
    },
    comments: {
      content: { like: "%important%" },
    },
  },
});
```

### Dynamic Field Selection

Select specific fields with include/exclude semantics:

```typescript
// Include only specific fields
const users = await client.accounts.user.read.query({
  select: ["id", "email", "name"],
});

// Exclude sensitive fields
const publicUsers = await client.accounts.user.read.query({
  select: ["-password", "-hashedPassword", "-resetToken"],
});

// Nested field selection
const postsWithAuthors = await client.blog.post.read.query({
  select: [
    "id",
    "title",
    "content",
    { author: ["name", "email", "avatar"] },
    { comments: ["content", "author", "-insertedAt"] },
  ],
});

// Conditional field selection
const posts = await client.blog.post.read.query({
  select: [
    "id",
    "title",
    "content",
    // Include author only if published
    { author: { filter: { isActive: { eq: true } } } },
  ],
});
```

### Relationship Loading

Load related data with flexible options:

```typescript
// Basic relationship loading
const posts = await client.blog.post.read.query({
  load: ["author", "comments", "tags"],
});

// Conditional relationship loading
const posts = await client.blog.post.read.query({
  load: [
    { author: { filter: { isActive: { eq: true } } } },
    {
      comments: {
        sort: { insertedAt: "desc" },
        limit: 10,
        filter: { isApproved: { eq: true } },
      },
    },
  ],
});

// Nested relationship queries
const users = await client.accounts.user.read.query({
  load: [
    {
      posts: {
        load: ["comments", "tags"],
        sort: { publishedAt: "desc" },
        limit: 5,
      },
    },
  ],
});
```

### Advanced Sorting

Multi-field and nested sorting:

```typescript
// Multi-field sort
const users = await client.accounts.user.read.query({
  sort: [
    { role: "asc" }, // Admins first
    { name: "asc" }, // Then alphabetical
    { insertedAt: "desc" }, // Newest first
  ],
});

// Sort by relationship fields
const posts = await client.blog.post.read.query({
  sort: [
    { author: { name: "asc" } }, // Sort by author name
    { publishedAt: "desc" }, // Then by publish date
  ],
});

// Dynamic sort configuration
const sortConfig = [
  { field: "priority", direction: "desc" },
  { field: "dueDate", direction: "asc" },
  { field: "title", direction: "asc" },
];

const tasks = await client.tasks.task.read.query({
  sort: sortConfig,
});
```

## Pagination Strategies

### Offset Pagination

Traditional page-based pagination:

```typescript
const users = await client.accounts.user.read.query({
  page: {
    type: "offset",
    limit: 20,
    offset: 40,  // Skip first 40 records
    count: true  // Include total count
  }
});

// Response includes pagination metadata
{
  result: [...], // 20 users
  meta: {
    limit: 20,
    offset: 40,
    hasMore: true,
    hasPrevious: true,
    currentPage: 3,
    nextPage: 4,
    previousPage: 2,
    totalPages: 10,
    count: 200,  // Total records
    type: "offset"
  }
}
```

### Keyset Pagination

Cursor-based pagination for better performance:

```typescript
const users = await client.accounts.user.read.query({
  page: {
    type: "keyset",
    limit: 20,
    after: "cursor_value",  // Start after this cursor
  }
});

// Response with cursor for next page
{
  result: [...], // 20 users
  meta: {
    limit: 20,
    nextCursor: "next_cursor_value",
    hasNextPage: true,
    type: "keyset"
  }
}
```

### Infinite Queries

Perfect for infinite scrolling:

```typescript
// React Query infinite query
const { data, fetchNextPage, hasNextPage, isFetchingNextPage } =
  trpc.accounts.user.read.useInfiniteQuery(
    {
      sort: { insertedAt: "desc" },
      page: { limit: 20 },
    },
    {
      getNextPageParam: (lastPage) => lastPage.meta.nextCursor,
    }
  );

// Render with infinite scroll
<div className="user-list">
  {data?.pages.map((page, index) => (
    <React.Fragment key={index}>
      {page.result.map((user) => (
        <UserCard key={user.id} user={user} />
      ))}
    </React.Fragment>
  ))}

  {hasNextPage && (
    <button onClick={() => fetchNextPage()} disabled={isFetchingNextPage}>
      {isFetchingNextPage ? "Loading..." : "Load More"}
    </button>
  )}
</div>;
```

## Performance Optimization

### Query Optimization

Optimize database queries:

```elixir
# Resource with optimized actions
defmodule MyApp.Blog.Post do
  actions do
    read :read do
      # Optimize query performance
      prepare build(load: [:author, :tags])
      prepare filter(expr(not(is_nil(published_at))))
    end

    read :drafts do
      # Separate action for drafts
      prepare filter(expr(is_nil(published_at)))
      prepare build(load: [:author])
    end
  end

  ash_rpc do
    expose [:read, :drafts]
  end
end
```

### Caching Strategies

Implement intelligent caching:

```typescript
// Query with stale-while-revalidate
const { data } = trpc.blog.post.read.useQuery(
  { limit: 10 },
  {
    staleTime: 5 * 60 * 1000, // 5 minutes
    cacheTime: 10 * 60 * 1000, // 10 minutes
  }
);

// Background refetch
trpc.blog.post.read.useQuery(
  { limit: 10 },
  {
    refetchInterval: 60000, // Refetch every minute
    refetchIntervalInBackground: true,
  }
);
```

### Optimistic Updates

Provide instant UI feedback:

```typescript
const createPost = trpc.blog.post.create.useMutation({
  onMutate: async (newPost) => {
    // Cancel outgoing refetches
    await queryClient.cancelQueries(["blog", "post"]);

    // Snapshot previous value
    const previousPosts = queryClient.getQueryData(["blog", "post"]);

    // Optimistically update cache
    queryClient.setQueryData(["blog", "post"], (old) => ({
      ...old,
      result: [newPost, ...(old?.result || [])],
    }));

    return { previousPosts };
  },

  onError: (err, newPost, context) => {
    // Revert on error
    if (context?.previousPosts) {
      queryClient.setQueryData(["blog", "post"], context.previousPosts);
    }
  },

  onSettled: () => {
    // Refetch to ensure consistency
    queryClient.invalidateQueries(["blog", "post"]);
  },
});
```

## File Uploads

### Direct Uploads

Handle file uploads efficiently:

```elixir
# Resource with file upload action
defmodule MyApp.Accounts.User do
  actions do
    action :upload_avatar do
      argument :filename, :string, allow_nil?: false
      argument :content_type, :string, allow_nil?: false

      run fn input, _ctx ->
        # Generate upload URL
        upload_url = generate_upload_url(input.filename, input.content_type)
        file_key = generate_file_key(input.filename)

        {:ok, %{upload_url: upload_url, file_key: file_key}}
      end
    end

    action :confirm_avatar_upload do
      argument :file_key, :string, allow_nil?: false

      change set_attribute(:avatar_key, arg(:file_key))
    end
  end

  ash_rpc do
    expose [:upload_avatar, :confirm_avatar_upload]
  end
end
```

```typescript
// Frontend upload handling
function AvatarUpload({ userId }: { userId: string }) {
  const [uploading, setUploading] = useState(false);

  const uploadAvatar = trpc.accounts.user.uploadAvatar.useMutation();
  const confirmUpload = trpc.accounts.user.confirmAvatarUpload.useMutation();

  const handleFileSelect = async (file: File) => {
    setUploading(true);

    try {
      // Get upload URL
      const { uploadUrl, fileKey } = await uploadAvatar.mutateAsync({
        filename: file.name,
        contentType: file.type,
      });

      // Upload file directly to storage
      await fetch(uploadUrl, {
        method: "PUT",
        body: file,
        headers: {
          "Content-Type": file.type,
        },
      });

      // Confirm upload
      await confirmUpload.mutateAsync({
        userId,
        fileKey,
      });

      // Update UI
      queryClient.invalidateQueries(["accounts", "user"]);
    } catch (error) {
      console.error("Upload failed:", error);
    } finally {
      setUploading(false);
    }
  };

  return (
    <div>
      <input
        type="file"
        accept="image/*"
        onChange={(e) => {
          const file = e.target.files?.[0];
          if (file) handleFileSelect(file);
        }}
        disabled={uploading}
      />
      {uploading && <div>Uploading...</div>}
    </div>
  );
}
```

## Advanced Error Handling

### Structured Error Responses

AshRpc provides detailed error information:

```typescript
try {
  await client.accounts.user.create.mutate(userData);
} catch (error: any) {
  // High-level error message
  console.log("Error:", error.shape?.message);

  // Detailed error breakdown
  error.shape?.data?.details?.forEach((detail) => {
    console.log("Field:", detail.pointer);
    console.log("Code:", detail.code);
    console.log("Message:", detail.message);
  });
}
```

### Error Recovery

Implement automatic error recovery:

```typescript
const createUser = trpc.accounts.user.create.useMutation({
  retry: (failureCount, error: any) => {
    // Don't retry validation errors
    if (error?.data?.code === "VALIDATION_ERROR") {
      return false;
    }

    // Retry network errors
    if (error?.data?.code === "INTERNAL_SERVER_ERROR") {
      return failureCount < 3;
    }

    return false;
  },

  onError: (error, variables, context) => {
    // Log detailed error information
    console.error("Mutation failed:", {
      procedure: "accounts.user.create",
      input: variables,
      error: error.shape,
      attempt: context?.failureCount || 1,
    });
  },
});
```

## Monitoring and Analytics

### Request Tracking

Track API usage and performance:

```elixir
# Custom middleware for analytics
defmodule MyApp.TrpcAnalytics do
  @behaviour AshRpc.Execution.Middleware

  @impl true
  def before_request(ctx) do
    # Record request start time
    ctx |> Map.put(:start_time, System.monotonic_time(:microsecond))
  end

  @impl true
  def after_request(ctx, result) do
    duration = System.monotonic_time(:microsecond) - ctx.start_time

    # Send metrics to monitoring system
    MyApp.Metrics.record_request(%{
      procedure: ctx.procedure,
      duration: duration,
      status: result.status,
      actor: ctx.actor && ctx.actor.id,
      user_agent: get_user_agent(ctx.conn)
    })

    result
  end
end

# Add to router
defmodule MyAppWeb.TrpcRouter do
  use AshRpc.Router,
    domains: [MyApp.Accounts],
    after: [MyApp.TrpcAnalytics]
end
```

### Performance Monitoring

Monitor query performance:

```typescript
// Client-side performance tracking
const client = createTRPCClient<AppRouter>({
  links: [
    httpBatchLink({
      url: "/trpc",
      fetch: async (url, options) => {
        const start = performance.now();
        const response = await fetch(url, options);
        const duration = performance.now() - start;

        // Track request performance
        if (typeof window !== "undefined" && (window as any).gtag) {
          (window as any).gtag("event", "api_request", {
            event_category: "api",
            event_label: url,
            value: Math.round(duration),
          });
        }

        return response;
      },
    }),
  ],
});
```

## Security Features

### Input Validation

Comprehensive input validation:

```elixir
# Resource with validation rules
defmodule MyApp.Accounts.User do
  attributes do
    attribute :email, :string do
      constraints [format: ~r/@/]
      allow_nil? false
    end

    attribute :password, :string do
      constraints [min_length: 8, max_length: 128]
      allow_nil? false
    end

    attribute :age, :integer do
      constraints [min: 13, max: 120]
    end
  end

  # Custom validations
  validations do
    validate {MyApp.Validations.StrongPassword, attribute: :password}
    validate {MyApp.Validations.UniqueEmail, attribute: :email}
  end
end
```

### Rate Limiting

Implement rate limiting:

```elixir
# Plug for rate limiting
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
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    user_id = conn.assigns[:current_user] && conn.assigns[:current_user].id
    "#{ip}:#{user_id || "anonymous"}"
  end
end

# Add to router pipeline
pipeline :ash_rpc do
  plug :accepts, ["json"]
  plug MyApp.Plugs.RateLimit, max_requests: 1000, window_seconds: 60
  plug :retrieve_from_bearer
  plug :set_actor, :user
end
```

### Audit Logging

Log all data access:

```elixir
# Audit middleware
defmodule MyApp.TrpcAudit do
  @behaviour AshRpc.Execution.Middleware

  @impl true
  def before_request(ctx) do
    # Log access attempt
    Logger.info("API Access", %{
      procedure: ctx.procedure,
      actor: ctx.actor && ctx.actor.id,
      ip: get_ip(ctx.conn),
      user_agent: get_user_agent(ctx.conn),
      timestamp: DateTime.utc_now()
    })
    ctx
  end

  @impl true
  def after_request(ctx, result) do
    # Log access result
    Logger.info("API Result", %{
      procedure: ctx.procedure,
      status: result.status,
      actor: ctx.actor && ctx.actor.id,
      timestamp: DateTime.utc_now()
    })
    result
  end

  defp get_ip(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end

  defp get_user_agent(conn) do
    conn |> Plug.Conn.get_req_header("user-agent") |> List.first()
  end
end
```

## Enterprise Features

### Multi-Tenant Support

Handle multiple tenants:

```elixir
# Tenant-scoped router
defmodule MyAppWeb.TenantTrpcRouter do
  use AshRpc.Router,
    domains: [MyApp.Tenant],
    # Tenant context from connection
    create_context: &MyApp.TrpcContext.with_tenant/1
end

# Tenant context
defmodule MyApp.TrpcContext do
  def with_tenant(conn) do
    # Extract tenant from subdomain, header, or JWT
    tenant = get_tenant_from_request(conn)

    %{
      actor: conn.assigns[:current_user],
      tenant: tenant,
      # Other context...
    }
  end
end
```

### Data Export/Import

Bulk data operations:

```elixir
# Bulk operations
defmodule MyApp.BulkOperations do
  actions do
    action :export_users do
      argument :format, :atom, constraints: [one_of: [:csv, :json, :xlsx]]

      run fn input, _ctx ->
        users = MyApp.Accounts.User
                |> Ash.Query.filter(input[:filter] || %{})
                |> Ash.read!()

        case input.format do
          :csv -> generate_csv(users)
          :json -> generate_json(users)
          :xlsx -> generate_xlsx(users)
        end
      end
    end

    action :import_users do
      argument :data, :string
      argument :format, :atom, constraints: [one_of: [:csv, :json]]

      run fn input, _ctx ->
        users_data = parse_data(input.data, input.format)

        # Bulk insert with validation
        MyApp.Accounts.bulk_create_users(users_data)
      end
    end
  end

  ash_rpc do
    expose [:export_users, :import_users]
  end
end
```

### Advanced Search

Full-text search capabilities:

```elixir
# Search resource
defmodule MyApp.Search do
  actions do
    read :search do
      argument :query, :string, allow_nil?: false
      argument :type, :atom, constraints: [one_of: [:users, :posts, :all]]

      prepare build(search: arg(:query), type: arg(:type))
    end
  end

  ash_rpc do
    expose [:search]
  end
end
```

```typescript
// Frontend search component
function GlobalSearch() {
  const [query, setQuery] = useState("");
  const [type, setType] = useState<"users" | "posts" | "all">("all");

  const { data, isLoading } = trpc.search.search.useQuery(
    { query, type },
    {
      enabled: query.length > 2, // Only search after 3 characters
      debounce: 300, // Debounce search requests
    }
  );

  return (
    <div className="search">
      <input
        type="text"
        placeholder="Search..."
        value={query}
        onChange={(e) => setQuery(e.target.value)}
      />
      <select value={type} onChange={(e) => setType(e.target.value)}>
        <option value="all">All</option>
        <option value="users">Users</option>
        <option value="posts">Posts</option>
      </select>

      {isLoading && <div>Searching...</div>}

      <div className="results">
        {data?.result.map((result) => (
          <SearchResult key={result.id} item={result} />
        ))}
      </div>
    </div>
  );
}
```

This comprehensive advanced features guide covers all of AshRpc's enterprise-grade capabilities for building scalable, performant, and secure applications.
