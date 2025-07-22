#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as timestream from 'aws-cdk-lib/aws-timestream';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as iot from 'aws-cdk-lib/aws-iot';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as s3 from 'aws-cdk-lib/aws-s3';
import { Construct } from 'constructs';

/**
 * Configuration interface for the Timestream IoT Solution
 */
interface TimestreamIoTSolutionProps extends cdk.StackProps {
  /**
   * Name for the Timestream database
   * @default 'iot-timeseries-db'
   */
  readonly databaseName?: string;
  
  /**
   * Name for the Timestream table
   * @default 'sensor-data'
   */
  readonly tableName?: string;
  
  /**
   * Memory store retention period in hours
   * @default 24
   */
  readonly memoryStoreRetentionHours?: number;
  
  /**
   * Magnetic store retention period in days
   * @default 365
   */
  readonly magneticStoreRetentionDays?: number;
  
  /**
   * Environment name for resource tagging
   * @default 'production'
   */
  readonly environment?: string;
}

/**
 * CDK Stack for Amazon Timestream IoT Time-Series Data Solution
 * 
 * This stack creates a comprehensive time-series data solution using Amazon Timestream
 * to ingest, store, and analyze IoT sensor data at scale. It includes:
 * - Timestream database and table with lifecycle management
 * - Lambda function for data ingestion and transformation
 * - IoT Core rule for direct data routing
 * - CloudWatch monitoring and alarms
 * - IAM roles with least privilege permissions
 */
export class TimestreamIoTSolutionStack extends cdk.Stack {
  public readonly database: timestream.CfnDatabase;
  public readonly table: timestream.CfnTable;
  public readonly ingestionFunction: lambda.Function;
  public readonly iotRule: iot.CfnTopicRule;
  public readonly rejectedDataBucket: s3.Bucket;

