#!/usr/bin/env python3
"""
CDK Python application for AWS Systems Manager State Manager configuration management.

This application creates a complete configuration management solution using AWS Systems Manager
State Manager with monitoring, alerting, and automated remediation capabilities.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_iam as iam,
    aws_ssm as ssm,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    aws_s3 as s3,
    Duration,
    RemovalPolicy,
    Tags,
)
from constructs import Construct
from typing import Dict, List, Optional


class StateManagerConfigStack(Stack):
    """
    CDK Stack for Systems Manager State Manager configuration management.
    
    This stack creates:
    - IAM roles and policies for State Manager
    - Custom SSM documents for security configuration
    - State Manager associations for automated configuration management
    - CloudWatch monitoring and alerting
    - SNS notifications for compliance events
    - S3 bucket for association outputs
    - Automated remediation workflows
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        notification_email: str,
        target_tag_key: str = "Environment",
        target_tag_value: str = "Demo",
        **kwargs
    ) -> None:
        """
        Initialize the State Manager configuration stack.
        
        Args:
            scope: The parent construct
            construct_id: Unique identifier for this stack
            notification_email: Email address for SNS notifications
            target_tag_key: EC2 tag key for targeting instances
            target_tag_value: EC2 tag value for targeting instances
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        self.notification_email = notification_email
        self.target_tag_key = target_tag_key
        self.target_tag_value = target_tag_value

        # Create foundational resources
        self.s3_bucket = self._create_s3_bucket()
        self.log_group = self._create_log_group()
        self.sns_topic = self._create_sns_topic()
        self.state_manager_role = self._create_state_manager_role()
        
        # Create custom SSM documents
        self.security_config_document = self._create_security_config_document()
        self.remediation_document = self._create_remediation_document()
        self.compliance_report_document = self._create_compliance_report_document()
        
        # Create State Manager associations
        self.ssm_agent_association = self._create_ssm_agent_association()
        self.security_association = self._create_security_association()
        
        # Create monitoring and alerting
        self.association_failure_alarm = self._create_association_failure_alarm()
        self.compliance_violation_alarm = self._create_compliance_violation_alarm()
        self.dashboard = self._create_dashboard()
        
        # Add tags to all resources
        self._add_tags()

    def _create_s3_bucket(self) -> s3.Bucket:
        """Create S3 bucket for State Manager association outputs."""
        bucket = s3.Bucket(
            self,
            "StateManagerOutputBucket",
            bucket_name=f"aws-ssm-{self.region}-{self.account}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldOutputs",
                    enabled=True,
                    expiration=Duration.days(90),
                    noncurrent_version_expiration=Duration.days(30),
                )
            ],
        )
        
        return bucket

    def _create_log_group(self) -> logs.LogGroup:
        """Create CloudWatch log group for State Manager operations."""
        log_group = logs.LogGroup(
            self,
            "StateManagerLogGroup",
            log_group_name="/aws/ssm/state-manager",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        return log_group

    def _create_sns_topic(self) -> sns.Topic:
        """Create SNS topic for configuration drift alerts."""
        topic = sns.Topic(
            self,
            "ConfigDriftAlertsTopic",
            topic_name="config-drift-alerts",
            display_name="Configuration Drift Alerts",
        )
        
        # Add email subscription
        topic.add_subscription(
            sns.EmailSubscription(self.notification_email)
        )
        
        return topic

    def _create_state_manager_role(self) -> iam.Role:
        """Create IAM role for State Manager operations."""
        role = iam.Role(
            self,
            "StateManagerRole",
            role_name="SSMStateManagerRole",
            assumed_by=iam.ServicePrincipal("ssm.amazonaws.com"),
            description="Role for Systems Manager State Manager operations",
        )
        
        # Attach AWS managed policies
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "AmazonSSMManagedInstanceCore"
            )
        )
        
        # Create custom policy for State Manager operations
        custom_policy = iam.Policy(
            self,
            "StateManagerCustomPolicy",
            policy_name="SSMStateManagerCustomPolicy",
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "ssm:CreateAssociation",
                        "ssm:DescribeAssociation*",
                        "ssm:GetAutomationExecution",
                        "ssm:ListAssociations",
                        "ssm:ListDocuments",
                        "ssm:SendCommand",
                        "ssm:StartAutomationExecution",
                        "ssm:DescribeInstanceInformation",
                        "ssm:DescribeDocumentParameters",
                        "ssm:ListCommandInvocations",
                        "ssm:StartAssociationsOnce",
                    ],
                    resources=["*"],
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "ec2:DescribeInstances",
                        "ec2:DescribeInstanceAttribute",
                        "ec2:DescribeImages",
                        "ec2:DescribeSnapshots",
                        "ec2:DescribeVolumes",
                    ],
                    resources=["*"],
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "cloudwatch:PutMetricData",
                        "logs:CreateLogGroup",
                        "logs:CreateLogStream",
                        "logs:PutLogEvents",
                    ],
                    resources=["*"],
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=["sns:Publish"],
                    resources=[self.sns_topic.topic_arn],
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:GetObject",
                        "s3:PutObject",
                        "s3:PutObjectAcl",
                    ],
                    resources=[f"{self.s3_bucket.bucket_arn}/*"],
                ),
            ],
        )
        
        role.attach_inline_policy(custom_policy)
        
        return role

    def _create_security_config_document(self) -> ssm.CfnDocument:
        """Create custom SSM document for security configuration."""
        document_content = {
            "schemaVersion": "2.2",
            "description": "Configure security settings on Linux instances",
            "parameters": {
                "enableFirewall": {
                    "type": "String",
                    "description": "Enable firewall",
                    "default": "true",
                    "allowedValues": ["true", "false"],
                },
                "disableRootLogin": {
                    "type": "String",
                    "description": "Disable root SSH login",
                    "default": "true",
                    "allowedValues": ["true", "false"],
                },
            },
            "mainSteps": [
                {
                    "action": "aws:runShellScript",
                    "name": "configureFirewall",
                    "precondition": {"StringEquals": ["platformType", "Linux"]},
                    "inputs": {
                        "runCommand": [
                            "#!/bin/bash",
                            "if [ '{{ enableFirewall }}' == 'true' ]; then",
                            "  if command -v ufw &> /dev/null; then",
                            "    ufw --force enable",
                            "    echo 'UFW firewall enabled'",
                            "  elif command -v firewall-cmd &> /dev/null; then",
                            "    systemctl enable firewalld",
                            "    systemctl start firewalld",
                            "    echo 'Firewalld enabled'",
                            "  fi",
                            "fi",
                        ]
                    },
                },
                {
                    "action": "aws:runShellScript",
                    "name": "configureSshSecurity",
                    "precondition": {"StringEquals": ["platformType", "Linux"]},
                    "inputs": {
                        "runCommand": [
                            "#!/bin/bash",
                            "if [ '{{ disableRootLogin }}' == 'true' ]; then",
                            "  sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config",
                            "  if systemctl is-active --quiet sshd; then",
                            "    systemctl reload sshd",
                            "  fi",
                            "  echo 'Root SSH login disabled'",
                            "fi",
                        ]
                    },
                },
            ],
        }
        
        document = ssm.CfnDocument(
            self,
            "SecurityConfigDocument",
            document_type="Command",
            document_format="JSON",
            content=document_content,
            name="Custom-SecurityConfiguration",
            tags=[
                {"Key": "Purpose", "Value": "StateManagerDemo"},
                {"Key": "DocumentType", "Value": "SecurityConfiguration"},
            ],
        )
        
        return document

    def _create_remediation_document(self) -> ssm.CfnDocument:
        """Create automation document for remediation workflows."""
        document_content = {
            "schemaVersion": "0.3",
            "description": "Automated remediation for configuration drift",
            "assumeRole": "{{ AutomationAssumeRole }}",
            "parameters": {
                "AutomationAssumeRole": {
                    "type": "String",
                    "description": "The ARN of the role for automation",
                },
                "InstanceId": {
                    "type": "String",
                    "description": "The ID of the non-compliant instance",
                },
                "AssociationId": {
                    "type": "String",
                    "description": "The ID of the failed association",
                },
            },
            "mainSteps": [
                {
                    "name": "RerunAssociation",
                    "action": "aws:executeAwsApi",
                    "inputs": {
                        "Service": "ssm",
                        "Api": "StartAssociationsOnce",
                        "AssociationIds": ["{{ AssociationId }}"],
                    },
                },
                {
                    "name": "WaitForCompletion",
                    "action": "aws:waitForAwsResourceProperty",
                    "inputs": {
                        "Service": "ssm",
                        "Api": "DescribeAssociationExecutions",
                        "AssociationId": "{{ AssociationId }}",
                        "PropertySelector": "$.AssociationExecutions[0].Status",
                        "DesiredValues": ["Success"],
                    },
                    "timeoutSeconds": 300,
                },
                {
                    "name": "SendNotification",
                    "action": "aws:executeAwsApi",
                    "inputs": {
                        "Service": "sns",
                        "Api": "Publish",
                        "TopicArn": self.sns_topic.topic_arn,
                        "Message": "Configuration drift remediation completed for instance {{ InstanceId }}",
                    },
                },
            ],
        }
        
        document = ssm.CfnDocument(
            self,
            "RemediationDocument",
            document_type="Automation",
            document_format="JSON",
            content=document_content,
            name="AutoRemediation",
            tags=[
                {"Key": "Purpose", "Value": "StateManagerDemo"},
                {"Key": "DocumentType", "Value": "Remediation"},
            ],
        )
        
        return document

    def _create_compliance_report_document(self) -> ssm.CfnDocument:
        """Create automation document for compliance reporting."""
        document_content = {
            "schemaVersion": "0.3",
            "description": "Generate compliance report",
            "mainSteps": [
                {
                    "name": "GenerateReport",
                    "action": "aws:executeAwsApi",
                    "inputs": {
                        "Service": "ssm",
                        "Api": "ListComplianceItems",
                        "ResourceTypes": ["ManagedInstance"],
                        "Filters": [
                            {
                                "Key": "ComplianceType",
                                "Values": ["Association"],
                            }
                        ],
                    },
                }
            ],
        }
        
        document = ssm.CfnDocument(
            self,
            "ComplianceReportDocument",
            document_type="Automation",
            document_format="JSON",
            content=document_content,
            name="ComplianceReport",
            tags=[
                {"Key": "Purpose", "Value": "StateManagerDemo"},
                {"Key": "DocumentType", "Value": "ComplianceReport"},
            ],
        )
        
        return document

    def _create_ssm_agent_association(self) -> ssm.CfnAssociation:
        """Create association to keep SSM Agent updated."""
        association = ssm.CfnAssociation(
            self,
            "SSMAgentAssociation",
            name="AWS-UpdateSSMAgent",
            association_name="ConfigManagement-SSMAgent",
            schedule_expression="rate(7 days)",
            targets=[
                {
                    "key": f"tag:{self.target_tag_key}",
                    "values": [self.target_tag_value],
                }
            ],
            output_location={
                "s3Location": {
                    "outputS3BucketName": self.s3_bucket.bucket_name,
                    "outputS3KeyPrefix": "ssm-agent-updates/",
                    "outputS3Region": self.region,
                }
            },
        )
        
        return association

    def _create_security_association(self) -> ssm.CfnAssociation:
        """Create association for security configuration."""
        association = ssm.CfnAssociation(
            self,
            "SecurityAssociation",
            name=self.security_config_document.ref,
            association_name="ConfigManagement-Security",
            schedule_expression="rate(1 day)",
            targets=[
                {
                    "key": f"tag:{self.target_tag_key}",
                    "values": [self.target_tag_value],
                }
            ],
            parameters={
                "enableFirewall": ["true"],
                "disableRootLogin": ["true"],
            },
            compliance_severity="CRITICAL",
            output_location={
                "s3Location": {
                    "outputS3BucketName": self.s3_bucket.bucket_name,
                    "outputS3KeyPrefix": "security-config/",
                    "outputS3Region": self.region,
                }
            },
        )
        
        # Ensure the document is created before the association
        association.add_depends_on(self.security_config_document)
        
        return association

    def _create_association_failure_alarm(self) -> cloudwatch.Alarm:
        """Create CloudWatch alarm for association failures."""
        alarm = cloudwatch.Alarm(
            self,
            "AssociationFailureAlarm",
            alarm_name="SSM-Association-Failures",
            alarm_description="Monitor SSM association failures",
            metric=cloudwatch.Metric(
                namespace="AWS/SSM",
                metric_name="AssociationExecutionsFailed",
                dimensions_map={
                    "AssociationName": "ConfigManagement-Security",
                },
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
        )
        
        alarm.add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )
        
        return alarm

    def _create_compliance_violation_alarm(self) -> cloudwatch.Alarm:
        """Create CloudWatch alarm for compliance violations."""
        alarm = cloudwatch.Alarm(
            self,
            "ComplianceViolationAlarm",
            alarm_name="SSM-Compliance-Violations",
            alarm_description="Monitor compliance violations",
            metric=cloudwatch.Metric(
                namespace="AWS/SSM",
                metric_name="ComplianceByConfigRule",
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
        )
        
        alarm.add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )
        
        return alarm

    def _create_dashboard(self) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for monitoring."""
        dashboard = cloudwatch.Dashboard(
            self,
            "StateManagerDashboard",
            dashboard_name="SSM-StateManager",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Association Execution Status",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/SSM",
                                metric_name="AssociationExecutionsSucceeded",
                                dimensions_map={
                                    "AssociationName": "ConfigManagement-Security",
                                },
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/SSM",
                                metric_name="AssociationExecutionsFailed",
                                dimensions_map={
                                    "AssociationName": "ConfigManagement-Security",
                                },
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                        ],
                        width=12,
                    ),
                    cloudwatch.GraphWidget(
                        title="Compliance Status",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/SSM",
                                metric_name="ComplianceByConfigRule",
                                dimensions_map={
                                    "RuleName": "ConfigManagement-Security",
                                    "ComplianceType": "Association",
                                },
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                        ],
                        width=12,
                    ),
                ],
            ],
        )
        
        return dashboard

    def _add_tags(self) -> None:
        """Add tags to all resources in the stack."""
        Tags.of(self).add("Purpose", "StateManagerDemo")
        Tags.of(self).add("Environment", "Demo")
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("Recipe", "configuration-management-systems-manager-state-manager")


class StateManagerApp(cdk.App):
    """CDK Application for State Manager configuration management."""
    
    def __init__(self) -> None:
        super().__init__()
        
        # Get configuration from context or environment
        notification_email = self.node.try_get_context("notification_email") or "your-email@example.com"
        target_tag_key = self.node.try_get_context("target_tag_key") or "Environment"
        target_tag_value = self.node.try_get_context("target_tag_value") or "Demo"
        
        # Create the main stack
        StateManagerConfigStack(
            self,
            "StateManagerConfigStack",
            notification_email=notification_email,
            target_tag_key=target_tag_key,
            target_tag_value=target_tag_value,
            description="AWS Systems Manager State Manager configuration management solution",
        )


# Application entry point
if __name__ == "__main__":
    app = StateManagerApp()
    app.synth()