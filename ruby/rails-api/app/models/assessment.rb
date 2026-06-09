# Abstract-base-class STI pattern exercised by the inherited_scopes demo endpoint.
#
# `Assessment` is a concrete STI base: its `default_scope` calls the abstract class
# method `category`, which each subclass implements. Querying a subclass through an
# inherited named scope (`unresolved`/`critical`) must run the scope body with
# `self` = the subclass, so `default_scope` resolves `category` on the subclass and
# scope tracking still tags the resulting DB span.
#
# NOTE: the inherited *named scope* is what carries the scope-tracking enrichment —
# a bare `SecurityAssessment.where(...)` builds directly on the subclass and is not
# scope-tagged. Always query via `.unresolved`/`.critical`. Querying the base
# `Assessment` directly raises by design (abstract `category`).
class Assessment < ApplicationRecord
  default_scope { where(kind: category) }

  scope :unresolved, -> { where(resolved_at: nil) }
  scope :critical,   -> { where(state: %w[blocked suspended]) }

  def self.category
    raise NotImplementedError, 'Subclasses must implement the category method'
  end
end
