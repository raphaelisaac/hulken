#!/usr/bin/env python3
"""
SOC (System of Controls) Validation Checks
Data integrity, format, and freshness validation functions.
"""

import os
from datetime import datetime, timedelta
from dataclasses import dataclass
from typing import List, Optional, Dict, Any
import pandas as pd
from google.cloud import bigquery
from dotenv import load_dotenv

# Import configuration
from config import (
    THRESHOLDS,
    BQ_PROJECT,
    BQ_DATASET,
    TABLES,
    PLATFORMS,
    STATUS,
    REPORT_SETTINGS
)

load_dotenv()

# Set up BigQuery credentials
os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = os.getenv(
    'GOOGLE_APPLICATION_CREDENTIALS',
    'D:/Better_signal/hulken-fb56a345ac08.json'
)


@dataclass
class SOCResult:
    """Result of a SOC check"""
    check_name: str
    status: str  # PASS, WARNING, CRITICAL, ERROR
    message: str
    details: Optional[Dict[str, Any]] = None

    def to_dict(self):
        return {
            "check_name": self.check_name,
            "status": self.status,
            "message": self.message,
            "details": self.details or {}
        }


class SOCValidator:
    """SOC validation checks for data quality"""

    def __init__(self):
        self.bq_client = bigquery.Client(project=BQ_PROJECT)
        self.results: List[SOCResult] = []

    # ============================================================
    # PRICE FORMAT VALIDATION
    # ============================================================

    def check_price_format(
        self,
        platform: str = "shopify",
        start_date: str = None,
        end_date: str = None
    ) -> SOCResult:
        """
        Detect if prices might be in cents instead of dollars.

        Logic:
        - If median price > $1000, likely cents error
        - If any single order > $10,000, flag as warning
        - If any single order > $100,000, flag as critical
        """
        check_name = f"Price Format Validation ({platform})"

        if platform not in PLATFORMS:
            return SOCResult(
                check_name=check_name,
                status="ERROR",
                message=f"Unknown platform: {platform}"
            )

        config = PLATFORMS[platform]

        # Only check platforms with price fields
        if "price_field" not in config:
            return SOCResult(
                check_name=check_name,
                status="PASS",
                message=f"No price field for {platform} - skipping"
            )

        table = TABLES.get(config["tables"][0])
        price_field = config["price_field"]
        date_field = config["date_field"]

        # Build date filter
        date_filter = ""
        if start_date and end_date:
            date_filter = f"WHERE DATE({date_field}) BETWEEN '{start_date}' AND '{end_date}'"

        query = f"""
        SELECT
            {price_field} as price,
            COUNT(*) OVER() as total_count,
            PERCENTILE_CONT({price_field}, 0.5) OVER() as median_price,
            MAX({price_field}) OVER() as max_price
        FROM `{table}`
        {date_filter}
        LIMIT 1000
        """

        try:
            df = self.bq_client.query(query).to_dataframe()

            if df.empty:
                return SOCResult(
                    check_name=check_name,
                    status="WARNING",
                    message="No price data found for the specified period"
                )

            median_price = df['median_price'].iloc[0]
            max_price = df['max_price'].iloc[0]

            # Count suspicious prices
            suspicious_count = len(df[df['price'] > THRESHOLDS['price_anomaly']['warning']])
            critical_count = len(df[df['price'] > THRESHOLDS['price_anomaly']['critical']])

            details = {
                "median_price": float(median_price) if median_price else 0,
                "max_price": float(max_price) if max_price else 0,
                "suspicious_count": suspicious_count,
                "critical_count": critical_count
            }

            # Check for cents error (median > $1000 is suspicious)
            if median_price and median_price > THRESHOLDS['price_anomaly']['median_threshold']:
                return SOCResult(
                    check_name=check_name,
                    status="CRITICAL",
                    message=f"Prices may be in CENTS. Median: ${median_price:,.2f}",
                    details=details
                )

            # Check for critical anomalies
            if critical_count > 0:
                return SOCResult(
                    check_name=check_name,
                    status="CRITICAL",
                    message=f"{critical_count} orders exceed ${THRESHOLDS['price_anomaly']['critical']:,}",
                    details=details
                )

            # Check for warning anomalies
            if suspicious_count > 0:
                return SOCResult(
                    check_name=check_name,
                    status="WARNING",
                    message=f"{suspicious_count} orders exceed ${THRESHOLDS['price_anomaly']['warning']:,}",
                    details=details
                )

            return SOCResult(
                check_name=check_name,
                status="PASS",
                message=f"Price format OK. Median: ${median_price:,.2f}",
                details=details
            )

        except Exception as e:
            return SOCResult(
                check_name=check_name,
                status="ERROR",
                message=f"Query failed: {str(e)}"
            )

    # ============================================================
    # DUPLICATE DETECTION
    # ============================================================

    def check_duplicates(
        self,
        platform: str = "shopify",
        start_date: str = None,
        end_date: str = None
    ) -> SOCResult:
        """
        Detect duplicate records by primary key.
        """
        check_name = f"Duplicate Detection ({platform})"

        if platform not in PLATFORMS:
            return SOCResult(
                check_name=check_name,
                status="ERROR",
                message=f"Unknown platform: {platform}"
            )

        config = PLATFORMS[platform]
        table = TABLES.get(config["tables"][0])
        primary_key = config["primary_key"]
        date_field = config["date_field"]

        # Build date filter
        date_filter = ""
        if start_date and end_date:
            date_filter = f"WHERE DATE({date_field}) BETWEEN '{start_date}' AND '{end_date}'"

        query = f"""
        WITH counts AS (
            SELECT
                {primary_key},
                COUNT(*) as cnt
            FROM `{table}`
            {date_filter}
            GROUP BY {primary_key}
            HAVING COUNT(*) > 1
        )
        SELECT
            COUNT(*) as duplicate_keys,
            SUM(cnt) as total_duplicate_rows,
            (SELECT COUNT(*) FROM `{table}` {date_filter}) as total_rows
        FROM counts
        """

        try:
            result = list(self.bq_client.query(query).result())[0]

            duplicate_keys = result.duplicate_keys or 0
            total_duplicate_rows = result.total_duplicate_rows or 0
            total_rows = result.total_rows or 0

            if total_rows == 0:
                return SOCResult(
                    check_name=check_name,
                    status="WARNING",
                    message="No data found for the specified period"
                )

            duplicate_rate = (duplicate_keys / total_rows * 100) if total_rows > 0 else 0

            details = {
                "duplicate_keys": duplicate_keys,
                "total_duplicate_rows": total_duplicate_rows,
                "total_rows": total_rows,
                "duplicate_rate_pct": round(duplicate_rate, 4)
            }

            if duplicate_rate > THRESHOLDS['duplicate_rate']['critical']:
                return SOCResult(
                    check_name=check_name,
                    status="CRITICAL",
                    message=f"High duplicate rate: {duplicate_rate:.2f}% ({duplicate_keys:,} keys)",
                    details=details
                )

            if duplicate_rate > THRESHOLDS['duplicate_rate']['warning']:
                return SOCResult(
                    check_name=check_name,
                    status="WARNING",
                    message=f"Duplicate rate: {duplicate_rate:.2f}% ({duplicate_keys:,} keys)",
                    details=details
                )

            return SOCResult(
                check_name=check_name,
                status="PASS",
                message=f"No significant duplicates. Rate: {duplicate_rate:.4f}%",
                details=details
            )

        except Exception as e:
            return SOCResult(
                check_name=check_name,
                status="ERROR",
                message=f"Query failed: {str(e)}"
            )

    # ============================================================
    # NULL RATE MONITORING
    # ============================================================

    def check_null_rates(
        self,
        platform: str = "shopify",
        start_date: str = None,
        end_date: str = None,
        critical_fields: List[str] = None
    ) -> SOCResult:
        """
        Monitor NULL percentage for critical fields.
        """
        check_name = f"Null Rate Monitoring ({platform})"

        if platform not in PLATFORMS:
            return SOCResult(
                check_name=check_name,
                status="ERROR",
                message=f"Unknown platform: {platform}"
            )

        config = PLATFORMS[platform]
        table = TABLES.get(config["tables"][0])
        date_field = config["date_field"]

        # Default critical fields by platform
        if critical_fields is None:
            if platform == "shopify":
                critical_fields = ["orderId", "totalPrice", "email", "createdAt"]
            elif platform == "facebook":
                critical_fields = ["ad_id", "spend", "impressions", "date_start"]
            elif platform == "tiktok":
                critical_fields = ["ad_id", "report_date"]
            else:
                critical_fields = [config["primary_key"]]

        # Build date filter
        date_filter = ""
        if start_date and end_date:
            date_filter = f"WHERE DATE({date_field}) BETWEEN '{start_date}' AND '{end_date}'"

        # Build null count query for each field
        null_checks = ", ".join([
            f"COUNTIF({f} IS NULL) as null_{f.replace('.', '_')}"
            for f in critical_fields
        ])

        query = f"""
        SELECT
            COUNT(*) as total_rows,
            {null_checks}
        FROM `{table}`
        {date_filter}
        """

        try:
            result = list(self.bq_client.query(query).result())[0]
            total_rows = result.total_rows

            if total_rows == 0:
                return SOCResult(
                    check_name=check_name,
                    status="WARNING",
                    message="No data found for the specified period"
                )

            null_rates = {}
            max_null_rate = 0
            worst_field = None

            for field in critical_fields:
                null_count = getattr(result, f"null_{field.replace('.', '_')}", 0)
                rate = (null_count / total_rows * 100) if total_rows > 0 else 0
                null_rates[field] = {
                    "null_count": null_count,
                    "rate_pct": round(rate, 2)
                }
                if rate > max_null_rate:
                    max_null_rate = rate
                    worst_field = field

            details = {
                "total_rows": total_rows,
                "null_rates": null_rates,
                "max_null_rate": max_null_rate,
                "worst_field": worst_field
            }

            if max_null_rate > THRESHOLDS['null_rate']['critical']:
                return SOCResult(
                    check_name=check_name,
                    status="CRITICAL",
                    message=f"Critical NULL rate in '{worst_field}': {max_null_rate:.1f}%",
                    details=details
                )

            if max_null_rate > THRESHOLDS['null_rate']['warning']:
                return SOCResult(
                    check_name=check_name,
                    status="WARNING",
                    message=f"High NULL rate in '{worst_field}': {max_null_rate:.1f}%",
                    details=details
                )

            return SOCResult(
                check_name=check_name,
                status="PASS",
                message=f"NULL rates acceptable. Max: {max_null_rate:.1f}% in '{worst_field}'",
                details=details
            )

        except Exception as e:
            return SOCResult(
                check_name=check_name,
                status="ERROR",
                message=f"Query failed: {str(e)}"
            )

    # ============================================================
    # DATA FRESHNESS
    # ============================================================

    def check_data_freshness(
        self,
        platform: str = "shopify"
    ) -> SOCResult:
        """
        Verify recent data exists and check sync lag.
        """
        check_name = f"Data Freshness ({platform})"

        if platform not in PLATFORMS:
            return SOCResult(
                check_name=check_name,
                status="ERROR",
                message=f"Unknown platform: {platform}"
            )

        config = PLATFORMS[platform]
        table = TABLES.get(config["tables"][0])
        date_field = config["date_field"]

        query = f"""
        SELECT
            MAX({date_field}) as latest_record,
            MIN({date_field}) as earliest_record,
            COUNT(*) as total_records,
            TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX({date_field}), HOUR) as hours_since_last
        FROM `{table}`
        """

        try:
            result = list(self.bq_client.query(query).result())[0]

            latest_record = result.latest_record
            hours_since_last = result.hours_since_last or 0
            total_records = result.total_records or 0

            if total_records == 0:
                return SOCResult(
                    check_name=check_name,
                    status="CRITICAL",
                    message="No data found in table",
                    details={"total_records": 0}
                )

            details = {
                "latest_record": str(latest_record) if latest_record else None,
                "earliest_record": str(result.earliest_record) if result.earliest_record else None,
                "total_records": total_records,
                "hours_since_last": hours_since_last
            }

            if hours_since_last > THRESHOLDS['sync_lag']['critical']:
                return SOCResult(
                    check_name=check_name,
                    status="CRITICAL",
                    message=f"Data is {hours_since_last} hours old (>{THRESHOLDS['sync_lag']['critical']}h)",
                    details=details
                )

            if hours_since_last > THRESHOLDS['sync_lag']['warning']:
                return SOCResult(
                    check_name=check_name,
                    status="WARNING",
                    message=f"Data is {hours_since_last} hours old",
                    details=details
                )

            return SOCResult(
                check_name=check_name,
                status="PASS",
                message=f"Data is fresh. Last record: {hours_since_last}h ago",
                details=details
            )

        except Exception as e:
            return SOCResult(
                check_name=check_name,
                status="ERROR",
                message=f"Query failed: {str(e)}"
            )

    # ============================================================
    # RECORD COUNT COMPARISON
    # ============================================================

    def check_record_count(
        self,
        platform: str = "shopify",
        start_date: str = None,
        end_date: str = None
    ) -> SOCResult:
        """
        Get record count for a date range.
        """
        check_name = f"Record Count ({platform})"

        if platform not in PLATFORMS:
            return SOCResult(
                check_name=check_name,
                status="ERROR",
                message=f"Unknown platform: {platform}"
            )

        config = PLATFORMS[platform]
        table = TABLES.get(config["tables"][0])
        date_field = config["date_field"]

        date_filter = ""
        if start_date and end_date:
            date_filter = f"WHERE DATE({date_field}) BETWEEN '{start_date}' AND '{end_date}'"

        query = f"""
        SELECT
            COUNT(*) as total_count,
            COUNT(DISTINCT DATE({date_field})) as unique_days
        FROM `{table}`
        {date_filter}
        """

        try:
            result = list(self.bq_client.query(query).result())[0]

            details = {
                "total_count": result.total_count,
                "unique_days": result.unique_days,
                "date_range": f"{start_date} to {end_date}" if start_date else "all time"
            }

            if result.total_count == 0:
                return SOCResult(
                    check_name=check_name,
                    status="WARNING",
                    message="No records found for the specified period",
                    details=details
                )

            return SOCResult(
                check_name=check_name,
                status="PASS",
                message=f"{result.total_count:,} records across {result.unique_days} days",
                details=details
            )

        except Exception as e:
            return SOCResult(
                check_name=check_name,
                status="ERROR",
                message=f"Query failed: {str(e)}"
            )

    # ============================================================
    # RUN ALL CHECKS
    # ============================================================

    def run_all_checks(
        self,
        platforms: List[str] = None,
        start_date: str = None,
        end_date: str = None
    ) -> List[SOCResult]:
        """
        Run all SOC checks for specified platforms.
        """
        if platforms is None:
            platforms = ["shopify", "facebook", "tiktok"]

        self.results = []

        for platform in platforms:
            # Skip disabled platforms
            if platform in PLATFORMS and not PLATFORMS[platform].get("enabled", True):
                continue

            # Run all checks
            self.results.append(self.check_price_format(platform, start_date, end_date))
            self.results.append(self.check_duplicates(platform, start_date, end_date))
            self.results.append(self.check_null_rates(platform, start_date, end_date))
            self.results.append(self.check_data_freshness(platform))
            self.results.append(self.check_record_count(platform, start_date, end_date))

        return self.results

    def get_summary(self) -> Dict[str, Any]:
        """Get summary of all check results."""
        summary = {
            "total_checks": len(self.results),
            "passed": len([r for r in self.results if r.status == "PASS"]),
            "warnings": len([r for r in self.results if r.status == "WARNING"]),
            "critical": len([r for r in self.results if r.status == "CRITICAL"]),
            "errors": len([r for r in self.results if r.status == "ERROR"]),
            "results": [r.to_dict() for r in self.results]
        }

        # Overall status
        if summary["critical"] > 0:
            summary["overall_status"] = "CRITICAL"
        elif summary["warnings"] > 0:
            summary["overall_status"] = "WARNING"
        elif summary["errors"] > 0:
            summary["overall_status"] = "ERROR"
        else:
            summary["overall_status"] = "PASS"

        return summary


