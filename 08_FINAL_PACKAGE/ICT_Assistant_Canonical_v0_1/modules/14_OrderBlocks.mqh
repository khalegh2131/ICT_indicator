//====================================================================
// OB ENGINE — رفع ایراد ۹،۱۲: OB باید زنجیره اثبات کامل داشته باشد
// و Core/Standalone در یک Registry واحد باشند (فقط با فلگ isStandalone
// از هم تفکیک می‌شوند، نه دو آرایه جدا)
//====================================================================
void DetectOB(const double &open[], const double &high[], const double &low[], const double &close[],
              int dispBarShift, long displacementId, long structureEventId, long liquidityEventId, long fvgId,
              double atrOfLast=0.0)
{
   // آخرین کندل مخالف‌رنگ قبل از Displacement (نه فقط کندل بلافاصله قبل)
   bool dispDown = close[dispBarShift] < open[dispBarShift]; // جهت دیسپلیسمنت
   ENUM_DIRECTION obDir = dispDown? DIR_BEAR : DIR_BULL;
   int obShift = -1;
   int backLimit = ArraySize(open)-dispBarShift-1;
   int lookback  = (InpOB_LookbackBars>0)? InpOB_LookbackBars : 1;
   if(backLimit>lookback) backLimit=lookback;
   for(int k=1;k<=backLimit;k++)
   {
      int idx=dispBarShift+k;
      bool opposite = dispDown ? (close[idx] > open[idx]) : (close[idx] < open[idx]);
      if(opposite){ obShift=idx; break; }
   }
   if(obShift<0) return;

   OBObj o;
   o.time = iTime(_Symbol, PERIOD_CURRENT, obShift);
   o.id = StableZoneId(o.time,obDir,2);
   if(InpOBUseFullCandleRange)
   {
      o.top = high[obShift];
      o.bottom = low[obShift];
   }
   else
   {
      o.top = MathMax(open[obShift], close[obShift]);
      o.bottom = MathMin(open[obShift], close[obShift]);
   }
   o.direction = obDir;
   o.displacementId = displacementId;
   o.structureEventId = structureEventId;   // -1 یعنی ناحیهٔ Standalone (فاز ۱۲)
   o.liquidityEventId = liquidityEventId;   // -1 مجاز است، ولی اگر باشد Breaker بعداً قوی‌تر می‌شود
   o.fvgId = fvgId;
   // --- فاز ۱۲ (#۳۵ #۳۶ #۳۸) ---
   // Core = ناحیه در شکست ساختار مشارکت کرده. Standalone = Displacement هست
   // ولی شکست ساختاری وجود ندارد. Extreme و Mitigation Block در پاس بعدی
   // (MarkExtremeOrderBlocks و UpdateOB_MitigationAndBreaker) برچسب می‌خورند.
   o.isStandalone = (structureEventId==-1);
   o.hasSweep     = (liquidityEventId!=-1);
   o.isExtreme    = false;
   o.kind = o.isStandalone ? OBK_STANDALONE : OBK_CORE;
   o.polarityFlipped = false;
   o.retested = false;
   o.createdTime = iTime(_Symbol, PERIOD_CURRENT, dispBarShift);
   o.brokenTime = 0;
   o.tf = PERIOD_CURRENT;   // فاز ۱۶+: مالکیت تایم‌فریم (روی چارت جاری ساخته شده)
   // فاز ۳۶: تفکیک Internal/External OB — طبق منبع (LuxAlgo — Internal vs
   // External Range Liquidity) ناحیه‌ای که مبدأ/اکسترمم لگ معامله‌گری است
   // External (ERL) و ناحیه‌ای که «left inside the leg» است Internal (IRL) است.
   // سنجش در لحظهٔ تولید با اکسترمم لگِ *تازه‌بسته*: فاصله تا مرز نزدیک لگ
   // حداکثر ۱۰٪ ATR → External؛ بقیه Internal. علامت‌گذاری نهایی External در
   // MarkExtremeOrderBlocks هم ادامه دارد (یک OB در هر سر لگ).
   o.scope = SCOPE_INTERNAL;   // پیش‌فرض: داخل لگ
   if(g_leg.valid)
   {
      double tolExt=(atrOfLast>0.0)? atrOfLast*0.10 : 0.0;
      if(MathAbs(o.top-g_leg.high)<=tolExt || MathAbs(o.bottom-g_leg.low)<=tolExt)
         o.scope=SCOPE_EXTERNAL;
   }

   // رفع ایراد ۹ + تکمیل فاز ۱۲: اعتبار اولیه فقط با Displacement واقعی.
   // نداشتن شکست ساختار ناحیه را «بی‌اعتبار» نمی‌کند؛ فقط Standalone میکند
   // و در امتیاز POI جریمه می‌شود.
   if(displacementId!=-1)
      o.state = OB_VALID;
   else
      o.state = OB_INVALID; // کندل مخالف بدون Displacement — نویز؛ در Setup استفاده نمی‌شود

   // فاز ۲۹ (#۷۳): dedup رجیستری OB — همان کلاس باگی که برای FVG در AppendFVG
   // بسته شده بود ولی اینجا باز مانده بود.
   // چرا رخ می‌دهد (اثبات از ترتیب کد): دو کندل Displacement **پیاپی** در یک
   // رالی/ریزش پرقدرت، هر دو به یک کندل مخالف می‌رسند (چون حداقل یکی از آن دو
   // هم‌رنگ Displacement است)، پس هر دو با StableZoneId **یکسان** ثبت می‌شدند:
   // دو باکس روی‌هم روی چارت، شمارش OB دو برابر، و مصرف سقف InpMaxOB با مناطق
   // تکراری — همان چیزی که چارت را بی‌دلیل شلوغ می‌کرد.
   // رفتار: نخستین ثبت مالک ناحیه است و متادیتای زنجیره فقط «تکمیل» می‌شود
   // (هرگز ضعیف‌تر نمی‌شود: Core شدن، Sweep داشتن، معتبر شدن).
   for(int i=ArraySize(g_obs)-1;i>=0;i--)
   {
      if(g_obs[i].id!=o.id) continue;
      if(g_obs[i].displacementId==-1) g_obs[i].displacementId=o.displacementId;
      if(g_obs[i].fvgId==-1)          g_obs[i].fvgId=o.fvgId;
      if(g_obs[i].structureEventId==-1 && o.structureEventId!=-1)
      {
         g_obs[i].structureEventId=o.structureEventId;
         g_obs[i].isStandalone=false;
         if(g_obs[i].kind==OBK_STANDALONE) g_obs[i].kind=OBK_CORE;
      }
      if(g_obs[i].liquidityEventId==-1 && o.liquidityEventId!=-1)
      {
         g_obs[i].liquidityEventId=o.liquidityEventId;
         g_obs[i].hasSweep=true;
      }
      if(g_obs[i].state==OB_INVALID && o.state==OB_VALID) g_obs[i].state=OB_VALID;
      g_obsDeduped++;
      return;
   }

   int n=ArraySize(g_obs); ArrayResize(g_obs,n+1); g_obs[n]=o;
   if(o.state==OB_VALID && !g_rebuildMode) DrawOB(o);

   if(ArraySize(g_obs) > InpMaxOB)
   {
      for(int i=0;i<ArraySize(g_obs)-1;i++) g_obs[i]=g_obs[i+1];
      ArrayResize(g_obs, InpMaxOB);
   }
}

