#!/usr/bin/env python3
"""
CDK Python application for deploying microservices on EKS with AWS App Mesh.

This application creates a complete infrastructure for running microservices
with service mesh capabilities using Amazon EKS and AWS App Mesh.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    Tags,
    aws_ec2 as ec2,
    aws_eks as eks,
    aws_iam as iam,
    aws_ecr as ecr,
    aws_appmesh as appmesh,
    aws_logs as logs,
    aws_xray as xray,
    aws_elbv2 as elbv2,
    CfnOutput,
    Duration,
    RemovalPolicy
)
from constructs import Construct


class MicroservicesEksServiceMeshStack(Stack):
    """
    CDK Stack for deploying microservices on EKS with AWS App Mesh.
    
    This stack creates:
    - VPC with public and private subnets
    - EKS cluster with managed node groups
    - ECR repositories for microservices
    - AWS App Mesh for service communication
    - IAM roles and policies for secure operations
    - CloudWatch logging and X-Ray tracing
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters
        cluster_name = "microservices-mesh-cluster"
        app_mesh_name = "microservices-mesh"
        namespace = "production"
        
        # Create VPC for EKS cluster
        self.vpc = self._create_vpc()
        
        # Create ECR repositories
        self.ecr_repositories = self._create_ecr_repositories()
        
        # Create EKS cluster
        self.eks_cluster = self._create_eks_cluster(cluster_name)
        
        # Create App Mesh
        self.app_mesh = self._create_app_mesh(app_mesh_name)
        
        # Create Virtual Nodes and Services
        self._create_virtual_nodes_and_services()
        
        # Configure observability
        self._configure_observability()
        
        # Add tags
        self._add_tags()
        
        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """
        Create VPC with public and private subnets for EKS cluster.
        
        Returns:
            ec2.Vpc: The created VPC
        """
        vpc = ec2.Vpc(
            self, "MicroservicesVPC",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,
            nat_gateways=1,
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
                ),
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )
        
        return vpc

    def _create_ecr_repositories(self) -> Dict[str, ecr.Repository]:
        """
        Create ECR repositories for microservices container images.
        
        Returns:
            Dict[str, ecr.Repository]: Dictionary of repository names to ECR repositories
        """
        repositories = {}
        services = ["service-a", "service-b", "service-c"]
        
        for service in services:
            repo = ecr.Repository(
                self, f"ECRRepo{service.replace('-', '').title()}",
                repository_name=f"microservices-demo-{service}",
                image_scan_on_push=True,
                lifecycle_rules=[
                    ecr.LifecycleRule(
                        description="Keep only 10 most recent images",
                        max_image_count=10,
                        rule_priority=1,
                    )
                ],
                removal_policy=RemovalPolicy.DESTROY,
            )
            repositories[service] = repo
            
        return repositories

    def _create_eks_cluster(self, cluster_name: str) -> eks.Cluster:
        """
        Create EKS cluster with managed node groups and App Mesh support.
        
        Args:
            cluster_name: Name of the EKS cluster
            
        Returns:
            eks.Cluster: The created EKS cluster
        """
        # Create cluster admin role
        cluster_admin_role = iam.Role(
            self, "ClusterAdminRole",
            assumed_by=iam.ServicePrincipal("eks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKSClusterPolicy"),
            ],
        )

        # Create node group role
        node_group_role = iam.Role(
            self, "NodeGroupRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKSWorkerNodePolicy"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKS_CNI_Policy"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEC2ContainerRegistryReadOnly"),
                iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchAgentServerPolicy"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AWSAppMeshEnvoyAccess"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AWSXRayDaemonWriteAccess"),
            ],
        )

        # Create EKS cluster
        cluster = eks.Cluster(
            self, "EKSCluster",
            cluster_name=cluster_name,
            version=eks.KubernetesVersion.V1_28,
            vpc=self.vpc,
            role=cluster_admin_role,
            default_capacity=0,  # We'll add managed node groups separately
            endpoint_access=eks.EndpointAccess.PUBLIC_AND_PRIVATE,
            cluster_logging=[
                eks.ClusterLoggingTypes.API,
                eks.ClusterLoggingTypes.AUDIT,
                eks.ClusterLoggingTypes.AUTHENTICATOR,
                eks.ClusterLoggingTypes.CONTROLLER_MANAGER,
                eks.ClusterLoggingTypes.SCHEDULER,
            ],
        )

        # Add managed node group
        cluster.add_nodegroup_capacity(
            "MicroservicesNodes",
            nodegroup_name="microservices-nodes",
            instance_types=[ec2.InstanceType("t3.medium")],
            min_size=3,
            max_size=6,
            desired_size=3,
            disk_size=20,
            node_role=node_group_role,
            ami_type=eks.NodegroupAmiType.AL2_X86_64,
            capacity_type=eks.CapacityType.ON_DEMAND,
            subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
        )

        # Install AWS Load Balancer Controller
        self._install_aws_load_balancer_controller(cluster)
        
        # Install App Mesh Controller
        self._install_app_mesh_controller(cluster)

        return cluster

    def _install_aws_load_balancer_controller(self, cluster: eks.Cluster) -> None:
        """
        Install AWS Load Balancer Controller on the EKS cluster.
        
        Args:
            cluster: The EKS cluster
        """
        # Create service account for AWS Load Balancer Controller
        alb_service_account = cluster.add_service_account(
            "AWSLoadBalancerControllerServiceAccount",
            name="aws-load-balancer-controller",
            namespace="kube-system",
        )

        # Create IAM policy for AWS Load Balancer Controller
        alb_policy = iam.Policy(
            self, "AWSLoadBalancerControllerPolicy",
            document=iam.PolicyDocument.from_json({
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Action": [
                            "iam:CreateServiceLinkedRole",
                            "ec2:DescribeAccountAttributes",
                            "ec2:DescribeAddresses",
                            "ec2:DescribeAvailabilityZones",
                            "ec2:DescribeInternetGateways",
                            "ec2:DescribeVpcs",
                            "ec2:DescribeSubnets",
                            "ec2:DescribeSecurityGroups",
                            "ec2:DescribeInstances",
                            "ec2:DescribeNetworkInterfaces",
                            "ec2:DescribeTags",
                            "ec2:GetCoipPoolUsage",
                            "ec2:DescribeCoipPools",
                            "elasticloadbalancing:DescribeLoadBalancers",
                            "elasticloadbalancing:DescribeLoadBalancerAttributes",
                            "elasticloadbalancing:DescribeListeners",
                            "elasticloadbalancing:DescribeListenerCertificates",
                            "elasticloadbalancing:DescribeSSLPolicies",
                            "elasticloadbalancing:DescribeRules",
                            "elasticloadbalancing:DescribeTargetGroups",
                            "elasticloadbalancing:DescribeTargetGroupAttributes",
                            "elasticloadbalancing:DescribeTargetHealth",
                            "elasticloadbalancing:DescribeTags"
                        ],
                        "Resource": "*"
                    },
                    {
                        "Effect": "Allow",
                        "Action": [
                            "cognito-idp:DescribeUserPoolClient",
                            "acm:ListCertificates",
                            "acm:DescribeCertificate",
                            "iam:ListServerCertificates",
                            "iam:GetServerCertificate",
                            "waf-regional:GetWebACL",
                            "waf-regional:GetWebACLForResource",
                            "waf-regional:AssociateWebACL",
                            "waf-regional:DisassociateWebACL",
                            "wafv2:GetWebACL",
                            "wafv2:GetWebACLForResource",
                            "wafv2:AssociateWebACL",
                            "wafv2:DisassociateWebACL",
                            "shield:DescribeProtection",
                            "shield:GetSubscriptionState",
                            "shield:DescribeSubscription",
                            "shield:CreateProtection",
                            "shield:DeleteProtection"
                        ],
                        "Resource": "*"
                    },
                    {
                        "Effect": "Allow",
                        "Action": [
                            "ec2:AuthorizeSecurityGroupIngress",
                            "ec2:RevokeSecurityGroupIngress"
                        ],
                        "Resource": "*"
                    },
                    {
                        "Effect": "Allow",
                        "Action": [
                            "ec2:CreateSecurityGroup"
                        ],
                        "Resource": "*"
                    },
                    {
                        "Effect": "Allow",
                        "Action": [
                            "ec2:CreateTags"
                        ],
                        "Resource": "arn:aws:ec2:*:*:security-group/*",
                        "Condition": {
                            "StringEquals": {
                                "ec2:CreateAction": "CreateSecurityGroup"
                            },
                            "Null": {
                                "aws:RequestedRegion": "false"
                            }
                        }
                    },
                    {
                        "Effect": "Allow",
                        "Action": [
                            "elasticloadbalancing:CreateLoadBalancer",
                            "elasticloadbalancing:CreateTargetGroup"
                        ],
                        "Resource": "*",
                        "Condition": {
                            "Null": {
                                "aws:RequestedRegion": "false"
                            }
                        }
                    },
                    {
                        "Effect": "Allow",
                        "Action": [
                            "elasticloadbalancing:CreateListener",
                            "elasticloadbalancing:DeleteListener",
                            "elasticloadbalancing:CreateRule",
                            "elasticloadbalancing:DeleteRule"
                        ],
                        "Resource": "*"
                    },
                    {
                        "Effect": "Allow",
                        "Action": [
                            "elasticloadbalancing:AddTags",
                            "elasticloadbalancing:RemoveTags"
                        ],
                        "Resource": [
                            "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
                            "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
                            "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
                        ],
                        "Condition": {
                            "Null": {
                                "aws:RequestedRegion": "false",
                                "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                            }
                        }
                    },
                    {
                        "Effect": "Allow",
                        "Action": [
                            "elasticloadbalancing:RegisterTargets",
                            "elasticloadbalancing:DeregisterTargets"
                        ],
                        "Resource": "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
                    },
                    {
                        "Effect": "Allow",
                        "Action": [
                            "elasticloadbalancing:SetWebAcl",
                            "elasticloadbalancing:ModifyListener",
                            "elasticloadbalancing:AddListenerCertificates",
                            "elasticloadbalancing:RemoveListenerCertificates",
                            "elasticloadbalancing:ModifyRule"
                        ],
                        "Resource": "*"
                    }
                ]
            })
        )

        alb_service_account.role.attach_inline_policy(alb_policy)

        # Install AWS Load Balancer Controller using Helm
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

    def _install_app_mesh_controller(self, cluster: eks.Cluster) -> None:
        """
        Install App Mesh Controller on the EKS cluster.
        
        Args:
            cluster: The EKS cluster
        """
        # Create service account for App Mesh Controller
        appmesh_service_account = cluster.add_service_account(
            "AppMeshControllerServiceAccount",
            name="appmesh-controller",
            namespace="appmesh-system",
        )

        # Attach AWS managed policies
        appmesh_service_account.role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("AWSCloudMapFullAccess")
        )
        appmesh_service_account.role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("AWSAppMeshFullAccess")
        )

        # Install App Mesh Controller using Helm
        cluster.add_helm_chart(
            "AppMeshController",
            chart="appmesh-controller",
            repository="https://aws.github.io/eks-charts",
            namespace="appmesh-system",
            create_namespace=True,
            values={
                "region": self.region,
                "serviceAccount": {
                    "create": False,
                    "name": "appmesh-controller"
                },
                "tracing": {
                    "enabled": True,
                    "provider": "x-ray"
                }
            }
        )

    def _create_app_mesh(self, mesh_name: str) -> appmesh.CfnMesh:
        """
        Create AWS App Mesh for service communication.
        
        Args:
            mesh_name: Name of the App Mesh
            
        Returns:
            appmesh.CfnMesh: The created App Mesh
        """
        mesh = appmesh.CfnMesh(
            self, "AppMesh",
            mesh_name=mesh_name,
            spec=appmesh.CfnMesh.MeshSpecProperty(
                egress_filter=appmesh.CfnMesh.EgressFilterProperty(
                    type="ALLOW_ALL"
                )
            ),
        )

        return mesh

    def _create_virtual_nodes_and_services(self) -> None:
        """
        Create Virtual Nodes and Virtual Services for the microservices.
        """
        services = ["service-a", "service-b", "service-c"]
        
        # Define service dependencies
        service_backends = {
            "service-a": ["service-b"],
            "service-b": ["service-c"],
            "service-c": []
        }

        # Create Virtual Services first
        virtual_services = {}
        for service in services:
            virtual_service = appmesh.CfnVirtualService(
                self, f"VirtualService{service.replace('-', '').title()}",
                mesh_name=self.app_mesh.mesh_name,
                virtual_service_name=f"{service}.production.svc.cluster.local",
                spec=appmesh.CfnVirtualService.VirtualServiceSpecProperty(
                    provider=appmesh.CfnVirtualService.VirtualServiceProviderProperty(
                        virtual_node=appmesh.CfnVirtualService.VirtualNodeServiceProviderProperty(
                            virtual_node_name=f"{service}-vn"
                        )
                    )
                )
            )
            virtual_services[service] = virtual_service

        # Create Virtual Nodes
        virtual_nodes = {}
        for service in services:
            # Build backends list
            backends = []
            for backend_service in service_backends.get(service, []):
                backends.append(
                    appmesh.CfnVirtualNode.BackendProperty(
                        virtual_service=appmesh.CfnVirtualNode.VirtualServiceBackendProperty(
                            virtual_service_name=f"{backend_service}.production.svc.cluster.local"
                        )
                    )
                )

            virtual_node = appmesh.CfnVirtualNode(
                self, f"VirtualNode{service.replace('-', '').title()}",
                mesh_name=self.app_mesh.mesh_name,
                virtual_node_name=f"{service}-vn",
                spec=appmesh.CfnVirtualNode.VirtualNodeSpecProperty(
                    listeners=[
                        appmesh.CfnVirtualNode.ListenerProperty(
                            port_mapping=appmesh.CfnVirtualNode.PortMappingProperty(
                                port=5000,
                                protocol="http"
                            ),
                            health_check=appmesh.CfnVirtualNode.HealthCheckProperty(
                                healthy_threshold=2,
                                interval_millis=5000,
                                path="/",
                                port=5000,
                                protocol="http",
                                timeout_millis=2000,
                                unhealthy_threshold=2
                            )
                        )
                    ],
                    service_discovery=appmesh.CfnVirtualNode.ServiceDiscoveryProperty(
                        dns=appmesh.CfnVirtualNode.DnsServiceDiscoveryProperty(
                            hostname=f"{service}.production.svc.cluster.local"
                        )
                    ),
                    backends=backends if backends else None
                )
            )
            
            # Add dependencies
            virtual_node.add_dependency(self.app_mesh)
            for backend_service in service_backends.get(service, []):
                virtual_node.add_dependency(virtual_services[backend_service])
                
            virtual_nodes[service] = virtual_node

        # Make virtual services depend on their corresponding virtual nodes
        for service in services:
            virtual_services[service].add_dependency(virtual_nodes[service])

    def _configure_observability(self) -> None:
        """
        Configure CloudWatch logging and X-Ray tracing for observability.
        """
        # Create CloudWatch Log Group for container insights
        log_group = logs.LogGroup(
            self, "ContainerInsightsLogGroup",
            log_group_name=f"/aws/containerinsights/{self.eks_cluster.cluster_name}/application",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Create X-Ray service role for daemon
        xray_role = iam.Role(
            self, "XRayDaemonRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AWSXRayDaemonWriteAccess")
            ]
        )

    def _add_tags(self) -> None:
        """
        Add common tags to all resources.
        """
        Tags.of(self).add("Project", "MicroservicesServiceMesh")
        Tags.of(self).add("Environment", "Demo")
        Tags.of(self).add("ManagedBy", "CDK")

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resource references.
        """
        CfnOutput(
            self, "VPCId",
            value=self.vpc.vpc_id,
            description="VPC ID for the EKS cluster"
        )

        CfnOutput(
            self, "EKSClusterName",
            value=self.eks_cluster.cluster_name,
            description="Name of the EKS cluster"
        )

        CfnOutput(
            self, "EKSClusterEndpoint",
            value=self.eks_cluster.cluster_endpoint,
            description="EKS cluster endpoint URL"
        )

        CfnOutput(
            self, "AppMeshName",
            value=self.app_mesh.mesh_name,
            description="Name of the AWS App Mesh"
        )

        for service, repo in self.ecr_repositories.items():
            CfnOutput(
                self, f"ECRRepo{service.replace('-', '').title()}",
                value=repo.repository_uri,
                description=f"ECR repository URI for {service}"
            )

        CfnOutput(
            self, "ConfigureKubectl",
            value=f"aws eks update-kubeconfig --region {self.region} --name {self.eks_cluster.cluster_name}",
            description="Command to configure kubectl for this cluster"
        )


def main() -> None:
    """
    Main function to create and deploy the CDK application.
    """
    app = cdk.App()
    
    # Get environment details
    env = Environment(
        account=os.getenv('CDK_DEFAULT_ACCOUNT'),
        region=os.getenv('CDK_DEFAULT_REGION', 'us-east-1')
    )
    
    # Create the stack
    stack = MicroservicesEksServiceMeshStack(
        app, 
        "MicroservicesEksServiceMeshStack",
        env=env,
        description="CDK stack for deploying microservices on EKS with AWS App Mesh"
    )
    
    app.synth()


if __name__ == "__main__":
    main()