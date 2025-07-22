/**
 * Jest test setup file
 * 
 * This file is executed before each test suite and provides
 * common setup and utilities for all tests.
 */

import * as aws from 'aws-sdk';

// Mock AWS SDK for testing
jest.mock('aws-sdk', () => ({
  ...jest.requireActual('aws-sdk'),
  config: {
    update: jest.fn(),
  },
}));

// Set up test environment variables
process.env.AWS_REGION = 'us-east-1';
process.env.AWS_ACCOUNT_ID = '123456789012';
process.env.CDK_DEFAULT_ACCOUNT = '123456789012';
process.env.CDK_DEFAULT_REGION = 'us-east-1';

// Global test timeout
jest.setTimeout(30000);

// Global beforeEach setup
beforeEach(() => {
  // Clear all mocks before each test
  jest.clearAllMocks();
});

// Global afterEach cleanup
afterEach(() => {
  // Clean up any resources after each test
  jest.restoreAllMocks();
});

// Export common test utilities
export const testConfig = {
  appName: 'test-voting-system',
  environment: 'test',
  blockchain: {
    network: 'GOERLI',
    instanceType: 'bc.t3.medium',
    nodeCount: 1,
  },
  security: {
    enableEncryption: true,
    enableMultiFactorAuth: true,
    kmsKeyRotation: true,
  },
  features: {
    enableDApp: true,
    enableMobileSupport: false,
    enableAuditReporting: true,
    enableRealTimeResults: true,
  },
  adminEmail: 'admin@test.com',
  logRetentionDays: 7,
};

export const mockAWSServices = {
  dynamodb: {
    createTable: jest.fn(),
    putItem: jest.fn(),
    getItem: jest.fn(),
    query: jest.fn(),
    scan: jest.fn(),
  },
  s3: {
    createBucket: jest.fn(),
    putObject: jest.fn(),
    getObject: jest.fn(),
    listObjects: jest.fn(),
  },
  lambda: {
    createFunction: jest.fn(),
    invoke: jest.fn(),
    updateFunctionCode: jest.fn(),
  },
  sns: {
    createTopic: jest.fn(),
    publish: jest.fn(),
    subscribe: jest.fn(),
  },
  kms: {
    createKey: jest.fn(),
    encrypt: jest.fn(),
    decrypt: jest.fn(),
    generateDataKey: jest.fn(),
  },
};