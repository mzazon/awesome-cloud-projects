#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as lambdaEventSources from 'aws-cdk-lib/aws-lambda-event-sources';

/**
 * Properties for the WebhookProcessingStack
 */
export interface WebhookProcessingStackProps extends cdk.StackProps {
  /**
   * The name prefix for all resources
   * @default 'webhook-processing'
   */
  readonly resourcePrefix?: string;
  
  /**
   * The batch size for SQS Lambda event source mapping
   * @default 10
   */
  readonly lambdaBatchSize?: number;
  
  /**
   * The maximum batching window in seconds for SQS Lambda event source mapping
   * @default 5
   */
  readonly lambdaBatchingWindow?: number;
  
  /**
   * The maximum number of retry attempts for SQS messages
   * @default 3
   */
  readonly maxRetryAttempts?: number;
  
  /**
   * Enable detailed CloudWatch monitoring
   * @default true
   */
  readonly enableDetailedMonitoring?: boolean;
}

/**
 * CDK Stack for Webhook Processing System
 * 
 * This stack creates a complete webhook processing system with:
 * - API Gateway REST API for webhook ingestion
 * - SQS queue for reliable message buffering
 * - Lambda function for asynchronous processing
 * - DynamoDB table for webhook history storage
 * - CloudWatch alarms for monitoring
 * - Dead letter queue for failed messages
 */
export class WebhookProcessingStack extends cdk.Stack {
  /** API Gateway REST API */
  public readonly api: apigateway.RestApi;
  
  /** Primary SQS queue for webhook messages */
  public readonly webhookQueue: sqs.Queue;
  
  /** Dead letter queue for failed messages */
  public readonly deadLetterQueue: sqs.Queue;
  
  /** Lambda function for processing webhooks */
  public readonly processingFunction: lambda.Function;
  
  /** DynamoDB table for webhook history */
  public readonly webhookTable: dynamodb.Table;
  
  /** CloudWatch alarms for monitoring */
  public readonly alarms: cloudwatch.Alarm[];

