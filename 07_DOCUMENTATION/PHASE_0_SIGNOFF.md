# Phase 0 Sign-off: ICT Assistant Foundation

Date: 2026-09-15
Status: FINALIZED

## Objective

Establish one controlled development source, one MT5 compile mirror, one canonical indicator candidate, and a documented reference set before adding more ICT logic.

## Development source

`D:\ICT_indicator`

Canonical source:

`D:\ICT_indicator\01_CANONICAL_CANDIDATES\ICT_Assistant_Canonical.mq5`

Standalone package:

`D:\ICT_indicator\08_FINAL_PACKAGE\ICT_Assistant_Canonical_v0_1`

## MT5 compile mirror

`C:\Users\Khaleq\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Indicators\khaleq\newICT`

The canonical `.mq5` file and the compile mirror are synchronized by hash after each source update.

## Current package files

- `ICT_Assistant_Canonical_v0_1.mq5`
- `README.md`

This package currently has no required `.mqh` files. Legacy headers are not copied into the canonical package because they use different timing and state contracts.

## Reference set

- ICT public concept reference
- Supplied TradingView references
- `joshyattridge/smart-money-concepts`
- `manuelinfosec/profittown-sniper-smc`
- `lordgaruda/XAU-60`

Reference notes:

- Public descriptions and open-source algorithms may inform an independent implementation.
- Private or copyrighted source code is not copied.
- Bot execution and risk-management code is excluded because the product is an indicator, not an EA.

## Locked engineering rules

- Bar 0 is forming; it cannot create a final event.
- Structure events use closed-bar confirmation.
- Wick-only penetration is a liquidity event, not automatically BOS or CHoCH.
- External and Internal structure remain separate.
- Every visible event needs a reason and invalidation explanation.
- Failed or invalidated setups must be explainable rather than silently disappearing.
- The indicator never places trades.
- English ICT terms remain unchanged on the chart; explanations are Persian.
- Chart colors are dark enough for a white chart background.

## Phase 0 deliverables

- Repository inventory and version grouping
- Workspace folder organization
- External reference index
- Research findings document
- Canonical architecture document
- Repaint/timing audit
- Standalone canonical source package
- MT5 compile mirror
- Persian educational display convention

## Exit condition

Phase 0 is complete. New work belongs to Phase 1 onward: feature completion, MTF context, setup lifecycle, validation, and optimization.
