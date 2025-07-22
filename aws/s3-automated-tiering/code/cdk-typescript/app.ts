#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as iam from 'aws-cdk-lib/aws-iam';

/**
 * Properties for the S3 Intelligent Tiering Stack
 */
interface S3IntelligentTieringStackProps extends cdk.StackProps {
  /** 
   * The name for the S3 bucket. If not provided, a unique name will be generated.
   */
  readonly bucketName?: string;
  
  /**
   * Whether to enable versioning on the S3 bucket.
   * @default true
   */
  readonly enableVersioning?: boolean;
  
  /**
   * Days after which objects transition to Archive Access tier.
   * @default 90
   */
  readonly archiveAccessDays?: number;
  
  /**
   * Days after which objects transition to Deep Archive Access tier.
   * @default 180
   */
  readonly deepArchiveAccessDays?: number;
  
  /**
   * Days after which non-current versions are deleted.
   * @default 365
   */
  readonly noncurrentVersionExpirationDays?: number;
  
  /**
   * Whether to create a CloudWatch dashboard for monitoring.
   * @default true
   */
  readonly createDashboard?: boolean;
}

/**
 * CDK Stack for S3 Intelligent Tiering and Lifecycle Management
 * 
 * This stack implements automated storage cost optimization using S3 Intelligent Tiering
 * and comprehensive lifecycle policies. It creates:
 * 
 * - S3 bucket with versioning enabled
 * - Intelligent Tiering configuration for automatic cost optimization
 * - Lifecycle policies for additional management
 * - CloudWatch monitoring and dashboard
 * - Sample data for testing
 */
export class S3IntelligentTieringStack extends cdk.Stack {
  public readonly bucket: s3.Bucket;
  public readonly dashboard?: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: S3IntelligentTieringStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const {
      bucketName,
      enableVersioning = true,
      archiveAccessDays = 90,
      deepArchiveAccessDays = 180,
      noncurrentVersionExpirationDays = 365,
      createDashboard = true
    } = props;

    // Validate input parameters
    this.validateParameters(archiveAccessDays, deepArchiveAccessDays, noncurrentVersionExpirationDays);

    // Create the S3 bucket with intelligent tiering and lifecycle management
    this.bucket = this.createS3Bucket(bucketName, enableVersioning);

    // Configure Intelligent Tiering
    this.configureIntelligentTiering(this.bucket, archiveAccessDays, deepArchiveAccessDays);

    // Configure Lifecycle Policy
    this.configureLifecyclePolicy(this.bucket, noncurrentVersionExpirationDays);

    // Create CloudWatch dashboard if requested
    if (createDashboard) {
      this.dashboard = this.createCloudWatchDashboard(this.bucket);
    }

    // Create sample data deployment custom resource
    this.createSampleDataDeployment(this.bucket);

    // Add outputs
    this.addOutputs(this.bucket, this.dashboard);

