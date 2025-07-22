#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as kinesis from 'aws-cdk-lib/aws-kinesis';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as logs from 'aws-cdk-lib/aws-logs';
import { KinesisEventSource } from 'aws-cdk-lib/aws-lambda-event-sources';

/**
 * Properties for the RealTimeAnalyticsStack
 */
interface RealTimeAnalyticsStackProps extends cdk.StackProps {
  /** Name prefix for resources */
  readonly resourcePrefix?: string;
  /** Number of Kinesis shards */
  readonly shardCount?: number;
  /** Retention period in hours */
  readonly retentionPeriodHours?: number;
  /** Environment name */
  readonly environmentName?: string;
}

/**
 * CDK Stack for Real-Time Analytics with Amazon Kinesis Data Streams
 * 
 * This stack creates a complete real-time analytics pipeline including:
 * - Kinesis Data Stream with configurable shards
 * - Lambda function for stream processing
 * - S3 bucket for analytics data storage
 * - CloudWatch monitoring and alarms
 * - IAM roles with least privilege access
 */
export class RealTimeAnalyticsStack extends cdk.Stack {
  /** The Kinesis Data Stream */
  public readonly kinesisStream: kinesis.Stream;
  
  /** The Lambda function for processing */
  public readonly processingFunction: lambda.Function;
  
  /** The S3 bucket for analytics storage */
  public readonly analyticsBucket: s3.Bucket;
  
