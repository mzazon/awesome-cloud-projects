// Jest setup for integration tests
import { STSClient, GetCallerIdentityCommand } from '@aws-sdk/client-sts';
import { S3Client, HeadBucketCommand } from '@aws-sdk/client-s3';
import { CloudFormationClient, DescribeStacksCommand } from '@aws-sdk/client-cloudformation';

// Integration test configuration
const INTEGRATION_TEST_TIMEOUT = 300000; // 5 minutes
const TEST_STACK_NAME = process.env.TEST_STACK_NAME || 'InfrastructurePolicyValidationStackIntegrationTest';

// AWS clients for integration testing
const stsClient = new STSClient({});
const s3Client = new S3Client({});
const cfnClient = new CloudFormationClient({});

beforeAll(async () => {
  // Verify AWS credentials are available
  try {
    const identity = await stsClient.send(new GetCallerIdentityCommand({}));
    console.log(`Running integration tests as AWS Account: ${identity.Account}`);
  } catch (error) {
    console.error('AWS credentials not available for integration tests:', error);
    throw new Error('AWS credentials required for integration tests');
  }
}, INTEGRATION_TEST_TIMEOUT);

afterAll(async () => {
  // Cleanup logic for integration tests
  console.log('Integration test cleanup completed');
});

// Helper functions for integration tests
export const testHelpers = {
  /**
   * Wait for stack to reach a specific status
   */
  async waitForStackStatus(stackName: string, expectedStatus: string, maxWaitTime = 300000) {
    const startTime = Date.now();
    
    while (Date.now() - startTime < maxWaitTime) {
      try {
        const response = await cfnClient.send(new DescribeStacksCommand({
          StackName: stackName,
        }));
        
        const stack = response.Stacks?.[0];
        if (stack?.StackStatus === expectedStatus) {
          return stack;
        }
        
        if (stack?.StackStatus?.includes('FAILED')) {
          throw new Error(`Stack ${stackName} failed with status: ${stack.StackStatus}`);
        }
        
        // Wait 10 seconds before checking again
        await new Promise(resolve => setTimeout(resolve, 10000));
      } catch (error) {
        if ((error as any).name === 'ValidationError') {
          throw new Error(`Stack ${stackName} does not exist`);
        }
        throw error;
      }
    }
    
    throw new Error(`Stack ${stackName} did not reach ${expectedStatus} within ${maxWaitTime}ms`);
  },

  /**
   * Get stack outputs by key
   */
  async getStackOutput(stackName: string, outputKey: string): Promise<string> {
    const response = await cfnClient.send(new DescribeStacksCommand({
      StackName: stackName,
    }));
    
    const stack = response.Stacks?.[0];
    const output = stack?.Outputs?.find(o => o.OutputKey === outputKey);
    
    if (!output?.OutputValue) {
      throw new Error(`Output ${outputKey} not found in stack ${stackName}`);
    }
    
    return output.OutputValue;
  },

  /**
   * Check if S3 bucket exists and is accessible
   */
  async verifyS3BucketExists(bucketName: string): Promise<boolean> {
    try {
      await s3Client.send(new HeadBucketCommand({
        Bucket: bucketName,
      }));
      return true;
    } catch (error) {
      return false;
    }
  },

  /**
   * Generate unique test resource name
   */
  generateTestResourceName(baseName: string): string {
    const timestamp = Date.now();
    const random = Math.random().toString(36).substring(2, 8);
    return `${baseName}-${timestamp}-${random}`.toLowerCase();
  },

  /**
   * Sleep for specified milliseconds
   */
  async sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  },
};

// Global test configuration for integration tests
jest.setTimeout(INTEGRATION_TEST_TIMEOUT);

export { TEST_STACK_NAME, INTEGRATION_TEST_TIMEOUT };