import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  'UniBridge user': 'Utilisateur UniBridge',

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

  // ---- App lock ----
  'Unlock UniBridge': 'Déverrouiller UniBridge',
  'UniBridge is locked': 'UniBridge est verrouillé',
  'Use your fingerprint, face or phone PIN to unlock.': 'Utilisez votre empreinte, votre visage ou le code du téléphone pour déverrouiller.',
  'Unlock': 'Déverrouiller',

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
  'This cannot be undone.\n\nDeleted: your profile, photos, listings, open requests, notifications and blocks.\n\nKept for the other person: finished transactions, chats and ratings (you will show as "UniBridge user").\n\nType DELETE to confirm.': 'Cette action est irréversible.\n\nSupprimés : votre profil, vos photos, annonces, demandes ouvertes, notifications et blocages.\n\nConservés pour l\'autre personne : échanges terminés, discussions et évaluations (vous apparaîtrez comme « Utilisateur UniBridge »).\n\nTapez DELETE pour confirmer.',
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
  'Send a clear photo of your student card. Your name and student number must be readable and must match your account. Only the UniBridge team can view this photo. It is used for this check and is never shown to other users.': "Envoyez une photo nette de votre carte d'étudiant. Votre nom et votre numéro doivent être lisibles et correspondre à votre compte. Seule l'équipe UniBridge peut voir cette photo. Elle sert uniquement à cette vérification et n'est jamais montrée aux autres.",
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
  'Your name is missing. Contact UniBridge support to add it.': 'Votre nom est manquant. Contactez le support UniBridge pour l\'ajouter.',
  'Wilaya (required)': 'Wilaya (obligatoire)',
  'City or area (optional)': 'Ville ou quartier (facultatif)',
  'Your profile could not be saved. Please contact UniBridge support.': 'Votre profil n\'a pas pu être enregistré. Contactez le support UniBridge.',
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
};
