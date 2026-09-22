//====================================================================
// PHASE 12 ENGINES — تکمیل پوشش SMC / MMM
// هر مفهوم این بخش با یک قانون عددی، زمان، تایم‌فریم مالک و مسیر Explain
// جداگانه کار می‌کند. هیچ بلاکی که در فاز ۱۱ اثبات شده دست نخورده است.
//====================================================================
string g_trendlineReject = "";
string g_rangeReject     = "";
bool   g_rangeActive     = false;
bool   g_rangeOk         = false;
bool   g_trendlineBuilt  = false;
bool   g_ipdaOk          = false;
string g_ipdaNote        = "";
double g_rangeHigh       = 0.0;
double g_rangeLow        = 0.0;
double g_rangeHeight     = 0.0;
int    g_rangeHighTouches= 0;
int    g_rangeLowTouches = 0;
string g_modelReason     = "";

//--------------------------------------------------------------------
// #۱۹ Trendline Liquidity — نقدینگی مورب
// خط از دو سویینگ تأییدشده ساخته می‌شود و تعداد سویینگ‌های نشسته روی خط
// گزارش می‌شود. ابطال: بسته‌شدن قیمت با فاصلهٔ مشخص فراتر از خط.
//--------------------------------------------------------------------
double TrendlinePriceAt(const TrendlineLiqObj &tl, datetime t)
{
   return tl.p2 + tl.slope * (double)((long)t-(long)tl.t2);
}

void UpdateTrendlineLifecycle(double curHigh, double curLow, double curClose, datetime curBarTime, double atrValue)
{
   if(!InpEnablePhase12 || !InpDetectTrendlineLiq) return;
   double buf=(atrValue>0.0)? atrValue*InpTrendlineBreakATR : 0.0;
   for(int i=0;i<ArraySize(g_trendlines);i++)
   {
      if(g_trendlines[i].invalidated) continue;
      double lvl=TrendlinePriceAt(g_trendlines[i], curBarTime);
      if(lvl<=0.0) continue;
      // عبور **بسته‌شده** از خط (نه فتیله) خط را باطل میکند
      bool broke = g_trendlines[i].isHigh ? (curClose > lvl+buf) : (curClose < lvl-buf);
      if(broke)
      {
         g_trendlines[i].invalidated=true;
         g_trendlines[i].invalidTime=curBarTime;
         g_trendlines[i].invalidPrice=curClose;
      }
   }
}

//--------------------------------------------------------------------
// فاز ۳۰ (#۷۶): Sweep نقدینگی مورب (خط روند).
// منبع (LuxAlgo — Trendline Liquidity، مرحلهٔ ۴): «a sharp poke through the line
// that stalls quickly and reclaims it suggests a sweep of trendline liquidity
// rather than a genuine trend change» و (LuxAlgo — Liquidity Sweep، مرحلهٔ ۳):
// «a trade through the level followed by a close back inside the prior range ...
// A close that holds beyond it, with continuation, is a breakout, not a sweep».
// پس قاعده دقیقاً همان قاعدهٔ Sweep سطوح افقی است: فتیله فراتر از خط +
// بسته‌شدن برگشتی به همان سمت. سطح هم مثل بقیهٔ سطوح در Registry ثبت و همان
// لحظه «مصرف‌شده» علامت می‌خورد تا زنجیرهٔ رویداد (ساختار/Displacement) به آن
// وصل شود — قبلاً خط روند فقط «باطل» می‌شد و هیچ Sweep ای برایش ثبت نمی‌شد.
//--------------------------------------------------------------------
long DetectTrendlineSweep(double barHigh, double barLow, double barClose, datetime t, ENUM_DIRECTION &outDir)
{
   outDir=DIR_NONE;
   if(!InpEnablePhase12 || !InpDetectTrendlineLiq) return -1;
   long mainId=-1;
   for(int i=0;i<ArraySize(g_trendlines);i++)
   {
      if(g_trendlines[i].invalidated || g_trendlines[i].swept) continue;
      double lvl=TrendlinePriceAt(g_trendlines[i], t);
      if(lvl<=0.0) continue;
      bool sweptHere = g_trendlines[i].isHigh ? (barHigh > lvl && barClose < lvl)
                                              : (barLow  < lvl && barClose > lvl);
      if(!sweptHere) continue;
      g_trendlines[i].swept=true;
      g_trendlines[i].sweptTime=t;
      g_trendlines[i].sweptPrice=lvl;
      long id=AddLiquidity(g_trendlines[i].isHigh? LIQ_TRENDLINE_H : LIQ_TRENDLINE_L,
                           SCOPE_INTERNAL, lvl, t, false);
      // سطح در همان کندل جارو شد، پس نباید «تازه» بماند؛ وگرنه کندل بعدی دوباره
      // همان سطح را جارو می‌کند و زنجیره دو بار ساخته می‌شود (هم‌قاعده با DetectSweep).
      for(int k=0;k<ArraySize(g_liquidity);k++)
         if(g_liquidity[k].id==id && g_liquidity[k].state==LSTATE_FRESH)
         {
            g_liquidity[k].state=LSTATE_SWEPT;
            g_liquidity[k].sweptTime=t;
         }
      if(mainId==-1)
      {
         mainId=id;
         outDir = g_trendlines[i].isHigh? DIR_BEAR : DIR_BULL;
      }
   }
   return mainId;
}

