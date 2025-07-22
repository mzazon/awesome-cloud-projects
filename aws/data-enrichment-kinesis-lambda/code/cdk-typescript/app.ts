#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as kinesis from 'aws-cdk-lib/aws-kinesis';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambdaEventSources from 'aws-cdk-lib/aws-lambda-event-sources';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * CDK Stack for streaming data enrichment pipeline with Kinesis and Lambda
 * 
 * This stack implements a real-time data enrichment solution that:
 * - Ingests streaming data via Kinesis Data Streams
 * - Enriches data using Lambda functions with DynamoDB lookups
 * - Stores enriched data in S3 with time-based partitioning
 * - Provides comprehensive monitoring and alerting
 */
export class DataEnrichmentKinesisLambdaStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = this.node.addr.slice(-6).toLowerCase();

    // =========================
    // DynamoDB Lookup Table
    // =========================
    
    /**
     * DynamoDB table for user profile lookups
     * Provides fast, low-latency access to user context data for enrichment
     */
    const lookupTable = new dynamodb.Table(this, 'EnrichmentLookupTable', {
      tableName: `enrichment-lookup-table-${uniqueSuffix}`,
      partitionKey: {
        name: 'user_id',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      pointInTimeRecovery: true,
      tags: {
        Purpose: 'DataEnrichment',
        Environment: 'Development',
      },
    });

    // Add sample data to the lookup table
    this.addSampleDataToTable(lookupTable);

    // =========================
    // S3 Bucket for Enriched Data
    // =========================
    
    /**
     * S3 bucket for storing enriched streaming data
     * Configured with versioning and lifecycle policies for cost optimization
     */
    const enrichedDataBucket = new s3.Bucket(this, 'EnrichedDataBucket', {
      bucketName: `enriched-data-bucket-${uniqueSuffix}`,
      versioned: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      autoDeleteObjects: true, // For demo purposes
      lifecycleRules: [
        {
          id: 'transition-to-ia',
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
      tags: {
        Purpose: 'DataEnrichment',
        Environment: 'Development',
      },
    });

    // =========================
    // Kinesis Data Stream
    // =========================
    
    /**
     * Kinesis Data Stream for real-time data ingestion
     * Configured with 2 shards to handle up to 2,000 records/second
     */
    const dataStream = new kinesis.Stream(this, 'DataEnrichmentStream', {
      streamName: `data-enrichment-stream-${uniqueSuffix}`,
      shardCount: 2,
      retentionPeriod: cdk.Duration.hours(24),
      tags: {
        Purpose: 'DataEnrichment',
        Environment: 'Development',
      },
    });

    // Enable enhanced monitoring for better observability
    dataStream.node.addMetadata('enhancedMonitoring', ['IncomingRecords', 'OutgoingRecords', 'IncomingBytes', 'OutgoingBytes']);

    // =========================
    // Lambda Execution Role
    // =========================
    
    /**
     * IAM role for Lambda function with least privilege access
     * Grants permissions for Kinesis, DynamoDB, S3, and CloudWatch
     */
    const lambdaExecutionRole = new iam.Role(this, 'DataEnrichmentLambdaRole', {
      roleName: `data-enrichment-lambda-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        DataEnrichmentPolicy: new iam.PolicyDocument({
          statements: [
            // Kinesis permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'kinesis:DescribeStream',
                'kinesis:DescribeStreamSummary',
                'kinesis:GetRecords',
                'kinesis:GetShardIterator',
                'kinesis:ListShards',
                'kinesis:SubscribeToShard',
              ],
              resources: [dataStream.streamArn],
            }),
            // DynamoDB permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:GetItem',
                'dynamodb:Query',
                'dynamodb:Scan',
              ],
              resources: [lookupTable.tableArn],
            }),
            // S3 permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:PutObject',
                's3:PutObjectAcl',
              ],
              resources: [`${enrichedDataBucket.bucketArn}/*`],
            }),
          ],
        }),
      },
      tags: {
        Purpose: 'DataEnrichment',
        Environment: 'Development',
      },
    });

    // =========================
    // Lambda Function
    // =========================
    
    /**
     * Lambda function for real-time data enrichment
     * Processes Kinesis records, enriches with DynamoDB data, stores in S3
     */
    const enrichmentFunction = new lambda.Function(this, 'DataEnrichmentFunction', {
      functionName: `data-enrichment-function-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      environment: {
        TABLE_NAME: lookupTable.tableName,
        BUCKET_NAME: enrichedDataBucket.bucketName,
        AWS_REGION: this.region,
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
import json
import boto3
import base64
import datetime
import os
from decimal import Decimal

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Main Lambda handler for processing Kinesis records and enriching data
    
    Args:
        event: Kinesis event containing records to process
        context: Lambda runtime context
        
    Returns:
        Processing summary
    """
    
    # Get environment variables
    table_name = os.environ['TABLE_NAME']
    bucket_name = os.environ['BUCKET_NAME']
    
    table = dynamodb.Table(table_name)
    processed_count = 0
    error_count = 0
    
    print(f"Processing {len(event['Records'])} records from Kinesis")
    
    for record in event['Records']:
        try:
            # Decode Kinesis data
            payload = base64.b64decode(record['kinesis']['data'])
            data = json.loads(payload)
            
            print(f"Processing record: {record['kinesis']['sequenceNumber']}")
            
            # Enrich data with user profile
            user_id = data.get('user_id')
            if user_id:
                try:
                    # Lookup user profile in DynamoDB
                    response = table.get_item(Key={'user_id': user_id})
                    if 'Item' in response:
                        # Add user profile data to event
                        user_profile = response['Item']
                        data['user_name'] = user_profile.get('name', 'Unknown')
                        data['user_email'] = user_profile.get('email', 'Unknown')
                        data['user_segment'] = user_profile.get('segment', 'Unknown')
                        data['user_location'] = user_profile.get('location', 'Unknown')
                        print(f"Enriched data for user: {user_id}")
                    else:
                        # User not found in lookup table
                        data['user_name'] = 'Unknown'
                        data['user_segment'] = 'Unknown'
                        data['user_email'] = 'Unknown'
                        data['user_location'] = 'Unknown'
                        print(f"User not found in lookup table: {user_id}")
                except Exception as e:
                    print(f"Error enriching user data for {user_id}: {e}")
                    data['enrichment_error'] = str(e)
            
            # Add processing metadata
            data['processing_timestamp'] = datetime.datetime.utcnow().isoformat()
            data['enriched'] = True
            data['lambda_request_id'] = context.aws_request_id
            
            # Store enriched data in S3 with time-based partitioning
            timestamp = datetime.datetime.utcnow().strftime('%Y/%m/%d/%H')
            key = f"enriched-data/{timestamp}/{record['kinesis']['sequenceNumber']}.json"
            
            try:
                s3.put_object(
                    Bucket=bucket_name,
                    Key=key,
                    Body=json.dumps(data, default=str),
                    ContentType='application/json',
                    Metadata={
                        'source': 'kinesis-lambda-enrichment',
                        'partition_key': record['kinesis']['partitionKey'],
                        'sequence_number': record['kinesis']['sequenceNumber']
                    }
                )
                processed_count += 1
                print(f"Successfully stored enriched data: {key}")
                
            except Exception as e:
                print(f"Error storing enriched data: {e}")
                error_count += 1
                raise
                
        except Exception as e:
            print(f"Error processing record {record['kinesis']['sequenceNumber']}: {e}")
            error_count += 1
            # Continue processing other records
    
    # Return processing summary
    result = {
        'processed_records': processed_count,
        'error_records': error_count,
        'total_records': len(event['Records']),
        'request_id': context.aws_request_id
    }
    
    print(f"Processing complete: {result}")
    return result
      `),
      tags: {
        Purpose: 'DataEnrichment',
        Environment: 'Development',
      },
    });

    // =========================
    // Event Source Mapping
    // =========================
    
    /**
     * Connect Kinesis stream to Lambda function
     * Configured for optimal batch processing and error handling
     */
    const eventSourceMapping = enrichmentFunction.addEventSource(
      new lambdaEventSources.KinesisEventSource(dataStream, {
        batchSize: 10, // Process up to 10 records per invocation
        maxBatchingWindow: cdk.Duration.seconds(5), // Wait up to 5 seconds to fill batch
        startingPosition: lambda.StartingPosition.LATEST,
        retryAttempts: 3, // Retry failed batches 3 times
        maxRecordAge: cdk.Duration.hours(1), // Discard records older than 1 hour
        parallelizationFactor: 1, // Process one batch per shard at a time
        reportBatchItemFailures: true, // Enable partial batch failure handling
      })
    );

    // =========================
    // CloudWatch Monitoring
    // =========================
    
    /**
     * CloudWatch alarms for monitoring pipeline health
     * Alerts on processing errors and stream activity
     */
    
    // Alarm for Lambda function errors
    const lambdaErrorAlarm = new cloudwatch.Alarm(this, 'LambdaErrorAlarm', {
      alarmName: `${enrichmentFunction.functionName}-Errors`,
      alarmDescription: 'Lambda function processing errors',
      metric: enrichmentFunction.metricErrors({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum',
      }),
      threshold: 1,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Alarm for Kinesis incoming records (detects lack of data)
    const kinesisIncomingRecordsAlarm = new cloudwatch.Alarm(this, 'KinesisIncomingRecordsAlarm', {
      alarmName: `${dataStream.streamName}-IncomingRecords`,
      alarmDescription: 'Kinesis stream incoming records monitoring',
      metric: dataStream.metricIncomingRecords({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum',
      }),
      threshold: 0,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.BREACHING,
    });

    // Alarm for Lambda duration (performance monitoring)
    const lambdaDurationAlarm = new cloudwatch.Alarm(this, 'LambdaDurationAlarm', {
      alarmName: `${enrichmentFunction.functionName}-Duration`,
      alarmDescription: 'Lambda function duration monitoring',
      metric: enrichmentFunction.metricDuration({
        period: cdk.Duration.minutes(5),
        statistic: 'Average',
      }),
      threshold: 30000, // 30 seconds
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // =========================
    // CloudFormation Outputs
    // =========================
    
    new cdk.CfnOutput(this, 'KinesisStreamName', {
      value: dataStream.streamName,
      description: 'Name of the Kinesis Data Stream',
      exportName: `${this.stackName}-KinesisStreamName`,
    });

    new cdk.CfnOutput(this, 'KinesisStreamArn', {
      value: dataStream.streamArn,
      description: 'ARN of the Kinesis Data Stream',
      exportName: `${this.stackName}-KinesisStreamArn`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: enrichmentFunction.functionName,
      description: 'Name of the data enrichment Lambda function',
      exportName: `${this.stackName}-LambdaFunctionName`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: enrichmentFunction.functionArn,
      description: 'ARN of the data enrichment Lambda function',
      exportName: `${this.stackName}-LambdaFunctionArn`,
    });

    new cdk.CfnOutput(this, 'DynamoDBTableName', {
      value: lookupTable.tableName,
      description: 'Name of the DynamoDB lookup table',
      exportName: `${this.stackName}-DynamoDBTableName`,
    });

    new cdk.CfnOutput(this, 'S3BucketName', {
      value: enrichedDataBucket.bucketName,
      description: 'Name of the S3 bucket for enriched data',
      exportName: `${this.stackName}-S3BucketName`,
    });

    new cdk.CfnOutput(this, 'TestCommand', {
      value: `aws kinesis put-record --stream-name ${dataStream.streamName} --partition-key "test" --data '{"event_type":"page_view","user_id":"user123","page":"/product/abc123","timestamp":"${new Date().toISOString()}","session_id":"session_xyz"}'`,
      description: 'Sample command to test the pipeline',
    });
  }

  /**
   * Add sample user profile data to the DynamoDB lookup table
   * This simulates the user context data used for enrichment
   */
  private addSampleDataToTable(table: dynamodb.Table): void {
    // Sample user profiles for enrichment testing
    const sampleUsers = [
      {
        user_id: 'user123',
        name: 'John Doe',
        email: 'john@example.com',
        segment: 'premium',
        location: 'New York',
      },
      {
        user_id: 'user456',
        name: 'Jane Smith',
        email: 'jane@example.com',
        segment: 'standard',
        location: 'California',
      },
      {
        user_id: 'user789',
        name: 'Bob Johnson',
        email: 'bob@example.com',
        segment: 'premium',
        location: 'Texas',
      },
    ];

    // Create custom resources to populate the table
    sampleUsers.forEach((user, index) => {
      new cdk.CustomResource(this, `SampleUser${index}`, {
        onUpdate: {
          service: 'DynamoDB',
          action: 'putItem',
          parameters: {
            TableName: table.tableName,
            Item: {
              user_id: { S: user.user_id },
              name: { S: user.name },
              email: { S: user.email },
              segment: { S: user.segment },
              location: { S: user.location },
            },
          },
          physicalResourceId: cdk.PhysicalResourceId.of(`sample-user-${user.user_id}`),
        },
        onDelete: {
          service: 'DynamoDB',
          action: 'deleteItem',
          parameters: {
            TableName: table.tableName,
            Key: {
              user_id: { S: user.user_id },
            },
          },
        },
        policy: cdk.AwsCustomResourcePolicy.fromSdkCalls({
          resources: [table.tableArn],
        }),
      });
    });
  }
}

// =========================
// CDK App
// =========================

const app = new cdk.App();

new DataEnrichmentKinesisLambdaStack(app, 'DataEnrichmentKinesisLambdaStack', {
  description: 'Streaming data enrichment pipeline with Kinesis and Lambda',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'DataEnrichmentPipeline',
    Environment: 'Development',
    CostCenter: 'Engineering',
  },
});

app.synth();