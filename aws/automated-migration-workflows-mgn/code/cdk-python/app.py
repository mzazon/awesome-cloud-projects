#!/usr/bin/env python3
"""
CDK Python Application for Automated Application Migration Workflows
with AWS Application Migration Service and Migration Hub Orchestrator

This application deploys the infrastructure needed for automated application
migration workflows using AWS Application Migration Service (MGN) and 
Migration Hub Orchestrator.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_ssm as ssm,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    aws_mgn as mgn,
    CfnOutput,
    Tags,
)
from constructs import Construct


class MigrationInfrastructureStack(Stack):
    """
    Stack for creating the core migration infrastructure including VPC,
    security groups, and MGN configuration.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        project_name: str,
        **kwargs: Any
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.project_name = project_name
        
        # Create VPC for migration targets
        self.vpc = self._create_vpc()
        
        # Create security groups
        self.migration_sg = self._create_security_groups()
        
        # Create IAM roles
        self.mgn_service_role = self._create_mgn_service_role()
        self.automation_role = self._create_automation_role()
        
        # Create CloudWatch Log Group for migration activities
        self.log_group = self._create_log_group()
        
        # Create MGN replication configuration template
        self._create_mgn_replication_template()
        
        # Add outputs
        self._add_outputs()
        
        # Add tags to all resources
        self._add_tags()

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC with public and private subnets for migration targets."""
        vpc = ec2.Vpc(
            self,
            "MigrationVPC",
            vpc_name=f"{self.project_name}-vpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                ),
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )
        
        # Add VPC Flow Logs for security monitoring
        vpc.add_flow_log(
            "MigrationVPCFlowLog",
            destination=ec2.FlowLogDestination.to_cloud_watch_logs(
                self.log_group
            ),
            traffic_type=ec2.FlowLogTrafficType.ALL,
        )
        
        return vpc

    def _create_security_groups(self) -> ec2.SecurityGroup:
        """Create security groups for migrated instances."""
        # Security group for migrated instances
        migration_sg = ec2.SecurityGroup(
            self,
            "MigrationSecurityGroup",
            vpc=self.vpc,
            description="Security group for migrated instances",
            security_group_name=f"{self.project_name}-migration-sg",
            allow_all_outbound=True,
        )
        
        # Allow SSH access from within VPC
        migration_sg.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(22),
            description="SSH access from VPC",
        )
        
        # Allow HTTP access from internet
        migration_sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="HTTP access from internet",
        )
        
        # Allow HTTPS access from internet
        migration_sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="HTTPS access from internet",
        )
        
        # Allow MGN replication traffic (TCP 1500)
        migration_sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(1500),
            description="MGN replication traffic",
        )
        
        return migration_sg

    def _create_mgn_service_role(self) -> iam.Role:
        """Create IAM role for MGN service operations."""
        mgn_service_role = iam.Role(
            self,
            "MGNServiceRole",
            assumed_by=iam.ServicePrincipal("mgn.amazonaws.com"),
            description="Service role for AWS Application Migration Service",
            role_name=f"{self.project_name}-mgn-service-role",
        )
        
        # Attach required AWS managed policies
        mgn_service_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "AWSApplicationMigrationServiceRolePolicy"
            )
        )
        
        return mgn_service_role

    def _create_automation_role(self) -> iam.Role:
        """Create IAM role for post-migration automation."""
        automation_role = iam.Role(
            self,
            "AutomationRole",
            assumed_by=iam.ServicePrincipal("ssm.amazonaws.com"),
            description="Role for post-migration automation tasks",
            role_name=f"{self.project_name}-automation-role",
        )
        
        # Attach required AWS managed policies
        automation_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "AmazonSSMAutomationRole"
            )
        )
        
        automation_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "CloudWatchAgentServerPolicy"
            )
        )
        
        # Add custom policy for EC2 management
        automation_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ec2:DescribeInstances",
                    "ec2:DescribeInstanceStatus",
                    "ec2:StartInstances",
                    "ec2:StopInstances",
                    "ec2:RebootInstances",
                    "ec2:CreateTags",
                ],
                resources=["*"],
            )
        )
        
        return automation_role

    def _create_log_group(self) -> logs.LogGroup:
        """Create CloudWatch Log Group for migration activities."""
        log_group = logs.LogGroup(
            self,
            "MigrationLogGroup",
            log_group_name=f"/aws/migration/{self.project_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        return log_group

    def _create_mgn_replication_template(self) -> None:
        """Create MGN replication configuration template."""
        # Note: MGN replication template is created via CLI in the recipe
        # This is a placeholder for the configuration that would be applied
        replication_template = mgn.CfnReplicationConfigurationTemplate(
            self,
            "MGNReplicationTemplate",
            associate_default_security_group=False,
            bandwidth_throttling=0,
            create_public_ip=False,
            data_plane_routing="PRIVATE_IP",
            default_large_staging_disk_type="GP2",
            ebs_encryption="DEFAULT",
            pit_policy=[
                mgn.CfnReplicationConfigurationTemplate.PITPropertyProperty(
                    enabled=True,
                    interval=10,
                    retention_duration=60,
                    rule_id=1,
                    units="MINUTE",
                )
            ],
            replication_server_instance_type="t3.small",
            replication_servers_security_groups_i_ds=[
                self.migration_sg.security_group_id
            ],
            staging_area_subnet_id=self.vpc.private_subnets[0].subnet_id,
            staging_area_tags={
                "Name": f"{self.project_name}-staging-area",
                "Project": self.project_name,
            },
            use_dedicated_replication_server=False,
        )


class MigrationMonitoringStack(Stack):
    """
    Stack for creating monitoring and alerting infrastructure for migration
    activities including CloudWatch dashboards and alarms.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        project_name: str,
        vpc: ec2.Vpc,
        log_group: logs.LogGroup,
        **kwargs: Any
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.project_name = project_name
        self.vpc = vpc
        self.log_group = log_group
        
        # Create CloudWatch dashboard
        self.dashboard = self._create_dashboard()
        
        # Create CloudWatch alarms
        self._create_alarms()
        
        # Add outputs
        self._add_outputs()
        
        # Add tags to all resources
        self._add_tags()

    def _create_dashboard(self) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for migration monitoring."""
        dashboard = cloudwatch.Dashboard(
            self,
            "MigrationDashboard",
            dashboard_name=f"{self.project_name}-migration-dashboard",
        )
        
        # Add MGN metrics widget
        mgn_metrics_widget = cloudwatch.GraphWidget(
            title="MGN Migration Status",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/MGN",
                    metric_name="TotalSourceServers",
                    statistic="Average",
                    period=Duration.minutes(5),
                ),
                cloudwatch.Metric(
                    namespace="AWS/MGN",
                    metric_name="HealthySourceServers",
                    statistic="Average",
                    period=Duration.minutes(5),
                ),
            ],
            width=12,
            height=6,
        )
        
        # Add replication progress widget
        replication_widget = cloudwatch.GraphWidget(
            title="Replication Progress",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/MGN",
                    metric_name="ReplicationProgress",
                    statistic="Average",
                    period=Duration.minutes(5),
                ),
            ],
            width=12,
            height=6,
        )
        
        # Add log insights widget for errors
        log_widget = cloudwatch.LogQueryWidget(
            title="Migration Errors",
            log_groups=[self.log_group],
            query_lines=[
                "fields @timestamp, @message",
                "filter @message like /ERROR/",
                "sort @timestamp desc",
                "limit 20",
            ],
            width=24,
            height=6,
        )
        
        # Add widgets to dashboard
        dashboard.add_widgets(mgn_metrics_widget, replication_widget)
        dashboard.add_widgets(log_widget)
        
        return dashboard

    def _create_alarms(self) -> None:
        """Create CloudWatch alarms for migration monitoring."""
        # Alarm for unhealthy source servers
        cloudwatch.Alarm(
            self,
            "MGNUnhealthyServersAlarm",
            alarm_name=f"{self.project_name}-mgn-unhealthy-servers",
            alarm_description="Alert when MGN source servers become unhealthy",
            metric=cloudwatch.Metric(
                namespace="AWS/MGN",
                metric_name="HealthySourceServers",
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.BREACHING,
        )
        
        # Alarm for replication lag
        cloudwatch.Alarm(
            self,
            "MGNReplicationLagAlarm",
            alarm_name=f"{self.project_name}-mgn-replication-lag",
            alarm_description="Alert when MGN replication lag exceeds threshold",
            metric=cloudwatch.Metric(
                namespace="AWS/MGN",
                metric_name="ReplicationLag",
                statistic="Maximum",
                period=Duration.minutes(5),
            ),
            threshold=300,  # 5 minutes
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=3,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

    def _add_outputs(self) -> None:
        """Add stack outputs."""
        CfnOutput(
            self,
            "DashboardURL",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="CloudWatch Dashboard URL for migration monitoring",
        )

    def _add_tags(self) -> None:
        """Add common tags to all resources in the stack."""
        Tags.of(self).add("Project", self.project_name)
        Tags.of(self).add("Stack", "MigrationMonitoring")
        Tags.of(self).add("Environment", "Migration")


class MigrationAutomationStack(Stack):
    """
    Stack for creating Systems Manager automation documents and workflow
    templates for post-migration tasks.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        project_name: str,
        automation_role: iam.Role,
        **kwargs: Any
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.project_name = project_name
        self.automation_role = automation_role
        
        # Create Systems Manager automation document
        self.automation_document = self._create_automation_document()
        
        # Add outputs
        self._add_outputs()
        
        # Add tags to all resources
        self._add_tags()

    def _create_automation_document(self) -> ssm.CfnDocument:
        """Create Systems Manager automation document for post-migration tasks."""
        automation_content = {
            "schemaVersion": "0.3",
            "description": "Post-migration automation tasks for migrated instances",
            "assumeRole": "{{ AutomationAssumeRole }}",
            "parameters": {
                "InstanceId": {
                    "type": "String",
                    "description": "EC2 Instance ID for post-migration tasks"
                },
                "AutomationAssumeRole": {
                    "type": "String",
                    "description": "IAM role for automation execution",
                    "default": self.automation_role.role_arn
                }
            },
            "mainSteps": [
                {
                    "name": "WaitForInstanceReady",
                    "action": "aws:waitForAwsResourceProperty",
                    "description": "Wait for EC2 instance to be ready",
                    "inputs": {
                        "Service": "ec2",
                        "Api": "DescribeInstanceStatus",
                        "InstanceIds": ["{{ InstanceId }}"],
                        "PropertySelector": "$.InstanceStatuses[0].InstanceStatus.Status",
                        "DesiredValues": ["ok"]
                    },
                    "timeoutSeconds": 600
                },
                {
                    "name": "InstallCloudWatchAgent",
                    "action": "aws:runCommand",
                    "description": "Install and configure CloudWatch Agent",
                    "inputs": {
                        "DocumentName": "AWS-ConfigureAWSPackage",
                        "InstanceIds": ["{{ InstanceId }}"],
                        "Parameters": {
                            "action": "Install",
                            "name": "AmazonCloudWatchAgent"
                        }
                    }
                },
                {
                    "name": "ConfigureSystemUpdates",
                    "action": "aws:runCommand",
                    "description": "Configure system updates and security patches",
                    "inputs": {
                        "DocumentName": "AWS-RunShellScript",
                        "InstanceIds": ["{{ InstanceId }}"],
                        "Parameters": {
                            "commands": [
                                "#!/bin/bash",
                                "yum update -y",
                                "yum install -y amazon-ssm-agent",
                                "systemctl enable amazon-ssm-agent",
                                "systemctl start amazon-ssm-agent"
                            ]
                        }
                    }
                },
                {
                    "name": "ValidateServices",
                    "action": "aws:runCommand",
                    "description": "Validate critical services are running",
                    "inputs": {
                        "DocumentName": "AWS-RunShellScript",
                        "InstanceIds": ["{{ InstanceId }}"],
                        "Parameters": {
                            "commands": [
                                "#!/bin/bash",
                                "systemctl status sshd",
                                "systemctl status amazon-ssm-agent",
                                "curl -f http://localhost/health || echo 'Application health check failed'"
                            ]
                        }
                    }
                },
                {
                    "name": "TagInstance",
                    "action": "aws:createTags",
                    "description": "Tag instance as migration completed",
                    "inputs": {
                        "ResourceType": "EC2",
                        "ResourceIds": ["{{ InstanceId }}"],
                        "Tags": [
                            {
                                "Key": "MigrationStatus",
                                "Value": "Completed"
                            },
                            {
                                "Key": "MigrationProject",
                                "Value": self.project_name
                            }
                        ]
                    }
                }
            ]
        }
        
        automation_document = ssm.CfnDocument(
            self,
            "PostMigrationAutomation",
            document_type="Automation",
            document_format="JSON",
            content=automation_content,
            name=f"{self.project_name}-post-migration-automation",
        )
        
        return automation_document

    def _add_outputs(self) -> None:
        """Add stack outputs."""
        CfnOutput(
            self,
            "AutomationDocumentName",
            value=self.automation_document.name,
            description="Systems Manager automation document name",
        )
        
        CfnOutput(
            self,
            "AutomationRoleArn",
            value=self.automation_role.role_arn,
            description="IAM role ARN for automation execution",
        )

    def _add_tags(self) -> None:
        """Add common tags to all resources in the stack."""
        Tags.of(self).add("Project", self.project_name)
        Tags.of(self).add("Stack", "MigrationAutomation")
        Tags.of(self).add("Environment", "Migration")


