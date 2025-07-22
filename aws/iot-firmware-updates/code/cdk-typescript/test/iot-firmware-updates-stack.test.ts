import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { IoTFirmwareUpdatesStack } from '../lib/iot-firmware-updates-stack';

describe('IoTFirmwareUpdatesStack', () => {
  let app: cdk.App;
  let stack: IoTFirmwareUpdatesStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new IoTFirmwareUpdatesStack(app, 'TestStack', {
      environment: 'test',
      env: {
        account: '123456789012',
        region: 'us-east-1'
      }
    });
    template = Template.fromStack(stack);
  });

  test('creates S3 bucket for firmware storage', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      VersioningConfiguration: {
        Status: 'Enabled'
      },
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

  test('creates Lambda function for firmware update management', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      Runtime: 'python3.11',
      Handler: 'index.lambda_handler',
      Timeout: 300,
      MemorySize: 256
    });
  });

  test('creates IoT Thing Group', () => {
    template.hasResourceProperties('AWS::IoT::ThingGroup', {
      ThingGroupProperties: {
        ThingGroupDescription: 'Devices eligible for firmware updates'
      }
    });
  });

  test('creates IoT Thing', () => {
    template.hasResourceProperties('AWS::IoT::Thing', {
      AttributePayload: {
        Attributes: {
          DeviceType: 'sensor',
          FirmwareVersion: '0.9.0',
          Environment: 'test'
        }
      }
    });
  });

  test('creates Signer signing profile', () => {
    template.hasResourceProperties('AWS::Signer::SigningProfile', {
      PlatformId: 'AmazonFreeRTOS-TI-CC3220SF',
      SignatureValidityPeriod: {
        Type: 'DAYS',
        Value: 365
      }
    });
  });

  test('creates IAM role for IoT Jobs', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Effect: 'Allow',
            Principal: {
              Service: 'iot.amazonaws.com'
            },
            Action: 'sts:AssumeRole'
          }
        ]
      }
    });
  });

  test('creates IAM role for Lambda function', () => {
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

  test('creates CloudWatch dashboard', () => {
    template.hasResourceProperties('AWS::CloudWatch::Dashboard', {
      DashboardBody: cdk.Match.anyValue()
    });
  });

  test('creates SNS topic for notifications', () => {
    template.hasResourceProperties('AWS::SNS::Topic', {
      DisplayName: 'IoT Firmware Update Notifications'
    });
  });

  test('creates EventBridge rule for job status monitoring', () => {
    template.hasResourceProperties('AWS::Events::Rule', {
      EventPattern: {
        source: ['aws.iot'],
        'detail-type': ['IoT Job Status Change'],
        detail: {
          status: ['SUCCEEDED', 'FAILED', 'CANCELED']
        }
      }
    });
  });

  test('has correct number of outputs', () => {
    const outputs = template.findOutputs('*');
    expect(Object.keys(outputs)).toHaveLength(10);
  });

  test('includes required stack outputs', () => {
    template.hasOutput('FirmwareBucketName', {});
    template.hasOutput('LambdaFunctionName', {});
    template.hasOutput('SigningProfileName', {});
    template.hasOutput('ThingGroupName', {});
    template.hasOutput('NotificationTopicArn', {});
  });

  test('Lambda function has correct environment variables', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      Environment: {
        Variables: {
          FIRMWARE_BUCKET: cdk.Match.anyValue(),
          SIGNING_PROFILE_NAME: cdk.Match.anyValue(),
          IOT_JOBS_ROLE_ARN: cdk.Match.anyValue()
        }
      }
    });
  });

  test('S3 bucket has lifecycle policies configured', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      LifecycleConfiguration: {
        Rules: [
          {
            Id: 'FirmwareRetention',
            Status: 'Enabled',
            ExpirationInDays: 365,
            NoncurrentVersionExpirationInDays: 90
          }
        ]
      }
    });
  });

  test('S3 bucket blocks public access', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      PublicAccessBlockConfiguration: {
        BlockPublicAcls: true,
        BlockPublicPolicy: true,
        IgnorePublicAcls: true,
        RestrictPublicBuckets: true
      }
    });
  });

  test('Lambda function has appropriate IAM permissions', () => {
    template.hasResourceProperties('AWS::IAM::Policy', {
      PolicyDocument: {
        Statement: cdk.Match.arrayWith([
          {
            Effect: 'Allow',
            Action: cdk.Match.arrayWith([
              'iot:CreateJob',
              'iot:DescribeJob',
              'iot:ListJobs'
            ]),
            Resource: '*'
          }
        ])
      }
    });
  });
});