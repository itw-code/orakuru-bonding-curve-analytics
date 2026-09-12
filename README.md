# Orakuru On-Chain Analytics & Bonding Curve Intelligence Suite

**Author**: Ihsan Tri Wanda ([GitHub: @itw-code](https://github.com/itw-code) · [LinkedIn](https://www.linkedin.com/in/ihsan3wanda/))  
**Target Protocol**: [Orakuru Network](https://orakuru.network/)  
**Architecture**: Production-grade dbt & DuckDB data pipeline, Kimball dimensional marts, and Dune Analytics V2 queries engineered to model bonding curve performance, wallet clustering, and token velocity across protocol launches.  

---

## 🎯 Purpose & Scope

Orakuru is building the next-generation decentralized bonding launchpad. In high-velocity bonding curve environments, raw blockchain logs are noisy, bot-distorted, and hard for non-technical stakeholders to interpret. 

This repository provides **analytics engineering rigor** for on-chain data:
1. **Bonding Curve Engine**: Tracks virtual AMM reserves ($x \cdot y = k$), real-time spot price, slippage, and graduation fill % towards DEX migration.
2. **Wallet Forensic Clustering**: Identifies MEV/bot snipers in blocks 0–2 of launch, monitors creator/dev wallet behavior, and calculates token supply concentration (Herfindahl-Hirschman Index / HHI).
3. **Token Velocity Metrics**: Calculates daily rolling token velocity ($V = \text{Volume} / \text{Market Cap}$), turnover ratios, and trader retention cohorts to predict post-launch liquidity durability.

---

## 🏛️ Data Architecture & Lineage

The pipeline follows the Kimball dimensional modeling methodology with clean data contracts:

```
[ Raw Blockchain Logs ]
  - raw_bonding_curve_events (CurveCreated, CurveGraduated, Sync)
  - raw_bonding_curve_swaps (Buy, Sell, Fees, Gas)
  - raw_token_transfers (ERC20 / BRC-20 Transfer events)
           │
           ▼
[ Staging Layer (Views) ]
  - stg_orakuru__bonding_swaps
  - stg_orakuru__curve_events
  - stg_orakuru__token_transfers
           │
           ▼
[ Intermediate Layer (State & Feature Engineering) ]
  - int_bonding_curve_state (Virtual reserves, spot price, fill %, slippage)
  - int_wallet_clustering (Block delta sniper detection, whale HHI, dev tracking)
  - int_token_velocity (Rolling volume, implied MCap, velocity index, turnover)
           │
           ▼
[ Marts Layer (Kimball Star Schema) ]
  - fct_bonding_trades (Grain: 1 row per swap with trader cohort & execution metrics)
  - fct_curve_daily_performance (Grain: 1 row per curve per day)
  - dim_wallets (Grain: 1 row per unique wallet address with lifetime PnL & cohort)
  - dim_tokens (Grain: 1 row per launched token with graduation & sniper penetration)
```

---

## 📐 Mathematical Foundations

### 1. Virtual AMM Bonding Curve State
Let $x_0$ and $y_0$ be initial virtual base reserves and virtual token reserves:
$$k = x_0 \cdot y_0$$
At any trade $t$, with net base assets collected $\Delta x_t$ and net tokens sold $\Delta y_t$:
$$x_t = x_0 + \Delta x_t$$
$$y_t = y_0 - \Delta y_t$$
$$\text{Instantaneous Spot Price } P_t = \frac{x_t}{y_t}$$
$$\text{Curve Fill \%} = \min\left(100.0, \frac{\Delta x_t}{\text{Graduation Threshold Base}} \times 100.0\right)$$

### 2. Token Velocity Index ($V$)
$$V = \frac{\text{24h Trading Volume (Base)}}{\text{Circulating Market Cap (Base)}}$$
- $V > 2.0$: **Hyper-Velocity** (Bot churn / high dump risk)
- $0.5 \le V \le 2.0$: **Healthy Circulation** (Organic trading depth)
- $V < 0.1$: **Stagnant Liquidity** (High risk of graduation failure)

### 3. Supply Concentration (Herfindahl-Hirschman Index / HHI)
$$\text{HHI} = \sum_{i=1}^{N} s_i^2$$
where $s_i$ is the percentage of supply held by holder $i$. An $\text{HHI} > 2,500$ triggers a cabal/whale centralization warning.

---

## 📊 Dune Analytics V2 Production Queries

Found in [`dune_queries/`](dune_queries/):
1. [`01_bonding_curve_realtime_monitor.sql`](dune_queries/01_bonding_curve_realtime_monitor.sql): Real-time fill % and virtual reserves ladder.
2. [`02_wallet_clustering_and_snipers.sql`](dune_queries/02_wallet_clustering_and_snipers.sql): Block 0–2 sniper identification and top-10 concentration.
3. [`03_token_velocity_and_health.sql`](dune_queries/03_token_velocity_and_health.sql): Velocity index, turnover ratios, and retention cohorts.

---

## 🧪 Verification & Invariant Testing

A standalone verification suite [`test_pipeline.py`](test_pipeline.py) runs the entire pipeline end-to-end in an in-memory DuckDB instance:

```bash
python test_pipeline.py
```

### Verified Business Invariants:
1. **Graduation Invariant**: Tokens reaching 100% threshold trigger `GRADUATED` status with zero math drift.
2. **Sniper Invariant**: Addresses buying in blocks $\le 2$ relative to creation are deterministically isolated and tagged.
3. **Whale Segmentation**: Large capital allocators are segmented to monitor dump exposure.
4. **Velocity Validity**: Token velocity index is strictly positive and numerically stable.
5. **Kimball Grain Integrity**: Zero duplicate keys or fan-out in dimensional marts.
