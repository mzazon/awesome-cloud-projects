#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as stepfunctions from 'aws-cdk-lib/aws-stepfunctions';
import * as stepfunctionsTasks from 'aws-cdk-lib/aws-stepfunctions-tasks';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Duration } from 'aws-cdk-lib';

/**
 * CDK Stack for Orchestrating Distributed Transactions with Saga Patterns
 * 
 * This stack creates a complete e-commerce transaction processing system using the saga pattern:
 * - Step Functions orchestrates distributed transactions across multiple microservices
 * - Lambda functions handle business logic (order, inventory, payment, notification)
 * - DynamoDB tables store service-specific data
 * - SNS provides notification capabilities
 * - API Gateway exposes REST endpoints for transaction initiation
 * - Compensation functions handle rollback scenarios
 */
export class SagaPatternStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate a unique suffix for resource names to avoid conflicts
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // ========================================
    // DynamoDB Tables for Business Services
    // ========================================

    // Order service table - stores order information
    const orderTable = new dynamodb.Table(this, 'OrderTable', {
      tableName: `saga-orders-${uniqueSuffix}`,
      partitionKey: {
        name: 'orderId',
        type: dynamodb.AttributeType.STRING
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      pointInTimeRecovery: true
    });

    // Inventory service table - manages product inventory with reservations
    const inventoryTable = new dynamodb.Table(this, 'InventoryTable', {
      tableName: `saga-inventory-${uniqueSuffix}`,
      partitionKey: {
        name: 'productId',
        type: dynamodb.AttributeType.STRING
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      pointInTimeRecovery: true
    });

    // Payment service table - handles payment processing and refunds
    const paymentTable = new dynamodb.Table(this, 'PaymentTable', {
      tableName: `saga-payments-${uniqueSuffix}`,
      partitionKey: {
        name: 'paymentId',
        type: dynamodb.AttributeType.STRING
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      pointInTimeRecovery: true
    });

    // ========================================
    // SNS Topic for Notifications
    // ========================================

    const notificationTopic = new sns.Topic(this, 'NotificationTopic', {
      topicName: `saga-notifications-${uniqueSuffix}`,
      displayName: 'Saga Transaction Notifications'
    });

    // ========================================
    // IAM Role for Lambda Functions
    // ========================================

    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for saga pattern Lambda functions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
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
                'dynamodb:Scan'
              ],
              resources: [
                orderTable.tableArn,
                inventoryTable.tableArn,
                paymentTable.tableArn
              ]
            })
          ]
        }),
        SNSPublish: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sns:Publish'],
              resources: [notificationTopic.topicArn]
            })
          ]
        })
      }
    });

    // ========================================
    // Business Service Lambda Functions
    // ========================================

    // Order Service - creates new orders
    const orderServiceFunction = new lambda.Function(this, 'OrderService', {
      functionName: `saga-order-service-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
from datetime import datetime

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        table_name = event['tableName']
        table = dynamodb.Table(table_name)
        
        order_id = str(uuid.uuid4())
        order_data = {
            'orderId': order_id,
            'customerId': event['customerId'],
            'productId': event['productId'],
            'quantity': event['quantity'],
            'status': 'PENDING',
            'timestamp': datetime.utcnow().isoformat()
        }
        
        table.put_item(Item=order_data)
        
        return {
            'statusCode': 200,
            'status': 'ORDER_PLACED',
            'orderId': order_id,
            'message': 'Order placed successfully'
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'status': 'ORDER_FAILED',
            'error': str(e)
        }
      `),
      role: lambdaRole,
      timeout: Duration.seconds(30),
      environment: {
        'TABLE_NAME': orderTable.tableName
      }
    });

    // Inventory Service - manages product inventory with reservations
    const inventoryServiceFunction = new lambda.Function(this, 'InventoryService', {
      functionName: `saga-inventory-service-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        table_name = event['tableName']
        table = dynamodb.Table(table_name)
        
        product_id = event['productId']
        quantity_needed = int(event['quantity'])
        
        # Get current inventory
        response = table.get_item(Key={'productId': product_id})
        
        if 'Item' not in response:
            return {
                'statusCode': 404,
                'status': 'INVENTORY_NOT_FOUND',
                'message': 'Product not found in inventory'
            }
        
        item = response['Item']
        available_quantity = int(item['quantity']) - int(item.get('reserved', 0))
        
        if available_quantity < quantity_needed:
            return {
                'statusCode': 400,
                'status': 'INSUFFICIENT_INVENTORY',
                'message': f'Only {available_quantity} items available'
            }
        
        # Reserve inventory
        table.update_item(
            Key={'productId': product_id},
            UpdateExpression='SET reserved = reserved + :qty',
            ExpressionAttributeValues={':qty': quantity_needed}
        )
        
        return {
            'statusCode': 200,
            'status': 'INVENTORY_RESERVED',
            'productId': product_id,
            'quantity': quantity_needed,
            'message': 'Inventory reserved successfully'
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'status': 'INVENTORY_FAILED',
            'error': str(e)
        }
      `),
      role: lambdaRole,
      timeout: Duration.seconds(30),
      environment: {
        'TABLE_NAME': inventoryTable.tableName
      }
    });

    // Payment Service - processes payments with simulated failure rate
    const paymentServiceFunction = new lambda.Function(this, 'PaymentService', {
      functionName: `saga-payment-service-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
import random
from datetime import datetime

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        table_name = event['tableName']
        table = dynamodb.Table(table_name)
        
        # Simulate payment processing with 20% failure rate
        if random.random() < 0.2:
            return {
                'statusCode': 400,
                'status': 'PAYMENT_FAILED',
                'message': 'Payment processing failed'
            }
        
        payment_id = str(uuid.uuid4())
        payment_data = {
            'paymentId': payment_id,
            'orderId': event['orderId'],
            'customerId': event['customerId'],
            'amount': event['amount'],
            'status': 'COMPLETED',
            'timestamp': datetime.utcnow().isoformat()
        }
        
        table.put_item(Item=payment_data)
        
        return {
            'statusCode': 200,
            'status': 'PAYMENT_COMPLETED',
            'paymentId': payment_id,
            'amount': event['amount'],
            'message': 'Payment processed successfully'
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'status': 'PAYMENT_FAILED',
            'error': str(e)
        }
      `),
      role: lambdaRole,
      timeout: Duration.seconds(30),
      environment: {
        'TABLE_NAME': paymentTable.tableName
      }
    });

    // Notification Service - sends notifications via SNS
    const notificationServiceFunction = new lambda.Function(this, 'NotificationService', {
      functionName: `saga-notification-service-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3

sns = boto3.client('sns')

def lambda_handler(event, context):
    try:
        topic_arn = event['topicArn']
        message = event['message']
        subject = event.get('subject', 'Order Notification')
        
        response = sns.publish(
            TopicArn=topic_arn,
            Subject=subject,
            Message=json.dumps(message, indent=2)
        )
        
        return {
            'statusCode': 200,
            'status': 'NOTIFICATION_SENT',
            'messageId': response['MessageId'],
            'message': 'Notification sent successfully'
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'status': 'NOTIFICATION_FAILED',
            'error': str(e)
        }
      `),
      role: lambdaRole,
      timeout: Duration.seconds(30),
      environment: {
        'TOPIC_ARN': notificationTopic.topicArn
      }
    });

    // ========================================
    // Compensation Lambda Functions
    // ========================================

    // Cancel Order - compensation for order placement
    const cancelOrderFunction = new lambda.Function(this, 'CancelOrderFunction', {
      functionName: `saga-cancel-order-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        table_name = event['tableName']
        table = dynamodb.Table(table_name)
        
        order_id = event['orderId']
        
        # Update order status to cancelled
        table.update_item(
            Key={'orderId': order_id},
            UpdateExpression='SET #status = :status',
            ExpressionAttributeNames={'#status': 'status'},
            ExpressionAttributeValues={':status': 'CANCELLED'}
        )
        
        return {
            'statusCode': 200,
            'status': 'ORDER_CANCELLED',
            'orderId': order_id,
            'message': 'Order cancelled successfully'
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'status': 'CANCELLATION_FAILED',
            'error': str(e)
        }
      `),
      role: lambdaRole,
      timeout: Duration.seconds(30),
      environment: {
        'TABLE_NAME': orderTable.tableName
      }
    });

    // Revert Inventory - compensation for inventory reservation
    const revertInventoryFunction = new lambda.Function(this, 'RevertInventoryFunction', {
      functionName: `saga-revert-inventory-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        table_name = event['tableName']
        table = dynamodb.Table(table_name)
        
        product_id = event['productId']
        quantity = int(event['quantity'])
        
        # Release reserved inventory
        table.update_item(
            Key={'productId': product_id},
            UpdateExpression='SET reserved = reserved - :qty',
            ExpressionAttributeValues={':qty': quantity}
        )
        
        return {
            'statusCode': 200,
            'status': 'INVENTORY_REVERTED',
            'productId': product_id,
            'quantity': quantity,
            'message': 'Inventory reservation reverted'
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'status': 'REVERT_FAILED',
            'error': str(e)
        }
      `),
      role: lambdaRole,
      timeout: Duration.seconds(30),
      environment: {
        'TABLE_NAME': inventoryTable.tableName
      }
    });

    // Refund Payment - compensation for payment processing
    const refundPaymentFunction = new lambda.Function(this, 'RefundPaymentFunction', {
      functionName: `saga-refund-payment-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
from datetime import datetime

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        table_name = event['tableName']
        table = dynamodb.Table(table_name)
        
        # Create refund record
        refund_id = str(uuid.uuid4())
        refund_data = {
            'paymentId': refund_id,
            'originalPaymentId': event['paymentId'],
            'orderId': event['orderId'],
            'customerId': event['customerId'],
            'amount': event['amount'],
            'status': 'REFUNDED',
            'type': 'REFUND',
            'timestamp': datetime.utcnow().isoformat()
        }
        
        table.put_item(Item=refund_data)
        
        return {
            'statusCode': 200,
            'status': 'PAYMENT_REFUNDED',
            'refundId': refund_id,
            'amount': event['amount'],
            'message': 'Payment refunded successfully'
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'status': 'REFUND_FAILED',
            'error': str(e)
        }
      `),
      role: lambdaRole,
      timeout: Duration.seconds(30),
      environment: {
        'TABLE_NAME': paymentTable.tableName
      }
    });

    // ========================================
    // CloudWatch Log Group for Step Functions
    // ========================================

    const sagaLogGroup = new logs.LogGroup(this, 'SagaLogGroup', {
      logGroupName: `/aws/stepfunctions/saga-orchestrator-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // ========================================
    // Step Functions State Machine Definition
    // ========================================

    // Define the saga orchestration workflow
    const placeOrderTask = new stepfunctionsTasks.LambdaInvoke(this, 'PlaceOrderTask', {
      lambdaFunction: orderServiceFunction,
      inputPath: '$',
      resultPath: '$.orderResult',
      payload: stepfunctions.TaskInput.fromObject({
        tableName: orderTable.tableName,
        'customerId.$': '$.customerId',
        'productId.$': '$.productId',
        'quantity.$': '$.quantity'
      }),
      retryOnServiceExceptions: true
    });

    const reserveInventoryTask = new stepfunctionsTasks.LambdaInvoke(this, 'ReserveInventoryTask', {
      lambdaFunction: inventoryServiceFunction,
      inputPath: '$',
      resultPath: '$.inventoryResult',
      payload: stepfunctions.TaskInput.fromObject({
        tableName: inventoryTable.tableName,
        'productId.$': '$.productId',
        'quantity.$': '$.quantity'
      }),
      retryOnServiceExceptions: true
    });

    const processPaymentTask = new stepfunctionsTasks.LambdaInvoke(this, 'ProcessPaymentTask', {
      lambdaFunction: paymentServiceFunction,
      inputPath: '$',
      resultPath: '$.paymentResult',
      payload: stepfunctions.TaskInput.fromObject({
        tableName: paymentTable.tableName,
        'orderId.$': '$.orderResult.Payload.orderId',
        'customerId.$': '$.customerId',
        'amount.$': '$.amount'
      }),
      retryOnServiceExceptions: true
    });

    const sendSuccessNotificationTask = new stepfunctionsTasks.LambdaInvoke(this, 'SendSuccessNotificationTask', {
      lambdaFunction: notificationServiceFunction,
      inputPath: '$',
      resultPath: '$.notificationResult',
      payload: stepfunctions.TaskInput.fromObject({
        topicArn: notificationTopic.topicArn,
        subject: 'Order Completed Successfully',
        message: {
          'orderId.$': '$.orderResult.Payload.orderId',
          'customerId.$': '$.customerId',
          status: 'SUCCESS',
          details: 'Your order has been processed successfully'
        }
      })
    });

    const sendFailureNotificationTask = new stepfunctionsTasks.LambdaInvoke(this, 'SendFailureNotificationTask', {
      lambdaFunction: notificationServiceFunction,
      inputPath: '$',
      resultPath: '$.notificationResult',
      payload: stepfunctions.TaskInput.fromObject({
        topicArn: notificationTopic.topicArn,
        subject: 'Order Processing Failed',
        message: {
          'orderId.$': '$.orderResult.Payload.orderId',
          'customerId.$': '$.customerId',
          status: 'FAILED',
          details: 'Your order could not be processed and has been cancelled'
        }
      })
    });

    const sendOrderFailedNotificationTask = new stepfunctionsTasks.LambdaInvoke(this, 'SendOrderFailedNotificationTask', {
      lambdaFunction: notificationServiceFunction,
      inputPath: '$',
      resultPath: '$.notificationResult',
      payload: stepfunctions.TaskInput.fromObject({
        topicArn: notificationTopic.topicArn,
        subject: 'Order Creation Failed',
        message: {
          'customerId.$': '$.customerId',
          status: 'FAILED',
          details: 'Order creation failed'
        }
      })
    });

    // Compensation tasks
    const cancelOrderTask = new stepfunctionsTasks.LambdaInvoke(this, 'CancelOrderTask', {
      lambdaFunction: cancelOrderFunction,
      inputPath: '$',
      resultPath: '$.cancelResult',
      payload: stepfunctions.TaskInput.fromObject({
        tableName: orderTable.tableName,
        'orderId.$': '$.orderResult.Payload.orderId'
      })
    });

    const revertInventoryTask = new stepfunctionsTasks.LambdaInvoke(this, 'RevertInventoryTask', {
      lambdaFunction: revertInventoryFunction,
      inputPath: '$',
      resultPath: '$.revertResult',
      payload: stepfunctions.TaskInput.fromObject({
        tableName: inventoryTable.tableName,
        'productId.$': '$.productId',
        'quantity.$': '$.quantity'
      })
    });

    const refundPaymentTask = new stepfunctionsTasks.LambdaInvoke(this, 'RefundPaymentTask', {
      lambdaFunction: refundPaymentFunction,
      inputPath: '$',
      resultPath: '$.refundResult',
      payload: stepfunctions.TaskInput.fromObject({
        tableName: paymentTable.tableName,
        'paymentId.$': '$.paymentResult.Payload.paymentId',
        'orderId.$': '$.orderResult.Payload.orderId',
        'customerId.$': '$.customerId',
        'amount.$': '$.amount'
      })
    });

    // Define choice conditions
    const orderStatusChoice = new stepfunctions.Choice(this, 'CheckOrderStatus')
      .when(
        stepfunctions.Condition.stringEquals('$.orderResult.Payload.status', 'ORDER_PLACED'),
        reserveInventoryTask
      )
      .otherwise(sendOrderFailedNotificationTask);

    const inventoryStatusChoice = new stepfunctions.Choice(this, 'CheckInventoryStatus')
      .when(
        stepfunctions.Condition.stringEquals('$.inventoryResult.Payload.status', 'INVENTORY_RESERVED'),
        processPaymentTask
      )
      .otherwise(cancelOrderTask);

    const paymentStatusChoice = new stepfunctions.Choice(this, 'CheckPaymentStatus')
      .when(
        stepfunctions.Condition.stringEquals('$.paymentResult.Payload.status', 'PAYMENT_COMPLETED'),
        sendSuccessNotificationTask
      )
      .otherwise(revertInventoryTask);

    // Define terminal states
    const successState = new stepfunctions.Pass(this, 'TransactionSuccess', {
      result: stepfunctions.Result.fromObject({
        status: 'SUCCESS',
        message: 'Transaction completed successfully'
      })
    });

    const failureState = new stepfunctions.Pass(this, 'TransactionFailed', {
      result: stepfunctions.Result.fromObject({
        status: 'FAILED',
        message: 'Transaction failed and compensations completed'
      })
    });

    const compensationFailedState = new stepfunctions.Pass(this, 'CompensationFailed', {
      result: stepfunctions.Result.fromObject({
        status: 'COMPENSATION_FAILED',
        message: 'Transaction failed and compensation actions also failed'
      })
    });

    // Chain the workflow together
    const definition = placeOrderTask
      .next(orderStatusChoice)
      .next(inventoryStatusChoice)
      .next(paymentStatusChoice)
      .next(sendSuccessNotificationTask)
      .next(successState);

    // Add compensation flows
    revertInventoryTask.next(cancelOrderTask);
    cancelOrderTask.next(refundPaymentTask);
    refundPaymentTask.next(sendFailureNotificationTask);
    sendFailureNotificationTask.next(failureState);
    sendOrderFailedNotificationTask.next(failureState);

    // Add error handling for compensation failures
    const compensationErrorHandler = stepfunctions.Catch.errors('States.ALL')
      .next(compensationFailedState);

    revertInventoryTask.addCatch(compensationErrorHandler);
    cancelOrderTask.addCatch(compensationErrorHandler);
    refundPaymentTask.addCatch(compensationErrorHandler);

    // Create IAM role for Step Functions
    const stepFunctionsRole = new iam.Role(this, 'StepFunctionsRole', {
      assumedBy: new iam.ServicePrincipal('states.amazonaws.com'),
      description: 'Execution role for Saga orchestrator Step Functions',
      inlinePolicies: {
        LambdaInvoke: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['lambda:InvokeFunction'],
              resources: [
                orderServiceFunction.functionArn,
                inventoryServiceFunction.functionArn,
                paymentServiceFunction.functionArn,
                notificationServiceFunction.functionArn,
                cancelOrderFunction.functionArn,
                revertInventoryFunction.functionArn,
                refundPaymentFunction.functionArn
              ]
            })
          ]
        }),
        CloudWatchLogs: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogDelivery',
                'logs:GetLogDelivery',
                'logs:UpdateLogDelivery',
                'logs:DeleteLogDelivery',
                'logs:ListLogDeliveries',
                'logs:PutResourcePolicy',
                'logs:DescribeResourcePolicies',
                'logs:DescribeLogGroups'
              ],
              resources: ['*']
            })
          ]
        })
      }
    });

    // Create the Step Functions state machine
    const sagaStateMachine = new stepfunctions.StateMachine(this, 'SagaStateMachine', {
      stateMachineName: `saga-orchestrator-${uniqueSuffix}`,
      definitionBody: stepfunctions.DefinitionBody.fromChainable(definition),
      role: stepFunctionsRole,
      logs: {
        destination: sagaLogGroup,
        level: stepfunctions.LogLevel.ALL,
        includeExecutionData: true
      }
    });

    // ========================================
    // API Gateway for Saga Initiation
    // ========================================

    // Create IAM role for API Gateway to invoke Step Functions
    const apiGatewayRole = new iam.Role(this, 'ApiGatewayRole', {
      assumedBy: new iam.ServicePrincipal('apigateway.amazonaws.com'),
      description: 'Role for API Gateway to invoke Step Functions',
      inlinePolicies: {
        StepFunctionsAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['states:StartExecution'],
              resources: [sagaStateMachine.stateMachineArn]
            })
          ]
        })
      }
    });

    // Create API Gateway
    const api = new apigateway.RestApi(this, 'SagaApi', {
      restApiName: `saga-api-${uniqueSuffix}`,
      description: 'API for initiating saga transactions',
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key']
      }
    });

    // Create orders resource
    const ordersResource = api.root.addResource('orders');

    // Create Step Functions integration
    const stepFunctionsIntegration = new apigateway.Integration({
      type: apigateway.IntegrationType.AWS,
      integrationHttpMethod: 'POST',
      uri: `arn:aws:apigateway:${this.region}:states:action/StartExecution`,
      options: {
        credentialsRole: apiGatewayRole,
        requestTemplates: {
          'application/json': JSON.stringify({
            stateMachineArn: sagaStateMachine.stateMachineArn,
            input: '$util.escapeJavaScript($input.body)'
          })
        },
        integrationResponses: [
          {
            statusCode: '200',
            responseTemplates: {
              'application/json': JSON.stringify({
                executionArn: '$input.path("$.executionArn")',
                startDate: '$input.path("$.startDate")'
              })
            }
          }
        ]
      }
    });

    // Add POST method to orders resource
    ordersResource.addMethod('POST', stepFunctionsIntegration, {
      methodResponses: [
        {
          statusCode: '200',
          responseModels: {
            'application/json': apigateway.Model.EMPTY_MODEL
          }
        }
      ]
    });

    // ========================================
    // Initialize Sample Data
    // ========================================

    // Custom resource to populate inventory table with sample data
    const initDataFunction = new lambda.Function(this, 'InitDataFunction', {
      functionName: `saga-init-data-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import boto3
import json

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        table_name = event['ResourceProperties']['TableName']
        table = dynamodb.Table(table_name)
        
        # Sample inventory items
        items = [
            {
                'productId': 'laptop-001',
                'quantity': 10,
                'price': 999.99,
                'reserved': 0
            },
            {
                'productId': 'phone-002',
                'quantity': 25,
                'price': 599.99,
                'reserved': 0
            },
            {
                'productId': 'tablet-003',
                'quantity': 15,
                'price': 399.99,
                'reserved': 0
            }
        ]
        
        # Insert sample data
        for item in items:
            table.put_item(Item=item)
        
        return {
            'Status': 'SUCCESS',
            'PhysicalResourceId': 'InitInventoryData'
        }
        
    except Exception as e:
        return {
            'Status': 'FAILED',
            'Reason': str(e),
            'PhysicalResourceId': 'InitInventoryData'
        }
      `),
      role: lambdaRole,
      timeout: Duration.seconds(60)
    });

    // Custom resource to initialize inventory data
    const initInventoryData = new cdk.CustomResource(this, 'InitInventoryData', {
      serviceToken: initDataFunction.functionArn,
      properties: {
        TableName: inventoryTable.tableName
      }
    });

    // Make sure the inventory table is created before initializing data
    initInventoryData.node.addDependency(inventoryTable);

    // ========================================
    // Outputs
    // ========================================

    new cdk.CfnOutput(this, 'ApiEndpoint', {
      value: api.url,
      description: 'API Gateway endpoint URL for initiating saga transactions'
    });

    new cdk.CfnOutput(this, 'StateMachineArn', {
      value: sagaStateMachine.stateMachineArn,
      description: 'Step Functions state machine ARN'
    });

    new cdk.CfnOutput(this, 'OrderTableName', {
      value: orderTable.tableName,
      description: 'DynamoDB table name for orders'
    });

    new cdk.CfnOutput(this, 'InventoryTableName', {
      value: inventoryTable.tableName,
      description: 'DynamoDB table name for inventory'
    });

    new cdk.CfnOutput(this, 'PaymentTableName', {
      value: paymentTable.tableName,
      description: 'DynamoDB table name for payments'
    });

    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: notificationTopic.topicArn,
      description: 'SNS topic ARN for notifications'
    });

    new cdk.CfnOutput(this, 'SampleCurlCommand', {
      value: `curl -X POST ${api.url}orders -H "Content-Type: application/json" -d '{"customerId": "customer-123", "productId": "laptop-001", "quantity": 2, "amount": 1999.98}'`,
      description: 'Sample curl command to test the saga pattern'
    });
  }
}

// CDK App
const app = new cdk.App();

new SagaPatternStack(app, 'SagaPatternStack', {
  description: 'Saga Pattern implementation with Step Functions for distributed transactions',
  tags: {
    Project: 'SagaPattern',
    Environment: 'Demo',
    Purpose: 'DistributedTransactions'
  }
});