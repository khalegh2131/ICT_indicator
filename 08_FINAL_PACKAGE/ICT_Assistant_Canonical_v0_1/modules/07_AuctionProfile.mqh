//====================================================================
// فاز ۳۴ — Auction Market Theory: IB · TPO · نوع روز · نوع باز شدن · Naked POC
//
// منبع قاعده‌ها (بازبینی 2026-09-19):
//  · FTMO × OANDA — «Market Profile: Types of Opens and the Anatomy of a
//      Trading Day»: «the first hour of trading, known as the Initial Balance (IB)».
//  · واژه‌نامهٔ استاندارد Market Profile (Dalton — Mind Over Markets):
//      Normal day = IB گسترده که تقریباً کل دامنهٔ روز را می‌پوشاند؛
//      Neutral day = هر دو طرف IB شکسته می‌شود و قیمت داخل IB می‌بندد؛
//      Trend day = پروفایل نامتوازن با IB کوچک نسبت به دامنهٔ روز؛
//      Non-trend day = «IB باریکی که معمولاً تا آخر سشن حفظ می‌شود»؛
//      Open-Drive = باز شدن بیرون رنج/ارزش روز قبل و حرکت یک‌جهته.
//  · TPO (Time Price Opportunity) = شمارش «زمان» در هر ردیف قیمت (نه حجم).
//      پس VA زمان‌محور و VA حجم‌محور دو عدد متفاوت و هر دو معتبرند؛ هر دو گزارش می‌شوند.
//  · Naked/Virgin POC = POC یک سشن که پس از بسته‌شدن آن سشن لمس نشده است.
// همهٔ آستانه‌ها ورودی قابل‌تنظیم‌اند (بدون عدد جادویی پنهان).
//====================================================================
struct AMTDay
{
   datetime start;  bool valid;
   double   open, close, hi, lo;
   double   ibHi, ibLo;  bool ibValid;
   double   tpoPoc, tpoVah, tpoVal;  bool tpoOk;
   int      bars;
};

double g_profVolAt[];
int    g_profRows=0;
double g_profHigh=0.0, g_profRowH=0.0;

// تاریخچهٔ POC روزهای گذشته برای Naked/Virgin POC
struct PocHistRec { datetime dayStart; double poc; bool touched; };
PocHistRec g_pocHist[];
datetime   g_pocHistBuiltFor=0;

// شروع پنجرهٔ روز با مرجع انتخاب‌شدهٔ کاربر (InpPD_Anchor)
bool AMTDayStart(int back, datetime refBarTime, datetime &startOut, datetime &endOut)
{
   if(InpPD_Anchor==PD_ANCHOR_BROKER_DAY)
   {
      datetime t0=iTime(_Symbol,PERIOD_D1,back);
      if(t0<=0) return false;
      startOut=t0;
      endOut=(datetime)((long)t0+86400);
      return true;
   }
   int anchorH=(InpPD_Anchor==PD_ANCHOR_NY_1700)? 17 : 0;
   double hi=0.0, lo=0.0; int cnt=0;
   return WindowForDayBack(back, anchorH,0, anchorH,0, refBarTime, startOut, endOut, hi, lo, cnt, true);
}

