import React, { useEffect, useState } from 'react';
import { Col, Button, Modal } from "antd";
import { Network, Provider, AptosClient } from "aptos";
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { useApolloClient } from '@apollo/client';

import { AccountTokensV2WithDataQuery } from './components/TokensList'
import EventsTable from './components/EventsTable';
import CONFIG from "./config.json"
import useSelectedToken from './context/useSelectedToken'
import useCollectionOwner from './context/useCollectionOwner'

const PackageName = "mint_stake_upgrade_tokens_v2"

const DevnetClientUrl = "https://fullnode.devnet.aptoslabs.com/v1"
const TestnetClientUrl = "https://fullnode.testnet.aptoslabs.com"

const client = new AptosClient(CONFIG.network === "devnet" ? DevnetClientUrl : TestnetClientUrl)
const provider = new Provider(CONFIG.network === "devnet" ?  Network.DEVNET : Network.TESTNET);

const RewardCoinType = `${CONFIG.moduleAddress}::mint_coins::${CONFIG.coinName}`

const Decimals = 8

const UpgradableTokenV2Layout = () => {
  const [unclaimedReward, setUnclaimedReward] = useState(0)
  const [claimEvents, setClaimEvents] = useState<any[]>([])
  const { selectedToken, setSelectedToken } = useSelectedToken()
  const { setCollectionOwnerAddress } = useCollectionOwner()
  const apolloClient = useApolloClient()

  const [ownerAddress, setOwnerAddress] = useState('')

  const { account, signAndSubmitTransaction } = useWallet();

  useEffect(() => {
    async function init() {
      if (account?.address) {
        getClaimEvents()
        getCollectionOwnerAddress()
      }
    }
    init()
    
  }, [account?.address])

  const createCollectionWithTokenUpgrade = async () => {
    const payload = {
      type: "entry_function_payload",
      function: `${CONFIG.moduleAddress}::${PackageName}::create_collection_and_enable_token_upgrade`,
      type_arguments: [RewardCoinType],    
      arguments: [],
    }
    try {
      const tx = await signAndSubmitTransaction(payload)
      await client.waitForTransactionWithResult(tx.hash)
      await apolloClient.refetchQueries({ include: [AccountTokensV2WithDataQuery]})
    } catch (e) {
      console.log("ERROR during create_collection_and_enable_token_upgrade")
      console.log(e)
    }
  }

  const getCollectionOwnerAddress = async () => {
    const payload = {
      function: `${CONFIG.moduleAddress}::${PackageName}::get_staking_resource_address_by_collection_name`,
      type_arguments: [],
      // creator, collection_name
      arguments: [CONFIG.moduleAddress, CONFIG.collectionName]
    }

    try {
      const viewResponse = await provider.view(payload)
      setCollectionOwnerAddress(String(viewResponse[0]))
      setOwnerAddress(String(viewResponse[0]))
    } catch(e) {
      console.log("Error during getting resource account addres")
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
      // dph, collection_name, total_amount
      arguments: [tokensPerHour * (10 ** Decimals), CONFIG.collectionName, amountToTreasury * 10 ** Decimals],
    }
    try {
      const tx = await signAndSubmitTransaction(payload)
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
      // staking_creator_addr, collection_owner_addr, token_address, collection_name, token_name, tokens
      arguments: [CONFIG.moduleAddress, ownerAddress, selectedToken?.storage_id, CONFIG.collectionName, selectedToken?.current_token_data.token_name, "1"]
    }
    try {
      const tx = await signAndSubmitTransaction(payload)
      setSelectedToken(null)
      setUnclaimedReward(0)
      await client.waitForTransactionWithResult(tx.hash)
      await apolloClient.refetchQueries({ include: [AccountTokensV2WithDataQuery]})
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
      // staking_creator_addr, collection_owner_addr, token_address, collection_name, token_name,
      arguments: [CONFIG.moduleAddress, ownerAddress, selectedToken?.storage_id, CONFIG.collectionName, selectedToken?.current_token_data.token_name]
    }
    try {
      const tx = await signAndSubmitTransaction(payload)
      setSelectedToken(null)
      setUnclaimedReward(0)
      await client.waitForTransactionWithResult(tx.hash)
      await apolloClient.refetchQueries({ include: [AccountTokensV2WithDataQuery]})
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
      // staking_creator_addr, token_address, collection_name, token_name
      arguments: [CONFIG.moduleAddress, selectedToken?.storage_id, CONFIG.collectionName, selectedToken?.current_token_data.token_name],
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
    const eventStore = `${CONFIG.moduleAddress}::${PackageName}::EventsStore`

    try {
      const claimEvents = await client.getEventsByEventHandle(account?.address || '', eventStore, "claim_events")
      const formmatedClaimEvents = claimEvents.map((claimEvent) => ({
        ...claimEvent.data,
        token_name: claimEvent.data.token_name,
      }))
      setClaimEvents(formmatedClaimEvents)
    } catch (e: any) {
      const errorMessage = JSON.parse(e.message)
      if (errorMessage.error_code === "resource_not_found") {
        console.log("No claims for upgradable token staking")
      }
    }
  }

  const getUnclaimedReward = async (token: any) => {
    const payload = {
      function: `${CONFIG.moduleAddress}::${PackageName}::get_unclaimed_reward`,
      type_arguments: [],
      // staker_addr, staking_creator_addr, token_address, collection_name, token_name
      arguments: [account?.address, CONFIG.moduleAddress, selectedToken?.storage_id, CONFIG.collectionName, selectedToken?.current_token_data.token_name]
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
    if (selectedToken) {
      getUnclaimedReward(selectedToken)
    }
  }, [selectedToken])

  const onLevelUpgrade = async () => {
    const payload = {
      type: "entry_function_payload",
      function: `${CONFIG.moduleAddress}::${PackageName}::upgrade_token`,
      type_arguments: [RewardCoinType],
      // collection_owner, token address
      arguments: [ownerAddress, selectedToken?.storage_id],
    }
    try {
      const tx = await signAndSubmitTransaction(payload)
      await client.waitForTransactionWithResult(tx.hash)
      setSelectedToken(null)
      setUnclaimedReward(0)
      await apolloClient.refetchQueries({ include: [AccountTokensV2WithDataQuery]})
    } catch (e) {
      console.log("ERROR during token upgrade")
    }
  }

  return (
    <>  
      <Col>
        <h3 className='admin-section'>Admin section</h3>
        <Button
          disabled={!account?.address}
          onClick={createCollectionWithTokenUpgrade}
          type="primary"
          style={{ marginLeft: '1rem' }}
        >
          Create Collection With Token Upgrade
        </Button>
        <Button
          disabled={!account?.address}
          onClick={createStaking}
          type="primary"
          style={{ marginLeft: '1rem' }}
        >
          Init Staking
        </Button>
        <EventsTable data={claimEvents} title="Upgradable Token Staking" />
        <Modal
          title="Upgradable Staking Actions"
          open={!!selectedToken}
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
          <p className="unclaimed-reward-text">
            Unclaimed reward: <span style={{ color: 'black', fontWeight: 'bold', fontSize: '1.2rem' }}>{unclaimedReward}</span> {CONFIG.coinName}
          </p>
        </Modal>
      </Col>
    </>
  );
}

export default UpgradableTokenV2Layout;
