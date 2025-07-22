// Test setup file for Jest
// This file is executed before each test file

// Mock AWS SDK to avoid actual AWS API calls during testing
jest.mock('aws-sdk', () => ({
  CloudFront: jest.fn().mockImplementation(() => ({
    createInvalidation: jest.fn().mockReturnValue({
      promise: jest.fn().mockResolvedValue({
        Invalidation: {
          Id: 'test-invalidation-id',
          Status: 'InProgress',
          CreateTime: new Date(),
          InvalidationBatch: {
            Paths: {
              Quantity: 1,
              Items: ['/test-path']
            },
            CallerReference: 'test-caller-ref'
          }
        }
      })
    }),
    getInvalidation: jest.fn().mockReturnValue({
      promise: jest.fn().mockResolvedValue({
        Invalidation: {
          Id: 'test-invalidation-id',
          Status: 'Completed'
        }
      })
    })
  })),
  DynamoDB: {
    DocumentClient: jest.fn().mockImplementation(() => ({
      put: jest.fn().mockReturnValue({
        promise: jest.fn().mockResolvedValue({})
      }),
      get: jest.fn().mockReturnValue({
        promise: jest.fn().mockResolvedValue({
          Item: {
            InvalidationId: 'test-invalidation-id',
            Timestamp: new Date().toISOString(),
            Status: 'InProgress'
          }
        })
      }),
      scan: jest.fn().mockReturnValue({
        promise: jest.fn().mockResolvedValue({
          Items: [],
          Count: 0
        })
      })
    }))
  },
  SQS: jest.fn().mockImplementation(() => ({
    sendMessage: jest.fn().mockReturnValue({
      promise: jest.fn().mockResolvedValue({
        MessageId: 'test-message-id'
      })
    }),
    receiveMessage: jest.fn().mockReturnValue({
      promise: jest.fn().mockResolvedValue({
        Messages: []
      })
    })
  }))
}));

// Set up environment variables for testing
process.env.AWS_REGION = 'us-east-1';
process.env.AWS_ACCOUNT_ID = '123456789012';
process.env.DDB_TABLE_NAME = 'test-invalidation-log';
process.env.QUEUE_URL = 'https://sqs.us-east-1.amazonaws.com/123456789012/test-queue';
process.env.DISTRIBUTION_ID = 'test-distribution-id';
process.env.BATCH_SIZE = '10';
process.env.ENABLE_COST_OPTIMIZATION = 'true';

// Increase timeout for CDK synthesis tests
jest.setTimeout(60000);

// Global test helpers
global.testProps = {
  projectName: 'test-invalidation',
  env: { 
    account: '123456789012', 
    region: 'us-east-1' 
  },
  enableMonitoring: true,
  enableBatchProcessing: true,
  enableCostOptimization: true,
  lambdaTimeout: 300,
  lambdaMemory: 256,
  batchSize: 10,
  batchWindow: 30,
  priceClass: 'PriceClass_100',
  enableCompression: true,
  enableIPv6: true,
  enableOriginAccessControl: true,
  enforceHTTPS: true,
  retentionPeriod: 30,
  dashboardName: 'Test-Dashboard'
};

// Console log suppression for cleaner test output
const originalLog = console.log;
const originalWarn = console.warn;
const originalError = console.error;

beforeEach(() => {
  // Suppress AWS CDK logs during tests unless explicitly needed
  console.log = jest.fn();
  console.warn = jest.fn();
  console.error = jest.fn();
});

afterEach(() => {
  // Restore console methods
  console.log = originalLog;
  console.warn = originalWarn;
  console.error = originalError;
  
  // Clear all mocks
  jest.clearAllMocks();
});

// Custom matchers for CDK testing
expect.extend({
  toHaveResourceWithLogicalId(template, resourceType, logicalId) {
    const resources = template.template.Resources;
    const resource = resources[logicalId];
    
    const pass = resource && resource.Type === resourceType;
    
    if (pass) {
      return {
        message: () => `Expected template not to have resource ${resourceType} with logical ID ${logicalId}`,
        pass: true,
      };
    } else {
      return {
        message: () => `Expected template to have resource ${resourceType} with logical ID ${logicalId}`,
        pass: false,
      };
    }
  },
  
  toHaveOutputWithValue(template, outputKey, expectedValue) {
    const outputs = template.template.Outputs;
    const output = outputs[outputKey];
    
    const pass = output && output.Value === expectedValue;
    
    if (pass) {
      return {
        message: () => `Expected template not to have output ${outputKey} with value ${expectedValue}`,
        pass: true,
      };
    } else {
      return {
        message: () => `Expected template to have output ${outputKey} with value ${expectedValue}`,
        pass: false,
      };
    }
  }
});

// TypeScript declarations for global test helpers
declare global {
  var testProps: any;
  
  namespace jest {
    interface Matchers<R> {
      toHaveResourceWithLogicalId(resourceType: string, logicalId: string): R;
      toHaveOutputWithValue(outputKey: string, expectedValue: string): R;
    }
  }
}