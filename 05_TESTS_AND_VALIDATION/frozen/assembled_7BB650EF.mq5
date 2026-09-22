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
#property version   "1.00"            // MQL5 rejects a 0.x major (compiler warning 68) → canonical core v0.1 is published as program version 1.00
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

#define ICT_EVENT_LEDGER_BASE "ICT_Assistant_V13_Events_v1"   // فاز ۲۲: نام دفتر = base + "_" + نماد + ".csv" (چند نماد دیگر قاطی هم نمی‌شوند)
#define ICT_REPLAY_LEDGER "ICT_Assistant_Canonical_ReplayLedger.csv"

//====================================================================
// INPUTS
//====================================================================
input group "== Timeframes =="
input ENUM_TIMEFRAMES InpHTF          = PERIOD_H4;    // HTF (Bias / Protected Structure)
input ENUM_TIMEFRAMES InpMTF          = PERIOD_H1;    // تایم‌فریم «ساختار داخلی» (مستقل از InpTF_Context1)
// LTF = تایم‌فریم چارت جاری (که اندیکاتور رویش نصب شده)

input group "== Structure =="
input int    InpSwingLeft             = 3;            // کندل سمت چپ برای تایید Pivot
input int    InpSwingRight            = 3;            // کندل سمت راست برای تایید Pivot (No-Repaint => فقط بعد از این‌که تایید شد ثبت می‌شود)
input int    InpMaxSwings             = 300;          // حداکثر Swing نگه‌داری‌شده در حافظه

input group "== Liquidity =="
input double InpEQ_Tolerance_Points   = 15;           // تلورانس EQH/EQL بر حسب پوینت
input double InpEQ_ToleranceATR        = 0.15;         // کف تلورانس EQH/EQL به نسبت ATR (0=غیرفعال)
// فاز ۳۰ (#۷۷): «جدایی» بین دو عضو خوشهٔ EQH/EQL.
// منبع (LuxAlgo — Equal Highs/lows As Liquidity، مرحلهٔ ۲): «Require separation:
// a meaningful pullback between the swings, so they read as distinct tests rather
// than one drawn-out top». قاعده از منبع است؛ عدد پیش‌فرض یک نقطهٔ شروع قابل
// تنظیم است، نه یک مقدار مستند (با InpEQ_MinSeparationATR = 0 خاموش می‌شود).
input double InpEQ_MinSeparationATR     = 0.0;         // عمق پس‌رفتِ لازم بین دو عضو خوشه (× ATR). ۰ = فقط شرط ساختاری (عمق حداقل برابر تلورانس)

input group "== Phase 32: Reverse-risk evidence (ریسک برگشت — شاهد، نه درصد حدسی) =="
input bool   InpEnableReverseRisk   = true;   // محاسبهٔ «ریسک برگشت» در هر کندل بسته
input bool   InpWriteReverseRisk    = true;   // نوشتن ICT_Assistant_Canonical_ReverseRisk_<symbol>.csv در COMMON\\Files
input int    InpMaxLiquidity          = 400;          // حداکثر آبجکت Liquidity در Registry

// فاز ۳۵: نوار تک‌خطی «کجا ایستاده‌ای» — بدون داشبورد، بدون CSV، بدون شلوغی.
// فقط سه چیز روی یک خط: جهت Bias، نزدیک‌ترین سطح (نوع + وضعیت + فاصله) و امتیاز برگشت.
input group "== Phase 35: Risk strip (نوار تک‌خطی ریسک برگشت) =="
input bool   InpShowRiskStrip        = true;   // نمایش نوار گوشهٔ بالا-چپ
// فاز ۴۶: درجهٔ سیگنال A+/A/B+/B/C که در همان نوار، ابتدای ردیف نشان داده
// می‌شود. ضرایبش سنجیده‌شده است (tools/Fit-SignalGrade.ps1) و خاموش‌کردنش
// فقط همان بخش را از نوار برمی‌دارد، نه محاسبهٔ ریسک برگشت را.
input bool   InpEnableSignalGrade    = true;   // فعال‌سازی درجهٔ سیگنال در نوار
input int    InpRiskStripY           = 2;      // فاصلهٔ نوار از لبهٔ بالا (پیکسل)
input int    InpRiskStripWidth       = 640;    // عرض نوار (پیکسل؛ به عرض چارت محدود می‌شود)

// فاز ۳۰ (#۷۵): مرز روز/هفته برای PDH/PDL/PWH/PWL.
// منبع (LuxAlgo — ICT Time Anchors): «The day's high and low are measured from
// the midnight open» و «Midnight New York time (00:00 ET), not midnight UTC, not
// the 5:00 pm forex rollover». یعنی مرز روز در ICT نیمه‌شب نیویورک است، نه مرز
// کندل روزانهٔ بروکر (که نیمه‌شب سرور است) — همان «خطای کلاسیک علامت‌گذاری».
enum ENUM_PD_ANCHOR { PD_ANCHOR_NY_MIDNIGHT, PD_ANCHOR_NY_1700, PD_ANCHOR_BROKER_DAY };
input ENUM_PD_ANCHOR InpPD_Anchor      = PD_ANCHOR_NY_MIDNIGHT; // مرز روز/هفته: نیویورک ۰۰:۰۰ (استاندارد ICT) / نیویورک ۱۷:۰۰ / کندل بروکر

input group "== Displacement =="
input double InpDisp_BodyRatio        = 0.65;         // حداقل Body/Range برای کاندید Displacement
input double InpDisp_RangeVsAvg       = 1.5;          // حداقل Range/ATR برای کاندید Displacement
input int    InpATR_Period            = 14;

input group "== Brooks Range/MM (فاز ۳۶) =="
input bool   InpEnableBrooksRange    = true;         // Trading Range دوطرفه + مغناطیس ۵۰٪ + هدف Measured Move (AB=CD)

input group "== Quarterly Theory (Trader Daye — فاز ۳۶) =="
input bool   InpEnableQT             = true;         // Quarterly Theory: ربع‌های AMD-X + True Open (ساعت نیویورک)
input bool   InpDrawQTOpens          = true;         // خط‌چین True Open روز (نیمه‌شب NY) و هفته (دوشنبه NY) — دو خط، بدون شلوغی

input group "== FVG / OB =="
input int    InpMaxFVG                = 150;
input int    InpMaxOB                 = 150;
input int    InpFVG_ExpireBars        = 500;          // بعد از این تعداد بار اگر لمس نشد Invalid می‌شود (0=غیرفعال)
input bool   InpOBUseFullCandleRange   = false;         // true = ناحیه OB کل کندل، false = فقط بدنه
// فاز ۲۹ (#۷۳): قاعدهٔ OB «آخرین کندل مخالف‌رنگ قبل از Displacement» سقف ثابت
// ندارد (منبع: LuxAlgo — Order Block: «Step back to the last opposite candle»).
// قبلاً این جست‌وجو با عدد ثابت ۶ در کد هارد‌کد بود و در رالی‌های کند (که
// چند کندل هم‌رنگ قبل از Displacement هستند) هیچ OB یافت نمی‌شد.
input int    InpOB_LookbackBars        = 6;            // حداکثر کندل عقب‌تر برای یافتن کندل مخالفِ مبدأ OB

input group "== Sessions (NY clock — این ورودی‌ها زنده‌اند و واقعاً اعمال می‌شوند) =="
input int    InpBrokerToNY_HourOffset = -7;           // مرجع/fallback: اختلاف ساعت بروکر با نیویورک (تنظیم کنید!) — تشخیص خودکار و DST بر این مقدم‌اند
input int    InpAsiaStartHourNY       = 20;           // Asian KZ شروع (ساعت نیویورک)
input int    InpAsiaEndHourNY         = 0;            // Asian KZ پایان (۰ = نیمه‌شب؛ عبور از نیمه‌شب پشتیبانی می‌شود)
input int    InpLondonStartHourNY     = 2;            // London KZ شروع (Judas / Manipulation)
input int    InpLondonEndHourNY       = 5;            // London KZ پایان
input int    InpNY_KZ_StartHourNY     = 7;            // New York AM KZ شروع
input int    InpNY_KZ_EndHourNY       = 10;           // New York AM KZ پایان

input group "== Time Base (real broker offset + NY clock) =="
input int    InpBrokerGMTOffsetOverrideHours = 99;    // آفست بروکر->GMT (ساعت) ؛ 99 = تشخیص خودکار
input bool   InpUseUS_DSTForNYClock           = true; // اعمال قواعد DST آمریکا روی ساعت نیویورک

input group "== Killzones / Session Ranges (NY time) =="
input ENUM_TIMEFRAMES InpSessionSourceTF      = PERIOD_M15; // منبع محاسبه رنج سشن‌ها (مستقل از چارت)
input int    InpKillzoneDaysBack              = 2;    // باکس‌های سشن چند روز آخر (قبلاً ۳)
// بازبینی نمایش (2026-09-18): باکس‌های سشن «تزئینی»‌اند — سشن/کیلیزون فعال از قبل
// در داشبورد و در محاسبات (SESS/AMD/SB) لحاظ می‌شود؛ پس پیش‌فرض رسم خاموش شد.
input bool   InpDrawKillzoneBoxes             = false; // قبلاً true
input bool   InpDrawAsianRange                = false; // قبلاً true — رنج آسیا هدف نقدینگی لندن است و در نقدینگی سشنی (LIQ_SESSION) محاسبه می‌شود
input bool   InpDrawSilverBullet              = false; // قبلاً true — پنجرهٔ SB خودش سیگنال نیست (تولتیپ خودش می‌گوید)؛ وضعیت SB در داشبورد هست

input group "== Display (what to draw on chart) =="
input bool   InpDrawLiquidity                 = true;  // ضروری: نقشهٔ نقدینگی = هدف ترید
input bool   InpDrawSweepMarkers              = true;  // ضروری: کجا استاپ‌ها خوردند (تأیید Manipulation)
input bool   InpDrawFVGZones                  = true;  // ضروری: ناحیهٔ ورود
input bool   InpDrawOBZones                   = true;  // ضروری: ناحیهٔ ورود
input bool   InpDrawStructureEvents           = true;  // ضروری: BOS/CHoCH جهت‌ساز
input bool   InpDrawMTFRange                  = true;  // ضروری: سطوح محافظت‌شدهٔ هر تایم‌فریم (مبنای ابطال)
input bool   InpDrawSetupBox                  = true;  // ضروری: باکس ورود + Entry/SL/TP
input bool   InpDrawOnlyCausalFVG             = true;  // قبلاً false — FVG زنجیره‌نشدهٔ Displacement نویز است؛ کشف کامل در رجیستری/CSV می‌ماند
input int    InpMaxDrawnLevels                = 14;   // چارت خلوت‌تر (قبلاً ۳۰)
input int    InpMaxDrawnZones                 = 8;    // چارت خلوت‌تر (قبلاً ۱۴)
input int    InpZoneExtendBars                = 12;   // طول نمایش ناحیه‌ها بر حسب کندل (قبلاً ۲۰)
// برچسب متنی روی سطوح = دوبرابرشدن آبجکت هر سطح (خط + متن). متن tooltip همان
// اطلاعات را دارد؛ داشبورد هم labelها را نشان می‌دهد → تزئینی، پیش‌فرض خاموش.
input bool   InpDrawLevelLabels               = false; // قبلاً true

input group "== MTF chain (each role has its own timeframe) =="
input ENUM_TIMEFRAMES InpTF_Bias              = PERIOD_H4;
input ENUM_TIMEFRAMES InpTF_Context1          = PERIOD_H1;
input ENUM_TIMEFRAMES InpTF_Context2          = PERIOD_M15;
input ENUM_TIMEFRAMES InpTF_Setup             = PERIOD_M5;
input ENUM_TIMEFRAMES InpTF_Confirm1          = PERIOD_M2;
input ENUM_TIMEFRAMES InpTF_Confirm2          = PERIOD_M1;

input group "== Explain Mode (indicator + teacher) =="
input bool   InpShowExplainPanel               = true;   // پنل توضیح با بردن موس روی آبجکت
input int    InpExplainPanelWidth              = 580;
input int    InpExplainFontSize                = 9;
input int    InpExplainMaxRows                 = 30;
input int    InpExplainHoverTolPx              = 8;
input string InpExplainFont                    = "Tahoma"; // فونتی که گلیف فارسی دارد
input bool   InpWriteExplainCsv                = true;   // ذخیرهٔ توضیح‌ها در CSV برای بررسی
input bool   InpSetObjectTooltips              = false;  // فاز ۲۵: پیش‌فرض خاموش — tooltip روی «هر» آبجکت یعنی روی همهٔ چارت باز می‌شد و هم پنل را می‌پوشاند. پنل تنها کانال توضیح است؛ true = فعال‌کردن tooltip آموزشی
// رندرگر آبجکت‌های چارت در buildهای اخیر MT5 دیگر bidi ندارد (گزارش رسمی انجمن MQL5)،
// بنابراین پیش‌فرض ۲ است: حروف با شکل‌های چسبیده (Presentation Forms) نوشته و ترتیب
// رشته به ترتیب بصری راست‌به‌چپ برگردانده می‌شود. اگر buildی داشتی که خودش bidi دارد، 0.
// فاز ۲۷ — ریشهٔ «فارسی کامل به‌هم‌ریخته»: پنل با OBJ_EDIT رسم می‌شود و OBJ_EDIT یک
// کنترل **بومی ویندوز** است که خودش bidi و شکل‌دهی حروف را انجام می‌دهد (همین
// کنترل قبلاً متن خام فارسی را درست نشان داده بود). پس تبدیل دستی متن
// (شکل‌دهی + ترتیب بصری) روی آن **دو بار تبدیل** می‌ساخت و حاصل به‌هم‌ریخته بود.
// پیش‌فرض ۰ = متن خام منطقی؛ همان چیزی که تأیید شده بود. حالت‌های ۱/۲/۳ فقط
// برای buildی مانده‌اند که خودش bidi ندارد — روی آن‌ها می‌شود ۲ را امتحان کرد.
input int    InpExplainRenderMode              = 0;      // 0=پیش‌فرض: متن خام منطقی (OBJ_EDIT خودش RTL را می‌چیند) | 2=شکل‌دهی+ترتیب بصری | 1=فقط ترتیب بصری | 3=RLE..PDF
input int    InpExplainTooltipMaxChars         = 220;   // سقف طول متن آموزشی tooltip روی خود آبجکت (فاز ۲۲)
// فاز ۴۱ — قاعدهٔ RTL: واژهٔ لاتینِ وسط جملهٔ فارسی، جمله را به دو قطعهٔ
// راست‌به‌چپ می‌شکند و ترتیبشان جابه‌جا می‌شود (OBJ_EDIT جهت پایه را از
// اولین کاراکتر قوی می‌گیرد). با این گزینه هر واژهٔ لاتین به ابتدای خط
// منتقل می‌شود تا متن فارسی یکپارچه بماند. ارقام دست‌نخورده می‌مانند.
input bool   InpExplainLatinFirst              = true;   // انتقال واژه‌های لاتین به ابتدای خط (بدون شکستن جملهٔ فارسی)

input group "== History rebuild on attach =="
input bool   InpRebuildHistoryOnAttach        = true;
input int    InpHistoryScanBars               = 600;
input bool   InpWriteLedgerDuringRebuild      = false; // ثبت رویدادهای بازسازی در دفتر (برای شواهد زنده false)
input bool   InpWriteReplayDiagnostics         = false; // ثبت MTF/Replay diagnostics در Common\Files
input bool   InpResetReplayDiagnostics         = false; // فقط با فعال‌سازی صریح فایل diagnostic را از نو شروع کن

input group "== Exhaustion / Trend Phase =="
input int    InpExhaustionLookback    = 8;     // تعداد کندل بسته برای سنجش ضعف
input int    InpExhaustionWatchScore  = 3;     // آستانه هشدار
input int    InpExhaustionRangeScore  = 5;     // آستانه Range/Transition
input double InpExhaustionWeakRangeRatio = 0.75; // افت Range نسبت به میانگین بسته
input double InpExhaustionNearDOL_ATR    = 2.0;  // فاصلهٔ هشدار از DOL بر حسب ATR

input group "== Setup / Signal =="
input bool   InpEnableSetupEngine     = true;
input double InpOTE_Low               = 0.62;
input double InpOTE_High              = 0.79;
input double InpRR_TP1                = 1.0;
input double InpRR_TP2                = 2.0;
input double InpRR_TP3                = 3.0;

input group "== Dashboard =="
// داشبورد پیش‌فرض خاموش است تا چارت خالی و تمیز بماند.
// آموزش روی خود آبجکت‌ها (tooltip + پنل توضیح با بردن موس) کار می‌کند و نیازی به کادر
// گزارش ندارد. برای برگرداندن داشبورد همین یک ورودی را true کن.
input bool   InpShowDashboard         = false;
input int    InpDashX                 = 15;
input int    InpDashY                 = 25;
input color  InpDashBg                = clrBlack;
input color  InpDashText              = clrWhite;
input color  InpColorBull             = clrLime;
input color  InpColorBear             = clrOrangeRed;
input color  InpColorNeutral          = clrSilver;

// داشبورد راهنما باشد نه گزارش کامل — حالت COMPACT
// فقط ردیف‌های تصمیم ترید را نشان می‌دهد (Bias، جهت داخلی، سشن، چرخه، DOL،
// مکان، ستاپ/انتظار، هشدارها) و همهٔ شمارنده‌های تشخیصی به حالت FULL می‌روند.
input bool   InpDashCompact           = true;  // داشبورد کم‌حجم: فقط ردیف‌های تصمیم (false = گزارش کامل قبلی)

input group "== Session windows — advanced overrides (NY clock) =="
input int    InpLondonCloseStartHourNY = 10;   // London Close KZ شروع (ساعت نیویورک)
input int    InpLondonCloseEndHourNY   = 12;   // London Close KZ پایان
input int    InpNYPM_StartHourNY       = 13;   // NY PM KZ شروع
input int    InpNYPM_StartMinuteNY     = 30;   // NY PM KZ شروع (دقیقه)
input int    InpNYPM_EndHourNY         = 16;   // NY PM KZ پایان
input int    InpNYPM_EndMinuteNY       = 0;    // NY PM KZ پایان (دقیقه)
input int    InpSB1_StartHourNY        = 3;    // Silver Bullet #1 شروع (ساعت نیویورک)
input int    InpSB1_EndHourNY          = 4;    // Silver Bullet #1 پایان
input int    InpSB2_StartHourNY        = 10;   // Silver Bullet #2 شروع
input int    InpSB2_EndHourNY          = 11;   // Silver Bullet #2 پایان
input int    InpSB3_StartHourNY        = 14;   // Silver Bullet #3 شروع
input int    InpSB3_EndHourNY          = 15;   // Silver Bullet #3 پایان

// --- فاز ۱۰: لگ واقعی، OTE، SL و R:R ---
input group "== Phase 10: Dealing Leg / OTE / SL / RR =="
input double InpMinLegATR              = 1.0;  // حداقل اندازهٔ لگ واقعی نسبت به ATR (کمتر = لگ بی‌ارزش)
input double InpOTE_Golden             = 0.705;// نقطهٔ طلایی OTE (۷۰٫۵٪ ریتریس لگ)
input double InpSL_MinATR              = 0.5;  // بافر SL: نسبت به ATR کندل تحلیل
input int    InpSL_MinPoints           = 20;   // بافر SL: کف مطلق به پوینت
input double InpMinRR                 = 1.5;  // حداقل R:R واقعی (entry→SL در برابر TP3/DOL)
input int    InpChainLookbackBars      = 96;   // پنجرهٔ تازگی زنجیرهٔ Sweep→Displacement→شکست ساختار
input double InpDOL_MinRoomATR         = 1.0;  // حداقل فاصلهٔ DOL برای ساختن R:R واقعی
input double InpDOL_FarATR             = 10.0; // بالای این فاصله، امتیاز «نزدیکی» صفر می‌شود
input bool   InpRequireSetupTFZone     = true; // ناحیهٔ ورود از تایم‌فریم SETUP (M5) ترجیح داده شود (#۶۶)

// --- فاز ۱۱: دروازهٔ برگشت تأییدشده و Smart Money Reversal ---
input group "== Phase 11: Confirmed Reversal Gate / Smart Money Reversal =="
input bool   InpEnableReversalGate       = true; // دروازهٔ برگشت: فقط با بسته‌شدن فراتر از سطح محافظت‌شدهٔ خارجی
input int    InpReversalFreshBars        = 3;    // چند کندل چارت پس از تأیید، برگشت «تازه» شمرده می‌شود
input int    InpSMR_SweepLookbackBars    = 12;   // پنجرهٔ جست‌وجوی Sweep نقدینگی مقابل (بر حسب کندل HTF)
input int    InpSMR_MinScore             = 3;    // حداقل شواهد از ۴ برای تأیید Smart Money Reversal
input bool   InpDrawReversalLevel        = true; // رسم سطح محافظت‌شدهٔ خارجی و خط تأیید برگشت
input bool   InpWriteReversalDiagnostics = true; // نوشتن دفترهای تشخیصی در COMMON\Files

// --- فاز ۱۲: تکمیل پوشش SMC / MMM ---
input group "== Phase 12: SMC/MMM coverage =="
input bool   InpEnablePhase12        = true;         // کل لایهٔ فاز ۱۲
input bool   InpDetectImpliedFVG     = true;         // #۳۰ گپ Implied بر مبنای بدنه (close کندل ۱ ↔ open کندل ۳)
input bool   InpDetectMicroFVG       = true;         // #۳۱ گپ Micro روی تایم‌فریم پایین‌تر داخل محدودهٔ کندل Displacement
input ENUM_TIMEFRAMES InpMicroTF     = PERIOD_M1;    // تایم‌فریم تشخیص Micro FVG
input int    InpMicroBarsPerDisp     = 20;           // حداکثر کندل Micro بررسی‌شده برای هر کندل Displacement
input double InpOB_ExtremeATR        = 0.5;          // #۳۵ فاصلهٔ مجاز ناحیه تا اکسترمم لگ برای برچسب Extreme (× ATR)
input bool   InpDetectTrendlineLiq   = true;         // #۱۹ نقدینگی مورب روی دو سوئینگ تأییدشده
input double InpTrendlineTolATR      = 0.35;         // تلورانس نشستن سویینگ روی خط (× ATR)
// فاز ۳۰ (#۷۶) — منبع (LuxAlgo — Trendline Liquidity، مرحلهٔ ۱): «a clean line
// with three or more respected touches». خط دو-لمسی ضعیف‌تر است و در ICT «استخر
// نقدینگی مورب» کم‌ارزش‌تری دارد. حد کمتر از ۲ بی‌معناست (خود دو آنکر روی خطند).
input int    InpTrendlineMinTouches  = 3;            // حداقل سویینگ تأییدشده روی خط روند
input double InpTrendlineBreakATR    = 0.25;         // عبور بسته‌شدهٔ این مقدار فراتر از خط = ابطال خط (× ATR)
input int    InpMaxTrendlines        = 20;           // سقف رجیستری Trendline
input bool   InpDetectRangeLiquidity = true;         // #۲۰ نقدینگی مرزهای رنج
input double InpRangeMaxATR          = 3.0;          // حداکثر ارتفاع رنج قابل قبول (× ATR)
input int    InpRangeMinTouches      = 3;            // حداقل سوئینگ روی هر مرز رنج
input int    InpRangeLookbackSwings  = 24;           // چند سویینگ آخر برای تحلیل رنج
input bool   InpDetectIPDA           = true;         // #۶۵ سطوح IPDA (Old High/Low ۲۰/۴۰/۶۰ روزه)
input bool   InpBuildPOIRegistry     = true;         // #۴۷ رجیستری POI یکپارچه
input int    InpMaxPOI               = 60;           // سقف رجیستری POI
input int    InpPOI_AgeDecayBars     = 24;           // هر چند کندل چارت، یک امتیاز کهنگی POI کم شود
input int    InpPreferredEntryModel  = 0;            // #۶۷ 0=خودکار، 1=ICT2022، 2=BOS/FVG/OB، 3=Sweep Entry، 4=OTE
input int    InpMinQualityScore      = 6;            // #۶۸ حداقل امتیاز کیفیت از ۱۰ برای READY
input int    InpInternalWindowBars   = 30;           // #۳ چند کندل HTF برای ساختار داخلی همان تایم‌فریم مالک
input int    InpTrendYoungBars       = 6;            // #۹ سن کمتر از این تعداد کندل HTF = فاز شروع روند

// --- فاز ۱۳: پایداری و کارایی (#۷ #۱۱ #۱۲) ---
input group "== Phase 13: stability & performance =="
input int    InpMaxEvents            = 400;          // #۱۱ سقف رجیستری رویداد ساختاری (FIFO — قدیمی‌ترین حذف می‌شود)
input int    InpMaxDisplacements     = 400;          // #۱۱ سقف رجیستری Displacement (FIFO)
input int    InpMaxRejections        = 50;           // سقف رجیستری Rejection Block (قبلاً ۵۰ هاردکد بود)
input bool   InpLogPerfOnRebuild     = true;         // نوشتن زمان بازسازی و شمارنده‌های فاز ۱۳ در Journal

// --- فاز ۱۴: redraw آشتی‌جویانه (تاریخچهٔ نمایش) و سلامت متن داشبورد ---
// این گروه هم در **انتهای** لیست ورودی‌ها اضافه شده است تا اندیس ورودی‌های
// قبلی عوض نشود و ست‌های ذخیره‌شدهٔ چارت کاربران جابه‌جا نشود (قانون ۱۴).
input group "== Phase 14: reconciling redraw & dashboard text health =="
input bool   InpFrozenHistoryEnabled    = true;        // نگه‌داشتن تاریخچهٔ رسم‌شده (خارج از سقف نمایش) به‌سبک frozen
input int    InpMaxFrozenObjects        = 300;         // سقف آبجکت‌های frozen (سیاست FIFO)
input color  InpFrozenColor             = clrDimGray;  // رنگ آبجکت frozen
input int    InpDashMaxWidth            = 0;           // ۰ = عرض خودکار از اندازهٔ واقعی متن؛ >۰ = سقف عرض و شکستن خط بلند
input int    InpDashLineHeight          = 16;          // ارتفاع هر ردیف داشبورد (پیکسل)
input bool   InpWritePhase14Diagnostics = true;        // نوشتن ICT_Assistant_Canonical_Phase14_Diag.csv
input bool   InpLogPhase14OnRedraw      = true;        // نوشتن شمارنده‌های فاز ۱۴ در Journal

// --- فاز ۱۵: آفست تاریخی بروکر (DST تاریخی) و چرخهٔ عمر ستاپ ---
// قاعدهٔ DST بروکر: بروکر آفستش را با DST عوض می‌کند، ولی MT5 فقط آفست *جاری*
// را می‌دهد. برای تحلیل تاریخچه باید قاعدهٔ DST بروکر معلوم باشد تا آفست هر
// لحظهٔ گذشته بازسازی شود (قاعدهٔ ثبت‌شدهٔ پروژه: تحلیل تاریخی همیشه با آفست امروز).
enum ENUM_BROKER_DST_RULE
{
   BDST_AUTO,   // تخمین از خانوادهٔ آفست جاری بروکر (+0..+3 → اروپا، −4/−5 → آمریکا، بقیه بدون DST)
   BDST_US,     // قاعدهٔ آمریکا: دومین یکشنبهٔ مارس ۰۲:۰۰ محلی → اولین یکشنبهٔ نوامبر ۰۲:۰۰ محلی
   BDST_EU,     // قاعدهٔ اروپا: آخرین یکشنبهٔ مارس ۰۱:۰۰ UTC → آخرین یکشنبهٔ اکتبر ۰۱:۰۰ UTC
   BDST_NONE    // بروکر DST ندارد (مثل GMT+5:30 / GMT+7 / GMT+10)
};
input group "== Phase 15: historical DST offset, setup lifecycle, HTF events =="
input ENUM_BROKER_DST_RULE InpBrokerDSTRule        = BDST_AUTO; // قاعدهٔ DST بروکر برای بازسازی آفست تاریخی
input bool   InpUseHistoricalBrokerOffset = true;  // آفست هر لحظهٔ تاریخی محاسبه شود (false = رفتار قدیمی: آفست امروز)
input bool   InpTrackSetupLifecycle       = true;  // #۶۶ ثبت ابطال ستاپ با عبور بستهٔ قیمت از SL
input bool   InpDrawHTFEvents             = true;  // رسم رویداد ساختاری HTF روی چارت (قبلاً هیچ آبجکتی نداشت)
input int    InpMaxDrawnHTFEvents         = 4;     // سقف رسم رویداد HTF (قبلاً ۸)
input bool   InpWritePhase15Diagnostics   = true;  // نوشتن ICT_Assistant_Canonical_Phase15_Diag.csv

// --- فاز ۲۶: توضیح آموزشی «کلیدمحور» ---
// چارت پیش‌فرض باید کاملاً تمیز باشد: تا وقتی کاربر خودش کلید انتخابی را پایین
// نگه نداشته، هیچ پنل آموزشی باز نمی‌شود و موس برای اسکرول/درگ آزاد است.
// مرجع رسمی: مستندات MQL5، CHARTEVENT_MOUSE_MOVE — مقدار sparam رشتهٔ
// بیت‌ماسک وضعیت دکمه‌های ماوس و مودیفایرهاست: بیت ۴ = SHIFT، بیت ۸ = CTRL.
// Alt در این بیت‌ماسک وجود ندارد، پس عمداً گزینه‌ای برایش گذاشته نشد؛ وعدهٔ
// بی‌پشتوانه نمی‌دهیم (اگر لازم شد فقط با DLL/GetAsyncKeyState ممکن است).
// نگاشت مقادیر با ورودی قدیمی bool سازگار است: false→0=FREE و true→1=CTRL،
// پس presetهای ذخیره‌شدهٔ کاربر بی‌صدا نمی‌شکنند.
enum ENUM_EXPLAIN_OPEN
{
   EXPLAIN_OPEN_CLICK = 0,   // پیش‌فرض: فقط با **کلیک** روی خط/باکس باز می‌شود (موس آزاد، چارت تمیز)
   EXPLAIN_OPEN_HOVER = 1    // سبک قدیمی: با ایستادن موس روی آبجکت
};

// --- حذف گذشتهٔ فیلدشده + کنترل انسداد چارت ---
// ۱) مواردی که باطل/فیلد/جارو شده‌اند دیگر رسم نمی‌شوند (تاریخچه فقط در CSV می‌ماند).
// ۲) پنل آموزشی کلیدمحور است (InpExplainGate) تا چارت پیش‌فرض تمیز بماند.
// ورودی‌ها در انتهای لیست اضافه شدند تا اندیس ورودی‌های قبلی عوض نشود.
input group "== Display hygiene (remove invalidated past, key-gated teaching panel) =="
input bool   InpHideInvalidatedObjects    = true;  // ناحیهٔ INVALID/MITIGATED/SWEPT/BROKEN/TOUCHED دیگر رسم نشود
input bool   InpDeleteExpiredObjects      = true;  // منقضی‌شده‌ها (FVG/OB/S-D/…) کاملاً از چارت و رجیستری حذف شوند — نه frozen
input int    InpExpiryKeepBars            = 40;    // عمر مجاز هر آبجکت رسم‌شده بر حسب کندل (۰=بدون انقضای رسم)
input int    InpSweptKeepBars             = 3;     // برای SWEPT فقط همین چند کندل آخر رسم بماند (۰=هیچ) — قبلاً ۶
input bool   InpDrawPerTimeframe          = true;  // هر تایم‌فریم مالک، رسم مخصوص خودش (مستقل از تایم‌فریم چارت)
input ENUM_EXPLAIN_OPEN InpExplainOpen    = EXPLAIN_OPEN_CLICK; // فاز ۲۷: پنل آموزشی با کلیک باز می‌شود (پیش‌فرض). HOVER = سبک قدیمی، فقط اگر خواستی

// --- فازهای ۱۶–۲۱ (2026-09-18): شش خانوادهٔ باقی‌مانده ---
input group "== Phase 16-21: Wyckoff / SupplyDemand / AlBrooks / RTM / Profile =="
input bool   InpEnableWyckoff            = true;  // فاز ۱۶: SC/BC، AR/ST، Spring/Upthrust، SOS/SOW، LPS/LPSY، فازهای A–E
input int    InpWyckoffLookbackBars      = 60;    // چند کندل بستهٔ چارت برای تحلیل فاز Wyckoff
input double InpWyckoffSpringATR         = 0.35;  // حداقل عمق فرو رفتن فتیله زیر رنج (× ATR) برای Spring/Upthrust
input group "== Phase 33: Wyckoff state machine (sourced, 13 events) =="
input int    InpWyckoffVolLookback         = 20;   // کندل‌های مرجع میانگین tick-volume (منبع: کلایمکس با حجم بالا)
input double InpWyckoffClimaxRangeATR      = 1.5;  // حداقل دامنهٔ کندل کلایمکس (× ATR) — «فروش شارپ»
input double InpWyckoffClimaxVolMult       = 1.5;  // حجم کلایمکتیک نسبت به میانگین (برای گزارش در پنل)
input bool   InpWyckoffClimaxRequireVolume = false;// منبع: کلایمکس می‌تواند بدون حجم کلایمکتیک باشد (Selling Exhaustion)
input int    InpWyckoffClimaxExtremeBars   = 20;   // کلایمکس باید اکستریم این تعداد کندل باشد
input double InpWyckoffClimaxResetATR      = 0.5;  // عبور از اکستریم چرخهٔ قبلی به این اندازه (× ATR) = چرخهٔ تازه
input double InpWyckoffAR_ATR              = 1.2;  // حداقل اندازهٔ AR (× ATR) — منبع: «حرکت چشمگیر»
input int    InpWyckoffAR_MaxBars          = 40;   // حداکثر کندل انتظار برای AR پس از کلایمکس
input double InpWyckoffST_ATR              = 0.6;  // نزدیکی ST به اکستریم کلایمکس (× ATR)
input double InpWyckoffST_UndercutATR      = 0.25; // حد مجاز تخطی ST از اکستریم کلایمکس (× ATR)
input bool   InpWyckoffSTRequireLighterVolume = true; // منبع: ST روی «حجم سبک‌تر» تأیید می‌شود
input double InpWyckoffAbsorbVolMult       = 1.5;  // Absorption: حجم بالا…
input double InpWyckoffAbsorbRangeATR      = 0.6;  // …با دامنهٔ کوچک (Effort vs Result)
input double InpWyckoffSOSRangeATR         = 1.2;  // حداقل دامنهٔ کندل SOS/SOW (× ATR)
input int    InpWyckoffPhaseE_Bars         = 5;    // کندل پیوستهٔ بیرون ساختار تا اعلام فاز E
input int    InpWyckoffRangeMaxBars        = 300;  // حداکثر عمر ساختار پیش از بازنشانی
input bool   InpEnableSupplyDemand       = true;  // فاز ۱۷: RBR/DBD/RBD/DBR + Fresh/Tested + Flip + Strength
input int    InpSD_MaxZones              = 12;    // سقف نواحی Supply/Demand در رجیستری (قبلاً ۲۴)
input int    InpSD_BaseMaxBars           = 3;     // حداکثر کندل «پایه» (Base) قابل قبول
input double InpSD_StrengthATR           = 0.8;   // حداقل حرکت خروج از پایه (× ATR) برای زون معتبر
input double InpSD_BaseMaxRangeATR       = 1.5;   // فاز ۳۳: حداکثر دامنهٔ «پایه» (× ATR) — قبلاً ۱.۵ سخت‌کد بود
input bool   InpEnableAlBrooks           = true;  // فاز ۱۸: Trend/Doji/Signal/Entry/Follow-through، Always-In، H1/H2، EMA20
input int    InpBrooks_EMA20_Period      = 20;    // دورهٔ EMA مرجع (پیش‌فرض ۲۰)
input double InpBrooks_TrendBarRatio     = 0.70;  // نسبت بدنه/دامنه برای «کندل روند»
input double InpBrooks_TailMaxRatio      = 0.25;  // حداکثر نسبت فتیله برای Doji/Small-bodied
input double InpBrooks_DojiBodyRatio     = 0.25;  // فاز ۳۳: نسبت بدنه/دامنه برای «Doji/Small bar» (تعریف Al Brooks: بدنهٔ کوچک)
input int    InpBrooks_PullbackWindow    = 12;    // فاز ۳۳: پنجرهٔ شمارش H1..H4 / L1..L4 (شکست سقف/کف کندل قبلی)
input int    InpBrooks_AI_EMASlopeBars   = 3;     // فاز ۳۳: تعداد کندل مرجع شیب ۲۰ EMA برای وضعیت Always-In (فقط برای پنل آموزش و گزارش)
input bool   InpEnableRTM                = true;  // فاز ۱۹: Compression/Expansion، Trap، Momentum، Confluence
input int    InpRTM_CompressBars         = 6;     // چند کندل باریک پشت‌سرهم = Compression
input double InpRTM_CompressRangeATR     = 0.5;   // میانگین دامنهٔ کندل در Compression (× ATR)
// فاز ۳۴: RTM از «یک خط یادداشت» به رویدادهای قابل‌کلیک تبدیل شد (قبلاً Trap/
// Momentum/Engulf/Rejection هیچ شناسه و رجیستری نداشتند).
input double InpRTM_MomentumATR          = 1.5;   // حداقل دامنهٔ کندل Momentum (× ATR)
input double InpRTM_MomentumBody         = 0.70;  // حداقل نسبت بدنه/دامنه در Momentum (کندل ممنتوم)
input double InpRTM_RejectTailRatio      = 0.60;  // حداقل نسبت فتیله به دامنه برای Rejection
input int    InpRTM_MaxEvents            = 12;    // سقف رویدادهای RTM در رجیستری
input bool   InpDrawRTMObjects           = false; // رسم برچسب رویدادهای RTM (پیش‌فرض خاموش: چارت تمیز)
input bool   InpEnableProfile            = true;  // فازهای ۲۰–۲۱: POC/VA/HVN/LVN/IB/TPO روی tick-volume
input int    InpProfileLookbackBars      = 120;   // چند کندل برای ساخت پروفایل سشن/روز
input int    InpProfilePriceRows         = 24;    // تعداد ردیف قیمتی پروفایل
input double InpProfileVA_Percent        = 70.0;  // درصد حجم داخل Value Area
input bool   InpDrawProfileOnChart       = false; // رسم خطوط POC/VAH/VAL (پیش‌فرض خاموش: شلوغ نشود)
input group "== Phase 34: Auction Market Theory — IB / TPO / Day types (sourced) =="
input int    InpProfileIB_Minutes        = 60;   // طول Initial Balance (دقیقه از شروع روز) — منبع: «ساعت اول سشن»
input int    InpAMT_HistDays             = 5;    // چند روز گذشته برای Naked POC و نوع روز
input double InpAMT_TrendIBRatio         = 0.50; // Trend day: نسبت IB به دامنهٔ روز ≤ این مقدار
input double InpAMT_NontrendIBRatio      = 0.85; // Non-trend day: نسبت IB به دامنهٔ روز ≥ این مقدار
input double InpProfileHVN_Ratio         = 1.50; // آستانهٔ HVN: حجم ردیف ≥ این ضریب میانگین ردیف‌ها
input double InpProfileLVN_Ratio         = 0.50; // آستانهٔ LVN: حجم ردیف ≤ این ضریب میانگین ردیف‌ها
input bool   InpDrawAMTOnChart           = false; // رسم خطوط IB و Naked POC (پیش‌فرض خاموش)

// --- بازبینی کامل نمایش (2026-09-18): ضروری‌های ترید روشن، تزئینات خاموش ---
// اصل: هر چیزی که برای «تصمیم ترید» لازم است (ناحیهٔ ورود، SL/TP، نقدینگی،
// سوئپ، ساختار، دروازهٔ برگشت) رسم می‌شود؛ هر چیزی که فقط «خواندنی تاریخی»
// یا متن تکراری داشبورد است، پیش‌فرض خاموش ولی با سوییچ در دسترس می‌ماند.
// محاسبات هرگز با این سوییچ‌ها خاموش نمی‌شود (کشف ≠ رسم).
// این گروه هم در **انتهای** لیست اضافه شد تا اندیس ورودی‌های قبلی نورد.
input group "== Display audit: essentials ON, decoration OFF (detection is never touched) =="
input bool   InpDrawWyckoffLabels = false; // برچسب متنی SC/BC/AR/ST/SOS/… روی چارت (فاز Wyckoff در داشبورد کامل است) — Spring/Upthrust به‌عنوان سوئپ نقدینگی خودشان در لایهٔ SWEEP دیده می‌شوند
input bool   InpDrawSDZones       = true;  // نواحی Supply/Demand (RBR/DBD/RBD/DBR) = نواحی ورود واقعی → ضروری
input bool   InpDrawIPDA          = true;  // سطوح IPDA (Old High/Low ۲۰/۴۰/۶۰ روزه) = نقشهٔ هدف نقدینگی بلندمدت → ضروری
input bool   InpDrawTrendlines    = true;  // نقدینگی مورب (Trendline) = ناحیهٔ فعال هدف‌گیری قیمت → ضروری
input bool   InpDrawBestPOI       = true;  // بهترین نقطهٔ ورود (POI) از رجیستری یکپارچه → ضروری
input bool   InpDrawDOL           = true;  // خط DOL (هدف معامله). خاموش = فقط در داشبورد — برای چارت خلوت‌تر

// --- فاز ۲۸: تکمیل و تصحیح منطق FVG (منابع انگلیسی، بدون حدس) ---
// منبع ۱ (LuxAlgo Library — Fair Value Gap، مرحلهٔ ۴ تشخیص): «گپ‌های سه‌کندلی
//   خام بی‌وقفه چاپ می‌شوند، پس بیشتر ابزارها حداقل اندازه (ATR یا درصد) یا
//   هم‌راستایی با ساختار می‌خواهند.» → فیلتر اهمیت بر مبنای ATR تحلیل.
// منبع ۲ (LuxAlgo Library — Implied FVG، فرمول ICT 2023): Implied FVG از
//   **میانهٔ فتیله‌ها** ساخته می‌شود، نه از بدنه‌ها. گپی که از مرزهای بدنه
//   ساخته می‌شود نامش **Volume Imbalance** است (لایه‌بانو: «گپی بین بدنه‌ها که
//   فتیله‌ها هنوز هم‌پوشانی دارند»). نسخهٔ قبلی این دو را قاطی کرده بود.
// این ورودی‌ها در **انتهای** لیست اضافه شدند تا اندیس ورودی‌های قبلی عوض نشود.
input group "== Phase 28: FVG completeness (ATR filter, implied, volume imbalance) =="
input double InpMinFVG_ATR        = 0.10;  // حداقل ارتفاع گپ = این ضریب × ATR تحلیل (۰ = بدون فیلتر). منبع: مرحلهٔ ۴ تشخیص FVG
input bool   InpDetectVolumeImbalance = true; // Volume Imbalance (گپ بدنه‌ها با فتیلهٔ هم‌پوشان) — مفهوم مستقل، نه Implied FVG

// --- فاز ۳۷: آزمون رفتاری روی دادهٔ ساختگی (FVG / OB / Sweep) ---
// چرا داخل خود اندیکاتور: تا امروز همهٔ «اعتبارسنجی»ها متن کد را grep می‌کردند،
// یعنی «رشته در فایل هست» را ثابت می‌کردند نه «محاسبهٔ عددی درست است» را.
// MQL5 بیرون از ترمینال اجرا نمی‌شود، پس تنها راه اثبات واقعی این است که همین
// توابع زندهٔ DetectFVG/DetectOB/DetectSweep روی کندل‌های ساختگی با پاسخ معلوم
// اجرا شوند و خروجی با انتظار مقایسه شود. یک‌بار در هر attach اجرا می‌شود،
// رجیستری‌ها را پس از آزمون صفر می‌کند و روی تحلیل زنده هیچ اثری ندارد.
// این ورودی در **انتهای** لیست اضافه شد تا اندیس ورودی‌های قبلی عوض نشود.
input group "== Phase 37: behavioral self-test on synthetic data =="
input bool   InpRunBehaviorSelfTest = true; // اجرا و نوشتن گزارش در ICT_Assistant_Canonical_SelfTest.csv (COMMON\Files)

// --- فاز ۴۴: مسیر کلیک — هیچ کلیکی بدون نام و دلیل نماند ---
// چرا آزمون جدا لازم است: آزمون فاز ۳۷ توابع *محاسبه* را می‌سنجد، ولی مسیر
// کلیک (hit-test پیکسلی ← مرجع در رجیستری ← متن توضیح) مسیر جداگانه‌ای است و
// تا امروز هیچ تست خودکاری نداشت. ابزار بیرونی هم ندارد: بدون چارت و بدون
// موس نمی‌شود آن را سنجید. این آزمون در **پایان** هر بازسازی (که آبجکت‌ها روی
// چارت هستند) همان مسیر کلیک را بدون موس اجرا می‌کند: مرکز هر آبجکت را با
// همان توابع تبدیل پیکسل حساب می‌کند، همان `HitTestExplainObject` را صدا
// می‌زند و همان سازندهٔ پنل را؛ نتیجه در یک CSV شاهد نوشته می‌شود.
// این ورودی در **انتهای** لیست اضافه شد تا اندیس ورودی‌های قبلی عوض نشود.
input group "== Phase 44: click path — every object answers with its name and reason =="
input bool   InpRunClickPathSelfTest = true; // آزمون خودکار مسیر کلیک در پایان هر بازسازی + نوشتن ICT_Assistant_Canonical_Click_Diag.csv
input int    InpClickDiagMaxObjects  = 400;  // سقف ردیف گزارش آزمون کلیک (برای چارت‌های سنگین)

// --- فاز ۴۷: سناریوی در انتظار (PENDING) — «چه چیزی منتظر بسته شدن کندل است» ---
// چرا جدا از دروازهٔ برگشت: دروازه پس‌رو است (تا کندل HTF بسته نشود چیزی
// اعلام نمی‌کند). این ردیف همان انتظار را پیش از بسته شدن نشان می‌دهد، همراه با
// نرخ اندازه‌گیری‌شدهٔ همان شرط. **ریپنت نمی‌کند**: تنها ورودی‌اش وضعیت آخرین
// کندل بسته است، پس تا کندل بعدی بسته نشود متنش عوض نمی‌شود؛ و صفر نوشتن دارد
// (نه رجیستری، نه رویداد، نه CSV) پس خاموش‌کردنش هیچ تحلیلی را عوض نمی‌کند.
// نرخ‌ها از tools/Fit-PendingScenario.ps1 می‌آیند؛ منبع و تعداد نمونه در همان
// ماژول 32_PendingScenario.mqh ثبت شده است.
// این ورودی‌ها در **انتهای** لیست اضافه شدند تا اندیس ورودی‌های قبلی عوض نشود.
input group "== Phase 47/48: pending scenario (در انتظار بسته شدن کندل، بدون ریپنت) =="
input bool   InpEnablePendingScenario = true;  // محاسبهٔ سناریوی در انتظار (خاموش = تحلیل دست‌نخورده می‌ماند)
// فاز ۴۸: ردیف جداگانهٔ «در انتظار» با ردیف درجهٔ سیگنال **ادغام** شد و حالا
// هر دو در همان یک نوار گوشهٔ چارت دیده می‌شوند. پس سه ورودی چیدمان ردیف
// (نمایش/ارتفاع/عرض) حذف شدند — چیدمان همان نوار ریسک است (InpRiskStripY/Width).

//====================================================================
// ENUMS  — هسته‌ی رفع ایراد شماره ۱ و ۲: هر خروجی یک Enum مستقل دارد
//====================================================================
// EVT_EXTERNAL_BREAK در انتهای لیست اضافه شد تا مقدار عددی رویدادهای موجود
// عوض نشود (StableEventId از همین عدد در شناسه استفاده می‌کند) — فاز ۱۱.
enum ENUM_EVENT_TYPE   { EVT_BOS, EVT_CHOCH, EVT_MSS, EVT_EXTERNAL_BREAK };
enum ENUM_DIRECTION    { DIR_BULL, DIR_BEAR, DIR_NONE };
enum ENUM_LIQ_TYPE     { LIQ_PDH, LIQ_PDL, LIQ_PWH, LIQ_PWL, LIQ_EQH, LIQ_EQL,
                          LIQ_SWING_H, LIQ_SWING_L, LIQ_SESSION_H, LIQ_SESSION_L,
                          // فاز ۱۲ (#۲۰ #۶۵) — در انتها تا مقدار عددی اعضای قبلی عوض نشود
                          LIQ_RANGE_H, LIQ_RANGE_L,
                          LIQ_IPDA20_H, LIQ_IPDA20_L, LIQ_IPDA40_H, LIQ_IPDA40_L,
                          LIQ_IPDA60_H, LIQ_IPDA60_L,
                          // فاز ۳۰ (#۷۶) — در انتها تا مقدار عددی اعضای قبلی عوض نشود
                          LIQ_TRENDLINE_H, LIQ_TRENDLINE_L };
enum ENUM_LIQ_SCOPE    { SCOPE_INTERNAL, SCOPE_EXTERNAL };
enum ENUM_LIQ_STATE    { LSTATE_FRESH, LSTATE_SWEPT, LSTATE_INVALID };
// OB_MITIGATION در انتها اضافه شد (#۳۸): بلوک Mitigation = ناحیه‌ای که
// شکسته شده ولی روی Sweep نقدینگی ساخته نشده بود — دقیقاً تفاوتش با Breaker.
enum ENUM_OB_STATE     { OB_VALID, OB_MITIGATED, OB_BROKEN, OB_BREAKER, OB_INVALID,
                          OB_MITIGATION };
enum ENUM_REJECTION_STATE { REJECTION_FRESH, REJECTION_TOUCHED, REJECTION_INVALID };
enum ENUM_SESSION      { SESS_NONE, SESS_ASIA, SESS_LONDON, SESS_NY_AM, SESS_LONDON_CLOSE, SESS_NY_PM };
enum ENUM_AMD          { AMD_NONE, AMD_ACCUMULATION, AMD_MANIPULATION, AMD_DISTRIBUTION };
enum ENUM_SILVERBULLET { SB_NONE, SB_LONDON, SB_NY_AM, SB_NY_PM };
// فاز ۳۶ — Quarterly Theory (Trader Daye): هر چرخه چهار ربع دارد و همان قالب
// AMD-X در هر ربع تکرار می‌شود. منبع: arongroups — «Quarterly Theory in Trading»:
// روز: Q1 18:00–00:00 (Accumulation) · Q2 00:00–06:00 (Manipulation/Judas) ·
// Q3 06:00–12:00 (Distribution) · Q4 12:00–18:00 (Continuation/Reversal)،
// همگی ساعت نیویورک. True Open = قیمت بازِ Q2 هر چرخه (روز: نیمه‌شب نیویورک؛
// هفته: دوشنبه ۰۰:۰۰ طبق منبع).
enum ENUM_QT_PHASE  { QT_NONE, QT_Q1_ACCUM, QT_Q2_MANIP, QT_Q3_DISTRIB, QT_Q4_REVERSAL };
enum ENUM_EXHAUSTION_STATE { EXH_NEUTRAL, EXH_TRENDING, EXH_EXTENDING, EXH_WATCH,
                              EXH_MICRO_PULLBACK, EXH_MICRO_REVERSAL_CONFIRMED,
                              EXH_RANGE_TRANSITION, EXH_REVERSAL_CONFIRMED };

// --- فاز ۱۲: انواع جدید. همهٔ اعضای جدید در **انتهای** هر enum اضافه شده‌اند تا
// مقدار عددی اعضای موجود (و idهای پایدار ساخته‌شده از آن‌ها) عوض نشود.
enum ENUM_FVG_KIND    { FVGK_STANDARD, FVGK_IMPLIED, FVGK_MICRO, FVGK_VOL_IMBALANCE };
enum ENUM_OB_KIND     { OBK_UNDEFINED, OBK_CORE, OBK_STANDALONE, OBK_EXTREME, OBK_MITIGATION_BLOCK };
enum ENUM_POI_KIND    { POIK_NONE, POIK_FVG, POIK_OB, POIK_BREAKER, POIK_MITIGATION,
                        POIK_REJECTION, POIK_TRENDLINE, POIK_RANGE };
enum ENUM_ENTRY_MODEL { MODEL_NONE, MODEL_ICT2022, MODEL_BOS_FVG_OB, MODEL_SWEEP_ENTRY, MODEL_OTE_ONLY };
enum ENUM_TREND_PHASE { PHASE_UNKNOWN, PHASE_INITIATION, PHASE_EXPANSION, PHASE_DISTRIBUTION, PHASE_REVERSAL };

//====================================================================
// DATA STRUCTS — رفع ایراد ۱۵: تلاش برای ONE SOURCE OF TRUTH
//====================================================================
struct SwingPoint
{
   datetime time;
   double   price;
   bool     isHigh;
   bool     confirmed;
   bool     broken;         // آیا بعداً شکسته شده (برای BOS/CHoCH استفاده می‌شود)
   long     id;
};

// --- رفع ایراد ۲: Event مستقل با فیلدهای کامل، نه یک Boolean ---
struct StructureEvent
{
   long             id;
   ENUM_EVENT_TYPE  type;
   ENUM_DIRECTION   direction;
   datetime         time;
   double           price;          // قیمت شکست
   long             brokenSwingId;
   long             protectedSwingId;
   int              confirmationBarShift;
   long             displacementId;   // -1 اگر هنوز متصل نشده
   long             sweepId;          // -1 اگر با Sweep شروع نشده
   long             parentEventId;    // -1 اگر ریشه است
   bool             isHTF;            // این Event روی HTF ساخته شده یا LTF
};

// --- رفع ایراد ۵ و ۶: Liquidity Registry واحد با متادیتای کامل ---
struct LiquidityObj
{
   long           id;
   ENUM_LIQ_TYPE  type;
   ENUM_LIQ_SCOPE scope;
   ENUM_LIQ_STATE state;
   double         price;
   datetime       time;
   datetime       sweptTime;
   long           sweptByEventId;    // کدام Sweep/Event این را جارو کرد
   bool           isHTF;
};

// --- رفع ایراد ۸: Displacement با اثبات ارتباط، نه فقط انرژی کندل ---
struct DisplacementObj
{
   long     id;
   datetime time;
   int      barShift;
   ENUM_DIRECTION direction;
   double   bodyRatio;
   double   rangeVsAtr;
   long     causedByEventId;   // MSS/BOS/CHoCH که این جابه‌جایی را ایجاد کرده -> اثبات ارتباط
   long     liquidityEventId;  // Sweep مرتبط (-1 اگر ندارد)
   bool     energyOnly;        // true یعنی فقط انرژی کندل تایید شده ولی هنوز به Event وصل نیست (ناقص)
};

// --- رفع ایراد ۷: FVG کاملاً Causal، به Displacement متصل است ---
struct FVGObj
{
   long     id;
   datetime time;
   double   top;
   double   bottom;
   ENUM_DIRECTION direction;
   long     displacementId;   // اجباری غیر از -1 برای این‌که "Causal" باشد
   bool     causal;           // true فقط اگر displacementId معتبر باشد
   bool     mitigated;
   bool     inverted;         // iFVG: قیمت از سمت مخالف بسته شده (پولاریتی ناحیه عوض شده)
   // --- فاز ۴۳: یک فیلد، یک معنی ---
   // `direction` همیشه جهت **تولد** گپ است (هندسهٔ گپ: top/bottom نسبت به آن تعریف
   // شده‌اند و شناسهٔ ناحیه از آن ساخته شده). نقش **فعلی** از روی `inverted`
   // مشتق می‌شود و فقط با FVGActiveDir() خوانده می‌شود. قبلاً همین تابع وارونگی
   // `direction` را هم عوض می‌کرد؛ نتیجه این بود که رنگ/CSV/پنل/ستاپ هر کدام
   // بسته به لحظهٔ خواندن، جهت متفاوتی می‌گفتند (و شناسهٔ ناحیه با جهت داخلش
   // نمی‌خواند). زمان وارونگی برای شاهد عددی نگه داشته می‌شود.
   datetime invertedTime;
   bool     invalidated;      // منقضی/بی‌اعتبار
   datetime createdTime;      // برای انقضای زمانی (مستقل از تایم‌فریم)
   datetime touchTime;        // زمان اولین لمس معتبر (تشخیصی — برای اثبات، نه امتیازدهی)
   bool     birthBarTouch;    // آیا کندل تولد خودش ناحیه را لمس می‌کرد؟ (تشخیصی — توضیح ایراد #۲۵)
   // --- فاز ۱۲ (#۳۰ #۳۱) ---
   ENUM_FVG_KIND   kind;      // STANDARD / IMPLIED / MICRO
   ENUM_TIMEFRAMES tf;        // تایم‌فریم مالک ناحیه (Micro روی تایم‌فریم پایین‌تر ساخته می‌شود)
   double          ce;        // Consequent Encroachment = میانهٔ گپ (برای ورود در ۵۰٪)
   // --- فاز ۲۸ (منبع: LuxAlgo Library — Consequent Encroachment / FVG) ---
   // «خط تصمیم» یک گپ، میانهٔ آن است: بیشتر مدل‌ها لمس میانه را «به‌قدر کافی
   // پر شده» می‌دانند. لمس لبهٔ ناحیه این معنا را ندارد؛ پس این پرچم جدا نگه
   // داشته می‌شود تا پنل آموزشی حقیقت را بگوید، نه فقط «mitigated».
   bool            ceTouched; // آیا قیمت به میانهٔ گپ (CE) رسیده است؟
};

// --- رفع ایراد ۹،۱۰،۱۱،۱۲: OB با زنجیره اثبات + منطق Breaker درست ---
struct OBObj
{
   long          id;
   datetime      time;
   double        top;
   double        bottom;
   ENUM_DIRECTION direction;
   long          displacementId;     // اثبات این‌که OB باعث Displacement شده
   long          structureEventId;   // اثبات مشارکت در شکست ساختار
   long          liquidityEventId;   // اثبات ارتباط با Sweep (اختیاری ولی برای Breaker لازم)
   long          fvgId;              // ارتباط با FVG (اختیاری)
   ENUM_OB_STATE state;
   bool          polarityFlipped;    // برای Breaker: پولاریتی برعکس شده
   bool          retested;           // برای Breaker: بعد از شکست، ریتست شده
   bool          isStandalone;       // false = Core OB (اولویت بالاتر) / true = Standalone
   datetime      createdTime;        // کندلی که این ناحیه در آن ثبت شد (برای رد لمس همان کندل)
   datetime      brokenTime;         // کندلی که در آن ناحیه شکست (ریتست باید بعد از این کندل باشد)
   // --- فاز ۱۲ (#۳۵ #۳۶ #۳۸) ---
   ENUM_OB_KIND  kind;               // CORE / STANDALONE / EXTREME / MITIGATION_BLOCK
   bool          isExtreme;          // ناحیهٔ اکسترمم لگ معامله‌گری (نه ناحیهٔ داخلی رنج)
   bool          hasSweep;           // روی Sweep نقدینگی ساخته شده؟ (تفاوت Breaker و Mitigation Block)
   ENUM_TIMEFRAMES tf;               // فاز ۱۶+: تایم‌فریم مالک ناحیه (برای رسم هر تایم‌فریم برای خودش)
   ENUM_LIQ_SCOPE scope;             // فاز ۳۶: External = مبدأ لگ (روی اکسترمم رنج معامله‌گری) · Internal = باقی‌ماندهٔ داخل لگ
                                     // منبع: LuxAlgo — Internal vs External Range Liquidity: «a bullish or bearish order
                                     // block left inside the leg» جزء IRL است و مبدأ اکسترمم رنج ERL است.
};

struct RejectionObj
{
   long id;
   datetime time;
   double top;
   double bottom;
   ENUM_DIRECTION direction;
   ENUM_REJECTION_STATE rejectionState;
};

//====================================================================
// پالت رنگی چارت (فاز ۴۸) — «یک رنگ، یک خانواده»
//====================================================================
// چرا این جدول اضافه شد
// --------------------
// پیش از این، رنگ‌ها پخش‌شده در کد بودند و چند **خانوادهٔ بی‌ربط** یک رنگ
// داشتند. شاهد واقعی از خود کد (نه حدس):
//
//   clrMagenta      → اردربلاک نزولی · پنجرهٔ سیلور بولت · ناحیهٔ اولیه (IB)
//                     · سطح طلایی OTE   (۴ خانوادهٔ متفاوت)
//   clrDodgerBlue   → اردربلاک صعودی · باکس سشن لندن
//   clrGold         → خط ستاپ · POC پروفایل · تعادل لگ (EQ)
//   clrOrangeRed    → هدف نقدینگی (DOL) · نقدینگی HTF · سشن نیویورک صبح
//                     · دروازهٔ برگشت تأییدشده · بایاس نزولی
//   clrTomato       → نقدینگی سقفی · خط روند بروکس · POC برهنه
//   clrAqua         → OTE · بلوک پس‌زدگی صعودی · VAH/VAL
//   clrGoldenrod    → حالت «لمس‌شده» (عمدی، مشترک) · باکس بستهٔ لندن
//
// نتیجه: کاربر نمی‌توانست از رنگ بفهمد روی چه چیزی کلیک می‌کند. این جدول
// آن را یک‌بار برای همیشه حل می‌کند: هر خانوادهٔ چارت **یک رنگ یکتا** دارد.
//
// قاعده‌های این جدول
// -----------------
// ۱) هر خانه یک رنگ یکتا است؛ هیچ دو خانواده‌ای رنگ مشترک ندارند.
// ۲) رنگ‌ها با **بیشینه‌سازی کمترین فاصلهٔ RGB** انتخاب شده‌اند (یک مسئلهٔ
//    چیدمان نقطه در مکعب رنگ)، نه با سلیقه. ابزار `tools/Validate-Phase48.ps1`
//    همین عدد را از متن همین جدول بازمحاسبه می‌کند؛ اگر روزی کسی رنگی را
//    نزدیک دیگری بگذارد، دروازه قرمز می‌شود.
//    • کمترین فاصلهٔ اندازه‌گیری‌شده در کل جدول: **۵۲٫۲**
//    • سه خانواده‌ای که کاربر صریحاً شکایت کرد (گپ وارونه / باز شدن روز /
//      باز شدن هفته) عمداً از هم دور گذاشته شدند: ۱۸۸ و ۲۵۹ و ۳۰۹.
// ۳) رنگِ جهت (صعودی/نزولی) در جدول نیست: آن دو ورودی کاربرند
//    (InpColorBull / InpColorBear) و دست‌نخورده می‌مانند.
// ۴) رنگِ **حالت** (لمس‌شده، جاروشده، باطل، شکسته) عمداً مشترک است، چون
//    معنی‌اش یکی است: «این سطح دیگر تازه نیست». این «یک معنی، یک رنگ» است،
//    نه تداخل — و در جدول پایین جدا نگه داشته شده تا قاطی نشود.
//
// جای این جدول چرا اینجاست: پیش از همهٔ ماژول‌های رسم قرار دارد، پس هر
// تابع رسمی می‌تواند بدون جابه‌جایی ترتیب include از آن استفاده کند.
//--------------------------------------------------------------------

// --- نقدینگی (خطوط افقی)
const color PAL_LIQ_HIGH        = C'255,104,101';  // نقدینگی سقفی (BSL)
const color PAL_LIQ_LOW         = C'29,191,69';    // نقدینگی کفی (SSL)
const color PAL_LIQ_HTF_HIGH    = C'255,62,70';    // نقدینگی سقفی تایم‌فریم بالاتر
const color PAL_LIQ_HTF_LOW     = C'139,242,36';   // نقدینگی کفی تایم‌فریم بالاتر

// --- ناحیه‌ها (مستطیل پُر؛ چون روی هم می‌افتند، هر خانواده رنگ خودش را دارد)
const color PAL_FVG_INVERTED    = C'217,36,242';   // گپ ارزش منصفانهٔ وارونه (iFVG)
const color PAL_OB_BULL         = C'85,154,242';   // اردربلاک صعودی
const color PAL_OB_BEAR         = C'242,36,191';   // اردربلاک نزولی
const color PAL_OB_BREAKER      = C'36,242,242';   // بریکر (پس از برگشت نقش)
const color PAL_REJ_BULL        = C'85,242,95';    // بلوک پس‌زدگی صعودی
const color PAL_REJ_BEAR        = C'242,114,36';   // بلوک پس‌زدگی نزولی
const color PAL_SD_DEMAND       = C'106,191,67';   // ناحیهٔ تقاضا
const color PAL_SD_SUPPLY       = C'110,29,191';   // ناحیهٔ عرضه

// --- سشن‌ها و پنجره‌های زمانی (باکس)
const color PAL_SESS_ASIA       = C'191,29,90';    // سشن آسیا
const color PAL_SESS_LONDON     = C'29,130,191';   // سشن لندن
const color PAL_SESS_NY         = C'191,29,29';    // سشن نیویورک
const color PAL_SESS_SB         = C'191,67,183';   // پنجرهٔ سیلور بولت
// دو نقش هم‌خانواده که عمداً رنگ مشترک دارند (برچسب روی باکس از هم جدایشان می‌کند):
// بستهٔ لندن با رنگ سشن لندن، و عصر نیویورک با رنگ سشن نیویورک.
const color PAL_SESS_LONDONCLOSE= C'29,130,191';
const color PAL_SESS_NYPM       = C'191,29,29';

// --- زمان‌بند Quarterly Theory (دو خط True Open)
const color PAL_QT_DAY          = C'36,88,242';    // باز شدن واقعی روز
const color PAL_QT_WEEK         = C'242,191,36';   // باز شدن واقعی هفته

// --- سطوح هدف و ورود
const color PAL_DOL             = C'62,36,242';    // هدف تحویل قیمت
const color PAL_SETUP           = C'242,232,85';   // خط ستاپ
const color PAL_GATE_CONFIRMED  = C'67,75,191';    // دروازهٔ برگشت — تأییدشده
const color PAL_GATE_PENDING    = C'85,213,242';   // دروازهٔ برگشت — در انتظار

// --- ناحیهٔ ارزش / پروفایل (خطوط افقی نازک)
const color PAL_PROF_POC        = C'134,85,242';   // نقطهٔ کنترل
const color PAL_PROF_VA         = C'62,242,36';    // سقف و کف ناحیهٔ ارزش
const color PAL_PROF_TPO        = C'171,191,29';   // ناحیهٔ ارزش زمان‌محور
const color PAL_PROF_IB         = C'193,85,242';   // ناحیهٔ اولیهٔ روز
const color PAL_PROF_HVN        = C'36,242,165';   // گرهٔ حجم بالا
const color PAL_PROF_LVN        = C'67,191,168';   // گرهٔ حجم پایین
// POC برهنه هم‌خانوادهٔ POC است و عمداً همان رنگ را دارد (خط‌چین ضخیم‌تر از هم جدایش می‌کند).
const color PAL_PROF_NPOC       = C'134,85,242';

// --- تعادل و ناحیهٔ ورود بهینه در لگ معامله‌گری
const color PAL_LOC_GOLDEN      = C'179,216,90';   // سطح طلایی
// تعادل لگ و دو مرز ورود بهینه هم‌خانوادهٔ همان سطوح‌اند و همان رنگ طلایی را دارند.
const color PAL_LOC_EQ          = C'179,216,90';
const color PAL_LOC_OTE         = C'179,216,90';

// --- خانوادهٔ بروکس (خطوط مورب و مغناطیس‌ها)
const color PAL_BROOKS_TR       = C'107,242,190';  // خط روند
const color PAL_BROOKS_MM       = C'242,85,173';   // حرکت سنجیده‌شده
// میانهٔ رنج و حرکت سنجیده‌شده هر دو «مغناطیس»اند و رنگ مشترک دارند.
const color PAL_BROOKS_TRMID    = C'242,85,173';

// --- رنگ‌های حالت: عمداً مشترک، چون معنی‌شان یکی است: «دیگر تازه نیست»
const color PAL_STATE_MITIGATED = clrGoldenrod;    // لمس‌شده / تخفیف‌خورده
const color PAL_STATE_SWEPT     = clrGray;         // جاروشده / استاپ‌های مصرف‌شده
const color PAL_STATE_BROKEN    = clrSlateGray;    // شکسته
const color PAL_STATE_INVALID   = clrDimGray;      // باطل / منقضی
const color PAL_STATE_NOCAUSAL  = clrGray;         // بدون زنجیرهٔ علّی (هم‌رنگ جاروشده)

// --- پوستهٔ پنل‌های گوشهٔ چارت (نوار و ردیف): کروم است، نه یک خانوادهٔ چارت
const color PAL_PANEL_BORDER    = C'105,105,105';  // قاب و خط دور پنل‌های فقط‌خواندنی

// --- رفع ایراد ۱۳،۱۴: DOL با دلیل قابل اثبات، نه فقط نزدیک‌ترین ---
struct DOLObj
{
   long           liquidityId;
   double         price;
   ENUM_DIRECTION direction;
   string         narrative;     // چرا این DOL انتخاب شد (رشته توضیحی برای Dashboard)
   bool           htfAligned;
   bool           structureAligned;
   bool           sweepStateOk;      // هنوز جارو نشده (از state واقعی سطح، نه هاردکد)
   bool           hierarchyOk;       // External بر Internal ارجحیت دارد وقتی HTF همسو است
   // --- فاز ۱۰: امتیازدهی چندمعیاره و شفاف (#۴۸) ---
   int            score;             // امتیاز نهایی انتخاب
   double         distATR;           // فاصلهٔ واقعی تا هدف بر حسب ATR
   string         typeName;          // نوع سطح انتخاب‌شده (PDH/PDL/EQH/...)
   string         breakdown;         // تفکیک عددی امتیاز برای کنترل دستی
};

//====================================================================
// GLOBAL STORAGE (آرایه‌های دینامیک = Registryهای واحد)
//====================================================================

SwingPoint       g_swingsLTF[];
SwingPoint       g_swingsHTF[];
StructureEvent   g_events[];
LiquidityObj     g_liquidity[];
DisplacementObj  g_displacements[];
FVGObj           g_fvgs[];
OBObj            g_obs[];
RejectionObj     g_rejections[];


ENUM_DIRECTION   g_htfBias        = DIR_NONE;
long             g_htfProtectedHighId = -1;
long             g_htfProtectedLowId  = -1;
// فاز ۱۱ (#۸/#۷۱): قیمت واقعی همان شناسه‌های محافظت‌شده — تا دروازهٔ برگشت
// روی عدد کار کند، نه روی شناسه.
double           g_htfProtectedHighPrice = 0.0;
double           g_htfProtectedLowPrice  = 0.0;
ENUM_DIRECTION   g_internalDir    = DIR_NONE;

DOLObj           g_currentDOL;
bool             g_hasDOL = false;

ENUM_SESSION     g_currentSession = SESS_NONE;
ENUM_AMD         g_currentAMD     = AMD_NONE;
// فاز ۳۶: AMD قیمتی — مرحلهٔ واقعی قیمت (A/M/D) از رفتار قیمت نسبت به رنج آسیا
ENUM_AMD         g_amdPriceStage  = AMD_NONE;
string           g_amdPriceNote   = "";

// Setup engine output
struct SetupState
{
   bool   active;
   ENUM_DIRECTION dir;
   double entry, sl, tp1, tp2, tp3;
   double rr;
   long   fvgId, obId, dolLiqId;
   string status; // "WAITING_RETRACE", "READY", "NONE"
   // --- فاز ۱۰: ستاپ صادق و بی‌خطر (#۶۶) ---
   double risk;          // فاصلهٔ واقعی entry→SL
   double rrTP1, rrTP2, rrTP3; // R:R واقعی هر هدف
   double oteLow, oteHigh, golden; // باند OTE و نقطهٔ طلایی همان لگ
   double slBuffer;      // بافر واقعی SL (قیمت)
   string zoneSource;    // منبع ناحیهٔ ورود: M5 setup TF یا chart TF
   string slSource;      // چرا بافر SL این اندازه شد
   long   chainSweepId, chainEventId, chainDispId; // زنجیرهٔ اثبات‌شده
   string chainText;     // شرح زنجیره برای پنل توضیح
   // --- فاز ۱۲ (#۴۷ #۶۷ #۶۸) ---
   ENUM_ENTRY_MODEL entryModel;   // مدل ورودی که واقعاً شرط‌هایش برآورده شد
   string           modelReason;  // چرا همین مدل انتخاب شد
   int              quality;      // امتیاز کیفیت ستاپ (شمارش معیارهای عددی)
   int              qualityMax;
   string           qualityText;  // تفکیک عددی معیارها برای کنترل دستی
   long             poiId;        // بهترین POI هم‌جهت از رجیستری
   ENUM_POI_KIND    poiKind;
   int              poiScore;
};
SetupState g_setup;

// --- فاز ۱۰: لگ واقعی (Dealing Leg) — یک منبع واحد برای DR/EQ/OTE ---
struct LegState
{
   bool            valid;
   ENUM_DIRECTION  dir;          // جهت لگ: کف→سقف = BULL
   double          low, high;
   datetime        lowTime, highTime;
   datetime        startTime, endTime;   // پیوت آغاز و پیوت پایان (همان دو نقطهٔ فیبوی دستی)
   double          startPrice, endPrice;
   double          range;
   double          eq;
   double          sizeATR;
   string          reject;       // اگر معتبر نیست، دلیل دقیق
};
LegState g_leg;

// --- فاز ۱۱: دروازهٔ برگشت تأییدشده (#۸ #۷۱ #۱۰ #۷۰) ---
// برگشت تأییدشده تنها یک معنا دارد: کندل بسته‌شدهٔ HTF فراتر از سطح
// محافظت‌شدهٔ خارجی بسته شود — همان سویینگی که آخرین رویداد مالک آن را
// محافظت کرده است. تابه‌حال این شناسه‌ها نوشته می‌شدند و هیچ‌جا خوانده
// نمی‌شدند. این ساختار فقط *گزارش* می‌کند؛ هیچ مسیری در آن g_htfBias را
// نمی‌نویسد (مالک Bias فقط EvaluateStructureBreak است).
struct ReversalState
{
   // --- تصویر لحظه‌ای سطح محافظت‌شده، گرفته‌شده پیش از ارزیابی ساختار ---
   // ارزیابی ساختار می‌تواند در همان کندل Bias را عوض کند و سطح محافظت‌شدهٔ
   // مقابل را جایگزین کند؛ پس دروازه باید از تصویر پیش‌از‌ارزیابی سنجیده شود.
   ENUM_DIRECTION snapBias;
   long           snapGuardId;
   bool           snapGuardOk;
   double         snapGuardPrice;
   datetime       snapGuardLevelTime;
   bool           snapGuardIsHigh;
   datetime       snapBarTime;        // کندل بستهٔ HTF که سنجیده می‌شود
   double         snapBarClose;
   // --- دروازهٔ فعال (برای نمایش روی چارت و داشبورد) ---
   bool           armed;
   long           levelSwingId;
   double         levelPrice;
   datetime       levelTime;
   bool           levelIsHigh;
   // --- آخرین برگشت تأییدشده (تاریخچه؛ فقط با یک شکست جدید جایگزین می‌شود) ---
   bool           confirmed;
   ENUM_DIRECTION dir;
   ENUM_DIRECTION priorBias;
   datetime       confirmedTime;
   datetime       confirmedCloseTime;
   double         confirmedClose;
   int            barsSince;
   long           eventId;
   // --- #۷۰ Smart Money Reversal (تعریف عملیاتی همین پروژه؛ در مستندات ثبت شده) ---
   int            smrScore;
   int            smrMax;
   bool           smr;
   string         smrReason;
   long           smrSweepId, smrDispId, smrZoneId;
   string         state;             // DISABLED / WAITING_H4_BIAS / WAITING_PROTECTED_LEVEL / WAITING_HTF_DATA / ARMED / CONFIRMED
   string         reason;
};
ReversalState g_reversal;

// --- فاز ۱۲ (#۱۹): نقدینگی مورب. خطی که دو سوئینگ تأییدشده را وصل می‌کند؛
// قیمت خط تابع زمان است، پس به‌جای یک قیمت ثابت، دو آنکر + شیب نگه داشته می‌شود.
struct TrendlineLiqObj
{
   long            id;
   bool            isHigh;         // خط روی سقف‌ها (مقاومت) یا کف‌ها (حمایت)
   datetime        t1, t2;
   double          p1, p2;
   double          slope;          // تغییر قیمت بر ثانیه
   int             touches;        // چند سویینگ تأییدشده روی این خط نشسته‌اند
   ENUM_TIMEFRAMES tf;
   datetime        createdTime;   bool            invalidated;    // عبور بسته‌شده از خط => نقدینگی برداشته شد
   datetime        invalidTime;
   double          invalidPrice;
   // فاز ۳۰ (#۷۶): «فرو رفتن + بازگشت» = جارو شدن خط (نه ابطال آن)
   bool            swept;
   datetime        sweptTime;
   double          sweptPrice;
};

// --- فاز ۱۲ (#۴۷): رجیستری POI یکپارچه. هر ناحیهٔ قابل معامله با نوع، جهت،
// محدوده، زمان، تایم‌فریم مالک، وضعیت اعتبار، دلیل ابطال و امتیاز — یک مسیر
// واحد برای انتخاب ناحیه در ستاپ و برای توضیح hover.
struct POIObj
{
   long            id;
   ENUM_POI_KIND   kind;
   ENUM_DIRECTION  direction;
   double          top, bottom;
   datetime        time;
   ENUM_TIMEFRAMES tf;
   bool            valid;
   string          invalidReason;
   int             score;
   long            sourceId;
};

// --- فاز ۱۲ (#۹): سن و مرحلهٔ روند
struct TrendState
{
   int              ageBars;      // چند کندل HTF از رویدادی که این Bias را ساخت
   datetime         sinceTime;
   long             sinceEventId;
   ENUM_TREND_PHASE phase;
   string           phaseReason;
};

TrendlineLiqObj g_trendlines[];
POIObj          g_poi[];
string          g_buildStamp="";   // فاز ۱۲: مهر بارگذاری (زمان attach همین instance)
TrendState      g_trend;

// --- فاز ۱۲ (#۳): ساختار داخلی **همان تایم‌فریم مالک** (نه ترند تایم‌فریم چارت)
ENUM_DIRECTION g_htfInternalDir = DIR_NONE;
string         g_htfInternalReason = "";

struct ExhaustionState
{
   ENUM_EXHAUSTION_STATE state;
   ENUM_DIRECTION direction;
   int score;
   int maxScore;
   datetime barTime;
   string reason;
};
ExhaustionState g_exhaustion;

struct MTFContextState
{
   ENUM_TIMEFRAMES timeframe;
   ENUM_DIRECTION externalDirection;
   ENUM_DIRECTION internalDirection;
   datetime confirmedBarTime;
   double protectedHigh;
   double protectedLow;
   string role;
};

MTFContextState g_mtfContext[6];
bool g_mtfConflict=false;
string g_mtfConflictReason="";
ENUM_TIMEFRAMES g_mtfTimeframes[6]={PERIOD_H4,PERIOD_H1,PERIOD_M15,PERIOD_M5,PERIOD_M2,PERIOD_M1};

// --- Time base و Context سشن‌ها (همه بر مبنای زمان کندل، نه TimeCurrent) ---
int  g_serverGMTOffsetSeconds = 0;    // بروکر -> GMT (دقیق، ثانیه؛ بروکرهای GMT+5:30 هم درست می‌شوند)
int  g_serverGMTOffsetHours   = 0;    // همان مقدار، فقط برای نمایش
int  g_brokerOffsetChanges    = 0;    // در این اجرا چند بار آفست بروکر عوض شد (#۵۵)
string g_brokerOffsetNote     = "";

// --- فاز ۱۵: پایهٔ آفست تاریخی بروکر ---
// آفست *جاری* بروکر از MT5 خوانده می‌شود، ولی آفست *تاریخی* فقط وقتی درست
// بازسازی می‌شود که آفست استاندارد (زمستان) و قاعدهٔ DST بروکر معلوم باشد.
int  g_brokerStdOffsetSeconds = 0;              // آفست زمستانی/استاندارد بروکر
ENUM_BROKER_DST_RULE g_brokerDSTRule = BDST_NONE; // قاعدهٔ مؤثر پس از حل AUTO
bool g_brokerDSTActiveNow = false;              // همین لحظه بروکر در DST است؟
string g_brokerOffsetSource = "";               // چطور تعیین شد (برای پنل و CSV)
int  g_histOffsetDeltaMin = 0;                  // اختلاف آفست لحظهٔ تحلیل با آفست جاری (دقیقه)

// --- فاز ۱۵: چرخهٔ عمر ستاپ (#۶۶) ---
string   g_setupLifeState = "IDLE";             // IDLE / TRACKING / INVALIDATED / TP1_HIT
ENUM_DIRECTION g_setupLifeDir = DIR_NONE;
double   g_setupLifeEntry=0, g_setupLifeSL=0, g_setupLifeTP1=0;
datetime g_setupLifeArmTime=0, g_setupLifeEndTime=0;
double   g_setupLifeEndPrice=0;
long     g_setupLifeChainId=-1;
string   g_setupLifeReason="";
int      g_setupArmedCount=0, g_setupInvalidCount=0, g_setupTP1Count=0;
datetime g_setupInvalidTime=0;
double   g_setupInvalidPrice=0;
ENUM_DIRECTION g_setupInvalidDir=DIR_NONE;
int      g_htfEventsDrawn=0;                    // چند رویداد HTF در این pass رسم شد
ENUM_DIRECTION g_mtfInternalDir = DIR_NONE;   // ساختار داخلی روی InpMTF (نقش واقعی ورودی #۶۱)
datetime g_mtfInternalBarTime = 0;
datetime g_mtfInternalBucket = 0;             // کش: آخرین باکت InpMTF که محاسبه شده
int  g_nyOffsetHoursNow     = -5;     // GMT -> NY
int  g_hourNYNow            = 0;
int  g_minNYNow             = 0;
ENUM_SILVERBULLET g_silverBullet = SB_NONE;
// فاز ۳۶: وضعیت Quarterly Theory — ساعت نیویورک (همهٔ محاسبات از NYStampOf می‌آید)
ENUM_QT_PHASE g_qtDayPhase    = QT_NONE;   // ربع روز (۶ ساعته)
ENUM_QT_PHASE g_qtWeekPhase   = QT_NONE;   // ربع هفته (دوشنبه‌محور، True Open هفته = دوشنبه ۰۰:۰۰ NY)
double        g_qtDayTrueOpen = 0.0;       // قیمت کندلی که ساعت نیویورک‌اش 00:00 است (True Open روز)
double        g_qtWkTrueOpen  = 0.0;       // True Open هفته = اولین کندل دوشنبه (بعد از 00:00 NY)
datetime      g_qtDayTrueOpenT= 0;
datetime      g_qtWkTrueOpenT = 0;
double g_asiaHigh=0,   g_asiaLow=0;
double g_londonHigh=0, g_londonLow=0;
double g_nyAmHigh=0,   g_nyAmLow=0;
datetime g_asiaStart=0,   g_asiaEnd=0;
datetime g_londonStart=0, g_londonEnd=0;
datetime g_nyAmStart=0,   g_nyAmEnd=0;
double g_htfRangeHigh=0, g_htfRangeLow=0;
// --- فاز ۱۰: یک منبع قیمت/نوسان برای کل زنجیره (#۴۵) ---
double   g_analysisClose=0.0;   // همان close کندل تحلیلی که موتور ستاپ استفاده می‌کند
double   g_analysisATR=0.0;     // ATR همان کندل
double   g_stopsLevelPrice=0.0; // SYMBOL_TRADE_STOPS_LEVEL تبدیل‌شده به قیمت
string   g_dolRejectReason="";  // اگر DOL پیدا نشد، دلیل واقعی
// --- فاز ۱۳ (#۷): نگهبان «حداکثر یک ارزیابی ساختار به‌ازای هر کندل HTF» ---
datetime g_lastHtfEvalBarTime = 0;   // باکت HTF که آخرین بار ارزیابی شد
datetime g_lastHtfEvalStamp   = 0;   // مهر زمانی آخرین ارزیابی (برای شاهد عددی)
long     g_htfEvalRuns        = 0;   // چند بار واقعاً ارزیابی شد
long     g_htfEvalSkips       = 0;   // چند فراخوانی در همان باکت رد شد (جلوگیری از BOS تکراری)

// --- فاز ۱۳ (#۱۱): شمارندهٔ یکنوا و آمار سیاست حذف FIFO ---
// شمارندهٔ یکنوا لازم است: وقتی سقف رجیستری پر شود، اندازهٔ آرایه دیگر
// افزایش پیدا نمی‌کند، پس تشخیص «رویداد تازه‌ای ساخته شد؟» با ArraySize غلط می‌شود.
long     g_eventsAdded        = 0;
long     g_eventsDropped      = 0;
long     g_dispDropped        = 0;

// --- فاز ۱۳ (کارایی): کش شناسه‌های دفتر رویداد — به‌جای اسکن کل فایل برای هر رویداد ---
string   g_ledgerCacheName    = "";
long     g_ledgerCacheIds[];
long     g_ledgerCacheHits    = 0;
long     g_ledgerCacheBuilds  = 0;

// --- فاز ۱۳ (کارایی): یک کپی مشترک از دادهٔ منبع‌سشن برای همهٔ پنجره‌های همان کندل ---
string   g_winCacheSymbol     = "";
ENUM_TIMEFRAMES g_winCacheTF  = PERIOD_CURRENT;
datetime g_winCacheNewest     = 0;
datetime g_winCacheT[];
double   g_winCacheH[];
double   g_winCacheL[];
// فاز ۳۴: open/close هم لازم شد — نوع روز بر مبنای «close در کدام ربع دامنهٔ روز»
// و «open نسبت به دامنهٔ روز قبل» تعریف می‌شود، پس فقط H/L کافی نیست.
double   g_winCacheO[];
double   g_winCacheC[];
bool     g_winCacheExhausted = false; // تاریخچه کمتر از درخواست بود
long     g_winCacheCopies     = 0;   // چند بار واقعاً Copy انجام شد
long     g_winCacheReuses     = 0;   // چند بار از بافر مشترک استفاده شد

// --- فاز ۱۳ (کارایی): کش تشخیص EQ تا وقتی مجموعهٔ سوئینگ‌ها عوض نشده ---
int      g_eqStampCount       = -1;
long     g_eqStampLastId      = 0;
datetime g_eqStampLastTime    = 0;
double   g_eqStampTol         = -1.0;
long     g_eqSkips            = 0;
long     g_obsDeduped         = 0;   // فاز ۲۹: چند OB تکراری (همان ناحیه) ادغام شد

// --- فاز ۳۲: شاهد «ریسک برگشت» (درصد فقط از داده شمرده می‌شود، نه از این اعداد) ---
bool   g_barSweptTowardBias = false;   // در همین کندل نقدینگی سمت Bias جارو شد و پشت سطح بسته شد
int    g_rrEventBarsAgo     = -1;     // چند کندل از آخرین رویداد ساختاری گذشته
string g_rrLevel            = "NONE"; // نزدیک‌ترین سطح به قیمت (نوع + جهت)
double g_rrLevelDist        = 0.0;    // فاصله تا آن سطح (× ATR)
string g_rrLevelState       = "-";
double g_rrLegProg          = 0.0;    // قیمت در کجای لگ معامله‌گری است (٪ در جهت لگ)
double g_rrDolDist          = 0.0;    // فاصله تا هدف نقدینگی (× ATR؛ منفی = از هدف گذشته)
int    g_rrScore            = 0;      // امتیاز هشدار ۰..۱۰۰ — مجموع وزن‌های مستند، «درصد» نیست
string g_rrLabel            = "LOW";
string g_rrReasons          = "";
// فاز ۳۵: نوار تک‌خطی — کش متن برای جلوگیری از بازنویسی بی‌دلیل در هر tick
string g_riskStripLastText  = "";
bool   g_riskStripOn        = false;

// --- فاز ۴۶: درجهٔ سیگنال A+/A/B+/B/C (تیتر بالای چارت) ---
// ضرایب از داده سنجیده شده‌اند (tools/Fit-SignalGrade.ps1)؛ این متغیرها فقط
// نتیجهٔ همان محاسبه برای کندل بستهٔ جاری‌اند و کش می‌شوند تا نوار در هر tick
// مجبور به بازمحاسبه نباشد.
string g_grade          = "—";   // A+ / A / B+ / B / C / —
string g_gradeFam       = "";    // کد خانوادهٔ نزدیک‌ترین سطح (famLIQ و ...)
double g_gradeScore     = 0.0;   // مجموع لیفت‌های سنجیده‌شده
double g_gradeWin       = 0.0;   // نرخ بردِ اندازه‌گیری‌شدهٔ همین درجه (٪)
int    g_gradeN         = 0;     // تعداد نمونهٔ همان سنجش
string g_gradeWhy       = "";    // بزرگ‌ترین بالابرنده و کاهنده
long   g_gradeComputed  = 0;     // شمارندهٔ محاسبه‌ها (شاهد اجرا)

// --- فاز ۴۷: سناریوی در انتظار. این متغیرها **فقط نمایشی** هستند و هیچ موتور
// تشخیصی آن‌ها را نمی‌خواند؛ پس نمی‌توانند روی رسم/رجیستری/بایاس اثر بگذارند.
bool   g_pendValid         = false;
string g_pendState         = "OFF";   // OFF / NO_BIAS / NO_GUARD / NO_ATR / WAITING / CONFIRMED_NOW
string g_pendTriggerFa     = "";      // متن ماشه: «بستهٔ زیر/بالای <سطح>»
double g_pendGuardDistATR  = 0.0;     // فاصلهٔ کندل بستهٔ HTF تا سطح، بر حسب دامنه
string g_pendBucket        = "";      // کد سبد فاصله (هم‌نام با ابزار فیت)
double g_pendRate          = 0.0;     // نرخ سنجیده‌شدهٔ همان سبد (درصد)
int    g_pendRateN         = 0;       // تعداد نمونهٔ همان سنجش
double g_pendBaselineRate  = 0.0;     // خط پایهٔ همان سنجش (درصد)
string g_pendMagnetName    = "";      // برچسب لاتین مقصد نقدینگی (برای پنل)
string g_pendMagnetTypeFa  = "";      // برچسب فارسی مقصد (برای ردیف روی چارت)
double g_pendMagnetPrice   = 0.0;
double g_pendMagnetDistATR = 0.0;
string g_pendLineText      = "";
// فاز ۴۸: ردیف جداگانهٔ «در انتظار» با نوار درجه ادغام شد. این پرچم فقط
// یک‌بار، در اولین پاس، اشیای ردیف قدیمی را از چارت پاک می‌کند.
bool   g_pendRowCleaned    = false;
long   g_pendComputed      = 0;       // شمارندهٔ محاسبه‌ها (شاهد اجرا)
// مقادیر همان کندل برای ثبت شاهد: نوشتن ردیف به بعد از محاسبهٔ درجه موکول
// شده تا ستون‌های درجه هرگز از کندل قبلی نیایند.
bool     g_rrHasRow = false;
datetime g_rrBarTime = 0;
double   g_rrClose = 0.0, g_rrHigh = 0.0, g_rrLow = 0.0, g_rrAtr = 0.0;

//====================================================================
// فاز ۲۴ (کارایی): پروب زمان‌سنج میکروثانیه‌ای
// مرجع رسمی MQL5 («Program Running»): همهٔ اندیکاتورهای یک نماد در **یک**
// ترد مشترک اجرا می‌شوند؛ پس هزینهٔ هر کندل، سرعت کل چارت را می‌گیرد.
// روش اندازه‌گیری هم همان چیزی است که مستندات MQL5 توصیه می‌کند
// (GetMicrosecondCount). پروب فقط وقتی روشن است هزینه دارد.
//====================================================================
#define PROBE_MAX 40
bool   g_probeOn=false;
string g_probeName[PROBE_MAX];
long   g_probeTotal[PROBE_MAX];
int    g_probeUsed=0;

void ProbeReset()
{
   for(int i=0;i<PROBE_MAX;i++) g_probeTotal[i]=0;
   g_probeUsed=0;
}

void ProbeAdd(const string name, long us)
{
   if(us<0) us=0;
   for(int i=0;i<g_probeUsed;i++)
      if(g_probeName[i]==name){ g_probeTotal[i]+=us; return; }
   if(g_probeUsed<PROBE_MAX)
   {
      g_probeName[g_probeUsed]=name;
      g_probeTotal[g_probeUsed]=us;
      g_probeUsed++;
   }
}

// سنگین‌ترین مرحله‌ها به ترتیب نزولی — دلیل هر گلوگاه را از داده می‌گوید، نه از حدس
string ProbeDumpTop(int top)
{
   string out="";
   bool   used[PROBE_MAX];
   for(int i=0;i<PROBE_MAX;i++) used[i]=false;
   for(int k=0;k<top;k++)
   {
      int best=-1;
      for(int i=0;i<g_probeUsed;i++)
      {
         if(used[i]) continue;
         if(best<0 || g_probeTotal[i]>g_probeTotal[best]) best=i;
      }
      if(best<0) break;
      used[best]=true;
      out += g_probeName[best]+"="+IntegerToString((int)g_probeTotal[best])+"us ";
   }
   return out;
}

#define PROBE_T0 (long)(g_probeOn?GetMicrosecondCount():(ulong)0)
#define PROBE_END(nm,t0) if(g_probeOn) ProbeAdd(nm,(long)GetMicrosecondCount()-(long)(t0))

// --- فاز ۲۴ (کارایی): کش زمان کندل
// iTime یک دسترسی timeseries است؛ صدا زدنش داخل حلقهٔ بازسازی (چند بار در
// هر کندل × صدها کندل) هزینهٔ بی‌دلیل است. یک بار CopyTime و بعد خواندن
// از آرایه — همان الگویی که مستند رسمی برای دسترسی پرتکرار توصیه می‌کند.
datetime g_barT[];
int      g_barTCount=0;

void RefreshBarTimeCache(int need)
{
   if(need<8) need=8;
   ArraySetAsSeries(g_barT,true);
   int got=CopyTime(_Symbol,PERIOD_CURRENT,0,need,g_barT);
   g_barTCount=(got>0)?got:0;
}

datetime BarTime(int shift)
{
   if(shift>=0 && shift<g_barTCount) return g_barT[shift];
   return iTime(_Symbol,PERIOD_CURRENT,shift);
}

//====================================================================
// فاز ۲۴ (کارایی): هندلِ نگه‌داشته‌شدهٔ فایل‌های شاهد در بازسازی
// هر FileOpen/FileWrite/FileClose روی پوشهٔ Common یک رفت‌وبرگشت دیسک
// است (و اسکنر آنتی‌ویروس روی همان فایل). در بازسازی ۶۰۰ کندلی، توابع
// شاهد تقریباً هر کندل یک ردیف می‌نویسند ⇒ بیش از هزار چرخهٔ باز/بسته.
// با هندل مشترک، همان ردیف‌ها با همان ترتیب و همان سرستون نوشته می‌شوند
// و تعداد چرخه‌های دیسک به «تعداد فایل‌ها» می‌رسد. در حالت زنده هیچ
// تغییری نیست (همان open/write/close قبلی) تا رفتار ابزارهای خوانندهٔ
// CSV عوض نشود.
//====================================================================
#define DIAG_HOLD_SLOTS 6
bool   g_diagHoldOn=false;
string g_diagHoldName[DIAG_HOLD_SLOTS];
int    g_diagHoldHandle[DIAG_HOLD_SLOTS];
int    g_diagHoldUsed=0;

int DiagHoldIndex(const string fileName)
{
   for(int i=0;i<g_diagHoldUsed;i++)
      if(g_diagHoldName[i]==fileName) return i;
   return -1;
}

int DiagOpen(const string fileName)
{
   if(g_diagHoldOn)
   {
      int idx=DiagHoldIndex(fileName);
      if(idx>=0 && g_diagHoldHandle[idx]!=INVALID_HANDLE) return g_diagHoldHandle[idx];
   }
   int h=FileOpen(fileName,FILE_COMMON|FILE_READ|FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_SHARE_WRITE,';');
   if(g_diagHoldOn && h!=INVALID_HANDLE && g_diagHoldUsed<DIAG_HOLD_SLOTS)
   {
      g_diagHoldName[g_diagHoldUsed]=fileName;
      g_diagHoldHandle[g_diagHoldUsed]=h;
      g_diagHoldUsed++;
   }
   return h;
}

// فراموش‌کردن اسلات، بدون بستن هندل (تنها برای مسیر خود-ترمیمی سرستون:
// فراخوانی خودش FileClose و FileDelete می‌زند و بدین‌ترتیب در هر دو حالت
// زنده و بازسازی یک‌بار بسته می‌شود — بستن دوباره خطرناک است).
void DiagDrop(const string fileName)
{
   int idx=DiagHoldIndex(fileName);
   if(idx<0) return;
   g_diagHoldName[idx]="";
   g_diagHoldHandle[idx]=INVALID_HANDLE;
}

void DiagClose(const int handle)
{
   if(g_diagHoldOn) return;                 // در بازسازی باز می‌ماند
   if(handle!=INVALID_HANDLE) FileClose(handle);
}

void DiagHoldRelease()
{
   for(int i=0;i<g_diagHoldUsed;i++)
      if(g_diagHoldHandle[i]!=INVALID_HANDLE) FileClose(g_diagHoldHandle[i]);
   for(int i=0;i<DIAG_HOLD_SLOTS;i++){ g_diagHoldName[i]=""; g_diagHoldHandle[i]=INVALID_HANDLE; }
   g_diagHoldUsed=0;
   g_diagHoldOn=false;
}

bool   g_historyRebuilt=false;
bool   g_rebuildMode=false;
datetime g_lastContextBarTime=0;

int    g_atrHandle = INVALID_HANDLE;

//====================================================================
// UTILITIES
//====================================================================

long StableSwingId(datetime swingTime, bool isHigh)
{
   return (long)swingTime*2L + (isHigh?1L:0L);
}

long StableEventId(datetime eventTime, ENUM_EVENT_TYPE type, ENUM_DIRECTION direction, long brokenSwingId, bool isHTF)
{
   long swingPart=MathAbs(brokenSwingId%900000L);
   return (long)eventTime*1000000L + swingPart + (long)type*100L + (long)direction*10L + (isHTF?1L:0L);
}

long StableLiquidityId(datetime levelTime, ENUM_LIQ_TYPE type, double price, bool isHTF)
{
   long priceTicks=(long)MathRound(price/_Point);
   return (long)levelTime*1000000L + (long)type*100000L + (isHTF?50000L:0L) + MathAbs(priceTicks%100000L);
}

long StableDisplacementId(datetime barTime, ENUM_DIRECTION direction)
{
   return (long)barTime*10L + (long)direction;
}

long StableZoneId(datetime zoneTime, ENUM_DIRECTION direction, int kind)
{
   return (long)zoneTime*100L + (long)kind*10L + (long)direction;
}

// آبجکت‌های چارت با شناسهٔ ۶۴ بیتی Registry نام‌گذاری می‌شوند. اگر این شناسه
// به int تبدیل شود (مثل IntegerToString((int)id)) بریده می‌شود و دیگر با
// Registry یکی نیست؛ در نتیجه هنگام hover هیچ توضیحی پیدا نمی‌شود. پس همیشه
// از همین helper برای نام‌گذاری استفاده کن.
string IdToStr(const long id) { return StringFormat("%I64d", id); }

// فاز ۱۱ (#۸/#۷۱): شناسهٔ سویینگ محافظت‌شده به قیمت/زمان واقعی تبدیل می‌شود.
// قبلاً این شناسه‌ها نوشته می‌شدند و هیچ‌جا خوانده نمی‌شدند، پس دروازهٔ برگشت
// وجود نداشت. اگر سویینگ با سقف InpMaxSwings از رجیستری حذف شده باشد،
// false برمی‌گردد و وضعیت صادقانه WAITING_PROTECTED_LEVEL می‌شود.
bool SwingById(SwingPoint &swings[], long id, double &priceOut, datetime &timeOut, bool &isHighOut)
{
   priceOut=0.0; timeOut=0; isHighOut=false;
   if(id==-1) return false;
   for(int i=0;i<ArraySize(swings);i++)
   {
      if(swings[i].id==id)
      {
         priceOut=swings[i].price;
         timeOut =swings[i].time;
         isHighOut=swings[i].isHigh;
         return true;
      }
   }
   return false;
}

// فاز ۱۳ (کارایی): قبلاً برای **هر** رویداد کل فایل دفتر خوانده می‌شد
// (O(n²) I/O). حالا ایندکس شناسه‌ها یک بار در رم ساخته می‌شود.
// معادل‌بودن با نسخهٔ قبلی: ستون اول هر ردیف همان شناسهٔ عددی است و همهٔ
// شناسه‌ها از StableEventId می‌آیند (time*1e6 + ...) پس همیشه > 0 هستند؛
// ردیف سرستون یا مقدار ناخوانا عدد ۰ می‌دهد و با هیچ شناسه‌ای برخورد نمی‌کند.
void EnsureLedgerIndex(string ledgerName)
{
   if(g_ledgerCacheName==ledgerName) return;
   g_ledgerCacheName=ledgerName;
   ArrayResize(g_ledgerCacheIds,0);
   g_ledgerCacheBuilds++;
   int handle=FileOpen(ledgerName,FILE_COMMON|FILE_READ|FILE_CSV|FILE_SHARE_READ|FILE_SHARE_WRITE,';');
   if(handle==INVALID_HANDLE) return;
   while(!FileIsEnding(handle))
   {
      string storedId=FileReadString(handle);
      if(StringLen(storedId)>0)
      {
         int m=ArraySize(g_ledgerCacheIds);
         ArrayResize(g_ledgerCacheIds,m+1);
         g_ledgerCacheIds[m]=(long)StringToInteger(storedId);
      }
      for(int column=1; column<11 && !FileIsEnding(handle); column++) FileReadString(handle);
   }
   FileClose(handle);
}

bool EventLedgerContains(string ledgerName, const long eventId)
{
   EnsureLedgerIndex(ledgerName);
   int n=ArraySize(g_ledgerCacheIds);
   for(int i=0;i<n;i++)
      if(g_ledgerCacheIds[i]==eventId) { g_ledgerCacheHits++; return true; }
   return false;
}

void LedgerIndexAdd(string ledgerName, const long eventId)
{
   EnsureLedgerIndex(ledgerName);
   int n=ArraySize(g_ledgerCacheIds);
   ArrayResize(g_ledgerCacheIds,n+1);
   g_ledgerCacheIds[n]=eventId;
}

// فاز ۲۲ — ایراد واقعی که از خود شاهد runtime پیدا شد:
// دفتر رویداد زنده یک نام **مشترک** داشت، پس هر چارت/اندیکاتوری که در همان
// ترمینال به همان فایل COMMON می‌نوشت، ردیف‌هایش قاطی دفتر XAUUSD می‌شد.
// در دفتر واقعی، ردیف‌هایی با قیمت ۱۷۹٫۱ (یک نماد دیگر) داخل دفتر XAUUSD
// دیده شد و دقیقاً همان ردیف‌ها ترتیب زمانی را می‌شکستند (یعنی «nتأیید دستی
// محاسبات» ناممکن بود). حالا نام دفتر به نماد چارت مقید است.
string EventLedgerFileName()
{
   string sym="";
   int n=StringLen(_Symbol);
   for(int i=0;i<n;i++)
   {
      ushort c=StringGetCharacter(_Symbol,i);
      bool ok=((c>='0'&&c<='9')||(c>='A'&&c<='Z')||(c>='a'&&c<='z')||c=='-');
      sym+=ShortToString(ok? c : (ushort)'_');
   }
   if(StringLen(sym)==0) sym="SYMBOL";
   return ICT_EVENT_LEDGER_BASE+"_"+sym+".csv";
}

void PersistStructureEvent(const StructureEvent &eventData)
{
   // Rebuild evidence belongs in its own ledger. Never mix historical replay
   // rows into the live event ledger.
   if(g_rebuildMode && !InpWriteLedgerDuringRebuild && !InpWriteReplayDiagnostics) return;
   string ledgerName=(g_rebuildMode && InpWriteReplayDiagnostics)?ICT_REPLAY_LEDGER:EventLedgerFileName();
   if(EventLedgerContains(ledgerName,eventData.id)) return;
   int handle=FileOpen(ledgerName,FILE_COMMON|FILE_READ|FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_SHARE_WRITE,';');
   if(handle==INVALID_HANDLE) return;
   FileSeek(handle,0,SEEK_END);
   // فاز ۲۲ — ایراد داده‌ای واقعی در دفتر شاهد:
   // این چهار ستون قبلاً با (int) نوشته می‌شدند. شناسهٔ سوئینگ/جابجایی
   // ۶۴ بیتی است (swingTime*2 ≈ 3.58e9) و در int32 می‌شرد؛ در CSV عدد
   // منفی/بی‌معنا می‌شد (مثل -715967644) و دیگر با Registry قابل تطبیق نبود،
   // یعنی همان چیزی که کاربر برای «تأیید دستی محاسبات» لازم دارد از بین می‌رفت.
   // همهٔ ستون‌های شناسه حالا با IdToStr (رشتهٔ ۶۴ بیتی) نوشته می‌شوند.
   FileWrite(handle,IdToStr(eventData.id),TimeToString(eventData.time,TIME_DATE|TIME_MINUTES),
             EventTypeToStr(eventData.type),DirToStr(eventData.direction),
             DoubleToString(eventData.price,_Digits),(int)eventData.confirmationBarShift,
             IdToStr(eventData.brokenSwingId),IdToStr(eventData.protectedSwingId),
             IdToStr(eventData.displacementId),IdToStr(eventData.sweepId),eventData.isHTF);
   FileClose(handle);
   // فاز ۱۳: ایندکس رم همان لحظه به‌روز می‌شود تا ردیف تازه دوباره نوشته نشود.
   LedgerIndexAdd(ledgerName,eventData.id);
}

double PointsToPrice(double pts) { return pts * _Point; }

ENUM_DIRECTION OppositeDir(ENUM_DIRECTION d)
{
   if(d==DIR_BULL) return DIR_BEAR;
   if(d==DIR_BEAR) return DIR_BULL;
   return DIR_NONE;
}

//--------------------------------------------------------------------
// فاز ۴۳ — "نقش فعلی" یک ناحیه، در یک جا تعریف می‌شود
//--------------------------------------------------------------------
// قاعده‌ای که این دو تابع تثبیت می‌کنند:
//   جهت **تولد** هرگز تغییر نمی‌کند. هندسهٔ ناحیه (top/bottom)، جهت حرکت
//   سازندهٔ آن و شناسه‌اش همه به تولد گره خورده‌اند. اما ناحیه‌ای که پولاریتی‌اش
//   برگشته، از آن لحظه در جهت مخالف کار می‌کند. این دو حقیقت جدا هستند و باید
//   جدا بمانند؛ هر مصرف‌کننده‌ای که می‌پرسد «این ناحیه الان در چه جهتی کار
//   می‌کند؟» باید همین تابع را صدا بزند.
//
// ریشهٔ باگ قبلی: تابع وارونگی، `direction` را بازنویسی می‌کرد. پس یک فیلد دو
// معنی داشت و خروجی‌ها بر اساس زمان خواندن متناقض می‌شدند — مربعِ وارون (رنگ
// عوض‌شده)، ردیف CSV (جهت بازنویسی‌شده)، پنل، و انتخاب ناحیهٔ ستاپ.
ENUM_DIRECTION FVGActiveDir(const FVGObj &f)
{
   return f.inverted? OppositeDir(f.direction) : f.direction;
}

// OB همین قاعده را دارد، با یک تفاوت: در OB پرچم جدا (polarityFlipped) و
// حالت‌های نهایی BREAKER/MITIGATION_BLOCK نگه داشته شده‌اند، پس جهت تولد همیشه
// دست‌نخورده مانده است. این تابع فقط برای آن مصرف‌کننده‌هایی است که نقش
// **فعلی** را گزارش می‌کنند (رجیستری POI و برچسب سطح)، وگرنه ناحیهٔ شکسته که
// دیگر سطح ورود نیست نباید دوباره به‌عنوان سطح دست‌نخورده معرفی شود.
ENUM_DIRECTION OBActiveDir(const OBObj &o)
{
   return o.polarityFlipped? OppositeDir(o.direction) : o.direction;
}

// فاز ۴۷ — کد کوتاه تایم‌فریم چارت، برای نام فایل شاهد. چرا لازم شد: تا فاز ۴۶
// دفتر برگشت و دفتر ریسک برگشت فقط نام نماد داشتند، پس دو چارت زندهٔ یک نماد
// (مثلاً M1 و M15) ردیف‌هایشان را در **یک فایل** می‌ریختند و هر اندازه‌گیری روی
// آن دفتر، دو تایم‌فریم را قاطی می‌کرد. کاربر خواسته است هر تایم‌فریم برای خودش
// باشد؛ این تابع همان جداسازی را در نام فایل انجام می‌دهد.
string ChartTfCode()
{
   switch((ENUM_TIMEFRAMES)Period())
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M2:  return "M2";
      case PERIOD_M3:  return "M3";
      case PERIOD_M4:  return "M4";
      case PERIOD_M5:  return "M5";
      case PERIOD_M6:  return "M6";
      case PERIOD_M10: return "M10";
      case PERIOD_M12: return "M12";
      case PERIOD_M15: return "M15";
      case PERIOD_M20: return "M20";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";
      case PERIOD_H3:  return "H3";
      case PERIOD_H4:  return "H4";
      case PERIOD_H6:  return "H6";
      case PERIOD_H8:  return "H8";
      case PERIOD_H12: return "H12";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
   }
   int sec=PeriodSeconds(PERIOD_CURRENT);
   if(sec<=0) sec=60;
   return "T"+IntegerToString(sec/60);   // تایم‌فریم سفارشی → دقیقه
}

string DirToStr(ENUM_DIRECTION d)
{
   switch(d){ case DIR_BULL: return "BULLISH"; case DIR_BEAR: return "BEARISH"; default: return "NEUTRAL"; }
}

string EventTypeToStr(ENUM_EVENT_TYPE t)
{
   switch(t)
   {
      case EVT_BOS:            return "BOS";
      case EVT_CHOCH:          return "CHoCH";
      case EVT_EXTERNAL_BREAK: return "EXTERNAL_BREAK";
      default:                 return "MSS";
   }
}

string LiqTypeToStr(ENUM_LIQ_TYPE t)
{
   switch(t)
   {
      case LIQ_PDH: return "PDH"; case LIQ_PDL: return "PDL";
      case LIQ_PWH: return "PWH"; case LIQ_PWL: return "PWL";
      case LIQ_EQH: return "EQH"; case LIQ_EQL: return "EQL";
      case LIQ_SWING_H: return "Swing High"; case LIQ_SWING_L: return "Swing Low";
      case LIQ_SESSION_H: return "Session High"; default: return "Session Low";
   }
}

//====================================================================
// TIME BASE — آفست واقعی بروکر و ساعت نیویورک (DST-aware).
// قاعده: هیچ محاسبه Context نباید به TimeCurrent وابسته باشد؛ همه چیز
// بر مبنای زمان کندلِ در حال تحلیل است تا بازپخش/تاریخ قابل اثبات بماند.
//====================================================================
int DayOfWeekOf(int year, int month, int day)
{
   MqlDateTime dt;
   dt.year=year; dt.mon=month; dt.day=day; dt.hour=12; dt.min=0; dt.sec=0;
   MqlDateTime out; TimeToStruct(StructToTime(dt), out);
   return out.day_of_week;   // 0 = Sunday
}

int NthSundayOfMonth(int year, int month, int nth)
{
   int firstDow    = DayOfWeekOf(year, month, 1);
   int firstSunday = 1 + ((7 - firstDow) % 7);
   return firstSunday + (nth-1)*7;
}

// ---- قاعدهٔ DST آمریکا: دقیق تا ثانیه، بر مبنای UTC (رفع #۵۶) ----
// عبور از ساعت تابستانی در آمریکا:
//   شروع: دومین یکشنبهٔ مارس، ساعت ۰۲:۰۰ EST  = ۰۷:۰۰ UTC
//   پایان: اولین یکشنبهٔ نوامبر، ساعت ۰۲:۰۰ EDT = ۰۱:۰۰ EST = ۰۶:۰۰ UTC
// نسخهٔ قبلی با «روز شروع» مقایسه می‌کرد و کل آن روز را غیر‌DST می‌گرفت؛
// نتیجه تا ۳ ساعت خطا در مرز سالانه بود. این نسخه از خود لحظهٔ UTC استفاده می‌کند.
datetime UTCBoundFor(int year, int month, int nthSunday, int hour, int minute)
{
   MqlDateTime d;
   d.year=year; d.mon=month; d.day=NthSundayOfMonth(year,month,nthSunday);
   d.hour=hour; d.min=minute; d.sec=0;
   return StructToTime(d);
}

// قاعدهٔ خالص آمریکا (مستقل از ورودی ساعت نیویورک؛ برای قاعدهٔ DST بروکر لازم است)
bool US_IsDST_UTC(datetime utcT)
{
   MqlDateTime d; TimeToStruct(utcT,d);
   if(d.mon<3 || d.mon>11) return false;
   datetime startU=UTCBoundFor(d.year,3,2,7,0);
   datetime endU  =UTCBoundFor(d.year,11,1,6,0);
   return (utcT>=startU && utcT<endU);
}

bool NY_IsDST_UTC(datetime utcT)
{
   if(!InpUseUS_DSTForNYClock) return false;
   return US_IsDST_UTC(utcT);
}

//====================================================================
// فازهای ۱۶–۲۱ (2026-09-18): شش خانوادهٔ باقی‌مانده
//   ۱۶ Wyckoff · ۱۷ Supply&Demand · ۱۸ Al Brooks · ۱۹ RTM · ۲۰–۲۱ Profile
// همهٔ محاسبات روی کندل بسته است (قانون ۸) و خروجی با hover فارسی
// و رعایت بهداشت نمایش (حذف فیلدشده‌ها) رندر می‌شود.
//====================================================================

// ---------- ساختارهای مشترک ----------
// فاز ۳۳: WE_PS و WE_PSY در انتهای enum اضافه شدند تا مقدار عددی اعضای قبلی
// عوض نشود (شناسه‌ها/رجیستری‌های ذخیره‌شده نشکنند) — همان درس فاز ۳۰.
enum ENUM_WYCK_EVENT  { WE_NONE, WE_SC, WE_BC, WE_AR, WE_ST, WE_SPRING, WE_UPTHRUST, WE_SOS, WE_SOW, WE_LPS, WE_LPSY, WE_TEST, WE_ABSORPTION, WE_PS, WE_PSY };
enum ENUM_WYCK_PHASE  { WP_NONE, WP_A, WP_B, WP_C, WP_D, WP_E };
enum ENUM_SD_KIND     { SDK_RBR, SDK_DBD, SDK_RBD, SDK_DBR, SDK_SUPPLY, SDK_DEMAND };
enum ENUM_SD_STATE    { SDS_FRESH, SDS_TESTED, SDS_FLIPPED, SDS_BROKEN };

// فاز ۳۳: وضعیت زندهٔ ساختار Wyckoff — منبع: توالی PS→SC→AR→ST (فاز A)،
// آزمون‌ها و جذب (فاز B)، شیکاوت (فاز C)، SOS و LPS (فاز D)، روند بیرون (فاز E).
struct WyckRangeState
{
   bool     hasClimax;      // SC یا BC شناسایی شد
   bool     isAccum;        // true=SC (Accumulation) · false=BC (Distribution)
   bool     hasPS;          // PS/PSY فاز A
   bool     hasAR;          // AR فاز A → مرز ساختار تعیین شد
   bool     hasST;          // ST فاز A → پایان فاز A
   bool     hasShakeout;    // Spring/UTAD فاز C
   bool     hasSOS;         // SOS/SOW فاز D
   bool     hasLPS;         // LPS/LPSY
   double   ceiling;        // سقف ساختار (AR در Accumulation)
   double   floor;          // کف ساختار (AR در Distribution)
   double   climaxPrice;    // اکستریم کلایمکس
   double   climaxVol;      // tick-volume کلایمکس (مرجع «حجم سبک‌تر» ST)
   double   climaxVolRatio; // نسبت حجم کلایمکس به میانگین (برای گزارش)
   datetime climaxTime;
   datetime sosTime;
   datetime lastLPSTime;
   double   lastLPSPrice;
   int      barsInRange;
   int      barsBeyond;     // کندل‌های پیوستهٔ بیرون ساختار (شرط فاز E)
   string   resetReason;
};
WyckRangeState g_wyckRange;

struct WyckoffObj
{
   ENUM_WYCK_EVENT evt;      // نوع رویداد
   datetime        time;     // زمان کندل تأیید
   double          price;    // قیمت محوری رویداد
   long            id;
   ENUM_WYCK_PHASE phase;    // فاز A–E فعلی
   string          phaseReason;
};

struct SDObj
{
   long            id;
   ENUM_SD_KIND    kind;
   ENUM_SD_STATE   state;
   datetime        time;     // پایان پایه
   double          top, bottom;
   int             tests;    // تعداد برخورد (قدرت/تازگی)
   double          exitMove; // اندازهٔ حرکت خروج از پایه (شارپ بودن)
   ENUM_TIMEFRAMES tf;       // تایم‌فریم مالک (هر تایم‌فریم رسم مخصوص خودش)
   int             strength;      // فاز ۳۶: امتیاز ترکیبی قدرت ناحیه ۱..۵
   string          strengthText;  // فاز ۳۶: تفکیک عددی برای پنل
   // فاز ۳۳: نقش زندهٔ ناحیه. یک Flip Zone واقعاً نقش عوض می‌کند (Supply ↔ Demand)
   // و باید همان‌جا هم رهگیری شود؛ قبلاً پس از FLIP هیچ lifecycle ای اجرا نمی‌شد.
   bool            roleSupply;   // نقش فعلی: true=Supply · false=Demand
   bool            flipped;      // آیا نقش عوض شده
   datetime        flipTime;     // کندل Flip (شرط ورود در جهت مخالف)
   double          flipLevel;    // قیمتی که Flip با آن تأیید شد
};

struct BrooksBarInfo
{
   bool  isTrendBar;
   bool  isDoji;
   bool  isSignalBar;
   bool  isEntryBar;
   bool  followThrough;
   bool  alwaysInLong;
   bool  alwaysInShort;  // فاز ۳۳: وضعیت Always-In باید هر دو جهت را داشته باشد
   int   alwaysIn;       // +1 صعودی · -1 نزولی · 0 خنثی (وضعیت، نه سه‌کندل‌هم‌رنگ)
   bool  bullSignal;     // سیگنال با بافت (انتهای لگ مخالف + بسته نزدیک سقف)
   bool  bearSignal;
   bool  h1, h2, h3, h4; // شمارش تلاش‌های صعودی در پولبک
   bool  l1, l2, l3, l4; // شمارش تلاش‌های نزولی در پولبک
   int   hAttempts;      // عدد خام شمارش (برای نمایش و آموزش)
   int   lAttempts;
   double ema20;         // مرجع رسمی لیست خواسته‌ها: 20 EMA
   bool  failedBreakout;
   // --- فاز ۳۶: Trading Range / Measured Move / Channel ---
   bool  inTradingRange;      // رنج دوطرفهٔ فعال (bull case و bear case هر دو زنده)
   double trHigh, trLow;      // مرزهای رنج دوطرفه
   double trMid;              // مغناطیس ۵۰٪ رنج (Brooks: «the middle of the range is a magnet»)
   int    trBars;             // عمر رنج
   bool   trBreakUp, trBreakDn;     // شکست مؤثر از رنج (بستهٔ قاطع)
   bool   trFailedBreakUp, trFailedBreakDn; // شکست فقط با فتیله + بسته داخل = شکست ناموفق
   bool   mmValid;                  // Measured Move AB=CD معتبر
   double mmA, mmB, mmC, mmD;       // نقاط A/B/C/D (D = هدف ۱۰۰٪ امتداد)
   datetime mmTimeA, mmTimeB, mmTimeC;
   int    chSlope;                  // شیب کانال: +1 صعودی، -1 نزولی، 0 بدون کانال
};

struct ProfileRow
{
   double priceLo, priceHi;
   long   vol;             // tick-volume
};

struct ProfileResult
{
   bool   valid;
   double poc;             // Point of Control
   double vah, val;        // Value Area high/low
   double ibHigh, ibLow;   // Initial Balance
   double sessionHigh, sessionLow;
   long   totalVol;
   int    pocRowIndex;
   // ---------------- فاز ۳۴: Auction Market Theory ----------------
   bool   tpoValid;        // آیا پروفایل TPO (زمانی) ساخته شده
   double tpoPoc, tpoVah, tpoVal;   // POC/VA بر پایهٔ TPO (شمارش زمان، نه حجم)
   int    tpoPocRow;
   bool   amtValid;        // آیا تحلیل روز (IB/نوع روز/نوع باز شدن) ساخته شده
   double dayOpen, dayClose, dayHi, dayLo;
   double ibHi, ibLo;      // Initial Balance با مرجع روزِ انتخاب‌شدهٔ کاربر
   uint   dayType;         // 1=Trend · 2=Normal Variation · 3=Normal · 4=Neutral · 5=Non-trend
   uint   openType;        // 1=Open-Drive · 2=Open-Test-Drive · 3=Open-Reject · 4=Open-Auction
   double hvn[3]; int hvnCount;   // High Volume Nodes
   double lvn[3]; int lvnCount;   // Low Volume Nodes
   double nakedPoc;  bool hasNakedPoc;  datetime nakedPocDay;  // Naked/Virgin POC
   string balanceNote;     // Balance (پذیرش درون ارزش) یا Imbalance (خروج)
};

// ---------- رجیستری‌ها ----------
WyckoffObj g_wyck[];
SDObj      g_sd[];
ProfileResult g_profileDaily;   // پروفایل روز جاری (tick-volume)
datetime   g_profileDayStart = 0;
int        g_brooksEmaHandle = INVALID_HANDLE;
int        g_wyckPhaseCount[6]; // WP_NONE..WP_E شمارندهٔ کلی
string     g_wyckPhaseReason = "";
string     g_brooksNote      = "";   // Always-In + H1/H2 خلاصه
BrooksBarInfo g_brooksInfo;      // فاز ۳۳: آخرین خوانش کندل برای پنل آموزشی (عدد خام)
string     g_rtmNote         = "";   // Compression/Expansion خلاصه
string     g_profileNote     = "";   // POC/VA خلاصه

long NextFamId() { static long fid=9100000000L; return ++fid; }   // فضا مخصوص خانواده‌های جدید

// ---------- فاز ۱۶ · بازنویسی کامل در فاز ۳۳ ----------
// ایراد اثبات‌شدهٔ نسخهٔ قبلی (شاهد: grep در همین فایل): از ۱۳ رویدادی که enum و
// متن آموزشی داشتند فقط ۵ رویداد تولید می‌شد (SC/BC/SPRING/UPTHRUST/TEST)؛
// یعنی AR · ST · SOS · SOW · LPS · LPSY · ABSORPTION · PS · PSY هرگز «push»
// نمی‌شدند و در نتیجه فازهای A، D و E هرگز قابل‌دستیابی نبودند (فقط B و C).
// ایراد دوم: «Spring» صرفاً یک قاعدهٔ هندسی روی کف پنجرهٔ ۶۰ کندلی بود، پس هر
// فتیلهٔ زیر کف پنجره در هر نقطهٔ تاریخچه یک «Spring» می‌ساخت.
// ایراد سوم: وضعیت رنج هیچ‌وقت بازنشانی نمی‌شد؛ رنج و فاز پس از پایان، جاودانه
// باقی می‌ماندند.
//
// قاعده‌های منبع‌دار (بازبینی 2026-09-19):
//  · Rubén Villahermosa — «Wyckoff Phases» (tradingwyckoff.com):
//      Phase A = PS/PSY → SC/BC → AR → ST و «با ST این فاز تمام می‌شود»؛
//      Phase B = آزمون‌های پیوسته و «جذب (Absorption)» در دو انتهای ساختار؛
//      Phase C = Spring/Shakeout یا UTAD و پایانش «با تست همان حرکت»؛
//      Phase D = SOS/JAC · SOW · LPS/BUEC · LPSY؛
//      Phase E = «روند خارج از ساختار» و شروعش منوط است به این‌که «قیمت بیرون
//      بماند و بازگشت فوری رخ ندهد».
//  · Elite Forex Trading — «Wyckoff Accumulation: schematic, phases & events»:
//      SC = «فروش شارپ با حجم بالا» · AR = «رالی بعد از کلایمکس که سقف رنج را
//      تعیین می‌کند» · ST = «بازگشت به کف با حجم سبک‌تر» · SOS = «رالی قوی،
//      غالباً با شکست سقف رنج» · LPS = «کف بالاتر در پولبک پس از SOS».
//  · منبع تصریح می‌کند شیکاوت «لزوماً اکستریم ساختار را نمی‌زند» و در آن حالت
//      «به‌عنوان LPS/LPSY عمل می‌کند» → پس Spring فقط با عبور از کف ساختار
//      معتبر است؛ برگشت بدون عبور، LPS ثبت می‌شود (نه Spring).
//  · منبع می‌گوید کلایمکس می‌تواند بدون حجم کلایمکتیک هم باشد (Selling
//      Exhaustion) → حجم در پیش‌فرض اجباری نیست ولی نسبتش در پنل گزارش می‌شود.
void PushWyck(ENUM_WYCK_EVENT evt, datetime t, double price)
{
   int n=ArraySize(g_wyck);
   ArrayResize(g_wyck,n+1);
   g_wyck[n].evt=evt; g_wyck[n].time=t; g_wyck[n].price=price;
   g_wyck[n].id=NextFamId();
   g_wyck[n].phase=(n>0)? g_wyck[n-1].phase : WP_NONE;
   g_wyck[n].phaseReason=(n>0)? g_wyck[n-1].phaseReason : "";
}

// میانگین tick-volume روی کندل‌های قدیمی‌تر از کندل جاری (مرجع «حجم سبک/سنگین»)
double WyckAvgVol(const long &v[], int from, int count)
{
   int total=ArraySize(v);
   double s=0.0; int n=0;
   for(int k=0;k<count;k++)
   {
      int i=from+k;
      if(i<0 || i>=total) break;
      s+=(double)v[i]; n++;
   }
   return (n>0)? s/(double)n : 0.0;
}

// پیوت تأییدشده (ایندکس سری: ۰ = جدیدترین). برای یکتایی، سمت قدیمی سخت‌گیرتر است.
bool WyckPivotHigh(const double &h[], int j, int left, int right, int total)
{
   if(j-left<0 || j+right>=total) return false;
   for(int k=1;k<=left;k++)  if(h[j+k]>=h[j]) return false;
   for(int k=1;k<=right;k++) if(h[j-k]>h[j])  return false;
   return true;
}

bool WyckPivotLow(const double &l[], int j, int left, int right, int total)
{
   if(j-left<0 || j+right>=total) return false;
   for(int k=1;k<=left;k++)  if(l[j+k]<=l[j]) return false;
   for(int k=1;k<=right;k++) if(l[j-k]<l[j])  return false;
   return true;
}

void WyckResetRange(string why)
{
   g_wyckRange.hasClimax=false; g_wyckRange.hasPS=false; g_wyckRange.hasAR=false;
   g_wyckRange.hasST=false;     g_wyckRange.hasShakeout=false; g_wyckRange.hasSOS=false;
   g_wyckRange.hasLPS=false;    g_wyckRange.barsInRange=0; g_wyckRange.barsBeyond=0;
   g_wyckRange.lastLPSTime=0;   g_wyckRange.sosTime=0; g_wyckRange.lastLPSPrice=0.0;
   g_wyckRange.climaxTime=0;    g_wyckRange.resetReason=why;
}

void UpdateWyckoff(const double &o[], const double &h[], const double &l[], const double &c[], int shift, double atr)
{
   if(!InpEnableWyckoff || atr<=0.0) return;
   int lb=MathMax(12, InpWyckoffLookbackBars);
   int extBars=MathMax(lb, InpWyckoffClimaxExtremeBars);
   int need=extBars+MathMax(InpWyckoffAR_MaxBars, InpSwingLeft+InpSwingRight+8)+8;
   if(shift+need>=ArraySize(h)) return;

   // حجم: یک CopyTickVolume برای هر کندل بسته (سیاست فاز ۲۴: بدون حلقهٔ iVolume)
   long v[]; ArraySetAsSeries(v,true);
   int volCopied=CopyTickVolume(_Symbol,PERIOD_CURRENT,0,need,v);
   if(volCopied<=0) return;
   // فاز ۴۰ — ایراد بحرانی «پریدن آبجکت‌ها با تعویض تایم‌فریم»:
   // CopyTickVolume فقط به تعداد کندل‌های *آمادهٔ* پر می‌کند. بی‌درنگ پس از
   // تعویض تایم‌فریم، تاریخچهٔ سری جدید ناقص است، پس طول v از need کمتر است؛
   // ولی v[shift] با shift بازسازی (تا InpHistoryScanBars) خوانده می‌شد ⇒
   // array out of range ⇒ کل پاس OnCalculate می‌مرد ⇒ نه بازسازی، نه رسم.
   // چون OnDeinit پیش‌تر لایهٔ گرافیکی را پاک کرده، نتیجه دقیقاً همان چیزی بود
   // که کاربر دید: با هر عوض‌کردن تایم‌فریم، چارت خالی می‌شد.
   if(shift>=volCopied) return;
   double avgVol=WyckAvgVol(v,shift+1,MathMax(5,InpWyckoffVolLookback));
   if(avgVol<=0.0) avgVol=1.0;

   double curHigh=h[shift], curLow=l[shift], curClose=c[shift], curOpen=o[shift];
   double barRange=curHigh-curLow;
   if(barRange<=0.0) return;
   datetime curT=BarTime(shift);
   double lowerTail=MathMin(curClose,curOpen)-curLow;
   double upperTail=curHigh-MathMax(curClose,curOpen);
   double volRatio=(double)v[shift]/avgVol;
   bool   volClimax=(v[shift]>=avgVol*InpWyckoffClimaxVolMult);
   bool   wideBar  =(barRange>=atr*InpWyckoffClimaxRangeATR);

   double extHigh=h[ArrayMaximum(h,extBars,shift+1)];
   double extLow =l[ArrayMinimum(l,extBars,shift+1)];

   g_wyckRange.barsInRange++;
   if(g_wyckRange.barsInRange>InpWyckoffRangeMaxBars)
      WyckResetRange("عمر ساختار از سقف گذشت ("+IntegerToString(InpWyckoffRangeMaxBars)+" کندل)");

   // ---------- ۱) فاز A — PS/PSY: «اولین خرید/فروش معناداری که روند پیشین را کند می‌کند» ----------
   if(!g_wyckRange.hasClimax && !g_wyckRange.hasPS)
   {
      if(curLow<=extLow && lowerTail>=barRange*0.5 && curClose>curLow+barRange*0.5 && volRatio>=1.2)
      {
         PushWyck(WE_PS, curT, curLow);
         g_wyckRange.hasPS=true;
      }
      else if(curHigh>=extHigh && upperTail>=barRange*0.5 && curClose<curHigh-barRange*0.5 && volRatio>=1.2)
      {
         PushWyck(WE_PSY, curT, curHigh);
         g_wyckRange.hasPS=true;
      }
   }

   // ---------- ۲) فاز A — SC/BC: «اوج هیجان» ------------------------------
   // SC: کندل فراخ‌دامنهٔ نزولی که کف تازه می‌سازد و در نیمهٔ بالای خود می‌بندد.
   bool scBar=(wideBar && curLow<=extLow && curClose>curLow+barRange*0.5 && curClose<curOpen);
   bool bcBar=(wideBar && curHigh>=extHigh && curClose<curHigh-barRange*0.5 && curClose>curOpen);
   if(InpWyckoffClimaxRequireVolume) { scBar=(scBar && volClimax); bcBar=(bcBar && volClimax); }

   if(scBar)
   {
      // چرخهٔ تازه فقط اگر اکستریم چرخهٔ قبلی معنادار شکسته شود (وگرنه SC تکراری)
      bool fresh=!g_wyckRange.hasClimax || (curLow<g_wyckRange.climaxPrice-atr*InpWyckoffClimaxResetATR);
      if(fresh)
      {
         WyckResetRange("SC تازه — چرخهٔ تازه");
         g_wyckRange.hasClimax=true; g_wyckRange.isAccum=true;
         g_wyckRange.floor=curLow;   g_wyckRange.ceiling=0.0;
         g_wyckRange.climaxPrice=curLow; g_wyckRange.climaxVol=(double)v[shift];
         g_wyckRange.climaxTime=curT; g_wyckRange.climaxVolRatio=volRatio;
         g_wyckRange.barsInRange=0;
         PushWyck(WE_SC, curT, curLow);
         // فاز ۳۶: Effort vs Result روی خود کلایمکس (منبع: Wyckoff — «Volume
         // Analysis (Effort vs Result)»): تلاش زیاد (حجم سنگین) + نتیجهٔ کم
         // (بسته در میانهٔ کندل، نه اکستریم مخالف) = جذب — برگشت زودتر از فاز D
         if(volRatio>=InpWyckoffClimaxVolMult && curClose>curLow+barRange*0.5)
            PushWyck(WE_ABSORPTION, curT, curClose);
      }
   }
   else if(bcBar)
   {
      bool fresh=!g_wyckRange.hasClimax || (curHigh>g_wyckRange.climaxPrice+atr*InpWyckoffClimaxResetATR);
      if(fresh)
      {
         WyckResetRange("BC تازه — چرخهٔ تازه");
         g_wyckRange.hasClimax=true; g_wyckRange.isAccum=false;
         g_wyckRange.ceiling=curHigh; g_wyckRange.floor=0.0;
         g_wyckRange.climaxPrice=curHigh; g_wyckRange.climaxVol=(double)v[shift];
         g_wyckRange.climaxTime=curT; g_wyckRange.climaxVolRatio=volRatio;
         g_wyckRange.barsInRange=0;
         PushWyck(WE_BC, curT, curHigh);
         // فاز ۳۶: آینهٔ نزولی — تلاش زیاد + نتیجهٔ کم = Absorption
         if(volRatio>=InpWyckoffClimaxVolMult && curClose<curHigh-barRange*0.5)
            PushWyck(WE_ABSORPTION, curT, curClose);
      }
   }

   // ---------- ۳) فاز A — AR: «رالی بعد از کلایمکس که مرز ساختار را تعیین می‌کند» ----------
   // فقط روی پیوت تأییدشده (کندل بسته) و با اندازهٔ چشمگیر — منبع.
   if(g_wyckRange.hasClimax && !g_wyckRange.hasAR)
   {
      int total=ArraySize(h);
      int jmax=MathMin(shift+InpSwingRight+InpWyckoffAR_MaxBars, total-InpSwingRight-1);
      for(int j=shift+InpSwingRight; j<=jmax; j++)
      {
         if(j<=0) continue;
         if(g_wyckRange.climaxTime>0 && BarTime(j)<=g_wyckRange.climaxTime) continue;
         if(g_wyckRange.isAccum)
         {
            if(!WyckPivotHigh(h,j,InpSwingLeft,InpSwingRight,total)) continue;
            if((h[j]-g_wyckRange.climaxPrice)<atr*InpWyckoffAR_ATR) continue;
            g_wyckRange.ceiling=h[j]; g_wyckRange.hasAR=true;
            PushWyck(WE_AR, BarTime(j), h[j]);
            break;
         }
         else
         {
            if(!WyckPivotLow(l,j,InpSwingLeft,InpSwingRight,total)) continue;
            if((g_wyckRange.climaxPrice-l[j])<atr*InpWyckoffAR_ATR) continue;
            g_wyckRange.floor=l[j]; g_wyckRange.hasAR=true;
            PushWyck(WE_AR, BarTime(j), l[j]);
            break;
         }
      }
   }

   // ---------- ۴) فاز A — ST: «بازگشت به اکستریم با حجم سبک‌تر» → پایان فاز A ----------
   if(g_wyckRange.hasAR && !g_wyckRange.hasST)
   {
      bool near=(g_wyckRange.isAccum)
                ? (curLow<=g_wyckRange.climaxPrice+atr*InpWyckoffST_ATR)
                : (curHigh>=g_wyckRange.climaxPrice-atr*InpWyckoffST_ATR);
      bool held=(g_wyckRange.isAccum)
                ? (curLow>=g_wyckRange.climaxPrice-atr*InpWyckoffST_UndercutATR)
                : (curHigh<=g_wyckRange.climaxPrice+atr*InpWyckoffST_UndercutATR);
      bool lighter=(g_wyckRange.climaxVol<=0.0) || ((double)v[shift]<g_wyckRange.climaxVol);
      if(near && held && (!InpWyckoffSTRequireLighterVolume || lighter))
      {
         g_wyckRange.hasST=true;   // پایان فاز A → شروع فاز B
         PushWyck(WE_ST, curT, (g_wyckRange.isAccum? curLow : curHigh));
      }
   }

   bool lastWasTest=false, lastWasAbsorb=false;
   int wn=ArraySize(g_wyck);
   if(wn>0)
   {
      lastWasTest  =(g_wyck[wn-1].evt==WE_TEST);
      lastWasAbsorb=(g_wyck[wn-1].evt==WE_ABSORPTION);
   }

   // ---------- ۵) فاز B — Absorption: «جذب» = تلاش بالا با نتیجهٔ کم ----------
   if(g_wyckRange.hasST && !lastWasAbsorb && volRatio>=InpWyckoffAbsorbVolMult &&
      barRange<=atr*InpWyckoffAbsorbRangeATR)
      PushWyck(WE_ABSORPTION, curT, curClose);

   // ---------- ۶) فاز C — Spring / UTAD: فقط در بافت ساختار تأییدشده ----------
   if(g_wyckRange.hasST)
   {
      if(g_wyckRange.isAccum && g_wyckRange.floor>0.0 &&
         curLow<g_wyckRange.floor-atr*InpWyckoffSpringATR && curClose>g_wyckRange.floor)
      {
         if(!g_wyckRange.hasShakeout) g_wyckRange.hasShakeout=true;
         PushWyck(WE_SPRING, curT, curLow);
      }
      if(!g_wyckRange.isAccum && g_wyckRange.ceiling>0.0 &&
         curHigh>g_wyckRange.ceiling+atr*InpWyckoffSpringATR && curClose<g_wyckRange.ceiling)
      {
         if(!g_wyckRange.hasShakeout) g_wyckRange.hasShakeout=true;
         PushWyck(WE_UPTHRUST, curT, curHigh);
      }
      // UA/UT فاز B: نفوذ به مرز و بسته‌شدن درون ساختار (بدون عبور کامل)
      else if(g_wyckRange.ceiling>0.0 && g_wyckRange.isAccum &&
              curHigh>g_wyckRange.ceiling && curClose<g_wyckRange.ceiling && !g_wyckRange.hasSOS)
         PushWyck(WE_UPTHRUST, curT, curHigh);
      // TEST فاز B: بازگشت کم‌دامنه به مرز پس از شیکاوت
      else if(g_wyckRange.hasShakeout && !lastWasTest &&
              barRange<atr*0.8 && curLow>g_wyckRange.floor && curHigh<g_wyckRange.ceiling)
         PushWyck(WE_TEST, curT, curClose);
   }

   // ---------- ۷) فاز D — SOS/SOW: «رالی/افت قوی با عبور از مرز ساختار» ----------
   bool strongBar=(barRange>=atr*InpWyckoffSOSRangeATR) || volClimax;
   if(g_wyckRange.hasST && !g_wyckRange.hasSOS)
   {
      if(g_wyckRange.isAccum && g_wyckRange.ceiling>0.0 && curClose>g_wyckRange.ceiling && strongBar)
      {
         g_wyckRange.hasSOS=true; g_wyckRange.sosTime=curT;
         g_wyckRange.lastLPSPrice=g_wyckRange.floor;
         PushWyck(WE_SOS, curT, curClose);
      }
      else if(!g_wyckRange.isAccum && g_wyckRange.floor>0.0 && curClose<g_wyckRange.floor && strongBar)
      {
         g_wyckRange.hasSOS=true; g_wyckRange.sosTime=curT;
         g_wyckRange.lastLPSPrice=g_wyckRange.ceiling;
         PushWyck(WE_SOW, curT, curClose);
      }
   }

   // ---------- ۸) فاز D/E — LPS/LPSY: «کف بالاتر / سقف پایین‌تر پس از SOS» ----------
   if(g_wyckRange.hasSOS)
   {
      int total2=ArraySize(h);
      int last=MathMin(shift+InpSwingRight+InpSwingRight+2, total2-InpSwingRight-1);
      for(int j=shift+InpSwingRight; j<=last; j++)
      {
         if(j<=0) continue;
         datetime jt=BarTime(j);
         if(g_wyckRange.sosTime>0 && jt<=g_wyckRange.sosTime) continue;
         if(jt<=g_wyckRange.lastLPSTime) continue;
         if(g_wyckRange.isAccum)
         {
            if(!WyckPivotLow(l,j,InpSwingLeft,InpSwingRight,total2)) continue;
            if(l[j]<=g_wyckRange.lastLPSPrice) continue;              // باید کف بالاتر باشد
            if(g_wyckRange.floor>0.0 && l[j]<=g_wyckRange.floor) continue;
            g_wyckRange.lastLPSPrice=l[j]; g_wyckRange.hasLPS=true; g_wyckRange.lastLPSTime=jt;
            PushWyck(WE_LPS, jt, l[j]);
            break;
         }
         else
         {
            if(!WyckPivotHigh(h,j,InpSwingLeft,InpSwingRight,total2)) continue;
            if(h[j]>=g_wyckRange.lastLPSPrice) continue;              // باید سقف پایین‌تر باشد
            if(g_wyckRange.ceiling>0.0 && h[j]>=g_wyckRange.ceiling) continue;
            g_wyckRange.lastLPSPrice=h[j]; g_wyckRange.hasLPS=true; g_wyckRange.lastLPSTime=jt;
            PushWyck(WE_LPSY, jt, h[j]);
            break;
         }
      }
   }

   // ---------- ۹) فاز E — «روند خارج از ساختار»: قیمت بیرون بماند ----------
   if(g_wyckRange.hasSOS)
   {
      bool beyond=(g_wyckRange.isAccum)? (g_wyckRange.ceiling>0.0 && curClose>g_wyckRange.ceiling)
                                       : (g_wyckRange.floor>0.0   && curClose<g_wyckRange.floor);
      if(beyond) g_wyckRange.barsBeyond++;
      else       g_wyckRange.barsBeyond=0;      // «بازگشت فوری» → فاز E هنوز تأیید نشده
   }
}

// تعیین فاز A–E از وضعیت ساختار (state machine، منبع‌دار)
void UpdateWyckoffPhase()
{
   int n=ArraySize(g_wyck);
   ENUM_WYCK_PHASE ph=WP_NONE;
   // فاز ۴۲: این رشته‌ها در پنل آموزشی وسط جملهٔ فارسی می‌آیند، پس باید
   // کاملاً فارسی باشند؛ واژه‌های لاتین معادل فارسی گرفتند.
   string reason="ساختاری شناسایی نشده (اوج هیجان در پنجره نیست)";
   if(g_wyckRange.hasClimax)
   {
      if(!g_wyckRange.hasAR)
      { ph=WP_A; reason="فاز الف — اوج هیجان ثبت شد؛ منتظر رالی خودکار که مرز ساختار را تعیین کند"; }
      else if(!g_wyckRange.hasST)
      { ph=WP_A; reason="فاز الف — رالی خودکار مرز ساختار را ساخت؛ منتظر آزمون دوم با حجم سبک‌تر برای پایان این فاز"; }
      else if(!g_wyckRange.hasSOS)
      {
         if(g_wyckRange.hasShakeout)
         { ph=WP_C; reason="فاز ج — شیک‌اوت انجام شد؛ منتظر نشانهٔ قدرت یا ضعف برای ورود به فاز د"; }
         else
         { ph=WP_B; reason=StringFormat("فاز ب — ساخت علت: ساختار %s بین %.5f و %.5f با آزمون‌های پیوسته",
                                       g_wyckRange.isAccum?"انباشت":"توزیع",
                                       g_wyckRange.floor, g_wyckRange.ceiling); }
      }
      else
      {
         if(g_wyckRange.barsBeyond>=InpWyckoffPhaseE_Bars)
         { ph=WP_E; reason=StringFormat("فاز ه — روند بیرون ساختار (%d کندل پیوسته بیرون؛ حالت %s)",
                                       g_wyckRange.barsBeyond, g_wyckRange.isAccum?"صعود":"نزول"); }
         else
         { ph=WP_D; reason=StringFormat("فاز د — نشانهٔ %s صادر شد؛ روند درون ساختار، آخرین نقطهٔ حمایت یا عرضه (%s)",
                                       g_wyckRange.isAccum?"قدرت":"ضعف", g_wyckRange.hasLPS?"دارد":"ندارد"); }
      }
   }
   if(n>0){ g_wyck[n-1].phase=ph; g_wyck[n-1].phaseReason=reason; }
   g_wyckPhaseReason=reason;
   ArrayInitialize(g_wyckPhaseCount,0);
}

// ---------- فاز ۱۷: Supply & Demand کلاسیک ----------
// الگوهای RBR/DBD/RBD/DBR: «پایه» (base) ۱ تا N کندل کم‌دامنه، سپس حرکت خروج
// شارپ. Fresh=بدون برخورد، Tested=برخورد خورده، Flipped=بسته از سمت مخالف.
// فاز ۳۳ — بازبینی S&D با تعریف استاندارد چهار الگو:
//   RBR = Rally-Base-Rally  (ورود صعودی، پایه، خروج صعودی) → Demand ادامه‌دهنده
//   RBD = Rally-Base-Drop   (ورود صعودی، پایه، خروج نزولی)  → Supply (برگشتی، سقف)
//   DBD = Drop-Base-Drop    (ورود نزولی، پایه، خروج نزولی)  → Supply ادامه‌دهنده
//   DBR = Drop-Base-Rally   (ورود نزولی، پایه، خروج صعودی)  → Demand (برگشتی، کف)
// ایراد اثبات‌شدهٔ نسخهٔ قبلی: تابع فقط «جای پایه» و «جهت خروج» را می‌دید و جهت
// «حرکت ورودی به پایه» را نادیده می‌گرفت → RBR و DBR از هم قابل‌تفکیک نبودند
// (هر دو «پایه در کف + خروج بالا»)؛ یعنی ادامه‌دهنده و برگشتی یکی می‌شدند.
ENUM_SD_KIND SDKindFor(bool preUp, bool exitUp)
{
   if(preUp && exitUp)  return SDK_RBR;
   if(preUp && !exitUp) return SDK_RBD;
   if(!preUp && exitUp) return SDK_DBR;
   return SDK_DBD;
}

// منبع واحد حقیقت برای نقش Supply/Demand — ایراد اثبات‌شدهٔ نسخهٔ قبلی: در سه جای
// مختلف نقش‌دهی تکرار شده بود و دو جا **برعکس** بود (DBR به‌عنوان Supply و RBD
// به‌عنوان Demand). نتیجه: RBD که یک ناحیهٔ Supply برگشتی است، رنگ صعودی می‌گرفت
// و با بستهٔ زیر کف خودش Flip می‌شد؛ و DBR دقیقاً برعکس. حالا فقط این تابع مرجع است.
bool SDIsSupplyKind(ENUM_SD_KIND k)
{
   return (k==SDK_SUPPLY || k==SDK_RBD || k==SDK_DBD);
}

string SDKindToStr(ENUM_SD_KIND k)
{
   switch(k)
   {
      case SDK_RBR:    return "RBR";
      case SDK_DBD:    return "DBD";
      case SDK_RBD:    return "RBD";
      case SDK_DBR:    return "DBR";
      case SDK_SUPPLY: return "SUPPLY";
      default:         return "DEMAND";
   }
}

void DetectSupplyDemand(const double &o[], const double &h[], const double &l[], const double &c[], int shift, double atr)
{
   if(!InpEnableSupplyDemand || atr<=0.0) return;
   int total=ArraySize(h);
   for(int baseBars=1; baseBars<=MathMax(1,InpSD_BaseMaxBars); baseBars++)
   {
      int baseStart=shift+1;             // قدیمی‌ترین کندل پایه
      int baseEnd  =shift+baseBars;      // جدیدترین کندل پایه
      if(baseEnd+1>=total) break;        // یک کندل قبل از پایه لازم است (جهت ورود)
      double bHigh=h[ArrayMaximum(h,baseBars,baseStart)];
      double bLow =l[ArrayMinimum(l,baseBars,baseStart)];
      // (فاز ۳۶) اطمینان: کندل‌های سوم الگوی FVG باید در دسترس باشند
      if(baseEnd+2>=total) break;
      double exitMove=MathAbs(c[shift]-(bHigh+bLow)/2.0);
      if(exitMove<atr*InpSD_StrengthATR) continue;   // خروج شارپ نیست
      bool exitUp=(c[shift]>bHigh);
      bool exitDn=(c[shift]<bLow);
      if(!exitUp && !exitDn) continue;

      // پایه باید واقعاً کم‌دامنه باشد (قبلاً عدد ۱.۵ سخت‌کد بود — فاز ۳۳ ورودی شد)
      if((bHigh-bLow)>atr*InpSD_BaseMaxRangeATR) continue;

      // جهت «حرکت ورودی به پایه»: لگ منتهی به پایه صعودی بوده یا نزولی؟
      // این تنها راه جداکردن الگوی ادامه‌دهنده از برگشتی است (RBR از DBR و RBD از DBD)
      // جهت لگ منتهی به پایه: بستهٔ کندل پیش از پایه در برابر بستهٔ کندل قبلش
      bool preUp=(c[baseEnd+1]>c[baseEnd+2]);

      SDObj z;
      z.id=NextFamId();
      z.kind=SDKindFor(preUp, exitUp);
      z.state=SDS_FRESH;
      z.time=BarTime(shift);
      z.top=bHigh; z.bottom=bLow; z.tests=0; z.exitMove=exitMove;
      z.tf=(ENUM_TIMEFRAMES)Period();
      z.roleSupply=SDIsSupplyKind(z.kind);
      z.flipped=false; z.flipTime=0; z.flipLevel=0.0;
      // فاز ۳۶ — Strength of Zone: امتیاز ترکیبی (۱ تا ۵) از سه معیارِ مستند:
      //  ۱) شارپ بودن خروج (exitMove/ATR)
      //  ۲) باریک بودن پایه (پایهٔ تنگ = سفارش نهادی متراکم)
      //  ۳) تعداد کندل پایه (۳–۵ کندل استاندارد منابع؛ نه ۱ و نه بیشتر از ۶)
      // و ضریب ۲ اگر خروج با FVG هم‌زمان باشد (منبع: trendspider — «large
      // candles, break of structure, volume, imbalance/FVG» معیارهای قدرت زون)
      {
         int strength=1;
         if(exitMove>=atr*InpSD_StrengthATR*1.5) strength++;
         if((bHigh-bLow)<=atr*InpSD_BaseMaxRangeATR*0.5) strength++;
         if(baseBars>=3 && baseBars<=5) strength++;
         // FVG هم‌زمان با خروج: گپ سه‌کندلی که همان کندل جاری سومش است
         double gapHi=(c[shift+2]<o[shift+2])? h[shift] : h[shift];   // placeholder برای خوانایی
         gapHi=h[shift];
         double gapLo=(o[shift+2]>c[shift+2])? h[shift+2] : l[shift+2];
         if(exitUp && l[shift]>MathMax(o[shift+2],c[shift+2])) strength++;      // گپ صعودی
         else if(!exitUp && h[shift]<MathMin(o[shift+2],c[shift+2])) strength++;// گپ نزولی
         if(strength>5) strength=5;
         z.strength=strength;
         z.strengthText=StringFormat("ATR | خروج %.2f برابر | پایه %.2f برابر | %d کندل پایه | %s",
                        exitMove/atr, (bHigh-bLow)/atr, baseBars,
                        (strength>=4?"قوی":(strength==3?"متوسط":"ضعیف")));
      }
      int n=ArraySize(g_sd);
      if(n>=InpSD_MaxZones)
      {
         ArrayRemove(g_sd,0,1); n--;                   // FIFO — قدیمی‌ترین حذف
      }
      ArrayResize(g_sd,n+1); g_sd[n]=z;
      break;   // برای هر کندل فقط یک الگو ثبت (قدیمی‌ترین پایه معتبر)
   }
}

// چرخهٔ عمر ناحیه با اجزای صریح:
//   FRESH   → هیچ برخوردی نشده
//   TESTED  → برخورد خورده (شکست ریز / واکنش) ولی نقش عوض نشده
//   FLIPPED → بستهٔ قاطع از سمت مقابل → نقش Supply↔Demand عوض شده (Flip Zone)
//             و از این لحظه ناحیه با **نقش جدید** رهگیری می‌شود (قبلاً رها می‌شد)
//   BROKEN  → پس از Flip، بسته از سمت مقابل جدید → ناحیه باطل (با
//             InpHideInvalidatedObjects از چارت هم برداشته می‌شود)
void UpdateSupplyDemandLifecycle(double curHigh, double curLow, double curClose, datetime curT)
{
   for(int i=0;i<ArraySize(g_sd);i++)
   {
      if(g_sd[i].state==SDS_BROKEN) continue;
      bool roleSupply=g_sd[i].roleSupply;
      bool inside=(curHigh>=g_sd[i].bottom && curLow<=g_sd[i].top);
      if(inside)
      {
         g_sd[i].tests++;
         if(g_sd[i].state==SDS_FRESH) g_sd[i].state=SDS_TESTED;
      }

      // Flip: بستهٔ قاطع از سمت مقابل نقش
      bool flipsNow=roleSupply? (curClose>g_sd[i].top) : (curClose<g_sd[i].bottom);
      if(flipsNow && !g_sd[i].flipped)
      {
         g_sd[i].flipped=true;
         g_sd[i].roleSupply=!roleSupply;      // نقش عوض شد → از این لحظه رهگیری مخالف
         g_sd[i].flipTime=curT;
         g_sd[i].flipLevel=curClose;
         g_sd[i].state=SDS_FLIPPED;
         continue;
      }

      // ابطال پس از Flip: بسته از سمت مقابل نقشِ جدید
      if(g_sd[i].flipped)
      {
         bool breaksNow=g_sd[i].roleSupply? (curClose>g_sd[i].top) : (curClose<g_sd[i].bottom);
         if(breaksNow) g_sd[i].state=SDS_BROKEN;
      }
   }
}

// ---------- فاز ۱۸ · بازبینی دونه‌به‌دونهٔ فاز ۳۳ ----------
// ایرادهای اثبات‌شدهٔ نسخهٔ قبلی (شاهد در همین فایل):
//  ۱) H1/H2 **برعکس** تعریف بود: کد «دو کف نزولی متوالی» را H2 می‌گرفت — یعنی
//     دقیقاً وسط یک پولبکِ در جریان، نه پایان آن. منبع: «H1 = اولین کندلی که
//     سقف کندل قبلی‌اش را رد می‌کند پس از شروع پولبک در روند صعودی؛ اگر آن تلاش
//     شکست بخورد، تلاش بعدی H2 است» (brookstradingcourse — «H1 H2 L1 L2 etc.»؛
//     nexusfi — two-legged pullback: «An H1 is a bar whose high exceeds the prior
//     bar's high»). پس H2 یک «کف بالاتر» نیست؛ «شمارش تلاش‌ها» است.
//  ۲) Always-In یک «وضعیت» است، نه سه کندل هم‌رنگ؛ و شرط نزولی‌اش در تابع نبود
//     (در محل نمایش با کد تکراری بازنویسی می‌شد).
//  ۳) ورودی InpBrooks_EMA20_Period و وهندل g_brooksEmaHandle **مرده** بودند: نه
//     هندل ساخته می‌شد و نه خوانده؛ درحالی‌که «20 EMA به‌عنوان مرجع» در لیست
//     خواسته‌های کاربر است. اکنون در OnInit ساخته و به‌عنوان بافت Always-In و
//     تشخیص «بازگشت روند» استفاده می‌شود.
//  ۴) Signal bar بدون بافت بود: هر چکش در هر نقطهٔ چارت سیگنال می‌شد. طبق تعریف،
//     Signal bar در **انتهای یک لگ مخالف** شکل می‌گیرد و در جهت موردنظر می‌بندد.
//  ۵) Follow-through نسبت به کندل قبلی سنجیده می‌شد، نه نسبت به Signal bar.
//  ۶) L1/L2 (آینهٔ نزولی) اصلاً وجود نداشت.
BrooksBarInfo AnalyzeBrooksBar(const double &o[], const double &h[], const double &l[], const double &c[], int shift, double atr)
{
   BrooksBarInfo bi;
   bi.isTrendBar=false; bi.isDoji=false; bi.isSignalBar=false; bi.isEntryBar=false;
   bi.followThrough=false; bi.alwaysInLong=false; bi.alwaysInShort=false; bi.alwaysIn=0;
   bi.bullSignal=false; bi.bearSignal=false;
   bi.h1=false; bi.h2=false; bi.h3=false; bi.h4=false;
   bi.l1=false; bi.l2=false; bi.l3=false; bi.l4=false;
   bi.hAttempts=0; bi.lAttempts=0; bi.ema20=0.0; bi.failedBreakout=false;
   // فاز ۳۶: پیش‌فرضهای خانوادهٔ Range/MeasuredMove/Channel
   bi.inTradingRange=false; bi.trHigh=0; bi.trLow=0; bi.trMid=0; bi.trBars=0;
   bi.trBreakUp=false; bi.trBreakDn=false; bi.trFailedBreakUp=false; bi.trFailedBreakDn=false;
   bi.mmValid=false; bi.mmA=0; bi.mmB=0; bi.mmC=0; bi.mmD=0;
   bi.mmTimeA=0; bi.mmTimeB=0; bi.mmTimeC=0;
   bi.chSlope=0;
   int total=ArraySize(h);
   if(shift+3>=total || atr<=0.0) return bi;
   double rng=h[shift]-l[shift];
   if(rng<=0.0) return bi;
   double body=MathAbs(c[shift]-o[shift]);
   double upperTail=h[shift]-MathMax(o[shift],c[shift]);
   double lowerTail=MathMin(o[shift],c[shift])-l[shift];
   double maxTail=MathMax(upperTail,lowerTail);

   bi.isTrendBar=(body/rng>=InpBrooks_TrendBarRatio);
   bi.isDoji=(body/rng<=InpBrooks_DojiBodyRatio) || (maxTail<=rng*InpBrooks_TailMaxRatio && body/rng<0.4);

   // --- ۲۰ EMA (مرجع «Al Brooks»): مقدار در کندل بستهٔ جاری + شیب چند کندلی ---
   double ema[];
   int ai=0;
   if(g_brooksEmaHandle!=INVALID_HANDLE && CopyBuffer(g_brooksEmaHandle,0,shift,InpBrooks_AI_EMASlopeBars,ema)>0)
   {
      bi.ema20=ema[0];
      int lastE=ArraySize(ema)-1;
      bool up=(ema[0]>ema[lastE]), dn=(ema[0]<ema[lastE]);
      // Always-In = وضعیت روند نسبت به ۲۰ EMA (پروکسی قابل‌توضیح؛ در پنل صریح گفته می‌شود)
      if(c[shift]>bi.ema20 && up) ai=1;
      else if(c[shift]<bi.ema20 && dn) ai=-1;
   }
   bi.alwaysIn=ai; bi.alwaysInLong=(ai==1); bi.alwaysInShort=(ai==-1);

   // --- Signal bar با بافت: انتهای لگ مخالف + بسته‌شدن نزدیک اکستریم در جهت ---
   bool prevBull=(c[shift+1]>o[shift+1]);
   bool bullBody=(c[shift]>o[shift]);
   bool closesNearHigh=((h[shift]-c[shift])<=rng*0.25);
   bool closesNearLow =((c[shift]-l[shift])<=rng*0.25);
   bi.bullSignal=(bullBody && closesNearHigh && c[shift]>c[shift+1] && !prevBull);
   bi.bearSignal=(!bullBody && closesNearLow && c[shift]<c[shift+1] && prevBull);
   bi.isSignalBar=(bi.bullSignal||bi.bearSignal);

   // --- Follow-through نسبت به Signal bar قبلی (نه نسبت به هر کندل) ---
   double prevRng=h[shift+1]-l[shift+1];
   bool prevBullSig=(prevRng>0.0 && prevBull && ((h[shift+1]-c[shift+1])<=prevRng*0.25) && c[shift+1]>c[shift+2]);
   bool prevBearSig=(prevRng>0.0 && !prevBull && ((c[shift+1]-l[shift+1])<=prevRng*0.25) && c[shift+1]<c[shift+2]);
   bi.isEntryBar=(bi.isTrendBar && ((bullBody && prevBullSig) || (!bullBody && prevBearSig)));
   bi.followThrough=(bi.isTrendBar && bi.isEntryBar);

   // --- شمارش H1..H4 / L1..L4: هر بار «رد کردن» سقف/کف کندل قبلی یک تلاش است ---
   // منبع (nexusfi): «An H1 is a bar whose high exceeds the prior bar's high» و
   // H2 = «تلاش دوم» پس از شکست تلاش اول؛ H3/H4 غالباً گوه (wedge) است.
   int win=MathMax(3, InpBrooks_PullbackWindow);
   if(shift+win+1<total)
   {
      double refHigh=h[ArrayMaximum(h,win,shift)];   // اکستریم پنجره (شامل جاری)
      double refLow =l[ArrayMinimum(l,win,shift)];
      int hAtt=0, lAtt=0;
      int oldest=shift+win;
      for(int i=oldest; i>=shift+1; i--)             // قدیم → جدید
      {
         if(i+1>=total) continue;
         if(h[i]>h[i+1]) hAtt++;                     // تلاش صعودی
         if(h[i]>=refHigh) hAtt=0;                   // روند صعودی غالب شد → شمارش از نو
         if(l[i]<l[i+1]) lAtt++;                     // تلاش نزولی
         if(l[i]<=refLow)  lAtt=0;                   // روند نزولی غالب شد → شمارش از نو
      }
      bi.hAttempts=hAtt; bi.lAttempts=lAtt;
      if(ai>=0) { bi.h1=(hAtt==1); bi.h2=(hAtt==2); bi.h3=(hAtt==3); bi.h4=(hAtt>=4); }
      if(ai<=0) { bi.l1=(lAtt==1); bi.l2=(lAtt==2); bi.l3=(lAtt==3); bi.l4=(lAtt>=4); }
   }

   // --- Failed breakout: شکست سقف/کف پنجرهٔ ۲۰ کندلی ولی بسته درون آن ---
   int brk=MathMin(20, total-shift-1);
   if(brk>5)
   {
      double hh=h[ArrayMaximum(h,brk,shift+1)];
      double ll=l[ArrayMinimum(l,brk,shift+1)];
      bi.failedBreakout=(cur(h,shift)>hh && c[shift]<hh) || (cur(l,shift)<ll && c[shift]>ll);
   }

   // ================= فاز ۳۶: Brooks — Trading Range دوطرفه ==================
   // منبع (Brooks, Trading Price Action Trading Ranges؛ brookstradingcourse glossary):
   // رنج = بازار دوطرفه؛ bull case و bear case هر دو زنده‌اند؛ وسط رنج
   // «مغناطیس» است و شکست اغلب ناموفق. تشخیص عملیاتی: در پنجرهٔ ۲۰ کندلی،
   // هم بسته‌های صعودی و هم نزولی حاضرند (هیچ‌کدام < ۳۵٪)، دامنهٔ رنج > 2×ATR
   // نباشد (وگرنه روند است) و قیمت به هر دو مرز حداقل یک بار نزدیک شده باشد.
   int trWin=MathMin(20, total-shift-1);
   if(trWin>=10)
   {
      double hh=h[ArrayMaximum(h,trWin,shift)];
      double ll=l[ArrayMinimum(l,trWin,shift)];
      int upBars=0, dnBars=0;
      for(int i=shift; i<shift+trWin; i++)
      {
         if(c[i]>o[i]) upBars++; else if(c[i]<o[i]) dnBars++;
      }
      double trRange=hh-ll;
      double upPct=(double)upBars/(double)trWin, dnPct=(double)dnBars/(double)trWin;
      bool bothAlive=(upPct>=0.20 && dnPct>=0.20);
      bool notTrend=(atr>0.0 && trRange<atr*4.0);
      bool touchedBoth=(hh-h[shift]<=trRange*0.35) || (l[shift]-ll<=trRange*0.35);
      // «نزدیکی به هر دو مرز در پنجره» — واقعی: کمترین فاصلهٔ بسته‌ها به مرزها
      int nearUp=0, nearDn=0;
      for(int i=shift;i<shift+trWin;i++)
      {
         if(h[i]>=hh-trRange*0.15) nearUp++;
         if(l[i]<=ll+trRange*0.15) nearDn++;
      }
      bothAlive=bothAlive && (nearUp>=2) && (nearDn>=2);
      bi.inTradingRange=(bothAlive && notTrend);
      bi.trHigh=hh; bi.trLow=ll; bi.trMid=ll+trRange*0.5; bi.trBars=trWin;
      // شکست مؤثر = بستهٔ قاطع خارج رنج؛ شکست ناموفق = فتیله بیرون + بسته داخل
      bi.trBreakUp  =(bi.inTradingRange && c[shift]>hh);
      bi.trBreakDn  =(bi.inTradingRange && c[shift]<ll);
      bi.trFailedBreakUp=(bi.inTradingRange && h[shift]>hh && c[shift]<hh);
      bi.trFailedBreakDn=(bi.inTradingRange && l[shift]<ll && c[shift]>ll);
      // ================ Measured Move (AB=CD) ================================
      // منبع (Brooks, Trading Price Action Trends — فصل Measured Moves؛ «AB=CD»):
      // حرکت لگ اول (AB) که پس از پولبک (BC) تکرار شود، هدف ۱۰۰٪ امتداد (D) می‌سازد:
      // D = C + (A-B). شرط: A/B/C پیوت تأییدشدهٔ چپ/راست با شمارش موجود.
      if(total>shift+InpSwingLeft+InpSwingRight+6)
      {
         int pr=InpSwingRight, pl=InpSwingLeft;
         // جست‌وجوی سه پیوت B (سقف یا کف) داخل ۴۰ کندل اخیر
         int bIdx=-1; bool bHigh=true;
         for(int j=shift+pr; j<=shift+pr+30 && j+pl<total; j++)
         {
            bool ph=true, plw=true;
            for(int s2=1;s2<=pl;s2++){ if(h[j+s2]>=h[j]) ph=false; if(l[j+s2]<=l[j]) plw=false; }
            for(int s2=1;s2<=pr;s2++){ if(h[j-s2]>h[j])  ph=false; if(l[j-s2]<l[j])  plw=false; }
            if(ph){ bIdx=j; bHigh=true; break; }
            if(plw){ bIdx=j; bHigh=false; break; }
         }
         if(bIdx>0)
         {
            // A = اکسترمم مقابل پیش از B، C = اکسترمم بعد از B (تا کندل جاری)
            if(bHigh)
            {
               int aIdx=bIdx+ArrayMinimum(l,MathMin(20,bIdx-1),1); // ساده: کف ۲۰ کندل پیش از B
               int aSpan=MathMin(20,bIdx); if(aSpan>0) aIdx=bIdx+ArrayMinimum(l,aSpan,1); else aIdx=-1;
               int cSpan=(bIdx-pr)-shift; if(cSpan<1) cSpan=1;
               int cIdx=shift+ArrayMinimum(l,cSpan,0);
               if(aIdx>0 && cIdx<=bIdx-pr && l[cIdx]<l[bIdx] && l[aIdx]>l[cIdx])
               {
                  bi.mmA=l[aIdx]; bi.mmB=h[bIdx]; bi.mmC=l[cIdx];
                  bi.mmD=bi.mmC+(bi.mmB-bi.mmA);   // ۱۰۰٪ امتداد AB=CD
                  bi.mmTimeA=BarTime(aIdx); bi.mmTimeB=BarTime(bIdx); bi.mmTimeC=BarTime(cIdx);
                  bi.mmValid=(bi.mmB>bi.mmA && bi.mmB>bi.mmC && (bi.mmB-bi.mmA)>atr*0.8);
               }
            }
            else
            {
               int aSpan=MathMin(20,bIdx); int aIdx=(aSpan>0)? bIdx+ArrayMaximum(h,aSpan,1) : -1;
               int cSpan=(bIdx-pr)-shift; if(cSpan<1) cSpan=1;
               int cIdx=shift+ArrayMaximum(h,cSpan,0);
               if(aIdx>0 && cIdx<=bIdx-pr && h[cIdx]>h[bIdx] && h[aIdx]<h[cIdx])
               {
                  bi.mmA=h[aIdx]; bi.mmB=l[bIdx]; bi.mmC=h[cIdx];
                  bi.mmD=bi.mmC-(bi.mmA-bi.mmB);
                  bi.mmTimeA=BarTime(aIdx); bi.mmTimeB=BarTime(bIdx); bi.mmTimeC=BarTime(cIdx);
                  bi.mmValid=(bi.mmA>bi.mmB && bi.mmC>bi.mmB && (bi.mmA-bi.mmB)>atr*0.8);
               }
            }
         }
      }
      // ================ Channel Lines =========================================
      // منبع (Brooks — فصل ۱۵ «How To Trade Channels»): کانال = روند با شیب
      // قابل‌توجه؛ خط کانال موازی خط روند، هدف/مغناطیس بعدی است. اینجا فقط
      // شیب Always-In گزارش می‌شود (خط روند رسمی همان Trendline Liquidity است)
      // و بستهٔ جاری نسبت به EMA20، سقف/کف کانال را نشان می‌دهد.
      if(bi.alwaysIn>0 && bi.ema20>0.0 && c[shift]>bi.ema20) bi.chSlope=+1;
      else if(bi.alwaysIn<0 && bi.ema20>0.0 && c[shift]<bi.ema20) bi.chSlope=-1;
   }
   return bi;
}
// helper کوچک برای خوانایی
double cur(const double &a[], int i){ return a[i]; }

// ---------- فاز ۱۹ · تکمیل در فاز ۳۴: RTM به‌عنوان موتور رویداد ----------
// ایراد اثبات‌شدهٔ نسخهٔ قبلی: تنها یک رشتهٔ یادداشت تولید می‌شد؛ هیچ شناسه،
// رجیستری، رسم یا توضیح قابل‌کلیکی برای Trap / Momentum / Engulfing / Rejection
// وجود نداشت — یعنی ۵ قلم از فهرست خواسته‌ها بی‌پیاده‌سازی بود (فقط Compression
// و Expansion آن هم به‌صورت متن وجود داشتند).
//
// تعریف هر رویداد (منبع: RTM = Read The Market؛ همان تعریف‌های رایج «Trap /
// Momentum / Compression-Expansion / Engulfing / Rejection»):
//   Compression  = میانگین دامنهٔ N کندل کمتر از آستانه → انرژی ذخیره شده
//   Expansion    = کندل با دامنهٔ بزرگ پس از فشر‌دگی (آزادسازی انرژی)
//   Trap Entry   = فتیله‌ای که استاپ‌های یک طرف جعبهٔ فشر‌دگی را می‌زند و قیمت
//                  داخل همان جعبه می‌بندد (شکار استاپ)
//   Momentum     = کندل فراخ‌دامنه با بدنهٔ غالب و بستهٔ نزدیک اکستریم جهت
//   Engulfing    = بدنهٔ کندل جاری، بدنهٔ کندل قبلی را در جهت مخالف می‌پوشاند
//   Rejection    = فتیلهٔ بلند در یک انتها و بسته‌شدن در ثلث مخالف
enum ENUM_RTM_EVENT { RTM_NONE, RTM_COMPRESSION, RTM_EXPANSION, RTM_TRAP, RTM_MOMENTUM, RTM_ENGULF, RTM_REJECTION };

struct RTMObj
{
   long           id;
   ENUM_RTM_EVENT evt;
   datetime       time;
   double         price;    // قیمت محوری رویداد (سطح جارو شده / بستهٔ کندل)
   double         top, bottom;  // جعبهٔ فشر‌دگی یا محدودهٔ کندل
   int            dir;      // +1 صعودی · -1 نزولی · 0 خنثی
   string         note;
};
RTMObj g_rtm[];
long   g_rtmDropped=0;

string RTMEventName(ENUM_RTM_EVENT e)
{
   switch(e)
   {
      case RTM_COMPRESSION: return "Compression (فشر‌دگی)";
      case RTM_EXPANSION:   return "Expansion (انبساط)";
      case RTM_TRAP:        return "Trap Entry (شکار استاپ)";
      case RTM_MOMENTUM:    return "Momentum Candle (کندل ممنتوم)";
      case RTM_ENGULF:      return "Engulfing (پوشش بدنه)";
      case RTM_REJECTION:   return "Rejection (رد قیمت)";
      default:              return "RTM";
   }
}

void PushRTM(ENUM_RTM_EVENT evt, datetime t, double price, double top, double bottom, int dir, string note)
{
   int n=ArraySize(g_rtm);
   if(n>=MathMax(1,InpRTM_MaxEvents)) { ArrayRemove(g_rtm,0,1); n--; g_rtmDropped++; }
   ArrayResize(g_rtm,n+1);
   g_rtm[n].id=NextFamId(); g_rtm[n].evt=evt; g_rtm[n].time=t;
   g_rtm[n].price=price; g_rtm[n].top=top; g_rtm[n].bottom=bottom;
   g_rtm[n].dir=dir; g_rtm[n].note=note;
}

void UpdateRTM(const double &o[], const double &h[], const double &l[], const double &c[], int shift, double atr)
{
   if(!InpEnableRTM || atr<=0.0) return;
   int need=MathMax(3,InpRTM_CompressBars);
   if(shift+need+2>=ArraySize(h)) return;
   double sum=0.0, boxHi=0.0, boxLo=0.0;
   for(int k=1;k<=need;k++)
   {
      sum+=(h[shift+k]-l[shift+k]);
      if(k==1){ boxHi=h[shift+k]; boxLo=l[shift+k]; }
      else { boxHi=MathMax(boxHi,h[shift+k]); boxLo=MathMin(boxLo,l[shift+k]); }
   }
   double avg=sum/need;
   double rng=h[shift]-l[shift];
   double body=MathAbs(c[shift]-o[shift]);
   double upTail=h[shift]-MathMax(o[shift],c[shift]);
   double dnTail=MathMin(o[shift],c[shift])-l[shift];
   bool compress=(avg<atr*InpRTM_CompressRangeATR);
   bool expand=(rng>atr*1.5);
   int  dir=(c[shift]>o[shift])? 1 : ((c[shift]<o[shift])? -1 : 0);
   datetime t=BarTime(shift);

   if(compress && expand)
   {
      // Phase 42: ATR is spelled out in Persian inside the sentence (میانگین دامنه) so
      // no Latin token sits inside a Persian clause; the flag word is hoisted.
      g_rtmNote=StringFormat("RTM | انبساط پس از فشر‌دگی %d کندلی (میانگین دامنه %.2f) — جهت: %s",need,avg/atr,(dir>0?"بالا":"پایین"));
      PushRTM(RTM_EXPANSION, t, c[shift], h[shift], l[shift], dir,
              StringFormat("EXPANSION | دامنهٔ کندل %.2f برابر میانگین دامنه، پس از فشر‌دگی %.2f برابر (میانگین %d کندل)", rng/atr, avg/atr, need));
   }
   else if(compress)
   {
      g_rtmNote=StringFormat("RTM | فشر‌دگی فعال (%d کندل، میانگین %.2f برابر میانگین دامنه) — منتظر انبساط",need,avg/atr);
      int n=ArraySize(g_rtm);
      if(n==0 || g_rtm[n-1].evt!=RTM_COMPRESSION)
         PushRTM(RTM_COMPRESSION, t, (boxHi+boxLo)/2.0, boxHi, boxLo, 0,
                 StringFormat("COMPRESSION | میانگین دامنهٔ %d کندل %.2f برابر میانگین دامنه (آستانه %.2f) — انرژی ذخیره شده", need, avg/atr, InpRTM_CompressRangeATR));
   }

   // ---- Trap Entry: فتیله یک طرف جعبه را می‌زند و بسته داخل جعبه است ----
   if(compress && rng>0.0)
   {
      if(h[shift]>boxHi && c[shift]<boxHi)
         PushRTM(RTM_TRAP, t, boxHi, h[shift], boxLo, -1,
                 StringFormat("Trap بالا: فتیله تا %.5f بالای جعبه رفت (%.5f) ولی بسته داخل ماند — استاپ‌های سمت فروش شکار شد", h[shift], boxHi));
      else if(l[shift]<boxLo && c[shift]>boxLo)
         PushRTM(RTM_TRAP, t, boxLo, boxHi, l[shift], 1,
                 StringFormat("Trap پایین: فتیله تا %.5f زیر جعبه رفت (%.5f) ولی بسته داخل ماند — استاپ‌های سمت خرید شکار شد", l[shift], boxLo));
   }

   // ---- Momentum Candle ----
   if(rng>atr*InpRTM_MomentumATR && (body/rng)>=InpRTM_MomentumBody && dir!=0)
   {
      bool closesNearExt=(dir>0)? ((h[shift]-c[shift])<=rng*0.25) : ((c[shift]-l[shift])<=rng*0.25);
      if(closesNearExt)
         PushRTM(RTM_MOMENTUM, t, c[shift], h[shift], l[shift], dir,
                 StringFormat("MOMENTUM | دامنه %.2f برابر میانگین دامنه و بدنه به دامنه %.0f درصد، با بستهٔ نزدیک اکستریم در جهت %s",
                              rng/atr, body/rng*100.0, dir>0?"صعود":"نزول"));
   }

   // ---- Engulfing: بدنهٔ جاری، بدنهٔ قبلی را در جهت مخالف می‌پوشاند ----
   double o1=o[shift+1], c1=c[shift+1];
   double b1Hi=MathMax(o1,c1), b1Lo=MathMin(o1,c1);
   bool body1Down=(c1<o1), body1Up=(c1>o1);
   if(dir>0 && body1Down && MathMin(o[shift],c[shift])<=b1Lo && c[shift]>=b1Hi)
      PushRTM(RTM_ENGULF, t, c[shift], h[shift], l[shift], 1,
              StringFormat("Engulfing صعودی: بدنهٔ کندل جاری بدنهٔ نزولی قبلی (%.5f–%.5f) را کامل پوشاند", b1Lo, b1Hi));
   else if(dir<0 && body1Up && MathMax(o[shift],c[shift])>=b1Hi && c[shift]<=b1Lo)
      PushRTM(RTM_ENGULF, t, c[shift], h[shift], l[shift], -1,
              StringFormat("Engulfing نزولی: بدنهٔ کندل جاری بدنهٔ صعودی قبلی (%.5f–%.5f) را کامل پوشاند", b1Lo, b1Hi));

   // ---- Rejection: فتیلهٔ بلند و بستهٔ ثلث مخالف ----
   if(rng>0.0)
   {
      if(dnTail>=rng*InpRTM_RejectTailRatio && c[shift]>l[shift]+rng*0.66)
         PushRTM(RTM_REJECTION, t, l[shift], h[shift], l[shift], 1,
                 StringFormat("Rejection پایین: فتیلهٔ پایین %.0f%% دامنه بود و کندل در ثلث بالا بست — عرضه‌ها جذب شد", dnTail/rng*100.0));
      else if(upTail>=rng*InpRTM_RejectTailRatio && c[shift]<h[shift]-rng*0.66)
         PushRTM(RTM_REJECTION, t, h[shift], h[shift], l[shift], -1,
                 StringFormat("Rejection بالا: فتیلهٔ بالا %.0f%% دامنه بود و کندل در ثلث پایین بست — تقاضای پرشده رد شد", upTail/rng*100.0));
   }
}

// ---------- فازهای ۲۰–۲۱: Market/Volume Profile با tick-volume ----------
// منبع حجم: iTickVolume در کندل‌های بسته (MT5 روی فارکس/CFD فقط tick volume
// می‌دهد — مستند رسمی؛ برچسب صادقانه در tooltip و CSV).
void UpdateProfile()
{
   if(!InpEnableProfile) return;
   int need=MathMax(24,InpProfileLookbackBars);
   int rows=MathMax(8,InpProfilePriceRows);
   double h[], l[];   long v[];
   ArraySetAsSeries(h,true); ArraySetAsSeries(l,true); ArraySetAsSeries(v,true);
   int copiedH=CopyHigh(_Symbol,PERIOD_CURRENT,0,need,h);        if(copiedH<=0) return;
   int copiedL=CopyLow(_Symbol,PERIOD_CURRENT,0,need,l);         if(copiedL<=0) return;
   // فاز ۲۴: قبلاً یک حلقهٔ iVolume (یک دسترسی timeseries در هر کندل) بود؛
   // حالا یک CopyTickVolume. مقدارها عیناً همان‌اند (اندیس ۰ = جدیدترین).
   int copiedV=CopyTickVolume(_Symbol,PERIOD_CURRENT,0,need,v);  if(copiedV<=0) return;
   // فاز ۴۰: مرجع حلقه = کوچک‌ترین سریِ واقعاً کپی‌شده، نه عدد درخواستی need.
   // همان دلیل ایراد Wyckoff: بعد از تعویض تایم‌فریم Copy* کمتر از need می‌دهد
   // و حلقهٔ i<need روی آرایهٔ کوتاه‌تر سرریز می‌کرد.
   int bars=MathMin(copiedV,MathMin(ArraySize(h),ArraySize(l)));
   if(bars<3) return;

   double pHigh=h[ArrayMaximum(h)], pLow=l[ArrayMinimum(l)];
   if(pHigh<=pLow) return;
   double rowH=(pHigh-pLow)/rows;
   // فاز ۲۲ — دو ایراد محاسباتی واقعی در ساخت پروفایل:
   //  ۱) قبلاً حجم کامل هر کندل به **همهٔ** ردیف‌هایی که کندل در بر می‌گرفت
   //     اضافه می‌شد؛ یعنی یک کندل پرنوسان با دامنهٔ بزرگ چند برابر وزن
   //     واقعی‌اش حجم می‌گرفت و POC به سمت کندل‌های پرنوسان کشیده می‌شد
   //     (دوباره‌شماری واقعی). حالا حجم کندل به‌صورت مساوی بین ردیف‌های
   //     پوشش‌داده‌شده تقسیم می‌شود — همان روش استاندارد ساخت پروفایل از
   //     کندل OHLC (جمع ردیف‌ها = حجم واقعی بازه).
   double volAt[]; ArrayResize(volAt,rows); ArrayInitialize(volAt,0.0);
   for(int i=0;i<bars;i++)
   {
      int r=(int)((h[i]-pHigh)/rowH); if(r<0) r=0; if(r>=rows) r=rows-1;
      int r2=(int)((l[i]-pHigh)/rowH); if(r2<0) r2=0; if(r2>=rows) r2=rows-1;
      int lo=MathMin(r,r2), hi=MathMax(r,r2);
      double share=(double)v[i]/(double)(hi-lo+1);
      for(int rr=lo; rr<=hi; rr++) volAt[rr]+=share;
   }
   double total=0.0; int poc=0;
   for(int r=0;r<rows;r++){ total+=volAt[r]; if(volAt[r]>volAt[poc]) poc=r; }

   // Value Area — قاعدهٔ استاندارد Market Profile، مستند CQG («Market Profile
   // Value Areas Study»): «سیستم VA را یک قیمت در هر تکرار گسترش می‌دهد و
   // جهت را بر مبنای تعداد TPO دو قیمتِ کنار VA یعنی **دو ردیف مجاور**
   // انتخاب می‌کند و به سمت قیمتی با TPO بیشتر پیش می‌رود» و در تساوی هر دو
   // سمت افزوده می‌شود. پیاده‌سازی قبلی فقط یک ردیف را مقایسه می‌کرد و با
   // قاعدهٔ CME/CQG یکی نبود (مورد اصلاح فاز ۲۲).
   double vaPct=MathMax(50.0,MathMin(95.0,InpProfileVA_Percent))/100.0;
   double target=total*vaPct;
   double acc=volAt[poc]; int up=poc, dn=poc;
   while(acc<target && (up<rows-1 || dn>0))
   {
      double up2=(up<rows-1)? volAt[up+1] : 0.0;
      if(up<rows-2) up2+=volAt[up+2];
      double dn2=(dn>0)? volAt[dn-1] : 0.0;
      if(dn>1) dn2+=volAt[dn-2];
      bool canUp=(up<rows-1), canDn=(dn>0);
      if(!canUp && !canDn) break;
      bool goUp=canUp && (!canDn || up2>dn2);
      bool goDn=canDn && (!canUp || dn2>up2);
      if(canUp && canDn && up2==dn2){ goUp=true; goDn=true; }   // تساوی: هر دو سمت
      if(goUp){ acc+=volAt[up+1]; up++; }
      if(goDn){ acc+=volAt[dn-1]; dn--; }
   }
   g_profileDaily.valid=true;
   g_profileDaily.poc=pHigh-(poc+0.5)*rowH;
   g_profileDaily.vah=pHigh-up*rowH;
   g_profileDaily.val=pHigh-(dn+1)*rowH;
   g_profileDaily.sessionHigh=pHigh; g_profileDaily.sessionLow=pLow;
   g_profileDaily.totalVol=(long)MathRound(total); g_profileDaily.pocRowIndex=poc;
   // فاز ۳۴: ردیف‌های حجم برای تشخیص HVN/LVN نگه داشته می‌شوند (قبلاً دور ریخته
   // می‌شدند و در نتیجه «HVN/LVN» در فهرست خواسته‌ها وجود خارجی نداشت).
   g_profRows=rows; g_profHigh=pHigh; g_profRowH=rowH;
   ArrayResize(g_profVolAt,rows);
   for(int r=0;r<rows;r++) g_profVolAt[r]=volAt[r];
   double rowAvg=(rows>0)? total/(double)rows : 0.0;
   g_profileDaily.hvnCount=0; g_profileDaily.lvnCount=0;
   for(int r=1;r<rows-1;r++)
   {
      double vv=volAt[r];
      bool isMax=(vv>volAt[r-1] && vv>volAt[r+1]);
      bool isMin=(vv<volAt[r-1] && vv<volAt[r+1]);
      double price=pHigh-(r+0.5)*rowH;
      if(isMax && rowAvg>0.0 && vv>=rowAvg*InpProfileHVN_Ratio && g_profileDaily.hvnCount<3)
         g_profileDaily.hvn[g_profileDaily.hvnCount++]=price;
      if(isMin && rowAvg>0.0 && vv<=rowAvg*InpProfileLVN_Ratio && g_profileDaily.lvnCount<3)
         g_profileDaily.lvn[g_profileDaily.lvnCount++]=price;
   }
   // Phase 42: the four acronyms are the subject of this readout, so they lead
   // the row (dictionary order); the caveat after the separator is pure Persian.
   g_profileNote=StringFormat("PROFILE | POC %.2f | VA %.2f–%.2f | HVN %d | LVN %d — حجم تیک است، نه حجم واقعی؛ ناحیهٔ ارزش با قاعدهٔ دو ردیفی محاسبه می‌شود",
                              g_profileDaily.poc,g_profileDaily.vah,g_profileDaily.val,
                              g_profileDaily.hvnCount,g_profileDaily.lvnCount);
}

//====================================================================
// فاز ۳۴ — Auction Market Theory: IB · TPO · نوع روز · نوع باز شدن · Naked POC
//
// منبع قاعده‌ها (بازبینی 2026-09-19):
//  · FTMO × OANDA — «Market Profile: Types of Opens and the Anatomy of a
//      Trading Day»: «the first hour of trading, known as the Initial Balance (IB)».
//  · واژه‌نامهٔ استاندارد Market Profile (Dalton — Mind Over Markets):
//      Normal day = IB گسترده که تقریباً کل دامنهٔ روز را می‌پوشاند؛
//      Neutral day = هر دو طرف IB شکسته می‌شود و قیمت داخل IB می‌بندد؛
//      Trend day = پروفایل نامتوازن با IB کوچک نسبت به دامنهٔ روز؛
//      Non-trend day = «IB باریکی که معمولاً تا آخر سشن حفظ می‌شود»؛
//      Open-Drive = باز شدن بیرون رنج/ارزش روز قبل و حرکت یک‌جهته.
//  · TPO (Time Price Opportunity) = شمارش «زمان» در هر ردیف قیمت (نه حجم).
//      پس VA زمان‌محور و VA حجم‌محور دو عدد متفاوت و هر دو معتبرند؛ هر دو گزارش می‌شوند.
//  · Naked/Virgin POC = POC یک سشن که پس از بسته‌شدن آن سشن لمس نشده است.
// همهٔ آستانه‌ها ورودی قابل‌تنظیم‌اند (بدون عدد جادویی پنهان).
//====================================================================
struct AMTDay
{
   datetime start;  bool valid;
   double   open, close, hi, lo;
   double   ibHi, ibLo;  bool ibValid;
   double   tpoPoc, tpoVah, tpoVal;  bool tpoOk;
   int      bars;
};

double g_profVolAt[];
int    g_profRows=0;
double g_profHigh=0.0, g_profRowH=0.0;

// تاریخچهٔ POC روزهای گذشته برای Naked/Virgin POC
struct PocHistRec { datetime dayStart; double poc; bool touched; };
PocHistRec g_pocHist[];
datetime   g_pocHistBuiltFor=0;

// شروع پنجرهٔ روز با مرجع انتخاب‌شدهٔ کاربر (InpPD_Anchor)
bool AMTDayStart(int back, datetime refBarTime, datetime &startOut, datetime &endOut)
{
   if(InpPD_Anchor==PD_ANCHOR_BROKER_DAY)
   {
      datetime t0=iTime(_Symbol,PERIOD_D1,back);
      if(t0<=0) return false;
      startOut=t0;
      endOut=(datetime)((long)t0+86400);
      return true;
   }
   int anchorH=(InpPD_Anchor==PD_ANCHOR_NY_1700)? 17 : 0;
   double hi=0.0, lo=0.0; int cnt=0;
   return WindowForDayBack(back, anchorH,0, anchorH,0, refBarTime, startOut, endOut, hi, lo, cnt, true);
}

// ساخت پروفایل یک روز روی تایم‌فریم منبع سشن (بدون دسترسی جدید به timeseries)
bool AMTBuildDay(int back, datetime barTime, AMTDay &d)
{
   d.valid=false; d.ibValid=false; d.tpoOk=false; d.bars=0;
   d.open=0; d.close=0; d.hi=0; d.lo=0; d.ibHi=0; d.ibLo=0;
   datetime dS=0,dE=0;
   if(!AMTDayStart(back, barTime, dS, dE)) return false;
   d.start=dS;
   int copied=ArraySize(g_winCacheT);
   if(copied<=0) return false;
   datetime ibEnd=(datetime)((long)dS+(long)MathMax(5,InpProfileIB_Minutes)*60);
   bool first=true;
   for(int i=0;i<copied;i++)
   {
      datetime t=g_winCacheT[i];
      if(t<dS || t>=dE) continue;
      if(first){ d.close=g_winCacheC[i]; first=false; }
      d.open=g_winCacheO[i];            // آخرین مقدار = قدیمی‌ترین کندل روز = open واقعی
      if(d.bars==0){ d.hi=g_winCacheH[i]; d.lo=g_winCacheL[i]; }
      else { d.hi=MathMax(d.hi,g_winCacheH[i]); d.lo=MathMin(d.lo,g_winCacheL[i]); }
      if(t<ibEnd)
      {
         if(!d.ibValid){ d.ibHi=g_winCacheH[i]; d.ibLo=g_winCacheL[i]; d.ibValid=true; }
         else { d.ibHi=MathMax(d.ibHi,g_winCacheH[i]); d.ibLo=MathMin(d.ibLo,g_winCacheL[i]); }
      }
      d.bars++;
   }
   if(d.bars<2 || d.hi<=d.lo) return false;
   d.valid=true;

   // پروفایل TPO: هر کندل به هر ردیفی که در بر می‌گیرد **یک** TPO می‌دهد
   int rows=MathMax(8,InpProfilePriceRows);
   int tpoAt[]; ArrayResize(tpoAt,rows); ArrayInitialize(tpoAt,0);
   double rowH=(d.hi-d.lo)/rows;
   if(rowH<=0.0) return true;
   for(int i=0;i<copied;i++)
   {
      datetime t=g_winCacheT[i];
      if(t<dS || t>=dE) continue;
      int r=(int)((g_winCacheH[i]-d.hi)/rowH); if(r<0) r=0; if(r>=rows) r=rows-1;
      int r2=(int)((g_winCacheL[i]-d.hi)/rowH); if(r2<0) r2=0; if(r2>=rows) r2=rows-1;
      int lo2=MathMin(r,r2), hi2=MathMax(r,r2);
      for(int rr=lo2; rr<=hi2; rr++) tpoAt[rr]+=1;
   }
   int tot=0; for(int r=0;r<rows;r++) tot+=tpoAt[r];
   if(tot<=0) return true;
   int poc=0; for(int r=0;r<rows;r++) if(tpoAt[r]>tpoAt[poc]) poc=r;
   double vaPct=MathMax(50.0,MathMin(95.0,InpProfileVA_Percent))/100.0;
   double target=tot*vaPct, acc=tpoAt[poc];
   int up=poc, dn=poc;
   while(acc<target && (up<rows-1 || dn>0))
   {
      double up2=(up<rows-1)? tpoAt[up+1] : 0.0;
      if(up<rows-2) up2+=tpoAt[up+2];
      double dn2=(dn>0)? tpoAt[dn-1] : 0.0;
      if(dn>1) dn2+=tpoAt[dn-2];
      bool canUp=(up<rows-1), canDn=(dn>0);
      if(!canUp && !canDn) break;
      bool goUp=canUp && (!canDn || up2>dn2);
      bool goDn=canDn && (!canUp || dn2>up2);
      if(canUp && canDn && up2==dn2){ goUp=true; goDn=true; }
      if(goUp){ acc+=tpoAt[up+1]; up++; }
      if(goDn){ acc+=tpoAt[dn-1]; dn--; }
   }
   d.tpoPoc=d.hi-(poc+0.5)*rowH;
   d.tpoVah=d.hi-up*rowH;
   d.tpoVal=d.hi-(dn+1)*rowH;
   d.tpoOk=true;
   return true;
}

// نوع روز از نسبت IB به دامنهٔ روز + محل بسته‌شدن (تعریف استاندارد Market Profile)
uint AMTDayType(const AMTDay &d, double atr)
{
   if(!d.valid || !d.ibValid) return 0;
   double ibR=d.ibHi-d.ibLo;
   double dR=d.hi-d.lo;
   if(ibR<=0.0 || dR<=0.0) return 0;
   bool extUp=(d.hi>d.ibHi), extDn=(d.lo<d.ibLo);
   // Neutral: هر دو طرف IB شکسته شود و بسته داخل IB بماند
   if(extUp && extDn && d.close<=d.ibHi && d.close>=d.ibLo) return 4;
   // Trend: IB کوچک نسبت به دامنهٔ روز و بسته در ربع بالا/پایین روز
   double q=dR*0.25;
   bool closeTop=(d.close>=d.hi-q), closeBot=(d.close<=d.lo+q);
   if(ibR<=InpAMT_TrendIBRatio*dR && (closeTop||closeBot) && (extUp||extDn)) return 1;
   // Non-trend: IB باریک/گسترده که تا آخر سشن حفظ شده (بدون امتداد)
   if(!extUp && !extDn && ibR>=InpAMT_NontrendIBRatio*dR) return 5;
   // Normal Variation: یک طرف شکسته و بسته بیرون IB
   if((extUp && d.close>d.ibHi) || (extDn && d.close<d.ibLo)) return 2;
   return 3;   // Normal
}

string AMTDayTypeName(uint t)
{
   switch(t)
   {
      // Phase 42: the Latin name of the day type opens the row (dictionary
      // order) and the explanation after it is pure Persian. A Latin word
      // inside a Persian clause splits the RTL run in two, so none is allowed
      // there - which is why the EMA acronym is spelled out as well.
      case 1: return "TREND DAY | روز روندی؛ جهت تا پایان روز حفظ می‌شود";
      case 2: return "NORMAL VARIATION DAY | نوسان طبیعی؛ دامنه کمی از روز قبل بیشتر";
      case 3: return "NORMAL DAY | روز معمول؛ دامنه نزدیک روز قبل";
      case 4: return "NEUTRAL DAY | خنثی — هر دو طرف بازهٔ اولیه شکسته";
      case 5: return "NON-TREND DAY | بی‌روند — بازهٔ اولیه حفظ شده";
      default: return "نامعلوم";
   }
}

// نوع باز شدن: Drive / Test-Drive / Reject / Auction — بر مبنای موقعیت open نسبت
// به دامنهٔ روز قبل و رفتار قیمت نسبت به IB همان روز (منبع: Dalton، فصل Opening Types)
uint AMTOpenType(const AMTDay &cur, const AMTDay &prev)
{
   if(!cur.valid || !cur.ibValid) return 0;
   if(!prev.valid) return 4;
   bool abovePrev=(cur.open>prev.hi), belowPrev=(cur.open<prev.lo);
   if(abovePrev || belowPrev) return 1;                       // Open-Drive
   double ibR=cur.ibHi-cur.ibLo;
   if(ibR<=0.0) return 4;
   if(prev.tpoOk && cur.open<=prev.tpoVah && cur.open>=prev.tpoVal) return 4;  // Open-Auction
   bool extUp=(cur.hi>cur.ibHi), extDn=(cur.lo<cur.ibLo);
   bool driveDir=(cur.close>cur.open);
   if(extUp && driveDir && (cur.close-cur.ibHi)>ibR*0.5) return 2;             // Test-Drive بالا
   if(extDn && !driveDir && (cur.ibLo-cur.close)>ibR*0.5) return 2;             // Test-Drive پایین
   if((extUp && !driveDir) || (extDn && driveDir)) return 3;                   // Reject-Reverse
   return 4;
}

string AMTOpenTypeName(uint t)
{
   switch(t)
   {
      case 1: return "OPEN-DRIVE | باز شدن بیرون رنج روز قبل و ادامه در همان جهت";
      case 2: return "OPEN-TEST-DRIVE | تست بازهٔ اولیه و سپس حرکت در جهت";
      case 3: return "OPEN-REJECT-REVERSE | رد بازهٔ اولیه و بازگشت";
      case 4: return "OPEN-AUCTION | باز شدن درون ناحیهٔ ارزش و تعادل";
      default: return "نامعلوم";
   }
}

void UpdateProfileAMT(datetime barTime, double atr)
{
   g_profileDaily.amtValid=false;
   if(!InpEnableProfile) return;
   int needBars=MathMax(400,(int)((double)(86400*(InpAMT_HistDays+2))/PeriodSeconds(InpSessionSourceTF))+120);
   if(!EnsureSessionBars(InpSessionSourceTF, needBars)) return;
   if(ArraySize(g_winCacheT)<30) return;

   AMTDay cur, prev;
   if(!AMTBuildDay(0, barTime, cur)) return;
   AMTBuildDay(1, barTime, prev);

   g_profileDaily.amtValid=true;
   g_profileDaily.dayOpen=cur.open; g_profileDaily.dayClose=cur.close;
   g_profileDaily.dayHi=cur.hi;     g_profileDaily.dayLo=cur.lo;
   g_profileDaily.ibHi=cur.ibHi;    g_profileDaily.ibLo=cur.ibLo;
   g_profileDaily.dayType=AMTDayType(cur, atr);
   g_profileDaily.openType=AMTOpenType(cur, prev);
   if(cur.tpoOk)
   {
      g_profileDaily.tpoValid=true;
      g_profileDaily.tpoPoc=cur.tpoPoc;
      g_profileDaily.tpoVah=cur.tpoVah;
      g_profileDaily.tpoVal=cur.tpoVal;
   }

   // --- Balance / Imbalance: پذیرش درون ارزش یا خروج از آن ---
   double refHi=(cur.tpoOk? cur.tpoVah : g_profileDaily.vah);
   double refLo=(cur.tpoOk? cur.tpoVal : g_profileDaily.val);
   double px=cur.close;
   g_profileDaily.balanceNote=(px<=refHi && px>=refLo)
      ? "BALANCE | پذیرش درون ناحیهٔ ارزش؛ تعادل"
      : "IMBALANCE | خروج از ناحیهٔ ارزش؛ عدم تعادل";

   // --- Naked/Virgin POC: تاریخچهٔ POC روزهای گذشته و بررسی لمس نشدن ---
   if(g_pocHistBuiltFor!=cur.start)
   {
      g_pocHistBuiltFor=cur.start;
      ArrayResize(g_pocHist,0);
      int copied=ArraySize(g_winCacheT);
      for(int back=1; back<=MathMax(1,InpAMT_HistDays); back++)
      {
         AMTDay hd;
         if(!AMTBuildDay(back, barTime, hd) || !hd.tpoOk) continue;
         PocHistRec rec; rec.dayStart=hd.start; rec.poc=hd.tpoPoc; rec.touched=false;
         // لمس بعد از پایان همان روز: هر کندلی که POC را در بر بگیرد
         for(int i=0;i<copied;i++)
         {
            if(g_winCacheT[i] < (datetime)((long)hd.start+86400)) continue;   // فقط بعد از روز
            if(g_winCacheT[i] > barTime) continue;
            if(g_winCacheH[i]>=hd.tpoPoc && g_winCacheL[i]<=hd.tpoPoc){ rec.touched=true; break; }
         }
         int n=ArraySize(g_pocHist);
         ArrayResize(g_pocHist,n+1); g_pocHist[n]=rec;
      }
   }
   g_profileDaily.hasNakedPoc=false; g_profileDaily.nakedPoc=0.0; g_profileDaily.nakedPocDay=0;
   for(int i=0;i<ArraySize(g_pocHist);i++)
   {
      if(g_pocHist[i].touched) continue;
      g_profileDaily.hasNakedPoc=true;
      g_profileDaily.nakedPoc=g_pocHist[i].poc;
      g_profileDaily.nakedPocDay=g_pocHist[i].dayStart;
      break;   // جدیدترین POC لمس‌نشده
   }
}

// ---------- دروازهٔ فراخوانی از AnalyzeClosedBar ----------
void UpdateFamilies(const double &o[], const double &h[], const double &l[], const double &c[], int shift, double atr)
{
   UpdateWyckoff(o,h,l,c,shift,atr);   // فاز ۳۳: o لازم شد (کلایمکس/PS به بدنهٔ کندل نیاز دارد)
   DetectSupplyDemand(o,h,l,c,shift,atr);
   if(shift==1)
   {
      // فاز ۳۳: یک منبع واحد برای نمایش و پنل آموزشی (بدون منطق تکراری).
      g_brooksInfo=AnalyzeBrooksBar(o,h,l,c,shift,atr);
      string barKind=g_brooksInfo.isTrendBar? "TREND BAR" : (g_brooksInfo.isDoji? "DOJI"
                  : (g_brooksInfo.isSignalBar? (g_brooksInfo.bullSignal? "BULL SIGNAL BAR":"BEAR SIGNAL BAR") : "کندل عادی"));
      string aiTxt=(g_brooksInfo.alwaysIn>0)? "LONG" : ((g_brooksInfo.alwaysIn<0)? "SHORT":"خنثی");
      string pullTxt="—";
      if(g_brooksInfo.alwaysIn>=0 && g_brooksInfo.hAttempts>0) pullTxt="H"+IntegerToString(g_brooksInfo.hAttempts);
      else if(g_brooksInfo.alwaysIn<=0 && g_brooksInfo.lAttempts>0) pullTxt="L"+IntegerToString(g_brooksInfo.lAttempts);
      // Phase 42: one row - Latin readout labels lead, and every clause after
      // a separator is pure Persian; the moving-average acronym is spelled out
      // in Persian so no Latin token sits inside the sentence.
      g_brooksNote=StringFormat("BROOKS | %s | ALWAYS-IN: %s | میانگین متحرک ۲۰ کندلی: %.5f | شمارش پولبک: %s",
                    barKind, aiTxt, g_brooksInfo.ema20, pullTxt);
   }
   UpdateRTM(o,h,l,c,shift,atr);
   if(shift==1) { UpdateProfile(); UpdateProfileAMT(BarTime(shift), atr); }
   UpdateWyckoffPhase();
}

// ---------- فاز ۱۵: قاعدهٔ DST اروپا ----
// شروع: آخرین یکشنبهٔ مارس ساعت ۰۱:۰۰ UTC · پایان: آخرین یکشنبهٔ اکتبر ۰۱:۰۰ UTC
// (قاعدهٔ ثابت اتحادیهٔ اروپا از ۱۹۹۶؛ همین قاعده برای همهٔ سال‌ها اعمال می‌شود و
//  همین موضوع در مستندات به‌عنوان محدودیت صریح ثبت شده است.)
int DaysInMonthOf(int year, int month)
{
   if(month<1 || month>12) return 30;
   if(month==2)
   {
      bool leap=((year%4==0 && year%100!=0) || year%400==0);
      return leap? 29 : 28;
   }
   int dim[12]={31,28,31,30,31,30,31,31,30,31,30,31};
   return dim[month-1];
}

int LastSundayOfMonth(int year, int month)
{
   int last=DaysInMonthOf(year,month);
   for(int day=last; day>=last-6; day--)
      if(DayOfWeekOf(year,month,day)==0) return day;
   return last;
}

datetime UTCBoundDay(int year, int month, int day, int hour, int minute)
{
   MqlDateTime d;
   d.year=year; d.mon=month; d.day=day; d.hour=hour; d.min=minute; d.sec=0;
   return StructToTime(d);
}

bool EU_IsDST_UTC(datetime utcT)
{
   MqlDateTime d; TimeToStruct(utcT,d);
   if(d.mon<3 || d.mon>10) return false;
   datetime startU=UTCBoundDay(d.year,3,LastSundayOfMonth(d.year,3),1,0);
   datetime endU  =UTCBoundDay(d.year,10,LastSundayOfMonth(d.year,10),1,0);
   return (utcT>=startU && utcT<endU);
}

string BrokerDSTRuleToStr(ENUM_BROKER_DST_RULE r)
{
   switch(r)
   {
      case BDST_AUTO: return "AUTO";
      case BDST_US:   return "US";
      case BDST_EU:   return "EU";
      default:        return "NONE";
   }
}

// AUTO: خانوادهٔ آفست جاری بروکر. بیشتر بروکرهای MT5 روی EET (+2 زمستان / +3 تابستان)
// هستند؛ اگر آفست در محدودهٔ اروپا نبود، قاعدهٔ آمریکا و در غیر این‌صورت «بدون DST»
// انتخاب می‌شود. این تخمین در CSV و پنل صریحاً گزارش می‌شود تا قابل بازبینی باشد.
ENUM_BROKER_DST_RULE ResolveBrokerDSTRule(int currentOffsetSeconds)
{
   if(InpBrokerDSTRule != BDST_AUTO) return InpBrokerDSTRule;
   int h=(int)MathRound((double)currentOffsetSeconds/3600.0);
   if(h>=0 && h<=3)   return BDST_EU;
   if(h==-4 || h==-5) return BDST_US;
   return BDST_NONE;
}

bool BrokerDSTAtUTC(datetime utcT)
{
   if(g_brokerDSTRule==BDST_US) return US_IsDST_UTC(utcT);
   if(g_brokerDSTRule==BDST_EU) return EU_IsDST_UTC(utcT);
   return false;
}

// آفست بروکر در یک لحظهٔ UTC مشخص (تاریخی). با خاموش بودن قابلیت، همان آفست جاری
// برمی‌گردد تا رفتار قبلی دقیقاً قابل بازتولید (و قابل مقایسه) بماند.
int BrokerOffsetSecondsAtUTC(datetime utcT)
{
   if(!InpUseHistoricalBrokerOffset) return g_serverGMTOffsetSeconds;
   return g_brokerStdOffsetSeconds + (BrokerDSTAtUTC(utcT)? 3600 : 0);
}

// آفست بروکر برای یک زمان *سرور* مشخص. چون زمان سرور خودش به آفست وابسته است،
// یک بازآزمایی نقطهٔ ثابت انجام می‌شود (خطای حداکثر یک ساعت فقط در پنجرهٔ گذار).
int BrokerOffsetSecondsAtServer(datetime serverT)
{
   if(!InpUseHistoricalBrokerOffset) return g_serverGMTOffsetSeconds;
   datetime utcA=(datetime)((long)serverT-(long)g_brokerStdOffsetSeconds);
   int offA=g_brokerStdOffsetSeconds+(BrokerDSTAtUTC(utcA)? 3600 : 0);
   datetime utcB=(datetime)((long)serverT-(long)offA);
   int offB=g_brokerStdOffsetSeconds+(BrokerDSTAtUTC(utcB)? 3600 : 0);
   return offB;
}

int NyOffsetSecondsUTC(datetime utcT) { return NY_IsDST_UTC(utcT) ? (-4*3600) : (-5*3600); }

datetime ServerToUTC(datetime serverT) { return (datetime)((long)serverT - (long)BrokerOffsetSecondsAtServer(serverT)); }
datetime UTCToServer(datetime utcT)    { return (datetime)((long)utcT + (long)BrokerOffsetSecondsAtUTC(utcT)); }

// نگه‌داشتن نام قبلی: ورودی «زمان سرور» می‌گیرد
bool IsUS_DST(datetime serverT) { return NY_IsDST_UTC(ServerToUTC(serverT)); }

int NY_GMTOffsetHours(datetime serverT) { return NyOffsetSecondsUTC(ServerToUTC(serverT))/3600; }

// تقویم نیویورک (year,mon,day,hour,min) -> زمان سرور بروکر.
// دو گذار سالانه دقیقاً مدیریت می‌شوند: ابتدا فرض EST آزموده می‌شود و اگر
// آن لحظه در بازهٔ DST باشد، فرض EDT هم بررسی می‌شود.
datetime NYWallToServer(int year, int month, int day, int hour, int minute, int dayShift)
{
   MqlDateTime dt;
   dt.year=year; dt.mon=month; dt.day=day; dt.hour=hour; dt.min=minute; dt.sec=0;
   datetime nyWall = (datetime)((long)StructToTime(dt) + (long)dayShift*86400);
   datetime utcEst = (datetime)((long)nyWall + 5*3600);     // فرض EST
   datetime utc = utcEst;
   if(NY_IsDST_UTC(utcEst))
   {
      datetime utcEdt = (datetime)((long)nyWall + 4*3600);  // فرض EDT
      if(NY_IsDST_UTC(utcEdt)) utc = utcEdt;
   }
   return UTCToServer(utc);
}

void NYStampOf(datetime barTime, MqlDateTime &out)
{
   datetime utc = ServerToUTC(barTime);
   datetime nyTime = (datetime)((long)utc + (long)NyOffsetSecondsUTC(utc));
   TimeToStruct(nyTime, out);
}

// فاز ۱۵: آفست استاندارد (زمستان) و قاعدهٔ DST بروکر از آفست *جاری* استخراج می‌شود.
// بدون این دو، بازسازی آفست تاریخی ممکن نیست (آفست جاری فقط لحظهٔ «حالا» را می‌گوید).
void DeriveBrokerDSTRuleAndStdOffset()
{
   int cur=DetectServerGMTOffsetSeconds();
   g_brokerDSTRule=ResolveBrokerDSTRule(cur);
   datetime nowUtc=(datetime)TimeGMT();
   g_brokerDSTActiveNow=BrokerDSTAtUTC(nowUtc);
   g_brokerStdOffsetSeconds = cur - (g_brokerDSTActiveNow? 3600 : 0);
   g_brokerOffsetSource=StringFormat("detected %+d min | rule %s | std %+d min | DST now %s",
                                     cur/60, BrokerDSTRuleToStr(g_brokerDSTRule),
                                     g_brokerStdOffsetSeconds/60, g_brokerDSTActiveNow?"ON":"OFF");
}

// آفست بروکر: دقیق (ثانیه) و بدون رُند به ساعت — بروکرهای GMT+5:30 هم درست می‌شوند.
// اگر تشخیص خودکار غیرقابل‌اعتماد باشد، InpBrokerToNY_HourOffset به‌عنوان
// ورودی مرجع/fallback استفاده می‌شود (#۵۷ — دیگر ورودی مرده نیست).
int DetectServerGMTOffsetSeconds()
{
   if(InpBrokerGMTOffsetOverrideHours != 99) return InpBrokerGMTOffsetOverrideHours*3600;
   long diff = (long)TimeTradeServer() - (long)TimeGMT();
   if(diff > (long)15*3600 || diff < -(long)15*3600)
   {
      datetime utcNow = (datetime)TimeGMT();
      return (int)((long)NyOffsetSecondsUTC(utcNow) - (long)InpBrokerToNY_HourOffset*3600);
   }
   return (int)diff;
}

// سطوح سشنی که با آفست قدیمی ساخته شده‌اند باید دور ریخته شوند، وگرنه بعد از
// تغییر آفست بروکر، هر دو نسخه (قدیم و جدید) به‌عنوان نقدینگی تازه می‌مانند (#۵۵)
void PurgeSessionLiquidity()
{
   int n=ArraySize(g_liquidity), w=0;
   for(int i=0;i<n;i++)
   {
      if(g_liquidity[i].type==LIQ_SESSION_H || g_liquidity[i].type==LIQ_SESSION_L) continue;
      if(w!=i) g_liquidity[w]=g_liquidity[i];
      w++;
   }
   if(w<n) ArrayResize(g_liquidity,w);
}

// آفست واقعی بروکر در هر کندل بسته بازآزمایی می‌شود؛ اگر بروکر آفست را با DST
// عوض کند، بدون این بازآزمایی همهٔ پنجره‌های سشن تا reload بعدی غلط می‌ماندند (#۵۵)
bool RefreshBrokerOffset()
{
   int seconds = DetectServerGMTOffsetSeconds();
   if(seconds == g_serverGMTOffsetSeconds) return false;
   int oldMin = g_serverGMTOffsetSeconds/60;
   g_serverGMTOffsetSeconds = seconds;
   g_serverGMTOffsetHours   = (int)MathRound((double)seconds/3600.0);
   // فاز ۱۵: عبور از DST بروکر آفست استاندارد را عوض نمی‌کند، ولی باید صریح
   // بازمحاسبه شود تا آفست تاریخی همهٔ لحظه‌های بعدی درست بماند.
   DeriveBrokerDSTRuleAndStdOffset();
   g_brokerOffsetChanges++;
   g_brokerOffsetNote = StringFormat("آفست بروکر عوض شد: %+d → %+d دقیقه (پنجره‌های سشن بازمحاسبه شدند)",
                                     oldMin, seconds/60);
   PrintFormat("ICT Canonical: broker GMT offset changed %+d -> %+d minutes; session liquidity rebuilt",
               oldMin, seconds/60);
   PurgeSessionLiquidity();
   return true;
}

// پنجرهٔ ساعت نیویورک برای یک دقیقهٔ مشخص؛ عبور از نیمه‌شب پشتیبانی می‌شود (۲۰:۰۰→۰۰:۰۰)
bool InNYWindow(int minutes, int startH, int startM, int endH, int endM)
{
   int s=startH*60+startM, e=endH*60+endM;
   if(s==e) return false;                       // پنجرهٔ صفر = غیرفعال
   if(s<e)  return (minutes>=s && minutes<e);
   return (minutes>=s || minutes<e);
}

// یک سری دادهٔ تاریخی که «در زمان asOf» وجود داشته است (بدون نگاه به آینده)
int CopyRatesAsOf(string symbol, ENUM_TIMEFRAMES tf, datetime asOf, int need, MqlRates &rates[])
{
   // Official CopyRates(start_time,count) returns bars whose open time is
   // <= asOf. This avoids the old fixed "latest 240 bars" look-back limit.
   MqlRates tmp[];
   int copied=CopyRates(symbol,tf,asOf,need,tmp);
   if(copied<=0) return 0;
   ArraySetAsSeries(tmp,true);

   // A higher-timeframe bar is usable only after its own close time.
   // The copied series is newest-first, so discard incomplete bars at front.
   int firstClosed=0;
   int tfSeconds=PeriodSeconds(tf);
   if(tfSeconds<=0) tfSeconds=60;
   while(firstClosed<copied && (long)tmp[firstClosed].time+(long)tfSeconds>(long)asOf)
      firstClosed++;
   if(firstClosed>=copied) return 0;

   int available=copied-firstClosed;
   ArrayResize(rates,available);
   for(int i=0;i<available;i++) rates[i]=tmp[firstClosed+i];
   ArraySetAsSeries(rates,true);
   return available;
}

// آخرین باکت بسته‌شدهٔ یک تایم‌فریم قبل از/mساوی barTime (مثال: PDH/PDL)
bool PreviousClosedBucket(datetime barTime, ENUM_TIMEFRAMES tf,
                          double &hi, double &lo, datetime &tOut)
{
   hi=0; lo=0; tOut=0;
   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   int copied=CopyRates(_Symbol,tf,0,80,rates);
   if(copied<3) return false;
   int idx=-1;
   for(int i=0;i<copied;i++) { if(rates[i].time<=barTime) { idx=i; break; } }
   if(idx<0 || idx+1>=copied) return false;
   hi=rates[idx+1].high; lo=rates[idx+1].low; tOut=rates[idx+1].time;
   return (hi>0 && lo>0);
}

//--------------------------------------------------------------------
// فاز ۱۳ (کارایی): دادهٔ منبع سشن یک بار در هر کندل کپی می‌شود و همهٔ
// پنجره‌ها (سشن‌ها + Silver Bullet، روی چند روز) از همان بافر مشترک
// می‌خوانند. علت: در بازسازی، هر پنجره جدا CopyTime/CopyHigh/CopyLow
// می‌زد و مجموع فراخوانی‌ها به ~۹۰ در هر کندل می‌رسید.
//
// حلقهٔ اسکن، شرط توقف و محاسبهٔ hi/lo عیناً همان است، پس اعداد تغییر
// نمی‌کنند؛ فقط منبع داده مشترک شده است. اگر کندل تازه‌ای روی ترمینال
// بیاید، بافر با یک CopyTime تک‌کندی باطل می‌شود.
//--------------------------------------------------------------------
bool EnsureSessionBars(ENUM_TIMEFRAMES tf, int need)
{
   // تک‌کندلی است، پس جهت آرایه (series بودن) اهمیتی ندارد و ArraySetAsSeries
   // روی آرایهٔ ایستا warning 63 می‌داد — همان یک warning فاز ۱۳.
   datetime newest[1];
   if(CopyTime(_Symbol,tf,0,1,newest)<=0) return false;

   bool same = (g_winCacheSymbol==_Symbol && g_winCacheTF==tf && g_winCacheNewest==newest[0]);
   if(same && (ArraySize(g_winCacheT)>=need || g_winCacheExhausted))
   {
      g_winCacheReuses++;
      return true;
   }

   int req=MathMax(need,800);
   datetime t[]; double h[]; double l[]; double o[]; double cl[];
   ArraySetAsSeries(t,true); ArraySetAsSeries(h,true); ArraySetAsSeries(l,true);
   ArraySetAsSeries(o,true); ArraySetAsSeries(cl,true);
   int copied = CopyTime(_Symbol, tf, 0, req, t);
   if(copied<=0) return false;
   int cH=CopyHigh(_Symbol, tf, 0, copied, h);   if(cH<=0) return false;
   int cL=CopyLow(_Symbol, tf, 0, copied, l);    if(cL<=0) return false;
   int cO=CopyOpen(_Symbol, tf, 0, copied, o);   if(cO<=0) return false;
   int cC=CopyClose(_Symbol, tf, 0, copied, cl); if(cC<=0) return false;
   // فاز ۴۰: طول پنجره را با کوچک‌ترین سری واقعاً کپی‌شده قفل کن (هم‌قاعده با
   // اصلاحات 06_MultiTimeframe) تا حلقه هرگز از آرایهٔ کوتاه‌تر بیرون نزند.
   int n=MathMin(copied,MathMin(cH,MathMin(cL,MathMin(cO,cC))));
   if(n<=0) return false;
   copied=n;

   g_winCacheSymbol=_Symbol;
   g_winCacheTF=tf;
   g_winCacheNewest=newest[0];
   g_winCacheExhausted=(copied<req);
   ArrayResize(g_winCacheT,copied);
   ArrayResize(g_winCacheH,copied);
   ArrayResize(g_winCacheL,copied);
   ArrayResize(g_winCacheO,copied);
   ArrayResize(g_winCacheC,copied);
   for(int i=0;i<copied;i++)
   { g_winCacheT[i]=t[i]; g_winCacheH[i]=h[i]; g_winCacheL[i]=l[i];
     g_winCacheO[i]=o[i]; g_winCacheC[i]=cl[i]; }
   g_winCacheCopies++;
   return true;
}

// رنج یک پنجرهٔ سشن، محاسبه‌شده روی تایم‌فریم منبع (مستقل از تایم‌فریم چارت)
bool CollectWindowRange(ENUM_TIMEFRAMES tf, datetime startSrv, datetime endSrv,
                        double &hi, double &lo, int &barCount)
{
   hi=0; lo=0; barCount=0;
   int need = MathMax(400, (int)((endSrv-startSrv)/PeriodSeconds(tf)) + 80);
   if(!EnsureSessionBars(tf,need)) return false;
   int copied=ArraySize(g_winCacheT);
   for(int i=0;i<copied;i++)
   {
      if(g_winCacheT[i] < startSrv) break;
      if(g_winCacheT[i] >= endSrv) continue;
      if(barCount==0){ hi=g_winCacheH[i]; lo=g_winCacheL[i]; }
      else { hi=MathMax(hi,g_winCacheH[i]); lo=MathMin(lo,g_winCacheL[i]); }
      barCount++;
   }
   return (barCount>0);
}

// آیا قدیمی‌ترین کندل موجود در کش پنجره از شروع پنجره قدیمی‌تر (یا مساوی) است؟
// فاز ۳۰ (#۷۵): بدون این گارد، پنجرهٔ نیمه‌پوشیده یک رنج کوچک‌تر از واقعیت
// می‌داد — یعنی PDH/PDL/PWH/PWL یا رنج سشن «غلط»، نه فقط «غایب». اصل پروژه
// این است که هیچ مقدار تقریبی به‌عنوان داده معتبر ثبت نشود.
bool WindowFullyCovered(datetime startSrv)
{
   int copied=ArraySize(g_winCacheT);
   if(copied<=0) return false;
   return (g_winCacheT[copied-1] <= startSrv);
}

// پنجرهٔ سشن مربوط به back روز قبل از روز مرجع (تقویم نیویورک)
bool WindowForDayBack(int back, int startH, int startM, int endH, int endM, datetime refBarTime,
                      datetime &startOut, datetime &endOut, double &hi, double &lo, int &barCount,
                      bool allowOpenWindow=false)
{
   MqlDateTime ref; NYStampOf(refBarTime, ref);
   bool crosses = ((endH*60+endM) <= (startH*60+startM));
   MqlDateTime dayRoot;
   dayRoot.year=ref.year; dayRoot.mon=ref.mon; dayRoot.day=ref.day;
   dayRoot.hour=0; dayRoot.min=0; dayRoot.sec=0;
   datetime nyMidnight = (datetime)((long)StructToTime(dayRoot) - (long)back*86400);
   MqlDateTime nd; TimeToStruct(nyMidnight, nd);
   startOut = NYWallToServer(nd.year, nd.mon, nd.day, startH, startM, 0);
   endOut   = crosses ? NYWallToServer(nd.year, nd.mon, nd.day, endH, endM, 1)
                      : NYWallToServer(nd.year, nd.mon, nd.day, endH, endM, 0);      if(endOut > refBarTime)
      {
         if(!allowOpenWindow) return false;     // پنجره هنوز بسته نشده
         endOut = refBarTime;                   // برای نمایش، فقط تا کندل جاری
      }
      // فاز ۳۰ (#۷۵): اگر کش پنجره از شروع آن قدیمی‌تر نباشد، دادهٔ کافی برای کل
      // پنجره نداریم و رنج به‌دست‌آمده کوچک‌تر از واقعیت می‌شود → رد (fail-safe).
      if(!allowOpenWindow && !WindowFullyCovered(startOut)) return false;
      return CollectWindowRange(InpSessionSourceTF, startOut, endOut, hi, lo, barCount);
}

// آخرین پنجرهٔ سشنی که کامل بسته شده است (قبل از زمان کندل جاری)
bool FindLastClosedWindow(int startH, int startM, int endH, int endM, datetime refBarTime,
                          datetime &startOut, datetime &endOut, double &hi, double &lo)
{
   int cnt=0;
   for(int back=0; back<=9; back++)
   {
      if(WindowForDayBack(back, startH, startM, endH, endM, refBarTime, startOut, endOut, hi, lo, cnt))
         return true;
   }
   return false;
}

//====================================================================
// INIT
//====================================================================
//====================================================================
// فاز ۲۷ — توضیح آموزشی «کلیکی»
//
// کاربر گفت: موس باید آزاد باشد و توضیح نباید خودش بیاید؛ هر خطی که کلیک
// شد توضیحش بیاید. پس مسیر پیش‌فرض حالا CHARTEVENT_CLICK است و هیچ رویداد
// حرکتی موس دریافت/مصرف نمی‌شود (حتی رویداد موس هم فعال نمی‌شود).
//   • کلیک روی خط/باکس  → پنل کامل همان آبجکت
//   • کلیک روی فضای خالی → بستن پنل
//   • کلیک دوباره روی همان آبجکت → بستن پنل (رفت‌وبرگشت)
//   • کلید ESC → بستن پنل
// در حالت EXPLAIN_OPEN_HOVER (اختیاری، پیش‌فرض نیست) رفتار قدیمی برمی‌گردد.
//====================================================================
int OnInit()
{
   // راهنمای یک‌باره — در Journal، نه روی چارت (چارت پیش‌فرض باید تمیز بماند).
   // بدون این خط، کاربر فکر می‌کند آموزش حذف شده است.
   if(InpExplainOpen==EXPLAIN_OPEN_CLICK)
      Print("ICT ASSISTANT v0.1 | توضیح آموزشی: روی هر خط یا باکس کلیک کن تا کامل توضیح بدهد. "
            "کلیک بعدی روی همان آبجکت، یا کلیک روی فضای خالی، پنل را می‌بندد");
   else
      Print("ICT ASSISTANT v0.1 | توضیح آموزشی: حالت بردن موس روی آبجکت فعال است — موس را روی خط یا باکس ببر؛ ورودی مربوطه در گروه توضیحات تنظیمات است");

   // فاز ۱۴: رسم لایه دیگه با ObjectsDeleteAll شروع نمی‌شود، پس registry frozen
   // هم باید روی هر attach/تغییر context از صفر شروع شود (وگرنه نام‌های مرده
   // در آن می‌مانند و reconcile را بی‌دلیل سنگین می‌کنند).
   ArrayResize(g_frozen,0);
   g_frozenSymbol=_Symbol;
   g_frozenPeriod=(ENUM_TIMEFRAMES)Period();
   g_frozenAdded=0; g_frozenEvicted=0; g_frozenRestored=0; g_hiddenDeleted=0;

   // پاک‌سازی آبجکت‌های نسخهٔ قبلی تا tooltip و ردیف‌های قدیمی پنل
   // بعد از reload روی چارت باقی نمانند.
   ObjectsDeleteAll(0, "ICTv13_");

   g_atrHandle = iATR(_Symbol, PERIOD_CURRENT, InpATR_Period);
   if(g_atrHandle==INVALID_HANDLE)
   {
      Print("خطا: ساخت هندل میانگین دامنهٔ واقعی ناموفق بود");
      return INIT_FAILED;
   }

   // فاز ۳۳: ورودی InpBrooks_EMA20_Period و وهندل g_brooksEmaHandle قبلاً «مرده»
   // بودند (نه ساخته می‌شدند و نه خوانده). ۲۰ EMA مرجع رسمی فهرست کاربر است، پس
   // اینجا ساخته می‌شود و در AnalyzeBrooksBar به‌عنوان بافت Always-In استفاده می‌شود.
   g_brooksEmaHandle = iMA(_Symbol, PERIOD_CURRENT, MathMax(2,InpBrooks_EMA20_Period), 0, MODE_EMA, PRICE_CLOSE);
   if(g_brooksEmaHandle==INVALID_HANDLE)
      Print("هشدار: ساخت هندل میانگین متحرک ۲۰ کندلی ناموفق بود؛ وضعیت جهت همیشگی خنثی می‌ماند");

   ArrayResize(g_swingsLTF, 0);
   ArrayResize(g_swingsHTF, 0);
   ArrayResize(g_events, 0);
   ArrayResize(g_liquidity, 0);
   ArrayResize(g_displacements, 0);
   ArrayResize(g_fvgs, 0);
   ArrayResize(g_obs, 0);
   ArrayResize(g_rejections, 0);

   // زنجیره MTF: هر نقش تایم‌فریم خودش را دارد (قابل تنظیم توسط کاربر)
   g_mtfTimeframes[0]=InpTF_Bias;
   g_mtfTimeframes[1]=InpTF_Context1;
   g_mtfTimeframes[2]=InpTF_Context2;
   g_mtfTimeframes[3]=InpTF_Setup;
   g_mtfTimeframes[4]=InpTF_Confirm1;
   g_mtfTimeframes[5]=InpTF_Confirm2;

   // آفست واقعی بروکر (پایهٔ ساعت سشن‌ها و DST)
   g_serverGMTOffsetSeconds = DetectServerGMTOffsetSeconds();
   g_serverGMTOffsetHours   = (int)MathRound((double)g_serverGMTOffsetSeconds/3600.0);
   // فاز ۱۵: قاعدهٔ DST بروکر و آفست استاندارد باید *پیش از* هر تبدیل زمانی
   // معلوم باشند تا ServerToUTC/UTCToServer از همان لحظه درست کار کنند.
   DeriveBrokerDSTRuleAndStdOffset();
   g_brokerOffsetChanges    = 0;
   g_brokerOffsetNote       = "";
   int nyOffsetNowHours = NyOffsetSecondsUTC(ServerToUTC(TimeCurrent()))/3600;
   PrintFormat("ICT Canonical: broker GMT offset = %+d min (%+d h) | NY GMT offset = %+d | broker->NY delta = %+d h (input reference %+d) | NY DST rules = %s | session source TF = %s",
               g_serverGMTOffsetSeconds/60, g_serverGMTOffsetHours, nyOffsetNowHours,
               nyOffsetNowHours-g_serverGMTOffsetHours, InpBrokerToNY_HourOffset,
               InpUseUS_DSTForNYClock?"ON":"OFF", EnumToString(InpSessionSourceTF));
   // فاز ۱۵: شاهد آفست تاریخی — قاعدهٔ DST بروکر از همین‌جا صریح اعلام می‌شود تا
   // بعداً کسی مجبور نباشد از آفست جاری حدس بزند بروکر چه قاعده‌ای دارد.
   PrintFormat("ICT PHASE15 | broker DST rule %s | standard offset %+d min | detected now %+d min | DST now %s | historical offset %s",
               BrokerDSTRuleToStr(g_brokerDSTRule), g_brokerStdOffsetSeconds/60,
               g_serverGMTOffsetSeconds/60, g_brokerDSTActiveNow?"ON":"OFF",
               InpUseHistoricalBrokerOffset?"ENABLED":"DISABLED (current-offset mode)");
   g_historyRebuilt = false;
   g_mtfInternalBucket = 0;      // کش ساختار داخلی InpMTF پس از attach از نو
   g_mtfInternalDir = DIR_NONE;
   g_mtfInternalBarTime = 0;

   // فاز ۱۲ — مهر بارگذاری (شاهد صداقت): تا این‌جا هیچ راه عددی برای فهمیدن
   // «کدام build روی چارت فعال است» نبود و همین باعث شد شاهد کهنه با تازه
   // مقایسه شود. حالا هر attach یک فایل مهر می‌نویسد.
   g_buildStamp=TimeToString(TimeLocal(),TIME_DATE|TIME_MINUTES|TIME_SECONDS);
   PersistLoadStamp();
   if(InpWriteReplayDiagnostics && InpResetReplayDiagnostics)
   {
      FileDelete("ICT_Assistant_Canonical_MTF_Diag.csv",FILE_COMMON);
      FileDelete(ICT_REPLAY_LEDGER,FILE_COMMON);
   }

   // تشخیص خوانایی متن فارسی: کدپوینت‌های واقعیِ رشتهٔ کامپایل‌شده در Journal
   // تست چسبیدن ارقام هگز به \x : حرف فارسی + حرف لاتین هگز (a) باید دو کدپوینت بدهد

   // توجه: از ZeroMemory روی این struct استفاده نمی‌کنیم چون شامل یک فیلد
   // string است (status) و ZeroMemory فقط برای structهای ساده/POD امن است؛
   // پاک‌سازی دستی فیلدها انجام می‌شود.
   g_setup.active = false;
   g_setup.dir = DIR_NONE;
   g_setup.entry = 0; g_setup.sl = 0; g_setup.tp1 = 0; g_setup.tp2 = 0; g_setup.tp3 = 0;
   g_setup.rr = 0;
   g_setup.fvgId = -1; g_setup.obId = -1; g_setup.dolLiqId = -1;
   g_setup.status = "NONE";

   // فاز ۲۷: پیش‌فرض CLICK است و رویداد حرکتی موس **فعال نمی‌شود** تا موس
   // کاملاً آزاد باشد (درگ/زوم چارت هیچ دخالتی نمی‌بیند).
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, InpExplainOpen==EXPLAIN_OPEN_HOVER);
   EventSetTimer(1);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   // فاز ۲۴: اگر اندیکاتور وسط بازسازی جدا شود، هندل‌های شاهد نباید باز بمانند.
   DiagHoldRelease();
   ObjectsDeleteAll(0, "ICTv13_");
   // فاز ۳۳: هندل ۲۰ EMA — هر هندل ساخته‌شده باید آزاد شود.
   if(g_brooksEmaHandle!=INVALID_HANDLE) { IndicatorRelease(g_brooksEmaHandle); g_brooksEmaHandle=INVALID_HANDLE; }
   // فاز ۴۰ — نشت هندل ATR: OnInit روی هر attach یک iATR تازه می‌سازد و تعویض
   // تایم‌فریم = یک OnDeinit + OnInit. بدون آزادسازی، هر بار عوض‌کردن تایم‌فریم
   // یک هندل جا می‌گذارد تا به سقف هندل‌های ترمینال بخورد و کپی‌ها بی‌صدا شکست
   // بخورند (آن‌وقت چارت دیگر پر نمی‌شود). هر هندل ساخته‌شده باید آزاد شود.
   if(g_atrHandle!=INVALID_HANDLE) { IndicatorRelease(g_atrHandle); g_atrHandle=INVALID_HANDLE; }
}

void OnTimer() { /* رزرو برای Alertهای زمان‌بندی‌شده */ }

// --- پیوت تأییدشده روی یک سری که به‌صورت series خوانده شده است ---
// فاز ۲۲ — ایراد محاسباتی واقعی (Double Top / Equal Highs):
// قاعدهٔ استاندارد پیوت (همان چیزی که TradingView در ta.pivothigh/ta.pivotlow
// و اسکریپت‌های Swing/SwingHigh به‌کار می‌برند): کندل پیوت باید از کندل‌های
// سمت **چپ/قدیمی‌تر** اکیداً بزرگ‌تر و از کندل‌های سمت **راست/جدیدتر** بزرگ‌تر
// یا مساوی باشد (تساوی فقط از یک طرف پذیرفته می‌شود تا سقف‌های مساوی یک پیوت
// بدهند، نه صفر پیوت).
// قبلاً هر دو طرف اکید بودند؛ یعنی یک Double Top با دو سقف **دقیقاً مساوی**
// هیچ پیوتی نمی‌ساخت → نه سقف محافظت‌شده، نه BSL و نه EQH. همان‌جا هم پیوت
//‌های H4 برای Bias گم می‌شدند. حالا راست/جدیدتر مساوی‌پذیر شد.
// منبع قاعده: مستندات/شهرت اسکریپت SwingHigh — «greater than or equal to the
// highs of the bars that follow it, strictly greater than the highs of the bars
// before it» (کندل‌های "before" = قدیمی‌تر = سمت چپ).
bool PivotHighAt(const MqlRates &rates[], int shift)
{
   for(int side=1; side<=InpSwingLeft; side++)
      if(rates[shift].high<=rates[shift+side].high) return false;      // چپ/قدیمی: اکید
   for(int side=1; side<=InpSwingRight; side++)
      if(shift-side<0 || rates[shift].high<rates[shift-side].high) return false;  // راست/جدید: مساوی‌پذیر
   return true;
}

bool PivotLowAt(const MqlRates &rates[], int shift)
{
   for(int side=1; side<=InpSwingLeft; side++)
      if(rates[shift].low>=rates[shift+side].low) return false;        // چپ/قدیمی: اکید
   for(int side=1; side<=InpSwingRight; side++)
      if(shift-side<0 || rates[shift].low>rates[shift-side].low) return false;    // راست/جدید: مساوی‌پذیر
   return true;
}

// ساختار داخلی یک تایم‌فریم مشخص، «همان‌طور که در زمان asOf دیده می‌شد».
// برخلاف ساختار خارجی که کل تاریخچه را می‌بیند، اینجا فقط پنجرهٔ کوتاه اخیر
// مبنای جهت است. مصرف‌کننده: ورودی InpMTF (رفع #۶۱ — نقش واقعی).
ENUM_DIRECTION InternalDirectionAsOf(datetime asOf, ENUM_TIMEFRAMES tf, datetime &barTimeOut)
{
   barTimeOut=0;
   // کش در سطح باکت همان تایم‌فریم: بازسازی تاریخچه صدها کندل LTF را پشت سر
   // می‌گذارد ولی تعداد باکت‌های InpMTF بسیار کمتر است، پس این کش هزینهٔ
   // CopyRates را از «هر کندل چارت» به «هر کندل InpMTF» کاهش می‌دهد.
   int tfSec=PeriodSeconds(tf);
   if(tfSec<=0) tfSec=PeriodSeconds(PERIOD_CURRENT);
   if(tfSec<=0) tfSec=60;
   datetime bucket=(datetime)(((long)asOf/(long)tfSec)*(long)tfSec);
   if(bucket==g_mtfInternalBucket)
   {
      barTimeOut=g_mtfInternalBarTime;
      return g_mtfInternalDir;
   }
   g_mtfInternalBucket=bucket;
   MqlRates rates[];
   int copied=CopyRatesAsOf(_Symbol,tf,asOf,240,rates);
   int total=ArraySize(rates);
   if(copied<InpSwingLeft+InpSwingRight+12) return DIR_NONE;
   barTimeOut=rates[0].time;
   SwingPoint highs[], lows[];
   int window=InpSwingLeft+InpSwingRight+20;
   for(int shift=total-InpSwingLeft-1; shift>=InpSwingRight; shift--)
   {
      if(shift>=window) continue;
      if(PivotHighAt(rates,shift))
      {
         SwingPoint p; p.time=rates[shift].time; p.price=rates[shift].high;
         p.isHigh=true; p.confirmed=true; p.broken=false; p.id=0;
         int n=ArraySize(highs); ArrayResize(highs,n+1); highs[n]=p;
      }
      if(PivotLowAt(rates,shift))
      {
         SwingPoint p; p.time=rates[shift].time; p.price=rates[shift].low;
         p.isHigh=false; p.confirmed=true; p.broken=false; p.id=0;
         int n=ArraySize(lows); ArrayResize(lows,n+1); lows[n]=p;
      }
   }
   return DirectionFromConfirmedSwings(highs,lows);
}

ENUM_DIRECTION DirectionFromConfirmedSwings(SwingPoint &highs[], SwingPoint &lows[])
{
   int hc=ArraySize(highs), lc=ArraySize(lows);
   if(hc<2 || lc<2) return DIR_NONE;
   bool higherHigh=highs[hc-1].price>highs[hc-2].price;
   bool higherLow=lows[lc-1].price>lows[lc-2].price;
   bool lowerHigh=highs[hc-1].price<highs[hc-2].price;
   bool lowerLow=lows[lc-1].price<lows[lc-2].price;
   if(higherHigh && higherLow) return DIR_BULL;
   if(lowerHigh && lowerLow) return DIR_BEAR;
   return DIR_NONE;
}

void AnalyzeMTFContext(datetime barTime)
{
   g_mtfConflict=false;
   g_mtfConflictReason="";
   for(int index=0; index<6; index++)
   {
      g_mtfContext[index].timeframe=g_mtfTimeframes[index];
      g_mtfContext[index].externalDirection=DIR_NONE;
      g_mtfContext[index].internalDirection=DIR_NONE;
      g_mtfContext[index].confirmedBarTime=0;
      g_mtfContext[index].protectedHigh=0.0;
      g_mtfContext[index].protectedLow=0.0;
      g_mtfContext[index].role=index==0?"BIAS":index<3?"CONTEXT":index==3?"SETUP":"CONFIRMATION";

      // داده «همان‌طور که در زمان این کندل دیده می‌شد» (بدون نگاه به آینده)
      MqlRates rates[];
      int copied=CopyRatesAsOf(_Symbol,g_mtfTimeframes[index],barTime,240,rates);
      if(copied<InpSwingLeft+InpSwingRight+12) continue;
      g_mtfContext[index].confirmedBarTime=rates[0].time;
      SwingPoint highs[], lows[], internalHighs[], internalLows[];
      int total=ArraySize(rates);
      // CopyRatesAsOf returns a series: shift 0 is newest. Build registries
      // from oldest to newest so the last element is the latest confirmed swing.
      for(int shift=total-InpSwingLeft-1; shift>=InpSwingRight; shift--)
      {
         bool high=true, low=true;
         for(int side=1; side<=InpSwingLeft; side++)
         {
            if(rates[shift].high<=rates[shift+side].high) high=false;   // چپ/قدیمی: اکید
            if(rates[shift].low>=rates[shift+side].low) low=false;
         }
         for(int side=1; side<=InpSwingRight; side++)
         {
            // راست/جدید: مساوی‌پذیر (هم‌قاعده با PivotHighAt — فاز ۲۲)
            if(shift-side<0 || rates[shift].high<rates[shift-side].high) high=false;
            if(shift-side<0 || rates[shift].low>rates[shift-side].low) low=false;
         }
         if(high)
         {
            SwingPoint point; point.time=rates[shift].time; point.price=rates[shift].high; point.isHigh=true; point.confirmed=true; point.broken=false; point.id=0;
            int n=ArraySize(highs); ArrayResize(highs,n+1); highs[n]=point;
            if(shift<InpSwingLeft+InpSwingRight+20){n=ArraySize(internalHighs);ArrayResize(internalHighs,n+1);internalHighs[n]=point;}
         }
         if(low)
         {
            SwingPoint point; point.time=rates[shift].time; point.price=rates[shift].low; point.isHigh=false; point.confirmed=true; point.broken=false; point.id=0;
            int n=ArraySize(lows); ArrayResize(lows,n+1); lows[n]=point;
            if(shift<InpSwingLeft+InpSwingRight+20){n=ArraySize(internalLows);ArrayResize(internalLows,n+1);internalLows[n]=point;}
         }
      }
      g_mtfContext[index].externalDirection=DirectionFromConfirmedSwings(highs,lows);
      g_mtfContext[index].internalDirection=DirectionFromConfirmedSwings(internalHighs,internalLows);
      if(ArraySize(highs)>0) g_mtfContext[index].protectedHigh=highs[ArraySize(highs)-1].price;
      if(ArraySize(lows)>0) g_mtfContext[index].protectedLow=lows[ArraySize(lows)-1].price;
   }
   // ===== MTF hierarchy: مالک Bias فقط H4 است =====
   // هیچ تایم‌فریم پایین‌تری اجازه ندارد Bias را عوض کند؛ فقط می‌تواند
   // Context را تایید کند یا ستاپ را رد کند (رد شدن = مسدود شدن READY).
   // مالک canonical Bias مقدار g_htfBias است (BOS/CHoCH روی H4، بدون repaint،
   // همان که زنجیرهٔ ستاپ و DOL و داشبورد استفاده می‌کنند). خوانش HH/HL نرم‌تر
   // mtfContext[0].externalDirection فقط context است؛ برای اینکه تشخیص تضاد،
   // زنجیرهٔ ستاپ و ستون تشخیص همه یک مقدار واحد را ببینند، مالک را روی
   // g_htfBias قفل می‌کنیم تا تناقض «BiasOwner=BULLISH ولی WAITING_H4_BIAS» حذف شود.
   ENUM_DIRECTION bias=g_htfBias;
   string biasName=EnumToString(g_mtfTimeframes[0]);
   if(bias!=DIR_NONE)
   {
      for(int index=1; index<6; index++)
      {
         if(g_mtfContext[index].externalDirection!=DIR_NONE && g_mtfContext[index].externalDirection!=bias)
         {
            g_mtfConflict=true;
            g_mtfConflictReason=StringFormat("%s conflicts with bias owner %s - lower timeframe cannot change bias (READY blocked)",
                                             EnumToString(g_mtfTimeframes[index]), biasName);
            break;
         }
      }
      // تأییدهای اجرایی: ناسازگاری M2/M1 هم READY را مسدود می‌کند ولی Bias را عوض نمی‌کند
      if(!g_mtfConflict)
      {
         for(int index=4; index<6; index++)
         {
            if(g_mtfContext[index].internalDirection!=DIR_NONE && g_mtfContext[index].internalDirection!=bias)
            {
               g_mtfConflict=true;
               g_mtfConflictReason=StringFormat("%s execution not aligned with bias owner %s - READY blocked",
                                                EnumToString(g_mtfTimeframes[index]), biasName);
               break;
            }
         }
      }
   }
   else
   {
      g_mtfConflict=true;
      g_mtfConflictReason=StringFormat("bias owner %s not confirmed yet",biasName);
   }
}

//====================================================================
// SWING DETECTION — No-Repaint: فقط وقتی InpSwingRight کندل بعدی تشکیل
// شد Pivot را "Confirmed" می‌کنیم (رفع ایراد ۱۹: Developing != Confirmed)
//====================================================================
bool IsConfirmedPivotHigh(const double &high[], int shift, int left, int right, int total)
{
   if(shift-right < 0 || shift+left >= total) return false;
   double v = high[shift];
   for(int i=1;i<=left;i++)  if(high[shift+i] >= v) return false;
   for(int i=1;i<=right;i++) if(high[shift-i] >= v) return false;
   return true;
}
bool IsConfirmedPivotLow(const double &low[], int shift, int left, int right, int total)
{
   if(shift-right < 0 || shift+left >= total) return false;
   double v = low[shift];
   for(int i=1;i<=left;i++)  if(low[shift+i] <= v) return false;
   for(int i=1;i<=right;i++) if(low[shift-i] <= v) return false;
   return true;
}

void PushSwing(SwingPoint &arr[], SwingPoint &s, int maxCount)
{
   int n = ArraySize(arr);
   // جلوگیری از تکرار روی همان زمان
   for(int i=0;i<n;i++) if(arr[i].time==s.time && arr[i].isHigh==s.isHigh) return;
   ArrayResize(arr, n+1);
   arr[n] = s;
   if(ArraySize(arr) > maxCount)
   {
      for(int i=0;i<ArraySize(arr)-1;i++) arr[i]=arr[i+1];
      ArrayResize(arr, maxCount);
   }
}

//====================================================================
// UNIFIED STRUCTURE ENGINE — رفع ایراد ۱: BOS/CHoCH/MSS سه Event
// جداگانه، از یک تابع واحد اما با منطق تفکیک‌شده تصمیم‌گیری می‌شوند:
//
//   BOS   = شکست سویینگ در همان جهت روند جاری (ادامه‌دهنده)
//   CHoCH = شکست اولین سویینگ خلاف جهت روند جاری (تغییر احتمالی)
//   MSS   = CHoCH که با Displacement معتبر تایید شده (تغییر ساختار قطعی)
//
// این‌ها یک بولین نیستند؛ سه شرط متفاوت با state متفاوت.
//====================================================================
ENUM_DIRECTION g_ltfTrendDir = DIR_NONE;

//====================================================================
// فاز ۱۳ (#۱۱): تنها مسیر افزودن رویداد ساختاری = سقف + سیاست حذف FIFO
//
// چرا FIFO امن است (اثبات، نه حدس):
//   * Bias و سطح محافظت‌شده: آخرین رویداد HTF از انتهای آرایه خوانده می‌شوند
//   * زنجیرهٔ ستاپ: پنجرهٔ InpChainLookbackBars = فقط رویدادهای تازه
//   * سن/فاز روند: آخرین رویداد همراستا از انتها
//   پس حذف قدیمی‌ترین‌ها هیچ خروجی زنده‌ای را تغییر نمی‌دهد و فقط حافظه را
//   کران‌دار می‌کند. اگر روزی مصرف‌کننده‌ای به رویداد «قدیمی» نیاز پیدا کند،
//   باید تاریخچهٔ کامل رویدادها از دفتر CSV خوانده شود، نه از رم.
//====================================================================
void AppendStructureEvent(const StructureEvent &e)
{
   int m=ArraySize(g_events);
   ArrayResize(g_events,m+1);
   g_events[m]=e;
   g_eventsAdded++;
   if(InpMaxEvents>0 && ArraySize(g_events)>InpMaxEvents)
   {
      int drop=ArraySize(g_events)-InpMaxEvents;
      int keep=ArraySize(g_events)-drop;
      for(int i=0;i<keep;i++) g_events[i]=g_events[i+drop];
      ArrayResize(g_events,InpMaxEvents);
      g_eventsDropped+=drop;
   }
}

void EvaluateStructureBreak(const double &close[], int shift, bool isHTF,
                             SwingPoint &swings[], ENUM_DIRECTION &trendDir,
                             const long dispCandidateId, const long liquidityCandidateId,
                             datetime confirmationTime)
{
   int n = ArraySize(swings);
   if(n<1) return;
   double c = close[shift];

   // آخرین سویینگ‌های شکسته‌نشده در هر جهت
   int lastHighIdx=-1, lastLowIdx=-1;
   for(int i=n-1;i>=0;i--)
   {
      if(swings[i].broken) continue;
      if(swings[i].isHigh && lastHighIdx==-1) lastHighIdx=i;
      if(!swings[i].isHigh && lastLowIdx==-1) lastLowIdx=i;
      if(lastHighIdx!=-1 && lastLowIdx!=-1) break;
   }

   // شکست سقف
   if(lastHighIdx!=-1 && c > swings[lastHighIdx].price)
   {
      ENUM_EVENT_TYPE t;
      // BOS سیگنال «ادامهٔ روند» است. بدون روند صعودیِ تأییدشده، برچسب BOS
      // صادر نمی‌شود؛ شکست بدون روند قبلی = CHoCH (تغییر اولیه) (#۴).
      if(trendDir==DIR_BULL) t = EVT_BOS;
      else t = EVT_CHOCH;

      StructureEvent e;
      // فاز ۱۳ (#۱۲): تولیدکنندهٔ شناسهٔ ترتیبی که بلافاصله با StableEventId
      // بازنویسی می‌شد، کد مرده بود و حذف شد؛ شناسهٔ نهایی فقط از
      // StableEventId می‌آید (اثبات grep-دار: هیچ ارجاعی به آن نام‌ها نمانده).
      e.type = t;
      e.direction = DIR_BULL;
      e.time = confirmationTime;
      e.price = swings[lastHighIdx].price;
      e.brokenSwingId = swings[lastHighIdx].id;
      // Protected swing = آخرین لو تاییدشده قبل از این شکست (نه فقط "آخرین پیوت")
      e.protectedSwingId = (lastLowIdx!=-1)? swings[lastLowIdx].id : -1;
      e.confirmationBarShift = shift;
      e.displacementId = dispCandidateId; // اگر با دیسپلیسمنت هم‌زمان بود، وصل می‌شود، وگرنه -1
      e.sweepId = liquidityCandidateId;
      e.parentEventId = -1;
      e.isHTF = isHTF;

      // فاز ۲۹ (#۷۲): CHoCH **همیشه** جهت مالک را عوض می‌کند.
      // منبع: LuxAlgo — Market Structure: «BOS فقط بعد از CHoCH می‌تواند رخ دهد»
      // و CHoCH = نشانهٔ برگشت. پیش‌تر جهت فقط در حالت BOS یا MSS عوض می‌شد؛
      // پس CHoCH بدون Sweep+Displacement هم‌زمان — و **همهٔ** CHoCHهای HTF که
      // disp/liq آن‌ها ثابت -1 است — جهت را دست‌نخورده می‌گذاشت و Bias عملاً
      // قفل می‌شد: از آن پس هر شکست بعدی هم برچسب CHoCH می‌گرفت، هیچ‌وقت BOS
      // نمی‌شد، و Bias فقط با نخستین شکست تاریخ تعیین می‌ماند.
      if(t==EVT_CHOCH && dispCandidateId!=-1 && liquidityCandidateId!=-1)
         e.type = EVT_MSS;      // ارتقای برچسب؛ عوض‌شدن جهت مشترک است
      trendDir = DIR_BULL;
      e.isHTF = isHTF;
      e.id = StableEventId(e.time,e.type,e.direction,e.brokenSwingId,e.isHTF);

      swings[lastHighIdx].broken = true;
      AppendStructureEvent(e);

      // فاز ۱۳ (کارایی): در حالت بازسازی، رسم بی‌فایده است چون انتهای
      // بازسازی لایه از Registry از نو ساخته می‌شود.
      if(!isHTF && !g_rebuildMode) DrawStructureEvent(e);
   }

   // شکست کف (قرینه)
   if(lastLowIdx!=-1 && c < swings[lastLowIdx].price)
   {
      ENUM_EVENT_TYPE t;
      // قرینه: BOS فقط در ادامهٔ روند نزولیِ تأییدشده (#۴).
      if(trendDir==DIR_BEAR) t = EVT_BOS;
      else t = EVT_CHOCH;

      StructureEvent e;
      // فاز ۱۳ (#۱۲): تولیدکنندهٔ شناسهٔ ترتیبی که بلافاصله با StableEventId
      // بازنویسی می‌شد، کد مرده بود و حذف شد؛ شناسهٔ نهایی فقط از
      // StableEventId می‌آید (اثبات grep-دار: هیچ ارجاعی به آن نام‌ها نمانده).
      e.type = t;
      e.direction = DIR_BEAR;
      e.time = confirmationTime;
      e.price = swings[lastLowIdx].price;
      e.brokenSwingId = swings[lastLowIdx].id;
      e.protectedSwingId = (lastHighIdx!=-1)? swings[lastHighIdx].id : -1;
      e.confirmationBarShift = shift;
      e.displacementId = dispCandidateId;
      e.sweepId = liquidityCandidateId;
      e.parentEventId = -1;
      e.isHTF = isHTF;

      // قرینهٔ شاخهٔ سقف (فاز ۲۹ / #۷۲): CHoCH جهت مالک را عوض می‌کند.
      if(t==EVT_CHOCH && dispCandidateId!=-1 && liquidityCandidateId!=-1)
         e.type = EVT_MSS;      // ارتقای برچسب؛ عوض‌شدن جهت مشترک است
      trendDir = DIR_BEAR;
      e.isHTF = isHTF;
      e.id = StableEventId(e.time,e.type,e.direction,e.brokenSwingId,e.isHTF);

      swings[lastLowIdx].broken = true;
      AppendStructureEvent(e);

      if(!isHTF && !g_rebuildMode) DrawStructureEvent(e);
   }
}

//====================================================================
// LIQUIDITY REGISTRY ENGINE — رفع ایراد ۵ و ۶
//====================================================================
long AddLiquidity(ENUM_LIQ_TYPE type, ENUM_LIQ_SCOPE scope, double price, datetime t, bool isHTF)
{
   int n = ArraySize(g_liquidity);
   // جلوگیری از دابل ثبت نزدیک هم برای همان نوع
   for(int i=0;i<n;i++)
   {
      if(g_liquidity[i].type==type && g_liquidity[i].isHTF==isHTF &&
         g_liquidity[i].time==t &&
         MathAbs(g_liquidity[i].price-price) < PointsToPrice(InpEQ_Tolerance_Points))
         return g_liquidity[i].id;
   }
   LiquidityObj o;
   o.id = StableLiquidityId(t,type,price,isHTF); o.type=type; o.scope=scope; o.state=LSTATE_FRESH;
   o.price=price; o.time=t; o.sweptTime=0; o.sweptByEventId=-1; o.isHTF=isHTF;
   ArrayResize(g_liquidity, n+1);
   g_liquidity[n]=o;
   if(n+1 > InpMaxLiquidity)
   {
      for(int i=0;i<ArraySize(g_liquidity)-1;i++) g_liquidity[i]=g_liquidity[i+1];
      ArrayResize(g_liquidity, InpMaxLiquidity);
   }
   return o.id;
}

// نوع Liquidity در سمت بالا (Buy-Side) یا پایین (Sell-Side)
bool IsHighSideLiquidity(ENUM_LIQ_TYPE type)
{
   return (type==LIQ_PDH || type==LIQ_PWH || type==LIQ_EQH ||
           type==LIQ_SWING_H || type==LIQ_SESSION_H ||
           // فاز ۱۲ (#۲۰ #۶۵)
           type==LIQ_RANGE_H || type==LIQ_IPDA20_H ||
           type==LIQ_IPDA40_H || type==LIQ_IPDA60_H ||
           // فاز ۳۰ (#۷۶): نقدینگی مورب سمت Buy
           type==LIQ_TRENDLINE_H);
}

//--------------------------------------------------------------------
// فاز ۳۰ (#۷۵): پنجرهٔ هفتهٔ گذشته با لنگر ساعت نیویورک (دوشنبه‌محور).
// همان روش بسته‌بندی تاریخ نیویورک در WindowForDayBack استفاده می‌شود تا جمع
// و تفریق روز مستقل از DST درست بماند؛ تبدیل نهایی به وقت سرور با
// NYWallToServer (که DST نیویورک را در همان تاریخ لحاظ می‌کند) انجام می‌شود.
//--------------------------------------------------------------------
bool WeekWindowBack(int anchorH, datetime refBarTime, datetime &startOut, datetime &endOut,
                    double &hi, double &lo, int &barCount)
{
   MqlDateTime ref;
   NYStampOf(refBarTime, ref);
   MqlDateTime dr;
   dr.year=ref.year; dr.mon=ref.mon; dr.day=ref.day;
   dr.hour=0; dr.min=0; dr.sec=0; dr.day_of_week=0; dr.day_of_year=0;
   long packed=(long)StructToTime(dr);
   int dow=ref.day_of_week;                    // 0 = یکشنبه
   int toMonday=(dow==0)? 6 : (dow-1);         // دوشنبهٔ همان هفتهٔ نیویورک
   long mondayPacked=packed-(long)toMonday*86400;

   for(int back=1; back<=3; back++)
   {
      MqlDateTime m1, m2;
      TimeToStruct((datetime)(mondayPacked-(long)back*7*86400), m1);
      TimeToStruct((datetime)(mondayPacked-(long)(back-1)*7*86400), m2);
      startOut=NYWallToServer(m1.year,m1.mon,m1.day,anchorH,0,0);
      endOut  =NYWallToServer(m2.year,m2.mon,m2.day,anchorH,0,0);
      if(startOut<=0 || endOut<=startOut) continue;
      if(endOut>refBarTime) continue;                // هفته هنوز بسته نشده
      if(!WindowFullyCovered(startOut)) continue;    // دادهٔ کافی برای کل پنجره نیست
      if(CollectWindowRange(InpSessionSourceTF,startOut,endOut,hi,lo,barCount)) return true;
   }
   return false;
}

// PDH/PDL/PWH/PWL بر مبنای «مرز روز/هفته».
// (قبلاً با iHigh(...,1) و TimeCurrent محاسبه می‌شد که در بازپخش و در DST
//  مقدار اشتباه می‌داد — همان ایراد قدیمی.)
// فاز ۳۰ (#۷۵): مرز پیش‌فرض حالا نیمه‌شب نیویورک است (منبع در توضیح ورودی
// InpPD_Anchor) و مرز کندل بروکر فقط اگر کاربر خودش انتخاب کند استفاده می‌شود.
void UpdateLiquidityRegistry_PDH_PDL_PWH_PWL(datetime barTime)
{
   double pdh=0, pdl=0, pwh=0, pwl=0;
   datetime tD=0, tW=0;

   if(InpPD_Anchor==PD_ANCHOR_BROKER_DAY)
   {
      if(PreviousClosedBucket(barTime, PERIOD_D1, pdh, pdl, tD))
      {
         if(pdh>0) AddLiquidity(LIQ_PDH, SCOPE_EXTERNAL, pdh, tD, true);
         if(pdl>0) AddLiquidity(LIQ_PDL, SCOPE_EXTERNAL, pdl, tD, true);
      }
      if(PreviousClosedBucket(barTime, PERIOD_W1, pwh, pwl, tW))
      {
         if(pwh>0) AddLiquidity(LIQ_PWH, SCOPE_EXTERNAL, pwh, tW, true);
         if(pwl>0) AddLiquidity(LIQ_PWL, SCOPE_EXTERNAL, pwl, tW, true);
      }
      return;
   }

   int anchorH=(InpPD_Anchor==PD_ANCHOR_NY_1700)? 17 : 0;
   int cnt=0;
   bool gotDay=false;
   for(int back=1; back<=3 && !gotDay; back++)
   {
      if(!WindowForDayBack(back, anchorH,0, anchorH,0, barTime, tD, tW, pdh, pdl, cnt))
         continue;
      if(!WindowFullyCovered(tD)) continue;
      gotDay=true;
   }
   if(gotDay)
   {
      if(pdh>0) AddLiquidity(LIQ_PDH, SCOPE_EXTERNAL, pdh, tD, true);
      if(pdl>0) AddLiquidity(LIQ_PDL, SCOPE_EXTERNAL, pdl, tD, true);
   }

   if(WeekWindowBack(anchorH, barTime, tW, tD, pwh, pwl, cnt))
   {
      if(pwh>0) AddLiquidity(LIQ_PWH, SCOPE_EXTERNAL, pwh, tW, true);
      if(pwl>0) AddLiquidity(LIQ_PWL, SCOPE_EXTERNAL, pwl, tW, true);
   }
}

// EQH/EQL از سویینگ‌های LTF -> رفع ایراد ۶: هرکدام یک Object با متادیتای کامل
// EQH/EQL: خوشه‌بندی سوئینگ‌های هم‌سطح (نه یک آبجکت برای هر جفت)
// فاز ۳۰ (#۷۷) — «جدایی معنادار» بین دو عضو یک خوشهٔ EQH/EQL.
// منبع (LuxAlgo — Equal Highs/lows As Liquidity، مرحلهٔ ۲): «Require separation:
// a meaningful pullback between the swings, so they read as distinct tests rather
// than one drawn-out top»؛ و توصیف استاندارد پیاده‌سازی‌ها: «two **consecutive**
// pivots form within a user-defined price threshold» — یعنی دو پیوت هم‌نوع که یک
// پیوت مخالف بین‌شان نشسته باشد. بدون این شرط، چند سقف پشت‌سرهم در یک چرخش
// کند «یک سقف کشیده» بودند ولی به‌عنوان استخر نقدینگی ثبت می‌شدند.
// عمق لازم = max(تلورانس، InpEQ_MinSeparationATR × ATR).
bool HasPullbackBetween(SwingPoint &swings[], int i, int j, bool isHigh, double tol, double atrValue)
{
   if(InpEQ_MinSeparationATR<=0.0 && tol<=0.0) return true;   // شرط جدایی خاموش است
   double need=tol;
   if(atrValue>0.0 && InpEQ_MinSeparationATR>0.0)
      need=MathMax(tol, atrValue*InpEQ_MinSeparationATR);
   for(int k=i+1;k<j;k++)
   {
      if(swings[k].isHigh==isHigh) continue;                    // فقط سویینگ مخالف = پس‌رفت
      double depth = isHigh ? (swings[i].price-swings[k].price)  // کفِ پس‌رفت زیر سقف لنگر
                            : (swings[k].price-swings[i].price); // سقفِ پس‌رفت بالای کف لنگر
      if(depth>=need) return true;
   }
   return false;
}

void DetectEQ_FromSwings(SwingPoint &swings[], double atrValue)
{
   int n = ArraySize(swings);
   if(n<2) return;
   // تلورانس EQ باید با نوسان بازار مقیاس بخورد، نه پوینت ثابت؛ ۱۵ پوینت روی
   // XAUUSD پرمومنت تقریباً صفر است و روی جفت‌ارز آرام بیش‌ازحد (#۱۴).
   double tol = PointsToPrice(InpEQ_Tolerance_Points);
   if(atrValue>0.0 && InpEQ_ToleranceATR>0.0)
      tol = MathMax(tol, atrValue*InpEQ_ToleranceATR);

   // فاز ۱۳ (کارایی): این تابع در هر کندل بسته روی تا InpMaxSwings=۳۰۰ سوئینگ
   // اجرا می‌شد (O(n²) واقعی). حالا اگر مجموعهٔ سوئینگ‌ها و تلورانس عوض نشده
   // باشد، نتیجه از نو ساخته نمی‌شود.
   //
   // چرا حذف فراخوانی تکراری هیچ سطحی را کم نمی‌کند (اثبات، نه حدس): تابع
   // idempotent است — برای هر گروه، AddLiquidity با همان (نوع، isHTF، زمان،
   // قیمت) صدا زده می‌شود و شرط dedup خودش آن را رد می‌کند. پس اجرای دوم و
   // سوم و ... مجموعهٔ g_liquidity را تغییر نمی‌دهد.
   //
   // اثر انگشت مجموعه = (تعداد، شناسه و زمان آخرین سوئینگ، تلورانس). تنها
   // تغییری که PushSwing می‌تواند بسازد افزودن به انتهای آرایه یا حذف از
   // ابتدای آن (سقف) است؛ هر دو این اثر انگشت را عوض می‌کنند.
   if(n==g_eqStampCount && g_eqStampLastId==swings[n-1].id &&
      g_eqStampLastTime==swings[n-1].time && g_eqStampTol==tol)
   {
      g_eqSkips++;
      return;
   }
   g_eqStampCount=n; g_eqStampLastId=swings[n-1].id;
   g_eqStampLastTime=swings[n-1].time; g_eqStampTol=tol;

   bool used[];
   ArrayResize(used, n);
   for(int i=0;i<n;i++) used[i]=false;

   for(int i=0;i<n;i++)
   {
      if(used[i]) continue;
      bool isHigh = swings[i].isHigh;
      // فاز ۳۰ (#۷۷): تلورانس نسبت به **لنگر خوشه** سنجیده می‌شود، نه نسبت به
      // اکسترِمی که در حال حرکت است. دلیل (منبع، همان صفحه): «two or more swing
      // highs stalling **within a few ticks of one another**» و «draw a band
      // covering the slightly uneven extremes». با مقایسهٔ زنجیره‌ای قبلی، یک
      // نردبان نزولی از سقف‌ها (۱۰۰٫۰ / ۱۰۰٫۵ / ۱۰۱٫۰ با تلورانس ۰٫۶) یک خوشهٔ
      // EQH واحد می‌ساخت که دو سر آن ۱٫۰ دلار فاصله داشت — یعنی استخری که وجود
      // ندارد. حالا بیرون‌رفتن از باند لنگر، خوشه را تمام می‌کند.
      double anchor = swings[i].price;
      double extreme = anchor;
      datetime lastTime = swings[i].time;
      int members = 1;
      for(int j=i+1;j<n;j++)
      {
         if(swings[j].isHigh!=isHigh) continue;
         if(MathAbs(swings[j].price-anchor) > tol) break;   // بیرون از باند لنگر ⇒ خوشه تمام شد
         if(used[j]) continue;
         // فاز ۳۰ (#۷۷): دو عضو باید با یک پس‌رفت معنادار از هم جدا باشند،
         // وگرنه «یک سقف کشیده» هستند، نه دو تست مستقل (منبع در ورودی).
         if(!HasPullbackBetween(swings, i, j, isHigh, tol, atrValue)) continue;
         used[j]=true;
         members++;
         if(isHigh) extreme = MathMax(extreme, swings[j].price);
         else       extreme = MathMin(extreme, swings[j].price);
         lastTime = swings[j].time;
      }
      if(members>=2)
      {
         used[i]=true;
         AddLiquidity(isHigh?LIQ_EQH:LIQ_EQL, SCOPE_INTERNAL, extreme, lastTime, false);
      }
   }
}

// هر Swing تاییدشده به‌عنوان Swing Liquidity هم ثبت می‌شود
void RegisterSwingLiquidity(const SwingPoint &s, bool isHTF)
{
   AddLiquidity(s.isHigh?LIQ_SWING_H:LIQ_SWING_L,
                isHTF?SCOPE_EXTERNAL:SCOPE_INTERNAL,
                s.price, s.time, isHTF);
}

//====================================================================
// SWEEP ENGINE — رفع ایراد ۵: Sweep Engine حالا با Registry واحد کار
// می‌کند، پس هر نوع Liquidity (نه فقط ۶ نوع قدیمی) قابل Sweep شدن است
//====================================================================
// توجه: Sweep باید مستقل از وجود Displacement تشخیص داده شود (wick فراتر از
// سطح + بسته‌شدن برگشتی کافی است). ارتباط Sweep با Displacement/Event بعداً
// و جداگانه (در LinkDisplacementToEvent) به‌عنوان زنجیره Causal ثبت می‌شود؛
// این تفکیک باعث نمی‌شود که به‌خاطر نبود یک Displacement بزرگ، Sweepهای
// واقعی از قلم بیفتند.
long DetectSweep(double barHigh, double barLow, double barClose, datetime t, ENUM_DIRECTION &outSweepDir)
{
   int n = ArraySize(g_liquidity);
   outSweepDir = DIR_NONE;
   // اولویت با نزدیک‌ترین سطح به قیمت جاری (تا اگر چند سطح هم‌زمان جارو شدند
   // منطقی‌ترین یکی انتخاب شود)
   long bestId=-1; double bestDist=1e18; ENUM_DIRECTION bestDir=DIR_NONE;
   for(int i=0;i<n;i++)
   {
      if(g_liquidity[i].state != LSTATE_FRESH) continue;
      if(g_liquidity[i].time == 0 || g_liquidity[i].time > t) continue; // سطح باید قبل از این کندل موجود باشد
      bool isHighType = IsHighSideLiquidity(g_liquidity[i].type);
      // Sweep بالا: قیمت از سطح بالاتر می‌رود ولی کندل زیر آن بسته می‌شود (BSL swept -> نزولی)
      if(isHighType && barHigh > g_liquidity[i].price && barClose < g_liquidity[i].price)
      {
         double dist = MathAbs(barHigh - g_liquidity[i].price);
         if(dist < bestDist){ bestDist=dist; bestId=g_liquidity[i].id; bestDir=DIR_BEAR; }
      }
      // Sweep پایین: قیمت از سطح پایین‌تر می‌رود ولی کندل بالای آن بسته می‌شود (SSL swept -> صعودی)
      if(!isHighType && barLow < g_liquidity[i].price && barClose > g_liquidity[i].price)
      {
         double dist = MathAbs(barLow - g_liquidity[i].price);
         if(dist < bestDist){ bestDist=dist; bestId=g_liquidity[i].id; bestDir=DIR_BULL; }
      }
   }
   if(bestId!=-1)
   {
      // یک کندل می‌تواند چند سطح را هم‌زمان جارو کند (مثلاً EQH + PDH + سقف سشن).
      // همهٔ آن سطوح ثبت می‌شوند؛ شناسهٔ برگشتی فقط سطح اصلی (نزدیک‌ترین)
      // است تا زنجیرهٔ رویداد یک مالک داشته باشد (#۱۷).
      for(int i=0;i<n;i++)
      {
         if(g_liquidity[i].state != LSTATE_FRESH) continue;
         if(g_liquidity[i].time == 0 || g_liquidity[i].time > t) continue;
         bool isHighType = IsHighSideLiquidity(g_liquidity[i].type);
         bool sweptHere =
            (isHighType  && barHigh > g_liquidity[i].price && barClose < g_liquidity[i].price) ||
            (!isHighType && barLow  < g_liquidity[i].price && barClose > g_liquidity[i].price);
         if(sweptHere){ g_liquidity[i].state=LSTATE_SWEPT; g_liquidity[i].sweptTime=t; }
      }
      outSweepDir = bestDir;
   }
   return bestId;
}

//====================================================================
// DISPLACEMENT ENGINE — رفع ایراد ۸: علاوه بر انرژی کندل، باید به یک
// Event/Liquidity وصل شود تا "Displacement ICT" اثبات‌شده حساب شود.
//====================================================================
long DetectDisplacementCandidate(const double &open[], const double &high[], const double &low[],
                                  const double &close[], int shift, double atrValue,
                                  ENUM_DIRECTION &outDir)
{
   double range = high[shift]-low[shift];
   double body  = MathAbs(close[shift]-open[shift]);
   if(range<=0 || atrValue<=0) return -1;

   double bodyRatio = body/range;
   double rangeVsAtr = range/atrValue;

   if(bodyRatio < InpDisp_BodyRatio || rangeVsAtr < InpDisp_RangeVsAvg) return -1;

   outDir = (close[shift]>open[shift]) ? DIR_BULL : DIR_BEAR;

   DisplacementObj d;
   d.time = iTime(_Symbol, PERIOD_CURRENT, shift);
   d.id = StableDisplacementId(d.time,outDir);
   d.barShift = shift;
   d.direction = outDir;
   d.bodyRatio = bodyRatio;
   d.rangeVsAtr = rangeVsAtr;
   d.causedByEventId = -1;   // تا وقتی به یک Event وصل نشود energyOnly می‌ماند
   d.liquidityEventId = -1;
   d.energyOnly = true;

   int n = ArraySize(g_displacements);
   ArrayResize(g_displacements, n+1);
   g_displacements[n]=d;
   // فاز ۱۳ (#۱۱): سقف + سیاست حذف FIFO. مصرف‌کننده‌ها (لینک رویداد،
   // DetectMicroFVG، DisplacementIdForBarTime) همیشه روی کندل جاری کار
   // می‌کنند، پس حذف قدیمی‌ترین‌ها خروجی زنده را عوض نمی‌کند.
   if(InpMaxDisplacements>0 && ArraySize(g_displacements)>InpMaxDisplacements)
   {
      int drop=ArraySize(g_displacements)-InpMaxDisplacements;
      int keep=ArraySize(g_displacements)-drop;
      for(int k=0;k<keep;k++) g_displacements[k]=g_displacements[k+drop];
      ArrayResize(g_displacements,InpMaxDisplacements);
      g_dispDropped+=drop;
   }
   return d.id;
}

// وقتی Event ای (BOS/CHoCH/MSS) ثبت شد و همزمان با یک Displacement candidate
// هم‌پوشانی زمانی داشت، اینجا آن دو را به‌هم قفل می‌کنیم (اثبات ارتباط واقعی)
void LinkDisplacementToEvent(long dispId, long eventId, long liqEventId)
{
   int n = ArraySize(g_displacements);
   for(int i=0;i<n;i++)
   {
      if(g_displacements[i].id==dispId)
      {
         g_displacements[i].causedByEventId = eventId;
         g_displacements[i].liquidityEventId = liqEventId;
         g_displacements[i].energyOnly = false;
         return;
      }
   }
}

// شناسهٔ Displacement همان کندل (برای اتصال FVG به کندل میانی الگو)
long DisplacementIdForBarTime(datetime t)
{
   if(t<=0) return -1;
   for(int i=ArraySize(g_displacements)-1;i>=0;i--)
      if(g_displacements[i].time==t) return g_displacements[i].id;
   return -1;
}

// Displacement فقط وقتی "زنجیره‌شده" است که به یک Structure Event وصل شده
// باشد (energyOnly=false) و جهت آن با ناحیهٔ مورد بررسی یکی باشد (#۲۴، #۲۷).
bool DisplacementChained(long dispId, ENUM_DIRECTION wantDir)
{
   if(dispId==-1) return false;
   for(int i=0;i<ArraySize(g_displacements);i++)
      if(g_displacements[i].id==dispId)
         return (!g_displacements[i].energyOnly && g_displacements[i].direction==wantDir);
   return false;
}

// FVG ممکن است قبل از بسته‌شدن زنجیرهٔ ساختار ثبت شود. این تابع پس از هر
// اتصال، FVGهایی را Causal می‌کند که Displacementشان واقعاً زنجیر شده باشد.
void PromoteCausalFVGs()
{
   for(int i=0;i<ArraySize(g_fvgs);i++)
   {
      if(g_fvgs[i].causal) continue;
      // فاز ۴۳: اینجا جهت **تولد** گپ سنجیده می‌شود (زنجیرهٔ Displacement مربوط به
      // کندل سازندهٔ گپ است، نه به نقش امروزش). پس عمداً FVGActiveDir() صدا زده
      // نمی‌شود؛ باگ قبلی دقیقاً همین بود که همین `direction` وسط کار بازنویسی
      // می‌شد و این زنجیره پس از وارونگی دیگر هرگز تأیید نمی‌شد.
      if(!DisplacementChained(g_fvgs[i].displacementId, g_fvgs[i].direction)) continue;
      g_fvgs[i].causal=true;
      if(!g_rebuildMode || InpDrawFVGZones) DrawFVG(g_fvgs[i]);
   }
}

//====================================================================
// FVG ENGINE — رفع ایراد ۷: FVG فقط وقتی "Causal" علامت می‌خورد که
// displacementId معتبر و غیر energyOnly داشته باشد.
//====================================================================
// فاز ۱۲ (#۳۰): گپ Implied جداگانه ثبت می‌شود چون سطح متفاوتی است.
// گپ استاندارد از high/low ساخته می‌شود و گپ Implied از **بدنهٔ** کندل اول و
// سوم (close کندل ۱ ↔ open کندل ۳). هر دو ناحیهٔ مستقل با شناسهٔ مستقل‌اند.
void AppendFVG(long id, datetime t, ENUM_DIRECTION dir, double top, double bottom,
               long midDispId, ENUM_FVG_KIND kind, ENUM_TIMEFRAMES tf, bool birthTouch)
{
   if(top<=bottom) return;
   for(int i=ArraySize(g_fvgs)-1;i>=0;i--)
      if(g_fvgs[i].id==id) return;          // همین ناحیه قبلأً ثبت شده
   FVGObj f;
   f.id=id; f.time=t; f.direction=dir; f.top=top; f.bottom=bottom;
   f.displacementId=midDispId;
   f.causal=DisplacementChained(midDispId, dir);
   f.mitigated=false; f.inverted=false; f.invalidated=false; f.invertedTime=0;
   f.ceTouched=false;
   f.createdTime=t; f.touchTime=0; f.birthBarTouch=birthTouch;
   f.kind=kind; f.tf=tf; f.ce=(top+bottom)/2.0;
   int n=ArraySize(g_fvgs); ArrayResize(g_fvgs,n+1); g_fvgs[n]=f;
   if(f.causal && !g_rebuildMode) DrawFVG(f);
}

void DetectFVG(const double &open[], const double &high[], const double &low[], const double &close[],
               int shift, long midBarDisplacementId)
{
   // الگوی سه‌کندلی استاندارد ICT: کندل سوم = shift، کندل میانی = shift+1،
   // کندل اول = shift+2. گپ بین high[shift+2] و low[shift] است و کندل
   // Displacement همان کندل **میانی** است، نه کندل تأییدکننده (#۲۶).
   if(shift+2 >= ArraySize(high) || shift+2 >= ArraySize(close) || shift+2 >= ArraySize(open)) return;

   // فاز ۲۸ — فیلتر اهمیت (منبع: LuxAlgo Library — FVG، مرحلهٔ ۴ تشخیص):
   // «گپ‌های سه‌کندلی خام بی‌وقفه چاپ می‌شوند، پس بیشتر ابزارها حداقل اندازه
   // (بر مبنای ATR یا درصد) یا هم‌راستایی با ساختار می‌خواهند.» بدون این گارد،
   // گپ‌های یک‌تیکی فقط نویز چارت بودند و مسئول بخشی از «FVG فیک» بودند.
   double minGap=(InpMinFVG_ATR>0.0 && g_analysisATR>0.0)? InpMinFVG_ATR*g_analysisATR : 0.0;

   // Bullish FVG
   if(low[shift] > high[shift+2] && (low[shift]-high[shift+2])>=minGap)
   {
      FVGObj f;
      f.time=BarTime(shift);
      f.direction=DIR_BULL;
      f.id=StableZoneId(f.time,f.direction,1);
      f.top=low[shift]; f.bottom=high[shift+2];
      f.displacementId = midBarDisplacementId;   // کندل میانی الگو
      // Causal فقط با Displacement زنجیرشده به Structure Event (#۲۷).
      f.causal = DisplacementChained(midBarDisplacementId, DIR_BULL);
      f.mitigated=false; f.inverted=false; f.invalidated=false; f.invertedTime=0;
      f.ceTouched=false;
      f.createdTime=f.time;
      f.touchTime=0;
      // تشخیصی: مرز گپ همیشه با همان کندل سوم لمس می‌شود، پس این مقدار باید true باشد.
      // همین موضوع ایراد #۲۵ بود؛ ثبتش برای اثبات کارکرد گاردِ lifecycle است.
      f.birthBarTouch=(low[shift]<=f.top && high[shift]>=f.bottom);
      f.kind=FVGK_STANDARD; f.tf=PERIOD_CURRENT; f.ce=(f.top+f.bottom)/2.0;   // فاز ۱۲
      int n=ArraySize(g_fvgs); ArrayResize(g_fvgs,n+1); g_fvgs[n]=f;
      if(f.causal && !g_rebuildMode) DrawFVG(f);
   }
   // Bearish FVG
   if(high[shift] < low[shift+2] && (low[shift+2]-high[shift])>=minGap)
   {
      FVGObj f;
      f.time=BarTime(shift);
      f.direction=DIR_BEAR;
      f.id=StableZoneId(f.time,f.direction,1);
      f.top=low[shift+2]; f.bottom=high[shift];
      f.displacementId = midBarDisplacementId;   // کندل میانی الگو
      f.causal = DisplacementChained(midBarDisplacementId, DIR_BEAR);
      f.mitigated=false; f.inverted=false; f.invalidated=false; f.invertedTime=0;
      f.ceTouched=false;
      f.createdTime=f.time;
      f.touchTime=0;
      // تشخیصی: مرز گپ همیشه با همان کندل سوم لمس می‌شود، پس این مقدار باید true باشد.
      // همین موضوع ایراد #۲۵ بود؛ ثبتش برای اثبات کارکرد گاردِ lifecycle است.
      f.birthBarTouch=(low[shift]<=f.top && high[shift]>=f.bottom);
      f.kind=FVGK_STANDARD; f.tf=PERIOD_CURRENT; f.ce=(f.top+f.bottom)/2.0;   // فاز ۱۲
      int n=ArraySize(g_fvgs); ArrayResize(g_fvgs,n+1); g_fvgs[n]=f;
      if(f.causal && !g_rebuildMode) DrawFVG(f);
   }

   // --- فاز ۲۸: Implied FVG با فرمول **واقعی** ICT 2023 ---
   // منبع: LuxAlgo Library — Implied FVG (فرمول استاندارد):
   //   UWM(x) = ( H(x) + max(O(x),C(x)) ) / 2      میانهٔ فتیلهٔ بالا
   //   LWM(x) = ( min(O(x),C(x)) + L(x) ) / 2      میانهٔ فتیلهٔ پایین
   //   صعودی در کندل t:  LWM(t) > UWM(t-2)  و  L(t) <= H(t-2)
   //        ناحیه: bottom = UWM(t-2) , top = LWM(t)
   //   نزولی در کندل t:  UWM(t) < LWM(t-2)  و  H(t) >= L(t-2)
   //        ناحیه: top = LWM(t-2) , bottom = UWM(t)
   // نگاشت روی ایندکس ما: t = shift (کندل سوم)، t-2 = shift+2 (کندل اول).
   //
   // ایراد واقعی که این جایگزین می‌بندد: نسخهٔ قبلی close کندل ۱ و open کندل ۳
   // (مرزهای **بدنه**) را می‌گرفت. آن فرمول Implied FVG نیست؛ اسم درستش
   // **Volume Imbalance** است. حالا هر دو با فرمول درست و برچسب درست ثبت می‌شوند.
   if(InpEnablePhase12 && InpDetectImpliedFVG)
   {
      double o1=open[shift+2],  c1=close[shift+2], h1=high[shift+2], l1=low[shift+2];
      double o3=open[shift],    c3=close[shift],   h3=high[shift],   l3=low[shift];
      double uwm1=(h1+MathMax(o1,c1))/2.0;   // میانهٔ فتیلهٔ بالای کندل اول
      double lwm1=(MathMin(o1,c1)+l1)/2.0;   // میانهٔ فتیلهٔ پایین کندل اول
      double uwm3=(h3+MathMax(o3,c3))/2.0;   // میانهٔ فتیلهٔ بالای کندل سوم
      double lwm3=(MathMin(o3,c3)+l3)/2.0;   // میانهٔ فتیلهٔ پایین کندل سوم

      // Implied صعودی: دو فتیلهٔ روبه‌روی هم، با هم‌پوشانی فتیلهٔ کندل اول و سوم.
      if(lwm3>uwm1 && l3<=h1 && (lwm3-uwm1)>=minGap)
         AppendFVG(StableZoneId(BarTime(shift),DIR_BULL,3),
                   BarTime(shift), DIR_BULL, lwm3, uwm1,
                   midBarDisplacementId, FVGK_IMPLIED, PERIOD_CURRENT,
                   (l3<=lwm3 && h3>=uwm1));
      // Implied نزولی
      if(uwm3<lwm1 && h3>=l1 && (lwm1-uwm3)>=minGap)
         AppendFVG(StableZoneId(BarTime(shift),DIR_BEAR,3),
                   BarTime(shift), DIR_BEAR, lwm1, uwm3,
                   midBarDisplacementId, FVGK_IMPLIED, PERIOD_CURRENT,
                   (l3<=lwm1 && h3>=uwm3));

      // --- Volume Imbalance (منبع: LuxAlgo Library — همان فرمولی که قبلاً
      // اشتباه «Implied» نامیده می‌شد): گپ بین **بدنهٔ** کندل اول و سوم
      // در حالی که فتیله‌ها هنوز هم‌پوشانی دارند. مفهوم مستقل و معتبر SMC است،
      // پس حذف نشد؛ برچسب درست گرفت و discriminator جدا (۵) تا با Implied قاطی نشود.
      if(InpDetectVolumeImbalance)
      {
         if(c3>c1 && (c3-c1)>=minGap)
            AppendFVG(StableZoneId(BarTime(shift),DIR_BULL,5),
                      BarTime(shift), DIR_BULL, c3, c1,
                      midBarDisplacementId, FVGK_VOL_IMBALANCE, PERIOD_CURRENT,
                      (l3<=c3 && h3>=c1));
         else if(c1>c3 && (c1-c3)>=minGap)
            AppendFVG(StableZoneId(BarTime(shift),DIR_BEAR,5),
                      BarTime(shift), DIR_BEAR, c1, c3,
                      midBarDisplacementId, FVGK_VOL_IMBALANCE, PERIOD_CURRENT,
                      (l3<=c1 && h3>=c3));
      }
   }

   if(ArraySize(g_fvgs) > InpMaxFVG)
   {
      for(int i=0;i<ArraySize(g_fvgs)-1;i++) g_fvgs[i]=g_fvgs[i+1];
      ArrayResize(g_fvgs, InpMaxFVG);
   }
}

//====================================================================
// OB ENGINE — رفع ایراد ۹،۱۲: OB باید زنجیره اثبات کامل داشته باشد
// و Core/Standalone در یک Registry واحد باشند (فقط با فلگ isStandalone
// از هم تفکیک می‌شوند، نه دو آرایه جدا)
//====================================================================
void DetectOB(const double &open[], const double &high[], const double &low[], const double &close[],
              int dispBarShift, long displacementId, long structureEventId, long liquidityEventId, long fvgId,
              double atrOfLast=0.0)
{
   // آخرین کندل مخالف‌رنگ قبل از Displacement (نه فقط کندل بلافاصله قبل)
   bool dispDown = close[dispBarShift] < open[dispBarShift]; // جهت دیسپلیسمنت
   ENUM_DIRECTION obDir = dispDown? DIR_BEAR : DIR_BULL;
   int obShift = -1;
   int backLimit = ArraySize(open)-dispBarShift-1;
   int lookback  = (InpOB_LookbackBars>0)? InpOB_LookbackBars : 1;
   if(backLimit>lookback) backLimit=lookback;
   for(int k=1;k<=backLimit;k++)
   {
      int idx=dispBarShift+k;
      bool opposite = dispDown ? (close[idx] > open[idx]) : (close[idx] < open[idx]);
      if(opposite){ obShift=idx; break; }
   }
   if(obShift<0) return;

   OBObj o;
   o.time = iTime(_Symbol, PERIOD_CURRENT, obShift);
   o.id = StableZoneId(o.time,obDir,2);
   if(InpOBUseFullCandleRange)
   {
      o.top = high[obShift];
      o.bottom = low[obShift];
   }
   else
   {
      o.top = MathMax(open[obShift], close[obShift]);
      o.bottom = MathMin(open[obShift], close[obShift]);
   }
   o.direction = obDir;
   o.displacementId = displacementId;
   o.structureEventId = structureEventId;   // -1 یعنی ناحیهٔ Standalone (فاز ۱۲)
   o.liquidityEventId = liquidityEventId;   // -1 مجاز است، ولی اگر باشد Breaker بعداً قوی‌تر می‌شود
   o.fvgId = fvgId;
   // --- فاز ۱۲ (#۳۵ #۳۶ #۳۸) ---
   // Core = ناحیه در شکست ساختار مشارکت کرده. Standalone = Displacement هست
   // ولی شکست ساختاری وجود ندارد. Extreme و Mitigation Block در پاس بعدی
   // (MarkExtremeOrderBlocks و UpdateOB_MitigationAndBreaker) برچسب می‌خورند.
   o.isStandalone = (structureEventId==-1);
   o.hasSweep     = (liquidityEventId!=-1);
   o.isExtreme    = false;
   o.kind = o.isStandalone ? OBK_STANDALONE : OBK_CORE;
   o.polarityFlipped = false;
   o.retested = false;
   o.createdTime = iTime(_Symbol, PERIOD_CURRENT, dispBarShift);
   o.brokenTime = 0;
   o.tf = PERIOD_CURRENT;   // فاز ۱۶+: مالکیت تایم‌فریم (روی چارت جاری ساخته شده)
   // فاز ۳۶: تفکیک Internal/External OB — طبق منبع (LuxAlgo — Internal vs
   // External Range Liquidity) ناحیه‌ای که مبدأ/اکسترمم لگ معامله‌گری است
   // External (ERL) و ناحیه‌ای که «left inside the leg» است Internal (IRL) است.
   // سنجش در لحظهٔ تولید با اکسترمم لگِ *تازه‌بسته*: فاصله تا مرز نزدیک لگ
   // حداکثر ۱۰٪ ATR → External؛ بقیه Internal. علامت‌گذاری نهایی External در
   // MarkExtremeOrderBlocks هم ادامه دارد (یک OB در هر سر لگ).
   o.scope = SCOPE_INTERNAL;   // پیش‌فرض: داخل لگ
   if(g_leg.valid)
   {
      double tolExt=(atrOfLast>0.0)? atrOfLast*0.10 : 0.0;
      if(MathAbs(o.top-g_leg.high)<=tolExt || MathAbs(o.bottom-g_leg.low)<=tolExt)
         o.scope=SCOPE_EXTERNAL;
   }

   // رفع ایراد ۹ + تکمیل فاز ۱۲: اعتبار اولیه فقط با Displacement واقعی.
   // نداشتن شکست ساختار ناحیه را «بی‌اعتبار» نمی‌کند؛ فقط Standalone میکند
   // و در امتیاز POI جریمه می‌شود.
   if(displacementId!=-1)
      o.state = OB_VALID;
   else
      o.state = OB_INVALID; // کندل مخالف بدون Displacement — نویز؛ در Setup استفاده نمی‌شود

   // فاز ۲۹ (#۷۳): dedup رجیستری OB — همان کلاس باگی که برای FVG در AppendFVG
   // بسته شده بود ولی اینجا باز مانده بود.
   // چرا رخ می‌دهد (اثبات از ترتیب کد): دو کندل Displacement **پیاپی** در یک
   // رالی/ریزش پرقدرت، هر دو به یک کندل مخالف می‌رسند (چون حداقل یکی از آن دو
   // هم‌رنگ Displacement است)، پس هر دو با StableZoneId **یکسان** ثبت می‌شدند:
   // دو باکس روی‌هم روی چارت، شمارش OB دو برابر، و مصرف سقف InpMaxOB با مناطق
   // تکراری — همان چیزی که چارت را بی‌دلیل شلوغ می‌کرد.
   // رفتار: نخستین ثبت مالک ناحیه است و متادیتای زنجیره فقط «تکمیل» می‌شود
   // (هرگز ضعیف‌تر نمی‌شود: Core شدن، Sweep داشتن، معتبر شدن).
   for(int i=ArraySize(g_obs)-1;i>=0;i--)
   {
      if(g_obs[i].id!=o.id) continue;
      if(g_obs[i].displacementId==-1) g_obs[i].displacementId=o.displacementId;
      if(g_obs[i].fvgId==-1)          g_obs[i].fvgId=o.fvgId;
      if(g_obs[i].structureEventId==-1 && o.structureEventId!=-1)
      {
         g_obs[i].structureEventId=o.structureEventId;
         g_obs[i].isStandalone=false;
         if(g_obs[i].kind==OBK_STANDALONE) g_obs[i].kind=OBK_CORE;
      }
      if(g_obs[i].liquidityEventId==-1 && o.liquidityEventId!=-1)
      {
         g_obs[i].liquidityEventId=o.liquidityEventId;
         g_obs[i].hasSweep=true;
      }
      if(g_obs[i].state==OB_INVALID && o.state==OB_VALID) g_obs[i].state=OB_VALID;
      g_obsDeduped++;
      return;
   }

   int n=ArraySize(g_obs); ArrayResize(g_obs,n+1); g_obs[n]=o;
   if(o.state==OB_VALID && !g_rebuildMode) DrawOB(o);

   if(ArraySize(g_obs) > InpMaxOB)
   {
      for(int i=0;i<ArraySize(g_obs)-1;i++) g_obs[i]=g_obs[i+1];
      ArrayResize(g_obs, InpMaxOB);
   }
}

//====================================================================
// BREAKER ENGINE — رفع ایراد ۱۰،۱۱: Breaker فقط از روی زنجیره کامل:
//   Valid OB -> Structural Violation -> Broken -> Polarity Flip -> Retest -> Breaker
// برچسب تخفیف‌خورده به‌تنهایی هرگز کافی نیست، و ساخته‌شدن پیش از جاروی نقدینگی هم به‌تنهایی
// کافی نیست (باید Retest واقعی هم رخ بدهد).
//====================================================================
void UpdateOB_MitigationAndBreaker(double curHigh, double curLow, double curClose, datetime curBarTime)
{
   int n=ArraySize(g_obs);
   for(int i=0;i<n;i++)
   {
      if(g_obs[i].state==OB_INVALID) continue;
      if(g_obs[i].state==OB_BREAKER) continue;      // زنجیره برای این ناحیه تمام شده
      if(g_obs[i].state==OB_MITIGATION) continue;   // فاز ۱۲: زنجیرهٔ Mitigation Block هم تمام شده

      bool priceInZone = (curLow <= g_obs[i].top && curHigh >= g_obs[i].bottom);
      // ناحیه‌ای که در همین کندل ثبت شده نمی‌تواند در همان کندل MITIGATED شود؛
      // کندل Displacement معمولاً از خود ناحیه شروع می‌شود و همین باعث می‌شد
      // همهٔ OBها همان لحظه مصرف‌شده به‌نظر برسند (#۲۵، همان کلاس باگ).
      bool registeredHere = (g_obs[i].createdTime >= curBarTime);

      // Step 1: Mitigation — فقط لمس، نه شکست
      if(g_obs[i].state==OB_VALID && priceInZone && !registeredHere)
         g_obs[i].state = OB_MITIGATED;

      // Step 2: Structural violation -> BROKEN (بسته‌شدن کامل از سمت مخالف)
      bool violated = false;
      if(g_obs[i].direction==DIR_BULL && curClose < g_obs[i].bottom) violated = true;
      if(g_obs[i].direction==DIR_BEAR && curClose > g_obs[i].top)    violated = true;

      if((g_obs[i].state==OB_VALID || g_obs[i].state==OB_MITIGATED) && violated)
      {
         g_obs[i].state = OB_BROKEN;
         g_obs[i].polarityFlipped = true; // پولاریتی از این لحظه برعکس در نظر گرفته می‌شود
         g_obs[i].brokenTime = curBarTime;
         continue;                        // ریتست باید در کندلی جدا از کندل شکست باشد
      }

      // Step 3: Retest -> BREAKER
      // دو شرط سخت‌گیرانهٔ Breaker (#۳۹):
      //   (۱) ناحیه باید روی یک Sweep واقعی نقدینگی ساخته شده باشد (liquidityEventId).
      //   (۲) ریتست باید در کندلی جداگانه و بعد از کندل شکست رخ دهد.
      if(g_obs[i].state==OB_BROKEN && g_obs[i].polarityFlipped &&
         g_obs[i].liquidityEventId!=-1 &&
         g_obs[i].brokenTime>0 && curBarTime>g_obs[i].brokenTime)
      {
         bool retestHappening =
            (g_obs[i].direction==DIR_BULL && curHigh >= g_obs[i].bottom && curHigh <= g_obs[i].top) ||
            (g_obs[i].direction==DIR_BEAR && curLow  <= g_obs[i].top    && curLow  >= g_obs[i].bottom);

         if(retestHappening)
         {
            g_obs[i].retested = true;
            g_obs[i].state = OB_BREAKER; // فقط الان، بعد از کل زنجیره
            // kind عوض نمی‌شود: Core/Standalone فقط دربارهٔ مشارکت در شکست ساختار
            // است و Breaker یک state است، نه یک نوع دیگر از ناحیه.
         }
      }

      // --- فاز ۱۲ (#۳۸): Mitigation Block **مستقل** ---
      // همان زنجیرهٔ شکست + پولاریتی برعکس + ریتست، ولی **بدون** Sweep
      // نقدینگی روی ناحیه. همین تفاوت، مرز Breaker و Mitigation Block است.
      if(g_obs[i].state==OB_BROKEN && g_obs[i].polarityFlipped &&
         g_obs[i].liquidityEventId==-1 &&
         g_obs[i].brokenTime>0 && curBarTime>g_obs[i].brokenTime)
      {
         bool retestMit =
            (g_obs[i].direction==DIR_BULL && curHigh >= g_obs[i].bottom && curHigh <= g_obs[i].top) ||
            (g_obs[i].direction==DIR_BEAR && curLow  <= g_obs[i].top    && curLow  >= g_obs[i].bottom);
         if(retestMit)
         {
            g_obs[i].retested = true;
            g_obs[i].state = OB_MITIGATION;
            g_obs[i].kind  = OBK_MITIGATION_BLOCK;
         }
      }
   }
}

void UpdateFVG_Lifecycle(double curHigh, double curLow, double curClose, datetime curBarTime)
{
   for(int i=0;i<ArraySize(g_fvgs);i++)
   {
      if(g_fvgs[i].invalidated) continue;
      // ناحیه‌ای که در همین کندل ساخته شده در همان کندل "لمس‌شده" حساب نمی‌شود.
      // کندل سوم الگو همیشه مرز گپ را لمس می‌کند، پس بدون این شرط هر FVG
      // در لحظهٔ تولد MITIGATED می‌شد (#۲۵).
      if(g_fvgs[i].createdTime >= curBarTime) continue;
      bool touched=(curLow<=g_fvgs[i].top && curHigh>=g_fvgs[i].bottom);
      if(touched && !g_fvgs[i].mitigated)
      {
         g_fvgs[i].mitigated=true;
         g_fvgs[i].touchTime=curBarTime;   // فقط برای تشخیص/اثبات؛ منطق امتیازدهی عوض نمی‌شود
      }
      // فاز ۲۸ — Consequent Encroachment (منبع: LuxAlgo Library — Consequent
      // Encroachment / FVG): «خط تصمیم» یک گپ میانهٔ آن است و بیشتر مدل‌ها لمس
      // میانه را «به‌قدر کافی پر شده» می‌دانند. لمس صرفِ لبهٔ ناحیه این معنا را
      // ندارد، پس این دو وضعیت از هم جدا نگه داشته می‌شوند و پنل آموزشی هر دو
      // را جدا می‌گوید (قبلاً فقط یک پرچم mitigated بود و همان هم هر لمسی را
      // «میتیگیت‌شده» اعلام می‌کرد).
      if(!g_fvgs[i].ceTouched && curLow<=g_fvgs[i].ce && curHigh>=g_fvgs[i].ce)
         g_fvgs[i].ceTouched=true;
      // عبور کامل از سمت مخالف => Inversion FVG (iFVG). ناحیه حذف نمی‌شود؛
      // پولاریتی آن برعکس می‌شود و به‌عنوان ناحیهٔ مخالف قابل استفاده است.
      //
      // فاز ۴۳ — اینجا باگ بود: **جهت تولد بازنویسی می‌شد.** `direction` را
      // نمی‌شود عوض کرد، چون سه چیز دیگر به آن گره خورده‌اند:
      //   (۱) هندسهٔ ناحیه: برای گپ صعودی top=کف کندل سوم و bottom=سقف کندل
      //       اول است؛ اگر جهت عوض شود، همان مرزها معنای مخالف می‌دهند و شرط
      //       «بسته‌شدن از سمت مخالف» در همین تابع روی جهت جابه‌جا شده اجرا
      //       می‌شود (یعنی دیگر اگر گپ وارونه یک‌بار دیگر بررسی شود، هیچ‌وقت
      //       نمی‌تواند تشخیص خودش را درست بپذیرد).
      //   (۲) شناسهٔ ناحیه: StableZoneId(زمان، جهت تولد، تفکیک‌کننده) و نام
      //       آبجکت روی چارت از همین شناسه ساخته می‌شود؛ با تغییر جهت، نام
      //       آبجکت دیگر با محتوایش نمی‌خواند.
      //   (۳) نام مکتب (BISI/SIBI) و زنجیرهٔ Displacement، که هر دو تابع
      //       جهتِ سازندهٔ گپ‌اند، نه نقش امروزش.
      // پس فقط پرچم وارونگی و زمانش ثبت می‌شود؛ نقش فعلی با FVGActiveDir()
      // خوانده می‌شود. نتیجه: رنگ، CSV، پنل، انتخاب ناحیهٔ ستاپ و دروازهٔ
      // برگشت همه از یک منبع حرف می‌زنند.
      if(!g_fvgs[i].inverted && g_fvgs[i].direction==DIR_BULL && curClose < g_fvgs[i].bottom)
      {
         g_fvgs[i].inverted=true;
         g_fvgs[i].invertedTime=curBarTime;
      }
      if(!g_fvgs[i].inverted && g_fvgs[i].direction==DIR_BEAR && curClose > g_fvgs[i].top)
      {
         g_fvgs[i].inverted=true;
         g_fvgs[i].invertedTime=curBarTime;
      }
      // انقضای زمانی
      if(InpFVG_ExpireBars>0 && curBarTime>0 && g_fvgs[i].createdTime>0)
      {
         int ageBars=(int)((curBarTime-g_fvgs[i].createdTime)/PeriodSeconds(PERIOD_CURRENT));
         if(ageBars>InpFVG_ExpireBars) g_fvgs[i].invalidated=true;
      }
   }
}

void PersistReplayDiagnostics(datetime barTime)
{
   if(!g_rebuildMode || !InpWriteReplayDiagnostics) return;
   int handle=DiagOpen("ICT_Assistant_Canonical_MTF_Diag.csv");
   if(handle==INVALID_HANDLE) return;
   if(FileSize(handle)==0)
      FileWrite(handle,"BarTime","BiasOwner","H4Confirmed","MTFChain","Conflict","ConflictReason","ReadyState");
   FileSeek(handle,0,SEEK_END);
   string chain="";
   for(int i=0;i<6;i++)
   {
      if(i>0) chain+="|";
      ENUM_DIRECTION extDir=(i==0)?g_htfBias:g_mtfContext[i].externalDirection;
      chain+=EnumToString(g_mtfTimeframes[i])+":"+DirToStr(extDir)+":"+DirToStr(g_mtfContext[i].internalDirection);
   }
   FileWrite(handle,TimeToString(barTime,TIME_DATE|TIME_MINUTES),
             DirToStr(g_htfBias),
             TimeToString(g_mtfContext[0].confirmedBarTime,TIME_DATE|TIME_MINUTES),
             chain,g_mtfConflict?"true":"false",g_mtfConflictReason,g_setup.status);
   DiagClose(handle);
}

void UpdateContextForClosedBar(datetime barTime, double closePrice, double atrValue,
                              double highPrice=0.0, double lowPrice=0.0)
{
   if(barTime<=0) return;
   // آفست بروکر در هر کندل بسته بازآزمایی می‌شود (رفع #۵۵): اگر بروکر آفست را
   // با DST عوض کند، بدون این خط همهٔ پنجره‌های سشن تا reload بعدی غلط می‌مانند.
   RefreshBrokerOffset();
   // فاز ۱۵: آفست *همین لحظهٔ تاریخی* (نه آفست امروز) ثبت می‌شود تا در CSV شاهد
   // عددی داشته باشیم که پنجره‌های سشن با DST تاریخی محاسبه شده‌اند.
   g_histOffsetDeltaMin=(BrokerOffsetSecondsAtServer(barTime)-g_serverGMTOffsetSeconds)/60;
   // فاز ۱۵ (#۶۶): چرخهٔ عمر ستاپ پیش از UpdateSetup سنجیده می‌شود، وگرنه وضعیت
   // ستاپِ در حال پیگیری با ستاپ جدیدِ همین کندل بازنویسی می‌شد و هیچ ابطالی
   // هرگز قابل مشاهده نبود.
   long c0=PROBE_T0;
   UpdateSetupLifecycle(barTime, closePrice, highPrice, lowPrice);
   PROBE_END("2o.lifecycle",c0);
   int chartSeconds=PeriodSeconds(PERIOD_CURRENT);
   if(chartSeconds<=0) chartSeconds=60;
   datetime analysisEnd=(datetime)((long)barTime+(long)chartSeconds-1L);
   c0=PROBE_T0; UpdateHTFStructure(analysisEnd);                    PROBE_END("2a.htf",c0);
   c0=PROBE_T0; UpdateLiquidityRegistry_PDH_PDL_PWH_PWL(analysisEnd); PROBE_END("2b.pdhl",c0);
   c0=PROBE_T0; UpdateSessionContext(analysisEnd);                   PROBE_END("2c.session",c0);
   c0=PROBE_T0; AnalyzeMTFContext(analysisEnd);                      PROBE_END("2d.mtf",c0);
   // فاز ۱۱: دروازهٔ برگشت بعد از تازه‌شدن MTF و پیش از DOL/Setup سنجیده
   // می‌شود تا شواهد SMR (هم‌جهتی کانتکست) از دادهٔ همین کندل باشد.
   c0=PROBE_T0; UpdateReversalEngine(analysisEnd, closePrice, atrValue); PROBE_END("2e.reversal",c0);
   c0=PROBE_T0; UpdateDealingLeg(analysisEnd, atrValue);             PROBE_END("2f.leg",c0);
   // --- فاز ۱۲: بعد از لگ (چون Extreme به اکسترمم لگ وابسته است) ---
   c0=PROBE_T0; MarkExtremeOrderBlocks(atrValue);                    PROBE_END("2g.extremeOB",c0);
   c0=PROBE_T0; BuildTrendlines(atrValue);                           PROBE_END("2h.trendline",c0);
   c0=PROBE_T0; UpdateRangeLiquidity(atrValue);                      PROBE_END("2i.rangeLiq",c0);
   c0=PROBE_T0; UpdateIPDAReferenceLevels(analysisEnd);              PROBE_END("2j.ipda",c0);
   c0=PROBE_T0; UpdateHtfInternalStructure(analysisEnd);             PROBE_END("2k.htfInternal",c0);
   c0=PROBE_T0; UpdatePOIRegistry(analysisEnd, atrValue);            PROBE_END("2l.poi",c0);
   // یک منبع واحد برای DR/EQ: اگر لگ واقعی معتبر باشد، همان مبنا است؛ وگرنه
   // سقف/کف حفاظت‌شدهٔ H4 به‌عنوان جانشین (بدون ادعای OTE) می‌ماند (#۴۳/#۴۵).
   g_htfRangeHigh=g_leg.valid? g_leg.high : g_mtfContext[0].protectedHigh;
   g_htfRangeLow =g_leg.valid? g_leg.low  : g_mtfContext[0].protectedLow;
   c0=PROBE_T0; UpdateDOL(closePrice, atrValue);                     PROBE_END("2m.dol",c0);
   c0=PROBE_T0; UpdateSetup(closePrice, atrValue, barTime);          PROBE_END("2n.setup",c0);
   // فاز ۱۵ (#۶۶): مسلح‌کردن پیگیری ستاپ بلافاصله بعد از READY شدن آن.
   ArmSetupLifecycle(barTime);
   g_lastContextBarTime=barTime;
   c0=PROBE_T0; PersistReplayDiagnostics(barTime);   PROBE_END("2p.replayDiag",c0);
   c0=PROBE_T0; PersistReversalDiagnostics(barTime); PROBE_END("2q.reversalDiag",c0);
   c0=PROBE_T0; PersistPhase15Diagnostics(barTime);  PROBE_END("2r.phase15Diag",c0);
   // فاز ۳۲: ریسک برگشت — بعد از DOL/لگ/Exhaustion محاسبه می‌شود، چون به همهٔ آن‌ها نگاه می‌کند.
   c0=PROBE_T0; UpdateReverseRisk(closePrice, atrValue, barTime, highPrice, lowPrice); PROBE_END("2s.revRisk",c0);
}

void DetectRejectionBlock(const double &open[], const double &high[], const double &low[], const double &close[], const int shift, long sweepId, ENUM_DIRECTION sweepDir)
{
   if(shift>=ArraySize(open)) return;
   double range=high[shift]-low[shift];
   if(range<=0.0) return;
   double body=MathAbs(close[shift]-open[shift]);
   double bodyTop=MathMax(open[shift],close[shift]);
   double bodyBot=MathMin(open[shift],close[shift]);
   double upperWick=high[shift]-bodyTop;
   double lowerWick=bodyBot-low[shift];
   double dominantWick=MathMax(upperWick,lowerWick);
   if(dominantWick/range<0.60 || body/range>0.40) return;

   // Rejection Block بدون زمینهٔ نقدینگی معنا ندارد (#۴۰): در همان کندل باید یک
   // سطح ثبت‌شدهٔ نقدینگی جارو شده باشد و جهت پس‌زدگی با جهت سوئپ هم‌خوان باشد.
   if(sweepId==-1) return;
   bool upperReject = (upperWick>lowerWick);   // فتیلهٔ بالا → پس‌زدگی نزولی (BSL جارو شده)
   if(upperReject && sweepDir!=DIR_BEAR) return;
   if(!upperReject && sweepDir!=DIR_BULL) return;

   RejectionObj block;
   block.time=BarTime(shift);
   // ناحیهٔ Rejection Block همان فتیلهٔ غالب است، نه کل کندل (#۴۰).
   if(upperReject){ block.top=high[shift]; block.bottom=bodyTop; }
   else            { block.top=bodyBot;    block.bottom=low[shift]; }
   if(block.top<=block.bottom) return;
   block.direction=upperReject ? DIR_BEAR : DIR_BULL;
   block.id=StableZoneId(block.time,block.direction,3);
   block.rejectionState=REJECTION_FRESH;
   int n=ArraySize(g_rejections);
   ArrayResize(g_rejections,n+1);
   g_rejections[n]=block;
   if(!g_rebuildMode) DrawRejection(block);
   // فاز ۱۳: سقف هاردکد ۵۰ به ورودی واقعی تبدیل شد (همان مقدار پیش‌فرض).
   if(InpMaxRejections>0 && ArraySize(g_rejections)>InpMaxRejections)
   {
      int drop=ArraySize(g_rejections)-InpMaxRejections;
      int keep=ArraySize(g_rejections)-drop;
      for(int i=0;i<keep;i++) g_rejections[i]=g_rejections[i+drop];
      ArrayResize(g_rejections,InpMaxRejections);
   }
}

void UpdateRejectionLifecycle(double curHigh, double curLow, double curClose, datetime curBarTime)
{
   for(int i=0;i<ArraySize(g_rejections);i++)
   {
      if(g_rejections[i].rejectionState==REJECTION_INVALID) continue;
      // کندل سازندهٔ ناحیه همان کندل را لمس کرده؛ این لمس معتبر نیست (#۴۰).
      if(g_rejections[i].time >= curBarTime) continue;
      if(curLow<=g_rejections[i].top && curHigh>=g_rejections[i].bottom)
         g_rejections[i].rejectionState=REJECTION_TOUCHED;
      if((g_rejections[i].direction==DIR_BULL && curClose<g_rejections[i].bottom) ||
         (g_rejections[i].direction==DIR_BEAR && curClose>g_rejections[i].top))
         g_rejections[i].rejectionState=REJECTION_INVALID;
   }
}

// سطحی که قیمت با **بسته‌شدن** از آن عبور کرده دیگر نقدینگی دست‌نخورده نیست؛
// نقدینگی "پذیرفته شد" (accepted) و از حالت انتظار خارج می‌شود (#۲۲).
// این سطح حذف نمی‌شود: فقط از FRESH به INVALID می‌رود تا تاریخچه روی چارت بماند.
void UpdateLiquidityLifecycle(double curClose)
{
   for(int i=0;i<ArraySize(g_liquidity);i++)
   {
      if(g_liquidity[i].state!=LSTATE_FRESH) continue;
      bool highSide=IsHighSideLiquidity(g_liquidity[i].type);
      if(highSide  && curClose > g_liquidity[i].price) g_liquidity[i].state=LSTATE_INVALID;
      if(!highSide && curClose < g_liquidity[i].price) g_liquidity[i].state=LSTATE_INVALID;
   }
}

//====================================================================
// فاز ۳۲ — «ریسک برگشت»: در چه نقطه‌ای از حرکت ایستاده‌ایم و خطر ورودِ خلاف جهت چقدر است
//
// قاعدهٔ صادقانه (مهم): این تابع **هیچ درصدی تولید نمی‌کند**. درصد فقط از داده
// شمرده می‌شود؛ ابزار tools/Report-ReverseRisk.ps1 همین CSV را می‌خواند، حرکت
// بعدیِ قیمت را از ستون‌های High/Low می‌سازد و نرخ واقعی برگشت را به تفکیک
// شرط‌ها می‌دهد (با تعداد نمونه). اینجا فقط *شاهد* ثبت می‌شود و یک امتیاز هشدار
// با وزن‌های مستند که در پنل تفکیک می‌شوند — تا کاربر خودش قضاوت کند.
//====================================================================
string RRFvgKindName(ENUM_FVG_KIND k)
{
   switch(k)
   {
      case FVGK_IMPLIED:       return "FVG Implied";
      case FVGK_MICRO:         return "FVG Micro";
      case FVGK_VOL_IMBALANCE: return "Volume Imbalance";
   }
   return "FVG Standard";
}
// فاز ۳۶: برچسب ترکیبی Silver Bullet + همسویی HTF-LTF (در داشبورد و ReverseRisk)
string SBSyncLabel()
{
   string sb="";
   if(g_silverBullet==SB_LONDON) sb="SB 03-04";
   else if(g_silverBullet==SB_NY_AM) sb="SB 10-11";
   else if(g_silverBullet==SB_NY_PM) sb="SB 14-15";
   if(sb=="") return "—";
   // Phase 42: this string is joined with the Silver Bullet tag by " | ", so
   // each part is a Latin-first label followed by a pure Persian word - the
   // composite row stays one visual run instead of splitting into two.
   string sync=(g_mtfConflict? "MTF | تضاد" : (g_htfBias==DIR_NONE? "BIAS | بدون" : "HTF-LTF | همسو"));
   return sb+" | "+sync;
}
string RRObStateName(ENUM_OB_STATE s)
{
   switch(s)
   {
      case OB_VALID:      return "VALID (دست‌نخورده)";
      case OB_MITIGATED:  return "MITIGATED (لمس شده)";
      case OB_BROKEN:     return "BROKEN (شکسته)";
      case OB_BREAKER:    return "BREAKER (پولاریتی برگشته)";
      case OB_MITIGATION:  return "MITIGATION BLOCK";
   }
   return "INVALID";
}
string RRObKindName(const OBObj &o)
{
   // فاز ۴۳: برچسب سطح، نقش فعلی است — یک Breaker/Mitigation Block که قطبیتش
   // برگشته، دیگر ناحیهٔ تقاضا/عرضهٔ تولدش نیست.
   string dirTxt=(OBActiveDir(o)==DIR_BULL)? " (تقاضا)" : " (عرضه)";
   string scope=(o.scope==SCOPE_EXTERNAL)? " EXT":" INT";   // فاز ۳۶
   if(o.state==OB_BREAKER)    return "Breaker"+dirTxt;
   if(o.state==OB_MITIGATION) return "Mitigation Block"+dirTxt;
   if(o.kind==OBK_EXTREME)      return "OB Extreme"+dirTxt;
   if(o.kind==OBK_STANDALONE)   return "OB Standalone"+dirTxt+scope;
   return "OB Core"+dirTxt+scope;
}
string RRSdKindName(ENUM_SD_KIND k)
{
   switch(k)
   {
      case SDK_RBR:    return "S/D RBR";
      case SDK_DBD:    return "S/D DBD";
      case SDK_RBD:    return "S/D RBD";
      case SDK_DBR:    return "S/D DBR";
      case SDK_SUPPLY: return "Supply Zone";
      case SDK_DEMAND: return "Demand Zone";
   }
   return "S/D Zone";
}
string RRSdStateName(ENUM_SD_STATE s)
{
   switch(s)
   {
      case SDS_FRESH:   return "FRESH";
      case SDS_TESTED:  return "TESTED";
      case SDS_FLIPPED: return "FLIPPED";
      case SDS_BROKEN:  return "BROKEN";
   }
   return "-";
}
string RRLiqStateName(ENUM_LIQ_STATE s)
{
   switch(s)
   {
      case LSTATE_FRESH:   return "FRESH (دست‌نخورده)";
      case LSTATE_SWEPT:   return "SWEPT (جارو شده)";
      case LSTATE_INVALID: return "ACCEPTED (پذیرفته/مصرف شده)";
   }
   return "-";
}

// فاصلهٔ قیمت تا یک ناحیه (۰ = داخل ناحیه) بر حسب ATR
double RRAreaDist(double price, double top, double bottom, double atr)
{
   if(atr<=0.0) return 0.0;
   if(price>=bottom && price<=top) return 0.0;
   return MathMin(MathAbs(price-top),MathAbs(price-bottom))/atr;
}

void UpdateReverseRisk(double curClose, double atrValue, datetime barTime, double curHigh, double curLow)
{
   g_rrLevel="NONE"; g_rrLevelDist=0.0; g_rrLevelState="-";
   g_rrLegProg=0.0; g_rrDolDist=0.0; g_rrScore=0; g_rrReasons=""; g_rrLabel="LOW";
   g_rrEventBarsAgo=-1;
   g_rrHasRow=false;   // فاز ۴۶: فقط اگر تا انتها برسیم، شاهد ثبت می‌شود
   if(!InpEnableReverseRisk || atrValue<=0.0 || curClose<=0.0) return;

   // --- ۱) نزدیک‌ترین سطح به قیمت (نقدینگی / OB / FVG / S/D / رنج / خط روند) ---
   // اگر قیمت داخل چند ناحیه باشد، عمیق‌ترین/نزدیک‌ترین آن‌ها گزارش می‌شود.
   double best=1e18;
   for(int i=0;i<ArraySize(g_liquidity);i++)
   {
      double d=MathAbs(curClose-g_liquidity[i].price)/atrValue;
      if(d>=best) continue;
      best=d;
      g_rrLevel="LIQ "+LiqTypeLabel(g_liquidity[i].type);
      g_rrLevelState=RRLiqStateName(g_liquidity[i].state);
   }
   for(int i=0;i<ArraySize(g_obs);i++)
   {
      if(g_obs[i].state==OB_INVALID) continue;
      double d=RRAreaDist(curClose,g_obs[i].top,g_obs[i].bottom,atrValue);
      if(d>=best) continue;
      best=d;
      g_rrLevel=RRObKindName(g_obs[i]);
      g_rrLevelState=RRObStateName(g_obs[i].state);
   }
   for(int i=0;i<ArraySize(g_fvgs);i++)
   {
      if(g_fvgs[i].invalidated) continue;
      // ناحیهٔ زنجیره‌نشده جزء لایهٔ رسم نیست؛ اینجا هم به‌عنوان «نزدیک‌ترین سطح»
      // گزارش نمی‌شود تا با نمودار بخواند.
      if(!g_fvgs[i].causal) continue;
      double d=RRAreaDist(curClose,g_fvgs[i].top,g_fvgs[i].bottom,atrValue);
      if(d>=best) continue;
      best=d;
      // فاز ۴۳: همان قاعده برای گپ؛ اگر وارونه شده، در متن هم گفته می‌شود تا این
      // تک‌خطی با رنگ مربع روی چارت یک حرف بزند.
      g_rrLevel=RRFvgKindName(g_fvgs[i].kind)+((FVGActiveDir(g_fvgs[i])==DIR_BULL)? " (صعودی)":" (نزولی)")
               +(g_fvgs[i].inverted? " — وارونه‌شده":"");
      g_rrLevelState=(g_fvgs[i].inverted? "INVERTED":(g_fvgs[i].mitigated?
                     (g_fvgs[i].ceTouched? "CE لمس شده":"MITIGATED (لمس شده)")
                    :(g_fvgs[i].ceTouched? "CE لمس شده":"FRESH (دست‌نخورده)")));
   }
   for(int i=0;i<ArraySize(g_sd);i++)
   {
      if(g_sd[i].state==SDS_BROKEN) continue;
      double d=RRAreaDist(curClose,g_sd[i].top,g_sd[i].bottom,atrValue);
      if(d>=best) continue;
      best=d;
      g_rrLevel=RRSdKindName(g_sd[i].kind);
      g_rrLevelState=RRSdStateName(g_sd[i].state);
   }
   if(g_rangeOk && g_rangeHigh>g_rangeLow)
   {
      double dHigh=MathAbs(curClose-g_rangeHigh)/atrValue;
      double dLow =MathAbs(curClose-g_rangeLow)/atrValue;
      double d=MathMin(dHigh,dLow);
      if(d<best)
      {
         best=d;
         g_rrLevel="Range Liquidity "+(dHigh<=dLow? "(سقف رنج)":"(کف رنج)");
         g_rrLevelState="ACTIVE (رنج جاری)";
      }
   }
   for(int i=0;i<ArraySize(g_trendlines);i++)
   {
      if(g_trendlines[i].invalidated) continue;
      double lvl=TrendlinePriceAt(g_trendlines[i], barTime);
      if(lvl<=0.0) continue;
      double d=MathAbs(curClose-lvl)/atrValue;
      if(d>=best) continue;
      best=d;
      g_rrLevel=(g_trendlines[i].isHigh? "Trendline (Buy-Side بالای خط)":"Trendline (Sell-Side زیر خط)");
      g_rrLevelState=(g_trendlines[i].swept? "SWEPT (جارو شده)":"FRESH (دست‌نخورده)");
   }
   // --- فاز ۳۴: سطوح Auction Market Theory هم در «نزدیک‌ترین سطح» می‌آیند ---
   // چرا لازم است: برای این پرسش کاربر «این نقطه OB است یا لیکویدی یا چیز دیگر و
   // برگشت از کجا محتمل است»، IB/VA/TPO-POC/Naked POC/HVN دقیقاً همان سطوحی هستند
   // که برگشت از آن‌ها شمرده می‌شود. اگر در این اسکن نبودند، نزدیک‌ترین سطح می‌توانست
   // یک FVG دور باشد در حالی که قیمت روی IB ایستاده است.
   if(g_profileDaily.valid && g_profileDaily.amtValid)
   {
      double cand[8]; string cname[8]; string cstate[8];
      int nc=0;
      if(g_profileDaily.ibHi>g_profileDaily.ibLo)
      {
         cand[nc]=g_profileDaily.ibHi; cname[nc]="Initial Balance High"; cstate[nc]="IB (اولین "+IntegerToString(InpProfileIB_Minutes)+" دقیقهٔ روز)"; nc++;
         cand[nc]=g_profileDaily.ibLo; cname[nc]="Initial Balance Low";  cstate[nc]="IB (اولین "+IntegerToString(InpProfileIB_Minutes)+" دقیقهٔ روز)"; nc++;
      }
      if(g_profileDaily.tpoValid)
      {
         cand[nc]=g_profileDaily.tpoVah; cname[nc]="TPO VAH"; cstate[nc]="Value Area زمان‌محور"; nc++;
         cand[nc]=g_profileDaily.tpoVal; cname[nc]="TPO VAL"; cstate[nc]="Value Area زمان‌محور"; nc++;
         cand[nc]=g_profileDaily.tpoPoc; cname[nc]="TPO POC"; cstate[nc]="قیمت منصفانه (زمان‌محور)"; nc++;
      }
      if(g_profileDaily.hasNakedPoc)
      {
         cand[nc]=g_profileDaily.nakedPoc; cname[nc]="Naked/Virgin POC";
         cstate[nc]="لمس‌نشده از "+TimeToString(g_profileDaily.nakedPocDay,TIME_DATE); nc++;
      }
      for(int hh=0; hh<g_profileDaily.hvnCount && nc<8; hh++)
      { cand[nc]=g_profileDaily.hvn[hh]; cname[nc]="HVN"; cstate[nc]="گرهٔ پرحجم (مانع/آهنربا)"; nc++; }
      for(int ll=0; ll<g_profileDaily.lvnCount && nc<8; ll++)
      { cand[nc]=g_profileDaily.lvn[ll]; cname[nc]="LVN"; cstate[nc]="گرهٔ کم‌حجم (عبور سریع)"; nc++; }
      for(int k=0;k<nc;k++)
      {
         if(cand[k]<=0.0) continue;
         double dd=MathAbs(curClose-cand[k])/atrValue;
         if(dd>=best) continue;
         best=dd;
         g_rrLevel=cname[k];
         g_rrLevelState=cstate[k];
      }
   }
   g_rrLevelDist=(best<1.0e17)? best : 0.0;

   // --- ۲) «طلا تا کجا رفت»: قیمت در کجای لگ معامله‌گری است ---
   if(g_leg.valid && g_leg.high>g_leg.low)
   {
      double span=g_leg.high-g_leg.low;
      double pos=(curClose-g_leg.low)/span;          // ۰ = کف لگ، ۱ = سقف لگ
      g_rrLegProg=(g_leg.dir==DIR_BEAR? (1.0-pos) : pos)*100.0;
      if(g_rrLegProg<0.0) g_rrLegProg=0.0;
      if(g_rrLegProg>100.0) g_rrLegProg=100.0;
   }

   // --- ۳) فاصله تا هدف نقدینگی (DOL) ---
   if(g_hasDOL && g_currentDOL.price>0.0)
      g_rrDolDist=((g_currentDOL.direction==DIR_BULL)? (g_currentDOL.price-curClose)
                                                        : (curClose-g_currentDOL.price))/atrValue;

   // --- ۴) آخرین رویداد ساختاری چند کندل پیش بود؟ ---
   if(ArraySize(g_events)>0)
   {
      int sec=PeriodSeconds(PERIOD_CURRENT);
      if(sec<=0) sec=60;
      long diff=(long)barTime-(long)g_events[ArraySize(g_events)-1].time;
      if(diff>=0) g_rrEventBarsAgo=(int)(diff/sec);
   }

   // --- ۵) امتیاز هشدار برگشت (وزن‌ها مستند؛ این عدد «درصد» نیست) ---
   int score=0; string why="";
   if(g_barSweptTowardBias)
   { score+=25; why+="+۲۵ نقدینگیِ سمت بایاس جارو شد و کندل پشت سطح بست — "; }
   if(g_rrEventBarsAgo>=0 && g_rrEventBarsAgo<=InpReversalFreshBars)
   { score+=20; why+=StringFormat("+۲۰ آخرین رویداد ساختاری %d کندل پیش بود (کاراکتر تازه عوض شده) — ", g_rrEventBarsAgo); }
   if(g_exhaustion.state==EXH_WATCH || g_exhaustion.state==EXH_MICRO_PULLBACK ||
      g_exhaustion.state==EXH_RANGE_TRANSITION || g_exhaustion.state==EXH_EXTENDING)
   { score+=15; why+="+۱۵ فرسودگی روند: قدرت ادامه ضعیف شده — "; }
   if(g_rrLegProg>=85.0)
   { score+=15; why+=StringFormat("+۱۵ قیمت در %.0f%% انتهای لگ است (نقطهٔ برگشت بالقوه) — ", g_rrLegProg); }
   if(g_leg.valid)
   {
      if(g_htfBias==DIR_BULL && curClose>g_leg.eq)
      { score+=10; why+="+۱۰ بایاس صعودی ولی قیمت در نیمهٔ گران لگ است (ورود دیرهنگام) — "; }
      if(g_htfBias==DIR_BEAR && curClose<g_leg.eq)
      { score+=10; why+="+۱۰ بایاس نزولی ولی قیمت در نیمهٔ ارزان لگ است (ورود دیرهنگام) — "; }
   }
   if(g_hasDOL && g_rrDolDist<=0.5)
   { score+=15; why+=StringFormat("+۱۵ هدف نقدینگی تقریباً پر شد (فاصله %.2f برابر میانگین دامنه) — ", g_rrDolDist); }
   if(!g_mtfConflict)
   { score-=10; why+="−۱۰ همهٔ تایم‌فریم‌ها هم‌جهت بایاس هستند (ادامه محتمل‌تر) — "; }
   if(score<0) score=0;
   if(score>100) score=100;
   g_rrScore=score;
   g_rrLabel=(score>=75)? "EXTREME" : ((score>=50)? "HIGH" : ((score>=25)? "MEDIUM" : "LOW"));
   g_rrReasons=why;

   // --- ۶) آماده‌سازی شاهد برای ثبت در CSV ---
   // فاز ۴۶: خودِ نوشتن به تابع جداگانه منتقل شد، چون درجهٔ سیگنال *بعد* از
   // فرسودگی همان کندل محاسبه می‌شود. اگر اینجا نوشته می‌شد، ستون‌های درجه
   // همیشه از کندل قبلی می‌آمدند و فایل شاهد تبدیل به شاهد دروغ می‌شد.
   g_rrHasRow = InpWriteReverseRisk;
   g_rrBarTime=barTime; g_rrClose=curClose; g_rrHigh=curHigh; g_rrLow=curLow; g_rrAtr=atrValue;
}

// ثبت یک ردیف شاهد از آخرین کندل بسته — دقیقاً یک‌بار در هر کندل، پس از
// محاسبهٔ درجه. محاسبهٔ هیچ عددی اینجا نیست؛ فقط همان مقادیر ذخیره‌شده.
void PersistReverseRiskEvidence()
{
   if(!g_rrHasRow) return;
   // فاز ۴۷: تایم‌فریم در نام فایل. چرا: تا فاز ۴۶ نام فقط نماد داشت، پس دو
   // چارت زندهٔ یک نماد (M1 و M15) ردیف‌هایشان را در یک فایل می‌ریختند و هر
   // سنجشی که از این دفتر می‌خواند (فیت درجه و فیت سناریوی در انتظار) ناخواسته
   // دو تایم‌فریم را قاطی می‌کرد. کاربر خواسته است هر تایم‌فریم برای خودش باشد.
   int h=DiagOpen("ICT_Assistant_Canonical_ReverseRisk_"+_Symbol+"_"+ChartTfCode()+".csv");
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0)
      FileWrite(h,"BarTime","Bias","Price","High","Low","ATR",
                "LevelType","LevelDistATR","LevelState",
                "LegProgressPct","DOLType","DOLDistATR",
                "Exhaustion","SweptTowardBias","EventBarsAgo","MTFAligned",
                "RiskScore","RiskLabel","Reasons",
                // فاز ۴۶: شاهد درجه. ستون‌های اضافه در انتها می‌آیند تا ابزارهای
                // قدیمی که ستون‌های ۱ تا ۱۹ را می‌خوانند دست‌نخورده بمانند.
                "LevelFamily","Grade","GradeScore","GradeWinPct","GradeN",
                // فاز ۴۷: تایم‌فریم چارت هم ستون می‌شود (دو لایه: نام فایل و ستون)
                // تا هر ردیف خودش بگوید از کدام تایم‌فریم آمده است.
                "ChartTF");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,
             TimeToString(g_rrBarTime,TIME_DATE|TIME_MINUTES),
             DirToStr(g_htfBias),
             DoubleToString(g_rrClose,_Digits),
             DoubleToString(g_rrHigh,_Digits),
             DoubleToString(g_rrLow,_Digits),
             DoubleToString(g_rrAtr,_Digits),
             g_rrLevel,
             DoubleToString(g_rrLevelDist,2),
             g_rrLevelState,
             DoubleToString(g_rrLegProg,1),
             (g_hasDOL? g_currentDOL.typeName : "NONE"),
             DoubleToString(g_rrDolDist,2),
             ExhaustionStateToStr(g_exhaustion.state),
             (g_barSweptTowardBias? "true":"false"),
             g_rrEventBarsAgo,
             (g_mtfConflict? "false":"true"),
             g_rrScore,
             g_rrLabel,
             g_rrReasons,
             g_gradeFam,
             g_grade,
             DoubleToString(g_gradeScore,3),
             DoubleToString(g_gradeWin,1),
             g_gradeN,
             ChartTfCode());
   DiagClose(h);
}

//====================================================================
// HTF ENGINE — رفع ایراد ۳،۴: تفکیک Confirmed Pivot از Protected
// Structure. Protected High/Low فقط بعد از این‌که یک BOS/CHoCH/MSS
// روی HTF آن سویینگ مقابل را "محافظت‌شده" اعلام کند تنظیم می‌شود،
// نه صرفاً آخرین Pivot تاییدشده.
//====================================================================
void UpdateHTFStructure(datetime barTime)
{
   // دادهٔ HTF «در زمان همین کندل» خوانده می‌شود، نه آخرین دادهٔ بازار
   MqlRates htfRates[];
   int htfCopied = CopyRatesAsOf(_Symbol, InpHTF, barTime, InpSwingLeft+InpSwingRight+80, htfRates);
   if(htfCopied < InpSwingLeft+InpSwingRight+10) return;

   //------------------------------------------------------------------
   // فاز ۱۳ (#۷): «هر کندل HTF حداکثر یک ارزیابی ساختار»
   //
   // چرا لازم است: این تابع از UpdateContextForClosedBar و در نتیجه در هر
   // کندل بستهٔ چارت (LTF) صدا زده می‌شود. بدون این نگهبان، بعد از این‌که
   // EvaluateStructureBreak یک سویینگ را broken می‌کند، فراخوانی بعدی در همان
   // کندل HTF همان close را با سویینگ قدیمی‌تر مقایسه می‌کند و یک BOS/CHoCH
   // تکراری روی همان کندل H4 ثبت می‌شود.
   //
   // چرا کل بدنه (نه فقط فراخوانی ارزیابی) محافظت می‌شود: در همان کندل HTF
   // نه پیوت تازه‌ای تأیید می‌شود (confirmIndex = InpSwingRight ثابت است)
   // و نه وضعیت «پیش از ارزیابی» می‌تواند عوض شود؛ پس تصویر لحظه‌ای دروازهٔ
   // برگشت هم باید همان مقدار اولین فراخوانی همان کندل بماند تا هر LTF bar
   // در همان کندل، برگشت را روی یک عدد یکسان بسنجد.
   //------------------------------------------------------------------
   if(htfRates[0].time==g_lastHtfEvalBarTime)
   {
      g_htfEvalSkips++;
      return;
   }
   g_lastHtfEvalBarTime = htfRates[0].time;
   g_lastHtfEvalStamp   = barTime;
   g_htfEvalRuns++;

   double hHigh[], hLow[], hClose[];
   ArrayResize(hHigh, htfCopied);
   ArrayResize(hLow,  htfCopied);
   ArrayResize(hClose,htfCopied);
   for(int i=0;i<htfCopied;i++)
   {
      hHigh[i] =htfRates[i].high;
      hLow[i]  =htfRates[i].low;
      hClose[i]=htfRates[i].close;
   }
   int total = htfCopied;

   int pivotShift = InpSwingRight; // آخرین pivot که right-side confirmation دارد
   if(IsConfirmedPivotHigh(hHigh, pivotShift, InpSwingLeft, InpSwingRight, total))
   {
      SwingPoint s; s.time=htfRates[pivotShift].time; s.price=hHigh[pivotShift];
      s.isHigh=true; s.confirmed=true; s.broken=false; s.id=StableSwingId(s.time,s.isHigh);
      PushSwing(g_swingsHTF, s, InpMaxSwings);
      RegisterSwingLiquidity(s, true);
   }
   if(IsConfirmedPivotLow(hLow, pivotShift, InpSwingLeft, InpSwingRight, total))
   {
      SwingPoint s; s.time=htfRates[pivotShift].time; s.price=hLow[pivotShift];
      s.isHigh=false; s.confirmed=true; s.broken=false; s.id=StableSwingId(s.time,s.isHigh);
      PushSwing(g_swingsHTF, s, InpMaxSwings);
      RegisterSwingLiquidity(s, true);
   }

   // --- فاز ۱۱ (#۸/#۷۱): تصویر لحظه‌ای دروازهٔ برگشت، *پیش از* ارزیابی ساختار ---
   // EvaluateStructureBreak می‌تواند در همین کندل Bias مالک را عوض کند و در
   // نتیجه شناسهٔ سطح محافظت‌شده را جایگزین کند. پس سطح محافظت‌شده‌ای که
   // برگشت باید نسبت به آن سنجیده شود، از وضعیت *قبل از* این ارزیابی برداشته
   // می‌شود؛ وگرنه برگشت هرگز روی سطح درست سنجیده نمی‌شود.
   {
      double gp=0.0; datetime gt=0; bool gh=false;
      g_reversal.snapBias          = g_htfBias;
      g_reversal.snapGuardId       = (g_htfBias==DIR_BULL)? g_htfProtectedLowId
                                   : (g_htfBias==DIR_BEAR)? g_htfProtectedHighId : -1;
      g_reversal.snapGuardOk       = SwingById(g_swingsHTF, g_reversal.snapGuardId, gp, gt, gh);
      g_reversal.snapGuardPrice    = g_reversal.snapGuardOk? gp : 0.0;
      g_reversal.snapGuardLevelTime= gt;
      g_reversal.snapGuardIsHigh   = gh;
      g_reversal.snapBarTime       = htfRates[0].time;
      g_reversal.snapBarClose      = htfRates[0].close;
   }

   // Structure Engine روی HTF (بدون displacement candidate جدا؛ -1 پاس می‌دهیم،
   // یعنی BOS/CHoCH ساده تشخیص داده می‌شود؛ MSS واقعی وقتی رخ می‌دهد که در
   // آینده Displacement HTF هم اضافه شود)
   // Break is evaluated on the latest completed H4 bar, not on the pivot
   // confirmation bar used to populate the registry.
   EvaluateStructureBreak(hClose, 0, true, g_swingsHTF, g_htfBias, -1, -1, htfRates[0].time);

   // --- Protected Structure واقعی ---
   // به‌جای "آخرین پیوت تاییدشده"، آخرین Eventِ HTF را می‌گیریم و
   // protectedSwingId آن Event را به‌عنوان Protected ثبت می‌کنیم.
   int ne = ArraySize(g_events);
   for(int i=ne-1;i>=0;i--)
   {
      if(!g_events[i].isHTF) continue;
      if(g_events[i].direction==DIR_BULL) g_htfProtectedLowId  = g_events[i].protectedSwingId;
      if(g_events[i].direction==DIR_BEAR) g_htfProtectedHighId = g_events[i].protectedSwingId;
      break;
   }

   // فاز ۱۱ (#۸/#۷۱): همان شناسه‌ها به قیمت واقعی تبدیل می‌شوند. تابه‌حال
   // این خط وجود نداشت، پس Protected High/Low روی چارت رسم می‌شد ولی
   // دروازهٔ برگشت هیچ عددیش نداشت.
   {
      double p=0.0; datetime t=0; bool isHigh=false;
      g_htfProtectedLowPrice  = SwingById(g_swingsHTF, g_htfProtectedLowId,  p,t,isHigh) ? p : 0.0;
      g_htfProtectedHighPrice = SwingById(g_swingsHTF, g_htfProtectedHighId, p,t,isHigh) ? p : 0.0;
   }
}

//====================================================================
// SESSION ENGINE — رفع ایراد ۱۷: Session فقط Context است، سیگنال نمی‌سازد
//====================================================================
//====================================================================
// SESSION / KILLZONE ENGINE — پنجره‌های واقعی ICT به وقت نیویورک،
// محاسبه‌شده از زمان کندل (نه TimeCurrent) و مستقل از تایم‌فریم چارت.
//   Asian KZ          20:00 - 00:00 NY
//   London KZ         02:00 - 05:00 NY  (Judas Swing / Manipulation)
//   NY AM KZ          07:00 - 10:00 NY
//   London Close KZ   10:00 - 12:00 NY
//   NY PM KZ          13:30 - 16:00 NY
//   Silver Bullet      03:00-04:00 | 10:00-11:00 | 14:00-15:00 NY
//   Power of 3        Asia=Accumulation, London=Manipulation, NY=Distribution
//====================================================================
void UpdateSessionContext(datetime barTime)
{
   MqlDateTime ny; NYStampOf(barTime, ny);
   g_hourNYNow = ny.hour;
   g_minNYNow  = ny.min;
   g_nyOffsetHoursNow = NY_GMTOffsetHours(barTime);
   int minutes = ny.hour*60 + ny.min;

   // پنجره‌ها از ورودی‌ها خوانده می‌شوند (رفع #۵۰): قبلاً همین ساعت‌ها هاردکد
   // بودند و ۶ ورودی پنل هیچ اثری نداشتند.
   g_currentSession = SESS_NONE;
   if(InNYWindow(minutes, InpAsiaStartHourNY,0, InpAsiaEndHourNY,0))
      g_currentSession = SESS_ASIA;
   if(InNYWindow(minutes, InpLondonStartHourNY,0, InpLondonEndHourNY,0))
      g_currentSession = SESS_LONDON;
   if(InNYWindow(minutes, InpNY_KZ_StartHourNY,0, InpNY_KZ_EndHourNY,0))
      g_currentSession = SESS_NY_AM;
   if(InNYWindow(minutes, InpLondonCloseStartHourNY,0, InpLondonCloseEndHourNY,0))
      g_currentSession = SESS_LONDON_CLOSE;
   if(InNYWindow(minutes, InpNYPM_StartHourNY,InpNYPM_StartMinuteNY, InpNYPM_EndHourNY,InpNYPM_EndMinuteNY))
      g_currentSession = SESS_NY_PM;

   g_currentAMD = AMD_NONE;
   if(g_currentSession==SESS_ASIA)   g_currentAMD = AMD_ACCUMULATION;
   if(g_currentSession==SESS_LONDON) g_currentAMD = AMD_MANIPULATION;
   if(g_currentSession==SESS_NY_AM || g_currentSession==SESS_NY_PM) g_currentAMD = AMD_DISTRIBUTION;

   // --- فاز ۳۶: AMD قیمتی (مکمل نگاشت زمانی) ---
   // منبع (ICT Power of Three؛ همان AMD-X در QT): A = رنج تنگ آسیا؛
   // M = سوئپ/Judas (فتیله بیرون رنج آسیا + بستهٔ برگشتی)؛ D = حرکت انبساطی
   // در جهت مخالف سوئپ. اگر سوئپ رخ نداده باشد، فقط A را اعلام می‌کنیم و
   // M/D را «در انتظار» می‌گذاریم — نه تفسیرِ پس از رویداد.
   g_amdPriceStage=AMD_NONE; g_amdPriceNote="";
   if(g_asiaHigh>g_asiaLow)
   {
      g_amdPriceStage=AMD_ACCUMULATION;
      // سوئپManipulation: فتیلهٔ امروز (در همان روز) بیرون رنج آسیا رفته و کندل داخل بسته
      datetime dayStart=0,dayEnd=0; double dH=0,dL=0; int dCnt=0;
      if(WindowForDayBack(0,0,0,0,0,barTime,dayStart,dayEnd,dH,dL,dCnt,true) && dayStart>0)
      {
         // سوئپ بالای رنج آسیا (BSL) = Manipulation صعودی → Distribution نزولی
         double hi=0, lo=0;
         if(CollectWindowRange(PERIOD_CURRENT, dayStart, g_asiaEnd, hi, lo, dCnt) && hi>0)
         {
            if(hi>g_asiaHigh)
            {
               g_amdPriceStage=AMD_MANIPULATION;
               g_amdPriceNote=StringFormat("M | تأیید دستکاری: فتیلهٔ روز تا %.2f بیرون سقف آسیا (%.2f) — اگر برگشت و کندل جابه‌جایی نزولی بیاید، توزیع نزولی و ورود فروش", hi, g_asiaHigh);
               if(CollectWindowRange(PERIOD_CURRENT, dayStart, barTime, hi, lo, dCnt) && lo<g_asiaLow)
               { g_amdPriceStage=AMD_DISTRIBUTION; g_amdPriceNote=StringFormat("D تأیید: بعد از سوئپ بالا، قیمت تا %.2f پایین کف آسیا (%.2f) رفته — لگ توزیع نزولی در جریان است", lo, g_asiaLow); }
            }
            else if(lo<g_asiaLow)
            {
               g_amdPriceStage=AMD_MANIPULATION;
               g_amdPriceNote=StringFormat("M | تأیید دستکاری: فتیلهٔ روز تا %.2f بیرون کف آسیا (%.2f) — اگر برگشت و کندل جابه‌جایی صعودی بیاید، توزیع صعودی و ورود خرید", lo, g_asiaLow);
            }
            else g_amdPriceNote="A | انباشت فعال: قیمت داخل رنج آسیا است و دستکاری هنوز رخ نداده؛ هیچ الزامی به معامله نیست";
         }
      }
   }

   g_silverBullet = SB_NONE;
   if(InNYWindow(minutes, InpSB1_StartHourNY,0, InpSB1_EndHourNY,0)) g_silverBullet = SB_LONDON;
   if(InNYWindow(minutes, InpSB2_StartHourNY,0, InpSB2_EndHourNY,0)) g_silverBullet = SB_NY_AM;
   if(InNYWindow(minutes, InpSB3_StartHourNY,0, InpSB3_EndHourNY,0)) g_silverBullet = SB_NY_PM;

   // --- فاز ۳۶: Quarterly Theory (Daye) — ربع‌های روز و هفته، ساعت نیویورک ---
   // روز: Q1 18–24 · Q2 00–06 · Q3 06–12 · Q4 12–18 (منبع: arongroups — QT)
   g_qtDayPhase=QT_NONE;
   if(minutes>=18*60 || minutes<0)              g_qtDayPhase=QT_Q1_ACCUM;
   else if(minutes<6*60)                        g_qtDayPhase=QT_Q2_MANIP;
   else if(minutes<12*60)                       g_qtDayPhase=QT_Q3_DISTRIB;
   else                                         g_qtDayPhase=QT_Q4_REVERSAL;
   // هفته: دوشنبه=Q1 · سه‌شنبه=Q2 · چهارشنبه=Q3 · پنجشنبه=Q4
   // (روایت اصلی منبع؛ جمعه = ادامهٔ Q4 — صادقانه در Explain گفته می‌شود)
   MqlDateTime nyW; NYStampOf(barTime, nyW);
   g_qtWeekPhase=QT_NONE;
   if(nyW.day_of_week>=1 && nyW.day_of_week<=4)
      g_qtWeekPhase=(ENUM_QT_PHASE)(nyW.day_of_week);   // 1..4 → QT_Q1..QT_Q4 (مقادیر enum یکی‌اند)
   else if(nyW.day_of_week==5)                  g_qtWeekPhase=QT_Q4_REVERSAL;
   // True Open روز = قیمت بازِ کندلی که ساعت NY آن 00:00 است
   if(g_hourNYNow==0 && g_minNYNow<60 && (g_qtDayTrueOpenT==0 ||
      (long)NYWallToServer(nyW.year,nyW.mon,nyW.day,0,0,0)-(long)g_qtDayTrueOpenT>=86400))
   {
      double to[1];
      datetime wStart=NYWallToServer(nyW.year,nyW.mon,nyW.day,0,0,0);
      if(CopyOpen(_Symbol,PERIOD_CURRENT,wStart,1,to)==1 && to[0]>0.0)
      { g_qtDayTrueOpen=to[0]; g_qtDayTrueOpenT=wStart; }
   }
   // True Open هفته = اولین کندل بعد از دوشنبه 00:00 NY (قیمت باز)
   if(g_qtWkTrueOpenT==0)
   {
      // جست‌وجوی عقب‌گرد تا ۱۰ روز: اولین دوشنبه‌ای که کندلش موجود است
      MqlDateTime probe=nyW;
      for(int backD=0; backD<10 && g_qtWkTrueOpenT==0; backD++)
      {
         MqlDateTime pd; datetime pT=(datetime)((long)barTime-(long)backD*86400);
         TimeToStruct(pT,pd);
         if(pd.day_of_week!=1) continue;
         datetime wOpen=NYWallToServer(pd.year,pd.mon,pd.day,0,0,0);
         double to2[1];
         if(CopyOpen(_Symbol,PERIOD_CURRENT,wOpen,1,to2)==1 && to2[0]>0.0)
         { g_qtWkTrueOpen=to2[0]; g_qtWkTrueOpenT=wOpen; }
      }
   }

   // ساختار داخلی روی تایم‌فریم InpMTF (رفع #۶۱: این ورودی قبلاً هیچ مصرفی نداشت)
   g_mtfInternalDir = InternalDirectionAsOf(barTime, InpMTF, g_mtfInternalBarTime);

   // رنج سشن‌ها: آخرین پنجرهٔ کامل‌شده (مثال: Asian Range هدف نقدینگی لندن است)
   if(FindLastClosedWindow(InpAsiaStartHourNY,0, InpAsiaEndHourNY,0, barTime, g_asiaStart, g_asiaEnd, g_asiaHigh, g_asiaLow))
   {
      AddLiquidity(LIQ_SESSION_H, SCOPE_INTERNAL, g_asiaHigh, g_asiaStart, false);
      AddLiquidity(LIQ_SESSION_L, SCOPE_INTERNAL, g_asiaLow,  g_asiaStart, false);
   }
   if(FindLastClosedWindow(InpLondonStartHourNY,0, InpLondonEndHourNY,0, barTime, g_londonStart, g_londonEnd, g_londonHigh, g_londonLow))
   {
      AddLiquidity(LIQ_SESSION_H, SCOPE_INTERNAL, g_londonHigh, g_londonStart, false);
      AddLiquidity(LIQ_SESSION_L, SCOPE_INTERNAL, g_londonLow,  g_londonStart, false);
   }
   if(FindLastClosedWindow(InpNY_KZ_StartHourNY,0, InpNY_KZ_EndHourNY,0, barTime, g_nyAmStart, g_nyAmEnd, g_nyAmHigh, g_nyAmLow))
   {
      AddLiquidity(LIQ_SESSION_H, SCOPE_INTERNAL, g_nyAmHigh, g_nyAmStart, false);
      AddLiquidity(LIQ_SESSION_L, SCOPE_INTERNAL, g_nyAmLow,  g_nyAmStart, false);
   }
}

//====================================================================
// LEG ENGINE (فاز ۱۰ / #۴۳) — «دامنهٔ معامله‌گری» از لگ واقعی ساخته می‌شود.
// قبلاً آخرین سقف تأییدشده و آخرین کف تأییدشده مستقل از هم برداشته
// می‌شدند و می‌توانستند به دو لگ مختلف (یا حتی برعکس ترتیب زمانی) تعلق
// داشته باشند؛ نتیجه یک رنج کاذب و EQ غلط بود.
// اکنون: پیوت‌های تأییدشدهٔ H4 به ترتیب زمان و به‌صورت **تناوبی** ساخته
// می‌شوند (سقف/کف یکی‌درمیان) و دو پیوت آخر همان لگ واقعی است؛ همان دو
// نقطه‌ای که کاربر می‌تواند فیبوی دستی را روی آن بگذارد.
//====================================================================
void UpdateDealingLeg(datetime barTime, double atrValue)
{
   g_leg.valid=false;
   g_leg.dir=DIR_NONE;
   g_leg.low=0; g_leg.high=0; g_leg.lowTime=0; g_leg.highTime=0;
   g_leg.startTime=0; g_leg.endTime=0; g_leg.startPrice=0; g_leg.endPrice=0;
   g_leg.range=0; g_leg.eq=0; g_leg.sizeATR=0;
   g_leg.reject="";

   MqlRates rates[];
   int copied=CopyRatesAsOf(_Symbol, g_mtfTimeframes[0], barTime, 300, rates);
   if(copied < InpSwingLeft+InpSwingRight+12)
   { g_leg.reject="H4_DATA_NOT_READY"; return; }

   // پیوت‌های تأییدشده، از قدیم به جدید (index 0 در سری = جدیدترین کندل)
   SwingPoint pivots[];
   int total=ArraySize(rates);
   for(int shift=total-InpSwingLeft-1; shift>=InpSwingRight; shift--)
   {
      bool isHigh=true, isLow=true;
      for(int side=1; side<=InpSwingLeft; side++)
      {
         if(rates[shift].high<=rates[shift+side].high) isHigh=false;   // چپ/قدیمی: اکید
         if(rates[shift].low >=rates[shift+side].low ) isLow=false;
      }
      for(int side=1; side<=InpSwingRight; side++)
      {
         // راست/جدید: مساوی‌پذیر (فاز ۲۲ — Double Top/EQH پیوت می‌سازند)
         if(shift-side<0 || rates[shift].high<rates[shift-side].high) isHigh=false;
         if(shift-side<0 || rates[shift].low >rates[shift-side].low ) isLow=false;
      }
      if(isHigh)
      {
         SwingPoint p; p.time=rates[shift].time; p.price=rates[shift].high;
         p.isHigh=true; p.confirmed=true; p.broken=false; p.id=0;
         int n=ArraySize(pivots); ArrayResize(pivots,n+1); pivots[n]=p;
      }
      if(isLow)
      {
         SwingPoint p; p.time=rates[shift].time; p.price=rates[shift].low;
         p.isHigh=false; p.confirmed=true; p.broken=false; p.id=0;
         int n=ArraySize(pivots); ArrayResize(pivots,n+1); pivots[n]=p;
      }
   }

   // فیلتر تناوبی: دو سقف/کف پشت‌سرهم مجاز نیست؛ اکسترمم‌تر جایگزین می‌شود
   SwingPoint seq[];
   for(int i=0;i<ArraySize(pivots);i++)
   {
      int n=ArraySize(seq);
      if(n==0){ ArrayResize(seq,1); seq[0]=pivots[i]; continue; }
      if(seq[n-1].isHigh==pivots[i].isHigh)
      {
         bool moreExtreme = pivots[i].isHigh ? (pivots[i].price>seq[n-1].price)
                                             : (pivots[i].price<seq[n-1].price);
         if(moreExtreme) seq[n-1]=pivots[i];
      }
      else
      {
         ArrayResize(seq,n+1); seq[n]=pivots[i];
      }
   }

   int ns=ArraySize(seq);
   if(ns<2){ g_leg.reject="NOT_ENOUGH_ALTERNATING_PIVOTS"; return; }

   SwingPoint p1=seq[ns-2];   // پیوت آغاز لگ
   SwingPoint p2=seq[ns-1];   // پیوت پایان لگ
   g_leg.startTime=p1.time;  g_leg.startPrice=p1.price;
   g_leg.endTime=p2.time;    g_leg.endPrice=p2.price;
   g_leg.low  = MathMin(p1.price,p2.price);
   g_leg.high = MathMax(p1.price,p2.price);
   if(p1.isHigh){ g_leg.highTime=p1.time; g_leg.lowTime=p2.time; }
   else         { g_leg.highTime=p2.time; g_leg.lowTime=p1.time; }
   g_leg.dir = p2.isHigh ? DIR_BULL : DIR_BEAR;   // پایان لگ روی سقف = لگ صعودی
   g_leg.range = g_leg.high-g_leg.low;
   if(g_leg.range<=0.0){ g_leg.reject="ZERO_RANGE"; return; }
   g_leg.eq = g_leg.low + g_leg.range*0.5;
   g_leg.sizeATR = (atrValue>0.0) ? g_leg.range/atrValue : 0.0;
   if(InpMinLegATR>0.0 && atrValue>0.0 && g_leg.sizeATR<InpMinLegATR)
   { g_leg.reject="LEG_TOO_SMALL"; return; }
   g_leg.valid=true;
}

// وزن نوع سطح نقدینگی در امتیازدهی DOL (#۴۸)
int LiqTypeWeight(ENUM_LIQ_TYPE t)
{
   switch(t)
   {
      case LIQ_PDH: case LIQ_PDL: case LIQ_PWH: case LIQ_PWL: return 15;
      case LIQ_EQH: case LIQ_EQL:                             return 12;
      case LIQ_SESSION_H: case LIQ_SESSION_L:                 return 9;
      case LIQ_SWING_H:   case LIQ_SWING_L:                   return 6;
   }
   return 0;
}

//====================================================================
// DOL ENGINE — فاز ۱۰ / #۴۸: امتیازدهی چندمعیاره با تفکیک عددی،
// نه وزن ثابت. حالا یک Internal نزدیک می‌تواند از یک External خیلی دور
// جلو بزند، و سطحی که R:R واقعی نمی‌سازد از ابتدا رد می‌شود.
//====================================================================
void UpdateDOL(double curClose, double atrValue)
{
   g_hasDOL = false;
   g_dolRejectReason="";
   if(g_htfBias==DIR_NONE) return;

   double atr = (atrValue>0.0)? atrValue : 0.0;
   long bestId=-1; double bestScore=-1e9; double bestPrice=0;
   ENUM_LIQ_SCOPE bestScope=SCOPE_INTERNAL; bool bestIsHTF=false;
   ENUM_LIQ_TYPE bestType=LIQ_SWING_H; double bestDistAtr=0;
   int considered=0, rejectedRoom=0;

   int n=ArraySize(g_liquidity);
   for(int i=0;i<n;i++)
   {
      if(g_liquidity[i].state!=LSTATE_FRESH) continue;
      bool isHighType = IsHighSideLiquidity(g_liquidity[i].type);
      // فقط جهت هم‌راستا با HTF Bias را در نظر می‌گیریم (رفع "نزدیک‌ترین بی‌جهت")
      if(g_htfBias==DIR_BULL && !isHighType) continue;
      if(g_htfBias==DIR_BEAR && isHighType) continue;

      double dist    = MathAbs(g_liquidity[i].price - curClose);
      double distAtr = (atr>0.0) ? dist/atr : 0.0;

      // اگر هدف خیلی نزدیک باشد، از فاصلهٔ واقعی ورود تا SL هیچ R:R درستی
      // ساخته نمی‌شود؛ پس این سطح به‌عنوان DOL معامله‌پذیر رد می‌شود (#۴۸/#۶۶).
      if(atr>0.0 && InpDOL_MinRoomATR>0.0 && distAtr<InpDOL_MinRoomATR)
      { rejectedRoom++; continue; }

      considered++;
      double score=0.0;
      if(g_liquidity[i].scope==SCOPE_EXTERNAL) score += 30.0;   // سلسله‌مراتب: External ارجح
      if(g_liquidity[i].isHTF)                 score += 10.0;   // سطح HTF وزن بیشتر
      score += (double)LiqTypeWeight(g_liquidity[i].type);       // کیفیت نوع سطح
      if(g_internalDir==g_htfBias)             score += 10.0;   // هم‌راستایی ساختار داخلی
      if(atr>0.0 && InpDOL_FarATR>0.0)
      {
         double prox = 1.0 - MathMin(distAtr,InpDOL_FarATR)/InpDOL_FarATR; // نزدیک‌تر = بالاتر
         score += 25.0*prox;
      }

      if(score>bestScore)
      {
         bestScore=score; bestId=g_liquidity[i].id; bestPrice=g_liquidity[i].price;
         bestScope=g_liquidity[i].scope; bestIsHTF=g_liquidity[i].isHTF;
         bestType=g_liquidity[i].type; bestDistAtr=distAtr;
      }
   }

   if(bestId==-1)
   {
      // Phase 42: no Latin token inside the Persian clause - ATR and FRESH are
      // spelled out, because this string is printed as a sentence in the panel.
      g_dolRejectReason = (rejectedRoom>0)
         ? StringFormat("همهٔ %d سطح هم‌جهت نزدیک‌تر از حداقل %.2f برابر میانگین دامنه بودند؛ نسبت سود به ریسک واقعی ساخته نمی‌شد", rejectedRoom, InpDOL_MinRoomATR)
         : "سطح نقدینگی هم‌جهت با بایاس و دست‌نخورده وجود ندارد";
      return;
   }

   g_currentDOL.liquidityId = bestId;
   g_currentDOL.price = bestPrice;
   g_currentDOL.direction = g_htfBias;
   g_currentDOL.htfAligned = bestIsHTF;
   g_currentDOL.structureAligned = (g_internalDir==g_htfBias);
   // از state واقعی سطح خوانده می‌شود، نه هاردکد true (#۴۸)
   g_currentDOL.sweepStateOk = true;   // شرط حلقه: فقط LSTATE_FRESH به اینجا می‌رسد
   g_currentDOL.hierarchyOk = (bestScope==SCOPE_EXTERNAL);
   g_currentDOL.score = (int)MathRound(bestScore);
   g_currentDOL.distATR = bestDistAtr;
   g_currentDOL.typeName = LiqTypeLabel(bestType);
   int wScope=(bestScope==SCOPE_EXTERNAL)?30:0;
   int wHTF=bestIsHTF?10:0;
   int wType=LiqTypeWeight(bestType);
   int wStruct=(g_internalDir==g_htfBias)?10:0;
   int wProx=0;
   if(atr>0.0 && InpDOL_FarATR>0.0)
      wProx=(int)MathRound(25.0*(1.0 - MathMin(bestDistAtr,InpDOL_FarATR)/InpDOL_FarATR));
   g_currentDOL.breakdown = StringFormat("EXTERNAL %d + HTF %d + TYPE %d + STRUCT %d + PROX %d = %d",
                                         wScope,wHTF,wType,wStruct,wProx,g_currentDOL.score);
   g_currentDOL.narrative = StringFormat("DOL | انتخاب از نوع %s | فاصله %.2f برابر میانگین دامنه | %d سطح بررسی شد | تفکیک: %s",
                                         g_currentDOL.typeName, bestDistAtr, considered, g_currentDOL.breakdown);
   g_hasDOL = true;
}

//====================================================================
// SETUP ENGINE — رفع ایراد ۱۶ (پیش‌نیاز Dashboard واقعی): از روی
// زنجیره واقعی Sweep->MSS->Displacement->FVG->OB تصمیم می‌گیرد، نه
// جدا از Core.
//====================================================================
// ناحیهٔ ورود روی تایم‌فریم SETUP (پیش‌فرض M5) — #۶۶ بند ۴:
// قبلاً ناحیه همیشه از تایم‌فریم چارت انتخاب می‌شد (مثلاً M15) درحالی‌که
// نقش SETUP در زنجیرهٔ MTF مال M5 است و ریزترین ناحیه هم همان‌جاست.
// الگو: FVG سه‌کندلی استاندارد؛ ناحیه‌ای که از سمت مخالف بسته شده باشد
// (کاملاً رد شده) دیگر معتبر نیست.
bool FindSetupTFZone(datetime asOfBarTime, ENUM_DIRECTION dir,
                     double &top, double &bottom, datetime &zoneTime)
{
   top=0; bottom=0; zoneTime=0;
   if(dir==DIR_NONE) return false;
   if(g_mtfTimeframes[3]==PERIOD_CURRENT) return false;   // همان تایم‌فریم چارت است؛ ناحیهٔ جدا لازم نیست

   MqlRates r5[];
   int copied=CopyRatesAsOf(_Symbol, g_mtfTimeframes[3], asOfBarTime, 150, r5);
   if(copied<10) return false;

   for(int i=0;i+2<copied;i++)   // i = کندل سوم الگو، i+2 = کندل اول، i+1 = کندل میانی
   {
      if(r5[i].time>=asOfBarTime) continue;   // فقط کندل بسته‌شدهٔ همان بازه
      double zTop=0, zBot=0;
      if(dir==DIR_BULL)
      {
         if(!(r5[i].low > r5[i+2].high)) continue;
         zTop=r5[i].low; zBot=r5[i+2].high;
         bool closedThrough=false;
         for(int j=0;j<i;j++) if(r5[j].close < zBot) { closedThrough=true; break; }
         if(closedThrough) continue;
      }
      else
      {
         if(!(r5[i].high < r5[i+2].low)) continue;
         zTop=r5[i+2].low; zBot=r5[i].high;
         bool closedThrough=false;
         for(int j=0;j<i;j++) if(r5[j].close > zTop) { closedThrough=true; break; }
         if(closedThrough) continue;
      }
      if(zTop-zBot <= PointsToPrice(1)) continue;
      top=zTop; bottom=zBot; zoneTime=r5[i].time;
      return true;
   }
   return false;
}

//====================================================================
// PHASE 15 — چرخهٔ عمر ستاپ (#۶۶): ابطال با عبور بستهٔ قیمت از SL
//====================================================================
// پیش از این، وضعیت ستاپ فقط «لحظه‌ای» بود: UpdateSetup هر کندل از صفر ساخته
// می‌شد و هیچ‌جا ثبت نمی‌شد که ستاپ آمادهٔ قبلی با عبور قیمت از SL باطل شده است.
// این یک ماشین حالت *قطعی* است که به ترتیب کندل‌ها اجرا می‌شود (در بازسازی
// تاریخچه هم همان ترتیب طی می‌شود)، پس نتیجه در full و incremental یکسان است.
string SessionShortStr()
{
   switch(g_currentSession)
   {
      case SESS_ASIA:         return "ASIA";
      case SESS_LONDON:       return "LONDON";
      case SESS_NY_AM:        return "NY_AM";
      case SESS_LONDON_CLOSE: return "LONDON_CLOSE";
      case SESS_NY_PM:        return "NY_PM";
      default:                return "NONE";
   }
}

void PersistSetupLifecycleEvent(string state, datetime t, double price)
{
   int h=FileOpen("ICT_Assistant_Canonical_SetupLifecycle.csv",FILE_COMMON|FILE_READ|FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_SHARE_WRITE,';');
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0)
      FileWrite(h,"EventTime","BuildStamp","Event","Dir","Entry","SL","TP1","Price","ChainEventId","Reason");
   FileSeek(h,0,SEEK_END);
   FileWrite(h, TimeToString(t,TIME_DATE|TIME_MINUTES), g_buildStamp, state, DirToStr(g_setupLifeDir),
             DoubleToString(g_setupLifeEntry,_Digits), DoubleToString(g_setupLifeSL,_Digits),
             DoubleToString(g_setupLifeTP1,_Digits), DoubleToString(price,_Digits),
             IdToStr(g_setupLifeChainId), g_setupLifeReason);
   FileClose(h);
}

// سنجش ستاپ مسلح با کندل *بستهٔ* جدید. ابطال فقط با close فراتر از SL است
// (فتیله کافی نیست) — همان قاعدهٔ برگشت تأییدشدهٔ HTF در فاز ۱۱.
void UpdateSetupLifecycle(datetime barTime, double closePrice, double highPrice, double lowPrice)
{
   if(!InpTrackSetupLifecycle) return;
   if(g_setupLifeState!="TRACKING") return;

   bool slHit=false, tp1Hit=false;
   if(g_setupLifeDir==DIR_BULL)
   {
      slHit  = (closePrice < g_setupLifeSL);
      tp1Hit = (highPrice>0.0 && highPrice>=g_setupLifeTP1);
   }
   else if(g_setupLifeDir==DIR_BEAR)
   {
      slHit  = (closePrice > g_setupLifeSL);
      tp1Hit = (lowPrice>0.0 && lowPrice<=g_setupLifeTP1);
   }
   else return;

   // اگر همان کندل هر دو را لمس کرد، محافظه‌کارانه ابطال مقدم است: ادعای
   // «هدف اول خورد» بدون شاهد بستهٔ قیمت پذیرفته نمیشود.
   if(slHit)
   {
      g_setupLifeState="INVALIDATED";
      g_setupLifeEndTime=barTime;
      g_setupLifeEndPrice=closePrice;
      g_setupInvalidTime=barTime;
      g_setupInvalidPrice=closePrice;
      g_setupInvalidDir=g_setupLifeDir;
      g_setupInvalidCount++;
      // Phase 42: no Latin token inside a Persian clause. The lifecycle code
      // (INVALIDATED / ARMED / TP1_HIT) stays Latin and leads the row.
      g_setupLifeReason=StringFormat("SETUP INVALIDATED | کندل %s با قیمت بستهٔ %s از حد ضرر %s رد شد (جهت ستاپ %s) → ستاپ باطل شد",
                                     TimeToString(barTime,TIME_DATE|TIME_MINUTES),
                                     DoubleToString(closePrice,_Digits),
                                     DoubleToString(g_setupLifeSL,_Digits), DirToStr(g_setupLifeDir));
      if(!g_rebuildMode)
         Print(StringFormat("ICT PHASE15 | setup INVALIDATED | %s | close %s beyond SL %s | dir %s | chain #%s | invalidated total %d",
               TimeToString(barTime,TIME_DATE|TIME_MINUTES), DoubleToString(closePrice,_Digits),
               DoubleToString(g_setupLifeSL,_Digits), DirToStr(g_setupLifeDir),
               IdToStr(g_setupLifeChainId), g_setupInvalidCount));
      PersistSetupLifecycleEvent("INVALIDATED", barTime, closePrice);
   }
   else if(tp1Hit)
   {
      double reached=(g_setupLifeDir==DIR_BULL)? highPrice : lowPrice;
      g_setupLifeState="TP1_HIT";
      g_setupLifeEndTime=barTime;
      g_setupLifeEndPrice=reached;
      g_setupTP1Count++;
      g_setupLifeReason=StringFormat("SETUP TP1_HIT | هدف اول (یک برابر ریسک = %s) در %s لمس شد → پیگیری این ستاپ بسته شد",
                                     DoubleToString(g_setupLifeTP1,_Digits),
                                     TimeToString(barTime,TIME_DATE|TIME_MINUTES));
      if(!g_rebuildMode)
         Print(StringFormat("ICT PHASE15 | setup TP1_HIT | %s | price %s reached TP1 %s | dir %s | tp1 total %d",
               TimeToString(barTime,TIME_DATE|TIME_MINUTES), DoubleToString(reached,_Digits),
               DoubleToString(g_setupLifeTP1,_Digits), DirToStr(g_setupLifeDir), g_setupTP1Count));
      PersistSetupLifecycleEvent("TP1_HIT", barTime, reached);
   }
}

// پس از UpdateSetup: اگر ستاپ READY شد، پیگیری از همین کندل مسلح می‌شود.
// تنها یک ستاپ در هر لحظه پیگیری می‌شود (آخرین زنجیرهٔ اثبات‌شده).
void ArmSetupLifecycle(datetime barTime)
{
   if(!InpTrackSetupLifecycle) return;
   if(!(g_setup.active && g_setup.status=="READY")) return;
   if(g_setup.sl<=0.0 || g_setup.tp1<=0.0 || g_setup.entry<=0.0) return;
   if(g_setupLifeState=="TRACKING" && g_setupLifeChainId==g_setup.chainEventId) return;

   g_setupLifeState="TRACKING";
   g_setupLifeDir=g_setup.dir;
   g_setupLifeEntry=g_setup.entry;
   g_setupLifeSL=g_setup.sl;
   g_setupLifeTP1=g_setup.tp1;
   g_setupLifeArmTime=barTime;
   g_setupLifeChainId=g_setup.chainEventId;
   g_setupArmedCount++;
   g_setupLifeReason=StringFormat("SETUP ARMED | مسلح شد در %s | ورود %s | حد ضرر %s | هدف اول %s | جهت %s",
                                  TimeToString(barTime,TIME_DATE|TIME_MINUTES),
                                  DoubleToString(g_setup.entry,_Digits), DoubleToString(g_setup.sl,_Digits),
                                  DoubleToString(g_setup.tp1,_Digits), DirToStr(g_setup.dir));
   if(!g_rebuildMode)
      Print(StringFormat("ICT PHASE15 | setup ARMED | %s | entry %s | SL %s | TP1 %s | dir %s | chain #%s | armed total %d",
            TimeToString(barTime,TIME_DATE|TIME_MINUTES), DoubleToString(g_setup.entry,_Digits),
            DoubleToString(g_setup.sl,_Digits), DoubleToString(g_setup.tp1,_Digits), DirToStr(g_setup.dir),
            IdToStr(g_setup.chainEventId), g_setupArmedCount));
   PersistSetupLifecycleEvent("ARMED", barTime, g_setup.entry);
}

// شاهد عددی فاز ۱۵ : آفست تاریخی/قاعدهٔ DST بروکر + وضعیت چرخهٔ عمر ستاپ.
// یک ردیف در هر کندل بسته (یا هر بار که مقدار کلیدی عوض شود) — به‌سبک فاز ۱۲.
void PersistPhase15Diagnostics(datetime barTime)
{
   if(!InpWritePhase15Diagnostics) return;
   int htfEvents=0;
   for(int i=0;i<ArraySize(g_events);i++)
      if(g_events[i].isHTF) htfEvents++;

   string sig=IntegerToString(g_histOffsetDeltaMin)+"|"+IntegerToString((int)g_brokerDSTRule)
              +"|"+(g_brokerDSTActiveNow?"1":"0")+"|"+g_setupLifeState
              +"|"+IntegerToString(g_setupArmedCount)+"|"+IntegerToString(g_setupInvalidCount)
              +"|"+IntegerToString(g_setupTP1Count)+"|"+g_setup.status
              +"|"+IntegerToString(htfEvents)+"|"+IntegerToString((int)g_currentSession);
   static datetime lastBar15=0;
   static string   lastSig15="";
   if(barTime==lastBar15 && sig==lastSig15) return;
   lastBar15=barTime; lastSig15=sig;

   int h=DiagOpen("ICT_Assistant_Canonical_Phase15_Diag.csv");
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0)
      FileWrite(h,"BuildStamp","BarTime","BrokerOffsetMinNow","BrokerStdOffsetMin","BrokerRule","BrokerDSTNow",
                "HistBarOffsetMin","HistDeltaMin","HistoryMode","NYHour","NYMin","Session",
                "SetupStatus","SetupLife","SetupEntry","SetupSL","SetupTP1",
                "ArmedTotal","InvalidTotal","TP1Total","HTFEventCount","HTFEventDrawn",
                "InvalidatedAt","InvalidatedPrice");
   FileSeek(h,0,SEEK_END);
   FileWrite(h, g_buildStamp, TimeToString(barTime,TIME_DATE|TIME_MINUTES),
             (int)(g_serverGMTOffsetSeconds/60), (int)(g_brokerStdOffsetSeconds/60),
             BrokerDSTRuleToStr(g_brokerDSTRule), g_brokerDSTActiveNow?"true":"false",
             (int)(BrokerOffsetSecondsAtServer(barTime)/60), g_histOffsetDeltaMin,
             InpUseHistoricalBrokerOffset?"HISTORICAL":"CURRENT",
             g_hourNYNow, g_minNYNow, SessionShortStr(),
             g_setup.status, g_setupLifeState,
             DoubleToString(g_setupLifeEntry,_Digits), DoubleToString(g_setupLifeSL,_Digits),
             DoubleToString(g_setupLifeTP1,_Digits),
             g_setupArmedCount, g_setupInvalidCount, g_setupTP1Count,
             htfEvents, g_htfEventsDrawn,
             g_setupInvalidTime>0? TimeToString(g_setupInvalidTime,TIME_DATE|TIME_MINUTES) : "",
             g_setupInvalidPrice>0.0? DoubleToString(g_setupInvalidPrice,_Digits) : "");
   DiagClose(h);
}

void UpdateSetup(double curClose, double atrValue, datetime barTime)
{
   g_setup.active=false; g_setup.status="NONE";
   g_setup.risk=0; g_setup.rrTP1=0; g_setup.rrTP2=0; g_setup.rrTP3=0;
   g_setup.oteLow=0; g_setup.oteHigh=0; g_setup.golden=0; g_setup.slBuffer=0;
   g_setup.zoneSource=""; g_setup.slSource=""; g_setup.chainText="";
   g_setup.chainSweepId=-1; g_setup.chainEventId=-1; g_setup.chainDispId=-1;
   g_setup.fvgId=-1; g_setup.obId=-1; g_setup.dolLiqId=-1;
   // فاز ۱۲
   g_setup.entryModel=MODEL_NONE; g_setup.modelReason="";
   g_setup.quality=0; g_setup.qualityMax=10; g_setup.qualityText="";
   g_setup.poiId=-1; g_setup.poiKind=POIK_NONE; g_setup.poiScore=0;
   g_analysisClose=curClose;
   g_analysisATR=atrValue;
   if(!InpEnableSetupEngine)
   {
      g_setup.status="SETUP_ENGINE_DISABLED";
      return;
   }
   if(g_htfBias==DIR_NONE)
   {
      g_setup.status="WAITING_H4_BIAS";
      return;
   }
   if(!g_hasDOL)
   {
      g_setup.status="WAITING_DOL";
      return;
   }

   if(g_mtfConflict)
   {
      g_setup.status="WAITING_MTF_CONFLICT";
      return;
   }
   if(g_mtfContext[1].externalDirection!=DIR_NONE && g_mtfContext[1].externalDirection!=g_htfBias) { g_setup.status="WAITING_H1_CONTEXT"; return; }
   if(g_mtfContext[2].externalDirection!=DIR_NONE && g_mtfContext[2].externalDirection!=g_htfBias) { g_setup.status="WAITING_M15_CONTEXT"; return; }
   if(g_mtfContext[3].externalDirection!=DIR_NONE && g_mtfContext[3].externalDirection!=g_htfBias && g_mtfContext[3].internalDirection!=g_htfBias) { g_setup.status="WAITING_M5_SETUP"; return; }
   if(g_mtfContext[4].internalDirection!=DIR_NONE && g_mtfContext[4].internalDirection!=g_htfBias) { g_setup.status="WAITING_M2_CONFIRMATION"; return; }
   if(g_mtfContext[5].internalDirection!=DIR_NONE && g_mtfContext[5].internalDirection!=g_htfBias) { g_setup.status="WAITING_M1_CONFIRMATION"; return; }

   // --- #۶۶ بند ۱: دروازهٔ زنجیرهٔ واقعی ICT ---
   // مدل: Sweep نقدینگی → Displacement → شکست ساختار هم‌جهت (MSS/BOS تأییدشده).
   // قبلاً مسیر READY هیچ‌کدام را چک نمی‌کرد و فقط به causal بودن ناحیه تکیه
   // داشت؛ حالا خودِ چرخه هم باید اثبات‌شده و تازه باشد.
   {
      bool sawUnproven=false;
      for(int i=ArraySize(g_events)-1;i>=0;i--)
      {
         if(g_events[i].isHTF) continue;
         if(g_events[i].direction!=g_htfBias) continue;
         if(g_events[i].type==EVT_CHOCH) { sawUnproven=true; continue; }
         if(g_events[i].displacementId==-1 || g_events[i].sweepId==-1) { sawUnproven=true; continue; }
         g_setup.chainEventId=g_events[i].id;
         g_setup.chainSweepId=g_events[i].sweepId;
         g_setup.chainDispId =g_events[i].displacementId;
         g_setup.chainText   =StringFormat("CHAIN | %s #%s | SWEEP #%s | DISPLACEMENT #%s | زمان %s",
                                           EventTypeToStr(g_events[i].type), IdToStr(g_events[i].id),
                                           TimeToString(g_events[i].time,TIME_DATE|TIME_MINUTES),
                                           IdToStr(g_events[i].sweepId), IdToStr(g_events[i].displacementId));
         if(barTime>0 && InpChainLookbackBars>0 && PeriodSeconds()>0 &&
            ((long)barTime-(long)g_events[i].time) > (long)PeriodSeconds()*(long)InpChainLookbackBars)
         {
            g_setup.status="WAITING_FRESH_CYCLE";
            return;
         }
         break;
      }
      if(g_setup.chainEventId==-1)
      {
         g_setup.status = sawUnproven ? "WAITING_PROVEN_SWEEP_MSS" : "WAITING_ICT_CYCLE";
         return;
      }
   }

   // آخرین FVG و OB Causal/Valid هم‌جهت با HTF Bias را پیدا کن
   // فاز ۱۲ (#۳۰ #۳۱): گپ Micro گاهی بسیار کوچک است و برای ناحیهٔ ورود مناسب
   // نیست؛ پس ابتدا گپ STANDARD/IMPLIED جست‌وجو می‌شود و Micro فقط به‌عنوان
   // جانشین می‌آید. همین منطق برای OB: Core/Extreme بر Standalone ارجح است (#۳۶).
   long fvgId=-1; double fTop=0,fBot=0;
   for(int pass=0;pass<2 && fvgId==-1;pass++)
      for(int i=ArraySize(g_fvgs)-1;i>=0;i--)
      {
         if(!g_fvgs[i].causal || g_fvgs[i].invalidated) continue;
         // فاز ۴۳ — ناحیهٔ ورود با **نقش فعلی** سنجیده می‌شود، نه جهت تولد: گپ
         // وارونه (iFVG) قابل معامله است ولی در جهت مخالف تولدش. قبلاً همین خط
         // جهت بازنویسی‌شده را می‌خواند و پیامدش این بود که یک گپ وارونهٔ هم‌جهت
         // با بایاس، هم می‌توانست وارد ستاپ شود و هم در CSV مخالف بایاس دیده شود.
         if(FVGActiveDir(g_fvgs[i])!=g_htfBias) continue;
         if(pass==0 && g_fvgs[i].kind==FVGK_MICRO) continue;
         fvgId=g_fvgs[i].id; fTop=g_fvgs[i].top; fBot=g_fvgs[i].bottom; break;
      }
   long obId=-1; double oTop=0,oBot=0;
   for(int pass=0;pass<2 && obId==-1;pass++)
      for(int i=ArraySize(g_obs)-1;i>=0;i--)
      {
         if(g_obs[i].state!=OB_VALID || g_obs[i].direction!=g_htfBias) continue;
         if(pass==0 && g_obs[i].isStandalone) continue;
         obId=g_obs[i].id; oTop=g_obs[i].top; oBot=g_obs[i].bottom; break;
      }

   bool hasChartZone = (fvgId!=-1 || obId!=-1);
   double chartTop = (obId!=-1)? oTop : fTop;
   double chartBot = (obId!=-1)? oBot : fBot;

   // --- #۴۳: دامنهٔ معامله‌گری از **لگ واقعی** خوانده می‌شود، نه آخرین سقف/کف مستقل ---
   if(!g_leg.valid)
   {
      g_setup.status="WAITING_DEALING_LEG";
      return;
   }
   double dealingRange=g_leg.range;
   double equilibrium=g_leg.eq;
   if(g_leg.dir!=g_htfBias)
   {
      // لگی که قیمت آخرین بار از آن گسترش یافته هم‌جهت Bias نیست؛ ریتریس
      // معامله‌پذیر روی لگ مخالف ساخته نمی‌شود (#۴۳/#۴۶).
      g_setup.status="WAITING_LEG_DIRECTION";
      return;
   }

   // --- #۴۶: OTE روی همان لگ (۶۲ / ۷۰٫۵ / ۷۹) ---
   double oteLow=0.0, oteHigh=0.0, golden=0.0;
   if(g_htfBias==DIR_BULL)
   {
      oteLow  = g_leg.high - dealingRange*InpOTE_High;     // مرز ۷۹٪
      oteHigh = g_leg.high - dealingRange*InpOTE_Low;      // مرز ۶۲٪
      golden  = g_leg.high - dealingRange*InpOTE_Golden;   // ۷۰٫۵٪
   }
   else
   {
      oteLow  = g_leg.low + dealingRange*InpOTE_Low;
      oteHigh = g_leg.low + dealingRange*InpOTE_High;
      golden  = g_leg.low + dealingRange*InpOTE_Golden;
   }
   g_setup.oteLow=oteLow; g_setup.oteHigh=oteHigh; g_setup.golden=golden;

   // سمت قیمت نسبت به EQ همان لگ (نه نسبت به هر رنج دیگری)
   bool priceSideOk = (g_htfBias==DIR_BULL) ? (curClose<=equilibrium) : (curClose>=equilibrium);
   if(!priceSideOk)
   {
      g_setup.status=g_htfBias==DIR_BULL?"WAITING_DISCOUNT_OTE":"WAITING_PREMIUM_OTE";
      return;
   }

   // --- #۶۶ بند ۴: ناحیهٔ ورود ابتدا روی تایم‌فریم SETUP (M5) جست‌وجو می‌شود ---
   double zoneTop=0.0, zoneBot=0.0;
   double m5Top=0.0, m5Bot=0.0, m5Mid=0.0;
   datetime m5Time=0;
   bool hasM5 = InpRequireSetupTFZone && FindSetupTFZone(barTime, g_htfBias, m5Top, m5Bot, m5Time);
   if(hasM5) m5Mid=(m5Top+m5Bot)/2.0;
   double chartMid=(chartTop+chartBot)/2.0;
   bool zoneSelected=false;
   if(hasM5 && m5Mid>=oteLow && m5Mid<=oteHigh)
   {
      zoneTop=m5Top; zoneBot=m5Bot;
      g_setup.zoneSource="FVG روی تایم‌فریم ستاپ (پنج دقیقه)، "+TimeToString(m5Time,TIME_DATE|TIME_MINUTES);
      zoneSelected=true;
   }
   else if(hasChartZone && chartMid>=oteLow && chartMid<=oteHigh)
   {
      zoneTop=chartTop; zoneBot=chartBot;
      g_setup.zoneSource=((obId!=-1)?"ORDER BLOCK":"FVG")+" | روی تایم‌فریم چارت";
      zoneSelected=true;
   }
   if(!zoneSelected)
   {
      g_setup.status = hasChartZone || hasM5
         ? (g_htfBias==DIR_BULL?"WAITING_DISCOUNT_OTE":"WAITING_PREMIUM_OTE")
         : "WAITING_RETRACE";
      return;
   }
   if(zoneTop<=zoneBot)
   {
      g_setup.status="WAITING_ZONE_GEOMETRY";
      return;
   }

   // --- #۶۶ بند ۲ و ۳: SL واقعی (ATR + StopsLevel) و R:R واقعی از DOL ---
   double dolPrice=(double)g_currentDOL.price;
   double entry=(zoneTop+zoneBot)/2.0;
   double sgn=(g_htfBias==DIR_BULL)?1.0:-1.0;
   int    stopsPts=(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   double stopsPrice=(double)stopsPts*_Point;
   g_stopsLevelPrice=stopsPrice;
   double bufAtr=(atrValue>0.0)? atrValue*InpSL_MinATR : 0.0;
   double bufPts=PointsToPrice((double)InpSL_MinPoints);
   double buf=MathMax(MathMax(bufPts,bufAtr),stopsPrice);
   if(buf<=0.0) buf=PointsToPrice(10.0);   // SL هرگز روی خود ناحیه نیفتد
   double sl=(g_htfBias==DIR_BULL)? zoneBot-buf : zoneTop+buf;
   double risk=MathAbs(entry-sl);
   if(risk<=0.0 || sl<=0.0)
   {
      g_setup.status="WAITING_SL_INVALID";
      return;
   }
   g_setup.slBuffer=buf;
   g_setup.slSource=StringFormat("SL BUFFER | میانگین دامنه %.2f×%.2f=%.2f | کف پوینتی %d نقطه=%.2f | حد توقف کارگزار %d نقطه=%.2f → بافر %.2f",
                                 atrValue, InpSL_MinATR, bufAtr, InpSL_MinPoints, bufPts,
                                 stopsPts, stopsPrice, buf);

   // DOL باید آن‌سوی ورود و در جهت معامله باشد؛ وگرنه هدف واقعی وجود ندارد
   if((g_htfBias==DIR_BULL && dolPrice<=entry) || (g_htfBias==DIR_BEAR && dolPrice>=entry))
   {
      g_setup.status="WAITING_DOL_DIRECTION";
      return;
   }

   double tp1=entry+sgn*risk*InpRR_TP1;
   double tp2=entry+sgn*risk*InpRR_TP2;
   double tp3Anchor=entry+sgn*risk*InpRR_TP3;
   double tp3=(g_htfBias==DIR_BULL)? MathMax(tp3Anchor,dolPrice) : MathMin(tp3Anchor,dolPrice);
   double rr=MathAbs(tp3-entry)/risk;      // R:R واقعی، نه مقدار ورودی

   g_setup.entry=entry; g_setup.sl=sl;
   g_setup.tp1=tp1; g_setup.tp2=tp2; g_setup.tp3=tp3;
   g_setup.risk=risk; g_setup.rr=rr;
   g_setup.rrTP1=MathAbs(tp1-entry)/risk;
   g_setup.rrTP2=MathAbs(tp2-entry)/risk;
   g_setup.rrTP3=rr;

   if(rr<InpMinRR)
   {
      g_setup.status="WAITING_RR_LOW";
      return;
   }

   // --- فاز ۱۲ (#۶۷): انتخاب مدل ورود ---
   // نوع رویداد زنجیره از رجیستری خوانده می‌شود تا مدل ۲۰۲۲ فقط با MSS
   // تأییدشده معتبر باشد، نه با هر CHoCH.
   bool chainIsMss=false;
   for(int i=0;i<ArraySize(g_events);i++)
      if(g_events[i].id==g_setup.chainEventId){ chainIsMss=(g_events[i].type==EVT_MSS); break; }
   bool hasChainedDisp=DisplacementChained(g_setup.chainDispId, g_htfBias);
   g_setup.entryModel=SelectEntryModel(chainIsMss, g_setup.chainSweepId!=-1, hasChainedDisp,
                                       fvgId, obId, zoneSelected, (g_leg.valid && g_leg.dir==g_htfBias));
   g_setup.modelReason=g_modelReason;

   // --- فاز ۱۲ (#۶۸): امتیاز کیفیت با ده معیار که واقعاً می‌توانند متفاوت باشند ---
   // توجه: معیارهای فاز روند از وضعیت کندل **قبلی** می‌آید چون UpdateExhaustion
   // بعد از UpdateContextForClosedBar اجرا می‌شود. یک کندل تأخیر، مستند شده.
   int q=0; string qb="";
   if(chainIsMss){ q++; qb+="۱ تغییر کاراکتر تأییدشده؛ "; }
   if(fvgId!=-1){ q++; qb+="۲ گپ علّی هم‌جهت؛ "; }
   if(obId!=-1){ q++; qb+="۳ اردر بلاک معتبر؛ "; }
   ENUM_OB_KIND obKind=OBK_UNDEFINED; bool obExtreme=false;
   for(int i=0;i<ArraySize(g_obs);i++)
      if(g_obs[i].id==obId){ obKind=g_obs[i].kind; obExtreme=g_obs[i].isExtreme; break; }
   if(obKind==OBK_CORE || obKind==OBK_EXTREME){ q++; qb+="۴ اردر بلاک از نوع هسته یا اکستریم، نه تنها؛ "; }
   if(obExtreme){ q++; qb+="۵ اردر بلاک روی اکسترمم لگ؛ "; }
   if(hasM5){ q++; qb+="۶ ناحیه از تایم‌فریم ستاپ؛ "; }
   POIObj bestPoi;
   if(FindBestPOI(g_htfBias, bestPoi) &&
      (bestPoi.kind==POIK_BREAKER || bestPoi.kind==POIK_OB || bestPoi.kind==POIK_MITIGATION))
   { q++; qb+="۷ بهترین نقطهٔ مورد علاقه یک ناحیهٔ ساختاری است؛ "; }
   if(curClose>=oteLow && curClose<=oteHigh){ q++; qb+="۸ قیمت داخل باند ورود بهینه؛ "; }
   if(g_trend.phase==PHASE_INITIATION || g_trend.phase==PHASE_EXPANSION){ q++; qb+="۹ فاز روند ادامه‌دار؛ "; }
   if(rr>=InpMinRR+0.5){ q++; qb+="۱۰ نسبت سود به ریسک با حاشیهٔ راحت"; }
   g_setup.quality=q; g_setup.qualityMax=10; g_setup.qualityText=qb;

   if(FindBestPOI(g_htfBias, bestPoi)){ g_setup.poiId=bestPoi.id; g_setup.poiKind=bestPoi.kind; g_setup.poiScore=bestPoi.score; }

   if(g_setup.entryModel==MODEL_NONE)
   {
      // کد وضعیت باید لاتین و خالص باشد؛ متن فارسی دلیل در پنل آموزشی
      // از g_modelReason خوانده می‌شود (فاز ۴۲).
      g_setup.status="WAITING_ENTRY_MODEL";
      return;
   }
   if(q<InpMinQualityScore)
   {
      g_setup.status=StringFormat("WAITING_QUALITY_LOW (score %d of 10)", q);
      return;
   }

   g_setup.status="READY";
   g_setup.active=true;
   g_setup.dir=g_htfBias;
   g_setup.fvgId=fvgId; g_setup.obId=obId; g_setup.dolLiqId=g_currentDOL.liquidityId;
}

//====================================================================
// PHASE 12 ENGINES — تکمیل پوشش SMC / MMM
// هر مفهوم این بخش با یک قانون عددی، زمان، تایم‌فریم مالک و مسیر Explain
// جداگانه کار می‌کند. هیچ بلاکی که در فاز ۱۱ اثبات شده دست نخورده است.
//====================================================================
string g_trendlineReject = "";
string g_rangeReject     = "";
bool   g_rangeActive     = false;
bool   g_rangeOk         = false;
bool   g_trendlineBuilt  = false;
bool   g_ipdaOk          = false;
string g_ipdaNote        = "";
double g_rangeHigh       = 0.0;
double g_rangeLow        = 0.0;
double g_rangeHeight     = 0.0;
int    g_rangeHighTouches= 0;
int    g_rangeLowTouches = 0;
string g_modelReason     = "";

//--------------------------------------------------------------------
// #۱۹ Trendline Liquidity — نقدینگی مورب
// خط از دو سویینگ تأییدشده ساخته می‌شود و تعداد سویینگ‌های نشسته روی خط
// گزارش می‌شود. ابطال: بسته‌شدن قیمت با فاصلهٔ مشخص فراتر از خط.
//--------------------------------------------------------------------
double TrendlinePriceAt(const TrendlineLiqObj &tl, datetime t)
{
   return tl.p2 + tl.slope * (double)((long)t-(long)tl.t2);
}

void UpdateTrendlineLifecycle(double curHigh, double curLow, double curClose, datetime curBarTime, double atrValue)
{
   if(!InpEnablePhase12 || !InpDetectTrendlineLiq) return;
   double buf=(atrValue>0.0)? atrValue*InpTrendlineBreakATR : 0.0;
   for(int i=0;i<ArraySize(g_trendlines);i++)
   {
      if(g_trendlines[i].invalidated) continue;
      double lvl=TrendlinePriceAt(g_trendlines[i], curBarTime);
      if(lvl<=0.0) continue;
      // عبور **بسته‌شده** از خط (نه فتیله) خط را باطل میکند
      bool broke = g_trendlines[i].isHigh ? (curClose > lvl+buf) : (curClose < lvl-buf);
      if(broke)
      {
         g_trendlines[i].invalidated=true;
         g_trendlines[i].invalidTime=curBarTime;
         g_trendlines[i].invalidPrice=curClose;
      }
   }
}

//--------------------------------------------------------------------
// فاز ۳۰ (#۷۶): Sweep نقدینگی مورب (خط روند).
// منبع (LuxAlgo — Trendline Liquidity، مرحلهٔ ۴): «a sharp poke through the line
// that stalls quickly and reclaims it suggests a sweep of trendline liquidity
// rather than a genuine trend change» و (LuxAlgo — Liquidity Sweep، مرحلهٔ ۳):
// «a trade through the level followed by a close back inside the prior range ...
// A close that holds beyond it, with continuation, is a breakout, not a sweep».
// پس قاعده دقیقاً همان قاعدهٔ Sweep سطوح افقی است: فتیله فراتر از خط +
// بسته‌شدن برگشتی به همان سمت. سطح هم مثل بقیهٔ سطوح در Registry ثبت و همان
// لحظه «مصرف‌شده» علامت می‌خورد تا زنجیرهٔ رویداد (ساختار/Displacement) به آن
// وصل شود — قبلاً خط روند فقط «باطل» می‌شد و هیچ Sweep ای برایش ثبت نمی‌شد.
//--------------------------------------------------------------------
long DetectTrendlineSweep(double barHigh, double barLow, double barClose, datetime t, ENUM_DIRECTION &outDir)
{
   outDir=DIR_NONE;
   if(!InpEnablePhase12 || !InpDetectTrendlineLiq) return -1;
   long mainId=-1;
   for(int i=0;i<ArraySize(g_trendlines);i++)
   {
      if(g_trendlines[i].invalidated || g_trendlines[i].swept) continue;
      double lvl=TrendlinePriceAt(g_trendlines[i], t);
      if(lvl<=0.0) continue;
      bool sweptHere = g_trendlines[i].isHigh ? (barHigh > lvl && barClose < lvl)
                                              : (barLow  < lvl && barClose > lvl);
      if(!sweptHere) continue;
      g_trendlines[i].swept=true;
      g_trendlines[i].sweptTime=t;
      g_trendlines[i].sweptPrice=lvl;
      long id=AddLiquidity(g_trendlines[i].isHigh? LIQ_TRENDLINE_H : LIQ_TRENDLINE_L,
                           SCOPE_INTERNAL, lvl, t, false);
      // سطح در همان کندل جارو شد، پس نباید «تازه» بماند؛ وگرنه کندل بعدی دوباره
      // همان سطح را جارو می‌کند و زنجیره دو بار ساخته می‌شود (هم‌قاعده با DetectSweep).
      for(int k=0;k<ArraySize(g_liquidity);k++)
         if(g_liquidity[k].id==id && g_liquidity[k].state==LSTATE_FRESH)
         {
            g_liquidity[k].state=LSTATE_SWEPT;
            g_liquidity[k].sweptTime=t;
         }
      if(mainId==-1)
      {
         mainId=id;
         outDir = g_trendlines[i].isHigh? DIR_BEAR : DIR_BULL;
      }
   }
   return mainId;
}

void BuildTrendlines(double atrValue)
{
   g_trendlineBuilt=false;
   g_trendlineReject="";
   if(!InpEnablePhase12 || !InpDetectTrendlineLiq) return;
   int n=ArraySize(g_swingsLTF);
   if(n<2){ g_trendlineReject="سوئینگ تأییدشدهٔ کافی برای ساخت خط نیست"; return; }
   double tol=(atrValue>0.0)? atrValue*InpTrendlineTolATR : PointsToPrice(InpEQ_Tolerance_Points);

   int built=0;
   for(int side=0;side<2;side++)
   {
      bool wantHigh=(side==0);
      // دو سویینگ آخر این سمت به ترتیب زمان
      // سوئینگ‌ها به ترتیب زمان (قدیم به جدید) در آرایه‌اند، پس پیمایش از
      // انتها یعنی از جدیدترین: اولین تطابق = آنکر جدید، دومین = آنکر قدیم.
      int idxB=-1, idxA=-1;
      for(int i=n-1;i>=0;i--)
      {
         if(g_swingsLTF[i].isHigh!=wantHigh) continue;
         if(idxB==-1){ idxB=i; continue; }
         idxA=i;
         break;
      }
      if(idxB==-1 || idxA==-1) continue;
      SwingPoint a=g_swingsLTF[idxA];
      SwingPoint b=g_swingsLTF[idxB];
      if(b.time<=a.time) continue;
      double dt=(double)((long)b.time-(long)a.time);
      if(dt<=0.0) continue;

      // فاز ۳۰ (#۷۶): سمت نقدینگی خط از **شیب** آن می‌آید، نه از این‌که خط روی
      // سقف‌ها یا کف‌ها وصل شده است.
      // منبع (LuxAlgo — Trendline Liquidity): «below a rising support line sit
      // stops from trendline buyers ... forming a diagonal band of sell-side
      // interest» و «the mirror image above a falling one». یعنی:
      //   • خط روی سقف‌های نزولی (lower highs) → نقدینگی Buy-Side بالای خط
      //   • خط روی کف‌های صعودی (higher lows)  → نقدینگی Sell-Side زیر خط
      // خطی که هیچ‌کدام نیست (سقف صعودی یا کف نزولی) استخر نقدینگی مورب
      // نمی‌سازد؛ قبلاً بدون این شرط ساخته می‌شد و خطی می‌کشید که قیمت در
      // همان لحظه از آن طرف رفته بود.
      if(wantHigh ? !(b.price < a.price) : !(b.price > a.price))
      {
         g_trendlineReject="شیب دو آنکر با استخر نقدینگی مورب نمی‌خواند (سقف‌ها باید نزولی و کف‌ها صعودی باشند)";
         continue;
      }

      TrendlineLiqObj tl;
      tl.id=(long)a.time*2L+(wantHigh?1L:0L);
      tl.isHigh=wantHigh; tl.t1=a.time; tl.t2=b.time; tl.p1=a.price; tl.p2=b.price;
      tl.slope=(b.price-a.price)/dt;
      tl.tf=PERIOD_CURRENT;
      tl.createdTime=a.time;
      tl.invalidated=false; tl.invalidTime=0; tl.invalidPrice=0.0;
      tl.swept=false; tl.sweptTime=0; tl.sweptPrice=0.0;

      // شمارش سویینگ‌هایی که روی خط نشسته‌اند (فقط ۴۰ سویینگ آخر برای هزینهٔ کم)
      int touches=0;
      int scanFrom=MathMax(0,n-40);
      for(int i=scanFrom;i<n;i++)
      {
         if(g_swingsLTF[i].isHigh!=wantHigh) continue;
         double lvl=TrendlinePriceAt(tl, g_swingsLTF[i].time);
         if(lvl>0.0 && MathAbs(g_swingsLTF[i].price-lvl)<=tol) touches++;
      }
      tl.touches=touches;

      // فاز ۳۰ (#۷۶) — منبع: همان صفحه، مرحلهٔ ۱ («a clean line with three or
      // more respected touches») و مرحلهٔ ۳ («each successive touch adds
      // participants»). خط دو-لمسی ضعیف‌ترین حالت است؛ پیش‌فرض ۳ است و از پنل
      // ورودی‌ها قابل کم‌کردن (وگرنه خطوط بی‌ارزش چارت را شلوغ می‌کردند).
      if(tl.touches < MathMax(2,InpTrendlineMinTouches))
      {
         g_trendlineReject=StringFormat("تعداد سویینگ روی خط (%d) کمتر از حد لازم (%d) است",
                                        tl.touches, MathMax(2,InpTrendlineMinTouches));
         continue;
      }

      bool exists=false;
      for(int i=0;i<ArraySize(g_trendlines);i++)
         if(g_trendlines[i].id==tl.id && !g_trendlines[i].invalidated){ exists=true; break; }
      if(exists) continue;
      int m=ArraySize(g_trendlines);
      ArrayResize(g_trendlines,m+1);
      g_trendlines[m]=tl;
      built++;
   }

   int cap=MathMax(1,InpMaxTrendlines);
   if(ArraySize(g_trendlines)>cap)
   {
      for(int i=0;i<ArraySize(g_trendlines)-1;i++) g_trendlines[i]=g_trendlines[i+1];
      ArrayResize(g_trendlines,cap);
   }
   g_trendlineBuilt=(built>0);
   if(!g_trendlineBuilt && g_trendlineReject=="")
      g_trendlineReject="برای هر سمت، دو سویینگ تأییدشدهٔ هم‌جهت با فاصلهٔ زمانی کافی پیدا نشد";
}

//--------------------------------------------------------------------
// #۲۰ Range Liquidity — نقدینگی مرزهای رنج
// قانون: در پنجرهٔ سویینگ‌های اخیر، حداقل InpRangeMinTouches سویینگ روی سقف و
// به همان تعداد روی کف، و ارتفاع رنج از حد مجاز کمتر باشد.
//--------------------------------------------------------------------
void UpdateRangeLiquidity(double atrValue)
{
   g_rangeActive=false;
   g_rangeOk=false;
   g_rangeReject="";
   if(!InpEnablePhase12 || !InpDetectRangeLiquidity) return;
   if(atrValue<=0.0){ g_rangeReject="ATR قابل محاسبه نیست"; return; }
   int n=ArraySize(g_swingsLTF);
   if(n<InpRangeMinTouches*2){ g_rangeReject=StringFormat("سوئینگ کافی نیست (%d از %d لازم)", n, InpRangeMinTouches*2); return; }
   int look=MathMin(n,MathMax(4,InpRangeLookbackSwings));
   int start=n-look;

   double H=-1e18, L=1e18; datetime tH=0, tL=0;
   for(int i=start;i<n;i++)
   {
      if(g_swingsLTF[i].isHigh && g_swingsLTF[i].price>H){ H=g_swingsLTF[i].price; tH=g_swingsLTF[i].time; }
      if(!g_swingsLTF[i].isHigh && g_swingsLTF[i].price<L){ L=g_swingsLTF[i].price; tL=g_swingsLTF[i].time; }
   }
   if(H<=L){ g_rangeReject="سقف و کف معتبر پیدا نشد"; return; }
   double height=H-L;
   double maxH=atrValue*InpRangeMaxATR;
   if(height>maxH)
   {
      g_rangeReject=StringFormat("RANGE REJECT | ارتفاع %.2f از حد مجاز %.2f (%.1f برابر میانگین دامنه) بیشتر است — روند است، نه رنج", height, maxH, InpRangeMaxATR);
      return;
   }
   double tol=MathMax(PointsToPrice(InpEQ_Tolerance_Points), atrValue*InpEQ_ToleranceATR);
   int hiT=0, loT=0;
   for(int i=start;i<n;i++)
   {
      if(g_swingsLTF[i].isHigh && MathAbs(g_swingsLTF[i].price-H)<=tol) hiT++;
      if(!g_swingsLTF[i].isHigh && MathAbs(g_swingsLTF[i].price-L)<=tol) loT++;
   }
   if(hiT<InpRangeMinTouches || loT<InpRangeMinTouches)
   {
      g_rangeReject=StringFormat("برخورد کافی روی مرزها نیست (سقف %d، کف %d از %d)", hiT, loT, InpRangeMinTouches);
      return;
   }
   g_rangeActive=true;
   g_rangeOk=true;
   g_rangeHigh=H; g_rangeLow=L; g_rangeHeight=height; g_rangeHighTouches=hiT; g_rangeLowTouches=loT;
   AddLiquidity(LIQ_RANGE_H, SCOPE_INTERNAL, H, tH, false);
   AddLiquidity(LIQ_RANGE_L, SCOPE_INTERNAL, L, tL, false);
}

//--------------------------------------------------------------------
// #۶۵ IPDA Reference Levels — Old High/Low افق‌های ۲۰/۴۰/۶۰ روزه
// فقط وقتی دادهٔ کافی باشد ثبت می‌شود؛ هیچ مقدار تقریبی نوشته نمی‌شود.
//--------------------------------------------------------------------
void UpdateIPDAReferenceLevels(datetime barTime)
{
   g_ipdaOk=false;
   g_ipdaNote="";
   if(!InpEnablePhase12 || !InpDetectIPDA) return;
   int horizons[3]={20,40,60};
   int registered=0;
   string missing="";
   for(int h=0;h<3;h++)
   {
      int days=horizons[h];
      double hiArr[], loArr[];
      ArraySetAsSeries(hiArr,true);
      ArraySetAsSeries(loArr,true);
      int ch=CopyHigh(_Symbol,PERIOD_D1,1,days,hiArr);
      int cl=CopyLow(_Symbol,PERIOD_D1,1,days,loArr);
      if(ch<days || cl<days)
      {
         missing+=StringFormat("%dd ", days);
         continue;
      }
      double hh=hiArr[ArrayMaximum(hiArr)];
      double ll=loArr[ArrayMinimum(loArr)];
      datetime anchor=iTime(_Symbol,PERIOD_D1,days);
      if(anchor<=0) anchor=barTime;
      ENUM_LIQ_TYPE tH=(days==20)?LIQ_IPDA20_H:((days==40)?LIQ_IPDA40_H:LIQ_IPDA60_H);
      ENUM_LIQ_TYPE tL=(days==20)?LIQ_IPDA20_L:((days==40)?LIQ_IPDA40_L:LIQ_IPDA60_L);
      if(hh>0.0) AddLiquidity(tH, SCOPE_EXTERNAL, hh, anchor, true);
      if(ll>0.0) AddLiquidity(tL, SCOPE_EXTERNAL, ll, anchor, true);
      registered++;
   }
   g_ipdaOk=(registered>0);
   g_ipdaNote=StringFormat("%d از ۳ افق ثبت شد", registered);
   if(StringLen(missing)>0) g_ipdaNote+=" | دادهٔ کافی برای: "+missing;
}

//--------------------------------------------------------------------
// #۳۵ OB Extreme و #۳۶ Core/Standalone
// Core = ناحیه‌ای که به یک شکست ساختار وصل است. Standalone = ناحیه‌ای با
// Displacement ولی بدون مشارکت در شکست ساختار. Extreme = ناحیه‌ای که روی
// اکسترمم لگ معامله‌گری نشسته است (سقف لگ ← عرضه، کف لگ ← تقاضا).
//--------------------------------------------------------------------
void MarkExtremeOrderBlocks(double atrValue)
{
   for(int i=0;i<ArraySize(g_obs);i++) g_obs[i].isExtreme=false;
   if(!g_leg.valid) return;
   double tol=(atrValue>0.0)? atrValue*InpOB_ExtremeATR : 0.0;
   long upId=-1, dnId=-1; double upDist=1e18, dnDist=1e18;
   for(int i=0;i<ArraySize(g_obs);i++)
   {
      if(g_obs[i].state==OB_INVALID) continue;
      if(g_obs[i].direction==DIR_BEAR)              // ناحیهٔ عرضه در سقف لگ
      {
         double d=MathAbs(g_obs[i].bottom-g_leg.high);
         if(g_obs[i].bottom>=g_leg.high-tol && d<upDist){ upDist=d; upId=g_obs[i].id; }
      }
      else if(g_obs[i].direction==DIR_BULL)         // ناحیهٔ تقاضا در کف لگ
      {
         double d=MathAbs(g_obs[i].top-g_leg.low);
         if(g_obs[i].top<=g_leg.low+tol && d<dnDist){ dnDist=d; dnId=g_obs[i].id; }
      }
   }
   for(int i=0;i<ArraySize(g_obs);i++)
   {
      if(g_obs[i].id!=upId && g_obs[i].id!=dnId) continue;
      g_obs[i].isExtreme=true;
      if(g_obs[i].kind!=OBK_MITIGATION_BLOCK) g_obs[i].kind=OBK_EXTREME;
      // فاز ۳۶: ناحیهٔ اکسترمم لگ = External OB (منبع: LuxAlgo — IRL/ERL:
      // مبدأ اکسترمم رنج معامله‌گری، External است؛ «inside the leg» یعنی Internal)
      g_obs[i].scope=SCOPE_EXTERNAL;
   }
}

//--------------------------------------------------------------------
// #۳۱ FVG Micro — گپ سه‌کندلی روی تایم‌فریم پایین‌تر، داخل محدودهٔ همان کندل
// Displacement. فقط از Displacement **زنجیرشده** ساخته می‌شود تا رجیستری با
// ناحیه‌های بی‌ارزش پر نشود.
//--------------------------------------------------------------------
void DetectMicroFVG(datetime dispBarTime, double dispHigh, double dispLow, long dispId)
{
   if(!InpEnablePhase12 || !InpDetectMicroFVG) return;
   if(dispBarTime<=0 || dispId==-1) return;
   int chartSec=PeriodSeconds(PERIOD_CURRENT);
   if(chartSec<=0) chartSec=60;
   int microSec=PeriodSeconds(InpMicroTF);
   if(microSec<=0 || microSec>=chartSec) return;   // فقط روی تایم‌فریم واقعاً پایین‌تر
   datetime windowEnd=(datetime)((long)dispBarTime+(long)chartSec);

   MqlRates mr[];
   int copied=CopyRates(_Symbol, InpMicroTF, windowEnd, MathMax(6,InpMicroBarsPerDisp), mr);
   if(copied<6) return;
   ArraySetAsSeries(mr,true);
   int made=0;
   for(int k=0;k+2<copied && made<4;k++)
   {
      if(mr[k].time>=windowEnd) continue;      // باید داخل همان کندل باشد
      if(mr[k+2].time<dispBarTime) continue;
      // صعودی: low کندل سوم بالای high کندل اول
      if(mr[k].low>mr[k+2].high)
      {
         double top=mr[k].low, bot=mr[k+2].high;
         if(top<=dispHigh && bot>=dispLow)
         {
            AppendFVG(StableZoneId(mr[k].time,DIR_BULL,4), mr[k].time, DIR_BULL, top, bot,
                      dispId, FVGK_MICRO, InpMicroTF, false);
            made++;
         }
      }
      // نزولی: high کندل سوم زیر low کندل اول
      if(mr[k].high<mr[k+2].low)
      {
         double top=mr[k+2].low, bot=mr[k].high;
         if(top<=dispHigh && bot>=dispLow)
         {
            AppendFVG(StableZoneId(mr[k].time,DIR_BEAR,4), mr[k].time, DIR_BEAR, top, bot,
                      dispId, FVGK_MICRO, InpMicroTF, false);
            made++;
         }
      }
   }
}

//--------------------------------------------------------------------
// #۳ ساختار داخلی **همان تایم‌فریم مالک**
// قبلاً ردیف «Internal» داشبورد همان ترند تایم‌فریم چارت بود، نه ساختار
// داخلی تایم‌فریم مالک. این تابع پیوت‌های تأییدشدهٔ همان تایم‌فریم مالک را
// در پنجرهٔ اخیر می‌گیرد و HH/HL یا LH/LL را گزارش می‌کند.
//--------------------------------------------------------------------
void UpdateHtfInternalStructure(datetime barTime)
{
   g_htfInternalDir=DIR_NONE;
   g_htfInternalReason="";
   if(!InpEnablePhase12) return;
   MqlRates rates[];
   int copied=CopyRatesAsOf(_Symbol, InpHTF, barTime, 120, rates);
   if(copied<InpSwingLeft+InpSwingRight+12)
   {
      g_htfInternalReason="دادهٔ بستهٔ کافی روی تایم‌فریم مالک نیست";
      return;
   }
   SwingPoint highs[], lows[];
   int total=ArraySize(rates);
   int window=MathMin(total-InpSwingRight-1, MathMax(InpSwingLeft+InpSwingRight+4,InpInternalWindowBars));
   for(int shift=window; shift>=InpSwingRight; shift--)
   {
      if(PivotHighAt(rates,shift))
      {
         SwingPoint p; p.time=rates[shift].time; p.price=rates[shift].high;
         p.isHigh=true; p.confirmed=true; p.broken=false; p.id=0;
         int n=ArraySize(highs); ArrayResize(highs,n+1); highs[n]=p;
      }
      if(PivotLowAt(rates,shift))
      {
         SwingPoint p; p.time=rates[shift].time; p.price=rates[shift].low;
         p.isHigh=false; p.confirmed=true; p.broken=false; p.id=0;
         int n=ArraySize(lows); ArrayResize(lows,n+1); lows[n]=p;
      }
   }
   g_htfInternalDir=DirectionFromConfirmedSwings(highs,lows);
   if(g_htfInternalDir==DIR_NONE)
      g_htfInternalReason=StringFormat("در پنجرهٔ %d کندلی، هیچ سقف و کف بالاتر یا پایین‌تر تأییدشده‌ای ثبت نشد", window);
}

//--------------------------------------------------------------------
// #۹ سن و مرحلهٔ روند
// سن = تعداد کندل HTF از رویدادی که Bias فعلی را ساخته است.
// مرحله بر اساس همان سن + وضعیت Exhaustion + تأیید برگشت تعیین میشود.
//--------------------------------------------------------------------
string TrendPhaseToStr(ENUM_TREND_PHASE p)
{
   switch(p)
   {
      case PHASE_INITIATION:   return "INITIATION";
      case PHASE_EXPANSION:    return "EXPANSION";
      case PHASE_DISTRIBUTION: return "DISTRIBUTION";
      case PHASE_REVERSAL:     return "REVERSAL";
      default:                 return "UNKNOWN";
   }
}

void UpdateTrendPhase(datetime asOf)
{
   g_trend.ageBars=0; g_trend.sinceTime=0; g_trend.sinceEventId=-1;
   g_trend.phase=PHASE_UNKNOWN; g_trend.phaseReason="";
   if(g_htfBias==DIR_NONE)
   {
      g_trend.phaseReason="بایاس مالک تایم‌فریم بالاتر هنوز تأیید نشده است";
      return;
   }
   // آخرین رویداد HTF هم‌جهت با Bias = رویدادی که این Bias را ساخته است
   for(int i=ArraySize(g_events)-1;i>=0;i--)
   {
      if(!g_events[i].isHTF) continue;
      if(g_events[i].direction!=g_htfBias) continue;
      g_trend.sinceTime=g_events[i].time;
      g_trend.sinceEventId=g_events[i].id;
      break;
   }
   if(g_trend.sinceTime<=0)
   {
      g_trend.phaseReason="رویداد تایم‌فریم بالاتر که این بایاس را ساخته باشد در رجیستری پیدا نشد";
      return;
   }
   int htfSec=PeriodSeconds(InpHTF);
   if(htfSec<=0) htfSec=14400;
   g_trend.ageBars=(int)(((long)asOf-(long)g_trend.sinceTime)/(long)htfSec);
   if(g_trend.ageBars<0) g_trend.ageBars=0;

   if(g_reversal.confirmed && g_reversal.dir==g_htfBias)
   {
      g_trend.phase=PHASE_REVERSAL;
      g_trend.phaseReason="برگشت تأییدشدهٔ سطح محافظت‌شدهٔ خارجی در جهت بایاس فعلی";
   }
   else if(g_trend.ageBars<=InpTrendYoungBars)
   {
      g_trend.phase=PHASE_INITIATION;
      g_trend.phaseReason=StringFormat("سن %d کندل تایم‌فریم بالاتر کمتر یا مساوی %d است", g_trend.ageBars, InpTrendYoungBars);
   }
   else if(g_exhaustion.state==EXH_WATCH || g_exhaustion.state==EXH_MICRO_PULLBACK ||
           g_exhaustion.state==EXH_RANGE_TRANSITION)
   {
      g_trend.phase=PHASE_DISTRIBUTION;
      g_trend.phaseReason="فرسودگی روند ضعف را گزارش می‌کند | "+ExhaustionStateToStr(g_exhaustion.state);
   }
   else
   {
      g_trend.phase=PHASE_EXPANSION;
      g_trend.phaseReason=StringFormat("سن %d کندل تایم‌فریم بالاتر و هیچ هشدار ضعفی ثبت نشده است", g_trend.ageBars);
   }
}

//--------------------------------------------------------------------
// #۴۷ رجیستری POI یکپارچه
// امتیاز عددی و شفاف است؛ کهنگی از امتیاز کم می‌کند. POI هیچ گاه جای
// دروازه‌های READY را نمی‌گیرد؛ فقط انتخاب ناحیه و توضیح را یکسان می‌کند.
//--------------------------------------------------------------------
string PoiKindToStr(ENUM_POI_KIND k)
{
   switch(k)
   {
      case POIK_FVG:        return "FVG";
      case POIK_OB:         return "Order Block";
      case POIK_BREAKER:    return "Breaker Block";
      case POIK_MITIGATION: return "Mitigation Block";
      case POIK_REJECTION:  return "Rejection Block";
      case POIK_TRENDLINE:  return "Trendline Liquidity";
      case POIK_RANGE:      return "Range Liquidity";
      default:              return "—";
   }
}

void AddPOI(long id, ENUM_POI_KIND kind, ENUM_DIRECTION dir, double top, double bottom,
            datetime t, ENUM_TIMEFRAMES tf, datetime asOf, int chartSec, double atrValue, bool extreme)
{
   if(top<=0.0 || bottom<=0.0) return;
   // ناحیهٔ بی‌اندازه پهن (خطای ورودی) به رجیستری راه پیدا نمی‌کند
   if(atrValue>0.0 && MathAbs(top-bottom) > atrValue*8.0) return;
   POIObj p;
   p.id=id; p.kind=kind; p.direction=dir;
   p.top=MathMax(top,bottom); p.bottom=MathMin(top,bottom);
   p.time=t; p.tf=tf; p.valid=true; p.invalidReason=""; p.sourceId=id;
   int ageBars=(t>0 && asOf>t)? (int)(((long)asOf-(long)t)/(long)chartSec) : 0;
   int decay=(InpPOI_AgeDecayBars>0)? (ageBars/InpPOI_AgeDecayBars) : 0;
   if(decay>10) decay=10;
   int s=20;
   if(kind==POIK_BREAKER)    s+=12;
   if(kind==POIK_FVG)        s+=8;
   if(kind==POIK_OB)         s+=6;
   if(kind==POIK_TRENDLINE)  s+=5;
   if(kind==POIK_RANGE)      s+=5;
   if(kind==POIK_MITIGATION) s+=4;
   if(kind==POIK_REJECTION)  s+=3;
   if(dir==g_htfBias)        s+=10;
   if(extreme)               s+=6;
   s-=decay;
   p.score=s;
   int n=ArraySize(g_poi);
   ArrayResize(g_poi,n+1);
   g_poi[n]=p;
}

void UpdatePOIRegistry(datetime asOf, double atrValue)
{
   if(!InpEnablePhase12 || !InpBuildPOIRegistry) return;
   ArrayResize(g_poi,0);
   int chartSec=PeriodSeconds(PERIOD_CURRENT);
   if(chartSec<=0) chartSec=60;

   for(int i=ArraySize(g_fvgs)-1;i>=0;i--)
   {
      if(!g_fvgs[i].causal || g_fvgs[i].invalidated) continue;
      // فاز ۴۳: مقصد (POI) یک سطح *قابل استفاده* است، پس نقش فعلی نوشته می‌شود.
      // گپ وارونه یک ورودی معتبر در جهت مخالف تولدش است.
      AddPOI(g_fvgs[i].id, POIK_FVG, FVGActiveDir(g_fvgs[i]), g_fvgs[i].top, g_fvgs[i].bottom,
             g_fvgs[i].time, g_fvgs[i].tf, asOf, chartSec, atrValue, false);
   }
   for(int i=ArraySize(g_obs)-1;i>=0;i--)
   {
      ENUM_POI_KIND k=POIK_NONE;
      if(g_obs[i].state==OB_BREAKER)         k=POIK_BREAKER;
      else if(g_obs[i].state==OB_MITIGATION) k=POIK_MITIGATION;
      else if(g_obs[i].state==OB_VALID)      k=POIK_OB;
      if(k==POIK_NONE) continue;
      // فاز ۴۳: همان قاعده برای OB. Breaker و Mitigation Block ناحیه‌هایی هستند
      // که پولاریتی‌شان برگشته (قطبیت عوض شده)، پس نقش فعلی‌شان مخالف جهت تولد
      // است؛ قبلاً رجیستری POI جهت تولد را می‌نوشت و یک Breaker صعودی‌زاد در
      // خروجی «صعودی» گزارش می‌شد، در حالی که رنگ و تعریفش نزولی بود.
      AddPOI(g_obs[i].id, k, OBActiveDir(g_obs[i]), g_obs[i].top, g_obs[i].bottom,
             g_obs[i].time, PERIOD_CURRENT, asOf, chartSec, atrValue, g_obs[i].isExtreme);
      // فاز ۳۶ — Nested / Multi-timeframe Mitigation (منبع: SMC — «Nested /
      // Multi-timeframe Mitigation»): ناحیهٔ HTF که داخل آن POI هم‌جهتِ LTF
      // هست، قوی‌تر است؛ امتیاز POI ناحیهٔ میزبان به‌اندازهٔ یک درجه تقویت
      // می‌شود و در پنل صریح گفته می‌شود. فقط برای نواحی سازگار با Bias مالک.
      // فاز ۴۳: هم‌جهتی با بایاس و هم‌جهتی میزبان/مهمان هر دو با **نقش فعلی**
      // سنجیده می‌شوند (یک ناحیهٔ وارونه یا Breaker دیگر ناحیهٔ هم‌جهت نیست).
      if(OBActiveDir(g_obs[i])==g_htfBias && g_obs[i].tf!=PERIOD_CURRENT)
      {
         for(int j=0;j<ArraySize(g_fvgs);j++)
         {
            if(!g_fvgs[j].causal || g_fvgs[j].invalidated) continue;
            if(FVGActiveDir(g_fvgs[j])!=OBActiveDir(g_obs[i])) continue;
            bool nested=(g_fvgs[j].top<=g_obs[i].top && g_fvgs[j].bottom>=g_obs[i].bottom);
            if(!nested) continue;
            for(int q=0;q<ArraySize(g_poi);q++)
               if(g_poi[q].sourceId==g_obs[i].id){ g_poi[q].score+=4; g_poi[q].valid=true; break; }
            break;   // یک شاهد کافی است؛ امتیاز دو بار داده نشود
         }
      }
   }
   for(int i=ArraySize(g_rejections)-1;i>=0;i--)
   {
      if(g_rejections[i].rejectionState!=REJECTION_FRESH) continue;
      AddPOI(g_rejections[i].id, POIK_REJECTION, g_rejections[i].direction,
             g_rejections[i].top, g_rejections[i].bottom, g_rejections[i].time,
             PERIOD_CURRENT, asOf, chartSec, atrValue, false);
   }
   for(int i=ArraySize(g_trendlines)-1;i>=0;i--)
   {
      if(g_trendlines[i].invalidated) continue;
      double lvl=TrendlinePriceAt(g_trendlines[i], asOf);
      if(lvl<=0.0) continue;
      double band=(atrValue>0.0)? atrValue*0.10 : 0.0;
      AddPOI(g_trendlines[i].id, POIK_TRENDLINE,
             g_trendlines[i].isHigh?DIR_BEAR:DIR_BULL,
             lvl+band, lvl-band, g_trendlines[i].t2, g_trendlines[i].tf,
             asOf, chartSec, atrValue, false);
   }
   for(int i=ArraySize(g_liquidity)-1;i>=0;i--)
   {
      if(g_liquidity[i].state!=LSTATE_FRESH) continue;
      if(g_liquidity[i].type!=LIQ_RANGE_H && g_liquidity[i].type!=LIQ_RANGE_L) continue;
      // #۲۰ مرز رنج یک «سطح» است نه ناحیهٔ بی‌بُعد. پیش از این top=bottom بود و
      // شرط رندر (top>bottom) چنین POI‌ی را هرگز رسم نمی‌کرد، درحالی‌که
      // FindBestPOI همان را به‌عنوان بهترین ناحیه برمی‌گرداند.
      double rband=(atrValue>0.0)? atrValue*0.10 : 0.0;
      AddPOI(g_liquidity[i].id, POIK_RANGE,
             IsHighSideLiquidity(g_liquidity[i].type)?DIR_BEAR:DIR_BULL,
             g_liquidity[i].price+rband, g_liquidity[i].price-rband,
             g_liquidity[i].time, PERIOD_CURRENT, asOf, chartSec, atrValue, false);
   }

   // مرتب‌سازی نزولی بر اساس امتیاز (insertion sort — رجیستری کوچک است)
   int n=ArraySize(g_poi);
   for(int i=1;i<n;i++)
   {
      POIObj key=g_poi[i];
      int j=i-1;
      while(j>=0 && g_poi[j].score<key.score){ g_poi[j+1]=g_poi[j]; j--; }
      g_poi[j+1]=key;
   }
   int cap=MathMax(1,InpMaxPOI);
   if(n>cap) ArrayResize(g_poi,cap);
}

bool FindBestPOI(ENUM_DIRECTION dir, POIObj &out)
{
   for(int i=0;i<ArraySize(g_poi);i++)
   {
      if(!g_poi[i].valid) continue;
      if(dir!=DIR_NONE && g_poi[i].direction!=dir) continue;
      out=g_poi[i];
      return true;
   }
   return false;
}

//--------------------------------------------------------------------
// #۶۷ انتخاب مدل ورود
// هر مدل شرط عددی خودش را دارد؛ مدل انتخابی همان می‌شود که واقعاً شرط‌هایش
// برآورده شده است. ورودی می‌تواند یک مدل را اجبار کند.
//--------------------------------------------------------------------
string EntryModelToStr(ENUM_ENTRY_MODEL m)
{
   switch(m)
   {
      case MODEL_ICT2022:     return "ICT 2022 (Sweep -> MSS -> FVG)";
      case MODEL_BOS_FVG_OB:  return "BOS -> FVG -> OB";
      case MODEL_SWEEP_ENTRY: return "Sweep Entry";
      case MODEL_OTE_ONLY:    return "OTE only";
      default:                return "NONE";
   }
}

ENUM_ENTRY_MODEL SelectEntryModel(bool chainIsMss, bool hasSweep, bool hasChainedDisp,
                                 long fvgId, long obId, bool zoneInOte, bool legAligned)
{
   g_modelReason="";
   if(!InpEnablePhase12)
   {
      g_modelReason="لایهٔ فاز ۱۲ خاموش است";
      return MODEL_NONE;
   }
   bool m2022 = chainIsMss && hasSweep && hasChainedDisp && fvgId!=-1;
   bool mBfo  = hasChainedDisp && fvgId!=-1 && obId!=-1;
   bool mSweep= hasSweep && zoneInOte;
   bool mOte  = legAligned && zoneInOte;

   if(InpPreferredEntryModel>0)
   {
      ENUM_ENTRY_MODEL forced=MODEL_NONE;
      if(InpPreferredEntryModel==1) forced=MODEL_ICT2022;
      else if(InpPreferredEntryModel==2) forced=MODEL_BOS_FVG_OB;
      else if(InpPreferredEntryModel==3) forced=MODEL_SWEEP_ENTRY;
      else if(InpPreferredEntryModel==4) forced=MODEL_OTE_ONLY;
      bool ok=false;
      if(forced==MODEL_ICT2022)     ok=m2022;
      else if(forced==MODEL_BOS_FVG_OB) ok=mBfo;
      else if(forced==MODEL_SWEEP_ENTRY) ok=mSweep;
      else if(forced==MODEL_OTE_ONLY) ok=mOte;
      g_modelReason=ok
         ? ("مدل اجباری از ورودی برآورده شد: "+EntryModelToStr(forced))
         : ("مدل اجباری از ورودی برآورده نشد: "+EntryModelToStr(forced));
      return ok? forced : MODEL_NONE;
   }
   // Phase 42: the model name is the label; the reason after the separator is a
   // pure Persian sentence, so no acronym rides inside a Persian clause.
   if(m2022){ g_modelReason="مدل ۲۰۲۲ | چرخهٔ تغییر کاراکتر با جاروی نقدینگی و کندل جابه‌جایی زنجیرشده و گپ هم‌جهت موجود است"; return MODEL_ICT2022; }
   if(mBfo) { g_modelReason="مدل شکست ساختار تا گپ تا اردر بلاک | شکست ساختار با کندل جابه‌جایی و هم‌پوشانی گپ و اردر بلاک هم‌جهت موجود است"; return MODEL_BOS_FVG_OB; }
   if(mSweep){ g_modelReason="مدل ورود پس از جارو | نقدینگی جارو شده و ناحیهٔ ورود داخل باند ورود بهینه همان لگ است"; return MODEL_SWEEP_ENTRY; }
   if(mOte) { g_modelReason="مدل فقط ورود بهینه | لگ معتبر هم‌جهت بایاس است و ناحیهٔ ورود داخل باند ورود بهینه قرار دارد"; return MODEL_OTE_ONLY; }
   g_modelReason="هیچ مدل شناخته‌شده‌ای شرط‌هایش کامل نشد";
   return MODEL_NONE;
}

//====================================================================
// REVERSAL ENGINE — فاز ۱۱ (#۸ #۷۱ #۱۰ #۷۰)
// برگشت «تأییدشده» فقط یک معنا دارد: کندل بسته‌شدهٔ HTF فراتر از سطح
// محافظت‌شدهٔ خارجی بسته شود (close کندل بسته، نه فتیله). این موتور:
//   • شناسهٔ سطح محافظت‌شده را به قیمت واقعی تبدیل می‌کند (#۸/#۷۱)،
//   • یک رویداد EVT_EXTERNAL_BREAK روی H4 می‌سازد،
//   • شواهد Smart Money Reversal را عددبه‌عدد می‌شمارد (#۷۰)،
//   • خروجی «برگشت تأییدشده» را به لایهٔ Exhaustion می‌دهد.
// تضمین #۱۰: هیچ خطی در این فایل بیرون از EvaluateStructureBreak/HTF
// مقدار g_htfBias را نمی‌نویسد؛ Exhaustion به‌تنهایی هرگز Bias را برنمی‌گرداند.
//====================================================================
int ChartBarsBetween(datetime from, datetime to)
{
   if(from<=0 || to<=from) return 0;
   int sec=PeriodSeconds(PERIOD_CURRENT);
   if(sec<=0) sec=60;
   return (int)(((long)to-(long)from)/(long)sec);
}

void RegisterExternalBreakEvent(ENUM_DIRECTION dir, datetime barTime, double levelPrice)
{
   long id=StableEventId(barTime, EVT_EXTERNAL_BREAK, dir, g_reversal.levelSwingId, true);
   g_reversal.eventId=id;
   for(int i=ArraySize(g_events)-1;i>=0;i--)
      if(g_events[i].id==id) return;   // همین شکست قبلأً ثبت شده — تکرار ممنوع

   StructureEvent e;
   e.id=id;
   e.type=EVT_EXTERNAL_BREAK;
   e.direction=dir;
   e.time=barTime;
   e.price=levelPrice;      // سطح محافظت‌شدهٔ خارجی که رد شد
   e.brokenSwingId=g_reversal.levelSwingId;
   // سطح محافظت‌شدهٔ مقابل در لحظهٔ شکست؛ پس از این کندل خودش محافظ می‌شود
   e.protectedSwingId=(dir==DIR_BULL)? g_htfProtectedHighId : g_htfProtectedLowId;
   e.confirmationBarShift=0;                       // shift صفر در سری HTF = کندل بستهٔ HTF
   e.displacementId=g_reversal.smrDispId;
   e.sweepId=g_reversal.smrSweepId;
   e.parentEventId=-1;
   e.isHTF=true;
   AppendStructureEvent(e);
   PersistStructureEvent(e);
   if(!g_rebuildMode)
      Print(StringFormat("ICT REVERSAL: EXTERNAL_BREAK %s | %s | protected %s %s broken by closed %s bar (close %s) | SMR %d/%d",
            DirToStr(dir), TimeToString(barTime,TIME_DATE|TIME_MINUTES),
            g_reversal.levelIsHigh?"HIGH":"LOW", DoubleToString(levelPrice,_Digits),
            EnumToString(InpHTF), DoubleToString(g_reversal.snapBarClose,_Digits),
            g_reversal.smrScore, g_reversal.smrMax));
}

// #۷۰ — Smart Money Reversal روی شواهد اثبات‌شدهٔ همین پروژه ساخته می‌شود، نه
// روی یک الگوی کندلی حدسی. چهار شاهد شمارش می‌شوند و آستانه از ورودی می‌آید.
// تعریف عملیاتی دقیقاً همین است و در مستندات ثبت می‌شود: این سنجه «قوی‌تر»
// از برگشت ساده است، نه یک قاعدهٔ خصوصی منسوب به شخص سوم.
void ScoreSmartMoneyReversal(ENUM_DIRECTION dir, datetime barOpen, datetime barCloseTime)
{
   g_reversal.smrScore=0;
   g_reversal.smrReason="";
   g_reversal.smr=false;
   g_reversal.smrSweepId=-1; g_reversal.smrDispId=-1; g_reversal.smrZoneId=-1;
   g_reversal.smrMax=4;

   int htfSec=PeriodSeconds(InpHTF);
   if(htfSec<=0) htfSec=14400;
   long window=(long)htfSec*(long)MathMax(1,InpSMR_SweepLookbackBars);
   datetime from=(datetime)((long)barOpen-window);

   // ۱) Sweep نقدینگی مقابل در همان پنجره (BSL برای برگشت نزولی، SSL برای صعودی)
   bool wantHighSide=(dir==DIR_BEAR);
   long sweepId=-1;
   for(int i=ArraySize(g_liquidity)-1;i>=0;i--)
   {
      if(g_liquidity[i].state!=LSTATE_SWEPT || g_liquidity[i].sweptTime<=0) continue;
      if(g_liquidity[i].sweptTime<from || g_liquidity[i].sweptTime>barCloseTime) continue;
      if(IsHighSideLiquidity(g_liquidity[i].type)!=wantHighSide) continue;
      sweepId=g_liquidity[i].id;
      break;
   }
   g_reversal.smrSweepId=sweepId;
   if(sweepId!=-1)
   {
      g_reversal.smrScore++;
      g_reversal.smrReason+=StringFormat("SWEEP | نقدینگی %s شماره #%s؛ ", wantHighSide?"سمت خرید":"سمت فروش", IdToStr(sweepId));
   }

   // ۲) Displacement زنجیرشدهٔ هم‌جهت (energyOnly=false یعنی به ساختار وصل است)
   long dispId=-1;
   for(int i=ArraySize(g_displacements)-1;i>=0;i--)
   {
      if(g_displacements[i].direction!=dir) continue;
      if(g_displacements[i].energyOnly) continue;
      if(g_displacements[i].time<from || g_displacements[i].time>barCloseTime) continue;
      dispId=g_displacements[i].id;
      break;
   }
   g_reversal.smrDispId=dispId;
   if(dispId!=-1)
   {
      g_reversal.smrScore++;
      g_reversal.smrReason+=StringFormat("Displacement زنجیرشده #%s؛ ", IdToStr(dispId));
   }

   // ۳) ناحیهٔ هم‌جهت (FVG causal معتبر یا Order Block معتبر)
   long zoneId=-1;
   // فاز ۴۳: شاهد «ناحیهٔ هم‌جهت» با نقش فعلی سنجیده می‌شود — گپ وارونه در جهت
   // مخالف تولدش شاهد این دروازه است، نه در جهت تولدش.
   for(int i=ArraySize(g_fvgs)-1;i>=0;i--)
      if(FVGActiveDir(g_fvgs[i])==dir && g_fvgs[i].causal && !g_fvgs[i].invalidated){ zoneId=g_fvgs[i].id; break; }
   if(zoneId==-1)
      for(int i=ArraySize(g_obs)-1;i>=0;i--)
         if(g_obs[i].direction==dir && g_obs[i].state==OB_VALID){ zoneId=g_obs[i].id; break; }
   g_reversal.smrZoneId=zoneId;
   if(zoneId!=-1)
   {
      g_reversal.smrScore++;
      g_reversal.smrReason+=StringFormat("ناحیهٔ هم‌جهت #%s؛ ", IdToStr(zoneId));
   }

   // ۴) هم‌جهت‌شدن ساختار داخلی/پایین‌تر با جهت برگشت
   bool ctxOk=(g_internalDir==dir) || (g_mtfContext[1].externalDirection==dir) ||
              (g_mtfContext[2].externalDirection==dir) || (g_mtfContext[3].externalDirection==dir);
   if(ctxOk)
   {
      g_reversal.smrScore++;
      g_reversal.smrReason+="هم‌جهتی ساختار داخلی/پایین‌تر با جهت برگشت؛ ";
   }

   g_reversal.smr=(g_reversal.smrScore>=InpSMR_MinScore);
   if(StringLen(g_reversal.smrReason)==0)
      g_reversal.smrReason="هیچ شاهد اضافی برای برگشت پول هوشمند پیدا نشد؛ ";
   g_reversal.smrReason+=StringFormat("%d از %d شرط", g_reversal.smrScore, g_reversal.smrMax);
}

void UpdateReversalEngine(datetime asOf, double closePrice, double atrValue)
{
   g_reversal.armed=false;
   g_reversal.smrMax=4;
   g_reversal.barsSince=ChartBarsBetween(g_reversal.confirmedCloseTime, asOf);

   if(!InpEnableReversalGate)
   {
      g_reversal.state="DISABLED";
      g_reversal.reason="دروازهٔ برگشت با ورودی مربوطه خاموش است؛ هیچ برگشتی تأیید نمی‌شود";
      return;
   }

   // دروازه از تصویر *پیش از* ارزیابی ساختار می‌آید، نه از Bias جاری
   // (Bias جاری می‌تواند در همین کندل عوض شده باشد و سطح را جابه‌جا کرده باشد).
   ENUM_DIRECTION guardBias=g_reversal.snapBias;
   g_reversal.levelSwingId=g_reversal.snapGuardId;
   g_reversal.levelPrice   =g_reversal.snapGuardPrice;
   g_reversal.levelTime    =g_reversal.snapGuardLevelTime;
   g_reversal.levelIsHigh  =g_reversal.snapGuardIsHigh;
   g_reversal.armed        =g_reversal.snapGuardOk;

   if(guardBias==DIR_NONE)
   {
      g_reversal.state="WAITING_H4_BIAS";
      g_reversal.reason="تا وقتی بایاس مالک تایم‌فریم بالاتر تأیید نشود، هیچ برگشتی اعلام نمی‌شود";
      return;
   }
   if(!g_reversal.snapGuardOk)
   {
      g_reversal.state="WAITING_PROTECTED_LEVEL";
      g_reversal.reason="سویینگ محافظت‌شدهٔ خارجی در رجیستری تایم‌فریم بالاتر پیدا نشد؛ یا آخرین رویداد آن تایم‌فریم سویینگ محافظ نداده، یا با سقف تعداد سویینگ‌ها حذف شده است";
      return;
   }
   if(g_reversal.snapBarTime<=0 || g_reversal.snapBarClose<=0.0)
   {
      g_reversal.state="WAITING_HTF_DATA";
      g_reversal.reason="دادهٔ کندل بستهٔ کافی روی تایم‌فریم بالاتر برای سنجش سطح محافظت‌شده وجود ندارد";
      return;
   }

   ENUM_DIRECTION revDir=OppositeDir(guardBias);

   // سطحی که در همان کندل (یا بعد از آن) ساخته شده، با همان کندل سنجیده نمی‌شود
   if(g_reversal.snapGuardLevelTime>0 && g_reversal.snapBarTime<=g_reversal.snapGuardLevelTime)
   {
      g_reversal.state=g_reversal.confirmed?"CONFIRMED":"ARMED";
      g_reversal.reason="سطح محافظت‌شده تازه ثبت شده است؛ سنجش از کندل بستهٔ بعدی تایم‌فریم بالاتر انجام می‌شود";
      return;
   }

   bool broke=(guardBias==DIR_BULL) ? (g_reversal.snapBarClose<g_reversal.levelPrice)
                                    : (g_reversal.snapBarClose>g_reversal.levelPrice);
   if(!broke)
   {
      if(!g_reversal.confirmed)
      {
         g_reversal.state="ARMED";
         g_reversal.reason=StringFormat("سطح محافظت‌شدهٔ خارجی (%s %.2f) با قیمت بستهٔ %.2f آخرین کندل بستهٔ تایم‌فریم بالاتر رد نشده است؛ برگشتی تأیید نمی‌شود",
                                        g_reversal.levelIsHigh?"سقف":"کف", g_reversal.levelPrice, g_reversal.snapBarClose);
      }
      else g_reversal.state="CONFIRMED";
      return;
   }

   // --- شکست سطح محافظت‌شدهٔ خارجی = تنها مسیر اعلام برگشت تأییدشده ---
   bool newBreak=(g_reversal.confirmedTime!=g_reversal.snapBarTime);
   if(newBreak)
   {
      g_reversal.confirmed=true;
      g_reversal.priorBias=guardBias;
      g_reversal.dir=revDir;
      g_reversal.confirmedTime=g_reversal.snapBarTime;
      g_reversal.confirmedCloseTime=(datetime)((long)g_reversal.snapBarTime+(long)PeriodSeconds(InpHTF));
      g_reversal.confirmedClose=g_reversal.snapBarClose;
      g_reversal.barsSince=ChartBarsBetween(g_reversal.confirmedCloseTime, asOf);
      // شواهد Smart Money Reversal باید بعد از تازه‌سازی MTF خوانده شود؛
      // UpdateReversalEngine در UpdateContextForClosedBar بعد از
      // AnalyzeMTFContext صدا زده می‌شود و همین ترتیب رعایت می‌شود.
      ScoreSmartMoneyReversal(revDir, g_reversal.confirmedTime, g_reversal.confirmedCloseTime);
      RegisterExternalBreakEvent(revDir, g_reversal.snapBarTime, g_reversal.levelPrice);
   }
   g_reversal.dir=revDir;
   g_reversal.state="CONFIRMED";
   g_reversal.reason=StringFormat("کندل بستهٔ %s در %s با قیمت بستهٔ %.2f فراتر از سطح محافظت‌شدهٔ خارجی (%s %.2f) بسته شد؛ این تنها مسیر اعلام برگشت تأییدشده است — فتیله کافی نیست",
                                  TfFa(InpHTF), TimeToString(g_reversal.confirmedTime,TIME_DATE|TIME_MINUTES),
                                  g_reversal.confirmedClose, g_reversal.levelIsHigh?"سقف":"کف", g_reversal.levelPrice);
}

// ابزار فقط-خواندنی برای اثبات با داده: فقط روی تغییر وضعیت یا کندل جدید HTF
// یک ردیف می‌نویسد تا فایل کوچک و قابل مقایسه بماند.
void PersistReversalDiagnostics(datetime barTime)
{
   if(!InpWriteReversalDiagnostics) return;
   static string   lastState="-";
   static datetime lastHtfBar=0;
   static datetime lastConfirm=0;
   bool htfChanged  =(g_reversal.snapBarTime!=lastHtfBar);
   bool stateChanged=(g_reversal.state!=lastState);
   bool newConfirm  =(g_reversal.confirmedTime!=lastConfirm);
   if(!htfChanged && !stateChanged && !newConfirm) return;
   lastState=g_reversal.state; lastHtfBar=g_reversal.snapBarTime; lastConfirm=g_reversal.confirmedTime;

   // فاز ۴۷: تایم‌فریم در نام فایل. چرا: دو چارت زندهٔ یک نماد (M1 و M15)
   // ردیف‌هایشان را در یک فایل می‌ریختند و هر سنجش «نرخ تأیید در کندل بعد»
   // ناخواسته دو تایم‌فریم را قاطی می‌کرد. کاربر خواسته است هر تایم‌فریم برای
   // خودش باشد و نام فایل صریح‌ترین جای بیان همان جداسازی است.
   int handle=DiagOpen("ICT_Assistant_Canonical_Reversal_Diag_"+ChartTfCode()+".csv");
   if(handle==INVALID_HANDLE) return;
   // خود-ترمیمی سرستون (فاز ۱۲): فایل‌های بازماندهٔ buildهای قدیمی سرستون
   // نداشتند و ردیف‌های کهنهٔ آن‌ها (با مقادیر پیش‌فرض صفر مثل GuardId=0) از
   // ردیف تازه قابل تشخیص نبود — همان چیزی که در سنجش فاز ۱۲ گمراه‌کننده شد.
   bool needHeader=(FileSize(handle)==0);
   if(!needHeader)
   {
      FileSeek(handle,0,SEEK_SET);
      string firstKey=FileReadString(handle);
      bool headerOk=(StringLen(firstKey)>0 && StringFind(firstKey,"ChartBar")>=0);
      if(headerOk)
      {
         // فاز ۱۵: ستون Symbol اضافه شد. بدون آن، ردیف‌های دو چارت زندهٔ
         // مختلف در همین فایل قاطی می‌شدند و هیچ راهی برای نسبت‌دادن یک ردیف
         // به نمادش وجود نداشت (شاهد غیرقابل‌استفاده).
         // نکتهٔ فاز ۴۷: سرستون حالا ستون ChartTF هم دارد، ولی چون نام فایل
         // خودش تایم‌فریم را در بر دارد، فایل‌های قدیمی هرگز با این نام روبه‌رو
         // نمی‌شوند؛ پس تشخیص «سرستون نامناسب» فقط همان شرط Symbol را می‌سنجد و
         // عوض‌کردن تعداد ستون‌ها باعث حذف بی‌دلیل فایل نمی‌شود.
         string secondKey=FileReadString(handle);
         if(StringFind(secondKey,"Symbol")<0) headerOk=false;
      }
      if(!headerOk)
      {
         // فاز ۲۴: هندل نگه‌داشته‌شده باید اول رها شود، وگرنه حذف/بازکردن فایل
         // روی هندل باز شکست می‌خورد و ردیف‌ها با سرستون کهنه مخلوط می‌شدند.
         DiagDrop("ICT_Assistant_Canonical_Reversal_Diag_"+ChartTfCode()+".csv");
         FileClose(handle);
         FileDelete("ICT_Assistant_Canonical_Reversal_Diag_"+ChartTfCode()+".csv",FILE_COMMON);
         handle=DiagOpen("ICT_Assistant_Canonical_Reversal_Diag_"+ChartTfCode()+".csv");
         if(handle==INVALID_HANDLE) return;
         needHeader=true;
      }
   }
   // ChartTF در **انتهای** سرستون می‌آید تا خواننده‌های قدیمی که بر اساس شمارهٔ
   // ستون کار می‌کنند دست‌نخورده بمانند (فاز ۴۷).
   if(needHeader)
      FileWrite(handle,"ChartBar","Symbol","State","BiasSnapshot","GuardId","GuardPrice","GuardSide","HtfBar","HtfClose","Broke","ConfirmedTime","ConfirmedClose","BarsSince","SmartMoneyReversal","SMRScore","SMRMax","SweepId","DispId","ZoneId","EventId","BuildStamp","ChartTF");
   // اگر بازنویسی سرستون ناممکن باشد (مثلاً نمونهٔ دیگری فایل را قفل کرده)،
   // یک ردیف مبهم نوشته *نمی‌شود*؛ به‌جایش یک‌بار در Journal هشدار داده می‌شود.
   else
   {
      FileSeek(handle,0,SEEK_SET);
      FileReadString(handle);
      if(StringFind(FileReadString(handle),"Symbol")<0) { DiagClose(handle); return; }
   }
   FileSeek(handle,0,SEEK_END);
   bool broke=(g_reversal.confirmedTime!=0 && g_reversal.confirmedTime==g_reversal.snapBarTime);
   FileWrite(handle,
             TimeToString(barTime,TIME_DATE|TIME_MINUTES),
             _Symbol,                              // فاز ۱۵: نسبت‌دادن ردیف به نماد
             g_reversal.state,
             DirToStr(g_reversal.snapBias),
             IdToStr(g_reversal.levelSwingId),
             DoubleToString(g_reversal.levelPrice,_Digits),
             g_reversal.armed?(g_reversal.levelIsHigh?"HIGH":"LOW"):"-",
             TimeToString(g_reversal.snapBarTime,TIME_DATE|TIME_MINUTES),
             DoubleToString(g_reversal.snapBarClose,_Digits),
             broke?"true":"false",
             TimeToString(g_reversal.confirmedTime,TIME_DATE|TIME_MINUTES),
             DoubleToString(g_reversal.confirmedClose,_Digits),
             g_reversal.barsSince,
             g_reversal.smr?"true":"false",
             g_reversal.smrScore,
             g_reversal.smrMax,
             IdToStr(g_reversal.smrSweepId),
             IdToStr(g_reversal.smrDispId),
             IdToStr(g_reversal.smrZoneId),
             IdToStr(g_reversal.eventId),
             g_buildStamp,
             ChartTfCode());
   DiagClose(handle);
}

//====================================================================
// فاز ۱۲ — مهر بارگذاری و دفتر شاهد عددی لایهٔ SMC/MMM
//====================================================================
// چرا مهر: بارها پیش آمد که «کدام build روی چارت فعال است؟» فقط با مقایسهٔ
// دستی زمان فایل‌ها حدس زده می‌شد و شاهد کهنه با شاهد تازه قاطی می‌شد.
// یک مهر کوچک در COMMON\Files این ابهام را برای همیشه برمی‌دارد.
void PersistLoadStamp()
{
   int h=FileOpen("ICT_Assistant_Canonical_Load.csv",FILE_COMMON|FILE_WRITE|FILE_CSV|FILE_UNICODE,';');
   if(h==INVALID_HANDLE) return;
   int nyHours=NyOffsetSecondsUTC(ServerToUTC(TimeCurrent()))/3600;
   FileWrite(h,"Key","Value");
   FileWrite(h,"BuildStamp",g_buildStamp);
   FileWrite(h,"Symbol",_Symbol);
   FileWrite(h,"ChartTF",EnumToString(PERIOD_CURRENT));
   FileWrite(h,"HTF",EnumToString(InpHTF));
   FileWrite(h,"SessionSourceTF",EnumToString(InpSessionSourceTF));
   FileWrite(h,"BrokerGMTOffsetMin",IntegerToString((int)(g_serverGMTOffsetSeconds/60)));
   FileWrite(h,"NYOffsetHours",IntegerToString(nyHours));
   FileWrite(h,"US_DSTforNYClock",InpUseUS_DSTForNYClock?"ON":"OFF");
   // فاز ۱۵
   FileWrite(h,"BrokerDSTRule",BrokerDSTRuleToStr(g_brokerDSTRule));
   FileWrite(h,"BrokerStdOffsetMin",IntegerToString((int)(g_brokerStdOffsetSeconds/60)));
   FileWrite(h,"HistoricalOffsetMode",InpUseHistoricalBrokerOffset?"HISTORICAL":"CURRENT");
   FileWrite(h,"TrackSetupLifecycle",InpTrackSetupLifecycle?"ON":"OFF");
   FileWrite(h,"DrawHTFEvents",InpDrawHTFEvents?"ON":"OFF");
   FileWrite(h,"Phase12",InpEnablePhase12?"ON":"OFF");
   FileWrite(h,"ReversalGate",InpEnableReversalGate?"ON":"OFF");
   FileWrite(h,"ProgramName",MQLInfoString(MQL_PROGRAM_NAME));
   FileWrite(h,"TerminalBuild",IntegerToString((int)TerminalInfoInteger(TERMINAL_BUILD)));
   FileClose(h);
}

// هر ردیف = یک کندل چارت، فقط وقتی کندل HTF یا وضعیت عوض شود. این فایل
// پرسش «لایهٔ فاز ۱۲ واقعاً چه چیزی تولید کرد؟» را با عدد جواب می‌دهد:
// چند خط مورب ساخته شد و چند بار لمس شدند، رنج معتبر بود یا با چه عددی رد
// شد، سطوح IPDA ثبت شد یا داده کافی نبود، چند گپ Implied/Micro، بهترین POI،
// مدل ورود، امتیاز کیفیت و سن/فاز روند.
void PersistPhase12Diagnostics(datetime barTime)
{
   if(!InpWriteReversalDiagnostics) return;
   int tlOk=0, tlInv=0, tlTouch=0, tlSwept=0;
   for(int i=0;i<ArraySize(g_trendlines);i++)
   {
      if(g_trendlines[i].swept) tlSwept++;
      if(g_trendlines[i].invalidated){ tlInv++; continue; }
      tlOk++; tlTouch+=g_trendlines[i].touches;
   }
   // فاز ۲۸: گپ‌هایی که Implied/Micro نیستند باید در همین شمارنده بیایند، وگرنه
   // نوع جدید Volume Imbalance بی‌صدا از شاهد حذف می‌شد و ستون کیفیت اشتباه می‌شد.
   int fImp=0, fMic=0, fExtra=0;
   for(int i=0;i<ArraySize(g_fvgs);i++)
   {
      if(g_fvgs[i].kind==FVGK_IMPLIED)              fImp++;
      else if(g_fvgs[i].kind==FVGK_MICRO)           fMic++;
      else if(g_fvgs[i].kind==FVGK_VOL_IMBALANCE)   fExtra++;
   }
   POIObj best;
   bool hasBest=FindBestPOI(DIR_NONE,best);

   string sig=TrendPhaseToStr(g_trend.phase)+"|"+g_reversal.state+"|"+IntegerToString(tlOk)
              +"|"+IntegerToString(tlSwept)
              +"|"+IntegerToString(fImp+fMic+fExtra)+"|"+(g_rangeOk?"1":"0")+"|"+(g_ipdaOk?"1":"0")
              +"|"+IntegerToString((int)g_setup.entryModel)+"|"+IntegerToString(g_setup.quality)
              +"|"+g_setup.status;
   static datetime lastBar=0;
   static string   lastSig="";
   if(barTime==lastBar && sig==lastSig) return;
   lastBar=barTime; lastSig=sig;

   int h=DiagOpen("ICT_Assistant_Canonical_Phase12_Diag.csv");
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0)
      FileWrite(h,"BarTime","BuildStamp","Bias","TrendAge","TrendPhase","InternalDir",
                "TrendlineOk","TrendlineInvalid","TrendlineTouches","TrendlineSwept","TrendlineBuilt","TrendlineReject",
                "RangeOk","RangeHigh","RangeLow","RangeHighTouches","RangeLowTouches","RangeReject",
                "IPDAOk","IPDANote","ImpliedFVG","MicroFVG",
                "POICount","BestPOIKind","BestPOIScore",
                "EntryModel","ModelReason","Quality","QualityMin","SetupStatus");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,
             TimeToString(barTime,TIME_DATE|TIME_MINUTES),
             g_buildStamp,
             DirToStr(g_htfBias),
             g_trend.ageBars,
             TrendPhaseToStr(g_trend.phase),
             DirToStr(g_htfInternalDir),
             tlOk, tlInv, tlTouch, tlSwept,
             g_trendlineBuilt?"true":"false",
             g_trendlineReject,
             g_rangeOk?"true":"false",
             DoubleToString(g_rangeHigh,_Digits),
             DoubleToString(g_rangeLow,_Digits),
             g_rangeHighTouches, g_rangeLowTouches,
             g_rangeReject,
             g_ipdaOk?"true":"false",
             g_ipdaNote,
             fImp, fMic,
             ArraySize(g_poi),
             hasBest? PoiKindToStr(best.kind) : "NONE",
             hasBest? best.score : 0,
             EntryModelToStr(g_setup.entryModel),
             g_setup.modelReason,
             g_setup.quality,
             InpMinQualityScore,
             g_setup.status);
   DiagClose(h);
}

//====================================================================
// DRAWING
//====================================================================
string EventReasonText(const StructureEvent &e)
{
   string reason = EventTypeToStr(e.type);
   reason += " | TF=" + EnumToString(e.isHTF?InpHTF:PERIOD_CURRENT);
   reason += " | closed-bar confirmation (shift " + IntegerToString(e.confirmationBarShift) + ")";
   if(e.sweepId!=-1)         reason += " | sweep #" + IdToStr(e.sweepId);
   if(e.displacementId!=-1)  reason += " | displacement #" + IdToStr(e.displacementId);
   if(e.brokenSwingId!=-1)   reason += " | broke swing #" + IdToStr(e.brokenSwingId);
   if(e.protectedSwingId!=-1) reason += " | protected opposite #" + IdToStr(e.protectedSwingId);
   if(e.type==EVT_MSS)        reason += " | causal: sweep + displacement";
   else if(e.type==EVT_CHOCH) reason += " | CHoCH without displacement (candidate)";
   else                       reason += " | continuation break";
   return reason;
}

// فاز ۱۵: نام کوتاه تایم‌فریم برای برچسب روی چارت (PERIOD_H4 → H4)
string TFShortName(ENUM_TIMEFRAMES tf)
{
   string s=EnumToString(tf);
   StringReplace(s,"PERIOD_","");
   return s;
}

void DrawStructureEvent(const StructureEvent &e)
{
   string name = "ICTv13_EVT_"+IdToStr(e.id);
   ObjectCreate(0,name,OBJ_TEXT,0,e.time,e.price);
   // فاز ۱۵: روی برچسب HTF، مالک تایم‌فریم صریح نوشته می‌شود تا با رویداد
   // همان تایم‌فریم چارت قاطی نشود.
   string evtTxt = EventTypeToStr(e.type)+(e.direction==DIR_BULL?" ↑":" ↓");
   if(e.isHTF) evtTxt = TFShortName(InpHTF)+" "+evtTxt;
   ObjectSetString(0,name,OBJPROP_TEXT, evtTxt);
   ObjectSetInteger(0,name,OBJPROP_COLOR, e.direction==DIR_BULL?InpColorBull:InpColorBear);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE, e.isHTF? 10 : 9);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,"\n");
   MarkDrawnLayerObj(name);

   // مرز ساختاری شکسته‌شده: خط افقی روی سطح، با دلیل کامل
   string lineName = "ICTv13_EVTL_"+IdToStr(e.id);
   datetime lineEnd = e.time + PeriodSeconds(e.isHTF? InpHTF : PERIOD_CURRENT)*10;
   if(ObjectFind(0,lineName)<0) ObjectCreate(0,lineName,OBJ_TREND,0,e.time,e.price,lineEnd,e.price);
   ObjectSetInteger(0,lineName,OBJPROP_TIME,0,e.time);
   ObjectSetDouble(0,lineName,OBJPROP_PRICE,0,e.price);
   ObjectSetInteger(0,lineName,OBJPROP_TIME,1,lineEnd);
   ObjectSetDouble(0,lineName,OBJPROP_PRICE,1,e.price);
   ObjectSetInteger(0,lineName,OBJPROP_COLOR, e.direction==DIR_BULL?InpColorBull:InpColorBear);
   ObjectSetInteger(0,lineName,OBJPROP_STYLE,STYLE_DASH);
   ObjectSetInteger(0,lineName,OBJPROP_WIDTH,1);
   ObjectSetString(0,lineName,OBJPROP_TOOLTIP,"\n");
   MarkDrawnLayerObj(lineName);
}

void DrawFVG(const FVGObj &f)
{
   // فاز ۴۳: رنگ از **نقش فعلی** گرفته می‌شود، نه از جهت تولد. برای گپ وارونه،
   // نقش مخالف تولد است و رنگ اختصاصی وارونگی (بنفش) در پایین رویش می‌نشیند؛
   // ولی برای گپ سالم، رنگ دقیقاً همان چیزی است که پنل و CSV هم می‌گویند —
   // پیش‌تر اینجا قبل از وارونگی سبز/قرمزِ تولد رسم می‌شد و مربع بنفش با ردیف
   // CSV متناقض می‌شد.
   color clr = FVGActiveDir(f)==DIR_BULL?InpColorBull:InpColorBear;
   string stateTxt = "FRESH imbalance";
   if(!f.causal)        { clr=PAL_STATE_NOCAUSAL; stateTxt="imbalance without causal displacement"; }
   if(f.mitigated)      { clr=PAL_STATE_MITIGATED; stateTxt="touched (mitigated) - not fresh anymore"; }
   if(f.inverted)       { clr=PAL_FVG_INVERTED;  stateTxt="iFVG: closed through, polarity inverted"; }
   if(f.invalidated)    { clr=PAL_STATE_INVALID; stateTxt="expired/invalid"; }

   string name = "ICTv13_FVG_"+IdToStr(f.id);
   datetime t2 = f.time + PeriodSeconds()*InpZoneExtendBars;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE,0,f.time,f.top,t2,f.bottom);
   ObjectSetInteger(0,name,OBJPROP_TIME,0,f.time);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,f.top);
   ObjectSetInteger(0,name,OBJPROP_TIME,1,t2);
   ObjectSetDouble(0,name,OBJPROP_PRICE,1,f.bottom);
   ObjectSetInteger(0,name,OBJPROP_COLOR, clr);
   ObjectSetInteger(0,name,OBJPROP_FILL,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,"\n");
   MarkDrawnLayerObj(name);

   // CE (Consequent Encroachment) = میانهٔ ناحیه
   string ceName = "ICTv13_FVGCE_"+IdToStr(f.id);
   double ce = (f.top+f.bottom)/2.0;
   datetime ceEnd = f.time + PeriodSeconds()*InpZoneExtendBars;
   if(ObjectFind(0,ceName)<0) ObjectCreate(0,ceName,OBJ_TREND,0,f.time,ce,ceEnd,ce);
   ObjectSetInteger(0,ceName,OBJPROP_TIME,0,f.time);
   ObjectSetDouble(0,ceName,OBJPROP_PRICE,0,ce);
   ObjectSetInteger(0,ceName,OBJPROP_TIME,1,ceEnd);
   ObjectSetDouble(0,ceName,OBJPROP_PRICE,1,ce);
   ObjectSetInteger(0,ceName,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,ceName,OBJPROP_STYLE,STYLE_DOT);
   ObjectSetInteger(0,ceName,OBJPROP_WIDTH,1);
   ObjectSetString(0,ceName,OBJPROP_TOOLTIP,"\n");
   MarkDrawnLayerObj(ceName);
}

void DrawOB(const OBObj &o)
{
   color clr = o.direction==DIR_BULL?PAL_OB_BULL:PAL_OB_BEAR;
   // فاز ۳۶: External OB ضخیم‌تر (مبدأ لگ)؛ Internal نازک‌تر — تمایز بصری بدون شلوغی
   int lineWidth = (o.scope==SCOPE_EXTERNAL)? 3 : 2;
   string stateTxt = "VALID (unmitigated)";
   if(o.state==OB_MITIGATED) { clr=PAL_STATE_MITIGATED; stateTxt="MITIGATED (touched)"; }
   if(o.state==OB_BROKEN)    { clr=PAL_STATE_BROKEN;    stateTxt="BROKEN (structural violation)"; }
   if(o.state==OB_BREAKER)   { clr=PAL_OB_BREAKER;      stateTxt="BREAKER (retested after polarity flip)"; }
   if(o.state==OB_INVALID)   { clr=PAL_STATE_INVALID;   stateTxt="INVALID (no displacement/structure link)"; }

   string name = "ICTv13_OB_"+IdToStr(o.id);
   datetime t2 = o.time + PeriodSeconds()*InpZoneExtendBars;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE,0,o.time,o.top,t2,o.bottom);
   ObjectSetInteger(0,name,OBJPROP_TIME,0,o.time);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,o.top);
   ObjectSetInteger(0,name,OBJPROP_TIME,1,t2);
   ObjectSetDouble(0,name,OBJPROP_PRICE,1,o.bottom);
   ObjectSetInteger(0,name,OBJPROP_COLOR, clr);
   ObjectSetInteger(0,name,OBJPROP_FILL,false);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,lineWidth);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,"\n");
   MarkDrawnLayerObj(name);
}

void DrawRejection(const RejectionObj &r)
{
   // Rejection باطل‌شده رسم نمی‌شود (فیلتر در DrawZoneLayer هم اعمال شده؛
   // این شرط دفاعی دوم است تا با هر مسیر رسمی چیزی از گذشته فیلدشده نماند).
   if(InpHideInvalidatedObjects && r.rejectionState==REJECTION_INVALID) return;
   color clr = r.direction==DIR_BULL?PAL_REJ_BULL:PAL_REJ_BEAR;
   if(r.rejectionState==REJECTION_TOUCHED) clr=PAL_STATE_MITIGATED;
   if(r.rejectionState==REJECTION_INVALID) clr=PAL_STATE_INVALID;
   string name="ICTv13_REJECTION_"+IdToStr(r.id);
   datetime t2=r.time+PeriodSeconds()*InpZoneExtendBars;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE,0,r.time,r.top,t2,r.bottom);
   ObjectSetInteger(0,name,OBJPROP_TIME,0,r.time);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,r.top);
   ObjectSetInteger(0,name,OBJPROP_TIME,1,t2);
   ObjectSetDouble(0,name,OBJPROP_PRICE,1,r.bottom);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DOT);
   ObjectSetInteger(0,name,OBJPROP_FILL,false);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,"\n");
   MarkDrawnLayerObj(name);
}

void DrawLocationLine(const string label, const double price, const color lineColor, const string tooltip)
{
   if(price<=0.0) return;
   string name="ICTv13_LOCATION_"+label;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_HLINE,0,0,price);
   ObjectSetDouble(0,name,OBJPROP_PRICE,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,lineColor);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DASHDOT);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,"\n");
   MarkDrawnLayerObj(name);
}

void DrawLocationLevels()
{
   if(!g_leg.valid) return;
   double range=g_leg.range;
   double eq=g_leg.eq;
   double oteLow=0.0, oteHigh=0.0, golden=0.0;
   if(g_leg.dir==DIR_BULL)
   {
      oteLow  = g_leg.high - range*InpOTE_High;
      oteHigh = g_leg.high - range*InpOTE_Low;
      golden  = g_leg.high - range*InpOTE_Golden;
   }
   else
   {
      oteLow  = g_leg.low + range*InpOTE_Low;
      oteHigh = g_leg.low + range*InpOTE_High;
      golden  = g_leg.low + range*InpOTE_Golden;
   }
   DrawLocationLine("EQ",eq,PAL_LOC_EQ,"");
   DrawLocationLine("OTE_LOW",oteLow,PAL_LOC_OTE,"");
   DrawLocationLine("OTE_HIGH",oteHigh,PAL_LOC_OTE,"");
   DrawLocationLine("GOLDEN",golden,PAL_LOC_GOLDEN,"");

   // خودِ لگ: خط بین پیوت آغاز و پیوت پایان — همان دو نقطه‌ای که کاربر
   // می‌تواند فیبوی دستی را روی آن بگذارد (#۴۳/#۴۶).
   string legName="ICTv13_LOCATION_LEG";
   if(ObjectFind(0,legName)<0) ObjectCreate(0,legName,OBJ_TREND,0,g_leg.startTime,g_leg.startPrice,g_leg.endTime,g_leg.endPrice);
   ObjectSetInteger(0,legName,OBJPROP_TIME,0,g_leg.startTime);
   ObjectSetDouble(0,legName,OBJPROP_PRICE,0,g_leg.startPrice);
   ObjectSetInteger(0,legName,OBJPROP_TIME,1,g_leg.endTime);
   ObjectSetDouble(0,legName,OBJPROP_PRICE,1,g_leg.endPrice);
   ObjectSetInteger(0,legName,OBJPROP_COLOR, g_leg.dir==DIR_BULL?InpColorBull:InpColorBear);
   ObjectSetInteger(0,legName,OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,legName,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,legName,OBJPROP_RAY_RIGHT,false);
   ObjectSetString(0,legName,OBJPROP_TOOLTIP,"\n");
   MarkDrawnLayerObj(legName);

   // فاز ۳۶: برچسب Price Delivery — لگ معامله‌گری با برچسب «Delivering به سمت کدام نقدینگی».
   // این همان زبان MMM/ICT است: قیمت همیشه از یک نقدینگی به نقدینگی دیگر «تحویل» می‌شود؛
   // برچسب جدا محاسبهٔ تازه ندارد: لگ همان محاسبه است و DOL هدفش.
   string pdName="ICTv13_LOCATION_PDLBL";
   string pdTxt=(g_leg.dir==DIR_BULL)?"Delivering UP → " : "Delivering DOWN → ";
   pdTxt += (g_hasDOL? StringFormat("DOL %.2f",g_currentDOL.price) : "هدف نقدینگی در انتظار");
   DrawTextObj(pdName, g_leg.endTime, g_leg.endPrice, pdTxt,
               g_leg.dir==DIR_BULL?InpColorBull:InpColorBear, 8,
               // Phase 42: the Latin label opens the tooltip, the rest is pure Persian.
               "PRICE DELIVERY | لگ فعال از "+TimeToString(g_leg.startTime,TIME_DATE|TIME_MINUTES)+
               " تا "+TimeToString(g_leg.endTime,TIME_DATE|TIME_MINUTES)+
               " | بازگشت به تعادل میانهٔ لگ یا ناحیهٔ ورود بهینه یعنی فرصت ورود هم‌جهت؛ نیمهٔ گران و ارزان لگ را از همان میانه بخوان");
}

// خط DOL: هدف واقعی معامله؛ روی hover توضیح عددی می‌دهد (مستقل از اعتبار لگ)
void DrawDOLLine()
{
   if(!InpDrawDOL) return;               // هدف روی چارت اختیاری است (در داشبورد هست)
   if(!g_hasDOL) return;
   string dolName="ICTv13_DOL_LINE";
   if(ObjectFind(0,dolName)<0) ObjectCreate(0,dolName,OBJ_HLINE,0,0,g_currentDOL.price);
   ObjectSetDouble(0,dolName,OBJPROP_PRICE,g_currentDOL.price);
   ObjectSetInteger(0,dolName,OBJPROP_COLOR,PAL_DOL);
   ObjectSetInteger(0,dolName,OBJPROP_STYLE,STYLE_DASHDOT);
   ObjectSetInteger(0,dolName,OBJPROP_WIDTH,2);
   ObjectSetString(0,dolName,OBJPROP_TOOLTIP,"\n");
   MarkDrawnLayerObj(dolName);
}

//====================================================================
// CHART OBJECT LAYER — نمایش واقعی همه‌چیز روی چارت
// یک‌بار در هر کندل بسته از روی Registryها بازسازی می‌شود (نه هر تیک)
// تا چارت هیچ‌وقت با State ناهمگام نشود.
//====================================================================
string LiqTypeLabel(ENUM_LIQ_TYPE t)
{
   switch(t)
   {
      case LIQ_PDH:       return "PDH (previous day high)";
      case LIQ_PDL:       return "PDL (previous day low)";
      case LIQ_PWH:       return "PWH (previous week high)";
      case LIQ_PWL:       return "PWL (previous week low)";
      case LIQ_EQH:       return "EQH (equal highs - liquidity pool)";
      case LIQ_EQL:       return "EQL (equal lows - liquidity pool)";
      case LIQ_SWING_H:   return "Swing High (BSL)";
      case LIQ_SWING_L:   return "Swing Low (SSL)";
      case LIQ_SESSION_H: return "Session High (BSL)";
      case LIQ_SESSION_L: return "Session Low (SSL)";
      // فاز ۱۲
      case LIQ_RANGE_H:   return "Range High (range liquidity, BSL)";
      case LIQ_RANGE_L:   return "Range Low (range liquidity, SSL)";
      case LIQ_IPDA20_H:  return "IPDA 20-day Old High";
      case LIQ_IPDA20_L:  return "IPDA 20-day Old Low";
      case LIQ_IPDA40_H:  return "IPDA 40-day Old High";
      case LIQ_IPDA40_L:  return "IPDA 40-day Old Low";
      case LIQ_IPDA60_H:  return "IPDA 60-day Old High";
      case LIQ_IPDA60_L:  return "IPDA 60-day Old Low";
   }
   return "Liquidity";
}

//====================================================================
// فاز ۱۴ — REDRAW آشتی‌جویانه (reconciling redraw)
//
// مسئله: RedrawChartObjects قبلاً کل لایه را با ObjectsDeleteAll پاک می‌کرد و
// از Registry بازسازی می‌کرد. سقف‌های نمایش (InpMaxDrawnZones/InpMaxDrawnLevels)
// باعث می‌شد ناحیه‌ای که یک بار روی چارت دیده شده، با ورود ناحیهٔ جدید ناپدید
// شود. این خلاف RESEARCH_FINDINGS بند ۸ است («سیگنالی که یک بار روی چارت آمده
// نباید بی‌صدا جابه‌جا یا ناپدید شود»).
//
// راه‌حل: در هر pass هر آبجکتِ لایه با MarkDrawnLayerObj علامت می‌خورد. بعد از pass:
//   ۱) لایهٔ خاموش‌شدهٔ کاربر         → حذف
//   ۲) فیلتر صریح (MarkHiddenLayerObj) → حذف
//   ۳) علامت‌خوردهٔ همین pass         → زنده (بازنویسی شد)
//   ۴) بقیه (از سقف نمایش بیرون)      → به سبک frozen می‌ماند، نه حذف
// registry frozen کران‌دار است (InpMaxFrozenObjects، FIFO) تا چارت/حافظه نشت نکند.
// ترتیب Array g_frozen از قدیمی به جدید است؛ پس FIFO روی ابتدای آرایه کار می‌کند.
//====================================================================
string g_passDrawn[];       // آبجکت‌هایی که در همین pass بازنویسی شدند
string g_passHidden[];      // آبجکت‌هایی که این pass صریحاً فیلتر شدند (باید حذف شوند)
string g_frozen[];          // تاریخچهٔ frozen که از پنجرهٔ نمایش بیرون افتاده (قدیمی → جدید)
long   g_frozenAdded    = 0;  // شمارندهٔ کل frozen شدن‌ها
long   g_frozenEvicted  = 0;  // چند frozen برای کران‌داری حذف شد
long   g_frozenRestored = 0;  // چند آبجکت از frozen به حالت زنده برگشت
long   g_hiddenDeleted  = 0;  // چند آبجکت به‌خاطر فیلتر صریح/لایهٔ خاموش حذف شد
string g_frozenSymbol   = ""; // سیمبل/تایم‌فریم registry frozen (برای purge روی تغییر context)
ENUM_TIMEFRAMES g_frozenPeriod = PERIOD_CURRENT;
int    g_rcLayerObjects = 0, g_rcDrawn = 0, g_rcFrozen = 0;

bool IsLayerObjectName(const string nm)
{
   if(StringFind(nm,"ICTv13_")!=0) return false;
   if(StringFind(nm,"ICTv13_DASH_")==0) return false;   // داشبورد
   if(StringFind(nm,"ICTv13_EXP_")==0)  return false;   // پنل توضیح
   return true;
}

// لایه‌ای که کاربر صریحاً خاموش کرده باید حذف شود، نه frozen بماند
bool LayerDisabledForName(const string nm)
{
   if(StringFind(nm,"ICTv13_FVG")==0)    return !InpDrawFVGZones;
   if(StringFind(nm,"ICTv13_OB_")==0)    return !InpDrawOBZones;
   if(StringFind(nm,"ICTv13_LIQ_")==0)   return !InpDrawLiquidity;
   if(StringFind(nm,"ICTv13_SWEEP_")==0) return !InpDrawSweepMarkers;
   if(StringFind(nm,"ICTv13_EVT")==0)    return !InpDrawStructureEvents;
   if(StringFind(nm,"ICTv13_MTF_")==0)   return !InpDrawMTFRange;
   if(StringFind(nm,"ICTv13_SETUP_")==0) return !InpDrawSetupBox;
   if(StringFind(nm,"ICTv13_SESS_")==0)  return !(InpDrawKillzoneBoxes || InpDrawAsianRange || InpDrawSilverBullet);
   return false;   // REJECTION / LOCATION / DOL / TRENDLINE / POI / REVERSAL همیشه فعال‌اند
}

// باکس سشن‌ها با اندیس «چند روز قبل» نام‌گذاری می‌شوند. اگر کاربر
// InpKillzoneDaysBack را کم کند، اندیس‌های بالاتر دادهٔ بیات هستند و باید حذف
// شوند (نه frozen بمانند)، چون دیگر هیچ روزی را نمایندگی نمی‌کنند.
bool IsStaleSessionBoxName(const string nm)
{
   if(StringFind(nm,"ICTv13_SESS_")!=0) return false;
   int us=StringFind(nm,"_",13);
   if(us<0) return false;
   string sfx=StringSubstr(nm,us+1);
   int back=(int)StringToInteger(sfx);
   return (back>=InpKillzoneDaysBack);
}

int IndexInNameList(const string &list[], const string nm)
{
   for(int i=ArraySize(list)-1;i>=0;i--) if(list[i]==nm) return i;
   return -1;
}

void ResetPassDrawSet()
{
   ArrayResize(g_passDrawn,0);
   ArrayResize(g_passHidden,0);
}

void DropFromFrozenList(const string nm)
{
   int f=IndexInNameList(g_frozen,nm);
   if(f<0) return;
   for(int k=f;k<ArraySize(g_frozen)-1;k++) g_frozen[k]=g_frozen[k+1];
   ArrayResize(g_frozen,ArraySize(g_frozen)-1);
}

void MarkDrawnLayerObj(const string name)
{
   if(StringLen(name)==0) return;
   if(IndexInNameList(g_passDrawn,name)>=0) return;
   int n=ArraySize(g_passDrawn);
   ArrayResize(g_passDrawn,n+1);
   g_passDrawn[n]=name;

   // آبجکتی که دوباره داخل پنجرهٔ نمایش آمد، از frozen خارج و زنده می‌شود
   if(IndexInNameList(g_frozen,name)>=0)
   {
      DropFromFrozenList(name);
      g_frozenRestored++;
   }
}

void MarkHiddenLayerObj(const string name)
{
   if(StringLen(name)==0) return;
   if(IndexInNameList(g_passHidden,name)>=0) return;
   int n=ArraySize(g_passHidden);
   ArrayResize(g_passHidden,n+1);
   g_passHidden[n]=name;
}

void FreezeLayerObject(const string nm)
{
   long t=ObjectGetInteger(0,nm,OBJPROP_TYPE);
   string origStyle="";
   if(t==OBJ_HLINE || t==OBJ_TREND)
   {
      long st=ObjectGetInteger(0,nm,OBJPROP_STYLE);
      origStyle=(st==STYLE_SOLID?"solid":st==STYLE_DASH?"dash":st==STYLE_DOT?"dot":
                 st==STYLE_DASHDOT?"dashdot":st==STYLE_DASHDOTDOT?"dashdotdot":"other");
      ObjectSetInteger(0,nm,OBJPROP_STYLE,STYLE_DOT);
      ObjectSetInteger(0,nm,OBJPROP_WIDTH,1);
   }
   ObjectSetInteger(0,nm,OBJPROP_COLOR,InpFrozenColor);
   ObjectSetString(0,nm,OBJPROP_TOOLTIP,
      // Phase 42: the Persian clause carries no Latin word; the only Latin left
      // is a labelled segment of its own.
      "FROZEN HISTORY | از پنجرهٔ نمایش فعلی بیرون افتاده و به‌عنوان شاهد تاریخی نگه داشته شده است، نه حذف — موس را روی آن نگه دار تا توضیح کامل فارسی بیاید"
      +(StringLen(origStyle)>0?" | ORIGINAL STYLE — "+origStyle:""));

   int n=ArraySize(g_frozen);
   ArrayResize(g_frozen,n+1);
   g_frozen[n]=nm;
   g_frozenAdded++;

   // کران‌داری FIFO: قدیمی‌ترین frozen‌ها اول حذف می‌شوند
   if(InpMaxFrozenObjects>0 && ArraySize(g_frozen)>InpMaxFrozenObjects)
   {
      int drop=ArraySize(g_frozen)-InpMaxFrozenObjects;
      for(int k=0;k<drop;k++)
      {
         ObjectDelete(0,g_frozen[k]);
         g_frozenEvicted++;
      }
      for(int k=drop;k<ArraySize(g_frozen);k++) g_frozen[k-drop]=g_frozen[k];
      ArrayResize(g_frozen,ArraySize(g_frozen)-drop);
   }
}

// روی تغییر سیمبل/تایم‌فریم، registry frozen به context قبلی تعلق دارد
void PurgeFrozenOnContextChange()
{
   if(g_frozenSymbol==_Symbol && g_frozenPeriod==(ENUM_TIMEFRAMES)Period()) return;
   g_frozenSymbol=_Symbol;
   g_frozenPeriod=(ENUM_TIMEFRAMES)Period();
   for(int i=0;i<ArraySize(g_frozen);i++) ObjectDelete(0,g_frozen[i]);
   ArrayResize(g_frozen,0);
}

void ReconcileChartLayer()
{
   int total=ObjectsTotal(0,-1,-1);
   for(int i=total-1;i>=0;i--)
   {
      string nm=ObjectName(0,i,-1,-1);
      if(!IsLayerObjectName(nm)) continue;

      // منقضی‌شده‌ها و گذشتهٔ پیر، **کاملاً پاک** شوند
      // (نه frozen). ملاک عمر، زمان ساخت داخل نام نیست؛ اینجا با «قدیمی‌بودنِ زمان
      // لنگر آبجکت» پیر شمرده می‌شود تا تاریخچهٔ خیلی عقب زنده نماند.
      if(InpDeleteExpiredObjects && InpExpiryKeepBars>0)
      {
         datetime anchor=(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,0);
         if(anchor<=0) anchor=(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,1);
         if(anchor>0 && g_lastContextBarTime>0)
         {
            int ageBars=(int)((g_lastContextBarTime-anchor)/MathMax(1,PeriodSeconds(PERIOD_CURRENT)));
            if(ageBars>InpExpiryKeepBars)
            {
               ObjectDelete(0,nm);
               DropFromFrozenList(nm);
               g_hiddenDeleted++;
               continue;
            }
         }
      }

      if(LayerDisabledForName(nm) || IsStaleSessionBoxName(nm) || IndexInNameList(g_passHidden,nm)>=0)
      {
         ObjectDelete(0,nm);
         DropFromFrozenList(nm);
         g_hiddenDeleted++;
         continue;
      }
      if(!InpFrozenHistoryEnabled)
      {
         ObjectDelete(0,nm);
         DropFromFrozenList(nm);
         continue;
      }
      if(IndexInNameList(g_passDrawn,nm)>=0) continue;   // همین pass بازنویسی شد: زنده
      if(IndexInNameList(g_frozen,nm)>=0)    continue;   // قبلاً frozen شده: دست نمی‌زنیم
      FreezeLayerObject(nm);                             // بیرون از سقف نمایش → شاهد تاریخی
   }
   g_rcLayerObjects=total;
   g_rcDrawn=ArraySize(g_passDrawn);
   g_rcFrozen=ArraySize(g_frozen);
}

void DrawHLineObj(string name, double price, color clr, ENUM_LINE_STYLE style, int width, string tip)
{
   if(price<=0.0) return;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_HLINE,0,0,price);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,"\n");
   MarkDrawnLayerObj(name);
}

void DrawTextObj(string name, datetime t, double price, string text, color clr, int size, string tip)
{
   if(t<=0 || price<=0.0) return;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_TEXT,0,t,price);
   ObjectSetInteger(0,name,OBJPROP_TIME,0,t);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,price);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
   ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
   ObjectSetString(0,name,OBJPROP_TOOLTIP,"\n");
   MarkDrawnLayerObj(name);
}

void DrawBoxObj(string name, datetime t1, double p1, datetime t2, double p2,
                color clr, bool fill, bool back, ENUM_LINE_STYLE style, int width, string tip)
{
   if(t1<=0 || p1<=0.0 || p2<=0.0) return;
   if(t2<=t1) t2 = t1 + PeriodSeconds()*3;
   if(p2>p1) { double swap=p1; p1=p2; p2=swap; }
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,p1,t2,p2);
   ObjectSetInteger(0,name,OBJPROP_TIME,0,t1);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,p1);
   ObjectSetInteger(0,name,OBJPROP_TIME,1,t2);
   ObjectSetDouble(0,name,OBJPROP_PRICE,1,p2);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FILL,fill);
   ObjectSetInteger(0,name,OBJPROP_BACK,back);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,"\n");
   MarkDrawnLayerObj(name);
}

// نقشهٔ نقدینگی: همهٔ سطوح لمس‌نشده (FRESH) و جاروشده (SWEPT)
void DrawLiquidityLayer()
{
   int drawn=0;
   for(int i=ArraySize(g_liquidity)-1; i>=0 && drawn<InpMaxDrawnLevels; i--)
   {
      if(g_liquidity[i].state==LSTATE_INVALID) continue;
      bool swept = (g_liquidity[i].state==LSTATE_SWEPT);
      // گذشتهٔ فیلدشده رسم نشود. سطح SWEPT فقط اگر تازه باشد
      // (برای مرجع الگوی سوئپ) و سطح INVALID هرگز رسم نمی‌شود.
      if(swept)
      {
         if(InpSweptKeepBars<=0) continue;
         datetime sweptT=g_liquidity[i].sweptTime;
         if(sweptT<=0) continue;
         int age=(int)((g_lastContextBarTime-sweptT)/MathMax(1,PeriodSeconds(PERIOD_CURRENT)));
         if(age>InpSweptKeepBars) continue;
      }
      bool isIPDA=(g_liquidity[i].type==LIQ_IPDA20_H || g_liquidity[i].type==LIQ_IPDA20_L ||
                   g_liquidity[i].type==LIQ_IPDA40_H || g_liquidity[i].type==LIQ_IPDA40_L ||
                   g_liquidity[i].type==LIQ_IPDA60_H || g_liquidity[i].type==LIQ_IPDA60_L);
      // بازبینی نمایش: IPDA سطوح خودش را دارد؛ اگر کاربر خاموشش کرده، نرسم
      // (در داشبورد و CSV کامل دیده می‌شود). کشف دست نخورد — فقط رسم.
      if(isIPDA && !InpDrawIPDA) continue;
      bool highSide = IsHighSideLiquidity(g_liquidity[i].type);
      // فاز ۴۸: رنگ از پالت واحد می‌آید (پیش‌تر Tomato/MediumSeaGreen بودند و
      // با خط روند بروکس و ناحیهٔ FVG صعودی قاطی می‌شدند).
      color clr = swept ? PAL_STATE_SWEPT : (highSide?PAL_LIQ_HIGH:PAL_LIQ_LOW);
      if(g_liquidity[i].isHTF && !swept) clr = highSide?PAL_LIQ_HTF_HIGH:PAL_LIQ_HTF_LOW;
      ENUM_LINE_STYLE style = swept ? STYLE_DOT : (g_liquidity[i].isHTF?STYLE_SOLID:STYLE_DASH);
      string name = "ICTv13_LIQ_"+IdToStr(g_liquidity[i].id);
      string tip = StringFormat("%s | %s | %s | price=%s%s",
                    LiqTypeLabel(g_liquidity[i].type),
                    g_liquidity[i].scope==SCOPE_EXTERNAL?"External (HTF)":"Internal (LTF)",
                    swept? "SWEPT at "+TimeToString(g_liquidity[i].sweptTime,TIME_DATE|TIME_MINUTES) : "FRESH - untapped liquidity",
                    DoubleToString(g_liquidity[i].price,_Digits),
                    swept? StringFormat(" | swept by event #%s",IdToStr(g_liquidity[i].sweptByEventId)):"");
      DrawHLineObj(name, g_liquidity[i].price, clr, style, g_liquidity[i].isHTF?2:1, tip);
      if(InpDrawLevelLabels)
         DrawTextObj(name+"_T", g_lastContextBarTime, g_liquidity[i].price,
                     (swept?"SWEPT ":"")+LiqTypeLabel(g_liquidity[i].type), clr, 8, tip);
      drawn++;
   }

   // سطوح INVALID دیگر رسم نمی‌شوند؛ تاریخچه در CSV می‌ماند.
   if(!InpHideInvalidatedObjects)
   {
      int invalidCap=InpMaxDrawnLevels/3;
      if(invalidCap<1) invalidCap=1;
      int drawnInvalid=0;
      for(int i=ArraySize(g_liquidity)-1; i>=0 && drawnInvalid<invalidCap; i--)
      {
         if(g_liquidity[i].state!=LSTATE_INVALID) continue;
         string name = "ICTv13_LIQ_"+IdToStr(g_liquidity[i].id);
         string tip = StringFormat("%s | %s | INVALID: price accepted beyond this level (close-through) | price=%s",
                       LiqTypeLabel(g_liquidity[i].type),
                       g_liquidity[i].scope==SCOPE_EXTERNAL?"External (HTF)":"Internal (LTF)",
                       DoubleToString(g_liquidity[i].price,_Digits));
         DrawHLineObj(name, g_liquidity[i].price, PAL_STATE_INVALID, STYLE_DOT, 1, tip);
         drawnInvalid++;
      }
   }
}

// علامت Sweep: کجا و کدام سطح جارو شد
void DrawSweepLayer()
{
   int drawn=0;
   for(int i=ArraySize(g_liquidity)-1; i>=0 && drawn<InpMaxDrawnLevels; i--)
   {
      if(g_liquidity[i].state!=LSTATE_SWEPT || g_liquidity[i].sweptTime<=0) continue;
      // نشانِ سوئپ هم گذشته است؛ فقط چند کندل آخر می‌ماند.
      if(InpSweptKeepBars>0)
      {
         int age=(int)((g_lastContextBarTime-g_liquidity[i].sweptTime)/MathMax(1,PeriodSeconds(PERIOD_CURRENT)));
         if(age>InpSweptKeepBars) continue;
      }
      else continue;
      bool highSide = IsHighSideLiquidity(g_liquidity[i].type);
      color clr = highSide?PAL_LIQ_HTF_HIGH:PAL_LIQ_HTF_LOW;
      DrawTextObj("ICTv13_SWEEP_"+IdToStr(g_liquidity[i].id),
                  g_liquidity[i].sweptTime, g_liquidity[i].price,
                  highSide?"SWEEP (BSL)":"SWEEP (SSL)", clr, 8,
                  StringFormat("%s swept and closed back inside | %s | price=%s",
                               LiqTypeLabel(g_liquidity[i].type),
                               TimeToString(g_liquidity[i].sweptTime,TIME_DATE|TIME_MINUTES),
                               DoubleToString(g_liquidity[i].price,_Digits)));
      drawn++;
   }
}

// ناحیه‌های FVG / OB / Rejection
void DrawZoneLayer()
{
   if(InpDrawFVGZones)
   {
      int drawn=0;
      for(int i=ArraySize(g_fvgs)-1; i>=0 && drawn<InpMaxDrawnZones; i--)
      {
         // فیلتر صریح کاربر = حذف (نه frozen)؛ آبجکتی که کاربر نخواسته دیده شود
         // نباید به‌عنوان «شاهد تاریخی» دورگه روی چارت بماند.
         if(InpDrawOnlyCausalFVG && !g_fvgs[i].causal)
         {
            MarkHiddenLayerObj("ICTv13_FVG_"+IdToStr(g_fvgs[i].id));
            MarkHiddenLayerObj("ICTv13_FVGCE_"+IdToStr(g_fvgs[i].id));
            continue;
         }
         if(g_fvgs[i].invalidated)
         {
            MarkHiddenLayerObj("ICTv13_FVG_"+IdToStr(g_fvgs[i].id));
            MarkHiddenLayerObj("ICTv13_FVGCE_"+IdToStr(g_fvgs[i].id));
            continue;
         }
         // FVG لمس‌شده/معکوس‌شده گذشته رسم نشود.
         // iFVG پولاریتی عوض کرده و دوباره «سطح معکوس» معتبر است، پس با منطق
         // «گذشته پاک شود» نمی‌خورد؛ فقط mitigated قدیمی حذف می‌شود. برای mitigated
         // فاقد touchTime ثبت‌شده، زمان تولد مبنا گرفته می‌شود (تولد قدیمی = گذشته).
         if(InpHideInvalidatedObjects && g_fvgs[i].mitigated && !g_fvgs[i].inverted)
         {
            datetime touchRef=(g_fvgs[i].touchTime>0)? g_fvgs[i].touchTime : g_fvgs[i].time;
            if((int)((g_lastContextBarTime-touchRef)/MathMax(1,PeriodSeconds(PERIOD_CURRENT)))>InpSweptKeepBars)
            {
               MarkHiddenLayerObj("ICTv13_FVG_"+IdToStr(g_fvgs[i].id));
               MarkHiddenLayerObj("ICTv13_FVGCE_"+IdToStr(g_fvgs[i].id));
               continue;
            }
         }
         // هر تایم‌فریم برای خودش رسم کند — ناحیهٔ متعلق به
         // تایم‌فریم مالکش رسم می‌شود (نه تایم‌فریم چارت). Micro (M1) همیشه رسم است.
         if(InpDrawPerTimeframe && g_fvgs[i].kind==FVGK_STANDARD && g_fvgs[i].tf!=PERIOD_CURRENT)
         {
            MarkHiddenLayerObj("ICTv13_FVG_"+IdToStr(g_fvgs[i].id));
            MarkHiddenLayerObj("ICTv13_FVGCE_"+IdToStr(g_fvgs[i].id));
            continue;
         }
         DrawFVG(g_fvgs[i]);
         drawn++;
      }
   }
   if(InpDrawOBZones)
   {
      int drawn=0;
      for(int i=ArraySize(g_obs)-1; i>=0 && drawn<InpMaxDrawnZones; i--)
      {
         // OB شکسته/نامعتبر گذشته رسم نشود؛ MITIGATED تازه می‌ماند.
         if(InpHideInvalidatedObjects &&
            (g_obs[i].state==OB_BROKEN || g_obs[i].state==OB_INVALID))
         {
            MarkHiddenLayerObj("ICTv13_OB_"+IdToStr(g_obs[i].id));
            continue;
         }
         // هر تایم‌فریم برای خودش رسم کند.
         if(InpDrawPerTimeframe && g_obs[i].tf!=PERIOD_CURRENT)
         {
            MarkHiddenLayerObj("ICTv13_OB_"+IdToStr(g_obs[i].id));
            continue;
         }
         DrawOB(g_obs[i]);
         drawn++;
      }
   }
   int drawnR=0;
   for(int i=ArraySize(g_rejections)-1; i>=0 && drawnR<InpMaxDrawnZones; i--)
   {
      if(InpHideInvalidatedObjects && g_rejections[i].rejectionState==REJECTION_INVALID)
      {
         MarkHiddenLayerObj("ICTv13_REJECTION_"+IdToStr(g_rejections[i].id));
         continue;
      }
      DrawRejection(g_rejections[i]);
      drawnR++;
   }
}

// سشن‌ها و کیلیزون‌ها به وقت نیویورک (شامل Asian Range به‌عنوان هدف نقدینگی)
void DrawSessionLayer()
{
   datetime ref = g_lastContextBarTime>0 ? g_lastContextBarTime : TimeCurrent();
   for(int back=0; back<InpKillzoneDaysBack; back++)
   {
      datetime s=0,e=0; double hi=0,lo=0; int cnt=0;
      string sfx=IntegerToString(back);
      if(InpDrawAsianRange && WindowForDayBack(back,InpAsiaStartHourNY,0,InpAsiaEndHourNY,0,ref,s,e,hi,lo,cnt,true))
         DrawBoxObj("ICTv13_SESS_ASIA_"+sfx, s, hi, e, lo, PAL_SESS_ASIA, false, true, STYLE_DOT, 1,
                    StringFormat("Asian Range (Accumulation) %.2f - %.2f | primary liquidity target for London",lo,hi));
      if(InpDrawKillzoneBoxes)
      {
         if(WindowForDayBack(back,InpLondonStartHourNY,0,InpLondonEndHourNY,0,ref,s,e,hi,lo,cnt,true))
            DrawBoxObj("ICTv13_SESS_LON_"+sfx, s, hi, e, lo, PAL_SESS_LONDON, false, true, STYLE_DOT, 1,
                       StringFormat("London Killzone %02d:00-%02d:00 NY | Manipulation / Judas Swing window",InpLondonStartHourNY,InpLondonEndHourNY));
         if(WindowForDayBack(back,InpNY_KZ_StartHourNY,0,InpNY_KZ_EndHourNY,0,ref,s,e,hi,lo,cnt,true))
            DrawBoxObj("ICTv13_SESS_NYAM_"+sfx, s, hi, e, lo, PAL_SESS_NY, false, true, STYLE_DOT, 1,
                       StringFormat("New York AM Killzone %02d:00-%02d:00 NY | Distribution",InpNY_KZ_StartHourNY,InpNY_KZ_EndHourNY));
         if(WindowForDayBack(back,InpLondonCloseStartHourNY,0,InpLondonCloseEndHourNY,0,ref,s,e,hi,lo,cnt,true))
            DrawBoxObj("ICTv13_SESS_LONCL_"+sfx, s, hi, e, lo, PAL_SESS_LONDONCLOSE, false, true, STYLE_DOT, 1,
                       StringFormat("London Close Killzone %02d:00-%02d:00 NY",InpLondonCloseStartHourNY,InpLondonCloseEndHourNY));
         if(WindowForDayBack(back,InpNYPM_StartHourNY,InpNYPM_StartMinuteNY,InpNYPM_EndHourNY,InpNYPM_EndMinuteNY,ref,s,e,hi,lo,cnt,true))
            DrawBoxObj("ICTv13_SESS_NYPM_"+sfx, s, hi, e, lo, PAL_SESS_NYPM, false, true, STYLE_DOT, 1,
                       StringFormat("New York PM Killzone %02d:%02d-%02d:%02d NY",InpNYPM_StartHourNY,InpNYPM_StartMinuteNY,InpNYPM_EndHourNY,InpNYPM_EndMinuteNY));
      }
      // Silver Bullet: قبلاً فقط متن داشبورد بود و InpDrawSilverBullet هیچ باکسی
      // رسم نمی‌کرد (رفع #۵۲). حالا هر سه پنجره رسم می‌شوند.
      if(InpDrawSilverBullet)
      {
         if(WindowForDayBack(back,InpSB1_StartHourNY,0,InpSB1_EndHourNY,0,ref,s,e,hi,lo,cnt,true))
            DrawBoxObj("ICTv13_SESS_SB1_"+sfx, s, hi, e, lo, PAL_SESS_SB, false, true, STYLE_DASHDOT, 1,
                       StringFormat("Silver Bullet #1 %02d:00-%02d:00 NY | one-hour algorithmic window. The window itself is NOT a signal: wait for a level sweep + displacement/FVG inside it",InpSB1_StartHourNY,InpSB1_EndHourNY));
         if(WindowForDayBack(back,InpSB2_StartHourNY,0,InpSB2_EndHourNY,0,ref,s,e,hi,lo,cnt,true))
            DrawBoxObj("ICTv13_SESS_SB2_"+sfx, s, hi, e, lo, PAL_SESS_SB, false, true, STYLE_DASHDOT, 1,
                       StringFormat("Silver Bullet #2 %02d:00-%02d:00 NY | one-hour algorithmic window. The window itself is NOT a signal: wait for a level sweep + displacement/FVG inside it",InpSB2_StartHourNY,InpSB2_EndHourNY));
         if(WindowForDayBack(back,InpSB3_StartHourNY,0,InpSB3_EndHourNY,0,ref,s,e,hi,lo,cnt,true))
            DrawBoxObj("ICTv13_SESS_SB3_"+sfx, s, hi, e, lo, PAL_SESS_SB, false, true, STYLE_DASHDOT, 1,
                       StringFormat("Silver Bullet #3 %02d:00-%02d:00 NY | one-hour algorithmic window. The window itself is NOT a signal: wait for a level sweep + displacement/FVG inside it",InpSB3_StartHourNY,InpSB3_EndHourNY));
      }
   }
}

// سطوح حفاظت‌شدهٔ هر تایم‌فریم MTF با ذکر مالک و نقش
void DrawMTFLayer()
{
   if(!InpDrawMTFRange) return;
   for(int index=0; index<6; index++)
   {
      if(g_mtfContext[index].protectedHigh<=0.0 && g_mtfContext[index].protectedLow<=0.0) continue;
      string tag = EnumToString(g_mtfContext[index].timeframe);
      color clr = (g_mtfContext[index].externalDirection==DIR_BULL)?clrLime:
                  (g_mtfContext[index].externalDirection==DIR_BEAR)?clrOrangeRed:clrSilver;
      int width = (index==0)?2:1;
      string tip = StringFormat("%s | role=%s | direction=%s | as of %s",tag,g_mtfContext[index].role,
                                 DirToStr(g_mtfContext[index].externalDirection),
                                 TimeToString(g_mtfContext[index].confirmedBarTime,TIME_DATE|TIME_MINUTES));
      if(g_mtfContext[index].protectedHigh>0.0)
         DrawHLineObj("ICTv13_MTF_"+tag+"_H", g_mtfContext[index].protectedHigh, clr, STYLE_DASHDOTDOT, width,
                      "Protected HIGH | "+tip);
      if(g_mtfContext[index].protectedLow>0.0)
         DrawHLineObj("ICTv13_MTF_"+tag+"_L", g_mtfContext[index].protectedLow, clr, STYLE_DASHDOTDOT, width,
                      "Protected LOW | "+tip);
   }
}

// باکس ستاپ + Entry/SL/TP با دلیل و وضعیت
void DrawSetupLayer()
{
   if(!InpDrawSetupBox) return;
   long obId=-1, fvgId=-1;
   double zTop=0, zBot=0;
   for(int i=ArraySize(g_obs)-1;i>=0;i--)
      if(g_obs[i].state==OB_VALID && !g_obs[i].isStandalone){ obId=g_obs[i].id; zTop=g_obs[i].top; zBot=g_obs[i].bottom; break; }
   if(obId==-1)
      for(int i=ArraySize(g_fvgs)-1;i>=0;i--)
         if(g_fvgs[i].causal && !g_fvgs[i].invalidated && !g_fvgs[i].inverted){ fvgId=g_fvgs[i].id; zTop=g_fvgs[i].top; zBot=g_fvgs[i].bottom; break; }

   datetime t1 = g_lastContextBarTime>0 ? g_lastContextBarTime : TimeCurrent();
   if(obId!=-1 || fvgId!=-1)
      DrawBoxObj("ICTv13_SETUP_ZONE", t1, zTop, t1 + PeriodSeconds()*InpZoneExtendBars, zBot,
                 g_setup.active?PAL_SETUP:PAL_STATE_INVALID, false, true, STYLE_SOLID, 2,
                 StringFormat("Entry zone = %s | status=%s | refines with CE/OTE",
                              obId!=-1?"Order Block":"FVG", g_setup.status));

   if(g_setup.active)
   {
      DrawHLineObj("ICTv13_SETUP_ENTRY", g_setup.entry, PAL_SETUP, STYLE_SOLID, 1, "Setup Entry | "+g_setup.status);
      DrawHLineObj("ICTv13_SETUP_SL",    g_setup.sl,    InpColorBear, STYLE_SOLID, 1,
                   "Setup SL | invalidated only by a CLOSED bar beyond it | lifecycle="+g_setupLifeState);
      DrawHLineObj("ICTv13_SETUP_TP1",   g_setup.tp1,   InpColorBull, STYLE_DASH, 1, "TP1 = 1R");
      DrawHLineObj("ICTv13_SETUP_TP2",   g_setup.tp2,   InpColorBull, STYLE_DASH, 1, "TP2 = 2R");
      DrawHLineObj("ICTv13_SETUP_TP3",   g_setup.tp3,   InpColorBull, STYLE_DASH, 1, "TP3 = draw on liquidity");
      DrawTextObj("ICTv13_SETUP_TXT", t1, g_setup.entry,
                  (g_setup.dir==DIR_BULL?"LONG ":"SHORT ")+g_setup.status,
                  g_setup.dir==DIR_BULL?InpColorBull:InpColorBear, 10,
                  StringFormat("Setup %s | bias owner=%s | DOL=%.2f | FVG#%s OB#%s",
                               g_setup.status, EnumToString(g_mtfTimeframes[0]), g_currentDOL.price,
                               IdToStr(g_setup.fvgId), IdToStr(g_setup.obId)));
   }
   else
   {
      double refPrice = (g_analysisClose>0.0)? g_analysisClose : SymbolInfoDouble(_Symbol,SYMBOL_BID);
      DrawTextObj("ICTv13_SETUP_TXT", t1, refPrice, "WAIT: "+g_setup.status, InpColorNeutral, 9,
                  g_mtfConflictReason!=""? g_mtfConflictReason : "Setup not READY on the latest closed bar");
   }

   // فاز ۱۵ (#۶۶): نشانهٔ چرخهٔ عمر ستاپ. خط SL ستاپ پیگیری‌شده و برچسب ابطال
   // روی چارت می‌مانند تا مشخص باشد ستاپ *کجا* باطل شد — همین چیزی که تا
   // پیش از این فاز هیچ‌جا ثبت نمی‌شد.
   if(InpTrackSetupLifecycle && (g_setupLifeState=="INVALIDATED" || g_setupLifeState=="TP1_HIT"))
   {
      datetime tEnd  = (g_setupLifeEndTime>0)? g_setupLifeEndTime : t1;
      double   pEnd  = g_setupLifeEndPrice;
      if(g_setupLifeSL>0.0)
         DrawHLineObj("ICTv13_SETUP_LIFE_SL", g_setupLifeSL, InpFrozenColor, STYLE_DOT, 1,
                      StringFormat("Setup being tracked from %s | SL = %s | lifecycle=%s",
                                   TimeToString(g_setupLifeArmTime,TIME_DATE|TIME_MINUTES),
                                   DoubleToString(g_setupLifeSL,_Digits), g_setupLifeState));
      if(pEnd>0.0)
      {
         string lifeTxt = (g_setupLifeState=="INVALIDATED")? "SETUP INVALIDATED" : "SETUP TP1 HIT (1R)";
         if(g_setupLifeState=="INVALIDATED")
            DrawHLineObj("ICTv13_SETUP_LIFE_END", pEnd, InpColorBear, STYLE_DASH, 1,
                         "Closing price was beyond the protected SL level here");
         DrawTextObj("ICTv13_SETUP_LIFE_TXT", tEnd, pEnd, lifeTxt,
                     (g_setupLifeState=="INVALIDATED")? InpColorBear : InpColorBull, 10,
                     "Setup lifecycle | "+g_setupLifeState+" | "+g_setupLifeReason);
      }
   }
}

// فاز ۱۱: سطح محافظت‌شدهٔ خارجی (دروازهٔ برگشت) و تأییدیهٔ برگشت
void DrawReversalLevels()
{
   // (چارت خلوت‌تر): فقط هشدارهای *فعال* برگشت رسم شوند —
   // دروازهٔ مسلح‌شده یا تأییدشده؛ حالت ساکن خطی روی چارت نمی‌گذارد.
   if(!InpDrawReversalLevel || !InpEnableReversalGate) return;
   if(!g_reversal.armed && !g_reversal.confirmed) return;
   if(g_reversal.armed && g_reversal.levelPrice>0.0)
   {
      string name="ICTv13_REVERSAL_GATE";
      string tip=StringFormat("Protected external level (%s) | price=%s | the reversal direction this level would confirm: %s",
                    g_reversal.levelIsHigh?"HIGH":"LOW", DoubleToString(g_reversal.levelPrice,_Digits),
                    DirToStr(OppositeDir(g_reversal.snapBias)));
      color gateClr = g_reversal.confirmed?PAL_GATE_CONFIRMED:PAL_GATE_PENDING;
      DrawHLineObj(name, g_reversal.levelPrice, gateClr,
                   g_reversal.confirmed?STYLE_SOLID:STYLE_DASH, 2, tip);
      if(InpDrawLevelLabels)
         DrawTextObj(name+"_T", g_lastContextBarTime, g_reversal.levelPrice, "REVERSAL GATE", gateClr, 8, tip);
   }
   if(g_reversal.confirmed && g_reversal.confirmedTime>0 && g_reversal.confirmedClose>0.0)
   {
      DrawTextObj("ICTv13_REVERSAL_CONFIRMED", g_reversal.confirmedTime, g_reversal.confirmedClose,
                  (g_reversal.dir==DIR_BULL?"REVERSAL CONFIRMED (BULLISH)":"REVERSAL CONFIRMED (BEARISH)"),
                  PAL_GATE_CONFIRMED, 9,
                  StringFormat("Confirmed reversal (%s) | a closed %s bar closed beyond the protected external level | SMR %d/%d",
                               DirToStr(g_reversal.dir), EnumToString(InpHTF), g_reversal.smrScore, g_reversal.smrMax));
   }
}

// ================= فازهای ۱۶–۲۱: رسم + hover فارسی =================
void DrawFamiliesLayer()
{
   // Wyckoff: رویدادهای آخر روی چارت (Spring/Upthrust مهم‌ترین‌اند).
   // بازبینی نمایش (2026-09-18): برچسب‌های متنی تکراری (SC/BC/AR/ST/…) «تزئینی»‌اند؛
   // پیش‌فرض خاموش. Spring/Upthrust که واقعاً سوئپ نقدینگی‌اند، از خودشان در لایهٔ
   // نقدینگی/سوئپ شواهد دارند. محاسبات Wyckoff (فاز/دلیل در داشبورد) دست‌نخورده.
   if(InpEnableWyckoff && InpDrawWyckoffLabels)
   {
      int drawn=0;
      for(int i=ArraySize(g_wyck)-1; i>=0 && drawn<6; i--)
      {
         if(g_wyck[i].evt==WE_NONE) continue;
         string label="";
         switch(g_wyck[i].evt)
         {
            case WE_SC: label="SC"; break;        case WE_BC: label="BC"; break;
            case WE_AR: label="AR"; break;        case WE_ST: label="ST"; break;
            case WE_SPRING: label="SPRING"; break; case WE_UPTHRUST: label="UPTHRUST"; break;
            case WE_SOS: label="SOS"; break;      case WE_SOW: label="SOW"; break;
            case WE_LPS: label="LPS"; break;      case WE_LPSY: label="LPSY"; break;
            case WE_TEST: label="TEST"; break;    case WE_ABSORPTION: label="ABSORB"; break;
            default: continue;
         }
         color wc=(g_wyck[i].evt==WE_SPRING)?InpColorBull:(g_wyck[i].evt==WE_UPTHRUST)?InpColorBear:InpColorNeutral;
         DrawTextObj("ICTv13_WYCK_"+IdToStr(g_wyck[i].id), g_wyck[i].time, g_wyck[i].price, label, wc, 8,
                     StringFormat("Wyckoff %s | فاز: %s | %s",label,
                                  (g_wyck[i].phase>=WP_A&&g_wyck[i].phase<=WP_E)?IntegerToString((int)g_wyck[i].phase):"—",
                                  g_wyckPhaseReason));
         drawn++;
      }
   }
   // Supply/Demand: ناحیهٔ ورود واقعی است (مانند FVG/OB) → پیش‌فرض روشن؛
   // سقف رسم هم به‌جای عدد ثابت ۱۰ از سقف رجیستری InpSD_MaxZones می‌آید تا
   // «رجیستری» و «نمایش» از هم جدا بمانند. هر تایم‌فریم مالک، رسم مخصوص خودش:
   // ناحیهٔ متعلق به تایم‌فریم دیگر روی این چارت رسم نمی‌شود (طراحی پروژه).
   if(InpEnableSupplyDemand && InpDrawSDZones)
   {
      int drawn=0;
      int sdCap=MathMin(10,InpSD_MaxZones);
      for(int i=ArraySize(g_sd)-1; i>=0 && drawn<sdCap; i--)
      {
         if(InpHideInvalidatedObjects && g_sd[i].state==SDS_BROKEN) continue;
         if(InpDrawPerTimeframe && g_sd[i].tf!=PERIOD_CURRENT) continue;
         // فاز ۳۳: رنگ و نقش از «نقش زندهٔ» ناحیه می‌آید، نه از نوع اولیهٔ الگو —
         // پس یک Flip Zone هم رنگ درست می‌گیرد و هم بعد از Flip زنده می‌ماند.
         bool isSupp=g_sd[i].roleSupply;
         color sc=isSupp?PAL_SD_SUPPLY:PAL_SD_DEMAND;
         if(g_sd[i].state==SDS_FLIPPED) sc=PAL_STATE_MITIGATED;
         else if(g_sd[i].state==SDS_TESTED) sc=PAL_STATE_SWEPT;
         string kn=SDKindToStr(g_sd[i].kind)+(g_sd[i].flipped? " → Flipped": "");
         DrawBoxObj("ICTv13_SD_"+IdToStr(g_sd[i].id), g_sd[i].time, g_sd[i].top,
                    (datetime)((long)g_sd[i].time+(long)PeriodSeconds()*InpZoneExtendBars), g_sd[i].bottom,
                    sc, false, true, STYLE_DOT, 1,
                    StringFormat("S/D %s | role=%s | state=%s | tests=%d | exit=%.2f ATR",kn,
                                 isSupp?"Supply":"Demand",
                                 g_sd[i].state==SDS_FRESH?"FRESH":g_sd[i].state==SDS_TESTED?"TESTED":g_sd[i].state==SDS_FLIPPED?"FLIPPED":"BROKEN",
                                 g_sd[i].tests, g_sd[i].exitMove));
         drawn++;
      }
   }
   // RTM (فاز ۳۴): رویدادها فقط اگر کاربر خواست روی چارت بیایند (پیش‌فرض خاموش
   // تا چارت شلوغ نشود)؛ ولی داده، رجیستری و پنل آموزشی همیشه فعال است.
   if(InpEnableRTM && InpDrawRTMObjects)
   {
      int rn=ArraySize(g_rtm), drawn=0;
      for(int i=rn-1; i>=0 && drawn<8; i--)
      {
         color rc=(g_rtm[i].dir>0)? InpColorBull : ((g_rtm[i].dir<0)? InpColorBear : InpColorNeutral);
         DrawTextObj("ICTv13_RTM_"+IdToStr(g_rtm[i].id), g_rtm[i].time, g_rtm[i].price,
                     "RTM:"+IntegerToString((int)g_rtm[i].evt), rc, 8, g_rtm[i].note);
         drawn++;
      }
   }
   // Profile: POC/VAH/VAL فقط اگر کاربر خواست
   // فاز ۳۴: خطوط IB و TPO-VA و Naked POC هم اضافه شدند — همه با پیشوند PROF_ تا
   // همان کلیک/پنل آموزشی داشته باشند (هیچ خطی بی‌توضیح نمی‌ماند).
   if(InpEnableProfile && (InpDrawProfileOnChart || InpDrawAMTOnChart) && g_profileDaily.valid)
   {
      DrawHLineObj("ICTv13_PROF_POC", g_profileDaily.poc, PAL_PROF_POC, STYLE_SOLID, 1, "POC | حجم تیک | "+g_profileNote);
      DrawHLineObj("ICTv13_PROF_VAH", g_profileDaily.vah, PAL_PROF_VA, STYLE_DOT, 1, "VAH | "+g_profileNote);
      DrawHLineObj("ICTv13_PROF_VAL", g_profileDaily.val, PAL_PROF_VA, STYLE_DOT, 1, "VAL | "+g_profileNote);
      if(g_profileDaily.tpoValid)
      {
         DrawHLineObj("ICTv13_PROF_TPOC", g_profileDaily.tpoPoc, PAL_PROF_TPO, STYLE_DASH, 1,
                      StringFormat("TPO POC | VA %.2f–%.2f | زمان‌محور است، نه حجم", g_profileDaily.tpoVah, g_profileDaily.tpoVal));
         DrawHLineObj("ICTv13_PROF_TVAH", g_profileDaily.tpoVah, PAL_PROF_TPO, STYLE_DOT, 1, "TPO VAH | ناحیهٔ ارزش زمان‌محور");
         DrawHLineObj("ICTv13_PROF_TVAL", g_profileDaily.tpoVal, PAL_PROF_TPO, STYLE_DOT, 1, "TPO VAL | ناحیهٔ ارزش زمان‌محور");
      }
      if(g_profileDaily.amtValid && g_profileDaily.ibHi>g_profileDaily.ibLo)
      {
         DrawHLineObj("ICTv13_PROF_IBH", g_profileDaily.ibHi, PAL_PROF_IB, STYLE_DOT, 1,
                      StringFormat("Initial Balance High (اولین %d دقیقهٔ روز)", InpProfileIB_Minutes));
         DrawHLineObj("ICTv13_PROF_IBL", g_profileDaily.ibLo, PAL_PROF_IB, STYLE_DOT, 1,
                      StringFormat("Initial Balance Low (اولین %d دقیقهٔ روز) — شکست آن جهت روز را می‌سازد", InpProfileIB_Minutes));
      }
      if(g_profileDaily.hasNakedPoc)
         DrawHLineObj("ICTv13_PROF_NPOC", g_profileDaily.nakedPoc, PAL_PROF_NPOC, STYLE_DASHDOT, 2,
                      StringFormat("Naked/Virgin POC روز %s — از بسته‌شدن آن سشن لمس نشده (آهنربای قیمت)",
                                   TimeToString(g_profileDaily.nakedPocDay,TIME_DATE)));
      if(InpDrawAMTOnChart)
      {
         for(int h=0; h<g_profileDaily.hvnCount; h++)
            DrawHLineObj("ICTv13_PROF_HVN"+IntegerToString(h), g_profileDaily.hvn[h], PAL_PROF_HVN, STYLE_DOT, 1,
                         "HVN (High Volume Node) — گرهٔ پرحجم: قیمت این‌جا وقت/حجم زیاد گذرانده (آهنربا و مانع)");
         for(int l2=0; l2<g_profileDaily.lvnCount; l2++)
            DrawHLineObj("ICTv13_PROF_LVN"+IntegerToString(l2), g_profileDaily.lvn[l2], PAL_PROF_LVN, STYLE_DOT, 1,
                         "LVN (Low Volume Node) — گرهٔ کم‌حجم: عبور قیمت از این‌جا سریع است (مسیر کم‌مقاومت)");
      }
   }
}

// hover فارسی برای خانواده‌های جدید (از BuildExplanation صدا زده می‌شود)
void ExplainWyckoff(const WyckoffObj &w)
{
   g_expTitle="WYCKOFF "+WyckoffEventCode(w.evt)+" #"+IdToStr(w.id);
   ExpAdd("رویداد: "+WyckoffEventFa(w.evt), clrWhite);
   ExpAdd(StringFormat("کندل %s | قیمت %.5f", TimeToString(w.time,TIME_DATE|TIME_MINUTES), w.price), clrWhite);
   ExpAdd(StringFormat("پنجرهٔ رنج تحلیل: %d کندل", InpWyckoffLookbackBars), clrWhite);
   ExpAddWrapped("چرا اهمیت دارد: پول بزرگ با اوج خرید و اوج فروش هیجان را می‌سازد و با اسپرینگ و آپ‌تراست استاپ‌های رنج را می‌شکند؛ برگشت درون رنج با آزمون کم‌دامنه تأیید می‌شود", clrAqua);
   ExpAddWrapped("فاز فعلی تحلیل: "+g_wyckPhaseReason, clrLime);
   ExpAddWrapped("فیک و باطل: اگر بستهٔ کندل بیرون مرز رنج بماند و فقط فتیله نباشد، دیگر اسپرینگ نیست و شکست واقعی است؛ سناریوی رنج باطل می‌شود", clrOrange);
   ExpAddWrapped("کنترل خودت: فتیلهٔ کندل را با کف و سقف رنج مقایسه کن؛ عمق باید بیشتر از آستانهٔ تنظیم‌شده باشد", clrSilver);
   ExpAdd("InpWyckoffSpringATR — آستانهٔ عمق اسپرینگ نسبت به میانگین دامنه", clrSilver);
}

// فاز ۳۳: متن آموزش S&D بازنویسی شد. قبلاً هم نقش الگو در نمایش/چرخهٔ عمر برعکس
// بود (RBD به‌عنوان Demand، DBR به‌عنوان Supply) و هم معنای RBR/RBD/DBD/DBR در
// متن آموزشی گفته نشده بود.
void ExplainSD(const SDObj &z)
{
   string kn=SDKindToStr(z.kind);
   g_expTitle="S/D "+kn+" #"+IdToStr(z.id)+(z.roleSupply? " SUPPLY" : " DEMAND");
   ExpAdd(StringFormat("%s = %s", kn, SDKindFa(z.kind)), clrWhite);
   ExpAdd(StringFormat("بازهٔ ناحیه %.2f تا %.2f | پایان پایه: %s",
          z.bottom, z.top, TimeToString(z.time,TIME_DATE|TIME_MINUTES)), clrWhite);
   ExpAddWrapped("تفکیک ادامه‌دهنده از برگشتی: الگوهای رالی و ریزش ادامهٔ روند پیشین هستند چون قیمت از همان سمت پایه بیرون می‌رود؛ الگوهای برگشتی پایه را در سقف یا کف می‌سازند و خروج مخالف آن است", clrAqua);
   ExpAdd(StringFormat("خروج از پایه شارپ بوده: %.2f برابر میانگین دامنه (حداقل %.2f) — نشانهٔ جذب سفارش نهادی", z.exitMove, InpSD_StrengthATR), clrAqua);
   ExpAdd(StringFormat("نقش فعلی ناحیه: %s", z.roleSupply?"عرضه":"تقاضا"), clrLime);
   if(z.flipped)
      ExpAdd(StringFormat("نقش این ناحیه عوض شده (چرخش) در %s روی قیمت %s و از این لحظه با نقش جدید رهگیری می‌شود",
             TimeToString(z.flipTime,TIME_DATE|TIME_MINUTES), PriceS(z.flipLevel)), clrLime);
   else
      ExpAdd("نقش عوض نشده و ناحیه با همان نقش اولیه رهگیری می‌شود", clrLime);
   ExpAdd(StringFormat("تازگی: %s (%d بار برخورد)",
          (z.state==SDS_FRESH?"دست‌نخورده":(z.state==SDS_TESTED?"آزمون‌شده":(z.state==SDS_FLIPPED?"نقش‌عوض‌شده":"شکسته"))), z.tests), clrLime);
   ExpAdd("دست‌نخورده یعنی بدون برخورد؛ آزمون‌شده یعنی استاپ‌های آن سمت مصرف شده و اعتبار کمتر است", clrSilver);
   // فاز ۳۶: Strength of Zone (امتیاز ترکیبی مستند)
   ExpAdd(StringFormat("قدرت ناحیه: %d از ۵", z.strength),
          z.strength>=4?clrLime:(z.strength==3?clrAqua:clrOrange));
   if(z.strengthText!="") ExpAddWrapped("تفکیک قدرت: "+z.strengthText, z.strength>=4?clrLime:(z.strength==3?clrAqua:clrOrange));
   ExpAdd("معیارهای مستند: خروج شارپ‌تر یعنی قوی‌تر؛ پایهٔ تنگ‌تر یعنی سفارش متراکم‌تر؛ سه تا پنج کندل پایه استاندارد منابع است؛ هم‌زمانی با گپ ضریب تقویت است", clrSilver);
   if(z.tests>=2)
      ExpAddWrapped("هشدار جذب سفارش: این ناحیه چند بار برخورد خورده و هر بار پذیرفته نشده؛ یعنی سفارش مخالف در حال جذب است و نواحی آزمون‌شده ریسک بالاتری دارند", clrOrange);
   ExpAddWrapped("فیک و باطل: بستهٔ قاطع از سمت مقابل نقش، ناحیه را برمی‌گرداند و از آن لحظه با نقش جدید رهگیری می‌شود", clrOrange);
   ExpAddWrapped("اگر قیمت دوباره از سمت مقابل نقش جدید ببندد ناحیه شکسته و بی‌اعتبار است و ورود برعکس روی ناحیهٔ برگشته ریسک بالا دارد", clrTomato);
   ExpAdd(StringFormat("کنترل خودت: پایه را پیدا کن (یک تا %d کندل بستهٔ کم‌دامنه با سقف دامنه کمتر از %.2f برابر میانگین دامنه) و نسبت خروج را خودت اندازه بگیر",
          InpSD_BaseMaxBars, InpSD_BaseMaxRangeATR), clrSilver);
}

// فاز ۳۳: متن آموزشی Al Brooks روی خوانش واقعی همان کندل بازنویسی شد
// (قبلاً «H1 = اولین پولبک» نوشته بود که با تعریف منبع نمی‌خواند) و همهٔ اعداد
// از یک منبع واحد (g_brooksInfo) می‌آید تا پنل با داشبورد ناهمخوان نباشد.
void ExplainBrooks()
{
   g_expTitle="AL BROOKS — PRICE ACTION";
   ExpAdd(StringFormat("نوع کندل جاری: %s",
          g_brooksInfo.isTrendBar? "کندل روند" : (g_brooksInfo.isSignalBar? "کندل سیگنال" : (g_brooksInfo.isDoji? "دوجی یا بدنهٔ کوچک":"عادی"))), clrWhite);
   ExpAdd(StringFormat("آستانهٔ کندل روند: بدنه به دامنه باید %.2f یا بیشتر باشد", InpBrooks_TrendBarRatio), clrWhite);
   ExpAddWrapped(StringFormat("وضعیت جهت همیشگی: %s — این یک حالت است، نه شمارش کندل همرنگ: قیمت نسبت به ۲۰ میانگین متحرک (%.5f) و شیب %d کندلی همان میانگین متحرک سنجیده می‌شود. تا وقتی جهت همیشگی صعودی است، هر پولبک فرصت خرید در جهت است، نه دلیل فروش برعکس",
                 g_brooksInfo.alwaysIn>0? "صعودی" : (g_brooksInfo.alwaysIn<0? "نزولی":"خنثی (بی‌روند)"),
                 g_brooksInfo.ema20, InpBrooks_AI_EMASlopeBars), clrLime);
   ExpAdd(StringFormat("شمارش پولبک: تلاش سقفی %d و تلاش کفی %d در پنجرهٔ %d کندل", g_brooksInfo.hAttempts, g_brooksInfo.lAttempts, InpBrooks_PullbackWindow), clrAqua);
   ExpAddWrapped("تعریف شمارش: نخستین کندلی که سقف کندل قبلی را رد کند تلاش یک است؛ اگر آن تلاش شکست بخورد و قیمت پایین‌تر برود تلاش بعدی شماره دو است و همین‌طور تا چهار (گوه)", clrAqua);
   ExpAdd("پس شماره دو یعنی کف بالاتر نیست، یعنی شمارش تلاش", clrAqua);
   ExpAdd(StringFormat("کندل جاری: کندل ورود %s | کندل سیگنال %s | شکست ناموفق %s",
          g_brooksInfo.isEntryBar?"بله":"خیر", g_brooksInfo.isSignalBar?"بله":"خیر", g_brooksInfo.failedBreakout?"بله":"خیر"), clrWhite);
   ExpAdd("کندل ورود همان کندل روند است که بلافاصله پس از کندل سیگنال می‌آید و کندل سیگنال فقط با بافت معنا دارد: بسته‌شدن نزدیک اکستریم در جهت و پس از یک دامنهٔ مخالف", clrSilver);
   // --- فاز ۳۶: Trading Range / Measured Move / Channel ---
   ExpAddWrapped(g_brooksInfo.inTradingRange
      ? StringFormat("رنج دوطرفه: فعال — مرزها %.2f تا %.2f در %d کندل | میانهٔ رنج %.2f مغناطیس است: تا وقتی قیمت آنجاست انتظار نوسان می‌رود نه روند، و ورود در میانه بدترین جای کار است",
                     g_brooksInfo.trLow, g_brooksInfo.trHigh, g_brooksInfo.trBars, g_brooksInfo.trMid)
      : "رنج دوطرفه: فعلاً تشخیص داده نشد (بازار یک‌سویه یا روند) — شرطش حضور مؤثر هر دو طرف در پنجرهٔ بیست کندلی و نزدیک‌شدن قیمت به هر دو مرز است",
      g_brooksInfo.inTradingRange?clrAqua:clrSilver);
   if(g_brooksInfo.trBreakUp || g_brooksInfo.trBreakDn)
      ExpAddWrapped(StringFormat("شکست مؤثر از رنج: %s — بستهٔ قاطع بیرون مرز؛ در رنجهای دوطرفهٔ تازه اغلب شکست دوم هم ناموفق است، پس انتظار برگشت به مرز دیگر را داشته باش",
                    g_brooksInfo.trBreakUp?"رو به بالا":"رو به پایین"), clrLime);
   if(g_brooksInfo.trFailedBreakUp || g_brooksInfo.trFailedBreakDn)
      ExpAdd(StringFormat("شکست ناموفق: %s — فتیله از مرز بیرون رفت ولی کندل داخل رنج بست؛ شکست ناموفق اغلب حرکت مخالف می‌سازد",
                    g_brooksInfo.trFailedBreakUp?"سقف رنج":"کف رنج"), clrOrange);
   ExpAddWrapped(g_brooksInfo.mmValid
      ? StringFormat("حرکت اندازه‌گیری‌شده: نقطهٔ آغاز %.2f، اوج میانی %.2f، پولبک %.2f و هدف %.2f که صد درصد امتداد نخستین دامنه است؛ دامنهٔ دوم که اندازهٔ دامنهٔ اول را تکرار کند هدف محاسبه‌پذیر می‌دهد",
                     g_brooksInfo.mmA, g_brooksInfo.mmB, g_brooksInfo.mmC, g_brooksInfo.mmD)
      : "حرکت اندازه‌گیری‌شده: فعلاً الگوی معتبری یافت نشد — سه پیوت تأییدشده با پولبک بین دو دامنه لازم است",
      g_brooksInfo.mmValid?clrLime:clrSilver);
   ExpAddWrapped(g_brooksInfo.chSlope!=0
      ? StringFormat("کانال: سوگیری %s و قیمت %s میانگین متحرک بیست دوره (%.5f)؛ خط کانال موازی خط روند و هدف یا مغناطیس بعدی حرکت است و کانال تند اغلب با شکست به سمت مخالف پایان می‌یابد",
                     g_brooksInfo.chSlope>0?"صعودی":"نزولی", g_brooksInfo.chSlope>0?"بالای":"زیر", g_brooksInfo.ema20)
      : "کانال: شیب قابل‌توجهی تشخیص داده نشد (جهت همیشگی خنثی یا قیمت چسبیده به میانگین متحرک)",
      g_brooksInfo.chSlope!=0?clrAqua:clrSilver);
   ExpAddWrapped("فیک و باطل: اگر شکست فقط با فتیله باشد و کندل داخل ببندد شکست ناموفق است و اغلب حرکت مخالف می‌سازد؛ و اگر جهت همیشگی خنثی شود و قیمت دو طرف میانگین متحرک سرگردان باشد شمارش تلاش‌ها اعتباری ندارد", clrOrange);
   ExpAdd(StringFormat("کنترل خودت: بدنه به دامنه را با %.2f و نسبت فتیله را با %.2f مقایسه کن؛ برای کندل دوجی آستانهٔ بدنه %.2f است",
          InpBrooks_TrendBarRatio, InpBrooks_TailMaxRatio, InpBrooks_DojiBodyRatio), clrSilver);
}

// فاز ۳۴: توضیح فارسی مخصوص هر رویداد RTM (کلیک روی خود آبجکت، نه فقط خلاصه)
void ExplainRTMEvent(const RTMObj &e)
{
   g_expTitle="RTM "+RTMEventCode(e.evt)+" #"+IdToStr(e.id);
   ExpAdd(StringFormat("چیست: %s — کندل %s · قیمت محوری %s",
          RTMEventFa(e.evt), TimeToString(e.time,TIME_DATE|TIME_MINUTES), PriceS(e.price)), clrWhite);
   ExpAddWrapped("چرا شکل گرفت: "+e.note, clrAqua);
   ExpAddWrapped(StringFormat("محدودهٔ رویداد: %s تا %s — جهت: %s",
                 PriceS(e.bottom), PriceS(e.top), e.dir>0?"صعودی":(e.dir<0?"نزولی":"خنثی (جعبهٔ فشر‌دگی)")), clrWhite);
   if(e.evt==RTM_TRAP)
      ExpAddWrapped("درست و فیک: درست آن است که قیمت بعد از تله در جهت مخالف فتیله ادامه دهد و از انتهای مخالف بسته شود؛ فیک برگشت فوری به داخل و بسته‌شدن آن‌طرف جعبه با کندل مخالف است", clrLime);
   else if(e.evt==RTM_EXPANSION)
      ExpAddWrapped("درست و فیک: درست آن است که حرکت در همان جهت ادامه دهد و قیمت بیرون جعبه بماند؛ فیک برگشت سریع به داخل جعبه است (انبساط کاذب)", clrLime);
   else if(e.evt==RTM_MOMENTUM)
      ExpAddWrapped("درست و فیک: درست آن است که کندل بعد در جهت ممنتوم ببندد (تداوم حرکت)؛ فیک کندلی است که کل دامنهٔ ممنتوم را پس بدهد", clrLime);
   else if(e.evt==RTM_ENGULF)
      ExpAddWrapped("درست و فیک: پوشش بدنه باید در انتهای یک حرکت مخالف رخ دهد؛ اگر وسط رنج باشد صرفاً نوسان است", clrLime);
   else if(e.evt==RTM_REJECTION)
      ExpAddWrapped("درست و فیک: رد واقعی وقتی است که قیمت به قیمت‌های سطح قبلی‌تر برنگردد؛ اگر چند کندل بعد سطح دوباره آزمون و بازدید شود، رد ناتمام است", clrLime);
   else
      ExpAddWrapped("درست و فیک: فشر‌دگی فقط کاهش دامنه است؛ تا انبساط جهت‌دار نیاید معاملهٔ فشر‌دگی بی‌جهت است", clrLime);
   ExpAdd(StringFormat("کنترل خودت: فشر‌دگی با میانگین دامنهٔ کمتر از %.2f برابر روی %d کندل | ممنتوم با دامنهٔ %.2f برابر و بدنهٔ %.0f درصد | فتیلهٔ رد %.0f درصد",
          InpRTM_CompressRangeATR, InpRTM_CompressBars, InpRTM_MomentumATR,
          InpRTM_MomentumBody*100.0, InpRTM_RejectTailRatio*100.0), clrSilver);
}

void ExplainRTM()
{
   g_expTitle="RTM — READ THE MARKET";
   ExpAdd(StringFormat("چیست: چرخهٔ فشر‌دگی و انبساط و رویدادهای رفتاری درون آن؛ فشر‌دگی یعنی میانگین دامنهٔ %d کندل کمتر از %.2f برابر میانگین دامنه (انرژی ذخیره‌شده)",
          InpRTM_CompressBars, InpRTM_CompressRangeATR), clrWhite);
   ExpAdd("وضعیت فعلی: "+(g_rtmNote==""? "هیچ فشر‌دگی فعالی نیست":g_rtmNote), clrAqua);
   ExpAdd(StringFormat("رویدادهای رهگیری‌شده در رجیستری: %d مورد — فشر‌دگی و انبساط، تله (فتیله بیرون جعبه و بسته داخل)، ممنتوم، پوشش بدنه و پس‌زدگی", ArraySize(g_rtm)), clrLime);
   ExpAdd(StringFormat("آستانه‌ها: ممنتوم با دامنهٔ %.2f برابر میانگین دامنه و بدنهٔ %.0f درصد | پس‌زدگی با فتیلهٔ %.0f درصد دامنه و بسته‌شدن در ثلث مخالف", InpRTM_MomentumATR, InpRTM_MomentumBody*100.0, InpRTM_RejectTailRatio*100.0), clrSilver);
   if(ArraySize(g_rtm)>0)
   {
      RTMObj last=g_rtm[ArraySize(g_rtm)-1];
      ExpAdd(StringFormat("آخرین رویداد: %s در %s", RTMEventFa(last.evt),
             TimeToString(last.time,TIME_DATE|TIME_MINUTES)), clrWhite);
      ExpAddWrapped(last.note, clrWhite);
   }
   ExpAddWrapped("نحوهٔ استفاده: ورود پس از انبساط در جهت آن، یا پس از تله در جهت مخالف فتیله؛ پوشش بدنه و پس‌زدگی تأییدکننده‌اند نه دلیل ورود — و اگر قیمت از انتهای مخالف جعبهٔ فشر‌دگی بسته شود سناریو باطل است", clrLime);
   ExpAddWrapped("فیک و باطل: انبساط بدون جهت مشخص یا کندلی که فتیلهٔ تله را بزند ولی بیرون همان جعبه ببندد تلهٔ واقعی نیست؛ فشر‌دگی هم بدون انبساط نویز است", clrOrange);
   ExpAdd(StringFormat("کنترل خودت: میانگین دامنهٔ %d کندل را با %.2f برابر میانگین دامنه و نسبت بدنه به دامنه را با %.2f مقایسه کن",
          InpRTM_CompressBars, InpRTM_CompressRangeATR, InpRTM_MomentumBody), clrSilver);
}

void ExplainProfile()
{
   g_expTitle="MARKET / VOLUME PROFILE + AMT";
   if(!g_profileDaily.valid){ ExpAddWrapped("پروفایل هنوز ساخته نشده", clrOrange); return; }
   ExpAdd(StringFormat("چیست: توزیع حجم روی ردیف‌های قیمتی از %d کندل اخیر", InpProfileLookbackBars), clrWhite);
   ExpAdd(StringFormat("قیمت با بیشترین حجم %.2f | سقف محدودهٔ ارزش %.2f | کف محدودهٔ ارزش %.2f",
          g_profileDaily.poc, g_profileDaily.vah, g_profileDaily.val), clrWhite);
   // ---------- فاز ۳۴: Auction Market Theory ----------
   if(g_profileDaily.tpoValid)
      ExpAdd(StringFormat("توضیح زمان‌محور: قیمت با بیشترین زمان %.2f | محدودهٔ ارزش زمانی %.2f تا %.2f",
             g_profileDaily.tpoPoc, g_profileDaily.tpoVah, g_profileDaily.tpoVal), clrAqua);
      ExpAdd("این عدد از شمارش زمان در هر ردیف می‌آید نه از حجم؛ پس تفاوت آن با قیمت پرحجم عیب نیست و دو ابزار متفاوت است", clrSilver);
   if(g_profileDaily.amtValid)
   {
      ExpAdd(StringFormat("ارزش اولیه: نخستین %d دقیقهٔ روز از %.2f تا %.2f",
             InpProfileIB_Minutes, g_profileDaily.ibLo, g_profileDaily.ibHi), clrMagenta);
      ExpAdd("شکست یک‌طرفهٔ ارزش اولیه همراه با نبود بازگشت روز روندی می‌سازد و برگشت به داخل روز خنثی", clrMagenta);
      ExpAdd(StringFormat("نوع روز: %s | نوع باز شدن: %s", AMTDayTypeFa(g_profileDaily.dayType), AMTOpenTypeFa(g_profileDaily.openType)), clrLime);
      ExpAdd(StringFormat("وضعیت بازار: %s", g_profileDaily.balanceNote), clrLime);
      ExpAdd(StringFormat("باز شدن روز %.5f | بسته شدن روز %.5f | کف و سقف روز %.5f تا %.5f",
             g_profileDaily.dayOpen, g_profileDaily.dayClose, g_profileDaily.dayLo, g_profileDaily.dayHi), clrLime);
      if(g_profileDaily.hasNakedPoc)
         ExpAdd(StringFormat("قیمت پرحجم لمس‌نشده: %.2f از روز %s — این سطح از بسته شدن آن سشن تا الان لمس نشده و رفتار آهنربایی دارد؛ ورود برعکس درست روی آن پرریسک است",
                g_profileDaily.nakedPoc, TimeToString(g_profileDaily.nakedPocDay,TIME_DATE)), clrTomato);
   }
   ExpAdd(StringFormat("گره‌های پرحجم و کم‌حجم: %d و %d — گرهٔ پرحجم جایی است که بازار وقت زیادی گذرانده (مانع و آهنربا) و گرهٔ کم‌حجم جایی که سریع عبور کرده (مسیر کم‌مقاومت)",
          g_profileDaily.hvnCount, g_profileDaily.lvnCount), clrAqua);
   ExpAdd(StringFormat("آستانه‌ها: گرهٔ پرحجم با نسبت %.2f و بیشتر و گرهٔ کم‌حجم با نسبت %.2f و کمتر از میانگین ردیف‌ها", InpProfileHVN_Ratio, InpProfileLVN_Ratio), clrSilver);
   ExpAddWrapped("فیک و باطل: هر سه سطح (ارزش اولیه، محدودهٔ ارزش و گرهٔ پرحجم) با شکست و پذیرش یعنی بسته‌شدن بیرون بی‌اعتبار می‌شوند؛ اگر قیمت فقط فتیله بزند و داخل ببندد سطح هنوز معتبر است", clrOrange);
   ExpAdd(StringFormat("حجم کل پنجره: %d تیک — صادقانه: کلاینت فقط حجم تیکی می‌دهد، پس این تقریب است نه حجم واقعی معاملات", g_profileDaily.totalVol), clrOrange);
   ExpAddWrapped("چرا اهمیت دارد: قیمت پرحجم همان قیمت منصفانه است؛ ماندن قیمت داخل محدودهٔ ارزش یعنی پذیرش و خروج قوی از آن یعنی پس‌زدگی و آغاز روند", clrLime);
   ExpAddWrapped("فیک و باطل: برخورد لحظه‌ای به سقف یا کف محدودهٔ ارزش معنای رد ندارد؛ بازگشت سریع به داخل محدوده خرابیِ شکست است", clrOrange);
   ExpAdd(StringFormat("کنترل خودت: ردیف‌ها را با آستانهٔ درصد پوشش محدودهٔ ارزش بازبینی کن — مقدار فعلی %.1f درصد", InpProfileVA_Percent), clrSilver);
   ExpAdd("InpProfileVA_Percent — کلید درصد پوشش محدودهٔ ارزش", clrSilver);
}
// ---------- فاز ۳۶: لایهٔ Brooks Range/Measured Move (فقط وقتی فعال) ----------
// رنج دوطرفه با دو مرز + خط مغناطیس ۵۰٪ و هدف Measured Move (D). همه با یک
// آبجکت برای هر چیز و فقط وقتی گزینه روشن است — چارت پیش‌فرض تمیز می‌ماند.
void DrawBrooksRangeLayer()
{
   if(!InpEnableBrooksRange || !g_brooksInfo.inTradingRange) return;
   datetime t1=g_lastContextBarTime;
   if(t1<=0) return;
   datetime t2=(datetime)((long)t1+(long)PeriodSeconds(PERIOD_CURRENT)*MathMax(1,InpZoneExtendBars)*4);
   DrawBoxObj("ICTv13_BROOKS_TR", t1, g_brooksInfo.trHigh, t2, g_brooksInfo.trLow, PAL_BROOKS_TR, false, true, STYLE_DOT, 1,
              StringFormat("BROOKS TRADING RANGE | %.2f - %.2f | هر دو سناریوی صعودی و نزولی زنده است | وسط رنج (%.2f) مغناطیس است و شکست اغلب ناموفق می‌ماند",
                           g_brooksInfo.trLow, g_brooksInfo.trHigh, g_brooksInfo.trMid));
   DrawHLineObj("ICTv13_BROOKS_TRMID", g_brooksInfo.trMid, PAL_BROOKS_TRMID, STYLE_DOT, 1,
                StringFormat("BROOKS RANGE MID | نیمهٔ رنج (مغناطیس) = %.2f", g_brooksInfo.trMid));
   if(g_brooksInfo.mmValid)
      DrawHLineObj("ICTv13_BROOKS_MM", g_brooksInfo.mmD, PAL_BROOKS_MM, STYLE_DASHDOT, 1,
                   StringFormat("BROOKS MEASURED MOVE | D = %.2f | A = %.2f | B = %.2f | C = %.2f | هدف نهایی، صد درصد امتداد لگ اول",
                                g_brooksInfo.mmD, g_brooksInfo.mmA, g_brooksInfo.mmB, g_brooksInfo.mmC));
}

// ---------- فاز ۳۶: لایهٔ Quarterly Theory ----------
// فقط دو خط: True Open روز (نیمه‌شب نیویورک) و True Open هفته (دوشنبه نیویورک).
// ربع‌ها در داشبورد و پنل توضیح هستند تا چارت شلوغ نشود. هیچ سیگنالی نیست:
// QT یک «زمان‌بند» است، نه سیگنال (منبع: صریحاً در همان مقاله).
void DrawQTLayer()
{
   if(!InpEnableQT || !InpDrawQTOpens) return;
   datetime t1=g_lastContextBarTime;
   if(t1<=0) return;
   datetime t2=(datetime)((long)t1+(long)PeriodSeconds(PERIOD_CURRENT)*MathMax(1,InpZoneExtendBars)*6);
   if(g_qtDayTrueOpen>0.0 && g_qtDayTrueOpenT>0)
   {
      string nm="ICTv13_QT_DAYOPEN";
      DrawHLineObj(nm,g_qtDayTrueOpen,PAL_QT_DAY,STYLE_DASHDOT,1,
         StringFormat("QUARTERLY THEORY | باز شدن واقعی روز (نیمه‌شب نیویورک) = %s از %s | قیمت زیر آن ناحیهٔ ارزان برای خرید است و بالای آن ناحیهٔ گران برای فروش؛ این همان باز شدن ربع دوم است",
                      DoubleToString(g_qtDayTrueOpen,_Digits), TimeToString(g_qtDayTrueOpenT,TIME_DATE)));
   }
   if(g_qtWkTrueOpen>0.0 && g_qtWkTrueOpenT>0)
   {
      string nm="ICTv13_QT_WKOPEN";
      DrawHLineObj(nm,g_qtWkTrueOpen,PAL_QT_WEEK,STYLE_DASHDOT,1,
         StringFormat("QUARTERLY THEORY | باز شدن واقعی هفته (دوشنبه نیمه‌شب نیویورک) = %s | مرجع ناحیهٔ گران و ارزان هفتگی", DoubleToString(g_qtWkTrueOpen,_Digits)));
   }
}

string QTPhaseToStr(ENUM_QT_PHASE p)
{
   switch(p)
   {
      case QT_Q1_ACCUM:   return "Q1 ACCUMULATION (18:00-00:00 NY)";
      case QT_Q2_MANIP:   return "Q2 MANIPULATION (00:00-06:00 NY)";
      case QT_Q3_DISTRIB: return "Q3 DISTRIBUTION (06:00-12:00 NY)";
      case QT_Q4_REVERSAL:return "Q4 CONTINUATION/REVERSAL (12:00-18:00 NY)";
   }
   return "—";
}

// پنل آموزشی Quarterly Theory (کلیک روی خطوط True Open یا آبجکت QT_)
void ExplainQT(bool week)
{
   g_expTitle=week? "QUARTERLY THEORY — WEEK" : "QUARTERLY THEORY — DAY";
   ExpAddWrapped("چیست: هر چرخهٔ زمانی به چهار ربع تقسیم می‌شود و انتظار می‌رود قالب انباشت، دستکاری، توزیع و ادامه یا برگشت در هر ربع تکرار شود", clrWhite);
   ExpAdd("قالب ربع‌ها: ربع نخست انباشت با رنج تنگ، ربع دوم دستکاری با جارو، ربع سوم توزیع با حرکت انبساطی، و ربع چهارم ادامه یا برگشت", clrAqua);
   ExpAdd("Source: arongroups — Quarterly Theory", clrSilver);
   if(!week)
   {
      ExpAdd("ربع فعلی روز: "+QTPhaseFa(g_qtDayPhase), clrLime);
      ExpAddWrapped(g_qtDayTrueOpen>0.0
         ? StringFormat("باز شدن واقعی روز %.5f — همان کندل ساعت صفر نیویورک؛ قاعده: خرید زیر آن (نیمهٔ ارزان) و فروش بالای آن (نیمهٔ گران) ترجیح دارد", g_qtDayTrueOpen)
         : "باز شدن واقعی روز هنوز ثبت نشده است", g_qtDayTrueOpen>0.0?clrAqua:clrOrange);
      ExpAddWrapped("درست و فیک: جارو شدن رنج ربع نخست در ربع دوم سیگنال اصلی است؛ اگر جارویی نبود چرخه طبق قالب نرفته", clrLime);
      ExpAdd("در هیچ حالتی الزامی به معامله نیست — این ابزار زمان‌بند است نه سیگنال", clrLime);
      ExpAdd("ربع فعلی هفته: "+QTPhaseFa(g_qtWeekPhase), clrAqua);
      ExpAddWrapped("روایت رایج هفته: دوشنبه ربع نخست، سه‌شنبه ربع دوم، چهارشنبه ربع سوم و پنج‌شنبه و جمعه ربع چهارم؛ برخی منابع جمعه را از شمارش بیرون می‌دانند", clrSilver);
   }
   else
   {
      ExpAddWrapped(g_qtWkTrueOpen>0.0
         ? StringFormat("باز شدن واقعی هفته %.5f — نخستین کندل دوشنبه پس از نیمه‌شب نیویورک؛ مرجع نیمهٔ گران و ارزان هفتگی", g_qtWkTrueOpen)
         : "باز شدن واقعی هفته هنوز ثبت نشده است", g_qtWkTrueOpen>0.0?clrAqua:clrOrange);
      ExpAddWrapped("نکتهٔ صادقانه: روایت‌های متفاوتی از شمارش هفته وجود دارد و این ابزار روایت اصلی را نشان می‌دهد و همان را صریح می‌گوید", clrSilver);
   }
   ExpAddWrapped("اتصال به بقیهٔ سیستم: ربع دوم نیویورک همان پنجرهٔ جاروی لندن است و ربع سوم همان پنجرهٔ نیویورک؛ پس جارویی که این سیستم در آن پنجره‌ها ثبت می‌کند دقیقاً همان رویداد ربع دوم است — دو نام برای یک رویداد، نه دو محاسبه", clrAqua);
   ExpAddWrapped("کنترل خودت: ساعت نیویورک را از داشبورد بخوان؛ ربع فعلی باید با ساعت هم‌خوان باشد و خط باز شدن واقعی باید روی بازِ کندل نیمه‌شب نیویورک باشد", clrSilver);
}

void DrawPhase12Layer()
{
   if(!InpEnablePhase12) return;
   if(InpDetectTrendlineLiq && InpDrawTrendlines)
   {
      for(int i=0;i<ArraySize(g_trendlines);i++)
      {
         if(g_trendlines[i].invalidated) continue;
         string nm="ICTv13_TRENDLINE_"+IdToStr(g_trendlines[i].id);
         datetime t2=g_trendlines[i].t2;
         int extend=MathMax(1,InpZoneExtendBars);
         datetime t1=(datetime)((long)g_lastContextBarTime+(long)PeriodSeconds(PERIOD_CURRENT)*extend);
         if(t1<=t2) t1=(datetime)((long)t2+(long)PeriodSeconds(PERIOD_CURRENT)*extend);
         double p1=TrendlinePriceAt(g_trendlines[i],t1);
         double p2=TrendlinePriceAt(g_trendlines[i],t2);
         if(p1<=0.0 || p2<=0.0) continue;
         if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_TREND,0,t2,p2,t1,p1);
         ObjectSetInteger(0,nm,OBJPROP_TIME,0,t2);  ObjectSetDouble(0,nm,OBJPROP_PRICE,0,p2);
         ObjectSetInteger(0,nm,OBJPROP_TIME,1,t1);  ObjectSetDouble(0,nm,OBJPROP_PRICE,1,p1);
         ObjectSetInteger(0,nm,OBJPROP_COLOR,g_trendlines[i].isHigh?PAL_LIQ_HIGH:PAL_LIQ_LOW);
         // فاز ۳۰: خطی که نقدینگی‌اش جارو شده دیگر هدف نیست ولی حذف نمی‌شود
         // (تاریخچهٔ آموزش)؛ فقط خط‌چین نمایش داده می‌شود تا با خط زنده قاطی نشود.
         ObjectSetInteger(0,nm,OBJPROP_STYLE,g_trendlines[i].swept?STYLE_DASH:STYLE_DOT);
         ObjectSetInteger(0,nm,OBJPROP_WIDTH,1);
         ObjectSetInteger(0,nm,OBJPROP_RAY_RIGHT,false);
         ObjectSetString(0,nm,OBJPROP_TOOLTIP,"\n");
         MarkDrawnLayerObj(nm);
      }
   }
   POIObj bp;
   if(InpDrawBestPOI && FindBestPOI(DIR_NONE, bp) && bp.top>bp.bottom)
   {
      string nm="ICTv13_POI_BEST";
      int extend=MathMax(1,InpZoneExtendBars);
      // فاز ۴۸: باکس POI برتر، «برجسته‌سازی» است نه یک خانوادهٔ تازه. رنگش را از
      // خود جهت می‌گیرد (همان دو ورودی کاربر)، چون یک باکس POI بدون جهت معنا ندارد؛
      // پیش‌تر DeepSkyBlue/OrangeRed بود که با اردربلاک بریکر و گپ نزولی قاطی می‌شد.
      DrawBoxObj(nm, bp.time, bp.top,
                 (datetime)((long)bp.time+(long)PeriodSeconds(PERIOD_CURRENT)*extend), bp.bottom,
                 bp.direction==DIR_BULL?InpColorBull:InpColorBear, false, true, STYLE_DOT, 1,
                 "POI "+PoiKindToStr(bp.kind));
   }
}

void RedrawChartObjects()
{
   // فاز ۱۴: کل لایه دیگه پاک نمی‌شود. فقط مجموعهٔ «رسم‌شدهٔ این pass» صفر
   // می‌شود و در پایان ReconcileChartLayer تصمیم می‌گیرد چه چیزی زنده، چه چیزی
   // حذف (لایهٔ خاموش/فیلتر صریح) و چه چیزی frozen (خارج از سقف نمایش) است.
   PurgeFrozenOnContextChange();
   ResetPassDrawSet();

   g_htfEventsDrawn=0;
   if(InpDrawStructureEvents)
   {
      int drawn=0;
      for(int i=ArraySize(g_events)-1; i>=0 && drawn<InpMaxDrawnZones; i--)
      {
         if(g_events[i].isHTF) continue;
         DrawStructureEvent(g_events[i]);
         drawn++;
      }
   }
   // فاز ۱۵: رویداد ساختاری HTF پیش از این **هیچ آبجکتی** نداشت؛ کامنت قدیمی
   // می‌گفت «HTF روی لایهٔ MTF نمایش داده می‌شود»، ولی DrawMTFLayer فقط سقف/کف
   // محافظت‌شده را می‌کشد. یک BOS/CHoCH روی H4 فقط در داشبورد دیده می‌شد.
   if(InpDrawHTFEvents)
   {
      int drawnH=0;
      for(int i=ArraySize(g_events)-1; i>=0 && drawnH<InpMaxDrawnHTFEvents; i--)
      {
         if(!g_events[i].isHTF) continue;
         DrawStructureEvent(g_events[i]);
         drawnH++;
      }
      g_htfEventsDrawn=drawnH;
   }
   DrawZoneLayer();
   if(InpDrawLiquidity)     DrawLiquidityLayer();
   if(InpDrawSweepMarkers)  DrawSweepLayer();
   DrawSessionLayer();
   DrawMTFLayer();
   DrawSetupLayer();
   DrawQTLayer();   // فاز ۳۶: True Open روز/هفته (Quarterly Theory)
   DrawBrooksRangeLayer();   // فاز ۳۶: Trading Range + Measured Move
   if(g_leg.valid && InpDrawSetupBox) DrawLocationLevels();  // EQ/OTE/Golden فقط با باکس ستاپ (همان خانوادهٔ تصمیم ورود)
   DrawDOLLine();
   DrawReversalLevels();
   DrawPhase12Layer();
   DrawFamiliesLayer();   // فازهای ۱۶–۲۱

   // فاز ۱۴: آشتی — آبجکت‌های رسم‌شده در همین pass تازه شدند، بقیه با سبک frozen
   // نگه داشته یا (اگر لایه/ فیلتر خاموش باشد) حذف می‌شوند. هیچ ناحیه‌ای دیگر
   // با پر شدن سقف نمایش ناپدید نمی‌شود.
   ReconcileChartLayer();
   ChartRedraw(0);

   if(InpLogPhase14OnRedraw)
      PrintFormat("ICT PHASE14 | layer objs %d | drew %d | frozen %d (added %d / restored %d / evicted %d) | hidden-deleted %d | dash rows %d | dash width %d",
                  g_rcLayerObjects, g_rcDrawn, g_rcFrozen,
                  (int)g_frozenAdded, (int)g_frozenRestored, (int)g_frozenEvicted,
                  (int)g_hiddenDeleted, g_dashRows, g_dashWidth);

   // ------------------------------------------------------------------
   // فاز ۲۲ — ایراد واقعی «هیچ‌چیزم نمی‌نویسد»:
   // قبلاً همین‌جا (بی هیچ شرطی) در هر pass رسم، ``g_expHovered=""`` و خطوط پاک
   // می‌شدند و RenderExplainPanel با total==0 همهٔ ردیف‌های EDIT پنل را حذف
   // می‌کرد. RedrawChartObjects دقیقاً یک‌بار در هر **کندل بسته** و یک‌بار در پایان
   // بازسازی تاریخچه اجرا می‌شود (نه هر tick)؛ یعنی روی M1 هر ۶۰ ثانیه و بعد از
   // هر rebuild، پنل نابود می‌شد. حالا فقط وقتی آبجکتِ زیر موس دیگر روی چارت
   // نیست پنل بسته می‌شود؛ در غیر این صورت دست‌نخورده می‌ماند تا کاربر توضیح
   // را بخواند.
   // ------------------------------------------------------------------
   if(g_expHovered!="" && ObjectFind(0,g_expHovered)<0)
   {
      g_expHovered="";
      ExpClear();
      RenderExplainPanel();
   }
   if(InpWriteExplainCsv || InpSetObjectTooltips) ExplainSaveCsv();
   else ExplainClearStaleTooltips();
   if(InpWriteExplainCsv) PersistFVGDictionary();
   if(InpWriteExplainCsv) PersistLegDictionary();
}

// فاز ۱۴: شاهد عددی برای دو معیار پذیرش این فاز:
//   ۱) «تاریخچهٔ رسم‌شده با پر شدن سقف‌های نمایش ناپدید نمی‌شود»
//      → ستون‌های LayerDrawn / FrozenLive / FrozenAdded / FrozenRestored / FrozenEvicted
//   ۲) «هیچ متن بریده/کهنه/روی‌هم‌افتاده‌ای در داشبورد نمی‌ماند»
//      → ستون‌های DashRows / DashWidth / DashMaxRowW / DashStaleDeleted / DashWrappedRows / DashOverflowRows
// روی هر کندل بسته یا با تغییر هر یک از این اعداد یک ردیف می‌گیرد.
void PersistPhase14Diagnostics()
{
   if(!InpWritePhase14Diagnostics) return;
   datetime barTime=g_lastContextBarTime;
   static datetime lastBar=0;
   static long     lastHash=-1;
   // فاز ۲۴ (کارایی): این تابع هر tick صدا زده می‌شود. قبلاً هر tick هشت
   // IntegerToString و هفت پیوند رشته می‌ساخت (تخصیص حافظه در مسیر داغ) فقط
   // برای مقایسه. حالا اول یک درهم‌ساز عددی ارزان مقایسه می‌شود؛ رشته و فایل
   // فقط وقتی واقعاً تغییری رخ داده ساخته می‌شوند.
   long sig=0;
   sig=sig*131L+g_rcLayerObjects; sig=sig*131L+g_rcDrawn;  sig=sig*131L+g_rcFrozen;
   sig=sig*131L+g_dashRows;       sig=sig*131L+g_dashWidth; sig=sig*131L+g_dashStale;
   sig=sig*131L+g_dashWrapped;    sig=sig*131L+g_dashOverflow;
   if(barTime==lastBar && sig==lastHash) return;
   lastBar=barTime; lastHash=sig;

   int h=FileOpen("ICT_Assistant_Canonical_Phase14_Diag.csv",FILE_COMMON|FILE_READ|FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_SHARE_WRITE,';');
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0)
      FileWrite(h,"BarTime","BuildStamp","Symbol","Period",
                "LayerObjects","LayerDrawn","FrozenLive","FrozenAdded","FrozenRestored","FrozenEvicted","HiddenDeleted",
                "FrozenHistoryEnabled","MaxFrozenObjects",
                "DashRows","DashWidth","DashHeight","DashMaxRowW","DashStaleDeleted","DashWrappedRows","DashOverflowRows",
                "MaxDrawnZones","MaxDrawnLevels");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,
             TimeToString(barTime,TIME_DATE|TIME_MINUTES),
             g_buildStamp, _Symbol, EnumToString((ENUM_TIMEFRAMES)Period()),
             g_rcLayerObjects, g_rcDrawn, g_rcFrozen,
             (int)g_frozenAdded, (int)g_frozenRestored, (int)g_frozenEvicted, (int)g_hiddenDeleted,
             InpFrozenHistoryEnabled?"true":"false", InpMaxFrozenObjects,
             g_dashRows, g_dashWidth, g_dashHeight, g_dashMaxRowW, g_dashStale, g_dashWrapped, g_dashOverflow,
             InpMaxDrawnZones, InpMaxDrawnLevels);
   FileClose(h);
}

//====================================================================
// EXPLAIN MODE (اندیکاتور + استاد)
// با بردن موس روی هر خط/ناحیه، یک پنل چندخطی نشان داده می‌شود:
//   چیست، چرا تشکیل شد، چه شرطی آن را معتبر می‌کند، چه چیزی آن را
//   فیک/بی‌اعتبار می‌کند، و چطور خودت مقدار را کنترل کنی.
// قاعدهٔ RTL: در هر خط، قطعه‌های لاتین به ابتدای خط منتقل می‌شوند تا
// کلمهٔ انگلیسی وسط جملهٔ فارسی نیفتد و متن به‌هم نریزد.
//====================================================================
string g_expTitle="";
string g_expLines[];
color  g_expLineColors[];
string g_expHovered="";
int    g_expPanelRows=0;
int    g_expAnchorX=0;
int    g_expAnchorY=0;

//--------------------------------------------------------------------
// فاز ۴۴ — عقد بسته‌شدهٔ مسیر کلیک: هر کلیک باید یا توضیح تخصصی همان آبجکت
// را نشان بدهد، یا یک پیام صادقانه بگوید چرا توضیح تخصصی نیست. حالت سوم
// («هیچ نمی‌نویسد») دیگر مجاز نیست، چون برای کاربر از یک خطای حساب هم
// گیج‌کننده‌تر است: نمی‌داند آبجکت چیست، نمی‌داند اشکال از اوست یا از کد.
// این وضعیت برای هر فراخوانی توضیح ثبت و در Journal شمارش می‌شود؛ پس
// «قطعی بودن» با عدد سنجیده می‌شود، نه با ادعا.
//--------------------------------------------------------------------
enum ENUM_CLICK_RESOLVE
{
   CLICK_RS_NONE = 0,   // هنوز توضیحی ساخته نشده
   CLICK_RS_OK,         // توضیح تخصصی همین خانواده ساخته شد
   CLICK_RS_FALLBACK    // توضیح تخصصی نبود؛ پیام جایگزین ساخته شد
};
ENUM_CLICK_RESOLVE g_clickResolve = CLICK_RS_NONE;
string g_clickLastHit   = "";   // نام آبجکتی که آخرین بار توضیح خواست
string g_clickLastTitle = "";   // عنوانی که پنل نشان داد (شاهد همانتغییر)
long   g_clickCount     = 0;
long   g_clickOk        = 0;
long   g_clickFallback  = 0;
// فاز ۴۴ — تفکیک دو نوع پیام جایگزین: «خانوادهٔ ناشناخته» یک نقص کد است،
// ولی «مرجع از رجیستری بیرون افتاده» یک حالت معتبر است که باید توضیح داده
// شود. بدون این تفکیک، آزمون نمی‌تواند بین نقص کد و حالت طراحی‌شده فرق بگذارد.
string g_clickReason    = "";   // RESOLVED | REGISTRY_MISS | NO_HANDLER
// فاز ۴۴ — شمارندهٔ آزمون خودکار مسیر کلیک (پایین‌تر در 26_PersianRender)
int    g_clickTestObjects  = 0;
int    g_clickTestResolved = 0;
int    g_clickTestEmpty    = 0;
int    g_clickTestOffscreen= 0;
int    g_clickTestSelfHit  = 0;
int    g_clickTestWeakHit  = 0;

// قاعدهٔ RTL این فایل (سرصفحه) در RtlSafe() پایین‌تر پیاده شده است — آن تابع
// با توکن‌های واژه‌ای کار می‌کند، نه با تک‌تک کاراکترها.

void ExpClear()
{
   ArrayResize(g_expLines,0);
   ArrayResize(g_expLineColors,0);
   g_expTitle="";
}

bool IsPersianChar(ushort c)
{
   if(c>=0x0600 && c<=0x06FF) return true;   // Arabic block (شامل حروف فارسی)
   if(c>=0xFB50 && c<=0xFDFF) return true;   // Presentation Forms-A
   if(c>=0xFE70 && c<=0xFEFF) return true;   // Presentation Forms-B
   return false;
}

// ---------------------------------------------------------------------------
// قاعدهٔ RTL — نسخهٔ درست (فاز ۴۱)
// ---------------------------------------------------------------------------
// چرا واژهٔ لاتین وسط جملهٔ فارسی متن را ناخوانا می‌کند:
//   ردیف‌های پنل با OBJ_EDIT رسم می‌شوند و OBJ_EDIT یک کنترل بومی است که
//   خودش bidi را انجام می‌دهد. جهت پایهٔ خط با قاعدهٔ P2/P3 انتخاب می‌شود؛
//   یعنی همان اولین کاراکترِ قوی. یک خط فارسی که وسطش واژهٔ لاتین دارد، به
//   دو قطعهٔ مستقل راست‌به‌چپ شکسته می‌شود. ترتیب **واژه‌ها در هر قطعه**
//   درست می‌ماند، ولی ترتیب دو قطعه نسبت به هم در برخی جهت‌های پایه
//   جابه‌جا می‌شود و خواننده جمله را وارونه می‌بیند.
//   ارقام این بلا را سر نمی‌آورند: عدد اروپایی داخل متن راست‌به‌چپ، با
//   قاعدهٔ W از UBA داخل همان قطعه می‌ماند (نه یک قطعهٔ L جدید).
// پس فقط «توکن‌هایی که حرف لاتین دارند» جابه‌جا می‌شوند، نه ارقام.
bool TokenHasLatinLetter(string w)
{
   for(int i=0;i<StringLen(w);i++)
   {
      ushort c=StringGetCharacter(w,i);
      if((c>='A'&&c<='Z')||(c>='a'&&c<='z')) return true;
   }
   return false;
}

bool TokenHasPersianChar(string w)
{
   for(int i=0;i<StringLen(w);i++)
      if(IsPersianChar(StringGetCharacter(w,i))) return true;
   return false;
}

// هر واژهٔ لاتینی که *بعد* از یک واژهٔ فارسی بیاید، به ابتدای خط منتقل
// می‌شود (ترتیب خودشان حفظ می‌شود) و با « | » از جملهٔ فارسی جدا می‌شود؛
// پس پیام فارسی یک قطعهٔ یکپارچه می‌ماند و جابه‌جا نمی‌شود. خطی که لاتینش
// از قبل اول است، و خط تمام‌لاتین، دست‌نخورده می‌ماند.
// این تابع idempotent است: اجرای دوباره روی خروجی خودش هیچ تغییری نمی‌دهد.
string RtlSafe(string s)
{
   if(StringLen(s)==0) return s;
   if(!TokenHasPersianChar(s)) return s;   // خط تمام‌لاتین (یا فقط عدد/علامت)

   string words[];
   int wc=StringSplit(s,' ',words);
   if(wc<=0) return s;

   bool seenPersian=false, needsMove=false;
   for(int i=0;i<wc;i++)
   {
      if(StringLen(words[i])==0) continue;
      if(TokenHasLatinLetter(words[i]))
      {
         if(seenPersian){ needsMove=true; break; }
      }
      else if(TokenHasPersianChar(words[i])) seenPersian=true;
   }
   if(!needsMove) return s;

   string latinPart="", faPart="";
   for(int i=0;i<wc;i++)
   {
      if(StringLen(words[i])==0) continue;
      if(TokenHasLatinLetter(words[i]))
      {
         if(StringLen(latinPart)>0) latinPart+=" ";
         latinPart+=words[i];
      }
      else
      {
         if(StringLen(faPart)>0) faPart+=" ";
         faPart+=words[i];
      }
   }
   if(StringLen(faPart)==0) return latinPart;
   return latinPart+" | "+faPart;
}

//====================================================================
// موتور نمایش فارسی — مستقل از رندر متاتریدر
// MT5 متن RTL را چپ‌به‌راست می‌کشد، پس خودمان:
//   ۱) حروف را به شکل‌های چسبیده (Presentation Forms) تبدیل می‌کنیم
//   ۲) ترتیب را به ترتیب بصری (راست‌به‌چپ) برمی‌گردانیم
//   ۳) واژه‌های لاتین/عددی را دست‌نخورده و در ابتدای خط نگه می‌داریم
//====================================================================
int g_faBase[]={0x0621,0x0622,0x0623,0x0624,0x0625,0x0626,0x0627,0x0628,0x0629,0x062A,0x062B,0x062C,0x062D,0x062E,0x062F,0x0630,0x0631,0x0632,0x0633,0x0634,0x0635,0x0636,0x0637,0x0638,0x0639,0x063A,0x0641,0x0642,0x0643,0x0644,0x0645,0x0646,0x0647,0x0648,0x0649,0x064A,0x067E,0x0686,0x0698,0x06A9,0x06AF,0x06C0,0x06CC};
int g_faIsol[]={0xFE80,0xFE81,0xFE83,0xFE85,0xFE87,0xFE89,0xFE8D,0xFE8F,0xFE93,0xFE95,0xFE99,0xFE9D,0xFEA1,0xFEA5,0xFEA9,0xFEAB,0xFEAD,0xFEAF,0xFEB1,0xFEB5,0xFEB9,0xFEBD,0xFEC1,0xFEC5,0xFEC9,0xFECD,0xFED1,0xFED5,0xFED9,0xFEDD,0xFEE1,0xFEE5,0xFEE9,0xFEED,0xFEEF,0xFEF1,0xFB56,0xFB7A,0xFB8A,0xFB8E,0xFB92,0xFBA4,0xFBFC};
int g_faFina[]={0xFE80,0xFE82,0xFE84,0xFE86,0xFE88,0xFE8A,0xFE8E,0xFE90,0xFE94,0xFE96,0xFE9A,0xFE9E,0xFEA2,0xFEA6,0xFEAA,0xFEAC,0xFEAE,0xFEB0,0xFEB2,0xFEB6,0xFEBA,0xFEBE,0xFEC2,0xFEC6,0xFECA,0xFECE,0xFED2,0xFED6,0xFEDA,0xFEDE,0xFEE2,0xFEE6,0xFEEA,0xFEEE,0xFEF0,0xFEF2,0xFB57,0xFB7B,0xFB8B,0xFB8F,0xFB93,0xFBA5,0xFBFD};
int g_faInit[]={0,0,0,0,0,0xFE8B,0,0xFE91,0,0xFE97,0xFE9B,0xFE9F,0xFEA3,0xFEA7,0,0,0,0,0xFEB3,0xFEB7,0xFEBB,0xFEBF,0xFEC3,0xFEC7,0xFECB,0xFECF,0xFED3,0xFED7,0xFEDB,0xFEDF,0xFEE3,0xFEE7,0xFEEB,0,0,0xFEF3,0xFB58,0xFB7C,0,0xFB90,0xFB94,0,0xFBFE};
int g_faMedi[]={0,0,0,0,0,0xFE8C,0,0xFE92,0,0xFE98,0xFE9C,0xFEA0,0xFEA4,0xFEA8,0,0,0,0,0xFEB4,0xFEB8,0xFEBC,0xFEC0,0xFEC4,0xFEC8,0xFECC,0xFED0,0xFED4,0xFED8,0xFEDC,0xFEE0,0xFEE4,0xFEE8,0xFEEC,0,0,0xFEF4,0xFB59,0xFB7D,0,0xFB91,0xFB95,0,0xFBFF};

int FasIndex(ushort c)
{
   int n=ArraySize(g_faBase);
   for(int i=0;i<n;i++) if(g_faBase[i]==(int)c) return i;
   return -1;
}

// شکل‌دهی منطقی: هر حرف فارسی به شکل درست (منفصل/آغازی/میانی/پایانی) تبدیل می‌شود
string ShapePersianLogical(string s)
{
   int n=StringLen(s);
   string shaped="";
   for(int i=0;i<n;i++)
   {
      ushort c=StringGetCharacter(s,i);
      int idx=FasIndex(c);
      if(idx<0){ shaped+=ShortToString(c); continue; }

      int prevIdx=-1, nextIdx=-1;
      if(i>0)   prevIdx=FasIndex(StringGetCharacter(s,i-1));
      if(i+1<n) nextIdx=FasIndex(StringGetCharacter(s,i+1));
      // اتصال فقط وقتی مجاز است که حرف قبلی اتصال‌دهنده به راست
      // و حرف فعلی/بعدی اتصال‌دهنده به چپ باشد. شرط قبلی هر حرف بعدی
      // را متصل فرض می‌کرد و شکل حروف را خراب می‌کرد.
      bool prevConnects = (prevIdx>=0 && g_faInit[prevIdx]!=0 && g_faFina[idx]!=g_faIsol[idx]);
      bool nextConnects = (nextIdx>=0 && g_faInit[idx]!=0 && g_faFina[nextIdx]!=g_faIsol[nextIdx]);

      int form;
      if(prevConnects && nextConnects && g_faMedi[idx]!=0) form=g_faMedi[idx];
      else if(prevConnects && g_faFina[idx]!=0)            form=g_faFina[idx];
      else if(nextConnects && g_faInit[idx]!=0)            form=g_faInit[idx];
      else                                                  form=g_faIsol[idx];
      shaped+=ShortToString((ushort)form);
   }
   return shaped;
}

// ---- جهت هر کاراکتر: +1 راست‌به‌چپ، -1 چپ‌به‌راست (لاتین/رقم)، 0 بی‌طرف ----
int FaCharDir(ushort c)
{
   if(c>=0x06F0 && c<=0x06F9) return -1;   // ارقام فارسی
   if(c>=0x0660 && c<=0x0669) return -1;   // ارقام عربی-هندی
   if(IsPersianChar(c))       return 1;
   if((c>='0'&&c<='9')||(c>='A'&&c<='Z')||(c>='a'&&c<='z')) return -1;
   return 0;
}

// هنگام معکوس‌کردن یک run راست‌به‌چپ، جفت‌های براکت باید آینه شوند
ushort FaMirror(ushort c)
{
   if(c=='(') return (ushort)')';   if(c==')') return (ushort)'(';
   if(c=='[') return (ushort)']';   if(c==']') return (ushort)'[';
   if(c=='{') return (ushort)'}';   if(c=='}') return (ushort)'{';
   if(c=='<') return (ushort)'>';   if(c=='>') return (ushort)'<';
   return c;
}

//====================================================================
// ترتیب بصری برای رندرگر MT5
// از buildهای اخیر، رندرگر آبجکت‌های چارت bidi را انجام نمی‌دهد و متن
// راست‌به‌چپ را چپ‌به‌راست می‌کشد (گزارش رسمی انجمن MQL5). پس خودمان
// رشته را به «ترتیب بصری» تبدیل می‌کنیم تا یک رندرگر LTR عیناً همان
// تصویر درست را بکشد.
//   ورودی : متن منطقی (mode 1) یا متنِ شکل‌داده (mode 2)
//   الگوریتم: قاعدهٔ N1/N2 از UBA برای کاراکترهای بی‌طرف، سپس چیدن runها
//             از آخر به اول و معکوس‌کردن runهای راست‌به‌چپ + آینه‌کردن براکت.
//====================================================================
string VisualOrderForLtrEngine(string s)
{
   StringTrimRight(s);
   int n=StringLen(s);
   if(n==0) return s;

   int dir[]; ArrayResize(dir,n);
   bool anyRtl=false;
   for(int i=0;i<n;i++)
   {
      dir[i]=FaCharDir(StringGetCharacter(s,i));
      if(dir[i]>0) anyRtl=true;
   }
   if(!anyRtl) return s;              // خط تمام‌لاتین: دست‌نخورده بماند

   // کاراکترهای بی‌طرف جهت همسایه‌های هم‌جهت خود را می‌گیرند؛
   // در غیر این صورت جهت پایه (راست‌به‌چپ) را می‌گیرند.
   for(int i=0;i<n;i++)
   {
      if(dir[i]!=0) continue;
      int j=i;
      while(j<n && dir[j]==0) j++;
      int before=(i>0)?dir[i-1]:1;
      int after =(j<n)?dir[j]:1;
      int res=(before==after)?before:1;
      for(int k=i;k<j;k++) dir[k]=res;
      i=j;
   }

   string out="";
   int j=n-1;
   while(j>=0)
   {
      int d=dir[j];
      int start=j;
      while(start>=0 && dir[start]==d) start--;
      string run=StringSubstr(s,start+1,j-start);
      if(d>0)
      {
         string rev="";
         for(int k=0;k<StringLen(run);k++)
            rev=ShortToString(FaMirror(StringGetCharacter(run,k)))+rev;
         run=rev;
      }
      out+=run;
      j=start;
   }
   return out;
}

// آیا خط حداقل یک حرف فارسی دارد؟ فقط این خط‌ها نیاز به جهت RTL دارند.
bool HasPersianText(string s)
{
   for(int i=0;i<StringLen(s);i++)
      if(IsPersianChar(StringGetCharacter(s,i))) return true;
   return false;
}

// آماده‌سازی یک خط برای رندر روی چارت.
//   0 = متن خام منطقی (فقط برای عیب‌یابی روی buildی که bidi دارد)
//   1 = ترتیب بصری، بدون شکل‌دهی حروف
//   2 = شکل‌دهی حروف + ترتیب بصری   ← پیش‌فرض درست روی buildهای فعلی MT5
//   3 = پیچیدن در RLE..PDF (نسخهٔ قدیمی؛ روی buildهای جدید MT5 اثر ندارد)
string RenderLine(string text, int mode)
{
   if(mode==0)
   {
      // فاز ۴۱ — جهت پایهٔ خط را قطعی می‌کنیم. U+200F (RIGHT-TO-LEFT MARK)
      // یک کاراکتر «قوی» راست‌به‌چپ است و کنترل بومی جهت پایه را با قاعدهٔ
      // P2/P3 از همان اولین کاراکتر قوی می‌گیرد. اگر کنترل خودش همین را
      // انتخاب کرده بود، هیچ تغییری نمی‌دهد؛ اگر چپ‌به‌راست بود، ترتیب
      // واژه‌ها را درست می‌کند. خودش چاپ نمی‌شود (کاراکتر بی‌عرض).
      if(HasPersianText(text)) return ShortToString(0x200F)+text;
      return text;
   }
   if(mode==3)
   {
      if(HasPersianText(text)) return ShortToString(0x202B)+text+ShortToString(0x202C);
      return text;
   }
   if(!HasPersianText(text)) return text;
   string shaped=(mode==2) ? ShapePersianLogical(text) : text;
   return VisualOrderForLtrEngine(shaped);
}

void ExpAdd(string text, color clr)
{
   int n=ArraySize(g_expLines);
   ArrayResize(g_expLines,n+1);
   ArrayResize(g_expLineColors,n+1);
   // فاز ۴۱ — قاعدهٔ RTL (توضیح کامل در 25_Explain.mqh): هر واژهٔ لاتینی که
   // بعد از واژهٔ فارسی بیاید به ابتدای خط منتقل می‌شود تا جملهٔ فارسی به دو
   // قطعهٔ جابه‌جا شکسته نشود. ارقام دست‌نخورده می‌مانند (درون قطعهٔ RTL می‌مانند).
   g_expLines[n]=InpExplainLatinFirst? RtlSafe(text) : text;
   g_expLineColors[n]=clr;
}

// یک خط آماده: قاعدهٔ RTL اعمال می‌شود و اگر با این جابه‌جایی از پهنای پنل
// بلندتر شد، بلوک لاتین در خط خودش و متن فارسی در خط‌های بعدی می‌نشیند تا
// هیچ خطی از عرض EDIT بیرون نزند و بریده نشود.
void ExpEmitLine(string line, color clr, int maxChars)
{
   string outLine = InpExplainLatinFirst? RtlSafe(line) : line;
   int sepPos=StringFind(outLine," | ");
   if(sepPos>0 && StringLen(outLine)>maxChars)
   {
      ExpAdd(StringSubstr(outLine,0,sepPos), clr);
      ExpAdd(StringSubstr(outLine,sepPos+3), clr);
      return;
   }
   ExpAdd(outLine, clr);
}

// شکستن متن طولانی به خطوط کوتاه (تا در یک خط نریزد)
void ExpAddWrapped(string text, color clr)
{
   int maxChars = MathMax(24, InpExplainPanelWidth/8);
   string words[];
   int wc=StringSplit(text,' ',words);
   string line="";
   for(int i=0;i<wc;i++)
   {
      if(StringLen(words[i])==0) continue;
      string candidate = (StringLen(line)==0)? words[i] : line+" "+words[i];
      if(StringLen(candidate)>maxChars && StringLen(line)>0)
      {
         ExpEmitLine(line, clr, maxChars);
         line=words[i];
      }
      else line=candidate;
   }
   if(StringLen(line)>0) ExpEmitLine(line, clr, maxChars);
}

// ---------------- تبدیل زمان/قیمت به پیکسل با تابع دقیق MT5 ----------------
// ChartTimePriceToXY مقیاس عمودی، شیفت افقی، shift چارت و عرض محور قیمت را
// درست حساب می‌کند. تبدیل دستی قبلی این‌ها را نادیده می‌گرفت و در نتیجه موس
// خیلی وقت‌ها روی آبجکت موردنظر نمی‌افتاد.
bool ExplainTimePriceToXY(datetime t, double price, int &x, int &y)
{
   if(t<=0) return false;
   return ChartTimePriceToXY(0,0,t,price,x,y);
}

// برای خط افقی فقط Y لازم است: یک زمان داخل محدودهٔ دید می‌دهیم تا
// تبدیل قیمت به پیکسل درست انجام شود.
datetime ExplainVisibleTime()
{
   int firstBar=(int)ChartGetInteger(0,CHART_FIRST_VISIBLE_BAR,0);
   if(firstBar<0) firstBar=0;
   datetime t=iTime(_Symbol,PERIOD_CURRENT,firstBar);
   if(t<=0) t=iTime(_Symbol,PERIOD_CURRENT,0);
   if(t<=0) t=TimeCurrent();
   return t;
}

double DistToSegment(double px, double py, double x1, double y1, double x2, double y2)
{
   double dx=x2-x1, dy=y2-y1;
   double len2=dx*dx+dy*dy;
   if(len2<=0.0) return MathSqrt((px-x1)*(px-x1)+(py-y1)*(py-y1));
   double t=((px-x1)*dx+(py-y1)*dy)/len2;
   if(t<0) t=0;
   if(t>1) t=1;
   double cx=x1+t*dx, cy=y1+t*dy;
   return MathSqrt((px-cx)*(px-cx)+(py-cy)*(py-cy));
}

// ---------------------------------------------------------------------------
// فاز ۲۲ — علت دوم «هیچ آبجکتی توضیح نمی‌دهد» (ایراد واقعی hit-test):
// `ChartTimePriceToXY` وقتی برمی‌گرداند **false** که نقطه در محدودهٔ دید نباشد.
// ناحیه‌های FVG/OB/S-D از چند کندل قبل شروع می‌شوند و به سمت راست کشیده می‌شوند؛
// پس روی چارت زوم‌شده لبهٔ چپ تقریباً همیشه بیرون از دید است و شرط
// `if(ExplainTimePriceToXY(...) && ExplainTimePriceToXY(...))` هیچ‌وقت درست
// نمی‌شد → هیچ باکسی قابل hover نبود (در حالی که نصف باکس روی صفحه دیده می‌شود).
// دو helper زیر تبدیل را حتی بیرون از محدودهٔ دید ادامه می‌دهند:
//   ExplainTimeToX  — خطی بر مبنای پهنای واقعی هر کندل (px/bar) که از دو کندل دید به‌دست می‌آید
//   ExplainPriceToY — اگر قیمت بیرون دید باشد، Y به بالا/پایین کادر کلمپ می‌شود (نه شکست)
// ---------------------------------------------------------------------------
bool ExplainTimeToX(datetime t, int &x)
{
   x=0;
   if(t<=0) return false;
   int firstBar=(int)ChartGetInteger(0,CHART_FIRST_VISIBLE_BAR,0);
   if(firstBar<0) firstBar=0;
   double pRef=iClose(_Symbol,PERIOD_CURRENT,firstBar);
   if(pRef<=0.0) pRef=iClose(_Symbol,PERIOD_CURRENT,0);
   if(pRef<=0.0) return false;
   datetime tRef=iTime(_Symbol,PERIOD_CURRENT,firstBar);
   if(tRef<=0) return false;
   int xRef=0,yRef=0;
   if(!ChartTimePriceToXY(0,0,tRef,pRef,xRef,yRef)) return false;
   int sec=PeriodSeconds(PERIOD_CURRENT);
   if(sec<=0) return false;
   // پهنای هر کندل (پیکسل) از یک کندل دورتر در همان محدودهٔ دید
   int farShift=firstBar-8; if(farShift<0) farShift=0;
   datetime tFar=iTime(_Symbol,PERIOD_CURRENT,farShift);
   int xFar=0,yFar=0;
   if(tFar<=0 || tFar==tRef || !ChartTimePriceToXY(0,0,tFar,pRef,xFar,yFar))
   {
      // بدون مرجع دوم: فقط نقطهٔ دید را برمی‌گردانیم (رفتار قبلی)
      x=xRef;
      return (t==tRef);
   }
   double barsRef=(double)(tFar-tRef)/(double)sec;      // منفی: tFar جدیدتر است
   double pxPerBar=((double)xFar-(double)xRef)/barsRef; // مثبت
   double barsAhead=((double)t-(double)tRef)/(double)sec;
   x=xRef+(int)MathRound(pxPerBar*barsAhead);
   return true;
}

int ExplainPriceToY(datetime tRef, double price, double refPrice, int chartH)
{
   int x=0,y=0;
   if(price>0.0 && ChartTimePriceToXY(0,0,tRef,price,x,y)) return y;
   // بیرون از محدودهٔ دید: بالای کادر یا پایین آن کلمپ می‌شود تا هندسهٔ
   // ناحیه (و در نتیجه hit-test) از بین نرود.
   if(refPrice<=0.0) return (int)MathRound(chartH/2.0);
   return (price>refPrice)? -60 : chartH+60;
}

// نزدیک‌ترین آبجکت به موس (فقط آبجکت‌های لایهٔ تحلیل، نه داشبورد/پنل)
//
// فاز ۴۴ — قاعدهٔ قطعی انتخاب در هم‌پوشانی (قبلاً ترتیب ساخت آبجکت‌ها تعیین‌کننده
// بود، یعنی نتیجه به ترتیب تصادفی چرخش `ObjectsTotal` وابسته بود):
//   ۱) کم‌ترین فاصله تا موس؛
//   ۲) اگر فاصله‌ها در یک حد باشند، **کوچک‌ترین ناحیه** برنده است، چون خاص‌تر
//      است (گپ ریز داخل یک اردر بلاک بزرگ باید گپ را بگوید، نه بلاک را)؛
//   ۳) اگر ناحیه‌ها هم‌اندازه بودند، نام کوچک‌تر الفباتیکی برنده می‌شود تا
//      نتیجه حتی بین دو اجرا با ترتیب مختلف نیز یکسان بماند.
// همین قاعده در آزمون بدون‌موس فاز ۴۴ سنجیده می‌شود.
string HitTestExplainObject(int mx, int my)
{
   string best="";
   double bestDist=1e18;
   double bestArea=1e18;
   double tol=(double)InpExplainHoverTolPx;
   if(tol<4.0) tol=4.0;
   datetime tVis=ExplainVisibleTime();
   int chartH=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   double refPrice=(g_analysisClose>0.0)? g_analysisClose : iClose(_Symbol,PERIOD_CURRENT,0);
   int total=ObjectsTotal(0,-1,-1);
   for(int i=0;i<total;i++)
   {
      string nm=ObjectName(0,i,-1,-1);
      if(StringFind(nm,"ICTv13_")!=0) continue;
      if(StringFind(nm,"ICTv13_DASH_")==0) continue;
      if(StringFind(nm,"ICTv13_EXP_")==0)  continue;
      long otype=ObjectGetInteger(0,nm,OBJPROP_TYPE);
      int x1=0,y1=0,x2=0,y2=0;
      double dist=1e18;
      double area=0.0;   // فاز ۴۴: مساحت کادر پیکسلی، برای قاعدهٔ ۲ انتخاب قطعی
      if(otype==OBJ_HLINE)
      {
         double price=ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
         int yy=ExplainPriceToY(tVis,price,refPrice,chartH);
         if(price>0.0) dist=MathAbs((double)yy-(double)my);
      }
      else if(otype==OBJ_RECTANGLE)
      {
         double p0=ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
         double p1=ObjectGetDouble(0,nm,OBJPROP_PRICE,1);
         datetime t0=(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,0);
         datetime tt1=(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,1);
         if(ExplainTimeToX(t0,x1) && ExplainTimeToX(tt1,x2))
         {
            y1=ExplainPriceToY(tVis,p0,refPrice,chartH);
            y2=ExplainPriceToY(tVis,p1,refPrice,chartH);
            double yTop=MathMin((double)y1,(double)y2), yBot=MathMax((double)y1,(double)y2);
            double xL=MathMin((double)x1,(double)x2),   xR=MathMax((double)x1,(double)x2);
            area=(xR-xL)*MathMax(yBot-yTop,0.0);
            // فاز ۲۵ — ریشهٔ «پنل همه‌جا باز می‌شود»: ExplainPriceToY قیمتِ
            // بیرون از دید را به −۶۰ یا chartH+۶۰ کلمپ می‌کند. اگر **هر دو**
            // قیمت یک ناحیه بیرون از دید باشند (ناحیهٔ کاملاً بالای صفحه یا
            // پایین صفحه)، کلمپ جعبه را از −۶۰ تا chartH+۶۰ می‌کشید و در نتیجه
            // کل ارتفاع چارت «داخلِ ناحیه» حساب می‌شد → با هر حرکت موس پنل باز
            // می‌شد. حالا ناحیه‌ای که هیچ بخش دیدنی ندارد اصلاً کاندید نمی‌شود
            // (این با ناحیهٔ واقعاً بزرگ که بالا تا پایین دید را می‌پوشاند فرق
            // دارد؛ آن یکی درست است و همان‌طور می‌ماند).
            bool verticallyVisible=(yBot>=-tol && yTop<=(double)chartH+tol);
            if(verticallyVisible)
            {
               if(my>=yTop-tol && my<=yBot+tol && mx>=xL-tol && mx<=xR+tol)
                  dist=0.0;   // داخل ناحیه: اولویت با ناحیه است نه خطِ عبوری
               else
               {
                  double dx=MathMax(MathMax(xL-(double)mx,(double)mx-xR),0.0);
                  double dy=MathMax(MathMax(yTop-(double)my,(double)my-yBot),0.0);
                  dist=MathSqrt(dx*dx+dy*dy);
               }
            }
         }
      }
      else if(otype==OBJ_TREND)
      {
         double p0=ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
         double p1=ObjectGetDouble(0,nm,OBJPROP_PRICE,1);
         datetime t0=(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,0);
         datetime tt1=(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,1);
         if(ExplainTimeToX(t0,x1) && ExplainTimeToX(tt1,x2))
         {
            y1=ExplainPriceToY(tVis,p0,refPrice,chartH);
            y2=ExplainPriceToY(tVis,p1,refPrice,chartH);
            dist=DistToSegment((double)mx,(double)my,(double)x1,(double)y1,(double)x2,(double)y2);
         }
      }
      else if(otype==OBJ_TEXT)
      {
         double p0=ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
         datetime t0=(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,0);
         if(ExplainTimeToX(t0,x1))
         {
            y1=ExplainPriceToY(tVis,p0,refPrice,chartH);
            double dx=(double)x1-(double)mx;
            double dy=(double)y1-(double)my;
            dist=MathSqrt(dx*dx+dy*dy);
         }
      }
      // فاز ۲۵: شعاع پذیرش از ۴ برابر تحمل به ۲ برابر کم شد تا پنل با
      // حرکت عادی موس روی فضای خالی هم باز نشود (روی خط حدود ~۱۶px).
      // فاز ۴۴: انتخاب قطعی (فاصله ← مساحت ← نام)
      if(dist>tol*2.0) continue;
      bool better=false;
      if(dist<bestDist-0.5) better=true;
      else if(MathAbs(dist-bestDist)<=0.5)
      {
         if(area<bestArea-0.5) better=true;
         else if(MathAbs(area-bestArea)<=0.5 && (best=="" || nm<best)) better=true;
      }
      if(better){ bestDist=dist; bestArea=area; best=nm; }
   }
   return best;
}

// ---------------- lookup در Registryها ----------------
bool FindLiquidityById(long id, LiquidityObj &out)
{
   for(int i=0;i<ArraySize(g_liquidity);i++)
      if(g_liquidity[i].id==id){ out=g_liquidity[i]; return true; }
   return false;
}
bool FindFVGById(long id, FVGObj &out)
{
   for(int i=0;i<ArraySize(g_fvgs);i++)
      if(g_fvgs[i].id==id){ out=g_fvgs[i]; return true; }
   return false;
}
bool FindOBById(long id, OBObj &out)
{
   for(int i=0;i<ArraySize(g_obs);i++)
      if(g_obs[i].id==id){ out=g_obs[i]; return true; }
   return false;
}
bool FindRejectionById(long id, RejectionObj &out)
{
   for(int i=0;i<ArraySize(g_rejections);i++)
      if(g_rejections[i].id==id){ out=g_rejections[i]; return true; }
   return false;
}
bool FindEventById(long id, StructureEvent &out)
{
   for(int i=0;i<ArraySize(g_events);i++)
      if(g_events[i].id==id){ out=g_events[i]; return true; }
   return false;
}

string PriceS(double p) { return DoubleToString(p,_Digits); }

//====================================================================
// فاز ۴۲ — واژه‌نامهٔ فارسی برای مقادیر کدگذاری‌شده
//====================================================================
// چرا لازم است: خط‌های آموزشی با StringFormat ساخته می‌شوند و جای %s غالباً
// یک **کد لاتین** می‌نشیند (BULLISH، FRESH، WAITING_H4_BIAS، ...). همان واژهٔ
// لاتین است که جملهٔ فارسی را به دو قطعهٔ جابه‌جا می‌شکند و خواننده متن را
// وارونه می‌بیند. پس هر کدی که وسط جمله می‌آید باید معادل فارسی داشته باشد؛
// اگر خود کد لازم بود، در **ابتدای خط** یا در یک خط مستقل لاتین می‌آید.
string TfFa(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "یک‌دقیقه‌ای";
      case PERIOD_M2:  return "دو‌دقیقه‌ای";
      case PERIOD_M3:  return "سه‌دقیقه‌ای";
      case PERIOD_M4:  return "چهار‌دقیقه‌ای";
      case PERIOD_M5:  return "پنج‌دقیقه‌ای";
      case PERIOD_M6:  return "شش‌دقیقه‌ای";
      case PERIOD_M10: return "ده‌دقیقه‌ای";
      case PERIOD_M12: return "دوازده‌دقیقه‌ای";
      case PERIOD_M15: return "پانزده‌دقیقه‌ای";
      case PERIOD_M20: return "بیست‌دقیقه‌ای";
      case PERIOD_M30: return "سی‌دقیقه‌ای";
      case PERIOD_H1:  return "یک‌ساعته";
      case PERIOD_H2:  return "دو‌ساعته";
      case PERIOD_H3:  return "سه‌ساعته";
      case PERIOD_H4:  return "چهار‌ساعته";
      case PERIOD_H6:  return "شش‌ساعته";
      case PERIOD_H8:  return "هشت‌ساعته";
      case PERIOD_H12: return "دوازده‌ساعته";
      case PERIOD_D1:  return "روزانه";
      case PERIOD_W1:  return "هفتگی";
      case PERIOD_MN1: return "ماهانه";
   }
   return "تایم‌فریم جاری";
}

string DirFa(ENUM_DIRECTION d)
{
   if(d==DIR_BULL) return "صعودی";
   if(d==DIR_BEAR) return "نزولی";
   return "بی‌جهت";
}

string LiqTypeFa(ENUM_LIQ_TYPE t)
{
   switch(t)
   {
      case LIQ_PDH:        return "سقف روز قبل";
      case LIQ_PDL:        return "کف روز قبل";
      case LIQ_PWH:        return "سقف هفتهٔ قبل";
      case LIQ_PWL:        return "کف هفتهٔ قبل";
      case LIQ_EQH:        return "سقف‌های برابر";
      case LIQ_EQL:        return "کف‌های برابر";
      case LIQ_SESSION_H:  return "سقف پنجرهٔ سشن";
      case LIQ_SESSION_L:  return "کف پنجرهٔ سشن";
      case LIQ_RANGE_H:    return "سقف رنج";
      case LIQ_RANGE_L:    return "کف رنج";
      case LIQ_IPDA20_H:   return "سقف چرخهٔ بیست‌روزه";
      case LIQ_IPDA20_L:   return "کف چرخهٔ بیست‌روزه";
      case LIQ_IPDA40_H:   return "سقف چرخهٔ چهل‌روزه";
      case LIQ_IPDA40_L:   return "کف چرخهٔ چهل‌روزه";
      case LIQ_IPDA60_H:   return "سقف چرخهٔ شصت‌روزه";
      case LIQ_IPDA60_L:   return "کف چرخهٔ شصت‌روزه";
      case LIQ_TRENDLINE_H: return "نقدینگی مورب سقفی";
      case LIQ_TRENDLINE_L: return "نقدینگی مورب کفی";
   }
   return "سوئینگ تأییدشده";
}

string ObStateFa(ENUM_OB_STATE s)
{
   if(s==OB_VALID)      return "معتبر و دست‌نخورده";
   if(s==OB_MITIGATED)  return "لمس شده (تازگی از دست رفته)";
   if(s==OB_BROKEN)     return "شکسته‌شده";
   if(s==OB_BREAKER)    return "تبدیل به بلوک شکننده";
   if(s==OB_MITIGATION) return "تبدیل به بلوک تخفیف";
   return "بی‌اعتبار";
}

string RejectionStateFa(ENUM_REJECTION_STATE s)
{
   if(s==REJECTION_FRESH)   return "تازه و دست‌نخورده";
   if(s==REJECTION_TOUCHED) return "لمس شده";
   return "بی‌اعتبار";
}

string ExhaustionStateFa(ENUM_EXHAUSTION_STATE s)
{
   switch(s)
   {
      case EXH_TRENDING:                  return "روند سالم و ادامه‌دار";
      case EXH_EXTENDING:                 return "روند در حال کشش";
      case EXH_WATCH:                     return "زیر نظر برای فرسودگی";
      case EXH_MICRO_PULLBACK:            return "پول‌بک ریز";
      case EXH_MICRO_REVERSAL_CONFIRMED:  return "برگشت ریز تأییدشده";
      case EXH_RANGE_TRANSITION:          return "گذار به رنج";
      case EXH_REVERSAL_CONFIRMED:        return "برگشت تأییدشده";
   }
   return "بی‌طرف";
}

string TrendPhaseFa(ENUM_TREND_PHASE p)
{
   switch(p)
   {
      case PHASE_INITIATION:   return "آغاز حرکت";
      case PHASE_EXPANSION:    return "انبساط";
      case PHASE_DISTRIBUTION: return "توزیع";
      case PHASE_REVERSAL:     return "برگشت";
   }
   return "نامعلوم";
}

string PoiKindFa(ENUM_POI_KIND k)
{
   switch(k)
   {
      case POIK_FVG:       return "گپ قیمتی";
      case POIK_OB:        return "اردر بلاک";
      case POIK_BREAKER:   return "بلوک شکننده";
      case POIK_MITIGATION:return "بلوک تخفیف";
      case POIK_REJECTION: return "بلوک پس‌زدگی";
      case POIK_TRENDLINE: return "نقدینگی مورب";
      case POIK_RANGE:     return "مرز رنج";
   }
   return "بدون نوع";
}

string EntryModelFa(ENUM_ENTRY_MODEL m)
{
   switch(m)
   {
      case MODEL_ICT2022:     return "مدل کلاسیک: جارو، سپس تغییر ساختار، سپس ورود روی گپ";
      case MODEL_BOS_FVG_OB:  return "مدل شکست ساختار، سپس گپ، سپس اردر بلاک";
      case MODEL_SWEEP_ENTRY: return "مدل ورود روی جاروی نقدینگی";
      case MODEL_OTE_ONLY:    return "مدل ورود فقط در باند بهینهٔ فیبوناچی";
   }
   return "مدل ورودی انتخاب نشده";
}

string RTMEventFa(ENUM_RTM_EVENT e)
{
   switch(e)
   {
      case RTM_COMPRESSION: return "فشردگی (ذخیرهٔ انرژی)";
      case RTM_EXPANSION:   return "انبساط (آزادسازی انرژی)";
      case RTM_TRAP:        return "تلهٔ ورود (شکار استاپ)";
      case RTM_MOMENTUM:    return "کندل ممنتوم";
      case RTM_ENGULF:      return "پوشش بدنهٔ کندل قبلی";
      case RTM_REJECTION:   return "پس‌زدگی از سطح";
   }
   return "رویداد رفتاری";
}

string AMTDayTypeFa(uint t)
{
   switch(t)
   {
      case 1: return "روز روندی";
      case 2: return "نوسان طبیعی روزانه";
      case 3: return "روز معمول";
      case 4: return "روز خنثی (هر دو طرف ارزش اولیه شکسته)";
      case 5: return "روز بی‌روند (ارزش اولیه حفظ شده)";
   }
   return "نامعلوم";
}

string AMTOpenTypeFa(uint t)
{
   switch(t)
   {
      case 1: return "باز شدن رانشی بیرون رنج روز قبل";
      case 2: return "آزمون ارزش اولیه و سپس حرکت";
      case 3: return "رد ارزش اولیه و بازگشت";
      case 4: return "باز شدن درون ارزش";
   }
   return "نامعلوم";
}

string SDKindFa(ENUM_SD_KIND k)
{
   switch(k)
   {
      case SDK_RBR:    return "رالی، پایه، رالی";
      case SDK_DBD:    return "ریزش، پایه، ریزش";
      case SDK_RBD:    return "رالی، پایه، ریزش";
      case SDK_DBR:    return "ریزش، پایه، رالی";
      case SDK_SUPPLY: return "ناحیهٔ عرضهٔ ساده";
   }
   return "ناحیهٔ تقاضای ساده";
}

string WyckoffEventFa(ENUM_WYCK_EVENT e)
{
   switch(e)
   {
      case WE_SC:         return "اوج فروش (تسلیم فروشندگان)";
      case WE_BC:         return "اوج خرید (هیجان خریداران)";
      case WE_AR:         return "رالی خودکار (واکنش نخست)";
      case WE_ST:         return "آزمون دوم محدوده";
      case WE_SPRING:     return "اسپرینگ (شکار استاپ کف رنج)";
      case WE_UPTHRUST:   return "آپ‌تراست (شکار استاپ سقف رنج)";
      case WE_SOS:        return "نشانهٔ قدرت";
      case WE_SOW:        return "نشانهٔ ضعف";
      case WE_LPS:        return "آخرین نقطهٔ حمایت";
      case WE_LPSY:       return "آخرین نقطهٔ عرضه";
      case WE_TEST:       return "آزمون کم‌دامنهٔ مرز";
      case WE_ABSORPTION: return "جذب سفارش در مرز رنج";
      case WE_PS:         return "حمایت مقدماتی";
      case WE_PSY:        return "عرضهٔ مقدماتی";
   }
   return "رویداد وایکاف";
}

string QTPhaseFa(ENUM_QT_PHASE p)
{
   switch(p)
   {
      case QT_Q1_ACCUM:    return "ربع نخست: انباشت (۱۸:۰۰ تا ۰۰:۰۰ نیویورک)";
      case QT_Q2_MANIP:    return "ربع دوم: دستکاری (۰۰:۰۰ تا ۰۶:۰۰ نیویورک)";
      case QT_Q3_DISTRIB:  return "ربع سوم: توزیع (۰۶:۰۰ تا ۱۲:۰۰ نیویورک)";
      case QT_Q4_REVERSAL: return "ربع چهارم: ادامه یا برگشت (۱۲:۰۰ تا ۱۸:۰۰ نیویورک)";
   }
   return "ربع نامعلوم";
}

// کد کوتاه لاتین سطح نقدینگی — فقط برای **عنوان پنل** و ابتدای خط، جایی که
// واژهٔ لاتین به عنوان لنگر دوزبانه می‌آید و وسط جملهٔ فارسی نمی‌افتد.
string LiqTypeCode(ENUM_LIQ_TYPE t)
{
   switch(t)
   {
      case LIQ_PDH:        return "PDH";
      case LIQ_PDL:        return "PDL";
      case LIQ_PWH:        return "PWH";
      case LIQ_PWL:        return "PWL";
      case LIQ_EQH:        return "EQH";
      case LIQ_EQL:        return "EQL";
      case LIQ_SWING_H:    return "SWING-H";
      case LIQ_SWING_L:    return "SWING-L";
      case LIQ_SESSION_H:  return "SESSION-H";
      case LIQ_SESSION_L:  return "SESSION-L";
      case LIQ_RANGE_H:    return "RANGE-H";
      case LIQ_RANGE_L:    return "RANGE-L";
      case LIQ_IPDA20_H:   return "IPDA20-H";
      case LIQ_IPDA20_L:   return "IPDA20-L";
      case LIQ_IPDA40_H:   return "IPDA40-H";
      case LIQ_IPDA40_L:   return "IPDA40-L";
      case LIQ_IPDA60_H:   return "IPDA60-H";
      case LIQ_IPDA60_L:   return "IPDA60-L";
      case LIQ_TRENDLINE_H: return "TRENDLINE-H";
      case LIQ_TRENDLINE_L: return "TRENDLINE-L";
   }
   return "LIQ";
}

string ObKindFa(ENUM_OB_KIND k)
{
   switch(k)
   {
      case OBK_CORE:             return "هسته‌ای (هم‌زمان با گپ و جارو)";
      case OBK_STANDALONE:       return "تنها (بدون هم‌پوشانی با گپ)";
      case OBK_EXTREME:          return "اکستریم (روی مبدأ دامنهٔ معامله‌گری)";
      case OBK_MITIGATION_BLOCK: return "بلوک تخفیف";
   }
   return "نامشخص";
}

string WyckoffEventCode(ENUM_WYCK_EVENT e)
{
   switch(e)
   {
      case WE_SC:         return "SC";
      case WE_BC:         return "BC";
      case WE_AR:         return "AR";
      case WE_ST:         return "ST";
      case WE_SPRING:     return "SPRING";
      case WE_UPTHRUST:   return "UPTHRUST";
      case WE_SOS:        return "SOS";
      case WE_SOW:        return "SOW";
      case WE_LPS:        return "LPS";
      case WE_LPSY:       return "LPSY";
      case WE_TEST:       return "TEST";
      case WE_ABSORPTION: return "ABSORPTION";
      case WE_PS:         return "PS";
      case WE_PSY:        return "PSY";
   }
   return "EVENT";
}

string RTMEventCode(ENUM_RTM_EVENT e)
{
   switch(e)
   {
      case RTM_COMPRESSION: return "COMPRESSION";
      case RTM_EXPANSION:   return "EXPANSION";
      case RTM_TRAP:        return "TRAP";
      case RTM_MOMENTUM:    return "MOMENTUM";
      case RTM_ENGULF:      return "ENGULFING";
      case RTM_REJECTION:   return "REJECTION";
   }
   return "EVENT";
}

// کد وضعیت موتور ستاپ → یک جملهٔ فارسی کوتاه. متن پنل به‌جای چاپ خودِ کد
// (که لاتین است و جمله را می‌شکند) همین جمله را نشان می‌دهد و کد را در یک خط
// مستقل لاتین می‌آورد.
string SetupStatusFa(string code)
{
   if(code=="NONE")                    return "موتور هنوز ارزیابی نکرده است";
   if(code=="READY")                   return "ستاپ کامل و آماده است";
   if(code=="SETUP_ENGINE_DISABLED")   return "موتور ستاپ با ورودی مربوطه خاموش است";
   if(code=="WAITING_H4_BIAS")         return "بایاس تایم‌فریم مالک هنوز تأیید نشده است";
   if(code=="WAITING_DOL")             return "هدف نقدینگی هم‌جهت با فاصلهٔ کافی پیدا نشد";
   if(code=="WAITING_MTF_CONFLICT")    return "تضاد بین تایم‌فریم‌ها فعال است";
   if(code=="WAITING_H1_CONTEXT")      return "کانتکست یک‌ساعته هم‌جهت نیست";
   if(code=="WAITING_M15_CONTEXT")     return "کانتکست پانزده‌دقیقه‌ای هم‌جهت نیست";
   if(code=="WAITING_M5_SETUP")        return "ستاپ پنج‌دقیقه‌ای هم‌جهت نیست";
   if(code=="WAITING_M2_CONFIRMATION") return "تأیید اجرایی دودقیقه‌ای نرسیده است";
   if(code=="WAITING_M1_CONFIRMATION") return "تأیید اجرایی یک‌دقیقه‌ای نرسیده است";
   if(code=="WAITING_ICT_CYCLE")       return "هیچ چرخهٔ اثبات‌شده‌ای در جهت بایاس نیست";
   if(code=="WAITING_PROVEN_SWEEP_MSS")return "چرخه هست ولی جارو و جابه‌جایی کامل نیست";
   if(code=="WAITING_FRESH_CYCLE")     return "چرخه قدیمی‌تر از پنجرهٔ مجاز است";
   if(code=="WAITING_DEALING_LEG")     return "دامنهٔ معامله‌گری معتبر نیست";
   if(code=="WAITING_LEG_DIRECTION")   return "آخرین دامنه مخالف بایاس است";
   if(code=="WAITING_RETRACE")         return "قیمت به ناحیهٔ ورود برنگشته است";
   if(code=="WAITING_DISCOUNT_OTE")    return "ناحیهٔ ورود در باند بهینهٔ نیمهٔ تخفیف نیست";
   if(code=="WAITING_PREMIUM_OTE")     return "ناحیهٔ ورود در باند بهینهٔ نیمهٔ گران نیست";
   if(code=="WAITING_ZONE_GEOMETRY")   return "هندسهٔ ناحیهٔ ورود نامعتبر است";
   if(code=="WAITING_SL_INVALID")      return "فاصلهٔ ورود تا حد ضرر صفر یا منفی می‌شد";
   if(code=="WAITING_DOL_DIRECTION")   return "هدف نقدینگی در جهت معامله نیست";
   if(code=="WAITING_RR_LOW")          return "نسبت سود به ریسک از حداقل کمتر است";
   if(StringFind(code,"WAITING_ENTRY_MODEL")==0) return "هیچ مدل ورودی شرط‌هایش را کامل نکرد";
   if(StringFind(code,"WAITING_QUALITY_LOW")==0) return "امتیاز کیفیت از حداقل کمتر است";
   return "دلیل نامشخص — کد فنی در خط بعدی آمده است";
}

// دلیل رد دامنهٔ معامل‌گری → فارسی
string LegRejectFa(string code)
{
   if(code=="H4_DATA_NOT_READY")            return "دادهٔ کافی تایم‌فریم مالک برای پیوت‌یابی آماده نیست";
   if(code=="NOT_ENOUGH_ALTERNATING_PIVOTS")return "سقف و کف تأییدشدهٔ متناوب کافی پیدا نشد";
   if(code=="ZERO_RANGE")                   return "دامنهٔ دامنهٔ معامله‌گری صفر است";
   if(code=="LEG_TOO_SMALL")                return "اندازهٔ دامنه از حداقل نسبت به میانگین دامنه کمتر است";
   return "دلیل نامشخص — کد فنی در خط بعدی آمده است";
}

// ---------------- تولید توضیح برای هر نوع آبجکت ----------------
void ExplainLiquidity(const LiquidityObj &l)
{
   bool highSide=IsHighSideLiquidity(l.type);
   g_expTitle="LIQ "+LiqTypeCode(l.type)+" #"+IdToStr(l.id);
   ExpAddWrapped(StringFormat("چیست: سطح نقدینگی %s در قیمت %s — نوع سطح: %s",
                 highSide?"سمت خرید (بالای قیمت)":"سمت فروش (زیر قیمت)",
                 PriceS(l.price), LiqTypeFa(l.type)), clrWhite);
   ExpAdd(StringFormat("جایگاه در سلسله‌مراتب: %s",
          l.scope==SCOPE_EXTERNAL?"خارجی — روی مبدأ دامنهٔ معامله‌گری":"داخلی — درون دامنهٔ معامله‌گری"), clrAqua);
   ExpAdd(StringFormat("تایم‌فریم منبع: %s", TfFa(l.isHTF?InpHTF:PERIOD_CURRENT)), clrAqua);

   if(l.type==LIQ_PDH||l.type==LIQ_PDL||l.type==LIQ_PWH||l.type==LIQ_PWL)
      ExpAddWrapped(StringFormat("چرا تشکیل شد: سقف یا کف دورهٔ قبلی که پیش از %s بسته شده بود — نقدینگی طبیعی بازار",
                    TimeToString(l.time,TIME_DATE|TIME_MINUTES)), clrAqua);
   else if(l.type==LIQ_EQH||l.type==LIQ_EQL)
   {
      ExpAddWrapped(StringFormat("چرا تشکیل شد: دو یا چند سویینگ تأییدشده با فاصلهٔ کمتر از تلورانس تنظیم‌شده (%.0f پوینت یا %.2f برابر میانگین دامنه) و یک پس‌رفت جداکننده بین‌شان — استخر نقدینگی",
                    InpEQ_Tolerance_Points, InpEQ_ToleranceATR), clrAqua);
      ExpAddWrapped("شرط جدایی: دو عضو باید یک سویینگ مخالف در میانه داشته باشند تا «دو تست مستقل» باشند، نه «یک سقف کشیده»", clrSilver);
      ExpAddWrapped(StringFormat("حداقل عمق جدایی برابر تلورانس است و با مقدار %.2f سخت‌تر می‌شود", InpEQ_MinSeparationATR), clrSilver);
      ExpAdd("InpEQ_MinSeparationATR — آستانهٔ سخت‌گیری عمق جدایی", clrSilver);
   }
   else if(l.type==LIQ_SESSION_H||l.type==LIQ_SESSION_L)
      ExpAddWrapped(StringFormat("چرا تشکیل شد: رنج یک پنجرهٔ سشن بسته‌شدهٔ قبلی در %s به‌عنوان هدف نقدینگی ثبت شد",
                    TimeToString(l.time,TIME_DATE|TIME_MINUTES)), clrAqua);
   else
      ExpAddWrapped("چرا تشکیل شد: یک سویینگ تأییدشده (پیوت با تأیید کندل‌های دو طرف) که به‌عنوان نقدینگی ثبت شده است", clrAqua);

   ExpAdd("وضعیت سطح: "+(l.state==LSTATE_FRESH?"دست‌نخورده":
          (l.state==LSTATE_SWEPT?"جارو شده در "+TimeToString(l.sweptTime,TIME_DATE|TIME_MINUTES)
                               :"بی‌اعتبار — قیمت با بسته‌شدن از سطح عبور کرد")),
          l.state==LSTATE_FRESH?clrLime:(l.state==LSTATE_SWEPT?clrOrange:clrDimGray));

   ExpAddWrapped("شکست واقعی: اگر کندل کامل بالای یا زیر این سطح ببندد، سطح از حالت نقدینگی خارج و به مرز ساختاری تبدیل می‌شود و شکست ساختار در همان جهت ثبت می‌شود", clrLime);
   ExpAddWrapped("جارو (فیک): اگر فقط فتیله از سطح بگذرد و کندل دوباره پشت آن ببندد، این برداشت نقدینگی است نه شکست، و زمینهٔ حرکت مخالف می‌شود", clrOrange);
   ExpAddWrapped("چه چیزی آن را باطل می‌کند: بسته‌شدن کندل از سمت مخالف سطح (سطح دیگر هدف معتبر نیست)؛ یا تغییر بایاس مالک", clrTomato);
   ExpAddWrapped(StringFormat("کنترل خودت: کندل %s را روی تایم‌فریم %s باز کن؛ باید در آن محدوده دو سویینگ تقریباً هم‌سطح ببینی؛ قیمت سطح %s",
                 TimeToString(l.time,TIME_DATE|TIME_MINUTES), TfFa(PERIOD_CURRENT), PriceS(l.price)), clrSilver);
   ExpAdd("LIQ #"+IdToStr(l.id)+" — ICT_Assistant_Canonical_Explain.csv", clrSilver);
}

void ExplainStructureEvent(const StructureEvent &e)
{
   g_expTitle="EVENT "+EventTypeToStr(e.type)+" #"+IdToStr(e.id)+" "+(e.direction==DIR_BULL?"BULLISH":"BEARISH");
   ExpAddWrapped(StringFormat("چیست: %s روی تایم‌فریم %s؛ کندل تأیید: %s؛ قیمت سطح شکسته‌شده: %s",
                 (e.type==EVT_MSS?"تغییر ساختار تأییدشده":(e.type==EVT_CHOCH?"تغییر جهت احتمالی":"ادامهٔ روند")),
                 TfFa(e.isHTF?InpHTF:PERIOD_CURRENT), TimeToString(e.time,TIME_DATE|TIME_MINUTES), PriceS(e.price)), clrWhite);
   ExpAddWrapped("چرا تشکیل شد: کندل بسته‌شده سطح سویینگ محافظت‌شدهٔ مقابل را رد کرد و یک جابه‌جایی زنجیرشده با آن ثبت شد", clrAqua);
   ExpAdd("Swing #"+IdToStr(e.brokenSwingId)+" | Protected #"+IdToStr(e.protectedSwingId)
          +" | Displacement #"+IdToStr(e.displacementId)+" | Sweep #"+IdToStr(e.sweepId), clrSilver);

   if(e.type==EVT_MSS)
      ExpAddWrapped("معنی: تغییر ساختار با شاهد کامل — جارو، جابه‌جایی و بسته‌شدن فراتر از سطح؛ معتبرترین حالت برای شروع ستاپ", clrLime);
   else if(e.type==EVT_CHOCH)
      ExpAddWrapped("هشدار: فقط جهت شکسته شده ولی جابه‌جایی کافی ثبت نشده؛ این هنوز یک کاندید است و به‌تنهایی ستاپ نمی‌سازد", clrOrange);
   else
      ExpAddWrapped("معنی: ادامهٔ روند فعلی — شکست در جهت روند، نه تغییر روند", clrAqua);

   ExpAddWrapped(StringFormat("شرط عددی جابه‌جایی: نسبت بدنه به دامنه باید %.2f و بیشتر و نسبت دامنه به میانگین دامنه %.2f و بیشتر باشد؛ در غیر این صورت ارتقا به تغییر ساختار تأییدشده انجام نمی‌شود",
                 InpDisp_BodyRatio, InpDisp_RangeVsAvg), clrSilver);
   ExpAdd("InpDisp_BodyRatio / InpDisp_RangeVsAvg — آستانهٔ جابه‌جایی", clrSilver);
   ExpAddWrapped("چه چیزی آن را باطل می‌کند: بسته‌شدن کندل از سطح محافظت‌شدهٔ مقابل؛ یا ساخته‌شدن یک تغییر ساختار مخالف بعدی", clrTomato);
   ExpAddWrapped(StringFormat("کنترل خودت: روی کندل %s وایسا؛ اگر کندل کامل بالای %s بسته شده شکست درست ثبت شده و اگر فقط فتیله بوده ثبت اشتباه است",
                 TimeToString(e.time,TIME_DATE|TIME_MINUTES), PriceS(e.price)), clrSilver);
   ExpAdd("ICT_Assistant_V13_Events_v1.csv — رویداد شمارهٔ "+IdToStr(e.id), clrSilver);
}

// فاز ۲۸: نام دقیق هر نوع گپ. قبل از این، همه‌چیز «FVG» نامیده می‌شد و در نتیجه
// پنل آموزشی هم تعریف غلط می‌داد (مثلاً برای Implied همان تعریف Standard).
string FVGKindToStr(ENUM_FVG_KIND k)
{
   // فاز ۴۱: این نام‌ها فقط در **عنوان** پنل می‌آیند و باید لاتین و خالص
   // باشند؛ عنوانی که فارسی وسطش بیاید، به دو قطعهٔ جابه‌جا می‌شکند. متن
   // آموزشی فارسی در FVGKindFa() است.
   if(k==FVGK_IMPLIED)       return "IMPLIED";
   if(k==FVGK_MICRO)         return "MICRO";
   if(k==FVGK_VOL_IMBALANCE) return "VOLUME IMBALANCE";
   return "STANDARD";
}
// همان نام‌ها به فارسی، برای خط‌های آموزشی بدنه (بدون واژهٔ لاتین وسط جمله).
string FVGKindFa(ENUM_FVG_KIND k)
{
   if(k==FVGK_IMPLIED)       return "گپ ضمنی (از میانهٔ فتیله‌ها کشیده شده)";
   if(k==FVGK_MICRO)         return "گپ ریز روی تایم‌فریم پایین‌تر";
   if(k==FVGK_VOL_IMBALANCE) return "گپ بین بدنه‌ها با فتیله‌های روی‌هم‌افتاده";
   return "گپ استاندارد سه‌کندلی";
}
// فاز ۳۶: نام‌گذاری ICT — BISI (Buy-side Imbalance / Sell-side Inefficiency) =
// FVG صعودی · SIBI (Sell-side Imbalance / Buy-side Inefficiency) = FVG نزولی.
// منبع: innercircletrader.net — «ICT SIBI and BISI Explained»؛ اسم جهت‌دار است،
// نه محاسبهٔ جدا: همان گپ سه‌کندلی با دو نام تجاری.
string FVGBisiSibiStr(ENUM_DIRECTION d)
{
   return (d==DIR_BULL)? "BISI (Buy-side Imbalance / Sell-side Inefficiency)"
                       : "SIBI (Sell-side Imbalance / Buy-side Inefficiency)";
}
// وضعیت چرخهٔ عمر گپ، به فارسی — قبلاً برچسب‌های FRESH/MITIGATED/iFVG وسط
// جملهٔ فارسی می‌افتادند و متن را ناخوانا می‌کردند (فاز ۴۱).
string FVGStateFa(const FVGObj &f)
{
   if(f.invalidated) return "بی‌اعتبار / منقضی";
   if(f.inverted)    return "پولاریتی برعکس (به گپ معکوس تبدیل شده)";
   if(f.ceTouched)   return "میانهٔ ناحیه لمس شده (به‌قدر کافی پر شده)";
   if(f.mitigated)   return "فقط لبهٔ ناحیه لمس شده";
   return "تازه و دست‌نخورده";
}

// فاز ۴۳ — یک رشتهٔ واحد برای «جهت + نقش» گپ، تا پنل، ردیف CSV و آزمون رفتاری
// نتوانند سه چیز متفاوت بگویند. قاعده: جهت تولد اول نوشته می‌شود و اگر وارونه
// شده باشد، نقش فعلی بعدش می‌آید؛ پس خواننده هیچ‌وقت جهت و وضعیت را قاطی نمی‌کند.
string FVGPolarityReport(const FVGObj &f)
{
   string birth=(f.direction==DIR_BULL? "BULLISH":"BEARISH");
   if(!f.inverted) return birth;
   return birth+" -> "+DirToStr(FVGActiveDir(f))+" (iFVG)";
}

void ExplainFVG(const FVGObj &f)
{
   g_expTitle="ZONE "+FVGKindToStr(f.kind)+" #"+IdToStr(f.id)+" "+FVGPolarityReport(f);
   // فاز ۴۱ — بازنویسی متن آموزشی: هر خط یا تمام‌لاتین است، یا لاتینش اول
   // جمله آمده و بقیه یکپارچه فارسی. دیگر هیچ واژهٔ انگلیسی وسط جملهٔ فارسی
   // نمی‌افتد (ریشهٔ «فارسی به‌هم‌ریخته»). ارقام وسط جمله مشکلی ندارند.
   ExpAdd(FVGBisiSibiStr(f.direction)+" — نام دوم همین گپ در این مکتب", clrAqua);   // فاز ۳۶
   ExpAddWrapped("چیست: ناحیهٔ عدم‌تعادل قیمت — جایی که یک طرف بازار سفارش بیشتری خورده و قیمت با سرعت از آن گذشته؛ نوع این گپ: "+FVGKindFa(f.kind), clrWhite);
   ExpAddWrapped(StringFormat("مرزهای ناحیه: از %.2f تا %.2f ؛ میانهٔ ناحیه (سطح تصمیم): %.2f ؛ زمان تشکیل: %s",
                 f.bottom,f.top,f.ce,TimeToString(f.time,TIME_DATE|TIME_MINUTES)), clrWhite);
   ExpAdd("شناسهٔ کندل جابه‌جایی سازنده: "+IdToStr(f.displacementId), clrSilver);
   // تعریف هر نوع، جداگانه — منبع: LuxAlgo Library (Fair Value Gap / Implied FVG / Consequent Encroachment).
   if(f.kind==FVGK_STANDARD)
      ExpAddWrapped("چطور ساخته شد: فتیلهٔ کندل اول و سوم هم‌پوشانی ندارند و همین شکاف، ناحیهٔ گپ است — کندل میانی همان کندل جابه‌جایی است", clrAqua);
   else if(f.kind==FVGK_IMPLIED)
      ExpAddWrapped("چطور ساخته شد: گپ واقعی چاپ نشده؛ ناحیه از میانهٔ فتیلهٔ کندل اول تا میانهٔ فتیلهٔ کندل سوم کشیده شده و فتیله‌ها روی هم می‌افتند", clrAqua);
   else if(f.kind==FVGK_VOL_IMBALANCE)
      ExpAddWrapped("چطور ساخته شد: شکاف بین بدنهٔ کندل اول و سوم، در حالی که فتیله‌ها روی هم می‌افتند؛ شاهدش ضعیف‌تر از گپ واقعی است", clrAqua);
   else
   {
      ExpAdd(EnumToString(f.tf)+" — تایم‌فریم منبع این گپ", clrAqua);
      ExpAddWrapped("چطور ساخته شد: گپ ریزی که روی تایم‌فریم پایین‌تر شکل گرفته و به این چارت منتقل شده", clrAqua);
   }
   ExpAdd("پشتوانهٔ ساختاری: "+(f.causal? "دارد — کندل جابه‌جایی سازنده به یک شکست ساختار زنجیر شده"
                                         : "ندارد — کندل جابه‌جایی هنوز به شکست ساختار زنجیر نشده"),
          f.causal?clrAqua:clrOrange);
   ExpAdd("وضعیت ناحیه: "+FVGStateFa(f),
          f.invalidated?clrDimGray:(f.inverted?clrMediumOrchid:((f.ceTouched||f.mitigated)?clrGoldenrod:clrLime)));
   // فاز ۴۳: نقش فعلی در متن هم صریح گفته می‌شود، وگرنه کاربر مربعی می‌بیند که
   // رنگش با جهت تولد نمی‌خواند و مجبور است حدس بزند کدام حرف درست است.
   if(f.inverted)
   {
      ExpAddWrapped("نقش فعلی: این گپ وارونه شده و از این به بعد در جهت مخالف تولدش خوانده می‌شود", clrMediumOrchid);
      string invAt=(f.invertedTime>0)? TimeToString(f.invertedTime,TIME_DATE|TIME_MINUTES) : "ثبت نشده";
      ExpAdd("زمان وارونگی: "+invAt+" ؛ جهت تولد گپ: "+(f.direction==DIR_BULL? "صعودی":"نزولی"), clrSilver);
      ExpAddWrapped("ورود هم‌جهت با گپ اولیه روی این ناحیه معتبر نیست؛ سطح را با نقش امروزش بسنج، نه با جهتی که ساخته شد", clrOrange);
   }
   // فاز ۲۸ — تفکیک لمس لبه از رسیدن به میانهٔ ناحیه (منبع: LuxAlgo — Consequent Encroachment).
   ExpAddWrapped((f.mitigated && !f.ceTouched)
                 ? "نکتهٔ مهم: تا این لحظه فقط لبهٔ ناحیه لمس شده و خط تصمیم، میانهٔ آن است؛ پس «پر شده» حساب نمی‌شود"
                 : (f.ceTouched
                    ? "نکتهٔ مهم: قیمت به میانهٔ ناحیه رسیده و بیشتر مدل‌ها همین را «به‌قدر کافی پر شده» می‌دانند"
                    : "هنوز هیچ لمسی ثبت نشده؛ ناحیه دست‌نخورده است"), clrSilver);
   ExpAdd("InpMinFVG_ATR — فیلتر اهمیت اعمال‌شده روی این چارت", clrSilver);
   ExpAddWrapped(StringFormat("حداقل ارتفاع مجاز گپ: %.2f برابر میانگین دامنهٔ کندل‌ها؛ میانگین دامنهٔ همین تحلیل: %.2f — گپ‌های ریزتر از چارت حذف شده‌اند",
                 InpMinFVG_ATR, g_analysisATR), clrSilver);
   ExpAddWrapped("استفادهٔ درست: ورود روی پول‌بک به داخل ناحیه و در جهت بایاس مالک؛ دقیق‌ترین ورود روی میانهٔ ناحیه است و اگر با ناحیهٔ اردر بلاک و باند ورود بهینه هم‌پوشانی داشته باشد، قوی‌تر می‌شود", clrLime);
   ExpAddWrapped("لمس معتبر: لمس شدن ناحیه در همان کندل شکل‌گیری حساب نمی‌شود و پرشدن جزئی فقط از کندل بعد ثبت می‌شود (مرز گپ همیشه با کندل سوم لمس می‌شود)", clrSilver);
   ExpAddWrapped("فیک / بی‌اعتبار: اگر کندلی کامل از سمت مخالف ناحیه بسته شود، گپ به گپ معکوس تبدیل می‌شود و از آن به بعد ناحیهٔ ورود هم‌جهت نیست", clrOrange);
   ExpAddWrapped("قاعدهٔ یکسان‌سازی: جهت نوشته‌شده در این پنل، رنگ مربع روی چارت، ستون نقش در فایل تشخیصی و ناحیهٔ انتخابی ستاپ، همه از یک محاسبه می‌آیند — اگر جایی وارونگی ثبت شود، هر چهار جا با هم عوض می‌شوند", clrSilver);
   if(!f.causal)
      ExpAddWrapped("هشدار کیفیت: این ناحیه به کندل جابه‌جایی معتبر وصل نیست؛ در این ایندیکاتور بیشتر برای ردیابی متن‌فریم به کار می‌رود", clrOrange);
   ExpAddWrapped(StringFormat("انقضا: اگر تا %d کندل لمس یا استفاده نشود، منقضی می‌شود (تنظیم فعلی)", InpFVG_ExpireBars), clrSilver);
   ExpAddWrapped(StringFormat("کنترل خودت: سه کندل اطراف %s را ببین؛ کندل وسط باید بدنهٔ بزرگ داشته باشد و شکاف بین کندل اول و سوم دیده شود؛ میانهٔ ناحیه: %.2f",
                 TimeToString(f.time,TIME_DATE|TIME_MINUTES),(f.top+f.bottom)/2.0), clrSilver);
   ExpAdd("ICT_Assistant_Canonical_Explain.csv — ردیف شمارهٔ "+IdToStr(f.id)+" در این فایل", clrSilver);
}

void ExplainOB(const OBObj &o)
{
   // فاز ۴۳: عنوان OB هم نقش فعلی را می‌گوید (Breaker/Mitigation Block قطبیت
   // برگشته دارد و دیگر در جهت تولدش کار نمی‌کند).
   g_expTitle="ZONE OB #"+IdToStr(o.id)+" "+(o.direction==DIR_BULL?"BULLISH":"BEARISH")
              +(o.polarityFlipped? " -> "+DirToStr(OBActiveDir(o))+" (polarity flipped)" : "");
   ExpAddWrapped(StringFormat("چیست: اردر بلاک؛ ناحیه %.2f تا %.2f؛ زمان %s",
                 o.bottom,o.top, TimeToString(o.time,TIME_DATE|TIME_MINUTES)), clrWhite);
   ExpAdd(StringFormat("دامنهٔ ناحیه: %s", InpOBUseFullCandleRange?"کل کندل، از فتیله تا فتیله":"فقط بدنهٔ کندل"), clrAqua);
   ExpAdd("نوع ناحیه: "+ObKindFa(o.kind), clrAqua);
   ExpAdd("وضعیت: "+ObStateFa(o.state),
          (o.state==OB_VALID)?clrLime:(o.state==OB_BREAKER?clrDeepSkyBlue:clrGoldenrod));
   ExpAddWrapped("چرا تشکیل شد: آخرین کندل مخالف‌رنگ پیش از یک جابه‌جایی، همراه با یک رویداد ساختاری و یک جاروی نقدینگی ثبت شد", clrAqua);
   ExpAdd("Displacement #"+IdToStr(o.displacementId)+" | Event #"+IdToStr(o.structureEventId)+" | Sweep #"+IdToStr(o.liquidityEventId), clrSilver);      ExpAddWrapped("زنجیرهٔ تبدیل به بلوک شکننده: اردر بلاک معتبر که روی یک جاروی نقدینگی ساخته شده باشد، بعد بسته‌شدن از سمت مخالف و در پایان ریتست در کندلی جدا", clrWhite);
      ExpAddWrapped("اگر ناحیه روی جارو ساخته نشده باشد، حتی با شکست و ریتست هم بلوک شکننده نمی‌شود", clrOrange);
   ExpAddWrapped("لمس معتبر: ناحیه در همان کندل ثبت خودش لمس‌شده حساب نمی‌شود؛ این وضعیت فقط از کندل بعد ثبت می‌شود", clrSilver);
   // فاز ۳۶ — تفکیک Internal/External OB (منبع: LuxAlgo — Internal vs External
   // Range Liquidity: OB داخل لگ = Internal؛ مبدأ اکسترمم رنج = External)
   ExpAdd((o.scope==SCOPE_EXTERNAL)?"EXTERNAL (ERL)":"INTERNAL (IRL)", o.scope==SCOPE_EXTERNAL?clrGold:clrAqua);
   ExpAddWrapped((o.scope==SCOPE_EXTERNAL)
      ? "جایگاه: ناحیه روی مبدأ یا اکسترمم دامنهٔ معامله‌گری نشسته است؛ شکست آن یعنی خروج از رنج و معمولاً آغاز یک دامنهٔ تازه — هدف بعدی به‌طور معمول نقدینگی درونی است"
      : "جایگاه: ناحیه درون دامنهٔ معامله‌گری مانده است؛ بعد از مصرف نقدینگی بیرونی، قیمت برای پرکردن ناهنجاری‌های درون دامنه برمی‌گردد و ورود هم‌جهت در نیمهٔ ارزان یا گران منطقی‌تر است",
      (o.scope==SCOPE_EXTERNAL)?clrGold:clrAqua);
   ExpAddWrapped("شرط استفاده: فقط وقتی ناحیه هم‌جهت با بایاس مالک باشد و با یک گپ قیمتی یا میانهٔ آن هم‌پوشانی داشته باشد؛ ناحیهٔ تنها و بدون ساختار را استفاده نکن", clrLime);
   ExpAddWrapped("فیک و بی‌اعتبار: اگر ناحیه بدون تازگی چند بار لمس شود اعتبارش می‌رود؛ و اگر کندل بسته از ناحیه عبور کند دیگر اردر بلاک نیست", clrOrange);
   if(o.state==OB_INVALID)
      ExpAddWrapped("دلیل بی‌اعتبار بودن این ناحیه: به جابه‌جایی و رویداد ساختاری معتبر وصل نشده بود؛ چنین ناحیه‌ای فقط برای شفافیت رسم می‌شود", clrOrange);
   ExpAddWrapped(StringFormat("کنترل خودت: کندل %s را ببین؛ باید کندل مخالف رنگ پیش از حرکت بزرگ باشد؛ ناحیهٔ ثبت‌شده %.2f تا %.2f",
                 TimeToString(o.time,TIME_DATE|TIME_MINUTES),o.bottom,o.top), clrSilver);
   ExpAdd("OB #"+IdToStr(o.id)+" — ICT_Assistant_Canonical_Explain.csv", clrSilver);
}

void ExplainRejection(const RejectionObj &r)
{
   g_expTitle="ZONE REJECTION #"+IdToStr(r.id)+" "+(r.direction==DIR_BULL?"BULLISH":"BEARISH");
   ExpAddWrapped(StringFormat("چیست: بلوک پس‌زدگی؛ ناحیه همان فتیلهٔ غالب است از %.2f تا %.2f و کل کندل نیست؛ زمان %s", r.bottom,r.top,TimeToString(r.time,TIME_DATE|TIME_MINUTES)), clrWhite);
   ExpAddWrapped("چرا تشکیل شد: در همان کندل یک سطح نقدینگی ثبت‌شده جارو شد و یک فتیله بیش از ۶۰ درصد دامنه را گرفت (بدنه کمتر از ۴۰ درصد)؛ یعنی قیمت نقدینگی را برداشت و برگشت", clrAqua);
   ExpAddWrapped("شرط ثبت: بدون جاروی یک سطح نقدینگی در همان کندل، هیچ بلوک پس‌زدگی ثبت نمی‌شود؛ لمس همان کندل سازنده هم محاسبه نمی‌شود", clrSilver);
   ExpAdd("وضعیت: "+RejectionStateFa(r.rejectionState),
          r.rejectionState==REJECTION_FRESH?clrLime:(r.rejectionState==REJECTION_TOUCHED?clrGoldenrod:clrDimGray));
   ExpAddWrapped("استفادهٔ درست: فقط وقتی هم‌جهت با بایاس و همراه با جارو و جابه‌جایی باشد؛ یک کندل پس‌زدگی تنها کافی نیست", clrLime);
   ExpAddWrapped("فیک و بی‌اعتبار: لمس شدن ناحیه تازگی را کم می‌کند و بسته‌شدن از سمت مخالف آن را بی‌اعتبار می‌کند", clrOrange);
   ExpAddWrapped(StringFormat("کنترل خودت: نسبت فتیله به دامنه را خودت روی کندل %s اندازه بگیر؛ اگر فتیله غالب نبود، ثبت درست نبوده", TimeToString(r.time,TIME_DATE|TIME_MINUTES)), clrSilver);
}

void ExplainSessionBox(string kind, int dayBack)
{
   datetime ref = g_lastContextBarTime>0? g_lastContextBarTime : TimeCurrent();
   datetime s=0,e=0; double hi=0,lo=0; int cnt=0;
   string winName=""; int sh=0,sm=0,eh=0,em=0;
   if(kind=="ASIA") { winName="Asian Range (Accumulation)"; sh=InpAsiaStartHourNY; sm=0; eh=InpAsiaEndHourNY; em=0; }
   else if(kind=="LON"){ winName="London Killzone (Manipulation/Judas)"; sh=InpLondonStartHourNY; sm=0; eh=InpLondonEndHourNY; em=0; }
   else if(kind=="NYAM"){ winName="New York AM Killzone (Distribution)"; sh=InpNY_KZ_StartHourNY; sm=0; eh=InpNY_KZ_EndHourNY; em=0; }
   else if(kind=="LONCL"){ winName="London Close Killzone"; sh=InpLondonCloseStartHourNY; sm=0; eh=InpLondonCloseEndHourNY; em=0; }
   else if(kind=="NYPM"){ winName="New York PM Killzone"; sh=InpNYPM_StartHourNY; sm=InpNYPM_StartMinuteNY; eh=InpNYPM_EndHourNY; em=InpNYPM_EndMinuteNY; }
   else if(kind=="SB1"){ winName="Silver Bullet #1"; sh=InpSB1_StartHourNY; sm=0; eh=InpSB1_EndHourNY; em=0; }
   else if(kind=="SB2"){ winName="Silver Bullet #2"; sh=InpSB2_StartHourNY; sm=0; eh=InpSB2_EndHourNY; em=0; }
   else if(kind=="SB3"){ winName="Silver Bullet #3"; sh=InpSB3_StartHourNY; sm=0; eh=InpSB3_EndHourNY; em=0; }

   g_expTitle="SESSION "+winName;
   if(!WindowForDayBack(dayBack, sh,sm, eh,em, ref, s,e,hi,lo,cnt,true))
   { ExpAdd("برای این روز داده‌ای پیدا نشد", clrSilver); return; }

   ExpAddWrapped(StringFormat("پنجره: %02d:%02d تا %02d:%02d به وقت نیویورک | معادل سرور: %s تا %s",
                 sh,sm,eh,em, TimeToString(s,TIME_DATE|TIME_MINUTES), TimeToString(e,TIME_DATE|TIME_MINUTES)), clrWhite);
   ExpAddWrapped(StringFormat("چیست: رنج همین پنجره؛ سقف %.2f و کف %.2f از %d کندل روی تایم‌فریم %s",
                 hi,lo,cnt,TfFa(InpSessionSourceTF)), clrAqua);
   if(kind=="ASIA")
   {
      ExpAddWrapped("چرا مهم است: آسیا فاز انباشت است؛ رنج آن هدف نقدینگی اصلی لندن می‌شود و بزرگ‌ترین حرکت روز معمولاً از برداشت همین نقدینگی شروع می‌شود", clrLime);
      ExpAddWrapped("در لندن چه انتظاری داریم: اگر فقط فتیله از سقف یا کف آسیا بگذرد و برگردد جاروی نقدینگی است؛ و اگر کندل بسته بیرون ببندد شکست واقعی و تغییر رفتار است", clrLime);
      ExpAddWrapped("فیک/بی‌اعتبار: اگر رنج آسیا بسیار باریک باشد (نقدینگی کم) کیفیت هدف پایین می‌آید؛ روزهای خبری بزرگ هم قواعد را می‌شکنند", clrOrange);
   }
   else if(StringFind(kind,"SB")==0)
   {
      ExpAddWrapped("چیست: این یک پنجرهٔ زمانی است، نه سیگنال — در این یک ساعت اگر نقدینگی مشخصی جارو شود و سپس جابه‌جایی و گپ یا تغییر ساختار در جهت بایاس مالک ظاهر شود، ستاپ کیفیت بالاتری دارد", clrLime);
      ExpAddWrapped("چرا مهم است: این پنجره‌ها ساعت‌هایی هستند که حرکت جهت‌دار اغلب از آن‌ها شروع می‌شود؛ پس همان الگوی همیشگی را در زمان پراحتمال‌تر می‌بینی", clrLime);
      ExpAddWrapped("فیک و بی‌اعتبار: اگر داخل پنجره فقط رنج باشد و هیچ جارو یا جابه‌جایی رخ ندهد هیچ ستاپی معتبر نیست — خودِ ساعت دلیل ورود نیست؛ و اگر بایاس مالک مخالف باشد حرکت داخل پنجره فقط ضد‌روند است", clrOrange);
      ExpAddWrapped("کنترل خودت: ساعت شروع و پایان نیویورک را روی داشبورد ببین و با محدودهٔ همین باکس مقایسه کن؛ اگر جابه‌جا بود آفست یا ساعت تابستانی را بررسی کن", clrSilver);
   }
   else
   {
      ExpAddWrapped("چرا مهم است: سقف و کف همین پنجره به‌عنوان نقدینگی کوتاه‌مدت ثبت می‌شود و جارو آن معمولاً نقطهٔ شروع حرکت جهت‌دار است", clrLime);
      ExpAddWrapped("دقت کندل بسته: ستاپ‌ها فقط با بسته‌شدن کندل خارج از این پنجره معنا دارند؛ داخل پنجره فقط زمینه‌سازی است", clrLime);
   }
   ExpAddWrapped(StringFormat("کنترل خودت: محدودهٔ %s تا %s را روی چارت ببین؛ اگر با ساعت نیویورک نمی‌خواند، آفست بروکر یا ساعت تابستانی را باید تنظیم کرد؛ داشبورد همان آفست تشخیص‌داده‌شده را در ردیف ساعت نشان می‌دهد",
                 TimeToString(s,TIME_DATE|TIME_MINUTES), TimeToString(e,TIME_DATE|TIME_MINUTES)), clrSilver);
   ExpAdd("InpBrokerGMTOffsetOverrideHours — تنظیم دستی آفست بروکر", clrSilver);
}

void ExplainMTFLevel(int index, bool isHigh)
{
   string tf=EnumToString(g_mtfContext[index].timeframe);
   g_expTitle="MTF "+tf+" — "+g_mtfContext[index].role;
   ExpAdd(StringFormat("نقش این تایم‌فریم: %s", g_mtfContext[index].role), clrGold);
   ExpAddWrapped(StringFormat("چیست: سطح حفاظت‌شدهٔ %s روی تایم‌فریم %s؛ داده در %s",
                 isHigh?"سقف":"کف", TfFa(g_mtfContext[index].timeframe),
                 TimeToString(g_mtfContext[index].confirmedBarTime,TIME_DATE|TIME_MINUTES)), clrWhite);
   ENUM_DIRECTION shownExt=(index==0)?g_htfBias:g_mtfContext[index].externalDirection;
   ExpAdd(StringFormat("جهت محاسبه‌شده — بیرونی: %s | درونی: %s",
          DirFa(shownExt), DirFa(g_mtfContext[index].internalDirection)), clrAqua);
   if(index==0)
      ExpAddWrapped("قاعدهٔ سخت: این تایم‌فریم مالک بایاس است؛ هیچ تایم‌فریم پایین‌تری اجازه ندارد آن را عوض کند — فقط می‌تواند تأیید یا رد کند و آماده‌شدن ستاپ را مسدود کند", clrGold);
   else
      ExpAddWrapped("قاعده: این تایم‌فریم نقش کانتکست، ستاپ یا تأیید دارد؛ هم‌جهت بودنش با بایاس شرط لازم است و تضاد آن فقط آماده‌شدن را مسدود می‌کند، نه تغییر بایاس", clrLime);
   if(g_mtfConflict)
      ExpAddWrapped("وضعیت فعلی: تضاد فعال است — "+g_mtfConflictReason, clrOrange);
   ExpAddWrapped(StringFormat("کنترل خودت: روی تایم‌فریم %s بازش کن و ببین جهت ساختار (سقف‌ها و کف‌های تأییدشده) با چیزی که اینجا نوشته هم‌خوان است یا نه", TfFa(g_mtfContext[index].timeframe)), clrSilver);
}

void ExplainSetup()
{
   g_expTitle="SETUP "+g_setup.status;
   if(g_setup.active)
   {
      ExpAdd(StringFormat("ستاپ فعال: جهت %s | ورود %s | حد ضرر %s",
             DirFa(g_setup.dir), PriceS(g_setup.entry), PriceS(g_setup.sl)), clrLime);
      ExpAdd(StringFormat("اهداف: اول %s | دوم %s | سوم %s", PriceS(g_setup.tp1), PriceS(g_setup.tp2), PriceS(g_setup.tp3)), clrLime);
      ExpAdd(StringFormat("ریسک واقعی: ورود تا حد ضرر %.2f (%.2f برابر میانگین دامنه)",
             g_setup.risk, (g_analysisATR>0.0? g_setup.risk/g_analysisATR : 0.0)), clrAqua);
      ExpAdd(StringFormat("نسبت سود به ریسک از فاصله‌ها حساب شده نه از ورودی: هدف سوم 1:%.2f | هدف اول 1:%.2f | هدف دوم 1:%.2f",
             g_setup.rrTP3, g_setup.rrTP1, g_setup.rrTP2), clrLime);
      ExpAdd("ناحیهٔ ورود: "+g_setup.zoneSource, clrAqua);
      ExpAdd("FVG #"+IdToStr(g_setup.fvgId)+" | OB #"+IdToStr(g_setup.obId)+" | DOL "+PriceS(g_currentDOL.price), clrSilver);
      ExpAdd("زنجیرهٔ اثبات: "+g_setup.chainText, clrAqua);
      ExpAdd("منبع حد ضرر: "+g_setup.slSource, clrSilver);
      ExpAddWrapped("چرا آماده شد — ساختار: بایاس مالک تأیید شده و تضاد تایم‌فریمی نیست؛ کانتکست‌های یک‌ساعته و پانزده‌دقیقه‌ای و پنج‌دقیقه‌ای هم‌جهت‌اند و تأیید اجرایی دو‌دقیقه‌ای و یک‌دقیقه‌ای رسیده است", clrLime);
      ExpAddWrapped("چرا آماده شد — چرخهٔ اثبات: یک چرخهٔ جارو و جابه‌جایی و شکست ساختار هم‌جهت و تازه وجود دارد؛ دامنهٔ معامله‌گری معتبر و هم‌جهت است", clrLime);
      ExpAddWrapped("چرا آماده شد — هدف و ریسک: هدف نقدینگی هم‌جهت با فاصلهٔ کافی موجود است؛ ناحیهٔ ورود داخل باند بهینه است و نسبت سود به ریسک از حداقل ورودی کمتر نیست", clrLime);
      ExpAddWrapped("محدودیت این نسخه: مدیریت پوزیشن و حجم معامله محاسبه نمی‌شود و چرخهٔ عمر فقط یک ستاپ را در هر لحظه پیگیری می‌کند", clrOrange);
      ExpAddWrapped("چه چیزی آن را باطل می‌کند: تغییر یا تضاد بایاس مالک؛ از دست رفتن هدف هم‌جهت؛ رفتن دامنه به دامنهٔ مخالف؛ بسته‌شدن قیمت فراتر از مرز باند بهینه به سمت مخالف؛ یا مصرف و انقضای ناحیه", clrTomato);
   }
   ExpAddWrapped("فرسودگی روند: "+ExhaustionStateFa(g_exhaustion.state)+" با امتیاز "+IntegerToString(g_exhaustion.score)+" از "+IntegerToString(g_exhaustion.maxScore), clrOrange);
   ExpAddWrapped(StringFormat("دروازهٔ برگشت: %s | سطح محافظت‌شدهٔ خارجی: %s | امتیاز برگشت پول بزرگ %d از %d — برگشت فقط با بسته‌شدن فراتر از سطح محافظت‌شدهٔ خارجی اعلام می‌شود و فرسودگی هرگز بایاس را عوض نمی‌کند",
                 g_reversal.state, (g_reversal.armed? DoubleToString(g_reversal.levelPrice,_Digits):"—"),
                 g_reversal.smrScore, g_reversal.smrMax), g_reversal.confirmed?clrLime:clrOrange);
   // فاز ۱۲ (#۳ #۹ #۴۷ #۶۷ #۶۸)
   ExpAdd(StringFormat("مدل ورود: %s | امتیاز کیفیت %d از ۱۰ (حداقل %d)",
          EntryModelFa(g_setup.entryModel), g_setup.quality, InpMinQualityScore),
          g_setup.entryModel==MODEL_NONE?clrOrange:clrLime);
   if(g_setup.modelReason!="") ExpAdd("دلیل مدل: "+g_setup.modelReason, clrSilver);
   if(g_setup.qualityText!="") ExpAdd("تفکیک کیفیت: "+g_setup.qualityText, clrSilver);
   ExpAdd(StringFormat("ساختار داخلی تایم‌فریم مالک (%s): %s", TfFa(InpHTF), DirFa(g_htfInternalDir)), clrAqua);
   if(g_htfInternalReason!="") ExpAdd(g_htfInternalReason, clrAqua);
   ExpAdd(StringFormat("فاز روند: %s با سن %d کندل", TrendPhaseFa(g_trend.phase), g_trend.ageBars), clrAqua);
   if(g_trend.phaseReason!="") ExpAdd(g_trend.phaseReason, clrAqua);
   ExpAdd(StringFormat("ناحیهٔ منتخب: %s با امتیاز %d (شناسه #%s)",
          PoiKindFa(g_setup.poiKind), g_setup.poiScore, IdToStr(g_setup.poiId)), clrAqua);
   if(g_trendlineBuilt) ExpAdd("نقدینگی مورب: فعال است", clrAqua);
   else if(g_trendlineReject!=""){ ExpAdd("نقدینگی مورب فعال نشد", clrOrange); ExpAddWrapped(g_trendlineReject, clrOrange); }
   if(g_rangeOk)
      ExpAdd(StringFormat("رنج فعال: %.2f تا %.2f (%.1f برابر میانگین دامنه) با %d و %d برخورد",
             g_rangeLow, g_rangeHigh, (g_analysisATR>0.0? g_rangeHeight/g_analysisATR:0.0),
             g_rangeLowTouches, g_rangeHighTouches), clrAqua);
   else if(g_rangeReject!=""){ ExpAdd("رنج معتبر پیدا نشد", clrOrange); ExpAddWrapped(g_rangeReject, clrOrange); }
   ExpAddWrapped("سطوح چرخهٔ تحویل: "+g_ipdaNote, g_ipdaOk?clrAqua:clrOrange);
   if(g_exhaustion.reason!="") ExpAddWrapped("شواهد فرسودگی: "+g_exhaustion.reason, clrSilver);
   if(!g_setup.active)
   {
      ExpAddWrapped("دلیل اینکه هنوز آماده نیست: "+SetupStatusFa(g_setup.status), clrOrange);
      ExpAdd("Setup status code: "+g_setup.status, clrSilver);
      ExpAddWrapped("ترتیب شرط‌ها: بایاس مالک، هدف نقدینگی هم‌جهت با حداقل فاصله، نبود تضاد تایم‌فریمی، هم‌جهتی کانتکست‌ها، تأیید اجرایی", clrLime);
      ExpAddWrapped("و سپس چرخهٔ اثبات‌شدهٔ جارو و جابه‌جایی و شکست ساختار، اعتبار دامنهٔ معامله‌گری، ناحیهٔ ورود داخل باند بهینه، حد ضرر معتبر و نسبت سود به ریسک کافی", clrLime);
   }
   // فاز ۱۵ (#۶۶): چرخهٔ عمر — ابطال با عبور *بستهٔ* قیمت از SL
   if(InpTrackSetupLifecycle)
   {
      string lifeColor = (g_setupLifeState=="INVALIDATED")? "ابطال‌شده" : "در جریان";
      ExpAdd(StringFormat("چرخهٔ عمر ستاپ: %s | مسلح‌شده در %s", lifeColor,
             (g_setupLifeArmTime>0? TimeToString(g_setupLifeArmTime,TIME_DATE|TIME_MINUTES):"—")), clrAqua);
      ExpAdd(StringFormat("حد ضرر پیگیری %s | هدف اول پیگیری %s | شمارنده‌ها: مسلح %d و باطل %d و هدف اول %d",
             (g_setupLifeSL>0.0? PriceS(g_setupLifeSL):"—"),
             (g_setupLifeTP1>0.0? PriceS(g_setupLifeTP1):"—"),
             g_setupArmedCount, g_setupInvalidCount, g_setupTP1Count), clrAqua);
      if(g_setupLifeState=="INVALIDATED")
         ExpAdd(StringFormat("ابطال با عبور بستهٔ قیمت از حد ضرر رخ داده است — کندل %s | قیمت بسته %s | حد ضرر %s",
                TimeToString(g_setupInvalidTime,TIME_DATE|TIME_MINUTES),
                PriceS(g_setupInvalidPrice), PriceS(g_setupLifeSL)), clrTomato);
      else if(g_setupLifeState=="TP1_HIT")
         ExpAdd("هدف اول (یک برابر ریسک) لمس شد و پیگیری این ستاپ بسته شد", clrLime);
      else if(g_setupLifeState=="TRACKING")
         ExpAdd("این ستاپ در حال پیگیری است: ابطال فقط وقتی ثبت می‌شود که یک کندل بسته فراتر از حد ضرر بسته شود؛ لمس فتیله ابطال نیست", clrOrange);
      else
         ExpAdd("هنوز هیچ ستاپ آماده‌ای مسلح نشده است؛ با آماده شدن ستاپ پیگیری شروع می‌شود", clrSilver);
      if(g_setupLifeReason!="") ExpAdd("دلیل آخرین تغییر وضعیت: "+g_setupLifeReason, clrSilver);
      ExpAdd("ICT_Assistant_Canonical_SetupLifecycle.csv — دفتر چرخهٔ عمر ستاپ", clrSilver);
   }
   ExpAdd(StringFormat("آفست زمانی بروکر: %+d دقیقه | استاندارد زمستانی: %+d دقیقه | قاعدهٔ ساعت تابستانی: %s",
          g_serverGMTOffsetSeconds/60, g_brokerStdOffsetSeconds/60,
          (g_brokerDSTRule==BDST_AUTO?"خودکار":(g_brokerDSTRule==BDST_US?"قاعدهٔ آمریکا":(g_brokerDSTRule==BDST_EU?"قاعدهٔ اروپا":"بدون قاعده")))), clrAqua);
   ExpAdd(StringFormat("حالت محاسبهٔ تاریخی: %s", InpUseHistoricalBrokerOffset?"فعال — ساعت تابستانی همان لحظه محاسبه می‌شود":"غیرفعال — آفست جاری استفاده می‌شود"), clrAqua);
   ExpAdd("پنجره‌های سشن با آفست همان لحظهٔ تاریخی ساخته می‌شوند، نه با آفست امروز", clrAqua);
   ExpAddWrapped("کنترل خودت: چیزی که این ابزار می‌گوید را با سه چیز بسنج — کندل تأیید، قیمت سطح و شناسه‌ها؛ اگر ناسازگار بود همان عدد را با پیوت دستی مقایسه کن", clrSilver);
   ExpAdd("SETUP — ICT_Assistant_Canonical_Explain.csv", clrSilver);
}

void ExplainLocation(string label)
{
   g_expTitle="LOCATION "+label;
   if(!g_leg.valid)
   {
      ExpAddWrapped("دامنهٔ معامله‌گری معتبر نیست — دلیل: "+LegRejectFa(g_leg.reject), clrOrange);
      ExpAdd("Leg reject code: "+g_leg.reject, clrSilver);
      ExpAddWrapped("معنی دلایل: دادهٔ کافی یعنی کندل بستهٔ کافی روی تایم‌فریم مالک موجود نبوده و سقف و کف متناوب یعنی پیوت‌های تأییدشدهٔ متناوب به حداقل نرسیده‌اند", clrSilver);
      ExpAddWrapped("دامنهٔ صفر یعنی دو پیوت روی یک قیمت نشسته‌اند و دامنهٔ کوچک یعنی اندازهٔ دامنه از حداقل نسبت به میانگین دامنه کمتر است", clrSilver);
      ExpAddWrapped("کنترل خودت: دو پیوت آخر تایم‌فریم مالک را روی چارت ببین؛ اگر فاصلهٔ پیوت‌ها کم یا نامنظم است، تایم‌فریم بالاتر برای رمزگذاری لگ مناسب‌تر است", clrSilver);
      return;
   }

   string dirFa = DirFa(g_leg.dir);
   ExpAddWrapped(StringFormat("چیست: دامنهٔ معامله‌گری از همان دامنهٔ واقعی ساخته شده — از پیوت آغاز %s در %.2f تا پیوت پایان %s در %.2f",
                 (g_leg.dir==DIR_BULL?"کف":"سقف"), g_leg.startPrice,
                 (g_leg.dir==DIR_BULL?"سقف":"کف"), g_leg.endPrice), clrWhite);
   ExpAdd(StringFormat("دو نقطهٔ دامنه: %s و %s",
          TimeToString(g_leg.startTime,TIME_DATE|TIME_MINUTES), TimeToString(g_leg.endTime,TIME_DATE|TIME_MINUTES)), clrAqua);
   ExpAdd(StringFormat("جهت دامنه: %s | اندازهٔ دامنه: %.2f (%.2f برابر میانگین دامنه)",
          dirFa, g_leg.range, g_leg.sizeATR), clrAqua);

   double eq=g_leg.eq;
   double oteLow = (g_leg.dir==DIR_BULL)? g_leg.high-g_leg.range*InpOTE_High : g_leg.low+g_leg.range*InpOTE_Low;
   double oteHigh= (g_leg.dir==DIR_BULL)? g_leg.high-g_leg.range*InpOTE_Low  : g_leg.low+g_leg.range*InpOTE_High;
   double golden = (g_leg.dir==DIR_BULL)? g_leg.high-g_leg.range*InpOTE_Golden : g_leg.low+g_leg.range*InpOTE_Golden;
   ExpAdd(StringFormat("تعادل دامنه %.2f | باند بهینهٔ فیبوناچی %.2f تا %.2f (بین %.0f%% و %.0f%%) | نقطهٔ طلایی %.2f (%.1f%%)",
          eq, oteLow, oteHigh, InpOTE_Low*100.0, InpOTE_High*100.0, golden, InpOTE_Golden*100.0), clrAqua);
   ExpAdd(StringFormat("قیمت تحلیل‌شده: %.2f — پس در سمت %s تعادل قرار دارد",
          g_analysisClose, (g_analysisClose>=eq?"گران (بالای تعادل)":"ارزان (زیر تعادل)")), clrWhite);
   // فاز ۳۶: توضیح Price Delivery (برچسب لگ روی چارت = همین مفهوم)
   ExpAdd(StringFormat("تحویل قیمت: قیمت همیشه از یک نقدینگی به نقدینگی دیگر تحویل می‌شود؛ این دامنهٔ %s از %s شروع شده و الان در %s تعادل است",
          dirFa, TimeToString(g_leg.startTime,TIME_DATE|TIME_MINUTES),
          (g_analysisClose>=eq?"نیمهٔ بالای":"نیمهٔ پایین")), clrLime);
   ExpAdd("بازگشت به تعادل یا باند بهینه فرصت ورود هم‌جهت است و عبور قاطع از اکسترمم دامنه یعنی تحویل به نقدینگی بعدی و آغاز دامنهٔ تازه", clrLime);

   if(label=="GOLDEN")
      ExpAdd(StringFormat("خاصیت نقطهٔ طلایی: %.2f وسط همان باند بهینه است و از ۷۰٫۵ درصد ریتریس دامنه می‌آید؛ ورود در همین نقطه کم‌ترین ریسک و بیشترین تطابق با دامنه را دارد", golden), clrLime);
   else
      ExpAdd("خاصیت این سطح: تعادل نصف دامنه است؛ بالای آن نیمهٔ گران و پایین آن نیمهٔ ارزان. در بایاس صعودی ورود فقط از نیمهٔ ارزان و در باند بهینه، و در بایاس نزولی فقط از نیمهٔ گران", clrLime);

   ExpAddWrapped("توجه: این باند فقط وقتی در ستاپ استفاده می‌شود که جهت دامنه با بایاس مالک یکی باشد؛ دامنهٔ مخالف دلیل رد شدن ستاپ است، نه دلیلی برای ورود برعکس", clrOrange);
   ExpAddWrapped("کنترل خودت: یک فیبوی دستی روی همان دو نقطه بگذار؛ باید ۶۲ و ۷۰٫۵ و ۷۹ همین اعداد را بدهد. اگر فرق داشت همین شناسه را گزارش کن", clrSilver);
   ExpAdd("ICT_Assistant_Canonical_Leg_Diag.csv — ردیف همان لحظه", clrSilver);
}

// توضیح فارسی خط DOL (هدف معامله) — روی hover همان خط دیده می‌شود
void ExplainDOL()
{
   g_expTitle="DRAW ON LIQUIDITY";
   if(!g_hasDOL)
   {
      ExpAddWrapped("فعلاً هدف نقدینگی معتبری وجود ندارد؛ واکنش به بایاس مالک شکل نگرفته یا سطح هم‌جهت پیدا نشده است", clrOrange);
      if(g_dolRejectReason!="") { ExpAdd("DOL reject code: "+g_dolRejectReason, clrSilver); }
      return;
   }
   ExpAdd(g_currentDOL.typeName, clrWhite);
   ExpAdd(StringFormat("چیست: سطح نقدینگی هم‌جهت بایاس که قیمت به سمت آن کشیده می‌شود — قیمت هدف %.2f", g_currentDOL.price), clrWhite);
   ExpAddWrapped("چرا این سطح: "+g_currentDOL.narrative, clrAqua);
   ExpAdd(StringFormat("فاصلهٔ واقعی تا هدف: %.2f برابر میانگین دامنه (%.2f قیمت)",
          g_currentDOL.distATR, MathAbs(g_currentDOL.price-g_analysisClose)), clrAqua);
   ExpAdd(StringFormat("حداقل فاصلهٔ لازم روی همین سطح: %.2f برابر میانگین دامنه تا نسبت سود به ریسک ناچیز رد شود", InpDOL_MinRoomATR), clrSilver);
   ExpAdd(StringFormat("سطح هنوز دست‌نخورده است: %s | جایگاه در سلسله‌مراتب تأیید شده: %s",
          (g_currentDOL.sweepStateOk?"بله":"خیر"), (g_currentDOL.hierarchyOk?"بله — بیرونی":"درونی")), clrLime);
   ExpAddWrapped("اشتباه رایج: انتخاب دورترین سطح به بهانهٔ سود بیشتر؛ نسبت سود به ریسک وقتی خراب می‌شود که هدف خیلی نزدیک باشد، نه خیلی دور", clrOrange);
   ExpAddWrapped("کنترل خودت: قیمت هدف را با سقف یا کف روز یا هفتهٔ قبل روی چارت مقایسه کن؛ اگر آن سطح با هیچ خط دیگری در رجیستری یکی نیست همین شناسه را گزارش کن", clrSilver);
}

// فاز ۱۲ (#۱۹) — توضیح فارسی نقدینگی مورب
void ExplainTrendline(long id)
{
   int idx=-1;
   for(int i=0;i<ArraySize(g_trendlines);i++) if(g_trendlines[i].id==id){ idx=i; break; }
   if(idx<0)
   {
      g_expTitle="TRENDLINE #"+IdToStr(id);
      ExpAdd("این خط در رجیستری نقدینگی مورب پیدا نشد؛ همین شناسه را گزارش کن", clrOrange);
      return;
   }
   g_expTitle="TRENDLINE "+(g_trendlines[idx].isHigh?"RESISTANCE":"SUPPORT")+" #"+IdToStr(id);
   ExpAddWrapped(StringFormat("چیست: نقدینگی مورب — خطی که %s تأییدشدهٔ تایم‌فریم %s را وصل می‌کند؛ استاپ‌ها پشت همین خط جمع می‌شوند",
                 g_trendlines[idx].isHigh?"دو سقف":"دو کف", TfFa(g_trendlines[idx].tf)), clrWhite);
   ExpAddWrapped(StringFormat("آنکرها: %s در %s تا %s در %s | شیب: %.6f قیمت بر ثانیه | تعداد سویینگ روی خط: %d",
                 DoubleToString(g_trendlines[idx].p1,_Digits), TimeToString(g_trendlines[idx].t1,TIME_DATE|TIME_MINUTES),
                 DoubleToString(g_trendlines[idx].p2,_Digits), TimeToString(g_trendlines[idx].t2,TIME_DATE|TIME_MINUTES),
                 g_trendlines[idx].slope, g_trendlines[idx].touches), clrAqua);
   ExpAddWrapped(StringFormat("قیمت خط در آخرین لحظهٔ تحلیل: %s (خط تابع زمان است، پس یک عدد ثابت نیست)",
                 DoubleToString(TrendlinePriceAt(g_trendlines[idx], g_lastContextBarTime),_Digits)), clrAqua);
   ExpAdd(StringFormat("شرط ابطال: بسته‌شدن کندل با فاصلهٔ بیش از %.2f برابر میانگین دامنه فراتر از خط، یعنی نقدینگی این خط برداشته شده و خط دیگر معتبر نیست",
          InpTrendlineBreakATR), clrTomato);
   if(g_trendlines[idx].swept)
   {
      ExpAdd(StringFormat("جارو شد در کندل %s — فتیله از خط عبور کرد ولی کندل به همان سمت خط بسته شد",
             TimeToString(g_trendlines[idx].sweptTime,TIME_DATE|TIME_MINUTES)), clrYellow);
      ExpAdd(StringFormat("قاعدهٔ جاروی مورب: فتیلهٔ فراتر همراه با بسته‌شدن برگشتی؛ قیمت خط در آن کندل %s بود و سطح مصرف‌شده علامت خورد",
             DoubleToString(g_trendlines[idx].sweptPrice,_Digits)), clrYellow);
   }
   else
      ExpAddWrapped("جارو نشده: هنوز هیچ فتیله‌ای فراتر از خط نرفته و به همان سمت برنگشته است — استخر نقدینگی مورب دست‌نخورده است", clrAqua);
   ExpAdd(StringFormat("کنترل خودت: دو آنکر نام‌برده‌شده را روی چارت ببین؛ شیب آن‌ها باید با قاعدهٔ سمت نقدینگی بخواند و تعداد سویینگ روی خط باید حداقل %d باشد",
          MathMax(2,InpTrendlineMinTouches)), clrSilver);
   ExpAdd("قاعدهٔ سمت: سقف‌های نزولی یعنی نقدینگی سقفی بالای خط و کف‌های صعودی یعنی نقدینگی کفی زیر خط", clrSilver);
   ExpAdd("InpTrendlineMinTouches — حداقل تعداد سویینگ روی خط", clrSilver);
}

// فاز ۱۲ (#۴۷ #۶۷ #۶۸) — توضیح بهترین POI و امتیاز کیفیت ستاپ
void ExplainBestPOI()
{
   POIObj bp;
   g_expTitle="POI REGISTRY";
   if(!InpBuildPOIRegistry || ArraySize(g_poi)==0)
   {
      ExpAdd("رجیستری نقاط مورد علاقه خالی است یا با ورودی مربوطه خاموش شده", clrOrange);
      ExpAdd("InpBuildPOIRegistry — کلید ساخت رجیستری", clrSilver);
      return;
   }
   ExpAdd(StringFormat("چیست: رجیستری یکپارچهٔ نقاط مورد علاقه — %d ناحیه با نوع، جهت، محدوده، زمان، تایم‌فریم مالک و امتیاز عددی", ArraySize(g_poi)), clrWhite);
   ExpAdd("منابع: گپ علّی، اردر بلاک، بلوک شکننده، بلوک تخفیف، بلوک پس‌زدگی، نقدینگی مورب و مرزهای رنج", clrWhite);
   if(FindBestPOI(g_htfBias, bp))
   {
      ExpAdd(StringFormat("بهترین ناحیهٔ هم‌جهت بایاس: %s با امتیاز %d (شناسه #%s)",
             PoiKindFa(bp.kind), bp.score, IdToStr(bp.id)), clrLime);
      ExpAdd(StringFormat("جهت %s | ناحیه %.2f تا %.2f | زمان %s | تایم‌فریم %s",
             DirFa(bp.direction), bp.bottom, bp.top, TimeToString(bp.time,TIME_DATE|TIME_MINUTES),
             TfFa(bp.tf)), clrLime);
   }
   else ExpAdd("هیچ ناحیهٔ هم‌جهتی با بایاس فعلی در رجیستری نیست", clrOrange);
   if(FindBestPOI(DIR_NONE, bp))
      ExpAdd(StringFormat("بالاترین امتیاز کل رجیستری: %s با امتیاز %d در جهت %s",
             PoiKindFa(bp.kind), bp.score, DirFa(bp.direction)), clrAqua);
   ExpAdd("تفکیک امتیاز: پایه ۲۰ | بلوک شکننده ۱۲+ | گپ ۸+ | اردر بلاک ۶+ | مورب یا رنج ۵+ | بلوک تخفیف ۴+ | پس‌زدگی ۳+", clrSilver);
   ExpAdd("امتیازهای افزوده: هم‌جهتی با بایاس ۱۰+ | نشستن روی اکسترمم دامنه ۶+ | بلوک تودرتوی درونی ۴+", clrSilver);
   ExpAdd(StringFormat("امتیاز کهنگی: هر %d کندل یک امتیاز کاسته می‌شود تا حداکثر ۱۰ امتیاز", MathMax(1,InpPOI_AgeDecayBars)), clrSilver);
   ExpAdd(StringFormat("ستاپ فعلی: مدل %s | امتیاز کیفیت %d از ۱۰ (حداقل ورودی %d)",
          EntryModelFa(g_setup.entryModel), g_setup.quality, InpMinQualityScore), g_setup.active?clrLime:clrOrange);
   if(g_setup.qualityText!="") ExpAdd("تفکیک کیفیت: "+g_setup.qualityText, g_setup.active?clrLime:clrOrange);
   ExpAddWrapped("امتیاز کیفیت هیچ‌وقت جای دروازهٔ ساختار را نمی‌گیرد؛ فقط ستاپ‌های ضعیف را رد می‌کند و رجیستری فقط انتخاب ناحیه را یکسان می‌کند", clrTomato);
}

// فاز ۱۱ — توضیح فارسی دروازهٔ برگشت و Smart Money Reversal
void ExplainReversal()
{
   g_expTitle="REVERSAL — "+g_reversal.state;
   ExpAddWrapped(StringFormat("چیست: برگشت تأییدشده فقط یک معنا دارد — کندل بستهٔ %s فراتر از سطح محافظت‌شدهٔ خارجی *بسته* شود. فتیله کافی نیست؛ بسته‌شدن لازم است (#۸/#۷۱)", TfFa(InpHTF)), clrWhite);

   if(!InpEnableReversalGate)
   {
      ExpAdd("دروازهٔ برگشت خاموش است؛ در این حالت هیچ برگشتی تأیید نمی‌شود و تنها هشدار فرسودگی نمایش داده می‌شود", clrOrange);
      ExpAdd("InpEnableReversalGate — کلید دروازهٔ برگشت", clrSilver);
      return;
   }
   if(!g_reversal.armed)
   {
      ExpAddWrapped("الان سطح محافظت‌شدهٔ خارجی فعالی وجود ندارد؛ وضعیت: ", clrOrange);
      ExpAdd("Reversal state code: "+g_reversal.state, clrSilver);
      ExpAddWrapped("دلیل واقعی: "+g_reversal.reason, clrSilver);
      ExpAddWrapped("معنی حالت‌ها: یا بایاس مالک هنوز تأیید نشده، یا آخرین رویداد تایم‌فریم مالک سویینگ محافظ نداده و با سقف نگه‌داری سویینگ‌ها از رجیستری حذف شده، یا دادهٔ بستهٔ کافی نیست", clrSilver);
      ExpAddWrapped("کنترل خودت: آخرین رویداد تایم‌فریم مالک را روی چارت ببین؛ همان رویداد باید یک سویینگ مقابل را به‌عنوان محافظ معرفی کرده باشد — همان سویینگ سطح این دروازه است", clrSilver);
      return;
   }

   ExpAddWrapped(StringFormat("سطح محافظت‌شدهٔ خارجی: %s در %s | زمان سویینگ: %s | شناسهٔ سویینگ: #%s",
                 g_reversal.levelIsHigh?"سقف":"کف", DoubleToString(g_reversal.levelPrice,_Digits),
                 TimeToString(g_reversal.levelTime,TIME_DATE|TIME_MINUTES), IdToStr(g_reversal.levelSwingId)), clrAqua);
   ExpAddWrapped(StringFormat("جهت برگشتی که این سطح تأیید می‌کند: %s | بایاس لحظهٔ سنجش: %s | کندل سنجیده‌شده: %s با قیمت بسته %s",
                 DirFa(OppositeDir(g_reversal.snapBias)), DirFa(g_reversal.snapBias),
                 TimeToString(g_reversal.snapBarTime,TIME_DATE|TIME_MINUTES), DoubleToString(g_reversal.snapBarClose,_Digits)), clrAqua);

   if(g_reversal.confirmed)
   {
      ExpAdd(StringFormat("برگشت تأییدشده: جهت %s | کندل تأیید %s",
             DirFa(g_reversal.dir), TimeToString(g_reversal.confirmedTime,TIME_DATE|TIME_MINUTES)), clrLime);
      ExpAdd(StringFormat("قیمت بستهٔ تأیید %.5f | %d کندل از تأیید گذشته | رویداد #%s",
             g_reversal.confirmedClose, g_reversal.barsSince, IdToStr(g_reversal.eventId)), clrLime);
      ExpAdd(StringFormat("برگشت پول بزرگ: %s — %s", g_reversal.smr?"تأییدشده":"تأیید نشده", g_reversal.smrReason),
             g_reversal.smr?clrLime:clrOrange);
      ExpAdd(StringFormat("چهار شاهدی که شمرده می‌شود (حداقل %d لازم است)، هر یک یکی از این‌هاست: جاروی نقدینگی مقابل تا %d کندل پیش از شکست؛ جابه‌جایی زنجیرشدهٔ هم‌جهت؛ ناحیهٔ هم‌جهت معتبر؛ و هم‌جهتی ساختار پایین‌تر با جهت برگشت",
             InpSMR_MinScore, InpSMR_SweepLookbackBars), clrSilver);
   }
   else
   {
      ExpAddWrapped("هنوز برنگشته: "+g_reversal.reason, clrOrange);
      ExpAddWrapped("نکتهٔ مهم: فرسودگی هرگز به‌تنهایی بایاس را عوض نمی‌کند؛ تنها همین دروازه یعنی بسته‌شدن فراتر از سطح حفاظت‌شدهٔ خارجی برگشت را تأیید می‌کند", clrTomato);
   }

   ExpAddWrapped("چه چیزی آن را باطل می‌کند: ساخت رویداد ساختاری تازه‌ای روی همان تایم‌فریم مالک که سطح حفاظت‌شده را جابه‌جا کند؛ در آن حالت شاهد برگشت قبلی دیگر تازه نیست و فقط در تاریخچه می‌ماند", clrTomato);
   ExpAdd("توجه: برگشت تأییدشده معنای «همین حالا بفروش» نیست؛ فقط می‌گوید ساختار حفاظت‌شده در جهت مخالف بسته شده است", clrOrange);
   ExpAddWrapped("کنترل خودت: کندل بستهٔ تایم‌فریم مالک را باز کن؛ اگر قیمت بستهٔ آن فراتر از این سطح است تأیید درست است و اگر فقط فتیله بوده ثبت اشتباه است", clrSilver);
   ExpAdd("REVERSAL — ICT_Assistant_Canonical_Explain.csv", clrSilver);
   ExpAdd("REVERSAL — ICT_Assistant_Canonical_Reversal_Diag.csv", clrSilver);
}

// تشخیص نوع آبجکت از نام و ساخت توضیح
// فاز ۴۴ — پیام واحد «مرجع آبجکت در رجیستری نیست».
// قبلاً هر خانواده در این حالت **بی‌صدا** برمی‌گشت (بدون عنوان و بدون خط)،
// یعنی پنل خالی می‌ماند: آبجکت روی چارت دیده می‌شود، کاربر کلیک می‌کند و
// هیچی نمی‌نویسد. علت معمولش سقف نگه‌داری رجیستری است: آبجکت به‌عنوان تاریخچهٔ
// نمایش (سبک frozen فاز ۱۴) روی چارت می‌ماند ولی مرجعش از رجیستری بیرون افتاده.
// این پیام همان حقیقت را می‌گوید و مسیر کنترل هم می‌دهد.
void ExplainRegistryMiss(string familyFa, string idStr)
{
   g_clickReason="REGISTRY_MISS";
   g_expTitle="OBJECT NOT IN REGISTRY";
   ExpAddWrapped("چیست: این آبجکت روی چارت رسم شده ولی مرجعش در رجیستری فعال پیدا نشد؛ خانواده: "+familyFa, clrOrange);
   ExpAdd("object id from name: "+idStr, clrSilver);
   ExpAddWrapped("چرا: سقف نگه‌داری رجیستری همین خانواده پر شده و قدیمی‌ترین مرجع حذف شده، در حالی که آبجکتش به‌عنوان تاریخچهٔ نمایش روی چارت مانده است", clrSilver);
   ExpAddWrapped("این خطای محاسبه نیست: اعداد همین ناحیه در فایل توضیحات و فایل‌های شاهد باقی می‌مانند؛ فقط نقشهٔ کلیک دیگر به آن مرجع نمی‌رسد", clrSilver);
   ExpAddWrapped("کنترل خودت: سقف نگه‌داری همین خانواده را بالا ببر یا پنجرهٔ تاریخچه را کوتاه کن؛ اگر آبجکت زنده (نه خاکستری) است و باز هم مرجع ندارد، همان شناسهٔ بالا را گزارش کن", clrAqua);
}

//--------------------------------------------------------------------
// فاز ۴۴ — توزیع‌کنندهٔ توضیح. این تابع **به‌تنهایی** پنل نمی‌سازد؛
// تضمین «هیچ‌وقت خالی نباش» را BuildExplanation() اضافه می‌کند.
//--------------------------------------------------------------------
void ExplainDispatchObject(string objName)
{
   string body=objName;
   StringReplace(body,"ICTv13_","");

   if(StringFind(body,"LIQ_")==0)
   {
      string idStr=body;
      StringReplace(idStr,"LIQ_","");
      StringReplace(idStr,"_T","");
      LiquidityObj l;
      if(FindLiquidityById((long)StringToInteger(idStr), l)) ExplainLiquidity(l);
      else ExplainRegistryMiss("سطح نقدینگی", idStr);
      return;
   }
   if(StringFind(body,"SWEEP_")==0)
   {
      string idStr=body; StringReplace(idStr,"SWEEP_","");
      LiquidityObj l;
      if(FindLiquidityById((long)StringToInteger(idStr), l))
      {
         ExplainLiquidity(l);
         ExpAdd(StringFormat("SWEEP — ثبت‌شده در %s", TimeToString(l.sweptTime,TIME_DATE|TIME_MINUTES)), clrOrange);
         ExpAdd("نقدینگی برداشته شد؛ برای تبدیل شدن به ستاپ، جابه‌جایی و شکست ساختار در جهت مخالف جارو لازم است", clrOrange);
      }
      else ExplainRegistryMiss("نشان جاروی نقدینگی", idStr);
      return;
   }
   if(StringFind(body,"EVT")==0)
   {
      string idStr=body; StringReplace(idStr,"EVTL_",""); StringReplace(idStr,"EVT_","");
      StructureEvent e;
      if(FindEventById((long)StringToInteger(idStr), e)) ExplainStructureEvent(e);
      else ExplainRegistryMiss("رویداد ساختاری", idStr);
      return;
   }
   if(StringFind(body,"FVG")==0)
   {
      string idStr=body; StringReplace(idStr,"FVGCE_",""); StringReplace(idStr,"FVG_","");
      FVGObj f;
      if(FindFVGById((long)StringToInteger(idStr), f)) ExplainFVG(f);
      else ExplainRegistryMiss("گپ ارزش منصفانهٔ کوچک", idStr);
      return;
   }
   if(StringFind(body,"OB_")==0)
   {
      string idStr=body; StringReplace(idStr,"OB_","");
      OBObj o;
      if(FindOBById((long)StringToInteger(idStr), o)) ExplainOB(o);
      else ExplainRegistryMiss("اردر بلاک", idStr);
      return;
   }
   if(StringFind(body,"REJECTION_")==0)
   {
      string idStr=body; StringReplace(idStr,"REJECTION_","");
      RejectionObj r;
      if(FindRejectionById((long)StringToInteger(idStr), r)) ExplainRejection(r);
      else ExplainRegistryMiss("بلوک پس‌زدگی", idStr);
      return;
   }
   // فاز ۴۴ — نوار تک‌خطی گوشهٔ چارت (RSTRIP). تنها آبجکتی بود که در فایل
   // توضیحات به پیام جایگزین می‌افتاد (شاهد: Explain.csv قبل از این فاز).
   if(StringFind(body,"RSTRIP")==0)
   {
      ExplainRiskStripObject();
      return;
   }
   // فاز ۴۸: ردیف جداگانهٔ PENDING حذف شد و داخل همان نوار مسیر رفت؛ پس دیگر
   // شاخهٔ کلیک مستقل ندارد. متن آن بخش هنوز از همان ماژولی می‌آید که عدد را
   // محاسبه می‌کند و از داخل ExplainRiskStripObject صدا زده می‌شود تا یک کلیک،
   // یک پنل و یک روایت بدهد.
   if(StringFind(body,"SESS_")==0)
   {
      string rest=body;
      StringReplace(rest,"SESS_","");
      int pos=StringFind(rest,"_");
      if(pos>0)
      {
         string kind=StringSubstr(rest,0,pos);
         string dayStr=StringSubstr(rest,pos+1);
         ExplainSessionBox(kind,(int)StringToInteger(dayStr));
      }
      return;
   }
   if(StringFind(body,"MTF_")==0)
   {
      string rest=body; StringReplace(rest,"MTF_","");
      bool isHigh=true;
      int len=StringLen(rest);
      string tag=rest;
      if(len>=2)
      {
         string suffix=StringSubstr(rest,len-2,2);
         if(suffix=="_H"){ isHigh=true;  tag=StringSubstr(rest,0,len-2); }
         else if(suffix=="_L"){ isHigh=false; tag=StringSubstr(rest,0,len-2); }
      }
      for(int i=0;i<6;i++)
         if(EnumToString(g_mtfTimeframes[i])==tag){ ExplainMTFLevel(i,isHigh); return; }
      ExpAdd(tag+" — سطح تایم‌فریم (در رجیستری متن‌فریم ثبت نشده)", clrWhite);
      return;
   }
   if(StringFind(body,"SETUP")==0)
   {
      ExplainSetup();
      return;
   }
   if(StringFind(body,"DOL_")==0)
   {
      ExplainDOL();
      return;
   }
   if(StringFind(body,"LOCATION_")==0)
   {
      ExplainLocation(StringSubstr(body,9));
      return;
   }
   // فاز ۳۶: برچسب Price Delivery — مسیر همان ExplainLocation است (یک حقیقت)
   // فاز ۱۱: دروازهٔ برگشت و تأییدیهٔ برگشت
   if(StringFind(body,"REVERSAL")==0)
   {
      ExplainReversal();
      return;
   }
   // فاز ۱۲: نقدینگی مورب و رجیستری POI
   if(StringFind(body,"TRENDLINE_")==0)
   {
      string tlId=body; StringReplace(tlId,"TRENDLINE_","");
      ExplainTrendline((long)StringToInteger(tlId));
      return;
   }
   if(StringFind(body,"POI_BEST")==0)
   {
      ExplainBestPOI();
      return;
   }
   // فاز ۳۶: Quarterly Theory — کلیک روی خطوط True Open
   // فاز ۳۶: AMD قیمتی — توضیح مستقل (کلیک روی سطر داشبورد یا آبجکت آینده)
   if(StringFind(body,"AMD_PRICE")==0)
   {
      g_expTitle="AMD PRICE (Power of Three)";
      ExpAddWrapped(g_amdPriceNote==""? "رنج آسیا هنوز ثبت نشده و رفتار قیمت در قالب انباشت، دستکاری و توزیع قابل بیان نیست": g_amdPriceNote, clrWhite);
      ExpAddWrapped("تفکیک زمانی از قیمتی: نگاشت سشنی (آسیا انباشت، لندن دستکاری، نیویورک توزیع) فقط زمان‌بندی است؛ این بخش رفتار واقعی قیمت را می‌سنجد: جاروی بیرون رنج آسیا همان دستکاری است و حرکت انبساطی مخالف آن همان توزیع", clrAqua);
      ExpAdd("Source: ICT Power of Three + AMD-X in Quarterly Theory", clrSilver);
      return;
   }
   if(StringFind(body,"QT_DAYOPEN")==0){ ExplainQT(false); return; }
   if(StringFind(body,"QT_WKOPEN")==0){ ExplainQT(true);  return; }
   // فاز ۳۶: Brooks Range / Measured Move
   if(StringFind(body,"BROOKS_TR")==0 || StringFind(body,"BROOKS_MM")==0){ ExplainBrooks(); return; }
   // فازهای ۱۶–۲۱: hover فارسی خانواده‌های جدید
   if(StringFind(body,"WYCK_")==0)
   {
      string wid=body; StringReplace(wid,"WYCK_","");
      long want=(long)StringToInteger(wid);
      for(int i=0;i<ArraySize(g_wyck);i++)
         if(g_wyck[i].id==want){ ExplainWyckoff(g_wyck[i]); return; }
      g_expTitle="WYCKOFF"; ExpAddWrapped("این رویداد در رجیستری پیدا نشد (ممکن است پنجرهٔ نگاه‌عقب گذشته باشد)", clrOrange);
      return;
   }
   if(StringFind(body,"SD_")==0)
   {
      string zid=body; StringReplace(zid,"SD_","");
      long want=(long)StringToInteger(zid);
      for(int i=0;i<ArraySize(g_sd);i++)
         if(g_sd[i].id==want){ ExplainSD(g_sd[i]); return; }
      g_expTitle="S/D"; ExpAdd("این ناحیه در رجیستری پیدا نشد (با سقف نگه‌داری از رجیستری بیرون افتاده است)", clrOrange);
      return;
   }
   if(StringFind(body,"BROOKS")==0){ ExplainBrooks(); return; }
   if(StringFind(body,"RTM_")==0)   // فاز ۳۴: توضیح مخصوص همان رویداد RTM
   {
      string rid=body; StringReplace(rid,"RTM_","");
      long want=(long)StringToInteger(rid);
      for(int i=0;i<ArraySize(g_rtm);i++)
         if(g_rtm[i].id==want){ ExplainRTMEvent(g_rtm[i]); return; }
      ExplainRTM(); return;
   }
   if(StringFind(body,"RTM")==0){ ExplainRTM(); return; }
   if(StringFind(body,"PROF")==0){ ExplainProfile(); return; }

}

//====================================================================
// فاز ۴۴ — تضمین «نام + دلیل» برای هر کلیک
//====================================================================
// قرار پروژه: هر چیزی که روی صفحه دیده می‌شود باید بگوید چیست و چرا شکل
// گرفته. یک راه نقض این قرار که هیچ ابزار بیرونی نمی‌تواند بگیرد، همین
// است: کاربر روی آبجکت کلیک کند و پنل **هیچ چیز** ننویسد. سه راه رخ دادنش:
//   ۱) پیشوند نام آبجکت در زنجیرهٔ تشخیص نباشد،
//   ۲) نام باشد ولی مرجعش از رجیستری حذف شده باشد (سقف نگه‌داری)،
//   ۳) شاخه توضیح را برگرداند ولی هیچ خطی نساخته باشد.
// سه لایهٔ زیر این هر سه حالت را به یک پیام صادقانه تبدیل می‌کنند:
//   ExplainDispatchObject  → تشخیص خانواده
//   ExplainUnknownObject   → پیام لایهٔ ناشناخته (تعویض/کدگذاری)
//   ExplainFrozenNote      → نگه‌داشتهٔ تاریخچه روی چارت
// و در آخر، عنوان هم اگر خالی مانده باشد از نام آبجکت ساخته می‌شود تا
// کاربر بداند کلیک او کجا خورده است.
void ExplainUnknownObject(string objName)
{
   string body=objName;
   StringReplace(body,"ICTv13_","");
   if(g_expTitle=="") g_expTitle="OBJECT "+body;
   ExpAddWrapped("چیست: این آبجکت روی چارت رسم شده ولی توضیح تخصصی برای لایهٔ آن ثبت نشده است؛ یعنی نام آبجکت با هیچ خانوادهٔ شناخته‌شده هم‌خوان نشد", clrOrange);
   ExpAdd("obj internal name: ICTv13_"+body, clrSilver);
   ExpAddWrapped("دلیل ممکن یکم: شناسهٔ داخل نام آبجکت با شناسهٔ داخلی رجیستری هم‌خوان نیست", clrSilver);
   ExpAddWrapped("دلیل ممکن دوم: این آبجکت خانوادهٔ تازه‌ای است که مسیر توضیحش تکمیل نشده؛ اگر زنده و قابل کلیک است همین را گزارش کن", clrTomato);
   ExpAddWrapped("کنترل خودت: نام آبجکت را از فهرست آبجکت‌های چارت بردار و ببین همان عددی را دارد که در فایل توضیحات نوشته شده یا نه", clrAqua);
}

// فاز ۱۴: آبجکتی که به‌سبک frozen نگه داشته شده، باید بالای پنل بگوید چرا
// خاکستری/نقطه‌چین است، تا کاربر آن را با «خطای محاسبه» اشتباه نگیرد.
void ExplainFrozenNote(string objName)
{
   if(ArraySize(g_expLines)==0) return;
   if(IndexInNameList(g_frozen,objName)<0) return;
   int n=ArraySize(g_expLines);
   ArrayResize(g_expLines,n+1);
   for(int i=n;i>0;i--) g_expLines[i]=g_expLines[i-1];
   // فاز ۴۴: این متن قبلاً یک ردیف ۲۶۲ نویسه‌ای بود و از سقف ۲۶۰ نویسه رد
   // می‌شد (با انتقالش به تابع مستقل، ابزار سنجش طول ردیف آن را دید). حالا
   // به دو ردیف کوتاه‌تر شکسته شده تا در پنل با عرض واقعی بریده نشود.
   g_expLines[0]=StringFormat("FROZEN HISTORY: این آبجکت دادهٔ معتبر دارد ولی از پنجرهٔ نمایش فعلی بیرون افتاده است (سقف %d ناحیه / %d سطح)",
                              InpMaxDrawnZones, InpMaxDrawnLevels);
   ArrayResize(g_expLineColors,n+1);
   for(int i=n;i>0;i--) g_expLineColors[i]=g_expLineColors[i-1];
   g_expLineColors[0]=clrDimGray;
   int m=ArraySize(g_expLines);
   ArrayResize(g_expLines,m+1);
   ArrayResize(g_expLineColors,m+1);
   g_expLines[m]="بی‌صدا حذف نشد؛ فقط رنگ خاکستری و خط نقطه‌چین گرفت تا با اشیای زنده قاطی نشود — اگر دوباره داخل پنجرهٔ نمایش برگردد، رنگ و خط اصلی خودکار برمی‌گردد";
   g_expLineColors[m]=clrSilver;
}

// هستهٔ توضیح: توزیع + تضمین، **بدون** شمارنده.
// آزمون خودکار کلیک هم همین تابع را صدا می‌زند تا شمارنده‌های کلیک کاربر با
// هزاران فراخوانی آزمون آلوده نشوند.
ENUM_CLICK_RESOLVE ExplainBuildDetailed(string objName)
{
   g_clickReason="";
   ExplainDispatchObject(objName);
   if(ArraySize(g_expLines)==0)      // سه راه بالا، یک نتیجه
   {
      // اگر خود توزیع‌کننده دلیل را گفته باشد (مرجع از رجیستری بیرون افتاده)
      // همان حفظ می‌شود؛ وگرنه این یک خانوادهٔ ناشناخته است که باید دیده شود.
      if(g_clickReason=="") g_clickReason="NO_HANDLER";
      ExplainUnknownObject(objName);
      ExplainFrozenNote(objName);
      return CLICK_RS_FALLBACK;
   }
   if(g_expTitle=="") g_expTitle="OBJECT "+objName;
   if(g_clickReason=="") g_clickReason="RESOLVED";
   ExplainFrozenNote(objName);
   return CLICK_RS_OK;
}

void BuildExplanation(string objName)
{
   g_clickResolve=ExplainBuildDetailed(objName);
   g_clickCount++;
   if(g_clickResolve==CLICK_RS_OK) g_clickOk++; else g_clickFallback++;
   g_clickLastHit=objName;
   g_clickLastTitle=g_expTitle;
}

//====================================================================
// فاز ۴۴ — توضیح نوار تک‌خطی گوشهٔ چارت (RISK STRIP)
//====================================================================
// این تنها آبجکتی بود که در ICT_Assistant_Canonical_Explain.csv به پیام
// جایگزین می‌افتاد (شاهد از اجرای واقعی: `ICTv13_RSTRIP_TXT` با عنوان
// OBJECT RSTRIP_TXT) — یعنی کاربر روی همان نوار کلیک می‌کرد و دلیل امتیاز
// را نمی‌گرفت. متن نوار، خلاصهٔ چهار شاهد است؛ اینجا همان چهار شاهد
// به تفکیک توضیح داده می‌شوند تا امتیاز قابل بازمحاسبه باشد.
//
// فاز ۴۸ — این نوار دیگر فقط «ریسک برگشت» نیست: ردیف درجهٔ سیگنال و ردیف
// سناریوی در انتظار در همین یک خط ادغام شدند. پس یک کلیک باید **هر دو** روایت
// را بدهد: بخش اول کیفیت سیگنال، بخش دوم مقصد نقدینگی و شرط برگشت. تفکیک
// دو پنل برای یک ردیف، همان چیزی بود که کاربر مجبور می‌شد دو بار کلیک کند.
void ExplainRiskStripObject()
{
   g_expTitle="SIGNAL STRIP — خط مسیر: درجه، سطح، مقصد و شرط برگشت";
   ExpAddWrapped("چیست: این نوار یک خط خواندنی است، نه سیگنال — سر ردیف درجهٔ هم‌جهتی با بایاس است و بقیه شواهد همان کندل بسته را نشان می‌دهد", clrWhite);
   // فاز ۴۶: توضیح درجه. عدد برد، اندازه‌گیری‌شده روی نمونهٔ همین نماد است و
   // تعداد نمونه هم کنارش می‌آید تا کسی آن را وعدهٔ درصد نگیرد.
   ExpAddWrapped("درجه چطور ساخته شد: مجموع هفت شاهد سنجیده‌شده روی کندل بسته (خانوادهٔ نزدیک‌ترین سطح، فاصله تا آن سطح، جای قیمت در لگ، فاصله تا هدف نقدینگی، همسویی تایم‌فریم‌ها، جاروی نقدینگی، وضعیت فرسودگی)", clrAqua);
   ExpAdd(StringFormat("why: %s", g_gradeWhy), clrAqua);
   ExpAddWrapped("معنی عدد برد: درصدی که همین درجه در گذشتهٔ ثبت‌شدهٔ همین نماد به هدف رسیده؛ یک اندازه‌گیری است، نه وعده — و تعداد نمونه‌اش کنارش نوشته می‌شود", clrSilver);
   ExpAddWrapped("رنگ نوار: سبز = درجهٔ بالا، طلایی = متوسط، خاکستری = درجهٔ پایین؛ رنگ دربارهٔ کیفیت هم‌جهتی حرف می‌زند، نه دربارهٔ جهت", clrSilver);
   ExpAdd(StringFormat("family: %s", g_gradeFam), clrSilver);
   ExpAddWrapped("چطور خودت بسنجی: با ابزار سنجش همین مخزن، درجه و برد را از فایل ریسک برگشت بازتولید کن؛ اگر با هم نخواند، حساب غلط است", clrAqua);
   // ردیف کدهای نوار، تمام‌لاتین می‌ماند (قاعدهٔ فاز ۴۲: یک ردیف یا فقط لاتین،
   // یا لاتینش ابتدای همان ردیف). معنی هر کد در ردیف فارسی بعدی می‌آید.
   ExpAdd(StringFormat("grade: %s | score: %.2f | win: %.1f%% | n: %d",
           g_grade, g_gradeScore, g_gradeWin, g_gradeN), clrAqua);
   ExpAdd(StringFormat("bias: %s | level: %s | state: %s | score: %d/100",
           DirToStr(g_htfBias), g_rrLevel, g_rrLevelState, g_rrScore), clrAqua);
   ExpAdd(StringFormat("فاصله تا نزدیک‌ترین سطح: %.2f برابر میانگین دامنه  |  پیشرفت در لگ: %.0f درصد  |  فاصله تا هدف نقدینگی: %.2f برابر میانگین دامنه",
           g_rrLevelDist, g_rrLegProg, g_rrDolDist), clrAqua);
   ExpAdd("معنی کدهای بالا: سطح = نزدیک‌ترین سطح به قیمت، وضعیت = وضعیت همان سطح، امتیاز از ۱۰۰", clrSilver);
   if(g_hasDOL)
      ExpAdd("target: "+g_currentDOL.typeName+" @ "+DoubleToString(g_currentDOL.price,_Digits), clrSilver);
   // امتیاز، مجموع وزن‌های مستند است؛ فهرست شواهد از همان منبعی می‌آید که
   // نوار را ساخته، نه از یک محاسبهٔ موازی.
   ExpAddWrapped("چطور ساخته شد: امتیاز مجموع وزن‌های شاهدهای زیر است (وزن‌ها در ورودی‌های همان ماژول ثبت شده‌اند و «درصد» نیستند)", clrAqua);
   if(g_rrReasons=="") ExpAdd("evidence list: (خالی — هنوز هیچ شاهدی وزن نگرفته)", clrSilver);
   else ExpAdd("evidence list: "+g_rrReasons, clrSilver);
   ExpAdd("دریافت‌شده از آخرین کندل بسته — چند کندل از آخرین رویداد ساختاری گذشته: "+IntegerToString(g_rrEventBarsAgo), clrSilver);
   ExpAddWrapped("نقدینگی سمت بایاس در همین کندل جارو شد و پشت سطح بسته شد: "+(g_barSweptTowardBias? "بله — این یک شاهد برگشت است":"خیر"),
                 g_barSweptTowardBias? clrOrange : clrSilver);
   ExpAddWrapped("چرا مهم است: قبل از ورود هم‌جهت، این نوار می‌گوید خطر برگشت چقدر بالا رفته و نزدیک‌ترین سطح مقابل کجاست — پس می‌شود فهمید «ورود در جهت روند» در نقطه‌ای است که برگشت هم شواهد دارد یا نه", clrLime);
   ExpAddWrapped("چه چیزی آن را بی‌اعتبار می‌کند: اگر بایاس مالک یا نزدیک‌ترین سطح عوض شود، همهٔ اعداد همین نوار در همان کندل بسته بازحساب می‌شوند", clrOrange);
   ExpAddWrapped("کنترل خودت: همین اعداد را در فایل ریسک برگشت بگیر و با شاهدهای چارت بسنج؛ اگر امتیاز با شواهد نمی‌خواند، فهرست شواهد را نگاه کن", clrAqua);
   ExpAdd("reverse-risk report: ICT_Assistant_Canonical_ReverseRisk_<symbol>_<tf>.csv", clrSilver);
   // بخش دوم همان ردیف: مسیر و شرط برگشت. keepTitle=true تا عنوان بالا نماند
   // و هر دو روایت در یک پنل دیده شوند.
   ExplainPendingScenario(true);
   ExpAdd("object name: ICTv13_RSTRIP_TXT (read-only row, not draggable)", clrSilver);
}

// یک ردیف EDIT فقط‌خواندنی، راست‌چین، با پس‌زمینه و border مشکی تا هیچ
// درز/خط افقی دیده نشود. این همان کنترل native است که رندر درست متن خام
// فارسی با آن قبلاً تأیید شده است؛ فقط حالا یک ردیف به‌جای کل متن.
void ExplainEditRow(string name, int x, int y, int w, int h, string text, color clr, int fontSize)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_EDIT,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_FONT,InpExplainFont);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fontSize);
   ObjectSetInteger(0,name,OBJPROP_ALIGN,ALIGN_RIGHT);
   ObjectSetInteger(0,name,OBJPROP_READONLY,true);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,clrBlack);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,clrBlack);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

// ---------------- رندر پنل چندخطی ----------------
// هر خط توضیح یک OBJ_EDIT مستقل و پشت‌سرهم (بدون فاصله) است.
// OBJ_EDIT تک‌خطی است، پس نسخهٔ قبلی که همهٔ خطوط را در یک EDIT می‌ریخت
// همهٔ خطوط بعد از اولی را از بین می‌برد. رنگ هر خط هم حفظ می‌شود.
void RenderExplainPanel()
{
   int total=ArraySize(g_expLines);
   if(!InpShowExplainPanel || total==0)
   {
      for(int i=0;i<=g_expPanelRows;i++) ObjectDelete(0,"ICTv13_EXP_"+IntegerToString(i));
      ObjectDelete(0,"ICTv13_EXP_TEXT");   // باقی‌ماندهٔ نسخهٔ تک‌EDIT قبلی
      ObjectDelete(0,"ICTv13_EXP_BG");
      g_expPanelRows=0;
      ChartRedraw(0);
      return;
   }
   if(total>InpExplainMaxRows) total=InpExplainMaxRows;

   int lineH   = InpExplainFontSize+11;
   int padX    = 6;
   int padY    = 6;
   int rows    = total+1;                       // عنوان + خطوط توضیح
   int height  = rows*lineH + padY*2;
   int chartW  = (int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
   int chartH  = (int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   int xPos    = g_expAnchorX+18;
   int yPos    = g_expAnchorY-20;
   if(xPos+InpExplainPanelWidth>chartW-10) xPos=MathMax(5,g_expAnchorX-InpExplainPanelWidth-18);
   if(yPos+height>chartH-10)              yPos=MathMax(5,chartH-height-10);
   if(yPos<5) yPos=5;

   string bg="ICTv13_EXP_BG";
   if(ObjectFind(0,bg)<0) ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bg,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,xPos);
   ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,yPos);
   ObjectSetInteger(0,bg,OBJPROP_XSIZE,InpExplainPanelWidth);
   ObjectSetInteger(0,bg,OBJPROP_YSIZE,height);
   ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,clrBlack);
   ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,bg,OBJPROP_COLOR,PAL_PANEL_BORDER);
   ObjectSetInteger(0,bg,OBJPROP_BACK,false);
   ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,bg,OBJPROP_HIDDEN,true);

   int editX = xPos+padX;
   int editW = InpExplainPanelWidth-padX*2;

   // ردیف ۰: عنوان
   ExplainEditRow("ICTv13_EXP_0", editX, yPos+padY, editW, lineH,
                  RenderLine(g_expTitle,InpExplainRenderMode), clrGold, InpExplainFontSize+1);

   // ردیف‌های ۱..total: هر خط مستقل، راست‌چین، با رنگ خودش
   for(int i=0;i<total;i++)
      ExplainEditRow("ICTv13_EXP_"+IntegerToString(i+1), editX, yPos+padY+(i+1)*lineH, editW, lineH,
                     RenderLine(g_expLines[i],InpExplainRenderMode), g_expLineColors[i], InpExplainFontSize);

   g_expPanelRows=total+1;   // تعداد واقعی ردیف‌های EXP_ ساخته‌شده (۰..total)

   // بدنِ تک‌EDIT قدیمی و ردیف‌های مانده از رندر قبلی را پاک کن
   ObjectDelete(0,"ICTv13_EXP_TEXT");
   for(int k=total+1;k<=InpExplainMaxRows+2;k++)
      ObjectDelete(0,"ICTv13_EXP_"+IntegerToString(k));

   ChartRedraw(0);
}

// ---------------- ذخیرهٔ توضیح‌ها در CSV برای بررسی عددی ----------------
void ExplainSaveCsv()
{
   int h=FileOpen("ICT_Assistant_Canonical_Explain.csv",FILE_COMMON|FILE_WRITE|FILE_CSV|FILE_UNICODE,';');
   if(h==INVALID_HANDLE) return;
   FileWrite(h,"Object","Kind","Price","Time","Summary");

   string savedTitle=g_expTitle;
   string savedLines[]; color savedColors[];
   int nSaves=ArraySize(g_expLines);
   ArrayResize(savedLines,nSaves); ArrayResize(savedColors,nSaves);
   for(int i=0;i<nSaves;i++){ savedLines[i]=g_expLines[i]; savedColors[i]=g_expLineColors[i]; }

   int total=ObjectsTotal(0,-1,-1);
   int written=0;
   for(int i=0;i<total && written<(InpMaxDrawnLevels+InpMaxDrawnZones*3+60);i++)
   {
      string nm=ObjectName(0,i,-1,-1);
      if(StringFind(nm,"ICTv13_")!=0) continue;
      if(StringFind(nm,"ICTv13_DASH_")==0) continue;
      if(StringFind(nm,"ICTv13_EXP_")==0)  continue;
      long otype=ObjectGetInteger(0,nm,OBJPROP_TYPE);
      if(otype==OBJ_RECTANGLE_LABEL||otype==OBJ_LABEL) continue;   // داشبورد و پنل

      ExpClear();
      BuildExplanation(nm);
      if(ArraySize(g_expLines)==0) continue;

      double price=0.0;
      datetime t=0;
      if(otype==OBJ_HLINE) price=ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
      else
      {
         price=ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
         t=(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,0);
      }
      string summary="";
      for(int k=0;k<ArraySize(g_expLines);k++)
      {
         summary += g_expLines[k];
         if(k<ArraySize(g_expLines)-1) summary += " ~ ";
      }
      FileWrite(h,nm,g_expTitle,DoubleToString(price,_Digits),
                t>0? TimeToString(t,TIME_DATE|TIME_MINUTES) : "", summary);

      // فاز ۲۲: متن آموزشی کوتاه به‌صورت tooltip روی خود آبجکت.
      // این مسیر مستقل از پنل EDIT است: حتی اگر پنل بسته/جابه‌جا باشد،
      // خودِ آبجکت توضیح می‌دهد. هر خط جداگانه با شکل‌دهی دستی و ترتیب
      // بصری رندر می‌شود تا در رندرگر بدون bidi هم حروف جدا نشوند و
      // ترتیب کلمات برنگردد. خطوط با \n به tooltip چندخطی تبدیل می‌شوند.
      // فاز ۲۵ — یک مسیر رندر واحد: پنل و tooltip هر دو از RenderLine عبور
      // می‌کنند. tooltip متن خام منطقی را برعکس نشان می‌داد (رندرگر ترمینال
      // همان مسیری است که bidi/shaping را برای آبجکت‌های متنی از دست داده —
      // گزارش انجمن MQL5 ۵۰۴۵۲۲)؛ با یکسان‌کردن مسیر، تنها تنظیم لازم برای هر
      // دو سطح InpExplainRenderMode است. متن خالی هم همیشه نوشته می‌شود تا با
      // خاموش‌کردن ورودی، tooltip کهنهٔ همان آبجکت پاک شود.
      string tip="";
      if(InpSetObjectTooltips)
      {
         tip=RenderLine(g_expTitle,InpExplainRenderMode);
         for(int k=0;k<ArraySize(g_expLines) && k<3;k++)
            tip += "\n" + RenderLine(g_expLines[k],InpExplainRenderMode);
         if(InpExplainTooltipMaxChars>0 && StringLen(tip)>InpExplainTooltipMaxChars)
            tip=StringSubstr(tip,0,InpExplainTooltipMaxChars)+"...";
      }
      ObjectSetString(0,nm,OBJPROP_TOOLTIP,tip);
      written++;
   }
   FileClose(h);

   // بازگرداندن پنل فعلی (اگر بازیابی نشود، توضیح روی‌موس از دست می‌رفت)
   ArrayResize(g_expLines,nSaves);
   ArrayResize(g_expLineColors,nSaves);
   for(int i=0;i<nSaves;i++){ g_expLines[i]=savedLines[i]; g_expLineColors[i]=savedColors[i]; }
   g_expTitle=savedTitle;
}

// فاز ۲۵: اگر هر دو کانال توضیح خاموش باشند (نه CSV، نه tooltip) ولی پیش‌تر
// tooltip روشن بوده، tooltipهای کهنه یک‌بار پاک می‌شوند تا روی چارت نمانند.
void ExplainClearStaleTooltips()
{
   static bool done=false;
   if(done) return;
   done=true;
   int total=ObjectsTotal(0,-1,-1);
   for(int i=0;i<total;i++)
   {
      string nm=ObjectName(0,i,-1,-1);
      if(StringFind(nm,"ICTv13_")!=0) continue;
      ObjectSetString(0,nm,OBJPROP_TOOLTIP,"");
   }
}

// ---------------- تشخیصی فاز ۸: دیکشنری وضعیت FVG (فقط-خواندنی) ----------------
// هر FVG رجیستری را با عمر، وضعیت و زمان اولین لمس می‌نویسد تا پرسش
// «چرا هیچ FVG ای FRESH نیست» با داده پاسخ بگیرد، نه با حدس.
// منطق تشخیصی هیچ تغییری نمی‌کند؛ این تابع فقط یک CSV در Common\Files می‌سازد.
void PersistFVGDictionary()
{
   int h=FileOpen("ICT_Assistant_Canonical_FVG_Diag.csv",FILE_COMMON|FILE_WRITE|FILE_CSV|FILE_UNICODE,';');
   if(h==INVALID_HANDLE) return;
   // فاز ۴۳: «Dir» به «DirBirth» تغییر نام داد و ستون‌های Role/ActiveDir/InvertedAt
   // اضافه شدند. دلیل: یک ستون به اسم Dir که هم جهت تولد و هم (پیش‌تر) جهت بازنویسی‌شده
   // را نگه می‌داشت، همان منبع تناقض بود؛ حالا هیچ عددی در این فایل دو معنی ندارد.
   FileWrite(h,"Id","DirBirth","Time","AgeBars","Top","Bottom","Causal",
             "Mitigated","Inverted","InvertedAt","Role","ActiveDir","Invalidated","TouchTime","BarsToTouch","BirthBarTouch");
   int secs=PeriodSeconds(PERIOD_CURRENT);
   if(secs<=0) secs=60;
   datetime now=(datetime)TimeCurrent();
   for(int i=0;i<ArraySize(g_fvgs);i++)
   {
      FVGObj f=g_fvgs[i];
      int ageBars=(f.createdTime>0)? (int)((now-f.createdTime)/secs) : 0;
      int barsToTouch=(f.touchTime>0 && f.createdTime>0)? (int)((f.touchTime-f.createdTime)/secs) : -1;
      FileWrite(h,IdToStr(f.id),
                (f.direction==DIR_BULL?"BULL":"BEAR"),
                TimeToString(f.time,TIME_DATE|TIME_MINUTES),
                ageBars,
                DoubleToString(f.top,_Digits),
                DoubleToString(f.bottom,_Digits),
                (f.causal?"1":"0"),
                (f.mitigated?"1":"0"),
                (f.inverted?"1":"0"),
                f.invertedTime>0? TimeToString(f.invertedTime,TIME_DATE|TIME_MINUTES): "",
                FVGPolarityReport(f),
                (FVGActiveDir(f)==DIR_BULL?"BULL":"BEAR"),
                (f.invalidated?"1":"0"),
                f.touchTime>0? TimeToString(f.touchTime,TIME_DATE|TIME_MINUTES): "",
                barsToTouch,
                (f.birthBarTouch?"1":"0"));
   }
   FileClose(h);
}

// دیکشنری لگ واقعی + سطوح مکان (فاز ۱۰). پیوت‌های خام (قیمت دو سر لگ) هم
// نوشته می‌شوند تا بتوان همهٔ اعداد (EQ/OTE/طلایی) را از دادهٔ خام به‌صورت
// مستقل بازمحاسبه کرد؛ ابزار: tools/Validate-DealingLeg.ps1
void PersistLegDictionary()
{
   int h=FileOpen("ICT_Assistant_Canonical_Leg_Diag.csv",FILE_COMMON|FILE_WRITE|FILE_CSV|FILE_UNICODE,';');
   if(h==INVALID_HANDLE) return;
   FileWrite(h,"Time","Symbol","ChartTF","LegValid","Reject","LegDir","StartTime","StartPrice",
             "EndTime","EndPrice","Low","High","Range","SizeATR","ATR","EQ","OTELow","OTEHigh","Golden",
             "AnalysisClose","Side","StopsLevelPts","MinLegATRInput","OTELowInput","OTEHighInput","GoldenInput",
             "SetupStatus","Entry","SL","TP3","Risk","RR","ZoneSource","ChainSweep","ChainEvent","ChainDisp");
   double range=g_leg.range;
   double oteLow=0, oteHigh=0, golden=0;
   if(g_leg.valid)
   {
      if(g_leg.dir==DIR_BULL)
      {
         oteLow  = g_leg.high - range*InpOTE_High;
         oteHigh = g_leg.high - range*InpOTE_Low;
         golden  = g_leg.high - range*InpOTE_Golden;
      }
      else
      {
         oteLow  = g_leg.low + range*InpOTE_Low;
         oteHigh = g_leg.low + range*InpOTE_High;
         golden  = g_leg.low + range*InpOTE_Golden;
      }
   }
   FileWrite(h,TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES), _Symbol, EnumToString(PERIOD_CURRENT),
             (g_leg.valid?"1":"0"), g_leg.reject, DirToStr(g_leg.dir),
             g_leg.startTime>0? TimeToString(g_leg.startTime,TIME_DATE|TIME_MINUTES):"",
             DoubleToString(g_leg.startPrice,_Digits),
             g_leg.endTime>0? TimeToString(g_leg.endTime,TIME_DATE|TIME_MINUTES):"",
             DoubleToString(g_leg.endPrice,_Digits),
             DoubleToString(g_leg.low,_Digits), DoubleToString(g_leg.high,_Digits),
             DoubleToString(range,_Digits), DoubleToString(g_leg.sizeATR,3), DoubleToString(g_analysisATR,_Digits),
             DoubleToString(g_leg.eq,_Digits), DoubleToString(oteLow,_Digits), DoubleToString(oteHigh,_Digits),
             DoubleToString(golden,_Digits),
             DoubleToString(g_analysisClose,_Digits),
             (g_leg.valid && g_analysisClose>=g_leg.eq)?"PREMIUM":"DISCOUNT",
             (int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
             DoubleToString(InpMinLegATR,3), DoubleToString(InpOTE_Low,3), DoubleToString(InpOTE_High,3), DoubleToString(InpOTE_Golden,3),
             g_setup.status, DoubleToString(g_setup.entry,_Digits), DoubleToString(g_setup.sl,_Digits),
             DoubleToString(g_setup.tp3,_Digits), DoubleToString(g_setup.risk,_Digits), DoubleToString(g_setup.rr,4),
             g_setup.zoneSource, IdToStr(g_setup.chainSweepId), IdToStr(g_setup.chainEventId), IdToStr(g_setup.chainDispId));
   FileClose(h);
}

// ---------------- رویدادهای چارت: باز/بستن پنل آموزشی ----------------
// مشترک بین دو حالت (کلیک و hover).
void ExplainOpenAt(int mx, int my)
{
   string hit=HitTestExplainObject(mx,my);
   if(hit==g_expHovered) return;          // هدف عوض نشده: پنل همان‌طور بماند
   g_expHovered=hit;
   ExpClear();
   if(hit=="")
   {
      RenderExplainPanel();               // فضای خالی → بستن
      return;
   }
   g_expAnchorX=mx;
   g_expAnchorY=my;
   BuildExplanation(hit);
   RenderExplainPanel();
}

void ExplainClosePanel()
{
   if(g_expHovered=="") return;
   g_expHovered="";
   ExpClear();
   RenderExplainPanel();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // ---- فاز ۲۷ (طراحی پروژه): مسیر پیش‌فرض «کلیک» است ----
   // CHARTEVENT_CLICK: lparam = X و dparam = Y کلیک.
   if(id==CHARTEVENT_CLICK)
   {
      if(InpExplainOpen!=EXPLAIN_OPEN_CLICK) return;
      if(!InpShowExplainPanel) return;
      int cx=(int)lparam, cy=(int)dparam;
      if(cx<0 || cy<0) return;
      string hit=HitTestExplainObject(cx,cy);
      if(hit!="" && hit==g_expHovered)
      {
         ExplainClosePanel();        // کلیک دوباره روی همان آبجکت = بستن
         return;
      }
      ExplainOpenAt(cx,cy);          // آبجکت جدید، یا فضای خالی (= بستن)
      return;
   }

   // ESC = بستن پنل در هر دو حالت.
   if(id==CHARTEVENT_KEYDOWN && lparam==27)
   {
      ExplainClosePanel();
      return;
   }

   // ---- حالت اختیاری HOVER (پیش‌فرض نیست؛ فقط اگر کاربر خودش بخواهد) ----
   if(id!=CHARTEVENT_MOUSE_MOVE) return;
   if(InpExplainOpen!=EXPLAIN_OPEN_HOVER) return;
   int mx=(int)lparam;
   int my=(int)dparam;
   if(mx<0 || my<0)
   {
      ExplainClosePanel();
      return;
   }
   ExplainOpenAt(mx,my);
}

//====================================================================
// فاز ۴۴ — آزمون مسیر کلیک بدون موس
//====================================================================
// مشکل واقعی: مسیر کلیک هیچ تست خودکاری نداشت. ابزارهای PowerShell فقط متن
// سورس را grep می‌کنند (و ثابت می‌کنند «رشته هست»)، ولی این مسیر سه مرحلهٔ
// زمان‌اجرا دارد که هیچ‌کدام با grep سنجیده نمی‌شود:
//   ۱) hit-test پیکسلی: تبدیل قیمت/زمان به پیکسل و انتخاب درست آبجکت
//   ۲) پیدا شدن مرجع آبجکت در رجیستری (شناسهٔ داخل نام)
//   ۳) ساخته شدن متن توضیح برای همان مرجع
// این آزمون دقیقاً همین سه مرحله را با همان توابع زنده اجرا می‌کند: برای هر
// آبجکت قابل‌کلیک روی چارت، مرکز پیکسلی‌اش را با همان helperهایی حساب می‌کند
// که خود hit-test استفاده می‌کند، بعد همان `HitTestExplainObject` را صدا
// می‌زند و در پایان همان سازندهٔ پنل. نتیجه در CSV شاهد می‌نشیند.
//
// آزمون در پایان بازسازی اجرا می‌شود: آن لحظه آبجکت‌ها روی چارت هستند و هیچ
// کلیکی رخ نداده، پس آزمایش روی تحلیل زنده اثر ندارد. در پایان پنل پاک می‌شود.

// مرکز پیکسلی یک آبجکت، با همان مسیر تبدیل hit-test (نه یک مسیر موازی).
bool ClickTestCenterOf(string nm, int chartH, double refPrice, datetime tVis, int &cx, int &cy)
{
   cx=0; cy=0;
   long otype=ObjectGetInteger(0,nm,OBJPROP_TYPE);
   if(otype==OBJ_HLINE)
   {
      double p=ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
      if(p<=0.0) return false;
      if(!ExplainTimeToX(tVis,cx)) return false;
      cy=ExplainPriceToY(tVis,p,refPrice,chartH);
      return true;
   }
   datetime t0=(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,0);
   datetime t1=(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,1);
   double   p0=ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
   double   p1=ObjectGetDouble(0,nm,OBJPROP_PRICE,1);
   if(otype==OBJ_TEXT)
   {
      if(!ExplainTimeToX(t0,cx)) return false;
      cy=ExplainPriceToY(t0,p0,refPrice,chartH);
      return true;
   }
   int x1=0,x2=0;
   if(!ExplainTimeToX(t0,x1) || !ExplainTimeToX(t1,x2)) return false;
   int y1=ExplainPriceToY(tVis,p0,refPrice,chartH);
   int y2=ExplainPriceToY(tVis,p1,refPrice,chartH);
   cx=(x1+x2)/2;
   cy=(y1+y2)/2;
   return true;
}

void RunClickPathSelfTest()
{
   if(!InpRunClickPathSelfTest) return;

   int chartW=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
   int chartH=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   if(chartW<=0 || chartH<=0) return;
   double refPrice=(g_analysisClose>0.0)? g_analysisClose : iClose(_Symbol,PERIOD_CURRENT,0);
   datetime tVis=ExplainVisibleTime();

   int h=FileOpen("ICT_Assistant_Canonical_Click_Diag.csv",
                  FILE_COMMON|FILE_WRITE|FILE_CSV|FILE_UNICODE,';');
   if(h==INVALID_HANDLE) return;
   FileWrite(h,"Object","ResolveStatus","Reason","Title","Lines",
             "CenterX","CenterY","OnScreen","HitObject","HitIsSelf","HitLines");

   g_clickTestObjects=0; g_clickTestResolved=0; g_clickTestEmpty=0;
   g_clickTestOffscreen=0; g_clickTestSelfHit=0; g_clickTestWeakHit=0;

   int total=ObjectsTotal(0,-1,-1);
   for(int i=0;i<total && g_clickTestObjects<InpClickDiagMaxObjects;i++)
   {
      string nm=ObjectName(0,i,-1,-1);
      if(StringFind(nm,"ICTv13_")!=0) continue;
      // داشبورد/پنل خودشان آبجکت‌های خواندنی‌اند، نه لایهٔ تحلیل؛ hit-test هم
      // عمداً آن‌ها را نادیده می‌گیرد، پس در آزمون کلیک هم نمی‌آیند.
      if(StringFind(nm,"ICTv13_DASH_")==0) continue;
      if(StringFind(nm,"ICTv13_EXP_")==0)  continue;
      long otype=ObjectGetInteger(0,nm,OBJPROP_TYPE);
      if(otype==OBJ_RECTANGLE_LABEL||otype==OBJ_LABEL) continue;

      g_clickTestObjects++;

      // مرحلهٔ ۲ و ۳: همان چیزی که یک کلیک روی همین آبجکت اجرا می‌کند.
      ExpClear();
      ENUM_CLICK_RESOLVE st=ExplainBuildDetailed(nm);
      string reason=g_clickReason;
      string title=g_expTitle;
      int    lines=ArraySize(g_expLines);
      if(st==CLICK_RS_OK) g_clickTestResolved++; else g_clickTestEmpty++;

      // مرحلهٔ ۱: شبیه‌سازی کلیک روی مرکز خود آبجکت
      int cx=0,cy=0;
      string hit=""; int hitLines=0; int self=0; int onScreen=0;
      if(ClickTestCenterOf(nm,chartH,refPrice,tVis,cx,cy))
      {
         if(cx>=0 && cx<chartW && cy>=-4 && cy<=chartH+4)
         {
            onScreen=1;
            hit=HitTestExplainObject(cx,cy);
            if(hit!=""){ self=(hit==nm)?1:0; ExpClear(); ExplainBuildDetailed(hit); hitLines=ArraySize(g_expLines); }
         }
      }
      if(!onScreen) g_clickTestOffscreen++;
      if(onScreen && hit=="") g_clickTestWeakHit++;
      if(self==1) g_clickTestSelfHit++;

      FileWrite(h,nm,(st==CLICK_RS_OK? "RESOLVED":"FALLBACK"),reason,title,lines,
                cx,cy,onScreen,hit,self,hitLines);
   }
   FileClose(h);

   // پنل باید تمیز بماند: آزمون نباید چیزی روی چارت جا بگذارد.
   g_expHovered="";
   ExpClear();

   Print(StringFormat("ICT PHASE44 | click path self-test | objects=%d resolved=%d no-handler=%d offscreen=%d center-hit-miss=%d center-hit-self=%d | report ICT_Assistant_Canonical_Click_Diag.csv",
         g_clickTestObjects,g_clickTestResolved,g_clickTestEmpty,g_clickTestOffscreen,
         g_clickTestWeakHit,g_clickTestSelfHit));
}

//====================================================================
// DASHBOARD — رفع ایراد ۱۶: از داده‌های واقعی Core می‌خواند، خودش
// چیزی محاسبه نمی‌کند.
//====================================================================
//====================================================================
// فاز ۱۴ — داشبورد با اندازه‌گیری واقعی متن (بدون بریدگی، بدون ردیف کهنه)
//
// دو ایراد واقعی که این بخش می‌بندد:
//   ۱) پس‌زمینهٔ داشبورد ۳۸۰×۶۴۰ هاردکد بود. با ۴۱ ردیف ممکن و ردیف‌های بلند
//      (مثلاً ردیف OB با ۶۶ کاراکتر)، متن از کادر بیرون می‌زد یا روی ردیف بعدی
//      می‌افتاد → همان «بریدگی/سرریز».
//      حالا عرض و ارتفاع از اندازهٔ واقعی متن می‌آید: TextSetFont + TextGetSize
//      (مرجع رسمی MQL5 — TextSetFont / TextGetSize در مستندات رسمی MQL5).
//   ۲) ردیف‌های شرطی (clocknote / sb / asia / mtfreason / dirline / entry / sl /
//      tp1..tp3 / rr) وقتی شرطشان false می‌شدند هرگز بازنویسی نمی‌شدند و متن
//      قدیمی روی چارت می‌ماند. حالا در DashEnd هر برچسبی که در همین pass
//      نوشته نشده باشد حذف می‌شود.
// اگر کاربر InpDashMaxWidth را بزرگ‌تر از ۴۰ بگذارد، ردیف بلندتر در نزدیک‌ترین
// « | » یا فاصله شکسته می‌شود؛ ولی اگر حتی با شکستن هم جا نشود، متن **بریده
// نمی‌شود** — عرض کادر باز می‌شود و شمارندهٔ سرریز بالا می‌رود تا در Journal
// دیده شود.
//====================================================================
string g_dashUsed[];      // نام ردیف‌هایی که در همین pass نوشته شدند
int    g_dashRows=0;      // تعداد ردیف‌های مصرف‌شده (با احتساب شکستن خط)
int    g_dashWidth=0;     // عرض نهایی پس‌زمینه (پیکسل)
int    g_dashHeight=0;    // ارتفاع نهایی پس‌زمینه (پیکسل)
int    g_dashMaxRowW=0;   // بلندترین ردیف این pass (پیکسل)
int    g_dashWrapped=0;   // چند ردیف شکسته شد
int    g_dashStale=0;     // چند برچسب کهنه حذف شد
int    g_dashOverflow=0;  // ردیف‌هایی که حتی پس از شکستن هم از سقف عرض رد شدند
int    g_dashX=0, g_dashY=0, g_dashLH=16;

// عرض واقعی متن با تنظیمات فونت فعلی. مقایسهٔ درست با OBJPROP_FONTSIZE:
// مستندات MQL5 می‌گوید «اندازهٔ فونت OBJ_LABEL را در ۱۰- ضرب کن تا فونت
// TextSetFont معادل شود»، پس برای size=9 عدد -90 داده می‌شود.
// اگر TextGetSize در دسترس نبود، تخمین محافظه‌کارانه برمی‌گردد تا متن خوشه‌ای
// بریده نشود (تخمین بزرگ‌تر از واقعیت انتخاب می‌شود).
int DashMeasure(const string s, int size)
{
   int n=StringLen(s);
   if(n==0) return 0;
   uint w=0,h=0;
   if(TextSetFont("Consolas", -size*10, FW_NORMAL) && TextGetSize(s,w,h) && w>0)
      return (int)w;
   // مدل پشتیبان مستند: هر کاراکتر ≈ ۰٫۶۲ × اندازهٔ فونت، به‌علاوهٔ ۲ پیکسل
   // حاشیهٔ اطمینان تا هرگز متن بریده نشود. همین مدل در
   // 05_TESTS_AND_VALIDATION/phase14_wrap.fixture.csv قفل شده است.
   return (int)MathCeil(n*size*0.62)+2;
}

// بهترین نقطهٔ شکست در نزدیک‌ترین « | » یا فاصله. ۰ = نقطهٔ مناسبی پیدا نشد.
int DashBreakIndex(const string s, int maxW, int size)
{
   int n=StringLen(s);
   int best=0;
   for(int i=1;i<n;i++)
   {
      ushort c=StringGetCharacter(s,i);
      if(c!=' ' && c!='|') continue;
      if(DashMeasure(StringSubstr(s,0,i),size)<=maxW) best=i;
      else break;                                  // عرض با طول متن یکنوا است
   }
   if(best>0) return best;
   for(int k=1;k<=n;k++)
      if(DashMeasure(StringSubstr(s,0,k),size)>maxW) return MathMax(1,k-1);
   return 0;
}

void DashPushRow(const string name, const string text, const color clr, const int size)
{
   string full="ICTv13_DASH_"+name;
   if(ObjectFind(0,full)<0) ObjectCreate(0,full,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,full,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,full,OBJPROP_XDISTANCE,g_dashX);
   ObjectSetInteger(0,full,OBJPROP_YDISTANCE,g_dashY+g_dashLH*g_dashRows);
   ObjectSetString(0,full,OBJPROP_TEXT,text);
   ObjectSetInteger(0,full,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,full,OBJPROP_FONTSIZE,size);
   ObjectSetString(0,full,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,full,OBJPROP_SELECTABLE,false);

   if(IndexInNameList(g_dashUsed,name)<0)
   {
      int k=ArraySize(g_dashUsed);
      ArrayResize(g_dashUsed,k+1);
      g_dashUsed[k]=name;
   }
   int w=DashMeasure(text,size);
   if(w>g_dashMaxRowW) g_dashMaxRowW=w;
   g_dashRows++;
}

// داشبورد COMPACT: فقط این ردیف‌ها راهنمای تصمیم تریدند؛ بقیه شمارندهٔ تشخیصی‌اند
// و در حالت COMPACT رسم نمی‌شوند (همه در CSVها هستند، پس چیزی گم نمی‌شود).
bool DashCompactSkip(const string name)
{
   if(name=="title" || name=="htf" || name=="mtfdirs" || name=="sess" ||
      name=="mtfsetup" || name=="dol" || name=="location" || name=="reversal" ||
      name=="exhaustion" || name=="setup" || name=="life" ||
      name=="dirline" || name=="entry" || name=="sl" || name=="tp1" ||
      name=="tp2" || name=="tp3" || name=="rr" || name=="revrisk")
      return false;                     // ردیف‌های تصمیم — همیشه نمایش
   if(StringFind(name,"sep")==0) return false;  // جداکننده‌ها سبک‌اند
   if(name=="mtfreason" && g_mtfConflict) return false; // فقط هنگام تضاد مهم است
   if(name=="clocknote" && g_brokerOffsetNote!="") return false; // هشدار آفست غیرعادی
   return true;                         // بقیه در COMPACT حذف
}

// ثبت یک ردیف داشبورد. نام باید ثابت باشد تا DashEnd بتواند ردیف کهنه را بشناسد.
void DashRow(const string name, const string text, const color clr, const int size=9)
{
   if(!InpShowDashboard) return;
   if(InpDashCompact && DashCompactSkip(name)) return;
   int w=DashMeasure(text,size);
   if(InpDashMaxWidth>40 && w>InpDashMaxWidth)
   {
      int cut=DashBreakIndex(text,InpDashMaxWidth,size);
      if(cut>0 && cut<StringLen(text))
      {
         string head=StringSubstr(text,0,cut);
         string tail=StringSubstr(text,cut);
         StringTrimRight(head);
         StringTrimLeft(tail);
         DashPushRow(name,head,clr,size);
         DashPushRow(name+"_cont","    "+tail,clr,size);
         g_dashWrapped++;
         return;
      }
      g_dashOverflow++;     // حتی با شکستن جا نشد: عرض باز می‌شود، متن بریده نمی‌شود
   }
   DashPushRow(name,text,clr,size);
}

void DashBegin()
{
   ArrayResize(g_dashUsed,0);
   g_dashRows=0; g_dashMaxRowW=0; g_dashWrapped=0; g_dashOverflow=0; g_dashStale=0;
   g_dashX=InpDashX; g_dashY=InpDashY;
   g_dashLH=(InpDashLineHeight>8?InpDashLineHeight:8);
}

void DashEnd()
{
   if(!InpShowDashboard) return;
   // ۱) ابعاد کادر از بلندترین ردیف واقعی؛ با گِردکردن به ۱۰ پیکسل تا لرزش
   //    رقم‌ها باعث تغییر اندازهٔ کادر در هر کندل نشود.
   int need=g_dashMaxRowW+8+16;
   int q=((need+9)/10)*10;
   if(q<140) q=140;
   g_dashWidth=q;
   int needH=g_dashLH*g_dashRows+16;
   if(needH<40) needH=40;
   g_dashHeight=needH;

   string bgName="ICTv13_DASH_BG";
   if(ObjectFind(0,bgName)<0) ObjectCreate(0,bgName,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bgName,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,bgName,OBJPROP_XDISTANCE,g_dashX-8);
   ObjectSetInteger(0,bgName,OBJPROP_YDISTANCE,g_dashY-8);
   ObjectSetInteger(0,bgName,OBJPROP_XSIZE,g_dashWidth);
   ObjectSetInteger(0,bgName,OBJPROP_YSIZE,g_dashHeight);
   ObjectSetInteger(0,bgName,OBJPROP_BGCOLOR,InpDashBg);
   ObjectSetInteger(0,bgName,OBJPROP_BACK,false);
   ObjectSetInteger(0,bgName,OBJPROP_SELECTABLE,false);

   // ۲) حذف ردیف‌های کهنه: هر برچسبی که در این pass نوشته نشده باشد
   int total=ObjectsTotal(0,-1,-1);
   for(int i=total-1;i>=0;i--)
   {
      string nm=ObjectName(0,i,-1,-1);
      if(StringFind(nm,"ICTv13_DASH_")!=0) continue;
      if(nm==bgName) continue;
      string sfx=StringSubstr(nm,StringLen("ICTv13_DASH_"));
      if(IndexInNameList(g_dashUsed,sfx)>=0) continue;
      ObjectDelete(0,nm);
      g_dashStale++;
   }
}

//====================================================================
// فاز ۳۵: نوار تک‌خطی «کجا ایستاده‌ای»
//
// چرا این شکل: کاربر خواست بدون داشبورد و بدون خواندن CSV بفهمد الان
// کجای حرکت است. منبع داده همان موتور فاز ۳۲ است (UpdateReverseRisk)،
// پس نوار هیچ محاسبهٔ موازی‌ای ندارد — فقط نمایش آخرین وضعیت کندل بسته.
//
// کانال نمایش: همان مسیر تأییدشدهٔ پنل آموزشی — OBJ_EDIT با متن خام
// (پیشفرض InpExplainRenderMode=0). دلیل: OBJ_EDIT کنترل بومی ویندوز
// است و خودش bidi/شکل‌دهی را انجام میدهد؛ تبدیل دستی روی آن «دوبار
// تبدیل» می‌سازد (ریشهٔ فاجعهٔ فاز ۲۲/۲۵ که در بند ۴-۰-۲۷ ثبت شد).
//
// پاک‌سازی: نام‌ها با پیشوند ICTv13_ هستند، پس OnDeinit با
// ObjectsDeleteAll(0,"ICTv13_") خودکار حذفشان می‌کند.
//====================================================================
void RenderRiskStrip()
{
   if(!InpShowRiskStrip)
   {
      if(g_riskStripOn)      // فقط یک بار حذف، نه در هر tick
      {
         ObjectDelete(0,"ICTv13_RSTRIP_BG");
         ObjectDelete(0,"ICTv13_RSTRIP_TXT");
         g_riskStripOn=false; g_riskStripLastText="";
      }
      return;
   }

   // فاز ۴۸ — «خط مسیر»: ردیف درجه (فاز ۴۶) و ردیف سناریوی در انتظار (فاز ۴۷)
   // در **یک** خط ادغام شدند. دلیل: هر دو یک واقعیت را دو تکه می‌گفتند و کاربر
   // باید دو ردیف را کنار هم می‌خواند تا بفهمد کجا ایستاده، کجا می‌رود و از کجا
   // برمی‌گردد. ترتیب خواندن عمدی است و همان پرسش کاربر را دنبال می‌کند:
   //   درجه و بایاس → روی چه سطحی ایستاده‌ایم → مقصد نقدینگی → شرط برگشت و نرخش.
   // قاعدهٔ RTL فاز ۴۲: برچسب‌های لاتین ابتدای ردیف می‌آیند و بقیه فارسی است.
   // متن کوتاه نگه داشته می‌شود عمداً: جزئیات کامل (امتیاز، فهرست شواهد، برد
   // تاریخی، سبد فاصله، خط پایهٔ سنجش) داخل پنل آموزشی همان ردیف است، نه روی چارت.
   string txt=StringFormat("GRADE: %s  %.1f%%  |  BIAS: %s  |  سطح: %s [%s]  |  ریسک برگشت: %s (%d)",
             g_grade, g_gradeWin, DirToStr(g_htfBias),
             g_rrLevel, g_rrLevelState, g_rrLabel, g_rrScore);

   // قطعهٔ «مسیر» از همان ماژولی می‌آید که آن را محاسبه می‌کند؛ پس یک عدد،
   // یک روایت دارد. اگر سناریوی در انتظار چیزی برای گفتن نداشته باشد،
   // نوار به همان شاهدهای همیشه‌موجود برمی‌گردد تا ردیف هیچ‌وقت خالی نماند.
   string path=PendingFragmentFa();
   if(path!="")
      txt+=path;
   else
   {
      txt+=StringFormat("  |  فاصله %.2f برابر میانگین دامنه  |  لگ %.0f درصد",
                        g_rrLevelDist, g_rrLegProg);
      if(g_hasDOL)
         txt+=StringFormat("  |  هدف: %s  |  فاصله %.2f برابر میانگین دامنه",
                           g_currentDOL.typeName, g_rrDolDist);
   }
   if(g_barSweptTowardBias)
      txt+="  |  SFP  |  نقدینگی سمت بایاس جارو شد";

   // کارایی: متن عوض نشده؟ هیچ ObjectSet و ChartRedraw ای لازم نیست.
   if(g_riskStripOn && txt==g_riskStripLastText) return;
   g_riskStripLastText=txt;

   int chartW=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
   int w=InpRiskStripWidth;
   // فاز ۴۶: قبلاً عرض نوار ثابت ۶۴۰ بود و ردیف بلندتر از آن بی‌صدا بریده
   // می‌شد (دقیقاً همان چیزی که کاربر «متن ناقص» می‌دید). حالا عرض از طول
   // واقعی متن هم حساب می‌شود و فقط به عرض چارت محدود می‌ماند.
   int need=(int)(StringLen(txt)*InpExplainFontSize*0.62)+24;
   if(need>w) w=need;
   if(chartW>20 && w>chartW-10) w=chartW-10;
   int lineH=InpExplainFontSize+11;   // همان فرمول ردیف پنل آموزشی

   string bg="ICTv13_RSTRIP_BG";
   if(ObjectFind(0,bg)<0) ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bg,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,2);
   ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,InpRiskStripY);
   ObjectSetInteger(0,bg,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,bg,OBJPROP_YSIZE,lineH+6);
   ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,clrBlack);
   ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,bg,OBJPROP_COLOR,PAL_PANEL_BORDER);
   ObjectSetInteger(0,bg,OBJPROP_BACK,false);
   ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,bg,OBJPROP_HIDDEN,true);

   // ردیف نوار از همان ExplainEditRow پنل آموزشی استفاده می‌کند تا رنگ/فونت/
   // تراز/فقط-خواندنی دقیقاً با مسیر تأییدشدهٔ فارسی یکی باشد.
   ExplainEditRow("ICTv13_RSTRIP_TXT", 8, InpRiskStripY+3, w-12, lineH,
                  RenderLine(txt,InpExplainRenderMode),
                  GradeStripColor(),
                  InpExplainFontSize);
   g_riskStripOn=true;
   ChartRedraw(0);   // فقط وقتی متن/رنگ واقعاً عوض شد
}

string RejectionStateToStr(ENUM_REJECTION_STATE state)
{
   if(state==REJECTION_FRESH) return "FRESH";
   if(state==REJECTION_TOUCHED) return "TOUCHED";
   if(state==REJECTION_INVALID) return "INVALID";
   return "UNKNOWN";
}

void RenderDashboard()
{
   if(!InpShowDashboard) return;
   // فاز ۱۴: ابعاد کادر دیگر هاردکد نیست؛ DashEnd آن را از اندازهٔ واقعی متن و
   // تعداد ردیف‌های مصرف‌شده می‌سازد. هیچ متنی بریده یا روی‌هم‌افتاده نمی‌ماند.
   DashBegin();

   DashRow("title", StringFormat("%s — ICT Assistant core v0.1", _Symbol), clrGold, 11);

   string sessTxt = (g_currentSession==SESS_ASIA)?"ASIAN KZ":(g_currentSession==SESS_LONDON)?"LONDON KZ":
                    (g_currentSession==SESS_NY_AM)?"NY AM KZ":(g_currentSession==SESS_LONDON_CLOSE)?"LONDON CLOSE":
                    (g_currentSession==SESS_NY_PM)?"NY PM KZ":"—";
   DashRow("sess", "Session: "+sessTxt, InpColorNeutral);
   // آفست تشخیص‌داده‌شده در همین خط دیده می‌شود تا کاربر بتواند پنجره‌های سشن را
   // با ساعت واقعی خودش مقایسه کند (بروکرهای ۳۰/۴۵ دقیقه هم درست نشان داده می‌شوند)
   DashRow("clock", StringFormat("NY %02d:%02d (GMT%+d) | broker GMT%+d:%02d", g_hourNYNow, g_minNYNow, g_nyOffsetHoursNow,
             g_serverGMTOffsetSeconds/3600, MathAbs(g_serverGMTOffsetSeconds%3600)/60),
             InpColorNeutral);
   // فاز ۱۵: قاعدهٔ DST بروکر و آفست استاندارد — بدون این دو، آفست تاریخی
   // (و در نتیجه پنجره‌های سشن روزهای قبل) قابل بازتولید نبود.
   DashRow("tzrule", StringFormat("TZ: rule %s | std GMT%+d:%02d | hist %s | bar delta %+d min",
             BrokerDSTRuleToStr(g_brokerDSTRule),
             g_brokerStdOffsetSeconds/3600, MathAbs(g_brokerStdOffsetSeconds%3600)/60,
             InpUseHistoricalBrokerOffset?"DST-aware":"current-offset",
             g_histOffsetDeltaMin),
             (g_histOffsetDeltaMin!=0)? clrGold : InpColorNeutral);
   // فقط وقتی یادداشت وجود دارد، ردیف نوشته می‌شود؛ در غیر این صورت DashEnd
   // خودش ردیف کهنه را پاک می‌کند (قبلᾰ این متن قدیمی تا ابد روی چارت می‌ماند).
   if(g_brokerOffsetNote!="") DashRow("clocknote", g_brokerOffsetNote, clrGold);
   if(g_silverBullet!=SB_NONE)
      DashRow("sb", "SILVER BULLET "+SBSyncLabel(), clrGold);   // فاز ۳۶: برچسب ترکیبی SB + همسویی HTF-LTF

   string amdTxt = (g_currentAMD==AMD_ACCUMULATION)?"ACCUMULATION":(g_currentAMD==AMD_MANIPULATION)?"MANIPULATION":(g_currentAMD==AMD_DISTRIBUTION)?"DISTRIBUTION":"—";
   DashRow("amd", "AMD/PO3: "+amdTxt, InpColorNeutral);
   // فاز ۳۶: AMD قیمتی — مرحلهٔ واقعی قیمت، نه فقط نگاشت سشنی
   string amdP=(g_amdPriceStage==AMD_ACCUMULATION)?"A":(g_amdPriceStage==AMD_MANIPULATION)?"M":(g_amdPriceStage==AMD_DISTRIBUTION)?"D":"—";
   DashRow("amdprice", "AMD قیمتی: "+amdP+(g_amdPriceNote!=""? " | "+g_amdPriceNote:""), clrViolet);
   if(g_asiaHigh>g_asiaLow)
      DashRow("asia", StringFormat("Asian Range: %.2f - %.2f (liquidity target)", g_asiaLow, g_asiaHigh),
                clrSlateBlue);

   DashRow("sep1","────────────────────", clrGray);
   DashRow("htf", "HTF Bias: "+DirToStr(g_htfBias), g_htfBias==DIR_BULL?InpColorBull:g_htfBias==DIR_BEAR?InpColorBear:InpColorNeutral);
   // دو ساختار داخلی، دو منبع متفاوت: یکی ترند تایم‌فریم چارت و دیگری ساختار
   // داخلی روی InpMTF (ورودی #۶۱ که قبلاً بی‌مصرف بود).
   DashRow("intd", "Internal "+EnumToString(PERIOD_CURRENT)+": "+DirToStr(g_internalDir), InpColorNeutral);
   DashRow("intdmtf", "Internal "+EnumToString(InpMTF)+": "+DirToStr(g_mtfInternalDir),
             (g_mtfInternalDir==DIR_NONE || g_mtfInternalDir==g_htfBias) ? InpColorNeutral : clrOrange);

   // MTF Status
   DashRow("mtf", "MTF: H4/H1/M15/M5/M2/M1", InpColorNeutral);
   DashRow("mtfdirs", DirToStr(g_htfBias)+" / "+DirToStr(g_mtfContext[1].externalDirection)+" / "+DirToStr(g_mtfContext[2].externalDirection)+" / "+DirToStr(g_mtfContext[3].externalDirection)+" / "+DirToStr(g_mtfContext[4].internalDirection)+" / "+DirToStr(g_mtfContext[5].internalDirection), g_mtfConflict?InpColorBear:InpColorNeutral);
   if(g_mtfConflict) DashRow("mtfreason",g_mtfConflictReason,InpColorBear);

   // آخرین Event
   string lastEvt="—"; color lastClr=InpColorNeutral;
   int ltfEventCount=0, htfEventCount=0;
   for(int i=ArraySize(g_events)-1;i>=0;i--)
   {
      if(g_events[i].isHTF) htfEventCount++;
      else
      {
         ltfEventCount++;
         if(lastEvt=="—")
         {
            lastEvt = EventTypeToStr(g_events[i].type)+" "+DirToStr(g_events[i].direction);
            lastClr = g_events[i].direction==DIR_BULL?InpColorBull:InpColorBear;
         }
      }
   }
   DashRow("lastevt","Last Event: "+lastEvt, lastClr);
   // داشبورد فول: رویدادهای ساختاری H4 جدا از رویدادهای تایم‌فریم چارت شمرده
   // می‌شوند تا هوشمندی MTF و آستانهٔ بی‌عدالتی تایم‌فریم‌ها بدون باز کردن CSV دیده شود.
   DashRow("events", StringFormat("Events: %d LTF / %d HTF (%s)", ltfEventCount, htfEventCount,
             TFShortName(InpHTF)), (htfEventCount>0)?clrGold:InpColorNeutral);

   DashRow("sep2","────────────────────", clrGray);

   // Liquidity summary
   int freshCount=0, sweptCount=0, invalidCount=0;
   for(int i=0;i<ArraySize(g_liquidity);i++)
   {
      if(g_liquidity[i].state==LSTATE_FRESH) freshCount++;
      if(g_liquidity[i].state==LSTATE_SWEPT) sweptCount++;
      if(g_liquidity[i].state==LSTATE_INVALID) invalidCount++;
   }
   DashRow("liq", StringFormat("Liquidity: %d fresh / %d swept / %d invalid", freshCount, sweptCount, invalidCount), InpColorNeutral);

   // داشبورد فول: تفکیک نقدینگی بر اساس نوع — BSL/SSL و EQH/EQL و PDH/PDL
   // بدون باز کردن CSV دیده شوند (هر سطح یک آبجکت واقعی در رجیستری است).
   int eqhN=0, eqlN=0, bslN=0, sslN=0, pdN=0, wkN=0, ipdaN=0;
   for(int i=0;i<ArraySize(g_liquidity);i++)
   {
      if(g_liquidity[i].state==LSTATE_INVALID) continue;
      ENUM_LIQ_TYPE t=g_liquidity[i].type;
      if(t==LIQ_EQH) eqhN++;
      else if(t==LIQ_EQL) eqlN++;
      if(IsHighSideLiquidity(t)) bslN++; else sslN++;
      if(t==LIQ_PDH || t==LIQ_PDL) pdN++;
      if(t==LIQ_SWING_H || t==LIQ_SWING_L) wkN++;
      if(t==LIQ_IPDA20_H || t==LIQ_IPDA20_L || t==LIQ_IPDA40_H || t==LIQ_IPDA40_L || t==LIQ_IPDA60_H || t==LIQ_IPDA60_L) ipdaN++;
   }
   DashRow("liqtype", StringFormat("LIQ types: EQH %d / EQL %d | BSL %d / SSL %d | PD %d | swing %d | IPDA %d",
             eqhN, eqlN, bslN, sslN, pdN, wkN, ipdaN), InpColorNeutral);

   // Displacement causal / energy-only
   int dCausal=0, dEnergy=0;
   for(int i=0;i<ArraySize(g_displacements);i++){ if(g_displacements[i].energyOnly) dEnergy++; else dCausal++; }
   DashRow("disp", StringFormat("Displacement: %d causal / %d energy-only", dCausal, dEnergy), InpColorNeutral);

   // FVG causal
   int fCausal=0, fTotal=ArraySize(g_fvgs);
   for(int i=0;i<fTotal;i++) if(g_fvgs[i].causal) fCausal++;
   DashRow("fvg", StringFormat("FVG: %d/%d CAUSAL", fCausal, fTotal), fCausal>0?InpColorBull:InpColorNeutral);

   // OB state summary
   int oValid=0,oBreaker=0,oMitig=0,oExtreme=0,oStandalone=0;
   for(int i=0;i<ArraySize(g_obs);i++)
   {
      if(g_obs[i].state==OB_VALID) oValid++;
      if(g_obs[i].state==OB_BREAKER) oBreaker++;
      if(g_obs[i].state==OB_MITIGATION) oMitig++;
      if(g_obs[i].isExtreme) oExtreme++;
      if(g_obs[i].isStandalone) oStandalone++;
   }
   // فاز ۱۴: این ردیف با ۶۶ کاراکتر از عرض قدیمی کادر بیرون می‌زد؛ حالا کادر
   // خودش را با عرض واقعی متن تنظیم می‌کند (یا در صورت سقف عرض، می‌شکند).
   DashRow("ob", StringFormat("OB: %d VALID / %d BREAKER / %d MITIG / %d EXTREME / %d STANDALONE", oValid, oBreaker, oMitig, oExtreme, oStandalone), InpColorNeutral);

   int fMitigated=0,fInvalid=0,fFresh=0,fIFVG=0;
   for(int i=0;i<ArraySize(g_fvgs);i++)
   {
      if(g_fvgs[i].invalidated)    fInvalid++;
      else if(g_fvgs[i].inverted)  fIFVG++;
      else if(g_fvgs[i].mitigated) fMitigated++;
      else                         fFresh++;
   }   // فاز ۱۲: شمارش گپ Implied و Micro تا بسته‌شدن دریچهٔ ابزار سنجششده باشد
   int fImplied=0, fMicro=0;
   for(int i=0;i<ArraySize(g_fvgs);i++)
   {
      if(g_fvgs[i].kind==FVGK_IMPLIED) fImplied++;
      else if(g_fvgs[i].kind==FVGK_MICRO) fMicro++;
   }
   DashRow("fvgstate", StringFormat("FVG: %d FRESH / %d MIT / %d iFVG / %d EXP | IMP %d / MIC %d", fFresh, fMitigated, fIFVG, fInvalid, fImplied, fMicro), fFresh>0?InpColorBull:InpColorNeutral);

   // داشبورد فول: مخازن تحلیلگر — سوئینگ‌ها، Displacement، نقدینگی مورب و رنج
   // به‌صورت عددی دیده شوند تا سلامت رجیستری‌ها بدون CSV قابل کنترل باشد.
   int swH=0, swL=0;
   for(int i=0;i<ArraySize(g_swingsLTF);i++){ if(g_swingsLTF[i].isHigh) swH++; else swL++; }
   DashRow("regs", StringFormat("Registry: swings %d (H%d/L%d) | disp %d | trendlines %d%s",
             ArraySize(g_swingsLTF), swH, swL, ArraySize(g_displacements), ArraySize(g_trendlines),
             g_rangeOk? StringFormat(" | range %s–%s (%d/%d)", PriceS(g_rangeLow), PriceS(g_rangeHigh),
                                     g_rangeLowTouches, g_rangeHighTouches) : ""),
             InpColorNeutral);
   DashRow("sep3","────────────────────", clrGray);

   // DOL — با امتیاز و نوع واقعی سطح (#۴۸)
   if(g_hasDOL)
      DashRow("dol", StringFormat("DOL: %s (%s) | %s | %.2f ATR | score %d",
                 DoubleToString(g_currentDOL.price,_Digits),
                 g_currentDOL.hierarchyOk?"External":"Internal", g_currentDOL.typeName,
                 g_currentDOL.distATR, g_currentDOL.score), InpColorNeutral);
   else
      DashRow("dol", (g_htfBias==DIR_NONE? "DOL: WAITING_H4_BIAS" : "DOL: WAITING_DOL")
                 +(g_dolRejectReason!=""?" | "+g_dolRejectReason:""), InpColorNeutral);

   // Location از همان close کندل تحلیلی و همان لگ واقعی ساخته می‌شود (#۴۵)
   string locationText="Location: WAITING_LEG";
   if(g_leg.valid)
   {
      locationText=StringFormat("Location: %s | EQ %.2f | leg %s",
                                (g_analysisClose>=g_leg.eq?"PREMIUM":"DISCOUNT"), g_leg.eq, DirToStr(g_leg.dir));
   }
   DashRow("location",locationText,InpColorNeutral);
   if(g_leg.valid)
      DashRow("leg", StringFormat("Leg %s: %.2f→%.2f (%.2f ATR) | %s → %s",
                 DirToStr(g_leg.dir), g_leg.low, g_leg.high, g_leg.sizeATR,
                 TimeToString(g_leg.startTime,TIME_DATE|TIME_MINUTES),
                 TimeToString(g_leg.endTime,TIME_DATE|TIME_MINUTES)), InpColorNeutral);
   else
      DashRow("leg", "Leg: "+g_leg.reject, InpColorNeutral);
   DashRow("mtfsetup", "MTF gate: "+g_setup.status, g_setup.active?InpColorBull:InpColorNeutral);
   color exhaustionClr=(g_exhaustion.state==EXH_REVERSAL_CONFIRMED)?clrGold:
                       (g_exhaustion.state==EXH_WATCH || g_exhaustion.state==EXH_MICRO_PULLBACK || g_exhaustion.state==EXH_RANGE_TRANSITION)?InpColorBear:InpColorNeutral;
   DashRow("exhaustion", "Exhaustion: "+ExhaustionStateToStr(g_exhaustion.state)+" "+IntegerToString(g_exhaustion.score)+"/"+IntegerToString(g_exhaustion.maxScore), exhaustionClr);

   // فاز ۱۲ (#۳ #۹): ساختار داخلی همان تایم‌فریم مالک + سن و فاز روند
   DashRow("trend", StringFormat("Trend: %s | age %d HTF bars | Internal %s: %s",
             TrendPhaseToStr(g_trend.phase), g_trend.ageBars, EnumToString(InpHTF), DirToStr(g_htfInternalDir)),
             (g_htfInternalDir==DIR_NONE || g_htfInternalDir==g_htfBias)?InpColorNeutral:clrOrange);
   // فاز ۱۲ (#۴۷ #۶۷ #۶۸)
   DashRow("quality", StringFormat("Model: %s | Quality %d/10 | POI %s (%d)",
             EntryModelToStr(g_setup.entryModel), (g_setup.active?g_setup.quality:g_setup.quality),
             PoiKindToStr(g_setup.poiKind), g_setup.poiScore),
             g_setup.active?InpColorBull:InpColorNeutral);

   // فاز ۱۱: دروازهٔ برگشت تأییدشده — جدا از Exhaustion تا تفاوت «هشدار» و «تأیید» دیده شود
   color reversalClr = g_reversal.confirmed ? (g_reversal.dir==DIR_BULL?InpColorBull:InpColorBear)
                                            : (g_reversal.armed?clrOrange:InpColorNeutral);
   DashRow("reversal", StringFormat("Reversal: %s | gate %s | -> %s | SMR %d/%d",
             g_reversal.state,
             (g_reversal.armed? DoubleToString(g_reversal.levelPrice,_Digits):"—"),
             DirToStr(g_reversal.confirmed? g_reversal.dir : OppositeDir(g_reversal.snapBias)),
             g_reversal.smrScore, g_reversal.smrMax), reversalClr);

   // Rejection Block Status
   // فازهای ۱۶–۲۱: ردیف‌های خانواده‌های جدید
   int sdFresh=0, sdTested=0, sdFlipped=0;
   for(int i=0;i<ArraySize(g_sd);i++)
   {
      if(g_sd[i].state==SDS_FRESH) sdFresh++;
      else if(g_sd[i].state==SDS_TESTED) sdTested++;
      else if(g_sd[i].state==SDS_FLIPPED) sdFlipped++;
   }
   DashRow("wyck", StringFormat("Wyckoff: %s", (g_wyckPhaseReason==""? "—":g_wyckPhaseReason)), InpColorNeutral);
   DashRow("sdfam", StringFormat("S/D zones: %d (FRESH %d / TESTED %d / FLIPPED %d)",
             ArraySize(g_sd), sdFresh, sdTested, sdFlipped), InpColorNeutral);
   DashRow("brooks", "Brooks: "+(g_brooksNote==""? "—":g_brooksNote), InpColorNeutral);
   DashRow("rtm", "RTM: "+(g_rtmNote==""? "—":g_rtmNote), InpColorNeutral);
   DashRow("profile", "Profile: "+(g_profileNote==""? "—":g_profileNote), InpColorNeutral);

   // داشبورد فول: IPDA و POI رجیستری — پیش از این فقط در CSV دیده می‌شدند
   DashRow("ipda", "IPDA: "+(g_ipdaOk? g_ipdaNote : (InpDetectIPDA? g_ipdaNote+" | OFF-data":"disabled")),
             g_ipdaOk?InpColorNeutral:clrGray);
   int poiValid=0; long poiBest=0; int poiBestScore=-1; string poiBestKind="";
   for(int i=0;i<ArraySize(g_poi);i++)
   {
      if(!g_poi[i].valid) continue;
      poiValid++;
      if(g_poi[i].score>poiBestScore){ poiBestScore=g_poi[i].score; poiBest=g_poi[i].id; poiBestKind=PoiKindToStr(g_poi[i].kind); }
   }
   DashRow("poi", StringFormat("POI: %d valid / %d total | best %s #%s (%d)",
             poiValid, ArraySize(g_poi), poiBestKind, IdToStr(poiBest), poiBestScore),
             poiValid>0?InpColorNeutral:clrGray);
   DashRow("atrbars", StringFormat("ATR(%d): %s | close %s | bars %d | build %s",
             InpATR_Period, (g_analysisATR>0.0? PriceS(g_analysisATR):"—"),
             (g_analysisClose>0.0? PriceS(g_analysisClose):"—"),
             InpHistoryScanBars, g_buildStamp), clrGray);

   int rFresh=0, rTouched=0, rInvalid=0;
   for(int i=0; i<ArraySize(g_rejections); i++)
   {
      if(g_rejections[i].rejectionState==REJECTION_FRESH) rFresh++;
      else if(g_rejections[i].rejectionState==REJECTION_TOUCHED) rTouched++;
      else if(g_rejections[i].rejectionState==REJECTION_INVALID) rInvalid++;
   }
   DashRow("rbstate", StringFormat("Rejection Block: %d FRESH / %d TOUCHED / %d INVALID", rFresh, rTouched, rInvalid), InpColorNeutral);

   // داشبورد فول: بهداشت نمایش — چند آبجکت روی چارت زنده/فریز است و چند ردیف
   // کهنه/شکسته حذف شده؛ برای تشخیص شلوغی چارت بدون شمارش دستی Ctrl+B.
   // (در COMPACT حذف می‌شود — شمارش ObjectsTotal در هر کندل هم هزینه دارد.)
   if(!InpDashCompact)
   {
      int chartLayerObjs=0;
      int to_=ObjectsTotal(0,-1,-1);
      for(int i=0;i<to_;i++)
         if(IsLayerObjectName(ObjectName(0,i,-1,-1))) chartLayerObjs++;
      DashRow("hygiene", StringFormat("Chart: %d live objs | frozen %d | dash stale %d / wrapped %d",
                chartLayerObjs, ArraySize(g_frozen), g_dashStale, g_dashWrapped), clrGray);
   }
   // فاز ۱۴: delimiter تکراری (sep5 و sep4 پشت‌سرهم) حذف شد.
   DashRow("sep4","────────────────────", clrGray);

   // فاز ۳۲: ریسک برگشت — در چه نقطه‌ای از حرکت هستیم و خطر ورودِ خلاف جهت چقدر است.
   // امتیاز، مجموع وزن‌های مستند است (در پنل تفکیک می‌شود)؛ «درصد» نیست. درصدِ واقعی
   // از CSV همین ثبت با ابزار tools/Report-ReverseRisk.ps1 روی تاریخچه شمرده می‌شود.
   DashRow("revrisk", StringFormat("ریسک برگشت: %s (%d) | نزدیک‌ترین سطح: %s [%s] | فاصله %.2f برابر میانگین دامنه | لگ %.0f درصد | هدف %s | فاصله %.2f برابر میانگین دامنه%s",
             g_rrLabel, g_rrScore, g_rrLevel, g_rrLevelState, DoubleToString(g_rrLevelDist,2),
             g_rrLegProg, (g_hasDOL? g_currentDOL.typeName : "-"), DoubleToString(g_rrDolDist,2),
             (g_barSweptTowardBias? " | SFP | نقدینگی سمت بایاس جارو شد":"")),
             g_rrScore>=50? InpColorBear : (g_rrScore>=25? InpColorNeutral : InpColorBull));

   // Setup / Signal — از g_setup که خودش از Core پر شده می‌خواند
   color setupClr = g_setup.active ? (g_setup.dir==DIR_BULL?InpColorBull:InpColorBear) : InpColorNeutral;
   DashRow("setup","Setup: "+g_setup.status, setupClr);
   // فاز ۱۵ (#۶۶): چرخهٔ عمر ستاپ — ابطال فقط با بستهٔ قیمت فراتر از SL
   if(InpTrackSetupLifecycle)
   {
      color lifeClr = (g_setupLifeState=="INVALIDATED")? InpColorBear
                    : (g_setupLifeState=="TP1_HIT")? InpColorBull
                    : (g_setupLifeState=="TRACKING")? InpColorNeutral : InpFrozenColor;
      string lifeTxt = (g_setupLifeState=="INVALIDATED")? "INVALIDATED" : "IDLE";
      if(g_setupLifeState=="TP1_HIT")  lifeTxt="TP1 HIT";
      else if(g_setupLifeState=="TRACKING") lifeTxt="TRACKING";
      else if(g_setupLifeState=="IDLE")     lifeTxt="IDLE";
      DashRow("life", StringFormat("Life: %s | armed %d / invalid %d / TP1 %d%s",
                lifeTxt, g_setupArmedCount, g_setupInvalidCount, g_setupTP1Count,
                (g_setupLifeState=="INVALIDATED" && g_setupLifeSL>0.0)?
                  StringFormat(" | SL %s | close %s", PriceS(g_setupLifeSL), PriceS(g_setupInvalidPrice)) : ""),
                lifeClr);
   }
   if(g_setup.active)
   {
      DashRow("dirline", (g_setup.dir==DIR_BULL?"LONG":"SHORT"), setupClr, 12);
      DashRow("entry", StringFormat("Entry: %s | %s", DoubleToString(g_setup.entry,_Digits), g_setup.zoneSource), InpDashText);
      DashRow("sl",    StringFormat("SL:    %s | risk %.2f (%.2f ATR)", DoubleToString(g_setup.sl,_Digits), g_setup.risk, (g_analysisATR>0.0? g_setup.risk/g_analysisATR : 0.0)), InpColorBear);
      DashRow("tp1",   StringFormat("TP1:   %s (1:%.1f)", DoubleToString(g_setup.tp1,_Digits), g_setup.rrTP1), InpColorBull);
      DashRow("tp2",   StringFormat("TP2:   %s (1:%.1f)", DoubleToString(g_setup.tp2,_Digits), g_setup.rrTP2), InpColorBull);
      DashRow("tp3",   StringFormat("TP3:   %s = DOL (1:%.2f)", DoubleToString(g_setup.tp3,_Digits), g_setup.rrTP3), InpColorBull);
      DashRow("rr",    StringFormat("R:R real 1:%.2f | min 1:%.1f | golden %.2f", g_setup.rr, InpMinRR, g_setup.golden), InpDashText);
   }

   // فاز ۱۴: پس‌زمینه به اندازهٔ واقعی متن، و حذف هر ردیف کهنه‌ای که در این
   // pass نوشته نشده باشد (Entry/SL/TP ستاپ قبلی، SILVER BULLET قدیمی، ...).
   DashEnd();
}

//====================================================================
// CLOSED-BAR ANALYSIS — یک مسیر کد مشترک برای حالت زنده و بازپخش
// تاریخچه. shift = شمارهٔ کندل کاملاً بسته‌شده‌ای که تحلیل می‌شود
// (در حالت زنده همیشه 1 = آخرین کندل بسته).
//====================================================================
void AnalyzeClosedBar(int shift, const double &o[], const double &h[], const double &l[],
                      const double &c[], const double &atrBuf[])
{
   int total = ArraySize(h);
   // فاز ۲۹ (#۷۴): تایید پیوت فقط با کندل‌های **بستهٔ** سمت راست.
   // IsConfirmedPivotHigh/low برای تایید، کندل‌های shift-1..shift-right را
   // می‌خواند. با pivotShift = shift + InpSwingRight - 1، آخرین کندل سمت راست
   // شاخص shift-1 می‌شد؛ در حالت زنده (shift=1) این شاخص 0 است و 0 = کندل
   // **در حال تشکیل**، نه بسته‌شده. پس پیوت یک کندل زودتر از موعد «تایید»
   // می‌شد و اگر همان کندل در حال تشکیل از پیوت عبور می‌کرد، آن پیوت دیگر
   // پیوت نبود ولی در Registry می‌ماند — یک سویینگ فانتوم که می‌توانست BOS
   // جعلی بسازد (خودِ ورودی می‌گوید No-Repaint).
   // با + InpSwingRight، آخرین کندل سمت راست شاخص shift = آخرین کندل بسته است.
   // HTF این را از قبل درست داشت (pivotShift = InpSwingRight با rates[0] بسته).
   int pivotShift = shift + InpSwingRight;

   // --- Swing (LTF) با ثبت در Registry نقدینگی ---
   if(IsConfirmedPivotHigh(h, pivotShift, InpSwingLeft, InpSwingRight, total))
   {
      SwingPoint s; s.time=BarTime(pivotShift); s.price=h[pivotShift];
      s.isHigh=true; s.confirmed=true; s.broken=false; s.id=StableSwingId(s.time,s.isHigh);
      PushSwing(g_swingsLTF, s, InpMaxSwings);
      RegisterSwingLiquidity(s, false);
   }
   if(IsConfirmedPivotLow(l, pivotShift, InpSwingLeft, InpSwingRight, total))
   {
      SwingPoint s; s.time=BarTime(pivotShift); s.price=l[pivotShift];
      s.isHigh=false; s.confirmed=true; s.broken=false; s.id=StableSwingId(s.time,s.isHigh);
      PushSwing(g_swingsLTF, s, InpMaxSwings);
      RegisterSwingLiquidity(s, false);
   }

   // --- Displacement candidate روی همین کندل ---
   ENUM_DIRECTION dDir=DIR_NONE;
   long dispId = DetectDisplacementCandidate(o,h,l,c, shift, atrBuf[shift], dDir);

   // --- Sweep مستقل از Displacement ---
   ENUM_DIRECTION sweepDir=DIR_NONE;
   long liqId = DetectSweep(h[shift], l[shift], c[shift], BarTime(shift), sweepDir);
   // فاز ۳۰ (#۷۶): Sweep خط روند (نقدینگی مورب) در همان مسیر کندل بسته بررسی
   // می‌شود. اگر Sweep سطح افقی پیدا نشد، همین زنجیرهٔ رویداد را می‌سازد؛
   // سطوح افقی اولویت دارند چون سنجیده‌شدن قیمت نسبت به آن‌ها صریح‌تر است.
   ENUM_DIRECTION tlSweepDir=DIR_NONE;
   long tlSweepId = DetectTrendlineSweep(h[shift], l[shift], c[shift], BarTime(shift), tlSweepDir);
   if(liqId==-1 && tlSweepId!=-1) { liqId=tlSweepId; sweepDir=tlSweepDir; }
   if(dDir==DIR_NONE) dDir = sweepDir;

   // فاز ۳۲: آیا نقدینگیِ **سمت Bias** در همین کندل جارو شد؟ (هدف حرکت مصرف شد
   // و قیمت پشت سطح برگشت = نشانهٔ کلاسیک برگشت/SFP).
   // دقت در معنای جهت: sweepDir=DIR_BEAR یعنی فتیله بالای یک سطح Buy-Side رفت و
   // کندل زیرش بست — یعنی هدفِ Bias صعودی مصرف شد.
   g_barSweptTowardBias = (g_htfBias!=DIR_NONE && sweepDir!=DIR_NONE &&
                           ((g_htfBias==DIR_BULL && sweepDir==DIR_BEAR) ||
                            (g_htfBias==DIR_BEAR && sweepDir==DIR_BULL)));

   // --- FVG روی هر Displacement واقعی ---
   // کندل Displacement الگوی سه‌کندلی کندل **میانی** است، نه کندل تأییدکننده؛
   // پس FVG فقط وقتی ساخته می‌شود که کندل میانی (shift+1) یک Displacement باشد (#۲۶).
   long midDispId = DisplacementIdForBarTime(BarTime(shift+1));
   if(midDispId!=-1) DetectFVG(o,h,l,c, shift, midDispId);

   // --- Structure Engine (LTF) ---
   // فاز ۱۳ (#۱۱): مبنای تشخیص «رویداد تازه ساخته شد؟» شمارندهٔ یکنوا است، نه
   // اندازهٔ آرایه؛ چون با پر شدن سقف رجیستری، اندازه ثابت می‌ماند در حالی که
   // یک رویداد تازه اضافه و یک قدیمی حذف شده است.
   long beforeEvents = g_eventsAdded;
   EvaluateStructureBreak(c, shift, false, g_swingsLTF, g_ltfTrendDir, dispId, liqId, BarTime(shift));
   g_internalDir = g_ltfTrendDir;

   long newEventId=-1;
   if(g_eventsAdded > beforeEvents && ArraySize(g_events)>0)
      newEventId = g_events[ArraySize(g_events)-1].id;

   if(newEventId!=-1)
   {
      if(dispId!=-1)
      {
         LinkDisplacementToEvent(dispId, newEventId, liqId);
         PromoteCausalFVGs();   // FVG فقط با Displacement زنجیرشده Causal می‌شود (#۲۷)
      }
      if(liqId!=-1)
      {
         int ne=ArraySize(g_events);
         g_events[ne-1].sweepId = liqId;
         // هر سطحی که در همین کندل جارو شده باشد به این رویداد وصل می‌شود،
         // نه فقط نزدیک‌ترین سطح (#۱۷).
         datetime barT=BarTime(shift);
         for(int i=0;i<ArraySize(g_liquidity);i++)
            if(g_liquidity[i].state==LSTATE_SWEPT && g_liquidity[i].sweptTime==barT)
               g_liquidity[i].sweptByEventId=newEventId;
      }
      PersistStructureEvent(g_events[ArraySize(g_events)-1]);
   }

   // --- فاز ۱۲ (#۳۶): OB جدا از وجود شکست ساختار هم ثبت می‌شود ---
   // قبلاً DetectOB فقط داخل شرط «رویداد ساختاری ساخته شد» صدا زده می‌شد،
   // پس structureEventId همیشه معتبر بود و isStandalone هرگز true نمی‌شد.
   // حالا ناحیه‌ای که Displacement دارد ولی در شکست ساختار مشارکت نکرده،
   // Standalone ثبت می‌شود — فیلتر !isStandalone در رسم ستاپ دیگر مرده نیست.
   if(dispId!=-1)
   {
      long fvgIdForOB=-1;
      if(ArraySize(g_fvgs)>0) fvgIdForOB = g_fvgs[ArraySize(g_fvgs)-1].id;
      DetectOB(o,h,l,c, shift, dispId, newEventId, liqId, fvgIdForOB, atrBuf[shift]);   // فاز ۳۶: ATR برای تشخیص Internal/External

      // --- فاز ۱۲ (#۳۱): Micro FVG فقط از Displacement زنجیرشده ---
      // اگر گپ را از هر Displacement بسازیم، رجیستری با ناحیهٔ بی‌ارزش پر می‌شود.
      if(DisplacementChained(dispId, dDir))
         DetectMicroFVG(BarTime(shift), h[shift], l[shift], dispId);
   }

   DetectRejectionBlock(o,h,l,c,shift, liqId, sweepDir);
   DetectEQ_FromSwings(g_swingsLTF, atrBuf[shift]);

   // --- فازهای ۱۶–۲۱: خانواده‌های جدید، روی همان کندل بسته ---
   UpdateFamilies(o,h,l,c,shift,atrBuf[shift]);

   // --- Lifecycleها روی همان کندل بسته (هیچ‌وقت با کندل در حال تشکیل) ---
   datetime curBarTime=BarTime(shift);
   UpdateOB_MitigationAndBreaker(h[shift], l[shift], c[shift], curBarTime);
   UpdateFVG_Lifecycle(h[shift], l[shift], c[shift], curBarTime);
   UpdateRejectionLifecycle(h[shift], l[shift], c[shift], curBarTime);
   UpdateLiquidityLifecycle(c[shift]);
   UpdateTrendlineLifecycle(h[shift], l[shift], c[shift], curBarTime, atrBuf[shift]);   // فاز ۱۲ (#۱۹)
   UpdateSupplyDemandLifecycle(h[shift], l[shift], c[shift], curBarTime);   // فاز ۱۷
}

string ExhaustionStateToStr(ENUM_EXHAUSTION_STATE state)
{
   switch(state)
   {
      case EXH_TRENDING: return "TRENDING";
      case EXH_EXTENDING: return "EXTENDING";
      case EXH_WATCH: return "EXHAUSTION_WATCH";
      case EXH_MICRO_PULLBACK: return "MICRO_PULLBACK";
      case EXH_MICRO_REVERSAL_CONFIRMED: return "MICRO_REVERSAL_CONFIRMED";
      case EXH_RANGE_TRANSITION: return "RANGE_OR_TRANSITION";
      case EXH_REVERSAL_CONFIRMED: return "REVERSAL_CONFIRMED";
      default: return "NEUTRAL";
   }
}

void UpdateExhaustion(const double &o[], const double &h[], const double &l[],
                      const double &c[], int shift, double atrValue)
{
   g_exhaustion.state=EXH_NEUTRAL;
   g_exhaustion.direction=g_htfBias;
   g_exhaustion.score=0;
   g_exhaustion.maxScore=6;
   g_exhaustion.barTime=(shift>=0 && shift<ArraySize(c))?BarTime(shift):0;
   g_exhaustion.reason="";

   // Exhaustion is deliberately subordinate to the H4 owner.  Until H4 has
   // a confirmed bias, no weakness/reversal state is allowed to imply one.
   if(g_htfBias==DIR_NONE || shift<0 || shift>=ArraySize(c))
   {
      g_exhaustion.reason="بایاس مالک تایم‌فریم بالاتر هنوز تأیید نشده است";
      return;
   }

   // --- فاز ۱۱ (#۱۰ #۷۱): برگشت تأییدشده فقط از دروازهٔ سطح محافظت‌شده می‌آید ---
   // هیچ خطی از این تابع g_htfBias را نمی‌نویسد؛ این شاخه فقط وضعیت را
   // گزارش می‌کند. Exhaustion به‌تنهایی هرگز Bias را برنمی‌گرداند.
   int chartSecX=PeriodSeconds(PERIOD_CURRENT);
   if(chartSecX<=0) chartSecX=60;
   datetime barCloseTime=(datetime)((long)g_exhaustion.barTime+(long)chartSecX);
   long freshWindow=(long)chartSecX*(long)MathMax(0,InpReversalFreshBars);
   bool reversalFresh=(g_reversal.confirmed &&
                       InpEnableReversalGate &&
                       g_reversal.dir!=DIR_NONE &&
                       g_reversal.priorBias!=DIR_NONE &&
                       g_reversal.dir!=g_reversal.priorBias &&
                       g_reversal.confirmedCloseTime>0 &&
                       (long)barCloseTime-(long)g_reversal.confirmedCloseTime<=freshWindow);
   if(reversalFresh)
   {
      g_exhaustion.state=EXH_REVERSAL_CONFIRMED;
      g_exhaustion.direction=g_reversal.dir;
      g_exhaustion.score=g_reversal.smrScore;
      g_exhaustion.maxScore=g_reversal.smrMax;
      // Phase 42: the SMR flag is a labelled segment of its own, so the Persian
      // sentences around it stay single visual runs.
      g_exhaustion.reason=StringFormat("REVERSAL CONFIRMED | کندل بستهٔ تایم‌فریم بالاتر با قیمت بستهٔ %s فراتر از سطح محافظت‌شدهٔ خارجی بسته شد (بایاس قبلی %s → جهت برگشت %s)؛ %d کندل چارت از این تأیید گذشته است",
                                       DoubleToString(g_reversal.confirmedClose,_Digits), DirToStr(g_reversal.priorBias),
                                       DirToStr(g_reversal.dir), g_reversal.barsSince);
      g_exhaustion.reason+=g_reversal.smr
         ? (" | SMR CONFIRMED — "+g_reversal.smrReason)
         : (" | SMR NOT CONFIRMED — "+g_reversal.smrReason);
      g_exhaustion.reason+=" | این وضعیت هم بایاس را نمی‌نویسد؛ مالک بایاس همان موتور ساختار تایم‌فریم بالاتر است";
      return;
   }

   int lookback=MathMax(2,InpExhaustionLookback);
   int available=MathMin(lookback,ArraySize(h)-shift-1);
   if(available<2)
   {
      g_exhaustion.reason="برای سنجش فرسودگی روند، کندل بستهٔ کافی وجود ندارد";
      return;
   }

   double avgRange=0.0, avgBody=0.0;
   double priorHigh=h[shift+1], priorLow=l[shift+1];
   for(int i=1;i<=available;i++)
   {
      double priorRange=h[shift+i]-l[shift+i];
      avgRange+=priorRange;
      avgBody+=MathAbs(c[shift+i]-o[shift+i]);
      priorHigh=MathMax(priorHigh,h[shift+i]);
      priorLow=MathMin(priorLow,l[shift+i]);
   }
   avgRange/=available;
   avgBody/=available;

   double range=MathMax(0.0,h[shift]-l[shift]);
   double body=MathAbs(c[shift]-o[shift]);
   double bodyRatio=(range>0.0)?body/range:0.0;
   bool weakEnergy=(avgRange>0.0 && range<=avgRange*InpExhaustionWeakRangeRatio) ||
                   (avgBody>0.0 && body<=avgBody*InpExhaustionWeakRangeRatio) ||
                   (bodyRatio<InpDisp_BodyRatio*0.80);
   bool failedExtension=(g_htfBias==DIR_BULL && h[shift]<=priorHigh) ||
                        (g_htfBias==DIR_BEAR && l[shift]>=priorLow);
   bool opposingClose=(g_htfBias==DIR_BULL && c[shift]<o[shift]) ||
                      (g_htfBias==DIR_BEAR && c[shift]>o[shift]);
   bool opposingInternal=(g_internalDir!=DIR_NONE && g_internalDir!=g_htfBias);
   bool opposingDisplacement=(atrValue>0.0 && range/atrValue>=InpDisp_RangeVsAvg &&
                              bodyRatio>=InpDisp_BodyRatio && opposingClose);
   bool nearDOL=(g_hasDOL && atrValue>0.0 &&
                 MathAbs(g_currentDOL.price-c[shift])<=atrValue*InpExhaustionNearDOL_ATR);
   bool zoneFailure=false;
   for(int i=ArraySize(g_fvgs)-1;i>=0 && i>=ArraySize(g_fvgs)-8;i--)
   {
      // فاز ۴۳: اینجا عمداً جهت **تولد** سنجیده می‌شود. پرسش این است: «ناحیه‌ای
      // که در جهت بایاس ساخته شده بود، الان از دست رفته است؟» — و گپ وارونه
      // دقیقاً همین است (هم‌جهت تولد، از دست رفته). با جهتِ بازنویسی‌شدهٔ قبلی،
      // این هشدار هرگز برای همان گپ فعال نمی‌شد چون جهتٍ گپ وارونه مخالف بایاس
      // نشان داده می‌شد و شرط رد می‌شد.
      if(g_fvgs[i].direction==g_htfBias && (g_fvgs[i].invalidated || g_fvgs[i].inverted))
      { zoneFailure=true; break; }
   }

   if(weakEnergy){ g_exhaustion.score++; g_exhaustion.reason+="افت انرژی نسبت به میانگین کندل‌های بسته؛ "; }
   if(failedExtension){ g_exhaustion.score++; g_exhaustion.reason+="عدم ساخت سقف/کف جدید در بازهٔ بررسی؛ "; }
   if(opposingClose){ g_exhaustion.score++; g_exhaustion.reason+="بسته‌شدن مخالف بایاس؛ "; }
   if(opposingInternal){ g_exhaustion.score++; g_exhaustion.reason+="هشدار ساختار داخلی مخالف؛ "; }
   if(nearDOL){ g_exhaustion.score++; g_exhaustion.reason+="نزدیکی به هدف نقدینگی؛ "; }
   if(zoneFailure){ g_exhaustion.score++; g_exhaustion.reason+="ضعف/وارونگی ناحیهٔ هم‌جهت؛ "; }

   // This is an internal warning only. It must never change g_htfBias.
   bool microReversal=opposingInternal && opposingDisplacement;
   if(microReversal)
      g_exhaustion.state=EXH_MICRO_REVERSAL_CONFIRMED;
   else if(g_exhaustion.score>=InpExhaustionRangeScore)
      g_exhaustion.state=EXH_RANGE_TRANSITION;
   else if(g_exhaustion.score>=InpExhaustionWatchScore)
      g_exhaustion.state=opposingInternal?EXH_MICRO_PULLBACK:EXH_WATCH;
   else if(avgRange>0.0 && range>avgRange*1.15 && bodyRatio>=InpDisp_BodyRatio)
      g_exhaustion.state=EXH_EXTENDING;
   else
      g_exhaustion.state=EXH_TRENDING;

   if(StringLen(g_exhaustion.reason)==0)
      g_exhaustion.reason="شواهد کافی برای ضعف روند دیده نشد؛ بایاس تایم‌فریم بالاتر بدون تغییر است";
   if(microReversal)
      g_exhaustion.reason+=" این چرخش فقط داخلی است؛ برای تغییر بایاس، شکست ساختار خارجی تایم‌فریم بالاتر لازم است.";
   else
      g_exhaustion.reason+=" این وضعیت هشدار است و به‌تنهایی بایاس تایم‌فریم بالاتر را تغییر نمی‌دهد.";
}

//====================================================================
// PHASE 37 — BEHAVIORAL SELF-TEST ON SYNTHETIC DATA (FVG / OB / SWEEP)
//====================================================================
// مسئله‌ای که این بخش می‌بندد:
//   تمام ابزارهای اعتبارسنجی قبلی متن کد را grep می‌کنند؛ یعنی ثابت می‌کنند
//   «رشته در فایل هست»، نه «محاسبهٔ عددی درست است». یک grep سبز با یک فرمول
//   اشتباه هم سبز می‌ماند. MQL5 بیرون از MetaTrader اجرا نمی‌شود، پس تنها راه
//   اثبات واقعی این است که همین توابع زندهٔ DetectFVG / DetectOB / DetectSweep
//   روی کندل‌های ساختگی با پاسخ معلوم اجرا شوند و خروجی واقعی با انتظار
//   مقایسه شود. این کار در همان محیط و همان کدی انجام می‌شود که روی چارت اجرا
//   می‌شود؛ پس هیچ منطق تکراری/موازی‌ای وجود ندارد که از کد اصلی جدا بیفتد.
//
// زمان اجرا: یک‌بار در هر attach، در اولین OnCalculate پیش از بازسازی واقعی.
//   در آن لحظه سری زمانی در دسترس است (BarTime کار می‌کند) ولی رجیستری‌ها
//   هنوز خالی‌اند. آزمون رجیستری‌ها را پس از خود صفر می‌کند، پس تحلیل زنده
//   دقیقاً همان چیزی را می‌بیند که اگر آزمون خاموش بود می‌دید.
//
// خروجی: ICT_Assistant_Canonical_SelfTest.csv در COMMON\Files
//   ستون‌ها: Scenario | Expected | Actual | Pass
//   خوانده‌شده توسط tools/Validate-Phase37.ps1
//
// دندان هارنس: ردیف SENSITIVITY_probe_must_report_FAIL یک انتظار **عمداً غلط**
//   اعلام می‌کند. اگر آن ردیف FAIL نشود، یعنی مقایسه کار نمی‌کند و بقیهٔ
//   PASSها بی‌ارزش‌اند. پس «همه سبز» هرگز کافی نیست — باید دقیقاً یک FAIL
//   طراحی‌شده وجود داشته باشد.
string g_selfTestName[], g_selfTestExp[], g_selfTestAct[];
int    g_selfTestOk[];
int    g_selfTestWritten = 0;

void SelfTestRow(const string name, const bool ok, const string expected, const string actual)
{
   int n=ArraySize(g_selfTestName);
   ArrayResize(g_selfTestName,n+1); ArrayResize(g_selfTestExp,n+1);
   ArrayResize(g_selfTestAct,n+1);  ArrayResize(g_selfTestOk,n+1);
   g_selfTestName[n]=name; g_selfTestExp[n]=expected; g_selfTestAct[n]=actual;
   g_selfTestOk[n]=ok?1:0;
}

// مقایسهٔ اعشاری با تلورانس صریح (نه ==) تا خطای نمایش IEEE یک آزمون درست را
// قرمز نکند؛ 5e-7 کمتر از هر tick واقعی قیمت است.
bool SelfTestEq(const double a, const double b) { return MathAbs(a-b)<=0.0000005; }

string SelfTestD(const double v) { return DoubleToString(v,5); }

// ساختارهای محلی MQL5 تضمین مقدار اولیه ندارند؛ پیش از استفاده صفرشان می‌کنیم تا
// اگر lookup شکست خورد، خواندن فیلدها در رشتهٔ گزارش حافظهٔ ناخواسته ندهد.
void SelfTestOBReset(OBObj &ob)
{
   ob.id=0; ob.time=0; ob.top=0.0; ob.bottom=0.0; ob.direction=DIR_NONE;
   ob.displacementId=-1; ob.structureEventId=-1; ob.liquidityEventId=-1; ob.fvgId=-1;
   ob.isStandalone=false; ob.hasSweep=false; ob.isExtreme=false; ob.kind=OBK_STANDALONE;
   ob.polarityFlipped=false; ob.retested=false; ob.state=OB_INVALID;
   ob.createdTime=0; ob.brokenTime=0;
}

void SelfTestLiqReset(LiquidityObj &lo)
{
   lo.id=0; lo.type=LIQ_PDH; lo.scope=SCOPE_INTERNAL; lo.state=LSTATE_INVALID;
   lo.price=0.0; lo.time=0; lo.sweptTime=0; lo.sweptByEventId=-1; lo.isHTF=false;
}

bool SelfTestFindFVG(const long id, double &topOut, double &bottomOut, int &kindOut)
{
   for(int i=0;i<ArraySize(g_fvgs);i++)
      if(g_fvgs[i].id==id)
      {
         topOut=g_fvgs[i].top; bottomOut=g_fvgs[i].bottom;
         kindOut=(int)g_fvgs[i].kind;
         return true;
      }
   return false;
}

bool SelfTestFindFVGObj(const long id, FVGObj &out)
{
   for(int i=0;i<ArraySize(g_fvgs);i++)
      if(g_fvgs[i].id==id){ out=g_fvgs[i]; return true; }
   return false;
}

bool SelfTestFindOB(const long id, OBObj &out)
{
   for(int i=0;i<ArraySize(g_obs);i++)
      if(g_obs[i].id==id){ out=g_obs[i]; return true; }
   return false;
}

bool SelfTestFindLiq(const long id, LiquidityObj &out)
{
   for(int i=0;i<ArraySize(g_liquidity);i++)
      if(g_liquidity[i].id==id){ out=g_liquidity[i]; return true; }
   return false;
}

// پرکردن آرایه‌های ساختگی با کندل‌های خنثی/هم‌اندازه تا هیچ الگویی خودبه‌خود
// فعال نشود و هر سناریو فقط همان چیزی را بسنجد که قصدش را دارد.
void SelfTestFillNeutral(double &o[], double &h[], double &l[], double &c[],
                         const int size, const double base, const bool upBars)
{
   for(int i=0;i<size;i++)
   {
      o[i]=base;
      c[i]=upBars? base+0.20 : base-0.20;
      h[i]=base+0.40;
      l[i]=base-0.20;
   }
}

//--------------------------------------------------------------------
// آزمون FVG — هندسهٔ گپ استاندارد، گارد حداقل اندازه، فرمول Implied و
// Volume Imbalance (سه محاسبهٔ مستقل که قبلاً قاطی شده بودند).
//--------------------------------------------------------------------
void SelfTestFVG()
{
   double so[6], sh[6], sl[6], sc[6];
   double tp=0.0, bt=0.0; int kd=-1;

   // --- FVG-1: گپ صعودی استاندارد ---
   // کندل اول (shift 2) high=104.00 · کندل سوم (shift 0) low=105.00 → گپ 1.00
   // انتظار: top = low کندل سوم = 105.00 ، bottom = high کندل اول = 104.00
   ArrayResize(g_fvgs,0);
   g_analysisATR=0.0;                       // گارد حداقل اندازه خاموش تا هندسه خالص سنجیده شود
   SelfTestFillNeutral(so,sh,sl,sc,6,100.0,true);
   so[2]=103.20; sc[2]=103.80; sh[2]=104.00; sl[2]=103.00;   // کندل اول
   so[0]=105.20; sc[0]=105.80; sh[0]=106.00; sl[0]=105.00;   // کندل سوم
   DetectFVG(so,sh,sl,sc,0,-1);
   bool f1=SelfTestFindFVG(StableZoneId(BarTime(0),DIR_BULL,1),tp,bt,kd);
   SelfTestRow("FVG_STANDARD_BULL",
      f1 && SelfTestEq(tp,105.00) && SelfTestEq(bt,104.00) && kd==(int)FVGK_STANDARD,
      "top=105.00000 bottom=104.00000 kind=STANDARD",
      f1? StringFormat("top=%s bottom=%s kind=%d",SelfTestD(tp),SelfTestD(bt),kd) : "no zone registered");

   // --- FVG-2: گپ نزولی استاندارد ---
   // شرط نزولی: high(کندل سوم) < low(کندل اول) → top = low کندل اول ، bottom = high کندل سوم
   // کندل اول low=105.00 · کندل سوم high=104.00 → گپ 1.00
   ArrayResize(g_fvgs,0);
   SelfTestFillNeutral(so,sh,sl,sc,6,100.0,true);
   so[2]=105.20; sc[2]=105.60; sh[2]=105.80; sl[2]=105.00;   // کندل اول
   so[0]=103.80; sc[0]=103.40; sh[0]=104.00; sl[0]=103.20;   // کندل سوم
   DetectFVG(so,sh,sl,sc,0,-1);
   bool f2=SelfTestFindFVG(StableZoneId(BarTime(0),DIR_BEAR,1),tp,bt,kd);
   SelfTestRow("FVG_STANDARD_BEAR",
      f2 && SelfTestEq(tp,105.00) && SelfTestEq(bt,104.00) && kd==(int)FVGK_STANDARD,
      "top=105.00000 bottom=104.00000 kind=STANDARD",
      f2? StringFormat("top=%s bottom=%s kind=%d",SelfTestD(tp),SelfTestD(bt),kd) : "no zone registered");

   // --- FVG-3: نبود گپ (هیچ الگویی نباید ثبت شود) ---
   ArrayResize(g_fvgs,0);
   SelfTestFillNeutral(so,sh,sl,sc,6,100.0,true);
   DetectFVG(so,sh,sl,sc,0,-1);
   bool f3=SelfTestFindFVG(StableZoneId(BarTime(0),DIR_BULL,1),tp,bt,kd)
         || SelfTestFindFVG(StableZoneId(BarTime(0),DIR_BEAR,1),tp,bt,kd);
   SelfTestRow("FVG_NO_GAP_REGISTERS_NOTHING", !f3,
      "0 standard zones registered",
      StringFormat("g_fvgs=%d",ArraySize(g_fvgs)));

   // --- FVG-4/5: گارد حداقل اندازه (InpMinFVG_ATR × ATR تحلیل) ---
   if(InpMinFVG_ATR>0.0)
   {
      // با ATR=1.00 و InpMinFVG_ATR=0.10 → حداقل گپ = 0.10
      g_analysisATR=1.0;
      double minGap=InpMinFVG_ATR*g_analysisATR;

      ArrayResize(g_fvgs,0);
      SelfTestFillNeutral(so,sh,sl,sc,6,100.0,true);
      sh[2]=104.00; sl[2]=103.00; so[2]=103.20; sc[2]=103.80;
      sh[0]=106.00; sl[0]=104.05; so[0]=104.20; sc[0]=104.60;   // low[0]-high[2] = 0.05
      DetectFVG(so,sh,sl,sc,0,-1);
      bool smallFound=SelfTestFindFVG(StableZoneId(BarTime(0),DIR_BULL,1),tp,bt,kd);
      SelfTestRow("FVG_MINGAP_REJECTS_SMALL_GAP", !smallFound,
         StringFormat("gap 0.05000 below guard %.5f -> zone must be absent",minGap),
         smallFound? StringFormat("zone WRONGLY registered top=%s bottom=%s",SelfTestD(tp),SelfTestD(bt)) : "zone absent (correct)");

      ArrayResize(g_fvgs,0);
      SelfTestFillNeutral(so,sh,sl,sc,6,100.0,true);
      sh[2]=104.00; sl[2]=103.00; so[2]=103.20; sc[2]=103.80;
      sh[0]=106.00; sl[0]=104.50; so[0]=104.60; sc[0]=105.00;   // low[0]-high[2] = 0.50
      DetectFVG(so,sh,sl,sc,0,-1);
      bool bigFound=SelfTestFindFVG(StableZoneId(BarTime(0),DIR_BULL,1),tp,bt,kd);
      SelfTestRow("FVG_MINGAP_ACCEPTS_LARGE_GAP",
         bigFound && SelfTestEq(tp,104.50) && SelfTestEq(bt,104.00),
         "top=104.50000 bottom=104.00000",
         bigFound? StringFormat("top=%s bottom=%s",SelfTestD(tp),SelfTestD(bt)) : "zone absent");
   }
   else
   {
      SelfTestRow("FVG_MINGAP_REJECTS_SMALL_GAP", true, "guard active (InpMinFVG_ATR>0)", "SKIPPED (InpMinFVG_ATR=0)");
      SelfTestRow("FVG_MINGAP_ACCEPTS_LARGE_GAP", true, "guard active (InpMinFVG_ATR>0)", "SKIPPED (InpMinFVG_ATR=0)");
   }

   // --- FVG-6: فرمول واقعی ICT برای Implied FVG (میانهٔ فتیله‌ها) ---
   // UWM(x)=(H+max(O,C))/2 · LWM(x)=(min(O,C)+L)/2
   // صعودی: LWM(سوم) > UWM(اول) و L(سوم) <= H(اول) → ناحیه: bottom=UWM(اول)، top=LWM(سوم)
   if(InpEnablePhase12 && InpDetectImpliedFVG)
   {
      g_analysisATR=0.0;
      ArrayResize(g_fvgs,0);
      SelfTestFillNeutral(so,sh,sl,sc,6,100.0,true);
      so[2]=102.00; sc[2]=102.40; sh[2]=103.00; sl[2]=101.80;   // کندل اول → UWM=102.70 LWM=101.90
      sh[0]=106.00; sl[0]=102.90; so[0]=103.50; sc[0]=105.00;   // کندل سوم → LWM=103.20 UWM=105.50
      DetectFVG(so,sh,sl,sc,0,-1);
      bool fi=SelfTestFindFVG(StableZoneId(BarTime(0),DIR_BULL,3),tp,bt,kd);
      SelfTestRow("FVG_IMPLIED_BULL_MIDWICK_FORMULA",
         fi && SelfTestEq(tp,103.20) && SelfTestEq(bt,102.70) && kd==(int)FVGK_IMPLIED,
         "top=103.20000 bottom=102.70000 kind=IMPLIED",
         fi? StringFormat("top=%s bottom=%s kind=%d",SelfTestD(tp),SelfTestD(bt),kd) : "no zone registered");

      // همان هندسه، ولی L(سوم) بالای H(اول) → شرط l3<=h1 می‌شکند و Implied نباید ثبت شود
      ArrayResize(g_fvgs,0);
      SelfTestFillNeutral(so,sh,sl,sc,6,100.0,true);
      so[2]=102.00; sc[2]=102.40; sh[2]=103.00; sl[2]=101.80;
      sh[0]=106.00; sl[0]=103.50; so[0]=103.80; sc[0]=105.00;   // l3=103.50 > h1=103.00
      DetectFVG(so,sh,sl,sc,0,-1);
      bool fiBad=SelfTestFindFVG(StableZoneId(BarTime(0),DIR_BULL,3),tp,bt,kd);
      SelfTestRow("FVG_IMPLIED_BULL_REQUIRES_L3_LE_H1", !fiBad,
         "implied zone must be absent when L(third) > H(first)",
         fiBad? StringFormat("zone WRONGLY registered top=%s bottom=%s",SelfTestD(tp),SelfTestD(bt)) : "zone absent (correct)");

      // --- FVG-7: Volume Imbalance — گپ **بدنه‌ها** (نه فتیله‌ها)، مفهوم مستقل ---
      if(InpDetectVolumeImbalance)
      {
         ArrayResize(g_fvgs,0);
         SelfTestFillNeutral(so,sh,sl,sc,6,100.0,true);
         so[2]=102.00; sc[2]=102.40; sh[2]=103.00; sl[2]=101.80;
         sh[0]=106.00; sl[0]=102.90; so[0]=103.50; sc[0]=105.00;
         DetectFVG(so,sh,sl,sc,0,-1);
         bool fv=SelfTestFindFVG(StableZoneId(BarTime(0),DIR_BULL,5),tp,bt,kd);
         SelfTestRow("FVG_VOLUME_IMBALANCE_IS_SEPARATE_KIND",
            fv && SelfTestEq(tp,105.00) && SelfTestEq(bt,102.40) && kd==(int)FVGK_VOL_IMBALANCE,
            "top=105.00000 bottom=102.40000 kind=VOL_IMBALANCE",
            fv? StringFormat("top=%s bottom=%s kind=%d",SelfTestD(tp),SelfTestD(bt),kd) : "no zone registered");
      }
      else
         SelfTestRow("FVG_VOLUME_IMBALANCE_IS_SEPARATE_KIND", true,
            "volume imbalance ON", "SKIPPED (InpDetectVolumeImbalance=off)");
   }
   else
   {
      SelfTestRow("FVG_IMPLIED_BULL_MIDWICK_FORMULA", true, "implied detection ON", "SKIPPED (InpEnablePhase12/InpDetectImpliedFVG off)");
      SelfTestRow("FVG_IMPLIED_BULL_REQUIRES_L3_LE_H1", true, "implied detection ON", "SKIPPED (InpEnablePhase12/InpDetectImpliedFVG off)");
      SelfTestRow("FVG_VOLUME_IMBALANCE_IS_SEPARATE_KIND", true, "implied detection ON", "SKIPPED (InpEnablePhase12/InpDetectImpliedFVG off)");
   }
}

//--------------------------------------------------------------------
// آزمون فاز ۴۳ — وارونگی گپ (iFVG): یک جهت، یک نقش، یک گزارش
//--------------------------------------------------------------------
// چرا این آزمون لازم است: باگ این بود که تابع وارونگی، جهت گپ را در رجیستری
// **بازنویسی** می‌کرد. در آن حالت جهت، دو معنی داشت (جهت تولد و نقش فعلی) و
// هر مصرف‌کننده بسته به لحظهٔ خواندن چیز دیگری می‌گفت: مربع روی چارت بنفش
// (وارونه)، ردیف فایل تشخیصی «صعودی» (جهت تولد)، و ناحیهٔ انتخابی ستاپ یا
// وارونه می‌شد یا نمی‌شد. هیچ grep ای این را نمی‌گیرد؛ فقط اجرای واقعی تابع
// زنده روی کندل‌های ساختگی با پاسخ معلوم آن را نشان می‌دهد.
void SelfTestFVGPolarity()
{
   double so[6], sh[6], sl[6], sc[6];
   g_analysisATR=0.0;
   ArrayResize(g_fvgs,0);

   // همان هندسهٔ FVG-1: گپ صعودی استاندارد با top=105.00 و bottom=104.00
   SelfTestFillNeutral(so,sh,sl,sc,6,100.0,true);
   so[2]=103.20; sc[2]=103.80; sh[2]=104.00; sl[2]=103.00;   // کندل اول
   so[0]=105.20; sc[0]=105.80; sh[0]=106.00; sl[0]=105.00;   // کندل سوم
   DetectFVG(so,sh,sl,sc,0,-1);

   long stdId=StableZoneId(BarTime(0),DIR_BULL,1);
   FVGObj f; f.id=0; f.direction=DIR_NONE; f.inverted=false; f.invertedTime=0;
   bool found=SelfTestFindFVGObj(stdId,f);
   SelfTestRow("FVG_INVERSION_TARGET_ZONE_PRESENT",
      found && f.direction==DIR_BULL && !f.inverted && SelfTestEq(f.top,105.00) && SelfTestEq(f.bottom,104.00),
      "birth zone present: dir=BULL inverted=0 top=105.00000 bottom=104.00000",
      found? StringFormat("dir=%d inverted=%d top=%s bottom=%s",(int)f.direction,(f.inverted?1:0),SelfTestD(f.top),SelfTestD(f.bottom))
            : "standard bull zone not registered");

   // یک کندل بستهٔ قاطع **زیر** مرز گپ (close 103.50 < bottom 104.00) → وارونگی
   int secs=PeriodSeconds(PERIOD_CURRENT);
   if(secs<=0) secs=60;
   datetime later=(datetime)((long)f.createdTime+(long)secs*2L);
   UpdateFVG_Lifecycle(103.90, 103.40, 103.50, later);

   FVGObj g; g.id=0; g.direction=DIR_NONE; g.inverted=false; g.invertedTime=0;
   bool after=SelfTestFindFVGObj(stdId,g);
   int actDir=(int)FVGActiveDir(g);

   // (۱) پرچم و زمان وارونگی ثبت شده است — شاهد عددی، نه ادعا
   SelfTestRow("FVG_INVERSION_FLAG_AND_TIME",
      after && g.inverted && g.invertedTime==later,
      StringFormat("inverted=1 invertedTime=%s",TimeToString(later,TIME_DATE|TIME_MINUTES)),
      after? StringFormat("inverted=%d invertedTime=%s",(g.inverted?1:0),
                          g.invertedTime>0? TimeToString(g.invertedTime,TIME_DATE|TIME_MINUTES):"0")
            : "zone vanished after inversion");

   // (۲) جهت **تولد** هرگز تغییر نمی‌کند (این همان خطای اصلی بود)
   SelfTestRow("FVG_INVERSION_KEEPS_BIRTH_DIRECTION",
      after && g.direction==DIR_BULL,
      "dir=BULL (0) — the birth direction is immutable",
      after? StringFormat("dir=%d (%s)",(int)g.direction,DirToStr(g.direction)) : "zone vanished");

   // (۳) ولی نقش فعلی عوض شده است — همان چیزی که رنگ و ستاپ باید بگویند
   SelfTestRow("FVG_INVERSION_SWITCHES_ACTIVE_ROLE",
      after && actDir==(int)DIR_BEAR,
      "activeDir=BEAR (1) after a close below the bottom edge",
      after? StringFormat("activeDir=%d (%s)",actDir,DirToStr(FVGActiveDir(g))) : "zone vanished");

   // (۴) هندسه و شناسه دست‌نخورده‌اند: نام آبجکت روی چارت از همین شناسه ساخته
   //     می‌شود، پس اگر جهت عوض شود نام با محتوا نمی‌خواند
   SelfTestRow("FVG_INVERSION_KEEPS_GEOMETRY_AND_ID",
      after && SelfTestEq(g.top,105.00) && SelfTestEq(g.bottom,104.00) && g.id==stdId,
      "top=105.00000 bottom=104.00000 id unchanged",
      after? StringFormat("top=%s bottom=%s idStable=%s",SelfTestD(g.top),SelfTestD(g.bottom),(g.id==stdId?"1":"0"))
            : "zone vanished");

   // (۵) پنل و CSV از همین یک تابع رشته می‌سازند، پس خروجی گزارش هم سنجیده می‌شود
   SelfTestRow("FVG_INVERSION_REPORTS_ONE_DIRECTION",
      after && FVGPolarityReport(g)=="BULLISH -> BEARISH (iFVG)",
      "panel and CSV row read: BULLISH -> BEARISH (iFVG)",
      after? FVGPolarityReport(g) : "zone vanished");

   // (۶) وارونگی یک‌طرفه است: بسته‌شدن بعدی از سمت مخالف، نقش را برنمی‌گرداند
   //     (واژهٔ iFVG یعنی همین سطح یک‌بار جابه‌جا شده، نه اینکه هر کندل عوض شود)
   datetime later2=(datetime)((long)later+(long)secs);
   UpdateFVG_Lifecycle(105.60, 105.20, 105.50, later2);
   FVGObj h; h.id=0; h.direction=DIR_NONE; h.inverted=false; h.invertedTime=0;
   bool after2=SelfTestFindFVGObj(stdId,h);
   SelfTestRow("FVG_INVERSION_IS_ONE_WAY",
      after2 && h.inverted && h.direction==DIR_BULL && (int)FVGActiveDir(h)==(int)DIR_BEAR && h.invertedTime==later,
      "inverted stays 1, dir stays BULL, active stays BEAR, invertedTime unchanged",
      after2? StringFormat("inverted=%d dir=%d activeDir=%d invertedTime=%s",(h.inverted?1:0),(int)h.direction,
                           (int)FVGActiveDir(h), h.invertedTime>0? TimeToString(h.invertedTime,TIME_DATE|TIME_MINUTES):"0")
            : "zone vanished");

   ArrayResize(g_fvgs,0);
}

//--------------------------------------------------------------------
// آزمون OB — کدام کندل مبدأ ناحیه می‌شود، بدنه یا کل کندل، حالت اعتبار،
// Core/Standalone، اتصال به Sweep، سقف عقب‌گرد جست‌وجو و dedup.
//--------------------------------------------------------------------
void SelfTestOB()
{
   double so[12], sh[12], sl[12], sc[12];
   const int dispBar=2;
   g_leg.valid=false;                       // scope ناحیه در آزمون قطعی باشد (Internal)
   g_analysisATR=0.0;

   // مبنا: همهٔ کندل‌ها صعودی و کوچک‌اند (کندل مخالف برای Displacement صعودی نیستند)
   SelfTestFillNeutral(so,sh,sl,sc,12,100.0,true);

   // --- OB-1: کندل مخالف واقعی در idx3، DisplacementId ندارد → OB_INVALID ---
   // انتظار: مبدأ = idx3 (آخرین کندل نزولی پیش از Displacement)، جهت = BULL
   so[2]=100.50; sc[2]=102.00; sh[2]=102.20; sl[2]=100.30;   // کندل Displacement صعودی
   so[3]=101.00; sc[3]=100.00; sh[3]=101.20; sl[3]= 99.80;   // کندل مخالف (نزولی)
   ArrayResize(g_obs,0);
   DetectOB(so,sh,sl,sc,dispBar,-1,-1,-1,-1,0.0);
   long expId=StableZoneId(iTime(_Symbol,PERIOD_CURRENT,3),DIR_BULL,2);
   OBObj ob;
   SelfTestOBReset(ob);
   bool found=SelfTestFindOB(expId,ob);
   double expTop = InpOBUseFullCandleRange? 101.20 : 101.00;
   double expBot = InpOBUseFullCandleRange?  99.80 : 100.00;
   SelfTestRow("OB_ORIGIN_IS_LAST_OPPOSITE_BAR",
      found && SelfTestEq(ob.top,expTop) && SelfTestEq(ob.bottom,expBot) && ob.direction==DIR_BULL,
      StringFormat("top=%s bottom=%s dir=BULL (origin bar shift 3)",SelfTestD(expTop),SelfTestD(expBot)),
      found? StringFormat("top=%s bottom=%s dir=%d",SelfTestD(ob.top),SelfTestD(ob.bottom),(int)ob.direction) : "no zone registered");
   SelfTestRow("OB_NO_DISPLACEMENT_IS_INVALID",
      found && ob.state==OB_INVALID,
      "state=OB_INVALID (displacementId=-1)",
      found? StringFormat("state=%d",(int)ob.state) : "no zone registered");
   SelfTestRow("OB_STANDALONE_WHEN_NO_STRUCTURE_EVENT",
      found && ob.isStandalone && ob.kind==OBK_STANDALONE && !ob.hasSweep,
      "isStandalone=true kind=STANDALONE hasSweep=false",
      found? StringFormat("isStandalone=%s kind=%d hasSweep=%s",
            ob.isStandalone?"true":"false",(int)ob.kind,ob.hasSweep?"true":"false") : "no zone registered");

   // --- OB-2: با زنجیرهٔ کامل → OB_VALID + Core + hasSweep ---
   ArrayResize(g_obs,0);
   DetectOB(so,sh,sl,sc,dispBar,1000,5000,77,-1,0.0);
   found=SelfTestFindOB(expId,ob);
   SelfTestRow("OB_VALID_WITH_DISPLACEMENT",
      found && ob.state==OB_VALID,
      "state=OB_VALID (displacementId given)",
      found? StringFormat("state=%d",(int)ob.state) : "no zone registered");
   SelfTestRow("OB_CORE_AND_SWEEP_LINKED",
      found && !ob.isStandalone && ob.kind==OBK_CORE && ob.hasSweep && ob.structureEventId==5000 && ob.liquidityEventId==77,
      "isStandalone=false kind=CORE hasSweep=true structureEventId=5000 liquidityEventId=77",
      found? StringFormat("isStandalone=%s kind=%d hasSweep=%s structId=%I64d liqId=%I64d",
            ob.isStandalone?"true":"false",(int)ob.kind,ob.hasSweep?"true":"false",ob.structureEventId,ob.liquidityEventId)
           : "no zone registered");

   // --- OB-3 (dedup): همان ناحیه دوباره → نباید ردیف تکراری بسازد ---
   int before=ArraySize(g_obs);
   long dedupBefore=g_obsDeduped;
   DetectOB(so,sh,sl,sc,dispBar,1000,5000,77,-1,0.0);
   SelfTestRow("OB_DEDUP_SAME_ZONE_NOT_REPEATED",
      ArraySize(g_obs)==before && g_obsDeduped==dedupBefore+1,
      StringFormat("registry stays %d, dedup counter +1",before),
      StringFormat("registry=%d dedupDelta=%I64d",ArraySize(g_obs),g_obsDeduped-dedupBefore));

   // --- OB-4: کندل مخالف بیرون از سقف عقب‌گرد → هیچ ناحیه‌ای ثبت نشود ---
   // کندل مخالف در idx11 یعنی فاصلهٔ 9 کندل از Displacement؛ سقف پیش‌فرض 6 است.
   SelfTestFillNeutral(so,sh,sl,sc,12,100.0,true);
   so[2]=100.50; sc[2]=102.00; sh[2]=102.20; sl[2]=100.30;
   so[11]=101.00; sc[11]=100.00; sh[11]=101.20; sl[11]=99.80;
   ArrayResize(g_obs,0);
   DetectOB(so,sh,sl,sc,dispBar,1000,5000,77,-1,0.0);
   SelfTestRow("OB_LOOKBACK_LIMIT_REJECTS_FAR_ORIGIN",
      ArraySize(g_obs)==0 && InpOB_LookbackBars<9,
      "0 zones (opposite bar 9 back, InpOB_LookbackBars<9)",
      StringFormat("g_obs=%d lookback=%d",ArraySize(g_obs),InpOB_LookbackBars));

   // --- OB-5: Displacement نزولی → مبدأ = کندل صعودی پیش از آن ---
   SelfTestFillNeutral(so,sh,sl,sc,12,100.0,true);
   so[2]=102.00; sc[2]=100.50; sh[2]=102.20; sl[2]=100.30;   // Displacement نزولی
   so[3]=100.00; sc[3]=101.00; sh[3]=101.30; sl[3]= 99.90;   // کندل مخالف (صعودی)
   ArrayResize(g_obs,0);
   DetectOB(so,sh,sl,sc,dispBar,1000,-1,-1,-1,0.0);
   long expIdBear=StableZoneId(iTime(_Symbol,PERIOD_CURRENT,3),DIR_BEAR,2);
   bool fBear=SelfTestFindOB(expIdBear,ob);
   double expTopB = InpOBUseFullCandleRange? 101.30 : 101.00;
   double expBotB = InpOBUseFullCandleRange?  99.90 : 100.00;
   SelfTestRow("OB_BEARISH_DISPLACEMENT_ORIGIN",
      fBear && ob.direction==DIR_BEAR && SelfTestEq(ob.top,expTopB) && SelfTestEq(ob.bottom,expBotB),
      StringFormat("top=%s bottom=%s dir=BEAR (origin bar shift 3)",SelfTestD(expTopB),SelfTestD(expBotB)),
      fBear? StringFormat("top=%s bottom=%s dir=%d",SelfTestD(ob.top),SelfTestD(ob.bottom),(int)ob.direction) : "no zone registered");

   ArrayResize(g_obs,0);
}

//--------------------------------------------------------------------
// آزمون Sweep — شرط واقعی جارو (فتیله فراتر + بستهٔ برگشتی)، نبود مثبت کاذب
// در شکست، سطح آینده، سطح قبلاً‌جاروشده و اولویت نزدیک‌ترین سطح.
//--------------------------------------------------------------------
void SelfTestSweep()
{
   datetime tBar = BarTime(1);
   datetime tOld = BarTime(20);
   ENUM_DIRECTION d=DIR_NONE;
   long lvl=0, ret=0;
   LiquidityObj lo;
   SelfTestLiqReset(lo);

   // --- SWEEP-1: BSL جارو شد → جهت نزولی، سطح SWEPT با زمان همان کندل ---
   ArrayResize(g_liquidity,0);
   lvl=AddLiquidity(LIQ_PDH,SCOPE_EXTERNAL,105.0,tOld,false);
   ret=DetectSweep(105.5,104.0,104.5,tBar,d);
   bool s1=(ret==lvl && d==DIR_BEAR);
   SelfTestRow("SWEEP_BSL_SWEPT_IS_BEARISH", s1,
      "returned id = level id, direction = BEAR",
      StringFormat("returned=%I64d level=%I64d dir=%d",ret,lvl,(int)d));
   bool s1b=SelfTestFindLiq(lvl,lo) && lo.state==LSTATE_SWEPT && lo.sweptTime==tBar;
   SelfTestRow("SWEEP_BSL_MARKS_LEVEL_SWEPT", s1b,
      "state=SWEPT sweptTime=the sweeping bar time",
      StringFormat("state=%d sweptTimeMatch=%s",(int)lo.state, lo.sweptTime==tBar?"true":"false"));

   // --- SWEEP-2: همان سطح دوباره نباید جارو شود (فقط FRESH قابل جاروست) ---
   ret=DetectSweep(105.5,104.0,104.5,tBar,d);
   SelfTestRow("SWEEP_ALREADY_SWEPT_NOT_RESWEPT",
      ret==-1 && d==DIR_NONE,
      "returned id = -1, direction = NONE",
      StringFormat("returned=%I64d dir=%d",ret,(int)d));

   // --- SWEEP-3: شکست، نه جارو (بستهٔ بالای سطح) → مثبت کاذب نداشته باشیم ---
   ArrayResize(g_liquidity,0);
   lvl=AddLiquidity(LIQ_PDH,SCOPE_EXTERNAL,105.0,tOld,false);
   ret=DetectSweep(106.0,104.0,105.8,tBar,d);
   bool stayedFresh=SelfTestFindLiq(lvl,lo) && lo.state==LSTATE_FRESH;
   SelfTestRow("SWEEP_BREAK_IS_NOT_A_SWEEP",
      ret==-1 && d==DIR_NONE && stayedFresh,
      "returned id = -1 and level stays FRESH",
      StringFormat("returned=%I64d dir=%d state=%d",ret,(int)d,(int)lo.state));

   // --- SWEEP-4: SSL جارو شد → صعودی ---
   ArrayResize(g_liquidity,0);
   lvl=AddLiquidity(LIQ_PDL,SCOPE_EXTERNAL,100.0,tOld,false);
   ret=DetectSweep(101.0,99.5,100.6,tBar,d);
   SelfTestRow("SWEEP_SSL_SWEPT_IS_BULLISH",
      ret==lvl && d==DIR_BULL,
      "returned id = level id, direction = BULL",
      StringFormat("returned=%I64d level=%I64d dir=%d",ret,lvl,(int)d));

   // --- SWEEP-5: سطحی که هنوز ساخته نشده (زمانش بعد از کندل است) نباید جارو شود ---
   ArrayResize(g_liquidity,0);
   lvl=AddLiquidity(LIQ_PDH,SCOPE_EXTERNAL,105.0,BarTime(1),false);   // زمان سطح جدیدتر از کندل
   ret=DetectSweep(105.5,104.0,104.5,BarTime(5),d);
   bool fresh5=SelfTestFindLiq(lvl,lo) && lo.state==LSTATE_FRESH;
   SelfTestRow("SWEEP_FUTURE_LEVEL_IGNORED",
      ret==-1 && fresh5,
      "returned id = -1 and level stays FRESH",
      StringFormat("returned=%I64d state=%d",ret,(int)lo.state));

   // --- SWEEP-6: دو سطح هم‌زمان جارو شدند → همه علامت می‌خورند، ولی مالک
   //             زنجیره نزدیک‌ترین سطح به قیمت است ---
   ArrayResize(g_liquidity,0);
   long idA=AddLiquidity(LIQ_PDH,SCOPE_EXTERNAL,105.0,tOld,false);   // فاصله 0.60
   long idB=AddLiquidity(LIQ_PWH,SCOPE_EXTERNAL,105.4,tOld,false);   // فاصله 0.20 (نزدیک‌ترین)
   ret=DetectSweep(105.6,104.0,104.0,tBar,d);
   LiquidityObj loA, loB;
   SelfTestLiqReset(loA); SelfTestLiqReset(loB);
   bool aSwept=SelfTestFindLiq(idA,loA) && loA.state==LSTATE_SWEPT;
   bool bSwept=SelfTestFindLiq(idB,loB) && loB.state==LSTATE_SWEPT;
   SelfTestRow("SWEEP_NEAREST_LEVEL_OWNS_THE_CHAIN",
      ret==idB && d==DIR_BEAR,
      "returned id = nearest level (PWH @105.40), direction = BEAR",
      StringFormat("returned=%I64d nearest=%I64d other=%I64d dir=%d",ret,idB,idA,(int)d));
   SelfTestRow("SWEEP_ALL_TOUCHED_LEVELS_MARKED", aSwept && bSwept,
      "both swept levels marked SWEPT",
      StringFormat("pdh=%s pwh=%s",aSwept?"SWEPT":"not",bSwept?"SWEPT":"not"));

   ArrayResize(g_liquidity,0);
}

//--------------------------------------------------------------------
// SENSITIVITY — اثبات اینکه هارنس «دندان» دارد.
// انتظاری **عمداً غلط** اعلام می‌شود: «در این سه کندل یک FVG صعودی استاندارد
// هست». واقعیت این است که نیست. اگر این ردیف FAIL نشود، یعنی مقایسه کار
// نمی‌کند و بقیهٔ PASSها بی‌ارزش‌اند. ابزار Validate-Phase37 دقیقاً همین یک
// ردیف FAIL را الزامی می‌داند.
//--------------------------------------------------------------------
void SelfTestSensitivity()
{
   double so[6], sh[6], sl[6], sc[6];
   double tp=0.0, bt=0.0; int kd=-1;
   g_analysisATR=0.0;
   ArrayResize(g_fvgs,0);
   SelfTestFillNeutral(so,sh,sl,sc,6,100.0,true);   // سه کندل بدون هیچ گپی
   DetectFVG(so,sh,sl,sc,0,-1);
   bool claimFound=SelfTestFindFVG(StableZoneId(BarTime(0),DIR_BULL,1),tp,bt,kd);
   SelfTestRow("SENSITIVITY_probe_must_report_FAIL", claimFound,
      "a bullish standard FVG exists in these three bars (deliberately false claim)",
      claimFound? "claim held - harness cannot detect a wrong expectation" : "claim rejected (harness has teeth)");
   ArrayResize(g_fvgs,0);
}

void SelfTestWrite()
{
   int h=FileOpen("ICT_Assistant_Canonical_SelfTest.csv",
                  FILE_COMMON|FILE_WRITE|FILE_CSV|FILE_UNICODE,';');
   if(h==INVALID_HANDLE)
   {
      PrintFormat("ICT PHASE37 | ERR=%d | نوشتن گزارش آزمون رفتاری ناموفق بود",GetLastError());
      return;
   }
   FileWrite(h,"Scenario","Expected","Actual","Pass");
   int pass=0, fail=0;
   for(int i=0;i<ArraySize(g_selfTestName);i++)
   {
      FileWrite(h,g_selfTestName[i],g_selfTestExp[i],g_selfTestAct[i],g_selfTestOk[i]);
      if(g_selfTestOk[i]==1) pass++; else fail++;
   }
   FileClose(h);
   // FAIL=1 همان ردیف SENSITIVITY طراحی‌شده است؛ عدد بزرگ‌تر یعنی آزمون واقعاً
   // چیزی را رد کرده و باید بررسی شود.
   PrintFormat("ICT PHASE37 | behavioral self-test on synthetic data: rows=%d PASS=%d FAIL=%d | report ICT_Assistant_Canonical_SelfTest.csv",
               ArraySize(g_selfTestName),pass,fail);
}

void RunBehaviorSelfTest(const int need)
{
   if(!InpRunBehaviorSelfTest || g_selfTestWritten) return;
   // سری زمانی باید به‌قدر کافی بار داشته باشد تا BarTime/iTime معنا داشته باشند.
   if(need<60) return;
   g_selfTestWritten=1;

   // وضعیت زنده ذخیره می‌شود؛ آزمون نباید هیچ ردی روی تحلیل واقعی بگذارد.
   bool   savedRebuild=g_rebuildMode;
   double savedATR    =g_analysisATR;
   bool   savedLeg    =g_leg.valid;
   long   savedDedup  =g_obsDeduped;

   ArrayResize(g_selfTestName,0); ArrayResize(g_selfTestExp,0);
   ArrayResize(g_selfTestAct,0);  ArrayResize(g_selfTestOk,0);

   g_rebuildMode=true;    // هیچ آبجکتی از دادهٔ ساختگی روی چارت رسم نشود
   g_leg.valid  =false;   // scope ناحیه‌های آزمون قطعی باشد (Internal)
   g_analysisATR=0.0;

   SelfTestFVG();
   SelfTestFVGPolarity();
   SelfTestOB();
   SelfTestSweep();
   SelfTestSensitivity();

   // رجیستری‌ها به وضعیت خالی برگردانده می‌شوند تا بازسازی واقعی از صفر شروع کند.
   ArrayResize(g_fvgs,0);
   ArrayResize(g_obs,0);
   ArrayResize(g_liquidity,0);

   g_rebuildMode=savedRebuild;
   g_analysisATR=savedATR;
   g_leg.valid  =savedLeg;
   g_obsDeduped =savedDedup;

   SelfTestWrite();
}

//====================================================================
// OnCalculate — فقط کندل بسته؛ سیگنال‌ها هرگز با کندل در حال شکل‌گیری
// ساخته نمی‌شوند. در لحظهٔ attach، تاریخچهٔ اخیر یک‌بار بازسازی می‌شود تا
// چارت از همان ابتدا پر باشد (و همین مسیر، مبنای بازپخش برای اعتبارسنجی است).
//====================================================================
int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
{
   if(rates_total < InpSwingLeft+InpSwingRight+10) return 0;

   // OnCalculate input arrays are not assumed to be series. MQL5 documents
   // that bar 0 is current only when the array is series-oriented.
   bool inputIsSeries=ArrayGetAsSeries(time);
   int currentIndex=inputIsSeries?0:rates_total-1;
   int closedIndex=inputIsSeries?1:rates_total-2;
   if(closedIndex<0) return 0;

   static datetime lastProcessedBarTime = 0;
   bool isNewBar = (time[currentIndex] != lastProcessedBarTime);
   if(isNewBar) lastProcessedBarTime = time[currentIndex];

   // --- فاز ۲۴ (کارایی): کپی سری‌ها فقط وقتی واقعاً لازم است ---
   // همهٔ تحلیل این اندیکاتور روی کندل *بسته* است (shift>=1)، پس داده روی هر
   // tick مصرف نمی‌شود. قبلاً پنج Copy روی هر tick اجرا می‌شد: تا ۲۰۰۰ کندل ×
   // ۵ سری (≈۱۰ هزار مقدار + تخصیص آرایهٔ داینامیک) در هر tick، در حالی که
   // مستند رسمی MQL5 می‌گوید برای فراخوانی‌های پرتکرار باید هزینهٔ تخصیص حافظه
   // را حذف کرد. اینجا کپی/تحلیل فقط در «کندل تازهٔ بسته» یا «بازسازی اولیه»
   // اتفاق می‌افتد؛ بقیهٔ tickها فقط یک بازگشت سریع دارند.
   bool firstRebuild = (!g_historyRebuilt && InpRebuildHistoryOnAttach);
   if(!isNewBar && !firstRebuild)
   {
      RenderDashboard();          // با داشبورد خاموش هزینهٔ صفر دارد
      RenderRiskStrip();          // فاز ۳۵: نوار در هر tick از آخرین وضعیت کندل بسته رندر می‌شود (با کش متن هزینهٔ صفر)
      PersistPhase14Diagnostics();
      return rates_total;
   }

   double h[], l[], c[], o[];
   ArraySetAsSeries(h,true); ArraySetAsSeries(l,true); ArraySetAsSeries(c,true); ArraySetAsSeries(o,true);
   int need = MathMin(rates_total, 2000);
   // در خطای موقت داده، مهر کندل پاک می‌شود تا tick بعد دوباره تلاش شود
   // (وگرنه تا کندل بعدی هیچ تحلیلی انجام نمی‌شد).
   if(CopyOpen(_Symbol,PERIOD_CURRENT,0,need,o)<=0)   { lastProcessedBarTime=0; return 0; }
   if(CopyHigh(_Symbol,PERIOD_CURRENT,0,need,h)<=0)   { lastProcessedBarTime=0; return 0; }
   if(CopyLow(_Symbol,PERIOD_CURRENT,0,need,l)<=0)    { lastProcessedBarTime=0; return 0; }
   if(CopyClose(_Symbol,PERIOD_CURRENT,0,need,c)<=0)  { lastProcessedBarTime=0; return 0; }

   double atrBuf[];
   ArraySetAsSeries(atrBuf,true);
   if(CopyBuffer(g_atrHandle,0,0,need,atrBuf)<=0)     { lastProcessedBarTime=0; return 0; }

   // فاز ۴۰: هر پنج سری باید مرز یکسانی داشته باشند. Copy* فقط به تعداد
   // کندل‌های آماده پر می‌کند، و بافر ATR بی‌درنگ بعد از ساخت هندل روی
   // تایم‌فریم تازه می‌تواند کوتاه‌تر از بقیه باشد. قبلاً مرز حلقه از
   // ArraySize(h) گرفته می‌شد و بقیهٔ آرایه‌ها می‌توانستند کوچک‌تر باشند ⇒
   // array out of range. حالا مرز = کوچک‌ترین سری.
   int avail=ArraySize(h);
   avail=MathMin(avail,ArraySize(o));
   avail=MathMin(avail,ArraySize(l));
   avail=MathMin(avail,ArraySize(c));
   avail=MathMin(avail,ArraySize(atrBuf));
   if(avail<InpSwingLeft+InpSwingRight+12) { lastProcessedBarTime=0; return 0; }

   RefreshBarTimeCache(need);   // فاز ۲۴: یک CopyTime جای ده‌ها iTime در حلقه‌ها

   // فاز ۳۷: آزمون رفتاری روی دادهٔ ساختگی — یک‌بار در هر attach، همین‌جا که سری
   // زمانی در دسترس است (BarTime/iTime کار می‌کنند) ولی رجیستری‌ها هنوز خالی‌اند.
   // خودِ آزمون رجیستری‌ها را پس از پایان صفر می‌کند، پس بازسازی واقعی پایین‌تر
   // دقیقاً همان چیزی را می‌بیند که اگر آزمون خاموش بود می‌دید.
   RunBehaviorSelfTest(need);

   // --- بازسازی تاریخچه در لحظهٔ attach (قدیم به جدید) ---
   if(!g_historyRebuilt && InpRebuildHistoryOnAttach)
   {
      int maxScan = avail - InpSwingLeft - InpSwingRight - 12;
      if(maxScan > InpHistoryScanBars) maxScan = InpHistoryScanBars;
      if(maxScan < 10) maxScan = 0;
      g_rebuildMode = true;
      g_probeOn=InpLogPerfOnRebuild;
      g_diagHoldOn=true;         // فاز ۲۴: هندل مشترک فایل‌های شاهد در بازسازی
      if(g_probeOn) ProbeReset();
      uint rbStart=GetTickCount();
      long rt0=PROBE_T0;
      for(int shift=maxScan; shift>=1; shift--)
      {
         datetime barT=BarTime(shift);          // فاز ۲۴: بدون iTime در حلقه
         long q0=PROBE_T0;
         AnalyzeClosedBar(shift, o,h,l,c, atrBuf);
         PROBE_END("1.analyze",q0);
         q0=PROBE_T0;
         UpdateContextForClosedBar(barT, c[shift], atrBuf[shift], h[shift], l[shift]);
         PROBE_END("2.context",q0);
         q0=PROBE_T0;
         UpdateExhaustion(o,h,l,c,shift,atrBuf[shift]);
         PROBE_END("3.exhaustion",q0);
         q0=PROBE_T0;
         UpdateTrendPhase(barT);   // فاز ۱۲ (#۹)
         PROBE_END("4.trendPhase",q0);
         q0=PROBE_T0;
         PersistPhase12Diagnostics(barT);
         PROBE_END("5.persist12",q0);
      }
      PROBE_END("0.loopTotal",rt0);
      g_rebuildMode = false;
      DiagHoldRelease();         // فاز ۲۴: بستن هندل‌های شاهد پس از بازسازی
      g_historyRebuilt = true;
      // shift=1 was already processed by the rebuild. Mark the current
      // forming bar as seen so the same closed bar is not processed twice.
      lastProcessedBarTime = time[currentIndex];
      isNewBar = false;

      // فاز ۱۳ (پایداری): در پایان بازسازی لایهٔ گرافیکی هم‌گام می‌شود.
      // قبلاً این تابع صدا زده نمی‌شد و چارت تا کندل بستهٔ بعدی ناهمگام می‌ماند
      // (ایراد «rebuild بدون redraw»). چون در کل بازسازی هیچ آبجکتی رسم نمی‌شود
      // (!g_rebuildMode)، این تنها نقطهٔ رسم اولیه است و دو بار رسم رخ نمی‌دهد.
      long rd0=PROBE_T0;
      RedrawChartObjects();
      PROBE_END("6.firstRedraw",rd0);

      // فاز ۴۴: آزمون مسیر کلیک — همین‌جا که همهٔ آبجکت‌ها روی چارت رسم شده‌اند
      // و هیچ کلیکی رخ نداده. همان توابع زندهٔ hit-test و سازندهٔ پنل اجرا
      // می‌شوند، پس آزمون یک پیاده‌سازی موازی نیست. یک‌بار در هر attach.
      static bool clickTestDone=false;
      if(!clickTestDone)
      {
         clickTestDone=true;
         long ct0=PROBE_T0;
         RunClickPathSelfTest();
         PROBE_END("7.clickPathTest",ct0);
      }
      if(InpLogPerfOnRebuild)
         Print(StringFormat("ICT PHASE13 | rebuild %d bars in %d ms | events %d(+%d dropped) | disp %d(+%d dropped) | HTF eval runs %d / skipped %d | ledger index builds %d hits %d | session copies %d reuses %d | EQ skips %d",
               maxScan, (int)(GetTickCount()-rbStart),
               ArraySize(g_events), (int)g_eventsDropped,
               ArraySize(g_displacements), (int)g_dispDropped,
               (int)g_htfEvalRuns, (int)g_htfEvalSkips,
               (int)g_ledgerCacheBuilds, (int)g_ledgerCacheHits,
               (int)g_winCacheCopies, (int)g_winCacheReuses,
               (int)g_eqSkips));
      Print(StringFormat("ICT PHASE29 | OB dedup merged %d | OB registry %d / cap %d",
            (int)g_obsDeduped, ArraySize(g_obs), InpMaxOB));
      if(g_probeOn)                       // فاز ۲۴: تفکیک هزینهٔ هر مرحله (میکروثانیه)
      {
         Print("ICT PHASE24 | profile (top 16, us) | "+ProbeDumpTop(16));
         g_probeOn=false;
      }
   }

   if(isNewBar)
   {
      AnalyzeClosedBar(1, o,h,l,c, atrBuf);

      // --- Context کامل، یک‌بار در هر کندل بسته و بر مبنای زمان همان کندل ---
      datetime closedBar = time[closedIndex];
      UpdateContextForClosedBar(closedBar, c[1], atrBuf[1], h[1], l[1]);
      UpdateExhaustion(o,h,l,c,1,atrBuf[1]);
      // فاز ۴۶: درجهٔ سیگنال بعد از فرسودگی و ریسک برگشت همان کندل بسته
      // محاسبه می‌شود، وگرنه یکی از هفت ویژگی از کندل قبلی می‌آمد. ثبت شاهد CSV
      // هم عمداً همین‌جا (بعد از درجه) انجام می‌شود تا ردیف فایل با همان کندل بخواند.
      UpdateSignalGrade();
      PersistReverseRiskEvidence();
      // فاز ۴۷: سناریوی در انتظار — بعد از دروازهٔ برگشت و درجه، چون به سطح
      // محافظت‌شدهٔ همان کندل بسته و بایاس مالک نگاه می‌کند. هیچ‌چیز نمی‌نویسد و
      // فقط از کندل بسته می‌خواند، پس نه ریپنت می‌کند و نه روی تحلیل اثر دارد.
      UpdatePendingScenario(atrBuf[1]);
      UpdateTrendPhase(closedBar);   // فاز ۱۲ (#۹)
      PersistPhase12Diagnostics(closedBar);

      RedrawChartObjects();
   }

   // فاز ۱۴: داشبورد رندر می‌شود و شاهد عددی همان pass نوشته می‌شود
   // (باید بعد از RenderDashboard باشد تا اعداد DashRows/DashWidth جاری باشند،
   //  نه اعداد pass قبلی).
   RenderDashboard();
   RenderRiskStrip();               // فاز ۳۵: بعد از UpdateReverseRiskِ همان pass
   CleanupLegacyPendingRow();       // فاز ۴۸: پاک‌سازی یک‌بارهٔ ردیف جداگانهٔ بیلد قبلی
   PersistPhase14Diagnostics();
   return rates_total;
}
//+------------------------------------------------------------------+
//====================================================================
// فاز ۴۶ — درجهٔ سیگنال (A+/A/B+/B/C): «تیتر بالای چارت» که قبلاً وجود نداشت
//
// چرا این فایل ساخته شد
// --------------------
// نوار تک‌خطی گوشهٔ چارت (فاز ۳۵) فقط «ریسک برگشت» را نشان می‌داد: یک امتیاز
// ۰..۱۰۰ از وزن‌های دستی. با اندازه‌گیری روی دادهٔ واقعی خودِ کاربر معلوم شد
// آن امتیاز **هیچ چیزی را رتبه‌بندی نمی‌کند** (برد در برچسب LOW ۲۹٫۲٪ و در
// HIGH ۲۹٫۳٪ بود، یعنی تفاوت صفر). پس تیتری که باید بگوید «این سیگنال A+ است
// یا C» عملاً وجود نداشت.
//
// این ماژول آن را می‌سازد و — مهم‌تر — ضرایبش را از سر خود درنمی‌آورد:
//
//   tools/Fit-SignalGrade.ps1   (اجرای بازتولیدپذیر روی CSV خودِ اندیکاتور)
//     • هر کندل را با یک «مسابقه» به آینده می‌برد: +۲ برابر ATR در جهت بایاس
//       در برابر −۱ برابر ATR خلاف آن، داخل ۱۲ کندل → WIN / LOSS / OPEN
//     • برای هر مقدار ویژگی، «لیفت لگاریتمی-شانسی» روی خط پایه می‌سنجد
//     • درجه = مجموع لیفت‌ها؛ آستانه‌ها از چارک‌های همان توزیع سنجیده‌شده
//     • خروجی، برد واقعی هر درجه است: A+ ۵۲٫۲٪ · A ۴۱٫۲٪ · B+ ۳۵٫۵٪ ·
//       B ۳۱٫۲٪ · C ۲۵٫۸٪  (خط پایه ۲۹٫۴٪، ۵۵۱۹ نمونه، XAUUSD)
//
// محدودیت صادقانه (بخوان): این اعداد روی نمونهٔ ثبت‌شدهٔ همین نماد سنجیده
// شده‌اند (n=۹۲ برای A+). پس درجه یک «شمارش شاهدِ کالیبره‌شده» است، نه وعدهٔ
// درصد. هر عددی که کنار درجه می‌بینی، همان نرخ اندازه‌گیری‌شده است.
//====================================================================

// --- نقشِ نزدیک‌ترین سطح: کد خانواده (همان قاعده‌ای که ابزار فیت به کار می‌برد)
// قاعده روی پیشوندِ لاتینِ متن سطح کار می‌کند، پس مستقل از متن فارسی است.
string RRLevelFamilyCode(string lvl)
{
   string u=lvl;
   StringToUpper(u);
   // پیشوندها باید لفظ‌به‌لفظ با Get-Family در tools/Fit-SignalGrade.ps1 یکی
   // باشند، وگرنه درجهٔ اجراشده با درجهٔ فیت‌شده یکی نمی‌شود.
   if(StringFind(u,"LIQ")==0)              return "famLIQ";
   if(StringFind(u,"OB ")==0)               return "famOB";
   if(StringFind(u,"BREAKER")==0)           return "famBREAKER";
   if(StringFind(u,"MITIGATION")==0)        return "famMITIG";
   if(StringFind(u,"VOLUME IMBALANCE")==0)  return "famFVGVI";
   if(StringFind(u,"FVG")==0)               return "famFVG";
   if(StringFind(u,"S/D")==0)               return "famSD";
   if(StringFind(u,"TRENDLINE")==0)         return "famTL";
   return "famOTHER";
}

string RRLevelFamilyFa(string code)
{
   if(code=="famBREAKER") return "بریکر";
   if(code=="famFVGVI")   return "ناترازی حجمی";
   if(code=="famLIQ")     return "نقدینگی";
   if(code=="famFVG")     return "گپ ارزش منصفانه";
   if(code=="famMITIG")   return "بلاک تخفیف";
   if(code=="famOB")      return "اردربلاک";
   if(code=="famSD")      return "عرضه و تقاضا";
   if(code=="famTL")      return "خط روند";
   return "سایر سطوح";
}

// --- سطل‌ها: عیناً همان مرزهایی که ابزار فیت استفاده می‌کند
string GradeDistBucket(double d)
{
   if(d<0.25) return "distLt025";
   if(d<0.5)  return "dist025to05";
   if(d<1.0)  return "dist05to1";
   return "distGt1";
}
string GradeLegBucket(double l)
{
   if(l<50.0) return "legLt50";
   if(l<85.0) return "leg50to85";
   return "legGte85";
}
string GradeDolBucket(double d)
{
   if(d<=0.0) return "dolNone";
   if(d<=0.5) return "dolLe05";
   if(d<=1.0) return "dol05to1";
   return "dolGt1";
}
string GradeExhKey()
{
   // کلید فرسودگی عیناً همان چیزی است که ابزار فیت می‌سازد: پیشوند exh +
   // نام لاتین وضعیت. یکسان‌بودن کلیدها شرط اثبات هم‌ارزی در ابزار قفل‌کننده است.
   return "exh"+ExhaustionStateToStr(g_exhaustion.state);
}

// --- جدول لیفت‌ها (سنجیده‌شده؛ منبع: tools/Fit-SignalGrade.ps1)
// ورودی هر تابع، کلید سطل است؛ سطل‌هایی که نمونه‌شان زیر کف بود صفر می‌مانند
// و همین صفر بودن هم مستند است (نه حدس).
double GradeLiftF1(string f)
{
   if(f=="famBREAKER") return  0.489;
   if(f=="famFVGVI")   return  0.277;
   if(f=="famLIQ")     return  0.252;
   if(f=="famFVG")     return -0.101;
   if(f=="famMITIG")   return -0.154;
   if(f=="famOB")      return -0.653;
   return 0.0;                    // famSD / famTL / famOTHER: نمونه کمتر از کف
}
double GradeLiftF2(string b)
{
   if(b=="distLt025")   return -0.040;
   if(b=="dist025to05") return  0.294;
   if(b=="dist05to1")   return  0.490;
   if(b=="distGt1")     return  0.115;
   return 0.0;
}
double GradeLiftF3(string b)
{
   if(b=="legLt50")   return  0.003;
   if(b=="leg50to85") return  0.677;
   if(b=="legGte85")  return -0.028;
   return 0.0;
}
double GradeLiftF4(string b)
{
   if(b=="dolNone") return -0.223;
   if(b=="dolGt1")  return  0.003;
   return 0.0;                    // dolLe05 / dol05to1: نمونه کمتر از کف
}
double GradeLiftF5(bool aligned) { return aligned? 0.110 : -0.033; }
double GradeLiftF6(bool swept)   { return swept? 0.032 : -0.001; }
double GradeLiftF7(string e)
{
   if(e=="exhREVERSAL_CONFIRMED")         return  0.598;
   if(e=="exhRANGE_OR_TRANSITION")        return  0.112;
   if(e=="exhEXHAUSTION_WATCH")           return  0.046;
   if(e=="exhEXTENDING")                  return  0.025;
   if(e=="exhTRENDING")                   return -0.030;
   if(e=="exhMICRO_PULLBACK")             return -0.078;
   if(e=="exhMICRO_REVERSAL_CONFIRMED")   return -0.171;
   return 0.0;                    // exhNEUTRAL: نمونه کمتر از کف
}

// --- آستانه‌ها: چارک‌های همان توزیع سنجیده‌شده (بازتولید با همان ابزار)
string GradeFromScore(double s)
{
   if(s>=0.827) return "A+";
   if(s>=0.564) return "A";
   if(s>=0.297) return "B+";
   if(s>=0.106) return "B";
   return "C";
}
// نرخ بردِ همان درجه — عدد ثابت نیست: از همان سنجش می‌آید و در پنل با n
// نشان داده می‌شود تا کاربر بداند این یک وعده نیست، یک اندازه‌گیری است.
double GradeMeasuredWin(string g)
{
   if(g=="A+") return 52.2;
   if(g=="A")  return 41.2;
   if(g=="B+") return 35.5;
   if(g=="B")  return 31.2;
   if(g=="C")  return 25.8;
   return 29.4;
}
int GradeMeasuredN(string g)
{
   if(g=="A+") return   92;
   if(g=="A")  return  306;
   if(g=="B+") return  707;
   if(g=="B")  return 1115;
   if(g=="C")  return 3299;
   return 5519;
}
string GradeFa(string g)
{
   if(g=="—")  return "بدون جهت";
   if(g=="A+") return "بهترین هم‌جهتی با بایاس";
   if(g=="A")  return "هم‌جهتی قوی";
   if(g=="B+") return "هم‌جهتی متوسط رو به بالا";
   if(g=="B")  return "هم‌جهتی ضعیف";
   if(g=="C")  return "هم‌جهتی ضعیف یا مخالف شواهد";
   return "تعیین نشده";
}

// رنگ نوار: چون سرِ ردیف حالا درجه است، رنگ هم درجه را می‌گوید (کیفیت
// هم‌جهتی)، نه ریسک برگشت را. اگر درجه تعیین نشده باشد به رنگ خنثی برمی‌گردد.
color GradeStripColor()
{
   if(g_grade=="A+") return clrLime;
   if(g_grade=="A")  return clrGreenYellow;
   if(g_grade=="B+") return clrGold;
   if(g_grade=="B")  return clrDarkOrange;
   if(g_grade=="C")  return clrGray;
   return InpColorNeutral;
}

// --- محاسبه: برای هر کندل *بسته*، یک‌بار. هیچ‌جا از آینده خبری نیست.
// اگر بایاس وجود نداشته باشد، درجه معنی ندارد و «—» می‌ماند.
void UpdateSignalGrade()
{
   g_grade="—"; g_gradeScore=0.0; g_gradeWhy=""; g_gradeFam="";
   g_gradeWin=0.0; g_gradeN=0;
   if(!InpEnableSignalGrade) return;
   if(g_htfBias==DIR_NONE)
   {
      g_gradeWhy="بایاس جهت‌دار وجود ندارد، پس شواهد هم‌جهت معنی ندارد";
      return;
   }

   string fam=RRLevelFamilyCode(g_rrLevel);
   string b2=GradeDistBucket(g_rrLevelDist);
   string b3=GradeLegBucket(g_rrLegProg);
   string b4=GradeDolBucket(g_rrDolDist);
   string e7=GradeExhKey();

   double l1=GradeLiftF1(fam);
   double l2=GradeLiftF2(b2);
   double l3=GradeLiftF3(b3);
   double l4=GradeLiftF4(b4);
   double l5=GradeLiftF5(!g_mtfConflict);
   double l6=GradeLiftF6(g_barSweptTowardBias);
   double l7=GradeLiftF7(e7);

   g_gradeComputed++;
   g_gradeScore=l1+l2+l3+l4+l5+l6+l7;
   g_grade=GradeFromScore(g_gradeScore);
   g_gradeFam=fam;
   g_gradeWin=GradeMeasuredWin(g_grade);
   g_gradeN=GradeMeasuredN(g_grade);

   // دلیل: بزرگ‌ترین بالابرنده و بزرگ‌ترین کاهنده، به فارسی و با همان عدد.
   double best=l1; string bestFa=RRLevelFamilyFa(fam);
   if(l2>best){ best=l2; bestFa="فاصله تا سطح"; }
   if(l3>best){ best=l3; bestFa="جای قیمت در لگ"; }
   if(l4>best){ best=l4; bestFa="فاصله تا هدف نقدینگی"; }
   if(l5>best){ best=l5; bestFa="همسویی تایم‌فریم‌ها"; }
   if(l6>best){ best=l6; bestFa="جاروی نقدینگی هم‌جهت"; }
   if(l7>best){ best=l7; bestFa="وضعیت فرسودگی"; }

   double worst=l1; string worstFa=RRLevelFamilyFa(fam);
   if(l2<worst){ worst=l2; worstFa="فاصله تا سطح"; }
   if(l3<worst){ worst=l3; worstFa="جای قیمت در لگ"; }
   if(l4<worst){ worst=l4; worstFa="فاصله تا هدف نقدینگی"; }
   if(l5<worst){ worst=l5; worstFa="همسویی تایم‌فریم‌ها"; }
   if(l6<worst){ worst=l6; worstFa="جاروی نقدینگی هم‌جهت"; }
   if(l7<worst){ worst=l7; worstFa="وضعیت فرسودگی"; }

   g_gradeWhy=StringFormat("بالابرنده: %s (%.2f)  |  کاهنده: %s (%.2f)",
                           bestFa, best, worstFa, worst);
}
//====================================================================
// فاز ۴۷ — سناریوی در انتظار (PENDING): «چه چیزی در انتظار بسته شدن کندل است»
//
// چرا این فایل ساخته شد
// --------------------
// دروازهٔ برگشت (فاز ۱۱) صادقانه ولی **پسرو** بود: تا کندل بستهٔ HTF فراتر از
// سطح محافظت‌شده نایستد، هیچ نمی‌گفت. کاربر اما می‌پرسد «الان چه چیزی قرار است
// اتفاق بیفتد و چقدر محتمل است؟». این ماژول همان پرسش را جواب می‌دهد.
//
// قاعدهٔ سخت — این بخش هرگز ریپنت نمی‌کند
// --------------------------------------
// ۱) *تنها* ورودی این ماژول وضعیتِ آخرین کندل **بسته** است: سطح محافظت‌شدهٔ
//    خارجی، قیمت بستهٔ آخرین کندل بستهٔ HTF، بایاس مالک، و ATR کندل بسته.
//    هیچ‌جا Bid/Ask/close کندل جاری خوانده نمی‌شود؛ پس متنِ این ردیف تا زمانی که
//    کندل بعدی بسته نشود **حرف‌به‌حرف ثابت** می‌ماند و هیچ تاریخی را بازنویسی
//    نمی‌کند. (ابزار Validate-Phase47 همین را روی متن کد قفل می‌کند.)
// ۲) این ماژول **صفر نوشتن** دارد: نه رجیستری، نه رویداد، نه بایاس، نه CSV.
//    خروجی‌اش فقط چند متغیر نمایشی (g_pend*) و یک ردیف متنی است. پس هیچ موتور
//    تشخیصی نمی‌تواند از آن اثر بگیرد؛ حتی اگر خاموشش کنی، تحلیل تغییر نمی‌کند.
// ۳) ردیف روی گوشهٔ چارت لنگر شده است، نه روی زمان/قیمت؛ پس با اسکرول یا
//    تغییر مقیاس جابه‌جا نمی‌شود.
//
// عدد «احتمال» از کجا می‌آید (بدون حدس)
// -----------------------------------
//   tools/Fit-PendingScenario.ps1   (بازتولیدپذیر روی دفتر شاهد خودِ اندیکاتور)
//     • ردیف‌های دفتر برگشت را به «اپیزود» می‌شکند: تا وقتی شناسهٔ سویینگ
//       محافظت‌شده عوض نشده، شرطِ انتظار هم عوض نشده است.
//     • در هر اپیزود، وضعیتِ هر کندل بستهٔ HTF نگه داشته می‌شود؛ ARMED یعنی
//       «منتظر» و CONFIRMED یعنی «کندل بسته از سطح گذشت».
//     • فاصلهٔ کندل بسته تا سطح را با ATR همان کندل (از دفتر ریسک برگشت) تقسیم
//       می‌کند و نرخِ «تأیید در کندل بستهٔ بعدی» را در هر سبد می‌شمارد.
//
//   اندازه‌گیری روی نمونهٔ ثبت‌شدهٔ XAUUSD.x (HTF=H4، چارت M15، ۳۰۰ اپیزود،
//   ۲۷۶۷ گذار «منتظر»):
//     | فاصله تا سطح      | نمونه | تأیید در کندل بعد | نرخ     |
//     | کمتر از ۰٫۲ ATR   |   ۲۳  |         ۹         | ۳۹٫۱٪  |
//     | ۰٫۲ تا ۰٫۵ ATR    |   ۳۹  |         ۰         |  ۰٫۰٪  |
//     | ۰٫۵ تا ۱٫۰ ATR    |   ۸۱  |         ۰         |  ۰٫۰٪  |
//     | ۱٫۰ تا ۲٫۰ ATR    |  ۱۶۸  |         ۳         |  ۱٫۸٪  |
//     | بیشتر از ۲٫۰ ATR  | ۲۴۵۶  |         ۰         |  ۰٫۰٪  |
//     خط پایهٔ کل: ۰٫۴٪
//
//   خواندنِ درستِ این عدد: «تأیید در همان کندل بستهٔ بعدی» نادر است مگر قیمت از
//   قبل تقریباً روی سطح باشد (کمتر از ۰٫۲ برابر دامنه). یعنی این ردیف می‌گوید
//   «بازار باید اول راه بیفتد»؛ به همین دلیل فاصله و مقصد نقدینگی هم کنارش
//   می‌آید. سبدِ کمتر از ۰٫۲ ATR فقط ۲۳ نمونه دارد؛ این عدد یک اندازه‌گیری است
//   روی یک نماد و یک پنجرهٔ آرشیو، نه وعدهٔ درصد — و تعداد نمونه همیشه کنارش
//   نوشته می‌شود.
//====================================================================

void PendClear()
{
   g_pendValid=false;
   g_pendState="OFF";
   g_pendTriggerFa="";
   g_pendGuardDistATR=0.0;
   g_pendBucket="";
   g_pendRate=0.0;
   g_pendRateN=0;
   g_pendMagnetName="";
   g_pendMagnetTypeFa="";
   g_pendMagnetPrice=0.0;
   g_pendMagnetDistATR=0.0;
   g_pendBaselineRate=0.0;
   g_pendLineText="";
}

// سبد فاصله — مرزها باید لفظ‌به‌لفظ با Get-PendBucket در ابزار فیت یکی باشند،
// وگرنه نرخِ اجراشده با نرخِ سنجیده‌شده یکی نمی‌شود (همان قاعدهٔ فاز ۴۶).
string PendBucketCode(double d)
{
   if(d<0.20) return "pendLt020";
   if(d<0.50) return "pend020to050";
   if(d<1.00) return "pend050to100";
   if(d<2.00) return "pend100to200";
   return "pendGt200";
}

// --- جدول سنجیده‌شده (منبع: tools/Fit-PendingScenario.ps1) ---
double PendMeasuredRate(string b)
{
   if(b=="pendLt020")   return 39.1;
   if(b=="pend020to050") return  0.0;
   if(b=="pend050to100") return  0.0;
   if(b=="pend100to200") return  1.8;
   if(b=="pendGt200")    return  0.0;
   return 0.0;
}
int PendMeasuredN(string b)
{
   if(b=="pendLt020")   return   23;
   if(b=="pend020to050") return   39;
   if(b=="pend050to100") return   81;
   if(b=="pend100to200") return  168;
   if(b=="pendGt200")    return 2456;
   return 0;
}

// نام فارسی نوع نقدینگیِ مقصد. چرا لازم است: برچسب لاتین (PDH، EQH، ASIA LOW…)
// وسط جملهٔ فارسی، خط را به دو قطعه می‌شکند و خواندنش به‌هم می‌ریزد (قاعدهٔ
// RTL فاز ۴۲). پس در ردیف، فقط نوع فارسی می‌آید و برچسب لاتین به پنل می‌رود.
string PendLiqTypeFa(ENUM_LIQ_TYPE t)
{
   switch(t)
   {
      case LIQ_PDH:            return "سقف روز قبل";
      case LIQ_PDL:            return "کف روز قبل";
      case LIQ_PWH:            return "سقف هفتهٔ قبل";
      case LIQ_PWL:            return "کف هفتهٔ قبل";
      case LIQ_EQH:            return "سقف‌های برابر";
      case LIQ_EQL:            return "کف‌های برابر";
      case LIQ_SWING_H:        return "سقف سوئینگ";
      case LIQ_SWING_L:        return "کف سوئینگ";
      case LIQ_SESSION_H:      return "سقف سشن";
      case LIQ_SESSION_L:      return "کف سشن";
      case LIQ_RANGE_H:        return "سقف رنج";
      case LIQ_RANGE_L:        return "کف رنج";
      case LIQ_IPDA20_H:       return "سقف ۲۰ روزه";
      case LIQ_IPDA20_L:       return "کف ۲۰ روزه";
      case LIQ_IPDA40_H:       return "سقف ۴۰ روزه";
      case LIQ_IPDA40_L:       return "کف ۴۰ روزه";
      case LIQ_IPDA60_H:       return "سقف ۶۰ روزه";
      case LIQ_IPDA60_L:       return "کف ۶۰ روزه";
      case LIQ_TRENDLINE_H:    return "خط روند بالایی";
      case LIQ_TRENDLINE_L:    return "خط روند پایینی";
   }
   return "سطح نقدینگی";
}

string PendStateFa(string s)
{
   if(s=="NO_BIAS")       return "بایاس جهت‌دار وجود ندارد، پس شرط انتظار معنا ندارد";
   if(s=="NO_GUARD")      return "سطح محافظت‌شدهٔ خارجی در رجیستری تایم‌فریم بالاتر پیدا نشد";
   if(s=="NO_ATR")        return "میانگین دامنهٔ کندل بسته صفر است، پس فاصله قابل سنجش نیست";
   if(s=="CONFIRMED_NOW") return "همین کندل بسته برگشت را تأیید کرد؛ چیزی در انتظار نیست";
   if(s=="WAITING")       return "منتظر بستهٔ کندل تایم‌فریم بالاتر هستیم";
   if(s=="OFF")           return "سناریوی در انتظار خاموش است";
   return "وضعیت نامشخص";
}

//--------------------------------------------------------------------
// محاسبه — فقط از کندل بسته، بدون هیچ نوشتنی.
// atrValue همان ATR کندل بسته است (همان‌که به UpdateReverseRisk می‌رود).
//--------------------------------------------------------------------
void UpdatePendingScenario(double atrValue)
{
   PendClear();
   if(!InpEnablePendingScenario) return;

   // ۱) بایاس جهت‌دار: بدون آن، «برگشت» و «مقصد نقدینگی» معنا ندارد.
   if(g_htfBias==DIR_NONE){ g_pendState="NO_BIAS"; return; }

   // ۲) سطح محافظت‌شدهٔ خارجی و قیمت بستهٔ آخرین کندل بستهٔ HTF.
   if(!g_reversal.snapGuardOk || g_reversal.snapBarClose<=0.0 || g_reversal.levelPrice<=0.0)
   { g_pendState="NO_GUARD"; return; }
   if(atrValue<=0.0){ g_pendState="NO_ATR"; return; }

   // ۳) مقصد نقدینگی: نزدیک‌ترین سطح **جارونشده** در جهت بایاس. برای بایاس
   //    نزولی مقصد سمت فروش است (کف‌ها) و برای صعودی سمت خرید (سقف‌ها) —
   //    همان معنای «میرود نقدینگی جمع کند».
   double bestD=1e18;
   for(int i=0;i<ArraySize(g_liquidity);i++)
   {
      if(g_liquidity[i].state!=LSTATE_FRESH) continue;
      bool highSide=IsHighSideLiquidity(g_liquidity[i].type);
      if(g_htfBias==DIR_BEAR && highSide)  continue;
      if(g_htfBias==DIR_BULL && !highSide) continue;
      double d=MathAbs(g_reversal.snapBarClose-g_liquidity[i].price)/atrValue;
      if(d>=bestD) continue;
      bestD=d;
      g_pendMagnetName=LiqTypeLabel(g_liquidity[i].type);
      g_pendMagnetTypeFa=PendLiqTypeFa(g_liquidity[i].type);
      g_pendMagnetPrice=g_liquidity[i].price;
      g_pendMagnetDistATR=d;
   }

   // ۴) اگر همین کندل بسته برگشت را تأیید کرده باشد، «انتظار» بی‌معناست.
   if(g_reversal.confirmed && g_reversal.confirmedTime==g_reversal.snapBarTime)
   {
      g_pendState="CONFIRMED_NOW";
      g_pendValid=true;
      g_pendComputed++;
      return;
   }

   // ۵) شرط انتظار: ماشه = بستهٔ HTF در جهت مخالف بایاس.
   //    (بایاس صعودی با بستهٔ **زیر** سطح محافظت‌شده باطل می‌شود.)
   bool breakDown=(g_htfBias==DIR_BULL);
   g_pendGuardDistATR=MathAbs(g_reversal.snapBarClose-g_reversal.levelPrice)/atrValue;
   g_pendBucket=PendBucketCode(g_pendGuardDistATR);
   g_pendRate=PendMeasuredRate(g_pendBucket);
   g_pendRateN=PendMeasuredN(g_pendBucket);
   g_pendBaselineRate=0.4;      // خط پایهٔ کل همان سنجش (۰٫۴٪ روی ۲۷۶۷ گذار)
   g_pendTriggerFa=StringFormat("بستهٔ %s %s", breakDown? "زیر":"بالای",
                                DoubleToString(g_reversal.levelPrice,_Digits));
   g_pendState="WAITING";
   g_pendValid=true;
   g_pendComputed++;
}

//--------------------------------------------------------------------
// فاز ۴۸ — قطعهٔ «مسیر» برای نوار یکپارچهٔ گوشهٔ چارت.
//
// چرا ردیف جداگانه حذف شد: دو ردیف تک‌خطی روی هم («درجه» و «در انتظار») عملاً
// یک واقعیت را دو بار می‌گفتند و کاربر مجبور بود هر دو را بخواند تا مسیر را
// بفهمد. حالا یک ردیف است و این تابع فقط قطعهٔ «مقصد و شرط برگشت» را می‌دهد؛
// ساخت خود ردیف در RenderRiskStrip است.
//
// قرارداد: برگرداندن رشتهٔ خالی یعنی «چیزی برای گفتن نیست» — نوار در آن حالت
// خودش جانشین می‌گذارد. هیچ محاسبهٔ تازه‌ای اینجا نیست؛ فقط گره‌های g_pend*
// به فارسی ریخته می‌شوند تا یک عدد دو روایت نداشته باشد.
// قاعدهٔ RTL فاز ۴۲: هیچ واژهٔ لاتین وسط جملهٔ فارسی نمی‌آید؛ فقط عدد و جهت
// و نام کوتاه تایم‌فریم در قطعه‌های جداگانه.
//--------------------------------------------------------------------
string PendingFragmentFa()
{
   if(g_pendState=="OFF" || g_pendState=="") return "";
   if(g_pendState=="NO_BIAS" || g_pendState=="NO_GUARD" || g_pendState=="NO_ATR")
      return "  |  مسیر: "+PendStateFa(g_pendState);

   string magnet="";
   if(g_pendMagnetPrice>0.0)
      magnet=StringFormat("  |  مقصد: %s %.2f", g_pendMagnetTypeFa, g_pendMagnetPrice);

   if(g_pendState=="CONFIRMED_NOW")
      return magnet+"  |  برگشت همین کندل بسته تأیید شد";

   return StringFormat("%s  |  برگشت: %s — نرخ %.1f%% از %d نمونه",
                       magnet, g_pendTriggerFa, g_pendRate, g_pendRateN);
}

// فاز ۴۸: رسم ردیف جداگانه حذف شد. اشیای ICTv13_PEND_BG / ICTv13_PEND_TXT
// ممکن است از بیلد قبلی روی چارت باقی مانده باشند؛ پاک‌سازی یک‌باره اینجا
// انجام می‌شود تا با یک بار attach چارت تمیز شود (بدون نیاز به Remove دستی).
void CleanupLegacyPendingRow()
{
   if(g_pendRowCleaned) return;
   g_pendRowCleaned=true;
   if(ObjectFind(0,"ICTv13_PEND_BG")>=0)  ObjectDelete(0,"ICTv13_PEND_BG");
   if(ObjectFind(0,"ICTv13_PEND_TXT")>=0) ObjectDelete(0,"ICTv13_PEND_TXT");
}

//--------------------------------------------------------------------
// توضیح فارسی همین ردیف (کلیک/هنگ روی آن). قاعده: ردیف‌های لاتین یا تمام‌لاتین
// می‌مانند و توضیح فارسی در ردیف بعدی می‌آید.
//--------------------------------------------------------------------
// keepTitle=true یعنی این بخش در پنل یکپارچهٔ «مسیر» به‌عنوان ادامه می‌آید و
// نباید عنوان پنل را بازنویسی کند (فاز ۴۸: یک کلیک، یک پنل، یک روایت).
void ExplainPendingScenario(bool keepTitle=false)
{
   if(!keepTitle) g_expTitle="PENDING — آنچه در انتظار بسته شدن کندل است";
   else ExpAddWrapped("بخش دوم: شرط برگشت و مقصد نقدینگی — همان دو عددی که در نوار یکپارچه دیده می‌شوند", clrAqua);
   ExpAddWrapped("چیست: این ردیف آینده را پیش‌بینی نمی‌کند؛ یک شرط را می‌گوید: اگر کندل بستهٔ تایم‌فریم بالاتر از یک سطح مشخص بگذرد، برگشت تأیید می‌شود و اگر نگذرد، هیچ چیز تأیید نمی‌شود", clrWhite);
   ExpAdd(StringFormat("state: %s | bias: %s | htf: %s",
           g_pendState, DirToStr(g_htfBias), TfFa(InpHTF)), clrAqua);
   ExpAddWrapped(PendStateFa(g_pendState), clrSilver);
   if(g_pendState=="WAITING")
   {
      ExpAdd("trigger: "+g_pendTriggerFa, clrAqua);
      ExpAdd(StringFormat("guard: %s %s | last closed htf close: %s | distance: %.2f ATR",
              g_reversal.levelIsHigh? "HIGH":"LOW", DoubleToString(g_reversal.levelPrice,_Digits),
              DoubleToString(g_reversal.snapBarClose,_Digits), g_pendGuardDistATR), clrAqua);
      ExpAdd(StringFormat("bucket: %s | measured next-close confirmation: %.1f%% | n: %d | baseline: %.1f%%",
              g_pendBucket, g_pendRate, g_pendRateN, g_pendBaselineRate), clrAqua);
      ExpAddWrapped("معنی این عدد: در نمونهٔ ثبت‌شده، وقتی فاصلهٔ کندل بسته تا سطح در همین سبد بود، چند بار کندل بستهٔ بعدی واقعاً از سطح گذشت. این «درصد موفقیت معامله» نیست، نرخ همان رویداد است", clrSilver);
      ExpAddWrapped("نکتهٔ مهم سنجش: تا وقتی قیمت از قبل تقریباً روی سطح نباشد (کمتر از ۰٫۲ برابر دامنه)، تأیید در کندل بعدی عملاً رخ نمی‌دهد؛ یعنی انتظارِ «همین کندل» واقع‌بینانه نیست و بازار اول باید حرکت کند", clrOrange);
      ExpAddWrapped("شمارش سبدِ نزدیک فقط ۲۳ نمونه دارد و روی یک نماد و یک پنجرهٔ آرشیو سنجیده شده؛ پس این یک اندازه‌گیری است، نه وعدهٔ درصد", clrOrange);
   }
   if(g_pendMagnetPrice>0.0)
   {
      ExpAdd(StringFormat("magnet: %s %s | distance: %.2f ATR",
              g_pendMagnetName, DoubleToString(g_pendMagnetPrice,_Digits), g_pendMagnetDistATR), clrAqua);
      ExpAddWrapped("چرا این سطح: در جهت بایاس، نزدیک‌ترین سطح نقدینگی **جارونشده** انتخاب شده است؛ چون هدف حرکت، برداشتن همان نقدینگی است و برگشت معمولاً بعد از رسیدن به آن سنجیده می‌شود", clrLime);
   }
   else
      ExpAddWrapped("در جهت بایاس، سطح نقدینگی جارونشده‌ای در رجیستری نیست؛ پس مقصدی هم اعلام نمی‌شود", clrSilver);
   ExpAddWrapped("چطور خودت بسنجی: با ابزار سنجش همین مخزن، نرخ و تعداد نمونه را از دفتر شاهد بازتولید کن؛ اگر با عدد روی ردیف نخواند، حساب غلط است", clrAqua);
   ExpAdd("provenance: tools/Fit-PendingScenario.ps1", clrSilver);
   ExpAddWrapped("چرا ریپنت نمی‌کند: همهٔ ورودی‌های این ردیف از آخرین کندل **بسته** می‌آید (سطح محافظت‌شده، قیمت بستهٔ آن، بایاس مالک، میانگین دامنهٔ همان کندل). تا کندل بعدی بسته نشود، این متن حرف‌به‌حرف ثابت می‌ماند و هیچ تاریخی بازنویسی نمی‌شود", clrLime);
   ExpAddWrapped("چه چیزی آن را بی‌اعتبار می‌کند: بسته شدن کندل بعدی (که یا تأیید می‌کند یا فاصله را عوض می‌کند)، یا عوض شدن سطح محافظت‌شده و بایاس مالک", clrOrange);
   ExpAdd("object name: ICTv13_RSTRIP_TXT (ردیف یکپارچهٔ مسیر — خواندنی، غیرقابل‌جابه‌جایی)", clrSilver);
}
