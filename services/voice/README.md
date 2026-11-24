# Nora voice service

Nora on a voice call. Stream carries the audio between the patient's phone and this process; here, fast-whisper turns speech into text, smart-turn decides when the patient has finished, and ElevenLabs speaks Nora's reply. The thinking is not here: every turn goes to the assistant API, the same graph as the chat, which also knows who is on the call. The patient's Confirm button goes to the API with the patient's own session, never through the call.

```bash
uv sync
set -a; . ./.env; set +a         # STREAM_API_KEY, STREAM_API_SECRET, ELEVENLABS_API_KEY, ASSISTANT_URL, ASSISTANT_INTERNAL_KEY
uv run python -m voice.call_type  # creates or checks the nora_voice call type: recording, transcription and video off
uv run nora-voice                 # claims calls the API lists as pending and joins each one as "nora"
uv run pytest -q
```
