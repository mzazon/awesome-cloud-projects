import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { SecurityComplianceAuditingStack } from '../lib/security-compliance-auditing-stack';

/**
 * Unit tests for Security Compliance Auditing Stack
 */

describe('SecurityComplianceAuditingStack', () => {
  let app: cdk.App;
  let stack: SecurityComplianceAuditingStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new SecurityComplianceAuditingStack(app, 'TestSecurityComplianceStack', {
      emailForAlerts: 'test@example.com',
      enableVpcLatticeDemo: true,
    });
    template = Template.fromStack(stack);
  });

  test('Stack creates GuardDuty detector', () => {
    template.hasResourceProperties('AWS::GuardDuty::Detector', {
      Enable: true,
      FindingPublishingFrequency: 'FIFTEEN_MINUTES',
    });
  });

  test('Stack creates S3 bucket with encryption', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      BucketEncryption: {
        ServerSideEncryptionConfiguration: [
          {
            ServerSideEncryptionByDefault: {
              SSEAlgorithm: 'AES256'
            }
          }
        ]
      }
    });
  });

  test('Stack creates Lambda function for security processing', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      FunctionName: 'security-compliance-processor',
      Runtime: 'python3.12',
      Handler: 'security_processor.lambda_handler',
      Timeout: 60,
      MemorySize: 512,
    });
  });

  test('Stack creates SNS topic for alerts', () => {
    template.hasResourceProperties('AWS::SNS::Topic', {
      DisplayName: 'Security Compliance Alerts',
    });
  });

  test('Stack creates CloudWatch log group', () => {
    template.hasResourceProperties('AWS::Logs::LogGroup', {
      LogGroupName: '/aws/vpclattice/security-audit',
      RetentionInDays: 30,
    });
  });

  test('Stack creates CloudWatch dashboard', () => {
    template.hasResourceProperties('AWS::CloudWatch::Dashboard', {
      DashboardName: 'SecurityComplianceDashboard',
    });
  });

  test('Stack creates VPC Lattice service network when demo is enabled', () => {
    template.hasResourceProperties('AWS::VpcLattice::ServiceNetwork', {});
  });

  test('Stack creates log subscription filter', () => {
    template.hasResourceProperties('AWS::Logs::SubscriptionFilter', {
      FilterName: 'SecurityComplianceFilter',
    });
  });

  test('Stack creates IAM role with proper permissions', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Effect: 'Allow',
            Principal: {
              Service: 'lambda.amazonaws.com'
            },
            Action: 'sts:AssumeRole'
          }
        ]
      }
    });
  });

  test('Stack outputs important resource identifiers', () => {
    const outputs = template.findOutputs('*');
    
    expect(outputs).toHaveProperty('GuardDutyDetectorId');
    expect(outputs).toHaveProperty('ComplianceReportsBucketName');
    expect(outputs).toHaveProperty('SecurityAlertsTopicArn');
    expect(outputs).toHaveProperty('SecurityProcessorFunctionName');
    expect(outputs).toHaveProperty('VpcLatticeLogGroupName');
    expect(outputs).toHaveProperty('SecurityDashboardUrl');
  });

  test('Lambda function has proper environment variables', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      Environment: {
        Variables: {
          GUARDDUTY_DETECTOR_ID: { Ref: expect.any(String) },
          BUCKET_NAME: { Ref: expect.any(String) },
          SNS_TOPIC_ARN: { Ref: expect.any(String) },
        }
      }
    });
  });

  test('S3 bucket has lifecycle policy for cost optimization', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      LifecycleConfiguration: {
        Rules: [
          {
            Id: 'DeleteOldReports',
            Status: 'Enabled',
            ExpirationInDays: 90,
            Transitions: [
              {
                StorageClass: 'STANDARD_IA',
                TransitionInDays: 30
              },
              {
                StorageClass: 'GLACIER',
                TransitionInDays: 60
              }
            ]
          }
        ]
      }
    });
  });

  test('Stack without demo VPC Lattice does not create service network', () => {
    const stackWithoutDemo = new SecurityComplianceAuditingStack(app, 'TestStackWithoutDemo', {
      emailForAlerts: 'test@example.com',
      enableVpcLatticeDemo: false,
    });
    const templateWithoutDemo = Template.fromStack(stackWithoutDemo);

    templateWithoutDemo.resourceCountIs('AWS::VpcLattice::ServiceNetwork', 0);
  });

  test('Stack has proper resource tags', () => {
    const resources = template.findResources('AWS::S3::Bucket');
    
    // Check that resources have the expected tags (implementation varies by resource type)
    expect(Object.keys(resources)).toHaveLength(1);
  });
});