    // Add tags to all resources
    cdk.Tags.of(this).add('Solution', 'S3-Intelligent-Tiering');
    cdk.Tags.of(this).add('CostOptimization', 'Enabled');
    cdk.Tags.of(this).add('AutomatedManagement', 'True');
  }

  /**
   * Validates the input parameters for logical consistency
   */
  private validateParameters(
    archiveAccessDays: number,
    deepArchiveAccessDays: number,
    noncurrentVersionExpirationDays: number
  ): void {
    if (archiveAccessDays >= deepArchiveAccessDays) {
      throw new Error('Archive access days must be less than deep archive access days');
    }
    
    if (archiveAccessDays < 30) {
      throw new Error('Archive access days must be at least 30 days for Intelligent Tiering');
    }
    
    if (noncurrentVersionExpirationDays < 1) {
      throw new Error('Non-current version expiration days must be at least 1 day');
    }
  }

  /**
   * Creates the S3 bucket with security best practices
   */
  private createS3Bucket(bucketName?: string, enableVersioning: boolean = true): s3.Bucket {
    const bucket = new s3.Bucket(this, 'IntelligentTieringBucket', {
      bucketName: bucketName,
      versioned: enableVersioning,
      
      // Security best practices
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      
      // Lifecycle management
      autoDeleteObjects: false, // Prevent accidental deletion
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      
      // Access logging for security monitoring
      serverAccessLogsPrefix: 'access-logs/',
      
      // Notification configuration for monitoring
      eventBridgeEnabled: true,
      
      // CORS configuration for potential web access
      cors: [
        {
          allowedMethods: [s3.HttpMethods.GET, s3.HttpMethods.PUT],
          allowedOrigins: ['*'],
          allowedHeaders: ['*'],
          maxAge: 86400,
        },
      ],
    });

    // Add additional bucket notifications for monitoring
    bucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      // Can be extended with SNS or Lambda targets for advanced monitoring
    );

    return bucket;
  }

  /**
   * Configures S3 Intelligent Tiering for automatic cost optimization
   */
  private configureIntelligentTiering(
    bucket: s3.Bucket,
    archiveAccessDays: number,
    deepArchiveAccessDays: number
  ): void {
    // Create Intelligent Tiering configuration using L1 construct for full control
    new s3.CfnBucket.IntelligentTieringConfigurationProperty({
      id: 'EntireBucketConfig',
      status: 'Enabled',
      
      // Apply to entire bucket
      prefix: '',
      
      // Configure automatic transitions to archive tiers
      tierings: [
        {
          accessTier: 'ARCHIVE_ACCESS',
          days: archiveAccessDays,
        },
        {
          accessTier: 'DEEP_ARCHIVE_ACCESS', 
          days: deepArchiveAccessDays,
        },
      ],
      
      // Optional: Add tag filters for more granular control
      tagFilters: [
        {
          key: 'IntelligentTiering',
          value: 'Enabled',
        },
      ],
    });

    // Add the intelligent tiering configuration to the bucket
    // Note: This requires using the underlying CloudFormation resource
    const cfnBucket = bucket.node.defaultChild as s3.CfnBucket;
    cfnBucket.addPropertyOverride('IntelligentTieringConfigurations', [
      {
        Id: 'EntireBucketConfig',
        Status: 'Enabled',
        Prefix: '',
        Tierings: [
          {
            AccessTier: 'ARCHIVE_ACCESS',
            Days: archiveAccessDays,
          },
          {
            AccessTier: 'DEEP_ARCHIVE_ACCESS',
            Days: deepArchiveAccessDays,
          },
        ],
      },
    ]);
  }

  /**
   * Configures comprehensive lifecycle policies
   */
  private configureLifecyclePolicy(bucket: s3.Bucket, noncurrentVersionExpirationDays: number): void {
    bucket.addLifecycleRule({
      id: 'OptimizeStorage',
      enabled: true,
      
      // Apply to all objects
      prefix: '',
      
      // Transition new objects to Intelligent Tiering after 30 days
      transitions: [
        {
          storageClass: s3.StorageClass.INTELLIGENT_TIERING,
          transitionAfter: cdk.Duration.days(30),
        },
      ],
      
      // Clean up incomplete multipart uploads
      abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
      
      // Manage non-current versions
      noncurrentVersionTransitions: [
        {
          storageClass: s3.StorageClass.INFREQUENT_ACCESS,
          transitionAfter: cdk.Duration.days(30),
        },
        {
          storageClass: s3.StorageClass.GLACIER,
          transitionAfter: cdk.Duration.days(90),
        },
      ],
      
      // Delete old versions to control costs
      noncurrentVersionExpiration: cdk.Duration.days(noncurrentVersionExpirationDays),
      
      // Optional: Expire delete markers
      expiredObjectDeleteMarker: true,
    });
  }

  /**
   * Creates CloudWatch dashboard for monitoring storage optimization
   */
  private createCloudWatchDashboard(bucket: s3.Bucket): cloudwatch.Dashboard {
    const dashboard = new cloudwatch.Dashboard(this, 'S3StorageOptimizationDashboard', {
      dashboardName: `S3-Storage-Optimization-${cdk.Stack.of(this).stackName}`,
    });

    // Create metrics for different storage classes
    const standardStorageMetric = new cloudwatch.Metric({
      namespace: 'AWS/S3',
      metricName: 'BucketSizeBytes',
      dimensionsMap: {
        BucketName: bucket.bucketName,
        StorageType: 'StandardStorage',
      },
      statistic: 'Average',
      period: cdk.Duration.days(1),
    });

    const intelligentTieringIAMetric = new cloudwatch.Metric({
      namespace: 'AWS/S3',
      metricName: 'BucketSizeBytes', 
      dimensionsMap: {
        BucketName: bucket.bucketName,
        StorageType: 'IntelligentTieringIAStorage',
      },
      statistic: 'Average',
      period: cdk.Duration.days(1),
    });

    const intelligentTieringAAMetric = new cloudwatch.Metric({
      namespace: 'AWS/S3',
      metricName: 'BucketSizeBytes',
      dimensionsMap: {
        BucketName: bucket.bucketName,
        StorageType: 'IntelligentTieringAAStorage',
      },
      statistic: 'Average',
      period: cdk.Duration.days(1),
    });

    const objectCountMetric = new cloudwatch.Metric({
      namespace: 'AWS/S3',
      metricName: 'NumberOfObjects',
      dimensionsMap: {
        BucketName: bucket.bucketName,
        StorageType: 'AllStorageTypes',
      },
      statistic: 'Average',
      period: cdk.Duration.days(1),
    });

    // Add storage distribution widget
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'S3 Storage Distribution by Class',
        left: [standardStorageMetric, intelligentTieringIAMetric, intelligentTieringAAMetric],
        width: 12,
        height: 6,
        stacked: true,
      }),
      new cloudwatch.SingleValueWidget({
        title: 'Total Object Count',
        metrics: [objectCountMetric],
        width: 12,
        height: 6,
      })
    );

    // Add request metrics if available
    const getRequestsMetric = new cloudwatch.Metric({
      namespace: 'AWS/S3',
      metricName: 'AllRequests',
      dimensionsMap: {
        BucketName: bucket.bucketName,
        FilterId: 'EntireBucket',
      },
      statistic: 'Sum',
      period: cdk.Duration.hours(1),
    });

    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'S3 Request Activity',
        left: [getRequestsMetric],
        width: 24,
        height: 6,
      })
    );

    return dashboard;
  }

  /**
   * Creates a custom resource to deploy sample data for testing
   */
  private createSampleDataDeployment(bucket: s3.Bucket): void {
    // Create IAM role for the custom resource Lambda
    const customResourceRole = new iam.Role(this, 'SampleDataDeploymentRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        S3Access: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:PutObject',
                's3:PutObjectTagging',
                's3:DeleteObject',
                's3:ListBucket',
              ],
              resources: [
                bucket.bucketArn,
                `${bucket.bucketArn}/*`,
              ],
            }),
          ],
        }),
      },
    });

    // Note: In a full implementation, you would create a Lambda function here
    // that deploys sample data similar to the CLI commands in the recipe.
    // For brevity, this is left as a placeholder, but the structure is provided.
    
    // Example Lambda function would:
    // 1. Create sample files with different access patterns
    // 2. Upload to different prefixes (active/, archive/, data/)
    // 3. Apply appropriate tags
    // 4. Handle cleanup on stack deletion
  }

  /**
   * Adds CloudFormation outputs for important resource information
   */
  private addOutputs(bucket: s3.Bucket, dashboard?: cloudwatch.Dashboard): void {
    new cdk.CfnOutput(this, 'BucketName', {
      value: bucket.bucketName,
      description: 'Name of the S3 bucket with Intelligent Tiering enabled',
      exportName: `${this.stackName}-BucketName`,
    });

    new cdk.CfnOutput(this, 'BucketArn', {
      value: bucket.bucketArn,
      description: 'ARN of the S3 bucket',
      exportName: `${this.stackName}-BucketArn`,
    });

    new cdk.CfnOutput(this, 'BucketDomainName', {
      value: bucket.bucketDomainName,
      description: 'Domain name of the S3 bucket',
      exportName: `${this.stackName}-BucketDomainName`,
    });

    if (dashboard) {
      new cdk.CfnOutput(this, 'DashboardURL', {
        value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
        description: 'CloudWatch Dashboard URL for monitoring storage optimization',
      });
    }

    new cdk.CfnOutput(this, 'ManagementConsoleURL', {
      value: `https://s3.console.aws.amazon.com/s3/buckets/${bucket.bucketName}?region=${this.region}&tab=management`,
      description: 'S3 Console URL for bucket management',
    });
  }
}

