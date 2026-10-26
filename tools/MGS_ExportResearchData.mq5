// Read-only research export. No trading operations. MT5 compilation UNVERIFIED.
#property copyright "Independent demo research"
#property version "1.000"
#property strict
#property script_show_inputs

input string InpSymbol="GOLD";
input string InpConversionSymbol="GBPUSD";
input datetime InpFrom=D'2026.05.22 00:00:00';
input datetime InpTo=D'2026.10.16 00:00:00'; // EXCLUSIVE, broker timestamp

// Pure validation shared with host tests. Times are broker timestamps, with no
// inferred UTC offset. MqlRates native integer fields cannot contain NaN.
bool IsValidResearchBar(MqlRates &bar,datetime from,datetime to,datetime last)
{
   if(from>=to || bar.time<=0 || bar.time<from || bar.time>=to || bar.time<=last)
      return false;
   if(!MathIsValidNumber(bar.open) || !MathIsValidNumber(bar.high) ||
      !MathIsValidNumber(bar.low) || !MathIsValidNumber(bar.close) ||
      bar.open<=0.0 || bar.high<=0.0 || bar.low<=0.0 || bar.close<=0.0)
      return false;
   return bar.low<=bar.high && bar.low<=MathMin(bar.open,bar.close) &&
          MathMax(bar.open,bar.close)<=bar.high && bar.tick_volume>=0 &&
          bar.spread>=0 && bar.real_volume>=0;
}

int NewResearchCSV(string filename)
{
   // The folder is unique; never truncate a file left by any earlier export.
   if(FileIsExist(filename))
   {
      Print("EXPORT INCOMPLETE: refusing to overwrite ",filename);
      return INVALID_HANDLE;
   }
   ResetLastError();
   int handle=FileOpen(filename,FILE_WRITE|FILE_CSV|FILE_ANSI,',',CP_UTF8);
   if(handle==INVALID_HANDLE)
      Print("EXPORT INCOMPLETE: FileOpen ",filename," error=",GetLastError());
   return handle;
}

bool FlushResearchCSV(int handle)
{
   if(handle==INVALID_HANDLE) return false;
   ResetLastError();
   FileFlush(handle);
   int error=GetLastError();
   if(error!=0) Print("EXPORT INCOMPLETE: FileFlush error=",error);
   return error==0;
}

bool ResearchMetadata(int handle,string key,string value)
{
   ResetLastError();
   uint bytes=FileWrite(handle,key,value);
   int error=GetLastError();
   if(bytes==0 || error!=0)
      Print("EXPORT INCOMPLETE: metadata write error=",error);
   return bytes>0 && error==0;
}

double ResearchSymbolDouble(string symbol,ENUM_SYMBOL_INFO_DOUBLE property,bool &ok)
{
   double value=0.0;
   ResetLastError();
   if(!SymbolInfoDouble(symbol,property,value) || !MathIsValidNumber(value))
   {
      Print("EXPORT INCOMPLETE: symbol double ",symbol," ",EnumToString(property),
            " error=",GetLastError());
      ok=false;
   }
   return value;
}

long ResearchSymbolInteger(string symbol,ENUM_SYMBOL_INFO_INTEGER property,bool &ok)
{
   long value=0;
   ResetLastError();
   if(!SymbolInfoInteger(symbol,property,value))
   {
      Print("EXPORT INCOMPLETE: symbol integer ",symbol," ",EnumToString(property),
            " error=",GetLastError());
      ok=false;
   }
   return value;
}

string ResearchSymbolString(string symbol,ENUM_SYMBOL_INFO_STRING property,bool &ok)
{
   string value="";
   ResetLastError();
   if(!SymbolInfoString(symbol,property,value))
   {
      Print("EXPORT INCOMPLETE: symbol string ",symbol," ",EnumToString(property),
            " error=",GetLastError());
      ok=false;
   }
   return value;
}