  constructor(scope: Construct, id: string, props: TimestreamIoTSolutionProps = {}) {
    super(scope, id, props);

    // Extract configuration with defaults
    const config = {
      databaseName: props.databaseName ?? 'iot-timeseries-db',
      tableName: props.tableName ?? 'sensor-data',
      memoryStoreRetentionHours: props.memoryStoreRetentionHours ?? 24,
      magneticStoreRetentionDays: props.magneticStoreRetentionDays ?? 365,
      environment: props.environment ?? 'production'
    };

    // Add unique suffix to ensure global uniqueness
    const uniqueSuffix = cdk.Names.uniqueId(this).toLowerCase().substring(0, 8);
    const uniqueDatabaseName = `${config.databaseName}-${uniqueSuffix}`;

    // Create S3 bucket for rejected data (with unique naming)
    this.rejectedDataBucket = new s3.Bucket(this, 'RejectedDataBucket', {
      bucketName: `timestream-rejected-data-${uniqueSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: false,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [{
        id: 'rejected-data-lifecycle',
        enabled: true,
        expiration: cdk.Duration.days(90),
        abortIncompleteMultipartUploadAfter: cdk.Duration.days(7)
      }]
    });

    // Create Timestream database
    this.database = new timestream.CfnDatabase(this, 'TimestreamDatabase', {
      databaseName: uniqueDatabaseName,
      tags: [
        { key: 'Project', value: 'IoT-TimeSeries' },
        { key: 'Environment', value: config.environment },
        { key: 'ManagedBy', value: 'CDK' }
      ]
    });

    // Create Timestream table with retention policies and magnetic store configuration
    this.table = new timestream.CfnTable(this, 'TimestreamTable', {
      databaseName: this.database.ref,
      tableName: config.tableName,
      retentionProperties: {
        memoryStoreRetentionPeriodInHours: config.memoryStoreRetentionHours.toString(),
        magneticStoreRetentionPeriodInDays: config.magneticStoreRetentionDays.toString()
      },
      magneticStoreWriteProperties: {
        enableMagneticStoreWrites: true,
        magneticStoreRejectedDataLocation: {
          s3Configuration: {
            bucketName: this.rejectedDataBucket.bucketName,
            objectKeyPrefix: 'rejected-records/'
          }
        }
      }
    });

    // Ensure table depends on database creation
    this.table.addDependency(this.database);

    // Create IAM role for Lambda function
    const lambdaRole = new iam.Role(this, 'LambdaTimestreamRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for Lambda function to write to Timestream',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ]
    });

    // Add Timestream write permissions to Lambda role
    lambdaRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'timestream:WriteRecords',
        'timestream:DescribeEndpoints'
      ],
      resources: [
        this.database.attrArn,
        `${this.database.attrArn}/table/${config.tableName}`
      ]
    }));

    // Create Lambda function for data ingestion
    this.ingestionFunction = new lambda.Function(this, 'TimestreamIngestionFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      description: 'Processes IoT sensor data and writes to Timestream',
      environment: {
        DATABASE_NAME: this.database.ref,
        TABLE_NAME: config.tableName
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
import time
from datetime import datetime, timezone

timestream = boto3.client('timestream-write')

def lambda_handler(event, context):
    """
    AWS Lambda handler for processing IoT sensor data and writing to Timestream.
    
    Supports multiple event sources:
    - Direct invocation with sensor data
    - SQS/SNS records
    - IoT Core message routing
    """
    try:
        database_name = os.environ['DATABASE_NAME']
        table_name = os.environ['TABLE_NAME']
        
        # Parse IoT message or direct invocation
        if 'Records' in event:
            # SQS/SNS records
            for record in event['Records']:
                body = json.loads(record['body'])
                write_to_timestream(database_name, table_name, body)
        else:
            # Direct invocation
            write_to_timestream(database_name, table_name, event)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Data written to Timestream successfully')
        }
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def write_to_timestream(database_name, table_name, data):
    """
    Write sensor data to Timestream with proper error handling and validation.
    """
    current_time = str(int(time.time() * 1000))
    
    records = []
    
    # Handle different data structures
    if isinstance(data, list):
        for item in data:
            records.extend(create_records(item, current_time))
    else:
        records.extend(create_records(data, current_time))
    
    if records:
        try:
            result = timestream.write_records(
                DatabaseName=database_name,
                TableName=table_name,
                Records=records
            )
            print(f"Successfully wrote {len(records)} records")
            return result
        except Exception as e:
            print(f"Error writing to Timestream: {str(e)}")
            raise

def create_records(data, current_time):
    """
    Transform sensor data into Timestream record format with proper dimensions.
    """
    records = []
    device_id = data.get('device_id', 'unknown')
    location = data.get('location', 'unknown')
    
    # Create dimensions (metadata)
    dimensions = [
        {'Name': 'device_id', 'Value': str(device_id)},
        {'Name': 'location', 'Value': str(location)}
    ]
    
    # Handle sensor readings
    if 'sensors' in data:
        for sensor_type, value in data['sensors'].items():
            records.append({
                'Dimensions': dimensions,
                'MeasureName': sensor_type,
                'MeasureValue': str(value),
                'MeasureValueType': 'DOUBLE',
                'Time': current_time,
                'TimeUnit': 'MILLISECONDS'
            })
    
    # Handle single measurements
    if 'measurement' in data:
        records.append({
            'Dimensions': dimensions,
            'MeasureName': data.get('metric_name', 'value'),
            'MeasureValue': str(data['measurement']),
            'MeasureValueType': 'DOUBLE',
            'Time': current_time,
            'TimeUnit': 'MILLISECONDS'
        })
    
    return records
      `)
    });

    // Create IAM role for IoT Core rule
    const iotRole = new iam.Role(this, 'IoTTimestreamRole', {
      assumedBy: new iam.ServicePrincipal('iot.amazonaws.com'),
      description: 'IAM role for IoT Core to write directly to Timestream'
    });

