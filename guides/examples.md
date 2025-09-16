# Examples Guide

This guide provides practical examples and common use cases for AshRpc, from simple CRUD operations to complex multi-tenant applications.

> ⚠️ **EXPERIMENTAL WARNING**: AshRpc is still in early development and considered highly experimental. Breaking changes may occur frequently without notice. We strongly advise against using this package in production environments until it reaches a stable release (v1.0.0+).

## Basic Examples

### Simple Blog Application

#### Backend Setup

```elixir
# lib/my_app/accounts/user.ex
defmodule MyApp.Accounts.User do
  use Ash.Resource,
    extensions: [AshRpc],
    domain: MyApp.Accounts

  attributes do
    uuid_primary_key :id
    attribute :email, :string, allow_nil?: false
    attribute :name, :string, allow_nil?: false
    attribute :role, :atom, default: :user, constraints: [one_of: [:user, :admin]]
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    read :by_email do
      argument :email, :string, allow_nil?: false
      filter expr(email == ^arg(:email))
    end
  end

  ash_rpc do
    expose [:read, :create, :update, :destroy]

    query :by_email, :by_email do
      filterable false
    end
  end
end

# lib/my_app/blog/post.ex
defmodule MyApp.Blog.Post do
  use Ash.Resource,
    extensions: [AshRpc],
    domain: MyApp.Blog

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false
    attribute :content, :string, allow_nil?: false
    attribute :published, :boolean, default: false
    attribute :published_at, :datetime
  end

  relationships do
    belongs_to :author, MyApp.Accounts.User
    has_many :comments, MyApp.Blog.Comment
    many_to_many :tags, MyApp.Blog.Tag, through: MyApp.Blog.PostTag
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    create :publish do
      change set_attribute(:published, true)
      change set_attribute(:published_at, &DateTime.utc_now/0)
    end

    read :published do
      filter expr(published == true)
    end
  end

  ash_rpc do
    expose [:read, :create, :update, :destroy, :publish]

    query :read do
      filterable true
      sortable true
      selectable true
      paginatable true
      relationships [:author, :comments, :tags]
    end

    query :published, :published do
      filterable true
      sortable true
      selectable true
      paginatable true
      relationships [:author, :tags]
    end

    mutation :publish, :publish do
      metadata fn _subject, post, _ctx ->
        %{published_at: post.published_at}
      end
    end
  end
end

# lib/my_app/blog/comment.ex
defmodule MyApp.Blog.Comment do
  use Ash.Resource,
    extensions: [AshRpc],
    domain: MyApp.Blog

  attributes do
    uuid_primary_key :id
    attribute :content, :string, allow_nil?: false
    attribute :approved, :boolean, default: false
  end

  relationships do
    belongs_to :post, MyApp.Blog.Post
    belongs_to :author, MyApp.Accounts.User
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    update :approve do
      change set_attribute(:approved, true)
    end
  end

  ash_rpc do
    expose [:read, :create, :update, :destroy, :approve]

    mutation :approve, :approve do
      metadata fn _subject, comment, _ctx ->
        %{approved_at: DateTime.utc_now()}
      end
    end
  end
end

# lib/my_app_web/trpc_router.ex
defmodule MyAppWeb.TrpcRouter do
  use AshRpc.Router,
    domains: [MyApp.Accounts, MyApp.Blog],
    debug: Mix.env() == :dev
end
```

#### Frontend Implementation

