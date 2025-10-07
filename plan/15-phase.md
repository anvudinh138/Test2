P0 — Baseline reset + Feature flags mặc định OFF

Goal: Chạy được build “rỗng” (chưa bật logic mới), không spam log.
Scope:

Giữ nguyên inputs nhưng đổi default = false cho Lazy/Trap/QE/Gap để không “kỳ vọng hành vi” khi chưa implement. (Trong 14-Phase-1.md đang mặc định = true → gây fail sớm.) 

14-Phase-1

 

14-Phase-1


Deliverables: Compile OK, backtest 1–2 ngày không lệnh mới.
Exit: Không crash, không mở lệnh từ modules mới.
Tests: Strategy Tester M1 1–2 ngày, tất cả feature OFF.
Rollback: Git tag baseline-reset.

Snippet (đổi default OFF trong Params.mqh):

// === Lazy Grid Fill ===
input bool InpLazyGridEnabled = false;
input int  InpInitialWarmLevels = 1;
input int  InpMaxLevelDistance = 500;
input double InpMaxDDForExpansion = -20.0;

// === Trap Detection ===
input bool   InpTrapDetectionEnabled = false;
input double InpTrapGapThreshold = 200.0;
input double InpTrapDDThreshold = -20.0;
input int    InpTrapConditionsRequired = 3;
input int    InpTrapStuckMinutes = 30;

// === Quick Exit ===
input bool   InpQuickExitEnabled = false;
input ENUM_QUICK_EXIT_MODE InpQuickExitMode = QE_FIXED;
input double InpQuickExitLoss = -10.0;
input double InpQuickExitPercentage = 0.30;
input bool   InpQuickExitCloseFar = true;
input bool   InpQuickExitReseed = true;
input int    InpQuickExitTimeoutMinutes = 60;

// === Gap Management ===
input bool   InpAutoFillBridge = false;
input int    InpMaxBridgeLevels = 5;
input double InpMaxPositionDistance = 300.0;
input double InpMaxAcceptableLoss = -100.0;


P1 — Observability: Logger + State & Metrics

Goal: Nhìn log là biết đang ở state nào và tại sao.
Scope: Chuẩn hóa Logger.mqh event types (TRAP, QE, BRIDGE, FAR_CLOSE, RESEED, EMERGENCY) + file log theo magic, như checklist bạn đã có. 

5-IMPLEMENTATION-PLAN


Deliverables: Logger hoạt động; PrintConfiguration() in toàn bộ inputs lúc khởi động (đã có khung trong Phase-5 cũ). 

14-Phase-5

 

14-Phase-5


Exit: Thấy log chuyển state, lý do guard/trigger rõ ràng.
Tests: Mock các state/trigger → log đúng.
Rollback: InpVerboseLog=false (nếu có) hoặc comment Log() tạm.

P2 — Test Harness & Presets

Goal: Có preset Range / Uptrend 300+ / Whipsaw / Gap-sideways để tái hiện bug lặp lại.
Scope: Script chạy backtest batch, xuất CSV KPI (MaxDD, traps, QE success). (Kịch bản test đã mô tả trong prompts của bạn.) 

11-AI-PROMPTS-FOR-IMPLEMENTATION


Deliverables: Folder /presets/ + hướng dẫn.
Exit: Repro được “Lazy fail” & “Gap fail” ổn định.
Tests: Chạy mỗi preset 1–2 ngày dữ liệu.
Rollback: Không cần.

P3 — Lazy Grid v1: Seed tối thiểu

Goal: 1 market + 1 pending sau seed, không nở thêm.
Scope: SeedInitialGrid() + SGridState (struct đã có trong Types). 

14-Phase-1


Deliverables: Log “Initial grid seeded”, đếm pending đúng.
Exit: Preset Range: chỉ có 2 lệnh ban đầu.
Tests: BUY/SELL seed như nhau.
Rollback: InpLazyGridEnabled=false.

P4 — Lazy Grid v2: Chỉ nở khi fill + Guards

