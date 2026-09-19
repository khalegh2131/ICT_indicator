# Audit کامل پروژه — دامنهٔ ICT + SMC + MMM

تاریخ: 2026-09-16
روش: خواندن کل `01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5` (۳۴۰۴ خط)، همهٔ اسناد، ابزارها، fixtureها، و تطبیق با مستندات رسمی MQL5 و منابع مرجع ICT/SMC/MMM.
هیچ کدی در این audit تغییر نکرد.

> **به‌روزرسانی 2026-09-16 (فاز ۸):** ستون‌های وضعیت در جدول‌های بخش ۲ وضعیت **زمان audit** را نشان می‌دهند، نه وضعیت امروز. موارد #۴، #۱۴، #۱۷، #۲۲، #۲۴، #۲۵، #۲۶، #۲۷، #۳۹ و #۴۰ در **فاز ۸** بسته شدند؛ جدول «فاز ۸ — بسته شد» در انتهای همین سند، قبل/بعد و شاهد واقعی را دارد.

راهنمای وضعیت:

- ✅ = محاسبه می‌شود و درست است
- 🟡 = وجود دارد ولی ناقص یا تقریبی
- 🔴 = وجود دارد ولی **غلط** است
- ❌ = صفر خط کد

---

## ۱) دامنهٔ رسمی (قفل‌شده)

**داخل دامنه:** ICT · SMC (Smart Money Concepts) · MMM (Market Maker Model)

**خارج از دامنه — رسماً حذف‌شده:** Wyckoff · Supply & Demand کلاسیک · Auction Market Theory / Market Profile · Volume Profile · Order Flow / Footprint / Delta · RTM (Read The Market) · Al Brooks Price Action

### شاهد اینکه این ۷ خانواده در مخزن نبودند

```text
grep -ril -E "wyckoff|volume profile|point of control|vpoc|value area|order flow|footprint|delta|
al brooks|read the market|market profile|tpo|initial balance|composite|upthrust|selling climax|
measured move|vwap|smart money|supply and demand|auction" --exclude-dir=.git .
```

نتیجه: **فقط یک فایل** → `07_DOCUMENTATION/RESEARCH_FINDINGS.md` (و فقط برای cross-check اصطلاحات و یک URL).

```text
02_SHARED_ENGINES/                     -> خالی
03_ICT_MODULES/                        -> خالی (نام پوشه هم ICT-only است)
05_TESTS_AND_VALIDATION/behavior/      -> خالی (صفر تست رفتاری)
06_EXTERNAL_REFERENCES/README.md       -> فقط منابع ICT/SMC + DeMark/HalfTrend/Divergence
```

### محدودیت پلتفرم که تصمیم حذف را تأیید می‌کند

مستند رسمی MT5 برای شاخص Volumes: «For the Forex market, Volumes is the indicator of the **number of price changes** within each period.»

یعنی در فارکس/CFD، حجم واقعی و در نتیجه `Delta` و `Footprint` واقعی از دادهٔ بومی MT5 قابل استخراج نیست. «Order Flow / Footprint» بدون فید فیوچرز یا بروکر خاص قابل پیاده‌سازی صادقانه نیست؛ بنابراین حذف شد.

---

## ۲) لیست کامل اجزای درون‌دامنه (۷۳ مورد)

### ۲‑A) ساختار

| # | جزء | وضعیت | علت خطا | درست چیست |
|---|---|---|---|---|
| 1 | Swing/Pivot تأییدشده (No-Repaint) | ✅ | — | pivot فقط پس از `InpSwingRight` کندل بعدی تأیید می‌شود |
| 2 | تفکیک Confirmed Pivot از Protected Level | ✅ | — | — |
| 3 | تفکیک ساختار Internal از External | ✅ | رفع شد در فاز ۱۲: `UpdateHtfInternalStructure()` پیوت‌های تأییدشدهٔ **همان تایم‌فریم مالک** (`InpHTF`) را در پنجرهٔ `InpInternalWindowBars` می‌گیرد و HH/HL یا LH/LL را در `g_htfInternalDir` می‌گذارد. ردیف `Internal` چارت‌محور سر جای خودش ماند و یک ردیف جدا برای مالک اضافه شد | **انجام شد** |
| 4 | BOS | 🔴 | در `trendDir==DIR_NONE` هم BOS صادر می‌شود. مرجع: BOS سیگنال **ادامهٔ** روند است | بدون روند قبلی، برچسب BOS مجاز نیست |
| 5 | CHoCH / MSB | ✅ | — | — |
| 6 | MSS | ✅ | `CHoCH + Displacement + Sweep` مطابق مرجع (Liquidity → Sweep → Displacement → BOS/CHoCH) | — |
| 7 | رویداد تکراری روی HTF | ✅ | رفع شد در فاز ۱۳: نگهبان باکت HTF در ابتدای `UpdateHTFStructure` (پیش از push پیوت و پیش از ارزیابی ساختار) + شمارنده‌های شاهد `g_htfEvalRuns`/`g_htfEvalSkips`. اثبات عددی: fixture سناریوی A (یک کندل H4، سه کندل بستهٔ چارت) → بدون نگهبان ۲ رویداد، با نگهبان ۱؛ سناریوی B نشان می‌دهد رویداد قانونی کندل بعدی حذف نمی‌شود. علت اصلی ایراد: | `EvaluateStructureBreak(hClose,0,...)` هر کندل بستهٔ LTF اجرا می‌شود؛ سوئینگ `broken` می‌شود و بار بعد همان close با سوئینگ قدیمی‌تر مقایسه می‌شود → BOS تکراری روی همان کندل H4 | هر کندل H4 حداکثر یک ارزیابی |
| 8 | Protected High / Low | ✅ | رفع شد در فاز ۱۱: `SwingById()` شناسه را به قیمت/زمان/نوع تبدیل می‌کند و `g_htfProtectedHighPrice`/`LowPrice` پر می‌شوند؛ دروازهٔ برگشت روی همین عدد کار می‌کند (تصویر لحظه‌ای **پیش از** ارزیابی ساختار) | **انجام شد** |
| 9 | مرحلهٔ روند / Trend Age | ✅ | رفع شد در فاز ۱۲: `UpdateTrendPhase()` سن را از رویداد HTF تعیین‌کنندهٔ Bias حساب می‌کند و `PHASE_INITIATION / EXPANSION / DISTRIBUTION / REVERSAL` را با دلیل متنی گزارش می‌دهد | **انجام شد** |
| 10 | Exhaustion / هشدار ضعف | ✅ | رفع شد در فاز ۱۱: ۶ معیار عددی دست‌نخورده مانده و `EXH_REVERSAL_CONFIRMED` حالا **قابل تولید** است — تنها از شاخهٔ `reversalFresh` که به `g_reversal.confirmed` گره خورده. اثبات مستقل: در کل فایل تنها یک انتساب به `g_htfBias` وجود دارد (خط تعریف) و بدنهٔ `UpdateExhaustion` هیچ انتسابی ندارد | **انجام شد** |
| 11 | سقف رجیستری‌ها | ✅ | رفع شد در فاز ۱۳: `AppendStructureEvent()` تنها مسیر push رویداد + سقف `InpMaxEvents=400`؛ سقف `InpMaxDisplacements=400` در `DetectDisplacementCandidate`؛ سیاست حذف FIFO (قدیمی‌ترین). همچنین یک باگ که خودِ سقف می‌ساخت رفع شد: تشخیص «رویداد تازه؟» از `ArraySize` به شمارندهٔ یکنوای `g_eventsAdded` منتقل شد. علت اصلی ایراد: | `g_events[]` و `g_displacements[]` سقف ندارند (بقیه دارند) → رشد بی‌پایان حافظه | سقف + سیاست حذف |
| 12 | `NewId()` | ✅ | حذف شد در فاز ۱۳ همراه با `g_nextId` (اثبات grep-دار: ۰ ارجاع به هر دو نام؛ شناسهٔ نهایی فقط از `StableEventId`). علت اصلی ایراد: | تولید می‌شود و بلافاصله با `StableEventId` بازنویسی می‌شود → کد مرده و گمراه‌کننده | — |

### ۲‑B) نقدینگی

