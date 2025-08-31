#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as s3Notifications from 'aws-cdk-lib/aws-s3-notifications';
import * as iam from 'aws-cdk-lib/aws-iam';

/**
 * Stack for Simple File Backup Notifications with S3 and SNS
 * 
 * This stack creates:
 * - S3 bucket with versioning and encryption enabled for backup storage
 * - SNS topic for notifications
 * - Email subscription to SNS topic
 * - S3 event notifications configured to trigger on object creation
 * - Proper IAM permissions for S3 to publish to SNS
 */
export class SimpleFileBackupNotificationsStack extends cdk.Stack {
  public readonly backupBucket: s3.Bucket;
  public readonly notificationTopic: sns.Topic;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate a unique suffix for resource names to avoid conflicts
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // Create SNS topic for backup notifications
    this.notificationTopic = new sns.Topic(this, 'BackupNotificationTopic', {
      topicName: `backup-alerts-${uniqueSuffix}`,
      displayName: 'File Backup Notifications',
      description: 'Notifications for file uploads to backup S3 bucket',
    });

    // Add email subscription to SNS topic
    // Note: Email address should be provided as context variable or parameter
    const emailAddress = this.node.tryGetContext('emailAddress') || 'admin@example.com';
    
    this.notificationTopic.addSubscription(
      new snsSubscriptions.EmailSubscription(emailAddress)
    );

    // Create S3 bucket for backup files with security best practices
    this.backupBucket = new s3.Bucket(this, 'BackupBucket', {
      bucketName: `backup-notifications-${uniqueSuffix}`,
      // Enable versioning for data protection
      versioned: true,
      // Enable server-side encryption with S3 managed keys
      encryption: s3.BucketEncryption.S3_MANAGED,
      // Block all public access for security
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      // Enable event bridge notifications (optional - can be used for additional integrations)
      eventBridgeEnabled: false,
      // Set lifecycle policy to optimize costs
      lifecycleRules: [
        {
          id: 'OptimizeStorage',
          enabled: true,
          // Transition to IA after 30 days
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
          ],
        },
      ],
      // Enable removal policy for cleanup (use RETAIN for production)
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      // Automatically delete objects when stack is destroyed (for demo purposes)
      autoDeleteObjects: true,
    });

    // Configure S3 event notifications to trigger SNS on object creation
    this.backupBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3Notifications.SnsDestination(this.notificationTopic)
    );

    // Add additional notification for object removal (optional)
    this.backupBucket.addEventNotification(
      s3.EventType.OBJECT_REMOVED,
      new s3Notifications.SnsDestination(this.notificationTopic)
    );

    // Create IAM policy for S3 to publish to SNS (handled automatically by CDK)
    // The CDK automatically creates the necessary permissions when using SnsDestination

    // Add tags to all resources for better management
    cdk.Tags.of(this).add('Project', 'SimpleFileBackupNotifications');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('Owner', 'IT-Team');

    // Output important information
    new cdk.CfnOutput(this, 'BucketName', {
      value: this.backupBucket.bucketName,
      description: 'Name of the S3 backup bucket',
      exportName: `${this.stackName}-BucketName`,
    });

    new cdk.CfnOutput(this, 'BucketArn', {
      value: this.backupBucket.bucketArn,
      description: 'ARN of the S3 backup bucket',
      exportName: `${this.stackName}-BucketArn`,
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: this.notificationTopic.topicArn,
      description: 'ARN of the SNS notification topic',
      exportName: `${this.stackName}-SNSTopicArn`,
    });

    new cdk.CfnOutput(this, 'EmailSubscription', {
      value: emailAddress,
      description: 'Email address subscribed to notifications',
    });

    new cdk.CfnOutput(this, 'TestUploadCommand', {
      value: `aws s3 cp test-file.txt s3://${this.backupBucket.bucketName}/`,
      description: 'Sample command to test notifications',
    });
  }
}

/**
 * CDK App definition
 * 
 * This creates the CDK application and instantiates the stack.
 * The stack can be customized through context variables.
 */
export class SimpleFileBackupNotificationsApp extends cdk.App {
  constructor() {
    super();

    // Get deployment configuration from context or use defaults
    const account = this.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT;
    const region = this.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION || 'us-east-1';
    const emailAddress = this.node.tryGetContext('emailAddress');

    // Validate email address is provided
    if (!emailAddress) {
      console.warn('⚠️  No email address provided. Using default admin@example.com');
      console.warn('   Set email address with: cdk deploy -c emailAddress=your-email@domain.com');
    }

    // Create the stack with proper environment configuration
    const stack = new SimpleFileBackupNotificationsStack(this, 'SimpleFileBackupNotificationsStack', {
      env: {
        account: account,
        region: region,
      },
      description: 'Simple File Backup Notifications with S3 and SNS (uksb-1tupboc57)',
      stackName: 'simple-file-backup-notifications',
    });

    // Add stack-level tags
    cdk.Tags.of(stack).add('CDKVersion', cdk.App.VERSION);
    cdk.Tags.of(stack).add('CreatedBy', 'AWS CDK');
  }
}

// Instantiate and run the CDK application
const app = new SimpleFileBackupNotificationsApp();

// Enable termination protection for production deployments
// app.node.setContext('@aws-cdk/core:enableStackNameDuplicates', true);

export default app;