//====================================================================
// FVG ENGINE — رفع ایراد ۷: FVG فقط وقتی "Causal" علامت می‌خورد که
// displacementId معتبر و غیر energyOnly داشته باشد.
//====================================================================
// فاز ۱۲ (#۳۰): گپ Implied جداگانه ثبت می‌شود چون سطح متفاوتی است.
// گپ استاندارد از high/low ساخته می‌شود و گپ Implied از **بدنهٔ** کندل اول و
// سوم (close کندل ۱ ↔ open کندل ۳). هر دو ناحیهٔ مستقل با شناسهٔ مستقل‌اند.
void AppendFVG(long id, datetime t, ENUM_DIRECTION dir, double top, double bottom,
               long midDispId, ENUM_FVG_KIND kind, ENUM_TIMEFRAMES tf, bool birthTouch)
{
   if(top<=bottom) return;
   for(int i=ArraySize(g_fvgs)-1;i>=0;i--)
      if(g_fvgs[i].id==id) return;          // همین ناحیه قبلأً ثبت شده
   FVGObj f;
   f.id=id; f.time=t; f.direction=dir; f.top=top; f.bottom=bottom;
   f.displacementId=midDispId;
   f.causal=DisplacementChained(midDispId, dir);
   f.mitigated=false; f.inverted=false; f.invalidated=false; f.invertedTime=0;
   f.ceTouched=false;
   f.createdTime=t; f.touchTime=0; f.birthBarTouch=birthTouch;
   f.kind=kind; f.tf=tf; f.ce=(top+bottom)/2.0;
   int n=ArraySize(g_fvgs); ArrayResize(g_fvgs,n+1); g_fvgs[n]=f;
   if(f.causal && !g_rebuildMode) DrawFVG(f);
}

