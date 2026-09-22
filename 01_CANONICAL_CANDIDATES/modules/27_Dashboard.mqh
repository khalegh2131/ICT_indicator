//====================================================================
// DASHBOARD — رفع ایراد ۱۶: از داده‌های واقعی Core می‌خواند، خودش
// چیزی محاسبه نمی‌کند.
//====================================================================
//====================================================================
// فاز ۱۴ — داشبورد با اندازه‌گیری واقعی متن (بدون بریدگی، بدون ردیف کهنه)
//
// دو ایراد واقعی که این بخش می‌بندد:
//   ۱) پس‌زمینهٔ داشبورد ۳۸۰×۶۴۰ هاردکد بود. با ۴۱ ردیف ممکن و ردیف‌های بلند
//      (مثلاً ردیف OB با ۶۶ کاراکتر)، متن از کادر بیرون می‌زد یا روی ردیف بعدی
//      می‌افتاد → همان «بریدگی/سرریز».
//      حالا عرض و ارتفاع از اندازهٔ واقعی متن می‌آید: TextSetFont + TextGetSize
//      (مرجع رسمی MQL5 — TextSetFont / TextGetSize در مستندات رسمی MQL5).
//   ۲) ردیف‌های شرطی (clocknote / sb / asia / mtfreason / dirline / entry / sl /
//      tp1..tp3 / rr) وقتی شرطشان false می‌شدند هرگز بازنویسی نمی‌شدند و متن
//      قدیمی روی چارت می‌ماند. حالا در DashEnd هر برچسبی که در همین pass
//      نوشته نشده باشد حذف می‌شود.
// اگر کاربر InpDashMaxWidth را بزرگ‌تر از ۴۰ بگذارد، ردیف بلندتر در نزدیک‌ترین
// « | » یا فاصله شکسته می‌شود؛ ولی اگر حتی با شکستن هم جا نشود، متن **بریده
// نمی‌شود** — عرض کادر باز می‌شود و شمارندهٔ سرریز بالا می‌رود تا در Journal
// دیده شود.
//====================================================================
string g_dashUsed[];      // نام ردیف‌هایی که در همین pass نوشته شدند
int    g_dashRows=0;      // تعداد ردیف‌های مصرف‌شده (با احتساب شکستن خط)
int    g_dashWidth=0;     // عرض نهایی پس‌زمینه (پیکسل)
int    g_dashHeight=0;    // ارتفاع نهایی پس‌زمینه (پیکسل)
int    g_dashMaxRowW=0;   // بلندترین ردیف این pass (پیکسل)
int    g_dashWrapped=0;   // چند ردیف شکسته شد
int    g_dashStale=0;     // چند برچسب کهنه حذف شد
int    g_dashOverflow=0;  // ردیف‌هایی که حتی پس از شکستن هم از سقف عرض رد شدند
int    g_dashX=0, g_dashY=0, g_dashLH=16;

// عرض واقعی متن با تنظیمات فونت فعلی. مقایسهٔ درست با OBJPROP_FONTSIZE:
// مستندات MQL5 می‌گوید «اندازهٔ فونت OBJ_LABEL را در ۱۰- ضرب کن تا فونت
// TextSetFont معادل شود»، پس برای size=9 عدد -90 داده می‌شود.
// اگر TextGetSize در دسترس نبود، تخمین محافظه‌کارانه برمی‌گردد تا متن خوشه‌ای
// بریده نشود (تخمین بزرگ‌تر از واقعیت انتخاب می‌شود).
int DashMeasure(const string s, int size)
{
   int n=StringLen(s);
   if(n==0) return 0;
   uint w=0,h=0;
   if(TextSetFont("Consolas", -size*10, FW_NORMAL) && TextGetSize(s,w,h) && w>0)
      return (int)w;
   // مدل پشتیبان مستند: هر کاراکتر ≈ ۰٫۶۲ × اندازهٔ فونت، به‌علاوهٔ ۲ پیکسل
   // حاشیهٔ اطمینان تا هرگز متن بریده نشود. همین مدل در
   // 05_TESTS_AND_VALIDATION/phase14_wrap.fixture.csv قفل شده است.
   return (int)MathCeil(n*size*0.62)+2;
}

// بهترین نقطهٔ شکست در نزدیک‌ترین « | » یا فاصله. ۰ = نقطهٔ مناسبی پیدا نشد.
int DashBreakIndex(const string s, int maxW, int size)
{
   int n=StringLen(s);
   int best=0;
   for(int i=1;i<n;i++)
   {
      ushort c=StringGetCharacter(s,i);
      if(c!=' ' && c!='|') continue;
      if(DashMeasure(StringSubstr(s,0,i),size)<=maxW) best=i;
      else break;                                  // عرض با طول متن یکنوا است
   }
   if(best>0) return best;
   for(int k=1;k<=n;k++)
      if(DashMeasure(StringSubstr(s,0,k),size)>maxW) return MathMax(1,k-1);
   return 0;
}

