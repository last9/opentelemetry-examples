'use client'

import { useState } from 'react'

interface UserFormProps {
  onUserAdded: () => void
}

export default function UserForm({ onUserAdded }: UserFormProps) {
  const [newUser, setNewUser] = useState({ name: '', email: '' })
  const [loading, setLoading] = useState(false)

  const addUser = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    try {
      const response = await fetch('/api/users', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(newUser),
      })
      if (!response.ok) throw new Error('Failed to add user')
      setNewUser({ name: '', email: '' })
      onUserAdded()
    } catch (err) {
      console.error('Failed to add user:', err)
    } finally {
      setLoading(false)
    }
  }

  return (
    <form onSubmit={addUser} className="mb-8">
      <div className="flex flex-col md:flex-row gap-4 mb-4">
        <input
          type="text"
          placeholder="Name"
          value={newUser.name}
          onChange={(e) => setNewUser({ ...newUser, name: e.target.value })}
          className={`flex-1 p-3 rounded-md border border-gray-600 bg-gray-800 placeholder-gray-400 ${
            newUser.name.length > 0 ? 'text-blue-500' : 'text-red-500'
          }`}
          required
        />
        <input
          type="email"
          placeholder="Email"
          value={newUser.email}
          onChange={(e) => setNewUser({ ...newUser, email: e.target.value })}
          className={`flex-1 p-3 rounded-md border border-gray-600 bg-gray-800 placeholder-gray-400 ${
            newUser.name.length > 0 ? 'text-blue-500' : 'text-red-500'
          }`}
          required
        />
        <button
          type="submit"
          disabled={loading}
          className="px-6 py-3 bg-blue-600 text-white font-medium rounded-md hover:bg-blue-700 disabled:opacity-50 transition-colors"
        >
          {loading ? 'Adding...' : 'Add User'}
        </button>
      </div>
    </form>
  )
}