# Export & Import Guide

Complete guide for exporting data from BigQuery, cleaning it, and re-uploading.

---

## Table of Contents
1. [Export Methods](#export-methods)
2. [Data Cleaning Workflows](#data-cleaning-workflows)
3. [Import Methods](#import-methods)
4. [Best Practices](#best-practices)

---

## Export Methods

### Method 1: Python (Recommended)

Best for: Medium datasets, automated workflows

```python
from google.cloud import bigquery
import pandas as pd

client = bigquery.Client(project='hulken')

# Query and export
query = """
SELECT order_id, total_price, first_utm_source, created_at
FROM `hulken.ads_data.shopify_utm`
WHERE created_at >= '2026-01-01'
"""

df = client.query(query).to_dataframe()
df.to_csv('shopify_utm_export.csv', index=False)
print(f"Exported {len(df)} rows")
```

### Method 2: bq Command Line

Best for: Quick exports, scripting

```bash
# Export query results to CSV
bq query --use_legacy_sql=false --format=csv \
  "SELECT * FROM hulken.ads_data.shopify_utm LIMIT 1000" \
  > shopify_utm.csv

# Export entire table
bq query --use_legacy_sql=false --format=csv \
  "SELECT * FROM hulken.ads_data.shopify_orders WHERE createdAt >= '2026-01-01'" \
  > orders.csv
```

### Method 3: Cloud Storage (Large Datasets)

Best for: Large exports (>1GB)

```bash
# Export to GCS (supports wildcard for parallel export)
bq extract --destination_format=CSV \
  --compression=GZIP \
  'hulken.ads_data.shopify_utm' \
  'gs://hulken-exports/shopify_utm_*.csv.gz'

# Download from GCS
gsutil cp 'gs://hulken-exports/shopify_utm_*.csv.gz' .
```

### Method 4: BigQuery Console

Best for: Ad-hoc exports, small datasets

1. Go to https://console.cloud.google.com/bigquery
2. Run your query
3. Click **SAVE RESULTS** > **CSV (local file)**

---

## Data Cleaning Workflows

### Basic Cleaning Template

```python
import pandas as pd

# Read exported data
df = pd.read_csv('shopify_utm_export.csv')

# 1. Remove duplicates
print(f"Before dedup: {len(df)}")
df = df.drop_duplicates(subset=['order_id'])
print(f"After dedup: {len(df)}")

# 2. Handle missing values
df['first_utm_source'] = df['first_utm_source'].fillna('unknown')
df['first_utm_medium'] = df['first_utm_medium'].fillna('unknown')

# 3. Normalize text
df['first_utm_source'] = df['first_utm_source'].str.lower().str.strip()
df['first_utm_medium'] = df['first_utm_medium'].str.lower().str.strip()

# 4. Filter invalid rows
df = df[df['total_price'] > 0]

# 5. Convert data types
df['created_at'] = pd.to_datetime(df['created_at'])
df['total_price'] = df['total_price'].astype(float)

# 6. Add calculated columns
df['month'] = df['created_at'].dt.to_period('M').astype(str)

# Save cleaned data
df.to_csv('shopify_utm_cleaned.csv', index=False)
print(f"Saved {len(df)} cleaned rows")
```

### UTM Cleaning Example

```python
import pandas as pd

df = pd.read_csv('utm_export.csv')

# Standardize UTM sources
source_mapping = {
    'fb': 'facebook',
    'ig': 'instagram',
    'insta': 'instagram',
    'gg': 'google',
    'goog': 'google',
    'tt': 'tiktok',
    'tik': 'tiktok'
}

df['first_utm_source'] = df['first_utm_source'].str.lower().replace(source_mapping)

# Standardize UTM mediums
medium_mapping = {
    'ppc': 'cpc',
    'pay': 'paid',
    'social': 'paid_social'
}

df['first_utm_medium'] = df['first_utm_medium'].str.lower().replace(medium_mapping)

# Create channel grouping
def get_channel(row):
    source = row['first_utm_source'] or ''
    medium = row['first_utm_medium'] or ''

    if source in ['facebook', 'instagram', 'tiktok']:
        return 'Paid Social'
    elif source == 'google' and medium == 'cpc':
        return 'Paid Search'
    elif source == 'google' and medium == 'organic':
        return 'Organic Search'
    elif medium == 'email':
        return 'Email'
    else:
        return 'Other'

df['channel'] = df.apply(get_channel, axis=1)

df.to_csv('utm_cleaned.csv', index=False)
```

### Remove PII Before Export

```python
# Always exclude PII columns
safe_columns = [
    'order_id', 'total_price', 'created_at',
    'first_utm_source', 'first_utm_medium', 'first_utm_campaign',
    'customer_order_index', 'days_to_conversion'
]

df_safe = df[safe_columns]
df_safe.to_csv('export_no_pii.csv', index=False)
```

---

## Import Methods

### Method 1: Python (Recommended)

```python
from google.cloud import bigquery
import pandas as pd

client = bigquery.Client(project='hulken')

# Read cleaned CSV
df = pd.read_csv('shopify_utm_cleaned.csv')

# Define destination
table_id = 'hulken.ads_data.shopify_utm_cleaned'

# Configure upload
job_config = bigquery.LoadJobConfig(
    write_disposition='WRITE_TRUNCATE',  # Replace table
    autodetect=True
)

# Alternative: Append to existing
# job_config = bigquery.LoadJobConfig(
#     write_disposition='WRITE_APPEND',
#     autodetect=True
# )

# Upload
job = client.load_table_from_dataframe(df, table_id, job_config=job_config)
job.result()  # Wait for completion

print(f"Uploaded {len(df)} rows to {table_id}")
```

### Method 2: bq Command Line

```bash
# Upload with auto-detect schema
bq load --autodetect --replace \
  hulken.ads_data.shopify_utm_cleaned \
  shopify_utm_cleaned.csv

# Upload with explicit schema
bq load --replace \
  hulken.ads_data.my_table \
  data.csv \
  order_id:STRING,total_price:FLOAT,created_at:TIMESTAMP
```

### Method 3: From Cloud Storage

```bash
# Upload to GCS first
gsutil cp cleaned_data.csv gs://hulken-exports/

# Load into BigQuery
bq load --autodetect --replace \
  hulken.ads_data.cleaned_table \
  gs://hulken-exports/cleaned_data.csv
```

### Schema Definition Example

```python
from google.cloud import bigquery

schema = [
    bigquery.SchemaField("order_id", "STRING", mode="REQUIRED"),
    bigquery.SchemaField("total_price", "FLOAT"),
    bigquery.SchemaField("created_at", "TIMESTAMP"),
    bigquery.SchemaField("first_utm_source", "STRING"),
    bigquery.SchemaField("first_utm_medium", "STRING"),
    bigquery.SchemaField("channel", "STRING"),
    bigquery.SchemaField("is_new_customer", "BOOLEAN"),
]

job_config = bigquery.LoadJobConfig(
    schema=schema,
    write_disposition='WRITE_TRUNCATE'
)
```

---

## Best Practices

### Before Export

1. **Add filters** - Don't export entire tables unnecessarily
   ```sql
   WHERE created_at >= '2026-01-01'
   ```

2. **Select only needed columns** - Reduces file size
   ```sql
   SELECT order_id, total_price  -- Not SELECT *
   ```

3. **Check for PII** - Never export raw PII
   ```sql
   SELECT order_id, total_price, email_hash  -- Not email
   ```

### During Cleaning

1. **Keep original** - Always save a backup before cleaning
   ```python
   df_original = df.copy()
   ```

2. **Document changes** - Log what was modified
   ```python
   print(f"Removed {before - after} duplicates")
   ```

3. **Validate results** - Check data quality after cleaning
   ```python
   assert df['total_price'].min() >= 0
   assert df['order_id'].nunique() == len(df)
   ```

### Before Import

1. **Test with small dataset** - Upload 100 rows first
   ```python
   df_test = df.head(100)
   ```

2. **Use staging tables** - Don't overwrite production
   ```python
   table_id = 'hulken.ads_data.shopify_utm_staging'
   ```

3. **Verify schema** - Check column types match
   ```python
   job_config = bigquery.QueryJobConfig(dry_run=True)
   ```

### Naming Conventions

| Type | Pattern | Example |
|------|---------|---------|
| Staging tables | `{table}_staging` | `shopify_utm_staging` |
| Cleaned tables | `{table}_cleaned` | `shopify_utm_cleaned` |
| Backup tables | `{table}_backup_{date}` | `shopify_utm_backup_20260204` |
| Export files | `{table}_{date}.csv` | `shopify_utm_20260204.csv` |

---

## Common Workflows

### Weekly UTM Report Export

```python
from google.cloud import bigquery
import pandas as pd
from datetime import datetime, timedelta

client = bigquery.Client(project='hulken')

# Last 7 days
end_date = datetime.now().date()
start_date = end_date - timedelta(days=7)

query = f"""
SELECT
  first_utm_source,
  first_utm_medium,
  COUNT(*) as orders,
  SUM(total_price) as revenue
FROM `hulken.ads_data.shopify_utm`
WHERE DATE(created_at) BETWEEN '{start_date}' AND '{end_date}'
GROUP BY 1, 2
ORDER BY revenue DESC
"""

df = client.query(query).to_dataframe()
filename = f"utm_report_{end_date}.csv"
df.to_csv(filename, index=False)
print(f"Report saved to {filename}")
```

### Bulk Customer Segmentation Upload

```python
from google.cloud import bigquery
import pandas as pd

client = bigquery.Client(project='hulken')

# Read segmentation file
df = pd.read_csv('customer_segments.csv')

# Validate
assert 'email_hash' in df.columns
assert 'segment' in df.columns

# Upload
table_id = 'hulken.ads_data.customer_segments'
job_config = bigquery.LoadJobConfig(
    write_disposition='WRITE_TRUNCATE',
    schema=[
        bigquery.SchemaField("email_hash", "STRING"),
        bigquery.SchemaField("segment", "STRING"),
        bigquery.SchemaField("updated_at", "TIMESTAMP"),
    ]
)

df['updated_at'] = pd.Timestamp.now()
job = client.load_table_from_dataframe(df, table_id, job_config=job_config)
job.result()

print(f"Uploaded {len(df)} customer segments")
```

---

*Last updated: 2026-02-04*
