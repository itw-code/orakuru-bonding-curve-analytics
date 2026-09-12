-- Intermediate model: int_token_velocity
-- Computes daily rolling token velocity, turnover ratio, and liquidity metrics across launches

with daily_trades as (
    select
        token_address,
        curve_address,
        cast(strftime(cast(block_timestamp as timestamp), '%Y-%m-%d') as varchar) as trade_date,
        count(distinct tx_hash) as tx_count,
        count(distinct trader_address) as unique_active_traders,
        sum(base_asset_amount) as daily_volume_base,
        sum(token_amount) as daily_tokens_traded,
        avg(spot_price_after_trade) as avg_daily_price,
        max(spot_price_after_trade) as close_price,
        max(curve_fill_pct) as end_of_day_curve_fill_pct,
        max(curve_status) as curve_status
    from {{ ref('int_bonding_curve_state') }}
    group by 1, 2, 3
),

token_supplies as (
    select
        token_address,
        curve_address,
        max(initial_token_supply) as total_token_supply
    from {{ ref('stg_orakuru__curve_events') }}
    where event_type = 'CurveCreated'
    group by 1, 2
),

velocity_metrics as (
    select
        d.token_address,
        d.curve_address,
        d.trade_date,
        d.tx_count,
        d.unique_active_traders,
        d.daily_volume_base,
        d.daily_tokens_traded,
        d.avg_daily_price,
        d.close_price,
        d.end_of_day_curve_fill_pct,
        d.curve_status,
        s.total_token_supply,
        -- Market cap in base asset terms: Total Supply * Close Price
        round(s.total_token_supply * d.close_price, 4) as implied_market_cap_base,
        -- Token Turnover: Tokens traded / Total token supply
        round((d.daily_tokens_traded / nullif(s.total_token_supply, 0)) * 100.0, 4) as turnover_rate_pct,
        -- Token Velocity V = Trading Volume / Market Cap
        case 
            when (s.total_token_supply * d.close_price) > 0 
            then round(d.daily_volume_base / (s.total_token_supply * d.close_price), 4)
            else 0.0 
        end as token_velocity_index
    from daily_trades d
    inner join token_supplies s 
        on d.curve_address = s.curve_address
)

select
    *,
    case 
        when token_velocity_index >= 2.0 then 'HYPER_VELOCITY'
        when token_velocity_index >= 0.5 then 'HEALTHY_CIRCULATION'
        when token_velocity_index >= 0.1 then 'MODERATE_VELOCITY'
        else 'STAGNANT_LIQUIDITY'
    end as velocity_health_tier
from velocity_metrics
