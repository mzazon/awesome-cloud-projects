// Jest setup file for CDK testing
// This file runs before each test file

// Set test environment variables
process.env.AWS_REGION = 'us-east-1';
process.env.CDK_DEFAULT_ACCOUNT = '123456789012';
process.env.CDK_DEFAULT_REGION = 'us-east-1';

// Mock AWS SDK to avoid actual AWS calls during testing
jest.mock('@aws-sdk/client-dsql');
jest.mock('@aws-sdk/client-eventbridge');

// Increase default timeout for CDK tests
jest.setTimeout(30000);