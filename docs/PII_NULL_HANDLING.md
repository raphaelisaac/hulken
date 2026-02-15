# PII Encoding - Traitement des NULL 🔐

**Date:** 2026-02-15
**Règle Importante:** NULL ne doit JAMAIS être encrypté!

---

## 🎯 Règle d'Or

**NULL reste NULL - Pas d'encryption!**

### Pourquoi?

| Cas | Exemple | Signification | Traitement |
|-----|---------|---------------|------------|
| **Valeur présente** | `john@example.com` | Client a fourni donnée | ✅ HASH |
| **Valeur manquante** | `NULL` | Guest checkout, donnée non fournie | ❌ PAS DE HASH |

**NULL signifie "donnée manquante"** - c'est une information sémantique importante qui doit être préservée.

---

## 📊 PII Couvertes

Le système encode de façon cohérente **6 types de données sensibles:**

| Type PII | Champ Source | Table de Référence | Exemple d'Usage |
|----------|--------------|-------------------|-----------------|
| **Email** | `email_hash` | `pii_email_reference` | Customer tracking, attribution |
| **Téléphone** | `phone_hash` | `pii_phone_reference` | Customer tracking, SMS marketing |
| **Prénom** | `first_name_hash` | `pii_first_name_reference` | Customer profiling |
| **Nom** | `last_name_hash` | `pii_last_name_reference` | Customer profiling |
| **Adresse** | `addresses_hash`, `default_address_hash` | `pii_address_reference` | Geographic analysis |
| **IP Browser** | `browser_ip` | `pii_ip_reference` | Fraud detection |

**Table Master:** `pii_master_reference` - Combine toutes les PII en une seule table

---

## ✅ Implémentation Correcte

### Étape 1: Tables de Référence (Excluent NULL)

Le script `create_complete_pii_reference.sql` crée **7 tables** pour toutes les PII:

#### 1. Email Reference

```sql
CREATE OR REPLACE TABLE `hulken.ads_data.pii_email_reference` AS

WITH all_emails AS (
  -- Shopify customers (NULL excluded)
  SELECT DISTINCT
    email_hash AS email_hash_original,
    'shopify_customers' AS source
  FROM `hulken.ads_data.shopify_live_customers_clean`
  WHERE email_hash IS NOT NULL  -- ✅ NULL values are EXCLUDED

  UNION DISTINCT

  -- Shopify orders (NULL excluded)
  SELECT DISTINCT
    email_hash AS email_hash_original,
    'shopify_orders' AS source
  FROM `hulken.ads_data.shopify_live_orders_clean`
  WHERE email_hash IS NOT NULL  -- ✅ NULL values are EXCLUDED
)

SELECT
  email_hash_original,
  TO_HEX(SHA256(email_hash_original)) AS email_hash_consistent,
  STRING_AGG(DISTINCT source, ', ') AS sources,
  COUNT(DISTINCT source) AS source_count
FROM all_emails
GROUP BY email_hash_original;
```

#### 2. Phone Reference

```sql
CREATE OR REPLACE TABLE `hulken.ads_data.pii_phone_reference` AS

WITH all_phones AS (
  SELECT DISTINCT
    phone_hash AS phone_hash_original,
    'shopify_customers' AS source
  FROM `hulken.ads_data.shopify_live_customers_clean`
  WHERE phone_hash IS NOT NULL  -- ✅ NULL excluded

  UNION DISTINCT

  SELECT DISTINCT
    phone_hash AS phone_hash_original,
    'shopify_orders' AS source
  FROM `hulken.ads_data.shopify_live_orders_clean`
  WHERE phone_hash IS NOT NULL  -- ✅ NULL excluded
)

SELECT
  phone_hash_original,
  TO_HEX(SHA256(phone_hash_original)) AS phone_hash_consistent,
  STRING_AGG(DISTINCT source, ', ') AS sources,
  COUNT(DISTINCT source) AS source_count
FROM all_phones
GROUP BY phone_hash_original;
```

**Même pattern pour:**
- ✅ `pii_first_name_reference`
- ✅ `pii_last_name_reference`
- ✅ `pii_address_reference`
- ✅ `pii_ip_reference`

