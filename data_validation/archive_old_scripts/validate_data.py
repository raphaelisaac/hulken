#!/usr/bin/env python3
"""
Data Validation Script - Compare BigQuery data with source APIs
Validates data integrity between Airbyte destination and original sources.
"""

import os
import json
import requests
from datetime import datetime, timedelta
from dotenv import load_dotenv
from google.cloud import bigquery
from tabulate import tabulate

# Load environment variables
load_dotenv()

# Configuration
BQ_PROJECT = os.getenv('BIGQUERY_PROJECT', 'hulken')
BQ_DATASET = os.getenv('BIGQUERY_DATASET', 'ads_data')

class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    END = '\033[0m'
    BOLD = '\033[1m'

def print_header(title):
    print(f"\n{Colors.BLUE}{Colors.BOLD}{'='*60}{Colors.END}")
    print(f"{Colors.BLUE}{Colors.BOLD}{title:^60}{Colors.END}")
    print(f"{Colors.BLUE}{Colors.BOLD}{'='*60}{Colors.END}\n")

def print_status(name, source_val, bq_val, tolerance=0.02):
    """Print validation status with color coding"""
    if source_val is None or bq_val is None:
        status = f"{Colors.YELLOW}[SKIP]{Colors.END}"
        diff = "N/A"
        is_ok = None
    elif source_val == 0 and bq_val == 0:
        status = f"{Colors.GREEN}[OK]{Colors.END}"
        diff = "0.00%"
        is_ok = True
    elif source_val == 0:
        status = f"{Colors.YELLOW}[WARN]{Colors.END}"
        diff = "Source=0"
        is_ok = True
    else:
        diff_pct = abs(source_val - bq_val) / source_val
        if diff_pct <= tolerance:
            status = f"{Colors.GREEN}[OK]{Colors.END}"
            is_ok = True
        else:
            status = f"{Colors.RED}[MISMATCH]{Colors.END}"
            is_ok = False
        diff = f"{diff_pct*100:.2f}%"

    print(f"  {status} {name}: Source={source_val:,.2f} | BigQuery={bq_val:,.2f} | Diff={diff}")
    return is_ok

# ============================================================================
# BigQuery Functions
# ============================================================================

def get_bigquery_client():
    """Initialize BigQuery client"""
    creds_path = os.getenv('GOOGLE_APPLICATION_CREDENTIALS')
    if creds_path:
        os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = creds_path
    return bigquery.Client(project=BQ_PROJECT)

def get_bigquery_facebook_stats_by_account(client, account_id, start_date, end_date):
    """Get Facebook stats from BigQuery for a specific account"""
    query = f"""
    SELECT
        COALESCE(SUM(spend), 0) as total_spend,
        COALESCE(SUM(impressions), 0) as total_impressions,
        COALESCE(SUM(clicks), 0) as total_clicks,
        COUNT(*) as row_count
    FROM `{BQ_PROJECT}.{BQ_DATASET}.facebook_insights`
    WHERE date_start BETWEEN '{start_date}' AND '{end_date}'
    AND account_id = '{account_id}'
    """
    try:
        result = client.query(query).result()
        for row in result:
            return {
                'spend': float(row.total_spend or 0),
                'impressions': int(row.total_impressions or 0),
                'clicks': int(row.total_clicks or 0),
                'rows': int(row.row_count or 0)
            }
    except Exception as e:
        print(f"  {Colors.RED}[ERROR]{Colors.END} BigQuery: {str(e)}")
    return {'spend': 0, 'impressions': 0, 'clicks': 0, 'rows': 0}

def get_bigquery_tiktok_stats(client, start_date, end_date):
    """Get TikTok stats from BigQuery"""
    query = f"""
    SELECT
        COALESCE(SUM(spend), 0) as total_spend,
        COALESCE(SUM(impressions), 0) as total_impressions,
        COALESCE(SUM(clicks), 0) as total_clicks,
        COUNT(*) as row_count
    FROM `{BQ_PROJECT}.{BQ_DATASET}.tiktok_ads_reports_daily`
    WHERE report_date BETWEEN '{start_date}' AND '{end_date}'
    """
    try:
        result = client.query(query).result()
        for row in result:
            return {
                'spend': float(row.total_spend or 0),
                'impressions': int(row.total_impressions or 0),
                'clicks': int(row.total_clicks or 0),
                'rows': int(row.row_count or 0)
            }
    except Exception as e:
        print(f"  {Colors.RED}[ERROR]{Colors.END} BigQuery TikTok: {str(e)}")
    return {'spend': 0, 'impressions': 0, 'clicks': 0, 'rows': 0}

