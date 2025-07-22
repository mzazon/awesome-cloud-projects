#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ec2 from 'aws-cdk-lib/aws-ec2';

/**
 * Stack for Self-Service File Management with AWS Transfer Family Web Apps
 * 
 * This stack creates:
 * - S3 bucket with versioning and encryption
 * - IAM roles for S3 Access Grants and Transfer Family integration
 * - VPC endpoint configuration for Transfer Family Web App
 * - Sample file structure for demonstration
 * 
 * Note: Some resources like S3 Access Grants and Transfer Family Web Apps
 * require manual configuration or CloudFormation custom resources as they
 * may not have full CDK construct support yet.
 */
export class SelfServiceFileManagementStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = cdk.Names.uniqueId(this).slice(-6).toLowerCase();

    // ============================================
    // Parameters for External Dependencies
    // ============================================

    const identityCenterInstanceArn = new cdk.CfnParameter(this, 'IdentityCenterInstanceArn', {
      type: 'String',
      description: 'ARN of the existing IAM Identity Center instance',
      constraintDescription: 'Must be a valid IAM Identity Center instance ARN',
      default: '',
    });

    const identityStoreId = new cdk.CfnParameter(this, 'IdentityStoreId', {
      type: 'String',
      description: 'ID of the Identity Store associated with IAM Identity Center',
      constraintDescription: 'Must be a valid Identity Store ID',
      default: '',
    });

    // ============================================
    // S3 Bucket Configuration
    // ============================================
    
    const fileManagementBucket = new s3.Bucket(this, 'FileManagementBucket', {
      bucketName: `file-management-demo-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'OptimizeStorageCosts',
          enabled: true,
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
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      autoDeleteObjects: true, // For demo purposes
    });

    // S3 bucket notifications can be added later for audit logging
    // fileManagementBucket.addEventNotification() can be configured with Lambda or SNS targets

    // Create sample folder structure using bucket deployment
    new s3deploy.BucketDeployment(this, 'SampleFiles', {
      sources: [
        s3deploy.Source.data('user-files/documents/README.txt', 
          `Welcome to the Secure File Management Portal!

This system provides a secure, easy-to-use interface for managing your files.

Getting Started:
1. Navigate through folders using the web interface
2. Upload files by dragging and dropping or using the upload button
3. Download files by clicking on them
4. Create new folders using the "New Folder" button

For support, contact your IT administrator.`),
        s3deploy.Source.data('user-files/documents/sample-document.txt',
          `This is a sample document to demonstrate file management capabilities.
You can upload, download, and manage files like this one through the web interface.`),
        s3deploy.Source.data('user-files/shared/team-resources.txt',
          `This folder contains shared resources for the team.
All team members have access to files in this location.`),
      ],
      destinationBucket: fileManagementBucket,
      retainOnDelete: false,
    });

    // ============================================
    // IAM Roles for S3 Access Grants
    // ============================================

    // Role for S3 Access Grants to assume
    const accessGrantsRole = new iam.Role(this, 'S3AccessGrantsRole', {
      roleName: `S3AccessGrantsRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('s3.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonS3FullAccess'),
      ],
      description: 'Role for S3 Access Grants to manage bucket access',
    });

    // Add custom policy for more granular S3 access
    accessGrantsRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        's3:GetObject',
        's3:PutObject',
        's3:DeleteObject',
        's3:ListBucket',
        's3:GetBucketLocation',
        's3:GetObjectVersion',
        's3:PutObjectAcl',
        's3:GetObjectAcl',
      ],
      resources: [
        fileManagementBucket.bucketArn,
        `${fileManagementBucket.bucketArn}/*`,
      ],
    }));

    // Identity Bearer Role for Transfer Family Web App
    const identityBearerRole = new iam.Role(this, 'TransferIdentityBearerRole', {
      roleName: `TransferIdentityBearerRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('transfer.amazonaws.com'),
      description: 'Role for Transfer Family Web App to integrate with S3 Access Grants',
      inlinePolicies: {
        'S3AccessGrantsPolicy': new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetDataAccess',
                's3control:GetDataAccess',
                's3control:CreateAccessGrant',
                's3control:GetAccessGrant',
                's3control:ListAccessGrants',
              ],
              resources: ['*'],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'sso:DescribeInstance',
                'sso:ListInstances',
                'identitystore:DescribeUser',
                'identitystore:ListUsers',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Grantee role for users accessing S3 through Access Grants
    const granteeRole = new iam.Role(this, 'S3AccessGrantsGranteeRole', {
      roleName: `S3AccessGrantsGranteeRole-${uniqueSuffix}`,
      assumedBy: new iam.CompositePrincipal(
        new iam.ServicePrincipal('s3.amazonaws.com'),
        new iam.ArnPrincipal(identityCenterInstanceArn.valueAsString),
      ),
      description: 'Role for users to access S3 resources through Access Grants',
      inlinePolicies: {
        'S3AccessPolicy': new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket',
              ],
              resources: [
                fileManagementBucket.bucketArn,
                `${fileManagementBucket.bucketArn}/*`,
              ],
              conditions: {
                StringLike: {
                  's3:prefix': ['user-files/*'],
                },
              },
            }),
          ],
        }),
      },
    });

    // ============================================
    // VPC Configuration for Transfer Family Web App
    // ============================================

    // Use default VPC or create a simple VPC for the web app endpoint
    let vpc: ec2.IVpc;
    
    try {
      vpc = ec2.Vpc.fromLookup(this, 'DefaultVpc', {
        isDefault: true,
      });
    } catch (error) {
      // If no default VPC exists, create a simple one
      vpc = new ec2.Vpc(this, 'TransferFamilyVpc', {
        maxAzs: 2,
        natGateways: 0, // Use public subnets only for demo
        subnetConfiguration: [
          {
            cidrMask: 24,
            name: 'Public',
            subnetType: ec2.SubnetType.PUBLIC,
          },
        ],
      });
    }

    // Security group for Transfer Family Web App
    const webAppSecurityGroup = new ec2.SecurityGroup(this, 'WebAppSecurityGroup', {
      vpc,
      description: 'Security group for Transfer Family Web App',
      allowAllOutbound: true,
    });

    webAppSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'Allow HTTPS access to Transfer Family Web App'
    );

    // ============================================
    // CloudFormation Custom Resources for Advanced Features
    // ============================================

    // S3 Access Grants Instance (using CloudFormation)
    const accessGrantsInstance = new cdk.CfnResource(this, 'AccessGrantsInstance', {
      type: 'AWS::S3Control::AccessGrantsInstance',
      properties: {
        IdentityCenterArn: identityCenterInstanceArn.valueAsString,
        Tags: [
          { Key: 'Name', Value: `file-management-grants-${uniqueSuffix}` },
          { Key: 'Purpose', Value: 'FileManagement' },
        ],
      },
    });

    // S3 Access Grants Location
    const accessGrantsLocation = new cdk.CfnResource(this, 'AccessGrantsLocation', {
      type: 'AWS::S3Control::AccessGrantsLocation',
      properties: {
        IamRoleArn: accessGrantsRole.roleArn,
        LocationScope: `${fileManagementBucket.bucketArn}/*`,
        Tags: [
          { Key: 'Name', Value: 'FileManagementLocation' },
        ],
      },
    });

    accessGrantsLocation.addDependency(accessGrantsInstance);

    // Transfer Family Web App (using CloudFormation)
    const webApp = new cdk.CfnResource(this, 'FileManagementWebApp', {
      type: 'AWS::Transfer::WebApp',
      properties: {
        IdentityProviderType: 'SERVICE_MANAGED',
        IdentityProviderDetails: {
          IdentityCenterConfig: {
            InstanceArn: identityCenterInstanceArn.valueAsString,
            Role: identityBearerRole.roleArn,
          },
        },
        AccessEndpoint: {
          Type: 'VPC',
          VpcId: vpc.vpcId,
          SubnetIds: vpc.publicSubnets.slice(0, 1).map(subnet => subnet.subnetId),
        },
        Tags: [
          { Key: 'Name', Value: `file-management-webapp-${uniqueSuffix}` },
          { Key: 'Environment', Value: 'Demo' },
        ],
      },
    });

    webApp.addDependency(identityBearerRole.node.defaultChild as cdk.CfnResource);

    // ============================================
    // Stack Outputs
    // ============================================

    new cdk.CfnOutput(this, 'S3BucketName', {
      value: fileManagementBucket.bucketName,
      description: 'Name of the S3 bucket for file storage',
      exportName: `${this.stackName}-S3BucketName`,
    });

    new cdk.CfnOutput(this, 'S3BucketArn', {
      value: fileManagementBucket.bucketArn,
      description: 'ARN of the S3 bucket for file storage',
      exportName: `${this.stackName}-S3BucketArn`,
    });

    new cdk.CfnOutput(this, 'S3BucketConsoleUrl', {
      value: `https://s3.console.aws.amazon.com/s3/buckets/${fileManagementBucket.bucketName}`,
      description: 'AWS Console URL for the S3 bucket',
    });

    new cdk.CfnOutput(this, 'AccessGrantsInstanceArn', {
      value: accessGrantsInstance.getAtt('AccessGrantsInstanceArn').toString(),
      description: 'ARN of the S3 Access Grants instance',
      exportName: `${this.stackName}-AccessGrantsInstanceArn`,
    });

    new cdk.CfnOutput(this, 'IdentityBearerRoleArn', {
      value: identityBearerRole.roleArn,
      description: 'ARN of the Identity Bearer Role for Transfer Family',
      exportName: `${this.stackName}-IdentityBearerRoleArn`,
    });

    new cdk.CfnOutput(this, 'AccessGrantsRoleArn', {
      value: accessGrantsRole.roleArn,
      description: 'ARN of the S3 Access Grants Role',
      exportName: `${this.stackName}-AccessGrantsRoleArn`,
    });

    new cdk.CfnOutput(this, 'WebAppArn', {
      value: webApp.getAtt('Arn').toString(),
      description: 'ARN of the Transfer Family Web App',
      exportName: `${this.stackName}-WebAppArn`,
    });

    new cdk.CfnOutput(this, 'WebAppEndpoint', {
      value: webApp.getAtt('WebAppEndpoint').toString(),
      description: 'URL endpoint of the Transfer Family Web App',
      exportName: `${this.stackName}-WebAppEndpoint`,
    });

    new cdk.CfnOutput(this, 'VpcId', {
      value: vpc.vpcId,
      description: 'VPC ID used for Transfer Family Web App',
      exportName: `${this.stackName}-VpcId`,
    });

    new cdk.CfnOutput(this, 'DeploymentInstructions', {
      value: 'After deployment, configure IAM Identity Center users and create Access Grants via AWS CLI or Console',
      description: 'Next steps for completing the setup',
    });

    // ============================================
    // Tagging
    // ============================================

    cdk.Tags.of(this).add('Project', 'SelfServiceFileManagement');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('CostCenter', 'IT-Infrastructure');
    cdk.Tags.of(this).add('Owner', 'CloudOpsTeam');
    cdk.Tags.of(this).add('Purpose', 'FileTransferSolution');
  }
}

// ============================================
// CDK App Configuration
// ============================================

const app = new cdk.App();

// Create the stack with environment configuration
new SelfServiceFileManagementStack(app, 'SelfServiceFileManagementStack', {
  description: 'Self-Service File Management with AWS Transfer Family Web Apps, S3 Access Grants, and IAM Identity Center integration',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Application: 'SelfServiceFileManagement',
    Version: '1.0.0',
    CreatedBy: 'CDK',
    Recipe: 'self-service-file-management-transfer-family-web-apps-identity-center',
  },
});

// Synthesize the app
app.synth();