# ZeeBaseEA.mq5

My personal starting point for every new EA. Copy it, rename it, drop in the signal logic — everything else is wired up.

---

## What's in the file

| Block     | Function                                                             | Notes                                         |
| --------- | -------------------------------------------------------------------- | --------------------------------------------- |
| Lifecycle | `OnInit`                                                             | Symbol cache, trade object setup, env flags   |
| Lifecycle | `OnDeinit`                                                           | Handle release, comment cleanup               |
| Main loop | `OnTick`                                                             | Spread gate → new-bar gate → signal → execute |
| Utility   | `IsNewBar(tf)`                                                       | Single-TF new-bar detection                   |
| Utility   | `HasOpenPosition()`                                                  | Netting + hedging account safe                |
| Utility   | `CloseAllPositions(dir)`                                             | Close all / buys only / sells only            |
| Utility   | `GetSpread()`                                                        | Spread in points                              |
| Sizing    | `CalculateLot(slDist)`                                               | Fixed lot or % equity                         |
| Entry     | `OpenTrade(type)`                                                    | Buy/sell with SL, TP, broker clamp            |
| Exit      | `TrailSL()`                                                          | Stub — fill in your trailing logic            |
| Helpers   | `GetRSI / GetBB / GetMA / GetATR / GetMACD / GetStoch / GetIchimoku` | Buffer-safe, return false on failure          |
| Structure | `FindSwingLow / FindSwingHigh`                                       | Fractal pivot scan, any TF                    |

---

## Getting started

**1. Copy and rename**

```
ZeeBaseEA.mq5  →  YourNewEA.mq5
```

Update the file header and `InpTradeComment` default.

**2. Set a unique magic number**

```cpp
input long InpMagicNumber = 100001;  // different for every EA on the account
```

**3. Create handles in `OnInit`, release in `OnDeinit`**

```cpp
// OnInit
handleRSI = iRSI(_Symbol, InpSignalTF, 14, PRICE_CLOSE);
if(handleRSI == INVALID_HANDLE) return INIT_FAILED;

// OnDeinit
if(handleRSI != INVALID_HANDLE) IndicatorRelease(handleRSI);
```

**4. Read values in `OnTick`, define signals**

```cpp
double rsi;
if(!GetRSI(handleRSI, 1, rsi)) return;  // shift=1 → last closed bar

bool buySignal  = (rsi < 30.0);
bool sellSignal = (rsi > 70.0);
```

**5. Fill in `TrailSL()` if you need it**
The skeleton is already there — uncomment and adapt.

---

## Inputs

**Identification**
| Input | Default | Description |
|---|---|---|
| `InpMagicNumber` | 100001 | Change for every EA |
| `InpTradeComment` | "ZeeBase" | Label on trades |

**Timeframes**
| Input | Default | Description |
|---|---|---|
| `InpSignalTF` | PERIOD_H1 | New-bar detection and signal evaluation |

**Risk**
| Input | Default | Description |
|---|---|---|
| `InpRiskMode` | RISK_PERCENT_EQUITY | Fixed lot or % equity |
| `InpFixedLot` | 0.10 | Used when mode = RISK_FIXED_LOT |
| `InpRiskPercent` | 1.0 | % of equity per trade |
| `InpMaxLot` | 5.0 | Hard cap regardless of sizing mode |

**Stop Loss / Take Profit**
| Input | Default | Description |
|---|---|---|
| `InpSL_Points` | 200 | SL distance in points |
| `InpTP_Points` | 400 | TP distance in points |
| `InpMinStopPoints` | 50 | Floor on SL distance |
| `InpSL_BufferPoints` | 30 | Buffer added on top of swing level |

**Trade Management**
| Input | Default | Description |
|---|---|---|
| `InpOneTradeOnly` | true | No new entries while a position is open |
| `InpMaxSpreadPoints` | 300 | Skip bar if spread exceeds this — tune per instrument |
| `InpSlippagePoints` | 20 | Order deviation tolerance |

---

## Indicator helpers

All helpers take a valid handle and a bar `shift`. Use `shift=1` (last closed bar) unless your strategy needs the live bar. Return `false` on `CopyBuffer` failure — always check.

```cpp
// RSI
double rsi;
if(!GetRSI(handle, 1, rsi)) return;

// Bollinger Bands
double upper, mid, lower;
if(!GetBB(handle, 1, upper, mid, lower)) return;

// MACD
double macdMain, macdSignal;
if(!GetMACD(handle, 1, macdMain, macdSignal)) return;

// Ichimoku
double tenkan, kijun, spA, spB, chikou;
if(!GetIchimoku(handle, 1, tenkan, kijun, spA, spB, chikou)) return;
```

---

## CloseAllPositions

```cpp
CloseAllPositions();                        // everything
CloseAllPositions(POSITION_TYPE_BUY);       // longs only
CloseAllPositions(POSITION_TYPE_SELL);      // shorts only
```

---

## Notes

- `IsNewBar` uses one static variable — only call it with a single TF per EA. For two-TF checks, keep a separate `prevTime` for each.
- `TrailSL` runs before the new-bar gate so it reacts to every tick, not just new bars.
- Gold needs `InpMaxSpreadPoints` ~800+. EUR/USD can sit at 30. Don't leave the default on a new instrument.
- Always backtest at least 2 years before forward testing.

---
