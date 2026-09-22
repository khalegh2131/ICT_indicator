//====================================================================
// موتور نمایش فارسی — مستقل از رندر متاتریدر
// MT5 متن RTL را چپ‌به‌راست می‌کشد، پس خودمان:
//   ۱) حروف را به شکل‌های چسبیده (Presentation Forms) تبدیل می‌کنیم
//   ۲) ترتیب را به ترتیب بصری (راست‌به‌چپ) برمی‌گردانیم
//   ۳) واژه‌های لاتین/عددی را دست‌نخورده و در ابتدای خط نگه می‌داریم
//====================================================================
int g_faBase[]={0x0621,0x0622,0x0623,0x0624,0x0625,0x0626,0x0627,0x0628,0x0629,0x062A,0x062B,0x062C,0x062D,0x062E,0x062F,0x0630,0x0631,0x0632,0x0633,0x0634,0x0635,0x0636,0x0637,0x0638,0x0639,0x063A,0x0641,0x0642,0x0643,0x0644,0x0645,0x0646,0x0647,0x0648,0x0649,0x064A,0x067E,0x0686,0x0698,0x06A9,0x06AF,0x06C0,0x06CC};
int g_faIsol[]={0xFE80,0xFE81,0xFE83,0xFE85,0xFE87,0xFE89,0xFE8D,0xFE8F,0xFE93,0xFE95,0xFE99,0xFE9D,0xFEA1,0xFEA5,0xFEA9,0xFEAB,0xFEAD,0xFEAF,0xFEB1,0xFEB5,0xFEB9,0xFEBD,0xFEC1,0xFEC5,0xFEC9,0xFECD,0xFED1,0xFED5,0xFED9,0xFEDD,0xFEE1,0xFEE5,0xFEE9,0xFEED,0xFEEF,0xFEF1,0xFB56,0xFB7A,0xFB8A,0xFB8E,0xFB92,0xFBA4,0xFBFC};
int g_faFina[]={0xFE80,0xFE82,0xFE84,0xFE86,0xFE88,0xFE8A,0xFE8E,0xFE90,0xFE94,0xFE96,0xFE9A,0xFE9E,0xFEA2,0xFEA6,0xFEAA,0xFEAC,0xFEAE,0xFEB0,0xFEB2,0xFEB6,0xFEBA,0xFEBE,0xFEC2,0xFEC6,0xFECA,0xFECE,0xFED2,0xFED6,0xFEDA,0xFEDE,0xFEE2,0xFEE6,0xFEEA,0xFEEE,0xFEF0,0xFEF2,0xFB57,0xFB7B,0xFB8B,0xFB8F,0xFB93,0xFBA5,0xFBFD};
int g_faInit[]={0,0,0,0,0,0xFE8B,0,0xFE91,0,0xFE97,0xFE9B,0xFE9F,0xFEA3,0xFEA7,0,0,0,0,0xFEB3,0xFEB7,0xFEBB,0xFEBF,0xFEC3,0xFEC7,0xFECB,0xFECF,0xFED3,0xFED7,0xFEDB,0xFEDF,0xFEE3,0xFEE7,0xFEEB,0,0,0xFEF3,0xFB58,0xFB7C,0,0xFB90,0xFB94,0,0xFBFE};
int g_faMedi[]={0,0,0,0,0,0xFE8C,0,0xFE92,0,0xFE98,0xFE9C,0xFEA0,0xFEA4,0xFEA8,0,0,0,0,0xFEB4,0xFEB8,0xFEBC,0xFEC0,0xFEC4,0xFEC8,0xFECC,0xFED0,0xFED4,0xFED8,0xFEDC,0xFEE0,0xFEE4,0xFEE8,0xFEEC,0,0,0xFEF4,0xFB59,0xFB7D,0,0xFB91,0xFB95,0,0xFBFF};

int FasIndex(ushort c)
{
   int n=ArraySize(g_faBase);
   for(int i=0;i<n;i++) if(g_faBase[i]==(int)c) return i;
   return -1;
}

// شکل‌دهی منطقی: هر حرف فارسی به شکل درست (منفصل/آغازی/میانی/پایانی) تبدیل می‌شود
string ShapePersianLogical(string s)
{
   int n=StringLen(s);
   string shaped="";
   for(int i=0;i<n;i++)
   {
      ushort c=StringGetCharacter(s,i);
      int idx=FasIndex(c);
      if(idx<0){ shaped+=ShortToString(c); continue; }

      int prevIdx=-1, nextIdx=-1;
      if(i>0)   prevIdx=FasIndex(StringGetCharacter(s,i-1));
      if(i+1<n) nextIdx=FasIndex(StringGetCharacter(s,i+1));
      // اتصال فقط وقتی مجاز است که حرف قبلی اتصال‌دهنده به راست
      // و حرف فعلی/بعدی اتصال‌دهنده به چپ باشد. شرط قبلی هر حرف بعدی
      // را متصل فرض می‌کرد و شکل حروف را خراب می‌کرد.
      bool prevConnects = (prevIdx>=0 && g_faInit[prevIdx]!=0 && g_faFina[idx]!=g_faIsol[idx]);
      bool nextConnects = (nextIdx>=0 && g_faInit[idx]!=0 && g_faFina[nextIdx]!=g_faIsol[nextIdx]);

      int form;
      if(prevConnects && nextConnects && g_faMedi[idx]!=0) form=g_faMedi[idx];
      else if(prevConnects && g_faFina[idx]!=0)            form=g_faFina[idx];
      else if(nextConnects && g_faInit[idx]!=0)            form=g_faInit[idx];
      else                                                  form=g_faIsol[idx];
      shaped+=ShortToString((ushort)form);
   }
   return shaped;
}

// ---- جهت هر کاراکتر: +1 راست‌به‌چپ، -1 چپ‌به‌راست (لاتین/رقم)، 0 بی‌طرف ----
int FaCharDir(ushort c)
{
   if(c>=0x06F0 && c<=0x06F9) return -1;   // ارقام فارسی
   if(c>=0x0660 && c<=0x0669) return -1;   // ارقام عربی-هندی
   if(IsPersianChar(c))       return 1;
   if((c>='0'&&c<='9')||(c>='A'&&c<='Z')||(c>='a'&&c<='z')) return -1;
   return 0;
}

// هنگام معکوس‌کردن یک run راست‌به‌چپ، جفت‌های براکت باید آینه شوند
ushort FaMirror(ushort c)
{
   if(c=='(') return (ushort)')';   if(c==')') return (ushort)'(';
   if(c=='[') return (ushort)']';   if(c==']') return (ushort)'[';
   if(c=='{') return (ushort)'}';   if(c=='}') return (ushort)'{';
   if(c=='<') return (ushort)'>';   if(c=='>') return (ushort)'<';
   return c;
}

//====================================================================
// ترتیب بصری برای رندرگر MT5
// از buildهای اخیر، رندرگر آبجکت‌های چارت bidi را انجام نمی‌دهد و متن
// راست‌به‌چپ را چپ‌به‌راست می‌کشد (گزارش رسمی انجمن MQL5). پس خودمان
// رشته را به «ترتیب بصری» تبدیل می‌کنیم تا یک رندرگر LTR عیناً همان
// تصویر درست را بکشد.
//   ورودی : متن منطقی (mode 1) یا متنِ شکل‌داده (mode 2)
//   الگوریتم: قاعدهٔ N1/N2 از UBA برای کاراکترهای بی‌طرف، سپس چیدن runها
//             از آخر به اول و معکوس‌کردن runهای راست‌به‌چپ + آینه‌کردن براکت.
//====================================================================
string VisualOrderForLtrEngine(string s)
{
   StringTrimRight(s);
   int n=StringLen(s);
   if(n==0) return s;

   int dir[]; ArrayResize(dir,n);
   bool anyRtl=false;
   for(int i=0;i<n;i++)
   {
      dir[i]=FaCharDir(StringGetCharacter(s,i));
      if(dir[i]>0) anyRtl=true;
   }
   if(!anyRtl) return s;              // خط تمام‌لاتین: دست‌نخورده بماند

   // کاراکترهای بی‌طرف جهت همسایه‌های هم‌جهت خود را می‌گیرند؛
   // در غیر این صورت جهت پایه (راست‌به‌چپ) را می‌گیرند.
   for(int i=0;i<n;i++)
   {
      if(dir[i]!=0) continue;
      int j=i;
      while(j<n && dir[j]==0) j++;
      int before=(i>0)?dir[i-1]:1;
      int after =(j<n)?dir[j]:1;
      int res=(before==after)?before:1;
      for(int k=i;k<j;k++) dir[k]=res;
      i=j;
   }

   string out="";
   int j=n-1;
   while(j>=0)
   {
      int d=dir[j];
      int start=j;
      while(start>=0 && dir[start]==d) start--;
      string run=StringSubstr(s,start+1,j-start);
      if(d>0)
      {
         string rev="";
         for(int k=0;k<StringLen(run);k++)
            rev=ShortToString(FaMirror(StringGetCharacter(run,k)))+rev;
         run=rev;
      }
      out+=run;
      j=start;
   }
   return out;
}

// آیا خط حداقل یک حرف فارسی دارد؟ فقط این خط‌ها نیاز به جهت RTL دارند.
bool HasPersianText(string s)
{
   for(int i=0;i<StringLen(s);i++)
      if(IsPersianChar(StringGetCharacter(s,i))) return true;
   return false;
}

// آماده‌سازی یک خط برای رندر روی چارت.
//   0 = متن خام منطقی (فقط برای عیب‌یابی روی buildی که bidi دارد)
//   1 = ترتیب بصری، بدون شکل‌دهی حروف
//   2 = شکل‌دهی حروف + ترتیب بصری   ← پیش‌فرض درست روی buildهای فعلی MT5
//   3 = پیچیدن در RLE..PDF (نسخهٔ قدیمی؛ روی buildهای جدید MT5 اثر ندارد)
string RenderLine(string text, int mode)
{
   if(mode==0)
   {
      // فاز ۴۱ — جهت پایهٔ خط را قطعی می‌کنیم. U+200F (RIGHT-TO-LEFT MARK)
      // یک کاراکتر «قوی» راست‌به‌چپ است و کنترل بومی جهت پایه را با قاعدهٔ
      // P2/P3 از همان اولین کاراکتر قوی می‌گیرد. اگر کنترل خودش همین را
      // انتخاب کرده بود، هیچ تغییری نمی‌دهد؛ اگر چپ‌به‌راست بود، ترتیب
      // واژه‌ها را درست می‌کند. خودش چاپ نمی‌شود (کاراکتر بی‌عرض).
      if(HasPersianText(text)) return ShortToString(0x200F)+text;
      return text;
   }
   if(mode==3)
   {
      if(HasPersianText(text)) return ShortToString(0x202B)+text+ShortToString(0x202C);
      return text;
   }
   if(!HasPersianText(text)) return text;
   string shaped=(mode==2) ? ShapePersianLogical(text) : text;
   return VisualOrderForLtrEngine(shaped);
}

void ExpAdd(string text, color clr)
{
   int n=ArraySize(g_expLines);
   ArrayResize(g_expLines,n+1);
   ArrayResize(g_expLineColors,n+1);
   // فاز ۴۱ — قاعدهٔ RTL (توضیح کامل در 25_Explain.mqh): هر واژهٔ لاتینی که
   // بعد از واژهٔ فارسی بیاید به ابتدای خط منتقل می‌شود تا جملهٔ فارسی به دو
   // قطعهٔ جابه‌جا شکسته نشود. ارقام دست‌نخورده می‌مانند (درون قطعهٔ RTL می‌مانند).
   g_expLines[n]=InpExplainLatinFirst? RtlSafe(text) : text;
   g_expLineColors[n]=clr;
}

// یک خط آماده: قاعدهٔ RTL اعمال می‌شود و اگر با این جابه‌جایی از پهنای پنل
// بلندتر شد، بلوک لاتین در خط خودش و متن فارسی در خط‌های بعدی می‌نشیند تا
// هیچ خطی از عرض EDIT بیرون نزند و بریده نشود.
void ExpEmitLine(string line, color clr, int maxChars)
{
   string outLine = InpExplainLatinFirst? RtlSafe(line) : line;
   int sepPos=StringFind(outLine," | ");
   if(sepPos>0 && StringLen(outLine)>maxChars)
   {
      ExpAdd(StringSubstr(outLine,0,sepPos), clr);
      ExpAdd(StringSubstr(outLine,sepPos+3), clr);
      return;
   }
   ExpAdd(outLine, clr);
}

// شکستن متن طولانی به خطوط کوتاه (تا در یک خط نریزد)
void ExpAddWrapped(string text, color clr)
{
   int maxChars = MathMax(24, InpExplainPanelWidth/8);
   string words[];
   int wc=StringSplit(text,' ',words);
   string line="";
   for(int i=0;i<wc;i++)
   {
      if(StringLen(words[i])==0) continue;
      string candidate = (StringLen(line)==0)? words[i] : line+" "+words[i];
      if(StringLen(candidate)>maxChars && StringLen(line)>0)
      {
         ExpEmitLine(line, clr, maxChars);
         line=words[i];
      }
      else line=candidate;
   }
   if(StringLen(line)>0) ExpEmitLine(line, clr, maxChars);
}

// ---------------- تبدیل زمان/قیمت به پیکسل با تابع دقیق MT5 ----------------
// ChartTimePriceToXY مقیاس عمودی، شیفت افقی، shift چارت و عرض محور قیمت را
// درست حساب می‌کند. تبدیل دستی قبلی این‌ها را نادیده می‌گرفت و در نتیجه موس
// خیلی وقت‌ها روی آبجکت موردنظر نمی‌افتاد.
bool ExplainTimePriceToXY(datetime t, double price, int &x, int &y)
{
   if(t<=0) return false;
   return ChartTimePriceToXY(0,0,t,price,x,y);
}

// برای خط افقی فقط Y لازم است: یک زمان داخل محدودهٔ دید می‌دهیم تا
// تبدیل قیمت به پیکسل درست انجام شود.
datetime ExplainVisibleTime()
{
   int firstBar=(int)ChartGetInteger(0,CHART_FIRST_VISIBLE_BAR,0);
   if(firstBar<0) firstBar=0;
   datetime t=iTime(_Symbol,PERIOD_CURRENT,firstBar);
   if(t<=0) t=iTime(_Symbol,PERIOD_CURRENT,0);
   if(t<=0) t=TimeCurrent();
   return t;
}

double DistToSegment(double px, double py, double x1, double y1, double x2, double y2)
{
   double dx=x2-x1, dy=y2-y1;
   double len2=dx*dx+dy*dy;
   if(len2<=0.0) return MathSqrt((px-x1)*(px-x1)+(py-y1)*(py-y1));
   double t=((px-x1)*dx+(py-y1)*dy)/len2;
   if(t<0) t=0;
   if(t>1) t=1;
   double cx=x1+t*dx, cy=y1+t*dy;
   return MathSqrt((px-cx)*(px-cx)+(py-cy)*(py-cy));
}

// ---------------------------------------------------------------------------
// فاز ۲۲ — علت دوم «هیچ آبجکتی توضیح نمی‌دهد» (ایراد واقعی hit-test):
// `ChartTimePriceToXY` وقتی برمی‌گرداند **false** که نقطه در محدودهٔ دید نباشد.
// ناحیه‌های FVG/OB/S-D از چند کندل قبل شروع می‌شوند و به سمت راست کشیده می‌شوند؛
// پس روی چارت زوم‌شده لبهٔ چپ تقریباً همیشه بیرون از دید است و شرط
// `if(ExplainTimePriceToXY(...) && ExplainTimePriceToXY(...))` هیچ‌وقت درست
// نمی‌شد → هیچ باکسی قابل hover نبود (در حالی که نصف باکس روی صفحه دیده می‌شود).
// دو helper زیر تبدیل را حتی بیرون از محدودهٔ دید ادامه می‌دهند:
//   ExplainTimeToX  — خطی بر مبنای پهنای واقعی هر کندل (px/bar) که از دو کندل دید به‌دست می‌آید
//   ExplainPriceToY — اگر قیمت بیرون دید باشد، Y به بالا/پایین کادر کلمپ می‌شود (نه شکست)
// ---------------------------------------------------------------------------
bool ExplainTimeToX(datetime t, int &x)
{
   x=0;
   if(t<=0) return false;
   int firstBar=(int)ChartGetInteger(0,CHART_FIRST_VISIBLE_BAR,0);
   if(firstBar<0) firstBar=0;
   double pRef=iClose(_Symbol,PERIOD_CURRENT,firstBar);
   if(pRef<=0.0) pRef=iClose(_Symbol,PERIOD_CURRENT,0);
   if(pRef<=0.0) return false;
   datetime tRef=iTime(_Symbol,PERIOD_CURRENT,firstBar);
   if(tRef<=0) return false;
   int xRef=0,yRef=0;
   if(!ChartTimePriceToXY(0,0,tRef,pRef,xRef,yRef)) return false;
   int sec=PeriodSeconds(PERIOD_CURRENT);
   if(sec<=0) return false;
   // پهنای هر کندل (پیکسل) از یک کندل دورتر در همان محدودهٔ دید
   int farShift=firstBar-8; if(farShift<0) farShift=0;
   datetime tFar=iTime(_Symbol,PERIOD_CURRENT,farShift);
   int xFar=0,yFar=0;
   if(tFar<=0 || tFar==tRef || !ChartTimePriceToXY(0,0,tFar,pRef,xFar,yFar))
   {
      // بدون مرجع دوم: فقط نقطهٔ دید را برمی‌گردانیم (رفتار قبلی)
      x=xRef;
      return (t==tRef);
   }
   double barsRef=(double)(tFar-tRef)/(double)sec;      // منفی: tFar جدیدتر است
   double pxPerBar=((double)xFar-(double)xRef)/barsRef; // مثبت
   double barsAhead=((double)t-(double)tRef)/(double)sec;
   x=xRef+(int)MathRound(pxPerBar*barsAhead);
   return true;
}

int ExplainPriceToY(datetime tRef, double price, double refPrice, int chartH)
{
   int x=0,y=0;
   if(price>0.0 && ChartTimePriceToXY(0,0,tRef,price,x,y)) return y;
   // بیرون از محدودهٔ دید: بالای کادر یا پایین آن کلمپ می‌شود تا هندسهٔ
   // ناحیه (و در نتیجه hit-test) از بین نرود.
   if(refPrice<=0.0) return (int)MathRound(chartH/2.0);
   return (price>refPrice)? -60 : chartH+60;
}

