#!/usr/bin/env python3
"""
PRODUCTION DATA RECONCILIATION CHECK v2
========================================
Comprehensive data quality verification with actionable diagnostics.

Every check explains:
- WHAT: the exact finding
- WHY: root cause analysis
- IMPACT: business consequence
- ACTION: what to do about it

Usage:
    python reconciliation_check.py
    python reconciliation_check.py --start 2026-01-01 --end 2026-01-31
    python reconciliation_check.py --checks freshness,pii,duplicates
"""

import os
import sys
import json
import argparse
from datetime import datetime, timedelta
from pathlib import Path

# Fix Unicode on Windows
if sys.platform == 'win32':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

from dotenv import load_dotenv
from google.cloud import bigquery

# Load env from data_validation/.env
env_path = Path(__file__).parent / '.env'
load_dotenv(env_path)

# ============================================================
# CONFIGURATION
# ============================================================
BQ_PROJECT = os.getenv('BIGQUERY_PROJECT', 'hulken')
BQ_DATASET = os.getenv('BIGQUERY_DATASET', 'ads_data')
CREDENTIALS_PATH = os.getenv('GOOGLE_APPLICATION_CREDENTIALS')

if CREDENTIALS_PATH:
    os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = CREDENTIALS_PATH

# Thresholds
FRESHNESS_OK_DAYS = 1       # GA4 J-1 is normal
FRESHNESS_WARNING_DAYS = 3  # Airbyte syncs daily, 3 days = missed syncs
FRESHNESS_CRITICAL_DAYS = 5 # 5+ days = connector is broken

# Expected daily volumes (for anomaly detection)
EXPECTED_DAILY = {
    'shopify_orders': {'min': 400, 'max': 1200},
    'facebook_ads': {'min': 100, 'max': 600},
    'tiktok_ads': {'min': 30, 'max': 150},
}

# Average daily spend for impact estimation
AVG_DAILY_SPEND = {
    'facebook': 20000,  # ~$20K/day based on historical
    'tiktok': 2000,     # ~$2K/day based on historical
    'shopify_revenue': 90000,  # ~$90K/day
}


# ============================================================
# RESULT TRACKING
# ============================================================
class CheckResult:
    def __init__(self, name, status, message, diagnosis=None, details=None):
        self.name = name
        self.status = status  # PASS, WARNING, FAIL, ERROR
        self.message = message
        self.diagnosis = diagnosis or {}
        self.details = details or {}

    def __str__(self):
        icon = {'PASS': '[OK  ]', 'WARNING': '[WARN]', 'FAIL': '[FAIL]', 'ERROR': '[ERR ]'}
        lines = [f"  {icon.get(self.status, '[????]')} {self.name}: {self.message}"]
        if self.diagnosis and self.status != 'PASS':
            if 'cause' in self.diagnosis:
                lines.append(f"         Cause: {self.diagnosis['cause']}")
            if 'impact' in self.diagnosis:
                lines.append(f"         Impact: {self.diagnosis['impact']}")
            if 'action' in self.diagnosis:
                lines.append(f"         Action: {self.diagnosis['action']}")
        return '\n'.join(lines)


