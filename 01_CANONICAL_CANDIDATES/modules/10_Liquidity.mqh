//====================================================================
// LIQUIDITY REGISTRY ENGINE — رفع ایراد ۵ و ۶
//====================================================================
long AddLiquidity(ENUM_LIQ_TYPE type, ENUM_LIQ_SCOPE scope, double price, datetime t, bool isHTF)
{
   int n = ArraySize(g_liquidity);
   // جلوگیری از دابل ثبت نزدیک هم برای همان نوع
   for(int i=0;i<n;i++)
   {
      if(g_liquidity[i].type==type && g_liquidity[i].isHTF==isHTF &&
         g_liquidity[i].time==t &&
         MathAbs(g_liquidity[i].price-price) < PointsToPrice(InpEQ_Tolerance_Points))
         return g_liquidity[i].id;
   }
   LiquidityObj o;
   o.id = StableLiquidityId(t,type,price,isHTF); o.type=type; o.scope=scope; o.state=LSTATE_FRESH;
   o.price=price; o.time=t; o.sweptTime=0; o.sweptByEventId=-1; o.isHTF=isHTF;
   ArrayResize(g_liquidity, n+1);
   g_liquidity[n]=o;
   if(n+1 > InpMaxLiquidity)
   {
      for(int i=0;i<ArraySize(g_liquidity)-1;i++) g_liquidity[i]=g_liquidity[i+1];
      ArrayResize(g_liquidity, InpMaxLiquidity);
   }
   return o.id;
}

// نوع Liquidity در سمت بالا (Buy-Side) یا پایین (Sell-Side)
bool IsHighSideLiquidity(ENUM_LIQ_TYPE type)
{
   return (type==LIQ_PDH || type==LIQ_PWH || type==LIQ_EQH ||
           type==LIQ_SWING_H || type==LIQ_SESSION_H ||
           // فاز ۱۲ (#۲۰ #۶۵)
           type==LIQ_RANGE_H || type==LIQ_IPDA20_H ||
           type==LIQ_IPDA40_H || type==LIQ_IPDA60_H ||
           // فاز ۳۰ (#۷۶): نقدینگی مورب سمت Buy
           type==LIQ_TRENDLINE_H);
}

//--------------------------------------------------------------------
// فاز ۳۰ (#۷۵): پنجرهٔ هفتهٔ گذشته با لنگر ساعت نیویورک (دوشنبه‌محور).
// همان روش بسته‌بندی تاریخ نیویورک در WindowForDayBack استفاده می‌شود تا جمع
// و تفریق روز مستقل از DST درست بماند؛ تبدیل نهایی به وقت سرور با
// NYWallToServer (که DST نیویورک را در همان تاریخ لحاظ می‌کند) انجام می‌شود.
//--------------------------------------------------------------------
bool WeekWindowBack(int anchorH, datetime refBarTime, datetime &startOut, datetime &endOut,
                    double &hi, double &lo, int &barCount)
{
   MqlDateTime ref;
   NYStampOf(refBarTime, ref);
   MqlDateTime dr;
   dr.year=ref.year; dr.mon=ref.mon; dr.day=ref.day;
   dr.hour=0; dr.min=0; dr.sec=0; dr.day_of_week=0; dr.day_of_year=0;
   long packed=(long)StructToTime(dr);
   int dow=ref.day_of_week;                    // 0 = یکشنبه
   int toMonday=(dow==0)? 6 : (dow-1);         // دوشنبهٔ همان هفتهٔ نیویورک
   long mondayPacked=packed-(long)toMonday*86400;

   for(int back=1; back<=3; back++)
   {
      MqlDateTime m1, m2;
      TimeToStruct((datetime)(mondayPacked-(long)back*7*86400), m1);
      TimeToStruct((datetime)(mondayPacked-(long)(back-1)*7*86400), m2);
      startOut=NYWallToServer(m1.year,m1.mon,m1.day,anchorH,0,0);
      endOut  =NYWallToServer(m2.year,m2.mon,m2.day,anchorH,0,0);
      if(startOut<=0 || endOut<=startOut) continue;
      if(endOut>refBarTime) continue;                // هفته هنوز بسته نشده
      if(!WindowFullyCovered(startOut)) continue;    // دادهٔ کافی برای کل پنجره نیست
      if(CollectWindowRange(InpSessionSourceTF,startOut,endOut,hi,lo,barCount)) return true;
   }
   return false;
}

