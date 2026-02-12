#!/usr/bin/env python3
"""
LIVE RECONCILIATION DEMO
=========================
Visual, step-by-step API vs BigQuery comparison.
Designed to be run in front of clients to demonstrate data integrity.

Calls Shopify API, Facebook Marketing API, and TikTok Marketing API,
then queries BigQuery, and shows a side-by-side comparison with match/mismatch indicators.

Usage:
    python data_validation/live_reconciliation.py
    python data_validation/live_reconciliation.py --days 30
    python data_validation/live_reconciliation.py --start-date 2025-01-01 --end-date 2025-01-31
    python data_validation/live_reconciliation.py --no-animation
    python data_validation/live_reconciliation.py --tolerance 5
    python data_validation/live_reconciliation.py --platform shopify
    python data_validation/live_reconciliation.py --platform all
"""

import os
import sys
import json
import time
import argparse
from datetime import datetime, timedelta
from pathlib import Path

# Fix Unicode on Windows
if sys.platform == 'win32':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

import requests
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

TOLERANCE = 0.02  # 2% tolerance for match

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


# ============================================================
# DISPLAY HELPERS
# ============================================================
def animate_delay(seconds, animated=True):
    """Small delay for theatrical effect."""
    if animated:
        time.sleep(seconds)

def print_step(step_num, total, label, color=C.CYAN):
    """Print a step header."""
    print(f"\n{color}{C.BOLD}  [{step_num}/{total}] {label}{C.END}")
    print(f"  {C.DIM}{'─' * 56}{C.END}")

def print_progress(msg, animated=True):
    """Print a progress message with dots animation."""
    if animated:
        sys.stdout.write(f"  {C.DIM}  {msg}")
        sys.stdout.flush()
        for _ in range(3):
            time.sleep(0.3)
            sys.stdout.write(".")
            sys.stdout.flush()
        print(C.END)
    else:
        print(f"  {C.DIM}  {msg}...{C.END}")

def print_value(label, value, color=C.WHITE):
    """Print a labeled value inside a box."""
    print(f"  {C.DIM}║{C.END}  {label:<20} {color}{value}{C.END}")

def format_money(amount):
    """Format a number as currency."""
    return f"${amount:,.2f}"

def format_number(n):
    """Format a number with commas."""
    return f"{n:,}"

def print_comparison_box(title, source_name, period_start, period_end, comparisons, animated=True):
    """
    Print a comparison box with source API vs BigQuery values.

    comparisons: list of (metric_name, api_value, bq_value, formatter)
    """
    animate_delay(0.3, animated)

    width = 54
    print()
    print(f"  {C.CYAN}{'=' * width}{C.END}")
    print(f"  {C.CYAN}{C.BOLD}  {title}{C.END}")
    print(f"  {C.CYAN}{'─' * width}{C.END}")
    print(f"  {C.DIM}║{C.END}  Source: {C.WHITE}{source_name}{C.END}")
    print(f"  {C.DIM}║{C.END}  Period: {C.WHITE}{period_start} to {period_end}{C.END}")
    print(f"  {C.CYAN}{'─' * width}{C.END}")

    results = []
    for metric_name, api_val, bq_val, formatter in comparisons:
        animate_delay(0.2, animated)

        api_str = formatter(api_val)
        bq_str = formatter(bq_val)

        if api_val == 0 and bq_val == 0:
            diff_pct = 0.0
        elif api_val == 0:
            diff_pct = 100.0
        else:
            diff_pct = abs(api_val - bq_val) / api_val * 100

        is_match = diff_pct <= (TOLERANCE * 100)
        results.append(is_match)

        if is_match:
            status = f"{C.GREEN}MATCH{C.END}"
            diff_color = C.GREEN
        else:
            status = f"{C.RED}MISMATCH{C.END}"
            diff_color = C.RED

        print(f"  {C.DIM}║{C.END}")
        print(f"  {C.DIM}║{C.END}  {C.BOLD}{metric_name}{C.END}")
        print(f"  {C.DIM}║{C.END}    API       ->  {C.WHITE}{api_str}{C.END}")
        print(f"  {C.DIM}║{C.END}    BigQuery  ->  {C.WHITE}{bq_str}{C.END}")
        print(f"  {C.DIM}║{C.END}    Diff      ->  {diff_color}{diff_pct:.2f}%{C.END}  {status}")

    print(f"  {C.CYAN}{'=' * width}{C.END}")

    return results


