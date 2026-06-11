//+------------------------------------------------------------------+
//|                                        AdaptiveMomentumEA_v2.mq5 |
//|   Adaptive chart-reading EA for Gold / momentum-trend trading    |
//|   Revised: closed-bar HTF reads, stricter retests, safer orders  |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//============================== INPUTS ==============================//
input double   BaseLotSize                        = 0.10;
input double   MinLotSize                         = 0.01;
input double   MaxLotSize                         = 1.00;

input ulong    MagicNumber                        = 20260402;

input bool     AllowBuy                           = true;
input bool     AllowSell                          = true;

input bool     OneTradeAtATime                    = false;
input bool     OneTradePerBar                     = true;
input int      MaxSpreadPoints                    = 500;
input int      MaxOpenTradesPerSymbol             = 3;
input int      ConfidenceForSecondTrade           = 75;
input int      ConfidenceForThirdTrade            = 90;

input int      FastEMA_Period                     = 8;
input int      SlowEMA_Period                     = 18;
input int      RSI_Period                         = 14;
input int      ATR_Period                         = 14;
input int      ADX_Period                         = 14;

input ENUM_TIMEFRAMES HTF_TrendTF                 = PERIOD_M5;
input ENUM_TIMEFRAMES HTF_BiasTF                  = PERIOD_M15;

input int      BreakoutLookbackBars               = 12;
input int      SwingLookbackBars                  = 12;
input int      PullbackLookbackBars               = 4;
input int      StructureSL_Lookback               = 8;
input int      ConsecutiveCandleLookback          = 4;
input int      ChopLookbackBars                   = 3;

input double   Regime_MinADX_Trend                = 16.0;
input double   Regime_StrongADX                   = 22.0;
input double   Regime_MinEMASeparationATR         = 0.12;
input double   Regime_MaxCrossRate                = 0.45;
input double   Regime_MaxOverlapRatio             = 0.52;
input double   Regime_LowVolATRPoints             = 80.0;

input double   Base_RSI_Buy_Threshold             = 54.0;
input double   Base_RSI_Sell_Threshold            = 46.0;
input double   Base_MaxEntryDistFastATRFrac       = 0.75;
input double   Base_MinBodyATRFrac                = 0.24;
input double   Base_MaxOppositeWickBodyRatio      = 1.00;
input double   Base_RetestToleranceATRFrac        = 0.20;
input double   Base_BreakoutBufferATRFrac         = 0.12;
input double   Base_MaxSignalCandleATRFrac        = 1.15;
input double   Base_MaxBoxWidthATRMult            = 3.20;

//--- Optional pattern entries
input bool     UsePatternEntries                  = true;
input bool     Pattern_UseFairValueGap            = true;
input bool     Pattern_UseEngulfing               = true;
input bool     Pattern_UseSwingFailure            = true;
input bool     Pattern_UseBreakRetest             = true;
input bool     Pattern_UseRejection               = true;
input int      Pattern_SwingLookback              = 10;
input int      Pattern_RetestLookbackBars         = 5;
input double   Pattern_MinGapATRFrac              = 0.12;
input double   Pattern_MinEngulfBodyATRFrac       = 0.22;
input double   Pattern_MinSweepATRFrac            = 0.10;
input double   Pattern_MinRejectWickBodyRatio     = 2.10;
input int      Pattern_BaseConfidence             = 72;

input int      Score_AggressiveInstant            = 93;
input int      Score_StrictConfirmed              = 80;
input int      Score_ReducedRisk                  = 65;
input int      Score_MinTrade                     = 60;

input bool     UseStructureSL                     = true;
input double   ATR_SL_Multiplier                  = 1.10;
input double   StructureBufferATRFrac             = 0.25;
input double   MaxHardStopDollars                 = 500.0;
input double   EmergencyStopDollars               = 700.0;

input bool     UseFixedTakeProfit                 = false;
input double   FixedTakeProfitDollars             = 0.0;

input bool     UseProfitLockLadder                = true;
input double   LadderStartProfit                  = 3.0;
input double   LadderSecondStepTrigger            = 6.0;
input double   LadderStepIncrement                = 2.0;
input double   LadderMaxTrigger                   = 200.0;

input bool     UseSessionFilter                   = true;
input int      LondonStartHour                    = 8;
input int      LondonEndHour                      = 17;
input int      NewYorkStartHour                   = 13;
input int      NewYorkEndHour                     = 22;
input bool     BlockDeadHours                     = false;
input int      DeadHourStart1                     = 0;
input int      DeadHourEnd1                       = 5;

input bool     UsePerformanceAdaptation           = true;
input int      PerfLookbackTrades                 = 8;
input int      PerfLookbackDays                   = 14;
input double   PerfTightenThreshold               = -10.0;
input double   PerfLoosenThreshold                = 10.0;

input bool     ShowSignalArrows                   = true;
input bool     PopupAlerts                        = true;
input bool     PushAlerts                         = false;
input bool     DebugPrint                         = true;

//============================= ENUMS ================================//
enum MarketState
{
   STATE_DEAD = 0,
   STATE_LOWVOL,
   STATE_RANGE,
   STATE_CHOPPY,
   STATE_TREND,
   STATE_STRONG_TREND,
   STATE_EXPLOSIVE
};

enum SetupType
{
   SETUP_NONE = 0,
   SETUP_BREAKOUT,
   SETUP_PULLBACK,
   SETUP_CONTINUATION
};

enum ExecStyle
{
   EXEC_SKIP = 0,
   EXEC_REDUCED_RISK,
   EXEC_STRICT_CONFIRMED,
   EXEC_AGGRESSIVE_INSTANT
};

//============================= STRUCTS ==============================//
struct AdaptiveParams
{
   double rsiBuy;
   double rsiSell;
   double maxEntryDistFastATRFrac;
   double minBodyATRFrac;
   double maxOppWickBodyRatio;
   double retestToleranceATRFrac;
   double breakoutBufferATRFrac;
   double maxSignalCandleATRFrac;
   double maxBoxWidthATRMult;
   double minADXTrade;
   int    minConfidence;
};

struct MarketAssessment
{
   MarketState state;
   string      reason;
   double      atr;
   double      adx;
   double      crossRate;
   double      overlapRatio;
   double      emaSepATR;
   bool        bullishBias;
   bool        bearishBias;
};

struct DirectionScore
{
   int    score;
   bool   valid;
   string reason;
};

struct SetupAssessment
{
   SetupType setup;
   bool      buyValid;
   bool      sellValid;
   int       buyScore;
   int       sellScore;
   bool      buyRetestOK;
   bool      sellRetestOK;
   bool      buyBreakoutOK;
   bool      sellBreakoutOK;
   double    boxHigh;
   double    boxLow;
   double    boxHeight;
   string    buyReason;
   string    sellReason;
};

struct TradePlan
{
   bool      trade;
   bool      isBuy;
   SetupType setup;
   ExecStyle style;
   int       confidence;
   double    lot;
   double    sl;
   double    tp;
   string    comment;
   string    reasoning;
};

struct PatternSignal
{
   bool   buyValid;
   bool   sellValid;
   int    buyScore;
   int    sellScore;
   string buyName;
   string sellName;
   string buyReason;
   string sellReason;
};

struct PerfAdaptation
{
   int    wins;
   int    losses;
   double netProfit;
   double biasTighten;
   double biasLoosen;
   double lotFactor;
   int    scoreShift;
   string reason;
};

//============================= GLOBALS ==============================//
int hFastEMA_Cur = INVALID_HANDLE;
int hSlowEMA_Cur = INVALID_HANDLE;
int hFastEMA_HTF = INVALID_HANDLE;
int hSlowEMA_HTF = INVALID_HANDLE;
int hFastEMA_BTF = INVALID_HANDLE;
int hSlowEMA_BTF = INVALID_HANDLE;
int hATR         = INVALID_HANDLE;
int hADX         = INVALID_HANDLE;
int hRSI         = INVALID_HANDLE;

datetime lastTradeBarTime = 0;
datetime lastAlertBarTime = 0;

//============================= HELPERS ==============================//
void Log(string msg)
{
   if(DebugPrint)
      Print("[AdaptiveEA_v2] ", msg);
}

bool CopySingle(int handle, int bufferIndex, int shift, double &val)
{
   if(handle == INVALID_HANDLE)
      return false;

   double arr[];
   ArraySetAsSeries(arr, true);
   if(CopyBuffer(handle, bufferIndex, shift, 1, arr) < 1)
      return false;

   val = arr[0];
   return true;
}

bool IsNewBar()
{
   static datetime lastBar = 0;
   datetime currentBar = iTime(_Symbol, _Period, 0);
   if(currentBar != lastBar)
   {
      lastBar = currentBar;
      return true;
   }
   return false;
}

double AbsVal(double v)
{
   return (v >= 0.0 ? v : -v);
}

double Clamp(double v, double lo, double hi)
{
   if(v < lo) return lo;
   if(v > hi) return hi;
   return v;
}

