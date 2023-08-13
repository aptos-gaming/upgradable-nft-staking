import React, { useEffect, useState } from 'react'
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { Col } from 'antd' 
import { gql, useQuery as useGraphqlQuery } from '@apollo/client'
import { Network, Provider } from "aptos";

import useCollectionOwner from '../context/useCollectionOwner';
import useSelectedToken from '../context/useSelectedToken'
import CONFIG from '../config.json'

export type TokenV1Props = {
  amount: number,
  collection_name: string,
  name: string,
  token_data_id_hash: string,
  property_version: number,
  current_token_data: {
    metadata_uri: string,
    default_properties: {
      level: string
    }
  }
  storage_id: string,
}

export type TokenV2Props = {
  amount: number,
  current_token_data: {
    token_name: string,
    token_uri: string,
    token_properties: {
      level: string
    },
  },
  storage_id: string,
}

interface RowItemProps {
  rowData: any;
  packageName: string;
  setSelectedToken: (data: any) => void;
}

const provider = new Provider(CONFIG.network === "devnet" ? Network.DEVNET : Network.TESTNET);

export const AccountTokensV2WithDataQuery = gql
  `query AccountTokensV2WithDataQuery($owner_address: String) {
    current_token_ownerships_v2_aggregate(
      where: {owner_address: {_eq: $owner_address }, current_token_data: {token_properties: {_has_key: "level"}}},
    ) {
      aggregate {
        count
      }
      nodes {
        is_soulbound_v2
        storage_id
        amount
        current_token_data {
          token_properties
          token_name
          token_uri
        }
      }
    }
  }
`

export const AccountTokensV1WithDataQuery = gql
  `query AccountTokensV1WithDataQuery($owner_address: String, $collection_name: String) {
    current_token_ownerships_aggregate(
      where: {owner_address: {_eq: $owner_address }, collection_name: {_eq: $collection_name }}
    ) {
      aggregate {
        count(columns: amount)
      }
      nodes {
        name
        owner_address
        collection_name
        property_version
        current_token_data {
          metadata_uri
          default_properties
        }
        amount
        token_data_id_hash
      }
    }
  }
`

interface TokensListProps {
  packageName: 'upgradable_token_v1_staking' | 'token_v1_staking'
}

export const TokensList = ({ packageName }: TokensListProps) => {
  const [tokens, setTokens] = useState<TokenV1Props[]>([])
  const { connected, account } = useWallet()
  const { setSelectedToken } = useSelectedToken()
  const { collectionOwnerAddress } = useCollectionOwner()

  const { loading, data } = useGraphqlQuery(CONFIG.tokenVersion === 2 ? AccountTokensV2WithDataQuery : AccountTokensV1WithDataQuery, {
    variables: {
      owner_address: account?.address,
      collection_name: CONFIG.collectionName,
    },
    skip: !connected || !account?.address,
  })

  const getStakedTokenIds = async (): Promise<Array<any>> => {
    const payload = {
      function: `${CONFIG.moduleAddress}::${packageName}::get_tokens_staking_statuses`,
      type_arguments: [],
      arguments: [account?.address]
    }

    try {
      const response = await provider.view(payload)
      return response[0] as Array<any>
    } catch(e) {
      console.log(e)
      console.log("Error during getting staked token ids")
    }
    return []
  }  

  // check all staking tokens and merge them in tokens list to display
  const getValidV1TokensList = async () => {
    const validTokens: TokenV1Props[] = []
    const allTokens = data?.current_token_ownerships_aggregate.nodes
    const allCurrentStakedTokens: Array<any> = await getStakedTokenIds()

    // check if token in allTokens that have amount = 0 exists in allCurrentStakedTokens
    // if yes -> push to validTokens
    for (const tokenData of allTokens) {
      if (!tokenData.amount) {
        const customTokenIdHash = JSON.stringify({ collection: CONFIG.collectionName, creator: collectionOwnerAddress, name: tokenData.name })
    
        allCurrentStakedTokens.forEach((stakedTokenData) => {
          const stakedTokenIdHash = JSON.stringify(stakedTokenData.token_data_id);
          
          if (customTokenIdHash === stakedTokenIdHash) {
            validTokens.push(tokenData)
          }
        })
      } else {
        validTokens.push(tokenData)
      }
    }
    setTokens(validTokens)
  }

  const getValidV2TokensList = async () => {
    const allTokens = data?.current_token_ownerships_v2_aggregate.nodes
    setTokens(allTokens)
  }

  useEffect(() => {
    // for tokenV1
    if (data?.current_token_ownerships_aggregate) {
      getValidV1TokensList()
    }
    // for tokenV2
    if (data?.current_token_ownerships_v2_aggregate) {
      getValidV2TokensList()
    }
  }, [data])
  
  const RowItem: React.FC<RowItemProps> = ({ rowData, packageName, setSelectedToken }) => {
    return (
      <div
        className='gridItem'
        onClick={() => setSelectedToken({ ...rowData, packageName })}
      >
        <div className='itemImage'>
          <img
            style={{ maxWidth: '250px' }}
            src={CONFIG.tokenVersion === 2 ? rowData.current_token_data.token_uri : rowData.current_token_data.metadata_uri}
            alt='Nft'
          />
        </div>
        <div className='itemDetails'>
          <span className='planet-level'>⭐ {CONFIG.tokenVersion === 2 ? rowData.current_token_data.token_properties.level : rowData.current_token_data.default_properties.level}</span>
          <span>Name: {CONFIG.tokenVersion === 2 ? rowData.current_token_data.token_name : rowData.name}</span>
          <span>Resources: Minerals</span>
          {CONFIG.tokenVersion === 1 && (
            <span>Status: {String(rowData.amount) === '0' ? <span className='planet-farming'>Farming</span> : <span className='planet-available'>Available</span>}</span>
          )}
          {CONFIG.tokenVersion === 2 && (
            <span>Status: {rowData.is_soulbound_v2 ? <span className='planet-farming'>Farming</span> : <span className='planet-available'>Available</span>}</span>
          )}
        </div>
      </div>
    );
  };
  
  return (
    <Col>
      <div>
        {!loading && (
          <div className='gridContainer'>
            {tokens.map((rowData) => (
              <RowItem
                rowData={rowData}
                packageName={packageName}
                setSelectedToken={setSelectedToken}
              />
            ))}
          </div>
        )}
      </div>
    </Col>
  );
  
}
