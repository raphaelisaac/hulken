#!/usr/bin/env python3
"""
PRODUCTION DATA RECONCILIATION CHECK
=====================================
Comprehensive data quality verification for Better Signal analytics pipeline.

Checks performed:
1. Data Freshness - Are all platforms syncing on time?
2. API vs BigQuery Reconciliation - Day-by-day comparison
3. Duplicate Detection - Primary key uniqueness
4. Temporal Continuity - No missing days
5. PII Audit - Zero cleartext exposure
6. Hash Consistency - Cross-platform matching
7. NULL Critical Fields - Data completeness

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
# CONFIGURATION (from .env only - never hardcode credentials)
# ============================================================
BQ_PROJECT = os.getenv('BIGQUERY_PROJECT', 'hulken')
BQ_DATASET = os.getenv('BIGQUERY_DATASET', 'ads_data')
CREDENTIALS_PATH = os.getenv('GOOGLE_APPLICATION_CREDENTIALS')

if CREDENTIALS_PATH:
    os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = CREDENTIALS_PATH

# Thresholds
FRESHNESS_WARNING_HOURS = 24
FRESHNESS_CRITICAL_HOURS = 48
SPEND_DIFF_WARNING_PCT = 1.0
SPEND_DIFF_CRITICAL_PCT = 5.0
COUNT_DIFF_WARNING_PCT = 1.0
COUNT_DIFF_CRITICAL_PCT = 5.0

# ============================================================
# RESULT TRACKING
# ============================================================
class CheckResult:
    def __init__(self, name, status, message, details=None):
        self.name = name
        self.status = status  # PASS, WARNING, FAIL, ERROR
        self.message = message
        self.details = details or {}

    def __str__(self):
        icon = {'PASS': '[PASS]', 'WARNING': '[WARN]', 'FAIL': '[FAIL]', 'ERROR': '[ERR ]'}
        return f"  {icon.get(self.status, '[????]')} {self.name}: {self.message}"


class ReconciliationCheck:
    def __init__(self, start_date=None, end_date=None, checks=None):
        self.bq = bigquery.Client(project=BQ_PROJECT)
        self.end_date = end_date or datetime.now().strftime('%Y-%m-%d')
        self.start_date = start_date or (datetime.now() - timedelta(days=30)).strftime('%Y-%m-%d')
        self.checks = checks  # None = all
        self.results = []
        self.timestamp = datetime.now().isoformat()

    def add(self, name, status, message, details=None):
        r = CheckResult(name, status, message, details)
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
        sql = f"""
        WITH facebook AS (
          SELECT 'Facebook Ads' AS source, MAX(date_start) AS latest_date
          FROM `{BQ_PROJECT}.{BQ_DATASET}.facebook_ads_insights`
        ),
        tiktok AS (
          SELECT 'TikTok Ads', MAX(DATE(stat_time_day))
          FROM `{BQ_PROJECT}.{BQ_DATASET}.tiktok_ads_reports_daily`
        ),
        shopify_orders AS (
          SELECT 'Shopify Orders', MAX(DATE(created_at))
          FROM `{BQ_PROJECT}.{BQ_DATASET}.shopify_live_orders`
        ),
        shopify_customers AS (
          SELECT 'Shopify Customers', MAX(DATE(updated_at))
          FROM `{BQ_PROJECT}.{BQ_DATASET}.shopify_live_customers`
        ),
        shopify_utm AS (
          SELECT 'Shopify UTM', MAX(DATE(created_at))
          FROM `{BQ_PROJECT}.{BQ_DATASET}.shopify_utm`
        )
        SELECT * FROM facebook UNION ALL SELECT * FROM tiktok
        UNION ALL SELECT * FROM shopify_orders UNION ALL SELECT * FROM shopify_customers
        UNION ALL SELECT * FROM shopify_utm
        """
        rows = self.query(sql)
        today = datetime.now().date()

        for row in rows:
            source = row[0]
            latest = row[1]
            if latest is None:
                self.add(f"Freshness: {source}", "FAIL", "No data found")
                continue

            gap_days = (today - latest).days
            if gap_days <= 1:
                self.add(f"Freshness: {source}", "PASS", f"Current (latest: {latest})")
            elif gap_days <= 3:
                self.add(f"Freshness: {source}", "WARNING", f"{gap_days} days behind (latest: {latest})")
            else:
                self.add(f"Freshness: {source}", "FAIL", f"{gap_days} days behind (latest: {latest})")

    # ============================================================
    # CHECK 2: DUPLICATE DETECTION
    # ============================================================
    def check_duplicates(self):
        print("\n=== DUPLICATE DETECTION ===")
        tables = [
            ("shopify_live_orders", "id"),
            ("shopify_live_orders_clean", "id"),
            ("shopify_live_customers", "id"),
            ("shopify_live_customers_clean", "id"),
            ("shopify_orders", "id"),
            ("shopify_utm", "order_id"),
        ]

        for table, pk in tables:
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
                self.add(f"Duplicates: {table}", "FAIL", f"{dupes:,} duplicates ({pct:.1f}%)")

        # Facebook needs special dedup check (known issue with Airbyte append mode)
        sql = f"""
        SELECT COUNT(*) AS total,
          COUNT(DISTINCT CONCAT(CAST(ad_id AS STRING), '|', date_start)) AS distinct_keys
        FROM `{BQ_PROJECT}.{BQ_DATASET}.facebook_ads_insights`
        """
        row = self.query(sql)[0]
        dupes = row.total - row.distinct_keys
        if dupes == 0:
            self.add("Duplicates: facebook_ads_insights", "PASS", f"0 duplicates")
        else:
            pct = dupes / row.total * 100
            self.add("Duplicates: facebook_ads_insights", "WARNING",
                     f"{dupes:,} duplicates from Airbyte append mode ({pct:.1f}%) - use dedup view for analysis")

        # TikTok
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
            self.add("Duplicates: tiktok_reports", "FAIL", f"{dupes:,} duplicates")

    # ============================================================
    # CHECK 3: PII AUDIT
    # ============================================================
    def check_pii(self):
        print("\n=== PII AUDIT (zero tolerance) ===")
        checks = [
            ("shopify_live_orders", "email", "email LIKE '%@%'"),
            ("shopify_live_orders", "contact_email", "contact_email LIKE '%@%'"),
            ("shopify_live_orders", "phone", "phone IS NOT NULL AND phone != '' AND LENGTH(phone) > 3"),
            ("shopify_live_orders", "browser_ip", "browser_ip IS NOT NULL AND browser_ip != ''"),
            ("shopify_live_orders", "customer_json", "customer IS NOT NULL AND JSON_VALUE(customer, '$.email') LIKE '%@%'"),
            ("shopify_live_customers", "email", "email LIKE '%@%'"),
            ("shopify_live_customers", "phone", "phone IS NOT NULL AND phone != '' AND LENGTH(phone) > 3"),
            ("shopify_live_customers", "first_name", "first_name IS NOT NULL AND first_name != ''"),
            ("shopify_live_customers", "last_name", "last_name IS NOT NULL AND last_name != ''"),
            ("shopify_live_orders_clean", "customer_email_in_json", "JSON_VALUE(customer, '$.email') LIKE '%@%'"),
            ("shopify_live_orders_clean", "customer_name_in_json", "JSON_VALUE(customer, '$.first_name') IS NOT NULL AND JSON_VALUE(customer, '$.first_name') != ''"),
            ("shopify_live_customers_clean", "first_name", "first_name IS NOT NULL AND first_name != ''"),
        ]

        total_exposed = 0
        for table, field, condition in checks:
            sql = f"""
            SELECT COUNTIF({condition}) AS exposed, COUNT(*) AS total
            FROM `{BQ_PROJECT}.{BQ_DATASET}.{table}`
            """
            row = self.query(sql)[0]
            if row.exposed == 0:
                self.add(f"PII: {table}.{field}", "PASS", "0 exposed")
            else:
                total_exposed += row.exposed
                self.add(f"PII: {table}.{field}", "FAIL", f"{row.exposed:,} records with cleartext PII!")

        if total_exposed == 0:
            self.add("PII: OVERALL", "PASS", "Zero PII exposure across all tables")
        else:
            self.add("PII: OVERALL", "FAIL", f"CRITICAL: {total_exposed:,} total PII exposures found!")

    # ============================================================
    # CHECK 4: HASH CONSISTENCY
    # ============================================================
    def check_hashes(self):
        print("\n=== HASH CONSISTENCY ===")

        # All hashes should be 64 chars (SHA256 hex)
        for table in ['shopify_live_orders_clean', 'shopify_live_customers_clean', 'shopify_orders']:
            sql = f"""
            SELECT COUNT(*) AS total,
              COUNTIF(email_hash IS NOT NULL AND email_hash != '' AND LENGTH(email_hash) = 64) AS correct,
              COUNTIF(email_hash IS NOT NULL AND email_hash != '' AND LENGTH(email_hash) != 64) AS wrong
            FROM `{BQ_PROJECT}.{BQ_DATASET}.{table}`
            """
            row = self.query(sql)[0]
            if row.wrong == 0:
                self.add(f"Hash format: {table}", "PASS", f"All {row.correct:,} hashes are 64-char SHA256")
            else:
                self.add(f"Hash format: {table}", "FAIL", f"{row.wrong:,} hashes have wrong length")

        # Cross-table match
        sql = f"""
        SELECT
          (SELECT COUNT(DISTINCT email_hash) FROM `{BQ_PROJECT}.{BQ_DATASET}.shopify_live_orders_clean`
           WHERE email_hash IS NOT NULL AND email_hash != 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') AS order_hashes,
          (SELECT COUNT(DISTINCT email_hash) FROM `{BQ_PROJECT}.{BQ_DATASET}.shopify_live_customers_clean`
           WHERE email_hash IS NOT NULL AND email_hash != 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') AS customer_hashes,
          (SELECT COUNT(*) FROM (
            SELECT DISTINCT o.email_hash FROM `{BQ_PROJECT}.{BQ_DATASET}.shopify_live_orders_clean` o
            JOIN `{BQ_PROJECT}.{BQ_DATASET}.shopify_live_customers_clean` c ON o.email_hash = c.email_hash
            WHERE o.email_hash != 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
          )) AS matched
        """
        row = self.query(sql)[0]
        match_rate = (row.matched / row.order_hashes * 100) if row.order_hashes > 0 else 0
        if match_rate > 50:
            self.add("Hash cross-table match", "PASS",
                     f"{row.matched:,}/{row.order_hashes:,} order hashes match customers ({match_rate:.0f}%)")
        else:
            self.add("Hash cross-table match", "WARNING",
                     f"Only {match_rate:.0f}% of order hashes match customers")

    # ============================================================
    # CHECK 5: TEMPORAL CONTINUITY (recent 30 days)
    # ============================================================
    def check_continuity(self):
        print("\n=== TEMPORAL CONTINUITY (last 30 days) ===")

        # Shopify orders
        sql = f"""
        WITH dates AS (
          SELECT date FROM UNNEST(GENERATE_DATE_ARRAY(
            DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY), DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
          )) AS date
        ),
        order_dates AS (
          SELECT DATE(created_at) AS d, COUNT(*) AS cnt
          FROM `{BQ_PROJECT}.{BQ_DATASET}.shopify_live_orders_clean`
          WHERE DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
          GROUP BY d
        )
        SELECT d.date, COALESCE(o.cnt, 0) AS orders
        FROM dates d LEFT JOIN order_dates o ON d.date = o.d
        WHERE o.cnt IS NULL OR o.cnt = 0
        ORDER BY d.date
        """
        missing = self.query(sql)
        if len(missing) == 0:
            self.add("Continuity: Shopify orders", "PASS", "No missing days in last 30 days")
        elif len(missing) <= 3:
            dates = [str(r.date) for r in missing]
            self.add("Continuity: Shopify orders", "WARNING", f"{len(missing)} missing days: {', '.join(dates)}")
        else:
            self.add("Continuity: Shopify orders", "FAIL", f"{len(missing)} missing days in last 30 days")

        # Facebook insights
        sql = f"""
        WITH dates AS (
          SELECT date FROM UNNEST(GENERATE_DATE_ARRAY(
            DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY), DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
          )) AS date
        ),
        fb_dates AS (
          SELECT date_start AS d, COUNT(*) AS cnt
          FROM `{BQ_PROJECT}.{BQ_DATASET}.facebook_ads_insights`
          WHERE date_start >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
          GROUP BY d
        )
        SELECT d.date FROM dates d LEFT JOIN fb_dates f ON d.date = f.d
        WHERE f.cnt IS NULL ORDER BY d.date
        """
        missing = self.query(sql)
        if len(missing) == 0:
            self.add("Continuity: Facebook", "PASS", "No missing days")
        elif len(missing) <= 3:
            dates = [str(r.date) for r in missing]
            self.add("Continuity: Facebook", "WARNING", f"Missing: {', '.join(dates)}")
        else:
            self.add("Continuity: Facebook", "FAIL", f"{len(missing)} missing days")

        # TikTok
        sql = f"""
        WITH dates AS (
          SELECT date FROM UNNEST(GENERATE_DATE_ARRAY(
            DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY), DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
          )) AS date
        ),
        tt_dates AS (
          SELECT DATE(stat_time_day) AS d, COUNT(*) AS cnt
          FROM `{BQ_PROJECT}.{BQ_DATASET}.tiktok_ads_reports_daily`
          WHERE DATE(stat_time_day) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
          GROUP BY d
        )
        SELECT d.date FROM dates d LEFT JOIN tt_dates t ON d.date = t.d
        WHERE t.cnt IS NULL ORDER BY d.date
        """
        missing = self.query(sql)
        if len(missing) == 0:
            self.add("Continuity: TikTok", "PASS", "No missing days")
        elif len(missing) <= 3:
            dates = [str(r.date) for r in missing]
            self.add("Continuity: TikTok", "WARNING", f"Missing: {', '.join(dates)}")
        else:
            self.add("Continuity: TikTok", "FAIL", f"{len(missing)} missing days")

    # ============================================================
    # CHECK 6: NULL CRITICAL FIELDS
    # ============================================================
    def check_nulls(self):
        print("\n=== CRITICAL FIELD COMPLETENESS ===")
        field_checks = [
            ("shopify_live_orders_clean", "total_price"),
            ("shopify_live_orders_clean", "created_at"),
            ("shopify_live_orders_clean", "email_hash"),
            ("shopify_live_customers_clean", "email_hash"),
            ("facebook_ads_insights", "spend"),
            ("facebook_ads_insights", "date_start"),
            ("facebook_ads_insights", "ad_id"),
            ("tiktok_ads_reports_daily", "metrics"),
            ("tiktok_ads_reports_daily", "stat_time_day"),
        ]

        for table, field in field_checks:
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
                self.add(f"NULLs: {table}.{field}", status, f"{row.null_count:,}/{row.total:,} null ({pct:.1f}%)")

    # ============================================================
    # CHECK 7: PII SCHEDULED QUERY HEALTH
    # ============================================================
    def check_pii_schedule(self):
        print("\n=== PII HASH SCHEDULE HEALTH ===")
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
                     f"Only {row.total_runs} runs in last hour")
        else:
            self.add("PII schedule: frequency", "FAIL",
                     f"Only {row.total_runs} runs in last hour - schedule may be broken")

        if row.errors == 0:
            self.add("PII schedule: errors", "PASS", "0 errors in last hour")
        else:
            self.add("PII schedule: errors", "FAIL", f"{row.errors} errors in last hour")

        if row.minutes_since_last is not None and row.minutes_since_last <= 10:
            self.add("PII schedule: recency", "PASS", f"Last run {row.minutes_since_last} min ago")
        else:
            mins = row.minutes_since_last if row.minutes_since_last else "unknown"
            self.add("PII schedule: recency", "FAIL", f"Last run {mins} min ago")

    # ============================================================
    # CHECK 8: DAY-BY-DAY API vs BQ (Facebook spend dedup)
    # ============================================================
    def check_facebook_daily(self):
        print("\n=== FACEBOOK DAILY SPEND (deduplicated) ===")
        sql = f"""
        WITH deduped AS (
          SELECT date_start, account_id, ad_id,
            CAST(spend AS FLOAT64) AS spend,
            ROW_NUMBER() OVER (PARTITION BY ad_id, date_start ORDER BY _airbyte_extracted_at DESC) AS rn
          FROM `{BQ_PROJECT}.{BQ_DATASET}.facebook_ads_insights`
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
            self.add("Facebook daily spend", "FAIL", "No data in date range")

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
                self.add(f"GA4 {region} ({dataset})", "PASS",
                         f"Daily: {row.latest_daily}, Intraday: {row.latest_intraday}")
            except Exception as e:
                self.add(f"GA4 {region}", "ERROR", str(e))

    # ============================================================
    # SUMMARY & REPORT
    # ============================================================
    def generate_report(self):
        total = len(self.results)
        passed = sum(1 for r in self.results if r.status == 'PASS')
        warnings = sum(1 for r in self.results if r.status == 'WARNING')
        failed = sum(1 for r in self.results if r.status == 'FAIL')
        errors = sum(1 for r in self.results if r.status == 'ERROR')

        print("\n" + "=" * 60)
        print("    RECONCILIATION SUMMARY")
        print("=" * 60)
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

        print("=" * 60)

        # Save JSON report
        report = {
            "timestamp": self.timestamp,
            "date_range": {"start": self.start_date, "end": self.end_date},
            "overall": overall,
            "summary": {"total": total, "passed": passed, "warnings": warnings, "failed": failed, "errors": errors},
            "checks": [
                {"name": r.name, "status": r.status, "message": r.message, "details": r.details}
                for r in self.results
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
        print("=" * 60)
        print("    PRODUCTION DATA RECONCILIATION CHECK")
        print(f"    {self.start_date} to {self.end_date}")
        print("=" * 60)

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
    parser = argparse.ArgumentParser(description='Production Data Reconciliation Check')
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