//====================================================================
// BREAKER ENGINE — رفع ایراد ۱۰،۱۱: Breaker فقط از روی زنجیره کامل:
//   Valid OB -> Structural Violation -> Broken -> Polarity Flip -> Retest -> Breaker
// برچسب تخفیف‌خورده به‌تنهایی هرگز کافی نیست، و ساخته‌شدن پیش از جاروی نقدینگی هم به‌تنهایی
// کافی نیست (باید Retest واقعی هم رخ بدهد).
//====================================================================
void UpdateOB_MitigationAndBreaker(double curHigh, double curLow, double curClose, datetime curBarTime)
{
   int n=ArraySize(g_obs);
   for(int i=0;i<n;i++)
   {
      if(g_obs[i].state==OB_INVALID) continue;
      if(g_obs[i].state==OB_BREAKER) continue;      // زنجیره برای این ناحیه تمام شده
      if(g_obs[i].state==OB_MITIGATION) continue;   // فاز ۱۲: زنجیرهٔ Mitigation Block هم تمام شده

      bool priceInZone = (curLow <= g_obs[i].top && curHigh >= g_obs[i].bottom);
      // ناحیه‌ای که در همین کندل ثبت شده نمی‌تواند در همان کندل MITIGATED شود؛
      // کندل Displacement معمولاً از خود ناحیه شروع می‌شود و همین باعث می‌شد
      // همهٔ OBها همان لحظه مصرف‌شده به‌نظر برسند (#۲۵، همان کلاس باگ).
      bool registeredHere = (g_obs[i].createdTime >= curBarTime);

      // Step 1: Mitigation — فقط لمس، نه شکست
      if(g_obs[i].state==OB_VALID && priceInZone && !registeredHere)
         g_obs[i].state = OB_MITIGATED;

      // Step 2: Structural violation -> BROKEN (بسته‌شدن کامل از سمت مخالف)
      bool violated = false;
      if(g_obs[i].direction==DIR_BULL && curClose < g_obs[i].bottom) violated = true;
      if(g_obs[i].direction==DIR_BEAR && curClose > g_obs[i].top)    violated = true;

      if((g_obs[i].state==OB_VALID || g_obs[i].state==OB_MITIGATED) && violated)
      {
         g_obs[i].state = OB_BROKEN;
         g_obs[i].polarityFlipped = true; // پولاریتی از این لحظه برعکس در نظر گرفته می‌شود
         g_obs[i].brokenTime = curBarTime;
         continue;                        // ریتست باید در کندلی جدا از کندل شکست باشد
      }

      // Step 3: Retest -> BREAKER
      // دو شرط سخت‌گیرانهٔ Breaker (#۳۹):
      //   (۱) ناحیه باید روی یک Sweep واقعی نقدینگی ساخته شده باشد (liquidityEventId).
      //   (۲) ریتست باید در کندلی جداگانه و بعد از کندل شکست رخ دهد.
      if(g_obs[i].state==OB_BROKEN && g_obs[i].polarityFlipped &&
         g_obs[i].liquidityEventId!=-1 &&
         g_obs[i].brokenTime>0 && curBarTime>g_obs[i].brokenTime)
      {
         bool retestHappening =
            (g_obs[i].direction==DIR_BULL && curHigh >= g_obs[i].bottom && curHigh <= g_obs[i].top) ||
            (g_obs[i].direction==DIR_BEAR && curLow  <= g_obs[i].top    && curLow  >= g_obs[i].bottom);

         if(retestHappening)
         {
            g_obs[i].retested = true;
            g_obs[i].state = OB_BREAKER; // فقط الان، بعد از کل زنجیره
            // kind عوض نمی‌شود: Core/Standalone فقط دربارهٔ مشارکت در شکست ساختار
            // است و Breaker یک state است، نه یک نوع دیگر از ناحیه.
         }
      }

      // --- فاز ۱۲ (#۳۸): Mitigation Block **مستقل** ---
      // همان زنجیرهٔ شکست + پولاریتی برعکس + ریتست، ولی **بدون** Sweep
      // نقدینگی روی ناحیه. همین تفاوت، مرز Breaker و Mitigation Block است.
      if(g_obs[i].state==OB_BROKEN && g_obs[i].polarityFlipped &&
         g_obs[i].liquidityEventId==-1 &&
         g_obs[i].brokenTime>0 && curBarTime>g_obs[i].brokenTime)
      {
         bool retestMit =
            (g_obs[i].direction==DIR_BULL && curHigh >= g_obs[i].bottom && curHigh <= g_obs[i].top) ||
            (g_obs[i].direction==DIR_BEAR && curLow  <= g_obs[i].top    && curLow  >= g_obs[i].bottom);
         if(retestMit)
         {
            g_obs[i].retested = true;
            g_obs[i].state = OB_MITIGATION;
            g_obs[i].kind  = OBK_MITIGATION_BLOCK;
         }
      }
   }
}

