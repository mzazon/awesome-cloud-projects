#!/usr/bin/env python3
"""
AWS CDK application for Resource Groups Automated Resource Management.

This application creates infrastructure for organizing and managing AWS resources
using Resource Groups, Systems Manager automation, CloudWatch monitoring,
and SNS notifications.
"""

import os
from typing import Dict, Any
import aws_cdk as cdk
from aws_cdk import (
    App,
    Stack,
    Duration,
    RemovalPolicy,
    aws_resourcegroups as resourcegroups,
    aws_sns as sns,
    aws_ssm as ssm,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cloudwatch_actions,
    aws_budgets as budgets,
    aws_events as events,
    aws_ce as ce,
    aws_logs as logs,
    aws_events_targets as targets,
    Tags,
)
from constructs import Construct
from cdk_nag import AwsSolutionsChecks, NagSuppressions


class ResourceGroupAutomatedManagementStack(Stack):
    """
    CDK Stack for automated resource management using AWS Resource Groups.
    
    This stack creates:
    - Resource Groups based on tags
    - Systems Manager automation documents and roles
    - CloudWatch monitoring and alarms
    - SNS topic for notifications
    - Cost monitoring with budgets
    - EventBridge rules for automated tagging
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        environment_name: str = "production",
        application_name: str = "web-app",
        notification_email: str = None,
        monthly_budget_limit: float = 100.0,
        **kwargs
    ) -> None:
        """
        Initialize the Resource Group Automated Management Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            environment_name: Environment name for resource tagging (default: production)
            application_name: Application name for resource tagging (default: web-app)
            notification_email: Email address for SNS notifications
            monthly_budget_limit: Monthly budget limit in USD (default: 100.0)
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        self.environment_name = environment_name
        self.application_name = application_name
        self.notification_email = notification_email
        self.monthly_budget_limit = monthly_budget_limit

        # Apply common tags to all resources in the stack
        Tags.of(self).add("Environment", self.environment_name)
        Tags.of(self).add("Application", self.application_name)
        Tags.of(self).add("Purpose", "resource-management")
        Tags.of(self).add("ManagedBy", "CDK")

        # Create core infrastructure components
        self._create_sns_topic()
        self._create_resource_group()
        self._create_iam_roles()
        self._create_ssm_automation()
        self._create_cloudwatch_monitoring()
        self._create_cost_monitoring()
        self._create_event_automation()

        # Apply CDK Nag suppressions for legitimate use cases
        self._apply_cdk_nag_suppressions()

    def _create_sns_topic(self) -> None:
        """Create SNS topic for resource group notifications."""
        self.sns_topic = sns.Topic(
            self,
            "ResourceAlertsTopic",
            topic_name=f"resource-alerts-{self.environment_name}",
            display_name="Resource Management Alerts",
            kms_master_key=sns.Topic.DEFAULT_KMS_KEY,  # Use AWS managed KMS key
        )

        # Add email subscription if provided
        if self.notification_email:
            self.sns_topic.add_subscription(
                sns.EmailSubscription(self.notification_email)
            )

        # Store topic ARN for use by other resources
        self.sns_topic_arn = self.sns_topic.topic_arn

    def _create_resource_group(self) -> None:
        """Create tag-based resource group for organizing resources."""
        # Define the resource query for the resource group
        resource_query = {
            "type": "TAG_FILTERS_1_0",
            "query": {
                "resourceTypeFilters": ["AWS::AllSupported"],
                "tagFilters": [
                    {
                        "key": "Environment",
                        "values": [self.environment_name]
                    },
                    {
                        "key": "Application", 
                        "values": [self.application_name]
                    }
                ]
            }
        }

        self.resource_group = resourcegroups.CfnGroup(
            self,
            "ProductionResourceGroup",
            name=f"{self.environment_name}-{self.application_name}-resources",
            description=f"{self.environment_name.title()} {self.application_name} resources",
            resource_query=resource_query,
            tags=[
                cdk.CfnTag(key="Environment", value=self.environment_name),
                cdk.CfnTag(key="Application", value=self.application_name),
                cdk.CfnTag(key="Purpose", value="resource-management")
            ]
        )

    def _create_iam_roles(self) -> None:
        """Create IAM roles for Systems Manager automation."""
        # Create role for Systems Manager automation
        self.ssm_automation_role = iam.Role(
            self,
            "SSMAutomationRole",
            role_name=f"ResourceGroupAutomationRole-{self.environment_name}",
            assumed_by=iam.ServicePrincipal("ssm.amazonaws.com"),
            description="Role for Systems Manager automation on resource groups",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMAutomationRole"),
                iam.ManagedPolicy.from_aws_managed_policy_name("ResourceGroupsandTagEditorReadOnlyAccess"),
            ],
            inline_policies={
                "ResourceGroupManagement": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "resource-groups:GetGroup",
                                "resource-groups:ListGroupResources",
                                "resourcegroupstaggingapi:GetResources",
                                "resourcegroupstaggingapi:TagResources",
                                "resourcegroupstaggingapi:UntagResources",
                                "tag:GetResources",
                                "tag:TagResources",
                                "tag:UntagResources",
                            ],
                            resources=["*"],
                            conditions={
                                "StringEquals": {
                                    "aws:RequestedRegion": self.region
                                }
                            }
                        )
                    ]
                )
            }
        )

        # Create role for EventBridge automation
        self.eventbridge_role = iam.Role(
            self,
            "EventBridgeAutomationRole",
            assumed_by=iam.ServicePrincipal("events.amazonaws.com"),
            description="Role for EventBridge to trigger Systems Manager automation",
            inline_policies={
                "SSMAutomationExecution": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "ssm:StartAutomationExecution",
                            ],
                            resources=[
                                f"arn:aws:ssm:{self.region}:{self.account}:automation-definition/*"
                            ]
                        )
                    ]
                )
            }
        )

    def _create_ssm_automation(self) -> None:
        """Create Systems Manager automation documents."""
        # Resource group maintenance automation document
        self.maintenance_document = ssm.CfnDocument(
            self,
            "ResourceGroupMaintenanceDoc",
            document_type="Automation",
            document_format="YAML",
            name=f"ResourceGroupMaintenance-{self.environment_name}",
            content={
                "schemaVersion": "0.3",
                "description": "Automated maintenance for resource group",
                "assumeRole": self.ssm_automation_role.role_arn,
                "parameters": {
                    "ResourceGroupName": {
                        "type": "String",
                        "description": "Name of the resource group to process"
                    }
                },
                "mainSteps": [
                    {
                        "name": "GetResourceGroupResources",
                        "action": "aws:executeAwsApi",
                        "description": "Retrieve resources from the resource group",
                        "inputs": {
                            "Service": "resource-groups",
                            "Api": "ListGroupResources",
                            "GroupName": "{{ ResourceGroupName }}"
                        },
                        "outputs": [
                            {
                                "Name": "ResourceCount",
                                "Selector": "$.ResourceIdentifiers | length",
                                "Type": "Integer"
                            }
                        ]
                    },
                    {
                        "name": "LogResourceGroupInfo",
                        "action": "aws:executeAwsApi",
                        "description": "Log resource group information",
                        "inputs": {
                            "Service": "logs",
                            "Api": "PutLogEvents",
                            "logGroupName": f"/aws/ssm/resource-group-automation",
                            "logStreamName": "resource-group-maintenance-{{ automation:EXECUTION_ID }}",
                            "logEvents": [
                                {
                                    "timestamp": "{{ global:DATE_TIME }}",
                                    "message": "Processed resource group {{ ResourceGroupName }} with {{ GetResourceGroupResources.ResourceCount }} resources"
                                }
                            ]
                        }
                    }
                ]
            }
        )

        # Automated resource tagging document
        self.tagging_document = ssm.CfnDocument(
            self,
            "AutomatedResourceTaggingDoc",
            document_type="Automation",
            document_format="YAML",
            name=f"AutomatedResourceTagging-{self.environment_name}",
            content={
                "schemaVersion": "0.3",
                "description": "Automated resource tagging for resource groups",
                "assumeRole": self.ssm_automation_role.role_arn,
                "parameters": {
                    "ResourceArn": {
                        "type": "String",
                        "description": "ARN of the resource to tag"
                    },
                    "TagKey": {
                        "type": "String",
                        "description": "Tag key to apply"
                    },
                    "TagValue": {
                        "type": "String",
                        "description": "Tag value to apply"
                    }
                },
                "mainSteps": [
                    {
                        "name": "TagResource",
                        "action": "aws:executeAwsApi",
                        "description": "Apply tags to the specified resource",
                        "inputs": {
                            "Service": "resourcegroupstaggingapi",
                            "Api": "TagResources",
                            "ResourceARNList": ["{{ ResourceArn }}"],
                            "Tags": {
                                "{{ TagKey }}": "{{ TagValue }}"
                            }
                        }
                    }
                ]
            }
        )

        # Create CloudWatch Log Group for automation logging
        self.automation_log_group = logs.LogGroup(
            self,
            "AutomationLogGroup",
            log_group_name="/aws/ssm/resource-group-automation",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )

    def _create_cloudwatch_monitoring(self) -> None:
        """Create CloudWatch monitoring infrastructure."""
        # Create custom CloudWatch dashboard
        self.dashboard = cloudwatch.Dashboard(
            self,
            "ResourceGroupDashboard",
            dashboard_name=f"resource-group-{self.environment_name}-dashboard",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="EC2 CPU Utilization",
                        width=12,
                        height=6,
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/EC2",
                                metric_name="CPUUtilization",
                                statistic="Average",
                                period=Duration.minutes(5),
                            )
                        ],
                        left_y_axis=cloudwatch.YAxisProps(
                            min=0,
                            max=100,
                            label="Percentage"
                        )
                    )
                ],
                [
                    cloudwatch.GraphWidget(
                        title="RDS CPU Utilization",
                        width=12,
                        height=6,
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/RDS",
                                metric_name="CPUUtilization",
                                statistic="Average",
                                period=Duration.minutes(5),
                            )
                        ],
                        left_y_axis=cloudwatch.YAxisProps(
                            min=0,
                            max=100,
                            label="Percentage"
                        )
                    )
                ],
                [
                    cloudwatch.SingleValueWidget(
                        title="Estimated Monthly Charges",
                        width=12,
                        height=6,
                        metrics=[
                            cloudwatch.Metric(
                                namespace="AWS/Billing",
                                metric_name="EstimatedCharges",
                                dimensions_map={"Currency": "USD"},
                                statistic="Maximum",
                                period=Duration.days(1),
                                region="us-east-1"  # Billing metrics only available in us-east-1
                            )
                        ]
                    )
                ]
            ]
        )

        # Create CloudWatch alarms
        self.high_cpu_alarm = cloudwatch.Alarm(
            self,
            "ResourceGroupHighCPUAlarm",
            alarm_name=f"ResourceGroup-HighCPU-{self.environment_name}",
            alarm_description="High CPU usage across resource group",
            metric=cloudwatch.Metric(
                namespace="AWS/EC2",
                metric_name="CPUUtilization",
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=80,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Add SNS action to alarm
        self.high_cpu_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.sns_topic)
        )

        self.health_check_alarm = cloudwatch.Alarm(
            self,
            "ResourceGroupHealthCheckAlarm",
            alarm_name=f"ResourceGroup-HealthCheck-{self.environment_name}",
            alarm_description="Overall health monitoring for resource group",
            metric=cloudwatch.Metric(
                namespace="AWS/EC2",
                metric_name="StatusCheckFailed",
                statistic="Maximum",
                period=Duration.minutes(5),
            ),
            threshold=0,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Add SNS action to health check alarm
        self.health_check_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.sns_topic)
        )

    def _create_cost_monitoring(self) -> None:
        """Create cost monitoring and budget alerts."""
        # Create budget for resource group
        self.budget = budgets.CfnBudget(
            self,
            "ResourceGroupBudget",
            budget={
                "budgetName": f"ResourceGroup-Budget-{self.environment_name}",
                "budgetLimit": {
                    "amount": self.monthly_budget_limit,
                    "unit": "USD"
                },
                "timeUnit": "MONTHLY",
                "budgetType": "COST",
                "costFilters": {
                    "TagKey": ["Environment", "Application"],
                    "TagValue": [self.environment_name, self.application_name]
                }
            },
            notifications_with_subscribers=[
                {
                    "notification": {
                        "notificationType": "ACTUAL",
                        "comparisonOperator": "GREATER_THAN",
                        "threshold": 80,
                        "thresholdType": "PERCENTAGE"
                    },
                    "subscribers": [
                        {
                            "subscriptionType": "SNS",
                            "address": self.sns_topic_arn
                        }
                    ]
                }
            ]
        )

        # Create cost anomaly detection
        self.anomaly_detector = ce.CfnAnomalyDetector(
            self,
            "ResourceGroupAnomalyDetector",
            detector_name=f"ResourceGroupAnomalyDetector-{self.environment_name}",
            monitor_type="DIMENSIONAL",
            dimension_key="SERVICE",
            monitor_specification={
                "dimensionKey": "SERVICE",
                "matchOptions": ["EQUALS"],
                "values": ["AmazonEC2-Instance", "AmazonRDS", "AmazonS3"]
            }
        )

    def _create_event_automation(self) -> None:
        """Create EventBridge rules for automated resource tagging."""
        # Create EventBridge rule for automated tagging on resource creation
        self.auto_tag_rule = events.Rule(
            self,
            "AutoTagNewResourcesRule",
            rule_name=f"AutoTagNewResources-{self.environment_name}",
            description="Automatically tag new resources for resource group inclusion",
            event_pattern=events.EventPattern(
                source=["aws.ec2", "aws.s3", "aws.rds"],
                detail_type=["AWS API Call via CloudTrail"],
                detail={
                    "eventSource": ["ec2.amazonaws.com", "s3.amazonaws.com", "rds.amazonaws.com"],
                    "eventName": ["RunInstances", "CreateBucket", "CreateDBInstance"]
                }
            ),
            enabled=True
        )

        # Add target to trigger Systems Manager automation
        self.auto_tag_rule.add_target(
            targets.SsmDocument(
                document=self.tagging_document,
                input=events.RuleTargetInput.from_object({
                    "ResourceArn": "$.detail.responseElements.instancesSet.items[0].instanceId",
                    "TagKey": "AutoTagged",
                    "TagValue": "true"
                }),
                role=self.eventbridge_role
            )
        )

    def _apply_cdk_nag_suppressions(self) -> None:
        """Apply CDK Nag suppressions for legitimate security exceptions."""
        # Suppress wildcard resource warnings for resource group operations
        NagSuppressions.add_resource_suppressions(
            self.ssm_automation_role,
            [
                {
                    "id": "AwsSolutions-IAM5",
                    "reason": "Wildcard permissions required for resource group operations across multiple resource types and regions. Scoped by condition to current region."
                }
            ]
        )

        # Suppress SNS encryption warning for demonstration purposes
        NagSuppressions.add_resource_suppressions(
            self.sns_topic,
            [
                {
                    "id": "AwsSolutions-SNS2",
                    "reason": "Using AWS managed KMS key for encryption. Custom KMS key can be provided in production environments."
                }
            ]
        )

        # Suppress CloudWatch Logs encryption warning
        NagSuppressions.add_resource_suppressions(
            self.automation_log_group,
            [
                {
                    "id": "AwsSolutions-CWL1",
                    "reason": "CloudWatch Logs encryption not required for automation logging in development environment. Enable in production."
                }
            ]
        )


