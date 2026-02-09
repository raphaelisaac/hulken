#!/usr/bin/env python3
"""
SYNC WATCHDOG - Never miss a broken sync again.
=================================================
Runs every hour via scheduled task / cron.
Checks all data sources for freshness.
Sends alerts when thresholds are breached.

Setup:
  Windows Task Scheduler:
    Action: python D:/Better_signal/data_validation/sync_watchdog.py
    Trigger: Every 1 hour

  Linux cron:
    0 * * * * cd /path/to/Better_signal && python data_validation/sync_watchdog.py

Alert methods:
  1. Log file (always)
  2. Console output (always)
  3. Email via SMTP (if configured in .env)
  4. Slack webhook (if configured in .env)
"""

import os
import sys
import json
import smtplib
from email.mime.text import MIMEText
from datetime import datetime
from pathlib import Path

if sys.platform == 'win32':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

from dotenv import load_dotenv
from google.cloud import bigquery

load_dotenv(Path(__file__).parent / '.env')

BQ_PROJECT = os.getenv('BIGQUERY_PROJECT', 'hulken')
BQ_DATASET = os.getenv('BIGQUERY_DATASET', 'ads_data')
CREDENTIALS_PATH = os.getenv('GOOGLE_APPLICATION_CREDENTIALS')
if CREDENTIALS_PATH:
    os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = CREDENTIALS_PATH

# Alert config
ALERT_EMAIL = os.getenv('ALERT_EMAIL', '')
SMTP_SERVER = os.getenv('SMTP_SERVER', '')
SMTP_PORT = int(os.getenv('SMTP_PORT', '587'))
SMTP_USER = os.getenv('SMTP_USER', '')
SMTP_PASS = os.getenv('SMTP_PASS', '')
SLACK_WEBHOOK = os.getenv('SLACK_WEBHOOK', '')

# Thresholds (hours)
THRESHOLDS = {
    'facebook_ads_insights': {'warn': 30, 'critical': 48, 'label': 'Facebook Ads', 'daily_value': 20000},
    'tiktokads_reports_daily': {'warn': 30, 'critical': 48, 'label': 'TikTok Ads', 'daily_value': 2000},
    'shopify_live_orders': {'warn': 30, 'critical': 48, 'label': 'Shopify Orders', 'daily_value': 90000},
    'shopify_live_customers': {'warn': 30, 'critical': 48, 'label': 'Shopify Customers', 'daily_value': 0},
    'shopify_live_orders_clean': {'warn': 30, 'critical': 48, 'label': 'Orders Clean (PII)', 'daily_value': 0},
    'shopify_live_customers_clean': {'warn': 30, 'critical': 48, 'label': 'Customers Clean (PII)', 'daily_value': 0},
}

LOG_PATH = Path(__file__).parent / 'sync_watchdog.log'
STATE_PATH = Path(__file__).parent / 'sync_watchdog_state.json'


def log(msg, level='INFO'):
    ts = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    line = f"[{ts}] [{level}] {msg}"
    print(line)
    with open(LOG_PATH, 'a', encoding='utf-8') as f:
        f.write(line + '\n')


def check_sync_status():
    """Query BigQuery for table freshness."""
    bq = bigquery.Client(project=BQ_PROJECT)

    tables = "', '".join(THRESHOLDS.keys())
    sql = f"""
    SELECT
      table_id,
      TIMESTAMP_MILLIS(last_modified_time) as last_modified,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), TIMESTAMP_MILLIS(last_modified_time), HOUR) as hours_behind,
      row_count
    FROM `{BQ_PROJECT}.{BQ_DATASET}.__TABLES__`
    WHERE table_id IN ('{tables}')
    """

    results = list(bq.query(sql).result())
    alerts = []

    for row in results:
        table = row.table_id
        hours = row.hours_behind
        config = THRESHOLDS.get(table, {})

        if hours >= config.get('critical', 48):
            days = hours // 24
            missed_value = days * config.get('daily_value', 0)
            alert = {
                'level': 'CRITICAL',
                'table': table,
                'label': config.get('label', table),
                'hours': hours,
                'days': days,
                'missed_value': missed_value,
                'message': f"CRITICAL: {config.get('label', table)} is {days} days behind ({hours}h). ~${missed_value:,.0f} untracked."
            }
            alerts.append(alert)
            log(alert['message'], 'CRITICAL')
        elif hours >= config.get('warn', 30):
            alert = {
                'level': 'WARNING',
                'table': table,
                'label': config.get('label', table),
                'hours': hours,
                'days': hours // 24,
                'missed_value': 0,
                'message': f"WARNING: {config.get('label', table)} is {hours}h behind schedule."
            }
            alerts.append(alert)
            log(alert['message'], 'WARNING')
        else:
            log(f"OK: {config.get('label', table)} - {hours}h since update ({row.row_count:,} rows)")

    return alerts


