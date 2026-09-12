#!/usr/bin/env python3
"""
Orakuru On-Chain Analytics Pipeline Validation Suite
Author: Ihsan Tri Wanda
Description: Initializes DuckDB in-memory, scaffolds raw blockchain event tables,
             loads realistic synthetic bonding curve transactions, runs all staging,
             intermediate, and mart transformations, and rigorously tests business invariants.
"""

import duckdb
import sys
from datetime import datetime, timedelta

def run_validation():
    print("==================================================================")
    print("🚀 Starting Orakuru Analytics Pipeline Invariant & Schema Validation")
    print("==================================================================")

    con = duckdb.connect(database=":memory:")

    # 1. Create Raw Tables
    print("Creating raw event tables...")
    con.execute("""
    create table raw_bonding_curve_events (
        event_id varchar primary key,
        tx_hash varchar,
        block_number bigint,
        block_timestamp timestamp,
        token_address varchar,
        curve_address varchar,
        event_type varchar,
        creator_address varchar,
        initial_token_supply double,
        virtual_base_reserves double,
        virtual_token_reserves double,
        graduation_threshold_base double
    );
    """)

    con.execute("""
    create table raw_bonding_curve_swaps (
        tx_hash varchar primary key,
        block_number bigint,
        block_timestamp timestamp,
        token_address varchar,
        curve_address varchar,
        trader_address varchar,
        trade_type varchar,
        base_asset_amount double,
        token_amount double,
        protocol_fee_amount double,
        gas_price_gwei double,
        tx_index integer
    );
    """)

    con.execute("""
    create table raw_token_transfers (
        tx_hash varchar,
        block_number bigint,
        block_timestamp timestamp,
        token_address varchar,
        from_address varchar,
        to_address varchar,
        amount double
    );
    """)

    # 2. Populate Synthetic Data
    # Token 1: Graduated Token ($NOVA) - reaches 100% fill
    # Token 2: Active Accumulating Token ($PHANTOM) - ~45% fill
    base_time = datetime(2026, 9, 10, 12, 0, 0)

    print("Inserting synthetic curve creation events...")
    con.execute(f"""
    insert into raw_bonding_curve_events values
    ('evt_1', '0x101', 1000, '{base_time}', '0xnova', '0xcurve_nova', 'CurveCreated', '0xcreator_alice', 1000000000.0, 30.0, 1073000000.0, 85.0),
    ('evt_2', '0x102', 2000, '{base_time + timedelta(hours=2)}', '0xphantom', '0xcurve_phantom', 'CurveCreated', '0xcreator_bob', 1000000000.0, 30.0, 1073000000.0, 85.0);
    """)

    print("Inserting synthetic trades (snipers, bots, dev, retail)...")
    # Block 1000: Creation of NOVA
    # Block 1001: Sniper 1 (0xsniper_1) buys 10 BNB
    # Block 1002: Sniper 2 (0xsniper_2) buys 15 BNB
    # Block 1050: Retail organic buyers
    # Block 1100: Whale (0xwhale_1) buys 60 BNB -> reaches graduation!
    swaps_data = [
        # NOVA trades
        ('0xsw_1', 1001, base_time + timedelta(seconds=12), '0xnova', '0xcurve_nova', '0xsniper_1', 'BUY', 10.0, 150000000.0, 0.1, 150.0, 1),
        ('0xsw_2', 1002, base_time + timedelta(seconds=24), '0xnova', '0xcurve_nova', '0xsniper_2', 'BUY', 15.0, 200000000.0, 0.15, 180.0, 1),
        ('0xsw_3', 1020, base_time + timedelta(minutes=5), '0xnova', '0xcurve_nova', '0xretail_1', 'BUY', 2.0, 25000000.0, 0.02, 30.0, 2),
        ('0xsw_4', 1040, base_time + timedelta(minutes=10), '0xnova', '0xcurve_nova', '0xretail_2', 'BUY', 3.0, 35000000.0, 0.03, 30.0, 1),
        ('0xsw_5', 1060, base_time + timedelta(minutes=15), '0xnova', '0xcurve_nova', '0xsniper_1', 'SELL', 8.0, 80000000.0, 0.08, 40.0, 1),
        ('0xsw_6', 1100, base_time + timedelta(hours=1), '0xnova', '0xcurve_nova', '0xwhale_1', 'BUY', 65.0, 300000000.0, 0.65, 50.0, 1),
        # PHANTOM trades
        ('0xsw_7', 2001, base_time + timedelta(hours=2, seconds=12), '0xphantom', '0xcurve_phantom', '0xsniper_1', 'BUY', 12.0, 180000000.0, 0.12, 140.0, 1),
        ('0xsw_8', 2050, base_time + timedelta(hours=2, minutes=15), '0xphantom', '0xcurve_phantom', '0xretail_3', 'BUY', 5.0, 60000000.0, 0.05, 30.0, 1),
        ('0xsw_9', 2100, base_time + timedelta(hours=2, minutes=45), '0xphantom', '0xcurve_phantom', '0xcreator_bob', 'BUY', 20.0, 220000000.0, 0.2, 35.0, 1),
    ]

    for s in swaps_data:
        con.execute(f"""
        insert into raw_bonding_curve_swaps values 
        ('{s[0]}', {s[1]}, '{s[2]}', '{s[3]}', '{s[4]}', '{s[5]}', '{s[6]}', {s[7]}, {s[8]}, {s[9]}, {s[10]}, {s[11]});
        """)

    # 3. Create Staging Views
    print("Building staging views...")
    con.execute("""
    create view stg_orakuru__bonding_swaps as 
    select
        tx_hash,
        block_number,
        block_timestamp,
        lower(token_address) as token_address,
        lower(curve_address) as curve_address,
        lower(trader_address) as trader_address,
        upper(trade_type) as trade_type,
        cast(base_asset_amount as double) as base_asset_amount,
        cast(token_amount as double) as token_amount,
        cast(protocol_fee_amount as double) as protocol_fee_amount,
        cast(gas_price_gwei as double) as gas_price_gwei,
        cast(tx_index as integer) as tx_index,
        case when token_amount > 0 then base_asset_amount / token_amount else 0.0 end as execution_price
    from raw_bonding_curve_swaps
    where token_amount > 0 and base_asset_amount >= 0;
    """)

    con.execute("""
    create view stg_orakuru__curve_events as
    select
        event_id,
        tx_hash,
        block_number,
        block_timestamp,
        lower(token_address) as token_address,
        lower(curve_address) as curve_address,
        event_type,
        lower(creator_address) as creator_address,
        cast(initial_token_supply as double) as initial_token_supply,
        cast(virtual_base_reserves as double) as virtual_base_reserves,
        cast(virtual_token_reserves as double) as virtual_token_reserves,
        cast(graduation_threshold_base as double) as graduation_threshold_base
    from raw_bonding_curve_events;
    """)

    # 4. Create Intermediate Views
    print("Building intermediate models...")
    con.execute("""
    create view int_bonding_curve_state as
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
        from stg_orakuru__curve_events
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
        from stg_orakuru__bonding_swaps
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
            m.virtual_base_reserves + c.cumulative_base_collected as current_virtual_base_reserves,
            m.virtual_token_reserves - c.cumulative_tokens_sold as current_virtual_token_reserves,
            c.cumulative_base_collected,
            m.graduation_threshold_base,
            round(
                least(100.0, greatest(0.0, (c.cumulative_base_collected / nullif(m.graduation_threshold_base, 0)) * 100.0)),
                2
            ) as curve_fill_pct,
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
    from with_slippage;
    """)

    con.execute("""
    create view int_wallet_clustering as
    with trades as (
        select * from int_bonding_curve_state
    ),
    curve_creators as (
        select distinct curve_address, creator_address
        from int_bonding_curve_state
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
                when wm.total_base_invested >= 20.0 then 'WHALE'
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
    select * from with_classification;
    """)

    con.execute("""
    create view int_token_velocity as
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
        from int_bonding_curve_state
        group by 1, 2, 3
    ),
    token_supplies as (
        select
            token_address,
            curve_address,
            max(initial_token_supply) as total_token_supply
        from stg_orakuru__curve_events
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
            round(s.total_token_supply * d.close_price, 4) as implied_market_cap_base,
            round((d.daily_tokens_traded / nullif(s.total_token_supply, 0)) * 100.0, 4) as turnover_rate_pct,
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
    from velocity_metrics;
    """)

    # 5. Create Mart Tables
    print("Building Mart tables...")
    con.execute("""
    create table fct_bonding_trades as
    with trades as (
        select * from int_bonding_curve_state
    ),
    wallets as (
        select 
            token_address,
            curve_address,
            trader_address,
            behavioral_cohort,
            is_sniper,
            is_creator
        from int_wallet_clustering
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
       and t.trader_address = w.trader_address;
    """)

    con.execute("""
    create table dim_wallets as
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
            case 
                when max(is_creator) = 1 then 'DEV_TEAM'
                when max(is_sniper) = 1 then 'SNIPER'
                when sum(total_base_invested) >= 20.0 then 'WHALE'
                when sum(buy_count) >= 5 and sum(sell_count) >= 5 then 'HIGH_FREQUENCY_TRADER'
                when sum(buy_count) >= 1 and sum(sell_count) = 0 then 'ACCUMULATOR'
                else 'RETAIL_ORGANIC'
            end as primary_wallet_segment
        from int_wallet_clustering
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
    from wallet_metrics;
    """)

    con.execute("""
    create table dim_tokens as
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
        from stg_orakuru__curve_events
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
        from fct_bonding_trades
        group by token_address, curve_address
    ),
    sniper_stats as (
        select
            token_address,
            curve_address,
            count(distinct case when is_sniper = 1 then trader_address end) as sniper_count,
            sum(case when is_sniper = 1 then base_asset_amount else 0 end) as sniper_volume_base
        from fct_bonding_trades
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
       and m.curve_address = s.curve_address;
    """)

    # 6. Run Invariant Checks
    print("\n------------------------------------------------------------------")
    print("🧪 Running Data Invariant Assertions...")
    print("------------------------------------------------------------------")

    # Invariant 1: NOVA should have graduated (84 BNB collected >= threshold or 100% fill)
    nova_status = con.execute("select curve_fill_pct, curve_status from dim_tokens where token_address = '0xnova'").fetchone()
    print(f"Assertion 1: NOVA Token Fill & Status -> {nova_status}")
    assert nova_status[0] == 100.0, f"Expected NOVA fill pct 100.0, got {nova_status[0]}"
    assert nova_status[1] == 'GRADUATED', f"Expected NOVA status GRADUATED, got {nova_status[1]}"
    print("✅ Invariant 1 Passed: Graduation calculation accurate.")

    # Invariant 2: Sniper detection
    sniper_check = con.execute("select trader_address, is_sniper, trader_cohort from fct_bonding_trades where trader_address in ('0xsniper_1', '0xsniper_2') limit 2").fetchall()
    print(f"Assertion 2: Sniper Detection -> {sniper_check}")
    for sc in sniper_check:
        assert sc[1] == 1, f"Expected is_sniper=1 for {sc[0]}"
        assert sc[2] == 'SNIPER', f"Expected cohort SNIPER for {sc[0]}"
    print("✅ Invariant 2 Passed: MEV & Early Block Snipers accurately flagged.")

    # Invariant 3: Whale classification
    whale_check = con.execute("select trader_address, primary_wallet_segment from dim_wallets where trader_address = '0xwhale_1'").fetchone()
    print(f"Assertion 3: Whale Classification -> {whale_check}")
    assert whale_check[1] == 'WHALE', f"Expected WHALE segment, got {whale_check[1]}"
    print("✅ Invariant 3 Passed: Whale capital accurately segmented.")

    # Invariant 4: Token velocity index non-null and positive
    velocity_check = con.execute("select token_address, token_velocity_index, turnover_rate_pct, velocity_health_tier from int_token_velocity").fetchall()
    print(f"Assertion 4: Token Velocity Metrics -> {velocity_check}")
    for vc in velocity_check:
        assert vc[1] is not None and vc[1] >= 0, f"Invalid velocity index: {vc}"
        assert vc[2] is not None and vc[2] >= 0, f"Invalid turnover pct: {vc}"
    print("✅ Invariant 4 Passed: Token velocity and turnover metrics valid.")

    # Invariant 5: Dim wallets row count matches unique traders
    unique_traders_raw = con.execute("select count(distinct trader_address) from raw_bonding_curve_swaps").fetchone()[0]
    dim_wallets_count = con.execute("select count(*) from dim_wallets").fetchone()[0]
    print(f"Assertion 5: Wallet Grain Consistency -> Raw: {unique_traders_raw}, Dim: {dim_wallets_count}")
    assert unique_traders_raw == dim_wallets_count, f"Mismatch in wallet grain: {unique_traders_raw} vs {dim_wallets_count}"
    print("✅ Invariant 5 Passed: Kimball dimensional model grain perfectly preserved.")

    print("\n==================================================================")
    print("🎉 ALL 5 PIPELINE INVARIANTS PASSED! Full mathematical & schema parity.")
    print("==================================================================")

if __name__ == "__main__":
    run_validation()
