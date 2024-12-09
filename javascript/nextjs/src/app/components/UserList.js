'use client'

import { useState } from 'react'

export default function UserList({ users, onUserDeleted }) {
  const [deletingId, setDeletingId] = useState(null)

  const deleteUser = async (id) => {
    setDeletingId(id)
    try {
      const response = await fetch(`http://localhost:3001/api/users?id=${id}`, {
        method: 'DELETE',
      })
      if (!response.ok) throw new Error('Failed to delete user')
      onUserDeleted()
    } catch (err) {
      console.error('Failed to delete user:', err)
    } finally {
      setDeletingId(null)
    }
  }

  return (
    <div className="bg-white shadow rounded-lg overflow-hidden">
      <table className="min-w-full">
        <thead className="bg-gray-50">
          <tr>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Name</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Email</th>
            <th className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Actions</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-200">
          {users.map((user) => (
            <tr key={user.id}>
              <td className="px-6 py-4 whitespace-nowrap">{user.name}</td>
              <td className="px-6 py-4 whitespace-nowrap">{user.email}</td>
              <td className="px-6 py-4 whitespace-nowrap text-right">
                <button
                  onClick={() => deleteUser(user.id)}
                  disabled={deletingId === user.id}
                  className="text-red-600 hover:text-red-900 disabled:opacity-50"
                >
                  {deletingId === user.id ? 'Deleting...' : 'Delete'}
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}