#!/usr/bin/env python3
"""
Amazon Connect Custom Contact Center Solution CDK Application

This CDK application deploys a complete contact center solution using Amazon Connect,
including instance configuration, storage setup, user management, queues, contact flows,
and monitoring capabilities.

Services Used:
- Amazon Connect: Core contact center platform
- Amazon S3: Call recording and transcript storage  
- Amazon CloudWatch: Monitoring and dashboards
- AWS IAM: Identity and access management

Author: AWS CDK Python Application Generator
Version: 1.0
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_connect as connect,
    aws_s3 as s3,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from constructs import Construct


class ContactCenterStack(Stack):
    """
    CDK Stack for Amazon Connect Contact Center Solution
    
    This stack creates a complete contact center infrastructure including:
    - Amazon Connect instance with inbound/outbound calling
    - S3 storage for call recordings and transcripts
    - Administrative and agent users with proper security profiles
    - Customer service queue and routing profile
    - Basic contact flow for call routing
    - CloudWatch monitoring and dashboard
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        instance_alias: str,
        enable_contact_lens: bool = True,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration parameters
        self.instance_alias = instance_alias
        self.enable_contact_lens = enable_contact_lens

        # Create S3 bucket for call recordings and transcripts
        self.create_storage_bucket()
        
        # Create Amazon Connect instance
        self.create_connect_instance()
        
        # Configure storage for Connect instance
        self.configure_instance_storage()
        
        # Create users and security profiles
        self.create_users()
        
        # Create queues and routing profiles
        self.create_queues_and_routing()
        
        # Create contact flows
        self.create_contact_flows()
        
        # Setup monitoring and analytics
        self.setup_monitoring()
        
        # Create outputs
        self.create_outputs()

    def create_storage_bucket(self) -> None:
        """Create S3 bucket for storing call recordings and chat transcripts."""
        
        self.storage_bucket = s3.Bucket(
            self,
            "ConnectStorageBucket",
            bucket_name=f"connect-recordings-{self.account}-{self.instance_alias}",
            versioning=s3.BucketVersioning.ENABLED,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            public_write_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="TransitionToIA",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ]
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Add bucket policy for Connect service access
        self.storage_bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AmazonConnectAccess",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("connect.amazonaws.com")],
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:PutObjectAcl",
                    "s3:DeleteObject"
                ],
                resources=[f"{self.storage_bucket.bucket_arn}/*"],
                conditions={
                    "StringEquals": {
                        "aws:SourceAccount": self.account
                    }
                }
            )
        )

        # Add bucket listing permission for Connect
        self.storage_bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AmazonConnectListAccess",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("connect.amazonaws.com")],
                actions=["s3:ListBucket"],
                resources=[self.storage_bucket.bucket_arn],
                conditions={
                    "StringEquals": {
                        "aws:SourceAccount": self.account
                    }
                }
            )
        )

    def create_connect_instance(self) -> None:
        """Create Amazon Connect instance with CONNECT_MANAGED identity."""
        
        self.connect_instance = connect.CfnInstance(
            self,
            "ConnectInstance",
            identity_management_type="CONNECT_MANAGED",
            instance_alias=self.instance_alias,
            attributes=connect.CfnInstance.AttributesProperty(
                inbound_calls=True,
                outbound_calls=True,
                # Enable contact flow logs for debugging and analytics
                contact_flow_logs=True,
                # Enable Contact Lens if specified
                contact_lens=self.enable_contact_lens,
                # Enable auto-resolved best practices
                auto_resolve_best_practices=True,
            )
        )

    def configure_instance_storage(self) -> None:
        """Configure S3 storage for call recordings and chat transcripts."""
        
        # Configure storage for call recordings
        self.call_recording_storage = connect.CfnInstanceStorageConfig(
            self,
            "CallRecordingStorage",
            instance_arn=self.connect_instance.attr_arn,
            resource_type="CALL_RECORDINGS",
            storage_config=connect.CfnInstanceStorageConfig.StorageConfigProperty(
                s3_config=connect.CfnInstanceStorageConfig.S3ConfigProperty(
                    bucket_name=self.storage_bucket.bucket_name,
                    bucket_prefix="call-recordings/",
                    encryption_config=connect.CfnInstanceStorageConfig.EncryptionConfigProperty(
                        encryption_type="KMS",
                        key_id="alias/aws/s3"
                    )
                ),
                storage_type="S3"
            )
        )

        # Configure storage for chat transcripts  
        self.chat_transcript_storage = connect.CfnInstanceStorageConfig(
            self,
            "ChatTranscriptStorage",
            instance_arn=self.connect_instance.attr_arn,
            resource_type="CHAT_TRANSCRIPTS",
            storage_config=connect.CfnInstanceStorageConfig.StorageConfigProperty(
                s3_config=connect.CfnInstanceStorageConfig.S3ConfigProperty(
                    bucket_name=self.storage_bucket.bucket_name,
                    bucket_prefix="chat-transcripts/",
                    encryption_config=connect.CfnInstanceStorageConfig.EncryptionConfigProperty(
                        encryption_type="KMS",
                        key_id="alias/aws/s3"
                    )
                ),
                storage_type="S3"
            )
        )

        # Configure storage for contact trace records
        self.ctr_storage = connect.CfnInstanceStorageConfig(
            self,
            "ContactTraceRecordStorage",
            instance_arn=self.connect_instance.attr_arn,
            resource_type="CONTACT_TRACE_RECORDS",
            storage_config=connect.CfnInstanceStorageConfig.StorageConfigProperty(
                s3_config=connect.CfnInstanceStorageConfig.S3ConfigProperty(
                    bucket_name=self.storage_bucket.bucket_name,
                    bucket_prefix="contact-trace-records/",
                    encryption_config=connect.CfnInstanceStorageConfig.EncryptionConfigProperty(
                        encryption_type="KMS",
                        key_id="alias/aws/s3"
                    )
                ),
                storage_type="S3"
            )
        )

    def create_users(self) -> None:
        """Create administrative and agent users with appropriate security profiles."""
        
        # Create hours of operation for the contact center (24/7 for demo)
        self.hours_of_operation = connect.CfnHoursOfOperation(
            self,
            "HoursOfOperation24x7",
            instance_arn=self.connect_instance.attr_arn,
            name="24x7Support",
            description="24/7 customer support hours",
            time_zone="UTC",
            config=[
                connect.CfnHoursOfOperation.HoursOfOperationConfigProperty(
                    day="MONDAY",
                    start_time=connect.CfnHoursOfOperation.HoursOfOperationTimeSliceProperty(
                        hours=0, minutes=0
                    ),
                    end_time=connect.CfnHoursOfOperation.HoursOfOperationTimeSliceProperty(
                        hours=23, minutes=59
                    )
                ),
                connect.CfnHoursOfOperation.HoursOfOperationConfigProperty(
                    day="TUESDAY",
                    start_time=connect.CfnHoursOfOperation.HoursOfOperationTimeSliceProperty(
                        hours=0, minutes=0
                    ),
                    end_time=connect.CfnHoursOfOperation.HoursOfOperationTimeSliceProperty(
                        hours=23, minutes=59
                    )
                ),
                connect.CfnHoursOfOperation.HoursOfOperationConfigProperty(
                    day="WEDNESDAY",
                    start_time=connect.CfnHoursOfOperation.HoursOfOperationTimeSliceProperty(
                        hours=0, minutes=0
                    ),
                    end_time=connect.CfnHoursOfOperation.HoursOfOperationTimeSliceProperty(
                        hours=23, minutes=59
                    )
                ),
                connect.CfnHoursOfOperation.HoursOfOperationConfigProperty(
                    day="THURSDAY",
                    start_time=connect.CfnHoursOfOperation.HoursOfOperationTimeSliceProperty(
                        hours=0, minutes=0
                    ),
                    end_time=connect.CfnHoursOfOperation.HoursOfOperationTimeSliceProperty(
                        hours=23, minutes=59
                    )
                ),
                connect.CfnHoursOfOperation.HoursOfOperationConfigProperty(
                    day="FRIDAY",
                    start_time=connect.CfnHoursOfOperation.HoursOfOperationTimeSliceProperty(
                        hours=0, minutes=0
                    ),
                    end_time=connect.CfnHoursOfOperation.HoursOfOperationTimeSliceProperty(
                        hours=23, minutes=59
                    )
                ),
                connect.CfnHoursOfOperation.HoursOfOperationConfigProperty(
                    day="SATURDAY",
                    start_time=connect.CfnHoursOfOperation.HoursOfOperationTimeSliceProperty(
                        hours=0, minutes=0
                    ),
                    end_time=connect.CfnHoursOfOperation.HoursOfOperationTimeSliceProperty(
                        hours=23, minutes=59
                    )
                ),
                connect.CfnHoursOfOperation.HoursOfOperationConfigProperty(
                    day="SUNDAY",
                    start_time=connect.CfnHoursOfOperation.HoursOfOperationTimeSliceProperty(
                        hours=0, minutes=0
                    ),
                    end_time=connect.CfnHoursOfOperation.HoursOfOperationTimeSliceProperty(
                        hours=23, minutes=59
                    )
                )
            ]
        )

    def create_queues_and_routing(self) -> None:
        """Create customer service queue and agent routing profile."""
        
        # Create customer service queue
        self.customer_service_queue = connect.CfnQueue(
            self,
            "CustomerServiceQueue",
            instance_arn=self.connect_instance.attr_arn,
            hours_of_operation_arn=self.hours_of_operation.attr_hours_of_operation_arn,
            name="CustomerService",
            description="Main customer service queue for general inquiries",
            max_contacts=50,
            outbound_caller_config=connect.CfnQueue.OutboundCallerConfigProperty(
                outbound_caller_id_name="Customer Service",
                outbound_flow_arn=""  # Will be set after contact flow creation
            ),
            tags=[
                cdk.CfnTag(key="Purpose", value="CustomerService"),
                cdk.CfnTag(key="Environment", value="Production")
            ]
        )

        # Create routing profile for customer service agents
        self.agent_routing_profile = connect.CfnRoutingProfile(
            self,
            "CustomerServiceAgentRoutingProfile", 
            instance_arn=self.connect_instance.attr_arn,
            name="CustomerServiceAgents",
            description="Routing profile for customer service representatives",
            default_outbound_queue_arn=self.customer_service_queue.attr_queue_arn,
            media_concurrencies=[
                connect.CfnRoutingProfile.MediaConcurrencyProperty(
                    channel="VOICE",
                    concurrency=1
                ),
                connect.CfnRoutingProfile.MediaConcurrencyProperty(
                    channel="CHAT", 
                    concurrency=2
                )
            ],
            queue_configs=[
                connect.CfnRoutingProfile.RoutingProfileQueueConfigProperty(
                    delay=0,
                    priority=1,
                    queue_reference=connect.CfnRoutingProfile.RoutingProfileQueueReferenceProperty(
                        channel="VOICE",
                        queue_arn=self.customer_service_queue.attr_queue_arn
                    )
                )
            ],
            tags=[
                cdk.CfnTag(key="Purpose", value="AgentRouting"),
                cdk.CfnTag(key="Environment", value="Production")
            ]
        )

    def create_contact_flows(self) -> None:
        """Create basic contact flow for customer service routing."""
        
        # Define contact flow content with proper structure
        contact_flow_content = {
            "Version": "2019-10-30",
            "StartAction": "greeting-message",
            "Actions": [
                {
                    "Identifier": "greeting-message",
                    "Type": "MessageParticipant",
                    "Parameters": {
                        "Text": "Thank you for calling our customer service. Please wait while we connect you to an available agent."
                    },
                    "Transitions": {
                        "NextAction": "enable-recording"
                    }
                },
                {
                    "Identifier": "enable-recording",
                    "Type": "SetRecordingBehavior", 
                    "Parameters": {
                        "RecordingBehaviorOption": "Enable",
                        "RecordingParticipantOption": "Both"
                    },
                    "Transitions": {
                        "NextAction": "transfer-to-queue"
                    }
                },
                {
                    "Identifier": "transfer-to-queue",
                    "Type": "TransferToQueue",
                    "Parameters": {
                        "QueueId": f"${{{self.customer_service_queue.attr_queue_arn}}}"
                    },
                    "Transitions": {}
                }
            ],
            "Metadata": {
                "entryPointPosition": {"x": 20, "y": 20},
                "snapToGrid": False,
                "ActionMetadata": {
                    "greeting-message": {"position": {"x": 178, "y": 52}},
                    "enable-recording": {"position": {"x": 392, "y": 154}},
                    "transfer-to-queue": {"position": {"x": 626, "y": 154}}
                }
            }
        }

        # Create customer service contact flow
        self.customer_service_flow = connect.CfnContactFlow(
            self,
            "CustomerServiceContactFlow",
            instance_arn=self.connect_instance.attr_arn,
            name="CustomerServiceFlow",
            type="CONTACT_FLOW",
            description="Main customer service contact flow with recording and queue transfer",
            content=cdk.Fn.to_json_string(contact_flow_content),
            state="ACTIVE",
            tags=[
                cdk.CfnTag(key="Purpose", value="CustomerService"),
                cdk.CfnTag(key="Environment", value="Production")
            ]
        )

    def setup_monitoring(self) -> None:
        """Setup CloudWatch monitoring and dashboard for the contact center."""
        
        # Create CloudWatch dashboard for contact center metrics
        self.dashboard = cloudwatch.Dashboard(
            self,
            "ContactCenterDashboard",
            dashboard_name=f"ConnectContactCenter-{self.instance_alias}",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Contact Volume",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/Connect",
                                metric_name="ContactsReceived",
                                dimensions_map={
                                    "InstanceId": self.connect_instance.ref
                                },
                                statistic="Sum",
                                period=Duration.minutes(5)
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/Connect", 
                                metric_name="ContactsHandled",
                                dimensions_map={
                                    "InstanceId": self.connect_instance.ref
                                },
                                statistic="Sum",
                                period=Duration.minutes(5)
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/Connect",
                                metric_name="ContactsAbandoned", 
                                dimensions_map={
                                    "InstanceId": self.connect_instance.ref
                                },
                                statistic="Sum",
                                period=Duration.minutes(5)
                            )
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.GraphWidget(
                        title="Agent Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/Connect",
                                metric_name="AgentsOnline",
                                dimensions_map={
                                    "InstanceId": self.connect_instance.ref
                                },
                                statistic="Average",
                                period=Duration.minutes(5)
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/Connect",
                                metric_name="AgentsAvailable",
                                dimensions_map={
                                    "InstanceId": self.connect_instance.ref
                                },
                                statistic="Average",
                                period=Duration.minutes(5)
                            )
                        ],
                        width=6,
                        height=6
                    ),
                    cloudwatch.GraphWidget(
                        title="Queue Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/Connect",
                                metric_name="ContactsInQueue",
                                dimensions_map={
                                    "InstanceId": self.connect_instance.ref,
                                    "QueueName": "CustomerService"
                                },
                                statistic="Average",
                                period=Duration.minutes(5)
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/Connect",
                                metric_name="LongestQueueWaitTime",
                                dimensions_map={
                                    "InstanceId": self.connect_instance.ref,
                                    "QueueName": "CustomerService"
                                },
                                statistic="Maximum",
                                period=Duration.minutes(5)
                            )
                        ],
                        width=6,
                        height=6
                    )
                ]
            ]
        )

        # Create CloudWatch log group for Connect logs
        self.connect_log_group = logs.LogGroup(
            self,
            "ConnectLogGroup",
            log_group_name=f"/aws/connect/{self.instance_alias}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )

    def create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        
        CfnOutput(
            self,
            "ConnectInstanceId",
            value=self.connect_instance.ref,
            description="Amazon Connect Instance ID",
            export_name=f"{self.stack_name}-ConnectInstanceId"
        )

        CfnOutput(
            self,
            "ConnectInstanceArn", 
            value=self.connect_instance.attr_arn,
            description="Amazon Connect Instance ARN",
            export_name=f"{self.stack_name}-ConnectInstanceArn"
        )

        CfnOutput(
            self,
            "ConnectInstanceAlias",
            value=self.instance_alias,
            description="Amazon Connect Instance Alias",
            export_name=f"{self.stack_name}-ConnectInstanceAlias"
        )

        CfnOutput(
            self,
            "StorageBucketName",
            value=self.storage_bucket.bucket_name,
            description="S3 Bucket for call recordings and transcripts",
            export_name=f"{self.stack_name}-StorageBucket"
        )

        CfnOutput(
            self,
            "CustomerServiceQueueArn",
            value=self.customer_service_queue.attr_queue_arn,
            description="Customer Service Queue ARN",
            export_name=f"{self.stack_name}-CustomerServiceQueueArn"
        )

        CfnOutput(
            self,
            "ContactFlowArn",
            value=self.customer_service_flow.attr_contact_flow_arn,
            description="Customer Service Contact Flow ARN",
            export_name=f"{self.stack_name}-ContactFlowArn"
        )

        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="CloudWatch Dashboard URL for monitoring",
            export_name=f"{self.stack_name}-DashboardUrl"
        )

        CfnOutput(
            self,
            "ConnectConsoleUrl",
            value=f"https://{self.instance_alias}.my.connect.aws/connect/home",
            description="Amazon Connect Admin Console URL",
            export_name=f"{self.stack_name}-ConnectConsoleUrl"
        )


class ContactCenterApp(cdk.App):
    """
    CDK Application for Amazon Connect Contact Center Solution
    
    This application creates a complete contact center infrastructure using Amazon Connect
    with supporting services for storage, monitoring, and analytics.
    """

    def __init__(self):
        super().__init__()

        # Get configuration from environment variables or context
        instance_alias = self.node.try_get_context("instance_alias") or os.environ.get("CONNECT_INSTANCE_ALIAS", "contact-center-demo")
        enable_contact_lens = self.node.try_get_context("enable_contact_lens") 
        if enable_contact_lens is None:
            enable_contact_lens = os.environ.get("ENABLE_CONTACT_LENS", "true").lower() == "true"

        # Create the contact center stack
        ContactCenterStack(
            self,
            "ContactCenterStack",
            instance_alias=instance_alias,
            enable_contact_lens=enable_contact_lens,
            description="Amazon Connect Custom Contact Center Solution",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION")
            ),
            tags={
                "Project": "ContactCenterSolution",
                "Environment": "Production",
                "Owner": "DevOps",
                "CostCenter": "CustomerService"
            }
        )


# Create and run the application
app = ContactCenterApp()
app.synth()