# ============================================================
# API FUNCTIONS
# ============================================================
def get_facebook_account_name(account_id, access_token):
    """Get Facebook account name from API."""
    url = f"https://graph.facebook.com/v18.0/act_{account_id}"
    params = {'access_token': access_token, 'fields': 'name'}
    try:
        resp = requests.get(url, params=params, timeout=15)
        return resp.json().get('name', account_id)
    except Exception:
        return str(account_id)

def get_facebook_api_stats(account_id, access_token, start_date, end_date):
    """Get stats from Facebook Marketing API for one account."""
    url = f"https://graph.facebook.com/v18.0/act_{account_id}/insights"
    params = {
        'access_token': access_token,
        'time_range': json.dumps({'since': start_date, 'until': end_date}),
        'fields': 'spend,impressions,clicks',
        'level': 'account'
    }
    try:
        resp = requests.get(url, params=params, timeout=30)
        data = resp.json()
        if 'data' in data and len(data['data']) > 0:
            row = data['data'][0]
            return {
                'spend': float(row.get('spend', 0)),
                'impressions': int(row.get('impressions', 0)),
                'clicks': int(row.get('clicks', 0)),
            }
        elif 'error' in data:
            print(f"  {C.RED}  API Error: {data['error'].get('message', 'Unknown')}{C.END}")
            return None
        else:
            return {'spend': 0, 'impressions': 0, 'clicks': 0}
    except Exception as e:
        print(f"  {C.RED}  Request failed: {e}{C.END}")
        return None

def get_shopify_api_order_count(store, token, start_date, end_date):
    """Get order count from Shopify REST API."""
    url = f"https://{store}.myshopify.com/admin/api/2024-01/orders/count.json"
    headers = {"X-Shopify-Access-Token": token}
    params = {
        "status": "any",
        "created_at_min": f"{start_date}T00:00:00Z",
        "created_at_max": f"{end_date}T23:59:59Z"
    }
    try:
        resp = requests.get(url, headers=headers, params=params, timeout=30)
        if resp.status_code == 200:
            return {'order_count': resp.json().get('count', 0)}
        else:
            print(f"  {C.RED}  Shopify API Error: HTTP {resp.status_code}{C.END}")
            return None
    except Exception as e:
        print(f"  {C.RED}  Request failed: {e}{C.END}")
        return None


def get_shopify_api_revenue(store, token, start_date, end_date):
    """Get total revenue from Shopify REST API by paginating orders."""
    url = f"https://{store}.myshopify.com/admin/api/2024-01/orders.json"
    headers = {"X-Shopify-Access-Token": token}
    total_revenue = 0.0
    total_orders = 0
    params = {
        "status": "any",
        "created_at_min": f"{start_date}T00:00:00Z",
        "created_at_max": f"{end_date}T23:59:59Z",
        "fields": "id,total_price",
        "limit": 250
    }
    try:
        while url:
            resp = requests.get(url, headers=headers, params=params, timeout=60)
            if resp.status_code != 200:
                print(f"  {C.RED}  Shopify API Error: HTTP {resp.status_code}{C.END}")
                break
            orders = resp.json().get('orders', [])
            for o in orders:
                total_revenue += float(o.get('total_price', 0))
                total_orders += 1
            # Follow pagination via Link header
            link = resp.headers.get('Link', '')
            if 'rel="next"' in link:
                next_url = link.split('>; rel="next"')[0].split('<')[-1]
                url = next_url
                params = None  # params are in the URL for subsequent pages
            else:
                url = None
        return {'revenue': round(total_revenue, 2), 'order_count': total_orders}
    except Exception as e:
        print(f"  {C.RED}  Request failed: {e}{C.END}")
        return None


