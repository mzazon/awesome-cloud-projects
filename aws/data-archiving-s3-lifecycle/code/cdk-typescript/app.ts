#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';

/**
 * Props for the DataArchivingStack
 */
interface DataArchivingStackProps extends cdk.StackProps {
  bucketName?: string;
  enableBillingAlerts?: boolean;
  billingThreshold?: number;
  objectCountThreshold?: number;
}

/**
 * CDK Stack that implements S3 Lifecycle Policies for data archiving
 * 
 * This stack creates:
 * - S3 bucket with versioning enabled
 * - Comprehensive lifecycle policies for different data types
 * - Intelligent tiering configuration
 * - S3 Analytics and Inventory configurations
 * - CloudWatch monitoring and alarms
 * - IAM roles for lifecycle management
 */
class DataArchivingStack extends cdk.Stack {
  public readonly bucket: s3.Bucket;
  public readonly lifecycleRole: iam.Role;

  constructor(scope: Construct, id: string, props: DataArchivingStackProps = {}) {
    super(scope, id, props);

    // Generate unique suffix for resources
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);
    const bucketName = props.bucketName || `data-archiving-demo-${uniqueSuffix}`;

    // Create S3 bucket with versioning and lifecycle management
    this.bucket = new s3.Bucket(this, 'DataArchivingBucket', {
      bucketName: bucketName,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      // Enable S3 Inventory
      inventories: [
        {
          id: 'StorageInventoryConfig',
          enabled: true,
          destination: {
            bucket: undefined, // Will be set to self after bucket creation
            prefix: 'inventory-reports/',
            format: s3.InventoryFormat.CSV,
          },
          frequency: s3.InventoryFrequency.DAILY,
          includeObjectVersions: s3.InventoryObjectVersion.CURRENT,
          optionalFields: [
            s3.InventoryObjectAttribute.SIZE,
            s3.InventoryObjectAttribute.LAST_MODIFIED_DATE,
            s3.InventoryObjectAttribute.STORAGE_CLASS,
            s3.InventoryObjectAttribute.INTELLIGENT_TIERING_ACCESS_TIER,
          ],
        },
      ],
      // Comprehensive lifecycle rules for different data types
      lifecycleRules: [
        {
          id: 'DocumentArchiving',
          enabled: true,
          prefix: 'documents/',
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
        },
        {
          id: 'LogArchiving',
          enabled: true,
          prefix: 'logs/',
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(7),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.DEEP_ARCHIVE,
              transitionAfter: cdk.Duration.days(90),
            },
          ],
          expiration: cdk.Duration.days(2555), // 7 years retention
        },
        {
          id: 'BackupArchiving',
          enabled: true,
          prefix: 'backups/',
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(1),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(30),
            },
          ],
        },
        {
          id: 'MediaIntelligentTiering',
          enabled: true,
          prefix: 'media/',
          transitions: [
            {
              storageClass: s3.StorageClass.INTELLIGENT_TIERING,
              transitionAfter: cdk.Duration.days(0),
            },
          ],
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Set inventory destination to the bucket itself
    const cfnBucket = this.bucket.node.defaultChild as s3.CfnBucket;
    cfnBucket.addPropertyOverride('InventoryConfigurations.0.Destination.S3BucketDestination.Bucket', this.bucket.bucketArn);

    // Create Intelligent Tiering Configuration
    new s3.CfnBucket.IntelligentTieringConfiguration(this, 'MediaIntelligentTieringConfig', {
      bucket: this.bucket.bucketName,
      id: 'MediaIntelligentTieringConfig',
      status: 'Enabled',
      prefix: 'media/',
      tierings: [
        {
          accessTier: 'ARCHIVE_ACCESS',
          days: 90,
        },
        {
          accessTier: 'DEEP_ARCHIVE_ACCESS',
          days: 180,
        },
      ],
    });

    // Create S3 Analytics Configuration for documents
    new s3.CfnBucket.AnalyticsConfiguration(this, 'DocumentAnalytics', {
      bucket: this.bucket.bucketName,
      id: 'DocumentAnalytics',
      prefix: 'documents/',
      storageClassAnalysis: {
        dataExport: {
          destination: {
            bucketArn: this.bucket.bucketArn,
            prefix: 'analytics-reports/documents/',
            format: 'CSV',
          },
          outputSchemaVersion: 'V_1',
        },
      },
    });

    // Create IAM role for lifecycle management automation
    this.lifecycleRole = new iam.Role(this, 'S3LifecycleRole', {
      roleName: `S3LifecycleRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('s3.amazonaws.com'),
      description: 'Role for S3 lifecycle management operations',
      inlinePolicies: {
        LifecycleManagementPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetBucketLocation',
                's3:GetBucketLifecycleConfiguration',
                's3:PutBucketLifecycleConfiguration',
                's3:GetBucketVersioning',
                's3:GetBucketIntelligentTieringConfiguration',
                's3:PutBucketIntelligentTieringConfiguration',
              ],
              resources: ['*'],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:GetObjectVersion',
                's3:ListBucket',
              ],
              resources: [
                this.bucket.bucketArn,
                `${this.bucket.bucketArn}/*`,
              ],
            }),
          ],
        }),
      },
    });

    // Create SNS topic for billing alerts (optional)
    let billingTopic: sns.Topic | undefined;
    if (props.enableBillingAlerts) {
      billingTopic = new sns.Topic(this, 'BillingAlertsTopic', {
        topicName: `S3-Billing-Alerts-${uniqueSuffix}`,
        displayName: 'S3 Storage Billing Alerts',
      });
    }

    // Create CloudWatch alarms for monitoring
    this.createCloudWatchAlarms({
      bucketName: this.bucket.bucketName,
      billingThreshold: props.billingThreshold || 10.0,
      objectCountThreshold: props.objectCountThreshold || 1000,
      billingTopic: billingTopic,
      uniqueSuffix: uniqueSuffix,
    });

    // Stack outputs
    new cdk.CfnOutput(this, 'BucketName', {
      value: this.bucket.bucketName,
      description: 'Name of the S3 bucket with lifecycle policies',
    });

    new cdk.CfnOutput(this, 'BucketArn', {
      value: this.bucket.bucketArn,
      description: 'ARN of the S3 bucket',
    });

    new cdk.CfnOutput(this, 'LifecycleRoleArn', {
      value: this.lifecycleRole.roleArn,
      description: 'ARN of the IAM role for lifecycle management',
    });

    new cdk.CfnOutput(this, 'SampleUploadCommands', {
      value: [
        `# Upload sample documents:`,
        `aws s3 cp sample-doc.txt s3://${this.bucket.bucketName}/documents/`,
        `# Upload sample logs:`,
        `aws s3 cp sample-log.log s3://${this.bucket.bucketName}/logs/`,
        `# Upload sample backups:`,
        `aws s3 cp sample-backup.sql s3://${this.bucket.bucketName}/backups/`,
        `# Upload sample media:`,
        `aws s3 cp sample-video.mp4 s3://${this.bucket.bucketName}/media/`,
      ].join('\n'),
      description: 'Sample commands to upload test data to different prefixes',
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'DataArchivingSolutions');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('Purpose', 'S3LifecyclePolicies');
  }

  /**
   * Create CloudWatch alarms for monitoring S3 storage
   */
  private createCloudWatchAlarms(params: {
    bucketName: string;
    billingThreshold: number;
    objectCountThreshold: number;
    billingTopic?: sns.Topic;
    uniqueSuffix: string;
  }): void {
    // Storage cost alarm (requires billing metrics to be enabled)
    try {
      const storageAlarm = new cloudwatch.Alarm(this, 'StorageCostAlarm', {
        alarmName: `S3-Storage-Cost-${params.bucketName}`,
        alarmDescription: 'Monitor S3 storage costs',
        metric: new cloudwatch.Metric({
          namespace: 'AWS/Billing',
          metricName: 'EstimatedCharges',
          dimensionsMap: {
            Currency: 'USD',
            ServiceName: 'AmazonS3',
          },
          statistic: 'Maximum',
          period: cdk.Duration.days(1),
        }),
        threshold: params.billingThreshold,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        evaluationPeriods: 1,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      });

      if (params.billingTopic) {
        storageAlarm.addAlarmAction(
          new cloudwatch.SnsAction(params.billingTopic)
        );
      }
    } catch (error) {
      // Billing metrics might not be available in all regions
      console.warn('Could not create billing alarm:', error);
    }

    // Object count alarm
    const objectCountAlarm = new cloudwatch.Alarm(this, 'ObjectCountAlarm', {
      alarmName: `S3-Object-Count-${params.bucketName}`,
      alarmDescription: 'Monitor S3 object count',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/S3',
        metricName: 'NumberOfObjects',
        dimensionsMap: {
          BucketName: params.bucketName,
          StorageType: 'AllStorageTypes',
        },
        statistic: 'Average',
        period: cdk.Duration.days(1),
      }),
      threshold: params.objectCountThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Bucket size alarm
    const bucketSizeAlarm = new cloudwatch.Alarm(this, 'BucketSizeAlarm', {
      alarmName: `S3-Bucket-Size-${params.bucketName}`,
      alarmDescription: 'Monitor S3 bucket size',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/S3',
        metricName: 'BucketSizeBytes',
        dimensionsMap: {
          BucketName: params.bucketName,
          StorageType: 'StandardStorage',
        },
        statistic: 'Average',
        period: cdk.Duration.days(1),
      }),
      threshold: 1073741824, // 1 GB in bytes
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Output alarm ARNs
    new cdk.CfnOutput(this, 'ObjectCountAlarmArn', {
      value: objectCountAlarm.alarmArn,
      description: 'ARN of the object count CloudWatch alarm',
    });

    new cdk.CfnOutput(this, 'BucketSizeAlarmArn', {
      value: bucketSizeAlarm.alarmArn,
      description: 'ARN of the bucket size CloudWatch alarm',
    });
  }
}

/**
 * Main CDK application
 */
const app = new cdk.App();

// Get configuration from context or environment variables
const bucketName = app.node.tryGetContext('bucketName') || process.env.BUCKET_NAME;
const enableBillingAlerts = app.node.tryGetContext('enableBillingAlerts') === 'true' || 
                           process.env.ENABLE_BILLING_ALERTS === 'true';
const billingThreshold = Number(app.node.tryGetContext('billingThreshold')) || 
                        Number(process.env.BILLING_THRESHOLD) || 10.0;
const objectCountThreshold = Number(app.node.tryGetContext('objectCountThreshold')) || 
                            Number(process.env.OBJECT_COUNT_THRESHOLD) || 1000;

// Create the stack
new DataArchivingStack(app, 'DataArchivingStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
  },
  description: 'Data Archiving Solutions with S3 Lifecycle Policies - CDK TypeScript implementation',
  bucketName: bucketName,
  enableBillingAlerts: enableBillingAlerts,
  billingThreshold: billingThreshold,
  objectCountThreshold: objectCountThreshold,
  tags: {
    Project: 'DataArchivingSolutions',
    Environment: 'Demo',
    IaCTool: 'CDK-TypeScript',
  },
});

// Synthesize the app
app.synth();