int ClampInt(int v, int lo, int hi)
{
   if(v < lo) return lo;
   if(v > hi) return hi;
   return v;
}

double NormalizeLots(double lots)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(minLot <= 0.0) minLot = 0.01;
   if(maxLot <= 0.0) maxLot = 100.0;
   if(lotStep <= 0.0) lotStep = 0.01;

   double finalLot = Clamp(lots, MathMax(minLot, MinLotSize), MathMin(maxLot, MaxLotSize));
   finalLot = MathFloor(finalLot / lotStep) * lotStep;
   return NormalizeDouble(finalLot, 2);
}

double NormalizePrice(double price)
{
   return NormalizeDouble(price, _Digits);
}

double GetATR(int shift=1)
{
   double v=0.0;
   if(!CopySingle(hATR,0,shift,v))
      return 0.0;
   return v;
}

double GetADX(int shift=1)
{
   double v=0.0;
   if(!CopySingle(hADX,0,shift,v))
      return 0.0;
   return v;
}

double GetRSI(int shift=1)
{
   double v=50.0;
   if(!CopySingle(hRSI,0,shift,v))
      return 50.0;
   return v;
}

double EMAAtShiftByHandle(int handle, int shift)
{
   double v=0.0;
   if(!CopySingle(handle,0,shift,v))
      return 0.0;
   return v;
}

bool GetEMAs(int shift,
             double &fastCur, double &slowCur,
             double &fastHTF, double &slowHTF,
             double &fastBTF, double &slowBTF)
{
   fastCur = EMAAtShiftByHandle(hFastEMA_Cur, shift);
   slowCur = EMAAtShiftByHandle(hSlowEMA_Cur, shift);

   // Confirmed HTF bars only to avoid live/backtest drift from incomplete candles.
   fastHTF = EMAAtShiftByHandle(hFastEMA_HTF, 1);
   slowHTF = EMAAtShiftByHandle(hSlowEMA_HTF, 1);
   fastBTF = EMAAtShiftByHandle(hFastEMA_BTF, 1);
   slowBTF = EMAAtShiftByHandle(hSlowEMA_BTF, 1);

   if(fastCur == 0.0 || slowCur == 0.0 || fastHTF == 0.0 || slowHTF == 0.0 || fastBTF == 0.0 || slowBTF == 0.0)
      return false;

   return true;
}

double DollarsToPriceDistance(double dollars, double volume)
{
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize <= 0.0 || tickValue <= 0.0 || volume <= 0.0)
      return 0.0;

   return (dollars / (tickValue * volume)) * tickSize;
}

double PriceDistanceToDollars(double priceDistance, double volume)
{
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize <= 0.0 || tickValue <= 0.0 || volume <= 0.0)
      return 0.0;

   return (priceDistance / tickSize) * tickValue * volume;
}

bool HasOpenPosition()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            (ulong)PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            return true;
      }
   }
   return false;
}

double GetOpenVolumeByDirection(bool isBuy)
{
   double volume = 0.0;
   ENUM_POSITION_TYPE desiredType = isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
            continue;
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == desiredType)
            volume += PositionGetDouble(POSITION_VOLUME);
      }
   }
   return volume;
}

int CountOpenPositions()
{
   int count = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            (ulong)PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            count++;
      }
   }
   return count;
}

int CountOpenPositionsByDirection(bool isBuy)
{
   int count = 0;
   ENUM_POSITION_TYPE desiredType = isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
            continue;
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == desiredType)
            count++;
      }
   }
   return count;
}

bool HasOppositePosition(bool isBuy)
{
   ENUM_POSITION_TYPE oppositeType = isBuy ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
            continue;
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == oppositeType)
            return true;
      }
   }
   return false;
}

double GetSpreadPoints()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0) return 999999.0;
   return (ask - bid) / _Point;
}

int GetServerHour()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return dt.hour;
}

bool InHourWindow(int hour, int startH, int endH)
{
   if(startH <= endH)
      return (hour >= startH && hour < endH);

   return (hour >= startH || hour < endH);
}

int FindPositionIdIndex(long &ids[], int count, long positionId)
{
   for(int i = 0; i < count; i++)
   {
      if(ids[i] == positionId)
         return i;
   }
   return -1;
}

int GetTargetOpenTrades(const TradePlan &plan)
{
   if(OneTradeAtATime)
      return 1;

   int targetTrades = 1;
   if(plan.confidence >= ConfidenceForSecondTrade)
      targetTrades = 2;
   if(plan.confidence >= ConfidenceForThirdTrade)
      targetTrades = 3;

   return ClampInt(targetTrades, 1, MathMax(1, MaxOpenTradesPerSymbol));
}

bool IsHedgingAccount()
{
   return ((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
}

string GetAccountModeLabel()
{
   ENUM_ACCOUNT_MARGIN_MODE mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);

   if(mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      return "hedging";
   if(mode == ACCOUNT_MARGIN_MODE_RETAIL_NETTING)
      return "retail netting";
   if(mode == ACCOUNT_MARGIN_MODE_EXCHANGE)
      return "exchange";

   return "unknown";
}

bool ConfigureTradeForSymbol()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);
   return true;
}

bool CanOpenVolume(bool isBuy, double volume, string &reason)
{
   long tradeMode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED || tradeMode == SYMBOL_TRADE_MODE_CLOSEONLY)
   {
      reason = "symbol trade mode blocks opening";
      return false;
   }

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double limit  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT);

   if(minLot > 0.0 && volume < minLot)
   {
      reason = "volume below broker minimum";
      return false;
   }

   if(maxLot > 0.0 && volume > maxLot)
   {
      reason = "volume above broker maximum";
      return false;
   }

   if(step > 0.0)
   {
      double steps = volume / step;
      if(AbsVal(steps - MathRound(steps)) > 0.00001)
      {
         reason = "volume step invalid for symbol";
         return false;
      }
   }

   if(limit > 0.0)
   {
      double currentDirVolume = GetOpenVolumeByDirection(isBuy);
      if(currentDirVolume + volume > limit + 0.0000001)
      {
         reason = "directional volume limit reached";
         return false;
      }
   }

   reason = "";
   return true;
}

bool HasEnoughMargin(bool isBuy, double volume, double price, string &reason)
{
   double requiredMargin = 0.0;
   ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   if(!OrderCalcMargin(orderType, _Symbol, volume, price, requiredMargin))
   {
      reason = "margin calculation failed";
      return false;
   }

   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(requiredMargin > freeMargin)
   {
      reason = "insufficient free margin";
      return false;
   }

   reason = "";
   return true;
}

int GetBrokerSafeTargetTrades(const TradePlan &plan)
{
   int targetTrades = GetTargetOpenTrades(plan);

   if(!IsHedgingAccount())
      targetTrades = 1;

   return ClampInt(targetTrades, 1, MathMax(1, MaxOpenTradesPerSymbol));
}

//====================== RECENT PERFORMANCE ADAPT ====================//
PerfAdaptation GetPerformanceAdaptation()
{
   PerfAdaptation pa;
   pa.wins        = 0;
   pa.losses      = 0;
   pa.netProfit   = 0.0;
   pa.biasTighten = 0.0;
   pa.biasLoosen  = 0.0;
   pa.lotFactor   = 1.0;
   pa.scoreShift  = 0;
   pa.reason      = "neutral";

   if(!UsePerformanceAdaptation)
      return pa;

   datetime fromTime = TimeCurrent() - (PerfLookbackDays * 86400);
   if(!HistorySelect(fromTime, TimeCurrent()))
      return pa;

   long   positionIds[];
   double profits[];
   int    tracked = 0;

   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0)
         continue;

      string symbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
      long   magic  = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
      long   entry  = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      long   posId  = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                    + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                    + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);

      if(symbol != _Symbol || (ulong)magic != MagicNumber)
         continue;

      if(entry != DEAL_ENTRY_OUT)
         continue;

      if(posId <= 0)
         continue;

      int idx = FindPositionIdIndex(positionIds, tracked, posId);
      if(idx < 0)
      {
         if(tracked >= PerfLookbackTrades)
            continue;

         idx = tracked;
         ArrayResize(positionIds, tracked + 1);
         ArrayResize(profits, tracked + 1);
         positionIds[idx] = posId;
         profits[idx]     = 0.0;
         tracked++;
      }

      profits[idx] += profit;
   }

   if(tracked == 0)
      return pa;

   for(int j = 0; j < tracked; j++)
   {
      pa.netProfit += profits[j];
      if(profits[j] >= 0.0) pa.wins++;
      else                  pa.losses++;
   }

   if(pa.netProfit <= PerfTightenThreshold)
   {
      pa.biasTighten = 1.0;
      pa.lotFactor   = 0.70;
      pa.scoreShift  = 6;
      pa.reason      = "recent performance weak -> tighten";
   }
   else if(pa.netProfit >= PerfLoosenThreshold)
   {
      pa.biasLoosen  = 1.0;
      pa.lotFactor   = 1.10;
      pa.scoreShift  = -2;
      pa.reason      = "recent performance strong -> slight loosen";
   }

   return pa;
}

