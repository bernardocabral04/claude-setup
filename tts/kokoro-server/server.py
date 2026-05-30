"""
Minimal FastAPI server wrapping Kokoro-82M for local TTS.

Usage:
    pip install -r requirements.txt
    python server.py

Endpoints:
    GET  /voices     — list available Kokoro voices
    POST /synthesize — synthesize text to audio with word-level timestamps
"""

import base64
import io
from contextlib import asynccontextmanager

import numpy as np
import soundfile as sf
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# ---------------------------------------------------------------------------
# Globals populated at startup
# ---------------------------------------------------------------------------
pipelines: dict = {}  # lang_code → KPipeline
SAMPLE_RATE = 24000

# Voice ID prefix → lang_code for KPipeline
VOICE_LANG_MAP = {
    "a": "a",   # American English (af_, am_)
    "b": "b",   # British English (bf_, bm_)
    "p": "p",   # Brazilian Portuguese (pf_, pm_)
}

VOICES = [
    {"id": "af_heart", "label": "Heart (US, Female)", "lang": "a"},
    {"id": "af_bella", "label": "Bella (US, Female)", "lang": "a"},
    {"id": "af_nicole", "label": "Nicole (US, Female)", "lang": "a"},
    {"id": "af_sarah", "label": "Sarah (US, Female)", "lang": "a"},
    {"id": "af_sky", "label": "Sky (US, Female)", "lang": "a"},
    {"id": "am_adam", "label": "Adam (US, Male)", "lang": "a"},
    {"id": "am_michael", "label": "Michael (US, Male)", "lang": "a"},
    {"id": "bf_emma", "label": "Emma (UK, Female)", "lang": "b"},
    {"id": "bf_isabella", "label": "Isabella (UK, Female)", "lang": "b"},
    {"id": "bm_george", "label": "George (UK, Male)", "lang": "b"},
    {"id": "bm_lewis", "label": "Lewis (UK, Male)", "lang": "b"},
    {"id": "pf_dora", "label": "Dora (BR, Female)", "lang": "p"},
    {"id": "pm_alex", "label": "Alex (BR, Male)", "lang": "p"},
    {"id": "pm_santa", "label": "Santa (BR, Male)", "lang": "p"},
]


# ---------------------------------------------------------------------------
# Startup / shutdown
# ---------------------------------------------------------------------------
def _get_pipeline(lang_code: str):
    """Get or lazily create a KPipeline for the given language."""
    if lang_code not in pipelines:
        from kokoro import KPipeline
        print(f"Loading Kokoro pipeline for lang_code='{lang_code}' …")
        pipelines[lang_code] = KPipeline(lang_code=lang_code)
        print(f"Kokoro pipeline (lang_code='{lang_code}') ready.")
    return pipelines[lang_code]


def _lang_for_voice(voice_id: str) -> str:
    """Derive the lang_code from a voice ID prefix (e.g. 'pf_dora' → 'p')."""
    prefix = voice_id[0] if voice_id else "a"
    return VOICE_LANG_MAP.get(prefix, "a")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Pre-load American English on startup
    _get_pipeline("a")
    yield
    pipelines.clear()


