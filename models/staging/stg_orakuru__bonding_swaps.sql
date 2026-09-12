-- Staging model: stg_orakuru__bonding_swaps
-- Decodes buy and sell events emitted by Orakuru bonding curve contracts.

with raw_swaps as (
    select
        tx_hash,
        block_number,
        block_timestamp,
        token_address,
        curve_address,
        trader_address,
        trade_type, -- 'BUY' or 'SELL'
        cast(base_asset_amount as double) as base_asset_amount, -- e.g. BNB, ETH, BTC, or USD equivalent
        cast(token_amount as double) as token_amount,
        cast(protocol_fee_amount as double) as protocol_fee_amount,
        cast(gas_price_gwei as double) as gas_price_gwei,
        cast(tx_index as integer) as tx_index
    from {{ ref('raw_bonding_curve_swaps') }}
),

validated as (
    select
        tx_hash,
        block_number,
        block_timestamp,
        lower(token_address) as token_address,
        lower(curve_address) as curve_address,
        lower(trader_address) as trader_address,
        upper(trade_type) as trade_type,
        base_asset_amount,
        token_amount,
        protocol_fee_amount,
        gas_price_gwei,
        tx_index,
        case 
            when token_amount > 0 then base_asset_amount / token_amount 
            else 0.0 
        end as execution_price
    from raw_swaps
    where token_amount > 0 and base_asset_amount >= 0
)

select * from validated
