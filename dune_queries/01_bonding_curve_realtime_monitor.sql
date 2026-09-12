-- ==============================================================================
-- DUNE ANALYTICS V2 / TRINO QUERY: 01_bonding_curve_realtime_monitor.sql
-- Title: Orakuru Bonding Curve Real-Time Liquidity & Graduation Health Monitor
-- Author: Ihsan Tri Wanda (@itw-code)
-- Description: Tracks real-time bonding curve fill %, virtual AMM reserves,
--              instantaneous spot price, and projected graduation time across launches.
-- ==============================================================================

with raw_swaps as (
    -- Replace with actual decoded Orakuru contract table on Base / BSC / Bitcoin Layer:
    -- e.g. orakuru_base.BondingCurve_evt_Swap
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
        fee_amount / 1e18 as protocol_fee
    from {{source_bonding_swaps}}
),

curve_meta as (
    select
        contract_address as curve_address,
        token_address,
        creator as creator_address,
        initial_token_supply / 1e18 as initial_token_supply,
        virtual_base_reserves / 1e18 as virtual_base_reserves,
        virtual_token_reserves / 1e18 as virtual_token_reserves,
        graduation_threshold_base / 1e18 as graduation_threshold_base,
        evt_block_time as creation_time
    from {{source_bonding_curve_created}}
),

cumulative_metrics as (
    select
        s.tx_hash,
        s.block_time,
        s.curve_address,
        s.token_address,
        s.trader_address,
        s.is_buy,
        s.base_asset_amount,
        s.token_amount,
        sum(case when s.is_buy then s.base_asset_amount else -s.base_asset_amount end) over (
            partition by s.curve_address 
            order by s.block_time, s.tx_hash
            rows between unbounded preceding and current row
        ) as net_base_collected,
        sum(case when s.is_buy then s.token_amount else -s.token_amount end) over (
            partition by s.curve_address 
            order by s.block_time, s.tx_hash
            rows between unbounded preceding and current row
        ) as net_tokens_sold
    from raw_swaps s
),

latest_curve_state as (
    select
        m.token_address,
        m.curve_address,
        m.creator_address,
        m.creation_time,
        m.graduation_threshold_base,
        c.block_time as last_trade_time,
        c.net_base_collected,
        c.net_tokens_sold,
        (m.virtual_base_reserves + c.net_base_collected) as current_virtual_base,
        (m.virtual_token_reserves - c.net_tokens_sold) as current_virtual_tokens,
        -- Real-time spot price P = x / y
        (m.virtual_base_reserves + c.net_base_collected) / nullif((m.virtual_token_reserves - c.net_tokens_sold), 0) as current_spot_price,
        -- Progress % towards DEX graduation threshold
        round(
            least(100.0, greatest(0.0, (c.net_base_collected / nullif(m.graduation_threshold_base, 0)) * 100.0)),
            2
        ) as curve_fill_pct,
        row_number() over (partition by m.curve_address order by c.block_time desc) as rn
    from curve_meta m
    inner join cumulative_metrics c 
        on m.curve_address = c.curve_address
)

select
    token_address,
    curve_address,
    creator_address,
    creation_time,
    last_trade_time,
    date_diff('minute', creation_time, last_trade_time) as curve_age_minutes,
    round(current_spot_price, 8) as spot_price_base,
    round(net_base_collected, 4) as total_base_locked,
    round(graduation_threshold_base, 4) as graduation_target_base,
    round(graduation_threshold_base - net_base_collected, 4) as base_remaining_to_graduate,
    curve_fill_pct,
    case 
        when curve_fill_pct >= 100.0 then 'GRADUATED_TO_DEX'
        when curve_fill_pct >= 80.0 then 'HIGH_GRADUATION_VELOCITY'
        when curve_fill_pct >= 30.0 then 'ACCUMULATING'
        else 'EARLY_STAGE'
    end as lifecycle_status
from latest_curve_state
where rn = 1
order by curve_fill_pct desc, total_base_locked desc;
