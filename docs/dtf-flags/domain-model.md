# DTF: Domain model change proposal (diagram styling and template)

Read when an agent is drawing the Mermaid diagrams for a domain model change (Domain Model Changes, step 3).

**Mermaid diagram styling rules — MUST follow:**

- All styled nodes must include explicit `color` for text readability
- Light backgrounds (`#c8e6c9`, `#fff9c4`, `#ffcdd2`, `#e3f2fd`, `#e8eaf6`, `#fff3e0`) use **black text**: `color:#000`
- Dark backgrounds (`#1976d2`, `#5c6bc0`, `#e65100`, `#4caf50`, `#f44336`, `#f9a825`) use **white text**: `color:#fff`
- Color meanings:
  - Green (`fill:#c8e6c9,stroke:#4caf50,color:#000`) = recommended / strong / low risk
  - Yellow (`fill:#fff9c4,stroke:#f9a825,color:#000`) = moderate / pragmatic
  - Red (`fill:#ffcdd2,stroke:#f44336,color:#000`) = high risk / weak
  - Blue (`fill:#e3f2fd,stroke:#1976d2,color:#000`) = junction/link tables
  - Indigo (`fill:#e8eaf6,stroke:#5c6bc0,color:#000`) = existing/unchanged entities
  - Orange (`fill:#fff3e0,stroke:#e65100,color:#000`) = context/polymorphic tables
- Use **erDiagram** for entity relationships + **classDiagram** for .NET entity field detail (show both)
- Use **sequenceDiagram** for data flow (e.g., create → link → view)
- Use **flowchart** for decision overviews and comparison charts

**Example output format for domain model proposals:**

```
## Option A: [Name]
[Pros/cons bullets]

### Entity Relationships
\`\`\`mermaid
erDiagram
    ...
\`\`\`

### Class Model
\`\`\`mermaid
classDiagram
    ...
    style MainEntity fill:#fff9c4,stroke:#f9a825,stroke-width:2px,color:#000
\`\`\`

## Option B: [Name]
[Pros/cons bullets]

### Entity Relationships
\`\`\`mermaid
erDiagram
    ...
\`\`\`

### Class Model
\`\`\`mermaid
classDiagram
    ...
    style MainEntity fill:#c8e6c9,stroke:#4caf50,stroke-width:2px,color:#000
\`\`\`
```
