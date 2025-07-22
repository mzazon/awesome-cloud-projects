// Jest setup file for CDK tests
process.env.AWS_REGION = 'us-east-1';
process.env.AWS_ACCOUNT_ID = '123456789012';

// Mock AWS SDK calls during testing
jest.mock('aws-sdk', () => ({
  config: {
    update: jest.fn(),
  },
}));

// Increase test timeout for CDK synthesis
jest.setTimeout(30000);