# Phase Execution Status

Date: 2026-09-15

## Canonical base promotion

The workspace has one active standalone canonical source: `01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5`. It contains the typed causal-chain implementation for structure events, liquidity, displacement, FVG, OB, DOL, setup state, chart rendering, and education mode.

This promotion is intentional: the project is now extending the strongest existing ICT implementation instead of maintaining a smaller parallel reimplementation.

Phase 1 integration progress: V13 closed-bar structure events are persisted to a restart-safe common ledger with Event ID, event time, type, direction, confirmation shift, protected swing, displacement ID, and sweep ID. The V13-specific validator is `tools\Validate-V13EventLedger.ps1`.

Phase 2 implementation progress: V13 now tracks FVG mitigation/invalidation lifecycle, uses the existing causal OB mitigation-to-breaker chain, and registers/draws closed-bar Rejection Blocks with touched/invalid states. The Phase 2 implementation gate is complete; replay evidence remains the validation gate.

## Phase 3 advanced implementation progress

- Added confirmed-structure MTF state for H4, H1, M15, M5, M2, and M1.
- H4 remains the Bias owner; H1/M15 are Context, M5 is Setup, and M2/M1 are Confirmation.
- Lower-timeframe conflicts are reported and block READY rather than changing H4 Bias.
- Dashboard now exposes the six-timeframe direction chain and conflict reason.
- Runtime MTF replay, broker offset, and DST validation remain evidence gates.

## Batch 1: Phases 0-2

### Phase 0 - Research and organization

Status: VALIDATED

- Canonical source: `01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5`
- Package source and MT5 mirror are synchronized by SHA256 after each source update.
- Legacy V13/V14 and Navigator timing paths remain reference material only.
- The canonical source is the only active implementation target.

### Phase 1 - Closed-bar and no-repaint foundation

Status: IMPLEMENTED, VALIDATION INCOMPLETE

Implemented and checked:

- New-bar gate uses `time[0]`.
- Analysis uses shift `1`, the latest closed bar.
- External and internal swing collections are separate.
- Protected high/low values are derived from confirmed swings.
- MSS now requires a causal sweep and displacement in addition to an internal close break.
- One immutable in-memory event record is appended per analyzed closed bar with a deterministic event ID.
- Each analyzed event is also appended to the versioned common CSV ledger `ICT_Assistant_Canonical_Events_v2.csv` for restart/replay evidence.
- Ledger writes are restart-safe: an existing `eventId` is not appended again after reinitialization.

Still required before VALIDATED:

- Full replay versus incremental replay comparison.
- Restart determinism comparison.
- Historical signal immutability check after later bars.
- Broker-specific XAUUSD data validation.

### Phase 2 - ICT core

Status: IMPLEMENTED, RUNTIME VALIDATION PENDING

Implemented in canonical source:

- Liquidity sweep and reclaim context.
- BSL/SSL through protected high/low liquidity levels.
- Close-based structure break context and causal MSS gate.
- ATR/body displacement filter.
- Three-candle FVG detection.
- Order-block search with mitigation and invalidation states.
- Breaker and BPR calculation hooks.
- Zone lifecycle states: fresh, mitigated, invalid.
- FVG invalidation is represented as an explicit `ZONE_INVERTED` / iFVG state and inverted zones are rejected as fresh entry zones.
- Closed-bar structure breaks now emit explicit `BOS`, `CHoCH`, or causally validated `MSS` event types with an owner label.

Still required before VALIDATED:

- Dedicated replay fixtures for false sweeps and false structure breaks.
- Explicit iFVG transition tests.
- Independent breaker and BPR fixtures.
- Verification that failed and mitigated objects remain explainable in the event record.

The implementation gate is complete; the remaining work is runtime evidence from XAUUSD replay.

## Build evidence

- MetaEditor: `C:\Program Files\MetaTrader 5\MetaEditor64.exe`
- Mirror compilation: `0 errors, 0 warnings`
- Canonical source, package source, and mirror SHA256 hashes match.

## Batch 2: Phases 3-4 progress

### Phase 3 - MTF and market context

Status: IMPLEMENTED PARTIALLY, VALIDATION INCOMPLETE

- H4 external structure is the authoritative Bias owner.
- H1, M15, M5, M2 and M1 retain explicit context, setup and confirmation roles.
- Lower-timeframe external conflicts no longer reverse H4 Bias or create an aligned READY setup.
- MTF conflict and its Persian explanation are shown in the dashboard.
- Mixed-timeframe replay and broker-time alignment still require executable validation.
- M2/M1 internal confirmation is now a hard gate for `READY`; lower-timeframe conflict is explained instead of changing H4 Bias.
- H1 and M15 external structure are now hard Context checks against H4 Bias.
- M5 external/internal structure is now the Setup check; M2/M1 remain execution Confirmation checks.
- Dashboard identifies the MTF owner as H4 and reports the failing hierarchy layer.
- The event ledger schema is versioned so older records cannot be mixed with the new structure-event columns.
- Trend state now persists bias, age, strength, start time, and transition reason; an unconfirmed opposite break enters `RANGE / TRANSITION` instead of silently flipping Bias.

### Phase 4 - Location and trade model

Status: IMPLEMENTED PARTIALLY, VALIDATION INCOMPLETE

- Premium/Discount, Equilibrium, OTE, DOL, PDH/PDL and PWH/PWL are calculated.
- Asian range, session classification, London/New York killzones and session High/Low are calculated from closed bars.
- AMD/PO3, CRT, Silver Bullet, Breaker and BPR calculation paths are wired into the closed-bar pipeline.
- Each remaining model needs independent replay fixtures and invalidation checks before validation.

## Phase 5 progress

Status: IMPLEMENTED, VALIDATION INCOMPLETE

- Exhaustion is calculated only after a closed bar through the shared analysis pipeline; bar 0 cannot create a state.
- The score uses six independent observations: range/body energy contraction versus the closed-bar lookback, failed extension against the prior lookback extreme, opposing close, opposing internal structure, proximity to DOL, and adverse FVG/iFVG state.
- Thresholds are explicit inputs: `InpExhaustionWeakRangeRatio`, `InpExhaustionWatchScore`, `InpExhaustionRangeScore`, and `InpExhaustionNearDOL_ATR`.
- States are exposed in the dashboard and Persian Explain panel: `TRENDING`, `EXTENDING`, `EXHAUSTION_WATCH`, `MICRO_PULLBACK`, `MICRO_REVERSAL_CONFIRMED`, and `RANGE_OR_TRANSITION`.
- `MICRO_REVERSAL_CONFIRMED` is explicitly an internal warning; it requires opposing internal structure plus an opposing displacement candle and cannot change `g_htfBias`.
- `REVERSAL_CONFIRMED` remains reserved for a separately proven external H4 protected-structure break; Exhaustion never promotes an internal warning to an H4 reversal. Corpus correction (2026-09-16): "reserved" means **unreachable in code today** — no path assigns this state, and the H4 protected high/low is computed but never read. Phase 11 must build this gate before the state can ever appear.
- The explanation includes the score, evidence, and the rule that H4 Bias remains unchanged until external confirmation.

Still required before `VALIDATED`:

- Replay fixtures for trend continuation, weakening trend, range transition, and internal reversal.
- Runtime XAUUSD evidence that bar-0/restart processing does not change historical exhaustion states.
- Evidence that an M1/M2 opposing displacement only creates an internal warning and never flips H4 Bias.

### Phase 5 build evidence (2026-09-16)

- Fresh MetaEditor compile and MT5 mirror sync: `0 errors, 0 warnings`.
- SHA256 (canonical/package/mirror): `48A7643CC9AFD92A31FE867647A04E3359055FFCBE67F0824877DAFE94C05097`.
- Artifact: `ICT_Assistant_Canonical_v0_1.ex5`, `2026-09-16 00:44:00`.

## Phase 6 validation execution (2026-09-16)

Status: IN PROGRESS — partial runtime gates passed

- Actual MT5 `ICT_Assistant_Canonical_ReplayLedger.csv`: 99 events; canonical 11-column ledger validator PASSED (0 duplicate IDs, 0 invalid IDs, 0 invalid times, 0 non-positive confirmation shifts).
- Actual MT5 `ICT_Assistant_Canonical_MTF_Diag.csv`: 600 rows; headerless seven-column parser fixed and hierarchy validator PASSED (0 missing chains, 0 invalid H4 owners, 0 READY-during-conflict rows, 0 lower-timeframe oppositions without a conflict block).
- Replay self-comparison PASSED, but this is not yet Full-vs-Incremental proof because both inputs were the same file. Independent second run and restart comparison remain open.
- The older `ICT_Assistant_Canonical_Events_v2.csv` in Common\Files uses a stale 14-column schema from an earlier build and was not falsely accepted as current evidence.
- Explain hover hardening: native MT5 tooltips now use `"\\n"` (hidden-tooltip sentinel) instead of an empty string, which otherwise makes MT5 display the object name. Fresh build/reload visual confirmation remains pending.

## Explain hover regression: truncated 64-bit identifiers (2026-09-16)

### Root cause

Every analysis object was named from a truncated identifier:

```mql5
StringFormat("ICTv13_FVG_%d", (int)f.id)          // f.id is ~1.79e15
"ICTv13_LIQ_" + IntegerToString((int)g_liquidity[i].id)
```

The registry stores the full `long` identifier, but the name carried only the low 32 bits. `BuildExplanation()` parsed the truncated number from the object name and searched the registry with it, so every lookup missed. With no explanation lines produced, `RenderExplainPanel()` deleted the panel, which is why hovering produced neither Persian nor English text.

### Fix

- Added `IdToStr(long)` using `StringFormat("%I64d", id)` and applied it to every identifier-bearing object name (`EVT`, `EVTL`, `FVG`, `FVGCE`, `OB`, `REJECTION`, `LIQ`, `SWEEP`) and to the explanation titles.
- Object names and the registry now share the same 64-bit identifier, so hover resolves the real record again.
- Added a fallback so a hovered object can never render an empty panel: if lookup still fails, the panel reports the full object name and states that the identifier link is broken instead of showing nothing.

### Build evidence

- Fresh MetaEditor compile and MT5 mirror sync: `0 errors, 0 warnings`.
- SHA256 (canonical/package/mirror): `0213D354232A3E0D87E6FA5EB29D17602945710FB9AAE4A20E2150B9560E2651`.
- Artifact: `ICT_Assistant_Canonical_v0_1.ex5`, `2026-09-16 01:14:23`.
- User visual confirmation after chart reload: still pending.

## Blocking evidence gaps

The former legacy behavior-test sources were removed during the workspace cleanup because they referenced missing `include/ICT` headers and were not executable validation for the standalone canonical contract. The remaining fixture under `05_TESTS_AND_VALIDATION` is retained for future canonical validation work.

No phase is release-ready until executable replay evidence exists. Phase 7 must remain blocked until phases 1-6 pass their behavior gates.

## Validation tools

- `tools\Sync-And-Compile-Canonical.ps1` synchronizes and compiles the MT5 mirror.
- `tools\Validate-CanonicalEventLedger.ps1` checks the common ledger for duplicate IDs, invalid timestamps, missing states/reasons, and non-monotonic rows.
- The ledger validator requires the indicator to be attached to a chart and to process at least one closed bar first.

## Batch 3: chart visibility and bar-time correctness (2026-09-15)

### Critical defect: Phase 3 MTF was dead code

`AnalyzeMTFContext()` was defined but never called anywhere in the file. Consequences: `g_mtfContext` stayed zeroed, `DrawLocationLevels()` returned early at `if(high<=low) return;`, so no EQ/OTE lines were ever drawn; the MTF conflict gate never blocked `READY`; and no multi-timeframe picture existed on the chart. Phase 3 was therefore 'implemented' on paper only.

### Defects found and corrected in this batch

- Session/AMD and PDH/PDL/PWH/PWL were computed with `TimeCurrent()` (server "now") instead of the analyzed bar time; HTF structure and MTF context read the newest bars instead of "as of the analyzed bar" (look-ahead).
- `UpdateSetup(c[0])` used the forming bar close, violating the closed-bar contract.
- No chart objects existed for liquidity, sweeps, sessions/killzones, Asian range, MTF levels, or the trade model; only the dashboard was visible (matching the early report "I see nothing but a dashboard").
- FVG was detected only when a structure event was created (real FVGs on displacement without a break were dropped); there was no iFVG state and `InpFVG_ExpireBars` was unused.
- OB search used only the candle immediately before displacement instead of the last opposite-colour candle; zone basis was body-only with no option for the full candle range.
- EQH/EQL created one object per swing pair instead of clustered equal levels.
- Sweep could match a liquidity level that was registered after the swept bar (no time-ordering guard).
- AMD mapped London to Accumulation; real Power of 3 has Asia=Accumulation, London=Manipulation, NY=Distribution.
- No broker offset or DST handling existed (fixed manual offset only).

### Implemented

- One shared closed-bar pipeline `AnalyzeClosedBar(shift)` used by both live processing and history rebuild, so full-history and incremental processing go through identical code.
- History rebuild on attach (`InpRebuildHistoryOnAttach`, `InpHistoryScanBars`) so the chart is populated immediately; ledger writes are suppressed during rebuild unless `InpWriteLedgerDuringRebuild` is enabled.
- Bar-time time base: `g_serverGMTOffsetHours` (auto-detected or overridden), NY clock with US DST rules, killzone windows (Asian 20-00, London 02-05, NY AM 07-10, London Close 10-12, NY PM 13:30-16), Silver Bullet windows (03-04, 10-11, 14-15 NY), and session ranges computed from `InpSessionSourceTF` (default M15) independent of the chart timeframe.
- `CopyRatesAsOf()` and `PreviousClosedBucket()` so higher-timeframe and daily/weekly values are read as of the analyzed bar.
- Session highs/lows registered as liquidity; EQH/EQL clustered; sweep time-ordering guard.
- Chart layer: liquidity map with labels and tooltips, sweep markers, FVG boxes with CE line and iFVG state, OB boxes with lifecycle state, rejection blocks, killzone/Asian range boxes, MTF protected levels labelled with owner timeframe and role, and a setup box with Entry/SL/TP plus reason text. Rebuilt once per closed bar via `RedrawChartObjects()`.
- Display inputs for every object group plus adjustable MTF chain timeframes.

### Build evidence

- MetaEditor: `0 errors, 0 warnings`
- SHA256: `7C5FB435DC7812EE01DEB8ABD7F3D2668DC23D96F6ACB23E86FF5F2A09653F5B` (canonical, package and mirror match)

### Known limitations to close before Phase 6 can be claimed