void BuildTrendlines(double atrValue)
{
   g_trendlineBuilt=false;
   g_trendlineReject="";
   if(!InpEnablePhase12 || !InpDetectTrendlineLiq) return;
   int n=ArraySize(g_swingsLTF);
   if(n<2){ g_trendlineReject="سوئینگ تأییدشدهٔ کافی برای ساخت خط نیست"; return; }
   double tol=(atrValue>0.0)? atrValue*InpTrendlineTolATR : PointsToPrice(InpEQ_Tolerance_Points);

   int built=0;
   for(int side=0;side<2;side++)
   {
      bool wantHigh=(side==0);
      // دو سویینگ آخر این سمت به ترتیب زمان
      // سوئینگ‌ها به ترتیب زمان (قدیم به جدید) در آرایه‌اند، پس پیمایش از
      // انتها یعنی از جدیدترین: اولین تطابق = آنکر جدید، دومین = آنکر قدیم.
      int idxB=-1, idxA=-1;
      for(int i=n-1;i>=0;i--)
      {
         if(g_swingsLTF[i].isHigh!=wantHigh) continue;
         if(idxB==-1){ idxB=i; continue; }
         idxA=i;
         break;
      }
      if(idxB==-1 || idxA==-1) continue;
      SwingPoint a=g_swingsLTF[idxA];
      SwingPoint b=g_swingsLTF[idxB];
      if(b.time<=a.time) continue;
      double dt=(double)((long)b.time-(long)a.time);
      if(dt<=0.0) continue;

      // فاز ۳۰ (#۷۶): سمت نقدینگی خط از **شیب** آن می‌آید، نه از این‌که خط روی
      // سقف‌ها یا کف‌ها وصل شده است.
      // منبع (LuxAlgo — Trendline Liquidity): «below a rising support line sit
      // stops from trendline buyers ... forming a diagonal band of sell-side
      // interest» و «the mirror image above a falling one». یعنی:
      //   • خط روی سقف‌های نزولی (lower highs) → نقدینگی Buy-Side بالای خط
      //   • خط روی کف‌های صعودی (higher lows)  → نقدینگی Sell-Side زیر خط
      // خطی که هیچ‌کدام نیست (سقف صعودی یا کف نزولی) استخر نقدینگی مورب
      // نمی‌سازد؛ قبلاً بدون این شرط ساخته می‌شد و خطی می‌کشید که قیمت در
      // همان لحظه از آن طرف رفته بود.
      if(wantHigh ? !(b.price < a.price) : !(b.price > a.price))
      {
         g_trendlineReject="شیب دو آنکر با استخر نقدینگی مورب نمی‌خواند (سقف‌ها باید نزولی و کف‌ها صعودی باشند)";
         continue;
      }

      TrendlineLiqObj tl;
      tl.id=(long)a.time*2L+(wantHigh?1L:0L);
      tl.isHigh=wantHigh; tl.t1=a.time; tl.t2=b.time; tl.p1=a.price; tl.p2=b.price;
      tl.slope=(b.price-a.price)/dt;
      tl.tf=PERIOD_CURRENT;
      tl.createdTime=a.time;
      tl.invalidated=false; tl.invalidTime=0; tl.invalidPrice=0.0;
      tl.swept=false; tl.sweptTime=0; tl.sweptPrice=0.0;

      // شمارش سویینگ‌هایی که روی خط نشسته‌اند (فقط ۴۰ سویینگ آخر برای هزینهٔ کم)
      int touches=0;
      int scanFrom=MathMax(0,n-40);
      for(int i=scanFrom;i<n;i++)
      {
         if(g_swingsLTF[i].isHigh!=wantHigh) continue;
         double lvl=TrendlinePriceAt(tl, g_swingsLTF[i].time);
         if(lvl>0.0 && MathAbs(g_swingsLTF[i].price-lvl)<=tol) touches++;
      }
      tl.touches=touches;

      // فاز ۳۰ (#۷۶) — منبع: همان صفحه، مرحلهٔ ۱ («a clean line with three or
      // more respected touches») و مرحلهٔ ۳ («each successive touch adds
      // participants»). خط دو-لمسی ضعیف‌ترین حالت است؛ پیش‌فرض ۳ است و از پنل
      // ورودی‌ها قابل کم‌کردن (وگرنه خطوط بی‌ارزش چارت را شلوغ می‌کردند).
      if(tl.touches < MathMax(2,InpTrendlineMinTouches))
      {
         g_trendlineReject=StringFormat("تعداد سویینگ روی خط (%d) کمتر از حد لازم (%d) است",
                                        tl.touches, MathMax(2,InpTrendlineMinTouches));
         continue;
      }

      bool exists=false;
      for(int i=0;i<ArraySize(g_trendlines);i++)
         if(g_trendlines[i].id==tl.id && !g_trendlines[i].invalidated){ exists=true; break; }
      if(exists) continue;
      int m=ArraySize(g_trendlines);
      ArrayResize(g_trendlines,m+1);
      g_trendlines[m]=tl;
      built++;
   }

   int cap=MathMax(1,InpMaxTrendlines);
   if(ArraySize(g_trendlines)>cap)
   {
      for(int i=0;i<ArraySize(g_trendlines)-1;i++) g_trendlines[i]=g_trendlines[i+1];
      ArrayResize(g_trendlines,cap);
   }
   g_trendlineBuilt=(built>0);
   if(!g_trendlineBuilt && g_trendlineReject=="")
      g_trendlineReject="برای هر سمت، دو سویینگ تأییدشدهٔ هم‌جهت با فاصلهٔ زمانی کافی پیدا نشد";
}

