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

// --- فاز ۴۹: کالیبراسیون درجه به‌ازای هر نماد. اگر فایل کالیبراسیون همین
// نماد/تایم‌فریم روی دیسک باشد، همین‌جا بار می‌شود و جدول ثابت ۳۱_SignalGrade
// کنار می‌رود. اگر نباشد، g_calLoaded صفر می‌ماند و UI صریح می‌گوید اعداد از
// نماد مرجع آمده‌اند (GradeSourceFa).
string   g_calKeys[];
double   g_calVals[];
bool     g_calLoaded=false;
int      g_calRows=0;
string   g_calSource="none";
string   g_calSymbol="";
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

