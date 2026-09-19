# Phase 15 behavior fixtures — what each file really is

Read this before quoting any number from these files. Two kinds of data live here:

1. **Rule fixtures** (`*.fixture.csv`) — written by hand from the rule text.
   The verifier `tools/Validate-Phase15.ps1` re-implements the rule
   independently and compares. Each rule fixture has a `_bad` twin that breaks
   the rule on purpose, and the verifier must catch it.
2. **Recorded snapshots** (`*_snapshot.csv`) — copied **byte-for-byte** (only
   UTF-16 → UTF-8 and line endings changed) from files the indicator itself
   wrote into
   `…\MetaQuotes\Terminal\Common\Files\`. They are evidence of what ran on a
   live chart, not of what the rules say.

## Rule fixtures

| File | Rule | Bad twin catches |
|---|---|---|
| `dst_rules.fixture.csv` | US: 2nd Sunday of March 07:00 UTC → 1st Sunday of November 06:00 UTC. EU: last Sunday of March 01:00 UTC → last Sunday of October 01:00 UTC. Both sides of every boundary are listed. | a boundary instant with the wrong DST flag |
| `broker_offset.fixture.csv` | `offset(serverT) = std + (dstAtUTC ? 60 : 0)`, resolved by a fixed point because the server clock depends on the offset. Cases: EET broker (+2/+3), US broker (−5/−4), a broker with no DST (+5:30), and the fall-back hour that occurs twice. | a fall-back instant with the summer offset |
| `setup_lifecycle.fixture.csv` | A tracked setup is invalidated **only** when a *closed* bar finishes beyond its SL; a wick is not enough. TP1 is a touch. If one bar does both, invalidation wins. Re-arming needs a new chain id. Switching the lifecycle off / a zero SL never arms. | a wick-only bar expected as invalidation, and a same-bar-both expected as TP1 |

**Known ambiguity, stated honestly:** inside the *skipped* hour of a spring
forward (e.g. 03:00 server time on the EU switch day) a wall-clock timestamp is
ambiguous, and no unique offset exists. MQL5 does not produce bars with such
timestamps — M1 bars jump from 02:59 to 04:00 — so no fixture case is built on
that hour, and the resolver's behaviour there is undefined rather than wrong.

## Recorded snapshots

| File | Origin | Filters applied |
|---|---|---|
| `fvg_lifecycle_snapshot.csv` | `ICT_Assistant_Canonical_FVG_Diag.csv`, written 2026-09-16 23:xx–00:36 by the chart instance whose symbol family is ~178 (EURJPY-class), chart TF = current (H1 by the recorded ages) | none — 26 rows, all present |
| `reversal_gate_snapshot.csv` | `ICT_Assistant_Canonical_Reversal_Diag.csv`, last 20 rows (2026-09-13 22:00 → 2026-09-16 20:00), **legacy schema (no `Symbol` column)** | none |

### A real defect this fixture exposed

The reversal ledger rows in that snapshot come from **two different chart
instances at once** (guard prices around 4450 belong to one symbol, `HtfClose`
around 185.6 to another) and the legacy ledger has **no symbol column**, so
there was no way to attribute a row to a symbol. Phase 15 therefore:

* added a `Symbol` column to `ICT_Assistant_Canonical_Reversal_Diag.csv`
  (second column, written as `_Symbol`) and made the header self-heal require
  it, and
* made the writer **refuse to append** a row when the file still carries the
  legacy header and cannot be rewritten, instead of writing an ambiguous row.

The copied snapshot above keeps the legacy (symbol-less) schema on purpose: it
is the evidence of the old behaviour, and it is the only copy that survives the
one-time rewrite of the live file.

### Invariants checked on the snapshots

FVG: geometry (`Top > Bottom`), never mitigated on the birth bar
(`Mitigated=1 ⇒ BarsToTouch ≥ 1`), `Mitigated` ⇔ a touch time exists,
`Inverted=1 ⇒ Mitigated=1`, `Invalidated=1 ⇒ Mitigated=1`, `AgeBars ≥
BarsToTouch`, and the recorded invalidation boundary agreeing with
`InpFVG_ExpireBars` read from the source (default 500 — the snapshot shows
invalidation only above age 500 and survival only at or below it).

Reversal gate: a not-broken gate never carries a confirmation, a waiting state
never carries a guard level/id/side, a break always has a guard level, the
reversal score never exceeds its maximum, and recorded chart bars ascend.

Every one of these has a `_bad` twin that the verifier must reject.
