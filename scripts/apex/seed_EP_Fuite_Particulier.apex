/*
 * Jeu de données de démonstration : parcours « EP – FUITE CHEZ UN PARTICULIER ».
 *
 * Charge en records le parcours décrit dans doc/EP_Fuite_Particulier_RECORDS.md :
 *   1 Parcours__c · 36 Noeud__c · 6 ChampSaisie__c · 53 Transition__c.
 *
 * Idempotent : relancer le script purge d'abord le parcours existant (même Code)
 * et ses enfants, puis recharge tout. Le pointeur NoeudDepart_FK est positionné
 * après insertion des nœuds (dépendance circulaire Parcours <-> Noeud).
 *
 * Exécution (hors de ce livrable, côté org cible) :
 *   sf apex run --file scripts/apex/seed_EP_Fuite_Particulier.apex --target-org <alias>
 */
final String CODE = 'EP_FUITE_PART';

// --- Purge idempotente -------------------------------------------------------
List<Parcours__c> existants = [SELECT Id FROM Parcours__c WHERE Code__c = :CODE];
if (!existants.isEmpty()) {
    Set<Id> parcoursIds = new Map<Id, Parcours__c>(existants).keySet();
    List<Noeud__c> noeudsExistants = [SELECT Id FROM Noeud__c WHERE Parcours_FK__c IN :parcoursIds];
    // Les transitions et champs pointent les nœuds ; on détache le départ d'abord.
    for (Parcours__c p : existants) {
        p.NoeudDepart_FK__c = null;
    }
    update existants;
    delete [SELECT Id FROM Transition__c WHERE NoeudSource_FK__c IN :noeudsExistants];
    delete [SELECT Id FROM ChampSaisie__c WHERE Noeud_FK__c IN :noeudsExistants];
    delete noeudsExistants;
    delete existants;
}

// --- 1. Parcours (sans nœud de départ pour l'instant) ------------------------
Parcours__c parcours = new Parcours__c(
    Name = 'PARCOURS_EP – FUITE CHEZ UN PARTICULIER',
    Code__c = CODE,
    Version__c = 1,
    Statut__c = 'Actif',
    Categorie__c = 'Eau potable'
);
insert parcours;

// --- 2. Nœuds ----------------------------------------------------------------
// Clé lisible -> enregistrement. Le Name porte la clé (recoupement logigramme).
Map<String, Noeud__c> noeuds = new Map<String, Noeud__c>();

// Questions
noeuds.put('N_ID', new Noeud__c(TypeNoeud__c = 'Question', Texte__c = 'Identification — voir ChampSaisie'));
noeuds.put('N_LOC', new Noeud__c(TypeNoeud__c = 'Question', Texte__c = 'Où se trouve la fuite ?'));
noeuds.put('N_EAU', new Noeud__c(TypeNoeud__c = 'Question', Texte__c = 'Eau propre ou eau sale ?'));
noeuds.put('N_IE', new Noeud__c(TypeNoeud__c = 'Question', Texte__c = 'À l\'intérieur ou à l\'extérieur ? (+ appart/maison, informatif)'));
noeuds.put('N_FOSSE', new Noeud__c(TypeNoeud__c = 'Question', Texte__c = 'Compteur dans une fosse (regard) ? La fosse déborde-t-elle ?'));
noeuds.put('N_EACCD', new Noeud__c(TypeNoeud__c = 'Question', Texte__c = 'Lieu accessible à toute heure (sans votre présence) ?'));
noeuds.put('N_EACCN', new Noeud__c(TypeNoeud__c = 'Question', Texte__c = 'Lieu accessible à toute heure (sans votre présence) ?'));
noeuds.put('N_INT', new Noeud__c(TypeNoeud__c = 'Question', Texte__c = 'Fuite entre compteur et rue, ou entre compteur et habitation ?'));
noeuds.put('N_OU', new Noeud__c(TypeNoeud__c = 'Question', Texte__c = 'Où est située précisément la fuite ?'));
noeuds.put('N_AMPC', new Noeud__c(TypeNoeud__c = 'Question', Texte__c = 'Ampleur de la fuite ? (temps pour remplir un seau) — CET05'));
noeuds.put('N_AMPB', new Noeud__c(TypeNoeud__c = 'Question', Texte__c = 'Ampleur de la fuite ? (temps pour remplir un seau) — BEC03'));
noeuds.put('N_CY', new Noeud__c(TypeNoeud__c = 'Question', Texte__c = 'Lieu accessible ?'));
noeuds.put('N_CO', new Noeud__c(TypeNoeud__c = 'Question', Texte__c = 'Lieu accessible ?'));
noeuds.put('N_CR', new Noeud__c(TypeNoeud__c = 'Question', Texte__c = 'Lieu accessible ?'));
noeuds.put('N_BY', new Noeud__c(TypeNoeud__c = 'Question', Texte__c = 'Lieu accessible ?'));
noeuds.put('N_BO', new Noeud__c(TypeNoeud__c = 'Question', Texte__c = 'Lieu accessible ?'));
noeuds.put('N_BR', new Noeud__c(TypeNoeud__c = 'Question', Texte__c = 'Lieu accessible ?'));