    // Add Timestream write permissions to IoT role
    iotRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'timestream:WriteRecords',
        'timestream:DescribeEndpoints'
      ],
      resources: [
        this.database.attrArn,
        `${this.database.attrArn}/table/${config.tableName}`
      ]
    }));

    // Create IoT Core rule for direct Timestream integration
    this.iotRule = new iot.CfnTopicRule(this, 'IoTTimestreamRule', {
      ruleName: `timestream_iot_rule_${uniqueSuffix.replace(/-/g, '_')}`,
      topicRulePayload: {
        sql: "SELECT device_id, location, timestamp, temperature, humidity, pressure FROM 'topic/sensors'",
        description: 'Route IoT sensor data directly to Timestream',
        ruleDisabled: false,
        awsIotSqlVersion: '2016-03-23',
        actions: [{
          timestream: {
            roleArn: iotRole.roleArn,
            databaseName: this.database.ref,
            tableName: config.tableName,
            dimensions: [
              {
                name: 'device_id',
                value: '${device_id}'
              },
              {
                name: 'location',
                value: '${location}'
              }
            ]
          }
        }]
      }
    });

    // Create CloudWatch alarms for monitoring
    const ingestionAlarm = new cloudwatch.Alarm(this, 'TimestreamIngestionAlarm', {
      alarmName: `Timestream-IngestionRate-${uniqueDatabaseName}`,
      alarmDescription: 'Monitor Timestream ingestion rate and latency',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Timestream',
        metricName: 'SuccessfulRequestLatency',
        dimensionsMap: {
          'DatabaseName': this.database.ref,
          'TableName': config.tableName,
          'Operation': 'WriteRecords'
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 1000,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    const queryLatencyAlarm = new cloudwatch.Alarm(this, 'TimestreamQueryLatencyAlarm', {
      alarmName: `Timestream-QueryLatency-${uniqueDatabaseName}`,
      alarmDescription: 'Monitor Timestream query performance',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Timestream',
        metricName: 'QueryLatency',
        dimensionsMap: {
          'DatabaseName': this.database.ref
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 5000,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Add outputs for key resources
    new cdk.CfnOutput(this, 'TimestreamDatabaseName', {
      value: this.database.ref,
      description: 'Name of the Timestream database',
      exportName: `${this.stackName}-DatabaseName`
    });

    new cdk.CfnOutput(this, 'TimestreamTableName', {
      value: config.tableName,
      description: 'Name of the Timestream table',
      exportName: `${this.stackName}-TableName`
    });

    new cdk.CfnOutput(this, 'TimestreamDatabaseArn', {
      value: this.database.attrArn,
      description: 'ARN of the Timestream database',
      exportName: `${this.stackName}-DatabaseArn`
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: this.ingestionFunction.functionName,
      description: 'Name of the Lambda ingestion function',
      exportName: `${this.stackName}-LambdaFunctionName`
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: this.ingestionFunction.functionArn,
      description: 'ARN of the Lambda ingestion function',
      exportName: `${this.stackName}-LambdaFunctionArn`
    });

    new cdk.CfnOutput(this, 'IoTRuleName', {
      value: this.iotRule.ref,
      description: 'Name of the IoT Core rule',
      exportName: `${this.stackName}-IoTRuleName`
    });

    new cdk.CfnOutput(this, 'RejectedDataBucketName', {
      value: this.rejectedDataBucket.bucketName,
      description: 'S3 bucket for rejected Timestream data',
      exportName: `${this.stackName}-RejectedDataBucket`
    });

    new cdk.CfnOutput(this, 'IoTTopicPattern', {
      value: 'topic/sensors',
      description: 'IoT topic pattern for sensor data',
      exportName: `${this.stackName}-IoTTopicPattern`
    });

    new cdk.CfnOutput(this, 'SampleQueryCommand', {
      value: `aws timestream-query query --query-string "SELECT device_id, location, measure_name, measure_value::double, time FROM \\"${this.database.ref}\\".~\\"${config.tableName}\\" WHERE time >= ago(1h) ORDER BY time DESC LIMIT 20"`,
      description: 'Sample CLI command to query recent data',
      exportName: `${this.stackName}-SampleQueryCommand`
    });
  }
}

// Create the CDK App
const app = new cdk.App();

// Get configuration from context or use defaults
const environment = app.node.tryGetContext('environment') || 'production';
const databaseName = app.node.tryGetContext('databaseName') || 'iot-timeseries-db';
const tableName = app.node.tryGetContext('tableName') || 'sensor-data';

// Create the stack with configuration
new TimestreamIoTSolutionStack(app, 'TimestreamIoTSolutionStack', {
  description: 'Amazon Timestream IoT Time-Series Data Solution (uksb-1tupboc58)',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  environment,
  databaseName,
  tableName,
  memoryStoreRetentionHours: parseInt(app.node.tryGetContext('memoryStoreRetentionHours') || '24'),
  magneticStoreRetentionDays: parseInt(app.node.tryGetContext('magneticStoreRetentionDays') || '365'),
  tags: {
    Project: 'IoT-TimeSeries',
    Environment: environment,
    ManagedBy: 'CDK',
    Recipe: 'time-series-data-solutions-amazon-timestream'
  }
});