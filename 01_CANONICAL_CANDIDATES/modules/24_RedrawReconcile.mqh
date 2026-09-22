//====================================================================
// فاز ۱۴ — REDRAW آشتی‌جویانه (reconciling redraw)
//
// مسئله: RedrawChartObjects قبلاً کل لایه را با ObjectsDeleteAll پاک می‌کرد و
// از Registry بازسازی می‌کرد. سقف‌های نمایش (InpMaxDrawnZones/InpMaxDrawnLevels)
// باعث می‌شد ناحیه‌ای که یک بار روی چارت دیده شده، با ورود ناحیهٔ جدید ناپدید
// شود. این خلاف RESEARCH_FINDINGS بند ۸ است («سیگنالی که یک بار روی چارت آمده
// نباید بی‌صدا جابه‌جا یا ناپدید شود»).
//
// راه‌حل: در هر pass هر آبجکتِ لایه با MarkDrawnLayerObj علامت می‌خورد. بعد از pass:
//   ۱) لایهٔ خاموش‌شدهٔ کاربر         → حذف
//   ۲) فیلتر صریح (MarkHiddenLayerObj) → حذف
//   ۳) علامت‌خوردهٔ همین pass         → زنده (بازنویسی شد)
//   ۴) بقیه (از سقف نمایش بیرون)      → به سبک frozen می‌ماند، نه حذف
// registry frozen کران‌دار است (InpMaxFrozenObjects، FIFO) تا چارت/حافظه نشت نکند.
// ترتیب Array g_frozen از قدیمی به جدید است؛ پس FIFO روی ابتدای آرایه کار می‌کند.
//====================================================================
string g_passDrawn[];       // آبجکت‌هایی که در همین pass بازنویسی شدند
string g_passHidden[];      // آبجکت‌هایی که این pass صریحاً فیلتر شدند (باید حذف شوند)
string g_frozen[];          // تاریخچهٔ frozen که از پنجرهٔ نمایش بیرون افتاده (قدیمی → جدید)
long   g_frozenAdded    = 0;  // شمارندهٔ کل frozen شدن‌ها
long   g_frozenEvicted  = 0;  // چند frozen برای کران‌داری حذف شد
long   g_frozenRestored = 0;  // چند آبجکت از frozen به حالت زنده برگشت
long   g_hiddenDeleted  = 0;  // چند آبجکت به‌خاطر فیلتر صریح/لایهٔ خاموش حذف شد
string g_frozenSymbol   = ""; // سیمبل/تایم‌فریم registry frozen (برای purge روی تغییر context)
ENUM_TIMEFRAMES g_frozenPeriod = PERIOD_CURRENT;
int    g_rcLayerObjects = 0, g_rcDrawn = 0, g_rcFrozen = 0;

bool IsLayerObjectName(const string nm)
{
   if(StringFind(nm,"ICTv13_")!=0) return false;
   if(StringFind(nm,"ICTv13_DASH_")==0) return false;   // داشبورد
   if(StringFind(nm,"ICTv13_EXP_")==0)  return false;   // پنل توضیح
   return true;
}

// لایه‌ای که کاربر صریحاً خاموش کرده باید حذف شود، نه frozen بماند
bool LayerDisabledForName(const string nm)
{
   if(StringFind(nm,"ICTv13_FVG")==0)    return !InpDrawFVGZones;
   if(StringFind(nm,"ICTv13_OB_")==0)    return !InpDrawOBZones;
   if(StringFind(nm,"ICTv13_LIQ_")==0)   return !InpDrawLiquidity;
   if(StringFind(nm,"ICTv13_SWEEP_")==0) return !InpDrawSweepMarkers;
   if(StringFind(nm,"ICTv13_EVT")==0)    return !InpDrawStructureEvents;
   if(StringFind(nm,"ICTv13_MTF_")==0)   return !InpDrawMTFRange;
   if(StringFind(nm,"ICTv13_SETUP_")==0) return !InpDrawSetupBox;
   if(StringFind(nm,"ICTv13_SESS_")==0)  return !(InpDrawKillzoneBoxes || InpDrawAsianRange || InpDrawSilverBullet);
   return false;   // REJECTION / LOCATION / DOL / TRENDLINE / POI / REVERSAL همیشه فعال‌اند
}

// باکس سشن‌ها با اندیس «چند روز قبل» نام‌گذاری می‌شوند. اگر کاربر
// InpKillzoneDaysBack را کم کند، اندیس‌های بالاتر دادهٔ بیات هستند و باید حذف
// شوند (نه frozen بمانند)، چون دیگر هیچ روزی را نمایندگی نمی‌کنند.
bool IsStaleSessionBoxName(const string nm)
{
   if(StringFind(nm,"ICTv13_SESS_")!=0) return false;
   int us=StringFind(nm,"_",13);
   if(us<0) return false;
   string sfx=StringSubstr(nm,us+1);
   int back=(int)StringToInteger(sfx);
   return (back>=InpKillzoneDaysBack);
}

int IndexInNameList(const string &list[], const string nm)
{
   for(int i=ArraySize(list)-1;i>=0;i--) if(list[i]==nm) return i;
   return -1;
}

void ResetPassDrawSet()
{
   ArrayResize(g_passDrawn,0);
   ArrayResize(g_passHidden,0);
}

void DropFromFrozenList(const string nm)
{
   int f=IndexInNameList(g_frozen,nm);
   if(f<0) return;
   for(int k=f;k<ArraySize(g_frozen)-1;k++) g_frozen[k]=g_frozen[k+1];
   ArrayResize(g_frozen,ArraySize(g_frozen)-1);
}

void MarkDrawnLayerObj(const string name)
{
   if(StringLen(name)==0) return;
   if(IndexInNameList(g_passDrawn,name)>=0) return;
   int n=ArraySize(g_passDrawn);
   ArrayResize(g_passDrawn,n+1);
   g_passDrawn[n]=name;

   // آبجکتی که دوباره داخل پنجرهٔ نمایش آمد، از frozen خارج و زنده می‌شود
   if(IndexInNameList(g_frozen,name)>=0)
   {
      DropFromFrozenList(name);
      g_frozenRestored++;
   }
}

void MarkHiddenLayerObj(const string name)
{
   if(StringLen(name)==0) return;
   if(IndexInNameList(g_passHidden,name)>=0) return;
   int n=ArraySize(g_passHidden);
   ArrayResize(g_passHidden,n+1);
   g_passHidden[n]=name;
}

void FreezeLayerObject(const string nm)
{
   long t=ObjectGetInteger(0,nm,OBJPROP_TYPE);
   string origStyle="";
   if(t==OBJ_HLINE || t==OBJ_TREND)
   {
      long st=ObjectGetInteger(0,nm,OBJPROP_STYLE);
      origStyle=(st==STYLE_SOLID?"solid":st==STYLE_DASH?"dash":st==STYLE_DOT?"dot":
                 st==STYLE_DASHDOT?"dashdot":st==STYLE_DASHDOTDOT?"dashdotdot":"other");
      ObjectSetInteger(0,nm,OBJPROP_STYLE,STYLE_DOT);
      ObjectSetInteger(0,nm,OBJPROP_WIDTH,1);
   }
   ObjectSetInteger(0,nm,OBJPROP_COLOR,InpFrozenColor);
   ObjectSetString(0,nm,OBJPROP_TOOLTIP,
      // Phase 42: the Persian clause carries no Latin word; the only Latin left
      // is a labelled segment of its own.
      "FROZEN HISTORY | از پنجرهٔ نمایش فعلی بیرون افتاده و به‌عنوان شاهد تاریخی نگه داشته شده است، نه حذف — موس را روی آن نگه دار تا توضیح کامل فارسی بیاید"
      +(StringLen(origStyle)>0?" | ORIGINAL STYLE — "+origStyle:""));

   int n=ArraySize(g_frozen);
   ArrayResize(g_frozen,n+1);
   g_frozen[n]=nm;
   g_frozenAdded++;

   // کران‌داری FIFO: قدیمی‌ترین frozen‌ها اول حذف می‌شوند
   if(InpMaxFrozenObjects>0 && ArraySize(g_frozen)>InpMaxFrozenObjects)
   {
      int drop=ArraySize(g_frozen)-InpMaxFrozenObjects;
      for(int k=0;k<drop;k++)
      {
         ObjectDelete(0,g_frozen[k]);
         g_frozenEvicted++;
      }
      for(int k=drop;k<ArraySize(g_frozen);k++) g_frozen[k-drop]=g_frozen[k];
      ArrayResize(g_frozen,ArraySize(g_frozen)-drop);
   }
}

// روی تغییر سیمبل/تایم‌فریم، registry frozen به context قبلی تعلق دارد
void PurgeFrozenOnContextChange()
{
   if(g_frozenSymbol==_Symbol && g_frozenPeriod==(ENUM_TIMEFRAMES)Period()) return;
   g_frozenSymbol=_Symbol;
   g_frozenPeriod=(ENUM_TIMEFRAMES)Period();
   for(int i=0;i<ArraySize(g_frozen);i++) ObjectDelete(0,g_frozen[i]);
   ArrayResize(g_frozen,0);
}

void ReconcileChartLayer()
{
   int total=ObjectsTotal(0,-1,-1);
   for(int i=total-1;i>=0;i--)
   {
      string nm=ObjectName(0,i,-1,-1);
      if(!IsLayerObjectName(nm)) continue;

      // منقضی‌شده‌ها و گذشتهٔ پیر، **کاملاً پاک** شوند
      // (نه frozen). ملاک عمر، زمان ساخت داخل نام نیست؛ اینجا با «قدیمی‌بودنِ زمان
      // لنگر آبجکت» پیر شمرده می‌شود تا تاریخچهٔ خیلی عقب زنده نماند.
      if(InpDeleteExpiredObjects && InpExpiryKeepBars>0)
      {
         datetime anchor=(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,0);
         if(anchor<=0) anchor=(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,1);
         if(anchor>0 && g_lastContextBarTime>0)
         {
            int ageBars=(int)((g_lastContextBarTime-anchor)/MathMax(1,PeriodSeconds(PERIOD_CURRENT)));
            if(ageBars>InpExpiryKeepBars)
            {
               ObjectDelete(0,nm);
               DropFromFrozenList(nm);
               g_hiddenDeleted++;
               continue;
            }
         }
      }

      if(LayerDisabledForName(nm) || IsStaleSessionBoxName(nm) || IndexInNameList(g_passHidden,nm)>=0)
      {
         ObjectDelete(0,nm);
         DropFromFrozenList(nm);
         g_hiddenDeleted++;
         continue;
      }
      if(!InpFrozenHistoryEnabled)
      {
         ObjectDelete(0,nm);
         DropFromFrozenList(nm);
         continue;
      }
      if(IndexInNameList(g_passDrawn,nm)>=0) continue;   // همین pass بازنویسی شد: زنده
      if(IndexInNameList(g_frozen,nm)>=0)    continue;   // قبلاً frozen شده: دست نمی‌زنیم
      FreezeLayerObject(nm);                             // بیرون از سقف نمایش → شاهد تاریخی
   }
   g_rcLayerObjects=total;
   g_rcDrawn=ArraySize(g_passDrawn);
   g_rcFrozen=ArraySize(g_frozen);
}

void DrawHLineObj(string name, double price, color clr, ENUM_LINE_STYLE style, int width, string tip)
{
   if(price<=0.0) return;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_HLINE,0,0,price);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,"\n");
   MarkDrawnLayerObj(name);
}