Goal: Nở level sau fill và qua guards: counter-trend, DD, max-levels, distance.
Scope: OnLevelFilled()->ShouldExpandGrid(), dùng IsPriceReasonable() để chặn pending sai phía/xa quá; function này bạn đã phác trong plan. 

5-IMPLEMENTATION-PLAN


Deliverables: State ACTIVE/HALTED/GRID_FULL đổi đúng, log lý do.
Exit: Preset Uptrend 300p: SELL dừng mở rộng sớm.
Tests: Bật/tắt từng guard xem hành vi.
Rollback: Tạm disable từng guard qua input ngưỡng.

P5 — Trap Detector v1 (3 điều kiện core)

Goal: Kích hoạt TRAP khi đạt ngưỡng (Gap + Counter-trend + Heavy DD).
Scope: Class CTrapDetector với 3 check đầu, counting >= InpTrapConditionsRequired (mặc định 3/5), log “TRAP DETECTED … Conditions x/5”. Bạn đã có khung code & prompts. 

5-IMPLEMENTATION-PLAN

 

11-AI-PROMPTS-FOR-IMPLEMENTATION

 

14-Phase-2


Deliverables: DetectTrapConditions() chạy trong GridBasket.Update(). 

5-IMPLEMENTATION-PLAN


Exit: Preset Uptrend 300p: trap SELL được phát hiện.
Tests: Range không báo trap.
Rollback: InpTrapDetectionEnabled=false hoặc tăng InpTrapConditionsRequired.

P6 — Trap Detector v2 (Moving-Away + Stuck)

Goal: Giảm false positives bằng 2 điều kiện còn lại (theo code mẫu). 

14-Phase-2

 

14-Phase-2


Scope: Track 5 phút & khoảng cách avg tăng >10%; oldest pos > InpTrapStuckMinutes & DD < −15%.
Deliverables: TrapState điền đủ cờ/metrics.
Exit: Range dài không trigger trap.
Tests: Unit từng condition.
Rollback: Tắt 2 condition mới bằng flag nội bộ.

P7 — Quick Exit v1: QE_FIXED + TP âm

Goal: Khi trap, kích hoạt QE_FIXED (nhận lỗ nhỏ: −$10) và hỗ trợ TP âm.
Scope: ActivateQuickExitMode() → backup target, set target âm, recalc TP; integrate từ prompt của bạn. 

11-AI-PROMPTS-FOR-IMPLEMENTATION

 

7-PSEUDOCODE


Deliverables: Log kích hoạt QE, TP mới gần hơn.
Exit: Preset Uptrend 300p: thoát trap bằng QE (lỗ nhỏ), reseed nếu bật.
Tests: BUY/SELL đều QE được; validate công thức TP âm.
Rollback: InpQuickExitEnabled=false.

P8 — Quick Exit v2: Percentage/Dynamic + Timeout + CloseFar

Goal: Hoàn thiện QE: 3 mode (Fixed/Percentage/Dynamic), timeout, đóng vị thế xa khi QE.
Scope: Thêm InpQuickExitTimeoutMinutes, InpQuickExitCloseFar; sau close-far recalculate basket metrics như hướng dẫn. 

11-AI-PROMPTS-FOR-IMPLEMENTATION


Deliverables: QE log đầy đủ: target, TP, distance, timeout/deactivate.
Exit: Preset Gap-sideways: thời gian thoát giảm đáng kể.
Tests: Timeout → restore target/state; close-far xong TP/avg cập nhật.
Rollback: Về QE_FIXED, tắt close-far.

P9 — Gap Management v1: CalculateGapSize + Bridge (200–400)

Goal: Đo gap chuẩn (max khoảng cách liên tiếp) & điền cầu khi 200–400 pips.
Scope: Tích hợp block “Check gap and manage” ở GridBasket.Update() (đoạn bạn đã có). 

5-IMPLEMENTATION-PLAN

 

5-IMPLEMENTATION-PLAN


Deliverables: Log gap size + từng bridge level được đặt.
Exit: Preset Gap-sideways: bridge hợp lý, không đặt giá vô lý.
Tests: Validate BUY dưới/SELL trên current (IsPriceReasonable). 

