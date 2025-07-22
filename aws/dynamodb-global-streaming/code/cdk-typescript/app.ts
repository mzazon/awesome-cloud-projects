#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as kinesis from 'aws-cdk-lib/aws-kinesis';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as eventSources from 'aws-cdk-lib/aws-lambda-event-sources';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import { Duration, RemovalPolicy, Stack, StackProps } from 'aws-cdk-lib';

/**
 * Configuration interface for the DynamoDB Global Tables streaming stack
 */
interface DynamoDBGlobalTablesConfig {
  readonly tableName: string;
  readonly streamName: string;
  readonly regions: string[];
  readonly enablePointInTimeRecovery: boolean;
  readonly enableKinesisStreaming: boolean;
}

/**
 * Stack for DynamoDB Global Tables with advanced streaming capabilities
 * Implements multi-region DynamoDB Global Tables with both DynamoDB Streams
 * and Kinesis Data Streams for comprehensive event processing
 */
class DynamoDBGlobalTablesStack extends Stack {
  public readonly table: dynamodb.Table;
  public readonly kinesisStream: kinesis.Stream;
  public readonly streamProcessorLambda: lambda.Function;
  public readonly kinesisProcessorLambda: lambda.Function;
  public readonly eventBus: events.EventBus;

  constructor(scope: Construct, id: string, config: DynamoDBGlobalTablesConfig, props?: StackProps) {
    super(scope, id, props);

    // Create the primary DynamoDB table with streams enabled
    this.table = this.createDynamoDBTable(config);

    // Create Kinesis Data Stream for analytics
    this.kinesisStream = this.createKinesisStream(config);

    // Create IAM role for Lambda functions
    const lambdaRole = this.createLambdaExecutionRole();

    // Create EventBridge custom event bus
    this.eventBus = this.createEventBus();

    // Create Lambda function for DynamoDB Streams processing
    this.streamProcessorLambda = this.createStreamProcessorLambda(lambdaRole, config);

    // Create Lambda function for Kinesis Data Streams processing
    this.kinesisProcessorLambda = this.createKinesisProcessorLambda(lambdaRole, config);

    // Configure event source mappings
    this.configureEventSources();

    // Enable Kinesis Data Streams integration for DynamoDB
    if (config.enableKinesisStreaming) {
      this.enableKinesisStreaming(config);
    }

    // Create CloudWatch dashboard for monitoring
    this.createMonitoringDashboard(config);

    // Configure Global Tables replication (requires manual setup in other regions)
    this.addGlobalTablesInstructions();

    // Add stack outputs
    this.addStackOutputs(config);
  }