def should_alert(alerts):
    """Check if we already alerted recently to avoid spam."""
    if not alerts:
        return False

    if STATE_PATH.exists():
        try:
            state = json.loads(STATE_PATH.read_text())
            last_alert = datetime.fromisoformat(state.get('last_alert', '2000-01-01'))
            hours_since = (datetime.now() - last_alert).total_seconds() / 3600

            # Don't re-alert if we already alerted in the last 4 hours for same tables
            if hours_since < 4:
                last_tables = set(state.get('alerted_tables', []))
                current_tables = set(a['table'] for a in alerts)
                if current_tables.issubset(last_tables):
                    log("Skipping alert - already alerted for these tables within 4 hours")
                    return False
        except (json.JSONDecodeError, ValueError):
            pass

    return True


def send_email_alert(alerts):
    """Send alert via email."""
    if not ALERT_EMAIL or not SMTP_SERVER:
        return

    critical = [a for a in alerts if a['level'] == 'CRITICAL']
    subject = f"[Better Signal] {'CRITICAL' if critical else 'WARNING'}: Data sync issues detected"

    body = "Better Signal Sync Watchdog Alert\n"
    body += "=" * 50 + "\n\n"
    body += f"Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n"

    for a in alerts:
        body += f"[{a['level']}] {a['label']}\n"
        body += f"  - {a['hours']}h behind ({a['days']} days)\n"
        if a['missed_value'] > 0:
            body += f"  - Estimated untracked: ${a['missed_value']:,.0f}\n"
        body += "\n"

    body += "\nAction Required:\n"
    body += "1. SSH to Airbyte VM\n"
    body += "2. Check connection status and error logs\n"
    body += "3. Trigger manual sync for failed connections\n"
    body += "4. See docs/runbooks/airbyte_runbook.md for details\n"

    try:
        msg = MIMEText(body)
        msg['Subject'] = subject
        msg['From'] = SMTP_USER
        msg['To'] = ALERT_EMAIL

        with smtplib.SMTP(SMTP_SERVER, SMTP_PORT) as server:
            server.starttls()
            server.login(SMTP_USER, SMTP_PASS)
            server.send_message(msg)
        log(f"Email alert sent to {ALERT_EMAIL}")
    except Exception as e:
        log(f"Failed to send email: {e}", 'ERROR')


def send_slack_alert(alerts):
    """Send alert via Slack webhook."""
    if not SLACK_WEBHOOK:
        return

    try:
        import requests
    except ImportError:
        log("requests not installed, skipping Slack alert", 'WARNING')
        return

    critical = [a for a in alerts if a['level'] == 'CRITICAL']
    emoji = ":rotating_light:" if critical else ":warning:"

    blocks = [
        {
            "type": "header",
            "text": {"type": "plain_text", "text": f"{emoji} Data Sync Alert - Better Signal"}
        }
    ]

    for a in alerts:
        icon = ":red_circle:" if a['level'] == 'CRITICAL' else ":large_yellow_circle:"
        text = f"{icon} *{a['label']}*: {a['hours']}h behind ({a['days']} days)"
        if a['missed_value'] > 0:
            text += f" | ~${a['missed_value']:,.0f} untracked"
        blocks.append({"type": "section", "text": {"type": "mrkdwn", "text": text}})

    blocks.append({
        "type": "section",
        "text": {"type": "mrkdwn", "text": "*Action:* SSH to Airbyte VM, restart failed connections. See `airbyte_runbook.md`."}
    })

    try:
        resp = requests.post(SLACK_WEBHOOK, json={"blocks": blocks})
        if resp.status_code == 200:
            log("Slack alert sent")
        else:
            log(f"Slack alert failed: {resp.status_code}", 'ERROR')
    except Exception as e:
        log(f"Slack alert error: {e}", 'ERROR')


def save_state(alerts):
    """Save alert state to prevent spam."""
    state = {
        'last_alert': datetime.now().isoformat(),
        'alerted_tables': [a['table'] for a in alerts],
        'alert_count': len(alerts),
    }
    STATE_PATH.write_text(json.dumps(state, indent=2))


def main():
    log("=" * 50)
    log("Sync Watchdog starting")

    alerts = check_sync_status()

    if alerts and should_alert(alerts):
        log(f"{len(alerts)} alert(s) detected - sending notifications")
        send_email_alert(alerts)
        send_slack_alert(alerts)
        save_state(alerts)
    elif alerts:
        log(f"{len(alerts)} alert(s) detected but already notified recently")
    else:
        log("All syncs are healthy")

    log("Sync Watchdog complete")


if __name__ == "__main__":
    main()
