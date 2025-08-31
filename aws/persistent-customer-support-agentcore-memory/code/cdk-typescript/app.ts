#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { NagSuppressions } from 'cdk-nag';

/**
 * Props for the PersistentCustomerSupportStack
 */
export interface PersistentCustomerSupportStackProps extends cdk.StackProps {
  /**
   * The name prefix for resources
   * @default 'customer-support'
   */
  readonly resourcePrefix?: string;

  /**
   * The stage/environment name
   * @default 'prod'
   */
  readonly stage?: string;

  /**
   * Whether to enable detailed monitoring
   * @default true
   */
  readonly enableDetailedMonitoring?: boolean;

  /**
   * DynamoDB table read capacity units
   * @default 5
   */
  readonly dynamoReadCapacity?: number;

  /**
   * DynamoDB table write capacity units
   * @default 5
   */
  readonly dynamoWriteCapacity?: number;

  /**
   * Lambda function timeout in seconds
   * @default 30
   */
  readonly lambdaTimeout?: number;

  /**
   * Lambda function memory size in MB
   * @default 512
   */
  readonly lambdaMemorySize?: number;
}

/**
 * CDK Stack for Persistent Customer Support Agent with Bedrock AgentCore Memory
 * 
 * This stack creates:
 * - DynamoDB table for customer metadata storage
 * - Lambda function for support agent logic
 * - API Gateway for client interactions
 * - IAM roles and policies with least privilege access
 * - CloudWatch log groups for monitoring
 * 
 * Note: Bedrock AgentCore Memory must be created manually using AWS CLI
 * as CDK support is not yet available for this preview service.
 */
export class PersistentCustomerSupportStack extends cdk.Stack {
  /**
   * The DynamoDB table for customer data
   */
  public readonly customerTable: dynamodb.Table;

  /**
   * The Lambda function for support agent processing
   */
  public readonly supportAgentFunction: lambda.Function;

  /**
   * The API Gateway REST API
   */
  public readonly supportApi: apigateway.RestApi;

  /**
   * The CloudWatch log group for Lambda function
   */
  public readonly lambdaLogGroup: logs.LogGroup;

