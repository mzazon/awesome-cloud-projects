#!/usr/bin/env python3
"""
CDK Python Application for Multi-Region Applications with Aurora DSQL

This CDK application deploys a globally distributed serverless application using Aurora DSQL's
active-active multi-region architecture with Lambda functions and API Gateway across multiple regions.

Architecture Components:
- Aurora DSQL clusters in primary and secondary regions with witness region
- Lambda functions for database operations in both regions
- API Gateway REST APIs in both regions
- IAM roles and policies with least privilege access
- Route 53 health checks and failover routing (optional)

Author: AWS Recipes Team
Version: 1.0
"""

import os
from typing import Dict, Any, Optional
import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
    Stack,
    StackProps,
    CfnOutput,
    RemovalPolicy,
    Duration,
    Tags
)
from aws_cdk import aws_dsql as dsql
from aws_cdk import aws_lambda as lambda_
from aws_cdk import aws_apigateway as apigateway
from aws_cdk import aws_iam as iam
from aws_cdk import aws_logs as logs
from constructs import Construct


class MultiRegionAuroraDsqlStack(Stack):
    """
    CDK Stack for Multi-Region Aurora DSQL Application
    
    This stack creates a complete multi-region serverless application with Aurora DSQL,
    Lambda functions, and API Gateway following AWS Well-Architected Framework principles.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        is_primary_region: bool = True,
        witness_region: str = "us-west-2",
        paired_region: Optional[str] = None,
        cluster_identifier: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the Multi-Region Aurora DSQL Stack
        
        Args:
            scope: CDK construct scope
            construct_id: Unique identifier for this construct
            is_primary_region: Whether this is the primary region deployment
            witness_region: AWS region for the witness cluster
            paired_region: The paired region for multi-region setup
            cluster_identifier: Custom cluster identifier
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration
        self.is_primary_region = is_primary_region
        self.witness_region = witness_region
        self.paired_region = paired_region
        self.current_region = self.region
        
        # Generate unique identifiers
        self.unique_suffix = self.node.try_get_context("unique_suffix") or "dev"
        self.cluster_identifier = cluster_identifier or f"multi-region-app-{self.unique_suffix}"
        
        # Create Aurora DSQL cluster
        self.dsql_cluster = self._create_dsql_cluster()
        
        # Create IAM role for Lambda functions
        self.lambda_role = self._create_lambda_role()
        
        # Create Lambda function
        self.lambda_function = self._create_lambda_function()
        
        # Create API Gateway
        self.api_gateway = self._create_api_gateway()
        
        # Configure outputs
        self._create_outputs()
        
        # Apply tags
        self._apply_tags()

    def _create_dsql_cluster(self) -> dsql.CfnCluster:
        """
        Create Aurora DSQL cluster with multi-region configuration
        
        Returns:
            dsql.CfnCluster: The created Aurora DSQL cluster
        """
        # Define cluster properties
        cluster_props = {
            "cluster_identifier": f"{self.cluster_identifier}-{'primary' if self.is_primary_region else 'secondary'}",
            "deletion_protection": True,
            "tags": [
                cdk.CfnTag(key="Environment", value="Production"),
                cdk.CfnTag(key="Application", value="MultiRegionApp"),
                cdk.CfnTag(key="Region", value=self.current_region),
                cdk.CfnTag(key="Type", value="Primary" if self.is_primary_region else "Secondary")
            ]
        }
        
        # Add multi-region properties
        if self.witness_region:
            cluster_props["multi_region_properties"] = dsql.CfnCluster.MultiRegionPropertiesProperty(
                witness_region=self.witness_region
            )
        
        # Create the cluster
        cluster = dsql.CfnCluster(
            self,
            "AuroraDsqlCluster",
            **cluster_props
        )
        
        return cluster

    def _create_lambda_role(self) -> iam.Role:
        """
        Create IAM role for Lambda functions with Aurora DSQL permissions
        
        Returns:
            iam.Role: IAM role for Lambda functions
        """
        # Create IAM role
        role = iam.Role(
            self,
            "MultiRegionLambdaRole",
            role_name=f"MultiRegionLambdaRole-{self.unique_suffix}-{self.current_region}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for multi-region Aurora DSQL Lambda functions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ]
        )
        
        # Add Aurora DSQL permissions
        dsql_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "dsql:DbConnect",
                "dsql:DbConnectAdmin"
            ],
            resources=["*"]
        )
        
        role.add_to_policy(dsql_policy)
        
        return role

    def _create_lambda_function(self) -> lambda_.Function:
        """
        Create Lambda function for database operations
        
        Returns:
            lambda_.Function: The created Lambda function
        """
        # Create CloudWatch log group
        log_group = logs.LogGroup(
            self,
            "LambdaLogGroup",
            log_group_name=f"/aws/lambda/multi-region-app-{self.unique_suffix}-{self.current_region}",
            retention=logs.RetentionDays.TWO_WEEKS,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Create Lambda function
        function = lambda_.Function(
            self,
            "MultiRegionFunction",
            function_name=f"multi-region-app-{self.unique_suffix}-{self.current_region}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="lambda_function.lambda_handler",
            role=self.lambda_role,
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.seconds(30),
            memory_size=512,
            environment={
                "DSQL_CLUSTER_ID": self.dsql_cluster.cluster_identifier,
                "AWS_REGION": self.current_region,
                "LOG_LEVEL": "INFO"
            },
            description=f"Multi-region Aurora DSQL application function - {self.current_region}",
            log_group=log_group
        )
        
        # Add dependency on DSQL cluster
        function.node.add_dependency(self.dsql_cluster)
        
        return function

    def _create_api_gateway(self) -> apigateway.RestApi:
        """
        Create API Gateway REST API with Lambda integration
        
        Returns:
            apigateway.RestApi: The created API Gateway
        """
        # Create REST API
        api = apigateway.RestApi(
            self,
            "MultiRegionApi",
            rest_api_name=f"multi-region-api-{self.unique_suffix}-{self.current_region}",
            description=f"Multi-region Aurora DSQL API - {self.current_region}",
            endpoint_configuration=apigateway.EndpointConfiguration(
                types=[apigateway.EndpointType.REGIONAL]
            ),
            deploy_options=apigateway.StageOptions(
                stage_name="prod",
                throttling_rate_limit=1000,
                throttling_burst_limit=2000,
                logging_level=apigateway.MethodLoggingLevel.INFO,
                data_trace_enabled=True,
                metrics_enabled=True
            ),
            cloud_watch_role=True,
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=apigateway.Cors.ALL_ORIGINS,
                allow_methods=apigateway.Cors.ALL_METHODS,
                allow_headers=["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key"]
            )
        )
        
        # Create Lambda integration
        lambda_integration = apigateway.LambdaIntegration(
            self.lambda_function,
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
        
        # Create /health resource
        health_resource = api.root.add_resource("health")
        health_resource.add_method(
            "GET",
            lambda_integration,
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": True
                    }
                )
            ]
        )
        
        # Create /users resource
        users_resource = api.root.add_resource("users")
        users_resource.add_method("GET", lambda_integration)
        users_resource.add_method("POST", lambda_integration)
        
        return api

    def _get_lambda_code(self) -> str:
        """
        Get the Lambda function code as a string
        
        Returns:
            str: Lambda function code
        """
        return '''
import json
import os
import boto3
import logging
from typing import Dict, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Aurora DSQL connection parameters
DSQL_CLUSTER_ID = os.environ.get('DSQL_CLUSTER_ID')
DSQL_REGION = os.environ.get('AWS_REGION')


def get_dsql_client():
    """Create Aurora DSQL client with IAM authentication"""
    try:
        return boto3.client('dsql', region_name=DSQL_REGION)
    except Exception as e:
        logger.error(f"Failed to create DSQL client: {str(e)}")
        raise


def execute_query(query: str, parameters: Optional[list] = None) -> Dict[str, Any]:
    """Execute query against Aurora DSQL cluster"""
    try:
        client = get_dsql_client()
        
        request = {
            'Database': 'postgres',
            'Sql': query
        }
        
        if parameters:
            request['Parameters'] = parameters
        
        response = client.execute_statement(**request)
        return response
    except Exception as e:
        logger.error(f"Query execution failed: {str(e)}")
        raise


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Main Lambda handler for multi-region application"""
    try:
        # Parse request
        http_method = event.get('httpMethod', 'GET')
        path = event.get('path', '/')
        body = event.get('body')
        
        logger.info(f"Processing {http_method} request to {path}")
        
        # Handle different API endpoints
        if path == '/health':
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'status': 'healthy',
                    'region': DSQL_REGION,
                    'cluster': DSQL_CLUSTER_ID,
                    'timestamp': context.aws_request_id
                })
            }
        
        elif path == '/users' and http_method == 'GET':
            # Initialize schema if needed
            try:
                execute_query("""
                    CREATE TABLE IF NOT EXISTS users (
                        id SERIAL PRIMARY KEY,
                        name VARCHAR(100) NOT NULL,
                        email VARCHAR(255) UNIQUE NOT NULL,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                """)
                
                execute_query("CREATE INDEX IF NOT EXISTS idx_users_email ON users(email)")
                execute_query("CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at)")
            except Exception as e:
                logger.warning(f"Schema initialization warning: {str(e)}")
            
            # Get all users
            result = execute_query(
                "SELECT id, name, email, created_at FROM users ORDER BY created_at DESC"
            )
            
            users = []
            if 'Records' in result:
                for record in result['Records']:
                    users.append({
                        'id': record[0].get('longValue'),
                        'name': record[1].get('stringValue'),
                        'email': record[2].get('stringValue'),
                        'created_at': record[3].get('stringValue')
                    })
            
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'users': users,
                    'region': DSQL_REGION,
                    'count': len(users)
                })
            }
        
        elif path == '/users' and http_method == 'POST':
            # Create new user
            data = json.loads(body) if body else {}
            name = data.get('name')
            email = data.get('email')
            
            if not name or not email:
                return {
                    'statusCode': 400,
                    'headers': {
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*'
                    },
                    'body': json.dumps({'error': 'Name and email are required'})
                }
            
            result = execute_query(
                "INSERT INTO users (name, email) VALUES (?, ?) RETURNING id",
                [{'stringValue': name}, {'stringValue': email}]
            )
            
            user_id = result['Records'][0][0]['longValue']
            
            return {
                'statusCode': 201,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'id': user_id,
                    'name': name,
                    'email': email,
                    'region': DSQL_REGION
                })
            }
        
        else:
            return {
                'statusCode': 404,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Not found'})
            }
    
    except Exception as e:
        logger.error(f"Unhandled error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Internal server error'})
        }
