package crossaccount

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"regexp"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials/stscreds"
	"github.com/aws/aws-sdk-go-v2/service/resourcegroupstaggingapi"
	"github.com/aws/aws-sdk-go-v2/service/sts"
)

var accountIDRegex = regexp.MustCompile(`^\d{12}$`)

// ClientFactory manages AWS Tagging API clients for multiple accounts.
// It creates the default client for the Lambda's own account and
// assumed-role clients for cross-account access.
type ClientFactory struct {
	logger           *slog.Logger
	currentAccountID string
	defaultClient    *resourcegroupstaggingapi.Client
	crossClients     map[string]*resourcegroupstaggingapi.Client
}

// NewClientFactory initializes the factory by detecting the current account
// via STS and creating clients for any configured cross-account roles.
func NewClientFactory(ctx context.Context, logger *slog.Logger, crossAccountRolesJSON string) (*ClientFactory, error) {
	cfg, err := awsconfig.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, fmt.Errorf("load AWS config: %w", err)
	}

	// Detect current account
	stsClient := sts.NewFromConfig(cfg)
	identity, err := stsClient.GetCallerIdentity(ctx, &sts.GetCallerIdentityInput{})
	if err != nil {
		return nil, fmt.Errorf("get caller identity: %w", err)
	}

	factory := &ClientFactory{
		logger:           logger,
		currentAccountID: aws.ToString(identity.Account),
		defaultClient:    resourcegroupstaggingapi.NewFromConfig(cfg),
		crossClients:     make(map[string]*resourcegroupstaggingapi.Client),
	}

	logger.Info("current account detected", "accountID", factory.currentAccountID)

	// Parse and create cross-account clients
	if crossAccountRolesJSON != "" {
		roles, err := ParseCrossAccountRoles(crossAccountRolesJSON, logger)
		if err != nil {
			return nil, fmt.Errorf("parse cross-account roles: %w", err)
		}

		for accountID, roleARN := range roles {
			crossCfg, err := awsconfig.LoadDefaultConfig(ctx,
				awsconfig.WithCredentialsProvider(
					stscreds.NewAssumeRoleProvider(stsClient, roleARN),
				),
			)
			if err != nil {
				logger.Error("failed to create cross-account config", "accountID", accountID, "error", err)
				continue
			}

			factory.crossClients[accountID] = resourcegroupstaggingapi.NewFromConfig(crossCfg)
			logger.Info("cross-account client initialized", "accountID", accountID, "roleARN", roleARN)
		}
	}

	return factory, nil
}

// TaggingClient abstracts the AWS Resource Groups Tagging API.
type TaggingClient interface {
	GetResources(ctx context.Context, params *resourcegroupstaggingapi.GetResourcesInput, optFns ...func(*resourcegroupstaggingapi.Options)) (*resourcegroupstaggingapi.GetResourcesOutput, error)
}

// GetClient returns the appropriate Tagging API client for the given account.
// Returns the default client for the Lambda's own account or empty accountID,
// the cross-account client if configured, or the default as fallback.
func (f *ClientFactory) GetClient(accountID string) TaggingClient {
	if accountID == "" || accountID == f.currentAccountID {
		return f.defaultClient
	}

	if client, ok := f.crossClients[accountID]; ok {
		f.logger.Debug("using cross-account client", "accountID", accountID)
		return client
	}

	f.logger.Warn("no cross-account role configured, using default", "accountID", accountID)
	return f.defaultClient
}

// CurrentAccountID returns the AWS account ID of the Lambda's execution environment.
func (f *ClientFactory) CurrentAccountID() string {
	return f.currentAccountID
}

// ParseCrossAccountRoles parses and validates the CROSS_ACCOUNT_ROLES JSON.
// Expected format: {"accountID": "roleARN", ...}
func ParseCrossAccountRoles(raw string, logger *slog.Logger) (map[string]string, error) {
	var parsed map[string]string
	if err := json.Unmarshal([]byte(raw), &parsed); err != nil {
		return nil, fmt.Errorf("invalid JSON: %w", err)
	}

	validated := make(map[string]string, len(parsed))
	for accountID, roleARN := range parsed {
		if !accountIDRegex.MatchString(accountID) {
			logger.Warn("skipping invalid account ID format", "accountID", accountID)
			continue
		}
		if roleARN == "" {
			logger.Warn("skipping empty role ARN", "accountID", accountID)
			continue
		}
		validated[accountID] = roleARN
	}

	return validated, nil
}
