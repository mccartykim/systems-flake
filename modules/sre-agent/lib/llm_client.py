"""SRE Agent LLM client — hybrid local Ollama + Ollama Cloud fallback.

Both paths request JSON output via prompt instructions instead of ollama's
format:schema parameter, which causes 5-20x slowdown on gemma4 models.
Cache: responses cached in STATE_DIR/llm-cache.jsonl keyed by alert fingerprint.
"""
import hashlib
import json
import os
import re
import sys
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional


def _extract_json(text: str) -> Optional[dict]:
    """Extract JSON from model response, handling markdown code blocks.

    Tries in order: raw parse, markdown code block, balanced-brace extraction.
    """
    # 1. Try parsing the whole response as JSON
    try:
        return json.loads(text)
    except (json.JSONDecodeError, ValueError):
        pass

    # 2. Try extracting from a markdown code block
    m = re.search(r'```(?:json)?\s*(.*?)\s*```', text, re.DOTALL)
    if m:
        try:
            return json.loads(m.group(1))
        except (json.JSONDecodeError, ValueError):
            pass

    # 3. Balanced-brace extraction: find the first { and match to its closing }
    depth = 0
    start = text.find('{')
    if start == -1:
        return None
    for i in range(start, len(text)):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                try:
                    return json.loads(text[start:i + 1])
                except (json.JSONDecodeError, ValueError):
                    break
    return None


@dataclass
class TriageResult:
    severity: str
    cause: str
    action: str
    file_issue: bool = False
    issue_title: str = ""
    silence_hours: int = 0  # 0 = don't silence, >0 = silence for N hours

    @classmethod
    def from_dict(cls, d: dict) -> "TriageResult":
        # Normalize keys to lowercase (LLM may return SEVERITY or severity)
        d = {k.lower(): v for k, v in d.items()}
        # Map SILENCE key to silence_hours
        if "silence" in d and "silence_hours" not in d:
            d["silence_hours"] = d["silence"]
        # Normalize file_issue: may be bool or string ("yes"/"no"/"true"/"1")
        fi = d.get("file_issue", False)
        if isinstance(fi, bool):
            file_issue = fi
        else:
            file_issue = str(fi).lower() in ("yes", "true", "1")
        return cls(
            severity=d.get("severity", "unknown"),
            cause=d.get("cause", ""),
            action=d.get("action", ""),
            file_issue=file_issue,
            issue_title=d.get("issue_title", ""),
            silence_hours=int(d.get("silence_hours", 0)),
        )


# --- Configuration ---

LOCAL_OLLAMA_HOST = os.environ.get(
    "OLLAMA_HOST", "http://total-eclipse.nebula:11434"
)
LOCAL_OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "qwen3:8b")
CLOUD_OLLAMA_HOST = os.environ.get(
    "OLLAMA_CLOUD_HOST", "http://historian.nebula:11434"
)
CLOUD_OLLAMA_MODEL = os.environ.get("OLLAMA_CLOUD_MODEL", "gemma4:12b")
CLOUD_OLLAMA_KEY_FILE = os.environ.get("OLLAMA_CLOUD_KEY_FILE", "")

LOCAL_TIMEOUT = 180
CLOUD_TIMEOUT = 300
MAX_RETRIES = 1
CACHE_TTL_SECONDS = 3600  # 1 hour

TRIAGE_SYSTEM_PROMPT = """You are an SRE triage assistant. Analyze this alert.

Respond with a JSON object with these fields:
- severity: one of ["critical", "warning", "info", "noise"]
- cause: one-line root cause guess
- action: one-line recommended action
- file_issue: true or false
- issue_title: suggested GitHub issue title (empty string if not filing)
- silence_hours: integer, hours to silence (0=never, 2=info alerts, 4=noise alerts, 24=persistent noise)"""

# JSON Schema included in system prompt for prompt-based JSON output.
# Previously used with ollama's format:schema parameter, which caused
# 5-20x slowdown on gemma4 models due to grammar-constrained decoding.
TRIAGE_SCHEMA = {
    "type": "object",
    "properties": {
        "severity": {"type": "string", "enum": ["critical", "warning", "info", "noise"]},
        "cause": {"type": "string"},
        "action": {"type": "string"},
        "file_issue": {"type": "boolean"},
        "issue_title": {"type": "string"},
        "silence_hours": {"type": "integer"},
    },
    "required": ["severity", "cause", "action", "file_issue", "issue_title", "silence_hours"],
}


