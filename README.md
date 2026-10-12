# Parcours métiers — moteur *data-driven* sur Salesforce

> **Statut : conception / spécifications.** Rien n'est déployé. Ce dépôt sert à **partager l'approche** avec l'équipe avant toute mise en œuvre sur Salesforce.

## 1. À quoi sert cette application

Les conseillers d'un **service client** s'appuient sur des **parcours métiers** (scripts guidés) pour traiter les appels : poser les bonnes questions au client, suivre les bifurcations selon ses réponses, donner les conseils adaptés, puis déclencher les actions qui en découlent (prise de rendez-vous, intervention urgente, etc.).

Ces parcours existent aujourd'hui sous forme de **logigrammes** (schémas). L'objectif est de les rendre **exécutables dans Salesforce**, directement depuis la fiche **Compte** ou **Requête (Case)**, pour **guider le conseiller pas à pas** et **créer automatiquement** les enregistrements métier associés.

Il y a **~100 parcours** à terme. L'enjeu n'est donc pas de traiter *un* parcours, mais de les traiter **tous**, et de pouvoir en **ajouter / modifier** sans redéveloppement.

## 2. Le principe : « la donnée décrit, le code exécute »

L'approche naïve — **1 Screen Flow par parcours** — ne passe pas à l'échelle : 100 flows à construire, maintenir et versionner, et une génération qui atteint vite ses limites sur les gros parcours.

Nous avons retenu une **architecture pilotée par la donnée** :

- **Un parcours = des enregistrements** dans des objets custom génériques (sa logique est *de la donnée*, pas du code).
- **Un seul moteur**, générique, **écrit une seule fois**, lit ces enregistrements et déroule le parcours à l'écran.
- **Ajouter un parcours = ajouter des données** — aucun flow ni code spécifique, aucun déploiement par parcours.

```mermaid
flowchart LR
  subgraph KO["Approche « 1 flow par parcours » (écartée)"]
    F1[Flow 1]:::ko --- F2[Flow 2]:::ko --- F3[… Flow 100]:::ko
  end
  subgraph OK["Approche data-driven (retenue)"]
    D[(Parcours en<br/>données)]:::data --> M[1 moteur<br/>générique]:::ok
  end
  classDef ko fill:#F9D5D3,stroke:#C0392B,color:#000;
  classDef data fill:#D6E8FF,stroke:#0176d3,color:#000;
  classDef ok fill:#CDE9D6,stroke:#2E7D32,color:#000;
```

## 3. Comment ça fonctionne (grandes lignes)

### Modèle de données

**Objets de définition** (le parcours, saisis une fois) :

| Objet | Rôle |
|---|---|
| `Parcours__c` | L'en-tête d'un parcours (libellé, catégorie, nœud de départ). |
| `Noeud__c` | Une étape : **Question**, **Conseil**, **Action**, **Navigation** (vers un autre parcours) ou **Fin**. |
| `Transition__c` | Un lien orienté entre deux nœuds = **une réponse possible**. L'enchaînement est un **graphe**, pas une liste ordonnée. |
| `ChampSaisie__c` | Les champs d'un écran de saisie (nom, téléphone…), avec recopie éventuelle vers la fiche. |

**Objets d'exécution** (ce qui se passe pendant l'appel) :

| Objet | Rôle |
|---|---|
| `SessionParcours__c` | Une exécution de parcours pour un client/une requête donnés (origine générique `OrigineType` / `OrigineId`). |
| `ReponseSaisie__c` | La trace de chaque réponse / saisie du conseiller. |
| `ActionExecutee__c` | Le journal des actions DML jouées (création / mise à jour / suppression). |

### Le moteur : un composant **LWC générique unique**

Posé sur la page **Compte / Requête**, le LWC :

1. charge le **nœud de départ** du parcours ;
2. affiche l'**écran adapté** au type du nœud (question + réponses issues des `Transition__c`, champs issus des `ChampSaisie__c`, conseil…) ;
3. **persiste** la réponse du conseiller (`ReponseSaisie__c`) ;
4. sur un nœud **Action**, appelle **une classe Apex générique** qui réalise le DML (`insert` / `update` / `delete`) sur l'objet cible décrit dans la donnée, et journalise (`ActionExecutee__c`) ;
5. **avance** au nœud suivant (la réponse choisie désigne la cible) et **se re-rend** — jusqu'au nœud **Fin**.

Le même composant sert les **100 parcours**. Une action = **un DML décrit par la donnée** (objet cible + mapping des champs en JSON) : plus de classe Apex par type d'action.

## 4. Les spécifications

Les spécifications sont les pages Markdown du dossier [`doc/`](doc/) ; l'**interprétation des schémas d'origine** (logigrammes Mermaid) vit dans [`interpretation/`](interpretation/). GitHub les **rend directement** dans le navigateur du dépôt, **diagrammes Mermaid inclus** — aucun téléchargement nécessaire.

**Spécifications — [`doc/`](doc/) :**

| Fichier | Contenu |
|---|---|
| [`Architecture_DataDriven.md`](doc/Architecture_DataDriven.md) | **Document d'architecture** : modèle de données, lancement depuis Compte/Case, sélection du parcours, boucle du moteur, navigation inter-parcours, classe Apex générique. **Commencer par celui-ci.** |
| [`Dictionnaire_Donnees_Parcours.md`](doc/Dictionnaire_Donnees_Parcours.md) | **Dictionnaire de données** : chaque objet/champ décrit, avec exemples. |
| [`EP_Fuite_Particulier_RECORDS.md`](doc/EP_Fuite_Particulier_RECORDS.md) | **Exemple concret** : le parcours « EP – Fuite chez un particulier » entièrement traduit en enregistrements (preuve que le modèle tient). |

**Interprétation des schémas — [`interpretation/`](interpretation/) :**

| Fichier | Contenu |
|---|---|
| [`EP_Fuite_Particulier_interpretation.md`](interpretation/EP_Fuite_Particulier_interpretation.md) | Logigramme Mermaid du parcours (interprétation du schéma d'origine). |

Les logigrammes d'origine (schémas sources) sont dans le dossier [`schema/`](schema/).

## 5. Suite envisagée

1. **Tranche verticale de validation** : créer les objets, importer le parcours « EP – Fuite », et un **moteur LWC minimal** (Question / Conseil / Fin + persistance des réponses, actions en *placeholder*).
2. **Activer les actions réelles** via la classe Apex générique (RV → Events, intervention → WorkOrder).
3. **Industrialiser** : import des autres parcours (pure donnée), navigation inter-parcours, visualiseur Mermaid intégré.

> Tout cela reste à l'état de **proposition** : aucune décision de mise en œuvre n'est prise, aucun composant n'est déployé.

---

## Annexe — squelette technique (Salesforce DX)

Ce dépôt est aussi un projet **Salesforce DX** (dossier `force-app/`, `config/`, `sfdx-project.json`) qui accueillera l'implémentation le moment venu.

Prérequis et prise en main : [Get Started with Salesforce DX](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_get_started_dx.htm) · [Install Salesforce CLI](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_install_cli.htm).
