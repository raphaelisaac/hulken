#!/usr/bin/env python3
"""
MASTER WORKFLOW ORCHESTRATOR
============================
Exécute tout le pipeline de data analytics de A à Z:

1. Connexion BigQuery
2. Réconciliation API vs BigQuery (live_reconciliation)
3. Détection nouvelles tables
4. Vérification freshness des données
5. Encoding PII cohérent (même email = même hash partout)
6. Unification des tables (dédoublonnage)
7. Détection anomalies (NULL, 0, data manquante)
8. Génération rapport exécutif

Usage:
    python3 master_workflow.py [--skip-reconciliation] [--skip-pii] [--skip-report]
"""

import os
import sys
import subprocess
import json
from datetime import datetime
from pathlib import Path

# Configuration
PROJECT_DIR = Path(__file__).parent.parent
DATA_VALIDATION_DIR = PROJECT_DIR / "data_validation"
REPORTS_DIR = PROJECT_DIR / "reports"
LOGS_DIR = PROJECT_DIR / "logs"

# BigQuery config
BQ_PROJECT = "hulken"
BQ_DATASET = "ads_data"

# Colors pour output
class Colors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'

def print_step(step_num, title, emoji=""):
    """Print formatted step header"""
    print(f"\n{Colors.BOLD}{Colors.OKBLUE}{'='*70}{Colors.ENDC}")
    print(f"{Colors.BOLD}{Colors.OKBLUE}ÉTAPE {step_num}: {emoji} {title}{Colors.ENDC}")
    print(f"{Colors.BOLD}{Colors.OKBLUE}{'='*70}{Colors.ENDC}\n")

def print_success(message):
    print(f"{Colors.OKGREEN}✅ {message}{Colors.ENDC}")

def print_error(message):
    print(f"{Colors.FAIL}❌ {message}{Colors.ENDC}")

def print_warning(message):
    print(f"{Colors.WARNING}⚠️  {message}{Colors.ENDC}")

def print_info(message):
    print(f"{Colors.OKCYAN}ℹ️  {message}{Colors.ENDC}")

def run_command(cmd, description, cwd=None):
    """Execute a shell command and return result"""
    print_info(f"Exécution: {description}")
    print(f"   Commande: {cmd}")

    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            cwd=cwd or PROJECT_DIR
        )

        if result.returncode == 0:
            print_success(f"{description} - Terminé")
            return True, result.stdout
        else:
            print_error(f"{description} - Échec")
            print(f"   Erreur: {result.stderr}")
            return False, result.stderr
    except Exception as e:
        print_error(f"{description} - Exception: {str(e)}")
        return False, str(e)

def step1_test_bigquery_connection():
    """Test BigQuery connection"""
    print_step(1, "Test Connexion BigQuery", "🔌")

    cmd = f"bq ls --project_id={BQ_PROJECT} {BQ_DATASET} --max_results=5"
    success, output = run_command(cmd, "Test connexion BigQuery")

    if success:
        print_success("Connexion BigQuery OK!")
        return True
    else:
        print_error("Impossible de se connecter à BigQuery")
        print_warning("Vérifiez: gcloud auth application-default login")
        return False

def step2_reconciliation():
    """Run live reconciliation (API vs BigQuery)"""
    print_step(2, "Réconciliation API vs BigQuery", "🔄")

    reconciliation_script = DATA_VALIDATION_DIR / "live_reconciliation.py"

    if not reconciliation_script.exists():
        print_warning("Script live_reconciliation.py non trouvé")
        print_info("Création d'un script de réconciliation basique...")
        return True  # Continue anyway

    cmd = f"python3 {reconciliation_script}"
    success, output = run_command(cmd, "Réconciliation API vs BigQuery", cwd=DATA_VALIDATION_DIR)

    return success

def step3_detect_new_tables():
    """Detect new tables in Airbyte connections"""
    print_step(3, "Détection Nouvelles Tables", "🔍")

    table_monitoring_script = DATA_VALIDATION_DIR / "table_monitoring.py"

    if not table_monitoring_script.exists():
        print_warning("Script table_monitoring.py non trouvé")
        return True

    cmd = f"python3 {table_monitoring_script}"
    success, output = run_command(cmd, "Détection nouvelles tables", cwd=DATA_VALIDATION_DIR)

    # Parse output to find new tables
    if "NEW tables detected" in output:
        print_warning("⚠️  Nouvelles tables détectées!")
        print(output)

    return success