// Navigation (ParcoursCible_FK renseigné plus tard, parcours cibles à venir)
noeuds.put('N_NAVDP', new Noeud__c(TypeNoeud__c = 'Navigation', Texte__c = 'Débranche vers « EP – FUITE DOMAINE PUBLIC »'));
noeuds.put('N_NAVAS', new Noeud__c(TypeNoeud__c = 'Navigation', Texte__c = 'Débranche vers « Assainissement »'));

// Conseil
noeuds.put('N_CONS', new Noeud__c(TypeNoeud__c = 'Conseil', Texte__c = 'Domaine privatif ; resp. exploitant entre rue et compteur ; voir un pro ; fermer le robinet avant compteur'));

// Actions — Events (prises de RV)
noeuds.put('N_RVCET48', new Noeud__c(TypeNoeud__c = 'Action', Texte__c = 'Prise de RV (<48h)', TypeAction__c = 'Créer', ObjetCible__c = 'Event',
    MappageChamps_JSON__c = '{"Subject":"RV CET05 (<48h)","ActivityDate":"TODAY+2","WhoId":"{client}","WhatId":"{case}"}'));
noeuds.put('N_RVCETJ_1', new Noeud__c(TypeNoeud__c = 'Action', Texte__c = 'Prise de RV — 1re visite (J+3)', TypeAction__c = 'Créer', ObjetCible__c = 'Event',
    MappageChamps_JSON__c = '{"Subject":"RV CET05 — visite 1","ActivityDate":"TODAY+3","WhoId":"{client}","WhatId":"{case}"}'));
noeuds.put('N_RVCETJ_2', new Noeud__c(TypeNoeud__c = 'Action', Texte__c = 'Prise de RV — 2e visite (J+9)', TypeAction__c = 'Créer', ObjetCible__c = 'Event',
    MappageChamps_JSON__c = '{"Subject":"RV CET05 — visite 2","ActivityDate":"TODAY+9","WhoId":"{client}","WhatId":"{case}"}'));
noeuds.put('N_RVCETU', new Noeud__c(TypeNoeud__c = 'Action', Texte__c = 'Prise de RV immédiate', TypeAction__c = 'Créer', ObjetCible__c = 'Event',
    MappageChamps_JSON__c = '{"Subject":"RV CET05 (immédiat)","ActivityDate":"TODAY","WhoId":"{client}","WhatId":"{case}"}'));
noeuds.put('N_RVBEC48', new Noeud__c(TypeNoeud__c = 'Action', Texte__c = 'Prise de RV (<48h)', TypeAction__c = 'Créer', ObjetCible__c = 'Event',
    MappageChamps_JSON__c = '{"Subject":"RV BEC03 (<48h)","ActivityDate":"TODAY+2","WhoId":"{client}","WhatId":"{case}"}'));
