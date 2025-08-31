// Global test setup for CDK testing

// Mock AWS SDK to prevent actual AWS calls during testing
jest.mock('aws-sdk', () => ({
  config: {
    update: jest.fn(),
  },
  // Add other AWS SDK mocks as needed
}));

// Set environment variables for testing
process.env.CDK_DEFAULT_ACCOUNT = '123456789012';
process.env.CDK_DEFAULT_REGION = 'us-east-1';

// Increase timeout for CDK tests which can be slow
jest.setTimeout(30000);

// Console log suppression for cleaner test output
const originalConsoleLog = console.log;
const originalConsoleWarn = console.warn;
const originalConsoleError = console.error;

beforeAll(() => {
  // Suppress console output during tests unless explicitly needed
  console.log = jest.fn();
  console.warn = jest.fn();
  console.error = jest.fn();
});

afterAll(() => {
  // Restore console methods
  console.log = originalConsoleLog;
  console.warn = originalConsoleWarn;
  console.error = originalConsoleError;
});