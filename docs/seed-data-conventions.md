# Seed Data Conventions

## General

### Docker Image vs Source Code
The running Docker images may lag behind the source code (e.g. enum values, new columns). Always verify against the actual running API, not just source code, when writing seed data.

### How to verify JSONB seed data
1. Create a real record via the API to generate the data
2. Query the DB: `SELECT column FROM table WHERE ...`
3. Compare the actual JSONB format with your seed data

### Schema drift
Seed scripts can break when migrations add NOT NULL columns. Always check the current table schema (`\d tablename`) before inserting. Example: `customers` table gained `customer_number` (NOT NULL) and `activation_date`.

## .NET JSONB Serialization (shared across all services)

Defined in `shared/Repo.Shared.Common/Extensions/EntityFrameworkExtensions.cs`:

```csharp
PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower  // JSON property names only
Converters = { new EnumMemberJsonConverterFactory() }    // enum values: [EnumMember] value or C# name
```

This applies to ALL `HasJsonbConversion()` columns across all services. Rules:

| Aspect | Format | Example |
|--------|--------|---------|
| JSON property names | **snake_case** | `"property_name"`, `"old_value"` |
| Enum values | **PascalCase** (C# name, unless `[EnumMember]` overrides) | `"StartDate"`, `"String"` |
| Date values | **ISO 8601 round-trip** | `"2024-01-15T00:00:00.0000000Z"` |

### Common mistakes
- PascalCase property names (`"PropertyName"`) — silently defaults to enum value 0 with null fields. No error, just wrong data.
- Short date format (`"2024-01-15"`) — backend round-trip format requires `T00:00:00.0000000Z`