void DrawTextObj(string name, datetime t, double price, string text, color clr, int size, string tip)
{
   if(t<=0 || price<=0.0) return;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_TEXT,0,t,price);
   ObjectSetInteger(0,name,OBJPROP_TIME,0,t);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,price);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
   ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
   ObjectSetString(0,name,OBJPROP_TOOLTIP,"\n");
   MarkDrawnLayerObj(name);
}

void DrawBoxObj(string name, datetime t1, double p1, datetime t2, double p2,
                color clr, bool fill, bool back, ENUM_LINE_STYLE style, int width, string tip)
{
   if(t1<=0 || p1<=0.0 || p2<=0.0) return;
   if(t2<=t1) t2 = t1 + PeriodSeconds()*3;
   if(p2>p1) { double swap=p1; p1=p2; p2=swap; }
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,p1,t2,p2);
   ObjectSetInteger(0,name,OBJPROP_TIME,0,t1);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,p1);
   ObjectSetInteger(0,name,OBJPROP_TIME,1,t2);
   ObjectSetDouble(0,name,OBJPROP_PRICE,1,p2);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FILL,fill);
   ObjectSetInteger(0,name,OBJPROP_BACK,back);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,"\n");
   MarkDrawnLayerObj(name);
}

// نقشهٔ نقدینگی: همهٔ سطوح لمس‌نشده (FRESH) و جاروشده (SWEPT)
void DrawLiquidityLayer()
{
   int drawn=0;
   for(int i=ArraySize(g_liquidity)-1; i>=0 && drawn<InpMaxDrawnLevels; i--)
   {
      if(g_liquidity[i].state==LSTATE_INVALID) continue;
      bool swept = (g_liquidity[i].state==LSTATE_SWEPT);
      // گذشتهٔ فیلدشده رسم نشود. سطح SWEPT فقط اگر تازه باشد
      // (برای مرجع الگوی سوئپ) و سطح INVALID هرگز رسم نمی‌شود.
      if(swept)
      {
         if(InpSweptKeepBars<=0) continue;
         datetime sweptT=g_liquidity[i].sweptTime;
         if(sweptT<=0) continue;
         int age=(int)((g_lastContextBarTime-sweptT)/MathMax(1,PeriodSeconds(PERIOD_CURRENT)));
         if(age>InpSweptKeepBars) continue;
      }
      bool isIPDA=(g_liquidity[i].type==LIQ_IPDA20_H || g_liquidity[i].type==LIQ_IPDA20_L ||
                   g_liquidity[i].type==LIQ_IPDA40_H || g_liquidity[i].type==LIQ_IPDA40_L ||
                   g_liquidity[i].type==LIQ_IPDA60_H || g_liquidity[i].type==LIQ_IPDA60_L);
      // بازبینی نمایش: IPDA سطوح خودش را دارد؛ اگر کاربر خاموشش کرده، نرسم
      // (در داشبورد و CSV کامل دیده می‌شود). کشف دست نخورد — فقط رسم.
      if(isIPDA && !InpDrawIPDA) continue;
      bool highSide = IsHighSideLiquidity(g_liquidity[i].type);
      // فاز ۴۸: رنگ از پالت واحد می‌آید (پیش‌تر Tomato/MediumSeaGreen بودند و
      // با خط روند بروکس و ناحیهٔ FVG صعودی قاطی می‌شدند).
      color clr = swept ? PAL_STATE_SWEPT : (highSide?PAL_LIQ_HIGH:PAL_LIQ_LOW);
      if(g_liquidity[i].isHTF && !swept) clr = highSide?PAL_LIQ_HTF_HIGH:PAL_LIQ_HTF_LOW;
      ENUM_LINE_STYLE style = swept ? STYLE_DOT : (g_liquidity[i].isHTF?STYLE_SOLID:STYLE_DASH);
      string name = "ICTv13_LIQ_"+IdToStr(g_liquidity[i].id);
      string tip = StringFormat("%s | %s | %s | price=%s%s",
                    LiqTypeLabel(g_liquidity[i].type),
                    g_liquidity[i].scope==SCOPE_EXTERNAL?"External (HTF)":"Internal (LTF)",
                    swept? "SWEPT at "+TimeToString(g_liquidity[i].sweptTime,TIME_DATE|TIME_MINUTES) : "FRESH - untapped liquidity",
                    DoubleToString(g_liquidity[i].price,_Digits),
                    swept? StringFormat(" | swept by event #%s",IdToStr(g_liquidity[i].sweptByEventId)):"");
      DrawHLineObj(name, g_liquidity[i].price, clr, style, g_liquidity[i].isHTF?2:1, tip);
      if(InpDrawLevelLabels)
         DrawTextObj(name+"_T", g_lastContextBarTime, g_liquidity[i].price,
                     (swept?"SWEPT ":"")+LiqTypeLabel(g_liquidity[i].type), clr, 8, tip);
      drawn++;
   }

   // سطوح INVALID دیگر رسم نمی‌شوند؛ تاریخچه در CSV می‌ماند.
   if(!InpHideInvalidatedObjects)
   {
      int invalidCap=InpMaxDrawnLevels/3;
      if(invalidCap<1) invalidCap=1;
      int drawnInvalid=0;
      for(int i=ArraySize(g_liquidity)-1; i>=0 && drawnInvalid<invalidCap; i--)
      {
         if(g_liquidity[i].state!=LSTATE_INVALID) continue;
         string name = "ICTv13_LIQ_"+IdToStr(g_liquidity[i].id);
         string tip = StringFormat("%s | %s | INVALID: price accepted beyond this level (close-through) | price=%s",
                       LiqTypeLabel(g_liquidity[i].type),
                       g_liquidity[i].scope==SCOPE_EXTERNAL?"External (HTF)":"Internal (LTF)",
                       DoubleToString(g_liquidity[i].price,_Digits));
         DrawHLineObj(name, g_liquidity[i].price, PAL_STATE_INVALID, STYLE_DOT, 1, tip);
         drawnInvalid++;
      }
   }
}

// علامت Sweep: کجا و کدام سطح جارو شد
void DrawSweepLayer()
{
   int drawn=0;
   for(int i=ArraySize(g_liquidity)-1; i>=0 && drawn<InpMaxDrawnLevels; i--)
   {
      if(g_liquidity[i].state!=LSTATE_SWEPT || g_liquidity[i].sweptTime<=0) continue;
      // نشانِ سوئپ هم گذشته است؛ فقط چند کندل آخر می‌ماند.
      if(InpSweptKeepBars>0)
      {
         int age=(int)((g_lastContextBarTime-g_liquidity[i].sweptTime)/MathMax(1,PeriodSeconds(PERIOD_CURRENT)));
         if(age>InpSweptKeepBars) continue;
      }
      else continue;
      bool highSide = IsHighSideLiquidity(g_liquidity[i].type);
      color clr = highSide?PAL_LIQ_HTF_HIGH:PAL_LIQ_HTF_LOW;
      DrawTextObj("ICTv13_SWEEP_"+IdToStr(g_liquidity[i].id),
                  g_liquidity[i].sweptTime, g_liquidity[i].price,
                  highSide?"SWEEP (BSL)":"SWEEP (SSL)", clr, 8,
                  StringFormat("%s swept and closed back inside | %s | price=%s",
                               LiqTypeLabel(g_liquidity[i].type),
                               TimeToString(g_liquidity[i].sweptTime,TIME_DATE|TIME_MINUTES),
                               DoubleToString(g_liquidity[i].price,_Digits)));
      drawn++;
   }
}

// ناحیه‌های FVG / OB / Rejection
void DrawZoneLayer()
{
   if(InpDrawFVGZones)
   {
      int drawn=0;
      for(int i=ArraySize(g_fvgs)-1; i>=0 && drawn<InpMaxDrawnZones; i--)
      {
         // فیلتر صریح کاربر = حذف (نه frozen)؛ آبجکتی که کاربر نخواسته دیده شود
         // نباید به‌عنوان «شاهد تاریخی» دورگه روی چارت بماند.
         if(InpDrawOnlyCausalFVG && !g_fvgs[i].causal)
         {
            MarkHiddenLayerObj("ICTv13_FVG_"+IdToStr(g_fvgs[i].id));
            MarkHiddenLayerObj("ICTv13_FVGCE_"+IdToStr(g_fvgs[i].id));
            continue;
         }
         if(g_fvgs[i].invalidated)
         {
            MarkHiddenLayerObj("ICTv13_FVG_"+IdToStr(g_fvgs[i].id));
            MarkHiddenLayerObj("ICTv13_FVGCE_"+IdToStr(g_fvgs[i].id));
            continue;
         }
         // FVG لمس‌شده/معکوس‌شده گذشته رسم نشود.
         // iFVG پولاریتی عوض کرده و دوباره «سطح معکوس» معتبر است، پس با منطق
         // «گذشته پاک شود» نمی‌خورد؛ فقط mitigated قدیمی حذف می‌شود. برای mitigated
         // فاقد touchTime ثبت‌شده، زمان تولد مبنا گرفته می‌شود (تولد قدیمی = گذشته).
         if(InpHideInvalidatedObjects && g_fvgs[i].mitigated && !g_fvgs[i].inverted)
         {
            datetime touchRef=(g_fvgs[i].touchTime>0)? g_fvgs[i].touchTime : g_fvgs[i].time;
            if((int)((g_lastContextBarTime-touchRef)/MathMax(1,PeriodSeconds(PERIOD_CURRENT)))>InpSweptKeepBars)
            {
               MarkHiddenLayerObj("ICTv13_FVG_"+IdToStr(g_fvgs[i].id));
               MarkHiddenLayerObj("ICTv13_FVGCE_"+IdToStr(g_fvgs[i].id));
               continue;
            }
         }
         // هر تایم‌فریم برای خودش رسم کند — ناحیهٔ متعلق به
         // تایم‌فریم مالکش رسم می‌شود (نه تایم‌فریم چارت). Micro (M1) همیشه رسم است.
         if(InpDrawPerTimeframe && g_fvgs[i].kind==FVGK_STANDARD && g_fvgs[i].tf!=PERIOD_CURRENT)
         {
            MarkHiddenLayerObj("ICTv13_FVG_"+IdToStr(g_fvgs[i].id));
            MarkHiddenLayerObj("ICTv13_FVGCE_"+IdToStr(g_fvgs[i].id));
            continue;
         }
         DrawFVG(g_fvgs[i]);
         drawn++;
      }
   }
   if(InpDrawOBZones)
   {
      int drawn=0;
      for(int i=ArraySize(g_obs)-1; i>=0 && drawn<InpMaxDrawnZones; i--)
      {
         // OB شکسته/نامعتبر گذشته رسم نشود؛ MITIGATED تازه می‌ماند.
         if(InpHideInvalidatedObjects &&
            (g_obs[i].state==OB_BROKEN || g_obs[i].state==OB_INVALID))
         {
            MarkHiddenLayerObj("ICTv13_OB_"+IdToStr(g_obs[i].id));
            continue;
         }
         // هر تایم‌فریم برای خودش رسم کند.
         if(InpDrawPerTimeframe && g_obs[i].tf!=PERIOD_CURRENT)
         {
            MarkHiddenLayerObj("ICTv13_OB_"+IdToStr(g_obs[i].id));
            continue;
         }
         DrawOB(g_obs[i]);
         drawn++;
      }
   }
   int drawnR=0;
   for(int i=ArraySize(g_rejections)-1; i>=0 && drawnR<InpMaxDrawnZones; i--)
   {
      if(InpHideInvalidatedObjects && g_rejections[i].rejectionState==REJECTION_INVALID)
      {
         MarkHiddenLayerObj("ICTv13_REJECTION_"+IdToStr(g_rejections[i].id));
         continue;
      }
      DrawRejection(g_rejections[i]);
      drawnR++;
   }
}

