/// Drafted policy text for TorqueDen. Shown in-app (Settings → Data & policies)
/// and intended to be copied to hosted URLs for the App Store / Play Store
/// listings.
///
/// NOT LEGAL ADVICE — have these reviewed before launch, and fill in the
/// bracketed company/contact details if they change.
library;

class PolicySection {
  const PolicySection(this.heading, this.body);
  final String heading;
  final String body;
}

class PolicyDoc {
  const PolicyDoc({required this.title, required this.effective, required this.sections});
  final String title;
  final String effective;
  final List<PolicySection> sections;
}

const String _kOperator = 'Aquamain';
const String _kContact = 'support@torqueden.app';
const String _kEffective = '5 July 2026';

const PolicyDoc kPrivacyPolicy = PolicyDoc(
  title: 'Privacy Policy',
  effective: _kEffective,
  sections: [
    PolicySection(
      'Who we are',
      'TorqueDen ("the app", "we", "us") is operated by $_kOperator. This policy '
      'explains what personal data we collect, why, and your rights over it. We '
      'are the data controller. For any privacy question, contact us at $_kContact.',
    ),
    PolicySection(
      'What we collect',
      '• Account details: your email address, username, and password (passwords are '
      'stored only as secure hashes by our authentication provider).\n'
      '• Profile details you choose to add: display name, bio, and profile photo.\n'
      '• Content you create: cars and build logs, photos and videos, feed posts, '
      'clubs, threads, replies, comments, and votes.\n'
      '• Approximate location: only if you use "near me" features. Your location is '
      'rounded to roughly a 1 km area before it is stored — we never keep your exact '
      'position.\n'
      '• Preferences: settings such as your notification choices and distance units.\n'
      '• Basic technical/usage data needed to run the service reliably.',
    ),
    PolicySection(
      'Why we use it (and our lawful basis)',
      '• To provide the app and your account (performance of our contract with you).\n'
      '• To show content near you and personalise the feed (your consent, given when '
      'you enable location; you can turn it off any time).\n'
      '• To keep the community safe — moderation, reports, and blocking (our '
      'legitimate interest in a safe service, and compliance with app-store rules).\n'
      '• To respond to your requests and provide support (our legitimate interest).',
    ),
    PolicySection(
      'Who we share it with',
      'We use trusted service providers who process data on our behalf under '
      'contract:\n'
      '• Supabase — cloud hosting, database, file storage, and authentication.\n'
      'Content you post publicly (cars, posts, club activity) is visible to other '
      'users by design. We do not sell your personal data. If we add advertising or '
      'payments in future (e.g. Google AdMob, PayPal), we will update this policy and '
      'name those providers before enabling them.',
    ),
    PolicySection(
      'Storage and retention',
      'Your data is stored on our providers\' servers. We keep it for as long as your '
      'account is active. When you delete your account, your account and associated '
      'personal data and content are deleted. Some information may persist briefly in '
      'backups before being overwritten.',
    ),
    PolicySection(
      'Your rights',
      'Under UK/EU data protection law you can: access the data we hold about you; '
      'have it corrected; have it erased; object to or restrict certain processing; '
      'and request a copy in a portable format. You can delete your account and its '
      'data at any time from Settings → Account → Delete account. To exercise any '
      'other right, email $_kContact — we aim to respond within one month. You also '
      'have the right to complain to the UK Information Commissioner\'s Office (ICO).',
    ),
    PolicySection(
      'Children',
      'TorqueDen is not intended for children under 13 (or the minimum age required in '
      'your country). We do not knowingly collect data from children under that age.',
    ),
    PolicySection(
      'Changes',
      'We may update this policy. We\'ll change the effective date above and, for '
      'significant changes, tell you in the app.',
    ),
  ],
);

const PolicyDoc kTermsOfService = PolicyDoc(
  title: 'Terms of Service',
  effective: _kEffective,
  sections: [
    PolicySection(
      'Acceptance',
      'By creating an account or using TorqueDen you agree to these Terms and to our '
      'Privacy Policy and Community Guidelines. If you don\'t agree, don\'t use the app.',
    ),
    PolicySection(
      'Eligibility & your account',
      'You must be at least 13 (or the minimum age in your country) to use TorqueDen. '
      'You\'re responsible for your account and for keeping your login secure. Provide '
      'accurate information and don\'t impersonate others.',
    ),
    PolicySection(
      'Zero tolerance for objectionable content and abuse',
      'There is no tolerance for objectionable content or abusive behaviour on '
      'TorqueDen. You agree not to post content that is unlawful, hateful, harassing, '
      'threatening, sexually explicit, violent, or that infringes others\' rights, and '
      'not to abuse, harass, or harm other users. Violations may result in content '
      'removal and account termination. See our Community Guidelines for detail.',
    ),
    PolicySection(
      'Your content',
      'You keep ownership of the content you post. You grant us a licence to host, '
      'store, display, and distribute it within the app so we can operate the service. '
      'You\'re responsible for the content you post and confirm you have the right to '
      'post it.',
    ),
    PolicySection(
      'Moderation & reporting',
      'You can report content or users, and block users, from within the app. We '
      'review reports and act on objectionable content — typically removing it and, '
      'where appropriate, removing the responsible user — within 24 hours. Club owners '
      'and admins may also moderate their own clubs.',
    ),
    PolicySection(
      'Memberships & payments',
      'TorqueDen may offer paid memberships (e.g. Premium, Partner). Where purchases '
      'are made through the App Store or Google Play, the store\'s billing terms apply '
      'and subscriptions renew unless cancelled in your device settings. Pricing and '
      'features will be shown before you buy.',
    ),
    PolicySection(
      'Termination',
      'You may stop using TorqueDen and delete your account at any time. We may '
      'suspend or terminate accounts that breach these Terms or the Community '
      'Guidelines.',
    ),
    PolicySection(
      'Disclaimers & liability',
      'TorqueDen is provided "as is". To the extent permitted by law, we\'re not liable '
      'for indirect or consequential loss. Nothing in these Terms limits liability that '
      'cannot be limited by law.',
    ),
    PolicySection(
      'Governing law',
      'These Terms are governed by the laws of England and Wales. Questions? Contact '
      '$_kContact.',
    ),
  ],
);

const PolicyDoc kCommunityGuidelines = PolicyDoc(
  title: 'Community Guidelines',
  effective: _kEffective,
  sections: [
    PolicySection(
      'Keep it about the builds',
      'TorqueDen is for car people to share builds, ask questions, and find their '
      'crew. Keep posts and clubs relevant and constructive.',
    ),
    PolicySection(
      'Be respectful',
      'Treat others how you\'d want to be treated. No harassment, bullying, hate '
      'speech, threats, or targeting people over race, religion, gender, sexuality, '
      'disability, or nationality.',
    ),
    PolicySection(
      'Not allowed',
      '• Illegal content or promoting dangerous or illegal activity.\n'
      '• Sexually explicit or graphic violent content.\n'
      '• Spam, scams, or misleading content.\n'
      '• Sharing others\' private information without consent.\n'
      '• Impersonation, or infringing someone else\'s copyright or trademarks.',
    ),
    PolicySection(
      'Reporting & consequences',
      'If you see something that breaks these guidelines, report it (long-press or use '
      'the report option) or block the user. We review reports and act — usually '
      'within 24 hours — by removing content and, where needed, removing the user. '
      'Serious or repeated breaches lead to account termination.',
    ),
    PolicySection(
      'Questions',
      'Not sure if something\'s allowed? Ask us at $_kContact.',
    ),
  ],
);
