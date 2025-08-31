#!/usr/bin/env python3
"""
CDK Python application for Canary Deployments with VPC Lattice and Lambda.

This application implements a progressive canary deployment system using:
- AWS Lambda function versions for production and canary code
- VPC Lattice for sophisticated traffic routing and service mesh capabilities
- CloudWatch for monitoring and automated rollback mechanisms
- Weighted routing to gradually shift traffic between versions

Architecture:
- Lambda functions with versioning for canary deployments
- VPC Lattice service network with weighted target groups
- CloudWatch alarms with automatic rollback capabilities
- IAM roles with least privilege access
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    CfnOutput,
    RemovalPolicy,
    aws_lambda as _lambda,
    aws_iam as iam,
    aws_vpclattice as lattice,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    aws_logs as logs,
)
from constructs import Construct
import json


class CanaryDeploymentLatticeStack(Stack):
    """
    CDK Stack for implementing canary deployments using VPC Lattice and Lambda.
    
    This stack creates a complete canary deployment infrastructure with:
    - Lambda functions with production and canary versions
    - VPC Lattice service network for traffic management
    - Weighted routing for progressive traffic shifting
    - CloudWatch monitoring and automated rollback
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource naming
        unique_suffix = self.node.addr[-6:].lower()

        # Create IAM execution role for Lambda functions
        lambda_execution_role = iam.Role(
            self, "LambdaExecutionRole",
            role_name=f"lambda-canary-execution-role-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "VPCLatticeServiceAccess"
                )
            ],
            description="Execution role for canary deployment Lambda functions"
        )

        # Create CloudWatch Log Group for Lambda functions
        lambda_log_group = logs.LogGroup(
            self, "LambdaLogGroup",
            log_group_name=f"/aws/lambda/canary-demo-function-{unique_suffix}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Create Lambda function for canary deployment
        canary_function = _lambda.Function(
            self, "CanaryDemoFunction",
            function_name=f"canary-demo-function-{unique_suffix}",
            runtime=_lambda.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(self._get_production_lambda_code()),
            role=lambda_execution_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            description="Lambda function for canary deployment demonstration",
            log_group=lambda_log_group,
            environment={
                "DEPLOYMENT_STAGE": "production",
                "VERSION": "1.0.0"
            }
        )

        # Publish production version (v1)
        production_version = _lambda.Version(
            self, "ProductionVersion",
            lambda_=canary_function,
            description="Production version 1.0.0",
            removal_policy=RemovalPolicy.RETAIN
        )

        # Update function code for canary version and publish v2
        canary_version = _lambda.Version(
            self, "CanaryVersion",
            lambda_=canary_function,
            description="Canary version 2.0.0 with enhanced features",
            removal_policy=RemovalPolicy.RETAIN,
            code_sha256_changed=True  # This ensures a new version is created
        )

        # Create VPC Lattice Service Network
        service_network = lattice.CfnServiceNetwork(
            self, "CanaryServiceNetwork",
            name=f"canary-demo-network-{unique_suffix}",
            auth_type="NONE"
        )

        # Create Target Group for Production Version
        production_target_group = lattice.CfnTargetGroup(
            self, "ProductionTargetGroup",
            name=f"prod-targets-{unique_suffix}",
            type="LAMBDA",
            targets=[
                lattice.CfnTargetGroup.TargetProperty(
                    id=f"{canary_function.function_arn}:{production_version.version}"
                )
            ]
        )

        # Create Target Group for Canary Version
        canary_target_group = lattice.CfnTargetGroup(
            self, "CanaryTargetGroup",
            name=f"canary-targets-{unique_suffix}",
            type="LAMBDA",
            targets=[
                lattice.CfnTargetGroup.TargetProperty(
                    id=f"{canary_function.function_arn}:{canary_version.version}"
                )
            ]
        )

        # Create VPC Lattice Service with weighted routing
        lattice_service = lattice.CfnService(
            self, "CanaryService",
            name=f"canary-demo-service-{unique_suffix}",
            auth_type="NONE"
        )

        # Create HTTP Listener with weighted routing for canary deployment
        lattice_listener = lattice.CfnListener(
            self, "CanaryListener",
            name="canary-listener",
            service_identifier=lattice_service.attr_id,
            protocol="HTTP",
            port=80,
            default_action=lattice.CfnListener.DefaultActionProperty(
                forward=lattice.CfnListener.ForwardProperty(
                    target_groups=[
                        lattice.CfnListener.WeightedTargetGroupProperty(
                            target_group_identifier=production_target_group.attr_id,
                            weight=90
                        ),
                        lattice.CfnListener.WeightedTargetGroupProperty(
                            target_group_identifier=canary_target_group.attr_id,
                            weight=10
                        )
                    ]
                )
            )
        )

        # Associate service with service network
        lattice.CfnServiceNetworkServiceAssociation(
            self, "ServiceNetworkAssociation",
            service_network_identifier=service_network.attr_id,
            service_identifier=lattice_service.attr_id
        )

        # Create SNS topic for rollback notifications
        rollback_topic = sns.Topic(
            self, "RollbackTopic",
            topic_name=f"canary-rollback-{unique_suffix}",
            description="SNS topic for canary deployment rollback notifications"
        )

        # Create automatic rollback Lambda function
        rollback_function = _lambda.Function(
            self, "RollbackFunction",
            function_name=f"canary-rollback-{unique_suffix}",
            runtime=_lambda.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(self._get_rollback_lambda_code()),
            role=self._create_rollback_role(unique_suffix, lattice_service, lattice_listener, production_target_group),
            timeout=Duration.seconds(60),
            memory_size=256,
            description="Automatic rollback function for canary deployments",
            environment={
                "SERVICE_ID": lattice_service.attr_id,
                "LISTENER_ID": lattice_listener.attr_id,
                "PROD_TARGET_GROUP_ID": production_target_group.attr_id
            }
        )

        # Subscribe rollback function to SNS topic
        rollback_topic.add_subscription(
            sns.LambdaSubscription(rollback_function)
        )

        # Create CloudWatch alarms for canary monitoring
        self._create_cloudwatch_alarms(
            unique_suffix, 
            canary_function, 
            canary_version, 
            rollback_topic
        )

        # Output important values
        CfnOutput(
            self, "ServiceNetworkId",
            value=service_network.attr_id,
            description="VPC Lattice Service Network ID"
        )

        CfnOutput(
            self, "ServiceId",
            value=lattice_service.attr_id,
            description="VPC Lattice Service ID"
        )

        CfnOutput(
            self, "ServiceDNS",
            value=lattice_service.attr_dns_entry.domain_name,
            description="VPC Lattice Service DNS endpoint"
        )

        CfnOutput(
            self, "ListenerId",
            value=lattice_listener.attr_id,
            description="VPC Lattice Listener ID for traffic management"
        )

        CfnOutput(
            self, "ProductionVersion",
            value=production_version.version,
            description="Lambda function production version"
        )

        CfnOutput(
            self, "CanaryVersion",
            value=canary_version.version,
            description="Lambda function canary version"
        )

        CfnOutput(
            self, "RollbackTopicArn",
            value=rollback_topic.topic_arn,
            description="SNS topic ARN for rollback notifications"
        )

    def _get_production_lambda_code(self) -> str:
        """Generate production Lambda function code."""
        return '''
import json
import time

def lambda_handler(event, context):
    """Production version Lambda handler."""
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json'
        },
        'body': json.dumps({
            'version': 'v1.0.0',
            'message': 'Hello from production version',
            'timestamp': int(time.time()),
            'environment': 'production'
        })
    }
'''

    def _get_canary_lambda_code(self) -> str:
        """Generate canary Lambda function code."""
        return '''
import json
import time
import random

def lambda_handler(event, context):
    """Canary version Lambda handler with enhanced features."""
    features = ['feature-a', 'feature-b', 'enhanced-logging']
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'X-Version': 'v2.0.0'
        },
        'body': json.dumps({
            'version': 'v2.0.0',
            'message': 'Hello from canary version',
            'timestamp': int(time.time()),
            'environment': 'canary',
            'features': features,
            'response_time': random.randint(50, 200)
        })
    }
'''

    def _get_rollback_lambda_code(self) -> str:
        """Generate automatic rollback Lambda function code."""
        return '''
import boto3
import json
import os

def lambda_handler(event, context):
    """Automatic rollback function for canary deployments."""
    lattice = boto3.client('vpc-lattice')
    
    try:
        # Parse CloudWatch alarm
        message = json.loads(event['Records'][0]['Sns']['Message'])
        alarm_name = message['AlarmName']
        
        if 'canary' in alarm_name and message['NewStateValue'] == 'ALARM':
            # Rollback to 100% production traffic
            lattice.update_listener(
                serviceIdentifier=os.environ['SERVICE_ID'],
                listenerIdentifier=os.environ['LISTENER_ID'],
                defaultAction={
                    'forward': {
                        'targetGroups': [
                            {
                                'targetGroupIdentifier': os.environ['PROD_TARGET_GROUP_ID'],
                                'weight': 100
                            }
                        ]
                    }
                }
            )
            print(f"Automatic rollback triggered by alarm: {alarm_name}")
            return {'statusCode': 200, 'body': 'Rollback successful'}
        
        return {'statusCode': 200, 'body': 'No action required'}
        
    except Exception as e:
        print(f"Rollback failed: {str(e)}")
        return {'statusCode': 500, 'body': f'Rollback failed: {str(e)}'}
'''

    def _create_rollback_role(self, unique_suffix: str, service, listener, target_group) -> iam.Role:
        """Create IAM role for rollback function with necessary permissions."""
        rollback_role = iam.Role(
            self, "RollbackRole",
            role_name=f"canary-rollback-role-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )

        # Add VPC Lattice permissions for rollback
        rollback_role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "vpc-lattice:UpdateListener",
                "vpc-lattice:GetListener",
                "vpc-lattice:GetService"
            ],
            resources=[
                f"arn:aws:vpc-lattice:{self.region}:{self.account}:service/{service.attr_id}",
                f"arn:aws:vpc-lattice:{self.region}:{self.account}:service/{service.attr_id}/listener/{listener.attr_id}"
            ]
        ))

        return rollback_role

    def _create_cloudwatch_alarms(self, unique_suffix: str, function: _lambda.Function, 
                                  version: _lambda.Version, topic: sns.Topic) -> None:
        """Create CloudWatch alarms for canary monitoring."""
        
        # Alarm for Lambda errors in canary version
        error_alarm = cloudwatch.Alarm(
            self, "CanaryErrorAlarm",
            alarm_name=f"canary-lambda-errors-{unique_suffix}",
            alarm_description="Monitor errors in canary Lambda version",
            metric=cloudwatch.Metric(
                namespace="AWS/Lambda",
                metric_name="Errors",
                dimensions_map={
                    "FunctionName": function.function_name,
                    "Resource": f"{function.function_name}:{version.version}"
                },
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=5,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Alarm for Lambda duration in canary version
        duration_alarm = cloudwatch.Alarm(
            self, "CanaryDurationAlarm",
            alarm_name=f"canary-lambda-duration-{unique_suffix}",
            alarm_description="Monitor duration in canary Lambda version",
            metric=cloudwatch.Metric(
                namespace="AWS/Lambda",
                metric_name="Duration",
                dimensions_map={
                    "FunctionName": function.function_name,
                    "Resource": f"{function.function_name}:{version.version}"
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=5000,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Add SNS actions to alarms
        error_alarm.add_alarm_action(
            cloudwatch.SnsAction(topic)
        )
        duration_alarm.add_alarm_action(
            cloudwatch.SnsAction(topic)
        )


app = cdk.App()

# Create the canary deployment stack
CanaryDeploymentLatticeStack(
    app, 
    "CanaryDeploymentLatticeStack",
    description="CDK stack for canary deployments using VPC Lattice and Lambda",
    tags={
        "Project": "CanaryDeployments",
        "Environment": "Demo",
        "Owner": "CDK"
    }
)

app.synth()