export const metadata = {
    title: 'User Management',
    description: 'Next.js User Management System',
  }
  
  export default function RootLayout({ children }) {
    return (
      <html lang="en">
        <body>{children}</body>
      </html>
    )
  }