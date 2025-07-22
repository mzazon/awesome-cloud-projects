#!/usr/bin/env python3
"""
CDK Application for Real-Time Streaming Analytics with EMR on EKS and Apache Flink

This CDK application deploys a complete streaming analytics platform using:
- Amazon EKS cluster optimized for EMR workloads
- EMR on EKS virtual cluster for Flink job management
- Kinesis Data Streams for real-time data ingestion
- S3 bucket for checkpoints and data storage
- IAM roles with least privilege access
- Monitoring and observability stack

Author: AWS CDK Generator
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    Duration,
    Tags,
    aws_s3 as s3,
    aws_iam as iam,
    aws_kinesis as kinesis,
    aws_eks as eks,
    aws_ec2 as ec2,
    aws_emrcontainers as emr_containers,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_kms as kms,
)
from constructs import Construct
import json
from typing import Dict, List, Optional


class FlinkStreamingAnalyticsStack(Stack):
    """
    CDK Stack for EMR on EKS Flink Streaming Analytics Platform
    
    This stack creates a production-ready streaming analytics platform capable of
    processing millions of events per second with exactly-once processing guarantees.
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str,
        cluster_name: str = "emr-flink-analytics",
        namespace: str = "emr-flink",
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration parameters
        self.cluster_name = cluster_name
        self.namespace = namespace
        
        # Generate unique suffix for global resources
        self.unique_suffix = self.node.try_get_context("unique_suffix") or "demo"
        
        # Create VPC for the EKS cluster
        self.vpc = self._create_vpc()
        
        # Create KMS key for encryption
        self.kms_key = self._create_kms_key()
        
        # Create S3 bucket for checkpoints and data storage
        self.data_bucket = self._create_s3_bucket()
        
        # Create Kinesis data streams
        self.trading_stream, self.market_stream = self._create_kinesis_streams()
        
        # Create IAM roles
        self.emr_service_role, self.job_execution_role = self._create_iam_roles()
        
        # Create EKS cluster
        self.eks_cluster = self._create_eks_cluster()
        
        # Create EMR virtual cluster
        self.virtual_cluster = self._create_emr_virtual_cluster()
        
        # Create CloudWatch log groups
        self.log_groups = self._create_log_groups()
        
        # Create monitoring dashboards
        self._create_monitoring_dashboard()
        
        # Apply tags to all resources
        self._apply_tags()
        
        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC with public and private subnets for EKS cluster"""
        return ec2.Vpc(
            self, "FlinkVPC",
            vpc_name=f"{self.cluster_name}-vpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,
            nat_gateways=2,
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

    def _create_kms_key(self) -> kms.Key:
        """Create KMS key for encryption of S3 bucket and EKS secrets"""
        return kms.Key(
            self, "FlinkKMSKey",
            description="KMS key for Flink streaming analytics platform",
            enable_key_rotation=True,
            removal_policy=cdk.RemovalPolicy.DESTROY
        )

    def _create_s3_bucket(self) -> s3.Bucket:
        """Create S3 bucket for Flink checkpoints and data storage"""
        bucket = s3.Bucket(
            self, "FlinkDataBucket",
            bucket_name=f"emr-flink-analytics-{self.unique_suffix}",
            encryption=s3.BucketEncryption.KMS,
            encryption_key=self.kms_key,
            versioned=True,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="FlinkCheckpointLifecycle",
                    enabled=True,
                    prefix="checkpoints/",
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.STANDARD_IA,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ]
                ),
                s3.LifecycleRule(
                    id="FlinkResultsLifecycle",
                    enabled=True,
                    prefix="results/",
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.STANDARD_IA,
                            transition_after=Duration.days(7)
                        )
                    ]
                )
            ],
            removal_policy=cdk.RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )
        
        return bucket

    def _create_kinesis_streams(self) -> tuple[kinesis.Stream, kinesis.Stream]:
        """Create Kinesis data streams for real-time data ingestion"""
        # Trading events stream - higher throughput
        trading_stream = kinesis.Stream(
            self, "TradingEventsStream",
            stream_name=f"trading-events-{self.unique_suffix}",
            shard_count=4,
            retention_period=Duration.hours(24),
            encryption=kinesis.StreamEncryption.KMS,
            encryption_key=self.kms_key
        )
        
        # Market data stream - moderate throughput
        market_stream = kinesis.Stream(
            self, "MarketDataStream",
            stream_name=f"market-data-{self.unique_suffix}",
            shard_count=2,
            retention_period=Duration.hours(24),
            encryption=kinesis.StreamEncryption.KMS,
            encryption_key=self.kms_key
        )
        
        return trading_stream, market_stream

    def _create_iam_roles(self) -> tuple[iam.Role, iam.Role]:
        """Create IAM roles for EMR service and job execution"""
        
        # EMR Containers Service Role
        emr_service_role = iam.Role(
            self, "EMRContainersServiceRole",
            role_name="EMRContainersServiceRole",
            assumed_by=iam.ServicePrincipal("emr-containers.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonEMRContainersServiceRolePolicy"
                )
            ]
        )
        
        # Job Execution Role with OIDC trust relationship
        job_execution_role = iam.Role(
            self, "EMRFlinkJobExecutionRole",
            role_name="EMRFlinkJobExecutionRole",
            # Trust relationship will be updated after EKS cluster creation
            assumed_by=iam.ServicePrincipal("emr-containers.amazonaws.com")
        )
        
        # Add permissions to job execution role
        job_execution_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket"
                ],
                resources=[
                    self.data_bucket.bucket_arn,
                    f"{self.data_bucket.bucket_arn}/*"
                ]
            )
        )
        
        job_execution_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "kinesis:DescribeStream",
                    "kinesis:DescribeStreamSummary",
                    "kinesis:GetRecords",
                    "kinesis:GetShardIterator",
                    "kinesis:ListShards",
                    "kinesis:ListStreams",
                    "kinesis:PutRecord",
                    "kinesis:PutRecords"
                ],
                resources=[
                    self.trading_stream.stream_arn,
                    self.market_stream.stream_arn
                ]
            )
        )
        
        job_execution_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                    "logs:DescribeLogGroups",
                    "logs:DescribeLogStreams"
                ],
                resources=["*"]
            )
        )
        
        job_execution_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudwatch:PutMetricData"
                ],
                resources=["*"]
            )
        )
        
        # KMS permissions for encryption
        job_execution_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "kms:Decrypt",
                    "kms:GenerateDataKey"
                ],
                resources=[self.kms_key.key_arn]
            )
        )
        
        return emr_service_role, job_execution_role

    def _create_eks_cluster(self) -> eks.Cluster:
        """Create EKS cluster optimized for EMR workloads"""
        
        # Create cluster admin role
        cluster_admin_role = iam.Role(
            self, "ClusterAdminRole",
            assumed_by=iam.AccountRootPrincipal(),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKSClusterPolicy")
            ]
        )
        
        # Create EKS cluster
        cluster = eks.Cluster(
            self, "EMRFlinkCluster",
            cluster_name=self.cluster_name,
            version=eks.KubernetesVersion.V1_28,
            vpc=self.vpc,
            vpc_subnets=[ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS)],
            masters_role=cluster_admin_role,
            endpoint_access=eks.EndpointAccess.PUBLIC_AND_PRIVATE,
            secrets_encryption_key=self.kms_key,
            default_capacity=0,  # We'll add managed node groups separately
            cluster_logging=[
                eks.ClusterLoggingTypes.API,
                eks.ClusterLoggingTypes.AUDIT,
                eks.ClusterLoggingTypes.AUTHENTICATOR,
                eks.ClusterLoggingTypes.CONTROLLER_MANAGER,
                eks.ClusterLoggingTypes.SCHEDULER
            ]
        )
        
        # Add managed node group for EMR workloads
        cluster.add_nodegroup_capacity(
            "EMRFlinkWorkers",
            instance_types=[ec2.InstanceType("m5.xlarge")],
            min_size=2,
            max_size=10,
            desired_size=4,
            disk_size=100,
            ami_type=eks.NodegroupAmiType.AL2_X86_64,
            capacity_type=eks.CapacityType.ON_DEMAND,
            subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            tags={
                "Environment": "analytics",
                "Project": "flink-streaming",
                "k8s.io/cluster-autoscaler/enabled": "true",
                f"k8s.io/cluster-autoscaler/{self.cluster_name}": "owned"
            }
        )
        
        # Install AWS Load Balancer Controller
        cluster.add_helm_chart(
            "AWSLoadBalancerController",
            chart="aws-load-balancer-controller",
            repository="https://aws.github.io/eks-charts",
            namespace="kube-system",
            values={
                "clusterName": self.cluster_name,
                "serviceAccount": {
                    "create": False,
                    "name": "aws-load-balancer-controller"
                }
            }
        )
        
        # Create service account for EMR jobs
        cluster.add_service_account(
            "EMRFlinkServiceAccount",
            name="emr-containers-sa-flink-operator",
            namespace=self.namespace
        )
        
        # Update job execution role trust policy for OIDC
        oidc_provider_arn = cluster.open_id_connect_provider.open_id_connect_provider_arn
        oidc_issuer = cluster.cluster_open_id_connect_issuer_url.replace("https://", "")
        
        self.job_execution_role.assume_role_policy.add_statements(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                principals=[
                    iam.FederatedPrincipal(
                        oidc_provider_arn,
                        {
                            "StringLike": {
                                f"{oidc_issuer}:sub": f"system:serviceaccount:{self.namespace}:*"
                            }
                        },
                        "sts:AssumeRoleWithWebIdentity"
                    )
                ]
            )
        )
        
        return cluster

    def _create_emr_virtual_cluster(self) -> emr_containers.CfnVirtualCluster:
        """Create EMR virtual cluster for job management"""
        return emr_containers.CfnVirtualCluster(
            self, "FlinkAnalyticsVirtualCluster",
            name="flink-analytics-cluster",
            container_provider=emr_containers.CfnVirtualCluster.ContainerProviderProperty(
                id=self.eks_cluster.cluster_name,
                type="EKS",
                info=emr_containers.CfnVirtualCluster.ContainerInfoProperty(
                    eks_info=emr_containers.CfnVirtualCluster.EksInfoProperty(
                        namespace=self.namespace
                    )
                )
            ),
            tags=[
                cdk.CfnTag(key="Environment", value="analytics"),
                cdk.CfnTag(key="Project", value="flink-streaming")
            ]
        )

    def _create_log_groups(self) -> Dict[str, logs.LogGroup]:
        """Create CloudWatch log groups for monitoring"""
        log_groups = {}
        
        # EMR containers log group
        log_groups["emr"] = logs.LogGroup(
            self, "EMRContainersLogGroup",
            log_group_name="/aws/emr-containers/flink",
            retention=logs.RetentionDays.ONE_MONTH,
            encryption_key=self.kms_key,
            removal_policy=cdk.RemovalPolicy.DESTROY
        )
        
        # Application log group
        log_groups["application"] = logs.LogGroup(
            self, "FlinkApplicationLogGroup",
            log_group_name=f"/aws/flink/{self.cluster_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            encryption_key=self.kms_key,
            removal_policy=cdk.RemovalPolicy.DESTROY
        )
        
        return log_groups

    def _create_monitoring_dashboard(self) -> None:
        """Create CloudWatch dashboard for monitoring Flink jobs"""
        dashboard = cloudwatch.Dashboard(
            self, "FlinkAnalyticsDashboard",
            dashboard_name=f"Flink-Analytics-{self.cluster_name}"
        )
        
        # Add widgets for key metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Kinesis Streams - Incoming Records",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/Kinesis",
                        metric_name="IncomingRecords",
                        dimensions_map={
                            "StreamName": self.trading_stream.stream_name
                        },
                        statistic="Sum",
                        period=Duration.minutes(5)
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/Kinesis",
                        metric_name="IncomingRecords",
                        dimensions_map={
                            "StreamName": self.market_stream.stream_name
                        },
                        statistic="Sum",
                        period=Duration.minutes(5)
                    )
                ]
            ),
            cloudwatch.GraphWidget(
                title="EKS Cluster - Node Resources",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/EKS",
                        metric_name="cluster_node_count",
                        dimensions_map={
                            "ClusterName": self.cluster_name
                        },
                        statistic="Average",
                        period=Duration.minutes(5)
                    )
                ]
            )
        )
        
        dashboard.add_widgets(
            cloudwatch.SingleValueWidget(
                title="Virtual Cluster Status",
                metrics=[
                    cloudwatch.Metric(
                        namespace="AWS/EMR-Containers",
                        metric_name="RunningJobsCount",
                        dimensions_map={
                            "VirtualClusterId": self.virtual_cluster.ref
                        },
                        statistic="Maximum",
                        period=Duration.minutes(5)
                    )
                ]
            )
        )

    def _apply_tags(self) -> None:
        """Apply consistent tags to all resources"""
        tags_to_apply = {
            "Project": "flink-streaming-analytics",
            "Environment": "production",
            "Owner": "data-engineering",
            "CostCenter": "analytics",
            "ManagedBy": "CDK"
        }
        
        for key, value in tags_to_apply.items():
            Tags.of(self).add(key, value)

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources"""
        CfnOutput(
            self, "EKSClusterName",
            value=self.eks_cluster.cluster_name,
            description="Name of the EKS cluster"
        )
        
        CfnOutput(
            self, "EMRVirtualClusterId",
            value=self.virtual_cluster.ref,
            description="EMR Virtual Cluster ID"
        )
        
        CfnOutput(
            self, "DataBucketName",
            value=self.data_bucket.bucket_name,
            description="S3 bucket for Flink checkpoints and data"
        )
        
        CfnOutput(
            self, "TradingStreamName",
            value=self.trading_stream.stream_name,
            description="Kinesis stream for trading events"
        )
        
        CfnOutput(
            self, "MarketDataStreamName",
            value=self.market_stream.stream_name,
            description="Kinesis stream for market data"
        )
        
        CfnOutput(
            self, "JobExecutionRoleArn",
            value=self.job_execution_role.role_arn,
            description="IAM role ARN for EMR job execution"
        )
        
        CfnOutput(
            self, "KubeconfigCommand",
            value=f"aws eks update-kubeconfig --region {self.region} --name {self.cluster_name}",
            description="Command to update kubectl configuration"
        )


class FlinkStreamingAnalyticsApp(cdk.App):
    """CDK Application class"""
    
    def __init__(self) -> None:
        super().__init__()
        
        # Create the main stack
        FlinkStreamingAnalyticsStack(
            self, "FlinkStreamingAnalyticsStack",
            cluster_name="emr-flink-analytics",
            namespace="emr-flink",
            env=cdk.Environment(
                account=self.node.try_get_context("account"),
                region=self.node.try_get_context("region")
            ),
            description="Real-time streaming analytics platform with EMR on EKS and Apache Flink"
        )


def main() -> None:
    """Main function to run the CDK application"""
    app = FlinkStreamingAnalyticsApp()
    app.synth()


if __name__ == "__main__":
    main()