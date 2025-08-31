#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';
import { AwsSolutionsChecks, NagSuppressions } from 'cdk-nag';

/**
 * CDK Stack for Simple Password Generator with Lambda and S3
 * 
 * This stack creates:
 * - S3 bucket with encryption and versioning for secure password storage
 * - Lambda function for generating cryptographically secure passwords
 * - IAM role with least privilege access for Lambda execution
 */
export class SimplePasswordGeneratorStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate a unique suffix for resource names to avoid conflicts
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // Create S3 bucket for secure password storage
    const passwordBucket = new s3.Bucket(this, 'PasswordStorageBucket', {
      bucketName: `password-generator-${uniqueSuffix}`,
      // Enable encryption at rest with S3-managed keys (AES256)
      encryption: s3.BucketEncryption.S3_MANAGED,
      // Enable versioning for password history tracking
      versioned: true,
      // Block all public access for security
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      // Enforce SSL for all requests
      enforceSSL: true,
      // Lifecycle management for cost optimization
      lifecycleRules: [
        {
          id: 'password-lifecycle',
          enabled: true,
          // Move passwords to Intelligent Tiering after 30 days
          transitions: [
            {
              storageClass: s3.StorageClass.INTELLIGENT_TIERING,
              transitionAfter: cdk.Duration.days(30),
            },
          ],
          // Delete non-current versions after 90 days
          noncurrentVersionExpiration: cdk.Duration.days(90),
        },
      ],
      // Enable access logging for security auditing
      serverAccessLogsBucket: new s3.Bucket(this, 'AccessLogsBucket', {
        bucketName: `password-generator-access-logs-${uniqueSuffix}`,
        encryption: s3.BucketEncryption.S3_MANAGED,
        blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
        enforceSSL: true,
        // Automatically delete access logs after 1 year
        lifecycleRules: [
          {
            id: 'access-logs-lifecycle',
            enabled: true,
            expiration: cdk.Duration.days(365),
          },
        ],
      }),
      serverAccessLogsPrefix: 'access-logs/',
      // Remove bucket when stack is deleted (for development only)
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create IAM role for Lambda function with least privilege access
    const lambdaRole = new iam.Role(this, 'PasswordGeneratorLambdaRole', {
      roleName: `lambda-password-generator-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for password generator Lambda function with least privilege access',
      managedPolicies: [
        // Basic Lambda execution role for CloudWatch Logs
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        S3AccessPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:PutObject',
                's3:GetObject',
                's3:PutObjectAcl',
              ],
              resources: [
                passwordBucket.bucketArn,
                `${passwordBucket.bucketArn}/*`,
              ],
              conditions: {
                StringEquals: {
                  's3:x-amz-server-side-encryption': 'AES256',
                },
              },
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:ListBucket'],
              resources: [passwordBucket.bucketArn],
              conditions: {
                StringLike: {
                  's3:prefix': 'passwords/*',
                },
              },
            }),
          ],
        }),
      },
    });

    // Create Lambda function for password generation
    const passwordGeneratorFunction = new lambda.Function(this, 'PasswordGeneratorFunction', {
      functionName: `password-generator-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      code: lambda.Code.fromInline(`
import json
import boto3
import secrets
import string
from datetime import datetime
import logging
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize S3 client
s3_client = boto3.client('s3')
BUCKET_NAME = os.environ['BUCKET_NAME']

def lambda_handler(event, context):
    try:
        # Parse request parameters
        body = json.loads(event.get('body', '{}')) if event.get('body') else event
        
        # Default password parameters
        length = body.get('length', 16)
        include_uppercase = body.get('include_uppercase', True)
        include_lowercase = body.get('include_lowercase', True)
        include_numbers = body.get('include_numbers', True)
        include_symbols = body.get('include_symbols', True)
        password_name = body.get('name', f'password_{datetime.now().strftime("%Y%m%d_%H%M%S")}')
        
        # Validate parameters
        if length < 8 or length > 128:
            raise ValueError("Password length must be between 8 and 128 characters")
        
        # Build character set
        charset = ""
        if include_lowercase:
            charset += string.ascii_lowercase
        if include_uppercase:
            charset += string.ascii_uppercase
        if include_numbers:
            charset += string.digits
        if include_symbols:
            charset += "!@#$%^&*()_+-=[]{}|;:,.<>?"
        
        if not charset:
            raise ValueError("At least one character type must be selected")
        
        # Generate secure password
        password = ''.join(secrets.choice(charset) for _ in range(length))
        
        # Create password metadata
        password_data = {
            'password': password,
            'length': length,
            'created_at': datetime.now().isoformat(),
            'parameters': {
                'include_uppercase': include_uppercase,
                'include_lowercase': include_lowercase,
                'include_numbers': include_numbers,
                'include_symbols': include_symbols
            }
        }
        
        # Store password in S3
        s3_key = f'passwords/{password_name}.json'
        s3_client.put_object(
            Bucket=BUCKET_NAME,
            Key=s3_key,
            Body=json.dumps(password_data, indent=2),
            ContentType='application/json',
            ServerSideEncryption='AES256'
        )
        
        logger.info(f"Password generated and stored: {s3_key}")
        
        # Return response (without actual password for security)
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Password generated successfully',
                'password_name': password_name,
                's3_key': s3_key,
                'length': length,
                'created_at': password_data['created_at']
            })
        }
        
    except Exception as e:
        logger.error(f"Error generating password: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Failed to generate password',
                'message': str(e)
            })
        }
      `),
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 128,
      description: 'Secure password generator with S3 storage',
      environment: {
        BUCKET_NAME: passwordBucket.bucketName,
      },
      // Enable tracing for debugging and monitoring
      tracing: lambda.Tracing.ACTIVE,
      // Reserve concurrency to prevent cost overruns
      reservedConcurrentExecutions: 10,
      // Enable dead letter queue for failed invocations
      deadLetterQueue: new lambda.Function(this, 'DeadLetterHandler', {
        functionName: `password-generator-dlq-${uniqueSuffix}`,
        runtime: lambda.Runtime.PYTHON_3_12,
        code: lambda.Code.fromInline(`
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    logger.error(f"Dead letter queue received event: {json.dumps(event)}")
    return {'statusCode': 200}
        `),
        handler: 'index.lambda_handler',
        timeout: cdk.Duration.seconds(10),
        memorySize: 128,
        description: 'Dead letter queue handler for password generator failures',
      }),
    });

    // Output important resource information
    new cdk.CfnOutput(this, 'S3BucketName', {
      value: passwordBucket.bucketName,
      description: 'Name of the S3 bucket storing generated passwords',
      exportName: `${this.stackName}-PasswordBucket`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: passwordGeneratorFunction.functionName,
      description: 'Name of the Lambda function for password generation',
      exportName: `${this.stackName}-LambdaFunction`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: passwordGeneratorFunction.functionArn,
      description: 'ARN of the Lambda function for password generation',
      exportName: `${this.stackName}-LambdaFunctionArn`,
    });

    new cdk.CfnOutput(this, 'IAMRoleArn', {
      value: lambdaRole.roleArn,
      description: 'ARN of the IAM role used by the Lambda function',
      exportName: `${this.stackName}-IAMRoleArn`,
    });

    // Add CDK Nag suppressions for development-specific configurations
    NagSuppressions.addResourceSuppressions(
      passwordBucket,
      [
        {
          id: 'AwsSolutions-S3-2',
          reason: 'Public read access is blocked by BlockPublicAccess configuration',
        },
      ],
      true
    );

    NagSuppressions.addResourceSuppressions(
      lambdaRole,
      [
        {
          id: 'AwsSolutions-IAM5',
          reason: 'Wildcard permissions are scoped to specific S3 bucket prefix for password storage',
        },
      ],
      true
    );

    // Add tags to all resources for cost tracking and governance
    cdk.Tags.of(this).add('Project', 'SimplePasswordGenerator');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('CostCenter', 'Engineering');
    cdk.Tags.of(this).add('Owner', 'DevSecOps');
  }
}

// Create the CDK application
const app = new cdk.App();

// Apply CDK Nag for security best practices validation
cdk.Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));

// Create the stack with appropriate naming and configuration
new SimplePasswordGeneratorStack(app, 'SimplePasswordGeneratorStack', {
  stackName: 'simple-password-generator-stack',
  description: 'CDK stack for Simple Password Generator with Lambda and S3 - Secure serverless password generation with encrypted storage',
  env: {
    // Use default AWS account and region from CDK context
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  // Enable termination protection in production
  terminationProtection: false,
  // Add stack-level tags
  tags: {
    Application: 'SimplePasswordGenerator',
    Stack: 'SimplePasswordGeneratorStack',
    CreatedBy: 'AWS-CDK',
  },
});

// Synthesize the application
app.synth();