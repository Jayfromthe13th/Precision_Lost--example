# Simple DeFi - Precision Loss Vulnerability

This project demonstrates a precision loss vulnerability in a Sui Move DeFi swap contract. The vulnerability allows users to bypass fees entirely by performing swaps with small amounts.

## Vulnerability Description

### The Issue
The swap contract has a precision loss vulnerability in the fee calculation mechanism. The fee is calculated using integer division:

```move
let fee_amount = (amount_in * FEE_RATE_BPS) / BASIS_POINTS;
```

Where:
- `FEE_RATE_BPS = 30` (0.3%)
- `BASIS_POINTS = 10000`

### The Problem
When the input amount is small, the fee calculation results in 0 due to integer division rounding down. For example:
- Amount: 1 SUI
- Fee calculation: (1 * 30) / 10000 = 0
- Result: No fee is charged

### Impact
1. **Fee Bypass**: Users can perform many small swaps to avoid paying fees entirely
2. **Revenue Loss**: The protocol loses expected fee revenue
3. **Unfair Advantage**: Users who understand the vulnerability can trade without fees while others pay

## Exploit Scenario

An attacker can:
1. Perform 1000 swaps of 1 SUI each
2. Pay 0 fees total (instead of 3 SUI in fees)
3. Execute the same trading volume as someone who pays fees

## Files

- `sources/swap.move` - The vulnerable swap contract
- `sources/swap_tests.move` - Tests demonstrating the vulnerability

## Running Tests

```bash
sui move test
```

## Fix

To fix this vulnerability, the contract should:
1. Use higher precision arithmetic (e.g., multiply by a larger factor)
2. Implement minimum fee amounts
3. Use proper rounding strategies
4. Consider using fixed-point arithmetic libraries

## Example Fix

We fix this by ensuring a minimum fee is always charged, preventing fee evasion:

```move
// Define minimum fee as a constant
const MINIMUM_FEE: u64 = 1; // Minimum fee to prevent evasion

// Fix precision loss by ensuring minimum fee
let fee_amount = if ((amount_in * FEE_RATE_BPS) / BASIS_POINTS == 0) {
    MINIMUM_FEE // Use configurable minimum fee
} else {
    (amount_in * FEE_RATE_BPS) / BASIS_POINTS
};
```

This change eliminates the precision loss and results in a correct, successful output.

### Additional Security: Assert Check

For extra security, you can also add an assert to ensure fees are never zero:

```move
let fee_amount = (amount_in * FEE_RATE_BPS) / BASIS_POINTS;
assert!(fee_amount > 0, EInvalidFeeRate); // Ensures fees are always charged
```

This assert will cause the transaction to fail if the fee calculation results in zero, preventing any fee evasion attempts. 