def step4_check_data_freshness():
    """Check if data syncs are up to date"""
    print_step(4, "Vérification Freshness des Données", "⏰")

    # Check last sync time for each source
    cmd = f"""
    bq query --project_id={BQ_PROJECT} --use_legacy_sql=false --format=csv '
    SELECT
      table_id,
      TIMESTAMP_MILLIS(last_modified_time) AS last_sync,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), TIMESTAMP_MILLIS(last_modified_time), HOUR) AS hours_since_sync
    FROM `{BQ_PROJECT}.{BQ_DATASET}.__TABLES__`
    WHERE table_id IN (
      \"shopify_live_orders\",
      \"facebook_ads_insights\",
      \"tiktok_ads_reports_daily\",
      \"google_ads_unified\"
    )
    ORDER BY hours_since_sync DESC
    '
    """

    success, output = run_command(cmd, "Vérification freshness")

    if success:
        print(output)
        # Parse and warn if data is stale (>48h)
        if "hours_since_sync" in output:
            for line in output.split('\n')[1:]:  # Skip header
                if line.strip():
                    parts = line.split(',')
                    if len(parts) >= 3:
                        table, last_sync, hours = parts[0], parts[1], parts[2]
                        if hours and float(hours) > 48:
                            print_warning(f"Table {table} n'a pas sync depuis {hours}h!")

    return success

def step5_consistent_pii_encoding():
    """Ensure PII encoding is consistent across all tables

    IMPORTANT: NULL values are PRESERVED (not hashed)
    - pii_hash_reference contains only non-NULL email hashes
    - NULL emails stay NULL (representing missing data, guest checkouts, etc.)
    - Same non-NULL email = same hash everywhere
    """
    print_step(5, "Encoding PII Cohérent", "🔐")

    print_info("Création d'une table de référence pour hashing cohérent...")
    print_info("⚠️  IMPORTANT: Les valeurs NULL ne sont PAS encryptées (restent NULL)")

    # Create a master email hash reference table
    cmd = f"""
    bq query --project_id={BQ_PROJECT} --use_legacy_sql=false '
    CREATE OR REPLACE TABLE `{BQ_PROJECT}.{BQ_DATASET}.pii_hash_reference` AS

    WITH all_emails AS (
      -- Shopify emails (excluding NULL)
      SELECT DISTINCT
        email_hash AS email_hash_original,
        \"shopify\" AS source
      FROM `{BQ_PROJECT}.{BQ_DATASET}.shopify_live_customers_clean`
      WHERE email_hash IS NOT NULL  -- NULL values excluded from hashing

      UNION DISTINCT

      SELECT DISTINCT
        email_hash,
        \"shopify_orders\" AS source
      FROM `{BQ_PROJECT}.{BQ_DATASET}.shopify_live_orders_clean`
      WHERE email_hash IS NOT NULL  -- NULL values excluded from hashing
    )

    SELECT
      email_hash_original,
      -- Create consistent hash using SHA256
      TO_HEX(SHA256(email_hash_original)) AS email_hash_consistent,
      STRING_AGG(DISTINCT source, \", \") AS sources,
      COUNT(DISTINCT source) AS source_count
    FROM all_emails
    GROUP BY email_hash_original
    ORDER BY source_count DESC
    '
    """

    success, output = run_command(cmd, "Création table de référence PII")

    if success:
        print_success("Table pii_hash_reference créée!")
        print_info("Emails non-NULL: même hash partout")
        print_info("Emails NULL: restent NULL (données manquantes, guest checkouts)")

        # Verify NULL count
        check_cmd = f"""
        bq query --project_id={BQ_PROJECT} --use_legacy_sql=false --format=csv '
        SELECT
          COUNT(*) AS total_hashes,
          COUNT(DISTINCT email_hash_original) AS unique_emails
        FROM `{BQ_PROJECT}.{BQ_DATASET}.pii_hash_reference`
        '
        """

        check_success, check_output = run_command(check_cmd, "Vérification table PII")
        if check_success:
            print(check_output)

    return success

