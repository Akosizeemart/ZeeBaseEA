//+------------------------------------------------------------------+
//|                                              ZeeBaseEA.mq5 |
//|                           Zee — Universal MQL5 EA Base Template  |
//|                                                                  |
//|  Includes:                                                       |
//|   • IsNewBar()          — multi-TF new-bar detection             |
//|   • HasOpenPosition()   — hedging-safe position check            |
//|   • CloseAllPositions() — close all matching positions           |
//|   • GetSpread()         — spread guard helper                    |
//|   • CalculateLot()      — fixed-lot OR % equity sizing           |
//|   • OpenTrade()         — buy/sell with SL & TP                  |
//|   • TrailSL()           — stub for trailing-stop logic           |
//|   • OnTick skeleton     — new-bar gated, spread-checked          |
//+------------------------------------------------------------------+
#property copyright "Zee"
#property version   "1.00"
#property strict
#property description "Universal MQL5 EA baseline. Copy, rename, and build on top."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//===================================================================
//  ENUMERATIONS
//===================================================================

enum ENUM_RISK_MODE
  {
   RISK_FIXED_LOT     = 0,  // Fixed lot size
   RISK_PERCENT_EQUITY       // % of equity per trade
  };

//===================================================================
//  INPUTS
//===================================================================

input group "=== Identification ==="
input long   InpMagicNumber   = 100001;        // Magic number
input string InpTradeComment  = "ZeeBase";     // Trade comment

input group "=== Timeframes ==="
input ENUM_TIMEFRAMES InpSignalTF = PERIOD_H1; // Signal / new-bar timeframe

input group "=== Risk Management ==="
input ENUM_RISK_MODE  InpRiskMode    = RISK_PERCENT_EQUITY; // Sizing mode
input double          InpFixedLot    = 0.10;   // Fixed lot (RISK_FIXED_LOT)
input double          InpRiskPercent = 1.0;    // Risk % of equity (RISK_PERCENT_EQUITY)
input double          InpMaxLot      = 5.0;    // Hard-cap lot size

input group "=== Stop Loss / Take Profit ==="
input int    InpSL_Points      = 200;          // Stop Loss in points
input int    InpTP_Points      = 400;          // Take Profit in points
input int    InpMinStopPoints  = 50;           // Minimum SL distance (points)
input int    InpSL_BufferPoints= 30;           // Extra SL buffer beyond level (points)

input group "=== Trade Management ==="
input bool   InpOneTradeOnly   = true;         // Allow only one open position
input int    InpMaxSpreadPoints= 300;          // Max spread gate (points)
input int    InpSlippagePoints = 20;           // Order slippage tolerance (points)

input group "=== News Filter ==="
input bool   InpUseNewsFilter     = true;      // Block trading around high-impact USD news
input int    InpNewsMinutesBefore = 30;        // Minutes before news: stop trading
input int    InpNewsMinutesAfter  = 30;        // Minutes after news: resume trading

input group "=== Visuals ==="
input bool   InpShowComment    = true;         // Show info block on chart

//===================================================================
//  GLOBALS
//===================================================================

CTrade        trade;
CPositionInfo posInfo;
CSymbolInfo   symInfo;

//--- Cached symbol constants
double g_point      = 0.0;
int    g_digits     = 0;
long   g_stopsLevel = 0;
double g_tickValue  = 0.0;
double g_tickSize   = 0.0;
double g_lotStep    = 0.0;
double g_minLot     = 0.0;
double g_maxLot     = 0.0;

bool   g_isTester        = false;
bool   g_isOptimization  = false;