// ساخت پروفایل یک روز روی تایم‌فریم منبع سشن (بدون دسترسی جدید به timeseries)
bool AMTBuildDay(int back, datetime barTime, AMTDay &d)
{
   d.valid=false; d.ibValid=false; d.tpoOk=false; d.bars=0;
   d.open=0; d.close=0; d.hi=0; d.lo=0; d.ibHi=0; d.ibLo=0;
   datetime dS=0,dE=0;
   if(!AMTDayStart(back, barTime, dS, dE)) return false;
   d.start=dS;
   int copied=ArraySize(g_winCacheT);
   if(copied<=0) return false;
   datetime ibEnd=(datetime)((long)dS+(long)MathMax(5,InpProfileIB_Minutes)*60);
   bool first=true;
   for(int i=0;i<copied;i++)
   {
      datetime t=g_winCacheT[i];
      if(t<dS || t>=dE) continue;
      if(first){ d.close=g_winCacheC[i]; first=false; }
      d.open=g_winCacheO[i];            // آخرین مقدار = قدیمی‌ترین کندل روز = open واقعی
      if(d.bars==0){ d.hi=g_winCacheH[i]; d.lo=g_winCacheL[i]; }
      else { d.hi=MathMax(d.hi,g_winCacheH[i]); d.lo=MathMin(d.lo,g_winCacheL[i]); }
      if(t<ibEnd)
      {
         if(!d.ibValid){ d.ibHi=g_winCacheH[i]; d.ibLo=g_winCacheL[i]; d.ibValid=true; }
         else { d.ibHi=MathMax(d.ibHi,g_winCacheH[i]); d.ibLo=MathMin(d.ibLo,g_winCacheL[i]); }
      }
      d.bars++;
   }
   if(d.bars<2 || d.hi<=d.lo) return false;
   d.valid=true;

   // پروفایل TPO: هر کندل به هر ردیفی که در بر می‌گیرد **یک** TPO می‌دهد
   int rows=MathMax(8,InpProfilePriceRows);
   int tpoAt[]; ArrayResize(tpoAt,rows); ArrayInitialize(tpoAt,0);
   double rowH=(d.hi-d.lo)/rows;
   if(rowH<=0.0) return true;
   for(int i=0;i<copied;i++)
   {
      datetime t=g_winCacheT[i];
      if(t<dS || t>=dE) continue;
      int r=(int)((g_winCacheH[i]-d.hi)/rowH); if(r<0) r=0; if(r>=rows) r=rows-1;
      int r2=(int)((g_winCacheL[i]-d.hi)/rowH); if(r2<0) r2=0; if(r2>=rows) r2=rows-1;
      int lo2=MathMin(r,r2), hi2=MathMax(r,r2);
      for(int rr=lo2; rr<=hi2; rr++) tpoAt[rr]+=1;
   }
   int tot=0; for(int r=0;r<rows;r++) tot+=tpoAt[r];
   if(tot<=0) return true;
   int poc=0; for(int r=0;r<rows;r++) if(tpoAt[r]>tpoAt[poc]) poc=r;
   double vaPct=MathMax(50.0,MathMin(95.0,InpProfileVA_Percent))/100.0;
   double target=tot*vaPct, acc=tpoAt[poc];
   int up=poc, dn=poc;
   while(acc<target && (up<rows-1 || dn>0))
   {
      double up2=(up<rows-1)? tpoAt[up+1] : 0.0;
      if(up<rows-2) up2+=tpoAt[up+2];
      double dn2=(dn>0)? tpoAt[dn-1] : 0.0;
      if(dn>1) dn2+=tpoAt[dn-2];
      bool canUp=(up<rows-1), canDn=(dn>0);
      if(!canUp && !canDn) break;
      bool goUp=canUp && (!canDn || up2>dn2);
      bool goDn=canDn && (!canUp || dn2>up2);
      if(canUp && canDn && up2==dn2){ goUp=true; goDn=true; }
      if(goUp){ acc+=tpoAt[up+1]; up++; }
      if(goDn){ acc+=tpoAt[dn-1]; dn--; }
   }
   d.tpoPoc=d.hi-(poc+0.5)*rowH;
   d.tpoVah=d.hi-up*rowH;
   d.tpoVal=d.hi-(dn+1)*rowH;
   d.tpoOk=true;
   return true;
}

// نوع روز از نسبت IB به دامنهٔ روز + محل بسته‌شدن (تعریف استاندارد Market Profile)
uint AMTDayType(const AMTDay &d, double atr)
{
   if(!d.valid || !d.ibValid) return 0;
   double ibR=d.ibHi-d.ibLo;
   double dR=d.hi-d.lo;
   if(ibR<=0.0 || dR<=0.0) return 0;
   bool extUp=(d.hi>d.ibHi), extDn=(d.lo<d.ibLo);
   // Neutral: هر دو طرف IB شکسته شود و بسته داخل IB بماند
   if(extUp && extDn && d.close<=d.ibHi && d.close>=d.ibLo) return 4;
   // Trend: IB کوچک نسبت به دامنهٔ روز و بسته در ربع بالا/پایین روز
   double q=dR*0.25;
   bool closeTop=(d.close>=d.hi-q), closeBot=(d.close<=d.lo+q);
   if(ibR<=InpAMT_TrendIBRatio*dR && (closeTop||closeBot) && (extUp||extDn)) return 1;
   // Non-trend: IB باریک/گسترده که تا آخر سشن حفظ شده (بدون امتداد)
   if(!extUp && !extDn && ibR>=InpAMT_NontrendIBRatio*dR) return 5;
   // Normal Variation: یک طرف شکسته و بسته بیرون IB
   if((extUp && d.close>d.ibHi) || (extDn && d.close<d.ibLo)) return 2;
   return 3;   // Normal
}

string AMTDayTypeName(uint t)
{
   switch(t)
   {
      // Phase 42: the Latin name of the day type opens the row (dictionary
      // order) and the explanation after it is pure Persian. A Latin word
      // inside a Persian clause splits the RTL run in two, so none is allowed
      // there - which is why the EMA acronym is spelled out as well.
      case 1: return "TREND DAY | روز روندی؛ جهت تا پایان روز حفظ می‌شود";
      case 2: return "NORMAL VARIATION DAY | نوسان طبیعی؛ دامنه کمی از روز قبل بیشتر";
      case 3: return "NORMAL DAY | روز معمول؛ دامنه نزدیک روز قبل";
      case 4: return "NEUTRAL DAY | خنثی — هر دو طرف بازهٔ اولیه شکسته";
      case 5: return "NON-TREND DAY | بی‌روند — بازهٔ اولیه حفظ شده";
      default: return "نامعلوم";
   }
}

