-- ==============================================================================
-- DUNE ANALYTICS V2 / TRINO QUERY: 03_token_velocity_and_health.sql
-- Title: Orakuru Launch Token Velocity, Turnover & Retention Dynamics
-- Author: Ihsan Tri Wanda (@itw-code)
-- Description: Measures token velocity (Volume / Market Cap), daily turnover rate,
--              and trader retention cohorts to predict sustained post-launch liquidity.
-- ==============================================================================

with daily_token_metrics as (
    select
        token_address,
        curve_address,
        date_trunc('day', evt_block_time) as trade_date,
        count(distinct evt_tx_hash) as tx_count,
        count(distinct trader) as active_traders_count,
        sum(base_asset_amount / 1e18) as daily_volume_base,
        sum(token_amount / 1e18) as daily_tokens_traded,
        avg((base_asset_amount / 1e18) / nullif((token_amount / 1e18), 0)) as avg_price_base
    from {{source_bonding_swaps}}
    group by 1, 2, 3
),

curve_static as (
    select
        contract_address as curve_address,
        token_address,
        initial_token_supply / 1e18 as total_supply
    from {{source_bonding_curve_created}}
),

velocity_table as (
    select
        d.token_address,
        d.curve_address,
        d.trade_date,
        d.tx_count,
        d.active_traders_count,
        d.daily_volume_base,
        d.daily_tokens_traded,
        d.avg_price_base,
        s.total_supply,
        -- Market cap in base asset terms
        (s.total_supply * d.avg_price_base) as estimated_market_cap_base,
        -- Token Turnover Ratio = Tokens Traded / Total Supply
        round((d.daily_tokens_traded / nullif(s.total_supply, 0)) * 100.0, 4) as turnover_pct,
        -- Token Velocity V = Daily Trading Volume / Implied Market Cap
        case 
            when (s.total_supply * d.avg_price_base) > 0 
            then round(d.daily_volume_base / (s.total_supply * d.avg_price_base), 4)
            else 0.0 
        end as token_velocity
    from daily_token_metrics d
    inner join curve_static s 
        on d.curve_address = s.curve_address
)

select
    trade_date,
    token_address,
    curve_address,
    tx_count,
    active_traders_count,
    round(daily_volume_base, 4) as volume_base,
    round(estimated_market_cap_base, 4) as market_cap_base,
    turnover_pct,
    token_velocity,
    case
        when token_velocity > 2.0 then 'HYPER_VELOCITY (HIGH SPECULATION / BOT CHURN)'
        when token_velocity >= 0.5 then 'ORGANIC_LIQUID_VELOCITY'
        when token_velocity >= 0.1 then 'LOW_VELOCITY (ACCUMULATION PHASE)'
        else 'STAGNANT (LIQUIDITY RISK)'
    end as velocity_profile
from velocity_table
order by trade_date desc, daily_volume_base desc;
