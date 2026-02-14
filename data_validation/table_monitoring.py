#!/usr/bin/env python3
"""
TABLE MONITORING - Automatic Detection of Empty/New Tables
===========================================================
Monitors BigQuery tables for:
- Empty tables (row_count = 0)
- New tables added by Airbyte
- Tables not synced recently (> 48h)
- Missing expected tables

Usage:
    # First time: create baseline
    python data_validation/table_monitoring.py --create-baseline

    # Regular monitoring
    python data_validation/table_monitoring.py --check

    # Check specific dataset
    python data_validation/table_monitoring.py --check --dataset google_Ads

    # Export report to file
    python data_validation/table_monitoring.py --check --output report.txt
"""

import os
import sys
import json
import argparse
from datetime import datetime, timedelta
from pathlib import Path

from dotenv import load_dotenv
from google.cloud import bigquery

# Load env
env_path = Path(__file__).parent / '.env'
load_dotenv(env_path)

BQ_PROJECT = os.getenv('BIGQUERY_PROJECT', 'hulken')
CREDENTIALS_PATH = os.getenv('GOOGLE_APPLICATION_CREDENTIALS')

if CREDENTIALS_PATH:
    os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = CREDENTIALS_PATH

# ANSI Colors
class C:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    WHITE = '\033[97m'
    BOLD = '\033[1m'
    DIM = '\033[2m'
    END = '\033[0m'


BASELINE_FILE = Path(__file__).parent / 'known_tables.json'

# Expected tables (minimum set)
EXPECTED_TABLES = {
    'ads_data': [
        'shopify_live_orders',
        'shopify_live_orders_clean',
        'shopify_live_customers',
        'shopify_live_customers_clean',
        'shopify_utm',
        'facebook_insights',
        'facebook_ads_insights',
        'tiktok_ads_reports_daily',
        'tiktokads_reports_daily',
    ],
    'google_Ads': [
        # Will be detected dynamically
    ],
}


def get_all_tables(client, dataset_id):
    """Get all tables in a dataset with metadata."""
    query = f"""
    SELECT
        table_id AS table_name,
        row_count,
        ROUND(size_bytes / 1024 / 1024, 2) AS size_mb,
        TIMESTAMP_MILLIS(creation_time) AS created_at,
        TIMESTAMP_MILLIS(last_modified_time) AS last_modified
    FROM `{BQ_PROJECT}.{dataset_id}.__TABLES__`
    ORDER BY table_name
    """
    try:
        df = client.query(query).to_dataframe()
        return df.to_dict('records')
    except Exception as e:
        print(f"{C.RED}Error querying {dataset_id}: {e}{C.END}")
        return []


def get_airbyte_sync_status(client, dataset_id, table_name):
    """Get last Airbyte sync time for a table."""
    try:
        query = f"""
        SELECT MAX(_airbyte_extracted_at) AS last_sync
        FROM `{BQ_PROJECT}.{dataset_id}.{table_name}`
        """
        result = list(client.query(query).result())
        if result and result[0].last_sync:
            return result[0].last_sync
        return None
    except Exception:
        return None


def create_baseline(client, datasets):
    """Create baseline of known tables."""
    baseline = {}

    print(f"\n{C.CYAN}{C.BOLD}Creating baseline of known tables...{C.END}\n")

    for dataset_id in datasets:
        print(f"  Scanning {dataset_id}...")
        tables = get_all_tables(client, dataset_id)

        baseline[dataset_id] = {
            'scanned_at': datetime.now().isoformat(),
            'tables': {t['table_name']: {
                'row_count': int(t['row_count'] or 0),
                'created_at': t['created_at'].isoformat() if t['created_at'] else None,
            } for t in tables}
        }

        print(f"    ✅ {len(tables)} tables found")

    # Save to file
    with open(BASELINE_FILE, 'w') as f:
        json.dump(baseline, f, indent=2)

    print(f"\n{C.GREEN}✅ Baseline saved to {BASELINE_FILE}{C.END}")
    print(f"   Total tables: {sum(len(d['tables']) for d in baseline.values())}")

    return baseline


def load_baseline():
    """Load baseline from file."""
    if not BASELINE_FILE.exists():
        return None

    with open(BASELINE_FILE, 'r') as f:
        return json.load(f)