  /**
   * Creates the primary DynamoDB table with streams and GSI
   */
  private createDynamoDBTable(config: DynamoDBGlobalTablesConfig): dynamodb.Table {
    const table = new dynamodb.Table(this, 'ECommerceTable', {
      tableName: config.tableName,
      partitionKey: {
        name: 'PK',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'SK',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
      pointInTimeRecovery: config.enablePointInTimeRecovery,
      removalPolicy: RemovalPolicy.DESTROY, // For demo purposes
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
    });

    // Add Global Secondary Index
    table.addGlobalSecondaryIndex({
      indexName: 'GSI1',
      partitionKey: {
        name: 'GSI1PK',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'GSI1SK',
        type: dynamodb.AttributeType.STRING,
      },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // Add tags
    cdk.Tags.of(table).add('Application', 'ECommerce');
    cdk.Tags.of(table).add('Environment', 'Production');
    cdk.Tags.of(table).add('Purpose', 'GlobalTablesDemo');

    return table;
  }

  /**
   * Creates Kinesis Data Stream for analytics processing
   */
  private createKinesisStream(config: DynamoDBGlobalTablesConfig): kinesis.Stream {
    const stream = new kinesis.Stream(this, 'ECommerceKinesisStream', {
      streamName: config.streamName,
      shardCount: 3,
      retentionPeriod: Duration.days(7), // Extended retention for analytics
      encryption: kinesis.StreamEncryption.MANAGED,
    });

    // Add tags
    cdk.Tags.of(stream).add('Application', 'ECommerce');
    cdk.Tags.of(stream).add('Environment', 'Production');
    cdk.Tags.of(stream).add('Purpose', 'StreamAnalytics');

    return stream;
  }

  /**
   * Creates IAM role for Lambda execution with necessary permissions
   */
  private createLambdaExecutionRole(): iam.Role {
    const role = new iam.Role(this, 'LambdaExecutionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for DynamoDB and Kinesis stream processing Lambda functions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Add DynamoDB permissions
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'dynamodb:DescribeStream',
        'dynamodb:GetRecords',
        'dynamodb:GetShardIterator',
        'dynamodb:ListStreams',
        'dynamodb:Query',
        'dynamodb:Scan',
        'dynamodb:GetItem',
      ],
      resources: ['*'], // Will be scoped properly in production
    }));

    // Add Kinesis permissions
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'kinesis:DescribeStream',
        'kinesis:GetRecords',
        'kinesis:GetShardIterator',
        'kinesis:ListStreams',
        'kinesis:PutRecord',
        'kinesis:PutRecords',
      ],
      resources: ['*'], // Will be scoped properly in production
    }));

    // Add EventBridge permissions
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'events:PutEvents',
      ],
      resources: ['*'],
    }));

    // Add CloudWatch permissions
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'cloudwatch:PutMetricData',
      ],
      resources: ['*'],
    }));

    return role;
  }

  /**
   * Creates custom EventBridge event bus for business events
   */
  private createEventBus(): events.EventBus {
    return new events.EventBus(this, 'ECommerceEventBus', {
      eventBusName: 'ecommerce-business-events',
      description: 'Custom event bus for e-commerce business events',
    });
  }

  /**
   * Creates Lambda function for processing DynamoDB Streams
   */
  private createStreamProcessorLambda(role: iam.Role, config: DynamoDBGlobalTablesConfig): lambda.Function {
    return new lambda.Function(this, 'StreamProcessorLambda', {
      functionName: `${config.tableName}-stream-processor`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: role,
      timeout: Duration.minutes(5),
      memorySize: 512,
      environment: {
        TABLE_NAME: config.tableName,
        EVENT_BUS_NAME: this.eventBus.eventBusName,
        REGION: this.region,
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from decimal import Decimal
from typing import Dict, Any, Optional

dynamodb = boto3.resource('dynamodb')
eventbridge = boto3.client('events')

def decimal_default(obj):
    """JSON serializer for Decimal objects"""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError(f"Object of type {type(obj)} is not JSON serializable")

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process DynamoDB Streams records for real-time business logic
    """
    try:
        processed_count = 0
        
        for record in event.get('Records', []):
            if record['eventName'] in ['INSERT', 'MODIFY', 'REMOVE']:
                process_record(record)
                processed_count += 1
        
        return {
            'statusCode': 200,
            'processedRecords': processed_count
        }
    except Exception as e:
        print(f"Error processing stream records: {str(e)}")
        raise

def process_record(record: Dict[str, Any]) -> None:
    """Process individual DynamoDB stream record"""
    event_name = record['eventName']
    table_name = record['eventSourceARN'].split('/')[-3]
    
    # Extract item data
    if 'NewImage' in record.get('dynamodb', {}):
        new_image = record['dynamodb']['NewImage']
        old_image = record['dynamodb'].get('OldImage', {})
        pk = new_image.get('PK', {}).get('S', '')
        
        # Route to appropriate processor based on entity type
        if pk.startswith('PRODUCT#'):
            process_product_event(event_name, new_image, old_image)
        elif pk.startswith('ORDER#'):
            process_order_event(event_name, new_image, old_image)
        elif pk.startswith('USER#'):
            process_user_event(event_name, new_image, old_image)

def process_product_event(event_name: str, new_image: Dict, old_image: Dict) -> None:
    """Handle product-related events"""
    if event_name == 'MODIFY' and old_image:
        old_stock = int(old_image.get('Stock', {}).get('N', '0'))
        new_stock = int(new_image.get('Stock', {}).get('N', '0'))
        
        if old_stock != new_stock:
            send_inventory_alert(new_image, old_stock, new_stock)
    elif event_name == 'INSERT':
        send_product_creation_event(new_image)

def process_order_event(event_name: str, new_image: Dict, old_image: Dict) -> None:
    """Handle order-related events"""
    if event_name == 'INSERT':
        send_order_notification(new_image)
    elif event_name == 'MODIFY':
        status_changed = check_order_status_change(new_image, old_image)
        if status_changed:
            send_status_update(new_image)

def process_user_event(event_name: str, new_image: Dict, old_image: Dict) -> None:
    """Handle user-related events"""
    if event_name == 'MODIFY':
        send_user_activity_event(new_image)

def send_inventory_alert(product: Dict, old_stock: int, new_stock: int) -> None:
    """Send inventory change alert to EventBridge"""
    try:
        eventbridge.put_events(
            Entries=[{
                'Source': 'ecommerce.inventory',
                'DetailType': 'Inventory Change',
                'Detail': json.dumps({
                    'productId': product.get('PK', {}).get('S', ''),
                    'productName': product.get('Name', {}).get('S', ''),
                    'oldStock': old_stock,
                    'newStock': new_stock,
                    'stockChange': new_stock - old_stock,
                    'timestamp': product.get('UpdatedAt', {}).get('S', ''),
                    'lowStockAlert': new_stock < 10
                }),
                'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
            }]
        )
    except Exception as e:
        print(f"Error sending inventory alert: {str(e)}")

def send_order_notification(order: Dict) -> None:
    """Send new order notification to EventBridge"""
    try:
        eventbridge.put_events(
            Entries=[{
                'Source': 'ecommerce.orders',
                'DetailType': 'New Order',
                'Detail': json.dumps({
                    'orderId': order.get('PK', {}).get('S', ''),
                    'customerId': order.get('CustomerId', {}).get('S', ''),
                    'amount': float(order.get('TotalAmount', {}).get('N', '0')),
                    'status': order.get('Status', {}).get('S', ''),
                    'timestamp': order.get('CreatedAt', {}).get('S', '')
                }),
                'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
            }]
        )
    except Exception as e:
        print(f"Error sending order notification: {str(e)}")

def send_status_update(order: Dict) -> None:
    """Send order status update to EventBridge"""
    try:
        eventbridge.put_events(
            Entries=[{
                'Source': 'ecommerce.orders',
                'DetailType': 'Order Status Update',
                'Detail': json.dumps({
                    'orderId': order.get('PK', {}).get('S', ''),
                    'status': order.get('Status', {}).get('S', ''),
                    'customerId': order.get('CustomerId', {}).get('S', ''),
                    'timestamp': order.get('UpdatedAt', {}).get('S', '')
                }),
                'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
            }]
        )
    except Exception as e:
        print(f"Error sending status update: {str(e)}")

def send_user_activity_event(user: Dict) -> None:
    """Send user activity event to EventBridge"""
    try:
        eventbridge.put_events(
            Entries=[{
                'Source': 'ecommerce.users',
                'DetailType': 'User Activity',
                'Detail': json.dumps({
                    'userId': user.get('PK', {}).get('S', ''),
                    'lastActive': user.get('LastActiveAt', {}).get('S', ''),
                    'timestamp': user.get('UpdatedAt', {}).get('S', '')
                }),
                'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
            }]
        )
    except Exception as e:
        print(f"Error sending user activity event: {str(e)}")

def send_product_creation_event(product: Dict) -> None:
    """Send product creation event to EventBridge"""
    try:
        eventbridge.put_events(
            Entries=[{
                'Source': 'ecommerce.products',
                'DetailType': 'Product Created',
                'Detail': json.dumps({
                    'productId': product.get('PK', {}).get('S', ''),
                    'productName': product.get('Name', {}).get('S', ''),
                    'category': product.get('GSI1PK', {}).get('S', ''),
                    'price': float(product.get('Price', {}).get('N', '0')),
                    'initialStock': int(product.get('Stock', {}).get('N', '0')),
                    'timestamp': product.get('CreatedAt', {}).get('S', '')
                }),
                'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
            }]
        )
    except Exception as e:
        print(f"Error sending product creation event: {str(e)}")

def check_order_status_change(new_image: Dict, old_image: Dict) -> bool:
    """Check if order status has changed"""
    if not old_image:
        return False
    old_status = old_image.get('Status', {}).get('S', '')
    new_status = new_image.get('Status', {}).get('S', '')
    return old_status != new_status
`),
      description: 'Processes DynamoDB Streams for real-time business logic',
    });
  }

  /**
   * Creates Lambda function for processing Kinesis Data Streams
   */
  private createKinesisProcessorLambda(role: iam.Role, config: DynamoDBGlobalTablesConfig): lambda.Function {
    return new lambda.Function(this, 'KinesisProcessorLambda', {
      functionName: `${config.streamName}-kinesis-processor`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: role,
      timeout: Duration.minutes(5),
      memorySize: 512,
      environment: {
        STREAM_NAME: config.streamName,
        REGION: this.region,
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
import json
import boto3
import base64
from datetime import datetime
from typing import Dict, Any, List

cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process Kinesis Data Streams records for analytics and monitoring
    """
    try:
        metrics_data = []
        processed_count = 0
        
        for record in event.get('Records', []):
            # Decode Kinesis data
            try:
                payload = json.loads(base64.b64decode(record['kinesis']['data']))
                process_kinesis_record(payload, metrics_data)
                processed_count += 1
            except Exception as e:
                print(f"Error processing record: {str(e)}")
                continue
        
        # Send metrics to CloudWatch
        if metrics_data:
            send_metrics(metrics_data)
        
        return {
            'statusCode': 200,
            'body': f'Processed {processed_count} records, generated {len(metrics_data)} metrics'
        }
    except Exception as e:
        print(f"Error in Kinesis processor: {str(e)}")
        raise

def process_kinesis_record(payload: Dict[str, Any], metrics_data: List[Dict]) -> None:
    """Process individual Kinesis record for analytics"""
    event_name = payload.get('eventName')
    
    if event_name == 'INSERT':
        process_insert_metrics(payload, metrics_data)
    elif event_name == 'MODIFY':
        process_modify_metrics(payload, metrics_data)
    elif event_name == 'REMOVE':
        process_remove_metrics(payload, metrics_data)

def process_insert_metrics(payload: Dict[str, Any], metrics_data: List[Dict]) -> None:
    """Process INSERT events for metrics"""
    dynamodb_data = payload.get('dynamodb', {})
    new_image = dynamodb_data.get('NewImage', {})
    pk = new_image.get('PK', {}).get('S', '')
    
    if pk.startswith('ORDER#'):
        amount = float(new_image.get('TotalAmount', {}).get('N', '0'))
        region = payload.get('awsRegion', 'unknown')
        
        metrics_data.extend([
            {
                'MetricName': 'NewOrders',
                'Value': 1,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'EntityType', 'Value': 'Order'},
                    {'Name': 'Region', 'Value': region}
                ]
            },
            {
                'MetricName': 'OrderValue',
                'Value': amount,
                'Unit': 'None',
                'Dimensions': [
                    {'Name': 'EntityType', 'Value': 'Order'},
                    {'Name': 'Region', 'Value': region}
                ]
            }
        ])
    elif pk.startswith('PRODUCT#'):
        region = payload.get('awsRegion', 'unknown')
        category = new_image.get('GSI1PK', {}).get('S', 'Unknown')
        
        metrics_data.append({
            'MetricName': 'NewProducts',
            'Value': 1,
            'Unit': 'Count',
            'Dimensions': [
                {'Name': 'EntityType', 'Value': 'Product'},
                {'Name': 'Region', 'Value': region},
                {'Name': 'Category', 'Value': category}
            ]
        })
    elif pk.startswith('USER#'):
        region = payload.get('awsRegion', 'unknown')
        
        metrics_data.append({
            'MetricName': 'NewUsers',
            'Value': 1,
            'Unit': 'Count',
            'Dimensions': [
                {'Name': 'EntityType', 'Value': 'User'},
                {'Name': 'Region', 'Value': region}
            ]
        })

def process_modify_metrics(payload: Dict[str, Any], metrics_data: List[Dict]) -> None:
    """Process MODIFY events for metrics"""
    dynamodb_data = payload.get('dynamodb', {})
    new_image = dynamodb_data.get('NewImage', {})
    old_image = dynamodb_data.get('OldImage', {})
    pk = new_image.get('PK', {}).get('S', '')
    region = payload.get('awsRegion', 'unknown')
    
    if pk.startswith('PRODUCT#'):
        old_stock = int(old_image.get('Stock', {}).get('N', '0'))
        new_stock = int(new_image.get('Stock', {}).get('N', '0'))
        stock_change = new_stock - old_stock
        
        if stock_change != 0:
            category = new_image.get('GSI1PK', {}).get('S', 'Unknown')
            
            metrics_data.extend([
                {
                    'MetricName': 'InventoryChange',
                    'Value': abs(stock_change),
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'EntityType', 'Value': 'Product'},
                        {'Name': 'ChangeType', 'Value': 'Increase' if stock_change > 0 else 'Decrease'},
                        {'Name': 'Region', 'Value': region},
                        {'Name': 'Category', 'Value': category}
                    ]
                },
                {
                    'MetricName': 'CurrentStock',
                    'Value': new_stock,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'EntityType', 'Value': 'Product'},
                        {'Name': 'Region', 'Value': region},
                        {'Name': 'Category', 'Value': category}
                    ]
                }
            ])
            
            # Low stock alert
            if new_stock < 10:
                metrics_data.append({
                    'MetricName': 'LowStockProducts',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'EntityType', 'Value': 'Product'},
                        {'Name': 'Region', 'Value': region},
                        {'Name': 'Category', 'Value': category}
                    ]
                })
    
    elif pk.startswith('ORDER#'):
        # Track order status changes
        old_status = old_image.get('Status', {}).get('S', '')
        new_status = new_image.get('Status', {}).get('S', '')
        
        if old_status != new_status:
            metrics_data.append({
                'MetricName': 'OrderStatusChanges',
                'Value': 1,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'EntityType', 'Value': 'Order'},
                    {'Name': 'OldStatus', 'Value': old_status},
                    {'Name': 'NewStatus', 'Value': new_status},
                    {'Name': 'Region', 'Value': region}
                ]
            })