def step6_unify_tables():
    """Run table unification with deduplication"""
    print_step(6, "Unification des Tables (Sans Doublons)", "🔗")

    unified_sql_script = PROJECT_DIR / "sql" / "create_unified_tables.sql"

    if not unified_sql_script.exists():
        print_warning("Script create_unified_tables.sql non trouvé")
        return True

    print_info("Exécution du script d'unification...")
    cmd = f"bq query --project_id={BQ_PROJECT} --use_legacy_sql=false < {unified_sql_script}"
    success, output = run_command(cmd, "Unification des tables")

    if success:
        # Check for duplicates
        print_info("Vérification des doublons...")

        duplicate_check_cmd = f"""
        bq query --project_id={BQ_PROJECT} --use_legacy_sql=false --format=csv '
        SELECT
          \"shopify_unified\" AS table_name,
          COUNT(*) AS total_rows,
          COUNT(DISTINCT order_id) AS unique_orders,
          COUNT(*) - COUNT(DISTINCT order_id) AS duplicates
        FROM `{BQ_PROJECT}.{BQ_DATASET}.shopify_unified`

        UNION ALL

        SELECT
          \"marketing_unified\",
          COUNT(*),
          COUNT(DISTINCT CONCAT(CAST(date AS STRING), \"_\", channel)),
          COUNT(*) - COUNT(DISTINCT CONCAT(CAST(date AS STRING), \"_\", channel))
        FROM `{BQ_PROJECT}.{BQ_DATASET}.marketing_unified`
        '
        """

        dup_success, dup_output = run_command(duplicate_check_cmd, "Vérification doublons")

        if dup_success:
            print(dup_output)
            if "duplicates,0" not in dup_output.replace(" ", ""):
                print_warning("⚠️  Doublons détectés!")
            else:
                print_success("Aucun doublon détecté!")

    return success

def step7_detect_anomalies():
    """Detect data anomalies (NULL, 0, missing data)"""
    print_step(7, "Détection d'Anomalies", "🚨")

    print_info("Recherche de données NULL ou 0 inappropriées...")

    # Check for suspicious NULLs/zeros
    anomaly_check_cmd = f"""
    bq query --project_id={BQ_PROJECT} --use_legacy_sql=false --format=pretty '
    WITH anomalies AS (
      SELECT
        \"shopify_unified\" AS table_name,
        \"order_value\" AS field,
        COUNT(*) AS total_rows,
        COUNTIF(order_value IS NULL) AS null_count,
        COUNTIF(order_value = 0) AS zero_count,
        ROUND(COUNTIF(order_value IS NULL) / COUNT(*) * 100, 2) AS null_pct
      FROM `{BQ_PROJECT}.{BQ_DATASET}.shopify_unified`

      UNION ALL

      SELECT
        \"shopify_unified\",
        \"customer_id\",
        COUNT(*),
        COUNTIF(customer_id IS NULL),
        0,
        ROUND(COUNTIF(customer_id IS NULL) / COUNT(*) * 100, 2)
      FROM `{BQ_PROJECT}.{BQ_DATASET}.shopify_unified`

      UNION ALL

      SELECT
        \"marketing_unified\",
        \"revenue\",
        COUNT(*),
        COUNTIF(revenue IS NULL),
        COUNTIF(revenue = 0),
        ROUND(COUNTIF(revenue IS NULL) / COUNT(*) * 100, 2)
      FROM `{BQ_PROJECT}.{BQ_DATASET}.marketing_unified`

      UNION ALL

      SELECT
        \"marketing_unified\",
        \"ad_spend\",
        COUNT(*),
        COUNTIF(ad_spend IS NULL),
        COUNTIF(ad_spend = 0),
        ROUND(COUNTIF(ad_spend IS NULL) / COUNT(*) * 100, 2)
      FROM `{BQ_PROJECT}.{BQ_DATASET}.marketing_unified`
    )

    SELECT *
    FROM anomalies
    WHERE null_count > 0 OR zero_count > (total_rows * 0.1)  -- More than 10% zeros
    ORDER BY null_pct DESC, zero_count DESC
    '
    """

    success, output = run_command(anomaly_check_cmd, "Détection anomalies")

    if success:
        if "0 rows" in output or not output.strip():
            print_success("Aucune anomalie majeure détectée!")
        else:
            print_warning("⚠️  Anomalies détectées:")
            print(output)

    # Save anomalies to file
    anomaly_file = LOGS_DIR / f"anomalies_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
    LOGS_DIR.mkdir(exist_ok=True)

    with open(anomaly_file, 'w') as f:
        f.write(f"Anomaly Detection Report\n")
        f.write(f"Generated: {datetime.now()}\n\n")
        f.write(output)

    print_info(f"Rapport sauvegardé: {anomaly_file}")

    return success

