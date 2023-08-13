import React, { useState } from 'react'
import { PetraWallet } from "petra-plugin-wallet-adapter"
import { MartianWallet } from '@martianwallet/aptos-wallet-adapter'
import { PontemWallet } from '@pontem/wallet-adapter-plugin'
import { AptosWalletAdapterProvider } from "@aptos-labs/wallet-adapter-react"
import {
  ApolloClient,
  InMemoryCache,
  ApolloProvider,
  HttpLink,
  NormalizedCacheObject,
} from "@apollo/client"
import { Tabs, TabsProps } from "antd"

import WalletConnect from './components/WalletConnect'
import TokenV1Layout from './TokenV1Layout';
import UpgradableTokenV1Layout from './UpgradableTokenV1Layout'
import CoinBalance from './components/CoinBalance'
import { SelectedTokenProvider } from './context/SelectedTokenProvider'
import { CollectionOwnerProvider } from './context/CollectionOwnerProvider'
import { TokensList } from './components/TokensList'
import CONFIG from './config.json'

const APTOS_GRAPH = `https://indexer-${CONFIG.network}.staging.gcp.aptosdev.com/v1/graphql`

function getGraphqlClient(): ApolloClient<NormalizedCacheObject> {
  return new ApolloClient({
    link: new HttpLink({
      uri: APTOS_GRAPH,
    }),
    cache: new InMemoryCache(),
  })
}

const items: TabsProps['items'] = [{
  key: '1',
  label: 'Basic Token Staking',
  children: (
    <>
      <TokensList packageName="token_v1_staking" />
      <TokenV1Layout />
    </>
  ),
}, {
  key: '2',
  label: 'Upgradable Token Staking',
  children: (
    <>
      <TokensList packageName="upgradable_token_v1_staking" />
      <UpgradableTokenV1Layout />
    </>
  ),
},
{
  key: '3',
  label: 'Marketplace (WIP)',
  children: (
    <>
    </>
  ),
}]

const App = () => {
  const [packageName, setPackageName] = useState<'upgradable_token_v1_staking' | 'token_v1_staking'>('token_v1_staking')
  const wallets = [new PetraWallet(), new MartianWallet(), new PontemWallet()];
  const graphqlClient = getGraphqlClient()

  return (
    <ApolloProvider client={graphqlClient}>
      <AptosWalletAdapterProvider plugins={wallets} autoConnect={true}>
        <WalletConnect />
        <CollectionOwnerProvider>
          <SelectedTokenProvider>
            <CoinBalance />
            <Tabs type="card" defaultActiveKey="1" items={items} onChange={(tab) => setPackageName(tab === '1' ? 'token_v1_staking' : 'upgradable_token_v1_staking')}/>
          </SelectedTokenProvider>
        </CollectionOwnerProvider>
      </AptosWalletAdapterProvider>
    </ApolloProvider>
  );
}

export default App;