def process_remove_metrics(payload: Dict[str, Any], metrics_data: List[Dict]) -> None:
    """Process REMOVE events for metrics"""
    dynamodb_data = payload.get('dynamodb', {})
    old_image = dynamodb_data.get('OldImage', {})
    pk = old_image.get('PK', {}).get('S', '')
    region = payload.get('awsRegion', 'unknown')
    
    if pk.startswith('ORDER#'):
        metrics_data.append({
            'MetricName': 'CancelledOrders',
            'Value': 1,
            'Unit': 'Count',
            'Dimensions': [
                {'Name': 'EntityType', 'Value': 'Order'},
                {'Name': 'Region', 'Value': region}
            ]
        })
    elif pk.startswith('PRODUCT#'):
        metrics_data.append({
            'MetricName': 'DeletedProducts',
            'Value': 1,
            'Unit': 'Count',
            'Dimensions': [
                {'Name': 'EntityType', 'Value': 'Product'},
                {'Name': 'Region', 'Value': region}
            ]
        })

def send_metrics(metrics_data: List[Dict]) -> None:
    """Send metrics to CloudWatch"""
    try:
        # CloudWatch has a limit of 20 metrics per call
        batch_size = 20
        for i in range(0, len(metrics_data), batch_size):
            batch = metrics_data[i:i + batch_size]
            
            cloudwatch.put_metric_data(
                Namespace='ECommerce/Global',
                MetricData=[{
                    **metric,
                    'Timestamp': datetime.utcnow()
                } for metric in batch]
            )
            
        print(f"Successfully sent {len(metrics_data)} metrics to CloudWatch")
    except Exception as e:
        print(f"Error sending metrics to CloudWatch: {str(e)}")
