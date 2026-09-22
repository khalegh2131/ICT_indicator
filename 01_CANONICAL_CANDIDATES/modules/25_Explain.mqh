//====================================================================
// EXPLAIN MODE (اندیکاتور + استاد)
// با بردن موس روی هر خط/ناحیه، یک پنل چندخطی نشان داده می‌شود:
//   چیست، چرا تشکیل شد، چه شرطی آن را معتبر می‌کند، چه چیزی آن را
//   فیک/بی‌اعتبار می‌کند، و چطور خودت مقدار را کنترل کنی.
// قاعدهٔ RTL: در هر خط، قطعه‌های لاتین به ابتدای خط منتقل می‌شوند تا
// کلمهٔ انگلیسی وسط جملهٔ فارسی نیفتد و متن به‌هم نریزد.
//====================================================================
string g_expTitle="";
string g_expLines[];
color  g_expLineColors[];
string g_expHovered="";
int    g_expPanelRows=0;
int    g_expAnchorX=0;
int    g_expAnchorY=0;

//--------------------------------------------------------------------
// فاز ۴۴ — عقد بسته‌شدهٔ مسیر کلیک: هر کلیک باید یا توضیح تخصصی همان آبجکت
// را نشان بدهد، یا یک پیام صادقانه بگوید چرا توضیح تخصصی نیست. حالت سوم
// («هیچ نمی‌نویسد») دیگر مجاز نیست، چون برای کاربر از یک خطای حساب هم
// گیج‌کننده‌تر است: نمی‌داند آبجکت چیست، نمی‌داند اشکال از اوست یا از کد.
// این وضعیت برای هر فراخوانی توضیح ثبت و در Journal شمارش می‌شود؛ پس
// «قطعی بودن» با عدد سنجیده می‌شود، نه با ادعا.
//--------------------------------------------------------------------
enum ENUM_CLICK_RESOLVE
{
   CLICK_RS_NONE = 0,   // هنوز توضیحی ساخته نشده
   CLICK_RS_OK,         // توضیح تخصصی همین خانواده ساخته شد
   CLICK_RS_FALLBACK    // توضیح تخصصی نبود؛ پیام جایگزین ساخته شد
};
ENUM_CLICK_RESOLVE g_clickResolve = CLICK_RS_NONE;
string g_clickLastHit   = "";   // نام آبجکتی که آخرین بار توضیح خواست
string g_clickLastTitle = "";   // عنوانی که پنل نشان داد (شاهد همانتغییر)
long   g_clickCount     = 0;
long   g_clickOk        = 0;
long   g_clickFallback  = 0;
// فاز ۴۴ — تفکیک دو نوع پیام جایگزین: «خانوادهٔ ناشناخته» یک نقص کد است،
// ولی «مرجع از رجیستری بیرون افتاده» یک حالت معتبر است که باید توضیح داده
// شود. بدون این تفکیک، آزمون نمی‌تواند بین نقص کد و حالت طراحی‌شده فرق بگذارد.
string g_clickReason    = "";   // RESOLVED | REGISTRY_MISS | NO_HANDLER
// فاز ۴۴ — شمارندهٔ آزمون خودکار مسیر کلیک (پایین‌تر در 26_PersianRender)
int    g_clickTestObjects  = 0;
int    g_clickTestResolved = 0;
int    g_clickTestEmpty    = 0;
int    g_clickTestOffscreen= 0;
int    g_clickTestSelfHit  = 0;
int    g_clickTestWeakHit  = 0;

// قاعدهٔ RTL این فایل (سرصفحه) در RtlSafe() پایین‌تر پیاده شده است — آن تابع
// با توکن‌های واژه‌ای کار می‌کند، نه با تک‌تک کاراکترها.

void ExpClear()
{
   ArrayResize(g_expLines,0);
   ArrayResize(g_expLineColors,0);
   g_expTitle="";
}

