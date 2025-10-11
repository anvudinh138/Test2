# Flowcharts - Recovery Grid Direction v3.1.0

## Main Control Flow

```mermaid
flowchart TD
    T[OnTick] --> M{Market Open?}
    M -- No --> END[Return]
    M -- Yes --> N{News Filter Active?}
    N -- Yes --> END
    N -- No --> U[Update Controller]

    U --> BA[Update BUY Basket]
    U --> BB[Update SELL Basket]

    BA --> BC{BUY Closed?}
    BC -- Yes --> BD[Take Realized Profit]
    BD --> BE[Reduce SELL Target]
    BE --> BF[Reseed BUY Grid]

    BB --> SC{SELL Closed?}
    SC -- Yes --> SD[Take Realized Profit]
    SD --> SE[Reduce BUY Target]
    SE --> SF[Reseed SELL Grid]

    BC -- No --> CONT[Continue]
    SC -- No --> CONT
    CONT --> END
```

## Basket Update Flow

```mermaid
flowchart TD
    A[Basket Update] --> B[Refresh Positions]
    B --> C[Calculate Floating PnL]
    C --> D[Update Average Price]
    D --> E[Calculate Group TP]

    E --> TE{Time Exit Check}
    TE -- Enabled --> TH[Check Hours Underwater]
    TH --> HRS{> 24 hours?}
    HRS -- Yes --> LOSS{Loss Acceptable?}
    LOSS -- Yes --> CLOSE[Close Basket]
    LOSS -- No --> TP
    HRS -- No --> TP
    TE -- Disabled --> TP

    TP{TP Hit?}
    TP -- Yes --> CLOSE
    TP -- No --> LG[Lazy Grid Check]

    LG --> EX{Need Expansion?}
    EX -- Yes --> ADD[Add Grid Levels]
    EX -- No --> RET[Return]

    CLOSE --> DONE[Mark Closed]
    ADD --> RET
```

## Lazy Grid Fill (Always ON)

```mermaid
flowchart TD
    START[Check Grid State] --> CNT{Positions < Max Levels?}
    CNT -- No --> SKIP[Skip Expansion]
    CNT -- Yes --> DD{Check Drawdown}

    DD --> TH{DD > Threshold?}
    TH -- Yes --> SKIP
    TH -- No --> DST[Check Distance to Next Level]

    DST --> FAR{Distance > Max?}
    FAR -- Yes --> SKIP
    FAR -- No --> PLACE[Place Next Grid Level]

    PLACE --> UPD[Update Grid State]
    UPD --> LOG[Log Expansion]
    LOG --> SKIP
```

## Dynamic Spacing (Always ON)

```mermaid
flowchart LR
    BASE[Base Spacing] --> TREND[Analyze Trend Strength]

    TREND --> STATE{Market State}
    STATE -- RANGE --> M1[1.0x Multiplier]
    STATE -- WEAK_TREND --> M2[1.5x Multiplier]
    STATE -- STRONG_TREND --> M3[2.0x Multiplier]
    STATE -- EXTREME_TREND --> M4[3.0x Multiplier]

    M1 --> FINAL[Final Spacing]
    M2 --> FINAL
    M3 --> FINAL
    M4 --> FINAL

    FINAL --> USE[Apply to Grid]
```

## Time-Based Exit Logic

```mermaid
flowchart TD
    CHECK[Time Exit Check] --> EN{Enabled?}
    EN -- No --> SKIP[Skip]
    EN -- Yes --> TIME[Get First Position Time]

    TIME --> CALC[Calculate Hours Underwater]
    CALC --> TH{> 24 hours?}
    TH -- No --> SKIP
    TH -- Yes --> MODE{Trend Only Mode?}

    MODE -- No --> AMT[Check Loss Amount]
    MODE -- Yes --> TREND{Counter-Trend?}
    TREND -- No --> SKIP
    TREND -- Yes --> AMT

    AMT --> ACC{Loss <= $100?}
    ACC -- No --> SKIP
    ACC -- Yes --> EXIT[Trigger Exit]

    EXIT --> CLOSE[Close Basket]
    CLOSE --> LOG[Log Exit Reason]
```

## Profit Redistribution

```mermaid
flowchart TD
    CLOSED[Basket Closed] --> PROFIT[Calculate Realized Profit]
    PROFIT --> POS{Profit > 0?}

    POS -- No --> SEED[Reseed Only]
    POS -- Yes --> OPP[Get Opposite Basket]

    OPP --> ACT{Opposite Active?}
    ACT -- No --> SEED
    ACT -- Yes --> RED[Reduce Target]

    RED --> CALC[New Target = Old - Profit]
    CALC --> TP[Recalculate TP Price]
    TP --> MOD[Modify TP Orders]

    MOD --> SEED
    SEED --> NEW[Open Fresh Grid]
    NEW --> DONE[Complete]
```

## Simplified vs Complex Architecture

```mermaid
graph LR
    subgraph "v3.0.0 Complex"
        C1[Multi-Job System]
        C2[Basket Stop Loss]
        C3[Gap Management]
        C4[TSL/Rescue]
        C5[Portfolio Ledger]
        style C1 fill:#ff9999
        style C2 fill:#ff9999
        style C3 fill:#ff9999
        style C4 fill:#ff9999
        style C5 fill:#ff9999
    end

    subgraph "v3.1.0 Simplified"
        S1[Dual Grid Only]
        S2[Lazy Fill ON]
        S3[Dynamic Spacing ON]
        S4[Time Exit]
        S5[Clean P&L]
        style S1 fill:#99ff99
        style S2 fill:#99ff99
        style S3 fill:#99ff99
        style S4 fill:#99ff99
        style S5 fill:#99ff99
    end

    C1 -.-> S1
    C2 -.-> S4
    C3 -.-> S2
    C4 -.-> S5
```

## News Filter Integration

```mermaid
flowchart TD
    TICK[OnTick] --> NF[Check News Filter]
    NF --> EN{Enabled?}

    EN -- No --> TRADE[Continue Trading]
    EN -- Yes --> FETCH[Fetch Calendar]

    FETCH --> OK{Success?}
    OK -- No --> CACHE[Use Cache/Skip]
    OK -- Yes --> PARSE[Parse Events]

    PARSE --> TIME[Check Current Time]
    TIME --> WIN{In News Window?}

    WIN -- Yes --> PAUSE[Pause Trading]
    WIN -- No --> TRADE

    PAUSE --> LOG[Log Once]
    LOG --> SKIP[Skip Tick]

    CACHE --> TRADE
```

## Complete System State

```mermaid
stateDiagram-v2
    [*] --> Init: OnInit()
    Init --> Idle: Ready

    Idle --> Trading: OnTick()

    Trading --> BuyActive: BUY positions
    Trading --> SellActive: SELL positions
    Trading --> BothActive: Both sides

    BuyActive --> BuyClosed: TP/TimeExit
    SellActive --> SellClosed: TP/TimeExit
    BothActive --> BuyActive: SELL closed
    BothActive --> SellActive: BUY closed

    BuyClosed --> Trading: Reseed
    SellClosed --> Trading: Reseed

    Trading --> Paused: News Event
    Paused --> Trading: News Over

    Trading --> [*]: OnDeinit()
```

---

*Last Updated: October 2024*