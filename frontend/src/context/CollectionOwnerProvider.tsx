import React, { useState } from 'react'


export interface ICollectionOwnerContext {
  collectionOwnerAddress: string | null;
  setCollectionOwnerAddress: (newOnwer: string | null) => void;
}

const defaultOwnerAddress = {
  collectionOwnerAddress: null,
  setCollectionOwnerAddress: () => {},
}

export const CollectionOwnerContext = React.createContext<ICollectionOwnerContext>(defaultOwnerAddress)

export function CollectionOwnerProvider({ children }: any) {
  const [collectionOwnerAddress, setCollectionOwnerAddress] = useState<string | null>(null)

  return (
    <CollectionOwnerContext.Provider value={{ collectionOwnerAddress, setCollectionOwnerAddress }}>
      {children}
    </CollectionOwnerContext.Provider>
  )
}