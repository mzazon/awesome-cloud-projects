#!/usr/bin/env python3
"""
CDK Python application for comprehensive container observability and performance monitoring.

This application creates a complete observability stack for containerized applications
including EKS cluster, ECS cluster, CloudWatch Container Insights, X-Ray tracing,
Prometheus monitoring, and automated performance optimization.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    RemovalPolicy,
    Duration,
    aws_ec2 as ec2,
    aws_eks as eks,
    aws_ecs as ecs,
    aws_iam as iam,
    aws_logs as logs,
    aws_cloudwatch as cw,
    aws_sns as sns,
    aws_lambda as lambda_,
    aws_events as events,
    aws_events_targets as targets,
    aws_opensearch as opensearch,
    aws_s3 as s3,
    aws_kinesisfirehose as firehose,
    aws_ssm as ssm,
)
from constructs import Construct
import json


class ContainerObservabilityStack(Stack):
    """
    CDK Stack for comprehensive container observability and performance monitoring.
    
    This stack creates:
    - EKS cluster with Container Insights
    - ECS cluster with Container Insights
    - CloudWatch alarms and anomaly detection
    - OpenSearch domain for log analytics
    - Performance optimization Lambda function
    - SNS topic for alerts
    - IAM roles and policies
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.try_get_context("unique_suffix") or "obs"
        
        # Create VPC for the infrastructure
        vpc = ec2.Vpc(
            self,
            "ObservabilityVPC",
            max_azs=3,
            nat_gateways=1,
            enable_dns_hostnames=True,
            enable_dns_support=True,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                ),
            ],
        )

        # Create S3 bucket for backup logs
        log_backup_bucket = s3.Bucket(
            self,
            "LogBackupBucket",
            bucket_name=f"container-logs-backup-{unique_suffix}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            versioned=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="LogRetention",
                    enabled=True,
                    expiration=Duration.days(30),
                    noncurrent_version_expiration=Duration.days(7),
                )
            ],
        )

        # Create SNS topic for alerts
        alert_topic = sns.Topic(
            self,
            "ContainerObservabilityAlerts",
            topic_name="container-observability-alerts",
            display_name="Container Observability Alerts",
        )

        # Create CloudWatch log groups
        eks_log_group = logs.LogGroup(
            self,
            "EKSApplicationLogs",
            log_group_name=f"/aws/eks/observability-eks-{unique_suffix}/application",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

        ecs_log_group = logs.LogGroup(
            self,
            "ECSApplicationLogs",
            log_group_name=f"/aws/ecs/observability-ecs-{unique_suffix}/application",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

        container_insights_log_group = logs.LogGroup(
            self,
            "ContainerInsightsLogs",
            log_group_name=f"/aws/containerinsights/observability-eks-{unique_suffix}/application",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create OpenSearch domain for log analytics
        opensearch_domain = opensearch.Domain(
            self,
            "ContainerLogsOpenSearch",
            domain_name=f"container-logs-{unique_suffix}",
            version=opensearch.EngineVersion.OPENSEARCH_2_3,
            capacity=opensearch.CapacityConfig(
                master_nodes=0,
                data_nodes=3,
                data_node_instance_type="t3.small.search",
            ),
            ebs=opensearch.EbsOptions(
                enabled=True,
                volume_type=ec2.EbsDeviceVolumeType.GP3,
                volume_size=20,
            ),
            zone_awareness=opensearch.ZoneAwarenessConfig(
                enabled=True,
                availability_zone_count=2,
            ),
            encryption_at_rest=opensearch.EncryptionAtRestOptions(enabled=True),
            node_to_node_encryption=True,
            enforce_https=True,
            removal_policy=RemovalPolicy.DESTROY,
            access_policies=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[iam.AnyPrincipal()],
                    actions=["es:*"],
                    resources=[f"arn:aws:es:{self.region}:{self.account}:domain/container-logs-{unique_suffix}/*"],
                )
            ],
        )

        # Create EKS cluster with Container Insights
        eks_cluster = eks.Cluster(
            self,
            "ObservabilityEKSCluster",
            cluster_name=f"observability-eks-{unique_suffix}",
            version=eks.KubernetesVersion.V1_28,
            vpc=vpc,
            default_capacity_type=eks.DefaultCapacityType.NODEGROUP,
            default_capacity=3,
            default_capacity_instance=ec2.InstanceType.of(
                ec2.InstanceClass.T3, ec2.InstanceSize.LARGE
            ),
            cluster_logging=[
                eks.ClusterLoggingTypes.API,
                eks.ClusterLoggingTypes.AUDIT,
                eks.ClusterLoggingTypes.AUTHENTICATOR,
                eks.ClusterLoggingTypes.CONTROLLER_MANAGER,
                eks.ClusterLoggingTypes.SCHEDULER,
            ],
            endpoint_access=eks.EndpointAccess.PUBLIC_AND_PRIVATE,
        )

        # Add Container Insights to EKS cluster
        eks_cluster.add_helm_chart(
            "ContainerInsights",
            chart="aws-cloudwatch-metrics",
            repository="https://aws.github.io/eks-charts",
            namespace="amazon-cloudwatch",
            create_namespace=True,
            values={
                "clusterName": eks_cluster.cluster_name,
                "region": self.region,
                "fluentBit": {
                    "enabled": True,
                    "config": {
                        "outputs": {
                            "cloudWatchLogs": {
                                "enabled": True,
                                "region": self.region,
                                "logGroupName": eks_log_group.log_group_name,
                            }
                        }
                    }
                }
            },
        )

        # Create ECS cluster with Container Insights
        ecs_cluster = ecs.Cluster(
            self,
            "ObservabilityECSCluster",
            cluster_name=f"observability-ecs-{unique_suffix}",
            vpc=vpc,
            container_insights=True,
            capacity_providers=[
                ecs.CapacityProvider.FARGATE,
                ecs.CapacityProvider.FARGATE_SPOT,
            ],
            enable_fargate_capacity_providers=True,
        )

        # Create IAM role for ECS tasks
        ecs_task_role = iam.Role(
            self,
            "ECSTaskRole",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonECSTaskExecutionRolePolicy"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "CloudWatchLogsFullAccess"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AWSXRayDaemonWriteAccess"
                ),
            ],
        )

        # Create ECS task definition with observability
        ecs_task_definition = ecs.FargateTaskDefinition(
            self,
            "ObservabilityDemoTask",
            family="observability-demo-task",
            cpu=512,
            memory_limit_mib=1024,
            task_role=ecs_task_role,
            execution_role=ecs_task_role,
        )

        # Add application container
        app_container = ecs_task_definition.add_container(
            "app",
            image=ecs.ContainerImage.from_registry("nginx:latest"),
            essential=True,
            port_mappings=[
                ecs.PortMapping(container_port=80, protocol=ecs.Protocol.TCP)
            ],
            logging=ecs.LogDriver.aws_logs(
                stream_prefix="app",
                log_group=ecs_log_group,
            ),
            environment={
                "AWS_XRAY_TRACING_NAME": "ecs-observability-demo",
            },
        )

        # Add ADOT collector container
        adot_container = ecs_task_definition.add_container(
            "aws-otel-collector",
            image=ecs.ContainerImage.from_registry(
                "public.ecr.aws/aws-observability/aws-otel-collector:latest"
            ),
            essential=False,
            logging=ecs.LogDriver.aws_logs(
                stream_prefix="otel-collector",
                log_group=ecs_log_group,
            ),
            environment={
                "AWS_REGION": self.region,
            },
        )

        # Create ECS service
        ecs_service = ecs.FargateService(
            self,
            "ObservabilityDemoService",
            cluster=ecs_cluster,
            task_definition=ecs_task_definition,
            service_name="observability-demo-service",
            desired_count=2,
            assign_public_ip=True,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC),
        )

        # Create CloudWatch alarms for EKS
        eks_cpu_alarm = cw.Alarm(
            self,
            "EKSHighCPUAlarm",
            alarm_name="EKS-High-CPU-Utilization",
            alarm_description="High CPU utilization in EKS cluster",
            metric=cw.Metric(
                namespace="AWS/ContainerInsights",
                metric_name="pod_cpu_utilization",
                dimensions_map={"ClusterName": eks_cluster.cluster_name},
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=80,
            evaluation_periods=2,
            comparison_operator=cw.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )

        eks_memory_alarm = cw.Alarm(
            self,
            "EKSHighMemoryAlarm",
            alarm_name="EKS-High-Memory-Utilization",
            alarm_description="High memory utilization in EKS cluster",
            metric=cw.Metric(
                namespace="AWS/ContainerInsights",
                metric_name="pod_memory_utilization",
                dimensions_map={"ClusterName": eks_cluster.cluster_name},
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=80,
            evaluation_periods=2,
            comparison_operator=cw.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )

        # Create CloudWatch alarms for ECS
        ecs_unhealthy_tasks_alarm = cw.Alarm(
            self,
            "ECSUnhealthyTasksAlarm",
            alarm_name="ECS-Service-Unhealthy-Tasks",
            alarm_description="Unhealthy tasks in ECS service",
            metric=cw.Metric(
                namespace="AWS/ECS",
                metric_name="RunningTaskCount",
                dimensions_map={
                    "ServiceName": ecs_service.service_name,
                    "ClusterName": ecs_cluster.cluster_name,
                },
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=1,
            evaluation_periods=2,
            comparison_operator=cw.ComparisonOperator.LESS_THAN_THRESHOLD,
        )

        # Add SNS actions to alarms
        for alarm in [eks_cpu_alarm, eks_memory_alarm, ecs_unhealthy_tasks_alarm]:
            alarm.add_alarm_action(
                cw.SnsAction(alert_topic)
            )
            alarm.add_ok_action(
                cw.SnsAction(alert_topic)
            )

        # Create performance optimization Lambda function
        performance_optimizer_role = iam.Role(
            self,
            "PerformanceOptimizerRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "CloudWatchReadOnlyAccess"
                ),
            ],
        )

        performance_optimizer_lambda = lambda_.Function(
            self,
            "PerformanceOptimizerFunction",
            function_name="container-performance-optimizer",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=performance_optimizer_role,
            timeout=Duration.seconds(60),
            environment={
                "EKS_CLUSTER_NAME": eks_cluster.cluster_name,
                "ECS_CLUSTER_NAME": ecs_cluster.cluster_name,
                "SNS_TOPIC_ARN": alert_topic.topic_arn,
            },
            code=lambda_.Code.from_inline("""
import json
import boto3
from datetime import datetime, timedelta
import os

def lambda_handler(event, context):
    cloudwatch = boto3.client('cloudwatch')
    sns = boto3.client('sns')
    
    eks_cluster_name = os.environ['EKS_CLUSTER_NAME']
    ecs_cluster_name = os.environ['ECS_CLUSTER_NAME']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    
    # Get performance metrics for the last hour
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(hours=1)
    
    recommendations = []
    
    try:
        # Get CPU utilization metrics for EKS
        cpu_metrics = cloudwatch.get_metric_statistics(
            Namespace='AWS/ContainerInsights',
            MetricName='pod_cpu_utilization',
            Dimensions=[
                {'Name': 'ClusterName', 'Value': eks_cluster_name}
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average', 'Maximum']
        )
        
        # Analyze CPU utilization
        if cpu_metrics['Datapoints']:
            avg_cpu = sum(point['Average'] for point in cpu_metrics['Datapoints']) / len(cpu_metrics['Datapoints'])
            max_cpu = max(point['Maximum'] for point in cpu_metrics['Datapoints'])
            
            if avg_cpu < 20:
                recommendations.append({
                    'type': 'DOWNSIZE_CPU',
                    'cluster': eks_cluster_name,
                    'message': f'Average CPU utilization is {avg_cpu:.1f}%. Consider reducing CPU requests.',
                    'severity': 'MEDIUM'
                })
            elif max_cpu > 90:
                recommendations.append({
                    'type': 'UPSIZE_CPU',
                    'cluster': eks_cluster_name,
                    'message': f'Maximum CPU utilization reached {max_cpu:.1f}%. Consider increasing CPU limits.',
                    'severity': 'HIGH'
                })
        
        # Get memory utilization metrics for EKS
        memory_metrics = cloudwatch.get_metric_statistics(
            Namespace='AWS/ContainerInsights',
            MetricName='pod_memory_utilization',
            Dimensions=[
                {'Name': 'ClusterName', 'Value': eks_cluster_name}
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average', 'Maximum']
        )
        
        # Analyze memory utilization
        if memory_metrics['Datapoints']:
            avg_memory = sum(point['Average'] for point in memory_metrics['Datapoints']) / len(memory_metrics['Datapoints'])
            max_memory = max(point['Maximum'] for point in memory_metrics['Datapoints'])
            
            if avg_memory < 30:
                recommendations.append({
                    'type': 'DOWNSIZE_MEMORY',
                    'cluster': eks_cluster_name,
                    'message': f'Average memory utilization is {avg_memory:.1f}%. Consider reducing memory requests.',
                    'severity': 'MEDIUM'
                })
            elif max_memory > 85:
                recommendations.append({
                    'type': 'UPSIZE_MEMORY',
                    'cluster': eks_cluster_name,
                    'message': f'Maximum memory utilization reached {max_memory:.1f}%. Consider increasing memory limits.',
                    'severity': 'HIGH'
                })
        
        # Send recommendations via SNS if any found
        if recommendations:
            message = {
                'timestamp': datetime.utcnow().isoformat(),
                'cluster_analysis': {
                    'eks_cluster': eks_cluster_name,
                    'ecs_cluster': ecs_cluster_name
                },
                'recommendations': recommendations
            }
            
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject='Container Performance Optimization Recommendations',
                Message=json.dumps(message, indent=2)
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'recommendations': recommendations,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        print(f"Error in performance analysis: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }
"""),
        )

        # Grant SNS publish permissions to Lambda
        alert_topic.grant_publish(performance_optimizer_lambda)

        # Create EventBridge rule for performance optimization
        performance_analysis_rule = events.Rule(
            self,
            "PerformanceAnalysisRule",
            rule_name="container-performance-analysis",
            description="Trigger container performance optimization analysis",
            schedule=events.Schedule.rate(Duration.hours(1)),
            targets=[
                targets.LambdaFunction(performance_optimizer_lambda)
            ],
        )

        # Create CloudWatch dashboard
        dashboard = cw.Dashboard(
            self,
            "ContainerObservabilityDashboard",
            dashboard_name=f"Container-Observability-{unique_suffix}",
            widgets=[
                [
                    cw.GraphWidget(
                        title="EKS Pod Resource Utilization",
                        left=[
                            cw.Metric(
                                namespace="AWS/ContainerInsights",
                                metric_name="pod_cpu_utilization",
                                dimensions_map={"ClusterName": eks_cluster.cluster_name},
                                statistic="Average",
                                period=Duration.minutes(5),
                            ),
                            cw.Metric(
                                namespace="AWS/ContainerInsights",
                                metric_name="pod_memory_utilization",
                                dimensions_map={"ClusterName": eks_cluster.cluster_name},
                                statistic="Average",
                                period=Duration.minutes(5),
                            ),
                        ],
                        width=12,
                        height=6,
                    ),
                    cw.GraphWidget(
                        title="ECS Service Resource Utilization",
                        left=[
                            cw.Metric(
                                namespace="AWS/ECS",
                                metric_name="CPUUtilization",
                                dimensions_map={
                                    "ServiceName": ecs_service.service_name,
                                    "ClusterName": ecs_cluster.cluster_name,
                                },
                                statistic="Average",
                                period=Duration.minutes(5),
                            ),
                            cw.Metric(
                                namespace="AWS/ECS",
                                metric_name="MemoryUtilization",
                                dimensions_map={
                                    "ServiceName": ecs_service.service_name,
                                    "ClusterName": ecs_cluster.cluster_name,
                                },
                                statistic="Average",
                                period=Duration.minutes(5),
                            ),
                        ],
                        width=12,
                        height=6,
                    ),
                ],
                [
                    cw.GraphWidget(
                        title="EKS Network I/O",
                        left=[
                            cw.Metric(
                                namespace="AWS/ContainerInsights",
                                metric_name="pod_network_rx_bytes",
                                dimensions_map={"ClusterName": eks_cluster.cluster_name},
                                statistic="Average",
                                period=Duration.minutes(5),
                            ),
                            cw.Metric(
                                namespace="AWS/ContainerInsights",
                                metric_name="pod_network_tx_bytes",
                                dimensions_map={"ClusterName": eks_cluster.cluster_name},
                                statistic="Average",
                                period=Duration.minutes(5),
                            ),
                        ],
                        width=12,
                        height=6,
                    ),
                    cw.GraphWidget(
                        title="ECS Task Counts",
                        left=[
                            cw.Metric(
                                namespace="AWS/ECS",
                                metric_name="RunningTaskCount",
                                dimensions_map={
                                    "ServiceName": ecs_service.service_name,
                                    "ClusterName": ecs_cluster.cluster_name,
                                },
                                statistic="Average",
                                period=Duration.minutes(5),
                            ),
                            cw.Metric(
                                namespace="AWS/ECS",
                                metric_name="PendingTaskCount",
                                dimensions_map={
                                    "ServiceName": ecs_service.service_name,
                                    "ClusterName": ecs_cluster.cluster_name,
                                },
                                statistic="Average",
                                period=Duration.minutes(5),
                            ),
                        ],
                        width=12,
                        height=6,
                    ),
                ],
            ],
        )

        # Store cluster names in SSM for easy access
        ssm.StringParameter(
            self,
            "EKSClusterNameParameter",
            parameter_name="/observability/eks-cluster-name",
            string_value=eks_cluster.cluster_name,
            description="EKS cluster name for observability demo",
        )

        ssm.StringParameter(
            self,
            "ECSClusterNameParameter",
            parameter_name="/observability/ecs-cluster-name",
            string_value=ecs_cluster.cluster_name,
            description="ECS cluster name for observability demo",
        )

        # Outputs
        CfnOutput(
            self,
            "EKSClusterName",
            value=eks_cluster.cluster_name,
            description="Name of the EKS cluster",
        )

        CfnOutput(
            self,
            "ECSClusterName",
            value=ecs_cluster.cluster_name,
            description="Name of the ECS cluster",
        )

        CfnOutput(
            self,
            "OpenSearchDomainEndpoint",
            value=f"https://{opensearch_domain.domain_endpoint}",
            description="OpenSearch domain endpoint for log analytics",
        )

        CfnOutput(
            self,
            "SNSTopicArn",
            value=alert_topic.topic_arn,
            description="SNS topic ARN for alerts",
        )

        CfnOutput(
            self,
            "DashboardURL",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={dashboard.dashboard_name}",
            description="CloudWatch dashboard URL",
        )

        CfnOutput(
            self,
            "LogBackupBucketName",
            value=log_backup_bucket.bucket_name,
            description="S3 bucket name for log backups",
        )


# CDK App
app = cdk.App()

# Get configuration from context
env = Environment(
    account=app.node.try_get_context("account") or app.account,
    region=app.node.try_get_context("region") or app.region,
)

# Create the stack
ContainerObservabilityStack(
    app,
    "ContainerObservabilityStack",
    env=env,
    description="Comprehensive container observability and performance monitoring stack",
)

app.synth()