import React from 'react'
import { Col } from "antd";
import { WalletSelector } from "@aptos-labs/wallet-adapter-ant-design";
import "@aptos-labs/wallet-adapter-ant-design/dist/index.css";

const WalletConnect = () => (
  <Col style={{ textAlign: "right" }}>
    <WalletSelector />
  </Col>
)

export default WalletConnect