// سشن‌ها و کیلیزون‌ها به وقت نیویورک (شامل Asian Range به‌عنوان هدف نقدینگی)
void DrawSessionLayer()
{
   datetime ref = g_lastContextBarTime>0 ? g_lastContextBarTime : TimeCurrent();
   for(int back=0; back<InpKillzoneDaysBack; back++)
   {
      datetime s=0,e=0; double hi=0,lo=0; int cnt=0;
      string sfx=IntegerToString(back);
      if(InpDrawAsianRange && WindowForDayBack(back,InpAsiaStartHourNY,0,InpAsiaEndHourNY,0,ref,s,e,hi,lo,cnt,true))
         DrawBoxObj("ICTv13_SESS_ASIA_"+sfx, s, hi, e, lo, PAL_SESS_ASIA, false, true, STYLE_DOT, 1,
                    StringFormat("Asian Range (Accumulation) %.2f - %.2f | primary liquidity target for London",lo,hi));
      if(InpDrawKillzoneBoxes)
      {
         if(WindowForDayBack(back,InpLondonStartHourNY,0,InpLondonEndHourNY,0,ref,s,e,hi,lo,cnt,true))
            DrawBoxObj("ICTv13_SESS_LON_"+sfx, s, hi, e, lo, PAL_SESS_LONDON, false, true, STYLE_DOT, 1,
                       StringFormat("London Killzone %02d:00-%02d:00 NY | Manipulation / Judas Swing window",InpLondonStartHourNY,InpLondonEndHourNY));
         if(WindowForDayBack(back,InpNY_KZ_StartHourNY,0,InpNY_KZ_EndHourNY,0,ref,s,e,hi,lo,cnt,true))
            DrawBoxObj("ICTv13_SESS_NYAM_"+sfx, s, hi, e, lo, PAL_SESS_NY, false, true, STYLE_DOT, 1,
                       StringFormat("New York AM Killzone %02d:00-%02d:00 NY | Distribution",InpNY_KZ_StartHourNY,InpNY_KZ_EndHourNY));
         if(WindowForDayBack(back,InpLondonCloseStartHourNY,0,InpLondonCloseEndHourNY,0,ref,s,e,hi,lo,cnt,true))
            DrawBoxObj("ICTv13_SESS_LONCL_"+sfx, s, hi, e, lo, PAL_SESS_LONDONCLOSE, false, true, STYLE_DOT, 1,
                       StringFormat("London Close Killzone %02d:00-%02d:00 NY",InpLondonCloseStartHourNY,InpLondonCloseEndHourNY));
         if(WindowForDayBack(back,InpNYPM_StartHourNY,InpNYPM_StartMinuteNY,InpNYPM_EndHourNY,InpNYPM_EndMinuteNY,ref,s,e,hi,lo,cnt,true))
            DrawBoxObj("ICTv13_SESS_NYPM_"+sfx, s, hi, e, lo, PAL_SESS_NYPM, false, true, STYLE_DOT, 1,
                       StringFormat("New York PM Killzone %02d:%02d-%02d:%02d NY",InpNYPM_StartHourNY,InpNYPM_StartMinuteNY,InpNYPM_EndHourNY,InpNYPM_EndMinuteNY));
      }
      // Silver Bullet: قبلاً فقط متن داشبورد بود و InpDrawSilverBullet هیچ باکسی
      // رسم نمی‌کرد (رفع #۵۲). حالا هر سه پنجره رسم می‌شوند.
      if(InpDrawSilverBullet)
      {
         if(WindowForDayBack(back,InpSB1_StartHourNY,0,InpSB1_EndHourNY,0,ref,s,e,hi,lo,cnt,true))
            DrawBoxObj("ICTv13_SESS_SB1_"+sfx, s, hi, e, lo, PAL_SESS_SB, false, true, STYLE_DASHDOT, 1,
                       StringFormat("Silver Bullet #1 %02d:00-%02d:00 NY | one-hour algorithmic window. The window itself is NOT a signal: wait for a level sweep + displacement/FVG inside it",InpSB1_StartHourNY,InpSB1_EndHourNY));
         if(WindowForDayBack(back,InpSB2_StartHourNY,0,InpSB2_EndHourNY,0,ref,s,e,hi,lo,cnt,true))
            DrawBoxObj("ICTv13_SESS_SB2_"+sfx, s, hi, e, lo, PAL_SESS_SB, false, true, STYLE_DASHDOT, 1,
                       StringFormat("Silver Bullet #2 %02d:00-%02d:00 NY | one-hour algorithmic window. The window itself is NOT a signal: wait for a level sweep + displacement/FVG inside it",InpSB2_StartHourNY,InpSB2_EndHourNY));
         if(WindowForDayBack(back,InpSB3_StartHourNY,0,InpSB3_EndHourNY,0,ref,s,e,hi,lo,cnt,true))
            DrawBoxObj("ICTv13_SESS_SB3_"+sfx, s, hi, e, lo, PAL_SESS_SB, false, true, STYLE_DASHDOT, 1,
                       StringFormat("Silver Bullet #3 %02d:00-%02d:00 NY | one-hour algorithmic window. The window itself is NOT a signal: wait for a level sweep + displacement/FVG inside it",InpSB3_StartHourNY,InpSB3_EndHourNY));
      }
   }
}

// سطوح حفاظت‌شدهٔ هر تایم‌فریم MTF با ذکر مالک و نقش
void DrawMTFLayer()
{
   if(!InpDrawMTFRange) return;
   for(int index=0; index<6; index++)
   {
      if(g_mtfContext[index].protectedHigh<=0.0 && g_mtfContext[index].protectedLow<=0.0) continue;
      string tag = EnumToString(g_mtfContext[index].timeframe);
      color clr = (g_mtfContext[index].externalDirection==DIR_BULL)?clrLime:
                  (g_mtfContext[index].externalDirection==DIR_BEAR)?clrOrangeRed:clrSilver;
      int width = (index==0)?2:1;
      string tip = StringFormat("%s | role=%s | direction=%s | as of %s",tag,g_mtfContext[index].role,
                                 DirToStr(g_mtfContext[index].externalDirection),
                                 TimeToString(g_mtfContext[index].confirmedBarTime,TIME_DATE|TIME_MINUTES));
      if(g_mtfContext[index].protectedHigh>0.0)
         DrawHLineObj("ICTv13_MTF_"+tag+"_H", g_mtfContext[index].protectedHigh, clr, STYLE_DASHDOTDOT, width,
                      "Protected HIGH | "+tip);
      if(g_mtfContext[index].protectedLow>0.0)
         DrawHLineObj("ICTv13_MTF_"+tag+"_L", g_mtfContext[index].protectedLow, clr, STYLE_DASHDOTDOT, width,
                      "Protected LOW | "+tip);
   }
}

// باکس ستاپ + Entry/SL/TP با دلیل و وضعیت
void DrawSetupLayer()
{
   if(!InpDrawSetupBox) return;
   long obId=-1, fvgId=-1;
   double zTop=0, zBot=0;
   for(int i=ArraySize(g_obs)-1;i>=0;i--)
      if(g_obs[i].state==OB_VALID && !g_obs[i].isStandalone){ obId=g_obs[i].id; zTop=g_obs[i].top; zBot=g_obs[i].bottom; break; }
   if(obId==-1)
      for(int i=ArraySize(g_fvgs)-1;i>=0;i--)
         if(g_fvgs[i].causal && !g_fvgs[i].invalidated && !g_fvgs[i].inverted){ fvgId=g_fvgs[i].id; zTop=g_fvgs[i].top; zBot=g_fvgs[i].bottom; break; }

   datetime t1 = g_lastContextBarTime>0 ? g_lastContextBarTime : TimeCurrent();
   if(obId!=-1 || fvgId!=-1)
      DrawBoxObj("ICTv13_SETUP_ZONE", t1, zTop, t1 + PeriodSeconds()*InpZoneExtendBars, zBot,
                 g_setup.active?PAL_SETUP:PAL_STATE_INVALID, false, true, STYLE_SOLID, 2,
                 StringFormat("Entry zone = %s | status=%s | refines with CE/OTE",
                              obId!=-1?"Order Block":"FVG", g_setup.status));

   if(g_setup.active)
   {
      DrawHLineObj("ICTv13_SETUP_ENTRY", g_setup.entry, PAL_SETUP, STYLE_SOLID, 1, "Setup Entry | "+g_setup.status);
      DrawHLineObj("ICTv13_SETUP_SL",    g_setup.sl,    InpColorBear, STYLE_SOLID, 1,
                   "Setup SL | invalidated only by a CLOSED bar beyond it | lifecycle="+g_setupLifeState);
      DrawHLineObj("ICTv13_SETUP_TP1",   g_setup.tp1,   InpColorBull, STYLE_DASH, 1, "TP1 = 1R");
      DrawHLineObj("ICTv13_SETUP_TP2",   g_setup.tp2,   InpColorBull, STYLE_DASH, 1, "TP2 = 2R");
      DrawHLineObj("ICTv13_SETUP_TP3",   g_setup.tp3,   InpColorBull, STYLE_DASH, 1, "TP3 = draw on liquidity");
      DrawTextObj("ICTv13_SETUP_TXT", t1, g_setup.entry,
                  (g_setup.dir==DIR_BULL?"LONG ":"SHORT ")+g_setup.status,
                  g_setup.dir==DIR_BULL?InpColorBull:InpColorBear, 10,
                  StringFormat("Setup %s | bias owner=%s | DOL=%.2f | FVG#%s OB#%s",
                               g_setup.status, EnumToString(g_mtfTimeframes[0]), g_currentDOL.price,
                               IdToStr(g_setup.fvgId), IdToStr(g_setup.obId)));
   }
   else
   {
      double refPrice = (g_analysisClose>0.0)? g_analysisClose : SymbolInfoDouble(_Symbol,SYMBOL_BID);
      DrawTextObj("ICTv13_SETUP_TXT", t1, refPrice, "WAIT: "+g_setup.status, InpColorNeutral, 9,
                  g_mtfConflictReason!=""? g_mtfConflictReason : "Setup not READY on the latest closed bar");
   }

   // فاز ۱۵ (#۶۶): نشانهٔ چرخهٔ عمر ستاپ. خط SL ستاپ پیگیری‌شده و برچسب ابطال
   // روی چارت می‌مانند تا مشخص باشد ستاپ *کجا* باطل شد — همین چیزی که تا
   // پیش از این فاز هیچ‌جا ثبت نمی‌شد.
   if(InpTrackSetupLifecycle && (g_setupLifeState=="INVALIDATED" || g_setupLifeState=="TP1_HIT"))
   {
      datetime tEnd  = (g_setupLifeEndTime>0)? g_setupLifeEndTime : t1;
      double   pEnd  = g_setupLifeEndPrice;
      if(g_setupLifeSL>0.0)
         DrawHLineObj("ICTv13_SETUP_LIFE_SL", g_setupLifeSL, InpFrozenColor, STYLE_DOT, 1,
                      StringFormat("Setup being tracked from %s | SL = %s | lifecycle=%s",
                                   TimeToString(g_setupLifeArmTime,TIME_DATE|TIME_MINUTES),
                                   DoubleToString(g_setupLifeSL,_Digits), g_setupLifeState));
      if(pEnd>0.0)
      {
         string lifeTxt = (g_setupLifeState=="INVALIDATED")? "SETUP INVALIDATED" : "SETUP TP1 HIT (1R)";
         if(g_setupLifeState=="INVALIDATED")
            DrawHLineObj("ICTv13_SETUP_LIFE_END", pEnd, InpColorBear, STYLE_DASH, 1,
                         "Closing price was beyond the protected SL level here");
         DrawTextObj("ICTv13_SETUP_LIFE_TXT", tEnd, pEnd, lifeTxt,
                     (g_setupLifeState=="INVALIDATED")? InpColorBear : InpColorBull, 10,
                     "Setup lifecycle | "+g_setupLifeState+" | "+g_setupLifeReason);
      }
   }
}

