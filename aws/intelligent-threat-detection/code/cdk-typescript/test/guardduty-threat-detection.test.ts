import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { GuardDutyThreatDetectionStack } from '../lib/guardduty-threat-detection-stack';

describe('GuardDutyThreatDetectionStack', () => {
  let app: cdk.App;
  let stack: GuardDutyThreatDetectionStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new GuardDutyThreatDetectionStack(app, 'TestGuardDutyStack', {
      notificationEmail: 'test@example.com',
      env: {
        account: '123456789012',
        region: 'us-east-1',
      },
    });
    template = Template.fromStack(stack);
  });

  test('Creates GuardDuty Detector', () => {
    template.hasResourceProperties('AWS::GuardDuty::Detector', {
      Enable: true,
      FindingPublishingFrequency: 'FIFTEEN_MINUTES',
    });
  });

  test('Creates SNS Topic for alerts', () => {
    template.hasResourceProperties('AWS::SNS::Topic', {
      DisplayName: 'GuardDuty Threat Detection Alerts',
    });
  });

  test('Creates Email Subscription', () => {
    template.hasResourceProperties('AWS::SNS::Subscription', {
      Protocol: 'email',
      Endpoint: 'test@example.com',
    });
  });

  test('Creates EventBridge Rule for GuardDuty findings', () => {
    template.hasResourceProperties('AWS::Events::Rule', {
      Description: 'Routes GuardDuty findings to SNS for alerting',
      EventPattern: {
        source: ['aws.guardduty'],
        'detail-type': ['GuardDuty Finding'],
      },
    });
  });

  test('Creates CloudWatch Dashboard', () => {
    template.hasResourceProperties('AWS::CloudWatch::Dashboard', {
      DashboardName: 'GuardDuty-Security-Monitoring',
    });
  });

  test('Creates S3 bucket for findings export by default', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
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

  test('Creates S3 bucket lifecycle rules', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      LifecycleConfiguration: {
        Rules: Match.arrayWith([
          Match.objectLike({
            Id: 'DeleteOldFindings',
            Status: 'Enabled',
            ExpirationInDays: 365,
          }),
        ]),
      },
    });
  });

  test('Creates GuardDuty publishing destination to S3', () => {
    template.hasResourceProperties('AWS::GuardDuty::PublishingDestination', {
      DestinationType: 'S3',
    });
  });

  test('Creates IAM role for GuardDuty S3 access', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: Match.arrayWith([
          Match.objectLike({
            Principal: {
              Service: 'guardduty.amazonaws.com',
            },
          }),
        ]),
      },
    });
  });

  test('Outputs important resource information', () => {
    template.hasOutput('GuardDutyDetectorId', {});
    template.hasOutput('SNSTopicArn', {});
    template.hasOutput('DashboardURL', {});
    template.hasOutput('FindingsExportBucket', {});
    template.hasOutput('NotificationEmail', {});
  });

  test('Stack without S3 export does not create bucket', () => {
    const appNoS3 = new cdk.App();
    const stackNoS3 = new GuardDutyThreatDetectionStack(appNoS3, 'TestStackNoS3', {
      notificationEmail: 'test@example.com',
      enableS3Export: false,
      env: {
        account: '123456789012',
        region: 'us-east-1',
      },
    });
    const templateNoS3 = Template.fromStack(stackNoS3);

    // Should not have S3 bucket or publishing destination
    templateNoS3.resourceCountIs('AWS::S3::Bucket', 0);
    templateNoS3.resourceCountIs('AWS::GuardDuty::PublishingDestination', 0);
  });

  test('Custom finding publishing frequency is applied', () => {
    const appCustom = new cdk.App();
    const stackCustom = new GuardDutyThreatDetectionStack(appCustom, 'TestStackCustom', {
      notificationEmail: 'test@example.com',
      findingPublishingFrequency: 'ONE_HOUR',
      env: {
        account: '123456789012',
        region: 'us-east-1',
      },
    });
    const templateCustom = Template.fromStack(stackCustom);

    templateCustom.hasResourceProperties('AWS::GuardDuty::Detector', {
      FindingPublishingFrequency: 'ONE_HOUR',
    });
  });

  test('EventBridge rule has correct target configuration', () => {
    template.hasResourceProperties('AWS::Events::Rule', {
      Targets: Match.arrayWith([
        Match.objectLike({
          Arn: Match.anyValue(),
          Id: Match.anyValue(),
          InputTransformer: {
            InputPathsMap: {
              severity: '$.detail.severity',
              type: '$.detail.type',
              region: '$.detail.region',
              accountId: '$.detail.accountId',
              description: '$.detail.description',
              detailUrl: '$.detail.service.detectorId',
              timestamp: '$.detail.updatedAt',
            },
          },
        }),
      ]),
    });
  });

  test('Stack applies expected tags', () => {
    const resources = template.findResources('AWS::GuardDuty::Detector');
    const detectorLogicalId = Object.keys(resources)[0];
    const detector = resources[detectorLogicalId];

    expect(detector.Properties.Tags).toEqual(
      expect.arrayContaining([
        { Key: 'Name', Value: 'ThreatDetectionDetector' },
        { Key: 'Purpose', Value: 'AutomatedThreatDetection' },
      ])
    );
  });
});