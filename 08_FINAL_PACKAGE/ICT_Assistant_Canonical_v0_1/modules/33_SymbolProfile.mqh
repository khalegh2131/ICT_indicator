//====================================================================
// فاز ۴۹ — پروفایل نماد: «همهٔ نمادها، ماژور و مینور»
//
// چرا این فایل ساخته شد
// --------------------
// تا فاز ۴۸ همهٔ اندازه‌گیری‌ها روی یک نماد (طلا) انجام شده بود و دو چیز
// به‌ازای هر نماد عوض می‌شود ولی کد آن را ثابت گرفته بود:
//
// ۱) **واحد پوینت.** «۱۵ پوینت» روی XAUUSD.x (۲ رقم، _Point=۰٫۰۱) می‌شود
//    ۰٫۱۵ دلار؛ همان «۱۵ پوینت» روی EURUSD.x (۵ رقم، _Point=۰٫۰۰۰۰۱) می‌شود
//    ۰٫۰۰۰۱۵. نسبت به ATR، دومی حدود ۱۶ برابر رقیق‌تر است — یعنی کف‌های
//    پوینتی (تلورانس EQH/EQL و بافر SL) روی جفت‌ارز چیز دیگری معنی می‌دادند.
//    روی بروکر ۴ رقمی ماجرا بدتر است: همان ورودی ۱۰ برابر گشادتر می‌شود.
//
// ۲) **کالیبراسیون درجه.** جدول لیفت‌های ۳۱_SignalGrade روی دادهٔ طلا فیت شده
//    است. اگر همان نرخ‌ها (مثلاً «۲۵٫۸٪ با ۳۲۹۹ نمونه») روی یورو نشان داده
//    شود، کاربر عددی می‌بیند که به نماد او تعلق ندارد — و همین بی‌اعتمادی
//    می‌سازد. راه‌حل: اعداد به‌ازای هر نماد از فایل کالیبراسیون خوانده می‌شوند و
//    اگر فایل نباشد، صریح اعلام می‌شود که این اعداد «مرجع»اند نه «اندازه‌گیری
//    همین نماد».
//
// هر دو تغییر **رفتار روی XAUUSD را دست‌نخورده** می‌گذارند: طلا نماد
// «پیپ‌دار» نیست، پس ضریب پوینت ۱٫۰ می‌ماند و کف هم مثل قبل حساب می‌شود.
//
// هیچ نام نمادی در منطق نیست؛ طبقهٔ هر نماد از خودِ ترمینال خوانده می‌شود.
//====================================================================

// --- کدهای ارز رایج برای تشخیص جفت‌ارز (بدون نام نماد خاص)
bool IsFxCurrencyCode(string c)
{
   return (c=="USD"||c=="EUR"||c=="GBP"||c=="JPY"||c=="CHF"||c=="CAD"||c=="AUD"||c=="NZD");
}

// --- نام پایهٔ نماد: پسوند بروکر حذف می‌شود («EURUSD.x» → «EURUSD»).
// قاعده: از ابتدای نام، فقط حروف و ارقام؛ اولین کاراکتر دیگر پایان می‌دهد.
string SymbolBaseName(const string sym="")
{
   string s=(StringLen(sym)>0)? sym : _Symbol;
   string out="";
   for(int i=0;i<StringLen(s);i++)
   {
      ushort c=StringGetCharacter(s,i);
      bool ok=((c>='A'&&c<='Z')||(c>='a'&&c<='z')||(c>='0'&&c<='9'));
      if(!ok) break;
      out+=ShortToString(c);
   }
   if(StringLen(out)==0) out=s;
   StringToUpper(out);
   return out;
}

// --- آیا این نماد «پیپ‌دار» است (جفت‌ارز)؟ طلا/شاخص/کریپتو پیپ ندارند.
bool IsPipQuotedSymbol()
{
   ENUM_SYM_CLASS c=SymbolClassCode();
   return (c==SYMCLS_FX_MAJOR || c==SYMCLS_FX_MINOR);
}