noeuds.put('N_RVBECJ_1', new Noeud__c(TypeNoeud__c = 'Action', Texte__c = 'Prise de RV — 1re visite (J+3)', TypeAction__c = 'Créer', ObjetCible__c = 'Event',
    MappageChamps_JSON__c = '{"Subject":"RV BEC03 — visite 1","ActivityDate":"TODAY+3","WhoId":"{client}","WhatId":"{case}"}'));
noeuds.put('N_RVBECJ_2', new Noeud__c(TypeNoeud__c = 'Action', Texte__c = 'Prise de RV — 2e visite (J+9)', TypeAction__c = 'Créer', ObjetCible__c = 'Event',
    MappageChamps_JSON__c = '{"Subject":"RV BEC03 — visite 2","ActivityDate":"TODAY+9","WhoId":"{client}","WhatId":"{case}"}'));
noeuds.put('N_RVBECU', new Noeud__c(TypeNoeud__c = 'Action', Texte__c = 'Prise de RV immédiate', TypeAction__c = 'Créer', ObjetCible__c = 'Event',
    MappageChamps_JSON__c = '{"Subject":"RV BEC03 (immédiat)","ActivityDate":"TODAY","WhoId":"{client}","WhatId":"{case}"}'));

// Actions — WorkOrders (interventions). WorkType porté par le CodePresta du nœud.
noeuds.put('N_CET48', new Noeud__c(TypeNoeud__c = 'Action', Texte__c = 'Intervention CET05 <48h', TypeAction__c = 'Créer', CodePresta__c = 'CET05', ObjetCible__c = 'WorkOrder',
    MappageChamps_JSON__c = '{"WorkType":"{noeud.CodePresta}","Priority":"<48h","AccountId":"{client}","CaseId":"{case}","Subject":"{localisation} / {ampleur} / {urgence}"}'));
noeuds.put('N_CETJ', new Noeud__c(TypeNoeud__c = 'Action', Texte__c = 'Intervention CET05 J+2–J+7', TypeAction__c = 'Créer', CodePresta__c = 'CET05', ObjetCible__c = 'WorkOrder',
    MappageChamps_JSON__c = '{"WorkType":"{noeud.CodePresta}","Priority":"J+2–J+7","AccountId":"{client}","CaseId":"{case}","Subject":"{localisation} / {ampleur} / {urgence}"}'));
noeuds.put('N_CETU', new Noeud__c(TypeNoeud__c = 'Action', Texte__c = 'Intervention CET05 URGENTE', TypeAction__c = 'Créer', CodePresta__c = 'CET05', ObjetCible__c = 'WorkOrder',
    MappageChamps_JSON__c = '{"WorkType":"{noeud.CodePresta}","Priority":"Urgent","AccountId":"{client}","CaseId":"{case}","Subject":"{localisation} / {ampleur} / {urgence}"}'));
noeuds.put('N_BEC48', new Noeud__c(TypeNoeud__c = 'Action', Texte__c = 'Intervention BEC03 <48h', TypeAction__c = 'Créer', CodePresta__c = 'BEC03', ObjetCible__c = 'WorkOrder',
    MappageChamps_JSON__c = '{"WorkType":"{noeud.CodePresta}","Priority":"<48h","AccountId":"{client}","CaseId":"{case}","Subject":"{localisation} / {ampleur} / {urgence}"}'));
noeuds.put('N_BECJ', new Noeud__c(TypeNoeud__c = 'Action', Texte__c = 'Intervention BEC03 J+2–J+7', TypeAction__c = 'Créer', CodePresta__c = 'BEC03', ObjetCible__c = 'WorkOrder',
    MappageChamps_JSON__c = '{"WorkType":"{noeud.CodePresta}","Priority":"J+2–J+7","AccountId":"{client}","CaseId":"{case}","Subject":"{localisation} / {ampleur} / {urgence}"}'));
noeuds.put('N_BECU', new Noeud__c(TypeNoeud__c = 'Action', Texte__c = 'Intervention BEC03 URGENTE', TypeAction__c = 'Créer', CodePresta__c = 'BEC03', ObjetCible__c = 'WorkOrder',
    MappageChamps_JSON__c = '{"WorkType":"{noeud.CodePresta}","Priority":"Urgent","AccountId":"{client}","CaseId":"{case}","Subject":"{localisation} / {ampleur} / {urgence}"}'));