class MigrationInfrastructureStack(Stack):
    """Main infrastructure stack that extends the base stack with outputs."""

    def _add_outputs(self) -> None:
        """Add stack outputs for integration with other stacks."""
        CfnOutput(
            self,
            "VPCId",
            value=self.vpc.vpc_id,
            description="VPC ID for migration targets",
            export_name=f"{self.project_name}-vpc-id",
        )
        
        CfnOutput(
            self,
            "PrivateSubnetIds",
            value=",".join([subnet.subnet_id for subnet in self.vpc.private_subnets]),
            description="Private subnet IDs for migration targets",
            export_name=f"{self.project_name}-private-subnet-ids",
        )
        
        CfnOutput(
            self,
            "PublicSubnetIds",
            value=",".join([subnet.subnet_id for subnet in self.vpc.public_subnets]),
            description="Public subnet IDs for migration targets",
            export_name=f"{self.project_name}-public-subnet-ids",
        )
        
        CfnOutput(
            self,
            "MigrationSecurityGroupId",
            value=self.migration_sg.security_group_id,
            description="Security group ID for migrated instances",
            export_name=f"{self.project_name}-migration-sg-id",
        )
        
        CfnOutput(
            self,
            "MGNServiceRoleArn",
            value=self.mgn_service_role.role_arn,
            description="MGN service role ARN",
            export_name=f"{self.project_name}-mgn-role-arn",
        )
        
        CfnOutput(
            self,
            "LogGroupName",
            value=self.log_group.log_group_name,
            description="CloudWatch Log Group name for migration activities",
            export_name=f"{self.project_name}-log-group-name",
        )

    def _add_tags(self) -> None:
        """Add common tags to all resources in the stack."""
        Tags.of(self).add("Project", self.project_name)
        Tags.of(self).add("Stack", "MigrationInfrastructure")
        Tags.of(self).add("Environment", "Migration")


