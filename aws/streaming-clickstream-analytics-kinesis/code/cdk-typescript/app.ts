#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as kinesis from 'aws-cdk-lib/aws-kinesis';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as eventsources from 'aws-cdk-lib/aws-lambda-event-sources';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Stack for Real-time Clickstream Analytics using Kinesis Data Streams and Lambda
 * 
 * This stack creates a complete real-time analytics pipeline that processes
 * clickstream events through Kinesis Data Streams, processes them with Lambda
 * functions, and stores results in DynamoDB for real-time dashboards.
 */
export class ClickstreamAnalyticsStack extends cdk.Stack {
  // Stack properties for external reference
  public readonly kinesisStream: kinesis.Stream;
  public readonly eventProcessorFunction: lambda.Function;
  public readonly anomalyDetectorFunction: lambda.Function;
  public readonly archiveBucket: s3.Bucket;
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const randomSuffix = Math.random().toString(36).substring(2, 8);

    // Create S3 bucket for raw data archiving
    // Uses lifecycle configuration to manage costs and compliance requirements
    this.archiveBucket = new s3.Bucket(this, 'ClickstreamArchiveBucket', {
      bucketName: `clickstream-archive-${randomSuffix}`,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'TransitionToIA',
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
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes only
      autoDeleteObjects: true // For demo purposes only
    });

    // Create Kinesis Data Stream for real-time event ingestion
    // Multiple shards provide parallel processing and higher throughput
    this.kinesisStream = new kinesis.Stream(this, 'ClickstreamDataStream', {
      streamName: `clickstream-events-${randomSuffix}`,
      shardCount: 2, // Supports 2,000 records/second write capacity
      retentionPeriod: cdk.Duration.days(1), // Balances cost and replay capability
      streamModeDetails: kinesis.StreamModeDetails.provisioned(),
      encryption: kinesis.StreamEncryption.MANAGED
    });

    // Create DynamoDB tables for real-time metrics storage
    // Table design optimized for query patterns and cost efficiency
    