void UpdateFVG_Lifecycle(double curHigh, double curLow, double curClose, datetime curBarTime)
{
   for(int i=0;i<ArraySize(g_fvgs);i++)
   {
      if(g_fvgs[i].invalidated) continue;
      // ناحیه‌ای که در همین کندل ساخته شده در همان کندل "لمس‌شده" حساب نمی‌شود.
      // کندل سوم الگو همیشه مرز گپ را لمس می‌کند، پس بدون این شرط هر FVG
      // در لحظهٔ تولد MITIGATED می‌شد (#۲۵).
      if(g_fvgs[i].createdTime >= curBarTime) continue;
      bool touched=(curLow<=g_fvgs[i].top && curHigh>=g_fvgs[i].bottom);
      if(touched && !g_fvgs[i].mitigated)
      {
         g_fvgs[i].mitigated=true;
         g_fvgs[i].touchTime=curBarTime;   // فقط برای تشخیص/اثبات؛ منطق امتیازدهی عوض نمی‌شود
      }
      // فاز ۲۸ — Consequent Encroachment (منبع: LuxAlgo Library — Consequent
      // Encroachment / FVG): «خط تصمیم» یک گپ میانهٔ آن است و بیشتر مدل‌ها لمس
      // میانه را «به‌قدر کافی پر شده» می‌دانند. لمس صرفِ لبهٔ ناحیه این معنا را
      // ندارد، پس این دو وضعیت از هم جدا نگه داشته می‌شوند و پنل آموزشی هر دو
      // را جدا می‌گوید (قبلاً فقط یک پرچم mitigated بود و همان هم هر لمسی را
      // «میتیگیت‌شده» اعلام می‌کرد).
      if(!g_fvgs[i].ceTouched && curLow<=g_fvgs[i].ce && curHigh>=g_fvgs[i].ce)
         g_fvgs[i].ceTouched=true;
      // عبور کامل از سمت مخالف => Inversion FVG (iFVG). ناحیه حذف نمی‌شود؛
      // پولاریتی آن برعکس می‌شود و به‌عنوان ناحیهٔ مخالف قابل استفاده است.
      //
      // فاز ۴۳ — اینجا باگ بود: **جهت تولد بازنویسی می‌شد.** `direction` را
      // نمی‌شود عوض کرد، چون سه چیز دیگر به آن گره خورده‌اند:
      //   (۱) هندسهٔ ناحیه: برای گپ صعودی top=کف کندل سوم و bottom=سقف کندل
      //       اول است؛ اگر جهت عوض شود، همان مرزها معنای مخالف می‌دهند و شرط
      //       «بسته‌شدن از سمت مخالف» در همین تابع روی جهت جابه‌جا شده اجرا
      //       می‌شود (یعنی دیگر اگر گپ وارونه یک‌بار دیگر بررسی شود، هیچ‌وقت
      //       نمی‌تواند تشخیص خودش را درست بپذیرد).
      //   (۲) شناسهٔ ناحیه: StableZoneId(زمان، جهت تولد، تفکیک‌کننده) و نام
      //       آبجکت روی چارت از همین شناسه ساخته می‌شود؛ با تغییر جهت، نام
      //       آبجکت دیگر با محتوایش نمی‌خواند.
      //   (۳) نام مکتب (BISI/SIBI) و زنجیرهٔ Displacement، که هر دو تابع
      //       جهتِ سازندهٔ گپ‌اند، نه نقش امروزش.
      // پس فقط پرچم وارونگی و زمانش ثبت می‌شود؛ نقش فعلی با FVGActiveDir()
      // خوانده می‌شود. نتیجه: رنگ، CSV، پنل، انتخاب ناحیهٔ ستاپ و دروازهٔ
      // برگشت همه از یک منبع حرف می‌زنند.
      if(!g_fvgs[i].inverted && g_fvgs[i].direction==DIR_BULL && curClose < g_fvgs[i].bottom)
      {
         g_fvgs[i].inverted=true;
         g_fvgs[i].invertedTime=curBarTime;
      }
      if(!g_fvgs[i].inverted && g_fvgs[i].direction==DIR_BEAR && curClose > g_fvgs[i].top)
      {
         g_fvgs[i].inverted=true;
         g_fvgs[i].invertedTime=curBarTime;
      }
      // انقضای زمانی
      if(InpFVG_ExpireBars>0 && curBarTime>0 && g_fvgs[i].createdTime>0)
      {
         int ageBars=(int)((curBarTime-g_fvgs[i].createdTime)/PeriodSeconds(PERIOD_CURRENT));
         if(ageBars>InpFVG_ExpireBars) g_fvgs[i].invalidated=true;
      }
   }
}

