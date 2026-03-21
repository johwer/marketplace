---
name: presentation-workflows
description: Sales presentation and proposal workflows — customer pitches, ROI models, competitive analysis for Repo
---

## Proposal Workflow

### 1. Research the Prospect
- Industry (healthcare, manufacturing, logistics, public sector)
- Company size (employees, departments)
- Current service-a management approach (manual, competitor, none)
- Pain points mentioned in sales conversations

### 2. Tailor the Pitch
- Lead with their pain point, not our features
- Use industry-specific benchmarks (e.g., "manufacturing sector averages X% sick leave")
- Include relevant case studies from similar companies
- ROI calculation based on their company size

### 3. Build the Presentation
Structure:
1. **The Challenge** — Industry-specific service-a management pain points
2. **The Cost** — Hidden costs of unmanaged service-a (replacement, admin, productivity)
3. **Repo Solution** — Feature mapping to their specific needs
4. **ROI Model** — Projected savings based on their company size
5. **Implementation** — Timeline, onboarding, training
6. **References** — Similar companies using Repo

### 4. Data-Driven Arguments
Pull from Repo data platform:
- Average service-a reduction after Repo implementation
- Time saved on administration
- Case handling outcomes (% returned to work faster)
- Customer satisfaction metrics

## ROI Calculation Template

```
Annual employees:           [N]
Average salary (SEK):       [X]
Current service-a rate (%):   [Y]
Target reduction (%):       [Z]

Cost of service-a per day = Average salary / 220 work days × 1.5 (employer costs)
Total service-a days/year = N × 220 × Y%
Reduction with Repo = Total days × Z%
Annual savings = Reduction days × Cost per day
Repo cost/year = [license fee]
Net ROI = Savings - Cost
Payback period = Cost / (Savings / 12) months
```

## Competitive Differentiators

Key selling points vs competitors:
1. **Data & Insights** — Real-time service-e, benchmarking, trend analysis
2. **Proactive case management** — Automated triggers, not just reactive
3. **Multi-company support** — One platform for corporate groups
4. **Integration** — HR system integrations via Fuse
5. **Nordic focus** — Built for Swedish labor law, expanding to Nordics

## Tools for Presentations

For creating PowerPoint/slides from Claude Code:
- Write markdown → convert with pandoc: `pandoc slides.md -t pptx -o presentation.pptx`
- Use python-pptx for programmatic slide generation
- Or generate HTML slides with reveal.js for web presentations
