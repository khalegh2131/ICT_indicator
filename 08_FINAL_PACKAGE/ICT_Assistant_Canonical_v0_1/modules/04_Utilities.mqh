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

