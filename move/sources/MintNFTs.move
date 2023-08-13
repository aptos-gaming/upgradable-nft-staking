module owner_addr::mint_and_manage_tokens {
  use aptos_std::signer;
  use aptos_std::string::{ Self, String };
  use aptos_std::string_utils;
  use aptos_std::vector;
  use aptos_std::math64;
  use aptos_std::type_info;

  use aptos_framework::coin;
  use aptos_framework::account;
  use aptos_framework::simple_map::{ Self, SimpleMap };

  use std::bcs::to_bytes;
  use std::bcs;

  use aptos_token::token::{ Self };
  use aptos_token::property_map;

  const MAX_LEVEL: u64 = 10;
  const COINS_PER_LEVEL: u64 = 100;

  const EMAX_LEVEL_REACHED: u64 = 1;
  const ENO_TOKEN_IN_TOKEN_STORE: u64 = 2;
  const EINSUFFICIENT_COIN_BALANCE: u64 = 3;
  const ENO_COIN_TYPE: u64 = 4;
  const ENO_COLLECTION: u64 = 5;
  const ENO_UPGRADE: u64 = 6;
  const ECOIN_TYPE_MISMATCH: u64 = 7;
  const ENO_RESOURCE_ACCOUNT: u64 = 8;

  struct MintTokensResourceInfo has key {
    signer_cap: account::SignerCapability,
    source: address,
    coin_type: address,
  }

  struct UpdateTokenInfo has key {
    map: SimpleMap<String, address>,
  }

  fun create_and_add_update_token_info(account: &signer, collection_name: String, resource_signer_address: address) acquires UpdateTokenInfo {
    let account_addr = signer::address_of(account);
    if (!exists<UpdateTokenInfo>(account_addr)) {
      move_to(account, UpdateTokenInfo {
        map: simple_map::create()
      })
    };
    let maps = borrow_global_mut<UpdateTokenInfo>(account_addr);
    simple_map::add(&mut maps.map, collection_name, resource_signer_address);
  }

  #[view]
  fun get_resource_address(creator: address, collection_name: String): address acquires UpdateTokenInfo {
    assert!(exists<UpdateTokenInfo>(creator), ENO_UPGRADE);
    let simple_maps = borrow_global<UpdateTokenInfo>(creator);

    let resource_address = *simple_map::borrow(&simple_maps.map, &collection_name);
    resource_address
  }

  // return address of CoinType coin
  fun coin_address<CoinType>(): address {
    let type_info = type_info::type_of<CoinType>();
    type_info::account_address(&type_info)
  }

  public entry fun create_collection_and_enable_token_upgrade<CoinType>(owner: &signer) acquires UpdateTokenInfo {
    let collection_name = string::utf8(b"Galactic Collection");
    let description = string::utf8(b"Galactic NFT collection");
    let uri = string::utf8(b"https://aptos.dev/");
    let max_nfts = 100;

    let resource_seed = collection_name;
    let additional_seed = description;
    string::append(&mut resource_seed, additional_seed);

    let (_resource, resource_cap) = account::create_resource_account(owner, to_bytes(&resource_seed));
    let resource_signer_from_cap = account::create_signer_with_capability(&resource_cap);

    move_to<MintTokensResourceInfo>(&resource_signer_from_cap, MintTokensResourceInfo {
      signer_cap: resource_cap,
      source: signer::address_of(owner),
      coin_type: coin_address<CoinType>(),
    });

    let resource_signer_address = signer::address_of(&resource_signer_from_cap);

    create_and_add_update_token_info(owner, collection_name, resource_signer_address);

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

    token::create_collection(&resource_signer_from_cap, collection_name, description, uri, max_nfts, vector<bool>[false, false, false]);

    let i = 1;

    while (i <= 10) {
      let token_name = string::utf8(b"Planet #");
      string::append(&mut token_name, string_utils::to_string(&i));

      let token_uri = *vector::borrow<String>(&token_uris, i - 1);

      let token_data_id = token::create_tokendata(
        &resource_signer_from_cap,
        collection_name,
        token_name,
        string::utf8(b"Planet ownership allows landlord to extract valuable resources."),
        1,
        token_uri,
        signer::address_of(owner),
        1,
        0,
        token::create_token_mutability_config(
            &vector<bool>[ false, false, false, false, true ]
        ),
        vector<String>[string::utf8(b"level")],
        vector<vector<u8>>[bcs::to_bytes<u64>(&i)],
        vector<String>[string::utf8(b"u64") ],
      );
      // token will be minted by resource account
      let token_id = token::mint_token(&resource_signer_from_cap, token_data_id, 1);
      // token will be transfered from resource account to main account
      token::direct_transfer(&resource_signer_from_cap, owner, token_id, 1);
      i = i + 1;
    }
  }

  public entry fun upgrade_token<CoinType>(
    owner: &signer, creator_addr: address, collection_name: String, token_name: String, property_version: u64,
  ) acquires MintTokensResourceInfo {
    let owner_addr = signer::address_of(owner);

    // check if collection exist
    assert!(token::check_collection_exists(creator_addr, collection_name), ENO_COLLECTION);

    let token_id = token::create_token_id_raw(creator_addr, collection_name, token_name, property_version);
    // check if owner has valid token balance
    assert!(token::balance_of(owner_addr, token_id) >= 1, ENO_TOKEN_IN_TOKEN_STORE);

    let pm = token::get_property_map(owner_addr, token_id);

    let current_level = property_map::read_u64(&pm, &string::utf8(b"level"));

    let token_admin_data = borrow_global<MintTokensResourceInfo>(creator_addr);

    // check if address of CoinType that we want to withdraw are equal to CoinType address stored in staking_data
    assert!(coin_address<CoinType>() == token_admin_data.coin_type, ECOIN_TYPE_MISMATCH); 

    // check if owner address has such CoinType
    assert!(coin::is_account_registered<CoinType>(owner_addr), ENO_COIN_TYPE);

    let coin_balance = coin::balance<CoinType>(owner_addr);

    let coin_decimals = coin::decimals<CoinType>();

    let required_amount_for_level = COINS_PER_LEVEL * math64::pow(10, (coin_decimals as u64)) * current_level;

    assert!(coin_balance >= required_amount_for_level, EINSUFFICIENT_COIN_BALANCE);
    
    // check if token reached max level or not
    assert!(current_level < MAX_LEVEL, EMAX_LEVEL_REACHED);

    let token_data_id = token::create_token_data_id(creator_addr, collection_name, token_name);

    let new_level = current_level + 1;

    let update_token_signer_from_cap = account::create_signer_with_capability(&token_admin_data.signer_cap);

    token::mutate_tokendata_property(
      &update_token_signer_from_cap, // only owner of collection can mutate tokendata
      token_data_id,
      vector<String>[string::utf8(b"level")], // keys
      vector<vector<u8>>[bcs::to_bytes<u64>(&new_level)], // values
      vector<String>[string::utf8(b"u64")],    // types
    );
    
    // send coins to module owner address (@owner_addr)
    coin::transfer<CoinType>(owner, @owner_addr, required_amount_for_level);
  }
}
