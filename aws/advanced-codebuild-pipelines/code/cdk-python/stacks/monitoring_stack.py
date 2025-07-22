"""
Monitoring Stack for Advanced CodeBuild Pipeline

This stack creates comprehensive monitoring and analytics infrastructure:
- CloudWatch dashboards for build metrics
- Custom metrics and alarms
- Analytics Lambda function
- SNS notifications
- Log insights queries
"""

from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    Stack,
    aws_cloudwatch as cloudwatch,
    aws_events as events,
    aws_events_targets as targets,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_logs as logs,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
)
from constructs import Construct

from .pipeline_stack import AdvancedCodeBuildPipelineStack
from .storage_stack import StorageStack


class MonitoringStack(Stack):
    """
    Stack containing monitoring and analytics infrastructure
    
    This stack creates:
    - CloudWatch dashboard for build metrics visualization
    - Custom alarms for build failures and performance issues
    - Analytics Lambda function for advanced reporting
    - SNS topics for notifications
    - Log insights queries for troubleshooting
    """
    
    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        pipeline_stack: AdvancedCodeBuildPipelineStack,
        storage_stack: StorageStack,
        project_name: str,
        environment: str,
        enable_analytics: bool = True,
        notification_email: Optional[str] = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        self.pipeline_stack = pipeline_stack
        self.storage_stack = storage_stack
        self.project_name = project_name
        self.environment = environment
        self.enable_analytics = enable_analytics
        
        # Create SNS topic for notifications
        self.notification_topic = self._create_notification_topic(notification_email)
        
        # Create CloudWatch dashboard
        self.dashboard = self._create_dashboard()
        
        # Create CloudWatch alarms
        self._create_alarms()
        
        # Create analytics function if enabled
        if self.enable_analytics:
            self.analytics_function = self._create_analytics_function()
            self._create_analytics_schedule()
        
        # Create log insights queries
        self._create_log_insights_queries()
        
        # Create outputs
        self._create_outputs()
    
    def _create_notification_topic(self, notification_email: Optional[str]) -> sns.Topic:
        """
        Create SNS topic for build notifications
        
        Args:
            notification_email: Email address for notifications
            
        Returns:
            SNS Topic for notifications
        """
        topic = sns.Topic(
            self,
            "BuildNotificationTopic",
            topic_name=f"{self.project_name}-build-notifications-{self.environment}",
            display_name="Advanced CodeBuild Pipeline Notifications",
            description="Notifications for build pipeline events and alerts"
        )
        
        # Add email subscription if provided
        if notification_email:
            topic.add_subscription(
                subscriptions.EmailSubscription(notification_email)
            )
        
        return topic
    
    def _create_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for build monitoring
        
        Returns:
            CloudWatch Dashboard
        """
        dashboard = cloudwatch.Dashboard(
            self,
            "BuildMonitoringDashboard",
            dashboard_name=f"Advanced-CodeBuild-{self.project_name}-{self.environment}",
            description="Comprehensive monitoring for advanced CodeBuild pipeline"
        )
        
        # Pipeline execution metrics
        pipeline_widget = cloudwatch.GraphWidget(
            title="Pipeline Execution Results",
            left=[
                cloudwatch.Metric(
                    namespace="CodeBuild/AdvancedPipeline",
                    metric_name="PipelineExecutions",
                    dimensions_map={"Status": "SUCCEEDED"},
                    statistic="Sum",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="CodeBuild/AdvancedPipeline",
                    metric_name="PipelineExecutions",
                    dimensions_map={"Status": "FAILED"},
                    statistic="Sum",
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6
        )
        
        # Build duration metrics
        duration_widget = cloudwatch.GraphWidget(
            title="Average Build Duration by Stage",
            left=[
                cloudwatch.Metric(
                    namespace="CodeBuild/AdvancedPipeline",
                    metric_name="BuildDuration",
                    dimensions_map={"Stage": "dependencies"},
                    statistic="Average",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="CodeBuild/AdvancedPipeline",
                    metric_name="BuildDuration",
                    dimensions_map={"Stage": "main"},
                    statistic="Average",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="CodeBuild/AdvancedPipeline",
                    metric_name="BuildDuration",
                    dimensions_map={"Stage": "parallel"},
                    statistic="Average",
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6
        )
        
        # CodeBuild project metrics
        codebuild_widget = cloudwatch.GraphWidget(
            title="CodeBuild Project Durations",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/CodeBuild",
                    metric_name="Duration",
                    dimensions_map={"ProjectName": self.pipeline_stack.dependency_project.project_name},
                    statistic="Average",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="AWS/CodeBuild",
                    metric_name="Duration",
                    dimensions_map={"ProjectName": self.pipeline_stack.main_project.project_name},
                    statistic="Average",
                    period=Duration.minutes(5)
                )
            ],
            width=8,
            height=6
        )
        
        # Build count metrics
        build_count_widget = cloudwatch.GraphWidget(
            title="Build Count by Project",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/CodeBuild",
                    metric_name="Builds",
                    dimensions_map={"ProjectName": self.pipeline_stack.dependency_project.project_name},
                    statistic="Sum",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="AWS/CodeBuild",
                    metric_name="Builds",
                    dimensions_map={"ProjectName": self.pipeline_stack.main_project.project_name},
                    statistic="Sum",
                    period=Duration.minutes(5)
                )
            ],
            width=8,
            height=6
        )
        
        # Storage usage metrics
        storage_widget = cloudwatch.GraphWidget(
            title="Storage Usage (Cache and Artifacts)",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/S3",
                    metric_name="BucketSizeBytes",
                    dimensions_map={
                        "BucketName": self.storage_stack.cache_bucket.bucket_name,
                        "StorageType": "StandardStorage"
                    },
                    statistic="Average",
                    period=Duration.hours(24)
                ),
                cloudwatch.Metric(
                    namespace="AWS/S3",
                    metric_name="BucketSizeBytes",
                    dimensions_map={
                        "BucketName": self.storage_stack.artifact_bucket.bucket_name,
                        "StorageType": "StandardStorage"
                    },
                    statistic="Average",
                    period=Duration.hours(24)
                )
            ],
            width=12,
            height=6
        )
        
        # Lambda performance metrics
        lambda_widget = cloudwatch.GraphWidget(
            title="Build Orchestrator Performance",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/Lambda",
                    metric_name="Duration",
                    dimensions_map={"FunctionName": self.pipeline_stack.orchestrator_function.function_name},
                    statistic="Average",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="AWS/Lambda",
                    metric_name="Invocations",
                    dimensions_map={"FunctionName": self.pipeline_stack.orchestrator_function.function_name},
                    statistic="Sum",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="AWS/Lambda",
                    metric_name="Errors",
                    dimensions_map={"FunctionName": self.pipeline_stack.orchestrator_function.function_name},
                    statistic="Sum",
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6
        )
        
        # Recent build errors log widget
        log_widget = cloudwatch.LogQueryWidget(
            title="Recent Build Errors",
            log_groups=[
                logs.LogGroup.from_log_group_name(
                    self,
                    "MainBuildLogGroupRef",
                    log_group_name=f"/aws/codebuild/{self.pipeline_stack.main_project.project_name}"
                )
            ],
            query_lines=[
                "fields @timestamp, @message",
                "filter @message like /ERROR/ or @message like /FAILED/",
                "sort @timestamp desc",
                "limit 20"
            ],
            width=8,
            height=6
        )
        
        # Add widgets to dashboard
        dashboard.add_widgets(
            pipeline_widget,
            duration_widget
        )
        dashboard.add_widgets(
            codebuild_widget,
            build_count_widget,
            log_widget
        )
        dashboard.add_widgets(
            storage_widget
        )
        dashboard.add_widgets(
            lambda_widget
        )
        
        return dashboard
    
    def _create_alarms(self) -> None:
        """Create CloudWatch alarms for monitoring"""
        
        # Build failure alarm
        build_failure_alarm = cloudwatch.Alarm(
            self,
            "BuildFailureAlarm",
            alarm_name=f"{self.project_name}-build-failures-{self.environment}",
            alarm_description="Alert when builds fail frequently",
            metric=cloudwatch.Metric(
                namespace="AWS/CodeBuild",
                metric_name="FailedBuilds",
                dimensions_map={"ProjectName": self.pipeline_stack.main_project.project_name},
                statistic="Sum",
                period=Duration.minutes(15)
            ),
            threshold=3,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # Add SNS action
        build_failure_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.notification_topic)
        )
        
        # Build duration alarm
        build_duration_alarm = cloudwatch.Alarm(
            self,
            "BuildDurationAlarm",
            alarm_name=f"{self.project_name}-build-duration-{self.environment}",
            alarm_description="Alert when builds take too long",
            metric=cloudwatch.Metric(
                namespace="AWS/CodeBuild",
                metric_name="Duration",
                dimensions_map={"ProjectName": self.pipeline_stack.main_project.project_name},
                statistic="Average",
                period=Duration.minutes(30)
            ),
            threshold=3600,  # 1 hour in seconds
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        build_duration_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.notification_topic)
        )
        
        # Orchestrator function error alarm
        orchestrator_error_alarm = cloudwatch.Alarm(
            self,
            "OrchestratorErrorAlarm",
            alarm_name=f"{self.project_name}-orchestrator-errors-{self.environment}",
            alarm_description="Alert when orchestrator function has errors",
            metric=cloudwatch.Metric(
                namespace="AWS/Lambda",
                metric_name="Errors",
                dimensions_map={"FunctionName": self.pipeline_stack.orchestrator_function.function_name},
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        orchestrator_error_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.notification_topic)
        )
    
    def _create_analytics_function(self) -> lambda_.Function:
        """
        Create Lambda function for build analytics
        
        Returns:
            Lambda Function for analytics
        """
        # Create IAM role for analytics
        analytics_role = iam.Role(
            self,
            "AnalyticsRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ]
        )
        
        # Add CodeBuild permissions
        analytics_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "codebuild:ListBuildsForProject",
                    "codebuild:BatchGetBuilds",
                ],
                resources=["*"]
            )
        )
        
        # Add S3 permissions
        analytics_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:PutObject",
                    "s3:GetObject",
                ],
                resources=[
                    f"{self.storage_stack.artifact_bucket.bucket_arn}/analytics/*"
                ]
            )
        )
        
        # Add CloudWatch permissions
        analytics_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudwatch:GetMetricStatistics",
                    "cloudwatch:ListMetrics",
                ],
                resources=["*"]
            )
        )
        
        function = lambda_.Function(
            self,
            "AnalyticsFunction",
            function_name=f"{self.project_name}-analytics-{self.environment}",
            description="Generate build analytics and performance reports",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline("""
