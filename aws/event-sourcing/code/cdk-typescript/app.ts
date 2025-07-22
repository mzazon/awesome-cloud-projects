#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import { Duration } from 'aws-cdk-lib';

/**
 * Event Sourcing Architecture Stack
 * 
 * This stack implements an event sourcing architecture using:
 * - EventBridge for event routing and processing
 * - DynamoDB for event store and read models
 * - Lambda functions for command and query processing
 * - CloudWatch for monitoring and alerting
 * - SQS for dead letter queues
 */
export class EventSourcingArchitectureStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const randomSuffix = Math.random().toString(36).substring(2, 8);

    // =============================================
    // DynamoDB Tables
    // =============================================

    // Event Store Table - stores immutable events with composite key for ordering
    const eventStoreTable = new dynamodb.Table(this, 'EventStoreTable', {
      tableName: `event-store-${randomSuffix}`,
      partitionKey: {
        name: 'AggregateId',
        type: dynamodb.AttributeType.STRING
      },
      sortKey: {
        name: 'EventSequence',
        type: dynamodb.AttributeType.NUMBER
      },
      billingMode: dynamodb.BillingMode.PROVISIONED,
      readCapacity: 10,
      writeCapacity: 10,
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes only
      tags: {
        Purpose: 'EventStore',
        Pattern: 'EventSourcing'
      }
    });

    // Global Secondary Index for querying by event type and timestamp
    eventStoreTable.addGlobalSecondaryIndex({
      indexName: 'EventType-Timestamp-index',
      partitionKey: {
        name: 'EventType',
        type: dynamodb.AttributeType.STRING
      },
      sortKey: {
        name: 'Timestamp',
        type: dynamodb.AttributeType.STRING
      },
      readCapacity: 5,
      writeCapacity: 5,
      projectionType: dynamodb.ProjectionType.ALL
    });

    // Read Model Table - stores materialized views for CQRS query side
    const readModelTable = new dynamodb.Table(this, 'ReadModelTable', {
      tableName: `read-model-${randomSuffix}`,
      partitionKey: {
        name: 'AccountId',
        type: dynamodb.AttributeType.STRING
      },
      sortKey: {
        name: 'ProjectionType',
        type: dynamodb.AttributeType.STRING
      },
      billingMode: dynamodb.BillingMode.PROVISIONED,
      readCapacity: 5,
      writeCapacity: 5,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes only
      tags: {
        Purpose: 'ReadModel',
        Pattern: 'CQRS'
      }
    });

    // =============================================
    // EventBridge Custom Bus
    // =============================================

    // Custom EventBridge bus for event sourcing
    const eventBus = new events.EventBus(this, 'EventSourcingBus', {
      eventBusName: `event-sourcing-bus-${randomSuffix}`,
      description: 'Event sourcing bus for financial transactions'
    });

    // Event Archive for replay capability
    const eventArchive = new events.Archive(this, 'EventArchive', {
      archiveName: `${eventBus.eventBusName}-archive`,
      sourceEventBus: eventBus,
      retention: Duration.days(365),
      description: 'Archive for event replay and audit'
    });

    // =============================================
    // Dead Letter Queue
    // =============================================

    // Dead Letter Queue for failed event processing
    const deadLetterQueue = new sqs.Queue(this, 'EventSourcingDLQ', {
      queueName: `event-sourcing-dlq-${randomSuffix}`,
      retentionPeriod: Duration.days(14),
      visibilityTimeout: Duration.minutes(5)
    });

    // =============================================
    // IAM Roles
    // =============================================

    // Lambda execution role with necessary permissions
    const lambdaExecutionRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `event-sourcing-lambda-role-${randomSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ]
    });

    // Custom policy for EventBridge and DynamoDB access
    const eventSourcingPolicy = new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'events:PutEvents',
        'events:List*',
        'events:Describe*',
        'dynamodb:PutItem',
        'dynamodb:GetItem',
        'dynamodb:Query',
        'dynamodb:Scan',
        'dynamodb:UpdateItem',
        'dynamodb:DeleteItem',
        'dynamodb:BatchGetItem',
        'dynamodb:BatchWriteItem'
      ],
      resources: ['*']
    });

    lambdaExecutionRole.addToPolicy(eventSourcingPolicy);

    // =============================================
    // Lambda Functions
    // =============================================

    // Command Handler Lambda - processes commands and generates events
    const commandHandler = new lambda.Function(this, 'CommandHandler', {
      functionName: `command-handler-${randomSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: Duration.seconds(30),
      memorySize: 512,
      environment: {
        EVENT_STORE_TABLE: eventStoreTable.tableName,
        EVENT_BUS_NAME: eventBus.eventBusName
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
from datetime import datetime
import os

events_client = boto3.client('events')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['EVENT_STORE_TABLE'])

def lambda_handler(event, context):
    try:
        # Parse command from event
        command = json.loads(event['body']) if 'body' in event else event
        
        # Generate event from command
        event_id = str(uuid.uuid4())
        aggregate_id = command['aggregateId']
        event_type = command['eventType']
        event_data = command['eventData']
        
        # Get next sequence number
        response = table.query(
            KeyConditionExpression='AggregateId = :aid',
            ExpressionAttributeValues={':aid': aggregate_id},
            ScanIndexForward=False,
            Limit=1
        )
        
        next_sequence = 1
        if response['Items']:
            next_sequence = response['Items'][0]['EventSequence'] + 1
        
        # Create event record
        timestamp = datetime.utcnow().isoformat()
        event_record = {
            'EventId': event_id,
            'AggregateId': aggregate_id,
            'EventSequence': next_sequence,
            'EventType': event_type,
            'EventData': event_data,
            'Timestamp': timestamp,
            'Version': '1.0'
        }
        
        # Store event in DynamoDB
        table.put_item(Item=event_record)
        
        # Publish event to EventBridge
        events_client.put_events(
            Entries=[
                {
                    'Source': 'event-sourcing.financial',
                    'DetailType': event_type,
                    'Detail': json.dumps(event_record),
                    'EventBusName': os.environ['EVENT_BUS_NAME']
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'eventId': event_id,
                'aggregateId': aggregate_id,
                'sequence': next_sequence
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
      `),
      description: 'Command handler for event sourcing - processes commands and generates events'
    });

    // Projection Handler Lambda - materializes read models from events
    const projectionHandler = new lambda.Function(this, 'ProjectionHandler', {
      functionName: `projection-handler-${randomSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: Duration.seconds(30),
      memorySize: 512,
      environment: {
        READ_MODEL_TABLE: readModelTable.tableName
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
read_model_table = dynamodb.Table(os.environ['READ_MODEL_TABLE'])

def lambda_handler(event, context):
    try:
        # Process EventBridge events
        for record in event['Records']:
            detail = json.loads(record['body']) if 'body' in record else record['detail']
            
            event_type = detail['EventType']
            aggregate_id = detail['AggregateId']
            event_data = detail['EventData']
            
            # Handle different event types
            if event_type == 'AccountCreated':
                handle_account_created(aggregate_id, event_data)
            elif event_type == 'TransactionProcessed':
                handle_transaction_processed(aggregate_id, event_data)
            elif event_type == 'AccountClosed':
                handle_account_closed(aggregate_id, event_data)
                
        return {'statusCode': 200}
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}

def handle_account_created(aggregate_id, event_data):
    read_model_table.put_item(
        Item={
            'AccountId': aggregate_id,
            'ProjectionType': 'AccountSummary',
            'Balance': Decimal('0.00'),
            'Status': 'Active',
            'CreatedAt': event_data['createdAt'],
            'TransactionCount': 0
        }
    )

def handle_transaction_processed(aggregate_id, event_data):
    # Update account balance
    response = read_model_table.get_item(
        Key={'AccountId': aggregate_id, 'ProjectionType': 'AccountSummary'}
    )
    
    if 'Item' in response:
        current_balance = response['Item']['Balance']
        transaction_count = response['Item']['TransactionCount']
        
        new_balance = current_balance + Decimal(str(event_data['amount']))
        
        read_model_table.update_item(
            Key={'AccountId': aggregate_id, 'ProjectionType': 'AccountSummary'},
            UpdateExpression='SET Balance = :balance, TransactionCount = :count, LastTransactionAt = :timestamp',
            ExpressionAttributeValues={
                ':balance': new_balance,
                ':count': transaction_count + 1,
                ':timestamp': event_data['timestamp']
            }
        )

def handle_account_closed(aggregate_id, event_data):
    read_model_table.update_item(
        Key={'AccountId': aggregate_id, 'ProjectionType': 'AccountSummary'},
        UpdateExpression='SET #status = :status, ClosedAt = :timestamp',
        ExpressionAttributeNames={'#status': 'Status'},
        ExpressionAttributeValues={
            ':status': 'Closed',
            ':timestamp': event_data['closedAt']
        }
    )
      `),
      description: 'Projection handler for CQRS - materializes read models from events'
    });

    // Query Handler Lambda - handles queries and event reconstruction
    const queryHandler = new lambda.Function(this, 'QueryHandler', {
      functionName: `query-handler-${randomSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: Duration.seconds(30),
      memorySize: 512,
      environment: {
        EVENT_STORE_TABLE: eventStoreTable.tableName,
        READ_MODEL_TABLE: readModelTable.tableName
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource('dynamodb')
event_store_table = dynamodb.Table(os.environ['EVENT_STORE_TABLE'])
read_model_table = dynamodb.Table(os.environ['READ_MODEL_TABLE'])

def lambda_handler(event, context):
    try:
        query_type = event['queryType']
        
        if query_type == 'getAggregateEvents':
            return get_aggregate_events(event['aggregateId'])
        elif query_type == 'getAccountSummary':
            return get_account_summary(event['accountId'])
        elif query_type == 'reconstructState':
            return reconstruct_state(event['aggregateId'], event.get('upToSequence'))
        else:
            return {'statusCode': 400, 'body': json.dumps({'error': 'Unknown query type'})}
            
    except Exception as e:
        print(f"Error: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}

def get_aggregate_events(aggregate_id):
    response = event_store_table.query(
        KeyConditionExpression=Key('AggregateId').eq(aggregate_id),
        ScanIndexForward=True
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'aggregateId': aggregate_id,
            'events': response['Items']
        }, default=str)
    }

def get_account_summary(account_id):
    response = read_model_table.get_item(
        Key={'AccountId': account_id, 'ProjectionType': 'AccountSummary'}
    )
    
    if 'Item' in response:
        return {
            'statusCode': 200,
            'body': json.dumps(response['Item'], default=str)
        }
    else:
        return {'statusCode': 404, 'body': json.dumps({'error': 'Account not found'})}

def reconstruct_state(aggregate_id, up_to_sequence=None):
    # Reconstruct state by replaying events
    key_condition = Key('AggregateId').eq(aggregate_id)
    
    if up_to_sequence:
        key_condition = key_condition & Key('EventSequence').lte(up_to_sequence)
    
    response = event_store_table.query(
        KeyConditionExpression=key_condition,
        ScanIndexForward=True
    )
    
    # Replay events to reconstruct state
    state = {'balance': 0, 'status': 'Unknown', 'transactionCount': 0}
    
    for event in response['Items']:
        event_type = event['EventType']
        event_data = event['EventData']
        
        if event_type == 'AccountCreated':
            state['status'] = 'Active'
            state['createdAt'] = event_data['createdAt']
        elif event_type == 'TransactionProcessed':
            state['balance'] += float(event_data['amount'])
            state['transactionCount'] += 1
        elif event_type == 'AccountClosed':
            state['status'] = 'Closed'
            state['closedAt'] = event_data['closedAt']
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'aggregateId': aggregate_id,
            'reconstructedState': state,
            'eventsProcessed': len(response['Items'])
        }, default=str)
    }
      `),
      description: 'Query handler for event sourcing - handles queries and event reconstruction'
    });

    // =============================================
    // EventBridge Rules and Targets
    // =============================================

    // Rule for routing financial events to projection handler
    const financialEventsRule = new events.Rule(this, 'FinancialEventsRule', {
      eventBus: eventBus,
      ruleName: 'financial-events-rule',
      description: 'Route financial events to projection handler',
      eventPattern: {
        source: ['event-sourcing.financial'],
        detailType: ['AccountCreated', 'TransactionProcessed', 'AccountClosed']
      }
    });

    // Add projection handler as target
    financialEventsRule.addTarget(new targets.LambdaFunction(projectionHandler));

    // Rule for failed events routing to DLQ
    const failedEventsRule = new events.Rule(this, 'FailedEventsRule', {
      eventBus: eventBus,
      ruleName: 'failed-events-rule',
      description: 'Route failed events to dead letter queue',
      eventPattern: {
        source: ['aws.events'],
        detailType: ['Event Processing Failed']
      }
    });

    // Add DLQ as target for failed events
    failedEventsRule.addTarget(new targets.SqsQueue(deadLetterQueue));

    // =============================================
    // CloudWatch Monitoring
    // =============================================

    // CloudWatch alarms for monitoring
    const eventStoreWriteThrottleAlarm = new cloudwatch.Alarm(this, 'EventStoreWriteThrottleAlarm', {
      alarmName: 'EventStore-WriteThrottles',
      alarmDescription: 'DynamoDB write throttles on event store',
      metric: eventStoreTable.metricUserErrors({
        metricName: 'WriteThrottleEvents',
        statistic: 'Sum'
      }),
      threshold: 5,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    const commandHandlerErrorAlarm = new cloudwatch.Alarm(this, 'CommandHandlerErrorAlarm', {
      alarmName: 'CommandHandler-Errors',
      alarmDescription: 'High error rate in command handler',
      metric: commandHandler.metricErrors({
        statistic: 'Sum'
      }),
      threshold: 10,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // =============================================
    // CloudWatch Log Groups
    // =============================================

    // Log groups for Lambda functions
    new logs.LogGroup(this, 'CommandHandlerLogGroup', {
      logGroupName: `/aws/lambda/${commandHandler.functionName}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    new logs.LogGroup(this, 'ProjectionHandlerLogGroup', {
      logGroupName: `/aws/lambda/${projectionHandler.functionName}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    new logs.LogGroup(this, 'QueryHandlerLogGroup', {
      logGroupName: `/aws/lambda/${queryHandler.functionName}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // =============================================
    // Stack Outputs
    // =============================================

    // Output important resource identifiers
    new cdk.CfnOutput(this, 'EventBusName', {
      value: eventBus.eventBusName,
      description: 'Name of the custom EventBridge bus'
    });

    new cdk.CfnOutput(this, 'EventStoreTableName', {
      value: eventStoreTable.tableName,
      description: 'Name of the DynamoDB event store table'
    });

    new cdk.CfnOutput(this, 'ReadModelTableName', {
      value: readModelTable.tableName,
      description: 'Name of the DynamoDB read model table'
    });

    new cdk.CfnOutput(this, 'CommandHandlerFunctionName', {
      value: commandHandler.functionName,
      description: 'Name of the command handler Lambda function'
    });

    new cdk.CfnOutput(this, 'ProjectionHandlerFunctionName', {
      value: projectionHandler.functionName,
      description: 'Name of the projection handler Lambda function'
    });

    new cdk.CfnOutput(this, 'QueryHandlerFunctionName', {
      value: queryHandler.functionName,
      description: 'Name of the query handler Lambda function'
    });

    new cdk.CfnOutput(this, 'DeadLetterQueueUrl', {
      value: deadLetterQueue.queueUrl,
      description: 'URL of the dead letter queue for failed events'
    });

    new cdk.CfnOutput(this, 'EventArchiveName', {
      value: eventArchive.archiveName,
      description: 'Name of the EventBridge archive for event replay'
    });

    // Tags for all resources
    cdk.Tags.of(this).add('Project', 'EventSourcingArchitecture');
    cdk.Tags.of(this).add('Pattern', 'EventSourcing-CQRS');
    cdk.Tags.of(this).add('Environment', 'Development');
  }
}

// =============================================
// CDK App
// =============================================

const app = new cdk.App();

// Create the stack
new EventSourcingArchitectureStack(app, 'EventSourcingArchitectureStack', {
  description: 'Event Sourcing Architecture with EventBridge and DynamoDB',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  },
  tags: {
    Application: 'EventSourcingDemo',
    CostCenter: 'Development',
    Owner: 'DevOps'
  }
});

// Synthesize the CloudFormation template
app.synth();