#!/usr/bin/env python3
"""
AWS CDK Python Application for Config Auto-Remediation

This CDK application deploys an auto-remediation solution using AWS Config and Lambda
to automatically detect and remediate security and compliance violations.

Author: Auto-generated from recipe
Version: 1.0
"""

import os
from typing import Dict, Any, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    Tags,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_config as config,
    aws_sns as sns,
    aws_ssm as ssm,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from constructs import Construct


class ConfigRemediationStack(Stack):
    """
    CDK Stack for AWS Config Auto-Remediation Solution
    
    This stack creates:
    - AWS Config with configuration recorder and delivery channel
    - Lambda functions for custom remediation logic
    - Config rules for compliance monitoring
    - SNS topics for notifications
    - CloudWatch dashboard for monitoring
    - IAM roles with least privilege permissions
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        env: Environment,
        config: Optional[Dict[str, Any]] = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, env=env, **kwargs)

        # Configuration with defaults
        self.config = config or {}
        self.random_suffix = self.config.get('random_suffix', cdk.Names.unique_id(self)[-6:].lower())
        
        # Create foundational resources
        self.s3_bucket = self._create_config_bucket()
        self.config_role = self._create_config_service_role()
        self.lambda_role = self._create_lambda_execution_role()
        
        # Create notification infrastructure
        self.sns_topic = self._create_sns_topic()
        
        # Create Lambda functions for remediation
        self.sg_remediation_lambda = self._create_security_group_remediation_lambda()
        
        # Set up AWS Config
        self.config_recorder = self._create_config_recorder()
        self.delivery_channel = self._create_delivery_channel()
        
        # Create Config rules with remediation
        self.config_rules = self._create_config_rules()
        self.remediation_configs = self._create_remediation_configurations()
        
        # Create monitoring and dashboards
        self.dashboard = self._create_cloudwatch_dashboard()
        
        # Create outputs
        self._create_outputs()
        
        # Apply tags to all resources
        self._apply_tags()

    def _create_config_bucket(self) -> s3.Bucket:
        """Create S3 bucket for AWS Config with appropriate policies."""
        bucket = s3.Bucket(
            self,
            "ConfigBucket",
            bucket_name=f"aws-config-bucket-{self.random_suffix}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            versioned=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ConfigLogRetention",
                    expiration=Duration.days(365),
                    noncurrent_version_expiration=Duration.days(90),
                )
            ],
        )

        # Add bucket policy for AWS Config service
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AWSConfigBucketPermissionsCheck",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("config.amazonaws.com")],
                actions=["s3:GetBucketAcl"],
                resources=[bucket.bucket_arn],
                conditions={
                    "StringEquals": {
                        "AWS:SourceAccount": self.account
                    }
                }
            )
        )

        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AWSConfigBucketExistenceCheck",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("config.amazonaws.com")],
                actions=["s3:ListBucket"],
                resources=[bucket.bucket_arn],
                conditions={
                    "StringEquals": {
                        "AWS:SourceAccount": self.account
                    }
                }
            )
        )

        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AWSConfigBucketDelivery",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("config.amazonaws.com")],
                actions=["s3:PutObject"],
                resources=[f"{bucket.bucket_arn}/AWSLogs/{self.account}/Config/*"],
                conditions={
                    "StringEquals": {
                        "s3:x-amz-acl": "bucket-owner-full-control",
                        "AWS:SourceAccount": self.account
                    }
                }
            )
        )

        return bucket

    def _create_config_service_role(self) -> iam.Role:
        """Create IAM role for AWS Config service."""
        role = iam.Role(
            self,
            "ConfigServiceRole",
            role_name=f"AWSConfigRole-{self.random_suffix}",
            assumed_by=iam.ServicePrincipal("config.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/ConfigRole")
            ],
            description="IAM role for AWS Config service to record configuration changes",
        )

        return role

    def _create_lambda_execution_role(self) -> iam.Role:
        """Create IAM role for Lambda remediation functions."""
        role = iam.Role(
            self,
            "LambdaExecutionRole",
            role_name=f"ConfigRemediationRole-{self.random_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ],
            description="IAM role for Lambda functions performing Config remediation",
        )

        # Add custom policy for remediation actions
        remediation_policy = iam.Policy(
            self,
            "RemediationPolicy",
            policy_name=f"ConfigRemediationPolicy-{self.random_suffix}",
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "ec2:DescribeSecurityGroups",
                        "ec2:AuthorizeSecurityGroupIngress",
                        "ec2:RevokeSecurityGroupIngress",
                        "ec2:AuthorizeSecurityGroupEgress",
                        "ec2:RevokeSecurityGroupEgress",
                        "ec2:CreateTags",
                    ],
                    resources=["*"],
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:GetBucketAcl",
                        "s3:GetBucketPolicy",
                        "s3:PutBucketAcl",
                        "s3:PutBucketPolicy",
                        "s3:DeleteBucketPolicy",
                        "s3:PutPublicAccessBlock",
                    ],
                    resources=["*"],
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=["config:PutEvaluations"],
                    resources=["*"],
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=["sns:Publish"],
                    resources=["*"],
                ),
            ],
        )

        role.attach_inline_policy(remediation_policy)
        return role

    def _create_sns_topic(self) -> sns.Topic:
        """Create SNS topic for compliance notifications."""
        topic = sns.Topic(
            self,
            "ComplianceAlertsTopic",
            topic_name=f"config-compliance-alerts-{self.random_suffix}",
            display_name="Config Compliance Alerts",
            description="SNS topic for AWS Config compliance and remediation notifications",
        )

        return topic

    def _create_security_group_remediation_lambda(self) -> lambda_.Function:
        """Create Lambda function for security group remediation."""
        # Create log group with retention policy
        log_group = logs.LogGroup(
            self,
            "SGRemediationLogGroup",
            log_group_name=f"/aws/lambda/SecurityGroupRemediation-{self.random_suffix}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

        function = lambda_.Function(
            self,
            "SecurityGroupRemediationFunction",
            function_name=f"SecurityGroupRemediation-{self.random_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=self.lambda_role,
            timeout=Duration.minutes(1),
            memory_size=256,
            description="Auto-remediate security groups with unrestricted access",
            environment={
                "SNS_TOPIC_ARN": self.sns_topic.topic_arn,
                "LOG_LEVEL": "INFO",
            },
            log_group=log_group,
            code=lambda_.Code.from_inline('''
import json
import boto3
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

ec2 = boto3.client('ec2')
sns = boto3.client('sns')

def lambda_handler(event, context):
    """
    Remediate security groups that allow unrestricted access (0.0.0.0/0)
    """
    
    try:
        # Parse the Config rule evaluation
        config_item = event['configurationItem']
        resource_id = config_item['resourceId']
        resource_type = config_item['resourceType']
        
        logger.info(f"Processing remediation for {resource_type}: {resource_id}")
        
        if resource_type != 'AWS::EC2::SecurityGroup':
            return {
                'statusCode': 400,
                'body': json.dumps('This function only handles Security Groups')
            }
        
        # Get security group details
        response = ec2.describe_security_groups(GroupIds=[resource_id])
        security_group = response['SecurityGroups'][0]
        
        remediation_actions = []
        
        # Check inbound rules for unrestricted access
        for rule in security_group['IpPermissions']:
            for ip_range in rule.get('IpRanges', []):
                if ip_range.get('CidrIp') == '0.0.0.0/0':
                    # Remove unrestricted inbound rule
                    try:
                        ec2.revoke_security_group_ingress(
                            GroupId=resource_id,
                            IpPermissions=[rule]
                        )
                        remediation_actions.append(f"Removed unrestricted inbound rule: {rule}")
                        logger.info(f"Removed unrestricted inbound rule from {resource_id}")
                    except Exception as e:
                        logger.error(f"Failed to remove inbound rule: {e}")
        
        # Add tag to indicate remediation
        ec2.create_tags(
            Resources=[resource_id],
            Tags=[
                {
                    'Key': 'AutoRemediated',
                    'Value': 'true'
                },
                {
                    'Key': 'RemediationDate',
                    'Value': datetime.now().isoformat()
                }
            ]
        )
        
        # Send notification if remediation occurred
        if remediation_actions:
            message = {
                'resource_id': resource_id,
                'resource_type': resource_type,
                'remediation_actions': remediation_actions,
                'timestamp': datetime.now().isoformat()
            }
            
            # Publish to SNS topic
            topic_arn = os.environ.get('SNS_TOPIC_ARN')
            if topic_arn:
                sns.publish(
                    TopicArn=topic_arn,
                    Subject=f'Security Group Auto-Remediation: {resource_id}',
                    Message=json.dumps(message, indent=2)
                )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Remediation completed',
                'resource_id': resource_id,
                'actions_taken': len(remediation_actions)
            })
        }
        
    except Exception as e:
        logger.error(f"Error in remediation: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
            '''),
        )

        # Grant SNS publish permissions
        self.sns_topic.grant_publish(function)

        return function

    def _create_config_recorder(self) -> config.CfnConfigurationRecorder:
        """Create AWS Config configuration recorder."""
        recorder = config.CfnConfigurationRecorder(
            self,
            "ConfigurationRecorder",
            name="default",
            role_arn=self.config_role.role_arn,
            recording_group=config.CfnConfigurationRecorder.RecordingGroupProperty(
                all_supported=True,
                include_global_resource_types=True,
                recording_mode_overrides=[
                    config.CfnConfigurationRecorder.RecordingModeOverrideProperty(
                        resource_types=["AWS::EC2::SecurityGroup"],
                        recording_mode=config.CfnConfigurationRecorder.RecordingModeProperty(
                            recording_frequency="CONTINUOUS"
                        ),
                    )
                ],
            ),
        )

        recorder.add_dependency(self.config_role.node.default_child)
        return recorder

    def _create_delivery_channel(self) -> config.CfnDeliveryChannel:
        """Create AWS Config delivery channel."""
        channel = config.CfnDeliveryChannel(
            self,
            "DeliveryChannel",
            name="default",
            s3_bucket_name=self.s3_bucket.bucket_name,
            config_snapshot_delivery_properties=config.CfnDeliveryChannel.ConfigSnapshotDeliveryPropertiesProperty(
                delivery_frequency="TwentyFour_Hours"
            ),
        )

        channel.add_dependency(self.s3_bucket.node.default_child)
        return channel

    def _create_config_rules(self) -> Dict[str, config.CfnConfigRule]:
        """Create AWS Config rules for compliance monitoring."""
        rules = {}

        # Security group SSH restriction rule
        rules['ssh_restricted'] = config.CfnConfigRule(
            self,
            "SecurityGroupSSHRestricted",
            config_rule_name="security-group-ssh-restricted",
            description="Checks if security groups allow unrestricted SSH access",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS",
                source_identifier="INCOMING_SSH_DISABLED",
            ),
            scope=config.CfnConfigRule.ScopeProperty(
                compliance_resource_types=["AWS::EC2::SecurityGroup"]
            ),
        )

        # S3 bucket public access rule
        rules['s3_public_access'] = config.CfnConfigRule(
            self,
            "S3BucketPublicAccessProhibited",
            config_rule_name="s3-bucket-public-access-prohibited",
            description="Checks if S3 buckets allow public access",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS",
                source_identifier="S3_BUCKET_PUBLIC_ACCESS_PROHIBITED",
            ),
            scope=config.CfnConfigRule.ScopeProperty(
                compliance_resource_types=["AWS::S3::Bucket"]
            ),
        )

        # Add dependencies
        for rule in rules.values():
            rule.add_dependency(self.config_recorder)

        return rules

    def _create_remediation_configurations(self) -> Dict[str, config.CfnRemediationConfiguration]:
        """Create auto-remediation configurations for Config rules."""
        remediation_configs = {}

        # Create SSM automation document for S3 remediation
        s3_remediation_document = ssm.CfnDocument(
            self,
            "S3RemediationDocument",
            name=f"S3-RemediatePublicAccess-{self.random_suffix}",
            document_type="Automation",
            document_format="JSON",
            content={
                "schemaVersion": "0.3",
                "description": "Remediate S3 bucket public access",
                "assumeRole": self.lambda_role.role_arn,
                "parameters": {
                    "BucketName": {
                        "type": "String",
                        "description": "Name of the S3 bucket to remediate"
                    }
                },
                "mainSteps": [
                    {
                        "name": "RemediateS3PublicAccess",
                        "action": "aws:executeAwsApi",
                        "inputs": {
                            "Service": "s3",
                            "Api": "PutPublicAccessBlock",
                            "BucketName": "{{ BucketName }}",
                            "PublicAccessBlockConfiguration": {
                                "BlockPublicAcls": True,
                                "IgnorePublicAcls": True,
                                "BlockPublicPolicy": True,
                                "RestrictPublicBuckets": True
                            }
                        }
                    }
                ]
            },
        )

        # Security group remediation configuration
        remediation_configs['ssh_restricted'] = config.CfnRemediationConfiguration(
            self,
            "SSHRemediationConfig",
            config_rule_name=self.config_rules['ssh_restricted'].config_rule_name,
            target_type="SSM_DOCUMENT",
            target_id="AWSConfigRemediation-RemoveUnrestrictedSourceInSecurityGroup",
            target_version="1",
            parameters={
                "AutomationAssumeRole": config.CfnRemediationConfiguration.StaticValueProperty(
                    values=[self.lambda_role.role_arn]
                ),
                "GroupId": config.CfnRemediationConfiguration.ResourceValueProperty(
                    value="RESOURCE_ID"
                ),
            },
            automatic=True,
            maximum_automatic_attempts=3,
        )

        # Add dependencies
        for remediation_config in remediation_configs.values():
            remediation_config.add_dependency(self.config_rules['ssh_restricted'])

        return remediation_configs

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for compliance monitoring."""
        dashboard = cloudwatch.Dashboard(
            self,
            "ComplianceDashboard",
            dashboard_name=f"Config-Compliance-Dashboard-{self.random_suffix}",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Config Rule Compliance Status",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/Config",
                                metric_name="ComplianceByConfigRule",
                                dimensions_map={
                                    "ConfigRuleName": "security-group-ssh-restricted",
                                    "ComplianceType": "COMPLIANT"
                                },
                                statistic="Maximum",
                                period=Duration.minutes(5),
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/Config",
                                metric_name="ComplianceByConfigRule",
                                dimensions_map={
                                    "ConfigRuleName": "security-group-ssh-restricted",
                                    "ComplianceType": "NON_COMPLIANT"
                                },
                                statistic="Maximum",
                                period=Duration.minutes(5),
                            ),
                        ],
                        width=12,
                        height=6,
                    )
                ],
                [
                    cloudwatch.GraphWidget(
                        title="Remediation Function Metrics",
                        left=[
                            self.sg_remediation_lambda.metric_invocations(
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                            self.sg_remediation_lambda.metric_errors(
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                            self.sg_remediation_lambda.metric_duration(
                                statistic="Average",
                                period=Duration.minutes(5),
                            ),
                        ],
                        width=12,
                        height=6,
                    )
                ],
            ],
        )

        return dashboard

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        CfnOutput(
            self,
            "ConfigBucketName",
            description="Name of the S3 bucket used by AWS Config",
            value=self.s3_bucket.bucket_name,
        )

        CfnOutput(
            self,
            "SNSTopicArn",
            description="ARN of the SNS topic for compliance notifications",
            value=self.sns_topic.topic_arn,
        )

        CfnOutput(
            self,
            "LambdaFunctionArn",
            description="ARN of the security group remediation Lambda function",
            value=self.sg_remediation_lambda.function_arn,
        )

        CfnOutput(
            self,
            "DashboardURL",
            description="URL of the CloudWatch dashboard for compliance monitoring",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
        )

        CfnOutput(
            self,
            "ConfigRoleArn",
            description="ARN of the IAM role used by AWS Config",
            value=self.config_role.role_arn,
        )

    def _apply_tags(self) -> None:
        """Apply consistent tags to all resources in the stack."""
        Tags.of(self).add("Project", "ConfigAutoRemediation")
        Tags.of(self).add("Environment", self.config.get('environment', 'development'))
        Tags.of(self).add("Owner", self.config.get('owner', 'aws-config-team'))
        Tags.of(self).add("CostCenter", self.config.get('cost_center', 'security'))
        Tags.of(self).add("CreatedBy", "CDK")


class ConfigRemediationApp(cdk.App):
    """CDK Application for Config Auto-Remediation."""

    def __init__(self):
        super().__init__()

        # Configuration from environment variables or context
        env_config = {
            'environment': os.environ.get('ENVIRONMENT', self.node.try_get_context('environment') or 'development'),
            'owner': os.environ.get('OWNER', self.node.try_get_context('owner') or 'aws-config-team'),
            'cost_center': os.environ.get('COST_CENTER', self.node.try_get_context('cost_center') or 'security'),
            'random_suffix': os.environ.get('RANDOM_SUFFIX', self.node.try_get_context('random_suffix')),
        }

        # Environment configuration
        env = Environment(
            account=os.environ.get('CDK_DEFAULT_ACCOUNT'),
            region=os.environ.get('CDK_DEFAULT_REGION', 'us-east-1'),
        )

        # Create the stack
        ConfigRemediationStack(
            self,
            "ConfigRemediationStack",
            env=env,
            config=env_config,
            description="AWS Config Auto-Remediation Solution with Lambda functions and monitoring",
        )


def main():
    """Main entry point for the CDK application."""
    app = ConfigRemediationApp()
    app.synth()


if __name__ == "__main__":
    main()