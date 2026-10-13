# Dictionnaire de données — modèle « Parcours » data-driven

> Description champ par champ, avec un **exemple concret tiré de l'arbre EP – FUITE**. Objectif : comprendre à quoi sert chaque colonne (notamment `Type`, `CodePresta`, `ObjetCible` / `MappageChamps_JSON` de `Noeud__c`). Document de conception — rien n'est déployé.

> **La règle de traduction de l'arbre, en une phrase :**
> chaque **case / losange** du logigramme → 1 `Noeud__c` • chaque **flèche (réponse)** → 1 `Transition__c` • chaque **champ d'un écran de saisie** → 1 `ChampSaisie__c`.

## A. Objets de DÉFINITION (le parcours tel qu'il est écrit)

### Parcours__c — l'en-tête du logigramme

| Champ | Type SF | Description | Exemple (EP – FUITE) |
|---|---|---|---|
| `Code` | Text (unique) | Identifiant technique stable, utilisé pour l'import et le mapping. | EP_FUITE_PART |
| `Libelle` | Text | Nom lisible affiché aux utilisateurs. | PARCOURS_EP – FUITE CHEZ UN PARTICULIER |
| `Version` | Number | Versionnage : faire évoluer un parcours sans casser l'historique des exécutions. | 1 |
| `Statut` | Picklist | Brouillon / Actif / Archivé. Seuls les « Actif » sont proposés aux agents. | Actif |
| `Categorie` | Picklist | Regroupe les parcours pour la sélection / le filtrage. | Eau potable |
| `NoeudDepart_FK` | Lookup → Noeud__c | Le premier nœud exécuté au lancement. | N_ID (écran d'identification) |

### Noeud__c — une étape du parcours (le cœur du modèle)

| Champ | Type SF | Description | Exemple (EP – FUITE) |
|---|---|---|---|
| `Parcours_FK` | Lookup → Parcours__c | À quel parcours appartient l'étape. | EP_FUITE_PART |
| `Type` | Picklist | **Le champ structurant** : la <u>nature</u> de l'étape. Détermine comment le moteur la traite (voir encadré ci-dessous). | Question |
| `Texte` | Long text | Le contenu affiché : la question, le conseil, ou le libellé de l'action. | « Quelle est l'ampleur de la fuite ? » |
| `TypeAction` | Picklist *(si Type = Action)* | **Le verbe DML** : dit à la classe générique quoi faire sur `ObjetCible` — **Créer** (`insert`), **Mettre à jour** (`update`, requiert l'`Id` cible dans le JSON), **Supprimer** (`delete`, requiert l'`Id`), éventuellement **Upsert**. Ne sert **plus** à aiguiller vers une classe par type : une seule classe générique suffit. | Créer / Mettre à jour / Supprimer |
| `CodePresta` | Text *(optionnel / reporting)* | **Le code de prestation métier** (type de bon d'intervention). Conservé comme **libellé reportable** et référencé par le JSON via `{noeud.CodePresta}` (zéro duplication). Supprimable si le client ne reporte pas dessus → mettre la valeur en dur dans le JSON. | CET05 (compteur/robinet/joint)<br>BEC03 (canalisation) |
| `ObjetCible` | Text *(si Type = Action)* | **QUEL objet Salesforce créer** (nom d'API). Le nœud crée **un seul** record ; plusieurs records = **plusieurs nœuds Action enchaînés**. | Event / WorkOrder |
| `MappageChamps_JSON` | Long text *(si Type = Action)* | **QUELS champs renseigner** : couples *champ → valeur*. Valeurs fixes, **jetons** (`{client}`, `{case}`, `TODAY+3`, `{noeud.CodePresta}`) ou réponses fusionnées (`{ampleur}`), résolus à l'exécution par le handler générique. Englobe l'ancien `Delai` (via `TODAY+N`), `Parametres_JSON` et `TemplateCommentaire` (via `Subject`). | `{ "ActivityDate":"TODAY+3", "WhoId":"{client}" }` |
| `ParcoursCible_FK` | Lookup → Parcours__c *(si Type = Navigation)* | **Vers quel autre parcours débrancher**. Le moteur passe la main au `NoeudDepart_FK` de ce parcours (voir encadré « Navigation inter-parcours »). | EP – FUITE DOMAINE PUBLIC |

> **Les 5 valeurs de `Type` — ce que fait le moteur :**
>
> | Type | Comportement | Exemple EP |
> |---|---|---|
> | **Question** | Affiche un écran ; les **réponses = ses Transitions** (+ éventuels ChampSaisie). | N_AMPB « Ampleur ? » |
> | **Navigation** | Passe la main à un autre parcours via `ParcoursCible_FK` (voir encadré). | N_NAVDP → « Domaine public » |
> | **Conseil** | Écran d'information à lire au client, puis on continue. | N_CONS « Domaine privatif… » |
> | **Action** | Opère un **DML sur un record** (`insert` / `update` / `delete` selon `TypeAction`) via la **classe générique unique**. | N_BEC48, N_RVBEC48 |
> | **Fin** | Termine le parcours (clôt la Session). | N_FIN |

### Transition__c — une réponse possible (une flèche du logigramme)

| Champ | Type SF | Description | Exemple (EP – FUITE) |
|---|---|---|---|
| `NoeudSource_FK` | Lookup → Noeud__c | Le nœud d'où part la réponse. | N_AMPB |
| `Libelle_reponse` | Text | Le texte du choix proposé à l'agent (l'option du bouton radio). | « Filet d'eau / seau en qq heures » |
| `NoeudCible_FK` | Lookup → Noeud__c | Le nœud vers lequel on va si ce choix est retenu. | N_BO |
| `Ordre` | Number | Ordre d'affichage des choix sur l'écran. | 2 |

> **C'est ainsi que sont « générées » les réponses :** une question = ses Transitions sortantes. « Oui/Non » = 2 Transitions ; « Propriété / Rue » = 2 Transitions. Et **plusieurs Transitions peuvent viser le même `NoeudCible`** → c'est la factorisation (fan-in) : ex. N_EACCD(Oui), N_CO(Oui) et N_RVCET48 pointent tous vers N_CET48.

> **⚠️ `Transition__c` ≠ réponse donnée — ne pas confondre définition et exécution.** `Transition__c` sert **uniquement à définir** les réponses *possibles* d'un nœud Question : chaque transition sortante = **une option** proposée (son `Libelle_reponse` + sa cible `NoeudCible_FK`). Ces enregistrements sont **écrits une fois** avec le parcours, **partagés par toutes les exécutions** et **jamais modifiés au déroulé**. La **réponse réellement obtenue** lors d'un appel n'est **pas** stockée dans `Transition__c` : elle est enregistrée dans **`ReponseSaisie__c`** (objet d'exécution, section B), qui **pointe vers la transition choisie** via son lookup `Transition_FK`.
>
> | | `Transition__c` (DÉFINITION) | `ReponseSaisie__c` (EXÉCUTION) |
> |---|---|---|
> | **Rôle** | les réponses *possibles* d'une Question | la réponse *obtenue* à une étape |
> | **Écrit** | une fois, à la conception du parcours | à chaque réponse, pendant l'appel |
> | **Partagé** | par toutes les sessions | propre à **une** session (`Session_FK`) |
> | **Choix retenu** | — (c'est le catalogue) | `Transition_FK` = la transition choisie |
> | **Saisie libre** | — | `Valeur_libre` (champ d'un écran de saisie) |
>
> **En clair :** `Transition__c` = le *menu* des réponses ; `ReponseSaisie__c` = le *ticket* de ce qui a été effectivement choisi/saisi. Une Question à choix produit une `ReponseSaisie__c` dont `Transition_FK` désigne l'option retenue ; un écran de saisie (`ChampSaisie__c`) produit une `ReponseSaisie__c` dont `Valeur_libre` porte la valeur tapée (sans transition).

### ChampSaisie__c — un champ d'un écran de saisie

| Champ | Type SF | Description | Exemple (EP – FUITE) |
|---|---|---|---|
| `Noeud_FK` | Lookup → Noeud__c | L'écran (Noeud de type Question) qui porte ce champ. | N_ID |
| `Libelle` | Text | Intitulé du champ saisi. | Téléphone |
| `TypeChamp` | Picklist | Text / Phone / Email / Number / Date… → pilote le composant d'input. | Phone |
| `MappageCible` | Text (option.) | **Chemin** de recopie vers une fiche (optionnel). **Dernier segment = champ à écrire** ; **préfixe = record à atteindre** (racine = jeton de session `{client}`/`{case}`, ou type d'origine `Case.Account.…`). Vide → la valeur n'est que tracée dans `ReponseSaisie__c`. | `{client}.Phone` |
| `Ordre` | Number | Ordre d'affichage dans l'écran. | 4 |

> **`MappageCible` — comment une saisie met à jour une fiche :**
>
> | `MappageCible` | Record mis à jour | Champ |
> |---|---|---|
> | `{client}.Phone` | Person Account de la session | Phone |
> | `{client}.PersonEmail` | Person Account de la session | PersonEmail |
> | `{case}.Subject` | Case de la session | Subject |
> | `Case.Account.LastName` | Account du Case (via `Case.AccountId`) | LastName |
>
> **3 règles :** (1) le jeton `{client}` est résolu que le parcours parte d'un **Case** ou d'un **Account** → **une seule valeur** valable partout (préférez-le au chemin absolu `Case.Account.…`, lié à un seul point de lancement) ; (2) le moteur **regroupe** les champs visant le même record → **un seul `update`** par record ; (3) **Person Account** : viser `{client}.PersonEmail` / `{client}.PersonMobilePhone`, pas `Contact.*`. **État :** mapping déclaré dans la donnée, recopie activée quand le moteur joue l'étape (phase ultérieure) ; la trace `ReponseSaisie__c` est systématique.

> **Modèle B — créer plusieurs records = enchaîner plusieurs nœuds :** si un nœud doit créer **2 Events** (J+3 et J+9), on crée **2 nœuds Action** reliés par une transition (ex. `N_RVCETJ_1` → `N_RVCETJ_2`), chacun avec son `ObjetCible` = Event et son JSON (dont `ActivityDate:"TODAY+3"` / `"TODAY+9"`). Pas d'objet enfant `ModeleAction__c` : le moteur boucle déjà sur les nœuds. L'ancien `{ nbEvents: 2 }` cachait tout dans le code — ici tout est **dans la donnée, lisible et éditable**, un nœud = un record.

> **Navigation inter-parcours — « Aller à un autre parcours » :** un nœud de type **Navigation** porte `ParcoursCible_FK`. En l'atteignant, le moteur **passe la main** au `NoeudDepart_FK` du parcours visé (ex. domaine public « Dans votre propriété » → parcours « Fuite domaine privé » ; « Eau sale » → « Assainissement »).
>
> - **Traçabilité :** on ouvre une **sous-session** (`SessionParcours__c` enfant, `SessionParente_FK` = session courante, même `OrigineType`/`OrigineId`) → chaque parcours garde son journal, le lien parent↔enfant reconstitue le trajet complet.
> - **Transfert, pas sous-routine :** « Aller à X » ne revient pas → le parent se clôt. (`SessionParente_FK` permettrait un retour si besoin un jour.)
> - **Coût :** 1 lookup sur `Noeud__c` + 1 lookup d'audit sur `SessionParcours__c`, **aucun nouvel objet**.

### TypeAction__mdt — registre de handlers spéciaux (optionnel, non utilisé par défaut)

> **Non requis pour les parcours actuels.** Toute action = un DML (Créer / Mettre à jour / Supprimer) sur `ObjetCible` → **une seule classe générique** suffit (lit `TypeAction` + `ObjetCible` + `MappageChamps_JSON`, résout les jetons, exécute le DML). Ce registre ne devient utile que si, un jour, une action n'est **pas** un simple DML — une **logique spéciale** (callout vers un système externe, calcul de date ouvrée…) : on branche alors une classe dédiée via une **clé de routage propre** (champ dédié sur le nœud), **sans toucher** à `TypeAction` qui reste le verbe DML.

| Champ | Type SF | Description | Exemple |
|---|---|---|---|
| `Label` | Text | Clé de l'action spéciale (référencée par un champ de routage dédié du nœud). | CalloutPlanif |
| `ClasseApex` | Text | Classe Apex dédiée (logique **non**-DML : callout, calcul). | PlanifExterneHandler |
| `Actif` | Checkbox | Activer/désactiver un type sans le supprimer. | ✓ |

## B. Objets d'EXÉCUTION (ce qui se passe quand on déroule le parcours)

### SessionParcours__c — une exécution

| Champ | Type SF | Description | Exemple |
|---|---|---|---|
| `Parcours_FK` | Lookup → Parcours__c | Quel parcours est déroulé. | EP_FUITE_PART |
| `OrigineType` | Text | **Type** de l'objet depuis lequel on a lancé (générique). | Case |
| `OrigineId` | Text (18) | **Id** du record d'origine. | 500Ab000001XyZ… |
| `Account_FK_option / Case_FK_option` | Lookup (option.) | Lookups de confort pour le reporting natif (dérivés). | — |
| `NoeudCourant_FK` | Lookup → Noeud__c | Où en est l'agent (permet la reprise). | N_BO |
| `SessionParente_FK` | Lookup → Session *(option.)* | Si cette session a été ouverte par un nœud **Navigation** d'un autre parcours → trace le parcours appelant (audit du trajet complet). | (la session « domaine public ») |
| `Statut` | Picklist | En cours / Terminé / Abandonné. | En cours |
| `DateDebut / DateFin` | DateTime | Horodatage de l'exécution. | 09/10/2026 14:32 |
| `Agent_FK` | Lookup → User | Qui déroule le parcours. | j.martin |

### ReponseSaisie__c — chaque réponse donnée

| Champ | Type SF | Description | Exemple |
|---|---|---|---|
| `Session_FK` | Master-Detail → Session | À quelle exécution appartient la réponse. | (la session en cours) |
| `Noeud_FK` | Lookup → Noeud__c | Quelle question était posée. | N_AMPB |
| `Transition_FK` | Lookup → Transition__c | Quelle réponse a été choisie (question à choix). | « Filet d'eau… » |
| `Valeur_libre` | Text | La valeur saisie (pour un ChampSaisie / saisie libre). | 06 12 34 56 78 |
| `Horodatage` | DateTime | Quand la réponse a été donnée. | 14:33 |

> **Double nature de `ReponseSaisie__c` (voir l'encadré « Transition ≠ réponse » en section A) :** sur un nœud **Question**, `Transition_FK` est renseigné (la branche choisie, dont on relit le libellé via `Transition__c.Libelle_reponse`) et `Valeur_libre` reste vide ; sur un **écran de saisie** (`ChampSaisie__c`), c'est l'inverse — `Valeur_libre` porte la valeur tapée et `Transition_FK` est vide. C'est cette trace, ordonnée par `Horodatage`, que le visualiseur d'exécution rejoue pour reconstituer le chemin suivi.

### ActionExecutee__c — journal des actions DML (créations / mises à jour / suppressions)

| Champ | Type SF | Description | Exemple |
|---|---|---|---|
| `Session_FK` | Master-Detail → Session | À quelle exécution. | (la session en cours) |
| `Noeud_FK` | Lookup → Noeud__c | Le nœud d'action exécuté. | N_BEC48 |
| `TypeAction` | Text | Le **verbe DML** joué (Créer / Mettre à jour / Supprimer). | Créer |
| `RecordCreeId` | Text | Id du record visé (créé / mis à jour / supprimé). → sert à l'**idempotence**. | 0WOAb000000… |
| `Statut` | Picklist | OK / Erreur. | OK |
| `Message` | Long text | Détail ou message d'erreur éventuel. | WorkOrder BEC03 créé |

## C. Fil rouge : un appel réel traduit dans le modèle

> **Scénario :** Mme Dupont appelle. Fuite **dans sa propriété**, **eau propre**, à l'**intérieur**, **entre compteur et rue**, sur la **canalisation**, **filet d'eau**, **lieu non accessible**.

### Le chemin parcouru (lecture des records de définition)

```
N_ID → N_LOC → N_EAU → N_IE → N_INT → N_OU → N_AMPB → N_BO → N_RVBEC48 → N_BEC48 → N_FIN
```

| # | Noeud (lu) | Type | Réponse de l'agent (Transition suivie) |
|---|---|---|---|
| 1 | N_ID | Question (saisie) | Saisit nom, réf, adresse, tél, mail → *Continuer* |
| 2 | N_LOC | Question | « Dans votre propriété » → N_EAU |
| 3 | N_EAU | Question | « Eau propre » → N_IE |
| 4 | N_IE | Question | « Intérieur » → N_INT |
| 5 | N_INT | Question | « Entre compteur et rue » → N_OU |
| 6 | N_OU | Question | « Canalisation (depuis la rue) » → N_AMPB |
| 7 | N_AMPB | Question | « Filet d'eau / seau en qq heures » → N_BO |
| 8 | N_BO | Question | « Non » (lieu pas accessible) → N_RVBEC48 |
| 9 | N_RVBEC48 | Action · PriseRV | — (enchaîne) → N_BEC48 |
| 10 | N_BEC48 | Action · Intervention | — (enchaîne) → N_FIN |
| 11 | N_FIN | Fin | Clôture |

### Les records CRÉÉS pendant cette exécution

| Quand | Objet créé | Contenu |
|---|---|---|
| Au lancement (depuis le Case) | SessionParcours__c ×1 | Parcours = EP_FUITE_PART · OrigineType = Case · OrigineId = 500… · Statut = En cours |
| Étapes 1 à 8 | ReponseSaisie__c ×8 | une par réponse (dont les 6 champs de l'écran d'identification en `Valeur_libre`). Les 3 champs à `MappageCible` non vide (`{client}.Phone` / `PersonMobilePhone` / `PersonEmail`) mettent aussi à jour le Person Account — en **un seul `update`** — quand le moteur joue l'étape (phase ultérieure) |
| Étape 9 — N_RVBEC48<br>(handler générique) | Event + ActionExecutee__c | le nœud porte `ObjetCible = Event` + son JSON ; le handler résout les jetons et crée l'Event de RV lié au client · journal OK *(un RV à 2 dates = 2 nœuds Action enchaînés)* |
| Étape 10 — N_BEC48<br>(handler générique) | WorkOrder + ActionExecutee__c | le nœud porte `ObjetCible = WorkOrder` + son JSON : **WorkOrder BEC03**, Priority = <48h, Compte/Case = origine, Subject = « canalisation / filet d'eau / <48h » (fusion) · journal OK |
| Étape 11 — N_FIN | SessionParcours__c (maj) | Statut = Terminé · DateFin renseignée |

> **À retenir :** le même moteur a lu une poignée de records de **définition** et produit les records **métier** attendus (1 WorkOrder BEC03 <48h + le RV). Pour un autre parcours, **seuls les records changent** — le moteur et les handlers restent identiques.
