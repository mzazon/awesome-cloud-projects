#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as stepfunctions from 'aws-cdk-lib/aws-stepfunctions';
import * as sfnTasks from 'aws-cdk-lib/aws-stepfunctions-tasks';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Enterprise API Integration Stack with AgentCore Gateway and Step Functions
 * 
 * This stack creates a complete enterprise API integration solution that enables
 * AI agents to interact with enterprise systems through Amazon Bedrock AgentCore Gateway,
 * orchestrated by Step Functions and powered by Lambda functions for transformation
 * and validation.
 */
class ApiIntegrationAgentCoreStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate a unique suffix for resource naming
    const uniqueSuffix = this.node.tryGetContext('uniqueSuffix') || 
      Math.random().toString(36).substring(2, 8);

    // ===== Lambda Execution Role =====
    const lambdaExecutionRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `lambda-execution-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for API transformation and validation Lambda functions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        LambdaLoggingPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: [`arn:aws:logs:${this.region}:${this.account}:*`],
            }),
          ],
        }),
      },
    });

    // ===== API Transformer Lambda Function =====
    const apiTransformerFunction = new lambda.Function(this, 'ApiTransformerFunction', {
      functionName: `api-transformer-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(60),
      memorySize: 512,
      description: 'Transforms API requests for enterprise system integration',
      environment: {
        ENVIRONMENT: 'production',
        LOG_LEVEL: 'INFO',
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
import json
import urllib3
from typing import Dict, Any

# Initialize urllib3 PoolManager for HTTP requests
http = urllib3.PoolManager()

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Transform API requests for enterprise system integration
    """
    try:
        # Extract request parameters
        api_type = event.get('api_type', 'generic')
        payload = event.get('payload', {})
        target_url = event.get('target_url')
        
        # Transform based on API type
        if api_type == 'erp':
            transformed_data = transform_erp_request(payload)
        elif api_type == 'crm':
            transformed_data = transform_crm_request(payload)
        else:
            transformed_data = payload
        
        # Simulate API call to target system (using mock response)
        # In production, this would make actual HTTP requests to enterprise APIs
        mock_response = {
            'success': True,
            'transaction_id': f"{api_type}-{payload.get('id', 'unknown')}",
            'processed_data': transformed_data,
            'status': 'completed'
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'success': True,
                'data': mock_response,
                'status_code': 200
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'success': False,
                'error': str(e)
            })
        }

def transform_erp_request(payload: Dict[str, Any]) -> Dict[str, Any]:
    """Transform requests for ERP system format"""
    return {
        'transaction_type': payload.get('type', 'query'),
        'data': payload.get('data', {}),
        'metadata': {
            'source': 'agentcore_gateway',
            'timestamp': payload.get('timestamp')
        }
    }

def transform_crm_request(payload: Dict[str, Any]) -> Dict[str, Any]:
    """Transform requests for CRM system format"""
    return {
        'operation': payload.get('action', 'read'),
        'entity': payload.get('entity', 'contact'),
        'attributes': payload.get('data', {}),
        'source_system': 'ai_agent'
    }
      `),
    });

    // ===== Data Validator Lambda Function =====
    const dataValidatorFunction = new lambda.Function(this, 'DataValidatorFunction', {
      functionName: `data-validator-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      description: 'Validates API request data according to enterprise rules',
      environment: {
        ENVIRONMENT: 'production',
        LOG_LEVEL: 'INFO',
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
import json
import re
from typing import Dict, Any, List

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Validate API request data according to enterprise rules
    """
    try:
        data = event.get('data', {})
        validation_type = event.get('validation_type', 'standard')
        
        # Perform validation based on type
        validation_result = validate_data(data, validation_type)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'valid': validation_result['is_valid'],
                'errors': validation_result['errors'],
                'sanitized_data': validation_result['sanitized_data']
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'valid': False,
                'errors': [f"Validation error: {str(e)}"]
            })
        }

def validate_data(data: Dict[str, Any], validation_type: str) -> Dict[str, Any]:
    """Perform comprehensive data validation"""
    errors = []
    sanitized_data = {}
    
    # Standard validation rules
    if validation_type == 'standard':
        errors.extend(validate_required_fields(data))
        errors.extend(validate_data_types(data))
        sanitized_data = sanitize_data(data)
    
    # Financial data validation
    elif validation_type == 'financial':
        errors.extend(validate_required_fields(data))
        errors.extend(validate_financial_data(data))
        sanitized_data = sanitize_financial_data(data)
    
    # Customer data validation
    elif validation_type == 'customer':
        errors.extend(validate_required_fields(data))
        errors.extend(validate_customer_data(data))
        sanitized_data = sanitize_customer_data(data)
    
    return {
        'is_valid': len(errors) == 0,
        'errors': errors,
        'sanitized_data': sanitized_data
    }

