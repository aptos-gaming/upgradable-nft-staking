import { useContext } from 'react'

import { ICollectionOwnerContext, CollectionOwnerContext } from './CollectionOwnerProvider'

const useCollectionOwner = () => useContext<ICollectionOwnerContext>(CollectionOwnerContext)

export default useCollectionOwner