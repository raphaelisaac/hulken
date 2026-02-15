# Comment Créer Tes Slides PowerPoint 📊

**3 options simples pour avoir ton rapport avec les 26 sections**

---

## 🥇 OPTION 1: Looker Studio → PowerPoint (RECOMMANDÉ)

**Temps:** 15 minutes
**Avantage:** Données réelles, auto-update, exportable

### Étapes:

1. **Créer le dashboard Looker** (10 min)
   - Suis le guide: [docs/LOOKER_10MIN_QUICKSTART.md](docs/LOOKER_10MIN_QUICKSTART.md)
   - Va sur https://lookerstudio.google.com
   - Connecte BigQuery (`hulken.ads_data.marketing_unified`)
   - Crée 4-5 pages avec tes KPIs

2. **Exporter en PDF** (2 min)
   - Dans Looker, cliquer **"Download"** → **"PDF - All pages"**
   - Attendre le téléchargement

3. **Convertir en PowerPoint** (3 min)
   - Ouvrir PowerPoint
   - **Insert** → **Pictures** → Choisir le PDF
   - PowerPoint convertit automatiquement chaque page PDF en slide

**✅ Résultat:** PowerPoint avec vraies données de BigQuery, graphiques professionnels

---

## 🥈 OPTION 2: BigQuery → PowerPoint (Manuel)

**Temps:** 30-45 minutes
**Avantage:** Contrôle total du design

### Étapes:

1. **Ouvrir PowerPoint** et créer une présentation vide

2. **Pour chaque section** (26 au total):

   a. **Va dans BigQuery Console**
      - https://console.cloud.google.com/bigquery?project=hulken

   b. **Exécute la requête SQL** correspondante
      - Toutes les requêtes sont dans: [docs/LOOKER_STUDIO_SETUP.md](docs/LOOKER_STUDIO_SETUP.md)
      - Exemple pour Section 1 (Executive Summary):
        ```sql
        SELECT
          'Gross Revenue' AS metric,
          SUM(revenue) AS value
        FROM `hulken.ads_data.marketing_unified`
        WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH);
        ```

   c. **Click "Chart"** en bas à droite de BigQuery
      - Choisir le type de graphique (bar, line, pie)
      - Screenshot le graphique

   d. **Colle dans PowerPoint**
      - Nouvelle slide
      - Coller l'image (Cmd+V)
      - Ajouter titre et annotations

3. **Répéter pour les 26 sections**

**✅ Résultat:** PowerPoint 100% personnalisé avec tes données

---

## 🥉 OPTION 3: Template Python → Remplir Manuellement

**Temps:** 45-60 minutes
**Avantage:** Structure déjà créée, tu remplis juste les données

### Étapes:

1. **Installer python-pptx** (si pas déjà fait)
   ```bash
   cd ~/Documents/Projects/Dev_Ops

   # Créer un environnement virtuel
   python3 -m venv venv
   source venv/bin/activate

   # Installer python-pptx
   pip install python-pptx
   ```

2. **Générer le template**
   ```bash
   python3 scripts/generate_powerpoint.py
   ```

3. **Ouvrir le PowerPoint généré**
   - Fichier: `reports/Marketing_Performance_Report.pptx`
   - Il contient déjà 16 slides avec la structure

4. **Remplir les données**
   - Les slides ont des données "placeholder"
   - Remplace-les avec les vraies données de BigQuery
   - Ajoute des graphiques screenshots de Looker ou BigQuery

**✅ Résultat:** PowerPoint avec structure complète, à remplir avec vraies données

---

## 📋 Les 26 Sections à Créer

Voici la liste complète avec statut:

### Section 1: Total Business Performance
1. ✅ **Executive Summary** - `executive_summary_monthly` VIEW
2. ✅ **Marketing Efficiency** - `marketing_monthly_performance` VIEW