//--------------------------------------------------------------------
// #۲۰ Range Liquidity — نقدینگی مرزهای رنج
// قانون: در پنجرهٔ سویینگ‌های اخیر، حداقل InpRangeMinTouches سویینگ روی سقف و
// به همان تعداد روی کف، و ارتفاع رنج از حد مجاز کمتر باشد.
//--------------------------------------------------------------------
void UpdateRangeLiquidity(double atrValue)
{
   g_rangeActive=false;
   g_rangeOk=false;
   g_rangeReject="";
   if(!InpEnablePhase12 || !InpDetectRangeLiquidity) return;
   if(atrValue<=0.0){ g_rangeReject="ATR قابل محاسبه نیست"; return; }
   int n=ArraySize(g_swingsLTF);
   if(n<InpRangeMinTouches*2){ g_rangeReject=StringFormat("سوئینگ کافی نیست (%d از %d لازم)", n, InpRangeMinTouches*2); return; }
   int look=MathMin(n,MathMax(4,InpRangeLookbackSwings));
   int start=n-look;

   double H=-1e18, L=1e18; datetime tH=0, tL=0;
   for(int i=start;i<n;i++)
   {
      if(g_swingsLTF[i].isHigh && g_swingsLTF[i].price>H){ H=g_swingsLTF[i].price; tH=g_swingsLTF[i].time; }
      if(!g_swingsLTF[i].isHigh && g_swingsLTF[i].price<L){ L=g_swingsLTF[i].price; tL=g_swingsLTF[i].time; }
   }
   if(H<=L){ g_rangeReject="سقف و کف معتبر پیدا نشد"; return; }
   double height=H-L;
   double maxH=atrValue*InpRangeMaxATR;
   if(height>maxH)
   {
      g_rangeReject=StringFormat("RANGE REJECT | ارتفاع %.2f از حد مجاز %.2f (%.1f برابر میانگین دامنه) بیشتر است — روند است، نه رنج", height, maxH, InpRangeMaxATR);
      return;
   }
   double tol=MathMax(PointsToPrice(InpEQ_Tolerance_Points), atrValue*InpEQ_ToleranceATR);
   int hiT=0, loT=0;
   for(int i=start;i<n;i++)
   {
      if(g_swingsLTF[i].isHigh && MathAbs(g_swingsLTF[i].price-H)<=tol) hiT++;
      if(!g_swingsLTF[i].isHigh && MathAbs(g_swingsLTF[i].price-L)<=tol) loT++;
   }
   if(hiT<InpRangeMinTouches || loT<InpRangeMinTouches)
   {
      g_rangeReject=StringFormat("برخورد کافی روی مرزها نیست (سقف %d، کف %d از %d)", hiT, loT, InpRangeMinTouches);
      return;
   }
   g_rangeActive=true;
   g_rangeOk=true;
   g_rangeHigh=H; g_rangeLow=L; g_rangeHeight=height; g_rangeHighTouches=hiT; g_rangeLowTouches=loT;
   AddLiquidity(LIQ_RANGE_H, SCOPE_INTERNAL, H, tH, false);
   AddLiquidity(LIQ_RANGE_L, SCOPE_INTERNAL, L, tL, false);
}

