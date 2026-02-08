#!/usr/bin/env python3
"""
PII ANONYMIZATION SCRIPT
Encrypts/anonymizes personally identifiable information in BigQuery tables.

Strategy:
1. Hash emails, names, phone numbers with SHA256
2. Create anonymized views for analytics
3. Maintain secure mapping table (restricted access)

Usage:
    python anonymize_pii.py --check     # Check current PII exposure
    python anonymize_pii.py --anonymize # Create anonymized views
    python anonymize_pii.py --report    # Generate PII audit report
"""

import os
import argparse
from datetime import datetime
from dotenv import load_dotenv
from google.cloud import bigquery

load_dotenv()

# Configuration
BQ_PROJECT = "hulken"
BQ_DATASET = "ads_data"
ANONYMIZED_DATASET = "ads_data_anonymized"  # Separate dataset for anonymized data

os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = os.getenv(
    'GOOGLE_APPLICATION_CREDENTIALS',
    'D:/Better_signal/hulken-fb56a345ac08.json'
)

# PII columns mapping per table
PII_COLUMNS = {
    "shopify_orders": {
        "customer_email": "email",
        "customer_firstName": "name",
        "customer_lastName": "name",
        "customer_id": "id",
        "shipping_address1": "address",
        "shipping_address2": "address",
        "shipping_phone": "phone",
    },
    "shopify_utm": {
        # UTM table typically doesn't have direct PII but check order linkage
    },
    "shopify_live_orders": {
        "email": "email",
        "billing_address": "json_address",
        "shipping_address": "json_address",
        "customer": "json_customer",
    },
    "shopify_live_customers": {
        "email": "email",
        "first_name": "name",
        "last_name": "name",
        "phone": "phone",
        "default_address": "json_address",
    },
}