| # | جزء | وضعیت | علت خطا | درست چیست |
|---|---|---|---|---|
| 13 | BSL / SSL | ✅ | — | — |
| 14 | EQH / EQL | 🟡 | تلورانس **پوینت ثابت** است، نه نرمال‌شده با ATR → روی XAUUSD و جفت‌ارز رفتار متفاوت | آستانه نسبت به ATR |
| 15 | PDH/PDL/PWH/PWL | ✅ | `CopyRates` با index 0 در حالت series = کندل جاری؛ منطق as-of درست است | — |
| 16 | Session High/Low | ✅ | Asian / London / NY AM range ثبت می‌شود | — |
| 17 | Liquidity Sweep / Stop Hunt / Judas | 🟡 | در هر کندل **فقط نزدیک‌ترین سطح** sweep می‌شود؛ اگر چند سطح هم‌زمان جارو شوند بقیه گم می‌شوند | ثبت همهٔ سطوح جاروشده |
| 18 | Reclaim بعد از Sweep | 🟡 | شرط close برگشتی هست، ولی reclaim رویداد مستقل با ID/زمان نیست | — |
| 19 | Trendline Liquidity | ✅ | رفع شد در فاز ۱۲: رجیستری `TrendlineLiqObj` با دو آنکر تأییدشده، شیب واقعی، شمارش برخورد و ابطال با **بسته‌شدن** فراتر از خط به اندازهٔ `InpTrendlineBreakATR×ATR`. خط تابع زمان است، پس قیمت با `TrendlinePriceAt()` حساب می‌شود — نه یک عدد ثابت | **انجام شد** |
| 20 | Range Liquidity | ✅ | رفع شد در فاز ۱۲: `UpdateRangeLiquidity()` ارتفاع رنج را با `InpRangeMaxATR×ATR` و تعداد برخورد هر مرز را با `InpRangeMinTouches` می‌سنجد؛ در صورت قبولی `LIQ_RANGE_H/L` ثبت می‌شود و دلیل رد صادقانه گزارش می‌شود. POI این مرز هم باند `۰.۱۰×ATR` دارد؛ پیش‌تر `top=bottom` بود و شرط رندر (`top>bottom`) آن را حذف می‌کرد درحالی‌که `FindBestPOI` همان را «بهترین ناحیه» برمی‌گرداند | **انجام شد** |
| 21 | Liquidity Pools (خوشهٔ چند سوئینگ) | 🟡 | EQH/EQL بخشی را می‌پوشاند؛ عمق/تعداد اعضا عددی نیست | — |
| 22 | انقضای نقدینگی (`LSTATE_INVALID`) | 🔴 | عضو enum و شاخهٔ `continue` در `DrawLiquidityLayer` وجود دارد ولی **هیچ‌جا set نمی‌شود** → سطوح بی‌نهایت FRESH می‌مانند و کد مرده می‌ماند. (تصحیح: `ExplainLiquidity` فقط FRESH/SWEPT را توصیف می‌کند، پس متن توضیح مشکلی ندارد؛ ایراد فقط در منطق است) | سیاست انقضا |
| 23 | `sweptByEventId` | ✅ | با `IdToStr` درست نمایش داده می‌شود | — |

### ۲‑C) Delivery و نواحی