//--------------------------------------------------------------------
// #۶۵ IPDA Reference Levels — Old High/Low افق‌های ۲۰/۴۰/۶۰ روزه
// فقط وقتی دادهٔ کافی باشد ثبت می‌شود؛ هیچ مقدار تقریبی نوشته نمی‌شود.
//--------------------------------------------------------------------
void UpdateIPDAReferenceLevels(datetime barTime)
{
   g_ipdaOk=false;
   g_ipdaNote="";
   if(!InpEnablePhase12 || !InpDetectIPDA) return;
   int horizons[3]={20,40,60};
   int registered=0;
   string missing="";
   for(int h=0;h<3;h++)
   {
      int days=horizons[h];
      double hiArr[], loArr[];
      ArraySetAsSeries(hiArr,true);
      ArraySetAsSeries(loArr,true);
      int ch=CopyHigh(_Symbol,PERIOD_D1,1,days,hiArr);
      int cl=CopyLow(_Symbol,PERIOD_D1,1,days,loArr);
      if(ch<days || cl<days)
      {
         missing+=StringFormat("%dd ", days);
         continue;
      }
      double hh=hiArr[ArrayMaximum(hiArr)];
      double ll=loArr[ArrayMinimum(loArr)];
      datetime anchor=iTime(_Symbol,PERIOD_D1,days);
      if(anchor<=0) anchor=barTime;
      ENUM_LIQ_TYPE tH=(days==20)?LIQ_IPDA20_H:((days==40)?LIQ_IPDA40_H:LIQ_IPDA60_H);
      ENUM_LIQ_TYPE tL=(days==20)?LIQ_IPDA20_L:((days==40)?LIQ_IPDA40_L:LIQ_IPDA60_L);
      if(hh>0.0) AddLiquidity(tH, SCOPE_EXTERNAL, hh, anchor, true);
      if(ll>0.0) AddLiquidity(tL, SCOPE_EXTERNAL, ll, anchor, true);
      registered++;
   }
   g_ipdaOk=(registered>0);
   g_ipdaNote=StringFormat("%d از ۳ افق ثبت شد", registered);
   if(StringLen(missing)>0) g_ipdaNote+=" | دادهٔ کافی برای: "+missing;
}

//--------------------------------------------------------------------
// #۳۵ OB Extreme و #۳۶ Core/Standalone
// Core = ناحیه‌ای که به یک شکست ساختار وصل است. Standalone = ناحیه‌ای با
// Displacement ولی بدون مشارکت در شکست ساختار. Extreme = ناحیه‌ای که روی
// اکسترمم لگ معامله‌گری نشسته است (سقف لگ ← عرضه، کف لگ ← تقاضا).
//--------------------------------------------------------------------
void MarkExtremeOrderBlocks(double atrValue)
{
   for(int i=0;i<ArraySize(g_obs);i++) g_obs[i].isExtreme=false;
   if(!g_leg.valid) return;
   double tol=(atrValue>0.0)? atrValue*InpOB_ExtremeATR : 0.0;
   long upId=-1, dnId=-1; double upDist=1e18, dnDist=1e18;
   for(int i=0;i<ArraySize(g_obs);i++)
   {
      if(g_obs[i].state==OB_INVALID) continue;
      if(g_obs[i].direction==DIR_BEAR)              // ناحیهٔ عرضه در سقف لگ
      {
         double d=MathAbs(g_obs[i].bottom-g_leg.high);
         if(g_obs[i].bottom>=g_leg.high-tol && d<upDist){ upDist=d; upId=g_obs[i].id; }
      }
      else if(g_obs[i].direction==DIR_BULL)         // ناحیهٔ تقاضا در کف لگ
      {
         double d=MathAbs(g_obs[i].top-g_leg.low);
         if(g_obs[i].top<=g_leg.low+tol && d<dnDist){ dnDist=d; dnId=g_obs[i].id; }
      }
   }
   for(int i=0;i<ArraySize(g_obs);i++)
   {
      if(g_obs[i].id!=upId && g_obs[i].id!=dnId) continue;
      g_obs[i].isExtreme=true;
      if(g_obs[i].kind!=OBK_MITIGATION_BLOCK) g_obs[i].kind=OBK_EXTREME;
      // فاز ۳۶: ناحیهٔ اکسترمم لگ = External OB (منبع: LuxAlgo — IRL/ERL:
      // مبدأ اکسترمم رنج معامله‌گری، External است؛ «inside the leg» یعنی Internal)
      g_obs[i].scope=SCOPE_EXTERNAL;
   }
}

