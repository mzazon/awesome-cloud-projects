#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as acm from 'aws-cdk-lib/aws-certificatemanager';

/**
 * Stack for implementing advanced API Gateway deployment strategies
 * with blue-green and canary patterns
 */
export class AdvancedApiGatewayDeploymentStack extends cdk.Stack {
  public readonly api: apigateway.RestApi;
  public readonly blueFunction: lambda.Function;
  public readonly greenFunction: lambda.Function;
  public readonly productionStage: apigateway.Stage;
  public readonly stagingStage: apigateway.Stage;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create IAM role for Lambda functions
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for API Gateway deployment Lambda functions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Create CloudWatch log groups for Lambda functions
    const blueLogGroup = new logs.LogGroup(this, 'BlueLogGroup', {
      logGroupName: '/aws/lambda/blue-api-function',
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    const greenLogGroup = new logs.LogGroup(this, 'GreenLogGroup', {
      logGroupName: '/aws/lambda/green-api-function',
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create Blue Lambda function (current production version)
    this.blueFunction = new lambda.Function(this, 'BlueFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      description: 'Blue environment API function - current production version',
      logGroup: blueLogGroup,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      environment: {
        ENVIRONMENT: 'blue',
        VERSION: 'v1.0.0',
      },
      code: lambda.Code.fromInline(`
import json
import os

def lambda_handler(event, context):
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'message': 'Hello from Blue environment!',
            'version': 'v1.0.0',
            'environment': 'blue',
            'timestamp': context.aws_request_id
        })
    }
      `),
    });

    // Create Green Lambda function (new version for testing)
    this.greenFunction = new lambda.Function(this, 'GreenFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      description: 'Green environment API function - new version for testing',
      logGroup: greenLogGroup,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      environment: {
        ENVIRONMENT: 'green',
        VERSION: 'v2.0.0',
      },
      code: lambda.Code.fromInline(`
import json
import os

def lambda_handler(event, context):
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'message': 'Hello from Green environment!',
            'version': 'v2.0.0',
            'environment': 'green',
            'timestamp': context.aws_request_id,
            'new_feature': 'Enhanced response format'
        })
    }
      `),
    });

    // Create API Gateway REST API
    this.api = new apigateway.RestApi(this, 'AdvancedDeploymentApi', {
      restApiName: 'Advanced Deployment API',
      description: 'API demonstrating advanced deployment strategies with blue-green and canary patterns',
      deploy: false, // We'll handle deployment manually for better control
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'Authorization'],
      },
      cloudWatchRole: true,
      cloudWatchRoleRemovalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create /hello resource
    const helloResource = this.api.root.addResource('hello');

    // Create Lambda integrations
    const blueIntegration = new apigateway.LambdaIntegration(this.blueFunction, {
      requestTemplates: { 'application/json': '{ "statusCode": "200" }' },
      proxy: true,
    });

    const greenIntegration = new apigateway.LambdaIntegration(this.greenFunction, {
      requestTemplates: { 'application/json': '{ "statusCode": "200" }' },
      proxy: true,
    });

    // Add GET method to /hello resource
    helloResource.addMethod('GET', blueIntegration, {
      methodResponses: [
        {
          statusCode: '200',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
      ],
    });

    // Create deployments
    const blueDeployment = new apigateway.Deployment(this, 'BlueDeployment', {
      api: this.api,
      description: 'Blue environment deployment',
    });

    const greenDeployment = new apigateway.Deployment(this, 'GreenDeployment', {
      api: this.api,
      description: 'Green environment deployment',
    });

    // Create production stage with Blue deployment
    this.productionStage = new apigateway.Stage(this, 'ProductionStage', {
      deployment: blueDeployment,
      stageName: 'production',
      description: 'Production stage with Blue environment',
      throttle: {
        rateLimit: 1000,
        burstLimit: 2000,
      },
      accessLogDestination: new apigateway.LogGroupLogDestination(
        new logs.LogGroup(this, 'ProductionAccessLogs', {
          logGroupName: '/aws/apigateway/production-access-logs',
          retention: logs.RetentionDays.ONE_WEEK,
          removalPolicy: cdk.RemovalPolicy.DESTROY,
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
        user: true,
      }),
      tracingEnabled: true,
      metricsEnabled: true,
      loggingLevel: apigateway.MethodLoggingLevel.INFO,
      dataTraceEnabled: true,
    });

    // Create staging stage for Green deployment testing
    this.stagingStage = new apigateway.Stage(this, 'StagingStage', {
      deployment: greenDeployment,
      stageName: 'staging',
      description: 'Staging stage for Green environment testing',
      throttle: {
        rateLimit: 500,
        burstLimit: 1000,
      },
      accessLogDestination: new apigateway.LogGroupLogDestination(
        new logs.LogGroup(this, 'StagingAccessLogs', {
          logGroupName: '/aws/apigateway/staging-access-logs',
          retention: logs.RetentionDays.ONE_WEEK,
          removalPolicy: cdk.RemovalPolicy.DESTROY,
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
        user: true,
      }),
      tracingEnabled: true,
      metricsEnabled: true,
      loggingLevel: apigateway.MethodLoggingLevel.INFO,
      dataTraceEnabled: true,
    });

    // Create CloudWatch alarms for monitoring deployment health
    const api4xxAlarm = new cloudwatch.Alarm(this, 'Api4xxErrorAlarm', {
      alarmName: `${this.api.restApiName}-4xx-errors`,
      alarmDescription: 'API Gateway 4XX errors',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ApiGateway',
        metricName: '4XXError',
        dimensionsMap: {
          ApiName: this.api.restApiName,
          Stage: this.productionStage.stageName,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 10,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const api5xxAlarm = new cloudwatch.Alarm(this, 'Api5xxErrorAlarm', {
      alarmName: `${this.api.restApiName}-5xx-errors`,
      alarmDescription: 'API Gateway 5XX errors',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ApiGateway',
        metricName: '5XXError',
        dimensionsMap: {
          ApiName: this.api.restApiName,
          Stage: this.productionStage.stageName,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 5,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const apiLatencyAlarm = new cloudwatch.Alarm(this, 'ApiLatencyAlarm', {
      alarmName: `${this.api.restApiName}-high-latency`,
      alarmDescription: 'API Gateway high latency',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ApiGateway',
        metricName: 'Latency',
        dimensionsMap: {
          ApiName: this.api.restApiName,
          Stage: this.productionStage.stageName,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 5000, // 5 seconds
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Create CloudWatch dashboard for monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'ApiDeploymentDashboard', {
      dashboardName: 'Advanced-API-Gateway-Deployment-Dashboard',
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'API Gateway Requests',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/ApiGateway',
                metricName: 'Count',
                dimensionsMap: {
                  ApiName: this.api.restApiName,
                  Stage: this.productionStage.stageName,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'API Gateway Errors',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/ApiGateway',
                metricName: '4XXError',
                dimensionsMap: {
                  ApiName: this.api.restApiName,
                  Stage: this.productionStage.stageName,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/ApiGateway',
                metricName: '5XXError',
                dimensionsMap: {
                  ApiName: this.api.restApiName,
                  Stage: this.productionStage.stageName,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'API Gateway Latency',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/ApiGateway',
                metricName: 'Latency',
                dimensionsMap: {
                  ApiName: this.api.restApiName,
                  Stage: this.productionStage.stageName,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
      ],
    });

    // Output important information
    new cdk.CfnOutput(this, 'ApiGatewayId', {
      value: this.api.restApiId,
      description: 'API Gateway REST API ID',
      exportName: 'ApiGatewayId',
    });

    new cdk.CfnOutput(this, 'ApiEndpoint', {
      value: this.api.url,
      description: 'API Gateway endpoint URL',
      exportName: 'ApiEndpoint',
    });

    new cdk.CfnOutput(this, 'ProductionStageUrl', {
      value: this.productionStage.url,
      description: 'Production stage URL',
      exportName: 'ProductionStageUrl',
    });

    new cdk.CfnOutput(this, 'StagingStageUrl', {
      value: this.stagingStage.url,
      description: 'Staging stage URL',
      exportName: 'StagingStageUrl',
    });

    new cdk.CfnOutput(this, 'BlueFunctionArn', {
      value: this.blueFunction.functionArn,
      description: 'Blue Lambda function ARN',
      exportName: 'BlueFunctionArn',
    });

    new cdk.CfnOutput(this, 'GreenFunctionArn', {
      value: this.greenFunction.functionArn,
      description: 'Green Lambda function ARN',
      exportName: 'GreenFunctionArn',
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch dashboard URL',
      exportName: 'DashboardUrl',
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Application', 'AdvancedApiGatewayDeployment');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('DeploymentStrategy', 'BlueGreenCanary');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }
}

/**
 * Custom construct for implementing canary deployment logic
 */
export class CanaryDeploymentConstruct extends Construct {
  constructor(scope: Construct, id: string, props: {
    api: apigateway.RestApi;
    productionStage: apigateway.Stage;
    greenDeployment: apigateway.Deployment;
    canaryPercentage: number;
  }) {
    super(scope, id);

    // This would typically be implemented with a custom resource or Lambda function
    // to handle the canary deployment logic programmatically
    // For now, we'll create the infrastructure that supports manual canary deployments
    
    // Create a custom resource that can manage canary deployments
    const canaryRole = new iam.Role(this, 'CanaryManagementRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        ApiGatewayManagement: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'apigateway:GET',
                'apigateway:POST',
                'apigateway:PUT',
                'apigateway:PATCH',
                'apigateway:DELETE',
              ],
              resources: [
                `arn:aws:apigateway:${cdk.Stack.of(this).region}::/restapis/${props.api.restApiId}/*`,
              ],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:GetMetricStatistics',
                'cloudwatch:PutMetricAlarm',
                'cloudwatch:DeleteAlarms',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    const canaryManagementFunction = new lambda.Function(this, 'CanaryManagementFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: canaryRole,
      description: 'Function to manage canary deployments',
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      environment: {
        API_ID: props.api.restApiId,
        PRODUCTION_STAGE: props.productionStage.stageName,
        CANARY_PERCENTAGE: props.canaryPercentage.toString(),
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from typing import Dict, Any

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function to manage canary deployments for API Gateway
    """
    client = boto3.client('apigateway')
    cloudwatch = boto3.client('cloudwatch')
    
    api_id = os.environ['API_ID']
    stage_name = os.environ['PRODUCTION_STAGE']
    canary_percentage = float(os.environ['CANARY_PERCENTAGE'])
    
    action = event.get('action', 'status')
    
    try:
        if action == 'create_canary':
            # Create canary deployment
            deployment_id = event.get('deployment_id')
            if not deployment_id:
                raise ValueError('deployment_id is required for create_canary action')
            
            response = client.create_deployment(
                restApiId=api_id,
                stageName=stage_name,
                description=f'Canary deployment - {canary_percentage}% traffic',
                canarySettings={
                    'percentTraffic': canary_percentage,
                    'deploymentId': deployment_id,
                    'useStageCache': False
                }
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Canary deployment created with {canary_percentage}% traffic',
                    'deployment_id': response['id']
                })
            }
        
        elif action == 'update_canary':
            # Update canary traffic percentage
            new_percentage = event.get('percentage', canary_percentage)
            
            client.update_stage(
                restApiId=api_id,
                stageName=stage_name,
                patchOps=[
                    {
                        'op': 'replace',
                        'path': '/canarySettings/percentTraffic',
                        'value': str(new_percentage)
                    }
                ]
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Canary traffic updated to {new_percentage}%'
                })
            }
        
        elif action == 'promote_canary':
            # Promote canary to production
            stage_info = client.get_stage(restApiId=api_id, stageName=stage_name)
            canary_deployment_id = stage_info['canarySettings']['deploymentId']
            
            client.update_stage(
                restApiId=api_id,
                stageName=stage_name,
                patchOps=[
                    {
                        'op': 'replace',
                        'path': '/deploymentId',
                        'value': canary_deployment_id
                    },
                    {
                        'op': 'remove',
                        'path': '/canarySettings'
                    }
                ]
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Canary promoted to production'
                })
            }
        
        elif action == 'rollback_canary':
            # Remove canary deployment (rollback)
            client.update_stage(
                restApiId=api_id,
                stageName=stage_name,
                patchOps=[
                    {
                        'op': 'remove',
                        'path': '/canarySettings'
                    }
                ]
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Canary deployment rolled back'
                })
            }
        
        else:
            # Get canary status
            try:
                stage_info = client.get_stage(restApiId=api_id, stageName=stage_name)
                canary_settings = stage_info.get('canarySettings', {})
                
                if canary_settings:
                    return {
                        'statusCode': 200,
                        'body': json.dumps({
                            'canary_active': True,
                            'percent_traffic': canary_settings.get('percentTraffic', 0),
                            'deployment_id': canary_settings.get('deploymentId', ''),
                            'use_stage_cache': canary_settings.get('useStageCache', False)
                        })
                    }
                else:
                    return {
                        'statusCode': 200,
                        'body': json.dumps({
                            'canary_active': False,
                            'message': 'No canary deployment active'
                        })
                    }
            except Exception as e:
                return {
                    'statusCode': 500,
                    'body': json.dumps({
                        'error': f'Error getting canary status: {str(e)}'
                    })
                }
    
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'Error performing action {action}: {str(e)}'
            })
        }
      `),
    });

    // Output the canary management function ARN
    new cdk.CfnOutput(this, 'CanaryManagementFunctionArn', {
      value: canaryManagementFunction.functionArn,
      description: 'Canary management function ARN',
      exportName: 'CanaryManagementFunctionArn',
    });
  }
}

// CDK Application
const app = new cdk.App();

// Create the main stack
const stack = new AdvancedApiGatewayDeploymentStack(app, 'AdvancedApiGatewayDeploymentStack', {
  description: 'Advanced API Gateway deployment strategies with blue-green and canary patterns',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

// Add canary deployment construct
new CanaryDeploymentConstruct(stack, 'CanaryDeployment', {
  api: stack.api,
  productionStage: stack.productionStage,
  greenDeployment: new apigateway.Deployment(stack, 'GreenDeploymentForCanary', {
    api: stack.api,
    description: 'Green deployment for canary testing',
  }),
  canaryPercentage: 10,
});

// Synthesize the CDK app
app.synth();