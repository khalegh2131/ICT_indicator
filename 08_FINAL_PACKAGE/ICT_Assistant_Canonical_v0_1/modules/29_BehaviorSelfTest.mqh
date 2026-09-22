//====================================================================
// PHASE 37 — BEHAVIORAL SELF-TEST ON SYNTHETIC DATA (FVG / OB / SWEEP)
//====================================================================
// مسئله‌ای که این بخش می‌بندد:
//   تمام ابزارهای اعتبارسنجی قبلی متن کد را grep می‌کنند؛ یعنی ثابت می‌کنند
//   «رشته در فایل هست»، نه «محاسبهٔ عددی درست است». یک grep سبز با یک فرمول
//   اشتباه هم سبز می‌ماند. MQL5 بیرون از MetaTrader اجرا نمی‌شود، پس تنها راه
//   اثبات واقعی این است که همین توابع زندهٔ DetectFVG / DetectOB / DetectSweep
//   روی کندل‌های ساختگی با پاسخ معلوم اجرا شوند و خروجی واقعی با انتظار
//   مقایسه شود. این کار در همان محیط و همان کدی انجام می‌شود که روی چارت اجرا
//   می‌شود؛ پس هیچ منطق تکراری/موازی‌ای وجود ندارد که از کد اصلی جدا بیفتد.
//
// زمان اجرا: یک‌بار در هر attach، در اولین OnCalculate پیش از بازسازی واقعی.
//   در آن لحظه سری زمانی در دسترس است (BarTime کار می‌کند) ولی رجیستری‌ها
//   هنوز خالی‌اند. آزمون رجیستری‌ها را پس از خود صفر می‌کند، پس تحلیل زنده
//   دقیقاً همان چیزی را می‌بیند که اگر آزمون خاموش بود می‌دید.
//
// خروجی: ICT_Assistant_Canonical_SelfTest.csv در COMMON\Files
//   ستون‌ها: Scenario | Expected | Actual | Pass
//   خوانده‌شده توسط tools/Validate-Phase37.ps1
//
// دندان هارنس: ردیف SENSITIVITY_probe_must_report_FAIL یک انتظار **عمداً غلط**
//   اعلام می‌کند. اگر آن ردیف FAIL نشود، یعنی مقایسه کار نمی‌کند و بقیهٔ
//   PASSها بی‌ارزش‌اند. پس «همه سبز» هرگز کافی نیست — باید دقیقاً یک FAIL
//   طراحی‌شده وجود داشته باشد.
string g_selfTestName[], g_selfTestExp[], g_selfTestAct[];
int    g_selfTestOk[];
int    g_selfTestWritten = 0;

void SelfTestRow(const string name, const bool ok, const string expected, const string actual)
{
   int n=ArraySize(g_selfTestName);
   ArrayResize(g_selfTestName,n+1); ArrayResize(g_selfTestExp,n+1);
   ArrayResize(g_selfTestAct,n+1);  ArrayResize(g_selfTestOk,n+1);
   g_selfTestName[n]=name; g_selfTestExp[n]=expected; g_selfTestAct[n]=actual;
   g_selfTestOk[n]=ok?1:0;
}

// مقایسهٔ اعشاری با تلورانس صریح (نه ==) تا خطای نمایش IEEE یک آزمون درست را
// قرمز نکند؛ 5e-7 کمتر از هر tick واقعی قیمت است.
bool SelfTestEq(const double a, const double b) { return MathAbs(a-b)<=0.0000005; }

string SelfTestD(const double v) { return DoubleToString(v,5); }

// ساختارهای محلی MQL5 تضمین مقدار اولیه ندارند؛ پیش از استفاده صفرشان می‌کنیم تا
// اگر lookup شکست خورد، خواندن فیلدها در رشتهٔ گزارش حافظهٔ ناخواسته ندهد.
void SelfTestOBReset(OBObj &ob)
{
   ob.id=0; ob.time=0; ob.top=0.0; ob.bottom=0.0; ob.direction=DIR_NONE;
   ob.displacementId=-1; ob.structureEventId=-1; ob.liquidityEventId=-1; ob.fvgId=-1;
   ob.isStandalone=false; ob.hasSweep=false; ob.isExtreme=false; ob.kind=OBK_STANDALONE;
   ob.polarityFlipped=false; ob.retested=false; ob.state=OB_INVALID;
   ob.createdTime=0; ob.brokenTime=0;
}

void SelfTestLiqReset(LiquidityObj &lo)
{
   lo.id=0; lo.type=LIQ_PDH; lo.scope=SCOPE_INTERNAL; lo.state=LSTATE_INVALID;
   lo.price=0.0; lo.time=0; lo.sweptTime=0; lo.sweptByEventId=-1; lo.isHTF=false;
}

bool SelfTestFindFVG(const long id, double &topOut, double &bottomOut, int &kindOut)
{
   for(int i=0;i<ArraySize(g_fvgs);i++)
      if(g_fvgs[i].id==id)
      {
         topOut=g_fvgs[i].top; bottomOut=g_fvgs[i].bottom;
         kindOut=(int)g_fvgs[i].kind;
         return true;
      }
   return false;
}

bool SelfTestFindFVGObj(const long id, FVGObj &out)
{
   for(int i=0;i<ArraySize(g_fvgs);i++)
      if(g_fvgs[i].id==id){ out=g_fvgs[i]; return true; }
   return false;
}

