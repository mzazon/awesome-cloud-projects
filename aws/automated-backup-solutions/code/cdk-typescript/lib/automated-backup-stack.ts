import * as cdk from 'aws-cdk-lib';
import * as backup from 'aws-cdk-lib/aws-backup';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as config from 'aws-cdk-lib/aws-config';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as events from 'aws-cdk-lib/aws-events';
import { Construct } from 'constructs';
import { NagSuppressions } from 'cdk-nag';

export interface AutomatedBackupStackProps extends cdk.StackProps {
  readonly drRegion: string;
  readonly backupRetentionDays: number;
  readonly weeklyRetentionDays: number;
  readonly notificationEmail?: string;
  readonly environment: string;
}

export class AutomatedBackupStack extends cdk.Stack {
  public readonly backupVault: backup.BackupVault;
  public readonly backupPlan: backup.BackupPlan;
  public readonly notificationTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: AutomatedBackupStackProps) {
    super(scope, id, props);

    // Create KMS key for backup encryption
    const backupKey = new kms.Key(this, 'BackupEncryptionKey', {
      description: 'KMS key for AWS Backup encryption',
      enableKeyRotation: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For development; use RETAIN in production
    });

    // Create backup vault in primary region
    this.backupVault = new backup.BackupVault(this, 'EnterpriseBackupVault', {
      backupVaultName: `enterprise-backup-vault-${this.account}-${this.region}`,
      encryptionKey: backupKey,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For development; use RETAIN in production
    });

    // Note: DR backup vault will be referenced by ARN for cross-region copy actions
    // The actual DR vault should be created separately in the DR region stack

    // Create SNS topic for backup notifications
    this.notificationTopic = new sns.Topic(this, 'BackupNotificationTopic', {
      topicName: `backup-notifications-${this.account}-${this.region}`,
      displayName: 'AWS Backup Notifications',
    });

    // Add email subscription if provided
    if (props.notificationEmail) {
      this.notificationTopic.addSubscription(
        new snsSubscriptions.EmailSubscription(props.notificationEmail)
      );
    }

    // Create IAM role for AWS Backup service
    const backupRole = new iam.Role(this, 'AWSBackupServiceRole', {
      roleName: 'AWSBackupDefaultServiceRole',
      assumedBy: new iam.ServicePrincipal('backup.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSBackupServiceRolePolicyForBackup'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSBackupServiceRolePolicyForRestores'),
      ],
    });

    // Create backup plan with daily and weekly schedules
    this.backupPlan = new backup.BackupPlan(this, 'EnterpriseBackupPlan', {
      backupPlanName: `enterprise-backup-plan-${this.account}-${this.region}`,
      backupPlanRules: [
        // Daily backup rule
        new backup.BackupPlanRule({
          ruleName: 'DailyBackups',
          backupVault: this.backupVault,
          scheduleExpression: events.Schedule.cron({
            minute: '0',
            hour: '2',
            day: '*',
            month: '*',
            year: '*',
          }),
          startWindow: cdk.Duration.minutes(60),
          completionWindow: cdk.Duration.minutes(120),
          deleteAfter: cdk.Duration.days(props.backupRetentionDays),
          copyActions: [{
            destinationBackupVaultArn: `arn:aws:backup:${props.drRegion}:${this.account}:backup-vault:dr-backup-vault-${this.account}-${props.drRegion}`,
            deleteAfter: cdk.Duration.days(props.backupRetentionDays),
          }],
          recoveryPointTags: {
            BackupType: 'Daily',
            Environment: props.environment,
          },
        }),
        // Weekly backup rule
        new backup.BackupPlanRule({
          ruleName: 'WeeklyBackups',
          backupVault: this.backupVault,
          scheduleExpression: events.Schedule.cron({
            minute: '0',
            hour: '3',
            weekDay: 'SUN',
            month: '*',
            year: '*',
          }),
          startWindow: cdk.Duration.minutes(60),
          completionWindow: cdk.Duration.minutes(240),
          deleteAfter: cdk.Duration.days(props.weeklyRetentionDays),
          copyActions: [{
            destinationBackupVaultArn: `arn:aws:backup:${props.drRegion}:${this.account}:backup-vault:dr-backup-vault-${this.account}-${props.drRegion}`,
            deleteAfter: cdk.Duration.days(props.weeklyRetentionDays),
          }],
          recoveryPointTags: {
            BackupType: 'Weekly',
            Environment: props.environment,
          },
        }),
      ],
    });

    // Create backup selection for environment resources
    new backup.BackupSelection(this, 'EnvironmentResourcesSelection', {
      backupPlan: this.backupPlan,
      selectionName: `${props.environment}Resources`,
      role: backupRole,
      resources: [
        backup.BackupResource.fromTag('Environment', props.environment),
      ],
    });

    // Configure backup vault notifications
    this.backupVault.addToResourcePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      principals: [new iam.ServicePrincipal('backup.amazonaws.com')],
      actions: ['sns:Publish'],
      resources: [this.notificationTopic.topicArn],
    }));

    // Create CloudWatch alarms for backup monitoring
    const backupJobFailuresAlarm = new cloudwatch.Alarm(this, 'BackupJobFailuresAlarm', {
      alarmName: 'AWS-Backup-Job-Failures',
      alarmDescription: 'Alert when backup jobs fail',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Backup',
        metricName: 'NumberOfBackupJobsFailed',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const backupStorageUsageAlarm = new cloudwatch.Alarm(this, 'BackupStorageUsageAlarm', {
      alarmName: 'AWS-Backup-Storage-Usage',
      alarmDescription: 'Alert when backup storage exceeds threshold',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Backup',
        metricName: 'BackupVaultSizeBytes',
        statistic: 'Average',
        period: cdk.Duration.hours(1),
        dimensionsMap: {
          BackupVaultName: this.backupVault.backupVaultName,
        },
      }),
      threshold: 107374182400, // 100 GB in bytes
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 1,
    });

    // Add SNS action to alarms
    const snsAction = new cloudwatchActions.SnsAction(this.notificationTopic);
    backupJobFailuresAlarm.addAlarmAction(snsAction);
    backupStorageUsageAlarm.addAlarmAction(snsAction);

    // Create S3 bucket for backup reports
    const reportsBucket = new s3.Bucket(this, 'BackupReportsBucket', {
      bucketName: `aws-backup-reports-${this.account}-${this.region}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For development; use RETAIN in production
      autoDeleteObjects: true, // For development; remove in production
    });

    // Create backup vault access policy for security
    const vaultAccessPolicy = new iam.PolicyDocument({
      statements: [
        new iam.PolicyStatement({
          sid: 'DenyDeleteBackupVault',
          effect: iam.Effect.DENY,
          principals: [new iam.AnyPrincipal()],
          actions: [
            'backup:DeleteBackupVault',
            'backup:DeleteRecoveryPoint',
            'backup:UpdateRecoveryPointLifecycle',
          ],
          resources: ['*'],
          conditions: {
            StringNotEquals: {
              'aws:userid': [`${this.account}:root`],
            },
          },
        }),
      ],
    });

    // Apply access policy to backup vault
    this.backupVault.addToAccessPolicy(vaultAccessPolicy.statements[0]);

    // Create AWS Config rule for backup compliance (if AWS Config is enabled)
    try {
      new config.ManagedRule(this, 'BackupPlanMinFrequencyRule', {
        identifier: config.ManagedRuleIdentifiers.BACKUP_PLAN_MIN_FREQUENCY_AND_MIN_RETENTION_CHECK,
        description: 'Checks whether a backup plan has a backup rule that satisfies the required frequency and retention period',
        inputParameters: {
          requiredFrequencyValue: '1',
          requiredRetentionDays: '35',
          requiredFrequencyUnit: 'days',
        },
      });
    } catch (error) {
      // Config service may not be available in all regions
      console.warn('AWS Config rule creation skipped - service may not be available');
    }

    // Output important resource information
    new cdk.CfnOutput(this, 'BackupVaultName', {
      value: this.backupVault.backupVaultName,
      description: 'Primary backup vault name',
      exportName: `${this.stackName}-BackupVaultName`,
    });

    new cdk.CfnOutput(this, 'BackupPlanId', {
      value: this.backupPlan.backupPlanId,
      description: 'Backup plan ID',
      exportName: `${this.stackName}-BackupPlanId`,
    });

    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: this.notificationTopic.topicArn,
      description: 'SNS topic ARN for backup notifications',
      exportName: `${this.stackName}-NotificationTopicArn`,
    });

    new cdk.CfnOutput(this, 'ReportsBucketName', {
      value: reportsBucket.bucketName,
      description: 'S3 bucket for backup reports',
      exportName: `${this.stackName}-ReportsBucketName`,
    });

    new cdk.CfnOutput(this, 'BackupRoleArn', {
      value: backupRole.roleArn,
      description: 'IAM role ARN for AWS Backup service',
      exportName: `${this.stackName}-BackupRoleArn`,
    });

    // Add CDK Nag suppressions for specific cases
    NagSuppressions.addResourceSuppressions(
      backupRole,
      [
        {
          id: 'AwsSolutions-IAM4',
          reason: 'AWS Backup service requires AWS managed policies for backup and restore operations',
        },
      ],
    );

    NagSuppressions.addResourceSuppressions(
      this.backupVault,
      [
        {
          id: 'AwsSolutions-S1',
          reason: 'Backup vault does not require access logging as it is primarily for data protection',
        },
      ],
    );

    NagSuppressions.addResourceSuppressions(
      reportsBucket,
      [
        {
          id: 'AwsSolutions-S1',
          reason: 'Reports bucket is for backup reports only and does not require access logging',
        },
      ],
    );
  }
}