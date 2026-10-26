# 통나무 섬 배달 / Log Island Delivery

Godot 4.7.2 standalone, offline, single-screen delivery puzzle. Open `project.godot` in Godot or run `godot --path .` from this folder. No third-party assets or services.

## Play

- Title: Enter or click. Level chart: click an unlocked number, or Enter to continue at the latest unlocked level.
- Arrow keys / WASD: move and face; bump a log to roll/push it. A log in water is a bridge; board it, then steer into empty water to pole it like a raft. Step onto land to leave the raft.
- Space / F: fell the tree immediately ahead. It lands one square beyond the tree, provided that square is free earth, dock, or water.
- Pick up the golden parcel, then reach the stamped mailbox. Delivery unlocks the next stage; Enter/click advances.
- Z / Backspace: unlimited undo; R: restart stage; H: toggle reachable next-tile outlines; Escape: level chart.
- Progress is stored locally in Godot's `user://island_progress.json`. The UI test uses a separate temporary save.

Six terrain tiles are earth, sea, cliff, tree, dock, mailbox. Three physical log conditions are standing tree, felled log on land, floating log on water. Levels move from a single-square bridge to parcel detours, rolling a felled log over earth, and multi-square raft passages. All 36 layouts are deterministic and have an authored successful move sequence.

## Verification

From this folder:

```sh
godot --headless --editor --path . --import
godot --headless --path . --script res://tests/test_game.gd
godot --headless --path . --script res://tests/test_ui.gd
godot --headless --path . --quit-after 15
```

The state test asserts terrain/log transitions, parcel pickup and undo, push/raft behavior, all 36 distinct serialized layouts, successful replay and complete rewind. The UI test traverses title → chart → game → victory → next level and reads the persisted unlock value back. Visual rendering is programmatic woodcut/map-style vector art and short synthesized tones; no downloaded audio.

## Browser build
`../docs/web-log-island-delivery/` contains the Godot Web export. Serve that folder over HTTP, for example `python3 -m http.server 8000 --directory ../docs/web-log-island-delivery`, then open `http://127.0.0.1:8000/`. Do not open `index.html` using `file://`. Web export uses the no-threads template and does not require cross-origin isolation. Progress is local to that browser/origin.

## Known limits

The 36 stages are algorithmic variations of a central crossing motif, not 36 individually hand-crafted puzzle mechanisms. A deterministic replay proves every stage can be completed, but does not certify uniqueness or difficulty. There is no gamepad-specific mapping. Headless launch verifies runtime loading, not a human visual inspection of the window.