    // Page metrics table - partitioned by URL for load distribution
    const pageMetricsTable = new dynamodb.Table(this, 'PageMetricsTable', {
      tableName: `clickstream-${randomSuffix}-page-metrics`,
      partitionKey: { name: 'page_url', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'timestamp_hour', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY // For demo purposes only
    });

    // Session metrics table - fast session lookups for anomaly detection
    const sessionMetricsTable = new dynamodb.Table(this, 'SessionMetricsTable', {
      tableName: `clickstream-${randomSuffix}-session-metrics`,
      partitionKey: { name: 'session_id', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY // For demo purposes only
    });

    // Real-time counters table - time-series aggregation with TTL
    const countersTable = new dynamodb.Table(this, 'CountersTable', {
      tableName: `clickstream-${randomSuffix}-counters`,
      partitionKey: { name: 'metric_name', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'time_window', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      timeToLiveAttribute: 'ttl', // Automatic cleanup to control costs
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY // For demo purposes only
    });

    // Create IAM role for Lambda functions with least privilege principles
    const lambdaRole = new iam.Role(this, 'ClickstreamProcessorRole', {
      roleName: `ClickstreamProcessorRole-${randomSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        ClickstreamProcessorPolicy: new iam.PolicyDocument({
          statements: [
            // Kinesis permissions for stream processing
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
            // DynamoDB permissions for metrics storage
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:PutItem',
                'dynamodb:UpdateItem',
                'dynamodb:GetItem',
                'dynamodb:Query'
              ],
              resources: [
                pageMetricsTable.tableArn,
                sessionMetricsTable.tableArn,
                countersTable.tableArn
              ]
            }),
            // S3 permissions for data archival
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:PutObject'],
              resources: [this.archiveBucket.arnForObjects('*')]
            }),
            // CloudWatch permissions for custom metrics
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['cloudwatch:PutMetricData'],
              resources: ['*'],
              conditions: {
                StringEquals: {
                  'cloudwatch:namespace': 'Clickstream/Events'
                }
              }
            })
          ]
        })
      }
    });

    // Create main event processor Lambda function
    // Handles real-time aggregation, archival, and metric publishing
    this.eventProcessorFunction = new lambda.Function(this, 'EventProcessorFunction', {
      functionName: `clickstream-event-processor-${randomSuffix}`,
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code: lambda.Code.fromInline(`
        const AWS = require('aws-sdk');
        const dynamodb = new AWS.DynamoDB.DocumentClient();
        const s3 = new AWS.S3();
        const cloudwatch = new AWS.CloudWatch();
        
        const TABLE_PREFIX = process.env.TABLE_PREFIX;
        const BUCKET_NAME = process.env.BUCKET_NAME;
        
        exports.handler = async (event) => {
            console.log('Processing', event.Records.length, 'records');
            
            const promises = event.Records.map(async (record) => {
                try {
                    // Decode the Kinesis data
                    const payload = Buffer.from(record.kinesis.data, 'base64').toString('utf-8');
                    const clickEvent = JSON.parse(payload);
                    
                    // Process different event types concurrently
                    await Promise.all([
                        processPageView(clickEvent),
                        updateSessionMetrics(clickEvent),
                        updateRealTimeCounters(clickEvent),
                        archiveRawEvent(clickEvent),
                        publishMetrics(clickEvent)
                    ]);
                    
                } catch (error) {
                    console.error('Error processing record:', error);
                    throw error;
                }
            });
            
            await Promise.all(promises);
            return { statusCode: 200, body: 'Successfully processed events' };
        };
        
        async function processPageView(event) {
            if (event.event_type !== 'page_view') return;
            
            const hour = new Date(event.timestamp).toISOString().slice(0, 13);
            
            const params = {
                TableName: \`\${TABLE_PREFIX}-page-metrics\`,
                Key: {
                    page_url: event.page_url,
                    timestamp_hour: hour
                },
                UpdateExpression: 'ADD view_count :inc SET last_updated = :now',
                ExpressionAttributeValues: {
                    ':inc': 1,
                    ':now': Date.now()
                }
            };
            
            await dynamodb.update(params).promise();
        }
        
        async function updateSessionMetrics(event) {
            const params = {
                TableName: \`\${TABLE_PREFIX}-session-metrics\`,
                Key: { session_id: event.session_id },
                UpdateExpression: 'SET last_activity = :now, user_agent = :ua ADD event_count :inc',
                ExpressionAttributeValues: {
                    ':now': event.timestamp,
                    ':ua': event.user_agent || 'unknown',
                    ':inc': 1
                }
            };
            
            await dynamodb.update(params).promise();
        }
        
        async function updateRealTimeCounters(event) {
            const minute = new Date(event.timestamp).toISOString().slice(0, 16);
            
            const params = {
                TableName: \`\${TABLE_PREFIX}-counters\`,
                Key: {
                    metric_name: \`events_per_minute_\${event.event_type}\`,
                    time_window: minute
                },
                UpdateExpression: 'ADD event_count :inc SET ttl = :ttl',
                ExpressionAttributeValues: {
                    ':inc': 1,
                    ':ttl': Math.floor(Date.now() / 1000) + (24 * 60 * 60) // 24 hour TTL
                }
            };
            
            await dynamodb.update(params).promise();
        }
        
        async function archiveRawEvent(event) {
            const date = new Date(event.timestamp);
            const key = \`year=\${date.getFullYear()}/month=\${date.getMonth() + 1}/day=\${date.getDate()}/hour=\${date.getHours()}/\${event.session_id}-\${Date.now()}.json\`;
            
            const params = {
                Bucket: BUCKET_NAME,
                Key: key,
                Body: JSON.stringify(event),
                ContentType: 'application/json'
            };
            
            await s3.putObject(params).promise();
        }
        
        async function publishMetrics(event) {
            const params = {
                Namespace: 'Clickstream/Events',
                MetricData: [
                    {
                        MetricName: 'EventsProcessed',
                        Value: 1,
                        Unit: 'Count',
                        Dimensions: [
                            {
                                Name: 'EventType',
                                Value: event.event_type
                            }
                        ]
                    }
                ]
            };
            
            await cloudwatch.putMetricData(params).promise();
        }
      `),
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      role: lambdaRole,
      environment: {
        TABLE_PREFIX: `clickstream-${randomSuffix}`,
        BUCKET_NAME: this.archiveBucket.bucketName
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      description: 'Processes clickstream events for real-time analytics and archival'
    });

    // Create anomaly detection Lambda function
    // Implements real-time pattern recognition for fraud detection
    this.anomalyDetectorFunction = new lambda.Function(this, 'AnomalyDetectorFunction', {
      functionName: `clickstream-anomaly-detector-${randomSuffix}`,
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code: lambda.Code.fromInline(`
        const AWS = require('aws-sdk');
        const dynamodb = new AWS.DynamoDB.DocumentClient();
        
        const TABLE_PREFIX = process.env.TABLE_PREFIX;
        
        exports.handler = async (event) => {
            console.log('Checking for anomalies in', event.Records.length, 'records');
            
            for (const record of event.Records) {
                try {
                    const payload = Buffer.from(record.kinesis.data, 'base64').toString('utf-8');
                    const clickEvent = JSON.parse(payload);
                    
                    await checkForAnomalies(clickEvent);
                    
                } catch (error) {
                    console.error('Error processing record for anomaly detection:', error);
                }
            }
            
            return { statusCode: 200 };
        };
        
        async function checkForAnomalies(event) {
            // Check for suspicious patterns
            const checks = await Promise.all([
                checkHighFrequencyClicks(event),
                checkSuspiciousUserAgent(event),
                checkUnusualPageSequence(event)
            ]);
            
            const anomalies = checks.filter(check => check.isAnomaly);
            
            if (anomalies.length > 0) {
                console.log('Anomalies detected:', anomalies);
                // In production, this would send alerts via SNS
            }
        }
        
        async function checkHighFrequencyClicks(event) {
            const minute = new Date(event.timestamp).toISOString().slice(0, 16);
            
            const params = {
                TableName: \`\${TABLE_PREFIX}-counters\`,
                Key: {
                    metric_name: \`session_events_\${event.session_id}\`,
                    time_window: minute
                }
            };
            
            try {
                const result = await dynamodb.get(params).promise();
                const eventCount = result.Item ? result.Item.event_count : 0;
                
                // Flag if more than 50 events per minute from same session
                return {
                    isAnomaly: eventCount > 50,
                    type: 'high_frequency_clicks',
                    details: \`\${eventCount} events in one minute\`
                };
            } catch (error) {
                console.error('Error checking high frequency clicks:', error);
                return { isAnomaly: false };
            }
        }
        
        async function checkSuspiciousUserAgent(event) {
            const suspiciousPatterns = ['bot', 'crawler', 'spider', 'scraper'];
            const userAgent = (event.user_agent || '').toLowerCase();
            
            const isSuspicious = suspiciousPatterns.some(pattern => 
                userAgent.includes(pattern)
            );
            
            return {
                isAnomaly: isSuspicious,
                type: 'suspicious_user_agent',
                details: event.user_agent
            };
        }
        
        async function checkUnusualPageSequence(event) {
            // Simple check for direct access to checkout without viewing products
            if (event.page_url && event.page_url.includes('/checkout')) {
                const params = {
                    TableName: \`\${TABLE_PREFIX}-session-metrics\`,
                    Key: { session_id: event.session_id }
                };
                
                try {
                    const result = await dynamodb.get(params).promise();
                    const eventCount = result.Item ? result.Item.event_count : 0;
                    
                    // Flag if going to checkout with very few page views
                    return {
                        isAnomaly: eventCount < 3,
                        type: 'unusual_page_sequence',
                        details: \`Direct checkout access with only \${eventCount} page views\`
                    };
                } catch (error) {
                    console.error('Error checking page sequence:', error);
                    return { isAnomaly: false };
                }
            }
            
            return { isAnomaly: false };
        }
      `),
      timeout: cdk.Duration.seconds(30),
      memorySize: 128,
      role: lambdaRole,
      environment: {
        TABLE_PREFIX: `clickstream-${randomSuffix}`
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      description: 'Detects anomalies and suspicious patterns in clickstream data'
    });

    // Create event source mappings for Lambda functions
    // Connects Kinesis stream to Lambda for automatic processing
    
    // Main event processor - optimized for throughput with larger batches
    this.eventProcessorFunction.addEventSource(
      new eventsources.KinesisEventSource(this.kinesisStream, {
        batchSize: 100, // Process up to 100 records per invocation
        maxBatchingWindow: cdk.Duration.seconds(5), // Max 5 second wait for batching
        startingPosition: lambda.StartingPosition.LATEST,
        retryAttempts: 3,
        maxRecordAge: cdk.Duration.hours(1),
        parallelizationFactor: 1
      })
    );

    // Anomaly detector - smaller batches for faster detection
    this.anomalyDetectorFunction.addEventSource(
      new eventsources.KinesisEventSource(this.kinesisStream, {
        batchSize: 50, // Smaller batches for faster anomaly detection
        maxBatchingWindow: cdk.Duration.seconds(10), // Slightly longer batching window
        startingPosition: lambda.StartingPosition.LATEST,
        retryAttempts: 2,
        maxRecordAge: cdk.Duration.minutes(30),
        parallelizationFactor: 1
      })
    );

    // Create CloudWatch Dashboard for monitoring
    // Provides real-time visibility into pipeline performance
    this.dashboard = new cloudwatch.Dashboard(this, 'ClickstreamDashboard', {
      dashboardName: `Clickstream-Analytics-${randomSuffix}`,
      widgets: [
        [
          // Events processed by type
          new cloudwatch.GraphWidget({
            title: 'Events Processed by Type',
            left: [
              new cloudwatch.Metric({
                namespace: 'Clickstream/Events',
                metricName: 'EventsProcessed',
                dimensionsMap: {
                  EventType: 'page_view'
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5)
              }),
              new cloudwatch.Metric({
                namespace: 'Clickstream/Events',
                metricName: 'EventsProcessed',
                dimensionsMap: {
                  EventType: 'click'
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5)
              })
            ],
            width: 12,
            height: 6
          }),

          // Lambda performance metrics
          new cloudwatch.GraphWidget({
            title: 'Lambda Performance',
            left: [
              this.eventProcessorFunction.metricDuration(),
              this.eventProcessorFunction.metricErrors(),
              this.eventProcessorFunction.metricInvocations()
            ],
            width: 12,
            height: 6
          })
        ],
        [
          // Kinesis stream throughput
          new cloudwatch.GraphWidget({
            title: 'Kinesis Stream Throughput',
            left: [
              this.kinesisStream.metricIncomingRecords(),
              this.kinesisStream.metricOutgoingRecords()
            ],
            width: 24,
            height: 6
          })
        ]
      ]
    });

    // Stack outputs for external integration and verification
    new cdk.CfnOutput(this, 'KinesisStreamName', {
      value: this.kinesisStream.streamName,
      description: 'Name of the Kinesis Data Stream for clickstream events',
      exportName: `${this.stackName}-StreamName`
    });

    new cdk.CfnOutput(this, 'KinesisStreamArn', {
      value: this.kinesisStream.streamArn,
      description: 'ARN of the Kinesis Data Stream',
      exportName: `${this.stackName}-StreamArn`
    });

    new cdk.CfnOutput(this, 'ArchiveBucketName', {
      value: this.archiveBucket.bucketName,
      description: 'S3 bucket for raw data archival',
      exportName: `${this.stackName}-ArchiveBucket`
    });

    new cdk.CfnOutput(this, 'EventProcessorFunctionName', {
      value: this.eventProcessorFunction.functionName,
      description: 'Name of the event processor Lambda function',
      exportName: `${this.stackName}-EventProcessor`
    });

    new cdk.CfnOutput(this, 'AnomalyDetectorFunctionName', {
      value: this.anomalyDetectorFunction.functionName,
      description: 'Name of the anomaly detector Lambda function',
      exportName: `${this.stackName}-AnomalyDetector`
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL for monitoring',
      exportName: `${this.stackName}-DashboardURL`
    });

    new cdk.CfnOutput(this, 'PageMetricsTableName', {
      value: pageMetricsTable.tableName,
      description: 'DynamoDB table for page view metrics',
      exportName: `${this.stackName}-PageMetricsTable`
    });

    new cdk.CfnOutput(this, 'SessionMetricsTableName', {
      value: sessionMetricsTable.tableName,
      description: 'DynamoDB table for session metrics',
      exportName: `${this.stackName}-SessionMetricsTable`
    });

    new cdk.CfnOutput(this, 'CountersTableName', {
      value: countersTable.tableName,
      description: 'DynamoDB table for real-time counters',
      exportName: `${this.stackName}-CountersTable`
    });

    // Add tags for resource management and cost tracking
    cdk.Tags.of(this).add('Project', 'ClickstreamAnalytics');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('Owner', 'DataEngineering');
    cdk.Tags.of(this).add('CostCenter', 'Analytics');
  }
}

// CDK App initialization
const app = new cdk.App();

// Create the main stack with appropriate configuration
new ClickstreamAnalyticsStack(app, 'ClickstreamAnalyticsStack', {
  description: 'Real-time clickstream analytics pipeline using Kinesis Data Streams and Lambda',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  },
  tags: {
    Application: 'ClickstreamAnalytics',
    CreatedBy: 'CDK'
  }
});

// Synthesize the app
app.synth();