bool WriteResearchSpecs(int handle,string symbol)
{
   ResetLastError();
   bool ok=SymbolSelect(symbol,true);
   if(!ok)
      Print("EXPORT INCOMPLETE: symbol unavailable ",symbol," error=",GetLastError());
   double contract=ResearchSymbolDouble(symbol,SYMBOL_TRADE_CONTRACT_SIZE,ok);
   double tick=ResearchSymbolDouble(symbol,SYMBOL_TRADE_TICK_SIZE,ok);
   double point=ResearchSymbolDouble(symbol,SYMBOL_POINT,ok);
   long digits=ResearchSymbolInteger(symbol,SYMBOL_DIGITS,ok);
   double minimum=ResearchSymbolDouble(symbol,SYMBOL_VOLUME_MIN,ok);
   double maximum=ResearchSymbolDouble(symbol,SYMBOL_VOLUME_MAX,ok);
   double step=ResearchSymbolDouble(symbol,SYMBOL_VOLUME_STEP,ok);
   double tickProfit=ResearchSymbolDouble(symbol,SYMBOL_TRADE_TICK_VALUE_PROFIT,ok);
   double tickLoss=ResearchSymbolDouble(symbol,SYMBOL_TRADE_TICK_VALUE_LOSS,ok);
   string profit=ResearchSymbolString(symbol,SYMBOL_CURRENCY_PROFIT,ok);
   string margin=ResearchSymbolString(symbol,SYMBOL_CURRENCY_MARGIN,ok);
   long stops=ResearchSymbolInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL,ok);
   long freeze=ResearchSymbolInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL,ok);
   long execution=ResearchSymbolInteger(symbol,SYMBOL_TRADE_EXEMODE,ok);
   long calculation=ResearchSymbolInteger(symbol,SYMBOL_TRADE_CALC_MODE,ok);
   if(contract<=0 || tick<=0 || point<=0 || digits<0 || minimum<=0 ||
      maximum<minimum || step<=0 || tickProfit<0 || tickLoss<0 ||
      profit=="" || margin=="" || stops<0 || freeze<0) ok=false;
   ResetLastError();
   uint bytes=FileWrite(handle,symbol,DoubleToString(contract,10),
      DoubleToString(tick,10),DoubleToString(point,10),digits,
      DoubleToString(minimum,8),DoubleToString(maximum,8),DoubleToString(step,8),
      DoubleToString(tickProfit,10),DoubleToString(tickLoss,10),profit,margin,
      stops,freeze,execution,calculation,ok?"READ_OK":"INCOMPLETE");
   if(bytes==0 || GetLastError()!=0) return false;
   return ok;
}

bool WriteResearchChunk(int handle,string symbol,datetime from,datetime to,
                        int copied,long written,long invalid,datetime first,
                        datetime last,int error,int attempts,string status)
{
   ResetLastError();
   uint bytes=FileWrite(handle,symbol,
      TimeToString(from,TIME_DATE|TIME_SECONDS),TimeToString(to,TIME_DATE|TIME_SECONDS),
      copied,written,invalid,first>0?TimeToString(first,TIME_DATE|TIME_SECONDS):"",
      last>0?TimeToString(last,TIME_DATE|TIME_SECONDS):"",error,attempts,status);
   return bytes>0 && GetLastError()==0;
}

bool ExportResearchBars(int handle,int chunks,string symbol,long &rows,int &emptyChunks)
{
   rows=0;
   ResetLastError();
   if(!SymbolSelect(symbol,true))
   {
      int error=GetLastError();
      Print("EXPORT INCOMPLETE: cannot select ",symbol," error=",error);
      WriteResearchChunk(chunks,symbol,InpFrom,InpTo,-1,0,0,0,0,error,0,"SYMBOL_UNAVAILABLE");
      return false;
   }
   long digits=0;
   if(!SymbolInfoInteger(symbol,SYMBOL_DIGITS,digits) || digits<0 || digits>16)
   {
      Print("EXPORT INCOMPLETE: unavailable/unsupported quote precision ",symbol);
      return false;
   }
   bool ok=true;
   datetime last=0;
   const int chunkSeconds=7*86400;
   for(datetime from=InpFrom;from<InpTo;)
   {
      datetime to=(datetime)MathMin((double)InpTo,(double)from+chunkSeconds);
      if(IsStopped())
      {
         WriteResearchChunk(chunks,symbol,from,to,-1,0,0,0,0,0,0,"STOPPED");
         return false;
      }
      MqlRates rates[];
      ArraySetAsSeries(rates,false); // oldest physical record first
      datetime through=(datetime)(to-1); // explicitly select the date-range overload
      int copied=-1,error=0,attempts=0;
      // No unbounded synchronization wait: initial attempt plus two retries.
      for(int attempt=0;attempt<3;attempt++)
      {
         attempts++;
         ResetLastError();
         copied=CopyRates(symbol,PERIOD_M1,from,through,rates);
         error=GetLastError();
         if(copied>=0 || IsStopped()) break;
         if(attempt<2) Sleep(1000);
      }
      long written=0,invalid=0;
      datetime first=0,chunkLast=0;
      string status="EXPORTED_COVERAGE_UNVERIFIED";
      bool writeOK=true;
      if(copied<0 || error!=0)
      {
         ok=false;
         status="COPY_ERROR";
         Print("EXPORT INCOMPLETE: CopyRates ",symbol," ",TimeToString(from),
               "..",TimeToString(to)," count=",copied," error=",error);
      }
      if(copied==0)
      {
         emptyChunks++;
         if(error==0) status="EMPTY_UNDETERMINED";
      }
      for(int i=0;i<copied;i++)
      {
         if(IsStopped()) { ok=false; status="STOPPED"; break; }
         if(!IsValidResearchBar(rates[i],from,to,last))
         {
            invalid++;
            ok=false;
            status="INVALID_BARS";
            continue; // invalid records are never written to the data CSV
         }
         ResetLastError();
         uint bytes=FileWrite(handle,
            TimeToString(rates[i].time,TIME_DATE|TIME_SECONDS),(long)rates[i].time,
            DoubleToString(rates[i].open,(int)digits),DoubleToString(rates[i].high,(int)digits),
            DoubleToString(rates[i].low,(int)digits),DoubleToString(rates[i].close,(int)digits),
            rates[i].tick_volume,rates[i].spread,rates[i].real_volume);
         int ioError=GetLastError();
         if(bytes==0 || ioError!=0)
         {
            Print("EXPORT INCOMPLETE: bar write ",symbol," error=",ioError);
            ok=false; writeOK=false; status="WRITE_ERROR"; break;
         }
         written++; rows++;
         last=rates[i].time; chunkLast=last;
         if(first==0) first=last;
      }
      if(!FlushResearchCSV(handle)) { ok=false; writeOK=false; status="FLUSH_ERROR"; }
      if(!WriteResearchChunk(chunks,symbol,from,to,copied,written,invalid,
                              first,chunkLast,error,attempts,status) || !FlushResearchCSV(chunks))
      {
         Print("EXPORT INCOMPLETE: chunk manifest write/flush failure.");
         return false;
      }
      if(!writeOK || IsStopped()) return false;
      from=to;
   }
   return ok;
}