```typescript
// lib/trpc.ts
import { createTRPCClient, httpBatchLink } from "@trpc/client";
import type { AppRouter } from "./generated/trpc";

export const client = createTRPCClient<AppRouter>({
  links: [httpBatchLink({ url: "/trpc" })],
});

// components/UserList.tsx
function UserList() {
  const [search, setSearch] = useState("");

  const { data, isLoading } = trpc.accounts.user.read.useQuery({
    filter: search ? { email: { like: `%${search}%` } } : undefined,
    select: ["id", "email", "name"],
    sort: { name: "asc" },
  });

  if (isLoading) return <div>Loading...</div>;

  return (
    <div>
      <input
        type="text"
        placeholder="Search users..."
        value={search}
        onChange={(e) => setSearch(e.target.value)}
      />
      {data?.result.map((user) => (
        <div key={user.id}>
          <h3>{user.name}</h3>
          <p>{user.email}</p>
        </div>
      ))}
    </div>
  );
}

// components/PostEditor.tsx
function PostEditor({ postId }: { postId?: string }) {
  const [formData, setFormData] = useState({
    title: "",
    content: "",
    published: false,
  });

  const createPost = trpc.blog.post.create.useMutation();
  const updatePost = trpc.blog.post.update.useMutation();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    try {
      if (postId) {
        await updatePost.mutateAsync({
          id: postId,
          ...formData,
        });
      } else {
        await createPost.mutateAsync(formData);
      }
    } catch (error) {
      console.error("Failed to save post:", error);
    }
  };

  return (
    <form onSubmit={handleSubmit}>
      <input
        type="text"
        placeholder="Post title"
        value={formData.title}
        onChange={(e) =>
          setFormData((prev) => ({ ...prev, title: e.target.value }))
        }
        required
      />
      <textarea
        placeholder="Post content"
        value={formData.content}
        onChange={(e) =>
          setFormData((prev) => ({ ...prev, content: e.target.value }))
        }
        required
      />
      <label>
        <input
          type="checkbox"
          checked={formData.published}
          onChange={(e) =>
            setFormData((prev) => ({ ...prev, published: e.target.checked }))
          }
        />
        Publish immediately
      </label>
      <button type="submit">{postId ? "Update" : "Create"} Post</button>
    </form>
  );
}

// components/PostList.tsx
function PostList() {
  const [page, setPage] = useState(0);
  const [filter, setFilter] = useState<"all" | "published" | "drafts">("all");

  const query = trpc.blog.post.read.useQuery({
    filter:
      filter === "published"
        ? { published: { eq: true } }
        : filter === "drafts"
        ? { published: { eq: false } }
        : undefined,
    sort: { insertedAt: "desc" },
    select: ["id", "title", "published", "insertedAt", { author: ["name"] }],
    page: { limit: 10, offset: page * 10 },
  });

  if (query.isLoading) return <div>Loading...</div>;

  return (
    <div>
      <div>
        <button onClick={() => setFilter("all")}>All</button>
        <button onClick={() => setFilter("published")}>Published</button>
        <button onClick={() => setFilter("drafts")}>Drafts</button>
      </div>

      {query.data?.result.map((post) => (
        <article key={post.id}>
          <h2>{post.title}</h2>
          <p>By {post.author?.name}</p>
          <small>
            {post.published ? "Published" : "Draft"} •
            {new Date(post.insertedAt).toLocaleDateString()}
          </small>
        </article>
      ))}

      <div>
        <button disabled={page === 0} onClick={() => setPage((p) => p - 1)}>
          Previous
        </button>
        <span>Page {page + 1}</span>
        <button
          disabled={!query.data?.meta.hasMore}
          onClick={() => setPage((p) => p + 1)}
        >
          Next
        </button>
      </div>
    </div>
  );
}
```

## Advanced Examples

### E-commerce Application

#### Product Management

