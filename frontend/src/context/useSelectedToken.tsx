import { useContext } from 'react'

import { ISelectedTokenContext, SelectedTokenContext } from './SelectedTokenProvider'

const useSelectedToken = () => useContext<ISelectedTokenContext>(SelectedTokenContext)

export default useSelectedToken