//====================================================================
// فاز ۴۷ — سناریوی در انتظار (PENDING): «چه چیزی در انتظار بسته شدن کندل است»
//
// چرا این فایل ساخته شد
// --------------------
// دروازهٔ برگشت (فاز ۱۱) صادقانه ولی **پسرو** بود: تا کندل بستهٔ HTF فراتر از
// سطح محافظت‌شده نایستد، هیچ نمی‌گفت. کاربر اما می‌پرسد «الان چه چیزی قرار است
// اتفاق بیفتد و چقدر محتمل است؟». این ماژول همان پرسش را جواب می‌دهد.
//
// قاعدهٔ سخت — این بخش هرگز ریپنت نمی‌کند
// --------------------------------------
// ۱) *تنها* ورودی این ماژول وضعیتِ آخرین کندل **بسته** است: سطح محافظت‌شدهٔ
//    خارجی، قیمت بستهٔ آخرین کندل بستهٔ HTF، بایاس مالک، و ATR کندل بسته.
//    هیچ‌جا Bid/Ask/close کندل جاری خوانده نمی‌شود؛ پس متنِ این ردیف تا زمانی که
//    کندل بعدی بسته نشود **حرف‌به‌حرف ثابت** می‌ماند و هیچ تاریخی را بازنویسی
//    نمی‌کند. (ابزار Validate-Phase47 همین را روی متن کد قفل می‌کند.)
// ۲) این ماژول **صفر نوشتن** دارد: نه رجیستری، نه رویداد، نه بایاس، نه CSV.
//    خروجی‌اش فقط چند متغیر نمایشی (g_pend*) و یک ردیف متنی است. پس هیچ موتور
//    تشخیصی نمی‌تواند از آن اثر بگیرد؛ حتی اگر خاموشش کنی، تحلیل تغییر نمی‌کند.
// ۳) ردیف روی گوشهٔ چارت لنگر شده است، نه روی زمان/قیمت؛ پس با اسکرول یا
//    تغییر مقیاس جابه‌جا نمی‌شود.
//
// عدد «احتمال» از کجا می‌آید (بدون حدس)
// -----------------------------------
//   tools/Fit-PendingScenario.ps1   (بازتولیدپذیر روی دفتر شاهد خودِ اندیکاتور)
//     • ردیف‌های دفتر برگشت را به «اپیزود» می‌شکند: تا وقتی شناسهٔ سویینگ
//       محافظت‌شده عوض نشده، شرطِ انتظار هم عوض نشده است.
//     • در هر اپیزود، وضعیتِ هر کندل بستهٔ HTF نگه داشته می‌شود؛ ARMED یعنی
//       «منتظر» و CONFIRMED یعنی «کندل بسته از سطح گذشت».
//     • فاصلهٔ کندل بسته تا سطح را با ATR همان کندل (از دفتر ریسک برگشت) تقسیم
//       می‌کند و نرخِ «تأیید در کندل بستهٔ بعدی» را در هر سبد می‌شمارد.
//
//   اندازه‌گیری روی نمونهٔ ثبت‌شدهٔ XAUUSD.x (HTF=H4، چارت M15، ۳۰۰ اپیزود،
//   ۲۷۶۷ گذار «منتظر»):
//     | فاصله تا سطح      | نمونه | تأیید در کندل بعد | نرخ     |
//     | کمتر از ۰٫۲ ATR   |   ۲۳  |         ۹         | ۳۹٫۱٪  |
//     | ۰٫۲ تا ۰٫۵ ATR    |   ۳۹  |         ۰         |  ۰٫۰٪  |
//     | ۰٫۵ تا ۱٫۰ ATR    |   ۸۱  |         ۰         |  ۰٫۰٪  |
//     | ۱٫۰ تا ۲٫۰ ATR    |  ۱۶۸  |         ۳         |  ۱٫۸٪  |
//     | بیشتر از ۲٫۰ ATR  | ۲۴۵۶  |         ۰         |  ۰٫۰٪  |
//     خط پایهٔ کل: ۰٫۴٪
//
//   خواندنِ درستِ این عدد: «تأیید در همان کندل بستهٔ بعدی» نادر است مگر قیمت از
//   قبل تقریباً روی سطح باشد (کمتر از ۰٫۲ برابر دامنه). یعنی این ردیف می‌گوید
//   «بازار باید اول راه بیفتد»؛ به همین دلیل فاصله و مقصد نقدینگی هم کنارش
//   می‌آید. سبدِ کمتر از ۰٫۲ ATR فقط ۲۳ نمونه دارد؛ این عدد یک اندازه‌گیری است
//   روی یک نماد و یک پنجرهٔ آرشیو، نه وعدهٔ درصد — و تعداد نمونه همیشه کنارش
//   نوشته می‌شود.
//====================================================================

