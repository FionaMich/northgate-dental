import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../design/art.dart';
import '../design/tokens.dart';
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
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: heroGradient,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 28),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Positioned(right: 18, top: 70, child: Orb(size: 52, tone: OrbTone.teal)),
                const Positioned(right: 120, top: 46, child: Orb(size: 14)),
                const Positioned(right: 40, top: 34, child: Tooth3D(height: 118)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Lockup(onDark: true, markHeight: 28),
                        const Spacer(),
                        TextButton(
                          key: const Key('sign-out'),
                          style: TextButton.styleFrom(foregroundColor: Colors.white),
                          onPressed: () => ref.read(accountRepositoryProvider).signOut(),
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 36),
                    SizedBox(
                      width: 210,
                      child: Text('Hello, ${current?.firstName ?? ''}', style: text.headlineLarge!.copyWith(color: Colors.white)),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Your smile, on track.',
                      style: TextStyle(color: Color(0xFFA9DCD1), fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                    if (people.length > 1) ...[
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final p in people)
                            _PersonChip(
                              key: Key('person-${p.id}'),
                              label: p.isSelf ? '${p.firstName} (you)' : p.firstName,
                              selected: p.id == current?.id,
                              onTap: () => ref.read(selectedPatientProvider.notifier).select(p.id),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), boxShadow: lift()),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(color: Palette.enamel, borderRadius: BorderRadius.circular(18)),
                    child: const Icon(Icons.event_available_outlined, color: Palette.teal),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Visits and plans', style: text.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          'Your appointments, visit history and treatment plan will show here.',
                          style: text.bodyLarge!.copyWith(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonChip extends StatelessWidget {
  const _PersonChip({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: selected ? 1 : 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: selected ? Palette.deepSea : Colors.white),
        ),
      ),
    ),
  );
}