bool SelfTestFindOB(const long id, OBObj &out)
{
   for(int i=0;i<ArraySize(g_obs);i++)
      if(g_obs[i].id==id){ out=g_obs[i]; return true; }
   return false;
}

bool SelfTestFindLiq(const long id, LiquidityObj &out)
{
   for(int i=0;i<ArraySize(g_liquidity);i++)
      if(g_liquidity[i].id==id){ out=g_liquidity[i]; return true; }
   return false;
}

// پرکردن آرایه‌های ساختگی با کندل‌های خنثی/هم‌اندازه تا هیچ الگویی خودبه‌خود
// فعال نشود و هر سناریو فقط همان چیزی را بسنجد که قصدش را دارد.
void SelfTestFillNeutral(double &o[], double &h[], double &l[], double &c[],
                         const int size, const double base, const bool upBars)
{
   for(int i=0;i<size;i++)
   {
      o[i]=base;
      c[i]=upBars? base+0.20 : base-0.20;
      h[i]=base+0.40;
      l[i]=base-0.20;
   }
}

//--------------------------------------------------------------------
// آزمون FVG — هندسهٔ گپ استاندارد، گارد حداقل اندازه، فرمول Implied و
// Volume Imbalance (سه محاسبهٔ مستقل که قبلاً قاطی شده بودند).
//--------------------------------------------------------------------
void SelfTestFVG()
{
   double so[6], sh[6], sl[6], sc[6];
   double tp=0.0, bt=0.0; int kd=-1;

   // --- FVG-1: گپ صعودی استاندارد ---
   // کندل اول (shift 2) high=104.00 · کندل سوم (shift 0) low=105.00 → گپ 1.00
   // انتظار: top = low کندل سوم = 105.00 ، bottom = high کندل اول = 104.00
   ArrayResize(g_fvgs,0);
   g_analysisATR=0.0;                       // گارد حداقل اندازه خاموش تا هندسه خالص سنجیده شود
   SelfTestFillNeutral(so,sh,sl,sc,6,100.0,true);
   so[2]=103.20; sc[2]=103.80; sh[2]=104.00; sl[2]=103.00;   // کندل اول
   so[0]=105.20; sc[0]=105.80; sh[0]=106.00; sl[0]=105.00;   // کندل سوم
   DetectFVG(so,sh,sl,sc,0,-1);
   bool f1=SelfTestFindFVG(StableZoneId(BarTime(0),DIR_BULL,1),tp,bt,kd);
   SelfTestRow("FVG_STANDARD_BULL",
      f1 && SelfTestEq(tp,105.00) && SelfTestEq(bt,104.00) && kd==(int)FVGK_STANDARD,
      "top=105.00000 bottom=104.00000 kind=STANDARD",
      f1? StringFormat("top=%s bottom=%s kind=%d",SelfTestD(tp),SelfTestD(bt),kd) : "no zone registered");

   // --- FVG-2: گپ نزولی استاندارد ---
   // شرط نزولی: high(کندل سوم) < low(کندل اول) → top = low کندل اول ، bottom = high کندل سوم
   // کندل اول low=105.00 · کندل سوم high=104.00 → گپ 1.00
   ArrayResize(g_fvgs,0);
   SelfTestFillNeutral(so,sh,sl,sc,6,100.0,true);
   so[2]=105.20; sc[2]=105.60; sh[2]=105.80; sl[2]=105.00;   // کندل اول
   so[0]=103.80; sc[0]=103.40; sh[0]=104.00; sl[0]=103.20;   // کندل سوم
   DetectFVG(so,sh,sl,sc,0,-1);
   bool f2=SelfTestFindFVG(StableZoneId(BarTime(0),DIR_BEAR,1),tp,bt,kd);
   SelfTestRow("FVG_STANDARD_BEAR",
      f2 && SelfTestEq(tp,105.00) && SelfTestEq(bt,104.00) && kd==(int)FVGK_STANDARD,
      "top=105.00000 bottom=104.00000 kind=STANDARD",
      f2? StringFormat("top=%s bottom=%s kind=%d",SelfTestD(tp),SelfTestD(bt),kd) : "no zone registered");

   // --- FVG-3: نبود گپ (هیچ الگویی نباید ثبت شود) ---
   ArrayResize(g_fvgs,0);
   SelfTestFillNeutral(so,sh,sl,sc,6,100.0,true);
   DetectFVG(so,sh,sl,sc,0,-1);
   bool f3=SelfTestFindFVG(StableZoneId(BarTime(0),DIR_BULL,1),tp,bt,kd)
         || SelfTestFindFVG(StableZoneId(BarTime(0),DIR_BEAR,1),tp,bt,kd);
   SelfTestRow("FVG_NO_GAP_REGISTERS_NOTHING", !f3,
      "0 standard zones registered",
      StringFormat("g_fvgs=%d",ArraySize(g_fvgs)));

   // --- FVG-4/5: گارد حداقل اندازه (InpMinFVG_ATR × ATR تحلیل) ---
   if(InpMinFVG_ATR>0.0)
   {
      // با ATR=1.00 و InpMinFVG_ATR=0.10 → حداقل گپ = 0.10
      g_analysisATR=1.0;
      double minGap=InpMinFVG_ATR*g_analysisATR;

      ArrayResize(g_fvgs,0);
      SelfTestFillNeutral(so,sh,sl,sc,6,100.0,true);
      sh[2]=104.00; sl[2]=103.00; so[2]=103.20; sc[2]=103.80;
      sh[0]=106.00; sl[0]=104.05; so[0]=104.20; sc[0]=104.60;   // low[0]-high[2] = 0.05
      DetectFVG(so,sh,sl,sc,0,-1);
      bool smallFound=SelfTestFindFVG(StableZoneId(BarTime(0),DIR_BULL,1),tp,bt,kd);
      SelfTestRow("FVG_MINGAP_REJECTS_SMALL_GAP", !smallFound,
         StringFormat("gap 0.05000 below guard %.5f -> zone must be absent",minGap),
         smallFound? StringFormat("zone WRONGLY registered top=%s bottom=%s",SelfTestD(tp),SelfTestD(bt)) : "zone absent (correct)");

      ArrayResize(g_fvgs,0);
      SelfTestFillNeutral(so,sh,sl,sc,6,100.0,true);
      sh[2]=104.00; sl[2]=103.00; so[2]=103.20; sc[2]=103.80;
      sh[0]=106.00; sl[0]=104.50; so[0]=104.60; sc[0]=105.00;   // low[0]-high[2] = 0.50
      DetectFVG(so,sh,sl,sc,0,-1);
      bool bigFound=SelfTestFindFVG(StableZoneId(BarTime(0),DIR_BULL,1),tp,bt,kd);
      SelfTestRow("FVG_MINGAP_ACCEPTS_LARGE_GAP",
         bigFound && SelfTestEq(tp,104.50) && SelfTestEq(bt,104.00),
         "top=104.50000 bottom=104.00000",
         bigFound? StringFormat("top=%s bottom=%s",SelfTestD(tp),SelfTestD(bt)) : "zone absent");
   }
   else
   {
      SelfTestRow("FVG_MINGAP_REJECTS_SMALL_GAP", true, "guard active (InpMinFVG_ATR>0)", "SKIPPED (InpMinFVG_ATR=0)");
      SelfTestRow("FVG_MINGAP_ACCEPTS_LARGE_GAP", true, "guard active (InpMinFVG_ATR>0)", "SKIPPED (InpMinFVG_ATR=0)");
   }

   // --- FVG-6: فرمول واقعی ICT برای Implied FVG (میانهٔ فتیله‌ها) ---
   // UWM(x)=(H+max(O,C))/2 · LWM(x)=(min(O,C)+L)/2
   // صعودی: LWM(سوم) > UWM(اول) و L(سوم) <= H(اول) → ناحیه: bottom=UWM(اول)، top=LWM(سوم)
   if(InpEnablePhase12 && InpDetectImpliedFVG)
   {
      g_analysisATR=0.0;
      ArrayResize(g_fvgs,0);
      SelfTestFillNeutral(so,sh,sl,sc,6,100.0,true);
      so[2]=102.00; sc[2]=102.40; sh[2]=103.00; sl[2]=101.80;   // کندل اول → UWM=102.70 LWM=101.90
      sh[0]=106.00; sl[0]=102.90; so[0]=103.50; sc[0]=105.00;   // کندل سوم → LWM=103.20 UWM=105.50
      DetectFVG(so,sh,sl,sc,0,-1);
      bool fi=SelfTestFindFVG(StableZoneId(BarTime(0),DIR_BULL,3),tp,bt,kd);
      SelfTestRow("FVG_IMPLIED_BULL_MIDWICK_FORMULA",
         fi && SelfTestEq(tp,103.20) && SelfTestEq(bt,102.70) && kd==(int)FVGK_IMPLIED,
         "top=103.20000 bottom=102.70000 kind=IMPLIED",
         fi? StringFormat("top=%s bottom=%s kind=%d",SelfTestD(tp),SelfTestD(bt),kd) : "no zone registered");

      // همان هندسه، ولی L(سوم) بالای H(اول) → شرط l3<=h1 می‌شکند و Implied نباید ثبت شود
      ArrayResize(g_fvgs,0);
      SelfTestFillNeutral(so,sh,sl,sc,6,100.0,true);
      so[2]=102.00; sc[2]=102.40; sh[2]=103.00; sl[2]=101.80;
      sh[0]=106.00; sl[0]=103.50; so[0]=103.80; sc[0]=105.00;   // l3=103.50 > h1=103.00
      DetectFVG(so,sh,sl,sc,0,-1);
      bool fiBad=SelfTestFindFVG(StableZoneId(BarTime(0),DIR_BULL,3),tp,bt,kd);
      SelfTestRow("FVG_IMPLIED_BULL_REQUIRES_L3_LE_H1", !fiBad,
         "implied zone must be absent when L(third) > H(first)",
         fiBad? StringFormat("zone WRONGLY registered top=%s bottom=%s",SelfTestD(tp),SelfTestD(bt)) : "zone absent (correct)");

      // --- FVG-7: Volume Imbalance — گپ **بدنه‌ها** (نه فتیله‌ها)، مفهوم مستقل ---
      if(InpDetectVolumeImbalance)
      {
         ArrayResize(g_fvgs,0);
         SelfTestFillNeutral(so,sh,sl,sc,6,100.0,true);
         so[2]=102.00; sc[2]=102.40; sh[2]=103.00; sl[2]=101.80;
         sh[0]=106.00; sl[0]=102.90; so[0]=103.50; sc[0]=105.00;
         DetectFVG(so,sh,sl,sc,0,-1);
         bool fv=SelfTestFindFVG(StableZoneId(BarTime(0),DIR_BULL,5),tp,bt,kd);
         SelfTestRow("FVG_VOLUME_IMBALANCE_IS_SEPARATE_KIND",
            fv && SelfTestEq(tp,105.00) && SelfTestEq(bt,102.40) && kd==(int)FVGK_VOL_IMBALANCE,
            "top=105.00000 bottom=102.40000 kind=VOL_IMBALANCE",
            fv? StringFormat("top=%s bottom=%s kind=%d",SelfTestD(tp),SelfTestD(bt),kd) : "no zone registered");
      }
      else
         SelfTestRow("FVG_VOLUME_IMBALANCE_IS_SEPARATE_KIND", true,
            "volume imbalance ON", "SKIPPED (InpDetectVolumeImbalance=off)");
   }
   else
   {
      SelfTestRow("FVG_IMPLIED_BULL_MIDWICK_FORMULA", true, "implied detection ON", "SKIPPED (InpEnablePhase12/InpDetectImpliedFVG off)");
      SelfTestRow("FVG_IMPLIED_BULL_REQUIRES_L3_LE_H1", true, "implied detection ON", "SKIPPED (InpEnablePhase12/InpDetectImpliedFVG off)");
      SelfTestRow("FVG_VOLUME_IMBALANCE_IS_SEPARATE_KIND", true, "implied detection ON", "SKIPPED (InpEnablePhase12/InpDetectImpliedFVG off)");
   }
}

