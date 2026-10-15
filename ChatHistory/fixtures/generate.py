#!/usr/bin/env python3
"""Generate public transcripts from authored text and aggregate workload statistics."""

import gzip
import hashlib
import json
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent
STAMP = 1767225600000

SNIPPETS = {
    "typescript": 'type Bin = { label: string; count: number };\nconst total = (bins: Bin[]) => bins.reduce((sum, bin) => sum + bin.count, 0);',
    "javascript": 'const squares = Array.from({ length: 6 }, (_, value) => value ** 2);\nconsole.log(squares.join(", "));',
    "python": 'def moving_average(values, width=3):\n    return [sum(values[i:i + width]) / width for i in range(len(values) - width + 1)]',
    "rust": 'fn sum(values: &[u32]) -> u32 {\n    values.iter().copied().sum()\n}',
    "go": 'func Clamp(value, low, high int) int {\n    if value < low { return low }; if value > high { return high }; return value\n}',
    "swift": 'struct Reading { let value: Double }\nlet mean = readings.map(\\.value).reduce(0, +) / Double(readings.count)',
    "kotlin": 'data class Tile(val row: Int, val column: Int)\nval diagonal = (0..5).map { Tile(it, it) }',
    "dart": 'class Sample {\n  final double value;\n  const Sample(this.value);\n}\nfinal values = <Sample>[const Sample(2.5)];',
    "c": '#include <stddef.h>\nint sum(const int *items, size_t count) {\n    int value = 0; for (size_t i = 0; i < count; ++i) value += items[i]; return value;\n}',
    "cpp": '#include <vector>\n#include <numeric>\nint total(const std::vector<int>& values) { return std::accumulate(values.begin(), values.end(), 0); }',
    "csharp": 'record Reading(double Value);\nvar total = new[] { new Reading(2), new Reading(3) }.Sum(item => item.Value);',
    "java": 'record Point(int x, int y) {}\nvar origin = new Point(0, 0);',
    "ruby": 'def histogram(values)\n  values.each_with_object(Hash.new(0)) { |value, counts| counts[value] += 1 }\nend',
    "sql": 'SELECT category, COUNT(*) AS samples, AVG(value) AS mean\nFROM readings GROUP BY category ORDER BY category;',
    "bash": 'for part in data/segment-*.json; do\n  printf "checking %s\\n" "$part"\ndone',
    "json": '{"dataset":"synthetic","readings":[0,1.25,-3,null],"ready":true,"options":{"mode":"bounded"}}',
    "yaml": 'dataset: synthetic\nsteps:\n  - read\n  - validate\n  - summarize\nlimits:\n  rows: 2048',
    "html": '<section aria-label="Readings"><h2>Daily sample</h2><output>12.5</output></section>',
    "css": '.readings { display: grid; grid-template-columns: repeat(3, 1fr); gap: 1rem; }',
    "diff": 'diff --git a/src/bins.ts b/src/bins.ts\n--- a/src/bins.ts\n+++ b/src/bins.ts\n@@ -1 +1,2 @@\n-export const limit = 4;\n+export const limit = 8;\n+export const stable = true;',
    "toml": '[dataset]\nname = "synthetic"\nrows = 2048\n[output]\nformat = "table"',
}

PROSE = (
    "The fictional sensor garden has three independent lanes. Each reading is generated "
    "from a fixed sequence, checked against the same bounds, and summarized in stable order. "
    "A missing value stays missing; it is never silently replaced by a zero. "
    "A boundary sample exercises the first and last bucket without changing its neighbors. "
    "The next review compares a narrow window, a full window, and an empty window. "
    "Keep the original order when values tie, and report the number of discarded samples. "
)


def markdown(index):
    language = list(SNIPPETS)[index % len(SNIPPETS)]
    return (
        f"# Synthetic field notebook {index + 1}\n\n"
        "## Plan and observations\n\n" + PROSE + "\n\n"
        "- [x] Generate a bounded input\n- [x] Preserve empty values\n- [ ] Compare the final table\n"
        "\n1. Read the sequence.\n2. Group by lane.\n3. Check the totals.\n\n"
        "| Lane | Samples | Mean |\n| :--- | ---: | ---: |\n| north | 12 | 4.25 |\n| south | 0 | — |\n\n"
        "> A generated observation is an example, not a field measurement.\n\n"
        f"```{language}\n{SNIPPETS[language]}\n```\n\n"
        "### Edge cases\n\n**Empty**, *single*, `inline_value`, ~~discarded~~, and escaped \\*text\\*.\n\n"
        "<details><summary>Review notes</summary>\n\nKeep the final ordering stable.\n\n</details>\n"
    )