5-IMPLEMENTATION-PLAN


Rollback: InpAutoFillBridge=false.

P10 — Gap Management v2: CloseFar (>400) + Reseed điều kiện

Goal: Gap lớn → đóng vị thế xa (nếu loss chấp nhận), reseed khi còn <2.
Scope: Theo checklist “Close far positions / Reseed / Price validation” trong prompts & plan. 

11-AI-PROMPTS-FOR-IMPLEMENTATION

 

5-IMPLEMENTATION-PLAN


Deliverables: Log tổng loss khi đóng xa + metrics sau recalc.
Exit: Preset Uptrend kéo dài: DD không phình, có lối thoát.
Tests: Đúng ngưỡng 300–400/ >400; TP/avg cập nhật chính xác.
Rollback: Tắt close-far, chỉ QE.

P11 — Lifecycle Controller: Profit sharing + Global risk

Goal: Basket TP → reduce target basket kia (x2 nếu bên kia đang QE); Emergency khi cả hai “trouble”.
Scope: Update() / HandleBasketClosures() / CheckGlobalRisk() như code checklist pha 4. 

14-Phase-4

 

14-Phase-4

 

5-IMPLEMENTATION-PLAN


Deliverables: Log x2 help khi basket kia đang QE; emergency protocol rõ ràng.
Exit: Preset Whipsaw: vòng đời mượt, không double-exposure kéo dài.
Tests: Đóng BUY giúp SELL (x2) & ngược lại; emergency đóng giỏ xấu hơn.
Rollback: Tắt multiplier (reduce = 1×).

P12 — Parameters & Presets theo symbol

Goal: Bề mặt tham số rõ ràng + presets an toàn (majors/XAU/indices).
Scope: Dựa bảng ngưỡng đã đúc rút (Gap 150–200 monitor; 200–400 bridge; >400 close-far; DD trap −20%; stuck 30’…). 

12-UPDATED-CLAUDE


Deliverables: .set cho 3–4 symbol phổ biến.
Exit: Load preset chạy ổn, ít chỉnh tay.
Tests: Sanity backtest 1–2 tuần/symbol.
Rollback: Preset “Conservative”.

P13 — Backtest Burn-in + Guardrails

Goal: 3 tháng dữ liệu: đo MaxDD, TrapEscapeRate, AvgLossPerTrap, AvgTimeToQE.
Scope: Kịch bản test & regression như prompts (5 test chính + regression). 

11-AI-PROMPTS-FOR-IMPLEMENTATION


Deliverables: CSV/Markdown + biểu đồ so sánh trước/sau.
Exit: DD ↓ 50–70% vs cũ; TrapEscapeRate ≥~80% (mục tiêu).
Tests: A/B bật/tắt QE và Gap Management.
Rollback: Giảm nhạy trap/QE nếu KPI xấu.

P14 — Main EA Integration

Goal: Nối Lifecycle + Logger + NewsFilter; hourly perf logs + print config.
Scope: Áp dụng RecoveryGridDirection_v3.mq5 như phase-5 cũ (OnInit/OnTick/OnDeinit + PrintConfiguration() + LogPerformanceMetrics()). 

14-Phase-5

Deliverables: EA chạy được end-to-end với flags.
Exit: Không crash, metrics in theo giờ.
Tests: Tắt NewsFilter vs bật; kiểm đồng bộ 2 baskets.
Rollback: Quay về tag trước integration.

P15 — Hardening, Docs & Release

Goal: Làm sạch module (tách helpers QE/Gap), viết docs & changelog.
Scope: Dựa prompts: User Guide / Technical docs / Testing report / Deployment checklist / Changelog 3.1.0. 

11-AI-PROMPTS-FOR-IMPLEMENTATION


Deliverables: Tag v3.1.0 + CHANGELOG.
Exit: Toàn bộ preset & regression pass xanh.
Tests: Re-run toàn bộ presets + 1 tuần demo ổn.