# --- Free-form response parser ---

def parse_freeform_response(text: str) -> Optional[TriageResult]:
    """Parse free-form LLM response for SEVERITY/CAUSE/ACTION/FILE_ISSUE/ISSUE_TITLE/SILENCE lines."""
    if not text.strip():
        return None

    lines = text.strip().split("\n")
    data = {}
    for line in lines:
        line = line.strip()
        # Case-insensitive match for key: value
        match = re.match(r"(SEVERITY|CAUSE|ACTION|FILE_ISSUE|ISSUE_TITLE|SILENCE)\s*:\s*(.+)", line, re.IGNORECASE)
        if match:
            key = match.group(1).upper()
            value = match.group(2).strip()
            data[key] = value

    if "SEVERITY" not in data:
        return None

    try:
        silence_hours = int(data.get("SILENCE", "0"))
    except ValueError:
        silence_hours = 0

    return TriageResult(
        severity=data.get("SEVERITY", "unknown"),
        cause=data.get("CAUSE", ""),
        action=data.get("ACTION", ""),
        file_issue=data.get("FILE_ISSUE", "no").lower() in ("yes", "true", "1"),
        issue_title=data.get("ISSUE_TITLE", ""),
        silence_hours=silence_hours,
    )


# --- Cache ---

def _cache_key(alertname: str, instance: str, summary: str) -> str:
    """Generate a cache key from alert fingerprint."""
    raw = f"{alertname}|{instance}|{summary}"
    return hashlib.sha256(raw.encode()).hexdigest()[:16]


def _read_cache(state_dir: str, key: str) -> Optional[TriageResult]:
    """Read a cached result if it exists and is fresh (< CACHE_TTL_SECONDS old)."""
    cache_path = os.path.join(state_dir, "llm-cache.jsonl")
    if not os.path.exists(cache_path):
        return None
    try:
        with open(cache_path) as f:
            for line in f:
                entry = json.loads(line.strip())
                if entry.get("key") == key:
                    age = (datetime.now(timezone.utc) - datetime.fromisoformat(entry["ts"])).total_seconds()
                    if age < CACHE_TTL_SECONDS:
                        return TriageResult.from_dict(entry["result"])
        return None
    except (json.JSONDecodeError, KeyError, OSError):
        return None


def _write_cache(state_dir: str, key: str, result: TriageResult):
    """Append a cache entry."""
    cache_path = os.path.join(state_dir, "llm-cache.jsonl")
    try:
        entry = {
            "key": key,
            "ts": datetime.now(timezone.utc).isoformat(),
            "result": {
                "severity": result.severity,
                "cause": result.cause,
                "action": result.action,
                "file_issue": result.file_issue,
                "issue_title": result.issue_title,
                "silence_hours": result.silence_hours,
            },
        }
        with open(cache_path, "a") as f:
            f.write(json.dumps(entry) + "\n")
    except OSError:
        pass


# --- LLM calls ---

def _get_local_host():
    return os.environ.get("OLLAMA_HOST", LOCAL_OLLAMA_HOST)

def _get_local_model():
    return os.environ.get("OLLAMA_MODEL", LOCAL_OLLAMA_MODEL)

def _get_cloud_host():
    return os.environ.get("OLLAMA_CLOUD_HOST", CLOUD_OLLAMA_HOST)

def _get_cloud_model():
    return os.environ.get("OLLAMA_CLOUD_MODEL", CLOUD_OLLAMA_MODEL)


