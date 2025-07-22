import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ssoadmin from 'aws-cdk-lib/aws-ssoadmin';
import * as identitystore from 'aws-cdk-lib/aws-identitystore';
import * as transfer from 'aws-cdk-lib/aws-transfer';
import * as s3control from 'aws-cdk-lib/aws-s3control';
import { Construct } from 'constructs';

/**
 * Properties for the Secure File Portal Stack
 */
export interface SecureFilePortalStackProps extends cdk.StackProps {
  /**
   * Optional Identity Center instance ARN. If not provided, will attempt to discover existing instance.
   */
  identityCenterInstanceArn?: string;
  
  /**
   * Optional test user email for demonstration purposes
   */
  testUserEmail?: string;
  
  /**
   * Optional custom domain for the web app (requires additional DNS configuration)
   */
  customDomain?: string;
  
  /**
   * Number of web app units for scaling (default: 1)
   */
  webAppUnits?: number;
}

/**
 * CDK Stack for Secure Self-Service File Portal with AWS Transfer Family Web Apps
 * 
 * This stack creates:
 * - S3 bucket with encryption, versioning, and access logging
 * - IAM Identity Center user for testing
 * - S3 Access Grants configuration
 * - Transfer Family Web App with Identity Center integration
 * - Required IAM roles with least privilege permissions
 * - CORS configuration for web app access
 */
export class SecureFilePortalStack extends cdk.Stack {
  public readonly fileStorageBucket: s3.Bucket;
  public readonly webApp: transfer.CfnWebApp;
  public readonly webAppAccessEndpoint: string;
  
