#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Props for the ServerlessApiStack
 */
interface ServerlessApiStackProps extends cdk.StackProps {
  /**
   * Environment prefix for resource naming
   * @default 'dev'
   */
  readonly environmentName?: string;
  
  /**
   * DynamoDB table name
   * @default 'users-table'
   */
  readonly tableName?: string;
  
  /**
   * Lambda function timeout in seconds
   * @default 30
   */
  readonly lambdaTimeout?: number;
  
  /**
   * Lambda function memory size in MB
   * @default 128
   */
  readonly lambdaMemorySize?: number;
  
  /**
   * API Gateway stage name
   * @default 'dev'
   */
  readonly stageName?: string;
  
  /**
   * Enable CORS for API Gateway
   * @default true
   */
  readonly enableCors?: boolean;
  
  /**
   * Enable API Gateway logging
   * @default true
   */
  readonly enableApiLogging?: boolean;
}

/**
 * CDK Stack for Serverless API Development with API Gateway, Lambda, and DynamoDB
 * 
 * This stack creates a complete serverless API with the following components:
 * - DynamoDB table for user data storage
 * - Lambda functions for CRUD operations
 * - API Gateway REST API with proper routing
 * - CloudWatch logs and monitoring
 * - Proper IAM roles and policies
 */
export class ServerlessApiStack extends cdk.Stack {
  
  /** DynamoDB table for storing user data */
  public readonly usersTable: dynamodb.Table;
  
  /** API Gateway REST API */
  public readonly api: apigateway.RestApi;
  
  /** Lambda functions for API operations */
  public readonly lambdaFunctions: { [key: string]: lambda.Function };
  
  /** CloudWatch log groups for Lambda functions */
  public readonly logGroups: { [key: string]: logs.LogGroup };

