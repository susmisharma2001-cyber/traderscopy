//+------------------------------------------------------------------+
//|                                              PulseCopyBridge.mq5 |
//|                                  Copyright 2024, PulseCopy Ltd.  |
//|                                             https://pulsecopy.io |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PulseCopy Ltd."
#property link      "https://pulsecopy.io"
#property version   "5.00"
#property strict

#define GITHUB_RAW_HOST "https://raw.githubusercontent.com"
#define GITHUB_SIGNALS_PATH "%s/main/trades.json"

//--- Input parameters
input string   InpProjectID     = "devi698/webtrade";     // GitHub repo path (owner/repo)
input string   InpBrokerServer  = "VantageMarkets-Demo";  // Broker server label for logs
input string   InpAccountNumber = "25449835";            // MT5 account number
input double   InpMaxLot        = 5.0;                     // Safety limit
input uint     InpPollSeconds   = 5;                       // Poll interval in seconds

//--- Global variables
string       lastProcessedId = "";
string       signalUrl = "";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("PulseCopy: Initializing Multi-Account Bridge v5.0...");
   Print("PulseCopy: Project ID = ", InpProjectID);
   Print("PulseCopy: Broker Server = ", InpBrokerServer);
   Print("PulseCopy: Monitoring signals for Account #", InpAccountNumber);

   if(StringLen(InpProjectID) == 0 || InpProjectID == "REPLACE_WITH_YOUR_GIT_PROJECT_ID")
     {
      Alert("PulseCopy Error: You MUST set your Project ID in the input settings!");
      return(INIT_FAILED);
     }

   if(StringLen(InpAccountNumber) == 0)
     {
      Alert("PulseCopy Error: You MUST set your account number in the input settings!");
      return(INIT_FAILED);
     }

   signalUrl = StringFormat("%s/" GITHUB_SIGNALS_PATH, GITHUB_RAW_HOST, InpProjectID);
   Print("PulseCopy: Signal URL = ", signalUrl);

   EventSetTimer(InpPollSeconds);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
  }

string TrimString(string value)
  {
   int start = 0;
   int end = StringLen(value) - 1;
   while(start <= end)
     {
      int ch = StringGetCharacter(value, start);
      if(ch == ' ' || ch == '\r' || ch == '\n' || ch == '\t')
         start++;
      else
         break;
     }
   while(end >= start)
     {
      int ch = StringGetCharacter(value, end);
      if(ch == ' ' || ch == '\r' || ch == '\n' || ch == '\t')
         end--;
      else
         break;
     }
   if(start == 0 && end == StringLen(value) - 1)
      return(value);
   if(end < start)
      return("");
   return(StringSubstr(value, start, end - start + 1));
  }

string ToUpper(string text)
  {
   string result = "";
   int length = StringLen(text);
   for(int i = 0; i < length; i++)
     {
      int ch = StringGetCharacter(text, i);
      if(ch >= 'a' && ch <= 'z')
         ch -= ('a' - 'A');
      result = result + CharToString(ch);
     }
   return(result);
  }

string NormalizeSymbol(string symbol)
  {
   symbol = ToUpper(TrimString(symbol));
   if(StringLen(symbol) == 0)
      return("");

   if(SymbolSelect(symbol, true))
      return(symbol);

   int total = SymbolsTotal(false);
   for(int i = 0; i < total; i++)
     {
      string candidate = ToUpper(SymbolName(i, false));
      if(StringLen(candidate) == 0)
         continue;

      if(candidate == symbol)
         return(candidate);
      if(StringFind(candidate, symbol) == 0)
         return(candidate);
      if(StringFind(candidate, symbol) == StringLen(candidate) - StringLen(symbol))
         return(candidate);
     }

   return(symbol);
  }

string NormalizeAction(string action)
  {
   action = ToUpper(TrimString(action));
   if(action == "BUY" || action == "SELL")
      return(action);
   if(action == "LONG")
      return("BUY");
   if(action == "SHORT")
      return("SELL");
   if(StringLen(action) > 0)
     {
      int ch = StringGetCharacter(action, 0);
      if(ch == 'B')
         return("BUY");
      if(ch == 'S')
         return("SELL");
     }
   return(action);
  }

