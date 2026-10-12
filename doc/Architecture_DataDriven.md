# Approche **data-driven** : 1 moteur + les parcours en données

> ℹ️ Document de **conception** (présales). Une **tranche verticale est désormais implémentée et déployée** sur un org de démonstration (modèle de données, moteur `parcoursRunner`, handler d'action générique, deux visualiseurs graphiques) — voir le [README §6](../README.md#6-état-dimplémentation) pour l'inventaire. Les choix décrits ci-dessous restent la référence d'architecture.
> Deux familles d'objets : **Définition** (le parcours tel qu'il est écrit) et **Exécution** (ce qui se passe quand un agent le déroule depuis un Account/Case).

## 1. Le changement de paradigme

```mermaid
flowchart LR
  subgraph AV["Approche « 1 flow par parcours »"]
    direction TB
    F1["Flow parcours 1"]:::ko
    F2["Flow parcours 2"]:::ko
    F3["… Flow parcours 100"]:::ko
  end
  subgraph AP["Approche data-driven"]
    direction TB
    M["1 MOTEUR générique"]:::ok
    D[("Données :<br/>100 parcours = records")]:::data
    H["Poignée de handlers d'action<br/>(écrits 1 fois)"]:::handler
    M --- D
    M --- H
  end
  AV -->|"ne scale pas :<br/>génération + maintenance ×100"| AP

  classDef ko fill:#FFD6D6,stroke:#c0392b,color:#000;
  classDef ok fill:#CDE9D6,stroke:#2E7D32,color:#000;
  classDef data fill:#D6E8FF,stroke:#0176d3,color:#000;
  classDef handler fill:#CDE9D6,stroke:#2E7D32,color:#000;
```

## 2. Modèle — DÉFINITION du parcours

```mermaid
erDiagram
  Parcours__c ||--o{ Noeud__c : "contient"
  Noeud__c ||--o{ Transition__c : "réponses possibles (source)"
  Noeud__c ||--o{ Transition__c : "cible de"
  Noeud__c ||--o{ ChampSaisie__c : "champs de saisie"
  Noeud__c }o--|| TypeAction__mdt : "résolu par (handler spécial)"
  Noeud__c }o--o| Parcours__c : "débranche vers (si Navigation)"

  Parcours__c {
    text Code
    text Libelle
    number Version
    picklist Statut
    picklist Categorie
    lookup NoeudDepart_FK
  }
  Noeud__c {
    lookup Parcours_FK
    picklist Type
    longtext Texte
    picklist TypeAction "optionnel"
    text CodePresta "optionnel / reporting"
    text ObjetCible "si Action"
    longtext MappageChamps_JSON "si Action"
    lookup ParcoursCible_FK "si Navigation"
  }
  Transition__c {
    lookup NoeudSource_FK
    text Libelle_reponse
    lookup NoeudCible_FK
    number Ordre
  }
  ChampSaisie__c {
    lookup Noeud_FK
    text Libelle
    picklist TypeChamp
    text MappageCible
    number Ordre
  }
  TypeAction__mdt {
    text Label
    text ClasseApex
    checkbox Actif
  }
```

