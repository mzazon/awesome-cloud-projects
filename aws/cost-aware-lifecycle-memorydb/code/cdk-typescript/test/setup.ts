// Global test setup for CDK tests

// Set up environment variables for testing
process.env.CDK_DEFAULT_ACCOUNT = '123456789012';
process.env.CDK_DEFAULT_REGION = 'us-east-1';

// Suppress CDK metadata for cleaner test output
process.env.CDK_DISABLE_VERSION_CHECK = '1';
process.env.CDK_DISABLE_STACK_TRACE = '1';