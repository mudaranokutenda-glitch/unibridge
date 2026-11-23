import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'startup_sound.dart';

// ---------------- Languages (English, French) + theme ----------------
//
// Write texts in English and wrap them with tr():
//   Text(tr('Log out'))
//   Text(tr('Block {name}?', {'name': name}))
// The translations are in _t below: 'English': 'Français'.
// A text that is missing from _t simply stays in English.

const Map<String, String> kLanguages = {
  'en': 'English',
  'fr': 'Français',
};

class AppSettings {
  static final language = ValueNotifier<String>('en');
  static final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

  // Called once in main(). First start: use the phone's language if we have it.
  static Future<void> load() async {
    final phone = PlatformDispatcher.instance.locale.languageCode;
    var lang = kLanguages.containsKey(phone) ? phone : 'en';
    var mode = ThemeMode.system;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('language');
      if (saved != null && kLanguages.containsKey(saved)) lang = saved;
      // Arabic was removed: a phone that had saved Arabic goes back to English.
      if (saved == 'ar') {
        lang = 'en';
        await prefs.setString('language', 'en');
      }
      mode = ThemeMode.values.firstWhere(
        (m) => m.name == prefs.getString('theme_mode'),
        orElse: () => ThemeMode.system,
      );
    } catch (e) {
      debugPrint('Could not load settings: $e');
    }
    language.value = lang;
    themeMode.value = mode;
  }

  static Future<void> setLanguage(String code) async {
    language.value = code;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('language', code);
    } catch (e) {
      debugPrint('Could not save language: $e');
    }
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('theme_mode', mode.name);
    } catch (e) {
      debugPrint('Could not save theme: $e');
    }
  }
}

String tr(String english, [Map<String, Object?> params = const {}]) {
  final lang = AppSettings.language.value;
  var text = english;
  if (lang != 'en') {
    final row = _t[english];
    if (row != null) text = row;
  }
  params.forEach((key, value) => text = text.replaceAll('{$key}', '$value'));
  return text;
}

// Language + theme pickers (Profile tab).
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(tr('Language')),
            trailing: DropdownButton<String>(
              value: AppSettings.language.value,
              underline: const SizedBox.shrink(),
              items: [
                for (final e in kLanguages.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) {
                if (v != null) AppSettings.setLanguage(v);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: Text(tr('Theme')),
            trailing: DropdownButton<ThemeMode>(
              value: AppSettings.themeMode.value,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem(
                    value: ThemeMode.system, child: Text(tr('System'))),
                DropdownMenuItem(value: ThemeMode.light, child: Text(tr('Light'))),
                DropdownMenuItem(value: ThemeMode.dark, child: Text(tr('Dark'))),
              ],
              onChanged: (v) {
                if (v != null) AppSettings.setThemeMode(v);
              },
            ),
          ),
          // Plays assets/sounds/startup.mp3 once when the app opens (never on silent).
          ValueListenableBuilder<bool>(
            valueListenable: StartupSound.enabled,
            builder: (context, on, _) => SwitchListTile(
              secondary: const Icon(Icons.volume_up_outlined),
              title: Text(tr('Startup sound')),
              subtitle: Text(tr('Plays when the app opens, never on silent.')),
              value: on,
              onChanged: (v) => StartupSound.setEnabled(v),
            ),
          ),
        ],
      ),
    );
  }
}

// Small language menu for the login screen's top bar.
class LanguageMenuButton extends StatelessWidget {
  final VoidCallback onChanged;
  const LanguageMenuButton({super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.translate),
      tooltip: tr('Language'),
      onSelected: (v) async {
        await AppSettings.setLanguage(v);
        onChanged();
      },
      itemBuilder: (context) => [
        for (final e in kLanguages.entries)
          PopupMenuItem(value: e.key, child: Text(e.value)),
      ],
    );
  }
}

// Request status as shown to people.
String statusLabel(dynamic status) {
  switch (status) {
    case 'OPEN':
      return tr('Open');
    case 'MATCHED':
      return tr('Matched');
    case 'SENDER_DONE':
      return tr('Sender confirmed');
    case 'RECEIVER_DONE':
      return tr('Receiver confirmed');
    case 'COMPLETED':
      return tr('Completed');
    case 'DISPUTED':
      return tr('Disputed');
    case 'CANCELLED':
      return tr('Cancelled');
    default:
      return '${status ?? ''}';
  }
}

// "Send" / "Receive" for a request type.
String typeLabel(dynamic type) =>
    type == 'SEND' ? tr('Send') : (type == 'RECEIVE' ? tr('Receive') : '$type');

