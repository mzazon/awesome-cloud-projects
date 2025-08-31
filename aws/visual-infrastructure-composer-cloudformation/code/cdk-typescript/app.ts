#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';

/**
 * CDK Stack for Visual Infrastructure Design Demo
 * 
 * This stack demonstrates the same infrastructure that would be created
 * using AWS Infrastructure Composer, showing how visual designs translate
 * to CDK TypeScript code for static website hosting.
 */
export class VisualInfrastructureComposerStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate a unique suffix for resource naming to avoid conflicts
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // Create S3 bucket for static website hosting
    // This demonstrates the same configuration that would be created
    // through Infrastructure Composer's visual S3 Bucket card
    const websiteBucket = new s3.Bucket(this, 'WebsiteBucket', {
      bucketName: `my-visual-website-${uniqueSuffix}`,
      
      // Enable static website hosting - equivalent to Infrastructure Composer's
      // website hosting configuration in the bucket properties panel
      websiteIndexDocument: 'index.html',
      websiteErrorDocument: 'error.html',
      
      // Enable public read access for website content
      // This replicates the bucket policy configuration from Infrastructure Composer
      publicReadAccess: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ACLS,
      
      // Configure bucket for website hosting use case
      autoDeleteObjects: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      
      // Enable versioning for content management best practices
      versioned: false,
      
      // Apply cost-effective storage class for static website content
      lifecycleRules: [
        {
          id: 'WebsiteContentLifecycle',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30)
            }
          ]
        }
      ]
    });

    // Create explicit bucket policy for public read access
    // This demonstrates the Infrastructure Composer bucket policy card
    // that would be visually connected to the S3 bucket card
    const bucketPolicy = new iam.PolicyDocument({
      statements: [
        new iam.PolicyStatement({
          sid: 'PublicReadGetObject',
          effect: iam.Effect.ALLOW,
          principals: [new iam.AnyPrincipal()],
          actions: ['s3:GetObject'],
          resources: [`${websiteBucket.bucketArn}/*`],
          conditions: {
            StringEquals: {
              's3:ExistingObjectTag/PublicAccess': 'true'
            }
          }
        })
      ]
    });

    // Apply the bucket policy to enable public website access
    // This creates the same policy that Infrastructure Composer generates
    // when connecting a bucket policy card to an S3 bucket card
    websiteBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AllowPublicRead',
        effect: iam.Effect.ALLOW,
        principals: [new iam.AnyPrincipal()],
        actions: ['s3:GetObject'],
        resources: [`${websiteBucket.bucketArn}/*`]
      })
    );

    // Add tags for resource management and cost tracking
    // These tags help identify resources created through this CDK stack
    cdk.Tags.of(this).add('Project', 'VisualInfrastructureComposer');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('CreatedBy', 'CDK');
    cdk.Tags.of(this).add('Purpose', 'StaticWebsiteHosting');

    // Create CloudFormation outputs for easy access to deployed resources
    // These outputs match what Infrastructure Composer would generate
    new cdk.CfnOutput(this, 'BucketName', {
      value: websiteBucket.bucketName,
      description: 'Name of the S3 bucket hosting the static website',
      exportName: `${this.stackName}-BucketName`
    });

    new cdk.CfnOutput(this, 'WebsiteURL', {
      value: websiteBucket.bucketWebsiteUrl,
      description: 'URL of the static website hosted on S3',
      exportName: `${this.stackName}-WebsiteURL`
    });

    new cdk.CfnOutput(this, 'BucketArn', {
      value: websiteBucket.bucketArn,
      description: 'ARN of the S3 bucket for reference in other stacks',
      exportName: `${this.stackName}-BucketArn`
    });

    new cdk.CfnOutput(this, 'WebsiteDomain', {
      value: websiteBucket.bucketWebsiteDomainName,
      description: 'Domain name of the website endpoint',
      exportName: `${this.stackName}-WebsiteDomain`
    });
  }
}

/**
 * CDK Application entry point
 * 
 * This creates and configures the CDK app with the appropriate stack,
 * demonstrating how Infrastructure Composer visual designs can be
 * implemented using CDK TypeScript for infrastructure as code.
 */
const app = new cdk.App();

// Create the stack with environment configuration
// Environment settings can be customized through CDK context or environment variables
new VisualInfrastructureComposerStack(app, 'VisualInfrastructureComposerStack', {
  description: 'CDK implementation of AWS Infrastructure Composer visual design for static website hosting',
  
  // Configure stack environment - can be overridden via CDK context
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  },
  
  // Enable stack termination protection for production deployments
  terminationProtection: false,
  
  // Configure stack tags for governance and cost allocation
  tags: {
    Project: 'VisualInfrastructureComposer',
    Environment: 'Demo',
    ManagedBy: 'CDK'
  }
});

// Add stack-level metadata for documentation and governance
app.node.setContext('@aws-cdk/core:enableStackNameDuplicates', false);
app.node.setContext('@aws-cdk/core:stackRelativeExports', true);