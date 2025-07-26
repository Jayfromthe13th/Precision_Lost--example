module simple_defi::swap {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use std::option::{Self, Option};

    // Error codes
    const EInsufficientLiquidity: u64 = 0;
    const EInvalidFeeRate: u64 = 1;
    const EAmountTooSmall: u64 = 2;

    // Fee rate in basis points (1 basis point = 0.01%)
    const FEE_RATE_BPS: u64 = 30; // 0.3%
    const BASIS_POINTS: u64 = 10000;
    const MINIMUM_FEE: u64 = 1; // Minimum fee to prevent fee evasion

    public struct SwapPool has key {
        id: UID,
        token_a_balance: Balance<0x2::sui::SUI>,
        token_b_balance: Balance<0x2::sui::SUI>,
        fee_balance: Balance<0x2::sui::SUI>,
        total_fees_collected: u64,
    }

    public struct SwapEvent has copy, drop {
        user: address,
        token_in: address,
        token_out: address,
        amount_in: u64,
        amount_out: u64,
        fee_amount: u64,
    }

    public fun create_pool(
        token_a: Coin<0x2::sui::SUI>,
        token_b: Coin<0x2::sui::SUI>,
        ctx: &mut TxContext
    ): (SwapPool, Coin<0x2::sui::SUI>, Coin<0x2::sui::SUI>) {
        let pool = SwapPool {
            id: object::new(ctx),
            token_a_balance: coin::into_balance(token_a),
            token_b_balance: coin::into_balance(token_b),
            fee_balance: balance::zero(),
            total_fees_collected: 0,
        };

        // Return empty coins for the pool creator
        (pool, coin::zero(ctx), coin::zero(ctx))
    }

    public fun swap_a_to_b(
        pool: &mut SwapPool,
        token_a: Coin<0x2::sui::SUI>,
        ctx: &mut TxContext
    ): (Coin<0x2::sui::SUI>, Coin<0x2::sui::SUI>) {
        let amount_in = coin::value(&token_a);
        assert!(amount_in > 0, EAmountTooSmall);

        // Fix precision loss vulnerability with ceiling division
        let fee_amount = if ((amount_in * FEE_RATE_BPS) / BASIS_POINTS == 0) {
            MINIMUM_FEE 
        } else {
            (amount_in * FEE_RATE_BPS) / BASIS_POINTS
        };
        
        let amount_after_fee = amount_in - fee_amount;

        // Calculate output amount using constant product formula
        let amount_out = calculate_output_amount(
            balance::value(&pool.token_a_balance),
            balance::value(&pool.token_b_balance),
            amount_after_fee
        );

        assert!(amount_out > 0, EInsufficientLiquidity);

        // Update pool balances
        balance::join(&mut pool.token_a_balance, coin::into_balance(token_a));
        let output_balance = balance::split(&mut pool.token_b_balance, amount_out);
        
        // Add fees to fee balance
        let fee_balance_split = balance::split(&mut pool.token_a_balance, fee_amount);
        balance::join(&mut pool.fee_balance, fee_balance_split);
        pool.total_fees_collected = pool.total_fees_collected + fee_amount;

        (coin::zero(ctx), coin::from_balance(output_balance, ctx))
    }

    public fun swap_b_to_a(
        pool: &mut SwapPool,
        token_b: Coin<0x2::sui::SUI>,
        ctx: &mut TxContext
    ): (Coin<0x2::sui::SUI>, Coin<0x2::sui::SUI>) {
        let amount_in = coin::value(&token_b);
        assert!(amount_in > 0, EAmountTooSmall);

        // Fix precision loss vulnerability with ceiling division
        let fee_amount = if ((amount_in * FEE_RATE_BPS) / BASIS_POINTS == 0) {
            MINIMUM_FEE 
        } else {
            (amount_in * FEE_RATE_BPS) / BASIS_POINTS
        };
        
        let amount_after_fee = amount_in - fee_amount;

        let amount_out = calculate_output_amount(
            balance::value(&pool.token_b_balance),
            balance::value(&pool.token_a_balance),
            amount_after_fee
        );

        assert!(amount_out > 0, EInsufficientLiquidity);

        // Update pool balances
        balance::join(&mut pool.token_b_balance, coin::into_balance(token_b));
        let output_balance = balance::split(&mut pool.token_a_balance, amount_out);
        
        // Add fees to fee balance
        let fee_balance_split = balance::split(&mut pool.token_b_balance, fee_amount);
        balance::join(&mut pool.fee_balance, fee_balance_split);
        pool.total_fees_collected = pool.total_fees_collected + fee_amount;

        (coin::zero(ctx), coin::from_balance(output_balance, ctx))
    }

    // Constant product formula: (x + dx) * (y - dy) = x * y
    fun calculate_output_amount(
        reserve_in: u64,
        reserve_out: u64,
        amount_in: u64
    ): u64 {
        let amount_in_with_fee = amount_in * (BASIS_POINTS - FEE_RATE_BPS);
        let numerator = amount_in_with_fee * reserve_out;
        let denominator = (reserve_in * BASIS_POINTS) + amount_in_with_fee;
        numerator / denominator
    }

    // Function to withdraw collected fees (only pool owner should call this)
    public fun withdraw_fees(
        pool: &mut SwapPool,
        ctx: &mut TxContext
    ): Coin<0x2::sui::SUI> {
        let fee_balance = balance::value(&pool.fee_balance);
        assert!(fee_balance > 0, EInsufficientLiquidity);
        
        coin::from_balance(balance::split(&mut pool.fee_balance, fee_balance), ctx)
    }

    // Getter functions
    public fun get_pool_info(pool: &SwapPool): (u64, u64, u64) {
        (
            balance::value(&pool.token_a_balance),
            balance::value(&pool.token_b_balance),
            pool.total_fees_collected
        )
    }

    public fun get_fee_rate(): u64 {
        FEE_RATE_BPS
    }


#[spec_only]
use prover::prover::{requires, ensures, asserts, old};

#[spec(prove_focus)]
fun swap_a_to_b_fee_calculation_spec(
    pool: &mut SwapPool,
    token_a: Coin<0x2::sui::SUI>,
    ctx: &mut TxContext
): (Coin<0x2::sui::SUI>, Coin<0x2::sui::SUI>) {
    let amount_in = coin::value(&token_a);
    requires(amount_in > 0);
    
    let old_pool = old!(pool);
    let old_fees = old_pool.total_fees_collected;
    
    let (coin_a_out, coin_b_out) = swap_a_to_b(pool, token_a, ctx);
    
   
    let expected_fee = (amount_in * FEE_RATE_BPS) / BASIS_POINTS;
    
    
    // For example: amount_in = 10, expected_fee = (10 * 30) / 10000 = 0
    // But the spec expects the actual fees to match this calculation
    ensures(pool.total_fees_collected == old_fees + expected_fee);
    
    (coin_a_out, coin_b_out)
}



} 