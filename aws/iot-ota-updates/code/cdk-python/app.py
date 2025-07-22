#!/usr/bin/env python3
"""
CDK Python Application for IoT Fleet Management and Over-the-Air Updates

This application creates the infrastructure needed for IoT fleet management
and over-the-air firmware updates using AWS IoT Core services.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_iot as iot,
    aws_s3 as s3,
    aws_s3_deployment as s3_deploy,
    aws_iam as iam,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    RemovalPolicy,
    Duration,
    CfnOutput,
    Tags,
)
from constructs import Construct


class IoTFleetManagementStack(Stack):
    """
    Stack for IoT Fleet Management and Over-the-Air Updates
    
    This stack creates:
    - S3 bucket for firmware storage
    - IoT policy for device permissions
    - IoT thing group for fleet organization
    - CloudWatch log group for monitoring
    - CloudWatch dashboard for fleet visibility
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        firmware_version: str = "v2.1.0",
        fleet_name: str = "ProductionDevices",
        environment: str = "production",
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration
        self.firmware_version = firmware_version
        self.fleet_name = fleet_name
        self.environment = environment

        # Create S3 bucket for firmware storage
        self.firmware_bucket = self._create_firmware_bucket()

        # Create IoT policy for device permissions
        self.device_policy = self._create_device_policy()

        # Create thing group for fleet organization
        self.thing_group = self._create_thing_group()

        # Create CloudWatch log group for monitoring
        self.log_group = self._create_log_group()

        # Create CloudWatch dashboard for fleet visibility
        self.dashboard = self._create_dashboard()

        # Deploy sample firmware file
        self._deploy_sample_firmware()

        # Create stack outputs
        self._create_outputs()

        # Add tags to all resources
        self._add_tags()

    def _create_firmware_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for storing firmware files with versioning and lifecycle policies
        """
        bucket = s3.Bucket(
            self,
            "FirmwareBucket",
            bucket_name=f"iot-firmware-updates-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="FirmwareLifecycle",
                    enabled=True,
                    noncurrent_version_expiration=Duration.days(90),
                    abort_incomplete_multipart_upload_after=Duration.days(1),
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Add bucket policy to allow IoT service access
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("iot.amazonaws.com")],
                actions=["s3:GetObject"],
                resources=[bucket.arn_for_objects("firmware/*")],
                conditions={
                    "StringEquals": {
                        "s3:ExistingObjectTag/FirmwareVersion": self.firmware_version
                    }
                },
            )
        )

        return bucket

    def _create_device_policy(self) -> iot.CfnPolicy:
        """
        Create IoT policy for device fleet with job management permissions
        """
        policy_document = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": ["iot:Connect"],
                    "Resource": f"arn:aws:iot:{self.region}:{self.account}:client/${{iot:Connection.Thing.ThingName}}",
                },
                {
                    "Effect": "Allow",
                    "Action": ["iot:Publish", "iot:Subscribe", "iot:Receive"],
                    "Resource": [
                        f"arn:aws:iot:{self.region}:{self.account}:topic/$aws/things/${{iot:Connection.Thing.ThingName}}/jobs/*",
                        f"arn:aws:iot:{self.region}:{self.account}:topicfilter/$aws/things/${{iot:Connection.Thing.ThingName}}/jobs/*",
                    ],
                },
                {
                    "Effect": "Allow",
                    "Action": ["iot:GetThingShadow", "iot:UpdateThingShadow"],
                    "Resource": f"arn:aws:iot:{self.region}:{self.account}:thing/${{iot:Connection.Thing.ThingName}}",
                },
            ],
        }

        return iot.CfnPolicy(
            self,
            "DevicePolicy",
            policy_name=f"IoTDevicePolicy-{self.fleet_name}",
            policy_document=policy_document,
        )

    def _create_thing_group(self) -> iot.CfnThingGroup:
        """
        Create thing group for fleet organization with metadata
        """
        return iot.CfnThingGroup(
            self,
            "ThingGroup",
            thing_group_name=f"{self.fleet_name}-{self.region}",
            thing_group_properties=iot.CfnThingGroup.ThingGroupPropertiesProperty(
                thing_group_description=f"Production IoT devices for OTA updates - {self.environment}",
                attribute_payload=iot.CfnThingGroup.AttributePayloadProperty(
                    attributes={
                        "environment": self.environment,
                        "updatePolicy": "automatic",
                        "firmwareVersion": self.firmware_version,
                        "managedBy": "CDK",
                        "region": self.region,
                    }
                ),
            ),
        )

    def _create_log_group(self) -> logs.LogGroup:
        """
        Create CloudWatch log group for IoT job monitoring
        """
        return logs.LogGroup(
            self,
            "IoTJobLogGroup",
            log_group_name=f"/aws/iot/jobs/{self.fleet_name}",
            retention=logs.RetentionDays.TWO_WEEKS,
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _create_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for fleet monitoring
        """
        dashboard = cloudwatch.Dashboard(
            self,
            "FleetDashboard",
            dashboard_name=f"IoT-Fleet-{self.fleet_name}-{self.region}",
            period_override=cloudwatch.PeriodOverride.INHERIT,
        )

        # Add widgets for fleet monitoring
        dashboard.add_widgets(
            cloudwatch.TextWidget(
                markdown=f"""
# IoT Fleet Management Dashboard

**Fleet Name:** {self.fleet_name}
**Environment:** {self.environment}
**Firmware Version:** {self.firmware_version}
**Region:** {self.region}

This dashboard provides real-time monitoring of your IoT fleet and OTA update operations.
                """,
                width=24,
                height=6,
            )
        )

        # Add job execution metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="IoT Job Executions",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/IoT",
                        metric_name="JobExecutions",
                        dimensions_map={"JobStatus": "SUCCEEDED"},
                        statistic="Sum",
                        period=Duration.minutes(5),
                        label="Successful Jobs",
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/IoT",
                        metric_name="JobExecutions",
                        dimensions_map={"JobStatus": "FAILED"},
                        statistic="Sum",
                        period=Duration.minutes(5),
                        label="Failed Jobs",
                    ),
                ],
                width=12,
                height=6,
            ),
            cloudwatch.GraphWidget(
                title="Device Connection Status",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/IoT",
                        metric_name="NumOfConnectedDevices",
                        statistic="Average",
                        period=Duration.minutes(5),
                        label="Connected Devices",
                    )
                ],
                width=12,
                height=6,
            ),
        )

        return dashboard

    def _deploy_sample_firmware(self) -> None:
        """
        Deploy sample firmware file to S3 bucket
        """
        s3_deploy.BucketDeployment(
            self,
            "FirmwareDeployment",
            sources=[
                s3_deploy.Source.data(
                    f"firmware/firmware-{self.firmware_version}.bin",
                    f"Sample firmware package {self.firmware_version} for IoT fleet management demo",
                )
            ],
            destination_bucket=self.firmware_bucket,
            destination_key_prefix="firmware/",
            object_metadata={
                "FirmwareVersion": self.firmware_version,
                "Environment": self.environment,
                "DeployedBy": "CDK",
            },
        )

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resources
        """
        CfnOutput(
            self,
            "FirmwareBucketName",
            value=self.firmware_bucket.bucket_name,
            description="S3 bucket for firmware storage",
            export_name=f"{self.stack_name}-FirmwareBucket",
        )

        CfnOutput(
            self,
            "DevicePolicyName",
            value=self.device_policy.policy_name,
            description="IoT policy for device permissions",
            export_name=f"{self.stack_name}-DevicePolicy",
        )

        CfnOutput(
            self,
            "ThingGroupName",
            value=self.thing_group.thing_group_name,
            description="Thing group for fleet organization",
            export_name=f"{self.stack_name}-ThingGroup",
        )

        CfnOutput(
            self,
            "LogGroupName",
            value=self.log_group.log_group_name,
            description="CloudWatch log group for IoT jobs",
            export_name=f"{self.stack_name}-LogGroup",
        )

        CfnOutput(
            self,
            "DashboardURL",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="CloudWatch dashboard URL for fleet monitoring",
            export_name=f"{self.stack_name}-Dashboard",
        )

        CfnOutput(
            self,
            "SampleFirmwareURL",
            value=f"https://{self.firmware_bucket.bucket_name}.s3.{self.region}.amazonaws.com/firmware/firmware-{self.firmware_version}.bin",
            description="Sample firmware download URL",
            export_name=f"{self.stack_name}-FirmwareURL",
        )

    def _add_tags(self) -> None:
        """
        Add tags to all resources in the stack
        """
        Tags.of(self).add("Project", "IoT Fleet Management")
        Tags.of(self).add("Environment", self.environment)
        Tags.of(self).add("FirmwareVersion", self.firmware_version)
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("CostCenter", "IoT Operations")


class IoTFleetManagementApp(cdk.App):
    """
    CDK Application for IoT Fleet Management
    """

    def __init__(self) -> None:
        super().__init__()

        # Get configuration from environment variables or use defaults
        config = self._get_configuration()

        # Create the IoT Fleet Management stack
        IoTFleetManagementStack(
            self,
            "IoTFleetManagementStack",
            env=cdk.Environment(
                account=config.get("account", os.getenv("CDK_DEFAULT_ACCOUNT")),
                region=config.get("region", os.getenv("CDK_DEFAULT_REGION", "us-east-1")),
            ),
            firmware_version=config.get("firmware_version", "v2.1.0"),
            fleet_name=config.get("fleet_name", "ProductionDevices"),
            environment=config.get("environment", "production"),
            description="IoT Fleet Management and Over-the-Air Updates infrastructure",
        )

    def _get_configuration(self) -> Dict[str, Any]:
        """
        Get configuration from environment variables or context
        """
        config = {}

        # Get values from environment variables
        if firmware_version := os.getenv("FIRMWARE_VERSION"):
            config["firmware_version"] = firmware_version

        if fleet_name := os.getenv("FLEET_NAME"):
            config["fleet_name"] = fleet_name

        if environment := os.getenv("ENVIRONMENT"):
            config["environment"] = environment

        if account := os.getenv("CDK_DEFAULT_ACCOUNT"):
            config["account"] = account

        if region := os.getenv("CDK_DEFAULT_REGION"):
            config["region"] = region

        # Get values from CDK context (cdk.json)
        try:
            if firmware_version := self.node.try_get_context("firmware_version"):
                config["firmware_version"] = firmware_version

            if fleet_name := self.node.try_get_context("fleet_name"):
                config["fleet_name"] = fleet_name

            if environment := self.node.try_get_context("environment"):
                config["environment"] = environment
        except AttributeError:
            # Context not available during initialization
            pass

        return config


# Application entry point
if __name__ == "__main__":
    app = IoTFleetManagementApp()
    app.synth()