//======================= ADAPTIVE PARAMETERS ========================//
AdaptiveParams GetAdaptiveParams(const MarketAssessment &ma, const PerfAdaptation &pa)
{
   AdaptiveParams ap;
   ap.rsiBuy                  = Base_RSI_Buy_Threshold;
   ap.rsiSell                 = Base_RSI_Sell_Threshold;
   ap.maxEntryDistFastATRFrac = Base_MaxEntryDistFastATRFrac;
   ap.minBodyATRFrac          = Base_MinBodyATRFrac;
   ap.maxOppWickBodyRatio     = Base_MaxOppositeWickBodyRatio;
   ap.retestToleranceATRFrac  = Base_RetestToleranceATRFrac;
   ap.breakoutBufferATRFrac   = Base_BreakoutBufferATRFrac;
   ap.maxSignalCandleATRFrac  = Base_MaxSignalCandleATRFrac;
   ap.maxBoxWidthATRMult      = Base_MaxBoxWidthATRMult;
   ap.minADXTrade             = Regime_MinADX_Trend;
   ap.minConfidence           = Score_MinTrade;

   if(ma.state == STATE_LOWVOL || ma.state == STATE_RANGE || ma.state == STATE_CHOPPY)
   {
      ap.minBodyATRFrac          += 0.08;
      ap.maxEntryDistFastATRFrac -= 0.15;
      ap.maxOppWickBodyRatio     -= 0.20;
      ap.minADXTrade             += 2.0;
      ap.minConfidence           += 4;
   }

   if(ma.state == STATE_STRONG_TREND)
   {
      ap.maxEntryDistFastATRFrac += 0.10;
      ap.breakoutBufferATRFrac   -= 0.03;
      ap.minConfidence           -= 2;
   }

   if(ma.state == STATE_EXPLOSIVE)
   {
      ap.minBodyATRFrac         += 0.05;
      ap.maxSignalCandleATRFrac -= 0.15;
      ap.minConfidence          += 5;
   }

   if(pa.biasTighten > 0.0)
   {
      ap.maxEntryDistFastATRFrac -= 0.10;
      ap.minBodyATRFrac          += 0.05;
      ap.minConfidence           += pa.scoreShift;
      ap.minADXTrade             += 1.5;
   }

   if(pa.biasLoosen > 0.0)
   {
      ap.maxEntryDistFastATRFrac += 0.05;
      ap.minConfidence           += pa.scoreShift;
   }

   int hour = GetServerHour();
   bool london  = InHourWindow(hour, LondonStartHour, LondonEndHour);
   bool ny      = InHourWindow(hour, NewYorkStartHour, NewYorkEndHour);
   bool overlap = london && ny;

   if(overlap)
   {
      ap.minConfidence         -= 2;
      ap.breakoutBufferATRFrac -= 0.02;
   }
   else if(!london && !ny)
   {
      ap.minConfidence += 4;
      ap.minBodyATRFrac += 0.04;
   }

   ap.maxEntryDistFastATRFrac = Clamp(ap.maxEntryDistFastATRFrac, 0.35, 1.20);
   ap.minBodyATRFrac          = Clamp(ap.minBodyATRFrac, 0.15, 0.60);
   ap.maxOppWickBodyRatio     = Clamp(ap.maxOppWickBodyRatio, 0.40, 1.50);
   ap.breakoutBufferATRFrac   = Clamp(ap.breakoutBufferATRFrac, 0.03, 0.25);
   ap.maxSignalCandleATRFrac  = Clamp(ap.maxSignalCandleATRFrac, 0.80, 1.80);
   ap.maxBoxWidthATRMult      = Clamp(ap.maxBoxWidthATRMult, 2.00, 5.00);

   return ap;
}

//======================== MARKET STATE LAYER ========================//
double CalcCrossRate(int bars)
{
   int crosses=0, validBars=0;

   for(int i=1; i<=bars; i++)
   {
      double close_i = iClose(_Symbol, _Period, i);
      double fast_i  = EMAAtShiftByHandle(hFastEMA_Cur, i);
      double slow_i  = EMAAtShiftByHandle(hSlowEMA_Cur, i);

      if(fast_i == 0.0 || slow_i == 0.0)
         continue;

      validBars++;

      bool aboveBoth = (close_i > fast_i && close_i > slow_i);
      bool belowBoth = (close_i < fast_i && close_i < slow_i);

      if(!aboveBoth && !belowBoth)
         crosses++;
   }

   if(validBars <= 0)
      return 1.0;

   return (double)crosses / (double)validBars;
}

double CalcOverlapRatio(int bars)
{
   if(bars < 2)
      return 1.0;

   double totalRange=0.0, totalOverlap=0.0;

   for(int i=1; i<bars; i++)
   {
      double hi1 = iHigh(_Symbol,_Period,i);
      double lo1 = iLow(_Symbol,_Period,i);
      double hi2 = iHigh(_Symbol,_Period,i+1);
      double lo2 = iLow(_Symbol,_Period,i+1);

      double range1 = hi1 - lo1;
      if(range1 <= 0.0)
         continue;

      double overlapHi = MathMin(hi1, hi2);
      double overlapLo = MathMax(lo1, lo2);
      double overlap   = overlapHi - overlapLo;
      if(overlap < 0.0) overlap = 0.0;

      totalRange   += range1;
      totalOverlap += overlap;
   }

   if(totalRange <= 0.0)
      return 1.0;

   return totalOverlap / totalRange;
}

bool IsSessionTradable(string &reason)
{
   if(!UseSessionFilter)
   {
      reason = "session filter off";
      return true;
   }

   int hour = GetServerHour();

   if(BlockDeadHours && InHourWindow(hour, DeadHourStart1, DeadHourEnd1))
   {
      reason = "dead hours blocked";
      return false;
   }

   bool london = InHourWindow(hour, LondonStartHour, LondonEndHour);
   bool ny     = InHourWindow(hour, NewYorkStartHour, NewYorkEndHour);

   if(london || ny)
   {
      reason = "main session";
      return true;
   }

   reason = "off-session, stricter mode";
   return true;
}

MarketAssessment AssessMarket()
{
   MarketAssessment ma;
   ma.state        = STATE_RANGE;
   ma.reason       = "";
   ma.atr          = GetATR(1);
   ma.adx          = GetADX(1);
   ma.crossRate    = CalcCrossRate(4);
   ma.overlapRatio = CalcOverlapRatio(ChopLookbackBars);
   ma.emaSepATR    = 0.0;
   ma.bullishBias  = false;
   ma.bearishBias  = false;

   double fastCur, slowCur, fastHTF, slowHTF, fastBTF, slowBTF;
   if(!GetEMAs(1, fastCur, slowCur, fastHTF, slowHTF, fastBTF, slowBTF))
   {
      ma.reason = "EMA read failed";
      return ma;
   }

   if(ma.atr > 0.0)
      ma.emaSepATR = AbsVal(fastCur - slowCur) / ma.atr;

   ma.bullishBias = (fastCur > slowCur && fastHTF > slowHTF && fastBTF > slowBTF);
   ma.bearishBias = (fastCur < slowCur && fastHTF < slowHTF && fastBTF < slowBTF);

   string sessionReason = "";
   bool tradableSession = IsSessionTradable(sessionReason);

   if(!tradableSession)
   {
      ma.state  = STATE_DEAD;
      ma.reason = sessionReason;
      return ma;
   }

   if(ma.atr/_Point < Regime_LowVolATRPoints)
   {
      ma.state  = STATE_LOWVOL;
      ma.reason = "low volatility";
      return ma;
   }

   if(ma.overlapRatio > Regime_MaxOverlapRatio)
   {
      ma.state  = STATE_CHOPPY;
      ma.reason = "choppy overlap";
      return ma;
   }

   if(ma.adx < Regime_MinADX_Trend || ma.emaSepATR < Regime_MinEMASeparationATR || ma.crossRate > Regime_MaxCrossRate)
   {
      ma.state  = STATE_RANGE;
      ma.reason = "range / weak trend";
      return ma;
   }

   double range1 = iHigh(_Symbol,_Period,1) - iLow(_Symbol,_Period,1);
   bool explosiveBar = (ma.atr > 0.0 && range1 > ma.atr * 1.6);

   if(explosiveBar)
   {
      ma.state  = STATE_EXPLOSIVE;
      ma.reason = "explosive bar regime";
      return ma;
   }

   if(ma.adx >= Regime_StrongADX && ma.emaSepATR >= (Regime_MinEMASeparationATR + 0.08))
   {
      ma.state  = STATE_STRONG_TREND;
      ma.reason = "strong trend";
      return ma;
   }

   ma.state  = STATE_TREND;
   ma.reason = "trend";
   return ma;
}

