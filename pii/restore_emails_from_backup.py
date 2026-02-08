#!/usr/bin/env python3
"""
RESTORE EMAILS FROM ORIGINAL JSONL BACKUP

This script restores the original email data from the Shopify bulk export
and re-creates the email columns that were accidentally deleted.

Strategy:
1. Add email columns back to tables
2. Load original emails from JSONL
3. Update tables with original emails
4. Keep both email AND email_hash (nullify email later if needed, but NEVER delete column)
"""

import json
import os
from google.cloud import bigquery

# Config
os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = 'D:/Better_signal/hulken-fb56a345ac08.json'
BQ_PROJECT = "hulken"
BQ_DATASET = "ads_data"
JSONL_PATH = "D:/Better_signal/Shopify/hulken-orders-bulk-export.jsonl"

def main():
    client = bigquery.Client(project=BQ_PROJECT)

    print("=" * 60)
    print("RESTORE EMAILS FROM BACKUP")
    print("=" * 60)

    # Step 1: Add email columns back
    print("\n[1/4] Adding email columns back to shopify_orders...")

    alter_queries = [
        "ALTER TABLE `hulken.ads_data.shopify_orders` ADD COLUMN IF NOT EXISTS customer_email STRING",
        "ALTER TABLE `hulken.ads_data.shopify_orders` ADD COLUMN IF NOT EXISTS customer_firstName STRING",
        "ALTER TABLE `hulken.ads_data.shopify_orders` ADD COLUMN IF NOT EXISTS customer_lastName STRING",
    ]

    for q in alter_queries:
        try:
            client.query(q).result()
            print(f"   OK: {q.split('ADD COLUMN IF NOT EXISTS ')[1].split(' ')[0]}")
        except Exception as e:
            print(f"   Error: {e}")

    # Step 2: Load emails from JSONL
    print("\n[2/4] Loading emails from JSONL backup...")

    emails_data = []
    with open(JSONL_PATH, 'r', encoding='utf-8') as f:
        for line in f:
            try:
                order = json.loads(line)
                order_id = order.get('id')
                customer = order.get('customer', {})

                if customer and order_id:
                    emails_data.append({
                        'order_id': order_id,
                        'customer_email': customer.get('email'),
                        'customer_firstName': customer.get('firstName'),
                        'customer_lastName': customer.get('lastName'),
                    })
            except json.JSONDecodeError:
                continue

    print(f"   Loaded {len(emails_data):,} orders with customer data")

    # Step 3: Create temp table with email data
    print("\n[3/4] Creating temp table with email data...")

    temp_table = f"{BQ_PROJECT}.{BQ_DATASET}.temp_email_restore"

    # Create schema
    schema = [
        bigquery.SchemaField("order_id", "STRING"),
        bigquery.SchemaField("customer_email", "STRING"),
        bigquery.SchemaField("customer_firstName", "STRING"),
        bigquery.SchemaField("customer_lastName", "STRING"),
    ]

    # Load to temp table
    job_config = bigquery.LoadJobConfig(
        schema=schema,
        write_disposition="WRITE_TRUNCATE",
    )

    job = client.load_table_from_json(emails_data, temp_table, job_config=job_config)
    job.result()
    print(f"   Uploaded {len(emails_data):,} rows to temp table")

    # Step 4: Update main table from temp
    print("\n[4/4] Updating shopify_orders with restored emails...")

    update_query = f"""
    UPDATE `{BQ_PROJECT}.{BQ_DATASET}.shopify_orders` t
    SET
        t.customer_email = s.customer_email,
        t.customer_firstName = s.customer_firstName,
        t.customer_lastName = s.customer_lastName
    FROM `{temp_table}` s
    WHERE t.id = s.order_id
    """

    result = client.query(update_query).result()
    print(f"   Updated shopify_orders with original emails")

    # Verify
    print("\n[VERIFICATION]")
    verify_query = f"""
    SELECT
        COUNT(*) as total,
        COUNTIF(customer_email IS NOT NULL) as with_email,
        COUNTIF(email_hash IS NOT NULL) as with_hash
    FROM `{BQ_PROJECT}.{BQ_DATASET}.shopify_orders`
    """

    result = list(client.query(verify_query).result())[0]
    print(f"   Total rows: {result.total:,}")
    print(f"   With email: {result.with_email:,}")
    print(f"   With hash:  {result.with_hash:,}")

    # Cleanup temp table
    client.delete_table(temp_table, not_found_ok=True)
    print(f"\n   Cleaned up temp table")

    print("\n" + "=" * 60)
    print("RESTORATION COMPLETE")
    print("=" * 60)
    print("\nNOTE: Both customer_email AND email_hash now exist.")
    print("To anonymize: SET customer_email = NULL (don't DELETE column)")


if __name__ == "__main__":
    main()
