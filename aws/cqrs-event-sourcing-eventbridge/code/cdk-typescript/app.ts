#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { DynamoEventSource } from 'aws-cdk-lib/aws-lambda-event-sources';

/**
 * CDK Stack implementing CQRS and Event Sourcing architecture
 * with EventBridge and DynamoDB
 */
export class CqrsEventSourcingStack extends cdk.Stack {
  public readonly eventStore: dynamodb.Table;
  public readonly userReadModel: dynamodb.Table;
  public readonly orderReadModel: dynamodb.Table;
  public readonly eventBus: events.EventBus;
  public readonly commandHandler: lambda.Function;
  public readonly queryHandler: lambda.Function;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.slice(-6);

    // Create Event Store DynamoDB Table
    // This table serves as the authoritative source of truth for all domain events
    this.eventStore = new dynamodb.Table(this, 'EventStore', {
      tableName: `cqrs-event-store-${uniqueSuffix}`,
      partitionKey: {
        name: 'AggregateId',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'Version',
        type: dynamodb.AttributeType.NUMBER,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      stream: dynamodb.StreamViewType.NEW_IMAGE,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Use RETAIN for production
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
    });

    // Add Global Secondary Index for efficient event type and temporal queries
    this.eventStore.addGlobalSecondaryIndex({
      indexName: 'EventType-Timestamp-index',
      partitionKey: {
        name: 'EventType',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'Timestamp',
        type: dynamodb.AttributeType.STRING,
      },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // Create User Read Model Table
    // Optimized for user profile queries and lookups
    this.userReadModel = new dynamodb.Table(this, 'UserReadModel', {
      tableName: `cqrs-user-profiles-${uniqueSuffix}`,
      partitionKey: {
        name: 'UserId',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Use RETAIN for production
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
    });

    // Add GSI for email-based lookups
    this.userReadModel.addGlobalSecondaryIndex({
      indexName: 'Email-index',
      partitionKey: {
        name: 'Email',
        type: dynamodb.AttributeType.STRING,
      },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // Create Order Read Model Table
    // Optimized for order queries by user, status, and order ID
    this.orderReadModel = new dynamodb.Table(this, 'OrderReadModel', {
      tableName: `cqrs-order-summaries-${uniqueSuffix}`,
      partitionKey: {
        name: 'OrderId',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Use RETAIN for production
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
    });

    // Add GSI for user-based order queries
    this.orderReadModel.addGlobalSecondaryIndex({
      indexName: 'UserId-index',
      partitionKey: {
        name: 'UserId',
        type: dynamodb.AttributeType.STRING,
      },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // Add GSI for status-based order queries
    this.orderReadModel.addGlobalSecondaryIndex({
      indexName: 'Status-index',
      partitionKey: {
        name: 'Status',
        type: dynamodb.AttributeType.STRING,
      },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // Create Custom EventBridge Bus
    // Serves as the event distribution backbone for domain events
    this.eventBus = new events.EventBus(this, 'CqrsEventBus', {
      eventBusName: `cqrs-events-${uniqueSuffix}`,
    });

    // Create event archive for replay capabilities
    new events.Archive(this, 'CqrsEventArchive', {
      archiveName: `cqrs-events-archive-${uniqueSuffix}`,
      sourceEventBus: this.eventBus,
      retention: cdk.Duration.days(30),
      description: 'Archive for CQRS event sourcing replay capabilities',
    });

    // Create IAM role for Command Handler
    // Restricted to event store access only (write side of CQRS)
    const commandRole = new iam.Role(this, 'CommandHandlerRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Grant command handler access to event store only
    this.eventStore.grantReadWriteData(commandRole);

    // Grant permission to publish events to EventBridge
    this.eventBus.grantPutEventsTo(commandRole);

    // Create IAM role for Projection Handlers
    // Restricted to read model access only (query side of CQRS)
    const projectionRole = new iam.Role(this, 'ProjectionHandlerRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Grant projection handlers access to read models only
    this.userReadModel.grantReadWriteData(projectionRole);
    this.orderReadModel.grantReadWriteData(projectionRole);

    // Create Command Handler Lambda Function
    // Processes business commands and generates domain events
    this.commandHandler = new lambda.Function(this, 'CommandHandler', {
      functionName: `cqrs-command-handler-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: commandRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 512,
      environment: {
        EVENT_STORE_TABLE: this.eventStore.tableName,
        EVENT_BUS_NAME: this.eventBus.eventBusName,
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
import os
from datetime import datetime
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
eventbridge = boto3.client('events')

def lambda_handler(event, context):
    try:
        # Parse command from API Gateway or direct invocation
        command = json.loads(event['body']) if 'body' in event else event
        
        # Command validation
        command_type = command.get('commandType')
        aggregate_id = command.get('aggregateId', str(uuid.uuid4()))
        
        if not command_type:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'commandType is required'})
            }
        
        # Get current version for optimistic concurrency control
        table = dynamodb.Table(os.environ['EVENT_STORE_TABLE'])
        
        # Query existing events for this aggregate
        response = table.query(
            KeyConditionExpression='AggregateId = :id',
            ExpressionAttributeValues={':id': aggregate_id},
            ScanIndexForward=False,
            Limit=1
        )
        
        current_version = 0
        if response['Items']:
            current_version = int(response['Items'][0]['Version'])
        
        # Create domain event
        event_id = str(uuid.uuid4())
        new_version = current_version + 1
        timestamp = datetime.utcnow().isoformat()
        
        # Event payload based on command type
        event_data = create_event_from_command(command_type, command, aggregate_id)
        
        # Store event in event store with optimistic concurrency
        table.put_item(
            Item={
                'AggregateId': aggregate_id,
                'Version': new_version,
                'EventId': event_id,
                'EventType': event_data['eventType'],
                'Timestamp': timestamp,
                'EventData': event_data['data'],
                'CommandId': command.get('commandId', str(uuid.uuid4())),
                'CorrelationId': command.get('correlationId', str(uuid.uuid4()))
            },
            ConditionExpression='attribute_not_exists(AggregateId) AND attribute_not_exists(Version)'
        )
        
        return {
            'statusCode': 201,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'aggregateId': aggregate_id,
                'version': new_version,
                'eventId': event_id,
                'timestamp': timestamp
            })
        }
        
    except Exception as e:
        print(f"Error processing command: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Internal server error'})
        }

def create_event_from_command(command_type, command, aggregate_id):
    """Transform commands into domain events"""
    
    if command_type == 'CreateUser':
        return {
            'eventType': 'UserCreated',
            'data': {
                'userId': aggregate_id,
                'email': command['email'],
                'name': command['name'],
                'createdAt': datetime.utcnow().isoformat()
            }
        }
    
    elif command_type == 'UpdateUserProfile':
        return {
            'eventType': 'UserProfileUpdated',
            'data': {
                'userId': aggregate_id,
                'changes': command['changes'],
                'updatedAt': datetime.utcnow().isoformat()
            }
        }
    
    elif command_type == 'CreateOrder':
        return {
            'eventType': 'OrderCreated',
            'data': {
                'orderId': aggregate_id,
                'userId': command['userId'],
                'items': command['items'],
                'totalAmount': command['totalAmount'],
                'createdAt': datetime.utcnow().isoformat()
            }
        }
    
    elif command_type == 'UpdateOrderStatus':
        return {
            'eventType': 'OrderStatusUpdated',
            'data': {
                'orderId': aggregate_id,
                'status': command['status'],
                'updatedAt': datetime.utcnow().isoformat()
            }
        }
    
    else:
        raise ValueError(f"Unknown command type: {command_type}")
      `),
    });

    // Create Stream Processor Lambda Function
    // Transforms DynamoDB stream events into EventBridge domain events
    const streamProcessor = new lambda.Function(this, 'StreamProcessor', {
      functionName: `cqrs-stream-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: commandRole,
      timeout: cdk.Duration.seconds(60),
      memorySize: 512,
      environment: {
        EVENT_BUS_NAME: this.eventBus.eventBusName,
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from decimal import Decimal

eventbridge = boto3.client('events')

def lambda_handler(event, context):
    try:
        for record in event['Records']:
            if record['eventName'] in ['INSERT']:
                # Extract event from DynamoDB stream
                dynamodb_event = record['dynamodb']['NewImage']
                
                # Convert DynamoDB format to normal format
                domain_event = {
                    'EventId': dynamodb_event['EventId']['S'],
                    'AggregateId': dynamodb_event['AggregateId']['S'],
                    'EventType': dynamodb_event['EventType']['S'],
                    'Version': int(dynamodb_event['Version']['N']),
                    'Timestamp': dynamodb_event['Timestamp']['S'],
                    'EventData': deserialize_dynamodb_item(dynamodb_event['EventData']['M']),
                    'CommandId': dynamodb_event.get('CommandId', {}).get('S'),
                    'CorrelationId': dynamodb_event.get('CorrelationId', {}).get('S')
                }
                
                # Publish to EventBridge
                eventbridge.put_events(
                    Entries=[{
                        'Source': 'cqrs.demo',
                        'DetailType': domain_event['EventType'],
                        'Detail': json.dumps(domain_event, default=str),
                        'EventBusName': os.environ['EVENT_BUS_NAME']
                    }]
                )
                
                print(f"Published event {domain_event['EventId']} to EventBridge")
        
        return {'statusCode': 200}
        
    except Exception as e:
        print(f"Error processing stream: {str(e)}")
        raise

def deserialize_dynamodb_item(item):
    """Convert DynamoDB item format to regular Python objects"""
    if isinstance(item, dict):
        if len(item) == 1:
            key, value = next(iter(item.items()))
            if key == 'S':
                return value
            elif key == 'N':
                return Decimal(value)
            elif key == 'B':
                return value
            elif key == 'SS':
                return set(value)
            elif key == 'NS':
                return set(Decimal(v) for v in value)
            elif key == 'BS':
                return set(value)
            elif key == 'M':
                return {k: deserialize_dynamodb_item(v) for k, v in value.items()}
            elif key == 'L':
                return [deserialize_dynamodb_item(v) for v in value]
            elif key == 'NULL':
                return None
            elif key == 'BOOL':
                return value
        else:
            return {k: deserialize_dynamodb_item(v) for k, v in item.items()}
    return item
      `),
    });

    // Connect DynamoDB Stream to Stream Processor
    streamProcessor.addEventSource(
      new DynamoEventSource(this.eventStore, {
        startingPosition: lambda.StartingPosition.LATEST,
        batchSize: 10,
        retryAttempts: 3,
      })
    );

    // Create User Projection Handler
    // Maintains user profile read model
    const userProjectionHandler = new lambda.Function(this, 'UserProjectionHandler', {
      functionName: `cqrs-user-projection-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: projectionRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      environment: {
        USER_READ_MODEL_TABLE: this.userReadModel.tableName,
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
import json
import boto3
import os

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        detail = event['detail']
        event_type = detail['EventType']
        event_data = detail['EventData']
        
        table = dynamodb.Table(os.environ['USER_READ_MODEL_TABLE'])
        
        if event_type == 'UserCreated':
            # Create user profile projection
            table.put_item(
                Item={
                    'UserId': event_data['userId'],
                    'Email': event_data['email'],
                    'Name': event_data['name'],
                    'CreatedAt': event_data['createdAt'],
                    'UpdatedAt': event_data['createdAt'],
                    'Version': detail['Version']
                }
            )
            print(f"Created user profile for {event_data['userId']}")
            
        elif event_type == 'UserProfileUpdated':
            # Update user profile projection
            update_expression = "SET UpdatedAt = :updated, Version = :version"
            expression_values = {
                ':updated': event_data['updatedAt'],
                ':version': detail['Version']
            }
            
            # Build update expression for changes
            for field, value in event_data['changes'].items():
                if field in ['Name', 'Email']:  # Allow only certain fields
                    update_expression += f", {field} = :{field.lower()}"
                    expression_values[f":{field.lower()}"] = value
            
            table.update_item(
                Key={'UserId': event_data['userId']},
                UpdateExpression=update_expression,
                ExpressionAttributeValues=expression_values
            )
            print(f"Updated user profile for {event_data['userId']}")
        
        return {'statusCode': 200}
        
    except Exception as e:
        print(f"Error in user projection: {str(e)}")
        raise
      `),
    });

    // Create Order Projection Handler
    // Maintains order summary read model
    const orderProjectionHandler = new lambda.Function(this, 'OrderProjectionHandler', {
      functionName: `cqrs-order-projection-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: projectionRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      environment: {
        ORDER_READ_MODEL_TABLE: this.orderReadModel.tableName,
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        detail = event['detail']
        event_type = detail['EventType']
        event_data = detail['EventData']
        
        table = dynamodb.Table(os.environ['ORDER_READ_MODEL_TABLE'])
        
        if event_type == 'OrderCreated':
            # Create order summary projection
            table.put_item(
                Item={
                    'OrderId': event_data['orderId'],
                    'UserId': event_data['userId'],
                    'Items': event_data['items'],
                    'TotalAmount': Decimal(str(event_data['totalAmount'])),
                    'Status': 'Created',
                    'CreatedAt': event_data['createdAt'],
                    'UpdatedAt': event_data['createdAt'],
                    'Version': detail['Version']
                }
            )
            print(f"Created order summary for {event_data['orderId']}")
            
        elif event_type == 'OrderStatusUpdated':
            # Update order status in projection
            table.update_item(
                Key={'OrderId': event_data['orderId']},
                UpdateExpression="SET #status = :status, UpdatedAt = :updated, Version = :version",
                ExpressionAttributeNames={'#status': 'Status'},
                ExpressionAttributeValues={
                    ':status': event_data['status'],
                    ':updated': event_data['updatedAt'],
                    ':version': detail['Version']
                }
            )
            print(f"Updated order status for {event_data['orderId']}")
        
        return {'statusCode': 200}
        
    except Exception as e:
        print(f"Error in order projection: {str(e)}")
        raise
      `),
    });

    // Create Query Handler Lambda Function
    // Serves optimized read queries from read models
    this.queryHandler = new lambda.Function(this, 'QueryHandler', {
      functionName: `cqrs-query-handler-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: projectionRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      environment: {
        USER_READ_MODEL_TABLE: this.userReadModel.tableName,
        ORDER_READ_MODEL_TABLE: this.orderReadModel.tableName,
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from boto3.dynamodb.conditions import Key
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        # Parse query from API Gateway or direct invocation
        query = json.loads(event['body']) if 'body' in event else event
        query_type = query.get('queryType')
        
        if query_type == 'GetUserProfile':
            result = get_user_profile(query['userId'])
        elif query_type == 'GetUserByEmail':
            result = get_user_by_email(query['email'])
        elif query_type == 'GetOrdersByUser':
            result = get_orders_by_user(query['userId'])
        elif query_type == 'GetOrdersByStatus':
            result = get_orders_by_status(query['status'])
        elif query_type == 'GetOrder':
            result = get_order(query['orderId'])
        else:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': f'Unknown query type: {query_type}'})
            }
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps(result, default=decimal_encoder)
        }
        
    except Exception as e:
        print(f"Error processing query: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Internal server error'})
        }

def get_user_profile(user_id):
    table = dynamodb.Table(os.environ['USER_READ_MODEL_TABLE'])
    response = table.get_item(Key={'UserId': user_id})
    return response.get('Item')

def get_user_by_email(email):
    table = dynamodb.Table(os.environ['USER_READ_MODEL_TABLE'])
    response = table.query(
        IndexName='Email-index',
        KeyConditionExpression=Key('Email').eq(email)
    )
    return response['Items'][0] if response['Items'] else None

def get_orders_by_user(user_id):
    table = dynamodb.Table(os.environ['ORDER_READ_MODEL_TABLE'])
    response = table.query(
        IndexName='UserId-index',
        KeyConditionExpression=Key('UserId').eq(user_id)
    )
    return response['Items']

def get_orders_by_status(status):
    table = dynamodb.Table(os.environ['ORDER_READ_MODEL_TABLE'])
    response = table.query(
        IndexName='Status-index',
        KeyConditionExpression=Key('Status').eq(status)
    )
    return response['Items']

def get_order(order_id):
    table = dynamodb.Table(os.environ['ORDER_READ_MODEL_TABLE'])
    response = table.get_item(Key={'OrderId': order_id})
    return response.get('Item')

def decimal_encoder(obj):
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError
      `),
    });

    // Create EventBridge Rules for Event Routing
    // Route user events to user projection handler
    const userEventsRule = new events.Rule(this, 'UserEventsRule', {
      ruleName: `cqrs-user-events-${uniqueSuffix}`,
      eventBus: this.eventBus,
      eventPattern: {
        source: ['cqrs.demo'],
        detailType: ['UserCreated', 'UserProfileUpdated'],
      },
      description: 'Route user domain events to user projection handler',
    });

    userEventsRule.addTarget(new targets.LambdaFunction(userProjectionHandler));

    // Route order events to order projection handler
    const orderEventsRule = new events.Rule(this, 'OrderEventsRule', {
      ruleName: `cqrs-order-events-${uniqueSuffix}`,
      eventBus: this.eventBus,
      eventPattern: {
        source: ['cqrs.demo'],
        detailType: ['OrderCreated', 'OrderStatusUpdated'],
      },
      description: 'Route order domain events to order projection handler',
    });

    orderEventsRule.addTarget(new targets.LambdaFunction(orderProjectionHandler));

    // Stack Outputs
    new cdk.CfnOutput(this, 'EventStoreTableName', {
      value: this.eventStore.tableName,
      description: 'Name of the Event Store DynamoDB table',
    });

    new cdk.CfnOutput(this, 'UserReadModelTableName', {
      value: this.userReadModel.tableName,
      description: 'Name of the User Read Model DynamoDB table',
    });

    new cdk.CfnOutput(this, 'OrderReadModelTableName', {
      value: this.orderReadModel.tableName,
      description: 'Name of the Order Read Model DynamoDB table',
    });

    new cdk.CfnOutput(this, 'EventBusName', {
      value: this.eventBus.eventBusName,
      description: 'Name of the custom EventBridge bus',
    });

    new cdk.CfnOutput(this, 'CommandHandlerFunctionName', {
      value: this.commandHandler.functionName,
      description: 'Name of the Command Handler Lambda function',
    });

    new cdk.CfnOutput(this, 'QueryHandlerFunctionName', {
      value: this.queryHandler.functionName,
      description: 'Name of the Query Handler Lambda function',
    });

    new cdk.CfnOutput(this, 'EventBusArn', {
      value: this.eventBus.eventBusArn,
      description: 'ARN of the custom EventBridge bus',
    });
  }
}

// Create the CDK App
const app = new cdk.App();

// Deploy the CQRS Event Sourcing Stack
new CqrsEventSourcingStack(app, 'CqrsEventSourcingStack', {
  description: 'CQRS and Event Sourcing architecture with EventBridge and DynamoDB',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'CQRS-EventSourcing',
    Environment: 'Demo',
    Architecture: 'Event-Driven',
    Pattern: 'CQRS',
  },
});

// Synthesize the CloudFormation template
app.synth();