//==================== DIRECTION / TREND SCORING =====================//
bool RecentStructureBull()
{
   int hiIdx = iHighest(_Symbol, _Period, MODE_HIGH, SwingLookbackBars, 1);
   int loIdx = iLowest(_Symbol, _Period, MODE_LOW,  SwingLookbackBars, 1);

   if(hiIdx < 0 || loIdx < 0)
      return false;

   double recentHigh = iHigh(_Symbol, _Period, hiIdx);
   double recentLow  = iLow(_Symbol, _Period, loIdx);
   double close1     = iClose(_Symbol, _Period, 1);

   return (close1 > recentLow + (recentHigh - recentLow) * 0.55);
}

bool RecentStructureBear()
{
   int hiIdx = iHighest(_Symbol, _Period, MODE_HIGH, SwingLookbackBars, 1);
   int loIdx = iLowest(_Symbol, _Period, MODE_LOW,  SwingLookbackBars, 1);

   if(hiIdx < 0 || loIdx < 0)
      return false;

   double recentHigh = iHigh(_Symbol, _Period, hiIdx);
   double recentLow  = iLow(_Symbol, _Period, loIdx);
   double close1     = iClose(_Symbol, _Period, 1);

   return (close1 < recentLow + (recentHigh - recentLow) * 0.45);
}

DirectionScore ScoreBullDirection(const AdaptiveParams &ap, const MarketAssessment &ma)
{
   DirectionScore ds;
   ds.score  = 0;
   ds.valid  = false;
   ds.reason = "";

   double fastCur, slowCur, fastHTF, slowHTF, fastBTF, slowBTF;
   if(!GetEMAs(1, fastCur, slowCur, fastHTF, slowHTF, fastBTF, slowBTF))
   {
      ds.reason = "EMA read failed";
      return ds;
   }

   double rsi    = GetRSI(1);
   double close1 = iClose(_Symbol, _Period, 1);

   double fastCurPrev = EMAAtShiftByHandle(hFastEMA_Cur, 3);
   double slowCurPrev = EMAAtShiftByHandle(hSlowEMA_Cur, 3);

   if(fastCur > slowCur) ds.score += 12;
   if(close1 > fastCur && close1 > slowCur) ds.score += 12;
   if(fastHTF > slowHTF) ds.score += 12;
   if(fastBTF > slowBTF) ds.score += 10;
   if(fastCur > fastCurPrev && slowCur >= slowCurPrev) ds.score += 8;
   if(ma.adx >= ap.minADXTrade) ds.score += 10;
   if(rsi >= ap.rsiBuy) ds.score += 10;
   if(ma.emaSepATR >= Regime_MinEMASeparationATR) ds.score += 8;
   if(RecentStructureBull()) ds.score += 10;
   if(ma.bullishBias) ds.score += 8;

   ds.valid  = (ds.score >= 55);
   ds.reason = "bull score=" + IntegerToString(ds.score);
   return ds;
}

DirectionScore ScoreBearDirection(const AdaptiveParams &ap, const MarketAssessment &ma)
{
   DirectionScore ds;
   ds.score  = 0;
   ds.valid  = false;
   ds.reason = "";

   double fastCur, slowCur, fastHTF, slowHTF, fastBTF, slowBTF;
   if(!GetEMAs(1, fastCur, slowCur, fastHTF, slowHTF, fastBTF, slowBTF))
   {
      ds.reason = "EMA read failed";
      return ds;
   }

   double rsi    = GetRSI(1);
   double close1 = iClose(_Symbol, _Period, 1);

   double fastCurPrev = EMAAtShiftByHandle(hFastEMA_Cur, 3);
   double slowCurPrev = EMAAtShiftByHandle(hSlowEMA_Cur, 3);

   if(fastCur < slowCur) ds.score += 12;
   if(close1 < fastCur && close1 < slowCur) ds.score += 12;
   if(fastHTF < slowHTF) ds.score += 12;
   if(fastBTF < slowBTF) ds.score += 10;
   if(fastCur < fastCurPrev && slowCur <= slowCurPrev) ds.score += 8;
   if(ma.adx >= ap.minADXTrade) ds.score += 10;
   if(rsi <= ap.rsiSell) ds.score += 10;
   if(ma.emaSepATR >= Regime_MinEMASeparationATR) ds.score += 8;
   if(RecentStructureBear()) ds.score += 10;
   if(ma.bearishBias) ds.score += 8;

   ds.valid  = (ds.score >= 55);
   ds.reason = "bear score=" + IntegerToString(ds.score);
   return ds;
}

//===================== LOCATION / ENTRY FILTERS =====================//
bool CandleQualityGood(bool isBuy, double atr, const AdaptiveParams &ap, int shift=1)
{
   double o = iOpen(_Symbol, _Period, shift);
   double h = iHigh(_Symbol, _Period, shift);
   double l = iLow(_Symbol, _Period, shift);
   double c = iClose(_Symbol, _Period, shift);

   double body      = AbsVal(c - o);
   double range     = h - l;
   double upperWick = h - MathMax(o, c);
   double lowerWick = MathMin(o, c) - l;

   if(atr <= 0.0 || range <= 0.0 || body <= 0.0)
      return false;

   if(body < atr * ap.minBodyATRFrac)
      return false;

   if(range > atr * ap.maxSignalCandleATRFrac)
      return false;

   if(isBuy)
   {
      if(c <= o) return false;
      if((upperWick / body) > ap.maxOppWickBodyRatio) return false;
      if(c < l + range * 0.60) return false;
      return true;
   }

   if(c >= o) return false;
   if((lowerWick / body) > ap.maxOppWickBodyRatio) return false;
   if(c > h - range * 0.60) return false;
   return true;
}

bool EntryTooFarFromEMA(bool isBuy, double atr, const AdaptiveParams &ap)
{
   double fastCur = EMAAtShiftByHandle(hFastEMA_Cur, 1);
   double price   = iClose(_Symbol, _Period, 1);

   if(fastCur == 0.0 || atr <= 0.0)
      return true;

   double dist = AbsVal(price - fastCur);
   if(dist > atr * ap.maxEntryDistFastATRFrac)
      return true;

   return false;
}

bool DetectBreakoutBox(double &boxHigh, double &boxLow, double &boxHeight)
{
   int hiIdx = iHighest(_Symbol, _Period, MODE_HIGH, BreakoutLookbackBars, 1);
   int loIdx = iLowest(_Symbol, _Period, MODE_LOW,  BreakoutLookbackBars, 1);

   if(hiIdx < 0 || loIdx < 0)
      return false;

   boxHigh   = iHigh(_Symbol, _Period, hiIdx);
   boxLow    = iLow(_Symbol, _Period, loIdx);
   boxHeight = boxHigh - boxLow;
   return true;
}

bool BreakoutConfirmed(bool isBuy, double level, double atr, const AdaptiveParams &ap)
{
   double close1 = iClose(_Symbol, _Period, 1);
   double high1  = iHigh(_Symbol, _Period, 1);
   double low1   = iLow(_Symbol, _Period, 1);
   double buffer = atr * ap.breakoutBufferATRFrac;

   if(isBuy)
      return (close1 > level + buffer && high1 > level + buffer);

   return (close1 < level - buffer && low1 < level - buffer);
}

bool RetestValid(bool isBuy, double breakoutLevel, double atr, const AdaptiveParams &ap)
{
   if(atr <= 0.0)
      return false;

   double tol = atr * ap.retestToleranceATRFrac;
   double buffer = atr * ap.breakoutBufferATRFrac;

   for(int breakoutShift = PullbackLookbackBars + 1; breakoutShift >= 2; breakoutShift--)
   {
      double breakoutClose = iClose(_Symbol, _Period, breakoutShift);
      double breakoutHigh  = iHigh(_Symbol, _Period, breakoutShift);
      double breakoutLow   = iLow(_Symbol, _Period, breakoutShift);

      bool broke = false;
      if(isBuy)
         broke = (breakoutClose > breakoutLevel + buffer && breakoutHigh > breakoutLevel + buffer);
      else
         broke = (breakoutClose < breakoutLevel - buffer && breakoutLow < breakoutLevel - buffer);

      if(!broke)
         continue;

      for(int retestShift = breakoutShift - 1; retestShift >= 1; retestShift--)
      {
         double hi = iHigh(_Symbol, _Period, retestShift);
         double lo = iLow(_Symbol, _Period, retestShift);
         double cl = iClose(_Symbol, _Period, retestShift);

         if(isBuy)
         {
            if(lo <= breakoutLevel + tol && cl >= breakoutLevel - tol)
               return true;
         }
         else
         {
            if(hi >= breakoutLevel - tol && cl <= breakoutLevel + tol)
               return true;
         }
      }
   }
   return false;
}

int CountConsecutiveDirectionalCandles(bool isBuy, int lookback)
{
   int count = 0;
   for(int i=1; i<=lookback; i++)
   {
      double o = iOpen(_Symbol,_Period,i);
      double c = iClose(_Symbol,_Period,i);

      if(isBuy)
      {
         if(c > o) count++;
         else break;
      }
      else
      {
         if(c < o) count++;
         else break;
      }
   }
   return count;
}

