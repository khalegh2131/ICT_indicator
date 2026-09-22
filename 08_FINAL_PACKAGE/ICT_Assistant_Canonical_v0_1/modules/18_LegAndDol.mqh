//====================================================================
// LEG ENGINE (فاز ۱۰ / #۴۳) — «دامنهٔ معامله‌گری» از لگ واقعی ساخته می‌شود.
// قبلاً آخرین سقف تأییدشده و آخرین کف تأییدشده مستقل از هم برداشته
// می‌شدند و می‌توانستند به دو لگ مختلف (یا حتی برعکس ترتیب زمانی) تعلق
// داشته باشند؛ نتیجه یک رنج کاذب و EQ غلط بود.
// اکنون: پیوت‌های تأییدشدهٔ H4 به ترتیب زمان و به‌صورت **تناوبی** ساخته
// می‌شوند (سقف/کف یکی‌درمیان) و دو پیوت آخر همان لگ واقعی است؛ همان دو
// نقطه‌ای که کاربر می‌تواند فیبوی دستی را روی آن بگذارد.
//====================================================================
void UpdateDealingLeg(datetime barTime, double atrValue)
{
   g_leg.valid=false;
   g_leg.dir=DIR_NONE;
   g_leg.low=0; g_leg.high=0; g_leg.lowTime=0; g_leg.highTime=0;
   g_leg.startTime=0; g_leg.endTime=0; g_leg.startPrice=0; g_leg.endPrice=0;
   g_leg.range=0; g_leg.eq=0; g_leg.sizeATR=0;
   g_leg.reject="";

   MqlRates rates[];
   int copied=CopyRatesAsOf(_Symbol, g_mtfTimeframes[0], barTime, 300, rates);
   if(copied < InpSwingLeft+InpSwingRight+12)
   { g_leg.reject="H4_DATA_NOT_READY"; return; }

   // پیوت‌های تأییدشده، از قدیم به جدید (index 0 در سری = جدیدترین کندل)
   SwingPoint pivots[];
   int total=ArraySize(rates);
   for(int shift=total-InpSwingLeft-1; shift>=InpSwingRight; shift--)
   {
      bool isHigh=true, isLow=true;
      for(int side=1; side<=InpSwingLeft; side++)
      {
         if(rates[shift].high<=rates[shift+side].high) isHigh=false;   // چپ/قدیمی: اکید
         if(rates[shift].low >=rates[shift+side].low ) isLow=false;
      }
      for(int side=1; side<=InpSwingRight; side++)
      {
         // راست/جدید: مساوی‌پذیر (فاز ۲۲ — Double Top/EQH پیوت می‌سازند)
         if(shift-side<0 || rates[shift].high<rates[shift-side].high) isHigh=false;
         if(shift-side<0 || rates[shift].low >rates[shift-side].low ) isLow=false;
      }
      if(isHigh)
      {
         SwingPoint p; p.time=rates[shift].time; p.price=rates[shift].high;
         p.isHigh=true; p.confirmed=true; p.broken=false; p.id=0;
         int n=ArraySize(pivots); ArrayResize(pivots,n+1); pivots[n]=p;
      }
      if(isLow)
      {
         SwingPoint p; p.time=rates[shift].time; p.price=rates[shift].low;
         p.isHigh=false; p.confirmed=true; p.broken=false; p.id=0;
         int n=ArraySize(pivots); ArrayResize(pivots,n+1); pivots[n]=p;
      }
   }

   // فیلتر تناوبی: دو سقف/کف پشت‌سرهم مجاز نیست؛ اکسترمم‌تر جایگزین می‌شود
   SwingPoint seq[];
   for(int i=0;i<ArraySize(pivots);i++)
   {
      int n=ArraySize(seq);
      if(n==0){ ArrayResize(seq,1); seq[0]=pivots[i]; continue; }
      if(seq[n-1].isHigh==pivots[i].isHigh)
      {
         bool moreExtreme = pivots[i].isHigh ? (pivots[i].price>seq[n-1].price)
                                             : (pivots[i].price<seq[n-1].price);
         if(moreExtreme) seq[n-1]=pivots[i];
      }
      else
      {
         ArrayResize(seq,n+1); seq[n]=pivots[i];
      }
   }

   int ns=ArraySize(seq);
   if(ns<2){ g_leg.reject="NOT_ENOUGH_ALTERNATING_PIVOTS"; return; }

   SwingPoint p1=seq[ns-2];   // پیوت آغاز لگ
   SwingPoint p2=seq[ns-1];   // پیوت پایان لگ
   g_leg.startTime=p1.time;  g_leg.startPrice=p1.price;
   g_leg.endTime=p2.time;    g_leg.endPrice=p2.price;
   g_leg.low  = MathMin(p1.price,p2.price);
   g_leg.high = MathMax(p1.price,p2.price);
   if(p1.isHigh){ g_leg.highTime=p1.time; g_leg.lowTime=p2.time; }
   else         { g_leg.highTime=p2.time; g_leg.lowTime=p1.time; }
   g_leg.dir = p2.isHigh ? DIR_BULL : DIR_BEAR;   // پایان لگ روی سقف = لگ صعودی
   g_leg.range = g_leg.high-g_leg.low;
   if(g_leg.range<=0.0){ g_leg.reject="ZERO_RANGE"; return; }
   g_leg.eq = g_leg.low + g_leg.range*0.5;
   g_leg.sizeATR = (atrValue>0.0) ? g_leg.range/atrValue : 0.0;
   if(InpMinLegATR>0.0 && atrValue>0.0 && g_leg.sizeATR<InpMinLegATR)
   { g_leg.reject="LEG_TOO_SMALL"; return; }
   g_leg.valid=true;
}

