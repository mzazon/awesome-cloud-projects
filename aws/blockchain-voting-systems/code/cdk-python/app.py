#!/usr/bin/env python3
"""
CDK Python application for Blockchain-Based Voting Systems
Implements a secure, transparent voting system using Amazon Managed Blockchain
"""

import os
import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_dynamodb as dynamodb,
    aws_s3 as s3,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_kms as kms,
    aws_events as events,
    aws_events_targets as targets,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cloudwatch_actions,
    aws_logs as logs,
    aws_apigateway as apigateway,
    aws_cognito as cognito,
    aws_secretsmanager as secretsmanager,
    aws_s3_deployment as s3_deployment,
    Tags,
)
from constructs import Construct
from typing import Dict, List, Optional


class BlockchainVotingSystemStack(Stack):
    """
    CDK Stack for Blockchain-Based Voting Systems
    
    Creates a comprehensive voting system infrastructure including:
    - DynamoDB tables for voter registration and election management
    - Lambda functions for voter authentication and vote monitoring
    - S3 buckets for secure data storage and DApp hosting
    - EventBridge rules for event-driven architecture
    - SNS topics for notifications
    - CloudWatch dashboards and alarms for monitoring
    - IAM roles and KMS keys for security
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        environment: str = "dev",
        **kwargs
    ) -> None:
        """
        Initialize the Blockchain Voting System Stack
        
        Args:
            scope: The parent construct
            construct_id: Unique identifier for this construct
            environment: Environment name (dev, staging, prod)
            **kwargs: Additional stack parameters
        """
        super().__init__(scope, construct_id, **kwargs)
        
        self.environment = environment
        
        # Generate unique suffix for resource names
        self.resource_suffix = f"{environment}-{self.account}-{self.region}"
        
        # Create core infrastructure
        self.create_kms_key()
        self.create_dynamodb_tables()
        self.create_s3_buckets()
        self.create_lambda_functions()
        self.create_event_infrastructure()
        self.create_monitoring()
        self.create_outputs()
        
        # Apply common tags
        self.apply_tags()

    def create_kms_key(self) -> None:
        """Create KMS key for encrypting sensitive voting data"""
        self.kms_key = kms.Key(
            self,
            "VotingSystemKey",
            description="KMS key for encrypting voting system data",
            enable_key_rotation=True,
            removal_policy=RemovalPolicy.DESTROY if self.environment == "dev" else RemovalPolicy.RETAIN,
            policy=iam.PolicyDocument(
                statements=[
                    iam.PolicyStatement(
                        sid="Enable IAM User Permissions",
                        effect=iam.Effect.ALLOW,
                        principals=[iam.AccountRootPrincipal()],
                        actions=["kms:*"],
                        resources=["*"],
                    ),
                    iam.PolicyStatement(
                        sid="Allow Lambda Functions",
                        effect=iam.Effect.ALLOW,
                        principals=[iam.ServicePrincipal("lambda.amazonaws.com")],
                        actions=[
                            "kms:Decrypt",
                            "kms:Encrypt",
                            "kms:ReEncrypt*",
                            "kms:GenerateDataKey*",
                            "kms:DescribeKey",
                        ],
                        resources=["*"],
                    ),
                ]
            ),
        )
        
        # Create alias for easier reference
        self.kms_alias = kms.Alias(
            self,
            "VotingSystemKeyAlias",
            alias_name=f"alias/voting-system-{self.environment}",
            target_key=self.kms_key,
        )

    def create_dynamodb_tables(self) -> None:
        """Create DynamoDB tables for voter registry and election management"""
        # Voter Registry Table
        self.voter_registry_table = dynamodb.Table(
            self,
            "VoterRegistry",
            table_name=f"VoterRegistry-{self.resource_suffix}",
            partition_key=dynamodb.Attribute(
                name="VoterId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="ElectionId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            encryption=dynamodb.TableEncryption.CUSTOMER_MANAGED,
            encryption_key=self.kms_key,
            point_in_time_recovery=True,
            removal_policy=RemovalPolicy.DESTROY if self.environment == "dev" else RemovalPolicy.RETAIN,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
        )
        
        # Elections Table
        self.elections_table = dynamodb.Table(
            self,
            "Elections",
            table_name=f"Elections-{self.resource_suffix}",
            partition_key=dynamodb.Attribute(
                name="ElectionId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            encryption=dynamodb.TableEncryption.CUSTOMER_MANAGED,
            encryption_key=self.kms_key,
            point_in_time_recovery=True,
            removal_policy=RemovalPolicy.DESTROY if self.environment == "dev" else RemovalPolicy.RETAIN,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
        )
        
        # Add global secondary indexes for common query patterns
        self.voter_registry_table.add_global_secondary_index(
            index_name="ElectionId-VoterId-index",
            partition_key=dynamodb.Attribute(
                name="ElectionId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="VoterId",
                type=dynamodb.AttributeType.STRING
            ),
        )

    def create_s3_buckets(self) -> None:
        """Create S3 buckets for voting data storage and DApp hosting"""
        # Main voting data bucket
        self.voting_data_bucket = s3.Bucket(
            self,
            "VotingDataBucket",
            bucket_name=f"voting-system-data-{self.resource_suffix}",
            encryption=s3.BucketEncryption.KMS,
            encryption_key=self.kms_key,
            versioned=True,
            access_control=s3.BucketAccessControl.BUCKET_OWNER_FULL_CONTROL,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY if self.environment == "dev" else RemovalPolicy.RETAIN,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="archive-old-votes",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30),
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90),
                        ),
                    ],
                ),
            ],
        )
        
        # DApp hosting bucket
        self.dapp_hosting_bucket = s3.Bucket(
            self,
            "DAppHostingBucket",
            bucket_name=f"voting-dapp-{self.resource_suffix}",
            website_index_document="index.html",
            website_error_document="error.html",
            public_read_access=True,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Smart contracts bucket
        self.smart_contracts_bucket = s3.Bucket(
            self,
            "SmartContractsBucket",
            bucket_name=f"voting-contracts-{self.resource_suffix}",
            encryption=s3.BucketEncryption.KMS,
            encryption_key=self.kms_key,
            versioned=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY if self.environment == "dev" else RemovalPolicy.RETAIN,
        )

    def create_lambda_functions(self) -> None:
        """Create Lambda functions for voter authentication and vote monitoring"""
        # Create Lambda layer for common dependencies
        self.lambda_layer = lambda_.LayerVersion(
            self,
            "VotingSystemLayer",
            code=lambda_.Code.from_asset("lambda/layer"),
            compatible_runtimes=[lambda_.Runtime.NODEJS_18_X],
            description="Common dependencies for voting system Lambda functions",
        )
        
        # Create IAM role for voter authentication Lambda
        self.voter_auth_role = iam.Role(
            self,
            "VoterAuthLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
            inline_policies={
                "VoterAuthPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "dynamodb:GetItem",
                                "dynamodb:PutItem",
                                "dynamodb:UpdateItem",
                                "dynamodb:Query",
                                "dynamodb:Scan",
                            ],
                            resources=[
                                self.voter_registry_table.table_arn,
                                self.elections_table.table_arn,
                                f"{self.voter_registry_table.table_arn}/index/*",
                                f"{self.elections_table.table_arn}/index/*",
                            ],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "kms:Decrypt",
                                "kms:Encrypt",
                                "kms:ReEncrypt*",
                                "kms:GenerateDataKey*",
                                "kms:DescribeKey",
                            ],
                            resources=[self.kms_key.key_arn],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:PutObject",
                            ],
                            resources=[
                                f"{self.voting_data_bucket.bucket_arn}/*",
                            ],
                        ),
                    ]
                ),
            },
        )
        
        # Voter Authentication Lambda
        self.voter_auth_lambda = lambda_.Function(
            self,
            "VoterAuthenticationFunction",
            function_name=f"VoterAuthentication-{self.resource_suffix}",
            runtime=lambda_.Runtime.NODEJS_18_X,
            handler="index.handler",
            code=lambda_.Code.from_asset("lambda/voter-auth"),
            role=self.voter_auth_role,
            timeout=Duration.seconds(60),
            memory_size=512,
            layers=[self.lambda_layer],
            environment={
                "VOTER_REGISTRY_TABLE": self.voter_registry_table.table_name,
                "ELECTIONS_TABLE": self.elections_table.table_name,
                "KMS_KEY_ID": self.kms_key.key_id,
                "VOTING_DATA_BUCKET": self.voting_data_bucket.bucket_name,
                "ENVIRONMENT": self.environment,
            },
            log_retention=logs.RetentionDays.ONE_WEEK if self.environment == "dev" else logs.RetentionDays.ONE_MONTH,
        )
        
        # Create IAM role for vote monitoring Lambda
        self.vote_monitor_role = iam.Role(
            self,
            "VoteMonitorLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
            inline_policies={
                "VoteMonitorPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "dynamodb:GetItem",
                                "dynamodb:PutItem",
                                "dynamodb:UpdateItem",
                                "dynamodb:Query",
                                "dynamodb:Scan",
                            ],
                            resources=[
                                self.voter_registry_table.table_arn,
                                self.elections_table.table_arn,
                                f"{self.voter_registry_table.table_arn}/index/*",
                                f"{self.elections_table.table_arn}/index/*",
                            ],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:PutObject",
                            ],
                            resources=[
                                f"{self.voting_data_bucket.bucket_arn}/*",
                            ],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "events:PutEvents",
                            ],
                            resources=[
                                f"arn:aws:events:{self.region}:{self.account}:event-bus/default",
                            ],
                        ),
                    ]
                ),
            },
        )
        
        # Vote Monitoring Lambda
        self.vote_monitor_lambda = lambda_.Function(
            self,
            "VoteMonitoringFunction",
            function_name=f"VoteMonitoring-{self.resource_suffix}",
            runtime=lambda_.Runtime.NODEJS_18_X,
            handler="index.handler",
            code=lambda_.Code.from_asset("lambda/vote-monitor"),
            role=self.vote_monitor_role,
            timeout=Duration.seconds(60),
            memory_size=512,
            layers=[self.lambda_layer],
            environment={
                "VOTER_REGISTRY_TABLE": self.voter_registry_table.table_name,
                "ELECTIONS_TABLE": self.elections_table.table_name,
                "VOTING_DATA_BUCKET": self.voting_data_bucket.bucket_name,
                "ENVIRONMENT": self.environment,
            },
            log_retention=logs.RetentionDays.ONE_WEEK if self.environment == "dev" else logs.RetentionDays.ONE_MONTH,
        )

    def create_event_infrastructure(self) -> None:
        """Create EventBridge rules and SNS topics for event-driven architecture"""
        # SNS topic for voting system notifications
        self.voting_notifications_topic = sns.Topic(
            self,
            "VotingNotificationsTopic",
            topic_name=f"voting-system-notifications-{self.resource_suffix}",
            display_name="Blockchain Voting System Notifications",
            kms_master_key=self.kms_key,
        )
        
        # EventBridge rule for voting system events
        self.voting_events_rule = events.Rule(
            self,
            "VotingSystemEventsRule",
            rule_name=f"VotingSystemEvents-{self.resource_suffix}",
            description="Rule for blockchain voting system events",
            event_pattern=events.EventPattern(
                source=["voting.blockchain"],
                detail_type=[
                    "VoteCast",
                    "ElectionCreated",
                    "ElectionEnded",
                    "CandidateRegistered",
                    "VoterRegistered",
                    "VoterVerified",
                ],
            ),
            targets=[
                targets.LambdaFunction(self.vote_monitor_lambda),
                targets.SnsTopic(self.voting_notifications_topic),
            ],
        )
        
        # Grant EventBridge permission to invoke Lambda
        self.vote_monitor_lambda.add_permission(
            "EventBridgeInvoke",
            principal=iam.ServicePrincipal("events.amazonaws.com"),
            source_arn=self.voting_events_rule.rule_arn,
        )

    def create_monitoring(self) -> None:
        """Create CloudWatch dashboards and alarms for monitoring"""
        # Create CloudWatch dashboard
        self.dashboard = cloudwatch.Dashboard(
            self,
            "VotingSystemDashboard",
            dashboard_name=f"BlockchainVotingSystem-{self.resource_suffix}",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Voter Authentication Metrics",
                        left=[
                            self.voter_auth_lambda.metric_invocations(
                                period=Duration.minutes(5)
                            ),
                            self.voter_auth_lambda.metric_errors(
                                period=Duration.minutes(5)
                            ),
                        ],
                        right=[
                            self.voter_auth_lambda.metric_duration(
                                period=Duration.minutes(5)
                            ),
                        ],
                    ),
                    cloudwatch.GraphWidget(
                        title="Vote Monitoring Metrics",
                        left=[
                            self.vote_monitor_lambda.metric_invocations(
                                period=Duration.minutes(5)
                            ),
                            self.vote_monitor_lambda.metric_errors(
                                period=Duration.minutes(5)
                            ),
                        ],
                        right=[
                            self.vote_monitor_lambda.metric_duration(
                                period=Duration.minutes(5)
                            ),
                        ],
                    ),
                ],
                [
                    cloudwatch.GraphWidget(
                        title="DynamoDB Table Metrics",
                        left=[
                            self.voter_registry_table.metric_consumed_read_capacity_units(
                                period=Duration.minutes(5)
                            ),
                            self.voter_registry_table.metric_consumed_write_capacity_units(
                                period=Duration.minutes(5)
                            ),
                        ],
                        right=[
                            self.elections_table.metric_consumed_read_capacity_units(
                                period=Duration.minutes(5)
                            ),
                            self.elections_table.metric_consumed_write_capacity_units(
                                period=Duration.minutes(5)
                            ),
                        ],
                    ),
                    cloudwatch.GraphWidget(
                        title="EventBridge Rule Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/Events",
                                metric_name="MatchedEvents",
                                dimensions_map={
                                    "RuleName": self.voting_events_rule.rule_name,
                                },
                                period=Duration.minutes(5),
                            ),
                        ],
                    ),
                ],
            ],
        )
        
        # Create alarms for critical metrics
        self.voter_auth_error_alarm = cloudwatch.Alarm(
            self,
            "VoterAuthErrorAlarm",
            alarm_name=f"VotingSystem-Auth-Errors-{self.resource_suffix}",
            alarm_description="Alert on voter authentication errors",
            metric=self.voter_auth_lambda.metric_errors(
                period=Duration.minutes(5)
            ),
            threshold=5,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
        )
        
        self.voter_auth_error_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.voting_notifications_topic)
        )
        
        self.vote_monitor_error_alarm = cloudwatch.Alarm(
            self,
            "VoteMonitorErrorAlarm",
            alarm_name=f"VotingSystem-Monitor-Errors-{self.resource_suffix}",
            alarm_description="Alert on vote monitoring errors",
            metric=self.vote_monitor_lambda.metric_errors(
                period=Duration.minutes(5)
            ),
            threshold=3,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
        )
        
        self.vote_monitor_error_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.voting_notifications_topic)
        )

    def create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources"""
        cdk.CfnOutput(
            self,
            "VoterRegistryTableName",
            value=self.voter_registry_table.table_name,
            description="Name of the voter registry DynamoDB table",
        )
        
        cdk.CfnOutput(
            self,
            "ElectionsTableName",
            value=self.elections_table.table_name,
            description="Name of the elections DynamoDB table",
        )
        
        cdk.CfnOutput(
            self,
            "VotingDataBucketName",
            value=self.voting_data_bucket.bucket_name,
            description="Name of the voting data S3 bucket",
        )
        
        cdk.CfnOutput(
            self,
            "DAppHostingBucketName",
            value=self.dapp_hosting_bucket.bucket_name,
            description="Name of the DApp hosting S3 bucket",
        )
        
        cdk.CfnOutput(
            self,
            "DAppWebsiteURL",
            value=self.dapp_hosting_bucket.bucket_website_url,
            description="URL of the voting DApp website",
        )
        
        cdk.CfnOutput(
            self,
            "VoterAuthLambdaFunction",
            value=self.voter_auth_lambda.function_name,
            description="Name of the voter authentication Lambda function",
        )
        
        cdk.CfnOutput(
            self,
            "VoteMonitorLambdaFunction",
            value=self.vote_monitor_lambda.function_name,
            description="Name of the vote monitoring Lambda function",
        )
        
        cdk.CfnOutput(
            self,
            "KMSKeyId",
            value=self.kms_key.key_id,
            description="ID of the KMS key used for encryption",
        )
        
        cdk.CfnOutput(
            self,
            "SNSTopicArn",
            value=self.voting_notifications_topic.topic_arn,
            description="ARN of the SNS topic for voting notifications",
        )
        
        cdk.CfnOutput(
            self,
            "CloudWatchDashboardURL",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="URL of the CloudWatch dashboard",
        )

    def apply_tags(self) -> None:
        """Apply common tags to all resources"""
        tags = {
            "Project": "BlockchainVotingSystem",
            "Environment": self.environment,
            "Owner": "VotingSystemTeam",
            "CostCenter": "Democracy",
            "Compliance": "ElectionSecurity",
        }
        
        for key, value in tags.items():
            Tags.of(self).add(key, value)


class VotingSystemApp(cdk.App):
    """CDK Application for the Blockchain Voting System"""
    
    def __init__(self):
        super().__init__()
        
        # Get environment configuration
        environment = self.node.try_get_context("environment") or "dev"
        
        # Define deployment environments
        environments = {
            "dev": {
                "account": os.environ.get("CDK_DEFAULT_ACCOUNT"),
                "region": os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
            },
            "staging": {
                "account": os.environ.get("CDK_DEFAULT_ACCOUNT"),
                "region": os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
            },
            "prod": {
                "account": os.environ.get("CDK_DEFAULT_ACCOUNT"),
                "region": os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
            },
        }
        
        # Create the voting system stack
        BlockchainVotingSystemStack(
            self,
            f"BlockchainVotingSystem-{environment}",
            environment=environment,
            env=cdk.Environment(**environments[environment]),
            description=f"Blockchain-based voting system infrastructure ({environment})",
        )


# Initialize and run the CDK app
app = VotingSystemApp()
app.synth()