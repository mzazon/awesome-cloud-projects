import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as stepfunctions from 'aws-cdk-lib/aws-stepfunctions';
import * as tasks from 'aws-cdk-lib/aws-stepfunctions-tasks';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as path from 'path';

export interface EventDrivenMicroservicesStackProps extends cdk.StackProps {
  projectName: string;
  environment: string;
}

/**
 * Stack implementing event-driven microservices architecture using EventBridge and Step Functions
 * 
 * This stack creates:
 * - Custom EventBridge event bus for decoupled messaging
 * - Lambda functions implementing Order, Payment, Inventory, and Notification services
 * - Step Functions state machine for order processing workflow orchestration
 * - DynamoDB table for order data persistence
 * - IAM roles with least privilege permissions
 * - CloudWatch dashboard for monitoring and observability
 * - EventBridge rules for event routing
 */
export class EventDrivenMicroservicesStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: EventDrivenMicroservicesStackProps) {
    super(scope, id, props);

    const { projectName, environment } = props;

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8);

    // =============================================================================
    // DynamoDB Table for Order Data
    // =============================================================================
    
    const ordersTable = new dynamodb.Table(this, 'OrdersTable', {
      tableName: `${projectName}-orders-${uniqueSuffix}`,
      partitionKey: {
        name: 'orderId',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'customerId',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PROVISIONED,
      readCapacity: 5,
      writeCapacity: 5,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      pointInTimeRecovery: true,
    });

    // Add Global Secondary Index for customer-based queries
    ordersTable.addGlobalSecondaryIndex({
      indexName: 'CustomerId-Index',
      partitionKey: {
        name: 'customerId',
        type: dynamodb.AttributeType.STRING,
      },
      readCapacity: 5,
      writeCapacity: 5,
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // =============================================================================
    // EventBridge Custom Event Bus
    // =============================================================================
    
    const eventBus = new events.EventBus(this, 'OrderProcessingEventBus', {
      eventBusName: `${projectName}-eventbus-${uniqueSuffix}`,
      description: 'Custom event bus for order processing microservices communication',
    });

    // =============================================================================
    // IAM Roles
    // =============================================================================
    
    // Lambda execution role with DynamoDB and EventBridge permissions
    const lambdaExecutionRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `${projectName}-lambda-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        DynamoDBAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:GetItem',
                'dynamodb:PutItem',
                'dynamodb:UpdateItem',
                'dynamodb:DeleteItem',
                'dynamodb:Query',
                'dynamodb:Scan',
              ],
              resources: [
                ordersTable.tableArn,
                `${ordersTable.tableArn}/index/*`,
              ],
            }),
          ],
        }),
        EventBridgeAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'events:PutEvents',
              ],
              resources: [eventBus.eventBusArn],
            }),
          ],
        }),
      },
    });

    // Step Functions execution role
    const stepFunctionsExecutionRole = new iam.Role(this, 'StepFunctionsExecutionRole', {
      roleName: `${projectName}-stepfunctions-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('states.amazonaws.com'),
      inlinePolicies: {
        LambdaInvokeAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['lambda:InvokeFunction'],
              resources: ['*'], // Will be refined after Lambda functions are created
            }),
          ],
        }),
      },
    });

    // =============================================================================
    // Lambda Functions (Microservices)
    // =============================================================================
    
    // Order Service Lambda Function
    const orderService = new lambda.Function(this, 'OrderService', {
      functionName: `${projectName}-order-service-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
from datetime import datetime
import os

dynamodb = boto3.resource('dynamodb')
eventbridge = boto3.client('events')

def lambda_handler(event, context):
    try:
        # Parse order data
        order_data = json.loads(event['body']) if 'body' in event else event
        
        # Create order record
        order_id = str(uuid.uuid4())
        order_item = {
            'orderId': order_id,
            'customerId': order_data['customerId'],
            'items': order_data['items'],
            'totalAmount': order_data['totalAmount'],
            'status': 'PENDING',
            'createdAt': datetime.utcnow().isoformat()
        }
        
        # Store in DynamoDB
        table = dynamodb.Table(os.environ['DYNAMODB_TABLE_NAME'])
        table.put_item(Item=order_item)
        
        # Publish event to EventBridge
        eventbridge.put_events(
            Entries=[
                {
                    'Source': 'order.service',
                    'DetailType': 'Order Created',
                    'Detail': json.dumps(order_item),
                    'EventBusName': os.environ['EVENTBUS_NAME']
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'orderId': order_id,
                'status': 'PENDING'
            })
        }
        
    except Exception as e:
        print(f"Error processing order: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
      `),
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      environment: {
        EVENTBUS_NAME: eventBus.eventBusName,
        DYNAMODB_TABLE_NAME: ordersTable.tableName,
      },
    });

    // Payment Service Lambda Function
    const paymentService = new lambda.Function(this, 'PaymentService', {
      functionName: `${projectName}-payment-service-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import random
import time
from datetime import datetime
import os

dynamodb = boto3.resource('dynamodb')
eventbridge = boto3.client('events')

def lambda_handler(event, context):
    try:
        # Parse payment data
        payment_data = event['detail'] if 'detail' in event else event
        order_id = payment_data['orderId']
        amount = payment_data['totalAmount']
        
        # Simulate payment processing delay
        time.sleep(2)
        
        # Simulate payment success/failure (90% success rate)
        payment_successful = random.random() < 0.9
        
        # Update order status
        table = dynamodb.Table(os.environ['DYNAMODB_TABLE_NAME'])
        
        if payment_successful:
            table.update_item(
                Key={'orderId': order_id, 'customerId': payment_data['customerId']},
                UpdateExpression='SET #status = :status, paymentId = :paymentId, updatedAt = :updatedAt',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={
                    ':status': 'PAID',
                    ':paymentId': f'pay_{order_id[:8]}',
                    ':updatedAt': datetime.utcnow().isoformat()
                }
            )
            
            # Publish payment success event
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'payment.service',
                        'DetailType': 'Payment Processed',
                        'Detail': json.dumps({
                            'orderId': order_id,
                            'paymentId': f'pay_{order_id[:8]}',
                            'amount': amount,
                            'status': 'SUCCESS'
                        }),
                        'EventBusName': os.environ['EVENTBUS_NAME']
                    }
                ]
            )
        else:
            table.update_item(
                Key={'orderId': order_id, 'customerId': payment_data['customerId']},
                UpdateExpression='SET #status = :status, updatedAt = :updatedAt',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={
                    ':status': 'PAYMENT_FAILED',
                    ':updatedAt': datetime.utcnow().isoformat()
                }
            )
            
            # Publish payment failure event
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'payment.service',
                        'DetailType': 'Payment Failed',
                        'Detail': json.dumps({
                            'orderId': order_id,
                            'amount': amount,
                            'status': 'FAILED'
                        }),
                        'EventBusName': os.environ['EVENTBUS_NAME']
                    }
                ]
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'orderId': order_id,
                'paymentStatus': 'SUCCESS' if payment_successful else 'FAILED'
            })
        }
        
    except Exception as e:
        print(f"Error processing payment: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
      `),
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      environment: {
        EVENTBUS_NAME: eventBus.eventBusName,
        DYNAMODB_TABLE_NAME: ordersTable.tableName,
      },
    });

    // Inventory Service Lambda Function
    const inventoryService = new lambda.Function(this, 'InventoryService', {
      functionName: `${projectName}-inventory-service-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import random
from datetime import datetime
import os

dynamodb = boto3.resource('dynamodb')
eventbridge = boto3.client('events')

def lambda_handler(event, context):
    try:
        # Parse inventory data
        inventory_data = event['detail'] if 'detail' in event else event
        order_id = inventory_data['orderId']
        items = inventory_data['items']
        
        # Simulate inventory check (95% success rate)
        inventory_available = random.random() < 0.95
        
        # Update order status
        table = dynamodb.Table(os.environ['DYNAMODB_TABLE_NAME'])
        
        if inventory_available:
            table.update_item(
                Key={'orderId': order_id, 'customerId': inventory_data['customerId']},
                UpdateExpression='SET #status = :status, updatedAt = :updatedAt',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={
                    ':status': 'INVENTORY_RESERVED',
                    ':updatedAt': datetime.utcnow().isoformat()
                }
            )
            
            # Publish inventory reserved event
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'inventory.service',
                        'DetailType': 'Inventory Reserved',
                        'Detail': json.dumps({
                            'orderId': order_id,
                            'items': items,
                            'status': 'RESERVED'
                        }),
                        'EventBusName': os.environ['EVENTBUS_NAME']
                    }
                ]
            )
        else:
            table.update_item(
                Key={'orderId': order_id, 'customerId': inventory_data['customerId']},
                UpdateExpression='SET #status = :status, updatedAt = :updatedAt',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={
                    ':status': 'INVENTORY_UNAVAILABLE',
                    ':updatedAt': datetime.utcnow().isoformat()
                }
            )
            
            # Publish inventory unavailable event
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'inventory.service',
                        'DetailType': 'Inventory Unavailable',
                        'Detail': json.dumps({
                            'orderId': order_id,
                            'items': items,
                            'status': 'UNAVAILABLE'
                        }),
                        'EventBusName': os.environ['EVENTBUS_NAME']
                    }
                ]
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'orderId': order_id,
                'inventoryStatus': 'RESERVED' if inventory_available else 'UNAVAILABLE'
            })
        }
        
    except Exception as e:
        print(f"Error processing inventory: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
      `),
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      environment: {
        EVENTBUS_NAME: eventBus.eventBusName,
        DYNAMODB_TABLE_NAME: ordersTable.tableName,
      },
    });

    // Notification Service Lambda Function
    const notificationService = new lambda.Function(this, 'NotificationService', {
      functionName: `${projectName}-notification-service-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
from datetime import datetime

def lambda_handler(event, context):
    try:
        # Parse notification data
        notification_data = event['detail'] if 'detail' in event else event
        
        # Log notification (in real scenario, send email/SMS)
        print(f"NOTIFICATION: {json.dumps(notification_data, indent=2)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Notification sent successfully',
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        print(f"Error sending notification: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
      `),
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
    });

    // =============================================================================
    // CloudWatch Log Group for Step Functions
    // =============================================================================
    
    const stepFunctionsLogGroup = new logs.LogGroup(this, 'StepFunctionsLogGroup', {
      logGroupName: `/aws/stepfunctions/${projectName}-order-processing-${uniqueSuffix}`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // =============================================================================
    // Step Functions State Machine
    // =============================================================================
    
    // Define individual states
    const processPayment = new tasks.LambdaInvoke(this, 'ProcessPayment', {
      lambdaFunction: paymentService,
      outputPath: '$',
      retryOnServiceExceptions: true,
    });

    const reserveInventory = new tasks.LambdaInvoke(this, 'ReserveInventory', {
      lambdaFunction: inventoryService,
      outputPath: '$',
      retryOnServiceExceptions: true,
    });

    const sendSuccessNotification = new tasks.LambdaInvoke(this, 'SendSuccessNotification', {
      lambdaFunction: notificationService,
      payload: stepfunctions.TaskInput.fromObject({
        message: 'Order processed successfully',
        'orderId.$': '$.detail.orderId',
        status: 'COMPLETED',
      }),
    });

    const sendPaymentFailedNotification = new tasks.LambdaInvoke(this, 'SendPaymentFailedNotification', {
      lambdaFunction: notificationService,
      payload: stepfunctions.TaskInput.fromObject({
        message: 'Payment failed',
        'orderId.$': '$.detail.orderId',
        status: 'PAYMENT_FAILED',
      }),
    });

    const sendInventoryFailedNotification = new tasks.LambdaInvoke(this, 'SendInventoryFailedNotification', {
      lambdaFunction: notificationService,
      payload: stepfunctions.TaskInput.fromObject({
        message: 'Inventory unavailable',
        'orderId.$': '$.detail.orderId',
        status: 'INVENTORY_FAILED',
      }),
    });

    // Define choice conditions
    const checkPaymentStatus = new stepfunctions.Choice(this, 'CheckPaymentStatus')
      .when(
        stepfunctions.Condition.stringMatches('$.Payload.body', '*SUCCESS*'),
        reserveInventory
      )
      .otherwise(sendPaymentFailedNotification);

    const checkInventoryStatus = new stepfunctions.Choice(this, 'CheckInventoryStatus')
      .when(
        stepfunctions.Condition.stringMatches('$.Payload.body', '*RESERVED*'),
        sendSuccessNotification
      )
      .otherwise(sendInventoryFailedNotification);

    // Define the workflow
    const definition = processPayment
      .addRetry({
        errors: ['Lambda.ServiceException', 'Lambda.AWSLambdaException', 'Lambda.SdkClientException'],
        interval: cdk.Duration.seconds(2),
        maxAttempts: 6,
        backoffRate: 2,
      })
      .addCatch(sendPaymentFailedNotification, {
        errors: ['States.ALL'],
        resultPath: '$.error',
      })
      .next(checkPaymentStatus);

    reserveInventory
      .addRetry({
        errors: ['Lambda.ServiceException', 'Lambda.AWSLambdaException', 'Lambda.SdkClientException'],
        interval: cdk.Duration.seconds(2),
        maxAttempts: 3,
        backoffRate: 2,
      })
      .addCatch(sendInventoryFailedNotification, {
        errors: ['States.ALL'],
        resultPath: '$.error',
      })
      .next(checkInventoryStatus);

    // Create the state machine
    const stateMachine = new stepfunctions.StateMachine(this, 'OrderProcessingStateMachine', {
      stateMachineName: `${projectName}-order-processing-${uniqueSuffix}`,
      definition,
      role: stepFunctionsExecutionRole,
      logs: {
        destination: stepFunctionsLogGroup,
        level: stepfunctions.LogLevel.ALL,
        includeExecutionData: true,
      },
    });

    // =============================================================================
    // EventBridge Rules and Targets
    // =============================================================================
    
    // Rule for Order Created events
    const orderCreatedRule = new events.Rule(this, 'OrderCreatedRule', {
      ruleName: `${projectName}-order-created-rule-${uniqueSuffix}`,
      eventBus,
      eventPattern: {
        source: ['order.service'],
        detailType: ['Order Created'],
      },
      description: 'Route Order Created events to Step Functions workflow',
    });

    // Add Step Functions as target for order created events
    orderCreatedRule.addTarget(new targets.SfnStateMachine(stateMachine, {
      role: stepFunctionsExecutionRole,
    }));

    // Rule for Payment events
    const paymentEventsRule = new events.Rule(this, 'PaymentEventsRule', {
      ruleName: `${projectName}-payment-events-rule-${uniqueSuffix}`,
      eventBus,
      eventPattern: {
        source: ['payment.service'],
        detailType: ['Payment Processed', 'Payment Failed'],
      },
      description: 'Route Payment events to Notification Service',
    });

    // Add Lambda as target for payment events
    paymentEventsRule.addTarget(new targets.LambdaFunction(notificationService));

    // =============================================================================
    // CloudWatch Dashboard
    // =============================================================================
    
    const dashboard = new cloudwatch.Dashboard(this, 'MicroservicesDashboard', {
      dashboardName: `${projectName}-microservices-dashboard-${uniqueSuffix}`,
    });

    // Lambda invocations widget
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Lambda Invocations',
        left: [
          orderService.metricInvocations(),
          paymentService.metricInvocations(),
          inventoryService.metricInvocations(),
          notificationService.metricInvocations(),
        ],
        period: cdk.Duration.minutes(5),
        statistic: 'Sum',
      })
    );

    // Step Functions executions widget
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Step Functions Executions',
        left: [
          stateMachine.metricSucceeded(),
          stateMachine.metricFailed(),
        ],
        period: cdk.Duration.minutes(5),
        statistic: 'Sum',
      })
    );

    // Lambda errors widget
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Lambda Errors',
        left: [
          orderService.metricErrors(),
          paymentService.metricErrors(),
          inventoryService.metricErrors(),
          notificationService.metricErrors(),
        ],
        period: cdk.Duration.minutes(5),
        statistic: 'Sum',
      })
    );

    // =============================================================================
    // Stack Outputs
    // =============================================================================
    
    new cdk.CfnOutput(this, 'EventBusName', {
      value: eventBus.eventBusName,
      description: 'Name of the custom EventBridge event bus',
    });

    new cdk.CfnOutput(this, 'EventBusArn', {
      value: eventBus.eventBusArn,
      description: 'ARN of the custom EventBridge event bus',
    });

    new cdk.CfnOutput(this, 'DynamoDBTableName', {
      value: ordersTable.tableName,
      description: 'Name of the DynamoDB orders table',
    });

    new cdk.CfnOutput(this, 'StateMachineArn', {
      value: stateMachine.stateMachineArn,
      description: 'ARN of the Step Functions state machine',
    });

    new cdk.CfnOutput(this, 'OrderServiceName', {
      value: orderService.functionName,
      description: 'Name of the Order Service Lambda function',
    });

    new cdk.CfnOutput(this, 'PaymentServiceName', {
      value: paymentService.functionName,
      description: 'Name of the Payment Service Lambda function',
    });

    new cdk.CfnOutput(this, 'InventoryServiceName', {
      value: inventoryService.functionName,
      description: 'Name of the Inventory Service Lambda function',
    });

    new cdk.CfnOutput(this, 'NotificationServiceName', {
      value: notificationService.functionName,
      description: 'Name of the Notification Service Lambda function',
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://${cdk.Stack.of(this).region}.console.aws.amazon.com/cloudwatch/home?region=${cdk.Stack.of(this).region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard',
    });
  }
}