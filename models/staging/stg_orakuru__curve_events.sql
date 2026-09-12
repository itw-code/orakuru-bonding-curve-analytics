-- Staging model: stg_orakuru__curve_events
-- Decodes lifecycle events: CurveCreated, CurveGraduated, Sync, FeeCollected

with raw_events as (
    select
        event_id,
        tx_hash,
        block_number,
        block_timestamp,
        token_address,
        curve_address,
        event_type, -- 'CurveCreated', 'CurveGraduated', 'FeeCollected'
        creator_address,
        initial_token_supply,
        virtual_base_reserves,
        virtual_token_reserves,
        graduation_threshold_base
    from {{ ref('raw_bonding_curve_events') }}
),

cleaned as (
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
    from raw_events
)

select * from cleaned