`),
      description: 'Processes Kinesis Data Streams for analytics and monitoring',
    });
  }

  /**
   * Configures event source mappings for Lambda functions
   */
  private configureEventSources(): void {
    // DynamoDB Streams event source mapping
    this.streamProcessorLambda.addEventSource(
      new eventSources.DynamoEventSource(this.table, {
        startingPosition: lambda.StartingPosition.LATEST,
        batchSize: 10,
        maxBatchingWindow: Duration.seconds(5),
        retryAttempts: 3,
        parallelizationFactor: 1,
        reportBatchItemFailures: true,
      })
    );

    // Kinesis Data Streams event source mapping
    this.kinesisProcessorLambda.addEventSource(
      new eventSources.KinesisEventSource(this.kinesisStream, {
        startingPosition: lambda.StartingPosition.LATEST,
        batchSize: 100,
        maxBatchingWindow: Duration.seconds(10),
        retryAttempts: 3,
        parallelizationFactor: 2,
        reportBatchItemFailures: true,
      })
    );
  }

  /**
   * Enables Kinesis Data Streams integration for DynamoDB
   * Note: This requires a custom resource in CDK as there's no direct construct
   */
  private enableKinesisStreaming(config: DynamoDBGlobalTablesConfig): void {
    // Custom resource to enable Kinesis Data Streams for DynamoDB
    const enableKinesisLambda = new lambda.Function(this, 'EnableKinesisStreaming', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.handler',
      timeout: Duration.minutes(5),
      code: lambda.Code.fromInline(`
