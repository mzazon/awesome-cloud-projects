import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { NetworkTroubleshootingStack } from '../lib/network-troubleshooting-stack';

describe('NetworkTroubleshootingStack', () => {
  let app: cdk.App;
  let stack: NetworkTroubleshootingStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new NetworkTroubleshootingStack(app, 'TestStack', {
      randomSuffix: 'test123',
      env: {
        account: '123456789012',
        region: 'us-east-1',
      },
    });
    template = Template.fromStack(stack);
  });

  test('Creates VPC Lattice Service Network', () => {
    template.hasResourceProperties('AWS::VpcLattice::ServiceNetwork', {
      Name: 'troubleshooting-network-test123',
      AuthType: 'AWS_IAM',
    });
  });

  test('Creates IAM roles with correct policies', () => {
    // Test automation role
    template.hasResourceProperties('AWS::IAM::Role', {
      RoleName: 'NetworkTroubleshootingRole-test123',
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Effect: 'Allow',
            Principal: {
              Service: 'ssm.amazonaws.com',
            },
            Action: 'sts:AssumeRole',
          },
        ],
      },
    });

    // Test Lambda role
    template.hasResourceProperties('AWS::IAM::Role', {
      RoleName: 'NetworkTroubleshootingLambdaRole-test123',
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

  test('Creates Lambda function with correct configuration', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      FunctionName: 'network-troubleshooting-test123',
      Runtime: 'python3.12',
      Handler: 'index.lambda_handler',
      Timeout: 60,
    });
  });

  test('Creates SNS topic and subscriptions', () => {
    template.hasResourceProperties('AWS::SNS::Topic', {
      TopicName: 'network-alerts-test123',
      DisplayName: 'Network Troubleshooting Alerts',
    });

    template.hasResourceProperties('AWS::SNS::Subscription', {
      Protocol: 'lambda',
    });
  });

  test('Creates CloudWatch alarms', () => {
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      AlarmName: 'VPCLattice-HighErrorRate-test123',
      MetricName: 'HTTPCode_Target_5XX_Count',
      Namespace: 'AWS/VpcLattice',
      Threshold: 10,
    });

    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      AlarmName: 'VPCLattice-HighLatency-test123',
      MetricName: 'TargetResponseTime',
      Namespace: 'AWS/VpcLattice',
      Threshold: 5000,
    });
  });

  test('Creates Systems Manager automation document', () => {
    template.hasResourceProperties('AWS::SSM::Document', {
      DocumentType: 'Automation',
      DocumentFormat: 'JSON',
      Name: 'NetworkReachabilityAnalysis-test123',
    });
  });

  test('Creates EC2 instance with security group', () => {
    template.hasResourceProperties('AWS::EC2::Instance', {
      InstanceType: 't3.micro',
    });

    template.hasResourceProperties('AWS::EC2::SecurityGroup', {
      GroupDescription: 'Security group for VPC Lattice testing',
    });
  });

  test('Creates CloudWatch dashboard', () => {
    template.hasResourceProperties('AWS::CloudWatch::Dashboard', {
      DashboardName: 'VPCLatticeNetworkTroubleshooting-test123',
    });
  });

  test('Creates CloudWatch log group', () => {
    template.hasResourceProperties('AWS::Logs::LogGroup', {
      RetentionInDays: 7,
    });
  });

  test('Has correct number of outputs', () => {
    const outputs = template.findOutputs('*');
    expect(Object.keys(outputs)).toHaveLength(7);
  });

  test('Stack contains required tags', () => {
    const stackTags = stack.tags;
    expect(stackTags.hasTag('Project')).toBe(true);
    expect(stackTags.hasTag('Environment')).toBe(true);
    expect(stackTags.hasTag('Purpose')).toBe(true);
  });
});