int OnInit()
  {
   //--- Symbol info
   if(!symInfo.Name(_Symbol))
     {
      Print("ERR: symInfo.Name() failed for ", _Symbol);
      return INIT_FAILED;
     }

   //--- Trade object setup
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);

   //--- Environment flags
   g_isTester       = (bool)MQLInfoInteger(MQL_TESTER);
   g_isOptimization = (bool)MQLInfoInteger(MQL_OPTIMIZATION);

   //--- Cache symbol constants (avoids repeated broker calls inside OnTick)
   g_point      = symInfo.Point();
   g_digits     = symInfo.Digits();
   g_stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   g_tickValue  = SymbolInfoDouble (_Symbol, SYMBOL_TRADE_TICK_VALUE);
   g_tickSize   = SymbolInfoDouble (_Symbol, SYMBOL_TRADE_TICK_SIZE);
   g_lotStep    = symInfo.LotsStep();
   g_minLot     = symInfo.LotsMin();
   g_maxLot     = MathMin(symInfo.LotsMax(), InpMaxLot);

   //--- TODO: create indicator handles here
   // handleXXX = iRSI(_Symbol, InpSignalTF, 14, PRICE_CLOSE);
   // if(handleXXX == INVALID_HANDLE) return INIT_FAILED;

   if(InpShowComment) Comment("");
   Print("ZeeBaseTemplate: initialised on ", _Symbol, " / ", EnumToString(InpSignalTF));
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   //--- TODO: release indicator handles here
   // if(handleXXX != INVALID_HANDLE) IndicatorRelease(handleXXX);

   Comment("");
  }

//===================================================================
//  MAIN LOOP
//===================================================================

void OnTick()
  {
  
  int highest = iHighest(_Symbol,PERIOD_CURRENT,MODE_HIGH,20,0);
  double hih = iHigh(_Symbol,PERIOD_CURRENT,highest);
  Print(highest);
   //--- Always-on tick work (trails, BE moves, TP updates, etc.)
   if(symInfo.RefreshRates())
     {
      TrailSL();       // ← implement as needed
     }

   //--- Gate everything below to new-bar only
   if(!IsNewBar(InpSignalTF))
      return;

   if(!symInfo.RefreshRates())
      return;

   //--- Spread guard
   if(GetSpread() > InpMaxSpreadPoints)
     {
      if(InpShowComment) Comment("Spread too wide — waiting");
      return;
     }

   //--- One-trade guard
   if(InpOneTradeOnly && HasOpenPosition())
      return;

   //--- News filter (high-impact USD)
   if(IsHighImpactUSDNewsTime())
     {
      if(InpShowComment) Comment("High-impact USD news window — no trading");
      return;
     }

   //--- TODO: read indicator values here
   // double rsi;
   // if(!GetRSI(handleXXX, 1, rsi)) return;

   //--- TODO: define your entry conditions
   bool buySignal  = false; // replace with real logic
   bool sellSignal = false; // replace with real logic

   //--- Execute
   if(buySignal)
      OpenTrade(ORDER_TYPE_BUY);
   else if(sellSignal)
      OpenTrade(ORDER_TYPE_SELL);

   //--- Chart comment
   if(InpShowComment)
      Comment(StringFormat(
         "=== %s | %s | Magic %I64d ===\n"
         "Buy: %s   Sell: %s\n"
         "Spread: %d pts",
         _Symbol, EnumToString(InpSignalTF), InpMagicNumber,
         (buySignal  ? "YES" : "no"),
         (sellSignal ? "YES" : "no"),
         GetSpread()
      ));
  }

//--------------------------------------------------------------------
//  IsNewBar — returns true exactly once per new bar on the given TF
//--------------------------------------------------------------------
bool IsNewBar(const ENUM_TIMEFRAMES tf)
  {
   static datetime s_prevTime = 0;
   datetime curTime = iTime(_Symbol, tf, 0);
   if(curTime != s_prevTime)
     {
      s_prevTime = curTime;
      return true;
     }
   return false;
  }

//--------------------------------------------------------------------
//  GetSpread — returns current spread in points (integer)
//--------------------------------------------------------------------
int GetSpread()
  {
   return (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
  }

//--------------------------------------------------------------------
//  IsHighImpactUSDNewsTime — true if now is inside the no-trade window
//  around any high-impact USD calendar event.
//  Window: [event - InpNewsMinutesBefore, event + InpNewsMinutesAfter].
//--------------------------------------------------------------------
bool IsHighImpactUSDNewsTime()
  {
   if(!InpUseNewsFilter) return false;

   datetime now      = TimeTradeServer();
   long     beforeS  = (long)InpNewsMinutesBefore * 60;
   long     afterS   = (long)InpNewsMinutesAfter  * 60;
   datetime fromTime = (datetime)((long)now - afterS);   // events whose "after" window still covers now
   datetime toTime   = (datetime)((long)now + beforeS);  // upcoming events whose "before" window starts now

   MqlCalendarValue values[];
   int count = CalendarValueHistory(values, fromTime, toTime, NULL, "USD");
   if(count <= 0) return false;

   for(int i = 0; i < count; i++)
     {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev)) continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH)  continue;

      datetime evTime    = values[i].time;
      datetime blockFrom = (datetime)((long)evTime - beforeS);
      datetime blockTo   = (datetime)((long)evTime + afterS);
      if(now >= blockFrom && now <= blockTo) return true;
     }
   return false;
  }

