#!/usr/bin/env python3
"""
CDK Python application for Continuous Deployment with CodeDeploy.

This application creates a complete CI/CD pipeline using AWS CodeCommit, CodeBuild,
and CodeDeploy with blue-green deployment strategy for zero-downtime releases.
"""

import os
from aws_cdk import (
    App,
    Environment,
    Stack,
    StackProps,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_elasticloadbalancingv2 as elbv2,
    aws_autoscaling as autoscaling,
    aws_codecommit as codecommit,
    aws_codebuild as codebuild,
    aws_codedeploy as codedeploy,
    aws_s3 as s3,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    Duration,
    Size,
    CfnOutput,
    RemovalPolicy,
    Tags,
)
from constructs import Construct


class ContinuousDeploymentCodeDeployStack(Stack):
    """
    Stack for Continuous Deployment with CodeDeploy.
    
    This stack creates:
    - VPC infrastructure with public subnets
    - Application Load Balancer with target groups for blue-green deployment
    - Auto Scaling Group with EC2 instances
    - CodeCommit repository for source control
    - CodeBuild project for build automation
    - CodeDeploy application with blue-green deployment configuration
    - CloudWatch alarms for monitoring and automatic rollback
    - S3 bucket for deployment artifacts
    - All necessary IAM roles and policies
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters
        self.app_name = "webapp-cdkpython"
        self.environment_name = "production"
        
        # Create VPC and networking
        vpc = self._create_vpc()
        
        # Create IAM roles
        codedeploy_role = self._create_codedeploy_service_role()
        ec2_role = self._create_ec2_instance_role()
        codebuild_role = self._create_codebuild_service_role()
        
        # Create S3 bucket for artifacts
        artifacts_bucket = self._create_artifacts_bucket()
        
        # Create security groups
        alb_sg = self._create_alb_security_group(vpc)
        ec2_sg = self._create_ec2_security_group(vpc, alb_sg)
        
        # Create Application Load Balancer and target groups
        alb, target_group_blue, target_group_green = self._create_load_balancer(
            vpc, alb_sg
        )
        
        # Create Auto Scaling Group
        asg = self._create_auto_scaling_group(vpc, ec2_sg, ec2_role, target_group_blue)
        
        # Create CodeCommit repository
        repo = self._create_codecommit_repository()
        
        # Create CodeBuild project
        build_project = self._create_codebuild_project(repo, artifacts_bucket, codebuild_role)
        
        # Create CodeDeploy application and deployment group
        app, deployment_group = self._create_codedeploy_application(
            codedeploy_role, asg, target_group_blue, target_group_green
        )
        
        # Create CloudWatch alarms
        self._create_cloudwatch_alarms(app, deployment_group, target_group_blue, alb)
        
        # Create outputs
        self._create_outputs(alb, repo, build_project, app, deployment_group, artifacts_bucket)

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC with public subnets for the application."""
        vpc = ec2.Vpc(
            self, "ContinuousDeploymentVPC",
            vpc_name=f"{self.app_name}-vpc",
            max_azs=2,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )
        
        Tags.of(vpc).add("Name", f"{self.app_name}-vpc")
        Tags.of(vpc).add("Environment", self.environment_name)
        
        return vpc

    def _create_codedeploy_service_role(self) -> iam.Role:
        """Create IAM role for CodeDeploy service."""
        role = iam.Role(
            self, "CodeDeployServiceRole",
            role_name=f"{self.app_name}-codedeploy-service-role",
            assumed_by=iam.ServicePrincipal("codedeploy.amazonaws.com"),
            description="Service role for CodeDeploy to perform deployments",
        )
        
        # Attach AWS managed policy for CodeDeploy
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "service-role/AWSCodeDeployRole"
            )
        )
        
        # Add additional permissions for blue-green deployments
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "elasticloadbalancing:DescribeLoadBalancers",
                    "elasticloadbalancing:DescribeTargetGroups",
                    "elasticloadbalancing:DescribeTargetHealth",
                    "elasticloadbalancing:RegisterTargets",
                    "elasticloadbalancing:DeregisterTargets",
                    "autoscaling:DescribeAutoScalingGroups",
                    "autoscaling:DescribeLaunchConfigurations",
                    "autoscaling:DescribeLaunchTemplates",
                    "autoscaling:CreateLaunchTemplate",
                    "autoscaling:CreateAutoScalingGroup",
                    "autoscaling:UpdateAutoScalingGroup",
                    "autoscaling:DeleteAutoScalingGroup",
                    "autoscaling:DeleteLaunchTemplate",
                    "ec2:DescribeInstances",
                    "ec2:DescribeImages",
                    "ec2:DescribeSecurityGroups",
                    "ec2:DescribeSubnets",
                    "ec2:CreateTags",
                    "cloudwatch:DescribeAlarms",
                ],
                resources=["*"],
            )
        )
        
        return role

    def _create_ec2_instance_role(self) -> iam.Role:
        """Create IAM role for EC2 instances."""
        role = iam.Role(
            self, "CodeDeployEC2Role",
            role_name=f"{self.app_name}-ec2-instance-role",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="Role for EC2 instances to work with CodeDeploy",
        )
        
        # Attach AWS managed policies
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "service-role/AmazonEC2RoleforAWSCodeDeploy"
            )
        )
        
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "CloudWatchAgentServerPolicy"
            )
        )
        
        # Add S3 access for deployment artifacts
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:ListBucket",
                ],
                resources=["*"],
            )
        )
        
        return role

    def _create_codebuild_service_role(self) -> iam.Role:
        """Create IAM role for CodeBuild service."""
        role = iam.Role(
            self, "CodeBuildServiceRole",
            role_name=f"{self.app_name}-codebuild-service-role",
            assumed_by=iam.ServicePrincipal("codebuild.amazonaws.com"),
            description="Service role for CodeBuild to build and store artifacts",
        )
        
        # Add CloudWatch Logs permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                ],
                resources=[
                    f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/codebuild/*",
                ],
            )
        )
        
        # Add S3 permissions for artifacts
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:GetBucketLocation",
                    "s3:ListBucket",
                ],
                resources=["*"],
            )
        )
        
        # Add CodeCommit permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "codecommit:GitPull",
                ],
                resources=["*"],
            )
        )
        
        return role

    def _create_artifacts_bucket(self) -> s3.Bucket:
        """Create S3 bucket for storing deployment artifacts."""
        bucket = s3.Bucket(
            self, "ArtifactsBucket",
            bucket_name=f"{self.app_name}-artifacts-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
        )
        
        # Add lifecycle policy to manage old artifacts
        bucket.add_lifecycle_rule(
            id="DeleteOldArtifacts",
            enabled=True,
            expiration=Duration.days(30),
            noncurrent_version_expiration=Duration.days(7),
        )
        
        return bucket

    def _create_alb_security_group(self, vpc: ec2.Vpc) -> ec2.SecurityGroup:
        """Create security group for Application Load Balancer."""
        sg = ec2.SecurityGroup(
            self, "ALBSecurityGroup",
            vpc=vpc,
            description="Security group for Application Load Balancer",
            security_group_name=f"{self.app_name}-alb-sg",
            allow_all_outbound=True,
        )
        
        # Allow HTTP traffic from internet
        sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP traffic from internet",
        )
        
        # Allow HTTPS traffic from internet
        sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS traffic from internet",
        )
        
        return sg

    def _create_ec2_security_group(self, vpc: ec2.Vpc, alb_sg: ec2.SecurityGroup) -> ec2.SecurityGroup:
        """Create security group for EC2 instances."""
        sg = ec2.SecurityGroup(
            self, "EC2SecurityGroup",
            vpc=vpc,
            description="Security group for EC2 instances",
            security_group_name=f"{self.app_name}-ec2-sg",
            allow_all_outbound=True,
        )
        
        # Allow HTTP traffic from ALB
        sg.add_ingress_rule(
            peer=alb_sg,
            connection=ec2.Port.tcp(80),
            description="Allow HTTP traffic from ALB",
        )
        
        # Allow SSH access for debugging (optional)
        sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(22),
            description="Allow SSH access",
        )
        
        return sg

    def _create_load_balancer(self, vpc: ec2.Vpc, alb_sg: ec2.SecurityGroup) -> tuple:
        """Create Application Load Balancer with target groups."""
        # Create Application Load Balancer
        alb = elbv2.ApplicationLoadBalancer(
            self, "ApplicationLoadBalancer",
            vpc=vpc,
            internet_facing=True,
            security_group=alb_sg,
            load_balancer_name=f"{self.app_name}-alb",
        )
        
        # Create target groups for blue-green deployment
        target_group_blue = elbv2.ApplicationTargetGroup(
            self, "TargetGroupBlue",
            target_group_name=f"{self.app_name}-tg-blue",
            protocol=elbv2.ApplicationProtocol.HTTP,
            port=80,
            vpc=vpc,
            health_check=elbv2.HealthCheck(
                enabled=True,
                healthy_http_codes="200",
                interval=Duration.seconds(30),
                path="/",
                protocol=elbv2.Protocol.HTTP,
                timeout=Duration.seconds(5),
                healthy_threshold_count=2,
                unhealthy_threshold_count=3,
            ),
        )
        
        target_group_green = elbv2.ApplicationTargetGroup(
            self, "TargetGroupGreen",
            target_group_name=f"{self.app_name}-tg-green",
            protocol=elbv2.ApplicationProtocol.HTTP,
            port=80,
            vpc=vpc,
            health_check=elbv2.HealthCheck(
                enabled=True,
                healthy_http_codes="200",
                interval=Duration.seconds(30),
                path="/",
                protocol=elbv2.Protocol.HTTP,
                timeout=Duration.seconds(5),
                healthy_threshold_count=2,
                unhealthy_threshold_count=3,
            ),
        )
        
        # Create listener
        listener = alb.add_listener(
            "Listener",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            default_target_groups=[target_group_blue],
        )
        
        return alb, target_group_blue, target_group_green

    def _create_auto_scaling_group(
        self, 
        vpc: ec2.Vpc, 
        ec2_sg: ec2.SecurityGroup, 
        ec2_role: iam.Role,
        target_group: elbv2.ApplicationTargetGroup
    ) -> autoscaling.AutoScalingGroup:
        """Create Auto Scaling Group with launch template."""
        # Create instance profile
        instance_profile = iam.CfnInstanceProfile(
            self, "EC2InstanceProfile",
            instance_profile_name=f"{self.app_name}-ec2-instance-profile",
            roles=[ec2_role.role_name],
        )
        
        # User data script for EC2 instances
        user_data = ec2.UserData.for_linux()
        user_data.add_commands(
            "#!/bin/bash",
            "yum update -y",
            "yum install -y ruby wget httpd",
            "systemctl start httpd",
            "systemctl enable httpd",
            'echo "<h1>Blue Environment - Version 1.0</h1><p>Deployed with CDK Python</p>" > /var/www/html/index.html',
            "cd /home/ec2-user",
            f"wget https://aws-codedeploy-{self.region}.s3.{self.region}.amazonaws.com/latest/install",
            "chmod +x ./install",
            "./install auto",
            "systemctl start codedeploy-agent",
            "systemctl enable codedeploy-agent",
        )
        
        # Create launch template
        launch_template = ec2.LaunchTemplate(
            self, "LaunchTemplate",
            launch_template_name=f"{self.app_name}-launch-template",
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.T3, ec2.InstanceSize.MICRO
            ),
            machine_image=ec2.AmazonLinuxImage(
                generation=ec2.AmazonLinuxGeneration.AMAZON_LINUX_2
            ),
            security_group=ec2_sg,
            user_data=user_data,
            role=ec2_role,
        )
        
        # Create Auto Scaling Group
        asg = autoscaling.AutoScalingGroup(
            self, "AutoScalingGroup",
            vpc=vpc,
            launch_template=launch_template,
            min_capacity=2,
            max_capacity=4,
            desired_capacity=2,
            auto_scaling_group_name=f"{self.app_name}-asg",
            health_check=autoscaling.HealthCheck.elb(
                grace=Duration.seconds(300)
            ),
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PUBLIC
            ),
        )
        
        # Attach to target group
        asg.attach_to_application_target_group(target_group)
        
        # Add tags
        Tags.of(asg).add("Name", f"{self.app_name}-instance")
        Tags.of(asg).add("Environment", "blue")
        
        return asg

    def _create_codecommit_repository(self) -> codecommit.Repository:
        """Create CodeCommit repository for source code."""
        repo = codecommit.Repository(
            self, "CodeCommitRepository",
            repository_name=f"{self.app_name}-repo",
            description="Repository for webapp deployment with CodeDeploy",
        )
        
        return repo

    def _create_codebuild_project(
        self, 
        repo: codecommit.Repository,
        artifacts_bucket: s3.Bucket,
        codebuild_role: iam.Role
    ) -> codebuild.Project:
        """Create CodeBuild project for building application."""
        # Grant CodeBuild access to the artifacts bucket
        artifacts_bucket.grant_read_write(codebuild_role)
        
        # Create CodeBuild project
        project = codebuild.Project(
            self, "CodeBuildProject",
            project_name=f"{self.app_name}-build",
            description="Build project for webapp deployment",
            role=codebuild_role,
            source=codebuild.Source.code_commit(
                repository=repo,
                branch_or_ref="main",
            ),
            artifacts=codebuild.Artifacts.s3(
                bucket=artifacts_bucket,
                name="artifacts",
                path="",
                packaging=codebuild.ArtifactsPackaging.ZIP,
            ),
            environment=codebuild.BuildEnvironment(
                build_image=codebuild.LinuxBuildImage.AMAZON_LINUX_2_3,
                compute_type=codebuild.ComputeType.SMALL,
            ),
            build_spec=codebuild.BuildSpec.from_object({
                "version": "0.2",
                "phases": {
                    "install": {
                        "runtime-versions": {
                            "nodejs": "14"
                        }
                    },
                    "pre_build": {
                        "commands": [
                            "echo Logging in to Amazon ECR...",
                            "echo Build started on `date`"
                        ]
                    },
                    "build": {
                        "commands": [
                            "echo Build completed on `date`"
                        ]
                    }
                },
                "artifacts": {
                    "files": [
                        "**/*"
                    ]
                }
            }),
        )
        
        return project

    def _create_codedeploy_application(
        self,
        codedeploy_role: iam.Role,
        asg: autoscaling.AutoScalingGroup,
        target_group_blue: elbv2.ApplicationTargetGroup,
        target_group_green: elbv2.ApplicationTargetGroup
    ) -> tuple:
        """Create CodeDeploy application and deployment group."""
        # Create CodeDeploy application
        app = codedeploy.ServerApplication(
            self, "CodeDeployApplication",
            application_name=f"{self.app_name}-app",
        )
        
        # Create deployment group
        deployment_group = codedeploy.ServerDeploymentGroup(
            self, "CodeDeployDeploymentGroup",
            application=app,
            deployment_group_name=f"{self.app_name}-deployment-group",
            service_role=codedeploy_role,
            auto_scaling_groups=[asg],
            deployment_config=codedeploy.ServerDeploymentConfig.ALL_AT_ONCE_BLUE_GREEN,
            load_balancer=codedeploy.LoadBalancer.application(target_group_blue),
            auto_rollback=codedeploy.AutoRollbackConfig(
                failed_deployment=True,
                stopped_deployment=True,
                deployment_in_alarm=True,
            ),
            blue_green_deployment_config=codedeploy.BlueGreenDeploymentConfiguration(
                deployment_ready_option=codedeploy.BlueGreenDeploymentReadyOption(
                    action_on_timeout=codedeploy.ActionOnTimeout.CONTINUE_DEPLOYMENT,
                ),
                terminate_blue_instances_on_deployment_success=codedeploy.BlueGreenTerminateBlueInstancesConfig(
                    action=codedeploy.TerminationAction.TERMINATE,
                    termination_wait_time=Duration.minutes(5),
                ),
                green_fleet_provisioning_option=codedeploy.GreenFleetProvisioningOption(
                    action=codedeploy.GreenFleetProvisioningAction.COPY_AUTO_SCALING_GROUP,
                ),
            ),
        )
        
        return app, deployment_group

    def _create_cloudwatch_alarms(
        self,
        app: codedeploy.ServerApplication,
        deployment_group: codedeploy.ServerDeploymentGroup,
        target_group: elbv2.ApplicationTargetGroup,
        alb: elbv2.ApplicationLoadBalancer
    ) -> None:
        """Create CloudWatch alarms for monitoring."""
        # Create SNS topic for notifications
        topic = sns.Topic(
            self, "DeploymentAlarmsTopic",
            topic_name=f"{self.app_name}-deployment-alarms",
            display_name="CodeDeploy Deployment Alarms",
        )
        
        # Alarm for deployment failures
        deployment_failure_alarm = cloudwatch.Alarm(
            self, "DeploymentFailureAlarm",
            alarm_name=f"{self.app_name}-deployment-failure",
            alarm_description="Alarm for CodeDeploy deployment failures",
            metric=cloudwatch.Metric(
                namespace="AWS/CodeDeploy",
                metric_name="FailedDeployments",
                dimensions_map={
                    "ApplicationName": app.application_name,
                    "DeploymentGroupName": deployment_group.deployment_group_name,
                },
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
        )
        
        # Alarm for target group health
        target_health_alarm = cloudwatch.Alarm(
            self, "TargetHealthAlarm",
            alarm_name=f"{self.app_name}-target-health",
            alarm_description="Alarm for target group health",
            metric=cloudwatch.Metric(
                namespace="AWS/ApplicationELB",
                metric_name="HealthyHostCount",
                dimensions_map={
                    "TargetGroup": target_group.target_group_full_name,
                    "LoadBalancer": alb.load_balancer_full_name,
                },
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=1,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
        )
        
        # Add alarms to deployment group
        deployment_group.add_alarm(deployment_failure_alarm)
        deployment_group.add_alarm(target_health_alarm)
        
        # Add SNS actions
        deployment_failure_alarm.add_alarm_action(
            cloudwatch.SnsAction(topic)
        )
        target_health_alarm.add_alarm_action(
            cloudwatch.SnsAction(topic)
        )

    def _create_outputs(
        self,
        alb: elbv2.ApplicationLoadBalancer,
        repo: codecommit.Repository,
        build_project: codebuild.Project,
        app: codedeploy.ServerApplication,
        deployment_group: codedeploy.ServerDeploymentGroup,
        artifacts_bucket: s3.Bucket
    ) -> None:
        """Create CloudFormation outputs."""
        CfnOutput(
            self, "ApplicationURL",
            value=f"http://{alb.load_balancer_dns_name}",
            description="URL of the deployed application",
        )
        
        CfnOutput(
            self, "CodeCommitRepositoryURL",
            value=repo.repository_clone_url_http,
            description="CodeCommit repository clone URL",
        )
        
        CfnOutput(
            self, "CodeBuildProjectName",
            value=build_project.project_name,
            description="CodeBuild project name",
        )
        
        CfnOutput(
            self, "CodeDeployApplicationName",
            value=app.application_name,
            description="CodeDeploy application name",
        )
        
        CfnOutput(
            self, "CodeDeployDeploymentGroupName",
            value=deployment_group.deployment_group_name,
            description="CodeDeploy deployment group name",
        )
        
        CfnOutput(
            self, "ArtifactsBucketName",
            value=artifacts_bucket.bucket_name,
            description="S3 bucket for deployment artifacts",
        )
        
        CfnOutput(
            self, "LoadBalancerDNSName",
            value=alb.load_balancer_dns_name,
            description="DNS name of the Application Load Balancer",
        )


# CDK App
app = App()

# Get AWS account and region from environment
account = os.environ.get("CDK_DEFAULT_ACCOUNT")
region = os.environ.get("CDK_DEFAULT_REGION", "us-east-1")

# Create stack
ContinuousDeploymentCodeDeployStack(
    app, 
    "ContinuousDeploymentCodeDeployStack",
    env=Environment(account=account, region=region),
    description="Continuous deployment pipeline with CodeDeploy blue-green deployments",
)

# Synthesize the app
app.synth()