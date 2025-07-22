#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudtrail from 'aws-cdk-lib/aws-cloudtrail';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Stack for Secure File Sharing with S3 Presigned URLs
 * This stack creates the infrastructure needed to securely share files
 * with external partners using time-limited presigned URLs
 */
export class FileSharingS3PresignedUrlsStack extends cdk.Stack {
  public readonly fileSharingBucket: s3.Bucket;
  public readonly presignedUrlRole: iam.Role;
  public readonly auditTrail: cloudtrail.Trail;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate a unique suffix for resource names to avoid conflicts
    const uniqueSuffix = cdk.Names.uniqueId(this).slice(-8).toLowerCase();

    // Create the main S3 bucket for file sharing with security best practices
    this.fileSharingBucket = new s3.Bucket(this, 'FileSharingBucket', {
      bucketName: `file-sharing-demo-${uniqueSuffix}`,
      // Block all public access - files will only be accessible via presigned URLs
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      // Enable versioning for file recovery and audit purposes
      versioned: true,
      // Configure lifecycle policies to manage storage costs
      lifecycleRules: [
        {
          id: 'delete-incomplete-multipart-uploads',
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
        },
        {
          id: 'transition-to-ia',
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
          ],
        },
      ],
      // Enable server-side encryption with AWS managed keys
      encryption: s3.BucketEncryption.S3_MANAGED,
      // Enforce HTTPS-only requests
      enforceSSL: true,
      // Configure CORS for web-based file sharing applications
      cors: [
        {
          allowedMethods: [
            s3.HttpMethods.GET,
            s3.HttpMethods.PUT,
            s3.HttpMethods.POST,
            s3.HttpMethods.DELETE,
          ],
          allowedOrigins: ['*'], // Configure specific origins in production
          allowedHeaders: ['*'],
          exposedHeaders: ['ETag'],
          maxAge: 3000,
        },
      ],
      // Configure intelligent tiering for cost optimization
      intelligentTieringConfigurations: [
        {
          name: 'entire-bucket-intelligent-tiering',
          optionalFields: [
            s3.IntelligentTieringOptionalFields.BULK_RETRIEVAL_ACCESS,
            s3.IntelligentTieringOptionalFields.ARCHIVE_ACCESS,
          ],
        },
      ],
      // Configure notifications for monitoring uploads/downloads
      notificationsHandlingRole: iam.Role.fromRoleArn(
        this,
        'BucketNotificationRole',
        `arn:aws:iam::${cdk.Aws.ACCOUNT_ID}:role/service-role/S3BucketNotificationsRole`
      ),
      // Auto-delete bucket contents when stack is destroyed (for demo purposes)
      autoDeleteObjects: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create folder structure within the bucket using dummy objects
    // This helps organize files and demonstrates the folder-based access patterns
    new s3.BucketDeployment(this, 'CreateFolderStructure', {
      sources: [
        s3.Source.data('documents/.keep', '# Documents folder for shared files'),
        s3.Source.data('uploads/.keep', '# Uploads folder for incoming files'),
        s3.Source.data('archive/.keep', '# Archive folder for historical files'),
      ],
      destinationBucket: this.fileSharingBucket,
    });

    // Create IAM role for generating presigned URLs with least privilege permissions
    this.presignedUrlRole = new iam.Role(this, 'PresignedUrlRole', {
      roleName: `file-sharing-presigned-url-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Role for generating presigned URLs for file sharing',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Grant specific permissions for presigned URL operations
    this.presignedUrlRole.addToPolicy(
      new iam.PolicyStatement({
        sid: 'AllowPresignedUrlGeneration',
        effect: iam.Effect.ALLOW,
        actions: [
          's3:GetObject',
          's3:PutObject',
          's3:DeleteObject',
          's3:GetObjectVersion',
          's3:ListBucket',
        ],
        resources: [
          this.fileSharingBucket.bucketArn,
          `${this.fileSharingBucket.bucketArn}/*`,
        ],
        conditions: {
          'StringEquals': {
            's3:signatureAge': '3600', // Limit signature age to 1 hour
          },
        },
      })
    );

    // Create a CloudWatch Log Group for CloudTrail logs
    const trailLogGroup = new logs.LogGroup(this, 'CloudTrailLogGroup', {
      logGroupName: `/aws/cloudtrail/file-sharing-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create CloudTrail for auditing all S3 access and presigned URL usage
    this.auditTrail = new cloudtrail.Trail(this, 'FileSharingAuditTrail', {
      trailName: `file-sharing-audit-${uniqueSuffix}`,
      // Send logs to CloudWatch for real-time monitoring
      sendToCloudWatchLogs: true,
      cloudWatchLogGroup: trailLogGroup,
      // Include global service events (IAM, STS)
      includeGlobalServiceEvents: true,
      // Enable multi-region trail for comprehensive coverage
      isMultiRegionTrail: true,
      // Enable log file validation for integrity checking
      enableFileValidation: true,
    });

    // Configure CloudTrail to specifically monitor our S3 bucket
    this.auditTrail.addS3EventSelector([
      {
        bucket: this.fileSharingBucket,
        objectPrefix: '', // Monitor all objects
        includeManagementEvents: true,
        readWriteType: cloudtrail.ReadWriteType.ALL,
      },
    ]);

    // Create a bucket policy to enhance security and provide additional controls
    this.fileSharingBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'DenyNonSSLRequests',
        effect: iam.Effect.DENY,
        principals: [new iam.AnyPrincipal()],
        actions: ['s3:*'],
        resources: [
          this.fileSharingBucket.bucketArn,
          `${this.fileSharingBucket.bucketArn}/*`,
        ],
        conditions: {
          Bool: {
            'aws:SecureTransport': 'false',
          },
        },
      })
    );

    // Add bucket policy to log access attempts for security monitoring
    this.fileSharingBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'RequireRequestLogging',
        effect: iam.Effect.DENY,
        principals: [new iam.AnyPrincipal()],
        actions: ['s3:*'],
        resources: [
          this.fileSharingBucket.bucketArn,
          `${this.fileSharingBucket.bucketArn}/*`,
        ],
        conditions: {
          'Null': {
            'aws:CloudTrail': 'true',
          },
        },
      })
    );

    // Create outputs for easy access to resource information
    new cdk.CfnOutput(this, 'BucketName', {
      value: this.fileSharingBucket.bucketName,
      description: 'Name of the S3 bucket for file sharing',
      exportName: `${cdk.Aws.STACK_NAME}-BucketName`,
    });

    new cdk.CfnOutput(this, 'BucketArn', {
      value: this.fileSharingBucket.bucketArn,
      description: 'ARN of the S3 bucket for file sharing',
      exportName: `${cdk.Aws.STACK_NAME}-BucketArn`,
    });

    new cdk.CfnOutput(this, 'PresignedUrlRoleArn', {
      value: this.presignedUrlRole.roleArn,
      description: 'ARN of the IAM role for generating presigned URLs',
      exportName: `${cdk.Aws.STACK_NAME}-PresignedUrlRoleArn`,
    });

    new cdk.CfnOutput(this, 'CloudTrailArn', {
      value: this.auditTrail.trailArn,
      description: 'ARN of the CloudTrail for audit logging',
      exportName: `${cdk.Aws.STACK_NAME}-CloudTrailArn`,
    });

    // Output sample CLI commands for generating presigned URLs
    new cdk.CfnOutput(this, 'SampleDownloadCommand', {
      value: `aws s3 presign s3://${this.fileSharingBucket.bucketName}/documents/sample-file.txt --expires-in 3600`,
      description: 'Sample command to generate a download presigned URL',
    });

    new cdk.CfnOutput(this, 'SampleUploadCommand', {
      value: `aws s3 presign s3://${this.fileSharingBucket.bucketName}/uploads/new-file.txt --expires-in 1800 --http-method PUT`,
      description: 'Sample command to generate an upload presigned URL',
    });

    // Add tags to all resources for better organization and cost tracking
    cdk.Tags.of(this).add('Project', 'FileSharingS3PresignedUrls');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('Purpose', 'SecureFileSharing');
    cdk.Tags.of(this).add('Recipe', 'file-sharing-solutions-s3-presigned-urls');
  }
}

// Import the S3 deployment construct
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
const s3Deployment = s3deploy;

// Create the CDK app
const app = new cdk.App();

// Deploy the stack with appropriate naming and environment configuration
new FileSharingS3PresignedUrlsStack(app, 'FileSharingS3PresignedUrlsStack', {
  description: 'Infrastructure for building secure file sharing solutions with S3 presigned URLs',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  // Enable termination protection for production deployments
  terminationProtection: false, // Set to true for production
});

// Add aspects for additional security and compliance checks
import { Aspects } from 'aws-cdk-lib';
import { AwsSolutionsChecks } from 'cdk-nag';

// Apply CDK NAG for security and compliance validation
Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));