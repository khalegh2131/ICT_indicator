//====================================================================
// فاز ۳۲ — «ریسک برگشت»: در چه نقطه‌ای از حرکت ایستاده‌ایم و خطر ورودِ خلاف جهت چقدر است
//
// قاعدهٔ صادقانه (مهم): این تابع **هیچ درصدی تولید نمی‌کند**. درصد فقط از داده
// شمرده می‌شود؛ ابزار tools/Report-ReverseRisk.ps1 همین CSV را می‌خواند، حرکت
// بعدیِ قیمت را از ستون‌های High/Low می‌سازد و نرخ واقعی برگشت را به تفکیک
// شرط‌ها می‌دهد (با تعداد نمونه). اینجا فقط *شاهد* ثبت می‌شود و یک امتیاز هشدار
// با وزن‌های مستند که در پنل تفکیک می‌شوند — تا کاربر خودش قضاوت کند.
//====================================================================
string RRFvgKindName(ENUM_FVG_KIND k)
{
   switch(k)
   {
      case FVGK_IMPLIED:       return "FVG Implied";
      case FVGK_MICRO:         return "FVG Micro";
      case FVGK_VOL_IMBALANCE: return "Volume Imbalance";
   }
   return "FVG Standard";
}
// فاز ۳۶: برچسب ترکیبی Silver Bullet + همسویی HTF-LTF (در داشبورد و ReverseRisk)
string SBSyncLabel()
{
   string sb="";
   if(g_silverBullet==SB_LONDON) sb="SB 03-04";
   else if(g_silverBullet==SB_NY_AM) sb="SB 10-11";
   else if(g_silverBullet==SB_NY_PM) sb="SB 14-15";
   if(sb=="") return "—";
   // Phase 42: this string is joined with the Silver Bullet tag by " | ", so
   // each part is a Latin-first label followed by a pure Persian word - the
   // composite row stays one visual run instead of splitting into two.
   string sync=(g_mtfConflict? "MTF | تضاد" : (g_htfBias==DIR_NONE? "BIAS | بدون" : "HTF-LTF | همسو"));
   return sb+" | "+sync;
}
string RRObStateName(ENUM_OB_STATE s)
{
   switch(s)
   {
      case OB_VALID:      return "VALID (دست‌نخورده)";
      case OB_MITIGATED:  return "MITIGATED (لمس شده)";
      case OB_BROKEN:     return "BROKEN (شکسته)";
      case OB_BREAKER:    return "BREAKER (پولاریتی برگشته)";
      case OB_MITIGATION:  return "MITIGATION BLOCK";
   }
   return "INVALID";
}
string RRObKindName(const OBObj &o)
{
   // فاز ۴۳: برچسب سطح، نقش فعلی است — یک Breaker/Mitigation Block که قطبیتش
   // برگشته، دیگر ناحیهٔ تقاضا/عرضهٔ تولدش نیست.
   string dirTxt=(OBActiveDir(o)==DIR_BULL)? " (تقاضا)" : " (عرضه)";
   string scope=(o.scope==SCOPE_EXTERNAL)? " EXT":" INT";   // فاز ۳۶
   if(o.state==OB_BREAKER)    return "Breaker"+dirTxt;
   if(o.state==OB_MITIGATION) return "Mitigation Block"+dirTxt;
   if(o.kind==OBK_EXTREME)      return "OB Extreme"+dirTxt;
   if(o.kind==OBK_STANDALONE)   return "OB Standalone"+dirTxt+scope;
   return "OB Core"+dirTxt+scope;
}
string RRSdKindName(ENUM_SD_KIND k)
{
   switch(k)
   {
      case SDK_RBR:    return "S/D RBR";
      case SDK_DBD:    return "S/D DBD";
      case SDK_RBD:    return "S/D RBD";
      case SDK_DBR:    return "S/D DBR";
      case SDK_SUPPLY: return "Supply Zone";
      case SDK_DEMAND: return "Demand Zone";
   }
   return "S/D Zone";
}
string RRSdStateName(ENUM_SD_STATE s)
{
   switch(s)
   {
      case SDS_FRESH:   return "FRESH";
      case SDS_TESTED:  return "TESTED";
      case SDS_FLIPPED: return "FLIPPED";
      case SDS_BROKEN:  return "BROKEN";
   }
   return "-";
}
string RRLiqStateName(ENUM_LIQ_STATE s)
{
   switch(s)
   {
      case LSTATE_FRESH:   return "FRESH (دست‌نخورده)";
      case LSTATE_SWEPT:   return "SWEPT (جارو شده)";
      case LSTATE_INVALID: return "ACCEPTED (پذیرفته/مصرف شده)";
   }
   return "-";
}