bool TooManyConsecutiveCandles(bool isBuy)
{
   int c = CountConsecutiveDirectionalCandles(isBuy, ConsecutiveCandleLookback);
   return (c >= 4);
}

bool TooCloseToStructure(bool isBuy, double atr)
{
   if(atr <= 0.0)
      return true;

   double price = iClose(_Symbol,_Period,1);
   int hiIdx = iHighest(_Symbol,_Period,MODE_HIGH,SwingLookbackBars,1);
   int loIdx = iLowest(_Symbol,_Period,MODE_LOW,SwingLookbackBars,1);
   if(hiIdx < 0 || loIdx < 0)
      return false;

   double recentHigh = iHigh(_Symbol,_Period,hiIdx);
   double recentLow  = iLow(_Symbol,_Period,loIdx);

   if(isBuy)
   {
      if((recentHigh - price) < atr * 0.35)
         return true;
   }
   else
   {
      if((price - recentLow) < atr * 0.35)
         return true;
   }
   return false;
}

bool ExhaustionBar(bool isBuy, double atr)
{
   if(atr <= 0.0)
      return false;

   double o = iOpen(_Symbol,_Period,1);
   double h = iHigh(_Symbol,_Period,1);
   double l = iLow(_Symbol,_Period,1);
   double c = iClose(_Symbol,_Period,1);

   double body  = AbsVal(c-o);
   double range = h-l;

   if(range > atr * 1.8 && body > atr * 0.9)
   {
      if(isBuy && c > o) return true;
      if(!isBuy && c < o) return true;
   }
   return false;
}

//========================== PATTERN ENTRIES =========================//
bool DetectFairValueGap(bool isBuy, double atr)
{
   if(!UsePatternEntries || !Pattern_UseFairValueGap || atr <= 0.0)
      return false;

   double high3 = iHigh(_Symbol, _Period, 3);
   double low3  = iLow(_Symbol, _Period, 3);
   double high1 = iHigh(_Symbol, _Period, 1);
   double low1  = iLow(_Symbol, _Period, 1);

   if(isBuy)
   {
      double gap = low1 - high3;
      return (gap > atr * Pattern_MinGapATRFrac);
   }

   double gap = low3 - high1;
   return (gap > atr * Pattern_MinGapATRFrac);
}

bool DetectEngulfing(bool isBuy, double atr)
{
   if(!UsePatternEntries || !Pattern_UseEngulfing || atr <= 0.0)
      return false;

   double o1 = iOpen(_Symbol, _Period, 1);
   double c1 = iClose(_Symbol, _Period, 1);
   double o2 = iOpen(_Symbol, _Period, 2);
   double c2 = iClose(_Symbol, _Period, 2);

   double body1 = AbsVal(c1 - o1);
   if(body1 < atr * Pattern_MinEngulfBodyATRFrac)
      return false;

   double bodyHigh1 = MathMax(o1, c1);
   double bodyLow1  = MathMin(o1, c1);
   double bodyHigh2 = MathMax(o2, c2);
   double bodyLow2  = MathMin(o2, c2);

   if(isBuy)
      return (c1 > o1 && c2 < o2 && bodyHigh1 >= bodyHigh2 && bodyLow1 <= bodyLow2);

   return (c1 < o1 && c2 > o2 && bodyHigh1 >= bodyHigh2 && bodyLow1 <= bodyLow2);
}

bool DetectSwingFailure(bool isBuy, double atr)
{
   if(!UsePatternEntries || !Pattern_UseSwingFailure || atr <= 0.0)
      return false;

   int lookback = MathMax(3, Pattern_SwingLookback);
   double close1 = iClose(_Symbol, _Period, 1);
   double high1  = iHigh(_Symbol, _Period, 1);
   double low1   = iLow(_Symbol, _Period, 1);

   if(isBuy)
   {
      int loIdx = iLowest(_Symbol, _Period, MODE_LOW, lookback, 2);
      if(loIdx < 0) return false;
      double swingLow = iLow(_Symbol, _Period, loIdx);
      return (low1 < swingLow - atr * Pattern_MinSweepATRFrac && close1 > swingLow);
   }

   int hiIdx = iHighest(_Symbol, _Period, MODE_HIGH, lookback, 2);
   if(hiIdx < 0) return false;
   double swingHigh = iHigh(_Symbol, _Period, hiIdx);
   return (high1 > swingHigh + atr * Pattern_MinSweepATRFrac && close1 < swingHigh);
}

bool DetectBreakRetestPattern(bool isBuy, double atr, const AdaptiveParams &ap)
{
   if(!UsePatternEntries || !Pattern_UseBreakRetest || atr <= 0.0)
      return false;

   double boxHigh, boxLow, boxHeight;
   if(!DetectBreakoutBox(boxHigh, boxLow, boxHeight))
      return false;

   bool broke = BreakoutConfirmed(isBuy, isBuy ? boxHigh : boxLow, atr, ap);
   bool retest = RetestValid(isBuy, isBuy ? boxHigh : boxLow, atr, ap);
   return (broke && retest);
}

bool DetectRejectionPattern(bool isBuy, double atr)
{
   if(!UsePatternEntries || !Pattern_UseRejection || atr <= 0.0)
      return false;

   double o = iOpen(_Symbol, _Period, 1);
   double h = iHigh(_Symbol, _Period, 1);
   double l = iLow(_Symbol, _Period, 1);
   double c = iClose(_Symbol, _Period, 1);
   double body = AbsVal(c - o);
   double range = h - l;
   double upperWick = h - MathMax(o, c);
   double lowerWick = MathMin(o, c) - l;

   if(body <= 0.0 || range <= 0.0 || body < atr * 0.10)
      return false;

   if(isBuy)
      return (lowerWick >= body * Pattern_MinRejectWickBodyRatio && c >= l + range * 0.60);

   return (upperWick >= body * Pattern_MinRejectWickBodyRatio && c <= h - range * 0.60);
}

PatternSignal AssessPatterns(const MarketAssessment &ma, const AdaptiveParams &ap)
{
   PatternSignal ps;
   ps.buyValid   = false;
   ps.sellValid  = false;
   ps.buyScore   = 0;
   ps.sellScore  = 0;
   ps.buyName    = "";
   ps.sellName   = "";
   ps.buyReason  = "";
   ps.sellReason = "";

   if(!UsePatternEntries || ma.atr <= 0.0)
      return ps;

   int buyBest = 0;
   int sellBest = 0;
   string buyBestName = "";
   string sellBestName = "";

   if(DetectFairValueGap(true, ma.atr) && 72 > buyBest) { buyBest = 72; buyBestName = "FairValueGap"; }
   if(DetectEngulfing(true, ma.atr) && 70 > buyBest) { buyBest = 70; buyBestName = "Engulfing"; }
   if(DetectSwingFailure(true, ma.atr) && 74 > buyBest) { buyBest = 74; buyBestName = "SwingFailure"; }
   if(DetectBreakRetestPattern(true, ma.atr, ap) && 78 > buyBest) { buyBest = 78; buyBestName = "BreakRetest"; }
   if(DetectRejectionPattern(true, ma.atr) && 69 > buyBest) { buyBest = 69; buyBestName = "Rejection"; }

   if(DetectFairValueGap(false, ma.atr) && 72 > sellBest) { sellBest = 72; sellBestName = "FairValueGap"; }
   if(DetectEngulfing(false, ma.atr) && 70 > sellBest) { sellBest = 70; sellBestName = "Engulfing"; }
   if(DetectSwingFailure(false, ma.atr) && 74 > sellBest) { sellBest = 74; sellBestName = "SwingFailure"; }
   if(DetectBreakRetestPattern(false, ma.atr, ap) && 78 > sellBest) { sellBest = 78; sellBestName = "BreakRetest"; }
   if(DetectRejectionPattern(false, ma.atr) && 69 > sellBest) { sellBest = 69; sellBestName = "Rejection"; }

   if(buyBest > 0)
   {
      ps.buyScore = MathMax(buyBest, Pattern_BaseConfidence);
      ps.buyValid = true;
      ps.buyName = buyBestName;
      ps.buyReason = "pattern=" + buyBestName + " score=" + IntegerToString(ps.buyScore);
   }

   if(sellBest > 0)
   {
      ps.sellScore = MathMax(sellBest, Pattern_BaseConfidence);
      ps.sellValid = true;
      ps.sellName = sellBestName;
      ps.sellReason = "pattern=" + sellBestName + " score=" + IntegerToString(ps.sellScore);
   }

   return ps;
}

