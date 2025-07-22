#!/usr/bin/env python3
"""
CDK Python application for EKS Node Groups with Spot Instances and Mixed Instance Types

This application creates cost-optimized EKS node groups using EC2 Spot instances
and mixed instance types to achieve up to 90% cost savings while maintaining
high availability through intelligent instance diversification.
"""

import os
from typing import List, Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    Tags,
    aws_ec2 as ec2,
    aws_eks as eks,
    aws_iam as iam,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
)
from constructs import Construct


class EksSpotNodeGroupsStack(Stack):
    """
    CDK Stack for EKS Node Groups with Spot Instances and Mixed Instance Types
    
    This stack creates:
    - EKS cluster with VPC and subnets
    - Spot instance node group with mixed instance types
    - On-Demand backup node group
    - IAM roles and policies
    - CloudWatch monitoring and alarms
    - SNS topic for notifications
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        cluster_name: str,
        node_group_role_name: str,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.cluster_name = cluster_name
        self.node_group_role_name = node_group_role_name
        
        # Create VPC for EKS cluster
        self.vpc = self._create_vpc()
        
        # Create IAM role for EKS cluster
        self.cluster_role = self._create_cluster_role()
        
        # Create IAM role for node groups
        self.node_group_role = self._create_node_group_role()
        
        # Create EKS cluster
        self.cluster = self._create_eks_cluster()
        
        # Create Spot instance node group
        self.spot_node_group = self._create_spot_node_group()
        
        # Create On-Demand backup node group
        self.ondemand_node_group = self._create_ondemand_node_group()
        
        # Create CloudWatch monitoring
        self.monitoring = self._create_monitoring()
        
        # Create outputs
        self._create_outputs()
        
        # Apply tags
        self._apply_tags()

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC with public and private subnets for EKS cluster"""
        vpc = ec2.Vpc(
            self,
            "EksVpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,
            nat_gateways=2,
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
        
        # Tag subnets for EKS cluster discovery
        for subnet in vpc.private_subnets:
            Tags.of(subnet).add(
                f"kubernetes.io/cluster/{self.cluster_name}",
                "owned"
            )
            Tags.of(subnet).add(
                "kubernetes.io/role/internal-elb",
                "1"
            )
        
        for subnet in vpc.public_subnets:
            Tags.of(subnet).add(
                f"kubernetes.io/cluster/{self.cluster_name}",
                "owned"
            )
            Tags.of(subnet).add(
                "kubernetes.io/role/elb",
                "1"
            )
        
        return vpc

    def _create_cluster_role(self) -> iam.Role:
        """Create IAM role for EKS cluster service"""
        role = iam.Role(
            self,
            "EksClusterRole",
            assumed_by=iam.ServicePrincipal("eks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonEKSClusterPolicy"
                ),
            ],
        )
        
        return role

    def _create_node_group_role(self) -> iam.Role:
        """Create IAM role for EKS node groups"""
        role = iam.Role(
            self,
            "EksNodeGroupRole",
            role_name=self.node_group_role_name,
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonEKSWorkerNodePolicy"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonEKS_CNI_Policy"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonEC2ContainerRegistryReadOnly"
                ),
            ],
        )
        
        # Add additional policy for Spot instance management
        spot_policy = iam.Policy(
            self,
            "SpotInstancePolicy",
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "ec2:DescribeSpotInstanceRequests",
                        "ec2:DescribeSpotPriceHistory",
                        "ec2:RequestSpotInstances",
                        "ec2:CancelSpotInstanceRequests",
                    ],
                    resources=["*"],
                ),
            ],
        )
        
        role.attach_inline_policy(spot_policy)
        
        return role

    def _create_eks_cluster(self) -> eks.Cluster:
        """Create EKS cluster with security and monitoring configurations"""
        cluster = eks.Cluster(
            self,
            "EksCluster",
            cluster_name=self.cluster_name,
            version=eks.KubernetesVersion.V1_28,
            role=self.cluster_role,
            vpc=self.vpc,
            vpc_subnets=[ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            )],
            endpoint_access=eks.EndpointAccess.PUBLIC_AND_PRIVATE,
            default_capacity=0,  # We'll add node groups separately
            cluster_logging=[
                eks.ClusterLoggingTypes.API,
                eks.ClusterLoggingTypes.AUDIT,
                eks.ClusterLoggingTypes.AUTHENTICATOR,
                eks.ClusterLoggingTypes.CONTROLLER_MANAGER,
                eks.ClusterLoggingTypes.SCHEDULER,
            ],
        )
        
        # Install AWS Node Termination Handler
        cluster.add_helm_chart(
            "aws-node-termination-handler",
            chart="aws-node-termination-handler",
            repository="https://aws.github.io/eks-charts",
            namespace="kube-system",
            values={
                "nodeSelector": {
                    "kubernetes.io/os": "linux"
                },
                "tolerations": [
                    {
                        "operator": "Exists"
                    }
                ],
                "enableSpotInterruptionDraining": True,
                "enableRebalanceMonitoring": True,
                "enableScheduledEventDraining": True,
                "metadataHttpEndpoint": "http://169.254.169.254:80",
                "metadataHttpTokens": "required",
                "metadataHttpPutResponseHopLimit": 2,
            },
        )
        
        # Install Cluster Autoscaler
        cluster.add_helm_chart(
            "cluster-autoscaler",
            chart="cluster-autoscaler",
            repository="https://kubernetes.github.io/autoscaler",
            namespace="kube-system",
            values={
                "autoDiscovery": {
                    "clusterName": self.cluster_name,
                    "enabled": True,
                },
                "awsRegion": self.region,
                "extraArgs": {
                    "v": 4,
                    "stderrthreshold": "info",
                    "cloud-provider": "aws",
                    "skip-nodes-with-local-storage": False,
                    "expander": "least-waste",
                    "node-group-auto-discovery": f"asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/{self.cluster_name}",
                },
                "rbac": {
                    "serviceAccount": {
                        "annotations": {
                            "eks.amazonaws.com/role-arn": f"arn:aws:iam::{self.account}:role/ClusterAutoscalerRole"
                        }
                    }
                },
            },
        )
        
        return cluster

    def _create_spot_node_group(self) -> eks.Nodegroup:
        """Create Spot instance node group with mixed instance types"""
        spot_node_group = eks.Nodegroup(
            self,
            "SpotNodeGroup",
            cluster=self.cluster,
            nodegroup_name="spot-mixed-nodegroup",
            node_role=self.node_group_role,
            subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
            instance_types=[
                ec2.InstanceType("m5.large"),
                ec2.InstanceType("m5a.large"),
                ec2.InstanceType("c5.large"),
                ec2.InstanceType("c5a.large"),
                ec2.InstanceType("m5.xlarge"),
                ec2.InstanceType("c5.xlarge"),
            ],
            capacity_type=eks.CapacityType.SPOT,
            scaling_config=eks.ScalingConfig(
                min_size=2,
                max_size=10,
                desired_size=4,
            ),
            disk_size=30,
            ami_type=eks.NodegroupAmiType.AL2_X86_64,
            labels={
                "node-type": "spot",
                "cost-optimization": "enabled",
            },
            tags={
                "Environment": "production",
                "NodeType": "spot",
                "CostOptimization": "enabled",
                f"k8s.io/cluster-autoscaler/{self.cluster_name}": "owned",
                "k8s.io/cluster-autoscaler/enabled": "true",
            },
            update_config=eks.UpdateConfig(
                max_unavailable=1,
            ),
        )
        
        return spot_node_group

    def _create_ondemand_node_group(self) -> eks.Nodegroup:
        """Create On-Demand backup node group for critical workloads"""
        ondemand_node_group = eks.Nodegroup(
            self,
            "OnDemandNodeGroup",
            cluster=self.cluster,
            nodegroup_name="ondemand-backup-nodegroup",
            node_role=self.node_group_role,
            subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
            instance_types=[
                ec2.InstanceType("m5.large"),
                ec2.InstanceType("c5.large"),
            ],
            capacity_type=eks.CapacityType.ON_DEMAND,
            scaling_config=eks.ScalingConfig(
                min_size=1,
                max_size=3,
                desired_size=2,
            ),
            disk_size=30,
            ami_type=eks.NodegroupAmiType.AL2_X86_64,
            labels={
                "node-type": "on-demand",
                "workload-type": "critical",
            },
            tags={
                "Environment": "production",
                "NodeType": "on-demand",
                "WorkloadType": "critical",
                f"k8s.io/cluster-autoscaler/{self.cluster_name}": "owned",
                "k8s.io/cluster-autoscaler/enabled": "true",
            },
            update_config=eks.UpdateConfig(
                max_unavailable=1,
            ),
        )
        
        return ondemand_node_group

    def _create_monitoring(self) -> Dict[str, Any]:
        """Create CloudWatch monitoring and alerting"""
        # Create SNS topic for alerts
        sns_topic = sns.Topic(
            self,
            "EksAlertsTopic",
            topic_name=f"eks-{self.cluster_name}-alerts",
            display_name="EKS Cluster Alerts",
        )
        
        # Create CloudWatch Log Group for Spot interruptions
        log_group = logs.LogGroup(
            self,
            "SpotInterruptionLogGroup",
            log_group_name=f"/aws/eks/{self.cluster_name}/spot-interruptions",
            retention=logs.RetentionDays.ONE_MONTH,
        )
        
        # Create CloudWatch alarm for high Spot interruption rate
        spot_interruption_alarm = cloudwatch.Alarm(
            self,
            "HighSpotInterruptionAlarm",
            alarm_name=f"EKS-{self.cluster_name}-HighSpotInterruptions",
            alarm_description="High spot instance interruption rate",
            metric=cloudwatch.Metric(
                namespace="AWS/EKS",
                metric_name="SpotInterruptionRate",
                dimensions_map={
                    "ClusterName": self.cluster_name,
                },
                statistic="Sum",
                period=cdk.Duration.minutes(5),
            ),
            threshold=5,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        # Add SNS action to alarm
        spot_interruption_alarm.add_alarm_action(
            cloudwatch.SnsAction(sns_topic)
        )
        
        # Create CloudWatch alarm for node group health
        node_health_alarm = cloudwatch.Alarm(
            self,
            "NodeGroupHealthAlarm",
            alarm_name=f"EKS-{self.cluster_name}-NodeGroupHealth",
            alarm_description="EKS node group health monitoring",
            metric=cloudwatch.Metric(
                namespace="AWS/EKS",
                metric_name="cluster_failed_node_count",
                dimensions_map={
                    "ClusterName": self.cluster_name,
                },
                statistic="Sum",
                period=cdk.Duration.minutes(5),
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        # Add SNS action to alarm
        node_health_alarm.add_alarm_action(
            cloudwatch.SnsAction(sns_topic)
        )
        
        return {
            "sns_topic": sns_topic,
            "log_group": log_group,
            "spot_interruption_alarm": spot_interruption_alarm,
            "node_health_alarm": node_health_alarm,
        }

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs"""
        CfnOutput(
            self,
            "ClusterName",
            value=self.cluster.cluster_name,
            description="EKS Cluster Name",
        )
        
        CfnOutput(
            self,
            "ClusterEndpoint",
            value=self.cluster.cluster_endpoint,
            description="EKS Cluster Endpoint",
        )
        
        CfnOutput(
            self,
            "ClusterArn",
            value=self.cluster.cluster_arn,
            description="EKS Cluster ARN",
        )
        
        CfnOutput(
            self,
            "SpotNodeGroupName",
            value=self.spot_node_group.nodegroup_name,
            description="Spot Node Group Name",
        )
        
        CfnOutput(
            self,
            "OnDemandNodeGroupName",
            value=self.ondemand_node_group.nodegroup_name,
            description="On-Demand Node Group Name",
        )
        
        CfnOutput(
            self,
            "NodeGroupRoleArn",
            value=self.node_group_role.role_arn,
            description="Node Group IAM Role ARN",
        )
        
        CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID",
        )
        
        CfnOutput(
            self,
            "AlertsTopicArn",
            value=self.monitoring["sns_topic"].topic_arn,
            description="SNS Topic ARN for alerts",
        )
        
        CfnOutput(
            self,
            "KubectlCommand",
            value=f"aws eks update-kubeconfig --region {self.region} --name {self.cluster_name}",
            description="Command to configure kubectl",
        )

    def _apply_tags(self) -> None:
        """Apply consistent tags to all resources"""
        tags = {
            "Project": "EKS-Spot-Mixed-Instances",
            "Environment": "production",
            "CostCenter": "engineering",
            "Owner": "platform-team",
            "CreatedBy": "CDK",
        }
        
        for key, value in tags.items():
            Tags.of(self).add(key, value)


class EksSpotNodeGroupsApp(cdk.App):
    """CDK Application for EKS Spot Node Groups"""
    
    def __init__(self) -> None:
        super().__init__()
        
        # Environment configuration
        env = Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-west-2"),
        )
        
        # Generate unique identifier for resources
        import time
        random_suffix = str(int(time.time()) % 1000000)
        
        # Stack configuration
        cluster_name = f"cost-optimized-eks-{random_suffix}"
        node_group_role_name = f"EKSNodeGroupRole-{random_suffix}"
        
        # Create the main stack
        EksSpotNodeGroupsStack(
            self,
            "EksSpotNodeGroupsStack",
            cluster_name=cluster_name,
            node_group_role_name=node_group_role_name,
            env=env,
            description="EKS Node Groups with Spot Instances and Mixed Instance Types for cost optimization",
        )


# Application entry point
if __name__ == "__main__":
    app = EksSpotNodeGroupsApp()
    app.synth()