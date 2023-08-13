import React, { useState } from 'react'

type TokenDataWithPackage = any & {
  packageName?: 'upgradable_token_v1_staking' | 'token_v1_staking'
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