import { Template, Match } from 'aws-cdk-lib/assertions';
import * as cdk from 'aws-cdk-lib';
import { S3InventoryStorageAnalyticsStack } from '../lib/s3-inventory-storage-analytics-stack';

describe('S3InventoryStorageAnalyticsStack', () => {
  let template: Template;
  let stack: S3InventoryStorageAnalyticsStack;

  beforeAll(() => {
    const app = new cdk.App();
    stack = new S3InventoryStorageAnalyticsStack(app, 'TestStack', {
      env: { account: '123456789012', region: 'us-east-1' },
    });
    template = Template.fromStack(stack);
  });

  describe('S3 Buckets', () => {
    test('creates source bucket with correct configuration', () => {
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
        VersioningConfiguration: {
          Status: 'Suspended',
        },
      });
    });

    test('creates destination bucket with correct configuration', () => {
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

    test('configures S3 inventory on source bucket', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        InventoryConfigurations: [
          {
            Id: 'daily-inventory-config',
            Enabled: true,
            IncludedObjectVersions: 'Current',
            ScheduleFrequency: Match.anyValue(),
            OptionalFields: [
              'Size',
              'LastModifiedDate',
              'StorageClass',
              'ETag',
              'ReplicationStatus',
              'EncryptionStatus',
            ],
            Destination: {
              BucketArn: Match.anyValue(),
              Format: 'CSV',
              Prefix: 'inventory-reports/',
              BucketAccountId: '123456789012',
            },
          },
        ],
      });
    });

    test('configures storage class analysis on source bucket', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        AnalyticsConfigurations: [
          {
            Id: 'storage-class-analysis',
            Prefix: Match.anyValue(),
            StorageClassAnalysis: {
              DataExport: {
                OutputSchemaVersion: 'V_1',
                Destination: {
                  Format: 'CSV',
                  BucketArn: Match.anyValue(),
                  Prefix: 'analytics-reports/',
                  BucketAccountId: '123456789012',
                },
              },
            },
          },
        ],
      });
    });
  });

  describe('AWS Glue Database', () => {
    test('creates Glue database for Athena queries', () => {
      template.hasResourceProperties('AWS::Glue::Database', {
        CatalogId: '123456789012',
        DatabaseInput: {
          Name: 's3-inventory-db',
          Description: 'Database for S3 inventory analysis',
        },
      });
    });
  });

  describe('Amazon Athena WorkGroup', () => {
    test('creates Athena WorkGroup with correct configuration', () => {
      template.hasResourceProperties('AWS::Athena::WorkGroup', {
        Name: 'storage-analytics-workgroup',
        Description: 'WorkGroup for S3 storage analytics queries',
        State: 'ENABLED',
        WorkGroupConfiguration: {
          ResultConfiguration: {
            OutputLocation: Match.anyValue(),
            EncryptionConfiguration: {
              EncryptionOption: 'SSE_S3',
            },
          },
          EnforceWorkGroupConfiguration: true,
          PublishCloudWatchMetrics: true,
          BytesScannedCutoffPerQuery: 1000000000,
        },
      });
    });
  });

  describe('Lambda Function', () => {
    test('creates Lambda function with correct configuration', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        Runtime: 'python3.11',
        Handler: 'index.lambda_handler',
        Timeout: 300,
        MemorySize: 256,
        Description: 'Automated S3 storage analytics and reporting function',
        Environment: {
          Variables: {
            ATHENA_DATABASE: Match.anyValue(),
            ATHENA_TABLE: 'inventory_table',
            DEST_BUCKET: Match.anyValue(),
            WORKGROUP_NAME: Match.anyValue(),
          },
        },
      });
    });

    test('creates IAM role for Lambda function', () => {
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
        Description: 'IAM role for S3 storage analytics Lambda function',
        ManagedPolicyArns: [
          {
            'Fn::Join': [
              '',
              [
                'arn:',
                { Ref: 'AWS::Partition' },
                ':iam::aws:policy/service-role/AWSLambdaBasicExecutionRole',
              ],
            ],
          },
        ],
      });
    });

    test('creates inline policy for Lambda function', () => {
      template.hasResourceProperties('AWS::IAM::Role', {
        Policies: [
          {
            PolicyName: 'StorageAnalyticsPolicy',
            PolicyDocument: {
              Statement: [
                {
                  Effect: 'Allow',
                  Action: [
                    'athena:StartQueryExecution',
                    'athena:GetQueryExecution',
                    'athena:GetQueryResults',
                    'athena:GetWorkGroup',
                  ],
                  Resource: Match.anyValue(),
                },
                {
                  Effect: 'Allow',
                  Action: [
                    's3:GetObject',
                    's3:PutObject',
                    's3:ListBucket',
                  ],
                  Resource: Match.anyValue(),
                },
                {
                  Effect: 'Allow',
                  Action: [
                    'glue:GetDatabase',
                    'glue:GetTable',
                    'glue:GetPartitions',
                  ],
                  Resource: Match.anyValue(),
                },
              ],
            },
          },
        ],
      });
    });
  });

  describe('EventBridge Rule', () => {
    test('creates EventBridge rule for daily scheduling', () => {
      template.hasResourceProperties('AWS::Events::Rule', {
        Name: 'storage-analytics-daily-schedule',
        Description: 'Daily schedule for automated S3 storage analytics reporting',
        ScheduleExpression: 'rate(1 day)',
        State: 'ENABLED',
        Targets: [
          {
            Arn: Match.anyValue(),
            Id: 'Target0',
          },
        ],
      });
    });
  });

  describe('CloudWatch Dashboard', () => {
    test('creates CloudWatch dashboard', () => {
      template.hasResourceProperties('AWS::CloudWatch::Dashboard', {
        DashboardName: Match.stringLikeRegexp('S3-Storage-Analytics-.*'),
        DashboardBody: Match.anyValue(),
      });
    });
  });

  describe('Stack Outputs', () => {
    test('exports all required outputs', () => {
      const outputs = template.findOutputs('*');
      
      expect(outputs).toHaveProperty('SourceBucketName');
      expect(outputs).toHaveProperty('DestinationBucketName');
      expect(outputs).toHaveProperty('GlueDatabaseName');
      expect(outputs).toHaveProperty('AthenaWorkGroupName');
      expect(outputs).toHaveProperty('AnalyticsFunctionName');
      expect(outputs).toHaveProperty('DashboardURL');
      expect(outputs).toHaveProperty('SampleDataCommands');
    });
  });

  describe('Resource Count', () => {
    test('creates expected number of resources', () => {
      const resources = template.findResources('*');
      
      // Verify we have the minimum expected resources
      expect(Object.keys(resources).length).toBeGreaterThanOrEqual(10);
    });
  });

  describe('Security Configuration', () => {
    test('enforces SSL on S3 buckets', () => {
      template.hasResourceProperties('AWS::S3::BucketPolicy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Effect: 'Deny',
              Condition: {
                Bool: {
                  'aws:SecureTransport': 'false',
                },
              },
            }),
          ]),
        },
      });
    });

    test('blocks public access on all S3 buckets', () => {
      const buckets = template.findResources('AWS::S3::Bucket');
      
      Object.values(buckets).forEach((bucket: any) => {
        expect(bucket.Properties).toHaveProperty('PublicAccessBlockConfiguration');
        expect(bucket.Properties.PublicAccessBlockConfiguration).toMatchObject({
          BlockPublicAcls: true,
          BlockPublicPolicy: true,
          IgnorePublicAcls: true,
          RestrictPublicBuckets: true,
        });
      });
    });
  });
});