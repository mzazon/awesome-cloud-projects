#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';

/**
 * CDK Stack for AWS CLI Setup and First Commands Recipe
 * 
 * This stack creates the infrastructure needed for learning AWS CLI basics:
 * - S3 bucket with encryption for practicing CLI commands
 * - Sample IAM user with appropriate permissions for CLI access
 * - Sample objects for testing CLI operations
 */
class AwsCliSetupStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate a unique suffix for bucket naming to avoid conflicts
    const uniqueSuffix = cdk.Names.uniqueId(this).toLowerCase().substring(0, 8);

    // Create S3 bucket with encryption for CLI practice
    const bucket = new s3.Bucket(this, 'CliTutorialBucket', {
      bucketName: `aws-cli-tutorial-bucket-${uniqueSuffix}`,
      
      // Enable server-side encryption with AES256 (as shown in recipe)
      encryption: s3.BucketEncryption.S3_MANAGED,
      
      // Enable versioning for better object management
      versioned: true,
      
      // Configure lifecycle rules to manage costs
      lifecycleRules: [
        {
          id: 'tutorial-cleanup',
          enabled: true,
          expiration: cdk.Duration.days(7), // Auto-delete after 7 days
          noncurrentVersionExpiration: cdk.Duration.days(1),
        },
      ],
      
      // Block public access for security
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      
      // Enable event notifications for advanced CLI learning
      eventBridgeEnabled: true,
      
      // Add removal policy for easy cleanup during development
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create IAM user for CLI access (following recipe requirements)
    const cliUser = new iam.User(this, 'CliTutorialUser', {
      userName: `aws-cli-tutorial-user-${uniqueSuffix}`,
      
      // Attach necessary policies for S3 operations
      managedPolicies: [
        // Allow STS operations for identity verification (aws sts get-caller-identity)
        iam.ManagedPolicy.fromAwsManagedPolicyName('ReadOnlyAccess'),
      ],
    });

    // Create custom policy for S3 operations on the tutorial bucket
    const s3Policy = new iam.PolicyDocument({
      statements: [
        // Allow all S3 operations on the tutorial bucket
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            's3:ListBucket',
            's3:GetBucketLocation',
            's3:GetBucketEncryption',
            's3:PutBucketEncryption',
            's3:GetObject',
            's3:PutObject',
            's3:DeleteObject',
            's3:PutObjectMetadata',
            's3:GetObjectMetadata',
            's3:ListBucketVersions',
          ],
          resources: [
            bucket.bucketArn,
            `${bucket.bucketArn}/*`,
          ],
        }),
        
        // Allow listing all buckets (for aws s3 ls command)
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: ['s3:ListAllMyBuckets'],
          resources: ['*'],
        }),
        
        // Allow STS operations for caller identity
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'sts:GetCallerIdentity',
          ],
          resources: ['*'],
        }),
      ],
    });

    // Attach the custom S3 policy to the user
    new iam.Policy(this, 'CliTutorialS3Policy', {
      policyName: `aws-cli-tutorial-s3-policy-${uniqueSuffix}`,
      document: s3Policy,
      users: [cliUser],
    });

    // Create access keys for CLI configuration
    const accessKey = new iam.AccessKey(this, 'CliTutorialAccessKey', {
      user: cliUser,
    });

    // Deploy sample files to the bucket for CLI practice
    // This creates the sample content similar to what's created in the recipe steps
    new s3deploy.BucketDeployment(this, 'SampleFiles', {
      sources: [
        s3deploy.Source.data('sample-file.txt', [
          'Hello AWS CLI! This is my first S3 object.',
          'AWS CLI makes cloud operations simple and scriptable.',
          `Created on ${new Date().toISOString()}`,
        ].join('\n')),
        
        s3deploy.Source.data('tutorial-readme.txt', [
          'AWS CLI Tutorial Sample Files',
          '================================',
          '',
          'This bucket contains sample files for practicing AWS CLI commands.',
          'You can use these files to test various CLI operations:',
          '',
          '1. List objects: aws s3 ls s3://bucket-name/',
          '2. Download files: aws s3 cp s3://bucket-name/file.txt .',
          '3. Upload files: aws s3 cp local-file.txt s3://bucket-name/',
          '4. Sync directories: aws s3 sync ./local-dir s3://bucket-name/remote-dir/',
          '',
          'For more information, visit: https://docs.aws.amazon.com/cli/',
        ].join('\n')),
      ],
      destinationBucket: bucket,
      
      // Add metadata to objects (similar to recipe example)
      metadata: {
        purpose: 'tutorial',
        'created-by': 'aws-cdk',
        'recipe-id': 'a1b2c3d4',
      },
    });

    // Output important values for CLI configuration
    new cdk.CfnOutput(this, 'BucketName', {
      value: bucket.bucketName,
      description: 'S3 bucket name for CLI practice',
    });

    new cdk.CfnOutput(this, 'BucketArn', {
      value: bucket.bucketArn,
      description: 'S3 bucket ARN',
    });

    new cdk.CfnOutput(this, 'UserName', {
      value: cliUser.userName,
      description: 'IAM user name for CLI access',
    });

    new cdk.CfnOutput(this, 'AccessKeyId', {
      value: accessKey.accessKeyId,
      description: 'Access Key ID for CLI configuration',
    });

    new cdk.CfnOutput(this, 'SecretAccessKey', {
      value: accessKey.secretAccessKey,
      description: 'Secret Access Key for CLI configuration (store securely!)',
    });

    new cdk.CfnOutput(this, 'Region', {
      value: this.region,
      description: 'AWS region for CLI configuration',
    });

    // Output CLI configuration instructions
    new cdk.CfnOutput(this, 'CliConfigInstructions', {
      value: [
        '1. Install AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html',
        '2. Run: aws configure',
        `3. Use Access Key ID: ${accessKey.accessKeyId}`,
        '4. Use Secret Access Key from SecretAccessKey output',
        `5. Set region: ${this.region}`,
        '6. Set output format: json',
        `7. Test with: aws s3 ls s3://${bucket.bucketName}/`,
      ].join(' | '),
      description: 'Step-by-step CLI configuration instructions',
    });

    // Add tags to all resources for cost tracking and management
    cdk.Tags.of(this).add('Project', 'AWS-CLI-Tutorial');
    cdk.Tags.of(this).add('Recipe', 'aws-cli-setup-first-commands');
    cdk.Tags.of(this).add('Environment', 'Tutorial');
    cdk.Tags.of(this).add('AutoCleanup', 'true');
  }
}

// Create the CDK app
const app = new cdk.App();

// Deploy the stack with consistent naming
new AwsCliSetupStack(app, 'AwsCliSetupStack', {
  description: 'Infrastructure for AWS CLI Setup and First Commands Tutorial (uksb-1234567890)',
  
  // Use default region from CDK context or environment
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Add stack-level tags
  tags: {
    Project: 'AWS-CLI-Tutorial',
    Recipe: 'aws-cli-setup-first-commands',
    CostCenter: 'Training',
  },
});

// Synthesize the CloudFormation template
app.synth();