// نزدیک‌ترین آبجکت به موس (فقط آبجکت‌های لایهٔ تحلیل، نه داشبورد/پنل)
//
// فاز ۴۴ — قاعدهٔ قطعی انتخاب در هم‌پوشانی (قبلاً ترتیب ساخت آبجکت‌ها تعیین‌کننده
// بود، یعنی نتیجه به ترتیب تصادفی چرخش `ObjectsTotal` وابسته بود):
//   ۱) کم‌ترین فاصله تا موس؛
//   ۲) اگر فاصله‌ها در یک حد باشند، **کوچک‌ترین ناحیه** برنده است، چون خاص‌تر
//      است (گپ ریز داخل یک اردر بلاک بزرگ باید گپ را بگوید، نه بلاک را)؛
//   ۳) اگر ناحیه‌ها هم‌اندازه بودند، نام کوچک‌تر الفباتیکی برنده می‌شود تا
//      نتیجه حتی بین دو اجرا با ترتیب مختلف نیز یکسان بماند.
// همین قاعده در آزمون بدون‌موس فاز ۴۴ سنجیده می‌شود.
string HitTestExplainObject(int mx, int my)
{
   string best="";
   double bestDist=1e18;
   double bestArea=1e18;
   double tol=(double)InpExplainHoverTolPx;
   if(tol<4.0) tol=4.0;
   datetime tVis=ExplainVisibleTime();
   int chartH=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   double refPrice=(g_analysisClose>0.0)? g_analysisClose : iClose(_Symbol,PERIOD_CURRENT,0);
   int total=ObjectsTotal(0,-1,-1);
   for(int i=0;i<total;i++)
   {
      string nm=ObjectName(0,i,-1,-1);
      if(StringFind(nm,"ICTv13_")!=0) continue;
      if(StringFind(nm,"ICTv13_DASH_")==0) continue;
      if(StringFind(nm,"ICTv13_EXP_")==0)  continue;
      long otype=ObjectGetInteger(0,nm,OBJPROP_TYPE);
      int x1=0,y1=0,x2=0,y2=0;
      double dist=1e18;
      double area=0.0;   // فاز ۴۴: مساحت کادر پیکسلی، برای قاعدهٔ ۲ انتخاب قطعی
      if(otype==OBJ_HLINE)
      {
         double price=ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
         int yy=ExplainPriceToY(tVis,price,refPrice,chartH);
         if(price>0.0) dist=MathAbs((double)yy-(double)my);
      }
      else if(otype==OBJ_RECTANGLE)
      {
         double p0=ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
         double p1=ObjectGetDouble(0,nm,OBJPROP_PRICE,1);
         datetime t0=(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,0);
         datetime tt1=(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,1);
         if(ExplainTimeToX(t0,x1) && ExplainTimeToX(tt1,x2))
         {
            y1=ExplainPriceToY(tVis,p0,refPrice,chartH);
            y2=ExplainPriceToY(tVis,p1,refPrice,chartH);
            double yTop=MathMin((double)y1,(double)y2), yBot=MathMax((double)y1,(double)y2);
            double xL=MathMin((double)x1,(double)x2),   xR=MathMax((double)x1,(double)x2);
            area=(xR-xL)*MathMax(yBot-yTop,0.0);
            // فاز ۲۵ — ریشهٔ «پنل همه‌جا باز می‌شود»: ExplainPriceToY قیمتِ
            // بیرون از دید را به −۶۰ یا chartH+۶۰ کلمپ می‌کند. اگر **هر دو**
            // قیمت یک ناحیه بیرون از دید باشند (ناحیهٔ کاملاً بالای صفحه یا
            // پایین صفحه)، کلمپ جعبه را از −۶۰ تا chartH+۶۰ می‌کشید و در نتیجه
            // کل ارتفاع چارت «داخلِ ناحیه» حساب می‌شد → با هر حرکت موس پنل باز
            // می‌شد. حالا ناحیه‌ای که هیچ بخش دیدنی ندارد اصلاً کاندید نمی‌شود
            // (این با ناحیهٔ واقعاً بزرگ که بالا تا پایین دید را می‌پوشاند فرق
            // دارد؛ آن یکی درست است و همان‌طور می‌ماند).
            bool verticallyVisible=(yBot>=-tol && yTop<=(double)chartH+tol);
            if(verticallyVisible)
            {
               if(my>=yTop-tol && my<=yBot+tol && mx>=xL-tol && mx<=xR+tol)
                  dist=0.0;   // داخل ناحیه: اولویت با ناحیه است نه خطِ عبوری
               else
               {
                  double dx=MathMax(MathMax(xL-(double)mx,(double)mx-xR),0.0);
                  double dy=MathMax(MathMax(yTop-(double)my,(double)my-yBot),0.0);
                  dist=MathSqrt(dx*dx+dy*dy);
               }
            }
         }
      }
      else if(otype==OBJ_TREND)
      {
         double p0=ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
         double p1=ObjectGetDouble(0,nm,OBJPROP_PRICE,1);
         datetime t0=(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,0);
         datetime tt1=(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,1);
         if(ExplainTimeToX(t0,x1) && ExplainTimeToX(tt1,x2))
         {
            y1=ExplainPriceToY(tVis,p0,refPrice,chartH);
            y2=ExplainPriceToY(tVis,p1,refPrice,chartH);
            dist=DistToSegment((double)mx,(double)my,(double)x1,(double)y1,(double)x2,(double)y2);
         }
      }
      else if(otype==OBJ_TEXT)
      {
         double p0=ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
         datetime t0=(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,0);
         if(ExplainTimeToX(t0,x1))
         {
            y1=ExplainPriceToY(tVis,p0,refPrice,chartH);
            double dx=(double)x1-(double)mx;
            double dy=(double)y1-(double)my;
            dist=MathSqrt(dx*dx+dy*dy);
         }
      }
      // فاز ۲۵: شعاع پذیرش از ۴ برابر تحمل به ۲ برابر کم شد تا پنل با
      // حرکت عادی موس روی فضای خالی هم باز نشود (روی خط حدود ~۱۶px).
      // فاز ۴۴: انتخاب قطعی (فاصله ← مساحت ← نام)
      if(dist>tol*2.0) continue;
      bool better=false;
      if(dist<bestDist-0.5) better=true;
      else if(MathAbs(dist-bestDist)<=0.5)
      {
         if(area<bestArea-0.5) better=true;
         else if(MathAbs(area-bestArea)<=0.5 && (best=="" || nm<best)) better=true;
      }
      if(better){ bestDist=dist; bestArea=area; best=nm; }
   }
   return best;
}

// ---------------- lookup در Registryها ----------------
bool FindLiquidityById(long id, LiquidityObj &out)
{
   for(int i=0;i<ArraySize(g_liquidity);i++)
      if(g_liquidity[i].id==id){ out=g_liquidity[i]; return true; }
   return false;
}
bool FindFVGById(long id, FVGObj &out)
{
   for(int i=0;i<ArraySize(g_fvgs);i++)
      if(g_fvgs[i].id==id){ out=g_fvgs[i]; return true; }
   return false;
}
bool FindOBById(long id, OBObj &out)
{
   for(int i=0;i<ArraySize(g_obs);i++)
      if(g_obs[i].id==id){ out=g_obs[i]; return true; }
   return false;
}
bool FindRejectionById(long id, RejectionObj &out)
{
   for(int i=0;i<ArraySize(g_rejections);i++)
      if(g_rejections[i].id==id){ out=g_rejections[i]; return true; }
   return false;
}
bool FindEventById(long id, StructureEvent &out)
{
   for(int i=0;i<ArraySize(g_events);i++)
      if(g_events[i].id==id){ out=g_events[i]; return true; }
   return false;
}

string PriceS(double p) { return DoubleToString(p,_Digits); }

//====================================================================
// فاز ۴۲ — واژه‌نامهٔ فارسی برای مقادیر کدگذاری‌شده
//====================================================================
// چرا لازم است: خط‌های آموزشی با StringFormat ساخته می‌شوند و جای %s غالباً
// یک **کد لاتین** می‌نشیند (BULLISH، FRESH، WAITING_H4_BIAS، ...). همان واژهٔ
// لاتین است که جملهٔ فارسی را به دو قطعهٔ جابه‌جا می‌شکند و خواننده متن را
// وارونه می‌بیند. پس هر کدی که وسط جمله می‌آید باید معادل فارسی داشته باشد؛
// اگر خود کد لازم بود، در **ابتدای خط** یا در یک خط مستقل لاتین می‌آید.
string TfFa(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "یک‌دقیقه‌ای";
      case PERIOD_M2:  return "دو‌دقیقه‌ای";
      case PERIOD_M3:  return "سه‌دقیقه‌ای";
      case PERIOD_M4:  return "چهار‌دقیقه‌ای";
      case PERIOD_M5:  return "پنج‌دقیقه‌ای";
      case PERIOD_M6:  return "شش‌دقیقه‌ای";
      case PERIOD_M10: return "ده‌دقیقه‌ای";
      case PERIOD_M12: return "دوازده‌دقیقه‌ای";
      case PERIOD_M15: return "پانزده‌دقیقه‌ای";
      case PERIOD_M20: return "بیست‌دقیقه‌ای";
      case PERIOD_M30: return "سی‌دقیقه‌ای";
      case PERIOD_H1:  return "یک‌ساعته";
      case PERIOD_H2:  return "دو‌ساعته";
      case PERIOD_H3:  return "سه‌ساعته";
      case PERIOD_H4:  return "چهار‌ساعته";
      case PERIOD_H6:  return "شش‌ساعته";
      case PERIOD_H8:  return "هشت‌ساعته";
      case PERIOD_H12: return "دوازده‌ساعته";
      case PERIOD_D1:  return "روزانه";
      case PERIOD_W1:  return "هفتگی";
      case PERIOD_MN1: return "ماهانه";
   }
   return "تایم‌فریم جاری";
}

string DirFa(ENUM_DIRECTION d)
{
   if(d==DIR_BULL) return "صعودی";
   if(d==DIR_BEAR) return "نزولی";
   return "بی‌جهت";
}

string LiqTypeFa(ENUM_LIQ_TYPE t)
{
   switch(t)
   {
      case LIQ_PDH:        return "سقف روز قبل";
      case LIQ_PDL:        return "کف روز قبل";
      case LIQ_PWH:        return "سقف هفتهٔ قبل";
      case LIQ_PWL:        return "کف هفتهٔ قبل";
      case LIQ_EQH:        return "سقف‌های برابر";
      case LIQ_EQL:        return "کف‌های برابر";
      case LIQ_SESSION_H:  return "سقف پنجرهٔ سشن";
      case LIQ_SESSION_L:  return "کف پنجرهٔ سشن";
      case LIQ_RANGE_H:    return "سقف رنج";
      case LIQ_RANGE_L:    return "کف رنج";
      case LIQ_IPDA20_H:   return "سقف چرخهٔ بیست‌روزه";
      case LIQ_IPDA20_L:   return "کف چرخهٔ بیست‌روزه";
      case LIQ_IPDA40_H:   return "سقف چرخهٔ چهل‌روزه";
      case LIQ_IPDA40_L:   return "کف چرخهٔ چهل‌روزه";
      case LIQ_IPDA60_H:   return "سقف چرخهٔ شصت‌روزه";
      case LIQ_IPDA60_L:   return "کف چرخهٔ شصت‌روزه";
      case LIQ_TRENDLINE_H: return "نقدینگی مورب سقفی";
      case LIQ_TRENDLINE_L: return "نقدینگی مورب کفی";
   }
   return "سوئینگ تأییدشده";
}

string ObStateFa(ENUM_OB_STATE s)
{
   if(s==OB_VALID)      return "معتبر و دست‌نخورده";
   if(s==OB_MITIGATED)  return "لمس شده (تازگی از دست رفته)";
   if(s==OB_BROKEN)     return "شکسته‌شده";
   if(s==OB_BREAKER)    return "تبدیل به بلوک شکننده";
   if(s==OB_MITIGATION) return "تبدیل به بلوک تخفیف";
   return "بی‌اعتبار";
}

string RejectionStateFa(ENUM_REJECTION_STATE s)
{
   if(s==REJECTION_FRESH)   return "تازه و دست‌نخورده";
   if(s==REJECTION_TOUCHED) return "لمس شده";
   return "بی‌اعتبار";
}

string ExhaustionStateFa(ENUM_EXHAUSTION_STATE s)
{
   switch(s)
   {
      case EXH_TRENDING:                  return "روند سالم و ادامه‌دار";
      case EXH_EXTENDING:                 return "روند در حال کشش";
      case EXH_WATCH:                     return "زیر نظر برای فرسودگی";
      case EXH_MICRO_PULLBACK:            return "پول‌بک ریز";
      case EXH_MICRO_REVERSAL_CONFIRMED:  return "برگشت ریز تأییدشده";
      case EXH_RANGE_TRANSITION:          return "گذار به رنج";
      case EXH_REVERSAL_CONFIRMED:        return "برگشت تأییدشده";
   }
   return "بی‌طرف";
}

string TrendPhaseFa(ENUM_TREND_PHASE p)
{
   switch(p)
   {
      case PHASE_INITIATION:   return "آغاز حرکت";
      case PHASE_EXPANSION:    return "انبساط";
      case PHASE_DISTRIBUTION: return "توزیع";
      case PHASE_REVERSAL:     return "برگشت";
   }
   return "نامعلوم";
}

string PoiKindFa(ENUM_POI_KIND k)
{
   switch(k)
   {
      case POIK_FVG:       return "گپ قیمتی";
      case POIK_OB:        return "اردر بلاک";
      case POIK_BREAKER:   return "بلوک شکننده";
      case POIK_MITIGATION:return "بلوک تخفیف";
      case POIK_REJECTION: return "بلوک پس‌زدگی";
      case POIK_TRENDLINE: return "نقدینگی مورب";
      case POIK_RANGE:     return "مرز رنج";
   }
   return "بدون نوع";
}

string EntryModelFa(ENUM_ENTRY_MODEL m)
{
   switch(m)
   {
      case MODEL_ICT2022:     return "مدل کلاسیک: جارو، سپس تغییر ساختار، سپس ورود روی گپ";
      case MODEL_BOS_FVG_OB:  return "مدل شکست ساختار، سپس گپ، سپس اردر بلاک";
      case MODEL_SWEEP_ENTRY: return "مدل ورود روی جاروی نقدینگی";
      case MODEL_OTE_ONLY:    return "مدل ورود فقط در باند بهینهٔ فیبوناچی";
   }
   return "مدل ورودی انتخاب نشده";
}

string RTMEventFa(ENUM_RTM_EVENT e)
{
   switch(e)
   {
      case RTM_COMPRESSION: return "فشردگی (ذخیرهٔ انرژی)";
      case RTM_EXPANSION:   return "انبساط (آزادسازی انرژی)";
      case RTM_TRAP:        return "تلهٔ ورود (شکار استاپ)";
      case RTM_MOMENTUM:    return "کندل ممنتوم";
      case RTM_ENGULF:      return "پوشش بدنهٔ کندل قبلی";
      case RTM_REJECTION:   return "پس‌زدگی از سطح";
   }
   return "رویداد رفتاری";
}

string AMTDayTypeFa(uint t)
{
   switch(t)
   {
      case 1: return "روز روندی";
      case 2: return "نوسان طبیعی روزانه";
      case 3: return "روز معمول";
      case 4: return "روز خنثی (هر دو طرف ارزش اولیه شکسته)";
      case 5: return "روز بی‌روند (ارزش اولیه حفظ شده)";
   }
   return "نامعلوم";
}

string AMTOpenTypeFa(uint t)
{
   switch(t)
   {
      case 1: return "باز شدن رانشی بیرون رنج روز قبل";
      case 2: return "آزمون ارزش اولیه و سپس حرکت";
      case 3: return "رد ارزش اولیه و بازگشت";
      case 4: return "باز شدن درون ارزش";
   }
   return "نامعلوم";
}

string SDKindFa(ENUM_SD_KIND k)
{
   switch(k)
   {
      case SDK_RBR:    return "رالی، پایه، رالی";
      case SDK_DBD:    return "ریزش، پایه، ریزش";
      case SDK_RBD:    return "رالی، پایه، ریزش";
      case SDK_DBR:    return "ریزش، پایه، رالی";
      case SDK_SUPPLY: return "ناحیهٔ عرضهٔ ساده";
   }
   return "ناحیهٔ تقاضای ساده";
}

string WyckoffEventFa(ENUM_WYCK_EVENT e)
{
   switch(e)
   {
      case WE_SC:         return "اوج فروش (تسلیم فروشندگان)";
      case WE_BC:         return "اوج خرید (هیجان خریداران)";
      case WE_AR:         return "رالی خودکار (واکنش نخست)";
      case WE_ST:         return "آزمون دوم محدوده";
      case WE_SPRING:     return "اسپرینگ (شکار استاپ کف رنج)";
      case WE_UPTHRUST:   return "آپ‌تراست (شکار استاپ سقف رنج)";
      case WE_SOS:        return "نشانهٔ قدرت";
      case WE_SOW:        return "نشانهٔ ضعف";
      case WE_LPS:        return "آخرین نقطهٔ حمایت";
      case WE_LPSY:       return "آخرین نقطهٔ عرضه";
      case WE_TEST:       return "آزمون کم‌دامنهٔ مرز";
      case WE_ABSORPTION: return "جذب سفارش در مرز رنج";
      case WE_PS:         return "حمایت مقدماتی";
      case WE_PSY:        return "عرضهٔ مقدماتی";
   }
   return "رویداد وایکاف";
}

string QTPhaseFa(ENUM_QT_PHASE p)
{
   switch(p)
   {
      case QT_Q1_ACCUM:    return "ربع نخست: انباشت (۱۸:۰۰ تا ۰۰:۰۰ نیویورک)";
      case QT_Q2_MANIP:    return "ربع دوم: دستکاری (۰۰:۰۰ تا ۰۶:۰۰ نیویورک)";
      case QT_Q3_DISTRIB:  return "ربع سوم: توزیع (۰۶:۰۰ تا ۱۲:۰۰ نیویورک)";
      case QT_Q4_REVERSAL: return "ربع چهارم: ادامه یا برگشت (۱۲:۰۰ تا ۱۸:۰۰ نیویورک)";
   }
   return "ربع نامعلوم";
}

// کد کوتاه لاتین سطح نقدینگی — فقط برای **عنوان پنل** و ابتدای خط، جایی که
// واژهٔ لاتین به عنوان لنگر دوزبانه می‌آید و وسط جملهٔ فارسی نمی‌افتد.
string LiqTypeCode(ENUM_LIQ_TYPE t)
{
   switch(t)
   {
      case LIQ_PDH:        return "PDH";
      case LIQ_PDL:        return "PDL";
      case LIQ_PWH:        return "PWH";
      case LIQ_PWL:        return "PWL";
      case LIQ_EQH:        return "EQH";
      case LIQ_EQL:        return "EQL";
      case LIQ_SWING_H:    return "SWING-H";
      case LIQ_SWING_L:    return "SWING-L";
      case LIQ_SESSION_H:  return "SESSION-H";
      case LIQ_SESSION_L:  return "SESSION-L";
      case LIQ_RANGE_H:    return "RANGE-H";
      case LIQ_RANGE_L:    return "RANGE-L";
      case LIQ_IPDA20_H:   return "IPDA20-H";
      case LIQ_IPDA20_L:   return "IPDA20-L";
      case LIQ_IPDA40_H:   return "IPDA40-H";
      case LIQ_IPDA40_L:   return "IPDA40-L";
      case LIQ_IPDA60_H:   return "IPDA60-H";
      case LIQ_IPDA60_L:   return "IPDA60-L";
      case LIQ_TRENDLINE_H: return "TRENDLINE-H";
      case LIQ_TRENDLINE_L: return "TRENDLINE-L";
   }
   return "LIQ";
}

string ObKindFa(ENUM_OB_KIND k)
{
   switch(k)
   {
      case OBK_CORE:             return "هسته‌ای (هم‌زمان با گپ و جارو)";
      case OBK_STANDALONE:       return "تنها (بدون هم‌پوشانی با گپ)";
      case OBK_EXTREME:          return "اکستریم (روی مبدأ دامنهٔ معامله‌گری)";
      case OBK_MITIGATION_BLOCK: return "بلوک تخفیف";
   }
   return "نامشخص";
}

string WyckoffEventCode(ENUM_WYCK_EVENT e)
{
   switch(e)
   {
      case WE_SC:         return "SC";
      case WE_BC:         return "BC";
      case WE_AR:         return "AR";
      case WE_ST:         return "ST";
      case WE_SPRING:     return "SPRING";
      case WE_UPTHRUST:   return "UPTHRUST";
      case WE_SOS:        return "SOS";
      case WE_SOW:        return "SOW";
      case WE_LPS:        return "LPS";
      case WE_LPSY:       return "LPSY";
      case WE_TEST:       return "TEST";
      case WE_ABSORPTION: return "ABSORPTION";
      case WE_PS:         return "PS";
      case WE_PSY:        return "PSY";
   }
   return "EVENT";
}

string RTMEventCode(ENUM_RTM_EVENT e)
{
   switch(e)
   {
      case RTM_COMPRESSION: return "COMPRESSION";
      case RTM_EXPANSION:   return "EXPANSION";
      case RTM_TRAP:        return "TRAP";
      case RTM_MOMENTUM:    return "MOMENTUM";
      case RTM_ENGULF:      return "ENGULFING";
      case RTM_REJECTION:   return "REJECTION";
   }
   return "EVENT";
}