void DashPushRow(const string name, const string text, const color clr, const int size)
{
   string full="ICTv13_DASH_"+name;
   if(ObjectFind(0,full)<0) ObjectCreate(0,full,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,full,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,full,OBJPROP_XDISTANCE,g_dashX);
   ObjectSetInteger(0,full,OBJPROP_YDISTANCE,g_dashY+g_dashLH*g_dashRows);
   ObjectSetString(0,full,OBJPROP_TEXT,text);
   ObjectSetInteger(0,full,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,full,OBJPROP_FONTSIZE,size);
   ObjectSetString(0,full,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,full,OBJPROP_SELECTABLE,false);

   if(IndexInNameList(g_dashUsed,name)<0)
   {
      int k=ArraySize(g_dashUsed);
      ArrayResize(g_dashUsed,k+1);
      g_dashUsed[k]=name;
   }
   int w=DashMeasure(text,size);
   if(w>g_dashMaxRowW) g_dashMaxRowW=w;
   g_dashRows++;
}

// داشبورد COMPACT: فقط این ردیف‌ها راهنمای تصمیم تریدند؛ بقیه شمارندهٔ تشخیصی‌اند
// و در حالت COMPACT رسم نمی‌شوند (همه در CSVها هستند، پس چیزی گم نمی‌شود).
bool DashCompactSkip(const string name)
{
   if(name=="title" || name=="htf" || name=="mtfdirs" || name=="sess" ||
      name=="mtfsetup" || name=="dol" || name=="location" || name=="reversal" ||
      name=="exhaustion" || name=="setup" || name=="life" ||
      name=="dirline" || name=="entry" || name=="sl" || name=="tp1" ||
      name=="tp2" || name=="tp3" || name=="rr" || name=="revrisk")
      return false;                     // ردیف‌های تصمیم — همیشه نمایش
   if(StringFind(name,"sep")==0) return false;  // جداکننده‌ها سبک‌اند
   if(name=="mtfreason" && g_mtfConflict) return false; // فقط هنگام تضاد مهم است
   if(name=="clocknote" && g_brokerOffsetNote!="") return false; // هشدار آفست غیرعادی
   return true;                         // بقیه در COMPACT حذف
}

// ثبت یک ردیف داشبورد. نام باید ثابت باشد تا DashEnd بتواند ردیف کهنه را بشناسد.
void DashRow(const string name, const string text, const color clr, const int size=9)
{
   if(!InpShowDashboard) return;
   if(InpDashCompact && DashCompactSkip(name)) return;
   int w=DashMeasure(text,size);
   if(InpDashMaxWidth>40 && w>InpDashMaxWidth)
   {
      int cut=DashBreakIndex(text,InpDashMaxWidth,size);
      if(cut>0 && cut<StringLen(text))
      {
         string head=StringSubstr(text,0,cut);
         string tail=StringSubstr(text,cut);
         StringTrimRight(head);
         StringTrimLeft(tail);
         DashPushRow(name,head,clr,size);
         DashPushRow(name+"_cont","    "+tail,clr,size);
         g_dashWrapped++;
         return;
      }
      g_dashOverflow++;     // حتی با شکستن جا نشد: عرض باز می‌شود، متن بریده نمی‌شود
   }
   DashPushRow(name,text,clr,size);
}

void DashBegin()
{
   ArrayResize(g_dashUsed,0);
   g_dashRows=0; g_dashMaxRowW=0; g_dashWrapped=0; g_dashOverflow=0; g_dashStale=0;
   g_dashX=InpDashX; g_dashY=InpDashY;
   g_dashLH=(InpDashLineHeight>8?InpDashLineHeight:8);
}

void DashEnd()
{
   if(!InpShowDashboard) return;
   // ۱) ابعاد کادر از بلندترین ردیف واقعی؛ با گِردکردن به ۱۰ پیکسل تا لرزش
   //    رقم‌ها باعث تغییر اندازهٔ کادر در هر کندل نشود.
   int need=g_dashMaxRowW+8+16;
   int q=((need+9)/10)*10;
   if(q<140) q=140;
   g_dashWidth=q;
   int needH=g_dashLH*g_dashRows+16;
   if(needH<40) needH=40;
   g_dashHeight=needH;

   string bgName="ICTv13_DASH_BG";
   if(ObjectFind(0,bgName)<0) ObjectCreate(0,bgName,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bgName,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,bgName,OBJPROP_XDISTANCE,g_dashX-8);
   ObjectSetInteger(0,bgName,OBJPROP_YDISTANCE,g_dashY-8);
   ObjectSetInteger(0,bgName,OBJPROP_XSIZE,g_dashWidth);
   ObjectSetInteger(0,bgName,OBJPROP_YSIZE,g_dashHeight);
   ObjectSetInteger(0,bgName,OBJPROP_BGCOLOR,InpDashBg);
   ObjectSetInteger(0,bgName,OBJPROP_BACK,false);
   ObjectSetInteger(0,bgName,OBJPROP_SELECTABLE,false);

   // ۲) حذف ردیف‌های کهنه: هر برچسبی که در این pass نوشته نشده باشد
   int total=ObjectsTotal(0,-1,-1);
   for(int i=total-1;i>=0;i--)
   {
      string nm=ObjectName(0,i,-1,-1);
      if(StringFind(nm,"ICTv13_DASH_")!=0) continue;
      if(nm==bgName) continue;
      string sfx=StringSubstr(nm,StringLen("ICTv13_DASH_"));
      if(IndexInNameList(g_dashUsed,sfx)>=0) continue;
      ObjectDelete(0,nm);
      g_dashStale++;
   }
}

