//====================================================================
// DISPLACEMENT ENGINE — رفع ایراد ۸: علاوه بر انرژی کندل، باید به یک
// Event/Liquidity وصل شود تا "Displacement ICT" اثبات‌شده حساب شود.
//====================================================================
long DetectDisplacementCandidate(const double &open[], const double &high[], const double &low[],
                                  const double &close[], int shift, double atrValue,
                                  ENUM_DIRECTION &outDir)
{
   double range = high[shift]-low[shift];
   double body  = MathAbs(close[shift]-open[shift]);
   if(range<=0 || atrValue<=0) return -1;

   double bodyRatio = body/range;
   double rangeVsAtr = range/atrValue;

   if(bodyRatio < InpDisp_BodyRatio || rangeVsAtr < InpDisp_RangeVsAvg) return -1;

   outDir = (close[shift]>open[shift]) ? DIR_BULL : DIR_BEAR;

   DisplacementObj d;
   d.time = iTime(_Symbol, PERIOD_CURRENT, shift);
   d.id = StableDisplacementId(d.time,outDir);
   d.barShift = shift;
   d.direction = outDir;
   d.bodyRatio = bodyRatio;
   d.rangeVsAtr = rangeVsAtr;
   d.causedByEventId = -1;   // تا وقتی به یک Event وصل نشود energyOnly می‌ماند
   d.liquidityEventId = -1;
   d.energyOnly = true;

   int n = ArraySize(g_displacements);
   ArrayResize(g_displacements, n+1);
   g_displacements[n]=d;
   // فاز ۱۳ (#۱۱): سقف + سیاست حذف FIFO. مصرف‌کننده‌ها (لینک رویداد،
   // DetectMicroFVG، DisplacementIdForBarTime) همیشه روی کندل جاری کار
   // می‌کنند، پس حذف قدیمی‌ترین‌ها خروجی زنده را عوض نمی‌کند.
   if(InpMaxDisplacements>0 && ArraySize(g_displacements)>InpMaxDisplacements)
   {
      int drop=ArraySize(g_displacements)-InpMaxDisplacements;
      int keep=ArraySize(g_displacements)-drop;
      for(int k=0;k<keep;k++) g_displacements[k]=g_displacements[k+drop];
      ArrayResize(g_displacements,InpMaxDisplacements);
      g_dispDropped+=drop;
   }
   return d.id;
}

// وقتی Event ای (BOS/CHoCH/MSS) ثبت شد و همزمان با یک Displacement candidate
// هم‌پوشانی زمانی داشت، اینجا آن دو را به‌هم قفل می‌کنیم (اثبات ارتباط واقعی)
void LinkDisplacementToEvent(long dispId, long eventId, long liqEventId)
{
   int n = ArraySize(g_displacements);
   for(int i=0;i<n;i++)
   {
      if(g_displacements[i].id==dispId)
      {
         g_displacements[i].causedByEventId = eventId;
         g_displacements[i].liquidityEventId = liqEventId;
         g_displacements[i].energyOnly = false;
         return;
      }
   }
}

// شناسهٔ Displacement همان کندل (برای اتصال FVG به کندل میانی الگو)
long DisplacementIdForBarTime(datetime t)
{
   if(t<=0) return -1;
   for(int i=ArraySize(g_displacements)-1;i>=0;i--)
      if(g_displacements[i].time==t) return g_displacements[i].id;
   return -1;
}

// Displacement فقط وقتی "زنجیره‌شده" است که به یک Structure Event وصل شده
// باشد (energyOnly=false) و جهت آن با ناحیهٔ مورد بررسی یکی باشد (#۲۴، #۲۷).
bool DisplacementChained(long dispId, ENUM_DIRECTION wantDir)
{
   if(dispId==-1) return false;
   for(int i=0;i<ArraySize(g_displacements);i++)
      if(g_displacements[i].id==dispId)
         return (!g_displacements[i].energyOnly && g_displacements[i].direction==wantDir);
   return false;
}

// FVG ممکن است قبل از بسته‌شدن زنجیرهٔ ساختار ثبت شود. این تابع پس از هر
// اتصال، FVGهایی را Causal می‌کند که Displacementشان واقعاً زنجیر شده باشد.
void PromoteCausalFVGs()
{
   for(int i=0;i<ArraySize(g_fvgs);i++)
   {
      if(g_fvgs[i].causal) continue;
      // فاز ۴۳: اینجا جهت **تولد** گپ سنجیده می‌شود (زنجیرهٔ Displacement مربوط به
      // کندل سازندهٔ گپ است، نه به نقش امروزش). پس عمداً FVGActiveDir() صدا زده
      // نمی‌شود؛ باگ قبلی دقیقاً همین بود که همین `direction` وسط کار بازنویسی
      // می‌شد و این زنجیره پس از وارونگی دیگر هرگز تأیید نمی‌شد.
      if(!DisplacementChained(g_fvgs[i].displacementId, g_fvgs[i].direction)) continue;
      g_fvgs[i].causal=true;
      if(!g_rebuildMode || InpDrawFVGZones) DrawFVG(g_fvgs[i]);
   }
}

