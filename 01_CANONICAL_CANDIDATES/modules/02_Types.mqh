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

