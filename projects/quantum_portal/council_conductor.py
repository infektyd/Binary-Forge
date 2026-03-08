#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

API_URL = "https://api.x.ai/v1/responses"
MODEL = "grok-4"
KEY_PATH = Path.home() / ".xai-key"
LOG_DIR = Path("logs")

ROLE_INSTRUCTIONS = {
    "workhorse": (
        "You are Workhorse. Be practical and execution-focused. "
        "Return concrete steps, constraints, and checks."
    ),
    "creative": (
        "You are Creative. Generate novel options and alternatives "
        "that are still realistic to execute."
    ),
    "speed": (
        "You are Speed. Optimize for minimal time-to-value. "
        "Return the fastest viable path with tradeoffs."
    ),
    "conductor": (
        "You are Conductor. Merge role outputs into one final plan. "
        "Resolve conflicts, keep only high-value actions, and provide "
        "a clear final answer."
    ),
}


def load_api_key() -> str:
    env_key = os.environ.get("XAI_API_KEY", "").strip()
    if env_key:
        return env_key
    try:
        return KEY_PATH.read_text(encoding="utf-8").strip()
    except OSError as exc:
        raise RuntimeError(f"Unable to read API key from {KEY_PATH}: {exc}") from exc


def extract_text(payload: dict) -> str:
    output = payload.get("output")
    if isinstance(output, list):
        chunks = []
        for item in output:
            content = item.get("content", []) if isinstance(item, dict) else []
            for block in content:
                if isinstance(block, dict) and block.get("type") == "output_text":
                    text = block.get("text", "")
                    if text:
                        chunks.append(text)
        if chunks:
            return "\n".join(chunks).strip()

    choices = payload.get("choices")
    if isinstance(choices, list) and choices:
        msg = choices[0].get("message", {})
        content = msg.get("content", "") if isinstance(msg, dict) else ""
        if isinstance(content, str) and content.strip():
            return content.strip()

    raise RuntimeError("xAI response did not contain extractable text")


def call_xai(api_key: str, prompt: str, instructions: str, max_tokens: int = 700) -> str:
    body = json.dumps(
        {
            "model": MODEL,
            "input": prompt,
            "instructions": instructions,
            "max_output_tokens": max_tokens,
        }
    ).encode("utf-8")

    req = urllib.request.Request(
        API_URL,
        data=body,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=75) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        err_text = exc.read().decode("utf-8", errors="ignore")
        raise RuntimeError(f"xAI HTTP {exc.code}: {err_text[:300]}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"xAI connection error: {exc}") from exc

    return extract_text(payload)


def route_roles(task: str) -> list[str]:
    t = task.lower()
    creative_hints = ("brainstorm", "idea", "creative", "name", "story", "design")
    speed_hints = ("fast", "quick", "asap", "urgent", "speed", "today")

    if any(h in t for h in creative_hints):
        return ["creative", "workhorse", "speed", "conductor"]
    if any(h in t for h in speed_hints):
        return ["speed", "workhorse", "creative", "conductor"]
    return ["workhorse", "speed", "creative", "conductor"]


def write_transcript(task: str, order: list[str], outputs: dict[str, str]) -> Path:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    ts = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    log_path = LOG_DIR / f"council_{ts}.log"

    lines = [
        f"timestamp: {dt.datetime.now().isoformat()}",
        f"model: {MODEL}",
        f"task: {task}",
        f"order: {' -> '.join(order)}",
        "",
    ]
    for role in ["workhorse", "creative", "speed", "conductor"]:
        lines.append(f"[{role}]")
        lines.append(outputs.get(role, "<no output>"))
        lines.append("")

    log_path.write_text("\n".join(lines), encoding="utf-8")
    return log_path


def run_council(task: str, api_key: str) -> tuple[list[str], dict[str, str], Path]:
    order = route_roles(task)
    outputs: dict[str, str] = {}

    for role in order:
        if role == "conductor":
            conductor_input = (
                f"Task:\n{task}\n\n"
                f"Workhorse:\n{outputs.get('workhorse', '')}\n\n"
                f"Creative:\n{outputs.get('creative', '')}\n\n"
                f"Speed:\n{outputs.get('speed', '')}\n\n"
                "Produce the final integrated answer."
            )
            outputs[role] = call_xai(api_key, conductor_input, ROLE_INSTRUCTIONS[role], 900)
        else:
            role_prompt = f"Task: {task}\n\nRespond as {role} with a concise, useful answer."
            outputs[role] = call_xai(api_key, role_prompt, ROLE_INSTRUCTIONS[role], 500)

    log_path = write_transcript(task, order, outputs)
    return order, outputs, log_path


def run_self_test() -> int:
    print("[test] quantum portal council conductor")
    failures = 0

    try:
        key = load_api_key()
        print("[ok] API key loaded")
    except Exception as exc:
        print(f"[fail] API key load: {exc}")
        return 1

    order = route_roles("quick creative design")
    if order and order[-1] == "conductor" and set(order[:3]) == {"workhorse", "creative", "speed"}:
        print(f"[ok] role routing: {' -> '.join(order)}")
    else:
        failures += 1
        print(f"[fail] role routing produced invalid order: {order}")

    try:
        response = call_xai(
            key,
            "Self-test ping. Reply with TEST_OK only.",
            "Return exactly TEST_OK.",
            32,
        )
        if "TEST_OK" in response:
            print("[ok] live xAI call")
        else:
            failures += 1
            print(f"[fail] live xAI call unexpected output: {response!r}")
    except Exception as exc:
        failures += 1
        print(f"[fail] live xAI call: {exc}")

    if failures == 0:
        print("[pass] self-test complete")
        return 0

    print(f"[fail] self-test failures: {failures}")
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Quantum Portal multi-role xAI conductor")
    parser.add_argument("task", nargs="?", help="Task text to run through the council")
    parser.add_argument("--test", action="store_true", help="Run quick self-test")
    args = parser.parse_args()

    if args.test:
        return run_self_test()

    if not args.task:
        print("Usage: python3 council_conductor.py \"task here\"", file=sys.stderr)
        return 2

    try:
        key = load_api_key()
        order, outputs, log_path = run_council(args.task, key)
    except Exception as exc:
        print(f"[error] {exc}", file=sys.stderr)
        return 1

    print(f"Order: {' -> '.join(order)}")
    print(outputs.get("conductor", ""))
    print(f"Transcript: {log_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
