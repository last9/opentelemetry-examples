import { instrument, ResolveConfigFn } from '@microlabs/otel-cf-workers';

const config: ResolveConfigFn = (env) => {
	return {
		exporter: {
			url: env.OTEL_TRACES_ENDPOINT,
			headers: {
				Authorization: env.OTEL_AUTH_HEADER,
			},
		},
		service: {
			name: 'otel-workers-itty',
		},
	};
};

export const instrumentation = (handler: ExportedHandler) => {
	return instrument(handler, config);
};