//--------------------------------------------------------------------
// آزمون فاز ۴۳ — وارونگی گپ (iFVG): یک جهت، یک نقش، یک گزارش
//--------------------------------------------------------------------
// چرا این آزمون لازم است: باگ این بود که تابع وارونگی، جهت گپ را در رجیستری
// **بازنویسی** می‌کرد. در آن حالت جهت، دو معنی داشت (جهت تولد و نقش فعلی) و
// هر مصرف‌کننده بسته به لحظهٔ خواندن چیز دیگری می‌گفت: مربع روی چارت بنفش
// (وارونه)، ردیف فایل تشخیصی «صعودی» (جهت تولد)، و ناحیهٔ انتخابی ستاپ یا
// وارونه می‌شد یا نمی‌شد. هیچ grep ای این را نمی‌گیرد؛ فقط اجرای واقعی تابع
// زنده روی کندل‌های ساختگی با پاسخ معلوم آن را نشان می‌دهد.
void SelfTestFVGPolarity()
{
   double so[6], sh[6], sl[6], sc[6];
   g_analysisATR=0.0;
   ArrayResize(g_fvgs,0);

   // همان هندسهٔ FVG-1: گپ صعودی استاندارد با top=105.00 و bottom=104.00
   SelfTestFillNeutral(so,sh,sl,sc,6,100.0,true);
   so[2]=103.20; sc[2]=103.80; sh[2]=104.00; sl[2]=103.00;   // کندل اول
   so[0]=105.20; sc[0]=105.80; sh[0]=106.00; sl[0]=105.00;   // کندل سوم
   DetectFVG(so,sh,sl,sc,0,-1);

   long stdId=StableZoneId(BarTime(0),DIR_BULL,1);
   FVGObj f; f.id=0; f.direction=DIR_NONE; f.inverted=false; f.invertedTime=0;
   bool found=SelfTestFindFVGObj(stdId,f);
   SelfTestRow("FVG_INVERSION_TARGET_ZONE_PRESENT",
      found && f.direction==DIR_BULL && !f.inverted && SelfTestEq(f.top,105.00) && SelfTestEq(f.bottom,104.00),
      "birth zone present: dir=BULL inverted=0 top=105.00000 bottom=104.00000",
      found? StringFormat("dir=%d inverted=%d top=%s bottom=%s",(int)f.direction,(f.inverted?1:0),SelfTestD(f.top),SelfTestD(f.bottom))
            : "standard bull zone not registered");

   // یک کندل بستهٔ قاطع **زیر** مرز گپ (close 103.50 < bottom 104.00) → وارونگی
   int secs=PeriodSeconds(PERIOD_CURRENT);
   if(secs<=0) secs=60;
   datetime later=(datetime)((long)f.createdTime+(long)secs*2L);
   UpdateFVG_Lifecycle(103.90, 103.40, 103.50, later);

   FVGObj g; g.id=0; g.direction=DIR_NONE; g.inverted=false; g.invertedTime=0;
   bool after=SelfTestFindFVGObj(stdId,g);
   int actDir=(int)FVGActiveDir(g);

   // (۱) پرچم و زمان وارونگی ثبت شده است — شاهد عددی، نه ادعا
   SelfTestRow("FVG_INVERSION_FLAG_AND_TIME",
      after && g.inverted && g.invertedTime==later,
      StringFormat("inverted=1 invertedTime=%s",TimeToString(later,TIME_DATE|TIME_MINUTES)),
      after? StringFormat("inverted=%d invertedTime=%s",(g.inverted?1:0),
                          g.invertedTime>0? TimeToString(g.invertedTime,TIME_DATE|TIME_MINUTES):"0")
            : "zone vanished after inversion");

   // (۲) جهت **تولد** هرگز تغییر نمی‌کند (این همان خطای اصلی بود)
   SelfTestRow("FVG_INVERSION_KEEPS_BIRTH_DIRECTION",
      after && g.direction==DIR_BULL,
      "dir=BULL (0) — the birth direction is immutable",
      after? StringFormat("dir=%d (%s)",(int)g.direction,DirToStr(g.direction)) : "zone vanished");

   // (۳) ولی نقش فعلی عوض شده است — همان چیزی که رنگ و ستاپ باید بگویند
   SelfTestRow("FVG_INVERSION_SWITCHES_ACTIVE_ROLE",
      after && actDir==(int)DIR_BEAR,
      "activeDir=BEAR (1) after a close below the bottom edge",
      after? StringFormat("activeDir=%d (%s)",actDir,DirToStr(FVGActiveDir(g))) : "zone vanished");

   // (۴) هندسه و شناسه دست‌نخورده‌اند: نام آبجکت روی چارت از همین شناسه ساخته
   //     می‌شود، پس اگر جهت عوض شود نام با محتوا نمی‌خواند
   SelfTestRow("FVG_INVERSION_KEEPS_GEOMETRY_AND_ID",
      after && SelfTestEq(g.top,105.00) && SelfTestEq(g.bottom,104.00) && g.id==stdId,
      "top=105.00000 bottom=104.00000 id unchanged",
      after? StringFormat("top=%s bottom=%s idStable=%s",SelfTestD(g.top),SelfTestD(g.bottom),(g.id==stdId?"1":"0"))
            : "zone vanished");

   // (۵) پنل و CSV از همین یک تابع رشته می‌سازند، پس خروجی گزارش هم سنجیده می‌شود
   SelfTestRow("FVG_INVERSION_REPORTS_ONE_DIRECTION",
      after && FVGPolarityReport(g)=="BULLISH -> BEARISH (iFVG)",
      "panel and CSV row read: BULLISH -> BEARISH (iFVG)",
      after? FVGPolarityReport(g) : "zone vanished");

   // (۶) وارونگی یک‌طرفه است: بسته‌شدن بعدی از سمت مخالف، نقش را برنمی‌گرداند
   //     (واژهٔ iFVG یعنی همین سطح یک‌بار جابه‌جا شده، نه اینکه هر کندل عوض شود)
   datetime later2=(datetime)((long)later+(long)secs);
   UpdateFVG_Lifecycle(105.60, 105.20, 105.50, later2);
   FVGObj h; h.id=0; h.direction=DIR_NONE; h.inverted=false; h.invertedTime=0;
   bool after2=SelfTestFindFVGObj(stdId,h);
   SelfTestRow("FVG_INVERSION_IS_ONE_WAY",
      after2 && h.inverted && h.direction==DIR_BULL && (int)FVGActiveDir(h)==(int)DIR_BEAR && h.invertedTime==later,
      "inverted stays 1, dir stays BULL, active stays BEAR, invertedTime unchanged",
      after2? StringFormat("inverted=%d dir=%d activeDir=%d invertedTime=%s",(h.inverted?1:0),(int)h.direction,
                           (int)FVGActiveDir(h), h.invertedTime>0? TimeToString(h.invertedTime,TIME_DATE|TIME_MINUTES):"0")
            : "zone vanished");

   ArrayResize(g_fvgs,0);
}