void PersistReplayDiagnostics(datetime barTime)
{
   if(!g_rebuildMode || !InpWriteReplayDiagnostics) return;
   int handle=DiagOpen("ICT_Assistant_Canonical_MTF_Diag.csv");
   if(handle==INVALID_HANDLE) return;
   if(FileSize(handle)==0)
      FileWrite(handle,"BarTime","BiasOwner","H4Confirmed","MTFChain","Conflict","ConflictReason","ReadyState");
   FileSeek(handle,0,SEEK_END);
   string chain="";
   for(int i=0;i<6;i++)
   {
      if(i>0) chain+="|";
      ENUM_DIRECTION extDir=(i==0)?g_htfBias:g_mtfContext[i].externalDirection;
      chain+=EnumToString(g_mtfTimeframes[i])+":"+DirToStr(extDir)+":"+DirToStr(g_mtfContext[i].internalDirection);
   }
   FileWrite(handle,TimeToString(barTime,TIME_DATE|TIME_MINUTES),
             DirToStr(g_htfBias),
             TimeToString(g_mtfContext[0].confirmedBarTime,TIME_DATE|TIME_MINUTES),
             chain,g_mtfConflict?"true":"false",g_mtfConflictReason,g_setup.status);
   DiagClose(handle);
}

void UpdateContextForClosedBar(datetime barTime, double closePrice, double atrValue,
                              double highPrice=0.0, double lowPrice=0.0)
{
   if(barTime<=0) return;
   // آفست بروکر در هر کندل بسته بازآزمایی می‌شود (رفع #۵۵): اگر بروکر آفست را
   // با DST عوض کند، بدون این خط همهٔ پنجره‌های سشن تا reload بعدی غلط می‌مانند.
   RefreshBrokerOffset();
   // فاز ۱۵: آفست *همین لحظهٔ تاریخی* (نه آفست امروز) ثبت می‌شود تا در CSV شاهد
   // عددی داشته باشیم که پنجره‌های سشن با DST تاریخی محاسبه شده‌اند.
   g_histOffsetDeltaMin=(BrokerOffsetSecondsAtServer(barTime)-g_serverGMTOffsetSeconds)/60;
   // فاز ۱۵ (#۶۶): چرخهٔ عمر ستاپ پیش از UpdateSetup سنجیده می‌شود، وگرنه وضعیت
   // ستاپِ در حال پیگیری با ستاپ جدیدِ همین کندل بازنویسی می‌شد و هیچ ابطالی
   // هرگز قابل مشاهده نبود.
   long c0=PROBE_T0;
   UpdateSetupLifecycle(barTime, closePrice, highPrice, lowPrice);
   PROBE_END("2o.lifecycle",c0);
   int chartSeconds=PeriodSeconds(PERIOD_CURRENT);
   if(chartSeconds<=0) chartSeconds=60;
   datetime analysisEnd=(datetime)((long)barTime+(long)chartSeconds-1L);
   c0=PROBE_T0; UpdateHTFStructure(analysisEnd);                    PROBE_END("2a.htf",c0);
   c0=PROBE_T0; UpdateLiquidityRegistry_PDH_PDL_PWH_PWL(analysisEnd); PROBE_END("2b.pdhl",c0);
   c0=PROBE_T0; UpdateSessionContext(analysisEnd);                   PROBE_END("2c.session",c0);
   c0=PROBE_T0; AnalyzeMTFContext(analysisEnd);                      PROBE_END("2d.mtf",c0);
   // فاز ۱۱: دروازهٔ برگشت بعد از تازه‌شدن MTF و پیش از DOL/Setup سنجیده
   // می‌شود تا شواهد SMR (هم‌جهتی کانتکست) از دادهٔ همین کندل باشد.
   c0=PROBE_T0; UpdateReversalEngine(analysisEnd, closePrice, atrValue); PROBE_END("2e.reversal",c0);
   c0=PROBE_T0; UpdateDealingLeg(analysisEnd, atrValue);             PROBE_END("2f.leg",c0);
   // --- فاز ۱۲: بعد از لگ (چون Extreme به اکسترمم لگ وابسته است) ---
   c0=PROBE_T0; MarkExtremeOrderBlocks(atrValue);                    PROBE_END("2g.extremeOB",c0);
   c0=PROBE_T0; BuildTrendlines(atrValue);                           PROBE_END("2h.trendline",c0);
   c0=PROBE_T0; UpdateRangeLiquidity(atrValue);                      PROBE_END("2i.rangeLiq",c0);
   c0=PROBE_T0; UpdateIPDAReferenceLevels(analysisEnd);              PROBE_END("2j.ipda",c0);
   c0=PROBE_T0; UpdateHtfInternalStructure(analysisEnd);             PROBE_END("2k.htfInternal",c0);
   c0=PROBE_T0; UpdatePOIRegistry(analysisEnd, atrValue);            PROBE_END("2l.poi",c0);
   // یک منبع واحد برای DR/EQ: اگر لگ واقعی معتبر باشد، همان مبنا است؛ وگرنه
   // سقف/کف حفاظت‌شدهٔ H4 به‌عنوان جانشین (بدون ادعای OTE) می‌ماند (#۴۳/#۴۵).
   g_htfRangeHigh=g_leg.valid? g_leg.high : g_mtfContext[0].protectedHigh;
   g_htfRangeLow =g_leg.valid? g_leg.low  : g_mtfContext[0].protectedLow;
   c0=PROBE_T0; UpdateDOL(closePrice, atrValue);                     PROBE_END("2m.dol",c0);
   c0=PROBE_T0; UpdateSetup(closePrice, atrValue, barTime);          PROBE_END("2n.setup",c0);
   // فاز ۱۵ (#۶۶): مسلح‌کردن پیگیری ستاپ بلافاصله بعد از READY شدن آن.
   ArmSetupLifecycle(barTime);
   g_lastContextBarTime=barTime;
   c0=PROBE_T0; PersistReplayDiagnostics(barTime);   PROBE_END("2p.replayDiag",c0);
   c0=PROBE_T0; PersistReversalDiagnostics(barTime); PROBE_END("2q.reversalDiag",c0);
   c0=PROBE_T0; PersistPhase15Diagnostics(barTime);  PROBE_END("2r.phase15Diag",c0);
   // فاز ۳۲: ریسک برگشت — بعد از DOL/لگ/Exhaustion محاسبه می‌شود، چون به همهٔ آن‌ها نگاه می‌کند.
   c0=PROBE_T0; UpdateReverseRisk(closePrice, atrValue, barTime, highPrice, lowPrice); PROBE_END("2s.revRisk",c0);
}