// کد وضعیت موتور ستاپ → یک جملهٔ فارسی کوتاه. متن پنل به‌جای چاپ خودِ کد
// (که لاتین است و جمله را می‌شکند) همین جمله را نشان می‌دهد و کد را در یک خط
// مستقل لاتین می‌آورد.
string SetupStatusFa(string code)
{
   if(code=="NONE")                    return "موتور هنوز ارزیابی نکرده است";
   if(code=="READY")                   return "ستاپ کامل و آماده است";
   if(code=="SETUP_ENGINE_DISABLED")   return "موتور ستاپ با ورودی مربوطه خاموش است";
   if(code=="WAITING_H4_BIAS")         return "بایاس تایم‌فریم مالک هنوز تأیید نشده است";
   if(code=="WAITING_DOL")             return "هدف نقدینگی هم‌جهت با فاصلهٔ کافی پیدا نشد";
   if(code=="WAITING_MTF_CONFLICT")    return "تضاد بین تایم‌فریم‌ها فعال است";
   if(code=="WAITING_H1_CONTEXT")      return "کانتکست یک‌ساعته هم‌جهت نیست";
   if(code=="WAITING_M15_CONTEXT")     return "کانتکست پانزده‌دقیقه‌ای هم‌جهت نیست";
   if(code=="WAITING_M5_SETUP")        return "ستاپ پنج‌دقیقه‌ای هم‌جهت نیست";
   if(code=="WAITING_M2_CONFIRMATION") return "تأیید اجرایی دودقیقه‌ای نرسیده است";
   if(code=="WAITING_M1_CONFIRMATION") return "تأیید اجرایی یک‌دقیقه‌ای نرسیده است";
   if(code=="WAITING_ICT_CYCLE")       return "هیچ چرخهٔ اثبات‌شده‌ای در جهت بایاس نیست";
   if(code=="WAITING_PROVEN_SWEEP_MSS")return "چرخه هست ولی جارو و جابه‌جایی کامل نیست";
   if(code=="WAITING_FRESH_CYCLE")     return "چرخه قدیمی‌تر از پنجرهٔ مجاز است";
   if(code=="WAITING_DEALING_LEG")     return "دامنهٔ معامله‌گری معتبر نیست";
   if(code=="WAITING_LEG_DIRECTION")   return "آخرین دامنه مخالف بایاس است";
   if(code=="WAITING_RETRACE")         return "قیمت به ناحیهٔ ورود برنگشته است";
   if(code=="WAITING_DISCOUNT_OTE")    return "ناحیهٔ ورود در باند بهینهٔ نیمهٔ تخفیف نیست";
   if(code=="WAITING_PREMIUM_OTE")     return "ناحیهٔ ورود در باند بهینهٔ نیمهٔ گران نیست";
   if(code=="WAITING_ZONE_GEOMETRY")   return "هندسهٔ ناحیهٔ ورود نامعتبر است";
   if(code=="WAITING_SL_INVALID")      return "فاصلهٔ ورود تا حد ضرر صفر یا منفی می‌شد";
   if(code=="WAITING_DOL_DIRECTION")   return "هدف نقدینگی در جهت معامله نیست";
   if(code=="WAITING_RR_LOW")          return "نسبت سود به ریسک از حداقل کمتر است";
   if(StringFind(code,"WAITING_ENTRY_MODEL")==0) return "هیچ مدل ورودی شرط‌هایش را کامل نکرد";
   if(StringFind(code,"WAITING_QUALITY_LOW")==0) return "امتیاز کیفیت از حداقل کمتر است";
   return "دلیل نامشخص — کد فنی در خط بعدی آمده است";
}

// دلیل رد دامنهٔ معامل‌گری → فارسی
string LegRejectFa(string code)
{
   if(code=="H4_DATA_NOT_READY")            return "دادهٔ کافی تایم‌فریم مالک برای پیوت‌یابی آماده نیست";
   if(code=="NOT_ENOUGH_ALTERNATING_PIVOTS")return "سقف و کف تأییدشدهٔ متناوب کافی پیدا نشد";
   if(code=="ZERO_RANGE")                   return "دامنهٔ دامنهٔ معامله‌گری صفر است";
   if(code=="LEG_TOO_SMALL")                return "اندازهٔ دامنه از حداقل نسبت به میانگین دامنه کمتر است";
   return "دلیل نامشخص — کد فنی در خط بعدی آمده است";
}

// ---------------- تولید توضیح برای هر نوع آبجکت ----------------
void ExplainLiquidity(const LiquidityObj &l)
{
   bool highSide=IsHighSideLiquidity(l.type);
   g_expTitle="LIQ "+LiqTypeCode(l.type)+" #"+IdToStr(l.id);
   ExpAddWrapped(StringFormat("چیست: سطح نقدینگی %s در قیمت %s — نوع سطح: %s",
                 highSide?"سمت خرید (بالای قیمت)":"سمت فروش (زیر قیمت)",
                 PriceS(l.price), LiqTypeFa(l.type)), clrWhite);
   ExpAdd(StringFormat("جایگاه در سلسله‌مراتب: %s",
          l.scope==SCOPE_EXTERNAL?"خارجی — روی مبدأ دامنهٔ معامله‌گری":"داخلی — درون دامنهٔ معامله‌گری"), clrAqua);
   ExpAdd(StringFormat("تایم‌فریم منبع: %s", TfFa(l.isHTF?InpHTF:PERIOD_CURRENT)), clrAqua);

   if(l.type==LIQ_PDH||l.type==LIQ_PDL||l.type==LIQ_PWH||l.type==LIQ_PWL)
      ExpAddWrapped(StringFormat("چرا تشکیل شد: سقف یا کف دورهٔ قبلی که پیش از %s بسته شده بود — نقدینگی طبیعی بازار",
                    TimeToString(l.time,TIME_DATE|TIME_MINUTES)), clrAqua);
   else if(l.type==LIQ_EQH||l.type==LIQ_EQL)
   {
      ExpAddWrapped(StringFormat("چرا تشکیل شد: دو یا چند سویینگ تأییدشده با فاصلهٔ کمتر از تلورانس تنظیم‌شده (%.0f پوینت یا %.2f برابر میانگین دامنه) و یک پس‌رفت جداکننده بین‌شان — استخر نقدینگی",
                    InpEQ_Tolerance_Points, InpEQ_ToleranceATR), clrAqua);
      ExpAddWrapped("شرط جدایی: دو عضو باید یک سویینگ مخالف در میانه داشته باشند تا «دو تست مستقل» باشند، نه «یک سقف کشیده»", clrSilver);
      ExpAddWrapped(StringFormat("حداقل عمق جدایی برابر تلورانس است و با مقدار %.2f سخت‌تر می‌شود", InpEQ_MinSeparationATR), clrSilver);
      ExpAdd("InpEQ_MinSeparationATR — آستانهٔ سخت‌گیری عمق جدایی", clrSilver);
   }
   else if(l.type==LIQ_SESSION_H||l.type==LIQ_SESSION_L)
      ExpAddWrapped(StringFormat("چرا تشکیل شد: رنج یک پنجرهٔ سشن بسته‌شدهٔ قبلی در %s به‌عنوان هدف نقدینگی ثبت شد",
                    TimeToString(l.time,TIME_DATE|TIME_MINUTES)), clrAqua);
   else
      ExpAddWrapped("چرا تشکیل شد: یک سویینگ تأییدشده (پیوت با تأیید کندل‌های دو طرف) که به‌عنوان نقدینگی ثبت شده است", clrAqua);

   ExpAdd("وضعیت سطح: "+(l.state==LSTATE_FRESH?"دست‌نخورده":
          (l.state==LSTATE_SWEPT?"جارو شده در "+TimeToString(l.sweptTime,TIME_DATE|TIME_MINUTES)
                               :"بی‌اعتبار — قیمت با بسته‌شدن از سطح عبور کرد")),
          l.state==LSTATE_FRESH?clrLime:(l.state==LSTATE_SWEPT?clrOrange:clrDimGray));

   ExpAddWrapped("شکست واقعی: اگر کندل کامل بالای یا زیر این سطح ببندد، سطح از حالت نقدینگی خارج و به مرز ساختاری تبدیل می‌شود و شکست ساختار در همان جهت ثبت می‌شود", clrLime);
   ExpAddWrapped("جارو (فیک): اگر فقط فتیله از سطح بگذرد و کندل دوباره پشت آن ببندد، این برداشت نقدینگی است نه شکست، و زمینهٔ حرکت مخالف می‌شود", clrOrange);
   ExpAddWrapped("چه چیزی آن را باطل می‌کند: بسته‌شدن کندل از سمت مخالف سطح (سطح دیگر هدف معتبر نیست)؛ یا تغییر بایاس مالک", clrTomato);
   ExpAddWrapped(StringFormat("کنترل خودت: کندل %s را روی تایم‌فریم %s باز کن؛ باید در آن محدوده دو سویینگ تقریباً هم‌سطح ببینی؛ قیمت سطح %s",
                 TimeToString(l.time,TIME_DATE|TIME_MINUTES), TfFa(PERIOD_CURRENT), PriceS(l.price)), clrSilver);
   ExpAdd("LIQ #"+IdToStr(l.id)+" — ICT_Assistant_Canonical_Explain.csv", clrSilver);
}

void ExplainStructureEvent(const StructureEvent &e)
{
   g_expTitle="EVENT "+EventTypeToStr(e.type)+" #"+IdToStr(e.id)+" "+(e.direction==DIR_BULL?"BULLISH":"BEARISH");
   ExpAddWrapped(StringFormat("چیست: %s روی تایم‌فریم %s؛ کندل تأیید: %s؛ قیمت سطح شکسته‌شده: %s",
                 (e.type==EVT_MSS?"تغییر ساختار تأییدشده":(e.type==EVT_CHOCH?"تغییر جهت احتمالی":"ادامهٔ روند")),
                 TfFa(e.isHTF?InpHTF:PERIOD_CURRENT), TimeToString(e.time,TIME_DATE|TIME_MINUTES), PriceS(e.price)), clrWhite);
   ExpAddWrapped("چرا تشکیل شد: کندل بسته‌شده سطح سویینگ محافظت‌شدهٔ مقابل را رد کرد و یک جابه‌جایی زنجیرشده با آن ثبت شد", clrAqua);
   ExpAdd("Swing #"+IdToStr(e.brokenSwingId)+" | Protected #"+IdToStr(e.protectedSwingId)
          +" | Displacement #"+IdToStr(e.displacementId)+" | Sweep #"+IdToStr(e.sweepId), clrSilver);

   if(e.type==EVT_MSS)
      ExpAddWrapped("معنی: تغییر ساختار با شاهد کامل — جارو، جابه‌جایی و بسته‌شدن فراتر از سطح؛ معتبرترین حالت برای شروع ستاپ", clrLime);
   else if(e.type==EVT_CHOCH)
      ExpAddWrapped("هشدار: فقط جهت شکسته شده ولی جابه‌جایی کافی ثبت نشده؛ این هنوز یک کاندید است و به‌تنهایی ستاپ نمی‌سازد", clrOrange);
   else
      ExpAddWrapped("معنی: ادامهٔ روند فعلی — شکست در جهت روند، نه تغییر روند", clrAqua);

   ExpAddWrapped(StringFormat("شرط عددی جابه‌جایی: نسبت بدنه به دامنه باید %.2f و بیشتر و نسبت دامنه به میانگین دامنه %.2f و بیشتر باشد؛ در غیر این صورت ارتقا به تغییر ساختار تأییدشده انجام نمی‌شود",
                 InpDisp_BodyRatio, InpDisp_RangeVsAvg), clrSilver);
   ExpAdd("InpDisp_BodyRatio / InpDisp_RangeVsAvg — آستانهٔ جابه‌جایی", clrSilver);
   ExpAddWrapped("چه چیزی آن را باطل می‌کند: بسته‌شدن کندل از سطح محافظت‌شدهٔ مقابل؛ یا ساخته‌شدن یک تغییر ساختار مخالف بعدی", clrTomato);
   ExpAddWrapped(StringFormat("کنترل خودت: روی کندل %s وایسا؛ اگر کندل کامل بالای %s بسته شده شکست درست ثبت شده و اگر فقط فتیله بوده ثبت اشتباه است",
                 TimeToString(e.time,TIME_DATE|TIME_MINUTES), PriceS(e.price)), clrSilver);
   ExpAdd("ICT_Assistant_V13_Events_v1.csv — رویداد شمارهٔ "+IdToStr(e.id), clrSilver);
}

// فاز ۲۸: نام دقیق هر نوع گپ. قبل از این، همه‌چیز «FVG» نامیده می‌شد و در نتیجه
// پنل آموزشی هم تعریف غلط می‌داد (مثلاً برای Implied همان تعریف Standard).
string FVGKindToStr(ENUM_FVG_KIND k)
{
   // فاز ۴۱: این نام‌ها فقط در **عنوان** پنل می‌آیند و باید لاتین و خالص
   // باشند؛ عنوانی که فارسی وسطش بیاید، به دو قطعهٔ جابه‌جا می‌شکند. متن
   // آموزشی فارسی در FVGKindFa() است.
   if(k==FVGK_IMPLIED)       return "IMPLIED";
   if(k==FVGK_MICRO)         return "MICRO";
   if(k==FVGK_VOL_IMBALANCE) return "VOLUME IMBALANCE";
   return "STANDARD";
}
// همان نام‌ها به فارسی، برای خط‌های آموزشی بدنه (بدون واژهٔ لاتین وسط جمله).
string FVGKindFa(ENUM_FVG_KIND k)
{
   if(k==FVGK_IMPLIED)       return "گپ ضمنی (از میانهٔ فتیله‌ها کشیده شده)";
   if(k==FVGK_MICRO)         return "گپ ریز روی تایم‌فریم پایین‌تر";
   if(k==FVGK_VOL_IMBALANCE) return "گپ بین بدنه‌ها با فتیله‌های روی‌هم‌افتاده";
   return "گپ استاندارد سه‌کندلی";
}
// فاز ۳۶: نام‌گذاری ICT — BISI (Buy-side Imbalance / Sell-side Inefficiency) =
// FVG صعودی · SIBI (Sell-side Imbalance / Buy-side Inefficiency) = FVG نزولی.
// منبع: innercircletrader.net — «ICT SIBI and BISI Explained»؛ اسم جهت‌دار است،
// نه محاسبهٔ جدا: همان گپ سه‌کندلی با دو نام تجاری.
string FVGBisiSibiStr(ENUM_DIRECTION d)
{
   return (d==DIR_BULL)? "BISI (Buy-side Imbalance / Sell-side Inefficiency)"
                       : "SIBI (Sell-side Imbalance / Buy-side Inefficiency)";
}
// وضعیت چرخهٔ عمر گپ، به فارسی — قبلاً برچسب‌های FRESH/MITIGATED/iFVG وسط
// جملهٔ فارسی می‌افتادند و متن را ناخوانا می‌کردند (فاز ۴۱).
string FVGStateFa(const FVGObj &f)
{
   if(f.invalidated) return "بی‌اعتبار / منقضی";
   if(f.inverted)    return "پولاریتی برعکس (به گپ معکوس تبدیل شده)";
   if(f.ceTouched)   return "میانهٔ ناحیه لمس شده (به‌قدر کافی پر شده)";
   if(f.mitigated)   return "فقط لبهٔ ناحیه لمس شده";
   return "تازه و دست‌نخورده";
}

// فاز ۴۳ — یک رشتهٔ واحد برای «جهت + نقش» گپ، تا پنل، ردیف CSV و آزمون رفتاری
// نتوانند سه چیز متفاوت بگویند. قاعده: جهت تولد اول نوشته می‌شود و اگر وارونه
// شده باشد، نقش فعلی بعدش می‌آید؛ پس خواننده هیچ‌وقت جهت و وضعیت را قاطی نمی‌کند.
string FVGPolarityReport(const FVGObj &f)
{
   string birth=(f.direction==DIR_BULL? "BULLISH":"BEARISH");
   if(!f.inverted) return birth;
   return birth+" -> "+DirToStr(FVGActiveDir(f))+" (iFVG)";
}

void ExplainFVG(const FVGObj &f)
{
   g_expTitle="ZONE "+FVGKindToStr(f.kind)+" #"+IdToStr(f.id)+" "+FVGPolarityReport(f);
   // فاز ۴۱ — بازنویسی متن آموزشی: هر خط یا تمام‌لاتین است، یا لاتینش اول
   // جمله آمده و بقیه یکپارچه فارسی. دیگر هیچ واژهٔ انگلیسی وسط جملهٔ فارسی
   // نمی‌افتد (ریشهٔ «فارسی به‌هم‌ریخته»). ارقام وسط جمله مشکلی ندارند.
   ExpAdd(FVGBisiSibiStr(f.direction)+" — نام دوم همین گپ در این مکتب", clrAqua);   // فاز ۳۶
   ExpAddWrapped("چیست: ناحیهٔ عدم‌تعادل قیمت — جایی که یک طرف بازار سفارش بیشتری خورده و قیمت با سرعت از آن گذشته؛ نوع این گپ: "+FVGKindFa(f.kind), clrWhite);
   ExpAddWrapped(StringFormat("مرزهای ناحیه: از %.2f تا %.2f ؛ میانهٔ ناحیه (سطح تصمیم): %.2f ؛ زمان تشکیل: %s",
                 f.bottom,f.top,f.ce,TimeToString(f.time,TIME_DATE|TIME_MINUTES)), clrWhite);
   ExpAdd("شناسهٔ کندل جابه‌جایی سازنده: "+IdToStr(f.displacementId), clrSilver);
   // تعریف هر نوع، جداگانه — منبع: LuxAlgo Library (Fair Value Gap / Implied FVG / Consequent Encroachment).
   if(f.kind==FVGK_STANDARD)
      ExpAddWrapped("چطور ساخته شد: فتیلهٔ کندل اول و سوم هم‌پوشانی ندارند و همین شکاف، ناحیهٔ گپ است — کندل میانی همان کندل جابه‌جایی است", clrAqua);
   else if(f.kind==FVGK_IMPLIED)
      ExpAddWrapped("چطور ساخته شد: گپ واقعی چاپ نشده؛ ناحیه از میانهٔ فتیلهٔ کندل اول تا میانهٔ فتیلهٔ کندل سوم کشیده شده و فتیله‌ها روی هم می‌افتند", clrAqua);
   else if(f.kind==FVGK_VOL_IMBALANCE)
      ExpAddWrapped("چطور ساخته شد: شکاف بین بدنهٔ کندل اول و سوم، در حالی که فتیله‌ها روی هم می‌افتند؛ شاهدش ضعیف‌تر از گپ واقعی است", clrAqua);
   else
   {
      ExpAdd(EnumToString(f.tf)+" — تایم‌فریم منبع این گپ", clrAqua);
      ExpAddWrapped("چطور ساخته شد: گپ ریزی که روی تایم‌فریم پایین‌تر شکل گرفته و به این چارت منتقل شده", clrAqua);
   }
   ExpAdd("پشتوانهٔ ساختاری: "+(f.causal? "دارد — کندل جابه‌جایی سازنده به یک شکست ساختار زنجیر شده"
                                         : "ندارد — کندل جابه‌جایی هنوز به شکست ساختار زنجیر نشده"),
          f.causal?clrAqua:clrOrange);
   ExpAdd("وضعیت ناحیه: "+FVGStateFa(f),
          f.invalidated?clrDimGray:(f.inverted?clrMediumOrchid:((f.ceTouched||f.mitigated)?clrGoldenrod:clrLime)));
   // فاز ۴۳: نقش فعلی در متن هم صریح گفته می‌شود، وگرنه کاربر مربعی می‌بیند که
   // رنگش با جهت تولد نمی‌خواند و مجبور است حدس بزند کدام حرف درست است.
   if(f.inverted)
   {
      ExpAddWrapped("نقش فعلی: این گپ وارونه شده و از این به بعد در جهت مخالف تولدش خوانده می‌شود", clrMediumOrchid);
      string invAt=(f.invertedTime>0)? TimeToString(f.invertedTime,TIME_DATE|TIME_MINUTES) : "ثبت نشده";
      ExpAdd("زمان وارونگی: "+invAt+" ؛ جهت تولد گپ: "+(f.direction==DIR_BULL? "صعودی":"نزولی"), clrSilver);
      ExpAddWrapped("ورود هم‌جهت با گپ اولیه روی این ناحیه معتبر نیست؛ سطح را با نقش امروزش بسنج، نه با جهتی که ساخته شد", clrOrange);
   }
   // فاز ۲۸ — تفکیک لمس لبه از رسیدن به میانهٔ ناحیه (منبع: LuxAlgo — Consequent Encroachment).
   ExpAddWrapped((f.mitigated && !f.ceTouched)
                 ? "نکتهٔ مهم: تا این لحظه فقط لبهٔ ناحیه لمس شده و خط تصمیم، میانهٔ آن است؛ پس «پر شده» حساب نمی‌شود"
                 : (f.ceTouched
                    ? "نکتهٔ مهم: قیمت به میانهٔ ناحیه رسیده و بیشتر مدل‌ها همین را «به‌قدر کافی پر شده» می‌دانند"
                    : "هنوز هیچ لمسی ثبت نشده؛ ناحیه دست‌نخورده است"), clrSilver);
   ExpAdd("InpMinFVG_ATR — فیلتر اهمیت اعمال‌شده روی این چارت", clrSilver);
   ExpAddWrapped(StringFormat("حداقل ارتفاع مجاز گپ: %.2f برابر میانگین دامنهٔ کندل‌ها؛ میانگین دامنهٔ همین تحلیل: %.2f — گپ‌های ریزتر از چارت حذف شده‌اند",
                 InpMinFVG_ATR, g_analysisATR), clrSilver);
   ExpAddWrapped("استفادهٔ درست: ورود روی پول‌بک به داخل ناحیه و در جهت بایاس مالک؛ دقیق‌ترین ورود روی میانهٔ ناحیه است و اگر با ناحیهٔ اردر بلاک و باند ورود بهینه هم‌پوشانی داشته باشد، قوی‌تر می‌شود", clrLime);
   ExpAddWrapped("لمس معتبر: لمس شدن ناحیه در همان کندل شکل‌گیری حساب نمی‌شود و پرشدن جزئی فقط از کندل بعد ثبت می‌شود (مرز گپ همیشه با کندل سوم لمس می‌شود)", clrSilver);
   ExpAddWrapped("فیک / بی‌اعتبار: اگر کندلی کامل از سمت مخالف ناحیه بسته شود، گپ به گپ معکوس تبدیل می‌شود و از آن به بعد ناحیهٔ ورود هم‌جهت نیست", clrOrange);
   ExpAddWrapped("قاعدهٔ یکسان‌سازی: جهت نوشته‌شده در این پنل، رنگ مربع روی چارت، ستون نقش در فایل تشخیصی و ناحیهٔ انتخابی ستاپ، همه از یک محاسبه می‌آیند — اگر جایی وارونگی ثبت شود، هر چهار جا با هم عوض می‌شوند", clrSilver);
   if(!f.causal)
      ExpAddWrapped("هشدار کیفیت: این ناحیه به کندل جابه‌جایی معتبر وصل نیست؛ در این ایندیکاتور بیشتر برای ردیابی متن‌فریم به کار می‌رود", clrOrange);
   ExpAddWrapped(StringFormat("انقضا: اگر تا %d کندل لمس یا استفاده نشود، منقضی می‌شود (تنظیم فعلی)", InpFVG_ExpireBars), clrSilver);
   ExpAddWrapped(StringFormat("کنترل خودت: سه کندل اطراف %s را ببین؛ کندل وسط باید بدنهٔ بزرگ داشته باشد و شکاف بین کندل اول و سوم دیده شود؛ میانهٔ ناحیه: %.2f",
                 TimeToString(f.time,TIME_DATE|TIME_MINUTES),(f.top+f.bottom)/2.0), clrSilver);
   ExpAdd("ICT_Assistant_Canonical_Explain.csv — ردیف شمارهٔ "+IdToStr(f.id)+" در این فایل", clrSilver);
}

