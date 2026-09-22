//====================================================================
// فاز ۴۶ — درجهٔ سیگنال (A+/A/B+/B/C): «تیتر بالای چارت» که قبلاً وجود نداشت
//
// چرا این فایل ساخته شد
// --------------------
// نوار تک‌خطی گوشهٔ چارت (فاز ۳۵) فقط «ریسک برگشت» را نشان می‌داد: یک امتیاز
// ۰..۱۰۰ از وزن‌های دستی. با اندازه‌گیری روی دادهٔ واقعی خودِ کاربر معلوم شد
// آن امتیاز **هیچ چیزی را رتبه‌بندی نمی‌کند** (برد در برچسب LOW ۲۹٫۲٪ و در
// HIGH ۲۹٫۳٪ بود، یعنی تفاوت صفر). پس تیتری که باید بگوید «این سیگنال A+ است
// یا C» عملاً وجود نداشت.
//
// این ماژول آن را می‌سازد و — مهم‌تر — ضرایبش را از سر خود درنمی‌آورد:
//
//   tools/Fit-SignalGrade.ps1   (اجرای بازتولیدپذیر روی CSV خودِ اندیکاتور)
//     • هر کندل را با یک «مسابقه» به آینده می‌برد: +۲ برابر ATR در جهت بایاس
//       در برابر −۱ برابر ATR خلاف آن، داخل ۱۲ کندل → WIN / LOSS / OPEN
//     • برای هر مقدار ویژگی، «لیفت لگاریتمی-شانسی» روی خط پایه می‌سنجد
//     • درجه = مجموع لیفت‌ها؛ آستانه‌ها از چارک‌های همان توزیع سنجیده‌شده
//     • خروجی، برد واقعی هر درجه است: A+ ۵۲٫۲٪ · A ۴۱٫۲٪ · B+ ۳۵٫۵٪ ·
//       B ۳۱٫۲٪ · C ۲۵٫۸٪  (خط پایه ۲۹٫۴٪، ۵۵۱۹ نمونه، XAUUSD)
//
// محدودیت صادقانه (بخوان): این اعداد روی نمونهٔ ثبت‌شدهٔ همین نماد سنجیده
// شده‌اند (n=۹۲ برای A+). پس درجه یک «شمارش شاهدِ کالیبره‌شده» است، نه وعدهٔ
// درصد. هر عددی که کنار درجه می‌بینی، همان نرخ اندازه‌گیری‌شده است.
//====================================================================

// --- نقشِ نزدیک‌ترین سطح: کد خانواده (همان قاعده‌ای که ابزار فیت به کار می‌برد)
// قاعده روی پیشوندِ لاتینِ متن سطح کار می‌کند، پس مستقل از متن فارسی است.
string RRLevelFamilyCode(string lvl)
{
   string u=lvl;
   StringToUpper(u);
   // پیشوندها باید لفظ‌به‌لفظ با Get-Family در tools/Fit-SignalGrade.ps1 یکی
   // باشند، وگرنه درجهٔ اجراشده با درجهٔ فیت‌شده یکی نمی‌شود.
   if(StringFind(u,"LIQ")==0)              return "famLIQ";
   if(StringFind(u,"OB ")==0)               return "famOB";
   if(StringFind(u,"BREAKER")==0)           return "famBREAKER";
   if(StringFind(u,"MITIGATION")==0)        return "famMITIG";
   if(StringFind(u,"VOLUME IMBALANCE")==0)  return "famFVGVI";
   if(StringFind(u,"FVG")==0)               return "famFVG";
   if(StringFind(u,"S/D")==0)               return "famSD";
   if(StringFind(u,"TRENDLINE")==0)         return "famTL";
   return "famOTHER";
}

string RRLevelFamilyFa(string code)
{
   if(code=="famBREAKER") return "بریکر";
   if(code=="famFVGVI")   return "ناترازی حجمی";
   if(code=="famLIQ")     return "نقدینگی";
   if(code=="famFVG")     return "گپ ارزش منصفانه";
   if(code=="famMITIG")   return "بلاک تخفیف";
   if(code=="famOB")      return "اردربلاک";
   if(code=="famSD")      return "عرضه و تقاضا";
   if(code=="famTL")      return "خط روند";
   return "سایر سطوح";
}