# ============================================================================
# Facebook Marketing API
# ============================================================================

def get_facebook_account_name(account_id, access_token):
    """Get Facebook account name"""
    url = f"https://graph.facebook.com/v18.0/act_{account_id}"
    params = {'access_token': access_token, 'fields': 'name'}
    try:
        response = requests.get(url, params=params)
        data = response.json()
        return data.get('name', account_id)
    except:
        return account_id

def get_facebook_stats_by_account(account_id, start_date, end_date):
    """Get stats for a single Facebook account"""
    access_token = os.getenv('FACEBOOK_ACCESS_TOKEN')
    if not access_token:
        return None

    url = f"https://graph.facebook.com/v18.0/act_{account_id}/insights"
    params = {
        'access_token': access_token,
        'time_range': json.dumps({'since': start_date, 'until': end_date}),
        'fields': 'spend,impressions,clicks',
        'level': 'account'
    }

    try:
        response = requests.get(url, params=params)
        data = response.json()

        if 'data' in data and len(data['data']) > 0:
            row = data['data'][0]
            return {
                'spend': float(row.get('spend', 0)),
                'impressions': int(row.get('impressions', 0)),
                'clicks': int(row.get('clicks', 0))
            }
        elif 'error' in data:
            print(f"  {Colors.RED}[ERROR]{Colors.END} Facebook API: {data['error'].get('message', 'Unknown')}")
            return None
        else:
            # No data for this period
            return {'spend': 0, 'impressions': 0, 'clicks': 0}

    except Exception as e:
        print(f"  {Colors.RED}[ERROR]{Colors.END} Facebook request failed: {str(e)}")
        return None

# ============================================================================
# TikTok Marketing API
# ============================================================================

def get_tiktok_stats(start_date, end_date):
    """Get stats directly from TikTok Marketing API"""
    access_token = os.getenv('TIKTOK_ACCESS_TOKEN')
    advertiser_id = os.getenv('TIKTOK_ADVERTISER_ID')

    if not access_token or not advertiser_id:
        print(f"  {Colors.YELLOW}[WARN]{Colors.END} TikTok credentials not configured")
        return None

    url = "https://business-api.tiktok.com/open_api/v1.3/report/integrated/get/"
    headers = {
        'Access-Token': access_token
    }

    # Use GET with params (not POST with JSON body)
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
        response = requests.get(url, headers=headers, params=params)
        data = response.json()

        if data.get('code') == 0 and 'data' in data:
            rows = data['data'].get('list', [])
            total_spend = 0
            total_impressions = 0
            total_clicks = 0

            for row in rows:
                metrics = row.get('metrics', {})
                total_spend += float(metrics.get('spend', 0) or 0)
                total_impressions += int(float(metrics.get('impressions', 0) or 0))
                total_clicks += int(float(metrics.get('clicks', 0) or 0))

            return {
                'spend': total_spend,
                'impressions': total_impressions,
                'clicks': total_clicks
            }
        else:
            error_msg = data.get('message', 'Unknown error')
            print(f"  {Colors.RED}[ERROR]{Colors.END} TikTok API: {error_msg}")
            return None

    except Exception as e:
        print(f"  {Colors.RED}[ERROR]{Colors.END} TikTok API request failed: {str(e)}")
        return None

# ============================================================================
# Main Validation
# ============================================================================

def validate_metrics(source_stats, bq_stats, tolerance=0.02):
    """Validate metrics between source and BigQuery"""
    results = []
    all_ok = True

    for metric in ['spend', 'impressions', 'clicks']:
        source_val = source_stats.get(metric, 0) if source_stats else 0
        bq_val = bq_stats.get(metric, 0) if bq_stats else 0

        is_ok = print_status(metric.capitalize(), source_val, bq_val, tolerance)
        if is_ok is False:
            all_ok = False

    return all_ok