// PDH/PDL/PWH/PWL بر مبنای «مرز روز/هفته».
// (قبلاً با iHigh(...,1) و TimeCurrent محاسبه می‌شد که در بازپخش و در DST
//  مقدار اشتباه می‌داد — همان ایراد قدیمی.)
// فاز ۳۰ (#۷۵): مرز پیش‌فرض حالا نیمه‌شب نیویورک است (منبع در توضیح ورودی
// InpPD_Anchor) و مرز کندل بروکر فقط اگر کاربر خودش انتخاب کند استفاده می‌شود.
void UpdateLiquidityRegistry_PDH_PDL_PWH_PWL(datetime barTime)
{
   double pdh=0, pdl=0, pwh=0, pwl=0;
   datetime tD=0, tW=0;

   if(InpPD_Anchor==PD_ANCHOR_BROKER_DAY)
   {
      if(PreviousClosedBucket(barTime, PERIOD_D1, pdh, pdl, tD))
      {
         if(pdh>0) AddLiquidity(LIQ_PDH, SCOPE_EXTERNAL, pdh, tD, true);
         if(pdl>0) AddLiquidity(LIQ_PDL, SCOPE_EXTERNAL, pdl, tD, true);
      }
      if(PreviousClosedBucket(barTime, PERIOD_W1, pwh, pwl, tW))
      {
         if(pwh>0) AddLiquidity(LIQ_PWH, SCOPE_EXTERNAL, pwh, tW, true);
         if(pwl>0) AddLiquidity(LIQ_PWL, SCOPE_EXTERNAL, pwl, tW, true);
      }
      return;
   }

   int anchorH=(InpPD_Anchor==PD_ANCHOR_NY_1700)? 17 : 0;
   int cnt=0;
   bool gotDay=false;
   for(int back=1; back<=3 && !gotDay; back++)
   {
      if(!WindowForDayBack(back, anchorH,0, anchorH,0, barTime, tD, tW, pdh, pdl, cnt))
         continue;
      if(!WindowFullyCovered(tD)) continue;
      gotDay=true;
   }
   if(gotDay)
   {
      if(pdh>0) AddLiquidity(LIQ_PDH, SCOPE_EXTERNAL, pdh, tD, true);
      if(pdl>0) AddLiquidity(LIQ_PDL, SCOPE_EXTERNAL, pdl, tD, true);
   }

   if(WeekWindowBack(anchorH, barTime, tW, tD, pwh, pwl, cnt))
   {
      if(pwh>0) AddLiquidity(LIQ_PWH, SCOPE_EXTERNAL, pwh, tW, true);
      if(pwl>0) AddLiquidity(LIQ_PWL, SCOPE_EXTERNAL, pwl, tW, true);
   }
}

// EQH/EQL از سویینگ‌های LTF -> رفع ایراد ۶: هرکدام یک Object با متادیتای کامل
// EQH/EQL: خوشه‌بندی سوئینگ‌های هم‌سطح (نه یک آبجکت برای هر جفت)
// فاز ۳۰ (#۷۷) — «جدایی معنادار» بین دو عضو یک خوشهٔ EQH/EQL.
// منبع (LuxAlgo — Equal Highs/lows As Liquidity، مرحلهٔ ۲): «Require separation:
// a meaningful pullback between the swings, so they read as distinct tests rather
// than one drawn-out top»؛ و توصیف استاندارد پیاده‌سازی‌ها: «two **consecutive**
// pivots form within a user-defined price threshold» — یعنی دو پیوت هم‌نوع که یک
// پیوت مخالف بین‌شان نشسته باشد. بدون این شرط، چند سقف پشت‌سرهم در یک چرخش
// کند «یک سقف کشیده» بودند ولی به‌عنوان استخر نقدینگی ثبت می‌شدند.
// عمق لازم = max(تلورانس، InpEQ_MinSeparationATR × ATR).
bool HasPullbackBetween(SwingPoint &swings[], int i, int j, bool isHigh, double tol, double atrValue)
{
   if(InpEQ_MinSeparationATR<=0.0 && tol<=0.0) return true;   // شرط جدایی خاموش است
   double need=tol;
   if(atrValue>0.0 && InpEQ_MinSeparationATR>0.0)
      need=MathMax(tol, atrValue*InpEQ_MinSeparationATR);
   for(int k=i+1;k<j;k++)
   {
      if(swings[k].isHigh==isHigh) continue;                    // فقط سویینگ مخالف = پس‌رفت
      double depth = isHigh ? (swings[i].price-swings[k].price)  // کفِ پس‌رفت زیر سقف لنگر
                            : (swings[k].price-swings[i].price); // سقفِ پس‌رفت بالای کف لنگر
      if(depth>=need) return true;
   }
   return false;
}

