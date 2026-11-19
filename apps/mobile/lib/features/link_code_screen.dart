import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/account_repository.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
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
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: heroGradient),
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Stack(
                    children: [
                      HeroStage(height: (box.maxHeight * 0.36).clamp(220, 320), quietCorner: true),
                      Positioned(
                        right: 8,
                        top: 8 + MediaQuery.paddingOf(context).top,
                        child: TextButton(
                          key: const Key('sign-out'),
                          style: TextButton.styleFrom(foregroundColor: Colors.white),
                          onPressed: () => ref.read(accountRepositoryProvider).signOut(),
                          child: const Text('Sign out'),
                        ),
                      ),
                    ],
                  ),
                  BottomSheetPanel(
                    children: [
                      Text('Link your record', style: text.headlineMedium),
                      const SizedBox(height: 6),
                      Text('Enter the 16-character code from the front desk. It works once and lasts 7 days.', style: text.bodyLarge),
                      const SizedBox(height: 22),
                      TextField(
                        key: const Key('code'),
                        controller: _code,
                        textCapitalization: TextCapitalization.characters,
                        autocorrect: false,
                        enableSuggestions: false,
                        maxLength: 16,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]'))],
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 3, color: Palette.deepSea),
                        onSubmitted: (_) => _link(),
                        decoration: const InputDecoration(labelText: 'Code', counterText: ''),
                      ),
                      if (_error != null) ...[const SizedBox(height: 14), ErrorNote(_error!)],
                      const SizedBox(height: 22),
                      PrimaryButton(key: const Key('link'), label: 'Link my record', busy: _busy, onPressed: _link),
                    ],
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
