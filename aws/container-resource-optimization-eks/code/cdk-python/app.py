#!/usr/bin/env python3
"""
AWS CDK Application for Container Resource Optimization and Right-Sizing with Amazon EKS

This CDK application deploys the infrastructure for implementing automated container
resource optimization using Kubernetes Vertical Pod Autoscaler (VPA) and AWS cost
monitoring tools on Amazon EKS.

Author: AWS Recipes Project
Version: 1.0
"""

import os
from typing import Optional
from aws_cdk import (
    App,
    Environment,
    Stack,
    StackProps,
    Tags,
    CfnOutput,
    Duration,
    RemovalPolicy,
)
from aws_cdk import aws_eks as eks
from aws_cdk import aws_ec2 as ec2
from aws_cdk import aws_iam as iam
from aws_cdk import aws_logs as logs
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_sns as sns
from aws_cdk import aws_lambda as lambda_
from aws_cdk import aws_events as events
from aws_cdk import aws_events_targets as targets
from constructs import Construct


class ContainerResourceOptimizationStack(Stack):
    """
    CDK Stack for Container Resource Optimization and Right-Sizing
    
    This stack creates:
    - Amazon EKS cluster with managed node groups
    - VPC with public and private subnets
    - CloudWatch Container Insights
    - Cost monitoring dashboard
    - SNS topic for cost alerts
    - Lambda function for automated cost optimization
    - IAM roles and policies for EKS and monitoring
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        cluster_name: Optional[str] = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters
        self.cluster_name = cluster_name or "cost-optimization-cluster"
        
        # Create VPC for EKS cluster
        self.vpc = self._create_vpc()
        
        # Create EKS cluster
        self.cluster = self._create_eks_cluster()
        
        # Enable Container Insights
        self._enable_container_insights()
        
        # Create cost monitoring resources
        self.sns_topic = self._create_sns_topic()
        self.dashboard = self._create_cost_dashboard()
        self.cost_alarm = self._create_cost_alarm()
        
        # Create Lambda function for automated optimization
        self.cost_optimizer_lambda = self._create_cost_optimizer_lambda()
        
        # Create EventBridge rule for scheduled optimization
        self._create_optimization_schedule()
        
        # Add tags for cost allocation
        self._add_cost_allocation_tags()
        
        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC with public and private subnets for EKS cluster."""
        vpc = ec2.Vpc(
            self,
            "EksVpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PUBLIC,
                    name="PublicSubnet",
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    name="PrivateSubnet",
                    cidr_mask=24,
                ),
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )
        
        # Add VPC Flow Logs for security monitoring
        log_group = logs.LogGroup(
            self,
            "VpcFlowLogGroup",
            log_group_name=f"/aws/vpc/flowlogs/{self.cluster_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        vpc.add_flow_log(
            "VpcFlowLog",
            destination=ec2.FlowLogDestination.to_cloud_watch_logs(log_group),
        )
        
        return vpc

    def _create_eks_cluster(self) -> eks.Cluster:
        """Create EKS cluster with managed node groups."""
        # Create EKS cluster role
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
                iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchAgentServerPolicy"),
            ],
        )
        
        # Create EKS cluster
        cluster = eks.Cluster(
            self,
            "EksCluster",
            cluster_name=self.cluster_name,
            version=eks.KubernetesVersion.V1_28,
            vpc=self.vpc,
            default_capacity=0,  # We'll add managed node groups separately
            endpoint_access=eks.EndpointAccess.PUBLIC_AND_PRIVATE,
            role=cluster_role,
            cluster_logging=[
                eks.ClusterLoggingTypes.API,
                eks.ClusterLoggingTypes.AUDIT,
                eks.ClusterLoggingTypes.AUTHENTICATOR,
                eks.ClusterLoggingTypes.CONTROLLER_MANAGER,
                eks.ClusterLoggingTypes.SCHEDULER,
            ],
        )
        
        # Add managed node group for cost optimization workloads
        cluster.add_nodegroup_capacity(
            "CostOptimizationNodeGroup",
            nodegroup_name="cost-optimization-nodes",
            instance_types=[
                ec2.InstanceType("m5.large"),
                ec2.InstanceType("m5.xlarge"),
            ],
            min_size=1,
            max_size=5,
            desired_size=2,
            node_role=node_group_role,
            ami_type=eks.NodegroupAmiType.AL2_X86_64,
            capacity_type=eks.CapacityType.ON_DEMAND,
            disk_size=50,
            subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            tags={
                "Purpose": "CostOptimization",
                "Environment": "Production",
            },
        )
        
        # Add Spot instances node group for cost-effective workloads
        cluster.add_nodegroup_capacity(
            "SpotNodeGroup",
            nodegroup_name="spot-optimization-nodes",
            instance_types=[
                ec2.InstanceType("m5.large"),
                ec2.InstanceType("m5a.large"),
                ec2.InstanceType("m4.large"),
            ],
            min_size=0,
            max_size=10,
            desired_size=1,
            node_role=node_group_role,
            ami_type=eks.NodegroupAmiType.AL2_X86_64,
            capacity_type=eks.CapacityType.SPOT,
            disk_size=50,
            subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            tags={
                "Purpose": "CostOptimizationSpot",
                "Environment": "Production",
            },
        )
        
        return cluster

    def _enable_container_insights(self) -> None:
        """Enable CloudWatch Container Insights for the EKS cluster."""
        # Create CloudWatch Log Group for Container Insights
        container_insights_log_group = logs.LogGroup(
            self,
            "ContainerInsightsLogGroup",
            log_group_name=f"/aws/containerinsights/{self.cluster_name}/application",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Create namespace for CloudWatch agent
        namespace_manifest = {
            "apiVersion": "v1",
            "kind": "Namespace",
            "metadata": {
                "name": "amazon-cloudwatch",
                "labels": {
                    "name": "amazon-cloudwatch",
                },
            },
        }
        
        self.cluster.add_manifest("CloudWatchNamespace", namespace_manifest)
        
        # Add CloudWatch agent service account
        cloudwatch_service_account = self.cluster.add_service_account(
            "CloudWatchServiceAccount",
            name="cloudwatch-agent",
            namespace="amazon-cloudwatch",
        )
        
        # Attach CloudWatch agent policy
        cloudwatch_service_account.role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchAgentServerPolicy")
        )

    def _create_sns_topic(self) -> sns.Topic:
        """Create SNS topic for cost optimization alerts."""
        topic = sns.Topic(
            self,
            "CostOptimizationTopic",
            topic_name=f"eks-cost-optimization-{self.cluster_name}",
            display_name="EKS Cost Optimization Alerts",
        )
        
        return topic

    def _create_cost_dashboard(self) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for cost monitoring."""
        dashboard = cloudwatch.Dashboard(
            self,
            "CostOptimizationDashboard",
            dashboard_name=f"EKS-Cost-Optimization-{self.cluster_name}",
        )
        
        # Add CPU utilization widget
        cpu_widget = cloudwatch.GraphWidget(
            title="Pod CPU Utilization vs Reserved Capacity",
            width=12,
            height=6,
            left=[
                cloudwatch.Metric(
                    namespace="ContainerInsights",
                    metric_name="pod_cpu_utilization",
                    dimensions_map={"ClusterName": self.cluster_name},
                    statistic="Average",
                    period=Duration.minutes(5),
                ),
                cloudwatch.Metric(
                    namespace="ContainerInsights",
                    metric_name="pod_cpu_reserved_capacity",
                    dimensions_map={"ClusterName": self.cluster_name},
                    statistic="Average",
                    period=Duration.minutes(5),
                ),
            ],
        )
        
        # Add memory utilization widget
        memory_widget = cloudwatch.GraphWidget(
            title="Pod Memory Utilization vs Reserved Capacity",
            width=12,
            height=6,
            left=[
                cloudwatch.Metric(
                    namespace="ContainerInsights",
                    metric_name="pod_memory_utilization",
                    dimensions_map={"ClusterName": self.cluster_name},
                    statistic="Average",
                    period=Duration.minutes(5),
                ),
                cloudwatch.Metric(
                    namespace="ContainerInsights",
                    metric_name="pod_memory_reserved_capacity",
                    dimensions_map={"ClusterName": self.cluster_name},
                    statistic="Average",
                    period=Duration.minutes(5),
                ),
            ],
        )
        
        # Add node utilization widget
        node_widget = cloudwatch.GraphWidget(
            title="Node Resource Utilization",
            width=12,
            height=6,
            left=[
                cloudwatch.Metric(
                    namespace="ContainerInsights",
                    metric_name="node_cpu_utilization",
                    dimensions_map={"ClusterName": self.cluster_name},
                    statistic="Average",
                    period=Duration.minutes(5),
                ),
                cloudwatch.Metric(
                    namespace="ContainerInsights",
                    metric_name="node_memory_utilization",
                    dimensions_map={"ClusterName": self.cluster_name},
                    statistic="Average",
                    period=Duration.minutes(5),
                ),
            ],
        )
        
        # Add cost efficiency widget
        efficiency_widget = cloudwatch.SingleValueWidget(
            title="Resource Efficiency Metrics",
            width=12,
            height=6,
            metrics=[
                cloudwatch.Metric(
                    namespace="ContainerInsights",
                    metric_name="pod_cpu_utilization",
                    dimensions_map={"ClusterName": self.cluster_name},
                    statistic="Average",
                    period=Duration.hours(1),
                ),
                cloudwatch.Metric(
                    namespace="ContainerInsights",
                    metric_name="pod_memory_utilization",
                    dimensions_map={"ClusterName": self.cluster_name},
                    statistic="Average",
                    period=Duration.hours(1),
                ),
            ],
        )
        
        # Add widgets to dashboard
        dashboard.add_widgets(cpu_widget, memory_widget)
        dashboard.add_widgets(node_widget, efficiency_widget)
        
        return dashboard

    def _create_cost_alarm(self) -> cloudwatch.Alarm:
        """Create CloudWatch alarm for high resource waste."""
        alarm = cloudwatch.Alarm(
            self,
            "HighResourceWasteAlarm",
            alarm_name=f"EKS-High-Resource-Waste-{self.cluster_name}",
            alarm_description="Alert when container resource utilization is low",
            metric=cloudwatch.Metric(
                namespace="ContainerInsights",
                metric_name="pod_cpu_utilization",
                dimensions_map={"ClusterName": self.cluster_name},
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=30,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        # Add SNS action to alarm
        alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.sns_topic)
        )
        
        return alarm

    def _create_cost_optimizer_lambda(self) -> lambda_.Function:
        """Create Lambda function for automated cost optimization."""
        # Create Lambda execution role
        lambda_role = iam.Role(
            self,
            "CostOptimizerLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
        )
        
        # Add CloudWatch permissions
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudwatch:GetMetricStatistics",
                    "cloudwatch:ListMetrics",
                    "eks:DescribeCluster",
                    "eks:ListClusters",
                    "sns:Publish",
                ],
                resources=["*"],
            )
        )
        
        # Create Lambda function
        cost_optimizer = lambda_.Function(
            self,
            "CostOptimizerFunction",
            function_name=f"eks-cost-optimizer-{self.cluster_name}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            role=lambda_role,
            timeout=Duration.minutes(5),
            memory_size=256,
            environment={
                "CLUSTER_NAME": self.cluster_name,
                "SNS_TOPIC_ARN": self.sns_topic.topic_arn,
            },
            code=lambda_.Code.from_inline(self._get_lambda_code()),
        )
        
        # Grant Lambda permissions to publish to SNS
        self.sns_topic.grant_publish(cost_optimizer)
        
        return cost_optimizer

    def _create_optimization_schedule(self) -> None:
        """Create EventBridge rule for scheduled cost optimization checks."""
        # Create EventBridge rule to run every hour
        rule = events.Rule(
            self,
            "CostOptimizationSchedule",
            rule_name=f"eks-cost-optimization-schedule-{self.cluster_name}",
            description="Scheduled cost optimization checks for EKS cluster",
            schedule=events.Schedule.rate(Duration.hours(1)),
        )
        
        # Add Lambda target to the rule
        rule.add_target(targets.LambdaFunction(self.cost_optimizer_lambda))

    def _get_lambda_code(self) -> str:
        """Return the Lambda function code for cost optimization."""
        return """
