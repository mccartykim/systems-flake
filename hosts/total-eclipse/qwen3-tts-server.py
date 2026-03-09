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
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8091)
    args = parser.parse_args()
    uvicorn.run(app, host=args.host, port=args.port)
