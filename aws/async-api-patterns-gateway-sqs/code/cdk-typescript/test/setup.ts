// Jest setup file for AWS CDK tests
import 'aws-sdk-client-mock-jest';

// Set AWS region for tests
process.env.AWS_DEFAULT_REGION = 'us-east-1';
process.env.CDK_DEFAULT_REGION = 'us-east-1';
process.env.CDK_DEFAULT_ACCOUNT = '123456789012';