import boto3
import json
import os
from datetime import datetime, timedelta
from typing import Dict, Any

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    \"\"\"
    Lambda function to analyze EKS cluster resource utilization and send alerts
    for cost optimization opportunities.
    \"\"\"
    
    cluster_name = os.environ['CLUSTER_NAME']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    
    cloudwatch = boto3.client('cloudwatch')
    sns = boto3.client('sns')
    
    try:
        # Query CPU utilization metrics
        cpu_response = cloudwatch.get_metric_statistics(
            Namespace='ContainerInsights',
            MetricName='pod_cpu_utilization',
            Dimensions=[
                {
                    'Name': 'ClusterName',
                    'Value': cluster_name
                }
            ],
            StartTime=datetime.utcnow() - timedelta(hours=1),
            EndTime=datetime.utcnow(),
            Period=300,
            Statistics=['Average']
        )
        
        # Query memory utilization metrics
        memory_response = cloudwatch.get_metric_statistics(
            Namespace='ContainerInsights',
            MetricName='pod_memory_utilization',
            Dimensions=[
                {
                    'Name': 'ClusterName',
                    'Value': cluster_name
                }
            ],
            StartTime=datetime.utcnow() - timedelta(hours=1),
            EndTime=datetime.utcnow(),
            Period=300,
            Statistics=['Average']
        )
        
        # Analyze utilization data
        optimization_recommendations = []
        
        if cpu_response['Datapoints']:
            avg_cpu = sum(dp['Average'] for dp in cpu_response['Datapoints']) / len(cpu_response['Datapoints'])
            if avg_cpu < 30:  # CPU utilization below 30%
                optimization_recommendations.append(f'CPU utilization is low: {avg_cpu:.2f}%')
        
        if memory_response['Datapoints']:
            avg_memory = sum(dp['Average'] for dp in memory_response['Datapoints']) / len(memory_response['Datapoints'])
            if avg_memory < 40:  # Memory utilization below 40%
                optimization_recommendations.append(f'Memory utilization is low: {avg_memory:.2f}%')
        
        # Send SNS notification if optimization opportunities exist
        if optimization_recommendations:
            message = f'''
EKS Cost Optimization Alert for cluster: {cluster_name}

The following optimization opportunities have been identified:
{chr(10).join(f'• {rec}' for rec in optimization_recommendations)}

Recommendations:
• Review VPA recommendations for right-sizing
• Consider reducing resource requests/limits
• Evaluate if workloads can use Spot instances
• Check for unused or idle pods

Dashboard: https://console.aws.amazon.com/cloudwatch/home#dashboards:name=EKS-Cost-Optimization-{cluster_name}
            '''
            
            sns.publish(
                TopicArn=sns_topic_arn,
                Message=message,
                Subject=f'EKS Cost Optimization Alert: {cluster_name}'
            )
            
            print(f"Sent cost optimization alert for cluster {cluster_name}")
        else:
            print(f"No optimization opportunities found for cluster {cluster_name}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'cluster': cluster_name,
                'recommendations': optimization_recommendations,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        print(f"Error analyzing cluster {cluster_name}: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'cluster': cluster_name
            })
        }
