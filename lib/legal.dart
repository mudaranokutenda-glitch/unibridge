import 'package:flutter/material.dart';
import 'l10n.dart';

// ---------------- Terms of use + Privacy policy (English and French) --------
// A template written for this app. Have it checked before release.
// The same text is in docs/privacy-policy.html: change both together.

const String kContactEmail = 'mudaranokutenda@gmail.com';
const String kLegalLastUpdatedEn = '11 November 2026';
const String kLegalLastUpdatedFr = '11 novembre 2026';

typedef LegalSection = (String, String);

// ---------------- Terms (English) ----------------
const List<LegalSection> kTermsEn = [
  (
    'About AZSA',
    'AZSA helps students in Algeria find each other to exchange money, '
        'buy and sell items, and keep their student information in one place. '
        'AZSA never holds, sends or receives money. Every exchange happens '
        'directly between the two users, outside the app.',
  ),
  (
    'Your account',
    'You sign up with your email and a password (or Google). You must give '
        'true information and keep your password secret. One person, one '
        'account. You can delete your account at any time (see "Deleting your '
        'account" in the privacy policy).',
  ),
  (
    'Exchanges between users',
    'You are fully responsible for every exchange you make, and for respecting '
        'the laws of Algeria, including the rules on foreign currency. AZSA '
        'is not a party to any exchange and cannot promise that the other user '
        'will keep their word. Suggested matches are only suggestions: a match '
        'happens only when both people accept. Both users must confirm in the app '
        'before an exchange counts as completed. If something goes wrong, open a '
        'dispute in the chat.',
  ),
  (
    'Marketplace',
    'Only list items you own and are allowed to sell. Forbidden: illegal items, '
        'weapons, drugs, stolen goods, fake documents, and anything that breaks '
        'the law.',
  ),
  (
    'Behaviour',
    'No scams, harassment, insults, spam, fake profiles or sharing other '
        "people's private information. You can report and block any user. We may "
        'hide content or close accounts that break these rules.',
  ),
  (
    'Emergency alerts',
    'The Educational Attaché may send urgent alerts to every user. Please read '
        'them carefully. They do not replace the official channels of the embassy '
        'or the Algerian authorities.',
  ),
  (
    'No warranty',
    'The app is provided "as is". Exchange rates shown in the app are for '
        'information only. As far as the law allows, AZSA is not liable for '
        'losses caused by exchanges or deals between users.',
  ),
  (
    'Changes',
    'We may update these terms. The date at the top shows the latest version. '
        'If you keep using the app, you accept the new terms.',
  ),
  ('Contact', 'Questions: $kContactEmail'),
];

