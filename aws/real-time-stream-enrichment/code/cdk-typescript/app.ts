#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as kinesis from 'aws-cdk-lib/aws-kinesis';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as kinesisfirehose from 'aws-cdk-lib/aws-kinesisfirehose';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as pipes from 'aws-cdk-lib/aws-pipes';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Properties for the StreamEnrichmentStack
 */
export interface StreamEnrichmentStackProps extends cdk.StackProps {
  /**
   * Optional prefix for resource names
   * @default 'stream-enrichment'
   */
  readonly resourcePrefix?: string;
  
  /**
   * Environment name for resource tagging
   * @default 'development'
   */
  readonly environment?: string;

  /**
   * Enable/disable data format conversion in Firehose
   * @default false
   */
  readonly enableDataFormatConversion?: boolean;
}

/**
 * CDK Stack for Real-Time Stream Enrichment with Kinesis Data Firehose and EventBridge Pipes
 * 
 * This stack creates a serverless real-time data enrichment pipeline that:
 * 1. Ingests streaming data through Kinesis Data Streams
 * 2. Enriches events using Lambda functions with DynamoDB lookups
 * 3. Delivers enriched data to S3 via Kinesis Data Firehose
 * 4. Orchestrates the flow using EventBridge Pipes
 */
export class StreamEnrichmentStack extends cdk.Stack {
  public readonly dataStream: kinesis.Stream;
  public readonly enrichmentFunction: lambda.Function;
  public readonly referenceDataTable: dynamodb.Table;
  public readonly dataBucket: s3.Bucket;
  public readonly deliveryStream: kinesisfirehose.CfnDeliveryStream;
  public readonly enrichmentPipe: pipes.CfnPipe;

