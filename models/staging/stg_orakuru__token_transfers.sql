-- Staging model: stg_orakuru__token_transfers
-- Decodes ERC20 / BRC-20 / Layer token transfer events for velocity & wallet balance tracking

with raw_transfers as (
    select
        tx_hash,
        block_number,
        block_timestamp,
        token_address,
        from_address,
        to_address,
        cast(amount as double) as amount
    from {{ ref('raw_token_transfers') }}
),

normalized as (
    select
        tx_hash,
        block_number,
        block_timestamp,
        lower(token_address) as token_address,
        lower(from_address) as from_address,
        lower(to_address) as to_address,
        amount
    from raw_transfers
    where amount > 0
      and lower(from_address) != lower(to_address)
)

select * from normalized
