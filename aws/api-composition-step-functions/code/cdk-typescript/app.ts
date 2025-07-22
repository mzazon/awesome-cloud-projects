#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as stepfunctions from 'aws-cdk-lib/aws-stepfunctions';
import * as stepfunctionsTasks from 'aws-cdk-lib/aws-stepfunctions-tasks';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * CDK Stack for API Composition with Step Functions and API Gateway
 * 
 * This stack demonstrates advanced API composition patterns using Step Functions
 * to orchestrate multiple microservices through API Gateway. The solution addresses
 * key challenges in microservices architecture including service coordination,
 * error handling, and transaction management.
 */
export class ApiCompositionStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = this.node.tryGetContext('uniqueSuffix') || 
                        Math.random().toString(36).substring(2, 8);

    // ========================================
    // DynamoDB Tables for Data Storage
    // ========================================

    // Orders table for storing order information
    const ordersTable = new dynamodb.Table(this, 'OrdersTable', {
      tableName: `api-composition-${uniqueSuffix}-orders`,
      partitionKey: { 
        name: 'orderId', 
        type: dynamodb.AttributeType.STRING 
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    // Audit table for tracking workflow executions and compensation actions
    const auditTable = new dynamodb.Table(this, 'AuditTable', {
      tableName: `api-composition-${uniqueSuffix}-audit`,
      partitionKey: { 
        name: 'auditId', 
        type: dynamodb.AttributeType.STRING 
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    // Reservations table for inventory management and compensation logic
    const reservationsTable = new dynamodb.Table(this, 'ReservationsTable', {
      tableName: `api-composition-${uniqueSuffix}-reservations`,
      partitionKey: { 
        name: 'orderId', 
        type: dynamodb.AttributeType.STRING 
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    // ========================================
    // Lambda Functions for Microservices
    // ========================================

    // User validation service - validates user credentials and retrieves user data
    const userService = new lambda.Function(this, 'UserService', {
      functionName: `${uniqueSuffix}-user-service`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.seconds(30),
      memorySize: 128,
      code: lambda.Code.fromInline(`
import json
import random

def lambda_handler(event, context):
    """
    User validation service that simulates user authentication and data retrieval.
    In production, this would integrate with identity providers or user databases.
    """
    user_id = event.get('userId', '')
    
    # Mock user validation logic
    if not user_id or len(user_id) < 3:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'valid': False,
                'error': 'Invalid user ID'
            })
        }
    
    # Simulate user data retrieval with realistic business data
    user_data = {
        'valid': True,
        'userId': user_id,
        'name': f'User {user_id}',
        'email': f'{user_id}@example.com',
        'creditLimit': random.randint(1000, 5000),
        'accountStatus': 'active'
    }
    
    return {
        'statusCode': 200,
        'body': json.dumps(user_data)
    }
      `),
      environment: {
        'LOG_LEVEL': 'INFO'
      }
    });

    // Inventory service - checks product availability and manages stock levels
    const inventoryService = new lambda.Function(this, 'InventoryService', {
      functionName: `${uniqueSuffix}-inventory-service`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.seconds(30),
      memorySize: 128,
      code: lambda.Code.fromInline(`
import json
import random

def lambda_handler(event, context):
    """
    Inventory service that checks product availability and calculates pricing.
    In production, this would integrate with inventory management systems.
    """
    items = event.get('items', [])
    
    inventory_status = []
    total_amount = 0
    
    for item in items:
        # Simulate inventory checks with realistic stock levels
        available = random.randint(0, 100)
        requested = item.get('quantity', 0)
        unit_price = random.randint(10, 500)
        item_total = unit_price * requested
        
        inventory_status.append({
            'productId': item.get('productId'),
            'requested': requested,
            'available': available,
            'sufficient': available >= requested,
            'unitPrice': unit_price,
            'itemTotal': item_total
        })
        
        if available >= requested:
            total_amount += item_total
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'inventoryStatus': inventory_status,
            'allItemsAvailable': all(item['sufficient'] for item in inventory_status),
            'totalAmount': total_amount
        })
    }
      `),
      environment: {
        'LOG_LEVEL': 'INFO'
      }
    });

    // Payment processing service - handles payment authorization and processing
    const paymentService = new lambda.Function(this, 'PaymentService', {
      functionName: `${uniqueSuffix}-payment-service`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.seconds(30),
      memorySize: 128,
      code: lambda.Code.fromInline(`
import json
import random

def lambda_handler(event, context):
    """
    Payment service that simulates payment processing and authorization.
    In production, this would integrate with payment gateways and fraud detection.
    """
    amount = event.get('amount', 0)
    user_id = event.get('userId', '')
    order_id = event.get('orderId', '')
    
    # Simulate payment processing with realistic success/failure scenarios
    payment_success = random.random() > 0.1  # 90% success rate
    
    if payment_success:
        transaction_id = f'txn_{random.randint(100000, 999999)}'
        return {
            'statusCode': 200,
            'body': json.dumps({
                'success': True,
                'transactionId': transaction_id,
                'amount': amount,
                'orderId': order_id,
                'status': 'authorized'
            })
        }
    else:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'success': False,
                'error': 'Payment authorization failed',
                'orderId': order_id
            })
        }
      `),
      environment: {
        'LOG_LEVEL': 'INFO'
      }
    });

    // ========================================
    // Step Functions State Machine Definition
    // ========================================

    // Define individual states for the workflow with comprehensive error handling

    // User validation state with retry logic for transient failures
    const validateUser = new stepfunctionsTasks.LambdaInvoke(this, 'ValidateUser', {
      lambdaFunction: userService,
      outputPath: '$.Payload',
      retryOnServiceExceptions: true,
    });

    // Inventory check state with business logic validation
    const checkInventory = new stepfunctionsTasks.LambdaInvoke(this, 'CheckInventory', {
      lambdaFunction: inventoryService,
      outputPath: '$.Payload',
      retryOnServiceExceptions: true,
    });

    // Payment processing state with authorization handling
    const processPayment = new stepfunctionsTasks.LambdaInvoke(this, 'ProcessPayment', {
      lambdaFunction: paymentService,
      outputPath: '$.Payload',
      retryOnServiceExceptions: true,
    });

    // Inventory reservation state using DynamoDB direct integration
    const reserveInventory = new stepfunctionsTasks.DynamoPutItem(this, 'ReserveInventory', {
      table: reservationsTable,
      item: {
        orderId: stepfunctionsTasks.DynamoAttributeValue.fromString(
          stepfunctions.JsonPath.stringAt('$.orderId')
        ),
        status: stepfunctionsTasks.DynamoAttributeValue.fromString('reserved'),
        timestamp: stepfunctionsTasks.DynamoAttributeValue.fromString(
          stepfunctions.JsonPath.stringAt('$$.State.EnteredTime')
        ),
        items: stepfunctionsTasks.DynamoAttributeValue.fromString(
          stepfunctions.JsonPath.jsonToString(stepfunctions.JsonPath.objectAt('$.items'))
        ),
      },
    });

    // Order persistence state for storing completed orders
    const saveOrder = new stepfunctionsTasks.DynamoPutItem(this, 'SaveOrder', {
      table: ordersTable,
      item: {
        orderId: stepfunctionsTasks.DynamoAttributeValue.fromString(
          stepfunctions.JsonPath.stringAt('$.orderId')
        ),
        userId: stepfunctionsTasks.DynamoAttributeValue.fromString(
          stepfunctions.JsonPath.stringAt('$.userId')
        ),
        status: stepfunctionsTasks.DynamoAttributeValue.fromString('completed'),
        amount: stepfunctionsTasks.DynamoAttributeValue.fromNumber(
          stepfunctions.JsonPath.numberAt('$.totalAmount')
        ),
        timestamp: stepfunctionsTasks.DynamoAttributeValue.fromString(
          stepfunctions.JsonPath.stringAt('$$.State.EnteredTime')
        ),
      },
    });

    // Audit logging state for compliance and monitoring
    const logAudit = new stepfunctionsTasks.DynamoPutItem(this, 'LogAudit', {
      table: auditTable,
      item: {
        auditId: stepfunctionsTasks.DynamoAttributeValue.fromString(
          stepfunctions.JsonPath.stringAt('$$.Execution.Name')
        ),
        orderId: stepfunctionsTasks.DynamoAttributeValue.fromString(
          stepfunctions.JsonPath.stringAt('$.orderId')
        ),
        action: stepfunctionsTasks.DynamoAttributeValue.fromString('order_processed'),
        timestamp: stepfunctionsTasks.DynamoAttributeValue.fromString(
          stepfunctions.JsonPath.stringAt('$$.State.EnteredTime')
        ),
      },
    });

    // Compensation state for handling failures and rollbacks
    const compensateOrder = new stepfunctionsTasks.DynamoPutItem(this, 'CompensateOrder', {
      table: auditTable,
      item: {
        auditId: stepfunctionsTasks.DynamoAttributeValue.fromString(
          stepfunctions.JsonPath.stringAt('$$.Execution.Name')
        ),
        orderId: stepfunctionsTasks.DynamoAttributeValue.fromString(
          stepfunctions.JsonPath.stringAt('$.orderId')
        ),
        action: stepfunctionsTasks.DynamoAttributeValue.fromString('order_failed'),
        error: stepfunctionsTasks.DynamoAttributeValue.fromString(
          stepfunctions.JsonPath.stringAt('$.error.Error')
        ),
        timestamp: stepfunctionsTasks.DynamoAttributeValue.fromString(
          stepfunctions.JsonPath.stringAt('$$.State.EnteredTime')
        ),
      },
    });

    // Success and failure end states with structured responses
    const orderProcessed = new stepfunctions.Pass(this, 'OrderProcessed', {
      parameters: {
        'orderId.$': '$.orderId',
        'status': 'completed',
        'message': 'Order processed successfully',
        'totalAmount.$': '$.totalAmount',
      },
    });

    const orderFailed = new stepfunctions.Pass(this, 'OrderFailed', {
      parameters: {
        'orderId.$': '$.orderId',
        'status': 'failed',
        'message': 'Order processing failed',
        'error.$': '$.error',
      },
    });

    // ========================================
    // Workflow Definition with Choice Logic
    // ========================================

    // Choice states for conditional workflow routing based on business rules
    const checkUserValid = new stepfunctions.Choice(this, 'CheckUserValid')
      .when(
        stepfunctions.Condition.booleanEquals('$.body.valid', true),
        checkInventory
      )
      .otherwise(compensateOrder.next(orderFailed));

    const checkInventoryResult = new stepfunctions.Choice(this, 'CheckInventoryResult')
      .when(
        stepfunctions.Condition.booleanEquals('$.body.allItemsAvailable', true),
        processPayment
      )
      .otherwise(compensateOrder.next(orderFailed));

    const checkPaymentResult = new stepfunctions.Choice(this, 'CheckPaymentResult')
      .when(
        stepfunctions.Condition.booleanEquals('$.body.success', true),
        reserveInventory
      )
      .otherwise(compensateOrder.next(orderFailed));

    // Parallel processing for independent operations to improve performance
    const parallelProcessing = new stepfunctions.Parallel(this, 'ParallelProcessing')
      .branch(saveOrder)
      .branch(logAudit)
      .next(orderProcessed)
      .addCatch(compensateOrder.next(orderFailed), {
        errors: ['States.ALL'],
        resultPath: '$.error',
      });

    // Define the complete workflow chain with error handling
    const definition = validateUser
      .addCatch(compensateOrder.next(orderFailed), {
        errors: ['States.ALL'],
        resultPath: '$.error',
      })
      .next(checkUserValid);

    checkInventory
      .addCatch(compensateOrder.next(orderFailed), {
        errors: ['States.ALL'],
        resultPath: '$.error',
      })
      .next(checkInventoryResult);

    processPayment
      .addCatch(compensateOrder.next(orderFailed), {
        errors: ['States.ALL'],
        resultPath: '$.error',
      })
      .next(checkPaymentResult);

    reserveInventory
      .addCatch(compensateOrder.next(orderFailed), {
        errors: ['States.ALL'],
        resultPath: '$.error',
      })
      .next(parallelProcessing);

    // Create CloudWatch Log Group for Step Functions execution logs
    const logGroup = new logs.LogGroup(this, 'StateMachineLogGroup', {
      logGroupName: `/aws/stepfunctions/api-composition-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create the State Machine with comprehensive logging and monitoring
    const stateMachine = new stepfunctions.StateMachine(this, 'OrderProcessingStateMachine', {
      stateMachineName: `api-composition-${uniqueSuffix}-workflow`,
      definition,
      stateMachineType: stepfunctions.StateMachineType.STANDARD,
      logs: {
        destination: logGroup,
        level: stepfunctions.LogLevel.ALL,
      },
      tracingEnabled: true, // Enable AWS X-Ray tracing for distributed monitoring
    });

    // Grant necessary permissions to the state machine for DynamoDB operations
    ordersTable.grantWriteData(stateMachine);
    auditTable.grantWriteData(stateMachine);
    reservationsTable.grantWriteData(stateMachine);

    // ========================================
    // API Gateway Configuration
    // ========================================

    // Create IAM role for API Gateway to invoke Step Functions
    const apiGatewayRole = new iam.Role(this, 'ApiGatewayStepFunctionsRole', {
      assumedBy: new iam.ServicePrincipal('apigateway.amazonaws.com'),
      inlinePolicies: {
        StepFunctionsExecution: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['states:StartExecution'],
              resources: [stateMachine.stateMachineArn],
            }),
          ],
        }),
        DynamoDBRead: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['dynamodb:GetItem', 'dynamodb:Query'],
              resources: [ordersTable.tableArn, auditTable.tableArn],
            }),
          ],
        }),
      },
    });

    // Create API Gateway with proper configuration for production use
    const api = new apigateway.RestApi(this, 'CompositionApi', {
      restApiName: `api-composition-${uniqueSuffix}`,
      description: 'API Composition with Step Functions for order processing',
      deployOptions: {
        stageName: 'prod',
        throttle: {
          rateLimit: 1000,
          burstLimit: 2000,
        },
        metricsEnabled: true,
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        dataTraceEnabled: true,
      },
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'Authorization'],
      },
    });

    // Create orders resource hierarchy for RESTful API design
    const ordersResource = api.root.addResource('orders');

    // POST /orders - Create new order with Step Functions orchestration
    ordersResource.addMethod('POST', new apigateway.AwsIntegration({
      service: 'states',
      action: 'StartExecution',
      integrationHttpMethod: 'POST',
      options: {
        credentialsRole: apiGatewayRole,
        requestTemplates: {
          'application/json': JSON.stringify({
            input: '$util.escapeJavaScript($input.json(\'$\'))',
            stateMachineArn: stateMachine.stateMachineArn,
          }),
        },
        integrationResponses: [
          {
            statusCode: '200',
            responseTemplates: {
              'application/json': JSON.stringify({
                executionArn: '$input.json(\'$.executionArn\')',
                message: 'Order processing started successfully',
              }),
            },
          },
          {
            statusCode: '400',
            selectionPattern: '4\\d{2}',
            responseTemplates: {
              'application/json': JSON.stringify({
                error: 'Invalid request format',
              }),
            },
          },
        ],
      },
    }), {
      methodResponses: [
        { statusCode: '200' },
        { statusCode: '400' },
      ],
    });

    // GET /orders/{orderId}/status - Retrieve order status with direct DynamoDB integration
    const orderIdResource = ordersResource.addResource('{orderId}');
    const statusResource = orderIdResource.addResource('status');

    statusResource.addMethod('GET', new apigateway.AwsIntegration({
      service: 'dynamodb',
      action: 'GetItem',
      integrationHttpMethod: 'POST',
      options: {
        credentialsRole: apiGatewayRole,
        requestTemplates: {
          'application/json': JSON.stringify({
            TableName: ordersTable.tableName,
            Key: {
              orderId: {
                S: '$input.params(\'orderId\')',
              },
            },
          }),
        },
        integrationResponses: [
          {
            statusCode: '200',
            responseTemplates: {
              'application/json': JSON.stringify({
                orderId: '$input.json(\'$.Item.orderId.S\')',
                status: '$input.json(\'$.Item.status.S\')',
                amount: '$input.json(\'$.Item.amount.N\')',
                timestamp: '$input.json(\'$.Item.timestamp.S\')',
              }),
            },
          },
          {
            statusCode: '404',
            selectionPattern: 'null',
            responseTemplates: {
              'application/json': JSON.stringify({
                error: 'Order not found',
              }),
            },
          },
        ],
      },
    }), {
      methodResponses: [
        { statusCode: '200' },
        { statusCode: '404' },
      ],
      requestParameters: {
        'method.request.path.orderId': true,
      },
    });

    // ========================================
    // CloudFormation Outputs
    // ========================================

    new cdk.CfnOutput(this, 'ApiEndpoint', {
      value: api.url,
      description: 'API Gateway endpoint URL for order processing',
      exportName: `ApiComposition-${uniqueSuffix}-ApiEndpoint`,
    });

    new cdk.CfnOutput(this, 'StateMachineArn', {
      value: stateMachine.stateMachineArn,
      description: 'Step Functions state machine ARN for order processing workflow',
      exportName: `ApiComposition-${uniqueSuffix}-StateMachineArn`,
    });

    new cdk.CfnOutput(this, 'OrdersTableName', {
      value: ordersTable.tableName,
      description: 'DynamoDB table name for storing order data',
      exportName: `ApiComposition-${uniqueSuffix}-OrdersTable`,
    });

    new cdk.CfnOutput(this, 'AuditTableName', {
      value: auditTable.tableName,
      description: 'DynamoDB table name for audit logging',
      exportName: `ApiComposition-${uniqueSuffix}-AuditTable`,
    });

    new cdk.CfnOutput(this, 'UserServiceFunctionName', {
      value: userService.functionName,
      description: 'Lambda function name for user validation service',
      exportName: `ApiComposition-${uniqueSuffix}-UserService`,
    });

    new cdk.CfnOutput(this, 'InventoryServiceFunctionName', {
      value: inventoryService.functionName,
      description: 'Lambda function name for inventory management service',
      exportName: `ApiComposition-${uniqueSuffix}-InventoryService`,
    });

    new cdk.CfnOutput(this, 'PaymentServiceFunctionName', {
      value: paymentService.functionName,
      description: 'Lambda function name for payment processing service',
      exportName: `ApiComposition-${uniqueSuffix}-PaymentService`,
    });
  }
}

// ========================================
// CDK Application Entry Point
// ========================================

const app = new cdk.App();

new ApiCompositionStack(app, 'ApiCompositionStack', {
  description: 'API Composition with Step Functions and API Gateway - demonstrating advanced microservices orchestration patterns',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'api-composition',
    Environment: 'demo',
    Recipe: 'building-api-composition-step-functions-api-gateway',
  },
});