//====================================================================
// SETUP ENGINE — رفع ایراد ۱۶ (پیش‌نیاز Dashboard واقعی): از روی
// زنجیره واقعی Sweep->MSS->Displacement->FVG->OB تصمیم می‌گیرد، نه
// جدا از Core.
//====================================================================
// ناحیهٔ ورود روی تایم‌فریم SETUP (پیش‌فرض M5) — #۶۶ بند ۴:
// قبلاً ناحیه همیشه از تایم‌فریم چارت انتخاب می‌شد (مثلاً M15) درحالی‌که
// نقش SETUP در زنجیرهٔ MTF مال M5 است و ریزترین ناحیه هم همان‌جاست.
// الگو: FVG سه‌کندلی استاندارد؛ ناحیه‌ای که از سمت مخالف بسته شده باشد
// (کاملاً رد شده) دیگر معتبر نیست.
bool FindSetupTFZone(datetime asOfBarTime, ENUM_DIRECTION dir,
                     double &top, double &bottom, datetime &zoneTime)
{
   top=0; bottom=0; zoneTime=0;
   if(dir==DIR_NONE) return false;
   if(g_mtfTimeframes[3]==PERIOD_CURRENT) return false;   // همان تایم‌فریم چارت است؛ ناحیهٔ جدا لازم نیست

   MqlRates r5[];
   int copied=CopyRatesAsOf(_Symbol, g_mtfTimeframes[3], asOfBarTime, 150, r5);
   if(copied<10) return false;

   for(int i=0;i+2<copied;i++)   // i = کندل سوم الگو، i+2 = کندل اول، i+1 = کندل میانی
   {
      if(r5[i].time>=asOfBarTime) continue;   // فقط کندل بسته‌شدهٔ همان بازه
      double zTop=0, zBot=0;
      if(dir==DIR_BULL)
      {
         if(!(r5[i].low > r5[i+2].high)) continue;
         zTop=r5[i].low; zBot=r5[i+2].high;
         bool closedThrough=false;
         for(int j=0;j<i;j++) if(r5[j].close < zBot) { closedThrough=true; break; }
         if(closedThrough) continue;
      }
      else
      {
         if(!(r5[i].high < r5[i+2].low)) continue;
         zTop=r5[i+2].low; zBot=r5[i].high;
         bool closedThrough=false;
         for(int j=0;j<i;j++) if(r5[j].close > zTop) { closedThrough=true; break; }
         if(closedThrough) continue;
      }
      if(zTop-zBot <= PointsToPrice(1)) continue;
      top=zTop; bottom=zBot; zoneTime=r5[i].time;
      return true;
   }
   return false;
}

//====================================================================
// PHASE 15 — چرخهٔ عمر ستاپ (#۶۶): ابطال با عبور بستهٔ قیمت از SL
//====================================================================
// پیش از این، وضعیت ستاپ فقط «لحظه‌ای» بود: UpdateSetup هر کندل از صفر ساخته
// می‌شد و هیچ‌جا ثبت نمی‌شد که ستاپ آمادهٔ قبلی با عبور قیمت از SL باطل شده است.
// این یک ماشین حالت *قطعی* است که به ترتیب کندل‌ها اجرا می‌شود (در بازسازی
// تاریخچه هم همان ترتیب طی می‌شود)، پس نتیجه در full و incremental یکسان است.
string SessionShortStr()
{
   switch(g_currentSession)
   {
      case SESS_ASIA:         return "ASIA";
      case SESS_LONDON:       return "LONDON";
      case SESS_NY_AM:        return "NY_AM";
      case SESS_LONDON_CLOSE: return "LONDON_CLOSE";
      case SESS_NY_PM:        return "NY_PM";
      default:                return "NONE";
   }
}

