#!/usr/bin/env python3
"""
AWS CDK Python application for Blue-Green Deployments with VPC Lattice and Lambda.

This application creates a complete blue-green deployment infrastructure using:
- VPC Lattice for application networking and traffic management
- Lambda functions for both blue and green environments
- CloudWatch monitoring and alarms for observability
- IAM roles with least privilege access

Architecture:
    - VPC Lattice Service Network for application networking
    - Blue and Green Lambda functions representing different versions
    - Target Groups for each environment with health checking
    - Weighted routing to control traffic distribution
    - CloudWatch alarms for automated monitoring

Author: AWS CDK Recipe Generator
Version: 1.0.0
License: MIT
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    CfnOutput,
    RemovalPolicy,
    aws_lambda as _lambda,
    aws_iam as iam,
    aws_vpclattice as vpclattice,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from constructs import Construct
from typing import Dict, Any, Optional
import json


class BlueGreenLatticeStack(Stack):
    """
    CDK Stack for Blue-Green Deployments with VPC Lattice and Lambda.
    
    This stack implements a production-ready blue-green deployment architecture
    using VPC Lattice for traffic management and Lambda for serverless compute.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        environment_name: str = "production",
        blue_version: str = "1.0.0",
        green_version: str = "2.0.0",
        initial_blue_weight: int = 90,
        initial_green_weight: int = 10,
        **kwargs
    ) -> None:
        """
        Initialize the Blue-Green Lattice Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            environment_name: Name of the environment (e.g., production, staging)
            blue_version: Version identifier for blue environment
            green_version: Version identifier for green environment  
            initial_blue_weight: Initial traffic weight for blue environment (0-100)
            initial_green_weight: Initial traffic weight for green environment (0-100)
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Validate weights
        if initial_blue_weight + initial_green_weight != 100:
            raise ValueError("Blue and green weights must sum to 100")

        # Store configuration
        self.environment_name = environment_name
        self.blue_version = blue_version
        self.green_version = green_version
        self.blue_weight = initial_blue_weight
        self.green_weight = initial_green_weight

        # Create resources
        self._create_iam_roles()
        self._create_lambda_functions()
        self._create_vpc_lattice_resources()
        self._create_monitoring()
        self._create_outputs()

    def _create_iam_roles(self) -> None:
        """Create IAM roles for Lambda functions with least privilege access."""
        # Create execution role for Lambda functions
        self.lambda_execution_role = iam.Role(
            self,
            "LambdaExecutionRole",
            role_name=f"BlueGreenLambdaRole-{self.environment_name}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for Blue-Green Lambda functions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Add CloudWatch Logs permissions
        self.lambda_execution_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                ],
                resources=[
                    f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/lambda/*"
                ],
            )
        )

    def _create_lambda_functions(self) -> None:
        """Create Lambda functions for blue and green environments."""
        # Blue environment Lambda function
        self.blue_function = _lambda.Function(
            self,
            "BlueLambdaFunction",
            function_name=f"ecommerce-blue-{self.environment_name}",
            runtime=_lambda.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            role=self.lambda_execution_role,
            code=_lambda.Code.from_inline(self._get_blue_function_code()),
            timeout=Duration.seconds(30),
            memory_size=256,
            environment={
                "ENVIRONMENT": "blue",
                "VERSION": self.blue_version,
                "DEPLOYMENT_TYPE": "blue-green",
            },
            description=f"Blue environment Lambda function - v{self.blue_version}",
            log_retention=logs.RetentionDays.ONE_WEEK,
            tracing=_lambda.Tracing.ACTIVE,
        )

        # Green environment Lambda function
        self.green_function = _lambda.Function(
            self,
            "GreenLambdaFunction",
            function_name=f"ecommerce-green-{self.environment_name}",
            runtime=_lambda.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            role=self.lambda_execution_role,
            code=_lambda.Code.from_inline(self._get_green_function_code()),
            timeout=Duration.seconds(30),
            memory_size=256,
            environment={
                "ENVIRONMENT": "green",
                "VERSION": self.green_version,
                "DEPLOYMENT_TYPE": "blue-green",
            },
            description=f"Green environment Lambda function - v{self.green_version}",
            log_retention=logs.RetentionDays.ONE_WEEK,
            tracing=_lambda.Tracing.ACTIVE,
        )

        # Add tags for better resource management
        for func in [self.blue_function, self.green_function]:
            cdk.Tags.of(func).add("Project", "BlueGreenDeployment")
            cdk.Tags.of(func).add("Environment", self.environment_name)

    def _create_vpc_lattice_resources(self) -> None:
        """Create VPC Lattice service network, target groups, and service."""
        # Create VPC Lattice Service Network
        self.service_network = vpclattice.CfnServiceNetwork(
            self,
            "ServiceNetwork",
            name=f"ecommerce-network-{self.environment_name}",
            auth_type="AWS_IAM",
        )

        # Create target groups for blue and green environments
        self.blue_target_group = vpclattice.CfnTargetGroup(
            self,
            "BlueTargetGroup",
            name=f"blue-tg-{self.environment_name}",
            type="LAMBDA",
            targets=[
                vpclattice.CfnTargetGroup.TargetProperty(
                    id=self.blue_function.function_arn
                )
            ],
            config=vpclattice.CfnTargetGroup.TargetGroupConfigProperty(
                health_check=vpclattice.CfnTargetGroup.HealthCheckConfigProperty(
                    enabled=True,
                    health_check_grace_period_seconds=30,
                    health_check_interval_seconds=30,
                    health_check_timeout_seconds=5,
                    healthy_threshold_count=2,
                    unhealthy_threshold_count=2,
                    matcher=vpclattice.CfnTargetGroup.MatcherProperty(
                        http_code="200"
                    ),
                    path="/health",
                    protocol="HTTPS",
                    protocol_version="HTTP1",
                )
            ),
        )

        self.green_target_group = vpclattice.CfnTargetGroup(
            self,
            "GreenTargetGroup", 
            name=f"green-tg-{self.environment_name}",
            type="LAMBDA",
            targets=[
                vpclattice.CfnTargetGroup.TargetProperty(
                    id=self.green_function.function_arn
                )
            ],
            config=vpclattice.CfnTargetGroup.TargetGroupConfigProperty(
                health_check=vpclattice.CfnTargetGroup.HealthCheckConfigProperty(
                    enabled=True,
                    health_check_grace_period_seconds=30,
                    health_check_interval_seconds=30,
                    health_check_timeout_seconds=5,
                    healthy_threshold_count=2,
                    unhealthy_threshold_count=2,
                    matcher=vpclattice.CfnTargetGroup.MatcherProperty(
                        http_code="200"
                    ),
                    path="/health",
                    protocol="HTTPS",
                    protocol_version="HTTP1",
                )
            ),
        )

        # Create VPC Lattice Service
        self.lattice_service = vpclattice.CfnService(
            self,
            "LatticeService",
            name=f"lattice-service-{self.environment_name}",
            auth_type="AWS_IAM",
        )

        # Associate service with service network
        self.service_association = vpclattice.CfnServiceNetworkServiceAssociation(
            self,
            "ServiceNetworkAssociation",
            service_identifier=self.lattice_service.ref,
            service_network_identifier=self.service_network.ref,
        )

        # Create listener with weighted routing
        self.listener = vpclattice.CfnListener(
            self,
            "HttpListener",
            service_identifier=self.lattice_service.ref,
            name="http-listener",
            protocol="HTTP",
            port=80,
            default_action=vpclattice.CfnListener.DefaultActionProperty(
                forward=vpclattice.CfnListener.ForwardProperty(
                    target_groups=[
                        vpclattice.CfnListener.WeightedTargetGroupProperty(
                            target_group_identifier=self.blue_target_group.ref,
                            weight=self.blue_weight,
                        ),
                        vpclattice.CfnListener.WeightedTargetGroupProperty(
                            target_group_identifier=self.green_target_group.ref,
                            weight=self.green_weight,
                        ),
                    ]
                )
            ),
        )

        # Grant VPC Lattice permission to invoke Lambda functions
        self.blue_function.add_permission(
            "VpcLatticeBlueInvoke",
            principal=iam.ServicePrincipal("vpc-lattice.amazonaws.com"),
            source_arn=self.blue_target_group.attr_arn,
        )

        self.green_function.add_permission(
            "VpcLatticeGreenInvoke",
            principal=iam.ServicePrincipal("vpc-lattice.amazonaws.com"),
            source_arn=self.green_target_group.attr_arn,
        )

    def _create_monitoring(self) -> None:
        """Create CloudWatch alarms for monitoring both environments."""
        # Create CloudWatch alarms for green environment monitoring
        self.green_error_alarm = cloudwatch.Alarm(
            self,
            "GreenEnvironmentErrorAlarm",
            alarm_name=f"{self.green_function.function_name}-ErrorRate",
            alarm_description="Monitor error rate for green environment",
            metric=self.green_function.metric_errors(
                period=Duration.minutes(5),
                statistic=cloudwatch.Statistic.SUM,
            ),
            threshold=5,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        self.green_duration_alarm = cloudwatch.Alarm(
            self,
            "GreenEnvironmentDurationAlarm",
            alarm_name=f"{self.green_function.function_name}-Duration",
            alarm_description="Monitor duration for green environment",
            metric=self.green_function.metric_duration(
                period=Duration.minutes(5),
                statistic=cloudwatch.Statistic.AVERAGE,
            ),
            threshold=10000,  # 10 seconds in milliseconds
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Create alarms for blue environment as baseline
        self.blue_error_alarm = cloudwatch.Alarm(
            self,
            "BlueEnvironmentErrorAlarm",
            alarm_name=f"{self.blue_function.function_name}-ErrorRate",
            alarm_description="Monitor error rate for blue environment",
            metric=self.blue_function.metric_errors(
                period=Duration.minutes(5),
                statistic=cloudwatch.Statistic.SUM,
            ),
            threshold=10,  # Higher threshold for production blue environment
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=3,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource identifiers."""
        CfnOutput(
            self,
            "ServiceNetworkId",
            value=self.service_network.ref,
            description="VPC Lattice Service Network ID",
            export_name=f"{self.stack_name}-ServiceNetworkId",
        )

        CfnOutput(
            self,
            "LatticeServiceId", 
            value=self.lattice_service.ref,
            description="VPC Lattice Service ID",
            export_name=f"{self.stack_name}-LatticeServiceId",
        )

        CfnOutput(
            self,
            "ServiceDomainName",
            value=self.lattice_service.attr_dns_entry_domain_name,
            description="VPC Lattice Service Domain Name",
            export_name=f"{self.stack_name}-ServiceDomainName",
        )

        CfnOutput(
            self,
            "BlueFunctionArn",
            value=self.blue_function.function_arn,
            description="Blue Environment Lambda Function ARN",
            export_name=f"{self.stack_name}-BlueFunctionArn",
        )

        CfnOutput(
            self,
            "GreenFunctionArn",
            value=self.green_function.function_arn,
            description="Green Environment Lambda Function ARN",
            export_name=f"{self.stack_name}-GreenFunctionArn",
        )

        CfnOutput(
            self,
            "BlueTargetGroupArn",
            value=self.blue_target_group.attr_arn,
            description="Blue Target Group ARN",
            export_name=f"{self.stack_name}-BlueTargetGroupArn",
        )

        CfnOutput(
            self,
            "GreenTargetGroupArn",
            value=self.green_target_group.attr_arn,
            description="Green Target Group ARN", 
            export_name=f"{self.stack_name}-GreenTargetGroupArn",
        )

        CfnOutput(
            self,
            "TrafficDistribution",
            value=f"Blue: {self.blue_weight}%, Green: {self.green_weight}%",
            description="Current traffic distribution between environments",
        )

    def _get_blue_function_code(self) -> str:
        """Get the Lambda function code for the blue environment."""
        return '''
import json
import time
import os


def lambda_handler(event, context):
    """
    Blue environment Lambda handler - stable production version.
    
    Args:
        event: Lambda event object
        context: Lambda context object
        
    Returns:
        dict: HTTP response with blue environment information
    """
    # Blue environment - stable production version
    response_data = {
        "environment": "blue",
        "version": os.environ.get("VERSION", "1.0.0"),
        "message": "Hello from Blue Environment!",
        "timestamp": int(time.time()),
        "request_id": context.aws_request_id,
        "deployment_type": os.environ.get("DEPLOYMENT_TYPE", "blue-green"),
        "function_name": context.function_name,
        "memory_limit": context.memory_limit_in_mb,
        "remaining_time": context.get_remaining_time_in_millis()
    }
    
    # Handle health check requests
    if event.get("path") == "/health":
        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                "X-Environment": "blue",
                "X-Health-Status": "healthy"
            },
            "body": json.dumps({"status": "healthy", "environment": "blue"})
        }
    
    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            "X-Environment": "blue",
            "X-Version": os.environ.get("VERSION", "1.0.0")
        },
        "body": json.dumps(response_data)
    }
'''

    def _get_green_function_code(self) -> str:
        """Get the Lambda function code for the green environment."""
        return '''
import json
import time
import os


def lambda_handler(event, context):
    """
    Green environment Lambda handler - new version being deployed.
    
    Args:
        event: Lambda event object
        context: Lambda context object
        
    Returns:
        dict: HTTP response with green environment information
    """
    # Green environment - new version being deployed
    response_data = {
        "environment": "green",
        "version": os.environ.get("VERSION", "2.0.0"),
        "message": "Hello from Green Environment!",
        "timestamp": int(time.time()),
        "request_id": context.aws_request_id,
        "deployment_type": os.environ.get("DEPLOYMENT_TYPE", "blue-green"),
        "function_name": context.function_name,
        "memory_limit": context.memory_limit_in_mb,
        "remaining_time": context.get_remaining_time_in_millis(),
        "new_feature": "Enhanced response with additional metadata"
    }
    
    # Handle health check requests
    if event.get("path") == "/health":
        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                "X-Environment": "green",
                "X-Health-Status": "healthy"
            },
            "body": json.dumps({"status": "healthy", "environment": "green"})
        }
    
    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            "X-Environment": "green",
            "X-Version": os.environ.get("VERSION", "2.0.0")
        },
        "body": json.dumps(response_data)
    }
'''


class BlueGreenDeploymentApp(cdk.App):
    """
    CDK Application for Blue-Green Deployments with VPC Lattice.
    
    This application demonstrates a complete blue-green deployment solution
    using AWS VPC Lattice for traffic management and Lambda for compute.
    """

    def __init__(self) -> None:
        """Initialize the CDK application."""
        super().__init__()

        # Get configuration from context or environment variables
        environment_name = self.node.try_get_context("environment") or "production"
        blue_version = self.node.try_get_context("blue_version") or "1.0.0"
        green_version = self.node.try_get_context("green_version") or "2.0.0"
        blue_weight = int(self.node.try_get_context("blue_weight") or 90)
        green_weight = int(self.node.try_get_context("green_weight") or 10)

        # Create the main stack
        BlueGreenLatticeStack(
            self,
            "BlueGreenLatticeStack",
            environment_name=environment_name,
            blue_version=blue_version,
            green_version=green_version,
            initial_blue_weight=blue_weight,
            initial_green_weight=green_weight,
            description="Blue-Green Deployment with VPC Lattice and Lambda",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION")
            ),
        )


if __name__ == "__main__":
    import os
    app = BlueGreenDeploymentApp()
    app.synth()