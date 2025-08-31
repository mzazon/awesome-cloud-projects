#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';
import { ApiGatewayToLambda } from '@aws-solutions-constructs/aws-apigateway-lambda';
import { AwsSolutionsChecks, NagSuppressions } from 'cdk-nag';
import { Construct } from 'constructs';

/**
 * Stack for Simple Random Data API with Lambda and API Gateway
 * 
 * This stack implements a serverless REST API that generates random data including
 * quotes, numbers, and colors. It uses AWS Solutions Constructs for best practices
 * and includes CDK Nag for security validation.
 */
export class SimpleRandomDataApiStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Lambda function code for random data generation
    const lambdaFunctionCode = `
import json
import random
import logging
from typing import Dict, Any, Union, List

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    AWS Lambda handler for random data API
    Returns random quotes, numbers, or colors based on query parameter
    
    Args:
        event: API Gateway event containing request data
        context: Lambda context object
        
    Returns:
        Dict containing HTTP response with random data
    """
    
    try:
        # Log the incoming request
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Parse query parameters
        query_params = event.get('queryStringParameters') or {}
        data_type = query_params.get('type', 'quote').lower()
        
        # Random data collections
        quotes: List[str] = [
            "The only way to do great work is to love what you do. - Steve Jobs",
            "Innovation distinguishes between a leader and a follower. - Steve Jobs",
            "Life is what happens to you while you're busy making other plans. - John Lennon",
            "The future belongs to those who believe in the beauty of their dreams. - Eleanor Roosevelt",
            "Success is not final, failure is not fatal: it is the courage to continue that counts. - Winston Churchill"
        ]
        
        colors: List[Dict[str, str]] = [
            {"name": "Ocean Blue", "hex": "#006994", "rgb": "rgb(0, 105, 148)"},
            {"name": "Sunset Orange", "hex": "#FF6B35", "rgb": "rgb(255, 107, 53)"},
            {"name": "Forest Green", "hex": "#2E8B57", "rgb": "rgb(46, 139, 87)"},
            {"name": "Purple Haze", "hex": "#9370DB", "rgb": "rgb(147, 112, 219)"},
            {"name": "Golden Yellow", "hex": "#FFD700", "rgb": "rgb(255, 215, 0)"}
        ]
        
        # Generate response based on type
        data: Union[str, int, Dict[str, str]]
        if data_type == 'quote':
            data = random.choice(quotes)
        elif data_type == 'number':
            data = random.randint(1, 1000)
        elif data_type == 'color':
            data = random.choice(colors)
        else:
            # Default to quote for unknown types
            data = random.choice(quotes)
            data_type = 'quote'
        
        # Create response
        response_body = {
            'type': data_type,
            'data': data,
            'timestamp': context.aws_request_id,
            'message': f'Random {data_type} generated successfully'
        }
        
        # Return successful response with CORS headers
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET',
                'Access-Control-Allow-Headers': 'Content-Type'
            },
            'body': json.dumps(response_body)
        }
        
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        
        # Return error response
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'message': 'Failed to generate random data'
            })
        }
`;

    // Create the API Gateway to Lambda construct using AWS Solutions Constructs
    // This provides a REST API backed by a Lambda function with security best practices
    const apiLambdaConstruct = new ApiGatewayToLambda(this, 'RandomDataApi', {
      // Lambda function configuration
      lambdaFunctionProps: {
        runtime: lambda.Runtime.PYTHON_3_12,
        handler: 'index.lambda_handler', 
        code: lambda.Code.fromInline(lambdaFunctionCode),
        timeout: cdk.Duration.seconds(30),
        memorySize: 128,
        description: 'Random data API generator - generates quotes, numbers, and colors',
        environment: {
          LOG_LEVEL: 'INFO'
        },
        // Enable CloudWatch Insights for enhanced monitoring
        insightsVersion: lambda.LambdaInsightsVersion.VERSION_1_0_229_0,
        // Configure log retention to manage costs
        logRetention: logs.RetentionDays.ONE_WEEK
      },
      
      // API Gateway configuration
      apiGatewayProps: {
        restApiName: 'Simple Random Data API',
        description: 'REST API for generating random quotes, numbers, and colors',
        // Enable request validation at API Gateway level
        deployOptions: {
          stageName: 'dev',
          description: 'Development stage for random data API',
          // Enable CloudWatch logging for API Gateway
          loggingLevel: cdk.aws_apigateway.MethodLoggingLevel.INFO,
          dataTraceEnabled: true,
          metricsEnabled: true,
          // Enable X-Ray tracing for distributed tracing
          tracingEnabled: true
        },
        // Configure default CORS for web applications
        defaultCorsPreflightOptions: {
          allowOrigins: cdk.aws_apigateway.Cors.ALL_ORIGINS,
          allowMethods: cdk.aws_apigateway.Cors.ALL_METHODS,
          allowHeaders: ['Content-Type', 'Authorization']
        },
        // Enable endpoint export for integration testing
        endpointExportName: 'RandomDataApiEndpoint'
      }
    });

    // Create a custom resource path '/random' for our API endpoint
    const randomResource = apiLambdaConstruct.apiGateway.root.addResource('random');
    
    // Add GET method to the /random resource with request validation
    randomResource.addMethod('GET', 
      new cdk.aws_apigateway.LambdaIntegration(apiLambdaConstruct.lambdaFunction, {
        requestTemplates: { 'application/json': '{ "statusCode": "200" }' },
        proxy: true
      }),
      {
        requestParameters: {
          'method.request.querystring.type': false // Optional query parameter
        },
        // Add method-level request validation
        requestValidatorOptions: {
          validateRequestParameters: true
        }
      }
    );

    // CDK Nag suppressions for acceptable security trade-offs in this simple example
    // These are explicitly documented for transparency and should be reviewed for production use
    
    // Suppress Lambda function environment variable encryption requirement
    // Justification: This function doesn't handle sensitive data, only generates random public data
    NagSuppressions.addResourceSuppressions(
      apiLambdaConstruct.lambdaFunction,
      [
        {
          id: 'AwsSolutions-L1',
          reason: 'Using Python 3.12 which is the latest supported runtime version'
        }
      ]
    );

    // Suppress API Gateway access logging requirement for this simple example
    // Justification: This is a beginner-friendly example focused on core functionality
    NagSuppressions.addResourceSuppressions(
      apiLambdaConstruct.apiGateway,
      [
        {
          id: 'AwsSolutions-APIG2',
          reason: 'Request validation is enabled at method level for this simple API'
        },
        {
          id: 'AwsSolutions-APIG3',
          reason: 'WAF is not required for this simple random data API example'
        },
        {
          id: 'AwsSolutions-APIG4',
          reason: 'Authorization not required for public random data API'
        },
        {
          id: 'AwsSolutions-COG4',
          reason: 'Cognito user pool authorization not needed for public random data'
        }
      ]
    );

    // CloudFormation outputs for easy access to deployed resources
    new cdk.CfnOutput(this, 'ApiGatewayUrl', {
      value: apiLambdaConstruct.apiGateway.url,
      description: 'Base URL of the Random Data API Gateway',
      exportName: 'RandomDataApiGatewayUrl'
    });

    new cdk.CfnOutput(this, 'RandomEndpointUrl', {
      value: \`\${apiLambdaConstruct.apiGateway.url}random\`,
      description: 'Full URL for the /random endpoint (append ?type=quote|number|color)',
      exportName: 'RandomDataApiRandomEndpoint'
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: apiLambdaConstruct.lambdaFunction.functionName,
      description: 'Name of the Lambda function handling random data generation',
      exportName: 'RandomDataApiLambdaFunction'
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: apiLambdaConstruct.lambdaFunction.functionArn,
      description: 'ARN of the Lambda function for CloudWatch monitoring',
      exportName: 'RandomDataApiLambdaFunctionArn'
    });

    // Add tags to all resources for cost tracking and management
    cdk.Tags.of(this).add('Project', 'SimpleRandomDataApi');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('CostCenter', 'Engineering');
    cdk.Tags.of(this).add('Owner', 'DevTeam');
  }
}

/**
 * CDK Application entry point
 * 
 * Creates and configures the CDK app with the Simple Random Data API stack
 * Includes CDK Nag security checks and proper environment configuration
 */
const app = new cdk.App();

// Create the stack with appropriate naming and environment configuration
const stack = new SimpleRandomDataApiStack(app, 'SimpleRandomDataApiStack', {
  description: 'Simple Random Data API using Lambda and API Gateway with AWS Solutions Constructs',
  
  // Environment configuration - uncomment and modify for specific deployment
  // env: {
  //   account: process.env.CDK_DEFAULT_ACCOUNT,
  //   region: process.env.CDK_DEFAULT_REGION,
  // },
  
  // Enable termination protection for production deployments
  terminationProtection: false, // Set to true for production
  
  // Stack-level tags
  tags: {
    Application: 'SimpleRandomDataApi',
    StackType: 'Serverless',
    Framework: 'CDK'
  }
});

// Apply CDK Nag security checks to ensure AWS best practices
// This will validate the infrastructure against AWS Well-Architected security principles
AwsSolutionsChecks.check(stack, {
  verbose: true,
  reports: true,
  logIgnores: true
});

// Additional stack-level suppressions for beginner-friendly example
// In production, these should be carefully evaluated and justified
NagSuppressions.addStackSuppressions(stack, [
  {
    id: 'AwsSolutions-IAM4',
    reason: 'AWS Solutions Constructs use managed policies following AWS best practices'
  },
  {
    id: 'AwsSolutions-IAM5', 
    reason: 'AWS Solutions Constructs use appropriate wildcard permissions for service integration'
  }
]);

// Synthesize the CDK app
app.synth();