# ============================================================
# STANDALONE FUNCTIONS (for direct import)
# ============================================================

def check_price_format(platform: str = "shopify", start_date: str = None, end_date: str = None) -> SOCResult:
    """Standalone price format check."""
    validator = SOCValidator()
    return validator.check_price_format(platform, start_date, end_date)


def check_duplicates(platform: str = "shopify", start_date: str = None, end_date: str = None) -> SOCResult:
    """Standalone duplicate detection."""
    validator = SOCValidator()
    return validator.check_duplicates(platform, start_date, end_date)


def check_null_rates(platform: str = "shopify", start_date: str = None, end_date: str = None) -> SOCResult:
    """Standalone null rate check."""
    validator = SOCValidator()
    return validator.check_null_rates(platform, start_date, end_date)


def check_data_freshness(platform: str = "shopify") -> SOCResult:
    """Standalone data freshness check."""
    validator = SOCValidator()
    return validator.check_data_freshness(platform)


if __name__ == "__main__":
    # Run checks for all platforms
    print("=" * 60)
    print("    SOC VALIDATION CHECKS")
    print("=" * 60)

    validator = SOCValidator()
    results = validator.run_all_checks()

    for result in results:
        status_icon = {
            "PASS": "[OK]",
            "WARNING": "[WARN]",
            "CRITICAL": "[CRIT]",
            "ERROR": "[ERR]"
        }.get(result.status, "[?]")

        print(f"\n{status_icon} {result.check_name}")
        print(f"    {result.message}")

    print("\n" + "=" * 60)
    summary = validator.get_summary()
    print(f"SUMMARY: {summary['passed']} passed, {summary['warnings']} warnings, "
          f"{summary['critical']} critical, {summary['errors']} errors")
    print(f"OVERALL: {summary['overall_status']}")
    print("=" * 60)
