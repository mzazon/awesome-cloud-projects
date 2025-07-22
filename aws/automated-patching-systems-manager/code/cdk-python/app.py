#!/usr/bin/env python3
"""
CDK Python Application for Automated Patching and Maintenance Windows

This application deploys AWS Systems Manager Patch Manager infrastructure
including patch baselines, maintenance windows, IAM roles, and monitoring.
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    StackProps,
    Duration,
    CfnOutput,
    aws_ssm as ssm,
    aws_iam as iam,
    aws_s3 as s3,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    aws_events as events,
    aws_events_targets as targets,
)
from constructs import Construct


class PatchManagementStack(Stack):
    """
    Stack for deploying AWS Systems Manager Patch Management infrastructure.
    
    Creates patch baselines, maintenance windows, IAM roles, monitoring,
    and supporting resources for automated patching operations.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        environment: str = "production",
        patch_schedule: str = "cron(0 2 ? * SUN *)",
        scan_schedule: str = "cron(0 1 * * ? *)",
        notification_email: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the Patch Management Stack.
        
        Args:
            scope: The parent construct
            construct_id: Unique identifier for this stack
            environment: Environment name (production, staging, etc.)
            patch_schedule: Cron expression for patch installation window
            scan_schedule: Cron expression for patch scanning window
            notification_email: Email address for notifications
        """
        super().__init__(scope, construct_id, **kwargs)

        self.environment = environment
        self.patch_schedule = patch_schedule
        self.scan_schedule = scan_schedule
        self.notification_email = notification_email

        # Create supporting resources
        self.create_s3_bucket()
        self.create_sns_topic()
        self.create_cloudwatch_log_group()
        self.create_iam_role()
        
        # Create patch management resources
        self.create_patch_baseline()
        self.create_maintenance_windows()
        self.create_monitoring()
        
        # Create outputs
        self.create_outputs()

    def create_s3_bucket(self) -> None:
        """Create S3 bucket for storing patch reports and logs."""
        self.reports_bucket = s3.Bucket(
            self,
            "PatchReportsBucket",
            bucket_name=f"patch-reports-{self.account}-{self.region}-{self.environment}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=cdk.RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldReports",
                    enabled=True,
                    expiration=Duration.days(90),
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        )
                    ]
                )
            ]
        )

    def create_sns_topic(self) -> None:
        """Create SNS topic for patch notifications."""
        self.notification_topic = sns.Topic(
            self,
            "PatchNotificationTopic",
            topic_name=f"patch-notifications-{self.environment}",
            display_name=f"Patch Management Notifications - {self.environment}",
            kms_master_key_id="alias/aws/sns"
        )

        # Subscribe email if provided
        if self.notification_email:
            self.notification_topic.add_subscription(
                sns.EmailSubscription(self.notification_email)
            )

    def create_cloudwatch_log_group(self) -> None:
        """Create CloudWatch log group for patch operations."""
        self.log_group = logs.LogGroup(
            self,
            "PatchLogGroup",
            log_group_name=f"/aws/ssm/patch-management/{self.environment}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=cdk.RemovalPolicy.DESTROY
        )

    def create_iam_role(self) -> None:
        """Create IAM role for maintenance window operations."""
        self.maintenance_window_role = iam.Role(
            self,
            "MaintenanceWindowRole",
            role_name=f"MaintenanceWindowRole-{self.environment}",
            assumed_by=iam.ServicePrincipal("ssm.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonSSMMaintenanceWindowRole"
                )
            ],
            inline_policies={
                "PatchManagementPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:PutObject",
                                "s3:GetObject",
                                "s3:ListBucket"
                            ],
                            resources=[
                                self.reports_bucket.bucket_arn,
                                f"{self.reports_bucket.bucket_arn}/*"
                            ]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "sns:Publish"
                            ],
                            resources=[self.notification_topic.topic_arn]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents"
                            ],
                            resources=[self.log_group.log_group_arn]
                        )
                    ]
                )
            }
        )

    def create_patch_baseline(self) -> None:
        """Create custom patch baseline with approval rules."""
        self.patch_baseline = ssm.CfnPatchBaseline(
            self,
            "CustomPatchBaseline",
            name=f"custom-baseline-{self.environment}",
            description=f"Custom patch baseline for {self.environment} instances",
            operating_system="AMAZON_LINUX_2",
            approved_patches_compliance_level="CRITICAL",
            approval_rules=ssm.CfnPatchBaseline.RuleGroupProperty(
                patch_rules=[
                    ssm.CfnPatchBaseline.RuleProperty(
                        approve_after_days=7,
                        compliance_level="CRITICAL",
                        patch_filter_group=ssm.CfnPatchBaseline.PatchFilterGroupProperty(
                            patch_filters=[
                                ssm.CfnPatchBaseline.PatchFilterProperty(
                                    key="CLASSIFICATION",
                                    values=["Security", "Bugfix", "Critical"]
                                )
                            ]
                        )
                    )
                ]
            ),
            tags=[
                cdk.CfnTag(key="Environment", value=self.environment),
                cdk.CfnTag(key="Purpose", value="AutomatedPatching")
            ]
        )

        # Register patch baseline with patch group
        self.patch_group = ssm.CfnPatchGroup(
            self,
            "PatchGroup",
            baseline_id=self.patch_baseline.ref,
            patch_group=self.environment.title()
        )

    def create_maintenance_windows(self) -> None:
        """Create maintenance windows for patch installation and scanning."""
        # Create patch installation maintenance window
        self.patch_maintenance_window = ssm.CfnMaintenanceWindow(
            self,
            "PatchMaintenanceWindow",
            name=f"patch-window-{self.environment}",
            description=f"Weekly patching maintenance window for {self.environment}",
            schedule=self.patch_schedule,
            duration=4,
            cutoff=1,
            schedule_timezone="UTC",
            allow_unassociated_targets=True,
            tags=[
                cdk.CfnTag(key="Environment", value=self.environment),
                cdk.CfnTag(key="Purpose", value="PatchInstallation")
            ]
        )

        # Create scan maintenance window
        self.scan_maintenance_window = ssm.CfnMaintenanceWindow(
            self,
            "ScanMaintenanceWindow",
            name=f"scan-window-{self.environment}",
            description=f"Daily patch scanning window for {self.environment}",
            schedule=self.scan_schedule,
            duration=2,
            cutoff=1,
            schedule_timezone="UTC",
            allow_unassociated_targets=True,
            tags=[
                cdk.CfnTag(key="Environment", value=self.environment),
                cdk.CfnTag(key="Purpose", value="PatchScanning")
            ]
        )

        # Create maintenance window targets
        self.create_maintenance_window_targets()
        
        # Create maintenance window tasks
        self.create_maintenance_window_tasks()

    def create_maintenance_window_targets(self) -> None:
        """Create targets for maintenance windows based on EC2 tags."""
        # Target for patch installation
        self.patch_target = ssm.CfnMaintenanceWindowTarget(
            self,
            "PatchTarget",
            window_id=self.patch_maintenance_window.ref,
            resource_type="INSTANCE",
            targets=[
                ssm.CfnMaintenanceWindowTarget.TargetsProperty(
                    key="tag:Environment",
                    values=[self.environment.title()]
                )
            ],
            name=f"{self.environment.title()}Instances"
        )

        # Target for patch scanning
        self.scan_target = ssm.CfnMaintenanceWindowTarget(
            self,
            "ScanTarget",
            window_id=self.scan_maintenance_window.ref,
            resource_type="INSTANCE",
            targets=[
                ssm.CfnMaintenanceWindowTarget.TargetsProperty(
                    key="tag:Environment",
                    values=[self.environment.title()]
                )
            ],
            name=f"{self.environment.title()}ScanInstances"
        )

    def create_maintenance_window_tasks(self) -> None:
        """Create maintenance window tasks for patching and scanning."""
        # Patch installation task
        self.patch_task = ssm.CfnMaintenanceWindowTask(
            self,
            "PatchTask",
            window_id=self.patch_maintenance_window.ref,
            task_type="RUN_COMMAND",
            task_arn="AWS-RunPatchBaseline",
            service_role_arn=self.maintenance_window_role.role_arn,
            targets=[
                ssm.CfnMaintenanceWindowTask.TargetProperty(
                    key="WindowTargetIds",
                    values=[self.patch_target.ref]
                )
            ],
            name="PatchingTask",
            description="Install patches using custom baseline",
            max_concurrency="50%",
            max_errors="10%",
            priority=1,
            task_parameters={
                "BaselineOverride": {
                    "Values": [self.patch_baseline.ref]
                },
                "Operation": {
                    "Values": ["Install"]
                }
            },
            logging_info=ssm.CfnMaintenanceWindowTask.LoggingInfoProperty(
                s3_bucket_name=self.reports_bucket.bucket_name,
                s3_key_prefix="patch-logs"
            )
        )

        # Patch scanning task
        self.scan_task = ssm.CfnMaintenanceWindowTask(
            self,
            "ScanTask",
            window_id=self.scan_maintenance_window.ref,
            task_type="RUN_COMMAND",
            task_arn="AWS-RunPatchBaseline",
            service_role_arn=self.maintenance_window_role.role_arn,
            targets=[
                ssm.CfnMaintenanceWindowTask.TargetProperty(
                    key="WindowTargetIds",
                    values=[self.scan_target.ref]
                )
            ],
            name="ScanningTask",
            description="Scan for missing patches",
            max_concurrency="100%",
            max_errors="5%",
            priority=1,
            task_parameters={
                "BaselineOverride": {
                    "Values": [self.patch_baseline.ref]
                },
                "Operation": {
                    "Values": ["Scan"]
                }
            },
            logging_info=ssm.CfnMaintenanceWindowTask.LoggingInfoProperty(
                s3_bucket_name=self.reports_bucket.bucket_name,
                s3_key_prefix="scan-logs"
            )
        )

    def create_monitoring(self) -> None:
        """Create CloudWatch monitoring and alarms for patch compliance."""
        # Create CloudWatch alarm for patch compliance
        self.compliance_alarm = cloudwatch.Alarm(
            self,
            "PatchComplianceAlarm",
            alarm_name=f"PatchComplianceAlarm-{self.environment}",
            alarm_description="Monitor patch compliance status",
            metric=cloudwatch.Metric(
                namespace="AWS/SSM-PatchCompliance",
                metric_name="ComplianceByPatchGroup",
                dimensions_map={
                    "PatchGroup": self.environment.title()
                },
                statistic="Maximum",
                period=Duration.hours(1)
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.BREACHING
        )

        # Add SNS action to alarm
        self.compliance_alarm.add_alarm_action(
            cloudwatch.AlarmAction(
                sns_topic=self.notification_topic
            )
        )

        # Create custom metric for maintenance window executions
        self.maintenance_window_metric = cloudwatch.Metric(
            namespace="AWS/SSM-MaintenanceWindow",
            metric_name="MaintenanceWindowExecutions",
            dimensions_map={
                "MaintenanceWindowName": self.patch_maintenance_window.name
            },
            statistic="Sum",
            period=Duration.hours(24)
        )

        # Create alarm for maintenance window failures
        self.maintenance_window_alarm = cloudwatch.Alarm(
            self,
            "MaintenanceWindowFailureAlarm",
            alarm_name=f"MaintenanceWindowFailures-{self.environment}",
            alarm_description="Monitor maintenance window execution failures",
            metric=cloudwatch.Metric(
                namespace="AWS/SSM-MaintenanceWindow",
                metric_name="MaintenanceWindowExecutionsFailed",
                dimensions_map={
                    "MaintenanceWindowName": self.patch_maintenance_window.name
                },
                statistic="Sum",
                period=Duration.hours(1)
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Add SNS action to maintenance window alarm
        self.maintenance_window_alarm.add_alarm_action(
            cloudwatch.AlarmAction(
                sns_topic=self.notification_topic
            )
        )

        # Create dashboard for patch management monitoring
        self.create_dashboard()

    def create_dashboard(self) -> None:
        """Create CloudWatch dashboard for patch management monitoring."""
        self.dashboard = cloudwatch.Dashboard(
            self,
            "PatchManagementDashboard",
            dashboard_name=f"PatchManagement-{self.environment}",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Patch Compliance",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/SSM-PatchCompliance",
                                metric_name="ComplianceByPatchGroup",
                                dimensions_map={
                                    "PatchGroup": self.environment.title()
                                },
                                statistic="Maximum"
                            )
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.GraphWidget(
                        title="Maintenance Window Executions",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/SSM-MaintenanceWindow",
                                metric_name="MaintenanceWindowExecutions",
                                dimensions_map={
                                    "MaintenanceWindowName": self.patch_maintenance_window.name
                                },
                                statistic="Sum"
                            )
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.SingleValueWidget(
                        title="Patch Compliance Status",
                        metrics=[
                            cloudwatch.Metric(
                                namespace="AWS/SSM-PatchCompliance",
                                metric_name="ComplianceByPatchGroup",
                                dimensions_map={
                                    "PatchGroup": self.environment.title()
                                },
                                statistic="Maximum"
                            )
                        ],
                        width=6,
                        height=4
                    ),
                    cloudwatch.SingleValueWidget(
                        title="Failed Maintenance Window Executions",
                        metrics=[
                            cloudwatch.Metric(
                                namespace="AWS/SSM-MaintenanceWindow",
                                metric_name="MaintenanceWindowExecutionsFailed",
                                dimensions_map={
                                    "MaintenanceWindowName": self.patch_maintenance_window.name
                                },
                                statistic="Sum"
                            )
                        ],
                        width=6,
                        height=4
                    )
                ]
            ]
        )

    def create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        CfnOutput(
            self,
            "PatchBaselineId",
            value=self.patch_baseline.ref,
            description="ID of the custom patch baseline",
            export_name=f"PatchBaseline-{self.environment}"
        )

        CfnOutput(
            self,
            "PatchMaintenanceWindowId",
            value=self.patch_maintenance_window.ref,
            description="ID of the patch maintenance window",
            export_name=f"PatchMaintenanceWindow-{self.environment}"
        )

        CfnOutput(
            self,
            "ScanMaintenanceWindowId",
            value=self.scan_maintenance_window.ref,
            description="ID of the scan maintenance window",
            export_name=f"ScanMaintenanceWindow-{self.environment}"
        )

        CfnOutput(
            self,
            "ReportsBucketName",
            value=self.reports_bucket.bucket_name,
            description="Name of the S3 bucket for patch reports",
            export_name=f"PatchReportsBucket-{self.environment}"
        )

        CfnOutput(
            self,
            "NotificationTopicArn",
            value=self.notification_topic.topic_arn,
            description="ARN of the SNS topic for notifications",
            export_name=f"PatchNotificationTopic-{self.environment}"
        )

        CfnOutput(
            self,
            "MaintenanceWindowRoleArn",
            value=self.maintenance_window_role.role_arn,
            description="ARN of the maintenance window IAM role",
            export_name=f"MaintenanceWindowRole-{self.environment}"
        )

        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="URL to the CloudWatch dashboard",
            export_name=f"PatchManagementDashboard-{self.environment}"
        )


class PatchManagementApp(cdk.App):
    """CDK Application for Patch Management Infrastructure."""

    def __init__(self) -> None:
        super().__init__()

        # Get configuration from environment variables or use defaults
        environment = os.getenv("ENVIRONMENT", "production")
        patch_schedule = os.getenv("PATCH_SCHEDULE", "cron(0 2 ? * SUN *)")
        scan_schedule = os.getenv("SCAN_SCHEDULE", "cron(0 1 * * ? *)")
        notification_email = os.getenv("NOTIFICATION_EMAIL")
        
        # Create the patch management stack
        PatchManagementStack(
            self,
            f"PatchManagementStack-{environment}",
            environment=environment,
            patch_schedule=patch_schedule,
            scan_schedule=scan_schedule,
            notification_email=notification_email,
            description=f"Automated patch management infrastructure for {environment} environment",
            tags={
                "Environment": environment,
                "Purpose": "AutomatedPatching",
                "Project": "PatchManagement"
            }
        )


if __name__ == "__main__":
    app = PatchManagementApp()
    app.synth()