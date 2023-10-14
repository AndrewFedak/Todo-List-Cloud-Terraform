import Head from 'next/head'
import Image from 'next/image'
import { Inter } from 'next/font/google'
import styles from '@/styles/Home.module.css'

const inter = Inter({ subsets: ['latin'] })

export default function Home({ data }: { data: string }) {
  return (
    <div>I am from server data: {data}</div>
  )
}

export async function getServerSideProps() {
  return {
    props: {
      data: 'Yep, I am from server'
    }
  }
}