// ---------------- Privacy (English) ----------------
const List<LegalSection> kPrivacyEn = [
  (
    'What we collect',
    '• Account: your name and email.\n'
        '• Profile: photo, wilaya, city or area, phone number.\n'
        '• Student space (you fill it in): student record (name, gender, program, '
        'level, years, wilaya, inscription number, phone), bank account number, '
        'passport number, results (PDF), date of entry into Algeria, passport '
        'scan when you ask for an attestation de bourse, appointment requests.\n'
        '• Verification (optional): a photo of your student card.\n'
        '• Activity: requests, chats (text and photos), listings, ratings, reports '
        'and blocks.\n'
        '• Device: a notification token, so we can send you notifications.',
  ),
  (
    'Who can see what',
    '• Every user: your name, profile photo, wilaya, city or area, verification '
        'badge, rating, number of completed exchanges and member-since date.\n'
        '• Your phone number: you, the Educational Attaché and the Governor of '
        'your wilaya. Never other students.\n'
        '• Your student record and results: you, the Educational Attaché and the '
        'Governor of your wilaya.\n'
        '• Your bank account number: you, the Educational Attaché and the '
        'Governor of your wilaya.\n'
        '• Your passport number, passport scan and attestations: you and the '
        'Educational Attaché only. Never a Governor.\n'
        '• Your appointments: you and the Educational Attaché.\n'
        '• Your student card (verification): you and the AZSA team.\n'
        '• Your chats: only the two people in the chat.\n'
        '• Your email: never shown to other users.\n'
        'The app administrator can technically access the stored data in order '
        'to run the app. Every time the Educational Attaché or a Governor opens '
        'your results, bank account, passport number or passport scan, it is '
        'recorded in an access log that cannot be changed.',
  ),
  (
    'Who is who',
    'The Educational Attaché of Zimbabwe works in the embassy office. A Governor '
        'is the student representative of one wilaya. AZSA itself is not an '
        'embassy app.',
  ),
  (
    'Why we use it',
    'To run the app: matching, chat, marketplace, notifications, student '
        'records, attestations, appointments, emergency alerts, and trust and '
        'safety (verification, reports, disputes).',
  ),
  (
    'Not sold, not shared',
    'We do not sell your data and we do not show ads. We do not share it with '
        'anyone outside the people listed above. The data is stored by the '
        'services that run the app: Supabase (database, login, files) and Google '
        'Firebase (notifications); Google sign-in is handled by Google. These '
        'services may store data outside Algeria. We protect the data with access '
        'rules in the database, but no system can be called completely safe.',
  ),
  (
    'How long we keep it',
    '• Chats (messages and photos) are deleted 30 days after the request is '
        'completed or cancelled. Chats of a request under dispute are kept until '
        'the dispute is solved. The request itself and the ratings stay, because '
        'ratings depend on them.\n'
        '• Your passport scan is deleted after your attestation is issued.\n'
        '• Everything else is kept until you delete your account.',
  ),
  (
    'Deleting your account',
    'Profile tab → Delete my account → type DELETE. This deletes your profile, '
        'phone number, student record, bank account and passport numbers, '
        'results, passport scans, attestations, appointments, photos (also those '
        'you sent in chats), listings, open requests and notifications. Finished '
        'exchanges, chat text messages and ratings stay for the other person, '
        'shown as "AZSA user". The access log keeps its records for safety. '
        'You cannot delete your account while an exchange is in progress. '
        'Messages you sent stay visible to the other person until the chat is '
        'deleted automatically, 30 days after the request ends. A security log '
        'of who opened sensitive documents is kept even after an account is '
        'deleted.',
  ),
  (
    'Your rights',
    'You can see and change your information in the app, delete your account '
        'in the app, and write to us to ask for a copy of your data or to correct '
        'it (Algerian law 18-07 on personal data).',
  ),
  ('Contact', 'Privacy questions: $kContactEmail'),
];

// ---------------- Conditions (français) ----------------
const List<LegalSection> kTermsFr = [
  (
    'À propos de AZSA',
    'AZSA aide les étudiants en Algérie à se trouver pour échanger de '
        "l'argent, acheter et vendre des objets, et garder leurs informations "
        "d'étudiant au même endroit. AZSA ne détient, n'envoie et ne reçoit "
        "jamais d'argent. Chaque échange se fait directement entre les deux "
        "utilisateurs, en dehors de l'application.",
  ),
  (
    'Votre compte',
    'Vous vous inscrivez avec votre e-mail et un mot de passe (ou Google). Vous '
        'devez donner des informations vraies et garder votre mot de passe secret. '
        'Une personne, un compte. Vous pouvez supprimer votre compte à tout moment '
        '(voir « Supprimer votre compte » dans la politique de confidentialité).',
  ),
  (
    'Échanges entre utilisateurs',
    'Vous êtes entièrement responsable de chaque échange et du respect des lois '
        "algériennes, y compris les règles sur les devises. AZSA n'est partie "
        "à aucun échange et ne peut pas promettre que l'autre utilisateur tiendra "
        'parole. Les correspondances suggérées ne sont que des suggestions : la '
        'mise en relation se fait seulement si les deux personnes acceptent. Les '
        "deux utilisateurs doivent confirmer dans l'application avant qu'un "
        'échange soit terminé. En cas de problème, ouvrez un litige dans la '
        'discussion.',
  ),
  (
    'Marché',
    'Ne publiez que des objets qui vous appartiennent et que vous avez le droit '
        'de vendre. Interdits : objets illégaux, armes, drogues, objets volés, faux '
        'documents, et tout ce qui est contraire à la loi.',
  ),
  (
    'Comportement',
    'Pas d’arnaques, de harcèlement, d’insultes, de spam, de faux profils ni de '
        'partage des informations privées des autres. Vous pouvez signaler et '
        'bloquer tout utilisateur. Nous pouvons masquer du contenu ou fermer les '
        'comptes qui ne respectent pas ces règles.',
  ),
  (
    "Alertes d'urgence",
    "L'Attaché d'éducation peut envoyer des alertes urgentes à tous les "
        'utilisateurs. Lisez-les attentivement. Elles ne remplacent pas les canaux '
        "officiels de l'ambassade ni des autorités algériennes.",
  ),
  (
    'Aucune garantie',
    "L'application est fournie « telle quelle ». Les taux de change affichés sont "
        'donnés à titre indicatif. Dans la mesure permise par la loi, AZSA '
        "n'est pas responsable des pertes causées par les échanges ou les affaires "
        'entre utilisateurs.',
  ),
  (
    'Modifications',
    'Nous pouvons modifier ces conditions. La date en haut indique la dernière '
        "version. Si vous continuez à utiliser l'application, vous acceptez les "
        'nouvelles conditions.',
  ),
  ('Contact', 'Questions : $kContactEmail'),
];

