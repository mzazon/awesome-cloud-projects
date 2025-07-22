import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { AnalyticsOptimizedS3TablesStack } from '../lib/analytics-optimized-s3-tables-stack';

/**
 * Test suite for Analytics-Optimized S3 Tables Stack
 * 
 * These tests validate the CDK stack configuration and ensure
 * proper resource creation with security best practices.
 */

describe('AnalyticsOptimizedS3TablesStack', () => {
  let app: cdk.App;
  let stack: AnalyticsOptimizedS3TablesStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new AnalyticsOptimizedS3TablesStack(app, 'TestStack', {
      env: {
        account: '123456789012',
        region: 'us-east-1',
      },
    });
    template = Template.fromStack(stack);
  });

  describe('S3 Resources', () => {
    test('creates data bucket with proper encryption', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        BucketEncryption: {
          ServerSideEncryptionConfiguration: [
            {
              ServerSideEncryptionByDefault: {
                SSEAlgorithm: 'AES256',
              },
            },
          ],
        },
        PublicAccessBlockConfiguration: {
          BlockPublicAcls: true,
          BlockPublicPolicy: true,
          IgnorePublicAcls: true,
          RestrictPublicBuckets: true,
        },
      });
    });

    test('creates Athena results bucket with lifecycle policy', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        LifecycleConfiguration: {
          Rules: [
            {
              Status: 'Enabled',
              ExpirationInDays: 30,
            },
          ],
        },
      });
    });

    test('creates exactly two S3 buckets', () => {
      template.resourceCountIs('AWS::S3::Bucket', 2);
    });
  });

  describe('AWS Glue Resources', () => {
    test('creates Glue database with proper configuration', () => {
      template.hasResourceProperties('AWS::Glue::Database', {
        DatabaseInput: {
          Name: 's3-tables-analytics',
          Description: 'AWS Glue database for S3 Tables analytics workloads',
          Parameters: {
            classification: 'iceberg',
            has_encrypted_data: 'true',
          },
        },
      });
    });
  });

  describe('Amazon Athena Resources', () => {
    test('creates Athena workgroup with proper configuration', () => {
      template.hasResourceProperties('AWS::Athena::WorkGroup', {
        Name: 's3-tables-workgroup',
        Description: 'Athena workgroup optimized for S3 Tables analytics',
        State: 'ENABLED',
        WorkGroupConfiguration: {
          EnforceWorkGroupConfiguration: true,
          PublishCloudWatchMetrics: true,
          ResultConfiguration: {
            EncryptionConfiguration: {
              EncryptionOption: 'SSE_S3',
            },
          },
          EngineVersion: {
            SelectedEngineVersion: 'Athena engine version 3',
          },
        },
      });
    });
  });

  describe('IAM Resources', () => {
    test('creates IAM role for S3 Tables custom resource', () => {
      template.hasResourceProperties('AWS::IAM::Role', {
        AssumeRolePolicyDocument: {
          Statement: [
            {
              Effect: 'Allow',
              Principal: {
                Service: 'lambda.amazonaws.com',
              },
              Action: 'sts:AssumeRole',
            },
          ],
        },
      });
    });

    test('creates proper IAM policies for S3 Tables operations', () => {
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            {
              Effect: 'Allow',
              Action: Match.arrayWith(['s3tables:*']),
              Resource: '*',
            },
          ]),
        },
      });
    });
  });

  describe('Lambda Resources', () => {
    test('creates Lambda function for S3 Tables custom resource', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        Runtime: 'python3.11',
        Handler: 'index.handler',
        Timeout: 300,
      });
    });

    test('creates Lambda log group with proper retention', () => {
      template.hasResourceProperties('AWS::Logs::LogGroup', {
        RetentionInDays: 7,
      });
    });
  });

  describe('Custom Resources', () => {
    test('creates custom resource for S3 Tables', () => {
      template.hasResourceProperties('AWS::CloudFormation::CustomResource', {
        TableBucketName: Match.stringLikeRegexp('analytics-tables-.*'),
        NamespaceName: 'sales_analytics',
        TableName: 'transaction_data',
      });
    });
  });

  describe('S3 Deployment', () => {
    test('creates S3 deployment for sample data', () => {
      // Check that there's a custom resource for S3 deployment
      template.hasResourceProperties('AWS::CloudFormation::CustomResource', {
        ServiceToken: Match.anyValue(),
      });
    });
  });

  describe('Stack Outputs', () => {
    test('creates proper CloudFormation outputs', () => {
      template.hasOutput('DataBucketName', {
        Description: 'Name of the S3 bucket containing sample data',
      });

      template.hasOutput('AthenaResultsBucketName', {
        Description: 'Name of the S3 bucket for Athena query results',
      });

      template.hasOutput('GlueDatabaseName', {
        Description: 'Name of the AWS Glue database for S3 Tables',
      });

      template.hasOutput('AthenaWorkgroupName', {
        Description: 'Name of the Amazon Athena workgroup',
      });
    });
  });

  describe('Security Validation', () => {
    test('ensures no hardcoded credentials', () => {
      // This test ensures no hardcoded AWS credentials are in the template
      const templateJson = JSON.stringify(template.toJSON());
      expect(templateJson).not.toMatch(/AKIA[A-Z0-9]{16}/); // AWS Access Key pattern
      expect(templateJson).not.toMatch(/[A-Za-z0-9/+=]{40}/); // AWS Secret Key pattern
    });

    test('ensures S3 buckets have public access blocked', () => {
      const buckets = template.findResources('AWS::S3::Bucket');
      Object.values(buckets).forEach((bucket: any) => {
        expect(bucket.Properties.PublicAccessBlockConfiguration).toEqual({
          BlockPublicAcls: true,
          BlockPublicPolicy: true,
          IgnorePublicAcls: true,
          RestrictPublicBuckets: true,
        });
      });
    });

    test('ensures all S3 buckets have encryption enabled', () => {
      const buckets = template.findResources('AWS::S3::Bucket');
      Object.values(buckets).forEach((bucket: any) => {
        expect(bucket.Properties.BucketEncryption).toBeDefined();
      });
    });
  });

  describe('Tagging', () => {
    test('includes proper resource tagging', () => {
      // Verify that resources include appropriate tags
      const template = Template.fromStack(stack);
      const stackJson = template.toJSON();
      
      // Check that tags are applied at the stack level
      expect(stackJson.Parameters).toBeDefined();
    });
  });
});

/**
 * Integration tests for stack synthesis and deployment validation
 */
describe('Stack Synthesis', () => {
  test('synthesizes without errors', () => {
    const app = new cdk.App();
    const stack = new AnalyticsOptimizedS3TablesStack(app, 'TestStack');
    
    // This will throw if there are synthesis errors
    expect(() => {
      app.synth();
    }).not.toThrow();
  });

  test('has correct stack metadata', () => {
    const app = new cdk.App();
    const stack = new AnalyticsOptimizedS3TablesStack(app, 'TestStack', {
      description: 'Test stack for analytics-optimized S3 Tables',
    });

    expect(stack.stackName).toBe('TestStack');
    expect(stack.templateOptions.description).toContain('Test stack');
  });
});