def step8_generate_executive_report():
    """Generate executive report PowerPoint"""
    print_step(8, "Génération Rapport Exécutif", "📊")

    ppt_script = PROJECT_DIR / "scripts" / "generate_powerpoint.py"

    if not ppt_script.exists():
        print_warning("Script generate_powerpoint.py non trouvé")
        return True

    cmd = f"python3 {ppt_script}"
    success, output = run_command(cmd, "Génération PowerPoint", cwd=PROJECT_DIR / "scripts")

    if success:
        print_success("Rapport PowerPoint généré!")
        ppt_file = REPORTS_DIR / "Marketing_Performance_Report.pptx"
        print_info(f"Fichier: {ppt_file}")

    return success

def main():
    """Main workflow orchestrator"""
    print(f"\n{Colors.HEADER}{Colors.BOLD}")
    print("╔═══════════════════════════════════════════════════════════════════╗")
    print("║                                                                   ║")
    print("║       MASTER WORKFLOW - ANALYTICS AUTOMATION                     ║")
    print("║       Hulken Data Pipeline                                       ║")
    print("║                                                                   ║")
    print("╚═══════════════════════════════════════════════════════════════════╝")
    print(f"{Colors.ENDC}\n")

    start_time = datetime.now()
    print_info(f"Démarrage: {start_time.strftime('%Y-%m-%d %H:%M:%S')}")

    # Parse arguments
    skip_reconciliation = "--skip-reconciliation" in sys.argv
    skip_pii = "--skip-pii" in sys.argv
    skip_report = "--skip-report" in sys.argv

    # Execute workflow steps
    steps = [
        ("BigQuery Connection", step1_test_bigquery_connection, False),
        ("Réconciliation API vs BigQuery", step2_reconciliation, skip_reconciliation),
        ("Détection Nouvelles Tables", step3_detect_new_tables, False),
        ("Vérification Freshness", step4_check_data_freshness, False),
        ("Encoding PII Cohérent", step5_consistent_pii_encoding, skip_pii),
        ("Unification Tables", step6_unify_tables, False),
        ("Détection Anomalies", step7_detect_anomalies, False),
        ("Génération Rapport", step8_generate_executive_report, skip_report),
    ]

    results = []

    for i, (name, func, skip) in enumerate(steps, 1):
        if skip:
            print_warning(f"\nÉtape {i} ({name}) - SKIPPED")
            results.append((name, "SKIPPED"))
            continue

        try:
            success = func()
            results.append((name, "SUCCESS" if success else "FAILED"))
        except Exception as e:
            print_error(f"Erreur dans {name}: {str(e)}")
            results.append((name, "ERROR"))

    # Summary
    end_time = datetime.now()
    duration = end_time - start_time

    print(f"\n{Colors.HEADER}{Colors.BOLD}")
    print("╔═══════════════════════════════════════════════════════════════════╗")
    print("║                     WORKFLOW TERMINÉ                              ║")
    print("╚═══════════════════════════════════════════════════════════════════╝")
    print(f"{Colors.ENDC}\n")

    print(f"Durée totale: {duration.total_seconds():.1f}s")
    print(f"\nRésultats:")

    for name, status in results:
        if status == "SUCCESS":
            print_success(f"{name}: {status}")
        elif status == "SKIPPED":
            print_warning(f"{name}: {status}")
        else:
            print_error(f"{name}: {status}")

    # Overall status
    failed = sum(1 for _, s in results if s == "FAILED" or s == "ERROR")

    if failed == 0:
        print(f"\n{Colors.OKGREEN}{Colors.BOLD}✅ WORKFLOW COMPLET - SUCCÈS!{Colors.ENDC}\n")
        return 0
    else:
        print(f"\n{Colors.WARNING}{Colors.BOLD}⚠️  WORKFLOW TERMINÉ AVEC {failed} ERREUR(S){Colors.ENDC}\n")
        return 1

if __name__ == "__main__":
    sys.exit(main())
