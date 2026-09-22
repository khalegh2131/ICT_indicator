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

