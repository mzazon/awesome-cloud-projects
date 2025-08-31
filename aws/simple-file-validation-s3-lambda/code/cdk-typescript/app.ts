#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * CDK Stack for Simple File Validation with S3 and Lambda
 * 
 * This stack creates:
 * - Three S3 buckets (upload, valid files, quarantine)
 * - Lambda function for file validation
 * - IAM roles and policies with least privilege access
 * - S3 event notifications to trigger Lambda
 * - CloudWatch Log Group for Lambda logs
 */
export class SimpleFileValidationStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // Create S3 Buckets
    // Upload bucket - where files are initially uploaded
    const uploadBucket = new s3.Bucket(this, 'UploadBucket', {
      bucketName: `file-upload-${uniqueSuffix}`,
      versioned: true, // Enable versioning for data protection
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true, // Require HTTPS for all requests
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes - use RETAIN in production
      autoDeleteObjects: true, // For demo purposes - remove in production
    });

    // Valid files bucket - for files that pass validation
    const validFilesBucket = new s3.Bucket(this, 'ValidFilesBucket', {
      bucketName: `valid-files-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Quarantine bucket - for files that fail validation
    const quarantineBucket = new s3.Bucket(this, 'QuarantineBucket', {
      bucketName: `quarantine-files-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create CloudWatch Log Group for Lambda function
    const logGroup = new logs.LogGroup(this, 'FileValidatorLogGroup', {
      logGroupName: `/aws/lambda/file-validator-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK, // Adjust retention as needed
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create Lambda function for file validation
    const fileValidatorFunction = new lambda.Function(this, 'FileValidatorFunction', {
      functionName: `file-validator-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.minutes(1),
      memorySize: 256,
      logGroup: logGroup,
      description: 'File validation function for S3 uploads - validates file types and sizes',
      environment: {
        VALID_BUCKET_NAME: validFilesBucket.bucketName,
        QUARANTINE_BUCKET_NAME: quarantineBucket.bucketName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import urllib.parse
import os
from datetime import datetime

s3_client = boto3.client('s3')

# Configuration - can be moved to environment variables for flexibility
MAX_FILE_SIZE = 10 * 1024 * 1024  # 10 MB
ALLOWED_EXTENSIONS = ['.txt', '.pdf', '.jpg', '.jpeg', '.png', '.doc', '.docx']

def lambda_handler(event, context):
    """
    Lambda handler for S3 event-triggered file validation.
    
    Validates uploaded files based on:
    - File size (max 10MB)
    - File extension (allowed types only)
    
    Valid files are moved to the valid bucket, invalid files to quarantine.
    """
    print(f"Received event: {json.dumps(event)}")
    
    valid_bucket = os.environ['VALID_BUCKET_NAME']
    quarantine_bucket = os.environ['QUARANTINE_BUCKET_NAME']
    
    try:
        for record in event['Records']:
            # Extract S3 information from the event
            bucket_name = record['s3']['bucket']['name']
            object_key = urllib.parse.unquote_plus(record['s3']['object']['key'])
            object_size = record['s3']['object']['size']
            
            print(f"Processing file: {object_key}, Size: {object_size} bytes")
            
            # Validate the file
            validation_result = validate_file(object_key, object_size)
            
            # Determine destination bucket based on validation result
            if validation_result['valid']:
                destination_bucket = valid_bucket
                print(f"✅ File {object_key} is valid")
            else:
                destination_bucket = quarantine_bucket
                print(f"❌ File {object_key} is invalid: {validation_result['reason']}")
            
            # Create date-organized path in destination bucket
            destination_key = f"{datetime.now().strftime('%Y/%m/%d')}/{object_key}"
            
            # Copy file to appropriate bucket
            copy_source = {'Bucket': bucket_name, 'Key': object_key}
            s3_client.copy_object(
                CopySource=copy_source,
                Bucket=destination_bucket,
                Key=destination_key
            )
            
            # Delete original file from upload bucket to prevent reprocessing
            s3_client.delete_object(
                Bucket=bucket_name,
                Key=object_key
            )
            
            print(f"Successfully moved {object_key} to {destination_bucket}/{destination_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps('File validation completed successfully')
        }
        
    except Exception as e:
        print(f"Error processing file: {str(e)}")
        raise e

def validate_file(filename, file_size):
    """
    Validates a file based on size and extension.
    
    Args:
        filename (str): Name of the file to validate
        file_size (int): Size of the file in bytes
    
    Returns:
        dict: Validation result with 'valid' boolean and 'reason' string
    """
    # Check file size limit
    if file_size > MAX_FILE_SIZE:
        return {
            'valid': False, 
            'reason': f'File size {file_size} bytes exceeds maximum {MAX_FILE_SIZE} bytes'
        }
    
    # Check if file has an extension
    if '.' not in filename:
        return {
            'valid': False, 
            'reason': 'File has no extension'
        }
    
    # Extract and validate file extension
    file_extension = '.' + filename.lower().split('.')[-1]
    if file_extension not in ALLOWED_EXTENSIONS:
        return {
            'valid': False, 
            'reason': f'File extension {file_extension} not in allowed list: {ALLOWED_EXTENSIONS}'
        }
    
    return {
        'valid': True, 
        'reason': 'File passed all validation checks'
    }
`),
    });

    // Grant Lambda function permissions to read from upload bucket
    uploadBucket.grantRead(fileValidatorFunction);
    uploadBucket.grantDelete(fileValidatorFunction);

    // Grant Lambda function permissions to write to destination buckets
    validFilesBucket.grantWrite(fileValidatorFunction);
    quarantineBucket.grantWrite(fileValidatorFunction);

    // Configure S3 event notification to trigger Lambda function
    // This creates the event-driven architecture for real-time file processing
    uploadBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(fileValidatorFunction)
    );

    // CloudFormation outputs for reference and verification
    new cdk.CfnOutput(this, 'UploadBucketName', {
      value: uploadBucket.bucketName,
      description: 'Name of the S3 bucket for file uploads',
      exportName: `${this.stackName}-UploadBucket`,
    });

    new cdk.CfnOutput(this, 'ValidFilesBucketName', {
      value: validFilesBucket.bucketName,
      description: 'Name of the S3 bucket for validated files',
      exportName: `${this.stackName}-ValidFilesBucket`,
    });

    new cdk.CfnOutput(this, 'QuarantineBucketName', {
      value: quarantineBucket.bucketName,
      description: 'Name of the S3 bucket for quarantined files',
      exportName: `${this.stackName}-QuarantineBucket`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: fileValidatorFunction.functionName,
      description: 'Name of the Lambda function for file validation',
      exportName: `${this.stackName}-LambdaFunction`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: fileValidatorFunction.functionArn,
      description: 'ARN of the Lambda function for file validation',
      exportName: `${this.stackName}-LambdaFunctionArn`,
    });

    // Add tags to all resources for better organization and cost tracking
    cdk.Tags.of(this).add('Project', 'SimpleFileValidation');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }
}

// CDK App
const app = new cdk.App();

// Create the stack with environment-specific configuration
new SimpleFileValidationStack(app, 'SimpleFileValidationStack', {
  description: 'Simple File Validation with S3 and Lambda - CDK TypeScript Implementation',
  
  // Uncomment and modify the following to deploy to specific account/region
  // env: {
  //   account: process.env.CDK_DEFAULT_ACCOUNT,
  //   region: process.env.CDK_DEFAULT_REGION,
  // },
  
  // Stack-level tags
  tags: {
    Project: 'SimpleFileValidation',
    Recipe: 'simple-file-validation-s3-lambda',
    IaC: 'CDK-TypeScript',
  },
});

// Synthesize the CloudFormation template
app.synth();