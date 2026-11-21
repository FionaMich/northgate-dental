import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfx/pdfx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/care_repository.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../state.dart';
import 'care_widgets.dart';

/// Opens a short-lived document link outside the app (PDFs open in the phone's viewer). Replaced in tests.
final documentOpenerProvider = Provider<Future<void> Function(String url)>(
  (ref) => (url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  },
);

/// Fetches a PDF over its short-lived link into memory (never written to the phone's storage). Replaced in tests.
final pdfBytesLoaderProvider = Provider<Future<Uint8List> Function(String url)>(
  (ref) => (url) async {
    final client = HttpClient();
    try {
      final res = await (await client.getUrl(Uri.parse(url))).close();
      if (res.statusCode != 200) throw const HttpException('document not available');
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in res) {
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } finally {
      client.close();
    }
  },
);

/// Draws a PDF with the phone's own PDF renderer (pdfx). Replaced in tests, where no renderer is available.
final pdfViewProvider = Provider<Widget Function(Uint8List bytes)>(
  (ref) =>
      (bytes) => _PdfPages(bytes),
);

/// Pinch-to-zoom pages of one PDF held in memory.
class _PdfPages extends StatefulWidget {
  const _PdfPages(this.bytes);
  final Uint8List bytes;

  @override
  State<_PdfPages> createState() => _PdfPagesState();
}

class _PdfPagesState extends State<_PdfPages> {
  late final _controller = PdfControllerPinch(document: PdfDocument.openData(widget.bytes));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PdfViewPinch(controller: _controller, padding: 12);
}

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
              image: heroPhoto,
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
                            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.8, color: Colors.white),
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
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const TintIcon(Icons.chat_bubble_outline_rounded, Tint.sky),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(v.reason!, style: const TextStyle(fontSize: 15, height: 1.45, color: Palette.deepSea)),
                        ),
                      ],
                    ),
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
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Palette.deepSea),
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
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFB35F1E)),
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

/// The 32 permanent teeth on two arches, as the patient faces you (Universal numbering): treated teeth in teal,
/// planned treatment in apricot, teeth the dentist noted ringed. Numbers show only on teeth with something to say.
class ToothChart extends StatelessWidget {
  const ToothChart({super.key, required this.procedures, required this.findings});
  final List<Procedure> procedures;
  final List<Finding> findings;

  // Molars are widest, then premolars, canines and incisors; one side of the arch, back to front.
  static const _sideWidths = [1.25, 1.25, 1.25, 0.95, 0.95, 0.85, 0.78, 0.82];