void PendClear()
{
   g_pendValid=false;
   g_pendState="OFF";
   g_pendTriggerFa="";
   g_pendGuardDistATR=0.0;
   g_pendBucket="";
   g_pendRate=0.0;
   g_pendRateN=0;
   g_pendMagnetName="";
   g_pendMagnetTypeFa="";
   g_pendMagnetPrice=0.0;
   g_pendMagnetDistATR=0.0;
   g_pendBaselineRate=0.0;
   g_pendLineText="";
}

// سبد فاصله — مرزها باید لفظ‌به‌لفظ با Get-PendBucket در ابزار فیت یکی باشند،
// وگرنه نرخِ اجراشده با نرخِ سنجیده‌شده یکی نمی‌شود (همان قاعدهٔ فاز ۴۶).
string PendBucketCode(double d)
{
   if(d<0.20) return "pendLt020";
   if(d<0.50) return "pend020to050";
   if(d<1.00) return "pend050to100";
   if(d<2.00) return "pend100to200";
   return "pendGt200";
}

// --- جدول سنجیده‌شده (منبع: tools/Fit-PendingScenario.ps1) ---
double PendMeasuredRate(string b)
{
   if(b=="pendLt020")   return 39.1;
   if(b=="pend020to050") return  0.0;
   if(b=="pend050to100") return  0.0;
   if(b=="pend100to200") return  1.8;
   if(b=="pendGt200")    return  0.0;
   return 0.0;
}
int PendMeasuredN(string b)
{
   if(b=="pendLt020")   return   23;
   if(b=="pend020to050") return   39;
   if(b=="pend050to100") return   81;
   if(b=="pend100to200") return  168;
   if(b=="pendGt200")    return 2456;
   return 0;
}

// نام فارسی نوع نقدینگیِ مقصد. چرا لازم است: برچسب لاتین (PDH، EQH، ASIA LOW…)
// وسط جملهٔ فارسی، خط را به دو قطعه می‌شکند و خواندنش به‌هم می‌ریزد (قاعدهٔ
// RTL فاز ۴۲). پس در ردیف، فقط نوع فارسی می‌آید و برچسب لاتین به پنل می‌رود.
string PendLiqTypeFa(ENUM_LIQ_TYPE t)
{
   switch(t)
   {
      case LIQ_PDH:            return "سقف روز قبل";
      case LIQ_PDL:            return "کف روز قبل";
      case LIQ_PWH:            return "سقف هفتهٔ قبل";
      case LIQ_PWL:            return "کف هفتهٔ قبل";
      case LIQ_EQH:            return "سقف‌های برابر";
      case LIQ_EQL:            return "کف‌های برابر";
      case LIQ_SWING_H:        return "سقف سوئینگ";
      case LIQ_SWING_L:        return "کف سوئینگ";
      case LIQ_SESSION_H:      return "سقف سشن";
      case LIQ_SESSION_L:      return "کف سشن";
      case LIQ_RANGE_H:        return "سقف رنج";
      case LIQ_RANGE_L:        return "کف رنج";
      case LIQ_IPDA20_H:       return "سقف ۲۰ روزه";
      case LIQ_IPDA20_L:       return "کف ۲۰ روزه";
      case LIQ_IPDA40_H:       return "سقف ۴۰ روزه";
      case LIQ_IPDA40_L:       return "کف ۴۰ روزه";
      case LIQ_IPDA60_H:       return "سقف ۶۰ روزه";
      case LIQ_IPDA60_L:       return "کف ۶۰ روزه";
      case LIQ_TRENDLINE_H:    return "خط روند بالایی";
      case LIQ_TRENDLINE_L:    return "خط روند پایینی";
   }
   return "سطح نقدینگی";
}