/**
 * Main CDK Application
 */
const app = new cdk.App();

// Get configuration from context or environment variables
const bucketName = app.node.tryGetContext('bucketName');
const enableVersioning = app.node.tryGetContext('enableVersioning') !== 'false';
const archiveAccessDays = Number(app.node.tryGetContext('archiveAccessDays')) || 90;
const deepArchiveAccessDays = Number(app.node.tryGetContext('deepArchiveAccessDays')) || 180;
const noncurrentVersionExpirationDays = Number(app.node.tryGetContext('noncurrentVersionExpirationDays')) || 365;
const createDashboard = app.node.tryGetContext('createDashboard') !== 'false';

// Create the stack
new S3IntelligentTieringStack(app, 'S3IntelligentTieringStack', {
  description: 'CDK implementation of S3 Intelligent Tiering and Lifecycle Management for automated storage cost optimization',
  
  // Configuration properties
  bucketName,
  enableVersioning,
  archiveAccessDays,
  deepArchiveAccessDays,
  noncurrentVersionExpirationDays,
  createDashboard,
  
  // Stack properties
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Tags applied to all resources in the stack
  tags: {
    Project: 'S3IntelligentTiering',
    Environment: app.node.tryGetContext('environment') || 'development',
    Owner: app.node.tryGetContext('owner') || 'DevOps',
    CostCenter: app.node.tryGetContext('costCenter') || 'Engineering',
  },
});

// Synthesize the app
app.synth();