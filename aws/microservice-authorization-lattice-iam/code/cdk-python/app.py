#!/usr/bin/env python3
"""
CDK Python application for Microservice Authorization with VPC Lattice and IAM.

This application demonstrates how to implement fine-grained, service-to-service
authorization using VPC Lattice auth policies combined with IAM roles to create
a zero-trust networking model for microservices.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_iam as iam,
    aws_lambda as _lambda,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_vpclattice as vpclattice,
)
from constructs import Construct
from typing import Dict, Any
import json


class MicroserviceAuthorizationStack(Stack):
    """
    CDK Stack for implementing microservice authorization with VPC Lattice and IAM.
    
    This stack creates:
    - IAM roles for microservice identity management
    - Lambda functions representing microservices
    - VPC Lattice service network with IAM authentication
    - VPC Lattice service with Lambda target
    - Fine-grained authorization policies
    - CloudWatch monitoring and access logging
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.try_get_context("unique_suffix") or "demo"

        # Create IAM roles for microservices
        self._create_iam_roles(unique_suffix)
        
        # Create Lambda functions representing microservices
        self._create_lambda_functions(unique_suffix)
        
        # Create VPC Lattice service network
        self._create_service_network(unique_suffix)
        
        # Create VPC Lattice service with Lambda target
        self._create_vpc_lattice_service(unique_suffix)
        
        # Associate service with service network
        self._associate_service_with_network()
        
        # Create authorization policy
        self._create_authorization_policy()
        
        # Enable monitoring and logging
        self._create_monitoring(unique_suffix)
        
        # Create stack outputs
        self._create_outputs()

    def _create_iam_roles(self, unique_suffix: str) -> None:
        """Create IAM roles for microservice identity management."""
        
        # IAM role for product service (client)
        self.product_service_role = iam.Role(
            self, f"ProductServiceRole-{unique_suffix}",
            role_name=f"ProductServiceRole-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for product service microservice",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )

        # IAM role for order service (provider)
        self.order_service_role = iam.Role(
            self, f"OrderServiceRole-{unique_suffix}",
            role_name=f"OrderServiceRole-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for order service microservice",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )

        # Add tags to roles
        cdk.Tags.of(self.product_service_role).add("Environment", "Demo")
        cdk.Tags.of(self.product_service_role).add("Purpose", "MicroserviceAuth")
        cdk.Tags.of(self.order_service_role).add("Environment", "Demo")
        cdk.Tags.of(self.order_service_role).add("Purpose", "MicroserviceAuth")

    def _create_lambda_functions(self, unique_suffix: str) -> None:
        """Create Lambda functions representing microservices."""
        
        # Product service Lambda function (client)
        product_service_code = '''
import json
import boto3
import urllib3

def lambda_handler(event, context):
    """Product service Lambda function handler."""
    try:
        # Simulate product service calling order service
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Product service authenticated and ready',
                'service': 'product-service',
                'role': context.invoked_function_arn.split(':')[4]
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
        '''

        self.product_service_function = _lambda.Function(
            self, f"ProductService-{unique_suffix}",
            function_name=f"product-service-{unique_suffix}",
            runtime=_lambda.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(product_service_code),
            role=self.product_service_role,
            timeout=Duration.seconds(30),
            description="Product service microservice Lambda function",
            environment={
                "SERVICE_NAME": "product-service",
                "ENVIRONMENT": "demo"
            }
        )

        # Order service Lambda function (provider)
        order_service_code = '''
import json

def lambda_handler(event, context):
    """Order service Lambda function handler."""
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Order service processing request',
            'service': 'order-service',
            'requestId': context.aws_request_id,
            'orders': [
                {'id': 1, 'product': 'Widget A', 'quantity': 5},
                {'id': 2, 'product': 'Widget B', 'quantity': 3}
            ]
        })
    }
        '''

        self.order_service_function = _lambda.Function(
            self, f"OrderService-{unique_suffix}",
            function_name=f"order-service-{unique_suffix}",
            runtime=_lambda.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(order_service_code),
            role=self.order_service_role,
            timeout=Duration.seconds(30),
            description="Order service microservice Lambda function",
            environment={
                "SERVICE_NAME": "order-service",
                "ENVIRONMENT": "demo"
            }
        )

        # Add tags to Lambda functions
        cdk.Tags.of(self.product_service_function).add("Environment", "Demo")
        cdk.Tags.of(self.product_service_function).add("Purpose", "MicroserviceAuth")
        cdk.Tags.of(self.order_service_function).add("Environment", "Demo")
        cdk.Tags.of(self.order_service_function).add("Purpose", "MicroserviceAuth")

    def _create_service_network(self, unique_suffix: str) -> None:
        """Create VPC Lattice service network with IAM authentication."""
        
        self.service_network = vpclattice.CfnServiceNetwork(
            self, f"MicroservicesNetwork-{unique_suffix}",
            name=f"microservices-network-{unique_suffix}",
            auth_type="AWS_IAM",
            tags=[
                cdk.CfnTag(key="Environment", value="Demo"),
                cdk.CfnTag(key="Purpose", value="MicroserviceAuth")
            ]
        )

    def _create_vpc_lattice_service(self, unique_suffix: str) -> None:
        """Create VPC Lattice service with Lambda target."""
        
        # Create VPC Lattice service for order service
        self.lattice_service = vpclattice.CfnService(
            self, f"OrderService-{unique_suffix}",
            name=f"order-service-{unique_suffix}",
            auth_type="AWS_IAM"
        )

        # Create target group for Lambda function
        self.target_group = vpclattice.CfnTargetGroup(
            self, f"OrderTargets-{unique_suffix}",
            name=f"order-targets-{unique_suffix}",
            type="LAMBDA",
            targets=[
                vpclattice.CfnTargetGroup.TargetProperty(
                    id=self.order_service_function.function_name
                )
            ]
        )

        # Create listener for the service
        self.listener = vpclattice.CfnListener(
            self, f"OrderListener-{unique_suffix}",
            name="order-listener",
            service_identifier=self.lattice_service.attr_id,
            protocol="HTTP",
            port=80,
            default_action=vpclattice.CfnListener.DefaultActionProperty(
                forward=vpclattice.CfnListener.ForwardProperty(
                    target_groups=[
                        vpclattice.CfnListener.WeightedTargetGroupProperty(
                            target_group_identifier=self.target_group.attr_id
                        )
                    ]
                )
            )
        )

        # Grant VPC Lattice permission to invoke Lambda function
        self.order_service_function.add_permission(
            "VPCLatticeInvoke",
            principal=iam.ServicePrincipal("vpc-lattice.amazonaws.com"),
            action="lambda:InvokeFunction"
        )

    def _associate_service_with_network(self) -> None:
        """Associate service with service network."""
        
        self.service_association = vpclattice.CfnServiceNetworkServiceAssociation(
            self, "ServiceNetworkAssociation",
            service_identifier=self.lattice_service.attr_id,
            service_network_identifier=self.service_network.attr_id
        )

    def _create_authorization_policy(self) -> None:
        """Create fine-grained authorization policy."""
        
        # Authorization policy for fine-grained access control
        auth_policy = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "AllowProductServiceAccess",
                    "Effect": "Allow",
                    "Principal": {
                        "AWS": self.product_service_role.role_arn
                    },
                    "Action": "vpc-lattice-svcs:Invoke",
                    "Resource": f"arn:aws:vpc-lattice:{self.region}:{self.account}:service/{self.lattice_service.attr_id}/*",
                    "Condition": {
                        "StringEquals": {
                            "vpc-lattice-svcs:RequestMethod": ["GET", "POST"]
                        },
                        "StringLike": {
                            "vpc-lattice-svcs:RequestPath": "/orders*"
                        }
                    }
                },
                {
                    "Sid": "DenyUnauthorizedAccess",
                    "Effect": "Deny",
                    "Principal": "*",
                    "Action": "vpc-lattice-svcs:Invoke",
                    "Resource": f"arn:aws:vpc-lattice:{self.region}:{self.account}:service/{self.lattice_service.attr_id}/*",
                    "Condition": {
                        "StringNotLike": {
                            "aws:PrincipalArn": self.product_service_role.role_arn
                        }
                    }
                }
            ]
        }

        # Apply auth policy to the service
        self.auth_policy = vpclattice.CfnAuthPolicy(
            self, "ServiceAuthPolicy",
            resource_identifier=self.lattice_service.attr_id,
            policy=auth_policy
        )

        # Add VPC Lattice invoke policy to product service role
        vpc_lattice_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=["vpc-lattice-svcs:Invoke"],
            resources=[
                f"arn:aws:vpc-lattice:{self.region}:{self.account}:service/{self.lattice_service.attr_id}/*"
            ]
        )

        self.product_service_role.add_to_policy(vpc_lattice_policy)

    def _create_monitoring(self, unique_suffix: str) -> None:
        """Create CloudWatch monitoring and access logging."""
        
        # Create CloudWatch log group for VPC Lattice access logs
        self.access_log_group = logs.LogGroup(
            self, f"VPCLatticeAccessLogs-{unique_suffix}",
            log_group_name=f"/aws/vpclattice/microservices-network-{unique_suffix}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Enable access logging for the service network
        self.access_log_subscription = vpclattice.CfnAccessLogSubscription(
            self, f"AccessLogSubscription-{unique_suffix}",
            resource_identifier=self.service_network.attr_id,
            destination_arn=self.access_log_group.log_group_arn
        )

        # Create CloudWatch alarm for authorization failures
        self.auth_failure_alarm = cloudwatch.Alarm(
            self, f"VPCLatticeAuthFailures-{unique_suffix}",
            alarm_name=f"VPC-Lattice-Auth-Failures-{unique_suffix}",
            alarm_description="Monitor VPC Lattice authorization failures",
            metric=cloudwatch.Metric(
                namespace="AWS/VpcLattice",
                metric_name="4XXError",
                dimensions_map={
                    "ServiceNetwork": self.service_network.attr_id
                },
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=5,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        
        # Service Network outputs
        cdk.CfnOutput(
            self, "ServiceNetworkId",
            value=self.service_network.attr_id,
            description="VPC Lattice Service Network ID"
        )

        cdk.CfnOutput(
            self, "ServiceNetworkArn",
            value=self.service_network.attr_arn,
            description="VPC Lattice Service Network ARN"
        )

        # Service outputs
        cdk.CfnOutput(
            self, "LatticeServiceId",
            value=self.lattice_service.attr_id,
            description="VPC Lattice Service ID"
        )

        cdk.CfnOutput(
            self, "LatticeServiceArn",
            value=self.lattice_service.attr_arn,
            description="VPC Lattice Service ARN"
        )

        # Lambda function outputs
        cdk.CfnOutput(
            self, "ProductServiceFunctionName",
            value=self.product_service_function.function_name,
            description="Product Service Lambda Function Name"
        )

        cdk.CfnOutput(
            self, "OrderServiceFunctionName",
            value=self.order_service_function.function_name,
            description="Order Service Lambda Function Name"
        )

        # IAM role outputs
        cdk.CfnOutput(
            self, "ProductServiceRoleArn",
            value=self.product_service_role.role_arn,
            description="Product Service IAM Role ARN"
        )

        cdk.CfnOutput(
            self, "OrderServiceRoleArn",
            value=self.order_service_role.role_arn,
            description="Order Service IAM Role ARN"
        )

        # Monitoring outputs
        cdk.CfnOutput(
            self, "AccessLogGroupName",
            value=self.access_log_group.log_group_name,
            description="CloudWatch Log Group for VPC Lattice Access Logs"
        )

        cdk.CfnOutput(
            self, "AuthFailureAlarmName",
            value=self.auth_failure_alarm.alarm_name,
            description="CloudWatch Alarm for Authorization Failures"
        )


class MicroserviceAuthorizationApp(cdk.App):
    """CDK Application for Microservice Authorization with VPC Lattice and IAM."""

    def __init__(self):
        super().__init__()

        # Get context values or use defaults
        env = cdk.Environment(
            account=self.node.try_get_context("account") or None,
            region=self.node.try_get_context("region") or "us-east-1"
        )

        # Create the main stack
        MicroserviceAuthorizationStack(
            self, "MicroserviceAuthorizationStack",
            env=env,
            description="Microservice Authorization with VPC Lattice and IAM - CDK Python Implementation"
        )


# Create and run the application
app = MicroserviceAuthorizationApp()
app.synth()