def get_tiktok_api_stats(access_token, advertiser_id, start_date, end_date):
    """Get stats from TikTok Marketing API."""
    url = "https://business-api.tiktok.com/open_api/v1.3/report/integrated/get/"
    headers = {'Access-Token': access_token}
    params = {
        "advertiser_id": advertiser_id,
        "report_type": "BASIC",
        "dimensions": json.dumps(["stat_time_day"]),
        "metrics": json.dumps(["spend", "impressions", "clicks"]),
        "data_level": "AUCTION_ADVERTISER",
        "start_date": start_date,
        "end_date": end_date,
        "page": 1,
        "page_size": 1000
    }
    try:
        resp = requests.get(url, headers=headers, params=params, timeout=30)
        data = resp.json()
        if data.get('code') == 0 and 'data' in data:
            rows = data['data'].get('list', [])
            total = {'spend': 0.0, 'impressions': 0, 'clicks': 0}
            for row in rows:
                m = row.get('metrics', {})
                total['spend'] += float(m.get('spend', 0) or 0)
                total['impressions'] += int(float(m.get('impressions', 0) or 0))
                total['clicks'] += int(float(m.get('clicks', 0) or 0))
            return total
        else:
            print(f"  {C.RED}  TikTok API Error: {data.get('message', 'Unknown')}{C.END}")
            return None
    except Exception as e:
        print(f"  {C.RED}  Request failed: {e}{C.END}")
        return None


# ============================================================
# BIGQUERY FUNCTIONS
# ============================================================
def get_bq_facebook_stats(client, account_id, start_date, end_date):
    """Get Facebook stats from BigQuery for one account."""
    sql = f"""
    SELECT
        COALESCE(SUM(CAST(spend AS FLOAT64)), 0) AS total_spend,
        COALESCE(SUM(impressions), 0) AS total_impressions,
        COALESCE(SUM(clicks), 0) AS total_clicks
    FROM `{BQ_PROJECT}.{BQ_DATASET}.facebook_insights`
    WHERE date_start BETWEEN '{start_date}' AND '{end_date}'
    AND account_id = '{account_id}'
    """
    try:
        row = list(client.query(sql).result())[0]
        return {
            'spend': float(row.total_spend or 0),
            'impressions': int(row.total_impressions or 0),
            'clicks': int(row.total_clicks or 0),
        }
    except Exception as e:
        print(f"  {C.RED}  BigQuery Error: {e}{C.END}")
        return None

def get_bq_tiktok_stats(client, start_date, end_date):
    """Get TikTok stats from BigQuery."""
    sql = f"""
    SELECT
        COALESCE(SUM(spend), 0) AS total_spend,
        COALESCE(SUM(impressions), 0) AS total_impressions,
        COALESCE(SUM(clicks), 0) AS total_clicks
    FROM `{BQ_PROJECT}.{BQ_DATASET}.tiktok_ads_reports_daily`
    WHERE report_date BETWEEN '{start_date}' AND '{end_date}'
    """
    try:
        row = list(client.query(sql).result())[0]
        return {
            'spend': float(row.total_spend or 0),
            'impressions': int(row.total_impressions or 0),
            'clicks': int(row.total_clicks or 0),
        }
    except Exception as e:
        print(f"  {C.RED}  BigQuery Error: {e}{C.END}")
        return None

def get_bq_shopify_stats(client, start_date, end_date):
    """Get Shopify order count and revenue from BigQuery _clean table."""
    sql = f"""
    SELECT
        COUNT(*) AS order_count,
        COALESCE(ROUND(SUM(CAST(total_price AS FLOAT64)), 2), 0) AS total_revenue
    FROM `{BQ_PROJECT}.{BQ_DATASET}.shopify_live_orders_clean`
    WHERE DATE(created_at) BETWEEN '{start_date}' AND '{end_date}'
    """
    try:
        row = list(client.query(sql).result())[0]
        return {
            'order_count': int(row.order_count or 0),
            'revenue': float(row.total_revenue or 0),
        }
    except Exception as e:
        print(f"  {C.RED}  BigQuery Error: {e}{C.END}")
        return None