bool IsPersianChar(ushort c)
{
   if(c>=0x0600 && c<=0x06FF) return true;   // Arabic block (شامل حروف فارسی)
   if(c>=0xFB50 && c<=0xFDFF) return true;   // Presentation Forms-A
   if(c>=0xFE70 && c<=0xFEFF) return true;   // Presentation Forms-B
   return false;
}

// ---------------------------------------------------------------------------
// قاعدهٔ RTL — نسخهٔ درست (فاز ۴۱)
// ---------------------------------------------------------------------------
// چرا واژهٔ لاتین وسط جملهٔ فارسی متن را ناخوانا می‌کند:
//   ردیف‌های پنل با OBJ_EDIT رسم می‌شوند و OBJ_EDIT یک کنترل بومی است که
//   خودش bidi را انجام می‌دهد. جهت پایهٔ خط با قاعدهٔ P2/P3 انتخاب می‌شود؛
//   یعنی همان اولین کاراکترِ قوی. یک خط فارسی که وسطش واژهٔ لاتین دارد، به
//   دو قطعهٔ مستقل راست‌به‌چپ شکسته می‌شود. ترتیب **واژه‌ها در هر قطعه**
//   درست می‌ماند، ولی ترتیب دو قطعه نسبت به هم در برخی جهت‌های پایه
//   جابه‌جا می‌شود و خواننده جمله را وارونه می‌بیند.
//   ارقام این بلا را سر نمی‌آورند: عدد اروپایی داخل متن راست‌به‌چپ، با
//   قاعدهٔ W از UBA داخل همان قطعه می‌ماند (نه یک قطعهٔ L جدید).
// پس فقط «توکن‌هایی که حرف لاتین دارند» جابه‌جا می‌شوند، نه ارقام.
bool TokenHasLatinLetter(string w)
{
   for(int i=0;i<StringLen(w);i++)
   {
      ushort c=StringGetCharacter(w,i);
      if((c>='A'&&c<='Z')||(c>='a'&&c<='z')) return true;
   }
   return false;
}

bool TokenHasPersianChar(string w)
{
   for(int i=0;i<StringLen(w);i++)
      if(IsPersianChar(StringGetCharacter(w,i))) return true;
   return false;
}

// هر واژهٔ لاتینی که *بعد* از یک واژهٔ فارسی بیاید، به ابتدای خط منتقل
// می‌شود (ترتیب خودشان حفظ می‌شود) و با « | » از جملهٔ فارسی جدا می‌شود؛
// پس پیام فارسی یک قطعهٔ یکپارچه می‌ماند و جابه‌جا نمی‌شود. خطی که لاتینش
// از قبل اول است، و خط تمام‌لاتین، دست‌نخورده می‌ماند.
// این تابع idempotent است: اجرای دوباره روی خروجی خودش هیچ تغییری نمی‌دهد.
string RtlSafe(string s)
{
   if(StringLen(s)==0) return s;
   if(!TokenHasPersianChar(s)) return s;   // خط تمام‌لاتین (یا فقط عدد/علامت)

   string words[];
   int wc=StringSplit(s,' ',words);
   if(wc<=0) return s;

   bool seenPersian=false, needsMove=false;
   for(int i=0;i<wc;i++)
   {
      if(StringLen(words[i])==0) continue;
      if(TokenHasLatinLetter(words[i]))
      {
         if(seenPersian){ needsMove=true; break; }
      }
      else if(TokenHasPersianChar(words[i])) seenPersian=true;
   }
   if(!needsMove) return s;

   string latinPart="", faPart="";
   for(int i=0;i<wc;i++)
   {
      if(StringLen(words[i])==0) continue;
      if(TokenHasLatinLetter(words[i]))
      {
         if(StringLen(latinPart)>0) latinPart+=" ";
         latinPart+=words[i];
      }
      else
      {
         if(StringLen(faPart)>0) faPart+=" ";
         faPart+=words[i];
      }
   }
   if(StringLen(faPart)==0) return latinPart;
   return latinPart+" | "+faPart;
}