string PendStateFa(string s)
{
   if(s=="NO_BIAS")       return "بایاس جهت‌دار وجود ندارد، پس شرط انتظار معنا ندارد";
   if(s=="NO_GUARD")      return "سطح محافظت‌شدهٔ خارجی در رجیستری تایم‌فریم بالاتر پیدا نشد";
   if(s=="NO_ATR")        return "میانگین دامنهٔ کندل بسته صفر است، پس فاصله قابل سنجش نیست";
   if(s=="CONFIRMED_NOW") return "همین کندل بسته برگشت را تأیید کرد؛ چیزی در انتظار نیست";
   if(s=="WAITING")       return "منتظر بستهٔ کندل تایم‌فریم بالاتر هستیم";
   if(s=="OFF")           return "سناریوی در انتظار خاموش است";
   return "وضعیت نامشخص";
}

//--------------------------------------------------------------------
// محاسبه — فقط از کندل بسته، بدون هیچ نوشتنی.
// atrValue همان ATR کندل بسته است (همان‌که به UpdateReverseRisk می‌رود).
//--------------------------------------------------------------------
void UpdatePendingScenario(double atrValue)
{
   PendClear();
   if(!InpEnablePendingScenario) return;

   // ۱) بایاس جهت‌دار: بدون آن، «برگشت» و «مقصد نقدینگی» معنا ندارد.
   if(g_htfBias==DIR_NONE){ g_pendState="NO_BIAS"; return; }

   // ۲) سطح محافظت‌شدهٔ خارجی و قیمت بستهٔ آخرین کندل بستهٔ HTF.
   if(!g_reversal.snapGuardOk || g_reversal.snapBarClose<=0.0 || g_reversal.levelPrice<=0.0)
   { g_pendState="NO_GUARD"; return; }
   if(atrValue<=0.0){ g_pendState="NO_ATR"; return; }

   // ۳) مقصد نقدینگی: نزدیک‌ترین سطح **جارونشده** در جهت بایاس. برای بایاس
   //    نزولی مقصد سمت فروش است (کف‌ها) و برای صعودی سمت خرید (سقف‌ها) —
   //    همان معنای «میرود نقدینگی جمع کند».
   double bestD=1e18;
   for(int i=0;i<ArraySize(g_liquidity);i++)
   {
      if(g_liquidity[i].state!=LSTATE_FRESH) continue;
      bool highSide=IsHighSideLiquidity(g_liquidity[i].type);
      if(g_htfBias==DIR_BEAR && highSide)  continue;
      if(g_htfBias==DIR_BULL && !highSide) continue;
      double d=MathAbs(g_reversal.snapBarClose-g_liquidity[i].price)/atrValue;
      if(d>=bestD) continue;
      bestD=d;
      g_pendMagnetName=LiqTypeLabel(g_liquidity[i].type);
      g_pendMagnetTypeFa=PendLiqTypeFa(g_liquidity[i].type);
      g_pendMagnetPrice=g_liquidity[i].price;
      g_pendMagnetDistATR=d;
   }

   // ۴) اگر همین کندل بسته برگشت را تأیید کرده باشد، «انتظار» بی‌معناست.
   if(g_reversal.confirmed && g_reversal.confirmedTime==g_reversal.snapBarTime)
   {
      g_pendState="CONFIRMED_NOW";
      g_pendValid=true;
      g_pendComputed++;
      return;
   }

   // ۵) شرط انتظار: ماشه = بستهٔ HTF در جهت مخالف بایاس.
   //    (بایاس صعودی با بستهٔ **زیر** سطح محافظت‌شده باطل می‌شود.)
   bool breakDown=(g_htfBias==DIR_BULL);
   g_pendGuardDistATR=MathAbs(g_reversal.snapBarClose-g_reversal.levelPrice)/atrValue;
   g_pendBucket=PendBucketCode(g_pendGuardDistATR);
   g_pendRate=PendMeasuredRate(g_pendBucket);
   g_pendRateN=PendMeasuredN(g_pendBucket);
   g_pendBaselineRate=0.4;      // خط پایهٔ کل همان سنجش (۰٫۴٪ روی ۲۷۶۷ گذار)
   g_pendTriggerFa=StringFormat("بستهٔ %s %s", breakDown? "زیر":"بالای",
                                DoubleToString(g_reversal.levelPrice,_Digits));
   g_pendState="WAITING";
   g_pendValid=true;
   g_pendComputed++;
}