def get_bq_data_freshness(client, platform):
    """Check when BigQuery data was last synced for a platform."""
    if platform == 'facebook':
        sql = f"""
        SELECT MAX(_airbyte_extracted_at) AS last_sync
        FROM `{BQ_PROJECT}.{BQ_DATASET}.facebook_ads_insights`
        """
    elif platform == 'tiktok':
        sql = f"""
        SELECT MAX(_airbyte_extracted_at) AS last_sync
        FROM `{BQ_PROJECT}.{BQ_DATASET}.tiktokads_reports_daily`
        """
    elif platform == 'shopify':
        sql = f"""
        SELECT MAX(_airbyte_extracted_at) AS last_sync
        FROM `{BQ_PROJECT}.{BQ_DATASET}.shopify_live_orders`
        """
    else:
        return None
    try:
        row = list(client.query(sql).result())[0]
        return row.last_sync
    except Exception:
        return None


def main():
    parser = argparse.ArgumentParser(description='Live Reconciliation Demo')
    parser.add_argument('--days', type=int, default=14, help='Number of days to compare (default: 14)')
    parser.add_argument('--start-date', type=str, help='Start date (YYYY-MM-DD). Overrides --days')
    parser.add_argument('--end-date', type=str, help='End date (YYYY-MM-DD). Overrides default')
    parser.add_argument('--tolerance', type=float, default=None, help='Match tolerance in percent (default: 2)')
    parser.add_argument('--no-animation', action='store_true', help='Disable animation delays')
    parser.add_argument('--platform', type=str, default='all',
                        help='Platform(s) to check: all, facebook, tiktok, shopify (default: all)')
    args = parser.parse_args()

    global TOLERANCE
    if args.tolerance is not None:
        TOLERANCE = args.tolerance / 100.0

    animated = not args.no_animation

    # Date handling: custom dates override --days
    if args.start_date and args.end_date:
        start_date = args.start_date
        end_date = args.end_date
    elif args.start_date:
        start_date = args.start_date
        end_date = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')
    else:
        # Default: exclude last 2 days for attribution window settling
        end_date = (datetime.now() - timedelta(days=2)).strftime('%Y-%m-%d')
        start_date = (datetime.now() - timedelta(days=2 + args.days)).strftime('%Y-%m-%d')

    # Calculate display days
    d_start = datetime.strptime(start_date, '%Y-%m-%d')
    d_end = datetime.strptime(end_date, '%Y-%m-%d')
    num_days = (d_end - d_start).days + 1

    # Title
    print()
    print(f"  {C.CYAN}{C.BOLD}{'=' * 54}{C.END}")
    print(f"  {C.CYAN}{C.BOLD}   LIVE DATA RECONCILIATION{C.END}")
    print(f"  {C.CYAN}{C.BOLD}   API vs BigQuery — Real-time Comparison{C.END}")
    print(f"  {C.CYAN}{C.BOLD}{'=' * 54}{C.END}")
    print(f"  {C.DIM}  Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}{C.END}")
    print(f"  {C.DIM}  Period:    {start_date} to {end_date} ({num_days} days){C.END}")
    print(f"  {C.DIM}  Tolerance: {TOLERANCE*100:.0f}%{C.END}")

    all_results = []  # (platform, metric, match_bool)
    selected = args.platform.lower()
    run_facebook = selected in ('all', 'facebook')
    run_tiktok = selected in ('all', 'tiktok')
    run_shopify = selected in ('all', 'shopify')

    # Calculate total steps dynamically: connect(1) + 3 per platform + scoreboard(1)
    total_steps = 2  # connect + scoreboard
    if run_facebook: total_steps += 3
    if run_tiktok: total_steps += 3
    if run_shopify: total_steps += 3
    step = 0

    # ── STEP: CONNECT TO BIGQUERY ──────────────────────────
    step += 1
    print_step(step, total_steps, "CONNECT — BigQuery")
    print_progress("Connecting to BigQuery", animated)
    try:
        bq_client = bigquery.Client(project=BQ_PROJECT)
        # Quick test query
        list(bq_client.query(f"SELECT 1").result())
        print(f"  {C.GREEN}  Connected to project '{BQ_PROJECT}', dataset '{BQ_DATASET}'{C.END}")
        # Show data freshness
        freshness_platforms = []
        if run_facebook: freshness_platforms.append('facebook')
        if run_tiktok: freshness_platforms.append('tiktok')
        if run_shopify: freshness_platforms.append('shopify')
        for plat in freshness_platforms:
            last_sync = get_bq_data_freshness(bq_client, plat)
            if last_sync:
                hours_ago = (datetime.utcnow() - last_sync.replace(tzinfo=None)).total_seconds() / 3600
                freshness_color = C.GREEN if hours_ago < 24 else C.YELLOW if hours_ago < 48 else C.RED
                print(f"  {C.DIM}  {plat.title()} last sync: {freshness_color}{last_sync.strftime('%Y-%m-%d %H:%M')} UTC ({hours_ago:.0f}h ago){C.END}")
    except Exception as e:
        print(f"  {C.RED}  FAILED: {e}{C.END}")
        print(f"\n  {C.RED}Cannot proceed without BigQuery connection.{C.END}")
        return 1

    # ── FACEBOOK ─────────────────────────────────────────────
    if run_facebook:
        step += 1
        print_step(step, total_steps, "FACEBOOK API — Calling Facebook Marketing API v18.0")

        fb_access_token = os.getenv('FACEBOOK_ACCESS_TOKEN')
        fb_account_ids = [a.strip() for a in os.getenv('FACEBOOK_ACCOUNT_IDS', '').split(',') if a.strip()]

        fb_api_results = {}
        fb_account_names = {}

        if not fb_access_token or not fb_account_ids:
            print(f"  {C.YELLOW}  Facebook credentials not configured — skipping{C.END}")
        else:
            for acct_id in fb_account_ids:
                name = get_facebook_account_name(acct_id, fb_access_token)
                fb_account_names[acct_id] = name
                print_progress(f"Querying account: {name} ({acct_id})", animated)
                stats = get_facebook_api_stats(acct_id, fb_access_token, start_date, end_date)
                if stats:
                    fb_api_results[acct_id] = stats
                    print(f"  {C.GREEN}  {name}: spend={format_money(stats['spend'])}, impressions={format_number(stats['impressions'])}, clicks={format_number(stats['clicks'])}{C.END}")
                else:
                    print(f"  {C.YELLOW}  {name}: no data or API error{C.END}")

        step += 1
        print_step(step, total_steps, "FACEBOOK BQ — Querying BigQuery facebook_insights")

        fb_bq_results = {}
        for acct_id in fb_api_results:
            name = fb_account_names[acct_id]
            print_progress(f"Querying BigQuery for {name}", animated)
            stats = get_bq_facebook_stats(bq_client, acct_id, start_date, end_date)
            if stats:
                fb_bq_results[acct_id] = stats
                print(f"  {C.GREEN}  {name}: spend={format_money(stats['spend'])}, impressions={format_number(stats['impressions'])}, clicks={format_number(stats['clicks'])}{C.END}")

        step += 1
        print_step(step, total_steps, "FACEBOOK COMPARE — Side-by-side comparison")

        for acct_id in fb_api_results:
            if acct_id not in fb_bq_results:
                continue
            name = fb_account_names[acct_id]
            api = fb_api_results[acct_id]
            bq = fb_bq_results[acct_id]

            # Skip zero-data accounts (e.g. dormant Canada account)
            if api['spend'] == 0 and api['impressions'] == 0 and bq['spend'] == 0 and bq['impressions'] == 0:
                print(f"\n  {C.YELLOW}  {name}: No activity in this period — skipped{C.END}")
                print(f"  {C.DIM}  Tip: Try a different date range (e.g. --start-date 2024-11-01 --end-date 2024-12-01){C.END}")
                all_results.append((f"Facebook ({name})", "All metrics", None))  # None = skipped
                continue

            comparisons = [
                ("Spend", api['spend'], bq['spend'], format_money),
                ("Impressions", api['impressions'], bq['impressions'], format_number),
                ("Clicks", api['clicks'], bq['clicks'], format_number),
            ]

            results = print_comparison_box(
                f"FACEBOOK ADS — {name}",
                "Facebook Marketing API v18.0",
                start_date, end_date,
                comparisons, animated
            )

            for (metric_name, _, _, _), matched in zip(comparisons, results):
                all_results.append((f"Facebook ({name})", metric_name, matched))

    # ── TIKTOK ──────────────────────────────────────────────
    if run_tiktok:
        step += 1
        print_step(step, total_steps, "TIKTOK API — Calling TikTok Marketing API v1.3")

        tt_access_token = os.getenv('TIKTOK_ACCESS_TOKEN')
        tt_advertiser_id = os.getenv('TIKTOK_ADVERTISER_ID')

        tt_api_stats = None
        if not tt_access_token or not tt_advertiser_id:
            print(f"  {C.YELLOW}  TikTok credentials not configured — skipping{C.END}")
        else:
            print_progress(f"Querying advertiser {tt_advertiser_id}", animated)
            tt_api_stats = get_tiktok_api_stats(tt_access_token, tt_advertiser_id, start_date, end_date)
            if tt_api_stats:
                print(f"  {C.GREEN}  TikTok: spend={format_money(tt_api_stats['spend'])}, impressions={format_number(tt_api_stats['impressions'])}, clicks={format_number(tt_api_stats['clicks'])}{C.END}")
            else:
                print(f"  {C.YELLOW}  TikTok: no data or API error{C.END}")

        step += 1
        print_step(step, total_steps, "TIKTOK BQ — Querying BigQuery tiktok_ads_reports_daily")

        tt_bq_stats = None
        if tt_api_stats:
            print_progress("Querying BigQuery for TikTok", animated)
            tt_bq_stats = get_bq_tiktok_stats(bq_client, start_date, end_date)
            if tt_bq_stats:
                print(f"  {C.GREEN}  TikTok BQ: spend={format_money(tt_bq_stats['spend'])}, impressions={format_number(tt_bq_stats['impressions'])}, clicks={format_number(tt_bq_stats['clicks'])}{C.END}")

        step += 1
        print_step(step, total_steps, "TIKTOK COMPARE — Side-by-side comparison")

        if tt_api_stats and tt_bq_stats:
            comparisons = [
                ("Spend", tt_api_stats['spend'], tt_bq_stats['spend'], format_money),
                ("Impressions", tt_api_stats['impressions'], tt_bq_stats['impressions'], format_number),
                ("Clicks", tt_api_stats['clicks'], tt_bq_stats['clicks'], format_number),
            ]

            results = print_comparison_box(
                "TIKTOK ADS",
                "TikTok Marketing API v1.3",
                start_date, end_date,
                comparisons, animated
            )

            for (metric_name, _, _, _), matched in zip(comparisons, results):
                all_results.append(("TikTok", metric_name, matched))
        else:
            print(f"  {C.YELLOW}  Skipped — missing API or BigQuery data{C.END}")

    # ── SHOPIFY ────────────────────────────────────────────
    if run_shopify:
        step += 1
        print_step(step, total_steps, "SHOPIFY API — Calling Shopify REST API")

        sh_store = os.getenv('SHOPIFY_STORE')
        sh_token = os.getenv('SHOPIFY_ACCESS_TOKEN')

        sh_api_stats = None
        if not sh_store or not sh_token:
            print(f"  {C.YELLOW}  Shopify credentials not configured — skipping{C.END}")
        else:
            print_progress(f"Querying store: {sh_store}", animated)
            # Get order count first (fast), then revenue with pagination
            count_data = get_shopify_api_order_count(sh_store, sh_token, start_date, end_date)
            if count_data:
                print(f"  {C.GREEN}  Order count (API): {format_number(count_data['order_count'])}{C.END}")
                print_progress("Fetching revenue (paginated)", animated)
                revenue_data = get_shopify_api_revenue(sh_store, sh_token, start_date, end_date)
                if revenue_data:
                    sh_api_stats = {
                        'order_count': count_data['order_count'],
                        'revenue': revenue_data['revenue'],
                    }
                    print(f"  {C.GREEN}  Revenue (API): {format_money(sh_api_stats['revenue'])} from {format_number(revenue_data['order_count'])} orders{C.END}")

        step += 1
        print_step(step, total_steps, "SHOPIFY BQ — Querying BigQuery shopify_live_orders_clean")

        sh_bq_stats = None
        if sh_api_stats:
            print_progress("Querying BigQuery for Shopify", animated)
            sh_bq_stats = get_bq_shopify_stats(bq_client, start_date, end_date)
            if sh_bq_stats:
                print(f"  {C.GREEN}  Shopify BQ: orders={format_number(sh_bq_stats['order_count'])}, revenue={format_money(sh_bq_stats['revenue'])}{C.END}")

        step += 1
        print_step(step, total_steps, "SHOPIFY COMPARE — Side-by-side comparison")

        if sh_api_stats and sh_bq_stats:
            comparisons = [
                ("Order Count", sh_api_stats['order_count'], sh_bq_stats['order_count'], format_number),
                ("Revenue", sh_api_stats['revenue'], sh_bq_stats['revenue'], format_money),
            ]

            results = print_comparison_box(
                "SHOPIFY ORDERS",
                f"Shopify REST API ({sh_store})",
                start_date, end_date,
                comparisons, animated
            )

            for (metric_name, _, _, _), matched in zip(comparisons, results):
                all_results.append(("Shopify", metric_name, matched))
        else:
            print(f"  {C.YELLOW}  Skipped — missing API or BigQuery data{C.END}")

    # ── SCOREBOARD ─────────────────────────────────────────
    step += 1
    print_step(step, total_steps, "SCOREBOARD — Final Results", C.BOLD)

    animate_delay(0.5, animated)

    # Separate actual checks from skipped
    actual_results = [(p, m, v) for p, m, v in all_results if v is not None]
    skipped_results = [(p, m) for p, m, v in all_results if v is None]

    total_checks = len(actual_results)
    total_match = sum(1 for _, _, m in actual_results if m)
    total_mismatch = total_checks - total_match

    width = 54
    print()
    print(f"  {C.CYAN}{'=' * width}{C.END}")
    print(f"  {C.CYAN}{C.BOLD}   RECONCILIATION SCOREBOARD{C.END}")
    print(f"  {C.CYAN}{'─' * width}{C.END}")
    print(f"  {C.DIM}║{C.END}  Period: {start_date} to {end_date}")
    print(f"  {C.DIM}║{C.END}  Tolerance: {TOLERANCE*100:.0f}%")
    print(f"  {C.CYAN}{'─' * width}{C.END}")

    for platform, metric, matched in actual_results:
        animate_delay(0.1, animated)
        if matched:
            icon = f"{C.GREEN}MATCH{C.END}"
        else:
            icon = f"{C.RED}MISMATCH{C.END}"
        print(f"  {C.DIM}║{C.END}  {platform:<28} {metric:<14} {icon}")

    for platform, metric in skipped_results:
        print(f"  {C.DIM}║{C.END}  {platform:<28} {metric:<14} {C.YELLOW}SKIPPED (no data){C.END}")

    print(f"  {C.CYAN}{'─' * width}{C.END}")

    if total_checks == 0:
        print(f"  {C.YELLOW}  No comparisons were possible. Check API credentials.{C.END}")
    elif total_mismatch == 0:
        print(f"  {C.GREEN}{C.BOLD}  RESULT: {total_match}/{total_checks} MATCH — Data integrity confirmed{C.END}")
    else:
        print(f"  {C.RED}{C.BOLD}  RESULT: {total_match}/{total_checks} MATCH, {total_mismatch} MISMATCH{C.END}")

    if skipped_results:
        print(f"  {C.YELLOW}  ({len(skipped_results)} account(s) skipped — no activity in period){C.END}")

    print(f"  {C.CYAN}{'=' * width}{C.END}")
    print()

    return 0 if total_mismatch == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
