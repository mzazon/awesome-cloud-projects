"""
ECS Stack for AWS Proton Infrastructure Automation

This stack creates a standardized ECS cluster and supporting infrastructure
for containerized applications deployed via AWS Proton service templates.
"""

from typing import Optional
from aws_cdk import (
    Stack,
    CfnOutput,
    aws_ec2 as ec2,
    aws_ecs as ecs,
    aws_logs as logs,
    aws_iam as iam,
    aws_servicediscovery as servicediscovery,
    Tags,
)
from constructs import Construct


class EcsStack(Stack):
    """
    ECS Stack for AWS Proton Infrastructure
    
    Creates a production-ready ECS cluster with service discovery,
    logging, and monitoring capabilities for use with AWS Proton
    service templates.
    """
    
    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        vpc: ec2.Vpc,
        env_name: str,
        enable_logging: bool = True,
        enable_service_discovery: bool = True,
        **kwargs
    ) -> None:
        """
        Initialize the ECS Stack
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            vpc: The VPC where ECS cluster will be deployed
            env_name: Environment name for resource naming
            enable_logging: Whether to enable container insights
            enable_service_discovery: Whether to enable service discovery
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)
        
        self.vpc = vpc
        self.env_name = env_name
        
        # Create ECS cluster
        self.cluster = self._create_ecs_cluster(enable_logging)
        
        # Create service discovery namespace
        if enable_service_discovery:
            self.namespace = self._create_service_discovery_namespace()
        
        # Create IAM roles
        self._create_iam_roles()
        
        # Create CloudWatch Log Group
        self._create_log_group()
        
        # Create outputs
        self._create_outputs()
        
        # Add tags
        self._add_tags()
    
    def _create_ecs_cluster(self, enable_logging: bool) -> ecs.Cluster:
        """Create ECS cluster with appropriate configuration."""
        
        cluster_settings = []
        if enable_logging:
            cluster_settings.append(
                ecs.ClusterSetting(
                    name=ecs.ClusterSettingName.CONTAINER_INSIGHTS,
                    value="enabled"
                )
            )
        
        cluster = ecs.Cluster(
            self,
            "ProtonEcsCluster",
            cluster_name=f"{self.env_name}-cluster",
            vpc=self.vpc,
            cluster_settings=cluster_settings,
            enable_fargate_capacity_providers=True,
        )
        
        return cluster
    
    def _create_service_discovery_namespace(self) -> servicediscovery.PrivateDnsNamespace:
        """Create service discovery namespace for service-to-service communication."""
        
        namespace = servicediscovery.PrivateDnsNamespace(
            self,
            "ServiceDiscoveryNamespace",
            name=f"{self.env_name}.local",
            vpc=self.vpc,
            description=f"Service discovery namespace for {self.env_name} environment",
        )
        
        return namespace
    
    def _create_iam_roles(self) -> None:
        """Create IAM roles for ECS tasks and services."""
        
        # ECS Task Execution Role
        self.task_execution_role = iam.Role(
            self,
            "EcsTaskExecutionRole",
            role_name=f"{self.env_name}-ecs-task-execution-role",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            description="IAM role for ECS task execution",
        )
        
        # Attach AWS managed policy for ECS task execution
        self.task_execution_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "service-role/AmazonECSTaskExecutionRolePolicy"
            )
        )
        
        # Add permissions for ECR private repositories
        self.task_execution_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ecr:GetAuthorizationToken",
                    "ecr:BatchCheckLayerAvailability",
                    "ecr:GetDownloadUrlForLayer",
                    "ecr:BatchGetImage",
                ],
                resources=["*"],
            )
        )
        
        # Add permissions for CloudWatch Logs
        self.task_execution_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                ],
                resources=[
                    f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/ecs/{self.env_name}/*"
                ],
            )
        )
        
        # ECS Task Role (for application permissions)
        self.task_role = iam.Role(
            self,
            "EcsTaskRole",
            role_name=f"{self.env_name}-ecs-task-role",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            description="IAM role for ECS tasks (application permissions)",
        )
        
        # Add basic AWS SDK permissions
        self.task_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "secretsmanager:GetSecretValue",
                    "ssm:GetParameter",
                    "ssm:GetParameters",
                    "ssm:GetParametersByPath",
                ],
                resources=[
                    f"arn:aws:secretsmanager:{self.region}:{self.account}:secret:/apps/{self.env_name}/*",
                    f"arn:aws:ssm:{self.region}:{self.account}:parameter/apps/{self.env_name}/*",
                ],
            )
        )
    
    def _create_log_group(self) -> None:
        """Create CloudWatch Log Group for ECS containers."""
        
        self.log_group = logs.LogGroup(
            self,
            "EcsLogGroup",
            log_group_name=f"/aws/ecs/{self.env_name}",
            retention=logs.RetentionDays.ONE_MONTH,
        )
    
    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for use by Proton templates."""
        
        # ECS Cluster outputs
        CfnOutput(
            self,
            "EcsClusterName",
            value=self.cluster.cluster_name,
            description="ECS cluster name",
            export_name=f"{self.env_name}-ecs-cluster-name",
        )
        
        CfnOutput(
            self,
            "EcsClusterArn",
            value=self.cluster.cluster_arn,
            description="ECS cluster ARN",
            export_name=f"{self.env_name}-ecs-cluster-arn",
        )
        
        # IAM Role outputs
        CfnOutput(
            self,
            "EcsTaskExecutionRoleArn",
            value=self.task_execution_role.role_arn,
            description="ECS task execution role ARN",
            export_name=f"{self.env_name}-ecs-task-execution-role-arn",
        )
        
        CfnOutput(
            self,
            "EcsTaskRoleArn",
            value=self.task_role.role_arn,
            description="ECS task role ARN",
            export_name=f"{self.env_name}-ecs-task-role-arn",
        )
        
        # Service Discovery outputs
        if hasattr(self, 'namespace'):
            CfnOutput(
                self,
                "ServiceDiscoveryNamespaceId",
                value=self.namespace.namespace_id,
                description="Service discovery namespace ID",
                export_name=f"{self.env_name}-service-discovery-namespace-id",
            )
            
            CfnOutput(
                self,
                "ServiceDiscoveryNamespaceName",
                value=self.namespace.namespace_name,
                description="Service discovery namespace name",
                export_name=f"{self.env_name}-service-discovery-namespace-name",
            )
        
        # Log Group outputs
        CfnOutput(
            self,
            "EcsLogGroupName",
            value=self.log_group.log_group_name,
            description="ECS log group name",
            export_name=f"{self.env_name}-ecs-log-group-name",
        )
        
        CfnOutput(
            self,
            "EcsLogGroupArn",
            value=self.log_group.log_group_arn,
            description="ECS log group ARN",
            export_name=f"{self.env_name}-ecs-log-group-arn",
        )
    
    def _add_tags(self) -> None:
        """Add tags to ECS resources."""
        Tags.of(self.cluster).add("Name", f"{self.env_name}-ecs-cluster")
        Tags.of(self.cluster).add("Purpose", "ProtonEnvironment")
        Tags.of(self.cluster).add("Component", "Compute")
        
        if hasattr(self, 'namespace'):
            Tags.of(self.namespace).add("Name", f"{self.env_name}-service-discovery")
            Tags.of(self.namespace).add("Purpose", "ServiceDiscovery")
        
        Tags.of(self.log_group).add("Name", f"{self.env_name}-ecs-logs")
        Tags.of(self.log_group).add("Purpose", "Logging")