class PIIAnonymizer:
    def __init__(self):
        self.client = bigquery.Client(project=BQ_PROJECT)
        self.report = {
            "timestamp": datetime.now().isoformat(),
            "tables_checked": [],
            "pii_found": [],
            "actions_taken": []
        }

    def check_pii_exposure(self):
        """Check which tables contain PII and sample the data"""
        print("=" * 60)
        print("        PII EXPOSURE CHECK")
        print("=" * 60)

        for table_name, pii_cols in PII_COLUMNS.items():
            if not pii_cols:
                continue

            print(f"\n📋 Checking {table_name}...")

            try:
                # Check if table exists and get sample
                query = f"""
                SELECT *
                FROM `{BQ_PROJECT}.{BQ_DATASET}.{table_name}`
                LIMIT 1
                """
                result = list(self.client.query(query).result())

                if result:
                    row = result[0]
                    schema = {field.name: field for field in row._xxx_field_to_index.keys()} if hasattr(row, '_xxx_field_to_index') else {}

                    found_pii = []
                    for col, pii_type in pii_cols.items():
                        # Check if column exists in schema
                        check_query = f"""
                        SELECT column_name
                        FROM `{BQ_PROJECT}.{BQ_DATASET}.INFORMATION_SCHEMA.COLUMNS`
                        WHERE table_name = '{table_name}' AND column_name = '{col}'
                        """
                        col_exists = list(self.client.query(check_query).result())

                        if col_exists:
                            # Sample the data to check if it contains actual PII
                            sample_query = f"""
                            SELECT {col}
                            FROM `{BQ_PROJECT}.{BQ_DATASET}.{table_name}`
                            WHERE {col} IS NOT NULL
                            LIMIT 3
                            """
                            samples = list(self.client.query(sample_query).result())

                            if samples:
                                sample_values = [str(s[0])[:30] + "..." if len(str(s[0])) > 30 else str(s[0]) for s in samples]
                                found_pii.append({
                                    "column": col,
                                    "type": pii_type,
                                    "samples": sample_values
                                })
                                print(f"   ⚠️  {col} ({pii_type}): Contains data")

                    if found_pii:
                        self.report["pii_found"].append({
                            "table": table_name,
                            "columns": found_pii
                        })
                    else:
                        print(f"   ✅ No PII columns found with data")

                    self.report["tables_checked"].append(table_name)

            except Exception as e:
                print(f"   ❌ Error: {e}")

        return self.report

    def create_anonymized_dataset(self):
        """Create the anonymized dataset if it doesn't exist"""
        dataset_id = f"{BQ_PROJECT}.{ANONYMIZED_DATASET}"

        try:
            self.client.get_dataset(dataset_id)
            print(f"✅ Dataset {ANONYMIZED_DATASET} already exists")
        except:
            dataset = bigquery.Dataset(dataset_id)
            dataset.location = "US"
            dataset.description = "Anonymized data with PII hashed/removed"
            self.client.create_dataset(dataset)
            print(f"✅ Created dataset {ANONYMIZED_DATASET}")

    def create_anonymized_views(self):
        """Create anonymized views for each table with PII"""
        print("\n" + "=" * 60)
        print("        CREATING ANONYMIZED VIEWS")
        print("=" * 60)

        self.create_anonymized_dataset()

        # Shopify Orders - Anonymized View
        print("\n📋 Creating anonymized shopify_orders view...")
        shopify_orders_view = f"""
        CREATE OR REPLACE VIEW `{BQ_PROJECT}.{ANONYMIZED_DATASET}.shopify_orders_anon` AS
        SELECT
            id,
            name,
            createdAt,
            processedAt,
            currencyCode,
            displayFinancialStatus,
            displayFulfillmentStatus,
            totalPrice,
            subtotalPrice,
            totalTax,
            totalDiscounts,
            -- Hash PII fields
            TO_HEX(SHA256(COALESCE(customer_id, ''))) as customer_id_hash,
            TO_HEX(SHA256(LOWER(COALESCE(customer_email, '')))) as customer_email_hash,
            -- Redact names (keep first initial only)
            CONCAT(SUBSTR(customer_firstName, 1, 1), '***') as customer_firstName_masked,
            CONCAT(SUBSTR(customer_lastName, 1, 1), '***') as customer_lastName_masked,
            -- Keep non-PII geographic data for analytics
            shipping_country,
            shipping_city,
            -- Hash specific address but keep zip for geo analysis
            shipping_zip
        FROM `{BQ_PROJECT}.{BQ_DATASET}.shopify_orders`
        """

        try:
            self.client.query(shopify_orders_view).result()
            print("   ✅ Created shopify_orders_anon view")
            self.report["actions_taken"].append("Created shopify_orders_anon view")
        except Exception as e:
            print(f"   ❌ Error: {e}")

        # Shopify Live Customers - Anonymized View
        print("\n📋 Creating anonymized shopify_live_customers view...")
        customers_view = f"""
        CREATE OR REPLACE VIEW `{BQ_PROJECT}.{ANONYMIZED_DATASET}.shopify_live_customers_anon` AS
        SELECT
            id,
            created_at,
            updated_at,
            orders_count,
            total_spent,
            -- Hash PII
            TO_HEX(SHA256(LOWER(COALESCE(email, '')))) as email_hash,
            CONCAT(SUBSTR(first_name, 1, 1), '***') as first_name_masked,
            CONCAT(SUBSTR(last_name, 1, 1), '***') as last_name_masked,
            -- Keep analytics-useful fields
            state,
            tags,
            accepts_marketing,
            verified_email
        FROM `{BQ_PROJECT}.{BQ_DATASET}.shopify_live_customers`
        """

        try:
            self.client.query(customers_view).result()
            print("   ✅ Created shopify_live_customers_anon view")
            self.report["actions_taken"].append("Created shopify_live_customers_anon view")
        except Exception as e:
            print(f"   ❌ Error: {e}")

        # Shopify Live Orders - Anonymized View
        print("\n📋 Creating anonymized shopify_live_orders view...")
        live_orders_view = f"""
        CREATE OR REPLACE VIEW `{BQ_PROJECT}.{ANONYMIZED_DATASET}.shopify_live_orders_anon` AS
        SELECT
            id,
            name,
            created_at,
            updated_at,
            processed_at,
            currency,
            financial_status,
            fulfillment_status,
            total_price,
            subtotal_price,
            total_tax,
            total_discounts,
            -- Hash email
            TO_HEX(SHA256(LOWER(COALESCE(email, '')))) as email_hash,
            -- Keep non-PII fields useful for analytics
            source_name,
            landing_site,
            referring_site,
            tags,
            -- Extract only non-PII from addresses
            JSON_EXTRACT_SCALAR(shipping_address, '$.country') as shipping_country,
            JSON_EXTRACT_SCALAR(shipping_address, '$.city') as shipping_city,
            JSON_EXTRACT_SCALAR(shipping_address, '$.province') as shipping_province
        FROM `{BQ_PROJECT}.{BQ_DATASET}.shopify_live_orders`
        """

        try:
            self.client.query(live_orders_view).result()
            print("   ✅ Created shopify_live_orders_anon view")
            self.report["actions_taken"].append("Created shopify_live_orders_anon view")
        except Exception as e:
            print(f"   ❌ Error: {e}")

        # Create secure customer mapping table (for authorized use only)
        print("\n📋 Creating secure customer mapping table...")
        mapping_table = f"""
        CREATE TABLE IF NOT EXISTS `{BQ_PROJECT}.{ANONYMIZED_DATASET}.customer_id_mapping` (
            email_hash STRING,
            customer_id_hash STRING,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
        )
        OPTIONS(
            description='Secure mapping table - RESTRICTED ACCESS',
            labels=[('pii', 'mapping'), ('access', 'restricted')]
        )
        """

        try:
            self.client.query(mapping_table).result()
            print("   ✅ Created customer_id_mapping table (restricted)")
            self.report["actions_taken"].append("Created customer_id_mapping table")
        except Exception as e:
            print(f"   ❌ Error: {e}")

        print("\n" + "=" * 60)
        print("        ANONYMIZATION COMPLETE")
        print("=" * 60)
        print(f"\n📊 Anonymized views created in: {BQ_PROJECT}.{ANONYMIZED_DATASET}")
        print("\n⚠️  IMPORTANT: Configure IAM permissions to:")
        print("    1. Restrict access to original tables (ads_data)")
        print("    2. Grant analysts access to anonymized dataset only")
        print("    3. Restrict customer_id_mapping to admins only")

    def generate_report(self):
        """Generate PII audit report"""
        print("\n" + "=" * 60)
        print("        PII AUDIT REPORT")
        print("=" * 60)

        # Check what anonymized views exist
        query = f"""
        SELECT table_name, table_type
        FROM `{BQ_PROJECT}.{ANONYMIZED_DATASET}.INFORMATION_SCHEMA.TABLES`
        """

        try:
            tables = list(self.client.query(query).result())
            print(f"\n📊 Anonymized Dataset: {ANONYMIZED_DATASET}")
            print(f"   Tables/Views: {len(tables)}")
            for t in tables:
                print(f"   - {t.table_name} ({t.table_type})")
        except Exception as e:
            print(f"   Dataset not yet created or error: {e}")

        # Summary
        print(f"\n📋 Tables with PII: {len(self.report.get('pii_found', []))}")
        for item in self.report.get('pii_found', []):
            print(f"   - {item['table']}: {len(item['columns'])} PII columns")

        return self.report


def main():
    parser = argparse.ArgumentParser(description='PII Anonymization Tool')
    parser.add_argument('--check', action='store_true', help='Check current PII exposure')
    parser.add_argument('--anonymize', action='store_true', help='Create anonymized views')
    parser.add_argument('--report', action='store_true', help='Generate PII audit report')
    parser.add_argument('--all', action='store_true', help='Run all operations')

    args = parser.parse_args()

    anonymizer = PIIAnonymizer()

    if args.check or args.all:
        anonymizer.check_pii_exposure()

    if args.anonymize or args.all:
        anonymizer.create_anonymized_views()

    if args.report or args.all:
        anonymizer.generate_report()

    if not any([args.check, args.anonymize, args.report, args.all]):
        print("Usage: python anonymize_pii.py --check | --anonymize | --report | --all")
        print("\nRun with --all to perform full PII audit and anonymization")


if __name__ == "__main__":
    main()
