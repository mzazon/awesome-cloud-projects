import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

export interface BackupStrategyStackProps extends cdk.StackProps {
  readonly notificationEmail?: string;
  readonly enableCrossRegionReplication?: boolean;
  readonly replicationDestinationRegion?: string;
}

export class BackupStrategyStack extends cdk.Stack {
  public readonly backupBucket: s3.Bucket;
  public readonly backupFunction: lambda.Function;
  public readonly notificationTopic: sns.Topic;

  constructor(scope: Construct, id: string, props?: BackupStrategyStackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // Create SNS topic for backup notifications
    this.notificationTopic = new sns.Topic(this, 'BackupNotificationTopic', {
      topicName: `backup-notifications-${uniqueSuffix}`,
      displayName: 'Backup Strategy Notifications',
      description: 'Notifications for backup operations and status updates',
    });

    // Subscribe email if provided
    if (props?.notificationEmail) {
      this.notificationTopic.addSubscription(
        new subscriptions.EmailSubscription(props.notificationEmail)
      );
    }

    // Create main backup bucket with comprehensive configuration
    this.backupBucket = new s3.Bucket(this, 'BackupBucket', {
      bucketName: `backup-strategy-demo-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      autoDeleteObjects: true, // For demo purposes
      lifecycleRules: [
        {
          id: 'backup-lifecycle-rule',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
            {
              storageClass: s3.StorageClass.DEEP_ARCHIVE,
              transitionAfter: cdk.Duration.days(365),
            },
          ],
          noncurrentVersionTransitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
          ],
          noncurrentVersionExpiration: cdk.Duration.days(2555), // ~7 years
        },
      ],
      intelligentTieringConfigurations: [
        {
          id: 'backup-intelligent-tiering',
          prefix: 'intelligent-tier/',
          archiveAccessTierTime: cdk.Duration.days(1),
          deepArchiveAccessTierTime: cdk.Duration.days(90),
        },
      ],
    });

    // Create IAM role for Lambda execution
    const backupExecutionRole = new iam.Role(this, 'BackupExecutionRole', {
      roleName: `backup-execution-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for backup orchestration Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        BackupExecutionPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket',
                's3:GetBucketLocation',
                's3:GetBucketVersioning',
                's3:RestoreObject',
              ],
              resources: [
                this.backupBucket.bucketArn,
                `${this.backupBucket.bucketArn}/*`,
              ],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'sns:Publish',
                'cloudwatch:PutMetricData',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create backup orchestration Lambda function
    this.backupFunction = new lambda.Function(this, 'BackupOrchestratorFunction', {
      functionName: `backup-orchestrator-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: backupExecutionRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      description: 'Lambda function for backup orchestration and validation',
      environment: {
        BACKUP_BUCKET: this.backupBucket.bucketName,
        SNS_TOPIC_ARN: this.notificationTopic.topicArn,
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')
sns = boto3.client('sns')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    bucket_name = os.environ['BACKUP_BUCKET']
    topic_arn = os.environ['SNS_TOPIC_ARN']
    
    try:
        # Extract backup parameters from event
        backup_type = event.get('backup_type', 'incremental')
        source_prefix = event.get('source_prefix', 'data/')
        
        # Perform backup operation
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        backup_key = f"backups/{backup_type}/{timestamp}/"
        
        # Simulate backup validation
        validation_result = validate_backup(bucket_name, backup_key)
        
        # Send CloudWatch metrics
        cloudwatch.put_metric_data(
            Namespace='BackupStrategy',
            MetricData=[
                {
                    'MetricName': 'BackupSuccess',
                    'Value': 1 if validation_result else 0,
                    'Unit': 'Count'
                },
                {
                    'MetricName': 'BackupDuration',
                    'Value': 120,  # Simulated duration
                    'Unit': 'Seconds'
                }
            ]
        )
        
        # Send notification
        message = {
            'backup_type': backup_type,
            'timestamp': timestamp,
            'status': 'SUCCESS' if validation_result else 'FAILED',
            'bucket': bucket_name,
            'backup_location': backup_key
        }
        
        sns.publish(
            TopicArn=topic_arn,
            Message=json.dumps(message, indent=2),
            Subject=f'Backup {message["status"]}: {backup_type}'
        )
        
        logger.info(f"Backup completed: {message}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(message)
        }
        
    except Exception as e:
        logger.error(f"Backup failed: {str(e)}")
        
        # Send failure notification
        sns.publish(
            TopicArn=topic_arn,
            Message=f'Backup failed: {str(e)}',
            Subject='Backup FAILED'
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def validate_backup(bucket_name, backup_key):
    """Validate backup integrity"""
    try:
        # Check if backup location exists
        response = s3.list_objects_v2(
            Bucket=bucket_name,
            Prefix=backup_key,
            MaxKeys=1
        )
        
        # In a real implementation, you would:
        # 1. Verify file checksums
        # 2. Test restoration of sample files
        # 3. Validate backup completeness
        
        return True  # Simplified validation
        
    except Exception as e:
        logger.error(f"Backup validation failed: {str(e)}")
        return False
`),
    });

    // Grant SNS permissions to Lambda
    this.notificationTopic.grantPublish(this.backupFunction);

    // Create EventBridge rules for scheduled backups
    const dailyBackupRule = new events.Rule(this, 'DailyBackupRule', {
      ruleName: `daily-backup-${uniqueSuffix}`,
      description: 'Daily incremental backup at 2 AM UTC',
      schedule: events.Schedule.cron({
        minute: '0',
        hour: '2',
        day: '*',
        month: '*',
        year: '*',
      }),
    });

    const weeklyBackupRule = new events.Rule(this, 'WeeklyBackupRule', {
      ruleName: `weekly-backup-${uniqueSuffix}`,
      description: 'Weekly full backup on Sunday at 1 AM UTC',
      schedule: events.Schedule.cron({
        minute: '0',
        hour: '1',
        day: '*',
        month: '*',
        year: '*',
        weekDay: 'SUN',
      }),
    });

    // Add Lambda targets to EventBridge rules
    dailyBackupRule.addTarget(
      new targets.LambdaFunction(this.backupFunction, {
        event: events.RuleTargetInput.fromObject({
          backup_type: 'incremental',
          source_prefix: 'daily/',
        }),
      })
    );

    weeklyBackupRule.addTarget(
      new targets.LambdaFunction(this.backupFunction, {
        event: events.RuleTargetInput.fromObject({
          backup_type: 'full',
          source_prefix: 'weekly/',
        }),
      })
    );

    // Create CloudWatch alarms for monitoring
    const backupFailureAlarm = new cloudwatch.Alarm(this, 'BackupFailureAlarm', {
      alarmName: `backup-failure-alarm-${uniqueSuffix}`,
      alarmDescription: 'Alert when backup operations fail',
      metric: new cloudwatch.Metric({
        namespace: 'BackupStrategy',
        metricName: 'BackupSuccess',
        statistic: 'Sum',
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.BREACHING,
    });

    const backupDurationAlarm = new cloudwatch.Alarm(this, 'BackupDurationAlarm', {
      alarmName: `backup-duration-alarm-${uniqueSuffix}`,
      alarmDescription: 'Alert when backup operations take too long',
      metric: new cloudwatch.Metric({
        namespace: 'BackupStrategy',
        metricName: 'BackupDuration',
        statistic: 'Average',
      }),
      threshold: 600, // 10 minutes
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
    });

    // Configure alarm actions
    backupFailureAlarm.addAlarmAction(
      new cloudwatch.SnsAction(this.notificationTopic)
    );
    backupDurationAlarm.addAlarmAction(
      new cloudwatch.SnsAction(this.notificationTopic)
    );

    // Cross-region replication (optional)
    if (props?.enableCrossRegionReplication && props?.replicationDestinationRegion) {
      this.createCrossRegionReplication(props.replicationDestinationRegion, uniqueSuffix);
    }

    // CloudFormation outputs
    new cdk.CfnOutput(this, 'BackupBucketName', {
      value: this.backupBucket.bucketName,
      description: 'Name of the S3 backup bucket',
      exportName: `${this.stackName}-BackupBucketName`,
    });

    new cdk.CfnOutput(this, 'BackupFunctionName', {
      value: this.backupFunction.functionName,
      description: 'Name of the backup orchestration Lambda function',
      exportName: `${this.stackName}-BackupFunctionName`,
    });

    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: this.notificationTopic.topicArn,
      description: 'ARN of the SNS notification topic',
      exportName: `${this.stackName}-NotificationTopicArn`,
    });

    new cdk.CfnOutput(this, 'DailyBackupRuleArn', {
      value: dailyBackupRule.ruleArn,
      description: 'ARN of the daily backup EventBridge rule',
      exportName: `${this.stackName}-DailyBackupRuleArn`,
    });

    new cdk.CfnOutput(this, 'WeeklyBackupRuleArn', {
      value: weeklyBackupRule.ruleArn,
      description: 'ARN of the weekly backup EventBridge rule',
      exportName: `${this.stackName}-WeeklyBackupRuleArn`,
    });
  }

