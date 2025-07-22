#!/usr/bin/env python3
"""
EC2 Image Building Pipelines with EC2 Image Builder
AWS CDK Python Application

This CDK application creates an automated EC2 Image Builder pipeline that:
- Creates build and test components for web server configuration
- Sets up image recipes combining components with base AMIs
- Configures infrastructure for secure build environments
- Establishes distribution settings for multi-region deployment
- Implements automated scheduling and notification

Author: AWS CDK Generator v1.3
Recipe: EC2 Image Building Pipelines
"""

import aws_cdk as cdk
from aws_cdk import (
    App,
    Stack,
    Environment,
    CfnOutput,
    Tags,
    aws_imagebuilder as imagebuilder,
    aws_iam as iam,
    aws_s3 as s3,
    aws_sns as sns,
    aws_ec2 as ec2,
    aws_logs as logs,
)
from constructs import Construct
from typing import Dict, List, Optional
import json


class ImageBuilderStack(Stack):
    """
    CDK Stack for EC2 Image Builder Pipeline Infrastructure
    
    This stack creates a complete EC2 Image Builder pipeline with:
    - IAM roles and policies for secure build execution
    - S3 bucket for component storage and build logs
    - SNS topic for build notifications
    - Security group for build instances
    - Build and test components for web server setup
    - Image recipe combining components with base AMI
    - Infrastructure configuration for build environment
    - Distribution configuration for multi-region deployment
    - Automated pipeline with scheduling
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        environment_name: str = "production",
        build_instance_type: str = "t3.medium",
        enable_notifications: bool = True,
        distribution_regions: Optional[List[str]] = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Set default distribution regions if not provided
        if distribution_regions is None:
            distribution_regions = [self.region]

        # Create S3 bucket for component storage and build logs
        self.logs_bucket = self._create_logs_bucket()

        # Create IAM roles for Image Builder
        self.instance_role = self._create_instance_role()
        self.instance_profile = self._create_instance_profile()

        # Create SNS topic for notifications (optional)
        self.notification_topic = None
        if enable_notifications:
            self.notification_topic = self._create_notification_topic()

        # Create security group for build instances
        self.security_group = self._create_security_group()

        # Create build and test components
        self.build_component = self._create_build_component()
        self.test_component = self._create_test_component()

        # Create image recipe
        self.image_recipe = self._create_image_recipe()

        # Create infrastructure configuration
        self.infrastructure_config = self._create_infrastructure_configuration(
            build_instance_type
        )

        # Create distribution configuration
        self.distribution_config = self._create_distribution_configuration(
            distribution_regions
        )

        # Create image pipeline
        self.image_pipeline = self._create_image_pipeline()

        # Apply tags to all resources
        self._apply_tags(environment_name)

        # Create outputs
        self._create_outputs()

    def _create_logs_bucket(self) -> s3.Bucket:
        """Create S3 bucket for component storage and build logs"""
        bucket = s3.Bucket(
            self,
            "ImageBuilderLogsBucket",
            bucket_name=f"image-builder-logs-{self.account}-{self.region}",
            removal_policy=cdk.RemovalPolicy.RETAIN,
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            enforce_ssl=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldLogs",
                    expiration=cdk.Duration.days(90),
                    noncurrent_version_expiration=cdk.Duration.days(30),
                )
            ],
        )

        # Add CloudWatch Logs resource policy for Image Builder
        logs.CfnResourcePolicy(
            self,
            "ImageBuilderLogsPolicy",
            policy_name=f"ImageBuilderLogsPolicy-{self.region}",
            policy_document=json.dumps({
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "Service": "imagebuilder.amazonaws.com"
                        },
                        "Action": [
                            "logs:CreateLogGroup",
                            "logs:CreateLogStream",
                            "logs:PutLogEvents"
                        ],
                        "Resource": f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/imagebuilder/*"
                    }
                ]
            })
        )

        return bucket

    def _create_instance_role(self) -> iam.Role:
        """Create IAM role for Image Builder instances"""
        role = iam.Role(
            self,
            "ImageBuilderInstanceRole",
            role_name=f"ImageBuilderInstanceRole-{self.region}",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "EC2InstanceProfileForImageBuilder"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonSSMManagedInstanceCore"
                ),
            ],
            inline_policies={
                "S3LogsAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:PutObject",
                                "s3:DeleteObject",
                                "s3:ListBucket",
                            ],
                            resources=[
                                self.logs_bucket.bucket_arn,
                                f"{self.logs_bucket.bucket_arn}/*",
                            ],
                        )
                    ]
                )
            },
        )
        return role

    def _create_instance_profile(self) -> iam.CfnInstanceProfile:
        """Create instance profile for Image Builder instances"""
        instance_profile = iam.CfnInstanceProfile(
            self,
            "ImageBuilderInstanceProfile",
            instance_profile_name=f"ImageBuilderInstanceProfile-{self.region}",
            roles=[self.instance_role.role_name],
        )
        instance_profile.add_dependency(self.instance_role.node.default_child)
        return instance_profile

    def _create_notification_topic(self) -> sns.Topic:
        """Create SNS topic for build notifications"""
        topic = sns.Topic(
            self,
            "ImageBuilderNotifications",
            topic_name=f"ImageBuilder-Notifications-{self.region}",
            display_name="EC2 Image Builder Notifications",
        )
        return topic

    def _create_security_group(self) -> ec2.SecurityGroup:
        """Create security group for Image Builder instances"""
        # Get default VPC
        vpc = ec2.Vpc.from_lookup(self, "DefaultVPC", is_default=True)

        security_group = ec2.SecurityGroup(
            self,
            "ImageBuilderSecurityGroup",
            vpc=vpc,
            description="Security group for EC2 Image Builder instances",
            security_group_name=f"ImageBuilder-SG-{self.region}",
        )

        # Add outbound rules for package downloads and updates
        security_group.add_egress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="HTTPS outbound for package downloads",
        )

        security_group.add_egress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="HTTP outbound for package downloads",
        )

        return security_group

    def _create_build_component(self) -> imagebuilder.CfnComponent:
        """Create build component for web server setup"""
        component_document = {
            "name": "WebServerSetup",
            "description": "Install and configure Apache web server with security hardening",
            "schemaVersion": "1.0",
            "phases": [
                {
                    "name": "build",
                    "steps": [
                        {
                            "name": "UpdateSystem",
                            "action": "UpdateOS",
                        },
                        {
                            "name": "InstallApache",
                            "action": "ExecuteBash",
                            "inputs": {
                                "commands": [
                                    "yum update -y",
                                    "yum install -y httpd",
                                    "systemctl enable httpd",
                                ]
                            },
                        },
                        {
                            "name": "ConfigureApache",
                            "action": "ExecuteBash",
                            "inputs": {
                                "commands": [
                                    "echo '<html><body><h1>Custom Web Server</h1><p>Built with EC2 Image Builder</p></body></html>' > /var/www/html/index.html",
                                    "chown apache:apache /var/www/html/index.html",
                                    "chmod 644 /var/www/html/index.html",
                                ]
                            },
                        },
                        {
                            "name": "SecurityHardening",
                            "action": "ExecuteBash",
                            "inputs": {
                                "commands": [
                                    "sed -i 's/^#ServerTokens OS/ServerTokens Prod/' /etc/httpd/conf/httpd.conf",
                                    "sed -i 's/^#ServerSignature On/ServerSignature Off/' /etc/httpd/conf/httpd.conf",
                                    "systemctl start httpd",
                                ]
                            },
                        },
                    ],
                },
                {
                    "name": "validate",
                    "steps": [
                        {
                            "name": "ValidateApache",
                            "action": "ExecuteBash",
                            "inputs": {
                                "commands": [
                                    "systemctl is-active httpd",
                                    "curl -f http://localhost/ || exit 1",
                                ]
                            },
                        }
                    ],
                },
                {
                    "name": "test",
                    "steps": [
                        {
                            "name": "TestWebServer",
                            "action": "ExecuteBash",
                            "inputs": {
                                "commands": [
                                    "systemctl status httpd",
                                    "curl -s http://localhost/ | grep -q 'Custom Web Server' || exit 1",
                                    "netstat -tlnp | grep :80 || exit 1",
                                ]
                            },
                        }
                    ],
                },
            ],
        }

        component = imagebuilder.CfnComponent(
            self,
            "WebServerBuildComponent",
            name=f"WebServerSetup-{self.region}",
            platform="Linux",
            version="1.0.0",
            description="Web server setup with security hardening",
            data=json.dumps(component_document, indent=2),
            tags={
                "Environment": "Production",
                "Purpose": "WebServer",
                "ComponentType": "Build",
            },
        )

        return component

    def _create_test_component(self) -> imagebuilder.CfnComponent:
        """Create test component for comprehensive validation"""
        component_document = {
            "name": "WebServerTest",
            "description": "Comprehensive testing of web server setup",
            "schemaVersion": "1.0",
            "phases": [
                {
                    "name": "test",
                    "steps": [
                        {
                            "name": "ServiceTest",
                            "action": "ExecuteBash",
                            "inputs": {
                                "commands": [
                                    "echo 'Testing Apache service status...'",
                                    "systemctl is-enabled httpd",
                                    "systemctl is-active httpd",
                                ]
                            },
                        },
                        {
                            "name": "ConfigurationTest",
                            "action": "ExecuteBash",
                            "inputs": {
                                "commands": [
                                    "echo 'Testing Apache configuration...'",
                                    "httpd -t",
                                    "grep -q 'ServerTokens Prod' /etc/httpd/conf/httpd.conf || exit 1",
                                    "grep -q 'ServerSignature Off' /etc/httpd/conf/httpd.conf || exit 1",
                                ]
                            },
                        },
                        {
                            "name": "SecurityTest",
                            "action": "ExecuteBash",
                            "inputs": {
                                "commands": [
                                    "echo 'Testing security configurations...'",
                                    "curl -I http://localhost/ | grep -q 'Apache' && exit 1 || echo 'Server signature hidden'",
                                    "ss -tlnp | grep :80 | grep -q httpd || exit 1",
                                ]
                            },
                        },
                        {
                            "name": "ContentTest",
                            "action": "ExecuteBash",
                            "inputs": {
                                "commands": [
                                    "echo 'Testing web content...'",
                                    "curl -s http://localhost/ | grep -q 'Custom Web Server' || exit 1",
                                    "test -f /var/www/html/index.html || exit 1",
                                ]
                            },
                        },
                    ],
                }
            ],
        }

        component = imagebuilder.CfnComponent(
            self,
            "WebServerTestComponent",
            name=f"WebServerTest-{self.region}",
            platform="Linux",
            version="1.0.0",
            description="Comprehensive web server testing",
            data=json.dumps(component_document, indent=2),
            tags={
                "Environment": "Production",
                "Purpose": "Testing",
                "ComponentType": "Test",
            },
        )

        return component

    def _create_image_recipe(self) -> imagebuilder.CfnImageRecipe:
        """Create image recipe combining components with base AMI"""
        # Use Amazon Linux 2 as base image
        base_image_arn = f"arn:aws:imagebuilder:{self.region}:aws:image/amazon-linux-2-x86/x.x.x"

        image_recipe = imagebuilder.CfnImageRecipe(
            self,
            "WebServerImageRecipe",
            name=f"WebServerRecipe-{self.region}",
            version="1.0.0",
            description="Web server recipe with security hardening",
            parent_image=base_image_arn,
            components=[
                {
                    "componentArn": self.build_component.attr_arn,
                },
                {
                    "componentArn": self.test_component.attr_arn,
                },
            ],
            tags={
                "Environment": "Production",
                "Purpose": "WebServer",
                "RecipeType": "Complete",
            },
        )

        image_recipe.add_dependency(self.build_component)
        image_recipe.add_dependency(self.test_component)

        return image_recipe

    def _create_infrastructure_configuration(
        self, instance_type: str
    ) -> imagebuilder.CfnInfrastructureConfiguration:
        """Create infrastructure configuration for build environment"""
        # Get default subnet
        vpc = ec2.Vpc.from_lookup(self, "DefaultVPC2", is_default=True)
        subnets = vpc.select_subnets(subnet_type=ec2.SubnetType.PUBLIC)

        config = imagebuilder.CfnInfrastructureConfiguration(
            self,
            "WebServerInfrastructureConfig",
            name=f"WebServerInfra-{self.region}",
            description="Infrastructure for web server image builds",
            instance_profile_name=self.instance_profile.instance_profile_name,
            instance_types=[instance_type],
            subnet_id=subnets.subnet_ids[0],
            security_group_ids=[self.security_group.security_group_id],
            terminate_instance_on_failure=True,
            logging={
                "s3Logs": {
                    "s3BucketName": self.logs_bucket.bucket_name,
                    "s3KeyPrefix": "build-logs/",
                }
            },
            sns_topic_arn=self.notification_topic.topic_arn if self.notification_topic else None,
            tags={
                "Environment": "Production",
                "Purpose": "WebServer",
                "InfraType": "Build",
            },
        )

        config.add_dependency(self.instance_profile)
        config.add_dependency(self.security_group.node.default_child)
        config.add_dependency(self.logs_bucket.node.default_child)

        return config

    def _create_distribution_configuration(
        self, regions: List[str]
    ) -> imagebuilder.CfnDistributionConfiguration:
        """Create distribution configuration for multi-region deployment"""
        distributions = []
        for region in regions:
            distributions.append({
                "region": region,
                "amiDistributionConfiguration": {
                    "name": "WebServer-{{imagebuilder:buildDate}}-{{imagebuilder:buildVersion}}",
                    "description": "Custom web server AMI built with Image Builder",
                    "amiTags": {
                        "Name": "WebServer-AMI",
                        "Environment": "Production",
                        "BuildDate": "{{imagebuilder:buildDate}}",
                        "BuildVersion": "{{imagebuilder:buildVersion}}",
                        "Recipe": f"WebServerRecipe-{self.region}",
                    },
                },
            })

        config = imagebuilder.CfnDistributionConfiguration(
            self,
            "WebServerDistributionConfig",
            name=f"WebServerDist-{self.region}",
            description="Multi-region distribution for web server AMIs",
            distributions=distributions,
            tags={
                "Environment": "Production",
                "Purpose": "WebServer",
                "DistributionType": "MultiRegion",
            },
        )

        return config

    def _create_image_pipeline(self) -> imagebuilder.CfnImagePipeline:
        """Create image pipeline for automated builds"""
        pipeline = imagebuilder.CfnImagePipeline(
            self,
            "WebServerImagePipeline",
            name=f"WebServerPipeline-{self.region}",
            description="Automated web server image building pipeline",
            image_recipe_arn=self.image_recipe.attr_arn,
            infrastructure_configuration_arn=self.infrastructure_config.attr_arn,
            distribution_configuration_arn=self.distribution_config.attr_arn,
            image_tests_configuration={
                "imageTestsEnabled": True,
                "timeoutMinutes": 90,
            },
            schedule={
                "scheduleExpression": "cron(0 2 * * SUN)",
                "pipelineExecutionStartCondition": "EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE",
            },
            status="ENABLED",
            tags={
                "Environment": "Production",
                "Purpose": "WebServer",
                "PipelineType": "Automated",
            },
        )

        pipeline.add_dependency(self.image_recipe)
        pipeline.add_dependency(self.infrastructure_config)
        pipeline.add_dependency(self.distribution_config)

        return pipeline

    def _apply_tags(self, environment_name: str) -> None:
        """Apply common tags to all resources in the stack"""
        Tags.of(self).add("Environment", environment_name.title())
        Tags.of(self).add("Purpose", "WebServer")
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("Recipe", "EC2ImageBuilderPipeline")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources"""
        CfnOutput(
            self,
            "LogsBucketName",
            description="S3 bucket for Image Builder logs",
            value=self.logs_bucket.bucket_name,
        )

        CfnOutput(
            self,
            "ImagePipelineArn",
            description="ARN of the Image Builder pipeline",
            value=self.image_pipeline.attr_arn,
        )

        CfnOutput(
            self,
            "ImageRecipeArn",
            description="ARN of the Image Builder recipe",
            value=self.image_recipe.attr_arn,
        )

        if self.notification_topic:
            CfnOutput(
                self,
                "NotificationTopicArn",
                description="ARN of the SNS notification topic",
                value=self.notification_topic.topic_arn,
            )

        CfnOutput(
            self,
            "SecurityGroupId",
            description="Security group ID for build instances",
            value=self.security_group.security_group_id,
        )


def main() -> None:
    """Main function to create and deploy the CDK application"""
    app = App()

    # Get configuration from CDK context or environment variables
    environment_name = app.node.try_get_context("environment") or "production"
    build_instance_type = app.node.try_get_context("buildInstanceType") or "t3.medium"
    enable_notifications = app.node.try_get_context("enableNotifications") != "false"
    
    # Get distribution regions from context
    distribution_regions = app.node.try_get_context("distributionRegions")
    if distribution_regions and isinstance(distribution_regions, str):
        distribution_regions = distribution_regions.split(",")

    # Create the stack
    ImageBuilderStack(
        app,
        "ImageBuilderStack",
        environment_name=environment_name,
        build_instance_type=build_instance_type,
        enable_notifications=enable_notifications,
        distribution_regions=distribution_regions,
        env=Environment(
            account=app.node.try_get_context("account"),
            region=app.node.try_get_context("region"),
        ),
        description="EC2 Image Builder Pipeline for Web Server AMI Creation",
    )

    app.synth()


if __name__ == "__main__":
    main()