//--------------------------------------------------------------------
// آزمون OB — کدام کندل مبدأ ناحیه می‌شود، بدنه یا کل کندل، حالت اعتبار،
// Core/Standalone، اتصال به Sweep، سقف عقب‌گرد جست‌وجو و dedup.
//--------------------------------------------------------------------
void SelfTestOB()
{
   double so[12], sh[12], sl[12], sc[12];
   const int dispBar=2;
   g_leg.valid=false;                       // scope ناحیه در آزمون قطعی باشد (Internal)
   g_analysisATR=0.0;

   // مبنا: همهٔ کندل‌ها صعودی و کوچک‌اند (کندل مخالف برای Displacement صعودی نیستند)
   SelfTestFillNeutral(so,sh,sl,sc,12,100.0,true);

   // --- OB-1: کندل مخالف واقعی در idx3، DisplacementId ندارد → OB_INVALID ---
   // انتظار: مبدأ = idx3 (آخرین کندل نزولی پیش از Displacement)، جهت = BULL
   so[2]=100.50; sc[2]=102.00; sh[2]=102.20; sl[2]=100.30;   // کندل Displacement صعودی
   so[3]=101.00; sc[3]=100.00; sh[3]=101.20; sl[3]= 99.80;   // کندل مخالف (نزولی)
   ArrayResize(g_obs,0);
   DetectOB(so,sh,sl,sc,dispBar,-1,-1,-1,-1,0.0);
   long expId=StableZoneId(iTime(_Symbol,PERIOD_CURRENT,3),DIR_BULL,2);
   OBObj ob;
   SelfTestOBReset(ob);
   bool found=SelfTestFindOB(expId,ob);
   double expTop = InpOBUseFullCandleRange? 101.20 : 101.00;
   double expBot = InpOBUseFullCandleRange?  99.80 : 100.00;
   SelfTestRow("OB_ORIGIN_IS_LAST_OPPOSITE_BAR",
      found && SelfTestEq(ob.top,expTop) && SelfTestEq(ob.bottom,expBot) && ob.direction==DIR_BULL,
      StringFormat("top=%s bottom=%s dir=BULL (origin bar shift 3)",SelfTestD(expTop),SelfTestD(expBot)),
      found? StringFormat("top=%s bottom=%s dir=%d",SelfTestD(ob.top),SelfTestD(ob.bottom),(int)ob.direction) : "no zone registered");
   SelfTestRow("OB_NO_DISPLACEMENT_IS_INVALID",
      found && ob.state==OB_INVALID,
      "state=OB_INVALID (displacementId=-1)",
      found? StringFormat("state=%d",(int)ob.state) : "no zone registered");
   SelfTestRow("OB_STANDALONE_WHEN_NO_STRUCTURE_EVENT",
      found && ob.isStandalone && ob.kind==OBK_STANDALONE && !ob.hasSweep,
      "isStandalone=true kind=STANDALONE hasSweep=false",
      found? StringFormat("isStandalone=%s kind=%d hasSweep=%s",
            ob.isStandalone?"true":"false",(int)ob.kind,ob.hasSweep?"true":"false") : "no zone registered");

   // --- OB-2: با زنجیرهٔ کامل → OB_VALID + Core + hasSweep ---
   ArrayResize(g_obs,0);
   DetectOB(so,sh,sl,sc,dispBar,1000,5000,77,-1,0.0);
   found=SelfTestFindOB(expId,ob);
   SelfTestRow("OB_VALID_WITH_DISPLACEMENT",
      found && ob.state==OB_VALID,
      "state=OB_VALID (displacementId given)",
      found? StringFormat("state=%d",(int)ob.state) : "no zone registered");
   SelfTestRow("OB_CORE_AND_SWEEP_LINKED",
      found && !ob.isStandalone && ob.kind==OBK_CORE && ob.hasSweep && ob.structureEventId==5000 && ob.liquidityEventId==77,
      "isStandalone=false kind=CORE hasSweep=true structureEventId=5000 liquidityEventId=77",
      found? StringFormat("isStandalone=%s kind=%d hasSweep=%s structId=%I64d liqId=%I64d",
            ob.isStandalone?"true":"false",(int)ob.kind,ob.hasSweep?"true":"false",ob.structureEventId,ob.liquidityEventId)
           : "no zone registered");

   // --- OB-3 (dedup): همان ناحیه دوباره → نباید ردیف تکراری بسازد ---
   int before=ArraySize(g_obs);
   long dedupBefore=g_obsDeduped;
   DetectOB(so,sh,sl,sc,dispBar,1000,5000,77,-1,0.0);
   SelfTestRow("OB_DEDUP_SAME_ZONE_NOT_REPEATED",
      ArraySize(g_obs)==before && g_obsDeduped==dedupBefore+1,
      StringFormat("registry stays %d, dedup counter +1",before),
      StringFormat("registry=%d dedupDelta=%I64d",ArraySize(g_obs),g_obsDeduped-dedupBefore));

   // --- OB-4: کندل مخالف بیرون از سقف عقب‌گرد → هیچ ناحیه‌ای ثبت نشود ---
   // کندل مخالف در idx11 یعنی فاصلهٔ 9 کندل از Displacement؛ سقف پیش‌فرض 6 است.
   SelfTestFillNeutral(so,sh,sl,sc,12,100.0,true);
   so[2]=100.50; sc[2]=102.00; sh[2]=102.20; sl[2]=100.30;
   so[11]=101.00; sc[11]=100.00; sh[11]=101.20; sl[11]=99.80;
   ArrayResize(g_obs,0);
   DetectOB(so,sh,sl,sc,dispBar,1000,5000,77,-1,0.0);
   SelfTestRow("OB_LOOKBACK_LIMIT_REJECTS_FAR_ORIGIN",
      ArraySize(g_obs)==0 && InpOB_LookbackBars<9,
      "0 zones (opposite bar 9 back, InpOB_LookbackBars<9)",
      StringFormat("g_obs=%d lookback=%d",ArraySize(g_obs),InpOB_LookbackBars));

   // --- OB-5: Displacement نزولی → مبدأ = کندل صعودی پیش از آن ---
   SelfTestFillNeutral(so,sh,sl,sc,12,100.0,true);
   so[2]=102.00; sc[2]=100.50; sh[2]=102.20; sl[2]=100.30;   // Displacement نزولی
   so[3]=100.00; sc[3]=101.00; sh[3]=101.30; sl[3]= 99.90;   // کندل مخالف (صعودی)
   ArrayResize(g_obs,0);
   DetectOB(so,sh,sl,sc,dispBar,1000,-1,-1,-1,0.0);
   long expIdBear=StableZoneId(iTime(_Symbol,PERIOD_CURRENT,3),DIR_BEAR,2);
   bool fBear=SelfTestFindOB(expIdBear,ob);
   double expTopB = InpOBUseFullCandleRange? 101.30 : 101.00;
   double expBotB = InpOBUseFullCandleRange?  99.90 : 100.00;
   SelfTestRow("OB_BEARISH_DISPLACEMENT_ORIGIN",
      fBear && ob.direction==DIR_BEAR && SelfTestEq(ob.top,expTopB) && SelfTestEq(ob.bottom,expBotB),
      StringFormat("top=%s bottom=%s dir=BEAR (origin bar shift 3)",SelfTestD(expTopB),SelfTestD(expBotB)),
      fBear? StringFormat("top=%s bottom=%s dir=%d",SelfTestD(ob.top),SelfTestD(ob.bottom),(int)ob.direction) : "no zone registered");

   ArrayResize(g_obs,0);
}