  @override
  Widget build(BuildContext context) => Column(
    children: [
      LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth, h = w * 0.86;
          final unit = w / 15.5;
          final widths = [..._sideWidths, ..._sideWidths.reversed]; // 16 teeth, back right to back left
          final total = widths.fold(0.0, (a, b) => a + b);
          final children = <Widget>[];
          for (final upper in [true, false]) {
            final cx = w / 2, cy = upper ? h * 0.48 : h * 0.52;
            final rx = w * 0.43, ry = h * 0.40;
            var run = 0.0;
            for (var k = 0; k < 16; k++) {
              final mid = (run + widths[k] / 2) / total;
              run += widths[k];
              // Upper arch runs over the top (pi to 2pi), lower arch under the bottom (pi down to 0).
              final theta = upper ? math.pi + 0.10 + mid * (math.pi - 0.20) : math.pi - 0.10 - mid * (math.pi - 0.20);
              final x = cx + rx * math.cos(theta), y = cy + ry * math.sin(theta);
              final number = upper ? '${k + 1}' : '${32 - k}';
              final tw = unit * widths[k], th = unit * 1.15;
              children.add(
                Positioned(
                  left: x - tw / 2,
                  top: y - th / 2,
                  child: Transform.rotate(angle: theta + math.pi / 2, child: _tooth(number, tw, th, theta + math.pi / 2)),
                ),
              );
            }
          }
          return SizedBox(
            width: w,
            height: h,
            child: Stack(
              children: [
                ...children,
                Align(
                  alignment: const Alignment(0, -0.12),
                  child: Text(
                    'Upper',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Palette.muted.withValues(alpha: 0.8)),
                  ),
                ),
                Align(
                  alignment: const Alignment(0, 0.12),
                  child: Text(
                    'Lower',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Palette.muted.withValues(alpha: 0.8)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      const SizedBox(height: 8),
      const Wrap(
        spacing: 14,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [_Key(Palette.teal, 'Treated'), _Key(Palette.apricot, 'Planned'), _Key(null, 'Noted by the dentist')],
      ),
    ],
  );

  Widget _tooth(String n, double w, double h, double turn) {
    final here = procedures.where((p) => p.tooth == n);
    final done = here.any((p) => p.done), planned = here.any((p) => !p.done);
    final noted = findings.any((f) => f.tooth == n);
    final states = [if (done) 'treated', if (planned) 'treatment planned', if (noted) 'finding'];
    final fill = done ? Palette.teal : (planned ? Palette.apricot : Colors.white);
    return Semantics(
      label: states.isEmpty ? 'Tooth $n' : 'Tooth $n: ${states.join(', ')}',
      child: ExcludeSemantics(
        child: Container(
          width: w,
          height: h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.vertical(top: Radius.circular(w * 0.45), bottom: Radius.circular(w * 0.3)),
            border: Border.all(
              color: noted ? const Color(0xFFB35F1E) : (states.isEmpty ? const Color(0xFFCFE0DC) : Colors.transparent),
              width: noted ? 2 : 1.2,
            ),
            boxShadow: states.isEmpty ? null : lift(0.6),
          ),
          child: states.isEmpty
              ? null
              : Transform.rotate(
                  angle: -turn, // the number stays upright while the tooth follows the arch
                  child: Text(
                    n,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: done ? Colors.white : Palette.deepSea),
                  ),
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

/// A shared document: X-rays and PDFs both open inside the app, through a 5-minute link; downloading is optional.
class DocumentTile extends ConsumerStatefulWidget {
  const DocumentTile({super.key, required this.document, this.card = false});
  final PracticeDocument document;

  /// A tall card for the swipeable row in Records, instead of a full-width row.
  final bool card;

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
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => d.isImage ? _ImageViewer(title: d.title, url: url) : _PdfScreen(title: d.title, url: url),
        ),
      );
    } on CoverageError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.document;
    if (widget.card) {
      final tint = d.isImage ? Tint.sky : Tint.apricot;
      return Pressable(
        onTap: _busy ? null : _open,
        child: GestureDetector(
          key: Key('doc-${d.id}'),
          onTap: _busy ? null : _open,
          child: Container(
            width: 172,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE3ECEA)),
              boxShadow: lift(0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TintIcon(d.isImage ? Icons.image_outlined : Icons.picture_as_pdf_outlined, tint, size: 44),
                    const Spacer(),
                    _busy
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.north_east_rounded, size: 18, color: tint.ink),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  d.isImage ? 'IMAGE' : 'PDF',
                  maxLines: 1,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1, color: tint.ink),
                ),
                const SizedBox(height: 4),
                Expanded(
                  // takes the room that is left, so a long title shortens with "..." instead of overflowing
                  child: Text(
                    d.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, height: 1.3, fontWeight: FontWeight.w700, color: Palette.deepSea),
                  ),
                ),
                const SizedBox(height: 4),
                Text(dayMonthYear(d.sharedAt), maxLines: 1, style: const TextStyle(fontSize: 12.5, color: Palette.muted)),
              ],
            ),
          ),
        ),
      );
    }
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
                : const Icon(Icons.chevron_right_rounded, color: Palette.teal),
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

/// A PDF shown inside the app; "Download" hands the short-lived link to the phone only if the patient asks.
class _PdfScreen extends ConsumerStatefulWidget {
  const _PdfScreen({required this.title, required this.url});
  final String title, url;

  @override
  ConsumerState<_PdfScreen> createState() => _PdfScreenState();
}

class _PdfScreenState extends ConsumerState<_PdfScreen> {
  late final Future<Uint8List> _bytes = ref.read(pdfBytesLoaderProvider)(widget.url);

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Palette.mist,
    appBar: AppBar(
      backgroundColor: Palette.heroMid,
      foregroundColor: Colors.white,
      title: Text(widget.title, style: const TextStyle(fontSize: 16)),
      actions: [
        IconButton(
          tooltip: 'Download',
          icon: const Icon(Icons.download_rounded),
          onPressed: () => ref.read(documentOpenerProvider)(widget.url),
        ),
      ],
    ),
    body: FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('We could not open this document. Check your connection and try again.', textAlign: TextAlign.center),
            ),
          );
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
        return ref.read(pdfViewProvider)(snap.data!);
      },
    ),
  );
}
