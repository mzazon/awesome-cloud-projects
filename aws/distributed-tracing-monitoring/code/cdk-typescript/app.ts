#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as xray from 'aws-cdk-lib/aws-xray';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Props for the XRayMonitoringStack
 */
interface XRayMonitoringStackProps extends cdk.StackProps {
  /**
   * Project name used for resource naming
   * @default 'xray-monitoring'
   */
  readonly projectName?: string;
  
  /**
   * Environment name for resource tagging
   * @default 'dev'
   */
  readonly environment?: string;
}

/**
 * AWS CDK Stack for implementing infrastructure monitoring with AWS X-Ray
 * 
 * This stack creates a complete serverless application with distributed tracing:
 * - DynamoDB table for data storage
 * - Lambda functions for business logic
 * - API Gateway for REST endpoints
 * - X-Ray tracing configuration
 * - CloudWatch dashboards and alarms
 * - EventBridge rules for automated monitoring
 */
export class XRayMonitoringStack extends cdk.Stack {
  public readonly ordersTable: dynamodb.Table;
  public readonly orderProcessorFunction: lambda.Function;
  public readonly inventoryManagerFunction: lambda.Function;
  public readonly traceAnalyzerFunction: lambda.Function;
  public readonly api: apigateway.RestApi;
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props?: XRayMonitoringStackProps) {
    super(scope, id, props);

    const projectName = props?.projectName || 'xray-monitoring';
    const environment = props?.environment || 'dev';

    // Generate unique suffix for resource naming
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);
    const resourcePrefix = `${projectName}-${uniqueSuffix}`;

    // Common tags for all resources
    const commonTags = {
      Project: projectName,
      Environment: environment,
      CreatedBy: 'CDK',
      Purpose: 'XRayMonitoring'
    };

    // Apply tags to the stack
    cdk.Tags.of(this).add('Project', projectName);
    cdk.Tags.of(this).add('Environment', environment);
    cdk.Tags.of(this).add('CreatedBy', 'CDK');

    // Create DynamoDB table for orders
    this.ordersTable = new dynamodb.Table(this, 'OrdersTable', {
      tableName: `${resourcePrefix}-orders`,
      partitionKey: {
        name: 'orderId',
        type: dynamodb.AttributeType.STRING
      },
      billingMode: dynamodb.BillingMode.PROVISIONED,
      readCapacity: 5,
      writeCapacity: 5,
      pointInTimeRecovery: true,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    // Create IAM role for Lambda functions
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `${resourcePrefix}-lambda-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSXRayDaemonWriteAccess'),
      ],
      inlinePolicies: {
        DynamoDBAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:PutItem',
                'dynamodb:GetItem',
                'dynamodb:UpdateItem',
                'dynamodb:DeleteItem',
                'dynamodb:Query',
                'dynamodb:Scan'
              ],
              resources: [this.ordersTable.tableArn]
            })
          ]
        }),
        XRayAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'xray:GetTraceSummaries',
                'xray:GetServiceGraph',
                'xray:GetTimeSeriesServiceStatistics',
                'xray:BatchGetTraces'
              ],
              resources: ['*']
            })
          ]
        }),
        CloudWatchAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:PutMetricData'
              ],
              resources: ['*']
            })
          ]
        })
      }
    });

    // Create order processor Lambda function
    this.orderProcessorFunction = new lambda.Function(this, 'OrderProcessorFunction', {
      functionName: `${resourcePrefix}-order-processor`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(30),
      tracing: lambda.Tracing.ACTIVE,
      environment: {
        ORDERS_TABLE: this.ordersTable.tableName,
        INVENTORY_FUNCTION: `${resourcePrefix}-inventory-manager`
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
from datetime import datetime
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all
import os

# Patch AWS SDK calls for X-Ray tracing
patch_all()

dynamodb = boto3.resource('dynamodb')
lambda_client = boto3.client('lambda')
table = dynamodb.Table(os.environ['ORDERS_TABLE'])

@xray_recorder.capture('process_order')
def lambda_handler(event, context):
    try:
        # Add custom annotations for filtering
        xray_recorder.put_annotation('service', 'order-processor')
        xray_recorder.put_annotation('operation', 'create_order')
        
        # Extract order details
        if 'body' in event:
            body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
        else:
            body = event
        
        order_id = str(uuid.uuid4())
        order_data = {
            'orderId': order_id,
            'customerId': body.get('customerId', 'unknown'),
            'productId': body.get('productId', 'unknown'),
            'quantity': body.get('quantity', 1),
            'timestamp': datetime.utcnow().isoformat(),
            'status': 'pending'
        }
        
        # Add custom metadata
        xray_recorder.put_metadata('order_details', {
            'order_id': order_id,
            'customer_id': body.get('customerId'),
            'product_id': body.get('productId')
        })
        
        # Store order in DynamoDB
        with xray_recorder.in_subsegment('dynamodb_put_item'):
            table.put_item(Item=order_data)
        
        # Simulate calling inventory service
        inventory_response = check_inventory(body.get('productId'))
        
        # Simulate calling notification service
        notification_response = send_notification(order_id, body.get('customerId'))
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'orderId': order_id,
                'status': 'processed',
                'inventory': inventory_response,
                'notification': notification_response
            })
        }
        
    except Exception as e:
        xray_recorder.put_annotation('error', str(e))
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': str(e)})
        }

@xray_recorder.capture('check_inventory')
def check_inventory(product_id):
    # Simulate inventory check with artificial delay
    import time
    time.sleep(0.1)
    
    xray_recorder.put_annotation('inventory_check', 'completed')
    return {'status': 'available', 'quantity': 100}

@xray_recorder.capture('send_notification')
def send_notification(order_id, customer_id):
    # Simulate notification sending
    import time
    time.sleep(0.05)
    
    xray_recorder.put_annotation('notification_sent', 'true')
    return {'status': 'sent', 'channel': 'email'}
      `)
    });

    // Create inventory manager Lambda function
    this.inventoryManagerFunction = new lambda.Function(this, 'InventoryManagerFunction', {
      functionName: `${resourcePrefix}-inventory-manager`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(30),
      tracing: lambda.Tracing.ACTIVE,
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
import json
import boto3
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all
import time

# Patch AWS SDK calls for X-Ray tracing
patch_all()

@xray_recorder.capture('inventory_manager')
def lambda_handler(event, context):
    try:
        xray_recorder.put_annotation('service', 'inventory-manager')
        xray_recorder.put_annotation('operation', 'update_inventory')
        
        # Simulate inventory processing
        with xray_recorder.in_subsegment('inventory_validation'):
            product_id = event.get('productId', 'unknown')
            quantity = event.get('quantity', 1)
            
            # Simulate database lookup
            time.sleep(0.1)
            
            xray_recorder.put_metadata('inventory_check', {
                'product_id': product_id,
                'requested_quantity': quantity,
                'available_quantity': 100
            })
        
        # Simulate inventory update
        with xray_recorder.in_subsegment('inventory_update'):
            time.sleep(0.05)
            xray_recorder.put_annotation('inventory_updated', 'true')
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'productId': product_id,
                'status': 'reserved',
                'availableQuantity': 100 - quantity
            })
        }
        
    except Exception as e:
        xray_recorder.put_annotation('error', str(e))
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
      `)
    });

    // Create trace analyzer Lambda function
    this.traceAnalyzerFunction = new lambda.Function(this, 'TraceAnalyzerFunction', {
      functionName: `${resourcePrefix}-trace-analyzer`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(60),
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
import json
import boto3
from datetime import datetime, timedelta

xray_client = boto3.client('xray')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    try:
        # Get traces from last hour
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=1)
        
        # Get trace summaries
        response = xray_client.get_trace_summaries(
            TimeRangeType='TimeStamp',
            StartTime=start_time,
            EndTime=end_time,
            FilterExpression='service("order-processor")'
        )
        
        # Analyze traces
        total_traces = len(response['TraceSummaries'])
        error_traces = len([t for t in response['TraceSummaries'] if t.get('IsError')])
        high_latency_traces = len([t for t in response['TraceSummaries'] if t.get('ResponseTime', 0) > 2])
        
        # Send custom metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='XRay/Analysis',
            MetricData=[
                {
                    'MetricName': 'TotalTraces',
                    'Value': total_traces,
                    'Unit': 'Count'
                },
                {
                    'MetricName': 'ErrorTraces',
                    'Value': error_traces,
                    'Unit': 'Count'
                },
                {
                    'MetricName': 'HighLatencyTraces',
                    'Value': high_latency_traces,
                    'Unit': 'Count'
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'total_traces': total_traces,
                'error_traces': error_traces,
                'high_latency_traces': high_latency_traces
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
      `)
    });

    // Create REST API Gateway
    this.api = new apigateway.RestApi(this, 'OrdersApi', {
      restApiName: `${resourcePrefix}-api`,
      description: 'API for X-Ray monitoring demo',
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key']
      },
      tracingEnabled: true,
      deployOptions: {
        stageName: 'prod',
        throttlingBurstLimit: 100,
        throttlingRateLimit: 50,
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        dataTraceEnabled: true,
        metricsEnabled: true
      }
    });

    // Create orders resource and POST method
    const ordersResource = this.api.root.addResource('orders');
    const ordersIntegration = new apigateway.LambdaIntegration(this.orderProcessorFunction, {
      requestTemplates: { 'application/json': '{ "statusCode": "200" }' },
      proxy: true
    });

    ordersResource.addMethod('POST', ordersIntegration, {
      methodResponses: [
        {
          statusCode: '200',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true
          }
        },
        {
          statusCode: '500',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true
          }
        }
      ]
    });

    // Grant API Gateway permission to invoke Lambda
    this.orderProcessorFunction.addPermission('ApiGatewayInvoke', {
      principal: new iam.ServicePrincipal('apigateway.amazonaws.com'),
      sourceArn: this.api.arnForExecuteApi('*', '/orders', 'POST')
    });

    // Create X-Ray sampling rules
    new xray.CfnSamplingRule(this, 'HighPrioritySamplingRule', {
      samplingRule: {
        ruleName: 'high-priority-requests',
        resourceArn: '*',
        priority: 100,
        fixedRate: 1.0,
        reservoirSize: 10,
        serviceName: 'order-processor',
        serviceType: '*',
        host: '*',
        httpMethod: '*',
        urlPath: '*',
        version: 1
      }
    });

    new xray.CfnSamplingRule(this, 'ErrorSamplingRule', {
      samplingRule: {
        ruleName: 'error-traces',
        resourceArn: '*',
        priority: 50,
        fixedRate: 1.0,
        reservoirSize: 5,
        serviceName: '*',
        serviceType: '*',
        host: '*',
        httpMethod: '*',
        urlPath: '*',
        version: 1
      }
    });

    // Create X-Ray filter groups
    new xray.CfnGroup(this, 'HighLatencyGroup', {
      groupName: 'high-latency-requests',
      filterExpression: 'responsetime > 2'
    });

    new xray.CfnGroup(this, 'ErrorGroup', {
      groupName: 'error-traces',
      filterExpression: 'error = true OR fault = true'
    });

    new xray.CfnGroup(this, 'OrderProcessorGroup', {
      groupName: 'order-processor-service',
      filterExpression: 'service("order-processor")'
    });

    // Create EventBridge rule for automated trace analysis
    const traceAnalysisRule = new events.Rule(this, 'TraceAnalysisRule', {
      ruleName: `${resourcePrefix}-trace-analysis`,
      description: 'Trigger trace analysis every hour',
      schedule: events.Schedule.rate(cdk.Duration.hours(1))
    });

    traceAnalysisRule.addTarget(new targets.LambdaFunction(this.traceAnalyzerFunction));

    // Create CloudWatch dashboard
    this.dashboard = new cloudwatch.Dashboard(this, 'XRayDashboard', {
      dashboardName: `${resourcePrefix}-xray-monitoring`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'X-Ray Trace Metrics',
            width: 12,
            height: 6,
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/X-Ray',
                metricName: 'TracesReceived',
                statistic: 'Sum'
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/X-Ray',
                metricName: 'TracesScanned',
                statistic: 'Sum'
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/X-Ray',
                metricName: 'LatencyHigh',
                statistic: 'Sum'
              })
            ]
          }),
          new cloudwatch.GraphWidget({
            title: 'Lambda Function Metrics',
            width: 12,
            height: 6,
            left: [
              this.orderProcessorFunction.metricDuration(),
              this.orderProcessorFunction.metricErrors(),
              this.orderProcessorFunction.metricThrottles()
            ]
          })
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Custom X-Ray Analysis Metrics',
            width: 24,
            height: 6,
            left: [
              new cloudwatch.Metric({
                namespace: 'XRay/Analysis',
                metricName: 'TotalTraces',
                statistic: 'Sum'
              }),
              new cloudwatch.Metric({
                namespace: 'XRay/Analysis',
                metricName: 'ErrorTraces',
                statistic: 'Sum'
              }),
              new cloudwatch.Metric({
                namespace: 'XRay/Analysis',
                metricName: 'HighLatencyTraces',
                statistic: 'Sum'
              })
            ]
          })
        ],
        [
          new cloudwatch.SingleValueWidget({
            title: 'API Gateway Requests',
            width: 8,
            height: 6,
            metrics: [
              this.api.metricCount()
            ]
          }),
          new cloudwatch.SingleValueWidget({
            title: 'API Gateway Latency',
            width: 8,
            height: 6,
            metrics: [
              this.api.metricLatency()
            ]
          }),
          new cloudwatch.SingleValueWidget({
            title: 'DynamoDB Consumed Capacity',
            width: 8,
            height: 6,
            metrics: [
              this.ordersTable.metricConsumedReadCapacityUnits(),
              this.ordersTable.metricConsumedWriteCapacityUnits()
            ]
          })
        ]
      ]
    });

    // Create CloudWatch alarms
    const highErrorRateAlarm = new cloudwatch.Alarm(this, 'HighErrorRateAlarm', {
      alarmName: `${resourcePrefix}-high-error-rate`,
      alarmDescription: 'High error rate detected in X-Ray traces',
      metric: new cloudwatch.Metric({
        namespace: 'XRay/Analysis',
        metricName: 'ErrorTraces',
        statistic: 'Sum'
      }),
      threshold: 5,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    const highLatencyAlarm = new cloudwatch.Alarm(this, 'HighLatencyAlarm', {
      alarmName: `${resourcePrefix}-high-latency`,
      alarmDescription: 'High latency detected in X-Ray traces',
      metric: new cloudwatch.Metric({
        namespace: 'XRay/Analysis',
        metricName: 'HighLatencyTraces',
        statistic: 'Sum'
      }),
      threshold: 3,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Output important values
    new cdk.CfnOutput(this, 'ApiEndpoint', {
      description: 'API Gateway endpoint URL',
      value: this.api.url,
      exportName: `${resourcePrefix}-api-endpoint`
    });

    new cdk.CfnOutput(this, 'OrdersTableName', {
      description: 'DynamoDB orders table name',
      value: this.ordersTable.tableName,
      exportName: `${resourcePrefix}-orders-table`
    });

    new cdk.CfnOutput(this, 'OrderProcessorFunctionName', {
      description: 'Order processor Lambda function name',
      value: this.orderProcessorFunction.functionName,
      exportName: `${resourcePrefix}-order-processor-function`
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      description: 'CloudWatch dashboard URL',
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      exportName: `${resourcePrefix}-dashboard-url`
    });

    new cdk.CfnOutput(this, 'XRayConsoleUrl', {
      description: 'X-Ray console URL',
      value: `https://${this.region}.console.aws.amazon.com/xray/home?region=${this.region}#/service-map`,
      exportName: `${resourcePrefix}-xray-console-url`
    });

    new cdk.CfnOutput(this, 'TestCommand', {
      description: 'Command to test the API',
      value: `curl -X POST ${this.api.url}orders -H "Content-Type: application/json" -d '{"customerId": "test-customer", "productId": "test-product", "quantity": 1}'`,
      exportName: `${resourcePrefix}-test-command`
    });
  }
}

// CDK App
const app = new cdk.App();

// Get context values
const projectName = app.node.tryGetContext('projectName') || 'xray-monitoring';
const environment = app.node.tryGetContext('environment') || 'dev';

new XRayMonitoringStack(app, 'XRayMonitoringStack', {
  projectName,
  environment,
  description: 'AWS X-Ray infrastructure monitoring implementation with distributed tracing',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

app.synth();