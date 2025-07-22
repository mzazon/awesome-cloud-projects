#!/usr/bin/env node

import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Duration } from 'aws-cdk-lib';

/**
 * Stack for building event-driven architectures with EventBridge
 * This stack demonstrates:
 * - Custom EventBridge event bus
 * - Event rules with pattern matching
 * - Multiple event targets (Lambda, SNS, SQS)
 * - Proper IAM permissions
 * - CloudWatch logging
 */
export class EventDrivenArchitectureStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // Create custom EventBridge event bus
    const customEventBus = new events.EventBus(this, 'ECommerceEventBus', {
      eventBusName: `ecommerce-events-${uniqueSuffix}`,
      description: 'Custom event bus for e-commerce application events',
    });

    // Add tags to event bus
    cdk.Tags.of(customEventBus).add('Name', `ecommerce-events-${uniqueSuffix}`);
    cdk.Tags.of(customEventBus).add('Purpose', 'ECommerce-Events');

    // Create SNS topic for notifications
    const notificationTopic = new sns.Topic(this, 'OrderNotificationTopic', {
      topicName: `order-notifications-${uniqueSuffix}`,
      displayName: 'Order Notifications',
      description: 'Topic for high-value order notifications',
    });

    // Create SQS queue for batch processing
    const processingQueue = new sqs.Queue(this, 'EventProcessingQueue', {
      queueName: `event-processing-${uniqueSuffix}`,
      visibilityTimeout: Duration.minutes(5),
      messageRetentionPeriod: Duration.days(14),
      deadLetterQueue: {
        queue: new sqs.Queue(this, 'EventProcessingDLQ', {
          queueName: `event-processing-dlq-${uniqueSuffix}`,
          messageRetentionPeriod: Duration.days(14),
        }),
        maxReceiveCount: 3,
      },
    });

    // Create CloudWatch log group for Lambda function
    const logGroup = new logs.LogGroup(this, 'EventProcessorLogGroup', {
      logGroupName: `/aws/lambda/event-processor-${uniqueSuffix}`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create Lambda function for event processing
    const eventProcessorFunction = new lambda.Function(this, 'EventProcessorFunction', {
      functionName: `event-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'event_processor.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Process EventBridge events"""
    
    try:
        logger.info(f"Received event: {json.dumps(event, indent=2)}")
        
        # Extract event details
        event_source = event.get('source', 'unknown')
        event_type = event.get('detail-type', 'unknown')
        event_detail = event.get('detail', {})
        
        # Process based on event type
        result = process_event(event_source, event_type, event_detail)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Event processed successfully',
                'eventSource': event_source,
                'eventType': event_type,
                'result': result,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def process_event(source, event_type, detail):
    """Process different types of events"""
    
    if source == 'ecommerce.orders':
        return process_order_event(event_type, detail)
    elif source == 'ecommerce.users':
        return process_user_event(event_type, detail)
    elif source == 'ecommerce.payments':
        return process_payment_event(event_type, detail)
    else:
        return process_generic_event(event_type, detail)

def process_order_event(event_type, detail):
    """Process order-related events"""
    
    if event_type == 'Order Created':
        order_id = detail.get('orderId')
        customer_id = detail.get('customerId')
        total_amount = detail.get('totalAmount', 0)
        
        logger.info(f"Processing new order: {order_id} for customer {customer_id}")
        
        # Business logic for order processing
        result = {
            'action': 'order_processed',
            'orderId': order_id,
            'customerId': customer_id,
            'totalAmount': total_amount,
            'priority': 'high' if total_amount > 1000 else 'normal'
        }
        
        return result
        
    elif event_type == 'Order Cancelled':
        order_id = detail.get('orderId')
        logger.info(f"Processing order cancellation: {order_id}")
        
        return {
            'action': 'order_cancelled',
            'orderId': order_id
        }
    
    return {'action': 'order_event_processed'}

def process_user_event(event_type, detail):
    """Process user-related events"""
    
    if event_type == 'User Registered':
        user_id = detail.get('userId')
        email = detail.get('email')
        
        logger.info(f"Processing new user registration: {user_id}")
        
        return {
            'action': 'user_registered',
            'userId': user_id,
            'email': email,
            'welcomeEmailSent': True
        }
    
    return {'action': 'user_event_processed'}

def process_payment_event(event_type, detail):
    """Process payment-related events"""
    
    if event_type == 'Payment Processed':
        payment_id = detail.get('paymentId')
        amount = detail.get('amount')
        
        logger.info(f"Processing payment: {payment_id} for amount {amount}")
        
        return {
            'action': 'payment_processed',
            'paymentId': payment_id,
            'amount': amount
        }
    
    return {'action': 'payment_event_processed'}

def process_generic_event(event_type, detail):
    """Process generic events"""
    
    logger.info(f"Processing generic event: {event_type}")
    
    return {
        'action': 'generic_event_processed',
        'eventType': event_type
    }
`),
      timeout: Duration.seconds(30),
      memorySize: 256,
      logGroup: logGroup,
      description: 'Processes events from EventBridge custom event bus',
      environment: {
        EVENT_BUS_NAME: customEventBus.eventBusName,
        SNS_TOPIC_ARN: notificationTopic.topicArn,
        SQS_QUEUE_URL: processingQueue.queueUrl,
      },
    });

    // Create IAM role for EventBridge with permissions to invoke targets
    const eventBridgeRole = new iam.Role(this, 'EventBridgeExecutionRole', {
      assumedBy: new iam.ServicePrincipal('events.amazonaws.com'),
      roleName: `EventBridgeExecutionRole-${uniqueSuffix}`,
      description: 'Role for EventBridge to invoke targets',
      inlinePolicies: {
        EventBridgeTargetsPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sns:Publish'],
              resources: [notificationTopic.topicArn],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sqs:SendMessage'],
              resources: [processingQueue.queueArn],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['lambda:InvokeFunction'],
              resources: [eventProcessorFunction.functionArn],
            }),
          ],
        }),
      },
    });

    // Rule 1: Route all order events to Lambda
    const orderEventsRule = new events.Rule(this, 'OrderEventsRule', {
      eventBus: customEventBus,
      ruleName: 'OrderEventsRule',
      description: 'Route order events to Lambda processor',
      eventPattern: {
        source: ['ecommerce.orders'],
        detailType: ['Order Created', 'Order Updated', 'Order Cancelled'],
      },
    });

    // Add Lambda target to order events rule
    orderEventsRule.addTarget(new targets.LambdaFunction(eventProcessorFunction, {
      retryAttempts: 3,
    }));

    // Rule 2: Route high-value orders to SNS for immediate notification
    const highValueOrdersRule = new events.Rule(this, 'HighValueOrdersRule', {
      eventBus: customEventBus,
      ruleName: 'HighValueOrdersRule',
      description: 'Route high-value orders to SNS for notifications',
      eventPattern: {
        source: ['ecommerce.orders'],
        detailType: ['Order Created'],
        detail: {
          totalAmount: [{ numeric: ['>', 1000] }],
        },
      },
    });

    // Add SNS target to high-value orders rule
    highValueOrdersRule.addTarget(new targets.SnsTopic(notificationTopic, {
      message: events.RuleTargetInput.fromText(
        'High-value order alert: Order ID ${detail.orderId} with amount $${detail.totalAmount} created for customer ${detail.customerId}'
      ),
    }));

    // Rule 3: Route all events to SQS for batch processing
    const allEventsToSQSRule = new events.Rule(this, 'AllEventsToSQSRule', {
      eventBus: customEventBus,
      ruleName: 'AllEventsToSQSRule',
      description: 'Route all events to SQS for batch processing',
      eventPattern: {
        source: ['ecommerce.orders', 'ecommerce.users', 'ecommerce.payments'],
      },
    });

    // Add SQS target to all events rule
    allEventsToSQSRule.addTarget(new targets.SqsQueue(processingQueue, {
      messageGroupId: 'event-processing',
    }));

    // Rule 4: Route user registration events to Lambda
    const userRegistrationRule = new events.Rule(this, 'UserRegistrationRule', {
      eventBus: customEventBus,
      ruleName: 'UserRegistrationRule',
      description: 'Route user registration events to Lambda',
      eventPattern: {
        source: ['ecommerce.users'],
        detailType: ['User Registered'],
      },
    });

    // Add Lambda target to user registration rule
    userRegistrationRule.addTarget(new targets.LambdaFunction(eventProcessorFunction, {
      retryAttempts: 3,
    }));

    // Grant EventBridge permissions to invoke Lambda function
    eventProcessorFunction.addPermission('AllowEventBridgeOrderEvents', {
      principal: new iam.ServicePrincipal('events.amazonaws.com'),
      action: 'lambda:InvokeFunction',
      sourceArn: orderEventsRule.ruleArn,
    });

    eventProcessorFunction.addPermission('AllowEventBridgeUserEvents', {
      principal: new iam.ServicePrincipal('events.amazonaws.com'),
      action: 'lambda:InvokeFunction',
      sourceArn: userRegistrationRule.ruleArn,
    });

    // Add CloudWatch monitoring
    const eventBusMetricFilter = new logs.MetricFilter(this, 'EventBusMetricFilter', {
      logGroup: logGroup,
      filterPattern: logs.FilterPattern.literal('[timestamp, requestId, level="ERROR"]'),
      metricNamespace: 'EventDrivenArchitecture',
      metricName: 'EventProcessingErrors',
      metricValue: '1',
    });

    // Create CloudWatch Dashboard
    const dashboard = new cdk.aws_cloudwatch.Dashboard(this, 'EventDrivenArchitectureDashboard', {
      dashboardName: `EventDrivenArchitecture-${uniqueSuffix}`,
    });

    // Add widgets to dashboard
    dashboard.addWidgets(
      new cdk.aws_cloudwatch.GraphWidget({
        title: 'EventBridge Rule Invocations',
        left: [
          orderEventsRule.metricAllMatches(),
          highValueOrdersRule.metricAllMatches(),
          allEventsToSQSRule.metricAllMatches(),
          userRegistrationRule.metricAllMatches(),
        ],
        width: 12,
        height: 6,
      })
    );

    dashboard.addWidgets(
      new cdk.aws_cloudwatch.GraphWidget({
        title: 'Lambda Function Metrics',
        left: [
          eventProcessorFunction.metricInvocations(),
          eventProcessorFunction.metricErrors(),
        ],
        right: [
          eventProcessorFunction.metricDuration(),
        ],
        width: 12,
        height: 6,
      })
    );

    dashboard.addWidgets(
      new cdk.aws_cloudwatch.GraphWidget({
        title: 'SQS Queue Metrics',
        left: [
          processingQueue.metricApproximateNumberOfMessages(),
          processingQueue.metricNumberOfMessagesSent(),
          processingQueue.metricNumberOfMessagesReceived(),
        ],
        width: 12,
        height: 6,
      })
    );

    // Output important resource ARNs and names
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

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: eventProcessorFunction.functionName,
      description: 'Name of the event processor Lambda function',
      exportName: `${this.stackName}-LambdaFunctionName`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: eventProcessorFunction.functionArn,
      description: 'ARN of the event processor Lambda function',
      exportName: `${this.stackName}-LambdaFunctionArn`,
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: notificationTopic.topicArn,
      description: 'ARN of the SNS notification topic',
      exportName: `${this.stackName}-SNSTopicArn`,
    });

    new cdk.CfnOutput(this, 'SQSQueueUrl', {
      value: processingQueue.queueUrl,
      description: 'URL of the SQS processing queue',
      exportName: `${this.stackName}-SQSQueueUrl`,
    });

    new cdk.CfnOutput(this, 'SQSQueueArn', {
      value: processingQueue.queueArn,
      description: 'ARN of the SQS processing queue',
      exportName: `${this.stackName}-SQSQueueArn`,
    });

    new cdk.CfnOutput(this, 'CloudWatchDashboardUrl', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard',
      exportName: `${this.stackName}-DashboardUrl`,
    });

    // Output event publishing examples
    new cdk.CfnOutput(this, 'EventPublishingExamples', {
      value: JSON.stringify({
        orderCreatedEvent: {
          Source: 'ecommerce.orders',
          DetailType: 'Order Created',
          Detail: {
            orderId: 'order-123',
            customerId: 'customer-456',
            totalAmount: 1500.00,
            currency: 'USD',
            timestamp: new Date().toISOString(),
          },
          EventBusName: customEventBus.eventBusName,
        },
        userRegisteredEvent: {
          Source: 'ecommerce.users',
          DetailType: 'User Registered',
          Detail: {
            userId: 'user-789',
            email: 'user@example.com',
            firstName: 'John',
            lastName: 'Doe',
            timestamp: new Date().toISOString(),
          },
          EventBusName: customEventBus.eventBusName,
        },
      }, null, 2),
      description: 'Example event structures for testing',
    });
  }
}

// CDK App
const app = new cdk.App();

// Create stack with default props
new EventDrivenArchitectureStack(app, 'EventDrivenArchitectureStack', {
  description: 'Event-driven architecture with EventBridge, Lambda, SNS, and SQS',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'EventDrivenArchitecture',
    Environment: process.env.CDK_ENVIRONMENT || 'development',
    Owner: process.env.CDK_OWNER || 'aws-cdk',
  },
});

// Add stack-level tags
cdk.Tags.of(app).add('Project', 'EventDrivenArchitecture');
cdk.Tags.of(app).add('CreatedBy', 'AWS-CDK');
cdk.Tags.of(app).add('Purpose', 'EventBridge-Recipe-Demo');