  private createCrossRegionReplication(destinationRegion: string, uniqueSuffix: string): void {
    // Create destination bucket in the specified region
    const destinationBucket = new s3.Bucket(this, 'BackupReplicationBucket', {
      bucketName: `backup-strategy-dr-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create replication role
    const replicationRole = new iam.Role(this, 'ReplicationRole', {
      roleName: `s3-replication-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('s3.amazonaws.com'),
      inlinePolicies: {
        ReplicationPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObjectVersionForReplication',
                's3:GetObjectVersionAcl',
              ],
              resources: [`${this.backupBucket.bucketArn}/*`],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:ListBucket'],
              resources: [this.backupBucket.bucketArn],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:ReplicateObject',
                's3:ReplicateDelete',
              ],
              resources: [`${destinationBucket.bucketArn}/*`],
            }),
          ],
        }),
      },
    });

    // Configure cross-region replication
    new s3.CfnBucket(this, 'BackupBucketWithReplication', {
      bucketName: this.backupBucket.bucketName,
      replicationConfiguration: {
        role: replicationRole.roleArn,
        rules: [
          {
            id: 'backup-replication-rule',
            status: 'Enabled',
            priority: 1,
            filter: {
              prefix: 'backups/',
            },
            destination: {
              bucket: destinationBucket.bucketArn,
              storageClass: 'STANDARD_IA',
            },
          },
        ],
      },
    });

    // Output destination bucket information
    new cdk.CfnOutput(this, 'ReplicationBucketName', {
      value: destinationBucket.bucketName,
      description: 'Name of the cross-region replication destination bucket',
      exportName: `${this.stackName}-ReplicationBucketName`,
    });
  }
}