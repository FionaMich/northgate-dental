"""The `nora_voice` call type on Stream (ADR 0015): voice only, nothing recorded, nothing transcribed by Stream.
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
    video=VideoSettingsRequest(enabled=False, camera_default_on=False,
                               target_resolution=TargetResolution(width=240, height=240, bitrate=100_000)),
    screensharing=ScreensharingSettingsRequest(enabled=False),
    audio=AudioSettingsRequest(default_device="speaker", mic_default_on=True, speaker_default_on=True),
)
# Patients (role "user") may start and join a call and send audio; nothing more.
GRANTS = {"user": ["create-call", "join-call", "read-call", "send-audio", "end-call"],
          "admin": ["create-call", "join-call", "read-call", "send-audio", "end-call", "update-call", "mute-users"]}


def main() -> int:
    client = Stream(api_key=os.environ["STREAM_API_KEY"], api_secret=os.environ["STREAM_API_SECRET"])
    try:
        client.video.get_call_type(NAME)
        client.video.update_call_type(NAME, settings=SETTINGS, grants=GRANTS)
        action = "updated"
    except Exception as e:  # Stream answers 400 "call type ... does not exist" for an unknown type
        if "does not exist" not in str(e):
            raise
        client.video.create_call_type(name=NAME, settings=SETTINGS, grants=GRANTS)
        action = "created"
    got = client.video.get_call_type(NAME).data
    s = got.settings
    checks = {"recording off": s.recording.mode == "disabled", "transcription off": s.transcription.mode == "disabled",
              "video off": s.video.enabled is False, "screenshare off": s.screensharing.enabled is False}
    print(f"{NAME} {action}: " + ", ".join(f"{k}={'yes' if v else 'NO'}" for k, v in checks.items()))
    return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
