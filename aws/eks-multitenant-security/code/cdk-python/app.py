#!/usr/bin/env python3
"""
CDK Python application for EKS Multi-Tenant Cluster Security with Namespace Isolation.

This application creates an EKS cluster with multi-tenant security features including:
- Namespace isolation for different tenants
- IAM roles and RBAC integration
- Network policies for tenant isolation
- Resource quotas and limits
- Sample applications for testing

Author: AWS CDK Team
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_eks as eks,
    aws_iam as iam,
    aws_ec2 as ec2,
    aws_logs as logs,
    CfnOutput,
    Duration,
    RemovalPolicy,
    Tags,
)
from constructs import Construct
import json
from typing import Dict, List, Optional


class EksMultiTenantSecurityStack(Stack):
    """
    CDK Stack for EKS Multi-Tenant Cluster Security.
    
    This stack creates an EKS cluster with comprehensive multi-tenant security
    features including namespace isolation, RBAC, network policies, and resource quotas.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration
        self.cluster_name = "multi-tenant-cluster"
        self.tenant_a_name = "tenant-alpha"
        self.tenant_b_name = "tenant-beta"
        self.kubernetes_version = eks.KubernetesVersion.V1_29
        
        # Create VPC for EKS cluster
        self.vpc = self._create_vpc()
        
        # Create EKS cluster
        self.cluster = self._create_eks_cluster()
        
        # Create IAM roles for tenants
        self.tenant_roles = self._create_tenant_iam_roles()
        
        # Configure EKS access entries
        self._configure_eks_access_entries()
        
        # Create Kubernetes resources
        self._create_kubernetes_resources()
        
        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC for the EKS cluster with proper configuration."""
        vpc = ec2.Vpc(
            self,
            "EksVpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,
            nat_gateways=1,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="PublicSubnet",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="PrivateSubnet",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                ),
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )
        
        # Tag VPC for EKS
        Tags.of(vpc).add("Name", f"{self.cluster_name}-vpc")
        
        return vpc

    def _create_eks_cluster(self) -> eks.Cluster:
        """Create EKS cluster with security best practices."""
        # Create cluster service role
        cluster_role = iam.Role(
            self,
            "EksClusterRole",
            assumed_by=iam.ServicePrincipal("eks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKSClusterPolicy"),
            ],
        )
        
        # Create node group role
        node_group_role = iam.Role(
            self,
            "EksNodeGroupRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKSWorkerNodePolicy"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKS_CNI_Policy"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEC2ContainerRegistryReadOnly"),
            ],
        )
        
        # Create CloudWatch log group for cluster logging
        log_group = logs.LogGroup(
            self,
            "EksClusterLogGroup",
            log_group_name=f"/aws/eks/{self.cluster_name}/cluster",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Create EKS cluster
        cluster = eks.Cluster(
            self,
            "EksCluster",
            cluster_name=self.cluster_name,
            version=self.kubernetes_version,
            vpc=self.vpc,
            vpc_subnets=[ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS)],
            endpoint_access=eks.EndpointAccess.PRIVATE_AND_PUBLIC,
            cluster_logging=[
                eks.ClusterLoggingTypes.API,
                eks.ClusterLoggingTypes.AUTHENTICATOR,
                eks.ClusterLoggingTypes.CONTROLLER_MANAGER,
            ],
            role=cluster_role,
            default_capacity=0,  # We'll add managed node group separately
            cluster_handler_security_group=None,
            authentication_mode=eks.AuthenticationMode.API_AND_CONFIG_MAP,
        )
        
        # Add managed node group
        cluster.add_nodegroup(
            "DefaultNodeGroup",
            instance_types=[ec2.InstanceType("t3.medium")],
            min_size=2,
            max_size=5,
            desired_size=3,
            subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            node_role=node_group_role,
            ami_type=eks.NodegroupAmiType.AL2_X86_64,
            capacity_type=eks.CapacityType.ON_DEMAND,
            disk_size=20,
            force_update=True,
            labels={
                "node-type": "worker",
                "environment": "production",
            },
            taints=[],
        )
        
        return cluster

    def _create_tenant_iam_roles(self) -> Dict[str, iam.Role]:
        """Create IAM roles for tenant access."""
        tenant_roles = {}
        
        for tenant_name in [self.tenant_a_name, self.tenant_b_name]:
            # Create IAM role for tenant
            role = iam.Role(
                self,
                f"{tenant_name.title().replace('-', '')}EksRole",
                role_name=f"{tenant_name}-eks-role",
                assumed_by=iam.CompositePrincipal(
                    iam.AccountRootPrincipal(),
                    iam.ServicePrincipal("eks.amazonaws.com"),
                ),
                description=f"IAM role for {tenant_name} tenant access to EKS cluster",
                max_session_duration=Duration.hours(12),
            )
            
            # Add basic EKS permissions
            role.add_to_policy(
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "eks:DescribeCluster",
                        "eks:ListClusters",
                    ],
                    resources=["*"],
                )
            )
            
            tenant_roles[tenant_name] = role
        
        return tenant_roles

    def _configure_eks_access_entries(self) -> None:
        """Configure EKS access entries for tenant IAM roles."""
        for tenant_name, role in self.tenant_roles.items():
            # Create access entry for tenant
            access_entry = eks.CfnAccessEntry(
                self,
                f"{tenant_name.title().replace('-', '')}AccessEntry",
                cluster_name=self.cluster.cluster_name,
                principal_arn=role.role_arn,
                type="STANDARD",
                username=f"{tenant_name}-user",
                kubernetes_groups=[],
            )
            
            # Add dependency on cluster
            access_entry.add_dependency(self.cluster.node.default_child)

    def _create_kubernetes_resources(self) -> None:
        """Create Kubernetes resources for multi-tenant security."""
        # Create namespaces for tenants
        self._create_tenant_namespaces()
        
        # Create RBAC resources
        self._create_rbac_resources()
        
        # Create network policies
        self._create_network_policies()
        
        # Create resource quotas and limits
        self._create_resource_quotas()
        
        # Deploy sample applications
        self._deploy_sample_applications()

    def _create_tenant_namespaces(self) -> None:
        """Create namespaces for each tenant with appropriate labels."""
        for tenant_name in [self.tenant_a_name, self.tenant_b_name]:
            tenant_label = tenant_name.split('-')[1]  # Extract 'alpha' or 'beta'
            
            namespace_manifest = {
                "apiVersion": "v1",
                "kind": "Namespace",
                "metadata": {
                    "name": tenant_name,
                    "labels": {
                        "tenant": tenant_label,
                        "isolation": "enabled",
                        "environment": "production",
                    },
                },
            }
            
            self.cluster.add_manifest(
                f"{tenant_name.title().replace('-', '')}Namespace",
                namespace_manifest,
            )

    def _create_rbac_resources(self) -> None:
        """Create RBAC roles and role bindings for tenant isolation."""
        for tenant_name in [self.tenant_a_name, self.tenant_b_name]:
            # Create Role for tenant
            role_manifest = {
                "apiVersion": "rbac.authorization.k8s.io/v1",
                "kind": "Role",
                "metadata": {
                    "namespace": tenant_name,
                    "name": f"{tenant_name}-role",
                },
                "rules": [
                    {
                        "apiGroups": [""],
                        "resources": [
                            "pods",
                            "services",
                            "configmaps",
                            "secrets",
                            "persistentvolumeclaims",
                        ],
                        "verbs": [
                            "get",
                            "list",
                            "watch",
                            "create",
                            "update",
                            "patch",
                            "delete",
                        ],
                    },
                    {
                        "apiGroups": ["apps"],
                        "resources": [
                            "deployments",
                            "replicasets",
                            "daemonsets",
                            "statefulsets",
                        ],
                        "verbs": [
                            "get",
                            "list",
                            "watch",
                            "create",
                            "update",
                            "patch",
                            "delete",
                        ],
                    },
                    {
                        "apiGroups": ["networking.k8s.io"],
                        "resources": ["ingresses", "networkpolicies"],
                        "verbs": [
                            "get",
                            "list",
                            "watch",
                            "create",
                            "update",
                            "patch",
                            "delete",
                        ],
                    },
                ],
            }
            
            # Create RoleBinding for tenant
            role_binding_manifest = {
                "apiVersion": "rbac.authorization.k8s.io/v1",
                "kind": "RoleBinding",
                "metadata": {
                    "name": f"{tenant_name}-binding",
                    "namespace": tenant_name,
                },
                "subjects": [
                    {
                        "kind": "User",
                        "name": f"{tenant_name}-user",
                        "apiGroup": "rbac.authorization.k8s.io",
                    }
                ],
                "roleRef": {
                    "kind": "Role",
                    "name": f"{tenant_name}-role",
                    "apiGroup": "rbac.authorization.k8s.io",
                },
            }
            
            self.cluster.add_manifest(
                f"{tenant_name.title().replace('-', '')}Role",
                role_manifest,
            )
            
            self.cluster.add_manifest(
                f"{tenant_name.title().replace('-', '')}RoleBinding",
                role_binding_manifest,
            )

    def _create_network_policies(self) -> None:
        """Create network policies for tenant isolation."""
        for tenant_name in [self.tenant_a_name, self.tenant_b_name]:
            tenant_label = tenant_name.split('-')[1]  # Extract 'alpha' or 'beta'
            
            network_policy_manifest = {
                "apiVersion": "networking.k8s.io/v1",
                "kind": "NetworkPolicy",
                "metadata": {
                    "name": f"{tenant_name}-isolation",
                    "namespace": tenant_name,
                },
                "spec": {
                    "podSelector": {},
                    "policyTypes": ["Ingress", "Egress"],
                    "ingress": [
                        {
                            "from": [
                                {
                                    "namespaceSelector": {
                                        "matchLabels": {"tenant": tenant_label}
                                    }
                                }
                            ]
                        },
                        {
                            "from": [
                                {
                                    "namespaceSelector": {
                                        "matchLabels": {"name": "kube-system"}
                                    }
                                }
                            ]
                        },
                    ],
                    "egress": [
                        {
                            "to": [
                                {
                                    "namespaceSelector": {
                                        "matchLabels": {"tenant": tenant_label}
                                    }
                                }
                            ]
                        },
                        {
                            "to": [
                                {
                                    "namespaceSelector": {
                                        "matchLabels": {"name": "kube-system"}
                                    }
                                }
                            ]
                        },
                        {
                            "to": [],
                            "ports": [
                                {"protocol": "TCP", "port": 53},
                                {"protocol": "UDP", "port": 53},
                            ],
                        },
                    ],
                },
            }
            
            self.cluster.add_manifest(
                f"{tenant_name.title().replace('-', '')}NetworkPolicy",
                network_policy_manifest,
            )

    def _create_resource_quotas(self) -> None:
        """Create resource quotas and limit ranges for tenant resource management."""
        for tenant_name in [self.tenant_a_name, self.tenant_b_name]:
            # Create ResourceQuota
            resource_quota_manifest = {
                "apiVersion": "v1",
                "kind": "ResourceQuota",
                "metadata": {
                    "name": f"{tenant_name}-quota",
                    "namespace": tenant_name,
                },
                "spec": {
                    "hard": {
                        "requests.cpu": "2",
                        "requests.memory": "4Gi",
                        "limits.cpu": "4",
                        "limits.memory": "8Gi",
                        "pods": "10",
                        "services": "5",
                        "secrets": "10",
                        "configmaps": "10",
                        "persistentvolumeclaims": "4",
                    }
                },
            }
            
            # Create LimitRange
            limit_range_manifest = {
                "apiVersion": "v1",
                "kind": "LimitRange",
                "metadata": {
                    "name": f"{tenant_name}-limits",
                    "namespace": tenant_name,
                },
                "spec": {
                    "limits": [
                        {
                            "type": "Container",
                            "default": {"cpu": "200m", "memory": "256Mi"},
                            "defaultRequest": {"cpu": "100m", "memory": "128Mi"},
                        }
                    ]
                },
            }
            
            self.cluster.add_manifest(
                f"{tenant_name.title().replace('-', '')}ResourceQuota",
                resource_quota_manifest,
            )
            
            self.cluster.add_manifest(
                f"{tenant_name.title().replace('-', '')}LimitRange",
                limit_range_manifest,
            )

    def _deploy_sample_applications(self) -> None:
        """Deploy sample applications for testing tenant isolation."""
        tenant_configs = {
            self.tenant_a_name: {
                "image": "nginx:1.20",
                "port": 80,
            },
            self.tenant_b_name: {
                "image": "httpd:2.4",
                "port": 80,
            },
        }
        
        for tenant_name, config in tenant_configs.items():
            # Create Deployment
            deployment_manifest = {
                "apiVersion": "apps/v1",
                "kind": "Deployment",
                "metadata": {
                    "name": f"{tenant_name}-app",
                    "namespace": tenant_name,
                },
                "spec": {
                    "replicas": 2,
                    "selector": {"matchLabels": {"app": f"{tenant_name}-app"}},
                    "template": {
                        "metadata": {"labels": {"app": f"{tenant_name}-app"}},
                        "spec": {
                            "containers": [
                                {
                                    "name": "app",
                                    "image": config["image"],
                                    "ports": [{"containerPort": config["port"]}],
                                    "resources": {
                                        "requests": {"cpu": "100m", "memory": "128Mi"},
                                        "limits": {"cpu": "200m", "memory": "256Mi"},
                                    },
                                }
                            ]
                        },
                    },
                },
            }
            
            # Create Service
            service_manifest = {
                "apiVersion": "v1",
                "kind": "Service",
                "metadata": {
                    "name": f"{tenant_name}-service",
                    "namespace": tenant_name,
                },
                "spec": {
                    "selector": {"app": f"{tenant_name}-app"},
                    "ports": [{"port": config["port"], "targetPort": config["port"]}],
                },
            }
            
            self.cluster.add_manifest(
                f"{tenant_name.title().replace('-', '')}Deployment",
                deployment_manifest,
            )
            
            self.cluster.add_manifest(
                f"{tenant_name.title().replace('-', '')}Service",
                service_manifest,
            )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "ClusterName",
            value=self.cluster.cluster_name,
            description="Name of the EKS cluster",
        )
        
        CfnOutput(
            self,
            "ClusterEndpoint",
            value=self.cluster.cluster_endpoint,
            description="Endpoint of the EKS cluster",
        )
        
        CfnOutput(
            self,
            "ClusterArn",
            value=self.cluster.cluster_arn,
            description="ARN of the EKS cluster",
        )
        
        CfnOutput(
            self,
            "KubectlCommand",
            value=f"aws eks update-kubeconfig --name {self.cluster.cluster_name} --region {self.region}",
            description="Command to configure kubectl",
        )
        
        for tenant_name, role in self.tenant_roles.items():
            CfnOutput(
                self,
                f"{tenant_name.title().replace('-', '')}RoleArn",
                value=role.role_arn,
                description=f"ARN of the {tenant_name} IAM role",
            )


class EksMultiTenantSecurityApp(cdk.App):
    """CDK Application for EKS Multi-Tenant Security."""
    
    def __init__(self) -> None:
        super().__init__()
        
        # Create the stack
        EksMultiTenantSecurityStack(
            self,
            "EksMultiTenantSecurityStack",
            description="EKS Multi-Tenant Cluster Security with Namespace Isolation",
            env=cdk.Environment(
                account=self.node.try_get_context("account"),
                region=self.node.try_get_context("region"),
            ),
        )


# Main application entry point
app = EksMultiTenantSecurityApp()
app.synth()