void ExplainOB(const OBObj &o)
{
   // فاز ۴۳: عنوان OB هم نقش فعلی را می‌گوید (Breaker/Mitigation Block قطبیت
   // برگشته دارد و دیگر در جهت تولدش کار نمی‌کند).
   g_expTitle="ZONE OB #"+IdToStr(o.id)+" "+(o.direction==DIR_BULL?"BULLISH":"BEARISH")
              +(o.polarityFlipped? " -> "+DirToStr(OBActiveDir(o))+" (polarity flipped)" : "");
   ExpAddWrapped(StringFormat("چیست: اردر بلاک؛ ناحیه %.2f تا %.2f؛ زمان %s",
                 o.bottom,o.top, TimeToString(o.time,TIME_DATE|TIME_MINUTES)), clrWhite);
   ExpAdd(StringFormat("دامنهٔ ناحیه: %s", InpOBUseFullCandleRange?"کل کندل، از فتیله تا فتیله":"فقط بدنهٔ کندل"), clrAqua);
   ExpAdd("نوع ناحیه: "+ObKindFa(o.kind), clrAqua);
   ExpAdd("وضعیت: "+ObStateFa(o.state),
          (o.state==OB_VALID)?clrLime:(o.state==OB_BREAKER?clrDeepSkyBlue:clrGoldenrod));
   ExpAddWrapped("چرا تشکیل شد: آخرین کندل مخالف‌رنگ پیش از یک جابه‌جایی، همراه با یک رویداد ساختاری و یک جاروی نقدینگی ثبت شد", clrAqua);
   ExpAdd("Displacement #"+IdToStr(o.displacementId)+" | Event #"+IdToStr(o.structureEventId)+" | Sweep #"+IdToStr(o.liquidityEventId), clrSilver);      ExpAddWrapped("زنجیرهٔ تبدیل به بلوک شکننده: اردر بلاک معتبر که روی یک جاروی نقدینگی ساخته شده باشد، بعد بسته‌شدن از سمت مخالف و در پایان ریتست در کندلی جدا", clrWhite);
      ExpAddWrapped("اگر ناحیه روی جارو ساخته نشده باشد، حتی با شکست و ریتست هم بلوک شکننده نمی‌شود", clrOrange);
   ExpAddWrapped("لمس معتبر: ناحیه در همان کندل ثبت خودش لمس‌شده حساب نمی‌شود؛ این وضعیت فقط از کندل بعد ثبت می‌شود", clrSilver);
   // فاز ۳۶ — تفکیک Internal/External OB (منبع: LuxAlgo — Internal vs External
   // Range Liquidity: OB داخل لگ = Internal؛ مبدأ اکسترمم رنج = External)
   ExpAdd((o.scope==SCOPE_EXTERNAL)?"EXTERNAL (ERL)":"INTERNAL (IRL)", o.scope==SCOPE_EXTERNAL?clrGold:clrAqua);
   ExpAddWrapped((o.scope==SCOPE_EXTERNAL)
      ? "جایگاه: ناحیه روی مبدأ یا اکسترمم دامنهٔ معامله‌گری نشسته است؛ شکست آن یعنی خروج از رنج و معمولاً آغاز یک دامنهٔ تازه — هدف بعدی به‌طور معمول نقدینگی درونی است"
      : "جایگاه: ناحیه درون دامنهٔ معامله‌گری مانده است؛ بعد از مصرف نقدینگی بیرونی، قیمت برای پرکردن ناهنجاری‌های درون دامنه برمی‌گردد و ورود هم‌جهت در نیمهٔ ارزان یا گران منطقی‌تر است",
      (o.scope==SCOPE_EXTERNAL)?clrGold:clrAqua);
   ExpAddWrapped("شرط استفاده: فقط وقتی ناحیه هم‌جهت با بایاس مالک باشد و با یک گپ قیمتی یا میانهٔ آن هم‌پوشانی داشته باشد؛ ناحیهٔ تنها و بدون ساختار را استفاده نکن", clrLime);
   ExpAddWrapped("فیک و بی‌اعتبار: اگر ناحیه بدون تازگی چند بار لمس شود اعتبارش می‌رود؛ و اگر کندل بسته از ناحیه عبور کند دیگر اردر بلاک نیست", clrOrange);
   if(o.state==OB_INVALID)
      ExpAddWrapped("دلیل بی‌اعتبار بودن این ناحیه: به جابه‌جایی و رویداد ساختاری معتبر وصل نشده بود؛ چنین ناحیه‌ای فقط برای شفافیت رسم می‌شود", clrOrange);
   ExpAddWrapped(StringFormat("کنترل خودت: کندل %s را ببین؛ باید کندل مخالف رنگ پیش از حرکت بزرگ باشد؛ ناحیهٔ ثبت‌شده %.2f تا %.2f",
                 TimeToString(o.time,TIME_DATE|TIME_MINUTES),o.bottom,o.top), clrSilver);
   ExpAdd("OB #"+IdToStr(o.id)+" — ICT_Assistant_Canonical_Explain.csv", clrSilver);
}

void ExplainRejection(const RejectionObj &r)
{
   g_expTitle="ZONE REJECTION #"+IdToStr(r.id)+" "+(r.direction==DIR_BULL?"BULLISH":"BEARISH");
   ExpAddWrapped(StringFormat("چیست: بلوک پس‌زدگی؛ ناحیه همان فتیلهٔ غالب است از %.2f تا %.2f و کل کندل نیست؛ زمان %s", r.bottom,r.top,TimeToString(r.time,TIME_DATE|TIME_MINUTES)), clrWhite);
   ExpAddWrapped("چرا تشکیل شد: در همان کندل یک سطح نقدینگی ثبت‌شده جارو شد و یک فتیله بیش از ۶۰ درصد دامنه را گرفت (بدنه کمتر از ۴۰ درصد)؛ یعنی قیمت نقدینگی را برداشت و برگشت", clrAqua);
   ExpAddWrapped("شرط ثبت: بدون جاروی یک سطح نقدینگی در همان کندل، هیچ بلوک پس‌زدگی ثبت نمی‌شود؛ لمس همان کندل سازنده هم محاسبه نمی‌شود", clrSilver);
   ExpAdd("وضعیت: "+RejectionStateFa(r.rejectionState),
          r.rejectionState==REJECTION_FRESH?clrLime:(r.rejectionState==REJECTION_TOUCHED?clrGoldenrod:clrDimGray));
   ExpAddWrapped("استفادهٔ درست: فقط وقتی هم‌جهت با بایاس و همراه با جارو و جابه‌جایی باشد؛ یک کندل پس‌زدگی تنها کافی نیست", clrLime);
   ExpAddWrapped("فیک و بی‌اعتبار: لمس شدن ناحیه تازگی را کم می‌کند و بسته‌شدن از سمت مخالف آن را بی‌اعتبار می‌کند", clrOrange);
   ExpAddWrapped(StringFormat("کنترل خودت: نسبت فتیله به دامنه را خودت روی کندل %s اندازه بگیر؛ اگر فتیله غالب نبود، ثبت درست نبوده", TimeToString(r.time,TIME_DATE|TIME_MINUTES)), clrSilver);
}

void ExplainSessionBox(string kind, int dayBack)
{
   datetime ref = g_lastContextBarTime>0? g_lastContextBarTime : TimeCurrent();
   datetime s=0,e=0; double hi=0,lo=0; int cnt=0;
   string winName=""; int sh=0,sm=0,eh=0,em=0;
   if(kind=="ASIA") { winName="Asian Range (Accumulation)"; sh=InpAsiaStartHourNY; sm=0; eh=InpAsiaEndHourNY; em=0; }
   else if(kind=="LON"){ winName="London Killzone (Manipulation/Judas)"; sh=InpLondonStartHourNY; sm=0; eh=InpLondonEndHourNY; em=0; }
   else if(kind=="NYAM"){ winName="New York AM Killzone (Distribution)"; sh=InpNY_KZ_StartHourNY; sm=0; eh=InpNY_KZ_EndHourNY; em=0; }
   else if(kind=="LONCL"){ winName="London Close Killzone"; sh=InpLondonCloseStartHourNY; sm=0; eh=InpLondonCloseEndHourNY; em=0; }
   else if(kind=="NYPM"){ winName="New York PM Killzone"; sh=InpNYPM_StartHourNY; sm=InpNYPM_StartMinuteNY; eh=InpNYPM_EndHourNY; em=InpNYPM_EndMinuteNY; }
   else if(kind=="SB1"){ winName="Silver Bullet #1"; sh=InpSB1_StartHourNY; sm=0; eh=InpSB1_EndHourNY; em=0; }
   else if(kind=="SB2"){ winName="Silver Bullet #2"; sh=InpSB2_StartHourNY; sm=0; eh=InpSB2_EndHourNY; em=0; }
   else if(kind=="SB3"){ winName="Silver Bullet #3"; sh=InpSB3_StartHourNY; sm=0; eh=InpSB3_EndHourNY; em=0; }

   g_expTitle="SESSION "+winName;
   if(!WindowForDayBack(dayBack, sh,sm, eh,em, ref, s,e,hi,lo,cnt,true))
   { ExpAdd("برای این روز داده‌ای پیدا نشد", clrSilver); return; }

   ExpAddWrapped(StringFormat("پنجره: %02d:%02d تا %02d:%02d به وقت نیویورک | معادل سرور: %s تا %s",
                 sh,sm,eh,em, TimeToString(s,TIME_DATE|TIME_MINUTES), TimeToString(e,TIME_DATE|TIME_MINUTES)), clrWhite);
   ExpAddWrapped(StringFormat("چیست: رنج همین پنجره؛ سقف %.2f و کف %.2f از %d کندل روی تایم‌فریم %s",
                 hi,lo,cnt,TfFa(InpSessionSourceTF)), clrAqua);
   if(kind=="ASIA")
   {
      ExpAddWrapped("چرا مهم است: آسیا فاز انباشت است؛ رنج آن هدف نقدینگی اصلی لندن می‌شود و بزرگ‌ترین حرکت روز معمولاً از برداشت همین نقدینگی شروع می‌شود", clrLime);
      ExpAddWrapped("در لندن چه انتظاری داریم: اگر فقط فتیله از سقف یا کف آسیا بگذرد و برگردد جاروی نقدینگی است؛ و اگر کندل بسته بیرون ببندد شکست واقعی و تغییر رفتار است", clrLime);
      ExpAddWrapped("فیک/بی‌اعتبار: اگر رنج آسیا بسیار باریک باشد (نقدینگی کم) کیفیت هدف پایین می‌آید؛ روزهای خبری بزرگ هم قواعد را می‌شکنند", clrOrange);
   }
   else if(StringFind(kind,"SB")==0)
   {
      ExpAddWrapped("چیست: این یک پنجرهٔ زمانی است، نه سیگنال — در این یک ساعت اگر نقدینگی مشخصی جارو شود و سپس جابه‌جایی و گپ یا تغییر ساختار در جهت بایاس مالک ظاهر شود، ستاپ کیفیت بالاتری دارد", clrLime);
      ExpAddWrapped("چرا مهم است: این پنجره‌ها ساعت‌هایی هستند که حرکت جهت‌دار اغلب از آن‌ها شروع می‌شود؛ پس همان الگوی همیشگی را در زمان پراحتمال‌تر می‌بینی", clrLime);
      ExpAddWrapped("فیک و بی‌اعتبار: اگر داخل پنجره فقط رنج باشد و هیچ جارو یا جابه‌جایی رخ ندهد هیچ ستاپی معتبر نیست — خودِ ساعت دلیل ورود نیست؛ و اگر بایاس مالک مخالف باشد حرکت داخل پنجره فقط ضد‌روند است", clrOrange);
      ExpAddWrapped("کنترل خودت: ساعت شروع و پایان نیویورک را روی داشبورد ببین و با محدودهٔ همین باکس مقایسه کن؛ اگر جابه‌جا بود آفست یا ساعت تابستانی را بررسی کن", clrSilver);
   }
   else
   {
      ExpAddWrapped("چرا مهم است: سقف و کف همین پنجره به‌عنوان نقدینگی کوتاه‌مدت ثبت می‌شود و جارو آن معمولاً نقطهٔ شروع حرکت جهت‌دار است", clrLime);
      ExpAddWrapped("دقت کندل بسته: ستاپ‌ها فقط با بسته‌شدن کندل خارج از این پنجره معنا دارند؛ داخل پنجره فقط زمینه‌سازی است", clrLime);
   }
   ExpAddWrapped(StringFormat("کنترل خودت: محدودهٔ %s تا %s را روی چارت ببین؛ اگر با ساعت نیویورک نمی‌خواند، آفست بروکر یا ساعت تابستانی را باید تنظیم کرد؛ داشبورد همان آفست تشخیص‌داده‌شده را در ردیف ساعت نشان می‌دهد",
                 TimeToString(s,TIME_DATE|TIME_MINUTES), TimeToString(e,TIME_DATE|TIME_MINUTES)), clrSilver);
   ExpAdd("InpBrokerGMTOffsetOverrideHours — تنظیم دستی آفست بروکر", clrSilver);
}

void ExplainMTFLevel(int index, bool isHigh)
{
   string tf=EnumToString(g_mtfContext[index].timeframe);
   g_expTitle="MTF "+tf+" — "+g_mtfContext[index].role;
   ExpAdd(StringFormat("نقش این تایم‌فریم: %s", g_mtfContext[index].role), clrGold);
   ExpAddWrapped(StringFormat("چیست: سطح حفاظت‌شدهٔ %s روی تایم‌فریم %s؛ داده در %s",
                 isHigh?"سقف":"کف", TfFa(g_mtfContext[index].timeframe),
                 TimeToString(g_mtfContext[index].confirmedBarTime,TIME_DATE|TIME_MINUTES)), clrWhite);
   ENUM_DIRECTION shownExt=(index==0)?g_htfBias:g_mtfContext[index].externalDirection;
   ExpAdd(StringFormat("جهت محاسبه‌شده — بیرونی: %s | درونی: %s",
          DirFa(shownExt), DirFa(g_mtfContext[index].internalDirection)), clrAqua);
   if(index==0)
      ExpAddWrapped("قاعدهٔ سخت: این تایم‌فریم مالک بایاس است؛ هیچ تایم‌فریم پایین‌تری اجازه ندارد آن را عوض کند — فقط می‌تواند تأیید یا رد کند و آماده‌شدن ستاپ را مسدود کند", clrGold);
   else
      ExpAddWrapped("قاعده: این تایم‌فریم نقش کانتکست، ستاپ یا تأیید دارد؛ هم‌جهت بودنش با بایاس شرط لازم است و تضاد آن فقط آماده‌شدن را مسدود می‌کند، نه تغییر بایاس", clrLime);
   if(g_mtfConflict)
      ExpAddWrapped("وضعیت فعلی: تضاد فعال است — "+g_mtfConflictReason, clrOrange);
   ExpAddWrapped(StringFormat("کنترل خودت: روی تایم‌فریم %s بازش کن و ببین جهت ساختار (سقف‌ها و کف‌های تأییدشده) با چیزی که اینجا نوشته هم‌خوان است یا نه", TfFa(g_mtfContext[index].timeframe)), clrSilver);
}

