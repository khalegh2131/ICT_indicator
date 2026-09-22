//====================================================================
// DRAWING
//====================================================================
string EventReasonText(const StructureEvent &e)
{
   string reason = EventTypeToStr(e.type);
   reason += " | TF=" + EnumToString(e.isHTF?InpHTF:PERIOD_CURRENT);
   reason += " | closed-bar confirmation (shift " + IntegerToString(e.confirmationBarShift) + ")";
   if(e.sweepId!=-1)         reason += " | sweep #" + IdToStr(e.sweepId);
   if(e.displacementId!=-1)  reason += " | displacement #" + IdToStr(e.displacementId);
   if(e.brokenSwingId!=-1)   reason += " | broke swing #" + IdToStr(e.brokenSwingId);
   if(e.protectedSwingId!=-1) reason += " | protected opposite #" + IdToStr(e.protectedSwingId);
   if(e.type==EVT_MSS)        reason += " | causal: sweep + displacement";
   else if(e.type==EVT_CHOCH) reason += " | CHoCH without displacement (candidate)";
   else                       reason += " | continuation break";
   return reason;
}

// فاز ۱۵: نام کوتاه تایم‌فریم برای برچسب روی چارت (PERIOD_H4 → H4)
string TFShortName(ENUM_TIMEFRAMES tf)
{
   string s=EnumToString(tf);
   StringReplace(s,"PERIOD_","");
   return s;
}

void DrawStructureEvent(const StructureEvent &e)
{
   string name = "ICTv13_EVT_"+IdToStr(e.id);
   ObjectCreate(0,name,OBJ_TEXT,0,e.time,e.price);
   // فاز ۱۵: روی برچسب HTF، مالک تایم‌فریم صریح نوشته می‌شود تا با رویداد
   // همان تایم‌فریم چارت قاطی نشود.
   string evtTxt = EventTypeToStr(e.type)+(e.direction==DIR_BULL?" ↑":" ↓");
   if(e.isHTF) evtTxt = TFShortName(InpHTF)+" "+evtTxt;
   ObjectSetString(0,name,OBJPROP_TEXT, evtTxt);
   ObjectSetInteger(0,name,OBJPROP_COLOR, e.direction==DIR_BULL?InpColorBull:InpColorBear);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE, e.isHTF? 10 : 9);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,"\n");
   MarkDrawnLayerObj(name);

   // مرز ساختاری شکسته‌شده: خط افقی روی سطح، با دلیل کامل
   string lineName = "ICTv13_EVTL_"+IdToStr(e.id);
   datetime lineEnd = e.time + PeriodSeconds(e.isHTF? InpHTF : PERIOD_CURRENT)*10;
   if(ObjectFind(0,lineName)<0) ObjectCreate(0,lineName,OBJ_TREND,0,e.time,e.price,lineEnd,e.price);
   ObjectSetInteger(0,lineName,OBJPROP_TIME,0,e.time);
   ObjectSetDouble(0,lineName,OBJPROP_PRICE,0,e.price);
   ObjectSetInteger(0,lineName,OBJPROP_TIME,1,lineEnd);
   ObjectSetDouble(0,lineName,OBJPROP_PRICE,1,e.price);
   ObjectSetInteger(0,lineName,OBJPROP_COLOR, e.direction==DIR_BULL?InpColorBull:InpColorBear);
   ObjectSetInteger(0,lineName,OBJPROP_STYLE,STYLE_DASH);
   ObjectSetInteger(0,lineName,OBJPROP_WIDTH,1);
   ObjectSetString(0,lineName,OBJPROP_TOOLTIP,"\n");
   MarkDrawnLayerObj(lineName);
}

