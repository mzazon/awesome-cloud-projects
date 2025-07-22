#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as kinesis from 'aws-cdk-lib/aws-kinesis';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cw_actions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as lambdaEventSources from 'aws-cdk-lib/aws-lambda-event-sources';
import * as kinesisanalytics from 'aws-cdk-lib/aws-kinesisanalytics';
import { Duration, RemovalPolicy } from 'aws-cdk-lib';

/**
 * Properties for the Real-Time IoT Analytics Stack
 */
export interface RealTimeIotAnalyticsStackProps extends cdk.StackProps {
  /**
   * Email address for SNS notifications
   * @default - No email subscription created
   */
  readonly alertEmail?: string;
  
  /**
   * Environment name for resource naming
   * @default 'dev'
   */
  readonly environmentName?: string;
  
  /**
   * Number of shards for Kinesis Data Stream
   * @default 2
   */
  readonly kinesisShardCount?: number;
  
  /**
   * Retention period for S3 data in days
   * @default 30
   */
  readonly s3RetentionDays?: number;
  
  /**
   * Lambda function timeout in seconds
   * @default 60
   */
  readonly lambdaTimeoutSeconds?: number;
  
  /**
   * Lambda function memory size in MB
   * @default 256
   */
  readonly lambdaMemorySize?: number;
}

/**
 * CDK Stack for Real-Time IoT Analytics with Kinesis and Managed Service for Apache Flink
 * 
 * This stack creates a comprehensive real-time IoT analytics pipeline that includes:
 * - Amazon Kinesis Data Streams for high-throughput data ingestion
 * - AWS Lambda for event-driven processing and anomaly detection
 * - Amazon S3 for data storage with organized folder structure
 * - Amazon SNS for real-time alerting
 * - Amazon Managed Service for Apache Flink for stream processing
 * - CloudWatch monitoring and alarms
 * - IAM roles with least privilege access
 */
export class RealTimeIotAnalyticsStack extends cdk.Stack {
  
  // Core resources
  public readonly kinesisStream: kinesis.Stream;
  public readonly dataBucket: s3.Bucket;
  public readonly alertTopic: sns.Topic;
  public readonly processorFunction: lambda.Function;
  
  // Analytics resources
  public readonly flinkApplication: kinesisanalytics.CfnApplication;
  
  // Monitoring resources
  public readonly dashboard: cloudwatch.Dashboard;
  
  constructor(scope: Construct, id: string, props: RealTimeIotAnalyticsStackProps = {}) {
    super(scope, id, props);
    
    // Extract props with defaults
    const environmentName = props.environmentName || 'dev';
    const kinesisShardCount = props.kinesisShardCount || 2;
    const s3RetentionDays = props.s3RetentionDays || 30;
    const lambdaTimeoutSeconds = props.lambdaTimeoutSeconds || 60;
    const lambdaMemorySize = props.lambdaMemorySize || 256;
    
    // Generate unique suffix for resource naming
    const resourceSuffix = cdk.Names.uniqueResourceName(this, {
      maxLength: 8,
      separator: '',
      allowedSpecialCharacters: ''
    }).toLowerCase();
    
    // Create S3 bucket for data storage
    this.dataBucket = this.createS3Bucket(resourceSuffix, s3RetentionDays);
    
    // Create SNS topic for alerts
    this.alertTopic = this.createSNSTopic(resourceSuffix, props.alertEmail);
    
    // Create Kinesis Data Stream
    this.kinesisStream = this.createKinesisStream(resourceSuffix, kinesisShardCount);
    
    // Create Lambda function for IoT data processing
    this.processorFunction = this.createLambdaFunction(
      resourceSuffix,
      lambdaTimeoutSeconds,
      lambdaMemorySize
    );
    
    // Create Flink application for stream analytics
    this.flinkApplication = this.createFlinkApplication(resourceSuffix);
    
    // Create CloudWatch monitoring
    this.createCloudWatchMonitoring(resourceSuffix);
    
    // Create dashboard
    this.dashboard = this.createDashboard(resourceSuffix);
    
    // Output important resource information
    this.createOutputs(resourceSuffix);
  }
  
