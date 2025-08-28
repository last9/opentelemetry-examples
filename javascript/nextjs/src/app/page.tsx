'use client'

import { useState, useEffect } from 'react'
import UserForm from './components/UserForm'
import UserList from './components/UserList'

export default function Home() {
  const [users, setUsers] = useState([])
  const [error, setError] = useState(null)

  const fetchUsers = async () => {
    try {
      const response = await fetch('/api/users')
      if (!response.ok) {
        throw new Error('Failed to fetch users')
      }
      const data = await response.json()
      setUsers(data)
    } catch (error) {
      console.error('Error fetching users:', error)
      setError('Failed to fetch users')
    }
  }

  useEffect(() => {
    fetchUsers()
  }, [])

  return (
    <div className="min-h-screen bg-gray-900 py-12 px-4">
      <div className="max-w-3xl mx-auto">
        <h1 className="text-4xl font-bold text-white mb-8 text-center">
          User Management
        </h1>
        
        <UserForm onUserAdded={fetchUsers} />

        {error && (
          <div className="mb-6 p-4 bg-red-900/50 border border-red-700 rounded-md">
            <p className="text-red-200">{error}</p>
          </div>
        )}

        <UserList users={users} onUserDeleted={fetchUsers} />
      </div>
    </div>
  )
}