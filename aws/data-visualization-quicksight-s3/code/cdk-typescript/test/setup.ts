// Test setup file for Jest
// Add any global test configuration or mocks here

import 'aws-cdk-lib/assertions';

// Mock AWS SDK if needed for tests
jest.mock('aws-sdk', () => ({
  // Add mocks as needed
}));

// Set test timeout for CDK tests
jest.setTimeout(30000);