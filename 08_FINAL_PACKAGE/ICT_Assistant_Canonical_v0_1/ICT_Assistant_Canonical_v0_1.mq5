//+------------------------------------------------------------------+
//| ICT_Assistant_Canonical.mq5  —  v0.1                                |
//| (lineage: ICT Assistant Pro / EAGLE EYE V13.2; بازطراحی معماری       |
//|  بر اساس ۲۰ ایراد ذکر شده روی V12.06)                                |
//|                                                                     |
//| هدف این نسخه: یک "ONE SOURCE OF TRUTH" برای ساختار/نقدینگی/         |
//| Displacement/FVG/OB/Breaker/DOL که همه با ID به هم زنجیر شده‌اند     |
//| (Causal Chain) به‌جای این‌که هرکدام جدا محاسبه شوند.                  |
//|                                                                     |
//| توجه صادقانه (بخوانید):                                             |
//|  - این فایل معماری را عمیقاً اصلاح می‌کند: Event Engine واحد،        |
//|    Liquidity Registry واحد، زنجیره Causal واقعی، Breaker منطقی.      |
//|  - مواردی مثل "No-Repaint اثبات‌شده" و "Determinism در Replay"       |
//|    (بندهای ۱۸ و ۱۹ گزارش) با نوشتن کد به‌تنهایی ثابت نمی‌شوند؛        |
//|    این فایل طوری نوشته شده که هیچ Event ای قبل از Confirm بار        |
//|    نمی‌شود (bar[1] فقط، نه bar[0])، اما تست نهایی را باید خودتان      |
//|    در Strategy Tester (Visual/Real Ticks) روی XAUUSD انجام دهید.     |
//|  - Setup/Signal/Entry/SL/TP در این نسخه پیاده‌سازی شده اما در حد      |
//|    یک قانون قابل‌توسعه (OTE + DOL narrative)، نه یک "سیستم معامله    |
//|    نهایی تضمین‌شده". لطفاً قبل از استفاده واقعی، حتماً بک‌تست کنید.    |
//+------------------------------------------------------------------+
#property copyright   "Khaleq Salehi — khaleq.sa@gmail.com — +989120143697"
#property link        "mailto:khaleq.sa@gmail.com"
#property description "ICT · SMC · MMM · Wyckoff · S&D · AMT · RTM · Brooks — اندیکاتور آموزشی و تحلیلی چند مکتبی: رسم روی چارت همراه با توضیح فارسی کامل زیر موس. نویسنده: خالق صالحی"
#property version   "1.01"            // MQL5 rejects a 0.x major (compiler warning 68) → the canonical core v0.1 is published as program version 1.01 (release v1.01: 32 family modules, fitted grade, single path row)
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

#define ICT_EVENT_LEDGER_BASE "ICT_Assistant_V13_Events_v1"   // فاز ۲۲: نام دفتر = base + "_" + نماد + ".csv" (چند نماد دیگر قاطی هم نمی‌شوند)
#define ICT_REPLAY_LEDGER "ICT_Assistant_Canonical_ReplayLedger.csv"

#include "modules/01_HeaderAndInputs.mqh"
#include "modules/02_Types.mqh"
#include "modules/03_GlobalState.mqh"
#include "modules/04_Utilities.mqh"
#include "modules/05_TimeBase.mqh"
#include "modules/06_MultiTimeframe.mqh"
#include "modules/07_AuctionProfile.mqh"
#include "modules/08_Lifecycle.mqh"
#include "modules/09_SwingAndStructure.mqh"
#include "modules/10_Liquidity.mqh"
#include "modules/11_Sweep.mqh"
#include "modules/12_Displacement.mqh"
#include "modules/13_FairValueGap.mqh"
#include "modules/14_OrderBlocks.mqh"
#include "modules/15_ReverseRisk.mqh"
#include "modules/16_HtfStructure.mqh"
#include "modules/17_Sessions.mqh"
#include "modules/18_LegAndDol.mqh"
#include "modules/19_SetupEngine.mqh"
#include "modules/20_SmcMmm.mqh"
#include "modules/21_ReversalGate.mqh"
#include "modules/22_LoadStamp.mqh"
#include "modules/23_Drawing.mqh"
#include "modules/24_RedrawReconcile.mqh"
#include "modules/25_Explain.mqh"
#include "modules/26_PersianRender.mqh"
#include "modules/27_Dashboard.mqh"
#include "modules/28_ClosedBarPipeline.mqh"
#include "modules/29_BehaviorSelfTest.mqh"
#include "modules/30_OnCalculate.mqh"
#include "modules/31_SignalGrade.mqh"
#include "modules/32_PendingScenario.mqh"
#include "modules/33_SymbolProfile.mqh"

//------------------------------------------------------------------
// بدنهٔ کد این اندیکاتور در پوشهٔ «modules/» است — یک فایل برای هر
// خانوادهٔ استراتژی. ترتیب includeها دقیقاً همان ترتیب اصلی است و
// پری‌پروسسور MQL5 این‌ها را در یک واحد کامپایل می‌چسباند، پس هیچ
// جابه‌جایی و هیچ تغییر منطقی رخ نداده است.
//
// فهرست ماژول‌ها و توضیح هرکدام: modules/README.md
// اثبات بایت‌به‌بایت برش:      tools/Verify-ModuleSplit.ps1
//------------------------------------------------------------------