void ExplainSetup()
{
   g_expTitle="SETUP "+g_setup.status;
   if(g_setup.active)
   {
      ExpAdd(StringFormat("ستاپ فعال: جهت %s | ورود %s | حد ضرر %s",
             DirFa(g_setup.dir), PriceS(g_setup.entry), PriceS(g_setup.sl)), clrLime);
      ExpAdd(StringFormat("اهداف: اول %s | دوم %s | سوم %s", PriceS(g_setup.tp1), PriceS(g_setup.tp2), PriceS(g_setup.tp3)), clrLime);
      ExpAdd(StringFormat("ریسک واقعی: ورود تا حد ضرر %.2f (%.2f برابر میانگین دامنه)",
             g_setup.risk, (g_analysisATR>0.0? g_setup.risk/g_analysisATR : 0.0)), clrAqua);
      ExpAdd(StringFormat("نسبت سود به ریسک از فاصله‌ها حساب شده نه از ورودی: هدف سوم 1:%.2f | هدف اول 1:%.2f | هدف دوم 1:%.2f",
             g_setup.rrTP3, g_setup.rrTP1, g_setup.rrTP2), clrLime);
      ExpAdd("ناحیهٔ ورود: "+g_setup.zoneSource, clrAqua);
      ExpAdd("FVG #"+IdToStr(g_setup.fvgId)+" | OB #"+IdToStr(g_setup.obId)+" | DOL "+PriceS(g_currentDOL.price), clrSilver);
      ExpAdd("زنجیرهٔ اثبات: "+g_setup.chainText, clrAqua);
      ExpAdd("منبع حد ضرر: "+g_setup.slSource, clrSilver);
      ExpAddWrapped("چرا آماده شد — ساختار: بایاس مالک تأیید شده و تضاد تایم‌فریمی نیست؛ کانتکست‌های یک‌ساعته و پانزده‌دقیقه‌ای و پنج‌دقیقه‌ای هم‌جهت‌اند و تأیید اجرایی دو‌دقیقه‌ای و یک‌دقیقه‌ای رسیده است", clrLime);
      ExpAddWrapped("چرا آماده شد — چرخهٔ اثبات: یک چرخهٔ جارو و جابه‌جایی و شکست ساختار هم‌جهت و تازه وجود دارد؛ دامنهٔ معامله‌گری معتبر و هم‌جهت است", clrLime);
      ExpAddWrapped("چرا آماده شد — هدف و ریسک: هدف نقدینگی هم‌جهت با فاصلهٔ کافی موجود است؛ ناحیهٔ ورود داخل باند بهینه است و نسبت سود به ریسک از حداقل ورودی کمتر نیست", clrLime);
      ExpAddWrapped("محدودیت این نسخه: مدیریت پوزیشن و حجم معامله محاسبه نمی‌شود و چرخهٔ عمر فقط یک ستاپ را در هر لحظه پیگیری می‌کند", clrOrange);
      ExpAddWrapped("چه چیزی آن را باطل می‌کند: تغییر یا تضاد بایاس مالک؛ از دست رفتن هدف هم‌جهت؛ رفتن دامنه به دامنهٔ مخالف؛ بسته‌شدن قیمت فراتر از مرز باند بهینه به سمت مخالف؛ یا مصرف و انقضای ناحیه", clrTomato);
   }
   ExpAddWrapped("فرسودگی روند: "+ExhaustionStateFa(g_exhaustion.state)+" با امتیاز "+IntegerToString(g_exhaustion.score)+" از "+IntegerToString(g_exhaustion.maxScore), clrOrange);
   ExpAddWrapped(StringFormat("دروازهٔ برگشت: %s | سطح محافظت‌شدهٔ خارجی: %s | امتیاز برگشت پول بزرگ %d از %d — برگشت فقط با بسته‌شدن فراتر از سطح محافظت‌شدهٔ خارجی اعلام می‌شود و فرسودگی هرگز بایاس را عوض نمی‌کند",
                 g_reversal.state, (g_reversal.armed? DoubleToString(g_reversal.levelPrice,_Digits):"—"),
                 g_reversal.smrScore, g_reversal.smrMax), g_reversal.confirmed?clrLime:clrOrange);
   // فاز ۱۲ (#۳ #۹ #۴۷ #۶۷ #۶۸)
   ExpAdd(StringFormat("مدل ورود: %s | امتیاز کیفیت %d از ۱۰ (حداقل %d)",
          EntryModelFa(g_setup.entryModel), g_setup.quality, InpMinQualityScore),
          g_setup.entryModel==MODEL_NONE?clrOrange:clrLime);
   if(g_setup.modelReason!="") ExpAdd("دلیل مدل: "+g_setup.modelReason, clrSilver);
   if(g_setup.qualityText!="") ExpAdd("تفکیک کیفیت: "+g_setup.qualityText, clrSilver);
   ExpAdd(StringFormat("ساختار داخلی تایم‌فریم مالک (%s): %s", TfFa(InpHTF), DirFa(g_htfInternalDir)), clrAqua);
   if(g_htfInternalReason!="") ExpAdd(g_htfInternalReason, clrAqua);
   ExpAdd(StringFormat("فاز روند: %s با سن %d کندل", TrendPhaseFa(g_trend.phase), g_trend.ageBars), clrAqua);
   if(g_trend.phaseReason!="") ExpAdd(g_trend.phaseReason, clrAqua);
   ExpAdd(StringFormat("ناحیهٔ منتخب: %s با امتیاز %d (شناسه #%s)",
          PoiKindFa(g_setup.poiKind), g_setup.poiScore, IdToStr(g_setup.poiId)), clrAqua);
   if(g_trendlineBuilt) ExpAdd("نقدینگی مورب: فعال است", clrAqua);
   else if(g_trendlineReject!=""){ ExpAdd("نقدینگی مورب فعال نشد", clrOrange); ExpAddWrapped(g_trendlineReject, clrOrange); }
   if(g_rangeOk)
      ExpAdd(StringFormat("رنج فعال: %.2f تا %.2f (%.1f برابر میانگین دامنه) با %d و %d برخورد",
             g_rangeLow, g_rangeHigh, (g_analysisATR>0.0? g_rangeHeight/g_analysisATR:0.0),
             g_rangeLowTouches, g_rangeHighTouches), clrAqua);
   else if(g_rangeReject!=""){ ExpAdd("رنج معتبر پیدا نشد", clrOrange); ExpAddWrapped(g_rangeReject, clrOrange); }
   ExpAddWrapped("سطوح چرخهٔ تحویل: "+g_ipdaNote, g_ipdaOk?clrAqua:clrOrange);
   if(g_exhaustion.reason!="") ExpAddWrapped("شواهد فرسودگی: "+g_exhaustion.reason, clrSilver);
   if(!g_setup.active)
   {
      ExpAddWrapped("دلیل اینکه هنوز آماده نیست: "+SetupStatusFa(g_setup.status), clrOrange);
      ExpAdd("Setup status code: "+g_setup.status, clrSilver);
      ExpAddWrapped("ترتیب شرط‌ها: بایاس مالک، هدف نقدینگی هم‌جهت با حداقل فاصله، نبود تضاد تایم‌فریمی، هم‌جهتی کانتکست‌ها، تأیید اجرایی", clrLime);
      ExpAddWrapped("و سپس چرخهٔ اثبات‌شدهٔ جارو و جابه‌جایی و شکست ساختار، اعتبار دامنهٔ معامله‌گری، ناحیهٔ ورود داخل باند بهینه، حد ضرر معتبر و نسبت سود به ریسک کافی", clrLime);
   }
   // فاز ۱۵ (#۶۶): چرخهٔ عمر — ابطال با عبور *بستهٔ* قیمت از SL
   if(InpTrackSetupLifecycle)
   {
      string lifeColor = (g_setupLifeState=="INVALIDATED")? "ابطال‌شده" : "در جریان";
      ExpAdd(StringFormat("چرخهٔ عمر ستاپ: %s | مسلح‌شده در %s", lifeColor,
             (g_setupLifeArmTime>0? TimeToString(g_setupLifeArmTime,TIME_DATE|TIME_MINUTES):"—")), clrAqua);
      ExpAdd(StringFormat("حد ضرر پیگیری %s | هدف اول پیگیری %s | شمارنده‌ها: مسلح %d و باطل %d و هدف اول %d",
             (g_setupLifeSL>0.0? PriceS(g_setupLifeSL):"—"),
             (g_setupLifeTP1>0.0? PriceS(g_setupLifeTP1):"—"),
             g_setupArmedCount, g_setupInvalidCount, g_setupTP1Count), clrAqua);
      if(g_setupLifeState=="INVALIDATED")
         ExpAdd(StringFormat("ابطال با عبور بستهٔ قیمت از حد ضرر رخ داده است — کندل %s | قیمت بسته %s | حد ضرر %s",
                TimeToString(g_setupInvalidTime,TIME_DATE|TIME_MINUTES),
                PriceS(g_setupInvalidPrice), PriceS(g_setupLifeSL)), clrTomato);
      else if(g_setupLifeState=="TP1_HIT")
         ExpAdd("هدف اول (یک برابر ریسک) لمس شد و پیگیری این ستاپ بسته شد", clrLime);
      else if(g_setupLifeState=="TRACKING")
         ExpAdd("این ستاپ در حال پیگیری است: ابطال فقط وقتی ثبت می‌شود که یک کندل بسته فراتر از حد ضرر بسته شود؛ لمس فتیله ابطال نیست", clrOrange);
      else
         ExpAdd("هنوز هیچ ستاپ آماده‌ای مسلح نشده است؛ با آماده شدن ستاپ پیگیری شروع می‌شود", clrSilver);
      if(g_setupLifeReason!="") ExpAdd("دلیل آخرین تغییر وضعیت: "+g_setupLifeReason, clrSilver);
      ExpAdd("ICT_Assistant_Canonical_SetupLifecycle.csv — دفتر چرخهٔ عمر ستاپ", clrSilver);
   }
   ExpAdd(StringFormat("آفست زمانی بروکر: %+d دقیقه | استاندارد زمستانی: %+d دقیقه | قاعدهٔ ساعت تابستانی: %s",
          g_serverGMTOffsetSeconds/60, g_brokerStdOffsetSeconds/60,
          (g_brokerDSTRule==BDST_AUTO?"خودکار":(g_brokerDSTRule==BDST_US?"قاعدهٔ آمریکا":(g_brokerDSTRule==BDST_EU?"قاعدهٔ اروپا":"بدون قاعده")))), clrAqua);
   ExpAdd(StringFormat("حالت محاسبهٔ تاریخی: %s", InpUseHistoricalBrokerOffset?"فعال — ساعت تابستانی همان لحظه محاسبه می‌شود":"غیرفعال — آفست جاری استفاده می‌شود"), clrAqua);
   ExpAdd("پنجره‌های سشن با آفست همان لحظهٔ تاریخی ساخته می‌شوند، نه با آفست امروز", clrAqua);
   ExpAddWrapped("کنترل خودت: چیزی که این ابزار می‌گوید را با سه چیز بسنج — کندل تأیید، قیمت سطح و شناسه‌ها؛ اگر ناسازگار بود همان عدد را با پیوت دستی مقایسه کن", clrSilver);
   ExpAdd("SETUP — ICT_Assistant_Canonical_Explain.csv", clrSilver);
}

void ExplainLocation(string label)
{
   g_expTitle="LOCATION "+label;
   if(!g_leg.valid)
   {
      ExpAddWrapped("دامنهٔ معامله‌گری معتبر نیست — دلیل: "+LegRejectFa(g_leg.reject), clrOrange);
      ExpAdd("Leg reject code: "+g_leg.reject, clrSilver);
      ExpAddWrapped("معنی دلایل: دادهٔ کافی یعنی کندل بستهٔ کافی روی تایم‌فریم مالک موجود نبوده و سقف و کف متناوب یعنی پیوت‌های تأییدشدهٔ متناوب به حداقل نرسیده‌اند", clrSilver);
      ExpAddWrapped("دامنهٔ صفر یعنی دو پیوت روی یک قیمت نشسته‌اند و دامنهٔ کوچک یعنی اندازهٔ دامنه از حداقل نسبت به میانگین دامنه کمتر است", clrSilver);
      ExpAddWrapped("کنترل خودت: دو پیوت آخر تایم‌فریم مالک را روی چارت ببین؛ اگر فاصلهٔ پیوت‌ها کم یا نامنظم است، تایم‌فریم بالاتر برای رمزگذاری لگ مناسب‌تر است", clrSilver);
      return;
   }

   string dirFa = DirFa(g_leg.dir);
   ExpAddWrapped(StringFormat("چیست: دامنهٔ معامله‌گری از همان دامنهٔ واقعی ساخته شده — از پیوت آغاز %s در %.2f تا پیوت پایان %s در %.2f",
                 (g_leg.dir==DIR_BULL?"کف":"سقف"), g_leg.startPrice,
                 (g_leg.dir==DIR_BULL?"سقف":"کف"), g_leg.endPrice), clrWhite);
   ExpAdd(StringFormat("دو نقطهٔ دامنه: %s و %s",
          TimeToString(g_leg.startTime,TIME_DATE|TIME_MINUTES), TimeToString(g_leg.endTime,TIME_DATE|TIME_MINUTES)), clrAqua);
   ExpAdd(StringFormat("جهت دامنه: %s | اندازهٔ دامنه: %.2f (%.2f برابر میانگین دامنه)",
          dirFa, g_leg.range, g_leg.sizeATR), clrAqua);

   double eq=g_leg.eq;
   double oteLow = (g_leg.dir==DIR_BULL)? g_leg.high-g_leg.range*InpOTE_High : g_leg.low+g_leg.range*InpOTE_Low;
   double oteHigh= (g_leg.dir==DIR_BULL)? g_leg.high-g_leg.range*InpOTE_Low  : g_leg.low+g_leg.range*InpOTE_High;
   double golden = (g_leg.dir==DIR_BULL)? g_leg.high-g_leg.range*InpOTE_Golden : g_leg.low+g_leg.range*InpOTE_Golden;
   ExpAdd(StringFormat("تعادل دامنه %.2f | باند بهینهٔ فیبوناچی %.2f تا %.2f (بین %.0f%% و %.0f%%) | نقطهٔ طلایی %.2f (%.1f%%)",
          eq, oteLow, oteHigh, InpOTE_Low*100.0, InpOTE_High*100.0, golden, InpOTE_Golden*100.0), clrAqua);
   ExpAdd(StringFormat("قیمت تحلیل‌شده: %.2f — پس در سمت %s تعادل قرار دارد",
          g_analysisClose, (g_analysisClose>=eq?"گران (بالای تعادل)":"ارزان (زیر تعادل)")), clrWhite);
   // فاز ۳۶: توضیح Price Delivery (برچسب لگ روی چارت = همین مفهوم)
   ExpAdd(StringFormat("تحویل قیمت: قیمت همیشه از یک نقدینگی به نقدینگی دیگر تحویل می‌شود؛ این دامنهٔ %s از %s شروع شده و الان در %s تعادل است",
          dirFa, TimeToString(g_leg.startTime,TIME_DATE|TIME_MINUTES),
          (g_analysisClose>=eq?"نیمهٔ بالای":"نیمهٔ پایین")), clrLime);
   ExpAdd("بازگشت به تعادل یا باند بهینه فرصت ورود هم‌جهت است و عبور قاطع از اکسترمم دامنه یعنی تحویل به نقدینگی بعدی و آغاز دامنهٔ تازه", clrLime);

   if(label=="GOLDEN")
      ExpAdd(StringFormat("خاصیت نقطهٔ طلایی: %.2f وسط همان باند بهینه است و از ۷۰٫۵ درصد ریتریس دامنه می‌آید؛ ورود در همین نقطه کم‌ترین ریسک و بیشترین تطابق با دامنه را دارد", golden), clrLime);
   else
      ExpAdd("خاصیت این سطح: تعادل نصف دامنه است؛ بالای آن نیمهٔ گران و پایین آن نیمهٔ ارزان. در بایاس صعودی ورود فقط از نیمهٔ ارزان و در باند بهینه، و در بایاس نزولی فقط از نیمهٔ گران", clrLime);

   ExpAddWrapped("توجه: این باند فقط وقتی در ستاپ استفاده می‌شود که جهت دامنه با بایاس مالک یکی باشد؛ دامنهٔ مخالف دلیل رد شدن ستاپ است، نه دلیلی برای ورود برعکس", clrOrange);
   ExpAddWrapped("کنترل خودت: یک فیبوی دستی روی همان دو نقطه بگذار؛ باید ۶۲ و ۷۰٫۵ و ۷۹ همین اعداد را بدهد. اگر فرق داشت همین شناسه را گزارش کن", clrSilver);
   ExpAdd("ICT_Assistant_Canonical_Leg_Diag.csv — ردیف همان لحظه", clrSilver);
}

// توضیح فارسی خط DOL (هدف معامله) — روی hover همان خط دیده می‌شود
void ExplainDOL()
{
   g_expTitle="DRAW ON LIQUIDITY";
   if(!g_hasDOL)
   {
      ExpAddWrapped("فعلاً هدف نقدینگی معتبری وجود ندارد؛ واکنش به بایاس مالک شکل نگرفته یا سطح هم‌جهت پیدا نشده است", clrOrange);
      if(g_dolRejectReason!="") { ExpAdd("DOL reject code: "+g_dolRejectReason, clrSilver); }
      return;
   }
   ExpAdd(g_currentDOL.typeName, clrWhite);
   ExpAdd(StringFormat("چیست: سطح نقدینگی هم‌جهت بایاس که قیمت به سمت آن کشیده می‌شود — قیمت هدف %.2f", g_currentDOL.price), clrWhite);
   ExpAddWrapped("چرا این سطح: "+g_currentDOL.narrative, clrAqua);
   ExpAdd(StringFormat("فاصلهٔ واقعی تا هدف: %.2f برابر میانگین دامنه (%.2f قیمت)",
          g_currentDOL.distATR, MathAbs(g_currentDOL.price-g_analysisClose)), clrAqua);
   ExpAdd(StringFormat("حداقل فاصلهٔ لازم روی همین سطح: %.2f برابر میانگین دامنه تا نسبت سود به ریسک ناچیز رد شود", InpDOL_MinRoomATR), clrSilver);
   ExpAdd(StringFormat("سطح هنوز دست‌نخورده است: %s | جایگاه در سلسله‌مراتب تأیید شده: %s",
          (g_currentDOL.sweepStateOk?"بله":"خیر"), (g_currentDOL.hierarchyOk?"بله — بیرونی":"درونی")), clrLime);
   ExpAddWrapped("اشتباه رایج: انتخاب دورترین سطح به بهانهٔ سود بیشتر؛ نسبت سود به ریسک وقتی خراب می‌شود که هدف خیلی نزدیک باشد، نه خیلی دور", clrOrange);
   ExpAddWrapped("کنترل خودت: قیمت هدف را با سقف یا کف روز یا هفتهٔ قبل روی چارت مقایسه کن؛ اگر آن سطح با هیچ خط دیگری در رجیستری یکی نیست همین شناسه را گزارش کن", clrSilver);
}

// فاز ۱۲ (#۱۹) — توضیح فارسی نقدینگی مورب
void ExplainTrendline(long id)
{
   int idx=-1;
   for(int i=0;i<ArraySize(g_trendlines);i++) if(g_trendlines[i].id==id){ idx=i; break; }
   if(idx<0)
   {
      g_expTitle="TRENDLINE #"+IdToStr(id);
      ExpAdd("این خط در رجیستری نقدینگی مورب پیدا نشد؛ همین شناسه را گزارش کن", clrOrange);
      return;
   }
   g_expTitle="TRENDLINE "+(g_trendlines[idx].isHigh?"RESISTANCE":"SUPPORT")+" #"+IdToStr(id);
   ExpAddWrapped(StringFormat("چیست: نقدینگی مورب — خطی که %s تأییدشدهٔ تایم‌فریم %s را وصل می‌کند؛ استاپ‌ها پشت همین خط جمع می‌شوند",
                 g_trendlines[idx].isHigh?"دو سقف":"دو کف", TfFa(g_trendlines[idx].tf)), clrWhite);
   ExpAddWrapped(StringFormat("آنکرها: %s در %s تا %s در %s | شیب: %.6f قیمت بر ثانیه | تعداد سویینگ روی خط: %d",
                 DoubleToString(g_trendlines[idx].p1,_Digits), TimeToString(g_trendlines[idx].t1,TIME_DATE|TIME_MINUTES),
                 DoubleToString(g_trendlines[idx].p2,_Digits), TimeToString(g_trendlines[idx].t2,TIME_DATE|TIME_MINUTES),
                 g_trendlines[idx].slope, g_trendlines[idx].touches), clrAqua);
   ExpAddWrapped(StringFormat("قیمت خط در آخرین لحظهٔ تحلیل: %s (خط تابع زمان است، پس یک عدد ثابت نیست)",
                 DoubleToString(TrendlinePriceAt(g_trendlines[idx], g_lastContextBarTime),_Digits)), clrAqua);
   ExpAdd(StringFormat("شرط ابطال: بسته‌شدن کندل با فاصلهٔ بیش از %.2f برابر میانگین دامنه فراتر از خط، یعنی نقدینگی این خط برداشته شده و خط دیگر معتبر نیست",
          InpTrendlineBreakATR), clrTomato);
   if(g_trendlines[idx].swept)
   {
      ExpAdd(StringFormat("جارو شد در کندل %s — فتیله از خط عبور کرد ولی کندل به همان سمت خط بسته شد",
             TimeToString(g_trendlines[idx].sweptTime,TIME_DATE|TIME_MINUTES)), clrYellow);
      ExpAdd(StringFormat("قاعدهٔ جاروی مورب: فتیلهٔ فراتر همراه با بسته‌شدن برگشتی؛ قیمت خط در آن کندل %s بود و سطح مصرف‌شده علامت خورد",
             DoubleToString(g_trendlines[idx].sweptPrice,_Digits)), clrYellow);
   }
   else
      ExpAddWrapped("جارو نشده: هنوز هیچ فتیله‌ای فراتر از خط نرفته و به همان سمت برنگشته است — استخر نقدینگی مورب دست‌نخورده است", clrAqua);
   ExpAdd(StringFormat("کنترل خودت: دو آنکر نام‌برده‌شده را روی چارت ببین؛ شیب آن‌ها باید با قاعدهٔ سمت نقدینگی بخواند و تعداد سویینگ روی خط باید حداقل %d باشد",
          MathMax(2,InpTrendlineMinTouches)), clrSilver);
   ExpAdd("قاعدهٔ سمت: سقف‌های نزولی یعنی نقدینگی سقفی بالای خط و کف‌های صعودی یعنی نقدینگی کفی زیر خط", clrSilver);
   ExpAdd("InpTrendlineMinTouches — حداقل تعداد سویینگ روی خط", clrSilver);
}