//--------------------------------------------------------------------
// آزمون Sweep — شرط واقعی جارو (فتیله فراتر + بستهٔ برگشتی)، نبود مثبت کاذب
// در شکست، سطح آینده، سطح قبلاً‌جاروشده و اولویت نزدیک‌ترین سطح.
//--------------------------------------------------------------------
void SelfTestSweep()
{
   datetime tBar = BarTime(1);
   datetime tOld = BarTime(20);
   ENUM_DIRECTION d=DIR_NONE;
   long lvl=0, ret=0;
   LiquidityObj lo;
   SelfTestLiqReset(lo);

   // --- SWEEP-1: BSL جارو شد → جهت نزولی، سطح SWEPT با زمان همان کندل ---
   ArrayResize(g_liquidity,0);
   lvl=AddLiquidity(LIQ_PDH,SCOPE_EXTERNAL,105.0,tOld,false);
   ret=DetectSweep(105.5,104.0,104.5,tBar,d);
   bool s1=(ret==lvl && d==DIR_BEAR);
   SelfTestRow("SWEEP_BSL_SWEPT_IS_BEARISH", s1,
      "returned id = level id, direction = BEAR",
      StringFormat("returned=%I64d level=%I64d dir=%d",ret,lvl,(int)d));
   bool s1b=SelfTestFindLiq(lvl,lo) && lo.state==LSTATE_SWEPT && lo.sweptTime==tBar;
   SelfTestRow("SWEEP_BSL_MARKS_LEVEL_SWEPT", s1b,
      "state=SWEPT sweptTime=the sweeping bar time",
      StringFormat("state=%d sweptTimeMatch=%s",(int)lo.state, lo.sweptTime==tBar?"true":"false"));

   // --- SWEEP-2: همان سطح دوباره نباید جارو شود (فقط FRESH قابل جاروست) ---
   ret=DetectSweep(105.5,104.0,104.5,tBar,d);
   SelfTestRow("SWEEP_ALREADY_SWEPT_NOT_RESWEPT",
      ret==-1 && d==DIR_NONE,
      "returned id = -1, direction = NONE",
      StringFormat("returned=%I64d dir=%d",ret,(int)d));

   // --- SWEEP-3: شکست، نه جارو (بستهٔ بالای سطح) → مثبت کاذب نداشته باشیم ---
   ArrayResize(g_liquidity,0);
   lvl=AddLiquidity(LIQ_PDH,SCOPE_EXTERNAL,105.0,tOld,false);
   ret=DetectSweep(106.0,104.0,105.8,tBar,d);
   bool stayedFresh=SelfTestFindLiq(lvl,lo) && lo.state==LSTATE_FRESH;
   SelfTestRow("SWEEP_BREAK_IS_NOT_A_SWEEP",
      ret==-1 && d==DIR_NONE && stayedFresh,
      "returned id = -1 and level stays FRESH",
      StringFormat("returned=%I64d dir=%d state=%d",ret,(int)d,(int)lo.state));

   // --- SWEEP-4: SSL جارو شد → صعودی ---
   ArrayResize(g_liquidity,0);
   lvl=AddLiquidity(LIQ_PDL,SCOPE_EXTERNAL,100.0,tOld,false);
   ret=DetectSweep(101.0,99.5,100.6,tBar,d);
   SelfTestRow("SWEEP_SSL_SWEPT_IS_BULLISH",
      ret==lvl && d==DIR_BULL,
      "returned id = level id, direction = BULL",
      StringFormat("returned=%I64d level=%I64d dir=%d",ret,lvl,(int)d));

   // --- SWEEP-5: سطحی که هنوز ساخته نشده (زمانش بعد از کندل است) نباید جارو شود ---
   ArrayResize(g_liquidity,0);
   lvl=AddLiquidity(LIQ_PDH,SCOPE_EXTERNAL,105.0,BarTime(1),false);   // زمان سطح جدیدتر از کندل
   ret=DetectSweep(105.5,104.0,104.5,BarTime(5),d);
   bool fresh5=SelfTestFindLiq(lvl,lo) && lo.state==LSTATE_FRESH;
   SelfTestRow("SWEEP_FUTURE_LEVEL_IGNORED",
      ret==-1 && fresh5,
      "returned id = -1 and level stays FRESH",
      StringFormat("returned=%I64d state=%d",ret,(int)lo.state));

   // --- SWEEP-6: دو سطح هم‌زمان جارو شدند → همه علامت می‌خورند، ولی مالک
   //             زنجیره نزدیک‌ترین سطح به قیمت است ---
   ArrayResize(g_liquidity,0);
   long idA=AddLiquidity(LIQ_PDH,SCOPE_EXTERNAL,105.0,tOld,false);   // فاصله 0.60
   long idB=AddLiquidity(LIQ_PWH,SCOPE_EXTERNAL,105.4,tOld,false);   // فاصله 0.20 (نزدیک‌ترین)
   ret=DetectSweep(105.6,104.0,104.0,tBar,d);
   LiquidityObj loA, loB;
   SelfTestLiqReset(loA); SelfTestLiqReset(loB);
   bool aSwept=SelfTestFindLiq(idA,loA) && loA.state==LSTATE_SWEPT;
   bool bSwept=SelfTestFindLiq(idB,loB) && loB.state==LSTATE_SWEPT;
   SelfTestRow("SWEEP_NEAREST_LEVEL_OWNS_THE_CHAIN",
      ret==idB && d==DIR_BEAR,
      "returned id = nearest level (PWH @105.40), direction = BEAR",
      StringFormat("returned=%I64d nearest=%I64d other=%I64d dir=%d",ret,idB,idA,(int)d));
   SelfTestRow("SWEEP_ALL_TOUCHED_LEVELS_MARKED", aSwept && bSwept,
      "both swept levels marked SWEPT",
      StringFormat("pdh=%s pwh=%s",aSwept?"SWEPT":"not",bSwept?"SWEPT":"not"));

   ArrayResize(g_liquidity,0);
}

