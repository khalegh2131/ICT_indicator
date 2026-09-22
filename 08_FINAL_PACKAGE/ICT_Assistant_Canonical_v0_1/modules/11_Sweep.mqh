//====================================================================
// SWEEP ENGINE — رفع ایراد ۵: Sweep Engine حالا با Registry واحد کار
// می‌کند، پس هر نوع Liquidity (نه فقط ۶ نوع قدیمی) قابل Sweep شدن است
//====================================================================
// توجه: Sweep باید مستقل از وجود Displacement تشخیص داده شود (wick فراتر از
// سطح + بسته‌شدن برگشتی کافی است). ارتباط Sweep با Displacement/Event بعداً
// و جداگانه (در LinkDisplacementToEvent) به‌عنوان زنجیره Causal ثبت می‌شود؛
// این تفکیک باعث نمی‌شود که به‌خاطر نبود یک Displacement بزرگ، Sweepهای
// واقعی از قلم بیفتند.
long DetectSweep(double barHigh, double barLow, double barClose, datetime t, ENUM_DIRECTION &outSweepDir)
{
   int n = ArraySize(g_liquidity);
   outSweepDir = DIR_NONE;
   // اولویت با نزدیک‌ترین سطح به قیمت جاری (تا اگر چند سطح هم‌زمان جارو شدند
   // منطقی‌ترین یکی انتخاب شود)
   long bestId=-1; double bestDist=1e18; ENUM_DIRECTION bestDir=DIR_NONE;
   for(int i=0;i<n;i++)
   {
      if(g_liquidity[i].state != LSTATE_FRESH) continue;
      if(g_liquidity[i].time == 0 || g_liquidity[i].time > t) continue; // سطح باید قبل از این کندل موجود باشد
      bool isHighType = IsHighSideLiquidity(g_liquidity[i].type);
      // Sweep بالا: قیمت از سطح بالاتر می‌رود ولی کندل زیر آن بسته می‌شود (BSL swept -> نزولی)
      if(isHighType && barHigh > g_liquidity[i].price && barClose < g_liquidity[i].price)
      {
         double dist = MathAbs(barHigh - g_liquidity[i].price);
         if(dist < bestDist){ bestDist=dist; bestId=g_liquidity[i].id; bestDir=DIR_BEAR; }
      }
      // Sweep پایین: قیمت از سطح پایین‌تر می‌رود ولی کندل بالای آن بسته می‌شود (SSL swept -> صعودی)
      if(!isHighType && barLow < g_liquidity[i].price && barClose > g_liquidity[i].price)
      {
         double dist = MathAbs(barLow - g_liquidity[i].price);
         if(dist < bestDist){ bestDist=dist; bestId=g_liquidity[i].id; bestDir=DIR_BULL; }
      }
   }
   if(bestId!=-1)
   {
      // یک کندل می‌تواند چند سطح را هم‌زمان جارو کند (مثلاً EQH + PDH + سقف سشن).
      // همهٔ آن سطوح ثبت می‌شوند؛ شناسهٔ برگشتی فقط سطح اصلی (نزدیک‌ترین)
      // است تا زنجیرهٔ رویداد یک مالک داشته باشد (#۱۷).
      for(int i=0;i<n;i++)
      {
         if(g_liquidity[i].state != LSTATE_FRESH) continue;
         if(g_liquidity[i].time == 0 || g_liquidity[i].time > t) continue;
         bool isHighType = IsHighSideLiquidity(g_liquidity[i].type);
         bool sweptHere =
            (isHighType  && barHigh > g_liquidity[i].price && barClose < g_liquidity[i].price) ||
            (!isHighType && barLow  < g_liquidity[i].price && barClose > g_liquidity[i].price);
         if(sweptHere){ g_liquidity[i].state=LSTATE_SWEPT; g_liquidity[i].sweptTime=t; }
      }
      outSweepDir = bestDir;
   }
   return bestId;
}

