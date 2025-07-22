#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as kinesisfirehose from 'aws-cdk-lib/aws-kinesisfirehose';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Stack for Streaming ETL with Kinesis Data Firehose
 * This stack creates a complete pipeline for processing real-time clickstream data
 * including Lambda transformations, S3 storage, and Parquet format conversion.
 */
export class StreamingEtlFirehoseStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = this.node.addr.substring(0, 8);

    // S3 bucket for storing processed data with intelligent partitioning
    const dataBucket = new s3.Bucket(this, 'StreamingEtlDataBucket', {
      bucketName: `streaming-etl-data-${uniqueSuffix}`,
      versioned: false,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'TransitionToIA',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30)
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90)
            }
          ]
        }
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // CloudWatch Log Group for Lambda function
    const transformLogGroup = new logs.LogGroup(this, 'TransformFunctionLogGroup', {
      logGroupName: `/aws/lambda/firehose-transform-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // IAM role for Lambda function with basic execution permissions
    const lambdaExecutionRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `FirehoseLambdaRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        CloudWatchLogsPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents'
              ],
              resources: [transformLogGroup.logGroupArn]
            })
          ]
        })
      }
    });

    // Lambda function for data transformation
    const transformFunction = new lambda.Function(this, 'TransformFunction', {
      functionName: `firehose-transform-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 128,
      logGroup: transformLogGroup,
      code: lambda.Code.fromInline(`
import json
import base64
import boto3
from datetime import datetime

def lambda_handler(event, context):
    """
    Transform function for Kinesis Data Firehose
    Processes incoming records, enriches with metadata, and formats for analytics
    """
    output = []
    
    for record in event['records']:
        try:
            # Decode the data from Firehose
            compressed_payload = base64.b64decode(record['data'])
            uncompressed_payload = compressed_payload.decode('utf-8')
            
            # Parse JSON data
            data = json.loads(uncompressed_payload)
            
            # Transform and enrich the data
            transformed_data = {
                'timestamp': datetime.utcnow().isoformat(),
                'event_type': data.get('event_type', 'unknown'),
                'user_id': data.get('user_id', 'anonymous'),
                'session_id': data.get('session_id', ''),
                'page_url': data.get('page_url', ''),
                'referrer': data.get('referrer', ''),
                'user_agent': data.get('user_agent', ''),
                'ip_address': data.get('ip_address', ''),
                'processed_by': 'lambda-firehose-transform',
                'processing_timestamp': datetime.utcnow().isoformat()
            }
            
            # Add line break for JSONL format in S3
            json_output = json.dumps(transformed_data) + '\\n'
            
            # Encode the transformed data
            output_record = {
                'recordId': record['recordId'],
                'result': 'Ok',
                'data': base64.b64encode(json_output.encode('utf-8')).decode('utf-8')
            }
            
        except Exception as e:
            print(f"Error processing record {record.get('recordId', 'unknown')}: {str(e)}")
            # Mark record as processing failed - Firehose will handle retry/error bucket
            output_record = {
                'recordId': record['recordId'],
                'result': 'ProcessingFailed'
            }
        
        output.append(output_record)
    
    print(f"Successfully processed {len([r for r in output if r['result'] == 'Ok'])} out of {len(output)} records")
    return {'records': output}
      `),
      description: 'Lambda function to transform streaming data for Kinesis Data Firehose'
    });

    // IAM role for Kinesis Data Firehose with comprehensive permissions
    const firehoseDeliveryRole = new iam.Role(this, 'FirehoseDeliveryRole', {
      roleName: `FirehoseDeliveryRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('firehose.amazonaws.com'),
      inlinePolicies: {
        S3DeliveryPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:AbortMultipartUpload',
                's3:GetBucketLocation',
                's3:GetObject',
                's3:ListBucket',
                's3:ListBucketMultipartUploads',
                's3:PutObject'
              ],
              resources: [
                dataBucket.bucketArn,
                `${dataBucket.bucketArn}/*`
              ]
            })
          ]
        }),
        LambdaInvokePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['lambda:InvokeFunction'],
              resources: [transformFunction.functionArn]
            })
          ]
        }),
        CloudWatchLogsPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents'
              ],
              resources: ['*']
            })
          ]
        })
      }
    });

    // Add managed policy for Kinesis Firehose service role
    firehoseDeliveryRole.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSKinesisFirehoseServiceRolePolicy')
    );

    // Kinesis Data Firehose delivery stream with Lambda transformation and Parquet conversion
    const deliveryStream = new kinesisfirehose.CfnDeliveryStream(this, 'DeliveryStream', {
      deliveryStreamName: `streaming-etl-${uniqueSuffix}`,
      deliveryStreamType: 'DirectPut',
      s3DestinationConfiguration: {
        bucketArn: dataBucket.bucketArn,
        roleArn: firehoseDeliveryRole.roleArn,
        // Intelligent partitioning by date and hour for efficient querying
        prefix: 'processed-data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/',
        errorOutputPrefix: 'error-data/',
        bufferingHints: {
          sizeInMBs: 5,
          intervalInSeconds: 300
        },
        compressionFormat: 'GZIP',
        // Processing configuration for Lambda transformation
        processingConfiguration: {
          enabled: true,
          processors: [
            {
              type: 'Lambda',
              parameters: [
                {
                  parameterName: 'LambdaArn',
                  parameterValue: transformFunction.functionArn
                },
                {
                  parameterName: 'BufferSizeInMBs',
                  parameterValue: '1'
                },
                {
                  parameterName: 'BufferIntervalInSeconds',
                  parameterValue: '60'
                }
              ]
            }
          ]
        },
        // Data format conversion to Parquet for optimized analytics
        dataFormatConversionConfiguration: {
          enabled: true,
          outputFormatConfiguration: {
            serializer: {
              parquetSerDe: {}
            }
          },
          schemaConfiguration: {
            databaseName: 'default',
            tableName: 'streaming_etl_data',
            roleArn: firehoseDeliveryRole.roleArn
          }
        },
        // CloudWatch logging configuration
        cloudWatchLoggingOptions: {
          enabled: true,
          logGroupName: `/aws/kinesisfirehose/streaming-etl-${uniqueSuffix}`
        }
      }
    });

    // Ensure proper dependency ordering
    deliveryStream.addDependency(firehoseDeliveryRole.node.defaultChild as cdk.CfnResource);
    deliveryStream.addDependency(transformFunction.node.defaultChild as cdk.CfnResource);

    // CloudWatch Log Group for Firehose
    const firehoseLogGroup = new logs.LogGroup(this, 'FirehoseLogGroup', {
      logGroupName: `/aws/kinesisfirehose/streaming-etl-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Stack outputs for easy reference and integration
    new cdk.CfnOutput(this, 'S3BucketName', {
      value: dataBucket.bucketName,
      description: 'S3 bucket name for storing processed data',
      exportName: `${this.stackName}-S3BucketName`
    });

    new cdk.CfnOutput(this, 'DeliveryStreamName', {
      value: deliveryStream.deliveryStreamName!,
      description: 'Kinesis Data Firehose delivery stream name',
      exportName: `${this.stackName}-DeliveryStreamName`
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: transformFunction.functionName,
      description: 'Lambda function name for data transformation',
      exportName: `${this.stackName}-LambdaFunctionName`
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: transformFunction.functionArn,
      description: 'Lambda function ARN for data transformation',
      exportName: `${this.stackName}-LambdaFunctionArn`
    });

    new cdk.CfnOutput(this, 'FirehoseRoleArn', {
      value: firehoseDeliveryRole.roleArn,
      description: 'Firehose delivery role ARN',
      exportName: `${this.stackName}-FirehoseRoleArn`
    });

    // Example CLI command for sending test data
    new cdk.CfnOutput(this, 'TestDataCommand', {
      value: `aws firehose put-record --delivery-stream-name ${deliveryStream.deliveryStreamName} --record '{"Data":"eyJldmVudF90eXBlIjogInBhZ2VfdmlldyIsICJ1c2VyX2lkIjogInVzZXIxMjMiLCAic2Vzc2lvbl9pZCI6ICJzZXNzaW9uNDU2IiwgInBhZ2VfdXJsIjogImh0dHBzOi8vZXhhbXBsZS5jb20vcHJvZHVjdHMiLCAicmVmZXJyZXIiOiAiaHR0cHM6Ly9nb29nbGUuY29tIiwgInVzZXJfYWdlbnQiOiAiTW96aWxsYS81LjAiLCAiaXBfYWRkcmVzcyI6ICIxOTIuMTY4LjEuMSJ9"}'`,
      description: 'Example command to send test data to the Firehose stream'
    });

    // Tags for resource management and cost tracking
    cdk.Tags.of(this).add('Project', 'StreamingETL');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }
}

// CDK App instantiation
const app = new cdk.App();

// Create the stack with default environment
new StreamingEtlFirehoseStack(app, 'StreamingEtlFirehoseStack', {
  description: 'Streaming ETL pipeline with Kinesis Data Firehose transformations, Lambda processing, and S3 storage with Parquet conversion',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'StreamingETL',
    Recipe: 'etl-kinesis-data-firehose-transformations'
  }
});