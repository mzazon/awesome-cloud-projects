#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as verifiedpermissions from 'aws-cdk-lib/aws-verifiedpermissions';
import { Construct } from 'constructs';
import * as path from 'path';

/**
 * Main CDK Stack for Fine-Grained API Authorization
 * 
 * This stack implements attribute-based access control (ABAC) using:
 * - Amazon Cognito for user identity and custom attributes
 * - Amazon Verified Permissions with Cedar policies for authorization
 * - API Gateway with Lambda authorizer for endpoint protection
 * - DynamoDB for document storage
 * - Lambda functions for business logic
 */
export class FineGrainedApiAuthorizationStack extends cdk.Stack {
  public readonly userPool: cognito.UserPool;
  public readonly userPoolClient: cognito.UserPoolClient;
  public readonly policyStore: verifiedpermissions.CfnPolicyStore;
  public readonly documentsTable: dynamodb.Table;
  public readonly api: apigateway.RestApi;
  public readonly apiEndpoint: string;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8);

    // Create DynamoDB table for document storage
    this.documentsTable = this.createDocumentsTable(uniqueSuffix);

    // Create Cognito User Pool with custom attributes
    const { userPool, userPoolClient } = this.createCognitoResources(uniqueSuffix);
    this.userPool = userPool;
    this.userPoolClient = userPoolClient;

    // Create Verified Permissions policy store and policies
    const { policyStore, identitySource } = this.createVerifiedPermissionsResources();
    this.policyStore = policyStore;

    // Create Lambda functions
    const { authorizerFunction, businessFunction } = this.createLambdaFunctions(
      uniqueSuffix,
      policyStore.attrPolicyStoreId,
      userPool.userPoolId,
      userPoolClient.userPoolClientId,
      this.documentsTable.tableName
    );

    // Create API Gateway with custom authorization
    this.api = this.createApiGateway(uniqueSuffix, authorizerFunction, businessFunction);
    this.apiEndpoint = this.api.url;

    // Create test users with different attributes
    this.createTestUsers();

    // Output important values
    this.createOutputs();
  }

  /**
   * Creates DynamoDB table for storing document metadata
   */
  private createDocumentsTable(uniqueSuffix: string): dynamodb.Table {
    const table = new dynamodb.Table(this, 'DocumentsTable', {
      tableName: `Documents-${uniqueSuffix}`,
      partitionKey: {
        name: 'documentId',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      pointInTimeRecovery: true,
    });

    // Add tags for identification
    cdk.Tags.of(table).add('Purpose', 'VerifiedPermissionsDemo');
    cdk.Tags.of(table).add('Component', 'DocumentStorage');

    return table;
  }

  /**
   * Creates Cognito User Pool with custom attributes for ABAC
   */
  private createCognitoResources(uniqueSuffix: string): {
    userPool: cognito.UserPool;
    userPoolClient: cognito.UserPoolClient;
  } {
    // Create User Pool with custom attributes for department and role
    const userPool = new cognito.UserPool(this, 'UserPool', {
      userPoolName: `DocManagement-UserPool-${uniqueSuffix}`,
      selfSignUpEnabled: false,
      signInAliases: {
        email: true,
      },
      autoVerify: {
        email: true,
      },
      passwordPolicy: {
        minLength: 8,
        requireLowercase: true,
        requireUppercase: true,
        requireDigits: true,
        requireSymbols: false,
      },
      customAttributes: {
        department: new cognito.StringAttribute({
          description: 'User department for authorization',
          mutable: true,
        }),
        role: new cognito.StringAttribute({
          description: 'User role for authorization',
          mutable: true,
        }),
      },
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create User Pool Client
    const userPoolClient = new cognito.UserPoolClient(this, 'UserPoolClient', {
      userPool,
      userPoolClientName: 'DocManagement-Client',
      generateSecret: true,
      authFlows: {
        adminUserPassword: true,
        userPassword: true,
      },
      preventUserExistenceErrors: true,
    });

    return { userPool, userPoolClient };
  }

  /**
   * Creates Verified Permissions policy store and Cedar policies
   */
  private createVerifiedPermissionsResources(): {
    policyStore: verifiedpermissions.CfnPolicyStore;
    identitySource: verifiedpermissions.CfnIdentitySource;
  } {
    // Create policy store for authorization rules
    const policyStore = new verifiedpermissions.CfnPolicyStore(this, 'PolicyStore', {
      description: 'Document Management Authorization Policies',
      validationSettings: {
        mode: 'STRICT',
      },
    });

    // Create identity source linking Cognito to Verified Permissions
    const identitySource = new verifiedpermissions.CfnIdentitySource(this, 'IdentitySource', {
      policyStoreId: policyStore.attrPolicyStoreId,
      configuration: {
        cognitoUserPoolConfiguration: {
          userPoolArn: this.userPool.userPoolArn,
          clientIds: [this.userPoolClient.userPoolClientId],
        },
      },
      principalEntityType: 'User',
    });

    // Create Cedar policies for fine-grained authorization
    this.createCedarPolicies(policyStore);

    return { policyStore, identitySource };
  }

  /**
   * Creates Cedar authorization policies
   */
  private createCedarPolicies(policyStore: verifiedpermissions.CfnPolicyStore): void {
    // Policy for document viewing based on department or management role
    new verifiedpermissions.CfnPolicy(this, 'ViewDocumentPolicy', {
      policyStoreId: policyStore.attrPolicyStoreId,
      definition: {
        static: {
          description: 'Allow document viewing based on department or management role',
          statement: `permit(
            principal,
            action == Action::"ViewDocument",
            resource
          ) when {
            principal.department == resource.department ||
            principal.role == "Manager" ||
            principal.role == "Admin"
          };`,
        },
      },
    });

    // Policy for document editing based on ownership and role
    new verifiedpermissions.CfnPolicy(this, 'EditDocumentPolicy', {
      policyStoreId: policyStore.attrPolicyStoreId,
      definition: {
        static: {
          description: 'Allow document editing for owners, department managers, or admins',
          statement: `permit(
            principal,
            action == Action::"EditDocument",
            resource
          ) when {
            (principal.sub == resource.owner) ||
            (principal.role == "Manager" && principal.department == resource.department) ||
            principal.role == "Admin"
          };`,
        },
      },
    });

    // Policy for document deletion - admin only
    new verifiedpermissions.CfnPolicy(this, 'DeleteDocumentPolicy', {
      policyStoreId: policyStore.attrPolicyStoreId,
      definition: {
        static: {
          description: 'Allow document deletion for admins only',
          statement: `permit(
            principal,
            action == Action::"DeleteDocument",
            resource
          ) when {
            principal.role == "Admin"
          };`,
        },
      },
    });
  }

  /**
   * Creates Lambda functions for authorization and business logic
   */
  private createLambdaFunctions(
    uniqueSuffix: string,
    policyStoreId: string,
    userPoolId: string,
    userPoolClientId: string,
    documentsTableName: string
  ): {
    authorizerFunction: lambda.Function;
    businessFunction: lambda.Function;
  } {
    // Create IAM role for Lambda functions
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `VerifiedPermissions-Lambda-Role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Add Verified Permissions policy
    lambdaRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['verifiedpermissions:IsAuthorizedWithToken'],
        resources: [policyStore.attrPolicyStoreArn],
      })
    );

    // Add DynamoDB permissions
    lambdaRole.addToPolicy(
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
        resources: [this.documentsTable.tableArn],
      })
    );

    // Create Lambda authorizer function
    const authorizerFunction = new lambda.Function(this, 'AuthorizerFunction', {
      functionName: `DocManagement-Authorizer-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(this.getAuthorizerCode()),
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      role: lambdaRole,
      environment: {
        POLICY_STORE_ID: policyStoreId,
        USER_POOL_ID: userPoolId,
        USER_POOL_CLIENT_ID: userPoolClientId,
        AWS_REGION: this.region,
      },
    });

    // Create business logic Lambda function
    const businessFunction = new lambda.Function(this, 'BusinessFunction', {
      functionName: `DocManagement-Business-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(this.getBusinessLogicCode()),
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      role: lambdaRole,
      environment: {
        DOCUMENTS_TABLE: documentsTableName,
      },
    });

    return { authorizerFunction, businessFunction };
  }

  /**
   * Creates API Gateway with custom authorization
   */
  private createApiGateway(
    uniqueSuffix: string,
    authorizerFunction: lambda.Function,
    businessFunction: lambda.Function
  ): apigateway.RestApi {
    // Create REST API
    const api = new apigateway.RestApi(this, 'DocumentManagementApi', {
      restApiName: `DocManagement-API-${uniqueSuffix}`,
      description: 'Document Management API with Verified Permissions',
      endpointConfiguration: {
        types: [apigateway.EndpointType.REGIONAL],
      },
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'Authorization'],
      },
    });

    // Create custom authorizer
    const authorizer = new apigateway.TokenAuthorizer(this, 'VerifiedPermissionsAuthorizer', {
      handler: authorizerFunction,
      identitySource: 'method.request.header.Authorization',
      authorizerName: 'VerifiedPermissionsAuthorizer',
      resultsCacheTtl: cdk.Duration.minutes(5),
    });

    // Create API resources and methods
    const documentsResource = api.root.addResource('documents');
    const documentResource = documentsResource.addResource('{documentId}');

    // Lambda integration
    const lambdaIntegration = new apigateway.LambdaIntegration(businessFunction, {
      proxy: true,
    });

    // Add methods with authorization
    documentsResource.addMethod('POST', lambdaIntegration, {
      authorizer,
      authorizationType: apigateway.AuthorizationType.CUSTOM,
    });

    documentResource.addMethod('GET', lambdaIntegration, {
      authorizer,
      authorizationType: apigateway.AuthorizationType.CUSTOM,
    });

    documentResource.addMethod('PUT', lambdaIntegration, {
      authorizer,
      authorizationType: apigateway.AuthorizationType.CUSTOM,
    });

    documentResource.addMethod('DELETE', lambdaIntegration, {
      authorizer,
      authorizationType: apigateway.AuthorizationType.CUSTOM,
    });

    return api;
  }

  /**
   * Creates test users with different attributes for demonstration
   */
  private createTestUsers(): void {
    // Note: In production, user creation should be handled through proper user management flows
    // This is for demonstration purposes only

    // Admin user
    new cognito.CfnUserPoolUser(this, 'AdminUser', {
      userPoolId: this.userPool.userPoolId,
      username: 'admin@company.com',
      userAttributes: [
        { name: 'email', value: 'admin@company.com' },
        { name: 'custom:department', value: 'IT' },
        { name: 'custom:role', value: 'Admin' },
      ],
      messageAction: 'SUPPRESS',
    });

    // Manager user
    new cognito.CfnUserPoolUser(this, 'ManagerUser', {
      userPoolId: this.userPool.userPoolId,
      username: 'manager@company.com',
      userAttributes: [
        { name: 'email', value: 'manager@company.com' },
        { name: 'custom:department', value: 'Sales' },
        { name: 'custom:role', value: 'Manager' },
      ],
      messageAction: 'SUPPRESS',
    });

    // Employee user
    new cognito.CfnUserPoolUser(this, 'EmployeeUser', {
      userPoolId: this.userPool.userPoolId,
      username: 'employee@company.com',
      userAttributes: [
        { name: 'email', value: 'employee@company.com' },
        { name: 'custom:department', value: 'Sales' },
        { name: 'custom:role', value: 'Employee' },
      ],
      messageAction: 'SUPPRESS',
    });
  }

  /**
   * Creates CloudFormation outputs
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'UserPoolId', {
      value: this.userPool.userPoolId,
      description: 'Cognito User Pool ID',
      exportName: `${this.stackName}-UserPoolId`,
    });

    new cdk.CfnOutput(this, 'UserPoolClientId', {
      value: this.userPoolClient.userPoolClientId,
      description: 'Cognito User Pool Client ID',
      exportName: `${this.stackName}-UserPoolClientId`,
    });

    new cdk.CfnOutput(this, 'PolicyStoreId', {
      value: this.policyStore.attrPolicyStoreId,
      description: 'Verified Permissions Policy Store ID',
      exportName: `${this.stackName}-PolicyStoreId`,
    });

    new cdk.CfnOutput(this, 'ApiEndpoint', {
      value: this.api.url,
      description: 'API Gateway endpoint URL',
      exportName: `${this.stackName}-ApiEndpoint`,
    });

    new cdk.CfnOutput(this, 'DocumentsTableName', {
      value: this.documentsTable.tableName,
      description: 'DynamoDB table name for documents',
      exportName: `${this.stackName}-DocumentsTableName`,
    });
  }

  /**
   * Returns the Lambda authorizer function code
   */
  private getAuthorizerCode(): string {
    return `
import json
import boto3
import jwt
from jwt import PyJWKSClient
import os
import urllib.request

verifiedpermissions = boto3.client('verifiedpermissions')
policy_store_id = os.environ['POLICY_STORE_ID']
user_pool_id = os.environ['USER_POOL_ID']
region = os.environ['AWS_REGION']

def lambda_handler(event, context):
    try:
        # Extract token from Authorization header
        token = event['authorizationToken'].replace('Bearer ', '')
        
        # Decode JWT token to get user attributes
        jwks_url = f'https://cognito-idp.{region}.amazonaws.com/{user_pool_id}/.well-known/jwks.json'
        jwks_client = PyJWKSClient(jwks_url)
        signing_key = jwks_client.get_signing_key_from_jwt(token)
        
        decoded_token = jwt.decode(
            token,
            signing_key.key,
            algorithms=['RS256'],
            audience=os.environ.get('USER_POOL_CLIENT_ID')
        )
        
        # Extract resource and action from method ARN
        method_arn = event['methodArn']
        resource_parts = method_arn.split(':')
        api_parts = resource_parts[5].split('/')
        
        http_method = api_parts[1]
        resource_path = '/'.join(api_parts[2:])
        
        # Map HTTP methods to actions
        action_map = {
            'GET': 'ViewDocument',
            'PUT': 'EditDocument',
            'POST': 'EditDocument',
            'DELETE': 'DeleteDocument'
        }
        
        action = action_map.get(http_method, 'ViewDocument')
        
        # Extract document ID from path
        document_id = resource_path.split('/')[-1] if resource_path else 'unknown'
        
        # Make authorization request to Verified Permissions
        response = verifiedpermissions.is_authorized_with_token(
            policyStoreId=policy_store_id,
            identityToken=token,
            action={
                'actionType': 'Action',
                'actionId': action
            },
            resource={
                'entityType': 'Document',
                'entityId': document_id
            }
        )
        
        # Generate policy based on decision
        effect = 'Allow' if response['decision'] == 'ALLOW' else 'Deny'
        
        return {
            'principalId': decoded_token['sub'],
            'policyDocument': {
                'Version': '2012-10-17',
                'Statement': [{
                    'Action': 'execute-api:Invoke',
                    'Effect': effect,
                    'Resource': event['methodArn']
                }]
            },
            'context': {
                'userId': decoded_token['sub'],
                'department': decoded_token.get('custom:department', ''),
                'role': decoded_token.get('custom:role', ''),
                'authDecision': response['decision']
            }
        }
        
    except Exception as e:
        print(f"Authorization error: {str(e)}")
        return {
            'principalId': 'unknown',
            'policyDocument': {
                'Version': '2012-10-17',
                'Statement': [{
                    'Action': 'execute-api:Invoke',
                    'Effect': 'Deny',
                    'Resource': event['methodArn']
                }]
            }
        }
`;
  }

  /**
   * Returns the business logic Lambda function code
   */
  private getBusinessLogicCode(): string {
    return `
import json
import boto3
import uuid
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DOCUMENTS_TABLE'])

def lambda_handler(event, context):
    try:
        # Extract user context from authorizer
        user_context = event['requestContext']['authorizer']
        user_id = user_context['userId']
        department = user_context['department']
        role = user_context['role']
        
        # Get HTTP method and document ID
        http_method = event['httpMethod']
        document_id = event['pathParameters'].get('documentId') if event.get('pathParameters') else None
        
        if http_method == 'GET' and document_id:
            # Retrieve specific document
            response = table.get_item(Key={'documentId': document_id})
            if 'Item' in response:
                return {
                    'statusCode': 200,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps(response['Item'])
                }
            else:
                return {
                    'statusCode': 404,
                    'body': json.dumps({'error': 'Document not found'})
                }
                
        elif http_method == 'GET':
            # List documents (simplified - in production, apply filtering)
            response = table.scan()
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps(response['Items'])
            }
            
        elif http_method == 'POST':
            # Create new document
            body = json.loads(event['body'])
            document = {
                'documentId': str(uuid.uuid4()),
                'title': body['title'],
                'content': body['content'],
                'owner': user_id,
                'department': department,
                'createdAt': datetime.utcnow().isoformat(),
                'updatedAt': datetime.utcnow().isoformat()
            }
            
            table.put_item(Item=document)
            return {
                'statusCode': 201,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps(document)
            }
            
        elif http_method == 'PUT' and document_id:
            # Update existing document
            body = json.loads(event['body'])
            response = table.update_item(
                Key={'documentId': document_id},
                UpdateExpression='SET title = :title, content = :content, updatedAt = :updated',
                ExpressionAttributeValues={
                    ':title': body['title'],
                    ':content': body['content'],
                    ':updated': datetime.utcnow().isoformat()
                },
                ReturnValues='ALL_NEW'
            )
            
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps(response['Attributes'])
            }
            
        elif http_method == 'DELETE' and document_id:
            # Delete document
            table.delete_item(Key={'documentId': document_id})
            return {
                'statusCode': 204,
                'body': ''
            }
            
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Invalid request'})
            }
            
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
`;
  }
}

/**
 * Main CDK Application
 */
const app = new cdk.App();

// Get deployment environment from context or use defaults
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
};

// Create the main stack
new FineGrainedApiAuthorizationStack(app, 'FineGrainedApiAuthorizationStack', {
  env,
  description: 'CDK Stack for Fine-Grained API Authorization with Verified Permissions',
  tags: {
    Project: 'FineGrainedApiAuthorization',
    Environment: 'Demo',
    CostCenter: 'Development',
  },
});

// Synthesize the CloudFormation template
app.synth();