import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as events from 'aws-cdk-lib/aws-events';
import * as sns from 'aws-cdk-lib/aws-sns';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { SustainabilityDashboardStack } from '../lib/sustainability-dashboard-stack';

describe('SustainabilityDashboardStack', () => {
  let app: cdk.App;
  let stack: SustainabilityDashboardStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new SustainabilityDashboardStack(app, 'TestSustainabilityDashboardStack', {
      env: { account: '123456789012', region: 'us-east-1' }
    });
    template = Template.fromStack(stack);
  });

  describe('S3 Data Lake Bucket', () => {
    test('should create S3 bucket with proper configuration', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        VersioningConfiguration: {
          Status: 'Enabled'
        },
        BucketEncryption: {
          ServerSideEncryptionConfiguration: [
            {
              ServerSideEncryptionByDefault: {
                SSEAlgorithm: 'AES256'
              }
            }
          ]
        },
        PublicAccessBlockConfiguration: {
          BlockPublicAcls: true,
          BlockPublicPolicy: true,
          IgnorePublicAcls: true,
          RestrictPublicBuckets: true
        }
      });
    });

    test('should have lifecycle configuration for cost optimization', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        LifecycleConfiguration: {
          Rules: [
            {
              Id: 'ArchiveOldData',
              Status: 'Enabled',
              Transitions: [
                {
                  StorageClass: 'STANDARD_IA',
                  TransitionInDays: 30
                },
                {
                  StorageClass: 'GLACIER',
                  TransitionInDays: 90
                },
                {
                  StorageClass: 'DEEP_ARCHIVE',
                  TransitionInDays: 365
                }
              ]
            }
          ]
        }
      });
    });
  });

  describe('Lambda Function', () => {
    test('should create Lambda function with correct runtime and handler', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        Runtime: 'python3.9',
        Handler: 'index.lambda_handler',
        Timeout: 300,
        MemorySize: 512
      });
    });

    test('should have environment variables configured', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        Environment: {
          Variables: {
            BUCKET_NAME: Match.anyValue(),
            AWS_REGION: Match.anyValue()
          }
        }
      });
    });

    test('should have proper IAM permissions', () => {
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Effect: 'Allow',
              Action: Match.arrayWith(['ce:GetCostAndUsage']),
              Resource: '*'
            }),
            Match.objectLike({
              Effect: 'Allow',
              Action: Match.arrayWith(['s3:GetObject', 's3:PutObject']),
              Resource: Match.anyValue()
            }),
            Match.objectLike({
              Effect: 'Allow',
              Action: ['cloudwatch:PutMetricData'],
              Resource: '*'
            })
          ])
        }
      });
    });
  });

  describe('EventBridge Rule', () => {
    test('should create scheduled rule for monthly execution', () => {
      template.hasResourceProperties('AWS::Events::Rule', {
        ScheduleExpression: 'rate(30 days)',
        State: 'ENABLED'
      });
    });

    test('should have Lambda function as target', () => {
      template.hasResourceProperties('AWS::Events::Rule', {
        Targets: [
          {
            Arn: Match.anyValue(),
            Id: Match.anyValue(),
            Input: Match.stringLikeRegexp('.*eventbridge.*')
          }
        ]
      });
    });
  });

  describe('SNS Topic', () => {
    test('should create SNS topic for alerts', () => {
      template.hasResourceProperties('AWS::SNS::Topic', {
        DisplayName: 'Sustainability Analytics Alerts'
      });
    });

    test('should enforce SSL on SNS topic', () => {
      template.hasResourceProperties('AWS::SNS::TopicPolicy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Effect: 'Deny',
              Principal: '*',
              Action: 'sns:Publish',
              Condition: {
                Bool: {
                  'aws:SecureTransport': 'false'
                }
              }
            })
          ])
        }
      });
    });
  });

  describe('CloudWatch Alarms', () => {
    test('should create alarm for Lambda errors', () => {
      template.hasResourceProperties('AWS::CloudWatch::Alarm', {
        MetricName: 'Errors',
        Namespace: 'AWS/Lambda',
        Statistic: 'Sum',
        Threshold: 1,
        ComparisonOperator: 'GreaterThanOrEqualToThreshold'
      });
    });

    test('should create alarm for successful processing', () => {
      template.hasResourceProperties('AWS::CloudWatch::Alarm', {
        MetricName: 'DataProcessingSuccess',
        Namespace: 'SustainabilityAnalytics',
        Statistic: 'Sum',
        Threshold: 1,
        ComparisonOperator: 'LessThanThreshold'
      });
    });

    test('should have SNS actions configured', () => {
      template.hasResourceProperties('AWS::CloudWatch::Alarm', {
        AlarmActions: Match.anyValue()
      });
    });
  });

  describe('Stack Outputs', () => {
    test('should create outputs for key resources', () => {
      template.hasOutput('DataLakeBucketName', {
        Description: 'S3 bucket name for sustainability analytics data lake'
      });

      template.hasOutput('DataProcessorFunctionName', {
        Description: 'Lambda function name for sustainability data processing'
      });

      template.hasOutput('AlertTopicArn', {
        Description: 'SNS topic ARN for sustainability alerts'
      });

      template.hasOutput('QuickSightManifestLocation', {
        Description: 'S3 location of QuickSight manifest file for data source setup'
      });
    });
  });

  describe('Security Best Practices', () => {
    test('should have SSL enforcement on S3 bucket', () => {
      template.hasResourceProperties('AWS::S3::BucketPolicy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Effect: 'Deny',
              Principal: '*',
              Action: 's3:*',
              Condition: {
                Bool: {
                  'aws:SecureTransport': 'false'
                }
              }
            })
          ])
        }
      });
    });

    test('should block all public access on S3 bucket', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        PublicAccessBlockConfiguration: {
          BlockPublicAcls: true,
          BlockPublicPolicy: true,
          IgnorePublicAcls: true,
          RestrictPublicBuckets: true
        }
      });
    });

    test('should have least privilege IAM permissions', () => {
      // Verify that IAM policies don't have overly broad permissions
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: Match.not(Match.arrayWith([
            Match.objectLike({
              Effect: 'Allow',
              Action: '*',
              Resource: '*'
            })
          ]))
        }
      });
    });
  });

  describe('Cost Optimization', () => {
    test('should have S3 lifecycle rules for cost optimization', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        LifecycleConfiguration: {
          Rules: Match.arrayWith([
            Match.objectLike({
              Transitions: Match.arrayWith([
                Match.objectLike({
                  StorageClass: 'STANDARD_IA'
                }),
                Match.objectLike({
                  StorageClass: 'GLACIER'
                }),
                Match.objectLike({
                  StorageClass: 'DEEP_ARCHIVE'
                })
              ])
            })
          ])
        }
      });
    });

    test('should have appropriate Lambda memory and timeout configuration', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        MemorySize: 512,
        Timeout: 300
      });
    });
  });

  describe('Stack Properties', () => {
    test('should accept custom properties', () => {
      const customStack = new SustainabilityDashboardStack(app, 'CustomStack', {
        alertEmail: 'test@example.com',
        lambdaMemorySize: 1024,
        lambdaTimeoutMinutes: 10,
        env: { account: '123456789012', region: 'us-east-1' }
      });

      const customTemplate = Template.fromStack(customStack);
      
      // Verify Lambda has custom configuration
      customTemplate.hasResourceProperties('AWS::Lambda::Function', {
        MemorySize: 1024,
        Timeout: 600
      });
    });
  });

  describe('Resource Count Validation', () => {
    test('should create expected number of resources', () => {
      const resources = template.toJSON().Resources;
      const resourceTypes = Object.values(resources).map((r: any) => r.Type);

      // Count key resource types
      expect(resourceTypes.filter(type => type === 'AWS::S3::Bucket')).toHaveLength(2); // Data lake + logs
      expect(resourceTypes.filter(type => type === 'AWS::Lambda::Function')).toHaveLength(2); // Data processor + manifest deploy
      expect(resourceTypes.filter(type => type === 'AWS::Events::Rule')).toHaveLength(1); // Schedule rule
      expect(resourceTypes.filter(type => type === 'AWS::SNS::Topic')).toHaveLength(1); // Alert topic
      expect(resourceTypes.filter(type => type === 'AWS::CloudWatch::Alarm')).toHaveLength(2); // Error + success alarms
      expect(resourceTypes.filter(type => type === 'AWS::IAM::Role')).toHaveLength(2); // Lambda roles
    });
  });
});

describe('Integration Tests', () => {
  test('should synthesize without errors', () => {
    const app = new cdk.App();
    
    expect(() => {
      new SustainabilityDashboardStack(app, 'TestStack', {
        env: { account: '123456789012', region: 'us-east-1' }
      });
    }).not.toThrow();
  });

  test('should produce valid CloudFormation template', () => {
    const app = new cdk.App();
    const stack = new SustainabilityDashboardStack(app, 'TestStack', {
      env: { account: '123456789012', region: 'us-east-1' }
    });

    const template = Template.fromStack(stack);
    const cfnTemplate = template.toJSON();

    // Verify CloudFormation template structure
    expect(cfnTemplate).toHaveProperty('AWSTemplateFormatVersion');
    expect(cfnTemplate).toHaveProperty('Resources');
    expect(cfnTemplate).toHaveProperty('Outputs');
    expect(Object.keys(cfnTemplate.Resources)).toHaveLength.greaterThan(0);
  });
});