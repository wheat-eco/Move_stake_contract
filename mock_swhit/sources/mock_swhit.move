module devnet_staking::mock_swhit {
    
    /// Mock SWHIT token for testing
    struct MOCK_SWHIT has drop {}

    #[allow(unused_use)]
    fun init(witness: MOCK_SWHIT, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency<MOCK_SWHIT>(
            witness, 
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
}
