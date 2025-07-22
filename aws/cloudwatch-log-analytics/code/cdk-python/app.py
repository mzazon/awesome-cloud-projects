#!/usr/bin/env python3
"""
CDK Application for CloudWatch Logs Insights Analytics Solution

This application deploys a complete log analytics solution using AWS CloudWatch Logs,
CloudWatch Logs Insights, Lambda functions for automated analysis, and SNS for alerting.
The solution provides real-time log monitoring, automated error detection, and
intelligent notification capabilities.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_logs as logs,
    aws_lambda as lambda_,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    aws_events as events,
    aws_events_targets as targets,
    aws_iam as iam,
    CfnOutput,
    Tags
)
from constructs import Construct


class LogAnalyticsStack(Stack):
    """
    Stack for deploying CloudWatch Logs Insights analytics solution.
    
    This stack creates:
    - CloudWatch Log Groups for centralized logging
    - Lambda function for automated log analysis
    - SNS topic for alert notifications
    - CloudWatch Events rule for scheduled analysis
    - IAM roles and policies with least privilege access
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        notification_email: str,
        **kwargs: Any
    ) -> None:
        """
        Initialize the Log Analytics Stack.
        
        Args:
            scope: CDK construct scope
            construct_id: Stack identifier
            notification_email: Email address for receiving alerts
            **kwargs: Additional stack parameters
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource naming
        unique_suffix = cdk.Fn.select(
            2, cdk.Fn.split("-", cdk.Fn.select(2, cdk.Fn.split("/", self.stack_id)))
        )

        # Create CloudWatch Log Group for centralized logging
        self.log_group = self._create_log_group(unique_suffix)

        # Create SNS topic for notifications
        self.sns_topic = self._create_sns_topic(unique_suffix, notification_email)

        # Create Lambda function for log analysis
        self.analysis_lambda = self._create_analysis_lambda(unique_suffix)

        # Create CloudWatch Events rule for scheduled analysis
        self.schedule_rule = self._create_schedule_rule(unique_suffix)

        # Add stack outputs
        self._create_outputs()

        # Apply resource tags
        self._apply_tags()

    def _create_log_group(self, suffix: str) -> logs.LogGroup:
        """
        Create CloudWatch Log Group with appropriate retention policy.
        
        Args:
            suffix: Unique suffix for resource naming
            
        Returns:
            CloudWatch Log Group construct
        """
        log_group = logs.LogGroup(
            self,
            "LogAnalyticsLogGroup",
            log_group_name=f"/aws/lambda/log-analytics-{suffix}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Add initial log stream for testing
        logs.LogStream(
            self,
            "ApiServerLogStream",
            log_group=log_group,
            log_stream_name="api-server-001",
            removal_policy=RemovalPolicy.DESTROY
        )

        return log_group

    def _create_sns_topic(self, suffix: str, email: str) -> sns.Topic:
        """
        Create SNS topic with email subscription for alerts.
        
        Args:
            suffix: Unique suffix for resource naming
            email: Email address for notifications
            
        Returns:
            SNS Topic construct
        """
        topic = sns.Topic(
            self,
            "LogAnalyticsTopic",
            topic_name=f"log-analytics-alerts-{suffix}",
            display_name="Log Analytics Alerts",
            fifo=False
        )

        # Add email subscription
        topic.add_subscription(
            subscriptions.EmailSubscription(email)
        )

        return topic

    def _create_analysis_lambda(self, suffix: str) -> lambda_.Function:
        """
        Create Lambda function for automated log analysis.
        
        Args:
            suffix: Unique suffix for resource naming
            
        Returns:
            Lambda Function construct
        """
        # Create IAM role for Lambda function
        lambda_role = iam.Role(
            self,
            "LogAnalysisLambdaRole",
            role_name=f"log-analytics-processor-{suffix}-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Role for CloudWatch Logs Insights analysis Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )

        # Add CloudWatch Logs Insights permissions
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:StartQuery",
                    "logs:GetQueryResults",
                    "logs:DescribeLogGroups",
                    "logs:DescribeLogStreams"
                ],
                resources=["*"]
            )
        )

        # Add SNS publishing permissions
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "sns:Publish"
                ],
                resources=[self.sns_topic.topic_arn]
            )
        )

        # Create Lambda function
        analysis_function = lambda_.Function(
            self,
            "LogAnalysisFunction",
            function_name=f"log-analytics-processor-{suffix}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="lambda_function.lambda_handler",
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.minutes(2),
            memory_size=256,
            role=lambda_role,
            description="Automated log analysis using CloudWatch Logs Insights",
            environment={
                "LOG_GROUP_NAME": self.log_group.log_group_name,
                "SNS_TOPIC_ARN": self.sns_topic.topic_arn,
                "ERROR_THRESHOLD": "1"
            },
            retry_attempts=2
        )

        return analysis_function

    def _create_schedule_rule(self, suffix: str) -> events.Rule:
        """
        Create CloudWatch Events rule for scheduled log analysis.
        
        Args:
            suffix: Unique suffix for resource naming
            
        Returns:
            CloudWatch Events Rule construct
        """
        rule = events.Rule(
            self,
            "LogAnalysisSchedule",
            rule_name=f"log-analytics-processor-{suffix}-schedule",
            description="Automated log analysis every 5 minutes",
            schedule=events.Schedule.rate(Duration.minutes(5)),
            enabled=True
        )

        # Add Lambda function as target
        rule.add_target(
            targets.LambdaFunction(
                self.analysis_lambda,
                retry_attempts=2
            )
        )

        return rule

    def _get_lambda_code(self) -> str:
        """
        Generate Lambda function code for log analysis.
        
        Returns:
            Lambda function code as string
        """
        return """