> ℹ️ **ChampSaisie__c** (nouveau) couvre les écrans qui **collectent** sans brancher (ex. l'écran Identification : nom / tél / mail).
> `MappageCible` recopie la valeur saisie vers une fiche : **chemin** dont le **dernier segment = le champ** et le **préfixe = le record cible**, racine = jeton de session (`{client}.Phone`, `{client}.PersonEmail`, `{case}.Subject`) — résolu quelle que soit l'origine (Case ou Account), avec **un seul `update` par record**. Vide → la valeur n'est que tracée dans `ReponseSaisie__c`.
> Un nœud **Action** porte `TypeAction` (le **verbe DML** : Créer / Mettre à jour / Supprimer), `ObjetCible` (QUEL objet) + `MappageChamps_JSON` (QUELS champs ; pour Mettre à jour / Supprimer, le JSON porte l'`Id` cible via un jeton). Un nœud = **un seul record** ; une action qui touche plusieurs records = **plusieurs nœuds Action enchaînés** (voir §9). `Delai` et `Parametres_JSON` sont supprimés : la date/priorité vit désormais dans le JSON. `CodePresta` est conservé comme **libellé reportable** (optionnel).
> Un nœud **Navigation** porte `ParcoursCible_FK` (vers quel autre `Parcours__c` débrancher) — voir §7b.

## 3. Modèle — EXÉCUTION (les résultats) — origine GÉNÉRIQUE

```mermaid
erDiagram
  Parcours__c ||--o{ SessionParcours__c : "instancié par"
  SessionParcours__c ||--o{ ReponseSaisie__c : "trace des réponses"
  SessionParcours__c ||--o{ ActionExecutee__c : "journal des actions"
  Noeud__c ||--o{ ReponseSaisie__c : "question posée"
  Transition__c ||--o{ ReponseSaisie__c : "réponse choisie"

  SessionParcours__c {
    lookup Parcours_FK
    text OrigineType "ex. Account, Case, Asset"
    text OrigineId "Id 18 du record d'origine"
    lookup Account_FK_option "confort / reporting"
    lookup Case_FK_option "confort / reporting"
    lookup NoeudCourant_FK
    lookup SessionParente_FK "si sous-parcours"
    picklist Statut
    datetime DateDebut
    datetime DateFin
    lookup Agent_FK
  }
  ReponseSaisie__c {
    masterdetail Session_FK
    lookup Noeud_FK
    lookup Transition_FK
    text Valeur_libre
    datetime Horodatage
  }
  ActionExecutee__c {
    masterdetail Session_FK
    lookup Noeud_FK
    text TypeAction
    text RecordCreeId
    picklist Statut
    longtext Message
  }
```

| Objet | Rôle |
| --- | --- |
| `SessionParcours__c` | **Une exécution**. Origine **générique** : `OrigineType` + `OrigineId` (tout objet, **0 modif de schéma**). Lookups Account/Case = **confort** optionnel (reporting natif), pas la source de vérité. |
| `ReponseSaisie__c` | **Chaque réponse** donnée : quelle question, quelle transition choisie (ou valeur libre). → alimente le commentaire fusionné + l'analytics. |
| `ActionExecutee__c` | **Journal des créations** (WorkOrder, Events…) : Id du record créé, OK/Erreur. → audit + **idempotence** (ne pas recréer si retour arrière). |

> ✅ **Origine générique :** `OrigineType` + `OrigineId` permettent de lancer un parcours depuis **n'importe quel objet** sans ajouter de champ. Salesforce n'autorise pas de lookup polymorphe *custom* → c'est le pattern recommandé. Les lookups Account/Case ne sont ajoutés que si un **reporting natif** croisé le justifie (dérivés — ex. `Case.AccountId` donne le compte gratuitement). Compromis : pas d'intégrité référentielle ni de related list native → voir 3b.

### 3b. Related list générique — LWC « Parcours lancés »

> ℹ️ Sans lookup typé, on restitue l'historique sur **n'importe quelle** page (Account, Case, Asset…) via un composant qui lit les sessions par `OrigineId` — UX générique, 0 champ par objet.

```mermaid
flowchart LR
  RP["Page d'un record<br/>(Account / Case / Asset / …)"]:::data -->|"recordId"| LWC["LWC « Parcours lancés »<br/>SELECT … WHERE OrigineId = recordId"]:::engine
  LWC --> LIST["Liste des SessionParcours__c<br/>(statut · date · lien)"]:::record

  classDef data fill:#D6E8FF,stroke:#0176d3,color:#000;
  classDef engine fill:#EDEDED,stroke:#555,color:#000;
  classDef record fill:#B9D9F5,stroke:#0176d3,color:#000,stroke-width:2px;
```

## 4. Comment sont générées les réponses d'une question ?

> ℹ️ Les choix d'une question **SONT ses `Transition__c` sortantes**. Pas d'objet « réponse » séparé : le libellé affiché et le routage sont le **même** record. Le moteur affiche un radio dont les options = les `Libelle_reponse` triés par `Ordre`.

```mermaid
flowchart TD
  Q["Noeud__c « Où se trouve la fuite ? »<br/>Type = Question"]:::question
  Q -->|"Transition n°1 — Ordre 1<br/>Libellé = « Dans votre propriété »"| T1["Nœud cible :<br/>« Eau propre / eau sale ? »"]:::question
  Q -->|"Transition n°2 — Ordre 2<br/>Libellé = « Dans la rue / voie publique »"| T2["Nœud cible :<br/>Navigation domaine public"]:::navigation

  classDef question fill:#E2E8D5,stroke:#333,color:#000;
  classDef navigation fill:#C9C2DE,stroke:#333,color:#000;
```

> ℹ️ « Oui / Non » = 2 transitions. « Dans votre propriété / Dans la rue » = 2 transitions. Pour un écran de **saisie** (nom, tél…), ce ne sont pas des transitions mais des `ChampSaisie__c`.

## 5. Lancer un parcours depuis un Account / un Case

```mermaid
flowchart LR
  RP["Page Account / Case<br/>(Quick Action ou Utility bar)"]:::data -->|"recordId transmis"| ENG["Moteur<br/>(composant LWC générique)"]:::engine
  ENG -->|"crée"| S["SessionParcours__c<br/>OrigineType / OrigineId = origine<br/>Statut = En cours"]:::record
  ENG -->|"à la fin, records métier"| WO["WorkOrder / Events<br/>rattachés au client / au Case"]:::record
  S -.->|"related list : historique des parcours"| RP

  classDef data fill:#D6E8FF,stroke:#0176d3,color:#000;
  classDef engine fill:#EDEDED,stroke:#555,color:#000;
  classDef record fill:#B9D9F5,stroke:#0176d3,color:#000,stroke-width:2px;
```

> ℹ️ Le moteur est posé sur la **page Account/Case** et reçoit le `recordId` → il crée la `SessionParcours__c` liée. Les records créés en fin de parcours sont naturellement rattachés (WorkOrder → Case/Compte, Events → client). La **related list** donne l'historique des parcours sur la fiche.

## 6. Choisir le parcours à déclencher

```mermaid
flowchart TD
  START([Agent sur un Account / Case]):::startend --> MODE{Mode de sélection}:::question
  MODE -->|"Manuel"| L["Liste des Parcours actifs<br/>filtrable par Catégorie / mots-clés"]:::navigation
  MODE -->|"Automatique"| MAP["Mapping « Type de Case → Parcours »<br/>(Custom Metadata / règle)"]:::registry
  MODE -->|"Guidé"| AIG["Parcours d'aiguillage<br/>(1er parcours qui route vers les autres)"]:::question
  L --> GO[Lancer le parcours choisi]:::engine
  MAP --> GO
  AIG --> GO

  classDef startend fill:#333,stroke:#000,color:#fff;
  classDef question fill:#E2E8D5,stroke:#333,color:#000;
  classDef navigation fill:#C9C2DE,stroke:#333,color:#000;
  classDef registry fill:#E8D9FF,stroke:#6B4FA0,color:#000;
  classDef engine fill:#EDEDED,stroke:#555,color:#000;
```

> ℹ️ Trois leviers, combinables : **manuel** (liste filtrée par `Categorie__c`), **automatique** (ex. Case « Fuite » → parcours mappé), **guidé** (un parcours d'aiguillage qui pose le motif et navigue — cohérent avec le modèle : Navigation = transition inter-parcours).

## 7. Le moteur (un seul composant LWC générique)

```mermaid
flowchart TD
  A([Démarrage : Parcours + Session + client]):::startend --> B[Charger NoeudDepart]:::engine
  B --> C{Type du nœud courant ?}:::question
  C -->|Question| D[Afficher écran + réponses<br/>issues de Transition__c + ChampSaisie__c]:::question
  D --> E[Agent répond]:::engine
  E --> F[Créer ReponseSaisie__c]:::engine
  F --> Fb[Recopier ChampSaisie à MappageCible non vide<br/>vers la fiche · 1 update par record]:::engine
  Fb --> G[Nœud courant = Transition.NoeudCible]:::engine
  G --> C
  C -->|Action| H[Lire TypeAction + ObjetCible<br/>+ MappageChamps_JSON]:::engine
  H --> I[[Classe Apex générique : insert / update / delete<br/>+ ActionExecutee__c]]:::handler
  I --> J[Nœud courant = transition unique]:::engine
  J --> C
  C -->|Conseil| K[Afficher le conseil<br/>puis transition unique]:::navigation
  K --> C
  C -->|Navigation| NAV[Débrancher vers ParcoursCible_FK<br/>= NoeudDepart de l'autre parcours · voir §7b]:::navigation
  NAV --> C
  C -->|Fin| L([Clore la Session : Statut = Terminé]):::startend

  classDef startend fill:#333,stroke:#000,color:#fff;
  classDef engine fill:#EDEDED,stroke:#555,color:#000;
  classDef question fill:#E2E8D5,stroke:#333,color:#000;
  classDef navigation fill:#C9C2DE,stroke:#333,color:#000;
  classDef handler fill:#CDE9D6,stroke:#2E7D32,color:#000;
```

> ⚠️ Le moteur est **un seul composant LWC générique**, écrit **une seule fois** : il lit le nœud courant, affiche l'écran adapté (question + réponses issues de `Transition__c`, champs issus de `ChampSaisie__c`, conseil…), persiste la réponse via Apex, exécute les actions, puis avance au nœud suivant et se re-rend. On ne génère **plus jamais** un flow par parcours — et on échappe au mur de génération des gros flows rencontré précédemment. Les 100 parcours restent de la pure **donnée**. Le LWC peut, si besoin, être encapsulé dans un Flow pour le packaging admin, mais le rendu dynamique et la boucle sont portés par le LWC.

## 7b. Débrancher vers un autre parcours (nœud Navigation)

> ℹ️ Révélé par le 2ᵉ parcours (**EP – FUITE DOMAINE PUBLIC**) : « Dans votre propriété → **Aller à Fuite domaine privé** », « Eau sale → **Aller à Assainissement** ». Un nœud **Navigation** n'affiche rien : il **passe la main** à un autre parcours, désigné par `ParcoursCible_FK`. C'est une **donnée** (un lookup), pas du code — donc réutilisable par les 100 parcours sans rien générer.

```mermaid
flowchart LR
  N["Noeud__c (Navigation)<br/>ParcoursCible_FK = « EP – FUITE DOMAINE PUBLIC »"]:::navigation
  N -->|"le moteur lit ParcoursCible_FK"| JP["Parcours cible"]:::data
  JP -->|"NoeudDepart_FK"| ND["1er nœud du parcours cible<br/>(souvent l'écran d'identification)"]:::question
  N -.->|"ouvre une sous-session"| SS["SessionParcours__c (enfant)<br/>même OrigineType/OrigineId<br/>SessionParente_FK = session courante"]:::record
  SS -.->|"à la fin → reprend ou clôt le parent"| RET["Retour / clôture"]:::startend

  classDef navigation fill:#C9C2DE,stroke:#333,color:#000;
  classDef data fill:#D6E8FF,stroke:#0176d3,color:#000;
  classDef question fill:#E2E8D5,stroke:#333,color:#000;
  classDef record fill:#B9D9F5,stroke:#0176d3,color:#000,stroke-width:2px;
  classDef startend fill:#333,stroke:#000,color:#fff;
```

| Point | Comment ça marche |
| --- | --- |
| **Cible** | Le nœud Navigation porte `ParcoursCible_FK` → le moteur charge le `NoeudDepart_FK` du parcours visé et continue la boucle. Aucune transition sortante nécessaire (le débranchement remplace la suite). |
| **Traçabilité** | Recommandé : ouvrir une **sous-session** (`SessionParcours__c` enfant, `SessionParente_FK` = session courante, même `OrigineType`/`OrigineId`). Chaque parcours garde son propre journal de réponses et d'actions ; le lien parent↔enfant reconstitue le parcours complet du client. |
| **Hand-off vs retour** | Dans ces logigrammes, « Aller à X » est un **transfert** (on ne revient pas) → le parent se clôt quand l'enfant démarre. Si un jour un « retour » est voulu (sous-routine), `SessionParente_FK` permet déjà de reprendre le parent là où il s'était arrêté (`NoeudCourant_FK`). |
| **Boucles** | Garde-fou simple : interdire qu'un parcours se rappelle lui-même en chaîne (détection via la chaîne `SessionParente_FK`). |

> ✅ **C'est le seul vrai manque que le 2ᵉ parcours a révélé** — et il se comble par **1 lookup sur `Noeud__c`** (`ParcoursCible_FK`) + **1 lookup d'audit sur `SessionParcours__c`** (`SessionParente_FK`), sans nouvel objet. Bonus : la cible « domaine public » **existe désormais** (ce parcours), et l'écran d'identification est **mutualisé** entre parcours.

## 8. Une seule classe générique : « la donnée décrit, le code exécute »

```mermaid
flowchart LR
  N["Noeud__c (Action)<br/>TypeAction = Créer / Mettre à jour / Supprimer<br/>ObjetCible + MappageChamps_JSON"]:::action --> G["Classe générique UNIQUE<br/>résout les jetons · coerce les types<br/>switch TypeAction → insert / update / delete"]:::iface
  G --> DML["DML sur ObjetCible<br/>(Event, WorkOrder, Case…)"]:::record
  G -.->|journalise| LOG["ActionExecutee__c"]:::record

  OPT["Extension OPTIONNELLE — non utilisée aujourd'hui<br/>logique spéciale : callout / calcul"]:::registry -.->|registre TypeAction__mdt + classe dédiée| G

  classDef action fill:#9EFF4D,stroke:#333,color:#000;
  classDef iface fill:#E0F0F0,stroke:#2C7A7A,color:#000;
  classDef record fill:#D9E8FF,stroke:#2B5CA0,color:#000;
  classDef registry fill:#E8D9FF,stroke:#6B4FA0,color:#000;
```

> ℹ️ **Toute action = un DML sur un record.** Qu'il s'agisse d'un **Event** (RV) ou d'un **WorkOrder** (intervention), c'est **la même opération** : créer / mettre à jour / supprimer un `ObjetCible` avec les champs de `MappageChamps_JSON`. Donc **une seule classe générique** (plus de `PriseRVHandler` / `InterventionHandler` distincts) : elle lit `TypeAction` (le verbe DML), résout les jetons (`{client}`, `{case}`, `TODAY+N`, `{noeud.CodePresta}`), coerce les types et exécute l'`insert` / `update` / `delete` (voir §9), **sans code par parcours**. Le registre `TypeAction__mdt` + une classe dédiée ne deviennent utiles que si, un jour, une action n'est **pas** un simple DML (callout, calcul) — **aucun cas aujourd'hui**.

## 9. Les actions = création de records (exemple EP – FUITE)

> ℹ️ **Principe (déclaratif) :** un nœud **Action** ne contient **aucune logique en dur**. Il porte `ObjetCible` (quel objet) + `MappageChamps_JSON` (quels champs) et crée **un seul record**. Une action métier qui crée plusieurs records (ex. un RV = 2 Events) = **plusieurs nœuds Action enchaînés** par des transitions. Un **unique handler générique** résout les jetons (`{client}`, `{case}`, `TODAY+3`, `{ampleur}`, `{noeud.CodePresta}`) et insère — **aucun code par parcours**. Besoin de 2 Events ? → **2 nœuds**.

### 9a. « Prise de RV J+3–J+9 » → 2 Events (2 nœuds Action enchaînés)

```mermaid
flowchart LR
  N1["Noeud__c N_RVCETJ_1 (Action)<br/>ObjetCible = Event<br/>{ Subject:'RV visite 1',<br/>ActivityDate:'TODAY+3',<br/>WhoId:'{client}', WhatId:'{case}' }"]:::action
  N1 -->|Transition| N2["Noeud__c N_RVCETJ_2 (Action)<br/>ObjetCible = Event<br/>{ Subject:'RV visite 2',<br/>ActivityDate:'TODAY+9',<br/>WhoId:'{client}', WhatId:'{case}' }"]:::action
  N1 -.->|exécuté par| H["Handler générique<br/>(résout les jetons, insère)"]:::handler
  N2 -.->|exécuté par| H
  H --> E1["Event (J+3)"]:::record
  H --> E2["Event (J+9)"]:::record
  H --> LOG1["ActionExecutee__c<br/>(1 par création)"]:::journal
  N2 -->|Transition| SUITE["… N_CETJ (intervention)"]:::court48

  classDef action fill:#9EFF4D,stroke:#333,color:#000;
  classDef handler fill:#CDE9D6,stroke:#2E7D32,color:#000;
  classDef record fill:#B9D9F5,stroke:#0176d3,color:#000,stroke-width:2px;
  classDef journal fill:#F0F0F0,stroke:#777,color:#000;
  classDef court48 fill:#FFA500,stroke:#333,color:#000;
```

> ℹ️ **Compromis assumé (modèle B) :** une action « 2 Events » occupe 2 nœuds au lieu d'un seul → on perd le mapping 1 case du logigramme = 1 nœud, et l'atomicité de création (les 2 Events ne sont plus insérés dans la même transaction). Mitigé par `SessionParcours__c.NoeudCourant` (reprise) et `ActionExecutee__c` (idempotence). En échange : **zéro objet enfant**, le moteur boucle déjà sur les nœuds — aucune machinerie nouvelle.

### 9b. « Intervention CET05 <48h » → 1 Work Order (1 nœud Action)

```mermaid
flowchart LR
  N2["Noeud__c N_CET48 (Action)<br/>TypeAction = Intervention · CodePresta = CET05<br/>ObjetCible = WorkOrder<br/>{ WorkType:'{noeud.CodePresta}',<br/>Priority:'<48h',<br/>AccountId:'{client}', CaseId:'{case}',<br/>Subject:'{localisation} / {ampleur} / {urgence}' }"]:::court48
  N2 -.->|exécuté par| HINT["Handler générique"]:::handler
  HINT --> WO["WorkOrder<br/>WorkType = CET05 · Priority = <48h<br/>Compte / Case = origine<br/>Subject fusionné (depuis ReponseSaisie__c)"]:::record
  HINT --> LOG2["ActionExecutee__c"]:::journal

  classDef court48 fill:#FFA500,stroke:#333,color:#000;
  classDef handler fill:#CDE9D6,stroke:#2E7D32,color:#000;
  classDef record fill:#B9D9F5,stroke:#0176d3,color:#000,stroke-width:2px;
  classDef journal fill:#F0F0F0,stroke:#777,color:#000;
```

> ℹ️ **Pourquoi un handler, et pas un simple `insert` ?** Les valeurs du JSON sont des **jetons** (`TODAY+3`, `{client}`, `{noeud.CodePresta}`, `{ampleur}`), pas des valeurs natives — ils n'existent qu'à l'exécution. Un **résolveur générique** (écrit **une seule fois**) : (1) crée le SObject dynamiquement (`ObjetCible`), (2) résout chaque jeton, (3) **coerce** la String en type du champ (Date / Id / Number), puis (4) `insert` + `ActionExecutee__c`. Aucun code spécifique à un parcours. C'est aussi pourquoi un champ `Delai` séparé est inutile : le résolveur transforme déjà `TODAY+N` en date.
> **Gravité SLA (`Priority`) :** le 2ᵉ parcours (domaine public) utilise **3 niveaux** issus de la légende du logigramme — **Urgent** (rouge), **<48h** (orange), **J+2–J+7** (jaune). Ce sont **3 valeurs de la picklist `WorkOrder.Priority`**, portées par le JSON du nœud — aucune logique en dur, juste la bonne valeur par nœud Action.

> ⚠️ **Vigilance :** création au **bon moment** (confirmation agent) ; **idempotence** via `ActionExecutee__c` (ne pas recréer si l'agent revient en arrière) ; gestion d'erreur (échec → message, parcours non bloqué).

## 10. Visualisation : deux viewers graphiques (implémentés)

> ✅ **Implémenté.** La visualisation initialement envisagée (génération Apex → Mermaid) a été remplacée par **deux composants LWC** au rendu **SVG interactif**, qui lisent directement les records. Disposition en couches via la ressource statique **dagre** (repli BFS si indisponible), zoom et légende colorée par type de nœud. Même nature graphique pour les deux.

```mermaid
flowchart LR
  REC[("Records :<br/>Parcours / Noeud / Transition")]:::data -->|"ParcoursGraphController"| VGP["parcoursGraphViewer<br/>(page Parcours__c)<br/>graphe STATIQUE du parcours<br/>+ admin des nœuds"]:::navigation
  EXE[("Records :<br/>SessionParcours / ReponseSaisie")]:::data -->|"ParcoursSessionViewerController"| VSE["parcoursSessionViewer<br/>(page SessionParcours__c · onglet « Déroulé »)<br/>chemin EXÉCUTÉ : nœuds franchis,<br/>réponse choisie par arête, nœud courant"]:::action

  classDef data fill:#D6E8FF,stroke:#0176d3,color:#000;
  classDef navigation fill:#C9C2DE,stroke:#333,color:#000;
  classDef action fill:#9EFF4D,stroke:#333,color:#000;
```

| Viewer | Source lue | Ce qu'il montre |
| --- | --- | --- |
| **`parcoursGraphViewer`** (page `Parcours__c`) | `Noeud__c` + `Transition__c` du parcours | Le **graphe statique** complet du parcours (toutes les branches possibles), avec administration inline des nœuds. |
| **`parcoursSessionViewer`** (page `SessionParcours__c`, onglet **« Déroulé »**) | `ReponseSaisie__c` triées par `Horodatage__c` + `NoeudCourant_FK__c` | Le **chemin réellement suivi** par une exécution : nœuds franchis dans l'ordre, **réponse choisie** portée par chaque arête, **valeurs saisies** dans un panneau de détail, **nœud courant** surligné. Les arêtes reliant les nœuds consécutifs du chemin, un saut vers un sous-parcours apparaît naturellement. |

## 11. Trajectoire de migration (incrémentale, sans risque)

```mermaid
flowchart LR
  P1["Phase 1<br/>Placeholders<br/>(handler = affichage texte)"]:::placeholder --> P2["Phase 2<br/>PriseRV → Events"]:::action
  P2 --> P3["Phase 3<br/>Intervention → Work Order"]:::court48
  P3 --> P4["Phase 4<br/>Types d'action restants"]:::handler

  classDef placeholder fill:#DDDDDD,stroke:#333,color:#000,stroke-dasharray:4 3;
  classDef action fill:#9EFF4D,stroke:#333,color:#000;
  classDef court48 fill:#FFA500,stroke:#333,color:#000;
  classDef handler fill:#CDE9D6,stroke:#2E7D32,color:#000;
```
