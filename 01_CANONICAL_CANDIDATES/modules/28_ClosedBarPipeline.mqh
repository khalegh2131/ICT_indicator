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