void PersistSetupLifecycleEvent(string state, datetime t, double price)
{
   int h=FileOpen("ICT_Assistant_Canonical_SetupLifecycle.csv",FILE_COMMON|FILE_READ|FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_SHARE_WRITE,';');
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0)
      FileWrite(h,"EventTime","BuildStamp","Event","Dir","Entry","SL","TP1","Price","ChainEventId","Reason");
   FileSeek(h,0,SEEK_END);
   FileWrite(h, TimeToString(t,TIME_DATE|TIME_MINUTES), g_buildStamp, state, DirToStr(g_setupLifeDir),
             DoubleToString(g_setupLifeEntry,_Digits), DoubleToString(g_setupLifeSL,_Digits),
             DoubleToString(g_setupLifeTP1,_Digits), DoubleToString(price,_Digits),
             IdToStr(g_setupLifeChainId), g_setupLifeReason);
   FileClose(h);
}

// سنجش ستاپ مسلح با کندل *بستهٔ* جدید. ابطال فقط با close فراتر از SL است
// (فتیله کافی نیست) — همان قاعدهٔ برگشت تأییدشدهٔ HTF در فاز ۱۱.
void UpdateSetupLifecycle(datetime barTime, double closePrice, double highPrice, double lowPrice)
{
   if(!InpTrackSetupLifecycle) return;
   if(g_setupLifeState!="TRACKING") return;

   bool slHit=false, tp1Hit=false;
   if(g_setupLifeDir==DIR_BULL)
   {
      slHit  = (closePrice < g_setupLifeSL);
      tp1Hit = (highPrice>0.0 && highPrice>=g_setupLifeTP1);
   }
   else if(g_setupLifeDir==DIR_BEAR)
   {
      slHit  = (closePrice > g_setupLifeSL);
      tp1Hit = (lowPrice>0.0 && lowPrice<=g_setupLifeTP1);
   }
   else return;

   // اگر همان کندل هر دو را لمس کرد، محافظه‌کارانه ابطال مقدم است: ادعای
   // «هدف اول خورد» بدون شاهد بستهٔ قیمت پذیرفته نمیشود.
   if(slHit)
   {
      g_setupLifeState="INVALIDATED";
      g_setupLifeEndTime=barTime;
      g_setupLifeEndPrice=closePrice;
      g_setupInvalidTime=barTime;
      g_setupInvalidPrice=closePrice;
      g_setupInvalidDir=g_setupLifeDir;
      g_setupInvalidCount++;
      // Phase 42: no Latin token inside a Persian clause. The lifecycle code
      // (INVALIDATED / ARMED / TP1_HIT) stays Latin and leads the row.
      g_setupLifeReason=StringFormat("SETUP INVALIDATED | کندل %s با قیمت بستهٔ %s از حد ضرر %s رد شد (جهت ستاپ %s) → ستاپ باطل شد",
                                     TimeToString(barTime,TIME_DATE|TIME_MINUTES),
                                     DoubleToString(closePrice,_Digits),
                                     DoubleToString(g_setupLifeSL,_Digits), DirToStr(g_setupLifeDir));
      if(!g_rebuildMode)
         Print(StringFormat("ICT PHASE15 | setup INVALIDATED | %s | close %s beyond SL %s | dir %s | chain #%s | invalidated total %d",
               TimeToString(barTime,TIME_DATE|TIME_MINUTES), DoubleToString(closePrice,_Digits),
               DoubleToString(g_setupLifeSL,_Digits), DirToStr(g_setupLifeDir),
               IdToStr(g_setupLifeChainId), g_setupInvalidCount));
      PersistSetupLifecycleEvent("INVALIDATED", barTime, closePrice);
   }
   else if(tp1Hit)
   {
      double reached=(g_setupLifeDir==DIR_BULL)? highPrice : lowPrice;
      g_setupLifeState="TP1_HIT";
      g_setupLifeEndTime=barTime;
      g_setupLifeEndPrice=reached;
      g_setupTP1Count++;
      g_setupLifeReason=StringFormat("SETUP TP1_HIT | هدف اول (یک برابر ریسک = %s) در %s لمس شد → پیگیری این ستاپ بسته شد",
                                     DoubleToString(g_setupLifeTP1,_Digits),
                                     TimeToString(barTime,TIME_DATE|TIME_MINUTES));
      if(!g_rebuildMode)
         Print(StringFormat("ICT PHASE15 | setup TP1_HIT | %s | price %s reached TP1 %s | dir %s | tp1 total %d",
               TimeToString(barTime,TIME_DATE|TIME_MINUTES), DoubleToString(reached,_Digits),
               DoubleToString(g_setupLifeTP1,_Digits), DirToStr(g_setupLifeDir), g_setupTP1Count));
      PersistSetupLifecycleEvent("TP1_HIT", barTime, reached);
   }
}

