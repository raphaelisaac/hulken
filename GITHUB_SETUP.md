# Configuration GitHub pour Dev_Ops

**Date:** 2026-02-13
**Objectif:** Créer un nouveau repo GitHub "hulken" et le configurer pour être réutilisable

---

## 🎯 Situation actuelle

- ✅ Dossier: `/Users/raphael_sebbah/Documents/Projects/Dev_Ops`
- ⚠️ Ancien remote: `devops131326/Hulken_better_signal` (cassé)
- 🎯 Nouveau repo: Votre GitHub personnel → `hulken`

---

## 📋 ÉTAPES COMPLÈTES

### 1. Créer le repo sur GitHub (dans le browser)

1. Aller sur https://github.com/new
2. Remplir:
   ```
   Repository name: hulken
   Description: Infrastructure de données pour analytics marketing (Airbyte, BigQuery, Python)
   Visibility: ✅ Public (réutilisable par d'autres)
            ou
            ❌ Private (si vous voulez garder privé)

   ❌ Ne PAS initialiser avec README (on a déjà tout)
   ❌ Ne PAS ajouter .gitignore (on a déjà)
   ❌ Ne PAS ajouter license
   ```
3. Cliquer **"Create repository"**

**Résultat:** Repo vide créé, GitHub vous montre les commandes à exécuter.

---

### 2. Nettoyer l'ancien remote (sur votre Mac)

```bash
cd /Users/raphael_sebbah/Documents/Projects/Dev_Ops

# Voir l'ancien remote
git remote -v

# Supprimer l'ancien remote
git remote remove origin

# Vérifier que c'est supprimé
git remote -v
# Devrait être vide
```

---

### 3. Ajouter le nouveau remote

**Remplacez `VOTRE_USERNAME` par votre nom d'utilisateur GitHub!**

```bash
cd /Users/raphael_sebbah/Documents/Projects/Dev_Ops

# Ajouter le nouveau remote
git remote add origin https://github.com/VOTRE_USERNAME/hulken.git

# Vérifier
git remote -v
# Devrait montrer: origin https://github.com/VOTRE_USERNAME/hulken.git
```

---

### 4. Commit les changements récents

```bash
cd /Users/raphael_sebbah/Documents/Projects/Dev_Ops

# Voir ce qui a changé
git status

# Ajouter tous les changements
git add .

# Commit avec message descriptif
git commit -m "Nettoyage et unification:
- Unifié 14 fichiers .md en COMPLETE_GUIDE.md
- Ajout table_monitoring.py (détection anomalies)
- Ajout create_unified_tables.sql (fusion sources)
- Archivé ancienne documentation
- Amélioration .gitignore"

# Vérifier que c'est commité
git status
# Devrait dire: nothing to commit, working tree clean
```

---

### 5. Push vers GitHub

```bash
cd /Users/raphael_sebbah/Documents/Projects/Dev_Ops

# Push (première fois, avec -u pour tracker la branche)
git push -u origin main

# Si erreur "main doesn't exist", essayer:
git branch -M main  # Renommer la branche en main
git push -u origin main
```

**Si demande login:**
- Username: Votre nom GitHub
- Password: **PAS votre mot de passe!** → Utiliser un **Personal Access Token**

**Comment créer un token:**
1. GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Generate new token (classic)
3. Donner un nom: "Dev_Ops push access"
4. Cocher: `repo` (full control)
5. Generate token
6. **COPIER LE TOKEN** (vous ne le reverrez plus!)
7. Utiliser ce token comme "password" quand git demande

---

### 6. Vérifier que ça marche

1. Aller sur https://github.com/VOTRE_USERNAME/hulken
2. Vous devriez voir tous vos fichiers:
   - COMPLETE_GUIDE.md
   - CHANGES.md
   - data_validation/
   - sql/
   - etc.

**⚠️ IMPORTANT:** Vérifier qu'il n'y a PAS de:
- Fichiers .env
- Credentials .json
- Mots de passe

Si vous en voyez → **URGENT:** Voir section "Supprimer credentials de l'historique" ci-dessous.

---

## 🔐 Sécurité: Vérifier qu'aucun credential n'est public

