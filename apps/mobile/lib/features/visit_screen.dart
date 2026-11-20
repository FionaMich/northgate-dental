import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/care_repository.dart';
import '../design/format.dart';
import '../design/tokens.dart';
import '../state.dart';
import 'care_widgets.dart';

/// Opens a short-lived document link outside the app (PDFs open in the phone's viewer). Replaced in tests.
final documentOpenerProvider = Provider<Future<void> Function(String url)>(
  (ref) => (url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  },
);

/// One visit in full: who, where, why, a tooth chart, what was done with fees, findings and shared documents.
class VisitScreen extends ConsumerWidget {
  const VisitScreen({super.key, required this.visit});
  final Visit visit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = (ref.watch(careSummaryProvider).value?.documents ?? const []).where((d) => d.encounterId == visit.id).toList();
    final v = visit;
    return Scaffold(
      backgroundColor: Palette.mist,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              gradient: heroGradient,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      color: Colors.white,
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            visitTitle(v.kind),
                            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${weekday(v.at)} ${dayMonthYear(v.at)} · ${clock(v.at)}',
                            style: const TextStyle(fontSize: 15, color: Color(0xFFCDEFE7)),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _Chip(Icons.location_on_rounded, v.location),
                              if (v.dentist != null) _Chip(Icons.person_rounded, v.dentist!),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (v.reason != null && v.reason!.trim().isNotEmpty) ...[
                  const SectionTitle('Why you came'),
                  Panel(
                    child: Text(v.reason!, style: const TextStyle(fontSize: 15, height: 1.45, color: Palette.deepSea)),
                  ),
                  const SizedBox(height: 22),
                ],
                const SectionTitle('Your teeth at this visit'),
                Panel(
                  child: ToothChart(procedures: v.procedures, findings: v.findings),
                ),
                const SizedBox(height: 22),
                const SectionTitle('What was done'),
                Panel(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: v.procedures.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Text('No procedures were recorded at this visit.', style: TextStyle(color: Palette.muted)),
                        )
                      : Column(
                          children: [
                            for (final p in v.procedures)
                              Row(
                                children: [
                                  Expanded(child: ProcedureRow(p)),
                                  if (p.feeCents != null) ...[
                                    const SizedBox(width: 10),
                                    Text(
                                      dollars(p.feeCents!),
                                      style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.deepSea),
                                    ),
                                  ],
                                ],
                              ),
                            const Divider(height: 20, color: Palette.line),
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Total before insurance',
                                    style: TextStyle(fontWeight: FontWeight.w700, color: Palette.muted),
                                  ),
                                ),
                                Text(
                                  dollars(v.totalCents),
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Palette.deepSea),
                                ),
                              ],
                            ),
                          ],
                        ),
                ),
                if (v.findings.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const SectionTitle('What the dentist noted'),
                  Panel(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Column(
                      children: [
                        for (final f in v.findings)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: const Color(0xFFFFF1E4),
                              child: Text(
                                f.tooth,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFB35F1E)),
                              ),
                            ),
                            title: Text(
                              conditionLabel(f.condition),
                              style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.deepSea),
                            ),
                            subtitle: Text('Tooth ${f.tooth}${f.surface == null ? '' : ', ${surfaceLabel(f.surface!)}'}'),
                          ),
                      ],
                    ),
                  ),
                ],
                if (docs.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const SectionTitle('Documents from this visit'),
                  for (final d in docs) DocumentTile(document: d),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF8FE3C8)),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ],
    ),
  );
}

/// The 32 permanent teeth (Universal numbering, as the patient faces you): treated teeth in teal,
/// planned treatment in apricot, teeth with a finding ringed.
class ToothChart extends StatelessWidget {
  const ToothChart({super.key, required this.procedures, required this.findings});
  final List<Procedure> procedures;
  final List<Finding> findings;