def check_tables(client, datasets, output_file=None):
    """Check for empty/new/stale tables."""
    baseline = load_baseline()

    if not baseline:
        print(f"{C.RED}❌ No baseline found. Run with --create-baseline first.{C.END}")
        return 1

    print(f"\n{C.CYAN}{C.BOLD}{'=' * 60}{C.END}")
    print(f"{C.CYAN}{C.BOLD}   TABLE MONITORING REPORT{C.END}")
    print(f"{C.CYAN}{C.BOLD}{'=' * 60}{C.END}")
    print(f"{C.DIM}   Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}{C.END}")
    print(f"{C.DIM}   Baseline: {baseline.get('ads_data', {}).get('scanned_at', 'Unknown')}{C.END}\n")

    issues_found = []

    for dataset_id in datasets:
        print(f"{C.CYAN}{'─' * 60}{C.END}")
        print(f"{C.BOLD}Dataset: {dataset_id}{C.END}")
        print(f"{C.CYAN}{'─' * 60}{C.END}\n")

        current_tables = get_all_tables(client, dataset_id)
        baseline_tables = baseline.get(dataset_id, {}).get('tables', {})

        current_table_names = {t['table_name'] for t in current_tables}
        baseline_table_names = set(baseline_tables.keys())

        # 1. NEW TABLES
        new_tables = current_table_names - baseline_table_names
        if new_tables:
            print(f"{C.YELLOW}🆕 NEW TABLES DETECTED ({len(new_tables)}){C.END}")
            for table_name in sorted(new_tables):
                table_info = next(t for t in current_tables if t['table_name'] == table_name)
                row_count = int(table_info['row_count'] or 0)
                created_at = table_info['created_at']

                print(f"   ├─ {table_name}")
                print(f"   │  ├─ Rows: {row_count:,}")
                print(f"   │  ├─ Created: {created_at}")

                if row_count == 0:
                    print(f"   │  └─ {C.RED}⚠️  EMPTY TABLE{C.END}")
                    issues_found.append(f"NEW & EMPTY: {dataset_id}.{table_name}")
                else:
                    print(f"   │  └─ {C.GREEN}✓ Has data{C.END}")
                    issues_found.append(f"NEW TABLE: {dataset_id}.{table_name} ({row_count:,} rows)")
            print()

        # 2. DELETED TABLES
        deleted_tables = baseline_table_names - current_table_names
        if deleted_tables:
            print(f"{C.RED}🗑️  DELETED TABLES ({len(deleted_tables)}){C.END}")
            for table_name in sorted(deleted_tables):
                print(f"   ├─ {table_name} (was in baseline, now missing)")
                issues_found.append(f"DELETED: {dataset_id}.{table_name}")
            print()

        # 3. EMPTY TABLES
        empty_tables = [t for t in current_tables if int(t['row_count'] or 0) == 0]
        if empty_tables:
            print(f"{C.RED}⚠️  EMPTY TABLES ({len(empty_tables)}){C.END}")
            for table_info in empty_tables:
                table_name = table_info['table_name']
                last_sync = get_airbyte_sync_status(client, dataset_id, table_name)

                print(f"   ├─ {table_name}")
                if last_sync:
                    hours_ago = (datetime.now(last_sync.tzinfo) - last_sync).total_seconds() / 3600
                    print(f"   │  ├─ Last sync: {last_sync} ({hours_ago:.0f}h ago)")
                else:
                    print(f"   │  ├─ Last sync: Unknown")

                # Check if it's expected to be empty
                was_empty = baseline_tables.get(table_name, {}).get('row_count', -1) == 0
                if was_empty:
                    print(f"   │  └─ {C.YELLOW}Still empty (was empty in baseline){C.END}")
                    issues_found.append(f"STILL EMPTY: {dataset_id}.{table_name}")
                else:
                    print(f"   │  └─ {C.RED}NEWLY EMPTY (had {baseline_tables.get(table_name, {}).get('row_count', 0):,} rows before){C.END}")
                    issues_found.append(f"NEWLY EMPTY: {dataset_id}.{table_name}")
            print()

        # 4. STALE TABLES (not synced in 48h)
        stale_tables = []
        for table_info in current_tables:
            table_name = table_info['table_name']
            # Only check Airbyte tables (have _airbyte_extracted_at)
            if any(prefix in table_name for prefix in ['shopify_', 'facebook_', 'tiktok']):
                last_sync = get_airbyte_sync_status(client, dataset_id, table_name)
                if last_sync:
                    hours_ago = (datetime.now(last_sync.tzinfo) - last_sync).total_seconds() / 3600
                    if hours_ago > 48:
                        stale_tables.append((table_name, last_sync, hours_ago))

        if stale_tables:
            print(f"{C.YELLOW}⏰ STALE TABLES - Not synced in 48+ hours ({len(stale_tables)}){C.END}")
            for table_name, last_sync, hours_ago in sorted(stale_tables, key=lambda x: x[2], reverse=True):
                print(f"   ├─ {table_name}")
                print(f"   │  └─ Last sync: {last_sync} ({hours_ago:.0f}h ago / {hours_ago/24:.1f} days)")
                issues_found.append(f"STALE: {dataset_id}.{table_name} ({hours_ago:.0f}h)")
            print()

        # 5. MISSING EXPECTED TABLES
        if dataset_id in EXPECTED_TABLES:
            expected = set(EXPECTED_TABLES[dataset_id])
            missing = expected - current_table_names
            if missing:
                print(f"{C.RED}❌ MISSING EXPECTED TABLES ({len(missing)}){C.END}")
                for table_name in sorted(missing):
                    print(f"   ├─ {table_name}")
                    issues_found.append(f"MISSING: {dataset_id}.{table_name}")
                print()

    # SUMMARY
    print(f"{C.CYAN}{'=' * 60}{C.END}")
    print(f"{C.BOLD}SUMMARY{C.END}")
    print(f"{C.CYAN}{'─' * 60}{C.END}")

    if not issues_found:
        print(f"{C.GREEN}✅ No issues found - All tables healthy!{C.END}")
        status = 0
    else:
        print(f"{C.YELLOW}⚠️  {len(issues_found)} issue(s) found:{C.END}\n")
        for issue in issues_found:
            icon = "🆕" if "NEW" in issue else "⚠️" if "EMPTY" in issue or "STALE" in issue else "❌"
            print(f"   {icon} {issue}")
        status = 1

    print(f"{C.CYAN}{'=' * 60}{C.END}\n")

    # Save to file if requested
    if output_file:
        with open(output_file, 'w') as f:
            f.write(f"TABLE MONITORING REPORT\n")
            f.write(f"Generated: {datetime.now().isoformat()}\n")
            f.write(f"Baseline: {baseline.get('ads_data', {}).get('scanned_at', 'Unknown')}\n\n")
            f.write(f"Issues found: {len(issues_found)}\n\n")
            for issue in issues_found:
                f.write(f"- {issue}\n")
        print(f"{C.GREEN}📄 Report saved to {output_file}{C.END}\n")

    return status


def main():
    parser = argparse.ArgumentParser(description='Monitor BigQuery tables for issues')
    parser.add_argument('--create-baseline', action='store_true',
                        help='Create baseline of current tables')
    parser.add_argument('--check', action='store_true',
                        help='Check for empty/new/stale tables')
    parser.add_argument('--dataset', type=str, default=None,
                        help='Check specific dataset (default: all)')
    parser.add_argument('--output', type=str, default=None,
                        help='Save report to file')

    args = parser.parse_args()

    # Connect to BigQuery
    try:
        client = bigquery.Client(project=BQ_PROJECT)
        # Test connection
        list(client.query("SELECT 1").result())
    except Exception as e:
        print(f"{C.RED}❌ Failed to connect to BigQuery: {e}{C.END}")
        return 1

    # Get datasets to check
    if args.dataset:
        datasets = [args.dataset]
    else:
        datasets = ['ads_data', 'google_Ads']

    # Execute action
    if args.create_baseline:
        create_baseline(client, datasets)
        return 0
    elif args.check:
        return check_tables(client, datasets, args.output)
    else:
        parser.print_help()
        return 1


if __name__ == '__main__':
    sys.exit(main())
