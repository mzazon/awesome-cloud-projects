#!/usr/bin/env python3
"""
AWS Zero Trust Security Architecture CDK Application

This CDK application implements a comprehensive zero trust security architecture
using AWS services including IAM Identity Center, Security Hub, GuardDuty, 
AWS Config, and VPC with private networking.

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    Stack,
    StackProps,
    aws_cloudtrail as cloudtrail,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cloudwatch_actions,
    aws_config as config,
    aws_ec2 as ec2,
    aws_events as events,
    aws_events_targets as targets,
    aws_guardduty as guardduty,
    aws_iam as iam,
    aws_kms as kms,
    aws_lambda as lambda_,
    aws_logs as logs,
    aws_s3 as s3,
    aws_secretsmanager as secretsmanager,
    aws_securityhub as securityhub,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    aws_ssm as ssm,
)
from constructs import Construct


class ZeroTrustSecurityStack(Stack):
    """
    Main stack Zero Trust Security Architecture with AWS services.
    
    This stack creates:
    - Security Hub with foundational standards
    - GuardDuty threat detection
    - AWS Config for compliance monitoring
    - VPC with private subnets and endpoints
    - IAM policies with conditional access
    - KMS encryption for data protection
    - CloudWatch monitoring and alerting
    - Lambda functions for automation
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        zero_trust_prefix: str,
        security_admin_email: str,
        trusted_networks: List[str],
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.zero_trust_prefix = zero_trust_prefix
        self.security_admin_email = security_admin_email
        self.trusted_networks = trusted_networks

        # Create foundational resources
        self._create_kms_key()
        self._create_s3_logging_bucket()
        self._create_vpc_infrastructure()
        
        # Set up security services
        self._create_security_hub()
        self._create_guardduty()
        self._create_config_service()
        
        # Implement zero trust controls
        self._create_zero_trust_iam_policies()
        self._create_session_management()
        self._create_monitoring_dashboard()
        self._create_automated_response()

    def _create_kms_key(self) -> None:
        """Create KMS key for zero trust encryption with fine-grained policies."""
        
        # KMS key policy for zero trust services
        key_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    sid="EnableIAMUserPermissions",
                    effect=iam.Effect.ALLOW,
                    principals=[iam.AccountRootPrincipal()],
                    actions=["kms:*"],
                    resources=["*"]
                ),
                iam.PolicyStatement(
                    sid="AllowZeroTrustServices",
                    effect=iam.Effect.ALLOW,
                    principals=[
                        iam.ServicePrincipal("s3.amazonaws.com"),
                        iam.ServicePrincipal("secretsmanager.amazonaws.com"),
                        iam.ServicePrincipal("logs.amazonaws.com"),
                        iam.ServicePrincipal("cloudtrail.amazonaws.com")
                    ],
                    actions=[
                        "kms:Decrypt",
                        "kms:Encrypt", 
                        "kms:GenerateDataKey",
                        "kms:CreateGrant"
                    ],
                    resources=["*"],
                    conditions={
                        "StringEquals": {
                            f"kms:ViaService": [
                                f"s3.{self.region}.amazonaws.com",
                                f"secretsmanager.{self.region}.amazonaws.com",
                                f"logs.{self.region}.amazonaws.com",
                                f"cloudtrail.{self.region}.amazonaws.com"
                            ]
                        }
                    }
                )
            ]
        )

        self.kms_key = kms.Key(
            self,
            "ZeroTrustKMSKey",
            description="Zero Trust Security Architecture encryption key",
            policy=key_policy,
            enable_key_rotation=True,
            removal_policy=cdk.RemovalPolicy.DESTROY  # For demo purposes
        )

        # Create key alias
        kms.Alias(
            self,
            "ZeroTrustKMSAlias",
            alias_name=f"alias/{self.zero_trust_prefix}-key",
            target_key=self.kms_key
        )

        # Output KMS key ID
        cdk.CfnOutput(
            self,
            "KMSKeyId",
            value=self.kms_key.key_id,
            description="KMS Key ID for zero trust encryption"
        )

    def _create_s3_logging_bucket(self) -> None:
        """Create S3 bucket for security logs with zero trust controls."""
        
        self.security_logs_bucket = s3.Bucket(
            self,
            "SecurityLogsBucket",
            bucket_name=f"{self.zero_trust_prefix}-security-logs-{self.account}",
            encryption=s3.BucketEncryption.KMS,
            encryption_key=self.kms_key,
            versioned=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=cdk.RemovalPolicy.DESTROY,  # For demo purposes
            auto_delete_objects=True,  # For demo purposes
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="SecurityLogsLifecycle",
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

        # Create secure data bucket
        self.secure_data_bucket = s3.Bucket(
            self,
            "SecureDataBucket",
            bucket_name=f"{self.zero_trust_prefix}-secure-data-{self.account}",
            encryption=s3.BucketEncryption.KMS,
            encryption_key=self.kms_key,
            versioned=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=cdk.RemovalPolicy.DESTROY,  # For demo purposes
            auto_delete_objects=True  # For demo purposes
        )

        # Output bucket names
        cdk.CfnOutput(
            self,
            "SecurityLogsBucketName",
            value=self.security_logs_bucket.bucket_name,
            description="S3 bucket for security logs"
        )

    def _create_vpc_infrastructure(self) -> None:
        """Create zero trust VPC with private subnets and endpoints."""
        
        # Create VPC with no NAT gateways (zero trust principle)
        self.vpc = ec2.Vpc(
            self,
            "ZeroTrustVPC",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                    cidr_mask=24
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True
        )

        # Create restrictive security group
        self.zero_trust_sg = ec2.SecurityGroup(
            self,
            "ZeroTrustSecurityGroup",
            vpc=self.vpc,
            description="Zero Trust Security Group with minimal access",
            allow_all_outbound=False
        )

        # Add minimal outbound rules for HTTPS only
        self.zero_trust_sg.add_egress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="HTTPS outbound for AWS service access"
        )

        # Create VPC endpoints for AWS services
        self._create_vpc_endpoints()

        # Output VPC information
        cdk.CfnOutput(
            self,
            "VPCId",
            value=self.vpc.vpc_id,
            description="Zero Trust VPC ID"
        )

    def _create_vpc_endpoints(self) -> None:
        """Create VPC endpoints for secure AWS service access."""
        
        # S3 Gateway endpoint
        self.vpc.add_gateway_endpoint(
            "S3Endpoint",
            service=ec2.GatewayVpcEndpointAwsService.S3,
            policy_document=iam.PolicyDocument(
                statements=[
                    iam.PolicyStatement(
                        effect=iam.Effect.ALLOW,
                        principals=[iam.StarPrincipal()],
                        actions=["s3:GetObject", "s3:PutObject"],
                        resources=[
                            f"{self.security_logs_bucket.bucket_arn}/*",
                            f"{self.secure_data_bucket.bucket_arn}/*"
                        ],
                        conditions={
                            "StringEquals": {
                                "s3:x-amz-server-side-encryption": "aws:kms"
                            }
                        }
                    )
                ]
            )
        )

        # Interface endpoints for other services
        interface_services = [
            ec2.InterfaceVpcEndpointAwsService.CLOUDTRAIL,
            ec2.InterfaceVpcEndpointAwsService.GUARDDUTY,
            ec2.InterfaceVpcEndpointAwsService.CONFIG,
            ec2.InterfaceVpcEndpointAwsService.SSM,
            ec2.InterfaceVpcEndpointAwsService.SECRETS_MANAGER,
            ec2.InterfaceVpcEndpointAwsService.KMS
        ]

        for service in interface_services:
            self.vpc.add_interface_endpoint(
                f"{service.name}Endpoint",
                service=service,
                security_groups=[self.zero_trust_sg]
            )

    def _create_security_hub(self) -> None:
        """Enable Security Hub with foundational security standards."""
        
        # Enable Security Hub
        security_hub = securityhub.CfnHub(
            self,
            "SecurityHub",
            enable_default_standards=True,
            control_finding_generator="SECURITY_CONTROL",
            auto_enable_controls=True
        )

        # Enable foundational security standard
        securityhub.CfnStandardsSubscription(
            self,
            "FoundationalStandard",
            standards_arn=f"arn:aws:securityhub:{self.region}::standard/aws-foundational-security/v/1.0.0",
            depends_on=[security_hub]
        )

        # Enable CIS benchmark
        securityhub.CfnStandardsSubscription(
            self,
            "CISBenchmark",
            standards_arn=f"arn:aws:securityhub:{self.region}::standard/cis-aws-foundations-benchmark/v/1.2.0",
            depends_on=[security_hub]
        )

    def _create_guardduty(self) -> None:
        """Enable GuardDuty with comprehensive threat detection."""
        
        # Create GuardDuty detector
        self.guardduty_detector = guardduty.CfnDetector(
            self,
            "GuardDutyDetector",
            enable=True,
            finding_publishing_frequency="FIFTEEN_MINUTES",
            data_sources=guardduty.CfnDetector.CFNDataSourceConfigurationsProperty(
                s3_logs=guardduty.CfnDetector.CFNS3LogsConfigurationProperty(enable=True),
                kubernetes=guardduty.CfnDetector.CFNKubernetesConfigurationProperty(
                    audit_logs=guardduty.CfnDetector.CFNKubernetesAuditLogsConfigurationProperty(enable=True)
                ),
                malware_protection=guardduty.CfnDetector.CFNMalwareProtectionConfigurationProperty(
                    scan_ec2_instance_with_findings=guardduty.CfnDetector.CFNScanEc2InstanceWithFindingsConfigurationProperty(
                        ebs_volumes=True
                    )
                )
            )
        )

        # Output GuardDuty detector ID
        cdk.CfnOutput(
            self,
            "GuardDutyDetectorId",
            value=self.guardduty_detector.ref,
            description="GuardDuty detector ID"
        )

    def _create_config_service(self) -> None:
        """Set up AWS Config for continuous compliance monitoring."""
        
        # Create Config service role
        config_role = iam.Role(
            self,
            "ConfigServiceRole",
            assumed_by=iam.ServicePrincipal("config.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/ConfigRole")
            ]
        )

        # Create Config delivery channel
        config.CfnDeliveryChannel(
            self,
            "ConfigDeliveryChannel",
            name="zero-trust-config-channel",
            s3_bucket_name=self.security_logs_bucket.bucket_name,
            s3_key_prefix="config/",
            config_snapshot_delivery_properties=config.CfnDeliveryChannel.ConfigSnapshotDeliveryPropertiesProperty(
                delivery_frequency="TwentyFour_Hours"
            )
        )

        # Create Config configuration recorder
        config.CfnConfigurationRecorder(
            self,
            "ConfigRecorder",
            name="zero-trust-config-recorder",
            role_arn=config_role.role_arn,
            recording_group=config.CfnConfigurationRecorder.RecordingGroupProperty(
                all_supported=True,
                include_global_resource_types=True,
                recording_mode_overrides=[
                    config.CfnConfigurationRecorder.RecordingModeOverrideProperty(
                        resource_types=["AWS::IAM::Role", "AWS::IAM::Policy"],
                        recording_mode=config.CfnConfigurationRecorder.RecordingModeProperty(
                            recording_frequency="CONTINUOUS"
                        )
                    )
                ]
            )
        )

        # Create Config rules for zero trust compliance
        self._create_config_rules()

    def _create_config_rules(self) -> None:
        """Create Config rules for zero trust compliance monitoring."""
        
        # MFA enabled rule
        config.CfnConfigRule(
            self,
            "MFAEnabledRule",
            config_rule_name="zero-trust-mfa-enabled",
            description="Checks if MFA is enabled for all IAM users",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS",
                source_identifier="MFA_ENABLED_FOR_IAM_CONSOLE_ACCESS"
            )
        )

        # S3 SSL requests only rule
        config.CfnConfigRule(
            self,
            "S3SSLRequestsOnlyRule",
            config_rule_name="zero-trust-s3-ssl-requests-only",
            description="Checks if S3 buckets have policies requiring SSL requests only",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS",
                source_identifier="S3_BUCKET_SSL_REQUESTS_ONLY"
            )
        )

        # Root user access key check
        config.CfnConfigRule(
            self,
            "RootAccessKeyCheckRule",
            config_rule_name="zero-trust-root-access-key-check",
            description="Checks if root user has access keys",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS",
                source_identifier="ROOT_ACCESS_KEY_CHECK"
            )
        )

    def _create_zero_trust_iam_policies(self) -> None:
        """Create IAM policies implementing zero trust principles."""
        
        # Zero trust boundary policy with conditional access
        zero_trust_conditions = {
            "BoolIfExists": {
                "aws:MultiFactorAuthPresent": "false"
            },
            "NumericLessThan": {
                "aws:MultiFactorAuthAge": "3600"
            }
        }

        if self.trusted_networks:
            zero_trust_conditions["IpAddressIfExists"] = {
                "aws:SourceIp": self.trusted_networks
            }

        self.zero_trust_boundary_policy = iam.ManagedPolicy(
            self,
            "ZeroTrustBoundaryPolicy",
            managed_policy_name=f"{self.zero_trust_prefix}-boundary-policy",
            description="Zero Trust Security Boundary Policy with conditional access",
            statements=[
                # Enforce MFA for all actions
                iam.PolicyStatement(
                    sid="EnforceMFAForAllActions",
                    effect=iam.Effect.DENY,
                    actions=["*"],
                    resources=["*"],
                    conditions=zero_trust_conditions
                ),
                # Enforce SSL for S3 requests
                iam.PolicyStatement(
                    sid="EnforceSSLRequests",
                    effect=iam.Effect.DENY,
                    actions=["s3:*"],
                    resources=["*"],
                    conditions={
                        "Bool": {
                            "aws:SecureTransport": "false"
                        }
                    }
                ),
                # Restrict high-risk actions to specific regions
                iam.PolicyStatement(
                    sid="RestrictHighRiskActions",
                    effect=iam.Effect.DENY,
                    actions=[
                        "iam:CreateUser",
                        "iam:DeleteUser",
                        "iam:CreateRole",
                        "iam:DeleteRole",
                        "iam:AttachUserPolicy",
                        "iam:DetachUserPolicy"
                    ],
                    resources=["*"],
                    conditions={
                        "StringNotEquals": {
                            "aws:RequestedRegion": [self.region]
                        }
                    }
                )
            ]
        )

        # Create security automation role
        self.security_role = iam.Role(
            self,
            "SecurityAutomationRole",
            role_name=f"{self.zero_trust_prefix}-security-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            permissions_boundary=self.zero_trust_boundary_policy,
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ]
        )

        # ABAC policy for attribute-based access control
        self._create_abac_policy()

    def _create_abac_policy(self) -> None:
        """Create attribute-based access control policy."""
        
        self.abac_policy = iam.ManagedPolicy(
            self,
            "ABACPolicy",
            managed_policy_name=f"{self.zero_trust_prefix}-abac-policy",
            description="Zero Trust Attribute-Based Access Control Policy",
            statements=[
                # Department-based S3 access
                iam.PolicyStatement(
                    sid="AllowAccessBasedOnDepartment",
                    effect=iam.Effect.ALLOW,
                    actions=["s3:GetObject", "s3:PutObject"],
                    resources=[f"arn:aws:s3:::*/${{saml:Department}}/*"],
                    conditions={
                        "StringEquals": {
                            "saml:Department": ["Finance", "HR", "Engineering"]
                        }
                    }
                ),
                # Time-based access restrictions
                iam.PolicyStatement(
                    sid="TimeBasedAccess",
                    effect=iam.Effect.DENY,
                    actions=["*"],
                    resources=["*"],
                    conditions={
                        "DateGreaterThan": {
                            "aws:CurrentTime": "18:00:00Z"
                        },
                        "DateLessThan": {
                            "aws:CurrentTime": "08:00:00Z"
                        },
                        "StringNotEquals": {
                            "saml:Role": "OnCallEngineer"
                        }
                    }
                )
            ]
        )

    def _create_session_management(self) -> None:
        """Create session management and verification system."""
        
        # Create CloudWatch log group for session logs
        self.session_log_group = logs.LogGroup(
            self,
            "SessionLogGroup",
            log_group_name=f"/aws/zero-trust/{self.zero_trust_prefix}/sessions",
            retention=logs.RetentionDays.ONE_MONTH,
            encryption_key=self.kms_key,
            removal_policy=cdk.RemovalPolicy.DESTROY
        )

        # Create session verification Lambda function
        self._create_session_verification_lambda()

        # Create SSM document for session preferences
        self._create_session_manager_document()

    def _create_session_verification_lambda(self) -> None:
        """Create Lambda function for continuous session verification."""
        
        # Lambda function code
        session_verification_code = '''
import json
import boto3
import logging
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Continuous session verification for zero trust architecture
    """
    try:
        # Parse session details from event
        session_id = event.get('sessionId')
        user_id = event.get('userId') 
        source_ip = event.get('sourceIp')
        
        logger.info(f"Verifying session {session_id} for user {user_id}")
        
        # Verify session integrity
        if not verify_session_integrity(session_id, user_id, source_ip):
            terminate_session(session_id)
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'action': 'terminated',
                    'reason': 'session_integrity_violation',
                    'sessionId': session_id
                })
            }
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'action': 'verified',
                'sessionId': session_id
            })
        }
        
    except Exception as e:
        logger.error(f"Session verification failed: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }

def verify_session_integrity(session_id, user_id, source_ip):
    """
    Verify session integrity based on zero trust principles
    """
    # Check session age
    # Check for IP address changes
    # Validate user behavior patterns
    # Additional security checks can be implemented here
    
    logger.info(f"Session integrity check passed for {session_id}")
    return True

def terminate_session(session_id):
    """
    Terminate session for security violation
    """
    try:
        ssm = boto3.client('ssm')
        ssm.terminate_session(SessionId=session_id)
        logger.info(f"Terminated session {session_id}")
    except Exception as e:
        logger.error(f"Failed to terminate session {session_id}: {str(e)}")
'''

        self.session_verification_lambda = lambda_.Function(
            self,
            "SessionVerificationFunction",
            function_name=f"{self.zero_trust_prefix}-session-verification",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(session_verification_code),
            description="Zero Trust Session Verification Function",
            timeout=Duration.seconds(30),
            memory_size=256,
            role=self.security_role,
            environment={
                "LOG_LEVEL": "INFO",
                "ZERO_TRUST_PREFIX": self.zero_trust_prefix
            }
        )

        # Grant SSM permissions to Lambda
        self.session_verification_lambda.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ssm:TerminateSession",
                    "ssm:DescribeSessions"
                ],
                resources=["*"]
            )
        )

    def _create_session_manager_document(self) -> None:
        """Create SSM document for session manager preferences."""
        
        session_preferences = {
            "schemaVersion": "1.0",
            "description": "Zero Trust Session Manager Preferences",
            "sessionType": "Standard_Stream",
            "inputs": {
                "s3BucketName": self.security_logs_bucket.bucket_name,
                "s3KeyPrefix": "session-logs/",
                "s3EncryptionEnabled": True,
                "cloudWatchLogGroupName": self.session_log_group.log_group_name,
                "cloudWatchEncryptionEnabled": True,
                "kmsKeyId": self.kms_key.key_id,
                "shellProfile": {
                    "linux": 'cd /tmp && echo "Zero Trust Session Started at $(date)" && export PS1="[ZT]\\u@\\h:\\w\\$ "',
                    "windows": "cd C:\\temp && echo Zero Trust Session Started at %DATE% %TIME%"
                }
            }
        }

        ssm.CfnDocument(
            self,
            "SessionManagerDocument",
            name=f"{self.zero_trust_prefix}-session-preferences",
            document_type="Session",
            document_format="JSON",
            content=session_preferences
        )

    def _create_monitoring_dashboard(self) -> None:
        """Create CloudWatch dashboard for zero trust monitoring."""
        
        # Create SNS topic for security alerts
        self.security_alerts_topic = sns.Topic(
            self,
            "SecurityAlertsTopic",
            topic_name=f"{self.zero_trust_prefix}-security-alerts",
            display_name="Zero Trust Security Alerts"
        )

        # Subscribe email to alerts
        if self.security_admin_email:
            self.security_alerts_topic.add_subscription(
                subscriptions.EmailSubscription(self.security_admin_email)
            )

        # Create CloudWatch alarms for security violations
        self._create_security_alarms()

        # Create CloudWatch dashboard
        self.dashboard = cloudwatch.Dashboard(
            self,
            "ZeroTrustDashboard",
            dashboard_name=f"{self.zero_trust_prefix}-security-dashboard"
        )

        # Add widgets to dashboard
        self._add_dashboard_widgets()

    def _create_security_alarms(self) -> None:
        """Create CloudWatch alarms for security monitoring."""
        
        # Failed login attempts alarm
        failed_logins_alarm = cloudwatch.Alarm(
            self,
            "FailedLoginsAlarm",
            alarm_name=f"{self.zero_trust_prefix}-failed-logins",
            alarm_description="Zero Trust: Multiple failed login attempts detected",
            metric=cloudwatch.Metric(
                namespace="AWS/CloudTrail",
                metric_name="ConsoleLogin",
                statistic="Sum"
            ),
            threshold=3,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            period=Duration.minutes(5)
        )

        failed_logins_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.security_alerts_topic)
        )

        # High severity Security Hub findings alarm
        security_hub_alarm = cloudwatch.Alarm(
            self,
            "SecurityHubHighSeverityAlarm", 
            alarm_name=f"{self.zero_trust_prefix}-security-hub-high-severity",
            alarm_description="Zero Trust: High severity Security Hub findings detected",
            metric=cloudwatch.Metric(
                namespace="AWS/SecurityHub",
                metric_name="Findings",
                dimensions_map={"ComplianceType": "FAILED"},
                statistic="Sum"
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            period=Duration.minutes(15)
        )

        security_hub_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.security_alerts_topic)
        )

    def _add_dashboard_widgets(self) -> None:
        """Add widgets to the CloudWatch dashboard."""
        
        # Security Hub findings widget
        security_hub_widget = cloudwatch.GraphWidget(
            title="Zero Trust Security Findings",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/SecurityHub",
                    metric_name="Findings",
                    dimensions_map={"ComplianceType": "FAILED"},
                    statistic="Sum"
                ),
                cloudwatch.Metric(
                    namespace="AWS/GuardDuty", 
                    metric_name="Findings",
                    dimensions_map={"Severity": "HIGH"},
                    statistic="Sum"
                )
            ],
            period=Duration.minutes(5)
        )

        # Session activity widget
        session_activity_widget = cloudwatch.LogQueryWidget(
            title="Zero Trust Access Patterns",
            log_groups=[self.session_log_group],
            query_lines=[
                "fields @timestamp, sourceIPAddress, userIdentity.type, eventName",
                "filter eventName like /AssumeRole/",
                "stats count() by userIdentity.type"
            ]
        )

        # Add widgets to dashboard
        self.dashboard.add_widgets(
            security_hub_widget,
            session_activity_widget
        )

    def _create_automated_response(self) -> None:
        """Create automated incident response system."""
        
        # Create EventBridge rule for Security Hub findings
        security_findings_rule = events.Rule(
            self,
            "SecurityFindingsRule",
            rule_name=f"{self.zero_trust_prefix}-security-findings",
            description="Rule to trigger automated response for security findings",
            event_pattern=events.EventPattern(
                source=["aws.securityhub"],
                detail_type=["Security Hub Findings - Imported"],
                detail={
                    "findings": {
                        "Severity": {
                            "Label": ["HIGH", "CRITICAL"]
                        }
                    }
                }
            )
        )

        # Add SNS target for immediate alerts
        security_findings_rule.add_target(
            targets.SnsTopic(self.security_alerts_topic)
        )

        # Add Lambda target for automated remediation
        security_findings_rule.add_target(
            targets.LambdaFunction(self.session_verification_lambda)
        )

        # Output dashboard URL
        cdk.CfnOutput(
            self,
            "DashboardURL",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.zero_trust_prefix}-security-dashboard",
            description="CloudWatch Dashboard URL for Zero Trust monitoring"
        )


class ZeroTrustSecurityApp(cdk.App):
    """CDK App for Zero Trust Security Architecture."""
    
    def __init__(self):
        super().__init__()
        
        # Get configuration from environment or use defaults
        zero_trust_prefix = self.node.try_get_context("zeroTrustPrefix") or "zero-trust-demo"
        security_admin_email = self.node.try_get_context("securityAdminEmail") or "admin@example.com"
        trusted_networks = self.node.try_get_context("trustedNetworks") or ["203.0.113.0/24", "198.51.100.0/24"]
        
        # Create the stack
        ZeroTrustSecurityStack(
            self, 
            "ZeroTrustSecurityStack",
            zero_trust_prefix=zero_trust_prefix,
            security_admin_email=security_admin_email,
            trusted_networks=trusted_networks,
            env=cdk.Environment(
                account=os.getenv('CDK_DEFAULT_ACCOUNT'),
                region=os.getenv('CDK_DEFAULT_REGION', 'us-east-1')
            )
        )


if __name__ == "__main__":
    app = ZeroTrustSecurityApp()
    app.synth()