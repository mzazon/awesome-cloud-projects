#!/usr/bin/env python3
"""
CDK Python application for Blue-Green Deployments with ECS
Implements zero-downtime deployments using CodeDeploy
"""

import os
from aws_cdk import (
    App,
    Stack,
    Environment,
    CfnOutput,
    Duration,
    aws_ec2 as ec2,
    aws_ecs as ecs,
    aws_elasticloadbalancingv2 as elbv2,
    aws_codedeploy as codedeploy,
    aws_iam as iam,
    aws_ecr as ecr,
    aws_logs as logs,
    aws_s3 as s3,
)
from constructs import Construct


class BlueGreenDeploymentStack(Stack):
    """
    Stack for Blue-Green ECS deployment infrastructure
    Creates ECS cluster, ALB, CodeDeploy application, and supporting resources
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create VPC with public and private subnets
        self.vpc = ec2.Vpc(
            self, "BlueGreenVPC",
            max_azs=2,
            nat_gateways=0,  # Use public subnets for simplicity
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True
        )

        # Create security group for ALB
        self.alb_security_group = ec2.SecurityGroup(
            self, "ALBSecurityGroup",
            vpc=self.vpc,
            description="Security group for Application Load Balancer",
            allow_all_outbound=True
        )
        
        self.alb_security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP traffic"
        )

        # Create security group for ECS tasks
        self.ecs_security_group = ec2.SecurityGroup(
            self, "ECSSecurityGroup",
            vpc=self.vpc,
            description="Security group for ECS tasks",
            allow_all_outbound=True
        )
        
        self.ecs_security_group.add_ingress_rule(
            peer=self.alb_security_group,
            connection=ec2.Port.tcp(80),
            description="Allow traffic from ALB"
        )

        # Create ECR repository for container images
        self.ecr_repository = ecr.Repository(
            self, "BlueGreenRepository",
            repository_name="bluegreen-app",
            image_scan_on_push=True,
            lifecycle_rules=[
                ecr.LifecycleRule(
                    max_image_count=10,
                    description="Keep only 10 images"
                )
            ]
        )

        # Create ECS cluster
        self.ecs_cluster = ecs.Cluster(
            self, "BlueGreenCluster",
            vpc=self.vpc,
            cluster_name="bluegreen-cluster",
            capacity_providers=["FARGATE"],
            default_capacity_provider_strategy=[
                ecs.CapacityProviderStrategy(
                    capacity_provider="FARGATE",
                    weight=1
                )
            ]
        )

        # Create CloudWatch log group for ECS tasks
        self.log_group = logs.LogGroup(
            self, "BlueGreenLogGroup",
            log_group_name="/ecs/bluegreen-task",
            retention=logs.RetentionDays.ONE_WEEK
        )

        # Create task execution role
        self.task_execution_role = iam.Role(
            self, "TaskExecutionRole",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonECSTaskExecutionRolePolicy"
                )
            ]
        )

        # Grant ECR permissions to task execution role
        self.ecr_repository.grant_pull(self.task_execution_role)

        # Create task definition
        self.task_definition = ecs.FargateTaskDefinition(
            self, "BlueGreenTaskDefinition",
            family="bluegreen-task",
            cpu=256,
            memory_limit_mib=512,
            execution_role=self.task_execution_role
        )

        # Add container to task definition
        self.container = self.task_definition.add_container(
            "bluegreen-container",
            image=ecs.ContainerImage.from_registry("nginx:alpine"),
            port_mappings=[
                ecs.PortMapping(
                    container_port=80,
                    protocol=ecs.Protocol.TCP
                )
            ],
            logging=ecs.LogDriver.aws_logs(
                stream_prefix="ecs",
                log_group=self.log_group
            ),
            essential=True
        )

        # Create Application Load Balancer
        self.alb = elbv2.ApplicationLoadBalancer(
            self, "BlueGreenALB",
            vpc=self.vpc,
            internet_facing=True,
            security_group=self.alb_security_group,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PUBLIC
            )
        )

        # Create blue target group
        self.blue_target_group = elbv2.ApplicationTargetGroup(
            self, "BlueTargetGroup",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            vpc=self.vpc,
            target_type=elbv2.TargetType.IP,
            health_check=elbv2.HealthCheck(
                path="/",
                healthy_threshold_count=2,
                unhealthy_threshold_count=3,
                timeout=Duration.seconds(5),
                interval=Duration.seconds(30)
            )
        )

        # Create green target group
        self.green_target_group = elbv2.ApplicationTargetGroup(
            self, "GreenTargetGroup",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            vpc=self.vpc,
            target_type=elbv2.TargetType.IP,
            health_check=elbv2.HealthCheck(
                path="/",
                healthy_threshold_count=2,
                unhealthy_threshold_count=3,
                timeout=Duration.seconds(5),
                interval=Duration.seconds(30)
            )
        )

        # Create ALB listener (initially points to blue target group)
        self.listener = self.alb.add_listener(
            "BlueGreenListener",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            default_action=elbv2.ListenerAction.forward(
                target_groups=[self.blue_target_group]
            )
        )

        # Create CodeDeploy service role
        self.codedeploy_role = iam.Role(
            self, "CodeDeployServiceRole",
            assumed_by=iam.ServicePrincipal("codedeploy.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSCodeDeployRoleForECS"
                )
            ]
        )

        # Create CodeDeploy application
        self.codedeploy_application = codedeploy.EcsApplication(
            self, "BlueGreenApplication",
            application_name="bluegreen-app"
        )

        # Create S3 bucket for deployment artifacts
        self.deployment_bucket = s3.Bucket(
            self, "DeploymentBucket",
            bucket_name=f"bluegreen-deployments-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            enforce_ssl=True
        )

        # Create CodeDeploy deployment group
        self.deployment_group = codedeploy.EcsDeploymentGroup(
            self, "BlueGreenDeploymentGroup",
            application=self.codedeploy_application,
            deployment_group_name="bluegreen-deployment-group",
            service=None,  # Will be set after ECS service creation
            blue_green_deployment_config=codedeploy.EcsBlueGreenDeploymentConfig(
                blue_target_group=self.blue_target_group,
                green_target_group=self.green_target_group,
                listener=self.listener,
                termination_wait_time=Duration.minutes(5)
            ),
            deployment_config=codedeploy.EcsDeploymentConfig.ALL_AT_ONCE,
            service_role=self.codedeploy_role
        )

        # Create ECS service with CodeDeploy deployment controller
        self.ecs_service = ecs.FargateService(
            self, "BlueGreenService",
            cluster=self.ecs_cluster,
            task_definition=self.task_definition,
            service_name="bluegreen-service",
            desired_count=2,
            deployment_controller=ecs.DeploymentController(
                type=ecs.DeploymentControllerType.CODE_DEPLOY
            ),
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PUBLIC
            ),
            security_groups=[self.ecs_security_group],
            assign_public_ip=True
        )

        # Associate service with target group
        self.ecs_service.attach_to_application_target_group(
            self.blue_target_group
        )

        # Update deployment group with ECS service
        self.deployment_group.node.add_dependency(self.ecs_service)

        # Outputs
        CfnOutput(
            self, "LoadBalancerDNS",
            value=self.alb.load_balancer_dns_name,
            description="DNS name of the Application Load Balancer"
        )

        CfnOutput(
            self, "ECRRepositoryURI",
            value=self.ecr_repository.repository_uri,
            description="URI of the ECR repository"
        )

        CfnOutput(
            self, "ECSClusterName",
            value=self.ecs_cluster.cluster_name,
            description="Name of the ECS cluster"
        )

        CfnOutput(
            self, "ECSServiceName",
            value=self.ecs_service.service_name,
            description="Name of the ECS service"
        )

        CfnOutput(
            self, "CodeDeployApplicationName",
            value=self.codedeploy_application.application_name,
            description="Name of the CodeDeploy application"
        )

        CfnOutput(
            self, "DeploymentBucketName",
            value=self.deployment_bucket.bucket_name,
            description="Name of the S3 bucket for deployment artifacts"
        )

        CfnOutput(
            self, "BlueTargetGroupArn",
            value=self.blue_target_group.target_group_arn,
            description="ARN of the blue target group"
        )

        CfnOutput(
            self, "GreenTargetGroupArn",
            value=self.green_target_group.target_group_arn,
            description="ARN of the green target group"
        )


def main():
    """Main function to create and deploy the CDK application"""
    app = App()
    
    # Get environment from context or use defaults
    account = app.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = app.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION")
    
    env = Environment(account=account, region=region)
    
    # Create the stack
    BlueGreenDeploymentStack(
        app, 
        "BlueGreenDeploymentStack",
        env=env,
        description="Blue-Green deployment infrastructure for containerized applications on ECS"
    )
    
    app.synth()


if __name__ == "__main__":
    main()