#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as fs from 'fs';
import * as path from 'path';

/**
 * Stack for Lambda Safe Deployments with Blue-Green and Canary
 */
export class LambdaDeploymentPatternsStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // Create IAM execution role for Lambda function
    const lambdaExecutionRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `lambda-deploy-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      description: 'IAM role for Lambda function with deployment patterns'
    });

    // Create Lambda function code for version 1 (Blue environment)
    const lambdaCodeV1 = `
import json
import os

def lambda_handler(event, context):
    version = "1.0.0"
    message = "Hello from Lambda Version 1 - Blue Environment"
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'version': version,
            'message': message,
            'timestamp': context.aws_request_id,
            'environment': 'blue'
        })
    }
`;

    // Create Lambda function code for version 2 (Green environment)
    const lambdaCodeV2 = `
import json
import os

def lambda_handler(event, context):
    version = "2.0.0"
    message = "Hello from Lambda Version 2 - Green Environment with NEW FEATURES!"
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'version': version,
            'message': message,
            'timestamp': context.aws_request_id,
            'environment': 'green',
            'features': ['enhanced_logging', 'improved_performance']
        })
    }
`;

    // Create Lambda function with initial version 1 code
    const lambdaFunction = new lambda.Function(this, 'DeploymentPatternsFunction', {
      functionName: `deploy-patterns-demo-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'lambda_function.lambda_handler',
      role: lambdaExecutionRole,
      code: lambda.Code.fromInline(lambdaCodeV1),
      description: 'Demo function for deployment patterns',
      timeout: cdk.Duration.seconds(30),
      memorySize: 128,
      environment: {
        DEPLOYMENT_PATTERN: 'blue-green-canary'
      }
    });

    // Create Lambda function version 1 (Blue)
    const version1 = new lambda.Version(this, 'Version1', {
      lambda: lambdaFunction,
      description: 'Initial production version - Blue environment'
    });

    // Create Lambda function version 2 (Green) by updating the code
    // Note: In a real scenario, you would deploy this as a separate deployment
    const version2Function = new lambda.Function(this, 'Version2Function', {
      functionName: `deploy-patterns-demo-v2-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'lambda_function.lambda_handler',
      role: lambdaExecutionRole,
      code: lambda.Code.fromInline(lambdaCodeV2),
      description: 'Version 2 with new features - Green environment',
      timeout: cdk.Duration.seconds(30),
      memorySize: 128,
      environment: {
        DEPLOYMENT_PATTERN: 'blue-green-canary',
        VERSION: '2.0.0'
      }
    });

    const version2 = new lambda.Version(this, 'Version2', {
      lambda: version2Function,
      description: 'Version 2 with new features - Green environment'
    });

    // Create production alias with weighted routing
    // Initially points to version 1, can be updated for canary/blue-green deployments
    const productionAlias = new lambda.Alias(this, 'ProductionAlias', {
      aliasName: 'production',
      version: version1,
      description: 'Production alias for blue-green deployments',
      // Configure weighted routing for canary deployment
      additionalVersions: [
        {
          version: version2,
          weight: 0.1 // 10% traffic to version 2 (canary)
        }
      ]
    });

    // Create REST API Gateway
    const api = new apigateway.RestApi(this, 'DeploymentApi', {
      restApiName: `deployment-api-${uniqueSuffix}`,
      description: 'API for Lambda deployment patterns demo',
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key']
      }
    });

    // Create demo resource
    const demoResource = api.root.addResource('demo');

    // Create Lambda integration using production alias
    const lambdaIntegration = new apigateway.LambdaIntegration(productionAlias, {
      requestTemplates: { 'application/json': '{ "statusCode": "200" }' },
      proxy: true
    });

    // Add GET method to demo resource
    demoResource.addMethod('GET', lambdaIntegration, {
      authorizationType: apigateway.AuthorizationType.NONE,
      methodResponses: [{
        statusCode: '200',
        responseParameters: {
          'method.response.header.Access-Control-Allow-Origin': true
        }
      }]
    });

    // Create CloudWatch alarm for error rate monitoring
    const errorRateAlarm = new cloudwatch.Alarm(this, 'ErrorRateAlarm', {
      alarmName: `${lambdaFunction.functionName}-error-rate`,
      alarmDescription: 'Monitor Lambda function error rate',
      metric: lambdaFunction.metricErrors({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum'
      }),
      threshold: 5,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Create SNS topic for alarm notifications (optional)
    const alarmTopic = new sns.Topic(this, 'AlarmTopic', {
      topicName: `lambda-deployment-alarms-${uniqueSuffix}`,
      displayName: 'Lambda Deployment Alarms'
    });

    // Add SNS action to alarm
    errorRateAlarm.addAlarmAction(new cloudwatchActions.SnsAction(alarmTopic));

    // Create additional CloudWatch alarms for comprehensive monitoring
    const durationAlarm = new cloudwatch.Alarm(this, 'DurationAlarm', {
      alarmName: `${lambdaFunction.functionName}-duration`,
      alarmDescription: 'Monitor Lambda function duration',
      metric: lambdaFunction.metricDuration({
        period: cdk.Duration.minutes(5),
        statistic: 'Average'
      }),
      threshold: 10000, // 10 seconds
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
    });

    const throttleAlarm = new cloudwatch.Alarm(this, 'ThrottleAlarm', {
      alarmName: `${lambdaFunction.functionName}-throttles`,
      alarmDescription: 'Monitor Lambda function throttles',
      metric: lambdaFunction.metricThrottles({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum'
      }),
      threshold: 1,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD
    });

    // Output important values for testing and management
    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: lambdaFunction.functionName,
      description: 'Name of the Lambda function'
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: lambdaFunction.functionArn,
      description: 'ARN of the Lambda function'
    });

    new cdk.CfnOutput(this, 'ProductionAliasArn', {
      value: productionAlias.functionArn,
      description: 'ARN of the production alias'
    });

    new cdk.CfnOutput(this, 'ApiGatewayUrl', {
      value: api.url,
      description: 'URL of the API Gateway'
    });

    new cdk.CfnOutput(this, 'ApiGatewayEndpoint', {
      value: `${api.url}demo`,
      description: 'Complete API endpoint URL for testing'
    });

    new cdk.CfnOutput(this, 'Version1Arn', {
      value: version1.functionArn,
      description: 'ARN of Lambda function version 1'
    });

    new cdk.CfnOutput(this, 'Version2Arn', {
      value: version2.functionArn,
      description: 'ARN of Lambda function version 2'
    });

    new cdk.CfnOutput(this, 'CloudWatchAlarmName', {
      value: errorRateAlarm.alarmName,
      description: 'Name of the CloudWatch error rate alarm'
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: alarmTopic.topicArn,
      description: 'ARN of the SNS topic for alarm notifications'
    });

    // Add tags to all resources for better organization
    cdk.Tags.of(this).add('Project', 'LambdaDeploymentPatterns');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('Purpose', 'BlueGreenCanaryDeployment');
  }
}

// Create the CDK app
const app = new cdk.App();

// Create the stack
new LambdaDeploymentPatternsStack(app, 'LambdaDeploymentPatternsStack', {
  description: 'Stack for implementing Lambda deployment patterns with blue-green and canary releases',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  }
});

// Synthesize the app
app.synth();