import './instrumentation.js';
import express from 'express';
import { ApolloServer } from 'apollo-server-express';
import { typeDefs, resolvers } from './schema.js';
import bodyParser from 'body-parser';
import { context, trace } from '@opentelemetry/api';

const app = express();
app.use(bodyParser.json());

const server = new ApolloServer({
  typeDefs,
  resolvers,
  // Extract error status code and message into the span.
  formatError: (err) => {
    const span = trace.getSpan(context.active());
    if (span) {
      span.setStatus({ code: 2, message: err.message }); // 2 = ERROR
      span.recordException(err);
    }
    return err;
  }
});

async function startServer() {
  await server.start();
  server.applyMiddleware({ app });

  app.listen({ port: 4000 }, () => {
    console.log(`🚀 Server ready at http://localhost:4000${server.graphqlPath}`);
  });
}

startServer();
