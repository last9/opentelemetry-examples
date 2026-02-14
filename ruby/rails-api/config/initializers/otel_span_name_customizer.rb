# frozen_string_literal: true

# Optional: customize generated span names.
#
# Context keys:
# - source: "active_record_query_name_normalization" | "sql_span_name_enrichment"
# - model: ActiveRecord model name when available
# - method: ActiveRecord method when available
# - db_system: db.system for SQL client spans (when available)
#
# Example output for SQL client spans:
#   "SELECT postgresql [Transaction.query]"
#
# Uncomment to enable custom naming:
# Rails.application.config.x.otel_span_name_customizer = lambda do |default_name:, span:, parent_span:, context:|
#   if context[:source] == 'sql_span_name_enrichment' && context[:model] && context[:method]
#     "#{default_name} [#{context[:model]}.#{context[:method]}]"
#   else
#     default_name
#   end
# end