//======================== SETUP SELECTION LAYER =====================//
SetupAssessment AssessSetups(const MarketAssessment &ma, const AdaptiveParams &ap)
{
   SetupAssessment sa;
   sa.setup         = SETUP_NONE;
   sa.buyValid      = false;
   sa.sellValid     = false;
   sa.buyScore      = 0;
   sa.sellScore     = 0;
   sa.buyRetestOK   = false;
   sa.sellRetestOK  = false;
   sa.buyBreakoutOK = false;
   sa.sellBreakoutOK= false;
   sa.boxHigh       = 0.0;
   sa.boxLow        = 0.0;
   sa.boxHeight     = 0.0;
   sa.buyReason     = "";
   sa.sellReason    = "";

   double atr = ma.atr;
   if(atr <= 0.0)
   {
      sa.buyReason  = "ATR invalid";
      sa.sellReason = "ATR invalid";
      return sa;
   }

   if(!DetectBreakoutBox(sa.boxHigh, sa.boxLow, sa.boxHeight))
   {
      sa.buyReason  = "box detect failed";
      sa.sellReason = "box detect failed";
      return sa;
   }

   bool boxOK = (sa.boxHeight <= atr * ap.maxBoxWidthATRMult);

   sa.buyBreakoutOK  = BreakoutConfirmed(true,  sa.boxHigh, atr, ap);
   sa.sellBreakoutOK = BreakoutConfirmed(false, sa.boxLow,  atr, ap);
   sa.buyRetestOK    = RetestValid(true,  sa.boxHigh, atr, ap);
   sa.sellRetestOK   = RetestValid(false, sa.boxLow,  atr, ap);

   if(boxOK) sa.buyScore += 8;
   if(sa.buyBreakoutOK) sa.buyScore += 18;
   if(CandleQualityGood(true, atr, ap, 1)) sa.buyScore += 15;
   if(!EntryTooFarFromEMA(true, atr, ap)) sa.buyScore += 12;
   if(sa.buyRetestOK) sa.buyScore += 10;
   if(!TooManyConsecutiveCandles(true)) sa.buyScore += 8;
   if(!TooCloseToStructure(true, atr)) sa.buyScore += 10;
   if(!ExhaustionBar(true, atr)) sa.buyScore += 8;

   if(boxOK) sa.sellScore += 8;
   if(sa.sellBreakoutOK) sa.sellScore += 18;
   if(CandleQualityGood(false, atr, ap, 1)) sa.sellScore += 15;
   if(!EntryTooFarFromEMA(false, atr, ap)) sa.sellScore += 12;
   if(sa.sellRetestOK) sa.sellScore += 10;
   if(!TooManyConsecutiveCandles(false)) sa.sellScore += 8;
   if(!TooCloseToStructure(false, atr)) sa.sellScore += 10;
   if(!ExhaustionBar(false, atr)) sa.sellScore += 8;

   if((sa.buyBreakoutOK && sa.buyRetestOK) || (sa.sellBreakoutOK && sa.sellRetestOK))
      sa.setup = SETUP_PULLBACK;
   else if(ma.state == STATE_STRONG_TREND)
      sa.setup = SETUP_CONTINUATION;
   else if(sa.buyBreakoutOK || sa.sellBreakoutOK)
      sa.setup = SETUP_BREAKOUT;

   sa.buyValid   = (sa.buyScore  >= 55);
   sa.sellValid  = (sa.sellScore >= 55);
   sa.buyReason  = "buy setup score="  + IntegerToString(sa.buyScore);
   sa.sellReason = "sell setup score=" + IntegerToString(sa.sellScore);

   return sa;
}

//=========================== CONFIDENCE =============================//
int BuildConfidence(bool isBuy,
                    const MarketAssessment &ma,
                    const DirectionScore &dir,
                    const SetupAssessment &sa,
                    const PerfAdaptation &pa,
                    const AdaptiveParams &ap)
{
   int score = 0;

   score += dir.score / 2;
   score += (isBuy ? sa.buyScore : sa.sellScore) / 2;

   if(ma.state == STATE_TREND)        score += 4;
   if(ma.state == STATE_STRONG_TREND) score += 8;
   if(ma.state == STATE_EXPLOSIVE)    score -= 6;
   if(ma.state == STATE_CHOPPY)       score -= 12;
   if(ma.state == STATE_RANGE)        score -= 12;
   if(ma.state == STATE_LOWVOL)       score -= 10;

   if(isBuy && sa.buyRetestOK)   score += 4;
   if(!isBuy && sa.sellRetestOK) score += 4;

   if(pa.biasTighten > 0.0) score -= 6;
   if(pa.biasLoosen  > 0.0) score += 2;

   if(GetSpreadPoints() > MaxSpreadPoints * 0.75)
      score -= 5;

   return (int)Clamp(score, 0, 100);
}

ExecStyle DecideExecStyle(int confidence, const MarketAssessment &ma)
{
   if(ma.state == STATE_DEAD || ma.state == STATE_RANGE || ma.state == STATE_CHOPPY || ma.state == STATE_LOWVOL)
      return EXEC_SKIP;

   if(confidence >= Score_AggressiveInstant)
      return EXEC_AGGRESSIVE_INSTANT;

   if(confidence >= Score_StrictConfirmed)
      return EXEC_STRICT_CONFIRMED;

   if(confidence >= Score_ReducedRisk)
      return EXEC_REDUCED_RISK;

   return EXEC_SKIP;
}

//============================== RISK ================================//
double BuildLotSize(int confidence, ExecStyle style, const PerfAdaptation &pa)
{
   double factor = 1.0;

   if(style == EXEC_REDUCED_RISK) factor = 0.50;
   else if(style == EXEC_STRICT_CONFIRMED) factor = 0.80;
   else if(style == EXEC_AGGRESSIVE_INSTANT) factor = 1.00;

   if(confidence >= 95) factor *= 1.10;
   else if(confidence <= 65) factor *= 0.85;

   factor *= pa.lotFactor;

   return NormalizeLots(BaseLotSize * factor);
}

double GetStructureStopPrice(bool isBuy, double atr)
{
   if(atr <= 0.0)
      return 0.0;

   int idx;
   double level;

   if(isBuy)
   {
      idx = iLowest(_Symbol,_Period,MODE_LOW,StructureSL_Lookback,1);
      if(idx < 0) return 0.0;
      level = iLow(_Symbol,_Period,idx) - atr * StructureBufferATRFrac;
      return level;
   }

   idx = iHighest(_Symbol,_Period,MODE_HIGH,StructureSL_Lookback,1);
   if(idx < 0) return 0.0;
   level = iHigh(_Symbol,_Period,idx) + atr * StructureBufferATRFrac;
   return level;
}

double GetATRStopPrice(bool isBuy, double entryPrice, double atr)
{
   if(atr <= 0.0)
      return 0.0;

   double dist = atr * ATR_SL_Multiplier;
   if(isBuy) return entryPrice - dist;
   return entryPrice + dist;
}

double CapSLByMaxDollarRisk(bool isBuy, double entryPrice, double rawSL, double volume)
{
   if(rawSL <= 0.0)
      return 0.0;

   double dist = AbsVal(entryPrice - rawSL);
   double riskDollars = PriceDistanceToDollars(dist, volume);

   if(riskDollars <= MaxHardStopDollars)
      return rawSL;

   double cappedDist = DollarsToPriceDistance(MaxHardStopDollars, volume);
   if(cappedDist <= 0.0)
      return rawSL;

   if(isBuy) return entryPrice - cappedDist;
   return entryPrice + cappedDist;
}

bool EnforceBrokerStopRules(bool isBuy, double entryPrice, double &sl, double &tp, string &reason)
{
   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStop = MathMax(stopsLevel * _Point, _Point);

   if(sl > 0.0)
   {
      if(isBuy)
      {
         if(sl >= entryPrice - minStop)
         {
            reason = "buy SL too close to entry";
            return false;
         }
      }
      else
      {
         if(sl <= entryPrice + minStop)
         {
            reason = "sell SL too close to entry";
            return false;
         }
      }
   }

   if(tp > 0.0)
   {
      if(isBuy)
      {
         if(tp <= entryPrice + minStop)
            tp = entryPrice + minStop;
      }
      else
      {
         if(tp >= entryPrice - minStop)
            tp = entryPrice - minStop;
      }
   }

   sl = NormalizePrice(sl);
   tp = (tp > 0.0 ? NormalizePrice(tp) : 0.0);
   reason = "";
   return true;
}

void BuildStops(bool isBuy, double entryPrice, double volume, double atr, int confidence, double &sl, double &tp)
{
   sl = 0.0;
   tp = 0.0;

   double slStruct = 0.0;
   double slATR    = GetATRStopPrice(isBuy, entryPrice, atr);

   if(UseStructureSL)
      slStruct = GetStructureStopPrice(isBuy, atr);

   double rawSL = 0.0;

   if(slStruct > 0.0 && slATR > 0.0)
   {
      if(isBuy)
         rawSL = MathMin(slStruct, slATR);
      else
         rawSL = MathMax(slStruct, slATR);
   }
   else if(slStruct > 0.0)
      rawSL = slStruct;
   else
      rawSL = slATR;

   sl = CapSLByMaxDollarRisk(isBuy, entryPrice, rawSL, volume);

   if(UseFixedTakeProfit && FixedTakeProfitDollars > 0.0)
   {
      double tpDist = DollarsToPriceDistance(FixedTakeProfitDollars, volume);
      if(tpDist > 0.0)
      {
         tp = isBuy ? (entryPrice + tpDist) : (entryPrice - tpDist);
      }
   }
   else
   {
      double rr = 1.2;
      if(confidence >= 90) rr = 1.6;
      else if(confidence >= 75) rr = 1.4;

      double riskDist = AbsVal(entryPrice - sl);
      tp = isBuy ? (entryPrice + riskDist * rr) : (entryPrice - riskDist * rr);
   }

   sl = NormalizePrice(sl);
   if(tp > 0.0)
      tp = NormalizePrice(tp);
}

