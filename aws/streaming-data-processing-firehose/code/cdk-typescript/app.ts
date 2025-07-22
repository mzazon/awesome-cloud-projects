#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as opensearch from 'aws-cdk-lib/aws-opensearch';
import * as kinesisfirehose from 'aws-cdk-lib/aws-kinesisfirehose';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import { PythonFunction } from '@aws-cdk/aws-lambda-python-alpha';

/**
 * Stack for Real-Time Data Processing with Kinesis Data Firehose
 * 
 * This stack creates a complete real-time data processing pipeline including:
 * - S3 bucket for data lake storage
 * - Lambda functions for data transformation and error handling
 * - OpenSearch domain for real-time search and analytics
 * - Kinesis Data Firehose delivery streams for S3 and OpenSearch
 * - CloudWatch monitoring and alarms
 * - SQS dead letter queue for error handling
 */
export class RealTimeDataProcessingStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate random suffix for unique resource names
    const randomSuffix = Math.random().toString(36).substring(2, 8);

    // ============================================================================
    // S3 BUCKET FOR DATA LAKE STORAGE
    // ============================================================================
    
    const dataBucket = new s3.Bucket(this, 'DataBucket', {
      bucketName: `firehose-data-bucket-${randomSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
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
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Note: Directory structure will be created automatically by Firehose
    // when data is first delivered to the bucket with the specified prefixes

    // ============================================================================
    // LAMBDA FUNCTIONS FOR DATA TRANSFORMATION AND ERROR HANDLING
    // ============================================================================

    // Data transformation Lambda function
    const transformFunction = new PythonFunction(this, 'TransformFunction', {
      functionName: `firehose-transform-${randomSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'lambda_handler',
      code: lambda.Code.fromInline(`
import json
import base64
import boto3
from datetime import datetime

def lambda_handler(event, context):
    output = []
    
    for record in event['records']:
        # Decode the data
        compressed_payload = base64.b64decode(record['data'])
        uncompressed_payload = compressed_payload.decode('utf-8')
        
        try:
            # Parse JSON data
            data = json.loads(uncompressed_payload)
            
            # Add timestamp and processing metadata
            data['processed_timestamp'] = datetime.utcnow().isoformat()
            data['processing_status'] = 'SUCCESS'
            
            # Enrich data with additional fields
            if 'user_id' in data:
                data['user_category'] = 'registered' if data['user_id'] else 'guest'
            
            if 'amount' in data:
                data['amount_category'] = 'high' if float(data['amount']) > 100 else 'low'
            
            # Convert back to JSON
            transformed_data = json.dumps(data) + '\\n'
            
            output_record = {
                'recordId': record['recordId'],
                'result': 'Ok',
                'data': base64.b64encode(transformed_data.encode('utf-8')).decode('utf-8')
            }
            
        except Exception as e:
            # Handle transformation errors
            error_data = {
                'recordId': record['recordId'],
                'error': str(e),
                'original_data': uncompressed_payload,
                'timestamp': datetime.utcnow().isoformat()
            }
            
            output_record = {
                'recordId': record['recordId'],
                'result': 'ProcessingFailed',
                'data': base64.b64encode(json.dumps(error_data).encode('utf-8')).decode('utf-8')
            }
        
        output.append(output_record)
    
    return {'records': output}
      `),
      timeout: cdk.Duration.seconds(300),
      memorySize: 128,
      description: 'Lambda function for transforming Kinesis Data Firehose records',
    });

    // SQS Dead Letter Queue for error handling
    const deadLetterQueue = new sqs.Queue(this, 'DeadLetterQueue', {
      queueName: `realtime-data-stream-${randomSuffix}-dlq`,
      visibilityTimeout: cdk.Duration.seconds(300),
      messageRetentionPeriod: cdk.Duration.days(14),
      encryption: sqs.QueueEncryption.SQS_MANAGED,
    });

    // Error handling Lambda function
    const errorHandlerFunction = new PythonFunction(this, 'ErrorHandlerFunction', {
      functionName: `firehose-transform-${randomSuffix}-error-handler`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import os

def lambda_handler(event, context):
    sqs = boto3.client('sqs')
    
    for record in event['Records']:
        if record['eventName'] == 'ERROR':
            # Send failed record to DLQ
            sqs.send_message(
                QueueUrl=os.environ['DLQ_URL'],
                MessageBody=json.dumps(record)
            )
    
    return {'statusCode': 200}
      `),
      timeout: cdk.Duration.seconds(300),
      memorySize: 128,
      environment: {
        'DLQ_URL': deadLetterQueue.queueUrl,
      },
      description: 'Lambda function for handling Kinesis Data Firehose errors',
    });

    // Grant SQS permissions to error handler
    deadLetterQueue.grantSendMessages(errorHandlerFunction);

    // ============================================================================
    // OPENSEARCH DOMAIN FOR REAL-TIME SEARCH AND ANALYTICS
    // ============================================================================

    const openSearchDomain = new opensearch.Domain(this, 'OpenSearchDomain', {
      domainName: `firehose-search-${randomSuffix}`,
      version: opensearch.EngineVersion.OPENSEARCH_1_3,
      capacity: {
        dataNodes: 1,
        dataNodeInstanceType: 't3.small.search',
      },
      ebs: {
        volumeSize: 20,
        volumeType: ec2.EbsDeviceVolumeType.GP2,
      },
      nodeToNodeEncryption: true,
      encryptionAtRest: {
        enabled: true,
      },
      enforceHttps: true,
      logging: {
        slowSearchLogEnabled: true,
        appLogEnabled: true,
        slowIndexLogEnabled: true,
      },
      accessPolicies: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          principals: [new iam.AccountRootPrincipal()],
          actions: ['es:*'],
          resources: ['*'],
        }),
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // ============================================================================
    // IAM ROLE FOR KINESIS DATA FIREHOSE
    // ============================================================================

    const firehoseRole = new iam.Role(this, 'FirehoseRole', {
      roleName: `FirehoseDeliveryRole-${randomSuffix}`,
      assumedBy: new iam.ServicePrincipal('firehose.amazonaws.com'),
      inlinePolicies: {
        FirehoseDeliveryPolicy: new iam.PolicyDocument({
          statements: [
            // S3 permissions
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
                dataBucket.bucketArn,
                `${dataBucket.bucketArn}/*`,
              ],
            }),
            // Lambda permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'lambda:InvokeFunction',
                'lambda:GetFunctionConfiguration',
              ],
              resources: [
                transformFunction.functionArn,
              ],
            }),
            // OpenSearch permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'es:DescribeElasticsearchDomain',
                'es:DescribeElasticsearchDomains',
                'es:DescribeElasticsearchDomainConfig',
                'es:ESHttpPost',
                'es:ESHttpPut',
              ],
              resources: [
                openSearchDomain.domainArn,
                `${openSearchDomain.domainArn}/*`,
              ],
            }),
            // CloudWatch Logs permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // ============================================================================
    // KINESIS DATA FIREHOSE DELIVERY STREAMS
    // ============================================================================

    // CloudWatch Log Groups for Firehose
    const s3LogGroup = new logs.LogGroup(this, 'S3FirehoseLogGroup', {
      logGroupName: `/aws/kinesisfirehose/realtime-data-stream-${randomSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    const openSearchLogGroup = new logs.LogGroup(this, 'OpenSearchFirehoseLogGroup', {
      logGroupName: `/aws/kinesisfirehose/realtime-data-stream-${randomSuffix}-opensearch`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Primary Firehose delivery stream for S3
    const s3DeliveryStream = new kinesisfirehose.CfnDeliveryStream(this, 'S3DeliveryStream', {
      deliveryStreamName: `realtime-data-stream-${randomSuffix}`,
      deliveryStreamType: 'DirectPut',
      s3DestinationConfiguration: {
        bucketArn: dataBucket.bucketArn,
        roleArn: firehoseRole.roleArn,
        prefix: 'transformed-data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/',
        errorOutputPrefix: 'error-data/',
        bufferingHints: {
          sizeInMBs: 5,
          intervalInSeconds: 300,
        },
        compressionFormat: 'GZIP',
        processingConfiguration: {
          enabled: true,
          processors: [
            {
              type: 'Lambda',
              parameters: [
                {
                  parameterName: 'LambdaArn',
                  parameterValue: transformFunction.functionArn,
                },
                {
                  parameterName: 'BufferSizeInMBs',
                  parameterValue: '3',
                },
                {
                  parameterName: 'BufferIntervalInSeconds',
                  parameterValue: '60',
                },
              ],
            },
          ],
        },
        dataFormatConversionConfiguration: {
          enabled: true,
          outputFormatConfiguration: {
            serializer: {
              parquetSerDe: {},
            },
          },
        },
        cloudWatchLoggingOptions: {
          enabled: true,
          logGroupName: s3LogGroup.logGroupName,
          logStreamName: 'S3Delivery',
        },
      },
    });

    // OpenSearch delivery stream with optimized buffering
    const openSearchDeliveryStream = new kinesisfirehose.CfnDeliveryStream(this, 'OpenSearchDeliveryStream', {
      deliveryStreamName: `realtime-data-stream-${randomSuffix}-opensearch`,
      deliveryStreamType: 'DirectPut',
      amazonopensearchserviceDestinationConfiguration: {
        roleArn: firehoseRole.roleArn,
        domainArn: openSearchDomain.domainArn,
        indexName: 'realtime-events',
        typeName: '_doc',
        indexRotationPeriod: 'OneDay',
        bufferingHints: {
          sizeInMBs: 1,
          intervalInSeconds: 60,
        },
        retryOptions: {
          durationInSeconds: 3600,
        },
        s3BackupMode: 'AllDocuments',
        s3Configuration: {
          bucketArn: dataBucket.bucketArn,
          roleArn: firehoseRole.roleArn,
          prefix: 'opensearch-backup/',
          bufferingHints: {
            sizeInMBs: 5,
            intervalInSeconds: 300,
          },
          compressionFormat: 'GZIP',
        },
        processingConfiguration: {
          enabled: true,
          processors: [
            {
              type: 'Lambda',
              parameters: [
                {
                  parameterName: 'LambdaArn',
                  parameterValue: transformFunction.functionArn,
                },
              ],
            },
          ],
        },
        cloudWatchLoggingOptions: {
          enabled: true,
          logGroupName: openSearchLogGroup.logGroupName,
          logStreamName: 'OpenSearchDelivery',
        },
      },
    });

    // Add dependencies to ensure proper creation order
    s3DeliveryStream.node.addDependency(transformFunction);
    s3DeliveryStream.node.addDependency(firehoseRole);
    openSearchDeliveryStream.node.addDependency(transformFunction);
    openSearchDeliveryStream.node.addDependency(firehoseRole);
    openSearchDeliveryStream.node.addDependency(openSearchDomain);

    // ============================================================================
    // CLOUDWATCH MONITORING AND ALARMS
    // ============================================================================

    // Alarm for S3 delivery errors
    const s3DeliveryErrorAlarm = new cloudwatch.Alarm(this, 'S3DeliveryErrorAlarm', {
      alarmName: `${s3DeliveryStream.deliveryStreamName}-DeliveryErrors`,
      alarmDescription: 'Monitor Firehose delivery errors to S3',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/KinesisFirehose',
        metricName: 'DeliveryToS3.Records',
        dimensionsMap: {
          DeliveryStreamName: s3DeliveryStream.deliveryStreamName!,
        },
        statistic: 'Sum',
        period: cdk.Duration.seconds(300),
      }),
      threshold: 0,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Alarm for Lambda transformation errors
    const lambdaErrorAlarm = new cloudwatch.Alarm(this, 'LambdaErrorAlarm', {
      alarmName: `${transformFunction.functionName}-Errors`,
      alarmDescription: 'Monitor Lambda transformation errors',
      metric: transformFunction.metricErrors({
        period: cdk.Duration.seconds(300),
      }),
      threshold: 5,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
    });

    // Alarm for OpenSearch delivery errors
    const openSearchErrorAlarm = new cloudwatch.Alarm(this, 'OpenSearchErrorAlarm', {
      alarmName: `${openSearchDeliveryStream.deliveryStreamName}-OpenSearchErrors`,
      alarmDescription: 'Monitor OpenSearch delivery errors',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/KinesisFirehose',
        metricName: 'DeliveryToOpenSearch.Records',
        dimensionsMap: {
          DeliveryStreamName: openSearchDeliveryStream.deliveryStreamName!,
        },
        statistic: 'Sum',
        period: cdk.Duration.seconds(300),
      }),
      threshold: 0,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // ============================================================================
    // OUTPUTS
    // ============================================================================

    new cdk.CfnOutput(this, 'S3BucketName', {
      value: dataBucket.bucketName,
      description: 'Name of the S3 bucket for data storage',
    });

    new cdk.CfnOutput(this, 'S3DeliveryStreamName', {
      value: s3DeliveryStream.deliveryStreamName!,
      description: 'Name of the Kinesis Data Firehose delivery stream for S3',
    });

    new cdk.CfnOutput(this, 'OpenSearchDeliveryStreamName', {
      value: openSearchDeliveryStream.deliveryStreamName!,
      description: 'Name of the Kinesis Data Firehose delivery stream for OpenSearch',
    });

    new cdk.CfnOutput(this, 'OpenSearchDomainEndpoint', {
      value: openSearchDomain.domainEndpoint,
      description: 'OpenSearch domain endpoint for real-time search',
    });

    new cdk.CfnOutput(this, 'TransformFunctionArn', {
      value: transformFunction.functionArn,
      description: 'ARN of the Lambda transformation function',
    });

    new cdk.CfnOutput(this, 'DeadLetterQueueUrl', {
      value: deadLetterQueue.queueUrl,
      description: 'URL of the SQS dead letter queue for error handling',
    });

    new cdk.CfnOutput(this, 'FirehoseRoleArn', {
      value: firehoseRole.roleArn,
      description: 'ARN of the IAM role used by Kinesis Data Firehose',
    });

    // Sample commands for testing
    new cdk.CfnOutput(this, 'SampleTestCommand', {
      value: `aws firehose put-record --delivery-stream-name ${s3DeliveryStream.deliveryStreamName} --record '{"Data":"eyJldmVudF9pZCI6InRlc3QwMDEiLCJ1c2VyX2lkIjoidXNlcjEyMyIsImV2ZW50X3R5cGUiOiJwdXJjaGFzZSIsImFtb3VudCI6MTUwLjUwLCJwcm9kdWN0X2lkIjoicHJvZDQ1NiIsInRpbWVzdGFtcCI6IjIwMjQtMDEtMTVUMTA6MzA6MDBaIn0="}'`,
      description: 'Sample AWS CLI command to test data ingestion',
    });
  }
}

// ============================================================================
// CDK APP DEFINITION
// ============================================================================

const app = new cdk.App();

new RealTimeDataProcessingStack(app, 'RealTimeDataProcessingStack', {
  description: 'Real-time data processing pipeline with Kinesis Data Firehose, Lambda, S3, and OpenSearch',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'RealTimeDataProcessing',
    Environment: 'Development',
    CostCenter: 'Analytics',
  },
});

app.synth();