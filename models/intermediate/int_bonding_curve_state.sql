-- Intermediate model: int_bonding_curve_state
-- Tracks virtual AMM reserves, real-time spot price, curve fill progress %, and slippage

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

swaps as (
    select
        tx_hash,
        block_number,
        block_timestamp,
        token_address,
        curve_address,
        trader_address,
        trade_type,
        base_asset_amount,
        token_amount,
        protocol_fee_amount,
        gas_price_gwei,
        tx_index,
        execution_price,
        case when trade_type = 'BUY' then base_asset_amount else -base_asset_amount end as net_base_delta,
        case when trade_type = 'BUY' then -token_amount else token_amount end as net_token_delta
    from {{ ref('stg_orakuru__bonding_swaps') }}
),

cumulative_swaps as (
    select
        s.*,
        sum(s.net_base_delta) over (
            partition by s.curve_address 
            order by s.block_number, s.tx_index
            rows between unbounded preceding and current row
        ) as cumulative_base_collected,
        sum(-s.net_token_delta) over (
            partition by s.curve_address 
            order by s.block_number, s.tx_index
            rows between unbounded preceding and current row
        ) as cumulative_tokens_sold
    from swaps s
),

curve_state_joined as (
    select
        c.tx_hash,
        c.block_number,
        c.block_timestamp,
        c.token_address,
        c.curve_address,
        m.creator_address,
        m.creation_timestamp,
        m.creation_block,
        c.trader_address,
        c.trade_type,
        c.base_asset_amount,
        c.token_amount,
        c.protocol_fee_amount,
        c.gas_price_gwei,
        c.tx_index,
        c.execution_price,
        -- Reserve calculation: Initial Virtual Reserves + Cumulative delta
        m.virtual_base_reserves + c.cumulative_base_collected as current_virtual_base_reserves,
        m.virtual_token_reserves - c.cumulative_tokens_sold as current_virtual_token_reserves,
        c.cumulative_base_collected,
        m.graduation_threshold_base,
        -- Progress % towards DEX migration graduation
        round(
            least(100.0, greatest(0.0, (c.cumulative_base_collected / nullif(m.graduation_threshold_base, 0)) * 100.0)),
            2
        ) as curve_fill_pct,
        -- Dynamic instantaneous spot price: Virtual Base / Virtual Token
        (m.virtual_base_reserves + c.cumulative_base_collected) / 
            nullif((m.virtual_token_reserves - c.cumulative_tokens_sold), 0) as spot_price_after_trade
    from cumulative_swaps c
    inner join curve_meta m 
        on c.curve_address = m.curve_address
),

with_slippage as (
    select
        cs.*,
        lag(spot_price_after_trade, 1) over (
            partition by curve_address 
            order by block_number, tx_index
        ) as spot_price_before_trade,
        case 
            when curve_fill_pct >= 100.0 then 'GRADUATED'
            else 'ACTIVE'
        end as curve_status
    from curve_state_joined cs
)

select
    tx_hash,
    block_number,
    block_timestamp,
    token_address,
    curve_address,
    creator_address,
    creation_timestamp,
    creation_block,
    trader_address,
    trade_type,
    base_asset_amount,
    token_amount,
    protocol_fee_amount,
    gas_price_gwei,
    tx_index,
    execution_price,
    spot_price_before_trade,
    spot_price_after_trade,
    case 
        when spot_price_before_trade is not null and spot_price_before_trade > 0 
        then round(abs(execution_price - spot_price_before_trade) / spot_price_before_trade * 100.0, 4)
        else 0.0
    end as slippage_pct,
    cumulative_base_collected,
    graduation_threshold_base,
    curve_fill_pct,
    curve_status
from with_slippage
