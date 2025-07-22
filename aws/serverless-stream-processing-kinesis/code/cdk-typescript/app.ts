#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as kinesis from 'aws-cdk-lib/aws-kinesis';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as lambdaEventSources from 'aws-cdk-lib/aws-lambda-event-sources';

/**
 * Properties for the RealTimeDataProcessingStack
 */
export interface RealTimeDataProcessingStackProps extends cdk.StackProps {
  /**
   * Name of the Kinesis Data Stream
   * @default 'realtime-data-stream'
   */
  readonly streamName?: string;

  /**
   * Number of shards for the Kinesis stream
   * @default 3
   */
  readonly shardCount?: number;

  /**
   * Lambda function memory size in MB
   * @default 256
   */
  readonly lambdaMemorySize?: number;

  /**
   * Lambda function timeout in seconds
   * @default 60
   */
  readonly lambdaTimeout?: number;

  /**
   * Batch size for Kinesis event source mapping
   * @default 100
   */
  readonly batchSize?: number;

  /**
   * Maximum batching window in seconds
   * @default 5
   */
  readonly maxBatchingWindowInSeconds?: number;

  /**
   * Environment name for resource tagging
   * @default 'dev'
   */
  readonly environment?: string;
}

/**
 * CDK Stack for Real-time Data Processing with Amazon Kinesis and Lambda
 * 
 * This stack creates:
 * - Amazon Kinesis Data Stream with configurable shards
 * - AWS Lambda function for processing stream records
 * - S3 bucket for storing processed data
 * - IAM roles and policies with least privilege access
 * - CloudWatch log groups for monitoring
 * - Event source mapping between Kinesis and Lambda
 */
export class RealTimeDataProcessingStack extends cdk.Stack {
  public readonly kinesisStream: kinesis.Stream;
  public readonly lambdaFunction: lambda.Function;
  public readonly s3Bucket: s3.Bucket;

