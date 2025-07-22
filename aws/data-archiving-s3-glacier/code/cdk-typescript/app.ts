#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as iam from 'aws-cdk-lib/aws-iam';

/**
 * Stack for automated data archiving with S3 Glacier
 * This stack creates:
 * - S3 bucket with lifecycle policies for automated archiving
 * - SNS topic for notifications
 * - Appropriate IAM permissions
 */
export class AutomatedDataArchivingStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Get account ID for unique bucket naming
    const accountId = cdk.Stack.of(this).account;
    
    // Create SNS topic for archive notifications
    const archiveNotificationTopic = new sns.Topic(this, 'ArchiveNotificationTopic', {
      topicName: 'archive-notification',
      displayName: 'S3 Archive Notifications',
      description: 'Topic for notifications about S3 archiving operations',
    });

    // Create S3 bucket with lifecycle configuration
    const archiveBucket = new s3.Bucket(this, 'ArchiveBucket', {
      bucketName: `awscookbook-archive-${accountId.slice(0, 8)}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: false,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      
      // Configure lifecycle rules for automated archiving
      lifecycleRules: [
        {
          id: 'ArchiveRule',
          enabled: true,
          
          // Apply rule to objects with 'data/' prefix
          filter: s3.LifecycleFilter.prefix('data/'),
          
          // Transition to Glacier Flexible Retrieval after 90 days
          transitions: [
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
            {
              // Transition to Glacier Deep Archive after 365 days
              storageClass: s3.StorageClass.DEEP_ARCHIVE,
              transitionAfter: cdk.Duration.days(365),
            },
          ],
        },
      ],
      
      // Configure notifications for restore operations
      notifications: [
        {
          destination: archiveNotificationTopic,
          events: [s3.EventType.OBJECT_RESTORE_COMPLETED],
          filters: [
            {
              prefix: 'data/',
            },
          ],
        },
      ],
    });

    // Allow SNS to be called by S3 bucket notifications
    archiveNotificationTopic.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AllowS3Publish',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('s3.amazonaws.com')],
        actions: ['sns:Publish'],
        resources: [archiveNotificationTopic.topicArn],
        conditions: {
          StringEquals: {
            'aws:SourceAccount': accountId,
          },
          ArnEquals: {
            'aws:SourceArn': archiveBucket.bucketArn,
          },
        },
      })
    );

    // Create IAM role for S3 restore operations (demonstration purposes)
    const s3RestoreRole = new iam.Role(this, 'S3RestoreRole', {
      roleName: 'S3ArchiveRestoreRole',
      assumedBy: new iam.ServicePrincipal('s3.amazonaws.com'),
      description: 'Role for S3 restore operations',
      inlinePolicies: {
        S3RestorePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:RestoreObject',
                's3:GetObject',
                's3:GetObjectVersion',
              ],
              resources: [
                archiveBucket.arnForObjects('*'),
              ],
            }),
          ],
        }),
      },
    });

    // Stack outputs
    new cdk.CfnOutput(this, 'BucketName', {
      value: archiveBucket.bucketName,
      description: 'Name of the S3 bucket for archiving',
      exportName: `${this.stackName}-BucketName`,
    });

    new cdk.CfnOutput(this, 'BucketArn', {
      value: archiveBucket.bucketArn,
      description: 'ARN of the S3 bucket for archiving',
      exportName: `${this.stackName}-BucketArn`,
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: archiveNotificationTopic.topicArn,
      description: 'ARN of the SNS topic for archive notifications',
      exportName: `${this.stackName}-SNSTopicArn`,
    });

    new cdk.CfnOutput(this, 'RestoreRoleArn', {
      value: s3RestoreRole.roleArn,
      description: 'ARN of the IAM role for S3 restore operations',
      exportName: `${this.stackName}-RestoreRoleArn`,
    });

    // Tags for all resources
    cdk.Tags.of(this).add('Project', 'AutomatedDataArchiving');
    cdk.Tags.of(this).add('Environment', 'demo');
    cdk.Tags.of(this).add('CostCenter', 'storage-optimization');
  }
}

/**
 * CDK App for automated data archiving with S3 Glacier
 * This application demonstrates best practices for:
 * - Cost-effective long-term data storage
 * - Automated lifecycle management
 * - Notification systems for archive operations
 */
const app = new cdk.App();

// Create the stack with appropriate naming and environment configuration
new AutomatedDataArchivingStack(app, 'AutomatedDataArchivingStack', {
  stackName: 'automated-data-archiving-stack',
  description: 'Stack for automated data archiving with S3 Glacier storage classes',
  
  // Use environment variables or defaults for AWS account and region
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Add stack-level tags
  tags: {
    'Recipe': 'automated-data-archiving-with-s3-glacier',
    'IaC': 'CDK-TypeScript',
    'Version': '1.0',
  },
});

// Enable termination protection for production deployments
// Uncomment the line below for production use
// app.node.setContext('@aws-cdk/core:enableStackNameDuplicates', true);