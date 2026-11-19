import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/account_repository.dart';
import '../state.dart';

/// Shown until the sign-in is linked to a patient record with the front desk's one-time code.
class LinkCodeScreen extends ConsumerStatefulWidget {
  const LinkCodeScreen({super.key});

  @override
  ConsumerState<LinkCodeScreen> createState() => _LinkCodeScreenState();
}

class _LinkCodeScreenState extends ConsumerState<LinkCodeScreen> {
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _link() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accountRepositoryProvider).redeemCode(_code.text);
      ref.invalidate(linkedPatientsProvider);
    } on AccountError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(actions: [
        TextButton(
          key: const Key('sign-out'),
          onPressed: () => ref.read(accountRepositoryProvider).signOut(),
          child: const Text('Sign out'),
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Text('Link your record', style: text.headlineSmall),
        const SizedBox(height: 8),
        Text('Enter the 16-character code the front desk gave you. It works once and lasts 7 days.', style: text.bodyLarge),
        const SizedBox(height: 24),
        TextField(
          key: const Key('code'),
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          onSubmitted: (_) => _link(),
          decoration: const InputDecoration(labelText: 'Code', border: OutlineInputBorder()),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 24),
        FilledButton(key: const Key('link'), onPressed: _busy ? null : _link, child: const Text('Link my record')),
      ]),
    );
  }
}
