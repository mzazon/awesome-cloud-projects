// Test setup file for CDK tests
// This file is run before each test suite

// Set default environment variables for testing
process.env.CDK_DEFAULT_ACCOUNT = '123456789012';
process.env.CDK_DEFAULT_REGION = 'us-east-1';

// Mock AWS SDK calls if needed
jest.mock('aws-sdk', () => ({
  config: {
    update: jest.fn(),
  },
}));

// Increase test timeout for CDK tests
jest.setTimeout(30000);

// Global test setup
beforeEach(() => {
  // Reset environment variables before each test
  delete process.env.CDK_DEFAULT_ACCOUNT;
  delete process.env.CDK_DEFAULT_REGION;
  
  // Set defaults
  process.env.CDK_DEFAULT_ACCOUNT = '123456789012';
  process.env.CDK_DEFAULT_REGION = 'us-east-1';
});

afterEach(() => {
  // Clean up after each test
  jest.clearAllMocks();
});