// نوع باز شدن: Drive / Test-Drive / Reject / Auction — بر مبنای موقعیت open نسبت
// به دامنهٔ روز قبل و رفتار قیمت نسبت به IB همان روز (منبع: Dalton، فصل Opening Types)
uint AMTOpenType(const AMTDay &cur, const AMTDay &prev)
{
   if(!cur.valid || !cur.ibValid) return 0;
   if(!prev.valid) return 4;
   bool abovePrev=(cur.open>prev.hi), belowPrev=(cur.open<prev.lo);
   if(abovePrev || belowPrev) return 1;                       // Open-Drive
   double ibR=cur.ibHi-cur.ibLo;
   if(ibR<=0.0) return 4;
   if(prev.tpoOk && cur.open<=prev.tpoVah && cur.open>=prev.tpoVal) return 4;  // Open-Auction
   bool extUp=(cur.hi>cur.ibHi), extDn=(cur.lo<cur.ibLo);
   bool driveDir=(cur.close>cur.open);
   if(extUp && driveDir && (cur.close-cur.ibHi)>ibR*0.5) return 2;             // Test-Drive بالا
   if(extDn && !driveDir && (cur.ibLo-cur.close)>ibR*0.5) return 2;             // Test-Drive پایین
   if((extUp && !driveDir) || (extDn && driveDir)) return 3;                   // Reject-Reverse
   return 4;
}

string AMTOpenTypeName(uint t)
{
   switch(t)
   {
      case 1: return "OPEN-DRIVE | باز شدن بیرون رنج روز قبل و ادامه در همان جهت";
      case 2: return "OPEN-TEST-DRIVE | تست بازهٔ اولیه و سپس حرکت در جهت";
      case 3: return "OPEN-REJECT-REVERSE | رد بازهٔ اولیه و بازگشت";
      case 4: return "OPEN-AUCTION | باز شدن درون ناحیهٔ ارزش و تعادل";
      default: return "نامعلوم";
   }
}

void UpdateProfileAMT(datetime barTime, double atr)
{
   g_profileDaily.amtValid=false;
   if(!InpEnableProfile) return;
   int needBars=MathMax(400,(int)((double)(86400*(InpAMT_HistDays+2))/PeriodSeconds(InpSessionSourceTF))+120);
   if(!EnsureSessionBars(InpSessionSourceTF, needBars)) return;
   if(ArraySize(g_winCacheT)<30) return;

   AMTDay cur, prev;
   if(!AMTBuildDay(0, barTime, cur)) return;
   AMTBuildDay(1, barTime, prev);

   g_profileDaily.amtValid=true;
   g_profileDaily.dayOpen=cur.open; g_profileDaily.dayClose=cur.close;
   g_profileDaily.dayHi=cur.hi;     g_profileDaily.dayLo=cur.lo;
   g_profileDaily.ibHi=cur.ibHi;    g_profileDaily.ibLo=cur.ibLo;
   g_profileDaily.dayType=AMTDayType(cur, atr);
   g_profileDaily.openType=AMTOpenType(cur, prev);
   if(cur.tpoOk)
   {
      g_profileDaily.tpoValid=true;
      g_profileDaily.tpoPoc=cur.tpoPoc;
      g_profileDaily.tpoVah=cur.tpoVah;
      g_profileDaily.tpoVal=cur.tpoVal;
   }

   // --- Balance / Imbalance: پذیرش درون ارزش یا خروج از آن ---
   double refHi=(cur.tpoOk? cur.tpoVah : g_profileDaily.vah);
   double refLo=(cur.tpoOk? cur.tpoVal : g_profileDaily.val);
   double px=cur.close;
   g_profileDaily.balanceNote=(px<=refHi && px>=refLo)
      ? "BALANCE | پذیرش درون ناحیهٔ ارزش؛ تعادل"
      : "IMBALANCE | خروج از ناحیهٔ ارزش؛ عدم تعادل";

   // --- Naked/Virgin POC: تاریخچهٔ POC روزهای گذشته و بررسی لمس نشدن ---
   if(g_pocHistBuiltFor!=cur.start)
   {
      g_pocHistBuiltFor=cur.start;
      ArrayResize(g_pocHist,0);
      int copied=ArraySize(g_winCacheT);
      for(int back=1; back<=MathMax(1,InpAMT_HistDays); back++)
      {
         AMTDay hd;
         if(!AMTBuildDay(back, barTime, hd) || !hd.tpoOk) continue;
         PocHistRec rec; rec.dayStart=hd.start; rec.poc=hd.tpoPoc; rec.touched=false;
         // لمس بعد از پایان همان روز: هر کندلی که POC را در بر بگیرد
         for(int i=0;i<copied;i++)
         {
            if(g_winCacheT[i] < (datetime)((long)hd.start+86400)) continue;   // فقط بعد از روز
            if(g_winCacheT[i] > barTime) continue;
            if(g_winCacheH[i]>=hd.tpoPoc && g_winCacheL[i]<=hd.tpoPoc){ rec.touched=true; break; }
         }
         int n=ArraySize(g_pocHist);
         ArrayResize(g_pocHist,n+1); g_pocHist[n]=rec;
      }
   }
   g_profileDaily.hasNakedPoc=false; g_profileDaily.nakedPoc=0.0; g_profileDaily.nakedPocDay=0;
   for(int i=0;i<ArraySize(g_pocHist);i++)
   {
      if(g_pocHist[i].touched) continue;
      g_profileDaily.hasNakedPoc=true;
      g_profileDaily.nakedPoc=g_pocHist[i].poc;
      g_profileDaily.nakedPocDay=g_pocHist[i].dayStart;
      break;   // جدیدترین POC لمس‌نشده
   }
}

