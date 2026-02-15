# Shopify Inventory Items - Table Vide

**Date:** 2026-02-15
**Problème:** La table `shopify_live_inventory_items` est complètement vide (0 lignes)

---

## 🔍 Diagnostic

### État actuel
```sql
SELECT COUNT(*) FROM `hulken.ads_data.shopify_live_inventory_items`;
-- Résultat: 0
```

### Causes possibles

1. **Stream désactivé dans Airbyte**
   - Le stream "Inventory Items" n'est peut-être pas coché dans la configuration Shopify
   - Solution: Activer le stream

2. **Permissions API manquantes**
   - Le token Shopify n'a peut-être pas le scope `read_inventory`
   - Solution: Ajouter le scope au token

3. **Aucune donnée d'inventaire dans Shopify**
   - La boutique n'utilise peut-être pas l'inventaire tracking
   - Solution: Activer inventory tracking dans Shopify

4. **Erreur de sync silencieuse**
   - Airbyte essaie de syncer mais échoue
   - Solution: Vérifier les logs Airbyte

---

## ✅ Solution Recommandée

### Étape 1: Accéder à Airbyte

```bash
# Depuis votre Mac
cd /Users/raphael_sebbah/Documents/Projects/Dev_Ops

# Démarrer la VM Airbyte (si arrêtée)
gcloud compute instances start instance-20260129-133637 \
  --project=hulken \
  --zone=us-central1-a

# Créer le tunnel IAP vers Airbyte
gcloud compute start-iap-tunnel instance-20260129-133637 8000 \
  --local-host-port=localhost:8006 \
  --zone=us-central1-a \
  --project=hulken
```

**Ensuite, ouvrir:** http://localhost:8006

---

### Étape 2: Vérifier la configuration Shopify dans Airbyte

1. Aller dans **Connections** → **Shopify → BigQuery**
2. Cliquer sur **Settings** / **Streams**
3. Chercher **"Inventory Items"** dans la liste des streams
4. Vérifier que:
   - ✅ La checkbox est cochée (stream activé)
   - ✅ Sync mode: `Full Refresh | Overwrite` ou `Incremental | Append`

### Étape 3: Si le stream est désactivé

1. Cocher la case **Inventory Items**
2. Choisir le sync mode: **Incremental | Append** (recommandé)
3. Cliquer **Save changes**
4. Cliquer **Sync now** pour forcer un sync manuel
5. Attendre 5-10 minutes
6. Vérifier dans BigQuery:
   ```sql
   SELECT COUNT(*) FROM `hulken.ads_data.shopify_live_inventory_items`;
   ```

---

### Étape 4: Si le stream est activé mais toujours vide

#### A. Vérifier les permissions du token Shopify

1. Aller dans Shopify Admin: https://hulken-inc.myshopify.com/admin
2. **Settings** → **Apps and sales channels** → **Develop apps**
3. Trouver l'app utilisée par Airbyte
4. **API credentials** → **Admin API access scopes**
5. Vérifier que ces scopes sont activés:
   - ✅ `read_inventory`
   - ✅ `read_products`
   - ✅ `read_all_orders`

6. Si `read_inventory` est manquant:
   - Cocher `read_inventory`
   - **Save**
   - **Reinstall app** (pour appliquer les nouveaux scopes)
   - Copier le nouveau Access Token
   - Retourner dans Airbyte → Shopify source → **Edit** → Coller le nouveau token
   - **Test** → **Save** → **Sync now**

---

#### B. Vérifier les logs Airbyte pour erreurs

1. Dans Airbyte UI: **Connections** → **Shopify → BigQuery**
2. Onglet **Job History**
3. Cliquer sur le dernier sync
4. Chercher des erreurs pour "Inventory Items"
5. Si erreur visible, la copier et me la partager pour diagnostic

---

## 🎯 Utilité de Inventory Items

### Données disponibles dans ce stream

- `cost`: Coût d'achat du produit (COGS)
- `tracked`: Est-ce que l'inventaire est tracké
- `country_code_of_origin`: Pays d'origine du produit
- `sku`: SKU du produit
- `product_id`: ID du produit lié

### Cas d'usage

1. **Calcul des marges**
   ```sql
   WITH product_costs AS (
     SELECT
       product_id,
       AVG(cost) AS avg_cost
     FROM `hulken.ads_data.shopify_live_inventory_items`
     GROUP BY product_id
   )

   SELECT
     o.order_id,
     o.order_value,
     SUM(c.avg_cost * i.quantity) AS total_cost,
     o.order_value - SUM(c.avg_cost * i.quantity) AS gross_margin
   FROM `hulken.ads_data.shopify_unified` o
   JOIN `hulken.ads_data.shopify_line_items` i
     ON o.order_id = i.order_id
   JOIN product_costs c
     ON i.product_id = c.product_id
   GROUP BY o.order_id, o.order_value
   ```

2. **Analyse de profitabilité par produit**
3. **Calcul du ROAS réel** (revenue - COGS) / ad_spend
4. **Suivi des stocks** (si tracked = true)

---

## 🚨 Si toujours vide après toutes ces étapes

### Option 1: Vérifier dans Shopify Admin

1. Aller dans **Products** → N'importe quel produit
2. Section **Inventory**
3. Vérifier qu'il y a bien des **variant inventory items**
4. Si tous les produits sont en "Track quantity = OFF", alors c'est normal qu'il n'y ait pas de données

### Option 2: Alternative - Utiliser Products à la place

Si Shopify n'utilise pas inventory tracking, utiliser `shopify_live_products` pour le coût:

```sql
SELECT
  id AS product_id,
  title,
  vendor,
  -- Extraire le cost des variants
  JSON_EXTRACT_SCALAR(variants[0], '$.cost') AS cost,
  JSON_EXTRACT_SCALAR(variants[0], '$.sku') AS sku
FROM `hulken.ads_data.shopify_live_products`
```

---

## 📝 Checklist de résolution

- [ ] Accéder à Airbyte UI (tunnel IAP)
- [ ] Vérifier que "Inventory Items" stream est activé
- [ ] Si désactivé → Activer et forcer sync
- [ ] Si activé mais vide → Vérifier permissions API (`read_inventory`)
- [ ] Si permissions OK → Vérifier logs Airbyte pour erreurs
- [ ] Si pas d'erreur → Vérifier Shopify Admin si inventory tracking est ON
- [ ] Si tracking OFF → Utiliser shopify_live_products comme alternative

---

## 🎉 Résultat attendu

Après activation:

```sql
SELECT COUNT(*) FROM `hulken.ads_data.shopify_live_inventory_items`;
-- Devrait être > 0 (nombre de variants de produits)

SELECT
  sku,
  cost,
  tracked,
  country_code_of_origin
FROM `hulken.ads_data.shopify_live_inventory_items`
LIMIT 10;
```