// پس از UpdateSetup: اگر ستاپ READY شد، پیگیری از همین کندل مسلح می‌شود.
// تنها یک ستاپ در هر لحظه پیگیری می‌شود (آخرین زنجیرهٔ اثبات‌شده).
void ArmSetupLifecycle(datetime barTime)
{
   if(!InpTrackSetupLifecycle) return;
   if(!(g_setup.active && g_setup.status=="READY")) return;
   if(g_setup.sl<=0.0 || g_setup.tp1<=0.0 || g_setup.entry<=0.0) return;
   if(g_setupLifeState=="TRACKING" && g_setupLifeChainId==g_setup.chainEventId) return;

   g_setupLifeState="TRACKING";
   g_setupLifeDir=g_setup.dir;
   g_setupLifeEntry=g_setup.entry;
   g_setupLifeSL=g_setup.sl;
   g_setupLifeTP1=g_setup.tp1;
   g_setupLifeArmTime=barTime;
   g_setupLifeChainId=g_setup.chainEventId;
   g_setupArmedCount++;
   g_setupLifeReason=StringFormat("SETUP ARMED | مسلح شد در %s | ورود %s | حد ضرر %s | هدف اول %s | جهت %s",
                                  TimeToString(barTime,TIME_DATE|TIME_MINUTES),
                                  DoubleToString(g_setup.entry,_Digits), DoubleToString(g_setup.sl,_Digits),
                                  DoubleToString(g_setup.tp1,_Digits), DirToStr(g_setup.dir));
   if(!g_rebuildMode)
      Print(StringFormat("ICT PHASE15 | setup ARMED | %s | entry %s | SL %s | TP1 %s | dir %s | chain #%s | armed total %d",
            TimeToString(barTime,TIME_DATE|TIME_MINUTES), DoubleToString(g_setup.entry,_Digits),
            DoubleToString(g_setup.sl,_Digits), DoubleToString(g_setup.tp1,_Digits), DirToStr(g_setup.dir),
            IdToStr(g_setup.chainEventId), g_setupArmedCount));
   PersistSetupLifecycleEvent("ARMED", barTime, g_setup.entry);
}