// ---------- دروازهٔ فراخوانی از AnalyzeClosedBar ----------
void UpdateFamilies(const double &o[], const double &h[], const double &l[], const double &c[], int shift, double atr)
{
   UpdateWyckoff(o,h,l,c,shift,atr);   // فاز ۳۳: o لازم شد (کلایمکس/PS به بدنهٔ کندل نیاز دارد)
   DetectSupplyDemand(o,h,l,c,shift,atr);
   if(shift==1)
   {
      // فاز ۳۳: یک منبع واحد برای نمایش و پنل آموزشی (بدون منطق تکراری).
      g_brooksInfo=AnalyzeBrooksBar(o,h,l,c,shift,atr);
      string barKind=g_brooksInfo.isTrendBar? "TREND BAR" : (g_brooksInfo.isDoji? "DOJI"
                  : (g_brooksInfo.isSignalBar? (g_brooksInfo.bullSignal? "BULL SIGNAL BAR":"BEAR SIGNAL BAR") : "کندل عادی"));
      string aiTxt=(g_brooksInfo.alwaysIn>0)? "LONG" : ((g_brooksInfo.alwaysIn<0)? "SHORT":"خنثی");
      string pullTxt="—";
      if(g_brooksInfo.alwaysIn>=0 && g_brooksInfo.hAttempts>0) pullTxt="H"+IntegerToString(g_brooksInfo.hAttempts);
      else if(g_brooksInfo.alwaysIn<=0 && g_brooksInfo.lAttempts>0) pullTxt="L"+IntegerToString(g_brooksInfo.lAttempts);
      // Phase 42: one row - Latin readout labels lead, and every clause after
      // a separator is pure Persian; the moving-average acronym is spelled out
      // in Persian so no Latin token sits inside the sentence.
      g_brooksNote=StringFormat("BROOKS | %s | ALWAYS-IN: %s | میانگین متحرک ۲۰ کندلی: %.5f | شمارش پولبک: %s",
                    barKind, aiTxt, g_brooksInfo.ema20, pullTxt);
   }
   UpdateRTM(o,h,l,c,shift,atr);
   if(shift==1) { UpdateProfile(); UpdateProfileAMT(BarTime(shift), atr); }
   UpdateWyckoffPhase();
}

// ---------- فاز ۱۵: قاعدهٔ DST اروپا ----
// شروع: آخرین یکشنبهٔ مارس ساعت ۰۱:۰۰ UTC · پایان: آخرین یکشنبهٔ اکتبر ۰۱:۰۰ UTC
// (قاعدهٔ ثابت اتحادیهٔ اروپا از ۱۹۹۶؛ همین قاعده برای همهٔ سال‌ها اعمال می‌شود و
//  همین موضوع در مستندات به‌عنوان محدودیت صریح ثبت شده است.)
int DaysInMonthOf(int year, int month)
{
   if(month<1 || month>12) return 30;
   if(month==2)
   {
      bool leap=((year%4==0 && year%100!=0) || year%400==0);
      return leap? 29 : 28;
   }
   int dim[12]={31,28,31,30,31,30,31,31,30,31,30,31};
   return dim[month-1];
}

int LastSundayOfMonth(int year, int month)
{
   int last=DaysInMonthOf(year,month);
   for(int day=last; day>=last-6; day--)
      if(DayOfWeekOf(year,month,day)==0) return day;
   return last;
}

datetime UTCBoundDay(int year, int month, int day, int hour, int minute)
{
   MqlDateTime d;
   d.year=year; d.mon=month; d.day=day; d.hour=hour; d.min=minute; d.sec=0;
   return StructToTime(d);
}

bool EU_IsDST_UTC(datetime utcT)
{
   MqlDateTime d; TimeToStruct(utcT,d);
   if(d.mon<3 || d.mon>10) return false;
   datetime startU=UTCBoundDay(d.year,3,LastSundayOfMonth(d.year,3),1,0);
   datetime endU  =UTCBoundDay(d.year,10,LastSundayOfMonth(d.year,10),1,0);
   return (utcT>=startU && utcT<endU);
}

