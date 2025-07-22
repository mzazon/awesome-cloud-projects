import * as cdk from 'aws-cdk-lib';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';
import * as path from 'path';

export interface EventDrivenArchitectureStackProps extends cdk.StackProps {
  uniqueSuffix: string;
  environment: string;
}

export class EventDrivenArchitectureStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: EventDrivenArchitectureStackProps) {
    super(scope, id, props);

    // Create custom EventBridge bus for e-commerce domain
    const customEventBus = new events.EventBus(this, 'EcommerceEventBus', {
      eventBusName: `ecommerce-events-${props.uniqueSuffix}`,
      description: 'Custom event bus for e-commerce domain events'
    });

    // Create CloudWatch Log Group for event monitoring
    const eventLogGroup = new logs.LogGroup(this, 'EventMonitoringLogGroup', {
      logGroupName: `/aws/events/${customEventBus.eventBusName}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Create IAM role for Lambda functions
    const lambdaExecutionRole = new iam.Role(this, 'LambdaExecutionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        EventBridgeInteractionPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'events:PutEvents',
                'events:ListRules',
                'events:DescribeRule'
              ],
              resources: ['*']
            })
          ]
        })
      }
    });

    // Create Lambda function for order processing
    const orderProcessorFunction = new lambda.Function(this, 'OrderProcessorFunction', {
      functionName: `eventbridge-demo-${props.uniqueSuffix}-order-processor`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(30),
      environment: {
        EVENT_BUS_NAME: customEventBus.eventBusName
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

eventbridge = boto3.client('events')

def lambda_handler(event, context):
    print(f"Processing order event: {json.dumps(event, indent=2)}")
    
    # Extract order details from the event
    order_details = event.get('detail', {})
    order_id = order_details.get('orderId', 'unknown')
    customer_id = order_details.get('customerId', 'unknown')
    total_amount = order_details.get('totalAmount', 0)
    
    try:
        # Simulate order processing logic
        print(f"Processing order {order_id} for customer {customer_id}")
        print(f"Order total: ${total_amount}")
        
        # Emit order processed event
        response = eventbridge.put_events(
            Entries=[
                {
                    'Source': 'ecommerce.order',
                    'DetailType': 'Order Processed',
                    'Detail': json.dumps({
                        'orderId': order_id,
                        'customerId': customer_id,
                        'totalAmount': total_amount,
                        'status': 'processed',
                        'timestamp': datetime.utcnow().isoformat()
                    }),
                    'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
                }
            ]
        )
        
        print(f"Emitted order processed event: {response}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Order {order_id} processed successfully',
                'eventId': response['Entries'][0]['EventId']
            })
        }
        
    except Exception as e:
        print(f"Error processing order: {str(e)}")
        
        # Emit order failed event
        eventbridge.put_events(
            Entries=[
                {
                    'Source': 'ecommerce.order',
                    'DetailType': 'Order Processing Failed',
                    'Detail': json.dumps({
                        'orderId': order_id,
                        'customerId': customer_id,
                        'error': str(e),
                        'timestamp': datetime.utcnow().isoformat()
                    }),
                    'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
                }
            ]
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
`)
    });

    // Create Lambda function for inventory management
    const inventoryManagerFunction = new lambda.Function(this, 'InventoryManagerFunction', {
      functionName: `eventbridge-demo-${props.uniqueSuffix}-inventory-manager`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(30),
      environment: {
        EVENT_BUS_NAME: customEventBus.eventBusName
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

eventbridge = boto3.client('events')

def lambda_handler(event, context):
    print(f"Processing inventory event: {json.dumps(event, indent=2)}")
    
    # Extract order details from the event
    order_details = event.get('detail', {})
    order_id = order_details.get('orderId', 'unknown')
    
    try:
        # Simulate inventory check and reservation
        print(f"Checking inventory for order {order_id}")
        
        # Simulate inventory availability (randomize for demo)
        import random
        inventory_available = random.choice([True, True, True, False])  # 75% success rate
        
        if inventory_available:
            # Emit inventory reserved event
            response = eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'ecommerce.inventory',
                        'DetailType': 'Inventory Reserved',
                        'Detail': json.dumps({
                            'orderId': order_id,
                            'status': 'reserved',
                            'reservationId': f"res-{order_id}-{int(datetime.now().timestamp())}",
                            'timestamp': datetime.utcnow().isoformat()
                        }),
                        'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
                    }
                ]
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Inventory reserved for order {order_id}',
                    'eventId': response['Entries'][0]['EventId']
                })
            }
        else:
            # Emit inventory unavailable event
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'ecommerce.inventory',
                        'DetailType': 'Inventory Unavailable',
                        'Detail': json.dumps({
                            'orderId': order_id,
                            'status': 'unavailable',
                            'reason': 'Insufficient stock',
                            'timestamp': datetime.utcnow().isoformat()
                        }),
                        'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
                    }
                ]
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Inventory unavailable for order {order_id}'
                })
            }
        
    except Exception as e:
        print(f"Error managing inventory: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
`)
    });

    // Create Lambda function for event generation (testing purposes)
    const eventGeneratorFunction = new lambda.Function(this, 'EventGeneratorFunction', {
      functionName: `eventbridge-demo-${props.uniqueSuffix}-event-generator`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(30),
      environment: {
        EVENT_BUS_NAME: customEventBus.eventBusName
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime
import random

eventbridge = boto3.client('events')

def lambda_handler(event, context):
    # Generate sample order data
    order_id = f"ord-{int(datetime.now().timestamp())}-{random.randint(1000, 9999)}"
    customer_id = f"cust-{random.randint(1000, 9999)}"
    total_amount = round(random.uniform(25.99, 299.99), 2)
    
    # Create order event
    order_event = {
        'Source': 'ecommerce.api',
        'DetailType': 'Order Created',
        'Detail': json.dumps({
            'orderId': order_id,
            'customerId': customer_id,
            'totalAmount': total_amount,
            'items': [
                {
                    'productId': f'prod-{random.randint(100, 999)}',
                    'quantity': random.randint(1, 3),
                    'price': round(total_amount / random.randint(1, 3), 2)
                }
            ],
            'timestamp': datetime.utcnow().isoformat()
        }),
        'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
    }
    
    try:
        response = eventbridge.put_events(Entries=[order_event])
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Order event generated successfully',
                'orderId': order_id,
                'eventId': response['Entries'][0]['EventId']
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
`)
    });

    // Create SQS queue for payment processing with delay
    const paymentProcessingQueue = new sqs.Queue(this, 'PaymentProcessingQueue', {
      queueName: `${props.uniqueSuffix}-payment-processing`,
      deliveryDelay: cdk.Duration.seconds(30),
      visibilityTimeout: cdk.Duration.minutes(5),
      retentionPeriod: cdk.Duration.days(7)
    });

    // EventBridge Rules and Targets

    // Rule 1: Route new orders to order processing Lambda
    const orderProcessingRule = new events.Rule(this, 'OrderProcessingRule', {
      ruleName: `${props.uniqueSuffix}-order-processing-rule`,
      eventBus: customEventBus,
      description: 'Route new orders to processing Lambda',
      eventPattern: {
        source: ['ecommerce.api'],
        detailType: ['Order Created'],
        detail: {
          totalAmount: [{ numeric: ['>', 0] }]
        }
      }
    });

    orderProcessingRule.addTarget(new targets.LambdaFunction(orderProcessorFunction));

    // Rule 2: Route processed orders to inventory management
    const inventoryCheckRule = new events.Rule(this, 'InventoryCheckRule', {
      ruleName: `${props.uniqueSuffix}-inventory-check-rule`,
      eventBus: customEventBus,
      description: 'Route processed orders to inventory check',
      eventPattern: {
        source: ['ecommerce.order'],
        detailType: ['Order Processed'],
        detail: {
          status: ['processed']
        }
      }
    });

    inventoryCheckRule.addTarget(new targets.LambdaFunction(inventoryManagerFunction));

    // Rule 3: Route inventory reserved events to payment processing
    const paymentProcessingRule = new events.Rule(this, 'PaymentProcessingRule', {
      ruleName: `${props.uniqueSuffix}-payment-processing-rule`,
      eventBus: customEventBus,
      description: 'Route inventory reserved events to payment',
      eventPattern: {
        source: ['ecommerce.inventory'],
        detailType: ['Inventory Reserved'],
        detail: {
          status: ['reserved']
        }
      }
    });

    paymentProcessingRule.addTarget(new targets.SqsQueue(paymentProcessingQueue));

    // Rule 4: Archive all events to CloudWatch Logs for monitoring
    const monitoringRule = new events.Rule(this, 'MonitoringRule', {
      ruleName: `${props.uniqueSuffix}-monitoring-rule`,
      eventBus: customEventBus,
      description: 'Archive all ecommerce events for monitoring',
      eventPattern: {
        source: [{ prefix: 'ecommerce.' }]
      }
    });

    monitoringRule.addTarget(new targets.CloudWatchLogGroup(eventLogGroup));

    // Outputs for verification and integration
    new cdk.CfnOutput(this, 'CustomEventBusName', {
      value: customEventBus.eventBusName,
      description: 'Name of the custom EventBridge bus'
    });

    new cdk.CfnOutput(this, 'CustomEventBusArn', {
      value: customEventBus.eventBusArn,
      description: 'ARN of the custom EventBridge bus'
    });

    new cdk.CfnOutput(this, 'OrderProcessorFunctionName', {
      value: orderProcessorFunction.functionName,
      description: 'Name of the order processor Lambda function'
    });

    new cdk.CfnOutput(this, 'InventoryManagerFunctionName', {
      value: inventoryManagerFunction.functionName,
      description: 'Name of the inventory manager Lambda function'
    });

    new cdk.CfnOutput(this, 'EventGeneratorFunctionName', {
      value: eventGeneratorFunction.functionName,
      description: 'Name of the event generator Lambda function'
    });

    new cdk.CfnOutput(this, 'PaymentQueueUrl', {
      value: paymentProcessingQueue.queueUrl,
      description: 'URL of the payment processing SQS queue'
    });

    new cdk.CfnOutput(this, 'PaymentQueueArn', {
      value: paymentProcessingQueue.queueArn,
      description: 'ARN of the payment processing SQS queue'
    });

    new cdk.CfnOutput(this, 'EventLogGroupName', {
      value: eventLogGroup.logGroupName,
      description: 'Name of the CloudWatch log group for event monitoring'
    });

    // Test command output
    new cdk.CfnOutput(this, 'TestCommand', {
      value: `aws lambda invoke --function-name ${eventGeneratorFunction.functionName} --payload '{}' response.json && cat response.json`,
      description: 'Command to test the event-driven architecture'
    });
  }
}