//--------------------------------------------------------------------
// #۳۱ FVG Micro — گپ سه‌کندلی روی تایم‌فریم پایین‌تر، داخل محدودهٔ همان کندل
// Displacement. فقط از Displacement **زنجیرشده** ساخته می‌شود تا رجیستری با
// ناحیه‌های بی‌ارزش پر نشود.
//--------------------------------------------------------------------
void DetectMicroFVG(datetime dispBarTime, double dispHigh, double dispLow, long dispId)
{
   if(!InpEnablePhase12 || !InpDetectMicroFVG) return;
   if(dispBarTime<=0 || dispId==-1) return;
   int chartSec=PeriodSeconds(PERIOD_CURRENT);
   if(chartSec<=0) chartSec=60;
   int microSec=PeriodSeconds(InpMicroTF);
   if(microSec<=0 || microSec>=chartSec) return;   // فقط روی تایم‌فریم واقعاً پایین‌تر
   datetime windowEnd=(datetime)((long)dispBarTime+(long)chartSec);

   MqlRates mr[];
   int copied=CopyRates(_Symbol, InpMicroTF, windowEnd, MathMax(6,InpMicroBarsPerDisp), mr);
   if(copied<6) return;
   ArraySetAsSeries(mr,true);
   int made=0;
   for(int k=0;k+2<copied && made<4;k++)
   {
      if(mr[k].time>=windowEnd) continue;      // باید داخل همان کندل باشد
      if(mr[k+2].time<dispBarTime) continue;
      // صعودی: low کندل سوم بالای high کندل اول
      if(mr[k].low>mr[k+2].high)
      {
         double top=mr[k].low, bot=mr[k+2].high;
         if(top<=dispHigh && bot>=dispLow)
         {
            AppendFVG(StableZoneId(mr[k].time,DIR_BULL,4), mr[k].time, DIR_BULL, top, bot,
                      dispId, FVGK_MICRO, InpMicroTF, false);
            made++;
         }
      }
      // نزولی: high کندل سوم زیر low کندل اول
      if(mr[k].high<mr[k+2].low)
      {
         double top=mr[k+2].low, bot=mr[k].high;
         if(top<=dispHigh && bot>=dispLow)
         {
            AppendFVG(StableZoneId(mr[k].time,DIR_BEAR,4), mr[k].time, DIR_BEAR, top, bot,
                      dispId, FVGK_MICRO, InpMicroTF, false);
            made++;
         }
      }
   }
}

