#!/usr/bin/env python3
"""
RESTORE PII FROM JSONL BACKUP TO SHOPIFY_ORDERS TABLE

This script restores the original PII columns that were accidentally DELETED
from the shopify_orders table. It uses the JSONL backup file from the original
Shopify bulk export.

IMPORTANT: This script ADDS columns back and populates them, but does NOT delete
anything. After restoration:
1. Verify data is correct
2. Hash emails to email_hash column (if not already done)
3. SET values to NULL (don't delete columns)

Strategy:
1. Add customer_email, customer_firstName, customer_lastName columns (if missing)
2. Load original data from JSONL backup
3. Create temp table with email data
4. Update shopify_orders with original values
5. Verify restoration was successful

Usage:
    python restore_shopify_orders_pii.py [--dry-run]

Arguments:
    --dry-run    Show what would be done without making changes
"""

import json
import os
import sys
from datetime import datetime

# Google Cloud BigQuery
from google.cloud import bigquery

# Configuration
GOOGLE_CREDENTIALS = 'D:/Better_signal/hulken-fb56a345ac08.json'
BQ_PROJECT = "hulken"
BQ_DATASET = "ads_data"
BQ_TABLE = "shopify_orders"
JSONL_PATH = "D:/Better_signal/Shopify/hulken-orders-bulk-export.jsonl"
TEMP_TABLE = f"{BQ_PROJECT}.{BQ_DATASET}.temp_pii_restore_{datetime.now().strftime('%Y%m%d_%H%M%S')}"


def setup_credentials():
    """Set up Google Cloud credentials."""
    if os.path.exists(GOOGLE_CREDENTIALS):
        os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = GOOGLE_CREDENTIALS
        print(f"[OK] Using credentials: {GOOGLE_CREDENTIALS}")
    else:
        print(f"[ERROR] Credentials file not found: {GOOGLE_CREDENTIALS}")
        sys.exit(1)


def check_current_state(client):
    """Check the current state of the shopify_orders table."""
    print("\n" + "=" * 60)
    print("CURRENT STATE CHECK")
    print("=" * 60)

    # Check which columns exist
    query = f"""
    SELECT column_name
    FROM `{BQ_PROJECT}.{BQ_DATASET}.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = '{BQ_TABLE}'
    AND column_name IN ('customer_email', 'customer_firstName', 'customer_lastName', 'email_hash')
    ORDER BY column_name
    """
    result = client.query(query).result()
    existing_columns = [row.column_name for row in result]

    print(f"\nExisting PII-related columns: {existing_columns}")

    # Check row counts
    query = f"""
    SELECT
        COUNT(*) as total_rows,
        COUNTIF(email_hash IS NOT NULL) as with_email_hash
    FROM `{BQ_PROJECT}.{BQ_DATASET}.{BQ_TABLE}`
    """
    result = list(client.query(query).result())[0]

    print(f"Total rows: {result.total_rows:,}")
    print(f"Rows with email_hash: {result.with_email_hash:,}")

    return existing_columns


def load_jsonl_data():
    """Load customer data from JSONL backup file."""
    print("\n" + "=" * 60)
    print("LOADING JSONL BACKUP")
    print("=" * 60)

    if not os.path.exists(JSONL_PATH):
        print(f"[ERROR] JSONL file not found: {JSONL_PATH}")
        sys.exit(1)

    print(f"Loading from: {JSONL_PATH}")

    email_data = []
    processed = 0
    errors = 0

    with open(JSONL_PATH, 'r', encoding='utf-8') as f:
        for line in f:
            processed += 1
            if processed % 100000 == 0:
                print(f"  Processed {processed:,} lines...")

            try:
                order = json.loads(line)
                order_id = order.get('id')
                customer = order.get('customer', {})

                if order_id and customer:
                    email_data.append({
                        'order_id': order_id,
                        'customer_email': customer.get('email'),
                        'customer_firstName': customer.get('firstName'),
                        'customer_lastName': customer.get('lastName'),
                    })
            except json.JSONDecodeError:
                errors += 1
                continue

    print(f"\nProcessed {processed:,} total lines")
    print(f"Extracted {len(email_data):,} orders with customer data")
    if errors:
        print(f"Skipped {errors:,} lines due to JSON errors")

    # Show sample
    if email_data:
        print("\nSample data (first 3 records):")
        for i, record in enumerate(email_data[:3]):
            email_display = record['customer_email'][:30] + "..." if record['customer_email'] and len(record['customer_email']) > 30 else record['customer_email']
            print(f"  {i+1}. {record['order_id'][:50]} | {email_display}")

    return email_data


def add_missing_columns(client, existing_columns, dry_run=False):
    """Add missing PII columns to the table."""
    print("\n" + "=" * 60)
    print("ADDING MISSING COLUMNS")
    print("=" * 60)

    columns_to_add = []
    if 'customer_email' not in existing_columns:
        columns_to_add.append(('customer_email', 'STRING'))
    if 'customer_firstName' not in existing_columns:
        columns_to_add.append(('customer_firstName', 'STRING'))
    if 'customer_lastName' not in existing_columns:
        columns_to_add.append(('customer_lastName', 'STRING'))

    if not columns_to_add:
        print("All required columns already exist.")
        return

    for col_name, col_type in columns_to_add:
        query = f"ALTER TABLE `{BQ_PROJECT}.{BQ_DATASET}.{BQ_TABLE}` ADD COLUMN IF NOT EXISTS {col_name} {col_type}"

        if dry_run:
            print(f"[DRY-RUN] Would execute: {query}")
        else:
            print(f"Adding column: {col_name}...")
            try:
                client.query(query).result()
                print(f"  [OK] Added {col_name}")
            except Exception as e:
                print(f"  [ERROR] Failed to add {col_name}: {e}")


