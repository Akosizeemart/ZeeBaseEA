//+------------------------------------------------------------------+
//|                                           ZeeBaseTemplate.mq5   |
//|                                    Zee — MQL5 EA base template   |
//+------------------------------------------------------------------+
#property copyright "Zee"
#property version   "1.00"
#property strict
#property description "Copy, rename, fill in signals. Everything else is done."

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

input group "=== Visuals ==="
input bool   InpShowComment    = true;         // Show info block on chart

//===================================================================
//  GLOBALS
//===================================================================

CTrade        trade;
CPositionInfo posInfo;
CSymbolInfo   symInfo;

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
   if(!symInfo.Name(_Symbol))
     {
      Print("ERR: symInfo.Name() failed for ", _Symbol);
      return INIT_FAILED;
     }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);

   g_isTester       = (bool)MQLInfoInteger(MQL_TESTER);
   g_isOptimization = (bool)MQLInfoInteger(MQL_OPTIMIZATION);

   //--- cache to avoid repeated broker calls on every tick
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

   //--- prime detector so first tick doesn't fire as a new bar
   IsNewBar(InpSignalTF);

   if(InpShowComment) Comment("");
   Print("ZeeBaseTemplate: init on ", _Symbol, " / ", EnumToString(InpSignalTF));
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
   //--- trail runs every tick, before the bar gate
   if(symInfo.RefreshRates())
      TrailSL();

   if(!IsNewBar(InpSignalTF))
      return;

   if(!symInfo.RefreshRates())
      return;

   if(GetSpread() > InpMaxSpreadPoints)
     {
      if(InpShowComment) Comment("Spread too wide — waiting");
      return;
     }

   if(InpOneTradeOnly && HasOpenPosition())
      return;

   //--- TODO: read indicator values here
   // double rsi;
   // if(!GetRSI(handleXXX, 1, rsi)) return;

   //--- TODO: define your entry conditions
   bool buySignal  = false;
   bool sellSignal = false;

   if(buySignal)
      OpenTrade(ORDER_TYPE_BUY);
   else if(sellSignal)
      OpenTrade(ORDER_TYPE_SELL);

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
//  IsNewBar — single static, safe for one TF call per EA.
//  If you need two TFs, keep a separate prevTime per timeframe.
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

int GetSpread()
  {
   return (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
  }

//--------------------------------------------------------------------
//  HasOpenPosition — netting: fast PositionSelect path.
//  Hedging: full scan because multiple positions per symbol exist.
//--------------------------------------------------------------------
bool HasOpenPosition()
  {
   if(PositionSelect(_Symbol))
      if((long)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         return true;

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
//  CloseAllPositions — directionFilter: POSITION_TYPE_BUY,
//  POSITION_TYPE_SELL, or -1 for everything.
//--------------------------------------------------------------------
void CloseAllPositions(const int directionFilter = -1)
  {
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      if(!posInfo.SelectByIndex(i))                    continue;
      if(posInfo.Symbol()            != _Symbol)        continue;
      if((long)posInfo.Magic()       != InpMagicNumber) continue;

      if(directionFilter != -1 &&
         (int)posInfo.PositionType() != directionFilter)
         continue;

      ulong  ticket     = posInfo.Ticket();
      string dir        = (posInfo.PositionType() == POSITION_TYPE_BUY ? "BUY" : "SELL");
      double closePrice = (posInfo.PositionType() == POSITION_TYPE_BUY)
                         ? symInfo.Bid() : symInfo.Ask();

      bool ok = trade.PositionClose(ticket, InpSlippagePoints);
      if(!ok)
         PrintFormat("CloseAllPositions: failed ticket=%I64u err=%d",
                     ticket, GetLastError());
      else
         PrintFormat("CloseAllPositions: closed ticket=%I64u %s @ %.5f",
                     ticket, dir, closePrice);
     }
  }

//--------------------------------------------------------------------
//  CalculateLot — slDistance in price units (entry to stop)
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

void OpenTrade(const ENUM_ORDER_TYPE orderType)
  {
   double price, sl, tp;
   //--- broker stop-level clamp: SL must be at least stopsLevel points away
   double minDist  = MathMax((double)g_stopsLevel, (double)InpMinStopPoints) * g_point;
   double slPoints = MathMax(InpSL_Points, InpMinStopPoints) * g_point;
   double tpPoints = InpTP_Points * g_point;

   if(orderType == ORDER_TYPE_BUY)
     {
      price = NormalizeDouble(symInfo.Ask(), g_digits);
      sl    = NormalizeDouble(price - slPoints, g_digits);
      tp    = NormalizeDouble(price + tpPoints, g_digits);

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
      PrintFormat("OpenTrade: failed retcode=%d err=%d lots=%.2f price=%.5f sl=%.5f tp=%.5f",
                  trade.ResultRetcode(), GetLastError(), lots, price, sl, tp);
   else
      PrintFormat("OpenTrade: %s lots=%.2f price=%.5f sl=%.5f tp=%.5f",
                  (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"), lots, price, sl, tp);
  }

//--------------------------------------------------------------------
//  TrailSL — runs every tick before the new-bar gate.
//  Move SL only in the profitable direction — never widen it.
//--------------------------------------------------------------------
void TrailSL()
  {
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
   //       trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit());
   //   }
  }

//===================================================================
//  INDICATOR HELPERS
//===================================================================

bool GetRSI(const int handle, const int shift, double &value)
  {
   double buf[1];
   if(CopyBuffer(handle, 0, shift, 1, buf) != 1) return false;
   value = buf[0];
   return true;
  }

//--- BB buffer layout: 0=mid, 1=upper, 2=lower
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

bool GetMA(const int handle, const int shift, double &value)
  {
   double buf[1];
   if(CopyBuffer(handle, 0, shift, 1, buf) != 1) return false;
   value = buf[0];
   return true;
  }

bool GetATR(const int handle, const int shift, double &value)
  {
   double buf[1];
   if(CopyBuffer(handle, 0, shift, 1, buf) != 1) return false;
   value = buf[0];
   return true;
  }

//--- MACD: 0=main, 1=signal
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

//--- Stochastic: 0=main, 1=signal
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

//--- Ichimoku: 0=tenkan, 1=kijun, 2=spA, 3=spB, 4=chikou
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
//  SWING HIGH / LOW
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
   //--- fallback to absolute low when no clean pivot found
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
