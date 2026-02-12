# BigQuery Table Cleanup Suggestions

**Date:** 2026-02-12
**Dataset:** `hulken.ads_data`
**Current state:** 38 tables/views, ~5.3 GB total

---

## 1. Why are there two Shopify orders tables?

| Table | Source | Period | Rows | How it got there |
|-------|--------|--------|------|------------------|
| `shopify_orders` | One-time bulk JSONL import | Sep 2021 - Jan 29 2026 | 585,927 | Manual upload |
| `shopify_live_orders_clean` | Airbyte live sync (ongoing) | May 2022 - today | 16,983 | Automatic daily |

- **8,114 orders exist in BOTH tables** (overlap from May 2022 to Jan 29)
- **8,869 orders exist only in live** (after Jan 29 - the bulk import cutoff)
- The two tables have **different column names** (`totalPrice` vs `total_price`, `createdAt` vs `created_at`)

**Suggestion:** Create a unified view `shopify_all_orders` that combines both tables with common columns and deduplicates by ID. Analysts use one table instead of guessing which one to pick.

---

## 2. TikTok: 4 redundant daily report tables

All four tables cover the same period (Jun 2022 - today) with the same spend total (~$2.6M):

| Table | Rows | Spend | Level | Needed? |
|-------|------|-------|-------|---------|
| `tiktokadvertisers_reports_daily` | 2,680 | $2,628,325 | Whole account (1 row/day) | No |
| `tiktokcampaigns_reports_daily` | 11,692 | $2,628,313 | Per campaign | Yes |
| `tiktokad_groups_reports_daily` | 13,519 | $2,628,299 | Per ad group | Maybe |
| `tiktokads_reports_daily` | 61,854 | $1,697,530 | Per individual ad | Yes |

The advertiser-level table is just one number per day - useless when you already have campaigns. The ad group level is rarely used in reports.

**Suggestion:** Disable `tiktokadvertisers_reports_daily` and `tiktokad_groups_reports_daily` in Airbyte. Keep `tiktokcampaigns_reports_daily` (campaign analysis) and `tiktokads_reports_daily` (ad-level detail).

**Impact:** -16K rows synced daily, faster sync times.

---

## 3. Facebook metadata tables: check if used

| Table | Rows | Size | Contains |
|-------|------|------|----------|
| `facebook_ad_creatives` | 5,160 | 13.3 MB | Ad images, videos, links, titles |
| `facebook_ads` | 5,428 | 7.2 MB | Ad names, statuses, IDs |
| `facebook_ad_sets` | 341 | 0.2 MB | Ad set names, budgets, targeting |

These are metadata/catalog tables. `facebook_insights` already contains `campaign_name` and `ad_name` directly, so joins to these tables are not needed for standard reporting.

**Suggestion:** If nobody queries these tables (check with the team), disable them in Airbyte. If creative analysis is planned (which image/video performs best), keep `facebook_ad_creatives`.

**Impact:** -11K rows, -20 MB, faster Facebook sync.

---

## 4. Shopify transactions: heavy and possibly unused

| Table | Rows | Size |
|-------|------|------|
| `shopify_live_transactions` | 59,041 | 174.5 MB |

This is the 3rd heaviest table. It contains payment transaction details (gateway, amount, authorization codes). If the only need is "was the order paid?", that info is already in `shopify_live_orders_clean` (financial status field).

**Suggestion:** Verify if anyone uses this table. If not, disable in Airbyte.

**Impact:** -174 MB, significantly faster Shopify sync.

---

## Summary

| Priority | Action | Tables | Impact |
|----------|--------|--------|--------|
| High | Create unified Shopify view | `shopify_orders` + `shopify_live_orders_clean` | Simpler for analysts |
| High | Disable in Airbyte | `tiktokadvertisers_reports_daily` | -2.7K useless rows |
| Medium | Disable in Airbyte | `tiktokad_groups_reports_daily` | -13.5K rows, faster sync |
| Medium | Check usage, then disable | `shopify_live_transactions` | -174 MB |
| Low | Check usage, then disable | `facebook_ad_creatives`, `facebook_ads`, `facebook_ad_sets` | -20 MB |

**Total potential savings:** ~200 MB storage, ~32K fewer rows synced daily, faster Airbyte sync times.

---

*No action taken - suggestions only. Confirm before implementing.*