#### 7. Master Reference (Combine Tout)

```sql
CREATE OR REPLACE TABLE `hulken.ads_data.pii_master_reference` AS

SELECT 'email' AS pii_field, email_hash_original AS original_value,
       email_hash_consistent AS consistent_hash, sources, source_count
FROM `hulken.ads_data.pii_email_reference`

UNION ALL

SELECT 'phone' AS pii_field, phone_hash_original AS original_value,
       phone_hash_consistent AS consistent_hash, sources, source_count
FROM `hulken.ads_data.pii_phone_reference`

-- ... (first_name, last_name, address, ip)
```

**Résultat:**
- Toutes les tables contiennent SEULEMENT les valeurs non-NULL
- NULL n'apparaît jamais dans aucune table de référence PII
- Table master permet de query toutes les PII en un seul endroit

---

### Étape 2: Utilisation dans Tables Unifiées (Préserve NULL)

```sql
SELECT
  -- ========== PII - CONSISTENT HASHING ==========
  -- IMPORTANT: NULL values are preserved (not hashed)
  -- If email_hash_original is NULL, email_hash_consistent will also be NULL (LEFT JOIN)
  COALESCE(
    pii_ref.email_hash_consistent,  -- Hash consistent si email existe dans reference
    o.email_hash_original            -- Sinon, garde l'original (qui peut être NULL)
  ) AS order_email_hash

FROM orders_base o

-- LEFT JOIN (not INNER JOIN!)
-- This ensures NULL emails stay NULL
LEFT JOIN `hulken.ads_data.pii_hash_reference` pii_ref
  ON o.email_hash_original = pii_ref.email_hash_original;
```

**Explication:**

1. **LEFT JOIN (pas INNER JOIN!)**
   - Si `email_hash_original` = `NULL`, pas de match dans `pii_ref`
   - `pii_ref.email_hash_consistent` sera `NULL`
   - `COALESCE` retourne `o.email_hash_original` qui est `NULL`
   - **Résultat:** NULL préservé ✅

2. **Si email existe:**
   - `email_hash_original` = `"abc123"`
   - Match trouvé dans `pii_ref`
   - `pii_ref.email_hash_consistent` = `"xyz789"` (hash consistent)
   - `COALESCE` retourne le hash consistent
   - **Résultat:** Hash cohérent ✅

---

## ❌ Implémentation Incorrecte (À Éviter!)

### Erreur 1: Hash NULL directement

```sql
-- ❌ MAUVAIS - Ceci hash NULL!
SELECT
  TO_HEX(SHA256(COALESCE(email_hash, 'UNKNOWN'))) AS email_hash_hashed
FROM orders;
```

**Problème:** `COALESCE(email_hash, 'UNKNOWN')` remplace NULL par `'UNKNOWN'`, qui est ensuite hashé. Tu perds l'information que l'email est manquant!

---

### Erreur 2: INNER JOIN au lieu de LEFT JOIN

```sql
-- ❌ MAUVAIS - Ceci exclut les NULL!
SELECT
  o.order_id,
  pii_ref.email_hash_consistent
FROM orders o
INNER JOIN pii_hash_reference pii_ref  -- ❌ INNER JOIN drops NULL rows!
  ON o.email_hash = pii_ref.email_hash_original;
```

**Problème:** `INNER JOIN` exclut tous les orders avec `email_hash = NULL`. Tu perds ces orders dans la table finale!

---

### Erreur 3: Inclure NULL dans la table de référence

```sql
-- ❌ MAUVAIS - Inclut NULL dans reference table
WITH all_emails AS (
  SELECT DISTINCT email_hash
  FROM shopify_customers
  -- ❌ Pas de WHERE email_hash IS NOT NULL
)

SELECT
  COALESCE(email_hash, 'NULL_VALUE') AS email_hash_original,  -- ❌ Hash NULL!
  TO_HEX(SHA256(COALESCE(email_hash, 'NULL_VALUE'))) AS email_hash_consistent
FROM all_emails;
```

**Problème:** Tous les NULL reçoivent le même hash `TO_HEX(SHA256('NULL_VALUE'))`. On ne peut plus distinguer les différents cas de NULL!

