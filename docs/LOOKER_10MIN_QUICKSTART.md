# Dashboard Looker Studio en 10 Minutes ⏱️

**Objectif:** Créer un dashboard professionnel avec tes vraies données BigQuery

---

## 🚀 Étape 1: Ouvrir Looker Studio (1 min)

1. Va sur: **https://lookerstudio.google.com**
2. Se connecter avec ton compte Google (celui du projet `hulken`)
3. Cliquer **"Create"** → **"Report"**

---

## 🔌 Étape 2: Connecter BigQuery (2 min)

1. Dans la fenêtre "Add data to report":
   - Chercher **"BigQuery"**
   - Cliquer sur **"BigQuery"** (by Google)

2. Autoriser l'accès si demandé

3. Sélectionner:
   - **My Projects** → `hulken`
   - **Dataset:** `ads_data`
   - **Table:** `marketing_unified`

4. Cliquer **"ADD"**

5. Si demandé "Add to report?", cliquer **"ADD TO REPORT"**

**✅ Tu es maintenant connecté à tes données!**

---

## 📊 Étape 3: Créer les KPIs Principaux (5 min)

### KPI 1: Total Revenue

1. Cliquer **"Add a chart"** (en haut) → **"Scorecard"**
2. Placer le scorecard en haut à gauche
3. Dans le panneau **"Setup"** à droite:
   - **Data source:** `marketing_unified` (déjà sélectionné)
   - **Date range dimension:** `date`
   - **Metric:** Cliquer sur le metric actuel → Chercher `revenue` → Sélectionner
   - **Aggregation:** `SUM`

4. Dans l'onglet **"Style"**:
   - **Number format:** Currency → **USD ($)**
   - **Compact numbers:** OFF
   - **Decimals:** 0

5. Ajouter un titre:
   - Cliquer sur le scorecard
   - Aller dans **"Style"** → **"Scorecard name"**
   - Écrire: **"Total Revenue"**

**🎉 Premier KPI créé!**

---

### KPI 2-4: Copier le KPI Revenue

1. Sélectionner le scorecard Revenue
2. **Cmd+C** (copier) puis **Cmd+V** (coller) 3 fois
3. Placer les 3 nouveaux scorecards à côté du premier

Pour chaque scorecard, changer le metric:

**KPI 2 - Total Spend:**
- Metric: `ad_spend` (SUM)
- Titre: "Total Ad Spend"

**KPI 3 - Orders:**
- Metric: `orders` (SUM)
- Number format: **Number** (pas Currency)
- Titre: "Total Orders"

**KPI 4 - ROAS:**
- Metric: Cliquer "CREATE FIELD" → Écrire:
  ```
  SUM(revenue) / SUM(ad_spend)
  ```
  - Name: `ROAS`
  - Cliquer **"SAVE"** puis **"DONE"**
- Number format: **Number** → 2 decimals
- Titre: "ROAS"

---

### Graphique 1: Revenue & Spend Trend

1. Cliquer **"Add a chart"** → **"Time series chart"**
2. Placer sous les KPIs
3. Setup:
   - **Date range dimension:** `date`
   - **Dimension:** `date`
   - **Metric 1:** `revenue` (SUM)
   - **Metric 2:** `ad_spend` (SUM)

