#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as sagemaker from 'aws-cdk-lib/aws-sagemaker';
import * as logs from 'aws-cdk-lib/aws-logs';
import { RemovalPolicy, Duration, CfnOutput } from 'aws-cdk-lib';

/**
 * Properties for the AutoML Forecasting Stack
 */
interface AutoMLForecastingStackProps extends cdk.StackProps {
  /**
   * Environment name (dev, staging, prod)
   * @default 'dev'
   */
  readonly environmentName?: string;

  /**
   * Forecast horizon in days
   * @default 14
   */
  readonly forecastHorizon?: number;

  /**
   * Forecast frequency (D, W, M)
   * @default 'D'
   */
  readonly forecastFrequency?: string;

  /**
   * Enable data encryption at rest
   * @default true
   */
  readonly enableEncryption?: boolean;

  /**
   * SageMaker instance type for endpoints
   * @default 'ml.m5.large'
   */
  readonly endpointInstanceType?: string;

  /**
   * Notification email for alerts
   */
  readonly notificationEmail?: string;
}

/**
 * CDK Stack for Amazon SageMaker AutoML Time Series Forecasting
 * 
 * This stack creates a complete forecasting solution using SageMaker AutoML
 * that automatically selects and trains the best algorithms for time series data.
 * 
 * Key Components:
 * - S3 bucket for data storage with encryption and versioning
 * - IAM roles with least privilege permissions
 * - Lambda function for real-time forecast API
 * - API Gateway for external access
 * - CloudWatch monitoring and alarms
 * - SNS notifications for alerts
 */
