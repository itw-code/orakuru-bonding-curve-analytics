-- Mart Dimension table: dim_tokens
-- Grain: 1 row per launched token on Orakuru

with curve_meta as (
    select
        token_address,
        curve_address,
        creator_address,
        initial_token_supply,
        virtual_base_reserves,
        virtual_token_reserves,
        graduation_threshold_base,
        block_timestamp as creation_timestamp,
        block_number as creation_block
    from {{ ref('stg_orakuru__curve_events') }}
    where event_type = 'CurveCreated'
),

lifetime_aggregates as (
    select
        token_address,
        curve_address,
        count(distinct tx_hash) as total_trades,
        count(distinct trader_address) as total_unique_traders,
        sum(base_asset_amount) as lifetime_volume_base,
        sum(protocol_fee_amount) as lifetime_protocol_fees_base,
        max(cumulative_base_collected) as final_base_collected,
        max(curve_fill_pct) as max_fill_pct,
        max(curve_status) as current_status,
        max(spot_price_after_trade) as all_time_high_price
    from {{ ref('fct_bonding_trades') }}
    group by token_address, curve_address
),

sniper_stats as (
    select
        token_address,
        curve_address,
        count(distinct case when is_sniper = 1 then trader_address end) as sniper_count,
        sum(case when is_sniper = 1 then base_asset_amount else 0 end) as sniper_volume_base
    from {{ ref('fct_bonding_trades') }}
    group by token_address, curve_address
)

select
    m.token_address,
    m.curve_address,
    m.creator_address,
    m.creation_timestamp,
    m.creation_block,
    m.initial_token_supply,
    m.graduation_threshold_base,
    coalesce(l.total_trades, 0) as total_trades,
    coalesce(l.total_unique_traders, 0) as total_unique_traders,
    round(coalesce(l.lifetime_volume_base, 0), 4) as lifetime_volume_base,
    round(coalesce(l.lifetime_protocol_fees_base, 0), 4) as lifetime_protocol_fees_base,
    round(coalesce(l.final_base_collected, 0), 4) as current_base_in_curve,
    coalesce(l.max_fill_pct, 0.0) as curve_fill_pct,
    coalesce(l.current_status, 'ACTIVE') as curve_status,
    round(coalesce(l.all_time_high_price, 0), 8) as all_time_high_price,
    coalesce(s.sniper_count, 0) as total_snipers_detected,
    case 
        when coalesce(l.lifetime_volume_base, 0) > 0 
        then round((coalesce(s.sniper_volume_base, 0) / l.lifetime_volume_base) * 100.0, 2)
        else 0.0 
    end as sniper_volume_penetration_pct
from curve_meta m
left join lifetime_aggregates l
    on m.token_address = l.token_address
   and m.curve_address = l.curve_address
left join sniper_stats s
    on m.token_address = s.token_address
   and m.curve_address = s.curve_address
