module owner_addr::mint_coins {
  use aptos_framework::managed_coin;
  use aptos_std::signer;

  struct Minerals {}

  fun init_module(owner: &signer) {
    let owner_addr = signer::address_of(owner);

    managed_coin::initialize<Minerals>(
      owner,
      b"Minerals Coin",
      b"Minerals",
      8,
      true,
    );

    // create resources 
    managed_coin::register<Minerals>(owner);

    // mint 100k Crystal during publish to owner_address
    managed_coin::mint<Minerals>(owner, owner_addr, 10000000000000);
  }
}
