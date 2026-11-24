import 'package:dental/ui.dart';

import '../design/tokens.dart';

/// The pieces of a messenger-style conversation, shared by every chat in the app: Nora's and the team's.
/// Bubbles carry their own time and delivery ticks, the day sits in a chip, and whoever is writing shows as
/// three moving dots.

enum Delivery { sent, delivered, read }

const chatWallpaper = Color(0xFFE7EFEC);
const _mineBubble = Color(0xFFD5F3E9);
const _readBlue = Color(0xFF2D9CDB);

String chatTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.text,
    required this.at,
    this.mine = false,
    this.delivery,
    this.first = true,
  });

  final String text;
  final DateTime at;
  final bool mine;

  /// Ticks for the patient's own messages; null for the other side.
  final Delivery? delivery;

  /// The first bubble of a run from one side has the pointed corner.
  final bool first;

  @override
  Widget build(BuildContext context) {
    const round = Radius.circular(16);
    final point = first ? const Radius.circular(3) : round;
    return Align(
      alignment: mine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        margin: EdgeInsets.only(top: first ? 8 : 2),
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 6),
        decoration: BoxDecoration(
          color: mine ? _mineBubble : Colors.white,
          borderRadius: BorderRadiusDirectional.only(
            topStart: mine ? round : point,
            topEnd: mine ? point : round,
            bottomStart: round,
            bottomEnd: round,
          ),
          boxShadow: [
            BoxShadow(
              color: Palette.deepSea.withValues(alpha: 0.08),
              blurRadius: 1.5,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: 1,
              child: SelectableText(
                text,
                style: const TextStyle(
                  fontSize: 15.5,
                  height: 1.35,
                  color: Palette.deepSea,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  chatTime(at),
                  style: const TextStyle(fontSize: 11, color: Palette.muted),
                ),
                if (delivery != null) ...[
                  const SizedBox(width: 3),
                  Icon(
                    delivery == Delivery.sent
                        ? Icons.done_rounded
                        : Icons.done_all_rounded,
                    key: Key('ticks-${delivery!.name}'),
                    size: 16,
                    color: delivery == Delivery.read
                        ? _readBlue
                        : Palette.muted,
                    semanticLabel: tr(switch (delivery!) {
                      Delivery.sent => 'Sent',
                      Delivery.delivered => 'Delivered',
                      Delivery.read => 'Read',
                    }),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ChatDayChip extends StatelessWidget {
  const ChatDayChip(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Palette.muted,
        ),
      ),
    ),
  );
}

/// Three dots that rise in turn while the other side writes.
class ChatTyping extends StatefulWidget {
  const ChatTyping({super.key, required this.who});
  final String who;

  @override
  State<ChatTyping> createState() => _ChatTypingState();
}

class _ChatTypingState extends State<ChatTyping>
    with SingleTickerProviderStateMixin {
  late final _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: tr('${widget.who} is typing'),
    liveRegion: true,
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        key: const Key('chat-typing'),
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadiusDirectional.only(
            topStart: Radius.circular(3),
            topEnd: Radius.circular(16),
            bottomStart: Radius.circular(16),
            bottomEnd: Radius.circular(16),
          ),
        ),
        child: AnimatedBuilder(
          animation: _beat,
          builder: (_, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.5),
                  child: Transform.translate(
                    // each dot lifts for a third of the beat, one after the other
                    offset: Offset(0, -4 * _lift((_beat.value - i * 0.18) % 1)),
                    child: const CircleAvatar(
                      radius: 3.6,
                      backgroundColor: Palette.muted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  static double _lift(double t) =>
      t < 0.36 ? Curves.easeInOut.transform(1 - (t / 0.18 - 1).abs()) : 0;
}

/// The message field and its round send button.
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.hint,
    required this.label,
    this.enabled = true,
    this.canSend = true,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final String hint, label;
  final bool enabled, canSend;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Semantics(
                label: tr(label), // the hint alone is not read as the field's name by every screen reader
                child: TextField(
                  key: const Key('assistant-input'),
                  controller: controller,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    hintText: tr(hint),
                    counterText: '',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    filled: false,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox.square(
            dimension: 48,
            child: IconButton.filled(
              key: const Key('assistant-send'),
              onPressed: canSend ? onSend : null,
              style: IconButton.styleFrom(backgroundColor: Palette.teal),
              icon: const Icon(Icons.send_rounded, size: 21),
              tooltip: tr('Send'),
            ),
          ),
        ],
      ),
    ),
  );
}
