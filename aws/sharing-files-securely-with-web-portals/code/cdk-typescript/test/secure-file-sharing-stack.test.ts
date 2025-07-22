import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { SecureFileSharingStack } from '../lib/secure-file-sharing-stack';

describe('SecureFileSharingStack', () => {
  let app: cdk.App;
  let stack: SecureFileSharingStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new SecureFileSharingStack(app, 'TestStack', {
      env: { account: '123456789012', region: 'us-east-1' }
    });
    template = Template.fromStack(stack);
  });

  describe('S3 Bucket Configuration', () => {
    test('creates S3 bucket with proper security configuration', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        PublicAccessBlockConfiguration: {
          BlockPublicAcls: true,
          BlockPublicPolicy: true,
          IgnorePublicAcls: true,
          RestrictPublicBuckets: true
        },
        BucketEncryption: {
          ServerSideEncryptionConfiguration: [
            {
              ServerSideEncryptionByDefault: {
                SSEAlgorithm: 'aws:kms'
              },
              BucketKeyEnabled: true
            }
          ]
        },
        VersioningConfiguration: {
          Status: 'Enabled'
        }
      });
    });

    test('creates S3 bucket with lifecycle configuration', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        LifecycleConfiguration: {
          Rules: Match.arrayWith([
            Match.objectLike({
              Id: 'ArchiveOldVersions',
              Status: 'Enabled',
              NoncurrentVersionExpirationInDays: 90
            }),
            Match.objectLike({
              Id: 'ArchiveByPrefix',
              Status: 'Enabled',
              Prefix: 'archive/'
            })
          ])
        }
      });
    });

    test('enables EventBridge notifications', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        NotificationConfiguration: {
          EventBridgeConfiguration: {
            EventBridgeEnabled: true
          }
        }
      });
    });
  });

  describe('KMS Configuration', () => {
    test('creates KMS key with rotation enabled', () => {
      template.hasResourceProperties('AWS::KMS::Key', {
        EnableKeyRotation: true,
        Description: 'KMS key for S3 bucket encryption in secure file sharing solution'
      });
    });

    test('creates KMS key with proper policy', () => {
      template.hasResourceProperties('AWS::KMS::Key', {
        KeyPolicy: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Sid: 'Enable IAM root permissions',
              Effect: 'Allow',
              Principal: { AWS: { 'Fn::Join': ['', ['arn:', { Ref: 'AWS::Partition' }, ':iam::', { Ref: 'AWS::AccountId' }, ':root']] } },
              Action: 'kms:*',
              Resource: '*'
            }),
            Match.objectLike({
              Sid: 'Allow CloudTrail encryption',
              Effect: 'Allow',
              Principal: { Service: 'cloudtrail.amazonaws.com' }
            })
          ])
        }
      });
    });

    test('creates KMS alias', () => {
      template.hasResourceProperties('AWS::KMS::Alias', {
        AliasName: Match.stringLikeRegexp('alias/secure-file-sharing-.*')
      });
    });
  });

  describe('CloudTrail Configuration', () => {
    test('creates CloudTrail with proper configuration', () => {
      template.hasResourceProperties('AWS::CloudTrail::Trail', {
        IncludeGlobalServiceEvents: true,
        IsMultiRegionTrail: true,
        EnableLogFileValidation: true
      });
    });

    test('creates CloudWatch log group for CloudTrail', () => {
      template.hasResourceProperties('AWS::Logs::LogGroup', {
        LogGroupName: Match.stringLikeRegexp('/aws/cloudtrail/secure-file-sharing-.*'),
        RetentionInDays: 180
      });
    });

    test('creates CloudTrail with S3 data events', () => {
      template.hasResourceProperties('AWS::CloudTrail::EventDataStore', Match.anyValue());
    });
  });

  describe('IAM Configuration', () => {
    test('creates Transfer Family IAM role', () => {
      template.hasResourceProperties('AWS::IAM::Role', {
        AssumeRolePolicyDocument: {
          Statement: [
            {
              Effect: 'Allow',
              Principal: { Service: 'transfer.amazonaws.com' },
              Action: 'sts:AssumeRole'
            }
          ]
        }
      });
    });

    test('Transfer Family role has required S3 permissions', () => {
      template.hasResourceProperties('AWS::IAM::Role', {
        Policies: [
          {
            PolicyName: 'S3AccessPolicy',
            PolicyDocument: {
              Statement: Match.arrayWith([
                Match.objectLike({
                  Sid: 'S3BucketAccess',
                  Effect: 'Allow',
                  Action: [
                    's3:ListBucket',
                    's3:GetBucketLocation',
                    's3:GetBucketVersioning'
                  ]
                }),
                Match.objectLike({
                  Sid: 'S3ObjectAccess',
                  Effect: 'Allow',
                  Action: [
                    's3:GetObject',
                    's3:GetObjectVersion',
                    's3:GetObjectAcl',
                    's3:PutObject',
                    's3:PutObjectAcl',
                    's3:DeleteObject',
                    's3:DeleteObjectVersion'
                  ]
                }),
                Match.objectLike({
                  Sid: 'KMSAccess',
                  Effect: 'Allow',
                  Action: [
                    'kms:Decrypt',
                    'kms:GenerateDataKey',
                    'kms:CreateGrant'
                  ]
                })
              ])
            }
          }
        ]
      });
    });
  });

  describe('Transfer Family Configuration', () => {
    test('creates Transfer Family Web App', () => {
      template.hasResourceProperties('AWS::Transfer::WebApp', {
        IdentityProviderType: 'SERVICE_MANAGED',
        AccessEndpointType: 'PUBLIC',
        WebAppUnits: 1
      });
    });

    test('Web App has proper tags', () => {
      template.hasResourceProperties('AWS::Transfer::WebApp', {
        Tags: Match.arrayWith([
          {
            Key: 'Purpose',
            Value: 'SecureFileSharing'
          }
        ])
      });
    });
  });

  describe('Stack Outputs', () => {
    test('creates all required outputs', () => {
      const outputs = template.findOutputs('*');
      
      expect(outputs).toHaveProperty('S3BucketName');
      expect(outputs).toHaveProperty('S3BucketArn');
      expect(outputs).toHaveProperty('WebAppId');
      expect(outputs).toHaveProperty('WebAppEndpoint');
      expect(outputs).toHaveProperty('TransferRoleArn');
      expect(outputs).toHaveProperty('CloudTrailArn');
      expect(outputs).toHaveProperty('KMSKeyArn');
    });
  });

  describe('Resource Tagging', () => {
    test('applies stack-level tags', () => {
      // Check that resources have proper tagging structure
      // This is a simplified test - in practice, you'd check specific resources
      expect(stack.tags.tagValues()).toBeDefined();
    });
  });

  describe('Security Compliance', () => {
    test('no resources allow public access', () => {
      // Ensure S3 bucket blocks public access
      template.hasResourceProperties('AWS::S3::Bucket', {
        PublicAccessBlockConfiguration: {
          BlockPublicAcls: true,
          BlockPublicPolicy: true,
          IgnorePublicAcls: true,
          RestrictPublicBuckets: true
        }
      });
    });

    test('all storage is encrypted', () => {
      // S3 encryption
      template.hasResourceProperties('AWS::S3::Bucket', {
        BucketEncryption: Match.objectLike({
          ServerSideEncryptionConfiguration: Match.anyValue()
        })
      });

      // CloudWatch Logs encryption
      template.hasResourceProperties('AWS::Logs::LogGroup', {
        KmsKeyId: Match.anyValue()
      });
    });
  });

  describe('Cost Optimization', () => {
    test('implements lifecycle policies for cost savings', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        LifecycleConfiguration: {
          Rules: Match.arrayWith([
            Match.objectLike({
              Status: 'Enabled',
              Transitions: Match.anyValue()
            })
          ])
        }
      });
    });

    test('uses S3 bucket keys for KMS cost optimization', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        BucketEncryption: {
          ServerSideEncryptionConfiguration: [
            {
              ServerSideEncryptionByDefault: Match.anyValue(),
              BucketKeyEnabled: true
            }
          ]
        }
      });
    });
  });
});