import json
import boto3
import logging
from datetime import datetime, timedelta
import statistics

logger = logging.getLogger()
logger.setLevel(logging.INFO)

codebuild = boto3.client('codebuild')
cloudwatch = boto3.client('cloudwatch')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    try:
        analysis_period = event.get('analysisPeriod', 7)
        project_names = event.get('projectNames', [])
        
        if not project_names:
            project_names = [
                os.environ['DEPENDENCY_PROJECT'],
                os.environ['MAIN_PROJECT']
            ]
        
        analytics_report = generate_analytics_report(project_names, analysis_period)
        store_analytics_report(analytics_report)
        
        return {
            'statusCode': 200,
            'body': json.dumps(analytics_report, default=str)
        }
        
    except Exception as e:
        logger.error(f"Error generating analytics: {str(e)}")
        return {'statusCode': 500, 'body': f'Error: {str(e)}'}

def generate_analytics_report(project_names, analysis_period):
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(days=analysis_period)
    
    report = {
        'report_id': f"analytics-{int(end_time.timestamp())}",
        'generated_at': end_time.isoformat(),
        'analysis_period': f"{analysis_period} days",
        'start_time': start_time.isoformat(),
        'end_time': end_time.isoformat(),
        'projects': {},
        'summary': {}
    }
    
    all_builds = []
    total_builds = 0
    successful_builds = 0
    
    for project_name in project_names:
        try:
            project_analytics = analyze_project(project_name, start_time, end_time)
            report['projects'][project_name] = project_analytics
            
            all_builds.extend(project_analytics.get('builds', []))
            total_builds += project_analytics.get('total_builds', 0)
            successful_builds += project_analytics.get('successful_builds', 0)
            
        except Exception as e:
            logger.error(f"Error analyzing project {project_name}: {str(e)}")
            report['projects'][project_name] = {'error': str(e)}
    
    report['summary'] = generate_summary_statistics(all_builds, total_builds, successful_builds)
    
    return report

