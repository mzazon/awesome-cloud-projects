#!/usr/bin/env python3
"""
AWS CDK Python application for Simple Web Deployment with Elastic Beanstalk and CloudWatch.

This CDK application creates:
- S3 bucket for application source bundle storage
- Elastic Beanstalk application and environment
- CloudWatch alarms for monitoring
- IAM roles and policies with least privilege access

Author: AWS CDK Team
Version: 1.0
"""

import os
from typing import Dict, Any, Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    Stack,
    StackProps,
    Environment,
    Tags,
    Duration,
    RemovalPolicy,
    CfnOutput,
)
from aws_cdk import aws_elasticbeanstalk as eb
from aws_cdk import aws_s3 as s3
from aws_cdk import aws_s3_deployment as s3deploy
from aws_cdk import aws_iam as iam
from aws_cdk import aws_logs as logs
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_sns as sns
from aws_cdk import aws_cloudwatch_actions as cw_actions
from constructs import Construct


class SimpleWebAppStack(Stack):
    """
    CDK Stack for deploying a simple web application using Elastic Beanstalk with CloudWatch monitoring.
    
    This stack creates a complete infrastructure for hosting a Python Flask web application
    with comprehensive monitoring and alerting capabilities.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        app_name: str = "simple-web-app",
        environment_name: str = "production",
        instance_type: str = "t3.micro",
        **kwargs: Any
    ) -> None:
        """
        Initialize the Simple Web App Stack.

        Args:
            scope: The construct scope
            construct_id: The construct identifier
            app_name: Name of the Elastic Beanstalk application
            environment_name: Name of the environment (production, staging, etc.)
            instance_type: EC2 instance type for the Beanstalk environment
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        self.app_name = app_name
        self.environment_name = environment_name
        self.instance_type = instance_type

        # Create S3 bucket for application source bundles
        self.source_bucket = self._create_source_bucket()

        # Create IAM roles for Elastic Beanstalk
        self.service_role, self.instance_profile = self._create_iam_roles()

        # Create SNS topic for alerts
        self.alert_topic = self._create_alert_topic()

        # Create Elastic Beanstalk application
        self.eb_application = self._create_eb_application()

        # Create Elastic Beanstalk environment
        self.eb_environment = self._create_eb_environment()

        # Create CloudWatch log group for custom logs
        self.log_group = self._create_log_group()

        # Create CloudWatch alarms
        self._create_cloudwatch_alarms()

        # Create stack outputs
        self._create_outputs()

        # Add tags to all resources
        self._add_tags()

    def _create_source_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for storing application source bundles.

        Returns:
            s3.Bucket: The created S3 bucket
        """
        bucket = s3.Bucket(
            self,
            "SourceBucket",
            bucket_name=f"{self.app_name}-source-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    enabled=True,
                    noncurrent_version_expiration=Duration.days(30),
                    noncurrent_versions_to_retain=5,
                )
            ],
        )

        # Add bucket policy to deny insecure transport
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="DenyInsecureConnections",
                effect=iam.Effect.DENY,
                principals=[iam.AnyPrincipal()],
                actions=["s3:*"],
                resources=[bucket.bucket_arn, f"{bucket.bucket_arn}/*"],
                conditions={
                    "Bool": {"aws:SecureTransport": "false"}
                },
            )
        )

        return bucket

    def _create_iam_roles(self) -> tuple[iam.Role, iam.CfnInstanceProfile]:
        """
        Create IAM roles and instance profile for Elastic Beanstalk.

        Returns:
            tuple: Service role and instance profile
        """
        # Create service role for Elastic Beanstalk
        service_role = iam.Role(
            self,
            "EBServiceRole",
            assumed_by=iam.ServicePrincipal("elasticbeanstalk.amazonaws.com"),
            description="Service role for Elastic Beanstalk environment",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSElasticBeanstalkEnhancedHealth"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSElasticBeanstalkService"
                ),
            ],
        )

        # Create instance role for EC2 instances
        instance_role = iam.Role(
            self,
            "EBInstanceRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="Instance role for Elastic Beanstalk EC2 instances",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AWSElasticBeanstalkWebTier"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AWSElasticBeanstalkWorkerTier"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AWSElasticBeanstalkMulticontainerDocker"
                ),
            ],
        )

        # Add CloudWatch Logs permissions
        instance_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                    "logs:DescribeLogStreams",
                ],
                resources=[f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/elasticbeanstalk/*"],
            )
        )

        # Add S3 permissions for source bundle access
        instance_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["s3:GetObject"],
                resources=[f"{self.source_bucket.bucket_arn}/*"],
            )
        )

        # Create instance profile
        instance_profile = iam.CfnInstanceProfile(
            self,
            "EBInstanceProfile",
            roles=[instance_role.role_name],
            instance_profile_name=f"{self.app_name}-instance-profile",
        )

        return service_role, instance_profile

    def _create_alert_topic(self) -> sns.Topic:
        """
        Create SNS topic for CloudWatch alarms.

        Returns:
            sns.Topic: The created SNS topic
        """
        topic = sns.Topic(
            self,
            "AlertTopic",
            topic_name=f"{self.app_name}-alerts",
            display_name="Simple Web App Alerts",
            master_key=sns.TopicEncryption.KMS_MANAGED,
        )

        return topic

    def _create_eb_application(self) -> eb.CfnApplication:
        """
        Create Elastic Beanstalk application.

        Returns:
            eb.CfnApplication: The created Elastic Beanstalk application
        """
        application = eb.CfnApplication(
            self,
            "EBApplication",
            application_name=self.app_name,
            description="Simple web application deployed with CDK",
            resource_lifecycle_config=eb.CfnApplication.ApplicationResourceLifecycleConfigProperty(
                service_role=self.service_role.role_arn,
                version_lifecycle_config=eb.CfnApplication.ApplicationVersionLifecycleConfigProperty(
                    max_count_rule=eb.CfnApplication.MaxCountRuleProperty(
                        enabled=True,
                        max_count=10,
                        delete_source_from_s3=True,
                    ),
                    max_age_rule=eb.CfnApplication.MaxAgeRuleProperty(
                        enabled=True,
                        max_age_in_days=30,
                        delete_source_from_s3=True,
                    ),
                ),
            ),
        )

        return application

    def _create_eb_environment(self) -> eb.CfnEnvironment:
        """
        Create Elastic Beanstalk environment with comprehensive configuration.

        Returns:
            eb.CfnEnvironment: The created Elastic Beanstalk environment
        """
        # Define option settings for the environment
        option_settings = [
            # Platform settings
            eb.CfnEnvironment.OptionSettingProperty(
                namespace="aws:elasticbeanstalk:environment",
                option_name="EnvironmentType",
                value="SingleInstance",
            ),
            eb.CfnEnvironment.OptionSettingProperty(
                namespace="aws:elasticbeanstalk:environment",
                option_name="ServiceRole",
                value=self.service_role.role_arn,
            ),
            # Instance settings
            eb.CfnEnvironment.OptionSettingProperty(
                namespace="aws:autoscaling:launchconfiguration",
                option_name="InstanceType",
                value=self.instance_type,
            ),
            eb.CfnEnvironment.OptionSettingProperty(
                namespace="aws:autoscaling:launchconfiguration",
                option_name="IamInstanceProfile",
                value=self.instance_profile.ref,
            ),
            eb.CfnEnvironment.OptionSettingProperty(
                namespace="aws:autoscaling:launchconfiguration",
                option_name="SecurityGroups",
                value="default",
            ),
            # CloudWatch Logs settings
            eb.CfnEnvironment.OptionSettingProperty(
                namespace="aws:elasticbeanstalk:cloudwatch:logs",
                option_name="StreamLogs",
                value="true",
            ),
            eb.CfnEnvironment.OptionSettingProperty(
                namespace="aws:elasticbeanstalk:cloudwatch:logs",
                option_name="DeleteOnTerminate",
                value="false",
            ),
            eb.CfnEnvironment.OptionSettingProperty(
                namespace="aws:elasticbeanstalk:cloudwatch:logs",
                option_name="RetentionInDays",
                value="7",
            ),
            # Enhanced health reporting
            eb.CfnEnvironment.OptionSettingProperty(
                namespace="aws:elasticbeanstalk:healthreporting:system",
                option_name="SystemType",
                value="enhanced",
            ),
            eb.CfnEnvironment.OptionSettingProperty(
                namespace="aws:elasticbeanstalk:healthreporting:system",
                option_name="EnhancedHealthAuthEnabled",
                value="true",
            ),
            eb.CfnEnvironment.OptionSettingProperty(
                namespace="aws:elasticbeanstalk:cloudwatch:logs:health",
                option_name="HealthStreamingEnabled",
                value="true",
            ),
            eb.CfnEnvironment.OptionSettingProperty(
                namespace="aws:elasticbeanstalk:cloudwatch:logs:health",
                option_name="DeleteOnTerminate",
                value="false",
            ),
            eb.CfnEnvironment.OptionSettingProperty(
                namespace="aws:elasticbeanstalk:cloudwatch:logs:health",
                option_name="RetentionInDays",
                value="7",
            ),
            # Application settings
            eb.CfnEnvironment.OptionSettingProperty(
                namespace="aws:elasticbeanstalk:application:environment",
                option_name="FLASK_ENV",
                value="production",
            ),
            eb.CfnEnvironment.OptionSettingProperty(
                namespace="aws:elasticbeanstalk:application:environment",
                option_name="PYTHONPATH",
                value="/var/app/current",
            ),
        ]

        # Create the environment
        environment = eb.CfnEnvironment(
            self,
            "EBEnvironment",
            application_name=self.eb_application.ref,
            environment_name=f"{self.app_name}-{self.environment_name}",
            solution_stack_name="64bit Amazon Linux 2023 v4.6.1 running Python 3.11",
            description=f"Environment for {self.app_name} application",
            option_settings=option_settings,
            tier=eb.CfnEnvironment.TierProperty(
                name="WebServer",
                type="Standard",
            ),
        )

        # Add dependency on the application
        environment.add_dependency(self.eb_application)

        return environment

    def _create_log_group(self) -> logs.LogGroup:
        """
        Create CloudWatch log group for application logs.

        Returns:
            logs.LogGroup: The created log group
        """
        log_group = logs.LogGroup(
            self,
            "AppLogGroup",
            log_group_name=f"/aws/elasticbeanstalk/{self.app_name}/application",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        return log_group

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for monitoring the Elastic Beanstalk environment."""
        
        # Environment Health Alarm
        health_alarm = cloudwatch.Alarm(
            self,
            "EnvironmentHealthAlarm",
            alarm_name=f"{self.app_name}-environment-health",
            alarm_description="Monitor Elastic Beanstalk environment health",
            metric=cloudwatch.Metric(
                namespace="AWS/ElasticBeanstalk",
                metric_name="EnvironmentHealth",
                dimensions_map={
                    "EnvironmentName": self.eb_environment.ref,
                },
                statistic="Average",
            ),
            threshold=15,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.BREACHING,
        )

        # Add SNS action to health alarm
        health_alarm.add_alarm_action(
            cw_actions.SnsAction(self.alert_topic)
        )

        # Application Requests 4xx Alarm
        requests_4xx_alarm = cloudwatch.Alarm(
            self,
            "Application4xxAlarm",
            alarm_name=f"{self.app_name}-4xx-errors",
            alarm_description="Monitor 4xx application errors",
            metric=cloudwatch.Metric(
                namespace="AWS/ElasticBeanstalk",
                metric_name="ApplicationRequests4xx",
                dimensions_map={
                    "EnvironmentName": self.eb_environment.ref,
                },
                statistic="Sum",
            ),
            threshold=10,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
            period=Duration.minutes(5),
        )

        # Add SNS action to 4xx alarm
        requests_4xx_alarm.add_alarm_action(
            cw_actions.SnsAction(self.alert_topic)
        )

        # Application Requests 5xx Alarm
        requests_5xx_alarm = cloudwatch.Alarm(
            self,
            "Application5xxAlarm",
            alarm_name=f"{self.app_name}-5xx-errors",
            alarm_description="Monitor 5xx server errors",
            metric=cloudwatch.Metric(
                namespace="AWS/ElasticBeanstalk",
                metric_name="ApplicationRequests5xx",
                dimensions_map={
                    "EnvironmentName": self.eb_environment.ref,
                },
                statistic="Sum",
            ),
            threshold=5,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
            period=Duration.minutes(5),
        )

        # Add SNS action to 5xx alarm
        requests_5xx_alarm.add_alarm_action(
            cw_actions.SnsAction(self.alert_topic)
        )

        # Response Time Alarm
        response_time_alarm = cloudwatch.Alarm(
            self,
            "ResponseTimeAlarm",
            alarm_name=f"{self.app_name}-response-time",
            alarm_description="Monitor application response time",
            metric=cloudwatch.Metric(
                namespace="AWS/ElasticBeanstalk",
                metric_name="ApplicationLatencyP95",
                dimensions_map={
                    "EnvironmentName": self.eb_environment.ref,
                },
                statistic="Average",
            ),
            threshold=2000,  # 2 seconds in milliseconds
            evaluation_periods=3,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
            period=Duration.minutes(5),
        )

        # Add SNS action to response time alarm
        response_time_alarm.add_alarm_action(
            cw_actions.SnsAction(self.alert_topic)
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        
        CfnOutput(
            self,
            "ApplicationName",
            description="Name of the Elastic Beanstalk application",
            value=self.eb_application.ref,
        )

        CfnOutput(
            self,
            "EnvironmentName",
            description="Name of the Elastic Beanstalk environment",
            value=self.eb_environment.ref,
        )

        CfnOutput(
            self,
            "EnvironmentURL",
            description="URL of the deployed application",
            value=f"http://{self.eb_environment.attr_endpoint_url}",
        )

        CfnOutput(
            self,
            "SourceBucketName",
            description="Name of the S3 bucket for source bundles",
            value=self.source_bucket.bucket_name,
        )

        CfnOutput(
            self,
            "AlertTopicArn",
            description="ARN of the SNS topic for alerts",
            value=self.alert_topic.topic_arn,
        )

        CfnOutput(
            self,
            "LogGroupName",
            description="Name of the CloudWatch log group",
            value=self.log_group.log_group_name,
        )

    def _add_tags(self) -> None:
        """Add common tags to all resources in the stack."""
        
        Tags.of(self).add("Application", self.app_name)
        Tags.of(self).add("Environment", self.environment_name)
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("Project", "SimpleWebApp")
        Tags.of(self).add("CostCenter", "Development")


def main() -> None:
    """Main function to create and deploy the CDK application."""
    
    # Create CDK app
    app = App()

    # Get configuration from context or environment variables
    app_name = app.node.try_get_context("app_name") or os.environ.get("APP_NAME", "simple-web-app")
    environment_name = app.node.try_get_context("environment") or os.environ.get("ENVIRONMENT", "production")
    instance_type = app.node.try_get_context("instance_type") or os.environ.get("INSTANCE_TYPE", "t3.micro")
    
    # Get AWS account and region from environment or CDK context
    account = os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = os.environ.get("CDK_DEFAULT_REGION", "us-east-1")

    # Create the stack
    SimpleWebAppStack(
        app,
        "SimpleWebAppStack",
        app_name=app_name,
        environment_name=environment_name,
        instance_type=instance_type,
        env=Environment(account=account, region=region),
        description="Simple web application deployment with Elastic Beanstalk and CloudWatch monitoring",
        tags={
            "Project": "SimpleWebApp",
            "Environment": environment_name,
        },
    )

    # Synthesize the CloudFormation template
    app.synth()


if __name__ == "__main__":
    main()