string BrokerDSTRuleToStr(ENUM_BROKER_DST_RULE r)
{
   switch(r)
   {
      case BDST_AUTO: return "AUTO";
      case BDST_US:   return "US";
      case BDST_EU:   return "EU";
      default:        return "NONE";
   }
}

// AUTO: خانوادهٔ آفست جاری بروکر. بیشتر بروکرهای MT5 روی EET (+2 زمستان / +3 تابستان)
// هستند؛ اگر آفست در محدودهٔ اروپا نبود، قاعدهٔ آمریکا و در غیر این‌صورت «بدون DST»
// انتخاب می‌شود. این تخمین در CSV و پنل صریحاً گزارش می‌شود تا قابل بازبینی باشد.
ENUM_BROKER_DST_RULE ResolveBrokerDSTRule(int currentOffsetSeconds)
{
   if(InpBrokerDSTRule != BDST_AUTO) return InpBrokerDSTRule;
   int h=(int)MathRound((double)currentOffsetSeconds/3600.0);
   if(h>=0 && h<=3)   return BDST_EU;
   if(h==-4 || h==-5) return BDST_US;
   return BDST_NONE;
}

bool BrokerDSTAtUTC(datetime utcT)
{
   if(g_brokerDSTRule==BDST_US) return US_IsDST_UTC(utcT);
   if(g_brokerDSTRule==BDST_EU) return EU_IsDST_UTC(utcT);
   return false;
}

// آفست بروکر در یک لحظهٔ UTC مشخص (تاریخی). با خاموش بودن قابلیت، همان آفست جاری
// برمی‌گردد تا رفتار قبلی دقیقاً قابل بازتولید (و قابل مقایسه) بماند.
int BrokerOffsetSecondsAtUTC(datetime utcT)
{
   if(!InpUseHistoricalBrokerOffset) return g_serverGMTOffsetSeconds;
   return g_brokerStdOffsetSeconds + (BrokerDSTAtUTC(utcT)? 3600 : 0);
}

// آفست بروکر برای یک زمان *سرور* مشخص. چون زمان سرور خودش به آفست وابسته است،
// یک بازآزمایی نقطهٔ ثابت انجام می‌شود (خطای حداکثر یک ساعت فقط در پنجرهٔ گذار).
int BrokerOffsetSecondsAtServer(datetime serverT)
{
   if(!InpUseHistoricalBrokerOffset) return g_serverGMTOffsetSeconds;
   datetime utcA=(datetime)((long)serverT-(long)g_brokerStdOffsetSeconds);
   int offA=g_brokerStdOffsetSeconds+(BrokerDSTAtUTC(utcA)? 3600 : 0);
   datetime utcB=(datetime)((long)serverT-(long)offA);
   int offB=g_brokerStdOffsetSeconds+(BrokerDSTAtUTC(utcB)? 3600 : 0);
   return offB;
}

int NyOffsetSecondsUTC(datetime utcT) { return NY_IsDST_UTC(utcT) ? (-4*3600) : (-5*3600); }

datetime ServerToUTC(datetime serverT) { return (datetime)((long)serverT - (long)BrokerOffsetSecondsAtServer(serverT)); }
datetime UTCToServer(datetime utcT)    { return (datetime)((long)utcT + (long)BrokerOffsetSecondsAtUTC(utcT)); }

// نگه‌داشتن نام قبلی: ورودی «زمان سرور» می‌گیرد
bool IsUS_DST(datetime serverT) { return NY_IsDST_UTC(ServerToUTC(serverT)); }

int NY_GMTOffsetHours(datetime serverT) { return NyOffsetSecondsUTC(ServerToUTC(serverT))/3600; }

// تقویم نیویورک (year,mon,day,hour,min) -> زمان سرور بروکر.
// دو گذار سالانه دقیقاً مدیریت می‌شوند: ابتدا فرض EST آزموده می‌شود و اگر
// آن لحظه در بازهٔ DST باشد، فرض EDT هم بررسی می‌شود.
datetime NYWallToServer(int year, int month, int day, int hour, int minute, int dayShift)
{
   MqlDateTime dt;
   dt.year=year; dt.mon=month; dt.day=day; dt.hour=hour; dt.min=minute; dt.sec=0;
   datetime nyWall = (datetime)((long)StructToTime(dt) + (long)dayShift*86400);
   datetime utcEst = (datetime)((long)nyWall + 5*3600);     // فرض EST
   datetime utc = utcEst;
   if(NY_IsDST_UTC(utcEst))
   {
      datetime utcEdt = (datetime)((long)nyWall + 4*3600);  // فرض EDT
      if(NY_IsDST_UTC(utcEdt)) utc = utcEdt;
   }
   return UTCToServer(utc);
}

