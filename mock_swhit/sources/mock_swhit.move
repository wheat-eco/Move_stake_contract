module devnet_staking::mock_swhit {

use sui::coin::{Self, CoinMetadata, TreasuryCap};



/// Mock SWHIT token for testing
struct MOCK_SWHIT has drop, store {}

/// One-time witness for the MOCK_SWHIT token
struct WITNESS has drop {}

// Remove public and change to internal init
fun init(ctx: &mut TxContext) {
let witness = WITNESS {};
let (treasury_cap, metadata) = coin::create_currency(
MOCK_SWHIT {},
9,
b"MOCK_SWHIT",
b"Mock SWHIT",
b"Mock SWHIT coin for devnet testing",
option::none(),
ctx
);

transfer::public_freeze_object(metadata);
transfer::public_transfer(treasury_cap, tx_context::sender(ctx));
}

public entry fun mint(
treasury_cap: &mut TreasuryCap<MOCK_SWHIT>,
  amount: u64,
  recipient: address,
  ctx: &mut TxContext
  ) {
  coin::mint_and_transfer(treasury_cap, amount, recipient, ctx);
  }

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
  init(ctx)
  }
  }