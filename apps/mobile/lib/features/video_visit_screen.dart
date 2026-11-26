import 'package:dental/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stream_video_flutter/stream_video_flutter.dart' as sv;

import '../data/consult_repository.dart';
import '../design/tokens.dart';
import '../state.dart';

/// Opens the patient's video consultation room, or says plainly that it is not available.
Future<void> openVideoVisit(BuildContext context, WidgetRef ref) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final ticket = await ref.read(consultRepositoryProvider).ticket();
    await navigator.push(
      MaterialPageRoute(builder: (_) => VideoVisitScreen(ticket: ticket)),
    );
  } on ConsultUnavailable {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Video consultations are unavailable right now. Please call your clinic.',
        ),
      ),
    );
  }
}

/// A video visit with the team: Stream's call layout (both cameras, mute, camera, flip, hang up) in our colours.
/// Stream learns the opaque user ID and the fixed name "Patient", as for voice calls.
class VideoVisitScreen extends StatefulWidget {
  const VideoVisitScreen({super.key, required this.ticket});
  final Map<String, dynamic> ticket;

  @override
  State<VideoVisitScreen> createState() => _VideoVisitScreenState();
}

class _VideoVisitScreenState extends State<VideoVisitScreen> {
  sv.StreamVideo? _client;
  sv.Call? _call;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    final t = widget.ticket;
    final client = _client = sv.StreamVideo(
      t['api_key'] as String,
      user: sv.User.regular(userId: t['user_id'] as String, name: 'Patient'),
      userToken: t['token'] as String,
      failIfSingletonExists: false,
    );
    final call = client.makeCall(
      callType: sv.StreamCallType.custom(t['call_type'] as String),
      id: t['call_id'] as String,
    );
    final ok =
        (await client.connect()).isSuccess &&
        (await call.getOrCreate()).isSuccess;
    if (!mounted) return;
    setState(() => ok ? _call = call : _failed = true);
  }

  @override
  void dispose() {
    final call = _call, client = _client;
    () async {
      try {
        await call?.leave();
        await client?.disconnect();
      } on Exception {
        // Best effort: the token dies within the hour anyway.
      }
    }();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final call = _call;
    return Scaffold(
      backgroundColor: Palette.deepSea,
      appBar: AppBar(
        backgroundColor: Palette.deepSea,
        foregroundColor: Colors.white,
        title: const Text('Video consultation'),
      ),
      body: call != null
          ? sv.StreamCallContainer(
              key: const Key('video-visit'),
              call: call,
              callConnectOptions: sv.CallConnectOptions(
                camera: sv.TrackOption.enabled(),
                microphone: sv.TrackOption.enabled(),
              ),
              onLeaveCallTap: () => Navigator.of(context).maybePop(),
              onCallDisconnected: (_) => Navigator.of(context).maybePop(),
            )
          : Center(
              child: _failed
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'The video consultation could not start. Please try again or call your clinic.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, height: 1.4),
                      ),
                    )
                  : const CircularProgressIndicator(color: Palette.shine),
            ),
    );
  }
}