  constructor(scope: Construct, id: string, props: PersistentCustomerSupportStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const resourcePrefix = props.resourcePrefix ?? 'customer-support';
    const stage = props.stage ?? 'prod';
    const enableDetailedMonitoring = props.enableDetailedMonitoring ?? true;
    const dynamoReadCapacity = props.dynamoReadCapacity ?? 5;
    const dynamoWriteCapacity = props.dynamoWriteCapacity ?? 5;
    const lambdaTimeout = props.lambdaTimeout ?? 30;
    const lambdaMemorySize = props.lambdaMemorySize ?? 512;

    // Create DynamoDB table for customer metadata
    this.customerTable = new dynamodb.Table(this, 'CustomerDataTable', {
      tableName: `${resourcePrefix}-customer-data`,
      partitionKey: {
        name: 'customerId',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PROVISIONED,
      readCapacity: dynamoReadCapacity,
      writeCapacity: dynamoWriteCapacity,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      tags: {
        Purpose: 'CustomerSupport',
        Environment: stage,
      },
    });

    // Create CloudWatch log group for Lambda function
    this.lambdaLogGroup = new logs.LogGroup(this, 'SupportAgentLogGroup', {
      logGroupName: `/aws/lambda/${resourcePrefix}-support-agent`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create IAM role for Lambda function with least privilege
    const lambdaRole = new iam.Role(this, 'SupportAgentRole', {
      roleName: `${resourcePrefix}-support-agent-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Role for customer support agent Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Add specific permissions for AgentCore Memory
    lambdaRole.addToPolicy(new iam.PolicyStatement({
      sid: 'BedrockAgentCorePermissions',
      effect: iam.Effect.ALLOW,
      actions: [
        'bedrock-agentcore:CreateEvent',
        'bedrock-agentcore:ListSessions',
        'bedrock-agentcore:ListEvents',
        'bedrock-agentcore:GetEvent',
        'bedrock-agentcore:RetrieveMemoryRecords',
      ],
      resources: ['*'], // AgentCore resources are account-scoped
    }));

    // Add Bedrock model invocation permissions
    lambdaRole.addToPolicy(new iam.PolicyStatement({
      sid: 'BedrockModelPermissions',
      effect: iam.Effect.ALLOW,
      actions: [
        'bedrock:InvokeModel',
      ],
      resources: [
        `arn:aws:bedrock:${this.region}::foundation-model/*`,
      ],
    }));

    // Add DynamoDB permissions
    lambdaRole.addToPolicy(new iam.PolicyStatement({
      sid: 'DynamoDBPermissions',
      effect: iam.Effect.ALLOW,
      actions: [
        'dynamodb:GetItem',
        'dynamodb:PutItem',
        'dynamodb:UpdateItem',
        'dynamodb:Query',
      ],
      resources: [this.customerTable.tableArn],
    }));

    // Add CloudWatch Logs permissions
    lambdaRole.addToPolicy(new iam.PolicyStatement({
      sid: 'CloudWatchLogsPermissions',
      effect: iam.Effect.ALLOW,
      actions: [
        'logs:CreateLogStream',
        'logs:PutLogEvents',
      ],
      resources: [this.lambdaLogGroup.logGroupArn],
    }));

    // Create Lambda function for support agent logic
    this.supportAgentFunction = new lambda.Function(this, 'SupportAgentFunction', {
      functionName: `${resourcePrefix}-support-agent`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'lambda_function.lambda_handler',
      code: lambda.Code.fromInline(this.getSupportAgentCode()),
      role: lambdaRole,
      timeout: cdk.Duration.seconds(lambdaTimeout),
      memorySize: lambdaMemorySize,
      logGroup: this.lambdaLogGroup,
      environment: {
        DDB_TABLE_NAME: this.customerTable.tableName,
        // MEMORY_ID will need to be set manually after AgentCore Memory creation
        MEMORY_ID: 'SET_AFTER_AGENTCORE_MEMORY_CREATION',
      },
      description: 'Customer support agent with persistent memory using Bedrock AgentCore',
      tracing: lambda.Tracing.ACTIVE,
    });

    // Create API Gateway REST API
    this.supportApi = new apigateway.RestApi(this, 'SupportApi', {
      restApiName: `${resourcePrefix}-support-api`,
      description: 'Customer Support Agent API with persistent memory',
      deployOptions: {
        stageName: stage,
        throttlingRateLimit: 100,
        throttlingBurstLimit: 200,
        loggingLevel: enableDetailedMonitoring ? apigateway.MethodLoggingLevel.INFO : apigateway.MethodLoggingLevel.ERROR,
        dataTraceEnabled: enableDetailedMonitoring,
        metricsEnabled: enableDetailedMonitoring,
      },
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key'],
      },
      cloudWatchRole: true,
    });

    // Create /support resource
    const supportResource = this.supportApi.root.addResource('support');

    // Add POST method for support interactions
    const supportIntegration = new apigateway.LambdaIntegration(this.supportAgentFunction, {
      requestTemplates: { 'application/json': '{ "statusCode": "200" }' },
      integrationResponses: [
        {
          statusCode: '200',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': "'*'",
          },
        },
        {
          statusCode: '400',
          selectionPattern: '4\\d{2}',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': "'*'",
          },
        },
        {
          statusCode: '500',
          selectionPattern: '5\\d{2}',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': "'*'",
          },
        },
      ],
    });

    supportResource.addMethod('POST', supportIntegration, {
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
          statusCode: '500',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
      ],
      requestValidator: new apigateway.RequestValidator(this, 'SupportRequestValidator', {
        restApi: this.supportApi,
        requestValidatorName: 'support-request-validator',
        validateRequestBody: true,
        validateRequestParameters: false,
      }),
      requestModels: {
        'application/json': new apigateway.Model(this, 'SupportRequestModel', {
          restApi: this.supportApi,
          modelName: 'SupportRequest',
          contentType: 'application/json',
          schema: {
            type: apigateway.JsonSchemaType.OBJECT,
            required: ['customerId', 'message'],
            properties: {
              customerId: {
                type: apigateway.JsonSchemaType.STRING,
                minLength: 1,
                maxLength: 256,
              },
              message: {
                type: apigateway.JsonSchemaType.STRING,
                minLength: 1,
                maxLength: 2000,
              },
              sessionId: {
                type: apigateway.JsonSchemaType.STRING,
                maxLength: 256,
              },
              metadata: {
                type: apigateway.JsonSchemaType.OBJECT,
              },
            },
          },
        }),
      },
    });

    // Create CloudWatch dashboard for monitoring (optional)
    if (enableDetailedMonitoring) {
      const dashboard = new cdk.aws_cloudwatch.Dashboard(this, 'SupportAgentDashboard', {
        dashboardName: `${resourcePrefix}-support-agent-dashboard`,
        widgets: [
          [
            new cdk.aws_cloudwatch.GraphWidget({
              title: 'Lambda Function Metrics',
              left: [
                this.supportAgentFunction.metricInvocations(),
                this.supportAgentFunction.metricErrors(),
                this.supportAgentFunction.metricThrottles(),
              ],
              right: [
                this.supportAgentFunction.metricDuration(),
              ],
            }),
          ],
          [
            new cdk.aws_cloudwatch.GraphWidget({
              title: 'API Gateway Metrics',
              left: [
                this.supportApi.metricCount(),
                this.supportApi.metricClientError(),
                this.supportApi.metricServerError(),
              ],
              right: [
                this.supportApi.metricLatency(),
                this.supportApi.metricIntegrationLatency(),
              ],
            }),
          ],
          [
            new cdk.aws_cloudwatch.GraphWidget({
              title: 'DynamoDB Metrics',
              left: [
                this.customerTable.metricConsumedReadCapacityUnits(),
                this.customerTable.metricConsumedWriteCapacityUnits(),
              ],
              right: [
                this.customerTable.metricSuccessfulRequestLatency(),
              ],
            }),
          ],
        ],
      });
    }

    // Add CDK-Nag suppressions for security best practices
    NagSuppressions.addResourceSuppressions(
      lambdaRole,
      [
        {
          id: 'AwsSolutions-IAM5',
          reason: 'AgentCore Memory resources are account-scoped and require wildcard permissions',
          appliesTo: ['Resource::*'],
        },
      ]
    );

    NagSuppressions.addResourceSuppressions(
      this.supportApi,
      [
        {
          id: 'AwsSolutions-APIG2',
          reason: 'Request validation is implemented for POST method',
        },
        {
          id: 'AwsSolutions-COG4',
          reason: 'This is a demo API. In production, implement Cognito or API Key authentication',
        },
      ]
    );

    NagSuppressions.addResourceSuppressions(
      this.supportAgentFunction,
      [
        {
          id: 'AwsSolutions-L1',
          reason: 'Python 3.11 is the latest supported runtime for this use case',
        },
      ]
    );

    // Stack outputs
    new cdk.CfnOutput(this, 'CustomerTableName', {
      value: this.customerTable.tableName,
      description: 'DynamoDB table name for customer data',
      exportName: `${id}-CustomerTableName`,
    });

    new cdk.CfnOutput(this, 'SupportApiEndpoint', {
      value: this.supportApi.url,
      description: 'API Gateway endpoint for customer support',
      exportName: `${id}-SupportApiEndpoint`,
    });

    new cdk.CfnOutput(this, 'SupportFunctionName', {
      value: this.supportAgentFunction.functionName,
      description: 'Lambda function name for support agent',
      exportName: `${id}-SupportFunctionName`,
    });

    new cdk.CfnOutput(this, 'LambdaRoleArn', {
      value: lambdaRole.roleArn,
      description: 'IAM role ARN for Lambda function',
      exportName: `${id}-LambdaRoleArn`,
    });

    new cdk.CfnOutput(this, 'PostDeploymentInstructions', {
      value: 'After deployment, create Bedrock AgentCore Memory using AWS CLI and update MEMORY_ID environment variable',
      description: 'Important post-deployment steps',
    });
  }

  /**
   * Returns the Lambda function code for the support agent
   */
  private getSupportAgentCode(): string {
    return `import json
import boto3
import os
from datetime import datetime

bedrock_agentcore = boto3.client('bedrock-agentcore')
bedrock_runtime = boto3.client('bedrock-runtime')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Main Lambda handler for customer support agent with persistent memory
    """
    try:
        # Parse incoming request
        body = json.loads(event['body']) if 'body' in event else event
        customer_id = body.get('customerId')
        message = body.get('message')
        session_id = body.get('sessionId', f"session-{customer_id}-{int(datetime.now().timestamp())}")
        
        # Validate required fields
        if not customer_id or not message:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'customerId and message are required'})
            }
        
        # Retrieve customer context from DynamoDB
        table = dynamodb.Table(os.environ['DDB_TABLE_NAME'])
        customer_data = get_customer_data(table, customer_id)
        
        # Retrieve relevant memories from AgentCore
        memory_context = retrieve_memory_context(customer_id, message)
        
        # Generate AI response using Bedrock
        ai_response = generate_support_response(message, memory_context, customer_data)
        
        # Store interaction in AgentCore Memory
        store_interaction(customer_id, session_id, message, ai_response)
        
        # Update customer data if needed
        update_customer_data(table, customer_id, body.get('metadata', {}))
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'response': ai_response,
                'sessionId': session_id,
                'customerId': customer_id,
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        print(f"Error processing support request: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Internal server error'})
        }

def get_customer_data(table, customer_id):
    """Retrieve customer data from DynamoDB"""
    try:
        response = table.get_item(Key={'customerId': customer_id})
        return response.get('Item', {})
    except Exception as e:
        print(f"Error retrieving customer data: {e}")
        return {}

def retrieve_memory_context(customer_id, query):
    """Retrieve relevant memories from AgentCore"""
    try:
        memory_id = os.environ.get('MEMORY_ID')
        if not memory_id or memory_id == 'SET_AFTER_AGENTCORE_MEMORY_CREATION':
            print("AgentCore Memory ID not configured")
            return []
            
        response = bedrock_agentcore.retrieve_memory_records(
            memoryId=memory_id,
            query=query,
            filter={'customerId': customer_id},
            maxResults=5
        )
        return [record['content'] for record in response.get('memoryRecords', [])]
    except Exception as e:
        print(f"Error retrieving memory: {e}")
        return []

def generate_support_response(message, memory_context, customer_data):
    """Generate AI response using Bedrock"""
    try:
        # Prepare context for AI model
        context_parts = []
        
        if memory_context:
            context_parts.append(f"Previous interactions: {'; '.join(memory_context)}")
        
        if customer_data:
            context_parts.append(f"Customer profile: {json.dumps(customer_data, default=str)}")
        
        context_parts.append(f"Current query: {message}")
        
        context = f"""
        Customer Support Context:
        {chr(10).join(context_parts)}
        
        Provide a helpful, personalized response based on the customer's history and current request.
        Be empathetic, professional, and reference relevant past interactions when appropriate.
        Keep responses concise but comprehensive.
        """
        
        # Invoke Bedrock model
        response = bedrock_runtime.invoke_model(
            modelId='anthropic.claude-3-haiku-20240307-v1:0',
            body=json.dumps({
                'anthropic_version': 'bedrock-2023-05-31',
                'max_tokens': 500,
                'messages': [
                    {
                        'role': 'user',
                        'content': context
                    }
                ]
            })
        )
        
        result = json.loads(response['body'].read())
        return result['content'][0]['text']
        
    except Exception as e:
        print(f"Error generating response: {e}")
        return "I apologize, but I'm experiencing technical difficulties. Please try again or contact support directly."

def store_interaction(customer_id, session_id, user_message, agent_response):
    """Store interaction in AgentCore Memory"""
    try:
        memory_id = os.environ.get('MEMORY_ID')
        if not memory_id or memory_id == 'SET_AFTER_AGENTCORE_MEMORY_CREATION':
            print("AgentCore Memory ID not configured - skipping memory storage")
            return
            
        # Store user message
        bedrock_agentcore.create_event(
            memoryId=memory_id,
            sessionId=session_id,
            eventData={
                'type': 'user_message',
                'customerId': customer_id,
                'content': user_message,
                'timestamp': datetime.now().isoformat()
            }
        )
        
        # Store agent response
        bedrock_agentcore.create_event(
            memoryId=memory_id,
            sessionId=session_id,
            eventData={
                'type': 'agent_response',
                'customerId': customer_id,
                'content': agent_response,
                'timestamp': datetime.now().isoformat()
            }
        )
    except Exception as e:
        print(f"Error storing interaction: {e}")

def update_customer_data(table, customer_id, metadata):
    """Update customer data in DynamoDB"""
    try:
        update_data = {
            'customerId': customer_id,
            'lastInteraction': datetime.now().isoformat()
        }
        
        # Add any provided metadata
        if metadata:
            update_data.update(metadata)
            
        table.put_item(Item=update_data)
    except Exception as e:
        print(f"Error updating customer data: {e}")
`;
  }
}

// CDK App
const app = new cdk.App();

// Get context values or use defaults
const resourcePrefix = app.node.tryGetContext('resourcePrefix') || 'customer-support';
const stage = app.node.tryGetContext('stage') || 'dev';
const enableDetailedMonitoring = app.node.tryGetContext('enableDetailedMonitoring') ?? true;

// Create the stack
new PersistentCustomerSupportStack(app, 'PersistentCustomerSupportStack', {
  resourcePrefix,
  stage,
  enableDetailedMonitoring,
  description: 'Persistent Customer Support Agent with Bedrock AgentCore Memory - CDK TypeScript Implementation',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'PersistentCustomerSupport',
    Environment: stage,
    ManagedBy: 'CDK',
    Version: '1.0',
  },
});

app.synth();