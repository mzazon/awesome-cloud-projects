#!/usr/bin/env python3
"""
AWS CDK Python application for Resource Cleanup Automation with Lambda and Tags.

This CDK application creates an automated resource cleanup system using AWS Lambda
to identify and terminate EC2 instances based on specific tags, with SNS notifications
to alert administrators about cleanup actions.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_lambda as _lambda,
    aws_iam as iam,
    aws_sns as sns,
    aws_sns_subscriptions as subs,
    aws_events as events,
    aws_events_targets as targets,
    aws_logs as logs,
)
from constructs import Construct


class ResourceCleanupStack(Stack):
    """
    CDK Stack for automated resource cleanup using Lambda and tags.
    
    This stack creates:
    - Lambda function for resource cleanup
    - IAM role with appropriate permissions
    - SNS topic for notifications
    - CloudWatch Events rule for scheduling (optional)
    - CloudWatch Log Group for Lambda logs
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        email_address: str = None,
        enable_scheduled_cleanup: bool = False,
        cleanup_schedule: str = "rate(1 day)",
        **kwargs
    ) -> None:
        """
        Initialize the Resource Cleanup Stack.
        
        Args:
            scope: The scope in which to define this construct.
            construct_id: The scoped construct ID.
            email_address: Email address for SNS notifications (optional).
            enable_scheduled_cleanup: Whether to enable scheduled cleanup.
            cleanup_schedule: Schedule expression for cleanup (default: daily).
            **kwargs: Additional keyword arguments.
        """
        super().__init__(scope, construct_id, **kwargs)

        # Create SNS topic for cleanup notifications
        self.cleanup_topic = sns.Topic(
            self,
            "CleanupAlertsTopic",
            display_name="Resource Cleanup Alerts",
            description="Notifications for automated resource cleanup actions",
        )

        # Subscribe email to SNS topic if provided
        if email_address:
            self.cleanup_topic.add_subscription(
                subs.EmailSubscription(email_address)
            )

        # Create CloudWatch Log Group for Lambda function
        self.log_group = logs.LogGroup(
            self,
            "CleanupFunctionLogGroup",
            log_group_name="/aws/lambda/resource-cleanup-function",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create IAM role for Lambda function
        self.lambda_role = iam.Role(
            self,
            "CleanupFunctionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for resource cleanup Lambda function",
            inline_policies={
                "ResourceCleanupPolicy": iam.PolicyDocument(
                    statements=[
                        # CloudWatch Logs permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents",
                            ],
                            resources=[
                                f"arn:aws:logs:{self.region}:{self.account}:*"
                            ],
                        ),
                        # EC2 permissions for describing and terminating instances
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "ec2:DescribeInstances",
                                "ec2:TerminateInstances",
                                "ec2:DescribeTags",
                            ],
                            resources=["*"],
                        ),
                        # SNS permissions for publishing notifications
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["sns:Publish"],
                            resources=[self.cleanup_topic.topic_arn],
                        ),
                    ]
                )
            },
        )

        # Create Lambda function for resource cleanup
        self.cleanup_function = _lambda.Function(
            self,
            "ResourceCleanupFunction",
            runtime=_lambda.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            role=self.lambda_role,
            code=_lambda.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.minutes(5),
            memory_size=256,
            description="Automated cleanup of tagged EC2 instances",
            environment={
                "SNS_TOPIC_ARN": self.cleanup_topic.topic_arn,
                "AWS_REGION": self.region,
            },
            log_group=self.log_group,
        )

        # Create CloudWatch Events rule for scheduled cleanup (optional)
        if enable_scheduled_cleanup:
            self.cleanup_schedule = events.Rule(
                self,
                "CleanupScheduleRule",
                description="Scheduled rule for resource cleanup",
                schedule=events.Schedule.expression(cleanup_schedule),
            )
            
            # Add Lambda function as target
            self.cleanup_schedule.add_target(
                targets.LambdaFunction(self.cleanup_function)
            )

        # Create outputs for important resource identifiers
        cdk.CfnOutput(
            self,
            "CleanupFunctionName",
            value=self.cleanup_function.function_name,
            description="Name of the cleanup Lambda function",
        )

        cdk.CfnOutput(
            self,
            "CleanupTopicArn",
            value=self.cleanup_topic.topic_arn,
            description="ARN of the SNS topic for cleanup notifications",
        )

        cdk.CfnOutput(
            self,
            "CleanupFunctionArn",
            value=self.cleanup_function.function_arn,
            description="ARN of the cleanup Lambda function",
        )

        if enable_scheduled_cleanup:
            cdk.CfnOutput(
                self,
                "CleanupScheduleRuleArn",
                value=self.cleanup_schedule.rule_arn,
                description="ARN of the CloudWatch Events rule for scheduled cleanup",
            )

    def _get_lambda_code(self) -> str:
        """
        Returns the Lambda function code as a string.
        
        Returns:
            str: The complete Lambda function code.
        """
        return '''
import json
import boto3
import os
from datetime import datetime, timezone
from typing import List, Dict, Any


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for automated EC2 instance cleanup based on tags.
    
    This function:
    1. Queries EC2 instances with the 'AutoCleanup' tag set to 'true'
    2. Terminates matching instances
    3. Sends SNS notifications about cleanup actions
    4. Handles errors gracefully with notifications
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Dict containing status code and response body
    """
    ec2 = boto3.client('ec2')
    sns = boto3.client('sns')
    
    # Get environment variables
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    aws_region = os.environ.get('AWS_REGION', 'Unknown')
    
    try:
        print("Starting resource cleanup process...")
        
        # Query instances with cleanup tag
        response = ec2.describe_instances(
            Filters=[
                {
                    'Name': 'tag:AutoCleanup',
                    'Values': ['true', 'True', 'TRUE']
                },
                {
                    'Name': 'instance-state-name',
                    'Values': ['running', 'stopped']
                }
            ]
        )
        
        instances_to_cleanup: List[Dict[str, str]] = []
        
        # Extract instance information
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instance_id = instance['InstanceId']
                instance_name = 'Unnamed'
                instance_type = instance.get('InstanceType', 'Unknown')
                launch_time = instance.get('LaunchTime', 'Unknown')
                
                # Get instance name from tags
                for tag in instance.get('Tags', []):
                    if tag['Key'] == 'Name':
                        instance_name = tag['Value']
                        break
                
                instances_to_cleanup.append({
                    'InstanceId': instance_id,
                    'Name': instance_name,
                    'State': instance['State']['Name'],
                    'Type': instance_type,
                    'LaunchTime': str(launch_time)
                })
        
        if not instances_to_cleanup:
            print("No instances found with AutoCleanup tag")
            message = f"""
AWS Resource Cleanup Report
Time: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC
Region: {aws_region}

No EC2 instances were found with the AutoCleanup tag.
The cleanup function executed successfully but found no resources to clean up.
"""
            
            # Send notification about no cleanup needed
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject='AWS Resource Cleanup - No Action Needed',
                Message=message
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps('No instances to cleanup')
            }
        
        print(f"Found {len(instances_to_cleanup)} instances to cleanup")
        
        # Terminate instances
        instance_ids = [inst['InstanceId'] for inst in instances_to_cleanup]
        ec2.terminate_instances(InstanceIds=instance_ids)
        
        print(f"Initiated termination for instances: {instance_ids}")
        
        # Build detailed notification message
        message = f"""
AWS Resource Cleanup Report
Time: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC
Region: {aws_region}

The following EC2 instances were terminated:

"""
        
        for instance in instances_to_cleanup:
            message += f"• {instance['Name']} ({instance['InstanceId']})\n"
            message += f"  - Type: {instance['Type']}\n"
            message += f"  - Previous State: {instance['State']}\n"
            message += f"  - Launch Time: {instance['LaunchTime']}\n\\n"
        
        message += f"Total instances cleaned up: {len(instances_to_cleanup)}\\n"
        message += f"\\nEstimated monthly savings: Varies by instance type and usage\\n"
        message += f"\\nNote: This cleanup was performed automatically based on the 'AutoCleanup=true' tag."
        
        # Publish success notification to SNS
        sns.publish(
            TopicArn=sns_topic_arn,
            Subject=f'AWS Resource Cleanup Completed - {len(instances_to_cleanup)} Instances',
            Message=message
        )
        
        print(f"Successfully terminated {len(instances_to_cleanup)} instances")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Cleaned up {len(instances_to_cleanup)} instances',
                'instances': instances_to_cleanup
            })
        }
        
    except Exception as e:
        error_message = f"Error during cleanup: {str(e)}"
        print(f"ERROR: {error_message}")
        
        # Send error notification
        try:
            error_notification = f"""
AWS Resource Cleanup Error Report
Time: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC
Region: {aws_region}

An error occurred during the automated resource cleanup process:

Error Details:
{error_message}

Please check the CloudWatch logs for more detailed information and investigate the issue.
Function Name: {context.function_name if context else 'Unknown'}
Request ID: {context.aws_request_id if context else 'Unknown'}
"""
            
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject='AWS Resource Cleanup Error - Immediate Attention Required',
                Message=error_notification
            )
            print("Error notification sent successfully")
            
        except Exception as sns_error:
            print(f"Failed to send error notification: {sns_error}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'message': 'Cleanup failed - check logs for details'
            })
        }
'''


class ResourceCleanupApp(cdk.App):
    """
    CDK Application for Resource Cleanup Automation.
    """

    def __init__(self, **kwargs) -> None:
        """Initialize the CDK application."""
        super().__init__(**kwargs)

        # Get configuration from context or environment variables
        email_address = self.node.try_get_context("email_address") or os.environ.get("CLEANUP_EMAIL_ADDRESS")
        enable_scheduled = self.node.try_get_context("enable_scheduled_cleanup") or False
        cleanup_schedule = self.node.try_get_context("cleanup_schedule") or "rate(1 day)"

        # Create the main stack
        ResourceCleanupStack(
            self,
            "ResourceCleanupStack",
            email_address=email_address,
            enable_scheduled_cleanup=enable_scheduled,
            cleanup_schedule=cleanup_schedule,
            description="Automated resource cleanup system using Lambda and tags",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
            ),
        )


# Create and run the CDK application
if __name__ == "__main__":
    app = ResourceCleanupApp()
    app.synth()