"""

    def _add_cost_allocation_tags(self) -> None:
        """Add tags for cost allocation and tracking."""
        tags_to_add = {
            "Project": "ContainerOptimization",
            "Environment": "Production",
            "CostCenter": "Engineering",
            "Purpose": "ResourceOptimization",
            "Owner": "DevOps",
        }
        
        for key, value in tags_to_add.items():
            Tags.of(self).add(key, value)

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for the stack."""
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
            description="Endpoint URL of the EKS cluster",
        )
        
        CfnOutput(
            self,
            "ClusterArn",
            value=self.cluster.cluster_arn,
            description="ARN of the EKS cluster",
        )
        
        CfnOutput(
            self,
            "UpdateKubeconfigCommand",
            value=f"aws eks update-kubeconfig --region {self.region} --name {self.cluster.cluster_name}",
            description="Command to update kubeconfig for cluster access",
        )
        
        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name=EKS-Cost-Optimization-{self.cluster_name}",
            description="URL to the cost optimization dashboard",
        )
        
        CfnOutput(
            self,
            "SnsTopicArn",
            value=self.sns_topic.topic_arn,
            description="ARN of the SNS topic for cost alerts",
        )
        
        CfnOutput(
            self,
            "CostOptimizerLambdaArn",
            value=self.cost_optimizer_lambda.function_arn,
            description="ARN of the cost optimizer Lambda function",
        )


# Import CloudWatch actions for alarm actions
try:
    from aws_cdk import aws_cloudwatch_actions as cloudwatch_actions
except ImportError:
    # For older CDK versions, create a simple SNS action
    class cloudwatch_actions:
        @staticmethod
        def SnsAction(topic):
            return topic


def main() -> None:
    """Main function to create and deploy the CDK application."""
    app = App()
    
    # Get configuration from context or environment variables
    cluster_name = app.node.try_get_context("cluster_name") or os.environ.get("CLUSTER_NAME")
    aws_account = os.environ.get("CDK_DEFAULT_ACCOUNT")
    aws_region = os.environ.get("CDK_DEFAULT_REGION")
    
    # Create the stack
    ContainerResourceOptimizationStack(
        app,
        "ContainerResourceOptimizationStack",
        cluster_name=cluster_name,
        env=Environment(
            account=aws_account,
            region=aws_region,
        ),
        description="CDK Stack for Container Resource Optimization and Right-Sizing with Amazon EKS",
    )
    
    # Synthesize the CDK app
    app.synth()


if __name__ == "__main__":
    main()