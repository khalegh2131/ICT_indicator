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

