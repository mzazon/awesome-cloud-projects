// Global test setup file
// This file runs before each test suite

import 'aws-cdk-lib/assertions';

// Set test environment variables
process.env.CDK_DEFAULT_ACCOUNT = '123456789012';
process.env.CDK_DEFAULT_REGION = 'us-east-1';

// Suppress CDK metadata and analytics for tests
process.env.CDK_DISABLE_STACK_TRACE = '1';
process.env.CDK_DISABLE_VERSION_REPORTING = '1';