//====================== PROFIT LOCK MANAGEMENT ======================//
double GetLockedProfitForCurrentProfit(double currentProfit)
{
   if(currentProfit < LadderStartProfit)
      return -1.0;

   if(currentProfit >= LadderStartProfit && currentProfit < LadderSecondStepTrigger)
      return 0.0;

   double bestLocked = 0.0;
   for(double trigger = LadderSecondStepTrigger; trigger <= LadderMaxTrigger + 0.0001; trigger += LadderStepIncrement)
   {
      if(currentProfit >= trigger)
         bestLocked = trigger - 2.0;
      else
         break;
   }

   return bestLocked;
}

double GetDesiredSLPrice(ENUM_POSITION_TYPE posType, double openPrice, double volume, double lockedProfitDollars)
{
   double dist = DollarsToPriceDistance(lockedProfitDollars, volume);
   if(dist <= 0.0)
      return 0.0;

   if(posType == POSITION_TYPE_BUY)
      return openPrice + dist;

   return openPrice - dist;
}

bool IsBetterSL(ENUM_POSITION_TYPE posType, double currentSL, double desiredSL)
{
   if(posType == POSITION_TYPE_BUY)
   {
      if(currentSL == 0.0) return true;
      return (desiredSL > currentSL);
   }

   if(currentSL == 0.0) return true;
   return (desiredSL < currentSL);
}

void ManageOpenPosition()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      double volume    = PositionGetDouble(POSITION_VOLUME);
      double profit    = PositionGetDouble(POSITION_PROFIT);

      if(profit <= -EmergencyStopDollars)
      {
         if(trade.PositionClose(ticket))
            Log("Emergency close triggered for ticket " + IntegerToString((int)ticket) + ".");
         continue;
      }

      if(!UseProfitLockLadder)
         continue;

      double lockedProfit = GetLockedProfitForCurrentProfit(profit);
      if(lockedProfit < 0.0)
         continue;

      double desiredSL = GetDesiredSLPrice(posType, openPrice, volume, lockedProfit);
      if(desiredSL <= 0.0)
         continue;

      double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double minStop = MathMax(stopsLevel * _Point, _Point);

      if(posType == POSITION_TYPE_BUY)
      {
         if(desiredSL >= bid - minStop)
            desiredSL = bid - minStop;
      }
      else
      {
         if(desiredSL <= ask + minStop)
            desiredSL = ask + minStop;
      }

      desiredSL = NormalizePrice(desiredSL);

      if(!IsBetterSL(posType, currentSL, desiredSL))
         continue;

      if(trade.PositionModify(ticket, desiredSL, currentTP))
         Log("Profit lock updated for ticket " + IntegerToString((int)ticket) + ". Profit=$" + DoubleToString(profit,2));
   }
}

//============================= VISUALS ==============================//
void DrawSignalArrow(bool isBuy, datetime t, double price)
{
   if(!ShowSignalArrows)
      return;

   string name = (isBuy ? "BUY_" : "SELL_") + IntegerToString((int)t) + "_" + DoubleToString(price, _Digits);
   if(ObjectFind(0, name) != -1)
      return;

   if(!ObjectCreate(0, name, OBJ_ARROW, 0, t, price))
      return;

   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, isBuy ? 233 : 234);
   ObjectSetInteger(0, name, OBJPROP_COLOR, isBuy ? clrLime : clrRed);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
}

void FireSignalAlert(string text)
{
   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime == lastAlertBarTime)
      return;

   lastAlertBarTime = barTime;

   string msg = _Symbol + " " + EnumToString((ENUM_TIMEFRAMES)_Period) + " " + text;

   if(PopupAlerts) Alert(msg);
   if(PushAlerts)  SendNotification(msg);
}

void DeleteArrowsByPrefix(string prefix)
{
   for(int i=ObjectsTotal(0)-1; i>=0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
   }
}

//========================== TRADE PLANNER ===========================//
bool StrictConfirmationPass(bool isBuy, double atr, const AdaptiveParams &ap)
{
   if(!CandleQualityGood(isBuy, atr, ap, 1))
      return false;

   double c1 = iClose(_Symbol,_Period,1);
   double c2 = iClose(_Symbol,_Period,2);

   if(isBuy)
      return (c1 >= c2);

   return (c1 <= c2);
}

TradePlan BuildTradePlan()
{
   TradePlan tp;
   tp.trade      = false;
   tp.isBuy      = true;
   tp.setup      = SETUP_NONE;
   tp.style      = EXEC_SKIP;
   tp.confidence = 0;
   tp.lot        = 0.0;
   tp.sl         = 0.0;
   tp.tp         = 0.0;
   tp.comment    = "";
   tp.reasoning  = "";

   if(GetSpreadPoints() > MaxSpreadPoints)
   {
      tp.reasoning = "spread too high";
      return tp;
   }

   PerfAdaptation   pa = GetPerformanceAdaptation();
   MarketAssessment ma = AssessMarket();
   AdaptiveParams   ap = GetAdaptiveParams(ma, pa);

   if(ma.state == STATE_DEAD || ma.state == STATE_RANGE || ma.state == STATE_CHOPPY || ma.state == STATE_LOWVOL)
   {
      tp.reasoning = "skip state: " + ma.reason;
      return tp;
   }

   DirectionScore  bull = ScoreBullDirection(ap, ma);
   DirectionScore  bear = ScoreBearDirection(ap, ma);
   SetupAssessment sa   = AssessSetups(ma, ap);
   PatternSignal   ps   = AssessPatterns(ma, ap);

   int  buyConfidence   = 0;
   int  sellConfidence  = 0;
   bool buyFromPattern  = false;
   bool sellFromPattern = false;

   if(AllowBuy && bull.valid && sa.buyValid)
      buyConfidence = BuildConfidence(true, ma, bull, sa, pa, ap);

   if(AllowSell && bear.valid && sa.sellValid)
      sellConfidence = BuildConfidence(false, ma, bear, sa, pa, ap);

   if(AllowBuy && buyConfidence < ap.minConfidence && ps.buyValid && bull.valid)
   {
      buyConfidence  = MathMax(buyConfidence, ps.buyScore);
      buyFromPattern = true;
   }

   if(AllowSell && sellConfidence < ap.minConfidence && ps.sellValid && bear.valid)
   {
      sellConfidence  = MathMax(sellConfidence, ps.sellScore);
      sellFromPattern = true;
   }

   bool chooseBuy  = (buyConfidence  >= ap.minConfidence && buyConfidence  > sellConfidence);
   bool chooseSell = (sellConfidence >= ap.minConfidence && sellConfidence > buyConfidence);

   if(!chooseBuy && !chooseSell)
   {
      tp.reasoning = "no side strong enough | buy=" + IntegerToString(buyConfidence) + " sell=" + IntegerToString(sellConfidence);
      return tp;
   }

   tp.isBuy      = chooseBuy;
   tp.confidence = chooseBuy ? buyConfidence : sellConfidence;
   tp.setup      = (chooseBuy && buyFromPattern) || (chooseSell && sellFromPattern) ? SETUP_PULLBACK : sa.setup;
   tp.style      = DecideExecStyle(tp.confidence, ma);

   if(tp.style == EXEC_SKIP)
   {
      tp.reasoning = "exec style skip | confidence=" + IntegerToString(tp.confidence);
      return tp;
   }

   if(tp.style == EXEC_STRICT_CONFIRMED || tp.style == EXEC_REDUCED_RISK)
   {
      if(!StrictConfirmationPass(tp.isBuy, ma.atr, ap))
      {
         tp.reasoning = "strict confirmation failed";
         return tp;
      }
   }

   double entryPrice = tp.isBuy ? SymbolInfoDouble(_Symbol,SYMBOL_ASK) : SymbolInfoDouble(_Symbol,SYMBOL_BID);
   tp.lot = BuildLotSize(tp.confidence, tp.style, pa);
   BuildStops(tp.isBuy, entryPrice, tp.lot, ma.atr, tp.confidence, tp.sl, tp.tp);

   if(tp.sl <= 0.0)
   {
      tp.reasoning = "SL invalid";
      return tp;
   }

   string stopReason = "";
   if(!EnforceBrokerStopRules(tp.isBuy, entryPrice, tp.sl, tp.tp, stopReason))
   {
      tp.reasoning = "stop rules failed: " + stopReason;
      return tp;
   }

   tp.trade = true;

   string setupTxt = "None";
   if(tp.setup == SETUP_BREAKOUT)     setupTxt = "Breakout";
   if(tp.setup == SETUP_PULLBACK)     setupTxt = "Pullback";
   if(tp.setup == SETUP_CONTINUATION) setupTxt = "Continuation";

   string styleTxt = "Skip";
   if(tp.style == EXEC_REDUCED_RISK)       styleTxt = "ReducedRisk";
   if(tp.style == EXEC_STRICT_CONFIRMED)   styleTxt = "StrictConfirmed";
   if(tp.style == EXEC_AGGRESSIVE_INSTANT) styleTxt = "AggressiveInstant";

   bool   chosenPattern = (tp.isBuy && buyFromPattern) || (!tp.isBuy && sellFromPattern);
   string patternName   = tp.isBuy ? ps.buyName : ps.sellName;

   if(chosenPattern)
      tp.comment = "Pattern " + patternName + " " + styleTxt + (tp.isBuy ? " Buy" : " Sell");
   else
      tp.comment = setupTxt + " " + styleTxt + (tp.isBuy ? " Buy" : " Sell");

   tp.reasoning = "state=" + ma.reason +
                  " | perf=" + pa.reason +
                  " | confidence=" + IntegerToString(tp.confidence) +
                  " | lot=" + DoubleToString(tp.lot,2) +
                  " | targetTrades=" + IntegerToString(GetBrokerSafeTargetTrades(tp)) +
                  (chosenPattern ? " | entry=pattern:" + patternName : " | entry=core");

   return tp;
}