//+------------------------------------------------------------------+
//| Fetch raw JSON from GitHub                                       |
//+------------------------------------------------------------------+
bool FetchSignals(string &json)
  {
   uchar data[];
   uchar result[];
   string headers;

   Print("DEBUG: FetchSignals() called");
   ArrayFree(data);
   ArrayFree(result);
   Print("DEBUG: Arrays cleared");

   string url = signalUrl + "?cb=" + (string)(TimeCurrent());
   Print("DEBUG: URL constructed: ", url);
   Print("PulseCopy: requesting URL ", url);
   
   Print("DEBUG: About to call WebRequest...");
   int res = WebRequest("GET", url, "Content-Type: application/json\r\n", 10000, data, result, headers);
   Print("DEBUG: WebRequest returned with code: ", res);
   Print("PulseCopy: WebRequest result=", res, " headers=", headers);

   if(res != 200)
     {
      Print("PulseCopy: WebRequest failed with code ", res, " - returning false");
      return(false);
     }

   Print("DEBUG: Converting result array to string...");
   ArrayResize(result, ArraySize(result) + 1);
   result[ArraySize(result) - 1] = 0;
   json = CharArrayToString(result, 0, WHOLE_ARRAY);
   Print("DEBUG: Conversion complete, json length=", StringLen(json));
   
   if(StringLen(json) == 0)
     {
      Print("PulseCopy: response is empty");
      return(false);
     }

   Print("PulseCopy: fetched signal JSON length=", StringLen(json));
   return(true);
  }

//+------------------------------------------------------------------+
//| JSON helpers                                                     |
//+------------------------------------------------------------------+
string JsonGetRawValue(const string json, const string key, int startPos=0)
  {
   string search = key + ":";
   int pos = StringFind(json, search, startPos);
   if(pos < 0)
     {
      Print("DEBUG JsonGetRawValue: Could not find '", search, "' starting from pos ", startPos);
      return("");
     }

   Print("DEBUG JsonGetRawValue: Found '", search, "' at position ", pos);

   int valueStart = pos + StringLen(search);
   while(valueStart < StringLen(json) &&
         (StringGetCharacter(json, valueStart) == ' ' ||
          StringGetCharacter(json, valueStart) == '\r' ||
          StringGetCharacter(json, valueStart) == '\n' ||
          StringGetCharacter(json, valueStart) == '\t'))
      valueStart++;

   if(valueStart >= StringLen(json))
     {
      Print("DEBUG JsonGetRawValue: valueStart beyond EOF");
      return("");
     }

   int firstChar = StringGetCharacter(json, valueStart);
   Print("DEBUG JsonGetRawValue: First char after whitespace: ", (char)firstChar, " (code=", firstChar, ")");

   if(firstChar == '"')
     {
      valueStart++;
      int valueEnd = StringFind(json, "\"", valueStart);
      if(valueEnd < 0)
        {
         Print("DEBUG JsonGetRawValue: No closing quote found");
         return("");
        }
      string result = StringSubstr(json, valueStart, valueEnd - valueStart);
      Print("DEBUG JsonGetRawValue: Extracted quoted value: '", result, "'");
      return(result);
     }

   int valueEnd = valueStart;
   while(valueEnd < StringLen(json))
     {
      int ch = StringGetCharacter(json, valueEnd);
      if(ch == ',' || ch == '}' || ch == ']' || ch == ' ' || ch == '\r' || ch == '\n' || ch == '\t')
         break;
      valueEnd++;
     }
   string result = StringSubstr(json, valueStart, valueEnd - valueStart);
   Print("DEBUG JsonGetRawValue: Extracted unquoted value: '", result, "'");
   return(result);
  }

string JsonGetString(const string json, const string key, int startPos=0)
  {
   return(JsonGetRawValue(json, key, startPos));
  }

double JsonGetDouble(const string json, const string key, int startPos=0)
  {
   string text = JsonGetRawValue(json, key, startPos);
   return(StringLen(text) > 0 ? StringToDouble(text) : 0.0);
  }

