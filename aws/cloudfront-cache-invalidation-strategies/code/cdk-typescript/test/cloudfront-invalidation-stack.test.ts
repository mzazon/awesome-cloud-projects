import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { CloudFrontInvalidationStack } from '../lib/cloudfront-invalidation-stack';

describe('CloudFrontInvalidationStack', () => {
  let app: cdk.App;
  let stack: CloudFrontInvalidationStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new CloudFrontInvalidationStack(app, 'TestStack', {
      projectName: 'test-invalidation',
      env: { account: '123456789012', region: 'us-east-1' },
    });
    template = Template.fromStack(stack);
  });

  describe('S3 Bucket', () => {
    test('creates S3 bucket with correct configuration', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        BucketEncryption: {
          ServerSideEncryptionConfiguration: [{
            ServerSideEncryptionByDefault: {
              SSEAlgorithm: 'AES256'
            }
          }]
        },
        PublicAccessBlockConfiguration: {
          BlockPublicAcls: true,
          BlockPublicPolicy: true,
          IgnorePublicAcls: true,
          RestrictPublicBuckets: true
        },
        VersioningConfiguration: {
          Status: 'Enabled'
        },
        NotificationConfiguration: {
          EventBridgeConfiguration: {}
        }
      });
    });
  });

  describe('CloudFront Distribution', () => {
    test('creates CloudFront distribution with OAC', () => {
      template.hasResourceProperties('AWS::CloudFront::Distribution', {
        DistributionConfig: {
          Enabled: true,
          DefaultRootObject: 'index.html',
          HttpVersion: 'http2',
          IPV6Enabled: true,
          PriceClass: 'PriceClass_100',
          DefaultCacheBehavior: {
            ViewerProtocolPolicy: 'redirect-to-https',
            Compress: true,
            AllowedMethods: ['GET', 'HEAD'],
            CachedMethods: ['GET', 'HEAD']
          }
        }
      });
    });

    test('creates Origin Access Control', () => {
      template.hasResourceProperties('AWS::CloudFront::OriginAccessControl', {
        OriginAccessControlConfig: {
          OriginAccessControlOriginType: 's3',
          SigningBehavior: 'always',
          SigningProtocol: 'sigv4'
        }
      });
    });

    test('includes cache behaviors for different content types', () => {
      template.hasResourceProperties('AWS::CloudFront::Distribution', {
        DistributionConfig: {
          CacheBehaviors: [
            {
              PathPattern: '/api/*',
              ViewerProtocolPolicy: 'https-only',
              Compress: true
            },
            {
              PathPattern: '/css/*',
              ViewerProtocolPolicy: 'https-only',
              Compress: true
            },
            {
              PathPattern: '/js/*',
              ViewerProtocolPolicy: 'https-only',
              Compress: true
            }
          ]
        }
      });
    });
  });

  describe('Lambda Function', () => {
    test('creates Lambda function with correct configuration', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        Runtime: 'nodejs18.x',
        Handler: 'index.handler',
        Timeout: 300,
        MemorySize: 256,
        Environment: {
          Variables: {
            BATCH_SIZE: '10',
            ENABLE_COST_OPTIMIZATION: 'true'
          }
        }
      });
    });

    test('grants Lambda CloudFront permissions', () => {
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: [
            {
              Effect: 'Allow',
              Action: [
                'cloudfront:CreateInvalidation',
                'cloudfront:GetInvalidation',
                'cloudfront:ListInvalidations'
              ],
              Resource: '*'
            }
          ]
        }
      });
    });
  });

  describe('DynamoDB Table', () => {
    test('creates DynamoDB table with correct configuration', () => {
      template.hasResourceProperties('AWS::DynamoDB::Table', {
        AttributeDefinitions: [
          {
            AttributeName: 'InvalidationId',
            AttributeType: 'S'
          },
          {
            AttributeName: 'Timestamp',
            AttributeType: 'S'
          }
        ],
        KeySchema: [
          {
            AttributeName: 'InvalidationId',
            KeyType: 'HASH'
          },
          {
            AttributeName: 'Timestamp',
            KeyType: 'RANGE'
          }
        ],
        BillingMode: 'PAY_PER_REQUEST',
        StreamSpecification: {
          StreamViewType: 'NEW_AND_OLD_IMAGES'
        },
        SSESpecification: {
          SSEEnabled: true
        },
        PointInTimeRecoverySpecification: {
          PointInTimeRecoveryEnabled: true
        },
        TimeToLiveSpecification: {
          AttributeName: 'TTL',
          Enabled: true
        }
      });
    });
  });

  describe('SQS Queue', () => {
    test('creates SQS queue with dead letter queue', () => {
      template.hasResourceProperties('AWS::SQS::Queue', {
        VisibilityTimeoutSeconds: 300,
        MessageRetentionPeriod: 1209600,
        ReceiveMessageWaitTimeSeconds: 20,
        KmsMasterKeyId: 'alias/aws/sqs'
      });
    });

    test('creates dead letter queue', () => {
      template.resourceCountIs('AWS::SQS::Queue', 2);
    });
  });

  describe('EventBridge', () => {
    test('creates custom event bus', () => {
      template.hasResourceProperties('AWS::Events::EventBus', {
        Name: 'test-invalidation-invalidation-events'
      });
    });

    test('creates event rules for S3 and deployment events', () => {
      template.hasResourceProperties('AWS::Events::Rule', {
        EventPattern: {
          source: ['aws.s3'],
          'detail-type': ['Object Created', 'Object Deleted']
        },
        State: 'ENABLED'
      });

      template.hasResourceProperties('AWS::Events::Rule', {
        EventPattern: {
          source: ['aws.codedeploy', 'custom.app'],
          'detail-type': ['Deployment State-change Notification', 'Application Deployment']
        },
        State: 'ENABLED'
      });
    });
  });

  describe('CloudWatch Monitoring', () => {
    test('creates CloudWatch dashboard', () => {
      template.hasResourceProperties('AWS::CloudWatch::Dashboard', {
        DashboardName: 'CloudFront-Invalidation-Dashboard'
      });
    });

    test('creates CloudWatch alarms', () => {
      // Check for Lambda error alarm
      template.hasResourceProperties('AWS::CloudWatch::Alarm', {
        ComparisonOperator: 'GreaterThanThreshold',
        EvaluationPeriods: 2,
        MetricName: 'Errors',
        Namespace: 'AWS/Lambda',
        Statistic: 'Sum',
        Threshold: 10
      });

      // Check for cache hit rate alarm
      template.hasResourceProperties('AWS::CloudWatch::Alarm', {
        ComparisonOperator: 'LessThanThreshold',
        EvaluationPeriods: 3,
        MetricName: 'CacheHitRate',
        Namespace: 'AWS/CloudFront',
        Statistic: 'Average',
        Threshold: 70
      });
    });
  });

  describe('IAM Roles and Policies', () => {
    test('creates Lambda execution role', () => {
      template.hasResourceProperties('AWS::IAM::Role', {
        AssumeRolePolicyDocument: {
          Statement: [
            {
              Action: 'sts:AssumeRole',
              Effect: 'Allow',
              Principal: {
                Service: 'lambda.amazonaws.com'
              }
            }
          ]
        }
      });
    });

    test('grants DynamoDB permissions to Lambda', () => {
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: [
            {
              Effect: 'Allow',
              Action: [
                'dynamodb:BatchGetItem',
                'dynamodb:GetRecords',
                'dynamodb:GetShardIterator',
                'dynamodb:Query',
                'dynamodb:GetItem',
                'dynamodb:Scan',
                'dynamodb:ConditionCheckItem',
                'dynamodb:BatchWriteItem',
                'dynamodb:PutItem',
                'dynamodb:UpdateItem',
                'dynamodb:DeleteItem',
                'dynamodb:DescribeTable'
              ]
            }
          ]
        }
      });
    });
  });

  describe('Stack Outputs', () => {
    test('creates all required outputs', () => {
      template.hasOutput('OriginBucketName', {});
      template.hasOutput('DistributionId', {});
      template.hasOutput('DistributionDomainName', {});
      template.hasOutput('InvalidationFunctionName', {});
      template.hasOutput('EventBusName', {});
      template.hasOutput('QueueUrl', {});
      template.hasOutput('TableName', {});
      template.hasOutput('DashboardUrl', {});
    });
  });

  describe('Resource Naming', () => {
    test('uses consistent resource naming convention', () => {
      // Check that resources use the project name prefix
      template.hasResourceProperties('AWS::S3::Bucket', {
        BucketName: 'test-invalidation-origin-content'
      });

      template.hasResourceProperties('AWS::DynamoDB::Table', {
        TableName: 'test-invalidation-invalidation-log'
      });

      template.hasResourceProperties('AWS::Events::EventBus', {
        Name: 'test-invalidation-invalidation-events'
      });
    });
  });

  describe('Security Configuration', () => {
    test('enables encryption for all storage resources', () => {
      // S3 bucket encryption
      template.hasResourceProperties('AWS::S3::Bucket', {
        BucketEncryption: {
          ServerSideEncryptionConfiguration: [{
            ServerSideEncryptionByDefault: {
              SSEAlgorithm: 'AES256'
            }
          }]
        }
      });

      // DynamoDB encryption
      template.hasResourceProperties('AWS::DynamoDB::Table', {
        SSESpecification: {
          SSEEnabled: true
        }
      });

      // SQS encryption
      template.hasResourceProperties('AWS::SQS::Queue', {
        KmsMasterKeyId: 'alias/aws/sqs'
      });
    });

    test('blocks public access to S3 bucket', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        PublicAccessBlockConfiguration: {
          BlockPublicAcls: true,
          BlockPublicPolicy: true,
          IgnorePublicAcls: true,
          RestrictPublicBuckets: true
        }
      });
    });
  });

  describe('Cost Optimization Features', () => {
    test('enables cost optimization by default', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        Environment: {
          Variables: {
            ENABLE_COST_OPTIMIZATION: 'true'
          }
        }
      });
    });

    test('configures appropriate batch sizes', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        Environment: {
          Variables: {
            BATCH_SIZE: '10'
          }
        }
      });
    });

    test('uses cost-effective CloudFront price class', () => {
      template.hasResourceProperties('AWS::CloudFront::Distribution', {
        DistributionConfig: {
          PriceClass: 'PriceClass_100'
        }
      });
    });
  });
});