"""
Scheduled Email Reports Stack

This CDK stack creates a complete serverless email reporting system using:
- AWS App Runner service for containerized Flask application
- Amazon SES for email delivery
- EventBridge Scheduler for automated scheduling
- CloudWatch for monitoring and alerting
- IAM roles with appropriate permissions

Architecture follows AWS Well-Architected principles with emphasis on:
- Security: Least privilege IAM roles
- Reliability: Health checks and retry logic
- Performance: Auto-scaling capabilities
- Cost Optimization: Serverless services
- Operational Excellence: Comprehensive monitoring
"""

from typing import Any, Dict, List

from aws_cdk import (
    CfnOutput,
    Duration,
    RemovalPolicy,
    Stack,
    aws_apprunner as apprunner,
    aws_cloudwatch as cloudwatch,
    aws_events_targets as targets,
    aws_iam as iam,
    aws_logs as logs,
    aws_scheduler as scheduler,
    aws_ses as ses,
)
from constructs import Construct


class ScheduledEmailReportsStack(Stack):
    """
    CDK Stack for Scheduled Email Reports using App Runner and SES.
    
    This stack creates all the necessary infrastructure for a serverless
    email reporting system with automated scheduling capabilities.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs: Any) -> None:
        """
        Initialize the Scheduled Email Reports Stack.
        
        Args:
            scope: The parent construct
            construct_id: Unique identifier for this stack
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Get configuration from CDK context
        self.app_name = self.node.try_get_context("app_name") or "email-reports-service"
        self.verified_email = self.node.try_get_context("verified_email") or "your-email@example.com"
        self.schedule_expression = self.node.try_get_context("schedule_expression") or "cron(0 9 * * ? *)"
        
        # Create IAM role for App Runner service
        self.app_runner_role = self._create_app_runner_role()
        
        # Create SES email identity
        self.email_identity = self._create_ses_identity()
        
        # Create App Runner service
        self.app_runner_service = self._create_app_runner_service()
        
        # Create CloudWatch log group for better log management
        self.log_group = self._create_log_group()
        
        # Create CloudWatch dashboard for monitoring
        self.dashboard = self._create_dashboard()
        
        # Create CloudWatch alarms for monitoring
        self.alarms = self._create_alarms()
        
        # Create EventBridge Scheduler role
        self.scheduler_role = self._create_scheduler_role()
        
        # Create EventBridge Schedule
        self.schedule = self._create_schedule()
        
        # Create stack outputs
        self._create_outputs()

    def _create_app_runner_role(self) -> iam.Role:
        """
        Create IAM role for App Runner service with minimum required permissions.
        
        Returns:
            IAM Role for App Runner service
        """
        role = iam.Role(
            self,
            "AppRunnerServiceRole",
            assumed_by=iam.ServicePrincipal("tasks.apprunner.amazonaws.com"),
            description="Role for App Runner service to access SES and CloudWatch",
            managed_policies=[
                # Minimal managed policy for basic operations
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSAppRunnerServicePolicyForECRAccess"
                )
            ]
        )

        # Add specific permissions for SES
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ses:SendEmail",
                    "ses:SendRawEmail",
                    "ses:GetIdentityVerificationAttributes",
                ],
                resources=[
                    f"arn:aws:ses:{self.region}:{self.account}:identity/*"
                ]
            )
        )

        # Add permissions for CloudWatch metrics
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudwatch:PutMetricData"
                ],
                resources=["*"],
                conditions={
                    "StringEquals": {
                        "cloudwatch:namespace": "EmailReports"
                    }
                }
            )
        )

        return role

    def _create_ses_identity(self) -> ses.EmailIdentity:
        """
        Create SES email identity for sending emails.
        
        Returns:
            SES EmailIdentity construct
        """
        identity = ses.EmailIdentity(
            self,
            "EmailIdentity",
            identity=ses.Identity.email(self.verified_email),
            mail_from_domain=None,  # Use default mail-from domain
            feedback_forwarding=True,
            configuration_set=None  # Use default configuration set
        )

        return identity

    def _create_app_runner_service(self) -> apprunner.CfnService:
        """
        Create App Runner service for the containerized Flask application.
        
        Returns:
            App Runner service construct
        """
        # Define service configuration
        source_configuration = {
            "autoDeploymentsEnabled": True,
            "codeRepository": {
                "repositoryUrl": "https://github.com/your-username/email-reports-app",
                "sourceCodeVersion": {
                    "type": "BRANCH",
                    "value": "main"
                },
                "codeConfiguration": {
                    "configurationSource": "REPOSITORY",
                    "codeConfigurationValues": {
                        "runtime": "PYTHON_3",
                        "buildCommand": "pip install -r requirements.txt",
                        "startCommand": "python app.py",
                        "runtimeEnvironmentVariables": {
                            "SES_VERIFIED_EMAIL": self.verified_email,
                            "AWS_DEFAULT_REGION": self.region
                        }
                    }
                }
            }
        }

        # Instance configuration
        instance_configuration = {
            "cpu": "0.25 vCPU",
            "memory": "0.5 GB",
            "instanceRoleArn": self.app_runner_role.role_arn
        }

        # Health check configuration
        health_check_configuration = {
            "protocol": "HTTP",
            "path": "/health",
            "interval": 10,
            "timeout": 5,
            "healthyThreshold": 1,
            "unhealthyThreshold": 5
        }

        service = apprunner.CfnService(
            self,
            "EmailReportsService",
            service_name=self.app_name,
            source_configuration=source_configuration,
            instance_configuration=instance_configuration,
            health_check_configuration=health_check_configuration,
            auto_scaling_configuration_arn=None,  # Use default auto-scaling
            encryption_configuration={
                "kmsKey": "alias/aws/apprunner"  # Use AWS managed key
            },
            observability_configuration={
                "observabilityEnabled": True,
                "observabilityConfigurationArn": None  # Use default observability
            },
            network_configuration={
                "egressConfiguration": {
                    "egressType": "DEFAULT"  # Allow all outbound traffic
                }
            }
        )

        return service

    def _create_log_group(self) -> logs.LogGroup:
        """
        Create CloudWatch log group for App Runner service logs.
        
        Returns:
            CloudWatch LogGroup construct
        """
        log_group = logs.LogGroup(
            self,
            "AppRunnerLogGroup",
            log_group_name=f"/aws/apprunner/{self.app_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        return log_group

    def _create_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for monitoring the email reporting system.
        
        Returns:
            CloudWatch Dashboard construct
        """
        dashboard = cloudwatch.Dashboard(
            self,
            "EmailReportsDashboard",
            dashboard_name=f"{self.app_name}-dashboard",
            default_interval=Duration.hours(1)
        )

        # Add metrics widgets
        dashboard.add_widgets(
            # App Runner service metrics
            cloudwatch.GraphWidget(
                title="App Runner Service Health",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/AppRunner",
                        metric_name="RequestCount",
                        dimensions_map={
                            "ServiceName": self.app_name
                        },
                        statistic="Sum"
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/AppRunner",
                        metric_name="ResponseTime",
                        dimensions_map={
                            "ServiceName": self.app_name
                        },
                        statistic="Average"
                    )
                ],
                width=12,
                height=6
            ),
            
            # Custom application metrics
            cloudwatch.GraphWidget(
                title="Email Reports Generated",
                left=[
                    cloudwatch.Metric(
                        namespace="EmailReports",
                        metric_name="ReportsGenerated",
                        statistic="Sum"
                    )
                ],
                width=12,
                height=6
            ),

            # SES metrics
            cloudwatch.GraphWidget(
                title="SES Email Metrics",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/SES",
                        metric_name="Send",
                        statistic="Sum"
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/SES", 
                        metric_name="Delivery",
                        statistic="Sum"
                    )
                ],
                width=12,
                height=6
            )
        )

        return dashboard

    def _create_alarms(self) -> List[cloudwatch.Alarm]:
        """
        Create CloudWatch alarms for monitoring application health.
        
        Returns:
            List of CloudWatch alarms
        """
        alarms = []

        # App Runner 4xx errors alarm
        error_alarm = cloudwatch.Alarm(
            self,
            "AppRunnerErrorAlarm",
            alarm_name=f"{self.app_name}-4xx-errors",
            alarm_description="Alert when App Runner service has high error rate",
            metric=cloudwatch.Metric(
                namespace="AWS/AppRunner",
                metric_name="4xxStatusResponses",
                dimensions_map={
                    "ServiceName": self.app_name
                },
                statistic="Sum"
            ),
            threshold=5,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        alarms.append(error_alarm)

        # Report generation failure alarm
        report_alarm = cloudwatch.Alarm(
            self,
            "ReportGenerationAlarm",
            alarm_name=f"{self.app_name}-report-failures",
            alarm_description="Alert when email report generation fails",
            metric=cloudwatch.Metric(
                namespace="EmailReports",
                metric_name="ReportsGenerated",
                statistic="Sum"
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        alarms.append(report_alarm)

        return alarms

    def _create_scheduler_role(self) -> iam.Role:
        """
        Create IAM role for EventBridge Scheduler to invoke App Runner.
        
        Returns:
            IAM Role for EventBridge Scheduler
        """
        role = iam.Role(
            self,
            "SchedulerExecutionRole",
            assumed_by=iam.ServicePrincipal("scheduler.amazonaws.com"),
            description="Role for EventBridge Scheduler to invoke App Runner service"
        )

        # Add permissions for HTTP invocation
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "apprunner:InvokeService"
                ],
                resources=[
                    f"arn:aws:apprunner:{self.region}:{self.account}:service/{self.app_name}/*"
                ]
            )
        )

        return role

    def _create_schedule(self) -> scheduler.CfnSchedule:
        """
        Create EventBridge Schedule for automated report generation.
        
        Returns:
            EventBridge Schedule construct
        """
        # Get service URL (this would be dynamically retrieved in practice)
        service_url = f"{self.app_runner_service.attr_service_url}"

        schedule_config = scheduler.CfnSchedule(
            self,
            "EmailReportSchedule",
            name=f"{self.app_name}-schedule",
            description="Daily email report generation schedule",
            schedule_expression=self.schedule_expression,
            schedule_expression_timezone="UTC",
            state="ENABLED",
            flexible_time_window=scheduler.CfnSchedule.FlexibleTimeWindowProperty(
                mode="OFF"
            ),
            target=scheduler.CfnSchedule.TargetProperty(
                arn="arn:aws:scheduler:::http-invoke",
                role_arn=self.scheduler_role.role_arn,
                http_parameters=scheduler.CfnSchedule.HttpParametersProperty(
                    http_method="POST",
                    url=f"https://{service_url}/generate-report",
                    header_parameters={
                        "Content-Type": "application/json"
                    }
                ),
                retry_policy=scheduler.CfnSchedule.RetryPolicyProperty(
                    maximum_retry_attempts=3,
                    maximum_event_age_in_seconds=86400
                )
            )
        )

        return schedule_config

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        
        CfnOutput(
            self,
            "AppRunnerServiceUrl",
            value=f"https://{self.app_runner_service.attr_service_url}",
            description="URL of the App Runner service",
            export_name=f"{self.stack_name}-service-url"
        )

        CfnOutput(
            self,
            "AppRunnerServiceArn", 
            value=self.app_runner_service.attr_service_arn,
            description="ARN of the App Runner service",
            export_name=f"{self.stack_name}-service-arn"
        )

        CfnOutput(
            self,
            "VerifiedEmailAddress",
            value=self.verified_email,
            description="Verified email address for SES",
            export_name=f"{self.stack_name}-verified-email"
        )

        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.app_name}-dashboard",
            description="CloudWatch Dashboard URL",
            export_name=f"{self.stack_name}-dashboard-url"
        )

        CfnOutput(
            self,
            "ScheduleName",
            value=self.schedule.name,
            description="EventBridge Schedule name",
            export_name=f"{self.stack_name}-schedule-name"
        )