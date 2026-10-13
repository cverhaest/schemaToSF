# CLAUDE.md — Projet « Parcours métiers »

Mémoire projet. Contexte, architecture, conventions et état d'avancement du moteur
de parcours *data-driven* sur Salesforce.

## Contrainte opérationnelle permanente — « source locale uniquement »

> **À respecter à chaque tour, sans exception.**

- **Aucun déploiement** vers un org **et aucun `git commit` / `git push`** sans
  **feu vert explicite de l'utilisateur, à chaque fois**. Un accord pour *un*
  déploiement n'autorise **pas** le suivant.
- L'utilisateur **gère lui-même** ses commits / pushes.
- **Autorisé sans demander** : créer / éditer des fichiers source **en local**.
- Un **dry-run** (check-only) est acceptable. Déployer sur un **sandbox / org de
  démo** avec `apexTestLevel: NoTestRun` est permis **une fois le feu vert donné**.
- **Gouvernance** : seules les règles de gouvernance **actuellement chargées**
  font foi. **Ne jamais inventer** de code de politique.

## Objectif métier

Service client : **~100 parcours métiers** (scripts guidés) que les conseillers
déroulent pendant un appel, lancés depuis une fiche **Compte** ou **Requête
(Case)**, pour guider pas à pas et **créer automatiquement** les enregistrements
métier (RV → Event, intervention → WorkOrder…). Application **générique** :
mêmes principes réutilisables par n'importe quel client, le métier vit dans la
donnée (parcours), pas dans le code.

## Principe d'architecture — « la donnée décrit, le code exécute »

- **Un parcours = des enregistrements** dans des objets custom génériques (sa
  logique est de la *donnée*, pas du code).
- **Un seul moteur générique** (LWC + Apex) interprète ces enregistrements au
  runtime et déroule le parcours.
- **Ajouter un parcours = ajouter des données** — aucun flow ni code par parcours,
  aucun déploiement par parcours.
- L'approche « 1 Screen Flow par parcours » a été **écartée** (ne passe pas à
  l'échelle sur 100 parcours).

## Modèle de données

**Définition** (écrit une fois, partagé par toutes les exécutions) :

| Objet | Rôle |
|---|---|
| `Parcours__c` | En-tête (code, libellé, catégorie, `NoeudDepart_FK`). |
| `Noeud__c` | Une étape. `Type` ∈ {Question, Navigation, Conseil, Action, Fin}. Pour Action : `TypeAction` (verbe DML Créer/MàJ/Supprimer), `ObjetCible`, `MappageChamps_JSON`. Pour Navigation : `ParcoursCible_FK`. |
| `Transition__c` | Une **réponse possible** d'un nœud Question (`NoeudSource_FK` → `NoeudCible_FK`, `Libelle_reponse`, `Ordre`). Graphe, pas liste ordonnée. Fan-in possible. |
| `ChampSaisie__c` | Un champ d'un écran de saisie (`TypeChamp`, `MappageCible` pour recopie vers une fiche via jetons `{client}`/`{case}`). |

