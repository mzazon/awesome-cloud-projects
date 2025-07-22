#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iot from 'aws-cdk-lib/aws-iot';
import * as iotanalytics from 'aws-cdk-lib/aws-iotanalytics';
import * as kinesis from 'aws-cdk-lib/aws-kinesis';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as timestream from 'aws-cdk-lib/aws-timestream';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Duration } from 'aws-cdk-lib';

/**
 * Stack for IoT Analytics Pipeline demonstrating both legacy IoT Analytics
 * and modern alternatives using Kinesis Data Streams and Amazon Timestream
 */
class IoTAnalyticsPipelineStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // ===========================================
    // IoT Analytics Resources (Legacy - End of Support Dec 15, 2025)
    // ===========================================

    // IoT Analytics Service Role
    const iotAnalyticsRole = new iam.Role(this, 'IoTAnalyticsServiceRole', {
      assumedBy: new iam.ServicePrincipal('iotanalytics.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSIoTAnalyticsServiceRole'),
      ],
      description: 'Service role for IoT Analytics pipeline operations',
    });

    // IoT Analytics Channel - Entry point for raw IoT data
    const iotAnalyticsChannel = new iotanalytics.CfnChannel(this, 'IoTAnalyticsChannel', {
      channelName: `iot-sensor-channel-${uniqueSuffix}`,
      retentionPeriod: {
        unlimited: true,
      },
      tags: [
        {
          key: 'Purpose',
          value: 'IoT Analytics Demo',
        },
      ],
    });

    // IoT Analytics Datastore - Permanent storage for processed data
    const iotAnalyticsDatastore = new iotanalytics.CfnDatastore(this, 'IoTAnalyticsDatastore', {
      datastoreName: `iot-sensor-datastore-${uniqueSuffix}`,
      retentionPeriod: {
        unlimited: true,
      },
      tags: [
        {
          key: 'Purpose',
          value: 'IoT Analytics Demo',
        },
      ],
    });

    // IoT Analytics Pipeline - Data transformation workflow
    const iotAnalyticsPipeline = new iotanalytics.CfnPipeline(this, 'IoTAnalyticsPipeline', {
      pipelineName: `iot-sensor-pipeline-${uniqueSuffix}`,
      pipelineActivities: [
        {
          channel: {
            name: 'ChannelActivity',
            channelName: iotAnalyticsChannel.channelName!,
            next: 'FilterActivity',
          },
        },
        {
          filter: {
            name: 'FilterActivity',
            filter: 'temperature > 0 AND temperature < 100',
            next: 'MathActivity',
          },
        },
        {
          math: {
            name: 'MathActivity',
            math: 'temperature',
            attribute: 'temperature_celsius',
            next: 'AddAttributesActivity',
          },
        },
        {
          addAttributes: {
            name: 'AddAttributesActivity',
            attributes: {
              location: 'factory_floor_1',
              device_type: 'temperature_sensor',
            },
            next: 'DatastoreActivity',
          },
        },
        {
          datastore: {
            name: 'DatastoreActivity',
            datastoreName: iotAnalyticsDatastore.datastoreName!,
          },
        },
      ],
      tags: [
        {
          key: 'Purpose',
          value: 'IoT Analytics Demo',
        },
      ],
    });

    // IoT Analytics Dataset - SQL-based interface for querying processed data
    const iotAnalyticsDataset = new iotanalytics.CfnDataset(this, 'IoTAnalyticsDataset', {
      datasetName: `iot-sensor-dataset-${uniqueSuffix}`,
      actions: [
        {
          actionName: 'SqlAction',
          queryAction: {
            sqlQuery: `SELECT * FROM ${iotAnalyticsDatastore.datastoreName} WHERE temperature_celsius > 25 ORDER BY timestamp DESC LIMIT 100`,
          },
        },
      ],
      triggers: [
        {
          schedule: {
            scheduleExpression: 'rate(1 hour)',
          },
        },
      ],
      tags: [
        {
          key: 'Purpose',
          value: 'IoT Analytics Demo',
        },
      ],
    });

    // IoT Rule to route data to IoT Analytics
    const iotRule = new iot.CfnTopicRule(this, 'IoTAnalyticsRule', {
      ruleName: `IoTAnalyticsRule${uniqueSuffix}`,
      topicRulePayload: {
        sql: 'SELECT * FROM "topic/sensor/data"',
        description: 'Route sensor data to IoT Analytics',
        actions: [
          {
            iotAnalytics: {
              channelName: iotAnalyticsChannel.channelName!,
            },
          },
        ],
      },
    });

    // ===========================================
    // Modern Alternative: Kinesis + Lambda + Timestream
    // ===========================================

    // Kinesis Data Stream for real-time data ingestion
    const kinesisStream = new kinesis.Stream(this, 'IoTSensorStream', {
      streamName: `iot-sensor-stream-${uniqueSuffix}`,
      shardCount: 1,
      streamModeDetails: {
        streamMode: kinesis.StreamMode.PROVISIONED,
      },
      retentionPeriod: Duration.days(1),
      encryption: kinesis.StreamEncryption.MANAGED,
    });

    // Timestream Database for time-series data storage
    const timestreamDatabase = new timestream.CfnDatabase(this, 'IoTSensorDatabase', {
      databaseName: `iot-sensor-db-${uniqueSuffix}`,
      tags: [
        {
          key: 'Purpose',
          value: 'IoT Analytics Demo',
        },
      ],
    });

    // Timestream Table for sensor data
    const timestreamTable = new timestream.CfnTable(this, 'IoTSensorTable', {
      databaseName: timestreamDatabase.databaseName!,
      tableName: 'sensor-data',
      retentionProperties: {
        memoryStoreRetentionPeriodInHours: '24',
        magneticStoreRetentionPeriodInDays: '365',
      },
      tags: [
        {
          key: 'Purpose',
          value: 'IoT Analytics Demo',
        },
      ],
    });

    // Lambda execution role with necessary permissions
    const lambdaExecutionRole = new iam.Role(this, 'LambdaTimestreamRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        TimestreamWritePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'timestream:WriteRecords',
                'timestream:DescribeEndpoints',
              ],
              resources: [
                timestreamTable.attrArn,
                timestreamDatabase.attrArn,
              ],
            }),
          ],
        }),
        KinesisReadPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'kinesis:DescribeStream',
                'kinesis:GetShardIterator',
                'kinesis:GetRecords',
                'kinesis:ListStreams',
              ],
              resources: [kinesisStream.streamArn],
            }),
          ],
        }),
      },
      description: 'Lambda execution role for processing IoT data and writing to Timestream',
    });

    // Lambda function for processing Kinesis records and writing to Timestream
    const dataProcessingFunction = new lambda.Function(this, 'ProcessIoTDataFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: Duration.seconds(60),
      memorySize: 256,
      environment: {
        TIMESTREAM_DATABASE_NAME: timestreamDatabase.databaseName!,
        TIMESTREAM_TABLE_NAME: timestreamTable.tableName!,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import time
import base64
from datetime import datetime
import os

timestream = boto3.client('timestream-write')

def lambda_handler(event, context):
    database_name = os.environ['TIMESTREAM_DATABASE_NAME']
    table_name = os.environ['TIMESTREAM_TABLE_NAME']
    
    records = []
    
    try:
        for record in event['Records']:
            # Parse Kinesis record - data is base64 encoded
            kinesis_data = record['kinesis']['data']
            decoded_data = base64.b64decode(kinesis_data).decode('utf-8')
            payload = json.loads(decoded_data)
            
            # Extract sensor data
            device_id = payload.get('deviceId', 'unknown')
            temperature = payload.get('temperature', 0)
            humidity = payload.get('humidity', 0)
            timestamp = payload.get('timestamp', datetime.utcnow().isoformat())
            
            # Prepare Timestream records
            current_time = str(int(time.time() * 1000))
            
            # Temperature record
            temperature_record = {
                'Time': current_time,
                'TimeUnit': 'MILLISECONDS',
                'Dimensions': [
                    {
                        'Name': 'DeviceId',
                        'Value': device_id
                    },
                    {
                        'Name': 'Location',
                        'Value': 'factory_floor_1'
                    },
                    {
                        'Name': 'DeviceType',
                        'Value': 'temperature_sensor'
                    }
                ],
                'MeasureName': 'temperature',
                'MeasureValue': str(temperature),
                'MeasureValueType': 'DOUBLE'
            }
            
            # Humidity record
            humidity_record = {
                'Time': current_time,
                'TimeUnit': 'MILLISECONDS',
                'Dimensions': [
                    {
                        'Name': 'DeviceId',
                        'Value': device_id
                    },
                    {
                        'Name': 'Location',
                        'Value': 'factory_floor_1'
                    },
                    {
                        'Name': 'DeviceType',
                        'Value': 'humidity_sensor'
                    }
                ],
                'MeasureName': 'humidity',
                'MeasureValue': str(humidity),
                'MeasureValueType': 'DOUBLE'
            }
            
            records.extend([temperature_record, humidity_record])
        
        # Write to Timestream in batches
        if records:
            batch_size = 100
            for i in range(0, len(records), batch_size):
                batch = records[i:i + batch_size]
                response = timestream.write_records(
                    DatabaseName=database_name,
                    TableName=table_name,
                    Records=batch
                )
                print(f"Successfully wrote {len(batch)} records to Timestream")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully processed {len(records)} records',
                'records_processed': len(records)
            })
        }
        
    except Exception as e:
        print(f"Error processing records: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
`),
      description: 'Processes IoT sensor data from Kinesis and writes to Timestream',
    });

    // CloudWatch Log Group for Lambda function
    const logGroup = new logs.LogGroup(this, 'ProcessIoTDataLogGroup', {
      logGroupName: `/aws/lambda/${dataProcessingFunction.functionName}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Event Source Mapping to connect Kinesis to Lambda
    new lambda.EventSourceMapping(this, 'KinesisEventSourceMapping', {
      eventSourceArn: kinesisStream.streamArn,
      target: dataProcessingFunction,
      batchSize: 10,
      maxBatchingWindow: Duration.seconds(5),
      startingPosition: lambda.StartingPosition.LATEST,
      parallelizationFactor: 1,
    });

    // IoT Rule to route data to Kinesis (modern alternative)
    const kinesisIoTRule = new iot.CfnTopicRule(this, 'KinesisIoTRule', {
      ruleName: `KinesisIoTRule${uniqueSuffix}`,
      topicRulePayload: {
        sql: 'SELECT * FROM "topic/sensor/data"',
        description: 'Route sensor data to Kinesis Data Stream',
        actions: [
          {
            kinesis: {
              streamName: kinesisStream.streamName,
              partitionKey: '${clientId()}',
              roleArn: new iam.Role(this, 'KinesisIoTRuleRole', {
                assumedBy: new iam.ServicePrincipal('iot.amazonaws.com'),
                inlinePolicies: {
                  KinesisWritePolicy: new iam.PolicyDocument({
                    statements: [
                      new iam.PolicyStatement({
                        effect: iam.Effect.ALLOW,
                        actions: ['kinesis:PutRecord'],
                        resources: [kinesisStream.streamArn],
                      }),
                    ],
                  }),
                },
              }).roleArn,
            },
          },
        ],
      },
    });

    // ===========================================
    // Outputs
    // ===========================================

    // IoT Analytics outputs
    new cdk.CfnOutput(this, 'IoTAnalyticsChannelName', {
      value: iotAnalyticsChannel.channelName!,
      description: 'IoT Analytics Channel Name (Legacy)',
    });

    new cdk.CfnOutput(this, 'IoTAnalyticsDatastoreName', {
      value: iotAnalyticsDatastore.datastoreName!,
      description: 'IoT Analytics Datastore Name (Legacy)',
    });

    new cdk.CfnOutput(this, 'IoTAnalyticsDatasetName', {
      value: iotAnalyticsDataset.datasetName!,
      description: 'IoT Analytics Dataset Name (Legacy)',
    });

    // Modern alternative outputs
    new cdk.CfnOutput(this, 'KinesisStreamName', {
      value: kinesisStream.streamName,
      description: 'Kinesis Data Stream Name (Modern Alternative)',
    });

    new cdk.CfnOutput(this, 'KinesisStreamArn', {
      value: kinesisStream.streamArn,
      description: 'Kinesis Data Stream ARN',
    });

    new cdk.CfnOutput(this, 'TimestreamDatabaseName', {
      value: timestreamDatabase.databaseName!,
      description: 'Timestream Database Name',
    });

    new cdk.CfnOutput(this, 'TimestreamTableName', {
      value: timestreamTable.tableName!,
      description: 'Timestream Table Name',
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: dataProcessingFunction.functionName,
      description: 'Lambda Function Name for Data Processing',
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: dataProcessingFunction.functionArn,
      description: 'Lambda Function ARN',
    });

    // Test commands
    new cdk.CfnOutput(this, 'TestCommand', {
      value: `aws iot-data publish --topic "topic/sensor/data" --payload '{"deviceId": "sensor001", "temperature": 25.3, "humidity": 60.1, "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'"}'`,
      description: 'Command to send test data to IoT topic',
    });

    new cdk.CfnOutput(this, 'QueryTimestreamCommand', {
      value: `aws timestream-query query --query-string "SELECT * FROM \\"${timestreamDatabase.databaseName!}\\".\\"${timestreamTable.tableName!}\\" WHERE time > ago(1h) ORDER BY time DESC LIMIT 10"`,
      description: 'Command to query Timestream data',
    });
  }
}

// CDK App
const app = new cdk.App();

new IoTAnalyticsPipelineStack(app, 'IoTAnalyticsPipelineStack', {
  description: 'IoT Analytics Pipeline with AWS IoT Analytics (Legacy) and Modern Alternatives (Kinesis + Timestream)',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'IoT Analytics Pipeline',
    Recipe: 'iot-analytics-pipelines-aws-iot-analytics',
    Environment: 'demo',
  },
});

app.synth();