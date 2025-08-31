#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';

/**
 * Simple S3 Infrastructure Stack
 * 
 * This stack creates an S3 bucket with enterprise-grade security settings
 * including AES-256 encryption, versioning for data protection, and 
 * comprehensive public access blocking following AWS security best practices.
 */
export class SimpleS3InfrastructureStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Get bucket name from context or generate unique name
    const bucketName = this.node.tryGetContext('bucketName') || 
      `my-infrastructure-bucket-${this.account.substring(0, 6)}`;

    // Create S3 bucket with security best practices
    const myS3Bucket = new s3.Bucket(this, 'MyS3Bucket', {
      bucketName: bucketName,
      
      // Enable versioning for data protection
      versioned: true,
      
      // Enable server-side encryption with AES-256
      encryption: s3.BucketEncryption.S3_MANAGED,
      bucketKeyEnabled: true,
      
      // Block all public access to prevent accidental data exposure
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      
      // Configure lifecycle to prevent permanent data loss
      lifecycleRules: [
        {
          id: 'delete-incomplete-multipart-uploads',
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
          enabled: true,
        },
      ],
      
      // Add tags for resource management and cost allocation
      tags: {
        Environment: 'Development',
        Purpose: 'Infrastructure-Template-Demo',
        CreatedBy: 'CDK-TypeScript',
      },
      
      // Enable event notifications (optional for future extension)
      eventBridgeEnabled: false,
      
      // Configure removal policy for development environment
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true, // WARNING: This will delete all objects on stack deletion
    });

    // Output bucket information for external consumption
    new cdk.CfnOutput(this, 'BucketName', {
      value: myS3Bucket.bucketName,
      description: 'Name of the created S3 bucket',
      exportName: `${this.stackName}-BucketName`,
    });

    new cdk.CfnOutput(this, 'BucketArn', {
      value: myS3Bucket.bucketArn,
      description: 'ARN of the created S3 bucket',
      exportName: `${this.stackName}-BucketArn`,
    });

    new cdk.CfnOutput(this, 'BucketDomainName', {
      value: myS3Bucket.bucketDomainName,
      description: 'Domain name of the S3 bucket',
    });

    new cdk.CfnOutput(this, 'BucketWebsiteUrl', {
      value: myS3Bucket.bucketWebsiteUrl,
      description: 'Website URL of the S3 bucket (if website hosting is enabled)',
    });
  }
}

/**
 * Main CDK App
 */
const app = new cdk.App();

// Create the stack with configurable environment
new SimpleS3InfrastructureStack(app, 'SimpleS3InfrastructureStack', {
  // Use environment variables or default values
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
  },
  
  // Stack description
  description: 'Simple S3 bucket with security best practices - CDK TypeScript implementation',
  
  // Add stack-level tags
  tags: {
    Application: 'Simple-Infrastructure-Templates',
    Framework: 'CDK-TypeScript',
    Purpose: 'Infrastructure-as-Code-Demo',
  },
});

// Synthesize the CloudFormation template
app.synth();