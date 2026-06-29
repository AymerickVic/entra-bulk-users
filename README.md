# New-BulkEntraUsers

Script PowerShell de création en masse d'utilisateurs Microsoft Entra ID à partir d'un fichier CSV, via Microsoft Graph. Conçu pour gérer les erreurs proprement : une ligne qui échoue n'arrête pas le traitement, et toutes les erreurs sont consignées dans un rapport exploitable.

## Pourquoi ce script

Créer 300+ comptes à la main dans le portail Entra n'est pas tenable. Un import CSV brut, lui, s'arrête à la première erreur (doublon, champ manquant) et laisse l'admin sans visibilité sur ce qui a réellement été créé. Ce script vise les deux : automatiser la création **et** garder une trace fiable des échecs.

## Fonctionnalités

- Lecture d'un CSV (une ligne = un utilisateur)
- Création via `New-MgUser` avec mot de passe temporaire forcé au premier login
- Gestion d'erreur ligne par ligne : le script continue malgré les échecs
- Rapport CSV des échecs (UPN, nom, raison), encodé UTF-8 et séparé par `;` pour s'ouvrir directement dans Excel
- Tenant cible explicite (paramètre obligatoire) pour éviter les connexions dans le mauvais contexte

## Prérequis

- PowerShell 7 ou supérieur
- Module `Microsoft.Graph`
  ```powershell
  Install-Module Microsoft.Graph -Scope CurrentUser
  ```
- Un compte avec la permission Graph `User.ReadWrite.All` sur le tenant cible

## Format du CSV

| Colonne | Exemple |
|---|---|
| DisplayName | Thomas Martin |
| MailNickname | thomas.martin |
| UserPrincipalName | thomas.martin@contoso.onmicrosoft.com |
| Department | IT |
| JobTitle | Technicien |

Un fichier `users_exemple.csv` est fourni.

## Utilisation

```powershell
./New-BulkEntraUsers.ps1 -CsvPath ./users_exemple.csv -TenantId contoso.onmicrosoft.com
```

Une fenêtre de connexion s'ouvre : authentifiez-vous avec un compte admin du tenant.

Paramètre optionnel `-ReportPath` pour choisir l'emplacement du rapport (défaut : `./echecs_creation.csv`).

## Le rapport d'échecs

Généré uniquement s'il y a au moins un échec. Exemple :

| UserPrincipalName | Nom | Raison |
|---|---|---|
| thomas.martin@contoso.onmicrosoft.com | Thomas Martin | Another object with the same value for property userPrincipalName already exists. |
| paul.durand@contoso.onmicrosoft.com | | Invalid value specified for property 'displayName' of resource 'User'. |

L'UPN est consigné en plus du nom : si `DisplayName` est vide (et provoque justement l'erreur), la ligne reste identifiable.

## Troubleshooting : l'erreur 405 MethodNotAllowed

Pendant les tests, toutes les créations échouaient avec `Status: 405 (MethodNotAllowed)` et `ErrorCode: UnknownError`, message vide. Démarche de diagnostic :

1. `$_.Exception.Message` renvoyait du vide. Le détail réel se trouvait dans `$_.ErrorDetails.Message`, qui révélait le code HTTP 405.
2. Un 405 signifie que la requête atteint l'API mais que la méthode n'est pas autorisée sur la ressource. Ce n'était donc ni le CSV, ni les permissions (qui renverraient 401/403).
3. `Invoke-MgGraphRequest -Uri /me` montrait un UPN en `...#EXT#@...` : le compte admin était un **invité (compte Microsoft personnel)** dans le tenant.
4. Cause racine : `Connect-MgGraph` sans `-TenantId` authentifiait le compte personnel dans **son propre contexte**, où la création d'utilisateur n'est pas supportée.

Correctif : forcer `-TenantId` sur la connexion. C'est pourquoi le paramètre est obligatoire dans ce script.

Références : [Microsoft Q&A — 405 MethodNotAllowed](https://learn.microsoft.com/en-us/answers/questions/2155900/update-mguser-throws-405-methodnotallowed), [New-MgUser (compte personnel non supporté)](https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.users/new-mguser).

## Limites connues

- Le séparateur `;` du rapport est adapté à Excel en configuration française. En Excel anglophone, remplacer par `-Delimiter ","` ou `-UseCulture`.
- Pas d'attribution de licence ni d'ajout à des groupes (hors périmètre actuel).

## Licence

MIT
