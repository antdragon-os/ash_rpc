# Changelog

## 0.1.0

- Initial extraction from sandbox into standalone `ashrpc` package
- Router, Controller, Executor, Procedure
- Error translation and protocol under AshRpc namespace
- Generator: `mix ash_rpc.gen` for TS types (+ optional Zod)
- Igniter installer: `mix ash_rpc.install` adds `:ash_rpc` pipeline and scoped forward, with
  optional AshAuthentication bearer hooks
- Expanded docs and guides, CI skeleton, and publish workflow
