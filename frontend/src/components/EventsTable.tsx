import React from 'react'
import { Table } from 'antd'

const Decimals = 8

const columns = [
  {
    title: 'Time',
    dataIndex: 'timestamp',
    key: 'timestamp',
    render: (time: any) => <p>{new Date(time * 1000).toISOString().split('T')[0]}</p>,
  },
  {
    title: 'Amount',
    dataIndex: 'coin_amount',
    key: 'coin_amount',
    render: (amount: any) => <p>{Number(amount) / 10 ** Decimals} Minerals</p>
  },
  {
    title: 'Level',
    dataIndex: 'token_level',
    key: 'token_level',
  },
  {
    title: 'Token Name',
    dataIndex: 'token_name',
    key: 'token_name'
  }
];

const EventsTable = ({ data, title }: any) => (
  <div>
    <h3>All 'claim' events in {title}:</h3>
    <Table dataSource={data || []} columns={columns} />;
  </div>
)

export default EventsTable