void OnStart()
{
   if(InpSymbol=="" || InpConversionSymbol=="" || InpSymbol==InpConversionSymbol ||
      InpFrom<=0 || InpTo<=InpFrom)
   {
      Print("EXPORT INCOMPLETE: supply two distinct symbols and a valid broker-time interval.");
      return;
   }
   string folder="MGS_Research_"+(string)(long)TimeLocal()+"_"+(string)GetTickCount64();
   ResetLastError();
   if(!FolderCreate(folder))
   {
      Print("EXPORT INCOMPLETE: cannot create unique folder ",folder," error=",GetLastError());
      return;
   }
   // Fixed filenames remain safe even when broker symbols contain a suffix or slash.
   int metadata=NewResearchCSV(folder+"\\metadata.csv");
   int specs=NewResearchCSV(folder+"\\specs.csv");
   int chunks=NewResearchCSV(folder+"\\chunks.csv");
   int gold=NewResearchCSV(folder+"\\GOLD_M1.csv");
   int conversion=NewResearchCSV(folder+"\\GBPUSD_M1.csv");
   bool ok=(metadata!=INVALID_HANDLE && specs!=INVALID_HANDLE && chunks!=INVALID_HANDLE &&
            gold!=INVALID_HANDLE && conversion!=INVALID_HANDLE);
   // Preserve a readable INCOMPLETE metadata file even if another file failed
   // to open. This does not overwrite any prior export.
   bool metadataHeaderOK=false;
   if(metadata!=INVALID_HANDLE)
   {
      ResetLastError();
      uint bytes=FileWrite(metadata,"key","value");
      metadataHeaderOK=(bytes>0 && GetLastError()==0);
   }
   ok=ok && metadataHeaderOK;
   long goldRows=0,conversionRows=0;
   int emptyChunks=0;
   if(ok)
   {
      ok=(FileWrite(specs,"symbol","contract_size","tick_size","point","digits", "volume_min",
             "volume_max","volume_step","tick_value_profit","tick_value_loss","profit_currency",
             "margin_currency","stops_level_points","freeze_level_points","execution_mode_code",
             "trade_calculation_mode_code","read_status")>0 &&
          FileWrite(chunks,"symbol","from_inclusive_broker_time","to_exclusive_broker_time",
             "copied_rows","written_rows","invalid_rows","first_written_broker_time",
             "last_written_broker_time","copy_error","attempts","status")>0 &&
          FileWrite(gold,"broker_time_no_offset","broker_time_seconds","open","high","low","close",
             "tick_volume","spread_points","real_volume")>0 &&
          FileWrite(conversion,"broker_time_no_offset","broker_time_seconds","open","high","low","close",
             "tick_volume","spread_points","real_volume")>0);
   }
   if(ok)
   {
      bool metaOK=true;
      if(!ResearchMetadata(metadata,"exporter_version","1.000_UNCOMPILED_IN_CLOUD")) metaOK=false;
      if(!ResearchMetadata(metadata,"purpose","DEVELOPMENT_RESEARCH_DATA_NOT_EXECUTION_BACKTEST")) metaOK=false;
      if(!ResearchMetadata(metadata,"broker_company",AccountInfoString(ACCOUNT_COMPANY))) metaOK=false;
      if(!ResearchMetadata(metadata,"broker_server",AccountInfoString(ACCOUNT_SERVER))) metaOK=false;
      if(!ResearchMetadata(metadata,"account_currency",AccountInfoString(ACCOUNT_CURRENCY))) metaOK=false;
      if(!ResearchMetadata(metadata,"account_leverage",(string)AccountInfoInteger(ACCOUNT_LEVERAGE))) metaOK=false;
      if(!ResearchMetadata(metadata,"export_started_local_clock",TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS))) metaOK=false;
      if(!ResearchMetadata(metadata,"from_inclusive_broker_time",TimeToString(InpFrom,TIME_DATE|TIME_SECONDS))) metaOK=false;
      if(!ResearchMetadata(metadata,"to_exclusive_broker_time",TimeToString(InpTo,TIME_DATE|TIME_SECONDS))) metaOK=false;
      if(!ResearchMetadata(metadata,"GOLD_M1.csv_symbol",InpSymbol)) metaOK=false;
      if(!ResearchMetadata(metadata,"GBPUSD_M1.csv_symbol",InpConversionSymbol)) metaOK=false;
      if(!ResearchMetadata(metadata,"time_semantics","BROKER_CLOCK;NO_UTC_OFFSET_INFERRED;DST_MAPPING_REQUIRED")) metaOK=false;
      if(!ResearchMetadata(metadata,"spread_semantics","M1_BAR_SPREAD_POINTS_NOT_FULL_BID_ASK_PATH")) metaOK=false;
      if(!ResearchMetadata(metadata,"tick_value_semantics","CURRENT_ACCOUNT_CURRENCY_SNAPSHOT_NOT_HISTORICAL")) metaOK=false;
      if(!ResearchMetadata(metadata,"coverage_semantics","RECORD_VALIDITY_ONLY;GAPS_AND_MARKET_SESSIONS_REQUIRE_SEPARATE_REVIEW")) metaOK=false;
      bool goldSpecsOK=WriteResearchSpecs(specs,InpSymbol);
      bool conversionSpecsOK=WriteResearchSpecs(specs,InpConversionSymbol);
      bool specsFlushed=FlushResearchCSV(specs);
      bool goldOK=ExportResearchBars(gold,chunks,InpSymbol,goldRows,emptyChunks);
      bool conversionOK=false;
      if(!IsStopped()) conversionOK=ExportResearchBars(conversion,chunks,InpConversionSymbol,conversionRows,emptyChunks);
      ok=(metaOK && goldSpecsOK && conversionSpecsOK && specsFlushed && goldOK && conversionOK && !IsStopped());
   }
   if(goldRows==0 || conversionRows==0) emptyChunks++;
   string status=(!ok?"INCOMPLETE":(emptyChunks>0?"COVERAGE_UNDETERMINED":"EXPORTED_COVERAGE_UNVERIFIED"));
   if(metadata!=INVALID_HANDLE)
   {
      bool finalOK=true;
      if(!ResearchMetadata(metadata,"GOLD_M1_rows",(string)goldRows)) finalOK=false;
      if(!ResearchMetadata(metadata,"GBPUSD_M1_rows",(string)conversionRows)) finalOK=false;
      if(!ResearchMetadata(metadata,"empty_or_missing_data_flags",(string)emptyChunks)) finalOK=false;
      if(!ResearchMetadata(metadata,"status",status)) finalOK=false;
      if(!FlushResearchCSV(metadata)) finalOK=false;
      if(!finalOK) status="INCOMPLETE";
   }
   if(gold!=INVALID_HANDLE) FileClose(gold);
   if(conversion!=INVALID_HANDLE) FileClose(conversion);
   if(chunks!=INVALID_HANDLE) FileClose(chunks);
   if(specs!=INVALID_HANDLE) FileClose(specs);
   if(metadata!=INVALID_HANDLE) FileClose(metadata);
   Print("RESEARCH EXPORT ",status," | MQL5/Files/",folder,
         " | GOLD_M1 rows=",goldRows," | GBPUSD_M1 rows=",conversionRows,
         " | coverage flags=",emptyChunks,
         " | OHLC/spread snapshots only; no executable trading result.");
}
