//====================================================================
// REVERSAL ENGINE — فاز ۱۱ (#۸ #۷۱ #۱۰ #۷۰)
// برگشت «تأییدشده» فقط یک معنا دارد: کندل بسته‌شدهٔ HTF فراتر از سطح
// محافظت‌شدهٔ خارجی بسته شود (close کندل بسته، نه فتیله). این موتور:
//   • شناسهٔ سطح محافظت‌شده را به قیمت واقعی تبدیل می‌کند (#۸/#۷۱)،
//   • یک رویداد EVT_EXTERNAL_BREAK روی H4 می‌سازد،
//   • شواهد Smart Money Reversal را عددبه‌عدد می‌شمارد (#۷۰)،
//   • خروجی «برگشت تأییدشده» را به لایهٔ Exhaustion می‌دهد.
// تضمین #۱۰: هیچ خطی در این فایل بیرون از EvaluateStructureBreak/HTF
// مقدار g_htfBias را نمی‌نویسد؛ Exhaustion به‌تنهایی هرگز Bias را برنمی‌گرداند.
//====================================================================
int ChartBarsBetween(datetime from, datetime to)
{
   if(from<=0 || to<=from) return 0;
   int sec=PeriodSeconds(PERIOD_CURRENT);
   if(sec<=0) sec=60;
   return (int)(((long)to-(long)from)/(long)sec);
}

void RegisterExternalBreakEvent(ENUM_DIRECTION dir, datetime barTime, double levelPrice)
{
   long id=StableEventId(barTime, EVT_EXTERNAL_BREAK, dir, g_reversal.levelSwingId, true);
   g_reversal.eventId=id;
   for(int i=ArraySize(g_events)-1;i>=0;i--)
      if(g_events[i].id==id) return;   // همین شکست قبلأً ثبت شده — تکرار ممنوع

   StructureEvent e;
   e.id=id;
   e.type=EVT_EXTERNAL_BREAK;
   e.direction=dir;
   e.time=barTime;
   e.price=levelPrice;      // سطح محافظت‌شدهٔ خارجی که رد شد
   e.brokenSwingId=g_reversal.levelSwingId;
   // سطح محافظت‌شدهٔ مقابل در لحظهٔ شکست؛ پس از این کندل خودش محافظ می‌شود
   e.protectedSwingId=(dir==DIR_BULL)? g_htfProtectedHighId : g_htfProtectedLowId;
   e.confirmationBarShift=0;                       // shift صفر در سری HTF = کندل بستهٔ HTF
   e.displacementId=g_reversal.smrDispId;
   e.sweepId=g_reversal.smrSweepId;
   e.parentEventId=-1;
   e.isHTF=true;
   AppendStructureEvent(e);
   PersistStructureEvent(e);
   if(!g_rebuildMode)
      Print(StringFormat("ICT REVERSAL: EXTERNAL_BREAK %s | %s | protected %s %s broken by closed %s bar (close %s) | SMR %d/%d",
            DirToStr(dir), TimeToString(barTime,TIME_DATE|TIME_MINUTES),
            g_reversal.levelIsHigh?"HIGH":"LOW", DoubleToString(levelPrice,_Digits),
            EnumToString(InpHTF), DoubleToString(g_reversal.snapBarClose,_Digits),
            g_reversal.smrScore, g_reversal.smrMax));
}

