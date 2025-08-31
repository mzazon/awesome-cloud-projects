#!/usr/bin/env python3
"""
CDK Application for Security Compliance Auditing with VPC Lattice and GuardDuty

This CDK application deploys a comprehensive security compliance auditing system
that monitors VPC Lattice access logs, integrates with GuardDuty threat intelligence,
and generates real-time compliance reports.

Architecture:
- VPC Lattice Service Network with access logging
- GuardDuty detector for threat detection
- Lambda function for log processing and correlation
- CloudWatch dashboard for monitoring
- S3 bucket for compliance report storage
- SNS topic for security alerts
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_s3 as s3,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_logs as logs,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    aws_guardduty as guardduty,
    aws_cloudwatch as cloudwatch,
    aws_events as events,
    aws_events_targets as targets,
)
from constructs import Construct


class SecurityComplianceAuditingStack(Stack):
    """
    CDK Stack for Security Compliance Auditing with VPC Lattice and GuardDuty
    
    This stack creates a complete security monitoring solution that:
    1. Enables GuardDuty for threat detection
    2. Sets up VPC Lattice access logging
    3. Processes logs with Lambda for security analysis
    4. Generates compliance reports and alerts
    5. Provides monitoring dashboards
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create core infrastructure
        self._create_storage_resources()
        self._create_guardduty_detector()
        self._create_notification_resources()
        self._create_logging_resources()
        self._create_lambda_resources()
        self._create_monitoring_resources()
        self._create_outputs()

    def _create_storage_resources(self) -> None:
        """Create S3 bucket for compliance reports and log storage"""
        
        # S3 bucket for compliance reports and log archival
        self.compliance_bucket = s3.Bucket(
            self,
            "ComplianceBucket",
            bucket_name=f"security-audit-logs-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            auto_delete_objects=True,  # For demo purposes
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ComplianceReportsLifecycle",
                    enabled=True,
                    prefix="compliance-reports/",
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ],
                    expiration=Duration.days(2555)  # 7 years retention
                )
            ]
        )

        # Add bucket policy for secure access
        self.compliance_bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="DenyInsecureConnections",
                effect=iam.Effect.DENY,
                principals=[iam.AnyPrincipal()],
                actions=["s3:*"],
                resources=[
                    self.compliance_bucket.bucket_arn,
                    f"{self.compliance_bucket.bucket_arn}/*"
                ],
                conditions={
                    "Bool": {
                        "aws:SecureTransport": "false"
                    }
                }
            )
        )

    def _create_guardduty_detector(self) -> None:
        """Enable GuardDuty detector for threat detection"""
        
        self.guardduty_detector = guardduty.CfnDetector(
            self,
            "SecurityGuardDutyDetector",
            enable=True,
            finding_publishing_frequency="FIFTEEN_MINUTES",
            datasources=guardduty.CfnDetector.CFNDataSourceConfigurationsProperty(
                s3_logs=guardduty.CfnDetector.CFNS3LogsConfigurationProperty(
                    enable=True
                ),
                kubernetes=guardduty.CfnDetector.CFNKubernetesConfigurationProperty(
                    audit_logs=guardduty.CfnDetector.CFNKubernetesAuditLogsConfigurationProperty(
                        enable=True
                    )
                ),
                malware_protection=guardduty.CfnDetector.CFNMalwareProtectionConfigurationProperty(
                    scan_ec2_instance_with_findings=guardduty.CfnDetector.CFNScanEc2InstanceWithFindingsConfigurationProperty(
                        ebs_volumes=True
                    )
                )
            )
        )

    def _create_notification_resources(self) -> None:
        """Create SNS topic and subscriptions for security alerts"""
        
        # SNS topic for security alerts
        self.security_alerts_topic = sns.Topic(
            self,
            "SecurityAlertsTopic",
            topic_name="security-compliance-alerts",
            display_name="Security Compliance Alerts",
            # Note: In production, add appropriate email subscriptions
        )

        # Add email subscription (commented out for demo)
        # self.security_alerts_topic.add_subscription(
        #     sns_subscriptions.EmailSubscription("security-admin@yourcompany.com")
        # )

    def _create_logging_resources(self) -> None:
        """Create CloudWatch log groups for VPC Lattice access logs"""
        
        # CloudWatch log group for VPC Lattice access logs
        self.vpc_lattice_log_group = logs.LogGroup(
            self,
            "VPCLatticeLogGroup",
            log_group_name="/aws/vpclattice/security-audit",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )

        # CloudWatch log group for Lambda function logs
        self.lambda_log_group = logs.LogGroup(
            self,
            "SecurityProcessorLogGroup",
            log_group_name="/aws/lambda/security-compliance-processor",
            retention=logs.RetentionDays.TWO_WEEKS,
            removal_policy=RemovalPolicy.DESTROY
        )

    def _create_lambda_resources(self) -> None:
        """Create Lambda function for security log processing"""
        
        # IAM role for Lambda function
        self.lambda_role = iam.Role(
            self,
            "SecurityProcessorRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "SecurityCompliancePolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents",
                                "logs:DescribeLogStreams",
                                "logs:FilterLogEvents"
                            ],
                            resources=["*"]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "guardduty:GetDetector",
                                "guardduty:GetFindings",
                                "guardduty:ListFindings"
                            ],
                            resources=["*"]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:PutObject",
                                "s3:ListBucket"
                            ],
                            resources=[
                                self.compliance_bucket.bucket_arn,
                                f"{self.compliance_bucket.bucket_arn}/*"
                            ]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["sns:Publish"],
                            resources=[self.security_alerts_topic.topic_arn]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["cloudwatch:PutMetricData"],
                            resources=["*"]
                        )
                    ]
                )
            }
        )

        # Lambda function for security log processing
        self.security_processor_function = lambda_.Function(
            self,
            "SecurityProcessorFunction",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="security_processor.lambda_handler",
            code=lambda_.Code.from_asset("lambda"),
            timeout=Duration.minutes(5),
            memory_size=512,
            role=self.lambda_role,
            environment={
                "GUARDDUTY_DETECTOR_ID": self.guardduty_detector.ref,
                "BUCKET_NAME": self.compliance_bucket.bucket_name,
                "SNS_TOPIC_ARN": self.security_alerts_topic.topic_arn,
                "LOG_LEVEL": "INFO"
            },
            log_group=self.lambda_log_group,
            description="Processes VPC Lattice access logs and correlates with GuardDuty findings"
        )

        # CloudWatch log subscription filter to trigger Lambda
        self.log_subscription_filter = logs.SubscriptionFilter(
            self,
            "SecurityLogSubscriptionFilter",
            log_group=self.vpc_lattice_log_group,
            destination=logs.LambdaDestination(self.security_processor_function),
            filter_pattern=logs.FilterPattern.all_terms(),
            filter_name="SecurityComplianceFilter"
        )

        # EventBridge rule to process GuardDuty findings
        self.guardduty_rule = events.Rule(
            self,
            "GuardDutyFindingsRule",
            event_pattern=events.EventPattern(
                source=["aws.guardduty"],
                detail_type=["GuardDuty Finding"]
            ),
            description="Process GuardDuty findings for correlation with VPC Lattice logs"
        )

        # Add Lambda as target for GuardDuty findings
        self.guardduty_rule.add_target(
            targets.LambdaFunction(self.security_processor_function)
        )

    def _create_monitoring_resources(self) -> None:
        """Create CloudWatch dashboard and alarms for security monitoring"""
        
        # Custom metrics for security monitoring
        request_count_metric = cloudwatch.Metric(
            namespace="Security/VPCLattice",
            metric_name="RequestCount",
            statistic="Sum"
        )

        error_count_metric = cloudwatch.Metric(
            namespace="Security/VPCLattice",
            metric_name="ErrorCount",
            statistic="Sum"
        )

        response_time_metric = cloudwatch.Metric(
            namespace="Security/VPCLattice",
            metric_name="AverageResponseTime",
            statistic="Average"
        )

        # CloudWatch dashboard for security monitoring
        self.security_dashboard = cloudwatch.Dashboard(
            self,
            "SecurityComplianceDashboard",
            dashboard_name="SecurityComplianceMonitoring",
            widgets=[
                [
                    # Traffic overview widget
                    cloudwatch.GraphWidget(
                        title="VPC Lattice Traffic Overview",
                        left=[request_count_metric, error_count_metric],
                        width=12,
                        height=6
                    ),
                    # Response time widget
                    cloudwatch.GraphWidget(
                        title="Average Response Time",
                        left=[response_time_metric],
                        width=12,
                        height=6
                    )
                ],
                [
                    # Lambda function metrics
                    cloudwatch.GraphWidget(
                        title="Security Processor Performance",
                        left=[
                            self.security_processor_function.metric_invocations(),
                            self.security_processor_function.metric_errors(),
                            self.security_processor_function.metric_duration()
                        ],
                        width=12,
                        height=6
                    ),
                    # GuardDuty findings widget
                    cloudwatch.SingleValueWidget(
                        title="Active GuardDuty Findings",
                        metrics=[
                            cloudwatch.Metric(
                                namespace="AWS/GuardDuty",
                                metric_name="FindingCount",
                                statistic="Sum"
                            )
                        ],
                        width=12,
                        height=6
                    )
                ]
            ]
        )

        # CloudWatch alarm for high error rate
        self.high_error_alarm = cloudwatch.Alarm(
            self,
            "HighErrorRateAlarm",
            metric=error_count_metric,
            threshold=10,
            evaluation_periods=2,
            datapoints_to_alarm=2,
            alarm_description="Alert when error count exceeds threshold",
            alarm_name="SecurityCompliance-HighErrorRate",
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Add SNS action to alarm
        self.high_error_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.security_alerts_topic)
        )

        # CloudWatch alarm for Lambda function errors
        self.lambda_error_alarm = cloudwatch.Alarm(
            self,
            "LambdaErrorAlarm",
            metric=self.security_processor_function.metric_errors(),
            threshold=1,
            evaluation_periods=1,
            alarm_description="Alert when Lambda function encounters errors",
            alarm_name="SecurityCompliance-LambdaErrors"
        )

        self.lambda_error_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.security_alerts_topic)
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources"""
        
        CfnOutput(
            self,
            "ComplianceBucketName",
            value=self.compliance_bucket.bucket_name,
            description="S3 bucket name for compliance reports and log storage"
        )

        CfnOutput(
            self,
            "GuardDutyDetectorId",
            value=self.guardduty_detector.ref,
            description="GuardDuty detector ID for threat detection"
        )

        CfnOutput(
            self,
            "SecurityAlertsTopicArn",
            value=self.security_alerts_topic.topic_arn,
            description="SNS topic ARN for security alerts"
        )

        CfnOutput(
            self,
            "VPCLatticeLogGroupName",
            value=self.vpc_lattice_log_group.log_group_name,
            description="CloudWatch log group for VPC Lattice access logs"
        )

        CfnOutput(
            self,
            "SecurityProcessorFunctionName",
            value=self.security_processor_function.function_name,
            description="Lambda function name for security log processing"
        )

        CfnOutput(
            self,
            "SecurityDashboardUrl",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.security_dashboard.dashboard_name}",
            description="URL to the CloudWatch security monitoring dashboard"
        )


class SecurityComplianceApp(cdk.App):
    """CDK Application for Security Compliance Auditing"""

    def __init__(self) -> None:
        super().__init__()

        # Environment configuration
        env = cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        )

        # Create the main stack
        SecurityComplianceAuditingStack(
            self,
            "SecurityComplianceAuditingStack",
            env=env,
            description="Security Compliance Auditing with VPC Lattice and GuardDuty",
            tags={
                "Project": "SecurityCompliance",
                "Environment": "Development",
                "Owner": "SecurityTeam",
                "CostCenter": "Security",
                "Recipe": "security-compliance-auditing-lattice-guardduty"
            }
        )


# Create and run the CDK app
app = SecurityComplianceApp()
app.synth()