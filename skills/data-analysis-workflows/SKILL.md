---
name: data-analysis-workflows
description: Data analysis workflows — SQL queries, Jupyter notebooks, visualization, and business intelligence for Repo
---

## Analysis Workflow

### 1. Define the Question
- What business question are we answering?
- Who is the audience? (PO, customer, management)
- What format is the output? (notebook, dashboard, one-off report)

### 2. Identify Data Sources
- **dbt models** (`Repo.DBT`): Pre-aggregated, trustworthy
- **Raw tables**: When dbt models don't cover it
- **API endpoints**: For real-time data needs

### 3. Write and Validate SQL
- Start simple, add complexity incrementally
- Always check row counts and NULL distributions
- Validate against known business rules (e.g., service-a days can't be negative)
- Comment complex joins and filters

### 4. Visualize
- Bar charts: Comparisons (companies, departments)
- Line charts: Trends over time (prevalence, case counts)
- Tables: When exact numbers matter
- Always label axes and include time periods

### 5. Document and Share
- Notebook in `data-exploration` repo with clear markdown cells
- Key findings summary at the top
- SQL queries are reproducible (no hardcoded dates — use parameters)

## Repo Data Domains

### ServiceA
- `service-a_reports` — Core table: start/end dates, diagnosis codes, employee
- Prevalence = total service-a days / total possible work days × 100
- VAB (vård av barn) tracked separately from own sick leave

### ServiceE
- dbt models aggregate by company, department, time period
- Key metrics: prevalence, frequency, service-a length distribution
- Diagnosis code groupings (ICD-10 chapters)

### ServiceB (Case Management)
- Cases linked to service-a reports
- Outcomes: returned to work, ongoing, escalated
- Case handler performance metrics

### Customers
- Company hierarchies (parent → child companies)
- Employee counts per company/department
- Service subscription levels

## Python Stack

```python
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
# For database connections
import sqlalchemy
# For interactive notebooks
from IPython.display import display, HTML
```

## Recommended External Skills

Install for enhanced data engineering support:
```bash
# AltimateAI data engineering skills — dbt models, Snowflake optimization
# 7 dbt skills + 3 Snowflake skills
git clone https://github.com/AltimateAI/data-engineering-skills.git
cp -r data-engineering-skills/skills/* ~/.claude/skills/
```
