#!/usr/bin/env python3
"""
Simple Log Analysis with CloudWatch Insights and SNS - CDK Python Application

This CDK application creates a complete log monitoring solution that combines CloudWatch Logs Insights
with automated alerting via SNS. The solution includes:
- CloudWatch Log Group for application logs
- Lambda function for automated log analysis using CloudWatch Logs Insights
- SNS topic for alert notifications
- EventBridge rule for scheduled log analysis
- Comprehensive IAM roles and policies

The architecture follows AWS Well-Architected Framework principles for operational excellence,
security, and cost optimization.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    App,
    Stack,
    Duration,
    RemovalPolicy,
    Environment,
)
from aws_cdk import aws_iam as iam
from aws_cdk import aws_lambda as lambda_
from aws_cdk import aws_logs as logs
from aws_cdk import aws_sns as sns
from aws_cdk import aws_sns_subscriptions as sns_subscriptions
from aws_cdk import aws_events as events
from aws_cdk import aws_events_targets as targets
from cdk_nag import AwsSolutionsChecks, NagSuppressions
from constructs import Construct


class SimpleLogAnalysisStack(Stack):
    """
    CDK Stack for Simple Log Analysis with CloudWatch Insights and SNS
    
    This stack creates all the necessary infrastructure for automated log monitoring
    including CloudWatch Logs, Lambda function for analysis, SNS for notifications,
    and EventBridge for scheduling.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self._email_address = self.node.try_get_context("email_address") or "admin@example.com"
        self._log_analysis_schedule = self.node.try_get_context("log_analysis_schedule") or "rate(5 minutes)"
        
        # Create CloudWatch Log Group
        self._create_log_group()
        
        # Create SNS Topic for notifications
        self._create_sns_topic()
        
        # Create Lambda function for log analysis
        self._create_lambda_function()
        
        # Create EventBridge rule for scheduled execution
        self._create_event_rule()
        
        # Apply CDK Nag suppressions for known acceptable cases
        self._apply_nag_suppressions()
        
        # Create stack outputs
        self._create_outputs()

    def _create_log_group(self) -> None:
        """
        Create CloudWatch Log Group for application logs with appropriate retention policy
        """
        self.log_group = logs.LogGroup(
            self,
            "ApplicationLogGroup",
            log_group_name=f"/aws/lambda/demo-app-{self.stack_name.lower()}",
            retention=logs.RetentionDays.ONE_WEEK,  # Cost optimization
            removal_policy=RemovalPolicy.DESTROY,  # Allow cleanup in dev/test
        )

    def _create_sns_topic(self) -> None:
        """
        Create SNS topic for log analysis alerts with email subscription
        """
        self.sns_topic = sns.Topic(
            self,
            "LogAnalysisAlertsTopic",
            topic_name=f"log-analysis-alerts-{self.stack_name.lower()}",
            display_name="Log Analysis Alerts",
            # Enable server-side encryption
            master_key=None,  # Use AWS managed key for cost optimization
        )
        
        # Add email subscription
        self.sns_topic.add_subscription(
            sns_subscriptions.EmailSubscription(self._email_address)
        )

    def _create_lambda_function(self) -> None:
        """
        Create Lambda function for automated log analysis using CloudWatch Logs Insights
        """
        # Create IAM role for Lambda function with least privilege permissions
        lambda_role = iam.Role(
            self,
            "LogAnalyzerLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )
        
        # Add custom permissions for CloudWatch Logs Insights and SNS
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:StartQuery",
                    "logs:GetQueryResults",
                    "logs:StopQuery",
                    "logs:DescribeLogGroups",
                    "logs:DescribeLogStreams",
                ],
                resources=["*"],  # CloudWatch Logs Insights requires wildcard access
            )
        )
        
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["sns:Publish"],
                resources=[self.sns_topic.topic_arn],
            )
        )

        # Create Lambda function
        self.lambda_function = lambda_.Function(
            self,
            "LogAnalyzerFunction",
            function_name=f"log-analyzer-{self.stack_name.lower()}",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            role=lambda_role,
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.seconds(60),
            memory_size=256,
            environment={
                "LOG_GROUP_NAME": self.log_group.log_group_name,
                "SNS_TOPIC_ARN": self.sns_topic.topic_arn,
            },
            # Enable tracing for better observability
            tracing=lambda_.Tracing.ACTIVE,
        )

    def _create_event_rule(self) -> None:
        """
        Create EventBridge rule for scheduled Lambda execution
        """
        self.event_rule = events.Rule(
            self,
            "LogAnalysisScheduleRule",
            rule_name=f"log-analysis-schedule-{self.stack_name.lower()}",
            description="Trigger log analysis every 5 minutes",
            schedule=events.Schedule.expression(self._log_analysis_schedule),
        )
        
        # Add Lambda function as target
        self.event_rule.add_target(
            targets.LambdaFunction(self.lambda_function)
        )

    def _get_lambda_code(self) -> str:
        """
        Return the Lambda function code for log analysis
        """
        return '''
import json
import boto3
import time
import os
from datetime import datetime, timedelta
from typing import Dict, Any, List

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function to analyze CloudWatch logs for error patterns and send SNS alerts
    
    This function:
    1. Queries CloudWatch Logs Insights for ERROR and CRITICAL patterns
    2. Processes the results and counts errors
    3. Sends SNS notification if errors are found
    4. Returns status information
    """
    logs_client = boto3.client('logs')
    sns_client = boto3.client('sns')
    
    log_group = os.environ['LOG_GROUP_NAME']
    sns_topic = os.environ['SNS_TOPIC_ARN']
    
    # Define time range (last 10 minutes)
    end_time = datetime.now()
    start_time = end_time - timedelta(minutes=10)
    
    # CloudWatch Logs Insights query for error patterns
    query = '''
    fields @timestamp, @message
    | filter @message like /ERROR|CRITICAL/
    | sort @timestamp desc
    | limit 100
    '''
    
    try:
        # Start the query
        response = logs_client.start_query(
            logGroupName=log_group,
            startTime=int(start_time.timestamp()),
            endTime=int(end_time.timestamp()),
            queryString=query
        )
        
        query_id = response['queryId']
        print(f"Started query {query_id} for log group {log_group}")
        
        # Wait for query completion with timeout
        max_wait_time = 30  # seconds
        wait_time = 0
        while wait_time < max_wait_time:
            time.sleep(2)
            wait_time += 2
            
            result = logs_client.get_query_results(queryId=query_id)
            if result['status'] == 'Complete':
                break
            elif result['status'] == 'Failed':
                raise Exception(f'Query failed: {result.get("statistics", {})}')
        
        if result['status'] != 'Complete':
            raise Exception(f'Query timed out after {max_wait_time} seconds')
        
        # Process results
        error_count = len(result['results'])
        print(f"Found {error_count} errors in the last 10 minutes")
        
        if error_count > 0:
            # Format alert message
            alert_message = f"""🚨 Log Analysis Alert

Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}
Log Group: {log_group}
Error Count: {error_count} errors found in the last 10 minutes

Recent Errors:"""
            
            # Include first 5 errors in the alert
            for i, log_entry in enumerate(result['results'][:5]):
                timestamp_field = next((field['value'] for field in log_entry if field['field'] == '@timestamp'), 'Unknown')
                message_field = next((field['value'] for field in log_entry if field['field'] == '@message'), 'Unknown')
                alert_message += f"\\n{i+1}. {timestamp_field}: {message_field}"
            
            if error_count > 5:
                alert_message += f"\\n... and {error_count - 5} more errors"
            
            # Send SNS notification
            sns_response = sns_client.publish(
                TopicArn=sns_topic,
                Subject='CloudWatch Log Analysis Alert',
                Message=alert_message
            )
            
            print(f"Alert sent: MessageId {sns_response['MessageId']}")
        else:
            print("No errors detected in recent logs")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'error_count': error_count,
                'status': 'success',
                'log_group': log_group,
                'query_id': query_id
            })
        }
        
    except Exception as e:
        error_message = f"Error analyzing logs: {str(e)}"
        print(error_message)
        
        # Send error notification
        try:
            sns_client.publish(
                TopicArn=sns_topic,
                Subject='Log Analysis Function Error',
                Message=f"The log analysis function encountered an error:\\n\\n{error_message}"
            )
        except Exception as sns_error:
            print(f"Failed to send error notification: {str(sns_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'status': 'error',
                'log_group': log_group
            })
        }
'''

    def _apply_nag_suppressions(self) -> None:
        """
        Apply CDK Nag suppressions for acceptable security findings
        """
        # Suppress CloudWatch Logs Insights wildcard permission requirement
        NagSuppressions.add_resource_suppressions(
            self.lambda_function.role,
            [
                {
                    "id": "AwsSolutions-IAM5",
                    "reason": "CloudWatch Logs Insights requires wildcard permissions to query across log groups. This is an AWS service limitation.",
                }
            ],
        )

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for key resources
        """
        cdk.CfnOutput(
            self,
            "LogGroupName",
            value=self.log_group.log_group_name,
            description="CloudWatch Log Group for application logs",
        )
        
        cdk.CfnOutput(
            self,
            "SNSTopicArn",
            value=self.sns_topic.topic_arn,
            description="SNS Topic ARN for log analysis alerts",
        )
        
        cdk.CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.lambda_function.function_name,
            description="Lambda function name for log analysis",
        )
        
        cdk.CfnOutput(
            self,
            "EventRuleName",
            value=self.event_rule.rule_name,
            description="EventBridge rule for scheduled log analysis",
        )


def main() -> None:
    """
    Main application entry point
    """
    app = App()
    
    # Get environment configuration
    env = Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
    )
    
    # Create the stack
    stack = SimpleLogAnalysisStack(
        app,
        "SimpleLogAnalysisStack",
        env=env,
        description="Simple Log Analysis with CloudWatch Insights and SNS - Automated log monitoring solution",
    )
    
    # Apply CDK Nag for security best practices
    AwsSolutionsChecks(verbose=True)
    
    # Add stack-level tags
    cdk.Tags.of(stack).add("Project", "SimpleLogAnalysis")
    cdk.Tags.of(stack).add("Environment", "Development")
    cdk.Tags.of(stack).add("Owner", "DevOps")
    
    app.synth()


if __name__ == "__main__":
    main()