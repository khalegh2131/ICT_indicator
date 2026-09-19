# Canonical ICT Assistant Architecture

## Product definition

A fast, non-automated MT5 chart assistant for high-selectivity ICT analysis. It displays complete ICT context, but only promotes a small number of setups to `READY`.

**Scope (locked 2026-09-16):** ICT + SMC + MMM. Wyckoff, classic Supply & Demand, Auction Market Theory / Market Profile, Volume Profile, Order Flow / Footprint / Delta, RTM and Al Brooks Price Action are out of scope and deliberately excluded.

## Implementation status — THIS DOCUMENT DESCRIBES THE TARGET, NOT THE CURRENT BUILD

Everything below is the target design. As of 2026-09-16 much of it is NOT implemented. Read this table before treating any rule in this document as a description of current behavior. Numbered root causes: `07_DOCUMENTATION/AUDIT_ICT_SMC_MMM.md`.

| Claim in this document | Actual state of the build |
|---|---|
| External structure and Internal structure as two layers *per timeframe* | Partial. External confirmed swings exist per timeframe. The dashboard row "Internal" is the chart-timeframe trend (`g_ltfTrendDir`), not a per-timeframe internal swing layer (#3). |
| Immutable `created_bar_time` and `confirmation_bar_time` | Partial. Creation time is stored; there is no separate confirmation-bar-time field. |
| A later bar may set `TOUCHED`, `MITIGATED`, `INVERTED`, `INVALID`, `EXPIRED`, `CONSUMED` | Partial. Only mitigated / inverted / invalidated exist. `TOUCHED` and `CONSUMED` have no representation. |
| Alerts keyed by event ID and confirmation bar time | Not implemented. There are no alerts; `OnTimer` is empty while a 1-second timer is armed (#72). |
| `BOS`: close breaks **a protected level** in the current structural direction | Not matching. It breaks the most recent *unbroken swing*, and it is also emitted when no prior trend exists at all (#4). |
| `REVERSAL_CONFIRMED` rules | **Implemented in phase 11** (#10, #8, #71, #70). One producer: a closed higher-timeframe bar must close beyond the protected external level (`UpdateReversalEngine`), and the confirmation must be fresh (`InpReversalFreshBars`). See the project's technical notes, section 4-0-10. |
| Exhaustion evidence includes "divergence or momentum contraction" | Absent. Six other observations exist (weak energy, failed extension, opposing close, opposing internal, near DOL, zone failure). |
| Exhaustion threshold is fully configurable | Partial. Thresholds exist, but the divergence/momentum component of the definition does not. |
| Setup pipeline ends in "quality score" | Not implemented. There is no quality score and no rejection of low-quality setups (#68). |
| Quality policy: the listed "core gates are hard requirements" | Mostly not implemented. `UpdateSetup` does not check a liquidity event, a structure event, a displacement link, an unmitigated zone, invalidation geometry or duplicate events (#66). |
| Soft evidence: session, SMT, divergence, volume/HVN, DeMark, HalfTrend | Only session exists. SMT, divergence, DeMark and HalfTrend are absent. |
| State list `WAITING_FOR_SWEEP` ... `EXPIRED` | Not implemented. The actual statuses are `WAITING_H4_BIAS`, `WAITING_DOL`, `WAITING_MTF_CONFLICT`, `WAITING_H1_CONTEXT`, `WAITING_M15_CONTEXT`, `WAITING_M5_SETUP`, `WAITING_M2_CONFIRMATION`, `WAITING_M1_CONFIRMATION`, `WAITING_RETRACE`, `WAITING_DEALING_RANGE`, `WAITING_DISCOUNT_OTE`, `WAITING_PREMIUM_OTE`, `READY`, `NONE`, `SETUP_ENGINE_DISABLED`. |
| "A failed setup remains visible in a muted color with a tooltip explaining the failure" | Not implemented. There is no failed-setup state and no persisted failure record. |
| "Drawing is diff-based: do not delete/recreate the entire chart" | Not matching. `RedrawChartObjects` deletes each object category and rebuilds it from the registries. |
| "Tooltips are generated from stored event metadata, not recomputed from mutable current price" | Mostly true for the Explain panel. Exception: the dashboard Location row reads live `SYMBOL_BID` while the setup engine uses the closed bar's close (#45). |
| Validation requirements (full vs incremental, restart, DST, ambiguous candles) | Designed and partially instrumented, not yet proven. Replay diagnostics currently write one shared file (#7 in the gates list). |

## Closed-bar contract

- Bar 0 is forming and is never allowed to create a final signal.
- All state transitions are evaluated on the latest closed bar only.
- A new-bar detector runs once per bar and is independent of tick rendering.
- Confirmed objects receive immutable `created_bar_time` and `confirmation_bar_time`.
- A later bar may change state to `TOUCHED`, `MITIGATED`, `INVERTED`, `INVALID`, `EXPIRED` or `CONSUMED`; it may not rewrite the original event.
- Alerts are keyed by event ID and confirmation bar time.

## Structure model

Each timeframe maintains two layers:

- External structure: major confirmed swings and protected highs/lows.
- Internal structure: smaller confirmed swings used for execution context.

Event rules:

- `BOS`: close breaks a protected level in the current structural direction.
- `CHoCH`: close breaks the protected level against the current structural direction.
- `MSS`: a CHoCH candidate that also has valid displacement and causal liquidity context.
- Wick-only penetration is a `LIQUIDITY_EVENT`, never a BOS/CHoCH.

## Trend phase model

The assistant must distinguish these phases:

- `TRENDING`: protected level intact, continuation breaks or displacement support the direction.
- `EXTENDING`: new leg is making progress but has not created a confirmed reversal.
- `EXHAUSTION_WATCH`: momentum/leg extension is weakening, price is near opposing liquidity or target, and micro structure shows warning signs. This is an advisory state only.
- `MICRO_PULLBACK`: internal counter-move without external invalidation.
- `MICRO_REVERSAL_CONFIRMED`: internal close break plus displacement, still not an external trend reversal.
- `RANGE_OR_TRANSITION`: external structure is no longer clean or draw on liquidity has changed.
- `REVERSAL_CONFIRMED`: external protected level is closed through and the reversal confirmation rules pass. **Implemented in phase 11.** The gate reads the real protected-level price (`SwingById`), compares the **close** of the last completed higher-timeframe bar against it, and publishes the break as an `EVT_EXTERNAL_BREAK` event. It is emitted only while the confirmation is still fresh; afterwards it reverts to the ordinary strength states. The MMM Smart Money Reversal is the stricter score layered on the same break.

Minimum exhaustion evidence should be configurable and must include multiple closed-bar observations, such as:

- loss of displacement relative to ATR;
- repeated failure to extend beyond the last external extreme;
- opposing internal break confirmed by close;
- divergence or momentum contraction;
- proximity to a major liquidity/DOL target;
- repeated FVG failure or deep retracement.

A single opposite candle can add one warning point but cannot change the trend phase.

## Setup pipeline

```text
HTF bias
  -> external/internal structure
  -> protected levels and liquidity map
  -> sweep + reclaim
  -> displacement
  -> MSS/BOS confirmation
  -> causal FVG/OB/Breaker
  -> premium/discount and OTE location
  -> DOL and session filter
  -> quality score and READY/WAIT/INVALID state
```

## Quality policy

The score is explanatory, not a probability. Core gates are hard requirements:

- valid directional context;
- confirmed liquidity event or explicitly selected model that does not require one;
- confirmed structure event;
- valid displacement where required;
- causal and unmitigated entry zone;
- acceptable invalidation and target geometry;
- no stale setup, dead zone or duplicate event.

Soft evidence may include session, SMT, divergence, volume/HVN, DeMark exhaustion and HalfTrend micro context. Soft evidence must never override a failed hard gate.

## State and failure display

The dashboard should show one primary state and the reason for waiting or failure:

- `WAITING_FOR_SWEEP`
- `SWEEP_DETECTED_WAITING_FOR_MSS`
- `MSS_CONFIRMED_WAITING_FOR_RETRACE`
- `RETRACE_ZONE_ACTIVE`
- `READY_ON_CLOSED_BAR`
- `FAILED_NO_DISPLACEMENT`
- `FAILED_STRUCTURE_INVALIDATED`
- `FAILED_ZONE_MITIGATED`
- `EXPIRED`

A failed setup remains visible in a muted color with a tooltip explaining the failure. It is not silently deleted.

## Performance rules

- Heavy historical reconstruction runs on initialization or explicit replay only.
- Live updates process only the new closed bar.
- Drawing is diff-based: update changed objects and do not delete/recreate the entire chart on every tick.
- Object count is capped by category and age.
- Tooltips are generated from stored event metadata, not recomputed from mutable current price.

## Validation requirements

Before live use, compare:

- full historical replay vs incremental new-bar replay;
- restart from the same bar vs uninterrupted run;
- closed-bar signal list before and after later bars;
- HTF mapping across DST and broker offsets;
- ambiguous candles where both SL and TP could be touched in one OHLC bar.

The indicator is considered stable only when these tests produce deterministic event IDs, timestamps and states.