  constructor(scope: Construct, id: string, props?: RealTimeDataProcessingStackProps) {
    super(scope, id, props);

    // Extract properties with defaults
    const streamName = props?.streamName ?? 'realtime-data-stream';
    const shardCount = props?.shardCount ?? 3;
    const lambdaMemorySize = props?.lambdaMemorySize ?? 256;
    const lambdaTimeout = props?.lambdaTimeout ?? 60;
    const batchSize = props?.batchSize ?? 100;
    const maxBatchingWindowInSeconds = props?.maxBatchingWindowInSeconds ?? 5;
    const environment = props?.environment ?? 'dev';

    // Create S3 bucket for storing processed data
    this.s3Bucket = new s3.Bucket(this, 'ProcessedDataBucket', {
      bucketName: `processed-data-${this.account}-${this.region}-${environment}`,
      // Enable versioning for data protection
      versioned: true,
      // Configure lifecycle policies to optimize costs
      lifecycleRules: [
        {
          id: 'TransitionToIA',
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
      // Enable server-side encryption
      encryption: s3.BucketEncryption.S3_MANAGED,
      // Block public access for security
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      // Auto-delete objects when stack is destroyed (for non-production environments)
      autoDeleteObjects: environment !== 'prod',
      removalPolicy: environment === 'prod' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
    });

    // Create Kinesis Data Stream with multiple shards for parallel processing
    this.kinesisStream = new kinesis.Stream(this, 'DataStream', {
      streamName: streamName,
      shardCount: shardCount,
      // Enable server-side encryption for data at rest
      encryption: kinesis.StreamEncryption.KMS,
      // Retain data for 24 hours (default) - can be extended up to 365 days
      retentionPeriod: cdk.Duration.hours(24),
    });

    // Create CloudWatch log group for Lambda function
    const logGroup = new logs.LogGroup(this, 'LambdaLogGroup', {
      logGroupName: `/aws/lambda/kinesis-data-processor-${environment}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create IAM role for Lambda function with least privilege access
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `kinesis-lambda-execution-role-${environment}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for Kinesis data processing Lambda function',
      managedPolicies: [
        // Basic Lambda execution permissions
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        // Kinesis stream reading permissions
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaKinesisExecutionRole'),
      ],
    });

    // Add S3 write permissions to Lambda role
    lambdaRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        's3:PutObject',
        's3:PutObjectAcl',
        's3:GetObject',
      ],
      resources: [
        this.s3Bucket.bucketArn,
        `${this.s3Bucket.bucketArn}/*`,
      ],
    }));

    // Create Lambda function for processing Kinesis records
    this.lambdaFunction = new lambda.Function(this, 'DataProcessor', {
      functionName: `kinesis-data-processor-${environment}`,
      description: 'Processes streaming data from Kinesis and stores results in S3',
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'lambda_function.lambda_handler',
      role: lambdaRole,
      memorySize: lambdaMemorySize,
      timeout: cdk.Duration.seconds(lambdaTimeout),
      logGroup: logGroup,
      environment: {
        S3_BUCKET_NAME: this.s3Bucket.bucketName,
        ENVIRONMENT: environment,
      },
      // Lambda function code - in production, this would be packaged separately
      code: lambda.Code.fromInline(`
import json
import base64
import boto3
import os
from datetime import datetime
from typing import Dict, Any, List

s3_client = boto3.client('s3')
BUCKET_NAME = os.environ['S3_BUCKET_NAME']

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process Kinesis records and store processed data in S3
    """
    processed_records = []
    
    for record in event['Records']:
        try:
            # Decode the Kinesis record data
            kinesis_data = record['kinesis']
            encoded_data = kinesis_data['data']
            decoded_data = base64.b64decode(encoded_data).decode('utf-8')
            
            # Parse the JSON data
            try:
                json_data = json.loads(decoded_data)
            except json.JSONDecodeError:
                # If not JSON, treat as plain text
                json_data = {"message": decoded_data}
                
            # Add processing metadata
            processed_record = {
                "original_data": json_data,
                "processing_timestamp": datetime.utcnow().isoformat(),
                "partition_key": kinesis_data['partitionKey'],
                "sequence_number": kinesis_data['sequenceNumber'],
                "event_id": record['eventID'],
                "processed": True
            }
            
            processed_records.append(processed_record)
            
            print(f"Processed record with EventID: {record['eventID']}")
            
        except Exception as e:
            print(f"Error processing record {record.get('eventID', 'unknown')}: {str(e)}")
            continue
    
    # Store processed records in S3
    if processed_records:
        try:
            s3_key = f"processed-data/{datetime.utcnow().strftime('%Y/%m/%d/%H')}/batch-{context.aws_request_id}.json"
            
            s3_client.put_object(
                Bucket=BUCKET_NAME,
                Key=s3_key,
                Body=json.dumps(processed_records, indent=2),
                ContentType='application/json'
            )
            
            print(f"Successfully stored {len(processed_records)} processed records to S3: {s3_key}")
            
        except Exception as e:
            print(f"Error storing data to S3: {str(e)}")
            raise
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'processed_count': len(processed_records),
            'message': 'Successfully processed Kinesis records'
        })
    }
      `),
      // Enable X-Ray tracing for observability
      tracing: lambda.Tracing.ACTIVE,
    });

    // Create event source mapping between Kinesis stream and Lambda function
    const eventSourceMapping = new lambdaEventSources.KinesisEventSource(this.kinesisStream, {
      batchSize: batchSize,
      maxBatchingWindow: cdk.Duration.seconds(maxBatchingWindowInSeconds),
      startingPosition: lambda.StartingPosition.LATEST,
      // Enable parallel processing per shard
      parallelizationFactor: 1,
      // Configure retry behavior
      retryAttempts: 3,
      // Enable bisect on function error for better error handling
      bisectBatchOnError: true,
      // Report batch item failures
      reportBatchItemFailures: true,
    });

    this.lambdaFunction.addEventSource(eventSourceMapping);

    // Add tags to all resources for better organization and cost tracking
    const tags = {
      'Project': 'RealTimeDataProcessing',
      'Environment': environment,
      'Owner': 'DataEngineering',
      'CostCenter': 'Analytics',
    };

    Object.entries(tags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });

    // CloudFormation outputs for easy reference
    new cdk.CfnOutput(this, 'KinesisStreamName', {
      value: this.kinesisStream.streamName,
      description: 'Name of the Kinesis Data Stream',
      exportName: `${this.stackName}-KinesisStreamName`,
    });

    new cdk.CfnOutput(this, 'KinesisStreamArn', {
      value: this.kinesisStream.streamArn,
      description: 'ARN of the Kinesis Data Stream',
      exportName: `${this.stackName}-KinesisStreamArn`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: this.lambdaFunction.functionName,
      description: 'Name of the Lambda processing function',
      exportName: `${this.stackName}-LambdaFunctionName`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: this.lambdaFunction.functionArn,
      description: 'ARN of the Lambda processing function',
      exportName: `${this.stackName}-LambdaFunctionArn`,
    });

    new cdk.CfnOutput(this, 'S3BucketName', {
      value: this.s3Bucket.bucketName,
      description: 'Name of the S3 bucket for processed data',
      exportName: `${this.stackName}-S3BucketName`,
    });

    new cdk.CfnOutput(this, 'S3BucketArn', {
      value: this.s3Bucket.bucketArn,
      description: 'ARN of the S3 bucket for processed data',
      exportName: `${this.stackName}-S3BucketArn`,
    });
  }
}

// CDK App
const app = new cdk.App();

// Get environment from context or default to 'dev'
const environment = app.node.tryGetContext('environment') ?? 'dev';

// Create the stack with customizable properties
new RealTimeDataProcessingStack(app, 'RealTimeDataProcessingStack', {
  description: 'Real-time data processing pipeline with Amazon Kinesis and Lambda',
  environment: environment,
  // Default stack properties - can be overridden via context
  streamName: app.node.tryGetContext('streamName'),
  shardCount: app.node.tryGetContext('shardCount'),
  lambdaMemorySize: app.node.tryGetContext('lambdaMemorySize'),
  lambdaTimeout: app.node.tryGetContext('lambdaTimeout'),
  batchSize: app.node.tryGetContext('batchSize'),
  maxBatchingWindowInSeconds: app.node.tryGetContext('maxBatchingWindowInSeconds'),
  env: {
    // Use account and region from environment variables or AWS profile
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  // Enable termination protection for production environments
  terminationProtection: environment === 'prod',
});

// Synthesize the app
app.synth();