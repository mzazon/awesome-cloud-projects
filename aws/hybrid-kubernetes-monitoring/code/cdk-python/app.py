#!/usr/bin/env python3
"""
CDK Application for Hybrid Kubernetes Monitoring with EKS Hybrid Nodes

This CDK application deploys a complete hybrid Kubernetes monitoring solution that includes:
- Amazon EKS cluster with hybrid node support
- AWS Fargate profile for cloud workloads  
- CloudWatch Observability add-on with Container Insights
- Custom monitoring infrastructure with dashboards and alarms
- VPC with public/private subnets for hybrid connectivity
- IAM roles and policies following least privilege principles
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_ec2 as ec2,
    aws_eks as eks,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    CfnOutput,
    Duration,
    RemovalPolicy,
)
from constructs import Construct
from typing import Dict, List, Optional
import json


class HybridKubernetesMonitoringStack(Stack):
    """
    CDK Stack for Hybrid Kubernetes Monitoring with EKS and CloudWatch
    
    This stack creates a comprehensive monitoring solution for hybrid Kubernetes
    environments using Amazon EKS Hybrid Nodes and CloudWatch observability.
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        cluster_name: Optional[str] = None,
        hybrid_cidr_blocks: Optional[List[str]] = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters with defaults
        self.cluster_name = cluster_name or f"hybrid-monitoring-cluster"
        self.hybrid_cidrs = hybrid_cidr_blocks or ["10.100.0.0/16"]
        self.cloudwatch_namespace = "EKS/HybridMonitoring"

        # Create VPC for EKS cluster
        self.vpc = self._create_vpc()
        
        # Create IAM roles
        self.cluster_role = self._create_cluster_service_role()
        self.fargate_role = self._create_fargate_execution_role()
        self.cloudwatch_role = self._create_cloudwatch_observability_role()
        
        # Create EKS cluster with hybrid node support
        self.eks_cluster = self._create_eks_cluster()
        
        # Create Fargate profile for cloud workloads
        self.fargate_profile = self._create_fargate_profile()
        
        # Install CloudWatch Observability add-on
        self._install_cloudwatch_addon()
        
        # Create monitoring infrastructure
        self._create_monitoring_infrastructure()
        
        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """
        Create VPC with public and private subnets for EKS cluster.
        
        The VPC includes:
        - Public subnets for EKS control plane and NAT gateways
        - Private subnets for Fargate workloads
        - Internet Gateway for external connectivity
        - NAT Gateways for private subnet internet access
        
        Returns:
            ec2.Vpc: The created VPC instance
        """
        vpc = ec2.Vpc(
            self,
            "HybridMonitoringVPC",
            vpc_name=f"{self.cluster_name}-vpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="PublicSubnet",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24
                ),
                ec2.SubnetConfiguration(
                    name="PrivateSubnet", 
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True
        )

        # Tag VPC for EKS cluster discovery
        cdk.Tags.of(vpc).add("kubernetes.io/cluster/" + self.cluster_name, "shared")
        
        return vpc

    def _create_cluster_service_role(self) -> iam.Role:
        """
        Create IAM service role for EKS cluster.
        
        This role allows EKS to manage the Kubernetes control plane and
        integrate with other AWS services on your behalf.
        
        Returns:
            iam.Role: The EKS cluster service role
        """
        role = iam.Role(
            self,
            "EKSClusterServiceRole",
            role_name=f"EKSClusterServiceRole-{self.cluster_name}",
            assumed_by=iam.ServicePrincipal("eks.amazonaws.com"),
            description="Service role for EKS cluster management",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKSClusterPolicy")
            ]
        )
        
        return role

    def _create_fargate_execution_role(self) -> iam.Role:
        """
        Create IAM execution role for Fargate profiles.
        
        This role allows Fargate to pull container images and write logs
        to CloudWatch on behalf of your applications.
        
        Returns:
            iam.Role: The Fargate execution role
        """
        role = iam.Role(
            self,
            "EKSFargateExecutionRole",
            role_name=f"EKSFargateExecutionRole-{self.cluster_name}",
            assumed_by=iam.ServicePrincipal("eks-fargate-pods.amazonaws.com"),
            description="Execution role for EKS Fargate profiles",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKSFargatePodExecutionRolePolicy")
            ]
        )
        
        return role

    def _create_cloudwatch_observability_role(self) -> iam.Role:
        """
        Create IAM role for CloudWatch Observability add-on.
        
        This role enables the CloudWatch agent to collect metrics and logs
        from the EKS cluster and publish them to CloudWatch.
        
        Returns:
            iam.Role: The CloudWatch observability role
        """
        role = iam.Role(
            self,
            "CloudWatchObservabilityRole",
            role_name=f"CloudWatchObservabilityRole-{self.cluster_name}",
            description="Role for CloudWatch Observability add-on",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchAgentServerPolicy")
            ]
        )
        
        return role

    def _create_eks_cluster(self) -> eks.Cluster:
        """
        Create EKS cluster with hybrid node support.
        
        The cluster is configured to accept connections from on-premises
        infrastructure while providing a managed Kubernetes control plane.
        
        Returns:
            eks.Cluster: The created EKS cluster
        """
        
        # Create cluster with hybrid node configuration
        cluster = eks.Cluster(
            self,
            "HybridMonitoringCluster",
            cluster_name=self.cluster_name,
            version=eks.KubernetesVersion.V1_31,
            role=self.cluster_role,
            vpc=self.vpc,
            vpc_subnets=[
                ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC)
            ],
            endpoint_access=eks.EndpointAccess.PUBLIC_AND_PRIVATE,
            default_capacity=0,  # No managed node groups by default
            authentication_mode=eks.AuthenticationMode.API_AND_CONFIG_MAP,
            output_cluster_name=True,
            output_config_command=True
        )

        # Add hybrid node network configuration using L1 construct
        cfn_cluster = cluster.node.default_child
        cfn_cluster.add_property_override(
            "RemoteNetworkConfig",
            {
                "RemoteNodeNetworks": [
                    {"Cidrs": self.hybrid_cidrs}
                ]
            }
        )

        return cluster

    def _create_fargate_profile(self) -> eks.FargateProfile:
        """
        Create Fargate profile for cloud workloads.
        
        This profile automatically schedules pods in the 'cloud-apps' namespace
        to run on AWS Fargate, providing serverless compute for cloud workloads.
        
        Returns:
            eks.FargateProfile: The created Fargate profile
        """
        profile = eks.FargateProfile(
            self,
            "CloudWorkloadsFargateProfile",
            cluster=self.eks_cluster,
            fargate_profile_name="cloud-workloads",
            pod_execution_role=self.fargate_role,
            vpc=self.vpc,
            subnet_selection=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
            selectors=[
                eks.Selector(
                    namespace="cloud-apps"
                )
            ]
        )

        return profile

    def _install_cloudwatch_addon(self) -> None:
        """
        Install CloudWatch Observability add-on for comprehensive monitoring.
        
        This add-on enables Container Insights, metrics collection, and log
        aggregation for both Fargate and hybrid node workloads.
        """
        
        # Configure IRSA for CloudWatch Observability add-on
        cloudwatch_sa = self.eks_cluster.add_service_account(
            "CloudWatchObservabilityServiceAccount",
            name="cloudwatch-agent",
            namespace="amazon-cloudwatch"
        )
        
        cloudwatch_sa.role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchAgentServerPolicy")
        )

        # Install CloudWatch Observability add-on using L1 construct
        cloudwatch_addon = eks.CfnAddon(
            self,
            "CloudWatchObservabilityAddon",
            cluster_name=self.eks_cluster.cluster_name,
            addon_name="amazon-cloudwatch-observability",
            addon_version="v2.1.0-eksbuild.1",
            service_account_role_arn=cloudwatch_sa.role.role_arn,
            configuration_values=json.dumps({
                "containerInsights": {
                    "enabled": True
                }
            }),
            resolve_conflicts="OVERWRITE"
        )

        # Ensure add-on is installed after cluster and service account
        cloudwatch_addon.add_dependency(self.eks_cluster.node.default_child)
        cloudwatch_addon.add_dependency(cloudwatch_sa.node.default_child)

    def _create_monitoring_infrastructure(self) -> None:
        """
        Create CloudWatch dashboards and alarms for hybrid monitoring.
        
        This includes:
        - Custom dashboard showing hybrid cluster metrics
        - Alarms for CPU, memory, and node count monitoring
        - Log group for application logs
        """
        
        # Create custom dashboard for hybrid monitoring
        dashboard = cloudwatch.Dashboard(
            self,
            "HybridMonitoringDashboard",
            dashboard_name=f"EKS-Hybrid-Monitoring-{self.cluster_name}",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Hybrid Cluster Capacity",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/EKS",
                                metric_name="cluster_node_count",
                                dimensions_map={"ClusterName": self.cluster_name},
                                statistic="Average",
                                period=Duration.minutes(5)
                            ),
                            cloudwatch.Metric(
                                namespace=self.cloudwatch_namespace,
                                metric_name="HybridNodeCount",
                                statistic="Average",
                                period=Duration.minutes(5)
                            ),
                            cloudwatch.Metric(
                                namespace=self.cloudwatch_namespace,
                                metric_name="FargatePodCount",
                                statistic="Average",
                                period=Duration.minutes(5)
                            )
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.GraphWidget(
                        title="Pod Resource Utilization",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/ContainerInsights",
                                metric_name="pod_cpu_utilization",
                                dimensions_map={"ClusterName": self.cluster_name},
                                statistic="Average",
                                period=Duration.minutes(5)
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/ContainerInsights", 
                                metric_name="pod_memory_utilization",
                                dimensions_map={"ClusterName": self.cluster_name},
                                statistic="Average",
                                period=Duration.minutes(5)
                            )
                        ],
                        left_y_axis=cloudwatch.YAxisProps(min=0, max=100),
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.LogQueryWidget(
                        title="Application Logs from Cloud Apps",
                        log_groups=[
                            logs.LogGroup.from_log_group_name(
                                self,
                                "ApplicationLogsGroup",
                                f"/aws/containerinsights/{self.cluster_name}/application"
                            )
                        ],
                        query_lines=[
                            "fields @timestamp, kubernetes.pod_name, log",
                            "filter kubernetes.namespace_name = \"cloud-apps\"",
                            "sort @timestamp desc",
                            "limit 100"
                        ],
                        width=24,
                        height=6
                    )
                ]
            ]
        )

        # Create CloudWatch alarms
        high_cpu_alarm = cloudwatch.Alarm(
            self,
            "HighCPUAlarm",
            alarm_name=f"EKS-Hybrid-HighCPU-{self.cluster_name}",
            alarm_description="High CPU utilization in hybrid cluster",
            metric=cloudwatch.Metric(
                namespace="AWS/ContainerInsights",
                metric_name="pod_cpu_utilization",
                dimensions_map={"ClusterName": self.cluster_name},
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=80,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        high_memory_alarm = cloudwatch.Alarm(
            self,
            "HighMemoryAlarm", 
            alarm_name=f"EKS-Hybrid-HighMemory-{self.cluster_name}",
            alarm_description="High memory utilization in hybrid cluster",
            metric=cloudwatch.Metric(
                namespace="AWS/ContainerInsights",
                metric_name="pod_memory_utilization", 
                dimensions_map={"ClusterName": self.cluster_name},
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=80,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        low_node_count_alarm = cloudwatch.Alarm(
            self,
            "LowNodeCountAlarm",
            alarm_name=f"EKS-Hybrid-LowNodeCount-{self.cluster_name}",
            alarm_description="Low hybrid node count",
            metric=cloudwatch.Metric(
                namespace=self.cloudwatch_namespace,
                metric_name="HybridNodeCount",
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.BREACHING
        )

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resource information.
        """
        CfnOutput(
            self,
            "ClusterName",
            description="Name of the EKS cluster",
            value=self.eks_cluster.cluster_name
        )

        CfnOutput(
            self,
            "ClusterEndpoint", 
            description="EKS cluster endpoint URL",
            value=self.eks_cluster.cluster_endpoint
        )

        CfnOutput(
            self,
            "ClusterArn",
            description="ARN of the EKS cluster", 
            value=self.eks_cluster.cluster_arn
        )

        CfnOutput(
            self,
            "VPCId",
            description="ID of the VPC",
            value=self.vpc.vpc_id
        )

        CfnOutput(
            self,
            "FargateProfileName",
            description="Name of the Fargate profile for cloud workloads",
            value=self.fargate_profile.fargate_profile_name
        )

        CfnOutput(
            self,
            "DashboardURL",
            description="URL to CloudWatch dashboard",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name=EKS-Hybrid-Monitoring-{self.cluster_name}"
        )

        CfnOutput(
            self,
            "UpdateKubeconfigCommand",
            description="Command to update kubeconfig",
            value=f"aws eks update-kubeconfig --region {self.region} --name {self.cluster_name}"
        )


def main() -> None:
    """
    Main application entry point.
    
    Creates the CDK app and instantiates the hybrid monitoring stack.
    """
    app = cdk.App()
    
    # Get configuration from CDK context or use defaults
    cluster_name = app.node.try_get_context("cluster_name")
    hybrid_cidrs = app.node.try_get_context("hybrid_cidrs")
    
    HybridKubernetesMonitoringStack(
        app,
        "HybridKubernetesMonitoringStack",
        cluster_name=cluster_name,
        hybrid_cidr_blocks=hybrid_cidrs,
        description="Hybrid Kubernetes monitoring with Amazon EKS Hybrid Nodes and CloudWatch",
        env=cdk.Environment(
            account=app.node.try_get_context("account") or None,
            region=app.node.try_get_context("region") or None
        )
    )
    
    app.synth()


if __name__ == "__main__":
    main()