// فاز ۱۲ (#۴۷ #۶۷ #۶۸) — توضیح بهترین POI و امتیاز کیفیت ستاپ
void ExplainBestPOI()
{
   POIObj bp;
   g_expTitle="POI REGISTRY";
   if(!InpBuildPOIRegistry || ArraySize(g_poi)==0)
   {
      ExpAdd("رجیستری نقاط مورد علاقه خالی است یا با ورودی مربوطه خاموش شده", clrOrange);
      ExpAdd("InpBuildPOIRegistry — کلید ساخت رجیستری", clrSilver);
      return;
   }
   ExpAdd(StringFormat("چیست: رجیستری یکپارچهٔ نقاط مورد علاقه — %d ناحیه با نوع، جهت، محدوده، زمان، تایم‌فریم مالک و امتیاز عددی", ArraySize(g_poi)), clrWhite);
   ExpAdd("منابع: گپ علّی، اردر بلاک، بلوک شکننده، بلوک تخفیف، بلوک پس‌زدگی، نقدینگی مورب و مرزهای رنج", clrWhite);
   if(FindBestPOI(g_htfBias, bp))
   {
      ExpAdd(StringFormat("بهترین ناحیهٔ هم‌جهت بایاس: %s با امتیاز %d (شناسه #%s)",
             PoiKindFa(bp.kind), bp.score, IdToStr(bp.id)), clrLime);
      ExpAdd(StringFormat("جهت %s | ناحیه %.2f تا %.2f | زمان %s | تایم‌فریم %s",
             DirFa(bp.direction), bp.bottom, bp.top, TimeToString(bp.time,TIME_DATE|TIME_MINUTES),
             TfFa(bp.tf)), clrLime);
   }
   else ExpAdd("هیچ ناحیهٔ هم‌جهتی با بایاس فعلی در رجیستری نیست", clrOrange);
   if(FindBestPOI(DIR_NONE, bp))
      ExpAdd(StringFormat("بالاترین امتیاز کل رجیستری: %s با امتیاز %d در جهت %s",
             PoiKindFa(bp.kind), bp.score, DirFa(bp.direction)), clrAqua);
   ExpAdd("تفکیک امتیاز: پایه ۲۰ | بلوک شکننده ۱۲+ | گپ ۸+ | اردر بلاک ۶+ | مورب یا رنج ۵+ | بلوک تخفیف ۴+ | پس‌زدگی ۳+", clrSilver);
   ExpAdd("امتیازهای افزوده: هم‌جهتی با بایاس ۱۰+ | نشستن روی اکسترمم دامنه ۶+ | بلوک تودرتوی درونی ۴+", clrSilver);
   ExpAdd(StringFormat("امتیاز کهنگی: هر %d کندل یک امتیاز کاسته می‌شود تا حداکثر ۱۰ امتیاز", MathMax(1,InpPOI_AgeDecayBars)), clrSilver);
   ExpAdd(StringFormat("ستاپ فعلی: مدل %s | امتیاز کیفیت %d از ۱۰ (حداقل ورودی %d)",
          EntryModelFa(g_setup.entryModel), g_setup.quality, InpMinQualityScore), g_setup.active?clrLime:clrOrange);
   if(g_setup.qualityText!="") ExpAdd("تفکیک کیفیت: "+g_setup.qualityText, g_setup.active?clrLime:clrOrange);
   ExpAddWrapped("امتیاز کیفیت هیچ‌وقت جای دروازهٔ ساختار را نمی‌گیرد؛ فقط ستاپ‌های ضعیف را رد می‌کند و رجیستری فقط انتخاب ناحیه را یکسان می‌کند", clrTomato);
}

// فاز ۱۱ — توضیح فارسی دروازهٔ برگشت و Smart Money Reversal
void ExplainReversal()
{
   g_expTitle="REVERSAL — "+g_reversal.state;
   ExpAddWrapped(StringFormat("چیست: برگشت تأییدشده فقط یک معنا دارد — کندل بستهٔ %s فراتر از سطح محافظت‌شدهٔ خارجی *بسته* شود. فتیله کافی نیست؛ بسته‌شدن لازم است (#۸/#۷۱)", TfFa(InpHTF)), clrWhite);

   if(!InpEnableReversalGate)
   {
      ExpAdd("دروازهٔ برگشت خاموش است؛ در این حالت هیچ برگشتی تأیید نمی‌شود و تنها هشدار فرسودگی نمایش داده می‌شود", clrOrange);
      ExpAdd("InpEnableReversalGate — کلید دروازهٔ برگشت", clrSilver);
      return;
   }
   if(!g_reversal.armed)
   {
      ExpAddWrapped("الان سطح محافظت‌شدهٔ خارجی فعالی وجود ندارد؛ وضعیت: ", clrOrange);
      ExpAdd("Reversal state code: "+g_reversal.state, clrSilver);
      ExpAddWrapped("دلیل واقعی: "+g_reversal.reason, clrSilver);
      ExpAddWrapped("معنی حالت‌ها: یا بایاس مالک هنوز تأیید نشده، یا آخرین رویداد تایم‌فریم مالک سویینگ محافظ نداده و با سقف نگه‌داری سویینگ‌ها از رجیستری حذف شده، یا دادهٔ بستهٔ کافی نیست", clrSilver);
      ExpAddWrapped("کنترل خودت: آخرین رویداد تایم‌فریم مالک را روی چارت ببین؛ همان رویداد باید یک سویینگ مقابل را به‌عنوان محافظ معرفی کرده باشد — همان سویینگ سطح این دروازه است", clrSilver);
      return;
   }

   ExpAddWrapped(StringFormat("سطح محافظت‌شدهٔ خارجی: %s در %s | زمان سویینگ: %s | شناسهٔ سویینگ: #%s",
                 g_reversal.levelIsHigh?"سقف":"کف", DoubleToString(g_reversal.levelPrice,_Digits),
                 TimeToString(g_reversal.levelTime,TIME_DATE|TIME_MINUTES), IdToStr(g_reversal.levelSwingId)), clrAqua);
   ExpAddWrapped(StringFormat("جهت برگشتی که این سطح تأیید می‌کند: %s | بایاس لحظهٔ سنجش: %s | کندل سنجیده‌شده: %s با قیمت بسته %s",
                 DirFa(OppositeDir(g_reversal.snapBias)), DirFa(g_reversal.snapBias),
                 TimeToString(g_reversal.snapBarTime,TIME_DATE|TIME_MINUTES), DoubleToString(g_reversal.snapBarClose,_Digits)), clrAqua);

   if(g_reversal.confirmed)
   {
      ExpAdd(StringFormat("برگشت تأییدشده: جهت %s | کندل تأیید %s",
             DirFa(g_reversal.dir), TimeToString(g_reversal.confirmedTime,TIME_DATE|TIME_MINUTES)), clrLime);
      ExpAdd(StringFormat("قیمت بستهٔ تأیید %.5f | %d کندل از تأیید گذشته | رویداد #%s",
             g_reversal.confirmedClose, g_reversal.barsSince, IdToStr(g_reversal.eventId)), clrLime);
      ExpAdd(StringFormat("برگشت پول بزرگ: %s — %s", g_reversal.smr?"تأییدشده":"تأیید نشده", g_reversal.smrReason),
             g_reversal.smr?clrLime:clrOrange);
      ExpAdd(StringFormat("چهار شاهدی که شمرده می‌شود (حداقل %d لازم است)، هر یک یکی از این‌هاست: جاروی نقدینگی مقابل تا %d کندل پیش از شکست؛ جابه‌جایی زنجیرشدهٔ هم‌جهت؛ ناحیهٔ هم‌جهت معتبر؛ و هم‌جهتی ساختار پایین‌تر با جهت برگشت",
             InpSMR_MinScore, InpSMR_SweepLookbackBars), clrSilver);
   }
   else
   {
      ExpAddWrapped("هنوز برنگشته: "+g_reversal.reason, clrOrange);
      ExpAddWrapped("نکتهٔ مهم: فرسودگی هرگز به‌تنهایی بایاس را عوض نمی‌کند؛ تنها همین دروازه یعنی بسته‌شدن فراتر از سطح حفاظت‌شدهٔ خارجی برگشت را تأیید می‌کند", clrTomato);
   }

   ExpAddWrapped("چه چیزی آن را باطل می‌کند: ساخت رویداد ساختاری تازه‌ای روی همان تایم‌فریم مالک که سطح حفاظت‌شده را جابه‌جا کند؛ در آن حالت شاهد برگشت قبلی دیگر تازه نیست و فقط در تاریخچه می‌ماند", clrTomato);
   ExpAdd("توجه: برگشت تأییدشده معنای «همین حالا بفروش» نیست؛ فقط می‌گوید ساختار حفاظت‌شده در جهت مخالف بسته شده است", clrOrange);
   ExpAddWrapped("کنترل خودت: کندل بستهٔ تایم‌فریم مالک را باز کن؛ اگر قیمت بستهٔ آن فراتر از این سطح است تأیید درست است و اگر فقط فتیله بوده ثبت اشتباه است", clrSilver);
   ExpAdd("REVERSAL — ICT_Assistant_Canonical_Explain.csv", clrSilver);
   ExpAdd("REVERSAL — ICT_Assistant_Canonical_Reversal_Diag.csv", clrSilver);
}

// تشخیص نوع آبجکت از نام و ساخت توضیح
// فاز ۴۴ — پیام واحد «مرجع آبجکت در رجیستری نیست».
// قبلاً هر خانواده در این حالت **بی‌صدا** برمی‌گشت (بدون عنوان و بدون خط)،
// یعنی پنل خالی می‌ماند: آبجکت روی چارت دیده می‌شود، کاربر کلیک می‌کند و
// هیچی نمی‌نویسد. علت معمولش سقف نگه‌داری رجیستری است: آبجکت به‌عنوان تاریخچهٔ
// نمایش (سبک frozen فاز ۱۴) روی چارت می‌ماند ولی مرجعش از رجیستری بیرون افتاده.
// این پیام همان حقیقت را می‌گوید و مسیر کنترل هم می‌دهد.
void ExplainRegistryMiss(string familyFa, string idStr)
{
   g_clickReason="REGISTRY_MISS";
   g_expTitle="OBJECT NOT IN REGISTRY";
   ExpAddWrapped("چیست: این آبجکت روی چارت رسم شده ولی مرجعش در رجیستری فعال پیدا نشد؛ خانواده: "+familyFa, clrOrange);
   ExpAdd("object id from name: "+idStr, clrSilver);
   ExpAddWrapped("چرا: سقف نگه‌داری رجیستری همین خانواده پر شده و قدیمی‌ترین مرجع حذف شده، در حالی که آبجکتش به‌عنوان تاریخچهٔ نمایش روی چارت مانده است", clrSilver);
   ExpAddWrapped("این خطای محاسبه نیست: اعداد همین ناحیه در فایل توضیحات و فایل‌های شاهد باقی می‌مانند؛ فقط نقشهٔ کلیک دیگر به آن مرجع نمی‌رسد", clrSilver);
   ExpAddWrapped("کنترل خودت: سقف نگه‌داری همین خانواده را بالا ببر یا پنجرهٔ تاریخچه را کوتاه کن؛ اگر آبجکت زنده (نه خاکستری) است و باز هم مرجع ندارد، همان شناسهٔ بالا را گزارش کن", clrAqua);
}

//--------------------------------------------------------------------
// فاز ۴۴ — توزیع‌کنندهٔ توضیح. این تابع **به‌تنهایی** پنل نمی‌سازد؛
// تضمین «هیچ‌وقت خالی نباش» را BuildExplanation() اضافه می‌کند.
//--------------------------------------------------------------------
void ExplainDispatchObject(string objName)
{
   string body=objName;
   StringReplace(body,"ICTv13_","");

   if(StringFind(body,"LIQ_")==0)
   {
      string idStr=body;
      StringReplace(idStr,"LIQ_","");
      StringReplace(idStr,"_T","");
      LiquidityObj l;
      if(FindLiquidityById((long)StringToInteger(idStr), l)) ExplainLiquidity(l);
      else ExplainRegistryMiss("سطح نقدینگی", idStr);
      return;
   }
   if(StringFind(body,"SWEEP_")==0)
   {
      string idStr=body; StringReplace(idStr,"SWEEP_","");
      LiquidityObj l;
      if(FindLiquidityById((long)StringToInteger(idStr), l))
      {
         ExplainLiquidity(l);
         ExpAdd(StringFormat("SWEEP — ثبت‌شده در %s", TimeToString(l.sweptTime,TIME_DATE|TIME_MINUTES)), clrOrange);
         ExpAdd("نقدینگی برداشته شد؛ برای تبدیل شدن به ستاپ، جابه‌جایی و شکست ساختار در جهت مخالف جارو لازم است", clrOrange);
      }
      else ExplainRegistryMiss("نشان جاروی نقدینگی", idStr);
      return;
   }
   if(StringFind(body,"EVT")==0)
   {
      string idStr=body; StringReplace(idStr,"EVTL_",""); StringReplace(idStr,"EVT_","");
      StructureEvent e;
      if(FindEventById((long)StringToInteger(idStr), e)) ExplainStructureEvent(e);
      else ExplainRegistryMiss("رویداد ساختاری", idStr);
      return;
   }
   if(StringFind(body,"FVG")==0)
   {
      string idStr=body; StringReplace(idStr,"FVGCE_",""); StringReplace(idStr,"FVG_","");
      FVGObj f;
      if(FindFVGById((long)StringToInteger(idStr), f)) ExplainFVG(f);
      else ExplainRegistryMiss("گپ ارزش منصفانهٔ کوچک", idStr);
      return;
   }
   if(StringFind(body,"OB_")==0)
   {
      string idStr=body; StringReplace(idStr,"OB_","");
      OBObj o;
      if(FindOBById((long)StringToInteger(idStr), o)) ExplainOB(o);
      else ExplainRegistryMiss("اردر بلاک", idStr);
      return;
   }
   if(StringFind(body,"REJECTION_")==0)
   {
      string idStr=body; StringReplace(idStr,"REJECTION_","");
      RejectionObj r;
      if(FindRejectionById((long)StringToInteger(idStr), r)) ExplainRejection(r);
      else ExplainRegistryMiss("بلوک پس‌زدگی", idStr);
      return;
   }
   // فاز ۴۴ — نوار تک‌خطی گوشهٔ چارت (RSTRIP). تنها آبجکتی بود که در فایل
   // توضیحات به پیام جایگزین می‌افتاد (شاهد: Explain.csv قبل از این فاز).
   if(StringFind(body,"RSTRIP")==0)
   {
      ExplainRiskStripObject();
      return;
   }
   // فاز ۴۸: ردیف جداگانهٔ PENDING حذف شد و داخل همان نوار مسیر رفت؛ پس دیگر
   // شاخهٔ کلیک مستقل ندارد. متن آن بخش هنوز از همان ماژولی می‌آید که عدد را
   // محاسبه می‌کند و از داخل ExplainRiskStripObject صدا زده می‌شود تا یک کلیک،
   // یک پنل و یک روایت بدهد.
   if(StringFind(body,"SESS_")==0)
   {
      string rest=body;
      StringReplace(rest,"SESS_","");
      int pos=StringFind(rest,"_");
      if(pos>0)
      {
         string kind=StringSubstr(rest,0,pos);
         string dayStr=StringSubstr(rest,pos+1);
         ExplainSessionBox(kind,(int)StringToInteger(dayStr));
      }
      return;
   }
   if(StringFind(body,"MTF_")==0)
   {
      string rest=body; StringReplace(rest,"MTF_","");
      bool isHigh=true;
      int len=StringLen(rest);
      string tag=rest;
      if(len>=2)
      {
         string suffix=StringSubstr(rest,len-2,2);
         if(suffix=="_H"){ isHigh=true;  tag=StringSubstr(rest,0,len-2); }
         else if(suffix=="_L"){ isHigh=false; tag=StringSubstr(rest,0,len-2); }
      }
      for(int i=0;i<6;i++)
         if(EnumToString(g_mtfTimeframes[i])==tag){ ExplainMTFLevel(i,isHigh); return; }
      ExpAdd(tag+" — سطح تایم‌فریم (در رجیستری متن‌فریم ثبت نشده)", clrWhite);
      return;
   }
   if(StringFind(body,"SETUP")==0)
   {
      ExplainSetup();
      return;
   }
   if(StringFind(body,"DOL_")==0)
   {
      ExplainDOL();
      return;
   }
   if(StringFind(body,"LOCATION_")==0)
   {
      ExplainLocation(StringSubstr(body,9));
      return;
   }
   // فاز ۳۶: برچسب Price Delivery — مسیر همان ExplainLocation است (یک حقیقت)
   // فاز ۱۱: دروازهٔ برگشت و تأییدیهٔ برگشت
   if(StringFind(body,"REVERSAL")==0)
   {
      ExplainReversal();
      return;
   }
   // فاز ۱۲: نقدینگی مورب و رجیستری POI
   if(StringFind(body,"TRENDLINE_")==0)
   {
      string tlId=body; StringReplace(tlId,"TRENDLINE_","");
      ExplainTrendline((long)StringToInteger(tlId));
      return;
   }
   if(StringFind(body,"POI_BEST")==0)
   {
      ExplainBestPOI();
      return;
   }
   // فاز ۳۶: Quarterly Theory — کلیک روی خطوط True Open
   // فاز ۳۶: AMD قیمتی — توضیح مستقل (کلیک روی سطر داشبورد یا آبجکت آینده)
   if(StringFind(body,"AMD_PRICE")==0)
   {
      g_expTitle="AMD PRICE (Power of Three)";
      ExpAddWrapped(g_amdPriceNote==""? "رنج آسیا هنوز ثبت نشده و رفتار قیمت در قالب انباشت، دستکاری و توزیع قابل بیان نیست": g_amdPriceNote, clrWhite);
      ExpAddWrapped("تفکیک زمانی از قیمتی: نگاشت سشنی (آسیا انباشت، لندن دستکاری، نیویورک توزیع) فقط زمان‌بندی است؛ این بخش رفتار واقعی قیمت را می‌سنجد: جاروی بیرون رنج آسیا همان دستکاری است و حرکت انبساطی مخالف آن همان توزیع", clrAqua);
      ExpAdd("Source: ICT Power of Three + AMD-X in Quarterly Theory", clrSilver);
      return;
   }
   if(StringFind(body,"QT_DAYOPEN")==0){ ExplainQT(false); return; }
   if(StringFind(body,"QT_WKOPEN")==0){ ExplainQT(true);  return; }
   // فاز ۳۶: Brooks Range / Measured Move
   if(StringFind(body,"BROOKS_TR")==0 || StringFind(body,"BROOKS_MM")==0){ ExplainBrooks(); return; }
   // فازهای ۱۶–۲۱: hover فارسی خانواده‌های جدید
   if(StringFind(body,"WYCK_")==0)
   {
      string wid=body; StringReplace(wid,"WYCK_","");
      long want=(long)StringToInteger(wid);
      for(int i=0;i<ArraySize(g_wyck);i++)
         if(g_wyck[i].id==want){ ExplainWyckoff(g_wyck[i]); return; }
      g_expTitle="WYCKOFF"; ExpAddWrapped("این رویداد در رجیستری پیدا نشد (ممکن است پنجرهٔ نگاه‌عقب گذشته باشد)", clrOrange);
      return;
   }
   if(StringFind(body,"SD_")==0)
   {
      string zid=body; StringReplace(zid,"SD_","");
      long want=(long)StringToInteger(zid);
      for(int i=0;i<ArraySize(g_sd);i++)
         if(g_sd[i].id==want){ ExplainSD(g_sd[i]); return; }
      g_expTitle="S/D"; ExpAdd("این ناحیه در رجیستری پیدا نشد (با سقف نگه‌داری از رجیستری بیرون افتاده است)", clrOrange);
      return;
   }
   if(StringFind(body,"BROOKS")==0){ ExplainBrooks(); return; }
   if(StringFind(body,"RTM_")==0)   // فاز ۳۴: توضیح مخصوص همان رویداد RTM
   {
      string rid=body; StringReplace(rid,"RTM_","");
      long want=(long)StringToInteger(rid);
      for(int i=0;i<ArraySize(g_rtm);i++)
         if(g_rtm[i].id==want){ ExplainRTMEvent(g_rtm[i]); return; }
      ExplainRTM(); return;
   }
   if(StringFind(body,"RTM")==0){ ExplainRTM(); return; }
   if(StringFind(body,"PROF")==0){ ExplainProfile(); return; }

}