// شاهد عددی فاز ۱۵ : آفست تاریخی/قاعدهٔ DST بروکر + وضعیت چرخهٔ عمر ستاپ.
// یک ردیف در هر کندل بسته (یا هر بار که مقدار کلیدی عوض شود) — به‌سبک فاز ۱۲.
void PersistPhase15Diagnostics(datetime barTime)
{
   if(!InpWritePhase15Diagnostics) return;
   int htfEvents=0;
   for(int i=0;i<ArraySize(g_events);i++)
      if(g_events[i].isHTF) htfEvents++;

   string sig=IntegerToString(g_histOffsetDeltaMin)+"|"+IntegerToString((int)g_brokerDSTRule)
              +"|"+(g_brokerDSTActiveNow?"1":"0")+"|"+g_setupLifeState
              +"|"+IntegerToString(g_setupArmedCount)+"|"+IntegerToString(g_setupInvalidCount)
              +"|"+IntegerToString(g_setupTP1Count)+"|"+g_setup.status
              +"|"+IntegerToString(htfEvents)+"|"+IntegerToString((int)g_currentSession);
   static datetime lastBar15=0;
   static string   lastSig15="";
   if(barTime==lastBar15 && sig==lastSig15) return;
   lastBar15=barTime; lastSig15=sig;

   int h=DiagOpen("ICT_Assistant_Canonical_Phase15_Diag.csv");
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0)
      FileWrite(h,"BuildStamp","BarTime","BrokerOffsetMinNow","BrokerStdOffsetMin","BrokerRule","BrokerDSTNow",
                "HistBarOffsetMin","HistDeltaMin","HistoryMode","NYHour","NYMin","Session",
                "SetupStatus","SetupLife","SetupEntry","SetupSL","SetupTP1",
                "ArmedTotal","InvalidTotal","TP1Total","HTFEventCount","HTFEventDrawn",
                "InvalidatedAt","InvalidatedPrice");
   FileSeek(h,0,SEEK_END);
   FileWrite(h, g_buildStamp, TimeToString(barTime,TIME_DATE|TIME_MINUTES),
             (int)(g_serverGMTOffsetSeconds/60), (int)(g_brokerStdOffsetSeconds/60),
             BrokerDSTRuleToStr(g_brokerDSTRule), g_brokerDSTActiveNow?"true":"false",
             (int)(BrokerOffsetSecondsAtServer(barTime)/60), g_histOffsetDeltaMin,
             InpUseHistoricalBrokerOffset?"HISTORICAL":"CURRENT",
             g_hourNYNow, g_minNYNow, SessionShortStr(),
             g_setup.status, g_setupLifeState,
             DoubleToString(g_setupLifeEntry,_Digits), DoubleToString(g_setupLifeSL,_Digits),
             DoubleToString(g_setupLifeTP1,_Digits),
             g_setupArmedCount, g_setupInvalidCount, g_setupTP1Count,
             htfEvents, g_htfEventsDrawn,
             g_setupInvalidTime>0? TimeToString(g_setupInvalidTime,TIME_DATE|TIME_MINUTES) : "",
             g_setupInvalidPrice>0.0? DoubleToString(g_setupInvalidPrice,_Digits) : "");
   DiagClose(h);
}