void DetectEQ_FromSwings(SwingPoint &swings[], double atrValue)
{
   int n = ArraySize(swings);
   if(n<2) return;
   // تلورانس EQ باید با نوسان بازار مقیاس بخورد، نه پوینت ثابت؛ ۱۵ پوینت روی
   // XAUUSD پرمومنت تقریباً صفر است و روی جفت‌ارز آرام بیش‌ازحد (#۱۴).
   double tol = PointsToPrice(InpEQ_Tolerance_Points);
   if(atrValue>0.0 && InpEQ_ToleranceATR>0.0)
      tol = MathMax(tol, atrValue*InpEQ_ToleranceATR);

   // فاز ۱۳ (کارایی): این تابع در هر کندل بسته روی تا InpMaxSwings=۳۰۰ سوئینگ
   // اجرا می‌شد (O(n²) واقعی). حالا اگر مجموعهٔ سوئینگ‌ها و تلورانس عوض نشده
   // باشد، نتیجه از نو ساخته نمی‌شود.
   //
   // چرا حذف فراخوانی تکراری هیچ سطحی را کم نمی‌کند (اثبات، نه حدس): تابع
   // idempotent است — برای هر گروه، AddLiquidity با همان (نوع، isHTF، زمان،
   // قیمت) صدا زده می‌شود و شرط dedup خودش آن را رد می‌کند. پس اجرای دوم و
   // سوم و ... مجموعهٔ g_liquidity را تغییر نمی‌دهد.
   //
   // اثر انگشت مجموعه = (تعداد، شناسه و زمان آخرین سوئینگ، تلورانس). تنها
   // تغییری که PushSwing می‌تواند بسازد افزودن به انتهای آرایه یا حذف از
   // ابتدای آن (سقف) است؛ هر دو این اثر انگشت را عوض می‌کنند.
   if(n==g_eqStampCount && g_eqStampLastId==swings[n-1].id &&
      g_eqStampLastTime==swings[n-1].time && g_eqStampTol==tol)
   {
      g_eqSkips++;
      return;
   }
   g_eqStampCount=n; g_eqStampLastId=swings[n-1].id;
   g_eqStampLastTime=swings[n-1].time; g_eqStampTol=tol;

   bool used[];
   ArrayResize(used, n);
   for(int i=0;i<n;i++) used[i]=false;

   for(int i=0;i<n;i++)
   {
      if(used[i]) continue;
      bool isHigh = swings[i].isHigh;
      // فاز ۳۰ (#۷۷): تلورانس نسبت به **لنگر خوشه** سنجیده می‌شود، نه نسبت به
      // اکسترِمی که در حال حرکت است. دلیل (منبع، همان صفحه): «two or more swing
      // highs stalling **within a few ticks of one another**» و «draw a band
      // covering the slightly uneven extremes». با مقایسهٔ زنجیره‌ای قبلی، یک
      // نردبان نزولی از سقف‌ها (۱۰۰٫۰ / ۱۰۰٫۵ / ۱۰۱٫۰ با تلورانس ۰٫۶) یک خوشهٔ
      // EQH واحد می‌ساخت که دو سر آن ۱٫۰ دلار فاصله داشت — یعنی استخری که وجود
      // ندارد. حالا بیرون‌رفتن از باند لنگر، خوشه را تمام می‌کند.
      double anchor = swings[i].price;
      double extreme = anchor;
      datetime lastTime = swings[i].time;
      int members = 1;
      for(int j=i+1;j<n;j++)
      {
         if(swings[j].isHigh!=isHigh) continue;
         if(MathAbs(swings[j].price-anchor) > tol) break;   // بیرون از باند لنگر ⇒ خوشه تمام شد
         if(used[j]) continue;
         // فاز ۳۰ (#۷۷): دو عضو باید با یک پس‌رفت معنادار از هم جدا باشند،
         // وگرنه «یک سقف کشیده» هستند، نه دو تست مستقل (منبع در ورودی).
         if(!HasPullbackBetween(swings, i, j, isHigh, tol, atrValue)) continue;
         used[j]=true;
         members++;
         if(isHigh) extreme = MathMax(extreme, swings[j].price);
         else       extreme = MathMin(extreme, swings[j].price);
         lastTime = swings[j].time;
      }
      if(members>=2)
      {
         used[i]=true;
         AddLiquidity(isHigh?LIQ_EQH:LIQ_EQL, SCOPE_INTERNAL, extreme, lastTime, false);
      }
   }
}

// هر Swing تاییدشده به‌عنوان Swing Liquidity هم ثبت می‌شود
void RegisterSwingLiquidity(const SwingPoint &s, bool isHTF)
{
   AddLiquidity(s.isHigh?LIQ_SWING_H:LIQ_SWING_L,
                isHTF?SCOPE_EXTERNAL:SCOPE_INTERNAL,
                s.price, s.time, isHTF);
}