---

## 📊 Vérification de l'Implémentation

### Test 1: Vérifier que pii_hash_reference n'a pas de NULL

```sql
SELECT
  COUNT(*) AS total_rows,
  COUNTIF(email_hash_original IS NULL) AS null_original,
  COUNTIF(email_hash_consistent IS NULL) AS null_consistent
FROM `hulken.ads_data.pii_hash_reference`;
```

**Résultat attendu:**
```
total_rows: 12,345
null_original: 0        ← ✅ Pas de NULL
null_consistent: 0      ← ✅ Pas de NULL
```

---

### Test 2: Vérifier que shopify_unified préserve NULL

```sql
SELECT
  COUNT(*) AS total_orders,
  COUNTIF(order_email_hash IS NULL) AS null_order_emails,
  COUNTIF(customer_email_hash IS NULL) AS null_customer_emails,
  ROUND(COUNTIF(order_email_hash IS NULL) / COUNT(*) * 100, 2) AS null_pct
FROM `hulken.ads_data.shopify_unified`;
```

**Résultat attendu:**
```
total_orders: 45,471
null_order_emails: 2,341    ← ✅ Guest checkouts préservés!
null_customer_emails: 3,127
null_pct: 5.15%             ← ✅ ~5% NULL est normal
```

---

### Test 3: Vérifier consistency (même email = même hash)

```sql
WITH email_hashes AS (
  -- Get all order email hashes
  SELECT DISTINCT order_email_hash AS email_hash
  FROM `hulken.ads_data.shopify_unified`
  WHERE order_email_hash IS NOT NULL

  UNION DISTINCT

  -- Get all customer email hashes
  SELECT DISTINCT customer_email_hash AS email_hash
  FROM `hulken.ads_data.shopify_unified`
  WHERE customer_email_hash IS NOT NULL
)

SELECT
  COUNT(*) AS total_unique_hashes
FROM email_hashes;

-- Compare with pii_hash_reference count
-- Should be equal (1:1 mapping)
```

**Résultat attendu:**
```
total_unique_hashes: 10,004

-- Should match:
SELECT COUNT(*) FROM pii_hash_reference;  -- 10,004 ✅
```

---

## 🔄 Cas d'Usage Pratiques

### Cas 1: Guest Checkout (NULL Email)

**Données originales:**
```
order_id: 12345
email_hash: NULL  ← Guest checkout, pas d'email
order_value: $125.00
```

**Après PII encoding:**
```
order_id: 12345
order_email_hash: NULL  ← ✅ Preserved!
order_value: $125.00
```

**Analyse:**
```sql
-- Comparer orders avec vs sans email
SELECT
  CASE
    WHEN order_email_hash IS NULL THEN 'Guest Checkout'
    ELSE 'Registered Customer'
  END AS customer_type,
  COUNT(*) AS order_count,
  ROUND(AVG(order_value), 2) AS avg_order_value
FROM shopify_unified
GROUP BY customer_type;
```

**Résultat:**
```
customer_type         | order_count | avg_order_value
Guest Checkout        | 2,341       | $87.45
Registered Customer   | 43,130      | $102.33
```

**Insight:** Guest checkouts ont AOV plus bas - info importante! Si on avait hashé NULL, on perdrait cette distinction.

---

### Cas 2: Même Email dans Orders et Customers

**Données originales:**
```
-- Orders table
order_id: 67890
email_hash: "abc123XYZ"

-- Customers table
customer_id: 5555
email_hash: "abc123XYZ"  ← Même email original
```

**Après PII encoding:**
```
-- shopify_unified
order_id: 67890
order_email_hash: "DEADBEEF123456..."      ← Hash consistent
customer_email_hash: "DEADBEEF123456..."   ← ✅ MÊME HASH!
```

**Analyse:**
```sql
-- Vérifier que orders et customers matchent
SELECT
  order_id,
  order_email_hash,
  customer_email_hash,
  CASE
    WHEN order_email_hash = customer_email_hash THEN 'Match'
    WHEN order_email_hash IS NULL AND customer_email_hash IS NULL THEN 'Both NULL'
    WHEN order_email_hash IS NULL OR customer_email_hash IS NULL THEN 'Partial NULL'
    ELSE 'Mismatch'
  END AS match_status
FROM shopify_unified
LIMIT 100;
```