### Section 2: Dot-Com (DTC) Performance
3. ✅ **Sitewide Overview** - `shopify_daily_metrics` VIEW
4. ✅ **Traffic & Sales Trends** - Graphique depuis `shopify_daily_metrics`
5. ✅ **Conversion & Revenue Efficiency** - KPIs calculés
6. ✅ **Marketing Cost Efficiency** - `marketing_unified` TABLE
7. ✅ **New vs Returning** - `shopify_daily_metrics` VIEW
8. ⚠️ **Search Demand Trends** - BESOIN: Google Trends API
9. ✅ **Funnel Measurement** - Calculable depuis `shopify_unified`
10. ✅ **Merchandising Performance** - `product_performance` VIEW
11. ⚠️ **Content & UX** - BESOIN: GA4 data
12. ✅ **Geographic Insights** - `shopify_unified` avec filtre geo
13. ✅ **International (Canada)** - `shopify_unified` filtré
14. ⚠️ **Demographics & Devices** - BESOIN: GA4 data

### Section 3: Amazon Performance
15. ⚠️ **Amazon Overview** - BESOIN: Amazon Ads
16. ⚠️ **Amazon Traffic/Conversion** - BESOIN: Amazon Ads
17. ⚠️ **Amazon Merchandising** - BESOIN: Amazon Ads

### Section 4: Paid Marketing
18. ✅ **Paid Channel Mix** - `channel_mix` VIEW
19. ✅ **PPC Performance Table** - `marketing_unified` TABLE
20. ⚠️ **Creative Performance** - BESOIN: Motion data
21. ⚠️ **Landing Page Performance** - BESOIN: GA4 + UTM
22. ⚠️ **Reach & Saturation** - BESOIN: Facebook Ads Manager
23. ⚠️ **Search Query Performance** - BESOIN: Google Ads query data

### Section 5: Customer Voice
24. ⚠️ **Attribution & Awareness** - BESOIN: Fairing surveys
25. ⚠️ **Purchase Friction** - BESOIN: Fairing surveys

### Appendix
26. ✅ **Total Business PPC Index** - `marketing_monthly_performance` VIEW

**Résumé:** 20/26 sections disponibles (77%)

---

## 🎯 Ma Recommandation

**Pour commencer MAINTENANT (15 min):**

1. **Va sur:** https://lookerstudio.google.com
2. **Suis:** [docs/LOOKER_10MIN_QUICKSTART.md](docs/LOOKER_10MIN_QUICKSTART.md)
3. **Crée** 4 pages avec:
   - Page 1: Executive Summary (KPIs + trend)
   - Page 2: Shopify Performance
   - Page 3: Channel Mix
   - Page 4: Top Products
4. **Download PDF** et convertir en PowerPoint

**Résultat:** Tu auras 70% du rapport en 15 minutes!

---

## 📚 Tous les Fichiers & Guides

| Fichier | Description |
|---------|-------------|
| **[COMMENT_CREER_SLIDES.md](COMMENT_CREER_SLIDES.md)** | Ce fichier - 3 options |
| **[docs/LOOKER_10MIN_QUICKSTART.md](docs/LOOKER_10MIN_QUICKSTART.md)** | Guide rapide Looker (COMMENCE ICI!) |
| **[docs/LOOKER_STUDIO_SETUP.md](docs/LOOKER_STUDIO_SETUP.md)** | Guide complet avec toutes les requêtes SQL |
| **[README_REPORTING.md](README_REPORTING.md)** | Vue d'ensemble du système |
| **[scripts/generate_powerpoint.py](scripts/generate_powerpoint.py)** | Script Python pour template |

---

## ❓ FAQ

### "Je suis pressé, quelle est l'option la plus rapide?"
→ **Option 1** (Looker Studio). 15 minutes pour avoir un dashboard professionnel.

### "Je veux un PowerPoint pour une présentation demain"
→ **Option 1** aussi. Crée le dashboard Looker, download en PDF, convertir en PowerPoint.

### "Je veux contrôle total du design"
→ **Option 2** (BigQuery manuel). Plus long mais plus de flexibilité.

### "Aucune de ces options ne fonctionne"
→ Dis-moi exactement ce qui bloque et je t'aide!

---

## 🚀 Action Immédiate

**MAINTENANT, fais ça:**

1. Ouvre un nouvel onglet: https://lookerstudio.google.com
2. Ouvre un autre onglet avec le guide: [docs/LOOKER_10MIN_QUICKSTART.md](docs/LOOKER_10MIN_QUICKSTART.md)
3. Suis les étapes pendant 10 minutes
4. Reviens me dire si tu es bloqué

**Dans 10 minutes tu auras ton premier dashboard!** 🎉

