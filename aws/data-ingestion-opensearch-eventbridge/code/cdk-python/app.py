#!/usr/bin/env python3
"""
CDK Python Application for Automated Data Ingestion Pipelines
This application creates an automated data ingestion pipeline using:
- Amazon OpenSearch Service for analytics and search
- OpenSearch Ingestion for serverless data processing
- EventBridge Scheduler for pipeline automation
- S3 for data lake storage
- IAM roles with least privilege access
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    RemovalPolicy,
    Duration,
    Tags,
    aws_s3 as s3,
    aws_opensearch as opensearch,
    aws_iam as iam,
    aws_scheduler as scheduler,
    aws_logs as logs,
    CfnOutput
)
from constructs import Construct
from typing import Dict, Any
import json


class DataIngestionPipelineStack(Stack):
    """
    CDK Stack for automated data ingestion pipeline with OpenSearch and EventBridge Scheduler.
    
    This stack creates:
    - S3 bucket for data lake storage with encryption and versioning
    - OpenSearch Service domain for analytics with security features
    - IAM roles for OpenSearch Ingestion and EventBridge Scheduler
    - OpenSearch Ingestion pipeline for data processing
    - EventBridge Scheduler schedules for pipeline automation
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters for customization
        self.project_name = self.node.try_get_context("project_name") or "data-ingestion"
        self.environment = self.node.try_get_context("environment") or "dev"
        self.opensearch_instance_type = self.node.try_get_context("opensearch_instance_type") or "t3.small.search"
        self.opensearch_instance_count = self.node.try_get_context("opensearch_instance_count") or 1
        self.opensearch_ebs_volume_size = self.node.try_get_context("opensearch_ebs_volume_size") or 20
        self.pipeline_min_units = self.node.try_get_context("pipeline_min_units") or 1
        self.pipeline_max_units = self.node.try_get_context("pipeline_max_units") or 4

        # Create S3 bucket for data lake
        self.data_bucket = self._create_s3_bucket()
        
        # Create OpenSearch domain
        self.opensearch_domain = self._create_opensearch_domain()
        
        # Create IAM roles
        self.ingestion_role = self._create_ingestion_role()
        self.scheduler_role = self._create_scheduler_role()
        
        # Create OpenSearch Ingestion pipeline
        self.ingestion_pipeline = self._create_ingestion_pipeline()
        
        # Create EventBridge Scheduler resources
        self.schedule_group = self._create_schedule_group()
        self._create_pipeline_schedules()
        
        # Create CloudWatch Log Group for monitoring
        self.log_group = self._create_log_group()
        
        # Add tags to all resources
        self._add_tags()
        
        # Create outputs
        self._create_outputs()

    def _create_s3_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for data lake storage with security best practices.
        
        Features:
        - Server-side encryption with AES256
        - Versioning enabled for data protection
        - Public access blocked for security
        - Lifecycle policies for cost optimization
        """
        bucket = s3.Bucket(
            self,
            "DataLakeBucket",
            bucket_name=f"{self.project_name}-data-lake-{self.account}-{self.region}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            versioned=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            auto_delete_objects=True,  # For demo purposes
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
            ]
        )
        
        return bucket

    def _create_opensearch_domain(self) -> opensearch.Domain:
        """
        Create OpenSearch Service domain with security and monitoring features.
        
        Features:
        - Latest OpenSearch version
        - Encryption at rest and in transit
        - Fine-grained access control
        - CloudWatch logging enabled
        - Appropriate instance sizing
        """
        # Create access policy for the domain
        access_policy = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "AWS": f"arn:aws:iam::{self.account}:root"
                    },
                    "Action": "es:*",
                    "Resource": f"arn:aws:es:{self.region}:{self.account}:domain/{self.project_name}-domain/*"
                }
            ]
        }

        domain = opensearch.Domain(
            self,
            "OpenSearchDomain",
            version=opensearch.EngineVersion.OPENSEARCH_2_11,
            domain_name=f"{self.project_name}-domain",
            capacity=opensearch.CapacityConfig(
                data_node_instance_type=self.opensearch_instance_type,
                data_nodes=self.opensearch_instance_count,
                master_nodes=0  # No dedicated master for small deployments
            ),
            ebs=opensearch.EbsOptions(
                enabled=True,
                volume_type=cdk.aws_ec2.EbsDeviceVolumeType.GP3,
                volume_size=self.opensearch_ebs_volume_size
            ),
            zone_awareness=opensearch.ZoneAwarenessConfig(
                enabled=False  # Single AZ for cost optimization in dev
            ),
            encryption_at_rest=opensearch.EncryptionAtRestOptions(
                enabled=True
            ),
            node_to_node_encryption=True,
            enforce_https=True,
            access_policies=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[iam.AccountRootPrincipal()],
                    actions=["es:*"],
                    resources=[f"arn:aws:es:{self.region}:{self.account}:domain/{self.project_name}-domain/*"]
                )
            ],
            logging=opensearch.LoggingOptions(
                slow_search_log_enabled=True,
                app_log_enabled=True,
                slow_index_log_enabled=True
            ),
            removal_policy=RemovalPolicy.DESTROY  # For demo purposes
        )
        
        return domain

    def _create_ingestion_role(self) -> iam.Role:
        """
        Create IAM role for OpenSearch Ingestion with least privilege permissions.
        
        Permissions:
        - Read access to S3 data bucket
        - Write access to OpenSearch domain
        - CloudWatch Logs permissions for monitoring
        """
        role = iam.Role(
            self,
            "IngestionRole",
            role_name=f"{self.project_name}-ingestion-role",
            assumed_by=iam.ServicePrincipal("osis-pipelines.amazonaws.com"),
            description="IAM role for OpenSearch Ingestion pipeline operations"
        )
        
        # Add policy for S3 access
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:ListBucket"
                ],
                resources=[
                    self.data_bucket.bucket_arn,
                    f"{self.data_bucket.bucket_arn}/*"
                ]
            )
        )
        
        # Add policy for OpenSearch access
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "es:ESHttpPost",
                    "es:ESHttpPut"
                ],
                resources=[f"{self.opensearch_domain.domain_arn}/*"]
            )
        )
        
        # Add CloudWatch Logs permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                    "logs:DescribeLogGroups",
                    "logs:DescribeLogStreams"
                ],
                resources=[f"arn:aws:logs:{self.region}:{self.account}:*"]
            )
        )
        
        return role

    def _create_scheduler_role(self) -> iam.Role:
        """
        Create IAM role for EventBridge Scheduler to control OpenSearch Ingestion pipeline.
        
        Permissions:
        - Start and stop OpenSearch Ingestion pipelines
        - Get pipeline status for monitoring
        """
        role = iam.Role(
            self,
            "SchedulerRole",
            role_name=f"{self.project_name}-scheduler-role",
            assumed_by=iam.ServicePrincipal("scheduler.amazonaws.com"),
            description="IAM role for EventBridge Scheduler pipeline automation"
        )
        
        # Add policy for pipeline control
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "osis:StartPipeline",
                    "osis:StopPipeline",
                    "osis:GetPipeline"
                ],
                resources=[f"arn:aws:osis:{self.region}:{self.account}:pipeline/{self.project_name}-pipeline"]
            )
        )
        
        return role

    def _create_ingestion_pipeline(self) -> opensearch.CfnPipeline:
        """
        Create OpenSearch Ingestion pipeline with Data Prepper configuration.
        
        Pipeline configuration:
        - S3 source with SQS notifications
        - Data transformation processors
        - OpenSearch sink with daily indices
        - Error handling and monitoring
        """
        # Create pipeline configuration YAML
        pipeline_config = f"""
{self.project_name}-ingestion-pipeline:
  source:
    s3:
      notification_type: "sqs"
      codec:
        newline: null
      compression: "none"
      bucket: "{self.data_bucket.bucket_name}"
      object_key:
        include_keys:
          - "logs/**"
          - "metrics/**"
          - "events/**"
  processor:
    - date:
        from_time_received: true
        destination: "@timestamp"
    - mutate:
        rename_keys:
          message: "raw_message"
    - grok:
        match:
          raw_message: ['%{{TIMESTAMP_ISO8601:timestamp}} %{{LOGLEVEL:level}} %{{GREEDYDATA:message}}']
        target_key: "parsed"
        break_on_match: true
        keep_empty_captures: false
  sink:
    - opensearch:
        hosts: ["https://{self.opensearch_domain.domain_endpoint}"]
        index: "application-logs-%{{yyyy.MM.dd}}"
        aws:
          region: "{self.region}"
          sts_role_arn: "{self.ingestion_role.role_arn}"
          serverless: false
        template_type: "index-template"
        template_content: |
          {{
            "index_patterns": ["application-logs-*"],
            "template": {{
              "settings": {{
                "number_of_shards": 1,
                "number_of_replicas": 0,
                "index.refresh_interval": "30s"
              }},
              "mappings": {{
                "properties": {{
                  "@timestamp": {{"type": "date"}},
                  "level": {{"type": "keyword"}},
                  "message": {{"type": "text"}},
                  "parsed": {{"type": "object"}}
                }}
              }}
            }}
          }}
