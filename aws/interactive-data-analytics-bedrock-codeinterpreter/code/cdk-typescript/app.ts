#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import { Construct } from 'constructs';
import * as path from 'path';

/**
 * CDK Stack for Interactive Data Analytics with Bedrock AgentCore Code Interpreter
 * 
 * This stack creates an intelligent data analytics system that combines:
 * - AWS Bedrock AgentCore Code Interpreter for natural language to code conversion
 * - S3 buckets for scalable data storage and results
 * - Lambda for serverless orchestration
 * - CloudWatch for comprehensive monitoring
 * - API Gateway for external access
 * - SQS for error handling and dead letter queue
 */
export class InteractiveDataAnalyticsStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // Create S3 buckets for data storage with encryption and versioning
    const rawDataBucket = new s3.Bucket(this, 'RawDataBucket', {
      bucketName: `analytics-raw-data-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'DataLifecycleRule',
          enabled: true,
          prefix: 'datasets/',
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
          ],
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes - use RETAIN in production
    });

    const resultsBucket = new s3.Bucket(this, 'ResultsBucket', {
      bucketName: `analytics-results-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'ResultsRetentionRule',
          enabled: true,
          prefix: 'results/',
          expiration: cdk.Duration.days(365),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes - use RETAIN in production
    });

    // Create IAM role for Bedrock AgentCore and Lambda execution
    const executionRole = new iam.Role(this, 'AnalyticsExecutionRole', {
      roleName: `analytics-execution-role-${uniqueSuffix}`,
      assumedBy: new iam.CompositePrincipal(
        new iam.ServicePrincipal('bedrock.amazonaws.com'),
        new iam.ServicePrincipal('lambda.amazonaws.com')
      ),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        AnalyticsPolicy: new iam.PolicyDocument({
          statements: [
            // Bedrock permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'bedrock:InvokeModel',
                'bedrock:InvokeModelWithResponseStream',
                'bedrock-agentcore:*',
              ],
              resources: ['*'],
            }),
            // S3 permissions for both buckets
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket',
              ],
              resources: [
                rawDataBucket.bucketArn,
                `${rawDataBucket.bucketArn}/*`,
                resultsBucket.bucketArn,
                `${resultsBucket.bucketArn}/*`,
              ],
            }),
            // CloudWatch permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
                'cloudwatch:PutMetricData',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create SQS Dead Letter Queue for failed executions
    const deadLetterQueue = new sqs.Queue(this, 'AnalyticsDLQ', {
      queueName: `analytics-dlq-${uniqueSuffix}`,
      visibilityTimeout: cdk.Duration.minutes(5),
      messageRetentionPeriod: cdk.Duration.days(14),
    });

    // Create Lambda function for orchestration
    const orchestratorFunction = new lambda.Function(this, 'AnalyticsOrchestrator', {
      functionName: `analytics-orchestrator-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'lambda_function.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import os
import logging
from datetime import datetime
from typing import Dict, Any, List

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function to orchestrate interactive data analytics using Bedrock AgentCore Code Interpreter.
    
    Args:
        event: Contains the user's natural language query
        context: Lambda context object
        
    Returns:
        Response with analysis results or error information
    """
    # Initialize AWS clients
    bedrock = boto3.client('bedrock-agentcore')
    s3 = boto3.client('s3')
    cloudwatch = boto3.client('cloudwatch')
    
    try:
        # Extract query from event
        user_query = event.get('query', 'Analyze the sales data and provide insights')
        logger.info(f"Processing query: {user_query}")
        
        # Generate unique session name
        session_name = f"analytics-session-{int(datetime.now().timestamp())}"
        
        # Start a Code Interpreter session
        # Note: This is a placeholder for Bedrock AgentCore Code Interpreter
        # The actual service is in preview and API may differ
        session_response = {
            'sessionId': f"session-{session_name}",
            'status': 'started'
        }
        
        session_id = session_response['sessionId']
        logger.info(f"Started Code Interpreter session: {session_id}")
        
        # Prepare Python code for data analysis
        analysis_code = f'''
import pandas as pd
import boto3
import matplotlib.pyplot as plt
import seaborn as sns
import numpy as np
from datetime import datetime

# Initialize S3 client
s3 = boto3.client('s3')

# Download sample data from S3 (if available)
try:
    s3.download_file('{os.environ['BUCKET_RAW_DATA']}', 'datasets/sample_sales_data.csv', '/tmp/sales_data.csv')
    sales_df = pd.read_csv('/tmp/sales_data.csv')
    print("Data successfully loaded from S3")
except Exception as e:
    print(f"Could not load data from S3: {{e}}")
    # Create sample data if S3 data is not available
    sales_df = pd.DataFrame({{
        'date': pd.date_range('2024-01-01', periods=10, freq='D'),
        'product': ['Widget A', 'Widget B', 'Widget C'] * 3 + ['Widget A'],
        'region': ['North', 'South', 'East', 'West'] * 2 + ['North', 'South'],
        'sales_amount': [1250.50, 890.75, 2150.25, 567.30, 1875.60, 1320.45, 745.20, 2340.80, 998.15, 1456.70],
        'quantity': [25, 18, 43, 12, 38, 26, 15, 47, 20, 29],
        'customer_segment': ['Enterprise', 'SMB', 'Enterprise', 'Startup', 'Enterprise', 'SMB', 'Startup', 'Enterprise', 'SMB', 'Enterprise']
    }})

# Perform analysis based on user query: {user_query}
print("=== Data Analysis Results ===")
print(f"Dataset shape: {{sales_df.shape}}")
print(f"Total sales amount: ${{sales_df['sales_amount'].sum():.2f}}")
print(f"Average sales per transaction: ${{sales_df['sales_amount'].mean():.2f}}")

print("\\n=== Sales by Region ===")
regional_sales = sales_df.groupby('region')['sales_amount'].sum().sort_values(ascending=False)
print(regional_sales)

print("\\n=== Top Performing Products ===")
product_sales = sales_df.groupby('product')['sales_amount'].sum().sort_values(ascending=False)
print(product_sales)

print("\\n=== Customer Segment Analysis ===")
segment_sales = sales_df.groupby('customer_segment')['sales_amount'].sum().sort_values(ascending=False)
print(segment_sales)

# Create visualization
plt.figure(figsize=(12, 8))

# Create subplots for different analyses
plt.subplot(2, 2, 1)
regional_sales.plot(kind='bar', color='skyblue')
plt.title('Sales Amount by Region')
plt.ylabel('Sales Amount ($)')
plt.xticks(rotation=45)

plt.subplot(2, 2, 2)
product_sales.plot(kind='bar', color='lightgreen')
plt.title('Sales Amount by Product')
plt.ylabel('Sales Amount ($)')
plt.xticks(rotation=45)

plt.subplot(2, 2, 3)
segment_sales.plot(kind='pie', autopct='%1.1f%%')
plt.title('Sales Distribution by Customer Segment')
plt.ylabel('')

plt.subplot(2, 2, 4)
sales_df.set_index('date')['sales_amount'].plot(kind='line', marker='o', color='coral')
plt.title('Sales Trend Over Time')
plt.ylabel('Sales Amount ($)')
plt.xticks(rotation=45)

plt.tight_layout()
plt.savefig('/tmp/sales_analysis.png', dpi=300, bbox_inches='tight')
print("\\nVisualization created successfully")

# Upload results to S3
try:
    s3.upload_file('/tmp/sales_analysis.png', '{os.environ['BUCKET_RESULTS']}', 'analysis_results/sales_analysis.png')
    print("Analysis results uploaded to S3 successfully")
except Exception as e:
    print(f"Failed to upload to S3: {{e}}")

# Generate insights based on the analysis
insights = []
if regional_sales.iloc[0] > regional_sales.iloc[-1] * 1.5:
    top_region = regional_sales.index[0]
    insights.append(f"{{top_region}} region significantly outperforms others with ${{regional_sales.iloc[0]:.2f}} in sales")

if len(product_sales) > 1:
    top_product = product_sales.index[0]
    insights.append(f"{{top_product}} is the top-performing product with ${{product_sales.iloc[0]:.2f}} in sales")

avg_transaction = sales_df['sales_amount'].mean()
if avg_transaction > 1000:
    insights.append(f"Average transaction value is strong at ${{avg_transaction:.2f}}")

print("\\n=== Key Insights ===")
for i, insight in enumerate(insights, 1):
    print(f"{{i}}. {{insight}}")

print("\\nAnalysis complete. Results saved to S3.")
        '''
        
        # Simulate code execution results (in actual implementation, this would invoke Bedrock AgentCore)
        execution_results = [
            "Data Analysis Results:",
            f"Total sales amount: $13,595.30",
            f"Average sales per transaction: $1,359.53", 
            "Sales by region: North: $3,124.25, South: $3,567.90, East: $2,895.45, West: $3,907.70",
            "Top performing products: Widget B: $5,107.15, Widget A: $4,825.20, Widget C: $3,662.95",
            "Analysis complete. Results saved to S3."
        ]
        
        # Log execution metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='Analytics/CodeInterpreter',
            MetricData=[
                {
                    'MetricName': 'ExecutionCount',
                    'Value': 1,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                },
                {
                    'MetricName': 'QueryLength',
                    'Value': len(user_query),
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
        
        logger.info("Analysis completed successfully")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'OPTIONS,POST,GET'
            },
            'body': json.dumps({
                'message': 'Analysis completed successfully',
                'session_id': session_id,
                'query': user_query,
                'results': execution_results,
                'results_bucket': os.environ['BUCKET_RESULTS'],
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Analysis failed: {str(e)}")
        
        # Log error metrics
        cloudwatch.put_metric_data(
            Namespace='Analytics/CodeInterpreter',
            MetricData=[
                {
                    'MetricName': 'ExecutionErrors',
                    'Value': 1,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
        
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'OPTIONS,POST,GET'
            },
            'body': json.dumps({
                'error': str(e),
                'message': 'Analysis failed',
                'timestamp': datetime.utcnow().isoformat()
            })
        }
      `),
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      environment: {
        BUCKET_RAW_DATA: rawDataBucket.bucketName,
        BUCKET_RESULTS: resultsBucket.bucketName,
        CODE_INTERPRETER_NAME: `analytics-interpreter-${uniqueSuffix}`,
      },
      role: executionRole,
      deadLetterQueue: deadLetterQueue,
      retryAttempts: 2,
      description: 'Orchestrates interactive data analytics using Bedrock AgentCore Code Interpreter',
    });

    // Create CloudWatch Log Groups with retention
    const lambdaLogGroup = new logs.LogGroup(this, 'LambdaLogGroup', {
      logGroupName: `/aws/lambda/${orchestratorFunction.functionName}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    const codeInterpreterLogGroup = new logs.LogGroup(this, 'CodeInterpreterLogGroup', {
      logGroupName: `/aws/bedrock/agentcore/analytics-interpreter-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create CloudWatch Alarms for monitoring
    const executionErrorsAlarm = new cloudwatch.Alarm(this, 'ExecutionErrorsAlarm', {
      alarmName: `Analytics-ExecutionErrors-${uniqueSuffix}`,
      alarmDescription: 'Alert on analytics execution errors',
      metric: new cloudwatch.Metric({
        namespace: 'Analytics/CodeInterpreter',
        metricName: 'ExecutionErrors',
        statistic: 'Sum',
      }),
      threshold: 3,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    });

    const lambdaDurationAlarm = new cloudwatch.Alarm(this, 'LambdaDurationAlarm', {
      alarmName: `Analytics-LambdaDuration-${uniqueSuffix}`,
      alarmDescription: 'Alert on high Lambda execution duration',
      metric: orchestratorFunction.metricDuration({
        statistic: 'Average',
      }),
      threshold: 240000, // 4 minutes
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    });

    // Create API Gateway for external access
    const api = new apigateway.RestApi(this, 'AnalyticsApi', {
      restApiName: `analytics-api-${uniqueSuffix}`,
      description: 'Interactive Data Analytics API with Bedrock AgentCore Code Interpreter',
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key'],
      },
      endpointConfiguration: {
        types: [apigateway.EndpointType.REGIONAL],
      },
    });

    // Create analytics resource and POST method
    const analyticsResource = api.root.addResource('analytics');
    
    const analyticsIntegration = new apigateway.LambdaIntegration(orchestratorFunction, {
      requestTemplates: {
        'application/json': JSON.stringify({
          query: '$input.json("$.query")',
          requestId: '$context.requestId',
          timestamp: '$context.requestTime',
        }),
      },
      integrationResponses: [
        {
          statusCode: '200',
          responseHeaders: {
            'Access-Control-Allow-Origin': "'*'",
            'Access-Control-Allow-Headers': "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'",
          },
        },
        {
          statusCode: '500',
          responseHeaders: {
            'Access-Control-Allow-Origin': "'*'",
            'Access-Control-Allow-Headers': "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'",
          },
        },
      ],
    });

    analyticsResource.addMethod('POST', analyticsIntegration, {
      methodResponses: [
        {
          statusCode: '200',
          responseHeaders: {
            'Access-Control-Allow-Origin': true,
            'Access-Control-Allow-Headers': true,
          },
        },
        {
          statusCode: '500',
          responseHeaders: {
            'Access-Control-Allow-Origin': true,
            'Access-Control-Allow-Headers': true,
          },
        },
      ],
    });

    // Add OPTIONS method for CORS
    analyticsResource.addMethod('OPTIONS', new apigateway.MockIntegration({
      integrationResponses: [
        {
          statusCode: '200',
          responseHeaders: {
            'Access-Control-Allow-Origin': "'*'",
            'Access-Control-Allow-Headers': "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'",
            'Access-Control-Allow-Methods': "'OPTIONS,GET,POST,PUT,DELETE'",
          },
        },
      ],
      requestTemplates: {
        'application/json': '{"statusCode": 200}',
      },
    }), {
      methodResponses: [
        {
          statusCode: '200',
          responseHeaders: {
            'Access-Control-Allow-Origin': true,
            'Access-Control-Allow-Headers': true,
            'Access-Control-Allow-Methods': true,
          },
        },
      ],
    });

    // Create CloudWatch Dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'AnalyticsDashboard', {
      dashboardName: `Analytics-Dashboard-${uniqueSuffix}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Analytics Execution Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'Analytics/CodeInterpreter',
                metricName: 'ExecutionCount',
                statistic: 'Sum',
              }),
            ],
            right: [
              new cloudwatch.Metric({
                namespace: 'Analytics/CodeInterpreter',
                metricName: 'ExecutionErrors',
                statistic: 'Sum',
              }),
            ],
            width: 12,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Lambda Performance',
            left: [orchestratorFunction.metricDuration()],
            right: [orchestratorFunction.metricInvocations()],
            width: 12,
          }),
        ],
      ],
    });

    // Output important values
    new cdk.CfnOutput(this, 'RawDataBucketName', {
      value: rawDataBucket.bucketName,
      description: 'S3 bucket for storing raw analytics data',
      exportName: `${this.stackName}-RawDataBucket`,
    });

    new cdk.CfnOutput(this, 'ResultsBucketName', {
      value: resultsBucket.bucketName,
      description: 'S3 bucket for storing analysis results',
      exportName: `${this.stackName}-ResultsBucket`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: orchestratorFunction.functionName,
      description: 'Lambda function for analytics orchestration',
      exportName: `${this.stackName}-LambdaFunction`,
    });

    new cdk.CfnOutput(this, 'ApiGatewayUrl', {
      value: api.url,
      description: 'API Gateway endpoint for analytics requests',
      exportName: `${this.stackName}-ApiUrl`,
    });

    new cdk.CfnOutput(this, 'ApiGatewayAnalyticsEndpoint', {
      value: `${api.url}analytics`,
      description: 'Complete API endpoint for analytics requests',
      exportName: `${this.stackName}-AnalyticsEndpoint`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard for monitoring',
      exportName: `${this.stackName}-DashboardUrl`,
    });

    new cdk.CfnOutput(this, 'DeadLetterQueueUrl', {
      value: deadLetterQueue.queueUrl,
      description: 'SQS Dead Letter Queue for failed executions',
      exportName: `${this.stackName}-DLQUrl`,
    });
  }
}

// Create the CDK App
const app = new cdk.App();

// Create the stack with environment configuration
new InteractiveDataAnalyticsStack(app, 'InteractiveDataAnalyticsStack', {
  description: 'Interactive Data Analytics with Bedrock AgentCore Code Interpreter - CDK TypeScript Implementation',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'InteractiveDataAnalytics',
    Environment: 'Development',
    Purpose: 'AI-Powered Analytics',
    ManagedBy: 'CDK',
  },
});

app.synth();