//--------------------------------------------------------------------
// SENSITIVITY — اثبات اینکه هارنس «دندان» دارد.
// انتظاری **عمداً غلط** اعلام می‌شود: «در این سه کندل یک FVG صعودی استاندارد
// هست». واقعیت این است که نیست. اگر این ردیف FAIL نشود، یعنی مقایسه کار
// نمی‌کند و بقیهٔ PASSها بی‌ارزش‌اند. ابزار Validate-Phase37 دقیقاً همین یک
// ردیف FAIL را الزامی می‌داند.
//--------------------------------------------------------------------
void SelfTestSensitivity()
{
   double so[6], sh[6], sl[6], sc[6];
   double tp=0.0, bt=0.0; int kd=-1;
   g_analysisATR=0.0;
   ArrayResize(g_fvgs,0);
   SelfTestFillNeutral(so,sh,sl,sc,6,100.0,true);   // سه کندل بدون هیچ گپی
   DetectFVG(so,sh,sl,sc,0,-1);
   bool claimFound=SelfTestFindFVG(StableZoneId(BarTime(0),DIR_BULL,1),tp,bt,kd);
   SelfTestRow("SENSITIVITY_probe_must_report_FAIL", claimFound,
      "a bullish standard FVG exists in these three bars (deliberately false claim)",
      claimFound? "claim held - harness cannot detect a wrong expectation" : "claim rejected (harness has teeth)");
   ArrayResize(g_fvgs,0);
}