def main():
    """Main validation function"""
    print_header("DATA VALIDATION REPORT")
    print(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    # Date range (last 7 days)
    end_date = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')
    start_date = (datetime.now() - timedelta(days=7)).strftime('%Y-%m-%d')

    print(f"Validation Period: {start_date} to {end_date}\n")

    # Initialize BigQuery
    print("Connecting to BigQuery...")
    try:
        bq_client = get_bigquery_client()
        print(f"  {Colors.GREEN}[OK]{Colors.END} Connected to BigQuery\n")
    except Exception as e:
        print(f"  {Colors.RED}[ERROR]{Colors.END} Failed to connect to BigQuery: {str(e)}")
        return 1

    validation_results = []
    access_token = os.getenv('FACEBOOK_ACCESS_TOKEN')

    # ========== Facebook Validation (by account) ==========
    print_header("FACEBOOK ADS VALIDATION")

    account_ids = os.getenv('FACEBOOK_ACCOUNT_IDS', '').split(',')
    account_ids = [a.strip() for a in account_ids if a.strip()]

    if not account_ids or not access_token:
        print(f"  {Colors.YELLOW}[SKIP]{Colors.END} Facebook credentials not configured")
    else:
        for account_id in account_ids:
            account_name = get_facebook_account_name(account_id, access_token)
            print(f"\n{Colors.BOLD}Account: {account_name} ({account_id}){Colors.END}")

            print("  Fetching from Facebook API...")
            fb_source = get_facebook_stats_by_account(account_id, start_date, end_date)

            print("  Fetching from BigQuery...")
            fb_bq = get_bigquery_facebook_stats_by_account(bq_client, account_id, start_date, end_date)

            if fb_bq['rows'] == 0:
                print(f"  {Colors.YELLOW}[INFO]{Colors.END} No data in BigQuery for this account (not synced yet)")
                validation_results.append({
                    'platform': f'Facebook - {account_name}',
                    'status': 'NOT SYNCED'
                })
            elif fb_source is None:
                print(f"  {Colors.RED}[ERROR]{Colors.END} Could not fetch from Facebook API")
                validation_results.append({
                    'platform': f'Facebook - {account_name}',
                    'status': 'API ERROR'
                })
            else:
                print(f"\n  Comparing:")
                is_ok = validate_metrics(fb_source, fb_bq)
                validation_results.append({
                    'platform': f'Facebook - {account_name}',
                    'status': 'PASS' if is_ok else 'FAIL'
                })

    # ========== TikTok Validation ==========
    print_header("TIKTOK ADS VALIDATION")

    print("Fetching from TikTok API...")
    tt_source = get_tiktok_stats(start_date, end_date)

    print("Fetching from BigQuery...")
    tt_bq = get_bigquery_tiktok_stats(bq_client, start_date, end_date)

    if tt_bq['rows'] == 0:
        print(f"  {Colors.YELLOW}[INFO]{Colors.END} No TikTok data in BigQuery")
        validation_results.append({'platform': 'TikTok', 'status': 'NO DATA'})
    elif tt_source is None:
        print(f"  {Colors.YELLOW}[WARN]{Colors.END} Could not validate - API error or credentials issue")
        validation_results.append({'platform': 'TikTok', 'status': 'API ERROR'})
    else:
        print(f"\nComparing ({start_date} to {end_date}):")
        is_ok = validate_metrics(tt_source, tt_bq)
        validation_results.append({
            'platform': 'TikTok',
            'status': 'PASS' if is_ok else 'FAIL'
        })

    # ========== Summary ==========
    print_header("VALIDATION SUMMARY")

    summary_data = []
    has_failures = False
    has_passes = False

    for result in validation_results:
        status = result['status']
        if status == 'PASS':
            status_colored = f"{Colors.GREEN}{status}{Colors.END}"
            has_passes = True
        elif status == 'FAIL':
            status_colored = f"{Colors.RED}{status}{Colors.END}"
            has_failures = True
        elif status == 'NOT SYNCED':
            status_colored = f"{Colors.YELLOW}{status}{Colors.END}"
        else:
            status_colored = f"{Colors.YELLOW}{status}{Colors.END}"

        summary_data.append([result['platform'], status_colored])

    print(tabulate(summary_data, headers=['Platform', 'Status'], tablefmt='grid'))

    print(f"\n{'='*60}")
    if has_failures:
        print(f"{Colors.RED}{Colors.BOLD}VALIDATION FAILED - Check mismatches above{Colors.END}")
        exit_code = 1
    elif has_passes:
        print(f"{Colors.GREEN}{Colors.BOLD}ALL SYNCED DATA VALIDATED - Data integrity confirmed{Colors.END}")
        exit_code = 0
    else:
        print(f"{Colors.YELLOW}{Colors.BOLD}NO DATA TO VALIDATE - Check Airbyte sync status{Colors.END}")
        exit_code = 0
    print(f"{'='*60}\n")

    return exit_code

if __name__ == "__main__":
    exit(main())
