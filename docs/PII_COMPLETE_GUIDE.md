# Guide Complet - PII Encoding (TOUTES Données Sensibles) 🔐

**Date:** 2026-02-15
**Version:** 2.0 - Couverture Complète

---

## 🎯 Vue d'Ensemble

Le système encode maintenant **6 types de données sensibles** de façon cohérente:

| # | Type PII | Champ Source | Table de Référence | Cas d'Usage |
|---|----------|--------------|-------------------|-------------|
| 1 | **Email** | `email_hash` | `pii_email_reference` | Customer tracking, attribution marketing |
| 2 | **Téléphone** | `phone_hash` | `pii_phone_reference` | Customer tracking, SMS marketing |
| 3 | **Prénom** | `first_name_hash` | `pii_first_name_reference` | Customer profiling, segmentation |
| 4 | **Nom** | `last_name_hash` | `pii_last_name_reference` | Customer profiling, segmentation |
| 5 | **Adresse** | `addresses_hash`, `default_address_hash` | `pii_address_reference` | Geographic analysis, shipping |
| 6 | **IP Browser** | `browser_ip` | `pii_ip_reference` | Fraud detection, geo-location |

**Table Master:** `pii_master_reference` - Combine toutes les PII en une seule table

---

## ✅ Principe Fondamental

**NULL ne doit JAMAIS être encrypté!**

### Pourquoi NULL est Important

| Exemple | Signification Business | Action |
|---------|----------------------|--------|
| `email = NULL` | Guest checkout (pas de compte) | ❌ PAS DE HASH - Analyser les guests séparément |
| `phone = NULL` | Client n'a pas fourni téléphone | ❌ PAS DE HASH - Opportunité SMS marketing perdue |
| `first_name = NULL` | Donnée manquante | ❌ PAS DE HASH - Profil incomplet |
| `browser_ip = NULL` | Tracking bloqué ou bot | ❌ PAS DE HASH - Possiblement frauduleux |

**NULL = Information sémantique** → Doit être préservé pour analytics!

---

## 🚀 Quick Start

### Étape 1: Créer Toutes les Tables PII Reference

```bash
cd ~/Documents/Projects/Dev_Ops

# Option A: Via workflow complet (recommandé)
python3 scripts/master_workflow.py

# Option B: Script SQL direct
bq query --project_id=hulken --use_legacy_sql=false < sql/create_complete_pii_reference.sql
```

**Durée:** 2-3 minutes

**Résultat:** 7 tables créées:
1. `pii_email_reference`
2. `pii_phone_reference`
3. `pii_first_name_reference`
4. `pii_last_name_reference`
5. `pii_address_reference`
6. `pii_ip_reference`
7. `pii_master_reference` (master table)

---

### Étape 2: Vérifier que NULL est Exclu

```sql
-- Check que les tables de référence n'ont pas de NULL
SELECT
  'Email Ref' AS table_name,
  COUNT(*) AS total,
  COUNTIF(email_hash_original IS NULL) AS null_count
FROM `hulken.ads_data.pii_email_reference`

UNION ALL

SELECT
  'Phone Ref' AS table_name,
  COUNT(*) AS total,
  COUNTIF(phone_hash_original IS NULL) AS null_count
FROM `hulken.ads_data.pii_phone_reference`

UNION ALL

SELECT
  'First Name Ref' AS table_name,
  COUNT(*) AS total,
  COUNTIF(first_name_hash_original IS NULL) AS null_count
FROM `hulken.ads_data.pii_first_name_reference`

UNION ALL

SELECT
  'Last Name Ref' AS table_name,
  COUNT(*) AS total,
  COUNTIF(last_name_hash_original IS NULL) AS null_count
FROM `hulken.ads_data.pii_last_name_reference`

UNION ALL

SELECT
  'Address Ref' AS table_name,
  COUNT(*) AS total,
  COUNTIF(address_hash_original IS NULL) AS null_count
FROM `hulken.ads_data.pii_address_reference`

UNION ALL

SELECT
  'IP Ref' AS table_name,
  COUNT(*) AS total,
  COUNTIF(ip_original IS NULL) AS null_count
FROM `hulken.ads_data.pii_ip_reference`;
```

**Résultat attendu:** `null_count = 0` pour TOUTES les tables ✅

---

### Étape 3: View Summary de Toutes les PII

```sql
-- Summary de toutes les PII
SELECT
  pii_field,
  COUNT(*) AS unique_values,
  SUM(source_count) AS total_occurrences,
  ROUND(AVG(source_count), 2) AS avg_sources_per_value
FROM `hulken.ads_data.pii_master_reference`
GROUP BY pii_field
ORDER BY unique_values DESC;
```

