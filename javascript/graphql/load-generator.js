// Load generator for Apollo GraphQL API
// Calls both the books query and addBook mutation with random data
// Usage: node load-generator.js
// Env vars: GRAPHQL_URL, CONCURRENCY, REQUESTS_PER_WORKER

import fetch from 'node-fetch';

const GRAPHQL_URL = process.env.GRAPHQL_URL || 'http://localhost:4000/graphql';
const CONCURRENCY = parseInt(process.env.CONCURRENCY || '5', 10);
const REQUESTS_PER_WORKER = parseInt(process.env.REQUESTS_PER_WORKER || '20', 10);
const INFINITE = process.env.INFINITE === 'true';

const booksQuery = {
  query: `query { books { title author } }`,
};

function randomString(len = 8) {
  return Math.random().toString(36).substring(2, 2 + len);
}

function addBookMutation() {
  return {
    query: `mutation($title: String!, $author: String!) { addBook(title: $title, author: $author) { title author } }`,
    variables: {
      title: 'Book ' + randomString(),
      author: 'Author ' + randomString(),
    },
  };
}

async function callGraphQL(payload) {
  const res = await fetch(GRAPHQL_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  return res.json();
}

async function worker(workerId) {
  for (let i = 0; i < REQUESTS_PER_WORKER; i++) {
    // Alternate between query and mutation
    const isQuery = i % 2 === 0;
    const payload = isQuery ? booksQuery : addBookMutation();
    try {
      const result = await callGraphQL(payload);
      console.log(`[Worker ${workerId}] ${isQuery ? 'Query' : 'Mutation'} result:`, JSON.stringify(result));
    } catch (err) {
      console.error(`[Worker ${workerId}] Error:`, err);
    }
  }
}

async function main() {
  do {
    const workers = [];
    for (let i = 0; i < CONCURRENCY; i++) {
      workers.push(worker(i + 1));
    }
    await Promise.all(workers);
    if (!INFINITE) {
      console.log('Load generation complete.');
    }
  } while (INFINITE);
  if (INFINITE) {
    console.log('Infinite load generation stopped (process exit or signal).');
  }
}

main(); 