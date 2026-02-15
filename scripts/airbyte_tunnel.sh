#!/bin/bash
# ============================================================
# AIRBYTE IAP TUNNEL - Fix for "Bad file descriptor" errors
# ============================================================
# Crée un tunnel stable vers Airbyte avec force IPv4

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Démarrage du tunnel IAP vers Airbyte...${NC}\n"

# Configuration
PROJECT="hulken"
ZONE="us-central1-a"
INSTANCE="instance-20260129-133637"
REMOTE_PORT=8000
LOCAL_PORT=8006

# Vérifier si la VM est démarrée
echo -e "${YELLOW}📡 Vérification de l'état de la VM...${NC}"
VM_STATUS=$(gcloud compute instances describe $INSTANCE \
  --project=$PROJECT \
  --zone=$ZONE \
  --format='get(status)' 2>/dev/null)

if [ "$VM_STATUS" != "RUNNING" ]; then
  echo -e "${YELLOW}⏳ VM arrêtée. Démarrage en cours...${NC}"
  gcloud compute instances start $INSTANCE \
    --project=$PROJECT \
    --zone=$ZONE

  echo -e "${YELLOW}⏳ Attente de 30 secondes pour le boot...${NC}"
  sleep 30
fi

# Tuer les anciens tunnels sur le port
echo -e "${YELLOW}🧹 Nettoyage des anciens tunnels...${NC}"
lsof -ti:$LOCAL_PORT | xargs kill -9 2>/dev/null || true
sleep 2

# Installer NumPy si manquant (pour améliorer les performances)
if ! python3 -c "import numpy" 2>/dev/null; then
  echo -e "${YELLOW}📦 NumPy non installé. Installation recommandée pour meilleures performances.${NC}"
  echo -e "${YELLOW}   Vous pouvez l'installer avec: pip3 install numpy${NC}\n"
fi

# Créer le tunnel avec force IPv4
echo -e "${GREEN}🔌 Création du tunnel IAP...${NC}"
echo -e "${GREEN}   Local: http://localhost:$LOCAL_PORT${NC}"
echo -e "${GREEN}   Remote: $INSTANCE:$REMOTE_PORT${NC}\n"

# Force IPv4 en utilisant --local-host-port avec 127.0.0.1
gcloud compute start-iap-tunnel $INSTANCE $REMOTE_PORT \
  --local-host-port=127.0.0.1:$LOCAL_PORT \
  --zone=$ZONE \
  --project=$PROJECT

# Note: Le tunnel reste ouvert jusqu'à ce que vous fassiez Ctrl+C