import boto3
import json
import urllib3

def handler(event, context):
    dynamodb = boto3.client('dynamodb')
    
    try:
        if event['RequestType'] == 'Create' or event['RequestType'] == 'Update':
            response = dynamodb.enable_kinesis_streaming_destination(
                TableName='${config.tableName}',
                StreamArn='${this.kinesisStream.streamArn}'
            )
            print(f"Enabled Kinesis streaming: {response}")
        elif event['RequestType'] == 'Delete':
            try:
                response = dynamodb.disable_kinesis_streaming_destination(
                    TableName='${config.tableName}',
                    StreamArn='${this.kinesisStream.streamArn}'
                )
                print(f"Disabled Kinesis streaming: {response}")
            except Exception as e:
                print(f"Error disabling Kinesis streaming (may already be disabled): {e}")
        
        send_response(event, context, 'SUCCESS', {})
    except Exception as e:
        print(f"Error: {e}")
        send_response(event, context, 'FAILED', {})

def send_response(event, context, status, data):
    response_body = {
        'Status': status,
        'Reason': f'See CloudWatch logs for details: {context.log_group_name}',
        'PhysicalResourceId': f"enable-kinesis-{event['StackId'].split('/')[-1]}",
        'StackId': event['StackId'],
        'RequestId': event['RequestId'],
        'LogicalResourceId': event['LogicalResourceId'],
        'Data': data
    }
    
    http = urllib3.PoolManager()
    response = http.request('PUT', event['ResponseURL'], 
                          body=json.dumps(response_body),
                          headers={'Content-Type': 'application/json'})
    print(f"Response status: {response.status}")
