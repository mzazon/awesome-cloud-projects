#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as certificatemanager from 'aws-cdk-lib/aws-certificatemanager';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as route53targets from 'aws-cdk-lib/aws-route53-targets';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Configuration interface for the API Gateway Custom Domain stack
 */
interface ApiGatewayCustomDomainProps extends cdk.StackProps {
  /**
   * The domain name for the API (e.g., 'api.example.com')
   */
  readonly apiDomainName: string;
  
  /**
   * The base domain name (e.g., 'example.com')
   */
  readonly baseDomainName: string;
  
  /**
   * Whether to create a new hosted zone or use existing one
   * @default false
   */
  readonly createHostedZone?: boolean;
  
  /**
   * Whether to create a new certificate or use existing one
   * @default true
   */
  readonly createCertificate?: boolean;
  
  /**
   * Existing certificate ARN if createCertificate is false
   */
  readonly existingCertificateArn?: string;
  
  /**
   * Environment name for tagging and naming
   * @default 'dev'
   */
  readonly environment?: string;
}

/**
 * CDK Stack for API Gateway with Custom Domain Names
 * 
 * This stack creates:
 * - Lambda functions for API backend and custom authorizer
 * - API Gateway REST API with custom domain
 * - SSL certificate through ACM
 * - Route 53 DNS records
 * - Proper IAM roles and policies
 * - Request validation and throttling
 */
export class ApiGatewayCustomDomainStack extends cdk.Stack {
  public readonly api: apigateway.RestApi;
  public readonly customDomain: apigateway.DomainName;
  public readonly certificate: certificatemanager.ICertificate;
  public readonly hostedZone: route53.IHostedZone;

  constructor(scope: Construct, id: string, props: ApiGatewayCustomDomainProps) {
    super(scope, id, props);

    const environment = props.environment || 'dev';

    // Create or import hosted zone
    this.hostedZone = this.createOrImportHostedZone(props);

    // Create or import SSL certificate
    this.certificate = this.createOrImportCertificate(props);

    // Create Lambda execution role
    const lambdaRole = this.createLambdaExecutionRole();

    // Create Lambda functions
    const { backendFunction, authorizerFunction } = this.createLambdaFunctions(lambdaRole, environment);

    // Create API Gateway with custom authorizer
    this.api = this.createApiGateway(authorizerFunction, environment);

    // Create custom domain
    this.customDomain = this.createCustomDomain(props.apiDomainName);

    // Configure API resources and methods
    this.configureApiResources(backendFunction, authorizerFunction);

    // Create DNS record
    this.createDnsRecord(props.apiDomainName);

    // Configure API stages with throttling
    this.configureApiStages();

    // Create base path mappings
    this.createBasePathMappings(props.apiDomainName);

    // Add outputs
    this.addOutputs(props.apiDomainName);
  }

  /**
   * Create or import Route 53 hosted zone
   */
  private createOrImportHostedZone(props: ApiGatewayCustomDomainProps): route53.IHostedZone {
    if (props.createHostedZone) {
      return new route53.HostedZone(this, 'HostedZone', {
        zoneName: props.baseDomainName,
        comment: `Hosted zone for ${props.baseDomainName} - API Gateway Custom Domain`,
      });
    } else {
      return route53.HostedZone.fromLookup(this, 'ExistingHostedZone', {
        domainName: props.baseDomainName,
      });
    }
  }

  /**
   * Create or import SSL certificate
   */
  private createOrImportCertificate(props: ApiGatewayCustomDomainProps): certificatemanager.ICertificate {
    if (props.createCertificate !== false) {
      return new certificatemanager.Certificate(this, 'ApiCertificate', {
        domainName: props.apiDomainName,
        subjectAlternativeNames: [`*.${props.apiDomainName}`],
        validation: certificatemanager.CertificateValidation.fromDns(this.hostedZone),
      });
    } else if (props.existingCertificateArn) {
      return certificatemanager.Certificate.fromCertificateArn(
        this,
        'ExistingCertificate',
        props.existingCertificateArn
      );
    } else {
      throw new Error('Either createCertificate must be true or existingCertificateArn must be provided');
    }
  }