void DrawFVG(const FVGObj &f)
{
   // فاز ۴۳: رنگ از **نقش فعلی** گرفته می‌شود، نه از جهت تولد. برای گپ وارونه،
   // نقش مخالف تولد است و رنگ اختصاصی وارونگی (بنفش) در پایین رویش می‌نشیند؛
   // ولی برای گپ سالم، رنگ دقیقاً همان چیزی است که پنل و CSV هم می‌گویند —
   // پیش‌تر اینجا قبل از وارونگی سبز/قرمزِ تولد رسم می‌شد و مربع بنفش با ردیف
   // CSV متناقض می‌شد.
   color clr = FVGActiveDir(f)==DIR_BULL?InpColorBull:InpColorBear;
   string stateTxt = "FRESH imbalance";
   if(!f.causal)        { clr=PAL_STATE_NOCAUSAL; stateTxt="imbalance without causal displacement"; }
   if(f.mitigated)      { clr=PAL_STATE_MITIGATED; stateTxt="touched (mitigated) - not fresh anymore"; }
   if(f.inverted)       { clr=PAL_FVG_INVERTED;  stateTxt="iFVG: closed through, polarity inverted"; }
   if(f.invalidated)    { clr=PAL_STATE_INVALID; stateTxt="expired/invalid"; }

   string name = "ICTv13_FVG_"+IdToStr(f.id);
   datetime t2 = f.time + PeriodSeconds()*InpZoneExtendBars;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE,0,f.time,f.top,t2,f.bottom);
   ObjectSetInteger(0,name,OBJPROP_TIME,0,f.time);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,f.top);
   ObjectSetInteger(0,name,OBJPROP_TIME,1,t2);
   ObjectSetDouble(0,name,OBJPROP_PRICE,1,f.bottom);
   ObjectSetInteger(0,name,OBJPROP_COLOR, clr);
   ObjectSetInteger(0,name,OBJPROP_FILL,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,"\n");
   MarkDrawnLayerObj(name);

   // CE (Consequent Encroachment) = میانهٔ ناحیه
   string ceName = "ICTv13_FVGCE_"+IdToStr(f.id);
   double ce = (f.top+f.bottom)/2.0;
   datetime ceEnd = f.time + PeriodSeconds()*InpZoneExtendBars;
   if(ObjectFind(0,ceName)<0) ObjectCreate(0,ceName,OBJ_TREND,0,f.time,ce,ceEnd,ce);
   ObjectSetInteger(0,ceName,OBJPROP_TIME,0,f.time);
   ObjectSetDouble(0,ceName,OBJPROP_PRICE,0,ce);
   ObjectSetInteger(0,ceName,OBJPROP_TIME,1,ceEnd);
   ObjectSetDouble(0,ceName,OBJPROP_PRICE,1,ce);
   ObjectSetInteger(0,ceName,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,ceName,OBJPROP_STYLE,STYLE_DOT);
   ObjectSetInteger(0,ceName,OBJPROP_WIDTH,1);
   ObjectSetString(0,ceName,OBJPROP_TOOLTIP,"\n");
   MarkDrawnLayerObj(ceName);
}

void DrawOB(const OBObj &o)
{
   color clr = o.direction==DIR_BULL?PAL_OB_BULL:PAL_OB_BEAR;
   // فاز ۳۶: External OB ضخیم‌تر (مبدأ لگ)؛ Internal نازک‌تر — تمایز بصری بدون شلوغی
   int lineWidth = (o.scope==SCOPE_EXTERNAL)? 3 : 2;
   string stateTxt = "VALID (unmitigated)";
   if(o.state==OB_MITIGATED) { clr=PAL_STATE_MITIGATED; stateTxt="MITIGATED (touched)"; }
   if(o.state==OB_BROKEN)    { clr=PAL_STATE_BROKEN;    stateTxt="BROKEN (structural violation)"; }
   if(o.state==OB_BREAKER)   { clr=PAL_OB_BREAKER;      stateTxt="BREAKER (retested after polarity flip)"; }
   if(o.state==OB_INVALID)   { clr=PAL_STATE_INVALID;   stateTxt="INVALID (no displacement/structure link)"; }

   string name = "ICTv13_OB_"+IdToStr(o.id);
   datetime t2 = o.time + PeriodSeconds()*InpZoneExtendBars;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE,0,o.time,o.top,t2,o.bottom);
   ObjectSetInteger(0,name,OBJPROP_TIME,0,o.time);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,o.top);
   ObjectSetInteger(0,name,OBJPROP_TIME,1,t2);
   ObjectSetDouble(0,name,OBJPROP_PRICE,1,o.bottom);
   ObjectSetInteger(0,name,OBJPROP_COLOR, clr);
   ObjectSetInteger(0,name,OBJPROP_FILL,false);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,lineWidth);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,"\n");
   MarkDrawnLayerObj(name);
}

