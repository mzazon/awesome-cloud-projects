import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { DatabaseMonitoringStack } from '../lib/database-monitoring-stack';

describe('DatabaseMonitoringStack', () => {
  let app: cdk.App;
  let stack: DatabaseMonitoringStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new DatabaseMonitoringStack(app, 'TestStack', {
      alertEmail: 'test@example.com',
      environment: 'test',
    });
    template = Template.fromStack(stack);
  });

  test('Creates VPC with correct configuration', () => {
    template.hasResourceProperties('AWS::EC2::VPC', {
      CidrBlock: '10.0.0.0/16',
      EnableDnsHostnames: true,
      EnableDnsSupport: true,
    });
  });

  test('Creates RDS instance with correct engine', () => {
    template.hasResourceProperties('AWS::RDS::DBInstance', {
      Engine: 'mysql',
      EngineVersion: '8.0.35',
      DBInstanceClass: 'db.t3.micro',
      AllocatedStorage: '20',
      StorageEncrypted: true,
    });
  });

  test('Creates SNS topic for database alerts', () => {
    template.hasResourceProperties('AWS::SNS::Topic', {
      DisplayName: 'Database Monitoring Alerts',
    });
  });

  test('Creates email subscription for SNS topic', () => {
    template.hasResourceProperties('AWS::SNS::Subscription', {
      Protocol: 'email',
      Endpoint: 'test@example.com',
    });
  });

  test('Creates CloudWatch alarms for CPU, connections, and storage', () => {
    // CPU Utilization Alarm
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      MetricName: 'CPUUtilization',
      Namespace: 'AWS/RDS',
      Threshold: 80,
      ComparisonOperator: 'GreaterThanThreshold',
    });

    // Database Connections Alarm
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      MetricName: 'DatabaseConnections',
      Namespace: 'AWS/RDS',
      Threshold: 50,
      ComparisonOperator: 'GreaterThanThreshold',
    });

    // Free Storage Space Alarm
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      MetricName: 'FreeStorageSpace',
      Namespace: 'AWS/RDS',
      Threshold: 2147483648,
      ComparisonOperator: 'LessThanThreshold',
    });
  });

  test('Creates CloudWatch dashboard', () => {
    template.hasResourceProperties('AWS::CloudWatch::Dashboard', {
      DashboardName: 'TestStack-DatabaseMonitoring',
    });
  });

  test('Creates security group with MySQL access', () => {
    template.hasResourceProperties('AWS::EC2::SecurityGroup', {
      SecurityGroupIngress: [
        {
          IpProtocol: 'tcp',
          FromPort: 3306,
          ToPort: 3306,
          CidrIp: '10.0.0.0/16',
        },
      ],
    });
  });

  test('Creates IAM role for enhanced monitoring when monitoring interval > 0', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Effect: 'Allow',
            Principal: {
              Service: 'monitoring.rds.amazonaws.com',
            },
            Action: 'sts:AssumeRole',
          },
        ],
      },
      ManagedPolicyArns: [
        'arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole',
      ],
    });
  });

  test('Production environment enables MultiAZ and deletion protection', () => {
    const prodStack = new DatabaseMonitoringStack(app, 'ProdStack', {
      alertEmail: 'prod@example.com',
      environment: 'production',
    });
    const prodTemplate = Template.fromStack(prodStack);

    prodTemplate.hasResourceProperties('AWS::RDS::DBInstance', {
      MultiAZ: true,
      DeletionProtection: true,
    });
  });

  test('Production environment creates additional latency alarms', () => {
    const prodStack = new DatabaseMonitoringStack(app, 'ProdStack', {
      alertEmail: 'prod@example.com',
      environment: 'production',
    });
    const prodTemplate = Template.fromStack(prodStack);

    // Read Latency Alarm
    prodTemplate.hasResourceProperties('AWS::CloudWatch::Alarm', {
      MetricName: 'ReadLatency',
      Namespace: 'AWS/RDS',
      Threshold: 0.2,
      ComparisonOperator: 'GreaterThanThreshold',
    });

    // Write Latency Alarm
    prodTemplate.hasResourceProperties('AWS::CloudWatch::Alarm', {
      MetricName: 'WriteLatency',
      Namespace: 'AWS/RDS',
      Threshold: 0.2,
      ComparisonOperator: 'GreaterThanThreshold',
    });
  });

  test('Custom configuration parameters are applied correctly', () => {
    const customStack = new DatabaseMonitoringStack(app, 'CustomStack', {
      alertEmail: 'custom@example.com',
      environment: 'development',
      databaseInstanceClass: 'db.t3.small',
      databaseAllocatedStorage: 50,
      cpuAlarmThreshold: 70,
      connectionsAlarmThreshold: 100,
    });
    const customTemplate = Template.fromStack(customStack);

    customTemplate.hasResourceProperties('AWS::RDS::DBInstance', {
      DBInstanceClass: 'db.t3.small',
      AllocatedStorage: '50',
    });

    customTemplate.hasResourceProperties('AWS::CloudWatch::Alarm', {
      MetricName: 'CPUUtilization',
      Threshold: 70,
    });

    customTemplate.hasResourceProperties('AWS::CloudWatch::Alarm', {
      MetricName: 'DatabaseConnections',
      Threshold: 100,
    });
  });

  test('Disabled enhanced monitoring when interval is 0', () => {
    const noMonitoringStack = new DatabaseMonitoringStack(app, 'NoMonitoringStack', {
      alertEmail: 'test@example.com',
      environment: 'development',
      monitoringInterval: 0,
    });
    const noMonitoringTemplate = Template.fromStack(noMonitoringStack);

    // Should not create enhanced monitoring role when interval is 0
    noMonitoringTemplate.resourceCountIs('AWS::IAM::Role', 0);
  });

  test('Stack has required outputs', () => {
    const outputs = template.findOutputs('*');
    
    expect(outputs).toHaveProperty('DatabaseInstanceIdentifier');
    expect(outputs).toHaveProperty('DatabaseEndpoint');
    expect(outputs).toHaveProperty('DatabasePort');
    expect(outputs).toHaveProperty('SNSTopicArn');
    expect(outputs).toHaveProperty('CloudWatchDashboardURL');
    expect(outputs).toHaveProperty('PerformanceInsightsEnabled');
    expect(outputs).toHaveProperty('DatabaseSecurityGroupId');
    expect(outputs).toHaveProperty('VPCId');
    expect(outputs).toHaveProperty('EstimatedMonthlyCost');
    expect(outputs).toHaveProperty('PostDeploymentSteps');
  });

  test('All resources have appropriate tags', () => {
    // Check that VPC has environment tag
    template.hasResourceProperties('AWS::EC2::VPC', {
      Tags: [
        {
          Key: 'Environment',
          Value: 'test',
        },
      ],
    });

    // Check that RDS instance has purpose tag
    template.hasResourceProperties('AWS::RDS::DBInstance', {
      Tags: [
        {
          Key: 'Purpose',
          Value: 'Database Monitoring Demo',
        },
      ],
    });
  });
});