import React, { useState } from 'react'

import { TokenData } from '../components/NftList'

type TokenDataWithPackage = TokenData & {
  packageName?: 'upgradable_nft_staking' | 'nft_staking'
}

export interface ISelectedTokenContext {
  selectedToken: TokenDataWithPackage | null;
  setSelectedToken: (newToken: TokenDataWithPackage | null) => void;
}

const defaultToken = {
  selectedToken: null,
  setSelectedToken: () => {},
}

export const SelectedTokenContext = React.createContext<ISelectedTokenContext>(defaultToken)

export function SelectedTokenProvider({ children }: any) {
  const [selectedToken, setSelectedToken] = useState<TokenDataWithPackage | null>(null)

  return (
    <SelectedTokenContext.Provider value={{ selectedToken, setSelectedToken }}>
      {children}
    </SelectedTokenContext.Provider>
  )
}