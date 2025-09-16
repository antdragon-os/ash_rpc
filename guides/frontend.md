# Frontend Integration (tRPC client)

This guide shows how to use the official tRPC client with AshRpc.

## Install tRPC client

```
npm i @trpc/client
```

For batching and fetch, also install (optional but recommended):

```
npm i @trpc/client @trpc/server zod
```

## Create client

Use the generated types from `mix ash_rpc.codegen`.

```ts
import { createTRPCClient, httpBatchLink } from "@trpc/client";
import type { AppRouter } from "./generated/trpc"; // generated trpc.d.ts

export function makeClient(token?: string) {
  return createTRPCClient<AppRouter>({
    links: [
      httpBatchLink({
        url: "/trpc",
        headers() {
          return token ? { Authorization: `Bearer ${token}` } : {};
        },
      }),
    ],
  });
}
```

## Query example

```ts
const client = makeClient();
// domain: accounts, resource: user, action: list (as in your DSL)
const users = await client.accounts.user.list.query({
  filter: { and: [{ email: { eq: "a@example.com" } }] },
  sort: { insertedAt: "desc" },
  select: ["id", "email"],
  page: { limit: 20, offset: 0 },
});
```

## Mutation example

```ts
const client = makeClient(myJwt);
const { result } = await client.accounts.user.register.mutate({
  email: "new@example.com",
  password: "supersecret",
});
```

## Error handling

AshRpc returns tRPC-compliant envelopes. Errors include a `data.details` array with compact error
items (message, code, optional pointer/field).

```ts
try {
  await client.accounts.user.register.mutate({});
} catch (e: any) {
  // e.shape?.message contains a high-level message
  // e.data?.details is an array of error details
}
```

## Zod schemas (optional)

If you invoked `mix ash_rpc.codegen --zod`, a `trpc.zod.ts` file is generated with composable input schemas
based on your resources and actions.

```ts
import { z } from "zod";
import * as schemas from "./generated/trpc.zod";

// Example: validate before sending
const Register = schemas.AccountsUserRegisterSchema; // name inferred from resource/action
Register.parse({ email: "x@y.com", password: "..." });
```

## Notes

- Batching is enabled by default via `httpBatchLink`
- Use bearer tokens for authentication; the router installer creates a `:ash_rpc` pipeline and optionally
  plugs `:retrieve_from_bearer` and `:set_actor, :user` when AshAuthentication is present