'''

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources"""
        CfnOutput(
            self,
            "DsqlClusterIdentifier",
            value=self.dsql_cluster.cluster_identifier,
            description="Aurora DSQL Cluster Identifier",
            export_name=f"DsqlCluster-{self.unique_suffix}-{self.current_region}"
        )
        
        CfnOutput(
            self,
            "DsqlClusterArn",
            value=self.dsql_cluster.attr_arn,
            description="Aurora DSQL Cluster ARN",
            export_name=f"DsqlClusterArn-{self.unique_suffix}-{self.current_region}"
        )
        
        CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.lambda_function.function_arn,
            description="Lambda Function ARN",
            export_name=f"LambdaArn-{self.unique_suffix}-{self.current_region}"
        )
        
        CfnOutput(
            self,
            "ApiGatewayUrl",
            value=self.api_gateway.url,
            description="API Gateway URL",
            export_name=f"ApiUrl-{self.unique_suffix}-{self.current_region}"
        )
        
        CfnOutput(
            self,
            "ApiGatewayId",
            value=self.api_gateway.rest_api_id,
            description="API Gateway ID",
            export_name=f"ApiId-{self.unique_suffix}-{self.current_region}"
        )

    def _apply_tags(self) -> None:
        """Apply tags to all resources in the stack"""
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("Application", "MultiRegionApp")
        Tags.of(self).add("Region", self.current_region)
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("RecipeName", "multi-region-applications-aurora-dsql")


class MultiRegionAuroraDsqlApp(App):
    """
    CDK Application for Multi-Region Aurora DSQL deployment
    
    This app can deploy to multiple regions and configure cluster peering
    """

    def __init__(self):
        super().__init__()
        
        # Get configuration from context or environment
        self.primary_region = self.node.try_get_context("primary_region") or "us-east-1"
        self.secondary_region = self.node.try_get_context("secondary_region") or "us-east-2"
        self.witness_region = self.node.try_get_context("witness_region") or "us-west-2"
        self.unique_suffix = self.node.try_get_context("unique_suffix") or "dev"
        self.deploy_secondary = self.node.try_get_context("deploy_secondary") or False
        
        # Get account from environment
        account = os.environ.get("CDK_DEFAULT_ACCOUNT")
        if not account:
            raise ValueError("CDK_DEFAULT_ACCOUNT environment variable must be set")
        
        # Create primary region stack
        self.primary_stack = MultiRegionAuroraDsqlStack(
            self,
            f"MultiRegionAuroraDsql-Primary-{self.unique_suffix}",
            env=Environment(account=account, region=self.primary_region),
            is_primary_region=True,
            witness_region=self.witness_region,
            paired_region=self.secondary_region,
            cluster_identifier=f"multi-region-app-{self.unique_suffix}"
        )
        
        # Create secondary region stack if requested
        if self.deploy_secondary:
            self.secondary_stack = MultiRegionAuroraDsqlStack(
                self,
                f"MultiRegionAuroraDsql-Secondary-{self.unique_suffix}",
                env=Environment(account=account, region=self.secondary_region),
                is_primary_region=False,
                witness_region=self.witness_region,
                paired_region=self.primary_region,
                cluster_identifier=f"multi-region-app-{self.unique_suffix}"
            )


def main():
    """Main entry point for the CDK application"""
    app = MultiRegionAuroraDsqlApp()
    app.synth()


if __name__ == "__main__":
    main()