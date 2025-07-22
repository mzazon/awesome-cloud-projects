import * as cdk from 'aws-cdk-lib';
import * as backup from 'aws-cdk-lib/aws-backup';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import { Construct } from 'constructs';

export interface MultiRegionBackupStackProps extends cdk.StackProps {
  readonly isPrimaryRegion: boolean;
  readonly primaryRegion: string;
  readonly secondaryRegion: string;
  readonly tertiaryRegion: string;
  readonly organizationName: string;
  readonly notificationEmail: string;
}

export class MultiRegionBackupStack extends cdk.Stack {
  public readonly backupVault: backup.BackupVault;
  public readonly backupPlan?: backup.BackupPlan;
  public readonly notificationTopic: sns.Topic;
  public readonly validatorFunction: lambda.Function;

  constructor(scope: Construct, id: string, props: MultiRegionBackupStackProps) {
    super(scope, id, props);

    // Create KMS key for backup encryption
    const backupKey = new cdk.aws_kms.Key(this, 'BackupKey', {
      description: `Backup encryption key for ${props.organizationName} in ${this.region}`,
      enableKeyRotation: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    backupKey.addAlias(`alias/${props.organizationName}-backup-key-${this.region}`);

    // Create backup vault with encryption
    const vaultName = `${props.organizationName}-${props.isPrimaryRegion ? 'primary' : 
      this.region === props.secondaryRegion ? 'secondary' : 'tertiary'}-vault`;
    
    this.backupVault = new backup.BackupVault(this, 'BackupVault', {
      backupVaultName: vaultName,
      encryptionKey: backupKey,
      accessPolicy: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            effect: iam.Effect.DENY,
            principals: [new iam.AnyPrincipal()],
            actions: ['backup:DeleteBackupVault', 'backup:DeleteBackupVaultAccessPolicy'],
            resources: ['*'],
            conditions: {
              Bool: {
                'aws:SecureTransport': 'false'
              }
            }
          })
        ]
      }),
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    // Create SNS topic for notifications
    this.notificationTopic = new sns.Topic(this, 'BackupNotificationTopic', {
      topicName: `backup-notifications-${this.region}`,
      displayName: `Backup Notifications for ${this.region}`,
    });

    // Subscribe email to SNS topic
    this.notificationTopic.addSubscription(
      new subscriptions.EmailSubscription(props.notificationEmail)
    );

    // Create IAM role for AWS Backup service
    const backupServiceRole = new iam.Role(this, 'BackupServiceRole', {
      roleName: `AWSBackupServiceRole-${this.region}`,
      assumedBy: new iam.ServicePrincipal('backup.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSBackupServiceRolePolicyForBackup'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSBackupServiceRolePolicyForRestores'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSBackupServiceRolePolicyForS3Backup'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSBackupServiceRolePolicyForS3Restore'),
      ],
    });

    // Create backup plan only in primary region to avoid conflicts
    if (props.isPrimaryRegion) {
      this.createBackupPlan(props, backupServiceRole);
    }

    // Create Lambda function for backup validation
    this.validatorFunction = this.createValidatorFunction(props);

    // Create EventBridge rules for backup monitoring
    this.createEventBridgeRules();

    // Output important information
    new cdk.CfnOutput(this, 'BackupVaultName', {
      value: this.backupVault.backupVaultName,
      description: 'Name of the backup vault',
      exportName: `${this.stackName}-BackupVaultName`,
    });

