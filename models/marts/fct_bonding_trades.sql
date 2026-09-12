-- Mart Fact table: fct_bonding_trades
-- Grain: 1 row per bonding curve swap transaction

with trades as (
    select * from {{ ref('int_bonding_curve_state') }}
),

wallets as (
    select 
        token_address,
        curve_address,
        trader_address,
        behavioral_cohort,
        is_sniper,
        is_creator
    from {{ ref('int_wallet_clustering') }}
)

select
    t.tx_hash,
    t.block_number,
    t.block_timestamp,
    t.token_address,
    t.curve_address,
    t.trader_address,
    w.behavioral_cohort as trader_cohort,
    w.is_sniper,
    w.is_creator,
    t.trade_type,
    t.base_asset_amount,
    t.token_amount,
    t.protocol_fee_amount,
    t.gas_price_gwei,
    t.tx_index,
    t.execution_price,
    t.spot_price_after_trade,
    t.slippage_pct,
    t.cumulative_base_collected,
    t.curve_fill_pct,
    t.curve_status
from trades t
left join wallets w
    on t.token_address = w.token_address
   and t.curve_address = w.curve_address
   and t.trader_address = w.trader_address
