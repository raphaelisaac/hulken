#!/bin/bash
# ============================================================
# Better Signal - VSCode + BigQuery Setup for Analysts (macOS)
# One-click installation script
# ============================================================
set -e

echo ""
echo "============================================================"
echo "  Better Signal - Analyst Environment Setup (macOS)"
echo "============================================================"
echo ""

# ============================================================
# [1/6] Check prerequisites
# ============================================================
echo "[1/6] Checking prerequisites..."

# Check Python
if command -v python3 &>/dev/null; then
    echo "  Python: OK ($(python3 --version 2>&1))"
else
    echo "  [ERROR] Python3 not found."
    echo "  Install with: brew install python3"
    echo "  Or download from https://python.org/downloads"
    exit 1
fi

# Check VSCode
if command -v code &>/dev/null; then
    echo "  VSCode: OK"
else
    echo "  [WARNING] VSCode CLI not found."
    echo "  Install from https://code.visualstudio.com"
    echo "  Then: Cmd+Shift+P > 'Shell Command: Install code command in PATH'"
    echo "  Continuing with other installs..."
fi

# Check Homebrew (useful for gcloud)
if command -v brew &>/dev/null; then
    echo "  Homebrew: OK"
else
    echo "  [INFO] Homebrew not found. Recommended: https://brew.sh"
fi

# ============================================================
# [2/6] Install Google Cloud SDK
# ============================================================
echo ""
echo "[2/6] Checking Google Cloud SDK..."

if command -v gcloud &>/dev/null; then
    echo "  Google Cloud SDK: OK ($(gcloud --version 2>&1 | head -1))"
else
    echo "  Google Cloud SDK not found. Installing..."
    if command -v brew &>/dev/null; then
        echo "  Installing via Homebrew..."
        brew install --cask google-cloud-sdk
    else
        echo "  Install manually from: https://cloud.google.com/sdk/docs/install#mac"
        echo "  Or install Homebrew first: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        echo "  Then: brew install --cask google-cloud-sdk"
        open "https://cloud.google.com/sdk/docs/install#mac"
        echo "  After install, run this script again."
        exit 1
    fi
fi

# ============================================================
# [3/6] Authenticate with Google Cloud
# ============================================================
echo ""
echo "[3/6] Setting up Google Cloud authentication..."

gcloud config set project hulken 2>/dev/null
echo "  Project set to: hulken"

# Check if already authenticated
if gcloud auth application-default print-access-token &>/dev/null 2>&1; then
    echo "  Already authenticated: OK"
else
    echo "  Opening browser for authentication..."
    echo "  >>> Connect with the Google account that has access to project 'hulken' <<<"
    gcloud auth application-default login
fi

# Also do regular auth for gcloud CLI (SSH, etc.)
if gcloud auth print-access-token &>/dev/null 2>&1; then
    echo "  CLI auth: OK"
else
    echo "  Setting up CLI authentication..."
    gcloud auth login
fi

# ============================================================
# [4/6] Install VSCode Extensions
# ============================================================
echo ""
echo "[4/6] Installing VSCode extensions..."

if command -v code &>/dev/null; then
    code --install-extension GoogleCloudTools.cloudcode --force 2>/dev/null && echo "  Google Cloud Code: OK" || echo "  [SKIP] Cloud Code"
    code --install-extension mtxr.sqltools --force 2>/dev/null && echo "  SQLTools: OK" || echo "  [SKIP] SQLTools"
    code --install-extension Evidence.sqltools-bigquery-driver --force 2>/dev/null && echo "  SQLTools BigQuery: OK" || echo "  [SKIP] BigQuery Driver"
    code --install-extension ms-python.python --force 2>/dev/null && echo "  Python: OK" || echo "  [SKIP] Python"
else
    echo "  [SKIP] VSCode not available"
fi

# ============================================================
# [5/6] Install Python Dependencies
# ============================================================
echo ""
echo "[5/6] Installing Python packages..."

pip3 install google-cloud-bigquery pandas pyarrow python-dotenv db-dtypes tabulate --quiet 2>/dev/null
if [ $? -eq 0 ]; then
    echo "  Python packages: OK"
else
    echo "  [WARNING] Some packages may have failed. Try:"
    echo "  pip3 install google-cloud-bigquery pandas pyarrow python-dotenv db-dtypes tabulate"
fi

# ============================================================
# [6/6] Verify Setup
# ============================================================
echo ""
echo "[6/6] Verifying setup..."

python3 -c "from google.cloud import bigquery; c = bigquery.Client(project='hulken'); print('  BigQuery connection: OK - project hulken')" 2>&1
if [ $? -ne 0 ]; then
    echo "  [WARNING] BigQuery connection test failed."
    echo "  Run: gcloud auth application-default login"
fi

# Test SSH access to VM
echo ""
echo "  Testing VM access..."
gcloud compute instances describe instance-20260129-133637 --zone=us-central1-a --format="value(status)" 2>/dev/null && echo "  VM access: OK" || echo "  [WARNING] VM access failed - check IAM permissions"

echo ""
echo "============================================================"
echo "  SETUP COMPLETE!"
echo "============================================================"
echo ""
echo "  Next steps:"
echo "  1. Open VSCode in the Better_signal folder"
echo "  2. Read docs/QUICK_START_ANALYST.md for query examples"
echo "  3. Try: python3 -c \"from google.cloud import bigquery; print('Ready!')\""
echo ""
echo "  Quick test:"
echo "  python3 data_validation/reconciliation_check.py --checks freshness"
echo ""