//====================================================================
// فاز ۴۴ — تضمین «نام + دلیل» برای هر کلیک
//====================================================================
// قرار پروژه: هر چیزی که روی صفحه دیده می‌شود باید بگوید چیست و چرا شکل
// گرفته. یک راه نقض این قرار که هیچ ابزار بیرونی نمی‌تواند بگیرد، همین
// است: کاربر روی آبجکت کلیک کند و پنل **هیچ چیز** ننویسد. سه راه رخ دادنش:
//   ۱) پیشوند نام آبجکت در زنجیرهٔ تشخیص نباشد،
//   ۲) نام باشد ولی مرجعش از رجیستری حذف شده باشد (سقف نگه‌داری)،
//   ۳) شاخه توضیح را برگرداند ولی هیچ خطی نساخته باشد.
// سه لایهٔ زیر این هر سه حالت را به یک پیام صادقانه تبدیل می‌کنند:
//   ExplainDispatchObject  → تشخیص خانواده
//   ExplainUnknownObject   → پیام لایهٔ ناشناخته (تعویض/کدگذاری)
//   ExplainFrozenNote      → نگه‌داشتهٔ تاریخچه روی چارت
// و در آخر، عنوان هم اگر خالی مانده باشد از نام آبجکت ساخته می‌شود تا
// کاربر بداند کلیک او کجا خورده است.
void ExplainUnknownObject(string objName)
{
   string body=objName;
   StringReplace(body,"ICTv13_","");
   if(g_expTitle=="") g_expTitle="OBJECT "+body;
   ExpAddWrapped("چیست: این آبجکت روی چارت رسم شده ولی توضیح تخصصی برای لایهٔ آن ثبت نشده است؛ یعنی نام آبجکت با هیچ خانوادهٔ شناخته‌شده هم‌خوان نشد", clrOrange);
   ExpAdd("obj internal name: ICTv13_"+body, clrSilver);
   ExpAddWrapped("دلیل ممکن یکم: شناسهٔ داخل نام آبجکت با شناسهٔ داخلی رجیستری هم‌خوان نیست", clrSilver);
   ExpAddWrapped("دلیل ممکن دوم: این آبجکت خانوادهٔ تازه‌ای است که مسیر توضیحش تکمیل نشده؛ اگر زنده و قابل کلیک است همین را گزارش کن", clrTomato);
   ExpAddWrapped("کنترل خودت: نام آبجکت را از فهرست آبجکت‌های چارت بردار و ببین همان عددی را دارد که در فایل توضیحات نوشته شده یا نه", clrAqua);
}

// فاز ۱۴: آبجکتی که به‌سبک frozen نگه داشته شده، باید بالای پنل بگوید چرا
// خاکستری/نقطه‌چین است، تا کاربر آن را با «خطای محاسبه» اشتباه نگیرد.
void ExplainFrozenNote(string objName)
{
   if(ArraySize(g_expLines)==0) return;
   if(IndexInNameList(g_frozen,objName)<0) return;
   int n=ArraySize(g_expLines);
   ArrayResize(g_expLines,n+1);
   for(int i=n;i>0;i--) g_expLines[i]=g_expLines[i-1];
   // فاز ۴۴: این متن قبلاً یک ردیف ۲۶۲ نویسه‌ای بود و از سقف ۲۶۰ نویسه رد
   // می‌شد (با انتقالش به تابع مستقل، ابزار سنجش طول ردیف آن را دید). حالا
   // به دو ردیف کوتاه‌تر شکسته شده تا در پنل با عرض واقعی بریده نشود.
   g_expLines[0]=StringFormat("FROZEN HISTORY: این آبجکت دادهٔ معتبر دارد ولی از پنجرهٔ نمایش فعلی بیرون افتاده است (سقف %d ناحیه / %d سطح)",
                              InpMaxDrawnZones, InpMaxDrawnLevels);
   ArrayResize(g_expLineColors,n+1);
   for(int i=n;i>0;i--) g_expLineColors[i]=g_expLineColors[i-1];
   g_expLineColors[0]=clrDimGray;
   int m=ArraySize(g_expLines);
   ArrayResize(g_expLines,m+1);
   ArrayResize(g_expLineColors,m+1);
   g_expLines[m]="بی‌صدا حذف نشد؛ فقط رنگ خاکستری و خط نقطه‌چین گرفت تا با اشیای زنده قاطی نشود — اگر دوباره داخل پنجرهٔ نمایش برگردد، رنگ و خط اصلی خودکار برمی‌گردد";
   g_expLineColors[m]=clrSilver;
}

// هستهٔ توضیح: توزیع + تضمین، **بدون** شمارنده.
// آزمون خودکار کلیک هم همین تابع را صدا می‌زند تا شمارنده‌های کلیک کاربر با
// هزاران فراخوانی آزمون آلوده نشوند.
ENUM_CLICK_RESOLVE ExplainBuildDetailed(string objName)
{
   g_clickReason="";
   ExplainDispatchObject(objName);
   if(ArraySize(g_expLines)==0)      // سه راه بالا، یک نتیجه
   {
      // اگر خود توزیع‌کننده دلیل را گفته باشد (مرجع از رجیستری بیرون افتاده)
      // همان حفظ می‌شود؛ وگرنه این یک خانوادهٔ ناشناخته است که باید دیده شود.
      if(g_clickReason=="") g_clickReason="NO_HANDLER";
      ExplainUnknownObject(objName);
      ExplainFrozenNote(objName);
      return CLICK_RS_FALLBACK;
   }
   if(g_expTitle=="") g_expTitle="OBJECT "+objName;
   if(g_clickReason=="") g_clickReason="RESOLVED";
   ExplainFrozenNote(objName);
   return CLICK_RS_OK;
}

void BuildExplanation(string objName)
{
   g_clickResolve=ExplainBuildDetailed(objName);
   g_clickCount++;
   if(g_clickResolve==CLICK_RS_OK) g_clickOk++; else g_clickFallback++;
   g_clickLastHit=objName;
   g_clickLastTitle=g_expTitle;
}

//====================================================================
// فاز ۴۴ — توضیح نوار تک‌خطی گوشهٔ چارت (RISK STRIP)
//====================================================================
// این تنها آبجکتی بود که در ICT_Assistant_Canonical_Explain.csv به پیام
// جایگزین می‌افتاد (شاهد از اجرای واقعی: `ICTv13_RSTRIP_TXT` با عنوان
// OBJECT RSTRIP_TXT) — یعنی کاربر روی همان نوار کلیک می‌کرد و دلیل امتیاز
// را نمی‌گرفت. متن نوار، خلاصهٔ چهار شاهد است؛ اینجا همان چهار شاهد
// به تفکیک توضیح داده می‌شوند تا امتیاز قابل بازمحاسبه باشد.
//
// فاز ۴۸ — این نوار دیگر فقط «ریسک برگشت» نیست: ردیف درجهٔ سیگنال و ردیف
// سناریوی در انتظار در همین یک خط ادغام شدند. پس یک کلیک باید **هر دو** روایت
// را بدهد: بخش اول کیفیت سیگنال، بخش دوم مقصد نقدینگی و شرط برگشت. تفکیک
// دو پنل برای یک ردیف، همان چیزی بود که کاربر مجبور می‌شد دو بار کلیک کند.
void ExplainRiskStripObject()
{
   g_expTitle="SIGNAL STRIP — خط مسیر: درجه، سطح، مقصد و شرط برگشت";
   ExpAddWrapped("چیست: این نوار یک خط خواندنی است، نه سیگنال — سر ردیف درجهٔ هم‌جهتی با بایاس است و بقیه شواهد همان کندل بسته را نشان می‌دهد", clrWhite);
   // فاز ۴۶: توضیح درجه. عدد برد، اندازه‌گیری‌شده روی نمونهٔ همین نماد است و
   // تعداد نمونه هم کنارش می‌آید تا کسی آن را وعدهٔ درصد نگیرد.
   ExpAddWrapped("درجه چطور ساخته شد: مجموع هفت شاهد سنجیده‌شده روی کندل بسته (خانوادهٔ نزدیک‌ترین سطح، فاصله تا آن سطح، جای قیمت در لگ، فاصله تا هدف نقدینگی، همسویی تایم‌فریم‌ها، جاروی نقدینگی، وضعیت فرسودگی)", clrAqua);
   ExpAdd(StringFormat("why: %s", g_gradeWhy), clrAqua);
   ExpAddWrapped("معنی عدد برد: درصدی که همین درجه در گذشتهٔ ثبت‌شدهٔ همین نماد به هدف رسیده؛ یک اندازه‌گیری است، نه وعده — و تعداد نمونه‌اش کنارش نوشته می‌شود", clrSilver);
   // فاز ۴۹: دو ردیف صادقانه — پروفایل همین نماد، و اینکه عدد نمایش‌داده‌شده
   // آیا از دادهٔ همین نماد است یا از جدول مرجع نماد دیگری.
   ExpAdd(StringFormat("symbol: %s | class: %s | base: %s | digits: %d | point: %s",
           _Symbol, SymbolClassCodeStr(), SymbolBaseName(),
           (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS), DoubleToString(_Point,8)), clrAqua);
   ExpAdd(StringFormat("point scale: %.2f | pip: %s | ref symbol: %s",
           SymbolPointScale(), DoubleToString(SymbolPipPrice(),8), GradeRefSymbolBase()), clrAqua);
   ExpAddWrapped("نماد این چارت: "+SymbolClassFa()+" — "+GradeSourceFa(), clrAqua);
   ExpAddWrapped("چرا مهم است: روی جفت‌ارز ۲/۴ رقمی، یک پوینت ۱۰ برابر بزرگ‌تر است؛ پس کف‌های پوینتی (تلورانس هم‌سطح‌ها و بافر حد ضرر) خودکار روی شبکهٔ مرجع تبدیل می‌شوند تا روی هر نماد همان معنی را بدهند", clrSilver);
   ExpAddWrapped("رنگ نوار: سبز = درجهٔ بالا، طلایی = متوسط، خاکستری = درجهٔ پایین؛ رنگ دربارهٔ کیفیت هم‌جهتی حرف می‌زند، نه دربارهٔ جهت", clrSilver);
   ExpAdd(StringFormat("family: %s", g_gradeFam), clrSilver);
   ExpAddWrapped("چطور خودت بسنجی: با ابزار سنجش همین مخزن، درجه و برد را از فایل ریسک برگشت بازتولید کن؛ اگر با هم نخواند، حساب غلط است", clrAqua);
   // ردیف کدهای نوار، تمام‌لاتین می‌ماند (قاعدهٔ فاز ۴۲: یک ردیف یا فقط لاتین،
   // یا لاتینش ابتدای همان ردیف). معنی هر کد در ردیف فارسی بعدی می‌آید.
   ExpAdd(StringFormat("grade: %s | score: %.2f | win: %.1f%% | n: %d",
           g_grade, g_gradeScore, g_gradeWin, g_gradeN), clrAqua);
   ExpAdd(StringFormat("bias: %s | level: %s | state: %s | score: %d/100",
           DirToStr(g_htfBias), g_rrLevel, g_rrLevelState, g_rrScore), clrAqua);
   ExpAdd(StringFormat("فاصله تا نزدیک‌ترین سطح: %.2f برابر میانگین دامنه  |  پیشرفت در لگ: %.0f درصد  |  فاصله تا هدف نقدینگی: %.2f برابر میانگین دامنه",
           g_rrLevelDist, g_rrLegProg, g_rrDolDist), clrAqua);
   ExpAdd("معنی کدهای بالا: سطح = نزدیک‌ترین سطح به قیمت، وضعیت = وضعیت همان سطح، امتیاز از ۱۰۰", clrSilver);
   if(g_hasDOL)
      ExpAdd("target: "+g_currentDOL.typeName+" @ "+DoubleToString(g_currentDOL.price,_Digits), clrSilver);
   // امتیاز، مجموع وزن‌های مستند است؛ فهرست شواهد از همان منبعی می‌آید که
   // نوار را ساخته، نه از یک محاسبهٔ موازی.
   ExpAddWrapped("چطور ساخته شد: امتیاز مجموع وزن‌های شاهدهای زیر است (وزن‌ها در ورودی‌های همان ماژول ثبت شده‌اند و «درصد» نیستند)", clrAqua);
   if(g_rrReasons=="") ExpAdd("evidence list: (خالی — هنوز هیچ شاهدی وزن نگرفته)", clrSilver);
   else ExpAdd("evidence list: "+g_rrReasons, clrSilver);
   ExpAdd("دریافت‌شده از آخرین کندل بسته — چند کندل از آخرین رویداد ساختاری گذشته: "+IntegerToString(g_rrEventBarsAgo), clrSilver);
   ExpAddWrapped("نقدینگی سمت بایاس در همین کندل جارو شد و پشت سطح بسته شد: "+(g_barSweptTowardBias? "بله — این یک شاهد برگشت است":"خیر"),
                 g_barSweptTowardBias? clrOrange : clrSilver);
   ExpAddWrapped("چرا مهم است: قبل از ورود هم‌جهت، این نوار می‌گوید خطر برگشت چقدر بالا رفته و نزدیک‌ترین سطح مقابل کجاست — پس می‌شود فهمید «ورود در جهت روند» در نقطه‌ای است که برگشت هم شواهد دارد یا نه", clrLime);
   ExpAddWrapped("چه چیزی آن را بی‌اعتبار می‌کند: اگر بایاس مالک یا نزدیک‌ترین سطح عوض شود، همهٔ اعداد همین نوار در همان کندل بسته بازحساب می‌شوند", clrOrange);
   ExpAddWrapped("کنترل خودت: همین اعداد را در فایل ریسک برگشت بگیر و با شاهدهای چارت بسنج؛ اگر امتیاز با شواهد نمی‌خواند، فهرست شواهد را نگاه کن", clrAqua);
   ExpAdd("reverse-risk report: ICT_Assistant_Canonical_ReverseRisk_<symbol>_<tf>.csv", clrSilver);
   // بخش دوم همان ردیف: مسیر و شرط برگشت. keepTitle=true تا عنوان بالا نماند
   // و هر دو روایت در یک پنل دیده شوند.
   ExplainPendingScenario(true);
   ExpAdd("object name: ICTv13_RSTRIP_TXT (read-only row, not draggable)", clrSilver);
}

// یک ردیف EDIT فقط‌خواندنی، راست‌چین، با پس‌زمینه و border مشکی تا هیچ
// درز/خط افقی دیده نشود. این همان کنترل native است که رندر درست متن خام
// فارسی با آن قبلاً تأیید شده است؛ فقط حالا یک ردیف به‌جای کل متن.
void ExplainEditRow(string name, int x, int y, int w, int h, string text, color clr, int fontSize)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_EDIT,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_FONT,InpExplainFont);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fontSize);
   ObjectSetInteger(0,name,OBJPROP_ALIGN,ALIGN_RIGHT);
   ObjectSetInteger(0,name,OBJPROP_READONLY,true);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,clrBlack);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,clrBlack);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

// ---------------- رندر پنل چندخطی ----------------
// هر خط توضیح یک OBJ_EDIT مستقل و پشت‌سرهم (بدون فاصله) است.
// OBJ_EDIT تک‌خطی است، پس نسخهٔ قبلی که همهٔ خطوط را در یک EDIT می‌ریخت
// همهٔ خطوط بعد از اولی را از بین می‌برد. رنگ هر خط هم حفظ می‌شود.
void RenderExplainPanel()
{
   int total=ArraySize(g_expLines);
   if(!InpShowExplainPanel || total==0)
   {
      for(int i=0;i<=g_expPanelRows;i++) ObjectDelete(0,"ICTv13_EXP_"+IntegerToString(i));
      ObjectDelete(0,"ICTv13_EXP_TEXT");   // باقی‌ماندهٔ نسخهٔ تک‌EDIT قبلی
      ObjectDelete(0,"ICTv13_EXP_BG");
      g_expPanelRows=0;
      ChartRedraw(0);
      return;
   }
   if(total>InpExplainMaxRows) total=InpExplainMaxRows;

   int lineH   = InpExplainFontSize+11;
   int padX    = 6;
   int padY    = 6;
   int rows    = total+1;                       // عنوان + خطوط توضیح
   int height  = rows*lineH + padY*2;
   int chartW  = (int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
   int chartH  = (int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   int xPos    = g_expAnchorX+18;
   int yPos    = g_expAnchorY-20;
   if(xPos+InpExplainPanelWidth>chartW-10) xPos=MathMax(5,g_expAnchorX-InpExplainPanelWidth-18);
   if(yPos+height>chartH-10)              yPos=MathMax(5,chartH-height-10);
   if(yPos<5) yPos=5;

   string bg="ICTv13_EXP_BG";
   if(ObjectFind(0,bg)<0) ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bg,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,xPos);
   ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,yPos);
   ObjectSetInteger(0,bg,OBJPROP_XSIZE,InpExplainPanelWidth);
   ObjectSetInteger(0,bg,OBJPROP_YSIZE,height);
   ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,clrBlack);
   ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,bg,OBJPROP_COLOR,PAL_PANEL_BORDER);
   ObjectSetInteger(0,bg,OBJPROP_BACK,false);
   ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,bg,OBJPROP_HIDDEN,true);

   int editX = xPos+padX;
   int editW = InpExplainPanelWidth-padX*2;

   // ردیف ۰: عنوان
   ExplainEditRow("ICTv13_EXP_0", editX, yPos+padY, editW, lineH,
                  RenderLine(g_expTitle,InpExplainRenderMode), clrGold, InpExplainFontSize+1);

   // ردیف‌های ۱..total: هر خط مستقل، راست‌چین، با رنگ خودش
   for(int i=0;i<total;i++)
      ExplainEditRow("ICTv13_EXP_"+IntegerToString(i+1), editX, yPos+padY+(i+1)*lineH, editW, lineH,
                     RenderLine(g_expLines[i],InpExplainRenderMode), g_expLineColors[i], InpExplainFontSize);

   g_expPanelRows=total+1;   // تعداد واقعی ردیف‌های EXP_ ساخته‌شده (۰..total)

   // بدنِ تک‌EDIT قدیمی و ردیف‌های مانده از رندر قبلی را پاک کن
   ObjectDelete(0,"ICTv13_EXP_TEXT");
   for(int k=total+1;k<=InpExplainMaxRows+2;k++)
      ObjectDelete(0,"ICTv13_EXP_"+IntegerToString(k));

   ChartRedraw(0);
}