- During history rebuild, PDH/PDL/session levels are registered for the latest bar only, so historical sweeps of session/daily levels are not reconstructed yet.
- Historical DST is assumed constant over the rebuilt window (the auto-detected offset is a single value); a per-period offset table is required for exact historical session mapping.
- Validation harness artefacts for Phase 6 (replay ledger comparison, restart determinism, MTF diag CSV) are still not implemented. See `VALIDATION_PLAN_FA.md`.

## Batch 4: Explain Mode - indicator and teacher (2026-09-15)

### Requirement

Hovering over any drawn object must explain, in Persian: what the level/zone is, why it was formed, what makes it valid, what makes it fake or invalid, and how the reader can verify the claim themselves.

### Why a panel and not a tooltip

`OBJPROP_TOOLTIP` is single-line only and MetaTrader does not apply bidi reordering, so Persian text containing inline Latin terms breaks order. Two measures were taken: (1) a multi-line on-chart panel is used for the teaching text so nothing is squeezed into one line, and (2) every generated line is passed through `RtlSafe()`, which moves Latin/digit runs to the start of the line so a Latin word can never sit inside a Persian run. Panel font defaults to `Tahoma` because `Consolas` has no Persian glyphs.

### Implemented

- `OnChartEvent(CHARTEVENT_MOUSE_MOVE)` hit testing (`HitTestExplainObject`) with price/time to pixel conversion, covering horizontal lines, rectangles, trend segments and text anchors.
- Per-object explanation builders: liquidity (PDH/PDL/PWH/PWL/EQH/EQL/swing/session), sweep markers, structure events (BOS/CHoCH/MSS with the displacement gate explained), FVG/iFVG with CE, order blocks with the full breaker chain, rejection blocks, killzone and Asian range windows, MTF protected levels with hierarchy rules, location lines (EQ/OTE/premium-discount) and the setup itself with every WAITING_* code explained.
- Panel renderer with wrapped lines, colour coding, edge-aware placement, and cleanup of stale rows.
- `ICT_Assistant_Canonical_Explain.csv` snapshot (Common\Files, UTF-16) written once per closed bar with object name, kind, price, time and the joined explanation, so any claim can be copied out and checked numerically.

### Build evidence

- MetaEditor: `0 errors, 0 warnings` (fresh compile, log and artifact timestamp verified)
- SHA256: `CE9474C3824330A913698FC3D6124C794711EAEBC05C25CAF14C0A80E6D89811`
- Artifact: `ICT_Assistant_Canonical_v0_1.ex5`, 157,750 bytes, 2026-09-15 19:30:26

### Build verification defect (corrected)

The earlier `Sync-And-Compile-Canonical.ps1` accepted whatever `.log` it found next to the mirror. With MetaEditor already open, the command-line `/compile` invocation was ignored and the stale log from the previous successful build was read, so a real compile error (`error 199: wrong parameters count` on a single-argument `StringFormat`) was wrongly reported as `0 errors`. The build script now deletes the old log, requires a freshly produced log, requires the `.ex5` to be no older than the source, and prints a warning when MetaEditor is running. Note for operators: MetaEditor deletes the previous `.ex5` when a compile fails, so a missing artifact in the mirror means the last compile did not pass.

## Batch 5: Persian rendering and documentation contract (2026-09-15)

- Replaced the invalid literal `\\xNNNN` text encoding with real Persian Unicode characters in the canonical source and preserved UTF-8 BOM encoding.
- Removed the temporary M0/M1/M2/M3 text probe and its codepoint diagnostics from the indicator.
- Corrected the Persian shaping join condition so right/left joining capability is checked for both neighboring letters instead of treating every next character as connectable.
- Added the mandatory root documentation contract: read-before-edit, canonical-only changes, no deletion without approval, no guessing or unsupported claims, fresh build evidence, and mandatory status updates.
- Build evidence after this change: `0 errors, 0 warnings`; canonical/package/mirror SHA256 `8CBF3BA37291C2918F1864F671D97A9AFAC7F2D4078505D76F97AB9478DE057B`; artifact timestamp `2026-09-15 22:06:01`.
- The explanation rows use read-only native `OBJ_EDIT` controls with right alignment and raw Unicode text; the extra separator and visible edit borders are hidden by matching the border color to the panel background. Final MT5 visual confirmation remains pending after reload.
- **User verification still pending:** remove and re-add the indicator in MT5 so the loaded chart instance uses the new `.ex5`, then confirm Persian readability with a screenshot. No release claim is made until that visual check passes.

## Batch 6: Phase 1-3 hardening (2026-09-15)

### Implemented in canonical source

- `CopyRatesAsOf` now uses time-bounded `CopyRates(start_time,count)` and discards incomplete higher-timeframe bars at the analysis cutoff.
- `OnCalculate` checks input-array orientation explicitly and prevents the latest closed bar from being processed twice after history rebuild.
- History rebuild now runs `AnalyzeClosedBar` plus HTF, session, DOL, setup and MTF context for each historical closed bar.
- Structure Event IDs and swing IDs are deterministic from event/swing time, direction, owner and protected swing; displacement, FVG, OB and rejection IDs use stable time-based IDs.
- MSS requires a close break plus linked displacement and linked liquidity sweep.
- FVG causal status is based on a valid displacement; a BOS/MSS is not required for the three-candle imbalance itself. iFVG changes polarity after a close through the opposite boundary.
- Added replay MTF diagnostics output (`ICT_Assistant_Canonical_MTF_Diag.csv`) behind explicit inputs.
- Updated the structure ledger validator to the actual 11-column canonical schema.
- Added `tools/Compare-ReplayLedgers.ps1` and `tools/Validate-MTF-Hierarchy.ps1` plus structure/MTF fixtures.

### Verification

- Structure fixture validator: PASSED.
- Replay comparison self-test: PASSED.
- MetaEditor fresh build after hardening: `0 errors, 0 warnings`.
- Latest canonical/package/mirror SHA256: `F96AA7F81DF3A8A36D2339A1C1A1A94641B3AA0FE975BBB1FA399F73913E34A1`.
- Latest artifact: `2026-09-15 23:06:40`.
- HTF pivot confirmation is now separated from break evaluation: the latest completed as-of HTF bar is the break bar, while pivot confirmation remains delayed by `InpSwingRight`.
- Historical rebuild evidence is now written to `ICT_Assistant_Canonical_ReplayLedger.csv` when `InpWriteReplayDiagnostics=true`; live events remain isolated in the live ledger.
- Static fixture checks passed: MTF hierarchy fixture and replay-ledger self-comparison.

### Still not claimable without live MT5 evidence

- Actual XAUUSD history replay versus an independent incremental run.
- Restart determinism and immutable-event comparison using the broker history.
- Runtime MTF diagnostics with `InpWriteReplayDiagnostics=true` on live XAUUSD history.
- Independent full-history versus incremental replay comparison using the generated replay ledger.
- Proof that M1/M2 conflicts block READY while H4 Bias remains unchanged on actual mixed-timeframe cases.

## Batch 7: Explain hover actually renders (2026-09-16)

### Requirement

Hovering any drawn object must show a multi-line Persian panel: what it is, why it formed, what validates it, what makes it fake/invalid, and how to verify it manually. The prior 64-bit-identifier fix made the registry lookup resolve, but the panel still showed nothing usable.

### Two additional root causes found and fixed

- **Single-line control for multi-line text.** `RenderExplainPanel()` joined every explanation line with `\n` into one `OBJ_EDIT`. `OBJ_EDIT` is single-line in MT5, so all lines after the first were dropped and the per-line color coding (valid/fake/invalid/verify) was lost. Fixed by rendering one native `OBJ_EDIT` per row via a new `ExplainEditRow()` helper: tiled with no gaps, `ALIGN_RIGHT`, `READONLY`, `BGCOLOR`=`BORDER_COLOR`=black so no seams show, and each row keeps its own `OBJPROP_COLOR` from `g_expLineColors`. `g_expPanelRows` now equals the true row count so the clear path deletes every row. This is the same native right-aligned edit control recorded in the documentation as validated for raw Persian; only the one-vs-many-lines usage changed.
- **Hit-test coordinate drift.** `HitTestExplainObject()` used hand-rolled `PixelXFromTime`/`PixelYFromPrice`, which ignored the chart's vertical scale padding, horizontal shift, and price-axis width. The resulting mouse→object mapping was systematically off (for `OBJ_HLINE` the Y error commonly exceeded the acceptance radius), so hover resolved to nothing. Fixed by converting with MT5's exact `ChartTimePriceToXY` through new helpers `ExplainTimePriceToXY()` and `ExplainVisibleTime()`, covering `OBJ_HLINE`/`OBJ_RECTANGLE`/`OBJ_TREND`/`OBJ_TEXT`; rectangle interiors return distance 0 so zones win over passing lines; minimum tolerance clamped to 4px. The manual pixel helpers were removed.
- `InpExplainRenderMode` (previously dead) is wired into the render path; default `3` (raw passthrough) is correct for the native edit control, and `2` (manual shaping) remains a no-rebuild fallback if Persian ever renders detached.

### Build evidence (independently verified, not just script output)

- Fresh MetaEditor log: `Result: 0 errors, 0 warnings, 6295 ms elapsed` (distinct from the prior 3930 ms build).
- SHA256 (canonical/package/mirror all match): `3ED6B6F95D853F045766428BA3CFCDFFEB645B0F1560A19F9CAEE0CC50F3B282`.
- Artifact `ICT_Assistant_Canonical_v0_1.ex5` timestamp `2026-09-16 01:43:35`, newer than the source (`01:42:40`); size grew 169,654 → 178,044 bytes.
- Only `01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5` was edited; package and mirror were produced by the sync tool. No files deleted.

### Open gates (still not claimable)

- **MT5 visual confirmation:** remove and re-add the indicator, hover each object family (liquidity line, FVG/OB, BOS/CHoCH/MSS event, sweep, session, MTF level, setup) and screenshot that the multi-line Persian panel renders readably. Until then this is IMPLEMENTED, visual check PENDING.
- **Runtime CSV evidence CORRECTION (2026-09-16):** the earlier "Common\Files is empty" claim was wrong — it checked a per-terminal path (`Terminal\<ID>\Common`). `FILE_COMMON` writes to the SHARED `C:\Users\Khaleq\AppData\Roaming\MetaQuotes\Terminal\Common\Files`, where the CSVs do exist: `ICT_Assistant_Canonical_ReplayLedger.csv` (99 events), `ICT_Assistant_Canonical_MTF_Diag.csv` (600 rows), `ICT_Assistant_Canonical_Explain.csv` (36 KB, grew after the 01:50 reload — the reloaded instance is writing). These were produced by an OLDER build, so they are real evidence of past behavior but must be regenerated against the current build for gates 1/2.

## Batch 8: H4 Bias unified to one canonical source + validators run on real data (2026-09-16)

### Requirement

"Logic must be right first." The replay diagnostics showed contradictory rows: `BiasOwner=BULLISH` together with `ReadyState=WAITING_H4_BIAS`.

### Root cause (real logic defect)

Three consumers read "H4 Bias" from two different computations:

- `AnalyzeMTFContext` measured lower-TF conflict against `g_mtfContext[0].externalDirection` (soft HH/HL swing read).
- `UpdateSetup` gated on `g_htfBias` (BOS/CHoCH break-event H4, no-repaint) — `WAITING_H4_BIAS` fires when `g_htfBias==DIR_NONE`.
- `PersistReplayDiagnostics` wrote `BiasOwner` from `g_mtfContext[0].externalDirection`.

So the diagnostic could report a BULLISH owner while the setup engine, using a different H4 value, was still waiting for bias.

### Fix (canonical only)

- Lock the canonical Bias owner to `g_htfBias` everywhere: `AnalyzeMTFContext` (`bias` variable), the `BiasOwner` column AND the H4 segment of `MTFChain` in `PersistReplayDiagnostics`, the dashboard H4 column (`mtfdirs`), and the H4 hover explanation (`ExplainMTFLevel`). `g_mtfContext[0].externalDirection` is retained only as context and for the protected dealing range.
- `IdToStr` rule cleanup: removed the last four `(int)` casts on 64-bit registry IDs in visible text/tooltips (FVG/OB in `ExplainSetup` and `ICTv13_SETUP_TXT`; `sweptByEventId` in the liquidity tooltip) → `IdToStr(long)` with `%s`.
- `tools/Validate-MTF-Hierarchy.ps1`: the writer emits a leading header row when the file starts empty, but the validator assumed headerless and would count the header literal as an invalid owner. Added `-notmatch '^BarTime;BiasOwner;'` so both headerless and header-bearing files validate. Re-ran on the existing data: still PASSED (no regression).

### Validation executed (real runtime data)

- `Validate-MTF-Hierarchy.ps1` on the real `MTF_Diag.csv`: 600 rows, Missing chains 0, Invalid H4 owners 0, Invalid bar times 0, **READY during conflict 0**, **Lower-timeframe opposition without conflict 0** → PASSED. Runtime evidence for the MTF lock: across 552 conflict rows the bias owner stayed BULLISH and only READY was blocked ("lower timeframe cannot change bias (READY blocked)").
- `Validate-CanonicalEventLedger.ps1` on the real `ReplayLedger.csv`: 99 events, 0 duplicate/invalid IDs, 0 missing type/direction, 0 non-positive confirmation shifts, 0 invalid/non-monotonic times → PASSED.

### Build evidence (independently verified)

- Fresh MetaEditor log: `Result: 0 errors, 0 warnings`.
- SHA256 (canonical/package/mirror all match): `FA60C213782B41E0F4E5C777BA856D7BF0EEC332059A9E4111360A30CB7248E8`.
- Artifact `.ex5` timestamp `2026-09-16 01:58:50`, newer than source `01:56:52`. MetaEditor was open (PID 24256); the sync script verified freshness rather than trusting exit code.
- Only the canonical source and the validator tool were edited; package/mirror produced by sync. No files deleted.

### Open gates (unchanged, require live MT5)

- Gates 1 (Full-vs-Incremental) and 2 (Restart determinism / immutability): need TWO independent replay runs on the NEW build. The CSVs above are from an older build; comparing a file to itself is not proof.
- Gate 3 (broker offset + historical DST): NY/US DST is per-bar correct in code; the single-value broker GMT offset detection is a documented, data-dependent limitation — must not be guessed.
- Gate 4 (MTF lock): logic verified by inspection AND validator PASSED on real (old-build) data; must be re-confirmed on a fresh replay produced by this build.
- Gate 5 (visual): remove/re-add the indicator, hover each object family, screenshot the multi-line Persian panel and hover-explain.

## Batch 9: Persian bidi fix proven necessary by chart screenshot (2026-09-16)

### Evidence (chart screenshot)

The hover panel now renders multi-line, but MIXED lines (Persian + digits/English/`|`) were misordered/garbled, while pure-Persian fragments ("ثبت شد", "وضعیت") rendered correctly. Conclusion: the `OBJ_EDIT` control performs bidi+shaping but uses an LTR base paragraph, so only mixed-direction lines break.