// فاز ۱۱: سطح محافظت‌شدهٔ خارجی (دروازهٔ برگشت) و تأییدیهٔ برگشت
void DrawReversalLevels()
{
   // (چارت خلوت‌تر): فقط هشدارهای *فعال* برگشت رسم شوند —
   // دروازهٔ مسلح‌شده یا تأییدشده؛ حالت ساکن خطی روی چارت نمی‌گذارد.
   if(!InpDrawReversalLevel || !InpEnableReversalGate) return;
   if(!g_reversal.armed && !g_reversal.confirmed) return;
   if(g_reversal.armed && g_reversal.levelPrice>0.0)
   {
      string name="ICTv13_REVERSAL_GATE";
      string tip=StringFormat("Protected external level (%s) | price=%s | the reversal direction this level would confirm: %s",
                    g_reversal.levelIsHigh?"HIGH":"LOW", DoubleToString(g_reversal.levelPrice,_Digits),
                    DirToStr(OppositeDir(g_reversal.snapBias)));
      color gateClr = g_reversal.confirmed?PAL_GATE_CONFIRMED:PAL_GATE_PENDING;
      DrawHLineObj(name, g_reversal.levelPrice, gateClr,
                   g_reversal.confirmed?STYLE_SOLID:STYLE_DASH, 2, tip);
      if(InpDrawLevelLabels)
         DrawTextObj(name+"_T", g_lastContextBarTime, g_reversal.levelPrice, "REVERSAL GATE", gateClr, 8, tip);
   }
   if(g_reversal.confirmed && g_reversal.confirmedTime>0 && g_reversal.confirmedClose>0.0)
   {
      DrawTextObj("ICTv13_REVERSAL_CONFIRMED", g_reversal.confirmedTime, g_reversal.confirmedClose,
                  (g_reversal.dir==DIR_BULL?"REVERSAL CONFIRMED (BULLISH)":"REVERSAL CONFIRMED (BEARISH)"),
                  PAL_GATE_CONFIRMED, 9,
                  StringFormat("Confirmed reversal (%s) | a closed %s bar closed beyond the protected external level | SMR %d/%d",
                               DirToStr(g_reversal.dir), EnumToString(InpHTF), g_reversal.smrScore, g_reversal.smrMax));
   }
}

// ================= فازهای ۱۶–۲۱: رسم + hover فارسی =================
void DrawFamiliesLayer()
{
   // Wyckoff: رویدادهای آخر روی چارت (Spring/Upthrust مهم‌ترین‌اند).
   // بازبینی نمایش (2026-09-18): برچسب‌های متنی تکراری (SC/BC/AR/ST/…) «تزئینی»‌اند؛
   // پیش‌فرض خاموش. Spring/Upthrust که واقعاً سوئپ نقدینگی‌اند، از خودشان در لایهٔ
   // نقدینگی/سوئپ شواهد دارند. محاسبات Wyckoff (فاز/دلیل در داشبورد) دست‌نخورده.
   if(InpEnableWyckoff && InpDrawWyckoffLabels)
   {
      int drawn=0;
      for(int i=ArraySize(g_wyck)-1; i>=0 && drawn<6; i--)
      {
         if(g_wyck[i].evt==WE_NONE) continue;
         string label="";
         switch(g_wyck[i].evt)
         {
            case WE_SC: label="SC"; break;        case WE_BC: label="BC"; break;
            case WE_AR: label="AR"; break;        case WE_ST: label="ST"; break;
            case WE_SPRING: label="SPRING"; break; case WE_UPTHRUST: label="UPTHRUST"; break;
            case WE_SOS: label="SOS"; break;      case WE_SOW: label="SOW"; break;
            case WE_LPS: label="LPS"; break;      case WE_LPSY: label="LPSY"; break;
            case WE_TEST: label="TEST"; break;    case WE_ABSORPTION: label="ABSORB"; break;
            default: continue;
         }
         color wc=(g_wyck[i].evt==WE_SPRING)?InpColorBull:(g_wyck[i].evt==WE_UPTHRUST)?InpColorBear:InpColorNeutral;
         DrawTextObj("ICTv13_WYCK_"+IdToStr(g_wyck[i].id), g_wyck[i].time, g_wyck[i].price, label, wc, 8,
                     StringFormat("Wyckoff %s | فاز: %s | %s",label,
                                  (g_wyck[i].phase>=WP_A&&g_wyck[i].phase<=WP_E)?IntegerToString((int)g_wyck[i].phase):"—",
                                  g_wyckPhaseReason));
         drawn++;
      }
   }
   // Supply/Demand: ناحیهٔ ورود واقعی است (مانند FVG/OB) → پیش‌فرض روشن؛
   // سقف رسم هم به‌جای عدد ثابت ۱۰ از سقف رجیستری InpSD_MaxZones می‌آید تا
   // «رجیستری» و «نمایش» از هم جدا بمانند. هر تایم‌فریم مالک، رسم مخصوص خودش:
   // ناحیهٔ متعلق به تایم‌فریم دیگر روی این چارت رسم نمی‌شود (طراحی پروژه).
   if(InpEnableSupplyDemand && InpDrawSDZones)
   {
      int drawn=0;
      int sdCap=MathMin(10,InpSD_MaxZones);
      for(int i=ArraySize(g_sd)-1; i>=0 && drawn<sdCap; i--)
      {
         if(InpHideInvalidatedObjects && g_sd[i].state==SDS_BROKEN) continue;
         if(InpDrawPerTimeframe && g_sd[i].tf!=PERIOD_CURRENT) continue;
         // فاز ۳۳: رنگ و نقش از «نقش زندهٔ» ناحیه می‌آید، نه از نوع اولیهٔ الگو —
         // پس یک Flip Zone هم رنگ درست می‌گیرد و هم بعد از Flip زنده می‌ماند.
         bool isSupp=g_sd[i].roleSupply;
         color sc=isSupp?PAL_SD_SUPPLY:PAL_SD_DEMAND;
         if(g_sd[i].state==SDS_FLIPPED) sc=PAL_STATE_MITIGATED;
         else if(g_sd[i].state==SDS_TESTED) sc=PAL_STATE_SWEPT;
         string kn=SDKindToStr(g_sd[i].kind)+(g_sd[i].flipped? " → Flipped": "");
         DrawBoxObj("ICTv13_SD_"+IdToStr(g_sd[i].id), g_sd[i].time, g_sd[i].top,
                    (datetime)((long)g_sd[i].time+(long)PeriodSeconds()*InpZoneExtendBars), g_sd[i].bottom,
                    sc, false, true, STYLE_DOT, 1,
                    StringFormat("S/D %s | role=%s | state=%s | tests=%d | exit=%.2f ATR",kn,
                                 isSupp?"Supply":"Demand",
                                 g_sd[i].state==SDS_FRESH?"FRESH":g_sd[i].state==SDS_TESTED?"TESTED":g_sd[i].state==SDS_FLIPPED?"FLIPPED":"BROKEN",
                                 g_sd[i].tests, g_sd[i].exitMove));
         drawn++;
      }
   }
   // RTM (فاز ۳۴): رویدادها فقط اگر کاربر خواست روی چارت بیایند (پیش‌فرض خاموش
   // تا چارت شلوغ نشود)؛ ولی داده، رجیستری و پنل آموزشی همیشه فعال است.
   if(InpEnableRTM && InpDrawRTMObjects)
   {
      int rn=ArraySize(g_rtm), drawn=0;
      for(int i=rn-1; i>=0 && drawn<8; i--)
      {
         color rc=(g_rtm[i].dir>0)? InpColorBull : ((g_rtm[i].dir<0)? InpColorBear : InpColorNeutral);
         DrawTextObj("ICTv13_RTM_"+IdToStr(g_rtm[i].id), g_rtm[i].time, g_rtm[i].price,
                     "RTM:"+IntegerToString((int)g_rtm[i].evt), rc, 8, g_rtm[i].note);
         drawn++;
      }
   }
   // Profile: POC/VAH/VAL فقط اگر کاربر خواست
   // فاز ۳۴: خطوط IB و TPO-VA و Naked POC هم اضافه شدند — همه با پیشوند PROF_ تا
   // همان کلیک/پنل آموزشی داشته باشند (هیچ خطی بی‌توضیح نمی‌ماند).
   if(InpEnableProfile && (InpDrawProfileOnChart || InpDrawAMTOnChart) && g_profileDaily.valid)
   {
      DrawHLineObj("ICTv13_PROF_POC", g_profileDaily.poc, PAL_PROF_POC, STYLE_SOLID, 1, "POC | حجم تیک | "+g_profileNote);
      DrawHLineObj("ICTv13_PROF_VAH", g_profileDaily.vah, PAL_PROF_VA, STYLE_DOT, 1, "VAH | "+g_profileNote);
      DrawHLineObj("ICTv13_PROF_VAL", g_profileDaily.val, PAL_PROF_VA, STYLE_DOT, 1, "VAL | "+g_profileNote);
      if(g_profileDaily.tpoValid)
      {
         DrawHLineObj("ICTv13_PROF_TPOC", g_profileDaily.tpoPoc, PAL_PROF_TPO, STYLE_DASH, 1,
                      StringFormat("TPO POC | VA %.2f–%.2f | زمان‌محور است، نه حجم", g_profileDaily.tpoVah, g_profileDaily.tpoVal));
         DrawHLineObj("ICTv13_PROF_TVAH", g_profileDaily.tpoVah, PAL_PROF_TPO, STYLE_DOT, 1, "TPO VAH | ناحیهٔ ارزش زمان‌محور");
         DrawHLineObj("ICTv13_PROF_TVAL", g_profileDaily.tpoVal, PAL_PROF_TPO, STYLE_DOT, 1, "TPO VAL | ناحیهٔ ارزش زمان‌محور");
      }
      if(g_profileDaily.amtValid && g_profileDaily.ibHi>g_profileDaily.ibLo)
      {
         DrawHLineObj("ICTv13_PROF_IBH", g_profileDaily.ibHi, PAL_PROF_IB, STYLE_DOT, 1,
                      StringFormat("Initial Balance High (اولین %d دقیقهٔ روز)", InpProfileIB_Minutes));
         DrawHLineObj("ICTv13_PROF_IBL", g_profileDaily.ibLo, PAL_PROF_IB, STYLE_DOT, 1,
                      StringFormat("Initial Balance Low (اولین %d دقیقهٔ روز) — شکست آن جهت روز را می‌سازد", InpProfileIB_Minutes));
      }
      if(g_profileDaily.hasNakedPoc)
         DrawHLineObj("ICTv13_PROF_NPOC", g_profileDaily.nakedPoc, PAL_PROF_NPOC, STYLE_DASHDOT, 2,
                      StringFormat("Naked/Virgin POC روز %s — از بسته‌شدن آن سشن لمس نشده (آهنربای قیمت)",
                                   TimeToString(g_profileDaily.nakedPocDay,TIME_DATE)));
      if(InpDrawAMTOnChart)
      {
         for(int h=0; h<g_profileDaily.hvnCount; h++)
            DrawHLineObj("ICTv13_PROF_HVN"+IntegerToString(h), g_profileDaily.hvn[h], PAL_PROF_HVN, STYLE_DOT, 1,
                         "HVN (High Volume Node) — گرهٔ پرحجم: قیمت این‌جا وقت/حجم زیاد گذرانده (آهنربا و مانع)");
         for(int l2=0; l2<g_profileDaily.lvnCount; l2++)
            DrawHLineObj("ICTv13_PROF_LVN"+IntegerToString(l2), g_profileDaily.lvn[l2], PAL_PROF_LVN, STYLE_DOT, 1,
                         "LVN (Low Volume Node) — گرهٔ کم‌حجم: عبور قیمت از این‌جا سریع است (مسیر کم‌مقاومت)");
      }
   }
}

