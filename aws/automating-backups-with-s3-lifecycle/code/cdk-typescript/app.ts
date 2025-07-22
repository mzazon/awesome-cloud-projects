#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Stack for implementing automated S3 backups with EventBridge scheduling
 * 
 * This stack creates:
 * - Primary S3 bucket for working data
 * - Backup S3 bucket with versioning and lifecycle policies
 * - Lambda function to perform backup operations
 * - EventBridge rule to trigger backups on schedule
 * - IAM roles and policies for secure access
 */
export class ScheduledS3BackupsStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // Primary S3 bucket for working data
    const primaryBucket = new s3.Bucket(this, 'PrimaryBucket', {
      bucketName: `primary-data-${uniqueSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: false,
    });

    // Backup S3 bucket with versioning and lifecycle policies
    const backupBucket = new s3.Bucket(this, 'BackupBucket', {
      bucketName: `backup-data-${uniqueSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: true,
      lifecycleRules: [
        {
          id: 'BackupRetentionRule',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.STANDARD_IA,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
          ],
          expiration: cdk.Duration.days(365),
        },
      ],
    });

    // CloudWatch Log Group for Lambda function
    const logGroup = new logs.LogGroup(this, 'BackupFunctionLogGroup', {
      logGroupName: `/aws/lambda/s3-backup-function-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Lambda function for performing backups
    const backupFunction = new lambda.Function(this, 'BackupFunction', {
      functionName: `s3-backup-function-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import boto3
import os
import time
import json
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to backup objects from primary S3 bucket to backup bucket
    """
    try:
        # Get bucket names from environment variables
        source_bucket = os.environ['SOURCE_BUCKET']
        destination_bucket = os.environ['DESTINATION_BUCKET']
        
        # Initialize S3 client
        s3 = boto3.client('s3')
        
        # Get current timestamp for logging
        timestamp = time.strftime("%Y-%m-%d-%H-%M-%S")
        logger.info(f"Starting backup process at {timestamp}")
        
        # List objects in source bucket
        objects = []
        try:
            paginator = s3.get_paginator('list_objects_v2')
            for page in paginator.paginate(Bucket=source_bucket):
                if 'Contents' in page:
                    objects.extend(page['Contents'])
        except Exception as e:
            logger.error(f"Error listing objects in source bucket: {str(e)}")
            raise e
        
        # If no objects found, log and return
        if not objects:
            logger.info("No objects found in source bucket")
            return {
                'statusCode': 200,
                'body': json.dumps('No objects to backup')
            }
        
        # Copy each object to the destination bucket
        copied_count = 0
        failed_count = 0
        
        for obj in objects:
            key = obj['Key']
            copy_source = {'Bucket': source_bucket, 'Key': key}
            
            try:
                logger.info(f"Copying {key} to backup bucket")
                s3.copy_object(
                    CopySource=copy_source,
                    Bucket=destination_bucket,
                    Key=key
                )
                copied_count += 1
            except Exception as e:
                logger.error(f"Error copying {key}: {str(e)}")
                failed_count += 1
                continue
        
        # Log results
        logger.info(f"Backup completed. Copied {copied_count} objects, failed {failed_count} objects.")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully backed up {copied_count} objects',
                'copied_count': copied_count,
                'failed_count': failed_count,
                'timestamp': timestamp
            })
        }
        
    except Exception as e:
        logger.error(f"Lambda function failed: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Backup process failed'
            })
        }
      `),
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      environment: {
        SOURCE_BUCKET: primaryBucket.bucketName,
        DESTINATION_BUCKET: backupBucket.bucketName,
      },
      logGroup: logGroup,
    });

    // Grant Lambda function permissions to read from primary bucket
    primaryBucket.grantRead(backupFunction);
    
    // Grant Lambda function permissions to write to backup bucket
    backupBucket.grantWrite(backupFunction);

    // EventBridge rule to trigger backups daily at 1:00 AM UTC
    const backupRule = new events.Rule(this, 'BackupRule', {
      ruleName: `DailyS3BackupRule-${uniqueSuffix}`,
      description: 'Trigger S3 backup function daily at 1:00 AM UTC',
      schedule: events.Schedule.cron({
        minute: '0',
        hour: '1',
        day: '*',
        month: '*',
        year: '*'
      }),
    });

    // Add Lambda function as target for the EventBridge rule
    backupRule.addTarget(new targets.LambdaFunction(backupFunction));

    // CloudFormation Outputs
    new cdk.CfnOutput(this, 'PrimaryBucketName', {
      value: primaryBucket.bucketName,
      description: 'Name of the primary S3 bucket',
      exportName: `${this.stackName}-PrimaryBucketName`,
    });

    new cdk.CfnOutput(this, 'BackupBucketName', {
      value: backupBucket.bucketName,
      description: 'Name of the backup S3 bucket',
      exportName: `${this.stackName}-BackupBucketName`,
    });

    new cdk.CfnOutput(this, 'BackupFunctionName', {
      value: backupFunction.functionName,
      description: 'Name of the backup Lambda function',
      exportName: `${this.stackName}-BackupFunctionName`,
    });

    new cdk.CfnOutput(this, 'BackupRuleName', {
      value: backupRule.ruleName,
      description: 'Name of the EventBridge backup rule',
      exportName: `${this.stackName}-BackupRuleName`,
    });

    new cdk.CfnOutput(this, 'BackupSchedule', {
      value: 'Daily at 1:00 AM UTC',
      description: 'Backup schedule',
      exportName: `${this.stackName}-BackupSchedule`,
    });

    // Tags for all resources
    cdk.Tags.of(this).add('Purpose', 'S3 Automated Backups');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('Owner', 'Infrastructure Team');
    cdk.Tags.of(this).add('Recipe', 'scheduled-backups-with-amazon-s3');
  }
}

// CDK App
const app = new cdk.App();

// Create the stack
new ScheduledS3BackupsStack(app, 'ScheduledS3BackupsStack', {
  description: 'Automated S3 backups with EventBridge scheduling - CDK TypeScript implementation',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

// Synthesize the stack
app.synth();