#!/usr/bin/env python3
"""
AWS CDK Python application for EKS cluster logging and monitoring with CloudWatch and Prometheus.

This application creates a comprehensive observability stack for Amazon EKS that includes:
- EKS cluster with comprehensive control plane logging
- CloudWatch Container Insights for infrastructure monitoring
- Fluent Bit for log collection and forwarding
- Amazon Managed Service for Prometheus for metrics collection
- CloudWatch dashboards and alarms for monitoring
- Sample application with Prometheus metrics

Architecture:
- VPC with public/private subnets across multiple AZs
- EKS cluster with managed node groups
- CloudWatch Log Groups for control plane and application logs
- Amazon Managed Prometheus workspace with scraper configuration
- CloudWatch dashboards for comprehensive monitoring
- Sample application demonstrating metrics collection
"""

import os
from typing import Dict, Any, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    StackProps,
    Environment,
    CfnOutput,
    Duration,
    Tags,
    aws_ec2 as ec2,
    aws_eks as eks,
    aws_iam as iam,
    aws_logs as logs,
    aws_aps as aps,
    aws_cloudwatch as cloudwatch,
    aws_ssm as ssm,
)
from constructs import Construct


class EKSObservabilityStack(Stack):
    """
    CDK Stack for EKS Logging and Monitoring with Prometheus.
    
    This stack creates:
    - VPC with public/private subnets
    - EKS cluster with comprehensive logging
    - CloudWatch Container Insights
    - Amazon Managed Prometheus workspace
    - CloudWatch dashboards and alarms
    - Sample application deployment
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        cluster_name: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the EKS Observability Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            cluster_name: Optional name for the EKS cluster
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique cluster name if not provided
        self.cluster_name = cluster_name or f"eks-observability-{self.node.addr[:8]}"
        
        # Create VPC for EKS cluster
        self.vpc = self._create_vpc()
        
        # Create EKS cluster with logging enabled
        self.cluster = self._create_eks_cluster()
        
        # Create CloudWatch Log Groups for comprehensive logging
        self.log_groups = self._create_log_groups()
        
        # Create Amazon Managed Prometheus workspace
        self.prometheus_workspace = self._create_prometheus_workspace()
        
        # Create CloudWatch dashboards for monitoring
        self.dashboard = self._create_cloudwatch_dashboard()
        
        # Create CloudWatch alarms for alerting
        self.alarms = self._create_cloudwatch_alarms()
        
        # Deploy monitoring components to the cluster
        self._deploy_monitoring_components()
        
        # Deploy sample application with metrics
        self._deploy_sample_application()
        
        # Create outputs for easy access
        self._create_outputs()
        
        # Apply tags to all resources
        self._apply_tags()

    def _create_vpc(self) -> ec2.Vpc:
        """
        Create a VPC with public and private subnets across multiple AZs.
        
        Returns:
            ec2.Vpc: The created VPC
        """
        vpc = ec2.Vpc(
            self,
            "EKSObservabilityVPC",
            vpc_name=f"{self.cluster_name}-vpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
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
        
        # Add VPC Flow Logs for network monitoring
        vpc.add_flow_log(
            "VPCFlowLog",
            destination=ec2.FlowLogDestination.to_cloud_watch_logs(
                logs.LogGroup(
                    self,
                    "VPCFlowLogGroup",
                    log_group_name=f"/aws/vpc/{self.cluster_name}/flowlogs",
                    retention=logs.RetentionDays.ONE_WEEK,
                    removal_policy=cdk.RemovalPolicy.DESTROY,
                )
            ),
            traffic_type=ec2.FlowLogTrafficType.ALL,
        )
        
        return vpc

    def _create_eks_cluster(self) -> eks.Cluster:
        """
        Create an EKS cluster with comprehensive logging enabled.
        
        Returns:
            eks.Cluster: The created EKS cluster
        """
        # Create cluster service role
        cluster_role = iam.Role(
            self,
            "EKSClusterRole",
            role_name=f"{self.cluster_name}-cluster-role",
            assumed_by=iam.ServicePrincipal("eks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKSClusterPolicy"),
            ],
        )
        
        # Create node group role
        node_role = iam.Role(
            self,
            "EKSNodeRole",
            role_name=f"{self.cluster_name}-node-role",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKSWorkerNodePolicy"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKS_CNI_Policy"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEC2ContainerRegistryReadOnly"),
                iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchAgentServerPolicy"),
            ],
        )
        
        # Create EKS cluster with comprehensive logging
        cluster = eks.Cluster(
            self,
            "EKSCluster",
            cluster_name=self.cluster_name,
            version=eks.KubernetesVersion.V1_28,
            vpc=self.vpc,
            vpc_subnets=[ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS)],
            role=cluster_role,
            endpoint_access=eks.EndpointAccess.PUBLIC_AND_PRIVATE,
            default_capacity=0,  # We'll create managed node groups separately
            cluster_logging=[
                eks.ClusterLoggingTypes.API,
                eks.ClusterLoggingTypes.AUDIT,
                eks.ClusterLoggingTypes.AUTHENTICATOR,
                eks.ClusterLoggingTypes.CONTROLLER_MANAGER,
                eks.ClusterLoggingTypes.SCHEDULER,
            ],
            output_cluster_name=True,
            output_config_command=True,
        )
        
        # Create managed node group
        cluster.add_nodegroup_capacity(
            "ManagedNodeGroup",
            nodegroup_name=f"{self.cluster_name}-nodes",
            instance_types=[ec2.InstanceType("t3.medium")],
            min_size=2,
            max_size=4,
            desired_size=2,
            disk_size=20,
            ami_type=eks.NodegroupAmiType.AL2_X86_64,
            capacity_type=eks.CapacityType.ON_DEMAND,
            node_role=node_role,
            subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            tags={
                "Name": f"{self.cluster_name}-node",
                "kubernetes.io/cluster/" + self.cluster_name: "owned",
            },
        )
        
        return cluster

    def _create_log_groups(self) -> Dict[str, logs.LogGroup]:
        """
        Create CloudWatch Log Groups for EKS cluster logging.
        
        Returns:
            Dict[str, logs.LogGroup]: Dictionary of created log groups
        """
        log_groups = {}
        
        # Container Insights log groups
        log_groups["application"] = logs.LogGroup(
            self,
            "ApplicationLogGroup",
            log_group_name=f"/aws/containerinsights/{self.cluster_name}/application",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=cdk.RemovalPolicy.DESTROY,
        )
        
        log_groups["dataplane"] = logs.LogGroup(
            self,
            "DataplaneLogGroup",
            log_group_name=f"/aws/containerinsights/{self.cluster_name}/dataplane",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=cdk.RemovalPolicy.DESTROY,
        )
        
        log_groups["host"] = logs.LogGroup(
            self,
            "HostLogGroup",
            log_group_name=f"/aws/containerinsights/{self.cluster_name}/host",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=cdk.RemovalPolicy.DESTROY,
        )
        
        log_groups["performance"] = logs.LogGroup(
            self,
            "PerformanceLogGroup",
            log_group_name=f"/aws/containerinsights/{self.cluster_name}/performance",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=cdk.RemovalPolicy.DESTROY,
        )
        
        return log_groups

    def _create_prometheus_workspace(self) -> aps.CfnWorkspace:
        """
        Create Amazon Managed Service for Prometheus workspace.
        
        Returns:
            aps.CfnWorkspace: The created Prometheus workspace
        """
        workspace = aps.CfnWorkspace(
            self,
            "PrometheusWorkspace",
            alias=f"{self.cluster_name}-prometheus",
            tags=[
                cdk.CfnTag(key="Name", value=f"{self.cluster_name}-prometheus"),
                cdk.CfnTag(key="Environment", value="observability"),
            ],
        )
        
        return workspace

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for EKS cluster monitoring.
        
        Returns:
            cloudwatch.Dashboard: The created dashboard
        """
        dashboard = cloudwatch.Dashboard(
            self,
            "EKSObservabilityDashboard",
            dashboard_name=f"{self.cluster_name}-observability",
            period_override=cloudwatch.PeriodOverride.INHERIT,
        )
        
        # Create widgets for cluster metrics
        cluster_widget = cloudwatch.GraphWidget(
            title="EKS Cluster Status",
            width=12,
            height=6,
            left=[
                cloudwatch.Metric(
                    namespace="ContainerInsights",
                    metric_name="cluster_node_count",
                    dimensions_map={"ClusterName": self.cluster_name},
                    period=Duration.minutes(5),
                    statistic="Average",
                    label="Node Count",
                ),
                cloudwatch.Metric(
                    namespace="ContainerInsights",
                    metric_name="cluster_node_running_count",
                    dimensions_map={"ClusterName": self.cluster_name},
                    period=Duration.minutes(5),
                    statistic="Average",
                    label="Running Nodes",
                ),
            ],
        )
        
        pod_widget = cloudwatch.GraphWidget(
            title="EKS Pod Status",
            width=12,
            height=6,
            left=[
                cloudwatch.Metric(
                    namespace="ContainerInsights",
                    metric_name="cluster_running_count",
                    dimensions_map={"ClusterName": self.cluster_name},
                    period=Duration.minutes(5),
                    statistic="Average",
                    label="Running Pods",
                ),
                cloudwatch.Metric(
                    namespace="ContainerInsights",
                    metric_name="cluster_pending_count",
                    dimensions_map={"ClusterName": self.cluster_name},
                    period=Duration.minutes(5),
                    statistic="Average",
                    label="Pending Pods",
                ),
            ],
        )
        
        resource_widget = cloudwatch.GraphWidget(
            title="Node Resource Utilization",
            width=12,
            height=6,
            left=[
                cloudwatch.Metric(
                    namespace="ContainerInsights",
                    metric_name="node_cpu_utilization",
                    dimensions_map={"ClusterName": self.cluster_name},
                    period=Duration.minutes(5),
                    statistic="Average",
                    label="CPU Utilization %",
                ),
                cloudwatch.Metric(
                    namespace="ContainerInsights",
                    metric_name="node_memory_utilization",
                    dimensions_map={"ClusterName": self.cluster_name},
                    period=Duration.minutes(5),
                    statistic="Average",
                    label="Memory Utilization %",
                ),
            ],
        )
        
        # Add widgets to dashboard
        dashboard.add_widgets(cluster_widget, pod_widget)
        dashboard.add_widgets(resource_widget)
        
        return dashboard

    def _create_cloudwatch_alarms(self) -> Dict[str, cloudwatch.Alarm]:
        """
        Create CloudWatch alarms for EKS cluster monitoring.
        
        Returns:
            Dict[str, cloudwatch.Alarm]: Dictionary of created alarms
        """
        alarms = {}
        
        # High CPU utilization alarm
        alarms["high_cpu"] = cloudwatch.Alarm(
            self,
            "HighCPUAlarm",
            alarm_name=f"{self.cluster_name}-high-cpu-utilization",
            alarm_description="High CPU utilization in EKS cluster",
            metric=cloudwatch.Metric(
                namespace="ContainerInsights",
                metric_name="node_cpu_utilization",
                dimensions_map={"ClusterName": self.cluster_name},
                period=Duration.minutes(5),
                statistic="Average",
            ),
            threshold=80,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            datapoints_to_alarm=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        # High memory utilization alarm
        alarms["high_memory"] = cloudwatch.Alarm(
            self,
            "HighMemoryAlarm",
            alarm_name=f"{self.cluster_name}-high-memory-utilization",
            alarm_description="High memory utilization in EKS cluster",
            metric=cloudwatch.Metric(
                namespace="ContainerInsights",
                metric_name="node_memory_utilization",
                dimensions_map={"ClusterName": self.cluster_name},
                period=Duration.minutes(5),
                statistic="Average",
            ),
            threshold=80,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            datapoints_to_alarm=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        # High failed pod count alarm
        alarms["high_failed_pods"] = cloudwatch.Alarm(
            self,
            "HighFailedPodsAlarm",
            alarm_name=f"{self.cluster_name}-high-failed-pods",
            alarm_description="High number of failed pods in EKS cluster",
            metric=cloudwatch.Metric(
                namespace="ContainerInsights",
                metric_name="cluster_failed_count",
                dimensions_map={"ClusterName": self.cluster_name},
                period=Duration.minutes(5),
                statistic="Average",
            ),
            threshold=5,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=1,
            datapoints_to_alarm=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        return alarms

    def _deploy_monitoring_components(self) -> None:
        """
        Deploy monitoring components to the EKS cluster using Kubernetes manifests.
        """
        # Create CloudWatch namespace
        cloudwatch_namespace = self.cluster.add_manifest(
            "CloudWatchNamespace",
            {
                "apiVersion": "v1",
                "kind": "Namespace",
                "metadata": {"name": "amazon-cloudwatch"},
            },
        )
        
        # Create service account for CloudWatch agent with IRSA
        cloudwatch_service_account = self.cluster.add_service_account(
            "CloudWatchServiceAccount",
            name="cloudwatch-agent",
            namespace="amazon-cloudwatch",
        )
        
        # Attach CloudWatch agent policy to service account
        cloudwatch_service_account.role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchAgentServerPolicy")
        )
        
        # Deploy Fluent Bit configuration
        fluent_bit_config = self.cluster.add_manifest(
            "FluentBitConfig",
            {
                "apiVersion": "v1",
                "kind": "ConfigMap",
                "metadata": {
                    "name": "fluent-bit-config",
                    "namespace": "amazon-cloudwatch",
                },
                "data": {
                    "fluent-bit.conf": self._get_fluent_bit_config(),
                    "parsers.conf": self._get_fluent_bit_parsers(),
                },
            },
        )
        
        # Deploy Fluent Bit DaemonSet
        fluent_bit_daemonset = self.cluster.add_manifest(
            "FluentBitDaemonSet",
            {
                "apiVersion": "apps/v1",
                "kind": "DaemonSet",
                "metadata": {
                    "name": "fluent-bit",
                    "namespace": "amazon-cloudwatch",
                },
                "spec": {
                    "selector": {"matchLabels": {"name": "fluent-bit"}},
                    "template": {
                        "metadata": {"labels": {"name": "fluent-bit"}},
                        "spec": {
                            "serviceAccountName": "cloudwatch-agent",
                            "containers": [
                                {
                                    "name": "fluent-bit",
                                    "image": "amazon/aws-for-fluent-bit:stable",
                                    "imagePullPolicy": "Always",
                                    "env": [
                                        {"name": "AWS_REGION", "value": self.region},
                                        {"name": "CLUSTER_NAME", "value": self.cluster_name},
                                        {"name": "HTTP_SERVER", "value": "On"},
                                        {"name": "HTTP_PORT", "value": "2020"},
                                        {"name": "READ_FROM_HEAD", "value": "Off"},
                                        {"name": "READ_FROM_TAIL", "value": "On"},
                                        {
                                            "name": "HOST_NAME",
                                            "valueFrom": {"fieldRef": {"fieldPath": "spec.nodeName"}},
                                        },
                                        {
                                            "name": "HOSTNAME",
                                            "valueFrom": {"fieldRef": {"fieldPath": "metadata.name"}},
                                        },
                                    ],
                                    "resources": {
                                        "limits": {"memory": "200Mi"},
                                        "requests": {"cpu": "500m", "memory": "100Mi"},
                                    },
                                    "volumeMounts": [
                                        {"name": "fluentbitstate", "mountPath": "/var/fluent-bit/state"},
                                        {"name": "varlog", "mountPath": "/var/log", "readOnly": True},
                                        {
                                            "name": "varlibdockercontainers",
                                            "mountPath": "/var/lib/docker/containers",
                                            "readOnly": True,
                                        },
                                        {"name": "fluent-bit-config", "mountPath": "/fluent-bit/etc/"},
                                        {"name": "runlogjournal", "mountPath": "/run/log/journal", "readOnly": True},
                                        {"name": "dmesg", "mountPath": "/var/log/dmesg", "readOnly": True},
                                    ],
                                }
                            ],
                            "terminationGracePeriodSeconds": 10,
                            "volumes": [
                                {"name": "fluentbitstate", "hostPath": {"path": "/var/fluent-bit/state"}},
                                {"name": "varlog", "hostPath": {"path": "/var/log"}},
                                {"name": "varlibdockercontainers", "hostPath": {"path": "/var/lib/docker/containers"}},
                                {"name": "fluent-bit-config", "configMap": {"name": "fluent-bit-config"}},
                                {"name": "runlogjournal", "hostPath": {"path": "/run/log/journal"}},
                                {"name": "dmesg", "hostPath": {"path": "/var/log/dmesg"}},
                            ],
                            "tolerations": [
                                {
                                    "key": "node-role.kubernetes.io/master",
                                    "operator": "Exists",
                                    "effect": "NoSchedule",
                                },
                                {"operator": "Exists", "effect": "NoExecute"},
                                {"operator": "Exists", "effect": "NoSchedule"},
                            ],
                        },
                    },
                },
            },
        )
        
        # Set dependencies
        fluent_bit_config.node.add_dependency(cloudwatch_namespace)
        fluent_bit_daemonset.node.add_dependency(fluent_bit_config)
        fluent_bit_daemonset.node.add_dependency(cloudwatch_service_account)

    def _deploy_sample_application(self) -> None:
        """
        Deploy sample application with Prometheus metrics.
        """
        sample_app = self.cluster.add_manifest(
            "SampleApp",
            {
                "apiVersion": "apps/v1",
                "kind": "Deployment",
                "metadata": {"name": "sample-app", "namespace": "default"},
                "spec": {
                    "replicas": 2,
                    "selector": {"matchLabels": {"app": "sample-app"}},
                    "template": {
                        "metadata": {
                            "labels": {"app": "sample-app"},
                            "annotations": {
                                "prometheus.io/scrape": "true",
                                "prometheus.io/port": "8080",
                                "prometheus.io/path": "/metrics",
                            },
                        },
                        "spec": {
                            "containers": [
                                {
                                    "name": "sample-app",
                                    "image": "nginx:1.21",
                                    "ports": [
                                        {"containerPort": 80},
                                        {"containerPort": 8080},
                                    ],
                                    "resources": {
                                        "requests": {"cpu": "100m", "memory": "128Mi"},
                                        "limits": {"cpu": "200m", "memory": "256Mi"},
                                    },
                                    "env": [{"name": "PROMETHEUS_ENABLED", "value": "true"}],
                                }
                            ]
                        },
                    },
                },
            },
        )
        
        sample_service = self.cluster.add_manifest(
            "SampleService",
            {
                "apiVersion": "v1",
                "kind": "Service",
                "metadata": {
                    "name": "sample-app-service",
                    "namespace": "default",
                    "annotations": {
                        "prometheus.io/scrape": "true",
                        "prometheus.io/port": "8080",
                    },
                },
                "spec": {
                    "selector": {"app": "sample-app"},
                    "ports": [
                        {"name": "http", "port": 80, "targetPort": 80},
                        {"name": "metrics", "port": 8080, "targetPort": 8080},
                    ],
                    "type": "ClusterIP",
                },
            },
        )
        
        sample_service.node.add_dependency(sample_app)

    def _get_fluent_bit_config(self) -> str:
        """
        Get Fluent Bit configuration for log collection.
        
        Returns:
            str: Fluent Bit configuration
        """
        return f"""[SERVICE]
    Flush                     5
    Grace                     30
    Log_Level                 info
    Daemon                    off
    Parsers_File              parsers.conf
    HTTP_Server               On
    HTTP_Listen               0.0.0.0
    HTTP_Port                 2020
    storage.path              /var/fluent-bit/state/flb-storage/
    storage.sync              normal
    storage.checksum          off
    storage.backlog.mem_limit 5M

[INPUT]
    Name                tail
    Tag                 application.*
    Exclude_Path        /var/log/containers/cloudwatch-agent*, /var/log/containers/fluent-bit*, /var/log/containers/aws-node*, /var/log/containers/kube-proxy*
    Path                /var/log/containers/*.log
    multiline.parser    docker, cri
    DB                  /var/fluent-bit/state/flb_container.db
    Mem_Buf_Limit       50MB
    Skip_Long_Lines     On
    Refresh_Interval    10
    Rotate_Wait         30
    storage.type        filesystem
    Read_from_Head      Off

[INPUT]
    Name                tail
    Tag                 dataplane.systemd.*
    Path                /var/log/journal
    multiline.parser    docker, cri
    DB                  /var/fluent-bit/state/flb_journal.db
    Mem_Buf_Limit       25MB
    Skip_Long_Lines     On
    Refresh_Interval    10
    Read_from_Head      Off

[FILTER]
    Name                kubernetes
    Match               application.*
    Kube_URL            https://kubernetes.default.svc:443
    Kube_Tag_Prefix     application.var.log.containers.
    Merge_Log           On
    Merge_Log_Key       log_processed
    K8S-Logging.Parser  On
    K8S-Logging.Exclude Off
    Labels              Off
    Annotations         Off
    Use_Kubelet         On
    Kubelet_Port        10250
    Buffer_Size         0

[OUTPUT]
    Name                cloudwatch_logs
    Match               application.*
    region              {self.region}
    log_group_name      /aws/containerinsights/{self.cluster_name}/application
    log_stream_prefix   ${{kubernetes_namespace_name}}-
    auto_create_group   On
    extra_user_agent    container-insights

[OUTPUT]
    Name                cloudwatch_logs
    Match               dataplane.systemd.*
    region              {self.region}
    log_group_name      /aws/containerinsights/{self.cluster_name}/dataplane
    log_stream_prefix   ${{hostname}}-
    auto_create_group   On
    extra_user_agent    container-insights"""

    def _get_fluent_bit_parsers(self) -> str:
        """
        Get Fluent Bit parsers configuration.
        
        Returns:
            str: Fluent Bit parsers configuration
        """
        return """[PARSER]
    Name                docker
    Format              json
    Time_Key            time
    Time_Format         %Y-%m-%dT%H:%M:%S.%L
    Time_Keep           On

[PARSER]
    Name                cri
    Format              regex
    Regex               ^(?<time>[^ ]+) (?<stream>stdout|stderr) (?<logtag>[^ ]*) (?<message>.*)$
    Time_Key            time
    Time_Format         %Y-%m-%dT%H:%M:%S.%L%z"""

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for easy access to resources.
        """
        CfnOutput(
            self,
            "ClusterName",
            value=self.cluster.cluster_name,
            description="EKS Cluster Name",
            export_name=f"{self.stack_name}-ClusterName",
        )
        
        CfnOutput(
            self,
            "ClusterEndpoint",
            value=self.cluster.cluster_endpoint,
            description="EKS Cluster Endpoint",
            export_name=f"{self.stack_name}-ClusterEndpoint",
        )
        
        CfnOutput(
            self,
            "ClusterArn",
            value=self.cluster.cluster_arn,
            description="EKS Cluster ARN",
            export_name=f"{self.stack_name}-ClusterArn",
        )
        
        CfnOutput(
            self,
            "PrometheusWorkspaceId",
            value=self.prometheus_workspace.attr_workspace_id,
            description="Amazon Managed Prometheus Workspace ID",
            export_name=f"{self.stack_name}-PrometheusWorkspaceId",
        )
        
        CfnOutput(
            self,
            "PrometheusWorkspaceArn",
            value=self.prometheus_workspace.attr_arn,
            description="Amazon Managed Prometheus Workspace ARN",
            export_name=f"{self.stack_name}-PrometheusWorkspaceArn",
        )
        
        CfnOutput(
            self,
            "DashboardName",
            value=self.dashboard.dashboard_name,
            description="CloudWatch Dashboard Name",
            export_name=f"{self.stack_name}-DashboardName",
        )
        
        CfnOutput(
            self,
            "KubectlCommand",
            value=f"aws eks update-kubeconfig --region {self.region} --name {self.cluster_name}",
            description="Command to configure kubectl",
            export_name=f"{self.stack_name}-KubectlCommand",
        )

    def _apply_tags(self) -> None:
        """
        Apply tags to all resources in the stack.
        """
        Tags.of(self).add("Project", "EKS-Observability")
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("ManagedBy", "AWS-CDK")
        Tags.of(self).add("Recipe", "eks-cluster-logging-monitoring-cloudwatch-prometheus")


class EKSObservabilityApp(cdk.App):
    """
    CDK Application for EKS Observability Stack.
    """

    def __init__(self, **kwargs) -> None:
        """
        Initialize the CDK application.
        """
        super().__init__(**kwargs)

        # Get environment configuration
        env = Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
        )

        # Create the EKS Observability Stack
        EKSObservabilityStack(
            self,
            "EKSObservabilityStack",
            env=env,
            description="EKS cluster logging and monitoring with CloudWatch and Prometheus",
            stack_name="eks-observability-stack",
        )


# Create and run the application
app = EKSObservabilityApp()
app.synth()