```elixir
# lib/my_app/catalog/product.ex
defmodule MyApp.Catalog.Product do
  use Ash.Resource,
    extensions: [AshRpc],
    domain: MyApp.Catalog

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :description, :string
    attribute :price, :decimal, allow_nil?: false
    attribute :sku, :string, allow_nil?: false
    attribute :stock_quantity, :integer, default: 0
    attribute :is_active, :boolean, default: true
  end

  relationships do
    belongs_to :category, MyApp.Catalog.Category
    has_many :variants, MyApp.Catalog.ProductVariant
    many_to_many :tags, MyApp.Catalog.Tag, through: MyApp.Catalog.ProductTag
    has_many :reviews, MyApp.Catalog.Review
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    read :active do
      filter expr(is_active == true and stock_quantity > 0)
    end

    read :by_category do
      argument :category_id, :uuid, allow_nil?: false
      filter expr(category_id == ^arg(:category_id) and is_active == true)
    end

    read :search do
      argument :query, :string, allow_nil?: false
      argument :category_id, :uuid

      filter expr(
        (name |> ilike(^"%#{arg(:query)}%")) or
        (description |> ilike(^"%#{arg(:query)}%")) and
        (^arg(:category_id) == nil or category_id == ^arg(:category_id))
      )
    end

    update :adjust_stock do
      argument :quantity_change, :integer, allow_nil?: false

      change fn changeset, _ctx ->
        current_stock = Ash.Changeset.get_attribute(changeset, :stock_quantity) || 0
        new_stock = current_stock + changeset.arguments.quantity_change

        if new_stock < 0 do
          Ash.Changeset.add_error(changeset, :quantity_change, "Insufficient stock")
        else
          Ash.Changeset.set_attribute(changeset, :stock_quantity, new_stock)
        end
      end
    end
  end

  ash_rpc do
    expose [:read, :create, :update, :destroy, :adjust_stock]

    query :read do
      filterable true
      sortable true
      selectable true
      paginatable true
      relationships [:category, :variants, :tags, :reviews]
    end

    query :active, :active do
      filterable true
      sortable true
      selectable true
      paginatable true
      relationships [:category, :tags]
    end

    query :by_category, :by_category do
      filterable true
      sortable true
      selectable true
      paginatable true
      relationships [:variants, :tags]
    end

    query :search, :search do
      filterable false
      sortable true
      selectable true
      paginatable true
      relationships [:category, :tags]
    end

    mutation :adjust_stock, :adjust_stock do
      metadata fn _subject, product, _ctx ->
        %{new_stock: product.stock_quantity}
      end
    end
  end
end
```

#### Order Management

```elixir
# lib/my_app/orders/order.ex
defmodule MyApp.Orders.Order do
  use Ash.Resource,
    extensions: [AshRpc],
    domain: MyApp.Orders

  attributes do
    uuid_primary_key :id
    attribute :status, :atom,
      default: :pending,
      constraints: [one_of: [:pending, :confirmed, :shipped, :delivered, :cancelled]]
    attribute :total_amount, :decimal, allow_nil?: false
    attribute :order_number, :string, allow_nil?: false
  end

  relationships do
    belongs_to :customer, MyApp.Accounts.User
    has_many :items, MyApp.Orders.OrderItem
    belongs_to :shipping_address, MyApp.Accounts.Address
    belongs_to :billing_address, MyApp.Accounts.Address
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    create :place_order do
      argument :items, {:array, :map}, allow_nil?: false
      argument :shipping_address_id, :uuid, allow_nil?: false
      argument :billing_address_id, :uuid

      change fn changeset, ctx ->
        # Validate items
        # Calculate total
        # Create order items
        # Update inventory
        changeset
      end
    end

    update :cancel do
      change set_attribute(:status, :cancelled)
      # Add inventory back, send notifications, etc.
    end

    update :ship do
      argument :tracking_number, :string

      change set_attribute(:status, :shipped)
      change set_attribute(:tracking_number, arg(:tracking_number))
    end
  end

  ash_rpc do
    expose [:read, :create, :update, :destroy, :cancel, :ship]

    query :read do
      filterable true
      sortable true
      selectable true
      paginatable true
      relationships [:customer, :items, :shipping_address, :billing_address]
    end

    mutation :place_order, :place_order do
      metadata fn _subject, order, _ctx ->
        %{order_number: order.order_number, total: order.total_amount}
      end
    end

    mutation :cancel, :cancel do
      metadata fn _subject, order, _ctx ->
        %{cancelled_at: DateTime.utc_now()}
      end
    end

    mutation :ship, :ship do
      metadata fn _subject, order, _ctx ->
        %{shipped_at: DateTime.utc_now()}
      end
    end
  end
end
```

#### Frontend Shopping Cart