void DrawRejection(const RejectionObj &r)
{
   // Rejection باطل‌شده رسم نمی‌شود (فیلتر در DrawZoneLayer هم اعمال شده؛
   // این شرط دفاعی دوم است تا با هر مسیر رسمی چیزی از گذشته فیلدشده نماند).
   if(InpHideInvalidatedObjects && r.rejectionState==REJECTION_INVALID) return;
   color clr = r.direction==DIR_BULL?PAL_REJ_BULL:PAL_REJ_BEAR;
   if(r.rejectionState==REJECTION_TOUCHED) clr=PAL_STATE_MITIGATED;
   if(r.rejectionState==REJECTION_INVALID) clr=PAL_STATE_INVALID;
   string name="ICTv13_REJECTION_"+IdToStr(r.id);
   datetime t2=r.time+PeriodSeconds()*InpZoneExtendBars;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE,0,r.time,r.top,t2,r.bottom);
   ObjectSetInteger(0,name,OBJPROP_TIME,0,r.time);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,r.top);
   ObjectSetInteger(0,name,OBJPROP_TIME,1,t2);
   ObjectSetDouble(0,name,OBJPROP_PRICE,1,r.bottom);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DOT);
   ObjectSetInteger(0,name,OBJPROP_FILL,false);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,"\n");
   MarkDrawnLayerObj(name);
}

void DrawLocationLine(const string label, const double price, const color lineColor, const string tooltip)
{
   if(price<=0.0) return;
   string name="ICTv13_LOCATION_"+label;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_HLINE,0,0,price);
   ObjectSetDouble(0,name,OBJPROP_PRICE,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,lineColor);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DASHDOT);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,"\n");
   MarkDrawnLayerObj(name);
}

void DrawLocationLevels()
{
   if(!g_leg.valid) return;
   double range=g_leg.range;
   double eq=g_leg.eq;
   double oteLow=0.0, oteHigh=0.0, golden=0.0;
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
   DrawLocationLine("EQ",eq,PAL_LOC_EQ,"");
   DrawLocationLine("OTE_LOW",oteLow,PAL_LOC_OTE,"");
   DrawLocationLine("OTE_HIGH",oteHigh,PAL_LOC_OTE,"");
   DrawLocationLine("GOLDEN",golden,PAL_LOC_GOLDEN,"");

   // خودِ لگ: خط بین پیوت آغاز و پیوت پایان — همان دو نقطه‌ای که کاربر
   // می‌تواند فیبوی دستی را روی آن بگذارد (#۴۳/#۴۶).
   string legName="ICTv13_LOCATION_LEG";
   if(ObjectFind(0,legName)<0) ObjectCreate(0,legName,OBJ_TREND,0,g_leg.startTime,g_leg.startPrice,g_leg.endTime,g_leg.endPrice);
   ObjectSetInteger(0,legName,OBJPROP_TIME,0,g_leg.startTime);
   ObjectSetDouble(0,legName,OBJPROP_PRICE,0,g_leg.startPrice);
   ObjectSetInteger(0,legName,OBJPROP_TIME,1,g_leg.endTime);
   ObjectSetDouble(0,legName,OBJPROP_PRICE,1,g_leg.endPrice);
   ObjectSetInteger(0,legName,OBJPROP_COLOR, g_leg.dir==DIR_BULL?InpColorBull:InpColorBear);
   ObjectSetInteger(0,legName,OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,legName,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,legName,OBJPROP_RAY_RIGHT,false);
   ObjectSetString(0,legName,OBJPROP_TOOLTIP,"\n");
   MarkDrawnLayerObj(legName);

   // فاز ۳۶: برچسب Price Delivery — لگ معامله‌گری با برچسب «Delivering به سمت کدام نقدینگی».
   // این همان زبان MMM/ICT است: قیمت همیشه از یک نقدینگی به نقدینگی دیگر «تحویل» می‌شود؛
   // برچسب جدا محاسبهٔ تازه ندارد: لگ همان محاسبه است و DOL هدفش.
   string pdName="ICTv13_LOCATION_PDLBL";
   string pdTxt=(g_leg.dir==DIR_BULL)?"Delivering UP → " : "Delivering DOWN → ";
   pdTxt += (g_hasDOL? StringFormat("DOL %.2f",g_currentDOL.price) : "هدف نقدینگی در انتظار");
   DrawTextObj(pdName, g_leg.endTime, g_leg.endPrice, pdTxt,
               g_leg.dir==DIR_BULL?InpColorBull:InpColorBear, 8,
               // Phase 42: the Latin label opens the tooltip, the rest is pure Persian.
               "PRICE DELIVERY | لگ فعال از "+TimeToString(g_leg.startTime,TIME_DATE|TIME_MINUTES)+
               " تا "+TimeToString(g_leg.endTime,TIME_DATE|TIME_MINUTES)+
               " | بازگشت به تعادل میانهٔ لگ یا ناحیهٔ ورود بهینه یعنی فرصت ورود هم‌جهت؛ نیمهٔ گران و ارزان لگ را از همان میانه بخوان");
}

