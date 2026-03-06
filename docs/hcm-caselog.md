# ServiceB CaseLog — Event Rendering

## EditedValue structure (health_case_events.edited_values)

Correct JSONB example:
```json
[{
  "property_name": "StartDate",
  "value_type": "Date",
  "old_value": "2024-01-15T00:00:00.0000000Z",
  "new_value": "2024-02-01T00:00:00.0000000Z"
}]
```

### Valid property_name values (EditedValueProperty enum)
ServiceB: `Action`, `ActivityName`, `AutomaticEndDate`, `Comment`, `Description`, `DocumentTitle`, `EndDate`, `OngoingReason`, `PlannedDate`, `Reason`, `RecipientUserIds`, `ResponsibleName`, `ResponsibleUserId`, `StartDate`, `Status`, `Title`

### Valid value_type values (EditedValueType enum)
`String`, `Date` (may become `DateTime` after Docker rebuild — check running image), `Number`

## Translation key patterns

### Event sentences (Trans component)
`employeeCard_caseTab_healthCaseEvent_caseLog_{type}_{operation}`
- `type`: HealthCase, Activity, Note, File, Task, Comment, Document (use lowercase in sentence text)
- Interpolation: `{{name}}`, `{{oldvalue}}`, `{{newvalue}}`

### Property labels (EditedValuesList)
`employeeCard_caseTab_editedValueProperty_{propertyName}`
- e.g. `_StartDate` → "Start date", `_Status` → "Status", `_PlannedDate` → "Planned date"
- These need to be created in TranslationService for all property names

## formatEditedValue function (CaseLogItem.utils.tsx)
Formats values based on `valueType`:
- `"Date"` / `"DateTime"` → `getDateTimeDisplayValue(value, { includeTime: false })`
- `"Number"` → raw value
- `"String"` / default → `t(value)` — requires translation keys for every possible value

## Known issue: t(value) for String type
When `valueType` is `"String"`, `formatEditedValue` calls `t(value)` on the raw value (e.g. `t("Preliminary")`, `t("Active")`). This only works if those exact keys exist in TranslationService. This has been a recurring issue in the platform — other areas have solved it by creating dedicated translation setups rather than passing backend values through `t()`.

## Seed data for CaseLog testing
File: `scripts/database-init/seed-healthcase-data.sql`
- Gunner's ongoing HealthPromotion (`45f3fd0a`): 28 events covering all type+operation combos
- Mika's preliminary HealthCase (`de13d999`): 18 events
- Events use `NOW() - INTERVAL 'N days'` for chronological ordering
- See [seed-data.md](seed-data.md) for JSONB format rules
