import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/screens/add_car_screen.dart' show kCarPhotosBucket;
import 'package:torqueden/theme.dart';

/// Account settings: edit your profile (avatar, display name, username, bio) and
/// manage login credentials (email + password). All wired to Supabase.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _client = Supabase.instance.client;
  final _displayName = TextEditingController();
  final _username = TextEditingController();
  final _bio = TextEditingController();

  late Future<void> _loaded;
  String? _avatarUrl;
  Uint8List? _avatarBytes;
  bool _saving = false;

  String get _uid => _client.auth.currentUser!.id;
  String? get _email => _client.auth.currentUser?.email;

  @override
  void initState() {
    super.initState();
    _loaded = _load();
  }

  @override
  void dispose() {
    _displayName.dispose();
    _username.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final row = await _client
        .from('profiles')
        .select('username, display_name, avatar_url, bio')
        .eq('id', _uid)
        .maybeSingle();
    if (row != null) {
      _username.text = (row['username'] as String?) ?? '';
      _displayName.text = (row['display_name'] as String?) ?? '';
      _bio.text = (row['bio'] as String?) ?? '';
      _avatarUrl = row['avatar_url'] as String?;
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() { _avatarBytes = bytes; });
  }

  Future<void> _saveProfile() async {
    final username = _username.text.trim();
    if (username.length < 3) return _snack('Username must be at least 3 characters.');
    if (username.contains(' ')) return _snack('Usernames can\'t contain spaces.');

    setState(() { _saving = true; });
    try {
      String? avatarUrl;
      if (_avatarBytes != null) {
        final path = '$_uid/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await _client.storage.from(kCarPhotosBucket).uploadBinary(
              path,
              _avatarBytes!,
              fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
            );
        avatarUrl = _client.storage.from(kCarPhotosBucket).getPublicUrl(path);
      }
      final display = _displayName.text.trim();
      final bio = _bio.text.trim();
      await _client.from('profiles').update({
        'username': username,
        'display_name': display.isEmpty ? null : display,
        'bio': bio.isEmpty ? null : bio,
        'avatar_url': ?avatarUrl,
      }).eq('id', _uid);
      if (!mounted) return;
      setState(() {
        if (avatarUrl != null) { _avatarUrl = avatarUrl; _avatarBytes = null; }
        _saving = false;
      });
      _snack('Profile saved.');
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() { _saving = false; });
      _snack(e.code == '23505' ? 'That username is taken.' : 'Could not save: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() { _saving = false; });
      _snack('Could not save: $e');
    }
  }

  Future<void> _changeEmail() async {
    final controller = TextEditingController(text: _email ?? '');
    final newEmail = await showDialog<String>(
      context: context,
      builder: (ctx) => _InputDialog(
        title: 'Change email',
        message: 'We\'ll send a confirmation link to the new address. The change '
            'takes effect once you confirm it.',
        controller: controller,
        label: 'New email',
        keyboardType: TextInputType.emailAddress,
        actionLabel: 'Send link',
        validate: (v) => (v.contains('@') && v.contains('.')) ? null : 'Enter a valid email',
      ),
    );
    controller.dispose();
    if (newEmail == null) return;
    try {
      await _client.auth.updateUser(UserAttributes(email: newEmail.trim()));
      _snack('Confirmation link sent to ${newEmail.trim()}.');
    } on AuthException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Could not change email: $e');
    }
  }

  Future<void> _changePassword() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => const _PasswordDialog(),
    );
    if (result == null) return;
    try {
      await _client.auth.updateUser(UserAttributes(password: result));
      _snack('Password updated.');
    } on AuthException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Could not change password: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: SafeArea(
        child: FutureBuilder<void>(
          future: _loaded,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: AppColors.ember));
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Center(child: _avatarPicker()),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: _saving ? null : _pickAvatar,
                    child: Text(
                      (_avatarBytes != null || (_avatarUrl?.isNotEmpty ?? false)) ? 'Change photo' : 'Add photo',
                      style: GoogleFonts.inter(color: AppColors.ember, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _displayName,
                  textCapitalization: TextCapitalization.words,
                  style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    hintText: 'Shown on your posts (optional)',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _username,
                  style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixText: '@',
                    hintText: 'boostedmk7',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _bio,
                  maxLines: 4,
                  maxLength: 200,
                  textCapitalization: TextCapitalization.sentences,
                  style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
                  decoration: const InputDecoration(
                    labelText: 'Bio',
                    hintText: 'A line about you and your builds.',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _saving ? null : _saveProfile,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onEmber))
                      : const Text('Save profile'),
                ),
                const SizedBox(height: 28),
                Text('LOGIN & SECURITY',
                    style: GoogleFonts.inter(
                        color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
                const SizedBox(height: 4),
                _row(
                  icon: Icons.alternate_email,
                  title: 'Email',
                  subtitle: _email ?? 'Not set',
                  actionLabel: 'Change',
                  onTap: _changeEmail,
                ),
                _row(
                  icon: Icons.lock_outline,
                  title: 'Password',
                  subtitle: '••••••••',
                  actionLabel: 'Change',
                  onTap: _changePassword,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _avatarPicker() {
    Widget child;
    if (_avatarBytes != null) {
      child = Image.memory(_avatarBytes!, fit: BoxFit.cover);
    } else if (_avatarUrl?.isNotEmpty ?? false) {
      child = Image.network(_avatarUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => _avatarFallback());
    } else {
      child = _avatarFallback();
    }
    return GestureDetector(
      onTap: _saving ? null : _pickAvatar,
      child: Stack(
        children: [
          ClipOval(child: SizedBox(width: 96, height: 96, child: child)),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(color: AppColors.ember, shape: BoxShape.circle),
              child: const Icon(Icons.photo_camera, size: 16, color: AppColors.onEmber),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarFallback() {
    final seed = _username.text.trim();
    return Container(
      color: AppColors.graphiteRaised,
      alignment: Alignment.center,
      child: Text(
        seed.isNotEmpty ? seed[0].toUpperCase() : '?',
        style: GoogleFonts.archivo(fontSize: 36, fontWeight: FontWeight.w800, color: AppColors.ember),
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: ListTile(
        tileColor: AppColors.graphite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.hairline),
        ),
        leading: Icon(icon, color: AppColors.steel),
        title: Text(title, style: GoogleFonts.inter(color: AppColors.cream, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
        trailing: TextButton(
          onPressed: onTap,
          child: Text(actionLabel, style: GoogleFonts.inter(color: AppColors.ember, fontWeight: FontWeight.w600)),
        ),
        onTap: onTap,
      ),
    );
  }
}

/// A simple single-field dialog returning the trimmed text (or null on cancel).
class _InputDialog extends StatefulWidget {
  const _InputDialog({
    required this.title,
    required this.controller,
    required this.label,
    required this.actionLabel,
    this.message,
    this.keyboardType,
    this.validate,
  });

  final String title;
  final String? message;
  final TextEditingController controller;
  final String label;
  final String actionLabel;
  final TextInputType? keyboardType;
  final String? Function(String)? validate;

  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  String? _error;

  void _submit() {
    final value = widget.controller.text.trim();
    final err = widget.validate?.call(value);
    if (err != null) { setState(() { _error = err; }); return; }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.graphite,
      title: Text(widget.title,
          style: GoogleFonts.archivo(color: AppColors.cream, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.message != null) ...[
            Text(widget.message!, style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: widget.controller,
            keyboardType: widget.keyboardType,
            autofocus: true,
            style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
            decoration: InputDecoration(labelText: widget.label, errorText: _error),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.steel))),
        TextButton(
          onPressed: _submit,
          child: Text(widget.actionLabel, style: GoogleFonts.inter(color: AppColors.ember, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

/// New-password dialog: enter + confirm. Returns the new password on success.
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (_pass.text.length < 6) { setState(() { _error = 'At least 6 characters'; }); return; }
    if (_pass.text != _confirm.text) { setState(() { _error = 'Passwords don\'t match'; }); return; }
    Navigator.pop(context, _pass.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.graphite,
      title: Text('Change password',
          style: GoogleFonts.archivo(color: AppColors.cream, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _pass,
            obscureText: true,
            style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
            decoration: const InputDecoration(labelText: 'New password'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            obscureText: true,
            style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
            decoration: InputDecoration(labelText: 'Confirm password', errorText: _error),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.steel))),
        TextButton(
          onPressed: _submit,
          child: Text('Update', style: GoogleFonts.inter(color: AppColors.ember, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