def fill(text, size):
    """ASCII padding models payload volume without retaining any source content."""
    if size <= len(text):
        return text[:size]
    return text + (PROSE * ((size - len(text)) // len(PROSE) + 1))[:size - len(text)]


def record(kind, index, text, call_number=None):
    timestamp = datetime(2026, 1, 1) + timedelta(seconds=index)
    root = {"timestamp": timestamp.isoformat(timespec="milliseconds") + "Z"}
    call_number = (index - 1 if kind.endswith("_output") else index) if call_number is None else call_number
    call_id = f"{'custom' if kind.startswith('custom') else 'function'}-{call_number}"
    if kind == "metadata":
        root.update(type="session_meta", payload={"id": "synthetic-session", "cwd": "workspace"})
    elif kind in ("user", "assistant", "developer"):
        root.update(type="response_item", payload={"type": "message", "role": kind,
                    "content": [{"type": "input_text" if kind == "user" else "output_text", "text": text}]})
    elif kind == "reasoning":
        root.update(type="response_item", payload={"type": "reasoning", "summary": [{"type": "summary_text", "text": text}]})
    elif kind in ("custom_tool_call", "function_call"):
        root.update(type="response_item", payload={"type": kind, "name": "exec_command", "call_id": call_id,
                    "input" if kind == "custom_tool_call" else "arguments": text})
    elif kind in ("custom_tool_call_output", "function_call_output"):
        root.update(type="response_item", payload={"type": kind, "call_id": call_id, "output": text})
    elif kind == "compacted":
        root.update(type="compacted", payload={"replacement_history": [{"type": "message", "role": "assistant",
                    "content": [{"type": "output_text", "text": text}]}]})
    else:
        root.update(type="event_msg", payload={"type": kind if kind != "other" else "task_started", "text": text})
    return root


def encode(value):
    return (json.dumps(value, ensure_ascii=True, separators=(",", ":")) + "\n").encode()


def large(name, counts, target, budgets, tails):
    # Fractional scheduling interleaves the exact quotas without nondeterministic randomness.
    schedule = sorted((position / count, order, kind, position)
                      for order, (kind, count) in enumerate(counts.items())
                      for position in range(count))
    schedule.remove((0, 0, "metadata", 0))
    schedule.insert(0, (0, 0, "metadata", 0))
    used = {kind: 0 for kind in counts}
    total = 0
    digest = hashlib.sha256()
    lengths = []
    output = ROOT / f"{name}.jsonl.gz"
    with output.open("wb") as raw, gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0, compresslevel=9) as stream:
        for index, (_, _, kind, position) in enumerate(schedule):
            count = counts[kind]
            base = record(kind, index, "", position)
            overhead = len(encode(base))
            if kind == "metadata":
                value = base
            else:
                budget = budgets.get(kind, count * 840)
                # Most rows stay near 840 bytes; sparse tails carry the expensive payloads.
                heavy_count = tails.get(kind, count)
                heavy_start = count - heavy_count
                if position < heavy_start:
                    size = 840
                else:
                    remaining = count - position
                    size = (budget - used[kind]) // remaining
                if kind == "custom_tool_call_output" and position == heavy_start and name.endswith("first"):
                    size = 8_000_000
                if index == len(schedule) - 1:
                    size = target - total
                size = max(overhead + 1, size)
                if kind in ("assistant", "user"):
                    content = markdown(position).replace("—", "-") if position % 11 else "OK."
                elif "call_output" in kind:
                    content = f"$ inspect data/segment-{position % 17:02}.json\nexit code: 0\nrows: 2048\nchecks: passed\n" + PROSE
                elif kind.endswith("call"):
                    content = '{"cmd":"inspect data/readings.json","mode":"read"}'
                else:
                    content = PROSE
                # Text is ASCII, but Markdown escapes enlarge JSON. Correct against encoded size.
                content = fill(content, size - overhead)
                if kind == "assistant":
                    # Keep native byte prefixes and JS character prefixes identical.
                    for limit in (4096, 8192):
                        if len(content) >= limit and content[limit - 1].isspace():
                            content = content[:limit - 1] + "." + content[limit:]
                value = record(kind, index, content, position)
                excess = len(encode(value)) - size
                if excess > 0:
                    value = record(kind, index, content[:-excess], position)
            data = encode(value)
            stream.write(data)
            digest.update(data)
            total += len(data)
            used[kind] += len(data)
            lengths.append(len(data))
    assert total == target, (name, total, target)
    print(json.dumps({"file": output.name, "sourceBytes": total, "records": len(lengths), "storedBytes": output.stat().st_size,
                      "lineP50": sorted(lengths)[len(lengths) // 2], "lineP90": sorted(lengths)[len(lengths) * 9 // 10],
                      "lineP99": sorted(lengths)[len(lengths) * 99 // 100], "maxLine": max(lengths)}))
    return entry(name, "codex", output.name, total, digest.hexdigest())


def entry(name, provider, path, size, digest):
    return {"id": f"{provider}:{name}", "provider": provider, "title": name.replace("-", " ").title(),
            "path": path, "sourceBytes": size, "sha256": digest,
            "lastActivityAt": STAMP, "modifiedAt": STAMP, "updatedAt": STAMP}


def small(name, provider, turns, long_size=0):
    records = []
    if provider == "codex":
        records.append(record("metadata", 0, ""))
        for turn in range(turns):
            index = len(records)
            user = record("user", index, "Compare the generated lanes." if turn else "Hi.")
            if turn == 1:
                user["payload"]["content"].append({"type": "input_image", "image_url": "data:image/png;base64,omitted"})
            records.append(user)
            records.append(record("function_call", index + 1, '{"cmd":"inspect data/readings.json"}'))
            records.append(record("function_call_output", index + 2, "lane=north count=12 status=passed\nlane=south count=0 status=empty\n"))
            records.append({"timestamp": "2026-01-01T00:00:04.000Z", "type": "event_msg", "payload": {
                "type": "patch_apply_end", "turn_id": f"turn-{turn}", "success": True, "changes": {
                    "src/bins.ts": {"type": "update", "unified_diff": "@@ -1 +1,2 @@\n-old\n+new\n+stable\n"}}}})
            text = markdown(turn)
            if long_size and turn == turns // 2:
                text = fill(text, long_size)
            records.append(record("assistant", index + 4, text))
    else:
        parent = None
        def append(kind, content, suffix="", side=False, previous=None):
            nonlocal parent
            uid = f"synthetic-{name}-{len(records)}{suffix}"
            records.append({"timestamp": f"2026-01-01T00:{len(records) // 60:02}:{len(records) % 60:02}.000Z",
                            "type": kind, "uuid": uid, "parentUuid": previous or parent, "isSidechain": side,
                            "message": {"role": kind, "content": content}})
            if not side:
                parent = uid
        for turn in range(turns):
            append("user", [{"type": "text", "text": "Hi." if turn == 0 else "Compare the next generated segment."}])
            start = parent
            append("assistant", [{"type": "text", "text": "An alternate ordering was considered."}], "-branch")
            parent = start
            call = f"read-{turn}"
            append("assistant", [{"type": "thinking", "thinking": "Check the synthetic boundary values."},
                                 {"type": "tool_use", "id": call, "name": "Read", "input": {"file_path": "data/readings.json"}}])
            append("user", [{"type": "tool_result", "tool_use_id": call,
                             "content": [{"type": "text", "text": "{\"values\":[1,2,null],\"ready\":true}"},
                                         {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": "omitted"}}],
                             "is_error": turn == 2}])
            text = markdown(turn) + "\nUnicode: Καλημέρα · こんにちは · مرحبا · café · 🪴\n"
            if long_size and turn == turns // 2:
                text = fill(text, long_size)
            append("assistant", [{"type": "text", "text": text}, {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": "omitted"}},
                                 {"type": "document", "source": {"type": "text", "data": "Synthetic table attachment"}}])
            append("assistant", [{"type": "text", "text": "Independent sidechain note."}], "-side", True)
    data = b"".join(encode(value) for value in records)
    path = ROOT / f"{name}.jsonl"
    path.write_bytes(data)
    print(json.dumps({"file": path.name, "sourceBytes": len(data), "records": len(records)}))
    return entry(name, provider, path.name, len(data), hashlib.sha256(data).hexdigest())


def main():
    counts = [
        dict(metadata=1, user=61, assistant=227, developer=14, reasoning=1527, custom_tool_call=1372,
             custom_tool_call_output=1372, function_call=5, function_call_output=5, item_completed=1941,
             token_count=1445, compacted=15, other=241),
        dict(metadata=1, user=74, assistant=294, developer=18, reasoning=1832, custom_tool_call=1637,
             custom_tool_call_output=1637, function_call=189, function_call_output=189, item_completed=2342,
             token_count=1900, compacted=14, other=255),
    ]
    fixtures = [
        large("synthetic-codex-first", counts[0], 239115823,
              dict(custom_tool_call_output=142000000, item_completed=44000000, compacted=40000000,
                   user=800000, assistant=4000000, reasoning=4200000, token_count=1500000),
              dict(custom_tool_call_output=400, item_completed=105, compacted=15, reasoning=509)),
        large("synthetic-codex-switch", counts[1], 148125953,
              dict(custom_tool_call_output=8000000, item_completed=127000000, compacted=1200000,
                   user=120000, assistant=500000, reasoning=5000000, token_count=2000000),
              dict(custom_tool_call_output=204, item_completed=334, compacted=14, reasoning=610)),
        small("synthetic-codex-brief", "codex", 2),
        small("synthetic-codex-language-tour", "codex", len(SNIPPETS), 320000),
        small("synthetic-claude-brief", "claude", 1),
        small("synthetic-claude-branches", "claude", 5),
        small("synthetic-claude-language-tour", "claude", len(SNIPPETS), 600000),
        small("synthetic-claude-long-notebook", "claude", 40, 2200000),
    ]
    manifest = {"version": 2, "loadImages": False, "switchDelayMs": 3000, "fixtures": fixtures}
    (ROOT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