// #۷۰ — Smart Money Reversal روی شواهد اثبات‌شدهٔ همین پروژه ساخته می‌شود، نه
// روی یک الگوی کندلی حدسی. چهار شاهد شمارش می‌شوند و آستانه از ورودی می‌آید.
// تعریف عملیاتی دقیقاً همین است و در مستندات ثبت می‌شود: این سنجه «قوی‌تر»
// از برگشت ساده است، نه یک قاعدهٔ خصوصی منسوب به شخص سوم.
void ScoreSmartMoneyReversal(ENUM_DIRECTION dir, datetime barOpen, datetime barCloseTime)
{
   g_reversal.smrScore=0;
   g_reversal.smrReason="";
   g_reversal.smr=false;
   g_reversal.smrSweepId=-1; g_reversal.smrDispId=-1; g_reversal.smrZoneId=-1;
   g_reversal.smrMax=4;

   int htfSec=PeriodSeconds(InpHTF);
   if(htfSec<=0) htfSec=14400;
   long window=(long)htfSec*(long)MathMax(1,InpSMR_SweepLookbackBars);
   datetime from=(datetime)((long)barOpen-window);

   // ۱) Sweep نقدینگی مقابل در همان پنجره (BSL برای برگشت نزولی، SSL برای صعودی)
   bool wantHighSide=(dir==DIR_BEAR);
   long sweepId=-1;
   for(int i=ArraySize(g_liquidity)-1;i>=0;i--)
   {
      if(g_liquidity[i].state!=LSTATE_SWEPT || g_liquidity[i].sweptTime<=0) continue;
      if(g_liquidity[i].sweptTime<from || g_liquidity[i].sweptTime>barCloseTime) continue;
      if(IsHighSideLiquidity(g_liquidity[i].type)!=wantHighSide) continue;
      sweepId=g_liquidity[i].id;
      break;
   }
   g_reversal.smrSweepId=sweepId;
   if(sweepId!=-1)
   {
      g_reversal.smrScore++;
      g_reversal.smrReason+=StringFormat("SWEEP | نقدینگی %s شماره #%s؛ ", wantHighSide?"سمت خرید":"سمت فروش", IdToStr(sweepId));
   }

   // ۲) Displacement زنجیرشدهٔ هم‌جهت (energyOnly=false یعنی به ساختار وصل است)
   long dispId=-1;
   for(int i=ArraySize(g_displacements)-1;i>=0;i--)
   {
      if(g_displacements[i].direction!=dir) continue;
      if(g_displacements[i].energyOnly) continue;
      if(g_displacements[i].time<from || g_displacements[i].time>barCloseTime) continue;
      dispId=g_displacements[i].id;
      break;
   }
   g_reversal.smrDispId=dispId;
   if(dispId!=-1)
   {
      g_reversal.smrScore++;
      g_reversal.smrReason+=StringFormat("Displacement زنجیرشده #%s؛ ", IdToStr(dispId));
   }

   // ۳) ناحیهٔ هم‌جهت (FVG causal معتبر یا Order Block معتبر)
   long zoneId=-1;
   // فاز ۴۳: شاهد «ناحیهٔ هم‌جهت» با نقش فعلی سنجیده می‌شود — گپ وارونه در جهت
   // مخالف تولدش شاهد این دروازه است، نه در جهت تولدش.
   for(int i=ArraySize(g_fvgs)-1;i>=0;i--)
      if(FVGActiveDir(g_fvgs[i])==dir && g_fvgs[i].causal && !g_fvgs[i].invalidated){ zoneId=g_fvgs[i].id; break; }
   if(zoneId==-1)
      for(int i=ArraySize(g_obs)-1;i>=0;i--)
         if(g_obs[i].direction==dir && g_obs[i].state==OB_VALID){ zoneId=g_obs[i].id; break; }
   g_reversal.smrZoneId=zoneId;
   if(zoneId!=-1)
   {
      g_reversal.smrScore++;
      g_reversal.smrReason+=StringFormat("ناحیهٔ هم‌جهت #%s؛ ", IdToStr(zoneId));
   }

   // ۴) هم‌جهت‌شدن ساختار داخلی/پایین‌تر با جهت برگشت
   bool ctxOk=(g_internalDir==dir) || (g_mtfContext[1].externalDirection==dir) ||
              (g_mtfContext[2].externalDirection==dir) || (g_mtfContext[3].externalDirection==dir);
   if(ctxOk)
   {
      g_reversal.smrScore++;
      g_reversal.smrReason+="هم‌جهتی ساختار داخلی/پایین‌تر با جهت برگشت؛ ";
   }

   g_reversal.smr=(g_reversal.smrScore>=InpSMR_MinScore);
   if(StringLen(g_reversal.smrReason)==0)
      g_reversal.smrReason="هیچ شاهد اضافی برای برگشت پول هوشمند پیدا نشد؛ ";
   g_reversal.smrReason+=StringFormat("%d از %d شرط", g_reversal.smrScore, g_reversal.smrMax);
}