// Fins
noeuds.put('N_FIN', new Noeud__c(TypeNoeud__c = 'Fin', Texte__c = 'Fin du parcours'));
noeuds.put('N_FINHS', new Noeud__c(TypeNoeud__c = 'Fin', Texte__c = 'Fin — hors schéma (routage à définir)'));

// Name = clé, rattachement au parcours.
for (String cle : noeuds.keySet()) {
    Noeud__c n = noeuds.get(cle);
    n.Name = cle;
    n.Parcours_FK__c = parcours.Id;
}
insert noeuds.values();

// --- 3. Nœud de départ -------------------------------------------------------
parcours.NoeudDepart_FK__c = noeuds.get('N_ID').Id;
update parcours;

// --- 4. Champs de saisie de l'écran d'identification (N_ID) ------------------
Id nId = noeuds.get('N_ID').Id;
insert new List<ChampSaisie__c>{
    new ChampSaisie__c(Noeud_FK__c = nId, Libelle__c = 'Nom (rappel)', TypeChamp__c = 'Text', Ordre__c = 1),
    new ChampSaisie__c(Noeud_FK__c = nId, Libelle__c = 'Référence client', TypeChamp__c = 'Text', MappageCible__c = 'contrôle contrat', Ordre__c = 2),
    new ChampSaisie__c(Noeud_FK__c = nId, Libelle__c = 'Adresse concernée', TypeChamp__c = 'Text', MappageCible__c = 'contrôle contrat', Ordre__c = 3),
    new ChampSaisie__c(Noeud_FK__c = nId, Libelle__c = 'Téléphone', TypeChamp__c = 'Phone', MappageCible__c = '{client}.Phone', Ordre__c = 4),
    new ChampSaisie__c(Noeud_FK__c = nId, Libelle__c = 'Portable', TypeChamp__c = 'Phone', MappageCible__c = '{client}.PersonMobilePhone', Ordre__c = 5),
    new ChampSaisie__c(Noeud_FK__c = nId, Libelle__c = 'Mail', TypeChamp__c = 'Email', MappageCible__c = '{client}.PersonEmail', Ordre__c = 6)
};