// فاصلهٔ قیمت تا یک ناحیه (۰ = داخل ناحیه) بر حسب ATR
double RRAreaDist(double price, double top, double bottom, double atr)
{
   if(atr<=0.0) return 0.0;
   if(price>=bottom && price<=top) return 0.0;
   return MathMin(MathAbs(price-top),MathAbs(price-bottom))/atr;
}

void UpdateReverseRisk(double curClose, double atrValue, datetime barTime, double curHigh, double curLow)
{
   g_rrLevel="NONE"; g_rrLevelDist=0.0; g_rrLevelState="-";
   g_rrLegProg=0.0; g_rrDolDist=0.0; g_rrScore=0; g_rrReasons=""; g_rrLabel="LOW";
   g_rrEventBarsAgo=-1;
   g_rrHasRow=false;   // فاز ۴۶: فقط اگر تا انتها برسیم، شاهد ثبت می‌شود
   if(!InpEnableReverseRisk || atrValue<=0.0 || curClose<=0.0) return;

   // --- ۱) نزدیک‌ترین سطح به قیمت (نقدینگی / OB / FVG / S/D / رنج / خط روند) ---
   // اگر قیمت داخل چند ناحیه باشد، عمیق‌ترین/نزدیک‌ترین آن‌ها گزارش می‌شود.
   double best=1e18;
   for(int i=0;i<ArraySize(g_liquidity);i++)
   {
      double d=MathAbs(curClose-g_liquidity[i].price)/atrValue;
      if(d>=best) continue;
      best=d;
      g_rrLevel="LIQ "+LiqTypeLabel(g_liquidity[i].type);
      g_rrLevelState=RRLiqStateName(g_liquidity[i].state);
   }
   for(int i=0;i<ArraySize(g_obs);i++)
   {
      if(g_obs[i].state==OB_INVALID) continue;
      double d=RRAreaDist(curClose,g_obs[i].top,g_obs[i].bottom,atrValue);
      if(d>=best) continue;
      best=d;
      g_rrLevel=RRObKindName(g_obs[i]);
      g_rrLevelState=RRObStateName(g_obs[i].state);
   }
   for(int i=0;i<ArraySize(g_fvgs);i++)
   {
      if(g_fvgs[i].invalidated) continue;
      // ناحیهٔ زنجیره‌نشده جزء لایهٔ رسم نیست؛ اینجا هم به‌عنوان «نزدیک‌ترین سطح»
      // گزارش نمی‌شود تا با نمودار بخواند.
      if(!g_fvgs[i].causal) continue;
      double d=RRAreaDist(curClose,g_fvgs[i].top,g_fvgs[i].bottom,atrValue);
      if(d>=best) continue;
      best=d;
      // فاز ۴۳: همان قاعده برای گپ؛ اگر وارونه شده، در متن هم گفته می‌شود تا این
      // تک‌خطی با رنگ مربع روی چارت یک حرف بزند.
      g_rrLevel=RRFvgKindName(g_fvgs[i].kind)+((FVGActiveDir(g_fvgs[i])==DIR_BULL)? " (صعودی)":" (نزولی)")
               +(g_fvgs[i].inverted? " — وارونه‌شده":"");
      g_rrLevelState=(g_fvgs[i].inverted? "INVERTED":(g_fvgs[i].mitigated?
                     (g_fvgs[i].ceTouched? "CE لمس شده":"MITIGATED (لمس شده)")
                    :(g_fvgs[i].ceTouched? "CE لمس شده":"FRESH (دست‌نخورده)")));
   }
   for(int i=0;i<ArraySize(g_sd);i++)
   {
      if(g_sd[i].state==SDS_BROKEN) continue;
      double d=RRAreaDist(curClose,g_sd[i].top,g_sd[i].bottom,atrValue);
      if(d>=best) continue;
      best=d;
      g_rrLevel=RRSdKindName(g_sd[i].kind);
      g_rrLevelState=RRSdStateName(g_sd[i].state);
   }
   if(g_rangeOk && g_rangeHigh>g_rangeLow)
   {
      double dHigh=MathAbs(curClose-g_rangeHigh)/atrValue;
      double dLow =MathAbs(curClose-g_rangeLow)/atrValue;
      double d=MathMin(dHigh,dLow);
      if(d<best)
      {
         best=d;
         g_rrLevel="Range Liquidity "+(dHigh<=dLow? "(سقف رنج)":"(کف رنج)");
         g_rrLevelState="ACTIVE (رنج جاری)";
      }
   }
   for(int i=0;i<ArraySize(g_trendlines);i++)
   {
      if(g_trendlines[i].invalidated) continue;
      double lvl=TrendlinePriceAt(g_trendlines[i], barTime);
      if(lvl<=0.0) continue;
      double d=MathAbs(curClose-lvl)/atrValue;
      if(d>=best) continue;
      best=d;
      g_rrLevel=(g_trendlines[i].isHigh? "Trendline (Buy-Side بالای خط)":"Trendline (Sell-Side زیر خط)");
      g_rrLevelState=(g_trendlines[i].swept? "SWEPT (جارو شده)":"FRESH (دست‌نخورده)");
   }
   // --- فاز ۳۴: سطوح Auction Market Theory هم در «نزدیک‌ترین سطح» می‌آیند ---
   // چرا لازم است: برای این پرسش کاربر «این نقطه OB است یا لیکویدی یا چیز دیگر و
   // برگشت از کجا محتمل است»، IB/VA/TPO-POC/Naked POC/HVN دقیقاً همان سطوحی هستند
   // که برگشت از آن‌ها شمرده می‌شود. اگر در این اسکن نبودند، نزدیک‌ترین سطح می‌توانست
   // یک FVG دور باشد در حالی که قیمت روی IB ایستاده است.
   if(g_profileDaily.valid && g_profileDaily.amtValid)
   {
      double cand[8]; string cname[8]; string cstate[8];
      int nc=0;
      if(g_profileDaily.ibHi>g_profileDaily.ibLo)
      {
         cand[nc]=g_profileDaily.ibHi; cname[nc]="Initial Balance High"; cstate[nc]="IB (اولین "+IntegerToString(InpProfileIB_Minutes)+" دقیقهٔ روز)"; nc++;
         cand[nc]=g_profileDaily.ibLo; cname[nc]="Initial Balance Low";  cstate[nc]="IB (اولین "+IntegerToString(InpProfileIB_Minutes)+" دقیقهٔ روز)"; nc++;
      }
      if(g_profileDaily.tpoValid)
      {
         cand[nc]=g_profileDaily.tpoVah; cname[nc]="TPO VAH"; cstate[nc]="Value Area زمان‌محور"; nc++;
         cand[nc]=g_profileDaily.tpoVal; cname[nc]="TPO VAL"; cstate[nc]="Value Area زمان‌محور"; nc++;
         cand[nc]=g_profileDaily.tpoPoc; cname[nc]="TPO POC"; cstate[nc]="قیمت منصفانه (زمان‌محور)"; nc++;
      }
      if(g_profileDaily.hasNakedPoc)
      {
         cand[nc]=g_profileDaily.nakedPoc; cname[nc]="Naked/Virgin POC";
         cstate[nc]="لمس‌نشده از "+TimeToString(g_profileDaily.nakedPocDay,TIME_DATE); nc++;
      }
      for(int hh=0; hh<g_profileDaily.hvnCount && nc<8; hh++)
      { cand[nc]=g_profileDaily.hvn[hh]; cname[nc]="HVN"; cstate[nc]="گرهٔ پرحجم (مانع/آهنربا)"; nc++; }
      for(int ll=0; ll<g_profileDaily.lvnCount && nc<8; ll++)
      { cand[nc]=g_profileDaily.lvn[ll]; cname[nc]="LVN"; cstate[nc]="گرهٔ کم‌حجم (عبور سریع)"; nc++; }
      for(int k=0;k<nc;k++)
      {
         if(cand[k]<=0.0) continue;
         double dd=MathAbs(curClose-cand[k])/atrValue;
         if(dd>=best) continue;
         best=dd;
         g_rrLevel=cname[k];
         g_rrLevelState=cstate[k];
      }
   }
   g_rrLevelDist=(best<1.0e17)? best : 0.0;

   // --- ۲) «طلا تا کجا رفت»: قیمت در کجای لگ معامله‌گری است ---
   if(g_leg.valid && g_leg.high>g_leg.low)
   {
      double span=g_leg.high-g_leg.low;
      double pos=(curClose-g_leg.low)/span;          // ۰ = کف لگ، ۱ = سقف لگ
      g_rrLegProg=(g_leg.dir==DIR_BEAR? (1.0-pos) : pos)*100.0;
      if(g_rrLegProg<0.0) g_rrLegProg=0.0;
      if(g_rrLegProg>100.0) g_rrLegProg=100.0;
   }

   // --- ۳) فاصله تا هدف نقدینگی (DOL) ---
   if(g_hasDOL && g_currentDOL.price>0.0)
      g_rrDolDist=((g_currentDOL.direction==DIR_BULL)? (g_currentDOL.price-curClose)
                                                        : (curClose-g_currentDOL.price))/atrValue;

   // --- ۴) آخرین رویداد ساختاری چند کندل پیش بود؟ ---
   if(ArraySize(g_events)>0)
   {
      int sec=PeriodSeconds(PERIOD_CURRENT);
      if(sec<=0) sec=60;
      long diff=(long)barTime-(long)g_events[ArraySize(g_events)-1].time;
      if(diff>=0) g_rrEventBarsAgo=(int)(diff/sec);
   }

   // --- ۵) امتیاز هشدار برگشت (وزن‌ها مستند؛ این عدد «درصد» نیست) ---
   int score=0; string why="";
   if(g_barSweptTowardBias)
   { score+=25; why+="+۲۵ نقدینگیِ سمت بایاس جارو شد و کندل پشت سطح بست — "; }
   if(g_rrEventBarsAgo>=0 && g_rrEventBarsAgo<=InpReversalFreshBars)
   { score+=20; why+=StringFormat("+۲۰ آخرین رویداد ساختاری %d کندل پیش بود (کاراکتر تازه عوض شده) — ", g_rrEventBarsAgo); }
   if(g_exhaustion.state==EXH_WATCH || g_exhaustion.state==EXH_MICRO_PULLBACK ||
      g_exhaustion.state==EXH_RANGE_TRANSITION || g_exhaustion.state==EXH_EXTENDING)
   { score+=15; why+="+۱۵ فرسودگی روند: قدرت ادامه ضعیف شده — "; }
   if(g_rrLegProg>=85.0)
   { score+=15; why+=StringFormat("+۱۵ قیمت در %.0f%% انتهای لگ است (نقطهٔ برگشت بالقوه) — ", g_rrLegProg); }
   if(g_leg.valid)
   {
      if(g_htfBias==DIR_BULL && curClose>g_leg.eq)
      { score+=10; why+="+۱۰ بایاس صعودی ولی قیمت در نیمهٔ گران لگ است (ورود دیرهنگام) — "; }
      if(g_htfBias==DIR_BEAR && curClose<g_leg.eq)
      { score+=10; why+="+۱۰ بایاس نزولی ولی قیمت در نیمهٔ ارزان لگ است (ورود دیرهنگام) — "; }
   }
   if(g_hasDOL && g_rrDolDist<=0.5)
   { score+=15; why+=StringFormat("+۱۵ هدف نقدینگی تقریباً پر شد (فاصله %.2f برابر میانگین دامنه) — ", g_rrDolDist); }
   if(!g_mtfConflict)
   { score-=10; why+="−۱۰ همهٔ تایم‌فریم‌ها هم‌جهت بایاس هستند (ادامه محتمل‌تر) — "; }
   if(score<0) score=0;
   if(score>100) score=100;
   g_rrScore=score;
   g_rrLabel=(score>=75)? "EXTREME" : ((score>=50)? "HIGH" : ((score>=25)? "MEDIUM" : "LOW"));
   g_rrReasons=why;

   // --- ۶) آماده‌سازی شاهد برای ثبت در CSV ---
   // فاز ۴۶: خودِ نوشتن به تابع جداگانه منتقل شد، چون درجهٔ سیگنال *بعد* از
   // فرسودگی همان کندل محاسبه می‌شود. اگر اینجا نوشته می‌شد، ستون‌های درجه
   // همیشه از کندل قبلی می‌آمدند و فایل شاهد تبدیل به شاهد دروغ می‌شد.
   g_rrHasRow = InpWriteReverseRisk;
   g_rrBarTime=barTime; g_rrClose=curClose; g_rrHigh=curHigh; g_rrLow=curLow; g_rrAtr=atrValue;
}