void UpdateReversalEngine(datetime asOf, double closePrice, double atrValue)
{
   g_reversal.armed=false;
   g_reversal.smrMax=4;
   g_reversal.barsSince=ChartBarsBetween(g_reversal.confirmedCloseTime, asOf);

   if(!InpEnableReversalGate)
   {
      g_reversal.state="DISABLED";
      g_reversal.reason="دروازهٔ برگشت با ورودی مربوطه خاموش است؛ هیچ برگشتی تأیید نمی‌شود";
      return;
   }

   // دروازه از تصویر *پیش از* ارزیابی ساختار می‌آید، نه از Bias جاری
   // (Bias جاری می‌تواند در همین کندل عوض شده باشد و سطح را جابه‌جا کرده باشد).
   ENUM_DIRECTION guardBias=g_reversal.snapBias;
   g_reversal.levelSwingId=g_reversal.snapGuardId;
   g_reversal.levelPrice   =g_reversal.snapGuardPrice;
   g_reversal.levelTime    =g_reversal.snapGuardLevelTime;
   g_reversal.levelIsHigh  =g_reversal.snapGuardIsHigh;
   g_reversal.armed        =g_reversal.snapGuardOk;

   if(guardBias==DIR_NONE)
   {
      g_reversal.state="WAITING_H4_BIAS";
      g_reversal.reason="تا وقتی بایاس مالک تایم‌فریم بالاتر تأیید نشود، هیچ برگشتی اعلام نمی‌شود";
      return;
   }
   if(!g_reversal.snapGuardOk)
   {
      g_reversal.state="WAITING_PROTECTED_LEVEL";
      g_reversal.reason="سویینگ محافظت‌شدهٔ خارجی در رجیستری تایم‌فریم بالاتر پیدا نشد؛ یا آخرین رویداد آن تایم‌فریم سویینگ محافظ نداده، یا با سقف تعداد سویینگ‌ها حذف شده است";
      return;
   }
   if(g_reversal.snapBarTime<=0 || g_reversal.snapBarClose<=0.0)
   {
      g_reversal.state="WAITING_HTF_DATA";
      g_reversal.reason="دادهٔ کندل بستهٔ کافی روی تایم‌فریم بالاتر برای سنجش سطح محافظت‌شده وجود ندارد";
      return;
   }

   ENUM_DIRECTION revDir=OppositeDir(guardBias);

   // سطحی که در همان کندل (یا بعد از آن) ساخته شده، با همان کندل سنجیده نمی‌شود
   if(g_reversal.snapGuardLevelTime>0 && g_reversal.snapBarTime<=g_reversal.snapGuardLevelTime)
   {
      g_reversal.state=g_reversal.confirmed?"CONFIRMED":"ARMED";
      g_reversal.reason="سطح محافظت‌شده تازه ثبت شده است؛ سنجش از کندل بستهٔ بعدی تایم‌فریم بالاتر انجام می‌شود";
      return;
   }

   bool broke=(guardBias==DIR_BULL) ? (g_reversal.snapBarClose<g_reversal.levelPrice)
                                    : (g_reversal.snapBarClose>g_reversal.levelPrice);
   if(!broke)
   {
      if(!g_reversal.confirmed)
      {
         g_reversal.state="ARMED";
         g_reversal.reason=StringFormat("سطح محافظت‌شدهٔ خارجی (%s %.2f) با قیمت بستهٔ %.2f آخرین کندل بستهٔ تایم‌فریم بالاتر رد نشده است؛ برگشتی تأیید نمی‌شود",
                                        g_reversal.levelIsHigh?"سقف":"کف", g_reversal.levelPrice, g_reversal.snapBarClose);
      }
      else g_reversal.state="CONFIRMED";
      return;
   }

   // --- شکست سطح محافظت‌شدهٔ خارجی = تنها مسیر اعلام برگشت تأییدشده ---
   bool newBreak=(g_reversal.confirmedTime!=g_reversal.snapBarTime);
   if(newBreak)
   {
      g_reversal.confirmed=true;
      g_reversal.priorBias=guardBias;
      g_reversal.dir=revDir;
      g_reversal.confirmedTime=g_reversal.snapBarTime;
      g_reversal.confirmedCloseTime=(datetime)((long)g_reversal.snapBarTime+(long)PeriodSeconds(InpHTF));
      g_reversal.confirmedClose=g_reversal.snapBarClose;
      g_reversal.barsSince=ChartBarsBetween(g_reversal.confirmedCloseTime, asOf);
      // شواهد Smart Money Reversal باید بعد از تازه‌سازی MTF خوانده شود؛
      // UpdateReversalEngine در UpdateContextForClosedBar بعد از
      // AnalyzeMTFContext صدا زده می‌شود و همین ترتیب رعایت می‌شود.
      ScoreSmartMoneyReversal(revDir, g_reversal.confirmedTime, g_reversal.confirmedCloseTime);
      RegisterExternalBreakEvent(revDir, g_reversal.snapBarTime, g_reversal.levelPrice);
   }
   g_reversal.dir=revDir;
   g_reversal.state="CONFIRMED";
   g_reversal.reason=StringFormat("کندل بستهٔ %s در %s با قیمت بستهٔ %.2f فراتر از سطح محافظت‌شدهٔ خارجی (%s %.2f) بسته شد؛ این تنها مسیر اعلام برگشت تأییدشده است — فتیله کافی نیست",
                                  TfFa(InpHTF), TimeToString(g_reversal.confirmedTime,TIME_DATE|TIME_MINUTES),
                                  g_reversal.confirmedClose, g_reversal.levelIsHigh?"سقف":"کف", g_reversal.levelPrice);
}

