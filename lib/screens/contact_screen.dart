import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:torqueden/support_links.dart';
import 'package:torqueden/theme.dart';

/// Contact us & Feedback — composes an email to the support inbox via the
/// device's mail app (mailto). If no mail client is available, the address is
/// offered to copy instead.
class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  static const _topics = <String>['General question', 'Feedback', 'Bug report', 'Report a problem'];

  String _topic = _topics.first;
  final _message = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _send() async {
    final body = _message.text.trim();
    if (body.isEmpty) return _snack('Add a message first.');
    setState(() { _sending = true; });
    final uri = Uri.parse(
      'mailto:${SupportLinks.supportEmail}'
      '?subject=${Uri.encodeComponent('[TorqueDen] $_topic')}'
      '&body=${Uri.encodeComponent(body)}',
    );
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      setState(() { _sending = false; });
      if (!ok) _noMailApp();
    } catch (_) {
      if (!mounted) return;
      setState(() { _sending = false; });
      _noMailApp();
    }
  }

  void _noMailApp() {
    Clipboard.setData(const ClipboardData(text: SupportLinks.supportEmail));
    _snack('No mail app found. Copied ${SupportLinks.supportEmail} to your clipboard.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contact us & Feedback')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(
              'Questions, ideas, or something not working? Send us a note and we\'ll '
              'get back to you.',
              style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 14, height: 1.45),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: _topic,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Topic',
                prefixIcon: Icon(Icons.label_outline, color: AppColors.steel, size: 20),
              ),
              dropdownColor: AppColors.graphiteRaised,
              style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
              iconEnabledColor: AppColors.steel,
              items: [for (final t in _topics) DropdownMenuItem(value: t, child: Text(t))],
              onChanged: (v) => v == null ? null : setState(() { _topic = v; }),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _message,
              maxLines: 8,
              minLines: 5,
              textCapitalization: TextCapitalization.sentences,
              style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
              decoration: const InputDecoration(
                labelText: 'Message',
                hintText: 'Tell us what\'s on your mind…',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _sending ? null : _send,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onEmber))
                  : const Icon(Icons.send_outlined, size: 20),
              label: const Text('Send'),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text('Sends to ${SupportLinks.supportEmail}',
                  style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