// --- کلیدواژهٔ موجود در نام (فهرست با کاما)
bool NameHasKeyword(string name, string list)
{
   string parts[];
   int n=StringSplit(list,',',parts);
   for(int i=0;i<n;i++)
   {
      string k=parts[i];
      StringTrimLeft(k); StringTrimRight(k);
      if(StringLen(k)>0 && StringFind(name,k)>=0) return true;
   }
   return false;
}

// --- طبقهٔ نماد: از نام پایه (قطعی و قابل توضیح)، با تأیید از مسیر نماد.
ENUM_SYM_CLASS SymbolClassCode()
{
   string b=SymbolBaseName();
   // مسیر ترمینال (مثلاً «Forex\Majors» یا «Crypto») اگر موجود باشد، شاهد دوم است.
   string path=SymbolInfoString(_Symbol,SYMBOL_PATH);
   StringToUpper(path);

   // جفت‌ارز: نام ۶ حرفی که دو سرش کد ارز است.
   if(StringLen(b)==6 &&
      IsFxCurrencyCode(StringSubstr(b,0,3)) && IsFxCurrencyCode(StringSubstr(b,3,3)))
      return ((StringSubstr(b,0,3)=="USD" || StringSubstr(b,3,3)=="USD") ? SYMCLS_FX_MAJOR
                                                                       : SYMCLS_FX_MINOR);
   // فلز
   if(NameHasKeyword(b,"XAU,XAG,XPT,XPD,GOLD,SILVER")) return SYMCLS_METAL;
   // رمزارز
   if(NameHasKeyword(b,"BTC,ETH,XRP,LTC,SOL,DOGE,ADA,BNB,DOT,AVAX"))  return SYMCLS_CRYPTO;
   // انرژی
   if(NameHasKeyword(b,"WTI,BRENT,OIL,NGAS,NATGAS,XNG"))              return SYMCLS_ENERGY;
   // شاخص‌ها: فهرست استاندارد نمادهای رایج
   if(NameHasKeyword(b,"US30,DJ30,US500,SPX500,SP500,NAS100,US100,US2000,USTEC,"
                        "DE30,DE40,GER30,GER40,DAX,UK100,JP225,NIKKEI,FR40,CAC,"
                        "EU50,STOXX,ES35,IT40,AU200,HK50,CHINA50,CHINA,HK33"))
      return SYMCLS_INDEX;
   // مسیر ترمینال به‌عنوان شاهد آخر
   if(StringFind(path,"FOREX")>=0 || StringFind(path,"FX")>=0) return SYMCLS_FX_MINOR;
   if(StringFind(path,"METAL")>=0)  return SYMCLS_METAL;
   if(StringFind(path,"INDEX")>=0 || StringFind(path,"INDICES")>=0) return SYMCLS_INDEX;
   if(StringFind(path,"CRYPTO")>=0) return SYMCLS_CRYPTO;
   return SYMCLS_OTHER;
}

string SymbolClassCodeStr()
{
   ENUM_SYM_CLASS c=SymbolClassCode();
   if(c==SYMCLS_FX_MAJOR) return "FX_MAJOR";
   if(c==SYMCLS_FX_MINOR) return "FX_MINOR";
   if(c==SYMCLS_METAL)    return "METAL";
   if(c==SYMCLS_INDEX)    return "INDEX";
   if(c==SYMCLS_CRYPTO)   return "CRYPTO";
   if(c==SYMCLS_ENERGY)   return "ENERGY";
   return "OTHER";
}

string SymbolClassFa()
{
   ENUM_SYM_CLASS c=SymbolClassCode();
   if(c==SYMCLS_FX_MAJOR) return "جفت‌ارز ماژور (یک سر دلار)";
   if(c==SYMCLS_FX_MINOR) return "جفت‌ارز مینور/کراس (بدون دلار)";
   if(c==SYMCLS_METAL)    return "فلز";
   if(c==SYMCLS_INDEX)    return "شاخص";
   if(c==SYMCLS_CRYPTO)   return "رمزارز";
   if(c==SYMCLS_ENERGY)   return "انرژی";
   return "سایر";
}