// --- سطل‌ها: عیناً همان مرزهایی که ابزار فیت استفاده می‌کند
string GradeDistBucket(double d)
{
   if(d<0.25) return "distLt025";
   if(d<0.5)  return "dist025to05";
   if(d<1.0)  return "dist05to1";
   return "distGt1";
}
string GradeLegBucket(double l)
{
   if(l<50.0) return "legLt50";
   if(l<85.0) return "leg50to85";
   return "legGte85";
}
string GradeDolBucket(double d)
{
   if(d<=0.0) return "dolNone";
   if(d<=0.5) return "dolLe05";
   if(d<=1.0) return "dol05to1";
   return "dolGt1";
}
string GradeExhKey()
{
   // کلید فرسودگی عیناً همان چیزی است که ابزار فیت می‌سازد: پیشوند exh +
   // نام لاتین وضعیت. یکسان‌بودن کلیدها شرط اثبات هم‌ارزی در ابزار قفل‌کننده است.
   return "exh"+ExhaustionStateToStr(g_exhaustion.state);
}

// --- جدول لیفت‌ها (سنجیده‌شده؛ منبع: tools/Fit-SignalGrade.ps1)
// ورودی هر تابع، کلید سطل است؛ سطل‌هایی که نمونه‌شان زیر کف بود صفر می‌مانند
// و همین صفر بودن هم مستند است (نه حدس).
double GradeLiftF1(string f)
{
   if(f=="famBREAKER") return  0.489;
   if(f=="famFVGVI")   return  0.277;
   if(f=="famLIQ")     return  0.252;
   if(f=="famFVG")     return -0.101;
   if(f=="famMITIG")   return -0.154;
   if(f=="famOB")      return -0.653;
   return 0.0;                    // famSD / famTL / famOTHER: نمونه کمتر از کف
}
double GradeLiftF2(string b)
{
   if(b=="distLt025")   return -0.040;
   if(b=="dist025to05") return  0.294;
   if(b=="dist05to1")   return  0.490;
   if(b=="distGt1")     return  0.115;
   return 0.0;
}
double GradeLiftF3(string b)
{
   if(b=="legLt50")   return  0.003;
   if(b=="leg50to85") return  0.677;
   if(b=="legGte85")  return -0.028;
   return 0.0;
}
double GradeLiftF4(string b)
{
   if(b=="dolNone") return -0.223;
   if(b=="dolGt1")  return  0.003;
   return 0.0;                    // dolLe05 / dol05to1: نمونه کمتر از کف
}
double GradeLiftF5(bool aligned) { return aligned? 0.110 : -0.033; }
double GradeLiftF6(bool swept)   { return swept? 0.032 : -0.001; }
double GradeLiftF7(string e)
{
   if(e=="exhREVERSAL_CONFIRMED")         return  0.598;
   if(e=="exhRANGE_OR_TRANSITION")        return  0.112;
   if(e=="exhEXHAUSTION_WATCH")           return  0.046;
   if(e=="exhEXTENDING")                  return  0.025;
   if(e=="exhTRENDING")                   return -0.030;
   if(e=="exhMICRO_PULLBACK")             return -0.078;
   if(e=="exhMICRO_REVERSAL_CONFIRMED")   return -0.171;
   return 0.0;                    // exhNEUTRAL: نمونه کمتر از کف
}

// --- آستانه‌ها: چارک‌های همان توزیع سنجیده‌شده (بازتولید با همان ابزار)
string GradeFromScore(double s)
{
   if(s>=0.827) return "A+";
   if(s>=0.564) return "A";
   if(s>=0.297) return "B+";
   if(s>=0.106) return "B";
   return "C";
}
// نرخ بردِ همان درجه — عدد ثابت نیست: از همان سنجش می‌آید و در پنل با n
// نشان داده می‌شود تا کاربر بداند این یک وعده نیست، یک اندازه‌گیری است.
double GradeMeasuredWin(string g)
{
   if(g=="A+") return 52.2;
   if(g=="A")  return 41.2;
   if(g=="B+") return 35.5;
   if(g=="B")  return 31.2;
   if(g=="C")  return 25.8;
   return 29.4;
}
int GradeMeasuredN(string g)
{
   if(g=="A+") return   92;
   if(g=="A")  return  306;
   if(g=="B+") return  707;
   if(g=="B")  return 1115;
   if(g=="C")  return 3299;
   return 5519;
}
string GradeFa(string g)
{
   if(g=="—")  return "بدون جهت";
   if(g=="A+") return "بهترین هم‌جهتی با بایاس";
   if(g=="A")  return "هم‌جهتی قوی";
   if(g=="B+") return "هم‌جهتی متوسط رو به بالا";
   if(g=="B")  return "هم‌جهتی ضعیف";
   if(g=="C")  return "هم‌جهتی ضعیف یا مخالف شواهد";
   return "تعیین نشده";
}

