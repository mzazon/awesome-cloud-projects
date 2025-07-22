#!/usr/bin/env python3
"""
CDK Python application for API Gateway with Custom Domain Names.

This application deploys a complete API Gateway setup with:
- Custom domain name with SSL certificate
- Lambda functions for API backend and custom authorizer
- Route 53 DNS configuration
- Request validation and throttling
- Multiple deployment stages (dev/prod)
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_apigateway as apigateway,
    aws_certificatemanager as acm,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_route53 as route53,
    aws_route53_targets as targets,
    aws_logs as logs,
)
from constructs import Construct


class ApiGatewayCustomDomainStack(Stack):
    """
    CDK Stack for API Gateway with Custom Domain Names.
    
    This stack creates a complete serverless API infrastructure with:
    - REST API with Lambda integration
    - Custom authorizer for security
    - SSL certificate for HTTPS
    - Custom domain with DNS routing
    - Multi-stage deployment support
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters
        self.domain_name = self.node.try_get_context("domain_name") or "example.com"
        self.api_subdomain = f"api.{self.domain_name}"
        self.api_name = self.node.try_get_context("api_name") or "petstore-api"
        
        # Create SSL certificate
        self.certificate = self._create_ssl_certificate()
        
        # Create Lambda functions
        self.api_lambda = self._create_api_lambda_function()
        self.authorizer_lambda = self._create_authorizer_lambda_function()
        
        # Create API Gateway
        self.api = self._create_api_gateway()
        
        # Create custom authorizer
        self.custom_authorizer = self._create_custom_authorizer()
        
        # Configure API resources and methods
        self._configure_api_resources()
        
        # Create deployments and stages
        self.dev_deployment = self._create_deployment("dev")
        self.prod_deployment = self._create_deployment("prod")
        
        # Create custom domain
        self.custom_domain = self._create_custom_domain()
        
        # Create base path mappings
        self._create_base_path_mappings()
        
        # Create DNS records
        self._create_dns_records()
        
        # Create outputs
        self._create_outputs()

    def _create_ssl_certificate(self) -> acm.Certificate:
        """Create SSL certificate for the custom domain."""
        return acm.Certificate(
            self,
            "ApiGatewayCertificate",
            domain_name=self.api_subdomain,
            subject_alternative_names=[f"*.{self.api_subdomain}"],
            validation=acm.CertificateValidation.from_dns(),
            certificate_name=f"{self.api_name}-certificate"
        )

    def _create_api_lambda_function(self) -> lambda_.Function:
        """Create the main API Lambda function."""
        # Create Lambda execution role
        lambda_role = iam.Role(
            self,
            "ApiLambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            description="Execution role for Pet Store API Lambda function"
        )

        # Create Lambda function
        api_function = lambda_.Function(
            self,
            "PetStoreApiFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="lambda_function.lambda_handler",
            role=lambda_role,
            code=lambda_.Code.from_inline(self._get_api_lambda_code()),
            timeout=Duration.seconds(30),
            memory_size=256,
            description="Pet Store API backend function",
            environment={
                "LOG_LEVEL": "INFO"
            },
            log_retention=logs.RetentionDays.ONE_WEEK
        )

        return api_function

    def _create_authorizer_lambda_function(self) -> lambda_.Function:
        """Create the custom authorizer Lambda function."""
        # Create Lambda execution role
        authorizer_role = iam.Role(
            self,
            "AuthorizerLambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            description="Execution role for API Gateway custom authorizer"
        )

        # Create authorizer function
        authorizer_function = lambda_.Function(
            self,
            "PetStoreAuthorizerFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="authorizer_function.lambda_handler",
            role=authorizer_role,
            code=lambda_.Code.from_inline(self._get_authorizer_lambda_code()),
            timeout=Duration.seconds(10),
            memory_size=128,
            description="Custom authorizer for Pet Store API",
            environment={
                "LOG_LEVEL": "INFO"
            },
            log_retention=logs.RetentionDays.ONE_WEEK
        )

        return authorizer_function

    def _create_api_gateway(self) -> apigateway.RestApi:
        """Create the API Gateway REST API."""
        # Create CloudWatch log group for API Gateway
        log_group = logs.LogGroup(
            self,
            "ApiGatewayLogGroup",
            log_group_name=f"/aws/apigateway/{self.api_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Create REST API
        api = apigateway.RestApi(
            self,
            "PetStoreApi",
            rest_api_name=self.api_name,
            description="Pet Store API with custom domain names",
            endpoint_configuration=apigateway.EndpointConfiguration(
                types=[apigateway.EndpointType.REGIONAL]
            ),
            cloud_watch_role=True,
            deploy=False,  # We'll handle deployment manually
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=apigateway.Cors.ALL_ORIGINS,
                allow_methods=apigateway.Cors.ALL_METHODS,
                allow_headers=["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key"]
            ),
            policy=iam.PolicyDocument(
                statements=[
                    iam.PolicyStatement(
                        effect=iam.Effect.ALLOW,
                        principals=[iam.AnyPrincipal()],
                        actions=["execute-api:Invoke"],
                        resources=["*"]
                    )
                ]
            )
        )

        return api

    def _create_custom_authorizer(self) -> apigateway.TokenAuthorizer:
        """Create custom authorizer for the API."""
        return apigateway.TokenAuthorizer(
            self,
            "PetStoreAuthorizer",
            handler=self.authorizer_lambda,
            identity_source="method.request.header.Authorization",
            authorizer_name=f"{self.api_name}-authorizer",
            results_cache_ttl=Duration.minutes(5)
        )

    def _configure_api_resources(self) -> None:
        """Configure API resources and methods."""
        # Create request validator
        request_validator = apigateway.RequestValidator(
            self,
            "PetStoreRequestValidator",
            rest_api=self.api,
            validate_request_body=True,
            validate_request_parameters=True,
            request_validator_name=f"{self.api_name}-validator"
        )

        # Create /pets resource
        pets_resource = self.api.root.add_resource("pets")

        # Lambda integration
        lambda_integration = apigateway.LambdaIntegration(
            self.api_lambda,
            proxy=True,
            integration_responses=[
                apigateway.IntegrationResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": "'*'"
                    }
                )
            ]
        )

        # Add GET method
        pets_resource.add_method(
            "GET",
            lambda_integration,
            authorization_type=apigateway.AuthorizationType.CUSTOM,
            authorizer=self.custom_authorizer,
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": True
                    }
                )
            ]
        )

        # Add POST method
        pets_resource.add_method(
            "POST",
            lambda_integration,
            authorization_type=apigateway.AuthorizationType.CUSTOM,
            authorizer=self.custom_authorizer,
            request_validator=request_validator,
            method_responses=[
                apigateway.MethodResponse(
                    status_code="201",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": True
                    }
                )
            ]
        )

    def _create_deployment(self, stage_name: str) -> apigateway.Deployment:
        """Create API deployment for a specific stage."""
        # Configure stage variables and throttling based on environment
        stage_variables = {"environment": stage_name}
        
        if stage_name == "prod":
            throttle_rate_limit = 100
            throttle_burst_limit = 200
        else:
            throttle_rate_limit = 50
            throttle_burst_limit = 100

        deployment = apigateway.Deployment(
            self,
            f"ApiDeployment{stage_name.title()}",
            api=self.api,
            description=f"Deployment for {stage_name} stage"
        )

        stage = apigateway.Stage(
            self,
            f"ApiStage{stage_name.title()}",
            deployment=deployment,
            stage_name=stage_name,
            variables=stage_variables,
            throttling_rate_limit=throttle_rate_limit,
            throttling_burst_limit=throttle_burst_limit,
            logging_level=apigateway.MethodLoggingLevel.INFO,
            data_trace_enabled=True,
            metrics_enabled=True,
            description=f"{stage_name.title()} stage for Pet Store API"
        )

        return deployment

    def _create_custom_domain(self) -> apigateway.DomainName:
        """Create custom domain name for the API."""
        return apigateway.DomainName(
            self,
            "ApiCustomDomain",
            domain_name=self.api_subdomain,
            certificate=self.certificate,
            endpoint_type=apigateway.EndpointType.REGIONAL,
            security_policy=apigateway.SecurityPolicy.TLS_1_2
        )

    def _create_base_path_mappings(self) -> None:
        """Create base path mappings for different stages."""
        # Production mapping (root path)
        apigateway.BasePathMapping(
            self,
            "ProdBasePathMapping",
            domain_name=self.custom_domain,
            rest_api=self.api,
            stage=self.api.deployment_stage if hasattr(self.api, 'deployment_stage') else None,
            base_path=""
        )

        # Production versioned mapping
        apigateway.BasePathMapping(
            self,
            "ProdVersionedBasePathMapping",
            domain_name=self.custom_domain,
            rest_api=self.api,
            stage=self.api.deployment_stage if hasattr(self.api, 'deployment_stage') else None,
            base_path="v1"
        )

        # Development mapping
        apigateway.BasePathMapping(
            self,
            "DevBasePathMapping",
            domain_name=self.custom_domain,
            rest_api=self.api,
            stage=self.api.deployment_stage if hasattr(self.api, 'deployment_stage') else None,
            base_path="v1-dev"
        )

    def _create_dns_records(self) -> None:
        """Create DNS records for the custom domain."""
        # Look up the hosted zone (assuming it exists)
        hosted_zone = route53.HostedZone.from_lookup(
            self,
            "HostedZone",
            domain_name=self.domain_name
        )

        # Create CNAME record for the custom domain
        route53.CnameRecord(
            self,
            "ApiDomainCnameRecord",
            zone=hosted_zone,
            record_name=f"api.{self.domain_name}",
            domain_name=self.custom_domain.domain_name_alias_domain_name,
            ttl=Duration.minutes(5),
            comment="CNAME record for API Gateway custom domain"
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        CfnOutput(
            self,
            "ApiGatewayId",
            value=self.api.rest_api_id,
            description="API Gateway REST API ID"
        )

        CfnOutput(
            self,
            "ApiGatewayUrl",
            value=self.api.url,
            description="API Gateway URL"
        )

        CfnOutput(
            self,
            "CustomDomainName",
            value=self.api_subdomain,
            description="Custom domain name for the API"
        )

        CfnOutput(
            self,
            "CustomDomainUrl",
            value=f"https://{self.api_subdomain}",
            description="Custom domain URL for the API"
        )

        CfnOutput(
            self,
            "CertificateArn",
            value=self.certificate.certificate_arn,
            description="SSL certificate ARN"
        )

        CfnOutput(
            self,
            "RegionalDomainName",
            value=self.custom_domain.domain_name_alias_domain_name,
            description="Regional domain name for DNS configuration"
        )

        CfnOutput(
            self,
            "ApiEndpoints",
            value=f"Production: https://{self.api_subdomain}/pets, Development: https://{self.api_subdomain}/v1-dev/pets",
            description="API endpoints for different environments"
        )

    def _get_api_lambda_code(self) -> str:
        """Get the API Lambda function code."""
        return '''
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    logger.info(f"Event: {json.dumps(event)}")
    
    # Extract HTTP method and path
    http_method = event.get('httpMethod', 'GET')
    path = event.get('path', '/')
    
    # CORS headers
    cors_headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key',
        'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
    }
    
    # Handle OPTIONS requests for CORS
    if http_method == 'OPTIONS':
        return {
            'statusCode': 200,
            'headers': cors_headers,
            'body': json.dumps({'message': 'CORS preflight'})
        }
    
    # Sample API responses
    if path.endswith('/pets') and http_method == 'GET':
        return {
            'statusCode': 200,
            'headers': cors_headers,
            'body': json.dumps({
                'pets': [
                    {'id': 1, 'name': 'Buddy', 'type': 'dog', 'age': 3},
                    {'id': 2, 'name': 'Whiskers', 'type': 'cat', 'age': 2},
                    {'id': 3, 'name': 'Charlie', 'type': 'bird', 'age': 1}
                ],
                'total': 3,
                'timestamp': context.aws_request_id
            })
        }
    elif path.endswith('/pets') and http_method == 'POST':
        try:
            # Parse request body
            request_body = json.loads(event.get('body', '{}'))
            pet_name = request_body.get('name', 'Unknown')
            pet_type = request_body.get('type', 'unknown')
            
            return {
                'statusCode': 201,
                'headers': cors_headers,
                'body': json.dumps({
                    'message': 'Pet created successfully',
                    'pet': {
                        'id': 4,
                        'name': pet_name,
                        'type': pet_type,
                        'created': True
                    },
                    'timestamp': context.aws_request_id
                })
            }
        except json.JSONDecodeError:
            return {
                'statusCode': 400,
                'headers': cors_headers,
                'body': json.dumps({
                    'error': 'Invalid JSON in request body',
                    'timestamp': context.aws_request_id
                })
            }
    else:
        return {
            'statusCode': 404,
            'headers': cors_headers,
            'body': json.dumps({
                'error': 'Not Found',
                'path': path,
                'method': http_method,
                'timestamp': context.aws_request_id
            })
        }
'''

    def _get_authorizer_lambda_code(self) -> str:
        """Get the authorizer Lambda function code."""
        return '''
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    logger.info(f"Authorizer Event: {json.dumps(event)}")
    
    # Extract the authorization token
    token = event.get('authorizationToken', '')
    method_arn = event.get('methodArn', '')
    
    # Parse the method ARN to get API details
    arn_parts = method_arn.split(':')
    api_gateway_arn = arn_parts[5] if len(arn_parts) > 5 else ''
    
    # Simple token validation (in production, use proper JWT validation)
    if token == 'Bearer valid-token':
        effect = 'Allow'
        principal_id = 'user123'
        logger.info(f"Authorization granted for token: {token}")
    elif token == 'Bearer admin-token':
        effect = 'Allow'
        principal_id = 'admin456'
        logger.info(f"Admin authorization granted for token: {token}")
    else:
        effect = 'Deny'
        principal_id = 'anonymous'
        logger.warning(f"Authorization denied for token: {token}")
    
    # Generate policy document
    policy_document = {
        'Version': '2012-10-17',
        'Statement': [
            {
                'Action': 'execute-api:Invoke',
                'Effect': effect,
                'Resource': method_arn
            }
        ]
    }
    
    # Additional context information
    context_info = {
        'userId': principal_id,
        'userRole': 'admin' if 'admin' in principal_id else 'user',
        'requestTime': context.aws_request_id
    }
    
    response = {
        'principalId': principal_id,
        'policyDocument': policy_document,
        'context': context_info
    }
    
    logger.info(f"Authorizer response: {json.dumps(response)}")
    return response
'''


def main() -> None:
    """Main application entry point."""
    app = cdk.App()
    
    # Get configuration from context
    env = cdk.Environment(
        account=app.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=app.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION")
    )
    
    # Create the stack
    ApiGatewayCustomDomainStack(
        app,
        "ApiGatewayCustomDomainStack",
        env=env,
        description="Pet Store API with custom domain names using API Gateway, Lambda, and Route 53",
        tags={
            "Project": "PetStoreAPI",
            "Environment": "demo",
            "Purpose": "custom-domain-demo"
        }
    )
    
    app.synth()


if __name__ == "__main__":
    main()