```typescript
// components/ProductList.tsx
function ProductList() {
  const [category, setCategory] = useState<string | null>(null);
  const [search, setSearch] = useState("");

  const query = trpc.catalog.product.active.useQuery({
    filter: category ? { category_id: { eq: category } } : undefined,
    sort: { name: "asc" },
    select: ["id", "name", "price", "stock_quantity", { category: ["name"] }],
    page: { limit: 20 },
  });

  if (query.isLoading) return <div>Loading products...</div>;

  return (
    <div>
      <div>
        <input
          type="text"
          placeholder="Search products..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <select
          value={category || ""}
          onChange={(e) => setCategory(e.target.value || null)}
        >
          <option value="">All Categories</option>
          {/* Category options */}
        </select>
      </div>

      <div className="product-grid">
        {query.data?.result.map((product) => (
          <ProductCard key={product.id} product={product} />
        ))}
      </div>
    </div>
  );
}

// components/ProductCard.tsx
function ProductCard({ product }: { product: Product }) {
  const addToCart = trpc.cart.add_item.useMutation();

  const handleAddToCart = async () => {
    try {
      await addToCart.mutateAsync({
        product_id: product.id,
        quantity: 1,
      });
    } catch (error) {
      console.error("Failed to add to cart:", error);
    }
  };

  return (
    <div className="product-card">
      <h3>{product.name}</h3>
      <p>{product.category?.name}</p>
      <p>${product.price}</p>
      <p>{product.stock_quantity} in stock</p>
      <button onClick={handleAddToCart} disabled={product.stock_quantity === 0}>
        Add to Cart
      </button>
    </div>
  );
}

// components/Checkout.tsx
function Checkout() {
  const [shippingAddress, setShippingAddress] = useState("");
  const [billingAddress, setBillingAddress] = useState("");

  const { data: cart } = trpc.cart.get.useQuery();
  const placeOrder = trpc.orders.order.place_order.useMutation();

  const handleCheckout = async () => {
    if (!cart?.items.length) return;

    try {
      const order = await placeOrder.mutateAsync({
        items: cart.items.map((item) => ({
          product_id: item.product_id,
          quantity: item.quantity,
        })),
        shipping_address_id: shippingAddress,
        billing_address_id: billingAddress || shippingAddress,
      });

      // Redirect to order confirmation
      window.location.href = `/orders/${order.result.id}`;
    } catch (error) {
      console.error("Failed to place order:", error);
    }
  };

  const total =
    cart?.items.reduce(
      (sum, item) => sum + item.product.price * item.quantity,
      0
    ) || 0;

  return (
    <div>
      <h2>Checkout</h2>

      <div>
        <h3>Items</h3>
        {cart?.items.map((item) => (
          <div key={item.id}>
            {item.product.name} x {item.quantity} = $
            {item.product.price * item.quantity}
          </div>
        ))}
        <div>Total: ${total}</div>
      </div>

      <div>
        <h3>Shipping Address</h3>
        <select
          value={shippingAddress}
          onChange={(e) => setShippingAddress(e.target.value)}
        >
          {/* Address options */}
        </select>
      </div>

      <button onClick={handleCheckout}>Place Order - ${total}</button>
    </div>
  );
}
```

### Real-time Dashboard

#### Backend with Subscriptions

