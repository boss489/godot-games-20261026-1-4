# 좌우 결투 신호등 / Night Signal Duel

Godot 4.7.2 local, self-contained 2D timing game. Open `project.godot` in Godot 4, or run:

```sh
godot --path .
```

## Play

- **A / ←**: defend left; **D / →**: defend right. On touch/mouse, use the large bottom left/right pads.
- Press only when the incoming foe enters the **bright HIT line** and its traffic light turns green. Early, wrong-side, or missed attacks cost one heart and reset the combo. Four hearts per run.
- **P / Escape** pauses/resumes; **R** immediately restarts; **Enter/Space** starts or continues. The pause and results overlays have clickable controls.
- The title offers **24 campaign intersections** (each unlocked by clearing the prior one) and an independent **90-second survival run**. Select unlocked stages from the grid. Progress and survival best score are saved with Godot `user://signal_duel_progress.cfg`.
- Five readable silhouettes: green standard, yellow sprinter (fast), red armored (hit twice, quickly), cyan switcher (changes lanes as it approaches), purple shadow (narrow center timing). Counter timing feeds a combo multiplier. Audio is synthesized in-game; no external assets or network calls.
- Stages draw from **20 distinct authored multi-beat patterns**; later stages increase length/speed and tighten timing. Survival gradually escalates across 90 seconds and uses its run seed to vary wave order.

## Verification

From this directory:

```sh
godot --headless --editor --import --quit
godot --headless --script res://tests/test_game.gd
godot --headless --script res://tests/test_full_runs.gd
godot --headless --script res://tests/test_ui.gd
godot --headless --quit-after 30
```

Verified on Godot 4.7.2: import clean; model tests **170 assertions, 0 failures**; deterministic complete-run tests for stages 1/8/16/24 and 90-second survival **5 completions, 0 failures**; UI/title/pause/restart/result/save integration **0 failures**; headless scene launch and native OpenGL/Metal launch exited cleanly. The UI test writes normal local progress to `user://`.

## Browser build
`../docs/web-signal-duel/` contains the Godot Web export. Serve that folder over HTTP, for example `python3 -m http.server 8000 --directory ../docs/web-signal-duel`, then open `http://127.0.0.1:8000/`. Do not open `index.html` using `file://`. Web export uses the no-threads template and does not require cross-origin isolation. Progress is local to that browser/origin.

## Limits

Stage content is patterned arcade escalation rather than 24 unique arenas or stories. Device-specific touch validation has not been performed. Automated perfect-input full runs are not a substitute for a human balance/accessibility playtest. The title/signal typography uses installed Korean system fonts where available, with OS fallback elsewhere.
