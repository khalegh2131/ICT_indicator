# Repaint and Timing Audit

Date: 2026-09-15

> Historical note: the legacy V13/V14 and Navigator sources referenced by this audit were removed during the 2026-09-15 workspace cleanup. This document preserves the reasons they were rejected; only the standalone canonical source remains active.

## Summary

STALE DOCUMENT — 2026-09-16: this audit describes the pre-canonical candidate collection (V13 EAGLE EYE, V14, root Navigator). Those files were deliberately purged from the repository and `01_CANONICAL_CANDIDATES/V13_EAGLE_EYE/` no longer exists. Only `01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5` is the active source. Keep this file as historical reasoning only; do not treat any path in it as present on disk. The timing conclusions were carried forward into the canonical closed-bar contract.

The current collection is not safe to treat as one consistent non-repainting system. `ICT_Assistant_Pro_V13_2_EAGLE_EYE` is the strongest timing candidate, but it still needs deterministic replay tests. V14 and the root Navigator contain timing paths that must not be reused unchanged.

## Findings

### High: V14 new-bar detection is not a reliable closed-bar gate

File: `01_CANONICAL_CANDIDATES/V14_EAGLE_EYE/ICT_Assistant_Pro_V14_EAGLE_EYE.mq5`

The code derives `g_is_new_bar` from `limit = rates_total - prev_calculated` and requires `limit > 1`. This is not a reliable new-bar detector: the initial calculation, history refresh, and later calls can produce different values, and a normal new bar can be missed. The canonical implementation must compare the current forming-bar timestamp with a stored timestamp and process shift 1 exactly once.

### High: V14 liquidity sweep timestamp uses the forming bar

File: `01_CANONICAL_CANDIDATES/V14_EAGLE_EYE/ICTv14_Liquidity.mqh`

`UpdateHTFLiquidity` marks sweeps with `iTime(_Symbol, PERIOD_CURRENT, 0)`. Even if the sweep decision is called from a new-bar branch, the timestamp is the current forming bar rather than the closed bar used for the event. This breaks event identity and can make tooltips and replay disagree. A closed-bar event must use shift 1 and store the exact confirmation bar time.

### High: V14 structure model can classify a normal counter-break as MSS

File: `01_CANONICAL_CANDIDATES/V14_EAGLE_EYE/ICTv14_Structure.mqh`

The structure code can promote a break to MSS when `sweep_id != -1` and `disp_id != -1`, but the current V14 caller sets `sweep_id = -1` and uses a displacement candidate without a complete causal registry. More importantly, the model uses the latest unbroken swing and does not clearly separate external protected structure from internal structure. This is insufficient for the requested trend-exhaustion behavior.

### Medium: V14 historical swing scan and live swing scan use different assumptions

File: `01_CANONICAL_CANDIDATES/V14_EAGLE_EYE/ICTv14_Swing.mqh`

The historical scan and new-bar scan use different loop boundaries and the live path checks `left_bars + 1` as the pivot shift. This needs a replay equivalence test. The same confirmed-pivot rule must be used in both historical reconstruction and incremental processing.

### High: Root Navigator uses the wrong chart-array endpoint for new-bar detection

File: `ICT_Market_Navigator.mq5`

`OnCalculate` uses `time[rates_total-1]` as `curBar`. In standard MQL5 indicator series arrays, index 0 is the current bar and index 1 is the latest closed bar; the last array element is the oldest loaded bar. This means the new-bar gate is not attached to the live bar. The Navigator should not be treated as timing-safe until its data orientation is made explicit and tested.

### Medium: Navigator mixes live/current and closed-bar timestamps

File: `ICT_Market_Navigator.mq5`

The pipeline intentionally uses both `g_candles[n-1]` and `g_candles[n-2]`, but the contract is not explicit at the engine boundary. Some state and visualization decisions use `n-1`, while displacement and replay use `n-2`. The canonical pipeline must pass a named `analysis_bar` object representing the latest closed candle and prohibit engines from choosing their own shift.

### Medium: Historical redraw/removal can hide state transitions

Files: `ICT_Market_Navigator.mq5`, `ICTv14_Draw.mqh`

Several paths delete objects by prefix or by age/distance. This is acceptable for a display cache, but not for event history. Event objects and failed setup objects must be separated from disposable live overlays. A failure should be muted or marked invalid, not silently deleted because price moved away.

### Medium: V13 still requires deterministic replay validation

File: `01_CANONICAL_CANDIDATES/V13_EAGLE_EYE/ICT_Assistant_Pro_V13_2_EAGLE_EYE.mq5`

V13 correctly uses a stored `time[0]` new-bar gate, `breakShift = 1`, and a separate confirmed pivot shift. However, it rebuilds arrays from copied history and uses static IDs/state. It must be tested for identical event IDs and timestamps after restart, history refresh, and incremental replay. The cloud copy is a duplicate and should not become a second source of truth.

### Low: Legacy versions are unsuitable as a timing baseline

The archived `ICT_Assistant_Pro` versions call `Update()` on every `OnCalculate` and mix current-time timers with chart-state mutation. They are useful for feature extraction only, not for timing or repaint claims.

## Canonical rules extracted from the audit

1. Treat all MT5 price arrays as explicitly oriented; never infer orientation from `rates_total-1`.
2. Detect a new bar using `time[0]` and process `analysis_shift = 1` once.
3. Store event time from the analyzed closed bar, never from shift 0.
4. Confirm swings only after the required right-side bars exist.
5. Require close breaks for structure; wick-only events remain liquidity events.
6. Keep external and internal structure registries separate.
7. Never promote MSS without linked sweep, displacement and protected-level evidence.
8. Preserve invalidated/failed events as historical records; only remove disposable drawings.
9. Make full replay and incremental replay produce the same event IDs, timestamps and states.
10. Use one canonical source file; do not maintain V13/V14/cloud variants as parallel active products.
