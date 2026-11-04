import 'package:flutter/material.dart';
import 'l10n.dart';

// ---------------- Terms of use + Privacy policy ----------------
// A template written for this app. Have it checked before release.

const String kContactEmail = 'mudaranokutenda@gmail.com';
const String kLegalLastUpdated = '4 November 2026';

const List<(String, String)> kTermsSections = [
  (
    'About UniBridge',
    'UniBridge helps students in Algeria find each other to exchange money '
        'and to buy and sell items. UniBridge never holds, sends or receives '
        'money. Every exchange happens directly between the two users, '
        'outside the app.',
  ),
  (
    'Your account',
    'You must give true information about yourself and keep your password '
        'secret. One person, one account. You may delete your account at any '
        'time from your profile.',
  ),
  (
    'Exchanges between users',
    'You are fully responsible for every exchange you make, and for '
        'respecting the laws of Algeria, including the rules on foreign '
        'currency. UniBridge is not a party to any exchange and does not '
        'guarantee that the other user will keep their promise. Both users '
        'must confirm in the app before an exchange counts as completed. If '
        'something goes wrong, open a dispute in the chat.',
  ),
  (
    'Marketplace',
    'Only list items you own and are allowed to sell. Forbidden: illegal '
        'items, weapons, drugs, stolen goods, fake documents, and anything '
        'that breaks the law.',
  ),
  (
    'Behaviour',
    'No scams, harassment, insults, spam, fake profiles or sharing other '
        "people's private information. You can report and block any user. We "
        'may hide content or close accounts that break these rules.',
  ),
  (
    'No warranty',
    'The app is provided "as is". Exchange rates shown in the app are for '
        'information only. As far as the law allows, UniBridge is not liable '
        'for losses caused by exchanges or deals between users.',
  ),
  (
    'Changes',
    'We may update these terms. The date at the top shows the latest '
        'version. If you keep using the app, you accept the new terms.',
  ),
  ('Contact', 'Questions: $kContactEmail'),
];

const List<(String, String)> kPrivacySections = [
  (
    'What we collect',
    '• Account: name, email, student inscription number.\n'
        '• Profile: wilaya, location you type, profile photo.\n'
        '• Verification (optional): photo of your student card. Only you '
        'and the UniBridge team can see it.\n'
        '• Activity: your requests, chats (text, photos, and a location only '
        'when you choose to share it), listings, ratings, reports and blocks.\n'
        '• Device: a notification token so we can send you push '
        'notifications.',
  ),
  (
    'What other users see',
    'Your name, profile photo, wilaya, location, verification badge, rating '
        'and member-since date. Your email, inscription number and student '
        'card are never shown to other users.',
  ),
  (
    'Why we use it',
    'To run the app: matching, chat, marketplace, notifications, trust and '
        'safety (verification, reports, disputes). We do not sell your data '
        'and we do not show ads.',
  ),
  (
    'Where it is stored',
    'Data is stored with Supabase (database, login, files). Push '
        'notifications go through Google Firebase. Google sign-in is handled '
        'by Google. These services may store data outside Algeria.',
  ),
  (
    'Location',
    'The app reads your location only when you press the location button in '
        'a chat and confirm. It is read once and sent only to that chat. The '
        'app never tracks you.',
  ),
  (
    'How long we keep it',
    'Until you delete your account. When you delete it, your profile, '
        'photos, listings, open requests and notifications are deleted. '
        'Finished exchanges, chats and ratings stay for the other person, '
        'shown as "UniBridge user", because they may be needed to solve '
        'disputes. Reports about an account may be kept for safety.',
  ),
  (
    'Your rights',
    'You can see and change your profile in the app, delete your account in '
        'the app, and write to us to ask for a copy of your data or to correct '
        'it (Algerian law 18-07 on personal data).',
  ),
  ('Contact', 'Privacy questions: $kContactEmail'),
];

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
        body: const TabBarView(
          children: [
            _LegalText(sections: kTermsSections),
            _LegalText(sections: kPrivacySections),
          ],
        ),
      ),
    );
  }
}

class _LegalText extends StatelessWidget {
  final List<(String, String)> sections;
  const _LegalText({required this.sections});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(tr('Last updated: {date}', {'date': kLegalLastUpdated}),
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