void NYStampOf(datetime barTime, MqlDateTime &out)
{
   datetime utc = ServerToUTC(barTime);
   datetime nyTime = (datetime)((long)utc + (long)NyOffsetSecondsUTC(utc));
   TimeToStruct(nyTime, out);
}

// فاز ۱۵: آفست استاندارد (زمستان) و قاعدهٔ DST بروکر از آفست *جاری* استخراج می‌شود.
// بدون این دو، بازسازی آفست تاریخی ممکن نیست (آفست جاری فقط لحظهٔ «حالا» را می‌گوید).
void DeriveBrokerDSTRuleAndStdOffset()
{
   int cur=DetectServerGMTOffsetSeconds();
   g_brokerDSTRule=ResolveBrokerDSTRule(cur);
   datetime nowUtc=(datetime)TimeGMT();
   g_brokerDSTActiveNow=BrokerDSTAtUTC(nowUtc);
   g_brokerStdOffsetSeconds = cur - (g_brokerDSTActiveNow? 3600 : 0);
   g_brokerOffsetSource=StringFormat("detected %+d min | rule %s | std %+d min | DST now %s",
                                     cur/60, BrokerDSTRuleToStr(g_brokerDSTRule),
                                     g_brokerStdOffsetSeconds/60, g_brokerDSTActiveNow?"ON":"OFF");
}

// آفست بروکر: دقیق (ثانیه) و بدون رُند به ساعت — بروکرهای GMT+5:30 هم درست می‌شوند.
// اگر تشخیص خودکار غیرقابل‌اعتماد باشد، InpBrokerToNY_HourOffset به‌عنوان
// ورودی مرجع/fallback استفاده می‌شود (#۵۷ — دیگر ورودی مرده نیست).
int DetectServerGMTOffsetSeconds()
{
   if(InpBrokerGMTOffsetOverrideHours != 99) return InpBrokerGMTOffsetOverrideHours*3600;
   long diff = (long)TimeTradeServer() - (long)TimeGMT();
   if(diff > (long)15*3600 || diff < -(long)15*3600)
   {
      datetime utcNow = (datetime)TimeGMT();
      return (int)((long)NyOffsetSecondsUTC(utcNow) - (long)InpBrokerToNY_HourOffset*3600);
   }
   return (int)diff;
}

// سطوح سشنی که با آفست قدیمی ساخته شده‌اند باید دور ریخته شوند، وگرنه بعد از
// تغییر آفست بروکر، هر دو نسخه (قدیم و جدید) به‌عنوان نقدینگی تازه می‌مانند (#۵۵)
void PurgeSessionLiquidity()
{
   int n=ArraySize(g_liquidity), w=0;
   for(int i=0;i<n;i++)
   {
      if(g_liquidity[i].type==LIQ_SESSION_H || g_liquidity[i].type==LIQ_SESSION_L) continue;
      if(w!=i) g_liquidity[w]=g_liquidity[i];
      w++;
   }
   if(w<n) ArrayResize(g_liquidity,w);
}

// آفست واقعی بروکر در هر کندل بسته بازآزمایی می‌شود؛ اگر بروکر آفست را با DST
// عوض کند، بدون این بازآزمایی همهٔ پنجره‌های سشن تا reload بعدی غلط می‌ماندند (#۵۵)
bool RefreshBrokerOffset()
{
   int seconds = DetectServerGMTOffsetSeconds();
   if(seconds == g_serverGMTOffsetSeconds) return false;
   int oldMin = g_serverGMTOffsetSeconds/60;
   g_serverGMTOffsetSeconds = seconds;
   g_serverGMTOffsetHours   = (int)MathRound((double)seconds/3600.0);
   // فاز ۱۵: عبور از DST بروکر آفست استاندارد را عوض نمی‌کند، ولی باید صریح
   // بازمحاسبه شود تا آفست تاریخی همهٔ لحظه‌های بعدی درست بماند.
   DeriveBrokerDSTRuleAndStdOffset();
   g_brokerOffsetChanges++;
   g_brokerOffsetNote = StringFormat("آفست بروکر عوض شد: %+d → %+d دقیقه (پنجره‌های سشن بازمحاسبه شدند)",
                                     oldMin, seconds/60);
   PrintFormat("ICT Canonical: broker GMT offset changed %+d -> %+d minutes; session liquidity rebuilt",
               oldMin, seconds/60);
   PurgeSessionLiquidity();
   return true;
}

// پنجرهٔ ساعت نیویورک برای یک دقیقهٔ مشخص؛ عبور از نیمه‌شب پشتیبانی می‌شود (۲۰:۰۰→۰۰:۰۰)
bool InNYWindow(int minutes, int startH, int startM, int endH, int endM)
{
   int s=startH*60+startM, e=endH*60+endM;
   if(s==e) return false;                       // پنجرهٔ صفر = غیرفعال
   if(s<e)  return (minutes>=s && minutes<e);
   return (minutes>=s || minutes<e);
}