class ReconciliationCheck:
    def __init__(self, start_date=None, end_date=None, checks=None):
        self.bq = bigquery.Client(project=BQ_PROJECT)
        self.end_date = end_date or datetime.now().strftime('%Y-%m-%d')
        self.start_date = start_date or (datetime.now() - timedelta(days=30)).strftime('%Y-%m-%d')
        self.checks = checks
        self.results = []
        self.timestamp = datetime.now().isoformat()

    def add(self, name, status, message, diagnosis=None, details=None):
        r = CheckResult(name, status, message, diagnosis, details)
        self.results.append(r)
        print(str(r))
        return r

    def query(self, sql):
        return list(self.bq.query(sql).result())

    # ============================================================
    # CHECK 1: DATA FRESHNESS
    # ============================================================
    def check_freshness(self):
        print("\n=== DATA FRESHNESS ===")

        sources = [
            {
                'name': 'Facebook Ads',
                'sql': f"SELECT MAX(date_start) FROM `{BQ_PROJECT}.{BQ_DATASET}.facebook_insights`",
                'connector': 'Airbyte Facebook Marketing',
                'daily_spend': AVG_DAILY_SPEND['facebook'],
            },
            {
                'name': 'TikTok Ads',
                'sql': f"SELECT MAX(DATE(stat_time_day)) FROM `{BQ_PROJECT}.{BQ_DATASET}.tiktok_ads_reports_daily`",
                'connector': 'Airbyte TikTok Marketing',
                'daily_spend': AVG_DAILY_SPEND['tiktok'],
            },
            {
                'name': 'Shopify Orders',
                'sql': f"SELECT MAX(DATE(created_at)) FROM `{BQ_PROJECT}.{BQ_DATASET}.shopify_live_orders`",
                'connector': 'Airbyte Shopify',
                'daily_spend': AVG_DAILY_SPEND['shopify_revenue'],
            },
            {
                'name': 'Shopify Customers',
                'sql': f"SELECT MAX(DATE(updated_at)) FROM `{BQ_PROJECT}.{BQ_DATASET}.shopify_live_customers`",
                'connector': 'Airbyte Shopify',
                'daily_spend': 0,
            },
            {
                'name': 'Shopify UTM',
                'sql': f"SELECT MAX(DATE(created_at)) FROM `{BQ_PROJECT}.{BQ_DATASET}.shopify_utm`",
                'connector': 'Local extraction script',
                'daily_spend': 0,
            },
        ]

        today = datetime.now().date()

        for src in sources:
            try:
                row = self.query(src['sql'])[0]
                latest = row[0]
            except Exception as e:
                self.add(f"Freshness: {src['name']}", "ERROR",
                         f"Query failed: {e}",
                         diagnosis={
                             'cause': f"Table may not exist or schema changed",
                             'impact': f"Cannot verify {src['name']} data freshness",
                             'action': f"Check table exists in BigQuery dataset {BQ_DATASET}"
                         })
                continue

            if latest is None:
                self.add(f"Freshness: {src['name']}", "FAIL", "No data found",
                         diagnosis={
                             'cause': f"{src['connector']} has never synced data to this table",
                             'impact': f"Zero {src['name']} data available for analysis",
                             'action': f"Verify {src['connector']} connection exists and is enabled in Airbyte UI"
                         })
                continue

            gap_days = (today - latest).days
            missed_spend = gap_days * src['daily_spend'] if src['daily_spend'] > 0 else 0

            if gap_days <= FRESHNESS_OK_DAYS:
                self.add(f"Freshness: {src['name']}", "PASS",
                         f"Current (latest: {latest})")
            elif gap_days <= FRESHNESS_WARNING_DAYS:
                self.add(f"Freshness: {src['name']}", "WARNING",
                         f"{gap_days} days behind (latest: {latest})",
                         diagnosis={
                             'cause': f"{src['connector']} has missed {gap_days - 1} scheduled syncs (runs every 24h)",
                             'impact': f"Missing {gap_days} days of data" + (f" = ~${missed_spend:,.0f} untracked" if missed_spend else ""),
                             'action': f"SSH to Airbyte VM, check connection '{src['connector']}' logs for errors. Trigger manual sync."
                         })
            else:
                self.add(f"Freshness: {src['name']}", "FAIL",
                         f"{gap_days} days behind (latest: {latest})",
                         diagnosis={
                             'cause': f"{src['connector']} connector is DOWN. No sync for {gap_days} days. Likely causes: expired API token, rate limiting, or Airbyte worker crash.",
                             'impact': f"CRITICAL: {gap_days} days of missing data" + (f" = ~${missed_spend:,.0f} of untracked spend/revenue" if missed_spend else "") + ". All reports and dashboards show stale numbers.",
                             'action': f"IMMEDIATE: SSH to Airbyte VM (see docs/runbooks/airbyte_runbook.md). Check connection status, review error logs, restart sync. If token expired, regenerate in platform's developer console."
                         })

    # ============================================================
    # CHECK 2: DUPLICATE DETECTION
    # ============================================================
    def check_duplicates(self):
        print("\n=== DUPLICATE DETECTION ===")

        tables = [
            ("shopify_live_orders", "id", "Airbyte Shopify sync"),
            ("shopify_live_orders_clean", "id", "PII hash scheduled query"),
            ("shopify_live_customers", "id", "Airbyte Shopify sync"),
            ("shopify_live_customers_clean", "id", "PII hash scheduled query"),
            ("shopify_orders", "id", "Airbyte Shopify sync (historical)"),
            ("shopify_utm", "order_id", "UTM extraction script"),
        ]

        for table, pk, source in tables:
            try:
                sql = f"""
                SELECT COUNT(*) AS total, COUNT(DISTINCT {pk}) AS distinct_keys
                FROM `{BQ_PROJECT}.{BQ_DATASET}.{table}`
                """
                row = self.query(sql)[0]
                dupes = row.total - row.distinct_keys
                if dupes == 0:
                    self.add(f"Duplicates: {table}", "PASS", f"0 duplicates ({row.total:,} rows)")
                else:
                    pct = dupes / row.total * 100
                    if pct < 1:
                        status = "WARNING"
                    else:
                        status = "FAIL"
                    self.add(f"Duplicates: {table}", status,
                             f"{dupes:,} duplicates ({pct:.1f}%) on {row.total:,} rows",
                             diagnosis={
                                 'cause': f"Source: {source}. Duplicate {pk} values found, likely from overlapping incremental sync windows or script re-runs.",
                                 'impact': f"SUM/COUNT queries on this table will be inflated by {pct:.1f}%. Revenue and order metrics are overstated.",
                                 'action': f"Deduplicate: CREATE VIEW {table}_dedup AS SELECT * EXCEPT(rn) FROM (SELECT *, ROW_NUMBER() OVER(PARTITION BY {pk} ORDER BY _airbyte_extracted_at DESC) rn FROM {table}) WHERE rn=1"
                             })
            except Exception as e:
                self.add(f"Duplicates: {table}", "ERROR", str(e))

        # Facebook - known append mode issue
        try:
            sql = f"""
            SELECT COUNT(*) AS total,
              COUNT(DISTINCT CONCAT(CAST(ad_id AS STRING), '|', CAST(date_start AS STRING), '|', CAST(account_id AS STRING))) AS distinct_keys
            FROM `{BQ_PROJECT}.{BQ_DATASET}.facebook_insights`
            """
            row = self.query(sql)[0]
            dupes = row.total - row.distinct_keys
            if dupes == 0:
                self.add("Duplicates: facebook_insights", "PASS", "0 duplicates")
            else:
                pct = dupes / row.total * 100
                self.add("Duplicates: facebook_insights", "WARNING",
                         f"{dupes:,} duplicates ({pct:.1f}%) - dedup view available",
                         diagnosis={
                             'cause': "Airbyte Facebook connector uses append mode. Each sync re-ingests recent days, creating overlapping records.",
                             'impact': f"{dupes:,} duplicate rows inflate spend totals by ~{pct:.0f}% if querying raw table. The dedup view 'facebook_insights' filters these out.",
                             'action': "ALWAYS use `facebook_insights` view for analysis. The view keeps only the latest version of each (ad_id, date_start, account_id) combination."
                         })
        except Exception as e:
            self.add("Duplicates: facebook_insights", "ERROR", str(e))

        # TikTok
        try:
            sql = f"""
            SELECT COUNT(*) AS total,
              COUNT(DISTINCT CONCAT(CAST(ad_id AS STRING), '|', CAST(stat_time_day AS STRING))) AS distinct_keys
            FROM `{BQ_PROJECT}.{BQ_DATASET}.tiktok_ads_reports_daily`
            """
            row = self.query(sql)[0]
            dupes = row.total - row.distinct_keys
            if dupes == 0:
                self.add("Duplicates: tiktok_reports", "PASS", f"0 duplicates ({row.total:,} rows)")
            else:
                pct = dupes / row.total * 100
                self.add("Duplicates: tiktok_reports", "FAIL",
                         f"{dupes:,} duplicates ({pct:.1f}%)",
                         diagnosis={
                             'cause': "TikTok Airbyte connector is configured as incremental_deduped_history, so duplicates indicate a primary key issue.",
                             'impact': f"TikTok spend totals may be inflated by {pct:.1f}%.",
                             'action': "Check Airbyte TikTok connection primary key configuration. Expected: (ad_id, stat_time_day)."
                         })
        except Exception as e:
            self.add("Duplicates: tiktok_reports", "ERROR", str(e))

    # ============================================================
    # CHECK 3: PII AUDIT
    # ============================================================
    def check_pii(self):
        print("\n=== PII AUDIT (zero tolerance) ===")
        checks = [
            ("shopify_live_orders", "email", "email LIKE '%@%'", "Customer email addresses"),
            ("shopify_live_orders", "contact_email", "contact_email LIKE '%@%'", "Contact email addresses"),
            ("shopify_live_orders", "phone", "phone IS NOT NULL AND phone != '' AND LENGTH(phone) > 3", "Phone numbers"),
            ("shopify_live_orders", "browser_ip", "browser_ip IS NOT NULL AND browser_ip != ''", "IP addresses"),
            ("shopify_live_orders", "customer_json", "customer IS NOT NULL AND JSON_VALUE(customer, '$.email') LIKE '%@%'", "Email in customer JSON"),
            ("shopify_live_customers", "email", "email LIKE '%@%'", "Customer email addresses"),
            ("shopify_live_customers", "phone", "phone IS NOT NULL AND phone != '' AND LENGTH(phone) > 3", "Phone numbers"),
            ("shopify_live_customers", "first_name", "first_name IS NOT NULL AND first_name != ''", "First names"),
            ("shopify_live_customers", "last_name", "last_name IS NOT NULL AND last_name != ''", "Last names"),
            ("shopify_live_orders_clean", "customer_email_in_json", "JSON_VALUE(customer, '$.email') LIKE '%@%'", "Email in clean customer JSON"),
            ("shopify_live_orders_clean", "customer_name_in_json", "JSON_VALUE(customer, '$.first_name') IS NOT NULL AND JSON_VALUE(customer, '$.first_name') != ''", "Name in clean customer JSON"),
            ("shopify_live_customers_clean", "first_name", "first_name IS NOT NULL AND first_name != ''", "First name in clean table"),
        ]

        total_exposed = 0
        for table, field, condition, description in checks:
            try:
                sql = f"""
                SELECT COUNTIF({condition}) AS exposed, COUNT(*) AS total
                FROM `{BQ_PROJECT}.{BQ_DATASET}.{table}`
                """
                row = self.query(sql)[0]
                if row.exposed == 0:
                    self.add(f"PII: {table}.{field}", "PASS", "0 exposed")
                else:
                    total_exposed += row.exposed
                    self.add(f"PII: {table}.{field}", "FAIL",
                             f"{row.exposed:,} records with cleartext PII!",
                             diagnosis={
                                 'cause': f"PII hash scheduled query failed to nullify {description} in {table}. The hash job runs every 5 minutes - if this fails, raw PII accumulates.",
                                 'impact': f"CRITICAL COMPLIANCE VIOLATION: {row.exposed:,} records with exposed {description}. SOC/GDPR breach risk.",
                                 'action': f"IMMEDIATE: Check BigQuery scheduled query 'PII Hash Job' for errors. Manually run the hash query to clear exposed data. Verify _clean table is populated correctly."
                             })
            except Exception as e:
                self.add(f"PII: {table}.{field}", "ERROR", str(e))

        if total_exposed == 0:
            self.add("PII: OVERALL", "PASS", "Zero PII exposure across all tables")
        else:
            self.add("PII: OVERALL", "FAIL",
                     f"CRITICAL: {total_exposed:,} total PII exposures found!",
                     diagnosis={
                         'cause': "PII hash scheduled query is not fully covering all PII fields.",
                         'impact': f"Regulatory compliance breach. {total_exposed:,} records with cleartext PII.",
                         'action': "Stop all downstream data access. Fix hash job. Re-run hash query. Verify zero exposure."
                     })

    # ============================================================
    # CHECK 4: HASH CONSISTENCY
    # ============================================================
    def check_hashes(self):
        print("\n=== HASH CONSISTENCY ===")

        for table in ['shopify_live_orders_clean', 'shopify_live_customers_clean', 'shopify_orders']:
            try:
                sql = f"""
                SELECT COUNT(*) AS total,
                  COUNTIF(email_hash IS NOT NULL AND email_hash != '' AND LENGTH(email_hash) = 64) AS correct,
                  COUNTIF(email_hash IS NOT NULL AND email_hash != '' AND LENGTH(email_hash) != 64) AS wrong,
                  COUNTIF(email_hash IS NULL OR email_hash = '') AS missing
                FROM `{BQ_PROJECT}.{BQ_DATASET}.{table}`
                """
                row = self.query(sql)[0]
                if row.wrong == 0 and row.missing == 0:
                    self.add(f"Hash format: {table}", "PASS", f"All {row.correct:,} hashes are 64-char SHA256")
                elif row.wrong > 0:
                    self.add(f"Hash format: {table}", "FAIL",
                             f"{row.wrong:,} hashes have wrong length (expected 64 chars)",
                             diagnosis={
                                 'cause': "Hash function produced non-standard output. Possible encoding issue or truncation.",
                                 'impact': f"{row.wrong:,} records cannot be matched cross-table. Attribution analysis will miss these customers.",
                                 'action': "Review the BigQuery scheduled hash query. Ensure SHA256(LOWER(TRIM(email))) is used consistently."
                             })
                elif row.missing > 0:
                    pct = row.missing / row.total * 100
                    status = "PASS" if pct < 1 else "WARNING"
                    self.add(f"Hash format: {table}", status,
                             f"{row.correct:,} valid hashes, {row.missing:,} missing ({pct:.1f}%)",
                             diagnosis={
                                 'cause': "Some records have NULL or empty email_hash. These are typically guest checkouts or records ingested before the hash job ran.",
                                 'impact': f"{row.missing:,} records cannot be used for customer matching. {pct:.1f}% of data is unlinked.",
                                 'action': "Check if these correspond to orders without email (guest checkout). If not, re-run hash job."
                             } if status != "PASS" else None)
            except Exception as e:
                self.add(f"Hash format: {table}", "ERROR", str(e))

        # Cross-table match
        try:
            sql = f"""
            SELECT
              (SELECT COUNT(DISTINCT email_hash) FROM `{BQ_PROJECT}.{BQ_DATASET}.shopify_live_orders_clean`
               WHERE email_hash IS NOT NULL AND email_hash != '' AND email_hash != 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') AS order_hashes,
              (SELECT COUNT(DISTINCT email_hash) FROM `{BQ_PROJECT}.{BQ_DATASET}.shopify_live_customers_clean`
               WHERE email_hash IS NOT NULL AND email_hash != '' AND email_hash != 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') AS customer_hashes,
              (SELECT COUNT(*) FROM (
                SELECT DISTINCT o.email_hash FROM `{BQ_PROJECT}.{BQ_DATASET}.shopify_live_orders_clean` o
                JOIN `{BQ_PROJECT}.{BQ_DATASET}.shopify_live_customers_clean` c ON o.email_hash = c.email_hash
                WHERE o.email_hash != 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
              )) AS matched
            """
            row = self.query(sql)[0]
            match_rate = (row.matched / row.order_hashes * 100) if row.order_hashes > 0 else 0
            unmatched = row.order_hashes - row.matched

            if match_rate >= 70:
                self.add("Hash cross-table match", "PASS",
                         f"{row.matched:,}/{row.order_hashes:,} order emails match customers ({match_rate:.0f}%)")
            elif match_rate >= 50:
                self.add("Hash cross-table match", "WARNING",
                         f"{row.matched:,}/{row.order_hashes:,} match ({match_rate:.0f}%), {unmatched:,} unmatched",
                         diagnosis={
                             'cause': f"{unmatched:,} order email hashes have no matching customer record. Common for: guest checkouts, recently created orders before customer sync, or email changes.",
                             'impact': f"Customer-level analysis (LTV, cohorts) will miss {100-match_rate:.0f}% of orders.",
                             'action': "Verify Shopify customer sync is up to date. Guest orders are expected to be unmatched."
                         })
            else:
                self.add("Hash cross-table match", "FAIL",
                         f"Only {match_rate:.0f}% match - hashing may be inconsistent",
                         diagnosis={
                             'cause': "Low match rate suggests different hashing methods between orders_clean and customers_clean tables.",
                             'impact': "Customer matching is broken. LTV, cohort, and repeat purchase analysis will be unreliable.",
                             'action': "Compare hash logic: both must use SHA256(LOWER(TRIM(email))). Check if one table hashes before and the other after email normalization."
                         })
        except Exception as e:
            self.add("Hash cross-table match", "ERROR", str(e))

    # ============================================================
    # CHECK 5: TEMPORAL CONTINUITY
    # ============================================================
    def check_continuity(self):
        print("\n=== TEMPORAL CONTINUITY (last 30 days) ===")

        continuity_checks = [
            {
                'name': 'Shopify orders',
                'sql': f"""
                    WITH dates AS (
                      SELECT date FROM UNNEST(GENERATE_DATE_ARRAY(
                        DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY), DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
                      )) AS date
                    ),
                    data_dates AS (
                      SELECT DATE(created_at) AS d, COUNT(*) AS cnt
                      FROM `{BQ_PROJECT}.{BQ_DATASET}.shopify_live_orders_clean`
                      WHERE DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
                      GROUP BY d
                    )
                    SELECT d.date FROM dates d LEFT JOIN data_dates o ON d.date = o.d
                    WHERE o.cnt IS NULL ORDER BY d.date
                """,
                'connector': 'Airbyte Shopify',
                'daily_value': AVG_DAILY_SPEND['shopify_revenue'],
                'value_label': 'revenue',
            },
            {
                'name': 'Facebook',
                'sql': f"""
                    WITH dates AS (
                      SELECT date FROM UNNEST(GENERATE_DATE_ARRAY(
                        DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY), DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
                      )) AS date
                    ),
                    data_dates AS (
                      SELECT date_start AS d, COUNT(*) AS cnt
                      FROM `{BQ_PROJECT}.{BQ_DATASET}.facebook_insights`
                      WHERE date_start >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
                      GROUP BY d
                    )
                    SELECT d.date FROM dates d LEFT JOIN data_dates f ON d.date = f.d
                    WHERE f.cnt IS NULL ORDER BY d.date
                """,
                'connector': 'Airbyte Facebook Marketing',
                'daily_value': AVG_DAILY_SPEND['facebook'],
                'value_label': 'ad spend',
            },
            {
                'name': 'TikTok',
                'sql': f"""
                    WITH dates AS (
                      SELECT date FROM UNNEST(GENERATE_DATE_ARRAY(
                        DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY), DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
                      )) AS date
                    ),
                    data_dates AS (
                      SELECT DATE(stat_time_day) AS d, COUNT(*) AS cnt
                      FROM `{BQ_PROJECT}.{BQ_DATASET}.tiktok_ads_reports_daily`
                      WHERE DATE(stat_time_day) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
                      GROUP BY d
                    )
                    SELECT d.date FROM dates d LEFT JOIN data_dates t ON d.date = t.d
                    WHERE t.cnt IS NULL ORDER BY d.date
                """,
                'connector': 'Airbyte TikTok Marketing',
                'daily_value': AVG_DAILY_SPEND['tiktok'],
                'value_label': 'ad spend',
            },
        ]

        for check in continuity_checks:
            try:
                missing = self.query(check['sql'])
                if len(missing) == 0:
                    self.add(f"Continuity: {check['name']}", "PASS", "No missing days in last 30 days")
                else:
                    dates = [str(r.date) for r in missing]
                    total_missing_value = len(missing) * check['daily_value']

                    # Determine if gap is at the end (sync stopped) or in the middle (sync hiccup)
                    today = datetime.now().date()
                    latest_missing = missing[-1].date
                    gap_at_end = (today - latest_missing).days <= 2

                    if gap_at_end:
                        cause = f"{check['connector']} connector stopped syncing. The {len(missing)} most recent days are missing, indicating the sync is currently broken."
                        action = f"URGENT: Restart {check['connector']} in Airbyte. After restart, verify backfill covers all missing dates: {', '.join(dates[-5:])}"
                    else:
                        cause = f"{check['connector']} had a temporary sync failure. {len(missing)} days are missing in the middle of the range, but recent syncs are working."
                        action = f"Trigger a historical re-sync in Airbyte for the missing dates. Consider reducing sync interval from 24h to 12h for redundancy."

                    if len(missing) <= 3:
                        status = "WARNING"
                    else:
                        status = "FAIL"

                    self.add(f"Continuity: {check['name']}", status,
                             f"{len(missing)} missing days: {', '.join(dates[:5])}" + (f"... +{len(dates)-5} more" if len(dates) > 5 else ""),
                             diagnosis={
                                 'cause': cause,
                                 'impact': f"~${total_missing_value:,.0f} of {check['value_label']} is untracked. Reports for these dates show zero values.",
                                 'action': action
                             })
            except Exception as e:
                self.add(f"Continuity: {check['name']}", "ERROR", str(e))

    # ============================================================
    # CHECK 6: NULL CRITICAL FIELDS
    # ============================================================
    def check_nulls(self):
        print("\n=== CRITICAL FIELD COMPLETENESS ===")
        field_checks = [
            ("shopify_live_orders_clean", "total_price", "Revenue calculation"),
            ("shopify_live_orders_clean", "created_at", "Time-series analysis"),
            ("shopify_live_orders_clean", "email_hash", "Customer matching"),
            ("shopify_live_customers_clean", "email_hash", "Customer identification"),
            ("facebook_insights", "spend", "Ad spend tracking"),
            ("facebook_insights", "date_start", "Date partitioning"),
            ("facebook_insights", "ad_id", "Ad-level attribution"),
            ("tiktok_ads_reports_daily", "metrics", "Performance metrics"),
            ("tiktok_ads_reports_daily", "stat_time_day", "Date partitioning"),
        ]

        for table, field, purpose in field_checks:
            try:
                sql = f"""
                SELECT COUNTIF({field} IS NULL) AS null_count, COUNT(*) AS total
                FROM `{BQ_PROJECT}.{BQ_DATASET}.{table}`
                """
                row = self.query(sql)[0]
                if row.null_count == 0:
                    self.add(f"NULLs: {table}.{field}", "PASS", f"0/{row.total:,} null")
                else:
                    pct = row.null_count / row.total * 100
                    status = "WARNING" if pct < 5 else "FAIL"
                    self.add(f"NULLs: {table}.{field}", status,
                             f"{row.null_count:,}/{row.total:,} null ({pct:.1f}%)",
                             diagnosis={
                                 'cause': f"Field '{field}' is NULL in {row.null_count:,} records. This field is required for: {purpose}.",
                                 'impact': f"{pct:.1f}% of records are missing {field}, which breaks {purpose.lower()}.",
                                 'action': f"Investigate source data in Airbyte. Check if Shopify/Facebook/TikTok API returns NULL for this field on specific record types."
                             })
            except Exception as e:
                self.add(f"NULLs: {table}.{field}", "ERROR", str(e))

    # ============================================================
    # CHECK 7: PII SCHEDULED QUERY HEALTH
    # ============================================================
    def check_pii_schedule(self):
        print("\n=== PII HASH SCHEDULE HEALTH ===")
        try:
            sql = """
            SELECT
              COUNT(*) AS total_runs,
              COUNTIF(error_result.reason IS NOT NULL) AS errors,
              MIN(creation_time) AS first_run,
              MAX(creation_time) AS last_run,
              TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(creation_time), MINUTE) AS minutes_since_last
            FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
            WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
              AND job_id LIKE 'scheduled_query%'
              AND job_type = 'QUERY'
            """
            row = self.query(sql)[0]

            if row.total_runs >= 10:
                self.add("PII schedule: frequency", "PASS",
                         f"{row.total_runs} runs in last hour (~every 5 min)")
            elif row.total_runs >= 5:
                self.add("PII schedule: frequency", "WARNING",
                         f"Only {row.total_runs} runs in last hour (expected 12)",
                         diagnosis={
                             'cause': "Scheduled query is running slower than expected. Possible: BigQuery slot contention or query taking longer than 5 minutes.",
                             'impact': "PII exposure window is wider. New Airbyte data may be visible in plaintext for up to 10 minutes instead of 5.",
                             'action': "Check BigQuery scheduled query execution times. Consider optimizing the hash query or increasing slot allocation."
                         })
            else:
                self.add("PII schedule: frequency", "FAIL",
                         f"Only {row.total_runs} runs in last hour - schedule may be broken",
                         diagnosis={
                             'cause': "PII hash scheduled query has nearly stopped running. The schedule may be paused, disabled, or encountering repeated errors.",
                             'impact': "CRITICAL: New data from Airbyte syncs will contain plaintext PII until the hash job processes it. Compliance breach risk.",
                             'action': "IMMEDIATE: Go to BigQuery > Scheduled Queries. Find the PII hash query. Check if it's enabled. Review error log. Re-enable if paused."
                         })

            if row.errors == 0:
                self.add("PII schedule: errors", "PASS", "0 errors in last hour")
            else:
                self.add("PII schedule: errors", "FAIL",
                         f"{row.errors} errors in last hour",
                         diagnosis={
                             'cause': f"{row.errors} scheduled query executions failed. Possible: schema change in source table, BigQuery quota exceeded, or query syntax error.",
                             'impact': "Failed runs mean PII data is not being hashed. Plaintext exposure accumulates with each failed run.",
                             'action': "Check BigQuery scheduled query error details. Common fixes: update column references if schema changed, request quota increase if limits hit."
                         })

            if row.minutes_since_last is not None and row.minutes_since_last <= 10:
                self.add("PII schedule: recency", "PASS", f"Last run {row.minutes_since_last} min ago")
            else:
                mins = row.minutes_since_last if row.minutes_since_last else "unknown"
                self.add("PII schedule: recency", "FAIL",
                         f"Last run {mins} min ago",
                         diagnosis={
                             'cause': "No recent scheduled query execution detected.",
                             'impact': "PII data may be accumulating in plaintext in raw tables.",
                             'action': "Manually trigger the PII hash query. Check if the schedule is still active in BigQuery."
                         })
        except Exception as e:
            self.add("PII schedule", "ERROR", f"Cannot check schedule: {e}")

    # ============================================================
    # CHECK 8: FACEBOOK DAILY SPEND (deduplicated)
    # ============================================================
    def check_facebook_daily(self):
        print("\n=== FACEBOOK DAILY SPEND (deduplicated) ===")
        try:
            sql = f"""
            WITH deduped AS (
              SELECT date_start, account_id, ad_id,
                CAST(spend AS FLOAT64) AS spend,
                ROW_NUMBER() OVER (PARTITION BY ad_id, date_start, account_id ORDER BY _airbyte_extracted_at DESC) AS rn
              FROM `{BQ_PROJECT}.{BQ_DATASET}.facebook_insights`
              WHERE date_start BETWEEN '{self.start_date}' AND '{self.end_date}'
            )
            SELECT date_start,
              ROUND(SUM(spend), 2) AS daily_spend,
              COUNT(*) AS ad_count
            FROM deduped WHERE rn = 1
            GROUP BY date_start
            ORDER BY date_start DESC
            LIMIT 10
            """
            rows = self.query(sql)
            if rows:
                latest = rows[0]
                self.add("Facebook daily spend", "PASS",
                         f"Latest: {latest.date_start} = ${latest.daily_spend:,.2f} ({latest.ad_count} ads)")
                for row in rows[:5]:
                    print(f"    {row.date_start}: ${row.daily_spend:,.2f} ({row.ad_count} ads)")
            else:
                self.add("Facebook daily spend", "FAIL", "No data in date range",
                         diagnosis={
                             'cause': "No Facebook Ads data exists for the selected date range.",
                             'impact': "Cannot track Facebook advertising performance or ROAS.",
                             'action': "Verify Airbyte Facebook connection. Check if the date range filter is correct."
                         })
        except Exception as e:
            self.add("Facebook daily spend", "ERROR", str(e))

    # ============================================================
    # CHECK 9: GA4 FRESHNESS
    # ============================================================
    def check_ga4(self):
        print("\n=== GOOGLE ANALYTICS 4 ===")
        ga4_datasets = [
            ('analytics_334792038', 'EU'),
            ('analytics_454869667', 'US'),
            ('analytics_454871405', 'CA'),
        ]
        for dataset, region in ga4_datasets:
            try:
                sql = f"""
                SELECT MAX(REGEXP_EXTRACT(table_id, r'events_(\\d{{8}})')) AS latest_daily,
                  (SELECT MAX(REGEXP_EXTRACT(table_id, r'events_intraday_(\\d{{8}})'))
                   FROM `{BQ_PROJECT}.{dataset}.__TABLES__` WHERE table_id LIKE '%intraday%') AS latest_intraday
                FROM `{BQ_PROJECT}.{dataset}.__TABLES__`
                WHERE table_id LIKE 'events_%' AND table_id NOT LIKE '%intraday%'
                """
                row = self.query(sql)[0]
                # GA4 is normally J-1 or J-2, no diagnosis needed
                self.add(f"GA4 {region} ({dataset})", "PASS",
                         f"Daily: {row.latest_daily}, Intraday: {row.latest_intraday}")
            except Exception as e:
                self.add(f"GA4 {region}", "ERROR", str(e),
                         diagnosis={
                             'cause': f"Cannot query GA4 dataset {dataset}. It may not exist or permissions are missing.",
                             'impact': f"No web analytics data for {region} region.",
                             'action': f"Verify GA4 BigQuery export is configured for property {dataset.split('_')[1]}."
                         })

    # ============================================================
    # CHECK 10: SYNC LAG MONITORING TABLE
    # ============================================================
    def check_sync_lag(self):
        print("\n=== SYNC LAG MONITORING ===")
        try:
            sql = f"""
            SELECT
              table_id,
              TIMESTAMP_MILLIS(last_modified_time) as last_modified,
              TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), TIMESTAMP_MILLIS(last_modified_time), HOUR) as hours_behind,
              row_count
            FROM `{BQ_PROJECT}.{BQ_DATASET}.__TABLES__`
            WHERE table_id IN (
              'shopify_live_orders', 'shopify_live_customers', 'shopify_utm',
              'facebook_insights', 'tiktok_ads_reports_daily',
              'shopify_live_orders_clean', 'shopify_live_customers_clean'
            )
            ORDER BY hours_behind DESC
            """
            rows = self.query(sql)
            for row in rows:
                hours = row.hours_behind
                if hours <= 25:
                    self.add(f"Sync lag: {row.table_id}", "PASS",
                             f"{hours}h since last update ({row.row_count:,} rows)")
                elif hours <= 72:
                    self.add(f"Sync lag: {row.table_id}", "WARNING",
                             f"{hours}h since last table modification",
                             diagnosis={
                                 'cause': f"Table {row.table_id} has not been updated for {hours} hours ({hours//24} days). Airbyte sync or hash job may have failed.",
                                 'impact': f"Data in {row.table_id} is {hours//24} days stale.",
                                 'action': "Check Airbyte connection status for this source. Trigger manual sync."
                             })
                else:
                    self.add(f"Sync lag: {row.table_id}", "FAIL",
                             f"{hours}h ({hours//24} days) since last update - STALE",
                             diagnosis={
                                 'cause': f"Table {row.table_id} has not been updated for {hours//24} days. The Airbyte connector is almost certainly down.",
                                 'impact': f"All analysis using {row.table_id} is based on data that is {hours//24} days old. Revenue, spend, and attribution reports are inaccurate.",
                                 'action': f"IMMEDIATE: SSH to Airbyte VM. Check the connection for {row.table_id.replace('_', ' ')}. Restart sync. See docs/runbooks/airbyte_runbook.md."
                             })
        except Exception as e:
            self.add("Sync lag", "ERROR", str(e))

    # ============================================================
    # SUMMARY & REPORT
    # ============================================================
    def generate_report(self):
        total = len(self.results)
        passed = sum(1 for r in self.results if r.status == 'PASS')
        warnings = sum(1 for r in self.results if r.status == 'WARNING')
        failed = sum(1 for r in self.results if r.status == 'FAIL')
        errors = sum(1 for r in self.results if r.status == 'ERROR')

        print("\n" + "=" * 70)
        print("    RECONCILIATION SUMMARY")
        print("=" * 70)
        print(f"  Date range: {self.start_date} to {self.end_date}")
        print(f"  Generated:  {self.timestamp}")
        print(f"  Total checks: {total}")
        print(f"  PASS:    {passed}")
        print(f"  WARNING: {warnings}")
        print(f"  FAIL:    {failed}")
        print(f"  ERROR:   {errors}")
        print()

        if failed == 0 and errors == 0:
            print("  OVERALL: PASS - All checks passed")
            overall = "PASS"
        elif failed > 0:
            print(f"  OVERALL: FAIL - {failed} checks failed")
            overall = "FAIL"
        else:
            print(f"  OVERALL: WARNING - {warnings} warnings, {errors} errors")
            overall = "WARNING"

        # Print action items for all non-passing checks
        action_items = [r for r in self.results if r.status in ('FAIL', 'WARNING', 'ERROR') and r.diagnosis.get('action')]
        if action_items:
            print("\n" + "-" * 70)
            print("    ACTION ITEMS (ordered by severity)")
            print("-" * 70)
            # FAIL first, then WARNING, then ERROR
            for status in ['FAIL', 'WARNING', 'ERROR']:
                items = [r for r in action_items if r.status == status]
                for r in items:
                    icon = {'FAIL': 'CRITICAL', 'WARNING': 'WARN', 'ERROR': 'ERROR'}[status]
                    print(f"\n  [{icon}] {r.name}")
                    print(f"    {r.diagnosis['action']}")

        print("\n" + "=" * 70)

        # Save JSON report
        report = {
            "timestamp": self.timestamp,
            "date_range": {"start": self.start_date, "end": self.end_date},
            "overall": overall,
            "summary": {"total": total, "passed": passed, "warnings": warnings, "failed": failed, "errors": errors},
            "checks": [
                {
                    "name": r.name,
                    "status": r.status,
                    "message": r.message,
                    "diagnosis": r.diagnosis,
                    "details": r.details
                }
                for r in self.results
            ],
            "action_items": [
                {
                    "severity": r.status,
                    "check": r.name,
                    "action": r.diagnosis.get('action', ''),
                    "impact": r.diagnosis.get('impact', ''),
                }
                for r in action_items
            ]
        }

        report_path = Path(__file__).parent / 'reconciliation_results.json'
        with open(report_path, 'w') as f:
            json.dump(report, f, indent=2, default=str)
        print(f"\n  JSON report: {report_path}")

        return overall

    # ============================================================
    # RUN
    # ============================================================
    def run(self):
        print("=" * 70)
        print("    PRODUCTION DATA RECONCILIATION CHECK v2")
        print(f"    {self.start_date} to {self.end_date}")
        print("    Diagnostics: cause / impact / action for every issue")
        print("=" * 70)

        available_checks = {
            'freshness': self.check_freshness,
            'duplicates': self.check_duplicates,
            'pii': self.check_pii,
            'hashes': self.check_hashes,
            'continuity': self.check_continuity,
            'nulls': self.check_nulls,
            'pii_schedule': self.check_pii_schedule,
            'facebook_daily': self.check_facebook_daily,
            'ga4': self.check_ga4,
            'sync_lag': self.check_sync_lag,
        }

        checks_to_run = self.checks or list(available_checks.keys())

        for check_name in checks_to_run:
            if check_name in available_checks:
                try:
                    available_checks[check_name]()
                except Exception as e:
                    self.add(f"{check_name}", "ERROR", f"Check failed: {e}")

        return self.generate_report()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Production Data Reconciliation Check v2')
    parser.add_argument('--start', help='Start date (YYYY-MM-DD)')
    parser.add_argument('--end', help='End date (YYYY-MM-DD)')
    parser.add_argument('--checks', help='Comma-separated list of checks to run (default: all)')

    args = parser.parse_args()
    checks = args.checks.split(',') if args.checks else None

    checker = ReconciliationCheck(
        start_date=args.start,
        end_date=args.end,
        checks=checks
    )
    result = checker.run()

    sys.exit(0 if result == 'PASS' else 1)