import json
import boto3
import time
import os
from datetime import datetime, timedelta
from typing import Dict, Any, List


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for automated log analysis using CloudWatch Logs Insights.
    
    This function:
    1. Executes CloudWatch Logs Insights queries to analyze log patterns
    2. Detects errors and anomalies in application logs
    3. Sends alerts via SNS when issues are detected
    4. Provides detailed analysis results for monitoring
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Response with analysis results and status
    """
    logs_client = boto3.client('logs')
    sns_client = boto3.client('sns')
    
    log_group_name = os.environ['LOG_GROUP_NAME']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    error_threshold = int(os.environ.get('ERROR_THRESHOLD', '1'))
    
    # Set time range for analysis (last hour)
    end_time = int(time.time())
    start_time = end_time - 3600  # 1 hour ago
    
    try:
        # Execute multiple analysis queries
        analysis_results = {}
        
        # Query 1: Error count analysis
        error_results = execute_logs_query(
            logs_client,
            log_group_name,
            start_time,
            end_time,
            '''
            fields @timestamp, @message
            | filter @message like /ERROR/
            | stats count() as error_count
            '''
        )
        
        if error_results and len(error_results) > 0:
            error_count = int(error_results[0][0]['value'])
            analysis_results['error_count'] = error_count
            
            if error_count > error_threshold:
                send_alert(
                    sns_client,
                    sns_topic_arn,
                    f"Alert: {error_count} errors detected in the last hour",
                    "High Error Rate Detected"
                )
        
        # Query 2: API response time analysis
        response_time_results = execute_logs_query(
            logs_client,
            log_group_name,
            start_time,
            end_time,
            '''
            fields @timestamp, @message
            | filter @message like /API Request/
            | parse @message "* - *ms" as status, response_time
            | stats avg(response_time) as avg_response_time, 
                    max(response_time) as max_response_time,
                    count() as request_count
            '''
        )
        
        if response_time_results and len(response_time_results) > 0:
            result = response_time_results[0]
            if len(result) >= 3:
                avg_time = float(result[0]['value']) if result[0]['value'] else 0
                max_time = float(result[1]['value']) if result[1]['value'] else 0
                request_count = int(result[2]['value']) if result[2]['value'] else 0
                
                analysis_results['avg_response_time'] = avg_time
                analysis_results['max_response_time'] = max_time
                analysis_results['request_count'] = request_count
                
                # Alert on slow response times
                if avg_time > 1000:  # More than 1 second average
                    send_alert(
                        sns_client,
                        sns_topic_arn,
                        f"Alert: High average response time ({avg_time:.1f}ms) detected",
                        "Performance Degradation"
                    )
        
        # Query 3: Warning count analysis
        warning_results = execute_logs_query(
            logs_client,
            log_group_name,
            start_time,
            end_time,
            '''
            fields @timestamp, @message
            | filter @message like /WARN/
            | stats count() as warning_count
            '''
        )
        
        if warning_results and len(warning_results) > 0:
            warning_count = int(warning_results[0][0]['value'])
            analysis_results['warning_count'] = warning_count
        
        print(f"Analysis completed successfully: {analysis_results}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Log analysis completed successfully',
                'analysis_results': analysis_results,
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        error_msg = f"Error during log analysis: {str(e)}"
        print(error_msg)
        
        # Send error alert
        try:
            send_alert(
                sns_client,
                sns_topic_arn,
                f"Log analysis function error: {str(e)}",
                "Log Analysis System Error"
            )
        except Exception as sns_error:
            print(f"Failed to send error alert: {str(sns_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_msg,
                'timestamp': datetime.now().isoformat()
            })
        }


def execute_logs_query(
    logs_client: Any,
    log_group_name: str,
    start_time: int,
    end_time: int,
    query: str,
    max_wait_time: int = 30
) -> List[List[Dict[str, str]]]:
    """
    Execute CloudWatch Logs Insights query and return results.
    
    Args:
        logs_client: CloudWatch Logs client
        log_group_name: Name of the log group to query
        start_time: Query start time (Unix timestamp)
        end_time: Query end time (Unix timestamp)
        query: CloudWatch Logs Insights query string
        max_wait_time: Maximum time to wait for query completion
        
    Returns:
        Query results as list of result rows
    """
    try:
        # Start the query
        response = logs_client.start_query(
            logGroupName=log_group_name,
            startTime=start_time,
            endTime=end_time,
            queryString=query
        )
        
        query_id = response['queryId']
        
        # Wait for query completion
        wait_time = 0
        while wait_time < max_wait_time:
            result = logs_client.get_query_results(queryId=query_id)
            
            if result['status'] == 'Complete':
                return result['results']
            elif result['status'] == 'Failed':
                raise Exception(f"Query failed: {result.get('statistics', {}).get('recordsMatched', 'Unknown error')}")
            
            time.sleep(1)
            wait_time += 1
        
        raise Exception(f"Query timed out after {max_wait_time} seconds")
        
    except Exception as e:
        print(f"Error executing query: {str(e)}")
        raise


def send_alert(
    sns_client: Any,
    topic_arn: str,
    message: str,
    subject: str
) -> None:
    """
    Send alert notification via SNS.
    
    Args:
        sns_client: SNS client
        topic_arn: SNS topic ARN
        message: Alert message content
        subject: Alert subject line
    """
    try:
        sns_client.publish(
            TopicArn=topic_arn,
            Message=message,
            Subject=subject
        )
        print(f"Alert sent successfully: {subject}")
    except Exception as e:
        print(f"Failed to send alert: {str(e)}")
        raise
"""

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self,
            "LogGroupName",
            value=self.log_group.log_group_name,
            description="CloudWatch Log Group name for application logs"
        )

        CfnOutput(
            self,
            "SNSTopicArn",
            value=self.sns_topic.topic_arn,
            description="SNS Topic ARN for log analytics alerts"
        )

        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.analysis_lambda.function_name,
            description="Lambda function name for log analysis"
        )

        CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.analysis_lambda.function_arn,
            description="Lambda function ARN for log analysis"
        )

        CfnOutput(
            self,
            "ScheduleRuleName",
            value=self.schedule_rule.rule_name,
            description="CloudWatch Events rule name for automated analysis"
        )

    def _apply_tags(self) -> None:
        """Apply consistent tags to all resources."""
        Tags.of(self).add("Project", "LogAnalytics")
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("Purpose", "CloudWatchLogsInsightsAnalytics")


def main() -> None:
    """
    Main application entry point.
    
    Creates and deploys the CDK application for CloudWatch Logs Insights
    analytics solution.
    """
    app = cdk.App()

    # Get notification email from context or environment
    notification_email = (
        app.node.try_get_context("notification_email") or 
        os.environ.get("NOTIFICATION_EMAIL", "admin@example.com")
    )

    # Get deployment environment
    env = cdk.Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    )

    # Create the stack
    LogAnalyticsStack(
        app,
        "LogAnalyticsStack",
        notification_email=notification_email,
        env=env,
        description="CloudWatch Logs Insights Analytics Solution - "
                   "Automated log analysis with real-time alerting"
    )

    # Synthesize the CDK app
    app.synth()


if __name__ == "__main__":
    main()