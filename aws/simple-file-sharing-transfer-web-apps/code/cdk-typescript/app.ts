#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as transfer from 'aws-cdk-lib/aws-transfer';
import * as sso from 'aws-cdk-lib/aws-sso';
import * as s3control from 'aws-cdk-lib/aws-s3control';

/**
 * Stack for Simple File Sharing with Transfer Family Web Apps
 * 
 * This stack creates:
 * - S3 bucket with versioning and encryption
 * - S3 Access Grants for fine-grained access control
 * - Transfer Family Web App for browser-based file sharing
 * - IAM roles and policies for secure access
 */
export class SimpleFileSharingStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // S3 Bucket for file storage with enterprise-grade security
    const fileSharingBucket = new s3.Bucket(this, 'FileSharingBucket', {
      bucketName: `file-sharing-demo-${uniqueSuffix}`,
      versioned: true, // Enable versioning for file history tracking
      encryption: s3.BucketEncryption.S3_MANAGED, // Server-side encryption
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true, // Require SSL for all requests
      lifecycleRules: [
        {
          id: 'delete-incomplete-multipart-uploads',
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
        },
      ],
      cors: [
        {
          allowedMethods: [
            s3.HttpMethods.GET,
            s3.HttpMethods.PUT,
            s3.HttpMethods.POST,
            s3.HttpMethods.DELETE,
            s3.HttpMethods.HEAD,
          ],
          allowedOrigins: ['*'], // Will be updated after Transfer Family Web App creation
          allowedHeaders: ['*'],
          exposedHeaders: [
            'last-modified',
            'content-length',
            'etag',
            'x-amz-version-id',
            'content-type',
            'x-amz-request-id',
            'x-amz-id-2',
            'date',
            'x-amz-cf-id',
            'x-amz-storage-class',
          ],
          maxAge: 3000,
        },
      ],
    });

    // IAM role for S3 Access Grants Location
    const s3AccessGrantsLocationRole = new iam.Role(this, 'S3AccessGrantsLocationRole', {
      roleName: `S3AccessGrantsLocationRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('s3.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonS3FullAccess'),
      ],
      inlinePolicies: {
        S3AccessGrantsPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket',
                's3:GetObjectVersion',
                's3:DeleteObjectVersion',
              ],
              resources: [
                fileSharingBucket.bucketArn,
                `${fileSharingBucket.bucketArn}/*`,
              ],
            }),
          ],
        }),
      },
    });

    // IAM role for Transfer Family Web App
    const transferFamilyWebAppRole = new iam.Role(this, 'TransferFamilyWebAppRole', {
      roleName: `TransferFamily-S3AccessGrants-WebAppRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('transfer.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSTransferReadOnlyAccess'),
      ],
      inlinePolicies: {
        S3AccessGrantsPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetAccessGrant',
                's3:GetDataAccess',
              ],
              resources: ['*'],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'identitystore:DescribeUser',
                'identitystore:DescribeGroup',
                'identitystore:ListGroupMemberships',
                'identitystore:IsMemberInGroups',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Get the existing IAM Identity Center instance ARN
    // Note: This assumes IAM Identity Center is already enabled
    // In practice, you would need to create this outside of CDK or use custom resources
    const identityCenterInstanceArn = `arn:aws:sso:::instance/ssoins-${this.account}`;

    // S3 Access Grants Instance
    // Note: This is created using L1 constructs as L2 constructs may not be available
    const accessGrantsInstance = new s3control.CfnAccessGrantsInstance(this, 'AccessGrantsInstance', {
      identityCenterArn: identityCenterInstanceArn,
      tags: [
        {
          key: 'Name',
          value: `AccessGrantsInstance-${uniqueSuffix}`,
        },
      ],
    });

    // S3 Access Grants Location
    const accessGrantsLocation = new s3control.CfnAccessGrantsLocation(this, 'AccessGrantsLocation', {
      locationScope: `${fileSharingBucket.bucketArn}/*`,
      iamRoleArn: s3AccessGrantsLocationRole.roleArn,
      tags: [
        {
          key: 'Name',
          value: `AccessGrantsLocation-${uniqueSuffix}`,
        },
      ],
    });

    // Ensure Access Grants Location depends on the instance
    accessGrantsLocation.addDependency(accessGrantsInstance);

    // Transfer Family Web App
    const webApp = new transfer.CfnWebApp(this, 'TransferFamilyWebApp', {
      identityProviderDetails: {
        identityCenterConfig: {
          instanceArn: identityCenterInstanceArn,
          role: transferFamilyWebAppRole.roleArn,
        },
      },
      tags: [
        {
          key: 'Name',
          value: `file-sharing-app-${uniqueSuffix}`,
        },
        {
          key: 'Purpose',
          value: 'FileSharing',
        },
      ],
    });

    // Outputs for reference and validation
    new cdk.CfnOutput(this, 'BucketName', {
      value: fileSharingBucket.bucketName,
      description: 'Name of the S3 bucket for file sharing',
    });

    new cdk.CfnOutput(this, 'BucketArn', {
      value: fileSharingBucket.bucketArn,
      description: 'ARN of the S3 bucket for file sharing',
    });

    new cdk.CfnOutput(this, 'WebAppId', {
      value: webApp.attrWebAppId,
      description: 'Transfer Family Web App ID',
    });

    new cdk.CfnOutput(this, 'WebAppAccessEndpoint', {
      value: webApp.attrAccessEndpoint,
      description: 'Transfer Family Web App access endpoint URL',
    });

    new cdk.CfnOutput(this, 'AccessGrantsLocationId', {
      value: accessGrantsLocation.attrAccessGrantsLocationId,
      description: 'S3 Access Grants Location ID',
    });

    new cdk.CfnOutput(this, 'S3AccessGrantsLocationRoleArn', {
      value: s3AccessGrantsLocationRole.roleArn,
      description: 'ARN of the S3 Access Grants Location role',
    });

    new cdk.CfnOutput(this, 'TransferFamilyWebAppRoleArn', {
      value: transferFamilyWebAppRole.roleArn,
      description: 'ARN of the Transfer Family Web App role',
    });

    new cdk.CfnOutput(this, 'IdentityCenterInstanceArn', {
      value: identityCenterInstanceArn,
      description: 'IAM Identity Center instance ARN (must be enabled manually)',
    });

    // Instructions for manual steps
    new cdk.CfnOutput(this, 'PostDeploymentInstructions', {
      value: [
        '1. Ensure IAM Identity Center is enabled in your AWS account',
        '2. Create users in IAM Identity Center',
        '3. Create S3 Access Grants for users using the Access Grants Location ID',
        '4. Assign users to the Transfer Family Web App',
        '5. Update S3 bucket CORS with the Web App access endpoint',
      ].join(' | '),
      description: 'Manual steps required after CDK deployment',
    });
  }
}

// CDK App
const app = new cdk.App();

new SimpleFileSharingStack(app, 'SimpleFileSharingStack', {
  description: 'Simple File Sharing with Transfer Family Web Apps',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'SimpleFileSharing',
    Environment: 'Demo',
    ManagedBy: 'CDK',
  },
});