// --- ضریب پوینت: ورودی‌های پوینتی روی شبکهٔ مرجع (۵ رقمی، پیپ=۱۰ پوینت)
// تنظیم شده‌اند. روی نماد ۲/۴ رقمی هر پوینت ۱۰ برابر بزرگ‌تر است، پس ورودی
// باید ۰٫۱ ضرب شود تا همان فاصلهٔ پیپی بماند. روی طلا/شاخص/کریپتو ضریب ۱٫۰
// است ⇒ رفتار فاز ۴۸ بیت‌به‌بیت دست‌نخورده.
double SymbolPointScale()
{
   if(!InpAutoPointScale) return 1.0;   // خاموش‌کردن = بازگشت به رفتار فاز ۴۸
   if(!IsPipQuotedSymbol()) return 1.0;
   int d=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   if(d==3 || d==5) return 1.0;   // شبکهٔ مرجع: پیپ = ۱۰ پوینت
   if(d==2 || d==4) return 0.1;   // یک پوینت = یک پیپ ⇒ ۱۰ برابر بزرگ‌تر
   return 1.0;
}

// --- کف پوینتی با واحد قابل‌حمل (جایگزین PointsToPrice برای کف‌های تنظیمی)
double PointFloorPrice(double pts) { return pts * SymbolPointScale() * _Point; }

// --- پیپ نماد بر حسب قیمت (برای نمایش و توضیح)
double SymbolPipPrice()
{
   int d=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   if(d==3 || d==5) return 10.0*_Point;
   return _Point;
}

//====================================================================
// کالیبراسیون درجه به‌ازای هر نماد
//====================================================================
double CalNum(string s)
{
   string out="";
   for(int i=0;i<StringLen(s);i++)
   {
      ushort c=StringGetCharacter(s,i);
      if((c>='0'&&c<='9')||c=='.'||c=='-'||c=='+') out+=ShortToString(c);
   }
   if(StringLen(out)==0) return 0.0;
   return StringToDouble(out);
}

void CalPut(string k, double v)
{
   int n=ArraySize(g_calKeys);
   ArrayResize(g_calKeys, n+1);
   ArrayResize(g_calVals, n+1);
   g_calKeys[n]=k; g_calVals[n]=v;
}

// جست‌وجوی خطی: جدول کالیبراسیون کوچک است (چند ده ردیف)، پس این هزینه در
// هر کندل بسته ناچیز است و در ازای آن هیچ چون‌ودر‌چرا در مدیریت حافظه نداریم.
double CalGet(string k, double dflt)
{
   int n=ArraySize(g_calKeys);
   for(int i=0;i<n;i++) if(g_calKeys[i]==k) return g_calVals[i];
   return dflt;
}

string GradeCalibFileName(int variant)
{
   string base=SymbolBaseName();
   string tf=ChartTfCode();
   if(variant==0) return "ICT_Assistant_Canonical_GradeCalib_"+base+"_"+tf+".csv";
   if(variant==1) return "ICT_Assistant_Canonical_GradeCalib_"+base+".csv";
   if(variant==2) return "ICT_Assistant_Canonical_GradeCalib_"+_Symbol+"_"+tf+".csv";
   return "ICT_Assistant_Canonical_GradeCalib_"+_Symbol+".csv";
}