int FindNextOpenSignal(const string response)
  {
   int currentPos = 0;
   int matchCount = 0;
   int samplesPrinted = 0;
   
   while(true)
     {
      int accountPos = StringFind(response, "account", currentPos);
      if(accountPos < 0)
        {
         Print("DEBUG: No more 'account' keys found. Total matches checked: ", matchCount);
         return(-1);
        }

      // Show context around where "account" was found (for first few matches)
      if(samplesPrinted < 3)
        {
         int contextStart = MathMax(0, accountPos - 50);
         int contextLen = MathMin(150, StringLen(response) - contextStart);
         string context = StringSubstr(response, contextStart, contextLen);
         Print("DEBUG: Context around match #", matchCount, ": ", context);
         samplesPrinted++;
        }

      string accountValue = JsonGetRawValue(response, "account", accountPos);
      Print("DEBUG: Found account value: '", accountValue, "' (len=", StringLen(accountValue), ")");
      matchCount++;
      
      if(StringLen(accountValue) == 0)
        {
         Print("DEBUG: Account value is empty, skipping. Trying next match.");
         currentPos = accountPos + 10;
         continue;
        }

      Print("DEBUG: Comparing '", accountValue, "' == '", InpAccountNumber, "'");
      if(accountValue == InpAccountNumber)
        {
         Print("DEBUG: ACCOUNT MATCHED!");
         int objectEnd = StringFind(response, "}", accountPos);
         if(objectEnd < 0)
           {
            Print("DEBUG: Could not find end of object");
            return(-1);
           }

         int statusPos = StringFind(response, "status", accountPos);
         if(statusPos >= 0 && statusPos < objectEnd)
           {
            string current_id = JsonGetString(response, "id", accountPos);
            Print("DEBUG: Signal ID: '", current_id, "'");
            if(StringLen(current_id) == 0)
               current_id = StringFormat("%s%s%s", JsonGetString(response, "symbol", accountPos), JsonGetString(response, "type", accountPos), InpAccountNumber);

            if(StringLen(current_id) == 0 || current_id != lastProcessedId)
               return(accountPos);
           }
        }
      else
        {
         Print("DEBUG: No match, trying next account");
        }
      currentPos = accountPos + 10;
     }
   return(-1);
  }

//+------------------------------------------------------------------+
//| Execute BUY order (without CTrade library)                       |
//+------------------------------------------------------------------+
bool ExecuteBuy(string symbol, double lot, double sl, double tp)
  {
   Print("DEBUG: ExecuteBuy called for symbol=", symbol, " lot=", lot);
   
   MqlTradeRequest request;
   MqlTradeResult result;

   request.action = TRADE_ACTION_DEAL;
   request.symbol = symbol;
   request.volume = lot;
   request.type = ORDER_TYPE_BUY;
   request.price = SymbolInfoDouble(symbol, SYMBOL_ASK);
   request.sl = sl;
   request.tp = tp;
   request.deviation = 10;
   request.magic = 20240602;
   request.comment = "PulseCopy BUY";

   if(OrderSend(request, result))
     {
      Print("PulseCopy: BUY Order sent successfully! Deal #", result.deal, " Order #", result.order);
      return(true);
     }
   else
     {
      Print("PulseCopy: BUY Order failed! Retcode=", result.retcode, " Error=", GetLastError());
      return(false);
     }
  }

//+------------------------------------------------------------------+
//| Execute SELL order (without CTrade library)                      |
//+------------------------------------------------------------------+
bool ExecuteSell(string symbol, double lot, double sl, double tp)
  {
   Print("DEBUG: ExecuteSell called for symbol=", symbol, " lot=", lot);
   
   MqlTradeRequest request;
   MqlTradeResult result;

   request.action = TRADE_ACTION_DEAL;
   request.symbol = symbol;
   request.volume = lot;
   request.type = ORDER_TYPE_SELL;
   request.price = SymbolInfoDouble(symbol, SYMBOL_BID);
   request.sl = sl;
   request.tp = tp;
   request.deviation = 10;
   request.magic = 20240602;
   request.comment = "PulseCopy SELL";

   if(OrderSend(request, result))
     {
      Print("PulseCopy: SELL Order sent successfully! Deal #", result.deal, " Order #", result.order);
      return(true);
     }
   else
     {
      Print("PulseCopy: SELL Order failed! Retcode=", result.retcode, " Error=", GetLastError());
      return(false);
     }
  }

