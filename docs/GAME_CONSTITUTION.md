# Endless Battle — Game Constitution

Permanent design constraints for Cursor and human contributors.
Source code is implementation truth; this document is the non-negotiable product contract.

---

## What Endless Battle Is

Endless Battle is a classic PC RTS inspired primarily by:

- Warcraft III
- Age of Empires
- Stronghold
- Cossacks

It is **not** a MOBA.

---

## Core Game Pillars

1. Responsive RTS unit control
2. Economy and workers
3. Base building
4. Army production
5. Heroes
6. Neutral creep camps
7. Strategic AI opponent
8. Large battles bigger than Warcraft III but not Cossacks-scale
9. Clear readable combat
10. Stable long matches

---

## Primary Quality Reference

**Warcraft III** is the primary reference for:

- command responsiveness
- movement reliability
- pathfinding feel
- hero control
- attack-move behavior
- army readability
- command feedback

Do not copy Warcraft III implementation blindly.
Match the quality principles.

---

## Non-Negotiable Player Experience

When the player gives a command:

- units obey immediately
- latest player command has highest authority
- units do not keep following obsolete group/formation commands
- units should reliably reach valid destinations
- normal movement must not require repeated clicking
- formations must never fight player commands
- no random runtime crashes
- no parser-error commits
- no stale previously-freed instance crashes

---

## Development Priority

Until core gameplay is stable:

1. crashes / runtime safety
2. player movement
3. performance
4. AI that actually plays
5. combat feel
6. UI / audio / graphics
7. balance / content

Do not add content to hide broken core mechanics.

---

## Related Documents

- `docs/ENGINE_RULES.md` — ownership, Node safety, performance
- `docs/MOVEMENT_CONTRACT.md` — target player movement design
- `docs/WORKFLOW.md` — Cursor/dev workflow and commit discipline
- `docs/MILITARY_AI_V2.md` — enemy military V2 ownership details
- `docs/ROADMAP.md` — current milestone task order (subordinate to this constitution when they conflict)
