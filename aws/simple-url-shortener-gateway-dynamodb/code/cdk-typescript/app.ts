#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as path from 'path';
import { AwsSolutionsChecks } from 'cdk-nag';

/**
 * Props for the UrlShortenerStack
 */  
export interface UrlShortenerStackProps extends cdk.StackProps {
  /**
   * The stage name for the API Gateway deployment
   * @default 'prod'
   */
  readonly stageName?: string;
  
  /**
   * Whether to enable CORS for the API
   * @default true
   */
  readonly enableCors?: boolean;
  
  /**
   * Billing mode for the DynamoDB table
   * @default PAY_PER_REQUEST
   */
  readonly dynamoDbBillingMode?: dynamodb.BillingMode;
}

/**
 * Stack for a serverless URL shortener using API Gateway, Lambda, and DynamoDB
 * 
 * This stack creates:
 * - DynamoDB table for storing URL mappings
 * - Lambda functions for creating short URLs and redirecting
 * - API Gateway REST API with proper endpoints
 * - IAM roles with least-privilege permissions
 */
export class UrlShortenerStack extends cdk.Stack {
  /** The DynamoDB table containing URL mappings */
  public readonly urlTable: dynamodb.Table;
  
  /** The Lambda function that creates short URLs */
  public readonly createUrlFunction: lambda.Function;
  
  /** The Lambda function that handles redirects */
  public readonly redirectFunction: lambda.Function;
  
  /** The API Gateway REST API */
  public readonly api: apigateway.RestApi;
  
  /** The API Gateway deployment stage */
  public readonly stage: apigateway.Stage;