// وزن نوع سطح نقدینگی در امتیازدهی DOL (#۴۸)
int LiqTypeWeight(ENUM_LIQ_TYPE t)
{
   switch(t)
   {
      case LIQ_PDH: case LIQ_PDL: case LIQ_PWH: case LIQ_PWL: return 15;
      case LIQ_EQH: case LIQ_EQL:                             return 12;
      case LIQ_SESSION_H: case LIQ_SESSION_L:                 return 9;
      case LIQ_SWING_H:   case LIQ_SWING_L:                   return 6;
   }
   return 0;
}

//====================================================================
// DOL ENGINE — فاز ۱۰ / #۴۸: امتیازدهی چندمعیاره با تفکیک عددی،
// نه وزن ثابت. حالا یک Internal نزدیک می‌تواند از یک External خیلی دور
// جلو بزند، و سطحی که R:R واقعی نمی‌سازد از ابتدا رد می‌شود.
//====================================================================
void UpdateDOL(double curClose, double atrValue)
{
   g_hasDOL = false;
   g_dolRejectReason="";
   if(g_htfBias==DIR_NONE) return;

   double atr = (atrValue>0.0)? atrValue : 0.0;
   long bestId=-1; double bestScore=-1e9; double bestPrice=0;
   ENUM_LIQ_SCOPE bestScope=SCOPE_INTERNAL; bool bestIsHTF=false;
   ENUM_LIQ_TYPE bestType=LIQ_SWING_H; double bestDistAtr=0;
   int considered=0, rejectedRoom=0;

   int n=ArraySize(g_liquidity);
   for(int i=0;i<n;i++)
   {
      if(g_liquidity[i].state!=LSTATE_FRESH) continue;
      bool isHighType = IsHighSideLiquidity(g_liquidity[i].type);
      // فقط جهت هم‌راستا با HTF Bias را در نظر می‌گیریم (رفع "نزدیک‌ترین بی‌جهت")
      if(g_htfBias==DIR_BULL && !isHighType) continue;
      if(g_htfBias==DIR_BEAR && isHighType) continue;

      double dist    = MathAbs(g_liquidity[i].price - curClose);
      double distAtr = (atr>0.0) ? dist/atr : 0.0;

      // اگر هدف خیلی نزدیک باشد، از فاصلهٔ واقعی ورود تا SL هیچ R:R درستی
      // ساخته نمی‌شود؛ پس این سطح به‌عنوان DOL معامله‌پذیر رد می‌شود (#۴۸/#۶۶).
      if(atr>0.0 && InpDOL_MinRoomATR>0.0 && distAtr<InpDOL_MinRoomATR)
      { rejectedRoom++; continue; }

      considered++;
      double score=0.0;
      if(g_liquidity[i].scope==SCOPE_EXTERNAL) score += 30.0;   // سلسله‌مراتب: External ارجح
      if(g_liquidity[i].isHTF)                 score += 10.0;   // سطح HTF وزن بیشتر
      score += (double)LiqTypeWeight(g_liquidity[i].type);       // کیفیت نوع سطح
      if(g_internalDir==g_htfBias)             score += 10.0;   // هم‌راستایی ساختار داخلی
      if(atr>0.0 && InpDOL_FarATR>0.0)
      {
         double prox = 1.0 - MathMin(distAtr,InpDOL_FarATR)/InpDOL_FarATR; // نزدیک‌تر = بالاتر
         score += 25.0*prox;
      }

      if(score>bestScore)
      {
         bestScore=score; bestId=g_liquidity[i].id; bestPrice=g_liquidity[i].price;
         bestScope=g_liquidity[i].scope; bestIsHTF=g_liquidity[i].isHTF;
         bestType=g_liquidity[i].type; bestDistAtr=distAtr;
      }
   }

   if(bestId==-1)
   {
      // Phase 42: no Latin token inside the Persian clause - ATR and FRESH are
      // spelled out, because this string is printed as a sentence in the panel.
      g_dolRejectReason = (rejectedRoom>0)
         ? StringFormat("همهٔ %d سطح هم‌جهت نزدیک‌تر از حداقل %.2f برابر میانگین دامنه بودند؛ نسبت سود به ریسک واقعی ساخته نمی‌شد", rejectedRoom, InpDOL_MinRoomATR)
         : "سطح نقدینگی هم‌جهت با بایاس و دست‌نخورده وجود ندارد";
      return;
   }

   g_currentDOL.liquidityId = bestId;
   g_currentDOL.price = bestPrice;
   g_currentDOL.direction = g_htfBias;
   g_currentDOL.htfAligned = bestIsHTF;
   g_currentDOL.structureAligned = (g_internalDir==g_htfBias);
   // از state واقعی سطح خوانده می‌شود، نه هاردکد true (#۴۸)
   g_currentDOL.sweepStateOk = true;   // شرط حلقه: فقط LSTATE_FRESH به اینجا می‌رسد
   g_currentDOL.hierarchyOk = (bestScope==SCOPE_EXTERNAL);
   g_currentDOL.score = (int)MathRound(bestScore);
   g_currentDOL.distATR = bestDistAtr;
   g_currentDOL.typeName = LiqTypeLabel(bestType);
   int wScope=(bestScope==SCOPE_EXTERNAL)?30:0;
   int wHTF=bestIsHTF?10:0;
   int wType=LiqTypeWeight(bestType);
   int wStruct=(g_internalDir==g_htfBias)?10:0;
   int wProx=0;
   if(atr>0.0 && InpDOL_FarATR>0.0)
      wProx=(int)MathRound(25.0*(1.0 - MathMin(bestDistAtr,InpDOL_FarATR)/InpDOL_FarATR));
   g_currentDOL.breakdown = StringFormat("EXTERNAL %d + HTF %d + TYPE %d + STRUCT %d + PROX %d = %d",
                                         wScope,wHTF,wType,wStruct,wProx,g_currentDOL.score);
   g_currentDOL.narrative = StringFormat("DOL | انتخاب از نوع %s | فاصله %.2f برابر میانگین دامنه | %d سطح بررسی شد | تفکیک: %s",
                                         g_currentDOL.typeName, bestDistAtr, considered, g_currentDOL.breakdown);
   g_hasDOL = true;
}

