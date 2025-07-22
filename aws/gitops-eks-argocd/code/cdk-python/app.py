#!/usr/bin/env python3
"""
CDK Application for GitOps Workflows with EKS, ArgoCD, and CodeCommit

This CDK application deploys the complete infrastructure for implementing
GitOps workflows using Amazon EKS, ArgoCD, and AWS CodeCommit as described
in the GitOps Workflows recipe.

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    Duration,
    RemovalPolicy,
    Tags,
)
from aws_cdk import aws_ec2 as ec2
from aws_cdk import aws_eks as eks
from aws_cdk import aws_codecommit as codecommit
from aws_cdk import aws_iam as iam
from aws_cdk import aws_logs as logs
from constructs import Construct


class GitOpsWorkflowStack(Stack):
    """
    CDK Stack for GitOps Workflows with EKS, ArgoCD, and CodeCommit
    
    This stack creates:
    - VPC with public and private subnets
    - EKS cluster with managed node group
    - CodeCommit repository for GitOps configuration
    - IAM roles and policies for GitOps operations
    - CloudWatch log groups for monitoring
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        config: Dict[str, Any],
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Apply tags to all resources in this stack
        Tags.of(self).add("Project", "GitOps-Workflows")
        Tags.of(self).add("Environment", config.get("environment", "development"))
        Tags.of(self).add("ManagedBy", "AWS-CDK")

        # Create VPC for EKS cluster
        self.vpc = self._create_vpc(config)
        
        # Create CodeCommit repository
        self.codecommit_repo = self._create_codecommit_repository(config)
        
        # Create EKS cluster
        self.eks_cluster = self._create_eks_cluster(config)
        
        # Create CloudWatch log groups
        self._create_log_groups(config)
        
        # Create outputs for important resources
        self._create_outputs()

    def _create_vpc(self, config: Dict[str, Any]) -> ec2.Vpc:
        """
        Create VPC with public and private subnets for EKS cluster
        
        Args:
            config: Configuration dictionary
            
        Returns:
            ec2.Vpc: The created VPC
        """
        return ec2.Vpc(
            self, "GitOpsVPC",
            vpc_name=f"{config['cluster_name']}-vpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,
            enable_dns_hostnames=True,
            enable_dns_support=True,
            subnet_configuration=[
                # Public subnets for load balancers and NAT gateways
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24
                ),
                # Private subnets for EKS worker nodes
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24
                )
            ],
            nat_gateways=2,  # High availability NAT gateways
        )

    def _create_codecommit_repository(self, config: Dict[str, Any]) -> codecommit.Repository:
        """
        Create CodeCommit repository for GitOps configuration
        
        Args:
            config: Configuration dictionary
            
        Returns:
            codecommit.Repository: The created repository
        """
        return codecommit.Repository(
            self, "GitOpsRepository",
            repository_name=config["repository_name"],
            description="GitOps configuration repository for EKS deployments with ArgoCD",
            code=codecommit.Code.from_directory(
                directory_path="./gitops-repo-template",
                branch="main"
            ) if os.path.exists("./gitops-repo-template") else None
        )

    def _create_eks_cluster(self, config: Dict[str, Any]) -> eks.Cluster:
        """
        Create EKS cluster with managed node group
        
        Args:
            config: Configuration dictionary
            
        Returns:
            eks.Cluster: The created EKS cluster
        """
        # Create IAM role for EKS cluster service
        cluster_role = iam.Role(
            self, "EKSClusterRole",
            assumed_by=iam.ServicePrincipal("eks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKSClusterPolicy")
            ]
        )

        # Create IAM role for EKS node group
        nodegroup_role = iam.Role(
            self, "EKSNodeGroupRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKSWorkerNodePolicy"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKS_CNI_Policy"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEC2ContainerRegistryReadOnly"),
                # Additional policy for ALB controller
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEC2ContainerRegistryPowerUser")
            ]
        )

        # Add CodeCommit access policy to node group role
        codecommit_policy = iam.Policy(
            self, "CodeCommitAccessPolicy",
            policy_name="EKSCodeCommitAccess",
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "codecommit:GitPull",
                        "codecommit:GitPush",
                        "codecommit:GetBranch",
                        "codecommit:GetCommit",
                        "codecommit:GetRepository",
                        "codecommit:ListBranches",
                        "codecommit:ListRepositories"
                    ],
                    resources=[self.codecommit_repo.repository_arn]
                )
            ]
        )
        nodegroup_role.attach_inline_policy(codecommit_policy)

        # Create EKS cluster
        cluster = eks.Cluster(
            self, "EKSCluster",
            cluster_name=config["cluster_name"],
            version=eks.KubernetesVersion.V1_28,
            role=cluster_role,
            vpc=self.vpc,
            vpc_subnets=[ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS)],
            endpoint_access=eks.EndpointAccess.PUBLIC_AND_PRIVATE,
            default_capacity=0,  # We'll add managed node groups separately
            cluster_logging=[
                eks.ClusterLoggingTypes.API,
                eks.ClusterLoggingTypes.AUDIT,
                eks.ClusterLoggingTypes.AUTHENTICATOR,
                eks.ClusterLoggingTypes.CONTROLLER_MANAGER,
                eks.ClusterLoggingTypes.SCHEDULER
            ]
        )

        # Add managed node group
        cluster.add_nodegroup_capacity(
            "WorkerNodes",
            nodegroup_name=f"{config['cluster_name']}-workers",
            node_role=nodegroup_role,
            instance_types=[ec2.InstanceType(config.get("node_instance_type", "t3.medium"))],
            min_size=config.get("min_nodes", 1),
            max_size=config.get("max_nodes", 4),
            desired_size=config.get("desired_nodes", 2),
            capacity_type=eks.CapacityType.ON_DEMAND,
            ami_type=eks.NodegroupAmiType.AL2_X86_64,
            disk_size=20,
            subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            tags={
                "Name": f"{config['cluster_name']}-worker-node",
                "kubernetes.io/cluster/{cluster_name}": "owned".format(cluster_name=config["cluster_name"])
            }
        )

        # Install AWS Load Balancer Controller
        aws_lb_controller_policy = iam.Policy.from_aws_managed_policy_name(
            "AWSLoadBalancerControllerIAMPolicy"
        )
        
        aws_lb_controller_service_account = cluster.add_service_account(
            "AWSLoadBalancerController",
            name="aws-load-balancer-controller",
            namespace="kube-system"
        )
        aws_lb_controller_service_account.role.add_managed_policy(aws_lb_controller_policy)

        # Add AWS Load Balancer Controller Helm chart
        cluster.add_helm_chart(
            "AWSLoadBalancerController",
            chart="aws-load-balancer-controller",
            repository="https://aws.github.io/eks-charts",
            namespace="kube-system",
            values={
                "clusterName": cluster.cluster_name,
                "serviceAccount": {
                    "create": False,
                    "name": "aws-load-balancer-controller"
                },
                "region": self.region,
                "vpcId": self.vpc.vpc_id
            }
        )

        # Install ArgoCD
        argocd_namespace = cluster.add_manifest(
            "ArgoCDNamespace",
            {
                "apiVersion": "v1",
                "kind": "Namespace",
                "metadata": {
                    "name": "argocd"
                }
            }
        )

        # Add ArgoCD Helm chart
        argocd_chart = cluster.add_helm_chart(
            "ArgoCD",
            chart="argo-cd",
            repository="https://argoproj.github.io/argo-helm",
            namespace="argocd",
            values={
                "server": {
                    "service": {
                        "type": "ClusterIP"
                    },
                    "ingress": {
                        "enabled": True,
                        "annotations": {
                            "alb.ingress.kubernetes.io/scheme": "internet-facing",
                            "alb.ingress.kubernetes.io/target-type": "ip",
                            "alb.ingress.kubernetes.io/listen-ports": '[{"HTTP": 80}, {"HTTPS": 443}]',
                            "alb.ingress.kubernetes.io/ssl-redirect": "443"
                        },
                        "ingressClassName": "alb",
                        "hosts": ["*"],
                        "paths": ["/"]
                    }
                },
                "configs": {
                    "repositories": {
                        self.codecommit_repo.repository_clone_url_http: {
                            "url": self.codecommit_repo.repository_clone_url_http,
                            "name": "gitops-config-repo",
                            "type": "git"
                        }
                    }
                }
            }
        )
        argocd_chart.node.add_dependency(argocd_namespace)

        return cluster

    def _create_log_groups(self, config: Dict[str, Any]) -> None:
        """
        Create CloudWatch log groups for monitoring
        
        Args:
            config: Configuration dictionary
        """
        # EKS cluster log group (automatically created by EKS)
        # ArgoCD application logs
        logs.LogGroup(
            self, "ArgoCDLogGroup",
            log_group_name=f"/aws/eks/{config['cluster_name']}/argocd",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )

        # GitOps workflow logs
        logs.LogGroup(
            self, "GitOpsWorkflowLogGroup",
            log_group_name=f"/aws/eks/{config['cluster_name']}/gitops-workflows",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources"""
        CfnOutput(
            self, "EKSClusterName",
            description="Name of the EKS cluster",
            value=self.eks_cluster.cluster_name
        )

        CfnOutput(
            self, "EKSClusterEndpoint",
            description="EKS cluster endpoint URL",
            value=self.eks_cluster.cluster_endpoint
        )

        CfnOutput(
            self, "EKSClusterArn",
            description="EKS cluster ARN",
            value=self.eks_cluster.cluster_arn
        )

        CfnOutput(
            self, "CodeCommitRepositoryName",
            description="Name of the CodeCommit repository",
            value=self.codecommit_repo.repository_name
        )

        CfnOutput(
            self, "CodeCommitRepositoryCloneUrl",
            description="CodeCommit repository clone URL (HTTPS)",
            value=self.codecommit_repo.repository_clone_url_http
        )

        CfnOutput(
            self, "VPCId",
            description="VPC ID for the EKS cluster",
            value=self.vpc.vpc_id
        )

        CfnOutput(
            self, "KubeconfigCommand",
            description="Command to update kubeconfig for cluster access",
            value=f"aws eks update-kubeconfig --region {self.region} --name {self.eks_cluster.cluster_name}"
        )


def load_configuration() -> Dict[str, Any]:
    """
    Load configuration from environment variables with sensible defaults
    
    Returns:
        Dict[str, Any]: Configuration dictionary
    """
    import random
    import string
    
    # Generate random suffix for unique resource names
    random_suffix = ''.join(random.choices(string.ascii_lowercase + string.digits, k=6))
    
    return {
        "cluster_name": os.getenv("CLUSTER_NAME", f"gitops-cluster-{random_suffix}"),
        "repository_name": os.getenv("REPOSITORY_NAME", f"gitops-config-{random_suffix}"),
        "environment": os.getenv("ENVIRONMENT", "development"),
        "node_instance_type": os.getenv("NODE_INSTANCE_TYPE", "t3.medium"),
        "min_nodes": int(os.getenv("MIN_NODES", "1")),
        "max_nodes": int(os.getenv("MAX_NODES", "4")),
        "desired_nodes": int(os.getenv("DESIRED_NODES", "2"))
    }


def main() -> None:
    """Main function to create and deploy the CDK application"""
    app = cdk.App()
    
    # Load configuration
    config = load_configuration()
    
    # Get AWS account and region from environment or CDK context
    account = os.getenv("CDK_DEFAULT_ACCOUNT") or app.node.try_get_context("account")
    region = os.getenv("CDK_DEFAULT_REGION") or app.node.try_get_context("region") or "us-west-2"
    
    # Create the GitOps workflow stack
    GitOpsWorkflowStack(
        app, 
        "GitOpsWorkflowStack",
        config=config,
        env=Environment(account=account, region=region),
        description="GitOps Workflows with EKS, ArgoCD, and CodeCommit - CDK Python Implementation"
    )
    
    # Synthesize the CloudFormation template
    app.synth()


if __name__ == "__main__":
    main()