    new cdk.CfnOutput(this, 'BackupVaultArn', {
      value: this.backupVault.backupVaultArn,
      description: 'ARN of the backup vault',
      exportName: `${this.stackName}-BackupVaultArn`,
    });

    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: this.notificationTopic.topicArn,
      description: 'ARN of the notification topic',
      exportName: `${this.stackName}-NotificationTopicArn`,
    });

    if (this.backupPlan) {
      new cdk.CfnOutput(this, 'BackupPlanId', {
        value: this.backupPlan.backupPlanId,
        description: 'ID of the backup plan',
        exportName: `${this.stackName}-BackupPlanId`,
      });
    }
  }

  private createBackupPlan(props: MultiRegionBackupStackProps, serviceRole: iam.Role): void {
    // Define cross-region copy destinations
    const secondaryVaultArn = `arn:aws:backup:${props.secondaryRegion}:${this.account}:backup-vault:${props.organizationName}-secondary-vault`;
    const tertiaryVaultArn = `arn:aws:backup:${props.tertiaryRegion}:${this.account}:backup-vault:${props.organizationName}-tertiary-vault`;

    this.backupPlan = new backup.BackupPlan(this, 'BackupPlan', {
      backupPlanName: 'MultiRegionBackupPlan',
      backupPlanRules: [
        // Daily backup rule with cross-region copy to secondary region
        new backup.BackupPlanRule({
          ruleName: 'DailyBackupsWithCrossRegionCopy',
          backupVault: this.backupVault,
          scheduleExpression: events.Schedule.cron({
            hour: '2',
            minute: '0',
          }),
          startWindow: cdk.Duration.hours(8),
          completionWindow: cdk.Duration.hours(168), // 7 days
          lifecycle: {
            moveToColdStorageAfter: cdk.Duration.days(30),
            deleteAfter: cdk.Duration.days(365),
          },
          copyActions: [
            {
              destinationBackupVault: backup.BackupVault.fromBackupVaultArn(
                this,
                'SecondaryVaultReference',
                secondaryVaultArn
              ),
              lifecycle: {
                moveToColdStorageAfter: cdk.Duration.days(30),
                deleteAfter: cdk.Duration.days(365),
              },
            },
          ],
          recoveryPointTags: {
            BackupType: 'Daily',
            Environment: 'Production',
            CrossRegion: 'true',
          },
        }),
        // Weekly backup rule with long-term archival in tertiary region
        new backup.BackupPlanRule({
          ruleName: 'WeeklyLongTermArchival',
          backupVault: this.backupVault,
          scheduleExpression: events.Schedule.cron({
            hour: '3',
            minute: '0',
            weekDay: 'SUN',
          }),
          startWindow: cdk.Duration.hours(8),
          completionWindow: cdk.Duration.hours(168), // 7 days
          lifecycle: {
            moveToColdStorageAfter: cdk.Duration.days(90),
            deleteAfter: cdk.Duration.days(2555), // 7 years
          },
          copyActions: [
            {
              destinationBackupVault: backup.BackupVault.fromBackupVaultArn(
                this,
                'TertiaryVaultReference',
                tertiaryVaultArn
              ),
              lifecycle: {
                moveToColdStorageAfter: cdk.Duration.days(90),
                deleteAfter: cdk.Duration.days(2555), // 7 years
              },
            },
          ],
          recoveryPointTags: {
            BackupType: 'Weekly',
            Environment: 'Production',
            LongTerm: 'true',
          },
        }),
      ],
    });

    // Create backup selection based on tags
    new backup.BackupSelection(this, 'BackupSelection', {
      backupPlan: this.backupPlan,
      selectionName: 'ProductionResourcesSelection',
      role: serviceRole,
      resources: [
        backup.BackupResource.fromArn('*'), // All resources
      ],
      conditions: {
        stringEquals: {
          'aws:ResourceTag/Environment': ['Production'],
          'aws:ResourceTag/BackupEnabled': ['true'],
        },
      },
    });
  }

  private createValidatorFunction(props: MultiRegionBackupStackProps): lambda.Function {
    // Create IAM role for Lambda function
    const lambdaRole = new iam.Role(this, 'ValidatorFunctionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        BackupValidatorPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'backup:DescribeBackupJob',
                'backup:ListCopyJobs',
                'backup:DescribeRecoveryPoint',
                'sns:Publish',
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Lambda function code
    const functionCode = `import json
import boto3
import logging
import os
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    backup_client = boto3.client('backup')
    sns_client = boto3.client('sns')
    
    # Extract backup job details from EventBridge event
    detail = event['detail']
    backup_job_id = detail['backupJobId']
    
    try:
        # Get backup job details
        response = backup_client.describe_backup_job(
            BackupJobId=backup_job_id
        )
        
        backup_job = response['BackupJob']
        
        # Validate backup job completion and health
        if backup_job['State'] in ['COMPLETED']:
            # Perform additional validation checks
            recovery_point_arn = backup_job['RecoveryPointArn']
            
            # Check if cross-region copy was successful
            copy_jobs = backup_client.list_copy_jobs()
            
            message = f"Backup validation successful for job {backup_job_id}"
            logger.info(message)
            
        elif backup_job['State'] in ['FAILED', 'ABORTED']:
            message = f"Backup job {backup_job_id} failed: {backup_job.get('StatusMessage', 'Unknown error')}"
            logger.error(message)
            
            # Send SNS notification for failed jobs
            sns_client.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Subject='AWS Backup Job Failed',
                Message=message
            )
    
    except Exception as e:
        logger.error(f"Error validating backup job: {str(e)}")
        raise
    
    return {
        'statusCode': 200,
        'body': json.dumps('Backup validation completed')
    }`;

    return new lambda.Function(this, 'ValidatorFunction', {
      functionName: `backup-validator-${this.region}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(functionCode),
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      environment: {
        SNS_TOPIC_ARN: this.notificationTopic.topicArn,
        REGION: this.region,
      },
      description: 'Validates backup jobs and sends notifications on failures',
    });
  }

  private createEventBridgeRules(): void {
    // EventBridge rule for backup job failures
    const backupFailureRule = new events.Rule(this, 'BackupJobFailureRule', {
      ruleName: `BackupJobFailureRule-${this.region}`,
      description: 'Captures backup job failures and triggers validation',
      eventPattern: {
        source: ['aws.backup'],
        detailType: ['Backup Job State Change'],
        detail: {
          state: ['FAILED', 'ABORTED'],
        },
      },
    });

    // EventBridge rule for backup job completions
    const backupCompletionRule = new events.Rule(this, 'BackupJobCompletionRule', {
      ruleName: `BackupJobCompletionRule-${this.region}`,
      description: 'Captures backup job completions for validation',
      eventPattern: {
        source: ['aws.backup'],
        detailType: ['Backup Job State Change'],
        detail: {
          state: ['COMPLETED'],
        },
      },
    });

    // Add Lambda function as target for both rules
    backupFailureRule.addTarget(new targets.LambdaFunction(this.validatorFunction));
    backupCompletionRule.addTarget(new targets.LambdaFunction(this.validatorFunction));

    // Grant EventBridge permission to invoke Lambda
    this.validatorFunction.addPermission('AllowEventBridgeInvocation', {
      principal: new iam.ServicePrincipal('events.amazonaws.com'),
      sourceArn: backupFailureRule.ruleArn,
    });

    this.validatorFunction.addPermission('AllowEventBridgeCompletionInvocation', {
      principal: new iam.ServicePrincipal('events.amazonaws.com'),
      sourceArn: backupCompletionRule.ruleArn,
    });
  }
}