// ابزار فقط-خواندنی برای اثبات با داده: فقط روی تغییر وضعیت یا کندل جدید HTF
// یک ردیف می‌نویسد تا فایل کوچک و قابل مقایسه بماند.
void PersistReversalDiagnostics(datetime barTime)
{
   if(!InpWriteReversalDiagnostics) return;
   static string   lastState="-";
   static datetime lastHtfBar=0;
   static datetime lastConfirm=0;
   bool htfChanged  =(g_reversal.snapBarTime!=lastHtfBar);
   bool stateChanged=(g_reversal.state!=lastState);
   bool newConfirm  =(g_reversal.confirmedTime!=lastConfirm);
   if(!htfChanged && !stateChanged && !newConfirm) return;
   lastState=g_reversal.state; lastHtfBar=g_reversal.snapBarTime; lastConfirm=g_reversal.confirmedTime;

   // فاز ۴۷: تایم‌فریم در نام فایل. چرا: دو چارت زندهٔ یک نماد (M1 و M15)
   // ردیف‌هایشان را در یک فایل می‌ریختند و هر سنجش «نرخ تأیید در کندل بعد»
   // ناخواسته دو تایم‌فریم را قاطی می‌کرد. کاربر خواسته است هر تایم‌فریم برای
   // خودش باشد و نام فایل صریح‌ترین جای بیان همان جداسازی است.
   int handle=DiagOpen("ICT_Assistant_Canonical_Reversal_Diag_"+ChartTfCode()+".csv");
   if(handle==INVALID_HANDLE) return;
   // خود-ترمیمی سرستون (فاز ۱۲): فایل‌های بازماندهٔ buildهای قدیمی سرستون
   // نداشتند و ردیف‌های کهنهٔ آن‌ها (با مقادیر پیش‌فرض صفر مثل GuardId=0) از
   // ردیف تازه قابل تشخیص نبود — همان چیزی که در سنجش فاز ۱۲ گمراه‌کننده شد.
   bool needHeader=(FileSize(handle)==0);
   if(!needHeader)
   {
      FileSeek(handle,0,SEEK_SET);
      string firstKey=FileReadString(handle);
      bool headerOk=(StringLen(firstKey)>0 && StringFind(firstKey,"ChartBar")>=0);
      if(headerOk)
      {
         // فاز ۱۵: ستون Symbol اضافه شد. بدون آن، ردیف‌های دو چارت زندهٔ
         // مختلف در همین فایل قاطی می‌شدند و هیچ راهی برای نسبت‌دادن یک ردیف
         // به نمادش وجود نداشت (شاهد غیرقابل‌استفاده).
         // نکتهٔ فاز ۴۷: سرستون حالا ستون ChartTF هم دارد، ولی چون نام فایل
         // خودش تایم‌فریم را در بر دارد، فایل‌های قدیمی هرگز با این نام روبه‌رو
         // نمی‌شوند؛ پس تشخیص «سرستون نامناسب» فقط همان شرط Symbol را می‌سنجد و
         // عوض‌کردن تعداد ستون‌ها باعث حذف بی‌دلیل فایل نمی‌شود.
         string secondKey=FileReadString(handle);
         if(StringFind(secondKey,"Symbol")<0) headerOk=false;
      }
      if(!headerOk)
      {
         // فاز ۲۴: هندل نگه‌داشته‌شده باید اول رها شود، وگرنه حذف/بازکردن فایل
         // روی هندل باز شکست می‌خورد و ردیف‌ها با سرستون کهنه مخلوط می‌شدند.
         DiagDrop("ICT_Assistant_Canonical_Reversal_Diag_"+ChartTfCode()+".csv");
         FileClose(handle);
         FileDelete("ICT_Assistant_Canonical_Reversal_Diag_"+ChartTfCode()+".csv",FILE_COMMON);
         handle=DiagOpen("ICT_Assistant_Canonical_Reversal_Diag_"+ChartTfCode()+".csv");
         if(handle==INVALID_HANDLE) return;
         needHeader=true;
      }
   }
   // ChartTF در **انتهای** سرستون می‌آید تا خواننده‌های قدیمی که بر اساس شمارهٔ
   // ستون کار می‌کنند دست‌نخورده بمانند (فاز ۴۷).
   if(needHeader)
      FileWrite(handle,"ChartBar","Symbol","State","BiasSnapshot","GuardId","GuardPrice","GuardSide","HtfBar","HtfClose","Broke","ConfirmedTime","ConfirmedClose","BarsSince","SmartMoneyReversal","SMRScore","SMRMax","SweepId","DispId","ZoneId","EventId","BuildStamp","ChartTF");
   // اگر بازنویسی سرستون ناممکن باشد (مثلاً نمونهٔ دیگری فایل را قفل کرده)،
   // یک ردیف مبهم نوشته *نمی‌شود*؛ به‌جایش یک‌بار در Journal هشدار داده می‌شود.
   else
   {
      FileSeek(handle,0,SEEK_SET);
      FileReadString(handle);
      if(StringFind(FileReadString(handle),"Symbol")<0) { DiagClose(handle); return; }
   }
   FileSeek(handle,0,SEEK_END);
   bool broke=(g_reversal.confirmedTime!=0 && g_reversal.confirmedTime==g_reversal.snapBarTime);
   FileWrite(handle,
             TimeToString(barTime,TIME_DATE|TIME_MINUTES),
             _Symbol,                              // فاز ۱۵: نسبت‌دادن ردیف به نماد
             g_reversal.state,
             DirToStr(g_reversal.snapBias),
             IdToStr(g_reversal.levelSwingId),
             DoubleToString(g_reversal.levelPrice,_Digits),
             g_reversal.armed?(g_reversal.levelIsHigh?"HIGH":"LOW"):"-",
             TimeToString(g_reversal.snapBarTime,TIME_DATE|TIME_MINUTES),
             DoubleToString(g_reversal.snapBarClose,_Digits),
             broke?"true":"false",
             TimeToString(g_reversal.confirmedTime,TIME_DATE|TIME_MINUTES),
             DoubleToString(g_reversal.confirmedClose,_Digits),
             g_reversal.barsSince,
             g_reversal.smr?"true":"false",
             g_reversal.smrScore,
             g_reversal.smrMax,
             IdToStr(g_reversal.smrSweepId),
             IdToStr(g_reversal.smrDispId),
             IdToStr(g_reversal.smrZoneId),
             IdToStr(g_reversal.eventId),
             g_buildStamp,
             ChartTfCode());
   DiagClose(handle);
}

