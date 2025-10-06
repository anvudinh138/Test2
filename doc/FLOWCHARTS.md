# Flowcharts (Mermaid)

## 1) High‑Level Controller (with Basket TP & Flip)
```mermaid
flowchart TD
    T[OnTick] --> U[Update A & B state]
    U --> V{Any basket losing?}
    V -- A losing --> R[Rescue decision for A]
    V -- B losing --> S[Rescue decision for B]
    V -- None --> W[Maintain grids only]

    R --> X{(Breach or DD) and (Cooldown, Exposure OK)?}
    S --> Y{(Breach or DD) and (Cooldown, Exposure OK)?}
    X -- Yes --> O[Open opposite hedge on B]
    Y -- Yes --> P[Open opposite hedge on A]
    X -- No --> W
    Y -- No --> W

    U --> Q{Group TP / TSL hit on A or B?}
    Q -- Yes --> Z[Close whole basket atomically]
    Z --> AA{Other side still in DD?}
    AA -- Yes --> AB[Flip roles / may open new hedge]
    AA -- No --> AC[Cycle complete]

    W --> AD{Risk limits breached?}
    AD -- Yes --> AE[Close All & Halt]
    AD -- No --> T
2) Basket Internal (Group TP + TSL)
mermaid



flowchart LR
    A[Refresh PnL & avg] --> B{PnL ≥ Target or price ≥ tp?}
    B -- Yes --> C[Close all orders in basket]
    B -- No --> D{Move in favour ≥ TSL_START?}
    D -- No --> E[Keep running]
    D -- Yes --> F[Enable trailing; trail by step]
    F --> E
3) Rescue/Hedge Engine
mermaid



flowchart LR
    S[Price breaches last grid OR DD ≥ threshold] --> C{Cooldown/Exposure OK?}
    C -- No --> X[Skip rescue]
    C -- Yes --> H[Open opposite basket: 1 market + staged limits]
    H --> T[Enable TSL when in profit]
    T --> M[Lock profits on pullbacks]
    M --> K[Use profit to pull loser TP closer]
4) Basket State Machine
mermaid



stateDiagram-v2
    [*] --> Idle
    Idle --> Building : seed + limits
    Building --> Active
    Active --> Hedge : opposite basket opened
    Hedge --> Active : hedge closed partial/full
    Active --> Closing : TP/TSL hit
    Closing --> Idle : basket flattened
    Active --> Halted : risk breach
    Hedge --> Halted  : risk breach
    Halted --> [*]