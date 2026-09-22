//====================================================================
// TIME BASE — آفست واقعی بروکر و ساعت نیویورک (DST-aware).
// قاعده: هیچ محاسبه Context نباید به TimeCurrent وابسته باشد؛ همه چیز
// بر مبنای زمان کندلِ در حال تحلیل است تا بازپخش/تاریخ قابل اثبات بماند.
//====================================================================
int DayOfWeekOf(int year, int month, int day)
{
   MqlDateTime dt;
   dt.year=year; dt.mon=month; dt.day=day; dt.hour=12; dt.min=0; dt.sec=0;
   MqlDateTime out; TimeToStruct(StructToTime(dt), out);
   return out.day_of_week;   // 0 = Sunday
}

int NthSundayOfMonth(int year, int month, int nth)
{
   int firstDow    = DayOfWeekOf(year, month, 1);
   int firstSunday = 1 + ((7 - firstDow) % 7);
   return firstSunday + (nth-1)*7;
}

// ---- قاعدهٔ DST آمریکا: دقیق تا ثانیه، بر مبنای UTC (رفع #۵۶) ----
// عبور از ساعت تابستانی در آمریکا:
//   شروع: دومین یکشنبهٔ مارس، ساعت ۰۲:۰۰ EST  = ۰۷:۰۰ UTC
//   پایان: اولین یکشنبهٔ نوامبر، ساعت ۰۲:۰۰ EDT = ۰۱:۰۰ EST = ۰۶:۰۰ UTC
// نسخهٔ قبلی با «روز شروع» مقایسه می‌کرد و کل آن روز را غیر‌DST می‌گرفت؛
// نتیجه تا ۳ ساعت خطا در مرز سالانه بود. این نسخه از خود لحظهٔ UTC استفاده می‌کند.
datetime UTCBoundFor(int year, int month, int nthSunday, int hour, int minute)
{
   MqlDateTime d;
   d.year=year; d.mon=month; d.day=NthSundayOfMonth(year,month,nthSunday);
   d.hour=hour; d.min=minute; d.sec=0;
   return StructToTime(d);
}

// قاعدهٔ خالص آمریکا (مستقل از ورودی ساعت نیویورک؛ برای قاعدهٔ DST بروکر لازم است)
bool US_IsDST_UTC(datetime utcT)
{
   MqlDateTime d; TimeToStruct(utcT,d);
   if(d.mon<3 || d.mon>11) return false;
   datetime startU=UTCBoundFor(d.year,3,2,7,0);
   datetime endU  =UTCBoundFor(d.year,11,1,6,0);
   return (utcT>=startU && utcT<endU);
}

bool NY_IsDST_UTC(datetime utcT)
{
   if(!InpUseUS_DSTForNYClock) return false;
   return US_IsDST_UTC(utcT);
}

