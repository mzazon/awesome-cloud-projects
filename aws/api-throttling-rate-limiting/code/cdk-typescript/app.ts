#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Configuration interface for different usage plan tiers
 */
interface UsagePlanConfig {
  name: string;
  description: string;
  rateLimit: number;
  burstLimit: number;
  quotaLimit: number;
  quotaPeriod: apigateway.Period;
}

/**
 * CDK Stack for API Throttling and Rate Limiting
 * 
 * This stack creates:
 * - Lambda function as API backend
 * - API Gateway REST API with throttling controls
 * - Three usage plans with different rate limits (Basic, Standard, Premium)
 * - API keys for each tier
 * - CloudWatch monitoring and alarms
 */
export class ApiThrottlingRateLimitingStack extends cdk.Stack {
  public readonly apiUrl: string;
  public readonly apiKeys: { [key: string]: string };

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const randomSuffix = Math.random().toString(36).substring(2, 8);

    // Define usage plan configurations
    const usagePlanConfigs: UsagePlanConfig[] = [
      {
        name: `Basic-Plan-${randomSuffix}`,
        description: 'Basic tier with low limits',
        rateLimit: 100,
        burstLimit: 200,
        quotaLimit: 10000,
        quotaPeriod: apigateway.Period.MONTH
      },
      {
        name: `Standard-Plan-${randomSuffix}`,
        description: 'Standard tier with moderate limits',
        rateLimit: 500,
        burstLimit: 1000,
        quotaLimit: 100000,
        quotaPeriod: apigateway.Period.MONTH
      },
      {
        name: `Premium-Plan-${randomSuffix}`,
        description: 'Premium tier with high limits',
        rateLimit: 2000,
        burstLimit: 5000,
        quotaLimit: 1000000,
        quotaPeriod: apigateway.Period.MONTH
      }
    ];

    // Create Lambda execution role with basic execution permissions
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      description: 'Execution role for API backend Lambda function'
    });

    // Create Lambda function for API backend
    const backendFunction = new lambda.Function(this, 'ApiBackendFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      code: lambda.Code.fromInline(`
import json
import time
import os

def lambda_handler(event, context):
    """
    Simple API backend function that returns a JSON response
    Includes processing delay to simulate real work
    """
    # Simulate some processing time
    time.sleep(0.1)
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'message': 'Hello from throttled API!',
            'timestamp': int(time.time()),
            'requestId': context.aws_request_id,
            'region': os.environ.get('AWS_REGION', 'unknown')
        })
    }
