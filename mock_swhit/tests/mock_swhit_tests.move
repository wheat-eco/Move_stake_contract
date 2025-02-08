#[test_only]
module devnet_staking::mock_swhit_tests {
use sui::test_scenario::{Self, Scenario};
use sui::coin::{Self, Coin, TreasuryCap};
use sui::tx_context;
use devnet_staking::mock_swhit::{Self, MOCK_SWHIT_COIN};

#[test]
fun test_mock_swhit_init_and_mint() {
let admin = @0xAD;
let user = @0xB0B;

let scenario = test_scenario::begin(admin);

// Test initialization
test_scenario::next_tx(&mut scenario, admin);
{
mock_swhit::init_for_testing(test_scenario::ctx(&mut scenario));
};

// Verify TreasuryCap is created and sent to admin
test_scenario::next_tx(&mut scenario, admin);
{
assert!(test_scenario::has_most_recent_for_sender<TreasuryCap<MOCK_SWHIT_COIN>>(&scenario), 0);
  };

  // Test minting
  test_scenario::next_tx(&mut scenario, admin);
  {
  let treasury_cap = test_scenario::take_from_sender<TreasuryCap<MOCK_SWHIT_COIN>>(&scenario);
    mock_swhit::mint(&mut treasury_cap, 1000, user, test_scenario::ctx(&mut scenario));
    test_scenario::return_to_sender(&scenario, treasury_cap);
    };

    // Verify minted coins are received by user
    test_scenario::next_tx(&mut scenario, user);
    {
    assert!(test_scenario::has_most_recent_for_sender<Coin<MOCK_SWHIT_COIN>>(&scenario), 1);
      let coin = test_scenario::take_from_sender<Coin<MOCK_SWHIT_COIN>>(&scenario);
        assert!(coin::value(&coin) == 1000, 2);
        test_scenario::return_to_sender(&scenario, coin);
        };

        test_scenario::end(scenario);
        }
        }