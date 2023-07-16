import React, { useEffect, useState } from 'react'
import { Button, Row, Col, Modal } from 'antd';
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { Network, Provider, AptosClient } from "aptos";
import { useApolloClient } from '@apollo/client';

import { AccountTokensWithDataQuery } from './components/NftList'
import useSelectedToken from './context/useSelectedToken'
import useCollectionOwner from './context/useCollectionOwner'
import { TokenData } from './components/NftList'
import EventsTable from './components/EventsTable'
import CONFIG from "./config.json"

const PackageName = "upgradable_nft_staking";

const client = new AptosClient("https://fullnode.devnet.aptoslabs.com/v1")
const provider = new Provider(Network.DEVNET);

const RewardCoinType = `${CONFIG.moduleAddress}::mint_coins::${CONFIG.coinName}`

const Decimals = 8 // coin has 8 decimals (check MintCoins.move)

interface ClaimEvent {
  coin_amount: string,
  timestamp: string,
  token_level: string,
  token_id: {
    property_version: string,
    token_data_id: {
      collection: string,
      creator: string,
      name: string,
    }
  }
}

const UpgradableNftStakingLayout = () => {
  const [unclaimedReward, setUnclaimedReward] = useState(0)
  const [claimEvents, setClaimEvents] = useState<ClaimEvent[]>([])
  const { selectedToken, setSelectedToken } = useSelectedToken()
  const { collectionOwnerAddress, setCollectionOwnerAddress } = useCollectionOwner()
  const apolloClient = useApolloClient()

  const { account, signAndSubmitTransaction } = useWallet()
  
  const getCollectionOwnerAddress = async () => {
    const packageName = "mint_and_manage_tokens"
    const payload = {
      function: `${CONFIG.moduleAddress}::${packageName}::get_resource_address`,
      type_arguments: [],
      // creator, collection_name
      arguments: [CONFIG.moduleAddress, CONFIG.collectionName]
    }

    try {
      const viewResponse = await provider.view(payload)
      setCollectionOwnerAddress(String(viewResponse[0]))
    } catch(e) {
      console.log("Error during getting resource account addres")
      console.log(e)
    }
  }

  const onLevelUpgrade = async () => {
    const packageName = "mint_and_manage_tokens"

    const payload = {
      type: "entry_function_payload",
      function: `${CONFIG.moduleAddress}::${packageName}::upgrade_token`,
      type_arguments: [RewardCoinType],
      // creator_addr, collection_name, token_name, property_version
      arguments: [collectionOwnerAddress, selectedToken?.collection_name, selectedToken?.name, selectedToken?.property_version ],
    }
    try {
      const tx = await signAndSubmitTransaction(payload)
      await client.waitForTransactionWithResult(tx.hash)
      setSelectedToken(null)
      setUnclaimedReward(0)
      await apolloClient.refetchQueries({ include: [AccountTokensWithDataQuery]})
    } catch (e) {
      console.log("ERROR during token upgrade")
    }
  }

  const createCollectionWithTokenUpgrade = async () => {
    const packageName = "mint_and_manage_tokens"

    const payload = {
      type: "entry_function_payload",
      function: `${CONFIG.moduleAddress}::${packageName}::create_collection_and_enable_token_upgrade`,
      type_arguments: [RewardCoinType],    
      arguments: [],
    }
    try {
      const tx = await signAndSubmitTransaction(payload)
      await client.waitForTransactionWithResult(tx.hash)
      await apolloClient.refetchQueries({ include: [AccountTokensWithDataQuery]})

    } catch (e) {
      console.log("ERROR during create_collection_and_enable_token_upgrade")
      console.log(e)
    }
  }

  const createStaking = async () => {
    const tokensPerHour = 36
    const amountToTreasury = 50000

    const payload = {
      type: "entry_function_payload",
      function: `${CONFIG.moduleAddress}::${PackageName}::create_staking`,
      type_arguments: [RewardCoinType],
      // collection_owner_address, dph, collection_name, total_amount
      arguments: [collectionOwnerAddress, tokensPerHour * (10 ** Decimals), CONFIG.collectionName, amountToTreasury * 10 ** Decimals],
    }
    try {
      const tx = await signAndSubmitTransaction(payload);
      await client.waitForTransactionWithResult(tx.hash)
    } catch (e) {
      console.log("ERROR during create staking tx")
      console.log(e)
    }
  }

  const onStakeToken = async () => {
    const payload = {
      type: "entry_function_payload",
      function: `${CONFIG.moduleAddress}::${PackageName}::stake_token`,
      type_arguments: [],
      // staking_creator_addr, collection_creator_addr, collection_name, token_name, property_version, tokens
      arguments: [CONFIG.moduleAddress, collectionOwnerAddress, selectedToken?.collection_name, selectedToken?.name, String(selectedToken?.property_version), "1"]
    }
    try {
      const tx = await signAndSubmitTransaction(payload)
      setSelectedToken(null)
      setUnclaimedReward(0)
      await client.waitForTransactionWithResult(tx.hash)
      await apolloClient.refetchQueries({ include: [AccountTokensWithDataQuery]})
    } catch (e) {
      console.log("Error druing stake token tx")
      console.log(e)
    }
  }

  const onUnstakeStaking = async () => {
    const payload = {
      type: "entry_function_payload",
      function: `${CONFIG.moduleAddress}::${PackageName}::unstake_token`,
      type_arguments: [RewardCoinType],
      // staking_creator_addr, collection_creator_addr, collection_name, token_name, property_version
      arguments: [CONFIG.moduleAddress, collectionOwnerAddress, selectedToken?.collection_name, selectedToken?.name, String(selectedToken?.property_version)]
    }
    try {
      const tx = await signAndSubmitTransaction(payload)
      setSelectedToken(null)
      setUnclaimedReward(0)
      await client.waitForTransactionWithResult(tx.hash)
      await apolloClient.refetchQueries({ include: [AccountTokensWithDataQuery]})
    } catch (e) {
      console.log("Error druing unstake token tx")
      console.log(e)
    }
  }

  const onClaimReward = async () => {
    const payload = {
      type: "entry_function_payload",
      function: `${CONFIG.moduleAddress}::${PackageName}::claim_reward`,
      type_arguments: [RewardCoinType],
      arguments: [CONFIG.moduleAddress, collectionOwnerAddress, selectedToken?.collection_name, selectedToken?.name, selectedToken?.property_version],
    }
    try {
      const tx = await signAndSubmitTransaction(payload)
      setSelectedToken(null)
      setUnclaimedReward(0)
      await client.waitForTransactionWithResult(tx.hash)
      getClaimEvents()
    } catch (e) {
      console.log("Error druing claim reward tx")
      console.log(e)
    }
  }

  const getClaimEvents = async () => {
    const stakingEventStore = `${CONFIG.moduleAddress}::${PackageName}::StakingEventStore`

    try {
      const claimEvents = await client.getEventsByEventHandle(account?.address || '', stakingEventStore, "claim_events")
      const formmatedClaimEvents = claimEvents.map((claimEvent) => ({
        ...claimEvent.data,
        token_name: claimEvent.data.token_id.token_data_id.name,
      }))
      setClaimEvents(formmatedClaimEvents)
    } catch (e: any) {
      const errorMessage = JSON.parse(e.message)
      if (errorMessage.error_code === "resource_not_found") {
        console.log("No claims for upgradable token staking")
      }
    }
  }

  const getUnclaimedReward = async (token: TokenData) => {
    const payload = {
      function: `${CONFIG.moduleAddress}::${PackageName}::get_unclaimed_reward`,
      type_arguments: [],
      // staker_addr, staking_creator_addr, collection_creator_addr, collection_name, token_name, property_version
      arguments: [account?.address, CONFIG.moduleAddress, collectionOwnerAddress, token?.collection_name, token?.name, String(token?.property_version)]
    }

    try {
      const unclaimedReward = await provider.view(payload)
      setUnclaimedReward(Number(unclaimedReward[0]) / 10 ** Decimals)
    } catch(e) {
      console.log("Error during getting unclaimed")
      console.log(e)
    }
  }

  useEffect(() => {
    if (selectedToken && selectedToken.packageName === "upgradable_nft_staking") {
      getUnclaimedReward(selectedToken)
    }
  }, [selectedToken])

  useEffect(() => {
    async function init() {
      if (account?.address) {
        getClaimEvents()
        // will return value only after createCollectionWithTokenUpgrade call
        getCollectionOwnerAddress()
      }
    }
    init()
    
  }, [account?.address])

  return (
    <>
      <Col>
        <h3 className='admin-section'>Admin section</h3>
        <Row>
          <Button
            disabled={!account?.address}
            onClick={createStaking}
            type="primary"
          >
            Init {CONFIG.coinName} Staking
          </Button>
          <Button
            disabled={!account?.address}
            onClick={createCollectionWithTokenUpgrade}
            type="primary"
            style={{ marginLeft: '1rem' }}
          >
            Create Collection With Token Upgrade
          </Button>
        </Row>
        <EventsTable data={claimEvents} title="Upgradable Token Staking" />
        <Modal
          title="Upgradable Staking Actions"
          open={!!selectedToken && selectedToken.packageName === "upgradable_nft_staking"}
          footer={null}
          onCancel={() => {
            setSelectedToken(null)
            setUnclaimedReward(0)  
          }}
        >
          <div style={{ marginTop: '3rem' }}>
            <Button
              type="primary"
              style={{ marginRight: '1rem'}}
              onClick={() => selectedToken && onStakeToken()}
              disabled={!selectedToken?.amount || !!unclaimedReward}
            >
              Stake
            </Button>
            <Button
              type="primary"
              style={{ marginRight: '1rem'}}
              onClick={() => selectedToken && onUnstakeStaking()}
              disabled={!unclaimedReward}
            >
              Unstake
            </Button>
            <Button
              type="primary"
              style={{ marginRight: '1rem'}}
              onClick={() => selectedToken && onClaimReward()}
              disabled={!unclaimedReward}
            >
              Claim
            </Button>
            <Button
              type="primary"
              onClick={() => selectedToken && onLevelUpgrade()}
              disabled={!!unclaimedReward}
            >
              Upgrade
            </Button>
          </div>
          <p style={{ marginTop: '3rem' }}>
            Unclaimed reward: <span style={{ fontWeight: 'bold', fontSize: '1.2rem' }}>{unclaimedReward}</span> {CONFIG.coinName}
          </p>
        </Modal>
      </Col>
    </>
  )
}

export default UpgradableNftStakingLayout