def _call_local_ollama(prompt: str) -> Optional[TriageResult]:
    """Call local Ollama and extract JSON from response.

    Uses prompt-based JSON instead of format:schema (5-20x faster on gemma4).
    """
    url = f"{_get_local_host()}/api/chat"
    schema_desc = "\n\nRespond with a JSON object matching this schema:\n" + json.dumps(TRIAGE_SCHEMA, indent=2)
    payload = json.dumps({
        "model": _get_local_model(),
        "messages": [
            {"role": "system", "content": TRIAGE_SYSTEM_PROMPT + schema_desc},
            {"role": "user", "content": prompt},
        ],
        "stream": False,
        "think": False,
        "options": {"temperature": 0.1},
    }).encode()

    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json", "User-Agent": "sre-agent/1.0"})

    for attempt in range(MAX_RETRIES):
        try:
            resp = urllib.request.urlopen(req, timeout=LOCAL_TIMEOUT)
            body = json.loads(resp.read().decode())
            content = body.get("message", {}).get("content", "")
            parsed = _extract_json(content)
            result = TriageResult.from_dict(parsed)
            print(f"llm: triage result for {prompt.splitlines()[0]}: severity={result.severity}", file=sys.stderr)
            return result
        except (json.JSONDecodeError, KeyError, TypeError) as e:
            # JSON parse failed — try free-form parsing as fallback
            print(f"llm: local parse error (attempt {attempt+1}): {e}", file=sys.stderr)
            result = parse_freeform_response(content)
            if result:
                return result
        except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as e:
            print(f"llm: local connection error (attempt {attempt+1}): {e}", file=sys.stderr)
            continue
    return None


def _call_cloud_ollama(prompt: str) -> Optional[TriageResult]:
    """Call fallback Ollama (historian) with prompt-based JSON output.

    Uses prompt-based JSON instead of format:schema (5-20x faster on gemma4).
    """
    key_file = os.environ.get("OLLAMA_CLOUD_KEY_FILE", CLOUD_OLLAMA_KEY_FILE)
    url = f"{_get_cloud_host()}/api/chat"
    headers = {"Content-Type": "application/json", "User-Agent": "sre-agent/1.0"}
    if key_file and os.path.exists(key_file):
        try:
            with open(key_file) as f:
                key = f.read().strip()
            if key and not key.startswith("PLACEHOLDER"):
                headers["Authorization"] = f"Bearer {key}"
        except OSError:
            pass

    schema_desc = "\n\nRespond with a JSON object matching this schema:\n" + json.dumps(TRIAGE_SCHEMA, indent=2)
    payload = json.dumps({
        "model": _get_cloud_model(),
        "messages": [
            {"role": "system", "content": TRIAGE_SYSTEM_PROMPT + schema_desc},
            {"role": "user", "content": prompt},
        ],
        "stream": False,
        "think": False,
        "options": {"temperature": 0.1},
    }).encode()

    for attempt in range(MAX_RETRIES):
        content = ""
        try:
            req = urllib.request.Request(url, data=payload, headers=headers)
            resp = urllib.request.urlopen(req, timeout=CLOUD_TIMEOUT)
            body = json.loads(resp.read().decode())
            content = body.get("message", {}).get("content", "")
            parsed = _extract_json(content)
            if parsed is None:
                raise json.JSONDecodeError("no JSON found", content, 0)
            result = TriageResult.from_dict(parsed)
            return result
        except (json.JSONDecodeError, KeyError, TypeError) as e:
            print(f"llm: cloud parse error (attempt {attempt+1}): {e}", file=sys.stderr)
            result = parse_freeform_response(content)
            if result:
                return result
        except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as e:
            print(f"llm: cloud connection error (attempt {attempt+1}): {e}", file=sys.stderr)
            continue
    return None


# --- Main triage function ---

def triage(
    alertname: str,
    severity: str,
    instance: str,
    summary: str,
    journal_tail: str = "",
) -> Optional[TriageResult]:
    """Run LLM triage on an alert. Returns None if all LLM calls fail (Phase 0 fallback)."""
    state_dir = os.environ.get("STATE_DIR", "/var/lib/sre-agent")
    key = _cache_key(alertname, instance, summary)

    # Check cache first
    cached = _read_cache(state_dir, key)
    if cached:
        return cached

    # Build prompt
    prompt = f"""Alert: {alertname}
Severity: {severity}
Instance: {instance}
Summary: {summary}"""
    if journal_tail:
        prompt += f"\nRecent journal (last 20 lines):\n{journal_tail}"

    # Try local Ollama first, then cloud
    result = _call_local_ollama(prompt)
    if result is None:
        print(f"llm: local failed, trying cloud fallback for {alertname}", file=sys.stderr)
        result = _call_cloud_ollama(prompt)
    else:
        print(f"llm: local triage succeeded for {alertname}: {result.severity}", file=sys.stderr)

    if result:
        _write_cache(state_dir, key, result)
    return result