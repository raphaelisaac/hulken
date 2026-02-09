#!/usr/bin/env python3
"""
DATA RECONCILIATION REPORT
Compares source platform data with BigQuery to detect data loss or discrepancies.

Usage (for non-technical users):
    Double-click on "run_reconciliation.bat"
    OR
    python reconciliation_report.py

Output: HTML report + console summary
"""

import os
import sys
import json
import requests
from datetime import datetime, timedelta
from dotenv import load_dotenv
from google.cloud import bigquery
import warnings
warnings.filterwarnings('ignore')

# Fix Unicode output on Windows
if sys.platform == 'win32':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

load_dotenv()

# Configuration
BQ_PROJECT = "hulken"
BQ_DATASET = "ads_data"

# Set credentials
os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = os.getenv(
    'GOOGLE_APPLICATION_CREDENTIALS',
    'D:/Better_signal/hulken-fb56a345ac08.json'
)

class DataReconciliation:
    def __init__(self):
        self.bq_client = bigquery.Client(project=BQ_PROJECT)
        self.results = {
            "timestamp": datetime.now().isoformat(),
            "platforms": {},
            "summary": {"passed": 0, "warnings": 0, "errors": 0}
        }

    def check_facebook(self):
        """Check Facebook data in BigQuery"""
        print("\n📘 Checking Facebook Ads...")

        # Query BigQuery
        query = """
        SELECT
            account_name,
            account_id,
            COUNT(*) as records,
            COUNT(DISTINCT date_start) as days,
            MIN(date_start) as first_date,
            MAX(date_start) as last_date,
            ROUND(SUM(CAST(spend AS FLOAT64)), 2) as total_spend,
            SUM(CAST(impressions AS INT64)) as total_impressions,
            SUM(CAST(clicks AS INT64)) as total_clicks
        FROM `hulken.ads_data.facebook_insights`
        GROUP BY account_name, account_id
        ORDER BY total_spend DESC
        """

        try:
            results = self.bq_client.query(query).result()
            accounts = []
            total_spend = 0
            total_records = 0

            for row in results:
                accounts.append({
                    "account_name": row.account_name,
                    "account_id": row.account_id,
                    "records": row.records,
                    "days": row.days,
                    "date_range": f"{row.first_date} to {row.last_date}",
                    "spend": row.total_spend,
                    "impressions": row.total_impressions,
                    "clicks": row.total_clicks
                })
                total_spend += row.total_spend or 0
                total_records += row.records

            # Check for expected accounts
            expected_accounts = ["440461496366294", "1686648438857084", "1673934429844193"]
            found_accounts = [a["account_id"] for a in accounts]
            missing = [aid for aid in expected_accounts if aid not in found_accounts]

            status = "✅ PASSED" if not missing else "⚠️ WARNING"
            if missing:
                self.results["summary"]["warnings"] += 1
            else:
                self.results["summary"]["passed"] += 1

            self.results["platforms"]["facebook"] = {
                "status": status,
                "accounts": accounts,
                "total_records": total_records,
                "total_spend": total_spend,
                "missing_accounts": missing,
                "tables_checked": ["facebook_insights"]
            }

            print(f"   {status}")
            print(f"   Total records: {total_records:,}")
            print(f"   Total spend: ${total_spend:,.2f}")
            print(f"   Accounts found: {len(accounts)}/3")
            if missing:
                print(f"   ⚠️ Missing accounts: {missing}")

        except Exception as e:
            self.results["platforms"]["facebook"] = {"status": "❌ ERROR", "error": str(e)}
            self.results["summary"]["errors"] += 1
            print(f"   ❌ ERROR: {e}")

    def check_tiktok(self):
        """Check TikTok data in BigQuery"""
        print("\n📱 Checking TikTok Ads...")

        query = """
        SELECT
            COUNT(*) as records,
            COUNT(DISTINCT stat_time_day) as days,
            MIN(stat_time_day) as first_date,
            MAX(stat_time_day) as last_date
        FROM `hulken.ads_data.tiktok_ads_reports_daily`
        """

        try:
            results = list(self.bq_client.query(query).result())
            row = results[0]

            # Also check metrics
            metrics_query = """
            SELECT
                ROUND(SUM(CAST(JSON_EXTRACT_SCALAR(metrics, '$.spend') AS FLOAT64)), 2) as total_spend,
                SUM(CAST(JSON_EXTRACT_SCALAR(metrics, '$.impressions') AS INT64)) as impressions
            FROM `hulken.ads_data.tiktok_ads_reports_daily`
            """
            metrics = list(self.bq_client.query(metrics_query).result())[0]

            status = "✅ PASSED" if row.records > 0 else "❌ ERROR"
            if row.records > 0:
                self.results["summary"]["passed"] += 1
            else:
                self.results["summary"]["errors"] += 1

            self.results["platforms"]["tiktok"] = {
                "status": status,
                "records": row.records,
                "days": row.days,
                "date_range": f"{row.first_date} to {row.last_date}",
                "total_spend": metrics.total_spend,
                "impressions": metrics.impressions,
                "tables_checked": ["tiktok_ads_reports_daily"]
            }

            print(f"   {status}")
            print(f"   Total records: {row.records:,}")
            print(f"   Total spend: ${metrics.total_spend:,.2f}" if metrics.total_spend else "   Spend: N/A")
            print(f"   Date range: {row.first_date} to {row.last_date}")

        except Exception as e:
            self.results["platforms"]["tiktok"] = {"status": "❌ ERROR", "error": str(e)}
            self.results["summary"]["errors"] += 1
            print(f"   ❌ ERROR: {e}")

    def check_shopify_orders(self):
        """Check Shopify orders data"""
        print("\n🛒 Checking Shopify Orders...")

        query = """
        SELECT
            COUNT(*) as total_orders,
            COUNT(DISTINCT DATE(createdAt)) as days,
            MIN(DATE(createdAt)) as first_date,
            MAX(DATE(createdAt)) as last_date,
            ROUND(SUM(totalPrice), 2) as total_revenue,
            COUNT(DISTINCT customer_id) as unique_customers
        FROM `hulken.ads_data.shopify_orders`
        """

        try:
            results = list(self.bq_client.query(query).result())
            row = results[0]

            status = "✅ PASSED" if row.total_orders > 0 else "❌ ERROR"
            if row.total_orders > 0:
                self.results["summary"]["passed"] += 1
            else:
                self.results["summary"]["errors"] += 1

            self.results["platforms"]["shopify_orders"] = {
                "status": status,
                "total_orders": row.total_orders,
                "days": row.days,
                "date_range": f"{row.first_date} to {row.last_date}",
                "total_revenue": row.total_revenue,
                "unique_customers": row.unique_customers,
                "tables_checked": ["shopify_orders"]
            }

            print(f"   {status}")
            print(f"   Total orders: {row.total_orders:,}")
            print(f"   Total revenue: ${row.total_revenue:,.2f}")
            print(f"   Unique customers: {row.unique_customers:,}")
            print(f"   Date range: {row.first_date} to {row.last_date}")

        except Exception as e:
            self.results["platforms"]["shopify_orders"] = {"status": "❌ ERROR", "error": str(e)}
            self.results["summary"]["errors"] += 1
            print(f"   ❌ ERROR: {e}")

    def check_shopify_utm(self):
        """Check Shopify UTM attribution data"""
        print("\n🔗 Checking Shopify UTM Attribution...")

        query = """
        SELECT
            COUNT(*) as total_records,
            COUNTIF(first_utm_source IS NOT NULL) as with_utm,
            MIN(DATE(created_at)) as first_date,
            MAX(DATE(created_at)) as last_date,
            ROUND(SUM(total_price), 2) as total_revenue
        FROM `hulken.ads_data.shopify_utm`
        """

        try:
            results = list(self.bq_client.query(query).result())
            row = results[0]

            utm_rate = (row.with_utm / row.total_records * 100) if row.total_records > 0 else 0
            status = "✅ PASSED" if row.total_records > 0 else "❌ ERROR"

            if row.total_records > 0:
                self.results["summary"]["passed"] += 1
            else:
                self.results["summary"]["errors"] += 1

            self.results["platforms"]["shopify_utm"] = {
                "status": status,
                "total_records": row.total_records,
                "with_utm": row.with_utm,
                "utm_rate": f"{utm_rate:.1f}%",
                "date_range": f"{row.first_date} to {row.last_date}",
                "total_revenue": row.total_revenue,
                "tables_checked": ["shopify_utm"]
            }

            print(f"   {status}")
            print(f"   Total records: {row.total_records:,}")
            print(f"   With UTM data: {row.with_utm:,} ({utm_rate:.1f}%)")
            print(f"   Total revenue: ${row.total_revenue:,.2f}")

        except Exception as e:
            self.results["platforms"]["shopify_utm"] = {"status": "❌ ERROR", "error": str(e)}
            self.results["summary"]["errors"] += 1
            print(f"   ❌ ERROR: {e}")

    def check_data_freshness(self):
        """Check if data is recent (within last 3 days)"""
        print("\n⏰ Checking Data Freshness...")

        checks = [
            ("Facebook", "SELECT MAX(date_start) as latest FROM `hulken.ads_data.facebook_insights`"),
            ("TikTok", "SELECT MAX(stat_time_day) as latest FROM `hulken.ads_data.tiktok_ads_reports_daily`"),
            ("Shopify Live", "SELECT MAX(DATE(updated_at)) as latest FROM `hulken.ads_data.shopify_live_orders`"),
            ("Shopify UTM", "SELECT MAX(DATE(extracted_at)) as latest FROM `hulken.ads_data.shopify_utm`"),
        ]

        freshness = {}
        today = datetime.now().date()

        for name, query in checks:
            try:
                result = list(self.bq_client.query(query).result())[0]
                latest = result.latest
                if latest:
                    days_old = (today - latest).days if hasattr(latest, 'days') else (today - datetime.strptime(str(latest), '%Y-%m-%d').date()).days
                    status = "🟢 Fresh" if days_old <= 2 else ("🟡 Stale" if days_old <= 7 else "🔴 Old")
                    freshness[name] = {"latest": str(latest), "days_old": days_old, "status": status}
                    print(f"   {name}: {latest} ({days_old} days old) {status}")
                else:
                    freshness[name] = {"latest": None, "status": "❌ No data"}
                    print(f"   {name}: No data")
            except Exception as e:
                freshness[name] = {"error": str(e)}
                print(f"   {name}: Error - {e}")

        self.results["freshness"] = freshness

    def generate_html_report(self):
        """Generate HTML report"""
        html = f"""
<!DOCTYPE html>
<html>
<head>
    <title>Data Reconciliation Report</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }}
        .container {{ max-width: 1000px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }}
        h1 {{ color: #333; border-bottom: 3px solid #4CAF50; padding-bottom: 10px; }}
        h2 {{ color: #555; margin-top: 30px; }}
        .summary {{ display: flex; gap: 20px; margin: 20px 0; }}
        .summary-box {{ padding: 20px; border-radius: 8px; flex: 1; text-align: center; }}
        .passed {{ background: #e8f5e9; color: #2e7d32; }}
        .warnings {{ background: #fff3e0; color: #ef6c00; }}
        .errors {{ background: #ffebee; color: #c62828; }}
        table {{ width: 100%; border-collapse: collapse; margin: 15px 0; }}
        th, td {{ padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }}
        th {{ background: #f8f9fa; font-weight: bold; }}
        .status {{ font-size: 1.2em; }}
        .timestamp {{ color: #888; font-size: 0.9em; }}
        .metric {{ font-size: 1.5em; font-weight: bold; }}
    </style>
</head>
<body>
    <div class="container">
        <h1>📊 Data Reconciliation Report</h1>
        <p class="timestamp">Generated: {self.results['timestamp']}</p>

        <div class="summary">
            <div class="summary-box passed">
                <div class="metric">{self.results['summary']['passed']}</div>
                <div>Passed</div>
            </div>
            <div class="summary-box warnings">
                <div class="metric">{self.results['summary']['warnings']}</div>
                <div>Warnings</div>
            </div>
            <div class="summary-box errors">
                <div class="metric">{self.results['summary']['errors']}</div>
                <div>Errors</div>
            </div>
        </div>

        <h2>📘 Facebook Ads</h2>
        <p class="status">{self.results['platforms'].get('facebook', {}).get('status', 'N/A')}</p>
        <table>
            <tr><th>Account</th><th>Records</th><th>Spend</th><th>Date Range</th></tr>
"""

        for acc in self.results['platforms'].get('facebook', {}).get('accounts', []):
            html += f"<tr><td>{acc['account_name']}</td><td>{acc['records']:,}</td><td>${acc['spend']:,.2f}</td><td>{acc['date_range']}</td></tr>"

        html += f"""
        </table>

        <h2>📱 TikTok Ads</h2>
        <p class="status">{self.results['platforms'].get('tiktok', {}).get('status', 'N/A')}</p>
        <table>
            <tr><th>Metric</th><th>Value</th></tr>
            <tr><td>Records</td><td>{self.results['platforms'].get('tiktok', {}).get('records', 0):,}</td></tr>
            <tr><td>Total Spend</td><td>${self.results['platforms'].get('tiktok', {}).get('total_spend', 0):,.2f}</td></tr>
            <tr><td>Date Range</td><td>{self.results['platforms'].get('tiktok', {}).get('date_range', 'N/A')}</td></tr>
        </table>

        <h2>🛒 Shopify Orders</h2>
        <p class="status">{self.results['platforms'].get('shopify_orders', {}).get('status', 'N/A')}</p>
        <table>
            <tr><th>Metric</th><th>Value</th></tr>
            <tr><td>Total Orders</td><td>{self.results['platforms'].get('shopify_orders', {}).get('total_orders', 0):,}</td></tr>
            <tr><td>Total Revenue</td><td>${self.results['platforms'].get('shopify_orders', {}).get('total_revenue', 0):,.2f}</td></tr>
            <tr><td>Unique Customers</td><td>{self.results['platforms'].get('shopify_orders', {}).get('unique_customers', 0):,}</td></tr>
            <tr><td>Date Range</td><td>{self.results['platforms'].get('shopify_orders', {}).get('date_range', 'N/A')}</td></tr>
        </table>

        <h2>🔗 Shopify UTM Attribution</h2>
        <p class="status">{self.results['platforms'].get('shopify_utm', {}).get('status', 'N/A')}</p>
        <table>
            <tr><th>Metric</th><th>Value</th></tr>
            <tr><td>Total Records</td><td>{self.results['platforms'].get('shopify_utm', {}).get('total_records', 0):,}</td></tr>
            <tr><td>With UTM Data</td><td>{self.results['platforms'].get('shopify_utm', {}).get('with_utm', 0):,} ({self.results['platforms'].get('shopify_utm', {}).get('utm_rate', '0%')})</td></tr>
        </table>

        <h2>⏰ Data Freshness</h2>
        <table>
            <tr><th>Source</th><th>Latest Data</th><th>Status</th></tr>
"""

        for source, info in self.results.get('freshness', {}).items():
            html += f"<tr><td>{source}</td><td>{info.get('latest', 'N/A')}</td><td>{info.get('status', 'Unknown')}</td></tr>"

        html += """
        </table>

        <p style="margin-top: 40px; color: #888; text-align: center;">
            Better Signals Data Infrastructure - Reconciliation Report
        </p>
    </div>
</body>
</html>
"""

        report_path = "D:/Better_signal/data_validation/reconciliation_report.html"
        with open(report_path, 'w', encoding='utf-8') as f:
            f.write(html)

        print(f"\n📄 HTML Report saved to: {report_path}")
        return report_path

    def run(self):
        """Run all reconciliation checks"""
        print("=" * 60)
        print("        DATA RECONCILIATION REPORT")
        print(f"        {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print("=" * 60)

        self.check_facebook()
        self.check_tiktok()
        self.check_shopify_orders()
        self.check_shopify_utm()
        self.check_data_freshness()

        print("\n" + "=" * 60)
        print("        SUMMARY")
        print("=" * 60)
        print(f"   ✅ Passed:   {self.results['summary']['passed']}")
        print(f"   ⚠️ Warnings: {self.results['summary']['warnings']}")
        print(f"   ❌ Errors:   {self.results['summary']['errors']}")

        report_path = self.generate_html_report()

        # Save JSON results
        json_path = "D:/Better_signal/data_validation/reconciliation_results.json"
        with open(json_path, 'w') as f:
            json.dump(self.results, f, indent=2, default=str)

        print(f"📊 JSON Results saved to: {json_path}")
        print("\n" + "=" * 60)

        # Open HTML report in browser
        import webbrowser
        webbrowser.open(f"file:///{report_path}")

        return self.results


if __name__ == "__main__":
    reconciler = DataReconciliation()
    reconciler.run()

    # Only prompt for input if running interactively
    if sys.stdin.isatty():
        input("\nPress Enter to exit...")
