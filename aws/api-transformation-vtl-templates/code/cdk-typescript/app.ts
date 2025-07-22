#!/usr/bin/env node

/**
 * CDK TypeScript Application for Request/Response Transformation with VTL Templates
 * 
 * This application demonstrates comprehensive request/response transformation using 
 * API Gateway's Velocity Template Language (VTL) mapping templates, custom models 
 * for validation, and integration patterns with Lambda functions and S3.
 * 
 * Features:
 * - JSON Schema models for request/response validation
 * - Advanced VTL mapping templates for data transformation
 * - Custom gateway responses for error handling
 * - CloudWatch logging and monitoring
 * - Multiple integration types (Lambda, S3)
 * - Comprehensive error handling and validation
 */

import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as path from 'path';

/**
 * Stack for implementing request/response transformation with VTL templates
 */
export class RequestResponseTransformationStack extends cdk.Stack {
  private readonly dataProcessorFunction: lambda.Function;
  private readonly dataBucket: s3.Bucket;
  private readonly transformationApi: apigateway.RestApi;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resources
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // Create S3 bucket for data operations
    this.dataBucket = this.createDataBucket(uniqueSuffix);

    // Create Lambda function for data processing
    this.dataProcessorFunction = this.createDataProcessorFunction(uniqueSuffix);

    // Create API Gateway with transformation capabilities
    this.transformationApi = this.createTransformationApi(uniqueSuffix);

    // Configure API Gateway resources and methods
    this.configureApiResources();

    // Create CloudWatch log group for API Gateway
    this.createCloudWatchLogGroup();