// hover فارسی برای خانواده‌های جدید (از BuildExplanation صدا زده می‌شود)
void ExplainWyckoff(const WyckoffObj &w)
{
   g_expTitle="WYCKOFF "+WyckoffEventCode(w.evt)+" #"+IdToStr(w.id);
   ExpAdd("رویداد: "+WyckoffEventFa(w.evt), clrWhite);
   ExpAdd(StringFormat("کندل %s | قیمت %.5f", TimeToString(w.time,TIME_DATE|TIME_MINUTES), w.price), clrWhite);
   ExpAdd(StringFormat("پنجرهٔ رنج تحلیل: %d کندل", InpWyckoffLookbackBars), clrWhite);
   ExpAddWrapped("چرا اهمیت دارد: پول بزرگ با اوج خرید و اوج فروش هیجان را می‌سازد و با اسپرینگ و آپ‌تراست استاپ‌های رنج را می‌شکند؛ برگشت درون رنج با آزمون کم‌دامنه تأیید می‌شود", clrAqua);
   ExpAddWrapped("فاز فعلی تحلیل: "+g_wyckPhaseReason, clrLime);
   ExpAddWrapped("فیک و باطل: اگر بستهٔ کندل بیرون مرز رنج بماند و فقط فتیله نباشد، دیگر اسپرینگ نیست و شکست واقعی است؛ سناریوی رنج باطل می‌شود", clrOrange);
   ExpAddWrapped("کنترل خودت: فتیلهٔ کندل را با کف و سقف رنج مقایسه کن؛ عمق باید بیشتر از آستانهٔ تنظیم‌شده باشد", clrSilver);
   ExpAdd("InpWyckoffSpringATR — آستانهٔ عمق اسپرینگ نسبت به میانگین دامنه", clrSilver);
}

// فاز ۳۳: متن آموزش S&D بازنویسی شد. قبلاً هم نقش الگو در نمایش/چرخهٔ عمر برعکس
// بود (RBD به‌عنوان Demand، DBR به‌عنوان Supply) و هم معنای RBR/RBD/DBD/DBR در
// متن آموزشی گفته نشده بود.
void ExplainSD(const SDObj &z)
{
   string kn=SDKindToStr(z.kind);
   g_expTitle="S/D "+kn+" #"+IdToStr(z.id)+(z.roleSupply? " SUPPLY" : " DEMAND");
   ExpAdd(StringFormat("%s = %s", kn, SDKindFa(z.kind)), clrWhite);
   ExpAdd(StringFormat("بازهٔ ناحیه %.2f تا %.2f | پایان پایه: %s",
          z.bottom, z.top, TimeToString(z.time,TIME_DATE|TIME_MINUTES)), clrWhite);
   ExpAddWrapped("تفکیک ادامه‌دهنده از برگشتی: الگوهای رالی و ریزش ادامهٔ روند پیشین هستند چون قیمت از همان سمت پایه بیرون می‌رود؛ الگوهای برگشتی پایه را در سقف یا کف می‌سازند و خروج مخالف آن است", clrAqua);
   ExpAdd(StringFormat("خروج از پایه شارپ بوده: %.2f برابر میانگین دامنه (حداقل %.2f) — نشانهٔ جذب سفارش نهادی", z.exitMove, InpSD_StrengthATR), clrAqua);
   ExpAdd(StringFormat("نقش فعلی ناحیه: %s", z.roleSupply?"عرضه":"تقاضا"), clrLime);
   if(z.flipped)
      ExpAdd(StringFormat("نقش این ناحیه عوض شده (چرخش) در %s روی قیمت %s و از این لحظه با نقش جدید رهگیری می‌شود",
             TimeToString(z.flipTime,TIME_DATE|TIME_MINUTES), PriceS(z.flipLevel)), clrLime);
   else
      ExpAdd("نقش عوض نشده و ناحیه با همان نقش اولیه رهگیری می‌شود", clrLime);
   ExpAdd(StringFormat("تازگی: %s (%d بار برخورد)",
          (z.state==SDS_FRESH?"دست‌نخورده":(z.state==SDS_TESTED?"آزمون‌شده":(z.state==SDS_FLIPPED?"نقش‌عوض‌شده":"شکسته"))), z.tests), clrLime);
   ExpAdd("دست‌نخورده یعنی بدون برخورد؛ آزمون‌شده یعنی استاپ‌های آن سمت مصرف شده و اعتبار کمتر است", clrSilver);
   // فاز ۳۶: Strength of Zone (امتیاز ترکیبی مستند)
   ExpAdd(StringFormat("قدرت ناحیه: %d از ۵", z.strength),
          z.strength>=4?clrLime:(z.strength==3?clrAqua:clrOrange));
   if(z.strengthText!="") ExpAddWrapped("تفکیک قدرت: "+z.strengthText, z.strength>=4?clrLime:(z.strength==3?clrAqua:clrOrange));
   ExpAdd("معیارهای مستند: خروج شارپ‌تر یعنی قوی‌تر؛ پایهٔ تنگ‌تر یعنی سفارش متراکم‌تر؛ سه تا پنج کندل پایه استاندارد منابع است؛ هم‌زمانی با گپ ضریب تقویت است", clrSilver);
   if(z.tests>=2)
      ExpAddWrapped("هشدار جذب سفارش: این ناحیه چند بار برخورد خورده و هر بار پذیرفته نشده؛ یعنی سفارش مخالف در حال جذب است و نواحی آزمون‌شده ریسک بالاتری دارند", clrOrange);
   ExpAddWrapped("فیک و باطل: بستهٔ قاطع از سمت مقابل نقش، ناحیه را برمی‌گرداند و از آن لحظه با نقش جدید رهگیری می‌شود", clrOrange);
   ExpAddWrapped("اگر قیمت دوباره از سمت مقابل نقش جدید ببندد ناحیه شکسته و بی‌اعتبار است و ورود برعکس روی ناحیهٔ برگشته ریسک بالا دارد", clrTomato);
   ExpAdd(StringFormat("کنترل خودت: پایه را پیدا کن (یک تا %d کندل بستهٔ کم‌دامنه با سقف دامنه کمتر از %.2f برابر میانگین دامنه) و نسبت خروج را خودت اندازه بگیر",
          InpSD_BaseMaxBars, InpSD_BaseMaxRangeATR), clrSilver);
}

// فاز ۳۳: متن آموزشی Al Brooks روی خوانش واقعی همان کندل بازنویسی شد
// (قبلاً «H1 = اولین پولبک» نوشته بود که با تعریف منبع نمی‌خواند) و همهٔ اعداد
// از یک منبع واحد (g_brooksInfo) می‌آید تا پنل با داشبورد ناهمخوان نباشد.
void ExplainBrooks()
{
   g_expTitle="AL BROOKS — PRICE ACTION";
   ExpAdd(StringFormat("نوع کندل جاری: %s",
          g_brooksInfo.isTrendBar? "کندل روند" : (g_brooksInfo.isSignalBar? "کندل سیگنال" : (g_brooksInfo.isDoji? "دوجی یا بدنهٔ کوچک":"عادی"))), clrWhite);
   ExpAdd(StringFormat("آستانهٔ کندل روند: بدنه به دامنه باید %.2f یا بیشتر باشد", InpBrooks_TrendBarRatio), clrWhite);
   ExpAddWrapped(StringFormat("وضعیت جهت همیشگی: %s — این یک حالت است، نه شمارش کندل همرنگ: قیمت نسبت به ۲۰ میانگین متحرک (%.5f) و شیب %d کندلی همان میانگین متحرک سنجیده می‌شود. تا وقتی جهت همیشگی صعودی است، هر پولبک فرصت خرید در جهت است، نه دلیل فروش برعکس",
                 g_brooksInfo.alwaysIn>0? "صعودی" : (g_brooksInfo.alwaysIn<0? "نزولی":"خنثی (بی‌روند)"),
                 g_brooksInfo.ema20, InpBrooks_AI_EMASlopeBars), clrLime);
   ExpAdd(StringFormat("شمارش پولبک: تلاش سقفی %d و تلاش کفی %d در پنجرهٔ %d کندل", g_brooksInfo.hAttempts, g_brooksInfo.lAttempts, InpBrooks_PullbackWindow), clrAqua);
   ExpAddWrapped("تعریف شمارش: نخستین کندلی که سقف کندل قبلی را رد کند تلاش یک است؛ اگر آن تلاش شکست بخورد و قیمت پایین‌تر برود تلاش بعدی شماره دو است و همین‌طور تا چهار (گوه)", clrAqua);
   ExpAdd("پس شماره دو یعنی کف بالاتر نیست، یعنی شمارش تلاش", clrAqua);
   ExpAdd(StringFormat("کندل جاری: کندل ورود %s | کندل سیگنال %s | شکست ناموفق %s",
          g_brooksInfo.isEntryBar?"بله":"خیر", g_brooksInfo.isSignalBar?"بله":"خیر", g_brooksInfo.failedBreakout?"بله":"خیر"), clrWhite);
   ExpAdd("کندل ورود همان کندل روند است که بلافاصله پس از کندل سیگنال می‌آید و کندل سیگنال فقط با بافت معنا دارد: بسته‌شدن نزدیک اکستریم در جهت و پس از یک دامنهٔ مخالف", clrSilver);
   // --- فاز ۳۶: Trading Range / Measured Move / Channel ---
   ExpAddWrapped(g_brooksInfo.inTradingRange
      ? StringFormat("رنج دوطرفه: فعال — مرزها %.2f تا %.2f در %d کندل | میانهٔ رنج %.2f مغناطیس است: تا وقتی قیمت آنجاست انتظار نوسان می‌رود نه روند، و ورود در میانه بدترین جای کار است",
                     g_brooksInfo.trLow, g_brooksInfo.trHigh, g_brooksInfo.trBars, g_brooksInfo.trMid)
      : "رنج دوطرفه: فعلاً تشخیص داده نشد (بازار یک‌سویه یا روند) — شرطش حضور مؤثر هر دو طرف در پنجرهٔ بیست کندلی و نزدیک‌شدن قیمت به هر دو مرز است",
      g_brooksInfo.inTradingRange?clrAqua:clrSilver);
   if(g_brooksInfo.trBreakUp || g_brooksInfo.trBreakDn)
      ExpAddWrapped(StringFormat("شکست مؤثر از رنج: %s — بستهٔ قاطع بیرون مرز؛ در رنجهای دوطرفهٔ تازه اغلب شکست دوم هم ناموفق است، پس انتظار برگشت به مرز دیگر را داشته باش",
                    g_brooksInfo.trBreakUp?"رو به بالا":"رو به پایین"), clrLime);
   if(g_brooksInfo.trFailedBreakUp || g_brooksInfo.trFailedBreakDn)
      ExpAdd(StringFormat("شکست ناموفق: %s — فتیله از مرز بیرون رفت ولی کندل داخل رنج بست؛ شکست ناموفق اغلب حرکت مخالف می‌سازد",
                    g_brooksInfo.trFailedBreakUp?"سقف رنج":"کف رنج"), clrOrange);
   ExpAddWrapped(g_brooksInfo.mmValid
      ? StringFormat("حرکت اندازه‌گیری‌شده: نقطهٔ آغاز %.2f، اوج میانی %.2f، پولبک %.2f و هدف %.2f که صد درصد امتداد نخستین دامنه است؛ دامنهٔ دوم که اندازهٔ دامنهٔ اول را تکرار کند هدف محاسبه‌پذیر می‌دهد",
                     g_brooksInfo.mmA, g_brooksInfo.mmB, g_brooksInfo.mmC, g_brooksInfo.mmD)
      : "حرکت اندازه‌گیری‌شده: فعلاً الگوی معتبری یافت نشد — سه پیوت تأییدشده با پولبک بین دو دامنه لازم است",
      g_brooksInfo.mmValid?clrLime:clrSilver);
   ExpAddWrapped(g_brooksInfo.chSlope!=0
      ? StringFormat("کانال: سوگیری %s و قیمت %s میانگین متحرک بیست دوره (%.5f)؛ خط کانال موازی خط روند و هدف یا مغناطیس بعدی حرکت است و کانال تند اغلب با شکست به سمت مخالف پایان می‌یابد",
                     g_brooksInfo.chSlope>0?"صعودی":"نزولی", g_brooksInfo.chSlope>0?"بالای":"زیر", g_brooksInfo.ema20)
      : "کانال: شیب قابل‌توجهی تشخیص داده نشد (جهت همیشگی خنثی یا قیمت چسبیده به میانگین متحرک)",
      g_brooksInfo.chSlope!=0?clrAqua:clrSilver);
   ExpAddWrapped("فیک و باطل: اگر شکست فقط با فتیله باشد و کندل داخل ببندد شکست ناموفق است و اغلب حرکت مخالف می‌سازد؛ و اگر جهت همیشگی خنثی شود و قیمت دو طرف میانگین متحرک سرگردان باشد شمارش تلاش‌ها اعتباری ندارد", clrOrange);
   ExpAdd(StringFormat("کنترل خودت: بدنه به دامنه را با %.2f و نسبت فتیله را با %.2f مقایسه کن؛ برای کندل دوجی آستانهٔ بدنه %.2f است",
          InpBrooks_TrendBarRatio, InpBrooks_TailMaxRatio, InpBrooks_DojiBodyRatio), clrSilver);
}

