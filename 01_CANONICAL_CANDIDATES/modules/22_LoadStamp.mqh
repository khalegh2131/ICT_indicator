//====================================================================
// فاز ۱۲ — مهر بارگذاری و دفتر شاهد عددی لایهٔ SMC/MMM
//====================================================================
// چرا مهر: بارها پیش آمد که «کدام build روی چارت فعال است؟» فقط با مقایسهٔ
// دستی زمان فایل‌ها حدس زده می‌شد و شاهد کهنه با شاهد تازه قاطی می‌شد.
// یک مهر کوچک در COMMON\Files این ابهام را برای همیشه برمی‌دارد.
void PersistLoadStamp()
{
   int h=FileOpen("ICT_Assistant_Canonical_Load.csv",FILE_COMMON|FILE_WRITE|FILE_CSV|FILE_UNICODE,';');
   if(h==INVALID_HANDLE) return;
   int nyHours=NyOffsetSecondsUTC(ServerToUTC(TimeCurrent()))/3600;
   FileWrite(h,"Key","Value");
   FileWrite(h,"BuildStamp",g_buildStamp);
   FileWrite(h,"Symbol",_Symbol);
   FileWrite(h,"ChartTF",EnumToString(PERIOD_CURRENT));
   FileWrite(h,"HTF",EnumToString(InpHTF));
   FileWrite(h,"SessionSourceTF",EnumToString(InpSessionSourceTF));
   FileWrite(h,"BrokerGMTOffsetMin",IntegerToString((int)(g_serverGMTOffsetSeconds/60)));
   FileWrite(h,"NYOffsetHours",IntegerToString(nyHours));
   FileWrite(h,"US_DSTforNYClock",InpUseUS_DSTForNYClock?"ON":"OFF");
   // فاز ۱۵
   FileWrite(h,"BrokerDSTRule",BrokerDSTRuleToStr(g_brokerDSTRule));
   FileWrite(h,"BrokerStdOffsetMin",IntegerToString((int)(g_brokerStdOffsetSeconds/60)));
   FileWrite(h,"HistoricalOffsetMode",InpUseHistoricalBrokerOffset?"HISTORICAL":"CURRENT");
   FileWrite(h,"TrackSetupLifecycle",InpTrackSetupLifecycle?"ON":"OFF");
   FileWrite(h,"DrawHTFEvents",InpDrawHTFEvents?"ON":"OFF");
   FileWrite(h,"Phase12",InpEnablePhase12?"ON":"OFF");
   FileWrite(h,"ReversalGate",InpEnableReversalGate?"ON":"OFF");
   FileWrite(h,"ProgramName",MQLInfoString(MQL_PROGRAM_NAME));
   FileWrite(h,"TerminalBuild",IntegerToString((int)TerminalInfoInteger(TERMINAL_BUILD)));
   FileClose(h);
}

// هر ردیف = یک کندل چارت، فقط وقتی کندل HTF یا وضعیت عوض شود. این فایل
// پرسش «لایهٔ فاز ۱۲ واقعاً چه چیزی تولید کرد؟» را با عدد جواب می‌دهد:
// چند خط مورب ساخته شد و چند بار لمس شدند، رنج معتبر بود یا با چه عددی رد
// شد، سطوح IPDA ثبت شد یا داده کافی نبود، چند گپ Implied/Micro، بهترین POI،
// مدل ورود، امتیاز کیفیت و سن/فاز روند.
void PersistPhase12Diagnostics(datetime barTime)
{
   if(!InpWriteReversalDiagnostics) return;
   int tlOk=0, tlInv=0, tlTouch=0, tlSwept=0;
   for(int i=0;i<ArraySize(g_trendlines);i++)
   {
      if(g_trendlines[i].swept) tlSwept++;
      if(g_trendlines[i].invalidated){ tlInv++; continue; }
      tlOk++; tlTouch+=g_trendlines[i].touches;
   }
   // فاز ۲۸: گپ‌هایی که Implied/Micro نیستند باید در همین شمارنده بیایند، وگرنه
   // نوع جدید Volume Imbalance بی‌صدا از شاهد حذف می‌شد و ستون کیفیت اشتباه می‌شد.
   int fImp=0, fMic=0, fExtra=0;
   for(int i=0;i<ArraySize(g_fvgs);i++)
   {
      if(g_fvgs[i].kind==FVGK_IMPLIED)              fImp++;
      else if(g_fvgs[i].kind==FVGK_MICRO)           fMic++;
      else if(g_fvgs[i].kind==FVGK_VOL_IMBALANCE)   fExtra++;
   }
   POIObj best;
   bool hasBest=FindBestPOI(DIR_NONE,best);

   string sig=TrendPhaseToStr(g_trend.phase)+"|"+g_reversal.state+"|"+IntegerToString(tlOk)
              +"|"+IntegerToString(tlSwept)
              +"|"+IntegerToString(fImp+fMic+fExtra)+"|"+(g_rangeOk?"1":"0")+"|"+(g_ipdaOk?"1":"0")
              +"|"+IntegerToString((int)g_setup.entryModel)+"|"+IntegerToString(g_setup.quality)
              +"|"+g_setup.status;
   static datetime lastBar=0;
   static string   lastSig="";
   if(barTime==lastBar && sig==lastSig) return;
   lastBar=barTime; lastSig=sig;

   int h=DiagOpen("ICT_Assistant_Canonical_Phase12_Diag.csv");
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0)
      FileWrite(h,"BarTime","BuildStamp","Bias","TrendAge","TrendPhase","InternalDir",
                "TrendlineOk","TrendlineInvalid","TrendlineTouches","TrendlineSwept","TrendlineBuilt","TrendlineReject",
                "RangeOk","RangeHigh","RangeLow","RangeHighTouches","RangeLowTouches","RangeReject",
                "IPDAOk","IPDANote","ImpliedFVG","MicroFVG",
                "POICount","BestPOIKind","BestPOIScore",
                "EntryModel","ModelReason","Quality","QualityMin","SetupStatus");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,
             TimeToString(barTime,TIME_DATE|TIME_MINUTES),
             g_buildStamp,
             DirToStr(g_htfBias),
             g_trend.ageBars,
             TrendPhaseToStr(g_trend.phase),
             DirToStr(g_htfInternalDir),
             tlOk, tlInv, tlTouch, tlSwept,
             g_trendlineBuilt?"true":"false",
             g_trendlineReject,
             g_rangeOk?"true":"false",
             DoubleToString(g_rangeHigh,_Digits),
             DoubleToString(g_rangeLow,_Digits),
             g_rangeHighTouches, g_rangeLowTouches,
             g_rangeReject,
             g_ipdaOk?"true":"false",
             g_ipdaNote,
             fImp, fMic,
             ArraySize(g_poi),
             hasBest? PoiKindToStr(best.kind) : "NONE",
             hasBest? best.score : 0,
             EntryModelToStr(g_setup.entryModel),
             g_setup.modelReason,
             g_setup.quality,
             InpMinQualityScore,
             g_setup.status);
   DiagClose(h);
}