```elixir
# lib/my_app/analytics/dashboard.ex
defmodule MyApp.Analytics.Dashboard do
  use Ash.Resource,
    extensions: [AshRpc],
    domain: MyApp.Analytics

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :metrics, :map, default: %{}
  end

  actions do
    read :real_time_metrics do
      argument :time_range, :string, default: "1h"

      run fn _input, _ctx ->
        # Fetch real-time metrics
        metrics = %{
          users_online: get_users_online(),
          orders_today: get_orders_today(),
          revenue_today: get_revenue_today(),
          top_products: get_top_products()
        }

        {:ok, metrics}
      end
    end

    read :historical_data do
      argument :metric, :string, allow_nil?: false
      argument :start_date, :date, allow_nil?: false
      argument :end_date, :date, allow_nil?: false

      run fn input, _ctx ->
        data = fetch_historical_data(
          input.metric,
          input.start_date,
          input.end_date
        )

        {:ok, data}
      end
    end
  end

  ash_rpc do
    expose [:real_time_metrics, :historical_data]

    query :real_time_metrics, :real_time_metrics do
      filterable false
      sortable false
      selectable false
      paginatable false
    end

    query :historical_data, :historical_data do
      filterable false
      sortable false
      selectable false
      paginatable false
    end
  end
end

# lib/my_app/notifications/notification.ex
defmodule MyApp.Notifications.Notification do
  use Ash.Resource,
    extensions: [AshRpc],
    domain: MyApp.Notifications

  attributes do
    uuid_primary_key :id
    attribute :type, :atom, constraints: [one_of: [:order, :user, :system]]
    attribute :title, :string, allow_nil?: false
    attribute :message, :string, allow_nil?: false
    attribute :data, :map, default: %{}
    attribute :read, :boolean, default: false
  end

  relationships do
    belongs_to :user, MyApp.Accounts.User
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    create :order_notification do
      argument :order_id, :uuid, allow_nil?: false

      change set_attribute(:type, :order)
      change set_attribute(:title, "New Order")
      change set_attribute(:message, "You have a new order")
      change set_attribute(:data, %{order_id: arg(:order_id)})
    end
  end

  ash_rpc do
    expose [:read, :create, :update, :destroy]
    subscribe [:create]  # Broadcast when notifications are created

    query :read do
      filterable true
      sortable true
      selectable true
      paginatable true
    end
  end
end
```

#### Frontend Dashboard

```typescript
// components/Dashboard.tsx
function Dashboard() {
  const [timeRange, setTimeRange] = useState("1h");

  // Real-time metrics
  const { data: metrics, refetch } =
    trpc.analytics.dashboard.real_time_metrics.useQuery(
      { time_range: timeRange },
      {
        refetchInterval: 30000, // Refetch every 30 seconds
      }
    );

  // Notifications subscription
  trpc.notifications.notification.onCreate.useSubscription(undefined, {
    onData: (notification) => {
      // Show notification toast
      toast.success(notification.title);

      // Refetch metrics if it's an order notification
      if (notification.type === "order") {
        refetch();
      }
    },
  });

  return (
    <div className="dashboard">
      <div className="metrics-grid">
        <MetricCard
          title="Users Online"
          value={metrics?.users_online || 0}
          icon="👥"
        />
        <MetricCard
          title="Orders Today"
          value={metrics?.orders_today || 0}
          icon="📦"
        />
        <MetricCard
          title="Revenue Today"
          value={`$${metrics?.revenue_today || 0}`}
          icon="💰"
        />
      </div>

      <div className="charts">
        <RevenueChart timeRange={timeRange} />
        <TopProductsChart timeRange={timeRange} />
      </div>

      <div className="recent-activity">
        <RecentOrders />
        <RecentUsers />
      </div>
    </div>
  );
}

// components/MetricCard.tsx
function MetricCard({
  title,
  value,
  icon,
}: {
  title: string;
  value: string | number;
  icon: string;
}) {
  return (
    <div className="metric-card">
      <div className="icon">{icon}</div>
      <div className="value">{value}</div>
      <div className="title">{title}</div>
    </div>
  );
}

// components/RevenueChart.tsx
function RevenueChart({ timeRange }: { timeRange: string }) {
  const { data } = trpc.analytics.dashboard.historical_data.useQuery({
    metric: "revenue",
    start_date: getStartDate(timeRange),
    end_date: new Date().toISOString().split("T")[0],
  });

  // Render chart with data
  return (
    <div className="chart">
      <h3>Revenue Trend</h3>
      {/* Chart component */}
    </div>
  );
}
```

### Multi-tenant Application

#### Tenant-scoped Resources