// فاز ۳۴: توضیح فارسی مخصوص هر رویداد RTM (کلیک روی خود آبجکت، نه فقط خلاصه)
void ExplainRTMEvent(const RTMObj &e)
{
   g_expTitle="RTM "+RTMEventCode(e.evt)+" #"+IdToStr(e.id);
   ExpAdd(StringFormat("چیست: %s — کندل %s · قیمت محوری %s",
          RTMEventFa(e.evt), TimeToString(e.time,TIME_DATE|TIME_MINUTES), PriceS(e.price)), clrWhite);
   ExpAddWrapped("چرا شکل گرفت: "+e.note, clrAqua);
   ExpAddWrapped(StringFormat("محدودهٔ رویداد: %s تا %s — جهت: %s",
                 PriceS(e.bottom), PriceS(e.top), e.dir>0?"صعودی":(e.dir<0?"نزولی":"خنثی (جعبهٔ فشر‌دگی)")), clrWhite);
   if(e.evt==RTM_TRAP)
      ExpAddWrapped("درست و فیک: درست آن است که قیمت بعد از تله در جهت مخالف فتیله ادامه دهد و از انتهای مخالف بسته شود؛ فیک برگشت فوری به داخل و بسته‌شدن آن‌طرف جعبه با کندل مخالف است", clrLime);
   else if(e.evt==RTM_EXPANSION)
      ExpAddWrapped("درست و فیک: درست آن است که حرکت در همان جهت ادامه دهد و قیمت بیرون جعبه بماند؛ فیک برگشت سریع به داخل جعبه است (انبساط کاذب)", clrLime);
   else if(e.evt==RTM_MOMENTUM)
      ExpAddWrapped("درست و فیک: درست آن است که کندل بعد در جهت ممنتوم ببندد (تداوم حرکت)؛ فیک کندلی است که کل دامنهٔ ممنتوم را پس بدهد", clrLime);
   else if(e.evt==RTM_ENGULF)
      ExpAddWrapped("درست و فیک: پوشش بدنه باید در انتهای یک حرکت مخالف رخ دهد؛ اگر وسط رنج باشد صرفاً نوسان است", clrLime);
   else if(e.evt==RTM_REJECTION)
      ExpAddWrapped("درست و فیک: رد واقعی وقتی است که قیمت به قیمت‌های سطح قبلی‌تر برنگردد؛ اگر چند کندل بعد سطح دوباره آزمون و بازدید شود، رد ناتمام است", clrLime);
   else
      ExpAddWrapped("درست و فیک: فشر‌دگی فقط کاهش دامنه است؛ تا انبساط جهت‌دار نیاید معاملهٔ فشر‌دگی بی‌جهت است", clrLime);
   ExpAdd(StringFormat("کنترل خودت: فشر‌دگی با میانگین دامنهٔ کمتر از %.2f برابر روی %d کندل | ممنتوم با دامنهٔ %.2f برابر و بدنهٔ %.0f درصد | فتیلهٔ رد %.0f درصد",
          InpRTM_CompressRangeATR, InpRTM_CompressBars, InpRTM_MomentumATR,
          InpRTM_MomentumBody*100.0, InpRTM_RejectTailRatio*100.0), clrSilver);
}

void ExplainRTM()
{
   g_expTitle="RTM — READ THE MARKET";
   ExpAdd(StringFormat("چیست: چرخهٔ فشر‌دگی و انبساط و رویدادهای رفتاری درون آن؛ فشر‌دگی یعنی میانگین دامنهٔ %d کندل کمتر از %.2f برابر میانگین دامنه (انرژی ذخیره‌شده)",
          InpRTM_CompressBars, InpRTM_CompressRangeATR), clrWhite);
   ExpAdd("وضعیت فعلی: "+(g_rtmNote==""? "هیچ فشر‌دگی فعالی نیست":g_rtmNote), clrAqua);
   ExpAdd(StringFormat("رویدادهای رهگیری‌شده در رجیستری: %d مورد — فشر‌دگی و انبساط، تله (فتیله بیرون جعبه و بسته داخل)، ممنتوم، پوشش بدنه و پس‌زدگی", ArraySize(g_rtm)), clrLime);
   ExpAdd(StringFormat("آستانه‌ها: ممنتوم با دامنهٔ %.2f برابر میانگین دامنه و بدنهٔ %.0f درصد | پس‌زدگی با فتیلهٔ %.0f درصد دامنه و بسته‌شدن در ثلث مخالف", InpRTM_MomentumATR, InpRTM_MomentumBody*100.0, InpRTM_RejectTailRatio*100.0), clrSilver);
   if(ArraySize(g_rtm)>0)
   {
      RTMObj last=g_rtm[ArraySize(g_rtm)-1];
      ExpAdd(StringFormat("آخرین رویداد: %s در %s", RTMEventFa(last.evt),
             TimeToString(last.time,TIME_DATE|TIME_MINUTES)), clrWhite);
      ExpAddWrapped(last.note, clrWhite);
   }
   ExpAddWrapped("نحوهٔ استفاده: ورود پس از انبساط در جهت آن، یا پس از تله در جهت مخالف فتیله؛ پوشش بدنه و پس‌زدگی تأییدکننده‌اند نه دلیل ورود — و اگر قیمت از انتهای مخالف جعبهٔ فشر‌دگی بسته شود سناریو باطل است", clrLime);
   ExpAddWrapped("فیک و باطل: انبساط بدون جهت مشخص یا کندلی که فتیلهٔ تله را بزند ولی بیرون همان جعبه ببندد تلهٔ واقعی نیست؛ فشر‌دگی هم بدون انبساط نویز است", clrOrange);
   ExpAdd(StringFormat("کنترل خودت: میانگین دامنهٔ %d کندل را با %.2f برابر میانگین دامنه و نسبت بدنه به دامنه را با %.2f مقایسه کن",
          InpRTM_CompressBars, InpRTM_CompressRangeATR, InpRTM_MomentumBody), clrSilver);
}

