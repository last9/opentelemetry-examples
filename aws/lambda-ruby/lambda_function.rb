# frozen_string_literal: true

$stdout.sync = true

require 'aws-sdk-s3'
require 'json'
require 'logger'
require_relative './setup_otel'

LOGGER = Logger.new($stdout)

# rubocop:disable Lint/UnusedMethodArgument
def lambda_handler(event:, context:)
  LOGGER.info("Processing event: #{event.inspect}")

  OTEL_TRACER.in_span('process_event', attributes: { 'event.keys' => event.keys.join(',') }) do |span|
    result = process(event, span)
    span.set_attribute('result.status', 'ok')
    result
  rescue StandardError => e
    span.record_exception(e)
    span.status = OpenTelemetry::Trace::Status.error(e.message)
    raise
  end
ensure
  # Critical: flush buffered spans before Lambda process freezes.
  OpenTelemetry.tracer_provider.force_flush
end
# rubocop:enable Lint/UnusedMethodArgument

def process(event, span)
  bucket = event['bucket']
  key    = event['key']

  if bucket && key
    span.set_attribute('s3.bucket', bucket)
    span.set_attribute('s3.key', key)

    # AwsSdk instrumentation auto-creates a child span for this call.
    s3 = Aws::S3::Client.new
    response = s3.get_object(bucket: bucket, key: key)
    body = response.body.read

    LOGGER.info("Fetched #{body.bytesize} bytes from s3://#{bucket}/#{key}")
    { status: 'ok', bytes: body.bytesize }
  else
    { status: 'ok', message: 'hello from ruby lambda' }
  end
end
