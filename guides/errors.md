# Errors

AshRpc translates exceptions into tRPC-compatible error envelopes. It provides a protocol for
adapting Ash exceptions into structured errors.

Highlights
- Consistent error shape with status_code, code, title, detail
- Optional pointer information for attribute/relationship errors
- Works for single and batch requests