void ExplainProfile()
{
   g_expTitle="MARKET / VOLUME PROFILE + AMT";
   if(!g_profileDaily.valid){ ExpAddWrapped("پروفایل هنوز ساخته نشده", clrOrange); return; }
   ExpAdd(StringFormat("چیست: توزیع حجم روی ردیف‌های قیمتی از %d کندل اخیر", InpProfileLookbackBars), clrWhite);
   ExpAdd(StringFormat("قیمت با بیشترین حجم %.2f | سقف محدودهٔ ارزش %.2f | کف محدودهٔ ارزش %.2f",
          g_profileDaily.poc, g_profileDaily.vah, g_profileDaily.val), clrWhite);
   // ---------- فاز ۳۴: Auction Market Theory ----------
   if(g_profileDaily.tpoValid)
      ExpAdd(StringFormat("توضیح زمان‌محور: قیمت با بیشترین زمان %.2f | محدودهٔ ارزش زمانی %.2f تا %.2f",
             g_profileDaily.tpoPoc, g_profileDaily.tpoVah, g_profileDaily.tpoVal), clrAqua);
      ExpAdd("این عدد از شمارش زمان در هر ردیف می‌آید نه از حجم؛ پس تفاوت آن با قیمت پرحجم عیب نیست و دو ابزار متفاوت است", clrSilver);
   if(g_profileDaily.amtValid)
   {
      ExpAdd(StringFormat("ارزش اولیه: نخستین %d دقیقهٔ روز از %.2f تا %.2f",
             InpProfileIB_Minutes, g_profileDaily.ibLo, g_profileDaily.ibHi), clrMagenta);
      ExpAdd("شکست یک‌طرفهٔ ارزش اولیه همراه با نبود بازگشت روز روندی می‌سازد و برگشت به داخل روز خنثی", clrMagenta);
      ExpAdd(StringFormat("نوع روز: %s | نوع باز شدن: %s", AMTDayTypeFa(g_profileDaily.dayType), AMTOpenTypeFa(g_profileDaily.openType)), clrLime);
      ExpAdd(StringFormat("وضعیت بازار: %s", g_profileDaily.balanceNote), clrLime);
      ExpAdd(StringFormat("باز شدن روز %.5f | بسته شدن روز %.5f | کف و سقف روز %.5f تا %.5f",
             g_profileDaily.dayOpen, g_profileDaily.dayClose, g_profileDaily.dayLo, g_profileDaily.dayHi), clrLime);
      if(g_profileDaily.hasNakedPoc)
         ExpAdd(StringFormat("قیمت پرحجم لمس‌نشده: %.2f از روز %s — این سطح از بسته شدن آن سشن تا الان لمس نشده و رفتار آهنربایی دارد؛ ورود برعکس درست روی آن پرریسک است",
                g_profileDaily.nakedPoc, TimeToString(g_profileDaily.nakedPocDay,TIME_DATE)), clrTomato);
   }
   ExpAdd(StringFormat("گره‌های پرحجم و کم‌حجم: %d و %d — گرهٔ پرحجم جایی است که بازار وقت زیادی گذرانده (مانع و آهنربا) و گرهٔ کم‌حجم جایی که سریع عبور کرده (مسیر کم‌مقاومت)",
          g_profileDaily.hvnCount, g_profileDaily.lvnCount), clrAqua);
   ExpAdd(StringFormat("آستانه‌ها: گرهٔ پرحجم با نسبت %.2f و بیشتر و گرهٔ کم‌حجم با نسبت %.2f و کمتر از میانگین ردیف‌ها", InpProfileHVN_Ratio, InpProfileLVN_Ratio), clrSilver);
   ExpAddWrapped("فیک و باطل: هر سه سطح (ارزش اولیه، محدودهٔ ارزش و گرهٔ پرحجم) با شکست و پذیرش یعنی بسته‌شدن بیرون بی‌اعتبار می‌شوند؛ اگر قیمت فقط فتیله بزند و داخل ببندد سطح هنوز معتبر است", clrOrange);
   ExpAdd(StringFormat("حجم کل پنجره: %d تیک — صادقانه: کلاینت فقط حجم تیکی می‌دهد، پس این تقریب است نه حجم واقعی معاملات", g_profileDaily.totalVol), clrOrange);
   ExpAddWrapped("چرا اهمیت دارد: قیمت پرحجم همان قیمت منصفانه است؛ ماندن قیمت داخل محدودهٔ ارزش یعنی پذیرش و خروج قوی از آن یعنی پس‌زدگی و آغاز روند", clrLime);
   ExpAddWrapped("فیک و باطل: برخورد لحظه‌ای به سقف یا کف محدودهٔ ارزش معنای رد ندارد؛ بازگشت سریع به داخل محدوده خرابیِ شکست است", clrOrange);
   ExpAdd(StringFormat("کنترل خودت: ردیف‌ها را با آستانهٔ درصد پوشش محدودهٔ ارزش بازبینی کن — مقدار فعلی %.1f درصد", InpProfileVA_Percent), clrSilver);
   ExpAdd("InpProfileVA_Percent — کلید درصد پوشش محدودهٔ ارزش", clrSilver);
}
// ---------- فاز ۳۶: لایهٔ Brooks Range/Measured Move (فقط وقتی فعال) ----------
// رنج دوطرفه با دو مرز + خط مغناطیس ۵۰٪ و هدف Measured Move (D). همه با یک
// آبجکت برای هر چیز و فقط وقتی گزینه روشن است — چارت پیش‌فرض تمیز می‌ماند.
void DrawBrooksRangeLayer()
{
   if(!InpEnableBrooksRange || !g_brooksInfo.inTradingRange) return;
   datetime t1=g_lastContextBarTime;
   if(t1<=0) return;
   datetime t2=(datetime)((long)t1+(long)PeriodSeconds(PERIOD_CURRENT)*MathMax(1,InpZoneExtendBars)*4);
   DrawBoxObj("ICTv13_BROOKS_TR", t1, g_brooksInfo.trHigh, t2, g_brooksInfo.trLow, PAL_BROOKS_TR, false, true, STYLE_DOT, 1,
              StringFormat("BROOKS TRADING RANGE | %.2f - %.2f | هر دو سناریوی صعودی و نزولی زنده است | وسط رنج (%.2f) مغناطیس است و شکست اغلب ناموفق می‌ماند",
                           g_brooksInfo.trLow, g_brooksInfo.trHigh, g_brooksInfo.trMid));
   DrawHLineObj("ICTv13_BROOKS_TRMID", g_brooksInfo.trMid, PAL_BROOKS_TRMID, STYLE_DOT, 1,
                StringFormat("BROOKS RANGE MID | نیمهٔ رنج (مغناطیس) = %.2f", g_brooksInfo.trMid));
   if(g_brooksInfo.mmValid)
      DrawHLineObj("ICTv13_BROOKS_MM", g_brooksInfo.mmD, PAL_BROOKS_MM, STYLE_DASHDOT, 1,
                   StringFormat("BROOKS MEASURED MOVE | D = %.2f | A = %.2f | B = %.2f | C = %.2f | هدف نهایی، صد درصد امتداد لگ اول",
                                g_brooksInfo.mmD, g_brooksInfo.mmA, g_brooksInfo.mmB, g_brooksInfo.mmC));
}

// ---------- فاز ۳۶: لایهٔ Quarterly Theory ----------
// فقط دو خط: True Open روز (نیمه‌شب نیویورک) و True Open هفته (دوشنبه نیویورک).
// ربع‌ها در داشبورد و پنل توضیح هستند تا چارت شلوغ نشود. هیچ سیگنالی نیست:
// QT یک «زمان‌بند» است، نه سیگنال (منبع: صریحاً در همان مقاله).
void DrawQTLayer()
{
   if(!InpEnableQT || !InpDrawQTOpens) return;
   datetime t1=g_lastContextBarTime;
   if(t1<=0) return;
   datetime t2=(datetime)((long)t1+(long)PeriodSeconds(PERIOD_CURRENT)*MathMax(1,InpZoneExtendBars)*6);
   if(g_qtDayTrueOpen>0.0 && g_qtDayTrueOpenT>0)
   {
      string nm="ICTv13_QT_DAYOPEN";
      DrawHLineObj(nm,g_qtDayTrueOpen,PAL_QT_DAY,STYLE_DASHDOT,1,
         StringFormat("QUARTERLY THEORY | باز شدن واقعی روز (نیمه‌شب نیویورک) = %s از %s | قیمت زیر آن ناحیهٔ ارزان برای خرید است و بالای آن ناحیهٔ گران برای فروش؛ این همان باز شدن ربع دوم است",
                      DoubleToString(g_qtDayTrueOpen,_Digits), TimeToString(g_qtDayTrueOpenT,TIME_DATE)));
   }
   if(g_qtWkTrueOpen>0.0 && g_qtWkTrueOpenT>0)
   {
      string nm="ICTv13_QT_WKOPEN";
      DrawHLineObj(nm,g_qtWkTrueOpen,PAL_QT_WEEK,STYLE_DASHDOT,1,
         StringFormat("QUARTERLY THEORY | باز شدن واقعی هفته (دوشنبه نیمه‌شب نیویورک) = %s | مرجع ناحیهٔ گران و ارزان هفتگی", DoubleToString(g_qtWkTrueOpen,_Digits)));
   }
}

string QTPhaseToStr(ENUM_QT_PHASE p)
{
   switch(p)
   {
      case QT_Q1_ACCUM:   return "Q1 ACCUMULATION (18:00-00:00 NY)";
      case QT_Q2_MANIP:   return "Q2 MANIPULATION (00:00-06:00 NY)";
      case QT_Q3_DISTRIB: return "Q3 DISTRIBUTION (06:00-12:00 NY)";
      case QT_Q4_REVERSAL:return "Q4 CONTINUATION/REVERSAL (12:00-18:00 NY)";
   }
   return "—";
}

// پنل آموزشی Quarterly Theory (کلیک روی خطوط True Open یا آبجکت QT_)
void ExplainQT(bool week)
{
   g_expTitle=week? "QUARTERLY THEORY — WEEK" : "QUARTERLY THEORY — DAY";
   ExpAddWrapped("چیست: هر چرخهٔ زمانی به چهار ربع تقسیم می‌شود و انتظار می‌رود قالب انباشت، دستکاری، توزیع و ادامه یا برگشت در هر ربع تکرار شود", clrWhite);
   ExpAdd("قالب ربع‌ها: ربع نخست انباشت با رنج تنگ، ربع دوم دستکاری با جارو، ربع سوم توزیع با حرکت انبساطی، و ربع چهارم ادامه یا برگشت", clrAqua);
   ExpAdd("Source: arongroups — Quarterly Theory", clrSilver);
   if(!week)
   {
      ExpAdd("ربع فعلی روز: "+QTPhaseFa(g_qtDayPhase), clrLime);
      ExpAddWrapped(g_qtDayTrueOpen>0.0
         ? StringFormat("باز شدن واقعی روز %.5f — همان کندل ساعت صفر نیویورک؛ قاعده: خرید زیر آن (نیمهٔ ارزان) و فروش بالای آن (نیمهٔ گران) ترجیح دارد", g_qtDayTrueOpen)
         : "باز شدن واقعی روز هنوز ثبت نشده است", g_qtDayTrueOpen>0.0?clrAqua:clrOrange);
      ExpAddWrapped("درست و فیک: جارو شدن رنج ربع نخست در ربع دوم سیگنال اصلی است؛ اگر جارویی نبود چرخه طبق قالب نرفته", clrLime);
      ExpAdd("در هیچ حالتی الزامی به معامله نیست — این ابزار زمان‌بند است نه سیگنال", clrLime);
      ExpAdd("ربع فعلی هفته: "+QTPhaseFa(g_qtWeekPhase), clrAqua);
      ExpAddWrapped("روایت رایج هفته: دوشنبه ربع نخست، سه‌شنبه ربع دوم، چهارشنبه ربع سوم و پنج‌شنبه و جمعه ربع چهارم؛ برخی منابع جمعه را از شمارش بیرون می‌دانند", clrSilver);
   }
   else
   {
      ExpAddWrapped(g_qtWkTrueOpen>0.0
         ? StringFormat("باز شدن واقعی هفته %.5f — نخستین کندل دوشنبه پس از نیمه‌شب نیویورک؛ مرجع نیمهٔ گران و ارزان هفتگی", g_qtWkTrueOpen)
         : "باز شدن واقعی هفته هنوز ثبت نشده است", g_qtWkTrueOpen>0.0?clrAqua:clrOrange);
      ExpAddWrapped("نکتهٔ صادقانه: روایت‌های متفاوتی از شمارش هفته وجود دارد و این ابزار روایت اصلی را نشان می‌دهد و همان را صریح می‌گوید", clrSilver);
   }
   ExpAddWrapped("اتصال به بقیهٔ سیستم: ربع دوم نیویورک همان پنجرهٔ جاروی لندن است و ربع سوم همان پنجرهٔ نیویورک؛ پس جارویی که این سیستم در آن پنجره‌ها ثبت می‌کند دقیقاً همان رویداد ربع دوم است — دو نام برای یک رویداد، نه دو محاسبه", clrAqua);
   ExpAddWrapped("کنترل خودت: ساعت نیویورک را از داشبورد بخوان؛ ربع فعلی باید با ساعت هم‌خوان باشد و خط باز شدن واقعی باید روی بازِ کندل نیمه‌شب نیویورک باشد", clrSilver);
}