4. Style:
   - **Line 1 color:** Blue (#4285F4)
   - **Line 2 color:** Red (#EA4335)
   - **Show data labels:** ON

5. Titre: "Revenue vs Spend Trend"

---

### Tableau 1: Performance par Canal

1. Cliquer **"Add a chart"** → **"Table"**
2. Placer à droite du graphique
3. Setup:
   - **Dimension:** `channel`
   - **Metrics:**
     - `ad_spend` (SUM) → Rename: "Spend"
     - `revenue` (SUM) → Rename: "Revenue"
     - `orders` (SUM) → Rename: "Orders"
     - Créer un champ ROAS: `SUM(revenue) / SUM(ad_spend)`

4. Style:
   - **Show header:** ON
   - **Show row numbers:** OFF
   - **Bars:** ON (pour visualiser les valeurs)

5. Tri: Cliquer sur colonne "Spend" → **Sort descending**

---

## 🎨 Étape 4: Ajouter Plus de Pages (2 min)

### Page 2: Shopify Performance

1. En bas, cliquer **"Add a page"**
2. Nommer la page: "Shopify Performance"

3. Changer la source de données:
   - **Add data** → **BigQuery**
   - `hulken` → `ads_data` → `shopify_daily_metrics`
   - **ADD**

4. Créer des KPIs similaires avec:
   - Total Orders: `SUM(orders)`
   - Gross Revenue: `SUM(gross_revenue)`
   - AOV: `SUM(gross_revenue) / SUM(orders)`
   - Returning %: `AVG(returning_customer_pct)`

### Page 3: Product Performance

1. **Add a page** → "Top Products"
2. **Add data** → `product_performance`
3. Créer un tableau:
   - Dimensions: `product_name`, `month`
   - Metrics: `gross_revenue`, `total_units`
   - Tri: par `gross_revenue` DESC
   - Limit: Top 20

### Page 4: Channel Mix

1. **Add a page** → "Channel Mix"
2. **Add data** → `channel_mix`
3. Créer un **Pie chart**:
   - Dimension: `channel`
   - Metric: `total_spend`
   - Show percentages: ON

---

## 📥 Étape 5: Exporter en PowerPoint (1 min)

### Option A: Export PDF (puis PowerPoint)

1. En haut à droite, cliquer **"Download report"**
2. Sélectionner **"PDF - All pages"**
3. Wait for download
4. Ouvrir PowerPoint
5. **Insert** → **Pictures** → Sélectionner le PDF
6. PowerPoint va convertir chaque page en slide

### Option B: Screenshots

1. Pour chaque page:
   - **Cmd+Shift+4** (Mac) ou **Snipping Tool** (Windows)
   - Screenshot la page
2. Coller dans PowerPoint

### Option C: Partager le lien (Meilleur!)

1. Cliquer **"Share"** (en haut à droite)
2. **Get report link**
3. Copier le lien
4. Dans PowerPoint:
   - Créer une slide
   - **Insert** → **Link**
   - Coller le lien avec texte: "📊 Live Dashboard"

**Avantage:** Les stakeholders voient toujours les données à jour!

---

## 🎯 Résultat Final

Tu auras un dashboard avec:
- ✅ 4 pages
- ✅ ~15 visualisations
- ✅ Données en temps réel de BigQuery
- ✅ Filtres interactifs (date range, channel, etc.)
- ✅ Exportable en PDF/PowerPoint
- ✅ Partage facile par lien

**Temps total: 10 minutes** ⏱️

---

## 💡 Tips Avancés

### Ajouter des Filtres

1. Cliquer **"Add a control"** → **"Drop-down list"**
2. Setup:
   - **Control field:** `channel`
   - **Metric:** None
3. Placer en haut de la page

Maintenant tu peux filtrer par canal!

### Ajouter un Comparaison YoY

1. Dans n'importe quel scorecard:
   - Setup → **Comparison date range:** `Previous year`
   - Style → **Show comparison:** ON

Tu verras automatiquement le % change YoY!

### Thème Personnalisé

1. Aller dans **Theme and layout** (en haut à droite)
2. Choisir un thème prédéfini ou:
   - **Current theme** → **Customize**
   - Changer les couleurs primaires/secondaires
   - Changer les fonts

---

## 📚 Requêtes SQL Utiles

Si tu veux créer des visualisations custom, utilise **"Custom query"**:

### Revenue par Mois avec YoY

```sql
WITH current_year AS (
  SELECT
    DATE_TRUNC(date, MONTH) AS month,
    SUM(revenue) AS revenue,
    SUM(ad_spend) AS spend
  FROM `hulken.ads_data.marketing_unified`
  WHERE EXTRACT(YEAR FROM date) = EXTRACT(YEAR FROM CURRENT_DATE())
  GROUP BY month
),

last_year AS (
  SELECT
    DATE_TRUNC(date, MONTH) AS month,
    SUM(revenue) AS revenue
  FROM `hulken.ads_data.marketing_unified`
  WHERE EXTRACT(YEAR FROM date) = EXTRACT(YEAR FROM CURRENT_DATE()) - 1
  GROUP BY month
)

SELECT
  c.month,
  c.revenue AS current_revenue,
  c.spend AS current_spend,
  l.revenue AS last_year_revenue,
  SAFE_DIVIDE(c.revenue - l.revenue, l.revenue) * 100 AS yoy_growth_pct
FROM current_year c
LEFT JOIN last_year l
  ON EXTRACT(MONTH FROM c.month) = EXTRACT(MONTH FROM l.month)
ORDER BY c.month;
```

### Top 10 Produits (Actuel)

```sql
SELECT
  product_name,
  SUM(gross_revenue) AS revenue,
  SUM(total_units) AS units
FROM `hulken.ads_data.product_performance`
WHERE month >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)
GROUP BY product_name
ORDER BY revenue DESC
LIMIT 10;
```

---

## 🎉 Tu as Terminé!

Ton dashboard est prêt avec:
- ✅ Toutes les données BigQuery connectées
- ✅ KPIs principaux visibles
- ✅ Graphiques interactifs
- ✅ Exportable en PowerPoint

**Prochaine étape:** Partager le lien avec ton équipe! 🚀

