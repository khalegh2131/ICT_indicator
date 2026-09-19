# ICT Assistant Research Findings

Date: 2026-09-15

## Scope

This document records reusable ideas from the supplied public references. It does not copy private or copyrighted TradingView source code. The implementation target remains a manual-analysis MT5 indicator, not an Expert Advisor or trade executor.

## Reference conclusions

### Inner Circle Trader concepts

The supplied ICT tutorial could not be fetched directly because the URL redirected to an external synchronization page. Therefore, its concepts are treated as a specification to verify against the user's supplied ICT material and public descriptions, not as a source to copy.

The canonical concept groups for this project are:

- Market structure: confirmed swing points, external and internal structure, BOS, CHoCH, MSS, protected highs/lows.
- Liquidity: BSL, SSL, EQH, EQL, previous day/week highs and lows, session highs/lows, liquidity sweep and reclaim.
- Delivery: displacement, FVG, inversion/iFVG, volume imbalance, order block, breaker, mitigation block, rejection block, BPR.
- Location: dealing range, equilibrium, premium/discount, OTE, draw on liquidity.
- Time: Asia/London/New York sessions, kill zones, macros, Silver Bullet, Judas/AMD/PO3.
- Context: multi-timeframe bias, SMT, volatility, spread, news/session risk, outcome tracking.

### GitHub: joshyattridge/smart-money-concepts

Useful as a reference implementation for deterministic base calculations:

- `swing_highs_lows`: pivot requires candles on both sides, so the pivot must be delayed until confirmation.
- `bos_choch`: supports close-based or wick-based breaks and returns level plus break index.
- `fvg`: three-candle gap with mitigation index; consecutive gaps can be joined.
- `ob`: detects blocks around a structure cross and tracks mitigation/breaker state.
- `liquidity`: groups multiple swing highs/lows within a range and records the first sweep.
- `previous_high_low`: maps completed higher-timeframe periods to lower-timeframe candles and tracks broken status.
- `sessions`: session membership and session high/low.
- `retracements`: current and deepest retracement from detected swings.

Important limitation: the swing and structure functions are batch calculations and use future candles to confirm historical pivots. For MT5 live use, the same results must be delayed and frozen after confirmation.

### GitHub: manuelinfosec/profittown-sniper-smc

Useful architectural ideas:

- Keep structure, OB filters, liquidity filters, Fibonacci location and backtesting as separate rule modules.
- Store a confluence checklist and reject low-quality setups instead of emitting every event.
- Record the full setup context and outcome.

Not suitable as-is:

- The repository is partly a prototype and contains simplified/demo rules.
- Its risk percentages and profit targets are not appropriate defaults for this indicator.
- It is designed around execution/bot flows, while this project must not place trades.

### GitHub: lordgaruda/XAU-60

Useful ideas:

- Typed data objects for SwingPoint, FairValueGap, OrderBlock, LiquidityZone and signal confirmation.
- Separate SMC analyzer, trend analyzer, CRT strategy and quality scoring.
- Asian-range sweep quality, rejection, volume and higher-timeframe bias as context fields.
- Explicit limits such as one setup per kill zone and two per day can be shown as analysis guardrails.

Not suitable as-is:

- It is a Python trading bot with execution and risk-management code.
- Some backtest/UI results are simulated or simplified.
- It contains assumptions specific to XAUUSD and must not be transplanted blindly.

## TradingView-derived ideas

Only publicly visible behavior is used:

- Tom DeMark Sequential can provide a secondary exhaustion context: price flip, nine-count setup, perfection and cancellation. It must never independently reverse ICT structure.
- HalfTrend can provide a smoothed micro-trend spine and volatility channel, but it is a lagging confirmation and must not create BOS/CHoCH.
- Divergence for Many Indicators provides regular/hidden divergence across several oscillators and a minimum-divergence-count idea. Divergence is warning/context only until price confirms structure.

## What the indicator must show

The chart assistant must show:

1. Current external trend and internal/micro trend separately.
2. Trend strength, age, protected level and current phase.
3. Early exhaustion warning without calling it CHoCH.
4. Confirmed structure change only after a closed-candle close break and required displacement.
5. The causal chain: liquidity target -> sweep/reclaim -> displacement -> MSS/BOS -> FVG/OB -> retracement -> entry readiness.
6. Every object with a tooltip explaining what it is, why it was drawn, its state, and what would invalidate it.
7. Fast state updates on the first tick of a new bar, with no repeated alert on later ticks.
8. Frozen historical signals: a closed-bar signal may be added, upgraded by a later event, or invalidated; it must not silently move or disappear.

## Official MQL5 timing and data references

The implementation of phases 1-3 follows the official MQL5 reference:

- `https://www.mql5.com/en/docs/series` — timeseries index 0 is the unfinished current bar; timeseries use reverse indexing.
- `https://www.mql5.com/en/docs/series/copyrates` — `CopyRates` can request by start time; returned bars are constrained by the requested time and arrays must be handled with explicit orientation.
- `https://www.mql5.com/en/docs/event_handlers/oncalculate` — `prev_calculated` is a performance hint, input array orientation must be checked explicitly, and a changed/deeper history can reset it to zero.

Adopted rules:

