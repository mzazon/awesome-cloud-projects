import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { AutomatedFileLifecycleManagementStack } from '../lib/automated-file-lifecycle-management-stack';

describe('AutomatedFileLifecycleManagementStack', () => {
  let app: cdk.App;
  let stack: AutomatedFileLifecycleManagementStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new AutomatedFileLifecycleManagementStack(app, 'TestStack', {
      fsxConfiguration: {
        storageCapacity: 64,
        throughputCapacity: 64,
        cacheSize: 128,
      },
      monitoring: {
        cacheHitRatioThreshold: 70,
        storageUtilizationThreshold: 85,
        networkUtilizationThreshold: 90,
      },
      automation: {
        lifecyclePolicySchedule: 'rate(1 hour)',
        costReportingSchedule: 'rate(24 hours)',
      },
      tags: {
        Project: 'FSx-Lifecycle-Management',
        Environment: 'test',
        Owner: 'test-user',
        CostCenter: 'testing',
      },
    });
    template = Template.fromStack(stack);
  });

  describe('FSx File System', () => {
    test('creates FSx file system with correct configuration', () => {
      template.hasResourceProperties('AWS::FSx::FileSystem', {
        FileSystemType: 'OpenZFS',
        StorageCapacity: 64,
        StorageType: 'SSD',
        OpenZFSConfiguration: {
          ThroughputCapacity: 64,
          ReadCacheConfig: {
            SizeGiB: 128,
          },
          DeploymentType: 'SINGLE_AZ_1',
          AutomaticBackupRetentionDays: 7,
        },
      });
    });

    test('applies correct tags to FSx file system', () => {
      template.hasResourceProperties('AWS::FSx::FileSystem', {
        Tags: Match.arrayWith([
          {
            Key: 'Name',
            Value: Match.stringLikeRegexp('fsx-lifecycle-.*'),
          },
        ]),
      });
    });
  });

  describe('Lambda Functions', () => {
    test('creates lifecycle policy Lambda function', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        FunctionName: Match.stringLikeRegexp('fsx-lifecycle-policy-.*'),
        Runtime: 'python3.9',
        Handler: 'index.lambda_handler',
        Timeout: 60,
        MemorySize: 256,
      });
    });

    test('creates cost reporting Lambda function', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        FunctionName: Match.stringLikeRegexp('fsx-cost-reporting-.*'),
        Runtime: 'python3.9',
        Handler: 'index.lambda_handler',
        Timeout: 120,
        MemorySize: 512,
      });
    });

    test('creates alert handler Lambda function', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        FunctionName: Match.stringLikeRegexp('fsx-alert-handler-.*'),
        Runtime: 'python3.9',
        Handler: 'index.lambda_handler',
        Timeout: 30,
        MemorySize: 256,
      });
    });

    test('configures correct environment variables for lifecycle function', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        FunctionName: Match.stringLikeRegexp('fsx-lifecycle-policy-.*'),
        Environment: {
          Variables: {
            SNS_TOPIC_ARN: Match.anyValue(),
          },
        },
      });
    });

    test('configures correct environment variables for cost reporting function', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        FunctionName: Match.stringLikeRegexp('fsx-cost-reporting-.*'),
        Environment: {
          Variables: {
            S3_BUCKET_NAME: Match.anyValue(),
          },
        },
      });
    });
  });

  describe('IAM Roles and Policies', () => {
    test('creates Lambda execution role with basic permissions', () => {
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
        ManagedPolicyArns: Match.arrayWith([
          'arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole',
        ]),
      });
    });

    test('creates custom policy for FSx and CloudWatch access', () => {
      template.hasResourceProperties('AWS::IAM::Role', {
        Policies: Match.arrayWith([
          {
            PolicyDocument: {
              Statement: Match.arrayWith([
                {
                  Effect: 'Allow',
                  Action: Match.arrayWith([
                    'fsx:DescribeFileSystems',
                    'fsx:DescribeVolumes',
                    'cloudwatch:GetMetricStatistics',
                    'cloudwatch:PutMetricData',
                    'sns:Publish',
                    's3:PutObject',
                    's3:GetObject',
                  ]),
                  Resource: '*',
                },
              ]),
            },
          },
        ]),
      });
    });
  });

  describe('EventBridge Rules', () => {
    test('creates lifecycle policy schedule rule', () => {
      template.hasResourceProperties('AWS::Events::Rule', {
        ScheduleExpression: 'rate(1 hour)',
        Description: 'Trigger lifecycle policy analysis',
        State: 'ENABLED',
      });
    });

    test('creates cost reporting schedule rule', () => {
      template.hasResourceProperties('AWS::Events::Rule', {
        ScheduleExpression: 'rate(24 hours)',
        Description: 'Generate cost reports',
        State: 'ENABLED',
      });
    });

    test('configures correct targets for EventBridge rules', () => {
      template.hasResourceProperties('AWS::Events::Rule', {
        Targets: Match.arrayWith([
          {
            Arn: Match.anyValue(),
            Id: Match.anyValue(),
          },
        ]),
      });
    });
  });

  describe('CloudWatch Alarms', () => {
    test('creates cache hit ratio alarm', () => {
      template.hasResourceProperties('AWS::CloudWatch::Alarm', {
        AlarmName: Match.stringLikeRegexp('FSx-Low-Cache-Hit-Ratio-.*'),
        AlarmDescription: 'Alert when FSx cache hit ratio is below threshold',
        MetricName: 'FileServerCacheHitRatio',
        Namespace: 'AWS/FSx',
        Threshold: 70,
        ComparisonOperator: 'LessThanThreshold',
        EvaluationPeriods: 2,
      });
    });

    test('creates storage utilization alarm', () => {
      template.hasResourceProperties('AWS::CloudWatch::Alarm', {
        AlarmName: Match.stringLikeRegexp('FSx-High-Storage-Utilization-.*'),
        AlarmDescription: 'Alert when FSx storage utilization exceeds threshold',
        MetricName: 'StorageUtilization',
        Namespace: 'AWS/FSx',
        Threshold: 85,
        ComparisonOperator: 'GreaterThanThreshold',
        EvaluationPeriods: 2,
      });
    });

    test('creates network utilization alarm', () => {
      template.hasResourceProperties('AWS::CloudWatch::Alarm', {
        AlarmName: Match.stringLikeRegexp('FSx-High-Network-Utilization-.*'),
        AlarmDescription: 'Alert when FSx network utilization exceeds threshold',
        MetricName: 'NetworkThroughputUtilization',
        Namespace: 'AWS/FSx',
        Threshold: 90,
        ComparisonOperator: 'GreaterThanThreshold',
        EvaluationPeriods: 2,
      });
    });

    test('configures SNS actions for alarms', () => {
      template.hasResourceProperties('AWS::CloudWatch::Alarm', {
        AlarmActions: Match.arrayWith([Match.anyValue()]),
      });
    });
  });

  describe('SNS Topic and Subscriptions', () => {
    test('creates SNS topic with correct configuration', () => {
      template.hasResourceProperties('AWS::SNS::Topic', {
        TopicName: Match.stringLikeRegexp('fsx-lifecycle-alerts-.*'),
        DisplayName: 'FSx Lifecycle Management Alerts',
      });
    });

    test('creates Lambda subscription to SNS topic', () => {
      template.hasResourceProperties('AWS::SNS::Subscription', {
        Protocol: 'lambda',
        TopicArn: Match.anyValue(),
        Endpoint: Match.anyValue(),
      });
    });
  });

  describe('S3 Bucket', () => {
    test('creates S3 bucket for reports with correct configuration', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        BucketName: Match.stringLikeRegexp('fsx-lifecycle-reports-.*'),
        VersioningConfiguration: {
          Status: 'Enabled',
        },
        LifecycleConfiguration: {
          Rules: Match.arrayWith([
            {
              Id: 'DeleteOldReports',
              Status: 'Enabled',
              ExpirationInDays: 90,
              NoncurrentVersionExpirationInDays: 30,
            },
          ]),
        },
        BucketEncryption: {
          ServerSideEncryptionConfiguration: Match.anyValue(),
        },
      });
    });

    test('configures bucket with block public access', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        PublicAccessBlockConfiguration: {
          BlockPublicAcls: true,
          BlockPublicPolicy: true,
          IgnorePublicAcls: true,
          RestrictPublicBuckets: true,
        },
      });
    });
  });

  describe('Security Group', () => {
    test('creates security group for FSx', () => {
      template.hasResourceProperties('AWS::EC2::SecurityGroup', {
        GroupDescription: 'Security group for FSx file system',
        SecurityGroupIngress: Match.arrayWith([
          {
            IpProtocol: 'tcp',
            FromPort: 2049,
            ToPort: 2049,
          },
          {
            IpProtocol: 'tcp',
            FromPort: 22,
            ToPort: 22,
            CidrIp: '0.0.0.0/0',
          },
        ]),
      });
    });
  });

  describe('CloudWatch Dashboard', () => {
    test('creates CloudWatch dashboard', () => {
      template.hasResourceProperties('AWS::CloudWatch::Dashboard', {
        DashboardName: Match.stringLikeRegexp('FSx-Lifecycle-Management-.*'),
        DashboardBody: Match.anyValue(),
      });
    });
  });

  describe('Stack Outputs', () => {
    test('creates all required outputs', () => {
      const outputs = template.findOutputs('*');
      
      expect(outputs).toHaveProperty('FsxFileSystemId');
      expect(outputs).toHaveProperty('FsxFileSystemDnsName');
      expect(outputs).toHaveProperty('LifecyclePolicyFunctionArn');
      expect(outputs).toHaveProperty('CostReportingFunctionArn');
      expect(outputs).toHaveProperty('AlertHandlerFunctionArn');
      expect(outputs).toHaveProperty('SnsTopicArn');
      expect(outputs).toHaveProperty('ReportsBucketName');
      expect(outputs).toHaveProperty('DashboardUrl');
    });
  });

  describe('Resource Count Validation', () => {
    test('creates expected number of resources', () => {
      const resources = template.toJSON().Resources;
      
      // Count specific resource types
      const lambdaFunctions = Object.values(resources).filter(
        (r: any) => r.Type === 'AWS::Lambda::Function'
      );
      const eventRules = Object.values(resources).filter(
        (r: any) => r.Type === 'AWS::Events::Rule'
      );
      const alarms = Object.values(resources).filter(
        (r: any) => r.Type === 'AWS::CloudWatch::Alarm'
      );
      
      expect(lambdaFunctions).toHaveLength(3); // lifecycle, cost-reporting, alert-handler
      expect(eventRules).toHaveLength(2); // lifecycle schedule, cost reporting schedule
      expect(alarms).toHaveLength(3); // cache hit ratio, storage utilization, network utilization
    });
  });

  describe('Custom Configuration', () => {
    test('accepts custom FSx configuration', () => {
      const customApp = new cdk.App();
      const customStack = new AutomatedFileLifecycleManagementStack(customApp, 'CustomStack', {
        fsxConfiguration: {
          storageCapacity: 128,
          throughputCapacity: 128,
          cacheSize: 256,
        },
        monitoring: {
          cacheHitRatioThreshold: 80,
          storageUtilizationThreshold: 90,
          networkUtilizationThreshold: 95,
        },
        automation: {
          lifecyclePolicySchedule: 'rate(30 minutes)',
          costReportingSchedule: 'rate(12 hours)',
        },
        tags: {
          Project: 'Custom-FSx',
          Environment: 'production',
          Owner: 'custom-user',
          CostCenter: 'custom-billing',
        },
      });
      
      const customTemplate = Template.fromStack(customStack);
      
      customTemplate.hasResourceProperties('AWS::FSx::FileSystem', {
        StorageCapacity: 128,
        OpenZFSConfiguration: {
          ThroughputCapacity: 128,
          ReadCacheConfig: {
            SizeGiB: 256,
          },
        },
      });
      
      customTemplate.hasResourceProperties('AWS::CloudWatch::Alarm', {
        Threshold: 80,
        MetricName: 'FileServerCacheHitRatio',
      });
      
      customTemplate.hasResourceProperties('AWS::Events::Rule', {
        ScheduleExpression: 'rate(30 minutes)',
      });
    });
  });
});