  /**
   * Create IAM role for Lambda functions
   */
  private createLambdaExecutionRole(): iam.Role {
    return new iam.Role(this, 'LambdaExecutionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for API Gateway Lambda functions',
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
              ],
              resources: ['arn:aws:logs:*:*:*'],
            }),
          ],
        }),
      },
    });
  }

  /**
   * Create Lambda functions for API backend and authorizer
   */
  private createLambdaFunctions(role: iam.Role, environment: string) {
    // Backend Lambda function
    const backendFunction = new lambda.Function(this, 'BackendFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: role,
      description: 'Pet Store API backend function',
      environment: {
        ENVIRONMENT: environment,
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
import json
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Pet Store API backend handler
    Handles GET and POST requests for /pets endpoint
    """
    logger.info(f"Event: {json.dumps(event)}")
    logger.info(f"Environment: {os.environ.get('ENVIRONMENT', 'unknown')}")
    
    # Extract HTTP method and path
    http_method = event.get('httpMethod', 'GET')
    path = event.get('path', '/')
    
    # CORS headers
    cors_headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'OPTIONS,GET,POST,PUT,DELETE'
    }
    
    try:
        # Handle OPTIONS requests for CORS
        if http_method == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': cors_headers,
                'body': json.dumps({'message': 'CORS preflight'})
            }
        
        # Sample API responses
        if path == '/pets' and http_method == 'GET':
            return {
                'statusCode': 200,
                'headers': cors_headers,
                'body': json.dumps({
                    'pets': [
                        {'id': 1, 'name': 'Buddy', 'type': 'dog', 'age': 3},
                        {'id': 2, 'name': 'Whiskers', 'type': 'cat', 'age': 2},
                        {'id': 3, 'name': 'Goldie', 'type': 'fish', 'age': 1}
                    ],
                    'environment': os.environ.get('ENVIRONMENT', 'unknown'),
                    'timestamp': context.aws_request_id
                })
            }
        elif path == '/pets' and http_method == 'POST':
            # Parse request body
            body = json.loads(event.get('body', '{}'))
            pet_name = body.get('name', 'Unknown')
            pet_type = body.get('type', 'unknown')
            
            return {
                'statusCode': 201,
                'headers': cors_headers,
                'body': json.dumps({
                    'message': 'Pet created successfully',
                    'pet': {
                        'id': 4,
                        'name': pet_name,
                        'type': pet_type,
                        'age': body.get('age', 0)
                    },
                    'environment': os.environ.get('ENVIRONMENT', 'unknown')
                })
            }
        else:
            return {
                'statusCode': 404,
                'headers': cors_headers,
                'body': json.dumps({
                    'error': 'Not Found',
                    'message': f'Endpoint {http_method} {path} not found',
                    'availableEndpoints': [
                        'GET /pets - List all pets',
                        'POST /pets - Create a new pet'
                    ]
                })
            }
    
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        return {
            'statusCode': 500,
            'headers': cors_headers,
            'body': json.dumps({
                'error': 'Internal Server Error',
                'message': 'An unexpected error occurred'
            })
        }
`),
    });

    // Custom authorizer Lambda function
    const authorizerFunction = new lambda.Function(this, 'AuthorizerFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: role,
      description: 'Custom authorizer for Pet Store API',
      environment: {
        ENVIRONMENT: environment,
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
import json
import logging
import re

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Custom authorizer for API Gateway
    Validates authorization tokens and returns IAM policies
    """
    logger.info(f"Authorizer Event: {json.dumps(event)}")
    
    # Extract the authorization token and method ARN
    token = event.get('authorizationToken', '')
    method_arn = event.get('methodArn', '')
    
    try:
        # Parse method ARN to get region, account, etc.
        arn_parts = method_arn.split(':')
        api_gateway_arn = ':'.join(arn_parts[:5]) + ':*'
        
        # Token validation logic
        # In production, implement proper JWT validation or OAuth
        principal_id = 'anonymous'
        effect = 'Deny'
        
        if token == 'Bearer valid-token':
            effect = 'Allow'
            principal_id = 'user123'
        elif token == 'Bearer admin-token':
            effect = 'Allow'
            principal_id = 'admin456'
        elif token.startswith('Bearer ') and len(token) > 20:
            # For demo purposes, allow any bearer token longer than 20 chars
            effect = 'Allow'
            principal_id = 'demo-user'
        
        # Generate IAM policy document
        policy_document = {
            'Version': '2012-10-17',
            'Statement': [
                {
                    'Action': 'execute-api:Invoke',
                    'Effect': effect,
                    'Resource': api_gateway_arn
                }
            ]
        }
        
        # Context to pass to Lambda function
        context_data = {
            'userId': principal_id,
            'userRole': 'admin' if 'admin' in principal_id else 'user',
            'tokenType': 'Bearer',
            'authTime': str(context.aws_request_id)
        }
        
        response = {
            'principalId': principal_id,
            'policyDocument': policy_document,
            'context': context_data
        }
        
        logger.info(f"Authorization response: {json.dumps(response)}")
        return response
    
    except Exception as e:
        logger.error(f"Authorization error: {str(e)}")
        # Deny access on any error
        return {
            'principalId': 'error',
            'policyDocument': {
                'Version': '2012-10-17',
                'Statement': [
                    {
                        'Action': 'execute-api:Invoke',
                        'Effect': 'Deny',
                        'Resource': method_arn
                    }
                ]
            }
        }
`),
    });

    return { backendFunction, authorizerFunction };
  }

  /**
   * Create API Gateway REST API with custom authorizer
   */
  private createApiGateway(authorizerFunction: lambda.Function, environment: string): apigateway.RestApi {
    // Create CloudWatch log group for API Gateway
    const logGroup = new logs.LogGroup(this, 'ApiGatewayLogGroup', {
      logGroupName: `/aws/apigateway/petstore-api-${environment}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create REST API
    const api = new apigateway.RestApi(this, 'PetStoreApi', {
      restApiName: `petstore-api-${environment}`,
      description: 'Pet Store API with custom domain names',
      endpointConfiguration: {
        types: [apigateway.EndpointType.REGIONAL],
      },
      deployOptions: {
        stageName: 'dev',
        throttlingBurstLimit: 100,
        throttlingRateLimit: 50,
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        accessLogDestination: new apigateway.LogGroupLogDestination(logGroup),
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
      },
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: [
          'Content-Type',
          'X-Amz-Date',
          'Authorization',
          'X-Api-Key',
          'X-Amz-Security-Token',
        ],
      },
    });

    // Create custom authorizer
    const authorizer = new apigateway.TokenAuthorizer(this, 'CustomAuthorizer', {
      handler: authorizerFunction,
      identitySource: 'method.request.header.Authorization',
      authorizerName: `petstore-authorizer-${environment}`,
      resultsCacheTtl: cdk.Duration.minutes(5),
    });

    // Store authorizer reference for later use
    (api as any).customAuthorizer = authorizer;

    return api;
  }

  /**
   * Create custom domain for API Gateway
   */
  private createCustomDomain(domainName: string): apigateway.DomainName {
    return new apigateway.DomainName(this, 'CustomDomain', {
      domainName: domainName,
      certificate: this.certificate,
      endpointType: apigateway.EndpointType.REGIONAL,
      securityPolicy: apigateway.SecurityPolicy.TLS_1_2,
    });
  }

  /**
   * Configure API resources, methods, and integrations
   */
  private configureApiResources(
    backendFunction: lambda.Function,
    authorizerFunction: lambda.Function
  ): void {
    const authorizer = (this.api as any).customAuthorizer;

    // Create /pets resource
    const petsResource = this.api.root.addResource('pets');

    // Create request validator
    const requestValidator = new apigateway.RequestValidator(this, 'RequestValidator', {
      restApi: this.api,
      requestValidatorName: 'petstore-validator',
      validateRequestBody: true,
      validateRequestParameters: true,
    });

    // Add GET method for /pets
    petsResource.addMethod('GET', new apigateway.LambdaIntegration(backendFunction), {
      authorizer: authorizer,
      authorizationType: apigateway.AuthorizationType.CUSTOM,
      requestValidator: requestValidator,
    });

    // Add POST method for /pets
    petsResource.addMethod('POST', new apigateway.LambdaIntegration(backendFunction), {
      authorizer: authorizer,
      authorizationType: apigateway.AuthorizationType.CUSTOM,
      requestValidator: requestValidator,
      requestModels: {
        'application/json': new apigateway.Model(this, 'PetModel', {
          restApi: this.api,
          modelName: 'PetModel',
          description: 'Model for pet creation requests',
          schema: {
            type: apigateway.JsonSchemaType.OBJECT,
            properties: {
              name: {
                type: apigateway.JsonSchemaType.STRING,
                minLength: 1,
                maxLength: 50,
              },
              type: {
                type: apigateway.JsonSchemaType.STRING,
                enum: ['dog', 'cat', 'bird', 'fish', 'rabbit'],
              },
              age: {
                type: apigateway.JsonSchemaType.NUMBER,
                minimum: 0,
                maximum: 30,
              },
            },
            required: ['name', 'type'],
          },
        }),
      },
    });

    // Add health check endpoint
    const healthResource = this.api.root.addResource('health');
    healthResource.addMethod('GET', new apigateway.MockIntegration({
      integrationResponses: [{
        statusCode: '200',
        responseTemplates: {
          'application/json': JSON.stringify({
            status: 'healthy',
            timestamp: '$context.requestTime',
            version: '1.0.0',
          }),
        },
      }],
      requestTemplates: {
        'application/json': '{"statusCode": 200}',
      },
    }), {
      methodResponses: [{
        statusCode: '200',
        responseModels: {
          'application/json': apigateway.Model.EMPTY_MODEL,
        },
      }],
    });
  }

  /**
   * Create DNS record pointing to the custom domain
   */
  private createDnsRecord(domainName: string): void {
    new route53.ARecord(this, 'ApiDnsRecord', {
      zone: this.hostedZone,
      recordName: domainName,
      target: route53.RecordTarget.fromAlias(
        new route53targets.ApiGatewayDomain(this.customDomain)
      ),
      comment: 'DNS record for API Gateway custom domain',
    });
  }

  /**
   * Configure API stages with different throttling settings
   */
  private configureApiStages(): void {
    // Create production stage
    const prodStage = new apigateway.Stage(this, 'ProdStage', {
      deployment: this.api.latestDeployment!,
      stageName: 'prod',
      description: 'Production stage with stricter throttling',
      throttlingBurstLimit: 200,
      throttlingRateLimit: 100,
      variables: {
        environment: 'production',
        version: '1.0.0',
      },
    });

    // Update dev stage throttling
    const devStage = this.api.deploymentStage;
    devStage.addProperty('ThrottlingBurstLimit', 100);
    devStage.addProperty('ThrottlingRateLimit', 50);
  }

  /**
   * Create base path mappings for different stages
   */
  private createBasePathMappings(domainName: string): void {
    // Default mapping (empty path) points to prod stage
    new apigateway.BasePathMapping(this, 'DefaultMapping', {
      domainName: this.customDomain,
      restApi: this.api,
      stage: this.api.deploymentStage.stageName === 'dev' ? 
        this.api.root.node.findChild('ProdStage') as apigateway.Stage :
        this.api.deploymentStage,
    });

    // Version 1 mapping for prod
    new apigateway.BasePathMapping(this, 'V1Mapping', {
      domainName: this.customDomain,
      restApi: this.api,
      stage: this.api.deploymentStage.stageName === 'dev' ? 
        this.api.root.node.findChild('ProdStage') as apigateway.Stage :
        this.api.deploymentStage,
      basePath: 'v1',
    });

    // Development mapping
    new apigateway.BasePathMapping(this, 'DevMapping', {
      domainName: this.customDomain,
      restApi: this.api,
      stage: this.api.deploymentStage,
      basePath: 'v1-dev',
    });
  }

  /**
   * Add CloudFormation outputs
   */
  private addOutputs(domainName: string): void {
    new cdk.CfnOutput(this, 'ApiUrl', {
      value: `https://${domainName}`,
      description: 'API Gateway custom domain URL',
      exportName: `${this.stackName}-api-url`,
    });

    new cdk.CfnOutput(this, 'ApiUrlDev', {
      value: `https://${domainName}/v1-dev`,
      description: 'API Gateway custom domain URL for development',
      exportName: `${this.stackName}-api-url-dev`,
    });

    new cdk.CfnOutput(this, 'ApiUrlV1', {
      value: `https://${domainName}/v1`,
      description: 'API Gateway custom domain URL for version 1',
      exportName: `${this.stackName}-api-url-v1`,
    });

    new cdk.CfnOutput(this, 'DefaultApiUrl', {
      value: this.api.url,
      description: 'Default API Gateway URL',
      exportName: `${this.stackName}-default-api-url`,
    });

    new cdk.CfnOutput(this, 'HostedZoneId', {
      value: this.hostedZone.hostedZoneId,
      description: 'Route 53 Hosted Zone ID',
      exportName: `${this.stackName}-hosted-zone-id`,
    });

    new cdk.CfnOutput(this, 'CertificateArn', {
      value: this.certificate.certificateArn,
      description: 'SSL Certificate ARN',
      exportName: `${this.stackName}-certificate-arn`,
    });

    new cdk.CfnOutput(this, 'RegionalDomainName', {
      value: this.customDomain.domainNameAliasDomainName,
      description: 'Regional domain name for external DNS configuration',
      exportName: `${this.stackName}-regional-domain-name`,
    });
  }
}