def analyze_project(project_name, start_time, end_time):
    project_data = {
        'project_name': project_name,
        'builds': [],
        'total_builds': 0,
        'successful_builds': 0,
        'failed_builds': 0,
        'average_duration': 0
    }
    
    try:
        builds_response = codebuild.list_builds_for_project(
            projectName=project_name,
            sortOrder='DESCENDING'
        )
        
        build_ids = builds_response.get('ids', [])
        
        if not build_ids:
            return project_data
        
        builds_detail = codebuild.batch_get_builds(ids=build_ids)
        builds = builds_detail.get('builds', [])
        
        filtered_builds = []
        for build in builds:
            build_start = build.get('startTime')
            if build_start and start_time <= build_start <= end_time:
                filtered_builds.append(build)
        
        durations = []
        
        for build in filtered_builds:
            build_status = build.get('buildStatus')
            build_duration = 0
            
            if build.get('startTime') and build.get('endTime'):
                duration = (build['endTime'] - build['startTime']).total_seconds()
                build_duration = duration
                durations.append(duration)
            
            if build_status == 'SUCCEEDED':
                project_data['successful_builds'] += 1
            else:
                project_data['failed_builds'] += 1
            
            project_data['builds'].append({
                'build_id': build.get('id'),
                'status': build_status,
                'duration': build_duration,
                'start_time': build.get('startTime').isoformat() if build.get('startTime') else None,
                'end_time': build.get('endTime').isoformat() if build.get('endTime') else None
            })
        
        project_data['total_builds'] = len(filtered_builds)
        project_data['average_duration'] = statistics.mean(durations) if durations else 0
        
        return project_data
        
    except Exception as e:
        logger.error(f"Error analyzing project {project_name}: {str(e)}")
        project_data['error'] = str(e)
        return project_data