`),
      functionName: `api-backend-${randomSuffix}`,
      timeout: cdk.Duration.seconds(30),
      memorySize: 128,
      description: 'Backend function for API throttling demonstration'
    });

    // Create CloudWatch log group for Lambda function
    new logs.LogGroup(this, 'BackendFunctionLogGroup', {
      logGroupName: `/aws/lambda/${backendFunction.functionName}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Create REST API with throttling configuration
    const api = new apigateway.RestApi(this, 'ThrottlingDemoApi', {
      restApiName: `throttling-demo-${randomSuffix}`,
      description: 'Demo API for throttling and rate limiting',
      
      // Configure default throttling at the API level
      deployOptions: {
        stageName: 'prod',
        throttleSettings: {
          rateLimit: 1000,
          burstLimit: 2000
        },
        // Enable detailed CloudWatch metrics
        metricsEnabled: true,
        dataTraceEnabled: false, // Disable for production to avoid logging sensitive data
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        accessLogDestination: new apigateway.LogGroupLogDestination(
          new logs.LogGroup(this, 'ApiAccessLogGroup', {
            logGroupName: `/aws/apigateway/${randomSuffix}/access-logs`,
            retention: logs.RetentionDays.ONE_WEEK,
            removalPolicy: cdk.RemovalPolicy.DESTROY
          })
        ),
        accessLogFormat: apigateway.AccessLogFormat.jsonWithStandardFields({
          caller: false,
          httpMethod: true,
          ip: true,
          protocol: true,
          requestTime: true,
          resourcePath: true,
          responseLength: true,
          status: true,
          user: true
        })
      },
      
      // Configure CORS for web applications
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key']
      }
    });

    // Create Lambda integration
    const lambdaIntegration = new apigateway.LambdaIntegration(backendFunction, {
      requestTemplates: { 'application/json': '{ "statusCode": "200" }' },
      integrationResponses: [
        {
          statusCode: '200',
          responseTemplates: {
            'application/json': ''
          }
        }
      ]
    });

    // Create API resource and method with API key requirement
    const dataResource = api.root.addResource('data');
    const dataMethod = dataResource.addMethod('GET', lambdaIntegration, {
      apiKeyRequired: true,
      methodResponses: [
        {
          statusCode: '200',
          responseModels: {
            'application/json': apigateway.Model.EMPTY_MODEL
          }
        }
      ]
    });

    // Store API keys for output
    this.apiKeys = {};

    // Create usage plans, API keys, and associate them
    const usagePlans: apigateway.UsagePlan[] = [];
    
    usagePlanConfigs.forEach((config, index) => {
      // Create usage plan
      const usagePlan = new apigateway.UsagePlan(this, `UsagePlan${index}`, {
        name: config.name,
        description: config.description,
        throttle: {
          rateLimit: config.rateLimit,
          burstLimit: config.burstLimit
        },
        quota: {
          limit: config.quotaLimit,
          period: config.quotaPeriod
        },
        apiStages: [
          {
            api: api,
            stage: api.deploymentStage
          }
        ]
      });

      usagePlans.push(usagePlan);

      // Create API key for this usage plan
      const tierName = config.name.split('-')[0].toLowerCase();
      const apiKey = new apigateway.ApiKey(this, `ApiKey${index}`, {
        apiKeyName: `${tierName}-customer-${randomSuffix}`,
        description: `${config.description} customer API key`,
        enabled: true
      });

      // Associate API key with usage plan
      usagePlan.addApiKey(apiKey);

      // Store API key ID for output (actual value will be available after deployment)
      this.apiKeys[tierName] = apiKey.keyId;
    });

    // Create CloudWatch alarms for monitoring
    const throttleAlarm = new cloudwatch.Alarm(this, 'HighThrottlingAlarm', {
      alarmName: `API-High-Throttling-${randomSuffix}`,
      alarmDescription: 'Alert when API throttling exceeds threshold',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ApiGateway',
        metricName: 'Count',
        dimensionsMap: {
          ApiName: api.restApiName,
          Stage: api.deploymentStage.stageName
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 100,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    const errorAlarm = new cloudwatch.Alarm(this, 'High4xxErrorsAlarm', {
      alarmName: `API-High-4xx-Errors-${randomSuffix}`,
      alarmDescription: 'Alert when 4xx errors exceed threshold',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ApiGateway',
        metricName: '4XXError',
        dimensionsMap: {
          ApiName: api.restApiName,
          Stage: api.deploymentStage.stageName
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 50,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Store API URL for output
    this.apiUrl = api.url + 'data';

    // CloudFormation Outputs
    new cdk.CfnOutput(this, 'ApiUrl', {
      value: this.apiUrl,
      description: 'URL of the throttled API endpoint'
    });

    new cdk.CfnOutput(this, 'ApiId', {
      value: api.restApiId,
      description: 'ID of the REST API'
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: backendFunction.functionName,
      description: 'Name of the backend Lambda function'
    });

    new cdk.CfnOutput(this, 'BasicApiKeyId', {
      value: this.apiKeys['basic'],
      description: 'ID of the Basic tier API key (use AWS CLI to get value)'
    });

    new cdk.CfnOutput(this, 'StandardApiKeyId', {
      value: this.apiKeys['standard'],
      description: 'ID of the Standard tier API key (use AWS CLI to get value)'
    });

    new cdk.CfnOutput(this, 'PremiumApiKeyId', {
      value: this.apiKeys['premium'],
      description: 'ID of the Premium tier API key (use AWS CLI to get value)'
    });

    new cdk.CfnOutput(this, 'ThrottleAlarmName', {
      value: throttleAlarm.alarmName,
      description: 'Name of the throttling CloudWatch alarm'
    });

    new cdk.CfnOutput(this, 'ErrorAlarmName', {
      value: errorAlarm.alarmName,
      description: 'Name of the 4xx errors CloudWatch alarm'
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'ApiThrottlingDemo');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('Purpose', 'Rate-Limiting-Example');
  }
}

// Create CDK App and instantiate the stack
const app = new cdk.App();

new ApiThrottlingRateLimitingStack(app, 'ApiThrottlingRateLimitingStack', {
  description: 'CDK stack for API throttling and rate limiting demonstration',
  
  // Specify environment if needed (uncomment and modify as needed)
  // env: {
  //   account: process.env.CDK_DEFAULT_ACCOUNT,
  //   region: process.env.CDK_DEFAULT_REGION,
  // },
  
  // Add stack-level tags
  tags: {
    Project: 'ApiThrottlingDemo',
    CreatedBy: 'CDK',
    Recipe: 'api-throttling-rate-limiting-api-gateway'
  }
});

// Synthesize the CDK app
app.synth();