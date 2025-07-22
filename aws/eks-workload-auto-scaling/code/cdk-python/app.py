#!/usr/bin/env python3
"""
CDK Application for EKS Auto-Scaling with HPA and Cluster Autoscaler

This CDK application deploys an Amazon EKS cluster with comprehensive auto-scaling
capabilities including Horizontal Pod Autoscaler (HPA) and Cluster Autoscaler.
The solution demonstrates enterprise-grade auto-scaling for Kubernetes workloads.
"""

import os
from typing import Dict, List, Optional
from aws_cdk import (
    App,
    Stack,
    StackProps,
    Environment,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_eks as eks,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_logs as logs,
    aws_autoscaling as autoscaling,
    aws_kms as kms,
)
from constructs import Construct


class EKSAutoScalingStack(Stack):
    """
    CDK Stack for EKS Auto-Scaling Solution
    
    This stack creates:
    - EKS Cluster with OIDC provider
    - Multiple managed node groups with different instance types
    - IAM roles for Cluster Autoscaler
    - Service accounts with IRSA
    - VPC with public and private subnets
    - CloudWatch log groups for cluster logging
    - Security groups for cluster components
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        cluster_name: str,
        kubernetes_version: str = "1.28",
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.cluster_name = cluster_name
        self.kubernetes_version = kubernetes_version

        # Create VPC for EKS cluster
        self.vpc = self._create_vpc()
        
        # Create KMS key for EKS cluster encryption
        self.kms_key = self._create_kms_key()
        
        # Create CloudWatch log group
        self.log_group = self._create_log_group()
        
        # Create EKS cluster
        self.cluster = self._create_eks_cluster()
        
        # Create managed node groups
        self.general_node_group = self._create_general_node_group()
        self.compute_node_group = self._create_compute_node_group()
        
        # Create IAM role for Cluster Autoscaler
        self.cluster_autoscaler_role = self._create_cluster_autoscaler_role()
        
        # Create service account for Cluster Autoscaler
        self.cluster_autoscaler_sa = self._create_cluster_autoscaler_service_account()
        
        # Deploy Kubernetes resources
        self._deploy_kubernetes_resources()
        
        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC with public and private subnets across multiple AZs."""
        vpc = ec2.Vpc(
            self,
            "EKSVpc",
            vpc_name=f"{self.cluster_name}-vpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,
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
        
        # Add VPC flow logs for monitoring
        vpc.add_flow_log(
            "VpcFlowLog",
            destination=ec2.FlowLogDestination.to_cloud_watch_logs(
                logs.LogGroup(
                    self,
                    "VpcFlowLogGroup",
                    log_group_name=f"/aws/vpc/{self.cluster_name}-flowlogs",
                    retention=logs.RetentionDays.ONE_WEEK,
                    removal_policy=RemovalPolicy.DESTROY,
                )
            ),
            traffic_type=ec2.FlowLogTrafficType.ALL,
        )
        
        return vpc

    def _create_kms_key(self) -> kms.Key:
        """Create KMS key for EKS cluster encryption."""
        return kms.Key(
            self,
            "EKSKMSKey",
            description=f"KMS key for EKS cluster {self.cluster_name}",
            enable_key_rotation=True,
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _create_log_group(self) -> logs.LogGroup:
        """Create CloudWatch log group for EKS cluster logs."""
        return logs.LogGroup(
            self,
            "EKSLogGroup",
            log_group_name=f"/aws/eks/{self.cluster_name}/cluster",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _create_eks_cluster(self) -> eks.Cluster:
        """Create EKS cluster with comprehensive configuration."""
        # Create cluster service role
        cluster_role = iam.Role(
            self,
            "EKSClusterRole",
            assumed_by=iam.ServicePrincipal("eks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKSClusterPolicy"),
            ],
        )

        # Create cluster
        cluster = eks.Cluster(
            self,
            "EKSCluster",
            cluster_name=self.cluster_name,
            version=eks.KubernetesVersion.of(self.kubernetes_version),
            role=cluster_role,
            vpc=self.vpc,
            vpc_subnets=[
                ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS)
            ],
            endpoint_access=eks.EndpointAccess.PUBLIC_AND_PRIVATE,
            secrets_encryption_key=self.kms_key,
            cluster_logging=[
                eks.ClusterLoggingTypes.API,
                eks.ClusterLoggingTypes.AUDIT,
                eks.ClusterLoggingTypes.AUTHENTICATOR,
                eks.ClusterLoggingTypes.CONTROLLER_MANAGER,
                eks.ClusterLoggingTypes.SCHEDULER,
            ],
            cluster_handler_security_group=ec2.SecurityGroup(
                self,
                "ClusterHandlerSecurityGroup",
                vpc=self.vpc,
                description="Security group for EKS cluster handler",
                allow_all_outbound=True,
            ),
            default_capacity=0,  # We'll create our own node groups
        )

        # Add AWS Load Balancer Controller
        cluster.add_helm_chart(
            "AWSLoadBalancerController",
            chart="aws-load-balancer-controller",
            repository="https://aws.github.io/eks-charts",
            namespace="kube-system",
            values={
                "clusterName": self.cluster_name,
                "serviceAccount.create": False,
                "serviceAccount.name": "aws-load-balancer-controller",
                "region": self.region,
                "vpcId": self.vpc.vpc_id,
            },
        )

        # Add EBS CSI Driver
        cluster.add_helm_chart(
            "EBSCSIDriver",
            chart="aws-ebs-csi-driver",
            repository="https://kubernetes-sigs.github.io/aws-ebs-csi-driver",
            namespace="kube-system",
            values={
                "enableVolumeScheduling": True,
                "enableVolumeResizing": True,
                "enableVolumeSnapshot": True,
            },
        )

        return cluster

    def _create_general_node_group(self) -> eks.Nodegroup:
        """Create general-purpose managed node group."""
        # Create node group IAM role
        node_group_role = iam.Role(
            self,
            "GeneralNodeGroupRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKSWorkerNodePolicy"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKS_CNI_Policy"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEC2ContainerRegistryReadOnly"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore"),
            ],
        )

        # Create launch template for better control
        launch_template = ec2.LaunchTemplate(
            self,
            "GeneralNodeGroupLaunchTemplate",
            instance_type=ec2.InstanceType("m5.large"),
            machine_image=eks.EksOptimizedImage.of(
                kubernetes_version=self.kubernetes_version,
                cpu_arch=eks.CpuArch.X86_64,
                node_type=eks.NodeType.STANDARD,
            ),
            user_data=ec2.UserData.for_linux(),
            block_devices=[
                ec2.BlockDevice(
                    device_name="/dev/xvda",
                    volume=ec2.BlockDeviceVolume.ebs(
                        volume_size=20,
                        volume_type=ec2.EbsDeviceVolumeType.GP3,
                        encrypted=True,
                        kms_key=self.kms_key,
                    ),
                )
            ],
        )

        return self.cluster.add_nodegroup_capacity(
            "GeneralNodeGroup",
            instance_types=[
                ec2.InstanceType("m5.large"),
                ec2.InstanceType("m5.xlarge"),
            ],
            min_size=1,
            max_size=10,
            desired_size=2,
            disk_size=20,
            ami_type=eks.NodegroupAmiType.AL2_X86_64,
            capacity_type=eks.CapacityType.ON_DEMAND,
            node_role=node_group_role,
            subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            tags={
                "Name": f"{self.cluster_name}-general-node",
                "workload-type": "general",
                "k8s.io/cluster-autoscaler/enabled": "true",
                f"k8s.io/cluster-autoscaler/{self.cluster_name}": "owned",
            },
        )

    def _create_compute_node_group(self) -> eks.Nodegroup:
        """Create compute-optimized managed node group."""
        # Create node group IAM role
        node_group_role = iam.Role(
            self,
            "ComputeNodeGroupRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKSWorkerNodePolicy"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKS_CNI_Policy"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEC2ContainerRegistryReadOnly"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore"),
            ],
        )

        return self.cluster.add_nodegroup_capacity(
            "ComputeNodeGroup",
            instance_types=[
                ec2.InstanceType("c5.large"),
                ec2.InstanceType("c5.xlarge"),
            ],
            min_size=0,
            max_size=5,
            desired_size=1,
            disk_size=20,
            ami_type=eks.NodegroupAmiType.AL2_X86_64,
            capacity_type=eks.CapacityType.ON_DEMAND,
            node_role=node_group_role,
            subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            tags={
                "Name": f"{self.cluster_name}-compute-node",
                "workload-type": "compute",
                "k8s.io/cluster-autoscaler/enabled": "true",
                f"k8s.io/cluster-autoscaler/{self.cluster_name}": "owned",
            },
        )

    def _create_cluster_autoscaler_role(self) -> iam.Role:
        """Create IAM role for Cluster Autoscaler with IRSA."""
        # Create IAM policy for Cluster Autoscaler
        cluster_autoscaler_policy = iam.Policy(
            self,
            "ClusterAutoscalerPolicy",
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "autoscaling:DescribeAutoScalingGroups",
                        "autoscaling:DescribeAutoScalingInstances",
                        "autoscaling:DescribeLaunchConfigurations",
                        "autoscaling:DescribeTags",
                        "autoscaling:SetDesiredCapacity",
                        "autoscaling:TerminateInstanceInAutoScalingGroup",
                        "ec2:DescribeLaunchTemplateVersions",
                        "ec2:DescribeInstanceTypes",
                    ],
                    resources=["*"],
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "autoscaling:SetDesiredCapacity",
                        "autoscaling:TerminateInstanceInAutoScalingGroup",
                    ],
                    resources=["*"],
                    conditions={
                        "StringEquals": {
                            f"autoscaling:ResourceTag/k8s.io/cluster-autoscaler/{self.cluster_name}": "owned"
                        }
                    },
                ),
            ],
        )

        # Create role for Cluster Autoscaler
        role = iam.Role(
            self,
            "ClusterAutoscalerRole",
            assumed_by=iam.WebIdentityPrincipal(
                identity_provider=self.cluster.open_id_connect_provider.open_id_connect_provider_arn,
                conditions={
                    "StringEquals": {
                        f"{self.cluster.open_id_connect_provider.open_id_connect_provider_issuer}:sub": "system:serviceaccount:kube-system:cluster-autoscaler",
                        f"{self.cluster.open_id_connect_provider.open_id_connect_provider_issuer}:aud": "sts.amazonaws.com",
                    }
                },
            ),
        )

        role.attach_inline_policy(cluster_autoscaler_policy)
        return role

    def _create_cluster_autoscaler_service_account(self) -> eks.ServiceAccount:
        """Create service account for Cluster Autoscaler."""
        return self.cluster.add_service_account(
            "ClusterAutoscalerServiceAccount",
            name="cluster-autoscaler",
            namespace="kube-system",
            role=self.cluster_autoscaler_role,
        )

    def _deploy_kubernetes_resources(self) -> None:
        """Deploy Kubernetes resources including Metrics Server, Cluster Autoscaler, and demo applications."""
        
        # Deploy Metrics Server
        metrics_server_manifest = self.cluster.add_manifest(
            "MetricsServer",
            {
                "apiVersion": "v1",
                "kind": "ServiceAccount",
                "metadata": {
                    "name": "metrics-server",
                    "namespace": "kube-system",
                    "labels": {
                        "k8s-app": "metrics-server"
                    }
                }
            }
        )

        # Deploy Cluster Autoscaler
        cluster_autoscaler_deployment = {
            "apiVersion": "apps/v1",
            "kind": "Deployment",
            "metadata": {
                "name": "cluster-autoscaler",
                "namespace": "kube-system",
                "labels": {
                    "app": "cluster-autoscaler"
                }
            },
            "spec": {
                "replicas": 1,
                "selector": {
                    "matchLabels": {
                        "app": "cluster-autoscaler"
                    }
                },
                "template": {
                    "metadata": {
                        "labels": {
                            "app": "cluster-autoscaler"
                        }
                    },
                    "spec": {
                        "serviceAccountName": "cluster-autoscaler",
                        "containers": [
                            {
                                "name": "cluster-autoscaler",
                                "image": "k8s.gcr.io/autoscaling/cluster-autoscaler:v1.28.0",
                                "command": [
                                    "./cluster-autoscaler",
                                    "--v=4",
                                    "--stderrthreshold=info",
                                    "--cloud-provider=aws",
                                    "--skip-nodes-with-local-storage=false",
                                    "--expander=least-waste",
                                    f"--node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/{self.cluster_name}",
                                    "--balance-similar-node-groups",
                                    "--skip-nodes-with-system-pods=false",
                                    "--scale-down-delay-after-add=10m",
                                    "--scale-down-unneeded-time=10m",
                                    "--scale-down-delay-after-delete=10s",
                                    "--scale-down-utilization-threshold=0.5"
                                ],
                                "resources": {
                                    "limits": {
                                        "cpu": "100m",
                                        "memory": "300Mi"
                                    },
                                    "requests": {
                                        "cpu": "100m",
                                        "memory": "300Mi"
                                    }
                                },
                                "env": [
                                    {
                                        "name": "AWS_REGION",
                                        "value": self.region
                                    }
                                ]
                            }
                        ],
                        "nodeSelector": {
                            "kubernetes.io/os": "linux"
                        }
                    }
                }
            }
        }

        self.cluster.add_manifest("ClusterAutoscaler", cluster_autoscaler_deployment)

        # Create demo applications namespace
        demo_namespace = self.cluster.add_manifest(
            "DemoNamespace",
            {
                "apiVersion": "v1",
                "kind": "Namespace",
                "metadata": {
                    "name": "demo-apps"
                }
            }
        )

        # Deploy sample CPU-intensive application with HPA
        cpu_demo_app = {
            "apiVersion": "apps/v1",
            "kind": "Deployment",
            "metadata": {
                "name": "cpu-demo",
                "namespace": "demo-apps"
            },
            "spec": {
                "replicas": 2,
                "selector": {
                    "matchLabels": {
                        "app": "cpu-demo"
                    }
                },
                "template": {
                    "metadata": {
                        "labels": {
                            "app": "cpu-demo"
                        }
                    },
                    "spec": {
                        "containers": [
                            {
                                "name": "cpu-demo",
                                "image": "k8s.gcr.io/hpa-example",
                                "ports": [
                                    {
                                        "containerPort": 80
                                    }
                                ],
                                "resources": {
                                    "requests": {
                                        "cpu": "100m",
                                        "memory": "128Mi"
                                    },
                                    "limits": {
                                        "cpu": "500m",
                                        "memory": "256Mi"
                                    }
                                }
                            }
                        ]
                    }
                }
            }
        }

        cpu_demo_service = {
            "apiVersion": "v1",
            "kind": "Service",
            "metadata": {
                "name": "cpu-demo-service",
                "namespace": "demo-apps"
            },
            "spec": {
                "selector": {
                    "app": "cpu-demo"
                },
                "ports": [
                    {
                        "port": 80,
                        "targetPort": 80
                    }
                ]
            }
        }

        cpu_demo_hpa = {
            "apiVersion": "autoscaling/v2",
            "kind": "HorizontalPodAutoscaler",
            "metadata": {
                "name": "cpu-demo-hpa",
                "namespace": "demo-apps"
            },
            "spec": {
                "scaleTargetRef": {
                    "apiVersion": "apps/v1",
                    "kind": "Deployment",
                    "name": "cpu-demo"
                },
                "minReplicas": 2,
                "maxReplicas": 20,
                "metrics": [
                    {
                        "type": "Resource",
                        "resource": {
                            "name": "cpu",
                            "target": {
                                "type": "Utilization",
                                "averageUtilization": 50
                            }
                        }
                    }
                ],
                "behavior": {
                    "scaleDown": {
                        "stabilizationWindowSeconds": 300,
                        "policies": [
                            {
                                "type": "Percent",
                                "value": 50,
                                "periodSeconds": 60
                            }
                        ]
                    },
                    "scaleUp": {
                        "stabilizationWindowSeconds": 60,
                        "policies": [
                            {
                                "type": "Percent",
                                "value": 100,
                                "periodSeconds": 60
                            }
                        ]
                    }
                }
            }
        }

        self.cluster.add_manifest("CPUDemoApp", cpu_demo_app)
        self.cluster.add_manifest("CPUDemoService", cpu_demo_service)
        self.cluster.add_manifest("CPUDemoHPA", cpu_demo_hpa)

        # Add Pod Disruption Budget
        cpu_demo_pdb = {
            "apiVersion": "policy/v1",
            "kind": "PodDisruptionBudget",
            "metadata": {
                "name": "cpu-demo-pdb",
                "namespace": "demo-apps"
            },
            "spec": {
                "minAvailable": 1,
                "selector": {
                    "matchLabels": {
                        "app": "cpu-demo"
                    }
                }
            }
        }

        self.cluster.add_manifest("CPUDemoPDB", cpu_demo_pdb)

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for the stack."""
        CfnOutput(
            self,
            "ClusterName",
            description="EKS Cluster Name",
            value=self.cluster.cluster_name,
        )

        CfnOutput(
            self,
            "ClusterEndpoint",
            description="EKS Cluster Endpoint",
            value=self.cluster.cluster_endpoint,
        )

        CfnOutput(
            self,
            "ClusterArn",
            description="EKS Cluster ARN",
            value=self.cluster.cluster_arn,
        )

        CfnOutput(
            self,
            "ClusterSecurityGroupId",
            description="EKS Cluster Security Group ID",
            value=self.cluster.cluster_security_group_id,
        )

        CfnOutput(
            self,
            "ClusterAutoscalerRoleArn",
            description="Cluster Autoscaler IAM Role ARN",
            value=self.cluster_autoscaler_role.role_arn,
        )

        CfnOutput(
            self,
            "VpcId",
            description="VPC ID",
            value=self.vpc.vpc_id,
        )

        CfnOutput(
            self,
            "KubectlCommand",
            description="Command to configure kubectl",
            value=f"aws eks update-kubeconfig --region {self.region} --name {self.cluster_name}",
        )


def main():
    """Main function to create and deploy the CDK application."""
    app = App()

    # Get configuration from environment variables or use defaults
    cluster_name = app.node.try_get_context("cluster_name") or "eks-autoscaling-demo"
    kubernetes_version = app.node.try_get_context("kubernetes_version") or "1.28"
    
    # Get AWS account and region
    account = os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = os.environ.get("CDK_DEFAULT_REGION", "us-east-1")

    # Create the EKS auto-scaling stack
    EKSAutoScalingStack(
        app,
        "EKSAutoScalingStack",
        cluster_name=cluster_name,
        kubernetes_version=kubernetes_version,
        env=Environment(account=account, region=region),
        description="EKS cluster with comprehensive auto-scaling capabilities including HPA and Cluster Autoscaler",
        tags={
            "Project": "EKS-AutoScaling-Demo",
            "Environment": "Development",
            "Owner": "DevOps-Team",
        },
    )

    app.synth()


if __name__ == "__main__":
    main()