//--------------------------------------------------------------------
// #۳ ساختار داخلی **همان تایم‌فریم مالک**
// قبلاً ردیف «Internal» داشبورد همان ترند تایم‌فریم چارت بود، نه ساختار
// داخلی تایم‌فریم مالک. این تابع پیوت‌های تأییدشدهٔ همان تایم‌فریم مالک را
// در پنجرهٔ اخیر می‌گیرد و HH/HL یا LH/LL را گزارش می‌کند.
//--------------------------------------------------------------------
void UpdateHtfInternalStructure(datetime barTime)
{
   g_htfInternalDir=DIR_NONE;
   g_htfInternalReason="";
   if(!InpEnablePhase12) return;
   MqlRates rates[];
   int copied=CopyRatesAsOf(_Symbol, InpHTF, barTime, 120, rates);
   if(copied<InpSwingLeft+InpSwingRight+12)
   {
      g_htfInternalReason="دادهٔ بستهٔ کافی روی تایم‌فریم مالک نیست";
      return;
   }
   SwingPoint highs[], lows[];
   int total=ArraySize(rates);
   int window=MathMin(total-InpSwingRight-1, MathMax(InpSwingLeft+InpSwingRight+4,InpInternalWindowBars));
   for(int shift=window; shift>=InpSwingRight; shift--)
   {
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
   g_htfInternalDir=DirectionFromConfirmedSwings(highs,lows);
   if(g_htfInternalDir==DIR_NONE)
      g_htfInternalReason=StringFormat("در پنجرهٔ %d کندلی، هیچ سقف و کف بالاتر یا پایین‌تر تأییدشده‌ای ثبت نشد", window);
}

//--------------------------------------------------------------------
// #۹ سن و مرحلهٔ روند
// سن = تعداد کندل HTF از رویدادی که Bias فعلی را ساخته است.
// مرحله بر اساس همان سن + وضعیت Exhaustion + تأیید برگشت تعیین میشود.
//--------------------------------------------------------------------
string TrendPhaseToStr(ENUM_TREND_PHASE p)
{
   switch(p)
   {
      case PHASE_INITIATION:   return "INITIATION";
      case PHASE_EXPANSION:    return "EXPANSION";
      case PHASE_DISTRIBUTION: return "DISTRIBUTION";
      case PHASE_REVERSAL:     return "REVERSAL";
      default:                 return "UNKNOWN";
   }
}

void UpdateTrendPhase(datetime asOf)
{
   g_trend.ageBars=0; g_trend.sinceTime=0; g_trend.sinceEventId=-1;
   g_trend.phase=PHASE_UNKNOWN; g_trend.phaseReason="";
   if(g_htfBias==DIR_NONE)
   {
      g_trend.phaseReason="بایاس مالک تایم‌فریم بالاتر هنوز تأیید نشده است";
      return;
   }
   // آخرین رویداد HTF هم‌جهت با Bias = رویدادی که این Bias را ساخته است
   for(int i=ArraySize(g_events)-1;i>=0;i--)
   {
      if(!g_events[i].isHTF) continue;
      if(g_events[i].direction!=g_htfBias) continue;
      g_trend.sinceTime=g_events[i].time;
      g_trend.sinceEventId=g_events[i].id;
      break;
   }
   if(g_trend.sinceTime<=0)
   {
      g_trend.phaseReason="رویداد تایم‌فریم بالاتر که این بایاس را ساخته باشد در رجیستری پیدا نشد";
      return;
   }
   int htfSec=PeriodSeconds(InpHTF);
   if(htfSec<=0) htfSec=14400;
   g_trend.ageBars=(int)(((long)asOf-(long)g_trend.sinceTime)/(long)htfSec);
   if(g_trend.ageBars<0) g_trend.ageBars=0;

   if(g_reversal.confirmed && g_reversal.dir==g_htfBias)
   {
      g_trend.phase=PHASE_REVERSAL;
      g_trend.phaseReason="برگشت تأییدشدهٔ سطح محافظت‌شدهٔ خارجی در جهت بایاس فعلی";
   }
   else if(g_trend.ageBars<=InpTrendYoungBars)
   {
      g_trend.phase=PHASE_INITIATION;
      g_trend.phaseReason=StringFormat("سن %d کندل تایم‌فریم بالاتر کمتر یا مساوی %d است", g_trend.ageBars, InpTrendYoungBars);
   }
   else if(g_exhaustion.state==EXH_WATCH || g_exhaustion.state==EXH_MICRO_PULLBACK ||
           g_exhaustion.state==EXH_RANGE_TRANSITION)
   {
      g_trend.phase=PHASE_DISTRIBUTION;
      g_trend.phaseReason="فرسودگی روند ضعف را گزارش می‌کند | "+ExhaustionStateToStr(g_exhaustion.state);
   }
   else
   {
      g_trend.phase=PHASE_EXPANSION;
      g_trend.phaseReason=StringFormat("سن %d کندل تایم‌فریم بالاتر و هیچ هشدار ضعفی ثبت نشده است", g_trend.ageBars);
   }
}

//--------------------------------------------------------------------
// #۴۷ رجیستری POI یکپارچه
// امتیاز عددی و شفاف است؛ کهنگی از امتیاز کم می‌کند. POI هیچ گاه جای
// دروازه‌های READY را نمی‌گیرد؛ فقط انتخاب ناحیه و توضیح را یکسان می‌کند.
//--------------------------------------------------------------------
string PoiKindToStr(ENUM_POI_KIND k)
{
   switch(k)
   {
      case POIK_FVG:        return "FVG";
      case POIK_OB:         return "Order Block";
      case POIK_BREAKER:    return "Breaker Block";
      case POIK_MITIGATION: return "Mitigation Block";
      case POIK_REJECTION:  return "Rejection Block";
      case POIK_TRENDLINE:  return "Trendline Liquidity";
      case POIK_RANGE:      return "Range Liquidity";
      default:              return "—";
   }
}

void AddPOI(long id, ENUM_POI_KIND kind, ENUM_DIRECTION dir, double top, double bottom,
            datetime t, ENUM_TIMEFRAMES tf, datetime asOf, int chartSec, double atrValue, bool extreme)
{
   if(top<=0.0 || bottom<=0.0) return;
   // ناحیهٔ بی‌اندازه پهن (خطای ورودی) به رجیستری راه پیدا نمی‌کند
   if(atrValue>0.0 && MathAbs(top-bottom) > atrValue*8.0) return;
   POIObj p;
   p.id=id; p.kind=kind; p.direction=dir;
   p.top=MathMax(top,bottom); p.bottom=MathMin(top,bottom);
   p.time=t; p.tf=tf; p.valid=true; p.invalidReason=""; p.sourceId=id;
   int ageBars=(t>0 && asOf>t)? (int)(((long)asOf-(long)t)/(long)chartSec) : 0;
   int decay=(InpPOI_AgeDecayBars>0)? (ageBars/InpPOI_AgeDecayBars) : 0;
   if(decay>10) decay=10;
   int s=20;
   if(kind==POIK_BREAKER)    s+=12;
   if(kind==POIK_FVG)        s+=8;
   if(kind==POIK_OB)         s+=6;
   if(kind==POIK_TRENDLINE)  s+=5;
   if(kind==POIK_RANGE)      s+=5;
   if(kind==POIK_MITIGATION) s+=4;
   if(kind==POIK_REJECTION)  s+=3;
   if(dir==g_htfBias)        s+=10;
   if(extreme)               s+=6;
   s-=decay;
   p.score=s;
   int n=ArraySize(g_poi);
   ArrayResize(g_poi,n+1);
   g_poi[n]=p;
}

void UpdatePOIRegistry(datetime asOf, double atrValue)
{
   if(!InpEnablePhase12 || !InpBuildPOIRegistry) return;
   ArrayResize(g_poi,0);
   int chartSec=PeriodSeconds(PERIOD_CURRENT);
   if(chartSec<=0) chartSec=60;

   for(int i=ArraySize(g_fvgs)-1;i>=0;i--)
   {
      if(!g_fvgs[i].causal || g_fvgs[i].invalidated) continue;
      // فاز ۴۳: مقصد (POI) یک سطح *قابل استفاده* است، پس نقش فعلی نوشته می‌شود.
      // گپ وارونه یک ورودی معتبر در جهت مخالف تولدش است.
      AddPOI(g_fvgs[i].id, POIK_FVG, FVGActiveDir(g_fvgs[i]), g_fvgs[i].top, g_fvgs[i].bottom,
             g_fvgs[i].time, g_fvgs[i].tf, asOf, chartSec, atrValue, false);
   }
   for(int i=ArraySize(g_obs)-1;i>=0;i--)
   {
      ENUM_POI_KIND k=POIK_NONE;
      if(g_obs[i].state==OB_BREAKER)         k=POIK_BREAKER;
      else if(g_obs[i].state==OB_MITIGATION) k=POIK_MITIGATION;
      else if(g_obs[i].state==OB_VALID)      k=POIK_OB;
      if(k==POIK_NONE) continue;
      // فاز ۴۳: همان قاعده برای OB. Breaker و Mitigation Block ناحیه‌هایی هستند
      // که پولاریتی‌شان برگشته (قطبیت عوض شده)، پس نقش فعلی‌شان مخالف جهت تولد
      // است؛ قبلاً رجیستری POI جهت تولد را می‌نوشت و یک Breaker صعودی‌زاد در
      // خروجی «صعودی» گزارش می‌شد، در حالی که رنگ و تعریفش نزولی بود.
      AddPOI(g_obs[i].id, k, OBActiveDir(g_obs[i]), g_obs[i].top, g_obs[i].bottom,
             g_obs[i].time, PERIOD_CURRENT, asOf, chartSec, atrValue, g_obs[i].isExtreme);
      // فاز ۳۶ — Nested / Multi-timeframe Mitigation (منبع: SMC — «Nested /
      // Multi-timeframe Mitigation»): ناحیهٔ HTF که داخل آن POI هم‌جهتِ LTF
      // هست، قوی‌تر است؛ امتیاز POI ناحیهٔ میزبان به‌اندازهٔ یک درجه تقویت
      // می‌شود و در پنل صریح گفته می‌شود. فقط برای نواحی سازگار با Bias مالک.
      // فاز ۴۳: هم‌جهتی با بایاس و هم‌جهتی میزبان/مهمان هر دو با **نقش فعلی**
      // سنجیده می‌شوند (یک ناحیهٔ وارونه یا Breaker دیگر ناحیهٔ هم‌جهت نیست).
      if(OBActiveDir(g_obs[i])==g_htfBias && g_obs[i].tf!=PERIOD_CURRENT)
      {
         for(int j=0;j<ArraySize(g_fvgs);j++)
         {
            if(!g_fvgs[j].causal || g_fvgs[j].invalidated) continue;
            if(FVGActiveDir(g_fvgs[j])!=OBActiveDir(g_obs[i])) continue;
            bool nested=(g_fvgs[j].top<=g_obs[i].top && g_fvgs[j].bottom>=g_obs[i].bottom);
            if(!nested) continue;
            for(int q=0;q<ArraySize(g_poi);q++)
               if(g_poi[q].sourceId==g_obs[i].id){ g_poi[q].score+=4; g_poi[q].valid=true; break; }
            break;   // یک شاهد کافی است؛ امتیاز دو بار داده نشود
         }
      }
   }
   for(int i=ArraySize(g_rejections)-1;i>=0;i--)
   {
      if(g_rejections[i].rejectionState!=REJECTION_FRESH) continue;
      AddPOI(g_rejections[i].id, POIK_REJECTION, g_rejections[i].direction,
             g_rejections[i].top, g_rejections[i].bottom, g_rejections[i].time,
             PERIOD_CURRENT, asOf, chartSec, atrValue, false);
   }
   for(int i=ArraySize(g_trendlines)-1;i>=0;i--)
   {
      if(g_trendlines[i].invalidated) continue;
      double lvl=TrendlinePriceAt(g_trendlines[i], asOf);
      if(lvl<=0.0) continue;
      double band=(atrValue>0.0)? atrValue*0.10 : 0.0;
      AddPOI(g_trendlines[i].id, POIK_TRENDLINE,
             g_trendlines[i].isHigh?DIR_BEAR:DIR_BULL,
             lvl+band, lvl-band, g_trendlines[i].t2, g_trendlines[i].tf,
             asOf, chartSec, atrValue, false);
   }
   for(int i=ArraySize(g_liquidity)-1;i>=0;i--)
   {
      if(g_liquidity[i].state!=LSTATE_FRESH) continue;
      if(g_liquidity[i].type!=LIQ_RANGE_H && g_liquidity[i].type!=LIQ_RANGE_L) continue;
      // #۲۰ مرز رنج یک «سطح» است نه ناحیهٔ بی‌بُعد. پیش از این top=bottom بود و
      // شرط رندر (top>bottom) چنین POI‌ی را هرگز رسم نمی‌کرد، درحالی‌که
      // FindBestPOI همان را به‌عنوان بهترین ناحیه برمی‌گرداند.
      double rband=(atrValue>0.0)? atrValue*0.10 : 0.0;
      AddPOI(g_liquidity[i].id, POIK_RANGE,
             IsHighSideLiquidity(g_liquidity[i].type)?DIR_BEAR:DIR_BULL,
             g_liquidity[i].price+rband, g_liquidity[i].price-rband,
             g_liquidity[i].time, PERIOD_CURRENT, asOf, chartSec, atrValue, false);
   }

   // مرتب‌سازی نزولی بر اساس امتیاز (insertion sort — رجیستری کوچک است)
   int n=ArraySize(g_poi);
   for(int i=1;i<n;i++)
   {
      POIObj key=g_poi[i];
      int j=i-1;
      while(j>=0 && g_poi[j].score<key.score){ g_poi[j+1]=g_poi[j]; j--; }
      g_poi[j+1]=key;
   }
   int cap=MathMax(1,InpMaxPOI);
   if(n>cap) ArrayResize(g_poi,cap);
}

bool FindBestPOI(ENUM_DIRECTION dir, POIObj &out)
{
   for(int i=0;i<ArraySize(g_poi);i++)
   {
      if(!g_poi[i].valid) continue;
      if(dir!=DIR_NONE && g_poi[i].direction!=dir) continue;
      out=g_poi[i];
      return true;
   }
   return false;
}

//--------------------------------------------------------------------
// #۶۷ انتخاب مدل ورود
// هر مدل شرط عددی خودش را دارد؛ مدل انتخابی همان می‌شود که واقعاً شرط‌هایش
// برآورده شده است. ورودی می‌تواند یک مدل را اجبار کند.
//--------------------------------------------------------------------
string EntryModelToStr(ENUM_ENTRY_MODEL m)
{
   switch(m)
   {
      case MODEL_ICT2022:     return "ICT 2022 (Sweep -> MSS -> FVG)";
      case MODEL_BOS_FVG_OB:  return "BOS -> FVG -> OB";
      case MODEL_SWEEP_ENTRY: return "Sweep Entry";
      case MODEL_OTE_ONLY:    return "OTE only";
      default:                return "NONE";
   }
}

ENUM_ENTRY_MODEL SelectEntryModel(bool chainIsMss, bool hasSweep, bool hasChainedDisp,
                                 long fvgId, long obId, bool zoneInOte, bool legAligned)
{
   g_modelReason="";
   if(!InpEnablePhase12)
   {
      g_modelReason="لایهٔ فاز ۱۲ خاموش است";
      return MODEL_NONE;
   }
   bool m2022 = chainIsMss && hasSweep && hasChainedDisp && fvgId!=-1;
   bool mBfo  = hasChainedDisp && fvgId!=-1 && obId!=-1;
   bool mSweep= hasSweep && zoneInOte;
   bool mOte  = legAligned && zoneInOte;

   if(InpPreferredEntryModel>0)
   {
      ENUM_ENTRY_MODEL forced=MODEL_NONE;
      if(InpPreferredEntryModel==1) forced=MODEL_ICT2022;
      else if(InpPreferredEntryModel==2) forced=MODEL_BOS_FVG_OB;
      else if(InpPreferredEntryModel==3) forced=MODEL_SWEEP_ENTRY;
      else if(InpPreferredEntryModel==4) forced=MODEL_OTE_ONLY;
      bool ok=false;
      if(forced==MODEL_ICT2022)     ok=m2022;
      else if(forced==MODEL_BOS_FVG_OB) ok=mBfo;
      else if(forced==MODEL_SWEEP_ENTRY) ok=mSweep;
      else if(forced==MODEL_OTE_ONLY) ok=mOte;
      g_modelReason=ok
         ? ("مدل اجباری از ورودی برآورده شد: "+EntryModelToStr(forced))
         : ("مدل اجباری از ورودی برآورده نشد: "+EntryModelToStr(forced));
      return ok? forced : MODEL_NONE;
   }
   // Phase 42: the model name is the label; the reason after the separator is a
   // pure Persian sentence, so no acronym rides inside a Persian clause.
   if(m2022){ g_modelReason="مدل ۲۰۲۲ | چرخهٔ تغییر کاراکتر با جاروی نقدینگی و کندل جابه‌جایی زنجیرشده و گپ هم‌جهت موجود است"; return MODEL_ICT2022; }
   if(mBfo) { g_modelReason="مدل شکست ساختار تا گپ تا اردر بلاک | شکست ساختار با کندل جابه‌جایی و هم‌پوشانی گپ و اردر بلاک هم‌جهت موجود است"; return MODEL_BOS_FVG_OB; }
   if(mSweep){ g_modelReason="مدل ورود پس از جارو | نقدینگی جارو شده و ناحیهٔ ورود داخل باند ورود بهینه همان لگ است"; return MODEL_SWEEP_ENTRY; }
   if(mOte) { g_modelReason="مدل فقط ورود بهینه | لگ معتبر هم‌جهت بایاس است و ناحیهٔ ورود داخل باند ورود بهینه قرار دارد"; return MODEL_OTE_ONLY; }
   g_modelReason="هیچ مدل شناخته‌شده‌ای شرط‌هایش کامل نشد";
   return MODEL_NONE;
}

