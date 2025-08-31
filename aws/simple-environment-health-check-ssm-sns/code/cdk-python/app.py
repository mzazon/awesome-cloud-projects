#!/usr/bin/env python3
"""
Simple Environment Health Check with Systems Manager and SNS

This CDK application deploys automated environment health monitoring using:
- AWS Systems Manager Compliance for tracking resource health status
- Amazon SNS for immediate notifications when problems are detected
- AWS Lambda for custom health checking logic
- EventBridge for scheduling and event-driven responses

The solution continuously monitors EC2 instances, checks compliance status,
and sends alerts to operations teams through email notifications.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_sns as sns,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_events as events,
    aws_events_targets as targets,
    aws_logs as logs,
    CfnOutput,
    Tags
)
from constructs import Construct


class EnvironmentHealthCheckStack(Stack):
    """
    Stack for deploying environment health check infrastructure.
    
    This stack creates:
    - SNS topic for health notifications
    - Lambda function for performing health checks
    - EventBridge rules for scheduling and compliance events
    - IAM roles and policies with least privilege
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.notification_email = self.node.try_get_context("notification_email") or "your-email@example.com"
        self.environment_name = self.node.try_get_context("environment_name") or "production"
        
        # Create SNS topic for health notifications
        self.health_topic = self._create_sns_topic()
        
        # Create Lambda function for health checks
        self.health_check_function = self._create_health_check_lambda()
        
        # Create EventBridge rules for scheduling and compliance monitoring
        self._create_eventbridge_rules()
        
        # Add tags to all resources
        self._add_resource_tags()
        
        # Create outputs
        self._create_outputs()

    def _create_sns_topic(self) -> sns.Topic:
        """
        Create SNS topic for health notifications with email subscription.
        
        Returns:
            sns.Topic: The created SNS topic
        """
        topic = sns.Topic(
            self, "HealthAlertsTopic",
            topic_name=f"environment-health-alerts-{self.environment_name}",
            display_name="Environment Health Alerts",
            description="SNS topic for environment health monitoring notifications"
        )
        
        # Add email subscription
        topic.add_subscription(
            sns.EmailSubscription(self.notification_email)
        )
        
        return topic

    def _create_health_check_lambda(self) -> lambda_.Function:
        """
        Create Lambda function for performing health checks.
        
        Returns:
            lambda_.Function: The created Lambda function
        """
        # Create IAM role for Lambda function
        lambda_role = iam.Role(
            self, "HealthCheckLambdaRole",
            role_name=f"HealthCheckLambdaRole-{self.environment_name}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for environment health check Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )
        
        # Add custom policy for Systems Manager and SNS access
        health_check_policy = iam.Policy(
            self, "HealthCheckPolicy",
            policy_name=f"HealthCheckPolicy-{self.environment_name}",
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "ssm:DescribeInstanceInformation",
                        "ssm:PutComplianceItems",
                        "ssm:ListComplianceItems",
                        "ssm:ListComplianceSummaries"
                    ],
                    resources=["*"],
                    description="Allow access to Systems Manager for health checks"
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=["sns:Publish"],
                    resources=[self.health_topic.topic_arn],
                    description="Allow publishing to health alerts SNS topic"
                )
            ]
        )
        
        lambda_role.attach_inline_policy(health_check_policy)
        
        # Create Lambda function
        function = lambda_.Function(
            self, "HealthCheckFunction",
            function_name=f"environment-health-check-{self.environment_name}",
            description="Function to perform environment health checks and update compliance",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            role=lambda_role,
            timeout=Duration.seconds(60),
            memory_size=256,
            environment={
                "SNS_TOPIC_ARN": self.health_topic.topic_arn,
                "ENVIRONMENT_NAME": self.environment_name
            },
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            log_retention=logs.RetentionDays.ONE_MONTH
        )
        
        return function

    def _create_eventbridge_rules(self) -> None:
        """
        Create EventBridge rules for scheduling health checks and monitoring compliance events.
        """
        # Create scheduled rule for periodic health checks
        schedule_rule = events.Rule(
            self, "HealthCheckScheduleRule",
            rule_name=f"health-check-schedule-{self.environment_name}",
            description="Schedule health checks every 5 minutes",
            schedule=events.Schedule.rate(Duration.minutes(5)),
            enabled=True
        )
        
        # Add Lambda function as target for scheduled rule
        schedule_rule.add_target(
            targets.LambdaFunction(
                self.health_check_function,
                event=events.RuleTargetInput.from_object({
                    "source": "eventbridge-schedule",
                    "environment": self.environment_name
                })
            )
        )
        
        # Create rule for compliance state changes
        compliance_rule = events.Rule(
            self, "ComplianceAlertsRule",
            rule_name=f"compliance-health-alerts-{self.environment_name}",
            description="Respond to compliance state changes for health monitoring",
            event_pattern=events.EventPattern(
                source=["aws.ssm"],
                detail_type=["Configuration Compliance State Change"],
                detail={
                    "compliance-type": ["Custom:EnvironmentHealth"],
                    "compliance-status": ["NON_COMPLIANT"]
                }
            ),
            enabled=True
        )
        
        # Add SNS topic as target for compliance events
        compliance_rule.add_target(
            targets.SnsTopic(
                self.health_topic,
                message=events.RuleTargetInput.from_text(
                    "Environment Health Alert: Instance <instance> is <status> at <time>. Please investigate immediately."
                ).replace("<instance>", events.EventField.from_path("$.detail.resource-id"))
                .replace("<status>", events.EventField.from_path("$.detail.compliance-status"))
                .replace("<time>", events.EventField.from_path("$.time"))
            )
        )

    def _add_resource_tags(self) -> None:
        """Add consistent tags to all resources in the stack."""
        Tags.of(self).add("Environment", self.environment_name)
        Tags.of(self).add("Purpose", "HealthMonitoring")
        Tags.of(self).add("Service", "EnvironmentHealthCheck")
        Tags.of(self).add("ManagedBy", "CDK")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        CfnOutput(
            self, "SNSTopicArn",
            value=self.health_topic.topic_arn,
            description="ARN of the SNS topic for health alerts",
            export_name=f"{self.stack_name}-SNSTopicArn"
        )
        
        CfnOutput(
            self, "LambdaFunctionName",
            value=self.health_check_function.function_name,
            description="Name of the health check Lambda function",
            export_name=f"{self.stack_name}-LambdaFunctionName"
        )
        
        CfnOutput(
            self, "LambdaFunctionArn",
            value=self.health_check_function.function_arn,
            description="ARN of the health check Lambda function",
            export_name=f"{self.stack_name}-LambdaFunctionArn"
        )

    def _get_lambda_code(self) -> str:
        """
        Get the Lambda function code for health checks.
        
        Returns:
            str: The Lambda function code as a string
        """
        return '''
import json
import boto3
import logging
import os
from datetime import datetime
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Health check function that monitors SSM agent status
    and updates Systems Manager compliance accordingly.
    
    Args:
        event: Lambda event object
        context: Lambda context object
        
    Returns:
        dict: Response with status code and execution details
    """
    ssm = boto3.client('ssm')
    sns = boto3.client('sns')
    
    sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
    environment_name = os.environ.get('ENVIRONMENT_NAME', 'production')
    
    try:
        # Get all managed instances
        logger.info("Starting health check for managed instances")
        response = ssm.describe_instance_information()
        
        compliance_items = []
        non_compliant_instances = []
        total_instances = len(response['InstanceInformationList'])
        
        logger.info(f"Found {total_instances} managed instances to check")
        
        for instance in response['InstanceInformationList']:
            instance_id = instance['InstanceId']
            ping_status = instance['PingStatus']
            last_ping_time = instance.get('LastPingDateTime', 'Unknown')
            instance_type = instance.get('InstanceType', 'Unknown')
            platform_type = instance.get('PlatformType', 'Unknown')
            
            # Determine compliance status based on ping status
            status = 'COMPLIANT' if ping_status == 'Online' else 'NON_COMPLIANT'
            severity = 'HIGH' if status == 'NON_COMPLIANT' else 'INFORMATIONAL'
            
            if status == 'NON_COMPLIANT':
                non_compliant_instances.append({
                    'InstanceId': instance_id,
                    'PingStatus': ping_status,
                    'LastPingTime': str(last_ping_time),
                    'InstanceType': instance_type,
                    'PlatformType': platform_type
                })
                logger.warning(f"Instance {instance_id} is non-compliant: {ping_status}")
            
            # Update compliance with enhanced details
            compliance_item = {
                'Id': f'HealthCheck-{instance_id}',
                'Title': 'InstanceConnectivityCheck',
                'Severity': severity,
                'Status': status,
                'Details': {
                    'PingStatus': ping_status,
                    'LastPingTime': str(last_ping_time),
                    'CheckTime': datetime.utcnow().isoformat() + 'Z',
                    'InstanceType': instance_type,
                    'PlatformType': platform_type,
                    'Environment': environment_name
                }
            }
            
            try:
                ssm.put_compliance_items(
                    ResourceId=instance_id,
                    ResourceType='ManagedInstance',
                    ComplianceType='Custom:EnvironmentHealth',
                    ExecutionSummary={
                        'ExecutionTime': datetime.utcnow().isoformat() + 'Z',
                        'ExecutionId': context.aws_request_id,
                        'ExecutionType': 'Command'
                    },
                    Items=[compliance_item]
                )
                logger.info(f"Updated compliance for instance {instance_id}: {status}")
            except ClientError as e:
                logger.error(f"Failed to update compliance for {instance_id}: {str(e)}")
            
            compliance_items.append(compliance_item)
        
        # Log health check results
        logger.info(f"Health check completed for {len(compliance_items)} instances")
        logger.info(f"Non-compliant instances: {len(non_compliant_instances)}")
        
        # Send notification if there are non-compliant instances
        if non_compliant_instances and sns_topic_arn:
            subject = f"Environment Health Alert - {environment_name}"
            message = f"Environment Health Alert for {environment_name}\\n\\n"
            message += f"Found {len(non_compliant_instances)} non-compliant instances out of {total_instances} total instances:\\n\\n"
            
            for instance in non_compliant_instances:
                message += f"• Instance: {instance['InstanceId']}\\n"
                message += f"  Status: {instance['PingStatus']}\\n"
                message += f"  Type: {instance['InstanceType']} ({instance['PlatformType']})\\n"
                message += f"  Last Ping: {instance['LastPingTime']}\\n\\n"
            
            message += f"Please investigate these instances immediately.\\n"
            message += f"Check Time: {datetime.utcnow().isoformat()}Z\\n"
            
            try:
                sns.publish(
                    TopicArn=sns_topic_arn,
                    Subject=subject,
                    Message=message
                )
                logger.info(f"Sent alert notification for {len(non_compliant_instances)} non-compliant instances")
            except ClientError as e:
                logger.error(f"Failed to send SNS notification: {str(e)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Health check completed successfully',
                'environment': environment_name,
                'total_instances': len(compliance_items),
                'non_compliant_instances': len(non_compliant_instances),
                'execution_id': context.aws_request_id,
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            })
        }
        
    except ClientError as e:
        error_message = f"AWS API error: {str(e)}"
        logger.error(error_message)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'execution_id': context.aws_request_id,
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            })
        }
    except Exception as e:
        error_message = f"Unexpected error: {str(e)}"
        logger.error(error_message)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'execution_id': context.aws_request_id,
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            })
        }
'''


def main() -> None:
    """Main function to create and deploy the CDK app."""
    app = cdk.App()
    
    # Get configuration from context or environment variables
    environment_name = app.node.try_get_context("environment_name") or os.environ.get("ENVIRONMENT_NAME", "production")
    notification_email = app.node.try_get_context("notification_email") or os.environ.get("NOTIFICATION_EMAIL", "your-email@example.com")
    
    # Create the stack
    EnvironmentHealthCheckStack(
        app, 
        f"EnvironmentHealthCheckStack-{environment_name}",
        description=f"Environment Health Check monitoring stack for {environment_name}",
        env=cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        )
    )
    
    app.synth()


if __name__ == "__main__":
    main()