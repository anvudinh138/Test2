# Pseudo‑Code (language‑agnostic)

> Targets MQL5/MT5 or any event‑driven env. Names are descriptive; adapt to your SDK.

## Types
struct Params { /* see STRATEGY_SPEC.md §2 */ }
struct BasketState {
Direction dir; // BUY or SELL
List<Order> orders; // open orders
float total_lot;
float avg_price;
float pnl;
float tp_price; // group TP target (BE + δ)
bool tsl_on;
bool closed_recently;
int cycles_done;
price last_grid_price;
}

shell




## Services & Modules
IExecutor // place/modify/close orders atomically
ISpacing // compute spacing (pips/ATR/hybrid)
IRescueEngine // decides when to open hedge
ILedger // risk tracking (exposure/session SL)
IValidator // broker rules guard
ILogger // structured logs

shell




## Lifecycle
OnInit():
svc = Services(...)
A = BasketState(SELL); A.InitGrid(price_now)
B = BasketState(BUY); B.InitGrid(price_now)

OnTick():
price = GetPrice()
A.Refresh(price); B.Refresh(price)

rust



// Identify loser/winner
losing = (A.pnl < 0 ? A : None)
if B.pnl < (losing?.pnl ?? +INF): losing = (B.pnl < 0 ? B : losing)
winning = (losing == A ? B : (losing == B ? A : None))

// Rescue if needed
if losing != None and svc.rescue.ShouldRescue(losing, price):
    OpenOppositeRescue(winning, price)

// TP/TSL management
A.ManageTPandTSL(price)
B.ManageTPandTSL(price)

// Flip roles after a basket closed
if A.closed_recently: MaybeFlip(A, B, price)
if B.closed_recently: MaybeFlip(B, A, price)

// Safety
if svc.ledger.ExceedsLimits():
    CloseAll(); Halt()
shell




## Basket Methods
BasketState.InitGrid(start_price):
spacing = svc.spacing.Value()
PlaceMarket(dir, params.lot_base)
for k in 1..(params.grid_levels-1):
level_price = start_price ± k*spacing (± per dir)
PlaceLimit(dir, level_price, LotAt(k))
last_grid_price = outermost_limit_price()
RecomputeTargets()

BasketState.Refresh(price):
UpdateOrderFills()
total_lot = Σ lot(filled)
avg_price = Σ(l_i * p_i) / Σl_i // if Σl_i > 0
pnl = ComputePnL(dir, avg_price, price)
closed_recently = false

BasketState.ManageTPandTSL(price):
// Enable trailing for hedge baskets only (decide by controller flag)
if params.tsl_enabled and InProfitEnough(price) and !tsl_on:
tsl_on = true
if tsl_on:
TrailStop(price, params.tsl_step_points)

csharp



// Close basket if group TP reached
if pnl >= TargetForThisBasket() or PriceTouches(tp_price):
    svc.executor.CloseAll(orders)
    closed_recently = true
    cycles_done++
BasketState.RecomputeTargets():
tp_price = SolvePriceForPnL(target_cycle_usd) // BE + δ

shell




## Rescue Engine
bool ShouldRescue(BasketState losing, price):
condA = Breached(losing.last_grid_price, price, params.offset_ratio, spacing)
condB = losing.pnl <= -params.dd_open_usd
condC = CooldownOK() and ExposureOK() and losing.cycles_done < params.max_cycles_per_side
return (condA or condB) and condC

OpenOppositeRescue(BasketState winner, price):
// one market + optional staged limits (recovery_steps)
PlaceMarket(winner.dir, params.recovery_lot)
for d in params.recovery_steps:
PlaceLimit(winner.dir, price ± sign(winner.dir)*d, params.recovery_lot)
winner.tsl_on = false // will auto-enable when in profit enough

shell




## Utilities
LotAt(k): return params.lot_base * pow(params.lot_scale, k)
InProfitEnough(price): return MoveInFavourFrom(avg_price, price) >= params.tsl_start_points
TargetForThisBasket(): return params.target_cycle_usd (dynamically reduced by realized hedge profit)

shell




## Safety & Halt
if exposure > exposure_cap_lots or session_loss <= -session_sl_usd:
CloseAll(); DisableNewOrders()

pgsql


