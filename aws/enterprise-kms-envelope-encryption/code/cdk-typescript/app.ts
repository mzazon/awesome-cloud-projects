#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Enterprise KMS Envelope Encryption Stack
 * 
 * This stack implements enterprise-grade envelope encryption using AWS KMS
 * with automated key rotation monitoring and secure S3 storage integration.
 * 
 * Features:
 * - Customer Master Key (CMK) with automatic rotation enabled
 * - S3 bucket with server-side encryption using KMS
 * - Lambda function for key rotation monitoring
 * - CloudWatch Events for automated monitoring schedule
 * - IAM roles with least privilege access
 */
export class EnterpriseKmsEnvelopeEncryptionStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = this.node.addr.slice(-6).toLowerCase();

    // ============================================
    // KMS Customer Master Key (CMK) Configuration
    // ============================================

    /**
     * Create enterprise Customer Master Key with automatic rotation
     * 
     * This CMK serves as the root of trust for all envelope encryption operations.
     * Automatic rotation is enabled to ensure cryptographic best practices.
     */
    const enterpriseCmk = new kms.Key(this, 'EnterpriseCMK', {
      description: 'Enterprise envelope encryption master key',
      enableKeyRotation: true, // Enable automatic annual key rotation
      keyUsage: kms.KeyUsage.ENCRYPT_DECRYPT,
      keySpec: kms.KeySpec.SYMMETRIC_DEFAULT,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes - use RETAIN in production
    });

    // Create human-readable alias for the CMK
    const keyAlias = new kms.Alias(this, 'EnterpriseCMKAlias', {
      aliasName: `alias/enterprise-encryption-${uniqueSuffix}`,
      targetKey: enterpriseCmk,
    });

    // =============================================
    // S3 Bucket with KMS Encryption Configuration
    // =============================================

    /**
     * Create S3 bucket with server-side encryption using the enterprise CMK
     * 
     * This bucket automatically encrypts all objects using the CMK,
     * demonstrating envelope encryption for data at rest.
     */
    const encryptedBucket = new s3.Bucket(this, 'EncryptedDataBucket', {
      bucketName: `enterprise-encrypted-data-${uniqueSuffix}`,
      versioned: true, // Enable versioning for data protection
      encryption: s3.BucketEncryption.KMS,
      encryptionKey: enterpriseCmk,
      bucketKeyEnabled: true, // Reduce KMS API calls and costs
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true, // Require HTTPS for all requests
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      autoDeleteObjects: true, // For demo cleanup
    });

    // ================================================
    // IAM Role for Lambda Key Management Function
    // ================================================

    /**
     * Create IAM role for Lambda function with least privilege permissions
     * 
     * This role provides only the necessary permissions for KMS key monitoring
     * and CloudWatch logging operations.
     */
    const lambdaExecutionRole = new iam.Role(this, 'KeyRotationMonitorRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for KMS key rotation monitoring Lambda',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Create custom policy for KMS operations
    const kmsManagementPolicy = new iam.PolicyDocument({
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'kms:DescribeKey',
            'kms:GetKeyRotationStatus',
            'kms:EnableKeyRotation',
            'kms:ListKeys',
            'kms:ListAliases',
          ],
          resources: ['*'], // KMS operations require wildcard for list operations
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'logs:CreateLogGroup',
            'logs:CreateLogStream',
            'logs:PutLogEvents',
          ],
          resources: [
            `arn:aws:logs:${this.region}:${this.account}:log-group:/aws/lambda/*`,
          ],
        }),
      ],
    });

    // Attach custom policy to Lambda role
    new iam.Policy(this, 'KMSManagementPolicy', {
      document: kmsManagementPolicy,
      roles: [lambdaExecutionRole],
    });

    // ==============================================
    // Lambda Function for Key Rotation Monitoring
    // ==============================================

    /**
     * Lambda function that monitors KMS key rotation status
     * 
     * This function checks all customer-managed keys for rotation status
     * and can automatically enable rotation for compliance.
     */
    const keyRotationMonitor = new lambda.Function(this, 'KeyRotationMonitor', {
      functionName: `kms-key-rotator-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(60),
      memorySize: 128,
      description: 'Monitors KMS key rotation status and enables rotation for compliance',
      environment: {
        ENTERPRISE_CMK_ID: enterpriseCmk.keyId,
        ENTERPRISE_CMK_ALIAS: keyAlias.aliasName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Monitor KMS key rotation status for enterprise compliance
    
    This function checks all customer-managed keys for rotation status
    and ensures compliance with enterprise security policies.
    """
    kms_client = boto3.client('kms')
    
    try:
        # Get enterprise CMK details from environment
        enterprise_cmk_id = os.environ.get('ENTERPRISE_CMK_ID')
        enterprise_cmk_alias = os.environ.get('ENTERPRISE_CMK_ALIAS')
        
        # List all customer-managed keys
        paginator = kms_client.get_paginator('list_keys')
        
        rotation_status = []
        keys_checked = 0
        keys_with_rotation_enabled = 0
        
        for page in paginator.paginate():
            for key in page['Keys']:
                key_id = key['KeyId']
                
                try:
                    # Get key details
                    key_details = kms_client.describe_key(KeyId=key_id)
                    key_metadata = key_details['KeyMetadata']
                    
                    # Skip AWS-managed keys
                    if key_metadata['KeyManager'] == 'AWS':
                        continue
                    
                    # Skip keys that are not enabled
                    if key_metadata['KeyState'] != 'Enabled':
                        continue
                    
                    keys_checked += 1
                    
                    # Check rotation status
                    rotation_response = kms_client.get_key_rotation_status(KeyId=key_id)
                    rotation_enabled = rotation_response['KeyRotationEnabled']
                    
                    if rotation_enabled:
                        keys_with_rotation_enabled += 1
                    
                    key_info = {
                        'KeyId': key_id,
                        'KeyArn': key_metadata['Arn'],
                        'RotationEnabled': rotation_enabled,
                        'KeyState': key_metadata['KeyState'],
                        'CreationDate': key_metadata['CreationDate'].isoformat()
                    }
                    
                    # Add alias information if available
                    aliases = kms_client.list_aliases(KeyId=key_id)
                    if aliases['Aliases']:
                        key_info['Aliases'] = [alias['AliasName'] for alias in aliases['Aliases']]
                    
                    rotation_status.append(key_info)
                    
                    # Log key rotation status
                    logger.info(f"Key {key_id}: Rotation {'enabled' if rotation_enabled else 'disabled'}")
                    
                    # Highlight enterprise CMK status
                    if key_id == enterprise_cmk_id:
                        logger.info(f"Enterprise CMK ({enterprise_cmk_alias}): Rotation status = {rotation_enabled}")
                    
                    # Optional: Enable rotation if disabled (uncomment for automatic enablement)
                    # if not rotation_enabled:
                    #     logger.warning(f"Enabling rotation for key {key_id}")
                    #     kms_client.enable_key_rotation(KeyId=key_id)
                    #     keys_with_rotation_enabled += 1
                    
                except Exception as key_error:
                    logger.error(f"Error processing key {key_id}: {str(key_error)}")
                    continue
        
        # Generate summary report
        summary = {
            'timestamp': datetime.now().isoformat(),
            'keys_checked': keys_checked,
            'keys_with_rotation_enabled': keys_with_rotation_enabled,
            'compliance_percentage': (keys_with_rotation_enabled / keys_checked * 100) if keys_checked > 0 else 0,
            'enterprise_cmk_id': enterprise_cmk_id,
            'enterprise_cmk_alias': enterprise_cmk_alias
        }
        
        logger.info(f"Rotation monitoring completed: {summary}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Key rotation monitoring completed successfully',
                'summary': summary,
                'detailed_status': rotation_status
            }, default=str)
        }
        
    except Exception as e:
        logger.error(f"Error during key rotation monitoring: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Key rotation monitoring failed'
            })
        }
`),
    });

    // Create CloudWatch log group for Lambda with retention policy
    new logs.LogGroup(this, 'KeyRotationMonitorLogGroup', {
      logGroupName: `/aws/lambda/${keyRotationMonitor.functionName}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // ================================================
    // CloudWatch Events for Automated Execution
    // ================================================

    /**
     * CloudWatch Events rule for scheduled key rotation monitoring
     * 
     * This rule triggers the Lambda function weekly to ensure continuous
     * compliance monitoring of key rotation status.
     */
    const keyRotationSchedule = new events.Rule(this, 'KeyRotationSchedule', {
      description: 'Weekly KMS key rotation monitoring schedule',
      schedule: events.Schedule.rate(cdk.Duration.days(7)), // Weekly execution
      enabled: true,
    });

    // Add Lambda function as target for the schedule
    keyRotationSchedule.addTarget(new targets.LambdaFunction(keyRotationMonitor, {
      retryAttempts: 2, // Retry failed executions
    }));

    // ================================================
    // CloudFormation Outputs
    // ================================================

    // Output enterprise CMK information
    new cdk.CfnOutput(this, 'EnterpriseCMKId', {
      value: enterpriseCmk.keyId,
      description: 'Enterprise Customer Master Key ID',
      exportName: `${this.stackName}-EnterpriseCMKId`,
    });

    new cdk.CfnOutput(this, 'EnterpriseCMKAlias', {
      value: keyAlias.aliasName,
      description: 'Enterprise Customer Master Key Alias',
      exportName: `${this.stackName}-EnterpriseCMKAlias`,
    });

    new cdk.CfnOutput(this, 'EnterpriseCMKArn', {
      value: enterpriseCmk.keyArn,
      description: 'Enterprise Customer Master Key ARN',
      exportName: `${this.stackName}-EnterpriseCMKArn`,
    });

    // Output S3 bucket information
    new cdk.CfnOutput(this, 'EncryptedBucketName', {
      value: encryptedBucket.bucketName,
      description: 'S3 bucket with KMS encryption enabled',
      exportName: `${this.stackName}-EncryptedBucketName`,
    });

    new cdk.CfnOutput(this, 'EncryptedBucketArn', {
      value: encryptedBucket.bucketArn,
      description: 'S3 bucket ARN with KMS encryption',
      exportName: `${this.stackName}-EncryptedBucketArn`,
    });

    // Output Lambda function information
    new cdk.CfnOutput(this, 'KeyRotationMonitorArn', {
      value: keyRotationMonitor.functionArn,
      description: 'Key rotation monitoring Lambda function ARN',
      exportName: `${this.stackName}-KeyRotationMonitorArn`,
    });

    new cdk.CfnOutput(this, 'KeyRotationScheduleArn', {
      value: keyRotationSchedule.ruleArn,
      description: 'CloudWatch Events rule for key rotation monitoring',
      exportName: `${this.stackName}-KeyRotationScheduleArn`,
    });

    // Output deployment information
    new cdk.CfnOutput(this, 'StackRegion', {
      value: this.region,
      description: 'AWS region where the stack is deployed',
    });

    new cdk.CfnOutput(this, 'UniqueSuffix', {
      value: uniqueSuffix,
      description: 'Unique suffix used for resource naming',
    });
  }
}

// ================================================
// CDK Application Entry Point
// ================================================

/**
 * CDK Application for Enterprise KMS Envelope Encryption
 * 
 * This application deploys a complete enterprise-grade envelope encryption
 * solution with automated key rotation monitoring.
 */
const app = new cdk.App();

// Get deployment environment from CDK context or use defaults
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
};

// Deploy the enterprise KMS envelope encryption stack
new EnterpriseKmsEnvelopeEncryptionStack(app, 'EnterpriseKmsEnvelopeEncryptionStack', {
  env,
  description: 'Enterprise KMS envelope encryption with automated key rotation monitoring',
  tags: {
    Project: 'EnterpriseEncryption',
    Environment: 'Demo',
    Security: 'High',
    Compliance: 'Required',
  },
});

// Add stack-level tags for resource management
cdk.Tags.of(app).add('Application', 'EnterpriseKmsEnvelopeEncryption');
cdk.Tags.of(app).add('ManagedBy', 'AWS-CDK');
cdk.Tags.of(app).add('CostCenter', 'Security');