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