  /** CloudWatch dashboard for monitoring */
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: RealTimeAnalyticsStackProps = {}) {
    super(scope, id, props);

    // Extract configuration with defaults
    const resourcePrefix = props.resourcePrefix || 'analytics';
    const shardCount = props.shardCount || 3;
    const retentionPeriodHours = props.retentionPeriodHours || 168; // 7 days
    const environmentName = props.environmentName || 'dev';

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8);

    // Create S3 bucket for analytics data storage
    this.analyticsBucket = new s3.Bucket(this, 'AnalyticsBucket', {
      bucketName: `${resourcePrefix}-kinesis-${uniqueSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Use RETAIN for production
      autoDeleteObjects: true, // Use false for production
      versioned: false,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'AnalyticsDataLifecycle',
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
          ],
          expiration: cdk.Duration.days(365)
        }
      ]
    });

    // Create Kinesis Data Stream
    this.kinesisStream = new kinesis.Stream(this, 'AnalyticsStream', {
      streamName: `${resourcePrefix}-stream-${uniqueSuffix}`,
      shardCount: shardCount,
      retentionPeriod: cdk.Duration.hours(retentionPeriodHours),
      encryption: kinesis.StreamEncryption.MANAGED,
      streamModeDetails: {
        streamMode: kinesis.StreamMode.PROVISIONED
      }
    });

    // Create IAM role for Lambda function
    const lambdaRole = new iam.Role(this, 'StreamProcessorRole', {
      roleName: `KinesisAnalyticsRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        StreamProcessorPolicy: new iam.PolicyDocument({
          statements: [
            // Kinesis permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'kinesis:DescribeStream',
                'kinesis:GetShardIterator',
                'kinesis:GetRecords',
                'kinesis:ListStreams'
              ],
              resources: [this.kinesisStream.streamArn]
            }),
            // S3 permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:PutObject',
                's3:GetObject'
              ],
              resources: [this.analyticsBucket.arnForObjects('*')]
            }),
            // CloudWatch metrics permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:PutMetricData'
              ],
              resources: ['*']
            })
          ]
        })
      }
    });

    // Create Lambda function for stream processing
    this.processingFunction = new lambda.Function(this, 'StreamProcessor', {
      functionName: `stream-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      environment: {
        S3_BUCKET: this.analyticsBucket.bucketName,
        ENVIRONMENT: environmentName
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
import json
import boto3
import base64
import datetime
import os
from decimal import Decimal

s3_client = boto3.client('s3')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """
    Process Kinesis records in real-time
    
    This function:
    1. Decodes Kinesis records
    2. Extracts analytics metrics
    3. Stores enriched data to S3
    4. Publishes custom metrics to CloudWatch
    """
    processed_records = 0
    total_amount = 0
    error_count = 0
    
    try:
        for record in event['Records']:
            try:
                # Decode Kinesis data
                payload = base64.b64decode(record['kinesis']['data']).decode('utf-8')
                data = json.loads(payload)
                
                # Process analytics data
                processed_records += 1
                
                # Example: Extract transaction amount for financial data
                if 'amount' in data:
                    total_amount += float(data['amount'])
                
                # Store processed record to S3
                timestamp = datetime.datetime.now().isoformat()
                s3_key = f"analytics-data/{timestamp[:10]}/{record['kinesis']['sequenceNumber']}.json"
                
                # Add processing metadata
                enhanced_data = {
                    'original_data': data,
                    'processed_at': timestamp,
                    'shard_id': record['kinesis']['partitionKey'],
                    'sequence_number': record['kinesis']['sequenceNumber'],
                    'environment': os.environ.get('ENVIRONMENT', 'unknown')
                }
                
                s3_client.put_object(
                    Bucket=os.environ['S3_BUCKET'],
                    Key=s3_key,
                    Body=json.dumps(enhanced_data, default=str),
                    ContentType='application/json'
                )
                
            except Exception as record_error:
                print(f"Error processing record: {record_error}")
                error_count += 1
                continue
        
        # Send custom metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='KinesisAnalytics',
            MetricData=[
                {
                    'MetricName': 'ProcessedRecords',
                    'Value': processed_records,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'Environment',
                            'Value': os.environ.get('ENVIRONMENT', 'unknown')
                        }
                    ]
                },
                {
                    'MetricName': 'TotalAmount',
                    'Value': total_amount,
                    'Unit': 'None',
                    'Dimensions': [
                        {
                            'Name': 'Environment',
                            'Value': os.environ.get('ENVIRONMENT', 'unknown')
                        }
                    ]
                },
                {
                    'MetricName': 'ProcessingErrors',
                    'Value': error_count,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'Environment',
                            'Value': os.environ.get('ENVIRONMENT', 'unknown')
                        }
                    ]
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'processed_records': processed_records,
                'total_amount': total_amount,
                'error_count': error_count
            })
        }
        
    except Exception as e:
        print(f"Lambda execution error: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
      `)
    });

    // Add Kinesis event source to Lambda
    this.processingFunction.addEventSource(new KinesisEventSource(this.kinesisStream, {
      startingPosition: lambda.StartingPosition.LATEST,
      batchSize: 10,
      maxBatchingWindow: cdk.Duration.seconds(5),
      retryAttempts: 3,
      parallelizationFactor: 1
    }));

    // Create SNS topic for alerts
    const alertTopic = new sns.Topic(this, 'AlertTopic', {
      topicName: `kinesis-analytics-alerts-${uniqueSuffix}`,
      displayName: 'Kinesis Analytics Alerts'
    });

    // Create CloudWatch alarms
    const highIncomingRecordsAlarm = new cloudwatch.Alarm(this, 'HighIncomingRecordsAlarm', {
      alarmName: `KinesisHighIncomingRecords-${uniqueSuffix}`,
      alarmDescription: 'Alert when incoming records exceed threshold',
      metric: this.kinesisStream.metricIncomingRecords({
        statistic: cloudwatch.Statistic.SUM,
        period: cdk.Duration.minutes(5)
      }),
      threshold: 1000,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    const lambdaErrorsAlarm = new cloudwatch.Alarm(this, 'LambdaErrorsAlarm', {
      alarmName: `LambdaProcessingErrors-${uniqueSuffix}`,
      alarmDescription: 'Alert on Lambda processing errors',
      metric: this.processingFunction.metricErrors({
        statistic: cloudwatch.Statistic.SUM,
        period: cdk.Duration.minutes(5)
      }),
      threshold: 1,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Add SNS actions to alarms
    highIncomingRecordsAlarm.addAlarmAction(
      new cloudwatch.actions.SnsAction(alertTopic)
    );
    lambdaErrorsAlarm.addAlarmAction(
      new cloudwatch.actions.SnsAction(alertTopic)
    );

    // Create CloudWatch dashboard
    this.dashboard = new cloudwatch.Dashboard(this, 'AnalyticsDashboard', {
      dashboardName: `KinesisAnalytics-${uniqueSuffix}`,
      widgets: [
        [
          // Kinesis metrics
          new cloudwatch.GraphWidget({
            title: 'Kinesis Stream Metrics',
            left: [
              this.kinesisStream.metricIncomingRecords({
                statistic: cloudwatch.Statistic.SUM,
                period: cdk.Duration.minutes(5),
                label: 'Incoming Records'
              }),
              this.kinesisStream.metricOutgoingRecords({
                statistic: cloudwatch.Statistic.SUM,
                period: cdk.Duration.minutes(5),
                label: 'Outgoing Records'
              })
            ],
            width: 12,
            height: 6
          })
        ],
        [
          // Lambda metrics
          new cloudwatch.GraphWidget({
            title: 'Lambda Processing Metrics',
            left: [
              this.processingFunction.metricInvocations({
                statistic: cloudwatch.Statistic.SUM,
                period: cdk.Duration.minutes(5),
                label: 'Invocations'
              }),
              this.processingFunction.metricErrors({
                statistic: cloudwatch.Statistic.SUM,
                period: cdk.Duration.minutes(5),
                label: 'Errors'
              })
            ],
            right: [
              this.processingFunction.metricDuration({
                statistic: cloudwatch.Statistic.AVERAGE,
                period: cdk.Duration.minutes(5),
                label: 'Duration (ms)'
              })
            ],
            width: 12,
            height: 6
          })
        ],
        [
          // Custom business metrics
          new cloudwatch.GraphWidget({
            title: 'Business Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'KinesisAnalytics',
                metricName: 'ProcessedRecords',
                statistic: cloudwatch.Statistic.SUM,
                period: cdk.Duration.minutes(5),
                label: 'Processed Records'
              }),
              new cloudwatch.Metric({
                namespace: 'KinesisAnalytics',
                metricName: 'TotalAmount',
                statistic: cloudwatch.Statistic.SUM,
                period: cdk.Duration.minutes(5),
                label: 'Total Amount'
              })
            ],
            width: 12,
            height: 6
          })
        ]
      ]
    });

    // Add tags to all resources
    const tags = {
      Project: 'RealTimeAnalytics',
      Environment: environmentName,
      Component: 'KinesisDataStreams',
      ManagedBy: 'CDK'
    };

    Object.entries(tags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });

    // Outputs
    new cdk.CfnOutput(this, 'KinesisStreamName', {
      value: this.kinesisStream.streamName,
      description: 'Name of the Kinesis Data Stream',
      exportName: `${this.stackName}-KinesisStreamName`
    });

    new cdk.CfnOutput(this, 'KinesisStreamArn', {
      value: this.kinesisStream.streamArn,
      description: 'ARN of the Kinesis Data Stream',
      exportName: `${this.stackName}-KinesisStreamArn`
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: this.processingFunction.functionName,
      description: 'Name of the Lambda processing function',
      exportName: `${this.stackName}-LambdaFunctionName`
    });

    new cdk.CfnOutput(this, 'S3BucketName', {
      value: this.analyticsBucket.bucketName,
      description: 'Name of the S3 analytics bucket',
      exportName: `${this.stackName}-S3BucketName`
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard',
      exportName: `${this.stackName}-DashboardUrl`
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: alertTopic.topicArn,
      description: 'ARN of the SNS topic for alerts',
      exportName: `${this.stackName}-SNSTopicArn`
    });
  }
}

/**
 * CDK Application for Real-Time Analytics
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const resourcePrefix = app.node.tryGetContext('resourcePrefix') || process.env.RESOURCE_PREFIX || 'analytics';
const shardCount = Number(app.node.tryGetContext('shardCount') || process.env.SHARD_COUNT || '3');
const retentionPeriodHours = Number(app.node.tryGetContext('retentionPeriodHours') || process.env.RETENTION_PERIOD_HOURS || '168');
const environmentName = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'dev';

// Create the stack
new RealTimeAnalyticsStack(app, 'RealTimeAnalyticsStack', {
  description: 'Real-Time Analytics with Amazon Kinesis Data Streams - CDK TypeScript',
  resourcePrefix,
  shardCount,
  retentionPeriodHours,
  environmentName,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  }
});

// Synthesize the stack
app.synth();