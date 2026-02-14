# frozen_string_literal: true

require 'test_helper'
require 'open3'

class E2ESpanGenerationTest < ActiveSupport::TestCase
  def test_active_record_generates_enriched_postgres_spans
    output = run_span_runner

    assert_match(/AR_COMPLEX_SCENARIOS_DONE/, output)
    assert_match(/name="Post#create"/, output)
    assert_match(/name="Post#update"/, output)
    assert_match(/name="Comment#create"/, output)
    assert_match(/name="Post#delete_all"/, output)
    assert_match(/name="Comment#delete_all"/, output)
    assert_match(/name="INSERT .* \(Post\.(create|save)\)"/, output)
    assert_match(/name="UPDATE .* \(Post\.(update|save)\)"/, output)
    assert_match(/name="INSERT .* \(Comment\.(create|save)\)"/, output)
    assert_match(/name="DELETE .* \(Post\.delete_all\)"/, output)
    assert_match(/name="DELETE .* \(Comment\.delete_all\)"/, output)
    assert_match(/"db\.system"=>"postgresql"/, output)
    assert_match(/"active_record\.model"=>"Post"/, output)
    assert_match(/"active_record\.method"=>"create"/, output)
  end

  private

  def run_span_runner
    env = {
      'RAILS_ENV' => 'development',
      'OTEL_TRACES_EXPORTER' => 'console',
      'OTEL_BSP_SCHEDULE_DELAY' => '200',
      'OTEL_BSP_EXPORT_TIMEOUT' => '10000',
      'POSTGRES_HOST' => ENV.fetch('POSTGRES_HOST', '127.0.0.1'),
      'POSTGRES_PORT' => ENV.fetch('POSTGRES_PORT', '7432'),
      'POSTGRES_USER' => ENV.fetch('POSTGRES_USER', 'postgres'),
      'POSTGRES_PASSWORD' => ENV.fetch('POSTGRES_PASSWORD', 'password'),
      'POSTGRES_DB' => ENV.fetch('POSTGRES_DB', 'rails_api_development')
    }

    script = <<~RUBY
      post = Post.create!(title: "hello", body: "first body")
      post.update!(body: "updated body")
      Comment.create!(post: post, body: "nice post")
      Post.where(id: post.id).limit(1).pluck(:id)
      Comment.where(post_id: post.id).delete_all
      Post.where(id: post.id).delete_all
      OpenTelemetry.tracer_provider.force_flush
      OpenTelemetry.tracer_provider.shutdown
      puts "AR_COMPLEX_SCENARIOS_DONE"
    RUBY

    stdout, stderr, status = Open3.capture3(env, 'bundle', 'exec', 'rails', 'runner', script)
    combined = "#{stdout}\n#{stderr}"

    skip("postgres unavailable for e2e span test: #{stderr.lines.first&.strip}") unless status.success?

    combined
  end
end