```bash
cd /Users/raphael_sebbah/Documents/Projects/Dev_Ops

# Lister tous les fichiers trackés
git ls-files

# Chercher les credentials
git ls-files | grep -E "\.(env|json)$"

# Si vous voyez des credentials → PAS BON!
```

**Si des credentials sont dans Git:**

```bash
# Supprimer du cache Git (garde le fichier local)
git rm --cached path/to/credential.json

# Commit
git commit -m "Remove credentials from tracking"

# Push
git push
```

---

## 🔄 Réutiliser Dev_Ops pour un autre projet

**Scénario:** Vous avez un nouveau client "ClientX" et voulez réutiliser Dev_Ops.

### Option A: Clone et renomme (RECOMMANDÉ)

```bash
cd /Users/raphael_sebbah/Documents/Projects

# Cloner le repo hulken
git clone https://github.com/VOTRE_USERNAME/hulken.git ClientX_DevOps

cd ClientX_DevOps

# Configurer pour le nouveau projet
./setup_new_project.sh
# Suivre les instructions (Project name, BigQuery project ID, etc.)
```

**Avantages:**
- ✅ Rapide (tout est déjà configuré)
- ✅ Garde hulken comme template
- ✅ Pas de risque de mélanger les projets

---

### Option B: Fork sur GitHub

1. Aller sur https://github.com/VOTRE_USERNAME/hulken
2. Cliquer **"Fork"**
3. Renommer le fork: `clientx-devops`
4. Cloner le fork localement

---

## 📝 Maintenir le repo à jour

### Après avoir fait des changements locaux:

```bash
cd /Users/raphael_sebbah/Documents/Projects/Dev_Ops

# 1. Voir ce qui a changé
git status

# 2. Ajouter les changements
git add .

# 3. Commit avec message clair
git commit -m "Description des changements"

# 4. Push vers GitHub
git push
```

### Si vous voulez récupérer les changements d'un autre ordinateur:

```bash
cd /Users/raphael_sebbah/Documents/Projects/Dev_Ops

# Pull les derniers changements
git pull
```

---

## 🚨 ERREURS FRÉQUENTES

### "Permission denied (publickey)"

**Solution:** Utiliser HTTPS au lieu de SSH

```bash
# Changer le remote en HTTPS
git remote set-url origin https://github.com/VOTRE_USERNAME/hulken.git
```

### "Updates were rejected"

**Cause:** GitHub a des commits que vous n'avez pas localement

**Solution:**
```bash
# Récupérer les changements distants
git pull --rebase origin main

# Puis push
git push
```

### "fatal: 'origin' does not appear to be a git repository"

**Cause:** Pas de remote configuré

**Solution:** Refaire l'étape 3 (ajouter le remote)

---

## ✅ CHECKLIST FINALE

Avant de considérer le setup terminé:

- [ ] Repo GitHub créé (public ou privé)
- [ ] Ancien remote supprimé (`git remote remove origin`)
- [ ] Nouveau remote ajouté (votre GitHub personnel)
- [ ] Changements commités localement
- [ ] Push réussi vers GitHub
- [ ] Vérifié sur GitHub: pas de credentials visibles
- [ ] Testé le clone sur un autre dossier (pour vérifier)
- [ ] README.md et COMPLETE_GUIDE.md sont visibles sur GitHub

---

## 📚 Structure finale

```
GitHub: VOTRE_USERNAME/hulken (repo principal, template)
  └── Clone → /Users/.../Projects/Dev_Ops (travail quotidien)
  └── Clone → /Users/.../Projects/ClientX_DevOps (autre projet)
  └── Clone → /Users/.../Projects/ClientY_DevOps (autre projet)
```

**Workflow:**
1. Faire des améliorations dans `Dev_Ops`
2. Commit et push vers `hulken` (GitHub)
3. Les autres projets peuvent pull les améliorations

---

## 🎉 TERMINÉ!

Une fois ces étapes complétées, vous avez:
- ✅ Un repo GitHub propre et réutilisable
- ✅ Aucun credential public
- ✅ Documentation complète (COMPLETE_GUIDE.md)
- ✅ Infrastructure portable pour d'autres projets

**Prochaine étape:** Partager le lien GitHub avec votre équipe ou l'utiliser comme template pour d'autres projets!

