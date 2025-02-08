module devnet_staking::mock_swhit {
use sui::coin::{Self, TreasuryCap};

/// One-time witness for coin creation
public struct MOCK_SWHIT has drop {}

/// The type identifier of mock SWHIT coin
public struct MOCK_SWHIT_COIN has drop {}

/// Initialize the currency
fun init(otw: MOCK_SWHIT, ctx: &mut TxContext) {
let (treasury_cap, metadata) = coin::create_currency(
otw,
9, // 9 decimals
b"MOCK_SWHIT",
b"Mock SWHIT",
b"Mock SWHIT coin for devnet testing",
option::none(),
ctx
);

transfer::public_freeze_object(metadata);
transfer::public_transfer(treasury_cap, tx_context::sender(ctx));
}

/// Mint new coins and transfer them to recipient
public entry fun mint(
treasury_cap: &mut TreasuryCap<MOCK_SWHIT_COIN>,
  amount: u64,
  recipient: address,
  ctx: &mut TxContext
  ) {
  coin::mint_and_transfer(treasury_cap, amount, recipient, ctx);
  }

  /// Mint coins without transferring them
  public fun mint_internal(
  treasury_cap: &mut TreasuryCap<MOCK_SWHIT_COIN>,
    amount: u64,
    ctx: &mut TxContext
    ): coin::Coin<MOCK_SWHIT_COIN> {
      coin::mint(treasury_cap, amount, ctx)
      }

      #[test_only]
      public fun init_for_testing(ctx: &mut TxContext) {
      init(MOCK_SWHIT {}, ctx)
      }
      }