module owner_addr::nft_staking {
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

  use aptos_std::type_info;
  use aptos_std::vector;
  
  const ENO_STAKING:u64 = 1;
  const ENO_TOKEN_IN_TOKEN_STORE: u64 = 2;
  const ENO_COLELCTION: u64 = 3;
  const ESTOPPED_STAKING: u64 = 4;
  const ENO_STAKING_ADDRESS: u64 = 5;
  const ENO_REWARD_RESOURCE: u64 = 6;
  const ENO_STAKER_MISMATCH: u64 = 7;
  const ECOIN_TYPE_MISMATCH: u64 = 8;
  const EINSUFFICIENT_TOKENS_BALANCE: u64 = 9;
  const ENO_STAKING_EXISTS: u64 = 10;

  struct StakeEvent has drop, store {
    token_id: TokenId,
    timestamp: u64,
  }

  struct UnstakeEvent has drop, store {
    token_id: TokenId,
    timestamp: u64,
  }

  struct ClaimEvent has drop, store {
    token_id: TokenId,
    coin_amount: u64,
    timestamp: u64,
  }

  // will be stored on account who move his nft into staking
  struct StakingEventStore has key {
    stake_events: EventHandle<StakeEvent>,
    unstake_events: EventHandle<UnstakeEvent>,
    claim_events: EventHandle<ClaimEvent>,
  }

  struct ResourceInfo has key {
    // SimpleMap<token_seed, reward_treasury_addr> 
    resource_map: SimpleMap<String, address>
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
    // reward = now() - reward_data.start_at * decimals... (it will be wrong data)
    withdraw_amount: u64,
    treasury_cap: account::SignerCapability,
    // start of staking
    start_time: u64,
    // amount of tokens
    tokens: u64,
  }

  struct ResourceStaking has key {
    collection: String,
    // reward per hour
    rph: u64,
    // status of staking
    status: bool,
    // the amount of coins stored in vault
    amount: u64,
    // coin type in which the staking are paid
    coin_type: address,
    // treasury capability
    treasury_cap: account::SignerCapability,
  }

