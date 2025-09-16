# Generator

AshRpc ships with a generator that produces TypeScript declarations for your tRPC router and
optionally Zod schemas for inputs.

Basic usage:

```
mix ash_rpc.gen --output=./frontend/generated
```

Also generate Zod schemas:

```
mix ash_rpc.gen --output=./frontend/generated --zod
```

Options

- `--output` (required): Output directory for `trpc.d.ts` and `trpc.zod.ts`
- `--domains` (optional): Comma/space-separated domain modules; if omitted, we auto-detect from a module using `AshRpc.Router`

The generated `trpc.d.ts` contains procedure signatures for queries and mutations inferred from
your Ash resources, plus advanced types for filtering, sorting, selecting fields, pagination,
and nested loads.