**Résultat attendu:**
```
pii_field    | unique_values | total_occurrences | avg_sources_per_value
email        | 12,345        | 24,690           | 2.00
phone        | 8,234         | 16,468           | 2.00
first_name   | 5,678         | 5,678            | 1.00
last_name    | 6,789         | 6,789            | 1.00
address      | 9,123         | 18,246           | 2.00
ip           | 45,678        | 45,678           | 1.00
```

---

## 📊 Utilisation dans Tables Unifiées

### Pattern Correct (Préserve NULL)

```sql
SELECT
  -- Email avec hash cohérent
  COALESCE(
    pii_email.email_hash_consistent,
    o.email_hash  -- Fallback sur original (peut être NULL)
  ) AS order_email_hash,

  -- Phone avec hash cohérent
  COALESCE(
    pii_phone.phone_hash_consistent,
    o.phone_hash  -- Fallback sur original (peut être NULL)
  ) AS order_phone_hash,

  -- First name avec hash cohérent
  COALESCE(
    pii_fname.first_name_hash_consistent,
    c.first_name_hash  -- Fallback sur original (peut être NULL)
  ) AS customer_first_name_hash,

  -- Last name avec hash cohérent
  COALESCE(
    pii_lname.last_name_hash_consistent,
    c.last_name_hash  -- Fallback sur original (peut être NULL)
  ) AS customer_last_name_hash,

  -- IP avec hash cohérent
  COALESCE(
    pii_ip.ip_hash_consistent,
    TO_HEX(SHA256(o.browser_ip))  -- Hash directement si pas dans ref
  ) AS browser_ip_hash

FROM orders o

LEFT JOIN customers c
  ON o.customer_id = c.id

-- LEFT JOIN (pas INNER!) pour préserver NULL
LEFT JOIN `hulken.ads_data.pii_email_reference` pii_email
  ON o.email_hash = pii_email.email_hash_original

LEFT JOIN `hulken.ads_data.pii_phone_reference` pii_phone
  ON o.phone_hash = pii_phone.phone_hash_original

LEFT JOIN `hulken.ads_data.pii_first_name_reference` pii_fname
  ON c.first_name_hash = pii_fname.first_name_hash_original

LEFT JOIN `hulken.ads_data.pii_last_name_reference` pii_lname
  ON c.last_name_hash = pii_lname.last_name_hash_original

LEFT JOIN `hulken.ads_data.pii_ip_reference` pii_ip
  ON o.browser_ip = pii_ip.ip_original;
```

**Résultat:**
- Si email = NULL → `order_email_hash` reste NULL ✅
- Si email existe → Hash consistent appliqué ✅
- Même logique pour phone, first_name, last_name, address, IP ✅

---

## 🔍 Cas d'Usage Pratiques

### Cas 1: Customer 360 View (Toutes PII Cohérentes)

```sql
-- Get complete customer profile avec PII cohérentes
SELECT
  c.customer_id,
  pii_email.email_hash_consistent AS email_hash,
  pii_phone.phone_hash_consistent AS phone_hash,
  pii_fname.first_name_hash_consistent AS first_name_hash,
  pii_lname.last_name_hash_consistent AS last_name_hash,
  pii_addr.address_hash_consistent AS address_hash,

  -- Flags pour données manquantes
  CASE WHEN c.email_hash IS NULL THEN 'No Email' ELSE 'Has Email' END AS email_status,
  CASE WHEN c.phone_hash IS NULL THEN 'No Phone' ELSE 'Has Phone' END AS phone_status,
  CASE WHEN c.addresses_hash IS NULL THEN 'No Address' ELSE 'Has Address' END AS address_status,

  -- Completeness score
  (
    CAST(c.email_hash IS NOT NULL AS INT64) +
    CAST(c.phone_hash IS NOT NULL AS INT64) +
    CAST(c.first_name_hash IS NOT NULL AS INT64) +
    CAST(c.last_name_hash IS NOT NULL AS INT64) +
    CAST(c.addresses_hash IS NOT NULL AS INT64)
  ) AS profile_completeness_score  -- 0 to 5

FROM `hulken.ads_data.shopify_live_customers_clean` c

LEFT JOIN `hulken.ads_data.pii_email_reference` pii_email
  ON c.email_hash = pii_email.email_hash_original

LEFT JOIN `hulken.ads_data.pii_phone_reference` pii_phone
  ON c.phone_hash = pii_phone.phone_hash_original

LEFT JOIN `hulken.ads_data.pii_first_name_reference` pii_fname
  ON c.first_name_hash = pii_fname.first_name_hash_original

LEFT JOIN `hulken.ads_data.pii_last_name_reference` pii_lname
  ON c.last_name_hash = pii_lname.last_name_hash_original

LEFT JOIN `hulken.ads_data.pii_address_reference` pii_addr
  ON c.addresses_hash = pii_addr.address_hash_original

ORDER BY profile_completeness_score DESC;
```