void DetectRejectionBlock(const double &open[], const double &high[], const double &low[], const double &close[], const int shift, long sweepId, ENUM_DIRECTION sweepDir)
{
   if(shift>=ArraySize(open)) return;
   double range=high[shift]-low[shift];
   if(range<=0.0) return;
   double body=MathAbs(close[shift]-open[shift]);
   double bodyTop=MathMax(open[shift],close[shift]);
   double bodyBot=MathMin(open[shift],close[shift]);
   double upperWick=high[shift]-bodyTop;
   double lowerWick=bodyBot-low[shift];
   double dominantWick=MathMax(upperWick,lowerWick);
   if(dominantWick/range<0.60 || body/range>0.40) return;

   // Rejection Block بدون زمینهٔ نقدینگی معنا ندارد (#۴۰): در همان کندل باید یک
   // سطح ثبت‌شدهٔ نقدینگی جارو شده باشد و جهت پس‌زدگی با جهت سوئپ هم‌خوان باشد.
   if(sweepId==-1) return;
   bool upperReject = (upperWick>lowerWick);   // فتیلهٔ بالا → پس‌زدگی نزولی (BSL جارو شده)
   if(upperReject && sweepDir!=DIR_BEAR) return;
   if(!upperReject && sweepDir!=DIR_BULL) return;

   RejectionObj block;
   block.time=BarTime(shift);
   // ناحیهٔ Rejection Block همان فتیلهٔ غالب است، نه کل کندل (#۴۰).
   if(upperReject){ block.top=high[shift]; block.bottom=bodyTop; }
   else            { block.top=bodyBot;    block.bottom=low[shift]; }
   if(block.top<=block.bottom) return;
   block.direction=upperReject ? DIR_BEAR : DIR_BULL;
   block.id=StableZoneId(block.time,block.direction,3);
   block.rejectionState=REJECTION_FRESH;
   int n=ArraySize(g_rejections);
   ArrayResize(g_rejections,n+1);
   g_rejections[n]=block;
   if(!g_rebuildMode) DrawRejection(block);
   // فاز ۱۳: سقف هاردکد ۵۰ به ورودی واقعی تبدیل شد (همان مقدار پیش‌فرض).
   if(InpMaxRejections>0 && ArraySize(g_rejections)>InpMaxRejections)
   {
      int drop=ArraySize(g_rejections)-InpMaxRejections;
      int keep=ArraySize(g_rejections)-drop;
      for(int i=0;i<keep;i++) g_rejections[i]=g_rejections[i+drop];
      ArrayResize(g_rejections,InpMaxRejections);
   }
}

