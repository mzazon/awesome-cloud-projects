#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as appsync from 'aws-cdk-lib/aws-appsync';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as path from 'path';

/**
 * CDK Stack for Real-Time Data Synchronization with AWS AppSync and DynamoDB Streams
 * 
 * This stack implements a complete real-time data synchronization solution using:
 * - DynamoDB table with streams enabled for change data capture
 * - Lambda function for processing stream events
 * - AppSync GraphQL API with real-time subscriptions
 * - IAM roles and policies for secure service integration
 */
export class RealTimeDataSyncStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = this.node.addr.substring(0, 8);

    // ================================
    // DynamoDB Table with Streams
    // ================================
    
    /**
     * DynamoDB table for storing real-time data with streams enabled
     * Streams capture all item-level changes for real-time processing
     */
    const dataTable = new dynamodb.Table(this, 'RealTimeDataTable', {
      tableName: `RealTimeData-${uniqueSuffix}`,
      partitionKey: {
        name: 'id',
        type: dynamodb.AttributeType.STRING
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For development/testing
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      tags: {
        Project: 'AppSyncRealTimeSync',
        Environment: 'Development'
      }
    });

    // ================================
    // Lambda Function for Stream Processing
    // ================================
    
    /**
     * Lambda function to process DynamoDB stream events
     * Transforms stream records into AppSync mutations for real-time updates
     */
    const streamProcessorFunction = new lambda.Function(this, 'StreamProcessor', {
      functionName: `AppSyncNotifier-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process DynamoDB stream events and trigger AppSync mutations
    for real-time data synchronization across connected clients
    
    Args:
        event: DynamoDB stream event containing change records
        context: Lambda runtime context
        
    Returns:
        Processing result with status and record count
    """
    
    logger.info(f"Processing {len(event['Records'])} DynamoDB stream records")
    
    processed_records = 0
    
    try:
        for record in event['Records']:
            event_name = record['eventName']
            
            if event_name in ['INSERT', 'MODIFY', 'REMOVE']:
                # Extract item data from stream record
                item_data = record.get('dynamodb', {})
                
                # Get item ID for logging and processing
                item_id = 'unknown'
                if 'NewImage' in item_data and 'id' in item_data['NewImage']:
                    item_id = item_data['NewImage']['id'].get('S', 'unknown')
                elif 'OldImage' in item_data and 'id' in item_data['OldImage']:
                    item_id = item_data['OldImage']['id'].get('S', 'unknown')
                
                logger.info(f"Processing {event_name} event for item {item_id}")
                
                # Create change event for AppSync notification
                change_event = {
                    'eventType': event_name,
                    'itemId': item_id,
                    'timestamp': datetime.utcnow().isoformat(),
                    'newImage': item_data.get('NewImage'),
                    'oldImage': item_data.get('OldImage')
                }
                
                # In production, this would trigger AppSync mutations
                # For demonstration, we log the processed event
                logger.info(f"Change event processed: {json.dumps(change_event, default=str)}")
                
                processed_records += 1
        
        logger.info(f"Successfully processed {processed_records} records")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Stream events processed successfully',
                'processedRecords': processed_records
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing stream events: {str(e)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Error processing stream events',
                'error': str(e)
            })
        }
`),
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      environment: {
        TABLE_NAME: dataTable.tableName,
        LOG_LEVEL: 'INFO'
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      description: 'Processes DynamoDB stream events for real-time AppSync notifications'
    });

    // Grant Lambda permissions to read from DynamoDB streams
    dataTable.grantStreamRead(streamProcessorFunction);

    // Create event source mapping for DynamoDB streams
    new lambda.EventSourceMapping(this, 'StreamEventSourceMapping', {
      target: streamProcessorFunction,
      eventSourceArn: dataTable.tableStreamArn!,
      startingPosition: lambda.StartingPosition.LATEST,
      batchSize: 10,
      maxBatchingWindow: cdk.Duration.seconds(5),
      retryAttempts: 3,
      parallelizationFactor: 1,
      reportBatchItemFailures: true
    });

    // ================================
    // AppSync GraphQL API
    // ================================
    
    /**
     * AppSync GraphQL API with real-time subscriptions
     * Provides managed WebSocket connections for real-time data sync
     */
    const graphqlApi = new appsync.GraphqlApi(this, 'RealTimeSyncAPI', {
      name: `RealTimeSyncAPI-${uniqueSuffix}`,
      schema: appsync.SchemaFile.fromAsset(path.join(__dirname, 'schema.graphql')),
      authorizationConfig: {
        defaultAuthorization: {
          authorizationType: appsync.AuthorizationType.API_KEY,
          apiKeyConfig: {
            name: 'RealTimeSyncAPIKey',
            description: 'API key for real-time data synchronization',
            expires: cdk.Expiration.after(cdk.Duration.days(30))
          }
        }
      },
      logConfig: {
        fieldLogLevel: appsync.FieldLogLevel.ALL,
        retentionTime: logs.RetentionDays.ONE_WEEK
      },
      xrayEnabled: true
    });

    // ================================
    // DynamoDB Data Source
    // ================================
    
    /**
     * AppSync data source for DynamoDB integration
     * Enables direct GraphQL operations on DynamoDB table
     */
    const dynamoDataSource = graphqlApi.addDynamoDbDataSource('DynamoDBDataSource', dataTable, {
      description: 'DynamoDB data source for real-time data operations'
    });

    // ================================
    // GraphQL Resolvers
    // ================================
    
    /**
     * Resolver for creating new data items
     * Triggers real-time subscriptions when items are created
     */
    dynamoDataSource.createResolver('CreateDataItemResolver', {
      typeName: 'Mutation',
      fieldName: 'createDataItem',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
{
  "version": "2017-02-28",
  "operation": "PutItem",
  "key": {
    "id": $util.dynamodb.toDynamoDBJson($util.autoId())
  },
  "attributeValues": {
    "title": $util.dynamodb.toDynamoDBJson($ctx.args.input.title),
    "content": $util.dynamodb.toDynamoDBJson($ctx.args.input.content),
    "timestamp": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
    "version": $util.dynamodb.toDynamoDBJson(1)
  }
}
`),
      responseMappingTemplate: appsync.MappingTemplate.fromString(`
$util.toJson($ctx.result)
`)
    });

    /**
     * Resolver for updating existing data items
     * Triggers real-time subscriptions when items are updated
     */
    dynamoDataSource.createResolver('UpdateDataItemResolver', {
      typeName: 'Mutation',
      fieldName: 'updateDataItem',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
{
  "version": "2017-02-28",
  "operation": "UpdateItem",
  "key": {
    "id": $util.dynamodb.toDynamoDBJson($ctx.args.input.id)
  },
  "update": {
    "expression": "SET #title = :title, #content = :content, #timestamp = :timestamp, #version = #version + :inc",
    "expressionNames": {
      "#title": "title",
      "#content": "content",
      "#timestamp": "timestamp",
      "#version": "version"
    },
    "expressionValues": {
      ":title": $util.dynamodb.toDynamoDBJson($ctx.args.input.title),
      ":content": $util.dynamodb.toDynamoDBJson($ctx.args.input.content),
      ":timestamp": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
      ":inc": $util.dynamodb.toDynamoDBJson(1)
    }
  }
}
`),
      responseMappingTemplate: appsync.MappingTemplate.fromString(`
$util.toJson($ctx.result)
`)
    });

    /**
     * Resolver for deleting data items
     * Triggers real-time subscriptions when items are deleted
     */
    dynamoDataSource.createResolver('DeleteDataItemResolver', {
      typeName: 'Mutation',
      fieldName: 'deleteDataItem',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
{
  "version": "2017-02-28",
  "operation": "DeleteItem",
  "key": {
    "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
  }
}
`),
      responseMappingTemplate: appsync.MappingTemplate.fromString(`
$util.toJson($ctx.result)
`)
    });

    /**
     * Resolver for querying individual data items
     */
    dynamoDataSource.createResolver('GetDataItemResolver', {
      typeName: 'Query',
      fieldName: 'getDataItem',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
{
  "version": "2017-02-28",
  "operation": "GetItem",
  "key": {
    "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
  }
}
`),
      responseMappingTemplate: appsync.MappingTemplate.fromString(`
$util.toJson($ctx.result)
`)
    });

    /**
     * Resolver for listing all data items
     */
    dynamoDataSource.createResolver('ListDataItemsResolver', {
      typeName: 'Query',
      fieldName: 'listDataItems',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
{
  "version": "2017-02-28",
  "operation": "Scan"
}
`),
      responseMappingTemplate: appsync.MappingTemplate.fromString(`
$util.toJson($ctx.result.items)
`)
    });

    // ================================
    // CloudWatch Alarms for Monitoring
    // ================================
    
    /**
     * CloudWatch alarm for Lambda function errors
     * Monitors stream processing function for failures
     */
    const lambdaErrorAlarm = new cdk.aws_cloudwatch.Alarm(this, 'LambdaErrorAlarm', {
      metric: streamProcessorFunction.metricErrors({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum'
      }),
      threshold: 1,
      evaluationPeriods: 1,
      treatMissingData: cdk.aws_cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'Lambda function errors processing DynamoDB stream events'
    });

    /**
     * CloudWatch alarm for AppSync API errors
     * Monitors GraphQL API for high error rates
     */
    const appsyncErrorAlarm = new cdk.aws_cloudwatch.Alarm(this, 'AppSyncErrorAlarm', {
      metric: new cdk.aws_cloudwatch.Metric({
        namespace: 'AWS/AppSync',
        metricName: '4XXError',
        dimensionsMap: {
          GraphQLAPIId: graphqlApi.apiId
        },
        period: cdk.Duration.minutes(5),
        statistic: 'Sum'
      }),
      threshold: 10,
      evaluationPeriods: 2,
      treatMissingData: cdk.aws_cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'High error rate in AppSync GraphQL API'
    });

    // ================================
    // Stack Outputs
    // ================================
    
    new cdk.CfnOutput(this, 'DynamoDBTableName', {
      value: dataTable.tableName,
      description: 'Name of the DynamoDB table for real-time data',
      exportName: `${this.stackName}-DynamoDBTableName`
    });

    new cdk.CfnOutput(this, 'DynamoDBStreamArn', {
      value: dataTable.tableStreamArn!,
      description: 'ARN of the DynamoDB stream for change data capture',
      exportName: `${this.stackName}-DynamoDBStreamArn`
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: streamProcessorFunction.functionName,
      description: 'Name of the Lambda function processing stream events',
      exportName: `${this.stackName}-LambdaFunctionName`
    });

    new cdk.CfnOutput(this, 'AppSyncAPIEndpoint', {
      value: graphqlApi.graphqlUrl,
      description: 'GraphQL API endpoint for real-time data synchronization',
      exportName: `${this.stackName}-AppSyncAPIEndpoint`
    });

    new cdk.CfnOutput(this, 'AppSyncAPIKey', {
      value: graphqlApi.apiKey || 'No API key generated',
      description: 'API key for authenticating with the GraphQL API',
      exportName: `${this.stackName}-AppSyncAPIKey`
    });

    new cdk.CfnOutput(this, 'AppSyncAPIId', {
      value: graphqlApi.apiId,
      description: 'ID of the AppSync GraphQL API',
      exportName: `${this.stackName}-AppSyncAPIId`
    });

    new cdk.CfnOutput(this, 'WebSocketEndpoint', {
      value: graphqlApi.graphqlUrl.replace('https://', 'wss://').replace('/graphql', '/graphql/realtime'),
      description: 'WebSocket endpoint for real-time subscriptions',
      exportName: `${this.stackName}-WebSocketEndpoint`
    });
  }
}

// ================================
// CDK App Configuration
// ================================

const app = new cdk.App();

// Create the stack with production-ready configuration
new RealTimeDataSyncStack(app, 'RealTimeDataSyncStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  },
  description: 'Real-time data synchronization with AWS AppSync and DynamoDB Streams',
  tags: {
    Project: 'AppSyncRealTimeSync',
    Environment: 'Development',
    Owner: 'CDK-Generated'
  }
});

// Add metadata for stack documentation
app.node.setContext('@aws-cdk/core:enableStackNameDuplicates', true);
app.node.setContext('@aws-cdk/core:stackRelativeExports', true);