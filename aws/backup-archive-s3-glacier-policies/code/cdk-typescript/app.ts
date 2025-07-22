#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as sns from 'aws-cdk-lib/aws-sns';
import { Construct } from 'constructs';

/**
 * CDK Stack for implementing comprehensive backup and archive strategies
 * with S3 Glacier and intelligent lifecycle policies
 */
export class BackupArchiveStack extends cdk.Stack {
  public readonly backupBucket: s3.Bucket;
  public readonly glacierOperationsRole: iam.Role;
  public readonly costAlarm: cloudwatch.Alarm;
  public readonly lifecycleTransitionsLogGroup: logs.LogGroup;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // Create S3 bucket for backup and archiving with comprehensive lifecycle policies
    this.backupBucket = new s3.Bucket(this, 'BackupArchiveBucket', {
      bucketName: `backup-archive-demo-${uniqueSuffix}`,
      // Enable versioning for backup integrity and compliance
      versioned: true,
      // Block public access for security
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      // Enforce SSL for data in transit
      enforceSSL: true,
      // Enable server-side encryption with S3 managed keys
      encryption: s3.BucketEncryption.S3_MANAGED,
      // Lifecycle rules for automated data transitions and cost optimization
      lifecycleRules: [
        {
          id: 'backup-archive-strategy',
          enabled: true,
          // Apply to all objects in the backups/ prefix
          filter: s3.LifecycleFilter.prefix('backups/'),
          // Progressive transitions through storage classes for cost optimization
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30)
            },
            {
              storageClass: s3.StorageClass.GLACIER_INSTANT_RETRIEVAL,
              transitionAfter: cdk.Duration.days(90)
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(365)
            },
            {
              storageClass: s3.StorageClass.DEEP_ARCHIVE,
              transitionAfter: cdk.Duration.days(2555) // ~7 years
            }
          ],
          // Handle non-current versions for backup integrity
          noncurrentVersionTransitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(7)
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(30)
            }
          ],
          // Expire non-current versions after 8 years for compliance
          noncurrentVersionExpiration: cdk.Duration.days(2920)
        },
        {
          id: 'logs-retention-policy',
          enabled: true,
          // Apply to log files with shorter retention requirements
          filter: s3.LifecycleFilter.prefix('logs/'),
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(7)
            },
            {
              storageClass: s3.StorageClass.GLACIER_INSTANT_RETRIEVAL,
              transitionAfter: cdk.Duration.days(30)
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90)
            }
          ],
          // Automatically delete log files after 7 years
          expiration: cdk.Duration.days(2555)
        },
        {
          id: 'documents-long-term-archive',
          enabled: true,
          // Apply to documents with specific tags for compliance
          filter: s3.LifecycleFilter.and(
            s3.LifecycleFilter.prefix('documents/'),
            s3.LifecycleFilter.tag('DataClass', 'Archive')
          ),
          transitions: [
            {
              storageClass: s3.StorageClass.GLACIER_INSTANT_RETRIEVAL,
              transitionAfter: cdk.Duration.days(60)
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(180)
            },
            {
              storageClass: s3.StorageClass.DEEP_ARCHIVE,
              transitionAfter: cdk.Duration.days(1095) // ~3 years
            }
          ]
        }
      ],
      // Automatically delete incomplete multipart uploads to reduce costs
      autoDeleteObjects: false, // Set to false for production to prevent accidental data loss
      removalPolicy: cdk.RemovalPolicy.RETAIN // Protect bucket from accidental deletion
    });

    // Create IAM role for Glacier operations with least privilege access
    this.glacierOperationsRole = new iam.Role(this, 'GlacierOperationsRole', {
      roleName: `GlacierOperationsRole-${uniqueSuffix}`,
      description: 'IAM role for secure Glacier lifecycle transitions and restore operations',
      // Allow Glacier service to assume this role
      assumedBy: new iam.ServicePrincipal('glacier.amazonaws.com'),
      // Attach managed policy for S3 operations
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonS3ReadOnlyAccess')
      ],
      // Add inline policy for specific Glacier operations
      inlinePolicies: {
        GlacierOperations: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:RestoreObject',
                's3:GetObjectVersion',
                's3:GetObjectVersionTagging',
                'glacier:InitiateJob',
                'glacier:DescribeJob',
                'glacier:GetJobOutput'
              ],
              resources: [
                this.backupBucket.bucketArn,
                `${this.backupBucket.bucketArn}/*`
              ]
            })
          ]
        })
      }
    });

    // Create CloudWatch Log Group for tracking lifecycle transitions
    this.lifecycleTransitionsLogGroup = new logs.LogGroup(this, 'LifecycleTransitionsLogGroup', {
      logGroupName: '/aws/s3/lifecycle-transitions',
      // Retain logs for compliance and audit purposes
      retention: logs.RetentionDays.ONE_YEAR,
      removalPolicy: cdk.RemovalPolicy.RETAIN
    });

    // Create SNS topic for billing alerts (optional - requires manual subscription)
    const billingAlertsTopic = new sns.Topic(this, 'BillingAlertsTopic', {
      topicName: `billing-alerts-${uniqueSuffix}`,
      displayName: 'S3 Storage Cost Alerts'
    });

    // Create CloudWatch alarm for monitoring S3 storage costs
    this.costAlarm = new cloudwatch.Alarm(this, 'GlacierCostAlarm', {
      alarmName: `glacier-cost-alarm-${uniqueSuffix}`,
      alarmDescription: 'Monitor S3 storage costs to prevent unexpected charges',
      // Monitor estimated charges for S3 service
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Billing',
        metricName: 'EstimatedCharges',
        dimensionsMap: {
          Currency: 'USD',
          ServiceName: 'AmazonS3'
        },
        statistic: 'Maximum',
        period: cdk.Duration.days(1)
      }),
      // Alert when monthly costs exceed $50
      threshold: 50.0,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Add SNS action to the alarm (optional)
    this.costAlarm.addAlarmAction(new cloudwatch.SnsAction(billingAlertsTopic));

    // Output important resource information
    new cdk.CfnOutput(this, 'BackupBucketName', {
      value: this.backupBucket.bucketName,
      description: 'Name of the S3 bucket for backup and archiving'
    });

    new cdk.CfnOutput(this, 'BackupBucketArn', {
      value: this.backupBucket.bucketArn,
      description: 'ARN of the backup bucket'
    });

    new cdk.CfnOutput(this, 'GlacierOperationsRoleArn', {
      value: this.glacierOperationsRole.roleArn,
      description: 'ARN of the IAM role for Glacier operations'
    });

    new cdk.CfnOutput(this, 'CostAlarmName', {
      value: this.costAlarm.alarmName,
      description: 'Name of the CloudWatch alarm monitoring storage costs'
    });

    new cdk.CfnOutput(this, 'LifecycleLogGroupName', {
      value: this.lifecycleTransitionsLogGroup.logGroupName,
      description: 'CloudWatch Log Group for lifecycle transition events'
    });

    new cdk.CfnOutput(this, 'BillingAlertsTopicArn', {
      value: billingAlertsTopic.topicArn,
      description: 'SNS topic ARN for billing alerts (subscribe manually)'
    });

    // Add tags to all resources for cost allocation and governance
    const commonTags = {
      Project: 'BackupArchiveStrategy',
      Environment: 'Demo',
      Purpose: 'CostOptimizedArchiving',
      Compliance: 'DataRetention'
    };

    Object.entries(commonTags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });
  }
}

// CDK App instantiation
const app = new cdk.App();

// Deploy the backup archive stack
new BackupArchiveStack(app, 'BackupArchiveStack', {
  description: 'Comprehensive backup and archive strategy with S3 Glacier and lifecycle policies',
  env: {
    // Use default AWS account and region from CLI/environment
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  }
});

// Synthesize the CloudFormation template
app.synth();