void SelfTestWrite()
{
   int h=FileOpen("ICT_Assistant_Canonical_SelfTest.csv",
                  FILE_COMMON|FILE_WRITE|FILE_CSV|FILE_UNICODE,';');
   if(h==INVALID_HANDLE)
   {
      PrintFormat("ICT PHASE37 | ERR=%d | نوشتن گزارش آزمون رفتاری ناموفق بود",GetLastError());
      return;
   }
   FileWrite(h,"Scenario","Expected","Actual","Pass");
   int pass=0, fail=0;
   for(int i=0;i<ArraySize(g_selfTestName);i++)
   {
      FileWrite(h,g_selfTestName[i],g_selfTestExp[i],g_selfTestAct[i],g_selfTestOk[i]);
      if(g_selfTestOk[i]==1) pass++; else fail++;
   }
   FileClose(h);
   // FAIL=1 همان ردیف SENSITIVITY طراحی‌شده است؛ عدد بزرگ‌تر یعنی آزمون واقعاً
   // چیزی را رد کرده و باید بررسی شود.
   PrintFormat("ICT PHASE37 | behavioral self-test on synthetic data: rows=%d PASS=%d FAIL=%d | report ICT_Assistant_Canonical_SelfTest.csv",
               ArraySize(g_selfTestName),pass,fail);
}