1. Final signals use a closed analysis bar and never bar 0.
2. Higher-timeframe data is accepted only when that timeframe bar has itself closed by the analysis cutoff.
3. Full rebuild and live processing call the same `AnalyzeClosedBar` and `UpdateContextForClosedBar` path.
4. A rebuild marks the current forming bar as already seen so shift 1 is not processed twice.

## Public ICT/SMC definition references

The public educational reference `https://tradingwyckoff.com/en/smart-money-concepts/` was used only to cross-check terminology and causal ordering. The adopted project rule is deliberately stricter than a label-only implementation: a Sweep is wick penetration plus reclaim close; MSS requires a close-based opposite structure break plus displacement and linked liquidity; FVG is a three-candle imbalance linked to a valid displacement; and iFVG flips polarity only after a close through the opposite boundary. Public material is reference text, not copied source code or a profitability claim.

## Explicit exclusions

- No order placement, position management or EA behavior.
- No claim of guaranteed profitability or 100% accuracy.
- No use of a single candle reversal as a trend reversal.
- No BOS/CHoCH label based only on wick unless the user explicitly enables a separate liquidity-event display.
- No unverified AI/KNN score in the core decision path.

## Implementation status of every promise in this document (added 2026-09-16)

This document records intent. It is NOT a description of the current build. Status verified by reading the canonical source on 2026-09-16; numbered root causes live in `AUDIT_ICT_SMC_MMM.md`.

### Concept groups promised above

| Promised | Status |
|---|---|
| Market structure: confirmed swings, external structure, BOS, CHoCH, MSS | Built |
| Internal structure per timeframe | Partial — the dashboard "Internal" row is the chart-timeframe trend, not a per-timeframe internal layer (#3) |
| Protected highs/lows | Computed, drawn **and now read as the reversal gate** since phase 11 (#8, #71). The gate compares the closed higher-timeframe close against the protected external level price. |
| Liquidity: BSL, SSL, EQH, EQL, PDH/PDL, PWH/PWL, session highs/lows | Built |
| Liquidity sweep and reclaim | Sweep built; "reclaim" is not recorded as its own event with its own id (#18) |
| Displacement | Built as a heuristic only; it does not require an FVG or a structure break (#24) |
| FVG, inversion/iFVG | Built. Every new FVG is immediately marked mitigated by its own bar (#25); `causal` is granted without a linked displacement (#27) |
| Volume imbalance | Not built |
| Order block | Built |
| Breaker | Built, but without the liquidity sweep strict ICT requires, and a single bar can flip BROKEN to BREAKER (#39) |
| Mitigation block (as a distinct concept) | Not built (#38) |
| Rejection block | Built, but the zone is the full candle instead of the wick (#40) |
| BPR (Balanced Price Range) | Not built |
| Dealing range, equilibrium, premium/discount | Built; the dealing range basis is the last two confirmed pivots rather than the real leg (#43) |
| OTE | Built; measured from the entry-zone midpoint instead of the impulse-leg retracement (#46) |
| Draw on liquidity | Built; scoring is effectively fixed-weight so an External level always wins on distance (#48) |
| Sessions and kill zones | Built. Times verified against public references. The hour inputs are inert — the windows are hard-coded (#50) |
| Macros | Not built |
| Silver Bullet | Dashboard text only; the draw-box input is inert (#52) |
| Judas / AMD / PO3 | Session-clock label only, not range-based accumulation/manipulation/distribution (#54) |
| Multi-timeframe bias | Built, and the H4 owner lock is verified by validator on real data |
| SMT | Not built |
| Volatility, spread, news/session risk | Not built |
| Outcome tracking | Not built |

### "What the indicator must show"

| # | Requirement | Status |
|---|---|---|
| 1 | External trend and internal/micro trend separately | Partial — two different notions of "internal" exist and are not unified (#3) |
| 2 | Trend strength, age, protected level, current phase | Partial — strength is the exhaustion score; age and phase are still absent; the protected level is now used as the confirmed-reversal gate (#8 closed in phase 11) |
| 3 | Early exhaustion warning without calling it CHoCH | Built |
| 4 | Confirmed structure change only after a closed-candle close break plus required displacement | Partial — LTF MSS requires displacement; the HTF path passes no displacement candidate at all, so HTF MSS can never occur |
| 5 | Causal chain from liquidity target to entry readiness | Partial — the chain is displayed, but it is not enforced before READY (#66) |
| 6 | Every object explains what it is, why, its state, and what invalidates it | Built and confirmed by the user's screenshot on 2026-09-16 |
| 7 | Fast state updates on the first tick of a new bar, no repeated alert | No alerting exists at all (#72) |
| 8 | Frozen historical signals must not silently move or disappear | Violated — registry caps drop the oldest entries and the redraw rebuilds only from the registries, so old objects vanish from the chart (see the audit's detailed section) |

### DeMark / HalfTrend / Divergence promises

All three are recorded above as intended secondary context. None is implemented. Separately, Tom DeMark, HalfTrend and divergence are outside the locked scope (ICT + SMC + MMM) unless the user explicitly re-adds them.

### Official MQL5 timing rules adopted above — verified in the build

All four adopted rules are genuinely implemented: final signals use a closed bar and never bar 0; higher-timeframe data is accepted only when that timeframe bar has closed by the analysis cutoff; rebuild and live processing share `AnalyzeClosedBar` / `UpdateContextForClosedBar`; and the rebuild marks the current forming bar as seen so shift 1 is not processed twice.