def create_temp_table(client, email_data, dry_run=False):
    """Create temporary table with email data."""
    print("\n" + "=" * 60)
    print("CREATING TEMP TABLE")
    print("=" * 60)

    if dry_run:
        print(f"[DRY-RUN] Would create temp table: {TEMP_TABLE}")
        print(f"[DRY-RUN] Would upload {len(email_data):,} rows")
        return

    print(f"Creating temp table: {TEMP_TABLE}")

    schema = [
        bigquery.SchemaField("order_id", "STRING"),
        bigquery.SchemaField("customer_email", "STRING"),
        bigquery.SchemaField("customer_firstName", "STRING"),
        bigquery.SchemaField("customer_lastName", "STRING"),
    ]

    job_config = bigquery.LoadJobConfig(
        schema=schema,
        write_disposition="WRITE_TRUNCATE",
    )

    job = client.load_table_from_json(email_data, TEMP_TABLE, job_config=job_config)
    job.result()

    print(f"[OK] Uploaded {len(email_data):,} rows to temp table")


def update_main_table(client, dry_run=False):
    """Update main table from temp table."""
    print("\n" + "=" * 60)
    print("UPDATING MAIN TABLE")
    print("=" * 60)

    update_query = f"""
    UPDATE `{BQ_PROJECT}.{BQ_DATASET}.{BQ_TABLE}` t
    SET
        t.customer_email = s.customer_email,
        t.customer_firstName = s.customer_firstName,
        t.customer_lastName = s.customer_lastName
    FROM `{TEMP_TABLE}` s
    WHERE t.id = s.order_id
    """

    if dry_run:
        print(f"[DRY-RUN] Would execute UPDATE query")
        print(f"[DRY-RUN] Joining on: t.id = s.order_id")
        return

    print("Running UPDATE query...")
    result = client.query(update_query).result()
    print(f"[OK] Updated shopify_orders with restored PII data")


def verify_restoration(client, dry_run=False):
    """Verify the restoration was successful."""
    print("\n" + "=" * 60)
    print("VERIFICATION")
    print("=" * 60)

    if dry_run:
        print("[DRY-RUN] Would verify restoration")
        return

    query = f"""
    SELECT
        COUNT(*) as total_rows,
        COUNTIF(customer_email IS NOT NULL) as with_email,
        COUNTIF(customer_firstName IS NOT NULL) as with_first_name,
        COUNTIF(customer_lastName IS NOT NULL) as with_last_name,
        COUNTIF(email_hash IS NOT NULL) as with_hash
    FROM `{BQ_PROJECT}.{BQ_DATASET}.{BQ_TABLE}`
    """

    result = list(client.query(query).result())[0]

    print(f"Total rows:           {result.total_rows:,}")
    print(f"With customer_email:  {result.with_email:,}")
    print(f"With firstName:       {result.with_first_name:,}")
    print(f"With lastName:        {result.with_last_name:,}")
    print(f"With email_hash:      {result.with_hash:,}")

    # Sample check
    query = f"""
    SELECT id, customer_email, customer_firstName, customer_lastName, email_hash
    FROM `{BQ_PROJECT}.{BQ_DATASET}.{BQ_TABLE}`
    WHERE customer_email IS NOT NULL
    LIMIT 3
    """

    print("\nSample restored records:")
    for row in client.query(query).result():
        email_display = row.customer_email[:30] + "..." if len(row.customer_email) > 30 else row.customer_email
        print(f"  {row.id[:40]} | {email_display} | {row.customer_firstName} {row.customer_lastName}")


def cleanup_temp_table(client, dry_run=False):
    """Delete the temporary table."""
    print("\n" + "=" * 60)
    print("CLEANUP")
    print("=" * 60)

    if dry_run:
        print(f"[DRY-RUN] Would delete temp table: {TEMP_TABLE}")
        return

    client.delete_table(TEMP_TABLE, not_found_ok=True)
    print(f"[OK] Deleted temp table: {TEMP_TABLE}")


def main():
    """Main function."""
    dry_run = '--dry-run' in sys.argv

    print("=" * 60)
    print("PII RESTORATION FOR SHOPIFY_ORDERS")
    print("=" * 60)
    print(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Mode: {'DRY-RUN (no changes will be made)' if dry_run else 'LIVE'}")

    # Setup
    setup_credentials()
    client = bigquery.Client(project=BQ_PROJECT)

    # Step 1: Check current state
    existing_columns = check_current_state(client)

    # Step 2: Load JSONL data
    email_data = load_jsonl_data()

    if not email_data:
        print("\n[ERROR] No data loaded from JSONL. Aborting.")
        return

    # Step 3: Add missing columns
    add_missing_columns(client, existing_columns, dry_run)

    # Step 4: Create temp table
    create_temp_table(client, email_data, dry_run)

    # Step 5: Update main table
    update_main_table(client, dry_run)

    # Step 6: Verify
    verify_restoration(client, dry_run)

    # Step 7: Cleanup
    cleanup_temp_table(client, dry_run)

    print("\n" + "=" * 60)
    print("RESTORATION COMPLETE")
    print("=" * 60)

    if not dry_run:
        print("""
NEXT STEPS:
1. Verify the data looks correct
2. Update email_hash for any new records:
   UPDATE hulken.ads_data.shopify_orders
   SET email_hash = TO_HEX(SHA256(LOWER(TRIM(customer_email))))
   WHERE customer_email IS NOT NULL AND email_hash IS NULL;

3. NEVER delete columns - only SET values to NULL when ready:
   UPDATE hulken.ads_data.shopify_orders
   SET customer_email = NULL, customer_firstName = NULL, customer_lastName = NULL
   WHERE email_hash IS NOT NULL;
""")


if __name__ == "__main__":
    main()
