#!/usr/bin/env python3
"""
CDK Python application for automated multi-account resource discovery
with AWS Resource Explorer, Config, EventBridge, and Lambda.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_events as events,
    aws_events_targets as targets,
    aws_s3 as s3,
    aws_config as config,
    aws_resourceexplorer2 as resource_explorer,
    aws_logs as logs,
    RemovalPolicy,
)
from constructs import Construct
from typing import Optional, List


class MultiAccountResourceDiscoveryStack(Stack):
    """
    CDK Stack for automated multi-account resource discovery system.
    
    This stack implements a comprehensive solution for discovering and monitoring
    resources across multiple AWS accounts using Resource Explorer, Config,
    EventBridge, and Lambda for intelligent automation.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create S3 bucket for Config data storage
        self._create_config_bucket()
        
        # Create Resource Explorer aggregated index
        self._create_resource_explorer_index()
        
        # Create Config service components
        self._create_config_service()
        
        # Create Lambda function for processing events
        self._create_lambda_function()
        
        # Create EventBridge rules for automation
        self._create_eventbridge_rules()
        
        # Create Config rules for compliance monitoring
        self._create_config_rules()
        
        # Create outputs for reference
        self._create_outputs()

    def _create_config_bucket(self) -> None:
        """Create S3 bucket for AWS Config data storage with proper policies."""
        self.config_bucket = s3.Bucket(
            self, "ConfigBucket",
            bucket_name=f"aws-config-bucket-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )
        
        # Add bucket policy for Config service
        config_service_principal = iam.ServicePrincipal("config.amazonaws.com")
        
        self.config_bucket.add_to_resource_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                principals=[config_service_principal],
                actions=["s3:GetBucketAcl"],
                resources=[self.config_bucket.bucket_arn],
            )
        )
        
        self.config_bucket.add_to_resource_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                principals=[config_service_principal],
                actions=["s3:PutObject"],
                resources=[f"{self.config_bucket.bucket_arn}/*"],
                conditions={
                    "StringEquals": {
                        "s3:x-amz-acl": "bucket-owner-full-control"
                    }
                }
            )
        )

    def _create_resource_explorer_index(self) -> None:
        """Create Resource Explorer aggregated index for multi-account search."""
        self.resource_explorer_index = resource_explorer.CfnIndex(
            self, "ResourceExplorerIndex",
            type="AGGREGATOR",
            tags=[
                cdk.CfnTag(key="Purpose", value="MultiAccountDiscovery"),
                cdk.CfnTag(key="ManagedBy", value="CDK-ResourceDiscovery")
            ]
        )
        
        # Create default view for organization-wide search
        self.resource_explorer_view = resource_explorer.CfnView(
            self, "ResourceExplorerView",
            view_name="organization-view",
            included_properties=[
                resource_explorer.CfnView.IncludedPropertyProperty(
                    name="tags"
                )
            ],
            tags=[
                cdk.CfnTag(key="Purpose", value="MultiAccountDiscovery"),
                cdk.CfnTag(key="ManagedBy", value="CDK-ResourceDiscovery")
            ]
        )
        
        # Make view depend on index
        self.resource_explorer_view.add_dependency(self.resource_explorer_index)

    def _create_config_service(self) -> None:
        """Create AWS Config service components including aggregator."""
        # Create service-linked role for Config (if not exists)
        # Note: Service-linked roles are created automatically by AWS Config service
        
        # Create configuration recorder
        self.config_recorder = config.CfnConfigurationRecorder(
            self, "ConfigRecorder",
            name="multi-account-discovery-recorder",
            role_arn=f"arn:aws:iam::{self.account}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig",
            recording_group=config.CfnConfigurationRecorder.RecordingGroupProperty(
                all_supported=True,
                include_global_resource_types=True,
                recording_mode_overrides=[]
            )
        )
        
        # Create delivery channel
        self.delivery_channel = config.CfnDeliveryChannel(
            self, "ConfigDeliveryChannel",
            name="multi-account-discovery-channel",
            s3_bucket_name=self.config_bucket.bucket_name,
            config_snapshot_delivery_properties=config.CfnDeliveryChannel.ConfigSnapshotDeliveryPropertiesProperty(
                delivery_frequency="TwentyFour_Hours"
            )
        )
        
        # Create organizational aggregator
        self.config_aggregator = config.CfnConfigurationAggregator(
            self, "ConfigAggregator",
            configuration_aggregator_name="multi-account-discovery-aggregator",
            organization_aggregation_source=config.CfnConfigurationAggregator.OrganizationAggregationSourceProperty(
                role_arn=f"arn:aws:iam::{self.account}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig",
                aws_regions=[self.region],
                all_aws_regions=False
            )
        )

    def _create_lambda_function(self) -> None:
        """Create Lambda function for processing discovery and compliance events."""
        # Create execution role for Lambda
        self.lambda_role = iam.Role(
            self, "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for multi-account resource discovery Lambda",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ]
        )
        
        # Add custom permissions for enhanced functionality
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "config:GetComplianceDetailsByConfigRule",
                    "config:GetAggregateComplianceDetailsByConfigRule",
                    "resource-explorer-2:Search",
                    "resource-explorer-2:GetIndex",
                    "sns:Publish",
                    "organizations:ListAccounts",
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ],
                resources=["*"]
            )
        )
        
        # Create Lambda function with enhanced code
        lambda_code = '''
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

config_client = boto3.client('config')
resource_explorer_client = boto3.client('resource-explorer-2')
organizations_client = boto3.client('organizations')

def lambda_handler(event, context):
    """Main handler for multi-account resource discovery events"""
    logger.info(f"Processing event: {json.dumps(event, default=str)}")
    
    try:
        # Process Config compliance events
        if event.get('source') == 'aws.config':
            return process_config_event(event)
        
        # Process Resource Explorer events
        elif event.get('source') == 'aws.resource-explorer-2':
            return process_resource_explorer_event(event)
        
        # Handle scheduled discovery tasks
        elif event.get('source') == 'aws.events' and 'Scheduled Event' in event.get('detail-type', ''):
            return process_scheduled_discovery()
        
        else:
            logger.warning(f"Unknown event source: {event.get('source')}")
            
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        raise
    
    return {
        'statusCode': 200,
        'body': json.dumps('Event processed successfully')
    }

def process_config_event(event):
    """Process AWS Config compliance events with enhanced logging"""
    detail = event.get('detail', {})
    compliance_type = detail.get('newEvaluationResult', {}).get('complianceType')
    resource_type = detail.get('resourceType')
    resource_id = detail.get('resourceId')
    account_id = detail.get('awsAccountId')
    
    logger.info(f"Config event - Resource: {resource_type}, "
                f"ID: {resource_id}, Account: {account_id}, "
                f"Compliance: {compliance_type}")
    
    if compliance_type == 'NON_COMPLIANT':
        logger.warning(f"Non-compliant resource detected: {resource_type} in account {account_id}")
        handle_compliance_violation(detail)
    
    return {'statusCode': 200, 'compliance_processed': True}

def process_resource_explorer_event(event):
    """Process Resource Explorer events for resource discovery"""
    logger.info("Processing Resource Explorer event for cross-account discovery")
    
    try:
        response = resource_explorer_client.search(
            QueryString="service:ec2",
            MaxResults=10
        )
        
        resource_count = len(response.get('Resources', []))
        logger.info(f"Discovered {resource_count} EC2 resources across accounts")
        
    except Exception as e:
        logger.error(f"Error in resource discovery: {str(e)}")
    
    return {'statusCode': 200, 'discovery_processed': True}

def handle_compliance_violation(detail):
    """Handle compliance violations with detailed logging"""
    resource_type = detail.get('resourceType')
    resource_id = detail.get('resourceId')
    config_rule_name = detail.get('configRuleName')
    
    logger.warning(f"Compliance violation detected:")
    logger.warning(f"  Rule: {config_rule_name}")
    logger.warning(f"  Resource Type: {resource_type}")
    logger.warning(f"  Resource ID: {resource_id}")

def process_scheduled_discovery():
    """Process scheduled resource discovery tasks"""
    logger.info("Processing scheduled resource discovery scan")
    
    try:
        accounts = organizations_client.list_accounts()
        active_accounts = [acc for acc in accounts['Accounts'] if acc['Status'] == 'ACTIVE']
        
        logger.info(f"Monitoring {len(active_accounts)} active accounts")
        
        search_results = resource_explorer_client.search(
            QueryString="*",
            MaxResults=100
        )
        
        logger.info(f"Total resources discovered: {len(search_results.get('Resources', []))}")
        
    except Exception as e:
        logger.error(f"Error in scheduled discovery: {str(e)}")
    
    return {'statusCode': 200, 'scheduled_discovery_complete': True}
'''
        
        self.lambda_function = lambda_.Function(
            self, "ResourceDiscoveryProcessor",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=512,
            description="Multi-account resource discovery and compliance processor",
            log_retention=logs.RetentionDays.ONE_WEEK,
            environment={
                "AWS_REGION": self.region,
                "CONFIG_AGGREGATOR_NAME": "multi-account-discovery-aggregator"
            }
        )

    def _create_eventbridge_rules(self) -> None:
        """Create EventBridge rules for automated event processing."""
        # Rule for Config compliance events
        self.config_compliance_rule = events.Rule(
            self, "ConfigComplianceRule",
            rule_name="multi-account-discovery-config-rule",
            description="Route Config compliance violations to Lambda processor",
            event_pattern=events.EventPattern(
                source=["aws.config"],
                detail_type=["Config Rules Compliance Change"],
                detail={
                    "newEvaluationResult": {
                        "complianceType": ["NON_COMPLIANT"]
                    }
                }
            )
        )
        
        # Add Lambda as target for compliance events
        self.config_compliance_rule.add_target(
            targets.LambdaFunction(self.lambda_function)
        )
        
        # Rule for scheduled resource discovery
        self.discovery_schedule_rule = events.Rule(
            self, "DiscoveryScheduleRule",
            rule_name="multi-account-discovery-schedule",
            description="Scheduled resource discovery across accounts",
            schedule=events.Schedule.rate(Duration.days(1))
        )
        
        # Add Lambda as target for scheduled events
        self.discovery_schedule_rule.add_target(
            targets.LambdaFunction(self.lambda_function)
        )

    def _create_config_rules(self) -> None:
        """Create AWS Config rules for comprehensive compliance monitoring."""
        # S3 bucket public access prohibited
        self.s3_public_access_rule = config.CfnConfigRule(
            self, "S3PublicAccessRule",
            config_rule_name="multi-account-s3-bucket-public-access-prohibited",
            description="Checks that S3 buckets do not allow public access",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS",
                source_identifier="S3_BUCKET_PUBLIC_ACCESS_PROHIBITED"
            ),
            depends_on=[self.config_recorder]
        )
        
        # EC2 security group attached to ENI
        self.ec2_sg_attached_rule = config.CfnConfigRule(
            self, "EC2SecurityGroupAttachedRule",
            config_rule_name="multi-account-ec2-security-group-attached-to-eni",
            description="Checks that security groups are attached to EC2 instances",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS",
                source_identifier="EC2_SECURITY_GROUP_ATTACHED_TO_ENI"
            ),
            depends_on=[self.config_recorder]
        )
        
        # Root access key check
        self.root_access_key_rule = config.CfnConfigRule(
            self, "RootAccessKeyRule",
            config_rule_name="multi-account-root-access-key-check",
            description="Checks whether root access key exists",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS",
                source_identifier="ROOT_ACCESS_KEY_CHECK"
            ),
            depends_on=[self.config_recorder]
        )
        
        # Encrypted volumes check
        self.encrypted_volumes_rule = config.CfnConfigRule(
            self, "EncryptedVolumesRule",
            config_rule_name="multi-account-encrypted-volumes",
            description="Checks whether EBS volumes are encrypted",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS",
                source_identifier="ENCRYPTED_VOLUMES"
            ),
            depends_on=[self.config_recorder]
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        cdk.CfnOutput(
            self, "ConfigBucketName",
            value=self.config_bucket.bucket_name,
            description="Name of the S3 bucket storing Config data",
            export_name="MultiAccountDiscovery-ConfigBucket"
        )
        
        cdk.CfnOutput(
            self, "LambdaFunctionArn",
            value=self.lambda_function.function_arn,
            description="ARN of the resource discovery Lambda function",
            export_name="MultiAccountDiscovery-LambdaFunction"
        )
        
        cdk.CfnOutput(
            self, "ConfigAggregatorName",
            value=self.config_aggregator.configuration_aggregator_name,
            description="Name of the Config aggregator for multi-account monitoring",
            export_name="MultiAccountDiscovery-ConfigAggregator"
        )
        
        cdk.CfnOutput(
            self, "ResourceExplorerIndexArn",
            value=self.resource_explorer_index.attr_index_arn,
            description="ARN of the Resource Explorer aggregated index",
            export_name="MultiAccountDiscovery-ResourceExplorerIndex"
        )


# CDK Application
app = cdk.App()

# Get context values with defaults
project_name = app.node.try_get_context("project_name") or "multi-account-discovery"
environment_name = app.node.try_get_context("environment") or "dev"

# Create stack with descriptive name
stack_name = f"{project_name}-{environment_name}"

MultiAccountResourceDiscoveryStack(
    app, 
    stack_name,
    description="Automated multi-account resource discovery with Resource Explorer and Config",
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region")
    ),
    tags={
        "Project": project_name,
        "Environment": environment_name,
        "Purpose": "MultiAccountResourceDiscovery",
        "ManagedBy": "CDK"
    }
)

app.synth()