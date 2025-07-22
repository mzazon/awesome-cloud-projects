#!/usr/bin/env python3
"""
AWS CDK Python Application for IoT Device Management
Creates an IoT device management solution with device types, groups, policies, and monitoring.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_iot as iot,
    aws_logs as logs,
    aws_iam as iam,
    CfnOutput,
    RemovalPolicy,
    Duration,
)
from constructs import Construct
from typing import List, Dict, Any
import json


class IoTDeviceManagementStack(Stack):
    """
    CDK Stack for IoT Device Management solution.
    
    This stack creates:
    - IoT Thing Type for device templates
    - IoT Thing Group for device organization
    - Dynamic Thing Groups for automated categorization
    - IoT Policy for secure device access
    - Fleet Metrics for monitoring
    - CloudWatch Log Group for device logs
    - Sample IoT Things (devices)
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.stack_name = self.stack_name
        self.region = self.region
        self.account = self.account
        
        # Create IoT Thing Type
        self.thing_type = self._create_thing_type()
        
        # Create IoT Thing Group
        self.thing_group = self._create_thing_group()
        
        # Create Dynamic Thing Groups
        self.dynamic_groups = self._create_dynamic_thing_groups()
        
        # Create IoT Policy
        self.iot_policy = self._create_iot_policy()
        
        # Create CloudWatch Log Group
        self.log_group = self._create_log_group()
        
        # Create Fleet Metrics
        self.fleet_metrics = self._create_fleet_metrics()
        
        # Create sample IoT Things
        self.sample_things = self._create_sample_things()
        
        # Create outputs
        self._create_outputs()

    def _create_thing_type(self) -> iot.CfnThingType:
        """
        Create IoT Thing Type for device templates.
        
        Returns:
            iot.CfnThingType: The created thing type
        """
        thing_type = iot.CfnThingType(
            self,
            "SensorThingType",
            thing_type_name=f"sensor-type-{self.stack_name}",
            thing_type_properties=iot.CfnThingType.ThingTypePropertiesProperty(
                thing_type_description="Temperature sensor device type for fleet management",
                searchable_attributes=["location", "firmwareVersion", "manufacturer"]
            )
        )
        
        return thing_type

    def _create_thing_group(self) -> iot.CfnThingGroup:
        """
        Create IoT Thing Group for device organization.
        
        Returns:
            iot.CfnThingGroup: The created thing group
        """
        thing_group = iot.CfnThingGroup(
            self,
            "ProductionSensorsGroup",
            thing_group_name=f"production-sensors-{self.stack_name}",
            thing_group_properties=iot.CfnThingGroup.ThingGroupPropertiesProperty(
                thing_group_description="Production temperature sensors fleet",
                attribute_payload=iot.CfnThingGroup.AttributePayloadProperty(
                    attributes={
                        "Environment": "Production",
                        "Location": "Factory1",
                        "ManagedBy": "IoT-Device-Management"
                    }
                )
            )
        )
        
        return thing_group

    def _create_dynamic_thing_groups(self) -> List[iot.CfnThingGroup]:
        """
        Create Dynamic Thing Groups for automated device categorization.
        
        Returns:
            List[iot.CfnThingGroup]: List of created dynamic thing groups
        """
        dynamic_groups = []
        
        # Dynamic group for outdated firmware
        outdated_firmware_group = iot.CfnThingGroup(
            self,
            "OutdatedFirmwareGroup",
            thing_group_name=f"outdated-firmware-{self.stack_name}",
            thing_group_properties=iot.CfnThingGroup.ThingGroupPropertiesProperty(
                thing_group_description="Devices requiring firmware updates"
            ),
            query_string="attributes.firmwareVersion:1.0.0"
        )
        dynamic_groups.append(outdated_firmware_group)
        
        # Dynamic group for Building A sensors
        building_a_group = iot.CfnThingGroup(
            self,
            "BuildingASensorsGroup",
            thing_group_name=f"building-a-sensors-{self.stack_name}",
            thing_group_properties=iot.CfnThingGroup.ThingGroupPropertiesProperty(
                thing_group_description="All sensors in Building A"
            ),
            query_string="attributes.location:Building-A"
        )
        dynamic_groups.append(building_a_group)
        
        return dynamic_groups

    def _create_iot_policy(self) -> iot.CfnPolicy:
        """
        Create IoT Policy for secure device access.
        
        Returns:
            iot.CfnPolicy: The created IoT policy
        """
        # Define IoT policy document
        policy_document = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "iot:Connect",
                        "iot:Publish",
                        "iot:Subscribe",
                        "iot:Receive"
                    ],
                    "Resource": [
                        f"arn:aws:iot:{self.region}:{self.account}:client/${{iot:Connection.Thing.ThingName}}",
                        f"arn:aws:iot:{self.region}:{self.account}:topic/device/${{iot:Connection.Thing.ThingName}}/*",
                        f"arn:aws:iot:{self.region}:{self.account}:topicfilter/device/${{iot:Connection.Thing.ThingName}}/*"
                    ]
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "iot:GetThingShadow",
                        "iot:UpdateThingShadow",
                        "iot:DeleteThingShadow"
                    ],
                    "Resource": [
                        f"arn:aws:iot:{self.region}:{self.account}:thing/${{iot:Connection.Thing.ThingName}}"
                    ]
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "iot:Subscribe"
                    ],
                    "Resource": [
                        f"arn:aws:iot:{self.region}:{self.account}:topicfilter/$aws/things/${{iot:Connection.Thing.ThingName}}/jobs/*"
                    ]
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "iot:Receive"
                    ],
                    "Resource": [
                        f"arn:aws:iot:{self.region}:{self.account}:topic/$aws/things/${{iot:Connection.Thing.ThingName}}/jobs/*"
                    ]
                }
            ]
        }
        
        iot_policy = iot.CfnPolicy(
            self,
            "DevicePolicy",
            policy_name=f"device-policy-{self.stack_name}",
            policy_document=policy_document
        )
        
        return iot_policy

    def _create_log_group(self) -> logs.LogGroup:
        """
        Create CloudWatch Log Group for IoT device logs.
        
        Returns:
            logs.LogGroup: The created log group
        """
        log_group = logs.LogGroup(
            self,
            "IoTDeviceLogGroup",
            log_group_name=f"/aws/iot/device-management-{self.stack_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        return log_group

    def _create_fleet_metrics(self) -> List[iot.CfnFleetMetric]:
        """
        Create Fleet Metrics for device monitoring.
        
        Returns:
            List[iot.CfnFleetMetric]: List of created fleet metrics
        """
        fleet_metrics = []
        
        # Fleet metric for connected devices
        connected_devices_metric = iot.CfnFleetMetric(
            self,
            "ConnectedDevicesMetric",
            metric_name=f"ConnectedDevices-{self.stack_name}",
            query_string="connectivity.connected:true",
            aggregation_type=iot.CfnFleetMetric.AggregationTypeProperty(
                name="Statistics",
                values=["count"]
            ),
            period=300,
            aggregation_field="connectivity.connected",
            description="Count of connected devices in fleet"
        )
        fleet_metrics.append(connected_devices_metric)
        
        # Fleet metric for firmware versions
        firmware_versions_metric = iot.CfnFleetMetric(
            self,
            "FirmwareVersionsMetric",
            metric_name=f"FirmwareVersions-{self.stack_name}",
            query_string="attributes.firmwareVersion:*",
            aggregation_type=iot.CfnFleetMetric.AggregationTypeProperty(
                name="Statistics",
                values=["count"]
            ),
            period=300,
            aggregation_field="attributes.firmwareVersion",
            description="Distribution of firmware versions across fleet"
        )
        fleet_metrics.append(firmware_versions_metric)
        
        return fleet_metrics

    def _create_sample_things(self) -> List[iot.CfnThing]:
        """
        Create sample IoT Things for demonstration.
        
        Returns:
            List[iot.CfnThing]: List of created IoT things
        """
        sample_things = []
        
        # Define sample devices
        devices = [
            {"name": "temp-sensor-01", "location": "Building-A", "firmware": "1.0.0"},
            {"name": "temp-sensor-02", "location": "Building-B", "firmware": "1.0.0"},
            {"name": "temp-sensor-03", "location": "Building-C", "firmware": "1.1.0"},
            {"name": "temp-sensor-04", "location": "Building-D", "firmware": "1.0.0"}
        ]
        
        for device in devices:
            thing = iot.CfnThing(
                self,
                f"Thing{device['name'].replace('-', '').title()}",
                thing_name=f"{device['name']}-{self.stack_name}",
                thing_type_name=self.thing_type.thing_type_name,
                attribute_payload=iot.CfnThing.AttributePayloadProperty(
                    attributes={
                        "location": device["location"],
                        "firmwareVersion": device["firmware"],
                        "manufacturer": "AcmeSensors",
                        "deviceType": "temperature-sensor"
                    }
                )
            )
            
            # Add thing to thing group
            thing_group_info = iot.CfnThingGroupInfo(
                self,
                f"ThingGroupInfo{device['name'].replace('-', '').title()}",
                thing_group_name=self.thing_group.thing_group_name,
                thing_name=thing.thing_name
            )
            thing_group_info.add_dependency(thing)
            thing_group_info.add_dependency(self.thing_group)
            
            sample_things.append(thing)
        
        return sample_things

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        
        # Thing Type outputs
        CfnOutput(
            self,
            "ThingTypeArn",
            value=self.thing_type.attr_arn,
            description="ARN of the IoT Thing Type"
        )
        
        CfnOutput(
            self,
            "ThingTypeName",
            value=self.thing_type.thing_type_name,
            description="Name of the IoT Thing Type"
        )
        
        # Thing Group outputs
        CfnOutput(
            self,
            "ThingGroupArn",
            value=self.thing_group.attr_arn,
            description="ARN of the IoT Thing Group"
        )
        
        CfnOutput(
            self,
            "ThingGroupName",
            value=self.thing_group.thing_group_name,
            description="Name of the IoT Thing Group"
        )
        
        # Dynamic Thing Groups outputs
        for i, group in enumerate(self.dynamic_groups):
            CfnOutput(
                self,
                f"DynamicThingGroup{i+1}Arn",
                value=group.attr_arn,
                description=f"ARN of Dynamic Thing Group {i+1}"
            )
        
        # IoT Policy outputs
        CfnOutput(
            self,
            "IoTPolicyArn",
            value=self.iot_policy.attr_arn,
            description="ARN of the IoT Policy"
        )
        
        CfnOutput(
            self,
            "IoTPolicyName",
            value=self.iot_policy.policy_name,
            description="Name of the IoT Policy"
        )
        
        # Log Group outputs
        CfnOutput(
            self,
            "LogGroupArn",
            value=self.log_group.log_group_arn,
            description="ARN of the CloudWatch Log Group"
        )
        
        CfnOutput(
            self,
            "LogGroupName",
            value=self.log_group.log_group_name,
            description="Name of the CloudWatch Log Group"
        )
        
        # Fleet Metrics outputs
        for i, metric in enumerate(self.fleet_metrics):
            CfnOutput(
                self,
                f"FleetMetric{i+1}Arn",
                value=metric.attr_metric_arn,
                description=f"ARN of Fleet Metric {i+1}"
            )
        
        # Sample Things outputs
        thing_names = [thing.thing_name for thing in self.sample_things]
        CfnOutput(
            self,
            "SampleThingNames",
            value=",".join(thing_names),
            description="Names of sample IoT Things created"
        )
        
        # IoT Core Endpoint
        CfnOutput(
            self,
            "IoTCoreEndpoint",
            value=f"https://{self.region}.amazonaws.com/iot",
            description="IoT Core endpoint URL for device connections"
        )


class IoTDeviceManagementApp(cdk.App):
    """
    CDK Application for IoT Device Management.
    """
    
    def __init__(self):
        super().__init__()
        
        # Get environment configuration
        env = cdk.Environment(
            account=self.node.try_get_context("account") or None,
            region=self.node.try_get_context("region") or "us-east-1"
        )
        
        # Create the IoT Device Management stack
        IoTDeviceManagementStack(
            self,
            "IoTDeviceManagementStack",
            env=env,
            description="AWS IoT Device Management solution with fleet organization and monitoring"
        )


def main():
    """Main entry point for the CDK application."""
    app = IoTDeviceManagementApp()
    app.synth()


if __name__ == "__main__":
    main()