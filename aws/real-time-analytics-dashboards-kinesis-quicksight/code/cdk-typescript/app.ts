#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as kinesis from 'aws-cdk-lib/aws-kinesis';
import * as kinesisanalytics from 'aws-cdk-lib/aws-kinesisanalyticsv2';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as quicksight from 'aws-cdk-lib/aws-quicksight';
import * as s3deployment from 'aws-cdk-lib/aws-s3-deployment';

/**
 * Configuration interface for the Real-time Analytics Dashboard Stack
 */
interface RealTimeAnalyticsDashboardProps extends cdk.StackProps {
  /**
   * Environment stage (dev, staging, prod)
   */
  stage?: string;
  
  /**
   * Number of shards for the Kinesis Data Stream
   * @default 2
   */
  shardCount?: number;
  
  /**
   * S3 bucket retention period in days
   * @default 30
   */
  s3RetentionDays?: number;
  
  /**
   * Flink application parallelism
   * @default 1
   */
  flinkParallelism?: number;
  
  /**
   * Enable auto-scaling for Flink application
   * @default true
   */
  enableAutoScaling?: boolean;
}

/**
 * CDK Stack for Real-time Analytics Dashboards using Kinesis Analytics and QuickSight
 * 
 * This stack creates:
 * - Kinesis Data Stream for real-time data ingestion
 * - IAM role with appropriate permissions for Flink application
 * - S3 buckets for processed data storage and application code
 * - Managed Service for Apache Flink application for stream processing
 * - CloudWatch Log Groups for monitoring and debugging
 * - QuickSight data source configuration (manual setup required)
 */
export class RealTimeAnalyticsDashboardStack extends cdk.Stack {
  
  public readonly kinesisStream: kinesis.Stream;
  public readonly flinkApplication: kinesisanalytics.CfnApplicationV2;
  public readonly dataStorageBucket: s3.Bucket;
  public readonly codeStorageBucket: s3.Bucket;
  public readonly flinkExecutionRole: iam.Role;

