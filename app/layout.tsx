import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'Salsa Night',
  description: 'A private campus prom partner and conversation space.',
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return <html lang="en"><body>{children}</body></html>
}
