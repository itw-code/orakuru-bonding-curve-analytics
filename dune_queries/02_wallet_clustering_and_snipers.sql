-- ==============================================================================
-- DUNE ANALYTICS V2 / TRINO QUERY: 02_wallet_clustering_and_snipers.sql
-- Title: Orakuru Wallet Clustering, Sniper Detection & Whale Concentration Analysis
-- Author: Ihsan Tri Wanda (@itw-code)
-- Description: Identifies MEV/bot snipers in blocks 0-2 of launch, classifies
--              insider dev holdings, and computes wallet concentration metrics (HHI).
-- ==============================================================================

with curve_meta as (
    select
        contract_address as curve_address,
        token_address,
        creator as creator_address,
        evt_block_number as creation_block,
        evt_block_time as creation_time,
        initial_token_supply / 1e18 as total_supply
    from {{source_bonding_curve_created}}
),

swaps as (
    select
        evt_tx_hash as tx_hash,
        evt_block_number as block_number,
        evt_block_time as block_time,
        contract_address as curve_address,
        token_address,
        trader as trader_address,
        is_buy,
        base_asset_amount / 1e18 as base_asset_amount,
        token_amount / 1e18 as token_amount,
        gas_price / 1e9 as gas_price_gwei
    from {{source_bonding_swaps}}
),

wallet_trade_summary as (
    select
        s.curve_address,
        s.token_address,
        s.trader_address,
        m.creator_address,
        m.total_supply,
        min(s.block_number) as first_block_traded,
        m.creation_block,
        min(s.block_number) - m.creation_block as sniper_block_delta,
        count(case when s.is_buy then 1 end) as buy_tx_count,
        count(case when not s.is_buy then 1 end) as sell_tx_count,
        sum(case when s.is_buy then s.base_asset_amount else 0 end) as total_base_invested,
        sum(case when not s.is_buy then s.base_asset_amount else 0 end) as total_base_realized,
        sum(case when s.is_buy then s.token_amount else -s.token_amount end) as current_token_balance,
        max(s.gas_price_gwei) as peak_gas_gwei
    from swaps s
    inner join curve_meta m 
        on s.curve_address = m.curve_address
    group by 
        s.curve_address,
        s.token_address,
        s.trader_address,
        m.creator_address,
        m.total_supply,
        m.creation_block
),

classified_wallets as (
    select
        w.*,
        round(w.total_base_realized - w.total_base_invested, 4) as net_pnl_base,
        round((w.current_token_balance / nullif(w.total_supply, 0)) * 100.0, 4) as pct_supply_held,
        case
            when w.trader_address = w.creator_address then 'DEV_TEAM_WALLET'
            when w.sniper_block_delta <= 1 then 'BLOCK_0_1_MEV_SNIPER'
            when w.sniper_block_delta <= 5 then 'EARLY_BOT_SNIPER'
            when (w.current_token_balance / nullif(w.total_supply, 0)) >= 0.02 then 'WHALE_HOLDER'
            when w.buy_tx_count >= 2 and w.sell_tx_count >= 2 then 'HIGH_FREQUENCY_TRADER'
            when w.buy_tx_count >= 1 and w.sell_tx_count = 0 then 'ORGANIC_ACCUMULATOR'
            else 'RETAIL_ORGANIC'
        end as wallet_cohort
    from wallet_trade_summary w
),

token_concentration as (
    -- Herfindahl-Hirschman Index (HHI) for supply concentration
    select
        curve_address,
        token_address,
        count(distinct trader_address) as unique_holders,
        sum(case when wallet_cohort in ('BLOCK_0_1_MEV_SNIPER', 'EARLY_BOT_SNIPER') then 1 else 0 end) as sniper_count,
        sum(case when wallet_cohort in ('BLOCK_0_1_MEV_SNIPER', 'EARLY_BOT_SNIPER') then current_token_balance else 0 end) as sniper_held_tokens,
        -- Top 10 holder share
        sum(case when row_num <= 10 then pct_supply_held else 0 end) as top_10_holder_supply_pct,
        -- HHI sum of squares of market shares (0 - 10,000)
        round(sum(power(greatest(0.0, pct_supply_held), 2)), 2) as concentration_hhi
    from (
        select
            *,
            row_number() over (partition by curve_address order by current_token_balance desc) as row_num
        from classified_wallets
        where current_token_balance > 0
    )
    group by curve_address, token_address
)

select
    c.token_address,
    c.curve_address,
    c.unique_holders,
    c.sniper_count,
    round(c.top_10_holder_supply_pct, 2) as top_10_supply_pct,
    c.concentration_hhi,
    case
        when c.concentration_hhi > 2500 then 'HIGH_CENTRALIZATION_RISK (WHALE / CABAL)'
        when c.concentration_hhi > 1500 then 'MODERATE_CONCENTRATION'
        else 'HEALTHY_DECENTRALIZED_DISTRIBUTION'
    end as distribution_health
from token_concentration c
order by c.top_10_holder_supply_pct desc;
