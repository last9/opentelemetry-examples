import { trace } from '@opentelemetry/api';
import { AutoRouter } from 'itty-router';
import { instrumentation } from './instrumentation';

const api = AutoRouter();

api.post('/posts', async (request) => {
	return new Response('Post created', { status: 201 });
});

api.get('/posts/:id', async (request) => {
	const postId = request.params.id;
	const span = trace.getActiveSpan();
	span?.setAttributes({ postId });

	return new Response(`Post ${postId}`, { status: 200 });
});

api.put('/posts/:id', async (request) => {
	const postId = request.params.id;
	return new Response(`Post ${postId} updated`, { status: 200 });
});

api.delete('/posts/:id', async (request) => {
	const postId = request.params.id;
	return new Response(`Post ${postId} deleted`, { status: 200 });
});

api.all('*', () => new Response('Not Found', { status: 404 }));

export default instrumentation({
	fetch: api.fetch,
} as ExportedHandler);
