import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudtrail from 'aws-cdk-lib/aws-cloudtrail';
import { Construct } from 'constructs';

/**
 * Interface defining the properties for the Disaster Recovery S3 Stack
 */
export interface DisasterRecoveryS3StackProps extends cdk.StackProps {
  readonly isPrimaryStack: boolean;
  readonly primaryRegion: string;
  readonly drRegion: string;
  readonly bucketPrefix: string;
  readonly enableCloudTrail: boolean;
  readonly enableMonitoring: boolean;
  readonly sourceBucketArn?: string;
  readonly replicationRoleArn?: string;
}

/**
 * CDK Stack for S3 Cross-Region Replication Disaster Recovery
 * 
 * This stack implements a comprehensive disaster recovery solution using S3 Cross-Region 
 * Replication with the following components:
 * 
 * Primary Stack (Source Region):
 * - Source S3 bucket with versioning and replication configuration
 * - IAM role for cross-region replication with least privilege permissions
 * - CloudWatch monitoring and alarms for replication metrics
 * - CloudTrail for audit logging and compliance
 * - SNS topic for alert notifications
 * 
 * DR Stack (Destination Region):
 * - Destination S3 bucket with versioning enabled
 * - CloudWatch monitoring for destination metrics
 * - Optional CloudTrail for destination region audit logs
 */
export class DisasterRecoveryS3Stack extends cdk.Stack {
  public readonly sourceBucketArn: string;
  public readonly destinationBucketArn: string;
  public readonly replicationRoleArn: string;
  public readonly snsTopicArn: string;

