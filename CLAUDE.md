# CLAUDE.md

Project guidance lives in **`claude/claude.md`** (stable context) and
**`claude/handoff.md`** (living state — read it first, and update it after any
big implementation step or before compaction).

Hard constraints, repeated here so they are never missed:

- **No Microsoft**: never reverse-engineer, impersonate, or connect to Link to
  Windows / Phone Link cloud, OAuth, Device Graph, or WNS; never decompile or
  incorporate the Samsung MDX APK.
- **No cloud** for now — LAN + USB + (later) BLE only.
- Don't fabricate protocol details; pin a version and cite upstream, or mark it
  to verify.