//--------------------------------------------------------------------
//  HasOpenPosition — true if a position exists for this EA's magic
//  Handles both netting and hedging account modes correctly.
//--------------------------------------------------------------------
bool HasOpenPosition()
  {
   //--- Fast path for netting accounts
   if(PositionSelect(_Symbol))
      if((long)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         return true;

   //--- Full scan required for hedging accounts
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)
      == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
        {
         if(!posInfo.SelectByIndex(i)) continue;
         if(posInfo.Symbol() == _Symbol &&
            (long)posInfo.Magic() == InpMagicNumber)
            return true;
        }
     }
   return false;
  }

//--------------------------------------------------------------------
//  CloseAllPositions — closes every position for this EA on _Symbol
//  Pass direction filter: POSITION_TYPE_BUY, POSITION_TYPE_SELL,
//  or -1 to close all.
//--------------------------------------------------------------------
void CloseAllPositions(const int directionFilter = -1)
  {
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      if(!posInfo.SelectByIndex(i))  continue;
      if(posInfo.Symbol()  != _Symbol)          continue;
      if((long)posInfo.Magic() != InpMagicNumber) continue;

      if(directionFilter != -1 &&
         (int)posInfo.PositionType() != directionFilter)
         continue;

      bool ok = trade.PositionClose(posInfo.Ticket(), InpSlippagePoints);
      if(!ok)
         PrintFormat("CloseAllPositions: failed ticket=%I64u err=%d",
                     posInfo.Ticket(), GetLastError());
      else
         PrintFormat("CloseAllPositions: closed ticket=%I64u %s @ %.5f",
                     posInfo.Ticket(),
                     (posInfo.PositionType() == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                     posInfo.PriceCurrent());
     }
  }

//--------------------------------------------------------------------
//  CalculateLot — fixed lot or % equity risk based on SL distance
//  slDistance: price distance from entry to stop (in price units)
//--------------------------------------------------------------------
double CalculateLot(const double slDistance)
  {
   double lots = InpFixedLot;

   if(InpRiskMode == RISK_PERCENT_EQUITY)
     {
      if(g_tickValue <= 0.0 || g_tickSize <= 0.0 || slDistance <= 0.0)
         return 0.0;

      double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
      double riskMoney = equity * (InpRiskPercent / 100.0);

      double moneyPerLotPerPrice = g_tickValue / g_tickSize;
      double lossPerLot          = slDistance * moneyPerLotPerPrice;
      if(lossPerLot <= 0.0) return 0.0;

      lots = riskMoney / lossPerLot;
     }

   //--- Normalise to broker lot step
   if(g_lotStep > 0.0)
      lots = MathFloor(lots / g_lotStep) * g_lotStep;

   lots = MathMax(g_minLot, MathMin(g_maxLot, lots));

   int stepDigits = (g_lotStep >= 1.0) ? 0
                  : (int)MathCeil(-MathLog10(g_lotStep));
   return NormalizeDouble(lots, stepDigits);
  }

//===================================================================
//  ENTRY / EXIT
//===================================================================

