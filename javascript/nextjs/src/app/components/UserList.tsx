'use client'

import { useState } from 'react'

interface User {
  id: string
  name: string
  email: string
}

interface UserListProps {
  users: User[]
  onUserDeleted: () => void
}

export default function UserList({ users, onUserDeleted }: UserListProps) {
  const [deletingId, setDeletingId] = useState<string | null>(null)

  const deleteUser = async (id: string) => {
    setDeletingId(id)
    try {
      const response = await fetch(`/api/users?id=${id}`, {
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
    <div className="bg-gray-800 rounded-lg overflow-hidden border border-gray-700">
      <div className="overflow-x-auto">
        <table className="min-w-full divide-y divide-gray-700">
          <thead>
            <tr className="bg-gray-900">
              <th className="px-6 py-4 text-left text-sm font-medium text-gray-300 uppercase tracking-wider">
                Name
              </th>
              <th className="px-6 py-4 text-left text-sm font-medium text-gray-300 uppercase tracking-wider">
                Email
              </th>
              <th className="px-6 py-4 text-right text-sm font-medium text-gray-300 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-700">
            {users.length === 0 ? (
              <tr>
                <td colSpan={3} className="px-6 py-8 text-center text-gray-400 text-sm">
                  No users found. Add one above to get started.
                </td>
              </tr>
            ) : (
              users.map((user) => (
                <tr key={user.id} className="hover:bg-gray-750">
                  <td className="px-6 py-4 text-sm text-white">
                    {user.name}
                  </td>
                  <td className="px-6 py-4 text-sm text-white">
                    {user.email}
                  </td>
                  <td className="px-6 py-4 text-right">
                    <button
                      onClick={() => deleteUser(user.id)}
                      disabled={deletingId === user.id}
                      className="text-sm font-medium text-red-400 hover:text-red-300 disabled:opacity-50 transition-colors"
                    >
                      {deletingId === user.id ? 'Deleting...' : 'Delete'}
                    </button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  )
}