  constructor(scope: Construct, id: string, props: DisasterRecoveryS3StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();
    const stackType = props.isPrimaryStack ? 'source' : 'destination';

    if (props.isPrimaryStack) {
      // ===== PRIMARY STACK RESOURCES =====
      
      // Create source S3 bucket with versioning and security configurations
      const sourceBucket = new s3.Bucket(this, 'SourceBucket', {
        bucketName: `${props.bucketPrefix}-source-${uniqueSuffix}`,
        versioned: true,
        blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
        encryption: s3.BucketEncryption.S3_MANAGED,
        lifecycleRules: [
          {
            id: 'DeleteIncompleteMultipartUploads',
            abortIncompleteMultipartUploadAfter: cdk.Duration.days(1),
            enabled: true,
          },
          {
            id: 'TransitionToIA',
            transitions: [
              {
                storageClass: s3.StorageClass.INFREQUENT_ACCESS,
                transitionAfter: cdk.Duration.days(30),
              },
            ],
            enabled: true,
          },
        ],
        enforceSSL: true,
        removalPolicy: cdk.RemovalPolicy.RETAIN, // Prevent accidental deletion
      });

      // Create IAM role for S3 Cross-Region Replication
      const replicationRole = new iam.Role(this, 'ReplicationRole', {
        roleName: `s3-replication-role-${uniqueSuffix}`,
        assumedBy: new iam.ServicePrincipal('s3.amazonaws.com'),
        description: 'IAM role for S3 Cross-Region Replication operations',
      });

      // Create inline policy for replication permissions
      const replicationPolicy = new iam.Policy(this, 'ReplicationPolicy', {
        policyName: `S3ReplicationPolicy-${uniqueSuffix}`,
        statements: [
          // Permissions to read from source bucket
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            actions: [
              's3:GetObjectVersionForReplication',
              's3:GetObjectVersionAcl',
              's3:GetObjectVersionTagging',
            ],
            resources: [`${sourceBucket.bucketArn}/*`],
          }),
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            actions: ['s3:ListBucket'],
            resources: [sourceBucket.bucketArn],
          }),
          // Permissions to write to destination bucket (will be in different region)
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            actions: [
              's3:ReplicateObject',
              's3:ReplicateDelete',
              's3:ReplicateTags',
            ],
            resources: [`arn:aws:s3:::${props.bucketPrefix}-destination-${uniqueSuffix}/*`],
          }),
        ],
      });

      // Attach policy to role
      replicationRole.attachInlinePolicy(replicationPolicy);

      // Configure Cross-Region Replication on source bucket
      // Note: This uses L1 construct as L2 doesn't fully support CRR configuration
      const cfnBucket = sourceBucket.node.defaultChild as s3.CfnBucket;
      cfnBucket.replicationConfiguration = {
        role: replicationRole.roleArn,
        rules: [
          {
            id: 'disaster-recovery-replication',
            status: 'Enabled',
            priority: 1,
            deleteMarkerReplication: {
              status: 'Enabled',
            },
            filter: {
              prefix: '', // Replicate all objects
            },
            destination: {
              bucket: `arn:aws:s3:::${props.bucketPrefix}-destination-${uniqueSuffix}`,
              storageClass: 'STANDARD_IA', // Cost optimization for DR
            },
          },
        ],
      };

      // Create SNS topic for monitoring alerts
      const alertTopic = new sns.Topic(this, 'ReplicationAlerts', {
        topicName: `s3-replication-alerts-${uniqueSuffix}`,
        displayName: 'S3 Replication Monitoring Alerts',
        description: 'SNS topic for S3 cross-region replication monitoring alerts',
      });

      // Add email subscription placeholder (can be configured via context)
      const alertEmail = this.node.tryGetContext('alertEmail');
      if (alertEmail) {
        alertTopic.addSubscription(new snsSubscriptions.EmailSubscription(alertEmail));
      }

      // CloudWatch Monitoring Setup
      if (props.enableMonitoring) {
        // Create CloudWatch alarm for replication failures
        const replicationFailureAlarm = new cloudwatch.Alarm(this, 'ReplicationFailureAlarm', {
          alarmName: `S3-Replication-Failures-${uniqueSuffix}`,
          alarmDescription: 'Monitor S3 replication failures and latency issues',
          metric: new cloudwatch.Metric({
            namespace: 'AWS/S3',
            metricName: 'ReplicationLatency',
            dimensionsMap: {
              SourceBucket: sourceBucket.bucketName,
            },
            statistic: 'Average',
            period: cdk.Duration.minutes(5),
          }),
          threshold: 900, // 15 minutes threshold
          evaluationPeriods: 2,
          comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
          treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
        });

        // Add SNS action to alarm
        replicationFailureAlarm.addAlarmAction(
          new cloudwatchActions.SnsAction(alertTopic)
        );

        // Create custom metric for replication monitoring
        const replicationMetricFilter = new cloudwatch.Metric({
          namespace: 'AWS/S3',
          metricName: 'BucketRequests',
          dimensionsMap: {
            BucketName: sourceBucket.bucketName,
            FilterId: 'EntireBucket',
          },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        });

        // Create dashboard for monitoring
        const dashboard = new cloudwatch.Dashboard(this, 'ReplicationDashboard', {
          dashboardName: `S3-Replication-Dashboard-${uniqueSuffix}`,
          widgets: [
            [
              new cloudwatch.GraphWidget({
                title: 'Replication Latency',
                left: [replicationFailureAlarm.metric],
                width: 12,
                height: 6,
              }),
            ],
            [
              new cloudwatch.GraphWidget({
                title: 'Bucket Requests',
                left: [replicationMetricFilter],
                width: 12,
                height: 6,
              }),
            ],
          ],
        });
      }

      // CloudTrail Setup for Audit Logging
      if (props.enableCloudTrail) {
        // Create CloudTrail for comprehensive S3 API logging
        const trail = new cloudtrail.Trail(this, 'S3ReplicationTrail', {
          trailName: `s3-replication-trail-${uniqueSuffix}`,
          bucket: sourceBucket,
          s3KeyPrefix: 'cloudtrail-logs/',
          includeGlobalServiceEvents: true,
          isMultiRegionTrail: true,
          enableFileValidation: true,
          sendToCloudWatchLogs: true,
        });

        // Add S3 data events for detailed monitoring
        trail.addS3EventSelector([
          {
            bucket: sourceBucket,
            objectPrefix: '',
            includeManagementEvents: false,
            readWriteType: cloudtrail.ReadWriteType.ALL,
          },
        ]);

        // Output CloudTrail ARN
        new cdk.CfnOutput(this, 'CloudTrailArn', {
          value: trail.trailArn,
          description: 'ARN of the CloudTrail for S3 replication audit logging',
          exportName: `${this.stackName}-CloudTrailArn`,
        });
      }

      // Export values for cross-stack references
      this.sourceBucketArn = sourceBucket.bucketArn;
      this.replicationRoleArn = replicationRole.roleArn;
      this.snsTopicArn = alertTopic.topicArn;

      // CloudFormation Outputs
      new cdk.CfnOutput(this, 'SourceBucketName', {
        value: sourceBucket.bucketName,
        description: 'Name of the source S3 bucket for disaster recovery replication',
        exportName: `${this.stackName}-SourceBucketName`,
      });

      new cdk.CfnOutput(this, 'SourceBucketArn', {
        value: sourceBucket.bucketArn,
        description: 'ARN of the source S3 bucket',
        exportName: `${this.stackName}-SourceBucketArn`,
      });

      new cdk.CfnOutput(this, 'ReplicationRoleArn', {
        value: replicationRole.roleArn,
        description: 'ARN of the IAM role used for cross-region replication',
        exportName: `${this.stackName}-ReplicationRoleArn`,
      });

      new cdk.CfnOutput(this, 'AlertTopicArn', {
        value: alertTopic.topicArn,
        description: 'ARN of the SNS topic for replication alerts',
        exportName: `${this.stackName}-AlertTopicArn`,
      });

    } else {
      // ===== DESTINATION STACK RESOURCES =====
      
      // Create destination S3 bucket in DR region
      const destinationBucket = new s3.Bucket(this, 'DestinationBucket', {
        bucketName: `${props.bucketPrefix}-destination-${uniqueSuffix}`,
        versioned: true,
        blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
        encryption: s3.BucketEncryption.S3_MANAGED,
        lifecycleRules: [
          {
            id: 'DeleteIncompleteMultipartUploads',
            abortIncompleteMultipartUploadAfter: cdk.Duration.days(1),
            enabled: true,
          },
          {
            id: 'TransitionToGlacier',
            transitions: [
              {
                storageClass: s3.StorageClass.GLACIER,
                transitionAfter: cdk.Duration.days(90),
              },
            ],
            enabled: true,
          },
        ],
        enforceSSL: true,
        removalPolicy: cdk.RemovalPolicy.RETAIN, // Prevent accidental deletion of DR data
      });

      // Create SNS topic for DR region monitoring
      const drAlertTopic = new sns.Topic(this, 'DrReplicationAlerts', {
        topicName: `s3-dr-alerts-${uniqueSuffix}`,
        displayName: 'S3 DR Region Monitoring Alerts',
        description: 'SNS topic for DR region S3 monitoring alerts',
      });

      // Add email subscription for DR alerts
      const drAlertEmail = this.node.tryGetContext('drAlertEmail');
      if (drAlertEmail) {
        drAlertTopic.addSubscription(new snsSubscriptions.EmailSubscription(drAlertEmail));
      }

      // CloudWatch Monitoring for destination bucket
      if (props.enableMonitoring) {
        // Monitor destination bucket for replication health
        const destinationMetrics = new cloudwatch.Metric({
          namespace: 'AWS/S3',
          metricName: 'BucketRequests',
          dimensionsMap: {
            BucketName: destinationBucket.bucketName,
            FilterId: 'EntireBucket',
          },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        });

        // Create alarm for unexpected activity in DR bucket
        const drActivityAlarm = new cloudwatch.Alarm(this, 'DrBucketActivityAlarm', {
          alarmName: `S3-DR-Unexpected-Activity-${uniqueSuffix}`,
          alarmDescription: 'Monitor for unexpected direct access to DR bucket',
          metric: destinationMetrics,
          threshold: 100, // Adjust based on expected replication volume
          evaluationPeriods: 2,
          comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
          treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
        });

        drActivityAlarm.addAlarmAction(
          new cloudwatchActions.SnsAction(drAlertTopic)
        );

        // DR Region Dashboard
        const drDashboard = new cloudwatch.Dashboard(this, 'DrReplicationDashboard', {
          dashboardName: `S3-DR-Dashboard-${uniqueSuffix}`,
          widgets: [
            [
              new cloudwatch.GraphWidget({
                title: 'DR Bucket Activity',
                left: [destinationMetrics],
                width: 12,
                height: 6,
              }),
            ],
          ],
        });
      }

      // Optional CloudTrail for DR region
      if (props.enableCloudTrail) {
        const drTrail = new cloudtrail.Trail(this, 'S3DrReplicationTrail', {
          trailName: `s3-dr-trail-${uniqueSuffix}`,
          bucket: destinationBucket,
          s3KeyPrefix: 'dr-cloudtrail-logs/',
          includeGlobalServiceEvents: false, // Region-specific trail
          isMultiRegionTrail: false,
          enableFileValidation: true,
        });

        // Add S3 data events for DR bucket monitoring
        drTrail.addS3EventSelector([
          {
            bucket: destinationBucket,
            objectPrefix: '',
            includeManagementEvents: false,
            readWriteType: cloudtrail.ReadWriteType.ALL,
          },
        ]);
      }

      // Set destination bucket ARN for outputs
      this.destinationBucketArn = destinationBucket.bucketArn;
      this.snsTopicArn = drAlertTopic.topicArn;

      // CloudFormation Outputs for DR stack
      new cdk.CfnOutput(this, 'DestinationBucketName', {
        value: destinationBucket.bucketName,
        description: 'Name of the destination S3 bucket for disaster recovery',
        exportName: `${this.stackName}-DestinationBucketName`,
      });

      new cdk.CfnOutput(this, 'DestinationBucketArn', {
        value: destinationBucket.bucketArn,
        description: 'ARN of the destination S3 bucket',
        exportName: `${this.stackName}-DestinationBucketArn`,
      });

      new cdk.CfnOutput(this, 'DrAlertTopicArn', {
        value: drAlertTopic.topicArn,
        description: 'ARN of the SNS topic for DR region alerts',
        exportName: `${this.stackName}-DrAlertTopicArn`,
      });
    }

    // Common outputs for both stacks
    new cdk.CfnOutput(this, 'StackType', {
      value: stackType,
      description: 'Type of stack (source or destination)',
    });

    new cdk.CfnOutput(this, 'DeploymentRegion', {
      value: this.region,
      description: 'AWS region where this stack is deployed',
    });

    // Add stack-level tags
    cdk.Tags.of(this).add('StackType', stackType);
    cdk.Tags.of(this).add('DisasterRecovery', 'S3CrossRegionReplication');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }
}