# Troubleshooting Guide

Common issues and solutions when working with BigQuery.

---

## Table of Contents
1. [Authentication Issues](#authentication-issues)
2. [Query Errors](#query-errors)
3. [Data Issues](#data-issues)
4. [Export/Import Problems](#exportimport-problems)
5. [Performance Issues](#performance-issues)
6. [Airbyte Sync Issues](#airbyte-sync-issues)

---

## Authentication Issues

### "Permission denied" Error

**Symptom:**
```
Error: Access Denied: Table hulken.ads_data.shopify_orders: User does not have permission
```

**Solutions:**

1. Re-authenticate with gcloud:
```bash
gcloud auth application-default login
```

2. Check project setting:
```bash
gcloud config set project hulken
```

3. Verify you have BigQuery access:
```bash
gcloud projects get-iam-policy hulken --filter="bindings.members:user:YOUR_EMAIL"
```

---

### "Project not found" Error

**Symptom:**
```
Error: Project hulken was not found
```

**Solutions:**

1. Set the correct project:
```bash
gcloud config set project hulken
```

2. List available projects:
```bash
gcloud projects list
```

3. Request access from project administrator if needed.

---

### Service Account Authentication

**For scripts/automation:**

1. Download service account key (contact admin)
2. Set environment variable:
```bash
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/hulken-service-account.json"
```

3. In Python:
```python
from google.cloud import bigquery
client = bigquery.Client(project='hulken')
```

---

## Query Errors

### "Division by zero" Error

**Symptom:**
```
Error: division by zero
```

**Solution:** Use SAFE_DIVIDE:
```sql
-- Instead of:
SELECT spend / clicks as cpc

-- Use:
SELECT SAFE_DIVIDE(spend, clicks) as cpc
```

---

### "Could not parse as DATE" Error

**Symptom:**
```
Error: Could not parse '2026-01-15 10:30:00' as DATE
```

**Solution:** Convert timestamp to date:
```sql
-- Use DATE() function
SELECT DATE(created_at) as order_date
FROM shopify_orders

-- Or EXTRACT
SELECT EXTRACT(DATE FROM created_at) as order_date
```

---

### "Unrecognized column" Error

**Symptom:**
```
Error: Unrecognized name: email
```

**Solutions:**

1. Check exact column names (case-sensitive):
```sql
SELECT column_name
FROM `hulken.ads_data.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'shopify_orders'
```

2. Use backticks for reserved words:
```sql
SELECT `name`, `date`
FROM table
```

---

### "Resources exceeded" Error

**Symptom:**
```
Error: Resources exceeded during query execution
```

**Solutions:**

1. Add date filters:
```sql
WHERE created_at >= '2026-01-01'
```

2. Limit results:
```sql
LIMIT 10000
```

3. Use partitioned columns:
```sql
WHERE _airbyte_extracted_at >= '2026-01-01'
```

4. Break into smaller queries

---

### JSON Extraction Errors

**Symptom:**
```
Error: Cannot access field metrics on a value with type STRING
```

**Solution:** Use correct JSON functions:
```sql
-- For JSON column
SELECT JSON_EXTRACT_SCALAR(metrics, '$.spend') as spend

-- For STRING containing JSON
SELECT JSON_EXTRACT_SCALAR(PARSE_JSON(metrics_string), '$.spend') as spend
```

---

## Data Issues

### Missing UTM Attribution

**Symptom:** Many orders have NULL utm_source

**Check attribution status:**
```sql
SELECT
  attribution_status,
  COUNT(*) as orders,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as pct
FROM `hulken.ads_data.shopify_utm`
GROUP BY 1
```

**Common causes:**
- Orders from POS/retail
- Direct navigation (no referrer)
- Privacy browsers blocking tracking
- Orders before tracking was implemented

---

### Duplicate Orders

**Check for duplicates:**
```sql
SELECT order_id, COUNT(*) as count
FROM `hulken.ads_data.shopify_utm`
GROUP BY 1
HAVING COUNT(*) > 1
```

**Fix:** Use DISTINCT or ROW_NUMBER:
```sql
WITH deduped AS (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY extracted_at DESC) as rn
  FROM `hulken.ads_data.shopify_utm`
)
SELECT * FROM deduped WHERE rn = 1
```

---

### Data Freshness Issues

**Check last update:**
```sql
SELECT
  'shopify_utm' as table_name,
  MAX(created_at) as latest_record
FROM `hulken.ads_data.shopify_utm`

UNION ALL

SELECT
  'shopify_live_orders',
  MAX(created_at)
FROM `hulken.ads_data.shopify_live_orders`
```

**If data is stale:**
1. Check Airbyte sync status
2. Check UTM extraction cron job
3. Contact data team

---

### Mismatched Row Counts

**Compare bulk vs live:**
```sql
SELECT
  (SELECT COUNT(*) FROM `hulken.ads_data.shopify_orders`) as bulk_orders,
  (SELECT COUNT(*) FROM `hulken.ads_data.shopify_live_orders`) as live_orders,
  (SELECT COUNT(*) FROM `hulken.ads_data.shopify_utm`) as utm_orders
```

**Note:** Differences are expected:
- `shopify_orders`: Historical bulk import
- `shopify_live_orders`: Airbyte real-time sync
- `shopify_utm`: Includes UTM extraction

---

## Export/Import Problems

### Large Export Timing Out

**Symptom:** Export hangs or times out

**Solutions:**

1. Export to Cloud Storage:
```bash
bq extract --destination_format=CSV \
  'hulken.ads_data.shopify_utm' \
  'gs://hulken-exports/shopify_utm_*.csv'
```

2. Add LIMIT for testing:
```sql
SELECT * FROM table LIMIT 1000
```

3. Filter data:
```sql
WHERE created_at >= '2026-01-01'
```

---

### CSV Encoding Issues

**Symptom:** Special characters appear as ???

**Solutions:**

1. Use UTF-8 encoding in Python:
```python
df.to_csv('output.csv', encoding='utf-8-sig', index=False)
```

2. Open in Excel with "Data > From Text" and select UTF-8

---

### Upload Schema Mismatch

**Symptom:** Upload fails due to schema

**Solutions:**

1. Use autodetect:
```python
job_config = bigquery.LoadJobConfig(
    autodetect=True,
    write_disposition='WRITE_TRUNCATE'
)
```

2. Specify schema explicitly:
```python
schema = [
    bigquery.SchemaField("order_id", "STRING"),
    bigquery.SchemaField("total_price", "FLOAT"),
]
job_config = bigquery.LoadJobConfig(schema=schema)
```

---

## Performance Issues

### Slow Queries

**Tips:**

1. Filter by partitioned column:
```sql
WHERE _airbyte_extracted_at >= '2026-01-01'
```

2. Select only needed columns:
```sql
SELECT order_id, total_price  -- Not SELECT *
```

3. Use approximation for large datasets:
```sql
SELECT APPROX_COUNT_DISTINCT(customer_id)
```

4. Check query execution details in BigQuery Console

---

### High Costs

**Monitor usage:**
```sql
SELECT
  table_id,
  ROUND(size_bytes / 1024 / 1024 / 1024, 2) as size_gb
FROM `hulken.ads_data.__TABLES__`
ORDER BY size_bytes DESC
```

**Tips:**
1. Always add WHERE clauses
2. Use LIMIT during development
3. Use dry_run to estimate costs:
```python
job_config = bigquery.QueryJobConfig(dry_run=True)
```

---

## Airbyte Sync Issues

### Check Sync Status

```sql
SELECT
  DATE(_airbyte_extracted_at) as sync_date,
  COUNT(*) as records
FROM `hulken.ads_data.shopify_live_orders`
GROUP BY 1
ORDER BY 1 DESC
LIMIT 7
```

### Missing Recent Data

**Possible causes:**
1. Airbyte sync paused
2. Connection error
3. API rate limiting

**Steps:**
1. Check Airbyte UI at http://localhost:8000
2. Review connection status
3. Check sync logs for errors

### Duplicate Records After Sync

**Airbyte uses deduplication, but check:**
```sql
SELECT _airbyte_raw_id, COUNT(*)
FROM `hulken.ads_data.shopify_live_orders`
GROUP BY 1
HAVING COUNT(*) > 1
```

---

## Quick Diagnostic Queries

### Overall Health Check
```sql
SELECT
  table_id,
  row_count,
  ROUND(size_bytes / 1024 / 1024, 2) as size_mb,
  TIMESTAMP_MILLIS(last_modified_time) as last_modified
FROM `hulken.ads_data.__TABLES__`
WHERE row_count > 0
ORDER BY last_modified_time DESC
LIMIT 20
```

### Data Pipeline Status
```sql
-- Check all key tables' freshness
SELECT 'shopify_utm' as source, MAX(created_at) as latest FROM `hulken.ads_data.shopify_utm`
UNION ALL
SELECT 'shopify_live_orders', MAX(created_at) FROM `hulken.ads_data.shopify_live_orders`
UNION ALL
SELECT 'facebook_ads_insights', MAX(date_start) FROM `hulken.ads_data.facebook_ads_insights`
UNION ALL
SELECT 'tiktokads_reports_daily', MAX(stat_time_day) FROM `hulken.ads_data.tiktokads_reports_daily`
```

---

## Contact & Escalation

For issues not covered here:

1. Check the RUNBOOK_VSCODE_BIGQUERY_SETUP.md
2. Review BigQuery documentation
3. Contact the data team

---

*Last updated: 2026-02-04*