// رنگ نوار: چون سرِ ردیف حالا درجه است، رنگ هم درجه را می‌گوید (کیفیت
// هم‌جهتی)، نه ریسک برگشت را. اگر درجه تعیین نشده باشد به رنگ خنثی برمی‌گردد.
color GradeStripColor()
{
   if(g_grade=="A+") return clrLime;
   if(g_grade=="A")  return clrGreenYellow;
   if(g_grade=="B+") return clrGold;
   if(g_grade=="B")  return clrDarkOrange;
   if(g_grade=="C")  return clrGray;
   return InpColorNeutral;
}

// --- محاسبه: برای هر کندل *بسته*، یک‌بار. هیچ‌جا از آینده خبری نیست.
// اگر بایاس وجود نداشته باشد، درجه معنی ندارد و «—» می‌ماند.
void UpdateSignalGrade()
{
   g_grade="—"; g_gradeScore=0.0; g_gradeWhy=""; g_gradeFam="";
   g_gradeWin=0.0; g_gradeN=0;
   if(!InpEnableSignalGrade) return;
   if(g_htfBias==DIR_NONE)
   {
      g_gradeWhy="بایاس جهت‌دار وجود ندارد، پس شواهد هم‌جهت معنی ندارد";
      return;
   }

   string fam=RRLevelFamilyCode(g_rrLevel);
   string b2=GradeDistBucket(g_rrLevelDist);
   string b3=GradeLegBucket(g_rrLegProg);
   string b4=GradeDolBucket(g_rrDolDist);
   string e7=GradeExhKey();

   double l1=GradeLiftF1(fam);
   double l2=GradeLiftF2(b2);
   double l3=GradeLiftF3(b3);
   double l4=GradeLiftF4(b4);
   double l5=GradeLiftF5(!g_mtfConflict);
   double l6=GradeLiftF6(g_barSweptTowardBias);
   double l7=GradeLiftF7(e7);

   g_gradeComputed++;
   g_gradeScore=l1+l2+l3+l4+l5+l6+l7;
   g_grade=GradeFromScore(g_gradeScore);
   g_gradeFam=fam;
   g_gradeWin=GradeMeasuredWin(g_grade);
   g_gradeN=GradeMeasuredN(g_grade);

   // دلیل: بزرگ‌ترین بالابرنده و بزرگ‌ترین کاهنده، به فارسی و با همان عدد.
   double best=l1; string bestFa=RRLevelFamilyFa(fam);
   if(l2>best){ best=l2; bestFa="فاصله تا سطح"; }
   if(l3>best){ best=l3; bestFa="جای قیمت در لگ"; }
   if(l4>best){ best=l4; bestFa="فاصله تا هدف نقدینگی"; }
   if(l5>best){ best=l5; bestFa="همسویی تایم‌فریم‌ها"; }
   if(l6>best){ best=l6; bestFa="جاروی نقدینگی هم‌جهت"; }
   if(l7>best){ best=l7; bestFa="وضعیت فرسودگی"; }

   double worst=l1; string worstFa=RRLevelFamilyFa(fam);
   if(l2<worst){ worst=l2; worstFa="فاصله تا سطح"; }
   if(l3<worst){ worst=l3; worstFa="جای قیمت در لگ"; }
   if(l4<worst){ worst=l4; worstFa="فاصله تا هدف نقدینگی"; }
   if(l5<worst){ worst=l5; worstFa="همسویی تایم‌فریم‌ها"; }
   if(l6<worst){ worst=l6; worstFa="جاروی نقدینگی هم‌جهت"; }
   if(l7<worst){ worst=l7; worstFa="وضعیت فرسودگی"; }

   g_gradeWhy=StringFormat("بالابرنده: %s (%.2f)  |  کاهنده: %s (%.2f)",
                           bestFa, best, worstFa, worst);
}
