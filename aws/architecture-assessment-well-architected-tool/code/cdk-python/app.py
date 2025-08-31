#!/usr/bin/env python3
"""
AWS CDK Python Application for Well-Architected Tool Assessment

This CDK application demonstrates how to use AWS infrastructure to support
Well-Architected Tool assessments with CloudWatch monitoring integration.
While the Well-Architected Tool itself is a managed service that doesn't
require infrastructure deployment, this stack creates supporting resources
for monitoring and automation around the assessment process.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_lambda as _lambda,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    aws_events as events,
    aws_events_targets as targets,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions
)
from constructs import Construct
from typing import Dict, List, Optional
import os


class WellArchitectedAssessmentStack(Stack):
    """
    CDK Stack for Well-Architected Tool Assessment Support Infrastructure
    
    This stack creates supporting infrastructure for Well-Architected Tool
    assessments including:
    - Lambda functions for automated workload management
    - CloudWatch dashboards for monitoring assessment progress
    - SNS notifications for assessment milestones
    - IAM roles with appropriate permissions
    """
    
    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        # Create SNS topic for assessment notifications
        self.notification_topic = self._create_notification_topic()
        
        # Create Lambda execution role
        self.lambda_role = self._create_lambda_role()
        
        # Create Lambda functions
        self.workload_manager_function = self._create_workload_manager_function()
        self.assessment_monitor_function = self._create_assessment_monitor_function()
        
        # Create CloudWatch dashboard
        self.dashboard = self._create_cloudwatch_dashboard()
        
        # Create EventBridge rule for scheduled assessments
        self.assessment_schedule = self._create_assessment_schedule()
        
        # Output important resource information
        self._create_outputs()
    
    def _create_notification_topic(self) -> sns.Topic:
        """Create SNS topic for Well-Architected assessment notifications."""
        topic = sns.Topic(
            self, "WellArchitectedNotificationTopic",
            topic_name="well-architected-assessment-notifications",
            display_name="Well-Architected Assessment Notifications",
            description="Notifications for Well-Architected Tool assessment events"
        )
        
        # Add email subscription if EMAIL_NOTIFICATION environment variable is set
        email = os.environ.get('EMAIL_NOTIFICATION')
        if email:
            topic.add_subscription(
                subscriptions.EmailSubscription(email)
            )
        
        return topic
    
    def _create_lambda_role(self) -> iam.Role:
        """Create IAM role for Lambda functions with Well-Architected permissions."""
        role = iam.Role(
            self, "WellArchitectedLambdaRole",
            role_name="well-architected-lambda-execution-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for Well-Architected Tool Lambda functions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )
        
        # Add Well-Architected Tool permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "wellarchitected:CreateWorkload",
                    "wellarchitected:GetWorkload",
                    "wellarchitected:UpdateWorkload",
                    "wellarchitected:DeleteWorkload",
                    "wellarchitected:ListWorkloads",
                    "wellarchitected:GetLensReview",
                    "wellarchitected:UpdateLensReview",
                    "wellarchitected:ListAnswers",
                    "wellarchitected:GetAnswer",
                    "wellarchitected:UpdateAnswer",
                    "wellarchitected:ListLensReviewImprovements",
                    "wellarchitected:CreateMilestone",
                    "wellarchitected:ListMilestones"
                ],
                resources=["*"]
            )
        )
        
        # Add CloudWatch permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudwatch:PutMetricData",
                    "cloudwatch:GetMetricStatistics",
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ],
                resources=["*"]
            )
        )
        
        # Add SNS permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "sns:Publish"
                ],
                resources=[self.notification_topic.topic_arn]
            )
        )
        
        return role
    
    def _create_workload_manager_function(self) -> _lambda.Function:
        """Create Lambda function for managing Well-Architected workloads."""
        function = _lambda.Function(
            self, "WorkloadManagerFunction",
            function_name="well-architected-workload-manager",
            runtime=_lambda.Runtime.PYTHON_3_11,
            handler="workload_manager.lambda_handler",
            code=_lambda.Code.from_inline(self._get_workload_manager_code()),
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=256,
            description="Manages Well-Architected Tool workloads",
            environment={
                "SNS_TOPIC_ARN": self.notification_topic.topic_arn,
                "LOG_LEVEL": "INFO"
            },
            log_retention=logs.RetentionDays.ONE_MONTH
        )
        
        return function
    
    def _create_assessment_monitor_function(self) -> _lambda.Function:
        """Create Lambda function for monitoring assessment progress."""
        function = _lambda.Function(
            self, "AssessmentMonitorFunction",
            function_name="well-architected-assessment-monitor",
            runtime=_lambda.Runtime.PYTHON_3_11,
            handler="assessment_monitor.lambda_handler",
            code=_lambda.Code.from_inline(self._get_assessment_monitor_code()),
            role=self.lambda_role,
            timeout=Duration.minutes(10),
            memory_size=512,
            description="Monitors Well-Architected assessment progress and generates metrics",
            environment={
                "SNS_TOPIC_ARN": self.notification_topic.topic_arn,
                "LOG_LEVEL": "INFO"
            },
            log_retention=logs.RetentionDays.ONE_MONTH
        )
        
        return function
    
    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for Well-Architected assessments."""
        dashboard = cloudwatch.Dashboard(
            self, "WellArchitectedDashboard",
            dashboard_name="WellArchitectedAssessments",
            period_override=cloudwatch.PeriodOverride.AUTO
        )
        
        # Add Lambda function metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Lambda Function Invocations",
                left=[
                    self.workload_manager_function.metric_invocations(
                        label="Workload Manager Invocations"
                    ),
                    self.assessment_monitor_function.metric_invocations(
                        label="Assessment Monitor Invocations"
                    )
                ],
                width=12,
                height=6
            )
        )
        
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Lambda Function Errors",
                left=[
                    self.workload_manager_function.metric_errors(
                        label="Workload Manager Errors"
                    ),
                    self.assessment_monitor_function.metric_errors(
                        label="Assessment Monitor Errors"
                    )
                ],
                width=12,
                height=6
            )
        )
        
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Lambda Function Duration",
                left=[
                    self.workload_manager_function.metric_duration(
                        label="Workload Manager Duration"
                    ),
                    self.assessment_monitor_function.metric_duration(
                        label="Assessment Monitor Duration"
                    )
                ],
                width=12,
                height=6
            )
        )
        
        return dashboard
    
    def _create_assessment_schedule(self) -> events.Rule:
        """Create EventBridge rule for scheduled assessment monitoring."""
        rule = events.Rule(
            self, "AssessmentScheduleRule",
            rule_name="well-architected-assessment-schedule",
            description="Scheduled monitoring of Well-Architected assessments",
            schedule=events.Schedule.rate(Duration.hours(24)),  # Daily monitoring
            enabled=True
        )
        
        # Add Lambda target
        rule.add_target(
            targets.LambdaFunction(
                self.assessment_monitor_function,
                retry_attempts=2
            )
        )
        
        return rule
    
    def _get_workload_manager_code(self) -> str:
        """Return the Python code for the workload manager Lambda function."""
        return '''
import json
import boto3
import os
import logging
from typing import Dict, Any
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
wellarchitected_client = boto3.client('wellarchitected')
sns_client = boto3.client('sns')

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Lambda handler for managing Well-Architected workloads.
    
    Supports the following operations:
    - create: Create a new workload
    - delete: Delete an existing workload
    - list: List all workloads
    - get: Get workload details
    """
    try:
        operation = event.get('operation', 'list')
        logger.info(f"Processing operation: {operation}")
        
        if operation == 'create':
            result = create_workload(event)
        elif operation == 'delete':
            result = delete_workload(event)
        elif operation == 'list':
            result = list_workloads(event)
        elif operation == 'get':
            result = get_workload(event)
        else:
            raise ValueError(f"Unsupported operation: {operation}")
        
        # Send success notification
        send_notification(f"Well-Architected operation '{operation}' completed successfully")
        
        return {
            'statusCode': 200,
            'body': json.dumps(result),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
        
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        
        # Send error notification
        send_notification(f"Well-Architected operation failed: {str(e)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            }),
            'headers': {
                'Content-Type': 'application/json'
            }
        }

def create_workload(event: Dict[str, Any]) -> Dict[str, Any]:
    """Create a new Well-Architected workload."""
    workload_name = event.get('workload_name', f'sample-workload-{int(datetime.now().timestamp())}')
    description = event.get('description', 'Sample workload created via CDK automation')
    environment = event.get('environment', 'PREPRODUCTION')
    
    response = wellarchitected_client.create_workload(
        WorkloadName=workload_name,
        Description=description,
        Environment=environment,
        Lenses=['wellarchitected'],
        IndustryType='InfoTech',
        ArchitecturalDesign='Three-tier web application architecture'
    )
    
    logger.info(f"Created workload: {response['WorkloadId']}")
    return {
        'workload_id': response['WorkloadId'],
        'workload_arn': response['WorkloadArn'],
        'operation': 'create'
    }

def delete_workload(event: Dict[str, Any]) -> Dict[str, Any]:
    """Delete a Well-Architected workload."""
    workload_id = event.get('workload_id')
    if not workload_id:
        raise ValueError("workload_id is required for delete operation")
    
    wellarchitected_client.delete_workload(WorkloadId=workload_id)
    
    logger.info(f"Deleted workload: {workload_id}")
    return {
        'workload_id': workload_id,
        'operation': 'delete',
        'status': 'deleted'
    }

def list_workloads(event: Dict[str, Any]) -> Dict[str, Any]:
    """List all Well-Architected workloads."""
    response = wellarchitected_client.list_workloads()
    
    workloads = []
    for workload in response.get('WorkloadSummaries', []):
        workloads.append({
            'workload_id': workload['WorkloadId'],
            'workload_name': workload['WorkloadName'],
            'owner': workload.get('Owner', ''),
            'updated_at': workload.get('UpdatedAt', '').isoformat() if workload.get('UpdatedAt') else '',
            'risk_counts': workload.get('RiskCounts', {})
        })
    
    logger.info(f"Found {len(workloads)} workloads")
    return {
        'workloads': workloads,
        'count': len(workloads),
        'operation': 'list'
    }

def get_workload(event: Dict[str, Any]) -> Dict[str, Any]:
    """Get details for a specific workload."""
    workload_id = event.get('workload_id')
    if not workload_id:
        raise ValueError("workload_id is required for get operation")
    
    response = wellarchitected_client.get_workload(WorkloadId=workload_id)
    workload = response['Workload']
    
    return {
        'workload_id': workload['WorkloadId'],
        'workload_name': workload['WorkloadName'],
        'description': workload.get('Description', ''),
        'environment': workload.get('Environment', ''),
        'review_owner': workload.get('ReviewOwner', ''),
        'lenses': workload.get('Lenses', []),
        'risk_counts': workload.get('RiskCounts', {}),
        'improvement_status': workload.get('ImprovementStatus', ''),
        'operation': 'get'
    }

def send_notification(message: str) -> None:
    """Send notification via SNS."""
    try:
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
        if sns_topic_arn:
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Message=message,
                Subject='Well-Architected Tool Notification'
            )
            logger.info("Notification sent successfully")
    except Exception as e:
        logger.warning(f"Failed to send notification: {str(e)}")
'''
    
    def _get_assessment_monitor_code(self) -> str:
        """Return the Python code for the assessment monitor Lambda function."""
        return '''
import json
import boto3
import os
import logging
from typing import Dict, Any, List
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
wellarchitected_client = boto3.client('wellarchitected')
cloudwatch_client = boto3.client('cloudwatch')
sns_client = boto3.client('sns')

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Lambda handler for monitoring Well-Architected assessments.
    
    This function:
    1. Lists all workloads
    2. Checks assessment progress for each workload
    3. Publishes metrics to CloudWatch
    4. Sends notifications for important events
    """
    try:
        logger.info("Starting Well-Architected assessment monitoring")
        
        # Get all workloads
        workloads = get_all_workloads()
        logger.info(f"Found {len(workloads)} workloads to monitor")
        
        # Monitor each workload
        monitoring_results = []
        for workload in workloads:
            result = monitor_workload(workload)
            monitoring_results.append(result)
        
        # Publish aggregate metrics
        publish_aggregate_metrics(monitoring_results)
        
        # Send summary notification
        send_summary_notification(monitoring_results)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'monitored_workloads': len(workloads),
                'results': monitoring_results,
                'timestamp': datetime.utcnow().isoformat()
            }),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
        
    except Exception as e:
        logger.error(f"Error monitoring assessments: {str(e)}")
        
        # Send error notification
        send_notification(f"Assessment monitoring failed: {str(e)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            }),
            'headers': {
                'Content-Type': 'application/json'
            }
        }

def get_all_workloads() -> List[Dict[str, Any]]:
    """Get all Well-Architected workloads."""
    response = wellarchitected_client.list_workloads()
    return response.get('WorkloadSummaries', [])

def monitor_workload(workload: Dict[str, Any]) -> Dict[str, Any]:
    """Monitor a specific workload's assessment progress."""
    workload_id = workload['WorkloadId']
    workload_name = workload['WorkloadName']
    
    try:
        # Get workload details
        workload_details = wellarchitected_client.get_workload(
            WorkloadId=workload_id
        )['Workload']
        
        # Get lens review
        lens_review = wellarchitected_client.get_lens_review(
            WorkloadId=workload_id,
            LensAlias='wellarchitected'
        )['LensReview']
        
        # Calculate assessment progress
        pillar_summaries = lens_review.get('PillarReviewSummaries', [])
        total_risks = {'HIGH': 0, 'MEDIUM': 0, 'LOW': 0, 'NONE': 0}
        
        for pillar in pillar_summaries:
            risk_counts = pillar.get('RiskCounts', {})
            for risk_level, count in risk_counts.items():
                if risk_level in total_risks:
                    total_risks[risk_level] += count
        
        # Publish metrics for this workload
        publish_workload_metrics(workload_id, workload_name, total_risks)
        
        result = {
            'workload_id': workload_id,
            'workload_name': workload_name,
            'status': 'success',
            'risk_counts': total_risks,
            'pillar_count': len(pillar_summaries),
            'lens_status': lens_review.get('LensStatus', 'UNKNOWN')
        }
        
        logger.info(f"Monitored workload {workload_name}: {total_risks}")
        return result
        
    except Exception as e:
        logger.error(f"Error monitoring workload {workload_name}: {str(e)}")
        return {
            'workload_id': workload_id,
            'workload_name': workload_name,
            'status': 'error',
            'error': str(e)
        }

def publish_workload_metrics(workload_id: str, workload_name: str, risk_counts: Dict[str, int]) -> None:
    """Publish CloudWatch metrics for a workload."""
    try:
        metric_data = []
        
        for risk_level, count in risk_counts.items():
            metric_data.append({
                'MetricName': f'RiskCount_{risk_level}',
                'Value': count,
                'Unit': 'Count',
                'Dimensions': [
                    {
                        'Name': 'WorkloadId',
                        'Value': workload_id
                    },
                    {
                        'Name': 'WorkloadName',
                        'Value': workload_name
                    }
                ]
            })
        
        # Add total risk count
        total_risks = sum(risk_counts.values())
        metric_data.append({
            'MetricName': 'TotalRisks',
            'Value': total_risks,
            'Unit': 'Count',
            'Dimensions': [
                {
                    'Name': 'WorkloadId',
                    'Value': workload_id
                },
                {
                    'Name': 'WorkloadName',
                    'Value': workload_name
                }
            ]
        })
        
        cloudwatch_client.put_metric_data(
            Namespace='AWS/WellArchitected',
            MetricData=metric_data
        )
        
        logger.info(f"Published metrics for workload {workload_name}")
        
    except Exception as e:
        logger.error(f"Error publishing metrics for workload {workload_name}: {str(e)}")

def publish_aggregate_metrics(results: List[Dict[str, Any]]) -> None:
    """Publish aggregate metrics across all workloads."""
    try:
        successful_results = [r for r in results if r['status'] == 'success']
        
        # Calculate aggregate statistics
        total_workloads = len(results)
        successful_workloads = len(successful_results)
        failed_workloads = total_workloads - successful_workloads
        
        aggregate_risks = {'HIGH': 0, 'MEDIUM': 0, 'LOW': 0, 'NONE': 0}
        for result in successful_results:
            risk_counts = result.get('risk_counts', {})
            for risk_level, count in risk_counts.items():
                if risk_level in aggregate_risks:
                    aggregate_risks[risk_level] += count
        
        # Publish aggregate metrics
        metric_data = [
            {
                'MetricName': 'TotalWorkloads',
                'Value': total_workloads,
                'Unit': 'Count'
            },
            {
                'MetricName': 'SuccessfulMonitoring',
                'Value': successful_workloads,
                'Unit': 'Count'
            },
            {
                'MetricName': 'FailedMonitoring',
                'Value': failed_workloads,
                'Unit': 'Count'
            }
        ]
        
        for risk_level, count in aggregate_risks.items():
            metric_data.append({
                'MetricName': f'AggregateRisk_{risk_level}',
                'Value': count,
                'Unit': 'Count'
            })
        
        cloudwatch_client.put_metric_data(
            Namespace='AWS/WellArchitected/Aggregate',
            MetricData=metric_data
        )
        
        logger.info("Published aggregate metrics")
        
    except Exception as e:
        logger.error(f"Error publishing aggregate metrics: {str(e)}")

def send_summary_notification(results: List[Dict[str, Any]]) -> None:
    """Send summary notification about monitoring results."""
    try:
        successful_results = [r for r in results if r['status'] == 'success']
        failed_results = [r for r in results if r['status'] == 'error']
        
        message = f"Well-Architected Assessment Monitoring Summary\\n\\n"
        message += f"Total workloads monitored: {len(results)}\\n"
        message += f"Successful: {len(successful_results)}\\n"
        message += f"Failed: {len(failed_results)}\\n\\n"
        
        if successful_results:
            # Calculate aggregate risk summary
            aggregate_risks = {'HIGH': 0, 'MEDIUM': 0, 'LOW': 0, 'NONE': 0}
            for result in successful_results:
                risk_counts = result.get('risk_counts', {})
                for risk_level, count in risk_counts.items():
                    if risk_level in aggregate_risks:
                        aggregate_risks[risk_level] += count
            
            message += "Aggregate Risk Summary:\\n"
            for risk_level, count in aggregate_risks.items():
                message += f"  {risk_level}: {count}\\n"
        
        if failed_results:
            message += "\\nFailed workloads:\\n"
            for result in failed_results[:5]:  # Limit to first 5 failures
                message += f"  - {result['workload_name']}: {result.get('error', 'Unknown error')}\\n"
        
        send_notification(message)
        
    except Exception as e:
        logger.error(f"Error sending summary notification: {str(e)}")

def send_notification(message: str) -> None:
    """Send notification via SNS."""
    try:
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
        if sns_topic_arn:
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Message=message,
                Subject='Well-Architected Assessment Monitoring Report'
            )
            logger.info("Notification sent successfully")
    except Exception as e:
        logger.warning(f"Failed to send notification: {str(e)}")
'''
    
    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        cdk.CfnOutput(
            self, "NotificationTopicArn",
            description="ARN of the SNS topic for Well-Architected notifications",
            value=self.notification_topic.topic_arn
        )
        
        cdk.CfnOutput(
            self, "WorkloadManagerFunctionName",
            description="Name of the Lambda function for managing workloads",
            value=self.workload_manager_function.function_name
        )
        
        cdk.CfnOutput(
            self, "AssessmentMonitorFunctionName",
            description="Name of the Lambda function for monitoring assessments",
            value=self.assessment_monitor_function.function_name
        )
        
        cdk.CfnOutput(
            self, "DashboardUrl",
            description="URL of the CloudWatch dashboard",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}"
        )
        
        cdk.CfnOutput(
            self, "LambdaRoleArn",
            description="ARN of the IAM role used by Lambda functions",
            value=self.lambda_role.role_arn
        )


class WellArchitectedApp(cdk.App):
    """CDK Application for Well-Architected Tool Assessment Infrastructure."""
    
    def __init__(self) -> None:
        super().__init__()
        
        # Create the main stack
        WellArchitectedAssessmentStack(
            self, "WellArchitectedAssessmentStack",
            description="Infrastructure to support AWS Well-Architected Tool assessments",
            env=cdk.Environment(
                account=os.environ.get('CDK_DEFAULT_ACCOUNT'),
                region=os.environ.get('CDK_DEFAULT_REGION', 'us-east-1')
            ),
            tags={
                'Project': 'WellArchitectedAssessment',
                'Environment': 'Production',
                'ManagedBy': 'CDK',
                'Purpose': 'AssessmentSupport'
            }
        )


# Create and run the CDK application
if __name__ == '__main__':
    app = WellArchitectedApp()
    app.synth()