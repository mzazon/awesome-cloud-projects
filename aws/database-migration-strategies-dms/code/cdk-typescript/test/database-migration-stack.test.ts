import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { DatabaseMigrationStack } from '../lib/database-migration-stack';

describe('DatabaseMigrationStack', () => {
  let app: cdk.App;
  let stack: DatabaseMigrationStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new DatabaseMigrationStack(app, 'TestDatabaseMigrationStack', {
      env: {
        account: '123456789012',
        region: 'us-east-1',
      },
    });
    template = Template.fromStack(stack);
  });

  test('DMS Replication Instance is created with correct configuration', () => {
    template.hasResourceProperties('AWS::DMS::ReplicationInstance', {
      ReplicationInstanceClass: 'dms.t3.medium',
      AllocatedStorage: 100,
      MultiAZ: true,
      EngineVersion: '3.5.2',
      PubliclyAccessible: false,
    });
  });

  test('DMS Subnet Group is created', () => {
    template.hasResourceProperties('AWS::DMS::ReplicationSubnetGroup', {
      ReplicationSubnetGroupDescription: 'DMS subnet group for database migration',
    });
  });

  test('Source and Target endpoints are created', () => {
    // Source endpoint
    template.hasResourceProperties('AWS::DMS::Endpoint', {
      EndpointType: 'source',
      EngineName: 'mysql',
      Port: 3306,
      SslMode: 'require',
    });

    // Target endpoint
    template.hasResourceProperties('AWS::DMS::Endpoint', {
      EndpointType: 'target',
      EngineName: 'mysql',
      Port: 3306,
      SslMode: 'require',
    });
  });

  test('Migration tasks are created with correct types', () => {
    // Full load and CDC task
    template.hasResourceProperties('AWS::DMS::ReplicationTask', {
      MigrationType: 'full-load-and-cdc',
    });

    // CDC only task
    template.hasResourceProperties('AWS::DMS::ReplicationTask', {
      MigrationType: 'cdc',
    });
  });

  test('S3 bucket for logging is created with security settings', () => {
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
        Status: 'Enabled',
      },
    });
  });

  test('CloudWatch Log Group is created', () => {
    template.hasResourceProperties('AWS::Logs::LogGroup', {
      RetentionInDays: 30,
    });
  });

  test('SNS Topic for alerting is created', () => {
    template.hasResourceProperties('AWS::SNS::Topic', {
      DisplayName: 'DMS Migration Alerts',
    });
  });

  test('CloudWatch Alarms are created for monitoring', () => {
    // Migration task failure alarm
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      AlarmDescription: 'Monitor DMS migration task failures',
      MetricName: 'ReplicationTasksState',
      Namespace: 'AWS/DMS',
      Statistic: 'Average',
      ComparisonOperator: 'GreaterThanOrEqualToThreshold',
      Threshold: 1,
    });

    // CDC latency alarm
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      AlarmDescription: 'Monitor DMS CDC latency',
      MetricName: 'CDCLatencyTarget',
      Namespace: 'AWS/DMS',
      ComparisonOperator: 'GreaterThanThreshold',
      Threshold: 300,
    });
  });

  test('Security Group allows database connections', () => {
    template.hasResourceProperties('AWS::EC2::SecurityGroup', {
      GroupDescription: 'Security group for DMS replication instance',
      SecurityGroupIngress: [
        {
          IpProtocol: 'tcp',
          FromPort: 3306,
          ToPort: 3306,
          Description: 'Allow MySQL connections from VPC',
        },
        {
          IpProtocol: 'tcp',
          FromPort: 5432,
          ToPort: 5432,
          Description: 'Allow PostgreSQL connections from VPC',
        },
      ],
    });
  });

  test('IAM Role for DMS is created with appropriate policies', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Effect: 'Allow',
            Principal: {
              Service: 'dms.amazonaws.com',
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
              ':iam::aws:policy/service-role/AmazonDMSVPCManagementRole',
            ],
          ],
        },
      ],
    });
  });

  test('Stack outputs are defined', () => {
    template.hasOutput('ReplicationInstanceIdentifier', {});
    template.hasOutput('SourceEndpointIdentifier', {});
    template.hasOutput('TargetEndpointIdentifier', {});
    template.hasOutput('MigrationLoggingBucket', {});
    template.hasOutput('CloudWatchLogGroup', {});
    template.hasOutput('AlertingTopicArn', {});
  });

  test('Stack has required tags', () => {
    template.hasResource('AWS::DMS::ReplicationInstance', {
      Properties: {
        Tags: [
          {
            Key: 'Name',
            Value: 'dms-migration-instance',
          },
          {
            Key: 'Environment',
            Value: 'migration',
          },
        ],
      },
    });
  });

  test('Stack can be customized with props', () => {
    const customStack = new DatabaseMigrationStack(app, 'CustomStack', {
      env: {
        account: '123456789012',
        region: 'us-west-2',
      },
      replicationInstanceClass: 'dms.r5.large',
      allocatedStorage: 200,
      multiAz: false,
      sourceEndpointConfig: {
        engineName: 'postgresql',
        serverName: 'custom-source.example.com',
        port: 5432,
        databaseName: 'customdb',
        username: 'customuser',
        password: 'custompass',
      },
    });

    const customTemplate = Template.fromStack(customStack);

    customTemplate.hasResourceProperties('AWS::DMS::ReplicationInstance', {
      ReplicationInstanceClass: 'dms.r5.large',
      AllocatedStorage: 200,
      MultiAZ: false,
    });

    customTemplate.hasResourceProperties('AWS::DMS::Endpoint', {
      EndpointType: 'source',
      EngineName: 'postgresql',
      ServerName: 'custom-source.example.com',
      Port: 5432,
      DatabaseName: 'customdb',
      Username: 'customuser',
    });
  });
});