//--------------------------------------------------------------------
// فاز ۴۸ — قطعهٔ «مسیر» برای نوار یکپارچهٔ گوشهٔ چارت.
//
// چرا ردیف جداگانه حذف شد: دو ردیف تک‌خطی روی هم («درجه» و «در انتظار») عملاً
// یک واقعیت را دو بار می‌گفتند و کاربر مجبور بود هر دو را بخواند تا مسیر را
// بفهمد. حالا یک ردیف است و این تابع فقط قطعهٔ «مقصد و شرط برگشت» را می‌دهد؛
// ساخت خود ردیف در RenderRiskStrip است.
//
// قرارداد: برگرداندن رشتهٔ خالی یعنی «چیزی برای گفتن نیست» — نوار در آن حالت
// خودش جانشین می‌گذارد. هیچ محاسبهٔ تازه‌ای اینجا نیست؛ فقط گره‌های g_pend*
// به فارسی ریخته می‌شوند تا یک عدد دو روایت نداشته باشد.
// قاعدهٔ RTL فاز ۴۲: هیچ واژهٔ لاتین وسط جملهٔ فارسی نمی‌آید؛ فقط عدد و جهت
// و نام کوتاه تایم‌فریم در قطعه‌های جداگانه.
//--------------------------------------------------------------------
string PendingFragmentFa()
{
   if(g_pendState=="OFF" || g_pendState=="") return "";
   if(g_pendState=="NO_BIAS" || g_pendState=="NO_GUARD" || g_pendState=="NO_ATR")
      return "  |  مسیر: "+PendStateFa(g_pendState);

   string magnet="";
   if(g_pendMagnetPrice>0.0)
      magnet=StringFormat("  |  مقصد: %s %.2f", g_pendMagnetTypeFa, g_pendMagnetPrice);

   if(g_pendState=="CONFIRMED_NOW")
      return magnet+"  |  برگشت همین کندل بسته تأیید شد";

   return StringFormat("%s  |  برگشت: %s — نرخ %.1f%% از %d نمونه",
                       magnet, g_pendTriggerFa, g_pendRate, g_pendRateN);
}

// فاز ۴۸: رسم ردیف جداگانه حذف شد. اشیای ICTv13_PEND_BG / ICTv13_PEND_TXT
// ممکن است از بیلد قبلی روی چارت باقی مانده باشند؛ پاک‌سازی یک‌باره اینجا
// انجام می‌شود تا با یک بار attach چارت تمیز شود (بدون نیاز به Remove دستی).
void CleanupLegacyPendingRow()
{
   if(g_pendRowCleaned) return;
   g_pendRowCleaned=true;
   if(ObjectFind(0,"ICTv13_PEND_BG")>=0)  ObjectDelete(0,"ICTv13_PEND_BG");
   if(ObjectFind(0,"ICTv13_PEND_TXT")>=0) ObjectDelete(0,"ICTv13_PEND_TXT");
}

