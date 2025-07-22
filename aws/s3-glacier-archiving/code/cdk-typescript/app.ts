#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import {
  aws_s3 as s3,
  aws_sns as sns,
  aws_sns_subscriptions as snsSubscriptions,
  aws_iam as iam,
  CfnOutput,
  Duration,
  RemovalPolicy,
  Stack,
  StackProps
} from 'aws-cdk-lib';
import { Construct } from 'constructs';

/**
 * Properties for the LongTermArchiving stack
 */
export interface LongTermArchivingStackProps extends StackProps {
  /**
   * Email address for archive notifications
   * @default - No email notifications configured
   */
  readonly notificationEmail?: string;
  
  /**
   * Prefix for the S3 bucket name
   * @default 'long-term-archive'
   */
  readonly bucketPrefix?: string;
  
  /**
   * Number of days before transitioning archives folder to Deep Archive
   * @default 90
   */
  readonly archiveFolderTransitionDays?: number;
  
  /**
   * Number of days before transitioning all files to Deep Archive
   * @default 180
   */
  readonly generalTransitionDays?: number;
  
  /**
   * Whether to enable S3 Inventory reporting
   * @default true
   */
  readonly enableInventory?: boolean;
  
  /**
   * File extensions to monitor for notifications (e.g., '.pdf', '.docx')
   * @default ['.pdf']
   */
  readonly monitoredFileExtensions?: string[];
}

/**
 * CDK Stack for S3 Glacier Deep Archive for Long-term Storage
 * 
 * This stack creates:
 * - S3 bucket with lifecycle policies for automatic transition to Glacier Deep Archive
 * - SNS topic and subscription for archive event notifications
 * - S3 inventory configuration for tracking archived objects
 * - Proper IAM permissions for S3 to publish to SNS
 */
export class LongTermArchivingStack extends Stack {
  /**
   * The S3 bucket used for long-term archiving
   */
  public readonly archiveBucket: s3.Bucket;
  
  /**
   * The SNS topic for archive notifications
   */
  public readonly notificationTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: LongTermArchivingStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const bucketPrefix = props.bucketPrefix ?? 'long-term-archive';
    const archiveFolderTransitionDays = props.archiveFolderTransitionDays ?? 90;
    const generalTransitionDays = props.generalTransitionDays ?? 180;
    const enableInventory = props.enableInventory ?? true;
    const monitoredFileExtensions = props.monitoredFileExtensions ?? ['.pdf'];

    // Create SNS topic for archive notifications
    this.notificationTopic = new sns.Topic(this, 'ArchiveNotificationTopic', {
      topicName: `s3-archive-notifications-${this.stackName}`,
      displayName: 'S3 Archive Notifications',
      description: 'Notifications for S3 lifecycle transitions to Glacier Deep Archive'
    });

    // Add email subscription if provided
    if (props.notificationEmail) {
      this.notificationTopic.addSubscription(
        new snsSubscriptions.EmailSubscription(props.notificationEmail)
      );
    }

