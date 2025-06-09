import { gql } from 'apollo-server-express';
import { PubSub } from 'apollo-server-express';

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
    books: () => {
      maybeThrowRandomError('before books logic');
      const result = books;
      maybeThrowRandomError('after books logic');
      return result;
    },
  },
  Mutation: {
    addBook: async (_, { title, author }) => {
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
      subscribe: async function* () {
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