export class AutoMLForecastingStack extends cdk.Stack {
  public readonly forecastBucket: s3.Bucket;
  public readonly sagemakerRole: iam.Role;
  public readonly lambdaFunction: lambda.Function;
  public readonly apiGateway: apigateway.RestApi;
  public readonly notificationTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: AutoMLForecastingStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const environmentName = props.environmentName ?? 'dev';
    const forecastHorizon = props.forecastHorizon ?? 14;
    const forecastFrequency = props.forecastFrequency ?? 'D';
    const enableEncryption = props.enableEncryption ?? true;
    const endpointInstanceType = props.endpointInstanceType ?? 'ml.m5.large';

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // Create S3 bucket for storing training data and model artifacts
    this.forecastBucket = new s3.Bucket(this, 'ForecastDataBucket', {
      bucketName: `automl-forecasting-${environmentName}-${uniqueSuffix}`,
      encryption: enableEncryption ? s3.BucketEncryption.S3_MANAGED : s3.BucketEncryption.UNENCRYPTED,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: RemovalPolicy.DESTROY, // Use RETAIN for production
      autoDeleteObjects: true, // Use false for production
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: Duration.days(30),
        },
        {
          id: 'TransitionToIA',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: Duration.days(90),
            },
          ],
        },
      ],
    });

    // Create IAM role for SageMaker AutoML with least privilege permissions
    this.sagemakerRole = new iam.Role(this, 'SageMakerAutoMLRole', {
      roleName: `AutoMLForecastingRole-${environmentName}-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('sagemaker.amazonaws.com'),
      description: 'IAM role for SageMaker AutoML forecasting operations',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSageMakerFullAccess'),
      ],
      inlinePolicies: {
        S3Access: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket',
              ],
              resources: [
                this.forecastBucket.bucketArn,
                this.forecastBucket.arnForObjects('*'),
              ],
            }),
          ],
        }),
        CloudWatchLogs: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
                'logs:DescribeLogStreams',
              ],
              resources: [`arn:aws:logs:${this.region}:${this.account}:log-group:/aws/sagemaker/*`],
            }),
          ],
        }),
      },
    });

    // Create SNS topic for notifications
    this.notificationTopic = new sns.Topic(this, 'ForecastNotificationTopic', {
      topicName: `automl-forecasting-alerts-${environmentName}-${uniqueSuffix}`,
      displayName: 'AutoML Forecasting Alerts',
    });

    // Add email subscription if provided
    if (props.notificationEmail) {
      this.notificationTopic.addSubscription(
        new sns.EmailSubscription(props.notificationEmail)
      );
    }

    // Create Lambda function for real-time forecast API
    this.lambdaFunction = new lambda.Function(this, 'ForecastAPIFunction', {
      functionName: `automl-forecast-api-${environmentName}-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: Duration.seconds(30),
      memorySize: 256,
      environment: {
        FORECAST_BUCKET: this.forecastBucket.bucketName,
        SAGEMAKER_ROLE_ARN: this.sagemakerRole.roleArn,
        FORECAST_HORIZON: forecastHorizon.toString(),
        FORECAST_FREQUENCY: forecastFrequency,
        ENVIRONMENT: environmentName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime, timedelta
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to provide real-time forecasting API
    """
    try:
        # Parse request
        body = json.loads(event.get('body', '{}'))
        item_id = body.get('item_id')
        forecast_horizon = int(body.get('forecast_horizon', os.environ.get('FORECAST_HORIZON', 14)))
        
        if not item_id:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'item_id is required'})
            }
        
        logger.info(f"Processing forecast request for item: {item_id}")
        
        # Initialize SageMaker runtime
        runtime = boto3.client('sagemaker-runtime')
        
        # Get endpoint name from environment or discover it
        endpoint_name = os.environ.get('SAGEMAKER_ENDPOINT_NAME')
        
        if not endpoint_name:
            # Try to discover active endpoints
            sagemaker = boto3.client('sagemaker')
            endpoints = sagemaker.list_endpoints(
                StatusEquals='InService',
                NameContains='automl-forecast'
            )
            
            if endpoints['Endpoints']:
                endpoint_name = endpoints['Endpoints'][0]['EndpointName']
                logger.info(f"Using discovered endpoint: {endpoint_name}")
            else:
                return {
                    'statusCode': 503,
                    'headers': {
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*'
                    },
                    'body': json.dumps({'error': 'No active forecast endpoint found'})
                }
        
        # Prepare mock inference request (in production, fetch real historical data from S3)
        inference_data = {
            'instances': [
                {
                    'start': '2023-01-01',
                    'target': [100 + i * 0.1 + (i % 7) * 5 for i in range(365)],  # Mock time series
                    'item_id': item_id
                }
            ],
            'configuration': {
                'num_samples': 100,
                'output_types': ['mean', 'quantiles'],
                'quantiles': ['0.1', '0.5', '0.9']
            }
        }
        
        # Make prediction
        response = runtime.invoke_endpoint(
            EndpointName=endpoint_name,
            ContentType='application/json',
            Body=json.dumps(inference_data)
        )
        
        # Parse response
        result = json.loads(response['Body'].read().decode())
        
        # Format response
        forecast_response = {
            'item_id': item_id,
            'forecast_horizon': forecast_horizon,
            'forecast': result.get('predictions', [{}])[0],
            'generated_at': datetime.now().isoformat(),
            'model_type': 'SageMaker AutoML',
            'confidence_intervals': True,
            'endpoint_name': endpoint_name
        }
        
        logger.info(f"Successfully generated forecast for item: {item_id}")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(forecast_response)
        }
        
    except Exception as e:
        logger.error(f"Error processing forecast request: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': str(e),
                'message': 'Internal server error'
            })
        }
`),
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // Grant Lambda permissions to access S3 and SageMaker
    this.forecastBucket.grantReadWrite(this.lambdaFunction);
    this.lambdaFunction.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'sagemaker:InvokeEndpoint',
          'sagemaker:ListEndpoints',
          'sagemaker:DescribeEndpoint',
        ],
        resources: [`arn:aws:sagemaker:${this.region}:${this.account}:endpoint/*`],
      })
    );

    // Create API Gateway for external access
    this.apiGateway = new apigateway.RestApi(this, 'ForecastAPI', {
      restApiName: `automl-forecast-api-${environmentName}`,
      description: 'API Gateway for AutoML forecasting service',
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key', 'X-Amz-Security-Token'],
      },
      deployOptions: {
        stageName: environmentName,
        throttlingRateLimit: 100,
        throttlingBurstLimit: 200,
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        dataTraceEnabled: true,
        metricsEnabled: true,
      },
    });

    // Create forecast resource and methods
    const forecastResource = this.apiGateway.root.addResource('forecast');
    
    // Add POST method for generating forecasts
    const lambdaIntegration = new apigateway.LambdaIntegration(this.lambdaFunction, {
      requestTemplates: { 'application/json': '{ "statusCode": "200" }' },
    });

    forecastResource.addMethod('POST', lambdaIntegration, {
      apiKeyRequired: false, // Set to true for production
      requestValidator: new apigateway.RequestValidator(this, 'ForecastRequestValidator', {
        restApi: this.apiGateway,
        requestValidatorName: 'forecast-request-validator',
        validateRequestBody: true,
        validateRequestParameters: true,
      }),
      requestModels: {
        'application/json': new apigateway.Model(this, 'ForecastRequestModel', {
          restApi: this.apiGateway,
          contentType: 'application/json',
          schema: {
            type: apigateway.JsonSchemaType.OBJECT,
            properties: {
              item_id: {
                type: apigateway.JsonSchemaType.STRING,
                description: 'Unique identifier for the item to forecast',
              },
              forecast_horizon: {
                type: apigateway.JsonSchemaType.INTEGER,
                minimum: 1,
                maximum: 365,
                description: 'Number of periods to forecast',
              },
            },
            required: ['item_id'],
          },
        }),
      },
    });

    // Add GET method for health checks
    forecastResource.addMethod('GET', new apigateway.MockIntegration({
      integrationResponses: [{
        statusCode: '200',
        responseTemplates: {
          'application/json': JSON.stringify({
            status: 'healthy',
            service: 'automl-forecasting-api',
            timestamp: new Date().toISOString(),
          }),
        },
      }],
      requestTemplates: {
        'application/json': '{ "statusCode": 200 }',
      },
    }), {
      methodResponses: [{
        statusCode: '200',
        responseModels: {
          'application/json': apigateway.Model.EMPTY_MODEL,
        },
      }],
    });

    // Create CloudWatch dashboard for monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'ForecastingDashboard', {
      dashboardName: `AutoML-Forecasting-${environmentName}-${uniqueSuffix}`,
    });

    // Add API Gateway metrics
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'API Gateway Metrics',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/ApiGateway',
            metricName: 'Count',
            dimensionsMap: {
              ApiName: this.apiGateway.restApiName,
              Stage: environmentName,
            },
            statistic: 'Sum',
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/ApiGateway',
            metricName: '4XXError',
            dimensionsMap: {
              ApiName: this.apiGateway.restApiName,
              Stage: environmentName,
            },
            statistic: 'Sum',
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/ApiGateway',
            metricName: '5XXError',
            dimensionsMap: {
              ApiName: this.apiGateway.restApiName,
              Stage: environmentName,
            },
            statistic: 'Sum',
          }),
        ],
        right: [
          new cloudwatch.Metric({
            namespace: 'AWS/ApiGateway',
            metricName: 'Latency',
            dimensionsMap: {
              ApiName: this.apiGateway.restApiName,
              Stage: environmentName,
            },
            statistic: 'Average',
          }),
        ],
      }),
    );

    // Add Lambda function metrics
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Lambda Function Metrics',
        left: [
          this.lambdaFunction.metricInvocations(),
          this.lambdaFunction.metricErrors(),
          this.lambdaFunction.metricThrottles(),
        ],
        right: [
          this.lambdaFunction.metricDuration(),
        ],
      }),
    );

    // Create CloudWatch alarms
    const highErrorRateAlarm = new cloudwatch.Alarm(this, 'HighErrorRateAlarm', {
      alarmName: `forecast-api-high-error-rate-${environmentName}`,
      alarmDescription: 'High error rate detected in forecast API',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ApiGateway',
        metricName: '5XXError',
        dimensionsMap: {
          ApiName: this.apiGateway.restApiName,
          Stage: environmentName,
        },
        statistic: 'Sum',
        period: Duration.minutes(5),
      }),
      threshold: 10,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    });

    const lambdaErrorAlarm = new cloudwatch.Alarm(this, 'LambdaErrorAlarm', {
      alarmName: `forecast-lambda-errors-${environmentName}`,
      alarmDescription: 'Lambda function errors detected',
      metric: this.lambdaFunction.metricErrors({
        period: Duration.minutes(5),
      }),
      threshold: 5,
      evaluationPeriods: 2,
    });

    // Add alarm actions to SNS topic
    highErrorRateAlarm.addAlarmAction(
      new cloudwatch.SnsAction(this.notificationTopic)
    );
    lambdaErrorAlarm.addAlarmAction(
      new cloudwatch.SnsAction(this.notificationTopic)
    );

    // Stack outputs
    new CfnOutput(this, 'ForecastBucketName', {
      value: this.forecastBucket.bucketName,
      description: 'S3 bucket for storing forecast data and models',
      exportName: `${this.stackName}-ForecastBucket`,
    });

    new CfnOutput(this, 'SageMakerRoleArn', {
      value: this.sagemakerRole.roleArn,
      description: 'IAM role ARN for SageMaker AutoML operations',
      exportName: `${this.stackName}-SageMakerRole`,
    });

    new CfnOutput(this, 'ForecastAPIEndpoint', {
      value: this.apiGateway.url,
      description: 'API Gateway endpoint for forecast requests',
      exportName: `${this.stackName}-APIEndpoint`,
    });

    new CfnOutput(this, 'LambdaFunctionName', {
      value: this.lambdaFunction.functionName,
      description: 'Lambda function name for forecast API',
      exportName: `${this.stackName}-LambdaFunction`,
    });

    new CfnOutput(this, 'NotificationTopicArn', {
      value: this.notificationTopic.topicArn,
      description: 'SNS topic ARN for forecast alerts',
      exportName: `${this.stackName}-NotificationTopic`,
    });

    new CfnOutput(this, 'CloudWatchDashboard', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch dashboard URL for monitoring',
    });

    // Tags for cost allocation and resource management
    cdk.Tags.of(this).add('Environment', environmentName);
    cdk.Tags.of(this).add('Application', 'AutoML-Forecasting');
    cdk.Tags.of(this).add('CostCenter', 'ML-Analytics');
    cdk.Tags.of(this).add('Owner', 'DataScience-Team');
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Get configuration from context or environment
const environmentName = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'dev';
const forecastHorizon = Number(app.node.tryGetContext('forecastHorizon')) || 14;
const forecastFrequency = app.node.tryGetContext('forecastFrequency') || 'D';
const enableEncryption = app.node.tryGetContext('enableEncryption') !== 'false';
const endpointInstanceType = app.node.tryGetContext('endpointInstanceType') || 'ml.m5.large';
const notificationEmail = app.node.tryGetContext('notificationEmail') || process.env.NOTIFICATION_EMAIL;

// Create the stack
new AutoMLForecastingStack(app, `AutoMLForecastingStack-${environmentName}`, {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Amazon SageMaker AutoML Time Series Forecasting Solution',
  environmentName,
  forecastHorizon,
  forecastFrequency,
  enableEncryption,
  endpointInstanceType,
  notificationEmail,
  tags: {
    Environment: environmentName,
    Application: 'AutoML-Forecasting',
    CreatedBy: 'CDK',
  },
});