// خروجی: true اگر فایل کالیبراسیون همین نماد/تایم‌فریم پیدا و خوانده شد.
bool LoadGradeCalibration()
{
   g_calLoaded=false; g_calRows=0; g_calSource="none";
   ArrayResize(g_calKeys,0); ArrayResize(g_calVals,0);
   g_calSymbol="";
   if(!InpGradeCalibAuto) return false;
   for(int v=0; v<4; v++)
   {
      string fn=GradeCalibFileName(v);
      if(!FileIsExist(fn,FILE_COMMON)) continue;
      int h=FileOpen(fn,FILE_COMMON|FILE_READ|FILE_CSV|FILE_SHARE_READ|FILE_SHARE_WRITE,';');
      if(h==INVALID_HANDLE) continue;
      while(!FileIsEnding(h))
      {
         string k=FileReadString(h);
         StringTrimLeft(k); StringTrimRight(k);
         if(FileIsEnding(h) && StringLen(k)==0) break;
         string vs=FileReadString(h);
         if(StringLen(k)==0) continue;
         if(StringGetCharacter(k,0)=='#') continue;
         CalPut(k, CalNum(vs));
      }
      FileClose(h);
      g_calRows=ArraySize(g_calKeys);
      if(g_calRows>0)
      {
         g_calLoaded=true;
         g_calSource="self";
         g_calSymbol=SymbolBaseName();
         return true;
      }
   }
   return false;
}

// --- نام پایهٔ نماد مرجعی که جدول ثابت ۳۱_SignalGrade رویش فیت شده است.
string GradeRefSymbolBase() { return SymbolBaseName(InpGradeRefSymbol); }

// --- آیا اعداد نمایش‌داده‌شده به **همین نماد** تعلق دارند؟
bool GradeCalibrated()
{
   if(g_calLoaded) return true;
   return (SymbolBaseName()==GradeRefSymbolBase());
}

// --- متن صادقانهٔ منبع کالیبراسیون (برای نوار و پنل)
string GradeSourceFa()
{
   if(g_calLoaded)
      return StringFormat("کالیبره‌شده برای همین نماد از فایل (%d ردیف)", g_calRows);
   if(GradeCalibrated())
      return StringFormat("کالیبره‌شده روی همین نماد (جدول مرجع %s)", GradeRefSymbolBase());
   if(InpGradeUncalibrated==GRUNC_SUPPRESS)
      return StringFormat("این نماد کالیبره نشده است (مرجع: %s) — درجه نمایش داده نمی‌شود", GradeRefSymbolBase());
   return StringFormat("این نماد کالیبره نشده است — درجه از جدول مرجع %s می‌آید، نه از دادهٔ همین نماد",
                       GradeRefSymbolBase());
}

// --- شاهد زمان‌اجرا: یک ردیف در هر attach با همهٔ اعداد پروفایل نماد.
// ستون‌ها طوری چیده شده‌اند که ابزار قفل‌کننده بتواند طبقه و ضریب را
// مستقل بازحساب کند (نسبت ضریب به رقمت و کلاس نماد).
void WriteSymbolProfileDiag()
{
   if(!InpWriteSymbolProfile) return;
   string fn="ICT_Assistant_Canonical_SymbolProfile.csv";
   int h=DiagOpen(fn);
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0)
      FileWrite(h,"Time","Symbol","Base","Class","ClassFa","Digits","Point","PipPrice",
                "PointScale","IsPipQuoted","RefSymbol","CalibSource","CalibRows",
                "Calibrated","GradeCalibFile","ChartTF","DigitsSet");
   FileWrite(h,
             TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
             _Symbol, SymbolBaseName(), SymbolClassCodeStr(), SymbolClassFa(),
             (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS),
             DoubleToString(_Point,8),
             DoubleToString(SymbolPipPrice(),8),
             DoubleToString(SymbolPointScale(),3),
             IsPipQuotedSymbol()?"true":"false",
             GradeRefSymbolBase(), g_calSource, g_calRows,
             GradeCalibrated()?"true":"false",
             GradeCalibFileName(0),
             ChartTfCode(),
             // شمارش‌گر «ضریب‌های غیر از ۱٫۰»: برای نماد پیپ‌دار ۲/۴ رقمی
             // باید ۱ و برای طلا/شاخص باید ۰ باشد. ابزار قفل‌کننده همین را
             // با ستون Digits مستقلاً بازحساب می‌کند.
             (SymbolPointScale()!=1.0)? 1 : 0);
   FileClose(h);
}