app = FastAPI(title="Kokoro TTS Server", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------
class SynthesizeRequest(BaseModel):
    text: str
    voice: str = "af_heart"
    speed: float = 1.0


class WordTimestamp(BaseModel):
    word: str
    start: float
    end: float


class SynthesizeResponse(BaseModel):
    audio: str  # base64-encoded WAV
    timestamps: list[WordTimestamp]
    sample_rate: int


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _audio_to_base64_wav(audio_np: np.ndarray, sr: int) -> str:
    buf = io.BytesIO()
    sf.write(buf, audio_np, sr, format="WAV")
    return base64.b64encode(buf.getvalue()).decode()


DURATION_DIVISOR = 80.0  # converts pred_dur ticks → seconds


def _extract_word_timestamps(tokens: list | None, graphemes: str, pred_dur, audio_len: int) -> list[WordTimestamp]:
    """
    Extract per-word timestamps. Uses MToken objects when available (English),
    falls back to pred_dur-based estimation for other languages.
    """
    # Try MToken-based timestamps first
    if tokens:
        timestamps: list[WordTimestamp] = []
        for token in tokens:
            text = getattr(token, "text", "")
            start = getattr(token, "start_ts", None)
            end = getattr(token, "end_ts", None)

            if start is None or end is None:
                continue

            # Skip punctuation-only tokens (merge timing into previous word)
            if not any(c.isalnum() for c in text):
                if timestamps:
                    timestamps[-1].end = round(end, 4)
                continue

            timestamps.append(WordTimestamp(word=text, start=round(start, 4), end=round(end, 4)))

        if timestamps:
            return timestamps

    # Fallback: distribute audio duration across words using pred_dur
    words = graphemes.split() if graphemes else []
    if not words:
        return []

    total_duration = audio_len / SAMPLE_RATE

    if pred_dur is not None:
        dur_np = pred_dur.numpy() if hasattr(pred_dur, "numpy") else np.array(pred_dur)
        total_ticks = float(dur_np.sum()) or 1.0

        # Map phonemes to words proportionally by character length
        # (pred_dur is phoneme-level, but we approximate per-word share)
        char_lengths = [len(w) for w in words]
        total_chars = sum(char_lengths) or 1

        timestamps = []
        cursor = 0.0
        for word, clen in zip(words, char_lengths):
            word_dur = (clen / total_chars) * total_duration
            timestamps.append(WordTimestamp(word=word, start=round(cursor, 4), end=round(cursor + word_dur, 4)))
            cursor += word_dur
        return timestamps

    # Last resort: even distribution
    dur_per_word = total_duration / len(words)
    return [
        WordTimestamp(word=w, start=round(i * dur_per_word, 4), end=round((i + 1) * dur_per_word, 4))
        for i, w in enumerate(words)
    ]


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------
@app.get("/voices")
async def list_voices():
    return {"voices": VOICES}


@app.post("/synthesize", response_model=SynthesizeResponse)
async def synthesize(req: SynthesizeRequest):
    lang_code = _lang_for_voice(req.voice)
    pipe = _get_pipeline(lang_code)

    all_audio: list[np.ndarray] = []
    all_timestamps: list[WordTimestamp] = []
    audio_offset = 0.0  # running offset in seconds across chunks

    generator = pipe(req.text, voice=req.voice, speed=req.speed)

    for result in generator:
        audio_np = result.audio.numpy() if hasattr(result.audio, "numpy") else np.array(result.audio)
        chunk_duration = len(audio_np) / SAMPLE_RATE

        # Extract word timestamps (precise from MTokens, or fallback from pred_dur)
        tokens = getattr(result, "tokens", None)
        graphemes = getattr(result, "graphemes", "") or ""
        pred_dur = getattr(result, "pred_dur", None)
        chunk_ts = _extract_word_timestamps(tokens, graphemes, pred_dur, len(audio_np))

        # Shift timestamps by the running audio offset
        for ts in chunk_ts:
            all_timestamps.append(
                WordTimestamp(
                    word=ts.word,
                    start=round(ts.start + audio_offset, 4),
                    end=round(ts.end + audio_offset, 4),
                )
            )

        audio_offset += chunk_duration
        all_audio.append(audio_np)

    if not all_audio:
        return SynthesizeResponse(audio="", timestamps=[], sample_rate=SAMPLE_RATE)

    # Pad with silence to prevent clipping at start/end of playback
    pad_samples = int(SAMPLE_RATE * 0.08)  # 80ms
    silence = np.zeros(pad_samples, dtype=np.float32)
    combined = np.concatenate([silence, *all_audio, silence])

    # Shift timestamps to account for the leading silence
    pad_seconds = pad_samples / SAMPLE_RATE
    for ts in all_timestamps:
        ts.start = round(ts.start + pad_seconds, 4)
        ts.end = round(ts.end + pad_seconds, 4)

    audio_b64 = _audio_to_base64_wav(combined, SAMPLE_RATE)

    return SynthesizeResponse(
        audio=audio_b64,
        timestamps=all_timestamps,
        sample_rate=SAMPLE_RATE,
    )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8321)
