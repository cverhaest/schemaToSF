# `PARCOURS_EP – FUITE CHEZ UN PARTICULIER` — saisi en **records**

> Démonstration **conception** (rien n'est déployé) : le logigramme **factorisé** traduit dans les objets du modèle data-driven.
> Les clés `N_XXX` reprennent les identifiants des étapes du logigramme [`interpretation/EP_Fuite_Particulier_interpretation.md`](../interpretation/EP_Fuite_Particulier_interpretation.md) pour recoupement direct (nœuds répétés fusionnés, comme dans le modèle data-driven).
> À l'exécution, ces records sont lus par le **composant LWC générique unique** (le « moteur » décrit dans [`Architecture_DataDriven.md`](Architecture_DataDriven.md) §7) — le **même** pour les 100 parcours : ni flow ni code spécifiques à ce parcours.

| | | | |
|---|---|---|---|
| **1** Parcours__c | **36** Noeud__c | **53** Transition__c | **6** ChampSaisie__c |

> **Comment le moteur (LWC générique) sait par où commencer et où aller ?**
> - **Premier nœud** : donné explicitement par `Parcours__c.NoeudDepart_FK` (ici N_ID). Il n'y a **aucun « numéro d'ordre »** sur les nœuds.
> - **Suite & bifurcations** : l'ordre n'est pas stocké, il **émerge** en suivant les `Transition__c` (c'est un **graphe**, pas une liste). Un nœud à **1 transition sortante** = on enchaîne tout droit (N_ID → N_LOC). Un nœud à **plusieurs transitions sortantes** = une bifurcation : chaque réponse de l'agent choisit sa cible (N_LOC : « Dans votre propriété » → N_EAU, « Dans la rue » → N_NAVDP).
> - `Ordre` ne décide **pas** où l'on va — il ne fait que **trier l'affichage** des choix à l'écran. C'est la **réponse** (= la transition suivie) qui décide de la cible.
> - **Actions** : même règle. L'ordre des créations = l'ordre des nœuds Action dans la chaîne. Ex. le RV J+3–J+9 = N_RVCETJ_1 → N_RVCETJ_2 : l'Event J+3 est créé avant le J+9 **parce que** son nœud précède l'autre.

## 1. Parcours__c (1 record)

| Réf | Code | Libelle | Version | Statut | Categorie | NoeudDepart_FK |
|---|---|---|---|---|---|---|
| P_EP_FUITE | EP_FUITE_PART | PARCOURS_EP – FUITE CHEZ UN PARTICULIER | 1 | Actif | Eau potable | N_ID |

## 2. ChampSaisie__c — écran d'identification (N_ID)

| Réf | Noeud_FK | Libelle | TypeChamp | MappageCible (option.) | Ordre |
|---|---|---|---|---|---|
| CS1 | N_ID | Nom (rappel) | Text | — | 1 |
| CS2 | N_ID | Référence client | Text | contrôle contrat | 2 |
| CS3 | N_ID | Adresse concernée | Text | contrôle contrat | 3 |
| CS4 | N_ID | Téléphone | Phone | `{client}.Phone` | 4 |
| CS5 | N_ID | Portable | Phone | `{client}.PersonMobilePhone` | 5 |
| CS6 | N_ID | Mail | Email | `{client}.PersonEmail` | 6 |

> **Sémantique de `MappageCible` (recopie vers une fiche) :** un chemin dont le **dernier segment = le champ à écrire** et le **préfixe = le record à atteindre** (racine = un jeton de session `{client}` / `{case}`, ou le type d'origine `Case.Account.…`).
>
> - `{client}.Phone` → met à jour le champ `Phone` du Person Account de la session.
> - Le jeton `{client}` est résolu que le parcours démarre d'un **Case** (via `Case.AccountId`) ou d'un **Account** → **une seule valeur** valable partout.
> - Le moteur **regroupe** tous les ChampSaisie visant le même record → **un seul `update`** par record (gouverneurs + cohérence).
> - **Person Account :** on écrit `{client}.PersonEmail` / `{client}.PersonMobilePhone` (champs « personne » de l'Account), **pas** `Contact.*` qui n'est pas adressable ainsi.
> - « contrôle contrat » (CS2/CS3) et — (CS1) = aucune recopie : saisie de vérification, uniquement tracée dans `ReponseSaisie__c`.
>
> **État actuel :** ces mappings sont **déclarés dans la donnée** ; la recopie est activée quand le moteur implémente l'étape « ChampSaisie à MappageCible non vide → `put` + `update` » (phase ultérieure). La trace dans `ReponseSaisie__c`, elle, est systématique.

## 3. Noeud__c (36 records)

| Réf | Type | Texte / libellé | TypeAction | CodePresta | ObjetCible |
|---|---|---|---|---|---|
| N_ID | Question (saisie) | Identification — voir ChampSaisie | — | — | — |
| N_LOC | Question | Où se trouve la fuite ? | — | — | — |
| N_EAU | Question | Eau propre ou eau sale ? | — | — | — |
| N_IE | Question | À l'intérieur ou à l'extérieur ? (+ appart/maison, informatif) | — | — | — |
| N_FOSSE | Question | Compteur dans une fosse (regard) ? La fosse déborde-t-elle ? | — | — | — |
| N_EACCD | Question | Lieu accessible à toute heure (sans votre présence) ? | — | — | — |
| N_EACCN | Question | Lieu accessible à toute heure (sans votre présence) ? | — | — | — |
| N_INT | Question | Fuite entre compteur et rue, ou entre compteur et habitation ? | — | — | — |
| N_OU | Question | Où est située précisément la fuite ? | — | — | — |
| N_AMPC | Question | Ampleur de la fuite ? (temps pour remplir un seau) — CET05 | — | — | — |
| N_AMPB | Question | Ampleur de la fuite ? (temps pour remplir un seau) — BEC03 | — | — | — |
| N_CY | Question | Lieu accessible ? | — | — | — |
| N_CO | Question | Lieu accessible ? | — | — | — |
| N_CR | Question | Lieu accessible ? | — | — | — |
| N_BY | Question | Lieu accessible ? | — | — | — |
| N_BO | Question | Lieu accessible ? | — | — | — |
| N_BR | Question | Lieu accessible ? | — | — | — |
| N_NAVDP | Navigation | Débranche vers « EP – FUITE DOMAINE PUBLIC » · `ParcoursCible_FK` → parcours 19 | — | — | — |
| N_NAVAS | Navigation | Débranche vers « Assainissement » · `ParcoursCible_FK` (parcours à venir) | — | — | — |
| N_CONS | Conseil | Domaine privatif ; resp. exploitant entre rue et compteur ; voir un pro ; fermer le robinet avant compteur | — | — | — |
| N_RVCET48 | Action | Prise de RV (<48h) | Créer | — | Event |
| N_RVCETJ_1 | Action | Prise de RV — 1re visite (J+3) | Créer | — | Event |
| N_RVCETJ_2 | Action | Prise de RV — 2e visite (J+9) | Créer | — | Event |
| N_RVCETU | Action | Prise de RV immédiate | Créer | — | Event |
| N_RVBEC48 | Action | Prise de RV (<48h) | Créer | — | Event |
| N_RVBECJ_1 | Action | Prise de RV — 1re visite (J+3) | Créer | — | Event |
| N_RVBECJ_2 | Action | Prise de RV — 2e visite (J+9) | Créer | — | Event |
| N_RVBECU | Action | Prise de RV immédiate | Créer | — | Event |
| N_CET48 | Action | Intervention CET05 <48h | Créer | CET05 | WorkOrder |
| N_CETJ | Action | Intervention CET05 J+2–J+7 | Créer | CET05 | WorkOrder |
| N_CETU | Action | Intervention CET05 URGENTE | Créer | CET05 | WorkOrder |
| N_BEC48 | Action | Intervention BEC03 <48h | Créer | BEC03 | WorkOrder |
| N_BECJ | Action | Intervention BEC03 J+2–J+7 | Créer | BEC03 | WorkOrder |
| N_BECU | Action | Intervention BEC03 URGENTE | Créer | BEC03 | WorkOrder |
| N_FIN | Fin | Fin du parcours | — | — | — |
| N_FINHS | Fin | Fin — hors schéma (routage à définir) | — | — | — |

> **Modèle B :** chaque nœud Action crée **un seul** record (`ObjetCible`) ; le détail des champs est dans `MappageChamps_JSON` (§3b). Le RV « J+3–J+9 » = **2 Events** → **2 nœuds enchaînés** (N_RVCETJ_1 → N_RVCETJ_2 et N_RVBECJ_1 → N_RVBECJ_2). Plus d'objet `ModeleAction__c`, plus de champ `Delai` ni de `Parametres_JSON = { nbEvents: 2 }` : la date vit dans le JSON (`ActivityDate:'TODAY+N'`).

## 3b. MappageChamps_JSON des nœuds Action — « quels champs créer »

| Réf | ObjetCible | MappageChamps_JSON |
|---|---|---|
| N_RVCET48 | Event | `{ Subject:'RV CET05 (<48h)', ActivityDate:'TODAY+2', WhoId:'{client}', WhatId:'{case}' }` |
| N_RVCETJ_1 | Event | `{ Subject:'RV CET05 — visite 1', ActivityDate:'TODAY+3', WhoId:'{client}', WhatId:'{case}' }` |
| N_RVCETJ_2 | Event | `{ Subject:'RV CET05 — visite 2', ActivityDate:'TODAY+9', WhoId:'{client}', WhatId:'{case}' }` |
| N_RVCETU | Event | `{ Subject:'RV CET05 (immédiat)', ActivityDate:'TODAY', WhoId:'{client}', WhatId:'{case}' }` |
| N_RVBEC48 | Event | `{ Subject:'RV BEC03 (<48h)', ActivityDate:'TODAY+2', WhoId:'{client}', WhatId:'{case}' }` |
| N_RVBECJ_1 | Event | `{ Subject:'RV BEC03 — visite 1', ActivityDate:'TODAY+3', WhoId:'{client}', WhatId:'{case}' }` |
| N_RVBECJ_2 | Event | `{ Subject:'RV BEC03 — visite 2', ActivityDate:'TODAY+9', WhoId:'{client}', WhatId:'{case}' }` |
| N_RVBECU | Event | `{ Subject:'RV BEC03 (immédiat)', ActivityDate:'TODAY', WhoId:'{client}', WhatId:'{case}' }` |
| N_CET48 | WorkOrder | `{ WorkType:'{noeud.CodePresta}', Priority:'<48h', AccountId:'{client}', CaseId:'{case}', Subject:'{localisation} / {ampleur} / {urgence}' }` |
| N_CETJ | WorkOrder | `{ WorkType:'{noeud.CodePresta}', Priority:'J+2–J+7', AccountId:'{client}', CaseId:'{case}', Subject:'{localisation} / {ampleur} / {urgence}' }` |
| N_CETU | WorkOrder | `{ WorkType:'{noeud.CodePresta}', Priority:'Urgent', AccountId:'{client}', CaseId:'{case}', Subject:'{localisation} / {ampleur} / {urgence}' }` |
| N_BEC48 | WorkOrder | `{ WorkType:'{noeud.CodePresta}', Priority:'<48h', AccountId:'{client}', CaseId:'{case}', Subject:'{localisation} / {ampleur} / {urgence}' }` |
| N_BECJ | WorkOrder | `{ WorkType:'{noeud.CodePresta}', Priority:'J+2–J+7', AccountId:'{client}', CaseId:'{case}', Subject:'{localisation} / {ampleur} / {urgence}' }` |
| N_BECU | WorkOrder | `{ WorkType:'{noeud.CodePresta}', Priority:'Urgent', AccountId:'{client}', CaseId:'{case}', Subject:'{localisation} / {ampleur} / {urgence}' }` |

> **Jetons résolus à l'exécution** par le handler générique : `{client}`/`{case}` (origine de la Session), `TODAY+N` (date calculée), `{noeud.CodePresta}` (le code porté par le nœud → `WorkType`), `{localisation}`/`{ampleur}`/`{urgence}` (réponses fusionnées depuis `ReponseSaisie__c` → l'ancien `TemplateCommentaire`). `Priority` reprend le libellé SLA du logigramme (<48h · J+2–J+7 · Urgent), mappé sur `WorkOrder.Priority`.

## 4. Transition__c (53 records) — les « réponses » de chaque question

| Réf source | Libelle_reponse | Cible | Ordre |
|---|---|---|---|
| N_ID | Continuer | N_LOC | 1 |
| N_LOC | Dans votre propriété | N_EAU | 1 |
| N_LOC | Dans la rue / voie publique | N_NAVDP | 2 |
| N_EAU | Eau propre | N_IE | 1 |
| N_EAU | Eau sale (couleur / odeur) | N_NAVAS | 2 |
| N_IE | Extérieur | N_FOSSE | 1 |
| N_IE | Intérieur | N_INT | 2 |
| N_FOSSE | Oui, la fosse déborde | N_EACCD | 1 |
| N_FOSSE | Oui, ne déborde pas | N_EACCN | 2 |
| N_FOSSE | Non, pas dans une fosse | N_FINHS | 3 |
| N_EACCD *(fan-in)* | Oui | N_CET48 | 1 |
| N_EACCD | Non | N_RVCET48 | 2 |
| N_EACCN *(fan-in)* | Oui | N_CETJ | 1 |
| N_EACCN | Non | N_RVCETJ_1 | 2 |
| N_INT | Entre compteur et rue | N_OU | 1 |
| N_INT | Entre compteur et habitation | N_CONS | 2 |
| N_OU | Compteur / robinet / joint | N_AMPC | 1 |
| N_OU | Canalisation (depuis la rue) | N_AMPB | 2 |
| N_AMPC | Goutte à goutte / seau en 1 j | N_CY | 1 |
| N_AMPC | Filet d'eau / seau en qq heures | N_CO | 2 |
| N_AMPC | Seau en qq minutes / inondation | N_CR | 3 |
| N_AMPB | Goutte à goutte / seau en 1 j | N_BY | 1 |
| N_AMPB | Filet d'eau / seau en qq heures | N_BO | 2 |
| N_AMPB | Seau en qq minutes / inondation | N_BR | 3 |
| N_CY *(fan-in)* | Oui | N_CETJ | 1 |
| N_CY | Non | N_RVCETJ_1 | 2 |
| N_CO *(fan-in)* | Oui | N_CET48 | 1 |
| N_CO | Non | N_RVCET48 | 2 |
| N_CR *(fan-in)* | Oui | N_CETU | 1 |
| N_CR | Non | N_RVCETU | 2 |
| N_BY *(fan-in)* | Oui | N_BECJ | 1 |
| N_BY | Non | N_RVBECJ_1 | 2 |
| N_BO *(fan-in)* | Oui | N_BEC48 | 1 |
| N_BO | Non | N_RVBEC48 | 2 |
| N_BR *(fan-in)* | Oui | N_BECU | 1 |
| N_BR | Non | N_RVBECU | 2 |
| N_NAVDP | ➡️ Aller au parcours « Domaine public » | N_FIN | 1 |
| N_NAVAS | ➡️ Aller au parcours « Assainissement » | N_FIN | 1 |
| N_CONS | Fin de l'appel | N_FIN | 1 |
| N_RVCET48 *(fan-in)* | (après prise de RV) | N_CET48 | 1 |
| N_RVCETJ_1 | (enchaîne — 2e visite) | N_RVCETJ_2 | 1 |
| N_RVCETJ_2 *(fan-in)* | (après prise de RV) | N_CETJ | 1 |
| N_RVCETU *(fan-in)* | (après prise de RV) | N_CETU | 1 |
| N_RVBEC48 *(fan-in)* | (après prise de RV) | N_BEC48 | 1 |
| N_RVBECJ_1 | (enchaîne — 2e visite) | N_RVBECJ_2 | 1 |
| N_RVBECJ_2 *(fan-in)* | (après prise de RV) | N_BECJ | 1 |
| N_RVBECU *(fan-in)* | (après prise de RV) | N_BECU | 1 |
| N_CET48 | (fin) | N_FIN | 1 |
| N_CETJ | (fin) | N_FIN | 1 |
| N_CETU | (fin) | N_FIN | 1 |
| N_BEC48 | (fin) | N_FIN | 1 |
| N_BECJ | (fin) | N_FIN | 1 |
| N_BECU | (fin) | N_FIN | 1 |

> Les lignes marquées *(fan-in)* sont les transitions qui **convergent** sur un nœud partagé — c'est là que vit la factorisation, désormais **explicite** dans la donnée.

## 5. Nœuds partagés (fan-in) — la déduplication, visible

| Nœud partagé | Transitions entrantes | Nb |
|---|---|---|
| N_CET48 | N_EACCD (Oui) · N_CO (Oui) · N_RVCET48 | 3 |
| N_CETJ | N_EACCN (Oui) · N_CY (Oui) · N_RVCETJ_2 | 3 |
| N_CETU | N_CR (Oui) · N_RVCETU | 2 |
| N_BEC48 | N_BO (Oui) · N_RVBEC48 | 2 |
| N_BECJ | N_BY (Oui) · N_RVBECJ_2 | 2 |
| N_BECU | N_BR (Oui) · N_RVBECU | 2 |
| N_FIN | N_NAVDP · N_NAVAS · N_CONS · 6 interventions | 9 |

> Sans factorisation, chacune de ces cibles serait **dupliquée** par branche (comme dans le diagramme d'origine : ECETO1/ECETO2, ECETY1/ECETY2…). Ici, **6 interventions + 8 nœuds RV** (dont les 2 RV « J+3–J+9 » comptant chacun 2 nœuds enchaînés) **+ 1 fin** sont des records **uniques** réutilisés. Ajouter un chemin qui mène à la même action = **1 transition de plus**, 0 nœud en plus.
