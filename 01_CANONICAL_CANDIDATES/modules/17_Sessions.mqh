//====================================================================
// SESSION ENGINE — رفع ایراد ۱۷: Session فقط Context است، سیگنال نمی‌سازد
//====================================================================
//====================================================================
// SESSION / KILLZONE ENGINE — پنجره‌های واقعی ICT به وقت نیویورک،
// محاسبه‌شده از زمان کندل (نه TimeCurrent) و مستقل از تایم‌فریم چارت.
//   Asian KZ          20:00 - 00:00 NY
//   London KZ         02:00 - 05:00 NY  (Judas Swing / Manipulation)
//   NY AM KZ          07:00 - 10:00 NY
//   London Close KZ   10:00 - 12:00 NY
//   NY PM KZ          13:30 - 16:00 NY
//   Silver Bullet      03:00-04:00 | 10:00-11:00 | 14:00-15:00 NY
//   Power of 3        Asia=Accumulation, London=Manipulation, NY=Distribution
//====================================================================
void UpdateSessionContext(datetime barTime)
{
   MqlDateTime ny; NYStampOf(barTime, ny);
   g_hourNYNow = ny.hour;
   g_minNYNow  = ny.min;
   g_nyOffsetHoursNow = NY_GMTOffsetHours(barTime);
   int minutes = ny.hour*60 + ny.min;

   // پنجره‌ها از ورودی‌ها خوانده می‌شوند (رفع #۵۰): قبلاً همین ساعت‌ها هاردکد
   // بودند و ۶ ورودی پنل هیچ اثری نداشتند.
   g_currentSession = SESS_NONE;
   if(InNYWindow(minutes, InpAsiaStartHourNY,0, InpAsiaEndHourNY,0))
      g_currentSession = SESS_ASIA;
   if(InNYWindow(minutes, InpLondonStartHourNY,0, InpLondonEndHourNY,0))
      g_currentSession = SESS_LONDON;
   if(InNYWindow(minutes, InpNY_KZ_StartHourNY,0, InpNY_KZ_EndHourNY,0))
      g_currentSession = SESS_NY_AM;
   if(InNYWindow(minutes, InpLondonCloseStartHourNY,0, InpLondonCloseEndHourNY,0))
      g_currentSession = SESS_LONDON_CLOSE;
   if(InNYWindow(minutes, InpNYPM_StartHourNY,InpNYPM_StartMinuteNY, InpNYPM_EndHourNY,InpNYPM_EndMinuteNY))
      g_currentSession = SESS_NY_PM;

   g_currentAMD = AMD_NONE;
   if(g_currentSession==SESS_ASIA)   g_currentAMD = AMD_ACCUMULATION;
   if(g_currentSession==SESS_LONDON) g_currentAMD = AMD_MANIPULATION;
   if(g_currentSession==SESS_NY_AM || g_currentSession==SESS_NY_PM) g_currentAMD = AMD_DISTRIBUTION;

   // --- فاز ۳۶: AMD قیمتی (مکمل نگاشت زمانی) ---
   // منبع (ICT Power of Three؛ همان AMD-X در QT): A = رنج تنگ آسیا؛
   // M = سوئپ/Judas (فتیله بیرون رنج آسیا + بستهٔ برگشتی)؛ D = حرکت انبساطی
   // در جهت مخالف سوئپ. اگر سوئپ رخ نداده باشد، فقط A را اعلام می‌کنیم و
   // M/D را «در انتظار» می‌گذاریم — نه تفسیرِ پس از رویداد.
   g_amdPriceStage=AMD_NONE; g_amdPriceNote="";
   if(g_asiaHigh>g_asiaLow)
   {
      g_amdPriceStage=AMD_ACCUMULATION;
      // سوئپManipulation: فتیلهٔ امروز (در همان روز) بیرون رنج آسیا رفته و کندل داخل بسته
      datetime dayStart=0,dayEnd=0; double dH=0,dL=0; int dCnt=0;
      if(WindowForDayBack(0,0,0,0,0,barTime,dayStart,dayEnd,dH,dL,dCnt,true) && dayStart>0)
      {
         // سوئپ بالای رنج آسیا (BSL) = Manipulation صعودی → Distribution نزولی
         double hi=0, lo=0;
         if(CollectWindowRange(PERIOD_CURRENT, dayStart, g_asiaEnd, hi, lo, dCnt) && hi>0)
         {
            if(hi>g_asiaHigh)
            {
               g_amdPriceStage=AMD_MANIPULATION;
               g_amdPriceNote=StringFormat("M | تأیید دستکاری: فتیلهٔ روز تا %.2f بیرون سقف آسیا (%.2f) — اگر برگشت و کندل جابه‌جایی نزولی بیاید، توزیع نزولی و ورود فروش", hi, g_asiaHigh);
               if(CollectWindowRange(PERIOD_CURRENT, dayStart, barTime, hi, lo, dCnt) && lo<g_asiaLow)
               { g_amdPriceStage=AMD_DISTRIBUTION; g_amdPriceNote=StringFormat("D تأیید: بعد از سوئپ بالا، قیمت تا %.2f پایین کف آسیا (%.2f) رفته — لگ توزیع نزولی در جریان است", lo, g_asiaLow); }
            }
            else if(lo<g_asiaLow)
            {
               g_amdPriceStage=AMD_MANIPULATION;
               g_amdPriceNote=StringFormat("M | تأیید دستکاری: فتیلهٔ روز تا %.2f بیرون کف آسیا (%.2f) — اگر برگشت و کندل جابه‌جایی صعودی بیاید، توزیع صعودی و ورود خرید", lo, g_asiaLow);
            }
            else g_amdPriceNote="A | انباشت فعال: قیمت داخل رنج آسیا است و دستکاری هنوز رخ نداده؛ هیچ الزامی به معامله نیست";
         }
      }
   }

   g_silverBullet = SB_NONE;
   if(InNYWindow(minutes, InpSB1_StartHourNY,0, InpSB1_EndHourNY,0)) g_silverBullet = SB_LONDON;
   if(InNYWindow(minutes, InpSB2_StartHourNY,0, InpSB2_EndHourNY,0)) g_silverBullet = SB_NY_AM;
   if(InNYWindow(minutes, InpSB3_StartHourNY,0, InpSB3_EndHourNY,0)) g_silverBullet = SB_NY_PM;

   // --- فاز ۳۶: Quarterly Theory (Daye) — ربع‌های روز و هفته، ساعت نیویورک ---
   // روز: Q1 18–24 · Q2 00–06 · Q3 06–12 · Q4 12–18 (منبع: arongroups — QT)
   g_qtDayPhase=QT_NONE;
   if(minutes>=18*60 || minutes<0)              g_qtDayPhase=QT_Q1_ACCUM;
   else if(minutes<6*60)                        g_qtDayPhase=QT_Q2_MANIP;
   else if(minutes<12*60)                       g_qtDayPhase=QT_Q3_DISTRIB;
   else                                         g_qtDayPhase=QT_Q4_REVERSAL;
   // هفته: دوشنبه=Q1 · سه‌شنبه=Q2 · چهارشنبه=Q3 · پنجشنبه=Q4
   // (روایت اصلی منبع؛ جمعه = ادامهٔ Q4 — صادقانه در Explain گفته می‌شود)
   MqlDateTime nyW; NYStampOf(barTime, nyW);
   g_qtWeekPhase=QT_NONE;
   if(nyW.day_of_week>=1 && nyW.day_of_week<=4)
      g_qtWeekPhase=(ENUM_QT_PHASE)(nyW.day_of_week);   // 1..4 → QT_Q1..QT_Q4 (مقادیر enum یکی‌اند)
   else if(nyW.day_of_week==5)                  g_qtWeekPhase=QT_Q4_REVERSAL;
   // True Open روز = قیمت بازِ کندلی که ساعت NY آن 00:00 است
   if(g_hourNYNow==0 && g_minNYNow<60 && (g_qtDayTrueOpenT==0 ||
      (long)NYWallToServer(nyW.year,nyW.mon,nyW.day,0,0,0)-(long)g_qtDayTrueOpenT>=86400))
   {
      double to[1];
      datetime wStart=NYWallToServer(nyW.year,nyW.mon,nyW.day,0,0,0);
      if(CopyOpen(_Symbol,PERIOD_CURRENT,wStart,1,to)==1 && to[0]>0.0)
      { g_qtDayTrueOpen=to[0]; g_qtDayTrueOpenT=wStart; }
   }
   // True Open هفته = اولین کندل بعد از دوشنبه 00:00 NY (قیمت باز)
   if(g_qtWkTrueOpenT==0)
   {
      // جست‌وجوی عقب‌گرد تا ۱۰ روز: اولین دوشنبه‌ای که کندلش موجود است
      MqlDateTime probe=nyW;
      for(int backD=0; backD<10 && g_qtWkTrueOpenT==0; backD++)
      {
         MqlDateTime pd; datetime pT=(datetime)((long)barTime-(long)backD*86400);
         TimeToStruct(pT,pd);
         if(pd.day_of_week!=1) continue;
         datetime wOpen=NYWallToServer(pd.year,pd.mon,pd.day,0,0,0);
         double to2[1];
         if(CopyOpen(_Symbol,PERIOD_CURRENT,wOpen,1,to2)==1 && to2[0]>0.0)
         { g_qtWkTrueOpen=to2[0]; g_qtWkTrueOpenT=wOpen; }
      }
   }

   // ساختار داخلی روی تایم‌فریم InpMTF (رفع #۶۱: این ورودی قبلاً هیچ مصرفی نداشت)
   g_mtfInternalDir = InternalDirectionAsOf(barTime, InpMTF, g_mtfInternalBarTime);

   // رنج سشن‌ها: آخرین پنجرهٔ کامل‌شده (مثال: Asian Range هدف نقدینگی لندن است)
   if(FindLastClosedWindow(InpAsiaStartHourNY,0, InpAsiaEndHourNY,0, barTime, g_asiaStart, g_asiaEnd, g_asiaHigh, g_asiaLow))
   {
      AddLiquidity(LIQ_SESSION_H, SCOPE_INTERNAL, g_asiaHigh, g_asiaStart, false);
      AddLiquidity(LIQ_SESSION_L, SCOPE_INTERNAL, g_asiaLow,  g_asiaStart, false);
   }
   if(FindLastClosedWindow(InpLondonStartHourNY,0, InpLondonEndHourNY,0, barTime, g_londonStart, g_londonEnd, g_londonHigh, g_londonLow))
   {
      AddLiquidity(LIQ_SESSION_H, SCOPE_INTERNAL, g_londonHigh, g_londonStart, false);
      AddLiquidity(LIQ_SESSION_L, SCOPE_INTERNAL, g_londonLow,  g_londonStart, false);
   }
   if(FindLastClosedWindow(InpNY_KZ_StartHourNY,0, InpNY_KZ_EndHourNY,0, barTime, g_nyAmStart, g_nyAmEnd, g_nyAmHigh, g_nyAmLow))
   {
      AddLiquidity(LIQ_SESSION_H, SCOPE_INTERNAL, g_nyAmHigh, g_nyAmStart, false);
      AddLiquidity(LIQ_SESSION_L, SCOPE_INTERNAL, g_nyAmLow,  g_nyAmStart, false);
   }
}

