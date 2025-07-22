import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { AutomatedBackupStack } from '../lib/automated-backup-stack';

describe('AutomatedBackupStack', () => {
  let app: cdk.App;
  let stack: AutomatedBackupStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new AutomatedBackupStack(app, 'TestBackupStack', {
      drRegion: 'us-east-1',
      backupRetentionDays: 30,
      weeklyRetentionDays: 90,
      environment: 'test',
      env: {
        account: '123456789012',
        region: 'us-west-2',
      },
    });
    template = Template.fromStack(stack);
  });

  test('creates backup vault with encryption', () => {
    template.hasResourceProperties('AWS::Backup::BackupVault', {
      EncryptionKeyArn: {
        'Fn::GetAtt': [
          template.findResources('AWS::KMS::Key')[0],
          'Arn'
        ]
      }
    });
  });

  test('creates backup plan with daily and weekly rules', () => {
    template.hasResourceProperties('AWS::Backup::BackupPlan', {
      BackupPlan: {
        BackupPlanRule: [
          {
            RuleName: 'DailyBackups',
            ScheduleExpression: 'cron(0 2 * * ? *)',
            Lifecycle: {
              DeleteAfterDays: 30
            }
          },
          {
            RuleName: 'WeeklyBackups', 
            ScheduleExpression: 'cron(0 3 ? * SUN *)',
            Lifecycle: {
              DeleteAfterDays: 90
            }
          }
        ]
      }
    });
  });

  test('creates backup selection with correct environment tag', () => {
    template.hasResourceProperties('AWS::Backup::BackupSelection', {
      BackupSelection: {
        SelectionName: 'testResources',
        Conditions: {
          StringEquals: {
            'aws:ResourceTag/Environment': ['test']
          }
        }
      }
    });
  });

  test('creates SNS topic for notifications', () => {
    template.hasResourceProperties('AWS::SNS::Topic', {
      DisplayName: 'AWS Backup Notifications'
    });
  });

  test('creates CloudWatch alarms for monitoring', () => {
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      AlarmName: 'AWS-Backup-Job-Failures',
      MetricName: 'NumberOfBackupJobsFailed',
      Namespace: 'AWS/Backup'
    });

    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      AlarmName: 'AWS-Backup-Storage-Usage',
      MetricName: 'BackupVaultSizeBytes',
      Namespace: 'AWS/Backup'
    });
  });

  test('creates IAM role with correct policies', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumedBy: {
        Service: 'backup.amazonaws.com'
      },
      ManagedPolicyArns: [
        'arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup',
        'arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores'
      ]
    });
  });

  test('creates S3 bucket for reports with encryption', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      BucketEncryption: {
        ServerSideEncryptionConfiguration: [
          {
            ServerSideEncryptionByDefault: {
              SSEAlgorithm: 'AES256'
            }
          }
        ]
      },
      PublicAccessBlockConfiguration: {
        BlockPublicAcls: true,
        BlockPublicPolicy: true,
        IgnorePublicAcls: true,
        RestrictPublicBuckets: true
      }
    });
  });

  test('has correct number of outputs', () => {
    const outputs = template.findOutputs('*');
    expect(Object.keys(outputs)).toHaveLength(5);
    
    template.hasOutput('BackupVaultName', {});
    template.hasOutput('BackupPlanId', {});
    template.hasOutput('NotificationTopicArn', {});
    template.hasOutput('ReportsBucketName', {});
    template.hasOutput('BackupRoleArn', {});
  });

  test('enables cross-region replication', () => {
    template.hasResourceProperties('AWS::Backup::BackupPlan', {
      BackupPlan: {
        BackupPlanRule: [
          {
            CopyActions: [
              {
                DestinationBackupVaultArn: 'arn:aws:backup:us-east-1:123456789012:backup-vault:dr-backup-vault-123456789012-us-east-1',
                Lifecycle: {
                  DeleteAfterDays: 30
                }
              }
            ]
          },
          {
            CopyActions: [
              {
                DestinationBackupVaultArn: 'arn:aws:backup:us-east-1:123456789012:backup-vault:dr-backup-vault-123456789012-us-east-1',
                Lifecycle: {
                  DeleteAfterDays: 90
                }
              }
            ]
          }
        ]
      }
    });
  });
});