// --- 5. Transitions (les « réponses » de chaque question) --------------------
List<List<Object>> aretes = new List<List<Object>>{
    new List<Object>{'N_ID', 'Continuer', 'N_LOC', 1},
    new List<Object>{'N_LOC', 'Dans votre propriété', 'N_EAU', 1},
    new List<Object>{'N_LOC', 'Dans la rue / voie publique', 'N_NAVDP', 2},
    new List<Object>{'N_EAU', 'Eau propre', 'N_IE', 1},
    new List<Object>{'N_EAU', 'Eau sale (couleur / odeur)', 'N_NAVAS', 2},
    new List<Object>{'N_IE', 'Extérieur', 'N_FOSSE', 1},
    new List<Object>{'N_IE', 'Intérieur', 'N_INT', 2},
    new List<Object>{'N_FOSSE', 'Oui, la fosse déborde', 'N_EACCD', 1},
    new List<Object>{'N_FOSSE', 'Oui, ne déborde pas', 'N_EACCN', 2},
    new List<Object>{'N_FOSSE', 'Non, pas dans une fosse', 'N_FINHS', 3},
    new List<Object>{'N_EACCD', 'Oui', 'N_CET48', 1},
    new List<Object>{'N_EACCD', 'Non', 'N_RVCET48', 2},
    new List<Object>{'N_EACCN', 'Oui', 'N_CETJ', 1},
    new List<Object>{'N_EACCN', 'Non', 'N_RVCETJ_1', 2},
    new List<Object>{'N_INT', 'Entre compteur et rue', 'N_OU', 1},
    new List<Object>{'N_INT', 'Entre compteur et habitation', 'N_CONS', 2},
    new List<Object>{'N_OU', 'Compteur / robinet / joint', 'N_AMPC', 1},
    new List<Object>{'N_OU', 'Canalisation (depuis la rue)', 'N_AMPB', 2},
    new List<Object>{'N_AMPC', 'Goutte à goutte / seau en 1 j', 'N_CY', 1},
    new List<Object>{'N_AMPC', 'Filet d\'eau / seau en qq heures', 'N_CO', 2},
    new List<Object>{'N_AMPC', 'Seau en qq minutes / inondation', 'N_CR', 3},
    new List<Object>{'N_AMPB', 'Goutte à goutte / seau en 1 j', 'N_BY', 1},
    new List<Object>{'N_AMPB', 'Filet d\'eau / seau en qq heures', 'N_BO', 2},
    new List<Object>{'N_AMPB', 'Seau en qq minutes / inondation', 'N_BR', 3},
    new List<Object>{'N_CY', 'Oui', 'N_CETJ', 1},
    new List<Object>{'N_CY', 'Non', 'N_RVCETJ_1', 2},
    new List<Object>{'N_CO', 'Oui', 'N_CET48', 1},
    new List<Object>{'N_CO', 'Non', 'N_RVCET48', 2},
    new List<Object>{'N_CR', 'Oui', 'N_CETU', 1},
    new List<Object>{'N_CR', 'Non', 'N_RVCETU', 2},
    new List<Object>{'N_BY', 'Oui', 'N_BECJ', 1},
    new List<Object>{'N_BY', 'Non', 'N_RVBECJ_1', 2},
    new List<Object>{'N_BO', 'Oui', 'N_BEC48', 1},
    new List<Object>{'N_BO', 'Non', 'N_RVBEC48', 2},
    new List<Object>{'N_BR', 'Oui', 'N_BECU', 1},
    new List<Object>{'N_BR', 'Non', 'N_RVBECU', 2},
    new List<Object>{'N_NAVDP', 'Aller au parcours « Domaine public »', 'N_FIN', 1},
    new List<Object>{'N_NAVAS', 'Aller au parcours « Assainissement »', 'N_FIN', 1},
    new List<Object>{'N_CONS', 'Fin de l\'appel', 'N_FIN', 1},
    new List<Object>{'N_RVCET48', '(après prise de RV)', 'N_CET48', 1},
    new List<Object>{'N_RVCETJ_1', '(enchaîne — 2e visite)', 'N_RVCETJ_2', 1},
    new List<Object>{'N_RVCETJ_2', '(après prise de RV)', 'N_CETJ', 1},
    new List<Object>{'N_RVCETU', '(après prise de RV)', 'N_CETU', 1},
    new List<Object>{'N_RVBEC48', '(après prise de RV)', 'N_BEC48', 1},
    new List<Object>{'N_RVBECJ_1', '(enchaîne — 2e visite)', 'N_RVBECJ_2', 1},
    new List<Object>{'N_RVBECJ_2', '(après prise de RV)', 'N_BECJ', 1},
    new List<Object>{'N_RVBECU', '(après prise de RV)', 'N_BECU', 1},
    new List<Object>{'N_CET48', '(fin)', 'N_FIN', 1},
    new List<Object>{'N_CETJ', '(fin)', 'N_FIN', 1},
    new List<Object>{'N_CETU', '(fin)', 'N_FIN', 1},
    new List<Object>{'N_BEC48', '(fin)', 'N_FIN', 1},
    new List<Object>{'N_BECJ', '(fin)', 'N_FIN', 1},
    new List<Object>{'N_BECU', '(fin)', 'N_FIN', 1}
};

List<Transition__c> transitions = new List<Transition__c>();
for (List<Object> a : aretes) {
    transitions.add(new Transition__c(
        NoeudSource_FK__c = noeuds.get((String) a[0]).Id,
        Libelle_reponse__c = (String) a[1],
        NoeudCible_FK__c = noeuds.get((String) a[2]).Id,
        Ordre__c = (Integer) a[3]
    ));
}
insert transitions;

System.debug('Seed EP – Fuite : ' + noeuds.size() + ' nœuds, ' + transitions.size() + ' transitions, 6 champs.');
