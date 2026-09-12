-- Mart Dimension table: dim_wallets
-- Grain: 1 row per unique wallet address across launches

with wallet_metrics as (
    select
        trader_address,
        count(distinct curve_address) as unique_curves_traded,
        count(distinct token_address) as unique_tokens_traded,
        min(first_trade_timestamp) as wallet_first_active_time,
        max(last_trade_timestamp) as wallet_last_active_time,
        sum(buy_count) as lifetime_buy_count,
        sum(sell_count) as lifetime_sell_count,
        sum(total_base_invested) as lifetime_base_invested,
        sum(total_base_realized) as lifetime_base_realized,
        sum(net_realized_pnl_base) as lifetime_net_pnl_base,
        max(is_sniper) as ever_sniped,
        max(is_creator) as is_protocol_or_dev,
        -- Primary cohort based on dominant behavior
        case 
            when max(is_creator) = 1 then 'DEV_TEAM'
            when max(is_sniper) = 1 then 'SNIPER'
            when sum(total_base_invested) >= 25.0 then 'WHALE'
            when sum(buy_count) >= 5 and sum(sell_count) >= 5 then 'HIGH_FREQUENCY_TRADER'
            when sum(buy_count) >= 1 and sum(sell_count) = 0 then 'ACCUMULATOR'
            else 'RETAIL_ORGANIC'
        end as primary_wallet_segment
    from {{ ref('int_wallet_clustering') }}
    group by trader_address
)

select
    trader_address,
    unique_curves_traded,
    unique_tokens_traded,
    wallet_first_active_time,
    wallet_last_active_time,
    lifetime_buy_count,
    lifetime_sell_count,
    round(lifetime_base_invested, 4) as lifetime_base_invested,
    round(lifetime_base_realized, 4) as lifetime_base_realized,
    round(lifetime_net_pnl_base, 4) as lifetime_net_pnl_base,
    ever_sniped,
    is_protocol_or_dev,
    primary_wallet_segment,
    case 
        when lifetime_net_pnl_base > 0 then 'PROFITABLE'
        when lifetime_net_pnl_base < 0 then 'UNPROFITABLE'
        else 'BREAKEVEN'
    end as profitability_status
from wallet_metrics
