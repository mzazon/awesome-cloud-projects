#!/usr/bin/env python3
"""
AWS CDK application for cost-aware resource lifecycle management with EventBridge Scheduler and MemoryDB.

This application creates a complete cost optimization system that automatically manages 
MemoryDB cluster scaling based on usage patterns, cost thresholds, and business hours.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    RemovalPolicy,
    Stack,
    StackProps,
    aws_budgets as budgets,
    aws_cloudwatch as cloudwatch,
    aws_events as events,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_logs as logs,
    aws_memorydb as memorydb,
    aws_scheduler as scheduler,
    aws_sqs as sqs,
)
from constructs import Construct


class CostAwareMemoryDBStack(Stack):
    """
    Stack for cost-aware MemoryDB resource lifecycle management.
    
    This stack creates:
    - MemoryDB cluster for cost optimization testing
    - Lambda function for intelligent cost management
    - EventBridge Scheduler for automated scaling
    - CloudWatch monitoring and alarms
    - Cost Explorer integration and budget alerts
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resources
        unique_suffix = cdk.Names.unique_id(self)[:6].lower()

        # Create IAM role for Lambda with comprehensive permissions
        lambda_role = self._create_lambda_execution_role(unique_suffix)

        # Create MemoryDB subnet group and cluster
        subnet_group, cluster = self._create_memorydb_cluster(unique_suffix)

        # Create Lambda function for cost optimization
        cost_optimizer_function = self._create_cost_optimizer_lambda(
            lambda_role, unique_suffix
        )

        # Create EventBridge Scheduler resources
        schedule_group = self._create_scheduler_group(unique_suffix)
        scheduler_role = self._create_scheduler_execution_role(
            cost_optimizer_function, unique_suffix
        )

        # Create business hours schedules
        self._create_business_hours_schedules(
            schedule_group, scheduler_role, cost_optimizer_function, 
            cluster.cluster_name, unique_suffix
        )

        # Create monitoring and alerting
        self._create_monitoring_dashboard(
            cluster.cluster_name, cost_optimizer_function.function_name, unique_suffix
        )

        # Create cost monitoring budget
        self._create_cost_budget(unique_suffix)

        # Stack outputs
        cdk.CfnOutput(
            self, "MemoryDBClusterName",
            value=cluster.cluster_name,
            description="Name of the MemoryDB cluster"
        )

        cdk.CfnOutput(
            self, "LambdaFunctionName",
            value=cost_optimizer_function.function_name,
            description="Name of the cost optimizer Lambda function"
        )

        cdk.CfnOutput(
            self, "SchedulerGroupName",
            value=schedule_group.schedule_group_name or "",
            description="Name of the EventBridge Scheduler group"
        )

    def _create_lambda_execution_role(self, suffix: str) -> iam.Role:
        """Create IAM role for Lambda function with necessary permissions."""
        role = iam.Role(
            self, "LambdaExecutionRole",
            role_name=f"memorydb-cost-optimizer-role-{suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Add custom policy for cost optimization operations
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "memorydb:DescribeClusters",
                    "memorydb:ModifyCluster",
                    "memorydb:DescribeSubnetGroups",
                    "memorydb:DescribeParameterGroups"
                ],
                resources=["*"]
            )
        )

        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ce:GetCostAndUsage",
                    "ce:GetUsageReport", 
                    "ce:GetDimensionValues",
                    "budgets:ViewBudget"
                ],
                resources=["*"]
            )
        )

        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudwatch:PutMetricData",
                    "cloudwatch:GetMetricStatistics"
                ],
                resources=["*"]
            )
        )

        return role

    def _create_memorydb_cluster(self, suffix: str) -> tuple[memorydb.CfnSubnetGroup, memorydb.CfnCluster]:
        """Create MemoryDB subnet group and cluster for cost optimization testing."""
        
        # Get default VPC subnets
        vpc = cdk.aws_ec2.Vpc.from_lookup(self, "DefaultVpc", is_default=True)
        
        # Create subnet group
        subnet_group = memorydb.CfnSubnetGroup(
            self, "MemoryDBSubnetGroup",
            subnet_group_name=f"cost-aware-memorydb-{suffix}-subnet-group",
            description="Subnet group for cost-aware MemoryDB cluster",
            subnet_ids=[subnet.subnet_id for subnet in vpc.private_subnets[:2]]
            if vpc.private_subnets else [subnet.subnet_id for subnet in vpc.public_subnets[:2]]
        )

        # Create MemoryDB cluster with cost-conscious initial sizing
        cluster = memorydb.CfnCluster(
            self, "MemoryDBCluster",
            cluster_name=f"cost-aware-memorydb-{suffix}",
            node_type="db.t4g.small",  # AWS Graviton2 for optimal price-performance
            num_shards=1,
            num_replicas_per_shard=0,  # Start with minimal configuration
            subnet_group_name=subnet_group.subnet_group_name,
            maintenance_window="sun:03:00-sun:04:00",
            description="MemoryDB cluster for cost optimization testing",
            tags=[
                cdk.CfnTag(key="Purpose", value="CostOptimization"),
                cdk.CfnTag(key="Environment", value="Test"),
                cdk.CfnTag(key="CreatedBy", value="CDK")
            ]
        )

        cluster.add_dependency(subnet_group)
        return subnet_group, cluster

    def _create_cost_optimizer_lambda(self, role: iam.Role, suffix: str) -> lambda_.Function:
        """Create Lambda function for intelligent cost management."""
        
        function = lambda_.Function(
            self, "CostOptimizerFunction",
            function_name=f"memorydb-cost-optimizer-{suffix}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="lambda_function.lambda_handler",
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            role=role,
            timeout=Duration.minutes(5),
            memory_size=256,
            description="Cost-aware MemoryDB cluster lifecycle management",
            environment={
                "LOG_LEVEL": "INFO"
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            retry_attempts=0  # Disable automatic retries for cost optimization
        )

        return function

    def _get_lambda_code(self) -> str:
        """Return the Lambda function code for cost optimization."""
        return '''
import json
import boto3
import datetime
import logging
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

memorydb = boto3.client('memorydb')
ce = boto3.client('ce')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Intelligent cost-aware MemoryDB cluster management.
    Analyzes cost patterns and adjusts cluster configuration based on thresholds.
    """
    
    cluster_name = event.get('cluster_name')
    action = event.get('action', 'analyze')
    cost_threshold = event.get('cost_threshold', 100.0)
    
    if not cluster_name:
        return {
            'statusCode': 400,
            'body': {'error': 'cluster_name is required'}
        }
    
    try:
        # Get current cluster status
        cluster_response = memorydb.describe_clusters(ClusterName=cluster_name)
        if not cluster_response['Clusters']:
            return {
                'statusCode': 404,
                'body': {'error': f'Cluster {cluster_name} not found'}
            }
            
        cluster = cluster_response['Clusters'][0]
        current_node_type = cluster['NodeType']
        current_shards = cluster['NumberOfShards']
        cluster_status = cluster['Status']
        
        # Only proceed if cluster is available
        if cluster_status != 'available':
            logger.warning(f"Cluster {cluster_name} is not available, status: {cluster_status}")
            return {
                'statusCode': 200,
                'body': {'message': f'Cluster not available for modification, status: {cluster_status}'}
            }
        
        # Analyze recent cost trends
        cost_data = get_cost_analysis()
        memorydb_cost = cost_data['total_cost']
        
        # Determine scaling action based on cost analysis
        scaling_recommendation = analyze_scaling_needs(
            memorydb_cost, cost_threshold, current_node_type, action
        )
        
        # Execute scaling if recommended and cluster is available
        if scaling_recommendation['action'] != 'none' and cluster_status == 'available':
            modify_result = modify_cluster(cluster_name, scaling_recommendation)
            scaling_recommendation['execution_result'] = modify_result
        
        # Send metrics to CloudWatch
        send_cloudwatch_metrics(cluster_name, memorydb_cost, scaling_recommendation)
        
        return {
            'statusCode': 200,
            'body': {
                'cluster_name': cluster_name,
                'current_cost': memorydb_cost,
                'current_node_type': current_node_type,
                'recommendation': scaling_recommendation,
                'timestamp': datetime.datetime.now().isoformat()
            }
        }
        
    except Exception as e:
        logger.error(f"Error in cost optimization: {str(e)}")
        return {
            'statusCode': 500,
            'body': {'error': str(e)}
        }

def get_cost_analysis() -> Dict[str, float]:
    """Retrieve and analyze recent MemoryDB costs."""
    try:
        end_date = datetime.datetime.now()
        start_date = end_date - datetime.timedelta(days=7)
        
        cost_response = ce.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='DAILY',
            Metrics=['BlendedCost'],
            GroupBy=[
                {'Type': 'DIMENSION', 'Key': 'SERVICE'},
            ]
        )
        
        # Calculate MemoryDB costs
        memorydb_cost = 0.0
        for result_by_time in cost_response['ResultsByTime']:
            for group in result_by_time['Groups']:
                if 'MemoryDB' in group['Keys'][0] or 'ElastiCache' in group['Keys'][0]:
                    memorydb_cost += float(group['Metrics']['BlendedCost']['Amount'])
        
        return {'total_cost': memorydb_cost}
        
    except Exception as e:
        logger.warning(f"Could not retrieve cost data: {str(e)}")
        return {'total_cost': 0.0}

def analyze_scaling_needs(cost: float, threshold: float, node_type: str, action: str) -> Dict[str, Any]:
    """Analyze cost patterns and recommend scaling actions."""
    
    if action == 'scale_down' and cost > threshold:
        # Business hours ended, scale down for cost savings
        if 'large' in node_type:
            return {
                'action': 'modify_node_type',
                'target_node_type': node_type.replace('large', 'small'),
                'reason': 'Off-peak cost optimization',
                'estimated_savings': '30-40%'
            }
        elif 'medium' in node_type:
            return {
                'action': 'modify_node_type',
                'target_node_type': node_type.replace('medium', 'small'),
                'reason': 'Off-peak cost optimization',
                'estimated_savings': '20-30%'
            }
    elif action == 'scale_up':
        # Business hours starting, scale up for performance
        if 'small' in node_type:
            return {
                'action': 'modify_node_type',
                'target_node_type': node_type.replace('small', 'medium'),
                'reason': 'Business hours performance optimization',
                'estimated_impact': 'Improved performance for business workloads'
            }
    
    return {'action': 'none', 'reason': 'No scaling needed based on current conditions'}

def modify_cluster(cluster_name: str, recommendation: Dict[str, Any]) -> Dict[str, str]:
    """Execute cluster modifications based on recommendations."""
    
    try:
        if recommendation['action'] == 'modify_node_type':
            response = memorydb.modify_cluster(
                ClusterName=cluster_name,
                NodeType=recommendation['target_node_type']
            )
            
            logger.info(f"Initiated cluster modification: {cluster_name} -> {recommendation['target_node_type']}")
            return {
                'status': 'initiated',
                'message': f"Cluster modification started to {recommendation['target_node_type']}"
            }
            
    except Exception as e:
        logger.error(f"Failed to modify cluster {cluster_name}: {str(e)}")
        return {
            'status': 'failed',
            'message': f"Cluster modification failed: {str(e)}"
        }

def send_cloudwatch_metrics(cluster_name: str, cost: float, recommendation: Dict[str, Any]) -> None:
    """Send cost optimization metrics to CloudWatch."""
    
    try:
        cloudwatch.put_metric_data(
            Namespace='MemoryDB/CostOptimization',
            MetricData=[
                {
                    'MetricName': 'WeeklyCost',
                    'Value': cost,
                    'Unit': 'None',
                    'Dimensions': [
                        {'Name': 'ClusterName', 'Value': cluster_name}
                    ]
                },
                {
                    'MetricName': 'OptimizationAction',
                    'Value': 1 if recommendation['action'] != 'none' else 0,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'ClusterName', 'Value': cluster_name}
                    ]
                }
            ]
        )
    except Exception as e:
        logger.warning(f"Failed to send CloudWatch metrics: {str(e)}")
        '''

    def _create_scheduler_group(self, suffix: str) -> scheduler.CfnScheduleGroup:
        """Create EventBridge Scheduler group for organizing schedules."""
        
        return scheduler.CfnScheduleGroup(
            self, "SchedulerGroup",
            name=f"cost-optimization-schedules-{suffix}",
            description="Cost optimization schedules for MemoryDB lifecycle management"
        )

    def _create_scheduler_execution_role(self, lambda_function: lambda_.Function, suffix: str) -> iam.Role:
        """Create IAM role for EventBridge Scheduler to invoke Lambda."""
        
        role = iam.Role(
            self, "SchedulerExecutionRole",
            role_name=f"eventbridge-scheduler-role-{suffix}",
            assumed_by=iam.ServicePrincipal("scheduler.amazonaws.com")
        )

        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["lambda:InvokeFunction"],
                resources=[lambda_function.function_arn]
            )
        )

        return role

    def _create_business_hours_schedules(
        self, 
        schedule_group: scheduler.CfnScheduleGroup,
        scheduler_role: iam.Role,
        lambda_function: lambda_.Function,
        cluster_name: str,
        suffix: str
    ) -> None:
        """Create EventBridge schedules for business hours automation."""
        
        # Business hours scale-up schedule (8 AM weekdays)
        scheduler.CfnSchedule(
            self, "BusinessHoursStartSchedule",
            name=f"memorydb-business-hours-start-{suffix}",
            group_name=schedule_group.name,
            schedule_expression="cron(0 8 ? * MON-FRI *)",
            target=scheduler.CfnSchedule.TargetProperty(
                arn=lambda_function.function_arn,
                role_arn=scheduler_role.role_arn,
                input=json.dumps({
                    "cluster_name": cluster_name,
                    "action": "scale_up", 
                    "cost_threshold": 100
                })
            ),
            flexible_time_window=scheduler.CfnSchedule.FlexibleTimeWindowProperty(
                mode="OFF"
            ),
            description="Scale up MemoryDB for business hours performance"
        )

        # Off-hours scale-down schedule (6 PM weekdays)
        scheduler.CfnSchedule(
            self, "BusinessHoursEndSchedule", 
            name=f"memorydb-business-hours-end-{suffix}",
            group_name=schedule_group.name,
            schedule_expression="cron(0 18 ? * MON-FRI *)",
            target=scheduler.CfnSchedule.TargetProperty(
                arn=lambda_function.function_arn,
                role_arn=scheduler_role.role_arn,
                input=json.dumps({
                    "cluster_name": cluster_name,
                    "action": "scale_down",
                    "cost_threshold": 50
                })
            ),
            flexible_time_window=scheduler.CfnSchedule.FlexibleTimeWindowProperty(
                mode="OFF"
            ),
            description="Scale down MemoryDB for cost optimization during off-hours"
        )

        # Weekly cost analysis schedule (Monday 9 AM)
        scheduler.CfnSchedule(
            self, "WeeklyCostAnalysisSchedule",
            name=f"memorydb-weekly-cost-analysis-{suffix}",
            group_name=schedule_group.name,
            schedule_expression="cron(0 9 ? * MON *)",
            target=scheduler.CfnSchedule.TargetProperty(
                arn=lambda_function.function_arn,
                role_arn=scheduler_role.role_arn,
                input=json.dumps({
                    "cluster_name": cluster_name,
                    "action": "analyze",
                    "cost_threshold": 150
                })
            ),
            flexible_time_window=scheduler.CfnSchedule.FlexibleTimeWindowProperty(
                mode="OFF" 
            ),
            description="Weekly MemoryDB cost analysis and optimization review"
        )

    def _create_monitoring_dashboard(
        self, 
        cluster_name: str, 
        function_name: str, 
        suffix: str
    ) -> None:
        """Create CloudWatch dashboard and alarms for monitoring."""
        
        # Create comprehensive monitoring dashboard
        dashboard = cloudwatch.Dashboard(
            self, "CostOptimizationDashboard",
            dashboard_name=f"MemoryDB-Cost-Optimization-{suffix}",
            widgets=[
                # Cost optimization metrics
                [cloudwatch.GraphWidget(
                    title="MemoryDB Cost Optimization Metrics",
                    left=[
                        cloudwatch.Metric(
                            namespace="MemoryDB/CostOptimization",
                            metric_name="WeeklyCost",
                            dimensions_map={"ClusterName": cluster_name},
                            statistic="Average",
                            period=Duration.days(1)
                        ),
                        cloudwatch.Metric(
                            namespace="MemoryDB/CostOptimization", 
                            metric_name="OptimizationAction",
                            dimensions_map={"ClusterName": cluster_name},
                            statistic="Average",
                            period=Duration.days(1)
                        )
                    ],
                    width=12,
                    height=6
                )],
                
                # MemoryDB performance metrics
                [cloudwatch.GraphWidget(
                    title="MemoryDB Performance Metrics",
                    left=[
                        cloudwatch.Metric(
                            namespace="AWS/MemoryDB",
                            metric_name="CPUUtilization",
                            dimensions_map={"ClusterName": cluster_name},
                            statistic="Average"
                        ),
                        cloudwatch.Metric(
                            namespace="AWS/MemoryDB",
                            metric_name="NetworkBytesIn", 
                            dimensions_map={"ClusterName": cluster_name},
                            statistic="Average"
                        )
                    ],
                    width=12,
                    height=6
                )],
                
                # Lambda function metrics
                [cloudwatch.GraphWidget(
                    title="Cost Optimization Lambda Metrics",
                    left=[
                        cloudwatch.Metric(
                            namespace="AWS/Lambda",
                            metric_name="Duration",
                            dimensions_map={"FunctionName": function_name},
                            statistic="Average"
                        ),
                        cloudwatch.Metric(
                            namespace="AWS/Lambda",
                            metric_name="Errors",
                            dimensions_map={"FunctionName": function_name},
                            statistic="Sum"
                        ),
                        cloudwatch.Metric(
                            namespace="AWS/Lambda", 
                            metric_name="Invocations",
                            dimensions_map={"FunctionName": function_name},
                            statistic="Sum"
                        )
                    ],
                    width=24,
                    height=6
                )]
            ]
        )

        # Cost alarm for weekly costs
        cloudwatch.Alarm(
            self, "WeeklyCostHighAlarm",
            alarm_name=f"MemoryDB-Weekly-Cost-High-{suffix}",
            alarm_description="Alert when MemoryDB weekly costs exceed threshold",
            metric=cloudwatch.Metric(
                namespace="MemoryDB/CostOptimization",
                metric_name="WeeklyCost",
                dimensions_map={"ClusterName": cluster_name},
                statistic="Average",
                period=Duration.days(7)
            ),
            threshold=150,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Lambda error alarm
        cloudwatch.Alarm(
            self, "LambdaErrorAlarm",
            alarm_name=f"MemoryDB-Optimizer-Lambda-Errors-{suffix}",
            alarm_description="Alert when cost optimization Lambda function has errors", 
            metric=cloudwatch.Metric(
                namespace="AWS/Lambda",
                metric_name="Errors",
                dimensions_map={"FunctionName": function_name},
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=2
        )

    def _create_cost_budget(self, suffix: str) -> None:
        """Create budget for MemoryDB cost monitoring."""
        
        budgets.CfnBudget(
            self, "MemoryDBCostBudget",
            budget=budgets.CfnBudget.BudgetDataProperty(
                budget_name=f"MemoryDB-Cost-Budget-{suffix}",
                budget_limit=budgets.CfnBudget.SpendProperty(
                    amount=200,
                    unit="USD"
                ),
                time_unit="MONTHLY",
                budget_type="COST",
                cost_filters=budgets.CfnBudget.CostFiltersProperty(
                    service=["Amazon MemoryDB for Redis"]
                ),
                time_period=budgets.CfnBudget.TimePeriodProperty(
                    start="2025-07-01",
                    end="2025-12-31"
                )
            ),
            notifications_with_subscribers=[
                budgets.CfnBudget.NotificationWithSubscribersProperty(
                    notification=budgets.CfnBudget.NotificationProperty(
                        notification_type="ACTUAL",
                        comparison_operator="GREATER_THAN",
                        threshold=80,
                        threshold_type="PERCENTAGE"
                    ),
                    subscribers=[
                        budgets.CfnBudget.SubscriberProperty(
                            subscription_type="EMAIL",
                            address="admin@example.com"
                        )
                    ]
                ),
                budgets.CfnBudget.NotificationWithSubscribersProperty(
                    notification=budgets.CfnBudget.NotificationProperty(
                        notification_type="FORECASTED",
                        comparison_operator="GREATER_THAN", 
                        threshold=90,
                        threshold_type="PERCENTAGE"
                    ),
                    subscribers=[
                        budgets.CfnBudget.SubscriberProperty(
                            subscription_type="EMAIL",
                            address="admin@example.com"
                        )
                    ]
                )
            ]
        )


# CDK App definition
app = cdk.App()

CostAwareMemoryDBStack(
    app, 
    "CostAwareMemoryDBStack",
    description="Cost-aware resource lifecycle management with EventBridge Scheduler and MemoryDB",
    env=cdk.Environment(
        account=os.getenv('CDK_DEFAULT_ACCOUNT'),
        region=os.getenv('CDK_DEFAULT_REGION')
    )
)

app.synth()