  @override
  Widget build(BuildContext context) {
    Widget row(Iterable<int> numbers, String label) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Palette.muted),
        ),
        const SizedBox(height: 6),
        Row(children: [for (final n in numbers) Expanded(child: _tooth('$n'))]),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row([for (var n = 1; n <= 16; n++) n], 'Upper teeth'),
        const SizedBox(height: 12),
        row([for (var n = 32; n >= 17; n--) n], 'Lower teeth'),
        const SizedBox(height: 14),
        const Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [_Key(Palette.teal, 'Treated'), _Key(Palette.apricot, 'Planned'), _Key(null, 'Noted by the dentist')],
        ),
      ],
    );
  }

  Widget _tooth(String n) {
    final here = procedures.where((p) => p.tooth == n);
    final done = here.any((p) => p.done), planned = here.any((p) => !p.done);
    final noted = findings.any((f) => f.tooth == n);
    final states = [if (done) 'treated', if (planned) 'treatment planned', if (noted) 'finding'];
    return Semantics(
      label: states.isEmpty ? 'Tooth $n' : 'Tooth $n: ${states.join(', ')}',
      child: ExcludeSemantics(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done ? Palette.teal : (planned ? Palette.apricot : Palette.enamel),
            borderRadius: BorderRadius.circular(7),
            border: noted ? Border.all(color: const Color(0xFFB35F1E), width: 2) : null,
          ),
          child: Text(
            n,
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: done ? Colors.white : Palette.deepSea),
          ),
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key(this.color, this.label);
  final Color? color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color ?? Palette.enamel,
          borderRadius: BorderRadius.circular(4),
          border: color == null ? Border.all(color: const Color(0xFFB35F1E), width: 2) : null,
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12, color: Palette.muted)),
    ],
  );
}

/// A shared document: X-rays open in the app's viewer, PDFs in the phone's viewer, both through a 5-minute link.
class DocumentTile extends ConsumerStatefulWidget {
  const DocumentTile({super.key, required this.document});
  final PracticeDocument document;

  @override
  ConsumerState<DocumentTile> createState() => _DocumentTileState();
}

class _DocumentTileState extends ConsumerState<DocumentTile> {
  bool _busy = false;

  Future<void> _open() async {
    final d = widget.document;
    setState(() => _busy = true);
    try {
      final url = await ref.read(careRepositoryProvider).documentLink(d.path);
      if (!mounted) return;
      if (d.isImage) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _ImageViewer(title: d.title, url: url),
          ),
        );
      } else {
        await ref.read(documentOpenerProvider)(url);
      }
    } on CoverageError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.document;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        onTap: _busy ? null : _open,
        padding: const EdgeInsets.all(14),
        child: Row(
          key: Key('doc-${d.id}'),
          children: [
            IconTile(d.isImage ? Icons.image_outlined : Icons.picture_as_pdf_outlined, size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Palette.deepSea),
                  ),
                  Text(switch (d.kind) {
                    'xray' => 'X-ray image',
                    'visit_summary' => 'Visit summary (PDF)',
                    _ => d.isImage ? 'Image' : 'Letter (PDF)',
                  }, style: const TextStyle(fontSize: 13, color: Palette.muted)),
                ],
              ),
            ),
            _busy
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(d.isImage ? Icons.open_in_full_rounded : Icons.download_rounded, color: Palette.teal),
          ],
        ),
      ),
    );
  }
}

class _ImageViewer extends ConsumerWidget {
  const _ImageViewer({required this.title, required this.url});
  final String title, url;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(title, style: const TextStyle(fontSize: 16)),
      actions: [
        IconButton(tooltip: 'Download', icon: const Icon(Icons.download_rounded), onPressed: () => ref.read(documentOpenerProvider)(url)),
      ],
    ),
    body: InteractiveViewer(
      maxScale: 5,
      child: Center(
        child: Image.network(
          url,
          errorBuilder: (_, _, _) => const Text('Could not load the image.', style: TextStyle(color: Colors.white70)),
        ),
      ),
    ),
  );
}
