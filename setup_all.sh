#!/bin/bash
# Script complet pour tout setup

echo "🚀 SETUP COMPLET - Dev_Ops"
echo ""

# 1. Aller dans Dev_Ops
cd /Users/raphael_sebbah/Documents/Projects/Dev_Ops || exit 1
echo "✅ Dans Dev_Ops"

# 2. Installer dépendances
echo ""
echo "📦 Installation dépendances..."
pip install -q streamlit google-cloud-bigquery pandas python-dotenv requests pyarrow db-dtypes
echo "✅ Dépendances installées"

# 3. Créer baseline (si pas déjà fait)
echo ""
echo "📊 Création baseline..."
python data_validation/table_monitoring.py --create-baseline 2>/dev/null || echo "Baseline déjà créée"

# 4. Tester super script
echo ""
echo "🔍 Test super script..."
python data_validation/run_all_checks.py --only-airbyte

# 5. Rendre scripts exécutables
echo ""
echo "🔧 Configuration scripts..."
chmod +x setup_github.sh
chmod +x setup_new_project.sh
echo "✅ Scripts configurés"

echo ""
echo "🎉 SETUP TERMINÉ!"
echo ""
echo "Prochaines étapes:"
echo "1. Setup GitHub: ./setup_github.sh"
echo "2. Créer repo sur GitHub: https://github.com/new"
echo "3. Push: git push -u origin main"
echo "4. Tester dashboard: streamlit run data_explorer.py"