```elixir
# lib/my_app/tenants/tenant.ex
defmodule MyApp.Tenants.Tenant do
  use Ash.Resource,
    extensions: [AshRpc],
    domain: MyApp.Tenants

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :slug, :string, allow_nil?: false
  end

  actions do
    defaults [:read, :create, :update, :destroy]
  end

  ash_rpc do
    expose [:read, :create, :update, :destroy]
  end
end

# lib/my_app/teams/team.ex
defmodule MyApp.Teams.Team do
  use Ash.Resource,
    extensions: [AshRpc],
    domain: MyApp.Teams

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :description, :string
  end

  relationships do
    belongs_to :tenant, MyApp.Tenants.Tenant
    has_many :members, MyApp.Teams.TeamMember
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    read :by_tenant do
      argument :tenant_id, :uuid, allow_nil?: false
      filter expr(tenant_id == ^arg(:tenant_id))
    end
  end

  ash_rpc do
    expose [:read, :create, :update, :destroy]

    query :by_tenant, :by_tenant do
      filterable true
      sortable true
      selectable true
      paginatable true
      relationships [:members]
    end
  end
end

# lib/my_app/projects/project.ex
defmodule MyApp.Projects.Project do
  use Ash.Resource,
    extensions: [AshRpc],
    domain: MyApp.Projects

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :description, :string
    attribute :status, :atom,
      default: :active,
      constraints: [one_of: [:active, :archived, :completed]]
  end

  relationships do
    belongs_to :tenant, MyApp.Tenants.Tenant
    belongs_to :team, MyApp.Teams.Team
    has_many :tasks, MyApp.Projects.Task
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    read :by_tenant do
      argument :tenant_id, :uuid, allow_nil?: false
      filter expr(tenant_id == ^arg(:tenant_id))
    end

    read :by_team do
      argument :team_id, :uuid, allow_nil?: false
      filter expr(team_id == ^arg(:team_id))
    end
  end

  ash_rpc do
    expose [:read, :create, :update, :destroy]

    query :by_tenant, :by_tenant do
      filterable true
      sortable true
      selectable true
      paginatable true
      relationships [:team, :tasks]
    end

    query :by_team, :by_team do
      filterable true
      sortable true
      selectable true
      paginatable true
      relationships [:tenant, :tasks]
    end
  end
end
```

#### Tenant Context and Middleware

```elixir
# lib/my_app/trpc_context.ex
defmodule MyApp.TrpcContext do
  def create(%Plug.Conn{} = conn) do
    tenant = get_tenant_from_request(conn)

    %{
      actor: conn.assigns[:current_user],
      tenant: tenant,
      request_id: Logger.metadata()[:request_id],
    }
  end

  defp get_tenant_from_request(conn) do
    # Extract tenant from subdomain, header, or JWT
    subdomain = get_subdomain(conn.host)
    header_tenant = Plug.Conn.get_req_header(conn, "x-tenant-id") |> List.first()
    jwt_tenant = get_tenant_from_jwt(conn)

    subdomain || header_tenant || jwt_tenant
  end

  defp get_subdomain(host) do
    case String.split(host, ".") do
      [subdomain, "myapp.com" | _] -> subdomain
      _ -> nil
    end
  end

  defp get_tenant_from_jwt(conn) do
    # Extract tenant from JWT token
    with ["Bearer " <> token] <- Plug.Conn.get_req_header(conn, "authorization"),
         {:ok, claims} <- MyApp.Auth.verify_token(token) do
      claims["tenant_id"]
    else
      _ -> nil
    end
  end
end

# lib/my_app/middleware/tenant_middleware.ex
defmodule MyApp.Middleware.TenantMiddleware do
  @behaviour AshRpc.Execution.Middleware

  @impl true
  def before_request(ctx) do
    tenant_id = ctx.tenant

    if is_nil(tenant_id) do
      raise AshRpc.Error.Error.to_trpc_error(
        %Ash.Error.Invalid{errors: [message: "Tenant required"]}
      )
    end

    # Add tenant filter to all queries
    ctx
    |> Map.put(:tenant_filter, %{tenant_id: tenant_id})
    |> Map.put(:tenant_id, tenant_id)
  end

  @impl true
  def after_request(ctx, result) do
    # Ensure all created records have tenant_id set
    case result do
      {:ok, %{result: record}} when is_map(record) ->
        if Map.has_key?(record, :tenant_id) and is_nil(record.tenant_id) do
          # This shouldn't happen if resources are configured correctly
          Logger.warning("Record created without tenant_id", %{record: record})
        end

      _ ->
        :ok
    end

    result
  end
end

# lib/my_app_web/trpc_router.ex
defmodule MyAppWeb.TrpcRouter do
  use AshRpc.Router,
    domains: [MyApp.Tenants, MyApp.Teams, MyApp.Projects],
    create_context: &MyApp.TrpcContext.create/1,
    middlewares: [MyApp.Middleware.TenantMiddleware]
end
```

