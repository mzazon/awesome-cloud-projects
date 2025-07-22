#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as iam from 'aws-cdk-lib/aws-iam';

/**
 * Stack for demonstrating S3 multipart upload strategies for large files
 * 
 * This stack creates:
 * - S3 bucket optimized for large file uploads
 * - Lifecycle policies for multipart upload cleanup
 * - CloudWatch dashboard for monitoring
 * - IAM roles and policies for secure access
 */
export class MultiPartUploadStrategiesStack extends cdk.Stack {
  public readonly bucket: s3.Bucket;
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.slice(-8).toLowerCase();

    // Create S3 bucket optimized for large file uploads
    this.bucket = new s3.Bucket(this, 'MultiPartUploadBucket', {
      bucketName: `multipart-upload-demo-${uniqueSuffix}`,
      
      // Versioning enabled for better data protection
      versioned: true,
      
      // Enable public read access prevention
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      
      // Server-side encryption with S3 managed keys
      encryption: s3.BucketEncryption.S3_MANAGED,
      
      // Enable bucket notifications and metrics
      eventBridgeEnabled: true,
      
      // Lifecycle configuration for multipart upload cleanup
      lifecycleRules: [
        {
          id: 'CleanupIncompleteMultipartUploads',
          enabled: true,
          
          // Automatically abort incomplete multipart uploads after 7 days
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
          
          // Delete old versions after 30 days to manage costs
          noncurrentVersionExpiration: cdk.Duration.days(30),
          
          // Transition current objects to IA storage after 30 days
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
      
      // CORS configuration for web-based uploads
      cors: [
        {
          allowedMethods: [
            s3.HttpMethods.GET,
            s3.HttpMethods.POST,
            s3.HttpMethods.PUT,
            s3.HttpMethods.DELETE,
            s3.HttpMethods.HEAD,
          ],
          allowedOrigins: ['*'],
          allowedHeaders: ['*'],
          exposedHeaders: ['ETag'],
          maxAge: 3000,
        },
      ],
      
      // Enable transfer acceleration for improved upload performance
      transferAcceleration: true,
      
      // Auto-delete objects when stack is destroyed (for demo purposes)
      autoDeleteObjects: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create CloudWatch dashboard for monitoring multipart uploads
    this.dashboard = new cloudwatch.Dashboard(this, 'MultiPartUploadDashboard', {
      dashboardName: `S3-MultipartUpload-Monitoring-${uniqueSuffix}`,
      
      widgets: [
        [
          // Bucket size and object count metrics
          new cloudwatch.GraphWidget({
            title: 'S3 Bucket Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/S3',
                metricName: 'NumberOfObjects',
                dimensionsMap: {
                  BucketName: this.bucket.bucketName,
                  StorageType: 'AllStorageTypes',
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
            ],
            right: [
              new cloudwatch.Metric({
                namespace: 'AWS/S3',
                metricName: 'BucketSizeBytes',
                dimensionsMap: {
                  BucketName: this.bucket.bucketName,
                  StorageType: 'StandardStorage',
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
        [
          // Request metrics for upload performance monitoring
          new cloudwatch.GraphWidget({
            title: 'S3 Request Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/S3',
                metricName: 'AllRequests',
                dimensionsMap: {
                  BucketName: this.bucket.bucketName,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
            right: [
              new cloudwatch.Metric({
                namespace: 'AWS/S3',
                metricName: '4xxErrors',
                dimensionsMap: {
                  BucketName: this.bucket.bucketName,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/S3',
                metricName: '5xxErrors',
                dimensionsMap: {
                  BucketName: this.bucket.bucketName,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
      ],
    });

    // Create IAM role for multipart upload operations
    const multipartUploadRole = new iam.Role(this, 'MultiPartUploadRole', {
      roleName: `MultiPartUploadRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'Role for performing multipart uploads to S3',
    });

    // Create policy for multipart upload operations
    const multipartUploadPolicy = new iam.Policy(this, 'MultiPartUploadPolicy', {
      policyName: `MultiPartUploadPolicy-${uniqueSuffix}`,
      statements: [
        // S3 multipart upload permissions
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            's3:CreateMultipartUpload',
            's3:UploadPart',
            's3:CompleteMultipartUpload',
            's3:AbortMultipartUpload',
            's3:ListMultipartUploadParts',
            's3:ListBucketMultipartUploads',
          ],
          resources: [
            this.bucket.bucketArn,
            `${this.bucket.bucketArn}/*`,
          ],
        }),
        // S3 object operations
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            's3:GetObject',
            's3:PutObject',
            's3:DeleteObject',
            's3:GetObjectVersion',
            's3:ListBucket',
          ],
          resources: [
            this.bucket.bucketArn,
            `${this.bucket.bucketArn}/*`,
          ],
        }),
        // CloudWatch permissions for monitoring
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'cloudwatch:GetMetricStatistics',
            'cloudwatch:ListMetrics',
            'cloudwatch:PutMetricData',
          ],
          resources: ['*'],
        }),
      ],
    });

    // Attach policy to role
    multipartUploadRole.attachInlinePolicy(multipartUploadPolicy);

    // Create CloudWatch alarms for monitoring
    new cloudwatch.Alarm(this, 'HighErrorRateAlarm', {
      alarmName: `S3-HighErrorRate-${uniqueSuffix}`,
      alarmDescription: 'Alarm when S3 error rate is high',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/S3',
        metricName: '4xxErrors',
        dimensionsMap: {
          BucketName: this.bucket.bucketName,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 10,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Output important resource information
    new cdk.CfnOutput(this, 'BucketName', {
      value: this.bucket.bucketName,
      description: 'Name of the S3 bucket for multipart uploads',
      exportName: `${this.stackName}-BucketName`,
    });

    new cdk.CfnOutput(this, 'BucketArn', {
      value: this.bucket.bucketArn,
      description: 'ARN of the S3 bucket',
      exportName: `${this.stackName}-BucketArn`,
    });

    new cdk.CfnOutput(this, 'BucketRegion', {
      value: this.region,
      description: 'Region where the S3 bucket is deployed',
      exportName: `${this.stackName}-BucketRegion`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard for monitoring',
      exportName: `${this.stackName}-DashboardUrl`,
    });

    new cdk.CfnOutput(this, 'MultiPartUploadRoleArn', {
      value: multipartUploadRole.roleArn,
      description: 'ARN of the IAM role for multipart upload operations',
      exportName: `${this.stackName}-MultiPartUploadRoleArn`,
    });

    new cdk.CfnOutput(this, 'TransferAccelerationEndpoint', {
      value: `${this.bucket.bucketName}.s3-accelerate.amazonaws.com`,
      description: 'S3 Transfer Acceleration endpoint for improved upload performance',
      exportName: `${this.stackName}-TransferAccelerationEndpoint`,
    });

    // Add tags to all resources for better organization
    cdk.Tags.of(this).add('Project', 'MultiPartUploadStrategies');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('Purpose', 'LargeFileUploads');
    cdk.Tags.of(this).add('CostCenter', 'Development');
  }
}

// CDK App instantiation
const app = new cdk.App();

// Create the stack with appropriate configuration
new MultiPartUploadStrategiesStack(app, 'MultiPartUploadStrategiesStack', {
  description: 'Infrastructure for demonstrating S3 multipart upload strategies for large files',
  
  // Environment configuration
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Stack-level tags
  tags: {
    Application: 'MultiPartUploadStrategies',
    Owner: 'AwsRecipes',
    Version: '1.0',
  },
});

// Synthesize the CloudFormation template
app.synth();