---

### Cas 3: Même Email dans Différentes Sources

**Données originales:**
```
-- Shopify
email_hash: "abc123XYZ"

-- Facebook (via custom audience upload)
email_hash: "abc123XYZ"  ← Même email

-- TikTok
email_hash: "abc123XYZ"  ← Même email
```

**Après PII encoding:**
```
-- Toutes les sources
consistent_hash: "DEADBEEF123456..."  ← ✅ MÊME HASH partout!
```

**Analyse:**
```sql
-- Cross-platform customer tracking
SELECT
  email_hash_consistent,
  COUNT(DISTINCT source) AS platforms_count,
  STRING_AGG(DISTINCT source, ', ') AS platforms
FROM pii_hash_reference
GROUP BY email_hash_consistent
HAVING COUNT(DISTINCT source) > 1
ORDER BY platforms_count DESC
LIMIT 10;
```

**Résultat:**
```
email_hash_consistent     | platforms_count | platforms
DEADBEEF123456...         | 3               | shopify, facebook, tiktok
CAFE12345678...           | 2               | shopify, facebook
...
```

---

## 🚨 Que Faire Si NULL Est Déjà Hashé?

Si tu as déjà hashé NULL par erreur, voici comment fix:

### Étape 1: Identifier les NULL hashés

```sql
-- Check si tu as le même hash pour beaucoup de "NULL"
SELECT
  email_hash_consistent,
  COUNT(*) AS occurrence_count
FROM pii_hash_reference
GROUP BY email_hash_consistent
HAVING COUNT(*) > 1000  -- Suspect si >1000 fois le même hash
ORDER BY occurrence_count DESC;
```

**Si tu vois un hash répété des milliers de fois, c'est probablement le hash de NULL!**

---

### Étape 2: Re-créer pii_hash_reference (correct)

```bash
cd ~/Documents/Projects/Dev_Ops
python3 scripts/master_workflow.py --skip-reconciliation --skip-report
```

Ou manuellement:
```sql
-- Re-run la création de pii_hash_reference avec WHERE IS NOT NULL
-- Voir: sql/update_unified_with_pii_reference.sql
```

---

### Étape 3: Re-créer tables unifiées

```bash
bq query --project_id=hulken --use_legacy_sql=false < sql/update_unified_with_pii_reference.sql
```

---

## ✅ Checklist Finale

- [ ] `pii_hash_reference` créée avec `WHERE email_hash IS NOT NULL`
- [ ] Tables unifiées utilisent `LEFT JOIN` (pas `INNER JOIN`)
- [ ] `COALESCE(pii_ref.hash, original)` préserve NULL
- [ ] Test vérifié: `pii_hash_reference` n'a pas de NULL
- [ ] Test vérifié: `shopify_unified` a des NULL préservés (~5% normal)
- [ ] Test vérifié: Même email = même hash across tables

---

## 📚 Ressources

**Scripts:**
- [master_workflow.py](../scripts/master_workflow.py) - Crée `pii_hash_reference` correctement
- [update_unified_with_pii_reference.sql](../sql/update_unified_with_pii_reference.sql) - Update tables unifiées

**Documentation:**
- [WORKFLOW_COMPLET.md](../WORKFLOW_COMPLET.md) - Étape 5: Encoding PII
- [COMPRENDRE_LES_DONNEES.md](COMPRENDRE_LES_DONNEES.md) - Cas 2: Valeurs à 0 (inclut NULL)

---

## 🎯 Résumé en 3 Points

1. **NULL ≠ Valeur** - NULL signifie "donnée manquante", c'est une information sémantique
2. **Table de référence exclut NULL** - `WHERE email_hash IS NOT NULL`
3. **LEFT JOIN préserve NULL** - Pas d'`INNER JOIN` qui dropperait les NULL

**Règle d'or:** NULL entre, NULL sort. Pas de hash! ✅

