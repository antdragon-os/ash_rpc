# Changelog

## 0.1.3

### Fixed Validation Error Messages

- **Fixed Generic Error Messages**: Validation errors now show specific messages (e.g., "Password must be between 8 and 100 characters") instead of generic "TodoApp" messages
- **Improved InvalidChanges Error Handling**: Better extraction of nested validation errors for clearer error reporting

## 0.1.2

### Enhanced Error Handling

- **Form Validation Errors**: Added structured `formErrors` field to error responses for better frontend handling
- **Frontend-Friendly Structure**: Form errors now available at `error.data.formErrors` with TypeScript type safety
- **Improved TypeScript Types**: Updated error shape types to include form validation error structure
- **Better Error Messages**: Generic "Validation failed" message when form errors present, clean field-specific messages otherwise

## 0.1.1

- Documentation updates and improvements

## 0.1.0

- Router, Controller, Executor, Procedure
- Error translation and protocol under AshRpc namespace
- Generator: `mix ash_rpc.codegen` for TS types (+ optional Zod)
- Igniter installer: `mix ash_rpc.install` adds `:ash_rpc` pipeline and scoped forward, with
  optional AshAuthentication bearer hooks
- Expanded docs and guides, CI skeleton, and publish workflow
