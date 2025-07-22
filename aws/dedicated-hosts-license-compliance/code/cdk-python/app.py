#!/usr/bin/env python3
"""
CDK Python Application for Dedicated Hosts License Compliance

This application deploys a comprehensive solution for managing software license
compliance using AWS EC2 Dedicated Hosts, License Manager, and Config.
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    RemovalPolicy,
    Duration,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_s3 as s3,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
    aws_config as config,
    aws_ssm as ssm,
    aws_lambda as lambda_,
    aws_events as events,
    aws_events_targets as targets,
    aws_licensemanager as license_manager,
)
from constructs import Construct


class DedicatedHostsLicenseComplianceStack(Stack):
    """
    Stack for implementing dedicated hosts license compliance solution.
    
    This stack creates:
    - EC2 Dedicated Hosts for BYOL workloads
    - AWS License Manager configurations
    - AWS Config rules for compliance monitoring
    - CloudWatch alarms and dashboards
    - Systems Manager inventory collection
    - Automated compliance reporting
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        environment_name: str = "production",
        license_compliance_prefix: Optional[str] = None,
        notification_email: Optional[str] = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Set default values
        self.environment_name = environment_name
        self.license_compliance_prefix = license_compliance_prefix or f"license-compliance-{environment_name}"
        self.notification_email = notification_email

        # Create core infrastructure
        self._create_notification_topic()
        self._create_s3_buckets()
        self._create_iam_roles()
        self._create_license_configurations()
        self._create_dedicated_hosts()
        self._create_launch_templates()
        self._create_config_service()
        self._create_cloudwatch_monitoring()
        self._create_systems_manager_inventory()
        self._create_compliance_automation()

        # Create outputs
        self._create_outputs()

    def _create_notification_topic(self) -> None:
        """Create SNS topic for compliance notifications."""
        self.compliance_topic = sns.Topic(
            self, "ComplianceTopic",
            topic_name=f"{self.license_compliance_prefix}-compliance-alerts",
            display_name="License Compliance Alerts",
        )

        # Add email subscription if provided
        if self.notification_email:
            sns.Subscription(
                self, "EmailSubscription",
                topic=self.compliance_topic,
                endpoint=self.notification_email,
                protocol=sns.SubscriptionProtocol.EMAIL,
            )

    def _create_s3_buckets(self) -> None:
        """Create S3 buckets for reports and Config delivery."""
        # Bucket for License Manager reports
        self.reports_bucket = s3.Bucket(
            self, "ReportsBucket",
            bucket_name=f"{self.license_compliance_prefix}-reports-{self.account}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Bucket for Config delivery
        self.config_bucket = s3.Bucket(
            self, "ConfigBucket",
            bucket_name=f"{self.license_compliance_prefix}-config-{self.account}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Grant License Manager access to reports bucket
        self.reports_bucket.add_to_resource_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("license-manager.amazonaws.com")],
                actions=[
                    "s3:GetBucketLocation",
                    "s3:ListBucket",
                    "s3:PutObject",
                    "s3:GetObject",
                ],
                resources=[
                    self.reports_bucket.bucket_arn,
                    f"{self.reports_bucket.bucket_arn}/*",
                ],
            )
        )

    def _create_iam_roles(self) -> None:
        """Create IAM roles for various services."""
        # Config service role
        self.config_role = iam.Role(
            self, "ConfigRole",
            role_name=f"{self.license_compliance_prefix}-config-role",
            assumed_by=iam.ServicePrincipal("config.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/ConfigRole")
            ],
        )

        # Lambda execution role for compliance reporting
        self.lambda_role = iam.Role(
            self, "LambdaRole",
            role_name=f"{self.license_compliance_prefix}-lambda-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Add additional permissions for Lambda
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "license-manager:List*",
                    "license-manager:Get*",
                    "ec2:DescribeHosts",
                    "ec2:DescribeInstances",
                    "sns:Publish",
                ],
                resources=["*"],
            )
        )

        # EC2 instance role for Systems Manager
        self.ec2_role = iam.Role(
            self, "EC2Role",
            role_name=f"{self.license_compliance_prefix}-ec2-role",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore")
            ],
        )

        # Instance profile for EC2 instances
        self.instance_profile = iam.InstanceProfile(
            self, "InstanceProfile",
            instance_profile_name=f"{self.license_compliance_prefix}-instance-profile",
            role=self.ec2_role,
        )

    def _create_license_configurations(self) -> None:
        """Create License Manager configurations."""
        # Windows Server license configuration
        self.windows_license_config = license_manager.CfnLicenseConfiguration(
            self, "WindowsLicenseConfig",
            name=f"{self.license_compliance_prefix}-windows-server",
            license_counting_type="Socket",
            license_count=10,
            license_count_hard_limit=True,
            description="Windows Server BYOL license tracking",
            tags=[
                cdk.CfnTag(key="Purpose", value="WindowsServer"),
                cdk.CfnTag(key="Environment", value=self.environment_name),
            ],
        )

        # Oracle Enterprise Edition license configuration
        self.oracle_license_config = license_manager.CfnLicenseConfiguration(
            self, "OracleLicenseConfig",
            name=f"{self.license_compliance_prefix}-oracle-enterprise",
            license_counting_type="Core",
            license_count=16,
            license_count_hard_limit=True,
            description="Oracle Enterprise Edition BYOL license tracking",
            tags=[
                cdk.CfnTag(key="Purpose", value="OracleDB"),
                cdk.CfnTag(key="Environment", value=self.environment_name),
            ],
        )

    def _create_dedicated_hosts(self) -> None:
        """Create EC2 Dedicated Hosts."""
        # Get availability zones
        azs = self.availability_zones[:2]  # Use first two AZs

        # Windows/SQL Server Dedicated Host (m5 family)
        self.windows_host = ec2.CfnHost(
            self, "WindowsHost",
            instance_family="m5",
            availability_zone=azs[0],
            auto_placement="off",
            host_recovery="on",
            tags=[
                cdk.CfnTag(key="LicenseCompliance", value="BYOL-Production"),
                cdk.CfnTag(key="LicenseType", value="WindowsServer"),
                cdk.CfnTag(key="Purpose", value="SQLServer"),
                cdk.CfnTag(key="Name", value=f"{self.license_compliance_prefix}-windows-host"),
            ],
        )

        # Oracle Database Dedicated Host (r5 family)
        self.oracle_host = ec2.CfnHost(
            self, "OracleHost",
            instance_family="r5",
            availability_zone=azs[1],
            auto_placement="off",
            host_recovery="on",
            tags=[
                cdk.CfnTag(key="LicenseCompliance", value="BYOL-Production"),
                cdk.CfnTag(key="LicenseType", value="Oracle"),
                cdk.CfnTag(key="Purpose", value="Database"),
                cdk.CfnTag(key="Name", value=f"{self.license_compliance_prefix}-oracle-host"),
            ],
        )

    def _create_launch_templates(self) -> None:
        """Create launch templates for BYOL instances."""
        # Get default VPC for simplicity (in production, use a custom VPC)
        vpc = ec2.Vpc.from_lookup(self, "DefaultVPC", is_default=True)
        
        # Get latest Windows Server AMI
        windows_ami = ec2.MachineImage.latest_windows(
            ec2.WindowsVersion.WINDOWS_SERVER_2019_ENGLISH_FULL_BASE
        )

        # Get latest Amazon Linux AMI (as Oracle placeholder)
        linux_ami = ec2.MachineImage.latest_amazon_linux2()

        # Security group for instances
        security_group = ec2.SecurityGroup(
            self, "InstanceSecurityGroup",
            vpc=vpc,
            description="Security group for BYOL instances",
            allow_all_outbound=True,
        )

        # Add RDP access for Windows instances
        security_group.add_ingress_rule(
            ec2.Peer.ipv4("10.0.0.0/8"),
            ec2.Port.tcp(3389),
            "RDP access from private networks",
        )

        # Add SSH access for Linux instances
        security_group.add_ingress_rule(
            ec2.Peer.ipv4("10.0.0.0/8"),
            ec2.Port.tcp(22),
            "SSH access from private networks",
        )

        # Windows Server with SQL Server launch template
        self.windows_launch_template = ec2.LaunchTemplate(
            self, "WindowsLaunchTemplate",
            launch_template_name=f"{self.license_compliance_prefix}-windows-sql",
            machine_image=windows_ami,
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.M5, ec2.InstanceSize.LARGE
            ),
            security_group=security_group,
            role=self.ec2_role,
            user_data=ec2.UserData.for_windows(),
            require_imdsv2=True,
        )

        # Oracle Database launch template
        self.oracle_launch_template = ec2.LaunchTemplate(
            self, "OracleLaunchTemplate",
            launch_template_name=f"{self.license_compliance_prefix}-oracle-db",
            machine_image=linux_ami,
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.R5, ec2.InstanceSize.XLARGE
            ),
            security_group=security_group,
            role=self.ec2_role,
            require_imdsv2=True,
        )

    def _create_config_service(self) -> None:
        """Set up AWS Config for compliance monitoring."""
        # Configuration recorder
        config_recorder = config.CfnConfigurationRecorder(
            self, "ConfigRecorder",
            name=f"{self.license_compliance_prefix}-recorder",
            role_arn=self.config_role.role_arn,
            recording_group=config.CfnConfigurationRecorder.RecordingGroupProperty(
                all_supported=False,
                include_global_resource_types=False,
                resource_types=["AWS::EC2::Host", "AWS::EC2::Instance"],
            ),
        )

        # Delivery channel
        config_delivery_channel = config.CfnDeliveryChannel(
            self, "ConfigDeliveryChannel",
            name=f"{self.license_compliance_prefix}-delivery-channel",
            s3_bucket_name=self.config_bucket.bucket_name,
            config_snapshot_delivery_properties=config.CfnDeliveryChannel.ConfigSnapshotDeliveryPropertiesProperty(
                delivery_frequency="TwentyFour_Hours"
            ),
        )

        # Config rule for Dedicated Host compliance
        config_rule = config.CfnConfigRule(
            self, "HostComplianceRule",
            config_rule_name=f"{self.license_compliance_prefix}-host-compliance",
            description="Checks if EC2 instances are running on properly configured Dedicated Hosts",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS",
                source_identifier="EC2_DEDICATED_HOST_COMPLIANCE",
            ),
            scope=config.CfnConfigRule.ScopeProperty(
                compliance_resource_types=["AWS::EC2::Instance"]
            ),
        )

        # Dependencies
        config_rule.add_dependency(config_recorder)
        config_delivery_channel.add_dependency(config_recorder)

    def _create_cloudwatch_monitoring(self) -> None:
        """Create CloudWatch alarms and dashboard."""
        # License utilization alarm for Windows
        windows_alarm = cloudwatch.Alarm(
            self, "WindowsLicenseUtilizationAlarm",
            alarm_name=f"{self.license_compliance_prefix}-windows-license-utilization",
            alarm_description="Monitor Windows Server license utilization threshold",
            metric=cloudwatch.Metric(
                namespace="AWS/LicenseManager",
                metric_name="LicenseUtilization",
                dimensions_map={
                    "LicenseConfigurationArn": self.windows_license_config.attr_license_configuration_arn
                },
                statistic="Average",
                period=Duration.hours(1),
            ),
            threshold=80,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=1,
        )

        # Add SNS action to alarm
        windows_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.compliance_topic)
        )

        # License utilization alarm for Oracle
        oracle_alarm = cloudwatch.Alarm(
            self, "OracleLicenseUtilizationAlarm",
            alarm_name=f"{self.license_compliance_prefix}-oracle-license-utilization",
            alarm_description="Monitor Oracle license utilization threshold",
            metric=cloudwatch.Metric(
                namespace="AWS/LicenseManager",
                metric_name="LicenseUtilization",
                dimensions_map={
                    "LicenseConfigurationArn": self.oracle_license_config.attr_license_configuration_arn
                },
                statistic="Average",
                period=Duration.hours(1),
            ),
            threshold=80,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=1,
        )

        oracle_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.compliance_topic)
        )

        # CloudWatch Dashboard
        self.dashboard = cloudwatch.Dashboard(
            self, "ComplianceDashboard",
            dashboard_name=f"{self.license_compliance_prefix}-compliance-dashboard",
        )

        # Add widgets to dashboard
        self.dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="License Utilization",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/LicenseManager",
                        metric_name="LicenseUtilization",
                        dimensions_map={
                            "LicenseConfigurationArn": self.windows_license_config.attr_license_configuration_arn
                        },
                        label="Windows Server Licenses",
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/LicenseManager",
                        metric_name="LicenseUtilization",
                        dimensions_map={
                            "LicenseConfigurationArn": self.oracle_license_config.attr_license_configuration_arn
                        },
                        label="Oracle Licenses",
                    ),
                ],
                period=Duration.hours(1),
            )
        )

    def _create_systems_manager_inventory(self) -> None:
        """Set up Systems Manager inventory collection."""
        # SSM association for inventory collection
        inventory_association = ssm.CfnAssociation(
            self, "InventoryAssociation",
            name="AWS-GatherSoftwareInventory",
            targets=[
                ssm.CfnAssociation.TargetProperty(
                    key="tag:BYOLCompliance",
                    values=["true"],
                )
            ],
            schedule_expression="rate(1 day)",
            parameters={
                "applications": ["Enabled"],
                "awsComponents": ["Enabled"],
                "customInventory": ["Enabled"],
                "files": ["Enabled"],
                "networkConfig": ["Enabled"],
                "services": ["Enabled"],
                "windowsRegistry": ["Enabled"],
                "windowsRoles": ["Enabled"],
                "windowsUpdates": ["Enabled"],
            },
        )

        # Custom document for license inventory
        license_inventory_document = ssm.CfnDocument(
            self, "LicenseInventoryDocument",
            name=f"{self.license_compliance_prefix}-license-inventory",
            document_type="Command",
            content={
                "schemaVersion": "2.2",
                "description": "Collect license information from BYOL instances",
                "mainSteps": [
                    {
                        "action": "aws:runPowerShellScript",
                        "name": "CollectLicenseInfo",
                        "inputs": {
                            "runCommand": [
                                "Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion, TotalPhysicalMemory | ConvertTo-Json",
                                'Get-Service | Where-Object {$_.Name -like "*SQL*"} | Select-Object Name, Status | ConvertTo-Json',
                            ]
                        },
                    }
                ],
            },
        )

    def _create_compliance_automation(self) -> None:
        """Create Lambda function for automated compliance reporting."""
        # Lambda function code
        compliance_function_code = """
import json
import boto3
import os
from datetime import datetime, timedelta

def lambda_handler(event, context):
    license_manager = boto3.client('license-manager')
    ec2 = boto3.client('ec2')
    sns = boto3.client('sns')
    
    # Get license configurations
    license_configs = license_manager.list_license_configurations()
    
    compliance_report = {
        'report_date': datetime.now().isoformat(),
        'license_utilization': []
    }
    
    for config in license_configs['LicenseConfigurations']:
        try:
            usage = license_manager.list_usage_for_license_configuration(
                LicenseConfigurationArn=config['LicenseConfigurationArn']
            )
            
            compliance_report['license_utilization'].append({
                'license_name': config['Name'],
                'license_count': config['LicenseCount'],
                'consumed_licenses': len(usage['LicenseConfigurationUsageList']),
                'utilization_percentage': (len(usage['LicenseConfigurationUsageList']) / config['LicenseCount']) * 100 if config['LicenseCount'] > 0 else 0
            })
        except Exception as e:
            print(f"Error processing license config {config['Name']}: {str(e)}")
    
    # Send compliance report via SNS
    try:
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=json.dumps(compliance_report, indent=2),
            Subject='Weekly License Compliance Report'
        )
    except Exception as e:
        print(f"Error sending SNS notification: {str(e)}")
    
    return {
        'statusCode': 200,
        'body': json.dumps('Compliance report generated successfully')
    }
"""

        # Create Lambda function
        self.compliance_function = lambda_.Function(
            self, "ComplianceFunction",
            function_name=f"{self.license_compliance_prefix}-compliance-report",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(compliance_function_code),
            role=self.lambda_role,
            timeout=Duration.seconds(60),
            environment={
                "SNS_TOPIC_ARN": self.compliance_topic.topic_arn,
            },
        )

        # Grant SNS publish permission
        self.compliance_topic.grant_publish(self.compliance_function)

        # Create EventBridge rule for weekly execution
        weekly_rule = events.Rule(
            self, "WeeklyComplianceRule",
            rule_name=f"{self.license_compliance_prefix}-weekly-compliance",
            description="Trigger weekly compliance report generation",
            schedule=events.Schedule.cron(
                minute="0",
                hour="9",
                week_day="MON",
            ),
        )

        # Add Lambda target to rule
        weekly_rule.add_target(targets.LambdaFunction(self.compliance_function))

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        CfnOutput(
            self, "WindowsHostId",
            description="Windows/SQL Server Dedicated Host ID",
            value=self.windows_host.attr_host_id,
        )

        CfnOutput(
            self, "OracleHostId",
            description="Oracle Database Dedicated Host ID",
            value=self.oracle_host.attr_host_id,
        )

        CfnOutput(
            self, "WindowsLicenseConfigurationArn",
            description="Windows Server License Configuration ARN",
            value=self.windows_license_config.attr_license_configuration_arn,
        )

        CfnOutput(
            self, "OracleLicenseConfigurationArn",
            description="Oracle License Configuration ARN",
            value=self.oracle_license_config.attr_license_configuration_arn,
        )

        CfnOutput(
            self, "ComplianceTopicArn",
            description="SNS Topic ARN for compliance notifications",
            value=self.compliance_topic.topic_arn,
        )

        CfnOutput(
            self, "ReportsBucketName",
            description="S3 Bucket for License Manager reports",
            value=self.reports_bucket.bucket_name,
        )

        CfnOutput(
            self, "DashboardUrl",
            description="CloudWatch Dashboard URL",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
        )

        CfnOutput(
            self, "WindowsLaunchTemplateId",
            description="Windows Server Launch Template ID",
            value=self.windows_launch_template.launch_template_id,
        )

        CfnOutput(
            self, "OracleLaunchTemplateId",
            description="Oracle Database Launch Template ID",
            value=self.oracle_launch_template.launch_template_id,
        )


def main() -> None:
    """Main application entry point."""
    app = cdk.App()

    # Get context values or use defaults
    environment_name = app.node.try_get_context("environment_name") or "production"
    notification_email = app.node.try_get_context("notification_email")
    license_compliance_prefix = app.node.try_get_context("license_compliance_prefix")

    # Create the stack
    DedicatedHostsLicenseComplianceStack(
        app,
        "DedicatedHostsLicenseComplianceStack",
        environment_name=environment_name,
        notification_email=notification_email,
        license_compliance_prefix=license_compliance_prefix,
        description="Dedicated Hosts License Compliance Infrastructure",
        env=cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION"),
        ),
    )

    app.synth()


if __name__ == "__main__":
    main()