`),
    });

    // Grant permissions
    enableKinesisLambda.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'dynamodb:EnableKinesisStreamingDestination',
        'dynamodb:DisableKinesisStreamingDestination',
      ],
      resources: [this.table.tableArn],
    }));

    // Create custom resource
    new cdk.CustomResource(this, 'KinesisStreamingIntegration', {
      serviceToken: enableKinesisLambda.functionArn,
      properties: {
        TableName: config.tableName,
        StreamArn: this.kinesisStream.streamArn,
      },
    });
  }

  /**
   * Creates CloudWatch dashboard for monitoring
   */
  private createMonitoringDashboard(config: DynamoDBGlobalTablesConfig): void {
    const dashboard = new cloudwatch.Dashboard(this, 'ECommerceDashboard', {
      dashboardName: 'ECommerce-Global-Monitoring',
      widgets: [
        [
          // DynamoDB metrics
          new cloudwatch.GraphWidget({
            title: 'DynamoDB Operations',
            left: [
              this.table.metricConsumedReadCapacityUnits(),
              this.table.metricConsumedWriteCapacityUnits(),
            ],
            width: 12,
            height: 6,
          }),
          
          // Kinesis metrics
          new cloudwatch.GraphWidget({
            title: 'Kinesis Stream Metrics',
            left: [
              this.kinesisStream.metricIncomingRecords(),
              this.kinesisStream.metricOutgoingRecords(),
            ],
            width: 12,
            height: 6,
          }),
        ],
        [
          // Lambda metrics
          new cloudwatch.GraphWidget({
            title: 'Lambda Function Performance',
            left: [
              this.streamProcessorLambda.metricInvocations(),
              this.kinesisProcessorLambda.metricInvocations(),
            ],
            right: [
              this.streamProcessorLambda.metricErrors(),
              this.kinesisProcessorLambda.metricErrors(),
            ],
            width: 12,
            height: 6,
          }),
          
          // Custom business metrics
          new cloudwatch.GraphWidget({
            title: 'Business Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'ECommerce/Global',
                metricName: 'NewOrders',
                dimensionsMap: { EntityType: 'Order' },
                statistic: 'Sum',
              }),
              new cloudwatch.Metric({
                namespace: 'ECommerce/Global',
                metricName: 'OrderValue',
                dimensionsMap: { EntityType: 'Order' },
                statistic: 'Sum',
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
      ],
    });
  }

  /**
   * Adds instructions for setting up Global Tables in other regions
   */
  private addGlobalTablesInstructions(): void {
    new cdk.CfnOutput(this, 'GlobalTablesSetupInstructions', {
      value: `