### Fix (canonical only)

- `RenderLine` mode 3 (default) now wraps any line containing Persian in an RTL embedding (`U+202B` RLE … `U+202C` PDF) so the entire line, including its numbers and embedded tokens, is laid out right-to-left. Pure-Latin lines (titles, ids) are left untouched. New helper `HasPersianText`.
- Modes 0/1/2 retained as manual fallbacks; input comment updated.

### Build evidence

- Fresh MetaEditor log: `Result: 0 errors, 0 warnings`.
- SHA256 (canonical/package/mirror): `790EB884105661DDBCB41975DA7A28D359AD4C40C01CDACA7A8613B51F4E6E6C`.
- Artifact `.ex5` timestamp `2026-09-16 02:10:12`; mirror updated by sync.

### Still pending (requires live MT5)

- Visual re-confirmation: reload the indicator and screenshot the hover panel. If mode 3 still mis-renders, set `InpExplainRenderMode=1` or `2` and re-screenshot; report which mode is correct so the default can be pinned.

## Batch 10: Phase 7 — scope lock and documentation honesty (2026-09-16)

### Requirement

Documentation rule 15: no document, README or Explain string may name a capability as present or as a checked gate when the code does not implement it. The full audit (`07_DOCUMENTATION/AUDIT_ICT_SMC_MMM.md`) found six such claims. This batch fixes only scope and wording. No calculation logic was touched.

### Scope lock (decided in this session)

In scope: ICT + SMC + MMM. Out of scope and now recorded as deliberately excluded: Wyckoff, classic Supply & Demand, Auction Market Theory / Market Profile, Volume Profile, Order Flow / Footprint / Delta, RTM, Al Brooks Price Action.

Order Flow / Footprint was excluded on a platform constraint, not a preference: the official MT5 documentation states that for the Forex market `Volumes` is the number of price changes rather than real volume, so a real Delta cannot be derived from native MT5 forex/CFD data.

### Evidence that the other seven families were never in the repository

A single recursive search over the whole repository for `wyckoff|volume profile|point of control|vpoc|value area|order flow|footprint|delta|al brooks|read the market|market profile|tpo|initial balance|composite|upthrust|selling climax|measured move|vwap|supply and demand|auction` returned exactly one file: `07_DOCUMENTATION/RESEARCH_FINDINGS.md` (a terminology cross-check link). `02_SHARED_ENGINES/`, `03_ICT_MODULES/` and `05_TESTS_AND_VALIDATION/behavior/` were all empty.

### What was corrected

- `08_FINAL_PACKAGE/ICT_Assistant_Canonical_v0_1/README.md`: removed the claim that `REVERSAL_CONFIRMED` is available; replaced the invented setup-gate chain ("Sweep -> MSS -> Displacement -> aligned FVG -> OB") with the eight gates the code actually evaluates; corrected `READY_ON_CLOSED_BAR` to `READY`; added a Scope section and a Known-gaps section that lists every recorded defect.
- `07_DOCUMENTATION/CANONICAL_ARCHITECTURE.md`: added an `Implementation status` table with 17 claims and their real state, headed explicitly with "THIS DOCUMENT DESCRIBES THE TARGET, NOT THE CURRENT BUILD"; flagged the `REVERSAL_CONFIRMED` rule inline as not implemented.
- `07_DOCUMENTATION/RESEARCH_FINDINGS.md`: added three status tables (concept groups, the eight "must show" requirements, the DeMark/HalfTrend/Divergence promises) and confirmed the four adopted MQL5 timing rules that genuinely are implemented.
- `01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5` (text only): `ExplainSetup` no longer claims Sweep/MSS/Displacement are READY gates or that an SL breach invalidates the setup; it now lists the eight real gates, states the known limitation explicitly, and documents every status code. Version identity unified: `#property version "1.00"` and the dashboard title `"<symbol> — ICT Assistant core v0.1"`.

### Why the version number is 1.00 and not 0.10

MQL5 requires `xxx.yyy` and rejects a zero major. Both `"0.10"` and `"0.100"` were rejected with `compiler warning 68`; `"1.00"` compiled clean. The package slug stays `ICT_Assistant_Canonical_v0_1`; the relationship is documented in the source header and in the technical documentation.

### Build evidence (independently verified)

- Fresh MetaEditor log: `Result: 0 errors, 0 warnings, 6602 ms elapsed`.
- All three `.mq5` copies (canonical / package / mirror): identical SHA256 `065D8CCAD96D68F0E9029361DAABDB075F0A90709E56AAB8EDF4D847814735DB`, size `168692` bytes, timestamp `12:36:34`.
- `.ex5` timestamp `2026-09-16 12:37:00`, size `180438` bytes, i.e. 26 seconds newer than the source, so the compile really ran.
- The sync script failed the two earlier attempts (1 warning) instead of reporting a false success. That guard behaved correctly.

### Audit self-correction

One audit claim was wrong and has been withdrawn: it said `ExplainLiquidity` describes an `INVALID` state that never occurs. The text only describes FRESH/SWEPT; the defect is purely the dead branch in the logic. One new defect was added meanwhile: registry caps drop the oldest entries and the redraw rebuilds only from the registries, so old objects silently disappear from the chart, which violates requirement 8 of `RESEARCH_FINDINGS.md` (frozen historical signals must not disappear).

### Still open

- Phases 12 to 15 are not started; phases 7, 8, 9, 10 and 11 are done (see the technical documentation (phases 7-11)). Phase 12 (completing SMC/MMM coverage: FVG Implied/Micro, Mitigation Block, Trendline and Range liquidity, OB Extreme, Core/Standalone split, IPDA reference levels, POI registry, confluence scoring, Entry Model selection, Internal/External split and trend age) is the highest-value next step. The phase 8 numbers still needing a reload are listed in phase 8 notes, and the phase 10/11 runtime values in the technical documentation.

## Phase 11 execution (2026-09-16) - confirmed reversal gate and Smart Money Reversal

The reversal gate now exists as code instead of a dead enum state. `SwingById()` turns the previously write-only `g_htfProtectedHighId`/`g_htfProtectedLowId` into a real price, and `UpdateReversalEngine()` decides with the closed higher-timeframe close whether the protected external level was passed. One ordering detail was the whole risk: `EvaluateStructureBreak` can flip the owner bias and replace the protected swing inside the same bar, so the gate is measured against a snapshot taken **before** that evaluation. The break is published as the new `EVT_EXTERNAL_BREAK` event (appended at the end of `ENUM_EVENT_TYPE` so existing numeric values and stable event ids do not move). `EXH_REVERSAL_CONFIRMED` now has exactly one producer, inside a branch gated by `reversalFresh`.

