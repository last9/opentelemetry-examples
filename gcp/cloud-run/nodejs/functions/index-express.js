/**
 * Cloud Run Function using Express Router
 * Routes are auto-detected by OTel Express instrumentation
 */
'use strict';

const functions = require('@google-cloud/functions-framework');
const express = require('express');

const app = express();
app.use(express.json());

// Mock data
const USERS = [
  { id: 1, name: 'Alice Johnson', email: 'alice@example.com' },
  { id: 2, name: 'Bob Smith', email: 'bob@example.com' },
  { id: 3, name: 'Charlie Brown', email: 'charlie@example.com' },
];

const ORDERS = [
  { id: 101, userId: 1, total: 99.99, status: 'completed' },
  { id: 102, userId: 2, total: 149.50, status: 'pending' },
];

// Routes - OTel Express instrumentation will auto-detect these patterns
app.get('/', (req, res) => {
  res.json({ service: 'Express API on Cloud Run Functions', version: '1.0.0' });
});

app.get('/users', (req, res) => {
  res.json({ users: USERS });
});

app.get('/users/:id', (req, res) => {
  const user = USERS.find(u => u.id === parseInt(req.params.id));
  if (!user) return res.status(404).json({ error: 'User not found' });
  res.json({ user });
});

app.get('/users/:id/orders', (req, res) => {
  const userId = parseInt(req.params.id);
  const user = USERS.find(u => u.id === userId);
  if (!user) return res.status(404).json({ error: 'User not found' });
  const userOrders = ORDERS.filter(o => o.userId === userId);
  res.json({ user: { id: user.id, name: user.name }, orders: userOrders });
});

app.get('/orders/:id', (req, res) => {
  const order = ORDERS.find(o => o.id === parseInt(req.params.id));
  if (!order) return res.status(404).json({ error: 'Order not found' });
  res.json({ order });
});

// Register Express app as the function handler
functions.http('expressApi', app);
