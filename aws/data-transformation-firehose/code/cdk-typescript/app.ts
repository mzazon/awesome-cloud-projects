#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as kinesisfirehose from 'aws-cdk-lib/aws-kinesisfirehose';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as path from 'path';

/**
 * Properties for the Real-Time Data Transformation Stack
 */
export interface RealTimeDataTransformationStackProps extends cdk.StackProps {
  /**
   * Minimum log level to process in the transformation Lambda
   * @default 'INFO'
   */
  readonly minLogLevel?: string;

  /**
   * Buffer size in MB for Firehose delivery to S3
   * @default 5
   */
  readonly bufferSizeMB?: number;

  /**
   * Buffer interval in seconds for Firehose delivery to S3
   * @default 60
   */
  readonly bufferIntervalSeconds?: number;

  /**
   * Email address for CloudWatch alarm notifications
   * @default undefined
   */
  readonly notificationEmail?: string;

  /**
   * Whether to enable detailed CloudWatch monitoring
   * @default true
   */
  readonly enableDetailedMonitoring?: boolean;
}

/**
 * CDK Stack for Real-Time Data Transformation with Kinesis Data Firehose
 * 
 * This stack creates:
 * - S3 buckets for raw data backup, processed data, and error handling
 * - Lambda function for data transformation with configurable filtering
 * - Kinesis Data Firehose delivery stream with transformation processing
 * - CloudWatch monitoring and alerting infrastructure
 * - SNS topic for notifications
 * 
 * Architecture:
 * Data Sources → Kinesis Data Firehose → Lambda Transform → S3 (Processed)
 *                                    ↓
 *                               S3 (Raw Backup)
 *                                    ↓
 *                               S3 (Errors/DLQ)
 */
export class RealTimeDataTransformationStack extends cdk.Stack {
  /**
   * The Kinesis Data Firehose delivery stream
   */
  public readonly deliveryStream: kinesisfirehose.CfnDeliveryStream;

  /**
   * The Lambda function for data transformation
   */
  public readonly transformFunction: lambda.Function;

  /**
   * S3 bucket for processed data storage
   */
  public readonly processedDataBucket: s3.Bucket;

  /**
   * S3 bucket for raw data backup
   */
  public readonly rawDataBucket: s3.Bucket;

  /**
   * S3 bucket for error/failed data
   */
  public readonly errorDataBucket: s3.Bucket;

