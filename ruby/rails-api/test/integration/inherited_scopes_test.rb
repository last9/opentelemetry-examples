# frozen_string_literal: true

require "test_helper"

# Verifies the inherited_scopes demo endpoint: an inherited named scope on an STI
# subclass whose abstract base default_scope calls an abstract class method.
# Guards against the receiver-binding regression where the scope body ran with
# self = the base class and raised NotImplementedError.
class InheritedScopesTest < ActionDispatch::IntegrationTest
  setup    { SPAN_EXPORTER.reset }
  teardown { SPAN_EXPORTER.reset }

  # DB spans created while a scope was active carry code.activerecord.scope.
  def scope_spans_for(model)
    SPAN_EXPORTER.finished_spans.select do |s|
      s.attributes.key?("code.activerecord.scope") &&
        s.attributes["code.activerecord.model"] == model
    end
  end

  test "inherited scope chain on an STI subclass does not raise and returns 200" do
    get "/api/v1/demo/inherited_scopes"

    assert_equal 200, response.status
  end

  test "abstract category resolves on the subclass, not the base" do
    get "/api/v1/demo/inherited_scopes"

    body = JSON.parse(response.body)
    assert_equal "security",   body["security_kind"]
    assert_equal "compliance", body["compliance_kind"]
  end

  test "unresolved scope excludes resolved rows" do
    get "/api/v1/demo/inherited_scopes"

    body = JSON.parse(response.body)
    # "unpatched CVE" is blocked + unresolved; "resolved finding" is excluded.
    assert_includes body["critical_unresolved_security"], "unpatched CVE"
    refute_includes body["critical_unresolved_security"], "resolved finding"
  end

  test "DB span is scope-tagged and resolves to the subclass model" do
    get "/api/v1/demo/inherited_scopes"

    span = scope_spans_for("SecurityAssessment").first
    assert span, "expected a scope-tagged SecurityAssessment DB span"
    assert_includes %w[unresolved critical], span.attributes["code.activerecord.scope"]
    assert_equal "SecurityAssessment", span.attributes["code.activerecord.model"]
  end

  test "second subclass also produces a scope-tagged span under its own model" do
    get "/api/v1/demo/inherited_scopes"

    span = scope_spans_for("ComplianceAssessment").first
    assert span, "expected a scope-tagged ComplianceAssessment DB span"
    assert_equal "unresolved", span.attributes["code.activerecord.scope"]
  end

  test "querying the abstract base directly raises NotImplementedError" do
    get "/api/v1/demo/inherited_scopes" # seed rows

    assert_raises(NotImplementedError) { Assessment.unresolved.to_a }
  end

  test "critical scope excludes rows whose state is not blocked or suspended" do
    get "/api/v1/demo/inherited_scopes" # seed rows

    open_unresolved = SecurityAssessment.create!(title: "open finding", state: "open")
    refute_includes SecurityAssessment.unresolved.critical.to_a, open_unresolved
  end

  test "endpoint is idempotent across repeated hits" do
    get "/api/v1/demo/inherited_scopes"
    assert_equal 200, response.status
    count = SecurityAssessment.count

    get "/api/v1/demo/inherited_scopes"
    assert_equal 200, response.status
    assert_equal count, SecurityAssessment.count, "repeated hits should not duplicate rows"
  end

  test "span_name_formatter rewrites the inherited-scope DB span to Model.scope" do
    get "/api/v1/demo/inherited_scopes"

    names = SPAN_EXPORTER.finished_spans.map(&:name)
    assert names.any? { |n| n.start_with?("SecurityAssessment.") },
           "expected a DB span renamed to SecurityAssessment.<scope>, got #{names.inspect}"
  end

  test "span_name_formatter does not rename non-DB spans" do
    get "/api/v1/demo/inherited_scopes"

    http_span = SPAN_EXPORTER.finished_spans.find { |s| s.attributes.key?("http.method") }
    assert http_span
    refute http_span.name.start_with?("SecurityAssessment", "Assessment"),
           "HTTP span should not be renamed by the DB-only formatter"
  end

  # Requires rails-otel-context 0.9.11+ (aggregate-query scope tagging).
  test "aggregate query on an inherited scope is scope-tagged" do
    get "/api/v1/demo/inherited_scopes" # seed rows + ensure gem installed
    SPAN_EXPORTER.reset

    SecurityAssessment.unresolved.count

    span = scope_spans_for("SecurityAssessment").first
    assert span, "expected a scope-tagged SecurityAssessment span for an aggregate query"
    assert_equal "unresolved", span.attributes["code.activerecord.scope"]
  end
end