void RunBehaviorSelfTest(const int need)
{
   if(!InpRunBehaviorSelfTest || g_selfTestWritten) return;
   // سری زمانی باید به‌قدر کافی بار داشته باشد تا BarTime/iTime معنا داشته باشند.
   if(need<60) return;
   g_selfTestWritten=1;

   // وضعیت زنده ذخیره می‌شود؛ آزمون نباید هیچ ردی روی تحلیل واقعی بگذارد.
   bool   savedRebuild=g_rebuildMode;
   double savedATR    =g_analysisATR;
   bool   savedLeg    =g_leg.valid;
   long   savedDedup  =g_obsDeduped;

   ArrayResize(g_selfTestName,0); ArrayResize(g_selfTestExp,0);
   ArrayResize(g_selfTestAct,0);  ArrayResize(g_selfTestOk,0);

   g_rebuildMode=true;    // هیچ آبجکتی از دادهٔ ساختگی روی چارت رسم نشود
   g_leg.valid  =false;   // scope ناحیه‌های آزمون قطعی باشد (Internal)
   g_analysisATR=0.0;

   SelfTestFVG();
   SelfTestFVGPolarity();
   SelfTestOB();
   SelfTestSweep();
   SelfTestSensitivity();

   // رجیستری‌ها به وضعیت خالی برگردانده می‌شوند تا بازسازی واقعی از صفر شروع کند.
   ArrayResize(g_fvgs,0);
   ArrayResize(g_obs,0);
   ArrayResize(g_liquidity,0);

   g_rebuildMode=savedRebuild;
   g_analysisATR=savedATR;
   g_leg.valid  =savedLeg;
   g_obsDeduped =savedDedup;

   SelfTestWrite();
}