// ثبت یک ردیف شاهد از آخرین کندل بسته — دقیقاً یک‌بار در هر کندل، پس از
// محاسبهٔ درجه. محاسبهٔ هیچ عددی اینجا نیست؛ فقط همان مقادیر ذخیره‌شده.
void PersistReverseRiskEvidence()
{
   if(!g_rrHasRow) return;
   // فاز ۴۷: تایم‌فریم در نام فایل. چرا: تا فاز ۴۶ نام فقط نماد داشت، پس دو
   // چارت زندهٔ یک نماد (M1 و M15) ردیف‌هایشان را در یک فایل می‌ریختند و هر
   // سنجشی که از این دفتر می‌خواند (فیت درجه و فیت سناریوی در انتظار) ناخواسته
   // دو تایم‌فریم را قاطی می‌کرد. کاربر خواسته است هر تایم‌فریم برای خودش باشد.
   int h=DiagOpen("ICT_Assistant_Canonical_ReverseRisk_"+_Symbol+"_"+ChartTfCode()+".csv");
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0)
      FileWrite(h,"BarTime","Bias","Price","High","Low","ATR",
                "LevelType","LevelDistATR","LevelState",
                "LegProgressPct","DOLType","DOLDistATR",
                "Exhaustion","SweptTowardBias","EventBarsAgo","MTFAligned",
                "RiskScore","RiskLabel","Reasons",
                // فاز ۴۶: شاهد درجه. ستون‌های اضافه در انتها می‌آیند تا ابزارهای
                // قدیمی که ستون‌های ۱ تا ۱۹ را می‌خوانند دست‌نخورده بمانند.
                "LevelFamily","Grade","GradeScore","GradeWinPct","GradeN",
                // فاز ۴۷: تایم‌فریم چارت هم ستون می‌شود (دو لایه: نام فایل و ستون)
                // تا هر ردیف خودش بگوید از کدام تایم‌فریم آمده است.
                "ChartTF");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,
             TimeToString(g_rrBarTime,TIME_DATE|TIME_MINUTES),
             DirToStr(g_htfBias),
             DoubleToString(g_rrClose,_Digits),
             DoubleToString(g_rrHigh,_Digits),
             DoubleToString(g_rrLow,_Digits),
             DoubleToString(g_rrAtr,_Digits),
             g_rrLevel,
             DoubleToString(g_rrLevelDist,2),
             g_rrLevelState,
             DoubleToString(g_rrLegProg,1),
             (g_hasDOL? g_currentDOL.typeName : "NONE"),
             DoubleToString(g_rrDolDist,2),
             ExhaustionStateToStr(g_exhaustion.state),
             (g_barSweptTowardBias? "true":"false"),
             g_rrEventBarsAgo,
             (g_mtfConflict? "false":"true"),
             g_rrScore,
             g_rrLabel,
             g_rrReasons,
             g_gradeFam,
             g_grade,
             DoubleToString(g_gradeScore,3),
             DoubleToString(g_gradeWin,1),
             g_gradeN,
             ChartTfCode());
   DiagClose(h);
}