  // helper function
  // if user try to stake nft first time, so he dont have ResourceInfo resource on account 
  // so we create it and also push into the map { token_seed, reward_treasury_addr }
  fun create_and_add_resource_info(account: &signer, token_seed: String, reward_treasury_addr: address) acquires ResourceInfo {
    let account_addr = signer::address_of(account);
    if (!exists<ResourceInfo>(account_addr)) {
      move_to(account, ResourceInfo { resource_map: simple_map::create() })
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

  fun initialize_staking_event_store(account: &signer) {
    if (!exists<StakingEventStore>(signer::address_of(account))) {
      move_to<StakingEventStore>(account, StakingEventStore {
        stake_events: account::new_event_handle<StakeEvent>(account),
        unstake_events: account::new_event_handle<UnstakeEvent>(account),
        claim_events: account::new_event_handle<ClaimEvent>(account),
      })
    }
  }

  // get staking address from resource struct
  fun get_resource_address(addr: address, collection_name: String): address acquires ResourceInfo {
    assert!(exists<ResourceInfo>(addr), ENO_STAKING);
    let simple_maps = borrow_global<ResourceInfo>(addr);

    let staking_address = *simple_map::borrow(&simple_maps.resource_map, &collection_name);
    staking_address
  }

  // check if staker address has ResourceInfo resources
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
  fun calculate_reward(rph: u64, staking_start_time: u64, number_of_tokens: u64, withdraw_amount: u64): u64 {
    let now = timestamp::now_seconds();
    // reward per second
    let rps = rph / 3600;
    let reward = ((now - staking_start_time) * rps * number_of_tokens);
    
    let release_amount = reward - withdraw_amount;
    release_amount
  }

  #[view]
  public fun get_tokens_staking_statuses(owner_addr: address): vector<TokenId> acquires StakingStatusInfo {
    let simple_maps = borrow_global<StakingStatusInfo>(owner_addr);

    simple_maps.staking_statuses_vector
  }

  // create new resource_account with staking_treasury and ResourceStaking resource
  // and also send some initial Coins to staking_tresury account
  public entry fun create_staking<CoinType>(
    staking_creator: &signer, collection_creator_addr: address, rph: u64, collection_name: String, total_amount: u64,
  ) acquires ResourceInfo {
    // check that creator has the collection
    assert!(token::check_collection_exists(collection_creator_addr, collection_name), ENO_COLELCTION);

    // create new staking resource account
    // this resource account will store funds data and Staking resource
    let (staking_treasury, staking_treasury_cap) = account::create_resource_account(staking_creator, to_bytes(&collection_name));
    let staking_treasury_signer_from_cap = account::create_signer_with_capability(&staking_treasury_cap);

    let staking_address = signer::address_of(&staking_treasury);
    // there should be Staking for this new resrouce account
    assert!(!exists<ResourceStaking>(staking_address), ENO_STAKING_EXISTS);
    // init ResourceInfo on main signer
    create_and_add_resource_info(staking_creator, collection_name, staking_address);
    // register new resource on just created staking account
    managed_coin::register<CoinType>(&staking_treasury_signer_from_cap);
    // move total_amount of coins<CoinType> to created resource account - staking_treasury_address
    coin::transfer<CoinType>(staking_creator, staking_address, total_amount);
    
    // init Staking on treasury struct
    move_to<ResourceStaking>(&staking_treasury_signer_from_cap, ResourceStaking {
      collection: collection_name,
      rph,
      status: true,
      amount: total_amount,
      coin_type: coin_address<CoinType>(),
      treasury_cap: staking_treasury_cap,
    });
  }

  // move nft from sender (staker) to resource account and start staking
  public entry fun stake_token(
    staker: &signer, staking_creator_addr: address, collection_creator_addr: address, collection_name: String, token_name: String, property_version: u64, tokens: u64,
  ) acquires ResourceReward, ResourceStaking, ResourceInfo, StakingEventStore, StakingStatusInfo {
    let staker_addr = signer::address_of(staker);
    
    let token_id = token::create_token_id_raw(collection_creator_addr, collection_name, token_name, property_version);
    // check that signer has token on balance
    assert!(token::balance_of(staker_addr, token_id) >= tokens, ENO_TOKEN_IN_TOKEN_STORE);
    // check that creator has collection
    assert!(token::check_collection_exists(collection_creator_addr, collection_name), ENO_COLELCTION);
    // check if creator start staking or not
    // staking can be initiated, but stopped later
    let staking_address = get_resource_address(staking_creator_addr, collection_name);
    assert!(exists<ResourceStaking>(staking_address), ESTOPPED_STAKING);

    let staking_data = borrow_global<ResourceStaking>(staking_address);
    assert!(staking_data.status, ESTOPPED_STAKING);

    // create seed token based on collection name and token name
    let token_seed = collection_name;
    let additional_seed = token_name;
    string::append(&mut token_seed, additional_seed);

    // check if staker_addr has ResourceInfo with resource_map inside it with
    let should_pass_restake = check_map(staker_addr, token_seed);

    let now = timestamp::now_seconds();

    initialize_staking_event_store(staker);

    let staking_event_store = borrow_global_mut<StakingEventStore>(staker_addr);

    event::emit_event<StakeEvent>(
      &mut staking_event_store.stake_events,
      StakeEvent {
        token_id,
        timestamp: now,
      },
    );

    if (should_pass_restake) {
      // nft was already in staking before
      let reward_treasury_addr = get_resource_address(staker_addr, token_seed);
      // check if resource account has Reward resource 
      assert!(exists<ResourceReward>(reward_treasury_addr), ENO_REWARD_RESOURCE);
      
      // get resource data
      let reward_data = borrow_global_mut<ResourceReward>(reward_treasury_addr);
      let reward_treasury_signer_from_cap = account::create_signer_with_capability(&reward_data.treasury_cap);
      
      // get staking statuses data
      let staking_statuses = borrow_global_mut<StakingStatusInfo>(staker_addr);
      vector::push_back(&mut staking_statuses.staking_statuses_vector, token_id);
      
      // update reward data
      reward_data.tokens = tokens;
      reward_data.start_time = now;
      reward_data.withdraw_amount = 0;

      // send nft to special resource account of signer
      token::direct_transfer(staker, &reward_treasury_signer_from_cap, token_id, tokens);
    } else {
      // first attempt to stake token
      // create new resource account based on token seed
      let (reward_treasury, reward_treasury_cap) = account::create_resource_account(staker, to_bytes(&token_seed));
      let reward_treasury_signer_from_cap = account::create_signer_with_capability(&reward_treasury_cap);
      // get address of created resource account
      let reward_treasury_addr = signer::address_of(&reward_treasury);

      assert!(!exists<ResourceReward>(reward_treasury_addr), ENO_STAKING_ADDRESS);

      // init account and fill ResourceInfo
      create_and_add_resource_info(staker, token_seed, reward_treasury_addr);
      // init/update StakingStatusesInfo
      create_and_add_staking_statuses_info(staker, token_id);

      // send token to special resource account
      token::direct_transfer(staker, &reward_treasury_signer_from_cap, token_id, tokens);
      
      // init Reward resource on special resource account
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
    staker_addr: address, staking_creator_addr: address, collection_name: String, token_name: String,
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

    let staking_data = borrow_global<ResourceStaking>(staking_address);
    let reward_data = borrow_global<ResourceReward>(reward_treasury_addr);

    // return amount of unclaimed reward based on token id, withdred amount and reward per hour
    calculate_reward(staking_data.rph, reward_data.start_time, reward_data.tokens, reward_data.withdraw_amount)
  }

  // same as unstake but without final sending of token and updating staking data
  public entry fun claim_reward<CoinType>(
    staker: &signer, staking_creator_addr: address, collection_creator_addr: address, collection_name: String, token_name: String, property_version: u64,
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

    // get reward treasury address which hold the tokens
    let reward_treasury_addr = get_resource_address(staker_addr, token_seed);
    assert!(exists<ResourceReward>(reward_treasury_addr), ENO_STAKING_ADDRESS);

    // get resource data
    let reward_data = borrow_global_mut<ResourceReward>(reward_treasury_addr);    
    // check that staker address stored inside Reward staker
    assert!(reward_data.staker == staker_addr, ENO_STAKER_MISMATCH);

    let token_id = token::create_token_id_raw(collection_creator_addr, collection_name, token_name, property_version);

    // calculate reward
    let release_amount = calculate_reward(staking_data.rph, reward_data.start_time, reward_data.tokens, reward_data.withdraw_amount);

    // check if address of CoinType that we want to withdraw are equal to CoinType address stored in staking_data resource
    assert!(coin_address<CoinType>() == staking_data.coin_type, ECOIN_TYPE_MISMATCH); 

    if (staking_data.amount < release_amount) {
      staking_data.status = false;
      // check if module has enough coins in treasury
      assert!(staking_data.amount > release_amount, EINSUFFICIENT_TOKENS_BALANCE);
    };
    // register new CoinType in case staker doesnt have it
    if (!coin::is_account_registered<CoinType>(staker_addr)) {
      managed_coin::register<CoinType>(staker);
    };

    let staking_event_store = borrow_global_mut<StakingEventStore>(staker_addr);

    // trigger claim event
    event::emit_event<ClaimEvent>(
      &mut staking_event_store.claim_events,
      ClaimEvent {
        token_id,
        coin_amount: release_amount,
        timestamp: timestamp::now_seconds(),
      },
    );

    // send coins from treasury to staker
    coin::transfer<CoinType>(&staking_treasury_signer_from_cap, staker_addr, release_amount);
    
    // update staking and reward data's
    staking_data.amount = staking_data.amount - release_amount;
    reward_data.withdraw_amount = reward_data.withdraw_amount + release_amount;
  }

  // send token from resource account back to staker and claim all pending reward
  public entry fun unstake_token<CoinType>(
    staker: &signer, staking_creator_addr: address, collection_creator_addr: address, collection_name: String, token_name: String, property_version: u64,
  ) acquires ResourceReward, ResourceStaking, ResourceInfo, StakingStatusInfo, StakingEventStore {
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

    // get reward treasury address which hold the tokens
    let reward_treasury_addr = get_resource_address(staker_addr, token_seed);
    assert!(exists<ResourceReward>(reward_treasury_addr), ENO_STAKING_ADDRESS);

    // get resource data
    let reward_data = borrow_global_mut<ResourceReward>(reward_treasury_addr);
    let reward_treasury_signer_from_cap = account::create_signer_with_capability(&reward_data.treasury_cap);
    
    // check that staker address stored inside Reward staker
    assert!(reward_data.staker == staker_addr, ENO_STAKER_MISMATCH);

    let release_amount = calculate_reward(staking_data.rph, reward_data.start_time, reward_data.tokens, reward_data.withdraw_amount);

    // check if address of CoinType that we want to withward are equal to CoinType address stored in staking_data
    assert!(coin_address<CoinType>() == staking_data.coin_type, ECOIN_TYPE_MISMATCH); 
    // create TokenId
    let token_id = token::create_token_id_raw(collection_creator_addr, collection_name, token_name, property_version);

    // check if reward_treasury_addr (resource account of staker) cointains token that we want to withdraw
    let token_balance = token::balance_of(reward_treasury_addr, token_id);
    assert!(token_balance >= reward_data.tokens, EINSUFFICIENT_TOKENS_BALANCE);

    // if user want to withdraw more than module has in treasury - staking will be disabled
    if (staking_data.amount < release_amount) {
      staking_data.status = false
    };
    if (staking_data.amount > release_amount) {
      // check if address where we gonna send reward, cointains valid CoinType resource, if no - create new
      if (!coin::is_account_registered<CoinType>(staker_addr)) {
        managed_coin::register<CoinType>(staker);
      };
    };
    
    let staking_event_store = borrow_global_mut<StakingEventStore>(staker_addr);

    // trigger unstake event
    event::emit_event<UnstakeEvent>(
      &mut staking_event_store.unstake_events,
      UnstakeEvent {
        token_id,
        timestamp: timestamp::now_seconds(),
      },
    );

    // remove tokenId data from vector in StakingStatusInfo
    let staking_statuses = borrow_global_mut<StakingStatusInfo>(staker_addr);
    let (_, index) = vector::index_of<TokenId>(&staking_statuses.staking_statuses_vector, &token_id);
    vector::remove<TokenId>(&mut staking_statuses.staking_statuses_vector, index);

    // transfer amount of coins from treasury to staker address
    coin::transfer<CoinType>(&staking_treasury_signer_from_cap, staker_addr, release_amount);

    // move nft from resource account to staker_addr
    token::direct_transfer(&reward_treasury_signer_from_cap, staker, token_id, reward_data.tokens);

    // update balance of main treasury
    staking_data.amount = staking_data.amount - release_amount;

    // reset reward and staking data
    reward_data.tokens = 0;
    reward_data.start_time = 0;
    reward_data.withdraw_amount = 0;
  }
}