void DetectFVG(const double &open[], const double &high[], const double &low[], const double &close[],
               int shift, long midBarDisplacementId)
{
   // الگوی سه‌کندلی استاندارد ICT: کندل سوم = shift، کندل میانی = shift+1،
   // کندل اول = shift+2. گپ بین high[shift+2] و low[shift] است و کندل
   // Displacement همان کندل **میانی** است، نه کندل تأییدکننده (#۲۶).
   if(shift+2 >= ArraySize(high) || shift+2 >= ArraySize(close) || shift+2 >= ArraySize(open)) return;

   // فاز ۲۸ — فیلتر اهمیت (منبع: LuxAlgo Library — FVG، مرحلهٔ ۴ تشخیص):
   // «گپ‌های سه‌کندلی خام بی‌وقفه چاپ می‌شوند، پس بیشتر ابزارها حداقل اندازه
   // (بر مبنای ATR یا درصد) یا هم‌راستایی با ساختار می‌خواهند.» بدون این گارد،
   // گپ‌های یک‌تیکی فقط نویز چارت بودند و مسئول بخشی از «FVG فیک» بودند.
   double minGap=(InpMinFVG_ATR>0.0 && g_analysisATR>0.0)? InpMinFVG_ATR*g_analysisATR : 0.0;

   // Bullish FVG
   if(low[shift] > high[shift+2] && (low[shift]-high[shift+2])>=minGap)
   {
      FVGObj f;
      f.time=BarTime(shift);
      f.direction=DIR_BULL;
      f.id=StableZoneId(f.time,f.direction,1);
      f.top=low[shift]; f.bottom=high[shift+2];
      f.displacementId = midBarDisplacementId;   // کندل میانی الگو
      // Causal فقط با Displacement زنجیرشده به Structure Event (#۲۷).
      f.causal = DisplacementChained(midBarDisplacementId, DIR_BULL);
      f.mitigated=false; f.inverted=false; f.invalidated=false; f.invertedTime=0;
      f.ceTouched=false;
      f.createdTime=f.time;
      f.touchTime=0;
      // تشخیصی: مرز گپ همیشه با همان کندل سوم لمس می‌شود، پس این مقدار باید true باشد.
      // همین موضوع ایراد #۲۵ بود؛ ثبتش برای اثبات کارکرد گاردِ lifecycle است.
      f.birthBarTouch=(low[shift]<=f.top && high[shift]>=f.bottom);
      f.kind=FVGK_STANDARD; f.tf=PERIOD_CURRENT; f.ce=(f.top+f.bottom)/2.0;   // فاز ۱۲
      int n=ArraySize(g_fvgs); ArrayResize(g_fvgs,n+1); g_fvgs[n]=f;
      if(f.causal && !g_rebuildMode) DrawFVG(f);
   }
   // Bearish FVG
   if(high[shift] < low[shift+2] && (low[shift+2]-high[shift])>=minGap)
   {
      FVGObj f;
      f.time=BarTime(shift);
      f.direction=DIR_BEAR;
      f.id=StableZoneId(f.time,f.direction,1);
      f.top=low[shift+2]; f.bottom=high[shift];
      f.displacementId = midBarDisplacementId;   // کندل میانی الگو
      f.causal = DisplacementChained(midBarDisplacementId, DIR_BEAR);
      f.mitigated=false; f.inverted=false; f.invalidated=false; f.invertedTime=0;
      f.ceTouched=false;
      f.createdTime=f.time;
      f.touchTime=0;
      // تشخیصی: مرز گپ همیشه با همان کندل سوم لمس می‌شود، پس این مقدار باید true باشد.
      // همین موضوع ایراد #۲۵ بود؛ ثبتش برای اثبات کارکرد گاردِ lifecycle است.
      f.birthBarTouch=(low[shift]<=f.top && high[shift]>=f.bottom);
      f.kind=FVGK_STANDARD; f.tf=PERIOD_CURRENT; f.ce=(f.top+f.bottom)/2.0;   // فاز ۱۲
      int n=ArraySize(g_fvgs); ArrayResize(g_fvgs,n+1); g_fvgs[n]=f;
      if(f.causal && !g_rebuildMode) DrawFVG(f);
   }

   // --- فاز ۲۸: Implied FVG با فرمول **واقعی** ICT 2023 ---
   // منبع: LuxAlgo Library — Implied FVG (فرمول استاندارد):
   //   UWM(x) = ( H(x) + max(O(x),C(x)) ) / 2      میانهٔ فتیلهٔ بالا
   //   LWM(x) = ( min(O(x),C(x)) + L(x) ) / 2      میانهٔ فتیلهٔ پایین
   //   صعودی در کندل t:  LWM(t) > UWM(t-2)  و  L(t) <= H(t-2)
   //        ناحیه: bottom = UWM(t-2) , top = LWM(t)
   //   نزولی در کندل t:  UWM(t) < LWM(t-2)  و  H(t) >= L(t-2)
   //        ناحیه: top = LWM(t-2) , bottom = UWM(t)
   // نگاشت روی ایندکس ما: t = shift (کندل سوم)، t-2 = shift+2 (کندل اول).
   //
   // ایراد واقعی که این جایگزین می‌بندد: نسخهٔ قبلی close کندل ۱ و open کندل ۳
   // (مرزهای **بدنه**) را می‌گرفت. آن فرمول Implied FVG نیست؛ اسم درستش
   // **Volume Imbalance** است. حالا هر دو با فرمول درست و برچسب درست ثبت می‌شوند.
   if(InpEnablePhase12 && InpDetectImpliedFVG)
   {
      double o1=open[shift+2],  c1=close[shift+2], h1=high[shift+2], l1=low[shift+2];
      double o3=open[shift],    c3=close[shift],   h3=high[shift],   l3=low[shift];
      double uwm1=(h1+MathMax(o1,c1))/2.0;   // میانهٔ فتیلهٔ بالای کندل اول
      double lwm1=(MathMin(o1,c1)+l1)/2.0;   // میانهٔ فتیلهٔ پایین کندل اول
      double uwm3=(h3+MathMax(o3,c3))/2.0;   // میانهٔ فتیلهٔ بالای کندل سوم
      double lwm3=(MathMin(o3,c3)+l3)/2.0;   // میانهٔ فتیلهٔ پایین کندل سوم

      // Implied صعودی: دو فتیلهٔ روبه‌روی هم، با هم‌پوشانی فتیلهٔ کندل اول و سوم.
      if(lwm3>uwm1 && l3<=h1 && (lwm3-uwm1)>=minGap)
         AppendFVG(StableZoneId(BarTime(shift),DIR_BULL,3),
                   BarTime(shift), DIR_BULL, lwm3, uwm1,
                   midBarDisplacementId, FVGK_IMPLIED, PERIOD_CURRENT,
                   (l3<=lwm3 && h3>=uwm1));
      // Implied نزولی
      if(uwm3<lwm1 && h3>=l1 && (lwm1-uwm3)>=minGap)
         AppendFVG(StableZoneId(BarTime(shift),DIR_BEAR,3),
                   BarTime(shift), DIR_BEAR, lwm1, uwm3,
                   midBarDisplacementId, FVGK_IMPLIED, PERIOD_CURRENT,
                   (l3<=lwm1 && h3>=uwm3));

      // --- Volume Imbalance (منبع: LuxAlgo Library — همان فرمولی که قبلاً
      // اشتباه «Implied» نامیده می‌شد): گپ بین **بدنهٔ** کندل اول و سوم
      // در حالی که فتیله‌ها هنوز هم‌پوشانی دارند. مفهوم مستقل و معتبر SMC است،
      // پس حذف نشد؛ برچسب درست گرفت و discriminator جدا (۵) تا با Implied قاطی نشود.
      if(InpDetectVolumeImbalance)
      {
         if(c3>c1 && (c3-c1)>=minGap)
            AppendFVG(StableZoneId(BarTime(shift),DIR_BULL,5),
                      BarTime(shift), DIR_BULL, c3, c1,
                      midBarDisplacementId, FVGK_VOL_IMBALANCE, PERIOD_CURRENT,
                      (l3<=c3 && h3>=c1));
         else if(c1>c3 && (c1-c3)>=minGap)
            AppendFVG(StableZoneId(BarTime(shift),DIR_BEAR,5),
                      BarTime(shift), DIR_BEAR, c1, c3,
                      midBarDisplacementId, FVGK_VOL_IMBALANCE, PERIOD_CURRENT,
                      (l3<=c1 && h3>=c3));
      }
   }

   if(ArraySize(g_fvgs) > InpMaxFVG)
   {
      for(int i=0;i<ArraySize(g_fvgs)-1;i++) g_fvgs[i]=g_fvgs[i+1];
      ArrayResize(g_fvgs, InpMaxFVG);
   }
}