  constructor(scope: Construct, id: string, props: RealTimeAnalyticsDashboardProps = {}) {
    super(scope, id, props);

    // Extract configuration with defaults
    const stage = props.stage || 'dev';
    const shardCount = props.shardCount || 2;
    const s3RetentionDays = props.s3RetentionDays || 30;
    const flinkParallelism = props.flinkParallelism || 1;
    const enableAutoScaling = props.enableAutoScaling ?? true;

    // Create Kinesis Data Stream for real-time data ingestion
    // Multiple shards enable parallel processing and higher throughput
    this.kinesisStream = new kinesis.Stream(this, 'AnalyticsDataStream', {
      streamName: `analytics-stream-${stage}`,
      shardCount: shardCount,
      retentionPeriod: cdk.Duration.hours(24), // 24 hours retention for cost optimization
      encryption: kinesis.StreamEncryption.KMS, // Enable encryption at rest
      encryptionKey: undefined, // Use AWS managed key for simplicity
    });

    // Create S3 bucket for storing processed analytics data
    // This bucket will contain the output from Flink processing for QuickSight consumption
    this.dataStorageBucket = new s3.Bucket(this, 'AnalyticsDataBucket', {
      bucketName: `analytics-results-${stage}-${this.account}`,
      versioned: false, // Disable versioning for cost optimization
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'DeleteOldAnalyticsData',
          enabled: true,
          expiration: cdk.Duration.days(s3RetentionDays),
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(1),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Allow cleanup during stack deletion
      autoDeleteObjects: true, // Automatically delete objects when bucket is destroyed
    });

    // Create S3 bucket for storing Flink application code and artifacts
    this.codeStorageBucket = new s3.Bucket(this, 'FlinkCodeBucket', {
      bucketName: `flink-code-${stage}-${this.account}`,
      versioned: true, // Enable versioning for application code management
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(7),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create IAM role for Managed Service for Apache Flink with comprehensive permissions
    this.flinkExecutionRole = new iam.Role(this, 'FlinkExecutionRole', {
      roleName: `FlinkAnalyticsRole-${stage}`,
      assumedBy: new iam.ServicePrincipal('kinesisanalytics.amazonaws.com'),
      description: 'IAM role for Managed Service for Apache Flink analytics application',
      inlinePolicies: {
        FlinkAnalyticsPolicy: new iam.PolicyDocument({
          statements: [
            // Kinesis Data Stream permissions for reading streaming data
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'kinesis:DescribeStream',
                'kinesis:GetShardIterator',
                'kinesis:GetRecords',
                'kinesis:ListShards',
                'kinesis:SubscribeToShard',
              ],
              resources: [this.kinesisStream.streamArn],
            }),
            // S3 permissions for reading application code and writing processed data
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
              ],
              resources: [
                `${this.dataStorageBucket.bucketArn}/*`,
                `${this.codeStorageBucket.bucketArn}/*`,
              ],
            }),
            // S3 bucket listing permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:ListBucket'],
              resources: [
                this.dataStorageBucket.bucketArn,
                this.codeStorageBucket.bucketArn,
              ],
            }),
            // CloudWatch Logs permissions for application monitoring and debugging
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
                'logs:DescribeLogGroups',
                'logs:DescribeLogStreams',
              ],
              resources: [`arn:aws:logs:${this.region}:${this.account}:*`],
            }),
            // CloudWatch metrics permissions for application monitoring
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:PutMetricData',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create CloudWatch Log Group for Flink application logs
    const flinkLogGroup = new logs.LogGroup(this, 'FlinkApplicationLogGroup', {
      logGroupName: `/aws/kinesis-analytics/analytics-app-${stage}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create Managed Service for Apache Flink application for stream processing
    // This application performs real-time analytics on the streaming data
    this.flinkApplication = new kinesisanalytics.CfnApplicationV2(this, 'FlinkAnalyticsApplication', {
      applicationName: `analytics-app-${stage}`,
      applicationDescription: 'Real-time analytics application for streaming data processing',
      runtimeEnvironment: 'FLINK-1_18', // Latest supported Flink version
      serviceExecutionRole: this.flinkExecutionRole.roleArn,
      
      applicationConfiguration: {
        // Application code configuration pointing to S3 location
        applicationCodeConfiguration: {
          codeContent: {
            s3ContentLocation: {
              bucketArn: this.codeStorageBucket.bucketArn,
              fileKey: 'flink-analytics-app-1.0.jar', // JAR file will be uploaded separately
            },
          },
          codeContentType: 'ZIPFILE',
        },
        
        // Environment properties for runtime configuration
        environmentProperties: {
          propertyGroups: [
            {
              propertyGroupId: 'kinesis.analytics.flink.run.options',
              propertyMap: {
                'input.stream.name': this.kinesisStream.streamName,
                'aws.region': this.region,
                's3.path': `s3://${this.dataStorageBucket.bucketName}/analytics-results/`,
              },
            },
          ],
        },
        
        // Flink-specific configuration for performance and monitoring
        flinkApplicationConfiguration: {
          // Checkpointing configuration for fault tolerance
          checkpointConfiguration: {
            configurationType: 'DEFAULT',
          },
          
          // Monitoring and logging configuration
          monitoringConfiguration: {
            configurationType: 'CUSTOM',
            logLevel: 'INFO',
            metricsLevel: 'APPLICATION',
          },
          
          // Parallelism configuration for performance tuning
          parallelismConfiguration: {
            configurationType: 'CUSTOM',
            parallelism: flinkParallelism,
            parallelismPerKpu: 1,
            autoScalingEnabled: enableAutoScaling,
          },
        },
        
        // Application snapshot configuration for backup and recovery
        applicationSnapshotConfiguration: {
          snapshotsEnabled: true,
        },
      },
    });

    // Create a sample manifest file for QuickSight data source setup
    const quicksightManifest = {
      fileLocations: [
        {
          URIPrefixes: [
            `s3://${this.dataStorageBucket.bucketName}/analytics-results/`,
          ],
        },
      ],
      globalUploadSettings: {
        format: 'JSON',
      },
    };

    // Store QuickSight manifest in S3 for easy setup
    new s3deployment.BucketDeployment(this, 'QuickSightManifestDeployment', {
      sources: [
        s3deployment.Source.jsonData('quicksight-manifest.json', quicksightManifest),
      ],
      destinationBucket: this.dataStorageBucket,
    });

    // Add tags to all resources for cost tracking and management
    cdk.Tags.of(this).add('Project', 'RealTimeAnalyticsDashboard');
    cdk.Tags.of(this).add('Stage', stage);
    cdk.Tags.of(this).add('ManagedBy', 'CDK');

    // Stack outputs for reference and integration
    new cdk.CfnOutput(this, 'KinesisStreamName', {
      value: this.kinesisStream.streamName,
      description: 'Name of the Kinesis Data Stream for data ingestion',
      exportName: `${this.stackName}-KinesisStreamName`,
    });

    new cdk.CfnOutput(this, 'KinesisStreamArn', {
      value: this.kinesisStream.streamArn,
      description: 'ARN of the Kinesis Data Stream',
      exportName: `${this.stackName}-KinesisStreamArn`,
    });

    new cdk.CfnOutput(this, 'FlinkApplicationName', {
      value: this.flinkApplication.applicationName!,
      description: 'Name of the Managed Service for Apache Flink application',
      exportName: `${this.stackName}-FlinkApplicationName`,
    });

    new cdk.CfnOutput(this, 'DataStorageBucketName', {
      value: this.dataStorageBucket.bucketName,
      description: 'S3 bucket containing processed analytics data for QuickSight',
      exportName: `${this.stackName}-DataStorageBucketName`,
    });

    new cdk.CfnOutput(this, 'CodeStorageBucketName', {
      value: this.codeStorageBucket.bucketName,
      description: 'S3 bucket for Flink application code storage',
      exportName: `${this.stackName}-CodeStorageBucketName`,
    });

    new cdk.CfnOutput(this, 'FlinkExecutionRoleArn', {
      value: this.flinkExecutionRole.roleArn,
      description: 'ARN of the IAM role used by the Flink application',
      exportName: `${this.stackName}-FlinkExecutionRoleArn`,
    });

    new cdk.CfnOutput(this, 'QuickSightManifestLocation', {
      value: `s3://${this.dataStorageBucket.bucketName}/quicksight-manifest.json`,
      description: 'Location of QuickSight manifest file for data source setup',
      exportName: `${this.stackName}-QuickSightManifestLocation`,
    });

    new cdk.CfnOutput(this, 'CloudWatchLogGroup', {
      value: flinkLogGroup.logGroupName,
      description: 'CloudWatch Log Group for Flink application logs',
      exportName: `${this.stackName}-CloudWatchLogGroup`,
    });
  }
}

/**
 * CDK App entry point
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const stage = app.node.tryGetContext('stage') || process.env.CDK_STAGE || 'dev';
const account = process.env.CDK_DEFAULT_ACCOUNT;
const region = process.env.CDK_DEFAULT_REGION;

// Validate required environment variables
if (!account || !region) {
  throw new Error('CDK_DEFAULT_ACCOUNT and CDK_DEFAULT_REGION environment variables must be set');
}

// Create the stack with appropriate configuration
new RealTimeAnalyticsDashboardStack(app, `RealTimeAnalyticsDashboard-${stage}`, {
  env: {
    account: account,
    region: region,
  },
  stage: stage,
  description: `Real-time analytics dashboard infrastructure for ${stage} environment`,
  
  // Configuration can be customized per environment
  shardCount: stage === 'prod' ? 4 : 2,
  s3RetentionDays: stage === 'prod' ? 90 : 30,
  flinkParallelism: stage === 'prod' ? 2 : 1,
  enableAutoScaling: true,
});

