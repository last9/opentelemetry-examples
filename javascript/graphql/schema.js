import { gql } from 'apollo-server-express';
import pkg from 'apollo-server-express';
import { context as otContext, trace } from '@opentelemetry/api';
import { PubSub } from 'graphql-subscriptions';
const { PubSub: ApolloPubSub } = pkg;

export const typeDefs = gql`
  type Book {
    title: String
    author: String
  }

  type Query {
    books: [Book]
  }

  type Mutation {
    addBook(title: String!, author: String!): Book
  }

  type Subscription {
    bookAdded: Book
  }
`;

const books = [
  { title: 'The Awakening', author: 'Kate Chopin' },
  { title: 'City of Glass', author: 'Paul Auster' },
];

function maybeThrowRandomError(stage = '') {
  if (Math.random() < 0.2) {
    throw new Error(`Random error at stage: ${stage}`);
  }
}

const pubsub = new PubSub();
const BOOK_ADDED = 'BOOK_ADDED';

export const resolvers = {
  Query: {
    books: (parent, args, ctx) => {
      const span = trace.getSpan(otContext.active());
      if (span) {
        span.setAttribute('graphql.operation.type', ctx.operationType);
        span.setAttribute('graphql.operation.name', ctx.operationName);
      }
      maybeThrowRandomError('before books logic');
      const result = books;
      maybeThrowRandomError('after books logic');
      return result;
    },
  },
  Mutation: {
    addBook: async (parent, { title, author }, ctx) => {
      const span = trace.getSpan(otContext.active());
      if (span) {
        span.setAttribute('graphql.operation.type', ctx.operationType);
        span.setAttribute('graphql.operation.name', ctx.operationName);
      }
      maybeThrowRandomError('before addBook logic');
      const book = { title, author };
      books.push(book);
      maybeThrowRandomError('after addBook logic');
      await pubsub.publish(BOOK_ADDED, { bookAdded: book });
      return book;
    },
  },
  Subscription: {
    bookAdded: {
      subscribe: async function* (parent, args, ctx) {
        const span = trace.getSpan(otContext.active());
        if (span) {
          span.setAttribute('graphql.operation.type', ctx.operationType);
          span.setAttribute('graphql.operation.name', ctx.operationName);
        }
        maybeThrowRandomError('before subscribe');
        const asyncIterator = pubsub.asyncIterator(BOOK_ADDED);
        maybeThrowRandomError('after subscribe');
        for await (const value of asyncIterator) {
          maybeThrowRandomError('during subscription');
          yield value;
        }
      },
    },
  },
}; 