  constructor(scope: Construct, id: string, props: UrlShortenerStackProps = {}) {
    super(scope, id, props);

    const stageName = props.stageName ?? 'prod';
    const enableCors = props.enableCors ?? true;
    const billingMode = props.dynamoDbBillingMode ?? dynamodb.BillingMode.PAY_PER_REQUEST;

    // Create DynamoDB table for URL mappings
    this.urlTable = new dynamodb.Table(this, 'UrlTable', {
      tableName: `url-shortener-${this.stackName.toLowerCase()}`,
      partitionKey: {
        name: 'shortCode',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: billingMode,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes - use RETAIN for production
      deletionProtection: false, // Set to true for production
    });

    // Tag the table for cost tracking
    cdk.Tags.of(this.urlTable).add('Project', 'URLShortener');
    cdk.Tags.of(this.urlTable).add('Component', 'Storage');

    // Create Lambda execution role
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for URL shortener Lambda functions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Grant DynamoDB permissions to Lambda role
    this.urlTable.grantReadWriteData(lambdaRole);

    // Create Lambda function for URL creation
    this.createUrlFunction = new lambda.Function(this, 'CreateUrlFunction', {
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import string
import random
import os
import logging
from urllib.parse import urlparse
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event, context):
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Parse request body
        if not event.get('body'):
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type',
                    'Access-Control-Allow-Methods': 'POST, OPTIONS'
                },
                'body': json.dumps({'error': 'Request body is required'})
            }
        
        body = json.loads(event['body'])
        original_url = body.get('url')
        
        # Validate URL presence
        if not original_url:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type',
                    'Access-Control-Allow-Methods': 'POST, OPTIONS'
                },
                'body': json.dumps({'error': 'URL is required'})
            }
        
        # Validate URL format
        try:
            parsed_url = urlparse(original_url)
            if not all([parsed_url.scheme, parsed_url.netloc]):
                return {
                    'statusCode': 400,
                    'headers': {
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*',
                        'Access-Control-Allow-Headers': 'Content-Type',
                        'Access-Control-Allow-Methods': 'POST, OPTIONS'
                    },
                    'body': json.dumps({'error': 'Invalid URL format'})
                }
        except Exception:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type',
                    'Access-Control-Allow-Methods': 'POST, OPTIONS'
                },
                'body': json.dumps({'error': 'Invalid URL format'})
            }
        
        # Generate short code (retry if collision occurs)
        max_retries = 5
        for attempt in range(max_retries):
            short_code = ''.join(random.choices(string.ascii_letters + string.digits, k=6))
            
            try:
                # Use conditional write to prevent overwriting existing codes
                table.put_item(
                    Item={
                        'shortCode': short_code,
                        'originalUrl': original_url
                    },
                    ConditionExpression='attribute_not_exists(shortCode)'
                )
                break
            except ClientError as e:
                if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
                    if attempt == max_retries - 1:
                        raise Exception("Unable to generate unique short code after multiple attempts")
                    continue
                else:
                    raise
        
        api_url = f"https://{event['requestContext']['domainName']}/{event['requestContext']['stage']}"
        
        logger.info(f"Created short URL: {short_code} -> {original_url}")
        
        return {
            'statusCode': 201,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'POST, OPTIONS'
            },
            'body': json.dumps({
                'shortCode': short_code,
                'shortUrl': f"{api_url}/{short_code}",
                'originalUrl': original_url
            })
        }
        
    except Exception as e:
        logger.error(f"Error creating short URL: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'POST, OPTIONS'
            },
            'body': json.dumps({'error': 'Internal server error'})
        }
      `),
      environment: {
        TABLE_NAME: this.urlTable.tableName,
      },
      role: lambdaRole,
      timeout: cdk.Duration.seconds(10),
      description: 'Creates short URLs and stores them in DynamoDB',
      memorySize: 256,
    });

    // Create Lambda function for URL redirection
    this.redirectFunction = new lambda.Function(this, 'RedirectFunction', {
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import os
import logging
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event, context):
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Get short code from path parameters
        if not event.get('pathParameters') or not event['pathParameters'].get('shortCode'):
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'text/html'},
                'body': '<h1>400 - Bad Request</h1><p>Short code parameter is required</p>'
            }
        
        short_code = event['pathParameters']['shortCode']
        
        # Validate short code format (basic validation)
        if not short_code or len(short_code) != 6 or not short_code.isalnum():
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'text/html'},
                'body': '<h1>400 - Bad Request</h1><p>Invalid short code format</p>'
            }
        
        # Lookup original URL in DynamoDB
        response = table.get_item(
            Key={'shortCode': short_code}
        )
        
        if 'Item' in response:
            original_url = response['Item']['originalUrl']
            logger.info(f"Redirecting {short_code} to {original_url}")
            return {
                'statusCode': 302,
                'headers': {
                    'Location': original_url,
                    'Cache-Control': 'no-cache, no-store, must-revalidate'
                }
            }
        else:
            logger.warning(f"Short code not found: {short_code}")
            return {
                'statusCode': 404,
                'headers': {'Content-Type': 'text/html'},
                'body': '<h1>404 - Short URL not found</h1><p>The requested short URL does not exist or has expired.</p>'
            }
            
    except ClientError as e:
        logger.error(f"DynamoDB error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'text/html'},
            'body': '<h1>500 - Internal Server Error</h1><p>Database error occurred</p>'
        }
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'text/html'},
            'body': '<h1>500 - Internal Server Error</h1><p>An unexpected error occurred</p>'
        }
      `),
      environment: {
        TABLE_NAME: this.urlTable.tableName,
      },
      role: lambdaRole,
      timeout: cdk.Duration.seconds(10),
      description: 'Handles URL redirects based on short codes',
      memorySize: 256,
    });

    // Create API Gateway REST API
    this.api = new apigateway.RestApi(this, 'UrlShortenerApi', {
      restApiName: `url-shortener-api-${this.stackName.toLowerCase()}`,
      description: 'Serverless URL Shortener API',
      deployOptions: {
        stageName: stageName,
        throttlingRateLimit: 100,
        throttlingBurstLimit: 200,
        tracingEnabled: true,
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        dataTraceEnabled: true,
        metricsEnabled: true,
      },
      defaultCorsPreflightOptions: enableCors ? {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key', 'X-Amz-Security-Token'],
      } : undefined,
      binaryMediaTypes: ['*/*'],
    });

    // Tag the API for cost tracking
    cdk.Tags.of(this.api).add('Project', 'URLShortener');
    cdk.Tags.of(this.api).add('Component', 'API');

    // Create /shorten resource for URL creation
    const shortenResource = this.api.root.addResource('shorten');
    
    // Add POST method to /shorten
    shortenResource.addMethod('POST', new apigateway.LambdaIntegration(this.createUrlFunction, {
      proxy: true,
      integrationResponses: [{
        statusCode: '200',
        responseParameters: {
          'method.response.header.Access-Control-Allow-Origin': "'*'",
        },
      }],
    }), {
      methodResponses: [{
        statusCode: '200',
        responseParameters: {
          'method.response.header.Access-Control-Allow-Origin': true,
        },
      }],
    });

    // Create /{shortCode} resource for redirects
    const shortCodeResource = this.api.root.addResource('{shortCode}');
    
    // Add GET method to /{shortCode}
    shortCodeResource.addMethod('GET', new apigateway.LambdaIntegration(this.redirectFunction, {
      proxy: true,
    }), {
      requestParameters: {
        'method.request.path.shortCode': true,
      },
    });

    // Store deployment stage reference
    this.stage = this.api.deploymentStage;

    // Outputs for easy access to the API endpoint
    new cdk.CfnOutput(this, 'ApiEndpoint', {
      value: this.api.url,
      description: 'API Gateway endpoint URL',
      exportName: `${this.stackName}-ApiEndpoint`,
    });

    new cdk.CfnOutput(this, 'CreateUrlEndpoint', {
      value: `${this.api.url}shorten`,
      description: 'POST endpoint for creating short URLs',
      exportName: `${this.stackName}-CreateUrlEndpoint`,
    });

    new cdk.CfnOutput(this, 'DynamoDbTableName', {
      value: this.urlTable.tableName,
      description: 'DynamoDB table name for URL mappings',
      exportName: `${this.stackName}-DynamoDbTableName`,
    });

    new cdk.CfnOutput(this, 'CreateFunctionName', {
      value: this.createUrlFunction.functionName,
      description: 'Lambda function name for URL creation',
      exportName: `${this.stackName}-CreateFunctionName`,
    });

    new cdk.CfnOutput(this, 'RedirectFunctionName', {
      value: this.redirectFunction.functionName,
      description: 'Lambda function name for URL redirection',
      exportName: `${this.stackName}-RedirectFunctionName`,
    });
  }
}

/**
 * The main CDK application
 */
const app = new cdk.App();

// Get configuration from context or use defaults
const stackName = app.node.tryGetContext('stackName') || 'UrlShortenerStack';
const stageName = app.node.tryGetContext('stageName') || 'prod';
const enableCors = app.node.tryGetContext('enableCors') !== 'false';

// Create the URL shortener stack
const urlShortenerStack = new UrlShortenerStack(app, stackName, {
  stageName,
  enableCors,
  description: 'A serverless URL shortener using API Gateway, Lambda, and DynamoDB',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

// Apply CDK Nag for security best practices validation
cdk.Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));

// Add tags to all resources in the stack
cdk.Tags.of(urlShortenerStack).add('Application', 'URLShortener');
cdk.Tags.of(urlShortenerStack).add('Environment', stageName);
cdk.Tags.of(urlShortenerStack).add('ManagedBy', 'CDK');

// Synthesize the app
app.synth();