//============================= EXECUTION ============================//
bool PlaceTrade(TradePlan &plan)
{
   ConfigureTradeForSymbol();

   double entryPrice  = plan.isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   string brokerReason = "";

   if(!CanOpenVolume(plan.isBuy, plan.lot, brokerReason))
   {
      Log("Order blocked before send: " + brokerReason);
      return false;
   }

   if(!HasEnoughMargin(plan.isBuy, plan.lot, entryPrice, brokerReason))
   {
      Log("Order blocked before send: " + brokerReason);
      return false;
   }

   bool ok = false;
   if(plan.isBuy)
      ok = trade.Buy(plan.lot, _Symbol, 0.0, plan.sl, plan.tp, plan.comment);
   else
      ok = trade.Sell(plan.lot, _Symbol, 0.0, plan.sl, plan.tp, plan.comment);

   if(ok)
   {
      Log((plan.isBuy ? "BUY" : "SELL") + " placed | " + plan.reasoning);
      return true;
   }

   Log("Order failed. Retcode=" + IntegerToString((int)trade.ResultRetcode()) +
       " Comment=" + trade.ResultComment());
   return false;
}

bool PlaceTradeBatch(TradePlan &plan, int tradesToPlace)
{
   if(tradesToPlace <= 0)
      return false;

   int placed = 0;
   for(int i = 0; i < tradesToPlace; i++)
   {
      TradePlan orderPlan  = plan;
      orderPlan.comment    = plan.comment + " [" + IntegerToString(i + 1) + "/" + IntegerToString(tradesToPlace) + "]";

      if(!PlaceTrade(orderPlan))
         break;

      placed++;
   }

   if(placed > 0)
   {
      lastTradeBarTime = iTime(_Symbol, _Period, 0);
      Log("Placed " + IntegerToString(placed) + " " + (plan.isBuy ? "buy" : "sell") + " trade(s) this bar.");
      return true;
   }

   return false;
}

//=============================== INIT ===============================//
int OnInit()
{
   hFastEMA_Cur = iMA(_Symbol, _Period,    FastEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   hSlowEMA_Cur = iMA(_Symbol, _Period,    SlowEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   hFastEMA_HTF = iMA(_Symbol, HTF_TrendTF, FastEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   hSlowEMA_HTF = iMA(_Symbol, HTF_TrendTF, SlowEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   hFastEMA_BTF = iMA(_Symbol, HTF_BiasTF,  FastEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   hSlowEMA_BTF = iMA(_Symbol, HTF_BiasTF,  SlowEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   hATR         = iATR(_Symbol, _Period, ATR_Period);
   hADX         = iADX(_Symbol, _Period, ADX_Period);
   hRSI         = iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE);

   if(hFastEMA_Cur == INVALID_HANDLE ||
      hSlowEMA_Cur == INVALID_HANDLE ||
      hFastEMA_HTF == INVALID_HANDLE ||
      hSlowEMA_HTF == INVALID_HANDLE ||
      hFastEMA_BTF == INVALID_HANDLE ||
      hSlowEMA_BTF == INVALID_HANDLE ||
      hATR == INVALID_HANDLE ||
      hADX == INVALID_HANDLE ||
      hRSI == INVALID_HANDLE)
   {
      Log("Failed to create indicator handles.");
      return INIT_FAILED;
   }

   DeleteArrowsByPrefix("BUY_");
   DeleteArrowsByPrefix("SELL_");

   Log("Initialized successfully. Account mode=" + GetAccountModeLabel());

   //--- BROKER DIAGNOSTIC (temporary - remove after comparing brokers) ---
   Print("=== BROKER DIAGNOSTIC ===");
   Print("Broker/company:    ", AccountInfoString(ACCOUNT_COMPANY));
   Print("Account mode:      ", GetAccountModeLabel());
   Print("Server time:       ", TimeCurrent());
   Print("Symbol:            ", _Symbol);
   Print("Spread points:     ", DoubleToString(GetSpreadPoints(), 1));
   Print("Tick size:         ", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE), 6));
   Print("Tick value:        ", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), 4));
   Print("Stops level:       ", IntegerToString((int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)));
   Print("Volume min:        ", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), 2));
   Print("Volume max:        ", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), 2));
   Print("Volume step:       ", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), 2));
   Print("Volume limit:      ", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT), 2));
   Print("Point size:        ", DoubleToString(_Point, 6));
   Print("Digits:            ", IntegerToString(_Digits));
   Print("ATR(1):            ", DoubleToString(GetATR(1), 2));
   Print("ATR in points:     ", DoubleToString(GetATR(1) / _Point, 1));
   Print("=========================");
   //--- END BROKER DIAGNOSTIC ---

   return INIT_SUCCEEDED;
}

//============================== DEINIT ==============================//
void OnDeinit(const int reason)
{
   DeleteArrowsByPrefix("BUY_");
   DeleteArrowsByPrefix("SELL_");

   if(hFastEMA_Cur != INVALID_HANDLE) IndicatorRelease(hFastEMA_Cur);
   if(hSlowEMA_Cur != INVALID_HANDLE) IndicatorRelease(hSlowEMA_Cur);
   if(hFastEMA_HTF != INVALID_HANDLE) IndicatorRelease(hFastEMA_HTF);
   if(hSlowEMA_HTF != INVALID_HANDLE) IndicatorRelease(hSlowEMA_HTF);
   if(hFastEMA_BTF != INVALID_HANDLE) IndicatorRelease(hFastEMA_BTF);
   if(hSlowEMA_BTF != INVALID_HANDLE) IndicatorRelease(hSlowEMA_BTF);
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   if(hADX != INVALID_HANDLE) IndicatorRelease(hADX);
   if(hRSI != INVALID_HANDLE) IndicatorRelease(hRSI);
}

//=============================== TICK ===============================//
void OnTick()
{
   ManageOpenPosition();

   if(!IsNewBar())
      return;

   if(OneTradePerBar && iTime(_Symbol, _Period, 0) == lastTradeBarTime)
   {
      Log("Already traded this bar.");
      return;
   }

   TradePlan plan = BuildTradePlan();

   if(!plan.trade)
   {
      Log("No trade: " + plan.reasoning);
      return;
   }

   if(HasOppositePosition(plan.isBuy))
   {
      Log("Opposite position already open. No new trade.");
      return;
   }

   int currentSameDirectionTrades = CountOpenPositionsByDirection(plan.isBuy);
   int maxOpenTrades    = MathMax(1, MaxOpenTradesPerSymbol);
   int targetOpenTrades = MathMin(GetBrokerSafeTargetTrades(plan), maxOpenTrades);

   if(currentSameDirectionTrades >= targetOpenTrades)
   {
      Log("Open trades already at confidence target. Current=" +
          IntegerToString(currentSameDirectionTrades) +
          " Target=" + IntegerToString(targetOpenTrades));
      return;
   }

   int tradesToPlace = targetOpenTrades - currentSameDirectionTrades;
   if(tradesToPlace <= 0)
      return;

   if(!IsHedgingAccount() && tradesToPlace > 1)
      tradesToPlace = 1;

   if(!PlaceTradeBatch(plan, tradesToPlace))
      return;

   if(plan.isBuy)
      DrawSignalArrow(true,  iTime(_Symbol,_Period,1), iLow(_Symbol,_Period,1)  - (20 * _Point));
   else
      DrawSignalArrow(false, iTime(_Symbol,_Period,1), iHigh(_Symbol,_Period,1) + (20 * _Point));

   FireSignalAlert(plan.comment + " | confidence=" + IntegerToString(plan.confidence) +
                   " | trades=" + IntegerToString(tradesToPlace));
}
//+------------------------------------------------------------------+
