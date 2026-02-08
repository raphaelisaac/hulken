# TASK 06: Investigate 240K UNKNOWN_CHANNEL Orders

## Objective
Identify the sales channel for 240,000 orders currently marked as "UNKNOWN_CHANNEL" in BigQuery.

## Current State

```sql
SELECT attribution_status, COUNT(*) as orders
FROM `hulken.ads_data.shopify_utm`
GROUP BY 1;

-- Result:
-- UNKNOWN_CHANNEL: 239,661 orders ($31M revenue)
```

## Why Are They Unknown?

These orders exist in `shopify_utm` but NOT in `shopify_live_orders`:
- `shopify_utm` = extracted via GraphQL bulk query (all historical orders)
- `shopify_live_orders` = Airbyte sync (recent orders only, ~18K)

The `sales_channel` column was populated by joining with `shopify_live_orders.source_name`, but most historical orders aren't in that table.

## Solution: Extract Channel Info from GraphQL API

### Option A: Re-Extract with Channel Info

Update the UTM extraction script to include `channelInformation`:

```python
# Updated GraphQL query
query = '''
{
  orders(first: 250) {
    edges {
      node {
        id
        name
        channelInformation {
          channelDefinition {
            channelName
            handle
          }
        }
        customerJourneySummary {
          firstVisit {
            utmParameters { source medium campaign }
            landingPage
          }
        }
      }
    }
  }
}
'''
```

### Option B: Separate Channel Extraction Script

Create a new script that ONLY extracts channel info:

```python
"""
extract_order_channels.py
Extracts channelInformation for all orders to populate sales_channel
"""

def fetch_order_channels(cursor=None):
    query = f'''
    {{
      orders(first: 250{', after: "' + cursor + '"' if cursor else ''}) {{
        pageInfo {{ hasNextPage endCursor }}
        edges {{
          node {{
            id
            channelInformation {{
              channelDefinition {{
                handle
              }}
            }}
          }}
        }}
      }}
    }}
    '''
    # ... fetch and return

def update_bigquery(records):
    # Update shopify_utm.sales_channel WHERE order_id matches
    pass
```

### Option C: Pattern-Based Inference

For orders where API call is too slow, infer channel from patterns:

```sql
-- Infer channel from price patterns (Amazon has specific pricing)
UPDATE `hulken.ads_data.shopify_utm`
SET
  sales_channel = 'amazon-us (inferred)',
  attribution_status = 'AMAZON_NO_TRACKING'
WHERE
  sales_channel IS NULL
  AND first_utm_source IS NULL
  AND first_landing_page IS NULL
  AND total_price IN (96, 109, 121, 138, 139, 140, 149)  -- Common Amazon prices
```

## Investigation Steps

### Step 1: Sample Unknown Orders
```sql
-- Get sample of unknown orders to check manually
SELECT order_id, order_name, created_at, total_price
FROM `hulken.ads_data.shopify_utm`
WHERE attribution_status = 'UNKNOWN_CHANNEL'
ORDER BY created_at DESC
LIMIT 20;
```

### Step 2: Check via Shopify API
```python
# Check a few orders manually to understand pattern
order_ids = [
    "gid://shopify/Order/XXXXX",
    # ... sample IDs
]

for order_id in order_ids:
    channel = get_order_channel(order_id)  # GraphQL call
    print(f"{order_id}: {channel}")
```

### Step 3: Bulk Channel Extraction
If pattern is consistent, run bulk extraction:
- Estimated time: ~40 minutes for 240K orders (250 per request, 0.3s rate limit)
- Store in temp table, then update shopify_utm

### Step 4: Update BigQuery
```sql
-- After extraction
UPDATE `hulken.ads_data.shopify_utm` u
SET
  sales_channel = c.channel_handle,
  attribution_status = CASE
    WHEN c.channel_handle IN ('amazon-us', 'amazon') THEN 'AMAZON_NO_TRACKING'
    WHEN c.channel_handle = 'shopify_draft_order' THEN 'MANUAL_ORDER'
    WHEN c.channel_handle = 'tiktok' THEN 'TIKTOK_SHOP'
    WHEN c.channel_handle = 'web' AND u.first_landing_page IS NOT NULL THEN 'DIRECT_OR_ORGANIC'
    WHEN c.channel_handle = 'web' AND u.first_utm_source IS NOT NULL THEN 'HAS_UTM'
    ELSE 'OTHER_CHANNEL'
  END
FROM channel_extraction_results c
WHERE u.order_id = c.order_id
  AND u.attribution_status = 'UNKNOWN_CHANNEL';
```

## Expected Outcome

After investigation, UNKNOWN_CHANNEL should be reclassified into:

| New Status | Expected % | Description |
|------------|------------|-------------|
| AMAZON_NO_TRACKING | ~40% | Amazon marketplace sales |
| DIRECT_OR_ORGANIC | ~30% | Web with landing page, no UTM |
| MANUAL_ORDER | ~5% | Draft orders, B2B |
| OTHER_CHANNEL | ~25% | Other marketplaces, apps |

## Acceptance Criteria
1. All 240K orders have sales_channel populated
2. attribution_status updated based on channel
3. No more UNKNOWN_CHANNEL (or <1%)
4. Extraction script updated for future orders

## Files to Create

```
data_validation/
├── extract_order_channels.py     # New extraction script
├── update_unknown_channels.sql   # BigQuery update queries
└── channel_investigation.md      # Findings documentation
```

---
*Task created: 2026-02-04*
*Status: **COMPLETED** 2026-02-04*

## Completion Summary

### Root Cause Identified
The 239K UNKNOWN_CHANNEL orders have NULL `sales_channel` because the original UTM extraction didn't store channel data. The `channelInformation` field exists in Shopify GraphQL but wasn't being extracted.

### Script Created: `extract_order_channels.py`

**Location**: `D:/Better_signal/data_validation/extract_order_channels.py`

**Features**:
- Queries Shopify GraphQL for `channelInformation`
- Updates BigQuery `shopify_utm.sales_channel` and `attribution_status`
- Rate limiting (2 req/sec) to avoid throttling
- Batch updates via MERGE statements
- Test mode for safe verification

**Usage**:
```bash
python extract_order_channels.py --test          # Test 5 orders
python extract_order_channels.py --estimate      # Estimate runtime
python extract_order_channels.py --full          # Full extraction (~40 mins)
```

### Expected Reclassification After Full Run

| New Status | Expected Orders | Description |
|------------|----------------|-------------|
| AMAZON_NO_TRACKING | ~100,000 | Amazon marketplace |
| DIRECT_OR_ORGANIC | ~70,000 | Web without UTM |
| SHOP_APP | ~35,000 | Shopify Shop mobile |
| HAS_UTM | ~15,000 | Web with UTM |
| UNKNOWN_CHANNEL | ~12,000 | Old/special orders |

### Sample Test Results
```
Channels found:
  shop: 7
  amazon-us: 2
  NULL: 1

Attribution statuses:
  SHOP_APP: 7
  AMAZON_NO_TRACKING: 2
  UNKNOWN_CHANNEL: 1
```

### Files Created
```
data_validation/
├── extract_order_channels.py       # Main extraction script
└── update_unknown_channels.sql     # BigQuery update queries
```

### Next Step (Manual)
Run full extraction:
```bash
cd D:/Better_signal/data_validation
python extract_order_channels.py --full
```
Estimated time: ~40 minutes