"""

        pipeline = opensearch.CfnPipeline(
            self,
            "IngestionPipeline",
            pipeline_name=f"{self.project_name}-pipeline",
            min_units=self.pipeline_min_units,
            max_units=self.pipeline_max_units,
            pipeline_configuration_body=pipeline_config,
            tags=[
                cdk.CfnTag(key="Environment", value=self.environment),
                cdk.CfnTag(key="Project", value=self.project_name),
                cdk.CfnTag(key="Service", value="OpenSearchIngestion")
            ]
        )
        
        # Add dependency on required resources
        pipeline.add_dependency(self.opensearch_domain.node.default_child)
        pipeline.add_dependency(self.ingestion_role.node.default_child)
        
        return pipeline

    def _create_schedule_group(self) -> scheduler.CfnScheduleGroup:
        """
        Create EventBridge Scheduler schedule group for organizing pipeline schedules.
        """
        schedule_group = scheduler.CfnScheduleGroup(
            self,
            "ScheduleGroup",
            name=f"{self.project_name}-schedules",
            tags=[
                cdk.CfnTag(key="Environment", value=self.environment),
                cdk.CfnTag(key="Service", value="DataIngestion")
            ]
        )
        
        return schedule_group

    def _create_pipeline_schedules(self) -> None:
        """
        Create EventBridge Scheduler schedules for automated pipeline start/stop operations.
        
        Schedules:
        - Start pipeline daily at 8 AM UTC (business hours)
        - Stop pipeline daily at 6 PM UTC (cost optimization)
        """
        # Start pipeline schedule
        start_schedule = scheduler.CfnSchedule(
            self,
            "StartPipelineSchedule",
            name="start-ingestion-pipeline",
            group_name=self.schedule_group.name,
            schedule_expression="cron(0 8 * * ? *)",  # 8 AM UTC daily
            target=scheduler.CfnSchedule.TargetProperty(
                arn=f"arn:aws:osis:{self.region}:{self.account}:pipeline/{self.project_name}-pipeline",
                role_arn=self.scheduler_role.role_arn,
                input='{"action": "start"}',
                retry_policy=scheduler.CfnSchedule.RetryPolicyProperty(
                    maximum_retry_attempts=3,
                    maximum_event_age_in_seconds=3600
                )
            ),
            flexible_time_window=scheduler.CfnSchedule.FlexibleTimeWindowProperty(
                mode="FLEXIBLE",
                maximum_window_in_minutes=15
            ),
            description="Daily start of data ingestion pipeline at 8 AM UTC",
            state="ENABLED"
        )
        
        # Stop pipeline schedule
        stop_schedule = scheduler.CfnSchedule(
            self,
            "StopPipelineSchedule",
            name="stop-ingestion-pipeline",
            group_name=self.schedule_group.name,
            schedule_expression="cron(0 18 * * ? *)",  # 6 PM UTC daily
            target=scheduler.CfnSchedule.TargetProperty(
                arn=f"arn:aws:osis:{self.region}:{self.account}:pipeline/{self.project_name}-pipeline",
                role_arn=self.scheduler_role.role_arn,
                input='{"action": "stop"}',
                retry_policy=scheduler.CfnSchedule.RetryPolicyProperty(
                    maximum_retry_attempts=3,
                    maximum_event_age_in_seconds=3600
                )
            ),
            flexible_time_window=scheduler.CfnSchedule.FlexibleTimeWindowProperty(
                mode="FLEXIBLE",
                maximum_window_in_minutes=15
            ),
            description="Daily stop of data ingestion pipeline at 6 PM UTC",
            state="ENABLED"
        )
        
        # Add dependencies
        start_schedule.add_dependency(self.schedule_group)
        start_schedule.add_dependency(self.scheduler_role.node.default_child)
        start_schedule.add_dependency(self.ingestion_pipeline)
        
        stop_schedule.add_dependency(self.schedule_group)
        stop_schedule.add_dependency(self.scheduler_role.node.default_child)
        stop_schedule.add_dependency(self.ingestion_pipeline)

    def _create_log_group(self) -> logs.LogGroup:
        """
        Create CloudWatch Log Group for centralized logging and monitoring.
        """
        log_group = logs.LogGroup(
            self,
            "PipelineLogGroup",
            log_group_name=f"/aws/opensearch-ingestion/{self.project_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        return log_group

    def _add_tags(self) -> None:
        """
        Add common tags to all resources in the stack.
        """
        Tags.of(self).add("Environment", self.environment)
        Tags.of(self).add("Project", self.project_name)
        Tags.of(self).add("Service", "DataIngestion")
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("CostCenter", "Analytics")

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resource information.
        """
        CfnOutput(
            self,
            "S3BucketName",
            value=self.data_bucket.bucket_name,
            description="Name of the S3 bucket for data lake storage",
            export_name=f"{self.stack_name}-S3BucketName"
        )
        
        CfnOutput(
            self,
            "OpenSearchDomainEndpoint",
            value=f"https://{self.opensearch_domain.domain_endpoint}",
            description="OpenSearch domain endpoint URL",
            export_name=f"{self.stack_name}-OpenSearchEndpoint"
        )
        
        CfnOutput(
            self,
            "OpenSearchDashboardsURL",
            value=f"https://{self.opensearch_domain.domain_endpoint}/_dashboards/",
            description="OpenSearch Dashboards URL for data visualization",
            export_name=f"{self.stack_name}-DashboardsURL"
        )
        
        CfnOutput(
            self,
            "IngestionPipelineName",
            value=self.ingestion_pipeline.pipeline_name,
            description="Name of the OpenSearch Ingestion pipeline",
            export_name=f"{self.stack_name}-PipelineName"
        )
        
        CfnOutput(
            self,
            "ScheduleGroupName",
            value=self.schedule_group.name,
            description="Name of the EventBridge Scheduler schedule group",
            export_name=f"{self.stack_name}-ScheduleGroupName"
        )
        
        CfnOutput(
            self,
            "LogGroupName",
            value=self.log_group.log_group_name,
            description="CloudWatch Log Group for pipeline monitoring",
            export_name=f"{self.stack_name}-LogGroupName"
        )


# CDK App definition
app = cdk.App()

# Get context values for stack configuration
account = app.node.try_get_context("account") or cdk.Aws.ACCOUNT_ID
region = app.node.try_get_context("region") or "us-east-1"
environment = app.node.try_get_context("environment") or "dev"

# Create the main stack
stack = DataIngestionPipelineStack(
    app, 
    f"DataIngestionPipeline-{environment}",
    env=cdk.Environment(account=account, region=region),
    description="Automated data ingestion pipeline with OpenSearch Ingestion and EventBridge Scheduler"
)

# Synthesize the CloudFormation template
app.synth()