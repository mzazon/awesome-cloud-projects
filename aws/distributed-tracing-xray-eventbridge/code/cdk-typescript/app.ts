#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

/**
 * CDK Stack for implementing Distributed Tracing with X-Ray
 * 
 * This stack creates a complete microservices architecture with:
 * - API Gateway with X-Ray tracing enabled
 * - Multiple Lambda functions with X-Ray instrumentation
 * - EventBridge custom event bus for event-driven communication
 * - IAM roles and policies for secure cross-service access
 */
export class DistributedTracingStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate a random suffix for unique resource naming
    const randomSuffix = Math.random().toString(36).substring(2, 8);

    // Create custom EventBridge event bus for isolated event routing
    const eventBus = new events.EventBus(this, 'DistributedTracingEventBus', {
      eventBusName: `distributed-tracing-bus-${randomSuffix}`,
      description: 'Custom event bus for distributed tracing demo with microservices communication'
    });

    // Create IAM role for Lambda functions with comprehensive permissions
    const lambdaRole = new iam.Role(this, 'DistributedTracingLambdaRole', {
      roleName: `distributed-tracing-lambda-role-${randomSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for Lambda functions with X-Ray and EventBridge permissions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSXRayDaemonWriteAccess'),
      ],
      inlinePolicies: {
        EventBridgeAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'events:PutEvents',
                'events:ListRules',
                'events:DescribeRule'
              ],
              resources: [
                eventBus.eventBusArn,
                `arn:aws:events:${this.region}:${this.account}:rule/${eventBus.eventBusName}/*`
              ]
            })
          ]
        })
      }
    });

    // Order Service Lambda Function - Entry point for distributed workflow
    const orderServiceCode = `
import json
import boto3
import os
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all
from datetime import datetime

# Patch AWS SDK calls for automatic X-Ray tracing
patch_all()

eventbridge = boto3.client('events')

@xray_recorder.capture('order_service_handler')
def lambda_handler(event, context):
    """
    Order service handler that processes order creation requests
    and publishes events to EventBridge for downstream processing
    """
    # Extract trace context from API Gateway request
    trace_header = event.get('headers', {}).get('X-Amzn-Trace-Id')
    
    # Create subsegment for detailed order processing tracking
    subsegment = xray_recorder.begin_subsegment('process_order')
    
    try:
        # Generate unique order ID with timestamp
        order_id = f"order-{datetime.now().strftime('%Y%m%d%H%M%S')}"
        customer_id = event.get('pathParameters', {}).get('customerId', 'anonymous')
        
        # Add business metadata to X-Ray trace for filtering and analysis
        subsegment.put_metadata('order_details', {
            'order_id': order_id,
            'customer_id': customer_id,
            'timestamp': datetime.now().isoformat(),
            'source': 'api-gateway'
        })
        
        # Create order event for EventBridge publication
        event_detail = {
            'orderId': order_id,
            'customerId': customer_id,
            'amount': 99.99,
            'status': 'created',
            'timestamp': datetime.now().isoformat()
        }
        
        # Publish order created event to custom EventBridge bus
        response = eventbridge.put_events(
            Entries=[
                {
                    'Source': 'order.service',
                    'DetailType': 'Order Created',
                    'Detail': json.dumps(event_detail),
                    'EventBusName': os.environ['EVENT_BUS_NAME']
                }
            ]
        )
        
        # Add X-Ray annotations for filtering and dashboard creation
        xray_recorder.put_annotation('order_id', order_id)
        xray_recorder.put_annotation('service_name', 'order-service')
        xray_recorder.put_annotation('customer_id', customer_id)
        xray_recorder.put_annotation('order_amount', 99.99)
        
        # Return successful response with trace context
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'X-Amzn-Trace-Id': trace_header,
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'orderId': order_id,
                'status': 'created',
                'message': 'Order created successfully and processing initiated',
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        # Add error annotation for X-Ray error tracking
        xray_recorder.put_annotation('error', str(e))
        xray_recorder.put_annotation('error_type', type(e).__name__)
        
        # Return error response
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'message': 'Failed to process order'
            })
        }
    finally:
        xray_recorder.end_subsegment()
`;

    const orderService = new lambda.Function(this, 'OrderService', {
      functionName: `order-service-${randomSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(orderServiceCode),
      role: lambdaRole,
      timeout: cdk.Duration.seconds(30),
      tracing: lambda.Tracing.ACTIVE,
      environment: {
        EVENT_BUS_NAME: eventBus.eventBusName
      },
      description: 'Order service that initiates distributed workflows via EventBridge'
    });

    // Payment Service Lambda Function - Processes payment events
    const paymentServiceCode = `
import json
import boto3
import os
import time
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patch AWS SDK calls for automatic X-Ray tracing
patch_all()

eventbridge = boto3.client('events')

@xray_recorder.capture('payment_service_handler')
def lambda_handler(event, context):
    """
    Payment service handler that processes payment for orders
    and publishes payment completion events
    """
    # Process EventBridge events (can be multiple in batch)
    for record in event.get('Records', [event]):
        # Handle direct EventBridge invocation or SQS/EventBridge integration
        if 'body' in record:
            detail = json.loads(record['body'])
        else:
            detail = record
            
        # Create subsegment for payment processing tracking
        subsegment = xray_recorder.begin_subsegment('process_payment')
        
        try:
            # Extract order details from event
            order_details = detail.get('detail', detail)
            order_id = order_details.get('orderId')
            amount = order_details.get('amount', 0)
            customer_id = order_details.get('customerId')
            
            # Add payment processing metadata to trace
            subsegment.put_metadata('payment_details', {
                'order_id': order_id,
                'customer_id': customer_id,
                'amount': amount,
                'processor': 'stripe',
                'processing_time_start': time.time()
            })
            
            # Simulate payment processing delay for realistic trace timing
            time.sleep(0.5)
            
            # Generate payment ID and create completion event
            payment_id = f"pay-{order_id}"
            payment_event = {
                'orderId': order_id,
                'customerId': customer_id,
                'amount': amount,
                'paymentId': payment_id,
                'status': 'processed',
                'processor': 'stripe',
                'timestamp': time.time()
            }
            
            # Publish payment processed event to EventBridge
            response = eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'payment.service',
                        'DetailType': 'Payment Processed',
                        'Detail': json.dumps(payment_event),
                        'EventBusName': os.environ['EVENT_BUS_NAME']
                    }
                ]
            )
            
            # Add X-Ray annotations for monitoring and filtering
            xray_recorder.put_annotation('order_id', order_id)
            xray_recorder.put_annotation('service_name', 'payment-service')
            xray_recorder.put_annotation('payment_amount', amount)
            xray_recorder.put_annotation('payment_id', payment_id)
            xray_recorder.put_annotation('customer_id', customer_id)
            
            # Add success metadata
            subsegment.put_metadata('payment_result', {
                'payment_id': payment_id,
                'status': 'success',
                'processing_time_end': time.time()
            })
            
        except Exception as e:
            # Add error tracking to X-Ray
            xray_recorder.put_annotation('error', str(e))
            xray_recorder.put_annotation('error_type', type(e).__name__)
            xray_recorder.put_annotation('service_name', 'payment-service')
            
            # Log error details
            subsegment.put_metadata('error_details', {
                'error_message': str(e),
                'error_type': type(e).__name__
            })
            
            raise e
        finally:
            xray_recorder.end_subsegment()

    return {'statusCode': 200, 'body': json.dumps('Payment processing completed')}
`;

    const paymentService = new lambda.Function(this, 'PaymentService', {
      functionName: `payment-service-${randomSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(paymentServiceCode),
      role: lambdaRole,
      timeout: cdk.Duration.seconds(30),
      tracing: lambda.Tracing.ACTIVE,
      environment: {
        EVENT_BUS_NAME: eventBus.eventBusName
      },
      description: 'Payment service that processes order payments via EventBridge events'
    });

    // Inventory Service Lambda Function - Manages inventory allocation
    const inventoryServiceCode = `
import json
import boto3
import os
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patch AWS SDK calls for automatic X-Ray tracing
patch_all()

eventbridge = boto3.client('events')

@xray_recorder.capture('inventory_service_handler')
def lambda_handler(event, context):
    """
    Inventory service handler that reserves inventory for orders
    and publishes inventory status events
    """
    # Process EventBridge events
    for record in event.get('Records', [event]):
        # Handle different event source formats
        if 'body' in record:
            detail = json.loads(record['body'])
        else:
            detail = record
            
        # Create subsegment for inventory operations tracking
        subsegment = xray_recorder.begin_subsegment('update_inventory')
        
        try:
            # Extract order information
            order_details = detail.get('detail', detail)
            order_id = order_details.get('orderId')
            customer_id = order_details.get('customerId')
            
            # Add inventory operation metadata to trace
            subsegment.put_metadata('inventory_update', {
                'order_id': order_id,
                'customer_id': customer_id,
                'items_reserved': 1,
                'warehouse': 'east-coast',
                'inventory_check_time': time.time() if 'time' in globals() else 'unknown'
            })
            
            # Create inventory updated event
            inventory_event = {
                'orderId': order_id,
                'customerId': customer_id,
                'status': 'reserved',
                'warehouse': 'east-coast',
                'items': [
                    {
                        'sku': 'DEMO-ITEM-001',
                        'quantity': 1,
                        'reserved': True
                    }
                ],
                'timestamp': time.time() if 'time' in globals() else 'unknown'
            }
            
            # Publish inventory updated event to EventBridge
            response = eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'inventory.service',
                        'DetailType': 'Inventory Updated',
                        'Detail': json.dumps(inventory_event),
                        'EventBusName': os.environ['EVENT_BUS_NAME']
                    }
                ]
            )
            
            # Add X-Ray annotations for service monitoring
            xray_recorder.put_annotation('order_id', order_id)
            xray_recorder.put_annotation('service_name', 'inventory-service')
            xray_recorder.put_annotation('warehouse', 'east-coast')
            xray_recorder.put_annotation('customer_id', customer_id)
            xray_recorder.put_annotation('items_reserved', 1)
            
        except Exception as e:
            # Track errors in X-Ray for debugging
            xray_recorder.put_annotation('error', str(e))
            xray_recorder.put_annotation('error_type', type(e).__name__)
            xray_recorder.put_annotation('service_name', 'inventory-service')
            raise e
        finally:
            xray_recorder.end_subsegment()

    return {'statusCode': 200, 'body': json.dumps('Inventory processing completed')}
`;

    const inventoryService = new lambda.Function(this, 'InventoryService', {
      functionName: `inventory-service-${randomSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(inventoryServiceCode),
      role: lambdaRole,
      timeout: cdk.Duration.seconds(30),
      tracing: lambda.Tracing.ACTIVE,
      environment: {
        EVENT_BUS_NAME: eventBus.eventBusName
      },
      description: 'Inventory service that manages stock allocation via EventBridge events'
    });

    // Notification Service Lambda Function - Handles customer communications
    const notificationServiceCode = `
import json
import boto3
import os
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patch AWS SDK calls for automatic X-Ray tracing
patch_all()

@xray_recorder.capture('notification_service_handler')
def lambda_handler(event, context):
    """
    Notification service handler that sends customer notifications
    for various order and payment events
    """
    # Process all notification events
    for record in event.get('Records', [event]):
        # Handle different event source formats
        if 'body' in record:
            detail = json.loads(record['body'])
        else:
            detail = record
            
        # Create subsegment for notification processing
        subsegment = xray_recorder.begin_subsegment('send_notification')
        
        try:
            # Extract event information
            order_details = detail.get('detail', detail)
            order_id = order_details.get('orderId')
            customer_id = order_details.get('customerId')
            event_type = detail.get('detail-type', 'Unknown Event')
            
            # Determine notification type based on event
            notification_type = 'email'
            if 'Payment' in event_type:
                notification_type = 'sms+email'
            elif 'Inventory' in event_type:
                notification_type = 'email'
                
            # Add notification metadata to trace
            subsegment.put_metadata('notification_sent', {
                'order_id': order_id,
                'customer_id': customer_id,
                'event_type': event_type,
                'channel': notification_type,
                'template': f"{event_type.lower().replace(' ', '_')}_notification",
                'sent_at': time.time() if 'time' in globals() else 'unknown'
            })
            
            # Add X-Ray annotations for notification tracking
            xray_recorder.put_annotation('order_id', order_id)
            xray_recorder.put_annotation('service_name', 'notification-service')
            xray_recorder.put_annotation('notification_type', event_type)
            xray_recorder.put_annotation('customer_id', customer_id)
            xray_recorder.put_annotation('channel', notification_type)
            
            # Add successful notification metadata
            subsegment.put_metadata('notification_result', {
                'status': 'sent',
                'delivery_method': notification_type,
                'template_used': f"{event_type.lower().replace(' ', '_')}_notification"
            })
            
        except Exception as e:
            # Track notification failures in X-Ray
            xray_recorder.put_annotation('error', str(e))
            xray_recorder.put_annotation('error_type', type(e).__name__)
            xray_recorder.put_annotation('service_name', 'notification-service')
            
            subsegment.put_metadata('notification_error', {
                'error_message': str(e),
                'failed_event_type': event_type if 'event_type' in locals() else 'unknown'
            })
            
            raise e
        finally:
            xray_recorder.end_subsegment()

    return {'statusCode': 200, 'body': json.dumps('Notifications processed')}
`;

    const notificationService = new lambda.Function(this, 'NotificationService', {
      functionName: `notification-service-${randomSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(notificationServiceCode),
      role: lambdaRole,
      timeout: cdk.Duration.seconds(30),
      tracing: lambda.Tracing.ACTIVE,
      environment: {
        EVENT_BUS_NAME: eventBus.eventBusName
      },
      description: 'Notification service that sends customer updates via EventBridge events'
    });

    // EventBridge Rules for event routing between microservices

    // Rule for payment processing - triggers when orders are created
    const paymentProcessingRule = new events.Rule(this, 'PaymentProcessingRule', {
      ruleName: `payment-processing-rule-${randomSuffix}`,
      eventBus: eventBus,
      description: 'Routes order creation events to payment processing service',
      eventPattern: {
        source: ['order.service'],
        detailType: ['Order Created']
      },
      enabled: true
    });

    // Rule for inventory updates - triggers when orders are created
    const inventoryUpdateRule = new events.Rule(this, 'InventoryUpdateRule', {
      ruleName: `inventory-update-rule-${randomSuffix}`,
      eventBus: eventBus,
      description: 'Routes order creation events to inventory management service',
      eventPattern: {
        source: ['order.service'],
        detailType: ['Order Created']
      },
      enabled: true
    });

    // Rule for notifications - triggers on payment and inventory events
    const notificationRule = new events.Rule(this, 'NotificationRule', {
      ruleName: `notification-rule-${randomSuffix}`,
      eventBus: eventBus,
      description: 'Routes payment and inventory events to customer notification service',
      eventPattern: {
        source: ['payment.service', 'inventory.service'],
        detailType: ['Payment Processed', 'Inventory Updated']
      },
      enabled: true
    });

    // Add Lambda targets to EventBridge rules
    paymentProcessingRule.addTarget(new targets.LambdaFunction(paymentService, {
      retryAttempts: 3,
      maxEventAge: cdk.Duration.hours(2)
    }));

    inventoryUpdateRule.addTarget(new targets.LambdaFunction(inventoryService, {
      retryAttempts: 3,
      maxEventAge: cdk.Duration.hours(2)
    }));

    notificationRule.addTarget(new targets.LambdaFunction(notificationService, {
      retryAttempts: 3,
      maxEventAge: cdk.Duration.hours(2)
    }));

    // API Gateway with X-Ray tracing for external access
    const api = new apigateway.RestApi(this, 'DistributedTracingApi', {
      restApiName: `distributed-tracing-api-${randomSuffix}`,
      description: 'API Gateway for distributed tracing demo with X-Ray enabled',
      tracingEnabled: true,
      deployOptions: {
        stageName: 'prod',
        tracingEnabled: true,
        metricsEnabled: true,
        dataTraceEnabled: true,
        loggingLevel: apigateway.MethodLoggingLevel.INFO
      },
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amzn-Trace-Id', 'Authorization']
      }
    });

    // Create API resources and methods
    const ordersResource = api.root.addResource('orders');
    const customerResource = ordersResource.addResource('{customerId}');

    // POST method for order creation
    const orderIntegration = new apigateway.LambdaIntegration(orderService, {
      requestTemplates: {
        'application/json': JSON.stringify({
          body: '$input.json("$")',
          headers: {
            '#foreach($header in $input.params().header.keySet())\n' +
            '"$header": "$util.escapeJavaScript($input.params().header.get($header))" #if($foreach.hasNext),#end\n' +
            '#end'
          },
          pathParameters: {
            '#foreach($param in $input.params().path.keySet())\n' +
            '"$param": "$util.escapeJavaScript($input.params().path.get($param))" #if($foreach.hasNext),#end\n' +
            '#end'
          }
        })
      },
      integrationResponses: [
        {
          statusCode: '200',
          responseTemplates: {
            'application/json': '$input.json("$")'
          },
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': "'*'"
          }
        }
      ]
    });

    customerResource.addMethod('POST', orderIntegration, {
      methodResponses: [
        {
          statusCode: '200',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true
          },
          responseModels: {
            'application/json': apigateway.Model.EMPTY_MODEL
          }
        }
      ]
    });

    // Stack outputs for easy access to created resources
    new cdk.CfnOutput(this, 'ApiEndpoint', {
      value: api.url,
      description: 'API Gateway endpoint URL for testing distributed tracing',
      exportName: `${this.stackName}-ApiEndpoint`
    });

    new cdk.CfnOutput(this, 'EventBusName', {
      value: eventBus.eventBusName,
      description: 'Custom EventBridge bus name for event routing',
      exportName: `${this.stackName}-EventBusName`
    });

    new cdk.CfnOutput(this, 'EventBusArn', {
      value: eventBus.eventBusArn,
      description: 'Custom EventBridge bus ARN',
      exportName: `${this.stackName}-EventBusArn`
    });

    new cdk.CfnOutput(this, 'XRayConsoleUrl', {
      value: `https://console.aws.amazon.com/xray/home?region=${this.region}#/service-map`,
      description: 'X-Ray console URL to view service map and traces',
      exportName: `${this.stackName}-XRayConsoleUrl`
    });

    new cdk.CfnOutput(this, 'TestCommand', {
      value: `curl -X POST -H "Content-Type: application/json" -d '{"productId": "12345", "quantity": 1}' "${api.url}orders/customer123"`,
      description: 'Test command to trigger distributed tracing workflow',
      exportName: `${this.stackName}-TestCommand`
    });

    // Add tags for resource organization and cost tracking
    cdk.Tags.of(this).add('Project', 'DistributedTracing');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('Recipe', 'distributed-tracing-x-ray-eventbridge');
    cdk.Tags.of(this).add('CostCenter', 'Development');
  }
}

// CDK App instantiation
const app = new cdk.App();

// Create the stack with appropriate configuration
new DistributedTracingStack(app, 'DistributedTracingStack', {
  description: 'Distributed tracing implementation with X-Ray and EventBridge for microservices observability',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  },
  tags: {
    Project: 'DistributedTracing',
    Recipe: 'distributed-tracing-x-ray-eventbridge',
    Environment: 'Demo'
  }
});