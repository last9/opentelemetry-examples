'use client'

import { useState } from 'react'

export default function UserForm({ onUserAdded }) {
  const [newUser, setNewUser] = useState({ name: '', email: '' })
  const [loading, setLoading] = useState(false)

  const addUser = async (e) => {
    e.preventDefault()
    setLoading(true)
    try {
      const response = await fetch('http://localhost:3001/api/users', {
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
      <div className="flex gap-4 mb-4">
        <input
          type="text"
          placeholder="Name"
          value={newUser.name}
          onChange={(e) => setNewUser({ ...newUser, name: e.target.value })}
          className="flex-1 p-2 border rounded text-red-500"
          required
        />
        <input
          type="email"
          placeholder="Email"
          value={newUser.email}
          onChange={(e) => setNewUser({ ...newUser, email: e.target.value })}
          className="flex-1 p-2 border rounded text-red-500"
          required
        />
        <button
          type="submit"
          disabled={loading}
          className="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600 disabled:opacity-50"
        >
          {loading ? 'Adding...' : 'Add User'}
        </button>
      </div>
    </form>
  )
}