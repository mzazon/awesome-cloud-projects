#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

/**
 * CDK Stack for Simple Timezone Converter API
 * 
 * This stack creates:
 * - Lambda function with Python 3.12 runtime for timezone conversion
 * - API Gateway REST API with /convert POST endpoint
 * - IAM role with least privilege permissions for Lambda execution
 * - CloudWatch Logs integration for monitoring and troubleshooting
 */
export class TimezoneConverterStack extends cdk.Stack {
  // Stack outputs for external reference
  public readonly apiEndpoint: cdk.CfnOutput;
  public readonly lambdaFunction: lambda.Function;
  public readonly restApi: apigateway.RestApi;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // Create IAM role for Lambda execution with least privilege permissions
    const lambdaExecutionRole = new iam.Role(this, 'TimezoneConverterExecutionRole', {
      roleName: `timezone-converter-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for timezone converter Lambda function',
      managedPolicies: [
        // Basic execution role provides CloudWatch Logs permissions
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ]
    });

    // Lambda function code for timezone conversion
    const lambdaCode = `
import json
import logging
from datetime import datetime
from zoneinfo import ZoneInfo

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Convert timestamp between timezones
    
    Expected event format:
    {
      "timestamp": "2025-07-12T15:30:00",
      "from_timezone": "UTC",
      "to_timezone": "America/New_York"
    }
    """
    try:
        # Parse the request body
        if 'body' in event:
            body = json.loads(event['body'])
        else:
            body = event
        
        # Extract required parameters
        timestamp_str = body.get('timestamp')
        from_tz = body.get('from_timezone', 'UTC')
        to_tz = body.get('to_timezone')
        
        # Validate required parameters
        if not timestamp_str or not to_tz:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'Missing required parameters: timestamp and to_timezone'
                })
            }
        
        # Parse the timestamp
        try:
            # Try parsing with timezone info first
            if 'T' in timestamp_str and ('+' in timestamp_str or 'Z' in timestamp_str):
                dt = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
            else:
                # Parse as naive datetime and assign source timezone
                dt_naive = datetime.fromisoformat(timestamp_str)
                dt = dt_naive.replace(tzinfo=ZoneInfo(from_tz))
        except ValueError as e:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': f'Invalid timestamp format: {str(e)}'
                })
            }
        
        # Convert to target timezone
        try:
            target_tz = ZoneInfo(to_tz)
            converted_dt = dt.astimezone(target_tz)
        except Exception as e:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': f'Invalid timezone: {str(e)}'
                })
            }
        
        # Format response
        response_data = {
            'original_timestamp': timestamp_str,
            'original_timezone': from_tz,
            'converted_timestamp': converted_dt.isoformat(),
            'target_timezone': to_tz,
            'timezone_offset': converted_dt.strftime('%z'),
            'timezone_name': converted_dt.tzname()
        }
        
        logger.info(f"Converted {timestamp_str} from {from_tz} to {to_tz}")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(response_data)
        }
        
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error'
            })
        }
`;

    // Create Lambda function with optimal configuration for timezone conversion
    this.lambdaFunction = new lambda.Function(this, 'TimezoneConverterFunction', {
      functionName: `timezone-converter-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12, // Latest Python runtime with zoneinfo support
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(lambdaCode),
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(30), // Sufficient for timezone calculations
      memorySize: 128, // Minimal memory for lightweight operations
      description: 'Simple timezone converter API using Python zoneinfo module',
      environment: {
        // Environment variables for Lambda function configuration
        LOG_LEVEL: 'INFO'
      },
      // Enable function insights for enhanced monitoring
      insightsVersion: lambda.LambdaInsightsVersion.VERSION_1_0_119_0
    });

    // Create API Gateway REST API with regional endpoint configuration
    this.restApi = new apigateway.RestApi(this, 'TimezoneConverterApi', {
      restApiName: `timezone-converter-api-${uniqueSuffix}`,
      description: 'REST API for timezone conversion service',
      endpointConfiguration: {
        types: [apigateway.EndpointType.REGIONAL]
      },
      // Enable CloudWatch request logging for production monitoring
      deployOptions: {
        stageName: 'prod',
        description: 'Production deployment of timezone converter API',
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        dataTraceEnabled: true,
        metricsEnabled: true
      },
      // Configure default CORS for web browser compatibility
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key']
      }
    });

    // Create /convert resource for timezone conversion endpoint
    const convertResource = this.restApi.root.addResource('convert', {
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: ['POST', 'OPTIONS'],
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key']
      }
    });

    // Create Lambda integration with AWS_PROXY type for complete request context
    const lambdaIntegration = new apigateway.LambdaIntegration(this.lambdaFunction, {
      requestTemplates: { 'application/json': '{ "statusCode": "200" }' },
      proxy: true, // Enable proxy integration for flexible request/response handling
      integrationResponses: [
        {
          statusCode: '200',
          responseParameters: {
            // Enable CORS headers in response
            'method.response.header.Access-Control-Allow-Origin': "'*'",
            'method.response.header.Access-Control-Allow-Headers': "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'",
            'method.response.header.Access-Control-Allow-Methods': "'POST,OPTIONS'"
          }
        }
      ]
    });

    // Add POST method to /convert resource with proper error handling
    convertResource.addMethod('POST', lambdaIntegration, {
      authorizationType: apigateway.AuthorizationType.NONE,
      methodResponses: [
        {
          statusCode: '200',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
            'method.response.header.Access-Control-Allow-Headers': true,
            'method.response.header.Access-Control-Allow-Methods': true
          }
        },
        {
          statusCode: '400',
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

    // Grant API Gateway permission to invoke Lambda function
    this.lambdaFunction.addPermission('ApiGatewayInvokePermission', {
      principal: new iam.ServicePrincipal('apigateway.amazonaws.com'),
      action: 'lambda:InvokeFunction',
      sourceArn: this.restApi.arnForExecuteApi('*', '/convert', 'POST')
    });

    // Create stack outputs for external reference and verification
    this.apiEndpoint = new cdk.CfnOutput(this, 'ApiEndpoint', {
      value: `${this.restApi.url}convert`,
      description: 'API Gateway endpoint URL for timezone conversion',
      exportName: 'TimezoneConverterApiEndpoint'
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: this.lambdaFunction.functionName,
      description: 'Lambda function name for timezone conversion',
      exportName: 'TimezoneConverterLambdaFunction'
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: this.lambdaFunction.functionArn,
      description: 'Lambda function ARN for timezone conversion',
      exportName: 'TimezoneConverterLambdaArn'
    });

    new cdk.CfnOutput(this, 'ApiGatewayId', {
      value: this.restApi.restApiId,
      description: 'API Gateway REST API ID',
      exportName: 'TimezoneConverterApiId'
    });

    // Add tags for resource management and cost allocation
    cdk.Tags.of(this).add('Project', 'TimezoneConverter');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('Owner', 'DevOps');
    cdk.Tags.of(this).add('CostCenter', 'Engineering');
  }
}

// CDK Application entry point
const app = new cdk.App();

// Create the timezone converter stack with proper naming and description
new TimezoneConverterStack(app, 'TimezoneConverterStack', {
  stackName: 'simple-timezone-converter',
  description: 'Simple Timezone Converter API using AWS Lambda and API Gateway - CDK TypeScript implementation',
  
  // Configure stack-level settings
  env: {
    // Use account and region from environment variables or CDK context
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Enable termination protection for production deployments
  terminationProtection: false, // Set to true for production environments
  
  // Configure stack tags for governance
  tags: {
    'aws-cdk:stack-type': 'serverless-api',
    'aws-cdk:description': 'Timezone converter REST API',
    'aws-cdk:version': '1.0.0'
  }
});

// Synthesize the CloudFormation template
app.synth();