  /**
   * SNS topic for notifications
   */
  public readonly notificationTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: RealTimeDataTransformationStackProps = {}) {
    super(scope, id, props);

    // Extract configuration from props with defaults
    const minLogLevel = props.minLogLevel || 'INFO';
    const bufferSizeMB = props.bufferSizeMB || 5;
    const bufferIntervalSeconds = props.bufferIntervalSeconds || 60;
    const enableDetailedMonitoring = props.enableDetailedMonitoring !== false;

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = cdk.Names.uniqueId(this).toLowerCase().substring(0, 8);

    // Create S3 buckets for data storage with security best practices
    this.createS3Buckets(uniqueSuffix);

    // Create Lambda function for data transformation
    this.createTransformFunction(minLogLevel, uniqueSuffix);

    // Create Kinesis Data Firehose delivery stream
    this.createFirehoseDeliveryStream(bufferSizeMB, bufferIntervalSeconds, uniqueSuffix);

    // Create monitoring and alerting infrastructure
    this.createMonitoringInfrastructure(props.notificationEmail, enableDetailedMonitoring);

    // Add stack outputs for easy access to resource information
    this.addStackOutputs();
  }

  /**
   * Create S3 buckets for raw data, processed data, and error handling
   * All buckets are configured with encryption, versioning, and lifecycle policies
   */
  private createS3Buckets(uniqueSuffix: string): void {
    // Raw data backup bucket - stores original data before transformation
    this.rawDataBucket = new s3.Bucket(this, 'RawDataBucket', {
      bucketName: `firehose-raw-data-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
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
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes - use RETAIN in production
    });

    // Processed data bucket - stores transformed data for analytics
    this.processedDataBucket = new s3.Bucket(this, 'ProcessedDataBucket', {
      bucketName: `firehose-processed-data-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
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
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes - use RETAIN in production
    });

    // Error data bucket - stores failed/rejected records for debugging
    this.errorDataBucket = new s3.Bucket(this, 'ErrorDataBucket', {
      bucketName: `firehose-error-data-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
        {
          id: 'RetainErrorsLonger',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(7), // Errors kept accessible longer
            },
          ],
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes - use RETAIN in production
    });

    // Add resource tags for cost tracking and organization
    const buckets = [this.rawDataBucket, this.processedDataBucket, this.errorDataBucket];
    buckets.forEach(bucket => {
      cdk.Tags.of(bucket).add('Project', 'RealTimeDataTransformation');
      cdk.Tags.of(bucket).add('Environment', 'Development');
      cdk.Tags.of(bucket).add('Owner', 'DataEngineering');
    });
  }

  /**
   * Create Lambda function for data transformation with comprehensive error handling
   */
  private createTransformFunction(minLogLevel: string, uniqueSuffix: string): void {
    // Create the Lambda function with inline code for the transformation logic
    this.transformFunction = new lambda.Function(this, 'TransformFunction', {
      functionName: `firehose-transform-${uniqueSuffix}`,
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      description: 'Transform function for Kinesis Data Firehose - filters, enriches, and formats log data',
      environment: {
        MIN_LOG_LEVEL: minLogLevel,
        ADD_PROCESSING_TIMESTAMP: 'true',
        FIELDS_TO_REDACT: 'password,creditCard,ssn',
      },
      logRetention: logs.RetentionDays.TWO_WEEKS,
      code: lambda.Code.fromInline(`
/**
 * Kinesis Firehose Data Transformation Lambda
 * - Processes incoming log records in batches
 * - Filters out records that don't match criteria
 * - Transforms and enriches valid records
 * - Returns both processed records and failed records
 */

// Configuration options from environment variables
const config = {
    // Minimum log level to process (logs below this level will be filtered out)
    minLogLevel: process.env.MIN_LOG_LEVEL || 'INFO',
    
    // Whether to include timestamp in transformed data
    addProcessingTimestamp: process.env.ADD_PROCESSING_TIMESTAMP === 'true',
    
    // Fields to remove from logs for privacy/compliance (PII, etc.)
    fieldsToRedact: (process.env.FIELDS_TO_REDACT || '').split(',').filter(f => f.trim())
};

/**
 * Event structure expected in records:
 * {
 *   "timestamp": "2023-04-10T12:34:56Z",
 *   "level": "INFO|DEBUG|WARN|ERROR",
 *   "service": "service-name",
 *   "message": "Log message",
 *   // Additional fields...
 * }
 */
exports.handler = async (event, context) => {
    console.log('Received event with', event.records.length, 'records');
    console.log('Configuration:', JSON.stringify(config, null, 2));
    
    const output = {
        records: []
    };
    
    let processedCount = 0;
    let droppedCount = 0;
    let failedCount = 0;
    
    // Process each record in the batch
    for (const record of event.records) {
        try {
            // Decode and parse the record data
            const buffer = Buffer.from(record.data, 'base64');
            const decodedData = buffer.toString('utf8');
            
            // Try to parse as JSON, fail gracefully if not valid JSON
            let parsedData;
            try {
                parsedData = JSON.parse(decodedData);
            } catch (e) {
                console.error('Invalid JSON in record:', record.recordId, 'Data:', decodedData);
                
                // Mark record as processing failed
                output.records.push({
                    recordId: record.recordId,
                    result: 'ProcessingFailed',
                    data: record.data
                });
                failedCount++;
                continue;
            }
            
            // Apply filtering logic - skip records with log level below minimum
            const logLevels = ['DEBUG', 'INFO', 'WARN', 'ERROR'];
            const currentLevelIndex = logLevels.indexOf(parsedData.level);
            const minLevelIndex = logLevels.indexOf(config.minLogLevel);
            
            if (parsedData.level && currentLevelIndex >= 0 && currentLevelIndex < minLevelIndex) {
                console.log('Filtering out record with level', parsedData.level, 'below minimum', config.minLogLevel);
                
                // Mark record as dropped
                output.records.push({
                    recordId: record.recordId,
                    result: 'Dropped',
                    data: record.data
                });
                droppedCount++;
                continue;
            }
            
            // Apply transformations
            
            // Add processing metadata
            if (config.addProcessingTimestamp) {
                parsedData.processedAt = new Date().toISOString();
            }
            
            // Add AWS request ID for traceability
            parsedData.lambdaRequestId = context.awsRequestId;
            
            // Add function version for debugging
            parsedData.functionVersion = context.functionVersion;
            
            // Redact any sensitive fields
            for (const field of config.fieldsToRedact) {
                if (parsedData[field]) {
                    parsedData[field] = '********';
                }
            }
            
            // Add record size for monitoring
            parsedData.recordSize = Buffer.byteLength(decodedData, 'utf8');
            
            // Convert transformed data back to string and encode as base64
            const transformedData = JSON.stringify(parsedData) + '\\n';
            const encodedData = Buffer.from(transformedData).toString('base64');
            
            // Add transformed record to output
            output.records.push({
                recordId: record.recordId,
                result: 'Ok',
                data: encodedData
            });
            
            processedCount++;
            
        } catch (error) {
            console.error('Error processing record:', record.recordId, 'Error:', error);
            
            // Mark record as processing failed
            output.records.push({
                recordId: record.recordId,
                result: 'ProcessingFailed',
                data: record.data
            });
            failedCount++;
        }
    }
    
    // Log processing summary
    console.log('Processing complete:', {
        total: event.records.length,
        processed: processedCount,
        dropped: droppedCount,
        failed: failedCount
    });
    
    return output;
};
      `),
    });

    // Grant the Lambda function permissions to write to CloudWatch Logs
    this.transformFunction.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'logs:CreateLogGroup',
          'logs:CreateLogStream',
          'logs:PutLogEvents',
        ],
        resources: ['*'],
      })
    );

    // Add tags for resource organization
    cdk.Tags.of(this.transformFunction).add('Project', 'RealTimeDataTransformation');
    cdk.Tags.of(this.transformFunction).add('Environment', 'Development');
    cdk.Tags.of(this.transformFunction).add('Owner', 'DataEngineering');
  }

  /**
   * Create Kinesis Data Firehose delivery stream with transformation processing
   */
  private createFirehoseDeliveryStream(
    bufferSizeMB: number,
    bufferIntervalSeconds: number,
    uniqueSuffix: string
  ): void {
    // Create IAM role for Firehose with least privilege permissions
    const firehoseRole = new iam.Role(this, 'FirehoseRole', {
      roleName: `kinesis-firehose-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('firehose.amazonaws.com'),
      description: 'IAM role for Kinesis Data Firehose delivery stream',
    });

    // Grant Firehose permissions to write to S3 buckets
    const s3PolicyStatement = new iam.PolicyStatement({
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
        this.rawDataBucket.bucketArn,
        this.rawDataBucket.bucketArn + '/*',
        this.processedDataBucket.bucketArn,
        this.processedDataBucket.bucketArn + '/*',
        this.errorDataBucket.bucketArn,
        this.errorDataBucket.bucketArn + '/*',
      ],
    });

    // Grant Firehose permissions to invoke Lambda function
    const lambdaPolicyStatement = new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'lambda:InvokeFunction',
        'lambda:GetFunctionConfiguration',
      ],
      resources: [this.transformFunction.functionArn],
    });

    // Grant Firehose permissions to write to CloudWatch Logs
    const logsPolicyStatement = new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'logs:PutLogEvents',
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
      ],
      resources: ['*'],
    });

    // Add all policy statements to the role
    firehoseRole.addToPolicy(s3PolicyStatement);
    firehoseRole.addToPolicy(lambdaPolicyStatement);
    firehoseRole.addToPolicy(logsPolicyStatement);

    // Create CloudWatch Log Group for Firehose
    const firehoseLogGroup = new logs.LogGroup(this, 'FirehoseLogGroup', {
      logGroupName: `/aws/kinesisfirehose/log-processing-stream-${uniqueSuffix}`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create the Firehose delivery stream
    this.deliveryStream = new kinesisfirehose.CfnDeliveryStream(this, 'DeliveryStream', {
      deliveryStreamName: `log-processing-stream-${uniqueSuffix}`,
      deliveryStreamType: 'DirectPut',
      extendedS3DestinationConfiguration: {
        roleArn: firehoseRole.roleArn,
        bucketArn: this.processedDataBucket.bucketArn,
        
        // Intelligent partitioning for optimal query performance
        prefix: 'logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/',
        errorOutputPrefix: 'errors/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/',
        
        // Buffer configuration for cost/latency optimization
        bufferingHints: {
          sizeInMBs: bufferSizeMB,
          intervalInSeconds: bufferIntervalSeconds,
        },
        
        // Compression to reduce storage costs
        compressionFormat: 'GZIP',
        
        // Enable backup of raw data before transformation
        s3BackupMode: 'Enabled',
        s3BackupConfiguration: {
          roleArn: firehoseRole.roleArn,
          bucketArn: this.rawDataBucket.bucketArn,
          prefix: 'raw/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/',
          bufferingHints: {
            sizeInMBs: bufferSizeMB,
            intervalInSeconds: bufferIntervalSeconds,
          },
          compressionFormat: 'GZIP',
        },
        
        // Data transformation configuration
        processingConfiguration: {
          enabled: true,
          processors: [
            {
              type: 'Lambda',
              parameters: [
                {
                  parameterName: 'LambdaArn',
                  parameterValue: this.transformFunction.functionArn,
                },
                {
                  parameterName: 'BufferSizeInMBs',
                  parameterValue: Math.min(bufferSizeMB, 3).toString(), // Lambda buffer should be <= main buffer
                },
                {
                  parameterName: 'BufferIntervalInSeconds',
                  parameterValue: bufferIntervalSeconds.toString(),
                },
              ],
            },
          ],
        },
        
        // CloudWatch logging configuration
        cloudWatchLoggingOptions: {
          enabled: true,
          logGroupName: firehoseLogGroup.logGroupName,
          logStreamName: 'S3Delivery',
        },
      },
    });

    // Add dependency to ensure role is created before delivery stream
    this.deliveryStream.node.addDependency(firehoseRole);
    this.deliveryStream.node.addDependency(firehoseLogGroup);

    // Add tags for resource organization
    cdk.Tags.of(this.deliveryStream).add('Project', 'RealTimeDataTransformation');
    cdk.Tags.of(this.deliveryStream).add('Environment', 'Development');
    cdk.Tags.of(this.deliveryStream).add('Owner', 'DataEngineering');
  }

  /**
   * Create monitoring and alerting infrastructure
   */
  private createMonitoringInfrastructure(notificationEmail?: string, enableDetailedMonitoring = true): void {
    // Create SNS topic for alarm notifications
    this.notificationTopic = new sns.Topic(this, 'NotificationTopic', {
      topicName: `firehose-alarms-${cdk.Names.uniqueId(this).toLowerCase().substring(0, 8)}`,
      displayName: 'Kinesis Firehose Alerts',
    });

    // Subscribe email to SNS topic if provided
    if (notificationEmail) {
      new sns.Subscription(this, 'EmailSubscription', {
        topic: this.notificationTopic,
        protocol: sns.SubscriptionProtocol.EMAIL,
        endpoint: notificationEmail,
      });
    }

    // Create CloudWatch alarm for delivery failures
    const deliveryFailureAlarm = new cloudwatch.Alarm(this, 'DeliveryFailureAlarm', {
      alarmName: `FirehoseDeliveryFailure-${this.deliveryStream.deliveryStreamName}`,
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Firehose',
        metricName: 'DeliveryToS3.DataFreshness',
        dimensionsMap: {
          DeliveryStreamName: this.deliveryStream.deliveryStreamName!,
        },
        statistic: 'Maximum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 900, // 15 minutes in seconds
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      alarmDescription: 'Alarm when Firehose records are not delivered to S3 within 15 minutes',
    });

    // Add SNS notification action to the alarm
    deliveryFailureAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.notificationTopic));
    deliveryFailureAlarm.addOkAction(new cloudwatchActions.SnsAction(this.notificationTopic));

    if (enableDetailedMonitoring) {
      // Create alarm for transformation errors
      const transformationErrorAlarm = new cloudwatch.Alarm(this, 'TransformationErrorAlarm', {
        alarmName: `FirehoseTransformationErrors-${this.deliveryStream.deliveryStreamName}`,
        metric: new cloudwatch.Metric({
          namespace: 'AWS/Firehose',
          metricName: 'DeliveryToS3.DataTransformation.Records',
          dimensionsMap: {
            DeliveryStreamName: this.deliveryStream.deliveryStreamName!,
          },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
        threshold: 10, // Alert if more than 10 transformation errors in 5 minutes
        evaluationPeriods: 1,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        alarmDescription: 'Alarm when Firehose transformation errors exceed threshold',
      });

      transformationErrorAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.notificationTopic));

      // Create alarm for Lambda function errors
      const lambdaErrorAlarm = new cloudwatch.Alarm(this, 'LambdaErrorAlarm', {
        alarmName: `LambdaTransformationErrors-${this.transformFunction.functionName}`,
        metric: this.transformFunction.metricErrors({
          period: cdk.Duration.minutes(5),
        }),
        threshold: 5, // Alert if more than 5 Lambda errors in 5 minutes
        evaluationPeriods: 1,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        alarmDescription: 'Alarm when Lambda transformation function errors exceed threshold',
      });

      lambdaErrorAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.notificationTopic));

      // Create alarm for Lambda function duration
      const lambdaDurationAlarm = new cloudwatch.Alarm(this, 'LambdaDurationAlarm', {
        alarmName: `LambdaTransformationDuration-${this.transformFunction.functionName}`,
        metric: this.transformFunction.metricDuration({
          period: cdk.Duration.minutes(5),
        }),
        threshold: 30000, // Alert if average duration exceeds 30 seconds
        evaluationPeriods: 2,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        alarmDescription: 'Alarm when Lambda transformation function duration is too high',
      });

      lambdaDurationAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.notificationTopic));
    }

    // Add tags for resource organization
    cdk.Tags.of(this.notificationTopic).add('Project', 'RealTimeDataTransformation');
    cdk.Tags.of(this.notificationTopic).add('Environment', 'Development');
    cdk.Tags.of(this.notificationTopic).add('Owner', 'DataEngineering');
  }

  /**
   * Add stack outputs for easy access to resource information
   */
  private addStackOutputs(): void {
    // Firehose delivery stream information
    new cdk.CfnOutput(this, 'DeliveryStreamName', {
      description: 'Name of the Kinesis Data Firehose delivery stream',
      value: this.deliveryStream.deliveryStreamName || 'N/A',
      exportName: `${this.stackName}-DeliveryStreamName`,
    });

    new cdk.CfnOutput(this, 'DeliveryStreamArn', {
      description: 'ARN of the Kinesis Data Firehose delivery stream',
      value: this.deliveryStream.attrArn,
      exportName: `${this.stackName}-DeliveryStreamArn`,
    });

    // Lambda function information
    new cdk.CfnOutput(this, 'TransformFunctionName', {
      description: 'Name of the Lambda transformation function',
      value: this.transformFunction.functionName,
      exportName: `${this.stackName}-TransformFunctionName`,
    });

    new cdk.CfnOutput(this, 'TransformFunctionArn', {
      description: 'ARN of the Lambda transformation function',
      value: this.transformFunction.functionArn,
      exportName: `${this.stackName}-TransformFunctionArn`,
    });

    // S3 bucket information
    new cdk.CfnOutput(this, 'ProcessedDataBucketName', {
      description: 'Name of the S3 bucket for processed data',
      value: this.processedDataBucket.bucketName,
      exportName: `${this.stackName}-ProcessedDataBucketName`,
    });

    new cdk.CfnOutput(this, 'RawDataBucketName', {
      description: 'Name of the S3 bucket for raw data backup',
      value: this.rawDataBucket.bucketName,
      exportName: `${this.stackName}-RawDataBucketName`,
    });

    new cdk.CfnOutput(this, 'ErrorDataBucketName', {
      description: 'Name of the S3 bucket for error data',
      value: this.errorDataBucket.bucketName,
      exportName: `${this.stackName}-ErrorDataBucketName`,
    });

    // SNS topic information
    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      description: 'ARN of the SNS topic for notifications',
      value: this.notificationTopic.topicArn,
      exportName: `${this.stackName}-NotificationTopicArn`,
    });

    // Instructions for testing
    new cdk.CfnOutput(this, 'TestingInstructions', {
      description: 'Instructions for testing the data pipeline',
      value: `To test: aws firehose put-record --delivery-stream-name ${this.deliveryStream.deliveryStreamName} --record Data="$(echo '{"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","level":"INFO","service":"test-service","message":"Test message"}' | base64)"`,
    });

    // Monitoring dashboard URL
    new cdk.CfnOutput(this, 'MonitoringDashboard', {
      description: 'URL to CloudWatch console for monitoring',
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:`,
    });
  }
}

/**
 * CDK Application
 */
const app = new cdk.App();

// Create the stack with default configuration
const stack = new RealTimeDataTransformationStack(app, 'RealTimeDataTransformationStack', {
  description: 'Real-time data transformation pipeline using Kinesis Data Firehose and Lambda',
  
  // Configuration options - these can be overridden via CDK context
  minLogLevel: app.node.tryGetContext('minLogLevel') || 'INFO',
  bufferSizeMB: app.node.tryGetContext('bufferSizeMB') || 5,
  bufferIntervalSeconds: app.node.tryGetContext('bufferIntervalSeconds') || 60,
  notificationEmail: app.node.tryGetContext('notificationEmail'),
  enableDetailedMonitoring: app.node.tryGetContext('enableDetailedMonitoring') !== 'false',
  
  // Standard stack configuration
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Stack-level tags
  tags: {
    Project: 'RealTimeDataTransformation',
    Environment: 'Development',
    Owner: 'DataEngineering',
    CostCenter: 'Analytics',
  },
});

// Add metadata to the stack
stack.templateOptions.description = 'CDK Stack for Real-Time Data Transformation with Kinesis Data Firehose - v1.0';
stack.templateOptions.metadata = {
  'AWS::CloudFormation::Designer': {
    'version': '1.0',
    'description': 'Real-time data transformation pipeline using Kinesis Data Firehose and Lambda',
  },
};

// Synthesize the application
app.synth();