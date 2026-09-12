-- Mart Fact table: fct_curve_daily_performance
-- Grain: 1 row per curve per day

with velocity as (
    select * from {{ ref('int_token_velocity') }}
),

sniper_volume as (
    select
        token_address,
        curve_address,
        cast(strftime(cast(block_timestamp as timestamp), '%Y-%m-%d') as varchar) as trade_date,
        sum(case when trader_cohort = 'SNIPER' then base_asset_amount else 0 end) as sniper_volume_base,
        sum(case when trader_cohort = 'SNIPER' then 1 else 0 end) as sniper_tx_count
    from {{ ref('fct_bonding_trades') }}
    group by 1, 2, 3
)

select
    v.token_address,
    v.curve_address,
    v.trade_date,
    v.tx_count,
    v.unique_active_traders,
    v.daily_volume_base,
    coalesce(sv.sniper_volume_base, 0) as sniper_volume_base,
    case 
        when v.daily_volume_base > 0 
        then round((coalesce(sv.sniper_volume_base, 0) / v.daily_volume_base) * 100.0, 2)
        else 0.0 
    end as sniper_volume_share_pct,
    v.daily_tokens_traded,
    v.avg_daily_price,
    v.close_price,
    v.implied_market_cap_base,
    v.end_of_day_curve_fill_pct,
    v.token_velocity_index,
    v.turnover_rate_pct,
    v.velocity_health_tier,
    v.curve_status
from velocity v
left join sniper_volume sv
    on v.token_address = sv.token_address
   and v.curve_address = sv.curve_address
   and v.trade_date = sv.trade_date
