import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as lambdaEventSources from 'aws-cdk-lib/aws-lambda-event-sources';
import { Construct } from 'constructs';

export interface EventDrivenDataProcessingStackProps extends cdk.StackProps {
  resourceSuffix: string;
  notificationEmail: string;
  enableDetailedMonitoring: boolean;
}

export class EventDrivenDataProcessingStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: EventDrivenDataProcessingStackProps) {
    super(scope, id, props);

    const { resourceSuffix, notificationEmail, enableDetailedMonitoring } = props;

    // Create S3 bucket for data processing
    const dataBucket = new s3.Bucket(this, 'DataBucket', {
      bucketName: `data-processing-${resourceSuffix}`,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
        {
          id: 'TransitionToIA',
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
          ],
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create SNS topic for error notifications
    const alertTopic = new sns.Topic(this, 'AlertTopic', {
      topicName: `data-processing-alerts-${resourceSuffix}`,
      displayName: 'Data Processing Alerts',
    });

    // Subscribe email to SNS topic
    alertTopic.addSubscription(
      new subscriptions.EmailSubscription(notificationEmail)
    );

    // Create Dead Letter Queue for failed processing
    const deadLetterQueue = new sqs.Queue(this, 'DeadLetterQueue', {
      queueName: `data-processing-dlq-${resourceSuffix}`,
      visibilityTimeout: cdk.Duration.seconds(300),
      retentionPeriod: cdk.Duration.days(14),
    });

    // Create IAM role for Lambda functions
    const lambdaRole = new iam.Role(this, 'LambdaRole', {
      roleName: `data-processing-lambda-role-${resourceSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        DataProcessingPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
              ],
              resources: [dataBucket.arnForObjects('*')],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'sqs:SendMessage',
                'sqs:GetQueueAttributes',
              ],
              resources: [deadLetterQueue.queueArn],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sns:Publish'],
              resources: [alertTopic.topicArn],
            }),
          ],
        }),
      },
    });

    // Create data processing Lambda function
    const dataProcessorFunction = new lambda.Function(this, 'DataProcessorFunction', {
      functionName: `data-processor-${resourceSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'data_processor.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import urllib.parse
from datetime import datetime

s3 = boto3.client('s3')
sqs = boto3.client('sqs')

def lambda_handler(event, context):
    try:
        # Process each S3 event record
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = urllib.parse.unquote_plus(record['s3']['object']['key'])
            
            print(f"Processing object: {key} from bucket: {bucket}")
            
            # Get object metadata
            response = s3.head_object(Bucket=bucket, Key=key)
            file_size = response['ContentLength']
            
            # Example processing logic based on file type
            if key.endswith('.csv'):
                process_csv_file(bucket, key, file_size)
            elif key.endswith('.json'):
                process_json_file(bucket, key, file_size)
            else:
                print(f"Unsupported file type: {key}")
                continue
            
            # Create processing report
            create_processing_report(bucket, key, file_size)
            
        return {
            'statusCode': 200,
            'body': json.dumps('Successfully processed S3 events')
        }
        
    except Exception as e:
        print(f"Error processing S3 event: {str(e)}")
        # Send to DLQ for retry logic
        send_to_dlq(event, str(e))
        raise e

def process_csv_file(bucket, key, file_size):
    """Process CSV files - add your business logic here"""
    print(f"Processing CSV file: {key} (Size: {file_size} bytes)")
    # Add your CSV processing logic here
    
def process_json_file(bucket, key, file_size):
    """Process JSON files - add your business logic here"""
    print(f"Processing JSON file: {key} (Size: {file_size} bytes)")
    # Add your JSON processing logic here

def create_processing_report(bucket, key, file_size):
    """Create a processing report and store it in S3"""
    report_key = f"reports/{key}-report-{datetime.now().strftime('%Y%m%d%H%M%S')}.json"
    
    report = {
        'file_processed': key,
        'file_size': file_size,
        'processing_time': datetime.now().isoformat(),
        'status': 'completed'
    }
    
    s3.put_object(
        Bucket=bucket,
        Key=report_key,
        Body=json.dumps(report),
        ContentType='application/json'
    )
    
    print(f"Processing report created: {report_key}")

def send_to_dlq(event, error_message):
    """Send failed event to DLQ for retry"""
    import os
    dlq_url = os.environ.get('DLQ_URL')
    
    if dlq_url:
        message = {
            'original_event': event,
            'error_message': error_message,
            'timestamp': datetime.now().isoformat()
        }
        
        sqs.send_message(
            QueueUrl=dlq_url,
            MessageBody=json.dumps(message)
        )
      `),
      role: lambdaRole,
      timeout: cdk.Duration.seconds(300),
      memorySize: 512,
      environment: {
        DLQ_URL: deadLetterQueue.queueUrl,
      },
      deadLetterQueue: deadLetterQueue,
      reservedConcurrentExecutions: enableDetailedMonitoring ? 100 : undefined,
    });

    // Create error handler Lambda function
    const errorHandlerFunction = new lambda.Function(this, 'ErrorHandlerFunction', {
      functionName: `error-handler-${resourceSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'error_handler.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
from datetime import datetime

sns = boto3.client('sns')

def lambda_handler(event, context):
    try:
        # Process SQS messages from DLQ
        for record in event['Records']:
            message_body = json.loads(record['body'])
            
            # Extract error details
            error_message = message_body.get('error_message', 'Unknown error')
            timestamp = message_body.get('timestamp', datetime.now().isoformat())
            
            # Send alert via SNS
            alert_message = f"""
Data Processing Error Alert

Error: {error_message}
Timestamp: {timestamp}

Please investigate the failed processing job.
            """
            
            import os
            sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
            
            if sns_topic_arn:
                sns.publish(
                    TopicArn=sns_topic_arn,
                    Message=alert_message,
                    Subject='Data Processing Error Alert'
                )
            
            print(f"Error alert sent for: {error_message}")
            
    except Exception as e:
        print(f"Error in error handler: {str(e)}")
        raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps('Error handling completed')
    }
      `),
      role: lambdaRole,
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      environment: {
        SNS_TOPIC_ARN: alertTopic.topicArn,
      },
    });

    // Add SQS trigger to error handler
    errorHandlerFunction.addEventSource(
      new lambdaEventSources.SqsEventSource(deadLetterQueue, {
        batchSize: 10,
        maxBatchingWindow: cdk.Duration.seconds(5),
      })
    );

    // Add S3 event notification to trigger data processing
    dataBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(dataProcessorFunction),
      {
        prefix: 'data/',
      }
    );

    // Create CloudWatch alarms for monitoring
    const lambdaErrorAlarm = new cloudwatch.Alarm(this, 'LambdaErrorAlarm', {
      alarmName: `${dataProcessorFunction.functionName}-errors`,
      alarmDescription: 'Monitor Lambda function errors',
      metric: dataProcessorFunction.metricErrors({
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Statistic.SUM,
      }),
      threshold: 1,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
    });

    const dlqMessageAlarm = new cloudwatch.Alarm(this, 'DLQMessageAlarm', {
      alarmName: `${deadLetterQueue.queueName}-messages`,
      alarmDescription: 'Monitor DLQ message count',
      metric: deadLetterQueue.metricApproximateNumberOfVisibleMessages({
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Statistic.AVERAGE,
      }),
      threshold: 5,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    });

    // Add SNS actions to alarms
    lambdaErrorAlarm.addAlarmAction(new cloudwatchActions.SnsAction(alertTopic));
    dlqMessageAlarm.addAlarmAction(new cloudwatchActions.SnsAction(alertTopic));

    // Optional: Create additional monitoring resources if detailed monitoring is enabled
    if (enableDetailedMonitoring) {
      // Create custom metrics for processing volume
      const processingVolumeMetric = new cloudwatch.Metric({
        namespace: 'DataProcessing',
        metricName: 'ProcessedFiles',
        dimensionsMap: {
          Environment: this.node.tryGetContext('environment') || 'dev',
        },
        statistic: cloudwatch.Statistic.SUM,
      });

      new cloudwatch.Alarm(this, 'ProcessingVolumeAlarm', {
        alarmName: `${resourceSuffix}-processing-volume`,
        alarmDescription: 'Monitor data processing volume',
        metric: processingVolumeMetric,
        threshold: 1000,
        evaluationPeriods: 1,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      });

      // Create dashboard for monitoring
      const dashboard = new cloudwatch.Dashboard(this, 'ProcessingDashboard', {
        dashboardName: `data-processing-dashboard-${resourceSuffix}`,
        widgets: [
          [
            new cloudwatch.GraphWidget({
              title: 'Lambda Function Metrics',
              left: [
                dataProcessorFunction.metricInvocations(),
                dataProcessorFunction.metricErrors(),
              ],
              right: [dataProcessorFunction.metricDuration()],
            }),
          ],
          [
            new cloudwatch.GraphWidget({
              title: 'Queue Metrics',
              left: [
                deadLetterQueue.metricApproximateNumberOfVisibleMessages(),
              ],
            }),
          ],
        ],
      });
    }

    // Stack outputs
    new cdk.CfnOutput(this, 'S3BucketName', {
      value: dataBucket.bucketName,
      description: 'Name of the S3 bucket for data processing',
    });

    new cdk.CfnOutput(this, 'DataProcessorFunctionName', {
      value: dataProcessorFunction.functionName,
      description: 'Name of the data processing Lambda function',
    });

    new cdk.CfnOutput(this, 'ErrorHandlerFunctionName', {
      value: errorHandlerFunction.functionName,
      description: 'Name of the error handler Lambda function',
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: alertTopic.topicArn,
      description: 'ARN of the SNS topic for alerts',
    });

    new cdk.CfnOutput(this, 'DeadLetterQueueUrl', {
      value: deadLetterQueue.queueUrl,
      description: 'URL of the Dead Letter Queue',
    });

    new cdk.CfnOutput(this, 'TestUploadCommand', {
      value: `aws s3 cp test-file.csv s3://${dataBucket.bucketName}/data/test-file.csv`,
      description: 'Example command to upload a test file',
    });
  }
}