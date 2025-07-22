import { NextResponse } from 'next/server'
import { trace } from '@opentelemetry/api'
import fs from 'fs'
import path from 'path'

const tracer = trace.getTracer('user-management-api')
const dataFile = path.join(process.cwd(), 'data', 'users.json')

// Helper function to read users
const getUsers = () => {
  return tracer.startActiveSpan('users.read', async (span) => {
    try {
      if (!fs.existsSync(path.dirname(dataFile))) {
        fs.mkdirSync(path.dirname(dataFile), { recursive: true })
        span.setAttribute('file.created_directory', true)
      }
      
      if (!fs.existsSync(dataFile)) {
        fs.writeFileSync(dataFile, JSON.stringify([]), 'utf8')
        console.log('Created new users.json file')
        span.setAttribute('file.created', true)
        return []
      }
      
      const data = fs.readFileSync(dataFile, 'utf8')
      const users = JSON.parse(data)
      span.setAttribute('users.count', users.length)
      span.setStatus({ code: 0 }) // Success
      return users
    } catch (err) {
      console.error('Error reading users file:', err)
      span.setAttribute('error', true)
      span.setAttribute('error.message', err.message)
      span.setStatus({ code: 1, message: err.message })
      return []
    } finally {
      span.end()
    }
  })
}

// Helper function to save users
const saveUsers = (users) => {
  return tracer.startActiveSpan('users.save', async (span) => {
    try {
      fs.writeFileSync(dataFile, JSON.stringify(users, null, 2))
      console.log('Successfully saved users')
      span.setAttribute('users.count', users.length)
      span.setStatus({ code: 0 })
      return true
    } catch (err) {
      console.error('Error saving users:', err)
      span.setAttribute('error', true)
      span.setAttribute('error.message', err.message)
      span.setStatus({ code: 1, message: err.message })
      return false
    } finally {
      span.end()
    }
  })
}

// GET handler
export async function GET() {
  return tracer.startActiveSpan('users.list', async (span) => {
    try {
      const users = await getUsers()
      span.setAttribute('users.count', users.length)
      span.setStatus({ code: 0 })
      console.log('Retrieved users:', users)
      return NextResponse.json(users)
    } catch (err) {
      console.error('Error in GET handler:', err)
      span.setAttribute('error', true)
      span.setAttribute('error.message', err.message)
      span.setStatus({ code: 1, message: err.message })
      return NextResponse.json(
        { error: 'Failed to fetch users' },
        { status: 500 }
      )
    } finally {
      span.end()
    }
  })
}

// POST handler
export async function POST(request) {
  return tracer.startActiveSpan('users.create', async (span) => {
    try {
      const users = await getUsers()
      const data = await request.json()
      const newUser = {
        id: Date.now().toString(),
        ...data
      }
      users.push(newUser)
      
      span.setAttribute('user.id', newUser.id)
      span.setAttribute('user.email', newUser.email)
      
      if (await saveUsers(users)) {
        span.setStatus({ code: 0 })
        return NextResponse.json(newUser, { status: 201 })
      } else {
        throw new Error('Failed to save user')
      }
    } catch (err) {
      console.error('Error in POST handler:', err)
      span.setAttribute('error', true)
      span.setAttribute('error.message', err.message)
      span.setStatus({ code: 1, message: err.message })
      return NextResponse.json(
        { error: 'Failed to add user' },
        { status: 500 }
      )
    } finally {
      span.end()
    }
  })
}

// DELETE handler
export async function DELETE(request) {
  return tracer.startActiveSpan('users.delete', async (span) => {
    try {
      const { searchParams } = new URL(request.url)
      const id = searchParams.get('id')
      span.setAttribute('user.id', id)
      
      let users = await getUsers()
      const initialCount = users.length
      users = users.filter(user => user.id !== id)
      
      span.setAttribute('users.deleted_count', initialCount - users.length)
      
      if (await saveUsers(users)) {
        span.setStatus({ code: 0 })
        return NextResponse.json({ message: 'User deleted' })
      } else {
        throw new Error('Failed to save after deletion')
      }
    } catch (err) {
      console.error('Error in DELETE handler:', err)
      span.setAttribute('error', true)
      span.setAttribute('error.message', err.message)
      span.setStatus({ code: 1, message: err.message })
      return NextResponse.json(
        { error: 'Failed to delete user' },
        { status: 500 }
      )
    } finally {
      span.end()
    }
  })
}