'use client'

import { useState, useEffect } from 'react'
import UserForm from './components/UserForm'
import UserList from './components/UserList'

export default function Home() {
  const [users, setUsers] = useState([])
  const [error, setError] = useState(null)

  const fetchUsers = async () => {
    try {
      const response = await fetch('http://localhost:3001/api/users')
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
    <div className="p-8 max-w-2xl mx-auto">
      <h1 className="text-3xl font-bold mb-8">User Management</h1>
      
      <UserForm onUserAdded={fetchUsers} />

      {error && (
        <div className="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
          {error}
        </div>
      )}

      <UserList users={users} onUserDeleted={fetchUsers} />
    </div>
  )
}