class ResourceGroupManagementApp(App):
    """CDK Application for Resource Group Automated Management."""

    def __init__(self):
        super().__init__()

        # Get configuration from environment variables or use defaults
        environment_name = os.environ.get("ENVIRONMENT_NAME", "production")
        application_name = os.environ.get("APPLICATION_NAME", "web-app")
        notification_email = os.environ.get("NOTIFICATION_EMAIL")
        monthly_budget_limit = float(os.environ.get("MONTHLY_BUDGET_LIMIT", "100.0"))
        aws_account = os.environ.get("CDK_DEFAULT_ACCOUNT")
        aws_region = os.environ.get("CDK_DEFAULT_REGION", "us-east-1")

        # Create the main stack
        stack = ResourceGroupAutomatedManagementStack(
            self,
            f"ResourceGroupManagement-{environment_name}",
            environment_name=environment_name,
            application_name=application_name,
            notification_email=notification_email,
            monthly_budget_limit=monthly_budget_limit,
            env=cdk.Environment(account=aws_account, region=aws_region),
            description=f"Resource Group Automated Management Stack for {environment_name} environment"
        )

        # Apply CDK Nag to the entire app for security best practices
        AwsSolutionsChecks(reports=True, verbose=True)

        # Add stack-level tags
        Tags.of(stack).add("Project", "ResourceGroupManagement")
        Tags.of(stack).add("Environment", environment_name)
        Tags.of(stack).add("ManagedBy", "CDK")


# Create the CDK application
app = ResourceGroupManagementApp()
app.synth()