package crossaccount

import (
	"log/slog"
	"os"
	"testing"
)

func testLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelError}))
}

func TestParseCrossAccountRoles_Valid(t *testing.T) {
	input := `{"123456789012": "arn:aws:iam::123456789012:role/Last9MetricEnrichment", "987654321098": "arn:aws:iam::987654321098:role/Last9Reader"}`

	roles, err := ParseCrossAccountRoles(input, testLogger())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(roles) != 2 {
		t.Fatalf("expected 2 roles, got %d", len(roles))
	}
	if roles["123456789012"] != "arn:aws:iam::123456789012:role/Last9MetricEnrichment" {
		t.Errorf("unexpected role ARN for 123456789012")
	}
}

func TestParseCrossAccountRoles_EmptyJSON(t *testing.T) {
	roles, err := ParseCrossAccountRoles("{}", testLogger())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(roles) != 0 {
		t.Errorf("expected 0 roles, got %d", len(roles))
	}
}

func TestParseCrossAccountRoles_InvalidJSON(t *testing.T) {
	_, err := ParseCrossAccountRoles("not json", testLogger())
	if err == nil {
		t.Fatal("expected error for invalid JSON")
	}
}

func TestParseCrossAccountRoles_InvalidAccountID(t *testing.T) {
	input := `{"short": "arn:aws:iam::short:role/Test", "123456789012": "arn:aws:iam::123456789012:role/Valid"}`

	roles, err := ParseCrossAccountRoles(input, testLogger())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(roles) != 1 {
		t.Fatalf("expected 1 valid role (invalid account skipped), got %d", len(roles))
	}
	if _, ok := roles["123456789012"]; !ok {
		t.Error("valid account ID missing from result")
	}
}

func TestParseCrossAccountRoles_EmptyRoleARN(t *testing.T) {
	input := `{"123456789012": ""}`

	roles, err := ParseCrossAccountRoles(input, testLogger())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(roles) != 0 {
		t.Errorf("expected 0 roles (empty ARN skipped), got %d", len(roles))
	}
}
