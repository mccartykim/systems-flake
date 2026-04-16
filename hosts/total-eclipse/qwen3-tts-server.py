# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "faster-qwen3-tts",
#   "fastapi",
#   "uvicorn[standard]",
#   "soundfile",
#   "torch",
# ]
# ///
"""Qwen3-TTS OpenAI-compatible server (faster-qwen3-tts backend).

Uses CUDA graph capture for realtime inference on consumer GPUs.
Exposes POST /v1/audio/speech with voice cloning from reference audio.
"""

import argparse
import asyncio
import io
import os
import time
from pathlib import Path

import soundfile as sf
import torch
import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel

app = FastAPI(title="Qwen3-TTS")

model = None
MODEL_NAME = os.environ.get("QWEN3_TTS_MODEL", "Qwen/Qwen3-TTS-12Hz-0.6B-Base")
VOICES_DIR = Path(os.environ.get("VOICES_DIR", "/var/lib/voice-references"))

# Idle-exit: full process exit is the only way to release the CUDA context's
# VRAM footprint so ollama can use the GPU. Socket activation in systemd
# re-spawns us on the next incoming request.
IDLE_TIMEOUT = float(os.environ.get("QWEN3_TTS_IDLE_TIMEOUT", "45"))
LAST_REQ = time.monotonic()
_server_ref: dict = {}


@app.middleware("http")
async def track_activity(request, call_next):
    global LAST_REQ
    LAST_REQ = time.monotonic()
    try:
        return await call_next(request)
    finally:
        LAST_REQ = time.monotonic()


async def idle_watchdog(server):
    while not server.should_exit:
        await asyncio.sleep(10)
        if time.monotonic() - LAST_REQ > IDLE_TIMEOUT:
            print(f"Idle {IDLE_TIMEOUT}s — exiting to free VRAM")
            server.should_exit = True
            return


@app.on_event("startup")
async def _start_watchdog():
    server = _server_ref.get("s")
    if server is not None:
        asyncio.create_task(idle_watchdog(server))


class SpeechRequest(BaseModel):
    model: str = "qwen3-tts"
    input: str
    voice: str = "default"
    response_format: str = "wav"
    language: str = "English"


@app.on_event("startup")
def load_model():
    global model
    from faster_qwen3_tts import FasterQwen3TTS

    print(f"CUDA available: {torch.cuda.is_available()}")
    if torch.cuda.is_available():
        print(f"GPU: {torch.cuda.get_device_name(0)}")
        print(f"VRAM: {torch.cuda.get_device_properties(0).total_memory / 1024**3:.1f} GB")

    print(f"Loading model: {MODEL_NAME}")
    model = FasterQwen3TTS.from_pretrained(MODEL_NAME)
    print("Model loaded successfully")


@app.get("/health")
def health():
    return {"status": "ok", "model_loaded": model is not None, "model": MODEL_NAME}


@app.post("/v1/audio/speech")
async def speech(request: SpeechRequest):
    if model is None:
        raise HTTPException(503, "Model not loaded yet")

    # Map "default" voice to soup reference
    voice_name = request.voice if request.voice != "default" else "soup"
    ref_audio = VOICES_DIR / f"{voice_name}.wav"
    ref_text_file = VOICES_DIR / f"{voice_name}.txt"

    if not ref_audio.exists():
        available = [f.stem for f in VOICES_DIR.glob("*.wav")]
        raise HTTPException(
            400,
            f"Voice '{voice_name}' not found. Available: {available}",
        )

    kwargs = dict(
        text=request.input,
        language=request.language,
        ref_audio=str(ref_audio),
    )
    # Use transcript if available (ICL mode, better quality)
    # Otherwise fall back to x-vector only mode
    if ref_text_file.exists():
        kwargs["ref_text"] = ref_text_file.read_text().strip()
    else:
        kwargs["ref_text"] = ""
        kwargs["xvec_only"] = True

    t0 = time.time()
    wavs, sr = model.generate_voice_clone(**kwargs)
    elapsed = time.time() - t0
    duration = len(wavs[0]) / sr
    rtf = duration / elapsed
    print(f"Generated {duration:.1f}s audio in {elapsed:.1f}s (RTF: {rtf:.2f}x)")

    buf = io.BytesIO()
    sf.write(buf, wavs[0], sr, format="WAV")
    buf.seek(0)
    return Response(content=buf.getvalue(), media_type="audio/wav")


if __name__ == "__main__":
    # Socket-activated by systemd: LISTEN_FDS=N, listening socket at fd 3.
    # Standalone: fall back to host/port binding.
    listen_fds = int(os.environ.get("LISTEN_FDS", "0"))
    if listen_fds >= 1:
        config = uvicorn.Config(app, fd=3, log_level="info")
    else:
        parser = argparse.ArgumentParser()
        parser.add_argument("--host", default="0.0.0.0")
        parser.add_argument("--port", type=int, default=8091)
        args = parser.parse_args()
        config = uvicorn.Config(app, host=args.host, port=args.port)
    server = uvicorn.Server(config)
    _server_ref["s"] = server
    server.run()
