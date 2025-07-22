#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as cloudtrail from 'aws-cdk-lib/aws-cloudtrail';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Interface for Multi-Region S3 Replication Stack properties
 */
interface MultiRegionS3ReplicationStackProps extends cdk.StackProps {
  readonly primaryRegion: string;
  readonly secondaryRegion: string;
  readonly tertiaryRegion: string;
  readonly bucketPrefix: string;
  readonly environment: string;
  readonly enableIntelligentTiering?: boolean;
  readonly enableReplicationTimeControl?: boolean;
  readonly notificationEmail?: string;
}

/**
 * Primary stack that creates source bucket and replication infrastructure in primary region
 */
class MultiRegionS3ReplicationPrimaryStack extends cdk.Stack {
  public readonly sourceBucket: s3.Bucket;
  public readonly sourceKmsKey: kms.Key;
  public readonly replicationRole: iam.Role;
  public readonly cloudTrail: cloudtrail.Trail;
  public readonly monitoringTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: MultiRegionS3ReplicationStackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();
    
    // Create KMS key for source bucket encryption
    this.sourceKmsKey = new kms.Key(this, 'SourceKmsKey', {
      description: 'KMS key for S3 multi-region replication source bucket',
      enableKeyRotation: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      policy: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            sid: 'EnableIAMUserPermissions',
            effect: iam.Effect.ALLOW,
            principals: [new iam.AccountRootPrincipal()],
            actions: ['kms:*'],
            resources: ['*'],
          }),
          new iam.PolicyStatement({
            sid: 'AllowS3Service',
            effect: iam.Effect.ALLOW,
            principals: [new iam.ServicePrincipal('s3.amazonaws.com')],
            actions: [
              'kms:Decrypt',
              'kms:GenerateDataKey',
              'kms:ReEncrypt*',
              'kms:CreateGrant',
              'kms:DescribeKey',
            ],
            resources: ['*'],
          }),
        ],
      }),
    });

    // Create alias for KMS key
    new kms.Alias(this, 'SourceKmsKeyAlias', {
      aliasName: `alias/s3-multi-region-source-${uniqueSuffix}`,
      targetKey: this.sourceKmsKey,
    });

    // Create IAM role for cross-region replication
    this.replicationRole = new iam.Role(this, 'ReplicationRole', {
      assumedBy: new iam.ServicePrincipal('s3.amazonaws.com'),
      roleName: `MultiRegionReplicationRole-${uniqueSuffix}`,
      description: 'IAM role for S3 cross-region replication',
    });

    // Create source S3 bucket with comprehensive configuration
    this.sourceBucket = new s3.Bucket(this, 'SourceBucket', {
      bucketName: `${props.bucketPrefix}-source-${uniqueSuffix}`,
      versioned: true, // Required for replication
      encryption: s3.BucketEncryption.KMS,
      encryptionKey: this.sourceKmsKey,
      bucketKeyEnabled: true, // Reduce KMS costs
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      autoDeleteObjects: true, // For demo purposes
      lifecycleRules: [
        {
          id: 'MultiRegionLifecycleRule',
          enabled: true,
          prefix: 'archive/',
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
              transitionAfter: cdk.Duration.days(7),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(30),
            },
          ],
          noncurrentVersionExpiration: cdk.Duration.days(365),
        },
      ],
    });

    // Configure intelligent tiering if enabled
    if (props.enableIntelligentTiering) {
      new s3.CfnBucket.IntelligentTieringConfiguration(this, 'IntelligentTiering', {
        bucket: this.sourceBucket.bucketName,
        id: 'EntireBucket',
        status: 'Enabled',
        prefix: '',
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
        optionalFields: ['BucketKeyStatus'],
      });
    }

    // Apply comprehensive bucket policy
    this.sourceBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'DenyInsecureConnections',
        effect: iam.Effect.DENY,
        principals: [new iam.AnyPrincipal()],
        actions: ['s3:*'],
        resources: [
          this.sourceBucket.bucketArn,
          this.sourceBucket.arnForObjects('*'),
        ],
        conditions: {
          Bool: {
            'aws:SecureTransport': 'false',
          },
        },
      })
    );

    this.sourceBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AllowReplicationRole',
        effect: iam.Effect.ALLOW,
        principals: [this.replicationRole],
        actions: [
          's3:GetReplicationConfiguration',
          's3:ListBucket',
          's3:GetObjectVersionForReplication',
          's3:GetObjectVersionAcl',
          's3:GetObjectVersionTagging',
        ],
        resources: [
          this.sourceBucket.bucketArn,
          this.sourceBucket.arnForObjects('*'),
        ],
      })
    );

    // Create SNS topic for monitoring alerts
    this.monitoringTopic = new sns.Topic(this, 'MonitoringTopic', {
      topicName: `s3-replication-alerts-${uniqueSuffix}`,
      displayName: 'S3 Multi-Region Replication Alerts',
    });

    // Create CloudWatch Log Group for CloudTrail
    const cloudTrailLogGroup = new logs.LogGroup(this, 'CloudTrailLogGroup', {
      logGroupName: `/aws/cloudtrail/s3-multi-region-audit-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create CloudTrail for comprehensive audit logging
    this.cloudTrail = new cloudtrail.Trail(this, 'AuditTrail', {
      trailName: `s3-multi-region-audit-trail-${uniqueSuffix}`,
      bucket: this.sourceBucket,
      s3KeyPrefix: 'audit-logs/',
      includeGlobalServiceEvents: true,
      isMultiRegionTrail: true,
      enableFileValidation: true,
      cloudWatchLogGroup: cloudTrailLogGroup,
      sendToCloudWatchLogs: true,
    });

    // Add resource tags for cost allocation and compliance
    cdk.Tags.of(this).add('Environment', props.environment);
    cdk.Tags.of(this).add('Application', 'MultiRegionReplication');
    cdk.Tags.of(this).add('CostCenter', 'IT-Storage');
    cdk.Tags.of(this).add('Owner', 'DataTeam');
    cdk.Tags.of(this).add('Compliance', 'SOX-GDPR');
    cdk.Tags.of(this).add('BackupStrategy', 'MultiRegion');

    // Output important resource identifiers
    new cdk.CfnOutput(this, 'SourceBucketName', {
      value: this.sourceBucket.bucketName,
      description: 'Name of the source S3 bucket',
      exportName: `${this.stackName}-SourceBucketName`,
    });

    new cdk.CfnOutput(this, 'SourceKmsKeyId', {
      value: this.sourceKmsKey.keyId,
      description: 'ID of the source KMS key',
      exportName: `${this.stackName}-SourceKmsKeyId`,
    });

    new cdk.CfnOutput(this, 'ReplicationRoleArn', {
      value: this.replicationRole.roleArn,
      description: 'ARN of the replication IAM role',
      exportName: `${this.stackName}-ReplicationRoleArn`,
    });

    new cdk.CfnOutput(this, 'MonitoringTopicArn', {
      value: this.monitoringTopic.topicArn,
      description: 'ARN of the monitoring SNS topic',
      exportName: `${this.stackName}-MonitoringTopicArn`,
    });
  }
}

/**
 * Secondary stack for destination buckets in other regions
 */
class MultiRegionS3ReplicationDestinationStack extends cdk.Stack {
  public readonly destinationBucket: s3.Bucket;
  public readonly destinationKmsKey: kms.Key;

  constructor(scope: Construct, id: string, props: MultiRegionS3ReplicationStackProps & {
    readonly bucketSuffix: string;
    readonly replicationRoleArn: string;
  }) {
    super(scope, id, props);

    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // Create KMS key for destination bucket encryption
    this.destinationKmsKey = new kms.Key(this, 'DestinationKmsKey', {
      description: `KMS key for S3 multi-region replication destination bucket - ${props.bucketSuffix}`,
      enableKeyRotation: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      policy: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            sid: 'EnableIAMUserPermissions',
            effect: iam.Effect.ALLOW,
            principals: [new iam.AccountRootPrincipal()],
            actions: ['kms:*'],
            resources: ['*'],
          }),
          new iam.PolicyStatement({
            sid: 'AllowS3Service',
            effect: iam.Effect.ALLOW,
            principals: [new iam.ServicePrincipal('s3.amazonaws.com')],
            actions: [
              'kms:Decrypt',
              'kms:GenerateDataKey',
              'kms:ReEncrypt*',
              'kms:CreateGrant',
              'kms:DescribeKey',
            ],
            resources: ['*'],
          }),
          new iam.PolicyStatement({
            sid: 'AllowReplicationRole',
            effect: iam.Effect.ALLOW,
            principals: [iam.Role.fromRoleArn(this, 'ImportedReplicationRole', props.replicationRoleArn)],
            actions: [
              'kms:Decrypt',
              'kms:GenerateDataKey',
              'kms:ReEncrypt*',
              'kms:CreateGrant',
              'kms:DescribeKey',
            ],
            resources: ['*'],
          }),
        ],
      }),
    });

    // Create alias for destination KMS key
    new kms.Alias(this, 'DestinationKmsKeyAlias', {
      aliasName: `alias/s3-multi-region-${props.bucketSuffix}-${uniqueSuffix}`,
      targetKey: this.destinationKmsKey,
    });

    // Create destination S3 bucket
    this.destinationBucket = new s3.Bucket(this, 'DestinationBucket', {
      bucketName: `${props.bucketPrefix}-${props.bucketSuffix}-${uniqueSuffix}`,
      versioned: true, // Required for replication
      encryption: s3.BucketEncryption.KMS,
      encryptionKey: this.destinationKmsKey,
      bucketKeyEnabled: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      autoDeleteObjects: true, // For demo purposes
    });

    // Grant replication role necessary permissions
    this.destinationBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AllowReplicationRole',
        effect: iam.Effect.ALLOW,
        principals: [iam.Role.fromRoleArn(this, 'ReplicationRoleForPolicy', props.replicationRoleArn)],
        actions: [
          's3:ReplicateObject',
          's3:ReplicateDelete',
          's3:ReplicateTags',
        ],
        resources: [this.destinationBucket.arnForObjects('*')],
      })
    );

    // Add resource tags
    cdk.Tags.of(this).add('Environment', props.environment);
    cdk.Tags.of(this).add('Application', 'MultiRegionReplication');
    cdk.Tags.of(this).add('CostCenter', 'IT-Storage');
    cdk.Tags.of(this).add('Owner', 'DataTeam');
    cdk.Tags.of(this).add('Compliance', 'SOX-GDPR');
    cdk.Tags.of(this).add('BackupStrategy', 'MultiRegion');
    cdk.Tags.of(this).add('ReplicaOf', `${props.bucketPrefix}-source-${uniqueSuffix}`);

    // Output destination bucket information
    new cdk.CfnOutput(this, 'DestinationBucketName', {
      value: this.destinationBucket.bucketName,
      description: `Name of the destination S3 bucket - ${props.bucketSuffix}`,
      exportName: `${this.stackName}-DestinationBucketName`,
    });

    new cdk.CfnOutput(this, 'DestinationKmsKeyId', {
      value: this.destinationKmsKey.keyId,
      description: `ID of the destination KMS key - ${props.bucketSuffix}`,
      exportName: `${this.stackName}-DestinationKmsKeyId`,
    });
  }
}

/**
 * Monitoring stack for CloudWatch dashboards and alarms
 */
class MultiRegionS3ReplicationMonitoringStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: MultiRegionS3ReplicationStackProps & {
    readonly sourceBucketName: string;
    readonly destinationBucket1Name: string;
    readonly destinationBucket2Name: string;
    readonly monitoringTopicArn: string;
  }) {
    super(scope, id, props);

    const monitoringTopic = sns.Topic.fromTopicArn(this, 'ImportedMonitoringTopic', props.monitoringTopicArn);

    // Create CloudWatch alarm for replication failures
    const replicationFailureAlarm = new cloudwatch.Alarm(this, 'ReplicationFailureAlarm', {
      alarmName: `S3-Replication-Failure-Rate-${props.sourceBucketName}`,
      alarmDescription: 'High replication failure rate detected',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/S3',
        metricName: 'FailedReplication',
        dimensionsMap: {
          SourceBucket: props.sourceBucketName,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 10,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    replicationFailureAlarm.addAlarmAction({
      bind: () => ({ alarmActionArn: monitoringTopic.topicArn }),
    });

    // Create CloudWatch alarm for replication latency
    const replicationLatencyAlarm = new cloudwatch.Alarm(this, 'ReplicationLatencyAlarm', {
      alarmName: `S3-Replication-Latency-${props.sourceBucketName}`,
      alarmDescription: 'Replication latency too high',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/S3',
        metricName: 'ReplicationLatency',
        dimensionsMap: {
          SourceBucket: props.sourceBucketName,
          DestinationBucket: props.destinationBucket1Name,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 900, // 15 minutes in seconds
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    replicationLatencyAlarm.addAlarmAction({
      bind: () => ({ alarmActionArn: monitoringTopic.topicArn }),
    });

    // Create comprehensive CloudWatch dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'ReplicationDashboard', {
      dashboardName: 'S3-Multi-Region-Replication-Dashboard',
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'S3 Multi-Region Replication Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/S3',
                metricName: 'ReplicationLatency',
                dimensionsMap: {
                  SourceBucket: props.sourceBucketName,
                  DestinationBucket: props.destinationBucket1Name,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
                label: 'Latency to Secondary Region',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/S3',
                metricName: 'ReplicationLatency',
                dimensionsMap: {
                  SourceBucket: props.sourceBucketName,
                  DestinationBucket: props.destinationBucket2Name,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
                label: 'Latency to Tertiary Region',
              }),
            ],
            right: [
              new cloudwatch.Metric({
                namespace: 'AWS/S3',
                metricName: 'FailedReplication',
                dimensionsMap: {
                  SourceBucket: props.sourceBucketName,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
                label: 'Failed Replications',
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Bucket Size Comparison',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/S3',
                metricName: 'BucketSizeBytes',
                dimensionsMap: {
                  BucketName: props.sourceBucketName,
                  StorageType: 'StandardStorage',
                },
                statistic: 'Average',
                period: cdk.Duration.days(1),
                label: 'Source Bucket Size',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/S3',
                metricName: 'BucketSizeBytes',
                dimensionsMap: {
                  BucketName: props.destinationBucket1Name,
                  StorageType: 'StandardStorage',
                },
                statistic: 'Average',
                period: cdk.Duration.days(1),
                label: 'Destination Bucket 1 Size',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/S3',
                metricName: 'BucketSizeBytes',
                dimensionsMap: {
                  BucketName: props.destinationBucket2Name,
                  StorageType: 'StandardStorage',
                },
                statistic: 'Average',
                period: cdk.Duration.days(1),
                label: 'Destination Bucket 2 Size',
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
      ],
    });

    // Output monitoring resources
    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'URL to CloudWatch Dashboard',
    });

    new cdk.CfnOutput(this, 'ReplicationFailureAlarmName', {
      value: replicationFailureAlarm.alarmName,
      description: 'Name of the replication failure alarm',
    });

    new cdk.CfnOutput(this, 'ReplicationLatencyAlarmName', {
      value: replicationLatencyAlarm.alarmName,
      description: 'Name of the replication latency alarm',
    });
  }
}

/**
 * Main CDK application
 */
class MultiRegionS3ReplicationApp extends cdk.App {
  constructor() {
    super();

    // Configuration parameters
    const config = {
      primaryRegion: 'us-east-1',
      secondaryRegion: 'us-west-2',
      tertiaryRegion: 'eu-west-1',
      bucketPrefix: 'multi-region',
      environment: 'production',
      enableIntelligentTiering: true,
      enableReplicationTimeControl: true,
    };

    // Create primary stack in primary region
    const primaryStack = new MultiRegionS3ReplicationPrimaryStack(this, 'MultiRegionS3ReplicationPrimary', {
      env: { region: config.primaryRegion },
      ...config,
      description: 'Primary stack for multi-region S3 replication with source bucket and monitoring',
    });

    // Create secondary destination stack
    const secondaryStack = new MultiRegionS3ReplicationDestinationStack(this, 'MultiRegionS3ReplicationSecondary', {
      env: { region: config.secondaryRegion },
      ...config,
      bucketSuffix: 'dest1',
      replicationRoleArn: primaryStack.replicationRole.roleArn,
      description: 'Secondary destination stack for multi-region S3 replication',
    });

    // Create tertiary destination stack
    const tertiaryStack = new MultiRegionS3ReplicationDestinationStack(this, 'MultiRegionS3ReplicationTertiary', {
      env: { region: config.tertiaryRegion },
      ...config,
      bucketSuffix: 'dest2',
      replicationRoleArn: primaryStack.replicationRole.roleArn,
      description: 'Tertiary destination stack for multi-region S3 replication',
    });

    // Add replication permissions to the role after all stacks are created
    primaryStack.replicationRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          's3:GetReplicationConfiguration',
          's3:ListBucket',
          's3:GetBucketVersioning',
        ],
        resources: [primaryStack.sourceBucket.bucketArn],
      })
    );

    primaryStack.replicationRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          's3:GetObjectVersionForReplication',
          's3:GetObjectVersionAcl',
          's3:GetObjectVersionTagging',
        ],
        resources: [primaryStack.sourceBucket.arnForObjects('*')],
      })
    );

    primaryStack.replicationRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          's3:ReplicateObject',
          's3:ReplicateDelete',
          's3:ReplicateTags',
        ],
        resources: [
          secondaryStack.destinationBucket.arnForObjects('*'),
          tertiaryStack.destinationBucket.arnForObjects('*'),
        ],
      })
    );

    primaryStack.replicationRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'kms:Decrypt',
          'kms:GenerateDataKey',
          'kms:ReEncrypt*',
          'kms:CreateGrant',
          'kms:DescribeKey',
        ],
        resources: [
          primaryStack.sourceKmsKey.keyArn,
          secondaryStack.destinationKmsKey.keyArn,
          tertiaryStack.destinationKmsKey.keyArn,
        ],
      })
    );

    // Create monitoring stack in primary region
    const monitoringStack = new MultiRegionS3ReplicationMonitoringStack(this, 'MultiRegionS3ReplicationMonitoring', {
      env: { region: config.primaryRegion },
      ...config,
      sourceBucketName: primaryStack.sourceBucket.bucketName,
      destinationBucket1Name: secondaryStack.destinationBucket.bucketName,
      destinationBucket2Name: tertiaryStack.destinationBucket.bucketName,
      monitoringTopicArn: primaryStack.monitoringTopic.topicArn,
      description: 'Monitoring stack for multi-region S3 replication with CloudWatch dashboards and alarms',
    });

    // Set up stack dependencies
    secondaryStack.addDependency(primaryStack);
    tertiaryStack.addDependency(primaryStack);
    monitoringStack.addDependency(primaryStack);
    monitoringStack.addDependency(secondaryStack);
    monitoringStack.addDependency(tertiaryStack);

    // Add deployment instructions as stack metadata
    primaryStack.addMetadata('DeploymentInstructions', {
      order: 1,
      description: 'Deploy primary stack first to create source bucket and IAM role',
      commands: [
        'npm install',
        'npm run build',
        'cdk deploy MultiRegionS3ReplicationPrimary',
      ],
    });

    secondaryStack.addMetadata('DeploymentInstructions', {
      order: 2,
      description: 'Deploy secondary destination stack',
      commands: ['cdk deploy MultiRegionS3ReplicationSecondary'],
    });

    tertiaryStack.addMetadata('DeploymentInstructions', {
      order: 3,
      description: 'Deploy tertiary destination stack',
      commands: ['cdk deploy MultiRegionS3ReplicationTertiary'],
    });

    monitoringStack.addMetadata('DeploymentInstructions', {
      order: 4,
      description: 'Deploy monitoring stack for CloudWatch resources',
      commands: ['cdk deploy MultiRegionS3ReplicationMonitoring'],
    });
  }
}

// Instantiate and run the CDK application
new MultiRegionS3ReplicationApp();