def generate_summary_statistics(all_builds, total_builds, successful_builds):
    try:
        success_rate = (successful_builds / total_builds) if total_builds > 0 else 0
        
        durations = [b['duration'] for b in all_builds if b['duration'] > 0]
        
        duration_stats = {}
        if durations:
            duration_stats = {
                'mean': statistics.mean(durations),
                'median': statistics.median(durations),
                'min': min(durations),
                'max': max(durations)
            }
        
        return {
            'total_builds': total_builds,
            'successful_builds': successful_builds,
            'failed_builds': total_builds - successful_builds,
            'success_rate': success_rate,
            'duration_statistics': duration_stats
        }
        
    except Exception as e:
        logger.error(f"Error generating summary: {str(e)}")
        return {'error': str(e)}

def store_analytics_report(report):
    try:
        bucket = os.environ['ARTIFACT_BUCKET']
        key = f"analytics/build-analytics-{report['report_id']}.json"
        
        s3.put_object(
            Bucket=bucket,
            Key=key,
            Body=json.dumps(report, indent=2, default=str),
            ContentType='application/json'
        )
        
        logger.info(f"Analytics report stored: s3://{bucket}/{key}")
        
    except Exception as e:
        logger.error(f"Error storing analytics report: {str(e)}")

import os
            """),
            timeout=Duration.minutes(15),
            memory_size=512,
            environment={
                "DEPENDENCY_PROJECT": self.pipeline_stack.dependency_project.project_name,
                "MAIN_PROJECT": self.pipeline_stack.main_project.project_name,
                "ARTIFACT_BUCKET": self.storage_stack.artifact_bucket.bucket_name,
            },
            role=analytics_role,
            log_retention=logs.RetentionDays.ONE_MONTH
        )
        
        return function
    
    def _create_analytics_schedule(self) -> None:
        """Create EventBridge schedule for analytics"""
        
        # Weekly analytics rule
        analytics_rule = events.Rule(
            self,
            "AnalyticsRule",
            rule_name=f"{self.project_name}-analytics-{self.environment}",
            description="Weekly build analytics report",
            schedule=events.Schedule.rate(Duration.days(7))
        )
        
        # Add analytics function as target
        analytics_rule.add_target(
            targets.LambdaFunction(self.analytics_function)
        )
        
        # Grant EventBridge permission to invoke Lambda
        self.analytics_function.add_permission(
            "AllowAnalyticsEventBridgeInvoke",
            principal=iam.ServicePrincipal("events.amazonaws.com"),
            source_arn=analytics_rule.rule_arn
        )
    
    def _create_log_insights_queries(self) -> None:
        """Create CloudWatch Log Insights queries for troubleshooting"""
        
        # Build failure analysis query
        logs.QueryDefinition(
            self,
            "BuildFailureQuery",
            query_definition_name=f"{self.project_name}-build-failures-{self.environment}",
            query_string="""
                fields @timestamp, @message
                | filter @message like /ERROR/ or @message like /FAILED/
                | stats count() by bin(5m)
                | sort @timestamp desc
            """,
            log_groups=[
                logs.LogGroup.from_log_group_name(
                    self,
                    "MainBuildLogGroupForQuery",
                    log_group_name=f"/aws/codebuild/{self.pipeline_stack.main_project.project_name}"
                )
            ]
        )
        
        # Build performance analysis query
        logs.QueryDefinition(
            self,
            "BuildPerformanceQuery",
            query_definition_name=f"{self.project_name}-build-performance-{self.environment}",
            query_string="""
                fields @timestamp, @duration
                | filter @type = "REPORT"
                | stats avg(@duration), max(@duration), min(@duration) by bin(5m)
                | sort @timestamp desc
            """,
            log_groups=[
                logs.LogGroup.from_log_group_name(
                    self,
                    "MainBuildLogGroupForPerfQuery",
                    log_group_name=f"/aws/codebuild/{self.pipeline_stack.main_project.project_name}"
                )
            ]
        )
    
    def _create_outputs(self) -> None:
        """Create CloudFormation outputs"""
        
        cdk.CfnOutput(
            self,
            "DashboardURL",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="URL to the CloudWatch dashboard"
        )
        
        cdk.CfnOutput(
            self,
            "NotificationTopicArn",
            value=self.notification_topic.topic_arn,
            description="ARN of the SNS topic for notifications"
        )
        
        if self.enable_analytics:
            cdk.CfnOutput(
                self,
                "AnalyticsFunctionArn",
                value=self.analytics_function.function_arn,
                description="ARN of the analytics function"
            )