def validate_required_fields(data: Dict[str, Any]) -> List[str]:
    """Validate required field presence"""
    errors = []
    required_fields = ['id', 'type', 'data']
    
    for field in required_fields:
        if field not in data or data[field] is None:
            errors.append(f"Required field '{field}' is missing")
    
    return errors

def validate_data_types(data: Dict[str, Any]) -> List[str]:
    """Validate data type constraints"""
    errors = []
    
    if 'id' in data and not isinstance(data['id'], (str, int)):
        errors.append("Field 'id' must be string or integer")
    
    if 'type' in data and not isinstance(data['type'], str):
        errors.append("Field 'type' must be string")
    
    return errors

def validate_financial_data(data: Dict[str, Any]) -> List[str]:
    """Validate financial-specific data"""
    errors = []
    
    if 'amount' in data:
        try:
            amount = float(data['amount'])
            if amount < 0:
                errors.append("Amount cannot be negative")
            if amount > 1000000:
                errors.append("Amount exceeds maximum limit")
        except (ValueError, TypeError):
            errors.append("Amount must be a valid number")
    
    return errors

def validate_customer_data(data: Dict[str, Any]) -> List[str]:
    """Validate customer-specific data"""
    errors = []
    
    if 'email' in data:
        email_pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$'
        if not re.match(email_pattern, data['email']):
            errors.append("Invalid email format")
    
    if 'phone' in data:
        phone_pattern = r'^\\+?[\\d\\s\\-\\(\\)]{10,}$'
        if not re.match(phone_pattern, str(data['phone'])):
            errors.append("Invalid phone number format")
    
    return errors

def sanitize_data(data: Dict[str, Any]) -> Dict[str, Any]:
    """Sanitize and clean data"""
    sanitized = {}
    for key, value in data.items():
        if isinstance(value, str):
            sanitized[key] = value.strip()
        else:
            sanitized[key] = value
    return sanitized

def sanitize_financial_data(data: Dict[str, Any]) -> Dict[str, Any]:
    """Sanitize financial-specific data"""
    sanitized = sanitize_data(data)
    if 'amount' in sanitized:
        try:
            sanitized['amount'] = round(float(sanitized['amount']), 2)
        except (ValueError, TypeError):
            pass
    return sanitized

