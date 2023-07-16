import React from 'react'
import { gql, useQuery as useGraphqlQuery } from '@apollo/client'
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { Col } from "antd";

import CONFIG from '../config.json'

const Decimals = 8

const CoinBalances = gql
  `query CoinBalance($owner_address: String, $coin_name: String) {
    current_coin_balances(
      where: {owner_address: {_eq: $owner_address}, coin_type: {_regex: $coin_name}}
    ) {
      amount
      coin_type
    }
  }
`

const CoinBalance = () => {
  const { connected, account } = useWallet()

  const { data } = useGraphqlQuery(CoinBalances, {
    variables: {
      owner_address: account?.address,
      coin_name: CONFIG.coinName,
    },
    skip: !connected || !account?.address,
  })

  return (
    <Col>
      <p style={{ fontSize: '1.5rem' }}>
        <span className='balance-container'>
          <span style={{ fontWeight: 'bold'}}>
            {data?.current_coin_balances.length ? (data.current_coin_balances[0].amount / 10 ** Decimals).toFixed(2) : 0}
          </span> {CONFIG.coinName}
        </span>
        {/* Placeholders for more resources */}
        <span className='balance-container'>
          <span style={{ fontWeight: 'bold'}}>
            0
          </span> Food
        </span>
        <span className='balance-container'>
          <span style={{ fontWeight: 'bold'}}>
            0
          </span> Fuel
        </span>
      </p>
    </Col>
  )
}

export default CoinBalance