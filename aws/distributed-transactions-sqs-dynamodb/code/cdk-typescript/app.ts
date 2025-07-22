#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as lambdaEventSources from 'aws-cdk-lib/aws-lambda-event-sources';
import { SqsEventSource } from 'aws-cdk-lib/aws-lambda-event-sources';

/**
 * Stack for implementing distributed transaction processing using the Saga pattern
 * with Amazon SQS FIFO queues and DynamoDB for state management.
 */
export class DistributedTransactionProcessingStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate a unique suffix for resource naming
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);
    const stackName = `distributed-tx-${uniqueSuffix}`;

    // ======================================================================
    // DynamoDB Tables
    // ======================================================================

    // Saga State Table - tracks distributed transaction state
    const sagaStateTable = new dynamodb.Table(this, 'SagaStateTable', {
      tableName: `${stackName}-saga-state`,
      partitionKey: { name: 'TransactionId', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
      timeToLiveAttribute: 'TTL',
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Order Table - stores order information
    const orderTable = new dynamodb.Table(this, 'OrderTable', {
      tableName: `${stackName}-orders`,
      partitionKey: { name: 'OrderId', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Payment Table - stores payment information
    const paymentTable = new dynamodb.Table(this, 'PaymentTable', {
      tableName: `${stackName}-payments`,
      partitionKey: { name: 'PaymentId', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Inventory Table - stores product inventory
    const inventoryTable = new dynamodb.Table(this, 'InventoryTable', {
      tableName: `${stackName}-inventory`,
      partitionKey: { name: 'ProductId', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // ======================================================================
    // SQS FIFO Queues
    // ======================================================================

    // Dead Letter Queue for failed messages
    const deadLetterQueue = new sqs.Queue(this, 'DeadLetterQueue', {
      queueName: `${stackName}-dlq.fifo`,
      fifo: true,
      contentBasedDeduplication: true,
      retentionPeriod: cdk.Duration.days(14),
      encryption: sqs.QueueEncryption.SQS_MANAGED,
    });

    // Order Processing Queue
    const orderProcessingQueue = new sqs.Queue(this, 'OrderProcessingQueue', {
      queueName: `${stackName}-order-processing.fifo`,
      fifo: true,
      contentBasedDeduplication: true,
      visibilityTimeout: cdk.Duration.minutes(5),
      retentionPeriod: cdk.Duration.days(14),
      encryption: sqs.QueueEncryption.SQS_MANAGED,
      deadLetterQueue: {
        queue: deadLetterQueue,
        maxReceiveCount: 3,
      },
    });

    // Payment Processing Queue
    const paymentProcessingQueue = new sqs.Queue(this, 'PaymentProcessingQueue', {
      queueName: `${stackName}-payment-processing.fifo`,
      fifo: true,
      contentBasedDeduplication: true,
      visibilityTimeout: cdk.Duration.minutes(5),
      retentionPeriod: cdk.Duration.days(14),
      encryption: sqs.QueueEncryption.SQS_MANAGED,
      deadLetterQueue: {
        queue: deadLetterQueue,
        maxReceiveCount: 3,
      },
    });

    // Inventory Update Queue
    const inventoryUpdateQueue = new sqs.Queue(this, 'InventoryUpdateQueue', {
      queueName: `${stackName}-inventory-update.fifo`,
      fifo: true,
      contentBasedDeduplication: true,
      visibilityTimeout: cdk.Duration.minutes(5),
      retentionPeriod: cdk.Duration.days(14),
      encryption: sqs.QueueEncryption.SQS_MANAGED,
      deadLetterQueue: {
        queue: deadLetterQueue,
        maxReceiveCount: 3,
      },
    });

    // Compensation Queue for rollback operations
    const compensationQueue = new sqs.Queue(this, 'CompensationQueue', {
      queueName: `${stackName}-compensation.fifo`,
      fifo: true,
      contentBasedDeduplication: true,
      visibilityTimeout: cdk.Duration.minutes(5),
      retentionPeriod: cdk.Duration.days(14),
      encryption: sqs.QueueEncryption.SQS_MANAGED,
      deadLetterQueue: {
        queue: deadLetterQueue,
        maxReceiveCount: 3,
      },
    });

    // ======================================================================
    // IAM Role for Lambda Functions
    // ======================================================================

    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `${stackName}-lambda-role`,
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
                'dynamodb:BatchGetItem',
                'dynamodb:BatchWriteItem',
              ],
              resources: [
                sagaStateTable.tableArn,
                orderTable.tableArn,
                paymentTable.tableArn,
                inventoryTable.tableArn,
              ],
            }),
          ],
        }),
        SQSAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'sqs:SendMessage',
                'sqs:ReceiveMessage',
                'sqs:DeleteMessage',
                'sqs:GetQueueAttributes',
                'sqs:GetQueueUrl',
              ],
              resources: [
                orderProcessingQueue.queueArn,
                paymentProcessingQueue.queueArn,
                inventoryUpdateQueue.queueArn,
                compensationQueue.queueArn,
                deadLetterQueue.queueArn,
              ],
            }),
          ],
        }),
      },
    });

    // ======================================================================
    // Lambda Functions
    // ======================================================================

    // Transaction Orchestrator Lambda
    const orchestratorFunction = new lambda.Function(this, 'TransactionOrchestrator', {
      functionName: `${stackName}-orchestrator`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')

SAGA_STATE_TABLE = os.environ['SAGA_STATE_TABLE']
ORDER_QUEUE_URL = os.environ['ORDER_QUEUE_URL']
COMPENSATION_QUEUE_URL = os.environ['COMPENSATION_QUEUE_URL']

def lambda_handler(event, context):
    try:
        # Initialize transaction
        transaction_id = str(uuid.uuid4())
        order_data = json.loads(event['body'])
        
        # Create saga state record
        saga_table = dynamodb.Table(SAGA_STATE_TABLE)
        saga_table.put_item(
            Item={
                'TransactionId': transaction_id,
                'Status': 'STARTED',
                'CurrentStep': 'ORDER_PROCESSING',
                'Steps': ['ORDER_PROCESSING', 'PAYMENT_PROCESSING', 'INVENTORY_UPDATE'],
                'CompletedSteps': [],
                'OrderData': order_data,
                'Timestamp': datetime.utcnow().isoformat(),
                'TTL': int(datetime.utcnow().timestamp()) + 86400  # 24 hours TTL
            }
        )
        
        # Start transaction by sending to order queue
        message_body = {
            'transactionId': transaction_id,
            'step': 'ORDER_PROCESSING',
            'data': order_data
        }
        
        sqs.send_message(
            QueueUrl=ORDER_QUEUE_URL,
            MessageBody=json.dumps(message_body),
            MessageGroupId=transaction_id
        )
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'transactionId': transaction_id,
                'status': 'STARTED',
                'message': 'Transaction initiated successfully'
            })
        }
        
    except Exception as e:
        print(f"Error in orchestrator: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': str(e)
            })
        }