**Exécution** (créé pendant l'appel) :

| Objet | Rôle |
|---|---|
| `SessionParcours__c` | Une exécution (`OrigineType`/`OrigineId` génériques, `NoeudCourant_FK` pour reprise, `SessionParente_FK` pour saut inter-parcours, `Statut`, dates, `Agent_FK`). |
| `ReponseSaisie__c` | **Chaque réponse obtenue** (`Noeud_FK`, `Transition_FK` = branche choisie, `Valeur_libre` = saisie libre, `Horodatage`). |
| `ActionExecutee__c` | Journal des DML (`TypeAction`, `RecordCreeId` pour idempotence, `Statut`, `Message`). |

### ⚠️ `Transition__c` ≠ `ReponseSaisie__c` (ne pas confondre)

- `Transition__c` = **DÉFINITION** : le *menu* des réponses possibles. Écrit une
  fois, partagé par toutes les sessions, **jamais modifié au déroulé**.
- `ReponseSaisie__c` = **EXÉCUTION** : le *ticket* de ce qui a été choisi/saisi.
  Un pour une session. Nœud Question → `Transition_FK` renseigné ; écran de
  saisie → `Valeur_libre` renseigné.

## Composants implémentés

**Apex** (chaque contrôleur a sa classe `*Test`) :

| Classe | Rôle |
|---|---|
| `ParcoursRunnerController` | Moteur : charge le nœud courant, persiste les réponses, avance (dont saut inter-parcours), clôture. |
| `ParcoursActionHandler` | Handler **générique** des nœuds Action (DML décrit par la donnée + journalisation). |
| `ParcoursGraphController` | Expose le **graphe statique** d'un parcours au visualiseur. |
| `ParcoursSessionViewerController` | Reconstruit le **chemin exécuté** d'une session depuis `ReponseSaisie__c` (ORDER BY `Horodatage__c`), `WITH USER_MODE`. DTOs : SessionPathDTO/StepDTO/EdgeDTO. |
| `TestDataFactory` | Fabrique de données de test partagée. |

**LWC** :

| Composant | Page | Rôle |
|---|---|---|
| `parcoursRunner` | Account / Case | Moteur générique, déroule le parcours pas à pas. |
| `parcoursGraphViewer` | `Parcours__c` | Visualiseur du graphe statique + admin des nœuds. |
| `parcoursSessionViewer` | `SessionParcours__c` | Visualiseur d'exécution (read-only) : rejoue le chemin suivi, réponse choisie sur chaque arête, nœud courant surligné, panneau de détail d'étape. |

**Visualiseurs — nature graphique commune** : disposition en couches via **dagre**
(ressource statique `dagre`, UMD `window.dagre`, chargée via `loadScript`), rendu
**SVG** (`polyline` arêtes + polygone-flèche + label au milieu), **repli BFS** si
dagre indisponible (c'est le cas sous sfdx-lwc-jest qui auto-mocke
platformResourceLoader). Zoom + légende par type de nœud. Le « Mermaid à la
demande » envisagé initialement a été **remplacé** par ce rendu SVG interactif.

**Intégration FlexiPage** : `Session_Record_Page` (`SessionParcours__c`) a un
onglet **« Déroulé »** dans le tabset principal (`maintabs`), hébergeant
`parcoursSessionViewer` via un facet `Facet-ParcoursSessionViewer`. Le `recordId`
est injecté automatiquement (aucune `componentInstanceProperty` nécessaire sur une
page d'enregistrement).

## Conventions projet

- Salesforce DX, **API 67.0**, **sans namespace**, source dans
  `force-app/main/default/`.
- **Skill-first** : charger la skill pertinente (ex. `platform-flexipage-generate`,
  `platform-apex-generate`) **avant** de générer de la métadonnée.
- Déploiement : `mcp__salesforce_dx__deploy_metadata` avec
  `apexTestLevel: NoTestRun` ; org résolu via `mcp__salesforce_dx__get_username`.
- Documentation :
  - `README.md` — vue d'ensemble + §6 « État d'implémentation ».
  - `doc/Architecture_DataDriven.md` — architecture (commencer par là).
  - `doc/Dictionnaire_Donnees_Parcours.md` — dictionnaire champ par champ (contient
    l'encadré « Transition ≠ réponse »).
  - `doc/EP_Fuite_Particulier_RECORDS.md` — exemple complet en enregistrements.
  - `interpretation/` — logigrammes Mermaid ; `schema/` — schémas d'origine.
  - **Ne pas surjouer l'état** : inventorier le contenu réel de `force-app/` avant
    de documenter « déployé / implémenté ».

## Suite / en attente (feu vert requis pour déployer ou committer)

- Correctif du **saut Navigation** dans `parcoursRunner` : dans `isNavigationJump`
  retirer `!this.hasTransitions` ; ajouter `showBranching` / `showNext` pour qu'un
  nœud Navigation n'affiche que le bouton de saut. Branche correspondante déjà
  éditée en local dans `ParcoursRunnerController.cls`.
- **Câbler les actions métier réelles** via `ParcoursActionHandler` (RV → Events,
  intervention → WorkOrder).
- Lancer le **code analyzer** et les **tests Jest** (Jest nécessite `npm install`).
- **Industrialiser** : import des autres parcours (pure donnée).
