# ICT Assistant Canonical v0.1

This folder is the standalone package for the first canonical MT5 indicator core.

Phase 0 status: FINALIZED on 2026-09-15.

Development source: `D:\ICT_indicator`

MT5 compile mirror: `C:\Users\Khaleq\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Indicators\khaleq\newICT`

## Scope (locked 2026-09-16)

In scope: **ICT (Inner Circle Trader) + SMC (Smart Money Concepts) + MMM (Market Maker Model)**.

Out of scope, deliberately excluded: Wyckoff, classic Supply & Demand, Auction Market Theory / Market Profile, Volume Profile, Order Flow / Footprint / Delta, RTM, Al Brooks Price Action.

Order Flow / Footprint was excluded for a platform reason, not a design preference: the official MT5 documentation states that for the Forex market the Volumes value is the number of price changes rather than real volume, so a real Delta cannot be derived from native MT5 forex/CFD data.

Full component-by-component status: `07_DOCUMENTATION/AUDIT_ICT_SMC_MMM.md`.

## Files

- `ICT_Assistant_Canonical_v0_1.mq5`: the only source file required by this package.

## Required `.mqh` files

None. This version is intentionally self-contained. It does not include the legacy V13/V14 headers or the older shared engines because those files have different timing contracts and would make this package non-deterministic to maintain.

## Current capabilities

- Closed-bar analysis only. Bar 0 never creates a final event.
- New-bar processing keyed by `time[0]`.
- External and internal swing context.
- Protected high/low are computed and drawn for H4. They are NOT yet used as a reversal-confirmation gate.
- Liquidity sweep and reclaim context.
- Displacement detection using ATR and body/range ratio.
- Three-candle FVG context.
- Setup gate (exactly what the code checks): H4 owner bias confirmed -> aligned DOL exists -> no MTF conflict -> H1/M15/M5 aligned -> M2/M1 execution confirmation aligned -> a causal FVG or a VALID OB in the bias direction exists -> H4 dealing range valid -> price inside Discount+OTE (bull) or Premium+OTE (bear). Sweep, MSS and Displacement are displayed as events but are NOT part of this gate yet.
- `READY` state (plus the `WAITING_*` states) with Entry / Stop / TP1-TP3 geometry. The stop distance is currently a fixed 20-point buffer and is not yet ATR-aware or aware of `SYMBOL_TRADE_STOPS_LEVEL`; the reported R:R is taken from the input rather than derived from the actual TP/DOL distance.
- Reachable trend-phase states: `TRENDING`, `EXTENDING`, `EXHAUSTION_WATCH`, `MICRO_PULLBACK`, `MICRO_REVERSAL_CONFIRMED`, `RANGE_OR_TRANSITION`, `REVERSAL_CONFIRMED`. Since phase 11 the last one is produced by one code path only: the closed higher-timeframe bar must close beyond the protected external level, and the confirmation must still be inside `InpReversalFreshBars` chart bars (`reversalFresh`). Without that gate the state is not emitted.
- Hover Explain panel describing each object: what it is, why it formed, its current state, what validates it, what invalidates it, and how to verify the number manually. Native MT5 object tooltips are deliberately suppressed using the official `"\n"` sentinel documented by MQL5.
- English ICT terminology on chart objects; Persian explanations in the hover panel and in the dashboard.
- Dark chart colors intended for a white chart background.
- No order placement. This is an indicator, not an Expert Advisor.

## Important status

This is the first standalone canonical package, not a profitability claim or a finished production release. Phase 0 is finalized; feature completion and validation continue in later phases. The following still require MetaEditor and Strategy Tester validation:

- Compile in the user's MT5 installation.
- Full replay versus incremental replay.
- Restart determinism.
- XAUUSD broker symbol and point/price conventions.
- Higher-timeframe mapping and DST/session handling.
- Setup state persistence across multiple bars.
- Historical invalidation and mitigation lifecycle for FVG/OB zones.

## Known gaps (honest status)

This package is NOT feature-complete. The following are known, recorded and numbered in `07_DOCUMENTATION/AUDIT_ICT_SMC_MMM.md`:

- Every new FVG is marked mitigated by its own creation bar, so no FVG is ever shown as fresh.
- `causal` is granted to FVGs whose displacement is only an unlinked energy candidate.
- Breaker blocks are created without the liquidity sweep that strict ICT requires, and a single bar can flip BROKEN to BREAKER.
- The rejection-block zone uses the full candle range instead of the wick.
- `BOS` is emitted even when no prior trend exists.
- `LSTATE_INVALID` is never assigned, so liquidity levels never expire.
- Dealing range is the last confirmed swing high to the last confirmed swing low, and OTE is measured from the entry-zone midpoint rather than from the real impulse leg.
- Sweep / MSS / Displacement are not enforced as READY gates.
- `REVERSAL_CONFIRMED` and the MMM Smart Money Reversal are implemented as of phase 11. The confirmation rule is strict and single-sourced: a **closed** higher-timeframe bar (never a wick) must close beyond the protected external level — the protected low while the owner bias is bullish, the protected high while it is bearish. Smart Money Reversal is a stricter score on top of that break (opposing liquidity sweep, chained displacement, an aligned causal FVG or valid order block, and lower-timeframe context agreement) against `InpSMR_MinScore`. It is the project's own explicit operational definition, not a quotation of a third party's private rule. Exhaustion can never flip the owner bias by itself: the whole file contains exactly one assignment to `g_htfBias`, and it is the declaration.
- Six session-hour inputs and `InpMTF` and `InpDrawSilverBullet` have no effect on the logic.
- The broker GMT offset is detected once at init and is not refreshed when the broker changes offset for DST.

Repair roadmap: documented phase-by-phase in the repository documentation (phases 7-15).

## Installation

1. Copy this `.mq5` file into the terminal's `MQL5\Indicators` folder, or open it directly in MetaEditor and compile it.
2. Attach `ICT_Assistant_Canonical_v0_1` to a chart.
3. Start with a demo account and inspect closed-bar events in visual replay.
4. Do not treat the `READY` state as an automatic trading instruction.

## Why no `.mqh` files yet

The package is kept deliberately small until each subsystem has a tested contract. When a subsystem becomes stable, it can be extracted into a focused header such as `CanonStructure.mqh`, `CanonLiquidity.mqh`, `CanonZones.mqh` or `CanonRender.mqh`. Those headers should be added only with tests and a documented ownership boundary.