  constructor(scope: Construct, id: string, props: StreamEnrichmentStackProps = {}) {
    super(scope, id, props);

    const resourcePrefix = props.resourcePrefix ?? 'stream-enrichment';
    const environment = props.environment ?? 'development';

    // Apply common tags to all resources
    cdk.Tags.of(this).add('Environment', environment);
    cdk.Tags.of(this).add('Project', 'StreamEnrichment');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');

    // S3 Bucket for storing enriched data
    this.dataBucket = new s3.Bucket(this, 'DataBucket', {
      bucketName: `${resourcePrefix}-data-${cdk.Aws.ACCOUNT_ID}-${cdk.Aws.REGION}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: false,
      lifecycleRules: [
        {
          id: 'ArchiveOldData',
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
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Use RETAIN for production
      autoDeleteObjects: true, // Use false for production
    });

    // DynamoDB table for reference data used in enrichment
    this.referenceDataTable = new dynamodb.Table(this, 'ReferenceDataTable', {
      tableName: `${resourcePrefix}-reference-data`,
      partitionKey: {
        name: 'productId',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Use RETAIN for production
    });

    // Add sample reference data
    this.addSampleReferenceData();

    // Kinesis Data Stream for raw event ingestion
    this.dataStream = new kinesis.Stream(this, 'DataStream', {
      streamName: `${resourcePrefix}-raw-events`,
      streamModeDetails: {
        streamMode: kinesis.StreamMode.ON_DEMAND,
      },
      encryption: kinesis.StreamEncryption.MANAGED,
      retentionPeriod: cdk.Duration.hours(24), // Minimum retention period
    });

    // Lambda function for event enrichment
    this.enrichmentFunction = this.createEnrichmentFunction(resourcePrefix);

    // IAM role for Kinesis Data Firehose
    const firehoseRole = this.createFirehoseRole();

    // Kinesis Data Firehose delivery stream
    this.deliveryStream = this.createFirehoseDeliveryStream(
      resourcePrefix,
      firehoseRole,
      props.enableDataFormatConversion
    );

    // IAM role for EventBridge Pipes
    const pipesRole = this.createPipesRole();

    // EventBridge Pipe for orchestrating the enrichment pipeline
    this.enrichmentPipe = this.createEventBridgePipe(resourcePrefix, pipesRole);

    // Output important resource identifiers
    this.createOutputs();
  }

  /**
   * Creates the Lambda function for event enrichment
   */
  private createEnrichmentFunction(resourcePrefix: string): lambda.Function {
    // CloudWatch Log Group for Lambda function
    const logGroup = new logs.LogGroup(this, 'EnrichmentFunctionLogGroup', {
      logGroupName: `/aws/lambda/${resourcePrefix}-enrich-events`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    const enrichmentFunction = new lambda.Function(this, 'EnrichmentFunction', {
      functionName: `${resourcePrefix}-enrich-events`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'lambda_function.lambda_handler',
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      logGroup: logGroup,
      environment: {
        TABLE_NAME: this.referenceDataTable.tableName,
        LOG_LEVEL: 'INFO',
      },
      code: lambda.Code.fromInline(`
import json
import base64
import boto3
import os
import logging
from datetime import datetime
from typing import List, Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize DynamoDB resource
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event: List[Dict[str, Any]], context) -> List[Dict[str, Any]]:
    """
    Lambda function to enrich streaming events with reference data from DynamoDB.
    
    Args:
        event: List of records from EventBridge Pipes
        context: Lambda context object
        
    Returns:
        List of enriched event records
    """
    logger.info(f"Processing {len(event)} records")
    enriched_records = []
    
    for record in event:
        try:
            # Decode Kinesis data
            payload = json.loads(
                base64.b64decode(record['data']).decode('utf-8')
            )
            logger.debug(f"Processing record: {payload}")
            
            # Lookup product details from reference data
            product_id = payload.get('productId')
            if product_id:
                try:
                    response = table.get_item(
                        Key={'productId': product_id}
                    )
                    
                    if 'Item' in response:
                        # Enrich the payload with reference data
                        item = response['Item']
                        payload['productName'] = item['productName']
                        payload['category'] = item['category']
                        payload['price'] = float(item['price'])
                        payload['enrichmentTimestamp'] = datetime.utcnow().isoformat()
                        payload['enrichmentStatus'] = 'success'
                        logger.debug(f"Successfully enriched record for product {product_id}")
                    else:
                        payload['enrichmentStatus'] = 'product_not_found'
                        payload['enrichmentTimestamp'] = datetime.utcnow().isoformat()
                        logger.warning(f"Product {product_id} not found in reference data")
                        
                except Exception as e:
                    payload['enrichmentStatus'] = 'error'
                    payload['enrichmentError'] = str(e)
                    payload['enrichmentTimestamp'] = datetime.utcnow().isoformat()
                    logger.error(f"Error looking up product {product_id}: {str(e)}")
            else:
                payload['enrichmentStatus'] = 'no_product_id'
                payload['enrichmentTimestamp'] = datetime.utcnow().isoformat()
                logger.warning("Record missing productId field")
            
            enriched_records.append(payload)
            
        except Exception as e:
            logger.error(f"Error processing record: {str(e)}")
            # Include the original record with error information
            error_record = {
                'originalData': record.get('data', ''),
                'enrichmentStatus': 'processing_error',
                'enrichmentError': str(e),
                'enrichmentTimestamp': datetime.utcnow().isoformat()
            }
            enriched_records.append(error_record)
    
    logger.info(f"Successfully processed {len(enriched_records)} records")
    return enriched_records
`),
    });

    // Grant the Lambda function read access to the DynamoDB table
    this.referenceDataTable.grantReadData(enrichmentFunction);

    return enrichmentFunction;
  }

  /**
   * Creates IAM role for Kinesis Data Firehose
   */
  private createFirehoseRole(): iam.Role {
    const firehoseRole = new iam.Role(this, 'FirehoseRole', {
      roleName: `${this.stackName}-firehose-delivery-role`,
      assumedBy: new iam.ServicePrincipal('firehose.amazonaws.com'),
      description: 'IAM role for Kinesis Data Firehose delivery stream',
    });

    // Grant S3 permissions for data delivery
    firehoseRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          's3:AbortMultipartUpload',
          's3:GetBucketLocation',
          's3:GetObject',
          's3:ListBucket',
          's3:ListBucketMultipartUploads',
          's3:PutObject',
        ],
        resources: [
          this.dataBucket.bucketArn,
          `${this.dataBucket.bucketArn}/*`,
        ],
      })
    );

    // Grant CloudWatch Logs permissions
    firehoseRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'logs:CreateLogGroup',
          'logs:CreateLogStream',
          'logs:PutLogEvents',
        ],
        resources: [
          `arn:aws:logs:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:log-group:/aws/kinesisfirehose/*`,
        ],
      })
    );

    return firehoseRole;
  }

  /**
   * Creates Kinesis Data Firehose delivery stream
   */
  private createFirehoseDeliveryStream(
    resourcePrefix: string,
    firehoseRole: iam.Role,
    enableDataFormatConversion?: boolean
  ): kinesisfirehose.CfnDeliveryStream {
    const deliveryStream = new kinesisfirehose.CfnDeliveryStream(this, 'DeliveryStream', {
      deliveryStreamName: `${resourcePrefix}-event-ingestion`,
      deliveryStreamType: 'DirectPut',
      extendedS3DestinationConfiguration: {
        roleArn: firehoseRole.roleArn,
        bucketArn: this.dataBucket.bucketArn,
        prefix: 'enriched-data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/',
        errorOutputPrefix: 'error-data/',
        compressionFormat: 'GZIP',
        bufferingHints: {
          sizeInMBs: 5,
          intervalInSeconds: 300,
        },
        cloudWatchLoggingOptions: {
          enabled: true,
          logGroupName: `/aws/kinesisfirehose/${resourcePrefix}-event-ingestion`,
        },
        dataFormatConversionConfiguration: enableDataFormatConversion ? {
          enabled: true,
          outputFormatConfiguration: {
            serializer: {
              parquetSerDe: {},
            },
          },
          schemaConfiguration: {
            region: cdk.Aws.REGION,
            roleArn: firehoseRole.roleArn,
            databaseName: 'default',
            tableName: 'enriched_events',
          },
        } : {
          enabled: false,
        },
      },
    });

    // Ensure the delivery stream depends on the IAM role
    deliveryStream.addDependency(firehoseRole.node.defaultChild as iam.CfnRole);

    return deliveryStream;
  }

  /**
   * Creates IAM role for EventBridge Pipes
   */
  private createPipesRole(): iam.Role {
    const pipesRole = new iam.Role(this, 'PipesRole', {
      roleName: `${this.stackName}-pipes-execution-role`,
      assumedBy: new iam.ServicePrincipal('pipes.amazonaws.com'),
      description: 'IAM role for EventBridge Pipes execution',
    });

    // Grant Kinesis Data Streams permissions
    pipesRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'kinesis:DescribeStream',
          'kinesis:GetRecords',
          'kinesis:GetShardIterator',
          'kinesis:ListStreams',
          'kinesis:SubscribeToShard',
        ],
        resources: [this.dataStream.streamArn],
      })
    );

    // Grant Lambda invocation permissions
    pipesRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['lambda:InvokeFunction'],
        resources: [this.enrichmentFunction.functionArn],
      })
    );

    // Grant Kinesis Data Firehose permissions
    pipesRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'firehose:PutRecord',
          'firehose:PutRecordBatch',
        ],
        resources: [this.deliveryStream.attrArn],
      })
    );

    return pipesRole;
  }

  /**
   * Creates EventBridge Pipe for orchestrating the enrichment pipeline
   */
  private createEventBridgePipe(resourcePrefix: string, pipesRole: iam.Role): pipes.CfnPipe {
    const enrichmentPipe = new pipes.CfnPipe(this, 'EnrichmentPipe', {
      name: `${resourcePrefix}-enrichment-pipe`,
      roleArn: pipesRole.roleArn,
      source: this.dataStream.streamArn,
      sourceParameters: {
        kinesisStreamParameters: {
          startingPosition: 'LATEST',
          batchSize: 10,
          maximumBatchingWindowInSeconds: 5,
          deadLetterConfig: {
            arn: this.createDeadLetterQueue().queueArn,
          },
        },
      },
      enrichment: this.enrichmentFunction.functionArn,
      target: this.deliveryStream.attrArn,
      targetParameters: {
        kinesisFirehoseParameters: {
          deliveryStreamName: this.deliveryStream.deliveryStreamName!,
        },
      },
      description: 'EventBridge Pipe for real-time stream enrichment',
    });

    // Ensure the pipe depends on the IAM role and other resources
    enrichmentPipe.addDependency(pipesRole.node.defaultChild as iam.CfnRole);
    enrichmentPipe.addDependency(this.deliveryStream);

    return enrichmentPipe;
  }

  /**
   * Creates a dead letter queue for failed pipe processing
   */
  private createDeadLetterQueue() {
    // For this example, we'll use a simple SQS queue
    // In production, consider using DLQ with proper monitoring
    const { Queue } = require('aws-cdk-lib/aws-sqs');
    
    return new Queue(this, 'DeadLetterQueue', {
      queueName: `${this.stackName}-pipe-dlq`,
      retentionPeriod: cdk.Duration.days(14),
    });
  }

  /**
   * Adds sample reference data to DynamoDB table
   */
  private addSampleReferenceData(): void {
    // Use AWS SDK custom resource to populate sample data
    const customResource = new cdk.CustomResource(this, 'SampleDataPopulator', {
      serviceToken: this.createSampleDataFunction().functionArn,
      properties: {
        TableName: this.referenceDataTable.tableName,
      },
    });

    customResource.node.addDependency(this.referenceDataTable);
  }

  /**
   * Creates Lambda function to populate sample reference data
   */
  private createSampleDataFunction(): lambda.Function {
    const sampleDataFunction = new lambda.Function(this, 'SampleDataFunction', {
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.handler',
      timeout: cdk.Duration.seconds(60),
      code: lambda.Code.fromInline(`
import boto3
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    try:
        if event['RequestType'] == 'Create':
            dynamodb = boto3.resource('dynamodb')
            table_name = event['ResourceProperties']['TableName']
            table = dynamodb.Table(table_name)
            
            # Sample reference data
            sample_data = [
                {
                    'productId': 'PROD-001',
                    'productName': 'Smart Sensor',
                    'category': 'IoT Devices',
                    'price': '49.99'
                },
                {
                    'productId': 'PROD-002',
                    'productName': 'Temperature Monitor',
                    'category': 'IoT Devices',
                    'price': '79.99'
                },
                {
                    'productId': 'PROD-003',
                    'productName': 'Motion Detector',
                    'category': 'Security',
                    'price': '129.99'
                }
            ]
            
            # Insert sample data
            for item in sample_data:
                table.put_item(Item=item)
                logger.info(f"Inserted item: {item['productId']}")
            
        return {'PhysicalResourceId': 'sample-data-populator'}
    except Exception as e:
        logger.error(f"Error: {str(e)}")
        raise e
`),
    });

    // Grant the function write access to the DynamoDB table
    this.referenceDataTable.grantWriteData(sampleDataFunction);

    return sampleDataFunction;
  }

  /**
   * Creates CloudFormation outputs for important resources
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'DataStreamName', {
      value: this.dataStream.streamName,
      description: 'Name of the Kinesis Data Stream for raw events',
      exportName: `${this.stackName}-DataStreamName`,
    });

    new cdk.CfnOutput(this, 'DataStreamArn', {
      value: this.dataStream.streamArn,
      description: 'ARN of the Kinesis Data Stream',
      exportName: `${this.stackName}-DataStreamArn`,
    });

    new cdk.CfnOutput(this, 'EnrichmentFunctionName', {
      value: this.enrichmentFunction.functionName,
      description: 'Name of the Lambda enrichment function',
      exportName: `${this.stackName}-EnrichmentFunctionName`,
    });

    new cdk.CfnOutput(this, 'ReferenceDataTableName', {
      value: this.referenceDataTable.tableName,
      description: 'Name of the DynamoDB reference data table',
      exportName: `${this.stackName}-ReferenceDataTableName`,
    });

    new cdk.CfnOutput(this, 'DataBucketName', {
      value: this.dataBucket.bucketName,
      description: 'Name of the S3 bucket for enriched data',
      exportName: `${this.stackName}-DataBucketName`,
    });

    new cdk.CfnOutput(this, 'DeliveryStreamName', {
      value: this.deliveryStream.deliveryStreamName!,
      description: 'Name of the Kinesis Data Firehose delivery stream',
      exportName: `${this.stackName}-DeliveryStreamName`,
    });

    new cdk.CfnOutput(this, 'EnrichmentPipeName', {
      value: this.enrichmentPipe.name!,
      description: 'Name of the EventBridge enrichment pipe',
      exportName: `${this.stackName}-EnrichmentPipeName`,
    });
  }
}

// CDK App
const app = new cdk.App();

// Get environment configuration from context or environment variables
const environment = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'development';
const resourcePrefix = app.node.tryGetContext('resourcePrefix') || process.env.RESOURCE_PREFIX || 'stream-enrichment';
const enableDataFormatConversion = app.node.tryGetContext('enableDataFormatConversion') === 'true';

// Create the stack
new StreamEnrichmentStack(app, 'StreamEnrichmentStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  resourcePrefix: resourcePrefix,
  environment: environment,
  enableDataFormatConversion: enableDataFormatConversion,
  description: 'Real-time stream enrichment pipeline with Kinesis Data Firehose and EventBridge Pipes',
  tags: {
    Environment: environment,
    Project: 'StreamEnrichment',
    Owner: 'DataEngineering',
    CostCenter: 'Analytics',
  },
});

app.synth();