//--------------------------------------------------------------------
//  OpenTrade — places a buy or sell order
//  SL & TP are calculated from InpSL_Points / InpTP_Points.
//  Replace this with entry logic (swing high/low, ATR, etc.)
//--------------------------------------------------------------------
void OpenTrade(const ENUM_ORDER_TYPE orderType)
  {
   double price, sl, tp;
   double minDist  = MathMax((double)g_stopsLevel, (double)InpMinStopPoints) * g_point;
   double slPoints = MathMax(InpSL_Points, InpMinStopPoints) * g_point;
   double tpPoints = InpTP_Points * g_point;

   if(orderType == ORDER_TYPE_BUY)
     {
      price = NormalizeDouble(symInfo.Ask(), g_digits);
      sl    = NormalizeDouble(price - slPoints, g_digits);
      tp    = NormalizeDouble(price + tpPoints, g_digits);

      //--- Broker min-distance clamp
      if((price - sl) < minDist) sl = NormalizeDouble(price - minDist, g_digits);
      if((tp - price) < minDist) tp = NormalizeDouble(price + minDist, g_digits);
     }
   else
     {
      price = NormalizeDouble(symInfo.Bid(), g_digits);
      sl    = NormalizeDouble(price + slPoints, g_digits);
      tp    = NormalizeDouble(price - tpPoints, g_digits);

      if((sl - price) < minDist) sl = NormalizeDouble(price + minDist, g_digits);
      if((price - tp) < minDist) tp = NormalizeDouble(price - minDist, g_digits);
     }

   double slDistance = (orderType == ORDER_TYPE_BUY) ? (price - sl) : (sl - price);
   double lots = CalculateLot(slDistance);
   if(lots <= 0.0)
     {
      Print("OpenTrade: lot calc returned 0 — skipping");
      return;
     }

   bool ok = (orderType == ORDER_TYPE_BUY)
             ? trade.Buy (lots, _Symbol, price, sl, tp, InpTradeComment)
             : trade.Sell(lots, _Symbol, price, sl, tp, InpTradeComment);

   if(!ok)
      PrintFormat("OpenTrade: OrderSend failed. retcode=%d err=%d lots=%.2f "
                  "price=%.5f sl=%.5f tp=%.5f",
                  trade.ResultRetcode(), GetLastError(),
                  lots, price, sl, tp);
   else
      PrintFormat("OpenTrade: %s lots=%.2f price=%.5f sl=%.5f tp=%.5f",
                  (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"),
                  lots, price, sl, tp);
  }

//--------------------------------------------------------------------
//  TrailSL — stub: implement your trailing stop logic here.
//  Called every tick BEFORE the new-bar gate.
//  Pattern: move SL only if it would improve (never widen).
//--------------------------------------------------------------------
void TrailSL()
  {
   //--- Example skeleton — adapt to your strategy:
   //
   // double buffer = InpSL_BufferPoints * g_point;
   // int total = PositionsTotal();
   // for(int i = total - 1; i >= 0; i--)
   //   {
   //    if(!posInfo.SelectByIndex(i))              continue;
   //    if(posInfo.Symbol()  != _Symbol)            continue;
   //    if((long)posInfo.Magic() != InpMagicNumber) continue;
   //
   //    double currentSL = posInfo.StopLoss();
   //    double bid       = symInfo.Bid();
   //    double ask       = symInfo.Ask();
   //    double newSL     = 0.0;
   //    bool   move      = false;
   //
   //    if(posInfo.PositionType() == POSITION_TYPE_BUY)
   //      {
   //       newSL = NormalizeDouble(bid - buffer, g_digits);
   //       if(newSL > currentSL && newSL < bid - g_stopsLevel * g_point)
   //          move = true;
   //      }
   //    else
   //      {
   //       newSL = NormalizeDouble(ask + buffer, g_digits);
   //       if((currentSL <= 0.0 || newSL < currentSL) &&
   //          newSL > ask + g_stopsLevel * g_point)
   //          move = true;
   //      }
   //
   //    if(move)
   //      {
   //       trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit());
   //      }
   //   }
  }

//===================================================================
//  INDICATOR HELPERS  (copy-paste pattern — one per indicator)
//===================================================================

//--- RSI helper (single buffer, single value at shift)
bool GetRSI(const int handle, const int shift, double &value)
  {
   double buf[1];
   if(CopyBuffer(handle, 0, shift, 1, buf) != 1) return false;
   value = buf[0];
   return true;
  }

//--- Bollinger Bands helper (upper=buf1, mid=buf0, lower=buf2)
bool GetBB(const int handle, const int shift,
           double &upper, double &middle, double &lower)
  {
   double bU[1], bM[1], bL[1];
   if(CopyBuffer(handle, 1, shift, 1, bU) != 1) return false;
   if(CopyBuffer(handle, 0, shift, 1, bM) != 1) return false;
   if(CopyBuffer(handle, 2, shift, 1, bL) != 1) return false;
   upper  = bU[0];
   middle = bM[0];
   lower  = bL[0];
   return true;
  }

//--- MA helper (any iMA handle)
bool GetMA(const int handle, const int shift, double &value)
  {
   double buf[1];
   if(CopyBuffer(handle, 0, shift, 1, buf) != 1) return false;
   value = buf[0];
   return true;
  }

//--- ATR helper
bool GetATR(const int handle, const int shift, double &value)
  {
   double buf[1];
   if(CopyBuffer(handle, 0, shift, 1, buf) != 1) return false;
   value = buf[0];
   return true;
  }

//--- MACD helper  (main=buf0, signal=buf1)
bool GetMACD(const int handle, const int shift,
             double &main, double &signal)
  {
   double bM[1], bS[1];
   if(CopyBuffer(handle, 0, shift, 1, bM) != 1) return false;
   if(CopyBuffer(handle, 1, shift, 1, bS) != 1) return false;
   main   = bM[0];
   signal = bS[0];
   return true;
  }

//--- Stochastic helper (main=buf0, signal=buf1)
bool GetStoch(const int handle, const int shift,
              double &main, double &signal)
  {
   double bM[1], bS[1];
   if(CopyBuffer(handle, 0, shift, 1, bM) != 1) return false;
   if(CopyBuffer(handle, 1, shift, 1, bS) != 1) return false;
   main   = bM[0];
   signal = bS[0];
   return true;
  }

//--- Ichimoku helper  (tenkan=0 kijun=1 spA=2 spB=3 chikou=4)
bool GetIchimoku(const int handle, const int shift,
                 double &tenkan, double &kijun,
                 double &spA,    double &spB,
                 double &chikou)
  {
   double bT[1], bK[1], bA[1], bB[1], bC[1];
   if(CopyBuffer(handle, 0, shift, 1, bT) != 1) return false;
   if(CopyBuffer(handle, 1, shift, 1, bK) != 1) return false;
   if(CopyBuffer(handle, 2, shift, 1, bA) != 1) return false;
   if(CopyBuffer(handle, 3, shift, 1, bB) != 1) return false;
   if(CopyBuffer(handle, 4, shift, 1, bC) != 1) return false;
   tenkan = bT[0]; kijun  = bK[0];
   spA    = bA[0]; spB    = bB[0]; chikou = bC[0];
   return true;
  }

//===================================================================
//  SWING HIGH / LOW  (fractal-style pivot scan on any TF)
//===================================================================

double FindSwingLow(const ENUM_TIMEFRAMES tf,
                    const int lookback,
                    const int fractalN)
  {
   for(int i = fractalN + 1; i <= lookback + fractalN; i++)
     {
      double low_i = iLow(_Symbol, tf, i);
      bool isPivot = true;
      for(int j = 1; j <= fractalN; j++)
        {
         if(iLow(_Symbol, tf, i - j) < low_i ||
            iLow(_Symbol, tf, i + j) < low_i)
           { isPivot = false; break; }
        }
      if(isPivot) return low_i;
     }
   //--- Fallback: absolute lowest bar in lookback window
   int idx = iLowest(_Symbol, tf, MODE_LOW, lookback, 1);
   return (idx >= 0) ? iLow(_Symbol, tf, idx) : 0.0;
  }

double FindSwingHigh(const ENUM_TIMEFRAMES tf,
                     const int lookback,
                     const int fractalN)
  {
   for(int i = fractalN + 1; i <= lookback + fractalN; i++)
     {
      double high_i = iHigh(_Symbol, tf, i);
      bool isPivot = true;
      for(int j = 1; j <= fractalN; j++)
        {
         if(iHigh(_Symbol, tf, i - j) > high_i ||
            iHigh(_Symbol, tf, i + j) > high_i)
           { isPivot = false; break; }
        }
      if(isPivot) return high_i;
     }
   int idx = iHighest(_Symbol, tf, MODE_HIGH, lookback, 1);
   return (idx >= 0) ? iHigh(_Symbol, tf, idx) : 0.0;
  }