  constructor(scope: Construct, id: string, props?: ServerlessApiStackProps) {
    super(scope, id, props);

    // Extract props with defaults
    const environmentName = props?.environmentName || 'dev';
    const tableName = props?.tableName || 'users-table';
    const lambdaTimeout = props?.lambdaTimeout || 30;
    const lambdaMemorySize = props?.lambdaMemorySize || 128;
    const stageName = props?.stageName || 'dev';
    const enableCors = props?.enableCors !== false;
    const enableApiLogging = props?.enableApiLogging !== false;

    // Create DynamoDB table for users
    this.usersTable = new dynamodb.Table(this, 'UsersTable', {
      tableName: `${this.stackName}-${tableName}`,
      partitionKey: {
        name: 'id',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Use RETAIN for production
      pointInTimeRecovery: true,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      tags: {
        Environment: environmentName,
        Application: 'ServerlessAPI',
        ManagedBy: 'CDK',
      },
    });

    // Create IAM role for Lambda functions
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        DynamoDBAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:GetItem',
                'dynamodb:PutItem',
                'dynamodb:UpdateItem',
                'dynamodb:DeleteItem',
                'dynamodb:Scan',
                'dynamodb:Query',
              ],
              resources: [this.usersTable.tableArn],
            }),
          ],
        }),
      },
    });

    // Lambda function code for shared utilities
    const sharedUtilitiesCode = `
import json
import boto3
from botocore.exceptions import ClientError

dynamodb = boto3.resource('dynamodb')

def get_table():
    import os
    table_name = os.environ.get('DYNAMODB_TABLE')
    return dynamodb.Table(table_name)

def create_response(status_code, body, headers=None):
    default_headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
    }
    
    if headers:
        default_headers.update(headers)
    
    return {
        'statusCode': status_code,
        'headers': default_headers,
        'body': json.dumps(body) if isinstance(body, (dict, list)) else body
    }

def handle_dynamodb_error(error):
    if error.response['Error']['Code'] == 'ResourceNotFoundException':
        return create_response(404, {'error': 'Resource not found'})
    else:
        return create_response(500, {'error': 'Internal server error'})
`;

    // Create Lambda functions for each API operation
    this.lambdaFunctions = {};
    this.logGroups = {};

    // List Users Function (GET /users)
    this.logGroups['listUsers'] = new logs.LogGroup(this, 'ListUsersLogGroup', {
      logGroupName: `/aws/lambda/${this.stackName}-list-users`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    this.lambdaFunctions['listUsers'] = new lambda.Function(this, 'ListUsersFunction', {
      functionName: `${this.stackName}-list-users`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(lambdaTimeout),
      memorySize: lambdaMemorySize,
      logGroup: this.logGroups['listUsers'],
      environment: {
        DYNAMODB_TABLE: this.usersTable.tableName,
        CORS_ALLOW_ORIGIN: '*',
      },
      code: lambda.Code.fromInline(`
${sharedUtilitiesCode}

def lambda_handler(event, context):
    try:
        table = get_table()
        
        # Scan table for all users
        response = table.scan()
        users = response.get('Items', [])
        
        # Handle pagination if needed
        while 'LastEvaluatedKey' in response:
            response = table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
            users.extend(response.get('Items', []))
        
        return create_response(200, users)
        
    except ClientError as e:
        return handle_dynamodb_error(e)
    except Exception as e:
        return create_response(500, {'error': str(e)})
`),
    });

    // Create User Function (POST /users)
    this.logGroups['createUser'] = new logs.LogGroup(this, 'CreateUserLogGroup', {
      logGroupName: `/aws/lambda/${this.stackName}-create-user`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    this.lambdaFunctions['createUser'] = new lambda.Function(this, 'CreateUserFunction', {
      functionName: `${this.stackName}-create-user`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(lambdaTimeout),
      memorySize: lambdaMemorySize,
      logGroup: this.logGroups['createUser'],
      environment: {
        DYNAMODB_TABLE: this.usersTable.tableName,
        CORS_ALLOW_ORIGIN: '*',
      },
      code: lambda.Code.fromInline(`
import uuid
from datetime import datetime
${sharedUtilitiesCode}

def lambda_handler(event, context):
    try:
        # Parse request body
        body = json.loads(event.get('body', '{}'))
        
        # Validate required fields
        if not body.get('name') or not body.get('email'):
            return create_response(400, {'error': 'Name and email are required'})
        
        # Generate user ID and timestamp
        user_id = str(uuid.uuid4())
        timestamp = datetime.utcnow().isoformat()
        
        # Create user item
        user_item = {
            'id': user_id,
            'name': body['name'],
            'email': body['email'],
            'created_at': timestamp,
            'updated_at': timestamp
        }
        
        # Optional fields
        if body.get('age'):
            user_item['age'] = int(body['age'])
        
        # Put item in DynamoDB
        table = get_table()
        table.put_item(Item=user_item)
        
        return create_response(201, user_item)
        
    except ClientError as e:
        return handle_dynamodb_error(e)
    except ValueError as e:
        return create_response(400, {'error': 'Invalid JSON in request body'})
    except Exception as e:
        return create_response(500, {'error': str(e)})
`),
    });

    // Get User Function (GET /users/{id})
    this.logGroups['getUser'] = new logs.LogGroup(this, 'GetUserLogGroup', {
      logGroupName: `/aws/lambda/${this.stackName}-get-user`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    this.lambdaFunctions['getUser'] = new lambda.Function(this, 'GetUserFunction', {
      functionName: `${this.stackName}-get-user`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(lambdaTimeout),
      memorySize: lambdaMemorySize,
      logGroup: this.logGroups['getUser'],
      environment: {
        DYNAMODB_TABLE: this.usersTable.tableName,
        CORS_ALLOW_ORIGIN: '*',
      },
      code: lambda.Code.fromInline(`
${sharedUtilitiesCode}

def lambda_handler(event, context):
    try:
        # Get user ID from path parameters
        user_id = event['pathParameters']['id']
        
        # Get item from DynamoDB
        table = get_table()
        response = table.get_item(Key={'id': user_id})
        
        if 'Item' not in response:
            return create_response(404, {'error': 'User not found'})
        
        return create_response(200, response['Item'])
        
    except ClientError as e:
        return handle_dynamodb_error(e)
    except Exception as e:
        return create_response(500, {'error': str(e)})
`),
    });

    // Update User Function (PUT /users/{id})
    this.logGroups['updateUser'] = new logs.LogGroup(this, 'UpdateUserLogGroup', {
      logGroupName: `/aws/lambda/${this.stackName}-update-user`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    this.lambdaFunctions['updateUser'] = new lambda.Function(this, 'UpdateUserFunction', {
      functionName: `${this.stackName}-update-user`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(lambdaTimeout),
      memorySize: lambdaMemorySize,
      logGroup: this.logGroups['updateUser'],
      environment: {
        DYNAMODB_TABLE: this.usersTable.tableName,
        CORS_ALLOW_ORIGIN: '*',
      },
      code: lambda.Code.fromInline(`
from datetime import datetime
${sharedUtilitiesCode}

def lambda_handler(event, context):
    try:
        # Get user ID from path parameters
        user_id = event['pathParameters']['id']
        
        # Parse request body
        body = json.loads(event.get('body', '{}'))
        
        # Check if user exists
        table = get_table()
        response = table.get_item(Key={'id': user_id})
        
        if 'Item' not in response:
            return create_response(404, {'error': 'User not found'})
        
        # Build update expression
        update_expression = "SET updated_at = :timestamp"
        expression_values = {':timestamp': datetime.utcnow().isoformat()}
        expression_names = {}
        
        if body.get('name'):
            update_expression += ", #name = :name"
            expression_values[':name'] = body['name']
            expression_names['#name'] = 'name'
        
        if body.get('email'):
            update_expression += ", email = :email"
            expression_values[':email'] = body['email']
        
        if body.get('age'):
            update_expression += ", age = :age"
            expression_values[':age'] = int(body['age'])
        
        # Update item
        update_kwargs = {
            'Key': {'id': user_id},
            'UpdateExpression': update_expression,
            'ExpressionAttributeValues': expression_values,
            'ReturnValues': 'ALL_NEW'
        }
        
        if expression_names:
            update_kwargs['ExpressionAttributeNames'] = expression_names
        
        response = table.update_item(**update_kwargs)
        
        return create_response(200, response['Attributes'])
        
    except ClientError as e:
        return handle_dynamodb_error(e)
    except ValueError as e:
        return create_response(400, {'error': 'Invalid JSON in request body'})
    except Exception as e:
        return create_response(500, {'error': str(e)})
`),
    });

    // Delete User Function (DELETE /users/{id})
    this.logGroups['deleteUser'] = new logs.LogGroup(this, 'DeleteUserLogGroup', {
      logGroupName: `/aws/lambda/${this.stackName}-delete-user`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    this.lambdaFunctions['deleteUser'] = new lambda.Function(this, 'DeleteUserFunction', {
      functionName: `${this.stackName}-delete-user`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(lambdaTimeout),
      memorySize: lambdaMemorySize,
      logGroup: this.logGroups['deleteUser'],
      environment: {
        DYNAMODB_TABLE: this.usersTable.tableName,
        CORS_ALLOW_ORIGIN: '*',
      },
      code: lambda.Code.fromInline(`
${sharedUtilitiesCode}

def lambda_handler(event, context):
    try:
        # Get user ID from path parameters
        user_id = event['pathParameters']['id']
        
        # Check if user exists
        table = get_table()
        response = table.get_item(Key={'id': user_id})
        
        if 'Item' not in response:
            return create_response(404, {'error': 'User not found'})
        
        # Delete item
        table.delete_item(Key={'id': user_id})
        
        return create_response(204, '')
        
    except ClientError as e:
        return handle_dynamodb_error(e)
    except Exception as e:
        return create_response(500, {'error': str(e)})
`),
    });

    // Create API Gateway
    const apiGatewayLogGroup = new logs.LogGroup(this, 'ApiGatewayLogGroup', {
      logGroupName: `/aws/apigateway/${this.stackName}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    this.api = new apigateway.RestApi(this, 'UsersApi', {
      restApiName: `${this.stackName}-users-api`,
      description: 'Serverless API for user management with Lambda and DynamoDB',
      deployOptions: {
        stageName: stageName,
        accessLogDestination: enableApiLogging ? new apigateway.LogGroupLogDestination(apiGatewayLogGroup) : undefined,
        accessLogFormat: enableApiLogging ? apigateway.AccessLogFormat.jsonWithStandardFields({
          caller: true,
          httpMethod: true,
          ip: true,
          protocol: true,
          requestTime: true,
          resourcePath: true,
          responseLength: true,
          status: true,
          user: true,
        }) : undefined,
        loggingLevel: enableApiLogging ? apigateway.MethodLoggingLevel.INFO : apigateway.MethodLoggingLevel.OFF,
        dataTraceEnabled: enableApiLogging,
        metricsEnabled: true,
      },
      defaultCorsPreflightOptions: enableCors ? {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: [
          'Content-Type',
          'X-Amz-Date',
          'Authorization',
          'X-Api-Key',
          'X-Amz-Security-Token',
        ],
      } : undefined,
      endpointConfiguration: {
        types: [apigateway.EndpointType.REGIONAL],
      },
    });

    // Create API Gateway resources and methods
    const usersResource = this.api.root.addResource('users');

    // GET /users - List all users
    usersResource.addMethod('GET', new apigateway.LambdaIntegration(this.lambdaFunctions['listUsers'], {
      requestTemplates: { 'application/json': '{ "statusCode": "200" }' },
    }), {
      methodResponses: [
        {
          statusCode: '200',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
        {
          statusCode: '500',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
      ],
    });

    // POST /users - Create new user
    usersResource.addMethod('POST', new apigateway.LambdaIntegration(this.lambdaFunctions['createUser']), {
      methodResponses: [
        {
          statusCode: '201',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
        {
          statusCode: '400',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
        {
          statusCode: '500',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
      ],
    });

    // Create {id} resource for individual user operations
    const userIdResource = usersResource.addResource('{id}');

    // GET /users/{id} - Get specific user
    userIdResource.addMethod('GET', new apigateway.LambdaIntegration(this.lambdaFunctions['getUser']), {
      requestParameters: {
        'method.request.path.id': true,
      },
      methodResponses: [
        {
          statusCode: '200',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
        {
          statusCode: '404',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
        {
          statusCode: '500',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
      ],
    });

    // PUT /users/{id} - Update user
    userIdResource.addMethod('PUT', new apigateway.LambdaIntegration(this.lambdaFunctions['updateUser']), {
      requestParameters: {
        'method.request.path.id': true,
      },
      methodResponses: [
        {
          statusCode: '200',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
        {
          statusCode: '400',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
        {
          statusCode: '404',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
        {
          statusCode: '500',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
      ],
    });

    // DELETE /users/{id} - Delete user
    userIdResource.addMethod('DELETE', new apigateway.LambdaIntegration(this.lambdaFunctions['deleteUser']), {
      requestParameters: {
        'method.request.path.id': true,
      },
      methodResponses: [
        {
          statusCode: '204',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
        {
          statusCode: '404',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
        {
          statusCode: '500',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
      ],
    });

    // Stack Outputs
    new cdk.CfnOutput(this, 'ApiGatewayUrl', {
      value: this.api.url,
      description: 'API Gateway endpoint URL for the serverless users API',
      exportName: `${this.stackName}-ApiUrl`,
    });

    new cdk.CfnOutput(this, 'UsersTableName', {
      value: this.usersTable.tableName,
      description: 'DynamoDB table name for user data storage',
      exportName: `${this.stackName}-TableName`,
    });

    new cdk.CfnOutput(this, 'UsersTableArn', {
      value: this.usersTable.tableArn,
      description: 'DynamoDB table ARN for user data storage',
      exportName: `${this.stackName}-TableArn`,
    });

    new cdk.CfnOutput(this, 'ApiGatewayId', {
      value: this.api.restApiId,
      description: 'API Gateway REST API ID',
      exportName: `${this.stackName}-ApiId`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionNames', {
      value: Object.values(this.lambdaFunctions).map(func => func.functionName).join(', '),
      description: 'Lambda function names for API operations',
      exportName: `${this.stackName}-LambdaFunctions`,
    });

    // Add tags to all resources in the stack
    cdk.Tags.of(this).add('Environment', environmentName);
    cdk.Tags.of(this).add('Application', 'ServerlessAPI');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
    cdk.Tags.of(this).add('Stack', this.stackName);
  }
}

/**
 * Main CDK App
 */
const app = new cdk.App();

// Get context values for stack configuration
const environmentName = app.node.tryGetContext('environmentName') || 'dev';
const stackName = app.node.tryGetContext('stackName') || `serverless-api-${environmentName}`;

// Create the main stack
new ServerlessApiStack(app, 'ServerlessApiStack', {
  stackName: stackName,
  description: 'Serverless API Development with SAM and API Gateway - CDK TypeScript implementation',
  environmentName: environmentName,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'ServerlessAPIRecipe',
    Environment: environmentName,
    ManagedBy: 'CDK',
    Repository: 'aws-recipes',
  },
});

// Synthesize the CloudFormation template
app.synth();