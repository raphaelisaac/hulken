#!/bin/bash
# ============================================================
# VSCODE_CONFIG SETUP FOR NEW PROJECT
# ============================================================
# This script configures vscode_config for a new project.
# It's designed to make vscode_config portable and reusable.
#
# Usage:
#   ./setup_new_project.sh
#
# What it does:
#   1. Prompts for project configuration
#   2. Creates .env file from template
#   3. Sets up git (if needed)
#   4. Installs Python dependencies
#   5. Tests BigQuery connection
#
# Created: 2026-02-13
# ============================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}  VSCODE_CONFIG SETUP FOR NEW PROJECT${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""

# ============================================================
# 1. Collect project information
# ============================================================
echo -e "${YELLOW}Step 1: Project Information${NC}"
echo ""

read -p "Project Name (e.g., Hulken): " PROJECT_NAME
if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME="MyProject"
fi

read -p "BigQuery Project ID: " BQ_PROJECT
if [ -z "$BQ_PROJECT" ]; then
    echo -e "${RED}Error: BigQuery Project ID is required${NC}"
    exit 1
fi

read -p "BigQuery Dataset (default: ads_data): " BQ_DATASET
if [ -z "$BQ_DATASET" ]; then
    BQ_DATASET="ads_data"
fi

read -p "Path to BigQuery credentials JSON: " CREDENTIALS_PATH
if [ ! -f "$CREDENTIALS_PATH" ]; then
    echo -e "${RED}Error: Credentials file not found: $CREDENTIALS_PATH${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ Project information collected${NC}"
echo ""

# ============================================================
# 2. Create .env file
# ============================================================
echo -e "${YELLOW}Step 2: Creating .env configuration${NC}"
echo ""

ENV_FILE="data_validation/.env"

if [ -f "$ENV_FILE" ]; then
    echo -e "${YELLOW}Warning: $ENV_FILE already exists${NC}"
    read -p "Overwrite? (y/n): " OVERWRITE
    if [ "$OVERWRITE" != "y" ]; then
        echo "Skipping .env creation"
    else
        cp data_validation/.env.template "$ENV_FILE"
    fi
else
    cp data_validation/.env.template "$ENV_FILE"
fi

# Copy credentials file to local directory
CREDENTIALS_FILENAME=$(basename "$CREDENTIALS_PATH")
cp "$CREDENTIALS_PATH" "data_validation/$CREDENTIALS_FILENAME"

# Update .env with user values
sed -i.bak "s|BIGQUERY_PROJECT=.*|BIGQUERY_PROJECT=$BQ_PROJECT|" "$ENV_FILE"
sed -i.bak "s|BIGQUERY_DATASET=.*|BIGQUERY_DATASET=$BQ_DATASET|" "$ENV_FILE"
sed -i.bak "s|GOOGLE_APPLICATION_CREDENTIALS=.*|GOOGLE_APPLICATION_CREDENTIALS=./$CREDENTIALS_FILENAME|" "$ENV_FILE"
sed -i.bak "s|PROJECT_NAME=.*|PROJECT_NAME=$PROJECT_NAME|" "$ENV_FILE"
rm "$ENV_FILE.bak"

echo -e "${GREEN}✓ .env file created: $ENV_FILE${NC}"
echo -e "${YELLOW}⚠️  Don't forget to add API credentials (Shopify, Facebook, TikTok)${NC}"
echo ""

# ============================================================
# 3. Install Python dependencies
# ============================================================
echo -e "${YELLOW}Step 3: Installing Python dependencies${NC}"
echo ""

if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python 3 is not installed${NC}"
    exit 1
fi

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
source venv/bin/activate

# Install dependencies
if [ -f "requirements.txt" ]; then
    echo "Installing requirements..."
    pip install -q --upgrade pip
    pip install -q -r requirements.txt
    echo -e "${GREEN}✓ Dependencies installed${NC}"
else
    echo -e "${YELLOW}Warning: requirements.txt not found${NC}"
    echo "Installing core dependencies..."
    pip install -q google-cloud-bigquery python-dotenv requests pandas streamlit
    echo -e "${GREEN}✓ Core dependencies installed${NC}"
fi

echo ""

# ============================================================
# 4. Test BigQuery connection
# ============================================================
echo -e "${YELLOW}Step 4: Testing BigQuery connection${NC}"
echo ""

python3 << EOF
import os
from dotenv import load_dotenv
from google.cloud import bigquery

load_dotenv('$ENV_FILE')

project = os.getenv('BIGQUERY_PROJECT')
dataset = os.getenv('BIGQUERY_DATASET')

try:
    client = bigquery.Client(project=project)
    # Test query
    query = f"SELECT COUNT(*) FROM \`{project}.{dataset}.__TABLES__\`"
    result = list(client.query(query).result())
    table_count = result[0][0]
    print(f"✓ Connected to BigQuery project: {project}")
    print(f"✓ Dataset '{dataset}' has {table_count} tables")
    exit(0)
except Exception as e:
    print(f"✗ Connection failed: {e}")
    exit(1)
EOF

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ BigQuery connection successful${NC}"
else
    echo -e "${RED}✗ BigQuery connection failed${NC}"
    echo -e "${YELLOW}Check your credentials and project/dataset names${NC}"
fi

echo ""

# ============================================================
# 5. Initialize git (if needed)
# ============================================================
echo -e "${YELLOW}Step 5: Git initialization${NC}"
echo ""

if [ -d ".git" ]; then
    echo -e "${GREEN}✓ Git repository already initialized${NC}"
else
    read -p "Initialize new git repository? (y/n): " INIT_GIT
    if [ "$INIT_GIT" = "y" ]; then
        git init
        git add .
        git commit -m "Initial commit: vscode_config setup for $PROJECT_NAME"
        echo -e "${GREEN}✓ Git repository initialized${NC}"
    fi
fi

echo ""

# ============================================================
# 6. Create baseline for table monitoring
# ============================================================
echo -e "${YELLOW}Step 6: Creating table monitoring baseline${NC}"
echo ""

read -p "Create baseline for table monitoring? (y/n): " CREATE_BASELINE
if [ "$CREATE_BASELINE" = "y" ]; then
    python3 data_validation/table_monitoring.py --create-baseline
    echo -e "${GREEN}✓ Baseline created${NC}"
else
    echo "Skipped. You can create it later with:"
    echo "  python data_validation/table_monitoring.py --create-baseline"
fi

echo ""

# ============================================================
# FINAL SUMMARY
# ============================================================
echo -e "${BLUE}============================================================${NC}"
echo -e "${GREEN}  SETUP COMPLETE!${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo -e "Project: ${GREEN}$PROJECT_NAME${NC}"
echo -e "BigQuery Project: ${GREEN}$BQ_PROJECT${NC}"
echo -e "Dataset: ${GREEN}$BQ_DATASET${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo "1. Add API credentials to: $ENV_FILE"
echo "   - SHOPIFY_ACCESS_TOKEN"
echo "   - FACEBOOK_ACCESS_TOKEN"
echo "   - TIKTOK_ACCESS_TOKEN"
echo ""
echo "2. Test the data explorer:"
echo "   ${BLUE}streamlit run data_explorer.py${NC}"
echo ""
echo "3. Run live reconciliation:"
echo "   ${BLUE}python data_validation/live_reconciliation.py${NC}"
echo ""
echo "4. Monitor tables for issues:"
echo "   ${BLUE}python data_validation/table_monitoring.py --check${NC}"
echo ""
echo -e "${GREEN}Happy analyzing!${NC}"
echo ""