#### Frontend Tenant Selection

```typescript
// contexts/TenantContext.tsx
import React, { createContext, useContext, useState, useEffect } from "react";

interface TenantContextType {
  currentTenant: Tenant | null;
  tenants: Tenant[];
  switchTenant: (tenantId: string) => void;
  isLoading: boolean;
}

const TenantContext = createContext<TenantContextType | null>(null);

export function TenantProvider({ children }: { children: ReactNode }) {
  const [currentTenant, setCurrentTenant] = useState<Tenant | null>(null);
  const [tenants, setTenants] = useState<Tenant[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  // Load available tenants
  useEffect(() => {
    trpc.tenants.tenant.read
      .query()
      .then(({ result }) => {
        setTenants(result);

        // Set current tenant from localStorage or first available
        const savedTenantId = localStorage.getItem("current_tenant");
        const tenant = savedTenantId
          ? result.find((t) => t.id === savedTenantId)
          : result[0];

        setCurrentTenant(tenant || null);
      })
      .finally(() => setIsLoading(false));
  }, []);

  const switchTenant = (tenantId: string) => {
    const tenant = tenants.find((t) => t.id === tenantId);
    if (tenant) {
      setCurrentTenant(tenant);
      localStorage.setItem("current_tenant", tenantId);

      // Clear cached data when switching tenants
      queryClient.clear();
    }
  };

  return (
    <TenantContext.Provider
      value={{
        currentTenant,
        tenants,
        switchTenant,
        isLoading,
      }}
    >
      {children}
    </TenantContext.Provider>
  );
}

export function useTenant() {
  const context = useContext(TenantContext);
  if (!context) {
    throw new Error("useTenant must be used within TenantProvider");
  }
  return context;
}

// lib/trpc.ts
export function createClient(token?: string, tenantId?: string) {
  return createTRPCClient<AppRouter>({
    links: [
      httpBatchLink({
        url: "/trpc",
        headers: {
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
          ...(tenantId ? { "x-tenant-id": tenantId } : {}),
        },
      }),
    ],
  });
}

// components/TenantSwitcher.tsx
function TenantSwitcher() {
  const { currentTenant, tenants, switchTenant } = useTenant();

  return (
    <select
      value={currentTenant?.id || ""}
      onChange={(e) => switchTenant(e.target.value)}
    >
      {tenants.map((tenant) => (
        <option key={tenant.id} value={tenant.id}>
          {tenant.name}
        </option>
      ))}
    </select>
  );
}

// components/ProjectsList.tsx
function ProjectsList() {
  const { currentTenant } = useTenant();

  const { data, isLoading } = trpc.projects.project.by_tenant.useQuery(
    { tenant_id: currentTenant?.id },
    { enabled: !!currentTenant }
  );

  if (isLoading) return <div>Loading projects...</div>;

  return (
    <div>
      <h2>Projects for {currentTenant?.name}</h2>
      {data?.result.map((project) => (
        <div key={project.id}>
          <h3>{project.name}</h3>
          <p>{project.description}</p>
          <small>Status: {project.status}</small>
        </div>
      ))}
    </div>
  );
}
```

These examples demonstrate the full range of AshRpc capabilities, from simple CRUD operations to complex multi-tenant applications with real-time features, advanced querying, and comprehensive error handling.