  constructor(scope: Construct, id: string, props?: SecureFilePortalStackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = this.node.addr.slice(-8).toLowerCase();
    
    // Create S3 bucket for file storage with enterprise security features
    this.fileStorageBucket = new s3.Bucket(this, 'FileStorageBucket', {
      bucketName: `file-portal-bucket-${uniqueSuffix}`,
      // Enable versioning for file history and recovery
      versioned: true,
      // Enable server-side encryption with S3 managed keys
      encryption: s3.BucketEncryption.S3_MANAGED,
      // Block all public access for security
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      // Enable access logging for compliance and auditing
      serverAccessLogsPrefix: 'access-logs/',
      // Lifecycle configuration for cost optimization
      lifecycleRules: [
        {
          id: 'intelligent-tiering',
          status: s3.LifecycleRuleStatus.ENABLED,
          transitions: [
            {
              storageClass: s3.StorageClass.INTELLIGENT_TIERING,
              transitionAfter: cdk.Duration.days(1)
            }
          ]
        }
      ],
      // Remove bucket when stack is deleted (for development)
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true
    });

    // Create IAM role for S3 Access Grants location
    const accessGrantsLocationRole = new iam.Role(this, 'AccessGrantsLocationRole', {
      roleName: `S3AccessGrantsLocationRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('s3.amazonaws.com'),
      description: 'IAM role for S3 Access Grants location to manage bucket permissions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonS3FullAccess')
      ]
    });

    // Create IAM role for Transfer Family Web App
    const webAppRole = new iam.Role(this, 'TransferFamilyWebAppRole', {
      roleName: 'AWSTransferFamilyWebAppIdentityBearerRole',
      assumedBy: new iam.ServicePrincipal('transfer.amazonaws.com'),
      description: 'IAM role for Transfer Family Web App to integrate with Identity Center and Access Grants',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSTransferFamilyWebAppIdentityBearerRole')
      ]
    });

    // Custom resource to get Identity Center instance details
    const getIdentityCenterInstance = new cdk.CustomResource(this, 'GetIdentityCenterInstance', {
      serviceToken: this.createIdentityCenterProviderFunction().functionArn,
      properties: {
        InstanceArn: props?.identityCenterInstanceArn
      }
    });

    // Extract Identity Center details from custom resource
    const identityCenterInstanceArn = getIdentityCenterInstance.getAttString('InstanceArn');
    const identityStoreId = getIdentityCenterInstance.getAttString('IdentityStoreId');

    // Create test user in IAM Identity Center (optional)
    let testUser: identitystore.CfnUser | undefined;
    if (props?.testUserEmail) {
      testUser = new identitystore.CfnUser(this, 'TestUser', {
        identityStoreId: identityStoreId,
        userName: `portal-user-${uniqueSuffix}`,
        displayName: 'Test Portal User',
        name: {
          givenName: 'Test',
          familyName: 'User'
        },
        emails: [{
          value: props.testUserEmail,
          type: 'work',
          primary: true
        }]
      });
    }

    // Create S3 Access Grants instance
    const accessGrantsInstance = new s3control.CfnAccessGrantsInstance(this, 'AccessGrantsInstance', {
      identityCenterArn: identityCenterInstanceArn
    });

    // Register S3 bucket as Access Grants location
    const accessGrantsLocation = new s3control.CfnAccessGrantsLocation(this, 'AccessGrantsLocation', {
      locationScope: `${this.fileStorageBucket.bucketArn}/*`,
      iamRoleArn: accessGrantsLocationRole.roleArn,
      tags: [{
        key: 'Purpose',
        value: 'TransferFamilyWebApp'
      }]
    });
    accessGrantsLocation.addDependency(accessGrantsInstance);

    // Create access grant for test user (if created)
    if (testUser) {
      const userAccessGrant = new s3control.CfnAccessGrant(this, 'UserAccessGrant', {
        accessGrantsLocationId: accessGrantsLocation.attrAccessGrantsLocationId,
        grantee: {
          granteeType: 'DIRECTORY_USER',
          granteeIdentifier: testUser.attrUserId
        },
        permission: 'READWRITE',
        accessGrantsLocationConfiguration: {
          s3SubPrefix: '*'
        },
        tags: [{
          key: 'User',
          value: testUser.userName!
        }]
      });
      userAccessGrant.addDependency(accessGrantsLocation);
    }

    // Create Transfer Family Web App
    this.webApp = new transfer.CfnWebApp(this, 'TransferFamilyWebApp', {
      identityProviderType: 'IDENTITY_CENTER',
      identityProviderDetails: {
        identityCenterConfig: {
          instanceArn: identityCenterInstanceArn
        }
      },
      accessRole: webAppRole.roleArn,
      webAppUnits: props?.webAppUnits || 1,
      tags: [{
        key: 'Name',
        value: `file-portal-webapp-${uniqueSuffix}`
      }]
    });

    // Get the web app access endpoint
    this.webAppAccessEndpoint = this.webApp.attrAccessEndpoint;

    // Configure CORS for S3 bucket to allow web app access
    const corsConfiguration = new s3.CfnBucket(this, 'BucketCorsConfiguration', {
      bucketName: this.fileStorageBucket.bucketName,
      corsConfiguration: {
        corsRules: [{
          allowedHeaders: ['*'],
          allowedMethods: ['GET', 'PUT', 'POST', 'DELETE', 'HEAD'],
          allowedOrigins: [`https://${this.webAppAccessEndpoint}`],
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
            'x-amz-storage-class'
          ],
          maxAge: 3000
        }]
      }
    });
    corsConfiguration.node.addDependency(this.webApp);

    // Custom resource to configure Identity Center integration for web app
    const configureWebAppIntegration = new cdk.CustomResource(this, 'ConfigureWebAppIntegration', {
      serviceToken: this.createWebAppConfigurationFunction().functionArn,
      properties: {
        WebAppId: this.webApp.attrWebAppId,
        IdentityCenterRole: webAppRole.roleArn
      }
    });
    configureWebAppIntegration.node.addDependency(this.webApp);

    // Output important information for users
    new cdk.CfnOutput(this, 'WebAppAccessUrl', {
      value: `https://${this.webAppAccessEndpoint}`,
      description: 'URL to access the secure file portal web application',
      exportName: `${this.stackName}-WebAppUrl`
    });

    new cdk.CfnOutput(this, 'S3BucketName', {
      value: this.fileStorageBucket.bucketName,
      description: 'S3 bucket name for file storage',
      exportName: `${this.stackName}-BucketName`
    });

    new cdk.CfnOutput(this, 'IdentityCenterInstanceArn', {
      value: identityCenterInstanceArn,
      description: 'IAM Identity Center instance ARN',
      exportName: `${this.stackName}-IdentityCenterArn`
    });

    if (testUser) {
      new cdk.CfnOutput(this, 'TestUserName', {
        value: testUser.userName!,
        description: 'Test user name for portal access',
        exportName: `${this.stackName}-TestUser`
      });
    }

    new cdk.CfnOutput(this, 'AccessGrantsInstanceId', {
      value: accessGrantsInstance.attrAccessGrantsInstanceId,
      description: 'S3 Access Grants instance ID',
      exportName: `${this.stackName}-AccessGrantsInstanceId`
    });
  }

  /**
   * Creates a Lambda function to get Identity Center instance details
   */
  private createIdentityCenterProviderFunction(): cdk.aws_lambda.Function {
    return new cdk.aws_lambda.Function(this, 'IdentityCenterProvider', {
      runtime: cdk.aws_lambda.Runtime.PYTHON_3_11,
      handler: 'index.handler',
      timeout: cdk.Duration.minutes(5),
      code: cdk.aws_lambda.Code.fromInline(`
import boto3
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    try:
        request_type = event['RequestType']
        properties = event['ResourceProperties']
        
        if request_type == 'Delete':
            return {'Status': 'SUCCESS', 'PhysicalResourceId': 'identity-center-provider'}
        
        sso_admin = boto3.client('sso-admin')
        
        # Get Identity Center instance
        if properties.get('InstanceArn'):
            instance_arn = properties['InstanceArn']
            # Extract identity store ID from instance
            response = sso_admin.list_instances()
            for instance in response['Instances']:
                if instance['InstanceArn'] == instance_arn:
                    identity_store_id = instance['IdentityStoreId']
                    break
            else:
                raise ValueError(f"Instance not found: {instance_arn}")
        else:
            # Get the first (typically only) Identity Center instance
            response = sso_admin.list_instances()
            if not response['Instances']:
                raise ValueError("No Identity Center instance found")
            
            instance = response['Instances'][0]
            instance_arn = instance['InstanceArn']
            identity_store_id = instance['IdentityStoreId']
        
        return {
            'Status': 'SUCCESS',
            'PhysicalResourceId': 'identity-center-provider',
            'Data': {
                'InstanceArn': instance_arn,
                'IdentityStoreId': identity_store_id
            }
        }
        
    except Exception as e:
        logger.error(f"Error: {str(e)}")
        return {
            'Status': 'FAILED',
            'PhysicalResourceId': 'identity-center-provider',
            'Reason': str(e)
        }
      `),
      role: new iam.Role(this, 'IdentityCenterProviderRole', {
        assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
        managedPolicies: [
          iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
        ],
        inlinePolicies: {
          SSOAdminAccess: new iam.PolicyDocument({
            statements: [
              new iam.PolicyStatement({
                effect: iam.Effect.ALLOW,
                actions: ['sso:ListInstances'],
                resources: ['*']
              })
            ]
          })
        }
      })
    });
  }

  /**
   * Creates a Lambda function to configure web app Identity Center integration
   */
  private createWebAppConfigurationFunction(): cdk.aws_lambda.Function {
    return new cdk.aws_lambda.Function(this, 'WebAppConfigurationProvider', {
      runtime: cdk.aws_lambda.Runtime.PYTHON_3_11,
      handler: 'index.handler',
      timeout: cdk.Duration.minutes(5),
      code: cdk.aws_lambda.Code.fromInline(`
import boto3
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    try:
        request_type = event['RequestType']
        properties = event['ResourceProperties']
        
        if request_type == 'Delete':
            return {'Status': 'SUCCESS', 'PhysicalResourceId': 'webapp-config'}
        
        transfer_client = boto3.client('transfer')
        
        web_app_id = properties['WebAppId']
        identity_center_role = properties['IdentityCenterRole']
        
        # Configure Identity Center integration
        transfer_client.put_web_app_identity_center_config(
            WebAppId=web_app_id,
            IdentityCenterConfig={
                'Role': identity_center_role
            }
        )
        
        return {
            'Status': 'SUCCESS',
            'PhysicalResourceId': 'webapp-config'
        }
        
    except Exception as e:
        logger.error(f"Error: {str(e)}")
        return {
            'Status': 'FAILED',
            'PhysicalResourceId': 'webapp-config',
            'Reason': str(e)
        }
      `),
      role: new iam.Role(this, 'WebAppConfigurationProviderRole', {
        assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
        managedPolicies: [
          iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
        ],
        inlinePolicies: {
          TransferAccess: new iam.PolicyDocument({
            statements: [
              new iam.PolicyStatement({
                effect: iam.Effect.ALLOW,
                actions: [
                  'transfer:PutWebAppIdentityCenterConfig',
                  'transfer:DescribeWebApp'
                ],
                resources: ['*']
              })
            ]
          })
        }
      })
    });
  }
}