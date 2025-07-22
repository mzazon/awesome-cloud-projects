#!/usr/bin/env python3
"""
AWS CDK Python Application for Automated Data Governance Pipelines
Recipe: Data Governance Pipelines with DataZone

This CDK application deploys a comprehensive data governance solution that includes:
- Amazon DataZone domain and project for centralized data cataloging
- AWS Config for compliance monitoring with custom rules
- EventBridge for event-driven automation
- Lambda function for governance processing
- CloudWatch monitoring and SNS alerts
"""

import os
from typing import Dict, Any, Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    Stack,
    StackProps,
    Environment,
    Duration,
    RemovalPolicy,
    CfnOutput,
    Tags,
)
from aws_cdk import aws_datazone as datazone
from aws_cdk import aws_config as config
from aws_cdk import aws_events as events
from aws_cdk import aws_events_targets as targets
from aws_cdk import aws_lambda as lambda_
from aws_cdk import aws_iam as iam
from aws_cdk import aws_s3 as s3
from aws_cdk import aws_sns as sns
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_logs as logs
from constructs import Construct


class DataGovernancePipelineStack(Stack):
    """
    CDK Stack for Automated Data Governance Pipeline
    
    Creates a complete governance solution integrating DataZone, Config,
    EventBridge, and Lambda for automated compliance monitoring and response.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        domain_name: Optional[str] = None,
        project_name: Optional[str] = None,
        notification_email: Optional[str] = None,
        **kwargs: Any
    ) -> None:
        """
        Initialize the Data Governance Pipeline Stack
        
        Args:
            scope: CDK app or parent construct
            construct_id: Unique identifier for this stack
            domain_name: Name for the DataZone domain
            project_name: Name for the DataZone project
            notification_email: Email address for governance alerts
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[-8:].lower()
        
        # Set default values with unique suffix
        self.domain_name = domain_name or f"governance-domain-{unique_suffix}"
        self.project_name = project_name or f"governance-project-{unique_suffix}"
        self.notification_email = notification_email

        # Create core governance infrastructure
        self._create_config_resources()
        self._create_datazone_resources()
        self._create_governance_automation()
        self._create_monitoring_and_alerting()
        
        # Add stack-level tags
        Tags.of(self).add("Project", "DataGovernancePipeline")
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("Owner", "DataGovernanceTeam")

    def _create_config_resources(self) -> None:
        """Create AWS Config resources for compliance monitoring"""
        
        # Create S3 bucket for Config delivery channel
        self.config_bucket = s3.Bucket(
            self,
            "ConfigBucket",
            bucket_name=f"aws-config-bucket-{self.account}-{self.node.addr[-8:].lower()}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Create IAM role for AWS Config
        self.config_role = iam.Role(
            self,
            "ConfigRole",
            role_name=f"DataGovernanceConfigRole-{self.node.addr[-8:].lower()}",
            assumed_by=iam.ServicePrincipal("config.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/ConfigRole")
            ],
            description="IAM role for AWS Config service in data governance pipeline"
        )

        # Grant Config access to S3 bucket
        self.config_bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AWSConfigBucketPermissionsCheck",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("config.amazonaws.com")],
                actions=["s3:GetBucketAcl", "s3:ListBucket"],
                resources=[self.config_bucket.bucket_arn],
                conditions={
                    "StringEquals": {
                        "AWS:SourceAccount": self.account
                    }
                }
            )
        )

        self.config_bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AWSConfigBucketExistenceCheck",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("config.amazonaws.com")],
                actions=["s3:PutObject"],
                resources=[f"{self.config_bucket.bucket_arn}/AWSLogs/{self.account}/Config/*"],
                conditions={
                    "StringEquals": {
                        "s3:x-amz-acl": "bucket-owner-full-control",
                        "AWS:SourceAccount": self.account
                    }
                }
            )
        )

        # Create Config configuration recorder
        self.config_recorder = config.CfnConfigurationRecorder(
            self,
            "ConfigRecorder",
            name="default",
            role_arn=self.config_role.role_arn,
            recording_group=config.CfnConfigurationRecorder.RecordingGroupProperty(
                all_supported=True,
                include_global_resource_types=True,
                recording_mode_overrides=[]
            )
        )

        # Create Config delivery channel
        self.config_delivery_channel = config.CfnDeliveryChannel(
            self,
            "ConfigDeliveryChannel",
            name="default",
            s3_bucket_name=self.config_bucket.bucket_name
        )

        # Ensure proper dependency order
        self.config_delivery_channel.add_dependency(self.config_recorder)

        # Create Config rules for data governance
        self._create_config_rules()

    def _create_config_rules(self) -> None:
        """Create AWS Config rules for compliance monitoring"""
        
        # Config rule for S3 bucket encryption
        self.s3_encryption_rule = config.CfnConfigRule(
            self,
            "S3EncryptionRule",
            config_rule_name="s3-bucket-server-side-encryption-enabled",
            description="Checks if S3 buckets have server-side encryption enabled",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS",
                source_identifier="S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"
            ),
            scope=config.CfnConfigRule.ScopeProperty(
                compliance_resource_types=["AWS::S3::Bucket"]
            )
        )
        self.s3_encryption_rule.add_dependency(self.config_recorder)

        # Config rule for RDS encryption
        self.rds_encryption_rule = config.CfnConfigRule(
            self,
            "RDSEncryptionRule",
            config_rule_name="rds-storage-encrypted",
            description="Checks if RDS instances have storage encryption enabled",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS",
                source_identifier="RDS_STORAGE_ENCRYPTED"
            ),
            scope=config.CfnConfigRule.ScopeProperty(
                compliance_resource_types=["AWS::RDS::DBInstance"]
            )
        )
        self.rds_encryption_rule.add_dependency(self.config_recorder)

        # Config rule for S3 public read access
        self.s3_public_read_rule = config.CfnConfigRule(
            self,
            "S3PublicReadRule",
            config_rule_name="s3-bucket-public-read-prohibited",
            description="Checks if S3 buckets prohibit public read access",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS",
                source_identifier="S3_BUCKET_PUBLIC_READ_PROHIBITED"
            ),
            scope=config.CfnConfigRule.ScopeProperty(
                compliance_resource_types=["AWS::S3::Bucket"]
            )
        )
        self.s3_public_read_rule.add_dependency(self.config_recorder)

    def _create_datazone_resources(self) -> None:
        """Create Amazon DataZone domain and project"""
        
        # Create DataZone domain
        self.datazone_domain = datazone.CfnDomain(
            self,
            "DataZoneDomain",
            name=self.domain_name,
            description="Automated data governance domain for centralized data management",
            domain_execution_role=f"arn:aws:iam::{self.account}:role/AmazonDataZoneServiceRole"
        )

        # Create DataZone project
        self.datazone_project = datazone.CfnProject(
            self,
            "DataZoneProject",
            domain_identifier=self.datazone_domain.attr_id,
            name=self.project_name,
            description="Automated data governance and compliance project"
        )

    def _create_governance_automation(self) -> None:
        """Create Lambda function and EventBridge rules for governance automation"""
        
        # Create IAM role for Lambda function
        self.lambda_role = iam.Role(
            self,
            "GovernanceLambdaRole",
            role_name=f"DataGovernanceLambdaRole-{self.node.addr[-8:].lower()}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ],
            inline_policies={
                "DataGovernancePolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "datazone:Get*",
                                "datazone:List*",
                                "datazone:Search*",
                                "datazone:UpdateAsset",
                                "config:GetComplianceDetailsByConfigRule",
                                "config:GetResourceConfigHistory",
                                "config:GetComplianceDetailsByResource",
                                "sns:Publish",
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            },
            description="IAM role for data governance Lambda function"
        )

        # Create Lambda function for governance processing
        self.governance_function = lambda_.Function(
            self,
            "GovernanceFunction",
            function_name=f"data-governance-processor-{self.node.addr[-8:].lower()}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            role=self.lambda_role,
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.minutes(5),
            memory_size=512,
            description="Data governance automation processor",
            environment={
                "LOG_LEVEL": "INFO",
                "AWS_ACCOUNT_ID": self.account,
                "AWS_REGION": self.region,
                "DATAZONE_DOMAIN_ID": self.datazone_domain.attr_id
            },
            log_retention=logs.RetentionDays.ONE_WEEK
        )

        # Create EventBridge rule for Config compliance changes
        self.governance_rule = events.Rule(
            self,
            "GovernanceEventRule",
            rule_name=f"data-governance-events-{self.node.addr[-8:].lower()}",
            description="Route data governance events to Lambda processor",
            event_pattern=events.EventPattern(
                source=["aws.config"],
                detail_type=["Config Rules Compliance Change"],
                detail={
                    "newEvaluationResult": {
                        "complianceType": ["NON_COMPLIANT", "COMPLIANT"]
                    },
                    "configRuleName": [
                        "s3-bucket-server-side-encryption-enabled",
                        "rds-storage-encrypted",
                        "s3-bucket-public-read-prohibited"
                    ]
                }
            ),
            enabled=True
        )

        # Add Lambda function as target for EventBridge rule
        self.governance_rule.add_target(
            targets.LambdaFunction(
                self.governance_function,
                retry_attempts=3,
                max_event_age=Duration.hours(1)
            )
        )

    def _create_monitoring_and_alerting(self) -> None:
        """Create CloudWatch monitoring and SNS alerting"""
        
        # Create SNS topic for governance alerts
        self.governance_topic = sns.Topic(
            self,
            "GovernanceAlertsTopic",
            topic_name=f"data-governance-alerts-{self.node.addr[-8:].lower()}",
            display_name="Data Governance Alerts",
            description="SNS topic for data governance pipeline alerts"
        )

        # Subscribe email address if provided
        if self.notification_email:
            self.governance_topic.add_subscription(
                sns.Subscription(
                    self,
                    "EmailSubscription",
                    endpoint=self.notification_email,
                    protocol=sns.SubscriptionProtocol.EMAIL
                )
            )

        # CloudWatch alarm for Lambda function errors
        self.lambda_error_alarm = cloudwatch.Alarm(
            self,
            "LambdaErrorAlarm",
            alarm_name=f"DataGovernanceErrors-{self.node.addr[-8:].lower()}",
            alarm_description="Monitor Lambda function errors in governance pipeline",
            metric=self.governance_function.metric_errors(
                period=Duration.minutes(5),
                statistic="Sum"
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        self.lambda_error_alarm.add_alarm_action(
            cloudwatch.AlarmAction.sns_topic(self.governance_topic)
        )

        # CloudWatch alarm for Lambda function duration
        self.lambda_duration_alarm = cloudwatch.Alarm(
            self,
            "LambdaDurationAlarm",
            alarm_name=f"DataGovernanceDuration-{self.node.addr[-8:].lower()}",
            alarm_description="Monitor Lambda function execution duration",
            metric=self.governance_function.metric_duration(
                period=Duration.minutes(5),
                statistic="Average"
            ),
            threshold=240000,  # 4 minutes in milliseconds
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        self.lambda_duration_alarm.add_alarm_action(
            cloudwatch.AlarmAction.sns_topic(self.governance_topic)
        )

        # Create outputs for key resources
        self._create_stack_outputs()

    def _create_stack_outputs(self) -> None:
        """Create CloudFormation outputs for key resources"""
        
        CfnOutput(
            self,
            "DataZoneDomainId",
            value=self.datazone_domain.attr_id,
            description="DataZone domain identifier for data governance",
            export_name=f"{self.stack_name}-DataZoneDomainId"
        )

        CfnOutput(
            self,
            "DataZoneProjectId",
            value=self.datazone_project.attr_id,
            description="DataZone project identifier for governance workflows",
            export_name=f"{self.stack_name}-DataZoneProjectId"
        )

        CfnOutput(
            self,
            "ConfigBucketName",
            value=self.config_bucket.bucket_name,
            description="S3 bucket name for AWS Config delivery channel",
            export_name=f"{self.stack_name}-ConfigBucketName"
        )

        CfnOutput(
            self,
            "GovernanceFunctionName",
            value=self.governance_function.function_name,
            description="Lambda function name for governance automation",
            export_name=f"{self.stack_name}-GovernanceFunctionName"
        )

        CfnOutput(
            self,
            "GovernanceTopicArn",
            value=self.governance_topic.topic_arn,
            description="SNS topic ARN for governance alerts",
            export_name=f"{self.stack_name}-GovernanceTopicArn"
        )

        CfnOutput(
            self,
            "EventBridgeRuleName",
            value=self.governance_rule.rule_name,
            description="EventBridge rule name for governance automation",
            export_name=f"{self.stack_name}-EventBridgeRuleName"
        )

    def _get_lambda_code(self) -> str:
        """Return the Lambda function code for governance processing"""
        return '''
import json
import boto3
import logging
from datetime import datetime
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Process governance events and update DataZone metadata"""
    
    try:
        logger.info(f"Received event: {json.dumps(event, default=str)}")
        
        # Parse EventBridge event structure
        detail = event.get('detail', {})
        config_item = detail.get('configurationItem', {})
        compliance_result = detail.get('newEvaluationResult', {})
        compliance_type = compliance_result.get('complianceType', 'UNKNOWN')
        
        resource_type = config_item.get('resourceType', '')
        resource_id = config_item.get('resourceId', '')
        resource_arn = config_item.get('arn', '')
        
        logger.info(f"Processing governance event for {resource_type}: {resource_id}")
        logger.info(f"Compliance status: {compliance_type}")
        
        # Initialize AWS clients with error handling
        try:
            datazone_client = boto3.client('datazone')
            config_client = boto3.client('config')
            sns_client = boto3.client('sns')
        except Exception as e:
            logger.error(f"Failed to initialize AWS clients: {str(e)}")
            raise
        
        # Create governance metadata
        governance_metadata = {
            'resourceId': resource_id,
            'resourceType': resource_type,
            'resourceArn': resource_arn,
            'complianceStatus': compliance_type,
            'evaluationTimestamp': compliance_result.get('resultRecordedTime', ''),
            'configRuleName': compliance_result.get('configRuleName', ''),
            'awsAccountId': detail.get('awsAccountId', ''),
            'awsRegion': detail.get('awsRegion', ''),
            'processedAt': datetime.utcnow().isoformat()
        }
        
        # Log governance event for audit trail
        logger.info(f"Governance metadata: {json.dumps(governance_metadata, default=str)}")
        
        # Process compliance violations
        if compliance_type == 'NON_COMPLIANT':
            logger.warning(f"Compliance violation detected for {resource_type}: {resource_id}")
            
            # In production, implement specific remediation logic:
            # 1. Update DataZone asset metadata with compliance status
            # 2. Create governance incidents in tracking systems
            # 3. Trigger automated remediation workflows
            # 4. Send notifications to data stewards
            # 5. Update compliance dashboards
            
            violation_summary = {
                'violationType': 'COMPLIANCE_VIOLATION',
                'severity': 'HIGH' if 'encryption' in compliance_result.get('configRuleName', '') else 'MEDIUM',
                'resource': resource_id,
                'rule': compliance_result.get('configRuleName', ''),
                'requiresAttention': True
            }
            
            logger.info(f"Violation summary: {json.dumps(violation_summary)}")
        
        # Prepare response
        response_body = {
            'statusCode': 200,
            'message': 'Governance event processed successfully',
            'metadata': governance_metadata,
            'processedResources': 1
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps(response_body, default=str)
        }
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        logger.error(f"AWS service error ({error_code}): {error_message}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'AWS service error: {error_code}',
                'message': error_message
            })
        }
        
    except Exception as e:
        logger.error(f"Unexpected error processing governance event: {str(e)}", exc_info=True)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal processing error',
                'message': str(e)
            })
        }
'''


def main() -> None:
    """Main function to create and deploy the CDK application"""
    app = App()

    # Get configuration from environment variables or context
    account = os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    
    # Get optional configuration from context
    domain_name = app.node.try_get_context("domain_name")
    project_name = app.node.try_get_context("project_name")
    notification_email = app.node.try_get_context("notification_email")

    # Create the data governance pipeline stack
    governance_stack = DataGovernancePipelineStack(
        app,
        "DataGovernancePipelineStack",
        domain_name=domain_name,
        project_name=project_name,
        notification_email=notification_email,
        env=Environment(account=account, region=region),
        description="Automated Data Governance Pipeline with DataZone and Config",
        stack_name="DataGovernancePipeline"
    )

    # Add application-level tags
    Tags.of(app).add("Application", "DataGovernancePipeline")
    Tags.of(app).add("CDKVersion", cdk.App.version())

    # Synthesize the CDK application
    app.synth()


if __name__ == "__main__":
    main()