**Insight:** Customers avec score < 3 → Opportunité d'enrichir le profil!

---

### Cas 2: Fraud Detection (IP + Email + Phone)

```sql
-- Detect suspicious patterns: Same IP, different emails/phones
WITH ip_patterns AS (
  SELECT
    pii_ip.ip_hash_consistent,
    COUNT(DISTINCT pii_email.email_hash_consistent) AS unique_emails,
    COUNT(DISTINCT pii_phone.phone_hash_consistent) AS unique_phones,
    COUNT(*) AS order_count

  FROM `hulken.ads_data.shopify_live_orders_clean` o

  LEFT JOIN `hulken.ads_data.pii_ip_reference` pii_ip
    ON o.browser_ip = pii_ip.ip_original

  LEFT JOIN `hulken.ads_data.pii_email_reference` pii_email
    ON o.email_hash = pii_email.email_hash_original

  LEFT JOIN `hulken.ads_data.pii_phone_reference` pii_phone
    ON o.phone_hash = pii_phone.phone_hash_original

  WHERE o.browser_ip IS NOT NULL
  GROUP BY pii_ip.ip_hash_consistent
)

SELECT
  ip_hash_consistent,
  unique_emails,
  unique_phones,
  order_count,
  CASE
    WHEN unique_emails > 5 AND unique_phones > 5 THEN 'High Risk - Many accounts from same IP'
    WHEN unique_emails > 3 THEN 'Medium Risk - Multiple accounts'
    ELSE 'Normal'
  END AS fraud_risk

FROM ip_patterns
WHERE unique_emails > 1 OR unique_phones > 1
ORDER BY unique_emails DESC, unique_phones DESC;
```

**Action:** Reviewer les "High Risk" IPs manuellement!

---

### Cas 3: Data Completeness Analysis

```sql
-- Analyze NULL rates par PII type
SELECT
  'Email' AS pii_type,
  COUNT(*) AS total_customers,
  COUNTIF(email_hash IS NOT NULL) AS has_value,
  COUNTIF(email_hash IS NULL) AS is_null,
  ROUND(COUNTIF(email_hash IS NULL) / COUNT(*) * 100, 2) AS null_pct
FROM `hulken.ads_data.shopify_live_customers_clean`

UNION ALL

SELECT
  'Phone' AS pii_type,
  COUNT(*) AS total_customers,
  COUNTIF(phone_hash IS NOT NULL) AS has_value,
  COUNTIF(phone_hash IS NULL) AS is_null,
  ROUND(COUNTIF(phone_hash IS NULL) / COUNT(*) * 100, 2) AS null_pct
FROM `hulken.ads_data.shopify_live_customers_clean`

UNION ALL

SELECT
  'First Name' AS pii_type,
  COUNT(*) AS total_customers,
  COUNTIF(first_name_hash IS NOT NULL) AS has_value,
  COUNTIF(first_name_hash IS NULL) AS is_null,
  ROUND(COUNTIF(first_name_hash IS NULL) / COUNT(*) * 100, 2) AS null_pct
FROM `hulken.ads_data.shopify_live_customers_clean`

UNION ALL

SELECT
  'Last Name' AS pii_type,
  COUNT(*) AS total_customers,
  COUNTIF(last_name_hash IS NOT NULL) AS has_value,
  COUNTIF(last_name_hash IS NULL) AS is_null,
  ROUND(COUNTIF(last_name_hash IS NULL) / COUNT(*) * 100, 2) AS null_pct
FROM `hulken.ads_data.shopify_live_customers_clean`

UNION ALL

SELECT
  'Address' AS pii_type,
  COUNT(*) AS total_customers,
  COUNTIF(addresses_hash IS NOT NULL) AS has_value,
  COUNTIF(addresses_hash IS NULL) AS is_null,
  ROUND(COUNTIF(addresses_hash IS NULL) / COUNT(*) * 100, 2) AS null_pct
FROM `hulken.ads_data.shopify_live_customers_clean`

ORDER BY null_pct DESC;
```

**Résultat Example:**
```
pii_type    | total_customers | has_value | is_null | null_pct
Address     | 15,234         | 12,456    | 2,778   | 18.23%   ← Priorité fix!
Phone       | 15,234         | 13,890    | 1,344   | 8.82%
Last Name   | 15,234         | 14,234    | 1,000   | 6.56%
First Name  | 15,234         | 14,890    | 344     | 2.26%
Email       | 15,234         | 15,100    | 134     | 0.88%    ← Bon!
```

**Action:** Focus sur collecting addresses (18% missing)!