  constructor(scope: Construct, id: string, props: WebhookProcessingStackProps = {}) {
    super(scope, id, props);

    // Extract configuration with defaults
    const resourcePrefix = props.resourcePrefix || 'webhook-processing';
    const lambdaBatchSize = props.lambdaBatchSize || 10;
    const lambdaBatchingWindow = props.lambdaBatchingWindow || 5;
    const maxRetryAttempts = props.maxRetryAttempts || 3;
    const enableDetailedMonitoring = props.enableDetailedMonitoring ?? true;

    // Create DynamoDB table for webhook history
    this.webhookTable = new dynamodb.Table(this, 'WebhookHistoryTable', {
      tableName: `${resourcePrefix}-history`,
      partitionKey: {
        name: 'webhook_id',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'timestamp',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes - use RETAIN in production
      pointInTimeRecovery: true,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      tags: {
        Purpose: 'WebhookProcessing',
        Component: 'Storage',
      },
    });

    // Create dead letter queue for failed messages
    this.deadLetterQueue = new sqs.Queue(this, 'WebhookDeadLetterQueue', {
      queueName: `${resourcePrefix}-dlq`,
      messageRetentionPeriod: cdk.Duration.days(14),
      visibilityTimeout: cdk.Duration.seconds(60),
      encryption: sqs.QueueEncryption.SQS_MANAGED,
    });

    // Create primary SQS queue for webhook messages
    this.webhookQueue = new sqs.Queue(this, 'WebhookQueue', {
      queueName: `${resourcePrefix}-queue`,
      messageRetentionPeriod: cdk.Duration.days(14),
      visibilityTimeout: cdk.Duration.seconds(300), // 5 minutes for Lambda processing
      encryption: sqs.QueueEncryption.SQS_MANAGED,
      deadLetterQueue: {
        queue: this.deadLetterQueue,
        maxReceiveCount: maxRetryAttempts,
      },
    });

    // Create Lambda function for webhook processing
    this.processingFunction = new lambda.Function(this, 'WebhookProcessingFunction', {
      functionName: `${resourcePrefix}-processor`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
import os
from datetime import datetime
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['WEBHOOK_TABLE_NAME'])

def lambda_handler(event, context):
    try:
        # Process each SQS record
        for record in event['Records']:
            # Parse the webhook payload
            webhook_body = json.loads(record['body'])
            
            # Generate unique webhook ID
            webhook_id = str(uuid.uuid4())
            timestamp = datetime.utcnow().isoformat()
            
            # Extract webhook metadata
            source_ip = webhook_body.get('source_ip', 'unknown')
            webhook_type = webhook_body.get('body', {}).get('type', 'unknown')
            
            # Process the webhook (customize based on your needs)
            processed_data = process_webhook(webhook_body.get('body', {}))
            
            # Store in DynamoDB
            table.put_item(
                Item={
                    'webhook_id': webhook_id,
                    'timestamp': timestamp,
                    'source_ip': source_ip,
                    'webhook_type': webhook_type,
                    'raw_payload': json.dumps(webhook_body),
                    'processed_data': json.dumps(processed_data),
                    'status': 'processed'
                }
            )
            
            logger.info(f"Processed webhook {webhook_id} of type {webhook_type}")
        
        return {
            'statusCode': 200,
            'body': json.dumps('Webhooks processed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error processing webhook: {str(e)}")
        raise

def process_webhook(payload):
    """
    Customize this function based on your webhook processing needs
    """
    # Example processing logic
    processed = {
        'processed_at': datetime.utcnow().isoformat(),
        'payload_size': len(json.dumps(payload)),
        'contains_sensitive_data': check_sensitive_data(payload)
    }
    
    # Add your specific processing logic here
    return processed

def check_sensitive_data(payload):
    """
    Example function to check for sensitive data
    """
    sensitive_keys = ['credit_card', 'ssn', 'password', 'secret']
    payload_str = json.dumps(payload).lower()
    
    return any(key in payload_str for key in sensitive_keys)
      `),
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      environment: {
        WEBHOOK_TABLE_NAME: this.webhookTable.tableName,
      },
      logRetention: logs.RetentionDays.ONE_MONTH,
      tracing: lambda.Tracing.ACTIVE,
    });

    // Grant Lambda function permissions to write to DynamoDB
    this.webhookTable.grantWriteData(this.processingFunction);

    // Create event source mapping for Lambda to process SQS messages
    this.processingFunction.addEventSource(
      new lambdaEventSources.SqsEventSource(this.webhookQueue, {
        batchSize: lambdaBatchSize,
        maxBatchingWindow: cdk.Duration.seconds(lambdaBatchingWindow),
        reportBatchItemFailures: true,
      })
    );

    // Create IAM role for API Gateway to send messages to SQS
    const apiGatewayRole = new iam.Role(this, 'ApiGatewaySqsRole', {
      assumedBy: new iam.ServicePrincipal('apigateway.amazonaws.com'),
      inlinePolicies: {
        SqsPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sqs:SendMessage', 'sqs:GetQueueAttributes'],
              resources: [this.webhookQueue.queueArn],
            }),
          ],
        }),
      },
    });

    // Create API Gateway REST API
    this.api = new apigateway.RestApi(this, 'WebhookApi', {
      restApiName: `${resourcePrefix}-api`,
      description: 'REST API for webhook processing',
      endpointConfiguration: {
        types: [apigateway.EndpointType.REGIONAL],
      },
      deployOptions: {
        stageName: 'prod',
        metricsEnabled: enableDetailedMonitoring,
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        dataTraceEnabled: true,
        throttle: {
          burstLimit: 2000,
          rateLimit: 1000,
        },
      },
      cloudWatchRole: true,
    });

    // Create /webhooks resource
    const webhooksResource = this.api.root.addResource('webhooks');

    // Create POST method with SQS integration
    const sqsIntegration = new apigateway.AwsIntegration({
      service: 'sqs',
      path: `${cdk.Aws.ACCOUNT_ID}/${this.webhookQueue.queueName}`,
      integrationHttpMethod: 'POST',
      options: {
        credentialsRole: apiGatewayRole,
        requestParameters: {
          'integration.request.header.Content-Type': "'application/x-www-form-urlencoded'",
        },
        requestTemplates: {
          'application/json': `Action=SendMessage&MessageBody=$util.urlEncode("{\\"source_ip\\":\\"$context.identity.sourceIp\\",\\"timestamp\\":\\"$context.requestTime\\",\\"body\\":$input.json('$')}")`,
        },
        integrationResponses: [
          {
            statusCode: '200',
            responseTemplates: {
              'application/json': `{"message": "Webhook received and queued for processing", "requestId": "$context.requestId"}`,
            },
          },
        ],
      },
    });

    // Add POST method to /webhooks resource
    webhooksResource.addMethod('POST', sqsIntegration, {
      methodResponses: [
        {
          statusCode: '200',
          responseModels: {
            'application/json': apigateway.Model.EMPTY_MODEL,
          },
        },
      ],
    });

    // Initialize alarms array
    this.alarms = [];

    // Create CloudWatch alarms for monitoring
    if (enableDetailedMonitoring) {
      // Alarm for dead letter queue messages
      const dlqAlarm = new cloudwatch.Alarm(this, 'DeadLetterQueueAlarm', {
        alarmName: `${resourcePrefix}-dlq-messages`,
        alarmDescription: 'Alert when messages appear in webhook dead letter queue',
        metric: this.deadLetterQueue.metricApproximateNumberOfVisibleMessages(),
        threshold: 1,
        evaluationPeriods: 1,
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Statistic.SUM,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      });

      // Alarm for Lambda function errors
      const lambdaErrorAlarm = new cloudwatch.Alarm(this, 'LambdaErrorAlarm', {
        alarmName: `${resourcePrefix}-lambda-errors`,
        alarmDescription: 'Alert on Lambda function errors',
        metric: this.processingFunction.metricErrors(),
        threshold: 5,
        evaluationPeriods: 1,
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Statistic.SUM,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      });

      // Alarm for API Gateway 4xx errors
      const apiGateway4xxAlarm = new cloudwatch.Alarm(this, 'ApiGateway4xxAlarm', {
        alarmName: `${resourcePrefix}-api-4xx-errors`,
        alarmDescription: 'Alert on API Gateway 4xx errors',
        metric: this.api.metricClientError(),
        threshold: 10,
        evaluationPeriods: 2,
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Statistic.SUM,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      });

      // Alarm for API Gateway 5xx errors
      const apiGateway5xxAlarm = new cloudwatch.Alarm(this, 'ApiGateway5xxAlarm', {
        alarmName: `${resourcePrefix}-api-5xx-errors`,
        alarmDescription: 'Alert on API Gateway 5xx errors',
        metric: this.api.metricServerError(),
        threshold: 5,
        evaluationPeriods: 1,
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Statistic.SUM,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      });

      // Add alarms to the array
      this.alarms.push(dlqAlarm, lambdaErrorAlarm, apiGateway4xxAlarm, apiGateway5xxAlarm);
    }

    // Output important resource information
    new cdk.CfnOutput(this, 'WebhookApiEndpoint', {
      value: this.api.url + 'webhooks',
      description: 'Webhook API endpoint URL',
      exportName: `${resourcePrefix}-api-endpoint`,
    });

    new cdk.CfnOutput(this, 'WebhookQueueUrl', {
      value: this.webhookQueue.queueUrl,
      description: 'SQS queue URL for webhook messages',
      exportName: `${resourcePrefix}-queue-url`,
    });

    new cdk.CfnOutput(this, 'WebhookTableName', {
      value: this.webhookTable.tableName,
      description: 'DynamoDB table name for webhook history',
      exportName: `${resourcePrefix}-table-name`,
    });

    new cdk.CfnOutput(this, 'ProcessingFunctionName', {
      value: this.processingFunction.functionName,
      description: 'Lambda function name for webhook processing',
      exportName: `${resourcePrefix}-function-name`,
    });

    new cdk.CfnOutput(this, 'DeadLetterQueueUrl', {
      value: this.deadLetterQueue.queueUrl,
      description: 'Dead letter queue URL for failed messages',
      exportName: `${resourcePrefix}-dlq-url`,
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'WebhookProcessing');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }
}

// Create the CDK application
const app = new cdk.App();

// Create the webhook processing stack
new WebhookProcessingStack(app, 'WebhookProcessingStack', {
  resourcePrefix: 'webhook-processing',
  lambdaBatchSize: 10,
  lambdaBatchingWindow: 5,
  maxRetryAttempts: 3,
  enableDetailedMonitoring: true,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Stack for webhook processing system with API Gateway, SQS, Lambda, and DynamoDB',
  tags: {
    Project: 'WebhookProcessing',
    CreatedBy: 'CDK',
  },
});

// Synthesize the CloudFormation template
app.synth();