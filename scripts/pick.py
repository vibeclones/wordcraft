#!/usr/bin/env python3
"""Choose which upstream releases to host, thinning out toward the past.

stdin: JSON list of {tagName, publishedAt} (from `gh release list --json tagName,publishedAt`).
stdout: the tags to keep, newest first, one per line.

Taste: recent releases are kept densely, older ones sparsely.
  - the newest release is always kept, and so is the oldest one (a relic, for fun)
  - the last release of each major version is kept (the "stable" landmarks)
  - everything else is bucketed by age, and only the last release in each bucket survives:
      under a week old: one per day;  under a month: one per 3 days;
      under 3 months: one per week;   under a year: one per month;  older: one per quarter
"""
import json, re, sys
from datetime import datetime, timezone

rels = json.load(sys.stdin)
now = datetime.now(timezone.utc)
for r in rels:
    r["d"] = datetime.fromisoformat(r["publishedAt"].replace("Z", "+00:00"))
rels.sort(key=lambda r: r["d"], reverse=True)

def major(tag):
    m = re.match(r"^\D*(\d+)", tag)
    return m.group(1) if m else None

def bucket(r):
    days = (now - r["d"]).days
    if days < 7:   return ("d", days)
    if days < 30:  return ("3d", days // 3)
    if days < 90:  return ("w", days // 7)
    if days < 365: return ("m", days // 30)
    return ("q", days // 91)

keep, seen, seen_major = set(), set(), set()
for r in rels:  # newest first, so the first hit in a bucket/major is its latest release
    b, mj = bucket(r), major(r["tagName"])
    if b not in seen:
        seen.add(b); keep.add(r["tagName"])
    if mj is not None and mj not in seen_major:
        seen_major.add(mj); keep.add(r["tagName"])
if rels:
    keep.add(rels[0]["tagName"]); keep.add(rels[-1]["tagName"])
for r in rels:
    if r["tagName"] in keep:
        print(r["tagName"])
