# ICT Indicator Workspace Map

## Folders

- `00_INBOX_NEW`: New files, source snippets, and material not reviewed yet.
- `01_CANONICAL_CANDIDATES`: Candidate bases for the unified professional indicator.
- `02_SHARED_ENGINES`: Shared engines after they are audited and normalized.
- `03_ICT_MODULES`: Reusable ICT concept modules.
- `04_LEGACY_VERSIONS`: Historical versions kept for comparison and recovery.
- `05_TESTS_AND_VALIDATION`: Behavior tests, replay cases, and validation artifacts.
- `06_EXTERNAL_REFERENCES`: TradingView links, public references, and user-provided specifications.
- `07_DOCUMENTATION`: Audit notes, definitions, decisions, and architecture documents.

## Current implementation

- `01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5`: the only editable implementation source; it contains the closed-bar ICT pipeline, MTF context, chart rendering, and educational explanation panel.
- `08_FINAL_PACKAGE/ICT_Assistant_Canonical_v0_1`: synchronized delivery copy of the canonical source.
- `tools/Sync-And-Compile-Canonical.ps1`: the only supported synchronization and compile path.
- `05_TESTS_AND_VALIDATION`: fixtures and validation artifacts for the canonical contract.

## Intake rule

Place new indicators or source material in `00_INBOX_NEW`. Place public URLs or exact behavioral specifications in `06_EXTERNAL_REFERENCES`. Do not merge new logic into a candidate until its timing, repaint behavior, and definition are reviewed.
