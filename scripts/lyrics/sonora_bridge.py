#!/usr/bin/env python3
"""Read Sonora's current lyrics, position and word-level karaoke timings.

Sonora's CLI exposes the lyric sheet that is currently displayed but only
gives line starts. The exact word onsets Sonora uses for its karaoke live in
its cache database, so this bridge joins both views into one JSON answer for
the QuickShell lyric widget. It never triggers a new lyric lookup.
"""

import json
import os
import re
import sqlite3
import subprocess
import sys


def run_json(args, timeout=2.0):
    try:
        out = subprocess.check_output(
            args, text=True, timeout=timeout, stderr=subprocess.DEVNULL
        )
        value = json.loads(out)
        return value if isinstance(value, dict) else {}
    except Exception:
        return {}


def secs(value):
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, dict):
        return float(value.get("secs", 0)) + float(value.get("nanos", 0)) / 1_000_000_000.0
    return 0.0


def cache_hits(cache_path, track_id):
    if not track_id or not re.fullmatch(r"[A-Za-z0-9_-]+", track_id):
        return []
    if not cache_path or not os.path.exists(cache_path):
        return []
    try:
        con = sqlite3.connect("file:%s?mode=ro" % cache_path, uri=True, timeout=1.0)
        row = con.execute(
            "SELECT value FROM lyrics WHERE key LIKE ? ORDER BY stored DESC LIMIT 1",
            ("%%%s:lyrics" % track_id,),
        ).fetchone()
        con.close()
        if not row:
            return []
        payload = json.loads(row[0])
        hits = payload.get("hits")
        return hits if isinstance(hits, list) else []
    except Exception:
        return []


def synced_lines(hit):
    lyrics = (hit or {}).get("lyrics")
    if not isinstance(lyrics, dict):
        return []
    synced = lyrics.get("Synced")
    if not isinstance(synced, dict):
        return []
    lines = synced.get("lines")
    return lines if isinstance(lines, list) else []


def pick_hit(hits, source, first_text):
    def score(hit):
        lines = synced_lines(hit)
        word_count = sum(len(line.get("words") or []) for line in lines)
        hit_source = str(hit.get("source") or "").lower()
        wanted = str(source or "").lower()
        first = str((lines[0].get("text") if lines else "") or "").strip()
        # Sonora kadang memilih sumber tanpa word timing; tetap pakai hit
        # dengan onset kata paling lengkap agar sapuan karaoke mengikuti vokal.
        value = min(word_count, 3000) * 10.0
        value += min(float(hit.get("trust") or 0), 500) * 2.0
        if wanted and wanted in hit_source:
            value += 800.0
        if first_text and first == first_text.strip():
            value += 400.0
        return value

    return max(hits, key=score) if hits else None


def word_timings(hit):
    result = []
    for line in synced_lines(hit):
        raw_words = line.get("words")
        if not raw_words:
            continue
        start = secs(line.get("start"))
        end = secs(line.get("end")) if line.get("end") else start
        text = str(line.get("text") or "")
        total = max(1, len(text))
        cursor = 0
        timings = []
        for index, word in enumerate(raw_words):
            rel_start = secs(word.get("start")) - start
            rel_end = secs(word.get("end")) - start
            if rel_end <= rel_start:
                if index + 1 < len(raw_words):
                    rel_end = secs(raw_words[index + 1].get("start")) - start
                else:
                    rel_end = end - start
                if rel_end <= rel_start:
                    rel_end = rel_start + 0.12
            word_text = str(word.get("text") or "")
            ratio_start = min(1.0, max(0.0, cursor / total))
            cursor += len(word_text)
            ratio_end = min(1.0, max(ratio_start, cursor / total))
            timings.append(
                {
                    "relStart": round(max(0.0, rel_start), 4),
                    "relEnd": round(max(rel_start + 0.02, rel_end), 4),
                    "ratioStart": round(ratio_start, 5),
                    "ratioEnd": round(ratio_end, 5),
                }
            )
        result.append({"start_ms": int(round(start * 1000)), "words": timings})
    return result


def main():
    cache_path = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
        "~/.cache/sonora/cache.sqlite"
    )
    lyrics = run_json(["sonora", "lyrics", "--json"])
    current = run_json(["sonora", "current", "--json"])
    track = current.get("track") or {}
    track_id = str(track.get("id") or "")
    position = current.get("position")
    if not isinstance(position, (int, float)):
        position = None

    first_text = ""
    for line in lyrics.get("lines") or []:
        text = str((line or {}).get("text") or "").strip()
        if text:
            first_text = text
            break

    hit = pick_hit(cache_hits(cache_path, track_id), lyrics.get("source"), first_text)
    payload = {
        "lyrics": lyrics,
        "position": position,
        "trackId": track_id,
        "words": word_timings(hit) if hit else [],
    }
    print(json.dumps(payload, separators=(",", ":")))


if __name__ == "__main__":
    main()