// یک سری دادهٔ تاریخی که «در زمان asOf» وجود داشته است (بدون نگاه به آینده)
int CopyRatesAsOf(string symbol, ENUM_TIMEFRAMES tf, datetime asOf, int need, MqlRates &rates[])
{
   // Official CopyRates(start_time,count) returns bars whose open time is
   // <= asOf. This avoids the old fixed "latest 240 bars" look-back limit.
   MqlRates tmp[];
   int copied=CopyRates(symbol,tf,asOf,need,tmp);
   if(copied<=0) return 0;
   ArraySetAsSeries(tmp,true);

   // A higher-timeframe bar is usable only after its own close time.
   // The copied series is newest-first, so discard incomplete bars at front.
   int firstClosed=0;
   int tfSeconds=PeriodSeconds(tf);
   if(tfSeconds<=0) tfSeconds=60;
   while(firstClosed<copied && (long)tmp[firstClosed].time+(long)tfSeconds>(long)asOf)
      firstClosed++;
   if(firstClosed>=copied) return 0;

   int available=copied-firstClosed;
   ArrayResize(rates,available);
   for(int i=0;i<available;i++) rates[i]=tmp[firstClosed+i];
   ArraySetAsSeries(rates,true);
   return available;
}

// آخرین باکت بسته‌شدهٔ یک تایم‌فریم قبل از/mساوی barTime (مثال: PDH/PDL)
bool PreviousClosedBucket(datetime barTime, ENUM_TIMEFRAMES tf,
                          double &hi, double &lo, datetime &tOut)
{
   hi=0; lo=0; tOut=0;
   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   int copied=CopyRates(_Symbol,tf,0,80,rates);
   if(copied<3) return false;
   int idx=-1;
   for(int i=0;i<copied;i++) { if(rates[i].time<=barTime) { idx=i; break; } }
   if(idx<0 || idx+1>=copied) return false;
   hi=rates[idx+1].high; lo=rates[idx+1].low; tOut=rates[idx+1].time;
   return (hi>0 && lo>0);
}

//--------------------------------------------------------------------
// فاز ۱۳ (کارایی): دادهٔ منبع سشن یک بار در هر کندل کپی می‌شود و همهٔ
// پنجره‌ها (سشن‌ها + Silver Bullet، روی چند روز) از همان بافر مشترک
// می‌خوانند. علت: در بازسازی، هر پنجره جدا CopyTime/CopyHigh/CopyLow
// می‌زد و مجموع فراخوانی‌ها به ~۹۰ در هر کندل می‌رسید.
//
// حلقهٔ اسکن، شرط توقف و محاسبهٔ hi/lo عیناً همان است، پس اعداد تغییر
// نمی‌کنند؛ فقط منبع داده مشترک شده است. اگر کندل تازه‌ای روی ترمینال
// بیاید، بافر با یک CopyTime تک‌کندی باطل می‌شود.
//--------------------------------------------------------------------
bool EnsureSessionBars(ENUM_TIMEFRAMES tf, int need)
{
   // تک‌کندلی است، پس جهت آرایه (series بودن) اهمیتی ندارد و ArraySetAsSeries
   // روی آرایهٔ ایستا warning 63 می‌داد — همان یک warning فاز ۱۳.
   datetime newest[1];
   if(CopyTime(_Symbol,tf,0,1,newest)<=0) return false;

   bool same = (g_winCacheSymbol==_Symbol && g_winCacheTF==tf && g_winCacheNewest==newest[0]);
   if(same && (ArraySize(g_winCacheT)>=need || g_winCacheExhausted))
   {
      g_winCacheReuses++;
      return true;
   }

   int req=MathMax(need,800);
   datetime t[]; double h[]; double l[]; double o[]; double cl[];
   ArraySetAsSeries(t,true); ArraySetAsSeries(h,true); ArraySetAsSeries(l,true);
   ArraySetAsSeries(o,true); ArraySetAsSeries(cl,true);
   int copied = CopyTime(_Symbol, tf, 0, req, t);
   if(copied<=0) return false;
   int cH=CopyHigh(_Symbol, tf, 0, copied, h);   if(cH<=0) return false;
   int cL=CopyLow(_Symbol, tf, 0, copied, l);    if(cL<=0) return false;
   int cO=CopyOpen(_Symbol, tf, 0, copied, o);   if(cO<=0) return false;
   int cC=CopyClose(_Symbol, tf, 0, copied, cl); if(cC<=0) return false;
   // فاز ۴۰: طول پنجره را با کوچک‌ترین سری واقعاً کپی‌شده قفل کن (هم‌قاعده با
   // اصلاحات 06_MultiTimeframe) تا حلقه هرگز از آرایهٔ کوتاه‌تر بیرون نزند.
   int n=MathMin(copied,MathMin(cH,MathMin(cL,MathMin(cO,cC))));
   if(n<=0) return false;
   copied=n;

   g_winCacheSymbol=_Symbol;
   g_winCacheTF=tf;
   g_winCacheNewest=newest[0];
   g_winCacheExhausted=(copied<req);
   ArrayResize(g_winCacheT,copied);
   ArrayResize(g_winCacheH,copied);
   ArrayResize(g_winCacheL,copied);
   ArrayResize(g_winCacheO,copied);
   ArrayResize(g_winCacheC,copied);
   for(int i=0;i<copied;i++)
   { g_winCacheT[i]=t[i]; g_winCacheH[i]=h[i]; g_winCacheL[i]=l[i];
     g_winCacheO[i]=o[i]; g_winCacheC[i]=cl[i]; }
   g_winCacheCopies++;
   return true;
}