    // Output important values
    this.createOutputs();
  }

  /**
   * Create S3 bucket for data storage operations
   */
  private createDataBucket(suffix: string): s3.Bucket {
    const bucket = new s3.Bucket(this, 'DataBucket', {
      bucketName: `api-data-store-${suffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: false,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
    });

    cdk.Tags.of(bucket).add('Purpose', 'API Data Operations');
    cdk.Tags.of(bucket).add('Environment', 'Transformation Demo');

    return bucket;
  }

  /**
   * Create Lambda function for processing transformed requests
   */
  private createDataProcessorFunction(suffix: string): lambda.Function {
    const lambdaFunction = new lambda.Function(this, 'DataProcessorFunction', {
      functionName: `data-processor-${suffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      description: 'Data processor with transformation support',
      environment: {
        BUCKET_NAME: this.dataBucket.bucketName,
        LOG_LEVEL: 'INFO',
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
from datetime import datetime
import os

s3 = boto3.client('s3')
bucket_name = os.environ.get('BUCKET_NAME')

def lambda_handler(event, context):
    try:
        # Log the transformed request for debugging
        print(f"Received event: {json.dumps(event)}")
        
        # Simulate processing based on event structure
        if 'user_data' in event:
            # Process user data from transformed request
            response_data = {
                'id': str(uuid.uuid4()),
                'processed_at': datetime.utcnow().isoformat(),
                'user_id': event['user_data'].get('id'),
                'full_name': f"{event['user_data'].get('first_name', '')} {event['user_data'].get('last_name', '')}".strip(),
                'profile': {
                    'email': event['user_data'].get('email'),
                    'phone': event['user_data'].get('phone'),
                    'preferences': event['user_data'].get('preferences', {})
                },
                'status': 'processed',
                'metadata': {
                    'source': 'api_gateway_transformation',
                    'version': '2.0'
                }
            }
            
            # Store processed data in S3 if bucket is available
            if bucket_name:
                try:
                    s3.put_object(
                        Bucket=bucket_name,
                        Key=f"processed/{response_data['id']}.json",
                        Body=json.dumps(response_data),
                        ContentType='application/json'
                    )
                    print(f"Stored processed data in S3: {response_data['id']}")
                except Exception as e:
                    print(f"Failed to store in S3: {str(e)}")
                    
        else:
            # Handle generic data processing
            response_data = {
                'id': str(uuid.uuid4()),
                'processed_at': datetime.utcnow().isoformat(),
                'input_data': event,
                'status': 'processed',
                'transformation_applied': True
            }
        
        return {
            'statusCode': 200,
            'body': response_data
        }
        
    except Exception as e:
        print(f"Error processing request: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': 'Internal processing error',
                'message': str(e),
                'request_id': context.aws_request_id
            }
        }
`),
    });

    // Grant S3 permissions to Lambda
    this.dataBucket.grantReadWrite(lambdaFunction);

    cdk.Tags.of(lambdaFunction).add('Purpose', 'Data Processing');
    cdk.Tags.of(lambdaFunction).add('Environment', 'Transformation Demo');

    return lambdaFunction;
  }

  /**
   * Create API Gateway with comprehensive transformation capabilities
   */
  private createTransformationApi(suffix: string): apigateway.RestApi {
    const api = new apigateway.RestApi(this, 'TransformationApi', {
      restApiName: `transformation-api-${suffix}`,
      description: 'API with advanced request/response transformation',
      deployOptions: {
        stageName: 'staging',
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        dataTraceEnabled: true,
        metricsEnabled: true,
        throttlingRateLimit: 100,
        throttlingBurstLimit: 200,
      },
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key'],
      },
      endpointConfiguration: {
        types: [apigateway.EndpointType.REGIONAL],
      },
      policy: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            principals: [new iam.AnyPrincipal()],
            actions: ['execute-api:Invoke'],
            resources: ['*'],
          }),
        ],
      }),
    });

    // Create JSON Schema models for request/response validation
    this.createApiModels(api);

    // Create request validator
    const validator = new apigateway.RequestValidator(this, 'RequestValidator', {
      restApi: api,
      requestValidatorName: 'comprehensive-validator',
      validateRequestBody: true,
      validateRequestParameters: true,
    });

    // Store validator as class property for use in methods
    (this as any).requestValidator = validator;

    // Configure custom gateway responses
    this.configureGatewayResponses(api);

    cdk.Tags.of(api).add('Purpose', 'API Transformation');
    cdk.Tags.of(api).add('Environment', 'Transformation Demo');

    return api;
  }

  /**
   * Create comprehensive JSON Schema models for validation
   */
  private createApiModels(api: apigateway.RestApi): void {
    // User Creation Request Model
    const userCreateRequestModel = new apigateway.Model(this, 'UserCreateRequestModel', {
      restApi: api,
      modelName: 'UserCreateRequest',
      contentType: 'application/json',
      schema: {
        schema: apigateway.JsonSchemaVersion.DRAFT4,
        title: 'User Creation Request',
        type: apigateway.JsonSchemaType.OBJECT,
        required: ['firstName', 'lastName', 'email'],
        properties: {
          firstName: {
            type: apigateway.JsonSchemaType.STRING,
            minLength: 1,
            maxLength: 50,
            pattern: '^[a-zA-Z\\s]+$',
          },
          lastName: {
            type: apigateway.JsonSchemaType.STRING,
            minLength: 1,
            maxLength: 50,
            pattern: '^[a-zA-Z\\s]+$',
          },
          email: {
            type: apigateway.JsonSchemaType.STRING,
            format: 'email',
            maxLength: 100,
          },
          phoneNumber: {
            type: apigateway.JsonSchemaType.STRING,
            pattern: '^\\+?[1-9]\\d{1,14}$',
          },
          preferences: {
            type: apigateway.JsonSchemaType.OBJECT,
            properties: {
              notifications: { type: apigateway.JsonSchemaType.BOOLEAN },
              theme: { 
                type: apigateway.JsonSchemaType.STRING,
                enum: ['light', 'dark'],
              },
              language: { 
                type: apigateway.JsonSchemaType.STRING,
                pattern: '^[a-z]{2}$',
              },
            },
          },
          metadata: {
            type: apigateway.JsonSchemaType.OBJECT,
            additionalProperties: true,
          },
        },
        additionalProperties: false,
      },
    });

    // User Response Model
    const userResponseModel = new apigateway.Model(this, 'UserResponseModel', {
      restApi: api,
      modelName: 'UserResponse',
      contentType: 'application/json',
      schema: {
        schema: apigateway.JsonSchemaVersion.DRAFT4,
        title: 'User Response',
        type: apigateway.JsonSchemaType.OBJECT,
        properties: {
          success: { type: apigateway.JsonSchemaType.BOOLEAN },
          data: {
            type: apigateway.JsonSchemaType.OBJECT,
            properties: {
              userId: { type: apigateway.JsonSchemaType.STRING },
              displayName: { type: apigateway.JsonSchemaType.STRING },
              contactInfo: {
                type: apigateway.JsonSchemaType.OBJECT,
                properties: {
                  email: { type: apigateway.JsonSchemaType.STRING },
                  phone: { type: apigateway.JsonSchemaType.STRING },
                },
              },
              createdAt: { type: apigateway.JsonSchemaType.STRING },
              profileComplete: { type: apigateway.JsonSchemaType.BOOLEAN },
            },
          },
          links: {
            type: apigateway.JsonSchemaType.OBJECT,
            properties: {
              self: { type: apigateway.JsonSchemaType.STRING },
              profile: { type: apigateway.JsonSchemaType.STRING },
            },
          },
        },
      },
    });

    // Error Response Model
    const errorResponseModel = new apigateway.Model(this, 'ErrorResponseModel', {
      restApi: api,
      modelName: 'ErrorResponse',
      contentType: 'application/json',
      schema: {
        schema: apigateway.JsonSchemaVersion.DRAFT4,
        title: 'Error Response',
        type: apigateway.JsonSchemaType.OBJECT,
        required: ['error', 'message'],
        properties: {
          error: { type: apigateway.JsonSchemaType.STRING },
          message: { type: apigateway.JsonSchemaType.STRING },
          details: {
            type: apigateway.JsonSchemaType.ARRAY,
            items: {
              type: apigateway.JsonSchemaType.OBJECT,
              properties: {
                field: { type: apigateway.JsonSchemaType.STRING },
                code: { type: apigateway.JsonSchemaType.STRING },
                message: { type: apigateway.JsonSchemaType.STRING },
              },
            },
          },
          timestamp: { type: apigateway.JsonSchemaType.STRING },
          path: { type: apigateway.JsonSchemaType.STRING },
        },
      },
    });

    // Store models as class properties for use in methods
    (this as any).userCreateRequestModel = userCreateRequestModel;
    (this as any).userResponseModel = userResponseModel;
    (this as any).errorResponseModel = errorResponseModel;
  }

  /**
   * Configure API Gateway resources and methods with transformation
   */
  private configureApiResources(): void {
    // Create /users resource
    const usersResource = this.transformationApi.root.addResource('users');

    // Configure POST method with advanced request transformation
    this.configurePostMethod(usersResource);

    // Configure GET method with query parameter transformation
    this.configureGetMethod(usersResource);
  }

  /**
   * Configure POST method with comprehensive request transformation
   */
  private configurePostMethod(resource: apigateway.Resource): void {
    const requestValidator = (this as any).requestValidator;
    const userCreateRequestModel = (this as any).userCreateRequestModel;
    const userResponseModel = (this as any).userResponseModel;
    const errorResponseModel = (this as any).errorResponseModel;

    // Advanced request mapping template
    const requestTemplate = `#set($inputRoot = $input.path('$'))
#set($context = $context)
#set($util = $util)

## Transform incoming request to backend format
{
    "user_data": {
        "id": "$util.escapeJavaScript($context.requestId)",
        "first_name": "$util.escapeJavaScript($inputRoot.firstName)",
        "last_name": "$util.escapeJavaScript($inputRoot.lastName)",
        "email": "$util.escapeJavaScript($inputRoot.email.toLowerCase())",
        #if($inputRoot.phoneNumber && $inputRoot.phoneNumber != "")
        "phone": "$util.escapeJavaScript($inputRoot.phoneNumber)",
        #end
        #if($inputRoot.preferences)
        "preferences": {
            #if($inputRoot.preferences.notifications)
            "email_notifications": $inputRoot.preferences.notifications,
            #end
            #if($inputRoot.preferences.theme)
            "ui_theme": "$util.escapeJavaScript($inputRoot.preferences.theme)",
            #end
            #if($inputRoot.preferences.language)
            "locale": "$util.escapeJavaScript($inputRoot.preferences.language)",
            #end
            "auto_save": true
        },
        #end
        "source": "api_gateway",
        "created_via": "rest_api"
    },
    "request_context": {
        "request_id": "$context.requestId",
        "api_id": "$context.apiId",
        "stage": "$context.stage",
        "resource_path": "$context.resourcePath",
        "http_method": "$context.httpMethod",
        "source_ip": "$context.identity.sourceIp",
        "user_agent": "$util.escapeJavaScript($context.identity.userAgent)",
        "request_time": "$context.requestTime",
        "request_time_epoch": $context.requestTimeEpoch
    },
    #if($inputRoot.metadata)
    "additional_metadata": $input.json('$.metadata'),
    #end
    "processing_flags": {
        "validate_email": true,
        "send_welcome": true,
        "create_profile": true
    }
}`;

    // Response transformation template
    const responseTemplate = `#set($inputRoot = $input.path('$'))
#set($context = $context)

## Transform backend response to standardized API format
{
    "success": true,
    "data": {
        "userId": "$util.escapeJavaScript($inputRoot.id)",
        "displayName": "$util.escapeJavaScript($inputRoot.full_name)",
        "contactInfo": {
            #if($inputRoot.profile.email)
            "email": "$util.escapeJavaScript($inputRoot.profile.email)",
            #end
            #if($inputRoot.profile.phone)
            "phone": "$util.escapeJavaScript($inputRoot.profile.phone)"
            #end
        },
        "createdAt": "$util.escapeJavaScript($inputRoot.processed_at)",
        "profileComplete": #if($inputRoot.profile.email && $inputRoot.full_name != "")true#{else}false#end,
        "preferences": #if($inputRoot.profile.preferences)$input.json('$.profile.preferences')#{else}{}#end
    },
    "metadata": {
        "processingId": "$util.escapeJavaScript($inputRoot.id)",
        "version": #if($inputRoot.metadata.version)"$util.escapeJavaScript($inputRoot.metadata.version)"#{else}"1.0"#end,
        "processedAt": "$util.escapeJavaScript($inputRoot.processed_at)"
    },
    "links": {
        "self": "https://$context.domainName/$context.stage/users/$util.escapeJavaScript($inputRoot.id)",
        "profile": "https://$context.domainName/$context.stage/users/$util.escapeJavaScript($inputRoot.id)/profile"
    }
}`;

    // Error response template
    const errorTemplate = `#set($inputRoot = $input.path('$.errorMessage'))
#set($context = $context)

{
    "error": "PROCESSING_ERROR",
    "message": #if($inputRoot)"$util.escapeJavaScript($inputRoot)"#{else}"An error occurred while processing your request"#end,
    "details": [
        {
            "field": "request",
            "code": "LAMBDA_EXECUTION_ERROR",
            "message": "Backend service encountered an error"
        }
    ],
    "timestamp": "$context.requestTime",
    "path": "$context.resourcePath",
    "requestId": "$context.requestId"
}`;

    // Create Lambda integration
    const lambdaIntegration = new apigateway.LambdaIntegration(
      this.dataProcessorFunction,
      {
        proxy: false,
        passthroughBehavior: apigateway.PassthroughBehavior.NEVER,
        requestTemplates: {
          'application/json': requestTemplate,
        },
        integrationResponses: [
          {
            statusCode: '200',
            responseTemplates: {
              'application/json': responseTemplate,
            },
          },
          {
            statusCode: '500',
            selectionPattern: '.*"statusCode": 500.*',
            responseTemplates: {
              'application/json': errorTemplate,
            },
          },
        ],
      }
    );

    // Create POST method
    const postMethod = resource.addMethod('POST', lambdaIntegration, {
      requestValidator: requestValidator,
      requestModels: {
        'application/json': userCreateRequestModel,
      },
      methodResponses: [
        {
          statusCode: '200',
          responseModels: {
            'application/json': userResponseModel,
          },
        },
        {
          statusCode: '400',
          responseModels: {
            'application/json': errorResponseModel,
          },
        },
        {
          statusCode: '500',
          responseModels: {
            'application/json': errorResponseModel,
          },
        },
      ],
    });

    // Grant API Gateway permission to invoke Lambda
    this.dataProcessorFunction.addPermission('ApiGatewayInvokePermission', {
      principal: new iam.ServicePrincipal('apigateway.amazonaws.com'),
      action: 'lambda:InvokeFunction',
      sourceArn: this.transformationApi.arnForExecuteApi(),
    });
  }

  /**
   * Configure GET method with query parameter transformation
   */
  private configureGetMethod(resource: apigateway.Resource): void {
    const userResponseModel = (this as any).userResponseModel;
    const errorResponseModel = (this as any).errorResponseModel;

    // Query parameter transformation template
    const getRequestTemplate = `{
    "operation": "list_users",
    "pagination": {
        "limit": #if($input.params('limit'))$input.params('limit')#{else}10#end,
        "offset": #if($input.params('offset'))$input.params('offset')#{else}0#end
    },
    #if($input.params('filter'))
    "filters": {
        #set($filterParam = $input.params('filter'))
        #if($filterParam.contains(':'))
            #set($filterParts = $filterParam.split(':'))
            "$util.escapeJavaScript($filterParts[0])": "$util.escapeJavaScript($filterParts[1])"
        #else
            "search": "$util.escapeJavaScript($filterParam)"
        #end
    },
    #end
    #if($input.params('sort'))
    "sorting": {
        #set($sortParam = $input.params('sort'))
        #if($sortParam.startsWith('-'))
            "field": "$util.escapeJavaScript($sortParam.substring(1))",
            "direction": "desc"
        #else
            "field": "$util.escapeJavaScript($sortParam)",
            "direction": "asc"
        #end
    },
    #end
    "request_context": {
        "request_id": "$context.requestId",
        "source_ip": "$context.identity.sourceIp",
        "user_agent": "$util.escapeJavaScript($context.identity.userAgent)"
    }
}`;

    // Response transformation for GET
    const getResponseTemplate = `#set($inputRoot = $input.path('$'))
#set($context = $context)

{
    "success": true,
    "data": {
        "users": #if($inputRoot.users)$input.json('$.users')#{else}[]#end,
        "pagination": {
            "limit": #if($inputRoot.pagination.limit)$inputRoot.pagination.limit#{else}10#end,
            "offset": #if($inputRoot.pagination.offset)$inputRoot.pagination.offset#{else}0#end,
            "total": #if($inputRoot.pagination.total)$inputRoot.pagination.total#{else}0#end
        },
        "filters": #if($inputRoot.filters)$input.json('$.filters')#{else}{}#end,
        "sorting": #if($inputRoot.sorting)$input.json('$.sorting')#{else}{}#end
    },
    "metadata": {
        "requestId": "$context.requestId",
        "timestamp": "$context.requestTime",
        "version": "1.0"
    },
    "links": {
        "self": "https://$context.domainName/$context.stage/users",
        "next": #if($inputRoot.pagination.hasNext)"https://$context.domainName/$context.stage/users?offset=$inputRoot.pagination.nextOffset"#{else}null#end,
        "prev": #if($inputRoot.pagination.hasPrev)"https://$context.domainName/$context.stage/users?offset=$inputRoot.pagination.prevOffset"#{else}null#end
    }
}`;

    // Create Lambda integration for GET
    const getLambdaIntegration = new apigateway.LambdaIntegration(
      this.dataProcessorFunction,
      {
        proxy: false,
        passthroughBehavior: apigateway.PassthroughBehavior.NEVER,
        requestTemplates: {
          'application/json': getRequestTemplate,
        },
        integrationResponses: [
          {
            statusCode: '200',
            responseTemplates: {
              'application/json': getResponseTemplate,
            },
          },
        ],
      }
    );

    // Create GET method
    const getMethod = resource.addMethod('GET', getLambdaIntegration, {
      requestParameters: {
        'method.request.querystring.limit': false,
        'method.request.querystring.offset': false,
        'method.request.querystring.filter': false,
        'method.request.querystring.sort': false,
      },
      methodResponses: [
        {
          statusCode: '200',
          responseModels: {
            'application/json': userResponseModel,
          },
        },
        {
          statusCode: '400',
          responseModels: {
            'application/json': errorResponseModel,
          },
        },
      ],
    });
  }

  /**
   * Configure custom gateway responses for comprehensive error handling
   */
  private configureGatewayResponses(api: apigateway.RestApi): void {
    const errorResponseModel = (this as any).errorResponseModel;

    // Validation error response
    const validationErrorTemplate = `{
    "error": "VALIDATION_ERROR",
    "message": "Request validation failed",
    "details": [
        #foreach($error in $context.error.validationErrorString.split(','))
        {
            "field": #if($error.contains('Invalid request body'))"body"#{elseif($error.contains('required'))$error.split("'")[1]#{else}"unknown"#end,
            "code": "VALIDATION_FAILED",
            "message": "$util.escapeJavaScript($error.trim())"
        }#if($foreach.hasNext),#end
        #end
    ],
    "timestamp": "$context.requestTime",
    "path": "$context.resourcePath",
    "requestId": "$context.requestId"
}`;

    // Configure gateway response for bad request body
    new apigateway.GatewayResponse(this, 'BadRequestBodyResponse', {
      restApi: api,
      type: apigateway.ResponseType.BAD_REQUEST_BODY,
      statusCode: '400',
      responseHeaders: {
        'Content-Type': "'application/json'",
      },
      templates: {
        'application/json': validationErrorTemplate,
      },
    });

    // Configure gateway response for unauthorized
    new apigateway.GatewayResponse(this, 'UnauthorizedResponse', {
      restApi: api,
      type: apigateway.ResponseType.UNAUTHORIZED,
      statusCode: '401',
      responseHeaders: {
        'Content-Type': "'application/json'",
      },
      templates: {
        'application/json': `{
    "error": "UNAUTHORIZED",
    "message": "Authentication required",
    "timestamp": "$context.requestTime",
    "path": "$context.resourcePath",
    "requestId": "$context.requestId"
}`,
      },
    });

    // Configure gateway response for missing authentication token
    new apigateway.GatewayResponse(this, 'MissingAuthenticationTokenResponse', {
      restApi: api,
      type: apigateway.ResponseType.MISSING_AUTHENTICATION_TOKEN,
      statusCode: '401',
      responseHeaders: {
        'Content-Type': "'application/json'",
      },
      templates: {
        'application/json': `{
    "error": "MISSING_AUTHENTICATION_TOKEN",
    "message": "Authentication token required",
    "timestamp": "$context.requestTime",
    "path": "$context.resourcePath",
    "requestId": "$context.requestId"
}`,
      },
    });

    // Configure gateway response for throttling
    new apigateway.GatewayResponse(this, 'ThrottleResponse', {
      restApi: api,
      type: apigateway.ResponseType.THROTTLED,
      statusCode: '429',
      responseHeaders: {
        'Content-Type': "'application/json'",
      },
      templates: {
        'application/json': `{
    "error": "THROTTLED",
    "message": "Request rate limit exceeded",
    "timestamp": "$context.requestTime",
    "path": "$context.resourcePath",
    "requestId": "$context.requestId"
}`,
      },
    });
  }

  /**
   * Create CloudWatch log group for API Gateway
   */
  private createCloudWatchLogGroup(): void {
    const logGroup = new logs.LogGroup(this, 'ApiGatewayLogGroup', {
      logGroupName: `/aws/apigateway/${this.transformationApi.restApiId}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    cdk.Tags.of(logGroup).add('Purpose', 'API Gateway Logs');
    cdk.Tags.of(logGroup).add('Environment', 'Transformation Demo');
  }

  /**
   * Create CloudFormation outputs for important values
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'ApiEndpoint', {
      value: this.transformationApi.url,
      description: 'API Gateway endpoint URL',
      exportName: `${this.stackName}-ApiEndpoint`,
    });

    new cdk.CfnOutput(this, 'ApiId', {
      value: this.transformationApi.restApiId,
      description: 'API Gateway REST API ID',
      exportName: `${this.stackName}-ApiId`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: this.dataProcessorFunction.functionName,
      description: 'Lambda function name for data processing',
      exportName: `${this.stackName}-LambdaFunctionName`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: this.dataProcessorFunction.functionArn,
      description: 'Lambda function ARN',
      exportName: `${this.stackName}-LambdaFunctionArn`,
    });

    new cdk.CfnOutput(this, 'S3BucketName', {
      value: this.dataBucket.bucketName,
      description: 'S3 bucket name for data storage',
      exportName: `${this.stackName}-S3BucketName`,
    });

    new cdk.CfnOutput(this, 'S3BucketArn', {
      value: this.dataBucket.bucketArn,
      description: 'S3 bucket ARN',
      exportName: `${this.stackName}-S3BucketArn`,
    });
  }
}

/**
 * CDK Application
 */
const app = new cdk.App();

// Create the transformation stack
new RequestResponseTransformationStack(app, 'RequestResponseTransformationStack', {
  description: 'Request/Response transformation with VTL templates and custom models',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'RequestResponseTransformation',
    Environment: 'Demo',
    Purpose: 'API Gateway VTL Templates',
  },
});

// Synthesize the application
app.synth();