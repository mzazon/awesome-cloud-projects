import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { DatabasePerformanceMonitoringStack } from '../lib/database-performance-monitoring-stack';

describe('DatabasePerformanceMonitoringStack', () => {
  let app: cdk.App;
  let stack: DatabasePerformanceMonitoringStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new DatabasePerformanceMonitoringStack(app, 'TestStack', {
      stackProps: {
        dbInstanceClass: 'db.t3.small',
        dbEngine: 'mysql',
        dbEngineVersion: '8.0.35',
        allocatedStorage: 20,
        performanceInsightsRetentionPeriod: 7,
        monitoringInterval: 60,
        lambdaMemorySize: 512,
        lambdaTimeout: 300,
        analysisSchedule: 'rate(15 minutes)',
        createDashboard: true,
        enableAnomalyDetection: true,
        enableCloudWatchLogs: true,
        enableEncryption: true,
        tags: {
          Environment: 'test',
          Project: 'DatabasePerformanceMonitoring',
        },
      },
    });
    template = Template.fromStack(stack);
  });

  test('creates VPC with correct configuration', () => {
    template.hasResourceProperties('AWS::EC2::VPC', {
      CidrBlock: '10.0.0.0/16',
      EnableDnsHostnames: true,
      EnableDnsSupport: true,
    });
  });

  test('creates RDS instance with Performance Insights enabled', () => {
    template.hasResourceProperties('AWS::RDS::DBInstance', {
      DBInstanceClass: 'db.t3.small',
      Engine: 'mysql',
      EngineVersion: '8.0.35',
      AllocatedStorage: '20',
      EnablePerformanceInsights: true,
      PerformanceInsightsRetentionPeriod: 7,
      MonitoringInterval: 60,
      PubliclyAccessible: false,
      StorageEncrypted: true,
    });
  });

  test('creates Lambda function with correct configuration', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      Runtime: 'python3.9',
      Handler: 'index.lambda_handler',
      Timeout: 300,
      MemorySize: 512,
    });
  });

  test('creates S3 bucket for reports', () => {
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

  test('creates SNS topic for alerts', () => {
    template.hasResourceProperties('AWS::SNS::Topic', {
      DisplayName: 'Database Performance Alerts',
    });
  });

  test('creates CloudWatch alarms', () => {
    // Test for high database connections alarm
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      MetricName: 'DatabaseConnections',
      Namespace: 'AWS/RDS',
      Statistic: 'Average',
      Threshold: 80,
      ComparisonOperator: 'GreaterThanThreshold',
      EvaluationPeriods: 2,
    });

    // Test for high CPU utilization alarm
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      MetricName: 'CPUUtilization',
      Namespace: 'AWS/RDS',
      Statistic: 'Average',
      Threshold: 75,
      ComparisonOperator: 'GreaterThanThreshold',
      EvaluationPeriods: 2,
    });

    // Test for custom metrics alarms
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      MetricName: 'HighLoadEvents',
      Namespace: 'RDS/PerformanceInsights',
      Statistic: 'Sum',
      Threshold: 5,
      ComparisonOperator: 'GreaterThanThreshold',
      EvaluationPeriods: 2,
    });
  });

  test('creates EventBridge rule for automated analysis', () => {
    template.hasResourceProperties('AWS::Events::Rule', {
      ScheduleExpression: 'rate(15 minutes)',
      State: 'ENABLED',
    });
  });

  test('creates CloudWatch dashboard', () => {
    template.hasResourceProperties('AWS::CloudWatch::Dashboard', {
      DashboardBody: cdk.Match.stringLikeRegexp('.*RDS Core Performance Metrics.*'),
    });
  });

  test('creates anomaly detectors', () => {
    template.hasResourceProperties('AWS::CloudWatch::AnomalyDetector', {
      MetricName: 'DatabaseConnections',
      Namespace: 'AWS/RDS',
      Stat: 'Average',
    });

    template.hasResourceProperties('AWS::CloudWatch::AnomalyDetector', {
      MetricName: 'CPUUtilization',
      Namespace: 'AWS/RDS',
      Stat: 'Average',
    });
  });

  test('creates IAM roles with correct policies', () => {
    // Test Lambda execution role
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Action: 'sts:AssumeRole',
            Effect: 'Allow',
            Principal: {
              Service: 'lambda.amazonaws.com',
            },
          },
        ],
      },
    });

    // Test RDS monitoring role
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Action: 'sts:AssumeRole',
            Effect: 'Allow',
            Principal: {
              Service: 'monitoring.rds.amazonaws.com',
            },
          },
        ],
      },
    });
  });

  test('creates security groups with correct rules', () => {
    template.hasResourceProperties('AWS::EC2::SecurityGroup', {
      GroupDescription: 'Security group for RDS Performance Insights database',
      SecurityGroupIngress: [
        {
          IpProtocol: 'tcp',
          FromPort: 3306,
          ToPort: 3306,
          CidrIp: '10.0.0.0/16',
        },
      ],
      SecurityGroupEgress: [],
    });
  });

  test('creates database subnet group', () => {
    template.hasResourceProperties('AWS::RDS::DBSubnetGroup', {
      DBSubnetGroupDescription: 'Subnet group for Performance Insights database',
    });
  });

  test('creates Secrets Manager secret for database credentials', () => {
    template.hasResourceProperties('AWS::SecretsManager::Secret', {
      Description: 'Database credentials for Performance Insights monitoring',
      GenerateSecretString: {
        SecretStringTemplate: '{"username":"admin"}',
        GenerateStringKey: 'password',
        ExcludeCharacters: '"@/\\',
        RequireEachIncludedType: true,
        IncludeSpace: false,
      },
    });
  });

  test('has correct number of resources', () => {
    const resources = template.findResources('*');
    
    // Verify we have the expected number of key resource types
    expect(Object.keys(resources).length).toBeGreaterThan(30);
    
    // Check specific resource counts
    expect(template.findResources('AWS::RDS::DBInstance')).toHaveProperty('length', 1);
    expect(template.findResources('AWS::Lambda::Function')).toHaveProperty('length', 1);
    expect(template.findResources('AWS::S3::Bucket')).toHaveProperty('length', 1);
    expect(template.findResources('AWS::SNS::Topic')).toHaveProperty('length', 1);
    expect(template.findResources('AWS::CloudWatch::Dashboard')).toHaveProperty('length', 1);
    expect(Object.keys(template.findResources('AWS::CloudWatch::Alarm')).length).toBeGreaterThanOrEqual(4);
  });

  test('creates stack outputs', () => {
    template.hasOutput('DatabaseEndpoint', {});
    template.hasOutput('DatabaseResourceId', {});
    template.hasOutput('ReportsBucketName', {});
    template.hasOutput('SNSTopicArn', {});
    template.hasOutput('LambdaFunctionName', {});
    template.hasOutput('PerformanceInsightsUrl', {});
  });

  test('applies tags correctly', () => {
    // Check that tags are applied to key resources
    template.hasResourceProperties('AWS::RDS::DBInstance', {
      Tags: cdk.Match.arrayWith([
        {
          Key: 'Environment',
          Value: 'test',
        },
        {
          Key: 'Project',
          Value: 'DatabasePerformanceMonitoring',
        },
      ]),
    });
  });

  test('configures encryption correctly', () => {
    // Test RDS encryption
    template.hasResourceProperties('AWS::RDS::DBInstance', {
      StorageEncrypted: true,
    });

    // Test S3 encryption
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
});