// Jest setup for unit tests
import 'aws-sdk-client-mock-jest';

// Mock AWS SDK
jest.mock('aws-sdk', () => ({
  S3: jest.fn(() => ({
    putObject: jest.fn().mockReturnThis(),
    getObject: jest.fn().mockReturnThis(),
    listObjectsV2: jest.fn().mockReturnThis(),
    promise: jest.fn(),
  })),
  Lambda: jest.fn(() => ({
    invoke: jest.fn().mockReturnThis(),
    promise: jest.fn(),
  })),
  CloudFormation: jest.fn(() => ({
    validateTemplate: jest.fn().mockReturnThis(),
    promise: jest.fn(),
  })),
  EventBridge: jest.fn(() => ({
    putEvents: jest.fn().mockReturnThis(),
    promise: jest.fn(),
  })),
}));

// Set test environment variables
process.env.AWS_REGION = 'us-east-1';
process.env.AWS_ACCOUNT_ID = '123456789012';

// Global test configuration
const originalConsoleLog = console.log;
const originalConsoleError = console.error;

beforeAll(() => {
  // Suppress console output during tests unless DEBUG is set
  if (!process.env.DEBUG) {
    console.log = jest.fn();
    console.error = jest.fn();
  }
});

afterAll(() => {
  // Restore console output
  console.log = originalConsoleLog;
  console.error = originalConsoleError;
});

// Custom matchers
expect.extend({
  toBeValidBucketName(received) {
    const bucketNameRegex = /^[a-z0-9][a-z0-9\-]*[a-z0-9]$/;
    const pass = bucketNameRegex.test(received) && received.length >= 3 && received.length <= 63;
    
    return {
      message: () => `expected ${received} to be a valid S3 bucket name`,
      pass,
    };
  },
  
  toBeValidIamRoleName(received) {
    const roleNameRegex = /^[a-zA-Z0-9+=,.@_-]+$/;
    const pass = roleNameRegex.test(received) && received.length <= 64;
    
    return {
      message: () => `expected ${received} to be a valid IAM role name`,
      pass,
    };
  },
});

// Type augmentation for custom matchers
declare global {
  namespace jest {
    interface Matchers<R> {
      toBeValidBucketName(): R;
      toBeValidIamRoleName(): R;
    }
  }
}