#!/usr/bin/env python3
"""
SUPER VALIDATION - Vérification complète de l'infrastructure
=============================================================
Ce script combine TOUTES les vérifications en un seul endroit:
  1. Validation API vs BigQuery (live_reconciliation.py)
  2. Détection tables vides/nouvelles (table_monitoring.py)  
  3. Surveillance syncs Airbyte
  4. Vérification qualité des données

Usage:
    # Routine quotidienne (tout vérifier)
    python run_all_checks.py

    # Seulement API vs BigQuery
    python run_all_checks.py --only-reconciliation

    # Seulement tables
    python run_all_checks.py --only-tables

    # Mode détaillé
    python run_all_checks.py --verbose

    # Sauvegarder le rapport
    python run_all_checks.py --output report.txt
"""

import os
import sys
import subprocess
import argparse
from datetime import datetime
from pathlib import Path

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


def print_header(title):
    """Print a section header."""
    width = 60
    print(f"\n{C.CYAN}{'=' * width}{C.END}")
    print(f"{C.CYAN}{C.BOLD}  {title}{C.END}")
    print(f"{C.CYAN}{'=' * width}{C.END}\n")


def run_command(cmd, description, verbose=False):
    """Run a command and capture output."""
    print(f"{C.BLUE}▶ {description}...{C.END}")
    
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=300  # 5 minutes max
        )
        
        if result.returncode == 0:
            print(f"{C.GREEN}✓ {description} - OK{C.END}")
            if verbose:
                print(result.stdout)
            return True, result.stdout
        else:
            print(f"{C.RED}✗ {description} - ÉCHEC{C.END}")
            if result.stderr:
                print(f"{C.RED}{result.stderr}{C.END}")
            return False, result.stderr
            
    except subprocess.TimeoutExpired:
        print(f"{C.RED}✗ {description} - TIMEOUT (> 5 min){C.END}")
        return False, "Timeout"
    except Exception as e:
        print(f"{C.RED}✗ {description} - ERREUR: {e}{C.END}")
        return False, str(e)


def check_airbyte_connections(verbose=False):
    """Vérifie l'état des connections Airbyte via BigQuery."""
    print(f"{C.BLUE}▶ Vérification syncs Airbyte...{C.END}")
    
    try:
        from google.cloud import bigquery
        client = bigquery.Client(project='hulken')
        
        # Vérifier la fraîcheur des syncs
        sources = {
            'Shopify': 'shopify_live_orders',
            'Facebook': 'facebook_ads_insights',
            'TikTok': 'tiktokads_reports_daily',
        }
        
        all_good = True
        for source_name, table_name in sources.items():
            query = f"""
            SELECT MAX(_airbyte_extracted_at) AS last_sync
            FROM `hulken.ads_data.{table_name}`
            """
            
            result = list(client.query(query).result())
            if result and result[0].last_sync:
                last_sync = result[0].last_sync
                hours_ago = (datetime.now(last_sync.tzinfo) - last_sync).total_seconds() / 3600
                
                if hours_ago < 2:
                    status = f"{C.GREEN}OK ({hours_ago:.0f}h ago){C.END}"
                elif hours_ago < 24:
                    status = f"{C.YELLOW}WARNING ({hours_ago:.0f}h ago){C.END}"
                    all_good = False
                else:
                    status = f"{C.RED}STALE ({hours_ago:.0f}h ago / {hours_ago/24:.1f} days){C.END}"
                    all_good = False
                
                print(f"  {source_name:15} - {status}")
            else:
                print(f"  {source_name:15} - {C.RED}NO DATA{C.END}")
                all_good = False
        
        if all_good:
            print(f"{C.GREEN}✓ Tous les syncs Airbyte sont à jour{C.END}")
        else:
            print(f"{C.YELLOW}⚠ Certains syncs sont en retard{C.END}")
        
        return all_good
        
    except Exception as e:
        print(f"{C.RED}✗ Erreur vérification Airbyte: {e}{C.END}")
        return False


def main():
    parser = argparse.ArgumentParser(description='Super validation - Toutes les vérifications')
    parser.add_argument('--only-reconciliation', action='store_true',
                        help='Seulement API vs BigQuery')
    parser.add_argument('--only-tables', action='store_true',
                        help='Seulement détection tables')
    parser.add_argument('--only-airbyte', action='store_true',
                        help='Seulement syncs Airbyte')
    parser.add_argument('--verbose', '-v', action='store_true',
                        help='Afficher tous les détails')
    parser.add_argument('--output', type=str,
                        help='Sauvegarder le rapport dans un fichier')
    args = parser.parse_args()
    
    # Redirect output to file if requested
    if args.output:
        sys.stdout = open(args.output, 'w')
    
    # Header
    print_header("SUPER VALIDATION - Vérification complète")
    print(f"{C.DIM}Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}{C.END}\n")
    
    results = {}
    
    # 1. Validation API vs BigQuery
    if not args.only_tables and not args.only_airbyte:
        print_header("1. VALIDATION API vs BigQuery")
        success, output = run_command(
            'python data_validation/live_reconciliation.py --no-animation',
            'Vérification cohérence API ↔ BigQuery',
            args.verbose
        )
        results['API vs BigQuery'] = success
    
    # 2. Détection tables vides/nouvelles
    if not args.only_reconciliation and not args.only_airbyte:
        print_header("2. DÉTECTION TABLES")
        success, output = run_command(
            'python data_validation/table_monitoring.py --check',
            'Vérification tables vides/nouvelles/stale',
            args.verbose
        )
        results['Monitoring tables'] = success
    
    # 3. Vérification syncs Airbyte
    if not args.only_reconciliation and not args.only_tables:
        print_header("3. SURVEILLANCE AIRBYTE")
        success = check_airbyte_connections(args.verbose)
        results['Syncs Airbyte'] = success
    
    # Summary
    print_header("RÉSUMÉ FINAL")
    
    all_passed = True
    for check_name, passed in results.items():
        if passed:
            print(f"  {C.GREEN}✓{C.END} {check_name}")
        else:
            print(f"  {C.RED}✗{C.END} {check_name}")
            all_passed = False
    
    print()
    if all_passed:
        print(f"{C.GREEN}{C.BOLD}🎉 TOUT EST OK!{C.END}")
        print(f"{C.GREEN}Toutes les vérifications ont réussi.{C.END}\n")
        return 0
    else:
        print(f"{C.YELLOW}{C.BOLD}⚠️  ATTENTION{C.END}")
        print(f"{C.YELLOW}Certaines vérifications ont échoué. Voir détails ci-dessus.{C.END}\n")
        return 1


if __name__ == '__main__':
    sys.exit(main())
