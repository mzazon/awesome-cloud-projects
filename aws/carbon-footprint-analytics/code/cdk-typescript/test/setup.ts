// Jest setup file for CDK tests
import 'jest';

// Global test timeout configuration
jest.setTimeout(30000);

// Suppress CDK deprecation warnings during tests
process.env.CDK_DISABLE_VERSION_CHECK = 'true';