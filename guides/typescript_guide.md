# TypeScript Integration Guide

This guide covers AshRpc's TypeScript integration, including automatic type generation, Zod schema generation, and advanced TypeScript patterns for building type-safe applications.

> ⚠️ **EXPERIMENTAL WARNING**: AshRpc is still in early development and considered highly experimental. Breaking changes may occur frequently without notice. We strongly advise against using this package in production environments until it reaches a stable release (v1.0.0+).

## Type Generation

### Basic Type Generation

Generate TypeScript types for your tRPC router:

```bash
# Generate basic types
mix ash_rpc.gen --output=./frontend/generated

# Generate types with Zod schemas
mix ash_rpc.gen --output=./frontend/generated --zod

# Generate for specific domains
mix ash_rpc.gen --output=./frontend/generated --domains=MyApp.Accounts,MyApp.Billing
```

### Generated Files

The generator creates the following files:

- `trpc.d.ts` - TypeScript types for your tRPC router
- `trpc.zod.ts` - Zod schemas for client-side validation (optional)

### File Structure

```
frontend/generated/
├── trpc.d.ts          # Main tRPC router types
├── trpc.zod.ts        # Zod validation schemas
```

## Router Types

### AppRouter Type

The main `AppRouter` type provides full type safety for your tRPC client:

```typescript
import type { AppRouter } from "./generated/trpc";

// Create a fully typed client
const client = createTRPCClient<AppRouter>({
  links: [httpBatchLink({ url: "/trpc" })],
});

// All procedures are fully typed
await client.accounts.user.read.query({
  // TypeScript will enforce correct parameter types
});

await client.accounts.user.create.mutate({
  // TypeScript will validate input against your Ash resource
});
```

### Procedure Types

Each procedure gets its own TypeScript type:

```typescript
// Query procedures
type UserReadProcedure = AppRouter["accounts"]["user"]["read"];
// Equivalent to: TRPCQueryProcedure<{input: UserQueryInput; output: UserResponse}>

// Mutation procedures
type UserCreateProcedure = AppRouter["accounts"]["user"]["create"];
// Equivalent to: TRPCMutationProcedure<{input: UserCreateInput; output: UserResponse}>
```

## Query Input Types

### Filter Types

AshRpc generates comprehensive filter types based on your Ash resources:

```typescript
// Basic field filters
type UserFilters = {
  email?: AshFieldOps<string>;
  name?: AshFieldOps<string>;
  age?: AshFieldOps<number>;
  role?: AshFieldOps<"admin" | "user" | "moderator">;
  insertedAt?: AshFieldOps<Date>;
};

// Complex filter expressions
type UserFilter = Partial<UserFilters> & {
  and?: UserFilter[];
  or?: UserFilter[];
  not?: UserFilter;
};

// Usage
const users = await client.accounts.user.read.query({
  filter: {
    and: [
      { email: { like: "%@company.com" } },
      { role: { eq: "admin" } },
      {
        or: [{ age: { gte: 18 } }, { role: { eq: "admin" } }],
      },
    ],
  },
});
```

### Sort Types

Sorting is fully typed based on your resource attributes:

```typescript
// Sort by any attribute
type UserSort = Record<string, "asc" | "desc">;

// Usage
const users = await client.accounts.user.read.query({
  sort: {
    insertedAt: "desc",
    name: "asc",
  },
});

// Multiple sort fields
const users = await client.accounts.user.read.query({
  sort: [{ insertedAt: "desc" }, { name: "asc" }],
});
```

### Field Selection Types

Dynamic field selection with include/exclude semantics:

```typescript
// Include specific fields
const users = await client.accounts.user.read.query({
  select: ["id", "email", "name"],
});

// Exclude fields
const users = await client.accounts.user.read.query({
  select: ["-password", "-hashedPassword"],
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

### Pagination Types

Support for both offset and keyset pagination:

```typescript
// Offset pagination
type OffsetPagination = {
  type?: "offset";
  limit?: number;
  offset?: number;
  count?: boolean;
};

// Keyset pagination
type KeysetPagination = {
  type?: "keyset";
  limit?: number;
  after?: AshCursor;
  before?: AshCursor;
};

// Unified pagination type
type AshPage = OffsetPagination | KeysetPagination;

// Usage
const users = await client.accounts.user.read.query({
  page: {
    type: "offset",
    limit: 20,
    offset: 40,
    count: true,
  },
});
```

## Response Types

### Query Response Types

Different response types based on query characteristics:

```typescript
// Standard query response
type AshQueryResponse<T> = {
  result: T;
  meta: Record<string, unknown>;
};

// Paginated response
type AshPaginatedQueryResponse<T> = {
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
};

// Infinite query response (for keyset pagination)
type AshInfiniteQueryResponse<T> = {
  result: T;
  meta: {
    limit: number;
    nextCursor?: AshCursor;
    hasNextPage: boolean;
    type: "keyset";
  } & Record<string, unknown>;
};
```

### Mutation Response Types

Mutations return the created/updated resource plus metadata:

```typescript
type UserCreateResponse = {
  result: User;
  meta: {
    userId: string;
    createdAt: string;
  };
};

// Usage
const response = await client.accounts.user.create.mutate({
  email: "user@example.com",
  password: "password123",
});

console.log(response.result); // Full user object
console.log(response.meta.userId); // User ID from metadata
```

## Zod Schema Integration

### Generated Zod Schemas

When using `--zod` flag, AshRpc generates Zod schemas for validation:

```typescript
import * as schemas from "./generated/trpc.zod";

// Input validation schemas
const userCreateSchema = schemas.AccountsUserCreateSchema;
const userUpdateSchema = schemas.AccountsUserUpdateSchema;

// Usage
const validatedData = userCreateSchema.parse({
  email: "user@example.com",
  password: "password123",
});
```

### Custom Zod Schemas

Extend generated schemas with custom validation:

```typescript
import { z } from "zod";
import * as schemas from "./generated/trpc.zod";

// Extend user creation schema
const extendedUserCreateSchema = schemas.AccountsUserCreateSchema.extend({
  confirmPassword: z.string().min(8),
  acceptTerms: z.boolean().refine((val) => val === true, {
    message: "You must accept the terms and conditions",
  }),
}).refine((data) => data.password === data.confirmPassword, {
  message: "Passwords don't match",
  path: ["confirmPassword"],
});

// Usage in form
function UserRegistrationForm() {
  const [errors, setErrors] = useState({});

  const handleSubmit = async (formData) => {
    try {
      const validatedData = extendedUserCreateSchema.parse(formData);
      await createUser(validatedData);
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
}
```

### Runtime Type Validation

Use Zod schemas for runtime validation:

```typescript
// Validate API responses
const userResponseSchema = z.object({
  result: schemas.AccountsUserSchema,
  meta: z.object({
    userId: z.string(),
    createdAt: z.string(),
  }),
});

// Validate incoming data
function validateUserInput(input: unknown) {
  return schemas.AccountsUserCreateSchema.safeParse(input);
}

// Type inference from schemas
type UserCreateInput = z.infer<typeof schemas.AccountsUserCreateSchema>;
type User = z.infer<typeof schemas.AccountsUserSchema>;
```
