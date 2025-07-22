#!/usr/bin/env python3
"""
CDK Python Application for Fine-Grained API Authorization
with Amazon Verified Permissions and Cognito

This application deploys a complete infrastructure for attribute-based access control (ABAC)
using Amazon Verified Permissions with Cedar policies, Cognito for identity management,
and API Gateway for endpoint protection.
"""

import aws_cdk as cdk
from constructs import Construct
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_cognito as cognito,
    aws_apigateway as apigateway,
    aws_lambda as lambda_,
    aws_dynamodb as dynamodb,
    aws_iam as iam,
    aws_verifiedpermissions as verifiedpermissions,
)
import json
from typing import Dict, Any


class FineGrainedAuthStack(Stack):
    """
    CDK Stack for Fine-Grained API Authorization using Amazon Verified Permissions
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[-8:].lower()

        # Create DynamoDB table for document storage
        self.documents_table = self._create_documents_table(unique_suffix)

        # Create Cognito User Pool for identity management
        self.user_pool, self.user_pool_client = self._create_cognito_resources(unique_suffix)

        # Create Verified Permissions policy store and policies
        self.policy_store = self._create_policy_store()
        self.identity_source = self._create_identity_source()
        self._create_cedar_policies()

        # Create Lambda functions
        self.authorizer_function = self._create_authorizer_function(unique_suffix)
        self.business_function = self._create_business_function(unique_suffix)

        # Create API Gateway with custom authorization
        self.api_gateway = self._create_api_gateway(unique_suffix)

        # Create test users
        self._create_test_users()

        # Create outputs
        self._create_outputs()

    def _create_documents_table(self, suffix: str) -> dynamodb.Table:
        """Create DynamoDB table for document metadata storage"""
        table = dynamodb.Table(
            self,
            "DocumentsTable",
            table_name=f"Documents-{suffix}",
            partition_key=dynamodb.Attribute(
                name="documentId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
        )

        # Add tags
        cdk.Tags.of(table).add("Purpose", "VerifiedPermissionsDemo")

        return table

    def _create_cognito_resources(self, suffix: str) -> tuple[cognito.UserPool, cognito.UserPoolClient]:
        """Create Cognito User Pool with custom attributes for ABAC"""
        # Create User Pool with custom attributes
        user_pool = cognito.UserPool(
            self,
            "UserPool",
            user_pool_name=f"DocManagement-UserPool-{suffix}",
            self_sign_up_enabled=False,
            sign_in_aliases=cognito.SignInAliases(email=True),
            auto_verify=cognito.AutoVerifiedAttrs(email=True),
            password_policy=cognito.PasswordPolicy(
                min_length=8,
                require_uppercase=True,
                require_lowercase=True,
                require_digits=True,
                require_symbols=False,
            ),
            custom_attributes={
                "department": cognito.StringAttribute(mutable=True),
                "role": cognito.StringAttribute(mutable=True),
            },
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create User Pool Client
        user_pool_client = cognito.UserPoolClient(
            self,
            "UserPoolClient",
            user_pool=user_pool,
            user_pool_client_name="DocManagement-Client",
            auth_flows=cognito.AuthFlow(
                admin_user_password=True,
                user_password=True,
            ),
            generate_secret=True,
        )

        return user_pool, user_pool_client

    def _create_policy_store(self) -> verifiedpermissions.CfnPolicyStore:
        """Create Amazon Verified Permissions policy store"""
        policy_store = verifiedpermissions.CfnPolicyStore(
            self,
            "PolicyStore",
            description="Document Management Authorization Policies",
            validation_settings=verifiedpermissions.CfnPolicyStore.ValidationSettingsProperty(
                mode="STRICT"
            ),
        )

        return policy_store

    def _create_identity_source(self) -> verifiedpermissions.CfnIdentitySource:
        """Create identity source linking Cognito to Verified Permissions"""
        identity_source = verifiedpermissions.CfnIdentitySource(
            self,
            "IdentitySource",
            policy_store_id=self.policy_store.attr_policy_store_id,
            configuration=verifiedpermissions.CfnIdentitySource.IdentitySourceConfigurationProperty(
                cognito_user_pool_configuration=verifiedpermissions.CfnIdentitySource.CognitoUserPoolConfigurationProperty(
                    user_pool_arn=self.user_pool.user_pool_arn,
                    client_ids=[self.user_pool_client.user_pool_client_id],
                )
            ),
            principal_entity_type="User",
        )

        return identity_source

    def _create_cedar_policies(self) -> None:
        """Create Cedar authorization policies in Verified Permissions"""
        # Policy for document viewing based on department or role
        view_policy = verifiedpermissions.CfnPolicy(
            self,
            "ViewPolicy",
            policy_store_id=self.policy_store.attr_policy_store_id,
            definition=verifiedpermissions.CfnPolicy.PolicyDefinitionProperty(
                static=verifiedpermissions.CfnPolicy.StaticPolicyDefinitionProperty(
                    description="Allow document viewing based on department or management role",
                    statement="""permit(
                        principal,
                        action == Action::"ViewDocument",
                        resource
                    ) when {
                        principal.department == resource.department ||
                        principal.role == "Manager" ||
                        principal.role == "Admin"
                    };""",
                )
            ),
        )

        # Policy for document editing based on ownership and role
        edit_policy = verifiedpermissions.CfnPolicy(
            self,
            "EditPolicy",
            policy_store_id=self.policy_store.attr_policy_store_id,
            definition=verifiedpermissions.CfnPolicy.PolicyDefinitionProperty(
                static=verifiedpermissions.CfnPolicy.StaticPolicyDefinitionProperty(
                    description="Allow document editing for owners, department managers, or admins",
                    statement="""permit(
                        principal,
                        action == Action::"EditDocument",
                        resource
                    ) when {
                        (principal.sub == resource.owner) ||
                        (principal.role == "Manager" && principal.department == resource.department) ||
                        principal.role == "Admin"
                    };""",
                )
            ),
        )

        # Policy for document deletion - admin only
        delete_policy = verifiedpermissions.CfnPolicy(
            self,
            "DeletePolicy",
            policy_store_id=self.policy_store.attr_policy_store_id,
            definition=verifiedpermissions.CfnPolicy.PolicyDefinitionProperty(
                static=verifiedpermissions.CfnPolicy.StaticPolicyDefinitionProperty(
                    description="Allow document deletion for admins only",
                    statement="""permit(
                        principal,
                        action == Action::"DeleteDocument",
                        resource
                    ) when {
                        principal.role == "Admin"
                    };""",
                )
            ),
        )

    def _create_authorizer_function(self, suffix: str) -> lambda_.Function:
        """Create Lambda authorizer function for API Gateway"""
        # Create IAM role for Lambda authorizer
        authorizer_role = iam.Role(
            self,
            "AuthorizerRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "VerifiedPermissionsAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["verifiedpermissions:IsAuthorizedWithToken"],
                            resources=[
                                f"arn:aws:verifiedpermissions::{self.account}:policy-store/{self.policy_store.attr_policy_store_id}"
                            ],
                        )
                    ]
                )
            },
        )

        # Lambda function code
        authorizer_code = """
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
"""

        # Create Lambda function
        authorizer_function = lambda_.Function(
            self,
            "AuthorizerFunction",
            function_name=f"DocManagement-Authorizer-{suffix}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(authorizer_code),
            timeout=Duration.seconds(30),
            memory_size=256,
            role=authorizer_role,
            environment={
                "POLICY_STORE_ID": self.policy_store.attr_policy_store_id,
                "USER_POOL_ID": self.user_pool.user_pool_id,
                "USER_POOL_CLIENT_ID": self.user_pool_client.user_pool_client_id,
            },
        )

        return authorizer_function

    def _create_business_function(self, suffix: str) -> lambda_.Function:
        """Create business logic Lambda function for document operations"""
        # Create IAM role for business function
        business_role = iam.Role(
            self,
            "BusinessRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "DynamoDBAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "dynamodb:GetItem",
                                "dynamodb:PutItem",
                                "dynamodb:UpdateItem",
                                "dynamodb:DeleteItem",
                                "dynamodb:Scan",
                                "dynamodb:Query",
                            ],
                            resources=[self.documents_table.table_arn],
                        )
                    ]
                )
            },
        )

        # Lambda function code
        business_code = """
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
"""

        # Create Lambda function
        business_function = lambda_.Function(
            self,
            "BusinessFunction",
            function_name=f"DocManagement-Business-{suffix}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(business_code),
            timeout=Duration.seconds(30),
            memory_size=256,
            role=business_role,
            environment={
                "DOCUMENTS_TABLE": self.documents_table.table_name,
            },
        )

        return business_function

    def _create_api_gateway(self, suffix: str) -> apigateway.RestApi:
        """Create API Gateway with custom authorization"""
        # Create REST API
        api = apigateway.RestApi(
            self,
            "DocumentAPI",
            rest_api_name=f"DocManagement-API-{suffix}",
            description="Document Management API with Verified Permissions",
            endpoint_configuration=apigateway.EndpointConfiguration(
                types=[apigateway.EndpointType.REGIONAL]
            ),
        )

        # Create custom authorizer
        authorizer = apigateway.TokenAuthorizer(
            self,
            "VerifiedPermissionsAuthorizer",
            handler=self.authorizer_function,
            identity_source="method.request.header.Authorization",
            results_cache_ttl=Duration.minutes(5),
        )

        # Create resources and methods
        documents_resource = api.root.add_resource("documents")
        document_id_resource = documents_resource.add_resource("{documentId}")

        # Create integrations
        business_integration = apigateway.LambdaIntegration(
            self.business_function,
            proxy=True,
        )

        # Add methods with authorization
        documents_resource.add_method(
            "POST",
            business_integration,
            authorizer=authorizer,
        )

        document_id_resource.add_method(
            "GET",
            business_integration,
            authorizer=authorizer,
        )

        document_id_resource.add_method(
            "PUT",
            business_integration,
            authorizer=authorizer,
        )

        document_id_resource.add_method(
            "DELETE",
            business_integration,
            authorizer=authorizer,
        )

        return api

    def _create_test_users(self) -> None:
        """Create test users with different attributes for testing ABAC"""
        # Admin user
        admin_user = cognito.CfnUserPoolUser(
            self,
            "AdminUser",
            user_pool_id=self.user_pool.user_pool_id,
            username="admin@company.com",
            message_action="SUPPRESS",
            user_attributes=[
                cognito.CfnUserPoolUser.AttributeTypeProperty(
                    name="email", value="admin@company.com"
                ),
                cognito.CfnUserPoolUser.AttributeTypeProperty(
                    name="custom:department", value="IT"
                ),
                cognito.CfnUserPoolUser.AttributeTypeProperty(
                    name="custom:role", value="Admin"
                ),
            ],
        )

        # Manager user
        manager_user = cognito.CfnUserPoolUser(
            self,
            "ManagerUser",
            user_pool_id=self.user_pool.user_pool_id,
            username="manager@company.com",
            message_action="SUPPRESS",
            user_attributes=[
                cognito.CfnUserPoolUser.AttributeTypeProperty(
                    name="email", value="manager@company.com"
                ),
                cognito.CfnUserPoolUser.AttributeTypeProperty(
                    name="custom:department", value="Sales"
                ),
                cognito.CfnUserPoolUser.AttributeTypeProperty(
                    name="custom:role", value="Manager"
                ),
            ],
        )

        # Employee user
        employee_user = cognito.CfnUserPoolUser(
            self,
            "EmployeeUser",
            user_pool_id=self.user_pool.user_pool_id,
            username="employee@company.com",
            message_action="SUPPRESS",
            user_attributes=[
                cognito.CfnUserPoolUser.AttributeTypeProperty(
                    name="email", value="employee@company.com"
                ),
                cognito.CfnUserPoolUser.AttributeTypeProperty(
                    name="custom:department", value="Sales"
                ),
                cognito.CfnUserPoolUser.AttributeTypeProperty(
                    name="custom:role", value="Employee"
                ),
            ],
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources"""
        CfnOutput(
            self,
            "UserPoolId",
            value=self.user_pool.user_pool_id,
            description="Cognito User Pool ID",
        )

        CfnOutput(
            self,
            "UserPoolClientId",
            value=self.user_pool_client.user_pool_client_id,
            description="Cognito User Pool Client ID",
        )

        CfnOutput(
            self,
            "PolicyStoreId",
            value=self.policy_store.attr_policy_store_id,
            description="Verified Permissions Policy Store ID",
        )

        CfnOutput(
            self,
            "APIEndpoint",
            value=self.api_gateway.url,
            description="API Gateway endpoint URL",
        )

        CfnOutput(
            self,
            "DocumentsTableName",
            value=self.documents_table.table_name,
            description="DynamoDB Documents table name",
        )


app = cdk.App()

# Create the stack
FineGrainedAuthStack(
    app,
    "FineGrainedAuthStack",
    description="Fine-Grained API Authorization with Amazon Verified Permissions and Cognito",
)

app.synth()