//--------------------------------------------------------------------
// توضیح فارسی همین ردیف (کلیک/هنگ روی آن). قاعده: ردیف‌های لاتین یا تمام‌لاتین
// می‌مانند و توضیح فارسی در ردیف بعدی می‌آید.
//--------------------------------------------------------------------
// keepTitle=true یعنی این بخش در پنل یکپارچهٔ «مسیر» به‌عنوان ادامه می‌آید و
// نباید عنوان پنل را بازنویسی کند (فاز ۴۸: یک کلیک، یک پنل، یک روایت).
void ExplainPendingScenario(bool keepTitle=false)
{
   if(!keepTitle) g_expTitle="PENDING — آنچه در انتظار بسته شدن کندل است";
   else ExpAddWrapped("بخش دوم: شرط برگشت و مقصد نقدینگی — همان دو عددی که در نوار یکپارچه دیده می‌شوند", clrAqua);
   ExpAddWrapped("چیست: این ردیف آینده را پیش‌بینی نمی‌کند؛ یک شرط را می‌گوید: اگر کندل بستهٔ تایم‌فریم بالاتر از یک سطح مشخص بگذرد، برگشت تأیید می‌شود و اگر نگذرد، هیچ چیز تأیید نمی‌شود", clrWhite);
   ExpAdd(StringFormat("state: %s | bias: %s | htf: %s",
           g_pendState, DirToStr(g_htfBias), TfFa(InpHTF)), clrAqua);
   ExpAddWrapped(PendStateFa(g_pendState), clrSilver);
   if(g_pendState=="WAITING")
   {
      ExpAdd("trigger: "+g_pendTriggerFa, clrAqua);
      ExpAdd(StringFormat("guard: %s %s | last closed htf close: %s | distance: %.2f ATR",
              g_reversal.levelIsHigh? "HIGH":"LOW", DoubleToString(g_reversal.levelPrice,_Digits),
              DoubleToString(g_reversal.snapBarClose,_Digits), g_pendGuardDistATR), clrAqua);
      ExpAdd(StringFormat("bucket: %s | measured next-close confirmation: %.1f%% | n: %d | baseline: %.1f%%",
              g_pendBucket, g_pendRate, g_pendRateN, g_pendBaselineRate), clrAqua);
      ExpAddWrapped("معنی این عدد: در نمونهٔ ثبت‌شده، وقتی فاصلهٔ کندل بسته تا سطح در همین سبد بود، چند بار کندل بستهٔ بعدی واقعاً از سطح گذشت. این «درصد موفقیت معامله» نیست، نرخ همان رویداد است", clrSilver);
      ExpAddWrapped("نکتهٔ مهم سنجش: تا وقتی قیمت از قبل تقریباً روی سطح نباشد (کمتر از ۰٫۲ برابر دامنه)، تأیید در کندل بعدی عملاً رخ نمی‌دهد؛ یعنی انتظارِ «همین کندل» واقع‌بینانه نیست و بازار اول باید حرکت کند", clrOrange);
      ExpAddWrapped("شمارش سبدِ نزدیک فقط ۲۳ نمونه دارد و روی یک نماد و یک پنجرهٔ آرشیو سنجیده شده؛ پس این یک اندازه‌گیری است، نه وعدهٔ درصد", clrOrange);
   }
   if(g_pendMagnetPrice>0.0)
   {
      ExpAdd(StringFormat("magnet: %s %s | distance: %.2f ATR",
              g_pendMagnetName, DoubleToString(g_pendMagnetPrice,_Digits), g_pendMagnetDistATR), clrAqua);
      ExpAddWrapped("چرا این سطح: در جهت بایاس، نزدیک‌ترین سطح نقدینگی **جارونشده** انتخاب شده است؛ چون هدف حرکت، برداشتن همان نقدینگی است و برگشت معمولاً بعد از رسیدن به آن سنجیده می‌شود", clrLime);
   }
   else
      ExpAddWrapped("در جهت بایاس، سطح نقدینگی جارونشده‌ای در رجیستری نیست؛ پس مقصدی هم اعلام نمی‌شود", clrSilver);
   ExpAddWrapped("چطور خودت بسنجی: با ابزار سنجش همین مخزن، نرخ و تعداد نمونه را از دفتر شاهد بازتولید کن؛ اگر با عدد روی ردیف نخواند، حساب غلط است", clrAqua);
   ExpAdd("provenance: tools/Fit-PendingScenario.ps1", clrSilver);
   ExpAddWrapped("چرا ریپنت نمی‌کند: همهٔ ورودی‌های این ردیف از آخرین کندل **بسته** می‌آید (سطح محافظت‌شده، قیمت بستهٔ آن، بایاس مالک، میانگین دامنهٔ همان کندل). تا کندل بعدی بسته نشود، این متن حرف‌به‌حرف ثابت می‌ماند و هیچ تاریخی بازنویسی نمی‌شود", clrLime);
   ExpAddWrapped("چه چیزی آن را بی‌اعتبار می‌کند: بسته شدن کندل بعدی (که یا تأیید می‌کند یا فاصله را عوض می‌کند)، یا عوض شدن سطح محافظت‌شده و بایاس مالک", clrOrange);
   ExpAdd("object name: ICTv13_RSTRIP_TXT (ردیف یکپارچهٔ مسیر — خواندنی، غیرقابل‌جابه‌جایی)", clrSilver);
}