void UpdateSetup(double curClose, double atrValue, datetime barTime)
{
   g_setup.active=false; g_setup.status="NONE";
   g_setup.risk=0; g_setup.rrTP1=0; g_setup.rrTP2=0; g_setup.rrTP3=0;
   g_setup.oteLow=0; g_setup.oteHigh=0; g_setup.golden=0; g_setup.slBuffer=0;
   g_setup.zoneSource=""; g_setup.slSource=""; g_setup.chainText="";
   g_setup.chainSweepId=-1; g_setup.chainEventId=-1; g_setup.chainDispId=-1;
   g_setup.fvgId=-1; g_setup.obId=-1; g_setup.dolLiqId=-1;
   // فاز ۱۲
   g_setup.entryModel=MODEL_NONE; g_setup.modelReason="";
   g_setup.quality=0; g_setup.qualityMax=10; g_setup.qualityText="";
   g_setup.poiId=-1; g_setup.poiKind=POIK_NONE; g_setup.poiScore=0;
   g_analysisClose=curClose;
   g_analysisATR=atrValue;
   if(!InpEnableSetupEngine)
   {
      g_setup.status="SETUP_ENGINE_DISABLED";
      return;
   }
   if(g_htfBias==DIR_NONE)
   {
      g_setup.status="WAITING_H4_BIAS";
      return;
   }
   if(!g_hasDOL)
   {
      g_setup.status="WAITING_DOL";
      return;
   }

   if(g_mtfConflict)
   {
      g_setup.status="WAITING_MTF_CONFLICT";
      return;
   }
   if(g_mtfContext[1].externalDirection!=DIR_NONE && g_mtfContext[1].externalDirection!=g_htfBias) { g_setup.status="WAITING_H1_CONTEXT"; return; }
   if(g_mtfContext[2].externalDirection!=DIR_NONE && g_mtfContext[2].externalDirection!=g_htfBias) { g_setup.status="WAITING_M15_CONTEXT"; return; }
   if(g_mtfContext[3].externalDirection!=DIR_NONE && g_mtfContext[3].externalDirection!=g_htfBias && g_mtfContext[3].internalDirection!=g_htfBias) { g_setup.status="WAITING_M5_SETUP"; return; }
   if(g_mtfContext[4].internalDirection!=DIR_NONE && g_mtfContext[4].internalDirection!=g_htfBias) { g_setup.status="WAITING_M2_CONFIRMATION"; return; }
   if(g_mtfContext[5].internalDirection!=DIR_NONE && g_mtfContext[5].internalDirection!=g_htfBias) { g_setup.status="WAITING_M1_CONFIRMATION"; return; }

   // --- #۶۶ بند ۱: دروازهٔ زنجیرهٔ واقعی ICT ---
   // مدل: Sweep نقدینگی → Displacement → شکست ساختار هم‌جهت (MSS/BOS تأییدشده).
   // قبلاً مسیر READY هیچ‌کدام را چک نمی‌کرد و فقط به causal بودن ناحیه تکیه
   // داشت؛ حالا خودِ چرخه هم باید اثبات‌شده و تازه باشد.
   {
      bool sawUnproven=false;
      for(int i=ArraySize(g_events)-1;i>=0;i--)
      {
         if(g_events[i].isHTF) continue;
         if(g_events[i].direction!=g_htfBias) continue;
         if(g_events[i].type==EVT_CHOCH) { sawUnproven=true; continue; }
         if(g_events[i].displacementId==-1 || g_events[i].sweepId==-1) { sawUnproven=true; continue; }
         g_setup.chainEventId=g_events[i].id;
         g_setup.chainSweepId=g_events[i].sweepId;
         g_setup.chainDispId =g_events[i].displacementId;
         g_setup.chainText   =StringFormat("CHAIN | %s #%s | SWEEP #%s | DISPLACEMENT #%s | زمان %s",
                                           EventTypeToStr(g_events[i].type), IdToStr(g_events[i].id),
                                           TimeToString(g_events[i].time,TIME_DATE|TIME_MINUTES),
                                           IdToStr(g_events[i].sweepId), IdToStr(g_events[i].displacementId));
         if(barTime>0 && InpChainLookbackBars>0 && PeriodSeconds()>0 &&
            ((long)barTime-(long)g_events[i].time) > (long)PeriodSeconds()*(long)InpChainLookbackBars)
         {
            g_setup.status="WAITING_FRESH_CYCLE";
            return;
         }
         break;
      }
      if(g_setup.chainEventId==-1)
      {
         g_setup.status = sawUnproven ? "WAITING_PROVEN_SWEEP_MSS" : "WAITING_ICT_CYCLE";
         return;
      }
   }

   // آخرین FVG و OB Causal/Valid هم‌جهت با HTF Bias را پیدا کن
   // فاز ۱۲ (#۳۰ #۳۱): گپ Micro گاهی بسیار کوچک است و برای ناحیهٔ ورود مناسب
   // نیست؛ پس ابتدا گپ STANDARD/IMPLIED جست‌وجو می‌شود و Micro فقط به‌عنوان
   // جانشین می‌آید. همین منطق برای OB: Core/Extreme بر Standalone ارجح است (#۳۶).
   long fvgId=-1; double fTop=0,fBot=0;
   for(int pass=0;pass<2 && fvgId==-1;pass++)
      for(int i=ArraySize(g_fvgs)-1;i>=0;i--)
      {
         if(!g_fvgs[i].causal || g_fvgs[i].invalidated) continue;
         // فاز ۴۳ — ناحیهٔ ورود با **نقش فعلی** سنجیده می‌شود، نه جهت تولد: گپ
         // وارونه (iFVG) قابل معامله است ولی در جهت مخالف تولدش. قبلاً همین خط
         // جهت بازنویسی‌شده را می‌خواند و پیامدش این بود که یک گپ وارونهٔ هم‌جهت
         // با بایاس، هم می‌توانست وارد ستاپ شود و هم در CSV مخالف بایاس دیده شود.
         if(FVGActiveDir(g_fvgs[i])!=g_htfBias) continue;
         if(pass==0 && g_fvgs[i].kind==FVGK_MICRO) continue;
         fvgId=g_fvgs[i].id; fTop=g_fvgs[i].top; fBot=g_fvgs[i].bottom; break;
      }
   long obId=-1; double oTop=0,oBot=0;
   for(int pass=0;pass<2 && obId==-1;pass++)
      for(int i=ArraySize(g_obs)-1;i>=0;i--)
      {
         if(g_obs[i].state!=OB_VALID || g_obs[i].direction!=g_htfBias) continue;
         if(pass==0 && g_obs[i].isStandalone) continue;
         obId=g_obs[i].id; oTop=g_obs[i].top; oBot=g_obs[i].bottom; break;
      }

   bool hasChartZone = (fvgId!=-1 || obId!=-1);
   double chartTop = (obId!=-1)? oTop : fTop;
   double chartBot = (obId!=-1)? oBot : fBot;

   // --- #۴۳: دامنهٔ معامله‌گری از **لگ واقعی** خوانده می‌شود، نه آخرین سقف/کف مستقل ---
   if(!g_leg.valid)
   {
      g_setup.status="WAITING_DEALING_LEG";
      return;
   }
   double dealingRange=g_leg.range;
   double equilibrium=g_leg.eq;
   if(g_leg.dir!=g_htfBias)
   {
      // لگی که قیمت آخرین بار از آن گسترش یافته هم‌جهت Bias نیست؛ ریتریس
      // معامله‌پذیر روی لگ مخالف ساخته نمی‌شود (#۴۳/#۴۶).
      g_setup.status="WAITING_LEG_DIRECTION";
      return;
   }

   // --- #۴۶: OTE روی همان لگ (۶۲ / ۷۰٫۵ / ۷۹) ---
   double oteLow=0.0, oteHigh=0.0, golden=0.0;
   if(g_htfBias==DIR_BULL)
   {
      oteLow  = g_leg.high - dealingRange*InpOTE_High;     // مرز ۷۹٪
      oteHigh = g_leg.high - dealingRange*InpOTE_Low;      // مرز ۶۲٪
      golden  = g_leg.high - dealingRange*InpOTE_Golden;   // ۷۰٫۵٪
   }
   else
   {
      oteLow  = g_leg.low + dealingRange*InpOTE_Low;
      oteHigh = g_leg.low + dealingRange*InpOTE_High;
      golden  = g_leg.low + dealingRange*InpOTE_Golden;
   }
   g_setup.oteLow=oteLow; g_setup.oteHigh=oteHigh; g_setup.golden=golden;

   // سمت قیمت نسبت به EQ همان لگ (نه نسبت به هر رنج دیگری)
   bool priceSideOk = (g_htfBias==DIR_BULL) ? (curClose<=equilibrium) : (curClose>=equilibrium);
   if(!priceSideOk)
   {
      g_setup.status=g_htfBias==DIR_BULL?"WAITING_DISCOUNT_OTE":"WAITING_PREMIUM_OTE";
      return;
   }

   // --- #۶۶ بند ۴: ناحیهٔ ورود ابتدا روی تایم‌فریم SETUP (M5) جست‌وجو می‌شود ---
   double zoneTop=0.0, zoneBot=0.0;
   double m5Top=0.0, m5Bot=0.0, m5Mid=0.0;
   datetime m5Time=0;
   bool hasM5 = InpRequireSetupTFZone && FindSetupTFZone(barTime, g_htfBias, m5Top, m5Bot, m5Time);
   if(hasM5) m5Mid=(m5Top+m5Bot)/2.0;
   double chartMid=(chartTop+chartBot)/2.0;
   bool zoneSelected=false;
   if(hasM5 && m5Mid>=oteLow && m5Mid<=oteHigh)
   {
      zoneTop=m5Top; zoneBot=m5Bot;
      g_setup.zoneSource="FVG روی تایم‌فریم ستاپ (پنج دقیقه)، "+TimeToString(m5Time,TIME_DATE|TIME_MINUTES);
      zoneSelected=true;
   }
   else if(hasChartZone && chartMid>=oteLow && chartMid<=oteHigh)
   {
      zoneTop=chartTop; zoneBot=chartBot;
      g_setup.zoneSource=((obId!=-1)?"ORDER BLOCK":"FVG")+" | روی تایم‌فریم چارت";
      zoneSelected=true;
   }
   if(!zoneSelected)
   {
      g_setup.status = hasChartZone || hasM5
         ? (g_htfBias==DIR_BULL?"WAITING_DISCOUNT_OTE":"WAITING_PREMIUM_OTE")
         : "WAITING_RETRACE";
      return;
   }
   if(zoneTop<=zoneBot)
   {
      g_setup.status="WAITING_ZONE_GEOMETRY";
      return;
   }

   // --- #۶۶ بند ۲ و ۳: SL واقعی (ATR + StopsLevel) و R:R واقعی از DOL ---
   double dolPrice=(double)g_currentDOL.price;
   double entry=(zoneTop+zoneBot)/2.0;
   double sgn=(g_htfBias==DIR_BULL)?1.0:-1.0;
   int    stopsPts=(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   double stopsPrice=(double)stopsPts*_Point;
   g_stopsLevelPrice=stopsPrice;
   double bufAtr=(atrValue>0.0)? atrValue*InpSL_MinATR : 0.0;
   double bufPts=PointsToPrice((double)InpSL_MinPoints);
   double buf=MathMax(MathMax(bufPts,bufAtr),stopsPrice);
   if(buf<=0.0) buf=PointsToPrice(10.0);   // SL هرگز روی خود ناحیه نیفتد
   double sl=(g_htfBias==DIR_BULL)? zoneBot-buf : zoneTop+buf;
   double risk=MathAbs(entry-sl);
   if(risk<=0.0 || sl<=0.0)
   {
      g_setup.status="WAITING_SL_INVALID";
      return;
   }
   g_setup.slBuffer=buf;
   g_setup.slSource=StringFormat("SL BUFFER | میانگین دامنه %.2f×%.2f=%.2f | کف پوینتی %d نقطه=%.2f | حد توقف کارگزار %d نقطه=%.2f → بافر %.2f",
                                 atrValue, InpSL_MinATR, bufAtr, InpSL_MinPoints, bufPts,
                                 stopsPts, stopsPrice, buf);

   // DOL باید آن‌سوی ورود و در جهت معامله باشد؛ وگرنه هدف واقعی وجود ندارد
   if((g_htfBias==DIR_BULL && dolPrice<=entry) || (g_htfBias==DIR_BEAR && dolPrice>=entry))
   {
      g_setup.status="WAITING_DOL_DIRECTION";
      return;
   }

   double tp1=entry+sgn*risk*InpRR_TP1;
   double tp2=entry+sgn*risk*InpRR_TP2;
   double tp3Anchor=entry+sgn*risk*InpRR_TP3;
   double tp3=(g_htfBias==DIR_BULL)? MathMax(tp3Anchor,dolPrice) : MathMin(tp3Anchor,dolPrice);
   double rr=MathAbs(tp3-entry)/risk;      // R:R واقعی، نه مقدار ورودی

   g_setup.entry=entry; g_setup.sl=sl;
   g_setup.tp1=tp1; g_setup.tp2=tp2; g_setup.tp3=tp3;
   g_setup.risk=risk; g_setup.rr=rr;
   g_setup.rrTP1=MathAbs(tp1-entry)/risk;
   g_setup.rrTP2=MathAbs(tp2-entry)/risk;
   g_setup.rrTP3=rr;

   if(rr<InpMinRR)
   {
      g_setup.status="WAITING_RR_LOW";
      return;
   }

   // --- فاز ۱۲ (#۶۷): انتخاب مدل ورود ---
   // نوع رویداد زنجیره از رجیستری خوانده می‌شود تا مدل ۲۰۲۲ فقط با MSS
   // تأییدشده معتبر باشد، نه با هر CHoCH.
   bool chainIsMss=false;
   for(int i=0;i<ArraySize(g_events);i++)
      if(g_events[i].id==g_setup.chainEventId){ chainIsMss=(g_events[i].type==EVT_MSS); break; }
   bool hasChainedDisp=DisplacementChained(g_setup.chainDispId, g_htfBias);
   g_setup.entryModel=SelectEntryModel(chainIsMss, g_setup.chainSweepId!=-1, hasChainedDisp,
                                       fvgId, obId, zoneSelected, (g_leg.valid && g_leg.dir==g_htfBias));
   g_setup.modelReason=g_modelReason;

   // --- فاز ۱۲ (#۶۸): امتیاز کیفیت با ده معیار که واقعاً می‌توانند متفاوت باشند ---
   // توجه: معیارهای فاز روند از وضعیت کندل **قبلی** می‌آید چون UpdateExhaustion
   // بعد از UpdateContextForClosedBar اجرا می‌شود. یک کندل تأخیر، مستند شده.
   int q=0; string qb="";
   if(chainIsMss){ q++; qb+="۱ تغییر کاراکتر تأییدشده؛ "; }
   if(fvgId!=-1){ q++; qb+="۲ گپ علّی هم‌جهت؛ "; }
   if(obId!=-1){ q++; qb+="۳ اردر بلاک معتبر؛ "; }
   ENUM_OB_KIND obKind=OBK_UNDEFINED; bool obExtreme=false;
   for(int i=0;i<ArraySize(g_obs);i++)
      if(g_obs[i].id==obId){ obKind=g_obs[i].kind; obExtreme=g_obs[i].isExtreme; break; }
   if(obKind==OBK_CORE || obKind==OBK_EXTREME){ q++; qb+="۴ اردر بلاک از نوع هسته یا اکستریم، نه تنها؛ "; }
   if(obExtreme){ q++; qb+="۵ اردر بلاک روی اکسترمم لگ؛ "; }
   if(hasM5){ q++; qb+="۶ ناحیه از تایم‌فریم ستاپ؛ "; }
   POIObj bestPoi;
   if(FindBestPOI(g_htfBias, bestPoi) &&
      (bestPoi.kind==POIK_BREAKER || bestPoi.kind==POIK_OB || bestPoi.kind==POIK_MITIGATION))
   { q++; qb+="۷ بهترین نقطهٔ مورد علاقه یک ناحیهٔ ساختاری است؛ "; }
   if(curClose>=oteLow && curClose<=oteHigh){ q++; qb+="۸ قیمت داخل باند ورود بهینه؛ "; }
   if(g_trend.phase==PHASE_INITIATION || g_trend.phase==PHASE_EXPANSION){ q++; qb+="۹ فاز روند ادامه‌دار؛ "; }
   if(rr>=InpMinRR+0.5){ q++; qb+="۱۰ نسبت سود به ریسک با حاشیهٔ راحت"; }
   g_setup.quality=q; g_setup.qualityMax=10; g_setup.qualityText=qb;

   if(FindBestPOI(g_htfBias, bestPoi)){ g_setup.poiId=bestPoi.id; g_setup.poiKind=bestPoi.kind; g_setup.poiScore=bestPoi.score; }

   if(g_setup.entryModel==MODEL_NONE)
   {
      // کد وضعیت باید لاتین و خالص باشد؛ متن فارسی دلیل در پنل آموزشی
      // از g_modelReason خوانده می‌شود (فاز ۴۲).
      g_setup.status="WAITING_ENTRY_MODEL";
      return;
   }
   if(q<InpMinQualityScore)
   {
      g_setup.status=StringFormat("WAITING_QUALITY_LOW (score %d of 10)", q);
      return;
   }

   g_setup.status="READY";
   g_setup.active=true;
   g_setup.dir=g_htfBias;
   g_setup.fvgId=fvgId; g_setup.obId=obId; g_setup.dolLiqId=g_currentDOL.liquidityId;
}