// ---------------- ذخیرهٔ توضیح‌ها در CSV برای بررسی عددی ----------------
void ExplainSaveCsv()
{
   int h=FileOpen("ICT_Assistant_Canonical_Explain.csv",FILE_COMMON|FILE_WRITE|FILE_CSV|FILE_UNICODE,';');
   if(h==INVALID_HANDLE) return;
   FileWrite(h,"Object","Kind","Price","Time","Summary");

   string savedTitle=g_expTitle;
   string savedLines[]; color savedColors[];
   int nSaves=ArraySize(g_expLines);
   ArrayResize(savedLines,nSaves); ArrayResize(savedColors,nSaves);
   for(int i=0;i<nSaves;i++){ savedLines[i]=g_expLines[i]; savedColors[i]=g_expLineColors[i]; }

   int total=ObjectsTotal(0,-1,-1);
   int written=0;
   for(int i=0;i<total && written<(InpMaxDrawnLevels+InpMaxDrawnZones*3+60);i++)
   {
      string nm=ObjectName(0,i,-1,-1);
      if(StringFind(nm,"ICTv13_")!=0) continue;
      if(StringFind(nm,"ICTv13_DASH_")==0) continue;
      if(StringFind(nm,"ICTv13_EXP_")==0)  continue;
      long otype=ObjectGetInteger(0,nm,OBJPROP_TYPE);
      if(otype==OBJ_RECTANGLE_LABEL||otype==OBJ_LABEL) continue;   // داشبورد و پنل

      ExpClear();
      BuildExplanation(nm);
      if(ArraySize(g_expLines)==0) continue;

      double price=0.0;
      datetime t=0;
      if(otype==OBJ_HLINE) price=ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
      else
      {
         price=ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
         t=(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,0);
      }
      string summary="";
      for(int k=0;k<ArraySize(g_expLines);k++)
      {
         summary += g_expLines[k];
         if(k<ArraySize(g_expLines)-1) summary += " ~ ";
      }
      FileWrite(h,nm,g_expTitle,DoubleToString(price,_Digits),
                t>0? TimeToString(t,TIME_DATE|TIME_MINUTES) : "", summary);

      // فاز ۲۲: متن آموزشی کوتاه به‌صورت tooltip روی خود آبجکت.
      // این مسیر مستقل از پنل EDIT است: حتی اگر پنل بسته/جابه‌جا باشد،
      // خودِ آبجکت توضیح می‌دهد. هر خط جداگانه با شکل‌دهی دستی و ترتیب
      // بصری رندر می‌شود تا در رندرگر بدون bidi هم حروف جدا نشوند و
      // ترتیب کلمات برنگردد. خطوط با \n به tooltip چندخطی تبدیل می‌شوند.
      // فاز ۲۵ — یک مسیر رندر واحد: پنل و tooltip هر دو از RenderLine عبور
      // می‌کنند. tooltip متن خام منطقی را برعکس نشان می‌داد (رندرگر ترمینال
      // همان مسیری است که bidi/shaping را برای آبجکت‌های متنی از دست داده —
      // گزارش انجمن MQL5 ۵۰۴۵۲۲)؛ با یکسان‌کردن مسیر، تنها تنظیم لازم برای هر
      // دو سطح InpExplainRenderMode است. متن خالی هم همیشه نوشته می‌شود تا با
      // خاموش‌کردن ورودی، tooltip کهنهٔ همان آبجکت پاک شود.
      string tip="";
      if(InpSetObjectTooltips)
      {
         tip=RenderLine(g_expTitle,InpExplainRenderMode);
         for(int k=0;k<ArraySize(g_expLines) && k<3;k++)
            tip += "\n" + RenderLine(g_expLines[k],InpExplainRenderMode);
         if(InpExplainTooltipMaxChars>0 && StringLen(tip)>InpExplainTooltipMaxChars)
            tip=StringSubstr(tip,0,InpExplainTooltipMaxChars)+"...";
      }
      ObjectSetString(0,nm,OBJPROP_TOOLTIP,tip);
      written++;
   }
   FileClose(h);

   // بازگرداندن پنل فعلی (اگر بازیابی نشود، توضیح روی‌موس از دست می‌رفت)
   ArrayResize(g_expLines,nSaves);
   ArrayResize(g_expLineColors,nSaves);
   for(int i=0;i<nSaves;i++){ g_expLines[i]=savedLines[i]; g_expLineColors[i]=savedColors[i]; }
   g_expTitle=savedTitle;
}

// فاز ۲۵: اگر هر دو کانال توضیح خاموش باشند (نه CSV، نه tooltip) ولی پیش‌تر
// tooltip روشن بوده، tooltipهای کهنه یک‌بار پاک می‌شوند تا روی چارت نمانند.
void ExplainClearStaleTooltips()
{
   static bool done=false;
   if(done) return;
   done=true;
   int total=ObjectsTotal(0,-1,-1);
   for(int i=0;i<total;i++)
   {
      string nm=ObjectName(0,i,-1,-1);
      if(StringFind(nm,"ICTv13_")!=0) continue;
      ObjectSetString(0,nm,OBJPROP_TOOLTIP,"");
   }
}

// ---------------- تشخیصی فاز ۸: دیکشنری وضعیت FVG (فقط-خواندنی) ----------------
// هر FVG رجیستری را با عمر، وضعیت و زمان اولین لمس می‌نویسد تا پرسش
// «چرا هیچ FVG ای FRESH نیست» با داده پاسخ بگیرد، نه با حدس.
// منطق تشخیصی هیچ تغییری نمی‌کند؛ این تابع فقط یک CSV در Common\Files می‌سازد.
void PersistFVGDictionary()
{
   int h=FileOpen("ICT_Assistant_Canonical_FVG_Diag.csv",FILE_COMMON|FILE_WRITE|FILE_CSV|FILE_UNICODE,';');
   if(h==INVALID_HANDLE) return;
   // فاز ۴۳: «Dir» به «DirBirth» تغییر نام داد و ستون‌های Role/ActiveDir/InvertedAt
   // اضافه شدند. دلیل: یک ستون به اسم Dir که هم جهت تولد و هم (پیش‌تر) جهت بازنویسی‌شده
   // را نگه می‌داشت، همان منبع تناقض بود؛ حالا هیچ عددی در این فایل دو معنی ندارد.
   FileWrite(h,"Id","DirBirth","Time","AgeBars","Top","Bottom","Causal",
             "Mitigated","Inverted","InvertedAt","Role","ActiveDir","Invalidated","TouchTime","BarsToTouch","BirthBarTouch");
   int secs=PeriodSeconds(PERIOD_CURRENT);
   if(secs<=0) secs=60;
   datetime now=(datetime)TimeCurrent();
   for(int i=0;i<ArraySize(g_fvgs);i++)
   {
      FVGObj f=g_fvgs[i];
      int ageBars=(f.createdTime>0)? (int)((now-f.createdTime)/secs) : 0;
      int barsToTouch=(f.touchTime>0 && f.createdTime>0)? (int)((f.touchTime-f.createdTime)/secs) : -1;
      FileWrite(h,IdToStr(f.id),
                (f.direction==DIR_BULL?"BULL":"BEAR"),
                TimeToString(f.time,TIME_DATE|TIME_MINUTES),
                ageBars,
                DoubleToString(f.top,_Digits),
                DoubleToString(f.bottom,_Digits),
                (f.causal?"1":"0"),
                (f.mitigated?"1":"0"),
                (f.inverted?"1":"0"),
                f.invertedTime>0? TimeToString(f.invertedTime,TIME_DATE|TIME_MINUTES): "",
                FVGPolarityReport(f),
                (FVGActiveDir(f)==DIR_BULL?"BULL":"BEAR"),
                (f.invalidated?"1":"0"),
                f.touchTime>0? TimeToString(f.touchTime,TIME_DATE|TIME_MINUTES): "",
                barsToTouch,
                (f.birthBarTouch?"1":"0"));
   }
   FileClose(h);
}

// دیکشنری لگ واقعی + سطوح مکان (فاز ۱۰). پیوت‌های خام (قیمت دو سر لگ) هم
// نوشته می‌شوند تا بتوان همهٔ اعداد (EQ/OTE/طلایی) را از دادهٔ خام به‌صورت
// مستقل بازمحاسبه کرد؛ ابزار: tools/Validate-DealingLeg.ps1
void PersistLegDictionary()
{
   int h=FileOpen("ICT_Assistant_Canonical_Leg_Diag.csv",FILE_COMMON|FILE_WRITE|FILE_CSV|FILE_UNICODE,';');
   if(h==INVALID_HANDLE) return;
   FileWrite(h,"Time","Symbol","ChartTF","LegValid","Reject","LegDir","StartTime","StartPrice",
             "EndTime","EndPrice","Low","High","Range","SizeATR","ATR","EQ","OTELow","OTEHigh","Golden",
             "AnalysisClose","Side","StopsLevelPts","MinLegATRInput","OTELowInput","OTEHighInput","GoldenInput",
             "SetupStatus","Entry","SL","TP3","Risk","RR","ZoneSource","ChainSweep","ChainEvent","ChainDisp");
   double range=g_leg.range;
   double oteLow=0, oteHigh=0, golden=0;
   if(g_leg.valid)
   {
      if(g_leg.dir==DIR_BULL)
      {
         oteLow  = g_leg.high - range*InpOTE_High;
         oteHigh = g_leg.high - range*InpOTE_Low;
         golden  = g_leg.high - range*InpOTE_Golden;
      }
      else
      {
         oteLow  = g_leg.low + range*InpOTE_Low;
         oteHigh = g_leg.low + range*InpOTE_High;
         golden  = g_leg.low + range*InpOTE_Golden;
      }
   }
   FileWrite(h,TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES), _Symbol, EnumToString(PERIOD_CURRENT),
             (g_leg.valid?"1":"0"), g_leg.reject, DirToStr(g_leg.dir),
             g_leg.startTime>0? TimeToString(g_leg.startTime,TIME_DATE|TIME_MINUTES):"",
             DoubleToString(g_leg.startPrice,_Digits),
             g_leg.endTime>0? TimeToString(g_leg.endTime,TIME_DATE|TIME_MINUTES):"",
             DoubleToString(g_leg.endPrice,_Digits),
             DoubleToString(g_leg.low,_Digits), DoubleToString(g_leg.high,_Digits),
             DoubleToString(range,_Digits), DoubleToString(g_leg.sizeATR,3), DoubleToString(g_analysisATR,_Digits),
             DoubleToString(g_leg.eq,_Digits), DoubleToString(oteLow,_Digits), DoubleToString(oteHigh,_Digits),
             DoubleToString(golden,_Digits),
             DoubleToString(g_analysisClose,_Digits),
             (g_leg.valid && g_analysisClose>=g_leg.eq)?"PREMIUM":"DISCOUNT",
             (int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
             DoubleToString(InpMinLegATR,3), DoubleToString(InpOTE_Low,3), DoubleToString(InpOTE_High,3), DoubleToString(InpOTE_Golden,3),
             g_setup.status, DoubleToString(g_setup.entry,_Digits), DoubleToString(g_setup.sl,_Digits),
             DoubleToString(g_setup.tp3,_Digits), DoubleToString(g_setup.risk,_Digits), DoubleToString(g_setup.rr,4),
             g_setup.zoneSource, IdToStr(g_setup.chainSweepId), IdToStr(g_setup.chainEventId), IdToStr(g_setup.chainDispId));
   FileClose(h);
}

// ---------------- رویدادهای چارت: باز/بستن پنل آموزشی ----------------
// مشترک بین دو حالت (کلیک و hover).
void ExplainOpenAt(int mx, int my)
{
   string hit=HitTestExplainObject(mx,my);
   if(hit==g_expHovered) return;          // هدف عوض نشده: پنل همان‌طور بماند
   g_expHovered=hit;
   ExpClear();
   if(hit=="")
   {
      RenderExplainPanel();               // فضای خالی → بستن
      return;
   }
   g_expAnchorX=mx;
   g_expAnchorY=my;
   BuildExplanation(hit);
   RenderExplainPanel();
}

void ExplainClosePanel()
{
   if(g_expHovered=="") return;
   g_expHovered="";
   ExpClear();
   RenderExplainPanel();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // ---- فاز ۲۷ (طراحی پروژه): مسیر پیش‌فرض «کلیک» است ----
   // CHARTEVENT_CLICK: lparam = X و dparam = Y کلیک.
   if(id==CHARTEVENT_CLICK)
   {
      if(InpExplainOpen!=EXPLAIN_OPEN_CLICK) return;
      if(!InpShowExplainPanel) return;
      int cx=(int)lparam, cy=(int)dparam;
      if(cx<0 || cy<0) return;
      string hit=HitTestExplainObject(cx,cy);
      if(hit!="" && hit==g_expHovered)
      {
         ExplainClosePanel();        // کلیک دوباره روی همان آبجکت = بستن
         return;
      }
      ExplainOpenAt(cx,cy);          // آبجکت جدید، یا فضای خالی (= بستن)
      return;
   }

   // ESC = بستن پنل در هر دو حالت.
   if(id==CHARTEVENT_KEYDOWN && lparam==27)
   {
      ExplainClosePanel();
      return;
   }

   // ---- حالت اختیاری HOVER (پیش‌فرض نیست؛ فقط اگر کاربر خودش بخواهد) ----
   if(id!=CHARTEVENT_MOUSE_MOVE) return;
   if(InpExplainOpen!=EXPLAIN_OPEN_HOVER) return;
   int mx=(int)lparam;
   int my=(int)dparam;
   if(mx<0 || my<0)
   {
      ExplainClosePanel();
      return;
   }
   ExplainOpenAt(mx,my);
}

//====================================================================
// فاز ۴۴ — آزمون مسیر کلیک بدون موس
//====================================================================
// مشکل واقعی: مسیر کلیک هیچ تست خودکاری نداشت. ابزارهای PowerShell فقط متن
// سورس را grep می‌کنند (و ثابت می‌کنند «رشته هست»)، ولی این مسیر سه مرحلهٔ
// زمان‌اجرا دارد که هیچ‌کدام با grep سنجیده نمی‌شود:
//   ۱) hit-test پیکسلی: تبدیل قیمت/زمان به پیکسل و انتخاب درست آبجکت
//   ۲) پیدا شدن مرجع آبجکت در رجیستری (شناسهٔ داخل نام)
//   ۳) ساخته شدن متن توضیح برای همان مرجع
// این آزمون دقیقاً همین سه مرحله را با همان توابع زنده اجرا می‌کند: برای هر
// آبجکت قابل‌کلیک روی چارت، مرکز پیکسلی‌اش را با همان helperهایی حساب می‌کند
// که خود hit-test استفاده می‌کند، بعد همان `HitTestExplainObject` را صدا
// می‌زند و در پایان همان سازندهٔ پنل. نتیجه در CSV شاهد می‌نشیند.
//
// آزمون در پایان بازسازی اجرا می‌شود: آن لحظه آبجکت‌ها روی چارت هستند و هیچ
// کلیکی رخ نداده، پس آزمایش روی تحلیل زنده اثر ندارد. در پایان پنل پاک می‌شود.

// مرکز پیکسلی یک آبجکت، با همان مسیر تبدیل hit-test (نه یک مسیر موازی).
bool ClickTestCenterOf(string nm, int chartH, double refPrice, datetime tVis, int &cx, int &cy)
{
   cx=0; cy=0;
   long otype=ObjectGetInteger(0,nm,OBJPROP_TYPE);
   if(otype==OBJ_HLINE)
   {
      double p=ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
      if(p<=0.0) return false;
      if(!ExplainTimeToX(tVis,cx)) return false;
      cy=ExplainPriceToY(tVis,p,refPrice,chartH);
      return true;
   }
   datetime t0=(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,0);
   datetime t1=(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,1);
   double   p0=ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
   double   p1=ObjectGetDouble(0,nm,OBJPROP_PRICE,1);
   if(otype==OBJ_TEXT)
   {
      if(!ExplainTimeToX(t0,cx)) return false;
      cy=ExplainPriceToY(t0,p0,refPrice,chartH);
      return true;
   }
   int x1=0,x2=0;
   if(!ExplainTimeToX(t0,x1) || !ExplainTimeToX(t1,x2)) return false;
   int y1=ExplainPriceToY(tVis,p0,refPrice,chartH);
   int y2=ExplainPriceToY(tVis,p1,refPrice,chartH);
   cx=(x1+x2)/2;
   cy=(y1+y2)/2;
   return true;
}

void RunClickPathSelfTest()
{
   if(!InpRunClickPathSelfTest) return;

   int chartW=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
   int chartH=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   if(chartW<=0 || chartH<=0) return;
   double refPrice=(g_analysisClose>0.0)? g_analysisClose : iClose(_Symbol,PERIOD_CURRENT,0);
   datetime tVis=ExplainVisibleTime();

   int h=FileOpen("ICT_Assistant_Canonical_Click_Diag.csv",
                  FILE_COMMON|FILE_WRITE|FILE_CSV|FILE_UNICODE,';');
   if(h==INVALID_HANDLE) return;
   FileWrite(h,"Object","ResolveStatus","Reason","Title","Lines",
             "CenterX","CenterY","OnScreen","HitObject","HitIsSelf","HitLines");

   g_clickTestObjects=0; g_clickTestResolved=0; g_clickTestEmpty=0;
   g_clickTestOffscreen=0; g_clickTestSelfHit=0; g_clickTestWeakHit=0;

   int total=ObjectsTotal(0,-1,-1);
   for(int i=0;i<total && g_clickTestObjects<InpClickDiagMaxObjects;i++)
   {
      string nm=ObjectName(0,i,-1,-1);
      if(StringFind(nm,"ICTv13_")!=0) continue;
      // داشبورد/پنل خودشان آبجکت‌های خواندنی‌اند، نه لایهٔ تحلیل؛ hit-test هم
      // عمداً آن‌ها را نادیده می‌گیرد، پس در آزمون کلیک هم نمی‌آیند.
      if(StringFind(nm,"ICTv13_DASH_")==0) continue;
      if(StringFind(nm,"ICTv13_EXP_")==0)  continue;
      long otype=ObjectGetInteger(0,nm,OBJPROP_TYPE);
      if(otype==OBJ_RECTANGLE_LABEL||otype==OBJ_LABEL) continue;

      g_clickTestObjects++;

      // مرحلهٔ ۲ و ۳: همان چیزی که یک کلیک روی همین آبجکت اجرا می‌کند.
      ExpClear();
      ENUM_CLICK_RESOLVE st=ExplainBuildDetailed(nm);
      string reason=g_clickReason;
      string title=g_expTitle;
      int    lines=ArraySize(g_expLines);
      if(st==CLICK_RS_OK) g_clickTestResolved++; else g_clickTestEmpty++;

      // مرحلهٔ ۱: شبیه‌سازی کلیک روی مرکز خود آبجکت
      int cx=0,cy=0;
      string hit=""; int hitLines=0; int self=0; int onScreen=0;
      if(ClickTestCenterOf(nm,chartH,refPrice,tVis,cx,cy))
      {
         if(cx>=0 && cx<chartW && cy>=-4 && cy<=chartH+4)
         {
            onScreen=1;
            hit=HitTestExplainObject(cx,cy);
            if(hit!=""){ self=(hit==nm)?1:0; ExpClear(); ExplainBuildDetailed(hit); hitLines=ArraySize(g_expLines); }
         }
      }
      if(!onScreen) g_clickTestOffscreen++;
      if(onScreen && hit=="") g_clickTestWeakHit++;
      if(self==1) g_clickTestSelfHit++;

      FileWrite(h,nm,(st==CLICK_RS_OK? "RESOLVED":"FALLBACK"),reason,title,lines,
                cx,cy,onScreen,hit,self,hitLines);
   }
   FileClose(h);

   // پنل باید تمیز بماند: آزمون نباید چیزی روی چارت جا بگذارد.
   g_expHovered="";
   ExpClear();

   Print(StringFormat("ICT PHASE44 | click path self-test | objects=%d resolved=%d no-handler=%d offscreen=%d center-hit-miss=%d center-hit-self=%d | report ICT_Assistant_Canonical_Click_Diag.csv",
         g_clickTestObjects,g_clickTestResolved,g_clickTestEmpty,g_clickTestOffscreen,
         g_clickTestWeakHit,g_clickTestSelfHit));
}