//====================================================================
// فاز ۳۵: نوار تک‌خطی «کجا ایستاده‌ای»
//
// چرا این شکل: کاربر خواست بدون داشبورد و بدون خواندن CSV بفهمد الان
// کجای حرکت است. منبع داده همان موتور فاز ۳۲ است (UpdateReverseRisk)،
// پس نوار هیچ محاسبهٔ موازی‌ای ندارد — فقط نمایش آخرین وضعیت کندل بسته.
//
// کانال نمایش: همان مسیر تأییدشدهٔ پنل آموزشی — OBJ_EDIT با متن خام
// (پیشفرض InpExplainRenderMode=0). دلیل: OBJ_EDIT کنترل بومی ویندوز
// است و خودش bidi/شکل‌دهی را انجام میدهد؛ تبدیل دستی روی آن «دوبار
// تبدیل» می‌سازد (ریشهٔ فاجعهٔ فاز ۲۲/۲۵ که در بند ۴-۰-۲۷ ثبت شد).
//
// پاک‌سازی: نام‌ها با پیشوند ICTv13_ هستند، پس OnDeinit با
// ObjectsDeleteAll(0,"ICTv13_") خودکار حذفشان می‌کند.
//====================================================================
void RenderRiskStrip()
{
   if(!InpShowRiskStrip)
   {
      if(g_riskStripOn)      // فقط یک بار حذف، نه در هر tick
      {
         ObjectDelete(0,"ICTv13_RSTRIP_BG");
         ObjectDelete(0,"ICTv13_RSTRIP_TXT");
         g_riskStripOn=false; g_riskStripLastText="";
      }
      return;
   }

   // فاز ۴۸ — «خط مسیر»: ردیف درجه (فاز ۴۶) و ردیف سناریوی در انتظار (فاز ۴۷)
   // در **یک** خط ادغام شدند. دلیل: هر دو یک واقعیت را دو تکه می‌گفتند و کاربر
   // باید دو ردیف را کنار هم می‌خواند تا بفهمد کجا ایستاده، کجا می‌رود و از کجا
   // برمی‌گردد. ترتیب خواندن عمدی است و همان پرسش کاربر را دنبال می‌کند:
   //   درجه و بایاس → روی چه سطحی ایستاده‌ایم → مقصد نقدینگی → شرط برگشت و نرخش.
   // قاعدهٔ RTL فاز ۴۲: برچسب‌های لاتین ابتدای ردیف می‌آیند و بقیه فارسی است.
   // متن کوتاه نگه داشته می‌شود عمداً: جزئیات کامل (امتیاز، فهرست شواهد، برد
   // تاریخی، سبد فاصله، خط پایهٔ سنجش) داخل پنل آموزشی همان ردیف است، نه روی چارت.
   // فاز ۴۹: سر ردیف از GradeTag() می‌آید تا روی نمادی که کالیبره نشده، نرخ
   // مرجع بی‌برچسب به نام اندازه‌گیری همین نماد جا نزند.
   string txt=StringFormat("%s  |  BIAS: %s  |  سطح: %s [%s]  |  ریسک برگشت: %s (%d)",
             GradeTag(), DirToStr(g_htfBias),
             g_rrLevel, g_rrLevelState, g_rrLabel, g_rrScore);

   // قطعهٔ «مسیر» از همان ماژولی می‌آید که آن را محاسبه می‌کند؛ پس یک عدد،
   // یک روایت دارد. اگر سناریوی در انتظار چیزی برای گفتن نداشته باشد،
   // نوار به همان شاهدهای همیشه‌موجود برمی‌گردد تا ردیف هیچ‌وقت خالی نماند.
   string path=PendingFragmentFa();
   if(path!="")
      txt+=path;
   else
   {
      txt+=StringFormat("  |  فاصله %.2f برابر میانگین دامنه  |  لگ %.0f درصد",
                        g_rrLevelDist, g_rrLegProg);
      if(g_hasDOL)
         txt+=StringFormat("  |  هدف: %s  |  فاصله %.2f برابر میانگین دامنه",
                           g_currentDOL.typeName, g_rrDolDist);
   }
   if(g_barSweptTowardBias)
      txt+="  |  SFP  |  نقدینگی سمت بایاس جارو شد";

   // کارایی: متن عوض نشده؟ هیچ ObjectSet و ChartRedraw ای لازم نیست.
   if(g_riskStripOn && txt==g_riskStripLastText) return;
   g_riskStripLastText=txt;

   int chartW=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
   int w=InpRiskStripWidth;
   // فاز ۴۶: قبلاً عرض نوار ثابت ۶۴۰ بود و ردیف بلندتر از آن بی‌صدا بریده
   // می‌شد (دقیقاً همان چیزی که کاربر «متن ناقص» می‌دید). حالا عرض از طول
   // واقعی متن هم حساب می‌شود و فقط به عرض چارت محدود می‌ماند.
   int need=(int)(StringLen(txt)*InpExplainFontSize*0.62)+24;
   if(need>w) w=need;
   if(chartW>20 && w>chartW-10) w=chartW-10;
   int lineH=InpExplainFontSize+11;   // همان فرمول ردیف پنل آموزشی

   string bg="ICTv13_RSTRIP_BG";
   if(ObjectFind(0,bg)<0) ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bg,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,2);
   ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,InpRiskStripY);
   ObjectSetInteger(0,bg,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,bg,OBJPROP_YSIZE,lineH+6);
   ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,clrBlack);
   ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,bg,OBJPROP_COLOR,PAL_PANEL_BORDER);
   ObjectSetInteger(0,bg,OBJPROP_BACK,false);
   ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,bg,OBJPROP_HIDDEN,true);

   // ردیف نوار از همان ExplainEditRow پنل آموزشی استفاده می‌کند تا رنگ/فونت/
   // تراز/فقط-خواندنی دقیقاً با مسیر تأییدشدهٔ فارسی یکی باشد.
   ExplainEditRow("ICTv13_RSTRIP_TXT", 8, InpRiskStripY+3, w-12, lineH,
                  RenderLine(txt,InpExplainRenderMode),
                  GradeStripColor(),
                  InpExplainFontSize);
   g_riskStripOn=true;
   ChartRedraw(0);   // فقط وقتی متن/رنگ واقعاً عوض شد
}

