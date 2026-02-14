#!/bin/bash
# ============================================================
# SETUP GITHUB - Nouveau repo "hulken"
# ============================================================
# Ce script configure Dev_Ops pour le nouveau repo GitHub
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}  SETUP GITHUB - hulken${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""

# ============================================================
# 1. Vérifier qu'on est dans le bon dossier
# ============================================================
if [ ! -f "README.md" ]; then
    echo -e "${RED}Erreur: Ce script doit être exécuté depuis Dev_Ops/${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Dossier correct: $(pwd)${NC}"
echo ""

# ============================================================
# 2. Demander le nom d'utilisateur GitHub
# ============================================================
echo -e "${YELLOW}Étape 1: Configuration GitHub${NC}"
echo ""

read -p "Votre nom d'utilisateur GitHub: " GITHUB_USERNAME

if [ -z "$GITHUB_USERNAME" ]; then
    echo -e "${RED}Erreur: Nom d'utilisateur requis${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ GitHub username: $GITHUB_USERNAME${NC}"
echo ""

# ============================================================
# 3. Vérifier qu'il n'y a pas de credentials
# ============================================================
echo -e "${YELLOW}Étape 2: Vérification sécurité${NC}"
echo ""

echo "Vérification des credentials dans Git..."
TRACKED_CREDS=$(git ls-files | grep -E "\.(env|json)$" | grep -v ".template" | grep -v "package.json" || true)

if [ ! -z "$TRACKED_CREDS" ]; then
    echo -e "${RED}⚠️  ATTENTION: Des credentials sont trackés dans Git:${NC}"
    echo "$TRACKED_CREDS"
    echo ""
    read -p "Voulez-vous les retirer du tracking? (y/n): " REMOVE_CREDS
    
    if [ "$REMOVE_CREDS" = "y" ]; then
        echo "$TRACKED_CREDS" | while read file; do
            git rm --cached "$file" 2>/dev/null || true
            echo "  ✓ Retiré: $file"
        done
        git commit -m "Remove credentials from tracking" 2>/dev/null || true
    fi
fi

echo -e "${GREEN}✓ Sécurité vérifiée${NC}"
echo ""

# ============================================================
# 4. Supprimer l'ancien remote
# ============================================================
echo -e "${YELLOW}Étape 3: Suppression ancien remote${NC}"
echo ""

CURRENT_REMOTE=$(git remote get-url origin 2>/dev/null || echo "none")

if [ "$CURRENT_REMOTE" != "none" ]; then
    echo "Ancien remote: $CURRENT_REMOTE"
    git remote remove origin
    echo -e "${GREEN}✓ Ancien remote supprimé${NC}"
else
    echo "Pas de remote existant"
fi

echo ""

# ============================================================
# 5. Ajouter le nouveau remote
# ============================================================
echo -e "${YELLOW}Étape 4: Ajout nouveau remote${NC}"
echo ""

NEW_REPO_URL="https://github.com/$GITHUB_USERNAME/hulken.git"

git remote add origin $NEW_REPO_URL

echo -e "${GREEN}✓ Nouveau remote ajouté: $NEW_REPO_URL${NC}"
echo ""

# ============================================================
# 6. Vérifier et commit les changements
# ============================================================
echo -e "${YELLOW}Étape 5: Commit des changements${NC}"
echo ""

if [ -n "$(git status --porcelain)" ]; then
    git add .
    git commit -m "Setup pour GitHub hulken

- Nettoyage documentation (14 .md → README.md)
- Ajout table_monitoring.py (détection anomalies)
- Ajout create_unified_tables.sql (fusion sources)
- Amélioration .gitignore (sécurité)
- Configuration GitHub" || echo "Rien à commiter"
    
    echo -e "${GREEN}✓ Changements commités${NC}"
else
    echo "Aucun changement à commiter"
fi

echo ""

# ============================================================
# 7. Instructions pour push
# ============================================================
echo -e "${BLUE}============================================================${NC}"
echo -e "${GREEN}  PRESQUE TERMINÉ!${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo -e "${YELLOW}Prochaines étapes:${NC}"
echo ""
echo "1. Créer le repo sur GitHub:"
echo "   ${BLUE}https://github.com/new${NC}"
echo ""
echo "   Repository name: ${GREEN}hulken${NC}"
echo "   Visibility: Public (ou Private)"
echo "   ${RED}❌ Ne PAS initialiser avec README/gitignore${NC}"
echo ""
echo "2. Une fois créé, revenir ici et exécuter:"
echo "   ${BLUE}git branch -M main${NC}"
echo "   ${BLUE}git push -u origin main${NC}"
echo ""
echo "3. Si demande login:"
echo "   - Username: $GITHUB_USERNAME"
echo "   - Password: Utiliser un ${GREEN}Personal Access Token${NC}"
echo "     (Pas votre mot de passe GitHub!)"
echo ""
echo "4. Créer un token:"
echo "   ${BLUE}https://github.com/settings/tokens${NC}"
echo "   → Generate new token (classic)"
echo "   → Cocher: repo (full control)"
echo "   → Copier le token et l'utiliser comme password"
echo ""
echo -e "${GREEN}Remote configuré: $NEW_REPO_URL${NC}"
echo ""