---

## 🚨 Troubleshooting

### Problème 1: NULL a été hashé par erreur

**Symptôme:** `pii_email_reference` a des milliers de fois le même hash

**Diagnostic:**
```sql
SELECT
  email_hash_consistent,
  COUNT(*) AS occurrence_count
FROM `hulken.ads_data.pii_email_reference`
GROUP BY email_hash_consistent
HAVING COUNT(*) > 1000
ORDER BY occurrence_count DESC;
```

**Si un hash apparaît 5000+ fois → C'est probablement le hash de NULL!**

**Fix:**
```bash
# Re-run le script PII complet
cd ~/Documents/Projects/Dev_Ops
bq query --project_id=hulken --use_legacy_sql=false < sql/create_complete_pii_reference.sql
```

---

### Problème 2: Tables unifiées ont perdu des rows

**Symptôme:** `shopify_unified` a moins de rows que `shopify_live_orders_clean`

**Cause:** INNER JOIN au lieu de LEFT JOIN

**Fix:** Vérifier les JOINs dans `create_unified_tables.sql`:
```sql
-- ❌ MAUVAIS
INNER JOIN pii_email_reference  -- Drops NULL emails!

-- ✅ BON
LEFT JOIN pii_email_reference   -- Preserves NULL emails
```

---

### Problème 3: Même email a différents hash

**Symptôme:** Customer a email hash différent dans orders vs customers table

**Diagnostic:**
```sql
-- Check consistency
SELECT
  o.order_id,
  o.email_hash AS order_email,
  c.email_hash AS customer_email,
  CASE
    WHEN o.email_hash = c.email_hash THEN 'Match'
    WHEN o.email_hash IS NULL AND c.email_hash IS NULL THEN 'Both NULL'
    ELSE 'MISMATCH'
  END AS status
FROM `hulken.ads_data.shopify_live_orders_clean` o
LEFT JOIN `hulken.ads_data.shopify_live_customers_clean` c
  ON o.user_id = c.id
WHERE o.email_hash != c.email_hash
  AND o.email_hash IS NOT NULL
  AND c.email_hash IS NOT NULL
LIMIT 100;
```

**Fix:** Re-run PII reference creation + update unified tables

---

## ✅ Checklist Finale

- [ ] 7 tables PII créées (email, phone, first_name, last_name, address, ip, master)
- [ ] Vérification: Aucune table PII n'a de NULL (`null_count = 0`)
- [ ] Vérification: `pii_master_reference` a toutes les PII types
- [ ] Tables unifiées utilisent LEFT JOIN (pas INNER JOIN)
- [ ] Pattern COALESCE utilisé pour préserver NULL
- [ ] Test: shopify_unified a des NULL préservés (~5-10% normal)
- [ ] Test: Même email = même hash dans orders et customers
- [ ] Documentation lue: [PII_NULL_HANDLING.md](PII_NULL_HANDLING.md)

---

## 📚 Ressources

**Scripts:**
- [create_complete_pii_reference.sql](../sql/create_complete_pii_reference.sql) - Crée toutes les tables PII
- [master_workflow.py](../scripts/master_workflow.py) - Step 5: Encoding PII complet
- [update_unified_with_pii_reference.sql](../sql/update_unified_with_pii_reference.sql) - Update tables unifiées

**Documentation:**
- [PII_NULL_HANDLING.md](PII_NULL_HANDLING.md) - Règle NULL + exemples détaillés
- [WORKFLOW_COMPLET.md](../WORKFLOW_COMPLET.md) - Étape 5: Encoding PII

---

## 🎯 Résumé en 5 Points

1. **6 Types PII Couverts:** Email, Phone, First Name, Last Name, Address, IP
2. **NULL Préservé:** `WHERE IS NOT NULL` dans toutes les tables de référence
3. **Hash Cohérent:** Même valeur = même hash partout (customers, orders, etc.)
4. **LEFT JOIN Obligatoire:** Préserve les rows avec NULL
5. **Master Table:** `pii_master_reference` combine toutes les PII

**Règle d'or:** NULL entre, NULL sort - Pas de hash! ✅

---

## 🚀 Next Steps

1. **Run workflow complet:**
   ```bash
   cd ~/Documents/Projects/Dev_Ops
   python3 scripts/master_workflow.py
   ```

2. **Vérifier toutes les PII:**
   ```sql
   SELECT pii_field, COUNT(*) AS count
   FROM `hulken.ads_data.pii_master_reference`
   GROUP BY pii_field;
   ```

3. **Update tables unifiées** avec toutes les PII (pas juste email)

4. **Créer dashboards** montrant data completeness par PII type

**Tu as maintenant un système PII complet et cohérent! 🎉**

