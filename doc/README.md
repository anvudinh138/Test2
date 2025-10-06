# Two‑Sided Recovery Grid (Flex‑Grid style)

> **DISCLAIMER**: Educational only — not investment advice. Grid/hedge strategies can lose money rapidly in strong one‑way trends. Use on demo first.

This repository documents a practical, implementation‑ready specification for a **two‑sided recovery grid** similar in spirit to the Flex‑Grid / DashPlus behavior seen in the screenshots you shared.

**Core idea**  
Always maintain two baskets (BUY & SELL). When one basket is in drawdown (loser), open a **small opposite hedge basket** with a **trailing stop (TSL)** to scalp pullbacks. The hedge profits are used to **pull the loser basket's group TP** (break‑even + small delta) **closer to current price**. When price tags this **group TP bar**, **close the entire loser basket at BE + δ**, then **flip roles** and repeat.

### Files
- `STRATEGY_SPEC.md` — full specification, parameters, math, safety.
- `PSEUDOCODE.md` — complete pseudo-code with OOP classes and control loop.
- `FLOWCHARTS.md` — Mermaid diagrams (high-level flow, basket TP/TSL, rescue engine, state machine).
- `ARCHITECTURE.md` — suggested modular structure for an EA/bot (MQL5/MT5, Python, or C#).
- `CONFIG_EXAMPLE.yaml` — baseline parameters to start safe testing.
- `TESTING_CHECKLIST.md` — acceptance, backtest scenarios, logging requirements.
- `GLOSSARY.md` — UI/term mapping (Basket, Recovery, TSL START, TP gộp...).

### Quick Start (conceptual)
1. Start with **neutral grids** both sides (1 market seed + N−1 limits).
2. Detect the **losing** side; if criteria met → open **opposite hedge** and enable **TSL**.
3. When hedge closes partial/full profit, **recompute loser TP** toward price.
4. If **group TP** is hit → **close full loser basket**, **flip roles**, maintain grids, continue.
5. Enforce **exposure & session risk caps**. Halt if breached.