void DrawPhase12Layer()
{
   if(!InpEnablePhase12) return;
   if(InpDetectTrendlineLiq && InpDrawTrendlines)
   {
      for(int i=0;i<ArraySize(g_trendlines);i++)
      {
         if(g_trendlines[i].invalidated) continue;
         string nm="ICTv13_TRENDLINE_"+IdToStr(g_trendlines[i].id);
         datetime t2=g_trendlines[i].t2;
         int extend=MathMax(1,InpZoneExtendBars);
         datetime t1=(datetime)((long)g_lastContextBarTime+(long)PeriodSeconds(PERIOD_CURRENT)*extend);
         if(t1<=t2) t1=(datetime)((long)t2+(long)PeriodSeconds(PERIOD_CURRENT)*extend);
         double p1=TrendlinePriceAt(g_trendlines[i],t1);
         double p2=TrendlinePriceAt(g_trendlines[i],t2);
         if(p1<=0.0 || p2<=0.0) continue;
         if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_TREND,0,t2,p2,t1,p1);
         ObjectSetInteger(0,nm,OBJPROP_TIME,0,t2);  ObjectSetDouble(0,nm,OBJPROP_PRICE,0,p2);
         ObjectSetInteger(0,nm,OBJPROP_TIME,1,t1);  ObjectSetDouble(0,nm,OBJPROP_PRICE,1,p1);
         ObjectSetInteger(0,nm,OBJPROP_COLOR,g_trendlines[i].isHigh?PAL_LIQ_HIGH:PAL_LIQ_LOW);
         // فاز ۳۰: خطی که نقدینگی‌اش جارو شده دیگر هدف نیست ولی حذف نمی‌شود
         // (تاریخچهٔ آموزش)؛ فقط خط‌چین نمایش داده می‌شود تا با خط زنده قاطی نشود.
         ObjectSetInteger(0,nm,OBJPROP_STYLE,g_trendlines[i].swept?STYLE_DASH:STYLE_DOT);
         ObjectSetInteger(0,nm,OBJPROP_WIDTH,1);
         ObjectSetInteger(0,nm,OBJPROP_RAY_RIGHT,false);
         ObjectSetString(0,nm,OBJPROP_TOOLTIP,"\n");
         MarkDrawnLayerObj(nm);
      }
   }
   POIObj bp;
   if(InpDrawBestPOI && FindBestPOI(DIR_NONE, bp) && bp.top>bp.bottom)
   {
      string nm="ICTv13_POI_BEST";
      int extend=MathMax(1,InpZoneExtendBars);
      // فاز ۴۸: باکس POI برتر، «برجسته‌سازی» است نه یک خانوادهٔ تازه. رنگش را از
      // خود جهت می‌گیرد (همان دو ورودی کاربر)، چون یک باکس POI بدون جهت معنا ندارد؛
      // پیش‌تر DeepSkyBlue/OrangeRed بود که با اردربلاک بریکر و گپ نزولی قاطی می‌شد.
      DrawBoxObj(nm, bp.time, bp.top,
                 (datetime)((long)bp.time+(long)PeriodSeconds(PERIOD_CURRENT)*extend), bp.bottom,
                 bp.direction==DIR_BULL?InpColorBull:InpColorBear, false, true, STYLE_DOT, 1,
                 "POI "+PoiKindToStr(bp.kind));
   }
}

void RedrawChartObjects()
{
   // فاز ۱۴: کل لایه دیگه پاک نمی‌شود. فقط مجموعهٔ «رسم‌شدهٔ این pass» صفر
   // می‌شود و در پایان ReconcileChartLayer تصمیم می‌گیرد چه چیزی زنده، چه چیزی
   // حذف (لایهٔ خاموش/فیلتر صریح) و چه چیزی frozen (خارج از سقف نمایش) است.
   PurgeFrozenOnContextChange();
   ResetPassDrawSet();

   g_htfEventsDrawn=0;
   if(InpDrawStructureEvents)
   {
      int drawn=0;
      for(int i=ArraySize(g_events)-1; i>=0 && drawn<InpMaxDrawnZones; i--)
      {
         if(g_events[i].isHTF) continue;
         DrawStructureEvent(g_events[i]);
         drawn++;
      }
   }
   // فاز ۱۵: رویداد ساختاری HTF پیش از این **هیچ آبجکتی** نداشت؛ کامنت قدیمی
   // می‌گفت «HTF روی لایهٔ MTF نمایش داده می‌شود»، ولی DrawMTFLayer فقط سقف/کف
   // محافظت‌شده را می‌کشد. یک BOS/CHoCH روی H4 فقط در داشبورد دیده می‌شد.
   if(InpDrawHTFEvents)
   {
      int drawnH=0;
      for(int i=ArraySize(g_events)-1; i>=0 && drawnH<InpMaxDrawnHTFEvents; i--)
      {
         if(!g_events[i].isHTF) continue;
         DrawStructureEvent(g_events[i]);
         drawnH++;
      }
      g_htfEventsDrawn=drawnH;
   }
   DrawZoneLayer();
   if(InpDrawLiquidity)     DrawLiquidityLayer();
   if(InpDrawSweepMarkers)  DrawSweepLayer();
   DrawSessionLayer();
   DrawMTFLayer();
   DrawSetupLayer();
   DrawQTLayer();   // فاز ۳۶: True Open روز/هفته (Quarterly Theory)
   DrawBrooksRangeLayer();   // فاز ۳۶: Trading Range + Measured Move
   if(g_leg.valid && InpDrawSetupBox) DrawLocationLevels();  // EQ/OTE/Golden فقط با باکس ستاپ (همان خانوادهٔ تصمیم ورود)
   DrawDOLLine();
   DrawReversalLevels();
   DrawPhase12Layer();
   DrawFamiliesLayer();   // فازهای ۱۶–۲۱

   // فاز ۱۴: آشتی — آبجکت‌های رسم‌شده در همین pass تازه شدند، بقیه با سبک frozen
   // نگه داشته یا (اگر لایه/ فیلتر خاموش باشد) حذف می‌شوند. هیچ ناحیه‌ای دیگر
   // با پر شدن سقف نمایش ناپدید نمی‌شود.
   ReconcileChartLayer();
   ChartRedraw(0);

   if(InpLogPhase14OnRedraw)
      PrintFormat("ICT PHASE14 | layer objs %d | drew %d | frozen %d (added %d / restored %d / evicted %d) | hidden-deleted %d | dash rows %d | dash width %d",
                  g_rcLayerObjects, g_rcDrawn, g_rcFrozen,
                  (int)g_frozenAdded, (int)g_frozenRestored, (int)g_frozenEvicted,
                  (int)g_hiddenDeleted, g_dashRows, g_dashWidth);

   // ------------------------------------------------------------------
   // فاز ۲۲ — ایراد واقعی «هیچ‌چیزم نمی‌نویسد»:
   // قبلاً همین‌جا (بی هیچ شرطی) در هر pass رسم، ``g_expHovered=""`` و خطوط پاک
   // می‌شدند و RenderExplainPanel با total==0 همهٔ ردیف‌های EDIT پنل را حذف
   // می‌کرد. RedrawChartObjects دقیقاً یک‌بار در هر **کندل بسته** و یک‌بار در پایان
   // بازسازی تاریخچه اجرا می‌شود (نه هر tick)؛ یعنی روی M1 هر ۶۰ ثانیه و بعد از
   // هر rebuild، پنل نابود می‌شد. حالا فقط وقتی آبجکتِ زیر موس دیگر روی چارت
   // نیست پنل بسته می‌شود؛ در غیر این صورت دست‌نخورده می‌ماند تا کاربر توضیح
   // را بخواند.
   // ------------------------------------------------------------------
   if(g_expHovered!="" && ObjectFind(0,g_expHovered)<0)
   {
      g_expHovered="";
      ExpClear();
      RenderExplainPanel();
   }
   if(InpWriteExplainCsv || InpSetObjectTooltips) ExplainSaveCsv();
   else ExplainClearStaleTooltips();
   if(InpWriteExplainCsv) PersistFVGDictionary();
   if(InpWriteExplainCsv) PersistLegDictionary();
}

// فاز ۱۴: شاهد عددی برای دو معیار پذیرش این فاز:
//   ۱) «تاریخچهٔ رسم‌شده با پر شدن سقف‌های نمایش ناپدید نمی‌شود»
//      → ستون‌های LayerDrawn / FrozenLive / FrozenAdded / FrozenRestored / FrozenEvicted
//   ۲) «هیچ متن بریده/کهنه/روی‌هم‌افتاده‌ای در داشبورد نمی‌ماند»
//      → ستون‌های DashRows / DashWidth / DashMaxRowW / DashStaleDeleted / DashWrappedRows / DashOverflowRows
// روی هر کندل بسته یا با تغییر هر یک از این اعداد یک ردیف می‌گیرد.
void PersistPhase14Diagnostics()
{
   if(!InpWritePhase14Diagnostics) return;
   datetime barTime=g_lastContextBarTime;
   static datetime lastBar=0;
   static long     lastHash=-1;
   // فاز ۲۴ (کارایی): این تابع هر tick صدا زده می‌شود. قبلاً هر tick هشت
   // IntegerToString و هفت پیوند رشته می‌ساخت (تخصیص حافظه در مسیر داغ) فقط
   // برای مقایسه. حالا اول یک درهم‌ساز عددی ارزان مقایسه می‌شود؛ رشته و فایل
   // فقط وقتی واقعاً تغییری رخ داده ساخته می‌شوند.
   long sig=0;
   sig=sig*131L+g_rcLayerObjects; sig=sig*131L+g_rcDrawn;  sig=sig*131L+g_rcFrozen;
   sig=sig*131L+g_dashRows;       sig=sig*131L+g_dashWidth; sig=sig*131L+g_dashStale;
   sig=sig*131L+g_dashWrapped;    sig=sig*131L+g_dashOverflow;
   if(barTime==lastBar && sig==lastHash) return;
   lastBar=barTime; lastHash=sig;

   int h=FileOpen("ICT_Assistant_Canonical_Phase14_Diag.csv",FILE_COMMON|FILE_READ|FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_SHARE_WRITE,';');
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0)
      FileWrite(h,"BarTime","BuildStamp","Symbol","Period",
                "LayerObjects","LayerDrawn","FrozenLive","FrozenAdded","FrozenRestored","FrozenEvicted","HiddenDeleted",
                "FrozenHistoryEnabled","MaxFrozenObjects",
                "DashRows","DashWidth","DashHeight","DashMaxRowW","DashStaleDeleted","DashWrappedRows","DashOverflowRows",
                "MaxDrawnZones","MaxDrawnLevels");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,
             TimeToString(barTime,TIME_DATE|TIME_MINUTES),
             g_buildStamp, _Symbol, EnumToString((ENUM_TIMEFRAMES)Period()),
             g_rcLayerObjects, g_rcDrawn, g_rcFrozen,
             (int)g_frozenAdded, (int)g_frozenRestored, (int)g_frozenEvicted, (int)g_hiddenDeleted,
             InpFrozenHistoryEnabled?"true":"false", InpMaxFrozenObjects,
             g_dashRows, g_dashWidth, g_dashHeight, g_dashMaxRowW, g_dashStale, g_dashWrapped, g_dashOverflow,
             InpMaxDrawnZones, InpMaxDrawnLevels);
   FileClose(h);
}