/**
 * CDK App entry point
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const domainName = app.node.tryGetContext('domainName') || process.env.API_DOMAIN_NAME || 'api.example.com';
const baseDomainName = app.node.tryGetContext('baseDomainName') || process.env.BASE_DOMAIN_NAME || 'example.com';
const environment = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'dev';
const createHostedZone = app.node.tryGetContext('createHostedZone') || false;
const createCertificate = app.node.tryGetContext('createCertificate') !== false;
const existingCertificateArn = app.node.tryGetContext('existingCertificateArn') || process.env.EXISTING_CERTIFICATE_ARN;

// Validate required configuration
if (!domainName || !baseDomainName) {
  throw new Error('domainName and baseDomainName are required. Set via CDK context or environment variables.');
}

// Create the stack
new ApiGatewayCustomDomainStack(app, `ApiGatewayCustomDomainStack-${environment}`, {
  apiDomainName: domainName,
  baseDomainName: baseDomainName,
  environment: environment,
  createHostedZone: createHostedZone,
  createCertificate: createCertificate,
  existingCertificateArn: existingCertificateArn,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: `API Gateway with custom domain names for ${environment} environment`,
  tags: {
    Project: 'ApiGatewayCustomDomain',
    Environment: environment,
    ManagedBy: 'AWS-CDK',
  },
});

app.synth();