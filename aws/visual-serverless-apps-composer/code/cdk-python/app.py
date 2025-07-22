#!/usr/bin/env python3
"""
CDK Python Application for Visual Serverless Applications with AWS Infrastructure Composer and CodeCatalyst

This CDK application creates a complete serverless architecture including:
- API Gateway REST API with CORS configuration
- Lambda function for user CRUD operations
- DynamoDB table with encryption and point-in-time recovery
- CloudWatch monitoring and X-Ray tracing
- Dead letter queue for error handling
- Comprehensive security configurations

Generated from recipe: Visual Serverless Applications with Infrastructure Composer
"""

import os
from typing import Dict, Any, Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    CfnOutput,
    Duration,
    RemovalPolicy,
    Stack,
    StackProps,
    aws_apigateway as apigateway,
    aws_dynamodb as dynamodb,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_logs as logs,
    aws_sqs as sqs,
)
from constructs import Construct


class VisualServerlessApplicationStack(Stack):
    """
    CDK Stack for Visual Serverless Application
    
    This stack creates a complete serverless architecture with visual design principles
    from AWS Application Composer, including proper security, monitoring, and error handling.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        stage: str = "dev",
        **kwargs: Any
    ) -> None:
        """
        Initialize the Visual Serverless Application Stack
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            stage: Deployment stage (dev, staging, prod)
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)
        
        self.stage = stage
        
        # Create core infrastructure components
        self.dynamodb_table = self._create_dynamodb_table()
        self.dead_letter_queue = self._create_dead_letter_queue()
        self.lambda_function = self._create_lambda_function()
        self.api_gateway = self._create_api_gateway()
        self.log_group = self._create_log_group()
        
        # Create outputs for reference
        self._create_outputs()
        
        # Add tags to all resources
        self._add_tags()

    def _create_dynamodb_table(self) -> dynamodb.Table:
        """
        Create DynamoDB table for user data storage
        
        Returns:
            DynamoDB table with encryption and point-in-time recovery
        """
        table = dynamodb.Table(
            self,
            "UsersTable",
            table_name=f"{self.stage}-users-table",
            partition_key=dynamodb.Attribute(
                name="id",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            point_in_time_recovery=True,
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
        )
        
        # Add tags
        cdk.Tags.of(table).add("Environment", self.stage)
        cdk.Tags.of(table).add("Application", "Visual Serverless App")
        cdk.Tags.of(table).add("Component", "Database")
        
        return table

    def _create_dead_letter_queue(self) -> sqs.Queue:
        """
        Create SQS dead letter queue for failed Lambda invocations
        
        Returns:
            SQS queue configured for dead letter processing
        """
        dlq = sqs.Queue(
            self,
            "UsersDeadLetterQueue",
            queue_name=f"{self.stage}-users-dlq",
            message_retention_period=Duration.days(14),
            visibility_timeout=Duration.seconds(60),
        )
        
        # Add tags
        cdk.Tags.of(dlq).add("Environment", self.stage)
        cdk.Tags.of(dlq).add("Application", "Visual Serverless App")
        cdk.Tags.of(dlq).add("Component", "Error Handling")
        
        return dlq

    def _create_lambda_function(self) -> lambda_.Function:
        """
        Create Lambda function for user CRUD operations
        
        Returns:
            Lambda function with proper IAM permissions and configuration
        """
        # Create IAM role for Lambda function
        lambda_role = iam.Role(
            self,
            "UsersLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AWSXRayDaemonWriteAccess"
                ),
            ],
        )
        
        # Add DynamoDB permissions
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:GetItem",
                    "dynamodb:PutItem",
                    "dynamodb:Query",
                    "dynamodb:Scan",
                    "dynamodb:UpdateItem",
                    "dynamodb:DeleteItem",
                ],
                resources=[
                    self.dynamodb_table.table_arn,
                    f"{self.dynamodb_table.table_arn}/index/*",
                ],
            )
        )
        
        # Add SQS permissions for dead letter queue
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "sqs:SendMessage",
                    "sqs:GetQueueAttributes",
                ],
                resources=[self.dead_letter_queue.queue_arn],
            )
        )
        
        # Create Lambda function
        function = lambda_.Function(
            self,
            "UsersFunction",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="users.lambda_handler",
            code=lambda_.Code.from_asset("../handlers"),
            timeout=Duration.seconds(30),
            memory_size=256,
            role=lambda_role,
            environment={
                "TABLE_NAME": self.dynamodb_table.table_name,
                "LOG_LEVEL": "INFO",
                "POWERTOOLS_SERVICE_NAME": "users-service",
            },
            tracing=lambda_.Tracing.ACTIVE,
            reserved_concurrent_executions=100,
            dead_letter_queue=self.dead_letter_queue,
            description="Handle CRUD operations for users in visual serverless app",
        )
        
        # Add tags
        cdk.Tags.of(function).add("Environment", self.stage)
        cdk.Tags.of(function).add("Application", "Visual Serverless App")
        cdk.Tags.of(function).add("Component", "Compute")
        
        return function

    def _create_api_gateway(self) -> apigateway.RestApi:
        """
        Create API Gateway REST API with CORS and monitoring
        
        Returns:
            API Gateway REST API with proper configuration
        """
        # Create REST API
        api = apigateway.RestApi(
            self,
            "ServerlessAPI",
            rest_api_name=f"{self.stage}-serverless-api",
            description=f"Serverless API for {self.stage} environment",
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=apigateway.Cors.ALL_ORIGINS,
                allow_methods=apigateway.Cors.ALL_METHODS,
                allow_headers=[
                    "Content-Type",
                    "X-Amz-Date",
                    "Authorization",
                    "X-Api-Key",
                    "X-Amz-Security-Token",
                ],
            ),
            deploy_options=apigateway.StageOptions(
                stage_name=self.stage,
                tracing_enabled=True,
                data_trace_enabled=True,
                logging_level=apigateway.MethodLoggingLevel.INFO,
                metrics_enabled=True,
                throttling_rate_limit=1000,
                throttling_burst_limit=2000,
            ),
            cloud_watch_role=True,
            endpoint_configuration=apigateway.EndpointConfiguration(
                types=[apigateway.EndpointType.REGIONAL]
            ),
        )
        
        # Create Lambda integration
        lambda_integration = apigateway.LambdaIntegration(
            self.lambda_function,
            request_templates={
                "application/json": '{"statusCode": "200"}'
            },
            proxy=True,
        )
        
        # Create /users resource
        users_resource = api.root.add_resource("users")
        
        # Add GET method for listing users
        users_resource.add_method(
            "GET",
            lambda_integration,
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": True,
                    },
                ),
                apigateway.MethodResponse(
                    status_code="500",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": True,
                    },
                ),
            ],
        )
        
        # Add POST method for creating users
        users_resource.add_method(
            "POST",
            lambda_integration,
            method_responses=[
                apigateway.MethodResponse(
                    status_code="201",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": True,
                    },
                ),
                apigateway.MethodResponse(
                    status_code="400",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": True,
                    },
                ),
                apigateway.MethodResponse(
                    status_code="500",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": True,
                    },
                ),
            ],
        )
        
        # Add tags
        cdk.Tags.of(api).add("Environment", self.stage)
        cdk.Tags.of(api).add("Application", "Visual Serverless App")
        cdk.Tags.of(api).add("Component", "API")
        
        return api

    def _create_log_group(self) -> logs.LogGroup:
        """
        Create CloudWatch log group for Lambda function
        
        Returns:
            CloudWatch log group with retention policy
        """
        log_group = logs.LogGroup(
            self,
            "UsersLogGroup",
            log_group_name=f"/aws/lambda/{self.lambda_function.function_name}",
            retention=logs.RetentionDays.TWO_WEEKS,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Add tags
        cdk.Tags.of(log_group).add("Environment", self.stage)
        cdk.Tags.of(log_group).add("Application", "Visual Serverless App")
        cdk.Tags.of(log_group).add("Component", "Logging")
        
        return log_group

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources"""
        
        CfnOutput(
            self,
            "ApiEndpoint",
            description="API Gateway endpoint URL",
            value=self.api_gateway.url,
            export_name=f"{self.stack_name}-ApiEndpoint",
        )
        
        CfnOutput(
            self,
            "DynamoDBTableName",
            description="DynamoDB table name for users",
            value=self.dynamodb_table.table_name,
            export_name=f"{self.stack_name}-UsersTable",
        )
        
        CfnOutput(
            self,
            "LambdaFunctionArn",
            description="Lambda function ARN",
            value=self.lambda_function.function_arn,
            export_name=f"{self.stack_name}-UsersFunction",
        )
        
        CfnOutput(
            self,
            "DynamoDBTableArn",
            description="DynamoDB table ARN",
            value=self.dynamodb_table.table_arn,
            export_name=f"{self.stack_name}-UsersTableArn",
        )
        
        CfnOutput(
            self,
            "DeadLetterQueueUrl",
            description="SQS dead letter queue URL",
            value=self.dead_letter_queue.queue_url,
            export_name=f"{self.stack_name}-DeadLetterQueue",
        )

    def _add_tags(self) -> None:
        """Add common tags to all resources in the stack"""
        
        cdk.Tags.of(self).add("Project", "Visual Serverless Application")
        cdk.Tags.of(self).add("Environment", self.stage)
        cdk.Tags.of(self).add("ManagedBy", "CDK")
        cdk.Tags.of(self).add("Recipe", "building-visual-serverless-applications")
        cdk.Tags.of(self).add("Repository", "aws-recipes")


def main() -> None:
    """
    Main function to create and deploy the CDK application
    """
    app = App()
    
    # Get stage from context or environment variable
    stage = app.node.try_get_context("stage") or os.environ.get("STAGE", "dev")
    
    # Get AWS account and region from environment
    account = os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    
    # Create the stack
    VisualServerlessApplicationStack(
        app,
        f"VisualServerlessApp-{stage}",
        stage=stage,
        env=cdk.Environment(
            account=account,
            region=region,
        ),
        description=f"Visual Serverless Application Stack for {stage} environment",
    )
    
    # Synthesize the CloudFormation template
    app.synth()


if __name__ == "__main__":
    main()