-- Intermediate model: int_wallet_clustering
-- Classifies wallet behavior across Orakuru launches: snipers, bots, dev wallets, whales, retail

with trades as (
    select * from {{ ref('int_bonding_curve_state') }}
),

curve_creators as (
    select distinct curve_address, creator_address
    from {{ ref('int_bonding_curve_state') }}
),

wallet_metrics as (
    select
        t.token_address,
        t.curve_address,
        t.trader_address,
        min(t.block_timestamp) as first_trade_timestamp,
        max(t.block_timestamp) as last_trade_timestamp,
        min(t.block_number) as first_trade_block,
        min(t.creation_block) as curve_creation_block,
        -- Block delta from creation (0 = same block snipe)
        min(t.block_number) - min(t.creation_block) as blocks_since_curve_creation,
        count(case when t.trade_type = 'BUY' then 1 end) as buy_count,
        count(case when t.trade_type = 'SELL' then 1 end) as sell_count,
        sum(case when t.trade_type = 'BUY' then t.base_asset_amount else 0 end) as total_base_invested,
        sum(case when t.trade_type = 'SELL' then t.base_asset_amount else 0 end) as total_base_realized,
        sum(case when t.trade_type = 'BUY' then t.token_amount else -t.token_amount end) as current_token_balance,
        max(t.gas_price_gwei) as max_gas_gwei,
        avg(t.gas_price_gwei) as avg_gas_gwei
    from trades t
    group by t.token_address, t.curve_address, t.trader_address
),

with_classification as (
    select
        wm.*,
        cc.creator_address,
        case when wm.trader_address = cc.creator_address then 1 else 0 end as is_creator,
        case when wm.blocks_since_curve_creation <= 2 then 1 else 0 end as is_sniper,
        case when wm.current_token_balance > 0 and wm.sell_count = 0 then 1 else 0 end as is_accumulator,
        case 
            when wm.trader_address = cc.creator_address then 'DEV_TEAM'
            when wm.blocks_since_curve_creation <= 2 then 'SNIPER'
            when wm.total_base_invested >= 10.0 then 'WHALE'
            when wm.buy_count >= 2 and wm.sell_count >= 2 then 'SWING_TRADER'
            when wm.buy_count >= 1 and wm.sell_count >= 1 and wm.current_token_balance <= 0 then 'PAPER_HANDS'
            when wm.buy_count >= 1 and wm.sell_count = 0 then 'DIAMOND_HANDS'
            else 'RETAIL_ORGANIC'
        end as behavioral_cohort,
        round(wm.total_base_realized - wm.total_base_invested, 4) as net_realized_pnl_base
    from wallet_metrics wm
    left join curve_creators cc 
        on wm.curve_address = cc.curve_address
)

select * from with_classification
