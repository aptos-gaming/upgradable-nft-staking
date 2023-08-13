import React, { useEffect, useState } from 'react'
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { Col } from 'antd' 
import { gql, useQuery as useGraphqlQuery } from '@apollo/client'
import { Network, Provider } from "aptos";

import useCollectionOwner from '../context/useCollectionOwner';
import useSelectedToken from '../context/useSelectedToken'
import CONFIG from '../config.json'

export type TokenData = {
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
}

interface RowItemProps {
  rowData: TokenData;
  packageName: string;
  setSelectedToken: (data: any) => void;
}

const provider = new Provider(CONFIG.network === "devnet" ? Network.DEVNET : Network.TESTNET);

export const AccountTokensWithDataQuery = gql
  `query AccountTokensWithDataQuery($owner_address: String, $collection_name: String) {
    current_token_ownerships_aggregate(
      where: {owner_address: {_eq: $owner_address}, collection_name: {_eq: $collection_name}}
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
interface NftListProps {
  packageName: 'upgradable_token_v1_staking' | 'token_v1_staking'
}

export const NftList = ({ packageName }: NftListProps) => {
  const [tokens, setTokens] = useState<TokenData[]>([])
  const { connected, account } = useWallet()
  const { setSelectedToken } = useSelectedToken()
  const { collectionOwnerAddress } = useCollectionOwner()

  const { loading, data } = useGraphqlQuery(AccountTokensWithDataQuery, {
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
  async function getValidTokensList() {
    const validTokens: TokenData[] = []
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

  useEffect(() => {
    if (data?.current_token_ownerships_aggregate) {
      getValidTokensList()
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
            src={rowData.current_token_data.metadata_uri}
            alt='Nft'
          />
        </div>
        <div className='itemDetails'>
          <span className='planet-level'>⭐ {rowData.current_token_data.default_properties.level}</span>
          <span>Name: {rowData.name}</span>
          <span>Resources: Minerals</span>
          <span>Status: {String(rowData.amount) === '0' ? <span className='planet-farming'>Farming</span> : <span className='planet-available'>Available</span>}</span>
        </div>
      </div>
    );
  };
  
  return (
    <Col>
      <div>
        {/* <h3 className="section-title">{`Your ${CONFIG.collectionName} nfts:`}</h3> */}
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
