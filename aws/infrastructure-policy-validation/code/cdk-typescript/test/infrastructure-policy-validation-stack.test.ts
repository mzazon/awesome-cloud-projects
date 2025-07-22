import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { InfrastructurePolicyValidationStack } from '../lib/infrastructure-policy-validation-stack';

describe('InfrastructurePolicyValidationStack', () => {
  let app: cdk.App;
  let stack: InfrastructurePolicyValidationStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new InfrastructurePolicyValidationStack(app, 'TestStack', {
      env: {
        account: '123456789012',
        region: 'us-east-1',
      },
    });
    template = Template.fromStack(stack);
  });

  describe('S3 Bucket Configuration', () => {
    test('creates S3 bucket with security best practices', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        VersioningConfiguration: {
          Status: 'Enabled',
        },
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

    test('creates access logs bucket when enabled', () => {
      const stackWithLogging = new InfrastructurePolicyValidationStack(app, 'TestStackLogging', {
        enableAccessLogging: true,
        env: {
          account: '123456789012',
          region: 'us-east-1',
        },
      });

      const loggingTemplate = Template.fromStack(stackWithLogging);
      
      // Should have two buckets: main bucket and access logs bucket
      loggingTemplate.resourceCountIs('AWS::S3::Bucket', 2);
    });

    test('configures lifecycle rules for cost optimization', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        LifecycleConfiguration: {
          Rules: Match.arrayWith([
            {
              Id: 'DeleteNonCurrentVersionsAfter30Days',
              NoncurrentVersionExpiration: {
                NoncurrentDays: 30,
              },
              Status: 'Enabled',
            },
            {
              Id: 'TransitionToIAAfter30Days',
              Status: 'Enabled',
              Transitions: [
                {
                  StorageClass: 'STANDARD_IA',
                  TransitionInDays: 30,
                },
              ],
            },
          ]),
        },
      });
    });
  });

  describe('IAM Role Configuration', () => {
    test('creates validation role with least privilege permissions', () => {
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
        ManagedPolicyArns: [
          {
            'Fn::Join': [
              '',
              [
                'arn:',
                {
                  Ref: 'AWS::Partition',
                },
                ':iam::aws:policy/service-role/AWSLambdaBasicExecutionRole',
              ],
            ],
          },
        ],
      });
    });

    test('grants appropriate S3 permissions', () => {
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            {
              Effect: 'Allow',
              Action: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket',
                's3:GetBucketVersioning',
              ],
              Resource: Match.anyValue(),
            },
          ]),
        },
      });
    });

    test('grants CloudFormation validation permissions', () => {
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            {
              Effect: 'Allow',
              Action: [
                'cloudformation:ValidateTemplate',
                'cloudformation:GetTemplate',
                'cloudformation:DescribeStacks',
                'cloudformation:DescribeStackResources',
              ],
              Resource: '*',
            },
          ]),
        },
      });
    });
  });

  describe('Lambda Function Configuration', () => {
    test('creates validation function with appropriate configuration', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        Runtime: 'python3.11',
        Handler: 'index.handler',
        Timeout: 900, // 15 minutes
        MemorySize: 1024,
        Description: 'Lambda function for CloudFormation Guard validation workflows',
      });
    });

    test('configures environment variables', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        Environment: {
          Variables: {
            BUCKET_NAME: {
              Ref: Match.stringLikeRegexp('GuardRulesBucket'),
            },
            LOG_LEVEL: 'INFO',
            POWERTOOLS_SERVICE_NAME: 'cfn-guard-validation',
          },
        },
      });
    });

    test('creates dedicated log group with retention', () => {
      template.hasResourceProperties('AWS::Logs::LogGroup', {
        RetentionInDays: 30,
        LogGroupName: Match.stringLikeRegexp('/aws/lambda/.*validation.*'),
      });
    });
  });

  describe('EventBridge Configuration', () => {
    test('creates scheduled validation rule', () => {
      template.hasResourceProperties('AWS::Events::Rule', {
        Description: 'Triggers scheduled CloudFormation Guard validations',
        ScheduleExpression: 'cron(0 9 * * ? *)',
        State: 'ENABLED',
      });
    });

    test('creates validation results processing rule', () => {
      template.hasResourceProperties('AWS::Events::Rule', {
        Description: 'Processes CloudFormation Guard validation results',
        EventPattern: {
          source: ['cfn.guard.validation'],
          'detail-type': ['guard-rule-validation', 'scheduled-validation'],
        },
        State: 'ENABLED',
      });
    });

    test('creates CloudWatch log group for results', () => {
      template.hasResourceProperties('AWS::Logs::LogGroup', {
        LogGroupName: '/aws/events/cfn-guard-validation-results',
        RetentionInDays: 30,
      });
    });
  });

  describe('S3 Deployment Configuration', () => {
    test('creates bucket deployment for sample rules', () => {
      template.hasResourceProperties('Custom::CDKBucketDeployment', {
        ServiceToken: Match.anyValue(),
        SourceBucketNames: Match.arrayWith([Match.anyValue()]),
        DestinationBucketName: {
          Ref: Match.stringLikeRegexp('GuardRulesBucket'),
        },
      });
    });
  });

  describe('Stack Outputs', () => {
    test('exports bucket name and ARN', () => {
      template.hasOutput('GuardRulesBucketName', {
        Description: 'Name of the S3 bucket storing CloudFormation Guard rules',
        Export: {
          Name: 'TestStack-GuardRulesBucket',
        },
      });

      template.hasOutput('GuardRulesBucketArn', {
        Description: 'ARN of the S3 bucket storing CloudFormation Guard rules',
      });
    });

    test('exports validation role and function information', () => {
      template.hasOutput('ValidationRoleArn', {
        Description: 'ARN of the IAM role for CloudFormation Guard validation',
      });

      template.hasOutput('ValidationFunctionArn', {
        Description: 'ARN of the Lambda function for CloudFormation Guard validation',
      });

      template.hasOutput('ValidationFunctionName', {
        Description: 'Name of the Lambda function for CloudFormation Guard validation',
      });
    });

    test('provides sample validation command', () => {
      template.hasOutput('SampleValidationCommand', {
        Description: 'Sample AWS CLI command to trigger validation',
      });
    });
  });

  describe('Resource Configuration Options', () => {
    test('respects custom resource prefix', () => {
      const customStack = new InfrastructurePolicyValidationStack(app, 'CustomStack', {
        resourcePrefix: 'custom-prefix',
        env: {
          account: '123456789012',
          region: 'us-east-1',
        },
      });

      const customTemplate = Template.fromStack(customStack);
      
      // Check that bucket name uses custom prefix
      customTemplate.hasResourceProperties('AWS::S3::Bucket', {
        BucketName: Match.stringLikeRegexp('custom-prefix-policies-.*'),
      });
    });

    test('can disable versioning when specified', () => {
      const noVersioningStack = new InfrastructurePolicyValidationStack(app, 'NoVersioningStack', {
        enableVersioning: false,
        env: {
          account: '123456789012',
          region: 'us-east-1',
        },
      });

      const noVersioningTemplate = Template.fromStack(noVersioningStack);
      
      // Should not have versioning configuration when disabled
      noVersioningTemplate.hasResourceProperties('AWS::S3::Bucket', {
        VersioningConfiguration: Match.absent(),
      });
    });

    test('supports custom KMS key for encryption', () => {
      const kmsKeyArn = 'arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012';
      
      const kmsStack = new InfrastructurePolicyValidationStack(app, 'KmsStack', {
        kmsKeyId: kmsKeyArn,
        env: {
          account: '123456789012',
          region: 'us-east-1',
        },
      });

      const kmsTemplate = Template.fromStack(kmsStack);
      
      kmsTemplate.hasResourceProperties('AWS::S3::Bucket', {
        BucketEncryption: {
          ServerSideEncryptionConfiguration: [
            {
              ServerSideEncryptionByDefault: {
                SSEAlgorithm: 'aws:kms',
              },
            },
          ],
        },
      });
    });
  });

  describe('Resource Count Validation', () => {
    test('creates expected number of resources', () => {
      // Count key resource types
      template.resourceCountIs('AWS::S3::Bucket', 2); // Main bucket + access logs bucket
      template.resourceCountIs('AWS::IAM::Role', 1);
      template.resourceCountIs('AWS::Lambda::Function', 1);
      template.resourceCountIs('AWS::Events::Rule', 2); // Schedule rule + results rule
      template.resourceCountIs('AWS::Logs::LogGroup', 3); // Function logs + results logs + validation logs
    });
  });

  describe('Security Validations', () => {
    test('enforces HTTPS for S3 bucket access', () => {
      template.hasResourceProperties('AWS::S3::BucketPolicy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            {
              Effect: 'Deny',
              Principal: '*',
              Action: 's3:*',
              Resource: Match.anyValue(),
              Condition: {
                Bool: {
                  'aws:SecureTransport': 'false',
                },
              },
            },
          ]),
        },
      });
    });
  });
});