//+------------------------------------------------------------------+
//| Timer function to poll for trades                                |
//+------------------------------------------------------------------+
void OnTimer()
  {
   Print("PulseCopy: OnTimer triggered");

   string response;
   Print("DEBUG: Calling FetchSignals()...");
   if(!FetchSignals(response))
     {
      Print("DEBUG: FetchSignals() returned false");
      return;
     }

   Print("DEBUG: FetchSignals() succeeded, response length=", StringLen(response));
   
   // Print first 500 chars of JSON to see structure
   if(StringLen(response) > 0)
     {
      int sampleLen = MathMin(500, StringLen(response));
      string jsonSample = StringSubstr(response, 0, sampleLen);
      Print("DEBUG: JSON sample (first ", sampleLen, " chars): ", jsonSample);
     }
   
   Print("DEBUG: Calling FindNextOpenSignal()...");
   int signalPos = FindNextOpenSignal(response);
   Print("DEBUG: FindNextOpenSignal returned signalPos=", signalPos);
   
   if(signalPos < 0)
     {
      Print("DEBUG: No signal found (signalPos < 0)");
      return;
     }

   string symbol = JsonGetString(response, "symbol", signalPos);
   string action = JsonGetString(response, "type", signalPos);
   if(StringLen(action) == 0)
      action = JsonGetString(response, "action", signalPos);

   Print("DEBUG: Raw symbol=", symbol, " action=", action);
   symbol = NormalizeSymbol(symbol);
   action = NormalizeAction(action);
   Print("PulseCopy: normalized symbol=", symbol, " action=", action);

   double lot = JsonGetDouble(response, "lot", signalPos);
   if(lot <= 0.0) lot = JsonGetDouble(response, "volume", signalPos);
   if(lot <= 0.0) lot = 0.01;
   if(lot > InpMaxLot) lot = InpMaxLot;

   double stop_loss = JsonGetDouble(response, "stop_loss", signalPos);
   double take_profit = JsonGetDouble(response, "take_profit", signalPos);

   string current_id = JsonGetString(response, "id", signalPos);
   if(StringLen(current_id) == 0)
      current_id = StringFormat("%s%s%s", symbol, action, InpAccountNumber);

   Print("DEBUG: current_id=", current_id, " lastProcessedId=", lastProcessedId);
   if(StringLen(current_id) == 0 || current_id == lastProcessedId)
     {
      Print("DEBUG: Signal already processed or empty ID");
      return;
     }

   if(StringLen(symbol) == 0 || StringLen(action) == 0)
     {
      Print("PulseCopy: Invalid trade signal payload.");
      return;
     }

   if(!SymbolSelect(symbol, true))
     {
      Print("PulseCopy: Symbol not available in Market Watch: ", symbol);
      return;
     }

   double askPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bidPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
   if(askPrice <= 0.0 || bidPrice <= 0.0)
     {
      Print("PulseCopy: Price unavailable for symbol ", symbol);
      return;
     }

   Print("PulseCopy: NEW SIGNAL DETECTED FOR ACC #", InpAccountNumber);
   PrintFormat("PulseCopy: EXECUTING %s %s LOT=%G SL=%G TP=%G", action, symbol, lot, stop_loss, take_profit);

   bool orderSent = false;
   if(action == "BUY")
      orderSent = ExecuteBuy(symbol, lot, stop_loss, take_profit);
   else if(action == "SELL")
      orderSent = ExecuteSell(symbol, lot, stop_loss, take_profit);
   else
      Print("PulseCopy: Unknown action ", action);

   if(orderSent)
     {
      Print("PulseCopy: Order sent successfully for ", symbol, " account #", InpAccountNumber);
      lastProcessedId = current_id;
     }
   else
     {
      Print("PulseCopy: Order failed for ", symbol, " error=", GetLastError());
     }
  }
