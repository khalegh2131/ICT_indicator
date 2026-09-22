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

   // فاز ۴۹: پروفایل نماد + کالیبراسیون درجهٔ همین نماد.
   // اگر فایل کالیبراسیون همین نماد/تایم‌فریم موجود باشد، جدول ثابت جایش را
   // می‌دهد (LoadGradeCalibration)؛ اگر نباشد، صفر می‌ماند و UI صریح می‌گوید
   // اعداد از نماد مرجع آمده‌اند. پس روی هیچ نمادی عدد جابه‌جا نماد جا نمی‌زند.
   LoadGradeCalibration();
   WriteSymbolProfileDiag();

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

