---
name: configuration-service-json
description: Convert configuration key/value rows into the configuration service platformConfig JSON import shape. Use when a user asks for configuration-service JSON, platformConfig JSON, or an import payload with platform, environment, consumer, isLocal, valueKey, and value fields.
---

# Configuration Service JSON

Convert supplied configuration entries into this exact root shape:

```json
{
  "platformConfig": []
}
```

Each entry must contain these fields in this order:

```json
{
  "name": "<configuration key>",
  "platform": "DataPortal",
  "environment": "DEFAULT",
  "valueKey": "<value key>",
  "value": "<configuration value>"
}
```

## Conversion Rules

- Preserve the supplied `name`, `value`, `platform`, `environment`, `consumer`, `isLocal`, and `valueKey` exactly when provided.
- Default `platform` to `DataPortal` when omitted.
- Default `environment` to `DEFAULT` when omitted.
- Default `valueKey` to the exact `name` when omitted.
- Keep configuration values as strings, including numeric-looking values such as `1433`, `6379`, `true`, and `false`, unless the user explicitly provides a non-string value or requests a different type.
- Produce one object per configuration entry under `platformConfig`.
- Preserve the user's entry order.
- Do not rename keys from a legacy namespace or infer a `DataPortal:` prefix unless explicitly requested. The configuration service accepts the key supplied in `name`.
- If a value is secret and not supplied, use a clear placeholder such as `<production password>` rather than inventing or exposing a credential.
- If the user supplies a redacted secret, preserve the redaction or use a placeholder; never guess the original value.
- Return valid JSON without comments or trailing commas when the user asks for the payload itself.

## Environment Handling

If the user names an environment, apply it to every entry unless individual entries override it. Use the exact requested casing, commonly `DEFAULT` or `Production`.

If the user asks for both default and production entries, emit separate entries for each environment. Do not silently duplicate secrets across environments when the values differ or are unknown.

## Value-Key Handling

`valueKey` is not always identical to `name`. Some existing configuration records intentionally use a different value key. Preserve an explicitly supplied value key, including legacy or service-specific values such as `edge.db.edge_rw_protocol`.

Example input:

```text
name: edge.db.ergon_rw.protocol
environment: Production
value: msodbc
```

Output:

```json
{
  "platformConfig": [
    {
      "name": "edge.db.ergon_rw.protocol",
      "platform": "DataPortal",
      "environment": "Production",
      "valueKey": "edge.db.ergon_rw.protocol",
      "value": "msodbc"
    }
  ]
}
```

When the user gives only a key/value list and asks for the import shape, convert it directly using the defaults above. Ask a concise clarification only when the target environment or value is necessary and cannot be safely defaulted.