To complete Global Tables setup:
1. Deploy this stack in additional regions (${this.stackName})
2. Create Global Tables configuration using AWS CLI:
   aws dynamodb create-global-table --global-table-name ${this.table.tableName} --replication-group RegionName=us-east-1 RegionName=eu-west-1 RegionName=ap-southeast-1
3. Verify replication is working across all regions
      `,
      description: 'Instructions for completing Global Tables setup',
    });
  }

  /**
   * Adds stack outputs for important resources
   */
  private addStackOutputs(config: DynamoDBGlobalTablesConfig): void {
    new cdk.CfnOutput(this, 'TableName', {
      value: this.table.tableName,
      description: 'DynamoDB table name',
      exportName: `${this.stackName}-TableName`,
    });

    new cdk.CfnOutput(this, 'TableArn', {
      value: this.table.tableArn,
      description: 'DynamoDB table ARN',
      exportName: `${this.stackName}-TableArn`,
    });

    new cdk.CfnOutput(this, 'StreamArn', {
      value: this.table.tableStreamArn || 'Not available',
      description: 'DynamoDB Stream ARN',
      exportName: `${this.stackName}-StreamArn`,
    });

    new cdk.CfnOutput(this, 'KinesisStreamName', {
      value: this.kinesisStream.streamName,
      description: 'Kinesis Data Stream name',
      exportName: `${this.stackName}-KinesisStreamName`,
    });

    new cdk.CfnOutput(this, 'KinesisStreamArn', {
      value: this.kinesisStream.streamArn,
      description: 'Kinesis Data Stream ARN',
      exportName: `${this.stackName}-KinesisStreamArn`,
    });

    new cdk.CfnOutput(this, 'EventBusName', {
      value: this.eventBus.eventBusName,
      description: 'EventBridge custom event bus name',
      exportName: `${this.stackName}-EventBusName`,
    });

    new cdk.CfnOutput(this, 'StreamProcessorLambdaName', {
      value: this.streamProcessorLambda.functionName,
      description: 'DynamoDB Stream processor Lambda function name',
      exportName: `${this.stackName}-StreamProcessorLambdaName`,
    });

    new cdk.CfnOutput(this, 'KinesisProcessorLambdaName', {
      value: this.kinesisProcessorLambda.functionName,
      description: 'Kinesis Data Stream processor Lambda function name',
      exportName: `${this.stackName}-KinesisProcessorLambdaName`,
    });
  }
}

/**
 * CDK Application for DynamoDB Global Tables with Advanced Streaming
 */
class DynamoDBGlobalTablesApp extends cdk.App {
  constructor() {
    super();

    // Generate unique suffix for resources
    const randomSuffix = Math.random().toString(36).substring(2, 8);

    // Configuration for the solution
    const config: DynamoDBGlobalTablesConfig = {
      tableName: `ecommerce-global-${randomSuffix}`,
      streamName: `ecommerce-events-${randomSuffix}`,
      regions: ['us-east-1', 'eu-west-1', 'ap-southeast-1'],
      enablePointInTimeRecovery: true,
      enableKinesisStreaming: true,
    };

    // Primary region stack (us-east-1)
    new DynamoDBGlobalTablesStack(this, 'DynamoDBGlobalTablesStack-Primary', config, {
      env: {
        account: process.env.CDK_DEFAULT_ACCOUNT,
        region: 'us-east-1',
      },
      description: 'Primary region stack for DynamoDB Global Tables with advanced streaming (us-east-1)',
      tags: {
        Application: 'ECommerce',
        Environment: 'Production',
        Region: 'Primary',
        Purpose: 'GlobalTablesDemo',
      },
    });

    // Secondary region stack (eu-west-1)
    new DynamoDBGlobalTablesStack(this, 'DynamoDBGlobalTablesStack-Secondary', config, {
      env: {
        account: process.env.CDK_DEFAULT_ACCOUNT,
        region: 'eu-west-1',
      },
      description: 'Secondary region stack for DynamoDB Global Tables with advanced streaming (eu-west-1)',
      tags: {
        Application: 'ECommerce',
        Environment: 'Production',
        Region: 'Secondary',
        Purpose: 'GlobalTablesDemo',
      },
    });

    // Tertiary region stack (ap-southeast-1)
    new DynamoDBGlobalTablesStack(this, 'DynamoDBGlobalTablesStack-Tertiary', config, {
      env: {
        account: process.env.CDK_DEFAULT_ACCOUNT,
        region: 'ap-southeast-1',
      },
      description: 'Tertiary region stack for DynamoDB Global Tables with advanced streaming (ap-southeast-1)',
      tags: {
        Application: 'ECommerce',
        Environment: 'Production',
        Region: 'Tertiary',
        Purpose: 'GlobalTablesDemo',
      },
    });
  }
}

// Instantiate the CDK application
new DynamoDBGlobalTablesApp();