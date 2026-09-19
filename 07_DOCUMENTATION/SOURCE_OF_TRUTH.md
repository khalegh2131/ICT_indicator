# Canonical Source of Truth

The project has one editable implementation source. It is now promoted from the former minimal snapshot to the V13 Eagle Eye causal-chain base:

`D:\ICT_indicator\01_CANONICAL_CANDIDATES\ICT_Assistant_Canonical.mq5`

The following files are generated copies and must not be edited directly:

- `D:\ICT_indicator\08_FINAL_PACKAGE\ICT_Assistant_Canonical_v0_1\ICT_Assistant_Canonical_v0_1.mq5`
- `C:\Users\Khaleq\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Indicators\khaleq\newICT\ICT_Assistant_Canonical_v0_1.mq5`

## Required workflow

1. Edit and review the canonical source in the repository.
2. Run `tools\Sync-And-Compile-Canonical.ps1`.
3. Confirm MetaEditor reports `0 errors, 0 warnings`.
4. Confirm the three MQ5 files have the same SHA256 hash.
5. Only then inspect the compiled indicator in MT5.

The active canonical source now contains the V13 typed registries for structure events, liquidity, displacement, FVG, OB, DOL, and setup state. The MT5 folder is a compile and runtime mirror, not a second development branch. V9 features such as SMT, Turtle Soup, Rejection Block, NDOG/NWOG, and outcome logging remain the next integration batch and are not claimed as present until connected to the V13 causal chain.

V13 structure events are persisted to the common ledger `ICT_Assistant_V13_Events_v1.csv`. Validate it with `tools\Validate-V13EventLedger.ps1`.