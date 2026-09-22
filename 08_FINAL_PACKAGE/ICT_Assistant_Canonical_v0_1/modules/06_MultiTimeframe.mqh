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

