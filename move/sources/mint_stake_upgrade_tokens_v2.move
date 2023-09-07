module owner_addr::mint_stake_upgrade_tokens_v2 {
  use std::string::{ Self, String };
  use std::bcs;
  use std::signer;

  use aptos_framework::timestamp;
  use aptos_framework::simple_map::{ Self, SimpleMap };
  use aptos_framework::managed_coin;
  use aptos_framework::coin;
  use aptos_framework::account;
  use aptos_framework::event::{ Self, EventHandle };
  use aptos_framework::object::{ Self };

  use aptos_token_objects::aptos_token;
  use aptos_token_objects::property_map;

  use aptos_std::math64;
  use aptos_std::type_info;
  use aptos_std::vector;
  use aptos_std::string_utils;

  const MAX_LEVEL: u64 = 10;
  const COINS_PER_LEVEL: u64 = 100;

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
  const EINSUFFICIENT_COIN_BALANCE: u64 = 13;
  const ENO_UPGRADE: u64 = 14;
  const ENO_COLLECTION_DOESNT_EXIST: u64 = 15;

  struct StakeEvent has drop, store {
    token_address: address,
    token_level: u64,
    timestamp: u64,
  }

  struct UnstakeEvent has drop, store {
    token_address: address,
    token_level: u64,
    timestamp: u64,
  }

  struct ClaimEvent has drop, store {
    token_address: address,
    token_name: String,
    token_level: u64,
    coin_amount: u64,
    timestamp: u64,
  }

  // will be stored on account who move his nft into staking
  struct EventsStore has key {
    stake_events: EventHandle<StakeEvent>,
    unstake_events: EventHandle<UnstakeEvent>,
    claim_events: EventHandle<ClaimEvent>,
  }

  struct AdminData has key {
    signer_cap: account::SignerCapability,
    source: address,
    coin_type: address,
  }

  // for upgrade token
  struct CollectionOwnerInfo has key {
    //            collection_name, resource_address
    map: SimpleMap<String, address>,
  }

  // for staking
  struct ResourceInfo has key {
    //                 token_seed, reward_treasury_addr 
    resource_map: SimpleMap<String, address>,
  }

  struct ResourceReward has drop, key {
    staker: address,
    token_name: String,
    collection_name: String,
    withdraw_amount: u64,
    treasury_cap: account::SignerCapability,
    start_time: u64,
    tokens: u64,
  }

  struct ResourceStaking has key {
    collection: String,
    rph: u64,
    status: bool,
    amount: u64,
    coin_type: address,
    treasury_cap: account::SignerCapability,
  }

  fun init_or_update_staking_creators(account: &signer, collection_name: String, resource_signer_address: address) acquires CollectionOwnerInfo {
    let account_addr = signer::address_of(account);
    if (!exists<CollectionOwnerInfo>(account_addr)) {
      move_to(account, CollectionOwnerInfo {
        map: simple_map::create()
      })
    };
    let maps = borrow_global_mut<CollectionOwnerInfo>(account_addr);
    simple_map::add(&mut maps.map, collection_name, resource_signer_address);
  }

  #[view]
  fun get_staking_resource_address_by_collection_name(creator: address, collection_name: String): address acquires CollectionOwnerInfo {
    assert!(exists<CollectionOwnerInfo>(creator), ENO_UPGRADE);
    let staking_creators_data = borrow_global<CollectionOwnerInfo>(creator);

    let resource_address = *simple_map::borrow(&staking_creators_data.map, &collection_name);
    resource_address
  }

  // init event store on staker address
  fun init_events_store(account: &signer) {
    if (!exists<EventsStore>(signer::address_of(account))) {
      move_to<EventsStore>(account, EventsStore {
        stake_events: account::new_event_handle<StakeEvent>(account),
        unstake_events: account::new_event_handle<UnstakeEvent>(account),
        claim_events: account::new_event_handle<ClaimEvent>(account),
      })
    }
  }

  // return address of CoinType coin
  fun coin_address<CoinType>(): address {
    let type_info = type_info::type_of<CoinType>();
    type_info::account_address(&type_info)
  }

  // calculate and return reward value 
  fun calculate_reward(token_address: address, rph: u64, staking_start_time: u64, number_of_tokens: u64, withdraw_amount: u64): u64 {
    let now = timestamp::now_seconds();
    // rps - reward per second
    let rps = rph / 3600;

    // get current level of token
    let level = get_token_level(token_address);

    let reward = ((now - staking_start_time) * (rps * level) * number_of_tokens);
  
    let release_amount = reward - withdraw_amount;
    release_amount
  }

  // return current token level
  fun get_token_level(token_address: address): u64 {
    let property_key = string::utf8(b"level");

    let token_object = object::address_to_object<aptos_token::AptosToken>(token_address);

    let level = property_map::read_u64(&token_object, &property_key);

    level
  }

  public fun get_resource_address(addr: address, seed: String): address acquires ResourceInfo {
    assert!(exists<ResourceInfo>(addr), ENO_STAKING);
    let simple_maps = borrow_global<ResourceInfo>(addr);
    // getting staking address from Resource Info simple map
    let staking_address = *simple_map::borrow(&simple_maps.resource_map, &seed);
    staking_address
  }

  fun check_map(addr: address, key_string: String):bool acquires ResourceInfo {
    if (!exists<ResourceInfo>(addr)) {
      false
    } else {
      let maps = borrow_global<ResourceInfo>(addr);
      simple_map::contains_key(&maps.resource_map, &key_string)
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
  // end of helper functions

  public entry fun create_collection_and_enable_token_upgrade<CoinType>(owner: &signer) acquires CollectionOwnerInfo {
    let collection_name = string::utf8(b"Staking Collection");
    let collection_description = string::utf8(b"Staking NFT collection");
    let collection_uri = string::utf8(b"Empty");
    let max_supply = 100;

    let resource_seed = collection_name;
    string::append(&mut resource_seed, collection_description);
    
    // create resource account
    let (_resource, resource_cap) = account::create_resource_account(owner, bcs::to_bytes(&resource_seed));
    let resource_signer_from_cap = account::create_signer_with_capability(&resource_cap);
    let resource_signer_address = signer::address_of(&resource_signer_from_cap);

    init_or_update_staking_creators(owner, collection_name, resource_signer_address);

    // need for token upgrade
    move_to<AdminData>(&resource_signer_from_cap, AdminData {
      signer_cap: resource_cap,
      source: signer::address_of(owner),
      coin_type: coin_address<CoinType>(),
    });

    let token_uris = vector<String>[
      string::utf8(b"https://raw.githubusercontent.com/aptos-gaming/public-assets/main/planets/1.png"),
      string::utf8(b"https://raw.githubusercontent.com/aptos-gaming/public-assets/main/planets/2.png"),
      string::utf8(b"https://raw.githubusercontent.com/aptos-gaming/public-assets/main/planets/3.png"),
      string::utf8(b"https://raw.githubusercontent.com/aptos-gaming/public-assets/main/planets/4.png"),
      string::utf8(b"https://raw.githubusercontent.com/aptos-gaming/public-assets/main/planets/5.png"),
      string::utf8(b"https://raw.githubusercontent.com/aptos-gaming/public-assets/main/planets/6.png"),
      string::utf8(b"https://raw.githubusercontent.com/aptos-gaming/public-assets/main/planets/7.png"),
      string::utf8(b"https://raw.githubusercontent.com/aptos-gaming/public-assets/main/planets/8.png"),
      string::utf8(b"https://raw.githubusercontent.com/aptos-gaming/public-assets/main/planets/9.png"),
      string::utf8(b"https://raw.githubusercontent.com/aptos-gaming/public-assets/main/planets/10.png"),
    ];

    // create collection
    aptos_token::create_collection(
      &resource_signer_from_cap,
      collection_description,
      max_supply,
      collection_name,
      collection_uri,
      false, // mutable_description
      false, // mutable_royalty
      false, // mutable_uri
      false, // mutable_token_description
      false, // mutable_token_name
      true, // mutable_token_properties
      false, // mutable_token_uri
      true, // tokens_burnable_by_creator
      true, // tokens_freezable_by_creator
      1, // royalty_numerator
      1, // royalty_denominator
    );

    let i = 1;

    while (i <= vector::length(&token_uris)) {
      let token_name = string::utf8(b"Planet #");
      string::append(&mut token_name, string_utils::to_string(&i));

      let token_uri = *vector::borrow<String>(&token_uris, i - 1);
            
      let token_object = aptos_token::mint_token_object(
        &resource_signer_from_cap,
        collection_name,
        collection_description,
        token_name,
        token_uri,
        vector<String>[string::utf8(b"level")],
        vector<String>[string::utf8(b"u64") ],
        vector<vector<u8>>[bcs::to_bytes<u64>(&i)],
      );
      
      // transfer token from resource account to the main account
      object::transfer<aptos_token::AptosToken>(&resource_signer_from_cap, token_object, @owner_addr);

      i = i + 1;
    }
  }

  public entry fun upgrade_token<CoinType>(user: &signer, collection_owner_addr: address, token_address: address) acquires AdminData {
    let user_addr = signer::address_of(user);

    assert!(exists<AdminData>(collection_owner_addr), ENO_COLLECTION_DOESNT_EXIST);
    let admin_data = borrow_global<AdminData>(collection_owner_addr);

    let property_key = string::utf8(b"level");
    let property_type = string::utf8(b"u64");
    
    let token_object = object::address_to_object<aptos_token::AptosToken>(token_address);

    // read current property value 
    let current_level = property_map::read_u64(&token_object, &property_key);
    let new_level = current_level + 1;
    
    let coin_balance = coin::balance<CoinType>(user_addr);

    let coin_decimals = coin::decimals<CoinType>();

    let required_amount_for_level = COINS_PER_LEVEL * math64::pow(10, (coin_decimals as u64)) * current_level;

    assert!(coin_balance >= required_amount_for_level, EINSUFFICIENT_COIN_BALANCE);

    let admin_signer_from_cap = account::create_signer_with_capability(&admin_data.signer_cap);
    
    // only owner of collection can update properties
    aptos_token::update_property(&admin_signer_from_cap, token_object, property_key, property_type, bcs::to_bytes(&new_level));

    // send coins
    coin::transfer<CoinType>(user, @owner_addr, required_amount_for_level);
  }


  // staking part
  // create new resource_account with staking_treasury and ResourceStaking resource
  // and also send some initial Coins to staking_treasury account
  public entry fun create_staking<CoinType>(
    staking_creator: &signer, rph: u64, collection_name: String, coins_amount: u64,
  ) acquires ResourceInfo {
    // create new staking resource account
    let (staking_treasury, staking_treasury_cap) = account::create_resource_account(staking_creator, bcs::to_bytes(&collection_name));
    let staking_treasury_signer_from_cap = account::create_signer_with_capability(&staking_treasury_cap);
    let staking_address = signer::address_of(&staking_treasury);

    // init ResourceInfo on main signer
    create_and_add_resource_info(staking_creator, collection_name, staking_address);
    // register new resource on just created staking account
    managed_coin::register<CoinType>(&staking_treasury_signer_from_cap);
    // move coins_amount of CoinType to just created resource account - staking_treasury
    coin::transfer<CoinType>(staking_creator, staking_address, coins_amount);
    
    // init ResourceStaking on treasury account
    move_to<ResourceStaking>(&staking_treasury_signer_from_cap, ResourceStaking {
      collection: collection_name,
      rph,
      status: true,
      amount: coins_amount,
      coin_type: coin_address<CoinType>(),
      treasury_cap: staking_treasury_cap,
    });
  }

  public entry fun stake_token(
    staker: &signer, staking_creator_addr: address, collection_owner_addr: address, token_address: address, collection_name: String, token_name: String, tokens: u64,
  ) acquires ResourceStaking, ResourceInfo, EventsStore, AdminData, ResourceReward {

    let staker_addr = signer::address_of(staker);
    let staking_address = get_resource_address(staking_creator_addr, collection_name);

    assert!(exists<AdminData>(collection_owner_addr), ENO_COLLECTION_DOESNT_EXIST);
    let admin_data = borrow_global<AdminData>(collection_owner_addr);
    let resource_signer = account::create_signer_with_capability(&admin_data.signer_cap);

    // staking can create anyone (not only creator of collection)
    assert!(exists<ResourceStaking>(staking_address), ESTOPPED_STAKING);

    let staking_data = borrow_global<ResourceStaking>(staking_address);
    assert!(staking_data.status, ESTOPPED_STAKING);
    
    let token_seed = collection_name;
    let additional_seed = token_name;
    string::append(&mut token_seed, additional_seed);

    // check if staker_addr has ResourceInfo with resource_map inside it with
    let should_pass_restake = check_map(staker_addr, token_seed);

    let now = timestamp::now_seconds();

    init_events_store(staker);

    let staking_event_store = borrow_global_mut<EventsStore>(staker_addr);

    // token still on owner address and will be transfered to resource account later
    let token_level = get_token_level(token_address);

    event::emit_event<StakeEvent>(
      &mut staking_event_store.stake_events,
      StakeEvent {
        token_address,
        timestamp: now,
        token_level,
      },
    );

    let token_object = object::address_to_object<aptos_token::AptosToken>(token_address);

    if (should_pass_restake) {
      // token was already in staking before
      let reward_treasury_addr = get_resource_address(staker_addr, token_seed);
      // check if resource account has ResourceReward
      assert!(exists<ResourceReward>(reward_treasury_addr), ENO_REWARD_RESOURCE);

      // get resource data
      let reward_data = borrow_global_mut<ResourceReward>(reward_treasury_addr);

      // update reward_data after new staking started
      reward_data.tokens = tokens;
      reward_data.start_time = now;
      reward_data.withdraw_amount = 0;

      // freeze token transfer by collection creator
      aptos_token::freeze_transfer<aptos_token::AptosToken>(&resource_signer, token_object);
    } else {
      // first try to stake nft
      // create some new resource account based on token seed
      let (reward_treasury, reward_treasury_cap) = account::create_resource_account(staker, bcs::to_bytes(&token_seed));
      let reward_treasury_signer_from_cap = account::create_signer_with_capability(&reward_treasury_cap);
      let reward_treasury_addr = signer::address_of(&reward_treasury);

      assert!(!exists<ResourceReward>(reward_treasury_addr), ENO_STAKING_ADDRESS);
      // init/update ResourceInfo
      create_and_add_resource_info(staker, token_seed, reward_treasury_addr);

      // freeze token instead of send by collection creator
      aptos_token::freeze_transfer<aptos_token::AptosToken>(&resource_signer, token_object);

      // init ResourceReward resource on special resource account
      move_to<ResourceReward>(&reward_treasury_signer_from_cap, ResourceReward {
        staker: staker_addr,
        token_name,
        collection_name,
        withdraw_amount: 0, 
        treasury_cap: reward_treasury_cap,
        start_time: now,
        tokens,
      });
    };
  }

  public entry fun unstake_token<CoinType>(
    staker: &signer, staking_creator_addr: address, collection_owner_addr: address,token_address: address, collection_name: String, token_name: String,
  ) acquires ResourceReward, ResourceStaking, ResourceInfo, EventsStore, AdminData {
    let staker_addr = signer::address_of(staker);

    assert!(exists<AdminData>(collection_owner_addr), ENO_COLLECTION_DOESNT_EXIST);
    let admin_data = borrow_global<AdminData>(collection_owner_addr);
    let resource_signer = account::create_signer_with_capability(&admin_data.signer_cap);

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

    // get reward treasury address which hold the tokens/nfts
    let reward_treasury_addr = get_resource_address(staker_addr, token_seed);
    assert!(exists<ResourceReward>(reward_treasury_addr), ENO_STAKING_ADDRESS);

    // getting resource data, same as for staking
    let reward_data = borrow_global_mut<ResourceReward>(reward_treasury_addr);
    
    // check that staker address stored inside MetaReward staker
    assert!(reward_data.staker == staker_addr, ESTAKER_MISMATCH);

    let release_amount = calculate_reward(token_address, staking_data.rph, reward_data.start_time, reward_data.tokens, reward_data.withdraw_amount);

    // check if address of CoinType that we want to withward are equal to CoinType address stored in staking_data
    assert!(coin_address<CoinType>() == staking_data.coin_type, ECOIN_TYPE_MISMATCH); 

    if (staking_data.amount < release_amount) {
      staking_data.status = false
    };
    if (staking_data.amount > release_amount) {
      // check if address where we gonna send reward, cointains valid CoinType resource
      if (!coin::is_account_registered<CoinType>(staker_addr)) {
        managed_coin::register<CoinType>(staker);
      };
    };

    assert!(exists<EventsStore>(staker_addr), ENO_STAKING_EVENT_STORE);

    let staking_event_store = borrow_global_mut<EventsStore>(staker_addr);

    let token_level = get_token_level(token_address);

    // trigger unstake event
    event::emit_event<UnstakeEvent>(
      &mut staking_event_store.unstake_events,
      UnstakeEvent {
        token_address,
        timestamp: timestamp::now_seconds(),
        token_level,
      },
    );

    // transfer coins from treasury to staker address
    coin::transfer<CoinType>(&staking_treasury_signer_from_cap, staker_addr, release_amount);

    let token_object = object::address_to_object<aptos_token::AptosToken>(token_address);

    // unfreeze token
    aptos_token::unfreeze_transfer<aptos_token::AptosToken>(&resource_signer, token_object);

    // update how many coins left in module
    staking_data.amount = staking_data.amount - release_amount;

    // reset reward and staking data
    reward_data.tokens = 0;
    reward_data.start_time = 0;
    reward_data.withdraw_amount = 0;
  }

  public entry fun claim_reward<CoinType>(
    staker: &signer, staking_creator_addr: address, token_address: address, collection_name: String, token_name: String,
  ) acquires ResourceReward, ResourceStaking, ResourceInfo, EventsStore {
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

    let release_amount = calculate_reward(token_address, staking_data.rph, reward_data.start_time, reward_data.tokens, reward_data.withdraw_amount);

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

    assert!(exists<EventsStore>(staker_addr), ENO_STAKING_EVENT_STORE);

    let staking_event_store = borrow_global_mut<EventsStore>(staker_addr);

    let token_level = get_token_level(token_address);

    // trigger claim event
    event::emit_event<ClaimEvent>(
      &mut staking_event_store.claim_events,
      ClaimEvent {
        token_address,
        token_name,
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


  #[view]
  public fun get_unclaimed_reward(
    staker_addr: address, staking_creator_addr: address, token_address: address, collection_name: String, token_name: String,
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
  
    calculate_reward(token_address, staking_data.rph, reward_data.start_time, reward_data.tokens, reward_data.withdraw_amount)
  }
}