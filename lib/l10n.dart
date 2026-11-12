import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------- Languages (English, French, Arabic) + theme ----------------
//
// Write texts in English and wrap them with tr():
//   Text(tr('Log out'))
//   Text(tr('Block {name}?', {'name': name}))
// The translations are in _t below: 'English': ['Français', 'العربية'].
// A text that is missing from _t simply stays in English.

const Map<String, String> kLanguages = {
  'en': 'English',
  'fr': 'Français',
  'ar': 'العربية',
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
    if (row != null) text = row[lang == 'fr' ? 0 : 1];
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

const Map<String, List<String>> _t = {
  // ---- Common ----
  'Cancel': ['Annuler', 'إلغاء'],
  'Error: {error}': ['Erreur : {error}', 'خطأ: {error}'],
  'Something went wrong: {error}': [
    'Une erreur est survenue : {error}',
    'حدث خطأ: {error}'
  ],
  'Please wait...': ['Veuillez patienter...', 'يرجى الانتظار...'],
  'Save': ['Enregistrer', 'حفظ'],
  'Saving...': ['Enregistrement...', 'جارٍ الحفظ...'],
  'Delete': ['Supprimer', 'حذف'],
  'Edit': ['Modifier', 'تعديل'],
  'Send': ['Envoyer', 'إرسال'],
  'Receive': ['Recevoir', 'استلام'],
  'Keep it': ['Garder', 'الإبقاء عليه'],
  'All': ['Tout', 'الكل'],
  'Yes': ['Oui', 'نعم'],
  'Not yet': ['Pas encore', 'ليس بعد'],
  'Other': ['Autre', 'أخرى'],
  'Location': ['Lieu', 'الموقع'],
  'Profile unavailable': ['Profil indisponible', 'الملف الشخصي غير متاح'],
  'UniBridge user': ['Utilisateur UniBridge', 'مستخدم UniBridge'],

  // ---- Tabs ----
  'Requests': ['Demandes', 'الطلبات'],
  'Marketplace': ['Marché', 'السوق'],
  'Rates': ['Taux', 'الأسعار'],
  'Profile': ['Profil', 'الملف الشخصي'],

  // ---- Login ----
  'Create account': ['Créer un compte', 'إنشاء حساب'],
  'Log in': ['Se connecter', 'تسجيل الدخول'],
  'Full name': ['Nom complet', 'الاسم الكامل'],
  'Inscription number': ["Numéro d'inscription", 'رقم التسجيل'],
  'Email': ['E-mail', 'البريد الإلكتروني'],
  'Password': ['Mot de passe', 'كلمة المرور'],
  'Sign up': ["S'inscrire", 'إنشاء حساب'],
  'Already have an account? Log in': [
    'Déjà un compte ? Se connecter',
    'لديك حساب؟ سجّل الدخول'
  ],
  'New here? Create an account': [
    'Nouveau ? Créer un compte',
    'جديد هنا؟ أنشئ حساباً'
  ],
  'OR': ['OU', 'أو'],
  'Continue with Google': ['Continuer avec Google', 'المتابعة باستخدام Google'],
  'Google sign-in failed: {error}': [
    'Échec de la connexion Google : {error}',
    'فشل تسجيل الدخول عبر Google: {error}'
  ],
  'By continuing, you agree to our Terms of use and Privacy policy.': [
    "En continuant, vous acceptez nos Conditions d'utilisation et notre Politique de confidentialité.",
    'بالمتابعة، فإنك توافق على شروط الاستخدام وسياسة الخصوصية.'
  ],
  'Terms of use': ["Conditions d'utilisation", 'شروط الاستخدام'],
  'Privacy policy': ['Politique de confidentialité', 'سياسة الخصوصية'],
  'Terms and privacy': ['Conditions et confidentialité', 'الشروط والخصوصية'],
  'Last updated: {date}': ['Dernière mise à jour : {date}', 'آخر تحديث: {date}'],
  'Log out?': ['Se déconnecter ?', 'تسجيل الخروج؟'],
  'Are you sure you want to log out?': [
    'Voulez-vous vraiment vous déconnecter ?',
    'هل تريد فعلاً تسجيل الخروج؟'
  ],
  'Log out': ['Se déconnecter', 'تسجيل الخروج'],

  // ---- App lock ----
  'Unlock UniBridge': ['Déverrouiller UniBridge', 'فتح UniBridge'],
  'UniBridge is locked': ['UniBridge est verrouillé', 'UniBridge مقفل'],
  'Use your fingerprint, face or phone PIN to unlock.': [
    'Utilisez votre empreinte, votre visage ou le code du téléphone pour déverrouiller.',
    'استخدم بصمتك أو وجهك أو رمز الهاتف لفتح التطبيق.'
  ],
  'Unlock': ['Déverrouiller', 'فتح'],

  // ---- Open requests + filters ----
  'Open requests': ['Demandes ouvertes', 'الطلبات المفتوحة'],
  'No open requests right now.': [
    'Aucune demande ouverte pour le moment.',
    'لا توجد طلبات مفتوحة حالياً.'
  ],
  'No requests match these filters.': [
    'Aucune demande ne correspond à ces filtres.',
    'لا توجد طلبات تطابق هذه المرشحات.'
  ],
  'Clear filters': ['Effacer les filtres', 'مسح المرشحات'],
  'Match': ['Accepter', 'قبول'],
  'Wants to send {amount}': ['Veut envoyer {amount}', 'يريد إرسال {amount}'],
  'Wants to receive {amount}': ['Veut recevoir {amount}', 'يريد استلام {amount}'],
  'Type': ['Type', 'النوع'],
  'Currency': ['Devise', 'العملة'],
  'Wilaya': ['Wilaya', 'الولاية'],
  '{label}: All': ['{label} : tout', '{label}: الكل'],
  'My requests': ['Mes demandes', 'طلباتي'],
  'Notifications': ['Notifications', 'الإشعارات'],
  'No notifications yet.': [
    'Aucune notification pour le moment.',
    'لا توجد إشعارات بعد.'
  ],

  // ---- New request / my requests ----
  'Enter a valid amount': ['Entrez un montant valide', 'أدخل مبلغاً صحيحاً'],
  'New request': ['Nouvelle demande', 'طلب جديد'],
  'What do you want to do?': ['Que voulez-vous faire ?', 'ماذا تريد أن تفعل؟'],
  'I want to SEND money': ["Je veux ENVOYER de l'argent", 'أريد إرسال المال'],
  'I want to RECEIVE money': ["Je veux RECEVOIR de l'argent", 'أريد استلام المال'],
  'Amount': ['Montant', 'المبلغ'],
  'Post request': ['Publier la demande', 'نشر الطلب'],
  'You have no requests yet.': [
    "Vous n'avez pas encore de demandes.",
    'ليس لديك طلبات بعد.'
  ],
  'Status: {status}': ['Statut : {status}', 'الحالة: {status}'],
  'Waiting for someone to match': [
    "En attente d'une correspondance",
    'في انتظار من يقبل الطلب'
  ],
  'Cancel request': ['Annuler la demande', 'إلغاء الطلب'],
  'Cancel this request?': ['Annuler cette demande ?', 'إلغاء هذا الطلب؟'],
  'It will no longer be visible to other users.': [
    'Elle ne sera plus visible pour les autres utilisateurs.',
    'لن يظهر بعد الآن للمستخدمين الآخرين.'
  ],
  'Request cancelled.': ['Demande annulée.', 'تم إلغاء الطلب.'],
  'Could not cancel: {error}': [
    "Impossible d'annuler : {error}",
    'تعذّر الإلغاء: {error}'
  ],
  'Open': ['Ouverte', 'مفتوح'],
  'Matched': ['Acceptée', 'تم القبول'],
  'Sender confirmed': ["Confirmée par l'envoyeur", 'أكّد المرسل'],
  'Receiver confirmed': ['Confirmée par le receveur', 'أكّد المستلم'],
  'Completed': ['Terminée', 'مكتمل'],
  'Disputed': ['En litige', 'متنازع عليه'],
  'Cancelled': ['Annulée', 'ملغى'],

  // ---- Chat ----
  'Chat': ['Discussion', 'المحادثة'],
  'Report a problem': ['Signaler un problème', 'الإبلاغ عن مشكلة'],
  'Describe what went wrong...': [
    "Décrivez ce qui s'est mal passé...",
    'صف ما الذي حدث...'
  ],
  'Submit': ['Envoyer', 'إرسال'],
  'Transaction complete! You can now rate each other.': [
    'Échange terminé ! Vous pouvez maintenant vous évaluer.',
    'اكتمل التبادل! يمكنكما الآن تقييم بعضكما.'
  ],
  'Dispute submitted.': ['Litige envoyé.', 'تم إرسال النزاع.'],
  'Thanks for rating!': ['Merci pour votre évaluation !', 'شكراً على التقييم!'],
  '✅ Transaction completed — thanks for rating!': [
    '✅ Échange terminé — merci pour votre évaluation !',
    '✅ اكتمل التبادل — شكراً على التقييم!'
  ],
  '✅ Transaction completed': ['✅ Échange terminé', '✅ اكتمل التبادل'],
  'Rate the other person:': ["Évaluez l'autre personne :", 'قيّم الطرف الآخر:'],
  'Optional comment...': ['Commentaire (facultatif)...', 'تعليق (اختياري)...'],
  'Submitting...': ['Envoi...', 'جارٍ الإرسال...'],
  'Submit rating': ["Envoyer l'évaluation", 'إرسال التقييم'],
  '⚠️ Dispute opened on this transaction': [
    '⚠️ Un litige a été ouvert sur cet échange',
    '⚠️ تم فتح نزاع على هذا التبادل'
  ],
  'You confirmed. Waiting for the other side...': [
    "Vous avez confirmé. En attente de l'autre personne...",
    'لقد أكّدت. في انتظار الطرف الآخر...'
  ],
  'Once the exchange is done outside the app, confirm here.': [
    "Une fois l'échange fait en dehors de l'application, confirmez ici.",
    'بعد إتمام التبادل خارج التطبيق، أكّد هنا.'
  ],
  'I sent the money': ["J'ai envoyé l'argent", 'لقد أرسلت المال'],
  'I received the money': ["J'ai reçu l'argent", 'لقد استلمت المال'],
  'No messages yet. Say hi!': [
    'Pas encore de messages. Dites bonjour !',
    'لا توجد رسائل بعد. ألقِ التحية!'
  ],
  'Type a message...': ['Écrire un message...', 'اكتب رسالة...'],
  'Send a photo': ['Envoyer une photo', 'إرسال صورة'],
  'Share my location': ['Partager ma position', 'مشاركة موقعي'],
  'Download chat as text': [
    'Télécharger la discussion (texte)',
    'تنزيل المحادثة كنص'
  ],
  'This photo is too big (max 5 MB).': [
    'Cette photo est trop lourde (5 Mo max).',
    'هذه الصورة كبيرة جداً (الحد الأقصى 5 ميغابايت).'
  ],
  'Could not send photo: {error}': [
    "Impossible d'envoyer la photo : {error}",
    'تعذّر إرسال الصورة: {error}'
  ],
  'Share location': ['Partager la position', 'مشاركة الموقع'],
  'Send your current location to {name}?': [
    'Envoyer votre position actuelle à {name} ?',
    'هل تريد إرسال موقعك الحالي إلى {name}؟'
  ],
  'the other person': ["l'autre personne", 'الطرف الآخر'],
  'Please turn on location (GPS) on your phone.': [
    'Activez la localisation (GPS) sur votre téléphone.',
    'يرجى تفعيل الموقع (GPS) في هاتفك.'
  ],
  'Location permission was refused.': [
    "L'autorisation de localisation a été refusée.",
    'تم رفض إذن الموقع.'
  ],
  'Could not send location: {error}': [
    "Impossible d'envoyer la position : {error}",
    'تعذّر إرسال الموقع: {error}'
  ],
  'Could not open the map.': [
    "Impossible d'ouvrir la carte.",
    'تعذّر فتح الخريطة.'
  ],
  '📍 My location (tap to open map)': [
    '📍 Ma position (touchez pour ouvrir la carte)',
    '📍 موقعي (اضغط لفتح الخريطة)'
  ],
  '📍 Location (tap to open map)': [
    '📍 Position (touchez pour ouvrir la carte)',
    '📍 الموقع (اضغط لفتح الخريطة)'
  ],
  'Chat saved.': ['Discussion enregistrée.', 'تم حفظ المحادثة.'],
  'Could not save the chat: {error}': [
    "Impossible d'enregistrer la discussion : {error}",
    'تعذّر حفظ المحادثة: {error}'
  ],
  "You can't send messages in this chat.": [
    'Vous ne pouvez pas envoyer de messages dans cette discussion.',
    'لا يمكنك إرسال رسائل في هذه المحادثة.'
  ],

  // ---- Profiles ----
  'No ratings yet': ["Pas encore d'évaluation", 'لا توجد تقييمات بعد'],
  '{count} completed': ['{count} terminés', '{count} مكتمل'],
  'New member': ['Nouveau membre', 'عضو جديد'],
  'Report user': ["Signaler l'utilisateur", 'الإبلاغ عن المستخدم'],
  'Block user': ["Bloquer l'utilisateur", 'حظر المستخدم'],
  'Unblock user': ["Débloquer l'utilisateur", 'إلغاء حظر المستخدم'],
  'Rating': ['Note', 'التقييم'],
  '★ {avg} ({count} reviews)': ['★ {avg} ({count} avis)', '★ {avg} ({count} تقييم)'],
  'Completed transactions': ['Échanges terminés', 'التبادلات المكتملة'],
  'Trust score': ['Score de confiance', 'درجة الثقة'],
  'Member since': ['Membre depuis', 'عضو منذ'],
  'Verified': ['Vérifié', 'موثَّق'],
  'Reviews': ['Avis', 'التقييمات'],
  'No reviews yet.': ["Pas encore d'avis.", 'لا توجد تقييمات بعد.'],
  'Scam or fraud': ['Arnaque ou fraude', 'احتيال أو نصب'],
  'Harassment': ['Harcèlement', 'تحرش أو إزعاج'],
  'Fake profile': ['Faux profil', 'ملف شخصي مزيف'],
  'Inappropriate content': ['Contenu inapproprié', 'محتوى غير لائق'],
  'Details (optional)': ['Détails (facultatif)', 'تفاصيل (اختياري)'],
  'Send report': ['Envoyer le signalement', 'إرسال البلاغ'],
  "Thanks, we'll review this report.": [
    'Merci, nous allons examiner ce signalement.',
    'شكراً، سنراجع هذا البلاغ.'
  ],
  'You already reported this user. We are reviewing it.': [
    'Vous avez déjà signalé cet utilisateur. Nous examinons le signalement.',
    'لقد أبلغت عن هذا المستخدم مسبقاً. نحن نراجع البلاغ.'
  ],
  'Could not send report: {error}': [
    "Impossible d'envoyer le signalement : {error}",
    'تعذّر إرسال البلاغ: {error}'
  ],
  'this user': ['cet utilisateur', 'هذا المستخدم'],
  'Block {name}?': ['Bloquer {name} ?', 'حظر {name}؟'],
  "You won't see each other's requests or listings, and you can't message each other. Open transactions can still be confirmed or disputed. You can unblock later in your profile.": [
    "Vous ne verrez plus vos demandes et annonces respectives et ne pourrez plus vous écrire. Les échanges en cours peuvent toujours être confirmés ou contestés. Vous pourrez débloquer plus tard dans votre profil.",
    'لن يرى أحدكما طلبات أو إعلانات الآخر، ولن تتمكنا من المراسلة. يمكن تأكيد التبادلات الجارية أو الاعتراض عليها. يمكنك إلغاء الحظر لاحقاً من ملفك الشخصي.'
  ],
  'Block': ['Bloquer', 'حظر'],
  '{name} blocked.': ['{name} a été bloqué.', 'تم حظر {name}.'],
  '{name} unblocked.': ['{name} a été débloqué.', 'تم إلغاء حظر {name}.'],
  'Blocked users': ['Utilisateurs bloqués', 'المستخدمون المحظورون'],
  'You have not blocked anyone.': [
    "Vous n'avez bloqué personne.",
    'لم تحظر أي شخص.'
  ],
  'Unblock': ['Débloquer', 'إلغاء الحظر'],
  'Could not load blocked users: {error}': [
    'Impossible de charger les utilisateurs bloqués : {error}',
    'تعذّر تحميل المستخدمين المحظورين: {error}'
  ],
  'My profile': ['Mon profil', 'ملفي الشخصي'],
  'Tap the picture to change it': [
    'Touchez la photo pour la changer',
    'اضغط على الصورة لتغييرها'
  ],
  'This is how others see you:': [
    'Voici comment les autres vous voient :',
    'هكذا يراك الآخرون:'
  ],
  "Your name and student ID come from sign-up and can't be changed here. Your student ID is never shown to other users.": [
    "Votre nom et votre numéro d'étudiant viennent de l'inscription et ne peuvent pas être modifiés ici. Votre numéro d'étudiant n'est jamais montré aux autres.",
    'اسمك ورقمك الجامعي مأخوذان من التسجيل ولا يمكن تغييرهما هنا. لا يظهر رقمك الجامعي أبداً للمستخدمين الآخرين.'
  ],
  'e.g. Annaba': ['ex. Annaba', 'مثال: عنابة'],
  'Location (city / area)': ['Lieu (ville / quartier)', 'الموقع (المدينة / الحي)'],
  'Could not save: {error}': [
    "Impossible d'enregistrer : {error}",
    'تعذّر الحفظ: {error}'
  ],
  'Profile saved.': ['Profil enregistré.', 'تم حفظ الملف الشخصي.'],
  'Get verified': ['Se faire vérifier', 'توثيق الحساب'],
  'Language': ['Langue', 'اللغة'],
  'Theme': ['Thème', 'المظهر'],
  'System': ['Système', 'حسب الهاتف'],
  'Light': ['Clair', 'فاتح'],
  'Dark': ['Sombre', 'داكن'],
  'Delete my account': ['Supprimer mon compte', 'حذف حسابي'],
  'Deleting...': ['Suppression...', 'جارٍ الحذف...'],
  'Delete forever': ['Supprimer définitivement', 'حذف نهائي'],
  'This cannot be undone.\n\nDeleted: your profile, photos, listings, open requests, notifications and blocks.\n\nKept for the other person: finished transactions, chats and ratings (you will show as "UniBridge user").\n\nType DELETE to confirm.': [
    'Cette action est irréversible.\n\nSupprimés : votre profil, vos photos, annonces, demandes ouvertes, notifications et blocages.\n\nConservés pour l\'autre personne : échanges terminés, discussions et évaluations (vous apparaîtrez comme « Utilisateur UniBridge »).\n\nTapez DELETE pour confirmer.',
    'لا يمكن التراجع عن هذا.\n\nسيُحذف: ملفك الشخصي وصورك وإعلاناتك وطلباتك المفتوحة وإشعاراتك وقائمة الحظر.\n\nيبقى للطرف الآخر: التبادلات المكتملة والمحادثات والتقييمات (ستظهر باسم "مستخدم UniBridge").\n\nاكتب DELETE للتأكيد.'
  ],
  'Finish or resolve your open transactions first.': [
    "Terminez ou réglez d'abord vos échanges en cours.",
    'أكمل أو سوِّ تبادلاتك الجارية أولاً.'
  ],
  'Could not delete account: {error}': [
    'Impossible de supprimer le compte : {error}',
    'تعذّر حذف الحساب: {error}'
  ],
  'Your account has been deleted.': [
    'Votre compte a été supprimé.',
    'تم حذف حسابك.'
  ],

  // ---- Verification ----
  'Could not load: {error}': [
    'Impossible de charger : {error}',
    'تعذّر التحميل: {error}'
  ],
  'Choose a photo of your student card first': [
    "Choisissez d'abord une photo de votre carte d'étudiant",
    'اختر صورة بطاقتك الطلابية أولاً'
  ],
  'Could not send: {error}': [
    "Impossible d'envoyer : {error}",
    'تعذّر الإرسال: {error}'
  ],
  'You are verified': ['Vous êtes vérifié', 'حسابك موثَّق'],
  'Other users can see the blue tick next to your name.': [
    'Les autres utilisateurs voient la coche bleue à côté de votre nom.',
    'يرى المستخدمون الآخرون العلامة الزرقاء بجانب اسمك.'
  ],
  'Under review': ['En cours de vérification', 'قيد المراجعة'],
  'We received your student card and will check it soon. You will see a blue tick here once it is approved.': [
    "Nous avons reçu votre carte d'étudiant et la vérifierons bientôt. Vous verrez une coche bleue ici une fois approuvée.",
    'استلمنا بطاقتك الطلابية وسنتحقق منها قريباً. ستظهر العلامة الزرقاء هنا بعد الموافقة.'
  ],
  'Check again': ['Vérifier à nouveau', 'تحقق مرة أخرى'],
  'Your last request was not approved. You can send a new photo.': [
    "Votre dernière demande n'a pas été approuvée. Vous pouvez envoyer une nouvelle photo.",
    'لم تتم الموافقة على طلبك الأخير. يمكنك إرسال صورة جديدة.'
  ],
  'Your last request was not approved: {note}': [
    "Votre dernière demande n'a pas été approuvée : {note}",
    'لم تتم الموافقة على طلبك الأخير: {note}'
  ],
  'A blue tick tells other students that we checked your student card.': [
    "La coche bleue indique aux autres étudiants que nous avons vérifié votre carte d'étudiant.",
    'تُعلم العلامة الزرقاء الطلاب الآخرين بأننا تحققنا من بطاقتك الطلابية.'
  ],
  'Send a clear photo of your student card. Your name and student number must be readable and must match your account. Only the UniBridge team can view this photo. It is used for this check and is never shown to other users.': [
    "Envoyez une photo nette de votre carte d'étudiant. Votre nom et votre numéro doivent être lisibles et correspondre à votre compte. Seule l'équipe UniBridge peut voir cette photo. Elle sert uniquement à cette vérification et n'est jamais montrée aux autres.",
    'أرسل صورة واضحة لبطاقتك الطلابية. يجب أن يكون اسمك ورقمك مقروءين ومطابقين لحسابك. فريق UniBridge وحده يمكنه رؤية هذه الصورة، وتُستخدم لهذا التحقق فقط ولا تظهر أبداً للمستخدمين الآخرين.'
  ],
  'Tap to choose a photo of your student card': [
    "Touchez pour choisir une photo de votre carte d'étudiant",
    'اضغط لاختيار صورة بطاقتك الطلابية'
  ],
  'Sending...': ['Envoi...', 'جارٍ الإرسال...'],
  'Send for review': ['Envoyer pour vérification', 'إرسال للمراجعة'],

  // ---- Rates ----
  'Exchange rates': ['Taux de change', 'أسعار الصرف'],
  'Buy': ['Achat', 'شراء'],
  'Sell': ['Vente', 'بيع'],
  'Bank': ['Banque', 'البنك'],
  'Parallel market': ['Marché parallèle', 'السوق الموازية'],
  'Parallel market is {pct}% higher than the bank': [
    'Le marché parallèle est {pct} % plus haut que la banque',
    'السوق الموازية أعلى من البنك بـ {pct}%'
  ],
  'Parallel market is {pct}% lower than the bank': [
    'Le marché parallèle est {pct} % plus bas que la banque',
    'السوق الموازية أقل من البنك بـ {pct}%'
  ],
  'Updated {ago}': ['Mis à jour {ago}', 'آخر تحديث {ago}'],
  'unknown': ['inconnu', 'غير معروف'],
  'just now': ["à l'instant", 'الآن'],
  '{n} min ago': ['il y a {n} min', 'منذ {n} دقيقة'],
  '{n} h ago': ['il y a {n} h', 'منذ {n} ساعة'],
  '{n} days ago': ['il y a {n} jours', 'منذ {n} يوم'],
  'No rates available yet.': [
    'Aucun taux disponible pour le moment.',
    'لا توجد أسعار متاحة بعد.'
  ],
  'Could not load rates: {error}': [
    'Impossible de charger les taux : {error}',
    'تعذّر تحميل الأسعار: {error}'
  ],
  'Buy = what you get when you sell foreign currency. Sell = what you pay to buy it. These rates are indicative and updated by hand, so always agree the exact rate with the other person before exchanging anything.': [
    "Achat = ce que vous recevez en vendant des devises. Vente = ce que vous payez pour en acheter. Ces taux sont indicatifs : mettez-vous toujours d'accord sur le taux exact avec l'autre personne avant tout échange.",
    'الشراء = ما تحصل عليه عند بيع العملة الأجنبية. البيع = ما تدفعه لشرائها. هذه الأسعار تقريبية، لذا اتفق دائماً على السعر الدقيق مع الطرف الآخر قبل أي تبادل.'
  ],

  // ---- Marketplace ----
  'Electronics & gadgets': ['Électronique et gadgets', 'إلكترونيات وأجهزة'],
  'Clothes & apparel': ['Vêtements', 'ملابس'],
  'Books & study materials': ["Livres et fournitures d'études", 'كتب ومستلزمات دراسية'],
  'Furniture & home': ['Meubles et maison', 'أثاث ومنزل'],
  'Food & drinks': ['Nourriture et boissons', 'طعام ومشروبات'],
  'Beauty & personal care': ['Beauté et soins', 'تجميل وعناية شخصية'],
  'Sports & fitness': ['Sport et fitness', 'رياضة ولياقة'],
  'Services': ['Services', 'خدمات'],
  'My listings': ['Mes annonces', 'إعلاناتي'],
  "Couldn't open that link": [
    "Impossible d'ouvrir ce lien",
    'تعذّر فتح هذا الرابط'
  ],
  'Price on request': ['Prix sur demande', 'السعر عند الطلب'],
  'Seller': ['Vendeur', 'البائع'],
  'SOLD': ['VENDU', 'مُباع'],
  'Categories': ['Catégories', 'الفئات'],
  'Search listings': ['Rechercher des annonces', 'ابحث في الإعلانات'],
  'Showing: {filter}': ['Affichage : {filter}', 'المعروض: {filter}'],
  'Show all': ['Tout afficher', 'عرض الكل'],
  'You have no listings yet.': [
    "Vous n'avez pas encore d'annonces.",
    'ليس لديك إعلانات بعد.'
  ],
  'No listings yet. Be the first!': [
    'Pas encore d\'annonces. Soyez le premier !',
    'لا توجد إعلانات بعد. كن الأول!'
  ],
  'No listings match your search.': [
    'Aucune annonce ne correspond à votre recherche.',
    'لا توجد إعلانات تطابق بحثك.'
  ],
  'Could not load listings: {error}': [
    'Impossible de charger les annonces : {error}',
    'تعذّر تحميل الإعلانات: {error}'
  ],
  'Listing': ['Annonce', 'الإعلان'],
  'Mark as available': ['Marquer comme disponible', 'تعيين كمتاح'],
  'Mark as sold': ['Marquer comme vendu', 'تعيين كمُباع'],
  'Your listing is available again.': [
    'Votre annonce est de nouveau disponible.',
    'إعلانك متاح مرة أخرى.'
  ],
  'Marked as sold. Other students can no longer see it.': [
    'Marqué comme vendu. Les autres étudiants ne le voient plus.',
    'تم التعيين كمُباع. لم يعد بإمكان الطلاب الآخرين رؤيته.'
  ],
  'Could not update: {error}': [
    'Impossible de mettre à jour : {error}',
    'تعذّر التحديث: {error}'
  ],
  'Delete this listing?': ['Supprimer cette annonce ?', 'حذف هذا الإعلان؟'],
  'This cannot be undone.': ['Cette action est irréversible.', 'لا يمكن التراجع عن هذا.'],
  'Listing deleted.': ['Annonce supprimée.', 'تم حذف الإعلان.'],
  'Could not delete: {error}': [
    'Impossible de supprimer : {error}',
    'تعذّر الحذف: {error}'
  ],
  'Contact seller': ['Contacter le vendeur', 'التواصل مع البائع'],
  'Edit listing': ["Modifier l'annonce", 'تعديل الإعلان'],
  'New listing': ['Nouvelle annonce', 'إعلان جديد'],
  'Photos ({count}/3)': ['Photos ({count}/3)', 'الصور ({count}/3)'],
  'Add photos': ['Ajouter des photos', 'إضافة صور'],
  'Title *': ['Titre *', 'العنوان *'],
  'Category *': ['Catégorie *', 'الفئة *'],
  'Description': ['Description', 'الوصف'],
  'Price in DA (optional)': ['Prix en DA (facultatif)', 'السعر بالدينار (اختياري)'],
  'WhatsApp number or contact link': [
    'Numéro WhatsApp ou lien de contact',
    'رقم واتساب أو رابط تواصل'
  ],
  '0555 12 34 56 or instagram.com/yourname': [
    '0555 12 34 56 ou instagram.com/votrenom',
    '0555 12 34 56 أو instagram.com/yourname'
  ],
  'Numbers starting with 0 become WhatsApp links for Algeria (+213).': [
    'Les numéros commençant par 0 deviennent des liens WhatsApp pour l\'Algérie (+213).',
    'الأرقام التي تبدأ بـ 0 تتحول إلى روابط واتساب للجزائر (+213).'
  ],
  'Uploading photos...': ['Envoi des photos...', 'جارٍ رفع الصور...'],
  'Save changes': ['Enregistrer les modifications', 'حفظ التغييرات'],
  'Post listing': ["Publier l'annonce", 'نشر الإعلان'],
  'Title is required': ['Le titre est obligatoire', 'العنوان مطلوب'],
  'Please choose a category': ['Choisissez une catégorie', 'يرجى اختيار فئة'],
  'Price must be a number': ['Le prix doit être un nombre', 'يجب أن يكون السعر رقماً'],
  'Only 3 photos are allowed per listing.': [
    'Seulement 3 photos sont autorisées par annonce.',
    'يُسمح بـ 3 صور فقط لكل إعلان.'
  ],
  // Profile set-up page and profile bar
  'Complete your profile': ['Complétez votre profil', 'أكمل ملفك الشخصي'],
  'Set up your profile': ['Configurez votre profil', 'إعداد ملفك الشخصي'],
  'Add a photo and your wilaya so other students can trust you.': [
    'Ajoutez une photo et votre wilaya pour que les autres étudiants puissent vous faire confiance.',
    'أضف صورة وولايتك حتى يتمكن الطلاب الآخرون من الوثوق بك.'
  ],
  'Tap to add a photo (required)': [
    'Touchez pour ajouter une photo (obligatoire)',
    'اضغط لإضافة صورة (إلزامي)'
  ],
  'Name': ['Nom', 'الاسم'],
  'Your name is missing. Contact UniBridge support to add it.': [
    'Votre nom est manquant. Contactez le support UniBridge pour l\'ajouter.',
    'اسمك غير موجود. تواصل مع دعم UniBridge لإضافته.'
  ],
  'Wilaya (required)': ['Wilaya (obligatoire)', 'الولاية (إلزامي)'],
  'City or area (optional)': ['Ville ou quartier (facultatif)', 'المدينة أو الحي (اختياري)'],
  'Your profile could not be saved. Please contact UniBridge support.': [
    'Votre profil n\'a pas pu être enregistré. Contactez le support UniBridge.',
    'تعذّر حفظ ملفك الشخصي. يرجى التواصل مع دعم UniBridge.'
  ],
  'Could not load your profile. Check your connection.': [
    'Impossible de charger votre profil. Vérifiez votre connexion.',
    'تعذّر تحميل ملفك الشخصي. تحقق من اتصالك.'
  ],
  'Try again': ['Réessayer', 'حاول مرة أخرى'],
};
