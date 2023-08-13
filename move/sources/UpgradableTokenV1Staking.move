module owner_addr::upgradable_token_v1_staking {
  use std::string::{ Self, String };
  use std::bcs::to_bytes;
  use std::signer;

  use aptos_framework::timestamp;
  use aptos_framework::simple_map::{ Self, SimpleMap };
  use aptos_framework::managed_coin;
  use aptos_framework::coin;
  use aptos_framework::account;
  use aptos_framework::event::{ Self, EventHandle };

  use aptos_token::token::{ Self, TokenId };
  use aptos_token::property_map;

  use aptos_std::type_info;
  use aptos_std::vector;

  const ESTAKER_MISMATCH: u64 = 1;
  const ECOIN_TYPE_MISMATCH: u64 = 2;
  const ESTOPPED_STAKING: u64 = 3;
  const EINSUFFICIENT_TOKENS_BALANCE: u64 = 4;
  const ENO_STAKING:u64 = 5;
  const ENO_TOKEN_IN_TOKEN_STORE: u64 = 6;
  const ENO_COLLECTION: u64 = 7;
  const ENO_STAKING_ADDRESS: u64 = 8;
  const ENO_REWARD_RESOURCE: u64 = 9;
  const ENO_STAKING_EXISTS: u64 = 10;
  const ENO_STAKING_EVENT_STORE: u64 = 11;
  const ENO_STAKING_STATUSES: u64 = 12;

  struct StakeEvent has drop, store {
    token_id: TokenId,
    token_level: u64,
    timestamp: u64,
  }

  struct UnstakeEvent has drop, store {
    token_id: TokenId,
    token_level: u64,
    timestamp: u64,
  }

  struct ClaimEvent has drop, store {
    token_id: TokenId,
    token_level: u64,
    coin_amount: u64,
    timestamp: u64,
  }

  // will be stored on account who move his token into staking
  struct StakingEventStore has key {
    stake_events: EventHandle<StakeEvent>,
    unstake_events: EventHandle<UnstakeEvent>,
    claim_events: EventHandle<ClaimEvent>,
  }

  struct ResourceInfo has key {
    // SimpleMap<token_seed, reward_treasury_addr> 
    resource_map: SimpleMap<String, address>,
  }

  struct StakingStatusInfo has key, drop {
    staking_statuses_vector: vector<TokenId>,
  }

  struct ResourceReward has drop, key {
    staker: address,
    token_name: String,
    collection: String,
    // total amount that user already withdraw
    // in case user call multiple claim's without fully unstake, so, we cannt calculate like this:
    // reward = now() - reward_data.start_at * decimals
    withdraw_amount: u64,
    treasury_cap: account::SignerCapability,
    start_time: u64,
    // amount of tokens
    tokens: u64,
  }

  struct ResourceStaking has key {
    collection: String,
    // amount of token paud in week for staking one token 
    // rph (reward per hour)
    rph: u64,
    // status of staking
    status: bool,
    // the amount of coins stored in vault
    amount: u64,
    // coin type in witch the staking are paid
    coin_type: address,
    // treasury_cap
    treasury_cap: account::SignerCapability,
  }

  // helper functions
  // init event store on staked_addr if he doesnt have such resource
  fun initialize_staking_event_store(account: &signer) {
    if (!exists<StakingEventStore>(signer::address_of(account))) {
      move_to<StakingEventStore>(account, StakingEventStore {
        stake_events: account::new_event_handle<StakeEvent>(account),
        unstake_events: account::new_event_handle<UnstakeEvent>(account),
        claim_events: account::new_event_handle<ClaimEvent>(account),
      })
    }
  }

  // check if user has ResourceInfo resource, if not - init, if yes - push some data
  fun create_and_add_resource_info(account: &signer, token_seed: String, reward_treasury_addr: address) acquires ResourceInfo {
    let account_addr = signer::address_of(account);
    if (!exists<ResourceInfo>(account_addr)) {
      move_to(account, ResourceInfo {
        resource_map: simple_map::create()
      })
    };
    let maps = borrow_global_mut<ResourceInfo>(account_addr);
    simple_map::add(&mut maps.resource_map, token_seed, reward_treasury_addr);
  }

  // check if user has StakingStatusInfo resource, if not - init, if yes - push some data
  fun create_and_add_staking_statuses_info(account: &signer, token_id: TokenId) acquires StakingStatusInfo {
    let account_addr = signer::address_of(account);

    if (!exists<StakingStatusInfo>(account_addr)) {
      move_to<StakingStatusInfo>(account, StakingStatusInfo {
        staking_statuses_vector: vector::empty()
      });
    };

    let staking_statuses = borrow_global_mut<StakingStatusInfo>(account_addr);
    vector::push_back<TokenId>(&mut staking_statuses.staking_statuses_vector, token_id);
  }

  public fun get_resource_address(addr: address, seed: String): address acquires ResourceInfo {
    assert!(exists<ResourceInfo>(addr), ENO_STAKING);
    let simple_maps = borrow_global<ResourceInfo>(addr);
    // getting staking address from Resource Info simple map
    let staking_address = *simple_map::borrow(&simple_maps.resource_map, &seed);
    staking_address
  }

  // check if staker address has ResourceInfo
  fun check_map(addr: address, string: String):bool acquires ResourceInfo {
    if (!exists<ResourceInfo>(addr)) {
      false
    } else {
      let maps = borrow_global<ResourceInfo>(addr);
      simple_map::contains_key(&maps.resource_map, &string)
    }
  }

  // return address of CoinType coin
  fun coin_address<CoinType>(): address {
    let type_info = type_info::type_of<CoinType>();
    type_info::account_address(&type_info)
  }

  // calculate and return reward value 
  fun calculate_reward(owner_addr: address, token_id: TokenId, rph: u64, staking_start_time: u64, number_of_tokens: u64, withdraw_amount: u64): u64 {
    let now = timestamp::now_seconds();
    // rps - reward per second
    let rps = rph / 3600;

    // get current level of token
    let level = get_token_level(owner_addr, token_id);

    let reward = ((now - staking_start_time) * (rps * level) * number_of_tokens);
  
    let release_amount = reward - withdraw_amount;
    release_amount
  }

  // return token level
  fun get_token_level(owner_addr: address, token_id: TokenId): u64 {
    let pm = token::get_property_map(owner_addr, token_id);

    let level = property_map::read_u64(&pm, &string::utf8(b"level"));

    level
  }

  #[view]
  public fun get_tokens_staking_statuses(owner_addr: address): vector<TokenId> acquires StakingStatusInfo {
    let simple_maps = borrow_global<StakingStatusInfo>(owner_addr);

    simple_maps.staking_statuses_vector
  }

  // create new resource_account with staking_treasury and ResourceStaking resource
  // and also send some initial Coins to staking_treasury account
  public entry fun create_staking<CoinType>(
    staking_creator: &signer, collection_owner_addr: address, rph: u64, collection_name: String, total_amount: u64,
  ) acquires ResourceInfo {
    // check that creator has the collection
    assert!(token::check_collection_exists(collection_owner_addr, collection_name), ENO_COLLECTION);

    // create new staking resource account
    let (staking_treasury, staking_treasury_cap) = account::create_resource_account(staking_creator, to_bytes(&collection_name));
    let staking_treasury_signer_from_cap = account::create_signer_with_capability(&staking_treasury_cap);

    let staking_address = signer::address_of(&staking_treasury);
    // should be ResourceStaking for this new resource account
    assert!(!exists<ResourceStaking>(staking_address), ENO_STAKING_EXISTS);
    // init ResourceInfo on main signer
    create_and_add_resource_info(staking_creator, collection_name, staking_address);
    // register new resource on just created staking account
    managed_coin::register<CoinType>(&staking_treasury_signer_from_cap);
    // move some coins of CoinType to just created resource account - staking_treasury
    coin::transfer<CoinType>(staking_creator, staking_address, total_amount);
    
    // init ResourceStaking on treasury account
    move_to<ResourceStaking>(&staking_treasury_signer_from_cap, ResourceStaking {
      collection: collection_name,
      rph,
      status: true,
      amount: total_amount,
      coin_type: coin_address<CoinType>(),
      treasury_cap: staking_treasury_cap,
    });
  }

  // move token from sender to resource account and start staking
  public entry fun stake_token(
    staker: &signer, staking_creator_addr: address, collection_owner_addr: address, collection_name: String, token_name: String, property_version: u64, tokens: u64,
  ) acquires ResourceReward, ResourceStaking, ResourceInfo, StakingEventStore, StakingStatusInfo {
    let staker_addr = signer::address_of(staker);

    let token_id = token::create_token_id_raw(collection_owner_addr, collection_name, token_name, property_version);
    // check that signer has token on balance
    assert!(token::balance_of(staker_addr, token_id) >= tokens, ENO_TOKEN_IN_TOKEN_STORE);
    // check that creator has collection
    assert!(token::check_collection_exists(collection_owner_addr, collection_name), ENO_COLLECTION);

    // check if staker start staking or not
    // staking can create anyone (not only creator of collection)
    let staking_address = get_resource_address(staking_creator_addr, collection_name);
    assert!(exists<ResourceStaking>(staking_address), ESTOPPED_STAKING);

    let staking_data = borrow_global<ResourceStaking>(staking_address);
    assert!(staking_data.status, ESTOPPED_STAKING);

    // create token seed
    let token_seed = collection_name;
    let additional_seed = token_name;
    string::append(&mut token_seed, additional_seed);

    // check if staker_addr has ResourceInfo with resource_map inside it with
    let should_pass_restake = check_map(staker_addr, token_seed);

    let now = timestamp::now_seconds();

    initialize_staking_event_store(staker);

    let staking_event_store = borrow_global_mut<StakingEventStore>(staker_addr);

    // token still on owner address and will be transfered to resource account later
    let token_level = get_token_level(staker_addr, token_id);

    event::emit_event<StakeEvent>(
      &mut staking_event_store.stake_events,
      StakeEvent {
        token_id,
        timestamp: now,
        token_level,
      },
    );

    if (should_pass_restake) {
      // token was already in staking before
      let reward_treasury_addr = get_resource_address(staker_addr, token_seed);
      // check if resource account has ResourceReward and StakingStatusInfo structs 
      assert!(exists<ResourceReward>(reward_treasury_addr), ENO_REWARD_RESOURCE);
      assert!(exists<StakingStatusInfo>(staker_addr), ENO_STAKING_STATUSES);

      // get resource data
      let reward_data = borrow_global_mut<ResourceReward>(reward_treasury_addr);
      let reward_treasury_signer_from_cap = account::create_signer_with_capability(&reward_data.treasury_cap);

      // get staking statuses data
      let staking_statuses = borrow_global_mut<StakingStatusInfo>(staker_addr);
      vector::push_back(&mut staking_statuses.staking_statuses_vector, token_id);

      // update reward_data after new staking started
      reward_data.tokens = tokens;
      reward_data.start_time = now;
      reward_data.withdraw_amount = 0;

      // send token to special resource account of signer
      token::direct_transfer(staker, &reward_treasury_signer_from_cap, token_id, tokens);
    } else {
      // first try to stake token
      // create some new resource account based on token seed
      let (reward_treasury, reward_treasury_cap) = account::create_resource_account(staker, to_bytes(&token_seed));
      let reward_treasury_signer_from_cap = account::create_signer_with_capability(&reward_treasury_cap);
      let reward_treasury_addr = signer::address_of(&reward_treasury);

      assert!(!exists<ResourceReward>(reward_treasury_addr), ENO_STAKING_ADDRESS);
      // init/update ResourceInfo
      create_and_add_resource_info(staker, token_seed, reward_treasury_addr);
      // init/update StakingStatusesInfo
      create_and_add_staking_statuses_info(staker, token_id);

      // send token to special resource account of signer
      token::direct_transfer(staker, &reward_treasury_signer_from_cap, token_id, tokens);
      
      // init ResourceReward resource on special resource account
      move_to<ResourceReward>(&reward_treasury_signer_from_cap, ResourceReward {
        staker: staker_addr,
        token_name,
        collection: collection_name,
        withdraw_amount: 0, 
        treasury_cap: reward_treasury_cap,
        start_time: now,
        tokens,
      });
    };
  }

  #[view]
  public fun get_unclaimed_reward(
    staker_addr: address, staking_creator_addr: address, collection_owner_addr: address, collection_name: String, token_name: String, property_version: u64,
  ): u64  acquires ResourceInfo, ResourceStaking, ResourceReward {
    // check if staker has resource info
    assert!(exists<ResourceInfo>(staker_addr), ENO_REWARD_RESOURCE);

    let token_seed = collection_name;
    let additional_seed = token_name;
    string::append(&mut token_seed, additional_seed);
    // get a reward treasury addr and read it data
    let reward_treasury_addr = get_resource_address(staker_addr, token_seed);
    assert!(exists<ResourceReward>(reward_treasury_addr), ENO_STAKING_ADDRESS);

    let staking_address = get_resource_address(staking_creator_addr, collection_name);
    assert!(exists<ResourceStaking>(staking_address), ENO_STAKING);

    // get staking and reward data to calculate unclaimed reward
    let staking_data = borrow_global<ResourceStaking>(staking_address);
    let reward_data = borrow_global<ResourceReward>(reward_treasury_addr);    
  
    let token_id = token::create_token_id_raw(collection_owner_addr, collection_name, token_name, property_version);
    
    // cannot use staker_addr, as now token stored in resource account
    calculate_reward(reward_treasury_addr, token_id, staking_data.rph, reward_data.start_time, reward_data.tokens, reward_data.withdraw_amount)
  }

  public entry fun claim_reward<CoinType>(
    staker: &signer, staking_creator_addr: address, collection_owner_addr: address, collection_name: String, token_name: String, property_version: u64,
  ) acquires ResourceReward, ResourceStaking, ResourceInfo, StakingEventStore {
    let staker_addr = signer::address_of(staker);

    let staking_address = get_resource_address(staking_creator_addr, collection_name);
    assert!(exists<ResourceStaking>(staking_address), ENO_STAKING);

    let staking_data = borrow_global_mut<ResourceStaking>(staking_address);
    let staking_treasury_signer_from_cap = account::create_signer_with_capability(&staking_data.treasury_cap);
    // check if staking enabled or not
    assert!(staking_data.status, ESTOPPED_STAKING);
    
    // create token seed 
    let token_seed = collection_name;
    let additional_seed = token_name;
    string::append(&mut token_seed, additional_seed);

    // get reward treasury address which hold the coins
    let reward_treasury_addr = get_resource_address(staker_addr, token_seed);
    assert!(exists<ResourceReward>(reward_treasury_addr), ENO_STAKING_ADDRESS);

    // getting resource data, same as for staking
    let reward_data = borrow_global_mut<ResourceReward>(reward_treasury_addr);    
    // check that staker address stored inside MetaReward staker
    assert!(reward_data.staker == staker_addr, ESTAKER_MISMATCH);

    let token_id = token::create_token_id_raw(collection_owner_addr, collection_name, token_name, property_version);

    let release_amount = calculate_reward(reward_treasury_addr, token_id, staking_data.rph, reward_data.start_time, reward_data.tokens, reward_data.withdraw_amount);

    // check if address of CoinType that we want to withdraw are equal to CoinType address stored in staking_data
    assert!(coin_address<CoinType>() == staking_data.coin_type, ECOIN_TYPE_MISMATCH); 

    if (staking_data.amount < release_amount) {
      staking_data.status = false;
      // check if module has enough coins in treasury
      assert!(staking_data.amount > release_amount, EINSUFFICIENT_TOKENS_BALANCE);
    };

    if (!coin::is_account_registered<CoinType>(staker_addr)) {
      managed_coin::register<CoinType>(staker);
    };

    assert!(exists<StakingEventStore>(staker_addr), ENO_STAKING_EVENT_STORE);

    let staking_event_store = borrow_global_mut<StakingEventStore>(staker_addr);

    // token are on reward_treasury_addr now, not on staker_addr
    let token_level = get_token_level(reward_treasury_addr, token_id);

    // trigger claim event
    event::emit_event<ClaimEvent>(
      &mut staking_event_store.claim_events,
      ClaimEvent {
        token_id,
        coin_amount: release_amount,
        timestamp: timestamp::now_seconds(),
        token_level,
      },
    );

    // send coins from treasury to signer
    coin::transfer<CoinType>(&staking_treasury_signer_from_cap, staker_addr, release_amount);
    
    // update staking and reward data's
    staking_data.amount = staking_data.amount - release_amount;
    reward_data.withdraw_amount = reward_data.withdraw_amount + release_amount;
  }

  public entry fun unstake_token<CoinType>(
    staker: &signer, staking_creator_addr: address, collection_owner_addr: address, collection_name: String, token_name: String, property_version: u64,
  ) acquires ResourceReward, ResourceStaking, ResourceInfo, StakingEventStore, StakingStatusInfo {
    let staker_addr = signer::address_of(staker);

    // check if staker start staking or not
    let staking_address = get_resource_address(staking_creator_addr, collection_name);
    assert!(exists<ResourceStaking>(staking_address), ENO_STAKING);

    let staking_data = borrow_global_mut<ResourceStaking>(staking_address);
    let staking_treasury_signer_from_cap = account::create_signer_with_capability(&staking_data.treasury_cap);
    
    // check if staking enabled or not
    assert!(staking_data.status, ESTOPPED_STAKING);

    let token_seed = collection_name;
    let additional_seed = token_name;
    string::append(&mut token_seed, additional_seed);

    // get reward treasury address which hold the tokens
    let reward_treasury_addr = get_resource_address(staker_addr, token_seed);
    assert!(exists<ResourceReward>(reward_treasury_addr), ENO_STAKING_ADDRESS);

    // getting resource data, same as for staking
    let reward_data = borrow_global_mut<ResourceReward>(reward_treasury_addr);
    let reward_treasury_signer_from_cap = account::create_signer_with_capability(&reward_data.treasury_cap);
    
    // check that staker address stored inside MetaReward staker
    assert!(reward_data.staker == staker_addr, ESTAKER_MISMATCH);

    let token_id = token::create_token_id_raw(collection_owner_addr, collection_name, token_name, property_version);

    let release_amount = calculate_reward(reward_treasury_addr, token_id, staking_data.rph, reward_data.start_time, reward_data.tokens, reward_data.withdraw_amount);

    // check if address of CoinType that we want to withward are equal to CoinType address stored in staking_data
    assert!(coin_address<CoinType>() == staking_data.coin_type, ECOIN_TYPE_MISMATCH); 

    // check if reward_treasury_addr (resource account of staker) cointains token that we want to withdraw
    let token_balance = token::balance_of(reward_treasury_addr, token_id);
    assert!(token_balance >= reward_data.tokens, EINSUFFICIENT_TOKENS_BALANCE);

    if (staking_data.amount < release_amount) {
      staking_data.status = false
    };
    if (staking_data.amount > release_amount) {
      // check if address where we gonna send reward, cointains valid CoinType resource
      if (!coin::is_account_registered<CoinType>(staker_addr)) {
        managed_coin::register<CoinType>(staker);
      };
    };

    // trigger unstake event
    assert!(exists<StakingEventStore>(staker_addr), ENO_STAKING_EVENT_STORE);

    let staking_event_store = borrow_global_mut<StakingEventStore>(staker_addr);

    // token on reward treasury address now
    let token_level = get_token_level(reward_treasury_addr, token_id);

    // trigger unstake event
    event::emit_event<UnstakeEvent>(
      &mut staking_event_store.unstake_events,
      UnstakeEvent {
        token_id,
        timestamp: timestamp::now_seconds(),
        token_level,
      },
    );

    // remove tokenId data from vector in StakingStatusInfo
    let staking_statuses = borrow_global_mut<StakingStatusInfo>(staker_addr);
    let (_, index) = vector::index_of<TokenId>(&staking_statuses.staking_statuses_vector, &token_id);
    vector::remove<TokenId>(&mut staking_statuses.staking_statuses_vector, index);

    // all staked coins stored in staking_treasury_addr
    // transfer coins from treasury to staker address
    coin::transfer<CoinType>(&staking_treasury_signer_from_cap, staker_addr, release_amount);

    // move token from resource account to staker_addr
    token::direct_transfer(&reward_treasury_signer_from_cap, staker, token_id, reward_data.tokens);

    // update how many coins left in module
    staking_data.amount = staking_data.amount - release_amount;

    // reset reward and staking data
    reward_data.tokens = 0;
    reward_data.start_time = 0;
    reward_data.withdraw_amount = 0;
  }
}