def main() -> None:
    """Main function to create and deploy the CDK application."""
    app = cdk.App()
    
    # Get project name from context or environment variable
    project_name = app.node.try_get_context("project_name") or os.environ.get(
        "MIGRATION_PROJECT_NAME", "migration-project"
    )
    
    # Get AWS environment details
    env = cdk.Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION"),
    )
    
    # Create infrastructure stack
    infrastructure_stack = MigrationInfrastructureStack(
        app,
        f"{project_name}-infrastructure",
        project_name=project_name,
        env=env,
        description="Core infrastructure for automated application migration workflows",
    )
    
    # Create monitoring stack
    monitoring_stack = MigrationMonitoringStack(
        app,
        f"{project_name}-monitoring",
        project_name=project_name,
        vpc=infrastructure_stack.vpc,
        log_group=infrastructure_stack.log_group,
        env=env,
        description="Monitoring and alerting for migration activities",
    )
    monitoring_stack.add_dependency(infrastructure_stack)
    
    # Create automation stack
    automation_stack = MigrationAutomationStack(
        app,
        f"{project_name}-automation",
        project_name=project_name,
        automation_role=infrastructure_stack.automation_role,
        env=env,
        description="Automation workflows for post-migration tasks",
    )
    automation_stack.add_dependency(infrastructure_stack)
    
    # Add application-level tags
    Tags.of(app).add("Application", "MigrationWorkflow")
    Tags.of(app).add("CDK", "Python")
    Tags.of(app).add("GeneratedBy", "CDK-Python-Recipe")
    
    app.synth()


if __name__ == "__main__":
    main()