  /**
   * Creates S3 bucket with proper configuration for IoT data storage
   */
  private createS3Bucket(resourceSuffix: string, retentionDays: number): s3.Bucket {
    const bucket = new s3.Bucket(this, 'DataBucket', {
      bucketName: `iot-analytics-${resourceSuffix}-data-${this.account}`,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: true,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'DeleteOldData',
          enabled: true,
          expiration: Duration.days(retentionDays),
          noncurrentVersionExpiration: Duration.days(7)
        }
      ]
    });
    
    // Add tags for organization
    cdk.Tags.of(bucket).add('Purpose', 'IoT Data Storage');
    cdk.Tags.of(bucket).add('DataClassification', 'Operational');
    
    return bucket;
  }
  
  /**
   * Creates SNS topic for alerting with optional email subscription
   */
  private createSNSTopic(resourceSuffix: string, alertEmail?: string): sns.Topic {
    const topic = new sns.Topic(this, 'AlertTopic', {
      topicName: `iot-analytics-${resourceSuffix}-alerts`,
      displayName: 'IoT Analytics Alerts',
      fifo: false
    });
    
    // Add email subscription if provided
    if (alertEmail) {
      topic.addSubscription(new snsSubscriptions.EmailSubscription(alertEmail));
    }
    
    cdk.Tags.of(topic).add('Purpose', 'IoT Alerting');
    
    return topic;
  }
  
  /**
   * Creates Kinesis Data Stream for IoT data ingestion
   */
  private createKinesisStream(resourceSuffix: string, shardCount: number): kinesis.Stream {
    const stream = new kinesis.Stream(this, 'KinesisStream', {
      streamName: `iot-analytics-${resourceSuffix}-stream`,
      shardCount: shardCount,
      retentionPeriod: Duration.days(1),
      encryption: kinesis.StreamEncryption.MANAGED
    });
    
    cdk.Tags.of(stream).add('Purpose', 'IoT Data Ingestion');
    
    return stream;
  }
  
  /**
   * Creates Lambda function for IoT data processing
   */
  private createLambdaFunction(
    resourceSuffix: string,
    timeoutSeconds: number,
    memorySize: number
  ): lambda.Function {
    
    // Create IAM role for Lambda with least privilege
    const lambdaRole = new iam.Role(this, 'LambdaRole', {
      roleName: `iot-analytics-${resourceSuffix}-lambda-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ]
    });
    
    // Add permissions for Kinesis
    lambdaRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'kinesis:DescribeStream',
        'kinesis:GetRecords',
        'kinesis:GetShardIterator',
        'kinesis:ListStreams'
      ],
      resources: [this.kinesisStream.streamArn]
    }));
    
    // Add permissions for S3
    lambdaRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        's3:PutObject',
        's3:GetObject'
      ],
      resources: [`${this.dataBucket.bucketArn}/*`]
    }));
    
    // Add permissions for SNS
    lambdaRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['sns:Publish'],
      resources: [this.alertTopic.topicArn]
    }));
    
    // Create the Lambda function
    const lambdaFunction = new lambda.Function(this, 'ProcessorFunction', {
      functionName: `iot-analytics-${resourceSuffix}-processor`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(this.getLambdaCode()),
      timeout: Duration.seconds(timeoutSeconds),
      memorySize: memorySize,
      role: lambdaRole,
      environment: {
        S3_BUCKET_NAME: this.dataBucket.bucketName,
        SNS_TOPIC_ARN: this.alertTopic.topicArn
      },
      description: 'Processes IoT data from Kinesis stream with anomaly detection'
    });
    
    // Add Kinesis event source
    lambdaFunction.addEventSource(new lambdaEventSources.KinesisEventSource(this.kinesisStream, {
      batchSize: 10,
      maxBatchingWindow: Duration.seconds(5),
      startingPosition: lambda.StartingPosition.LATEST,
      retryAttempts: 3
    }));
    
    cdk.Tags.of(lambdaFunction).add('Purpose', 'IoT Data Processing');
    
    return lambdaFunction;
  }
  
  /**
   * Creates Flink application for stream analytics
   */
  private createFlinkApplication(resourceSuffix: string): kinesisanalytics.CfnApplication {
    // Create IAM role for Flink
    const flinkRole = new iam.Role(this, 'FlinkRole', {
      roleName: `iot-analytics-${resourceSuffix}-flink-role`,
      assumedBy: new iam.ServicePrincipal('kinesisanalytics.amazonaws.com'),
    });
    
    // Add permissions for Kinesis
    flinkRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'kinesis:DescribeStream',
        'kinesis:GetRecords',
        'kinesis:GetShardIterator',
        'kinesis:ListStreams'
      ],
      resources: [this.kinesisStream.streamArn]
    }));
    
    // Add permissions for S3
    flinkRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        's3:PutObject',
        's3:GetObject',
        's3:ListBucket'
      ],
      resources: [
        this.dataBucket.bucketArn,
        `${this.dataBucket.bucketArn}/*`
      ]
    }));
    
    // Add CloudWatch permissions
    flinkRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
        'logs:PutLogEvents'
      ],
      resources: ['*']
    }));
    
    // Create Flink application
    const flinkApp = new kinesisanalytics.CfnApplication(this, 'FlinkApplication', {
      applicationName: `iot-analytics-${resourceSuffix}-flink-app`,
      runtimeEnvironment: 'FLINK-1_18',
      serviceExecutionRole: flinkRole.roleArn,
      applicationDescription: 'Real-time IoT analytics with windowed aggregations'
    });
    
    cdk.Tags.of(flinkApp).add('Purpose', 'IoT Stream Analytics');
    
    return flinkApp;
  }
  
  /**
   * Creates CloudWatch monitoring alarms
   */
  private createCloudWatchMonitoring(resourceSuffix: string): void {
    // Alarm for high Kinesis incoming records
    const kinesisAlarm = new cloudwatch.Alarm(this, 'KinesisHighVolumeAlarm', {
      alarmName: `${resourceSuffix}-kinesis-high-volume`,
      alarmDescription: 'High volume of incoming Kinesis records',
      metric: this.kinesisStream.metricIncomingRecords({
        statistic: cloudwatch.Statistic.SUM,
        period: Duration.minutes(5)
      }),
      threshold: 100,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });
    
    kinesisAlarm.addAlarmAction(new cw_actions.SnsAction(this.alertTopic));
    
    // Alarm for Lambda errors
    const lambdaErrorAlarm = new cloudwatch.Alarm(this, 'LambdaErrorAlarm', {
      alarmName: `${resourceSuffix}-lambda-errors`,
      alarmDescription: 'Lambda function errors',
      metric: this.processorFunction.metricErrors({
        statistic: cloudwatch.Statistic.SUM,
        period: Duration.minutes(5)
      }),
      threshold: 5,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });
    
    lambdaErrorAlarm.addAlarmAction(new cw_actions.SnsAction(this.alertTopic));
    
    // Alarm for Lambda duration
    const lambdaDurationAlarm = new cloudwatch.Alarm(this, 'LambdaDurationAlarm', {
      alarmName: `${resourceSuffix}-lambda-duration`,
      alarmDescription: 'Lambda function high duration',
      metric: this.processorFunction.metricDuration({
        statistic: cloudwatch.Statistic.AVERAGE,
        period: Duration.minutes(5)
      }),
      threshold: 30000, // 30 seconds
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });
    
    lambdaDurationAlarm.addAlarmAction(new cw_actions.SnsAction(this.alertTopic));
  }
  
  /**
   * Creates CloudWatch dashboard for monitoring
   */
  private createDashboard(resourceSuffix: string): cloudwatch.Dashboard {
    const dashboard = new cloudwatch.Dashboard(this, 'MonitoringDashboard', {
      dashboardName: `iot-analytics-${resourceSuffix}-dashboard`,
      defaultInterval: Duration.minutes(5)
    });
    
    // Kinesis metrics widget
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Kinesis Stream Metrics',
        left: [
          this.kinesisStream.metricIncomingRecords({
            statistic: cloudwatch.Statistic.SUM,
            label: 'Incoming Records'
          }),
          this.kinesisStream.metricOutgoingRecords({
            statistic: cloudwatch.Statistic.SUM,
            label: 'Outgoing Records'
          })
        ],
        width: 12,
        height: 6
      })
    );
    
    // Lambda metrics widget
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Lambda Function Metrics',
        left: [
          this.processorFunction.metricInvocations({
            statistic: cloudwatch.Statistic.SUM,
            label: 'Invocations'
          }),
          this.processorFunction.metricErrors({
            statistic: cloudwatch.Statistic.SUM,
            label: 'Errors'
          })
        ],
        right: [
          this.processorFunction.metricDuration({
            statistic: cloudwatch.Statistic.AVERAGE,
            label: 'Duration (ms)'
          })
        ],
        width: 12,
        height: 6
      })
    );
    
    // S3 metrics widget
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'S3 Bucket Metrics',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/S3',
            metricName: 'NumberOfObjects',
            dimensionsMap: {
              BucketName: this.dataBucket.bucketName,
              StorageType: 'AllStorageTypes'
            },
            statistic: cloudwatch.Statistic.AVERAGE,
            label: 'Object Count'
          })
        ],
        right: [
          new cloudwatch.Metric({
            namespace: 'AWS/S3',
            metricName: 'BucketSizeBytes',
            dimensionsMap: {
              BucketName: this.dataBucket.bucketName,
              StorageType: 'StandardStorage'
            },
            statistic: cloudwatch.Statistic.AVERAGE,
            label: 'Bucket Size (Bytes)'
          })
        ],
        width: 12,
        height: 6
      })
    );
    
    return dashboard;
  }
  
  /**
   * Creates stack outputs for key resources
   */
  private createOutputs(resourceSuffix: string): void {
    new cdk.CfnOutput(this, 'KinesisStreamName', {
      value: this.kinesisStream.streamName,
      description: 'Name of the Kinesis Data Stream for IoT data ingestion',
      exportName: `${this.stackName}-KinesisStreamName`
    });
    
    new cdk.CfnOutput(this, 'KinesisStreamArn', {
      value: this.kinesisStream.streamArn,
      description: 'ARN of the Kinesis Data Stream',
      exportName: `${this.stackName}-KinesisStreamArn`
    });
    
    new cdk.CfnOutput(this, 'S3BucketName', {
      value: this.dataBucket.bucketName,
      description: 'Name of the S3 bucket for data storage',
      exportName: `${this.stackName}-S3BucketName`
    });
    
    new cdk.CfnOutput(this, 'S3BucketArn', {
      value: this.dataBucket.bucketArn,
      description: 'ARN of the S3 bucket for data storage',
      exportName: `${this.stackName}-S3BucketArn`
    });
    
    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: this.alertTopic.topicArn,
      description: 'ARN of the SNS topic for alerts',
      exportName: `${this.stackName}-SNSTopicArn`
    });
    
    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: this.processorFunction.functionName,
      description: 'Name of the Lambda function for IoT data processing',
      exportName: `${this.stackName}-LambdaFunctionName`
    });
    
    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: this.processorFunction.functionArn,
      description: 'ARN of the Lambda function for IoT data processing',
      exportName: `${this.stackName}-LambdaFunctionArn`
    });
    
    new cdk.CfnOutput(this, 'FlinkApplicationName', {
      value: this.flinkApplication.applicationName!,
      description: 'Name of the Flink application for stream analytics',
      exportName: `${this.stackName}-FlinkApplicationName`
    });
    
    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard',
      exportName: `${this.stackName}-DashboardUrl`
    });
  }
  
  /**
   * Returns the Lambda function code as inline code
   */
  private getLambdaCode(): string {
    return `
import json
import boto3
import base64
from datetime import datetime
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3 = boto3.client('s3')
sns = boto3.client('sns')

def lambda_handler(event, context):
    """
    Main Lambda handler for processing IoT data from Kinesis
    """
    try:
        bucket_name = os.environ['S3_BUCKET_NAME']
        topic_arn = os.environ['SNS_TOPIC_ARN']
        
        processed_records = []
        
        for record in event['Records']:
            try:
                # Decode Kinesis data
                payload = base64.b64decode(record['kinesis']['data']).decode('utf-8')
                data = json.loads(payload)
                
                # Process the IoT data
                processed_data = process_iot_data(data)
                processed_records.append(processed_data)
                
                # Store raw data in S3
                store_raw_data(data, bucket_name, record['kinesis']['sequenceNumber'])
                
                # Check for anomalies and send alerts
                if is_anomaly(processed_data):
                    send_alert(processed_data, topic_arn)
                    
            except Exception as e:
                logger.error(f"Error processing record: {str(e)}")
                continue
        
        logger.info(f"Successfully processed {len(processed_records)} records")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Processed {len(processed_records)} records',
                'processedRecords': len(processed_records)
            })
        }
        
    except Exception as e:
        logger.error(f"Error in lambda_handler: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }

def process_iot_data(data):
    """
    Process IoT sensor data with validation and enrichment
    """
    return {
        'device_id': data.get('device_id', 'unknown'),
        'timestamp': data.get('timestamp', datetime.now().isoformat()),
        'sensor_type': data.get('sensor_type', 'unknown'),
        'value': float(data.get('value', 0)) if data.get('value') is not None else 0,
        'unit': data.get('unit', ''),
        'location': data.get('location', 'unknown'),
        'processed_at': datetime.now().isoformat(),
        'status': 'processed'
    }

def store_raw_data(data, bucket_name, sequence_number):
    """
    Store raw IoT data in S3 with time-based partitioning
    """
    try:
        timestamp = datetime.now().strftime('%Y/%m/%d/%H')
        key = f"raw-data/{timestamp}/{sequence_number}.json"
        
        s3.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=json.dumps(data, indent=2),
            ContentType='application/json',
            ServerSideEncryption='AES256'
        )
        
        logger.info(f"Stored raw data: s3://{bucket_name}/{key}")
        
    except Exception as e:
        logger.error(f"Error storing raw data: {str(e)}")
        raise

def is_anomaly(data):
    """
    Simple anomaly detection logic with configurable thresholds
    """
    try:
        sensor_type = data.get('sensor_type', '').lower()
        value = float(data.get('value', 0))
        
        # Define anomaly thresholds by sensor type
        thresholds = {
            'temperature': {'min': -10, 'max': 80},
            'pressure': {'min': 0, 'max': 100},
            'vibration': {'min': 0, 'max': 50},
            'flow': {'min': 0, 'max': 200}
        }
        
        if sensor_type in thresholds:
            threshold = thresholds[sensor_type]
            return value < threshold['min'] or value > threshold['max']
        
        # Default anomaly detection for unknown sensor types
        return value > 1000 or value < -1000
        
    except Exception as e:
        logger.error(f"Error in anomaly detection: {str(e)}")
        return False

def send_alert(data, topic_arn):
    """
    Send alert via SNS with detailed information
    """
    try:
        message = {
            'alert_type': 'anomaly_detected',
            'device_id': data.get('device_id'),
            'sensor_type': data.get('sensor_type'),
            'value': data.get('value'),
            'unit': data.get('unit'),
            'location': data.get('location'),
            'timestamp': data.get('timestamp'),
            'processed_at': data.get('processed_at')
        }
        
        subject = f"IoT Anomaly Alert: {data.get('sensor_type', 'Unknown')} Sensor"
        message_text = f"""
ALERT: Anomaly detected in IoT sensor data

Device ID: {data.get('device_id', 'Unknown')}
Sensor Type: {data.get('sensor_type', 'Unknown')}
Value: {data.get('value', 'Unknown')} {data.get('unit', '')}
Location: {data.get('location', 'Unknown')}
Timestamp: {data.get('timestamp', 'Unknown')}

Please investigate immediately.
        """
        
        sns.publish(
            TopicArn=topic_arn,
            Message=message_text,
            Subject=subject,
            MessageAttributes={
                'alert_type': {
                    'DataType': 'String',
                    'StringValue': 'anomaly'
                },
                'device_id': {
                    'DataType': 'String',
                    'StringValue': data.get('device_id', 'unknown')
                },
                'sensor_type': {
                    'DataType': 'String',
                    'StringValue': data.get('sensor_type', 'unknown')
                }
            }
        )
        
        logger.info(f"Alert sent for device {data.get('device_id')} - {data.get('sensor_type')}")
        
    except Exception as e:
        logger.error(f"Error sending alert: {str(e)}")
        raise
`;
  }
}

// Main CDK App
const app = new cdk.App();

// Get configuration from context or environment
const environmentName = app.node.tryGetContext('environment') || 'dev';
const alertEmail = app.node.tryGetContext('alertEmail');
const kinesisShardCount = app.node.tryGetContext('kinesisShardCount') || 2;
const s3RetentionDays = app.node.tryGetContext('s3RetentionDays') || 30;

// Create the stack
new RealTimeIotAnalyticsStack(app, 'RealTimeIotAnalyticsStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  },
  description: 'Real-Time IoT Analytics with Kinesis and Managed Service for Apache Flink',
  
  // Stack configuration
  environmentName,
  alertEmail,
  kinesisShardCount,
  s3RetentionDays,
  lambdaTimeoutSeconds: 60,
  lambdaMemorySize: 256,
  
  // Stack tags
  tags: {
    Project: 'IoT Analytics',
    Environment: environmentName,
    Owner: 'DevOps Team',
    CostCenter: 'Engineering',
    ManagedBy: 'CDK'
  }
});

// Synthesize the app
app.synth();