import './instrumentation.js';
import express from 'express';
import { ApolloServer } from 'apollo-server-express';
import { typeDefs, resolvers } from './schema.js';
import bodyParser from 'body-parser';
import { context, trace } from '@opentelemetry/api';

const app = express();
app.use(bodyParser.json());

// No Express middleware for OpenTelemetry span enrichment here

const server = new ApolloServer({
  typeDefs,
  resolvers,
  context: ({ req }) => {
    const opName = req.body?.operationName;
    const span = trace.getSpan(context.active());
    if (span && opName) {
      span.setAttribute('graphql.operation.name', opName);
      span.updateName(`POST /graphql (${opName})`); // Optionally update the span name
    }
    return {};
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
