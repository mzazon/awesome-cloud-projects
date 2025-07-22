// Jest setup file for CDK tests
import 'source-map-support/register';

// Mock AWS SDK calls during testing
jest.mock('aws-sdk', () => ({
  config: {
    update: jest.fn(),
  },
  STS: jest.fn(() => ({
    getCallerIdentity: jest.fn().mockReturnValue({
      promise: jest.fn().mockResolvedValue({
        Account: '123456789012',
        Arn: 'arn:aws:iam::123456789012:user/test-user',
        UserId: 'AIDACKCEVSQ6C2EXAMPLE',
      }),
    }),
  })),
}));

// Set default environment variables for tests
process.env.CDK_DEFAULT_ACCOUNT = '123456789012';
process.env.CDK_DEFAULT_REGION = 'us-east-1';

// Suppress CDK output during tests
process.env.CDK_DISABLE_STACK_TRACE = 'true';