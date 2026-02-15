#!/bin/bash
# ============================================================
# AIRBYTE ACCESS - Alternative Method (Direct SSH)
# ============================================================
# Alternative au tunnel IAP qui a des problèmes de "Bad file descriptor"

set -e

# Configuration
PROJECT="hulken"
ZONE="us-central1-a"
INSTANCE="instance-20260129-133637"
REMOTE_PORT=8000
LOCAL_PORT=8006

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Accès Airbyte - Méthode Alternative${NC}\n"

# Option 1: SSH Direct avec Port Forwarding
echo -e "${YELLOW}Option 1: SSH Direct (Recommandé si firewall permet)${NC}"
echo "Commande:"
echo "  gcloud compute ssh $INSTANCE --project=$PROJECT --zone=$ZONE -- -L $LOCAL_PORT:localhost:$REMOTE_PORT -N"
echo ""

# Option 2: Cloud Console Web
echo -e "${YELLOW}Option 2: Via Google Cloud Console (Toujours fonctionne!)${NC}"
echo "1. Aller sur: https://console.cloud.google.com/compute/instances?project=$PROJECT"
echo "2. Trouver la VM: $INSTANCE"
echo "3. Cliquer sur 'SSH' (dans le navigateur)"
echo "4. Dans la console SSH, exécuter:"
echo "   curl http://localhost:$REMOTE_PORT"
echo "5. Si Airbyte répond, c'est actif!"
echo ""

# Option 3: API Airbyte (Pour automatisation)
echo -e "${YELLOW}Option 3: API Airbyte via curl (Pour vérifier status)${NC}"
echo "Utiliser gcloud compute ssh avec commande à distance:"
echo ""
cat << 'EOF'
gcloud compute ssh instance-20260129-133637 \
  --project=hulken \
  --zone=us-central1-a \
  --command="curl -s http://localhost:8000/api/v1/health"
EOF
echo ""

# Essayer Option 3 automatiquement
echo -e "${GREEN}🔍 Test de connexion à Airbyte (Option 3)...${NC}"

HEALTH_CHECK=$(gcloud compute ssh $INSTANCE \
  --project=$PROJECT \
  --zone=$ZONE \
  --tunnel-through-iap \
  --command="curl -s http://localhost:$REMOTE_PORT/api/v1/health" 2>/dev/null || echo "FAILED")

if [ "$HEALTH_CHECK" != "FAILED" ]; then
  echo -e "${GREEN}✅ Airbyte est actif!${NC}"
  echo "Réponse: $HEALTH_CHECK"
  echo ""

  # Get Airbyte version
  echo -e "${GREEN}📊 Version Airbyte:${NC}"
  gcloud compute ssh $INSTANCE \
    --project=$PROJECT \
    --zone=$ZONE \
    --tunnel-through-iap \
    --command="curl -s http://localhost:$REMOTE_PORT/api/v1/health | python3 -m json.tool" 2>/dev/null || true
else
  echo -e "${RED}❌ Impossible de contacter Airbyte${NC}"
  echo ""
  echo "Solutions:"
  echo "1. Vérifier que la VM est démarrée:"
  echo "   gcloud compute instances describe $INSTANCE --project=$PROJECT --zone=$ZONE --format='get(status)'"
  echo ""
  echo "2. Démarrer la VM si arrêtée:"
  echo "   gcloud compute instances start $INSTANCE --project=$PROJECT --zone=$ZONE"
  echo ""
  echo "3. Se connecter via SSH web console (Option 2 ci-dessus)"
fi

echo ""
echo -e "${YELLOW}💡 Recommandation:${NC}"
echo "Pour accès UI Airbyte, utiliser l'Option 2 (Cloud Console Web SSH)"
echo "C'est plus stable que le tunnel IAP pour cette version de gcloud SDK."