Smart Money Reversal (#70) is implemented as four counted pieces of evidence (opposing liquidity sweep inside a configurable higher-timeframe window, chained displacement in the reversal direction, an aligned causal FVG or valid order block, and lower-timeframe/internal context agreement) with a configurable threshold. Web search returned nothing in this session, so this is recorded as the project's own explicit operational definition, not as a quotation of a third party's private rule.

- #8/#71: the protected high/low price is now consumed; both ids are read, not just written.
- #10: proven structurally - the whole file contains exactly one assignment to `g_htfBias` (its declaration), and the `UpdateExhaustion` body contains none. The verifier checks both as independent assertions.
- Verified offline: `tools/Validate-ReversalGate.ps1` -> `PASS=24 FAIL=0`, covering 8 correct gate rows, 9 threshold rows, a deliberately wrong fixture in which all 4 rows must be rejected, and 6 source-level invariants.
- Build: `0 errors, 0 warnings`, identical SHA256 across all three `.mq5` copies, `.ex5` newer than the source.
- Not yet shown at runtime: `ICT_Assistant_Canonical_Reversal_Diag.csv`, the dashboard `Reversal:` row, the `ICTv13_REVERSAL_GATE`/`_CONFIRMED` chart objects, and a real confirmed reversal on the symbol. All four need one chart reload.
- Persian rendering on the chart was confirmed correct on 2026-09-16. Rendering is therefore closed; only the correctness of the educational content is open. Documentation rule 13 forbids touching the renderer without a new screenshot proving breakage.
- The dashboard still clips long rows and its background box is a fixed 380x560 (raised in phase 9 to fit two new rows; phase 14 still owns row-level clipping).

## Phase 9 execution (2026-09-16) - time base, dead inputs, broker offset

All six dead inputs are wired: `InpBrokerToNY_HourOffset` (fallback + reference), `InpMTF` (internal-structure timeframe), and the six session window hours plus 14 new per-window overrides appended at the END of the input list so existing saved parameters do not shift.

- #55: `RefreshBrokerOffset()` re-detects the broker GMT offset on every closed bar, keeps it in seconds (30/45-minute brokers are now exact), logs the change, and purges session liquidity created under the old offset so two contradictory sets cannot coexist.
- #56: `NY_IsDST_UTC()` decides DST from UTC bounds (07:00 UTC on the 2nd Sunday of March, 06:00 UTC on the 1st Sunday of November) instead of comparing day numbers in the wrong time frame.
- #52: `InpDrawSilverBullet` now draws three real boxes (`ICTv13_SESS_SB1/SB2/SB3`) with hover explanations.
- #50/#51: session detection, session ranges, box drawing and the Explain text all read the same inputs through `InNYWindow()`, which supports windows that cross midnight.

### Build evidence (independently verified)

- `0 errors, 0 warnings`; SHA256 of all three `.mq5` copies `7AD5E4220E212932514B2D084F1B60C291BB53FFC11807C1A12DD9D89E3927B0` (197552 bytes, 15:20:17); `.ex5` written 19 seconds later (15:20:36), so the compile really ran. An intermediate build of the same phase carried `BF0011023A990572...`; the only difference is a per-bucket cache for the InpMTF internal direction.
- `tools/Validate-TimeBase.ps1` (offline mirror of the MQL5 rules): 0 mismatches for 2024-2028 transition dates, exact boundary instants (06:59:59 EST / 07:00:00 EDT, 05:59:59 EDT / 06:00:00 EST), and a report of the windows in server time. It also quantifies what the old rule got wrong: 721 minutes at the March transition and 360 minutes at the November transition.
- Live-data cross-check: `ICT_Assistant_Canonical_Explain.csv` registers the Asian session low at server 00:00 and the London session high at server 06:00, matching NY 20:00 and NY 02:00 with the broker GMT+0 offset that the terminal Journal reports.

### Still open for phase 9

- The new dashboard rows (`clock` with the detected offset, `Internal <TF>`), the Silver Bullet boxes and the new Journal line have no runtime evidence yet; they need one chart reload.
- `InpMTF` is deliberately display/explain only: phase 9 added no new READY-blocking gate.
- Historical analysis still uses the current offset; a real historical offset table is phase 15 work.

## Phase 10 execution (2026-09-16) - location and trade model

Location and the setup model now read from one real impulse leg instead of two unrelated pivot prices.

- #43: `UpdateDealingLeg()` builds confirmed H4 pivots, filters them to an alternating sequence (two highs or two lows in a row collapse to the more extreme one) and takes the last two as the real leg. Leg direction comes from the closing pivot type (`endHigh = BULL`), so the dealing range, EQ and both OTE bands are all derived from the same two anchors. A leg smaller than `InpMinLegATR x ATR` is rejected with an explicit reason.
- #46: OTE is now 62/79 percent of that leg (with the 70.5 percent golden level computed, drawn and explained); READY additionally requires the leg direction to equal the bias owner (`WAITING_LEG_DIRECTION`). The leg itself is drawn as `ICTv13_LOCATION_LEG` so a manual fib can be laid on the exact same anchors.
- #45: `g_analysisClose` is the single price source for the setup engine, the dashboard row and the Explain text; `SYMBOL_BID` no longer feeds the Location line, and premium/discount is measured against the leg EQ.
- #48: DOL selection is a scored multi-criteria decision (External 30, HTF 10, level type 6-15, internal alignment 10, ATR-normalised proximity up to 25) with candidates closer than `InpDOL_MinRoomATR` rejected before scoring, because they cannot produce an honest R:R. `sweepStateOk` is now read from the liquidity state instead of being hardcoded true, and the numeric breakdown travels to the dashboard and the Explain panel.
- #66: the READY path now requires a proven ICT cycle (last same-direction, non-CHoCH event carrying both a sweep and a displacement) inside `InpChainLookbackBars`; SL uses `max(ATR x InpSL_MinATR, InpSL_MinPoints, SYMBOL_TRADE_STOPS_LEVEL)` and can never be zero (`WAITING_SL_INVALID`); TP3 stays `max/min(entry +/- risk x 3, DOL)` but the displayed R:R is recomputed from the price distances and gated by `InpMinRR`; the entry zone is searched on the MTF SETUP timeframe (M5) first and `zoneSource` records which zone was used.

### Build evidence (independently verified)

- `0 errors, 0 warnings`; SHA256 of all three `.mq5` copies `9289B13AE60C0C9A7C6652FA0942BD3387EE31342242FE66256585FA40258F06` (226597 bytes, 17:42:25); `.ex5` written at 17:44:11, 106 seconds later, so the compile really ran.
- `tools/Validate-DealingLeg.ps1` recomputes range/EQ/OTE/golden/sizeATR/risk/R:R from the raw pivot prices in PowerShell and compares them with the values the indicator wrote. Self-tested: a consistent fixture passes all 20 checks, a deliberately wrong fixture fails 6 (bad EQ, wrong side label, wrong golden, hardcoded R:R 3 vs 4.6667, golden outside the band, missing sweep id).
- Before-state from the previous build's own `ICT_Assistant_Canonical_Explain.csv` (17:30): EQ 186.48 over 186.74/186.23 with OTE bull 186.335-186.422 and OTE bear 186.543-186.630. The arithmetic of the old formula checks out by hand, which is exactly why the defect was the *basis* (two unrelated last pivots) rather than the arithmetic.
- Web search returned no results in this turn, so no claim rests on it. The official MQL5 documentation was read for `SYMBOL_TRADE_STOPS_LEVEL` (minimal indention in points from the current close price to place stop orders) and the project's own recorded OTE research was used for 62/79 and 70.5.

### Still open for phase 10

- All runtime numbers (leg anchors, OTE, SL, R:R), the new dashboard rows (`Leg`, `DOL`, `R:R real`), the new chart lines (`ICTv13_LOCATION_LEG`, `ICTv13_LOCATION_GOLDEN`, `ICTv13_DOL_LINE`) and the new `ICT_Assistant_Canonical_Leg_Diag.csv` need one chart reload.
- Breaching the SL still does not register an invalidation event, and position sizing is out of scope for this indicator.

## Phase 12 — SMC / MMM coverage completeness (#3 #9 #19 #20 #30 #31 #35 #36 #47 #65 #67 #68)

Scope: detection and scoring layer only. Persian rendering, HTF bias ownership, the phase 11 reversal gate, standard FVG/OB handling and the time architecture were not touched (rule 13).

- #30 Implied FVG: the gap is built from the **bodies** (close of candle 1 vs open of candle 3) and stored as `FVGK_IMPLIED` with its own id space (`kind=3` in `StableZoneId`), so it can never be confused with a standard gap.
- #31 Micro FVG: `DetectMicroFVG()` scans `InpMicroTF` (default M1) for a three-candle gap that lies **entirely inside** the displacement candle. It is created only for a **chained** displacement, and the entry-zone search still prefers STANDARD/IMPLIED gaps over micro ones.
- #35 OB Extreme: `MarkExtremeOrderBlocks()` labels the closest zone to the leg extreme (leg high -> supply, leg low -> demand) within `InpOB_ExtremeATR x ATR` and the POI score adds 6 for it.
- #36 Core vs Standalone: `DetectOB` moved out of the structure-event branch and is now gated only on `dispId != -1`, so a zone with displacement but no share in a structure break really becomes `OBK_STANDALONE` / `isStandalone=true`. The previously dead `!isStandalone` filter now works and the setup search prefers Core/Extreme.
- #19 Trendline Liquidity: `TrendlineLiqObj` registry with two confirmed anchors, a real slope, touch counting and invalidation on a **closed** bar beyond the line by `InpTrendlineBreakATR x ATR`. Because the line is a function of time, the level is always evaluated with `TrendlinePriceAt()`, never as a frozen number.
- #20 Range Liquidity: `UpdateRangeLiquidity()` gates on `InpRangeMaxATR x ATR` height and `InpRangeMinTouches` per boundary; a rejected range reports the actual numbers (`hiT`, `loT`, `height`) instead of a generic message. The POI derived from a boundary now carries a `0.10 x ATR` band, because a zero-height zone is dropped by the render gate while `FindBestPOI` would still return it as the best opportunity.
- #65 IPDA: 20/40/60-day old high/low from **closed** daily candles; a horizon with less data than it needs is **not** registered and the shortage is reported in the dashboard, so no approximate value is ever written.
- #47 POI: one registry (`POIObj`) fed by causal FVGs, order blocks (valid/breaker/mitigation), fresh rejection blocks, valid trendlines and range boundaries, each with type, direction, bounds, time, owning timeframe, validity and a **decomposed numeric score** (base 20, kind bonus 3-12, bias alignment 10, extreme 6, age decay 0-10).
- #67 Entry model: `SelectEntryModel()` implements four models with separate numeric preconditions and an automatic priority (ICT2022 -> BOS/FVG/OB -> Sweep Entry -> OTE); `InpPreferredEntryModel` can force one, and a forced model that fails its conditions yields an explicit `WAITING_ENTRY_MODEL`.
- #68 Setup quality: ten **variable** criteria are counted (full MSS, causal FVG, valid OB, Core/Extreme OB, leg extreme, SETUP zone, structural POI, price inside OTE, continuing trend phase, R:R with margin) and a setup below `InpMinQualityScore` is rejected with `WAITING_QUALITY_LOW`.
- #3 / #9: the dashboard's `Internal` row used to be the chart timeframe trend. `g_htfInternalDir` is now the internal structure of the **owning** timeframe, and `UpdateTrendPhase()` reports trend age and phase with a textual reason.

### Evidence hygiene added in this phase

- `ICT_Assistant_Canonical_Phase12_Diag.csv` (29 columns) is the numeric witness for this layer: trendline count/touches/invalidated, range decision and rejection numbers, IPDA registered count, implied and micro gap counts, POI count and best POI score, entry model with its reason, quality score, trend age/phase and internal direction.
- `ICT_Assistant_Canonical_Load.csv` is the load stamp (`BuildStamp`, symbol, chart timeframe, HTF, session timeframe, broker offset, terminal build). It exists because "which build is running?" had to be inferred by comparing file timestamps, and that inference once caused stale rows to be compared against fresh ones.
- Diagnostic ledgers now self-repair their header: if the first key of the first row is not the expected column name, the file is recreated with a header, and every row carries a `BuildStamp`.

### Build evidence (independently verified)

- `0 errors, 0 warnings` (MetaEditor log: `10254 ms elapsed, cpu='X64 Regular'`); source SHA256 identical in the repo and in the MT5 folder: `0A2EA6FE604E08F51F8FECC05759F685959F4F088A55DE786DD02B35BF47DA23` (317657 bytes); `.ex5` written at `19:00:19` (292172 bytes, SHA256 `BC753B6A10B2BBBCA87C02B95A0DB5AF4B21CED682B2AF3B405DBFDD18F93283`), later than the source, so the compile really ran.
- `tools/Validate-Phase12.ps1` re-implements every new rule in PowerShell from the rule text alone and compares it against fixtures: `PASS=77 FAIL=0`. It also proves source invariants (append-only enums, owning-timeframe internal structure, micro gaps only from chained displacements, the 9-parameter `AppendFVG` signature, the range-POI band, the self-healing headers, the build stamp, both ledger call sites) and guards the bidi-digit percent lookalike (U+066A) that broke 22 format strings while writing this phase.
- No regression in earlier phases: `Validate-ReversalGate.ps1` `PASS=24 FAIL=0`, `Validate-TimeBase.ps1` `0 mismatches`.

### Still open for phase 12

- Every runtime number needs one chart reload. Verified from the terminal journal that the last attach was `18:34:11` while this build is `19:00:19`, so no chart has run it yet. The `18:45` `Explain.csv` snapshot contains no phase-12 object at all, even though the same chart carried 9 independent swing highs and 8 swing lows and `BuildTrendlines` needs only two of each — independent confirmation that the snapshot predates this layer.
- The two `GuardId=0` rows in `Reversal_Diag.csv` were stale rows from an older build in a headerless file, not a logic defect; that is now fixed by the self-healing header and the build stamp rather than by changing the reversal logic.

---

## Phase 13 — Stability & performance (completed 2026-09-16)

Full write-up: the technical documentation.

### What changed

- **#7 duplicate event on HTF**: `UpdateHTFStructure` runs on every closed chart bar, so after a swing was marked `broken` the next call inside the same HTF bar compared the same close against an *older* unbroken swing and emitted a second BOS/CHoCH on one H4 candle. A bucket guard (`htfRates[0].time == g_lastHtfEvalBarTime`) now returns early, placed **before** the pivot push and before the structure evaluation, with `g_htfEvalRuns` / `g_htfEvalSkips` as counters.
- **#11 unbounded registries**: `g_events[]` and `g_displacements[]` were the only registries without a cap. `AppendStructureEvent()` is now the single push path with `InpMaxEvents=400`, and `DetectDisplacementCandidate` caps `g_displacements` at `InpMaxDisplacements=400`; policy is FIFO (oldest dropped).
- **A bug the cap itself would have created**: `AnalyzeClosedBar` detected "a new event was created" with `ArraySize(g_events) > beforeEvents`. With a full registry the size stops growing (one in, one out), so the condition would stay false and the fresh event would never be linked to its displacement/sweep. The test now uses the monotonic `g_eventsAdded` counter.
- **#12 dead code**: `NewId()` and `g_nextId` removed; every event id already came from `StableEventId` (grep proof: zero references).
- **Performance**: the event ledger is indexed in memory once (`EnsureLedgerIndex` + `LedgerIndexAdd`) instead of re-reading the whole file per event; all session windows share one M15 buffer (`EnsureSessionBars`) instead of ~90 `Copy*` calls per bar; `DetectEQ_FromSwings` is memoized on a swing-set fingerprint; seven draw calls are suppressed during the history rebuild; the rebuild now ends with `RedrawChartObjects()`; the unused indicator buffer (`g_bufDummy` + `SetIndexBuffer`) is gone and `#property indicator_buffers 0` compiles clean.
- The hardcoded rejection cap (50) became the real input `InpMaxRejections` with the same default.

### Why the FIFO policy cannot change a live decision

Every derived state is read from the *end* of the arrays: bias and protected level (latest HTF event), setup chain (`InpChainLookbackBars`), trend age/phase (latest aligned event), displacement (current bar). Dropping the oldest rows therefore bounds memory without moving any decision; historical events remain available in the CSV ledger, not in RAM.

### Build evidence (independently verified)

- `0 errors, 0 warnings` (`9572 ms elapsed, cpu='X64 Regular'`); source SHA256 identical in repo, MT5 mirror and final package: `61E397FB6353A05FD964A55119336C9D075A9E1DB658C4A4B0B23CD810B1CE7A` (331302 bytes); `.ex5` 296122 bytes written `19:34:42`, newer than the source.
- `tools/Validate-Phase13.ps1` → `PASS=55 FAIL=0`, in three families: the cadence rule (fixture scenario A: one H4 candle with three chart closes over two protected highs → **2 events without the guard, 1 with it**; scenario B proves the guard does not eat the next H4 candle's legitimate event; a deliberately wrong fixture is caught 3/3), the cap/drop arithmetic (6 rows including `cap=0` and `cap=1`, plus "the survivor is always the newest"), and EQ idempotence (5 scenarios, second run registers nothing new). 15 source-level proofs run alongside them.
- No regression: `Validate-TimeBase` `0 mismatches`, `Validate-ReversalGate` `PASS=24 FAIL=0`, `Validate-Phase12` `PASS=77 FAIL=0`, `Validate-DealingLeg` now fully green.

### Side finding: the phase-10 verifier was inherently red

`tools/Validate-DealingLeg.ps1` failed 7 checks on live data for tool-side reasons only: it compared the direction against `BULL`/`BEAR` while the CSV writer emits `BULLISH`/`BEARISH` through `DirToStr` (so no direction branch ever ran), its tolerance (`range*1e-7`) was far below the three-decimal rounding of the written prices, the `sizeATR` threshold was a fixed 0.01, and the 62/79% check only had the bullish formula and always reported ~41% deviation on a bear leg. All four were corrected (two-form direction match, tolerance derived from the real write precision, analytic `sizeATR` tolerance, per-direction formula); the candle logic was not touched. Same snapshot: `19 pass / 0 mismatch` with real deviation `far=0.0252% · near=0.0330%`.

### Still open for phase 13

- **No runtime witness yet.** `ICT_Assistant_Canonical_Load.csv` shows `BuildStamp=2026.09.16 19:25:02`, and the MetaEditor compile journal gives the build timeline `19:00:19` (phase 12) → `19:27:49` → `19:28:54` → `19:34:42`. So the attached instance loaded the *phase-12* artifact (which prints nothing at attach, which is why the expert log has no line after `18:35`). One chart reload is required; the Journal must then show the `ICT PHASE13 | rebuild …` line, and `Load.csv` must show a stamp `> 19:34:42`.
- ~~**Frozen display history vs registry caps**~~ ✅ closed in phase 14 (reconciling redraw instead of blanket delete + rebuild). See the Phase 14 section below.
- `DetectEQ_FromSwings` is still O(n²) in the worst case (memoized, not re-derived), and `AnalyzeMTFContext` still copies 5-6 timeframes per bar; both were left untouched to keep behaviour identical.

---

## Phase 14 - Dashboard & Explain (reconciling redraw + text health)

Status: IMPLEMENTED + BUILD VERIFIED + TOOL VERIFIED + SOURCE-PROVEN (not chart-VALIDATED)

### The two defects that were actually found (not assumed)

1. **Drawn history vanished when the display caps filled up.** `RedrawChartObjects()` wiped the whole
   layer with fourteen `ObjectsDeleteAll(0,"ICTv13_...")` calls and rebuilt it from the registries, and the
   display caps (`InpMaxDrawnZones=14`, `InpMaxDrawnLevels=30`) decided what got re-created. Any zone pushed
   out of the visible window disappeared from the chart. That directly violates `RESEARCH_FINDINGS` item 8:
   a closed-bar signal "must not silently move or disappear".
2. **Stale dashboard rows and clipped text.** The panel background was hard-coded at `380x640` with `lh=16`,
   while the maximum reachable row count is 41 rows = 656 px. Eleven conditional rows (`clocknote`, `sb`,
   `asia`, `mtfreason`, `dirline`, `entry`, `sl`, `tp1..tp3`, `rr`) had no removal path, so when their
   condition turned false the old text stayed on the chart - and because the `row` cursor shifted, every
   later row also moved. `sep5` and `sep4` were drawn back to back.

### What changed

| Item | Before | After |
|---|---|---|
| Layer redraw | 14x `ObjectsDeleteAll`, then rebuild | `MarkDrawnLayerObj()` marks every creation path (structural proof: 13 `ObjectCreate` sites in the draw section = 13 `MarkDrawnLayerObj` call sites); `ReconcileChartLayer()` classifies live / delete / frozen |
| Frozen policy | none | Objects pushed out of the display window keep a `FROZEN` style (`InpFrozenColor` + `STYLE_DOT`, tooltip explains why and records the original line style). The registry is bounded at `InpMaxFrozenObjects=300` with FIFO eviction |
| Return from frozen | n/a | If an object re-enters the window it leaves the frozen registry and the draw call restores its real colour/style (`g_frozenRestored`) |
| Disabled layers | blanket wipe made this free | `LayerDisabledForName()` deletes instead of freezing, so switching a layer off leaves no grey ghosts. `IsStaleSessionBoxName()` deletes session boxes whose day-back index is now beyond `InpKillzoneDaysBack` |
| Explicit filters | `continue` only | `MarkHiddenLayerObj()` -> deleted by the reconciler. "Deliberately hidden" stays distinct from "the display cap filled up" |
| Dashboard clipping | hard-coded 380x640 | `DashMeasure()` uses `TextSetFont("Consolas",-size*10,FW_NORMAL)` + `TextGetSize()`; `DashEnd()` sizes the box from the measured widest row and the used row count |
| Long rows | drawn on one line, clipped | Break at the last fitting separator when `InpDashMaxWidth>40`; if it still does not fit the text is **never truncated** - the panel widens and `g_dashOverflow` counts it |
| Stale rows | no removal path | `DashBegin`/`DashRow`/`DashEnd`; any `ICTv13_DASH_*` label not written in this pass is deleted (`g_dashStale`) |
| Duplicate separator | `sep5` + `sep4` | only `sep4` |
| Hover on a frozen object | n/a | `BuildExplanation` inserts a Persian first row explaining that the object is valid history and the grey colour only means "outside the current display window" |
| Panel fallback text | "this is a bug" as the only cause | two explicit causes: id mismatch **or** the reference left the bounded registry (a phase-13 cap), which is not a bug |

Seven new inputs, all appended at the end of the input list (rule 14) so saved chart presets keep their indices:
`InpFrozenHistoryEnabled`, `InpMaxFrozenObjects`, `InpFrozenColor`, `InpDashMaxWidth`, `InpDashLineHeight`,
`InpWritePhase14Diagnostics`, `InpLogPhase14OnRedraw`.

### Build evidence (independently verified)

- `0 errors, 0 warnings`; source SHA256 `8B9CFFB39BCD16C361365C169783FE99BA69624C0FC44D286A4ABE141DF9B614`
  (354390 bytes) identical in the repo and the MT5 mirror; last `.ex5` 315920 bytes written `2026-09-17 00:18:10`,
  newer than the source (`00:09:13`), SHA256 `55B49570F075D1B648B929AD75D77EA628E024626BC6A0B9DFA60117F6E4F0B7`.
- Note on `.ex5` reproducibility: two consecutive compiles of the **same** source produced two different
  `.ex5` files (315680 and 315920 bytes, different hashes) because MetaEditor embeds a timestamp in the binary.
  The meaningful checks are therefore "`.ex5` is newer than the source" plus "the source hash is identical
  across all copies", not a fixed binary hash.
- `tools/Validate-Phase14.ps1` -> `PASS=137 FAIL=0`, in four families: frozen-history FIFO arithmetic
  (7 scenarios covering add/restore/`cap=0`/`cap=1`), long-row wrap (6 rows), stale-row deletion (3 passes),
  auto-sized background (6 rows). Each family also ships a deliberately wrong fixture and the self-test
  asserts the checker rejects it (`caught N of N`). 25 source-level proofs run alongside.
- Honest limit of the wrap fixture: it locks the *break-selection algorithm* under the indicator's own
  documented fallback width model (`ceil(len x size x 0.62) + 2`), because `TextGetSize` cannot be called
  outside MT5. Three invariants independent of the width model are checked as well: no character is lost,
  the cut lands on a separator whenever a separator prefix fits, and a single-row result only happens when
  the whole text fits.
- No regression: `Validate-Phase12` `PASS=77 FAIL=0`, `Validate-Phase13` `PASS=55 FAIL=0`,
  `Validate-ReversalGate` `PASS=24 FAIL=0`, `Validate-TimeBase` `0 mismatches`, `Validate-DealingLeg` green.

### New evidence artefacts

- Journal line on every redraw:
  `ICT PHASE14 | layer objs <n> | drew <n> | frozen <n> (added <n> / restored <n> / evicted <n>) | hidden-deleted <n> | dash rows <n> | dash width <n>`
- `.../Terminal/Common/Files/ICT_Assistant_Canonical_Phase14_Diag.csv` (22 columns: `LayerObjects`,
  `LayerDrawn`, `FrozenLive`, `FrozenAdded`, `FrozenRestored`, `FrozenEvicted`, `HiddenDeleted`,
  `DashRows`, `DashWidth`, `DashHeight`, `DashMaxRowW`, `DashStaleDeleted`, `DashWrappedRows`,
  `DashOverflowRows`, ...). It is written **after** `RenderDashboard()` so the dashboard numbers are the
  current pass, not the previous one.

### Still open after phase 14

- ~~**No runtime witness yet.**~~ (checklist unchanged, still pending a chart reload)
- ~~**HTF structure events are still never drawn.**~~ ✅ **closed in phase 15** — `InpDrawHTFEvents=true`
  draws the last `InpMaxDrawnHTFEvents=8` HTF structure events on the chart.
- The three performance items of phase 13 (`DetectEQ_FromSwings` O(n^2), `AnalyzeMTFContext` copies,
  full `Explain.csv` rewrite per bar) are unchanged.

## Phase 15 - Final validation: historical DST offset + setup lifecycle + HTF events  ✅ implemented (2026-09-18)

```text
Status: IMPLEMENTED + BUILD VERIFIED + TOOL VERIFIED + SOURCE-PROVEN (chart VALIDATION pending reload)
Build:  0 errors, 0 warnings — source SHA256 E212D497…5E96736 (382,692 B), identical in all three copies
        .ex5 343,676 B @ 2026-09-18 05:24:16 · SHA256 F7662D7A…1FEED69
Tools:  Validate-Phase15.ps1 → PASS=36 FAIL=0 (16 rule/source checks + good/bad behavior fixtures)
        Re-run of Phase14 (137) / Phase13 (55) / ReversalGate (24) / TimeBase (0 mismatches): no regressions
```

What phase 15 closed:

1. **Historical broker DST offset** — `ENUM_BROKER_DST_RULE {BDST_AUTO, BDST_US, BDST_EU, BDST_NONE}` +
   `InpUseHistoricalBrokerOffset`. Every historical instant resolves its own offset through the broker's DST
   rule (fixed-point resolution, because the server clock itself depends on the offset). US rule: 2nd Sunday
   of March 07:00 UTC → 1st Sunday of November 06:00 UTC; EU rule: last Sunday of March/October 01:00 UTC.
   `AUTO` infers the family from the current offset (+0..+3 → EU, −4/−5 → US, others → NONE).
2. **Setup lifecycle (#66)** — armed setups are tracked; a **closed** bar beyond SL records INVALIDATION
   (wick is not enough), a TP1 touch records TP1_HIT, invalidation wins when one bar does both, re-arming
   needs a new chain id. Evidence: `ICT_Assistant_Canonical_Phase15_Diag.csv` (Common\Files).
3. **HTF structure events are drawn on the chart** (the open item of phase 14) with an independent cap
   `InpMaxDrawnHTFEvents=8`.
4. **Copyright metadata:** `#property copyright` = "Khaleq Salehi —
   khaleq.sa@gmail.com — +989120143697", `#property link`, Persian description. Metadata only; a follow-up
   build after this change was again `0 errors, 0 warnings` (source SHA256 `6CE73562…ACA3479`, .ex5 @
   2026-09-18 00:22:25).

All 15 phases are now implemented; the remaining gate for phases 10–15 is one chart reload so the
runtime evidence (Phase15_Diag.csv, Journal lines, HTF events) can be recorded.

## Display hygiene patch — invalidated past hidden + hover only with Ctrl  ✅ (2026-09-18)

```text
Build:  0 errors, 0 warnings — source SHA256 B9DA6D8E…5DF0B7 identical in 3 copies · .ex5 @ 2026-09-18 01:16:43
Tools:  Phase14 137/0 (hidden-count check loosened to >=5 to cover the new call sites) · Phase15 36/0 ·
        Phase13 55/0 · ReversalGate 24/0 — no regressions
```

1. **Invalidated past is no longer drawn.** New inputs (appended at the end of the input list):
   `InpHideInvalidatedObjects=true`, `InpSweptKeepBars=6`, `InpExplainOnlyWithCtrl=true`.
   - Liquidity `LSTATE_INVALID` → never drawn; `LSTATE_SWEPT` lines and `SWEEP_*` markers → only the last
     `InpSweptKeepBars` chart bars (0 = none).
   - FVG `mitigated`/`inverted` older than the keep-window → removed via `MarkHiddenLayerObj`.
   - OB `BROKEN`/`INVALID` → removed; Rejection `INVALID` → removed (filter in `DrawZoneLayer` plus a
     defensive early-return inside `DrawRejection`).
   - The numeric history remains fully available in `FVG_Diag.csv` / `Explain.csv`.
2. **Hover no longer blocks the chart.** The explanation panel opens **only while Ctrl is held**, per the
   official MQL5 `OnChartEvent` reference: for `CHARTEVENT_MOUSE_MOVE`, `sparam` carries the modifier-key
   bitmask string and **bit 8 = CTRL**. With Ctrl released the panel closes and hit-testing is skipped, so the
   mouse is completely free for scrolling/dragging. First build attempt failed with
   `TERMINAL_KEYSTATE_LEFT_CTRL` (undeclared — no such MQL5 constant); corrected to the documented bitmask.

## Phases 16-21 — remaining six families added  ✅ (2026-09-18)

```text
Build:  0 errors, 0 warnings — source SHA256 26309436…DF31C7E identical in 3 copies · .ex5 @ 2026-09-18 01:43:32
Tools:  Phase14 137/0 (DashRow cap widened to >=45 for the new rows) · Phase15 36/0 — no regressions
```

The full 10-family list was supplied and adding the six missing families was approved via the
interactive question. The project domain table was reopened accordingly.

| Phase | Family | What is computed | Chart + Persian hover |
|---|---|---|---|
| 16 | Wyckoff | SC/BC climaxes, Spring/Upthrust (wick beyond range edge + close inside — fake/real distinction), low-range Test, phases A–E derived from the event history | `SC/BC/SPRING/UPTHRUST/…` labels + full hover incl. invalidation |
| 17 | Supply & Demand | 1–3 candle base + sharp exit (ATR-normalized), FRESH/TESTED/FLIPPED states with touch counter, FIFO registry | `ICTv13_SD_*` boxes + hover with freshness and flip rule |
| 18 | Al Brooks | Trend/Doji/Signal/Entry bars, follow-through, 3-bar Always-In, H1/H2 pullbacks, 20-bar Failed Breakout | dashboard `Brooks:` row + teaching hover |
| 19 | RTM | Compression (avg range below threshold) and the following expansion, with direction | dashboard `RTM:` row + hover |
| 20-21 | Market/Volume Profile | tick-volume distribution over price rows; POC/VAH/VAL via two-sided expansion from POC to the VA percent; drawing off by default | optional POC/VAH/VAL lines + hover that honestly labels tick-volume as an approximation |

Honest limitation recorded: profiles use **tick-volume** (official MQL5 docs — forex/CFD has no real volume);
real Delta/Footprint stays out of scope. All new logic runs on closed bars only and respects the display-hygiene
filters (invalidated objects are not drawn).

## Full dashboard — registry transparency rows (2026-09-18 03:09)

Request: "داشبورد فول میخوام". Seven read-only rows added to RenderDashboard, all read from the
same registries the engines use (dashboard computes nothing): Events LTF/HTF split, Liquidity type
breakdown (EQH/EQL, BSL/SSL, PD, swing, IPDA), Registry health (swings H/L, displacements,
trendlines, range state), IPDA status, POI registry best-score, ATR/close/bars/build-stamp, and
display hygiene (live objects, frozen count, stale/wrapped dashboard rows).

Behavior changed: no analytical logic touched; read-only display only.
Build: 0 errors, 0 warnings — source SHA256 F6D1BEF2B2234334B3E5B5D4C2FBA47D3385B22462EB312D09B68899E0DF6C4B
identical in repo and MT5 folder · .ex5 381278 bytes · 2026-09-18 03:09:15.
Pending: runtime numbers need one chart reload (Remove -> Refresh -> Add).

## 2026-09-18 05:10 — بازبینی نهایی نمایش (بند ۴‑۰‑۱۹ مستندات فنی)
- سوییچ‌های نمایش جدید: `InpDrawIPDA=true` · `InpDrawTrendlines=true` · `InpDrawBestPOI=true` (کشف دست نخورد؛ فقط رسم)
- هر-تایم‌فریم: `SDObj.tf` اضافه شد و در `DrawFamiliesLayer` با `InpDrawPerTimeframe` فیلتر می‌شود؛ EQ/OTE/Golden تابع `InpDrawSetupBox`
- build: 0 errors, 0 warnings — سورس SHA256 `814AFA65…6AD` یکسان (مخزن + MT5) · .ex5 2026-09-18 05:10:12
- رگرسیون: Validate-Phase14 137/0 · Validate-Phase15 36/0

## 2026-09-18 11:12 — داشبورد COMPACT پیش‌فرض + خطوط غیرفعال حالت ساکن (بند ۴‑۰‑۲۰ مستندات فنی)

- `InpDashCompact=true` (پیش‌فرض): `DashCompactSkip` در `DashRow` فقط ردیف‌های تصمیم ترید را رسم می‌کند (title/htf/mtfdirs/sess/mtfsetup/dol/location/reversal/exhaustion/setup/life/dirline/entry/sl/tp1..tp3/rr + sep* + mtfreason هنگام تضاد + clocknote هنگام هشدار). شمارنده‌های تشخیصی فقط با `InpDashCompact=false` — دادهٔ کامل در CSVها باقی است.
- ردیف `hygiene` در COMPACT نه رسم می‌شود نه محاسبه (حذف پیمایش `ObjectsTotal` در هر کندل).
- `InpDrawDOL` (سوییچ جدید، پیش‌فرض true): خط DOL اکنون خاموش‌شدنی است.
- `DrawReversalLevels`: خط REVERSAL فقط وقتی دروازه armed یا confirmed است رسم می‌شود؛ حالت ساکن بدون خط.
- build: 0 errors, 0 warnings؛ SHA256 سورس 3D9FFA2178CEE6EF… یکسان در مخزن/پکیج/پوشهٔ MT5؛ .ex5 در 2026-09-18 11:12:59؛ رگرسیون Phase14 137/0، Phase15 36/0.

## Phase 22 — دو ایراد گزارش‌شده: «hover توضیح نمی‌دهد» + «بعضی محاسبات غلط است» (2026-09-18 12:21)

### الف) ریشهٔ واقعی «هیچی نمی‌نویسد» (دو علت مستقل)
- **علت الف:** `RedrawChartObjects()` بی هیچ شرطی `g_expHovered=""; ExpClear(); RenderExplainPanel();` را اجرا می‌کرد و `RenderExplainPanel` با `total==0` همهٔ ردیف‌های `ICTv13_EXP_*` را حذف می‌کرد. این تابع یک‌بار در هر **کندل بسته** و یک‌بار در پایان rebuild اجرا می‌شود (دو call site، تأییدشده با grep روی `OnCalculate`)؛ یعنی روی M1 هر دقیقه و بعد از هر rebuild پنل نابود می‌شد.
- **علت ب (علت اصلی نبودن پاسخ روی باکس‌ها):** `ChartTimePriceToXY` برای نقاط بیرون از محدودهٔ دید `false` می‌دهد. شرط قدیمی hit-test می‌خواست **هر دو گوشهٔ** باکس روی صفحه باشند؛ ولی لبهٔ چپ نواحی FVG/OB/S-D روی چارت زوم‌شده بیرون از دید است → هیچ باکسی قابل hover نبود. حالا `ExplainTimeToX` تبدیل را با پهنای واقعی کندل (px/bar از دو کندل دید) ادامه می‌دهد و `ExplainPriceToY` قیمت بیرون‌از‌دید را کلمپ می‌کند.
- اصلاح: پنل فقط وقتی بسته می‌شود که آبجکت زیر موس دیگر وجود نداشته باشد.
- مسیر دوم مستقل: `InpSetObjectTooltips=true` متن کوتاه آموزشی را به‌صورت tooltip چندخطی روی خود آبجکت می‌گذارد (شکل‌دهی دستی + ترتیب بصری).
- مسیر سوم: `InpExplainOnlyWithCtrl` پیش‌فرض `false` شد تا بدون Ctrl هم توضیح بیاید.

### ب) ایرادهای محاسباتی اصلاح‌شده (با مرجع)
| # | مورد | تشخیص | اصلاح |
|---|---|---|---|
| ۱ | پیوت Double Top / Equal Highs | هر دو طرف اکید بود؛ دو سقف دقیقاً مساوی صفر پیوت می‌ساختند (نه BSL، نه EQH، نه سقف محافظت‌شدهٔ H4) | سمتراست مساوی‌پذیر شد (قاعدهٔ `ta.pivothigh` و اسکریپت Swing تردینگ‌ویو) — سه محل |
| ۲ | Value Area پروفایل | فقط یک ردیف مقایسه می‌شد | قاعدهٔ مستند CQG: مقایسهٔ **دو ردیف مجاور**؛ تساوی → هر دو سمت |
| ۳ | حجم پروفایل | حجم کامل هر کندل به همهٔ ردیف‌های پوشش داده می‌شد (دوباره‌شماری و کج‌شدن POC به سمت کندل‌های پرنوسان) | تقسیم حجم کندل بین ردیف‌های پوشش |
| ۴ | دفتر شاهد | چهار ستون شناسه با `(int)` نوشته می‌شد و می‌شکست (نمونهٔ واقعی `-715967644`) | `IdToStr` (۶۴ بیتی) |
| ۵ | آلودگی دفتر بین نمادها | دفتر مشترک، ردیف‌های نماد دیگر (قیمت ۱۷۹٫۱) را قاطی دفتر XAUUSD می‌کرد و ترتیب زمانی را می‌شکست | نام دفتر مقید به نماد + auto-discovery در validator + بررسی یکنوایی درون هر تایم‌فریم |

### ج) آنچه بازبینی شد و درست بود
کشک‌زون‌ها (۲۰:۰۰–۰۰:۰۰ / ۰۲:۰۰–۰۵:۰۰ / ۰۷:۰۰–۱۰:۰۰ نیویورک) · OTE ۶۲/۷۰٫۵/۷۹ و فرمول متقارن دو جهت · FVG استاندارد سه‌کندلی و Implied از بدنه · Sweep = فتیله فراتر + بسته‌شدن پشت سطح · SL با ATR/StopsLevel و R:R واقعی از DOL · قاعدهٔ DST آمریکا تا ثانیه.

### د) شاهد
```text
Build: 0 errors, 0 warnings — SHA256 954EDB610153FA81C03BAD76DB61A39C3BD44F0621211339422DCF045F0BA9C9 (سه کپی یکسان)
.ex5: 2026-09-18 12:20:58 → …\MQL5\Indicators\khaleq\newICT\ICT_Assistant_Canonical_v0_1.ex5
Validate: Phase12 77/0 · Phase13 55/0 · Phase14 150/0 (۱۳ بررسی سطح‌سورس فاز ۲۲ در بخش B12) · Phase15 36/0 · ReversalGate 24/0 · MTF PASSED · TimeBase 0 mismatch · DealingLeg 0 mismatch
Validate-CanonicalEventLedger: فایل قدیمی آلوده FAILED (۷ ردیف خارج از ترتیب، همه از نماد دیگر) — دفتر نمادی جدید بعد از یک reload باید سبز شود
```

### ه) فاز ۲۳ — رندر فارسی روی آبجکت‌های چارت + داشبورد خاموش (2026-09-18 12:41)

| # | مورد | ریشهٔ واقعی (با مرجع) | اصلاح |
|---|---|---|---|
| ۱ | فارسی برعکس/بی‌ریخت دیده می‌شد | مرجع بیرونی: تاپیک ۵۰۴۵۲۲ انجمن MQL5 — از buildهای اخیر، رندرگر آبجکت‌های چارت **bidi ندارد** و RTL را LTR می‌کشد. حالت پیش‌فرض `InpExplainRenderMode=3` بود که به RLE..PDF تکیه می‌کرد؛ روی این buildها بی‌اثر است | پیش‌فرض حالت **۲**: شکل‌دهی حروف روی متن منطقی + تبدیل به ترتیب بصری |
| ۲ | ترتیب کلمه‌ها و علائم نگارشی جابه‌جا بود | نسخهٔ قبلی ترتیب بصری را **کلمه‌به‌کلمه** می‌ساخت و براکت‌ها را آینه نمی‌کرد | بازنویسی با قاعدهٔ **N1/N2 از UBA** + چیدن runها از آخر به اول + آینه‌کردن براکت (`FaMirror`) |
| ۳ | tooltip روی آبجکت برعکس بود | tooltip را خود ترمینال می‌کشد (bidi دارد)؛ تبدیل دستی رشته را **دو بار** برمی‌گرداند | `OBJPROP_TOOLTIP` متن منطقی خام می‌گیرد (همان قرارداد tooltip آبجکت‌های FROZEN) |
| ۴ | داشبورد چارت را می‌گرفت | کادر گزارش حذف شود | `InpShowDashboard=false` پیش‌فرض (یک ورودی، قابل برگشت) |

**ابزار جدید:** `tools/Validate-PersianRender.ps1` — یعنی `PASS=21 FAIL=0`
- بخش A: بازپیاده‌سازی مستقل قاعدهٔ ترتیب بصری + ۸ fixture با مقدار چشم‌انتظار دستی (`persian_visual.fixture.csv`)
- بخش A2: oracle استاندارد Unicode برای جدول‌های شکل‌دهی در ۸ کدپوینت (`persian_shape.fixture.csv`) — «final» برای حرف غیراتصال‌دهنده عمداً تکرار «isolated» است، چون آزمون اتصال در کد همین را می‌خواهد
- بخش B: قفل‌کردن سیم‌کشی (حالت ۲ پیش‌فرض، RLE پیش‌فرض نیست، tooltip خام، جدول‌های ۴۳تایی هم‌تراز، پنل از `RenderLine` می‌گذرد، داشبورد خاموش)

```text
Build: 0 errors, 0 warnings — SHA256 3B8D85412B4333CD3C8C7B1A04493E0316D78BF19B76E740DF0A0B63FB929CE9
.ex5: 2026-09-18 12:41:40 → …\MQL5\Indicators\khaleq\newICT\ICT_Assistant_Canonical_v0_1.ex5
Validate: Phase14 150/0 · Phase15 36/0 · PersianRender 21/0
```

### و) فاز ۲۴ — سرعت: اندازه‌گیری واقعی و رفع گلوگاه (2026-09-18 13:17)

| # | مورد | ریشهٔ واقعی (عدد از ژورنال زندهٔ MT5) | اصلاح |
|---|---|---|---|
| ۱ | بازسازی ۶۰۰ کندلی ~۱۹٫۵ ثانیه | پروفایل میکروثانیه‌ای نشان داد `PersistPhase12Diagnostics` تنها **۹۷٪** هزینه است: `5.persist12=18,917,116us` از `0.loopTotal=19,475,348us` | هندل مشترک فایل‌های شاهد در بازسازی (`DiagOpen/DiagClose/DiagHoldRelease`): ~۵۹۰ چرخهٔ `FileOpen/seek/write/close` روی پوشهٔ Common → ۴ چرخه، با **همان ردیف‌ها و همان سرستون** |
| ۲ | هزینهٔ هر چرخهٔ فایل ~۳۲ ms | سرباز فایل + اسکنر آنتی‌ویروس روی فایل Common؛ هزینهٔ I/O بود نه محاسبه | همان بالا؛ در حالت زنده رفتار قبلی دست‌نخورده و آزادسازی هندل‌ها در `OnDeinit` |
| ۳ | پنج `Copy*` روی هر tick | تا ۲۰۰۰ کندل × ۵ سری در هر tick، در حالی که تحلیل فقط روی کندل بسته است | کپی فقط با «کندل تازهٔ بسته» یا «بازسازی اولیه»؛ در خطای موقت داده مهر کندل پاک می‌شود تا tick بعد دوباره تلاش شود |
| ۴ | ۱۲۰ `iVolume()` در هر کندل (پروفایل) | فراخوانی timeseries در حلقه | یک `CopyTickVolume`؛ مقدارها عیناً یکی |
| ۵ | ۱۲ `iTime()` در مسیر هر کندل (۹ مورد در `AnalyzeClosedBar`) | فراخوانی timeseries در حلقه | کش `BarTime()` از یک `CopyTime` |
| ۶ | ساخت رشته در هر tick برای شاهد فاز ۱۴ | هشت `IntegerToString` + هفت پیوند در مسیر داغ | گیت درهم‌ساز عددی؛ رشته و فایل فقط با تغییر واقعی |

**ابزارهای جدید**
- `tools/Validate-PerfPhase24.ps1` → `PASS=19 FAIL=0` (قفل‌کردن شش قاعده + هندل مشترک شاهدها)
- `tools/Report-PerfProfile.ps1` → خطوط `ICT PHASE13`/`ICT PHASE24` را از ژورنال زندهٔ ترمینال (UTF-16LE با هندل اشتراکی) می‌خواند و ms هر بازسازی را چاپ می‌کند

**پروفایل «قبل» (اندازه‌گیری‌شده، نه تخمین)**
```text
ICT PHASE13 | rebuild 600 bars in 19516 ms
ICT PHASE24 | profile (top 16, us) | 0.loopTotal=19475348  5.persist12=18917116  2.context=523425
             2r.phase15Diag=312112  2q.reversalDiag=64917  2d.mtf=56631  1.analyze=31508 ...
```
یعنی کل موتور تحلیل (ساختار، نقدینگی، FVG/OB، MTF، DOL، POI، ستاپ) روی هم ~۰٫۶ ثانیه بود و ۱۸٫۹ ثانیه صرف نوشتن شاهد می‌شد.

```text
Build: 0 errors, 0 warnings — SHA256 90E63A508AE3EE5D6179707008794EE844506EBA1773EBC7C6C15342DFADBFB0
.ex5: 2026-09-18 13:17:00 → …\MQL5\Indicators\khaleq\newICT\ICT_Assistant_Canonical_v0_1.ex5
Validate: Phase12 77/0 · Phase13 55/0 · Phase14 150/0 · Phase15 36/0 · ReversalGate 24/0 · MTF PASSED
          TimeBase 0 mismatch · DealingLeg 0 mismatch · PersianRender 21/0 · PerfPhase24 19/0
عدد «بعد»: نیازمند یک reload روی چارت → `powershell -File tools/Report-PerfProfile.ps1`
```

---

## فاز ۲۵ — پنل «همه‌جا» + فارسی tooltip (2026-09-18 14:58)

دو ایراد گزارش‌شده و دو ریشهٔ مستقل:

| # | ایراد | ریشهٔ واقعی | اصلاح |
|---|---|---|---|
| ۱ | پنل توضیح روی همه‌جای چارت باز می‌شد (کادر سیاه) | کلمپ `ExplainPriceToY`: ناحیه‌ای که **هر دو** قیمتش بیرون از دید باشد جعبه‌ای از `−۶۰` تا `chartH+۶۰` می‌ساخت و کل ارتفاع چارت «داخلِ ناحیه» حساب می‌شد → `dist=0` برای هر نقطه | گارد `verticallyVisible`: ناحیهٔ بدون بخش دیدنی کاندید hover نمی‌شود؛ شعاع پذیرش از `tol*4` به `tol*2` |
| ۲ | فارسی «هنوز» خراب دیده می‌شد | کانال tooltip فاز ۲۲ روی **هر** آبجکت: هم روی کل چارت پاپ‌آپ می‌شد، هم متن خام منطقی می‌گرفت و رندرگر ترمینال bidi ندارد (تاپیک ۵۰۴۵۲۲ انجمن MQL5) | `InpSetObjectTooltips=false` پیش‌فرض؛ tooltip حالا از همان `RenderLine(mode)` عبور می‌کند؛ نوشتن بی‌قید + `ExplainClearStaleTooltips()` |

مسیر فارسی پنل تغییر نکرد: `InpExplainRenderMode=2` (شکل‌دهی + ترتیب بصری). منطق تحلیل، رجیستری‌ها و CSVها دست‌نخورده‌اند.

```text
Build: 0 errors, 0 warnings — SHA256 380C05EFB12FA7A37D651903315BB08E6E7471B09F13E784027419FA16A6C4BD
سه کپی یکسان (مخزن / 08_FINAL_PACKAGE / پوشهٔ MT5) · .ex5: 2026-09-18 14:58:02
Validate: PersianRender 24/0 (سه بررسی جدید) · Phase12 77/0 · Phase13 55/0 · Phase14 150/0 ·
          Phase15 36/0 · PerfPhase24 19/0
```

**باز مانده (نیازمند بازبینی چشمی):** «پنل فقط روی ناحیه/خط باز می‌شود» و «فارسی پنل درست است» با یک reload تأیید می‌شود. اگر لازم شد: `InpExplainOnlyWithCtrl=true` (پنل فقط با Ctrl) — بدون rebuild.

---

## فاز ۲۶ — پنل آموزشی کلیدمحور، چارت پیش‌فرض تمیز (2026-09-19 07:17)

| # | قبل | بعد |
|---|---|---|
| ۱ | `input bool InpExplainOnlyWithCtrl = false` (پنل با هر ایستادن موس روی خط باز می‌شد) | `input ENUM_EXPLAIN_GATE InpExplainGate = EXPLAIN_GATE_CTRL` — تا کلید پایین نباشد پنلی باز نمی‌شود |
| ۲ | فقط Ctrl | `CTRL` (پیش‌فرض) · `SHIFT` · `CTRL_SHIFT` · `FREE` |
| ۳ | منطق بیت‌ماسک داخل بدنهٔ `OnChartEvent` | `ExplainGateOpen(sparam)` + `ExplainGateKeyName()` |
| ۴ | نام کلید واضح نبود | یک خط راهنما در **Journal** هنگام attach (روی چارت چیزی اضافه نشد) |

نگاشت مقادیر عمداً با ورودی قدیمی سازگار است: `false → 0 = FREE` و `true → 1 = CTRL`.

مرجع: مستندات رسمی MQL5 — `CHARTEVENT_MOUSE_MOVE`، `sparam` رشتهٔ بیت‌ماسک دکمه‌های ماوس و مودیفایرهاست (بیت ۴ = SHIFT، بیت ۸ = CTRL). Alt در این بیت‌ماسک **نیست**، پس گزینه‌ای برایش گذاشته نشد.

منطق تحلیل، رجیستری‌ها و CSVها دست‌نخورده. `InpExplainOnlyWithCtrl` حذف شد؛ ارجاع‌های فازهای ۱۶ و ۲۲ به آن فقط سابقهٔ تاریخی است.

```text
Build: 0 errors, 0 warnings — SHA256 3293421EE58574E8315CC8353B4B7D240A1D8C6C04E7808145CC41F8DC7591CA
سه کپی یکسان (مخزن / 08_FINAL_PACKAGE / پوشهٔ MT5) · .ex5: 2026-09-19 07:16:58 (394,350 بایت)
Validate: Phase14 153/0 (سه بررسی جدید فاز ۲۶) · Phase12 77/0 · Phase13 55/0 · Phase15 36/0 ·
          PerfPhase24 19/0 · PersianRender 24/0
```

**باز مانده (نیازمند بازبینی چشمی):** «پنل فقط با کلید باز می‌شود» و «فارسی سالم است» با یک reload تأیید می‌شود.

---

## فاز ۲۷ — پنل **کلیکی** + ریشهٔ واقعی خرابی فارسی (2026-09-19 07:22)

**ریشهٔ فارسی (ایراد واقعی، نه حدس):** پنل توضیح با `OBJ_EDIT` رسم می‌شود — یعنی کنترل **بومی ویندوز** که خودش شکل‌دهی و bidi را انجام می‌دهد (کامنت خود کد: «همان کنترل native که رندر درست متن خام فارسی با آن قبلاً تأیید شده»). فاز ۲۲/۲۵ پیش‌فرض `InpExplainRenderMode=2` گذاشت، یعنی متن **قبل از** دادن به آن کنترل به شکل‌های چسبیده تبدیل و به ترتیب بصری برگردانده می‌شد → **دو بار تبدیل** → «فارسی کامل به‌هم‌ریخته».

| # | قبل | بعد |
|---|---|---|
| ۱ | `InpExplainRenderMode = 2` (شکل‌دهی + ترتیب بصری روی کنترل بومی) | `= 0` متن خام منطقی — همان چیزی که قبلاً تأیید شده بود |
| ۲ | پنل با hover یا نگه‌داشتن Ctrl باز می‌شد | `InpExplainOpen = EXPLAIN_OPEN_CLICK` پیش‌فرض؛ کلیک روی آبجکت = پنل کامل، کلیک روی فضای خالی/کلیک دوباره/`ESC` = بستن |
| ۳ | `CHART_EVENT_MOUSE_MOVE` همیشه فعال | فقط در حالت اختیاری HOVER فعال می‌شود → در پیش‌فرض **هیچ** رویداد حرکتی موس دریافت نمی‌شود |
| ۴ | منطق باز/بسته داخل `OnChartEvent` تکرار شده بود | `ExplainOpenAt()` + `ExplainClosePanel()` مشترک بین دو حالت |

**شاهد مستقل فونت:** ابزار جدید `tools/Probe-PersianFont.ps1` با GDI (`GetGlyphIndicesW` + `GetTextFaceW`؛ چون `CreateFontW` فونت غایب را بی‌صدا جایگزین می‌کند) نشان داد `Tahoma` هر ۱۴ کدپوینت آزمون را دارد → **فونت مقصر نبود**.

```text
Build: 0 errors, 0 warnings
Validate: Phase14 154/0 · PersianRender 25/0 · بقیه بدون تغییر
```

---

## فاز ۲۸ — تصحیح منطق FVG با منابع انگلیسی (2026-09-19 07:28)

| # | ایراد | منبع | اصلاح |
|---|---|---|---|
| ۱ | **Implied FVG غلط**: `close` کندل اول ↔ `open` کندل سوم (مرزهای بدنه) | LuxAlgo Library — Implied FVG، فرمول ICT 2023: `UWM=(H+max(O,C))/2`، `LWM=(min(O,C)+L)/2`، صعودی `LWM(t)>UWM(t-2) && L(t)<=H(t-2)` | فرمول میانهٔ فتیله با هر دو شرط، دقیقاً مثل منبع |
| ۲ | آن فرمول بدنه‌ای با برچسب غلط Implied می‌ماند | LuxAlgo — Volume Imbalance: «گپی بین بدنه‌ها که فتیله‌ها هم‌پوشانی دارند» | `FVGK_VOL_IMBALANCE` با discriminator مستقل `۵` (نه حذف) |
| ۳ | هیچ فیلتری برای اندازهٔ گپ نبود → گپ‌های یک‌تیکی = «FVG فیک» | LuxAlgo — Fair Value Gap، مرحلهٔ ۴ تشخیص | `InpMinFVG_ATR = 0.10` (ضریب × ATR، ۰=خاموش) روی هر دو جهت |
| ۴ | لمس لبه و رسیدن به CE یکی حساب می‌شدند | LuxAlgo — Consequent Encroachment: میانه «خط تصمیم» است | پرچم مستقل `FVGObj.ceTouched` + متن پنل حقیقت را می‌گوید |
| ۵ | پنل برای همهٔ نوع‌ها یک تعریف می‌داد | — | `FVGKindToStr()` و خط «چطور ساخته شد» نوع‌محور + گزارش فیلتر با عدد ATR |
| ۶ | شمارندهٔ دفتر فقط Implied+Micro را جمع می‌زد | — | Volume Imbalance هم شمرده می‌شود (وگرنه نوع جدید بی‌صدا حذف می‌شد) |

```text
Build: 0 errors, 0 warnings — SHA256 0E4F3698DDE4E5660F3B75452CF9912B0E3042F84DFB4A69F4E23BEB90F20288
سه کپی یکسان (مخزن / 08_FINAL_PACKAGE / پوشهٔ MT5) · .ex5: 2026-09-19 07:27:37
Validate-Phase28 (ابزار جدید): PASS=19 FAIL=0
باقی ابزارها: Phase12 77/0 · Phase13 55/0 · Phase14 154/0 · Phase15 36/0 · PerfPhase24 19/0 ·
            PersianRender 25/0 · ReversalGate 24/0 · MTF PASSED · TimeBase 0 · DealingLeg 0
```

**هنوز بسته نشده (صادقانه):** بازبینی خط‌به‌خط OB (Breaker/Mitigation/Extreme) و قاعده‌های نقدینگی با منبع انگلیسی انجام **نشده** — قدم بعدی همان روش فاز ۲۸ است.

---

## فاز ۲۹ — BOS/CHoCH و OB (2026-09-19 09:28)

پرسش پس از فاز ۲۸: «FVG ها درست حساب می‌شن؛ BOS ها چی؟ OB چی؟» چهار ایراد زیر با سند در کد + منبع انگلیسی بسته شد:

| # | ایراد | سند | اصلاح |
|---|---|---|---|
| ۱ | **CHoCH هیچ‌وقت جهت مالک را عوض نمی‌کرد** — جهت فقط در `EVT_BOS` یا `EVT_MSS` به‌روز می‌شد. چون خروجی HTF همیشه `disp/liq = -1` می‌گیرد، Bias H4 **فقط با نخستین شکست تاریخچه** تعیین می‌ماند و هرگز برنمی‌گشت. | grep: تنها مسیر عوض‌شدن `g_htfBias`/`g_ltfTrendDir` همان تابع است · LuxAlgo Market Structure: «BOS only can occur after a CHoCH» | `trendDir` پس از هر شکست **بی‌قید** ست می‌شود؛ `MSS` فقط ارتقای برچسب است |
| ۲ | **تایید پیوت یک کندل زودتر از موعد** — `IsConfirmedPivotHigh` شاخص `shift-1` را می‌خواند که در حالت زنده کندل در حال تشکیل است؛ پس سویینگ فانتوم می‌توانست BOS جعلی بسازد (خودِ ورودی می‌گوید No-Repaint). مسیر HTF درست بود. | کد `IsConfirmedPivotHigh` + هم‌خوانی HTF | `pivotShift = shift + InpSwingRight` (فقط کندل‌های **بسته**) |
| ۳ | **رجیستری OB dedup نداشت** — `AppendFVG` داشت، `DetectOB` نه. با دو Displacement پیاپی، `StableZoneId` یکسان دو بار ثبت می‌شد: باکس روی‌هم، شمارش دو برابر، مصرف سقف `InpMaxOB` | کد: `AppendFVG` vs `DetectOB` | حلقهٔ dedup پیش از append؛ متادیتا فقط تکمیل می‌شود + شمارندهٔ `g_obsDeduped` |
| ۴ | **سقف ثابت ۶ کندل** برای یافتن کندل مبدأ OB | LuxAlgo OB: «Step back to the last opposite candle» | `InpOB_LookbackBars = 6` (ورودی) |

```text
Build: 0 errors, 0 warnings — SHA256 E5A409E2033E1E8B925E7E4820249B2FC32631A9EDDF365AD9F6B01233BA68A0
سه کپی یکسان (مخزن / 08_FINAL_PACKAGE / پوشهٔ MT5) · .ex5: 2026-09-19 09:27:50
Validate-Phase29 (ابزار جدید): PASS=20 FAIL=0
باقی ابزارها بدون رگرسیون: Phase12 ✅ · Phase13 ✅ · Phase14 ✅ · Phase15 ✅ · Phase28 19/0 ·
   PerfPhase24 19/0 · PersianRender ✅ · ReversalGate 24/0 · MTF PASSED · TimeBase 0 · DealingLeg 0
```

**هنوز بسته نشده:** (۱) بازبینی قاعده‌به‌قاعدهٔ **نقدینگی** با منبع انگلیسی؛ (۲) `Validate-CanonicalEventLedger` روی CSV **قدیمی** (پیش از محدود‌کردن دفتر به نماد) هنوز FAIL است — دفتر تازه پس از یک reload ساخته می‌شود.

---

## فاز ۳۰ — بازبینی نقدینگی با منابع انگلیسی (2026-09-19 09:36)

هر قاعدهٔ نقدینگی یک‌به‌یک با منبع انگلیسی بازبینی شد. هشت ایراد واقعی بسته شد:

| # | قاعده | منبع | اصلاح |
|---|---|---|---|
| ۱ | **PDH/PDL از کندل روزانهٔ بروکر خوانده می‌شد** (مرز نیمه‌شب سرور) | LuxAlgo — ICT Time Anchors: «The day's high and low are measured from the **midnight open**» · «Midnight New York time, not midnight UTC, not the 5:00 pm forex rollover» | `InpPD_Anchor` با پیش‌فرض `NY_MIDNIGHT` (+ `NY_1700` و `BROKER_DAY`) |
| ۲ | **PWH/PWL همان ایراد در ابعاد هفته** | همان منبع | `WeekWindowBack` پنجرهٔ دوشنبه‌محور نیویورک |
| ۳ | **سمت نقدینگی خط روند از شیب نمی‌آمد** | LuxAlgo — Trendline Liquidity: «below a **rising** support line … a diagonal band of **sell-side** interest» | شرط شیب: سقف‌های نزولی = Buy-Side بالا، کف‌های صعودی = Sell-Side پایین |
| ۴ | **حداقل لمس خط روند اجباری نبود** | LuxAlgo — Trendline Liquidity، مرحلهٔ ۱: «three or more respected touches» | `InpTrendlineMinTouches = 3` |
| ۵ | **Sweep خط روند تشخیص داده نمی‌شد** | LuxAlgo — Trendline Liquidity مرحلهٔ ۴ + Liquidity Sweep مرحلهٔ ۳ | `DetectTrendlineSweep` + نوع `LIQ_TRENDLINE_H/L` + اتصال به زنجیرهٔ رویداد |
| ۶ | **پنجرهٔ نیمه‌پوشیده به‌عنوان رنج ثبت می‌شد** | اصل پروژه: هیچ مقدار تقریبی به‌عنوان داده معتبر | گارد `WindowFullyCovered` روی سشن، روز و هفته |
| ۷ | **EQH/EQL «جدایی» نداشت:** چند پیوت هم‌سطح پشت‌سرهم = «یک سقف کشیده» ولی به‌عنوان استخر نقدینگی ثبت می‌شد | LuxAlgo — Equal Highs/lows As Liquidity، مرحلهٔ ۲: «Require separation … rather than one drawn-out top» | `HasPullbackBetween` + ورودی `InpEQ_MinSeparationATR` |
| ۸ | **زنجیره‌شدن تلورانس EQH/EQL:** مقایسه با اکسترِم متغیر، نردبان نزولی سقف‌ها را یک استخر می‌کرد (دو سر با ۱ دلار فاصله) | همان صفحه، مرحلهٔ ۱ و ۳: «within a few ticks **of one another**» / «draw a **band**» | تلورانس نسبت به **لنگر خوشه**؛ بیرون‌رفتن از باند = پایان خوشه |

**بازبینی شد و درست بود (دست‌نخورده):** قاعدهٔ Sweep افقی (فتیلهٔ فراتر + بستهٔ برگشتی) · پذیرش سطح · جهت EQH/EQL و مقیاس ATR تلورانس · Killzoneها (۲۰–۰۰ / ۰۲–۰۵ / ۰۷–۱۰ نیویورک) · London Close ۱۰–۱۲ · NY PM ۱۳:۳۰–۱۶:۰۰ · Silver Bullets (۰۳–۰۴ / ۱۰–۱۱ / ۱۴–۱۵ نیویورک — منبع: ICT Silver Bullet Times) · Range Liquidity · IPDA ۲۰/۴۰/۶۰ (از کندل ۱، پس بدون امروز) · تفکیک Buy/Sell برای همهٔ انواع.

```text
Build: 0 errors, 0 warnings — SHA256 E9F2FE5E8DBA5252B16CEF3AAF544D40B564753B9D6072D3A7F750158D851130
سه کپی یکسان (مخزن / 08_FINAL_PACKAGE / پوشهٔ MT5) · .ex5: 2026-09-19 09:40 (406,718 بایت)
Validate-Phase30 (ابزار جدید): PASS=43 FAIL=0
بدون رگرسیون: Phase12–15 ✅ · Phase28 ✅ · Phase29 20/0 · PersianRender ✅ · PerfPhase24 ✅ · ReversalGate ✅ · MTF PASSED · TimeBase 0 · DealingLeg 0
```

**ورودی‌های جدید:** `InpPD_Anchor` (پیش‌فرض نیویورک ۰۰:۰۰) · `InpTrendlineMinTouches` (پیش‌فرض ۳) · `InpEQ_MinSeparationATR` (پیش‌فرض ۰ = فقط شرط ساختاری جدایی).
**هنوز بسته نشده:** دفتر رویداد قدیمی (CSV پیش از محدود‌سازی به نماد) — دفتر نمادی تازه بعد از یک reload ساخته می‌شود.

---

## فاز ۳۱ — ممیزی کل پروژه (2026-09-19)

| حوزه | درست‌بودن با منبع |
|---|---|
| FVG · OB · BOS/CHoCH · نقدینگی | ✅ در فازهای ۲۸–۳۰ سنجیده و اصلاح شد |
| Wyckoff · S&D · RTM · Brooks · Profile/MP · MTF · DOL · ستاپ | ⚠️ پیاده است، ولی قاعده‌به‌قاعده با منبع **سنجیده نشده** |

**وجود ندارند (grep = ۰):** Open Types · Day Types · Profile Shapes · Naked/Virgin POC · Fixed/Visible Range Profile · Balance/Imbalance به‌عنوان حالت · Trading Range · Measured Moves · L1/L2 · Engulfing به‌عنوان الگوی کندلی · Price Delivery · Quarterly Theory · Nested/MTF Mitigation.

**مسیر پیشنهادی:** اول بازبینی با منبع برای خانواده‌های موجود (Wyckoff → S&D → Profile → Brooks → RTM → DOL/ستاپ)، سپس پیاده‌سازی غایب‌ها.

---

## فاز ۳۲ — موتور «ریسک برگشت» (2026-09-19 09:47)

برای این پرسش: «طلا تا کجا رفت، چند درصد احتمال برگشت دارد، اون نقطه OB است یا لیکویدی — که برعکس وارد ترید نشوم.»

- در هر کندل بسته: نزدیک‌ترین سطح از **همهٔ** رجیستری‌ها + وضعیتش + فاصله (ATR) · پیشرفت لگ (٪) · فاصله تا DOL · پرچم SFP · Exhaustion · هم‌جهتی MTF.
- امتیاز هشدار ۰..۱۰۰ با وزن‌های مستند (۲۵/۲۰/۱۵×۳/۱۰×۲/−۱۰) — **«درصد» نیست** و در کد هم هیچ درصدی تولید نمی‌شود.
- درصد واقعی از داده شمرده می‌شود: `tools/Report-ReverseRisk.ps1` روی CSV شاهد، با تعریف صریح «برگشت = حرکت R×ATR خلاف Bias در افق N کندل» و حداقل ۱۰ نمونه برای هر خوشه.

```text
Build: 0 errors, 0 warnings — SHA256 9FBA5966E3AAE09A02DC58B63640D82012E9513D607C389EAB42391587EB7A54 · .ex5: 2026-09-19 09:46
Validate-Phase32 (جدید): PASS=26 FAIL=0 · ابزار جدید: Report-ReverseRisk.ps1
شاهد: COMMON\Files\ICT_Assistant_Canonical_ReverseRisk_<symbol>.csv (۱۹ ستون)
```

**هنوز نیست:** تا یک reload و یک اجرای ابزار، هیچ عدد درصدی وجود ندارد (کد هم ادعایی نمی‌کند).

---

## فاز ۳۰ — به‌روزرسانی نهایی (سقف باند EQ + شرط جدایی)

با شرط جدایی و تلورانس لنگرمحور در EQH/EQL، تعداد نهایی بررسی‌های ابزار `Validate-Phase30` به **PASS=43** رسید (فاز ۳۰ = ۸ ایراد نقدینگی).

---

## فاز ۳۳–۳۴ — ممیزی دونه‌به‌دونهٔ Wyckoff · S&D · Brooks · Profile/AMT · RTM با منابع (2026-09-19 10:02)

**۱۹ ایراد اثبات‌شده** با شاهد کد + منبع انگلیسی بازبینی و بسته شد (جدول کامل در مستندات فنی پروژه):

| خانواده | ایرادهای بسته‌شده |
|---|---|
| Wyckoff | ۷ ایراد — ۸ رویداد بی‌موتور (AR/ST/SOS/SOW/LPS/LPSY/PS/PSY) → فازهای A/D/E غیرقابل‌دستیابی · Spring در هر نقطهٔ تاریخچه · رنج جاودانه · نبود جذب |
| Al Brooks | ۶ ایراد — H1/H2 برعکس تعریف · نبود L1/L2 · Always-In نه وضعیت · ورودی و هندل ۲۰ EMA مرده · Signal bar بی‌بافت · Follow-through بی‌مرجع |
| Supply & Demand | ۴ ایراد — نقش Supply/Demand دو الگوی برگشتی برعکس · تفکیک‌نشدن RBR از DBR · ناحیهٔ FLIP رهاشده · حالت `SDS_BROKEN` مرده + سقف سخت‌کد |
| Profile / AMT | ۱ بستهٔ ۵ آیه — `ibHigh/ibLow` مرده (Initial Balance نبود) + نبود TPO · HVN/LVN · Naked POC · نوع روز · نوع باز شدن · Balance/Imbalance |
| RTM | ۱ بستهٔ ۵ آیه — Trap · Momentum · Engulfing · Rejection بدون شناسه/رجیستری/توضیح |

```text
Build: 0 errors, 0 warnings
SHA256: 6CE1741E3DB52E5932A55AEC12B133B4DE47909ED184ED89AE42384AC768AE31 (سه کپی یکسان)
.ex5: 2026-09-19 10:02 — 462,382 بایت → …\MQL5\Indicators\khaleq\newICT\
Validate-Phase34 (جدید): PASS=63 FAIL=0
رگرسیون: Phase12 77/0 · Phase13 55/0 · Phase14 154/0 · Phase15 36/0 · Phase28 19/0 · Phase29 20/0
   Phase30 43/0 · Phase32 26/0 · PerfPhase24 19/0 · PersianRender 25/0 · ReversalGate 24/0 · TimeBase 0 · DealingLeg 0
```

**ورودی‌های جدید (همه از پنجرهٔ تنظیمات، بدون rebuild):** گروه Wyckoff state machine (۱۵ ورودی) · `InpBrooks_DojiBodyRatio` · `InpBrooks_PullbackWindow` · `InpBrooks_AI_EMASlopeBars` · `InpSD_BaseMaxRangeATR` · گروه AMT (`InpProfileIB_Minutes` · `InpAMT_HistDays` · `InpAMT_TrendIBRatio` · `InpAMT_NontrendIBRatio` · `InpProfileHVN_Ratio` · `InpProfileLVN_Ratio` · `InpDrawAMTOnChart`) · گروه RTM (`InpRTM_MomentumATR` · `InpRTM_MomentumBody` · `InpRTM_RejectTailRatio` · `InpRTM_MaxEvents` · `InpDrawRTMObjects`).

**رفتار قابل تغییر که باید بدانی:** رویدادهای Wyckoff حالا **کمتر ولی معنادار** دیده می‌شوند (Spring فقط داخل رنج تأییدشده)، برچسب H/L شمارش تلاش‌ها را نشان می‌دهد (نه پولبک)، و RTM/AMT برچسب پیش‌فرض روی چارت ندارند (فقط در داشبورد و پنل کلیکی) تا چارت تمیز بماند.

**هنوز نیست (صادقانه):** Measured Moves · Trading Ranges دو طرفه · Nested/MTF Mitigation · برچسب Price Delivery · Quarterly Theory · Profile Shapes · Heatmap/Iceberg (روی tick-volume اصلاً ممکن نیست) · Channel Lines. این‌ها در «فاز ۳۶ به بعد» قابل شروع‌اند (فاز ۳۵ به نوار ریسک اختصاص یافت — بند ۴‑۰‑۳۳ در مستندات فنی).

## Phase 35 — Single-line risk strip (2026-09-19 15:04)

نوار تک‌خطی گوشهٔ بالا-چپ چارت: `Bias | ریسک برگشت: LABEL (score) | سطح: نوع [وضعیت] N ATR | لگ N% | هدف` — فقط نمایش آخرین وضعیت موتور فاز ۳۲؛ بدون داشبورد، بدون CSV، بدون محاسبهٔ موازی.

- کانال فارسی: همان `ExplainEditRow` پنل آموزشی (OBJ_EDIT، متن خام، پیش‌فرض `InpExplainRenderMode=0`)
- کارایی: کش متن `g_riskStripLastText` — متن تغییری نکرده، هیچ ObjectSet/ChartRedraw
- ورودی‌ها: `InpShowRiskStrip=true` · `InpRiskStripY=2` · `InpRiskStripWidth=640`

```text
Build: 0 errors, 0 warnings
SHA256: DCFDBB79A195272FFB16E0B78D2C04343ED28EDBEBB1C424BBD514D736598B6B (سه کپی یکسان)
.ex5: 2026-09-19 15:04 — 469,640 بایت → …\MQL5\Indicators\khaleq\newICT\
Validate-Phase35 (جدید): PASS=23 FAIL=0
رگرسیون: Phase12 77/0 · Phase13 55/0 · Phase14 154/0 · Phase15 36/0 · Phase28 19/0 · Phase29 20/0
   Phase30 43/0 · Phase32 26/0 · PerfPhase24 19/0 · PersianRender 25/0
```

## فاز ۳۶ — پوشش کامل ۱۳ قلم باقی‌مانده (2026-09-19)

هر ۵ قلم ❌ (OB Internal/External · Quarterly Theory · Brooks Trading Range · Measured Move · Channel Lines) و ۸ نقطهٔ ⚠️ (BISI/SIBI · SB+HTF-LTF Sync · Strength of Zone · Effort vs Result · Engulfing/Absorption در نواحی · AMD قیمتی · Price Delivery · Nested Mitigation) با منبع انگلیسی (LuxAlgo IRL/ERL، Quarterly Theory Daye-4Q، Brooks TR/MM/Channel، ICT BISI/SIBI، SMC Nested Mitigation) پیاده شد.

```text
Build: 0 errors, 0 warnings
SHA256: 21F76343B25D46B6DDF9B793694EE9040AE78B88E57EAF73EA0121CDDAD8FBD1 (سه کپی یکسان)
.ex5: 2026-09-19 19:56 — 471,384 بایت → …\MQL5\Indicators\khaleq\newICT\
Validate-Phase36 (جدید): PASS=51 FAIL=0
رگرسیون: Phase12 77/0 · Phase13 55/0 · Phase14 154/0 · Phase15 36/0 · Phase28 19/0 · Phase29 20/0
   Phase30 43/0 · Phase32 26/0 · Phase34 63/0 · Phase35 23/0 · PerfPhase24 19/0 · PersianRender 25/0
```

جزئیات و لنگرهای کد: مستندات فنی پروژه بند ۴‑۰‑۳۷. فهرست قبلی «فاز ۳۶ به بعد» بسته شد؛ هیچ قلم ❌ از فهرست رسمی باقی نمانده است.

## فاز ۳۷ — آزمون رفتاری روی دادهٔ ساختگی (FVG · OB · Sweep) (2026-09-20)

**ایراد ساختاری که بسته شد:** پیش از این، هر ۲۵ ابزار `tools/Validate-*.ps1` فقط متن کد را grep می‌کردند. یک grep سبز با یک فرمول اشتباه هم سبز می‌ماند؛ یعنی «رشته در فایل هست» ثابت می‌شد، نه «محاسبهٔ عددی درست است». این فاز اولین لایه‌ای است که **عدد** می‌سنجد.

**راه‌حل:** MQL5 بیرون از MetaTrader اجرا نمی‌شود، پس بازنویسی منطق در PowerShell یعنی سنجیدن دو پیاده‌سازی مستقل با هم (نه کد واقعی). بنابراین هارنس **داخل خود اندیکاتور** است و همان توابع زندهٔ `DetectFVG` / `DetectOB` / `DetectSweep` را روی کندل‌های ساختگی با پاسخ معلوم اجرا می‌کند. هیچ منطق تکراری‌ای وجود ندارد که از کد اصلی جدا بیفتد.

| مورد | مقدار |
|---|---|
| سناریوها | ۲۵ (FVG ۸ · OB ۸ · Sweep ۸ · SENSITIVITY ۱) |
| ورودی جدید | `InpRunBehaviorSelfTest` (پیش‌فرض روشن) + گروه آخر لیست تا اندیس ورودی‌های قبلی عوض نشود |
| خروجی | `ICT_Assistant_Canonical_SelfTest.csv` در `COMMON\Files` — یک‌بار در هر attach |
| تفکیک از تحلیل زنده | `g_rebuildMode=true` (رسم نمی‌شود) · رجیستری‌ها پس از آزمون صفر · `g_analysisATR`/`g_leg.valid`/`g_obsDeduped` بازگردانده می‌شوند |
| دندان هارنس | ردیف `SENSITIVITY_probe_must_report_FAIL` یک ادعای عمداً غلط است؛ ابزار **دقیقاً یک** FAIL را الزامی می‌داند |

**ابزار `tools/Validate-Phase37.ps1` — سه بخش مستقل:**

- **A) پیاده‌سازی دوم:** اعداد انتظار از متن قاعده در PowerShell بازمحاسبه می‌شوند (مرز گپ سه‌کندلی ICT، `UWM/LWM` فرمول Implied، گپ بدنه = Volume Imbalance، شرط جارو، انتخاب نزدیک‌ترین سطح، بدنه/کل‌کندل OB). اگر کندل‌های ساختگی عوض شوند، A دیگر با گزارش موافق نمی‌ماند → drift بی‌صدا رد نمی‌شود.
- **B) شاهد runtime:** گزارش CSV خوانده می‌شود؛ هر ۲۵ سناریو دقیقاً یک‌بار؛ همه PASS به‌جز **یک** FAIL طراحی‌شده؛ ستون `Actual` با بازمحاسبهٔ A مقایسه می‌شود؛ `SKIPPED` فقط وقتی ورودی مربوطه واقعاً خاموش است.
- **C) اثبات سیم‌کشی:** تعریف یک‌تا، فراخوانی یک‌تا با شمار کندل، قرارگیری **پیش از** بازسازی تاریخچه، صفر شدن رجیستری‌ها، بازگردانی وضعیت زنده، انطباق فهرست سناریوها با سورس.