// ---------------- Confidentialité (français) ----------------
const List<LegalSection> kPrivacyFr = [
  (
    'Ce que nous collectons',
    '• Compte : votre nom et votre e-mail.\n'
        '• Profil : photo, wilaya, ville ou quartier, numéro de téléphone.\n'
        "• Espace étudiant (vous le remplissez) : fiche étudiant (nom, sexe, "
        "filière, niveau, années, wilaya, numéro d'inscription, téléphone), numéro "
        'de compte bancaire, numéro de passeport, résultats (PDF), date d’entrée en '
        "Algérie, scan du passeport quand vous demandez une attestation de bourse, "
        'demandes de rendez-vous.\n'
        "• Vérification (facultative) : une photo de votre carte d'étudiant.\n"
        '• Activité : demandes, discussions (texte et photos), annonces, notes, '
        'signalements et blocages.\n'
        "• Appareil : un jeton de notification, pour vous envoyer des notifications.",
  ),
  (
    'Qui peut voir quoi',
    '• Tous les utilisateurs : votre nom, photo de profil, wilaya, ville ou '
        "quartier, badge de vérification, note, nombre d'échanges terminés et date "
        "d'inscription.\n"
        "• Votre numéro de téléphone : vous, l'Attaché d'éducation et le Gouverneur "
        'de votre wilaya. Jamais les autres étudiants.\n'
        "• Votre fiche étudiant et vos résultats : vous, l'Attaché d'éducation et "
        'le Gouverneur de votre wilaya.\n'
        "• Votre numéro de compte bancaire : vous, l'Attaché d'éducation et le "
        'Gouverneur de votre wilaya.\n'
        '• Votre numéro de passeport, le scan du passeport et vos attestations : '
        "vous et l'Attaché d'éducation seulement. Jamais un Gouverneur.\n"
        "• Vos rendez-vous : vous et l'Attaché d'éducation.\n"
        "• Votre carte d'étudiant (vérification) : vous et l'équipe AZSA.\n"
        '• Vos discussions : seulement les deux personnes de la discussion.\n'
        "• Votre e-mail : jamais montré aux autres utilisateurs.\n"
        "L'administrateur de l'application peut techniquement accéder aux données "
        "enregistrées pour faire fonctionner l'application. Chaque fois que "
        "l'Attaché d'éducation ou un Gouverneur ouvre vos résultats, votre compte "
        'bancaire, votre numéro de passeport ou le scan du passeport, cela est '
        "enregistré dans un journal d'accès qui ne peut pas être modifié.",
  ),
  (
    'Qui est qui',
    "L'Attaché d'éducation du Zimbabwe travaille au bureau de l'ambassade. Un "
        "Gouverneur est le représentant des étudiants d'une wilaya. AZSA "
        "n'est pas une application de l'ambassade.",
  ),
  (
    'Pourquoi nous les utilisons',
    "Pour faire fonctionner l'application : mise en relation, discussion, marché, "
        "notifications, fiches étudiants, attestations, rendez-vous, alertes "
        "d'urgence, et confiance et sécurité (vérification, signalements, litiges).",
  ),
  (
    'Ni vendues, ni partagées',
    'Nous ne vendons pas vos données et nous ne montrons pas de publicité. Nous '
        'ne les partageons avec personne en dehors des personnes citées plus haut. '
        "Les données sont hébergées par les services qui font fonctionner "
        "l'application : Supabase (base de données, connexion, fichiers) et Google "
        'Firebase (notifications) ; la connexion Google est gérée par Google. Ces '
        "services peuvent stocker des données hors d'Algérie. Nous protégeons les "
        "données par des règles d'accès dans la base de données, mais aucun système "
        'ne peut être dit totalement sûr.',
  ),
  (
    'Combien de temps nous les gardons',
    '• Les discussions (messages et photos) sont supprimées 30 jours après que la '
        'demande est terminée ou annulée. Les discussions d’une demande en litige '
        "sont gardées jusqu'à la fin du litige. La demande et les notes restent, "
        'car les notes en dépendent.\n'
        '• Le scan de votre passeport est supprimé après la délivrance de votre '
        'attestation.\n'
        "• Tout le reste est gardé jusqu'à la suppression de votre compte.",
  ),
  (
    'Supprimer votre compte',
    'Onglet Profil → Supprimer mon compte → tapez DELETE. Cela supprime votre '
        'profil, votre numéro de téléphone, votre fiche étudiant, vos numéros de '
        'compte bancaire et de passeport, vos résultats, scans de passeport, '
        'attestations, rendez-vous, photos (aussi celles envoyées dans les '
        'discussions), annonces, demandes ouvertes et notifications. Les échanges '
        "terminés, les messages texte et les notes restent pour l'autre personne, "
        "avec le nom « AZSA user ». Le journal d'accès garde ses lignes pour la "
        'sécurité. Vous ne pouvez pas supprimer votre compte pendant un échange en '
        "cours. Les messages que vous avez envoyés restent visibles pour l'autre "
        "personne jusqu'à la suppression automatique de la discussion, 30 jours "
        'après la fin de la demande. Un journal de sécurité indiquant qui a ouvert '
        'des documents sensibles est conservé même après la suppression d\'un '
        'compte.',
  ),
  (
    'Vos droits',
    "Vous pouvez voir et modifier vos informations dans l'application, supprimer "
        "votre compte dans l'application, et nous écrire pour demander une copie "
        'de vos données ou les corriger (loi algérienne 18-07 sur les données '
        'personnelles).',
  ),
  ('Contact', 'Questions sur la confidentialité : $kContactEmail'),
];

bool get _french => AppSettings.language.value == 'fr';

class LegalScreen extends StatelessWidget {
  // 0 = Terms, 1 = Privacy
  final int initialTab;
  const LegalScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Terms and privacy')),
          bottom: TabBar(
            tabs: [
              Tab(text: tr('Terms of use')),
              Tab(text: tr('Privacy policy')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _LegalText(sections: _french ? kTermsFr : kTermsEn),
            _LegalText(sections: _french ? kPrivacyFr : kPrivacyEn),
          ],
        ),
      ),
    );
  }
}

class _LegalText extends StatelessWidget {
  final List<LegalSection> sections;
  const _LegalText({required this.sections});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
            tr('Last updated: {date}',
                {'date': _french ? kLegalLastUpdatedFr : kLegalLastUpdatedEn}),
            style: Theme.of(context).textTheme.bodySmall),
        for (final (title, body) in sections) ...[
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(body),
        ],
      ],
    );
  }
}