const Map<String, String> _t = {
  // ---- Common ----
  'Cancel': 'Annuler',
  'Error: {error}': 'Erreur : {error}',
  'Something went wrong: {error}': 'Une erreur est survenue : {error}',
  'Please wait...': 'Veuillez patienter...',
  'Save': 'Enregistrer',
  'Saving...': 'Enregistrement...',
  'Delete': 'Supprimer',
  'Edit': 'Modifier',
  'Send': 'Envoyer',
  'Receive': 'Recevoir',
  'Keep it': 'Garder',
  'All': 'Tout',
  'Yes': 'Oui',
  'Not yet': 'Pas encore',
  'Other': 'Autre',
  'Location': 'Lieu',
  'Profile unavailable': 'Profil indisponible',
  'AZSA user': 'Utilisateur AZSA',

  // ---- Tabs ----
  'Requests': 'Demandes',
  'Marketplace': 'Marché',
  'Rates': 'Taux',
  'Profile': 'Profil',

  // ---- Login ----
  'Create account': 'Créer un compte',
  'Log in': 'Se connecter',
  'Full name': 'Nom complet',
  'Inscription number': "Numéro d'inscription",
  'Email': 'E-mail',
  'Password': 'Mot de passe',
  'Sign up': "S'inscrire",
  'Already have an account? Log in': 'Déjà un compte ? Se connecter',
  'New here? Create an account': 'Nouveau ? Créer un compte',
  'OR': 'OU',
  'Continue with Google': 'Continuer avec Google',
  'Google sign-in failed: {error}': 'Échec de la connexion Google : {error}',
  'By continuing, you agree to our Terms of use and Privacy policy.': "En continuant, vous acceptez nos Conditions d'utilisation et notre Politique de confidentialité.",
  'Terms of use': "Conditions d'utilisation",
  'Privacy policy': 'Politique de confidentialité',
  'Terms and privacy': 'Conditions et confidentialité',
  'Last updated: {date}': 'Dernière mise à jour : {date}',
  'Log out?': 'Se déconnecter ?',
  'Are you sure you want to log out?': 'Voulez-vous vraiment vous déconnecter ?',
  'Log out': 'Se déconnecter',


  // ---- Open requests + filters ----
  'Open requests': 'Demandes ouvertes',
  'No open requests right now.': 'Aucune demande ouverte pour le moment.',
  'No requests match these filters.': 'Aucune demande ne correspond à ces filtres.',
  'Clear filters': 'Effacer les filtres',
  'Match': 'Accepter',
  'Wants to send {amount}': 'Veut envoyer {amount}',
  'Wants to receive {amount}': 'Veut recevoir {amount}',
  'Type': 'Type',
  'Currency': 'Devise',
  'Wilaya': 'Wilaya',
  '{label}: All': '{label} : tout',
  'My requests': 'Mes demandes',
  'Notifications': 'Notifications',
  'No notifications yet.': 'Aucune notification pour le moment.',

  // ---- New request / my requests ----
  'Enter a valid amount': 'Entrez un montant valide',
  'New request': 'Nouvelle demande',
  'What do you want to do?': 'Que voulez-vous faire ?',
  'I want to SEND money': "Je veux ENVOYER de l'argent",
  'I want to RECEIVE money': "Je veux RECEVOIR de l'argent",
  'Amount': 'Montant',
  'Post request': 'Publier la demande',
  'You have no requests yet.': "Vous n'avez pas encore de demandes.",
  'Status: {status}': 'Statut : {status}',
  'Waiting for someone to match': "En attente d'une correspondance",
  'Cancel request': 'Annuler la demande',
  'Cancel this request?': 'Annuler cette demande ?',
  'It will no longer be visible to other users.': 'Elle ne sera plus visible pour les autres utilisateurs.',
  'Request cancelled.': 'Demande annulée.',
  'Could not cancel: {error}': "Impossible d'annuler : {error}",
  'Open': 'Ouverte',
  'Matched': 'Acceptée',
  'Sender confirmed': "Confirmée par l'envoyeur",
  'Receiver confirmed': 'Confirmée par le receveur',
  'Completed': 'Terminée',
  'Disputed': 'En litige',
  'Cancelled': 'Annulée',

  // ---- Chat ----
  'Chat': 'Discussion',
  'Report a problem': 'Signaler un problème',
  'Describe what went wrong...': "Décrivez ce qui s'est mal passé...",
  'Submit': 'Envoyer',
  'Transaction complete! You can now rate each other.': 'Échange terminé ! Vous pouvez maintenant vous évaluer.',
  'Dispute submitted.': 'Litige envoyé.',
  'Thanks for rating!': 'Merci pour votre évaluation !',
  '✅ Transaction completed — thanks for rating!': '✅ Échange terminé — merci pour votre évaluation !',
  '✅ Transaction completed': '✅ Échange terminé',
  'Rate the other person:': "Évaluez l'autre personne :",
  'Optional comment...': 'Commentaire (facultatif)...',
  'Submitting...': 'Envoi...',
  'Submit rating': "Envoyer l'évaluation",
  '⚠️ Dispute opened on this transaction': '⚠️ Un litige a été ouvert sur cet échange',
  'You confirmed. Waiting for the other side...': "Vous avez confirmé. En attente de l'autre personne...",
  'Once the exchange is done outside the app, confirm here.': "Une fois l'échange fait en dehors de l'application, confirmez ici.",
  'I sent the money': "J'ai envoyé l'argent",
  'I received the money': "J'ai reçu l'argent",
  'No messages yet. Say hi!': 'Pas encore de messages. Dites bonjour !',
  'Type a message...': 'Écrire un message...',
  'Send a photo': 'Envoyer une photo',
  'current academic year': 'année universitaire en cours',
  'Ministry': 'Ministère',
  'Récépissé or Carte de séjour': 'Récépissé ou Carte de séjour',
  'Before arrival': "Avant l'arrivée",
  'Give the list of new students to their cités, so the rooms are ready.': 'Donner la liste des nouveaux étudiants à leurs cités, pour que les chambres soient prêtes.',
  'Tell each cité the arrival date in Algeria, and the date and time the students will reach the cité.': "Indiquer à chaque cité la date d'arrivée en Algérie, ainsi que la date et l'heure d'arrivée des étudiants à la cité.",
  'Scan these documents before handing them in (the university keeps the originals): birth certificate, A Level certificate, O Level certificate.': "Scanner ces documents avant de les remettre (l'université garde les originaux) : acte de naissance, certificat A Level, certificat O Level.",
  'Inscription at the Rectorat / DOU (student card)': "Inscription au Rectorat / DOU (carte d'étudiant)",
  'Birth certificate (original + 1 copy)': 'Acte de naissance (original + 1 copie)',
  'O Level certificate (original + 1 copy)': 'Certificat O Level (original + 1 copie)',
  'A Level certificate (original + 1 copy)': 'Certificat A Level (original + 1 copie)',
  'Passport: data page and visa page (1 copy or more)': "Passeport : page d'identité et page du visa (1 copie ou plus)",
  '4 passport photos': "4 photos d'identité",
  'Inscription fee: 200 DA': "Frais d'inscription : 200 DA",
  "You will be given envelopes to take to your faculty, then to your department, where the student cards are printed. If you will study French first, you will also be given an Autorisation d'inscription étudiant étranger to block (reserve) your year.": "On vous donnera des enveloppes à apporter à votre faculté, puis à votre département, où les cartes d'étudiant sont imprimées. Si vous étudiez d'abord le français, on vous donnera aussi une Autorisation d'inscription étudiant étranger pour bloquer (réserver) votre année.",
  'Documents from the Educational Attaché': "Documents de l'Attaché d'éducation",
  'Medical tests': 'Examens médicaux',
  'First get the prescription from your residence clinic.': "D'abord, obtenez l'ordonnance à la clinique de votre résidence.",
  'Then get the medical certificate from the cité clinic.': 'Ensuite, obtenez le certificat médical à la clinique de la cité.',
  'Hébergement (residence)': 'Hébergement (résidence)',
  'Birth certificate': 'Acte de naissance',
  'Passport copy': 'Copie du passeport',
  '2 passport photos': "2 photos d'identité",
  'Medical certificate from your residence clinic': 'Certificat médical de la clinique de votre résidence',
  'Then fill in your student information in the app: name, date of entry, passport number, issue and expiry dates, programme, current year and phone number.': "Ensuite, remplissez vos informations d'étudiant dans l'application : nom, date d'entrée, numéro de passeport, dates de délivrance et d'expiration, filière, année en cours et numéro de téléphone.",
  'Police (Récépissé or Carte de séjour)': 'Police (Récépissé ou Carte de séjour)',
  'Quittance: 20,000 DA (the amount can change from one academic year to another)': "Quittance : 20 000 DA (le montant peut changer d'une année universitaire à l'autre)",
  'Birth certificate copies': "Copies de l'acte de naissance",
  'Passport copies': 'Copies du passeport',
  '10 clear passport photos': "10 photos d'identité nettes",
  'Medical certificate: original + 3 copies': 'Certificat médical : original + 3 copies',
  'original + 3 copies': 'original + 3 copies',
  'Birth certificate: original + 1 copy': 'Acte de naissance : original + 1 copie',
  'French or Arabic course': "Cours de français ou d'arabe",
  '1 passport copy': '1 copie du passeport',
  '1 A Level copy': '1 copie du A Level',
  '1 birth certificate': '1 acte de naissance',
  '1 A4 khaki envelope': '1 enveloppe kraft A4',
  'SIM card (Ooredoo, Djezzy or Mobilis)': 'Carte SIM (Ooredoo, Djezzy ou Mobilis)',
  'Passport': 'Passeport',
  'Poste account (CCP), then BaridiMob': 'Compte postal (CCP), puis BaridiMob',
  'Algerian phone number': 'Numéro de téléphone algérien',
  'For BaridiMob you need your CCP account.': 'Pour BaridiMob, il faut votre compte CCP.',
  'Algerian bourse': 'Bourse algérienne',
  'Cheque book (from your Poste account)': 'Chéquier (de votre compte postal)',
  'A Level certificate': 'Certificat A Level',
  'O Level certificate': 'Certificat O Level',
  "Attestation d'inscription (French course)": "Attestation d'inscription (cours de français)",
  'Carte Chifa (medical card)': 'Carte Chifa (carte médicale)',
  'Passport photos': "Photos d'identité",
  'Blood group': 'Groupe sanguin',
  'Tram card': 'Carte de tram',
  'Passport photo': "Photo d'identité",
  'Application form': 'Formulaire de demande',
  'These are the standard steps. They can vary from one wilaya to another.': "Ce sont les étapes habituelles. Elles peuvent varier d'une wilaya à l'autre.",
  'Questions? Contact your current Governor, the current AZSA President or the administration.': "Des questions ? Contactez votre Gouverneur actuel, le Président actuel de l'AZSA ou l'administration.",
  'Documents to bring': 'Documents à apporter',
  'To do': 'À faire',
  'Ask for the attestation de bourse': "Demander l'attestation de bourse",
  'Fill in my student information': 'Remplir mes informations',
  'More information': "Plus d'informations",
  'Typed by the Educational Attaché.': "Saisi par l'Attaché d'éducation.",
  'This rate may be out of date.': 'Ce taux est peut-être dépassé.',
  'Buy = what you get when you sell foreign currency. Sell = what you pay to buy it. The parallel rate is the Algiers rate (Square Port-Saïd), checked every hour from several public sources. It is indicative: always agree the exact rate with the other person before exchanging anything.': "Achat = ce que vous recevez en vendant des devises. Vente = ce que vous payez pour en acheter. Le taux parallèle est celui d'Alger (Square Port-Saïd), vérifié chaque heure auprès de plusieurs sources publiques. Il est indicatif : mettez-vous toujours d'accord sur le taux exact avec l'autre personne avant tout échange.",
  'Square Port-Saïd · Algiers': 'Square Port-Saïd · Alger',
  "Only if the automatic rate is wrong: type today's Algiers square rate (DA). It replaces the automatic rate for 24 hours.": "Seulement si le taux automatique est faux : saisissez le taux du square d'Alger du jour (DA). Il remplace le taux automatique pendant 24 heures.",
  'Percentage': 'Pourcentage',
  'Percentage: {percent}': 'Pourcentage : {percent}',
  '{percent} of {amount} = {part}': '{percent} de {amount} = {part}',
  'You receive this in dinars.': 'Vous recevez ce montant en dinars.',
  'You pay this in dinars.': 'Vous payez ce montant en dinars.',
  'online': 'en ligne',
  'offline': 'hors ligne',
  'View photo': 'Voir la photo',
  'Change photo': 'Changer la photo',
  'Share my location': 'Partager ma position',
  'Download chat as text': 'Télécharger la discussion (texte)',
  'This photo is too big (max 5 MB).': 'Cette photo est trop lourde (5 Mo max).',
  'Could not send photo: {error}': "Impossible d'envoyer la photo : {error}",
  'Share location': 'Partager la position',
  'Send your current location to {name}?': 'Envoyer votre position actuelle à {name} ?',
  'the other person': "l'autre personne",
  'Please turn on location (GPS) on your phone.': 'Activez la localisation (GPS) sur votre téléphone.',
  'Location permission was refused.': "L'autorisation de localisation a été refusée.",
  'Could not send location: {error}': "Impossible d'envoyer la position : {error}",
  'Could not open the map.': "Impossible d'ouvrir la carte.",
  '📍 My location (tap to open map)': '📍 Ma position (touchez pour ouvrir la carte)',
  '📍 Location (tap to open map)': '📍 Position (touchez pour ouvrir la carte)',
  'Chat saved.': 'Discussion enregistrée.',
  'Could not save the chat: {error}': "Impossible d'enregistrer la discussion : {error}",
  "You can't send messages in this chat.": 'Vous ne pouvez pas envoyer de messages dans cette discussion.',

  // ---- Profiles ----
  'No ratings yet': "Pas encore d'évaluation",
  '{count} completed': '{count} terminés',
  'New member': 'Nouveau membre',
  'Report user': "Signaler l'utilisateur",
  'Block user': "Bloquer l'utilisateur",
  'Unblock user': "Débloquer l'utilisateur",
  'Rating': 'Note',
  '★ {avg} ({count} reviews)': '★ {avg} ({count} avis)',
  'Completed transactions': 'Échanges terminés',
  'Trust score': 'Score de confiance',
  'Member since': 'Membre depuis',
  'Verified': 'Vérifié',
  'Reviews': 'Avis',
  'No reviews yet.': "Pas encore d'avis.",
  'Scam or fraud': 'Arnaque ou fraude',
  'Harassment': 'Harcèlement',
  'Fake profile': 'Faux profil',
  'Inappropriate content': 'Contenu inapproprié',
  'Details (optional)': 'Détails (facultatif)',
  'Send report': 'Envoyer le signalement',
  "Thanks, we'll review this report.": 'Merci, nous allons examiner ce signalement.',
  'You already reported this user. We are reviewing it.': 'Vous avez déjà signalé cet utilisateur. Nous examinons le signalement.',
  'Could not send report: {error}': "Impossible d'envoyer le signalement : {error}",
  'this user': 'cet utilisateur',
  'Block {name}?': 'Bloquer {name} ?',
  "You won't see each other's requests or listings, and you can't message each other. Open transactions can still be confirmed or disputed. You can unblock later in your profile.": "Vous ne verrez plus vos demandes et annonces respectives et ne pourrez plus vous écrire. Les échanges en cours peuvent toujours être confirmés ou contestés. Vous pourrez débloquer plus tard dans votre profil.",
  'Block': 'Bloquer',
  '{name} blocked.': '{name} a été bloqué.',
  '{name} unblocked.': '{name} a été débloqué.',
  'Blocked users': 'Utilisateurs bloqués',
  'You have not blocked anyone.': "Vous n'avez bloqué personne.",
  'Unblock': 'Débloquer',
  'Could not load blocked users: {error}': 'Impossible de charger les utilisateurs bloqués : {error}',
  'My profile': 'Mon profil',
  'Tap the picture to change it': 'Touchez la photo pour la changer',
  'This is how others see you:': 'Voici comment les autres vous voient :',
  "Your name and student ID come from sign-up and can't be changed here. Your student ID is never shown to other users.": "Votre nom et votre numéro d'étudiant viennent de l'inscription et ne peuvent pas être modifiés ici. Votre numéro d'étudiant n'est jamais montré aux autres.",
  'e.g. Annaba': 'ex. Annaba',
  'Location (city / area)': 'Lieu (ville / quartier)',
  'Could not save: {error}': "Impossible d'enregistrer : {error}",
  'Profile saved.': 'Profil enregistré.',
  'Get verified': 'Se faire vérifier',
  'Language': 'Langue',
  'Theme': 'Thème',
  'System': 'Système',
  'Light': 'Clair',
  'Dark': 'Sombre',
  'Delete my account': 'Supprimer mon compte',
  'Deleting...': 'Suppression...',
  'Delete forever': 'Supprimer définitivement',
  'This cannot be undone.\n\nDeleted: your profile, photos, listings, open requests, notifications and blocks.\n\nKept for the other person: finished transactions, chats and ratings (you will show as "AZSA user").\n\nType DELETE to confirm.': 'Cette action est irréversible.\n\nSupprimés : votre profil, vos photos, annonces, demandes ouvertes, notifications et blocages.\n\nConservés pour l\'autre personne : échanges terminés, discussions et évaluations (vous apparaîtrez comme « Utilisateur AZSA »).\n\nTapez DELETE pour confirmer.',
  'Finish or resolve your open transactions first.': "Terminez ou réglez d'abord vos échanges en cours.",
  'Could not delete account: {error}': 'Impossible de supprimer le compte : {error}',
  'Your account has been deleted.': 'Votre compte a été supprimé.',

  // ---- Verification ----
  'Could not load: {error}': 'Impossible de charger : {error}',
  'Choose a photo of your student card first': "Choisissez d'abord une photo de votre carte d'étudiant",
  'Could not send: {error}': "Impossible d'envoyer : {error}",
  'You are verified': 'Vous êtes vérifié',
  'Other users can see the blue tick next to your name.': 'Les autres utilisateurs voient la coche bleue à côté de votre nom.',
  'Under review': 'En cours de vérification',
  'We received your student card and will check it soon. You will see a blue tick here once it is approved.': "Nous avons reçu votre carte d'étudiant et la vérifierons bientôt. Vous verrez une coche bleue ici une fois approuvée.",
  'Check again': 'Vérifier à nouveau',
  'Your last request was not approved. You can send a new photo.': "Votre dernière demande n'a pas été approuvée. Vous pouvez envoyer une nouvelle photo.",
  'Your last request was not approved: {note}': "Votre dernière demande n'a pas été approuvée : {note}",
  'A blue tick tells other students that we checked your student card.': "La coche bleue indique aux autres étudiants que nous avons vérifié votre carte d'étudiant.",
  'Send a clear photo of your student card. Your name and student number must be readable and must match your account. Only the AZSA team can view this photo. It is used for this check and is never shown to other users.': "Envoyez une photo nette de votre carte d'étudiant. Votre nom et votre numéro doivent être lisibles et correspondre à votre compte. Seule l'équipe AZSA peut voir cette photo. Elle sert uniquement à cette vérification et n'est jamais montrée aux autres.",
  'Tap to choose a photo of your student card': "Touchez pour choisir une photo de votre carte d'étudiant",
  'Sending...': 'Envoi...',
  'Send for review': 'Envoyer pour vérification',

  // ---- Rates ----
  'Exchange rates': 'Taux de change',
  'Buy': 'Achat',
  'Sell': 'Vente',
  'Bank': 'Banque',
  'Parallel market': 'Marché parallèle',
  'Parallel market is {pct}% higher than the bank': 'Le marché parallèle est {pct} % plus haut que la banque',
  'Parallel market is {pct}% lower than the bank': 'Le marché parallèle est {pct} % plus bas que la banque',
  'Updated {ago}': 'Mis à jour {ago}',
  'unknown': 'inconnu',
  'just now': "à l'instant",
  '{n} min ago': 'il y a {n} min',
  '{n} h ago': 'il y a {n} h',
  '{n} days ago': 'il y a {n} jours',
  'No rates available yet.': 'Aucun taux disponible pour le moment.',
  'Could not load rates: {error}': 'Impossible de charger les taux : {error}',
  'Buy = what you get when you sell foreign currency. Sell = what you pay to buy it. These rates are indicative and updated by hand, so always agree the exact rate with the other person before exchanging anything.': "Achat = ce que vous recevez en vendant des devises. Vente = ce que vous payez pour en acheter. Ces taux sont indicatifs : mettez-vous toujours d'accord sur le taux exact avec l'autre personne avant tout échange.",

  // ---- Marketplace ----
  'Electronics & gadgets': 'Électronique et gadgets',
  'Clothes & apparel': 'Vêtements',
  'Books & study materials': "Livres et fournitures d'études",
  'Furniture & home': 'Meubles et maison',
  'Food & drinks': 'Nourriture et boissons',
  'Beauty & personal care': 'Beauté et soins',
  'Sports & fitness': 'Sport et fitness',
  'Services': 'Services',
  'My listings': 'Mes annonces',
  "Couldn't open that link": "Impossible d'ouvrir ce lien",
  'Price on request': 'Prix sur demande',
  'Seller': 'Vendeur',
  'SOLD': 'VENDU',
  'Categories': 'Catégories',
  'Search listings': 'Rechercher des annonces',
  'Showing: {filter}': 'Affichage : {filter}',
  'Show all': 'Tout afficher',
  'You have no listings yet.': "Vous n'avez pas encore d'annonces.",
  'No listings yet. Be the first!': 'Pas encore d\'annonces. Soyez le premier !',
  'No listings match your search.': 'Aucune annonce ne correspond à votre recherche.',
  'Could not load listings: {error}': 'Impossible de charger les annonces : {error}',
  'Listing': 'Annonce',
  'Mark as available': 'Marquer comme disponible',
  'Mark as sold': 'Marquer comme vendu',
  'Your listing is available again.': 'Votre annonce est de nouveau disponible.',
  'Marked as sold. Other students can no longer see it.': 'Marqué comme vendu. Les autres étudiants ne le voient plus.',
  'Could not update: {error}': 'Impossible de mettre à jour : {error}',
  'Delete this listing?': 'Supprimer cette annonce ?',
  'This cannot be undone.': 'Cette action est irréversible.',
  'Listing deleted.': 'Annonce supprimée.',
  'Could not delete: {error}': 'Impossible de supprimer : {error}',
  'Contact seller': 'Contacter le vendeur',
  'Edit listing': "Modifier l'annonce",
  'New listing': 'Nouvelle annonce',
  'Photos ({count}/3)': 'Photos ({count}/3)',
  'Add photos': 'Ajouter des photos',
  'Title *': 'Titre *',
  'Category *': 'Catégorie *',
  'Description': 'Description',
  'Price in DA (optional)': 'Prix en DA (facultatif)',
  'WhatsApp number or contact link': 'Numéro WhatsApp ou lien de contact',
  '0555 12 34 56 or instagram.com/yourname': '0555 12 34 56 ou instagram.com/votrenom',
  'Numbers starting with 0 become WhatsApp links for Algeria (+213).': 'Les numéros commençant par 0 deviennent des liens WhatsApp pour l\'Algérie (+213).',
  'Uploading photos...': 'Envoi des photos...',
  'Save changes': 'Enregistrer les modifications',
  'Post listing': "Publier l'annonce",
  'Title is required': 'Le titre est obligatoire',
  'Please choose a category': 'Choisissez une catégorie',
  'Price must be a number': 'Le prix doit être un nombre',
  'Only 3 photos are allowed per listing.': 'Seulement 3 photos sont autorisées par annonce.',
  // Profile set-up page and profile bar
  'Complete your profile': 'Complétez votre profil',
  'Set up your profile': 'Configurez votre profil',
  'Add a photo and your wilaya so other students can trust you.': 'Ajoutez une photo et votre wilaya pour que les autres étudiants puissent vous faire confiance.',
  'Tap to add a photo (required)': 'Touchez pour ajouter une photo (obligatoire)',
  'Name': 'Nom',
  'Your name is missing. Contact AZSA support to add it.': 'Votre nom est manquant. Contactez le support AZSA pour l\'ajouter.',
  'Wilaya (required)': 'Wilaya (obligatoire)',
  'City or area (optional)': 'Ville ou quartier (facultatif)',
  'Your profile could not be saved. Please contact AZSA support.': 'Votre profil n\'a pas pu être enregistré. Contactez le support AZSA.',
  'Could not load your profile. Check your connection.': 'Impossible de charger votre profil. Vérifiez votre connexion.',
  'Try again': 'Réessayer',

  'Add a photo, your wilaya and your phone number.':
      'Ajoutez une photo, votre wilaya et votre numéro de téléphone.',
  'Phone number (required)':
      'Numéro de téléphone (obligatoire)',
  'Starts with +213 or +263. Only you, the Educational Attaché and your Governor can see it.':
      'Commence par +213 ou +263. Seuls vous, l\'Attaché d\'éducation et votre Gouverneur pouvez le voir.',
  'Use +213 or +263 followed by 8 to 10 digits.':
      'Utilisez +213 ou +263 suivi de 8 à 10 chiffres.',
  'Your name comes from sign-up and can\'t be changed here.':
      'Votre nom vient de l\'inscription et ne peut pas être modifié ici.',
  'Phone (e.g. +213555123456)':
      'Téléphone (ex. +213555123456)',
  'Only you, the Educational Attaché and the Governor of your wilaya can see this. Other students never see your inscription number or phone.':
      'Seuls vous, l\'Attaché d\'éducation et le Gouverneur de votre wilaya pouvez voir ceci. Les autres étudiants ne voient jamais votre numéro d\'inscription ni votre téléphone.',
  '[Location]':
      '[Position]',
  'This chat is closed.':
      'Cette discussion est fermée.',
  'Rate':
      'Noter',
  'New unmatched requests':
      'Nouvelles demandes sans correspondance',
  'Student space':
      'Espace étudiant',
  'General':
      'Général',
  'Messages, matches and requests':
      'Messages, correspondances et demandes',
  'Emergency alerts':
      'Alertes d\'urgence',
  'Urgent alerts from the Educational Attaché':
      'Alertes urgentes de l\'Attaché d\'éducation',
  'New request notifications':
      'Notifications de nouvelles demandes',
  'A notification each time someone posts a request.':
      'Une notification chaque fois que quelqu\'un publie une demande.',
  'Suggested matches':
      'Correspondances suggérées',
  'A match is available. Accept or decline':
      'Une correspondance est disponible. Acceptez ou refusez',
  'Your request: {type}':
      'Votre demande : {type}',
  'Expires in {hours} h':
      'Expire dans {hours} h',
  'You accepted. Waiting for the other student.':
      'Vous avez accepté. En attente de l\'autre étudiant.',
  'Accepted. Waiting for the other student.':
      'Accepté. En attente de l\'autre étudiant.',
  'Suggestion declined.':
      'Suggestion refusée.',
  'Decline':
      'Refuser',
  'Accept':
      'Accepter',
  'Gender':
      'Sexe',
  'Male':
      'Homme',
  'Female':
      'Femme',
  'Bank account number (20 digits)':
      'Numéro de compte bancaire (20 chiffres)',
  'Only the Educational Attaché and your Governor can see your bank account number.':
      'Seuls l\'Attaché d\'éducation et votre Gouverneur peuvent voir votre numéro de compte bancaire.',
  'Exactly 20 digits':
      'Exactement 20 chiffres',
  'Passport number':
      'Numéro de passeport',
  'Only you and the Educational Attaché can see your passport number.':
      'Seuls vous et l\'Attaché d\'éducation pouvez voir votre numéro de passeport.',
  '6 to 12 letters and digits':
      '6 à 12 lettres et chiffres',
  'Could not open it.':
      'Impossible de l\'ouvrir.',
  'Call':
      'Appeler',
  'Contacts':
      'Contacts',
  'Manage contacts':
      'Gérer les contacts',
  'Contact the Educational Attaché':
      'Contacter l\'Attaché d\'éducation',
  'No contact yet.':
      'Aucun contact pour l\'instant.',
  'Contact your Governor':
      'Contacter votre Gouverneur',
  'Choose your wilaya in your profile first.':
      'Choisissez d\'abord votre wilaya dans votre profil.',
  'Governors\' contacts':
      'Contacts des Gouverneurs',
  'Add a contact':
      'Ajouter un contact',
  'Edit contact':
      'Modifier le contact',
  'Delete this contact?':
      'Supprimer ce contact ?',
  'Educational Attaché':
      'Attaché d\'éducation',
  'Governor':
      'Gouverneur',
  'Write a name.':
      'Écrivez un nom.',
  'Choose the wilaya.':
      'Choisissez la wilaya.',
  'Give a phone number or an email.':
      'Donnez un numéro de téléphone ou un e-mail.',
  'Kind':
      'Type',
  'Phone':
      'Téléphone',
  'Order':
      'Ordre',
  'Guide for new students':
      'Guide pour les nouveaux étudiants',
  'Coming soon':
      'Bientôt disponible',
  '{count} items':
      '{count} éléments',
  'Police':
      'Police',
  'Bourse':
      'Bourse',
  'Medical':
      'Médical',
  'Add':
      'Ajouter',
  'Open the PDF':
      'Ouvrir le PDF',
  'Write a title.':
      'Écrivez un titre.',
  'Delete this item?':
      'Supprimer cet élément ?',
  'Title':
      'Titre',
  'Text':
      'Texte',
  'PDF attached':
      'PDF joint',
  'No PDF (optional)':
      'Pas de PDF (facultatif)',
  'Remove':
      'Retirer',
  'Help':
      'Aide',
  'Search the questions':
      'Rechercher dans les questions',
  'No questions yet.':
      'Aucune question pour l\'instant.',
  'Nothing found.':
      'Aucun résultat.',
  'Write the question and the answer.':
      'Écrivez la question et la réponse.',
  'Delete this question?':
      'Supprimer cette question ?',
  'Question':
      'Question',
  'Answer':
      'Réponse',
  'Waiting for an answer':
      'En attente de réponse',
  'Confirmed':
      'Confirmé',
  'Another time proposed':
      'Autre horaire proposé',
  'Declined':
      'Refusé',
  'Appointments':
      'Rendez-vous',
  'Ask for an appointment':
      'Demander un rendez-vous',
  'Reason':
      'Motif',
  'Write the reason (at least 3 letters).':
      'Écrivez le motif (au moins 3 lettres).',
  'Request sent to the Educational Attaché.':
      'Demande envoyée à l\'Attaché d\'éducation.',
  'Ask the Educational Attaché for an appointment: choose a date, a time and the reason.':
      'Demandez un rendez-vous à l\'Attaché d\'éducation : choisissez une date, une heure et le motif.',
  'Asked for: {date}':
      'Demandé pour : {date}',
  'Proposed: {date}':
      'Proposé : {date}',
  'Note: {note}':
      'Note : {note}',
  'Cancel this appointment?':
      'Annuler ce rendez-vous ?',
  'Cancel appointment':
      'Annuler le rendez-vous',
  'Accept this time':
      'Accepter cet horaire',
  'Propose another time':
      'Proposer un autre horaire',
  'Note for the student':
      'Note pour l\'étudiant',
  'Note for the student (optional)':
      'Note pour l\'étudiant (facultatif)',
  'Only open appointments':
      'Rendez-vous en cours seulement',
  'No appointments.':
      'Aucun rendez-vous.',
  'Meet the Educational Attaché':
      'Rencontrer l\'Attaché d\'éducation',
  'The Educational Attaché and your Governor':
      'L\'Attaché d\'éducation et votre Gouverneur',
  'Police, bank, bourse, medical':
      'Police, banque, bourse, médical',
  'Frequently asked questions':
      'Questions fréquentes',
  'Date of entry into Algeria':
      'Date d\'entrée en Algérie',
  'The date of entry into Algeria is required.':
      'La date d\'entrée en Algérie est obligatoire.',
  'You need two things: the date you entered Algeria, and a clear scan or photo of your passport (photo page). The Educational Attaché checks it and issues your attestation here. Your passport scan is deleted after the attestation is issued.':
      'Il vous faut deux choses : la date de votre entrée en Algérie et un scan ou une photo nette de votre passeport (page photo). L\'Attaché d\'éducation le vérifie et délivre votre attestation ici. Le scan de votre passeport est supprimé après la délivrance de l\'attestation.',
  'Your documents':
      'Vos documents',
  'Please read this before you upload a personal document.':
      'Veuillez lire ceci avant d\'envoyer un document personnel.',
  'I have read this and I agree.':
      'J\'ai lu et j\'accepte.',
  'Continue':
      'Continuer',
  'Not now':
      'Pas maintenant',
  'Delete this poster?':
      'Supprimer cette affiche ?',
  'Posters':
      'Affiches',
  'Add poster':
      'Ajouter une affiche',
  '{count} of 4 active. Each active poster has its own position (1 is shown first). Images should be 16:9.':
      '{count} sur 4 actives. Chaque affiche active a sa propre position (1 est affichée en premier). Les images doivent être en 16:9.',
  'Active, position {n}':
      'Active, position {n}',
  'Not active':
      'Inactive',
  'Choose an image.':
      'Choisissez une image.',
  'The link must start with https://':
      'Le lien doit commencer par https://',
  'Another active poster already uses position {n}. Choose another position or turn that poster off first.':
      'Une autre affiche active utilise déjà la position {n}. Choisissez une autre position ou désactivez d\'abord cette affiche.',
  'Edit poster':
      'Modifier l\'affiche',
  'Tap to choose an image (16:9)':
      'Touchez pour choisir une image (16:9)',
  'Link (optional)':
      'Lien (facultatif)',
  'Start: {d}':
      'Début : {d}',
  'End: {d}':
      'Fin : {d}',
  'Position':
      'Position',
  'Active':
      'Active',
  'This cannot be undone.\n\nDeleted: your profile, all your photos and files (also the photos you sent in chats, your results, passport and attestations), your student record, listings, open requests, notifications and blocks.\n\nKept for the other person: finished transactions, chat text messages and ratings (you will show as "AZSA user").\n\nType DELETE to confirm.':
      'Cette action est définitive.\n\nSupprimés : votre profil, toutes vos photos et fichiers (aussi les photos envoyées dans les discussions, vos résultats, passeport et attestations), votre fiche étudiant, vos annonces, demandes ouvertes, notifications et blocages.\n\nConservés pour l\'autre personne : les transactions terminées, les messages texte et les notes (vous apparaîtrez comme « AZSA user »).\n\nTapez DELETE pour confirmer.',
  'Could not open the file: {error}':
      'Impossible d\'ouvrir le fichier : {error}',
  'No student record':
      'Pas de fiche étudiant',
  'Staff ({role})':
      'Personnel ({role})',
  'Governor of {wilaya}':
      'Gouverneur de {wilaya}',
  'Students':
      'Étudiants',
  'Attestation requests':
      'Demandes d\'attestation',
  'Final list of students':
      'Liste finale des étudiants',
  'Access log':
      'Journal d\'accès',
  'Only requests still to do':
      'Seulement les demandes à traiter',
  'No requests.':
      'Aucune demande.',
  'Please choose a PDF file.':
      'Veuillez choisir un fichier PDF.',
  'This file is too big (max 10 MB).':
      'Ce fichier est trop volumineux (max 10 Mo).',
  'Attestation issued. The student was notified.':
      'Attestation délivrée. L\'étudiant a été prévenu.',
  'Reject request':
      'Refuser la demande',
  'Note for the student (required)':
      'Note pour l\'étudiant (obligatoire)',
  'Reject':
      'Refuser',
  'Request rejected. The student was notified.':
      'Demande refusée. L\'étudiant a été prévenu.',
  'Delete the passport scan now?':
      'Supprimer le scan du passeport maintenant ?',
  'Passport scan deleted.':
      'Scan du passeport supprimé.',
  'Attestation request':
      'Demande d\'attestation',
  'Status':
      'Statut',
  'Sent on':
      'Envoyé le',
  'Open passport (recorded in the access log)':
      'Ouvrir le passeport (enregistré dans le journal d\'accès)',
  'Passport scan deleted on {date}':
      'Scan du passeport supprimé le {date}',
  'Marked as being reviewed.':
      'Marquée comme en cours d\'examen.',
  'Mark as being reviewed':
      'Marquer comme en cours d\'examen',
  'Upload attestation (PDF) and issue':
      'Envoyer l\'attestation (PDF) et la délivrer',
  'Reject with a note':
      'Refuser avec une note',
  'Open issued attestation':
      'Ouvrir l\'attestation délivrée',
  'Delete passport scan now':
      'Supprimer le scan du passeport maintenant',
  'Otherwise it is deleted automatically 30 days after the attestation is issued.':
      'Sinon, il est supprimé automatiquement 30 jours après la délivrance de l\'attestation.',
  'Academic year':
      'Année universitaire',
  'All years':
      'Toutes les années',
  '{count} students':
      '{count} étudiants',
  'Choose wilaya and year to compile':
      'Choisissez la wilaya et l\'année pour compiler',
  'Compile results PDF':
      'Compiler les résultats en PDF',
  'No students.':
      'Aucun étudiant.',
  'Program':
      'Filière',
  'Level':
      'Niveau',
  'Current academic year':
      'Année universitaire en cours',
  'Start year':
      'Année de début',
  'Expected finish year':
      'Année de fin prévue',
  'Results':
      'Résultats',
  'Opening a file is recorded in the access log.':
      'L\'ouverture d\'un fichier est enregistrée dans le journal d\'accès.',
  'No results uploaded yet.':
      'Aucun résultat envoyé pour l\'instant.',
  'Compile results':
      'Compiler les résultats',
  'The PDF has a cover page with the list of students, then each student\'s results. Big wilayas are split into several parts. Each link works for 1 hour.':
      'Le PDF a une page de garde avec la liste des étudiants, puis les résultats de chaque étudiant. Les grandes wilayas sont divisées en plusieurs parties. Chaque lien fonctionne pendant 1 heure.',
  '{count} students, {parts} part(s).':
      '{count} étudiants, {parts} partie(s).',
  'Part {n}':
      'Partie {n}',
  'Ready. Tap Open.':
      'Prêt. Touchez Ouvrir.',
  'Building... this can take a minute.':
      'Création en cours... cela peut prendre une minute.',
  'Not built yet':
      'Pas encore créé',
  'Build':
      'Créer',
  'Could not build: {error}':
      'Création impossible : {error}',
  'This export contains bank account numbers. It will be recorded in the access log. Continue?':
      'Cet export contient des numéros de compte bancaire. Il sera enregistré dans le journal d\'accès. Continuer ?',
  'Export':
      'Exporter',
  'Students sorted by wilaya and name. Columns: number, last name, first name, inscription number, wilaya, program, level, academic year, start year, expected finish year, phone, and the bank account if you choose it. The link works for 1 hour.':
      'Étudiants triés par wilaya et par nom. Colonnes : numéro, nom, prénom, numéro d\'inscription, wilaya, filière, niveau, année universitaire, année de début, année de fin prévue, téléphone, et le compte bancaire si vous le choisissez. Le lien fonctionne pendant 1 heure.',
  'Include the bank account column':
      'Ajouter la colonne du compte bancaire',
  'Recorded in the access log.':
      'Enregistré dans le journal d\'accès.',
  'Building...':
      'Création...',
  'Export as PDF':
      'Exporter en PDF',
  'Export as CSV (Excel)':
      'Exporter en CSV (Excel)',
  'Nothing recorded yet.':
      'Rien d\'enregistré pour l\'instant.',
  'Automatic cleanup':
      'Nettoyage automatique',
  'deleted account':
      'compte supprimé',
  'Type at least 2 letters or choose a wilaya.':
      'Tapez au moins 2 lettres ou choisissez une wilaya.',
  'Search students':
      'Rechercher des étudiants',
  'Name or inscription number':
      'Nom ou numéro d\'inscription',
  'Searching...':
      'Recherche...',
  'Search':
      'Rechercher',
  'Search by name, inscription number or wilaya. At most 50 results.':
      'Recherchez par nom, numéro d\'inscription ou wilaya. 50 résultats au maximum.',
  'Student not found':
      'Étudiant introuvable',
  'Opening this page is recorded in the access log.':
      'L\'ouverture de cette page est enregistrée dans le journal d\'accès.',
  'Contact':
      'Contact',
  'Student record':
      'Fiche étudiant',
  'Private information':
      'Informations privées',
  'Bank account':
      'Compte bancaire',
  'Dashboard':
      'Tableau de bord',
  'Total students':
      'Total des étudiants',
  '{count} with a student record':
      '{count} avec une fiche étudiant',
  'Write a title and a message.':
      'Écrivez un titre et un message.',
  'Send this emergency alert to EVERY user now? Their phones will ring with the alarm sound.':
      'Envoyer cette alerte d\'urgence à TOUS les utilisateurs maintenant ? Leurs téléphones sonneront avec le son d\'alarme.',
  'Send to everyone':
      'Envoyer à tout le monde',
  'Alert sent to {count} phones.':
      'Alerte envoyée à {count} téléphones.',
  'Emergency alert':
      'Alerte d\'urgence',
  'Use this only for real emergencies. The alert goes to every user as a high-priority notification and is saved in the app.':
      'À utiliser uniquement pour de vraies urgences. L\'alerte est envoyée à tous les utilisateurs comme notification prioritaire et elle est enregistrée dans l\'application.',
  'Message':
      'Message',
  'Send the alert':
      'Envoyer l\'alerte',
  'Past alerts':
      'Alertes précédentes',
  'Alerts':
      'Alertes',
  'No alerts.':
      'Aucune alerte.',
  'Hide':
      'Masquer',
  'Results tracker':
      'Suivi des résultats',
  'Semester':
      'Semestre',
  '{done} of {total} have uploaded their results':
      '{done} sur {total} ont envoyé leurs résultats',
  'Uploaded on {date}':
      'Envoyé le {date}',
  'Not uploaded yet':
      'Pas encore envoyé',
  'No student record yet':
      'Pas encore de fiche étudiant',
  'Everyone has filled in their student record.':
      'Tout le monde a rempli sa fiche étudiant.',
  '{count} users of your wilaya have not filled in their student record.':
      '{count} utilisateurs de votre wilaya n\'ont pas rempli leur fiche étudiant.',
  'No phone number':
      'Pas de numéro de téléphone',
  'Bank accounts':
      'Comptes bancaires',
  'View only. Opening this list is recorded in the access log.':
      'Consultation seulement. L\'ouverture de cette liste est enregistrée dans le journal d\'accès.',
  'Not given yet':
      'Pas encore donné',
  'Choose PDF':
      'Choisir un PDF',
  'Could not open the file.':
      'Impossible d\'ouvrir le fichier.',
  'My student record':
      'Ma fiche étudiant',
  'Program, level, year, wilaya':
      'Filière, niveau, année, wilaya',
  'My results':
      'Mes résultats',
  'Upload your results (PDF)':
      'Envoyez vos résultats (PDF)',
  'Attestation de bourse':
      'Attestation de bourse',
  'Ask for it and download it':
      'La demander et la télécharger',
  'Who can see my documents':
      'Qui peut voir mes documents',
  'You will be asked before your first upload.':
      'On vous le demandera avant votre premier envoi.',
  'You agreed on {date}.':
      'Vous avez accepté le {date}.',
  'Record saved.':
      'Fiche enregistrée.',
  'Required':
      'Obligatoire',
  'First name':
      'Prénom',
  'Last name':
      'Nom',
  'Program (e.g. Civil engineering)':
      'Filière (ex. Génie civil)',
  'The finish year cannot be before the start year.':
      'L\'année de fin ne peut pas être avant l\'année de début.',
  'Save my record':
      'Enregistrer ma fiche',
  'Upload results':
      'Envoyer des résultats',
  'PDF only, max 10 MB.':
      'PDF uniquement, max 10 Mo.',
  'Results uploaded.':
      'Résultats envoyés.',
  'Could not upload: {error}':
      'Envoi impossible : {error}',
  'Delete this file?':
      'Supprimer ce fichier ?',
  'Uploading...':
      'Envoi...',
  'Please choose a photo (JPG, PNG) or a PDF.':
      'Veuillez choisir une photo (JPG, PNG) ou un PDF.',
  'Request sent.':
      'Demande envoyée.',
  'You already have a request in progress':
      'Vous avez déjà une demande en cours',
  'Ask for an attestation':
      'Demander une attestation',
  'Download my attestation':
      'Télécharger mon attestation',
  'All wilayas':
      'Toutes les wilayas',
  'Semester 1':
      'Semestre 1',
  'Semester 2':
      'Semestre 2',
  'Whole year':
      'Année entière',
  'Preparatory / language year':
      'Année préparatoire / de langue',
  'Engineering':
      'Ingénieur',
  'Doctorate':
      'Doctorat',
  'Sent, waiting':
      'Envoyée, en attente',
  'Being reviewed':
      'En cours d\'examen',
  'Issued':
      'Délivrée',
  'Not accepted':
      'Non acceptée',
  'Opened results':
      'Résultats ouverts',
  'Opened passport':
      'Passeport ouvert',
  'Deleted passport':
      'Passeport supprimé',
  'Compiled results':
      'Résultats compilés',
  'Exported final list':
      'Liste finale exportée',
  'Exported final list with bank accounts':
      'Liste finale exportée avec les comptes bancaires',
  'Opened student details (bank, passport number)':
      'Détails d\'un étudiant ouverts (banque, numéro de passeport)',
  'Opened a bank account':
      'Compte bancaire ouvert',
  'Opened the bank account list':
      'Liste des comptes bancaires ouverte',
  'Opened the results tracker':
      'Suivi des résultats ouvert',
  'What you give':
      'Ce que vous donnez',
  'Your student record, your bank account number, your passport number, your results (PDF), your passport scan and date of entry into Algeria for an attestation de bourse, and the photo of your student card.':
      'Votre fiche étudiant, votre numéro de compte bancaire, votre numéro de passeport, vos résultats (PDF), le scan de votre passeport et votre date d\'entrée en Algérie pour une attestation de bourse, et la photo de votre carte d\'étudiant.',
  'Who can see what':
      'Qui peut voir quoi',
  '• The Educational Attaché of Zimbabwe: everything in your student space.\n• The Governor of your wilaya: your student record, results, phone and bank account number. Never your passport number, passport scan or attestation.\n• The app administrator: can technically access the stored data to keep the app running.\n• Other students: nothing. They never see your documents, your inscription number, your phone or your bank account.':
      '• L\'Attaché d\'éducation du Zimbabwe : tout ce qui est dans votre espace étudiant.\n• Le Gouverneur de votre wilaya : votre fiche étudiant, vos résultats, votre téléphone et votre numéro de compte bancaire. Jamais votre numéro de passeport, le scan du passeport ni l\'attestation.\n• L\'administrateur de l\'application : peut techniquement accéder aux données enregistrées pour faire fonctionner l\'application.\n• Les autres étudiants : rien. Ils ne voient jamais vos documents, votre numéro d\'inscription, votre téléphone ni votre compte bancaire.',
  'How it is protected':
      'Comment c\'est protégé',
  'Files are kept in private storage. Every time the Educational Attaché or a Governor opens your results, bank account, passport number or passport scan, it is recorded with the date. Links to a file stop working after at most one hour.':
      'Les fichiers sont gardés dans un stockage privé. Chaque fois que l\'Attaché d\'éducation ou un Gouverneur ouvre vos résultats, votre compte bancaire, votre numéro de passeport ou le scan du passeport, c\'est enregistré avec la date. Les liens vers un fichier cessent de fonctionner après une heure au maximum.',
  'How long it is kept':
      'Combien de temps c\'est gardé',
  'Your passport scan is deleted after your attestation is issued. The rest stays until you delete it or delete your account. Deleting your account deletes all your files.':
      'Le scan de votre passeport est supprimé après la délivrance de votre attestation. Le reste est gardé jusqu\'à ce que vous le supprimiez ou supprimiez votre compte. La suppression de votre compte supprime tous vos fichiers.',
  'This cannot be undone.\n\nDeleted: your profile, phone number, all your photos and files (also the photos you sent in chats, your results, passport and attestations), your student record, bank account and passport numbers, appointments, listings, open requests, notifications and blocks.\n\nKept for the other person: finished transactions, chat text messages and ratings (you will show as "AZSA user").\n\nType DELETE to confirm.':
      'Cette action est définitive.\n\nSupprimés : votre profil, votre numéro de téléphone, toutes vos photos et fichiers (aussi les photos envoyées dans les discussions, vos résultats, passeport et attestations), votre fiche étudiant, vos numéros de compte bancaire et de passeport, vos rendez-vous, annonces, demandes ouvertes, notifications et blocages.\n\nConservés pour l\'autre personne : les transactions terminées, les messages texte et les notes (vous apparaîtrez comme « AZSA user »).\n\nTapez DELETE pour confirmer.',
  'Send a test to myself':
      "Envoyer un test à moi-même",
  'Test sent to your phone only.':
      "Test envoyé seulement à votre téléphone.",
  'The test could not be sent to your phone.':
      "Le test n'a pas pu être envoyé à votre téléphone.",
  'The alert was not sent to every phone.':
      "L'alerte n'a pas été envoyée à tous les téléphones.",
  'Staff accounts are removed by the app owner.':
      "Les comptes du personnel sont supprimés par le propriétaire de l'application.",
  'This match is no longer available.':
      "Cette mise en relation n'est plus disponible.",
  'Waiting for approval by your Governor':
      "En attente d'approbation par votre Gouverneur",
  'You will get a notification when your request is answered.':
      "Vous recevrez une notification quand votre demande aura une réponse.",
  'Your request was not approved.':
      "Votre demande n'a pas été approuvée.",
  'You can ask again 24 hours after the answer, or contact your Governor.':
      "Vous pouvez redemander 24 heures après la réponse, ou contacter votre Gouverneur.",
  'Request to join':
      "Demander à rejoindre",
  'Join the student space':
      "Rejoindre l'espace étudiant",
  'The student space has your contacts, the guide and your appointments. The Governor of your wilaya approves new members.':
      "L'espace étudiant contient vos contacts, le guide et vos rendez-vous. Le Gouverneur de votre wilaya approuve les nouveaux membres.",
  'Your wilaya: {wilaya}':
      "Votre wilaya : {wilaya}",
  'Approve {name} as a member of the student space?':
      "Approuver {name} comme membre de l'espace étudiant ?",
  'Reject the request of {name}?':
      "Refuser la demande de {name} ?",
  'Approve':
      "Approuver",
  'Approved.':
      "Approuvé.",
  'Rejected.':
      "Refusé.",
  'Join requests':
      "Demandes d'adhésion",
  'No requests are waiting.':
      "Aucune demande en attente.",
  'Approve new members of the student space':
      "Approuver les nouveaux membres de l'espace étudiant",
  'Recent access':
      "Accès récents",
  'Person (name)':
      "Personne (nom)",
  'What':
      "Quoi",
  'The last 100 rows, newest first.':
      "Les 100 dernières lignes, les plus récentes d'abord.",
  'No matching rows.':
      "Aucune ligne correspondante.",
  'Who opened student information':
      "Qui a ouvert des informations d'étudiants",
  'Verify your email':
      "Vérifiez votre e-mail",
  'Reset password':
      "Réinitialiser le mot de passe",
  'Enter the 6-digit code we sent to {email}':
      "Entrez le code à 6 chiffres envoyé à {email}",
  '6-digit code':
      "Code à 6 chiffres",
  'Verify':
      "Vérifier",
  'Resend code':
      "Renvoyer le code",
  'Resend code in {seconds} s':
      "Renvoyer le code dans {seconds} s",
  'A new code was sent.':
      "Un nouveau code a été envoyé.",
  'Enter the 6 digits.':
      "Entrez les 6 chiffres.",
  'Wrong or expired code. Try again.':
      "Code incorrect ou expiré. Réessayez.",
  'This email already has an account. Please log in.':
      "Cet e-mail a déjà un compte. Connectez-vous.",
  'Your email is not confirmed yet. Enter the code we sent you.':
      "Votre e-mail n'est pas encore confirmé. Entrez le code que nous vous avons envoyé.",
  'Send me a new code':
      "Envoyer un nouveau code",
  'Forgot password?':
      "Mot de passe oublié ?",
  'Enter your email first.':
      "Entrez d'abord votre e-mail.",
  'Choose a new password.':
      "Choisissez un nouveau mot de passe.",
  'New password':
      "Nouveau mot de passe",
  'Confirm new password':
      "Confirmez le nouveau mot de passe",
  'Save password':
      "Enregistrer le mot de passe",
  'Passwords do not match.':
      "Les mots de passe ne correspondent pas.",
  'Password must have at least 6 characters.':
      "Le mot de passe doit avoir au moins 6 caractères.",
  'Password changed.':
      "Mot de passe modifié.",
  'Algeria':
      "Algérie",
  'Zimbabwe':
      "Zimbabwe",
  '9 digits, without the first 0. Only you, the Educational Attaché and your Governor can see it.':
      "9 chiffres, sans le 0 du début. Seuls vous, l'attaché éducatif et votre gouverneur pouvez le voir.",
  '9 digits, without the first 0.':
      "9 chiffres, sans le 0 du début.",
  'Enter the 9 digits after the code.':
      "Entrez les 9 chiffres après le code.",
  'Choose +213 or +263 and enter the 9 digits.':
      "Choisissez +213 ou +263 et entrez les 9 chiffres.",
  'Indicative rate (Annaba)':
      "Taux indicatif (Annaba)",
  'Indicative rate is {pct}% higher than the bank':
      "Le taux indicatif est {pct} % plus haut que la banque",
  'Indicative rate is {pct}% lower than the bank':
      "Le taux indicatif est {pct} % plus bas que la banque",
  'Calculator':
      "Calculatrice",
  'Amount in {currency}':
      "Montant en {currency}",
  'I send foreign currency / I receive DA':
      "J'envoie des devises / je reçois des DA",
  'I receive foreign currency / I send DA':
      "Je reçois des devises / j'envoie des DA",
  'Indicative, not a guarantee':
      "Indicatif, sans garantie",
  'No rate available for {currency}.':
      "Aucun taux disponible pour {currency}.",
  'Expires in {time}':
      "Expire dans {time}",
  'Expired':
      "Expirée",
  'Received':
      "Reçue",
  'In review':
      "En cours d'examen",
  'Rejected':
      "Refusée",
  'Remember me':
      "Se souvenir de moi",
  'Only your email is remembered, on this phone.':
      "Seul votre e-mail est mémorisé, sur ce téléphone.",
  'Log In':
      "Connexion",
  'Glad to see you again.':
      "Ravi de vous revoir.",
  'Join AZSA today.':
      "Rejoignez AZSA dès aujourd'hui.",
  "Don't have an account? Sign up":
      "Pas encore de compte ? Inscrivez-vous",
  'Staff tools':
      "Outils du personnel",
  'Administrator':
      "Administrateur",
  'Student':
      "Étudiant",
  'With a record':
      "Avec dossier",
  'Without a record':
      "Sans dossier",
  'Students per wilaya':
      "Étudiants par wilaya",
  'Startup sound':
      "Son de démarrage",
  'Plays when the app opens, never on silent.':
      "Joué à l'ouverture de l'application, jamais en mode silencieux.",

  // Onboarding fixes (2026-11-19)
  'Wrong email or password.':
      "Email ou mot de passe incorrect.",
  'Enter a valid email address.':
      "Entrez une adresse email valide.",
  'Too many tries. Wait a few minutes and try again.':
      "Trop d'essais. Attendez quelques minutes et réessayez.",
  'No internet connection. Check it and try again.':
      "Pas de connexion internet. Vérifiez-la et réessayez.",
  'Enter your full name (2 to 80 characters)':
      "Entrez votre nom complet (2 à 80 caractères)",
  'Enter your password.':
      "Entrez votre mot de passe.",
  'Google sign-in is not available right now. Use your email and password, or try again later.':
      "La connexion Google n'est pas disponible pour le moment. Utilisez votre email et votre mot de passe, ou réessayez plus tard.",
  'Google sign-in failed. Check your internet and try again.':
      "Échec de la connexion Google. Vérifiez votre internet et réessayez.",
  'Could not save. Check your internet and try again.':
      "Impossible d'enregistrer. Vérifiez votre internet et réessayez.",
  'Full name (required)':
      "Nom complet (obligatoire)",
  'As on your passport. You cannot change it later.':
      "Comme sur votre passeport. Vous ne pourrez pas le modifier ensuite.",
  'Your name is already set. Contact AZSA support to change it.':
      "Votre nom est déjà enregistré. Contactez le support AZSA pour le modifier.",
  'Hide password':
      "Masquer le mot de passe",
  'Show password':
      "Afficher le mot de passe",
  // Errors, chat and requests (2026-11-19)
  'no internet connection.':
      "pas de connexion internet.",
  'not allowed.':
      "non autorisé.",
  'You are not allowed to do this.':
      "Vous n'êtes pas autorisé à faire ceci.",
  'it already exists.':
      "cela existe déjà.",
  'This already exists.':
      "Cela existe déjà.",
  'it is no longer available.':
      "ce n'est plus disponible.",
  'This is no longer available.':
      "Ce n'est plus disponible.",
  'please log in again.':
      "reconnectez-vous.",
  'Your login has expired. Please log in again.':
      "Votre connexion a expiré. Reconnectez-vous.",
  'the file is too big.':
      "le fichier est trop grand.",
  'This file is too big.':
      "Ce fichier est trop grand.",
  'please try again.':
      "réessayez.",
  'Something went wrong. Try again.':
      "Un problème est survenu. Réessayez.",
  'Message not sent: {error}':
      "Message non envoyé : {error}",
  'Did you really send the money?':
      "Avez-vous vraiment envoyé l'argent ?",
  'Did you really receive the money?':
      "Avez-vous vraiment reçu l'argent ?",
  'Confirm only when it is really done. This cannot be undone.':
      "Confirmez seulement quand c'est vraiment fait. Impossible d'annuler ensuite.",
  'Yes, confirm':
      "Oui, confirmer",
  'This request was cancelled.':
      "Cette demande a été annulée.",
  'Could not load this exchange.':
      "Impossible de charger cet échange.",
  'this student':
      "cet étudiant",
  'Match with {name}?':
      "Accepter l'échange avec {name} ?",
  '{type} · {amount}. A chat opens with this student. Only exchange money when you both agree.':
      "{type} · {amount}. Une discussion s'ouvre avec cet étudiant. N'échangez l'argent que lorsque vous êtes tous les deux d'accord.",
  'Request is no longer open':
      "Cette demande n'est plus ouverte",
  'Cannot match your own request':
      "Vous ne pouvez pas accepter votre propre demande",
  'You cannot match with this user.':
      "Vous ne pouvez pas faire d'échange avec cet utilisateur.",
  'You are not part of this transaction':
      "Vous ne faites pas partie de cet échange",
  'You can only confirm your own side':
      "Vous ne pouvez confirmer que votre côté",
  'You already confirmed your side':
      "Vous avez déjà confirmé votre côté",
  'A problem can only be reported while the exchange is in progress':
      "Un problème ne peut être signalé que pendant l'échange",
  'Ratings only unlock after a completed transaction':
      "La note n'est possible qu'après un échange terminé",
  'You were not part of this transaction':
      "Vous ne faisiez pas partie de cet échange",
  'Not signed in':
      "Non connecté",
  // Notifications (2026-11-19)
  'Notifications ({count} new)':
      "Notifications ({count} nouvelles)",
  'Today':
      "Aujourd'hui",
  'Yesterday':
      "Hier",
  'Earlier':
      "Plus tôt",
  'Clear all notifications?':
      "Effacer toutes les notifications ?",
  'They will be deleted. This cannot be undone.':
      "Elles seront supprimées. Impossible d'annuler.",
  'Clear all':
      "Tout effacer",
  'You\'re all caught up':
      "Vous êtes à jour",
  'Matches, confirmations and updates will appear here.':
      "Les échanges, confirmations et nouvelles apparaîtront ici.",
  'Swipe left to delete one notification.':
      "Glissez vers la gauche pour supprimer une notification.",
  'Someone matched with your request. Chat is now open.':
      "Quelqu'un a accepté votre demande. La discussion est ouverte.",
  'Transaction complete. You can now rate each other.':
      "Échange terminé. Vous pouvez maintenant vous noter.",
  'The other party confirmed their side. Please confirm yours once done.':
      "L'autre personne a confirmé. Confirmez votre côté une fois fait.",
  'A dispute was opened on one of your transactions.':
      "Un litige a été ouvert sur un de vos échanges.",
  // Profile redesign (2026-11-19)
  'New':
      "Nouveau",
  'Trusted':
      "Fiable",
  'Good':
      "Bon",
  'Low':
      "Faible",
  'Member since {date}':
      "Membre depuis {date}",
  '{count} reviews':
      "{count} avis",
  'completed':
      "terminés",
  'trust level':
      "confiance",
  'Verified student':
      "Étudiant vérifié",
  'Not verified yet':
      "Pas encore vérifié",
  '{count} exchanges done':
      "{count} échanges faits",
  'Safety':
      "Sécurité",
  'New photo chosen. Tap Save changes.':
      "Nouvelle photo choisie. Touchez Enregistrer.",
  'Your details':
      "Vos informations",
  'Account':
      "Compte",
  'Verification':
      "Vérification",
  'See my public profile':
      "Voir mon profil public",
  'This is how others see you.':
      "C'est ce que les autres voient.",
  'Staff':
      "Équipe",
  'Settings':
      "Paramètres",
  // Profile sheet + settings (2026-11-19)
  'Edit profile':
      "Modifier le profil",
  'Public view':
      "Vue publique",
  'Get the gold tick':
      "Obtenez le badge doré",
  'Other students see the gold tick on your profile.':
      "Les autres étudiants voient le badge doré sur votre profil.",
  'Verified students are trusted more and match faster.':
      "Les étudiants vérifiés inspirent plus confiance et trouvent un échange plus vite.",
  'Choose your wilaya.':
      "Choisissez votre wilaya.",
  'Your name can\'t be changed.':
      "Votre nom ne peut pas être modifié.",
  'App':
      "Application",
  'Privacy':
      "Confidentialité",
  // Photo picker (2026-11-19)
  'Profile photo':
      "Photo de profil",
  'Take a photo':
      "Prendre une photo",
  'Choose from gallery':
      "Choisir dans la galerie",
  'Could not open the camera or the gallery.':
      "Impossible d'ouvrir l'appareil photo ou la galerie.",
  'Photo updated.':
      "Photo mise à jour.",
  // Home, rates, staff hub, expiry (2026-11-19)
  'Anyone to receive {amount}':
      "Quelqu'un pour recevoir {amount}",
  'Anyone to send {amount}':
      "Quelqu'un pour envoyer {amount}",
  'Anyone to receive':
      "Quelqu'un pour recevoir",
  'Anyone to send':
      "Quelqu'un pour envoyer",
  'Anyone who wants to receive':
      "Quelqu'un qui veut recevoir",
  'Anyone who wants to send':
      "Quelqu'un qui veut envoyer",
  'I send the money':
      "J'envoie l'argent",
  'I receive the money':
      "Je reçois l'argent",
  'Who are you looking for?':
      "Qui cherchez-vous ?",
  'New requests':
      "Nouvelles demandes",
  '{request}. A chat opens with this student. Only exchange money when you both agree.':
      "{request}. Une discussion s'ouvre avec cet étudiant. N'échangez l'argent que lorsque vous êtes tous les deux d'accord.",
  'Parallel':
      "Parallèle",
  'Official':
      "Officiel",
  'Staff hub':
      "Espace équipe",
  '{count} tools':
      "{count} outils",
  'Search a tool (attestation, alert, bank...)':
      "Chercher un outil (attestation, alerte, banque...)",
  'No tool matches "{q}".':
      "Aucun outil ne correspond à « {q} ».",
  'Clear':
      "Effacer",
  'Find a student by name or number':
      "Trouver un étudiant par nom ou numéro",
  'All students and their records':
      "Tous les étudiants et leurs dossiers",
  'Numbers per wilaya':
      "Chiffres par wilaya",
  'The list to export':
      "La liste à exporter",
  'Review and issue attestations':
      "Vérifier et délivrer les attestations",
  'Requests to meet the Attaché':
      "Demandes de rendez-vous avec l'Attaché",
  'Who opened which document':
      "Qui a ouvert quel document",
  'Urgent message to every student':
      "Message urgent à tous les étudiants",
  'Images on the home screen':
      "Images sur l'écran d'accueil",
  'Phone numbers of the Governors':
      "Numéros des Gouverneurs",
  'Contacts shown to students':
      "Contacts affichés aux étudiants",
  'Students of your wilaya':
      "Étudiants de votre wilaya",
  'Numbers for your wilaya':
      "Chiffres de votre wilaya",
  'Who sent their results':
      "Qui a envoyé ses résultats",
  'Students to remind':
      "Étudiants à relancer",
  'Opening one is recorded':
      "Chaque ouverture est enregistrée",
  'Phone numbers and emails':
      "Numéros et e-mails",
  'Documents':
      "Documents",
  'Communication':
      "Communication",
  'Money':
      "Argent",
  'Your request expired':
      "Votre demande a expiré",
  'Post the same request again?':
      "Publier la même demande à nouveau ?",
  '{request}. Post the same request again?':
      "{request}. Publier la même demande à nouveau ?",
  'No, thanks':
      "Non, merci",
  'Post again':
      "Republier",
  'Your request is posted again.':
      "Votre demande est publiée à nouveau.",
  'Your request expired. Tap to post it again.':
      "Votre demande a expiré. Touchez pour la republier.",
  'This is not your request':
      "Ce n'est pas votre demande",
  'Only an expired request can be posted again':
      "Seule une demande expirée peut être republiée",
  'You already posted this request again':
      "Vous avez déjà republié cette demande",
  // Live rates (2026-11-19)
  'Estimated from the official rate.':
      "Estimé à partir du taux officiel.",
  'Parallel rates':
      "Taux parallèles",
  'Type today\'s square rate':
      "Saisir le taux du square du jour",
  'Type today\'s square rate in Annaba (DA). It replaces the estimate for 24 hours.':
      "Saisissez le taux du square d'Annaba du jour (DA). Il remplace l'estimation pendant 24 heures.",
  'Fill in both buy and sell for {pair}.':
      "Remplissez l'achat et la vente pour {pair}.",
  'Parallel rates saved.':
      "Taux parallèles enregistrés.",
  'Only the Educational Attaché or the admin can change the rates':
      "Seuls l'Attaché ou l'admin peuvent modifier les taux",
  'Enter real rates (more than 0)':
      "Entrez de vrais taux (plus de 0)",
  'The buy rate cannot be higher than the sell rate':
      "Le taux d'achat ne peut pas dépasser le taux de vente",
};