`),
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      environment: {
        SAGA_STATE_TABLE: sagaStateTable.tableName,
        ORDER_QUEUE_URL: orderProcessingQueue.queueUrl,
        COMPENSATION_QUEUE_URL: compensationQueue.queueUrl,
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // Compensation Handler Lambda
    const compensationHandlerFunction = new lambda.Function(this, 'CompensationHandler', {
      functionName: `${stackName}-compensation-handler`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.handle_compensation',
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')

SAGA_STATE_TABLE = os.environ['SAGA_STATE_TABLE']

def handle_compensation(event, context):
    try:
        # Process compensation messages
        for record in event['Records']:
            message_body = json.loads(record['body'])
            transaction_id = message_body['transactionId']
            failed_step = message_body['failedStep']
            
            # Update saga state to failed
            saga_table = dynamodb.Table(SAGA_STATE_TABLE)
            saga_table.update_item(
                Key={'TransactionId': transaction_id},
                UpdateExpression='SET #status = :status, FailedStep = :failed_step',
                ExpressionAttributeNames={'#status': 'Status'},
                ExpressionAttributeValues={
                    ':status': 'FAILED',
                    ':failed_step': failed_step
                }
            )
            
            print(f"Transaction {transaction_id} failed at step {failed_step}")
            
    except Exception as e:
        print(f"Error in compensation handler: {str(e)}")
        raise
`),
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      environment: {
        SAGA_STATE_TABLE: sagaStateTable.tableName,
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // Order Service Lambda
    const orderServiceFunction = new lambda.Function(this, 'OrderService', {
      functionName: `${stackName}-order-service`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')

ORDER_TABLE = os.environ['ORDER_TABLE']
SAGA_STATE_TABLE = os.environ['SAGA_STATE_TABLE']
PAYMENT_QUEUE_URL = os.environ['PAYMENT_QUEUE_URL']
COMPENSATION_QUEUE_URL = os.environ['COMPENSATION_QUEUE_URL']

def lambda_handler(event, context):
    try:
        for record in event['Records']:
            message_body = json.loads(record['body'])
            transaction_id = message_body['transactionId']
            order_data = message_body['data']
            
            # Generate order ID
            order_id = str(uuid.uuid4())
            
            # Create order record
            order_table = dynamodb.Table(ORDER_TABLE)
            saga_table = dynamodb.Table(SAGA_STATE_TABLE)
            
            order_table.put_item(
                Item={
                    'OrderId': order_id,
                    'TransactionId': transaction_id,
                    'CustomerId': order_data['customerId'],
                    'ProductId': order_data['productId'],
                    'Quantity': order_data['quantity'],
                    'Amount': order_data['amount'],
                    'Status': 'PENDING',
                    'Timestamp': datetime.utcnow().isoformat()
                }
            )
            
            # Update saga state
            saga_table.update_item(
                Key={'TransactionId': transaction_id},
                UpdateExpression='SET CompletedSteps = list_append(CompletedSteps, :step), CurrentStep = :next_step',
                ExpressionAttributeValues={
                    ':step': ['ORDER_PROCESSING'],
                    ':next_step': 'PAYMENT_PROCESSING'
                }
            )
            
            # Send message to payment queue
            payment_message = {
                'transactionId': transaction_id,
                'step': 'PAYMENT_PROCESSING',
                'data': {
                    'orderId': order_id,
                    'customerId': order_data['customerId'],
                    'amount': order_data['amount']
                }
            }
            
            sqs.send_message(
                QueueUrl=PAYMENT_QUEUE_URL,
                MessageBody=json.dumps(payment_message),
                MessageGroupId=transaction_id
            )
            
            print(f"Order {order_id} created for transaction {transaction_id}")
            
    except Exception as e:
        print(f"Error in order service: {str(e)}")
        # Send compensation message
        compensation_message = {
            'transactionId': transaction_id,
            'failedStep': 'ORDER_PROCESSING',
            'error': str(e)
        }
        
        sqs.send_message(
            QueueUrl=COMPENSATION_QUEUE_URL,
            MessageBody=json.dumps(compensation_message),
            MessageGroupId=transaction_id
        )
        
        raise
`),
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      environment: {
        ORDER_TABLE: orderTable.tableName,
        SAGA_STATE_TABLE: sagaStateTable.tableName,
        PAYMENT_QUEUE_URL: paymentProcessingQueue.queueUrl,
        COMPENSATION_QUEUE_URL: compensationQueue.queueUrl,
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // Payment Service Lambda
    const paymentServiceFunction = new lambda.Function(this, 'PaymentService', {
      functionName: `${stackName}-payment-service`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
import os
import random
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')

PAYMENT_TABLE = os.environ['PAYMENT_TABLE']
SAGA_STATE_TABLE = os.environ['SAGA_STATE_TABLE']
INVENTORY_QUEUE_URL = os.environ['INVENTORY_QUEUE_URL']
COMPENSATION_QUEUE_URL = os.environ['COMPENSATION_QUEUE_URL']

def lambda_handler(event, context):
    try:
        for record in event['Records']:
            message_body = json.loads(record['body'])
            transaction_id = message_body['transactionId']
            payment_data = message_body['data']
            
            # Simulate payment processing (90% success rate)
            if random.random() < 0.1:
                raise Exception("Payment processing failed - insufficient funds")
            
            # Generate payment ID
            payment_id = str(uuid.uuid4())
            
            # Create payment record
            payment_table = dynamodb.Table(PAYMENT_TABLE)
            saga_table = dynamodb.Table(SAGA_STATE_TABLE)
            
            payment_table.put_item(
                Item={
                    'PaymentId': payment_id,
                    'TransactionId': transaction_id,
                    'OrderId': payment_data['orderId'],
                    'CustomerId': payment_data['customerId'],
                    'Amount': payment_data['amount'],
                    'Status': 'PROCESSED',
                    'Timestamp': datetime.utcnow().isoformat()
                }
            )
            
            # Update saga state
            saga_table.update_item(
                Key={'TransactionId': transaction_id},
                UpdateExpression='SET CompletedSteps = list_append(CompletedSteps, :step), CurrentStep = :next_step',
                ExpressionAttributeValues={
                    ':step': ['PAYMENT_PROCESSING'],
                    ':next_step': 'INVENTORY_UPDATE'
                }
            )
            
            # Get original order data for inventory update
            saga_response = saga_table.get_item(
                Key={'TransactionId': transaction_id}
            )
            order_data = saga_response['Item']['OrderData']
            
            # Send message to inventory queue
            inventory_message = {
                'transactionId': transaction_id,
                'step': 'INVENTORY_UPDATE',
                'data': {
                    'orderId': payment_data['orderId'],
                    'paymentId': payment_id,
                    'productId': order_data['productId'],
                    'quantity': order_data['quantity']
                }
            }
            
            sqs.send_message(
                QueueUrl=INVENTORY_QUEUE_URL,
                MessageBody=json.dumps(inventory_message),
                MessageGroupId=transaction_id
            )
            
            print(f"Payment {payment_id} processed for transaction {transaction_id}")
            
    except Exception as e:
        print(f"Error in payment service: {str(e)}")
        # Send compensation message
        compensation_message = {
            'transactionId': transaction_id,
            'failedStep': 'PAYMENT_PROCESSING',
            'error': str(e)
        }
        
        sqs.send_message(
            QueueUrl=COMPENSATION_QUEUE_URL,
            MessageBody=json.dumps(compensation_message),
            MessageGroupId=transaction_id
        )
        
        raise
`),
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      environment: {
        PAYMENT_TABLE: paymentTable.tableName,
        SAGA_STATE_TABLE: sagaStateTable.tableName,
        INVENTORY_QUEUE_URL: inventoryUpdateQueue.queueUrl,
        COMPENSATION_QUEUE_URL: compensationQueue.queueUrl,
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // Inventory Service Lambda
    const inventoryServiceFunction = new lambda.Function(this, 'InventoryService', {
      functionName: `${stackName}-inventory-service`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import os
import random
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')

INVENTORY_TABLE = os.environ['INVENTORY_TABLE']
SAGA_STATE_TABLE = os.environ['SAGA_STATE_TABLE']
COMPENSATION_QUEUE_URL = os.environ['COMPENSATION_QUEUE_URL']

def lambda_handler(event, context):
    try:
        for record in event['Records']:
            message_body = json.loads(record['body'])
            transaction_id = message_body['transactionId']
            inventory_data = message_body['data']
            
            # Simulate inventory check (85% success rate)
            if random.random() < 0.15:
                raise Exception("Insufficient inventory available")
            
            # Update inventory using DynamoDB transaction
            inventory_table = dynamodb.Table(INVENTORY_TABLE)
            saga_table = dynamodb.Table(SAGA_STATE_TABLE)
            
            # Try to update inventory atomically
            try:
                inventory_table.update_item(
                    Key={'ProductId': inventory_data['productId']},
                    UpdateExpression='SET QuantityAvailable = QuantityAvailable - :quantity, LastUpdated = :timestamp',
                    ConditionExpression='QuantityAvailable >= :quantity',
                    ExpressionAttributeValues={
                        ':quantity': inventory_data['quantity'],
                        ':timestamp': datetime.utcnow().isoformat()
                    }
                )
            except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
                raise Exception("Insufficient inventory - conditional check failed")
            
            # Update saga state to completed
            saga_table.update_item(
                Key={'TransactionId': transaction_id},
                UpdateExpression='SET CompletedSteps = list_append(CompletedSteps, :step), CurrentStep = :next_step, #status = :status',
                ExpressionAttributeNames={'#status': 'Status'},
                ExpressionAttributeValues={
                    ':step': ['INVENTORY_UPDATE'],
                    ':next_step': 'COMPLETED',
                    ':status': 'COMPLETED'
                }
            )
            
            print(f"Inventory updated for transaction {transaction_id}, product {inventory_data['productId']}")
            
    except Exception as e:
        print(f"Error in inventory service: {str(e)}")
        # Send compensation message
        compensation_message = {
            'transactionId': transaction_id,
            'failedStep': 'INVENTORY_UPDATE',
            'error': str(e)
        }
        
        sqs.send_message(
            QueueUrl=COMPENSATION_QUEUE_URL,
            MessageBody=json.dumps(compensation_message),
            MessageGroupId=transaction_id
        )
        
        raise
`),
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      environment: {
        INVENTORY_TABLE: inventoryTable.tableName,
        SAGA_STATE_TABLE: sagaStateTable.tableName,
        COMPENSATION_QUEUE_URL: compensationQueue.queueUrl,
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // ======================================================================
    // Lambda Event Source Mappings
    // ======================================================================

    // Connect queues to Lambda functions
    orderServiceFunction.addEventSource(
      new SqsEventSource(orderProcessingQueue, {
        batchSize: 1,
        maxBatchingWindow: cdk.Duration.seconds(5),
      })
    );

    paymentServiceFunction.addEventSource(
      new SqsEventSource(paymentProcessingQueue, {
        batchSize: 1,
        maxBatchingWindow: cdk.Duration.seconds(5),
      })
    );

    inventoryServiceFunction.addEventSource(
      new SqsEventSource(inventoryUpdateQueue, {
        batchSize: 1,
        maxBatchingWindow: cdk.Duration.seconds(5),
      })
    );

    compensationHandlerFunction.addEventSource(
      new SqsEventSource(compensationQueue, {
        batchSize: 1,
        maxBatchingWindow: cdk.Duration.seconds(5),
      })
    );

    // ======================================================================
    // API Gateway
    // ======================================================================

    const api = new apigateway.RestApi(this, 'TransactionApi', {
      restApiName: `${stackName}-transaction-api`,
      description: 'REST API for distributed transaction processing',
      deployOptions: {
        stageName: 'prod',
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        dataTraceEnabled: true,
        metricsEnabled: true,
      },
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key'],
      },
    });

    // Create transactions resource
    const transactionsResource = api.root.addResource('transactions');
    
    // Create POST method for transaction initiation
    const transactionIntegration = new apigateway.LambdaIntegration(orchestratorFunction, {
      proxy: true,
      integrationResponses: [
        {
          statusCode: '200',
          responseHeaders: {
            'Access-Control-Allow-Origin': "'*'",
            'Access-Control-Allow-Headers': "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'",
          },
        },
      ],
    });

    transactionsResource.addMethod('POST', transactionIntegration, {
      methodResponses: [
        {
          statusCode: '200',
          responseHeaders: {
            'Access-Control-Allow-Origin': true,
            'Access-Control-Allow-Headers': true,
          },
        },
      ],
    });

    // ======================================================================
    // CloudWatch Alarms
    // ======================================================================

    // Failed transactions alarm
    const failedTransactionsAlarm = new cloudwatch.Alarm(this, 'FailedTransactionsAlarm', {
      alarmName: `${stackName}-failed-transactions`,
      alarmDescription: 'Alert when transactions fail',
      metric: orchestratorFunction.metricErrors({
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 5,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // SQS message age alarm
    const messageAgeAlarm = new cloudwatch.Alarm(this, 'MessageAgeAlarm', {
      alarmName: `${stackName}-message-age`,
      alarmDescription: 'Alert when messages age in queue',
      metric: orderProcessingQueue.metricApproximateAgeOfOldestMessage({
        statistic: 'Maximum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 600, // 10 minutes
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // ======================================================================
    // Sample Inventory Data (Custom Resource)
    // ======================================================================

    const sampleDataFunction = new lambda.Function(this, 'SampleDataFunction', {
      functionName: `${stackName}-sample-data`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import cfnresponse
from datetime import datetime

def lambda_handler(event, context):
    try:
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table('${inventoryTable.tableName}')
        
        if event['RequestType'] == 'Create':
            # Add sample products
            sample_products = [
                {
                    'ProductId': 'PROD-001',
                    'ProductName': 'Premium Laptop',
                    'QuantityAvailable': 50,
                    'Price': 1299.99,
                    'LastUpdated': datetime.utcnow().isoformat()
                },
                {
                    'ProductId': 'PROD-002',
                    'ProductName': 'Wireless Headphones',
                    'QuantityAvailable': 100,
                    'Price': 199.99,
                    'LastUpdated': datetime.utcnow().isoformat()
                },
                {
                    'ProductId': 'PROD-003',
                    'ProductName': 'Smartphone',
                    'QuantityAvailable': 25,
                    'Price': 799.99,
                    'LastUpdated': datetime.utcnow().isoformat()
                }
            ]
            
            for product in sample_products:
                table.put_item(Item=product)
            
            print("Sample inventory data created successfully")
        
        cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
        
    except Exception as e:
        print(f"Error: {str(e)}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {})
`),
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // Custom resource to populate sample inventory data
    new cdk.CustomResource(this, 'SampleInventoryData', {
      serviceToken: sampleDataFunction.functionArn,
      properties: {
        Timestamp: new Date().toISOString(), // Force update on each deploy
      },
    });

    // ======================================================================
    // Stack Outputs
    // ======================================================================

    new cdk.CfnOutput(this, 'ApiEndpoint', {
      value: api.url,
      description: 'API Gateway endpoint for transaction processing',
      exportName: `${stackName}-api-endpoint`,
    });

    new cdk.CfnOutput(this, 'SagaStateTableName', {
      value: sagaStateTable.tableName,
      description: 'Name of the saga state DynamoDB table',
      exportName: `${stackName}-saga-state-table`,
    });

    new cdk.CfnOutput(this, 'OrderTableName', {
      value: orderTable.tableName,
      description: 'Name of the orders DynamoDB table',
      exportName: `${stackName}-order-table`,
    });

    new cdk.CfnOutput(this, 'PaymentTableName', {
      value: paymentTable.tableName,
      description: 'Name of the payments DynamoDB table',
      exportName: `${stackName}-payment-table`,
    });

    new cdk.CfnOutput(this, 'InventoryTableName', {
      value: inventoryTable.tableName,
      description: 'Name of the inventory DynamoDB table',
      exportName: `${stackName}-inventory-table`,
    });

    new cdk.CfnOutput(this, 'StackName', {
      value: stackName,
      description: 'Generated stack name with unique suffix',
      exportName: `${stackName}-name`,
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'DistributedTransactionProcessing');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('Owner', 'CDK');
    cdk.Tags.of(this).add('CostCenter', 'Engineering');
  }
}

// ======================================================================
// CDK App
// ======================================================================

const app = new cdk.App();

new DistributedTransactionProcessingStack(app, 'DistributedTransactionProcessingStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Distributed transaction processing using SQS and DynamoDB with the Saga pattern',
  tags: {
    Project: 'DistributedTransactionProcessing',
    Environment: 'Development',
    Generator: 'CDK-TypeScript',
  },
});

app.synth();