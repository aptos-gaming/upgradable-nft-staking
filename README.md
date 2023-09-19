### Local testing

1. Follow the official [Aptos CLI installation guide](https://aptos.dev/tools/install-cli/)
2. Create new aptos account with `aptos init` (will create new folder .aptos and store public and private key in it)
3. Import private_key from .aptos to Petra Extension
4. Mint Minerals coin and deploy 2 staking modules using account (owner_addr) in `Move.toml` from `.aptos/config.yaml` 'account' field 
    Run `aptos move publish --named-addresses owner_addr=account` in /move folder
5. Go to main react app and change module address in `config.json` with account from `.aptos`
6. Install all frontend dependecies in `/frontend` and then run main app `npm run start` and connect wallet and click on `Create Collection With Token Upgrade` button
7. Click on `Init Minerals Staking` on Basic Token Staking tab or Upgradeble Token Staking tab.
8. Connect new address to the UI and click on `Stake`
9. You can also upgrade you token level using `Upgrade` button (but only in Upgrade Token Staking tab)

To stake:
1. Run Init Staking and confirm transaction
2. Select any NFT from table and click on it, than you can manage it by `Stake/Unstake/Claim`
 If you have any unclaimed coins, they will be displayed


Modules 
- mint_coins.move - module that init new coin - Minerals and mint 100k to owner address
- mint_upgrade_tokens_v1.move - module that create resource account, that creates collection and mint 10 nfts to owner address, also contains `upgrade_token` method
- token_v1_staking.move - basic staking module based on dph reward for each NFT
- upgradable_token_v1_staking.move - advanced NFT staking module, that calculate reward based on token "level" property
- mint_stake_upgrade_tokens_v2.move - mint tokensV2 and have advanced NFT staking module, that calculate reward based on token "level" property for tokenV2

#### Deployed Modules on Testnet can be found here:
[0f663e428a90eb3f7a485383a54511720e69a92d52e12d2d06fcc2af0bb3897e](https://explorer.aptoslabs.com/account/0f663e428a90eb3f7a485383a54511720e69a92d52e12d2d06fcc2af0bb3897e?network=testnet)


# MintNFTS

## Entrypoins

### `Upgrade Token`

Upgrade token level to the current level + 1, required COINS_PER_LEVEL * current level coins for each level. Max level is 10.
           
Arguments: `owner: &signer, creator_addr: address, collection_name: String, token_name: String, property_version: u64`

Type Arguments: any `CoinType` which will be used as a reward coin

Usage:

```js
const moduleAddress = "0x1"; // pass your module address
const collectionOwnerAddress = "0x2"; // pass your collection owner address
const rewardCoinType = `${moduleAddress}::mint_coins::Minerals`; // might be aptos coin or any custom coin type
const collectionName = "Test Collection";
const tokenName = "Token 1";
const propertyVersion = "0";
const packageName = "mint_upgrade_tokens_v1"

const payload = {
    type: "entry_function_payload",
    function: `${moduleAddress}::${packageName}::upgrade_token`,
    type_arguments: [RewardCoinType],
    arguments: [collectionOwnerAddress, collectionName, tokenName, propertyVersion ],
}
try {
    const txResult = await signAndSubmitTransaction(payload);
    await client.waitForTransactionWithResult(txResult.hash)
} catch (e) {
    console.log(e)
}
```


# NftStaking


## Entrypoints

### `Create Staking`

Create and enable staking for new collection, set default reward per hour for staking 1 token and transfer initial amount of coins to rewards treasury.
           
Arguments: `staking_creator: &signer, collection_owner_addr: address, rph: u64, collection_name: String, total_amount: u64`

Type Arguments: any `CoinType` which will be used as a reward coin

Usage:

```js
const tokensPerHour = 36; // number of coins that will be received in 1 hour of staking
const treasuryCoins = 50000; // number of coins that will be send to treasury
const moduleAddress = "0x1"; // pass your module address
const collectionCreatorAddress = "0x2"
const rewardCoinType = `${moduleAddress}::mint_coins::Minerals`; // might be aptos coin or any custom coin type
const decimals = 8;

const payload = {
    type: "entry_function_payload",
    function: `${moduleAddress}::token_v1_staking::create_staking`,
    type_arguments: [rewardCoinType],
    arguments: [collectionCreatorAddress, tokensPerHour * (10 ** decimals), CollectionName, treasuryCoins * (10 ** decimals)],
}
// submit a tx
try {
    const txResult = await signAndSubmitTransaction(payload);
    await client.waitForTransactionWithResult(txResult.hash)
} catch (e) {
    console.log(e)
}
```

### `Stake Token`

Token will be moved from sender address to resource account and start receiving rewards for staking.

Arguments: `staker: &signer, staking_creator_addr: address, collection_owner_addr: addres, collection_name: String, token_name: String, property_version: u64, tokens: u64`

Usage:

```js
const collectionName = "Test Collection";
const tokenName = "Token 1";
const propertyVersion = "0";
const tokens = "1"; // set a number of tokens you want to stake
const stakingCreatorAddress = "0x1";
const collectionCreatorAddress = "0x2"

const payload = {
    type: "entry_function_payload",
    function: `${moduleAddress}::token_v1_staking::stake_token`,
    type_arguments: [],
    arguments: [stakingCreatorAddress, collectionCreatorAddress, collectionName, tokenName, propertyVersion, tokens]
}
try {
    const txResult = await signAndSubmitTransaction(payload);
    await client.waitForTransactionWithResult(txResult.hash)
} catch (e) {
    console.log(e)
}
```

### `Unstake Token`

Token will be moved from resource account staker address, stop staking and claim current pending reward.
           
Arguments: `staker: &signer, staking_creator_addr: address, collection_owner_addr: address, collection_name: String, token_name: String, property_version: u64`

Type Arguments: `CoinType` that was used during staking init.

Usage:

```js
const collectionName = "Test Collection";
const tokenName = "Token 1";
const propertyVersion = "0";
const rewardCoinType = `${moduleAddress}::mint_coins::Minerals`; // might be aptos coin or any custom coin type
const stakingCreatorAddress = "0x1";
const collectionCreatorAddress = "0x2"

const payload = {
    type: "entry_function_payload",
    function: `${moduleAddress}::token_v1_staking::unstake_token`,
    type_arguments: [RewardCoinType],
    arguments: [stakingCreatorAddress, collectionCreatorAddress, collectionName, tokenName, propertyVersion]
}
try {
    const txResult = await signAndSubmitTransaction(payload);
    await client.waitForTransactionWithResult(txResult.hash)
} catch (e) {
    console.log(e)
}
```

### `Claim Reward`

Claim current pending reward to staker address based on rph rate.

Arguments: `staker: &signer, staking_creator_addr: address, collection_owner_addr: address, collection_name: String, token_name: String, property_version: u64`

Type Arguments: `CoinType` that was used during staking init.

Usage:

```js
const collectionName = "Test Collection";
const tokenName = "Token 1";
const propertyVersion = "0";
const rewardCoinType = `${moduleAddress}::mint_coins::Minerals`; // might be aptos coin or any custom coin type
const stakingCreatorAddress = "0x1";
const collectionCreatorAddress = "0x2"

const payload = {
    type: "entry_function_payload",
    function: `${moduleAddress}::token_v1_staking::claim_reward`,
    type_arguments: [rewardCoinType],
    arguments: [stakingCreatorAddress, collectionCreatorAddress, collectionName, tokenName, propertyVersion],
}
try {
    const txResult = await signAndSubmitTransaction(payload);
    await client.waitForTransactionWithResult(txResult.hash)
} catch (e) {
    console.log(e)
}
```

## View Functions

### `Get Unclaimed Reward`

Return number of unclaimed coins for the staked token.

Arguments: `staker_addr: address, staking_creator_addr: address, collection_name: String, token_name: String`

Usage:

```js
const collectionName = "Test Collection";
const tokenName = "Token 1";
const stakingCreatorAddress = "0x1";

const payload = {
    function: `${moduleAddress}::token_v1_staking::get_unclaimed_reward`,
    type_arguments: [],
    arguments: [account.address, stakingCreatorAddress, collectionName, tokenName]
}

try {
    const unclaimedReward = await provider.view(payload)
    console.log(unclaimedReward[0] / 10 ** Decimals)
} catch(e) {
    console.log(e)
}
```

### `Get Staking Tokens`

Return array of TokenIds that currently staking by owner address.

Arguments: `owner_addr: address`

Usage:

```js
const payload = {
    function: `${moduleAddress}::token_v1_staking::get_tokens_staking_statuses`,
    type_arguments: [],
    arguments: [account.address]
}

try {
    const response = await provider.view(payload)
    console.log(response[0])
} catch(e) {
    console.log("Error during getting staked token ids")
}
```




# UpgradableNftStaking

Module will work only for tokens that have `level` properties, if you dont need such feature - just use a basic `NftStaking` module.

Customization:
- if you want to change main token property name, open `upgradable_token_v1_staking.move` and change `level`  in `get_nft_lvl` function.
- if you want to change reward calculation for different levels, open `upgradable_token_v1_staking.move` and change calculation of reward in `calculate_reward` function.


## Entrypoints

### `Create Staking`

Create and enable staking for new collection, set default reward per hour for staking 1 token and transfer initial amount of coins to rewards treasury.
Staking creator can be anyone, not only the creator of the collection.

Arguments: `staking_creator: &signer, collection_owner_addr: address, rph: u64, collection_name: String, total_amount: u64`

Type Arguments: any `CoinType` which will be used as a reward coin

Usage:

```js
const tokensPerHour = 36; // number of coins that will be received in 1 hour of staking
const treasuryCoins = 50000; // number of coins that will be send to treasury
const moduleAddress = "0x1"; // pass your module address
const collectionOwnerAddress = "0x2";
const rewardCoinType = `${moduleAddress}::mint_coins::Minerals`; // might be aptos coin or any custom coin type
const decimals = 8;

const payload = {
    type: "entry_function_payload",
    function: `${moduleAddress}::upgradable_token_v1_staking::create_staking`,
    type_arguments: [rewardCoinType],
    arguments: [collectionOwnerAddress, tokensPerHour * (10 ** decimals), CollectionName, treasuryCoins * (10 ** decimals)],
}
// submit a tx
try {
    const txResult = await signAndSubmitTransaction(payload);
    await client.waitForTransactionWithResult(txResult.hash)
} catch (e) {
    console.log(e)
}
```

### `Stake Token`

Token will be moved from sender address to resource account, emit `StakeEvent` and start receiving rewards for staking.

Arguments: `staker: &signer, staking_creator_addr: address, collection_owner_addr: address, collection_name: String, token_name: String, property_version: u64, tokens: u64`

Usage:

```js
const collectionName = "Test Collection";
const tokenName = "Token 1";
const propertyVersion = "0";
const stakingCreatorAddress = "0x1";
const collectionOwnerAddress = "0x2";
const tokens = "1"; // set a number of tokens you want to stake

const payload = {
    type: "entry_function_payload",
    function: `${moduleAddress}::upgradable_token_v1_staking::stake_token`,
    type_arguments: [],
    arguments: [stakingCreatorAddress, collectionOwnerAddress, collectionName, tokenName, propertyVersion, tokens]
}
try {
    const txResult = await signAndSubmitTransaction(payload);
    await client.waitForTransactionWithResult(txResult.hash)
} catch (e) {
    console.log(e)
}
```

### `Unstake Token`

Token will be moved from resource account staker address, emit `UnstakeEvent`, stop staking and claim current pending reward.

Arguments: `staker: &signer, staking_creator_addr: address, collection_owner_addr: address, collection_name: String, token_name: String, property_version: u64`

Type Arguments: `CoinType` that was used during staking init.

Usage:

```js
const collectionName = "Test Collection";
const tokenName = "Token 1";
const propertyVersion = "0";
const stakingCreatorAddress = "0x1";
const collectionOwnerAddress = "0x2";
const rewardCoinType = `${moduleAddress}::mint_coins::Minerals`; // might be aptos coin or any custom coin type

const payload = {
    type: "entry_function_payload",
    function: `${moduleAddress}::upgradable_token_v1_staking::unstake_token`,
    type_arguments: [RewardCoinType],
    arguments: [stakingCreatorAddress, collectionOwnerAddress, collectionName, tokenName, propertyVersion]
}
try {
    const txResult = await signAndSubmitTransaction(payload);
    await client.waitForTransactionWithResult(txResult.hash)
} catch (e) {
    console.log(e)
}
```

### `Claim Reward`

Emit `ClaimEvent` and claim current pending reward to staker address based on Token level.
Token level - is a miltiplier for basic (setted during staking init) reward per hour. So, if you set reward per hour to 10, but stake Token with level 2 - you will get 20 (10 * 2) coins per hour.

Arguments: `staker: &signer, staking_creator_addr: address, collection_owner_addr: address,  collection_name: String, token_name: String, property_version: u64`

Type Arguments: `CoinType` that was used during staking init.

Usage:

```js
const collectionName = "Test Collection";
const tokenName = "Token 1";
const propertyVersion = "0";
const stakingCreatorAddress = "0x1";
const collectionOwnerAddress = "0x2";
const rewardCoinType = `${moduleAddress}::mint_coins::Minerals`; // might be aptos coin or any custom coin type

const payload = {
    type: "entry_function_payload",
    function: `${moduleAddress}::upgradable_token_v1_staking::claim_reward`,
    type_arguments: [rewardCoinType],
    arguments: [stakingCreatorAddress, collectionOwnerAddress, collectionName, tokenName, propertyVersion],
}
try {
    const txResult = await signAndSubmitTransaction(payload);
    await client.waitForTransactionWithResult(txResult.hash)
} catch (e) {
    console.log(e)
}
```

## View Functions

### `Get Unclaimed Reward`

Return number of unclaimed coins for the staked token.

Arguments: `staker_addr: address, staking_creator_addr: address, collection_owner_addr: address, collection_name: String, token_name: String, property_version: u64`

Usage:

```js
const collectionName = "Test Collection";
const tokenName = "Token 1";
const propertyVersion = "0";
const stakingCreatorAddress = "0x1";
const collectionOwnerAddress = "0x2";

const payload = {
    function: `${moduleAddress}::upgradable_token_v1_staking::get_unclaimed_reward`,
    type_arguments: [],
    arguments: [account.address, stakingCreatorAddress, collectionOwnerAddress, collectionName, tokenName, propertyVersion]
}

try {
    const unclaimedReward = await provider.view(payload)
    console.log(unclaimedReward[0] / 10 ** Decimals)
} catch(e) {
    console.log(e)
}
```

### `Get Staking Tokens`

Return array of TokenIds that currently staking by owner address.

Arguments: `owner_addr: address`

Usage:

```js
const payload = {
    function: `${moduleAddress}::upgradable_token_v1_staking::get_tokens_staking_statuses`,
    type_arguments: [],
    arguments: [account.address]
}

try {
    const response = await provider.view(payload)
    console.log(response[0])
} catch(e) {
    console.log("Error during getting staked token ids")
}
```

### `Get List of Events`

Module has 3 basic events: `ClaimEvent`, `StakeEvent`, `UnstakeEvent` with following formats:
*basic token staking events doesn't have `token_level` field.

```sh
StakeEvent {
    token_id: TokenId,
    token_level: number,
    timestamp: number,
}

UnstakeEvent {
    token_id: TokenId,
    token_level: number,
    timestamp: number,
}

ClaimEvent {
    token_id: TokenId,
    token_level: number,
    coin_amount: number,
    timestamp: number,
}
```

Usage (example with claim events, but you can change `claim_event` to `unstake_events` or `stake_events`)

```js
const eventStore = `${moduleAddress}::upgradable_token_v1_staking::EventsStore`

try {
    const claimEvents = await client.getEventsByEventHandle(account.address, eventStore, "claim_events")
    console.log(claimEvents)
} catch (e) {
    console.log(e)
}
```

Simple Diagram with all resources and staking flow:
![alt text](https://github.com/proxycapital/AptosNftStakingV1/blob/master/stakingDiagram.png)