```text
Build: 0 errors, 0 warnings
SHA256: 13A34E6B175AD4B49CA88DFF7C3CA48D68A3DB7AF58780779BE19D618B2871E2 (سه کپی یکسان)
.ex5: 2026-09-20 11:37 — 518,248 بایت → …\MQL5\Indicators\khaleq\newICT\
سورس: 11,068 خط · 259 ورودی
Validate-Phase37 (جدید): PASS=21 FAIL=0 PENDING=1  ← بخش B منتظر یک reload روی چارت
رگرسیون: Phase12 77/0 · Phase13 55/0 · Phase14 154/0 · Phase15 36/0 · Phase28 19/0 · Phase29 20/0
   Phase30 43/0 · Phase32 26/0 · Phase34 63/0 · Phase35 23/0 · Phase36 51/0 · PerfPhase24 19/0 · PersianRender 25/0
```

**وضعیت صادقانه:** بخش‌های A و C (بازمحاسبهٔ عددی + اثبات سیم‌کشی) بدون MetaTrader اثبات شده‌اند. بخش B به یک reload نیاز دارد، چون MQL5 بیرون ترمینال اجرا نمی‌شود؛ تا آن لحظه ابزار `PENDING` می‌دهد و ادعای سبز نمی‌کند.

جزئیات و لنگرهای کد: مستندات فنی پروژه بند ۴‑۰‑۳۸.
