import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/club.dart';
import 'package:torqueden/theme.dart';

/// Create a new club. Pops the created [Club] on success (the owner is added as
/// a member automatically by a DB trigger).
class CreateClubScreen extends StatefulWidget {
  const CreateClubScreen({super.key});

  @override
  State<CreateClubScreen> createState() => _CreateClubScreenState();
}

class _CreateClubScreenState extends State<CreateClubScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final client = Supabase.instance.client;
    final desc = _description.text.trim();
    try {
      // owner_id defaults to auth.uid(); the trigger adds owner membership.
      final rows = await client.from('clubs').insert({
        'name': _name.text.trim(),
        'description': desc.isEmpty ? null : desc,
      }).select('*, club_members(count)');
      if (mounted) Navigator.of(context).pop(Club.fromMap(rows.first));
    } on PostgrestException catch (e) {
      _fail('Could not create the club: ${e.message}');
    } catch (e) {
      _fail('Could not create the club: $e');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 5)),
    );
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create a club')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 60,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Give your club a name' : null,
                    decoration: const InputDecoration(
                      labelText: 'Club name *',
                      hintText: 'e.g. E85 Tuning',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _description,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 4,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      labelText: 'What\'s it about?',
                      hintText: 'A line or two so people know what they\'re joining.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_saving)
                    const Center(child: CircularProgressIndicator(color: AppColors.ember))
                  else
                    FilledButton.icon(
                      onPressed: _create,
                      icon: const Icon(Icons.groups, size: 20),
                      label: const Text('Create club'),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Your club is public — anyone can find it and join. You\'re the owner and can remove posts.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
