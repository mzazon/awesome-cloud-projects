#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudtrail from 'aws-cdk-lib/aws-cloudtrail';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as crypto from 'crypto';

/**
 * Configuration interface for the disaster recovery solution
 */
interface DisasterRecoveryConfig {
  readonly primaryRegion: string;
  readonly secondaryRegion: string;
  readonly bucketPrefix: string;
  readonly environment: string;
  readonly costCenter: string;
  readonly enableCloudTrail: boolean;
  readonly enableMonitoring: boolean;
  readonly replicationTimeControlEnabled: boolean;
}

/**
 * Stack for resources in the primary region (source bucket, IAM roles, CloudWatch alarms)
 */
class PrimaryRegionStack extends cdk.Stack {
  public readonly sourceBucket: s3.Bucket;
  public readonly replicationRole: iam.Role;
  public readonly replicaBucketArn: string;
  public readonly alertsTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: cdk.StackProps & { config: DisasterRecoveryConfig }) {
    super(scope, id, props);

    const { config } = props;
    
    // Generate unique suffix for resource names
    const uniqueSuffix = crypto.randomBytes(3).toString('hex');
    
    // Common tags for all resources
    const commonTags = {
      Purpose: 'DisasterRecovery',
      Environment: config.environment,
      CostCenter: config.costCenter,
      Recipe: 'disaster-recovery-s3-cross-region-replication'
    };

    // Create SNS topic for alerts
    this.alertsTopic = new sns.Topic(this, 'DisasterRecoveryAlerts', {
      topicName: `dr-alerts-${uniqueSuffix}`,
      displayName: 'Disaster Recovery Alerts',
      description: 'SNS topic for disaster recovery alerts and notifications'
    });

    // Apply tags to SNS topic
    Object.entries(commonTags).forEach(([key, value]) => {
      cdk.Tags.of(this.alertsTopic).add(key, value);
    });

    // Create source bucket in primary region
    this.sourceBucket = new s3.Bucket(this, 'SourceBucket', {
      bucketName: `${config.bucketPrefix}-source-${uniqueSuffix}`,
      versioned: true, // Required for cross-region replication
      enforceSSL: true, // Security best practice
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL, // Security best practice
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes - use RETAIN in production
      autoDeleteObjects: true, // For demo purposes - remove in production
      
      // Lifecycle rules for cost optimization
      lifecycleRules: [
        {
          id: 'TransitionToIA',
          enabled: true,
          prefix: 'standard/',
          transitions: [
            {
              storageClass: s3.StorageClass.STANDARD_IA,
              transitionAfter: cdk.Duration.days(30)
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90)
            }
          ]
        }
      ],

      // Enable server access logging for audit purposes
      serverAccessLogsPrefix: 'access-logs/',
      
      // Enable object lock for compliance (optional)
      objectLockEnabled: false,
      
      // Add notification configuration if needed
      notifications: []
    });

    // Apply tags to source bucket
    Object.entries(commonTags).forEach(([key, value]) => {
      cdk.Tags.of(this.sourceBucket).add(key, value);
    });

    // Calculate replica bucket ARN (will be created in secondary region)
    this.replicaBucketArn = `arn:aws:s3:::${config.bucketPrefix}-replica-${uniqueSuffix}`;

    // Create IAM role for S3 replication
    this.replicationRole = new iam.Role(this, 'ReplicationRole', {
      roleName: `s3-replication-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('s3.amazonaws.com'),
      description: 'IAM role for S3 cross-region replication',
      
      // Inline policy for replication permissions
      inlinePolicies: {
        S3ReplicationPolicy: new iam.PolicyDocument({
          statements: [
            // Permissions for source bucket
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetReplicationConfiguration',
                's3:ListBucket'
              ],
              resources: [this.sourceBucket.bucketArn]
            }),
            
            // Permissions for source bucket objects
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObjectVersionForReplication',
                's3:GetObjectVersionAcl',
                's3:GetObjectVersionTagging'
              ],
              resources: [`${this.sourceBucket.bucketArn}/*`]
            }),
            
            // Permissions for replica bucket objects
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:ReplicateObject',
                's3:ReplicateDelete',
                's3:ReplicateTags'
              ],
              resources: [`${this.replicaBucketArn}/*`]
            })
          ]
        })
      }
    });

    // Apply tags to replication role
    Object.entries(commonTags).forEach(([key, value]) => {
      cdk.Tags.of(this.replicationRole).add(key, value);
    });

    // Configure cross-region replication after replica bucket is created
    // This will be done in the main app after both stacks are created
    
    // Create CloudTrail for audit logging if enabled
    if (config.enableCloudTrail) {
      const cloudTrail = new cloudtrail.Trail(this, 'DisasterRecoveryTrail', {
        trailName: `s3-dr-audit-trail-${uniqueSuffix}`,
        isMultiRegionTrail: true,
        includeGlobalServiceEvents: true,
        enableFileValidation: true,
        sendToCloudWatchLogs: true,
        
        // Store logs in the source bucket
        bucket: this.sourceBucket,
        s3KeyPrefix: 'cloudtrail-logs/',
        
        // Event selectors for S3 data events
        dataEvents: [
          {
            includeManagementEvents: true,
            readWriteType: cloudtrail.ReadWriteType.ALL,
            resources: [
              this.sourceBucket.arnForObjects('*')
            ]
          }
        ]
      });

      // Apply tags to CloudTrail
      Object.entries(commonTags).forEach(([key, value]) => {
        cdk.Tags.of(cloudTrail).add(key, value);
      });
    }

    // Create CloudWatch alarms for monitoring if enabled
    if (config.enableMonitoring) {
      this.createCloudWatchAlarms(uniqueSuffix, commonTags);
    }

    // Outputs
    new cdk.CfnOutput(this, 'SourceBucketName', {
      value: this.sourceBucket.bucketName,
      description: 'Name of the source S3 bucket',
      exportName: `${this.stackName}-SourceBucketName`
    });

    new cdk.CfnOutput(this, 'ReplicationRoleArn', {
      value: this.replicationRole.roleArn,
      description: 'ARN of the replication IAM role',
      exportName: `${this.stackName}-ReplicationRoleArn`
    });

    new cdk.CfnOutput(this, 'AlertsTopicArn', {
      value: this.alertsTopic.topicArn,
      description: 'ARN of the SNS topic for alerts',
      exportName: `${this.stackName}-AlertsTopicArn`
    });
  }

  /**
   * Create CloudWatch alarms for monitoring replication
   */
  private createCloudWatchAlarms(uniqueSuffix: string, commonTags: Record<string, string>) {
    // Alarm for replication latency
    const replicationLatencyAlarm = new cloudwatch.Alarm(this, 'ReplicationLatencyAlarm', {
      alarmName: `S3-Replication-Latency-${uniqueSuffix}`,
      alarmDescription: 'Alarm for S3 replication latency exceeding 15 minutes',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/S3',
        metricName: 'ReplicationLatency',
        dimensionsMap: {
          SourceBucket: this.sourceBucket.bucketName,
          DestinationBucket: this.replicaBucketArn.split(':')[5] // Extract bucket name from ARN
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 900, // 15 minutes in seconds
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      actionsEnabled: true
    });

    // Add SNS action to the alarm
    replicationLatencyAlarm.addAlarmAction(
      new cloudwatch.SnsAction(this.alertsTopic)
    );

    // Apply tags to alarm
    Object.entries(commonTags).forEach(([key, value]) => {
      cdk.Tags.of(replicationLatencyAlarm).add(key, value);
    });

    // Alarm for replication failures
    const replicationFailureAlarm = new cloudwatch.Alarm(this, 'ReplicationFailureAlarm', {
      alarmName: `S3-Replication-Failures-${uniqueSuffix}`,
      alarmDescription: 'Alarm for S3 replication failures',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/S3',
        metricName: 'ReplicationFailures',
        dimensionsMap: {
          SourceBucket: this.sourceBucket.bucketName,
          DestinationBucket: this.replicaBucketArn.split(':')[5]
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      actionsEnabled: true
    });

    // Add SNS action to the alarm
    replicationFailureAlarm.addAlarmAction(
      new cloudwatch.SnsAction(this.alertsTopic)
    );

    // Apply tags to alarm
    Object.entries(commonTags).forEach(([key, value]) => {
      cdk.Tags.of(replicationFailureAlarm).add(key, value);
    });

    // Create CloudWatch Dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'DisasterRecoveryDashboard', {
      dashboardName: `S3-DR-Dashboard-${uniqueSuffix}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'S3 Replication Latency',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/S3',
                metricName: 'ReplicationLatency',
                dimensionsMap: {
                  SourceBucket: this.sourceBucket.bucketName
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5)
              })
            ],
            width: 12,
            height: 6
          }),
          new cloudwatch.GraphWidget({
            title: 'S3 Replication Failures',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/S3',
                metricName: 'ReplicationFailures',
                dimensionsMap: {
                  SourceBucket: this.sourceBucket.bucketName
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5)
              })
            ],
            width: 12,
            height: 6
          })
        ]
      ]
    });

    // Apply tags to dashboard
    Object.entries(commonTags).forEach(([key, value]) => {
      cdk.Tags.of(dashboard).add(key, value);
    });
  }
}

/**
 * Stack for resources in the secondary region (replica bucket)
 */
class SecondaryRegionStack extends cdk.Stack {
  public readonly replicaBucket: s3.Bucket;

  constructor(scope: Construct, id: string, props: cdk.StackProps & { config: DisasterRecoveryConfig; bucketSuffix: string }) {
    super(scope, id, props);

    const { config, bucketSuffix } = props;
    
    // Common tags for all resources
    const commonTags = {
      Purpose: 'DisasterRecovery',
      Environment: config.environment,
      CostCenter: config.costCenter,
      Recipe: 'disaster-recovery-s3-cross-region-replication'
    };

    // Create replica bucket in secondary region
    this.replicaBucket = new s3.Bucket(this, 'ReplicaBucket', {
      bucketName: `${config.bucketPrefix}-replica-${bucketSuffix}`,
      versioned: true, // Required for cross-region replication
      enforceSSL: true, // Security best practice
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL, // Security best practice
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes - use RETAIN in production
      autoDeleteObjects: true, // For demo purposes - remove in production
      
      // Enable server access logging for audit purposes
      serverAccessLogsPrefix: 'access-logs/',
      
      // Enable object lock for compliance (optional)
      objectLockEnabled: false
    });

    // Apply tags to replica bucket
    Object.entries(commonTags).forEach(([key, value]) => {
      cdk.Tags.of(this.replicaBucket).add(key, value);
    });

    // Outputs
    new cdk.CfnOutput(this, 'ReplicaBucketName', {
      value: this.replicaBucket.bucketName,
      description: 'Name of the replica S3 bucket',
      exportName: `${this.stackName}-ReplicaBucketName`
    });

    new cdk.CfnOutput(this, 'ReplicaBucketArn', {
      value: this.replicaBucket.bucketArn,
      description: 'ARN of the replica S3 bucket',
      exportName: `${this.stackName}-ReplicaBucketArn`
    });
  }
}

/**
 * Main CDK App
 */
class DisasterRecoveryApp extends cdk.App {
  constructor() {
    super();

    // Configuration
    const config: DisasterRecoveryConfig = {
      primaryRegion: 'us-east-1',
      secondaryRegion: 'us-west-2',
      bucketPrefix: 'dr-bucket',
      environment: 'production',
      costCenter: 'IT-DR',
      enableCloudTrail: true,
      enableMonitoring: true,
      replicationTimeControlEnabled: false // Enable for SLA-backed replication
    };

    // Generate unique suffix for bucket names
    const bucketSuffix = crypto.randomBytes(3).toString('hex');

    // Create primary region stack
    const primaryStack = new PrimaryRegionStack(this, 'DisasterRecoveryPrimary', {
      env: {
        account: process.env.CDK_DEFAULT_ACCOUNT,
        region: config.primaryRegion
      },
      config,
      description: 'Primary region stack for S3 disaster recovery solution'
    });

    // Create secondary region stack
    const secondaryStack = new SecondaryRegionStack(this, 'DisasterRecoverySecondary', {
      env: {
        account: process.env.CDK_DEFAULT_ACCOUNT,
        region: config.secondaryRegion
      },
      config,
      bucketSuffix,
      description: 'Secondary region stack for S3 disaster recovery solution'
    });

    // Add dependency to ensure primary stack creates resources first
    secondaryStack.addDependency(primaryStack);

    // Add replication configuration to source bucket after both stacks are created
    // This is done using a custom resource since CDK doesn't directly support
    // cross-region replication configuration
    const replicationConfig = new cdk.CfnResource(primaryStack, 'ReplicationConfiguration', {
      type: 'AWS::S3::Bucket',
      properties: {
        BucketName: primaryStack.sourceBucket.bucketName,
        ReplicationConfiguration: {
          Role: primaryStack.replicationRole.roleArn,
          Rules: [
            {
              Id: 'ReplicateEverything',
              Status: 'Enabled',
              Priority: 1,
              Filter: {
                Prefix: ''
              },
              DeleteMarkerReplication: {
                Status: 'Enabled'
              },
              Destination: {
                Bucket: secondaryStack.replicaBucket.bucketArn,
                StorageClass: 'STANDARD_IA'
              }
            },
            {
              Id: 'ReplicateCriticalData',
              Status: 'Enabled',
              Priority: 2,
              Filter: {
                And: {
                  Prefix: 'critical/',
                  Tags: [
                    {
                      Key: 'Classification',
                      Value: 'Critical'
                    }
                  ]
                }
              },
              DeleteMarkerReplication: {
                Status: 'Enabled'
              },
              Destination: {
                Bucket: secondaryStack.replicaBucket.bucketArn,
                StorageClass: 'STANDARD'
              }
            }
          ]
        }
      }
    });

    // Add dependency to ensure replica bucket exists before configuring replication
    replicationConfig.addDependency(secondaryStack.replicaBucket.node.defaultChild as cdk.CfnResource);

    // Add tags to the app
    cdk.Tags.of(this).add('Purpose', 'DisasterRecovery');
    cdk.Tags.of(this).add('Environment', config.environment);
    cdk.Tags.of(this).add('CostCenter', config.costCenter);
    cdk.Tags.of(this).add('Recipe', 'disaster-recovery-s3-cross-region-replication');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }
}

// Create and run the app
const app = new DisasterRecoveryApp();
app.synth();