/**
 * Jest setup file for CDK tests
 * 
 * This file is run before each test suite and can be used to configure
 * global test settings, mocks, or other test infrastructure.
 */

// Suppress CDK metadata and other verbose outputs during testing
process.env.CDK_DISABLE_STACK_TRACE = '1';
process.env.CDK_CLI_ASM_EXTERNAL_ID = 'test-external-id';

// Mock AWS region and account for consistent testing
process.env.CDK_DEFAULT_REGION = 'us-east-1';
process.env.CDK_DEFAULT_ACCOUNT = '123456789012';

// Increase Jest timeout for CDK tests which can be slower
jest.setTimeout(30000);

// Global test configuration
beforeAll(() => {
  // Any global setup logic
  console.log('Setting up CDK test environment...');
});

afterAll(() => {
  // Any global cleanup logic
  console.log('Cleaning up CDK test environment...');
});

// Mock console methods to reduce test output noise
const originalConsole = console;
global.console = {
  ...originalConsole,
  // Keep error and warn, but suppress info and log during tests
  log: jest.fn(),
  info: jest.fn(),
  warn: originalConsole.warn,
  error: originalConsole.error,
};