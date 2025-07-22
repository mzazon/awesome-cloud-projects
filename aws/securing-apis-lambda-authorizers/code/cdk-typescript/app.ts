#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * CDK Stack for Serverless API Patterns with Lambda Authorizers and API Gateway
 * 
 * This stack demonstrates comprehensive serverless API security using AWS API Gateway 
 * with custom Lambda authorizers to create flexible authentication and authorization patterns.
 * 
 * Features:
 * - Token-based Lambda authorizer for JWT validation
 * - Request-based Lambda authorizer for custom business logic
 * - Protected and public API endpoints
 * - Comprehensive authorization caching
 * - CloudWatch logging and monitoring
 */
export class ServerlessApiPatternsStack extends cdk.Stack {
  
  public readonly apiUrl: string;
  public readonly tokenAuthorizerFunction: lambda.Function;
  public readonly requestAuthorizerFunction: lambda.Function;
  public readonly protectedApiFunction: lambda.Function;
  public readonly publicApiFunction: lambda.Function;
  public readonly restApi: apigateway.RestApi;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create IAM role for Lambda functions with enhanced permissions
    const lambdaExecutionRole = new iam.Role(this, 'LambdaExecutionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for Lambda functions with API Gateway authorizers',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        CloudWatchLogs: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
                'logs:DescribeLogStreams'
              ],
              resources: ['arn:aws:logs:*:*:*']
            })
          ]
        })
      }
    });

    // Token-based Lambda Authorizer Function
    this.tokenAuthorizerFunction = new lambda.Function(this, 'TokenAuthorizerFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      description: 'Token-based authorizer that validates Bearer tokens',
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      logRetention: logs.RetentionDays.ONE_WEEK,
      environment: {
        LOG_LEVEL: 'INFO'
      },
      code: lambda.Code.fromInline(`
import json
import re
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Token-based authorizer that validates Bearer tokens
    """
    logger.info(f"Token Authorizer Event: {json.dumps(event, default=str)}")
    
    try:
        # Extract token from event
        token = event.get('authorizationToken', '')
        method_arn = event.get('methodArn', '')
        
        # Validate token format (Bearer <token>)
        if not token.startswith('Bearer '):
            logger.warning("Invalid token format - must start with 'Bearer '")
            raise Exception('Unauthorized')
        
        # Extract actual token
        actual_token = token.replace('Bearer ', '')
        
        # Validate token (simplified validation for demo)
        # In production, validate JWT signature, expiration, etc.
        valid_tokens = {
            'admin-token': {
                'principalId': 'admin-user',
                'effect': 'Allow',
                'context': {
                    'role': 'admin',
                    'permissions': 'read,write,delete',
                    'authType': 'token'
                }
            },
            'user-token': {
                'principalId': 'regular-user', 
                'effect': 'Allow',
                'context': {
                    'role': 'user',
                    'permissions': 'read',
                    'authType': 'token'
                }
            }
        }
        
        # Check if token is valid
        if actual_token not in valid_tokens:
            logger.warning(f"Invalid token: {actual_token}")
            raise Exception('Unauthorized')
        
        token_info = valid_tokens[actual_token]
        
        # Generate policy
        policy = generate_policy(
            token_info['principalId'],
            token_info['effect'],
            method_arn,
            token_info['context']
        )
        
        logger.info(f"Generated Policy for {token_info['principalId']}: Allow")
        return policy
        
    except Exception as e:
        logger.error(f"Authorization failed: {str(e)}")
        raise Exception('Unauthorized')

def generate_policy(principal_id, effect, resource, context=None):
    """Generate IAM policy for API Gateway"""
    policy = {
        'principalId': principal_id,
        'policyDocument': {
            'Version': '2012-10-17',
            'Statement': [
                {
                    'Action': 'execute-api:Invoke',
                    'Effect': effect,
                    'Resource': resource
                }
            ]
        }
    }
    
    # Add context for passing additional information
    if context:
        policy['context'] = context
        
    return policy
      `)
    });

    // Request-based Lambda Authorizer Function
    this.requestAuthorizerFunction = new lambda.Function(this, 'RequestAuthorizerFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      description: 'Request-based authorizer that validates based on request context',
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      logRetention: logs.RetentionDays.ONE_WEEK,
      environment: {
        LOG_LEVEL: 'INFO'
      },
      code: lambda.Code.fromInline(`
import json
import logging
from urllib.parse import parse_qs

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Request-based authorizer that validates based on request context
    """
    logger.info(f"Request Authorizer Event: {json.dumps(event, default=str)}")
    
    try:
        # Extract request details
        headers = event.get('headers', {})
        query_params = event.get('queryStringParameters', {}) or {}
        method_arn = event.get('methodArn', '')
        source_ip = event.get('requestContext', {}).get('identity', {}).get('sourceIp', '')
        
        # Check for API key in query parameters
        api_key = query_params.get('api_key', '')
        
        # Check for custom authentication header
        custom_auth = headers.get('X-Custom-Auth', '')
        
        # Validate based on multiple criteria
        principal_id = 'unknown'
        effect = 'Deny'
        context = {}
        
        # API Key validation
        if api_key == 'secret-api-key-123':
            principal_id = 'api-key-user'
            effect = 'Allow'
            context = {
                'authType': 'api-key',
                'sourceIp': source_ip,
                'permissions': 'read,write'
            }
            logger.info(f"API key authentication successful for IP: {source_ip}")
        # Custom header validation
        elif custom_auth == 'custom-auth-value':
            principal_id = 'custom-user'
            effect = 'Allow'
            context = {
                'authType': 'custom-header',
                'sourceIp': source_ip,
                'permissions': 'read'
            }
            logger.info(f"Custom header authentication successful for IP: {source_ip}")
        # IP-based validation (example for internal networks)
        elif source_ip.startswith('10.') or source_ip.startswith('172.') or source_ip.startswith('192.168.'):
            principal_id = 'internal-user'
            effect = 'Allow'
            context = {
                'authType': 'ip-whitelist',
                'sourceIp': source_ip,
                'permissions': 'read,write,delete'
            }
            logger.info(f"IP whitelist authentication successful for IP: {source_ip}")
        else:
            logger.warning(f"No valid authentication method found for IP: {source_ip}")
        
        # Generate policy
        policy = generate_policy(principal_id, effect, method_arn, context)
        
        logger.info(f"Generated Policy for {principal_id}: {effect}")
        return policy
        
    except Exception as e:
        logger.error(f"Authorization failed: {str(e)}")
        raise Exception('Unauthorized')

def generate_policy(principal_id, effect, resource, context=None):
    """Generate IAM policy for API Gateway"""
    policy = {
        'principalId': principal_id,
        'policyDocument': {
            'Version': '2012-10-17',
            'Statement': [
                {
                    'Action': 'execute-api:Invoke',
                    'Effect': effect,
                    'Resource': resource
                }
            ]
        }
    }
    
    if context:
        policy['context'] = context
        
    return policy
      `)
    });

    // Protected API Lambda Function
    this.protectedApiFunction = new lambda.Function(this, 'ProtectedApiFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      description: 'Protected API that requires authorization',
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      logRetention: logs.RetentionDays.ONE_WEEK,
      environment: {
        LOG_LEVEL: 'INFO'
      },
      code: lambda.Code.fromInline(`
import json
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Protected API that requires authorization"""
    
    logger.info(f"Protected API called with event: {json.dumps(event, default=str)}")
    
    try:
        # Extract authorization context
        auth_context = event.get('requestContext', {}).get('authorizer', {})
        principal_id = auth_context.get('principalId', 'unknown')
        
        # Get additional context passed from authorizer
        role = auth_context.get('role', 'unknown')
        permissions = auth_context.get('permissions', 'none')
        auth_type = auth_context.get('authType', 'token')
        source_ip = auth_context.get('sourceIp', 'unknown')
        
        logger.info(f"Authorized request from {principal_id} with role {role}")
        
        response_data = {
            'message': 'Access granted to protected resource',
            'user': {
                'principalId': principal_id,
                'role': role,
                'permissions': permissions.split(',') if permissions != 'none' else [],
                'authType': auth_type,
                'sourceIp': source_ip
            },
            'timestamp': context.aws_request_id,
            'protected_data': {
                'secret_value': 'This is confidential information',
                'access_level': role,
                'data_classification': 'RESTRICTED'
            }
        }
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'X-Request-ID': context.aws_request_id
            },
            'body': json.dumps(response_data, indent=2)
        }
        
    except Exception as e:
        logger.error(f"Error processing protected API request: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'message': 'An error occurred processing your request'
            })
        }
      `)
    });

    // Public API Lambda Function
    this.publicApiFunction = new lambda.Function(this, 'PublicApiFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      description: 'Public API that does not require authorization',
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      logRetention: logs.RetentionDays.ONE_WEEK,
      environment: {
        LOG_LEVEL: 'INFO'
      },
      code: lambda.Code.fromInline(`
import json
import time
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Public API that doesn't require authorization"""
    
    logger.info(f"Public API called with event: {json.dumps(event, default=str)}")
    
    try:
        response_data = {
            'message': 'Welcome to the public API',
            'status': 'operational',
            'timestamp': int(time.time()),
            'request_id': context.aws_request_id,
            'public_data': {
                'api_version': '1.0',
                'service_name': 'Serverless API Patterns Demo',
                'available_endpoints': [
                    '/public - Public endpoint (no auth required)',
                    '/protected - Protected endpoint (requires Bearer token)',
                    '/protected/admin - Admin endpoint (requires API key or custom header)'
                ],
                'documentation': 'https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-lambda-authorizer.html'
            }
        }
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'X-Request-ID': context.aws_request_id,
                'Cache-Control': 'max-age=300'
            },
            'body': json.dumps(response_data, indent=2)
        }
        
    except Exception as e:
        logger.error(f"Error processing public API request: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'message': 'An error occurred processing your request'
            })
        }
      `)
    });

    // Create REST API Gateway
    this.restApi = new apigateway.RestApi(this, 'ServerlessApiPatternsApi', {
      restApiName: 'Serverless API Patterns Demo',
      description: 'Comprehensive serverless API security using Lambda authorizers',
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key', 'X-Custom-Auth']
      },
      cloudWatchRole: true,
      deployOptions: {
        stageName: 'prod',
        description: 'Production stage with comprehensive logging',
        tracingEnabled: true,
        dataTraceEnabled: true,
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        metricsEnabled: true,
        throttlingBurstLimit: 500,
        throttlingRateLimit: 100
      },
      policy: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            principals: [new iam.AnyPrincipal()],
            actions: ['execute-api:Invoke'],
            resources: ['*']
          })
        ]
      })
    });

    // Create Token-based Authorizer
    const tokenAuthorizer = new apigateway.TokenAuthorizer(this, 'TokenAuthorizer', {
      handler: this.tokenAuthorizerFunction,
      identitySource: 'method.request.header.Authorization',
      authorizerName: 'TokenAuthorizer',
      resultsCacheTtl: cdk.Duration.minutes(5)
    });

    // Create Request-based Authorizer
    const requestAuthorizer = new apigateway.RequestAuthorizer(this, 'RequestAuthorizer', {
      handler: this.requestAuthorizerFunction,
      identitySources: [
        'method.request.header.X-Custom-Auth',
        'method.request.querystring.api_key'
      ],
      authorizerName: 'RequestAuthorizer',
      resultsCacheTtl: cdk.Duration.minutes(5)
    });

    // Create API resources and methods

    // Public resource (no authorization)
    const publicResource = this.restApi.root.addResource('public');
    const publicIntegration = new apigateway.LambdaIntegration(this.publicApiFunction, {
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

    publicResource.addMethod('GET', publicIntegration, {
      authorizationType: apigateway.AuthorizationType.NONE,
      methodResponses: [
        {
          statusCode: '200',
          responseModels: {
            'application/json': apigateway.Model.EMPTY_MODEL
          }
        }
      ]
    });

    // Protected resource (token authorization)
    const protectedResource = this.restApi.root.addResource('protected');
    const protectedIntegration = new apigateway.LambdaIntegration(this.protectedApiFunction, {
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

    protectedResource.addMethod('GET', protectedIntegration, {
      authorizationType: apigateway.AuthorizationType.CUSTOM,
      authorizer: tokenAuthorizer,
      methodResponses: [
        {
          statusCode: '200',
          responseModels: {
            'application/json': apigateway.Model.EMPTY_MODEL
          }
        }
      ]
    });

    // Admin resource (request authorization)
    const adminResource = protectedResource.addResource('admin');
    const adminIntegration = new apigateway.LambdaIntegration(this.protectedApiFunction, {
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

    adminResource.addMethod('GET', adminIntegration, {
      authorizationType: apigateway.AuthorizationType.CUSTOM,
      authorizer: requestAuthorizer,
      methodResponses: [
        {
          statusCode: '200',
          responseModels: {
            'application/json': apigateway.Model.EMPTY_MODEL
          }
        }
      ]
    });

    // Store the API URL for output
    this.apiUrl = this.restApi.url;

    // CloudFormation Outputs
    new cdk.CfnOutput(this, 'ApiGatewayUrl', {
      value: this.apiUrl,
      description: 'URL of the API Gateway REST API',
      exportName: `${this.stackName}-ApiUrl`
    });

    new cdk.CfnOutput(this, 'PublicEndpoint', {
      value: `${this.apiUrl}public`,
      description: 'Public endpoint (no authorization required)'
    });

    new cdk.CfnOutput(this, 'ProtectedEndpoint', {
      value: `${this.apiUrl}protected`,
      description: 'Protected endpoint (requires Bearer token)'
    });

    new cdk.CfnOutput(this, 'AdminEndpoint', {
      value: `${this.apiUrl}protected/admin`,
      description: 'Admin endpoint (requires API key or custom header)'
    });

    new cdk.CfnOutput(this, 'TokenAuthorizerFunction', {
      value: this.tokenAuthorizerFunction.functionName,
      description: 'Token-based Lambda authorizer function name'
    });

    new cdk.CfnOutput(this, 'RequestAuthorizerFunction', {
      value: this.requestAuthorizerFunction.functionName,
      description: 'Request-based Lambda authorizer function name'
    });

    new cdk.CfnOutput(this, 'TestCommands', {
      value: [
        `# Test public endpoint:`,
        `curl "${this.apiUrl}public"`,
        ``,
        `# Test protected endpoint with user token:`,
        `curl -H "Authorization: Bearer user-token" "${this.apiUrl}protected"`,
        ``,
        `# Test protected endpoint with admin token:`,
        `curl -H "Authorization: Bearer admin-token" "${this.apiUrl}protected"`,
        ``,
        `# Test admin endpoint with API key:`,
        `curl "${this.apiUrl}protected/admin?api_key=secret-api-key-123"`,
        ``,
        `# Test admin endpoint with custom header:`,
        `curl -H "X-Custom-Auth: custom-auth-value" "${this.apiUrl}protected/admin"`
      ].join('\\n'),
      description: 'Sample curl commands to test the API'
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'ServerlessApiPatterns');
    cdk.Tags.of(this).add('Purpose', 'Lambda Authorizers Demo');
    cdk.Tags.of(this).add('Environment', 'Demo');
  }
}

// CDK App
const app = new cdk.App();

new ServerlessApiPatternsStack(app, 'ServerlessApiPatternsStack', {
  description: 'Serverless API Patterns with Lambda Authorizers and API Gateway (uksb-1tupboc57)',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    'CDK': 'v2',
    'Recipe': 'serverless-api-patterns-lambda-authorizers-api-gateway'
  }
});

app.synth();