"""The Stream call types (ADR 0015): `nora_voice` (voice only) and `consult` (a video visit with the team). Neither
records nor transcribes anything at Stream.
Run `uv run nora-call-type` once per Stream app and again before each release; it creates or updates the type and
prints the settings that matter. Geofence is left off while the test phone is outside the US."""

import os
import sys

from getstream import Stream
from getstream.models import (AudioSettingsRequest, CallSettingsRequest, RecordSettingsRequest,
                              ScreensharingSettingsRequest, TargetResolution, TranscriptionSettingsRequest,
                              VideoSettingsRequest)

NAME = "nora_voice"
SETTINGS = CallSettingsRequest(
    recording=RecordSettingsRequest(mode="disabled"),
    transcription=TranscriptionSettingsRequest(mode="disabled", closed_caption_mode="disabled"),
    # Video is off; Stream still insists on a resolution of at least 240 pixels, so the smallest it accepts.
    video=VideoSettingsRequest(enabled=False, camera_default_on=False, camera_facing="front",  # the app SDK rejects an empty facing
                               target_resolution=TargetResolution(width=240, height=240, bitrate=100_000)),
    screensharing=ScreensharingSettingsRequest(enabled=False),
    audio=AudioSettingsRequest(default_device="speaker", mic_default_on=True, speaker_default_on=True),
)
# A video consultation: camera and microphone, still nothing recorded or transcribed.
CONSULT = CallSettingsRequest(
    recording=RecordSettingsRequest(mode="disabled"),
    transcription=TranscriptionSettingsRequest(mode="disabled", closed_caption_mode="disabled"),
    video=VideoSettingsRequest(enabled=True, camera_default_on=True, camera_facing="front",
                               target_resolution=TargetResolution(width=1280, height=720, bitrate=1_500_000)),
    screensharing=ScreensharingSettingsRequest(enabled=False),
    audio=AudioSettingsRequest(default_device="speaker", mic_default_on=True, speaker_default_on=True),
)
CONSULT_GRANTS = {"user": ["create-call", "join-call", "read-call", "send-audio", "send-video", "end-call"],
                  "admin": ["create-call", "join-call", "read-call", "send-audio", "send-video", "end-call",
                            "update-call", "mute-users"]}

# Patients (role "user") may start and join a call and send audio; nothing more.
GRANTS = {"user": ["create-call", "join-call", "read-call", "send-audio", "end-call"],
          "admin": ["create-call", "join-call", "read-call", "send-audio", "end-call", "update-call", "mute-users"]}


def ensure(client, name, settings, grants) -> str:
    try:
        client.video.get_call_type(name)
        client.video.update_call_type(name, settings=settings, grants=grants)
        return "updated"
    except Exception as e:  # Stream answers 400 "call type ... does not exist" for an unknown type
        if "does not exist" not in str(e):
            raise
        client.video.create_call_type(name=name, settings=settings, grants=grants)
        return "created"


def main() -> int:
    client = Stream(api_key=os.environ["STREAM_API_KEY"], api_secret=os.environ["STREAM_API_SECRET"])
    ok = True
    for name, settings, grants, video in [(NAME, SETTINGS, GRANTS, False), ("consult", CONSULT, CONSULT_GRANTS, True)]:
        action = ensure(client, name, settings, grants)
        s = client.video.get_call_type(name).data.settings
        checks = {"recording off": s.recording.mode == "disabled", "transcription off": s.transcription.mode == "disabled",
                  f"video {'on' if video else 'off'}": s.video.enabled is video, "screenshare off": s.screensharing.enabled is False}
        print(f"{name} {action}: " + ", ".join(f"{k}={'yes' if v else 'NO'}" for k, v in checks.items()))
        ok = ok and all(checks.values())
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