// خط DOL: هدف واقعی معامله؛ روی hover توضیح عددی می‌دهد (مستقل از اعتبار لگ)
void DrawDOLLine()
{
   if(!InpDrawDOL) return;               // هدف روی چارت اختیاری است (در داشبورد هست)
   if(!g_hasDOL) return;
   string dolName="ICTv13_DOL_LINE";
   if(ObjectFind(0,dolName)<0) ObjectCreate(0,dolName,OBJ_HLINE,0,0,g_currentDOL.price);
   ObjectSetDouble(0,dolName,OBJPROP_PRICE,g_currentDOL.price);
   ObjectSetInteger(0,dolName,OBJPROP_COLOR,PAL_DOL);
   ObjectSetInteger(0,dolName,OBJPROP_STYLE,STYLE_DASHDOT);
   ObjectSetInteger(0,dolName,OBJPROP_WIDTH,2);
   ObjectSetString(0,dolName,OBJPROP_TOOLTIP,"\n");
   MarkDrawnLayerObj(dolName);
}

//====================================================================
// CHART OBJECT LAYER — نمایش واقعی همه‌چیز روی چارت
// یک‌بار در هر کندل بسته از روی Registryها بازسازی می‌شود (نه هر تیک)
// تا چارت هیچ‌وقت با State ناهمگام نشود.
//====================================================================
string LiqTypeLabel(ENUM_LIQ_TYPE t)
{
   switch(t)
   {
      case LIQ_PDH:       return "PDH (previous day high)";
      case LIQ_PDL:       return "PDL (previous day low)";
      case LIQ_PWH:       return "PWH (previous week high)";
      case LIQ_PWL:       return "PWL (previous week low)";
      case LIQ_EQH:       return "EQH (equal highs - liquidity pool)";
      case LIQ_EQL:       return "EQL (equal lows - liquidity pool)";
      case LIQ_SWING_H:   return "Swing High (BSL)";
      case LIQ_SWING_L:   return "Swing Low (SSL)";
      case LIQ_SESSION_H: return "Session High (BSL)";
      case LIQ_SESSION_L: return "Session Low (SSL)";
      // فاز ۱۲
      case LIQ_RANGE_H:   return "Range High (range liquidity, BSL)";
      case LIQ_RANGE_L:   return "Range Low (range liquidity, SSL)";
      case LIQ_IPDA20_H:  return "IPDA 20-day Old High";
      case LIQ_IPDA20_L:  return "IPDA 20-day Old Low";
      case LIQ_IPDA40_H:  return "IPDA 40-day Old High";
      case LIQ_IPDA40_L:  return "IPDA 40-day Old Low";
      case LIQ_IPDA60_H:  return "IPDA 60-day Old High";
      case LIQ_IPDA60_L:  return "IPDA 60-day Old Low";
   }
   return "Liquidity";
}

