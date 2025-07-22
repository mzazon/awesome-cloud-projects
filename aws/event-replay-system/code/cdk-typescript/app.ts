import * as cdk from 'aws-cdk-lib';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as sns from 'aws-cdk-lib/aws-sns';
import { Construct } from 'constructs';

/**
 * EventBridge Archive and Replay Stack
 * 
 * This stack implements a comprehensive event replay system using Amazon EventBridge Archive
 * to capture, filter, and replay events on-demand. The solution provides automated event
 * archiving with selective filtering, controlled replay mechanisms, and monitoring capabilities.
 */
export class EventReplayMechanismStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.slice(-6);

    // S3 bucket for logs and artifacts
    const logsBucket = new s3.Bucket(this, 'EventReplayLogsBucket', {
      bucketName: `eventbridge-replay-logs-${uniqueSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'delete-old-logs',
          enabled: true,
          expiration: cdk.Duration.days(30),
        },
      ],
    });

    // Custom EventBridge Event Bus
    const customEventBus = new events.EventBus(this, 'ReplayDemoEventBus', {
      eventBusName: `replay-demo-bus-${uniqueSuffix}`,
      description: 'Custom event bus for replay demonstration',
    });

    // Lambda execution role with necessary permissions
    const lambdaExecutionRole = new iam.Role(this, 'EventReplayProcessorRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      roleName: `EventReplayProcessorRole-${uniqueSuffix}`,
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        EventProcessingPolicy: new iam.PolicyDocument({
          statements: [
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

    // Lambda function for event processing
    const eventProcessorFunction = new lambda.Function(this, 'EventProcessorFunction', {
      functionName: `replay-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process events and log details for replay analysis
    """
    try:
        # Log the complete event for debugging
        logger.info(f"Received event: {json.dumps(event, indent=2)}")
        
        # Extract event details
        event_source = event.get('source', 'unknown')
        event_type = event.get('detail-type', 'unknown')
        event_time = event.get('time', datetime.utcnow().isoformat())
        
        # Check if this is a replayed event
        replay_name = event.get('replay-name')
        if replay_name:
            logger.info(f"Processing REPLAYED event from: {replay_name}")
            
        # Simulate business logic processing
        if event_source == 'myapp.orders':
            process_order_event(event)
        elif event_source == 'myapp.users':
            process_user_event(event)
        else:
            logger.info(f"Processing generic event: {event_type}")
        
        # Return successful response
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Event processed successfully',
                'eventSource': event_source,
                'eventType': event_type,
                'isReplay': bool(replay_name)
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        raise

def process_order_event(event):
    """Process order-related events"""
    order_id = event.get('detail', {}).get('orderId', 'unknown')
    logger.info(f"Processing order event for order: {order_id}")
    
def process_user_event(event):
    """Process user-related events"""
    user_id = event.get('detail', {}).get('userId', 'unknown')
    logger.info(f"Processing user event for user: {user_id}")
      `),
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      description: 'Processes EventBridge events and distinguishes between original and replayed events',
    });

    // EventBridge Rule for event routing
    const eventRule = new events.Rule(this, 'ReplayDemoRule', {
      ruleName: `replay-demo-rule-${uniqueSuffix}`,
      eventBus: customEventBus,
      description: 'Rule for processing application events',
      eventPattern: {
        source: ['myapp.orders', 'myapp.users', 'myapp.inventory'],
        detailType: ['Order Created', 'User Registered', 'Inventory Updated'],
      },
      enabled: true,
    });

    // Add Lambda function as target to the rule
    eventRule.addTarget(new targets.LambdaFunction(eventProcessorFunction));

    // EventBridge Archive for selective event storage
    const eventArchive = new events.Archive(this, 'ReplayDemoArchive', {
      archiveName: `replay-demo-archive-${uniqueSuffix}`,
      sourceEventBus: customEventBus,
      description: 'Archive for order and user events',
      eventPattern: {
        source: ['myapp.orders', 'myapp.users'],
        detailType: ['Order Created', 'User Registered'],
      },
      retention: cdk.Duration.days(30),
    });

    // SNS Topic for replay notifications
    const replayAlertsTopic = new sns.Topic(this, 'ReplayAlertsTopic', {
      topicName: `eventbridge-replay-alerts-${uniqueSuffix}`,
      displayName: 'EventBridge Replay Alerts',
      description: 'SNS topic for EventBridge replay notifications',
    });

    // CloudWatch Alarm for replay failures
    const replayFailureAlarm = new cloudwatch.Alarm(this, 'ReplayFailureAlarm', {
      alarmName: `EventBridge-Replay-Failures-${uniqueSuffix}`,
      alarmDescription: 'Alert when EventBridge replay fails',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Events',
        metricName: 'ReplayFailures',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add SNS topic as alarm action
    replayFailureAlarm.addAlarmAction(
      new cloudwatch.SnsAction(replayAlertsTopic)
    );

    // CloudWatch Log Group for replay monitoring
    const replayMonitoringLogGroup = new logs.LogGroup(this, 'ReplayMonitoringLogGroup', {
      logGroupName: `/aws/events/replay-monitoring-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Custom resource for event generation (for testing)
    const eventGeneratorFunction = new lambda.Function(this, 'EventGeneratorFunction', {
      functionName: `event-generator-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import random
from datetime import datetime

def lambda_handler(event, context):
    """
    Generate sample events for testing the replay system
    """
    try:
        events_client = boto3.client('events')
        event_bus_name = event.get('EventBusName')
        
        if not event_bus_name:
            raise ValueError('EventBusName is required')
        
        # Generate sample events
        for i in range(1, 11):
            # Generate order events
            order_event = {
                'Source': 'myapp.orders',
                'DetailType': 'Order Created',
                'Detail': json.dumps({
                    'orderId': f'order-{i}',
                    'amount': random.randint(50, 1000),
                    'customerId': f'customer-{i}',
                    'timestamp': datetime.utcnow().isoformat()
                }),
                'EventBusName': event_bus_name
            }
            
            # Generate user events
            user_event = {
                'Source': 'myapp.users',
                'DetailType': 'User Registered',
                'Detail': json.dumps({
                    'userId': f'user-{i}',
                    'email': f'user{i}@example.com',
                    'timestamp': datetime.utcnow().isoformat()
                }),
                'EventBusName': event_bus_name
            }
            
            # Send events
            events_client.put_events(Entries=[order_event, user_event])
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Successfully generated 20 test events',
                'eventBusName': event_bus_name
            })
        }
        
    except Exception as e:
        print(f"Error generating events: {str(e)}")
        raise
      `),
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      description: 'Generates sample events for testing the replay system',
    });

    // Grant EventBridge permissions to the event generator function
    eventGeneratorFunction.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['events:PutEvents'],
        resources: [customEventBus.eventBusArn],
      })
    );

    // Custom resource for replay automation
    const replayAutomationFunction = new lambda.Function(this, 'ReplayAutomationFunction', {
      functionName: `replay-automation-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
from datetime import datetime, timedelta

def lambda_handler(event, context):
    """
    Automate replay operations with configurable parameters
    """
    try:
        events_client = boto3.client('events')
        
        # Extract parameters
        archive_name = event.get('ArchiveName')
        hours_back = event.get('HoursBack', 1)
        replay_name = event.get('ReplayName')
        
        if not archive_name or not replay_name:
            raise ValueError('ArchiveName and ReplayName are required')
        
        # Calculate replay time window
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=hours_back)
        
        # Get archive details
        archive_response = events_client.describe_archive(ArchiveName=archive_name)
        source_arn = archive_response['SourceArn']
        
        # Start replay
        replay_response = events_client.start_replay(
            ReplayName=replay_name,
            EventSourceArn=source_arn,
            EventStartTime=start_time,
            EventEndTime=end_time,
            Destination={
                'Arn': source_arn
            }
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Replay started successfully',
                'replayName': replay_name,
                'replayArn': replay_response['ReplayArn'],
                'startTime': start_time.isoformat(),
                'endTime': end_time.isoformat(),
                'sourceArn': source_arn
            })
        }
        
    except Exception as e:
        print(f"Error starting replay: {str(e)}")
        raise
      `),
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      description: 'Automates replay operations with configurable parameters',
    });

    // Grant EventBridge permissions to the replay automation function
    replayAutomationFunction.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'events:DescribeArchive',
          'events:StartReplay',
          'events:DescribeReplay',
          'events:ListReplays',
          'events:CancelReplay',
        ],
        resources: ['*'],
      })
    );

    // Outputs for verification and integration
    new cdk.CfnOutput(this, 'EventBusName', {
      value: customEventBus.eventBusName,
      description: 'Name of the custom EventBridge event bus',
      exportName: `${this.stackName}-EventBusName`,
    });

    new cdk.CfnOutput(this, 'EventBusArn', {
      value: customEventBus.eventBusArn,
      description: 'ARN of the custom EventBridge event bus',
      exportName: `${this.stackName}-EventBusArn`,
    });

    new cdk.CfnOutput(this, 'ArchiveName', {
      value: eventArchive.archiveName,
      description: 'Name of the EventBridge archive',
      exportName: `${this.stackName}-ArchiveName`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: eventProcessorFunction.functionName,
      description: 'Name of the event processor Lambda function',
      exportName: `${this.stackName}-LambdaFunctionName`,
    });

    new cdk.CfnOutput(this, 'S3BucketName', {
      value: logsBucket.bucketName,
      description: 'Name of the S3 bucket for logs and artifacts',
      exportName: `${this.stackName}-S3BucketName`,
    });

    new cdk.CfnOutput(this, 'EventGeneratorFunctionName', {
      value: eventGeneratorFunction.functionName,
      description: 'Name of the event generator Lambda function (for testing)',
      exportName: `${this.stackName}-EventGeneratorFunctionName`,
    });

    new cdk.CfnOutput(this, 'ReplayAutomationFunctionName', {
      value: replayAutomationFunction.functionName,
      description: 'Name of the replay automation Lambda function',
      exportName: `${this.stackName}-ReplayAutomationFunctionName`,
    });

    new cdk.CfnOutput(this, 'ReplayAlertsTopicArn', {
      value: replayAlertsTopic.topicArn,
      description: 'ARN of the SNS topic for replay alerts',
      exportName: `${this.stackName}-ReplayAlertsTopicArn`,
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Purpose', 'EventReplayDemo');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('Recipe', 'event-replay-mechanisms-eventbridge-archive');
  }
}

// CDK Application
const app = new cdk.App();

new EventReplayMechanismStack(app, 'EventReplayMechanismStack', {
  description: 'EventBridge Archive and Replay Mechanism Stack - Event Replay with EventBridge Archive',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

app.synth();