// رنج یک پنجرهٔ سشن، محاسبه‌شده روی تایم‌فریم منبع (مستقل از تایم‌فریم چارت)
bool CollectWindowRange(ENUM_TIMEFRAMES tf, datetime startSrv, datetime endSrv,
                        double &hi, double &lo, int &barCount)
{
   hi=0; lo=0; barCount=0;
   int need = MathMax(400, (int)((endSrv-startSrv)/PeriodSeconds(tf)) + 80);
   if(!EnsureSessionBars(tf,need)) return false;
   int copied=ArraySize(g_winCacheT);
   for(int i=0;i<copied;i++)
   {
      if(g_winCacheT[i] < startSrv) break;
      if(g_winCacheT[i] >= endSrv) continue;
      if(barCount==0){ hi=g_winCacheH[i]; lo=g_winCacheL[i]; }
      else { hi=MathMax(hi,g_winCacheH[i]); lo=MathMin(lo,g_winCacheL[i]); }
      barCount++;
   }
   return (barCount>0);
}

// آیا قدیمی‌ترین کندل موجود در کش پنجره از شروع پنجره قدیمی‌تر (یا مساوی) است؟
// فاز ۳۰ (#۷۵): بدون این گارد، پنجرهٔ نیمه‌پوشیده یک رنج کوچک‌تر از واقعیت
// می‌داد — یعنی PDH/PDL/PWH/PWL یا رنج سشن «غلط»، نه فقط «غایب». اصل پروژه
// این است که هیچ مقدار تقریبی به‌عنوان داده معتبر ثبت نشود.
bool WindowFullyCovered(datetime startSrv)
{
   int copied=ArraySize(g_winCacheT);
   if(copied<=0) return false;
   return (g_winCacheT[copied-1] <= startSrv);
}

// پنجرهٔ سشن مربوط به back روز قبل از روز مرجع (تقویم نیویورک)
bool WindowForDayBack(int back, int startH, int startM, int endH, int endM, datetime refBarTime,
                      datetime &startOut, datetime &endOut, double &hi, double &lo, int &barCount,
                      bool allowOpenWindow=false)
{
   MqlDateTime ref; NYStampOf(refBarTime, ref);
   bool crosses = ((endH*60+endM) <= (startH*60+startM));
   MqlDateTime dayRoot;
   dayRoot.year=ref.year; dayRoot.mon=ref.mon; dayRoot.day=ref.day;
   dayRoot.hour=0; dayRoot.min=0; dayRoot.sec=0;
   datetime nyMidnight = (datetime)((long)StructToTime(dayRoot) - (long)back*86400);
   MqlDateTime nd; TimeToStruct(nyMidnight, nd);
   startOut = NYWallToServer(nd.year, nd.mon, nd.day, startH, startM, 0);
   endOut   = crosses ? NYWallToServer(nd.year, nd.mon, nd.day, endH, endM, 1)
                      : NYWallToServer(nd.year, nd.mon, nd.day, endH, endM, 0);      if(endOut > refBarTime)
      {
         if(!allowOpenWindow) return false;     // پنجره هنوز بسته نشده
         endOut = refBarTime;                   // برای نمایش، فقط تا کندل جاری
      }
      // فاز ۳۰ (#۷۵): اگر کش پنجره از شروع آن قدیمی‌تر نباشد، دادهٔ کافی برای کل
      // پنجره نداریم و رنج به‌دست‌آمده کوچک‌تر از واقعیت می‌شود → رد (fail-safe).
      if(!allowOpenWindow && !WindowFullyCovered(startOut)) return false;
      return CollectWindowRange(InpSessionSourceTF, startOut, endOut, hi, lo, barCount);
}

// آخرین پنجرهٔ سشنی که کامل بسته شده است (قبل از زمان کندل جاری)
bool FindLastClosedWindow(int startH, int startM, int endH, int endM, datetime refBarTime,
                          datetime &startOut, datetime &endOut, double &hi, double &lo)
{
   int cnt=0;
   for(int back=0; back<=9; back++)
   {
      if(WindowForDayBack(back, startH, startM, endH, endM, refBarTime, startOut, endOut, hi, lo, cnt))
         return true;
   }
   return false;
}

