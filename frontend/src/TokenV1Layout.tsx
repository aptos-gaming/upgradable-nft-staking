import React, { useEffect, useState } from 'react'
import { Button, Row, Col, Modal } from 'antd';
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { AptosClient, Provider, Network } from "aptos";
import { useApolloClient } from '@apollo/client';

import { AccountTokensV1WithDataQuery } from './components/TokensList'
import EventsTable from './components/EventsTable';
import useSelectedToken from './context/useSelectedToken'
import useCollectionOwner from './context/useCollectionOwner'
import CONFIG from "./config.json"

const PackageName = "token_v1_staking";

const DevnetClientUrl = "https://fullnode.devnet.aptoslabs.com/v1"
const TestnetClientUrl = "https://fullnode.testnet.aptoslabs.com"

const client = new AptosClient(CONFIG.network === "devnet" ? DevnetClientUrl : TestnetClientUrl)
const provider = new Provider(CONFIG.network === "devnet" ?  Network.DEVNET : Network.TESTNET);

const RewardCoinType = `${CONFIG.moduleAddress}::mint_coins::${CONFIG.coinName}`

const Decimals = 8

interface ClaimEvent {
  coin_amount: string,
  timestamp: string,
  token_id: {
    property_version: string,
    token_data_id: {
      collection: string,
      creator: string,
      name: string,
    }
  }
}

const TokenV1Layout = () => {
  const { account, signAndSubmitTransaction } = useWallet()
  const { selectedToken, setSelectedToken } = useSelectedToken()
  const [claimEvents, setClaimEvents] = useState<ClaimEvent[]>([])
  const [unclaimedReward, setUnclaimedReward] = useState(0)
  const apolloClient = useApolloClient()
  const { collectionOwnerAddress, setCollectionOwnerAddress } = useCollectionOwner()

  const getCollectionOwnerAddress = async () => {
    const packageName = "mint_upgrade_tokens_v1"
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

  const createStaking = async () => {
    const tokensPerHour = 10
    const amountToTreasury = 50000

    const payload = {
      type: "entry_function_payload",
      function: `${CONFIG.moduleAddress}::${PackageName}::create_staking`,
      type_arguments: [RewardCoinType],
      // collection_owner_addr, dpr, collection_name, total_amount
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
      // staking_creator_addr, collection_owner_addr, collection_name, token_name, property_version, tokens
      arguments: [CONFIG.moduleAddress, collectionOwnerAddress, CONFIG.collectionName, selectedToken?.name, selectedToken?.property_version, "1"]
    }
    try {
      const tx = await signAndSubmitTransaction(payload);
      await client.waitForTransactionWithResult(tx.hash)
      setSelectedToken(null)
      setUnclaimedReward(0)
      await apolloClient.refetchQueries({ include: [AccountTokensV1WithDataQuery]})
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
      // staking_creator_addr, collection_owner_addr, collection_name, token_name, property_version
      arguments: [CONFIG.moduleAddress, collectionOwnerAddress, CONFIG.collectionName, selectedToken?.name, selectedToken?.property_version]
    }
    try {
      const tx = await signAndSubmitTransaction(payload);
      await client.waitForTransactionWithResult(tx.hash)
      setSelectedToken(null)
      setUnclaimedReward(0)
      await apolloClient.refetchQueries({ include: [AccountTokensV1WithDataQuery]})
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
      // staking_creator_addr, collection_owner_addr, collection_name, token_name, property_version
      arguments: [CONFIG.moduleAddress, collectionOwnerAddress, selectedToken?.collection_name, selectedToken?.name, selectedToken?.property_version],
    }
    try {
      const tx = await signAndSubmitTransaction(payload);
      await client.waitForTransactionWithResult(tx.hash)
      setSelectedToken(null)
      setUnclaimedReward(0)
      getClaimEvents()
    } catch (e) {
      console.log("Error druing claim reward tx")
      console.log(e)
    }
  }

  const getClaimEvents = async () => {
    const eventStore = `${CONFIG.moduleAddress}::${PackageName}::EventsStore`

    try {
      const claimEvents = await client.getEventsByEventHandle(account?.address || '', eventStore, "claim_events")
      const formmatedClaimEvents = claimEvents.map((claimEvent) => ({
        ...claimEvent.data,
        token_name: claimEvent.data.token_id.token_data_id.name,
      }))
      setClaimEvents(formmatedClaimEvents)
    } catch (e: any) {
      const errorMessage = JSON.parse(e.message)
      if (errorMessage.error_code === "resource_not_found") {
        console.log("No claims for basic token staking")
      }
    }
  }

  const getUnclaimedReward = async (token: any) => {
    const payload = {
      function: `${CONFIG.moduleAddress}::${PackageName}::get_unclaimed_reward`,
      type_arguments: [],
      // staker_addr, staking_creator_addr, collection_name, token_name
      arguments: [account?.address, CONFIG.moduleAddress, token?.collection_name, token?.name]
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
    if (selectedToken && selectedToken.packageName === "token_v1_staking") {
      getUnclaimedReward(selectedToken)
    }
  }, [selectedToken])

  useEffect(() => {
    async function init() {
      if (account?.address) {
        getClaimEvents()
        getCollectionOwnerAddress()
      }
    }
    init()
    
  }, [account?.address])

  return (
    <Col>
      <h3 className='admin-section'>Admin section</h3>
      <Row>
        <Button disabled={!account?.address} onClick={createStaking} type="primary">Init {CONFIG.coinName} Staking</Button>
      </Row>
      <EventsTable data={claimEvents} title="Basic Token Staking" />
      <Modal
        title="Basic Staking Actions"
        open={!!selectedToken && selectedToken.packageName === "token_v1_staking"}
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
            disabled={!selectedToken?.amount}
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
            onClick={() => selectedToken && onClaimReward()}
            disabled={!unclaimedReward}
          >
            Claim
          </Button>
        </div>
        <p style={{ marginTop: '3rem' }}>
          Unclaimed reward: <span style={{ fontWeight: 'bold', fontSize: '1.2rem' }}>{unclaimedReward}</span> {CONFIG.coinName}
        </p>
      </Modal>
    </Col>
  )
}

export default TokenV1Layout