void UpdateRejectionLifecycle(double curHigh, double curLow, double curClose, datetime curBarTime)
{
   for(int i=0;i<ArraySize(g_rejections);i++)
   {
      if(g_rejections[i].rejectionState==REJECTION_INVALID) continue;
      // کندل سازندهٔ ناحیه همان کندل را لمس کرده؛ این لمس معتبر نیست (#۴۰).
      if(g_rejections[i].time >= curBarTime) continue;
      if(curLow<=g_rejections[i].top && curHigh>=g_rejections[i].bottom)
         g_rejections[i].rejectionState=REJECTION_TOUCHED;
      if((g_rejections[i].direction==DIR_BULL && curClose<g_rejections[i].bottom) ||
         (g_rejections[i].direction==DIR_BEAR && curClose>g_rejections[i].top))
         g_rejections[i].rejectionState=REJECTION_INVALID;
   }
}

// سطحی که قیمت با **بسته‌شدن** از آن عبور کرده دیگر نقدینگی دست‌نخورده نیست؛
// نقدینگی "پذیرفته شد" (accepted) و از حالت انتظار خارج می‌شود (#۲۲).
// این سطح حذف نمی‌شود: فقط از FRESH به INVALID می‌رود تا تاریخچه روی چارت بماند.
void UpdateLiquidityLifecycle(double curClose)
{
   for(int i=0;i<ArraySize(g_liquidity);i++)
   {
      if(g_liquidity[i].state!=LSTATE_FRESH) continue;
      bool highSide=IsHighSideLiquidity(g_liquidity[i].type);
      if(highSide  && curClose > g_liquidity[i].price) g_liquidity[i].state=LSTATE_INVALID;
      if(!highSide && curClose < g_liquidity[i].price) g_liquidity[i].state=LSTATE_INVALID;
   }
}