def sanitize_customer_data(data: Dict[str, Any]) -> Dict[str, Any]:
    """Sanitize customer-specific data"""
    sanitized = sanitize_data(data)
    if 'email' in sanitized:
        sanitized['email'] = sanitized['email'].lower()
    return sanitized
      `),
    });

    // ===== Step Functions Execution Role =====
    const stepFunctionsRole = new iam.Role(this, 'StepFunctionsExecutionRole', {
      roleName: `stepfunctions-execution-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('states.amazonaws.com'),
      description: 'Execution role for Step Functions state machine orchestration',
      inlinePolicies: {
        LambdaInvokePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['lambda:InvokeFunction'],
              resources: [
                apiTransformerFunction.functionArn,
                dataValidatorFunction.functionArn,
              ],
            }),
          ],
        }),
        LoggingPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogDelivery',
                'logs:GetLogDelivery',
                'logs:UpdateLogDelivery',
                'logs:DeleteLogDelivery',
                'logs:ListLogDeliveries',
                'logs:PutResourcePolicy',
                'logs:DescribeResourcePolicies',
                'logs:DescribeLogGroups',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // ===== CloudWatch Log Group for Step Functions =====
    const stepFunctionsLogGroup = new logs.LogGroup(this, 'StepFunctionsLogGroup', {
      logGroupName: `/aws/stepfunctions/ApiOrchestration-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // ===== Step Functions Tasks =====
    const validateInputTask = new sfnTasks.LambdaInvoke(this, 'ValidateInputTask', {
      lambdaFunction: dataValidatorFunction,
      outputPath: '$.Payload',
      retryOnServiceExceptions: true,
      timeout: cdk.Duration.seconds(30),
    });

    const transformForERPTask = new sfnTasks.LambdaInvoke(this, 'TransformForERPTask', {
      lambdaFunction: apiTransformerFunction,
      payload: stepfunctions.TaskInput.fromObject({
        'api_type': 'erp',
        'payload.$': '$',
        'target_url': 'https://example-erp.com/api/v1/process',
      }),
      outputPath: '$.Payload',
      retryOnServiceExceptions: true,
      timeout: cdk.Duration.seconds(60),
    });

    const transformForCRMTask = new sfnTasks.LambdaInvoke(this, 'TransformForCRMTask', {
      lambdaFunction: apiTransformerFunction,
      payload: stepfunctions.TaskInput.fromObject({
        'api_type': 'crm',
        'payload.$': '$',
        'target_url': 'https://example-crm.com/api/v2/entities',
      }),
      outputPath: '$.Payload',
      retryOnServiceExceptions: true,
      timeout: cdk.Duration.seconds(60),
    });

    // ===== Step Functions State Machine Definition =====
    const checkValidation = new stepfunctions.Choice(this, 'CheckValidation')
      .when(
        stepfunctions.Condition.stringMatches('$.body', '*"valid":true*'),
        new stepfunctions.Parallel(this, 'RouteRequest')
          .branch(transformForERPTask)
          .branch(transformForCRMTask)
          .next(new stepfunctions.Pass(this, 'AggregateResults', {
            parameters: {
              'status': 'success',
              'results.$': '$',
              'timestamp.$': '$$.State.EnteredTime',
              'execution_arn.$': '$$.Execution.Name',
            },
          }))
          .addCatch(new stepfunctions.Pass(this, 'ProcessingFailed', {
            parameters: {
              'status': 'processing_failed',
              'error.$': '$.Error',
              'timestamp.$': '$$.State.EnteredTime',
            },
          }), {
            resultPath: '$.error',
          })
      )
      .otherwise(new stepfunctions.Pass(this, 'ValidationFailed', {
        parameters: {
          'status': 'validation_failed',
          'errors.$': '$.errors',
          'timestamp.$': '$$.State.EnteredTime',
        },
      }));

    const definition = validateInputTask
      .addCatch(new stepfunctions.Pass(this, 'ValidationError', {
        parameters: {
          'status': 'validation_error',
          'error.$': '$.Error',
          'timestamp.$': '$$.State.EnteredTime',
        },
      }), {
        resultPath: '$.error',
      })
      .next(checkValidation);

    // ===== Step Functions State Machine =====
    const stateMachine = new stepfunctions.StateMachine(this, 'ApiOrchestrationStateMachine', {
      stateMachineName: `api-orchestrator-${uniqueSuffix}`,
      definition,
      role: stepFunctionsRole,
      timeout: cdk.Duration.minutes(5),
      tracingEnabled: true,
      logs: {
        destination: stepFunctionsLogGroup,
        level: stepfunctions.LogLevel.ALL,
        includeExecutionData: true,
      },
    });

    // ===== API Gateway Role =====
    const apiGatewayRole = new iam.Role(this, 'ApiGatewayStepFunctionsRole', {
      roleName: `apigateway-stepfunctions-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('apigateway.amazonaws.com'),
      description: 'Role for API Gateway to invoke Step Functions',
      inlinePolicies: {
        StepFunctionsPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['states:StartExecution'],
              resources: [stateMachine.stateMachineArn],
            }),
          ],
        }),
      },
    });

    // ===== API Gateway =====
    const api = new apigateway.RestApi(this, 'EnterpriseApiIntegration', {
      restApiName: `enterprise-api-integration-${uniqueSuffix}`,
      description: 'Enterprise API Integration with AgentCore Gateway',
      endpointConfiguration: {
        types: [apigateway.EndpointType.REGIONAL],
      },
      deployOptions: {
        stageName: 'prod',
        metricsEnabled: true,
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        dataTraceEnabled: true,
        throttlingBurstLimit: 100,
        throttlingRateLimit: 50,
      },
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key'],
      },
    });

    // ===== API Gateway Integration =====
    const integrateResource = api.root.addResource('integrate');
    
    const stepFunctionsIntegration = new apigateway.Integration({
      type: apigateway.IntegrationType.AWS,
      integrationHttpMethod: 'POST',
      uri: `arn:aws:apigateway:${this.region}:states:action/StartExecution`,
      options: {
        credentialsRole: apiGatewayRole,
        requestTemplates: {
          'application/json': JSON.stringify({
            input: '$util.escapeJavaScript($input.body)',
            stateMachineArn: stateMachine.stateMachineArn,
          }),
        },
        integrationResponses: [
          {
            statusCode: '200',
            responseTemplates: {
              'application/json': JSON.stringify({
                executionArn: '$input.path("$.executionArn")',
                startDate: '$input.path("$.startDate")',
                status: 'STARTED',
              }),
            },
          },
          {
            statusCode: '400',
            selectionPattern: '4\\d{2}',
            responseTemplates: {
              'application/json': JSON.stringify({
                error: 'Bad Request',
                message: '$input.path("$.errorMessage")',
              }),
            },
          },
          {
            statusCode: '500',
            selectionPattern: '5\\d{2}',
            responseTemplates: {
              'application/json': JSON.stringify({
                error: 'Internal Server Error',
                message: 'An error occurred while processing your request',
              }),
            },
          },
        ],
      },
    });

    integrateResource.addMethod('POST', stepFunctionsIntegration, {
      methodResponses: [
        {
          statusCode: '200',
          responseModels: {
            'application/json': apigateway.Model.EMPTY_MODEL,
          },
        },
        {
          statusCode: '400',
          responseModels: {
            'application/json': apigateway.Model.ERROR_MODEL,
          },
        },
        {
          statusCode: '500',
          responseModels: {
            'application/json': apigateway.Model.ERROR_MODEL,
          },
        },
      ],
      requestValidator: new apigateway.RequestValidator(this, 'RequestValidator', {
        restApi: api,
        validateRequestBody: true,
        validateRequestParameters: false,
      }),
      requestModels: {
        'application/json': new apigateway.Model(this, 'IntegrationRequestModel', {
          restApi: api,
          contentType: 'application/json',
          schema: {
            type: apigateway.JsonSchemaType.OBJECT,
            properties: {
              id: {
                type: apigateway.JsonSchemaType.STRING,
                description: 'Unique request identifier',
              },
              type: {
                type: apigateway.JsonSchemaType.STRING,
                enum: ['erp', 'crm', 'inventory'],
                description: 'Target system type',
              },
              data: {
                type: apigateway.JsonSchemaType.OBJECT,
                description: 'Request payload data',
                properties: {
                  amount: {
                    type: apigateway.JsonSchemaType.NUMBER,
                    description: 'Transaction amount (for financial data)',
                  },
                  email: {
                    type: apigateway.JsonSchemaType.STRING,
                    description: 'Email address (for customer data)',
                  },
                },
              },
              validation_type: {
                type: apigateway.JsonSchemaType.STRING,
                enum: ['standard', 'financial', 'customer'],
                description: 'Validation rules to apply',
              },
            },
            required: ['id', 'type', 'data'],
          },
        }),
      },
    });

    // ===== CloudWatch Dashboard (Optional) =====
    // Uncomment to create a monitoring dashboard
    /*
    const dashboard = new cloudwatch.Dashboard(this, 'ApiIntegrationDashboard', {
      dashboardName: `api-integration-dashboard-${uniqueSuffix}`,
    });

    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'API Gateway Requests',
        left: [api.metricCount()],
        width: 12,
      }),
      new cloudwatch.GraphWidget({
        title: 'Step Functions Executions',
        left: [stateMachine.metricStarted()],
        width: 12,
      }),
      new cloudwatch.GraphWidget({
        title: 'Lambda Function Invocations',
        left: [
          apiTransformerFunction.metricInvocations(),
          dataValidatorFunction.metricInvocations(),
        ],
        width: 12,
      }),
      new cloudwatch.GraphWidget({
        title: 'Lambda Function Errors',
        left: [
          apiTransformerFunction.metricErrors(),
          dataValidatorFunction.metricErrors(),
        ],
        width: 12,
      })
    );
    */

    // ===== CloudFormation Outputs =====
    new cdk.CfnOutput(this, 'ApiGatewayUrl', {
      value: api.url,
      description: 'URL of the API Gateway endpoint for enterprise integration',
      exportName: `ApiGatewayUrl-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'IntegrateEndpoint', {
      value: `${api.url}integrate`,
      description: 'Full URL for the integration endpoint',
      exportName: `IntegrateEndpoint-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'StateMachineArn', {
      value: stateMachine.stateMachineArn,
      description: 'ARN of the Step Functions state machine',
      exportName: `StateMachineArn-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'ApiTransformerFunctionName', {
      value: apiTransformerFunction.functionName,
      description: 'Name of the API transformer Lambda function',
      exportName: `ApiTransformerFunctionName-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'DataValidatorFunctionName', {
      value: dataValidatorFunction.functionName,
      description: 'Name of the data validator Lambda function',
      exportName: `DataValidatorFunctionName-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'StepFunctionsLogGroup', {
      value: stepFunctionsLogGroup.logGroupName,
      description: 'CloudWatch Log Group for Step Functions execution logs',
      exportName: `StepFunctionsLogGroup-${uniqueSuffix}`,
    });

    // ===== Tags for Resource Management =====
    cdk.Tags.of(this).add('Project', 'EnterpriseApiIntegration');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('Owner', 'AwsRecipes');
    cdk.Tags.of(this).add('CostCenter', 'Engineering');
    cdk.Tags.of(this).add('Purpose', 'AgentCoreGatewayIntegration');
  }
}

// ===== CDK Application =====
const app = new cdk.App();

// Get context values for deployment customization
const uniqueSuffix = app.node.tryGetContext('uniqueSuffix') || 
  Math.random().toString(36).substring(2, 8);

new ApiIntegrationAgentCoreStack(app, 'ApiIntegrationAgentCoreStack', {
  description: 'Enterprise API Integration with AgentCore Gateway and Step Functions',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  stackName: `api-integration-agentcore-${uniqueSuffix}`,
  tags: {
    Project: 'EnterpriseApiIntegration',
    Environment: 'Production',
    DeployedBy: 'CDK',
  },
});

app.synth();