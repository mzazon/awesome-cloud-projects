import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { RedshiftDataWarehouseStack } from '../lib/redshift-data-warehouse-stack';

describe('RedshiftDataWarehouseStack', () => {
  let app: cdk.App;
  let stack: RedshiftDataWarehouseStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new RedshiftDataWarehouseStack(app, 'TestStack', {
      env: { account: '123456789012', region: 'us-east-1' },
    });
    template = Template.fromStack(stack);
  });

  test('Creates Redshift Serverless Namespace', () => {
    template.hasResourceProperties('AWS::RedshiftServerless::Namespace', {
      NamespaceName: expect.stringMatching(/^data-warehouse-ns-/),
      AdminUsername: 'awsuser',
      DbName: 'sampledb',
      KmsKeyId: 'alias/aws/redshift',
    });
  });

  test('Creates Redshift Serverless Workgroup', () => {
    template.hasResourceProperties('AWS::RedshiftServerless::Workgroup', {
      WorkgroupName: expect.stringMatching(/^data-warehouse-wg-/),
      BaseCapacity: 128,
      PubliclyAccessible: true,
    });
  });

  test('Creates S3 bucket with proper configuration', () => {
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
      VersioningConfiguration: {
        Status: 'Enabled',
      },
      PublicAccessBlockConfiguration: {
        BlockPublicAcls: true,
        BlockPublicPolicy: true,
        IgnorePublicAcls: true,
        RestrictPublicBuckets: true,
      },
    });
  });

  test('Creates IAM role for Redshift', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Effect: 'Allow',
            Principal: {
              Service: 'redshift.amazonaws.com',
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
              { Ref: 'AWS::Partition' },
              ':iam::aws:policy/AmazonS3ReadOnlyAccess',
            ],
          ],
        },
      ],
    });
  });

  test('Creates CloudWatch dashboard', () => {
    template.hasResourceProperties('AWS::CloudWatch::Dashboard', {
      DashboardName: expect.stringMatching(/^RedshiftServerless-/),
    });
  });

  test('Creates CloudWatch log group', () => {
    template.hasResourceProperties('AWS::Logs::LogGroup', {
      LogGroupName: expect.stringMatching(/^\/aws\/redshift\/serverless\//),
      RetentionInDays: 30,
    });
  });

  test('Has required outputs', () => {
    template.hasOutput('DataBucketName', {});
    template.hasOutput('RedshiftNamespace', {});
    template.hasOutput('RedshiftWorkgroup', {});
    template.hasOutput('RedshiftEndpoint', {});
    template.hasOutput('RedshiftRoleArn', {});
    template.hasOutput('DatabaseName', {});
    template.hasOutput('AdminUsername', {});
  });

  test('Workgroup depends on namespace', () => {
    template.hasResource('AWS::RedshiftServerless::Workgroup', {
      DependsOn: [expect.stringMatching(/^Namespace/)],
    });
  });

  test('S3 bucket has lifecycle rules', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      LifecycleConfiguration: {
        Rules: [
          {
            Id: 'DataLifecycleRule',
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
          },
        ],
      },
    });
  });

  test('Creates custom stack tags', () => {
    // Test that custom tags are applied to resources
    const stackTags = stack.tags.renderTags();
    expect(stackTags).toEqual(
      expect.objectContaining({
        Project: 'DataWarehouse',
        Environment: 'development',
        Owner: 'data-team',
        CostCenter: 'analytics',
      })
    );
  });

  test('Environment-specific configuration', () => {
    // Test production environment configuration
    const prodStack = new RedshiftDataWarehouseStack(app, 'ProdStack', {
      env: { account: '123456789012', region: 'us-east-1' },
      environment: 'production',
    });

    const prodTemplate = Template.fromStack(prodStack);

    // S3 bucket should have retention policy in production
    prodTemplate.hasResourceProperties('AWS::S3::Bucket', {
      DeletionPolicy: 'Retain',
    });
  });

  test('Custom base capacity configuration', () => {
    const customStack = new RedshiftDataWarehouseStack(app, 'CustomStack', {
      env: { account: '123456789012', region: 'us-east-1' },
      baseCapacity: 256,
    });

    const customTemplate = Template.fromStack(customStack);

    customTemplate.hasResourceProperties('AWS::RedshiftServerless::Workgroup', {
      BaseCapacity: 256,
    });
  });

  test('Redshift role has CloudWatch Logs permissions', () => {
    template.hasResourceProperties('AWS::IAM::Policy', {
      PolicyDocument: {
        Statement: expect.arrayContaining([
          expect.objectContaining({
            Effect: 'Allow',
            Action: [
              'logs:CreateLogGroup',
              'logs:CreateLogStream',
              'logs:PutLogEvents',
              'logs:DescribeLogGroups',
              'logs:DescribeLogStreams',
            ],
            Resource: expect.stringMatching(/arn:aws:logs:.*:.*:log-group:\/aws\/redshift\/\*/),
          }),
        ]),
      },
    });
  });
});