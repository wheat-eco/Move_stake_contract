module devnet_staking::mock_swhit {

use sui::coin::{Self, CoinMetadata, TreasuryCap};

/// Mock SWHIT token for testing
struct MOCK_SWHIT has drop {}

#[allow(unused_use)]
fun init(witness: MOCK_SWHIT, ctx: &mut TxContext) {
let (treasury_cap, metadata) = coin::create_currency(
witness,
9,
b"MOCK_SWHIT",
b"Mock SWHIT",
b"Mock SWHIT coin for devnet testing",
option::none(),
ctx
);

// Explicitly type the metadata
let metadata: CoinMetadata<MOCK_SWHIT> = metadata;
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
    init(MOCK_SWHIT {}, ctx)
    }
    }