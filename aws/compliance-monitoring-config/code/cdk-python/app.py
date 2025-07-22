#!/usr/bin/env python3
"""
AWS CDK Python application for Compliance Monitoring with AWS Config.

This CDK application creates a comprehensive compliance monitoring system using AWS Config
to continuously track resource configurations, evaluate compliance against predefined rules,
and automatically remediate violations.

Author: Generated from AWS recipe "compliance-monitoring-aws-config"
"""

import os
from typing import Dict, List

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_config as config,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_s3 as s3,
    aws_sns as sns,
    aws_events as events,
    aws_events_targets as targets,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    Tags,
)
from constructs import Construct


class ComplianceMonitoringStack(Stack):
    """
    CDK Stack for AWS Config Compliance Monitoring.
    
    This stack creates:
    - AWS Config service with delivery channel
    - S3 bucket for Config data storage
    - SNS topic for notifications
    - AWS managed and custom Config rules
    - Lambda functions for custom rules and remediation
    - CloudWatch dashboard and alarms
    - EventBridge rules for automated remediation
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters
        self.environment_name = cdk.CfnParameter(
            self,
            "EnvironmentName",
            type="String",
            default="dev",
            description="Environment name for resource tagging",
            allowed_values=["dev", "staging", "prod"]
        )

        self.notification_email = cdk.CfnParameter(
            self,
            "NotificationEmail",
            type="String",
            description="Email address for compliance notifications (optional)",
            default=""
        )

        self.enable_remediation = cdk.CfnParameter(
            self,
            "EnableRemediation",
            type="String",
            default="true",
            description="Enable automatic remediation of compliance violations",
            allowed_values=["true", "false"]
        )

        # Create foundational resources
        self._create_s3_bucket()
        self._create_sns_topic()
        self._create_config_service_role()
        self._create_config_service()
        
        # Create compliance rules
        self._create_aws_managed_rules()
        self._create_custom_lambda_rule()
        
        # Create remediation system
        if self.enable_remediation.value_as_string == "true":
            self._create_remediation_system()
        
        # Create monitoring and dashboards
        self._create_cloudwatch_resources()
        
        # Apply tags to all resources
        self._apply_tags()

    def _create_s3_bucket(self) -> None:
        """Create S3 bucket for AWS Config data storage."""
        self.config_bucket = s3.Bucket(
            self,
            "ConfigBucket",
            bucket_name=f"aws-config-bucket-{self.account}-{cdk.Aws.REGION}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ConfigDataLifecycle",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.STANDARD_IA,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ],
                    expiration=Duration.days(365)
                )
            ]
        )

    def _create_sns_topic(self) -> None:
        """Create SNS topic for compliance notifications."""
        self.config_topic = sns.Topic(
            self,
            "ConfigTopic",
            topic_name=f"config-compliance-notifications-{self.environment_name.value_as_string}",
            display_name="AWS Config Compliance Notifications"
        )

        # Add email subscription if provided
        if self.notification_email.value_as_string:
            sns.Subscription(
                self,
                "EmailSubscription",
                topic=self.config_topic,
                endpoint=self.notification_email.value_as_string,
                protocol=sns.SubscriptionProtocol.EMAIL
            )

    def _create_config_service_role(self) -> None:
        """Create IAM role for AWS Config service."""
        self.config_role = iam.Role(
            self,
            "ConfigServiceRole",
            role_name=f"ConfigServiceRole-{self.environment_name.value_as_string}",
            assumed_by=iam.ServicePrincipal("config.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/ConfigRole")
            ]
        )

        # Add S3 bucket permissions
        self.config_bucket.grant_read_write(self.config_role)
        
        # Add SNS topic permissions
        self.config_topic.grant_publish(self.config_role)

    def _create_config_service(self) -> None:
        """Create AWS Config configuration recorder and delivery channel."""
        # Configuration recorder
        self.config_recorder = config.CfnConfigurationRecorder(
            self,
            "ConfigRecorder",
            name="default",
            role_arn=self.config_role.role_arn,
            recording_group=config.CfnConfigurationRecorder.RecordingGroupProperty(
                all_supported=True,
                include_global_resource_types=True,
                recording_mode=config.CfnConfigurationRecorder.RecordingModeProperty(
                    recording_frequency="CONTINUOUS",
                    recording_mode_overrides=[
                        config.CfnConfigurationRecorder.RecordingModeOverrideProperty(
                            resource_types=["AWS::EC2::Instance"],
                            recording_frequency="DAILY"
                        )
                    ]
                )
            )
        )

        # Delivery channel
        self.delivery_channel = config.CfnDeliveryChannel(
            self,
            "ConfigDeliveryChannel",
            name="default",
            s3_bucket_name=self.config_bucket.bucket_name,
            sns_topic_arn=self.config_topic.topic_arn,
            config_snapshot_delivery_properties=config.CfnDeliveryChannel.ConfigSnapshotDeliveryPropertiesProperty(
                delivery_frequency="TwentyFour_Hours"
            )
        )

        # Ensure proper dependencies
        self.delivery_channel.add_dependency(self.config_recorder)

    def _create_aws_managed_rules(self) -> None:
        """Create AWS managed Config rules for common compliance checks."""
        self.managed_rules: List[config.CfnConfigRule] = []

        # S3 bucket public access prohibited
        s3_rule = config.CfnConfigRule(
            self,
            "S3BucketPublicAccessProhibited",
            config_rule_name="s3-bucket-public-access-prohibited",
            description="Checks that S3 buckets do not allow public access",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS",
                source_identifier="S3_BUCKET_PUBLIC_ACCESS_PROHIBITED"
            ),
            scope=config.CfnConfigRule.ScopeProperty(
                compliance_resource_types=["AWS::S3::Bucket"]
            )
        )
        s3_rule.add_dependency(self.config_recorder)
        self.managed_rules.append(s3_rule)

        # Encrypted EBS volumes
        ebs_rule = config.CfnConfigRule(
            self,
            "EncryptedVolumes",
            config_rule_name="encrypted-volumes",
            description="Checks whether EBS volumes are encrypted",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS",
                source_identifier="ENCRYPTED_VOLUMES"
            ),
            scope=config.CfnConfigRule.ScopeProperty(
                compliance_resource_types=["AWS::EC2::Volume"]
            )
        )
        ebs_rule.add_dependency(self.config_recorder)
        self.managed_rules.append(ebs_rule)

        # Root access key check
        root_key_rule = config.CfnConfigRule(
            self,
            "RootAccessKeyCheck",
            config_rule_name="root-access-key-check",
            description="Checks whether root access keys exist",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS",
                source_identifier="ROOT_ACCESS_KEY_CHECK"
            )
        )
        root_key_rule.add_dependency(self.config_recorder)
        self.managed_rules.append(root_key_rule)

        # Required tags for EC2 instances
        tags_rule = config.CfnConfigRule(
            self,
            "RequiredTagsEC2",
            config_rule_name="required-tags-ec2",
            description="Checks whether EC2 instances have required tags",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS",
                source_identifier="REQUIRED_TAGS"
            ),
            scope=config.CfnConfigRule.ScopeProperty(
                compliance_resource_types=["AWS::EC2::Instance"]
            ),
            input_parameters='{"tag1Key":"Environment","tag2Key":"Owner"}'
        )
        tags_rule.add_dependency(self.config_recorder)
        self.managed_rules.append(tags_rule)

    def _create_custom_lambda_rule(self) -> None:
        """Create custom Lambda-based Config rule for security group evaluation."""
        # IAM role for custom rule Lambda
        self.lambda_role = iam.Role(
            self,
            "ConfigLambdaRole",
            role_name=f"ConfigLambdaRole-{self.environment_name.value_as_string}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole"),
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSConfigRulesExecutionRole")
            ]
        )

        # Lambda function for custom Config rule
        self.custom_rule_lambda = lambda_.Function(
            self,
            "CustomConfigRuleLambda",
            function_name=f"ConfigSecurityGroupRule-{self.environment_name.value_as_string}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=self.lambda_role,
            timeout=Duration.seconds(60),
            memory_size=256,
            code=lambda_.Code.from_inline(self._get_custom_rule_code()),
            log_retention=logs.RetentionDays.ONE_MONTH
        )

        # Grant Config permission to invoke Lambda
        self.custom_rule_lambda.add_permission(
            "ConfigPermission",
            principal=iam.ServicePrincipal("config.amazonaws.com"),
            action="lambda:InvokeFunction",
            source_account=self.account
        )

        # Custom Config rule
        self.custom_rule = config.CfnConfigRule(
            self,
            "SecurityGroupRestrictedIngress",
            config_rule_name="security-group-restricted-ingress",
            description="Checks that security groups do not allow unrestricted ingress except for ports 80 and 443",
            source=config.CfnConfigRule.SourceProperty(
                owner="CUSTOM_LAMBDA",
                source_identifier=self.custom_rule_lambda.function_arn,
                source_details=[
                    config.CfnConfigRule.SourceDetailProperty(
                        event_source="aws.config",
                        message_type="ConfigurationItemChangeNotification"
                    )
                ]
            ),
            scope=config.CfnConfigRule.ScopeProperty(
                compliance_resource_types=["AWS::EC2::SecurityGroup"]
            )
        )
        self.custom_rule.add_dependency(self.config_recorder)

    def _create_remediation_system(self) -> None:
        """Create automated remediation system with Lambda and EventBridge."""
        # IAM role for remediation Lambda
        self.remediation_role = iam.Role(
            self,
            "ConfigRemediationRole",
            role_name=f"ConfigRemediationRole-{self.environment_name.value_as_string}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ]
        )

        # Add specific permissions for remediation actions
        self.remediation_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ec2:DescribeInstances",
                    "ec2:CreateTags",
                    "ec2:AuthorizeSecurityGroupIngress",
                    "ec2:RevokeSecurityGroupIngress",
                    "ec2:DescribeSecurityGroups",
                    "s3:PutBucketPublicAccessBlock",
                    "s3:GetBucketPublicAccessBlock"
                ],
                resources=["*"]
            )
        )

        # Remediation Lambda function
        self.remediation_lambda = lambda_.Function(
            self,
            "ConfigRemediationLambda",
            function_name=f"ConfigRemediation-{self.environment_name.value_as_string}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=self.remediation_role,
            timeout=Duration.seconds(60),
            memory_size=256,
            code=lambda_.Code.from_inline(self._get_remediation_code()),
            log_retention=logs.RetentionDays.ONE_MONTH
        )

        # EventBridge rule for Config compliance changes
        self.compliance_rule = events.Rule(
            self,
            "ConfigComplianceRule",
            rule_name=f"ConfigComplianceRule-{self.environment_name.value_as_string}",
            description="Trigger remediation on Config compliance changes",
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

        # Add Lambda as target for EventBridge rule
        self.compliance_rule.add_target(
            targets.LambdaFunction(self.remediation_lambda)
        )

    def _create_cloudwatch_resources(self) -> None:
        """Create CloudWatch dashboard and alarms for monitoring."""
        # CloudWatch dashboard
        self.dashboard = cloudwatch.Dashboard(
            self,
            "ConfigComplianceDashboard",
            dashboard_name=f"ConfigCompliance-{self.environment_name.value_as_string}"
        )

        # Add widgets to dashboard
        self.dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Config Rule Compliance Status",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/Config",
                        metric_name="ComplianceByConfigRule",
                        dimensions_map={"ConfigRuleName": rule.config_rule_name}
                    ) for rule in self.managed_rules
                ],
                period=Duration.minutes(5),
                statistic="Average"
            ),
            cloudwatch.GraphWidget(
                title="Remediation Function Metrics",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/Lambda",
                        metric_name="Invocations",
                        dimensions_map={"FunctionName": self.remediation_lambda.function_name}
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/Lambda",
                        metric_name="Errors",
                        dimensions_map={"FunctionName": self.remediation_lambda.function_name}
                    )
                ] if hasattr(self, 'remediation_lambda') else [],
                period=Duration.minutes(5)
            ) if hasattr(self, 'remediation_lambda') else cloudwatch.TextWidget(
                markdown="## Remediation Disabled\nAutomatic remediation is disabled for this environment."
            )
        )

        # CloudWatch alarms
        self._create_compliance_alarms()

    def _create_compliance_alarms(self) -> None:
        """Create CloudWatch alarms for compliance monitoring."""
        # Alarm for non-compliant resources
        cloudwatch.Alarm(
            self,
            "NonCompliantResourcesAlarm",
            alarm_name=f"ConfigNonCompliantResources-{self.environment_name.value_as_string}",
            alarm_description="Alert when non-compliant resources are detected",
            metric=cloudwatch.Metric(
                namespace="AWS/Config",
                metric_name="ComplianceByConfigRule",
                statistic="Sum"
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=2,
            period=Duration.minutes(5)
        ).add_alarm_action(
            cloudwatch.SnsAction(self.config_topic)
        )

        # Alarm for remediation function errors (if remediation is enabled)
        if hasattr(self, 'remediation_lambda'):
            cloudwatch.Alarm(
                self,
                "RemediationErrorsAlarm",
                alarm_name=f"ConfigRemediationErrors-{self.environment_name.value_as_string}",
                alarm_description="Alert when remediation function encounters errors",
                metric=cloudwatch.Metric(
                    namespace="AWS/Lambda",
                    metric_name="Errors",
                    dimensions_map={"FunctionName": self.remediation_lambda.function_name},
                    statistic="Sum"
                ),
                threshold=1,
                comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
                evaluation_periods=1,
                period=Duration.minutes(5)
            ).add_alarm_action(
                cloudwatch.SnsAction(self.config_topic)
            )

    def _get_custom_rule_code(self) -> str:
        """Return the custom Config rule Lambda function code."""
        return '''
import boto3
import json

def lambda_handler(event, context):
    """
    Custom Config rule to evaluate security group ingress rules.
    Checks that security groups do not allow unrestricted ingress except for ports 80 and 443.
    """
    # Initialize AWS Config client
    config = boto3.client('config')
    
    # Get configuration item from event
    configuration_item = event['configurationItem']
    
    # Initialize compliance status
    compliance_status = 'COMPLIANT'
    
    # Check if resource is a Security Group
    if configuration_item['resourceType'] == 'AWS::EC2::SecurityGroup':
        # Get security group configuration
        sg_config = configuration_item['configuration']
        
        # Check for overly permissive ingress rules
        for rule in sg_config.get('ipPermissions', []):
            for ip_range in rule.get('ipRanges', []):
                if ip_range.get('cidrIp') == '0.0.0.0/0':
                    # Check if it's not port 80 or 443
                    if rule.get('fromPort') not in [80, 443]:
                        compliance_status = 'NON_COMPLIANT'
                        break
            if compliance_status == 'NON_COMPLIANT':
                break
    
    # Put evaluation result
    config.put_evaluations(
        Evaluations=[
            {
                'ComplianceResourceType': configuration_item['resourceType'],
                'ComplianceResourceId': configuration_item['resourceId'],
                'ComplianceType': compliance_status,
                'OrderingTimestamp': configuration_item['configurationItemCaptureTime']
            }
        ],
        ResultToken=event['resultToken']
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps('Config rule evaluation completed')
    }
'''

    def _get_remediation_code(self) -> str:
        """Return the remediation Lambda function code."""
        return '''
import boto3
import json

def lambda_handler(event, context):
    """
    Automated remediation function for Config compliance violations.
    Handles common violations like missing tags and public S3 access.
    """
    ec2 = boto3.client('ec2')
    s3 = boto3.client('s3')
    
    # Parse the event
    detail = event['detail']
    config_rule_name = detail['configRuleName']
    compliance_type = detail['newEvaluationResult']['complianceType']
    resource_type = detail['resourceType']
    resource_id = detail['resourceId']
    
    print(f"Processing {compliance_type} resource: {resource_type}/{resource_id} for rule: {config_rule_name}")
    
    if compliance_type == 'NON_COMPLIANT':
        try:
            if config_rule_name == 'required-tags-ec2' and resource_type == 'AWS::EC2::Instance':
                # Add missing tags to EC2 instance
                ec2.create_tags(
                    Resources=[resource_id],
                    Tags=[
                        {'Key': 'Environment', 'Value': 'Unknown'},
                        {'Key': 'Owner', 'Value': 'Unknown'}
                    ]
                )
                print(f"Added missing tags to EC2 instance {resource_id}")
            
            elif config_rule_name == 's3-bucket-public-access-prohibited' and resource_type == 'AWS::S3::Bucket':
                # Block public access on S3 bucket
                s3.put_public_access_block(
                    Bucket=resource_id,
                    PublicAccessBlockConfiguration={
                        'BlockPublicAcls': True,
                        'IgnorePublicAcls': True,
                        'BlockPublicPolicy': True,
                        'RestrictPublicBuckets': True
                    }
                )
                print(f"Blocked public access on S3 bucket {resource_id}")
            
            else:
                print(f"No remediation action available for rule: {config_rule_name}")
                
        except Exception as e:
            print(f"Error during remediation: {str(e)}")
            raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps('Remediation completed')
    }
'''

    def _apply_tags(self) -> None:
        """Apply common tags to all resources in the stack."""
        Tags.of(self).add("Environment", self.environment_name.value_as_string)
        Tags.of(self).add("Project", "ComplianceMonitoring")
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("Recipe", "compliance-monitoring-aws-config")


class ComplianceMonitoringApp(cdk.App):
    """CDK Application for Compliance Monitoring."""

    def __init__(self):
        super().__init__()

        # Get environment from context or use defaults
        env = cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        )

        # Create the compliance monitoring stack
        ComplianceMonitoringStack(
            self,
            "ComplianceMonitoringStack",
            env=env,
            description="AWS Config Compliance Monitoring System with automated remediation"
        )


# Create and run the application
if __name__ == "__main__":
    app = ComplianceMonitoringApp()
    app.synth()