string RejectionStateToStr(ENUM_REJECTION_STATE state)
{
   if(state==REJECTION_FRESH) return "FRESH";
   if(state==REJECTION_TOUCHED) return "TOUCHED";
   if(state==REJECTION_INVALID) return "INVALID";
   return "UNKNOWN";
}

void RenderDashboard()
{
   if(!InpShowDashboard) return;
   // فاز ۱۴: ابعاد کادر دیگر هاردکد نیست؛ DashEnd آن را از اندازهٔ واقعی متن و
   // تعداد ردیف‌های مصرف‌شده می‌سازد. هیچ متنی بریده یا روی‌هم‌افتاده نمی‌ماند.
   DashBegin();

   DashRow("title", StringFormat("%s — ICT Assistant core v0.1", _Symbol), clrGold, 11);

   string sessTxt = (g_currentSession==SESS_ASIA)?"ASIAN KZ":(g_currentSession==SESS_LONDON)?"LONDON KZ":
                    (g_currentSession==SESS_NY_AM)?"NY AM KZ":(g_currentSession==SESS_LONDON_CLOSE)?"LONDON CLOSE":
                    (g_currentSession==SESS_NY_PM)?"NY PM KZ":"—";
   DashRow("sess", "Session: "+sessTxt, InpColorNeutral);
   // آفست تشخیص‌داده‌شده در همین خط دیده می‌شود تا کاربر بتواند پنجره‌های سشن را
   // با ساعت واقعی خودش مقایسه کند (بروکرهای ۳۰/۴۵ دقیقه هم درست نشان داده می‌شوند)
   DashRow("clock", StringFormat("NY %02d:%02d (GMT%+d) | broker GMT%+d:%02d", g_hourNYNow, g_minNYNow, g_nyOffsetHoursNow,
             g_serverGMTOffsetSeconds/3600, MathAbs(g_serverGMTOffsetSeconds%3600)/60),
             InpColorNeutral);
   // فاز ۱۵: قاعدهٔ DST بروکر و آفست استاندارد — بدون این دو، آفست تاریخی
   // (و در نتیجه پنجره‌های سشن روزهای قبل) قابل بازتولید نبود.
   DashRow("tzrule", StringFormat("TZ: rule %s | std GMT%+d:%02d | hist %s | bar delta %+d min",
             BrokerDSTRuleToStr(g_brokerDSTRule),
             g_brokerStdOffsetSeconds/3600, MathAbs(g_brokerStdOffsetSeconds%3600)/60,
             InpUseHistoricalBrokerOffset?"DST-aware":"current-offset",
             g_histOffsetDeltaMin),
             (g_histOffsetDeltaMin!=0)? clrGold : InpColorNeutral);
   // فقط وقتی یادداشت وجود دارد، ردیف نوشته می‌شود؛ در غیر این صورت DashEnd
   // خودش ردیف کهنه را پاک می‌کند (قبلᾰ این متن قدیمی تا ابد روی چارت می‌ماند).
   if(g_brokerOffsetNote!="") DashRow("clocknote", g_brokerOffsetNote, clrGold);
   if(g_silverBullet!=SB_NONE)
      DashRow("sb", "SILVER BULLET "+SBSyncLabel(), clrGold);   // فاز ۳۶: برچسب ترکیبی SB + همسویی HTF-LTF

   string amdTxt = (g_currentAMD==AMD_ACCUMULATION)?"ACCUMULATION":(g_currentAMD==AMD_MANIPULATION)?"MANIPULATION":(g_currentAMD==AMD_DISTRIBUTION)?"DISTRIBUTION":"—";
   DashRow("amd", "AMD/PO3: "+amdTxt, InpColorNeutral);
   // فاز ۳۶: AMD قیمتی — مرحلهٔ واقعی قیمت، نه فقط نگاشت سشنی
   string amdP=(g_amdPriceStage==AMD_ACCUMULATION)?"A":(g_amdPriceStage==AMD_MANIPULATION)?"M":(g_amdPriceStage==AMD_DISTRIBUTION)?"D":"—";
   DashRow("amdprice", "AMD قیمتی: "+amdP+(g_amdPriceNote!=""? " | "+g_amdPriceNote:""), clrViolet);
   if(g_asiaHigh>g_asiaLow)
      DashRow("asia", StringFormat("Asian Range: %.2f - %.2f (liquidity target)", g_asiaLow, g_asiaHigh),
                clrSlateBlue);

   DashRow("sep1","────────────────────", clrGray);
   DashRow("htf", "HTF Bias: "+DirToStr(g_htfBias), g_htfBias==DIR_BULL?InpColorBull:g_htfBias==DIR_BEAR?InpColorBear:InpColorNeutral);
   // دو ساختار داخلی، دو منبع متفاوت: یکی ترند تایم‌فریم چارت و دیگری ساختار
   // داخلی روی InpMTF (ورودی #۶۱ که قبلاً بی‌مصرف بود).
   DashRow("intd", "Internal "+EnumToString(PERIOD_CURRENT)+": "+DirToStr(g_internalDir), InpColorNeutral);
   DashRow("intdmtf", "Internal "+EnumToString(InpMTF)+": "+DirToStr(g_mtfInternalDir),
             (g_mtfInternalDir==DIR_NONE || g_mtfInternalDir==g_htfBias) ? InpColorNeutral : clrOrange);

   // MTF Status
   DashRow("mtf", "MTF: H4/H1/M15/M5/M2/M1", InpColorNeutral);
   DashRow("mtfdirs", DirToStr(g_htfBias)+" / "+DirToStr(g_mtfContext[1].externalDirection)+" / "+DirToStr(g_mtfContext[2].externalDirection)+" / "+DirToStr(g_mtfContext[3].externalDirection)+" / "+DirToStr(g_mtfContext[4].internalDirection)+" / "+DirToStr(g_mtfContext[5].internalDirection), g_mtfConflict?InpColorBear:InpColorNeutral);
   if(g_mtfConflict) DashRow("mtfreason",g_mtfConflictReason,InpColorBear);

   // آخرین Event
   string lastEvt="—"; color lastClr=InpColorNeutral;
   int ltfEventCount=0, htfEventCount=0;
   for(int i=ArraySize(g_events)-1;i>=0;i--)
   {
      if(g_events[i].isHTF) htfEventCount++;
      else
      {
         ltfEventCount++;
         if(lastEvt=="—")
         {
            lastEvt = EventTypeToStr(g_events[i].type)+" "+DirToStr(g_events[i].direction);
            lastClr = g_events[i].direction==DIR_BULL?InpColorBull:InpColorBear;
         }
      }
   }
   DashRow("lastevt","Last Event: "+lastEvt, lastClr);
   // داشبورد فول: رویدادهای ساختاری H4 جدا از رویدادهای تایم‌فریم چارت شمرده
   // می‌شوند تا هوشمندی MTF و آستانهٔ بی‌عدالتی تایم‌فریم‌ها بدون باز کردن CSV دیده شود.
   DashRow("events", StringFormat("Events: %d LTF / %d HTF (%s)", ltfEventCount, htfEventCount,
             TFShortName(InpHTF)), (htfEventCount>0)?clrGold:InpColorNeutral);

   DashRow("sep2","────────────────────", clrGray);

   // Liquidity summary
   int freshCount=0, sweptCount=0, invalidCount=0;
   for(int i=0;i<ArraySize(g_liquidity);i++)
   {
      if(g_liquidity[i].state==LSTATE_FRESH) freshCount++;
      if(g_liquidity[i].state==LSTATE_SWEPT) sweptCount++;
      if(g_liquidity[i].state==LSTATE_INVALID) invalidCount++;
   }
   DashRow("liq", StringFormat("Liquidity: %d fresh / %d swept / %d invalid", freshCount, sweptCount, invalidCount), InpColorNeutral);

   // داشبورد فول: تفکیک نقدینگی بر اساس نوع — BSL/SSL و EQH/EQL و PDH/PDL
   // بدون باز کردن CSV دیده شوند (هر سطح یک آبجکت واقعی در رجیستری است).
   int eqhN=0, eqlN=0, bslN=0, sslN=0, pdN=0, wkN=0, ipdaN=0;
   for(int i=0;i<ArraySize(g_liquidity);i++)
   {
      if(g_liquidity[i].state==LSTATE_INVALID) continue;
      ENUM_LIQ_TYPE t=g_liquidity[i].type;
      if(t==LIQ_EQH) eqhN++;
      else if(t==LIQ_EQL) eqlN++;
      if(IsHighSideLiquidity(t)) bslN++; else sslN++;
      if(t==LIQ_PDH || t==LIQ_PDL) pdN++;
      if(t==LIQ_SWING_H || t==LIQ_SWING_L) wkN++;
      if(t==LIQ_IPDA20_H || t==LIQ_IPDA20_L || t==LIQ_IPDA40_H || t==LIQ_IPDA40_L || t==LIQ_IPDA60_H || t==LIQ_IPDA60_L) ipdaN++;
   }
   DashRow("liqtype", StringFormat("LIQ types: EQH %d / EQL %d | BSL %d / SSL %d | PD %d | swing %d | IPDA %d",
             eqhN, eqlN, bslN, sslN, pdN, wkN, ipdaN), InpColorNeutral);

   // Displacement causal / energy-only
   int dCausal=0, dEnergy=0;
   for(int i=0;i<ArraySize(g_displacements);i++){ if(g_displacements[i].energyOnly) dEnergy++; else dCausal++; }
   DashRow("disp", StringFormat("Displacement: %d causal / %d energy-only", dCausal, dEnergy), InpColorNeutral);

   // FVG causal
   int fCausal=0, fTotal=ArraySize(g_fvgs);
   for(int i=0;i<fTotal;i++) if(g_fvgs[i].causal) fCausal++;
   DashRow("fvg", StringFormat("FVG: %d/%d CAUSAL", fCausal, fTotal), fCausal>0?InpColorBull:InpColorNeutral);

   // OB state summary
   int oValid=0,oBreaker=0,oMitig=0,oExtreme=0,oStandalone=0;
   for(int i=0;i<ArraySize(g_obs);i++)
   {
      if(g_obs[i].state==OB_VALID) oValid++;
      if(g_obs[i].state==OB_BREAKER) oBreaker++;
      if(g_obs[i].state==OB_MITIGATION) oMitig++;
      if(g_obs[i].isExtreme) oExtreme++;
      if(g_obs[i].isStandalone) oStandalone++;
   }
   // فاز ۱۴: این ردیف با ۶۶ کاراکتر از عرض قدیمی کادر بیرون می‌زد؛ حالا کادر
   // خودش را با عرض واقعی متن تنظیم می‌کند (یا در صورت سقف عرض، می‌شکند).
   DashRow("ob", StringFormat("OB: %d VALID / %d BREAKER / %d MITIG / %d EXTREME / %d STANDALONE", oValid, oBreaker, oMitig, oExtreme, oStandalone), InpColorNeutral);

   int fMitigated=0,fInvalid=0,fFresh=0,fIFVG=0;
   for(int i=0;i<ArraySize(g_fvgs);i++)
   {
      if(g_fvgs[i].invalidated)    fInvalid++;
      else if(g_fvgs[i].inverted)  fIFVG++;
      else if(g_fvgs[i].mitigated) fMitigated++;
      else                         fFresh++;
   }   // فاز ۱۲: شمارش گپ Implied و Micro تا بسته‌شدن دریچهٔ ابزار سنجششده باشد
   int fImplied=0, fMicro=0;
   for(int i=0;i<ArraySize(g_fvgs);i++)
   {
      if(g_fvgs[i].kind==FVGK_IMPLIED) fImplied++;
      else if(g_fvgs[i].kind==FVGK_MICRO) fMicro++;
   }
   DashRow("fvgstate", StringFormat("FVG: %d FRESH / %d MIT / %d iFVG / %d EXP | IMP %d / MIC %d", fFresh, fMitigated, fIFVG, fInvalid, fImplied, fMicro), fFresh>0?InpColorBull:InpColorNeutral);

   // داشبورد فول: مخازن تحلیلگر — سوئینگ‌ها، Displacement، نقدینگی مورب و رنج
   // به‌صورت عددی دیده شوند تا سلامت رجیستری‌ها بدون CSV قابل کنترل باشد.
   int swH=0, swL=0;
   for(int i=0;i<ArraySize(g_swingsLTF);i++){ if(g_swingsLTF[i].isHigh) swH++; else swL++; }
   DashRow("regs", StringFormat("Registry: swings %d (H%d/L%d) | disp %d | trendlines %d%s",
             ArraySize(g_swingsLTF), swH, swL, ArraySize(g_displacements), ArraySize(g_trendlines),
             g_rangeOk? StringFormat(" | range %s–%s (%d/%d)", PriceS(g_rangeLow), PriceS(g_rangeHigh),
                                     g_rangeLowTouches, g_rangeHighTouches) : ""),
             InpColorNeutral);
   DashRow("sep3","────────────────────", clrGray);

   // DOL — با امتیاز و نوع واقعی سطح (#۴۸)
   if(g_hasDOL)
      DashRow("dol", StringFormat("DOL: %s (%s) | %s | %.2f ATR | score %d",
                 DoubleToString(g_currentDOL.price,_Digits),
                 g_currentDOL.hierarchyOk?"External":"Internal", g_currentDOL.typeName,
                 g_currentDOL.distATR, g_currentDOL.score), InpColorNeutral);
   else
      DashRow("dol", (g_htfBias==DIR_NONE? "DOL: WAITING_H4_BIAS" : "DOL: WAITING_DOL")
                 +(g_dolRejectReason!=""?" | "+g_dolRejectReason:""), InpColorNeutral);

   // Location از همان close کندل تحلیلی و همان لگ واقعی ساخته می‌شود (#۴۵)
   string locationText="Location: WAITING_LEG";
   if(g_leg.valid)
   {
      locationText=StringFormat("Location: %s | EQ %.2f | leg %s",
                                (g_analysisClose>=g_leg.eq?"PREMIUM":"DISCOUNT"), g_leg.eq, DirToStr(g_leg.dir));
   }
   DashRow("location",locationText,InpColorNeutral);
   if(g_leg.valid)
      DashRow("leg", StringFormat("Leg %s: %.2f→%.2f (%.2f ATR) | %s → %s",
                 DirToStr(g_leg.dir), g_leg.low, g_leg.high, g_leg.sizeATR,
                 TimeToString(g_leg.startTime,TIME_DATE|TIME_MINUTES),
                 TimeToString(g_leg.endTime,TIME_DATE|TIME_MINUTES)), InpColorNeutral);
   else
      DashRow("leg", "Leg: "+g_leg.reject, InpColorNeutral);
   DashRow("mtfsetup", "MTF gate: "+g_setup.status, g_setup.active?InpColorBull:InpColorNeutral);
   color exhaustionClr=(g_exhaustion.state==EXH_REVERSAL_CONFIRMED)?clrGold:
                       (g_exhaustion.state==EXH_WATCH || g_exhaustion.state==EXH_MICRO_PULLBACK || g_exhaustion.state==EXH_RANGE_TRANSITION)?InpColorBear:InpColorNeutral;
   DashRow("exhaustion", "Exhaustion: "+ExhaustionStateToStr(g_exhaustion.state)+" "+IntegerToString(g_exhaustion.score)+"/"+IntegerToString(g_exhaustion.maxScore), exhaustionClr);

   // فاز ۱۲ (#۳ #۹): ساختار داخلی همان تایم‌فریم مالک + سن و فاز روند
   DashRow("trend", StringFormat("Trend: %s | age %d HTF bars | Internal %s: %s",
             TrendPhaseToStr(g_trend.phase), g_trend.ageBars, EnumToString(InpHTF), DirToStr(g_htfInternalDir)),
             (g_htfInternalDir==DIR_NONE || g_htfInternalDir==g_htfBias)?InpColorNeutral:clrOrange);
   // فاز ۱۲ (#۴۷ #۶۷ #۶۸)
   DashRow("quality", StringFormat("Model: %s | Quality %d/10 | POI %s (%d)",
             EntryModelToStr(g_setup.entryModel), (g_setup.active?g_setup.quality:g_setup.quality),
             PoiKindToStr(g_setup.poiKind), g_setup.poiScore),
             g_setup.active?InpColorBull:InpColorNeutral);

   // فاز ۱۱: دروازهٔ برگشت تأییدشده — جدا از Exhaustion تا تفاوت «هشدار» و «تأیید» دیده شود
   color reversalClr = g_reversal.confirmed ? (g_reversal.dir==DIR_BULL?InpColorBull:InpColorBear)
                                            : (g_reversal.armed?clrOrange:InpColorNeutral);
   DashRow("reversal", StringFormat("Reversal: %s | gate %s | -> %s | SMR %d/%d",
             g_reversal.state,
             (g_reversal.armed? DoubleToString(g_reversal.levelPrice,_Digits):"—"),
             DirToStr(g_reversal.confirmed? g_reversal.dir : OppositeDir(g_reversal.snapBias)),
             g_reversal.smrScore, g_reversal.smrMax), reversalClr);

   // Rejection Block Status
   // فازهای ۱۶–۲۱: ردیف‌های خانواده‌های جدید
   int sdFresh=0, sdTested=0, sdFlipped=0;
   for(int i=0;i<ArraySize(g_sd);i++)
   {
      if(g_sd[i].state==SDS_FRESH) sdFresh++;
      else if(g_sd[i].state==SDS_TESTED) sdTested++;
      else if(g_sd[i].state==SDS_FLIPPED) sdFlipped++;
   }
   DashRow("wyck", StringFormat("Wyckoff: %s", (g_wyckPhaseReason==""? "—":g_wyckPhaseReason)), InpColorNeutral);
   DashRow("sdfam", StringFormat("S/D zones: %d (FRESH %d / TESTED %d / FLIPPED %d)",
             ArraySize(g_sd), sdFresh, sdTested, sdFlipped), InpColorNeutral);
   DashRow("brooks", "Brooks: "+(g_brooksNote==""? "—":g_brooksNote), InpColorNeutral);
   DashRow("rtm", "RTM: "+(g_rtmNote==""? "—":g_rtmNote), InpColorNeutral);
   DashRow("profile", "Profile: "+(g_profileNote==""? "—":g_profileNote), InpColorNeutral);

   // داشبورد فول: IPDA و POI رجیستری — پیش از این فقط در CSV دیده می‌شدند
   DashRow("ipda", "IPDA: "+(g_ipdaOk? g_ipdaNote : (InpDetectIPDA? g_ipdaNote+" | OFF-data":"disabled")),
             g_ipdaOk?InpColorNeutral:clrGray);
   int poiValid=0; long poiBest=0; int poiBestScore=-1; string poiBestKind="";
   for(int i=0;i<ArraySize(g_poi);i++)
   {
      if(!g_poi[i].valid) continue;
      poiValid++;
      if(g_poi[i].score>poiBestScore){ poiBestScore=g_poi[i].score; poiBest=g_poi[i].id; poiBestKind=PoiKindToStr(g_poi[i].kind); }
   }
   DashRow("poi", StringFormat("POI: %d valid / %d total | best %s #%s (%d)",
             poiValid, ArraySize(g_poi), poiBestKind, IdToStr(poiBest), poiBestScore),
             poiValid>0?InpColorNeutral:clrGray);
   DashRow("atrbars", StringFormat("ATR(%d): %s | close %s | bars %d | build %s",
             InpATR_Period, (g_analysisATR>0.0? PriceS(g_analysisATR):"—"),
             (g_analysisClose>0.0? PriceS(g_analysisClose):"—"),
             InpHistoryScanBars, g_buildStamp), clrGray);

   int rFresh=0, rTouched=0, rInvalid=0;
   for(int i=0; i<ArraySize(g_rejections); i++)
   {
      if(g_rejections[i].rejectionState==REJECTION_FRESH) rFresh++;
      else if(g_rejections[i].rejectionState==REJECTION_TOUCHED) rTouched++;
      else if(g_rejections[i].rejectionState==REJECTION_INVALID) rInvalid++;
   }
   DashRow("rbstate", StringFormat("Rejection Block: %d FRESH / %d TOUCHED / %d INVALID", rFresh, rTouched, rInvalid), InpColorNeutral);

   // داشبورد فول: بهداشت نمایش — چند آبجکت روی چارت زنده/فریز است و چند ردیف
   // کهنه/شکسته حذف شده؛ برای تشخیص شلوغی چارت بدون شمارش دستی Ctrl+B.
   // (در COMPACT حذف می‌شود — شمارش ObjectsTotal در هر کندل هم هزینه دارد.)
   if(!InpDashCompact)
   {
      int chartLayerObjs=0;
      int to_=ObjectsTotal(0,-1,-1);
      for(int i=0;i<to_;i++)
         if(IsLayerObjectName(ObjectName(0,i,-1,-1))) chartLayerObjs++;
      DashRow("hygiene", StringFormat("Chart: %d live objs | frozen %d | dash stale %d / wrapped %d",
                chartLayerObjs, ArraySize(g_frozen), g_dashStale, g_dashWrapped), clrGray);
   }
   // فاز ۱۴: delimiter تکراری (sep5 و sep4 پشت‌سرهم) حذف شد.
   DashRow("sep4","────────────────────", clrGray);

   // فاز ۳۲: ریسک برگشت — در چه نقطه‌ای از حرکت هستیم و خطر ورودِ خلاف جهت چقدر است.
   // امتیاز، مجموع وزن‌های مستند است (در پنل تفکیک می‌شود)؛ «درصد» نیست. درصدِ واقعی
   // از CSV همین ثبت با ابزار tools/Report-ReverseRisk.ps1 روی تاریخچه شمرده می‌شود.
   DashRow("revrisk", StringFormat("ریسک برگشت: %s (%d) | نزدیک‌ترین سطح: %s [%s] | فاصله %.2f برابر میانگین دامنه | لگ %.0f درصد | هدف %s | فاصله %.2f برابر میانگین دامنه%s",
             g_rrLabel, g_rrScore, g_rrLevel, g_rrLevelState, DoubleToString(g_rrLevelDist,2),
             g_rrLegProg, (g_hasDOL? g_currentDOL.typeName : "-"), DoubleToString(g_rrDolDist,2),
             (g_barSweptTowardBias? " | SFP | نقدینگی سمت بایاس جارو شد":"")),
             g_rrScore>=50? InpColorBear : (g_rrScore>=25? InpColorNeutral : InpColorBull));

   // Setup / Signal — از g_setup که خودش از Core پر شده می‌خواند
   color setupClr = g_setup.active ? (g_setup.dir==DIR_BULL?InpColorBull:InpColorBear) : InpColorNeutral;
   DashRow("setup","Setup: "+g_setup.status, setupClr);
   // فاز ۱۵ (#۶۶): چرخهٔ عمر ستاپ — ابطال فقط با بستهٔ قیمت فراتر از SL
   if(InpTrackSetupLifecycle)
   {
      color lifeClr = (g_setupLifeState=="INVALIDATED")? InpColorBear
                    : (g_setupLifeState=="TP1_HIT")? InpColorBull
                    : (g_setupLifeState=="TRACKING")? InpColorNeutral : InpFrozenColor;
      string lifeTxt = (g_setupLifeState=="INVALIDATED")? "INVALIDATED" : "IDLE";
      if(g_setupLifeState=="TP1_HIT")  lifeTxt="TP1 HIT";
      else if(g_setupLifeState=="TRACKING") lifeTxt="TRACKING";
      else if(g_setupLifeState=="IDLE")     lifeTxt="IDLE";
      DashRow("life", StringFormat("Life: %s | armed %d / invalid %d / TP1 %d%s",
                lifeTxt, g_setupArmedCount, g_setupInvalidCount, g_setupTP1Count,
                (g_setupLifeState=="INVALIDATED" && g_setupLifeSL>0.0)?
                  StringFormat(" | SL %s | close %s", PriceS(g_setupLifeSL), PriceS(g_setupInvalidPrice)) : ""),
                lifeClr);
   }
   if(g_setup.active)
   {
      DashRow("dirline", (g_setup.dir==DIR_BULL?"LONG":"SHORT"), setupClr, 12);
      DashRow("entry", StringFormat("Entry: %s | %s", DoubleToString(g_setup.entry,_Digits), g_setup.zoneSource), InpDashText);
      DashRow("sl",    StringFormat("SL:    %s | risk %.2f (%.2f ATR)", DoubleToString(g_setup.sl,_Digits), g_setup.risk, (g_analysisATR>0.0? g_setup.risk/g_analysisATR : 0.0)), InpColorBear);
      DashRow("tp1",   StringFormat("TP1:   %s (1:%.1f)", DoubleToString(g_setup.tp1,_Digits), g_setup.rrTP1), InpColorBull);
      DashRow("tp2",   StringFormat("TP2:   %s (1:%.1f)", DoubleToString(g_setup.tp2,_Digits), g_setup.rrTP2), InpColorBull);
      DashRow("tp3",   StringFormat("TP3:   %s = DOL (1:%.2f)", DoubleToString(g_setup.tp3,_Digits), g_setup.rrTP3), InpColorBull);
      DashRow("rr",    StringFormat("R:R real 1:%.2f | min 1:%.1f | golden %.2f", g_setup.rr, InpMinRR, g_setup.golden), InpDashText);
   }

   // فاز ۱۴: پس‌زمینه به اندازهٔ واقعی متن، و حذف هر ردیف کهنه‌ای که در این
   // pass نوشته نشده باشد (Entry/SL/TP ستاپ قبلی، SILVER BULLET قدیمی، ...).
   DashEnd();
}

