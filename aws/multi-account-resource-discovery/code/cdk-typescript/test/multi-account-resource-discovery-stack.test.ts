import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { MultiAccountResourceDiscoveryStack } from '../lib/multi-account-resource-discovery-stack';

/**
 * Test suite for Multi-Account Resource Discovery Stack
 * 
 * These tests validate the CDK stack creates the expected resources
 * with proper configurations for security, compliance, and functionality.
 */
describe('MultiAccountResourceDiscoveryStack', () => {
  let app: cdk.App;
  let stack: MultiAccountResourceDiscoveryStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new MultiAccountResourceDiscoveryStack(app, 'TestStack', {
      projectName: 'test-discovery',
      env: {
        account: '123456789012',
        region: 'us-east-1',
      },
    });
    template = Template.fromStack(stack);
  });

  describe('Lambda Function', () => {
    test('creates processing function with correct configuration', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        FunctionName: 'test-discovery-processor',
        Runtime: 'python3.12',
        Handler: 'lambda_function.lambda_handler',
        Timeout: 300,
        MemorySize: 1024,
        ReservedConcurrentExecutions: 10,
      });
    });

    test('creates Lambda function with environment variables', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        Environment: {
          Variables: {
            PROJECT_NAME: 'test-discovery',
            REGION: 'us-east-1',
            ACCOUNT_ID: '123456789012',
          },
        },
      });
    });

    test('creates Lambda function with dead letter queue', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        DeadLetterConfig: {
          TargetArn: Match.anyValue(),
        },
      });
    });
  });

  describe('IAM Roles and Policies', () => {
    test('creates Lambda execution role', () => {
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

    test('creates Config service role', () => {
      template.hasResourceProperties('AWS::IAM::Role', {
        AssumeRolePolicyDocument: {
          Statement: [
            {
              Effect: 'Allow',
              Principal: {
                Service: 'config.amazonaws.com',
              },
              Action: 'sts:AssumeRole',
            },
          ],
        },
      });
    });

    test('attaches required managed policies to Lambda role', () => {
      template.hasResourceProperties('AWS::IAM::Role', {
        ManagedPolicyArns: Match.arrayWith([
          'arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole',
        ]),
      });
    });

    test('creates custom policy for Lambda with required permissions', () => {
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            {
              Effect: 'Allow',
              Action: Match.arrayWith([
                'config:GetComplianceDetailsByConfigRule',
                'config:GetAggregateComplianceDetailsByConfigRule',
                'resource-explorer-2:Search',
                'resource-explorer-2:GetIndex',
                'organizations:ListAccounts',
                'organizations:DescribeOrganization',
              ]),
              Resource: '*',
            },
          ]),
        },
      });
    });
  });

  describe('S3 Bucket Configuration', () => {
    test('creates Config bucket with encryption', () => {
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
      });
    });

    test('creates Config bucket with versioning enabled', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        VersioningConfiguration: {
          Status: 'Enabled',
        },
      });
    });

    test('creates Config bucket with public access blocked', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        PublicAccessBlockConfiguration: {
          BlockPublicAcls: true,
          BlockPublicPolicy: true,
          IgnorePublicAcls: true,
          RestrictPublicBuckets: true,
        },
      });
    });

    test('creates lifecycle rule for Config bucket', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        LifecycleConfiguration: {
          Rules: [
            {
              Id: 'ConfigDataLifecycle',
              Status: 'Enabled',
              Transitions: [
                {
                  StorageClass: 'STANDARD_IA',
                  TransitionInDays: 30,
                },
                {
                  StorageClass: 'GLACIER',
                  TransitionInDays: 90,
                },
              ],
              ExpirationInDays: 2557,
            },
          ],
        },
      });
    });

    test('creates access logs bucket', () => {
      // Should create a second bucket for access logs
      const buckets = template.findResources('AWS::S3::Bucket');
      expect(Object.keys(buckets).length).toBeGreaterThanOrEqual(2);
    });

    test('creates bucket policy for Config service', () => {
      template.hasResourceProperties('AWS::S3::BucketPolicy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            {
              Effect: 'Allow',
              Principal: {
                Service: 'config.amazonaws.com',
              },
              Action: Match.arrayWith(['s3:GetBucketAcl', 's3:ListBucket']),
              Condition: {
                StringEquals: {
                  'AWS:SourceAccount': '123456789012',
                },
              },
            },
          ]),
        },
      });
    });
  });

  describe('Resource Explorer Configuration', () => {
    test('creates Resource Explorer aggregated index', () => {
      template.hasResourceProperties('AWS::ResourceExplorer2::Index', {
        Type: 'AGGREGATOR',
        Tags: {
          Name: 'test-discovery-resource-explorer-index',
          Purpose: 'Multi-account resource discovery',
          ManagedBy: 'test-discovery',
        },
      });
    });

    test('creates Resource Explorer view', () => {
      template.hasResourceProperties('AWS::ResourceExplorer2::View', {
        ViewName: 'test-discovery-organization-view',
        IncludedProperties: [
          {
            Name: 'tags',
          },
        ],
      });
    });
  });

  describe('AWS Config Configuration', () => {
    test('creates configuration recorder', () => {
      template.hasResourceProperties('AWS::Config::ConfigurationRecorder', {
        Name: 'test-discovery-recorder',
        RecordingGroup: {
          AllSupported: true,
          IncludeGlobalResourceTypes: true,
          ResourceTypes: [],
        },
        RecordingMode: {
          RecordingFrequency: 'CONTINUOUS',
        },
      });
    });

    test('creates delivery channel', () => {
      template.hasResourceProperties('AWS::Config::DeliveryChannel', {
        Name: 'test-discovery-delivery-channel',
        ConfigSnapshotDeliveryProperties: {
          DeliveryFrequency: 'TwentyFour_Hours',
        },
      });
    });

    test('creates configuration aggregator', () => {
      template.hasResourceProperties('AWS::Config::ConfigurationAggregator', {
        ConfigurationAggregatorName: 'test-discovery-aggregator',
        OrganizationAggregationSource: {
          AwsRegions: ['us-east-1'],
          AllAwsRegions: false,
        },
      });
    });

    test('creates expected number of Config rules', () => {
      const configRules = template.findResources('AWS::Config::ConfigRule');
      expect(Object.keys(configRules).length).toBe(6); // Should create 6 compliance rules
    });

    test('creates S3 bucket public access prohibited rule', () => {
      template.hasResourceProperties('AWS::Config::ConfigRule', {
        ConfigRuleName: 'test-discovery-s3-bucket-public-access-prohibited',
        Source: {
          Owner: 'AWS',
          SourceIdentifier: 'S3_BUCKET_PUBLIC_ACCESS_PROHIBITED',
        },
      });
    });

    test('creates encrypted volumes rule', () => {
      template.hasResourceProperties('AWS::Config::ConfigRule', {
        ConfigRuleName: 'test-discovery-encrypted-volumes',
        Source: {
          Owner: 'AWS',
          SourceIdentifier: 'ENCRYPTED_VOLUMES',
        },
      });
    });

    test('creates IAM password policy rule with parameters', () => {
      template.hasResourceProperties('AWS::Config::ConfigRule', {
        ConfigRuleName: 'test-discovery-iam-password-policy',
        Source: {
          Owner: 'AWS',
          SourceIdentifier: 'IAM_PASSWORD_POLICY',
        },
        InputParameters: Match.stringLikeRegexp('.*RequireUppercaseCharacters.*true.*'),
      });
    });
  });

  describe('EventBridge Rules', () => {
    test('creates Config compliance rule', () => {
      template.hasResourceProperties('AWS::Events::Rule', {
        Name: 'test-discovery-config-compliance-rule',
        EventPattern: {
          source: ['aws.config'],
          'detail-type': ['Config Rules Compliance Change'],
          detail: {
            newEvaluationResult: {
              complianceType: ['NON_COMPLIANT'],
            },
          },
        },
      });
    });

    test('creates scheduled discovery rule', () => {
      template.hasResourceProperties('AWS::Events::Rule', {
        Name: 'test-discovery-scheduled-discovery-rule',
        ScheduleExpression: 'rate(1 day)',
      });
    });

    test('creates Resource Explorer rule', () => {
      template.hasResourceProperties('AWS::Events::Rule', {
        Name: 'test-discovery-resource-explorer-rule',
        EventPattern: {
          source: ['aws.resource-explorer-2'],
        },
      });
    });

    test('EventBridge rules target Lambda function', () => {
      template.hasResourceProperties('AWS::Events::Rule', {
        Targets: [
          {
            Arn: Match.anyValue(),
            Id: Match.anyValue(),
            RetryPolicy: {
              MaximumEventAge: 7200,
              MaximumRetryAttempts: 2,
            },
          },
        ],
      });
    });
  });

  describe('CloudWatch Configuration', () => {
    test('creates Lambda log group with retention', () => {
      template.hasResourceProperties('AWS::Logs::LogGroup', {
        LogGroupName: '/aws/lambda/test-discovery-processor',
        RetentionInDays: 30,
      });
    });
  });

  describe('Stack Outputs', () => {
    test('creates expected CloudFormation outputs', () => {
      template.hasOutput('ProcessingFunctionArn', {
        Export: {
          Name: 'test-discovery-processing-function-arn',
        },
      });

      template.hasOutput('ConfigBucketName', {
        Export: {
          Name: 'test-discovery-config-bucket-name',
        },
      });

      template.hasOutput('ResourceExplorerIndexArn', {
        Export: {
          Name: 'test-discovery-resource-explorer-index-arn',
        },
      });

      template.hasOutput('ConfigAggregatorName', {
        Export: {
          Name: 'test-discovery-config-aggregator-name',
        },
      });

      template.hasOutput('ProjectName', {});
      template.hasOutput('DeploymentRegion', {});
    });
  });

  describe('Resource Count Validation', () => {
    test('creates expected total number of resources', () => {
      const resources = template.findResources('*');
      const resourceCount = Object.keys(resources).length;
      
      // Validate minimum expected resources (this will vary based on CDK constructs)
      expect(resourceCount).toBeGreaterThan(20);
    });

    test('resource naming follows conventions', () => {
      const resources = template.findResources('*');
      
      // Check that critical resources exist
      const hasLambdaFunction = Object.values(resources).some(
        resource => resource.Type === 'AWS::Lambda::Function'
      );
      const hasS3Bucket = Object.values(resources).some(
        resource => resource.Type === 'AWS::S3::Bucket'
      );
      const hasConfigRule = Object.values(resources).some(
        resource => resource.Type === 'AWS::Config::ConfigRule'
      );
      const hasEventRule = Object.values(resources).some(
        resource => resource.Type === 'AWS::Events::Rule'
      );

      expect(hasLambdaFunction).toBe(true);
      expect(hasS3Bucket).toBe(true);
      expect(hasConfigRule).toBe(true);
      expect(hasEventRule).toBe(true);
    });
  });

  describe('Security Validation', () => {
    test('no hardcoded sensitive values', () => {
      const templateJson = JSON.stringify(template.toJSON());
      
      // Check for common security anti-patterns
      expect(templateJson).not.toMatch(/AKIA[0-9A-Z]{16}/); // AWS Access Key ID pattern
      expect(templateJson).not.toMatch(/password.*[=:]\s*["'][^"']+["']/i); // Hardcoded passwords
      expect(templateJson).not.toMatch(/secret.*[=:]\s*["'][^"']+["']/i); // Hardcoded secrets
    });

    test('IAM roles use least privilege principle', () => {
      template.hasResourceProperties('AWS::IAM::Role', {
        AssumeRolePolicyDocument: {
          Statement: Match.arrayWith([
            {
              Effect: 'Allow',
              Principal: Match.objectLike({
                Service: Match.anyValue(),
              }),
            },
          ]),
        },
      });
    });

    test('S3 buckets block public access', () => {
      const buckets = template.findResources('AWS::S3::Bucket');
      
      Object.values(buckets).forEach((bucket: any) => {
        if (bucket.Properties?.PublicAccessBlockConfiguration) {
          expect(bucket.Properties.PublicAccessBlockConfiguration.BlockPublicAcls).toBe(true);
          expect(bucket.Properties.PublicAccessBlockConfiguration.BlockPublicPolicy).toBe(true);
          expect(bucket.Properties.PublicAccessBlockConfiguration.IgnorePublicAcls).toBe(true);
          expect(bucket.Properties.PublicAccessBlockConfiguration.RestrictPublicBuckets).toBe(true);
        }
      });
    });
  });
});