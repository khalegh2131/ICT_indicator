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
