# TASK 03: Documentation & Setup for Analyst

## Objective
Organize all documentation into `doc_setup/` folder for the analyst to get started with BigQuery.

## Deliverables

### 1. Move/Create Files in doc_setup/

```
doc_setup/
├── RUNBOOK_VSCODE_BIGQUERY_SETUP.md    # Already created - move here
├── BIGQUERY_TABLES_REFERENCE.md         # Create - all tables documented
├── COMMON_QUERIES.md                    # Create - useful SQL queries
├── DATA_DICTIONARY.md                   # Create - all columns explained
├── EXPORT_IMPORT_GUIDE.md               # Create - CSV workflows
└── TROUBLESHOOTING.md                   # Create - common issues
```

### 2. BIGQUERY_TABLES_REFERENCE.md Content

```markdown
# BigQuery Tables Reference

## Project: hulken
## Dataset: ads_data

### Shopify Tables
| Table | Description | Rows | Key Columns |
|-------|-------------|------|-------------|
| shopify_orders | Historical orders (bulk import) | 585K | id, totalPrice, email_hash |
| shopify_live_orders | Airbyte synced orders | 18K | id, total_price, email_hash |
| shopify_live_customers | Airbyte synced customers | 10K | id, email_hash, total_spent |
| shopify_utm | UTM attribution data | 589K | order_id, first_utm_source |

### Ads Tables
| Table | Description | Rows | Key Columns |
|-------|-------------|------|-------------|
| facebook_ads_insights | Facebook ad metrics | 957K | campaign_id, spend, impressions |
| tiktokads_reports_daily | TikTok ad metrics | 38K | campaign_id, metrics (JSON) |

### GA4 Tables
| Dataset | Description |
|---------|-------------|
| analytics_334792038 | GA4 property 1 |
| analytics_454869667 | GA4 property 2 |
| analytics_454871405 | GA4 property 3 |
```

### 3. COMMON_QUERIES.md Content

```markdown
# Common BigQuery Queries

## Revenue by UTM Source
SELECT first_utm_source, SUM(total_price) as revenue
FROM shopify_utm
WHERE first_utm_source IS NOT NULL
GROUP BY 1 ORDER BY 2 DESC

## Facebook Campaign Performance
SELECT campaign_name, SUM(spend), SUM(impressions)
FROM facebook_ads_insights
GROUP BY 1 ORDER BY 2 DESC

## Customer Lifetime Value
SELECT email_hash, COUNT(*) orders, SUM(totalPrice) ltv
FROM shopify_orders
GROUP BY 1 ORDER BY 3 DESC
```

### 4. DATA_DICTIONARY.md Content

Document ALL columns with:
- Column name
- Data type
- Description
- Example value
- PII status (Safe/Hashed/Removed)

### 5. Acceptance Criteria
1. All docs in `doc_setup/` folder
2. Analyst can follow runbook independently
3. All tables documented
4. Common queries provided
5. No PII in examples

---
*Task created: 2026-02-04*
*Status: COMPLETED*
*Completed: 2026-02-04*

## Completion Notes

All deliverables completed:
1. Created `doc_setup/` folder structure
2. Copied `RUNBOOK_VSCODE_BIGQUERY_SETUP.md` to doc_setup/
3. Created `BIGQUERY_TABLES_REFERENCE.md` with 63 tables documented
4. Created `COMMON_QUERIES.md` with 25+ useful SQL queries
5. Created `DATA_DICTIONARY.md` with full column schemas and PII classification
6. Created `EXPORT_IMPORT_GUIDE.md` with CSV workflow documentation
7. Created `TROUBLESHOOTING.md` with common issues and solutions

Key findings from BigQuery:
- 63 total tables in hulken.ads_data
- Largest tables: facebook_ads_insights_age_and_gender (1.5M rows), tiktokads_audience_reports_by_province_daily (1M rows)
- Shopify data: 585K orders (bulk), 21K orders (live), 589K UTM records
- Facebook data: 159K ads_insights rows
- TikTok data: 28K ads_reports_daily rows