    // Create the main archival S3 bucket
    this.archiveBucket = new s3.Bucket(this, 'ArchiveBucket', {
      bucketName: `${bucketPrefix}-${this.account}-${this.region}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: RemovalPolicy.RETAIN, // Protect against accidental deletion
      
      // Configure lifecycle rules for automatic archiving
      lifecycleRules: [
        {
          id: 'MoveArchivesToGlacierDeepArchive',
          enabled: true,
          prefix: 'archives/',
          transitions: [
            {
              storageClass: s3.StorageClass.DEEP_ARCHIVE,
              transitionAfter: Duration.days(archiveFolderTransitionDays)
            }
          ]
        },
        {
          id: 'MoveAllFilesToGlacierDeepArchive',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.DEEP_ARCHIVE,
              transitionAfter: Duration.days(generalTransitionDays)
            }
          ]
        }
      ],

      // Configure event notifications for lifecycle transitions
      eventBridgeEnabled: true,
      notifications: this.createNotificationTargets(monitoredFileExtensions)
    });

    // Configure S3 Inventory if enabled
    if (enableInventory) {
      this.configureInventory();
    }

    // Grant necessary permissions for S3 to publish to SNS
    this.grantS3PublishPermissions();

    // Create outputs for important resources
    this.createOutputs();
  }

  /**
   * Creates notification targets for S3 events
   */
  private createNotificationTargets(fileExtensions: string[]): s3.NotificationKeyFilter[] {
    return fileExtensions.map(extension => ({
      suffix: extension
    }));
  }

  /**
   * Configures S3 Inventory for the archive bucket
   */
  private configureInventory(): void {
    try {
      // Create inventory configuration using L1 construct for full control
      new s3.CfnBucket.InventoryConfigurationProperty(this, 'WeeklyInventory', {
        id: 'Weekly-Inventory',
        destination: {
          bucketArn: this.archiveBucket.bucketArn,
          format: 'CSV',
          prefix: 'inventory-reports'
        },
        enabled: true,
        includedObjectVersions: 'Current',
        scheduleFrequency: 'Weekly',
        optionalFields: [
          'Size',
          'LastModifiedDate',
          'StorageClass',
          'ETag',
          'ReplicationStatus'
        ]
      });
    } catch (error) {
      console.warn('Could not configure S3 Inventory directly through CDK. Configure manually if needed:', error);
    }
  }

  /**
   * Grants S3 permissions to publish to the SNS topic
   */
  private grantS3PublishPermissions(): void {
    // Create policy statement for S3 to publish to SNS
    const s3ServicePrincipal = new iam.ServicePrincipal('s3.amazonaws.com');
    
    this.notificationTopic.addToResourcePolicy(new iam.PolicyStatement({
      sid: 'AllowS3Publish',
      effect: iam.Effect.ALLOW,
      principals: [s3ServicePrincipal],
      actions: ['sns:Publish'],
      resources: [this.notificationTopic.topicArn],
      conditions: {
        StringEquals: {
          'aws:SourceAccount': this.account
        },
        StringLike: {
          'aws:SourceArn': `${this.archiveBucket.bucketArn}*`
        }
      }
    }));
  }

  /**
   * Creates CloudFormation outputs for key resources
   */
  private createOutputs(): void {
    new CfnOutput(this, 'ArchiveBucketName', {
      value: this.archiveBucket.bucketName,
      description: 'Name of the S3 bucket for long-term archiving',
      exportName: `${this.stackName}-ArchiveBucketName`
    });

    new CfnOutput(this, 'ArchiveBucketArn', {
      value: this.archiveBucket.bucketArn,
      description: 'ARN of the S3 bucket for long-term archiving',
      exportName: `${this.stackName}-ArchiveBucketArn`
    });

    new CfnOutput(this, 'NotificationTopicArn', {
      value: this.notificationTopic.topicArn,
      description: 'ARN of the SNS topic for archive notifications',
      exportName: `${this.stackName}-NotificationTopicArn`
    });

    new CfnOutput(this, 'BucketWebsiteUrl', {
      value: `https://${this.archiveBucket.bucketName}.s3.${this.region}.amazonaws.com`,
      description: 'S3 bucket URL for management operations'
    });
  }
}

/**
 * Main CDK application
 */
class LongTermArchivingApp extends cdk.App {
  constructor() {
    super();

    // Get configuration from context or environment variables
    const notificationEmail = this.node.tryGetContext('notificationEmail') || 
                             process.env.NOTIFICATION_EMAIL;
    
    const bucketPrefix = this.node.tryGetContext('bucketPrefix') || 
                        process.env.BUCKET_PREFIX || 
                        'long-term-archive';

    const archiveFolderTransitionDays = Number(
      this.node.tryGetContext('archiveFolderTransitionDays') || 
      process.env.ARCHIVE_FOLDER_TRANSITION_DAYS || 
      '90'
    );

    const generalTransitionDays = Number(
      this.node.tryGetContext('generalTransitionDays') || 
      process.env.GENERAL_TRANSITION_DAYS || 
      '180'
    );

    const enableInventory = (
      this.node.tryGetContext('enableInventory') || 
      process.env.ENABLE_INVENTORY || 
      'true'
    ).toLowerCase() === 'true';

    // Parse monitored file extensions from context or environment
    const monitoredExtensionsStr = this.node.tryGetContext('monitoredFileExtensions') || 
                                  process.env.MONITORED_FILE_EXTENSIONS || 
                                  '.pdf';
    const monitoredFileExtensions = monitoredExtensionsStr.split(',').map(ext => ext.trim());

    // Create the stack
    new LongTermArchivingStack(this, 'LongTermArchivingStack', {
      notificationEmail,
      bucketPrefix,
      archiveFolderTransitionDays,
      generalTransitionDays,
      enableInventory,
      monitoredFileExtensions,
      
      // Use environment-specific naming
      stackName: `long-term-archiving-${this.node.tryGetContext('environment') || 'dev'}`,
      
      description: 'Long-term data archiving solution using S3 Glacier Deep Archive with automated lifecycle policies and monitoring',
      
      tags: {
        Project: 'LongTermArchiving',
        Purpose: 'DataRetention',
        CostCenter: 'Storage',
        Environment: this.node.tryGetContext('environment') || 'dev',
        Recipe: 'long-term-data-archiving-s3-glacier'
      }
    });
  }
}

// Instantiate and run the CDK application
new LongTermArchivingApp();