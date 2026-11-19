import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../state.dart';

/// Home for the chosen person. Visits, plans and appointments are added in T3.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(linkedPatientsProvider).value ?? const [];
    final current = ref.watch(currentPatientProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Northgate Dental'), actions: [
        TextButton(
          key: const Key('sign-out'),
          onPressed: () => ref.read(accountRepositoryProvider).signOut(),
          child: const Text('Sign out'),
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        if (people.length > 1) ...[
          Wrap(spacing: 8, children: [
            for (final p in people)
              ChoiceChip(
                key: Key('person-${p.id}'),
                label: Text(p.isSelf ? '${p.firstName} (you)' : p.firstName),
                selected: p.id == current?.id,
                onSelected: (_) => ref.read(selectedPatientProvider.notifier).select(p.id),
              ),
          ]),
          const SizedBox(height: 24),
        ],
        Text('Hello, ${current?.firstName ?? ''}', style: text.headlineSmall),
      ]),
    );
  }
}