| # | جزء | وضعیت | علت خطا | درست چیست |
|---|---|---|---|---|
| 24 | Displacement | 🟡 | فقط `body/range≥0.65` و `range/ATR≥1.5`؛ هیچ الزامی به ساخت FVG یا شکست ساختار ندارد. مرجع: «حرکت پرانرژی که FVG می‌سازد» | گره به FVG یا شکست ساختار |
| 25 | FVG Standard | 🔴 | مرزها درست، ولی `UpdateFVG_Lifecycle` با **همان کندل سازنده** اجرا می‌شود و شرط لمس با تساوی برقرار است → **هر FVG در لحظهٔ تولد MITIGATED می‌شود**. شاهد runtime: داشبورد «FVG: 6/6 CAUSAL» و «FVG lifecycle: 6 mitigated» (۶ از ۶) | لمس از کندل بعد |
| 26 | اتصال FVG به Displacement | 🔴 | به displacement **کندل سوم** وصل می‌شود؛ کندل Displacement **کندل میانی** است | `shift+1` |
| 27 | کیفیت Causal در FVG | 🔴 | `f.causal` با displacement صرفاً `energyOnly` (بدون اتصال به Event) هم `true` می‌شود — خلاف کامنت طراحی خود فایل. شاهد runtime: «FVG: 6/6 CAUSAL» = ۱۰۰٪ | فقط displacement زنجیرشده |
| 28 | CE (Consequent Encroachment) | ✅ | خط میانه رسم می‌شود | — |
| 29 | iFVG / Inversion | ✅ | فقط با close از سمت مخالف polarity عوض می‌شود | — |
| 30 | FVG Implied | ✅ | رفع شد در فاز ۱۲: گپ از **بدنهٔ** کندل اول و سوم ساخته می‌شود (`close` کندل ۱ ↔ `open` کندل ۳) و به‌عنوان `FVGK_IMPLIED` با شناسهٔ مستقل (`kind=3` در `StableZoneId`) ثبت می‌شود تا با گپ استاندارد قاطی نشود | **انجام شد** |
| 31 | FVG Micro | ✅ | رفع شد در فاز ۱۲: `DetectMicroFVG()` روی `InpMicroTF` (پیش‌فرض M1) گپ سه‌کندلی می‌یابد که **کاملاً داخل محدودهٔ کندل Displacement** باشد. فقط از Displacement **زنجیرشده** ساخته می‌شود تا رجیستری پر نشود. ناحیهٔ ورود ابتدا میان گپ‌های STANDARD/IMPLIED جست‌وجو می‌شود و Micro جانشین آخر است | **انجام شد** |
| 32 | Volume Imbalance | ❌ | صفر خط کد (در `RESEARCH_FINDINGS` قول داده شده) | — |
| 33 | BPR (Balanced Price Range) | ❌ | صفر خط کد (در `RESEARCH_FINDINGS` قول داده شده) | — |
| 34 | OB Bullish/Bearish | ✅ | آخرین کندل مخالف قبل از displacement | — |
| 35 | OB نوع Extreme | ✅ | رفع شد در فاز ۱۲: `MarkExtremeOrderBlocks()` نزدیک‌ترین ناحیه به اکسترمم لگ (سقف ← ناحیهٔ عرضه، کف ← ناحیهٔ تقاضا) را در فاصلهٔ `InpOB_ExtremeATR×ATR` برچسب `isExtreme` می‌زند و در امتیاز POI +۶ می‌گیرد | **انجام شد** |
| 36 | OB Internal در برابر External | ✅ | رفع شد در فاز ۱۲: `DetectOB` از داخل شرط «رویداد ساختاری ساخته شد» بیرون آمد و حالا فقط به `dispId!=-1` گره خورده. پس ناحیه‌ای با Displacement ولی **بدون** مشارکت در شکست ساختار واقعاً `OBK_STANDALONE` و `isStandalone=true` می‌شود؛ فیلتر `!isStandalone` دیگر مرده نیست و `UpdateSetup` ابتدا Core/Extreme و بعد Standalone را جست‌وجو می‌کند | **انجام شد** |
| 37 | OB Mitigation | 🟡 | «لمس = mitigation» رایج است، ولی زمان و تعداد برخورد ثبت نمی‌شود | — |
| 38 | Mitigation Block (مستقل) | ✅ | رفع شد در فاز ۱۲: `OB_MITIGATION` (در انتهای enum) + `OBK_MITIGATION_BLOCK`؛ همان زنجیرهٔ شکست + پولاریتی برعکس + ریتست، ولی با `liquidityEventId==-1`. این تفاوت تعریفی با Breaker است، نه یک نام دیگر برای آن | **انجام شد** |
| 39 | Breaker Block | 🔴 | (۱) **بدون الزام Sweep** (`liquidityEventId` می‌تواند −۱ باشد) درحالی‌که breaker سخت‌گیرانهٔ ICT sweep لازم دارد؛ (۲) یک کندل می‌تواند هم `violated` باشد هم `retestHappening` → BROKEN و بعد BREAKER در **همان کندل**. شاهد runtime: «OB: 3 VALID / 9 BREAKER» = ۷۵٪ breaker | sweep اجباری + retest در کندل جدا |
| 40 | Rejection Block | 🔴 | (۱) ناحیه = **کل کندل** (`top=high`, `bottom=low`) درحالی‌که ناحیهٔ Rejection Block **فتیله** است؛ (۲) هیچ الزامی به sweep یک swing high/low ندارد → هر کندل با فتیلهٔ ۶۰٪ ثبت می‌شود | ناحیهٔ فتیله + زمینهٔ سطح |
| 41 | Strength of Zone (کیفیت ناحیه) | ❌ | هیچ امتیازدهی کیفیت (تعداد برخورد، شارپ بودن حرکت، تازگی) وجود ندارد | — |
| 42 | Fresh vs Tested | 🟡 | فقط روی OB/Rejection؛ روی FVG عملاً بی‌معنی است چون همه mitigated شروع می‌کنند (#۲۵) | — |

### ۲‑D) Location

| # | جزء | وضعیت | علت خطا | درست چیست |
|---|---|---|---|---|
| 43 | Dealing Range | ✅ | رفع شد در فاز ۱۰ — `UpdateDealingLeg()` پیوت‌های تأییدشدهٔ H4 را تناوبی می‌کند و دو پیوت آخر همان لگ است (قبلاً两名 پیوت مستقل می‌توانستند به دو لگ مختلف تعلق داشته باشند) | محدودهٔ لگی که قیمت از آن گسترش یافته — **انجام شد** |
| 44 | Equilibrium (50%) | ✅ | درست محاسبه می‌شود | — |
| 45 | Premium / Discount | ✅ | رفع شد در فاز ۱۰ — `g_analysisClose` یک منبع قیمت شد و EQ/Premium/Discount از EQ همان لگ واقعی می‌آید. جزئیات اولیه:  EQ درست ولی مبنا (DR) غلط است (#۴۳). ضمناً داشبورد `Location` را از `SymbolInfoDouble(_Symbol,SYMBOL_BID)` می‌سازد درحالی‌که موتور ستاپ از close کندل → ناسازگاری ممکن | یک منبع واحد |
| 46 | OTE | ✅ | رفع شد در فاز ۱۰ — OTE از همان لگ واقعی (۶۲ / ۷۰٫۵ / ۷۹٪) حساب و رسم می‌شود و شرط «جهت لگ = جهت Bias» اضافه شد. جزئیات اولیه:  `zoneMid` (میانهٔ OB/FVG) داخل باند ۶۲–۷۹٪ چک می‌شود. مرجع: ۶۲–۷۹٪ ریتریس **لگ/سوئینگ تأییدشده**، نقطهٔ طلایی ۷۰.۵٪. کامنت خود کد اعتراف می‌کند روی leg حساب نشده | محاسبه از leg |
| 47 | PD Array / POI | ✅ | رفع شد در فاز ۱۲: رجیستری یکپارچهٔ POI (`POIObj`) منابع FVG causal / OB / Breaker / Mitigation Block / Rejection / Trendline / Range را با نوع، جهت، محدوده، زمان، TF مالک، اعتبار و **امتیاز عددی تفکیک‌شده** نگه می‌دارد؛ مرتب‌سازی نزولی و انتخاب بهترین POI هم‌جهت Bias | **انجام شد** |
| 48 | Draw on Liquidity (DOL) | ✅ | رفع شد در فاز ۱۰ — امتیازدهی چندمعیاره با تفکیک عددی (External ۳۰ + HTF ۱۰ + نوع سطح ۶‑۱۵ + هم‌راستایی ۱۰ + نزدیکی تا ۲۵ نرمال‌شده با ATR)؛ سطوح نزدیک‌تر از `InpDOL_MinRoomATR` رد می‌شوند؛ `sweepStateOk` از state واقعی سطح می‌آید (فقط LSTATE_FRESH به حلقه می‌رسد) و `breakdown` عددی در داشبورد/پنل دیده می‌شود | امتیاز چندمعیاره — **انجام شد** |
| 49 | Liquidity Run / NDOG-NWOG | ❌ | وجود ندارد | — |

### ۲‑E) Time

| # | جزء | وضعیت | علت خطا | درست چیست |
|---|---|---|---|---|
| 50 | ورودی‌های سشن | ✅ | رفع شد در فاز ۹ — پنجره‌ها از ورودی خوانده می‌شوند (`InNYWindow`) و پنل پنجرهٔ نامعتبر را رد می‌کند | خواندن از ورودی‌ها — **انجام شد**
| 51 | Kill Zones | ✅ | `InpKillzoneDaysBack` و `InpDrawKillzoneBoxes` کار می‌کنند؛ ساعت‌ها با منابع تطبیق داده شد | — |
| 52 | Silver Bullet | ✅ | رفع شد در فاز ۹ — سه باکس `ICTv13_SESS_SB1/SB2/SB3` رسم می‌شود و `InpDrawSilverBullet` واقعاً کار می‌کند | باکس پنجره رسم شود — **انجام شد**
| 53 | Macros | ❌ | صفر خط کد | — |
| 54 | AMD / Power of Three | 🟡 | فقط لیبل زمانی از روی ساعت؛ Acc/Man/Dist رنج‌محور محاسبه نمی‌شود | — |
| 55 | Broker GMT Offset | ✅ | رفع شد در فاز ۹ — `RefreshBrokerOffset()` در هر کندل بسته؛ آفست به **ثانیه** (بروکر ۳۰/۴۵ دقیقه‌ای هم درست)؛ در تغییر، سطوح سشن با آفست قدیمی پاک و بازمحاسبه می‌شوند | بازآزمایی در هر کندل — **انجام شد**
| 56 | DST نیویورک | ✅ | رفع شد در فاز ۹ — قاعده روی UTC بسته می‌شود (۰۷:۰۰ UTC دومین یکشنبهٔ مارس / ۰۶:۰۰ UTC اولین یکشنبهٔ نوامبر). `tools/Validate-TimeBase.ps1` می‌گوید قاعدهٔ قدیم ۷۲۱ دقیقه در مارس و ۳۶۰ دقیقه در نوامبر اشتباه بود | DST از ۰۲:۰۰ همان روز — **انجام شد (تا ثانیه)**
| 57 | `InpBrokerToNY_HourOffset` | ✅ | رفع شد در فاز ۹ — نقش واقعی گرفت: fallback وقتی تشخیص خودکار غیرقابل‌اعتماد است (|offset|>۱۵h) + مرجع در Journal و ردیف `clock` داشبورد | حذف یا وصل — **وصل شد**
| 58 | SMT (divergence بین نمادها) | ❌ | صفر خط کد (در `RESEARCH_FINDINGS` قول داده شده) | — |

### ۲‑F) Context و MTF

| # | جزء | وضعیت | علت خطا | درست چیست |
|---|---|---|---|---|
| 59 | Bias owner = H4 | ✅ | تضاد M1/M2 فقط READY را block می‌کند و Bias را عوض نمی‌کند؛ با validator روی ۶۰۰ ردیف واقعی تأیید شد | — |
| 60 | as-of-bar برای HTF | ✅ | `CopyRatesAsOf` با فرم زمانی + حذف کندل HTF باز؛ مطابق مستند رسمی `CopyRates` | — |
| 61 | `InpMTF` | ✅ | رفع شد در فاز ۹ — تایم‌فریم «ساختار داخلی» را انتخاب می‌کند (`InternalDirectionAsOf`)؛ ردیف `Internal <TF>` داشبورد از آن می‌آید | حذف یا وصل — **وصل شد (فقط نمایش/توضیح، بدون دروازهٔ جدید)** |
| 62 | Nested / MTF Mitigation | ❌ | وجود ندارد | — |
| 63 | Volatility / Spread risk | ❌ | وجود ندارد (در سند قول داده شده) | — |
| 64 | News / session risk | ❌ | وجود ندارد (در سند قول داده شده) | — |
| 65 | IPDA Reference Levels | ✅ | رفع شد در فاز ۱۲: افق‌های ۲۰/۴۰/۶۰ روزه با `CopyHigh/CopyLow` روی کندل‌های **بستهٔ** روزانه؛ اگر تعداد کندل برگشتی کمتر از افق باشد، آن افق **ثبت نمی‌شود** و کمبود صادقانه در داشبورد گزارش می‌شود (هیچ مقدار تقریبی نوشته نمی‌شود) | **انجام شد** |

### ۲‑G) مدل، خروجی، سیستم

| # | جزء | وضعیت | علت خطا | درست چیست |
|---|---|---|---|---|
| 66 | مدل ستاپ (Entry/SL/TP/RR) | ✅ | رفع شد در فاز ۱۰ (هر چهار بند): (۱) دروازهٔ چرخهٔ اثبات‌شدهٔ Sweep+Displacement+شکست ساختار هم‌جهت و تازه اضافه شد؛ (۲) `buf = max(ATR×InpSL_MinATR, InpSL_MinPoints×_Point, SYMBOL_TRADE_STOPS_LEVEL×_Point)` و `WAITING_SL_INVALID` برای risk≤۰؛ (۳) `rr = |TP3−entry|/|entry−SL|` واقعی + `InpMinRR` (حالا `TP3 = max/min(entry±risk×3, DOL)` و R:R همان است که نمایش داده می‌شود)؛ (۴) `FindSetupTFZone()` ناحیه را روی تایم‌فریم SETUP (M5) جست‌وجو می‌کند و `zoneSource` می‌گوید کدام منبع استفاده شد | — **انجام شد** |
| 67 | Entry Models (ICT 2022 / BOS→FVG→OB / Sweep Entry) | ✅ | رفع شد در فاز ۱۲: `SelectEntryModel()` با چهار مدل و شرط عددی جدا؛ اولویت خودکار ICT2022 → BOS/FVG/OB → Sweep Entry → OTE و ورودی `InpPreferredEntryModel` می‌تواند یک مدل را اجبار کند؛ ناموفق بودن مدل اجباری = `WAITING_ENTRY_MODEL` صریح | **انجام شد** |
| 68 | Confluence checklist / کیفیت ستاپ | ✅ | رفع شد در فاز ۱۲: `UpdateSetup` ده معیار **متغیر** را می‌شمارد (MSS کامل، FVG causal، OB معتبر، Core/Extreme بودن OB، اکسترمم لگ، ناحیهٔ SETUP، POI ساختاری، قیمت داخل OTE، فاز روند ادامه‌دار، R:R با حاشیه) و ستاپ زیر `InpMinQualityScore` با `WAITING_QUALITY_LOW` رد می‌شود | **انجام شد** |
| 69 | Outcome tracking | ❌ | ثبت نتیجهٔ ستاپ وجود ندارد (در سند قول داده شده) | — |
| 70 | **Smart Money Reversal (MMM)** | ✅ | رفع شد در فاز ۱۱: `ScoreSmartMoneyReversal()` چهار شاهد عددی می‌شمارد (Sweep نقدینگی مقابل در پنجرهٔ ورودی · Displacement زنجیرشدهٔ هم‌جهت · ناحیهٔ هم‌جهت FVG causal/OB معتبر · هم‌جهتی ساختار داخلی/پایین‌تر) و آستانه `InpSMR_MinScore` است. **تعریف عملیاتی همین پروژه است، نه نقل قول از قاعدهٔ خصوصی شخص سوم** (جست‌وجوی وب در آن نوبت نتیجه نداد) | **انجام شد** |
| 71 | تأیید برگشت بیرونی | ✅ | رفع شد در فاز ۱۱: رویداد `EVT_EXTERNAL_BREAK` روی H4 ساخته می‌شود (enum + `EventTypeToStr` + `RegisterExternalBreakEvent` با dedup بر `StableEventId`) و `UpdateReversalEngine` دروازه را از **close کندل بستهٔ HTF** می‌سنجد، نه فتیله | **انجام شد** |
| 72 | Alerts | ❌ | `OnTimer` خالی است و `EventSetTimer(1)` بی‌استفاده است | — |
| 73 | BISI / SIBI | 🟡 | منطق FVG صعودی/نزولی هست، برچسب MMM نیست (فقط نام‌گذاری) | — |

### ۲‑H) مشترک: آموزش، نمایش، کارایی، صداقت سند

| مورد | وضعیت | علت |
|---|---|---|
| پنل Explain فارسی چندخطی | ✅ | با screenshot تأیید شد؛ متن RTL با اعداد و توکن‌های لاتین درست خوانده می‌شود |
| ~~حالت پیش‌فرض رندر ۳~~ | ✅ | **کار می‌کند — دست نزنید** |
| حالت ۲ (شکل‌دهی دستی) | 🔴 | `VisualOrderForLtrEngine` هر کلمهٔ فارسی را کاراکتر‌به‌کاراکتر معکوس می‌کند → اعداد فارسی (۰‑۹) معکوس می‌شوند: «۱۲۳» → «۳۲۱». فقط به‌عنوان fallback است |
| لیگاتور «لا» | 🟡 | ساخته نمی‌شود |
| Hit-test روی متن | 🟡 | برای `OBJ_TEXT` فقط anchor تست می‌شود → موس روی خود متن توضیح نمی‌دهد |
| `"\n"` برای tooltip | ✅ | روش رسمی مستند MQL5 برای خفه‌کردن tooltip |
| داشبورد — برچسب کهنه | ✅ | رفع شد در فاز ۱۴: `DashBegin`/`DashRow`/`DashEnd`؛ مجموعهٔ ردیف‌های این pass ثبت می‌شود و `DashEnd` هر برچسب `ICTv13_DASH_*` که در آن نباشد را حذف می‌کند. اثبات: fixture `phase14_stale_rows` + شمارندهٔ `g_dashStale` در `Phase14_Diag.csv` — پیش از رفع: برچسب‌های شرطی (`sb`, `asia`, `dirline`, `entry`, `sl`, `tp1..tp3`, `rr`, `mtfreason`) هیچ‌وقت حذف نمی‌شدند |
| داشبورد — بریدن و سرریز | ✅ | رفع شد در فاز ۱۴: `DashMeasure()` با `TextSetFont`+`TextGetSize` عرض واقعی هر ردیف را می‌گیرد و `DashEnd()` کادر را از بلندترین ردیف و تعداد ردیف مصرف‌شده می‌سازد (`width=max(140, ceil10(maxRowW+24))` · `height=max(40, lh×rows+16)`). شکستن خط در آخرین جداکنندهٔ جا‌شده اگر `InpDashMaxWidth>40` باشد؛ و اگر باز هم جا نشد متن **بریده نمی‌شود**. اثبات: fixture `phase14_dash_size` + `phase14_wrap`. شاهد پیش از رفع: کادر ثابت ۳۸۰×۶۴۰ در برابر نیاز واقعی ۶۵۶ پیکسل ارتفاع برای ۴۱ ردیف |
| داشبورد — مبنا | ✅ | رفع شد در فاز ۱۰: `Location` از `g_analysisClose` (close کندل تحلیلی) و از همان `g_leg` ساخته می‌شود؛ دیگر `SYMBOL_BID` خوانده نمی‌شود. در فاز ۱۴ دوباره تأیید شد |
| داشبورد — separator تکراری | ✅ | رفع شد در فاز ۱۴: تنها `sep4` می‌ماند. اثبات: `duplicate-separator-removed` در `Validate-Phase14.ps1` (`DashRow("sep5")` = ۰) |
| کارایی — rebuild | ✅ | فاز ۱۳: سه کاهش واقعی — (۱) سرکوب هفت فراخوانی رسم در کل بازسازی (چون انتهای بازسازی لایه از Registry از نو ساخته می‌شود)، (۲) یک بافر مشترک M15 برای همهٔ پنجره‌های سشن (`EnsureSessionBars`) به‌جای ~۹۰ فراخوانی `Copy*` در هر کندل، (۳) memo تشخیص EQ. بازسازی هم با `RedrawChartObjects()` تمام می‌شود. علت اصلی ایراد: | ۶۰۰ کندل × (۶ تایم‌فریم × ۲۴۰ کندل اسکن + تا ~۹۰ فراخوانی `CopyTime/High/Low` برای پنجره‌های سشن) → احتمال فریز چند ثانیه‌ای در attach |
| کارایی — `DetectEQ_FromSwings` | 🟡 | فاز ۱۳: memo روی اثر انگشت مجموعهٔ سوئینگ‌ها (تعداد + شناسه/زمان آخرین سوئینگ + تلورانس)؛ چون تابع idempotent است و `AddLiquidity` گروه تکراری را رد می‌کند، skip هیچ سطحی را گم نمی‌کند (fixture `phase13_eqidem`). بدترین حالت هنوز O(n²) است و تبدیل به clustering روی قیمت مرتب **مجاز نیست**، چون با ترتیب زمانی فعلی (گسترش اکستریمم) معادل نیست. علت اصلی ایراد: | O(n²) روی تا ۳۰۰ سوئینگ در **هر** کندل بسته |
| کارایی — `EventLedgerContains` | ✅ | فاز ۱۳: ایندکس شناسه‌ها یک بار در رم (`EnsureLedgerIndex`) و به‌روزرسانی پس از هر نوشتن (`LedgerIndexAdd`)؛ تابع جست‌وجو دیگر `FileOpen` ندارد (اثبات سطح سورس). علت اصلی ایراد: | کل فایل ledger برای **هر** رویداد خوانده می‌شود → O(n²) I/O |
| کارایی — `ExplainSaveCsv` | 🟡 | هر کندل بسته کل فایل را از نو می‌نویسد + برای هر آبجکت کل Registry اسکن می‌شود |
| کارایی — rebuild بدون redraw | ✅ | فاز ۱۳: `RedrawChartObjects()` در پایان بازسازی صدا زده می‌شود، و چون در بازسازی هیچ آبجکتی رسم نمی‌شود این تنها گذر رسم اولیه است (بدون رسم دوباره). علت اصلی ایراد: | در پایان rebuild `RedrawChartObjects()` صدا زده نمی‌شود → چارت تا کندل بعدی ناهمگام |
| **تاریخچهٔ نمایش با سقف رجیستری حذف می‌شود** | ✅ | رفع شد در فاز ۱۴: `RedrawChartObjects` دیگر کل لایه را پاک نمی‌کند (اثبات: ۰ فراخوانی `ObjectsDeleteAll` در بدنهٔ آن). `MarkDrawnLayerObj` روی هر ۱۳ مسیر ساخت آبجکت صدا زده می‌شود (اثبات ساختاری: ۱۳ سایت `ObjectCreate` = ۱۳ سایت `MarkDrawnLayerObj`) و `ReconcileChartLayer()` بقیه را به سبک frozen نگه می‌دارد — `InpFrozenColor` + `STYLE_DOT` + tooltip صریح، با سقف FIFO `InpMaxFrozenObjects=300`. سقف‌های رجیستری (`g_fvgs`=۱۵۰ · `g_obs`=۱۵۰ · `g_rejections`=۵۰ · `g_liquidity`=۴۰۰ · `g_swings`=۳۰۰) بلا تغییر مانده‌اند؛ حالا دیگر باعث ناپدیدی نمی‌شوند. آبجکتی که دوباره داخل پنجرهٔ نمایش بیاید، رنگ اصلی‌اش خودکار برمی‌گردد (`g_frozenRestored`). **هنوز فقط با reload چارت شاهد عددی دارد** |
| `g_bufDummy` | ✅ | فاز ۱۳: بافر و `SetIndexBuffer` حذف شدند و `#property indicator_buffers 0` بدون خطا و **بدون warning** کامپایل می‌شود (اثبات سطح سورس در `Validate-Phase13.ps1`). علت اصلی: ۱ بافر بی‌استفاده با `SetIndexBuffer` |
| سند — `REVERSAL_CONFIRMED` | 🔴 | `08_FINAL_PACKAGE/.../README.md` خط ۳۰ و `CANONICAL_ARCHITECTURE.md` خط ۴۰ آن را قابلیت موجود می‌نامند؛ کد هرگز set نمی‌کند |
| سند — `CANONICAL_ARCHITECTURE.md` خط ۴۰ | 🔴 | می‌گوید «external protected level is closed through»؛ همین شناسه‌ها خوانده نمی‌شوند |
| سند — متن `ExplainSetup` | 🔴 | می‌گوید «همهٔ دروازه‌های سخت: تخلیهٔ نقدینگی، تأیید ساختار با Displacement…»؛ `UpdateSetup` هیچ‌کدام را چک نمی‌کند |
| سند — `RESEARCH_FINDINGS.md` | 🔴 | BPR، Volume Imbalance، SMT، Macros، Volatility/Spread risk، News risk، Outcome tracking قول داده شده‌اند و در کد نیستند |
| نسخه | 🟡 | سورس خط ۱۷: `13.20` و `V13_2_EAGLE_EYE`؛ فایل `v0_1` است → MT5 عنوان ۱۳.۲۰ نشان می‌دهد |

---

## ۳) جمع‌بندی عددی

پایین‌ترین ستون «خط پایه» وضعیت لحظهٔ نوشتن audit است و ستون دوم با **بازخوانی همان جدول‌های بخش ۲** پس از فازهای ۷ تا ۱۲ به‌روز شده است:

| وضعیت | خط پایهٔ audit | جاری (پایان فاز ۱۲) |
|---|---:|---:|
| ✅ درست | ۱۳ | **۴۳** |
| 🟡 ناقص/تقریبی | ۲۳ | **۱۰** |
| 🔴 غلط | ۲۲ | **۹** |
| ❌ صفر خط کد | ۱۵ | **۱۱** |
| جمع | ۷۳ | ۷۳ |

موارد باقی‌مانده زیر ❌/🔴 عمدتاً در حیطهٔ فازهای ۱۳ تا ۱۵ هستند (سقف رجیستری‌ها، به‌روزرسانی الگو، ابطال SL، ردیابی نتیجه، BPR، Macros و SMT).

پوشش خانواده‌ها: عدد درصدی این سطر یک **تخمین** است، نه سنجهٔ ماشینی. سنجهٔ ماشینی همان جدول بالا است: ۴۳ از ۷۳ مورد audited اکنون ✅ هستند. پیشرفت موتور برگشت + Smart Money Reversal (فاز ۱۱) و پوشش SMC/MMM (فاز ۱۲) بزرگ‌ترین سهم را داشته‌اند.

---

## ۴) پاسخ به پرسش «نقاط برگشتی»

**پاسخ پس از فاز ۱۱: بله، می‌تواند — ولی فقط یک نقطهٔ برگشت را دوباره اعلام می‌کند و فقط وقتی معیار پذیرش خودش برآورده شود.** شاهدهای کد و ابزار در جدول زیر و در بخش فنی مربوطه در مستندات پروژه. نکتهٔ باقی‌مانده: تأیید این‌که روی نماد واقعی یک برگشت واقعاً تولید شود یک reload چارت لازم دارد (فاز ۱۵).

| مسیر تأیید برگشت در دامنهٔ ما | وضعیت |
|---|---|
| ICT/SMC: بستن کندل فراتر از Protected Level H4 | ✅ فاز ۱۱: `UpdateReversalEngine` روی قیمت واقعی سطح (نه شناسه) و **close کندل بستهٔ HTF** سنجش می‌کند (#۸ و #۷۱) |
| ICT/SMC: state `REVERSAL_CONFIRMED` | ✅ فاز ۱۱: از شاخهٔ `reversalFresh` قابل تولید است (#۱۰) |
| MMM: **Smart Money Reversal** | ✅ فاز ۱۱: ۴ شاهد عددی + آستانهٔ ورودی (#۷۰) — تعریف عملیاتی مستند، نه نقل قول |
| SMC: CHoCH/MSS مخالف در HTF | 🟡 هست، ولی MTF فقط تضاد را block می‌کند و هرگز Bias H4 را برنمی‌گرداند (این رفتار **درست** است) → پس هیچ مسیری برای flip اعلام‌شدهٔ Bias وجود ندارد |

هشدار ضعف (`EXH_MICRO_REVERSAL_CONFIRMED` = «ساختار داخلی مخالف» + «یک کندل بستهٔ مخالف با انرژی کافی») هنوز هم فقط هشدار است و برگشت اعلام نمی‌کند — همین رفتار درست است و دست نخورد. برگشت **تأییدشده** فقط از `EXH_REVERSAL_CONFIRMED` می‌آید که تنها با بسته‌شدن فراتر از سطح محافظت‌شدهٔ خارجی تولید می‌شود.

معماری فعلی هم «ورود» را می‌فهمد (Sweep → MSS → FVG/OB → OTE → DOL) و هم «برگشت تأییدشده» را (سطح محافظت‌شده → رویداد `EVT_EXTERNAL_BREAK` → `REVERSAL_CONFIRMED`).

---

## ۵) آنچه فقط با اجرای واقعی قابل اثبات است (حدس نمی‌زنیم)

1. Full History Replay در برابر Incremental Replay
2. Restart Determinism و immutability رویدادهای قدیمی
3. آفست واقعی بروکر و تاریخچهٔ DST آن
4. اینکه در بازهٔ دیده‌شده H4 واقعاً fractal تأییدشده نداشته یا نه
5. رفتار setup روی نمونه‌های واقعی FVG / Sweep / OB / Breaker

---
---

# نقشهٔ تعمیر — ۹ فاز

هر فاز فقط وقتی تمام است که معیار پذیرشش با شاهد (build تازه + داده/عکس) ثابت شود.
هیچ فازی نباید رندر فارسی را تغییر دهد.

## فاز ۷ — قفل دامنه و صداقت سند

**هدف:** هیچ سند یا متنی ادعای قابلیتی را نکند که در کد نیست؛ دامنه صریح باشد.

**کار:** ثبت دامنهٔ ICT+SMC+MMM و حذف رسمی ۷ خانواده در مستندات پروژه و READMEها · اصلاح ادعای `REVERSAL_CONFIRMED` در `README.md` و `CANONICAL_ARCHITECTURE.md` · اصلاح متن `ExplainSetup` که دروازه‌های ناموجود را ادعا می‌کند · اصلاح `RESEARCH_FINDINGS.md` برای موارد قول‌داده‌شده ولی پیاده‌نشده · یکسان‌سازی نسخه (`v0_1` در برابر `13.20`).

**معیار پذیرش:** grep روی مستندات هیچ ادعای بی‌کدبرگشتی نداشته باشد؛ جدول دامنه در مستندات پروژه موجود باشد.
**ریسک:** صفر (بدون تغییر منطق). **حالت پیشنهادی:** HIGH

## فاز ۸ — دقت موتور هسته  ✅ انجام‌شده (2026-09-16)

**وضعیت:** بسته شد — شرح کامل، قبل/بعد، شاهد واقعی و hash build در مستندات فنی پروژه.

**هدف:** محاسبات FVG / OB / Breaker / Rejection / BOS / Liquidity / Displacement درست شوند.

**کار:** #۲۵ FVG در کندل سازنده mitigated نشود · #۲۶ اتصال به کندل میانی · #۲۷ causal فقط با displacement زنجیرشده · #۳۹ Breaker با sweep اجباری و retest در کندل جدا · #۴۰ Rejection با ناحیهٔ فتیله و زمینهٔ سطح · #۴ BOS در نبود روند صادر نشود · #۲۲ سیاست `LSTATE_INVALID` · #۱۷ ثبت چند سطح sweep در یک کندل · #۱۴ تلورانس EQ نرمال‌شده با ATR · #۲۴ Displacement گره‌خورده به FVG/ساختار.

**معیار پذیرش:** روی دادهٔ واقعی، FVG تازه FRESH بماند؛ هیچ FVG با کندل خودش mitigated نشود؛ نسبت breaker به کل OB معقول باشد؛ شمارش داشبورد با واقعیت بخواند.
**ریسک:** متوسط (منطق تشخیص). **حالت پیشنهادی:** MAX (این فاز، هستهٔ دقت است)

### فاز ۸ — بسته شد: قبل در برابر بعد

شاهد «قبل» از دادهٔ واقعی MT5 (build پیش از فاز ۸):

```text
Explain.csv  (2026-09-16 13:00)
  FVG rows = 8   ->  IFVG=7  MITIGATED=1  FRESH=0
  FVG Causal = 8/8 (100%)
  Liquidity rows = 60  ->  FRESH=32  SWEPT=28  INVALID=0
  OB rows = 8  ->  INVALID=6  BREAKER=2
ReplayLedger.csv (2026-09-15 23:43)
  events = 99  ->  BOS=55  CHoCH=40  MSS=4
```

هر چهار عدد بالا مستقیماً همان باگ‌های شماره‌گذاری‌شدهٔ این audit هستند (`FRESH=0` = #۲۵، `Causal=100%` = #۲۷، `INVALID=0` = #۲۲، غلبهٔ `BOS` = #۴).

| # | جزء | اصلاح فاز ۸ |
|---|---|---|
| ۴ | BOS | برچسب BOS فقط با روند هم‌جهت تأییدشده؛ شکست بدون روند = CHoCH (و همان CHoCH جهت مالک را تعیین می‌کند تا ماشین روند رگرسیون نکند) |
| ۱۴ | EQH/EQL | تلورانس = `max(PointsToPrice(InpEQ_Tolerance_Points), ATR × InpEQ_ToleranceATR)` |
| ۱۷ | Liquidity Sweep | همهٔ سطوح جاروشده در یک کندل ثبت و به رویداد همان کندل وصل می‌شوند |
| ۲۲ | انقضای نقدینگی | `UpdateLiquidityLifecycle`: عبور بسته‌شده از سطح ⇒ `LSTATE_INVALID`؛ سطوح INVALID حذف نمی‌شوند و کم‌رنگ رسم می‌شوند |
| ۲۴ | Displacement | Causal فقط با Displacement زنجیرشده به Structure Event؛ Displacement انرژی‌محور هرگز FVG را Causal نمی‌کند |
| ۲۵ | FVG Standard | محافظ `createdTime >= curBarTime` در `UpdateFVG_Lifecycle` (و همان محافظ برای OB و Rejection) |
| ۲۶ | اتصال به Displacement | به Displacement **کندل میانی** (`shift+1`) وصل می‌شود، نه کندل سوم |
| ۲۷ | کیفیت Causal | `DisplacementChained()` + `PromoteCausalFVGs()` جای منطق سخاوتمند قبلی |
| ۳۹ | Breaker | `liquidityEventId!=-1` اجباری + `brokenTime` + شرط `curBarTime>brokenTime` (ریتست در کندل جدا) |
| ۴۰ | Rejection Block | ناحیه = فتیلهٔ غالب؛ ثبت فقط با Sweep همان کندل و هم‌خوانی جهت |

**تأییدنشده:** اجرای واقعی روی چارت با build جدید. سنجه‌های «بعد» با ابزار فقط-خواندنی `tools/Report-CoreObjectEvidence.ps1` بعد از reload ثبت می‌شود.

## فاز ۹ — زمان و ورودی‌های بی‌اثر

**هدف:** هیچ ورودی بی‌اثری نماند؛ DST و آفست بروکر درست باشد.

**کار:** #۵۰ وصل‌کردن ۶ ورودی سشن (یا حذفشان) · #۵۲ رسم واقعی باکس Silver Bullet · #۵۷ حذف/وصل `InpBrokerToNY_HourOffset` · #۶۱ حذف/وصل `InpMTF` · #۵۵ بازآزمایی آفست بروکر در هر کندل · #۵۶ اصلاح مرز روز شروع DST.

**معیار پذیرش:** تغییر هر ورودی سشن روی چارت اثر visible بگذارد؛ هیچ ورودی بدون مصرف نماند؛ پنجره‌های سشن در دو سوی تغییر DST بروکر درست باشند.
**ریسک:** متوسط (وابسته به دادهٔ بروکر). **حالت پیشنهادی:** HIGH

**وضعیت: ✅ انجام شد (2026-09-16) — در مستندات فنی پروژه.**
اگر `InpAsiaStartHourNY` را در پنل عوض کنی، کادر رنج آسیا، خط `Session:` داشبورد، و سطح `LIQ Session High/Low` هر دو تغییر می‌کنند. اگر `InpDrawSilverBullet=false` کنی، باکس‌های SB از چارت می‌روند. مرز DST با `tools/Validate-TimeBase.ps1` تأیید شد (۰ ناسازگاری در ۲۰۲۴‑۲۰۲۸، و گذار مرزی تا ثانیه).
محدودیت باقی‌مانده: ردیف‌های جدید داشبورد و باکس‌های SB تا یک reload چارت تأییدنشده‌اند؛ و تحلیل تاریخی همیشه با آفست جاری انجام می‌شود (فاز ۱۵).

## فاز ۱۰ — Location و مدل ترید

**هدف:** Premium/Discount و OTE روی رنج واقعی؛ ستاپ صادق و بی‌خطر.

**کار:** #۴۳ Dealing Range از لگ واقعی · #۴۶ OTE از ریتریس لگ (۶۲ / ۷۰.۵ / ۷۹) · #۴۵ یک منبع واحد برای Location (حذف `SYMBOL_BID`) · #۴۸ امتیازدهی چندمعیاره DOL · #۶۶ ورود Sweep/MSS/Displacement به دروازهٔ READY، SL مبتنی بر ATR و `SYMBOL_TRADE_STOPS_LEVEL`، RR واقعی بر پایهٔ TP3/DOL.

**معیار پذیرش:** اعداد OTE با فیبوی دستی روی همان لگ بخواند؛ RR نمایش‌داده‌شده با فاصلهٔ واقعی ورود تا SL و TP3/DOL یکی باشد؛ SL هرگز صفر نباشد.
**ریسک:** بالا (بازطراحی منطق). **حالت پیشنهادی:** MAX

**وضعیت: ✅ پیاده‌سازی + build تأییدشده، سنجش runtime در انتظار یک reload — در مستندات فنی پروژه.**

| مورد | قبل | بعد |
|---|---|---|
| #۴۳ | آخرین سقف و آخرین کف تأییدشدهٔ مستقل (می‌توانستند دو لگ مختلف باشند) | `UpdateDealingLeg()`: پیوت‌های تأییدشدهٔ H4 + فیلتر تناوبی + دو پیوت آخر = لگ واقعی؛ جهت لگ از نوع پیوت پایان؛ کف اندازه `InpMinLegATR×ATR` |
| #۴۶ | `zoneMid` داخل باند ۶۲–۷۹٪ روی رنجی که لگ نبود | OTE از همان لگ (`0.62/0.705/0.79`) + نقطهٔ طلایی جدا + شرط «جهت لگ = جهت Bias» |
| #۴۵ | داشبورد از `SYMBOL_BID`، موتور از close کندل | `g_analysisClose` تنها منبع قیمت؛ EQ از EQ همان لگ |
| #۴۸ | External ۱۰۰ / HTF ۵۰ و `-dist` فقط tie-breaker؛ `sweepStateOk=true` هاردکد | امتیاز چندمعیاره با تفکیک عددی + رد سطوح با فضای کمتر از `InpDOL_MinRoomATR` + `sweepStateOk` از state واقعی سطح |
| #۶۶ | بی‌دروازه، SL = ۲۰ پوینت، RR = ورودی هاردکد | دروازهٔ چرخهٔ اثبات‌شده + SL با `max(ATR×ratio, points, StopsLevel)` + `rr = |TP3−entry|/|entry−SL|` واقعی + `InpMinRR` + ناحیهٔ M5 با `zoneSource` |

**تأییدنشده (نیازمند reload چارت):** اعداد نهایی لگ/OTE/SL/RR روی نماد واقعی، ردیف‌های جدید داشبورد (`Leg`, `DOL`, `R:R real`)، خط‌های `ICTv13_LOCATION_LEG` / `_GOLDEN` / `ICTv13_DOL_LINE` و فایل `ICT_Assistant_Canonical_Leg_Diag.csv`.
**ابزار سنجش:** `tools/Validate-DealingLeg.ps1` (فقط‌خواندنی) — همهٔ اعداد را از پیوت‌های خام بازمحاسبه و با مقادیر نوشته‌شده مقایسه می‌کند؛ خودآزمونش روی fixture درست (۲۰ PASS) و fixture غلط (۶ FAIL) انجام شد.

## فاز ۱۱ — موتور برگشت و Smart Money Reversal (قلب MMM)

**هدف:** توانایی اعلام نقطهٔ برگشت **تأییدشده** — نه هشدار ضعف.

**کار:** #۸ و #۷۱ خواندن واقعی Protected High/Low · ساخت رویداد `EXTERNAL_BREAK` روی H4 · تغذیهٔ `EXH_REVERSAL_CONFIRMED` از آن · #۷۰ پیاده‌سازی Smart Money Reversal · تضمین اینکه Exhaustion هرگز به‌تنهایی Bias را برنگرداند.

**معیار پذیرش:** در تست، برگشت فقط پس از بسته‌شدن فراتر از سطح محافظت‌شدهٔ خارجی اعلام شود؛ `REVERSAL_CONFIRMED` قابل‌تولید باشد؛ هیچ سناریویی با Exhaustion تنها Bias را flip نکند.
**ریسک:** بالا (معماری جدید). **حالت پیشنهادی:** MAX

**وضعیت: ✅ انجام شد (2026-09-16)** — در مستندات فنی پروژه.

| کار خواسته‌شده | شاهد |
|---|---|
| #۸ و #۷۱ خواندن واقعی Protected High/Low | `SwingById()` + `g_htfProtectedHighPrice`/`LowPrice`؛ تصویر لحظه‌ای **پیش از** `EvaluateStructureBreak` (چون آن تابع می‌تواند در همان کندل Bias و سطح را عوض کند) |
| ساخت رویداد `EXTERNAL_BREAK` روی H4 | `EVT_EXTERNAL_BREAK` (**انتهای enum** تا مقدار عددی رویدادهای موجود عوض نشود) + `RegisterExternalBreakEvent()` با dedup بر `StableEventId` |
| تغذیهٔ `EXH_REVERSAL_CONFIRMED` از آن | تنها تولیدکننده خط ۴۶۳۸ است، داخل شاخهٔ `reversalFresh` که به `g_reversal.confirmed` گره خورده |
| #۷۰ Smart Money Reversal | `ScoreSmartMoneyReversal()` — چهار شاهد عددی، آستانهٔ `InpSMR_MinScore`؛ در پنل فارسی صریحاً «تعریف عملیاتی این پروژه» برچسب خورده |
| تضمین عدم تغییر Bias با Exhaustion | در کل فایل **فقط یک** انتساب به `g_htfBias` وجود دارد (خط ۳۴۰، خط تعریف)؛ `UpdateExhaustion` هیچ انتسابی ندارد |

**build:** `0 errors, 0 warnings` · hash سه کپی `.mq5` برابر `4C7C35102894683F429441118634146A9242199DB3FE50939A72CE4F9F3F30F0` · `.ex5` موجود در پوشهٔ MT5 (۲۴۱۴۶۰ بایت، `18:16:03`) جدیدتر از سورس (`18:15:43`).
**ابزار سنجش:** `tools/Validate-ReversalGate.ps1` + سه fixture — نتیجهٔ `PASS=24 FAIL=0`.
**شاهد «قبل»:** `Explain.csv` پیش از فاز ۱۱ هیچ ردیفی با رشتهٔ `REVERSAL` ندارد (حالت مرده بود).
**تأییدنشده (نیازمند reload چارت):** `Reversal_Diag.csv`، ردیف داشبورد `Reversal:`، خط‌های `ICTv13_REVERSAL_GATE`/`_CONFIRMED` و تولید واقعی یک برگشت تأییدشده روی نماد.

## فاز ۱۲ — تکمیل SMC و MMM

**هدف:** پوشش کامل اجزای اعلام‌شدهٔ SMC/MMM.

**کار:** #۳۰ FVG Implied · #۳۱ FVG Micro · #۳۸ Mitigation Block مستقل · #۱۹ Trendline Liquidity · #۲۰ Range Liquidity · #۳۵ OB Extreme · #۳۶ تفکیک واقعی Core/Standalone · #۶۵ IPDA Reference Levels · #۴۷ رجیستری POI · #۶۸ امتیاز کیفیت و confluence · #۶۷ انتخاب Entry Model · #۳ و #۹ تفکیک واقعی Internal/External و سن روند.

**معیار پذیرش:** هر مفهوم جدید detection + زمان + TF مالک + شرط اعتبار + شرط invalidation + مسیر Explain داشته باشد.
**ریسک:** متوسط. **حالت پیشنهادی:** MAX

**وضعیت: ✅ انجام شد (2026-09-16) — در مستندات فنی پروژه.**

| مفهوم | detection | زمان | TF مالک | اعتبار | ابطال | Explain |
|---|---|---|---|---|---|---|
| #۳۰ FVG Implied | بدنهٔ کندل ۱↔۳ | کندل سوم | تایم‌فریم چارت | `causal` فقط با Displacement زنجیرشده | همان lifecycle گپ | ✅ |
| #۳۱ FVG Micro | گپ سه‌کندلی روی `InpMicroTF` | کندل Micro | `InpMicroTF` | کاملاً داخل محدودهٔ کندل Displacement + Displacement زنجیرشده | همان lifecycle گپ | ✅ |
| #۳۵ OB Extreme | نزدیک‌ترین ناحیه به اکسترمم لگ | کندل OB | تایم‌فریم چارت | فاصله ≤ `InpOB_ExtremeATR×ATR` | تغییر لگ | ✅ (POI) |
| #۳۶ Core/Standalone | `structureEventId==-1` | کندل OB | تایم‌فریم چارت | Core = مشارکت در شکست ساختار | پایان رجیستری | ✅ |
| #۳۸ Mitigation Block | شکست + پولاریتی + ریتست **بدون** Sweep | کندل ریتست | تایم‌فریم چارت | `liquidityEventId==-1` | زنجیره تمام می‌شود | ✅ |
| #۱۹ Trendline Liq | دو آنکر تأییدشدهٔ هم‌سمت | `t1..t2` + شیب | تایم‌فریم چارت | حداقل ۲ سویینگ روی خط | بسته‌شدن > خط + `InpTrendlineBreakATR×ATR` | ✅ |
| #۲۰ Range Liq | مرزهای رنج با برخورد کافی | زمان سویینگ | تایم‌فریم چارت | ارتفاع ≤ `InpRangeMaxATR×ATR` و `InpRangeMinTouches` در هر مرز | عبور بسته‌شده (lifecycle نقدینگی) | ✅ (POI) |
| #۶۵ IPDA | Old High/Low ۲۰/۴۰/۶۰ روزه | کندل روزانه | PERIOD_D1 | فقط با دادهٔ کامل افق، وگرنه ثبت نمی‌شود | عبور بسته‌شده | ✅ (POI) |
| #۴۷ POI | رجیستری یکپارچه با امتیاز عددی | زمان ناحیه | TF هر منبع | منبع در وضعیت معتبر | کهنگی از امتیاز کم می‌کند | ✅ |
| #۶۷ Entry Model | `SelectEntryModel()` با ۴ مدل | کندل تأیید | تایم‌فریم چارت | شرط عددی هر مدل | تغییر وضعیت ناحیه/چرخه | ✅ |
| #۶۸ Quality | ۱۰ معیار متغیر | کندل تأیید | — | `InpMinQualityScore` | کاهش کیفیت = بلاک READY | ✅ |
| #۳ / #۹ | `UpdateHtfInternalStructure` / `UpdateTrendPhase` | رویداد HTF | `InpHTF` | HH/HL یا LH/LL تأییدشده | تغییر Bias یا رویداد جدید | ✅ |

**build:** `0 errors, 0 warnings` · hash سه کپی `.mq5` برابر `0E42694AE9DB6AB4A79FD6D738C5BF787F51809AB28AF7513FFF32DE4582B8AF` · `.ex5` در پوشهٔ MT5 جدیدتر از سورس است (تأیید مستقل با مهر زمانی).
**ابزار سنجش:** `tools/Validate-Phase12.ps1` با ۹ fixture — نتیجهٔ `PASS=69 FAIL=0`.
**شاهد «قبل»:** `Explain.csv` پیش از فاز ۱۲ هیچ ردیفی با `IMPLIED`/`MICRO`/`MITIGATION`/`IPDA`/`TRENDLINE`/`POI` نداشت.
**تأییدنشده (نیازمند reload چارت):** اعداد واقعی ردیف‌های `Trend`/`Model`/`Quality`/`POI`، خط‌های `ICTv13_TRENDLINE_*` و `ICTv13_POI_BEST` و باکس POI.

## فاز ۱۳ — پایداری و کارایی

**هدف:** حذف رشد بی‌پایان، رویداد تکراری و کندی.

**کار:** #۷ رویداد تکراری HTF · #۱۱ سقف `g_events` و `g_displacements` · #۱۲ حذف `NewId()` مرده · کارایی rebuild · O(n²) در `DetectEQ_FromSwings` و `EventLedgerContains` · redraw در پایان rebuild · حذف بافر بی‌استفاده.

**معیار پذیرش:** زمان attach قابل قبول؛ هیچ BOS تکراری روی یک کندل H4؛ مصرف حافظه در اجرای طولانی کراندار.
**ریسک:** متوسط. **حالت پیشنهادی:** HIGH

**وضعیت: ✅ انجام شد (2026-09-16) — در مستندات فنی پروژه + `tools/Validate-Phase13.ps1`.**

**بندهای ۲‑H که در این فاز بسته شدند:**

| بند ۲‑H | نتیجه | شاهد |
|---|---|---|
| کارایی — rebuild | ✅ بسته | سرکوب رسم در بازسازی + بافر مشترک پنجره‌های سشن (`CollectWindowRange` دیگر صفر فراخوانی `Copy*` دارد) + memo تشخیص EQ + redraw پایان بازسازی. شاهد عددی real-time پس از reload: خط Journal «ICT PHASE13 \| rebuild» |
| کارایی — `EventLedgerContains` | ✅ بسته | ایندکس رم؛ اثبات سطح سورس: تابع جست‌وجو `FileOpen` ندارد و `LedgerIndexAdd` بعد از `FileWrite` صدا زده می‌شود |
| کارایی — `DetectEQ_FromSwings` | 🟡 جزئی | memo روی اثر انگشت سوئینگ‌ها (۲‑عملکرد حذف شد)؛ O(n²) بدترین حالت باقی است و تبدیل به مرتب‌سازی مجاز نیست |
| کارایی — rebuild بدون redraw | ✅ بسته | `RedrawChartObjects()` در پایان بازسازی؛ چون در بازسازی رسمی رخ نمی‌دهد، رسم دوباره ندارد |
| `g_bufDummy` | ✅ بسته | حذف بافر + `indicator_buffers 0` بدون warning |
| کارایی — `ExplainSaveCsv` | 🟡 عمداً دست‌نخورده | این CSV ابزار شاهد پروژه است؛ بهینه‌سازی آن می‌تواند شاهد را ضعیف کند و در فاز ۱۳ انجام نشد |
| **تاریخچهٔ نمایش با سقف رجیستری حذف می‌شود** | ✅ **بسته شد در فاز ۱۴** | redraw آشتی‌جویانه پیاده شد: `MarkDrawnLayerObj` + `ReconcileChartLayer` + سبک frozen کران‌دار (FIFO، `InpMaxFrozenObjects=300`). هیچ ناحیه‌ای دیگر با پر شدن سقف نمایش ناپدید نمی‌شود. شرح کامل در مستندات فنی پروژه |

**build:** `0 errors, 0 warnings` · hash سه کپی `.mq5` برابر `61E397FB6353A05FD964A55119336C9D075A9E1DB658C4A4B0B23CD810B1CE7A` (331302 بایت) · `.ex5` 296122 بایت · `19:34:42` · `8CCADE198B77493012DE0F098C013271E08B298F56DCCB19275406025E3A8A79`.
**ابزار سنجش:** `tools/Validate-Phase13.ps1` → `PASS=55 FAIL=0` (قاعدهٔ cadence + حساب سقف/حذف + idempotence تشخیص EQ + ۱۵ اثبات سطح سورس؛ شامل یک fixture غلط که باید رد شود و می‌شود).
**بدون رگرسیون:** `Validate-TimeBase` `0 mismatches` · `Validate-ReversalGate` `PASS=24 FAIL=0` · `Validate-Phase12` `PASS=77 FAIL=0` · `Validate-DealingLeg` `all checks passed` (پس از اصلاح ابزار).
**یافتهٔ جانبی:** ابزار `Validate-DealingLeg` (فاز ۱۰) ذاتاً قرمز بود — مقایسهٔ جهت با `BULL/BEAR` در حالی که CSV مقدار `BULLISH/BEARISH` می‌نویسد، تلورانس کوچک‌تر از دقت نوشتن، و فرمول ۶۲/۷۹ فقط برای لگ صعودی (روی لگ نزولی همیشه ~۴۱٪ انحراف). ابزار اصلاح شد؛ منطق کندل دست نخورد.
**تأییدنشده (نیازمند reload چارت):** زمان rebuild، شمارنده‌های `g_htfEvalSkips`/`g_winCacheReuses`/`g_eqSkips`/`g_eventsDropped` و نبود BOS تکراری روی یک کندل H4 در دادهٔ زنده.

## فاز ۱۴ — داشبورد و Explain  ✅ انجام‌شده (2026-09-17)

**هدف:** نمایش تمیز و بدون بریدگی، بدون کهنگی، **با حفظ رندر فارسی فعلی**.

**کار انجام‌شده:**

| مورد | قبل | بعد | شاهد |
|---|---|---|---|
| عرض/ارتفاع پس‌زمینه | هاردکد `380×640` با `lh=16`؛ با ۴۱ ردیف ممکن نیاز واقعی `656 px` ارتفاع و `~450 px` عرض بود | `DashEnd()` از بلندترین ردیف **اندازه‌گیری‌شده** (`TextSetFont`+`TextGetSize`) و تعداد ردیف مصرف‌شده می‌سازد | `phase14_dash_size.fixture.csv` + `dashsize(41 rows …)` در ابزار |
| ردیف بلند | در یک خط نشان داده می‌شد و بریده/روی‌هم می‌افتاد | شکستن در آخرین جداکنندهٔ جا‌شده وقتی `InpDashMaxWidth>40`؛ و اگر باز هم جا نشد، متن **بریده نمی‌شود**، عرض باز می‌شود و `g_dashOverflow` بالا می‌رود | `phase14_wrap.fixture.csv` + `overflow-is-counted-then-written-in-full` |
| برچسب کهنه | ۱۱ ردیف شرطی (`clocknote`/`sb`/`asia`/`mtfreason`/`dirline`/`entry`/`sl`/`tp1..tp3`/`rr`) مسیر حذف نداشتند؛ متن قدیمی می‌ماند و چون `row` جابه‌جا می‌شد ردیف‌های بعدی هم سرجای دیگری می‌نشستند | `DashBegin`/`DashRow`/`DashEnd`: هر برچسب `ICTv13_DASH_*` که در مجموعهٔ این pass نباشد حذف می‌شود (`g_dashStale`) | `phase14_stale_rows.fixture.csv` + `stale-label-sweep-present` |
| separator تکراری | `sep5` و `sep4` پشت‌سرهم | فقط `sep4` | `duplicate-separator-removed` |
| یک منبع واحد Location | در فاز ۱۰ بسته شد (`g_analysisClose` + `g_leg`) | بلا تغییر؛ در این فاز دوباره تأیید شد | `DashRow("location"…)` و `DashRow("leg"…)` هر دو از `g_leg` |
| hit-test کادر متن | در فاز ۶/۷ با `ChartTimePriceToXY` بسته شد | بلا تغییر | بلا تغییر |
| **تاریخچهٔ نمایش** (مورد 🔴 منتقل‌شده از فاز ۱۳) | `RedrawChartObjects` با ۱۴× `ObjectsDeleteAll` کل لایه را پاک می‌کرد؛ ناحیهٔ بیرون از `InpMaxDrawnZones=14` / `InpMaxDrawnLevels=30` **ناپدید** می‌شد | redraw آشتی‌جویانه: `MarkDrawnLayerObj` روی همهٔ ۱۳ مسیر ساخت آبجکت + `ReconcileChartLayer()` که زنده/حذف/frozen را تفکیک می‌کند؛ frozen کران‌دار با FIFO (`InpMaxFrozenObjects=300`) | `phase14_freeze_fifo.fixture.csv` + `redraw-no-longer-wipes-the-layer` + `every-layer-creation-marks-itself` |
| تفکیک «فیلتر کاربر» از «سقف نمایش» | نداشت | `LayerDisabledForName()` (لایهٔ خاموش = حذف)، `IsStaleSessionBoxName()` (باکس سشن با اندیس ≥ `InpKillzoneDaysBack` = حذف)، `MarkHiddenLayerObj()` (فیلتر صریح FVG = حذف) | `layer-toggles-delete-instead-of-freeze` · `stale-session-boxes-are-deleted` · `hidden-objects-are-deleted` |
| توضیح فارسی آبجکت frozen | — | `BuildExplanation` یک ردیف بالا‌ی پنل درج می‌کند که می‌گوید آبجکت معتبر است و رنگ خاکستری فقط نشانهٔ بیرون‌افتادن از پنجرهٔ نمایش است | `FROZEN HISTORY:` در `BuildExplanation` |
| پیام fallback پنل | «این یک باگ است» به‌عنوان تنها دلیل | دو دلیل صریح و متمایز: ناسازگاری شناسه **یا** بیرون‌رفتن از رجیستری کران‌دار (سقف‌های فاز ۱۳) که باگ نیست | متن fallback در `BuildExplanation` |
| ورودی‌های جدید | — | ۷ ورودی، همه در **انتهای** لیست (قانون ۱۴) تا اندیس تنظیمات ذخیره‌شدهٔ چارت‌ها جابه‌جا نشود | `phase14-inputs-are-appended` |

**ممنوع بود و رعایت شد:** تغییر حالت پیش‌فرض رندر (`InpExplainRenderMode=3`)، `RenderLine`/`HasPersianText`، و هر منطق تحلیل. تنها تغییری در لایهٔ Explain، درج یک ردیف **بالای** پنل برای آبجکت frozen است (بدون تغییر مسیر رندر).

**معیار پذیرش:** کد + ابزار ✅؛ `tools/Validate-Phase14.ps1` → `PASS=137 FAIL=0`؛ build `0 errors, 0 warnings`. ⬜ **screenshot هنوز نیامده** — فارسی باید همچنان درست خوانده شود و چک‌لیست چهاربندی «۴‑۰‑۱۳ بند ۶» روی چارت بسته شود.
**ریسک:** متوسط — بلا مانع. **وضعیت پایانی:** `IMPLEMENTED + BUILD VERIFIED + TOOL VERIFIED + SOURCE-PROVEN` (نه `VALIDATED`).

## فاز ۱۵ — اعتبارسنجی نهایی و release

**هدف:** بستن دروازه‌های شواهد.

**کار:** Full در برابر Incremental · Restart Determinism و immutability · آفست بروکر و DST تاریخی · بازتولید قفل MTF روی build جدید · تست رفتاری FVG/Sweep/OB/Breaker/Setup روی XAUUSD · پرکردن `05_TESTS_AND_VALIDATION/behavior/` با تست واقعی.

**معیار پذیرش:** همهٔ دروازه‌ها با داده و لاگ تازه بسته شوند؛ هیچ ادعای بی‌شاهد نماند؛ وضعیت `RELEASE-READY`.
**ریسک:** پایین. **حالت پیشنهادی:** HIGH
