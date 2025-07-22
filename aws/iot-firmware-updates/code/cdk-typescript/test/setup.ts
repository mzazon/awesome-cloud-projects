// Test setup configuration
import 'jest';

// Mock AWS SDK calls during testing
jest.mock('aws-sdk', () => ({
  // Mock AWS services as needed
  config: {
    update: jest.fn(),
  },
}));

// Set default timeout for tests
jest.setTimeout(30000);

// Setup global test environment
beforeAll(() => {
  // Set environment variables for testing
  process.env.CDK_DEFAULT_ACCOUNT = '123456789012';
  process.env.CDK_DEFAULT_REGION = 'us-east-1';
});

afterAll(() => {
  // Clean up test environment
  delete process.env.CDK_DEFAULT_ACCOUNT;
  delete process.env.CDK_DEFAULT_REGION;
});