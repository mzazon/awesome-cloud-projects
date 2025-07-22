import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { S3CrossRegionReplicationStack } from '../lib/s3-cross-region-replication-stack';

describe('S3CrossRegionReplicationStack', () => {
  let app: cdk.App;
  
  beforeEach(() => {
    app = new cdk.App();
  });

  describe('Primary Region Stack', () => {
    let template: Template;
    
    beforeEach(() => {
      const stack = new S3CrossRegionReplicationStack(app, 'TestPrimaryStack', {
        env: { region: 'us-east-1', account: '123456789012' },
        isPrimaryRegion: true,
        primaryRegion: 'us-east-1',
        secondaryRegion: 'us-west-2',
        projectName: 'TestProject',
      });
      template = Template.fromStack(stack);
    });

    test('creates source S3 bucket with correct configuration', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        BucketName: Match.stringLikeRegexp('crr-source-testproject-'),
        VersioningConfiguration: {
          Status: 'Enabled',
        },
        BucketEncryption: {
          ServerSideEncryptionConfiguration: [{
            ServerSideEncryptionByDefault: {
              SSEAlgorithm: 'aws:kms',
            },
            BucketKeyEnabled: true,
          }],
        },
        PublicAccessBlockConfiguration: {
          BlockPublicAcls: true,
          BlockPublicPolicy: true,
          IgnorePublicAcls: true,
          RestrictPublicBuckets: true,
        },
      });
    });

    test('creates source KMS key with rotation enabled', () => {
      template.hasResourceProperties('AWS::KMS::Key', {
        Description: Match.stringLikeRegexp('S3 Cross-Region Replication Source Key'),
        EnableKeyRotation: true,
        KeyPolicy: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Sid: 'EnableIAMUserPermissions',
              Effect: 'Allow',
              Principal: {
                AWS: Match.anyValue(),
              },
              Action: 'kms:*',
              Resource: '*',
            }),
            Match.objectLike({
              Sid: 'AllowS3Service',
              Effect: 'Allow',
              Principal: {
                Service: 's3.amazonaws.com',
              },
              Action: Match.arrayWith([
                'kms:Decrypt',
                'kms:GenerateDataKey',
              ]),
            }),
          ]),
        },
      });
    });

    test('creates KMS key alias', () => {
      template.hasResourceProperties('AWS::KMS::Alias', {
        AliasName: 'alias/s3-crr-source-testproject',
      });
    });

    test('creates replication IAM role with correct trust policy', () => {
      template.hasResourceProperties('AWS::IAM::Role', {
        RoleName: 'S3ReplicationRole-TestProject',
        AssumeRolePolicyDocument: {
          Statement: [{
            Effect: 'Allow',
            Principal: {
              Service: 's3.amazonaws.com',
            },
            Action: 'sts:AssumeRole',
          }],
        },
        Description: 'S3 Cross-Region Replication Role',
      });
    });

    test('creates replication role policies with correct permissions', () => {
      // Check for source bucket read permissions
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Sid: 'GetObjectPermissions',
              Effect: 'Allow',
              Action: [
                's3:GetObjectVersion',
                's3:GetObjectVersionAcl',
                's3:GetObjectVersionForReplication',
                's3:GetObjectVersionTagging',
              ],
            }),
          ]),
        },
      });

      // Check for destination bucket write permissions
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Sid: 'ReplicateObjectPermissions',
              Effect: 'Allow',
              Action: [
                's3:ReplicateObject',
                's3:ReplicateDelete',
                's3:ReplicateTags',
              ],
            }),
          ]),
        },
      });

      // Check for KMS permissions
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Sid: 'KMSDecryptPermissions',
              Effect: 'Allow',
              Action: ['kms:Decrypt'],
            }),
          ]),
        },
      });
    });

    test('creates bucket policy with security controls', () => {
      template.hasResourceProperties('AWS::S3::BucketPolicy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Sid: 'DenyUnencryptedObjectUploads',
              Effect: 'Deny',
              Principal: '*',
              Action: 's3:PutObject',
              Condition: {
                StringNotEquals: {
                  's3:x-amz-server-side-encryption': 'aws:kms',
                },
              },
            }),
            Match.objectLike({
              Sid: 'DenyInsecureConnections',
              Effect: 'Deny',
              Principal: '*',
              Action: 's3:*',
              Condition: {
                Bool: {
                  'aws:SecureTransport': 'false',
                },
              },
            }),
          ]),
        },
      });
    });

    test('creates CloudWatch alarm for replication monitoring', () => {
      template.hasResourceProperties('AWS::CloudWatch::Alarm', {
        AlarmName: Match.stringLikeRegexp('S3-Replication-Failures-'),
        AlarmDescription: 'Alert when S3 replication fails',
        MetricName: 'ReplicationLatency',
        Namespace: 'AWS/S3',
        Statistic: 'Maximum',
        Period: 300,
        Threshold: 900,
        EvaluationPeriods: 2,
        ComparisonOperator: 'GreaterThanThreshold',
      });
    });

    test('creates CloudFormation outputs', () => {
      template.hasOutput('SourceBucketName', {
        Description: 'Name of the source S3 bucket',
      });

      template.hasOutput('SourceBucketArn', {
        Description: 'ARN of the source S3 bucket',
      });

      template.hasOutput('SourceKmsKeyId', {
        Description: 'ID of the source KMS key',
      });

      template.hasOutput('ReplicationRoleArn', {
        Description: 'ARN of the replication IAM role',
      });
    });
  });

  describe('Secondary Region Stack', () => {
    let template: Template;
    
    beforeEach(() => {
      const stack = new S3CrossRegionReplicationStack(app, 'TestSecondaryStack', {
        env: { region: 'us-west-2', account: '123456789012' },
        isPrimaryRegion: false,
        primaryRegion: 'us-east-1',
        secondaryRegion: 'us-west-2',
        projectName: 'TestProject',
        sourceBucketArn: 'arn:aws:s3:::test-source-bucket',
        sourceKmsKeyArn: 'arn:aws:kms:us-east-1:123456789012:key/test-key-id',
      });
      template = Template.fromStack(stack);
    });

    test('creates destination S3 bucket with correct configuration', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        BucketName: Match.stringLikeRegexp('crr-dest-testproject-'),
        VersioningConfiguration: {
          Status: 'Enabled',
        },
        BucketEncryption: {
          ServerSideEncryptionConfiguration: [{
            ServerSideEncryptionByDefault: {
              SSEAlgorithm: 'aws:kms',
            },
            BucketKeyEnabled: true,
          }],
        },
        PublicAccessBlockConfiguration: {
          BlockPublicAcls: true,
          BlockPublicPolicy: true,
          IgnorePublicAcls: true,
          RestrictPublicBuckets: true,
        },
      });
    });

    test('creates destination KMS key with correct policy', () => {
      template.hasResourceProperties('AWS::KMS::Key', {
        Description: Match.stringLikeRegexp('S3 Cross-Region Replication Destination Key'),
        EnableKeyRotation: true,
        KeyPolicy: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Sid: 'AllowReplicationRole',
              Effect: 'Allow',
              Principal: {
                AWS: Match.stringLikeRegexp('arn:aws:iam::.*:role/S3ReplicationRole-TestProject'),
              },
              Action: ['kms:GenerateDataKey'],
            }),
          ]),
        },
      });
    });

    test('creates destination KMS key alias', () => {
      template.hasResourceProperties('AWS::KMS::Alias', {
        AliasName: 'alias/s3-crr-dest-testproject',
      });
    });

    test('creates destination bucket policy with replication permissions', () => {
      template.hasResourceProperties('AWS::S3::BucketPolicy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Sid: 'AllowReplicationRole',
              Effect: 'Allow',
              Principal: {
                AWS: Match.stringLikeRegexp('arn:aws:iam::.*:role/S3ReplicationRole-TestProject'),
              },
              Action: [
                's3:ReplicateObject',
                's3:ReplicateDelete',
                's3:ReplicateTags',
              ],
            }),
          ]),
        },
      });
    });

    test('creates Lambda function for replication configuration', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        Runtime: 'python3.9',
        Handler: 'index.handler',
        Timeout: 300,
      });
    });

    test('creates custom resource for replication configuration', () => {
      template.hasResourceProperties('AWS::CloudFormation::CustomResource', {
        ServiceToken: Match.anyValue(),
      });
    });

    test('creates CloudFormation outputs for destination resources', () => {
      template.hasOutput('DestinationBucketName', {
        Description: 'Name of the destination S3 bucket',
      });

      template.hasOutput('DestinationBucketArn', {
        Description: 'ARN of the destination S3 bucket',
      });

      template.hasOutput('DestinationKmsKeyId', {
        Description: 'ID of the destination KMS key',
      });
    });
  });

  describe('Stack Dependencies', () => {
    test('secondary stack requires source bucket ARN', () => {
      expect(() => {
        new S3CrossRegionReplicationStack(app, 'TestSecondaryStackInvalid', {
          env: { region: 'us-west-2', account: '123456789012' },
          isPrimaryRegion: false,
          primaryRegion: 'us-east-1',
          secondaryRegion: 'us-west-2',
          projectName: 'TestProject',
          // Missing sourceBucketArn and sourceKmsKeyArn
        });
      }).toThrow();
    });
  });

  describe('Resource Naming', () => {
    test('uses consistent naming patterns', () => {
      const primaryStack = new S3CrossRegionReplicationStack(app, 'TestPrimaryStack', {
        env: { region: 'us-east-1', account: '123456789012' },
        isPrimaryRegion: true,
        primaryRegion: 'us-east-1',
        secondaryRegion: 'us-west-2',
        projectName: 'MyTestProject',
      });

      const template = Template.fromStack(primaryStack);

      // Check bucket naming convention
      template.hasResourceProperties('AWS::S3::Bucket', {
        BucketName: Match.stringLikeRegexp('crr-source-mytestproject-'),
      });

      // Check KMS alias naming convention
      template.hasResourceProperties('AWS::KMS::Alias', {
        AliasName: 'alias/s3-crr-source-mytestproject',
      });

      // Check IAM role naming convention
      template.hasResourceProperties('AWS::IAM::Role', {
        RoleName: 'S3ReplicationRole-MyTestProject',
      });
    });
  });
});