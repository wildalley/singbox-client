# Obsidian Signal design handoff

Generated with Google Stitch MCP on 2026-08-28.

- Stitch project: `projects/13673201704756137298`
- Design system: `assets/13690083369528402681`
- Project title: SingBox Client
- Visual system: Obsidian Signal

## Screens

- `SingBox Home` — disconnected mobile state (`f138010213974d5bbccc0bd87cb12033`)
- `SingBox Home (Connected)` — connected mobile state (`eb682977b8e44d4886316ea1ebacfe22`)
- `Nodes List` — mobile node selection (`2f770bc8685c4c2496b63a79ff3cd9ca`)
- `Settings` — mobile configuration (`aa85b91da92245ad86dcf24e2b45942c`)
- `Overview — SingBox` — desktop dashboard (`7e1ba17d99ec4a5d871e209151d5ccf7`)
- `Settings — Obsidian Signal` — refreshed mobile configuration (`c719162dee81486997e4bdd87122f41b`)

Preview exports (`home-disconnected.png`, `home-connected.png`, `nodes.png`, `settings.png`, and `desktop-overview.png`) are kept in this directory for implementation review. The Flutter code intentionally recreates the design using native widgets and CustomPaint rather than embedding generated HTML.

## Synapse V4 (successor)

Obsidian Signal is the design the app ships today. **Synapse V4** is the next
visual direction: same information architecture, denser and more instrumented
presentation.

- Reference sheet: [`synapse-v4.png`](synapse-v4.png)
- Implementation plan: [`synapse-v4.md`](synapse-v4.md)

The plan supersedes the Obsidian Signal tokens where the two disagree. It is
written to be applied in stages, so the two can coexist while the migration is
in progress.
