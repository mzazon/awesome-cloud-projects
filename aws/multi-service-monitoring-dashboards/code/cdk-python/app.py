#!/usr/bin/env python3
"""
Advanced Multi-Service Monitoring Dashboards with Custom Metrics and Anomaly Detection

This CDK application creates a comprehensive monitoring solution that combines infrastructure
metrics with custom business metrics, implementing intelligent anomaly detection and
role-specific dashboards for enterprise observability.

Author: AWS CDK Team
Version: 1.0.0
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cloudwatch_actions,
    aws_events as events,
    aws_events_targets as events_targets,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_logs as logs,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
)
from constructs import Construct


class AdvancedMonitoringStack(Stack):
    """
    Main stack for the advanced monitoring solution.
    
    Creates Lambda functions for custom metrics collection, SNS topics for tiered alerting,
    CloudWatch dashboards for different audiences, and anomaly detection capabilities.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        project_name: str,
        alert_email: str,
        **kwargs
    ) -> None:
        """
        Initialize the Advanced Monitoring Stack.
        
        Args:
            scope: The parent construct
            construct_id: Unique identifier for this construct
            project_name: Name prefix for all resources
            alert_email: Email address for critical alerts
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        self.project_name = project_name
        self.alert_email = alert_email

        # Create foundational resources
        self.sns_topics = self._create_sns_topics()
        self.lambda_role = self._create_lambda_execution_role()
        
        # Create Lambda functions for metric collection
        self.business_metrics_function = self._create_business_metrics_function()
        self.infrastructure_health_function = self._create_infrastructure_health_function()
        self.cost_monitoring_function = self._create_cost_monitoring_function()
        
        # Set up scheduled metric collection
        self._create_scheduled_invocations()
        
        # Create CloudWatch dashboards
        self._create_infrastructure_dashboard()
        self._create_business_dashboard()
        self._create_executive_dashboard()
        self._create_operations_dashboard()
        
        # Set up anomaly detection and alarms
        self._create_anomaly_detection()
        self._create_intelligent_alarms()
        
        # Create outputs
        self._create_outputs()

    def _create_sns_topics(self) -> Dict[str, sns.Topic]:
        """Create SNS topics for tiered alerting."""
        topics = {}
        
        # Critical alerts topic
        topics['critical'] = sns.Topic(
            self,
            "CriticalAlerts",
            topic_name=f"{self.project_name}-critical",
            display_name="Critical Alerts for Production Issues",
            description="High-priority alerts requiring immediate attention"
        )
        
        # Warning alerts topic
        topics['warning'] = sns.Topic(
            self,
            "WarningAlerts",
            topic_name=f"{self.project_name}-warning",
            display_name="Warning Alerts for Performance Issues",
            description="Medium-priority alerts for performance degradation"
        )
        
        # Info alerts topic
        topics['info'] = sns.Topic(
            self,
            "InfoAlerts",
            topic_name=f"{self.project_name}-info",
            display_name="Info Alerts for System Changes",
            description="Low-priority alerts for system changes and updates"
        )
        
        # Subscribe email to critical alerts
        topics['critical'].add_subscription(
            sns_subscriptions.EmailSubscription(self.alert_email)
        )
        
        return topics

    def _create_lambda_execution_role(self) -> iam.Role:
        """Create IAM role for Lambda functions with necessary permissions."""
        role = iam.Role(
            self,
            "LambdaExecutionRole",
            role_name=f"{self.project_name}-lambda-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for monitoring Lambda functions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "CloudWatchFullAccess"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonRDSReadOnlyAccess"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonElastiCacheReadOnlyAccess"
                )
            ]
        )
        
        # Add Cost Explorer permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ce:GetCostAndUsage",
                    "ce:GetUsageReport",
                    "ce:ListCostCategoryDefinitions",
                    "ce:GetDimensionValues"
                ],
                resources=["*"]
            )
        )
        
        return role

    def _create_business_metrics_function(self) -> lambda_.Function:
        """Create Lambda function for business metrics collection."""
        return lambda_.Function(
            self,
            "BusinessMetricsFunction",
            function_name=f"{self.project_name}-business-metrics",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=self.lambda_role,
            timeout=Duration.seconds(60),
            memory_size=256,
            environment={
                "PROJECT_NAME": self.project_name,
                "ENVIRONMENT": "production"
            },
            code=lambda_.Code.from_inline("""
import json
import boto3
import random
from datetime import datetime

cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    try:
        # Simulate business metrics (replace with real business logic)
        
        # Revenue metrics
        hourly_revenue = random.uniform(10000, 50000)
        transaction_count = random.randint(100, 1000)
        average_order_value = hourly_revenue / transaction_count
        
        # User engagement metrics
        active_users = random.randint(500, 5000)
        page_views = random.randint(10000, 50000)
        bounce_rate = random.uniform(0.2, 0.8)
        
        # Performance metrics
        api_response_time = random.uniform(100, 2000)
        error_rate = random.uniform(0.001, 0.05)
        throughput = random.randint(100, 1000)
        
        # Customer satisfaction
        nps_score = random.uniform(6.0, 9.5)
        support_ticket_volume = random.randint(5, 50)
        
        # Send custom metrics to CloudWatch
        metrics = [
            {
                'MetricName': 'HourlyRevenue',
                'Value': hourly_revenue,
                'Unit': 'None',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': 'production'},
                    {'Name': 'BusinessUnit', 'Value': 'ecommerce'}
                ]
            },
            {
                'MetricName': 'TransactionCount',
                'Value': transaction_count,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': 'production'},
                    {'Name': 'BusinessUnit', 'Value': 'ecommerce'}
                ]
            },
            {
                'MetricName': 'AverageOrderValue',
                'Value': average_order_value,
                'Unit': 'None',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': 'production'},
                    {'Name': 'BusinessUnit', 'Value': 'ecommerce'}
                ]
            },
            {
                'MetricName': 'ActiveUsers',
                'Value': active_users,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': 'production'}
                ]
            },
            {
                'MetricName': 'APIResponseTime',
                'Value': api_response_time,
                'Unit': 'Milliseconds',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': 'production'},
                    {'Name': 'Service', 'Value': 'api-gateway'}
                ]
            },
            {
                'MetricName': 'ErrorRate',
                'Value': error_rate,
                'Unit': 'Percent',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': 'production'},
                    {'Name': 'Service', 'Value': 'api-gateway'}
                ]
            },
            {
                'MetricName': 'NPSScore',
                'Value': nps_score,
                'Unit': 'None',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': 'production'}
                ]
            },
            {
                'MetricName': 'SupportTicketVolume',
                'Value': support_ticket_volume,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': 'production'}
                ]
            }
        ]
        
        # Submit metrics in batches
        for i in range(0, len(metrics), 20):
            batch = metrics[i:i+20]
            cloudwatch.put_metric_data(
                Namespace='Business/Metrics',
                MetricData=batch
            )
        
        # Calculate and submit composite health score
        health_score = calculate_health_score(
            api_response_time, error_rate, nps_score, 
            support_ticket_volume, active_users
        )
        
        cloudwatch.put_metric_data(
            Namespace='Business/Health',
            MetricData=[
                {
                    'MetricName': 'CompositeHealthScore',
                    'Value': health_score,
                    'Unit': 'Percent',
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': 'production'}
                    ]
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Business metrics published successfully',
                'health_score': health_score,
                'metrics_count': len(metrics)
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def calculate_health_score(response_time, error_rate, nps, tickets, users):
    \"\"\"Calculate composite health score based on multiple metrics.\"\"\"
    # Normalize metrics to 0-100 scale and weight them
    response_score = max(0, 100 - (response_time / 20))  # Lower is better
    error_score = max(0, 100 - (error_rate * 2000))      # Lower is better
    nps_score = (nps / 10) * 100                         # Higher is better
    ticket_score = max(0, 100 - (tickets * 2))          # Lower is better
    user_score = min(100, (users / 50))                 # Higher is better
    
    # Weighted average
    weights = [0.25, 0.30, 0.20, 0.15, 0.10]
    scores = [response_score, error_score, nps_score, ticket_score, user_score]
    
    return sum(w * s for w, s in zip(weights, scores))
            """),
            description="Collects and publishes business metrics to CloudWatch",
            log_retention=logs.RetentionDays.ONE_MONTH
        )

    def _create_infrastructure_health_function(self) -> lambda_.Function:
        """Create Lambda function for infrastructure health monitoring."""
        return lambda_.Function(
            self,
            "InfrastructureHealthFunction",
            function_name=f"{self.project_name}-infrastructure-health",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=self.lambda_role,
            timeout=Duration.seconds(120),
            memory_size=256,
            environment={
                "PROJECT_NAME": self.project_name,
                "ENVIRONMENT": "production"
            },
            code=lambda_.Code.from_inline("""
import json
import boto3
from datetime import datetime, timedelta

cloudwatch = boto3.client('cloudwatch')
rds = boto3.client('rds')
elasticache = boto3.client('elasticache')
ec2 = boto3.client('ec2')

def lambda_handler(event, context):
    try:
        health_scores = {}
        
        # Check RDS health
        rds_health = check_rds_health()
        health_scores['RDS'] = rds_health
        
        # Check ElastiCache health
        cache_health = check_elasticache_health()
        health_scores['ElastiCache'] = cache_health
        
        # Check EC2/ECS health
        compute_health = check_compute_health()
        health_scores['Compute'] = compute_health
        
        # Calculate overall infrastructure health
        overall_health = sum(health_scores.values()) / len(health_scores)
        
        # Publish infrastructure health metrics
        metrics = []
        for service, score in health_scores.items():
            metrics.append({
                'MetricName': f'{service}HealthScore',
                'Value': score,
                'Unit': 'Percent',
                'Dimensions': [
                    {'Name': 'Service', 'Value': service},
                    {'Name': 'Environment', 'Value': 'production'}
                ]
            })
        
        # Add overall health score
        metrics.append({
            'MetricName': 'OverallInfrastructureHealth',
            'Value': overall_health,
            'Unit': 'Percent',
            'Dimensions': [
                {'Name': 'Environment', 'Value': 'production'}
            ]
        })
        
        cloudwatch.put_metric_data(
            Namespace='Infrastructure/Health',
            MetricData=metrics
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'health_scores': health_scores,
                'overall_health': overall_health
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def check_rds_health():
    \"\"\"Check RDS instance health.\"\"\"
    try:
        instances = rds.describe_db_instances()
        if not instances['DBInstances']:
            return 100  # No instances to monitor
        
        healthy_count = 0
        total_count = len(instances['DBInstances'])
        
        for instance in instances['DBInstances']:
            if instance['DBInstanceStatus'] == 'available':
                healthy_count += 1
        
        return (healthy_count / total_count) * 100
    except Exception as e:
        print(f"RDS health check error: {str(e)}")
        return 50  # Assume degraded if can't check

def check_elasticache_health():
    \"\"\"Check ElastiCache cluster health.\"\"\"
    try:
        clusters = elasticache.describe_cache_clusters()
        if not clusters['CacheClusters']:
            return 100  # No clusters to monitor
        
        healthy_count = 0
        total_count = len(clusters['CacheClusters'])
        
        for cluster in clusters['CacheClusters']:
            if cluster['CacheClusterStatus'] == 'available':
                healthy_count += 1
        
        return (healthy_count / total_count) * 100
    except Exception as e:
        print(f"ElastiCache health check error: {str(e)}")
        return 50  # Assume degraded if can't check

def check_compute_health():
    \"\"\"Check compute resource health.\"\"\"
    try:
        # Simplified compute health check
        instances = ec2.describe_instances(
            Filters=[
                {'Name': 'instance-state-name', 'Values': ['running']}
            ]
        )
        
        total_instances = 0
        for reservation in instances['Reservations']:
            total_instances += len(reservation['Instances'])
        
        # Simple health heuristic based on running instances
        if total_instances == 0:
            return 100  # No instances to monitor
        elif total_instances >= 3:
            return 95   # Good redundancy
        elif total_instances >= 2:
            return 80   # Acceptable redundancy
        else:
            return 60   # Limited redundancy
            
    except Exception as e:
        print(f"Compute health check error: {str(e)}")
        return 50  # Assume degraded if can't check
            """),
            description="Monitors infrastructure health across AWS services",
            log_retention=logs.RetentionDays.ONE_MONTH
        )

    def _create_cost_monitoring_function(self) -> lambda_.Function:
        """Create Lambda function for cost monitoring."""
        return lambda_.Function(
            self,
            "CostMonitoringFunction",
            function_name=f"{self.project_name}-cost-monitoring",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=self.lambda_role,
            timeout=Duration.seconds(120),
            memory_size=256,
            environment={
                "PROJECT_NAME": self.project_name,
                "ENVIRONMENT": "production"
            },
            code=lambda_.Code.from_inline("""
import json
import boto3
from datetime import datetime, timedelta

cloudwatch = boto3.client('cloudwatch')
ce = boto3.client('ce')

def lambda_handler(event, context):
    try:
        # Get cost data for the last 7 days
        end_date = datetime.now().date()
        start_date = end_date - timedelta(days=7)
        
        response = ce.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='DAILY',
            Metrics=['BlendedCost'],
            GroupBy=[
                {
                    'Type': 'DIMENSION',
                    'Key': 'SERVICE'
                }
            ]
        )
        
        # Calculate daily cost trend
        daily_costs = []
        for result in response['ResultsByTime']:
            daily_cost = float(result['Total']['BlendedCost']['Amount'])
            daily_costs.append(daily_cost)
        
        # Calculate cost metrics
        if daily_costs:
            avg_daily_cost = sum(daily_costs) / len(daily_costs)
            latest_cost = daily_costs[-1]
            cost_trend = ((latest_cost - avg_daily_cost) / avg_daily_cost) * 100 if avg_daily_cost > 0 else 0
        else:
            avg_daily_cost = 0
            latest_cost = 0
            cost_trend = 0
        
        # Publish cost metrics
        cloudwatch.put_metric_data(
            Namespace='Cost/Management',
            MetricData=[
                {
                    'MetricName': 'DailyCost',
                    'Value': latest_cost,
                    'Unit': 'None',
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': 'production'}
                    ]
                },
                {
                    'MetricName': 'CostTrend',
                    'Value': cost_trend,
                    'Unit': 'Percent',
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': 'production'}
                    ]
                },
                {
                    'MetricName': 'WeeklyAverageCost',
                    'Value': avg_daily_cost,
                    'Unit': 'None',
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': 'production'}
                    ]
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'daily_cost': latest_cost,
                'cost_trend': cost_trend,
                'weekly_average': avg_daily_cost
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
            """),
            description="Monitors AWS costs and publishes trend metrics",
            log_retention=logs.RetentionDays.ONE_MONTH
        )

    def _create_scheduled_invocations(self) -> None:
        """Create EventBridge rules for scheduled metric collection."""
        # Business metrics every 5 minutes
        business_metrics_rule = events.Rule(
            self,
            "BusinessMetricsRule",
            rule_name=f"{self.project_name}-business-metrics",
            description="Collect business metrics every 5 minutes",
            schedule=events.Schedule.rate(Duration.minutes(5)),
            enabled=True
        )
        business_metrics_rule.add_target(
            events_targets.LambdaFunction(self.business_metrics_function)
        )
        
        # Infrastructure health every 10 minutes
        infrastructure_health_rule = events.Rule(
            self,
            "InfrastructureHealthRule",
            rule_name=f"{self.project_name}-infrastructure-health",
            description="Check infrastructure health every 10 minutes",
            schedule=events.Schedule.rate(Duration.minutes(10)),
            enabled=True
        )
        infrastructure_health_rule.add_target(
            events_targets.LambdaFunction(self.infrastructure_health_function)
        )
        
        # Cost monitoring daily
        cost_monitoring_rule = events.Rule(
            self,
            "CostMonitoringRule",
            rule_name=f"{self.project_name}-cost-monitoring",
            description="Daily cost monitoring",
            schedule=events.Schedule.rate(Duration.days(1)),
            enabled=True
        )
        cost_monitoring_rule.add_target(
            events_targets.LambdaFunction(self.cost_monitoring_function)
        )

    def _create_infrastructure_dashboard(self) -> None:
        """Create infrastructure monitoring dashboard."""
        dashboard = cloudwatch.Dashboard(
            self,
            "InfrastructureDashboard",
            dashboard_name=f"{self.project_name}-Infrastructure",
            widgets=[
                [
                    # Overall System Health
                    cloudwatch.GraphWidget(
                        title="Overall System Health",
                        left=[
                            cloudwatch.Metric(
                                namespace="Infrastructure/Health",
                                metric_name="OverallInfrastructureHealth",
                                dimensions_map={"Environment": "production"}
                            ),
                            cloudwatch.Metric(
                                namespace="Business/Health",
                                metric_name="CompositeHealthScore",
                                dimensions_map={"Environment": "production"}
                            )
                        ],
                        period=Duration.minutes(5),
                        width=8,
                        height=6,
                        left_y_axis=cloudwatch.YAxisProps(min=0, max=100)
                    ),
                    # ECS Service Utilization
                    cloudwatch.GraphWidget(
                        title="ECS Service Utilization",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/ECS",
                                metric_name="CPUUtilization",
                                dimensions_map={"ServiceName": "web-service"}
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/ECS",
                                metric_name="MemoryUtilization",
                                dimensions_map={"ServiceName": "web-service"}
                            )
                        ],
                        period=Duration.minutes(5),
                        width=8,
                        height=6
                    ),
                    # RDS Performance Metrics
                    cloudwatch.GraphWidget(
                        title="RDS Performance Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/RDS",
                                metric_name="CPUUtilization",
                                dimensions_map={"DBInstanceIdentifier": "production-db"}
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/RDS",
                                metric_name="DatabaseConnections",
                                dimensions_map={"DBInstanceIdentifier": "production-db"}
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/RDS",
                                metric_name="FreeableMemory",
                                dimensions_map={"DBInstanceIdentifier": "production-db"}
                            )
                        ],
                        period=Duration.minutes(5),
                        width=8,
                        height=6
                    )
                ],
                [
                    # ElastiCache Performance
                    cloudwatch.GraphWidget(
                        title="ElastiCache Performance",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/ElastiCache",
                                metric_name="CPUUtilization",
                                dimensions_map={"CacheClusterId": "production-cache"}
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/ElastiCache",
                                metric_name="CacheHits",
                                dimensions_map={"CacheClusterId": "production-cache"}
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/ElastiCache",
                                metric_name="CacheMisses",
                                dimensions_map={"CacheClusterId": "production-cache"}
                            )
                        ],
                        period=Duration.minutes(5),
                        width=12,
                        height=6
                    ),
                    # Service Health Scores
                    cloudwatch.GraphWidget(
                        title="Service Health Scores",
                        left=[
                            cloudwatch.Metric(
                                namespace="Infrastructure/Health",
                                metric_name="RDSHealthScore",
                                dimensions_map={"Service": "RDS", "Environment": "production"}
                            ),
                            cloudwatch.Metric(
                                namespace="Infrastructure/Health",
                                metric_name="ElastiCacheHealthScore",
                                dimensions_map={"Service": "ElastiCache", "Environment": "production"}
                            ),
                            cloudwatch.Metric(
                                namespace="Infrastructure/Health",
                                metric_name="ComputeHealthScore",
                                dimensions_map={"Service": "Compute", "Environment": "production"}
                            )
                        ],
                        period=Duration.minutes(5),
                        width=12,
                        height=6,
                        left_y_axis=cloudwatch.YAxisProps(min=0, max=100)
                    )
                ]
            ]
        )

    def _create_business_dashboard(self) -> None:
        """Create business metrics dashboard."""
        dashboard = cloudwatch.Dashboard(
            self,
            "BusinessDashboard",
            dashboard_name=f"{self.project_name}-Business",
            widgets=[
                [
                    # Hourly Revenue
                    cloudwatch.GraphWidget(
                        title="Hourly Revenue",
                        left=[
                            cloudwatch.Metric(
                                namespace="Business/Metrics",
                                metric_name="HourlyRevenue",
                                dimensions_map={"Environment": "production", "BusinessUnit": "ecommerce"}
                            )
                        ],
                        period=Duration.minutes(5),
                        width=8,
                        height=6
                    ),
                    # Transaction Volume & Active Users
                    cloudwatch.GraphWidget(
                        title="Transaction Volume & Active Users",
                        left=[
                            cloudwatch.Metric(
                                namespace="Business/Metrics",
                                metric_name="TransactionCount",
                                dimensions_map={"Environment": "production", "BusinessUnit": "ecommerce"},
                                statistic="Sum"
                            ),
                            cloudwatch.Metric(
                                namespace="Business/Metrics",
                                metric_name="ActiveUsers",
                                dimensions_map={"Environment": "production"},
                                statistic="Sum"
                            )
                        ],
                        period=Duration.minutes(5),
                        width=8,
                        height=6
                    ),
                    # Average Order Value
                    cloudwatch.GraphWidget(
                        title="Average Order Value",
                        left=[
                            cloudwatch.Metric(
                                namespace="Business/Metrics",
                                metric_name="AverageOrderValue",
                                dimensions_map={"Environment": "production", "BusinessUnit": "ecommerce"}
                            )
                        ],
                        period=Duration.minutes(5),
                        width=8,
                        height=6
                    )
                ],
                [
                    # API Performance Metrics
                    cloudwatch.GraphWidget(
                        title="API Performance Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="Business/Metrics",
                                metric_name="APIResponseTime",
                                dimensions_map={"Environment": "production", "Service": "api-gateway"}
                            ),
                            cloudwatch.Metric(
                                namespace="Business/Metrics",
                                metric_name="ErrorRate",
                                dimensions_map={"Environment": "production", "Service": "api-gateway"}
                            )
                        ],
                        period=Duration.minutes(5),
                        width=12,
                        height=6
                    ),
                    # Customer Satisfaction Metrics
                    cloudwatch.GraphWidget(
                        title="Customer Satisfaction Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="Business/Metrics",
                                metric_name="NPSScore",
                                dimensions_map={"Environment": "production"}
                            ),
                            cloudwatch.Metric(
                                namespace="Business/Metrics",
                                metric_name="SupportTicketVolume",
                                dimensions_map={"Environment": "production"}
                            )
                        ],
                        period=Duration.minutes(5),
                        width=12,
                        height=6
                    )
                ]
            ]
        )

    def _create_executive_dashboard(self) -> None:
        """Create executive summary dashboard."""
        dashboard = cloudwatch.Dashboard(
            self,
            "ExecutiveDashboard",
            dashboard_name=f"{self.project_name}-Executive",
            widgets=[
                [
                    # System Health Overview (24 Hours)
                    cloudwatch.GraphWidget(
                        title="System Health Overview (Last 24 Hours)",
                        left=[
                            cloudwatch.Metric(
                                namespace="Business/Health",
                                metric_name="CompositeHealthScore",
                                dimensions_map={"Environment": "production"}
                            ),
                            cloudwatch.Metric(
                                namespace="Infrastructure/Health",
                                metric_name="OverallInfrastructureHealth",
                                dimensions_map={"Environment": "production"}
                            )
                        ],
                        period=Duration.hours(1),
                        width=24,
                        height=6,
                        left_y_axis=cloudwatch.YAxisProps(min=0, max=100)
                    )
                ],
                [
                    # Revenue Trend (24H)
                    cloudwatch.SingleValueWidget(
                        title="Revenue Trend (24H)",
                        metrics=[
                            cloudwatch.Metric(
                                namespace="Business/Metrics",
                                metric_name="HourlyRevenue",
                                dimensions_map={"Environment": "production", "BusinessUnit": "ecommerce"},
                                statistic="Sum"
                            )
                        ],
                        period=Duration.hours(1),
                        width=8,
                        height=6,
                        set_period_to_time_range=True
                    ),
                    # Active Users (24H Avg)
                    cloudwatch.SingleValueWidget(
                        title="Active Users (24H Avg)",
                        metrics=[
                            cloudwatch.Metric(
                                namespace="Business/Metrics",
                                metric_name="ActiveUsers",
                                dimensions_map={"Environment": "production"}
                            )
                        ],
                        period=Duration.hours(1),
                        width=8,
                        height=6,
                        set_period_to_time_range=True
                    ),
                    # Customer Satisfaction (NPS)
                    cloudwatch.SingleValueWidget(
                        title="Customer Satisfaction (NPS)",
                        metrics=[
                            cloudwatch.Metric(
                                namespace="Business/Metrics",
                                metric_name="NPSScore",
                                dimensions_map={"Environment": "production"}
                            )
                        ],
                        period=Duration.hours(1),
                        width=8,
                        height=6,
                        set_period_to_time_range=True
                    )
                ],
                [
                    # Error Rate Trend
                    cloudwatch.GraphWidget(
                        title="Error Rate Trend",
                        left=[
                            cloudwatch.Metric(
                                namespace="Business/Metrics",
                                metric_name="ErrorRate",
                                dimensions_map={"Environment": "production", "Service": "api-gateway"}
                            )
                        ],
                        period=Duration.hours(1),
                        width=12,
                        height=6,
                        left_y_axis=cloudwatch.YAxisProps(min=0)
                    ),
                    # Monitoring System Health
                    cloudwatch.GraphWidget(
                        title="Monitoring System Health",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/Lambda",
                                metric_name="Errors",
                                dimensions_map={"FunctionName": f"{self.project_name}-business-metrics"},
                                statistic="Sum"
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/Lambda",
                                metric_name="Duration",
                                dimensions_map={"FunctionName": f"{self.project_name}-business-metrics"},
                                statistic="Sum"
                            )
                        ],
                        period=Duration.hours(1),
                        width=12,
                        height=6
                    )
                ]
            ]
        )

    def _create_operations_dashboard(self) -> None:
        """Create operational runbook dashboard."""
        dashboard = cloudwatch.Dashboard(
            self,
            "OperationsDashboard",
            dashboard_name=f"{self.project_name}-Operations",
            widgets=[
                [
                    # Recent Monitoring Errors (Log Widget)
                    cloudwatch.LogQueryWidget(
                        title="Recent Monitoring Errors",
                        log_groups=[
                            logs.LogGroup.from_log_group_name(
                                self,
                                "BusinessMetricsLogGroup",
                                f"/aws/lambda/{self.project_name}-business-metrics"
                            )
                        ],
                        query_lines=[
                            "fields @timestamp, @message",
                            "filter @message like /ERROR/",
                            "sort @timestamp desc",
                            "limit 20"
                        ],
                        width=24,
                        height=6
                    )
                ],
                [
                    # Monitoring Function Health
                    cloudwatch.GraphWidget(
                        title="Monitoring Function Health",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/Lambda",
                                metric_name="Invocations",
                                dimensions_map={"FunctionName": f"{self.project_name}-business-metrics"},
                                statistic="Sum"
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/Lambda",
                                metric_name="Errors",
                                dimensions_map={"FunctionName": f"{self.project_name}-business-metrics"},
                                statistic="Sum"
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/Lambda",
                                metric_name="Duration",
                                dimensions_map={"FunctionName": f"{self.project_name}-business-metrics"},
                                statistic="Sum"
                            )
                        ],
                        period=Duration.minutes(5),
                        width=8,
                        height=6
                    ),
                    # Alert Delivery Status
                    cloudwatch.GraphWidget(
                        title="Alert Delivery Status",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/SNS",
                                metric_name="NumberOfMessagesSent",
                                dimensions_map={"TopicName": f"{self.project_name}-critical"},
                                statistic="Sum"
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/SNS",
                                metric_name="NumberOfNotificationsFailed",
                                dimensions_map={"TopicName": f"{self.project_name}-critical"},
                                statistic="Sum"
                            )
                        ],
                        period=Duration.minutes(5),
                        width=8,
                        height=6
                    ),
                    # Cost Monitoring
                    cloudwatch.GraphWidget(
                        title="Cost Monitoring",
                        left=[
                            cloudwatch.Metric(
                                namespace="Cost/Management",
                                metric_name="DailyCost",
                                dimensions_map={"Environment": "production"}
                            ),
                            cloudwatch.Metric(
                                namespace="Cost/Management",
                                metric_name="CostTrend",
                                dimensions_map={"Environment": "production"}
                            )
                        ],
                        period=Duration.days(1),
                        width=8,
                        height=6
                    )
                ]
            ]
        )

    def _create_anomaly_detection(self) -> None:
        """Create anomaly detectors for key metrics."""
        # Revenue anomaly detection
        cloudwatch.CfnAnomalyDetector(
            self,
            "RevenueAnomalyDetector",
            namespace="Business/Metrics",
            metric_name="HourlyRevenue",
            dimensions=[
                {"name": "Environment", "value": "production"},
                {"name": "BusinessUnit", "value": "ecommerce"}
            ],
            stat="Average"
        )
        
        # Response time anomaly detection
        cloudwatch.CfnAnomalyDetector(
            self,
            "ResponseTimeAnomalyDetector",
            namespace="Business/Metrics",
            metric_name="APIResponseTime",
            dimensions=[
                {"name": "Environment", "value": "production"},
                {"name": "Service", "value": "api-gateway"}
            ],
            stat="Average"
        )
        
        # Error rate anomaly detection
        cloudwatch.CfnAnomalyDetector(
            self,
            "ErrorRateAnomalyDetector",
            namespace="Business/Metrics",
            metric_name="ErrorRate",
            dimensions=[
                {"name": "Environment", "value": "production"},
                {"name": "Service", "value": "api-gateway"}
            ],
            stat="Average"
        )
        
        # Infrastructure health anomaly detection
        cloudwatch.CfnAnomalyDetector(
            self,
            "InfrastructureHealthAnomalyDetector",
            namespace="Infrastructure/Health",
            metric_name="OverallInfrastructureHealth",
            dimensions=[
                {"name": "Environment", "value": "production"}
            ],
            stat="Average"
        )

    def _create_intelligent_alarms(self) -> None:
        """Create intelligent alarms with anomaly detection."""
        # Revenue anomaly alarm
        revenue_alarm = cloudwatch.Alarm(
            self,
            "RevenueAnomalyAlarm",
            alarm_name=f"{self.project_name}-revenue-anomaly",
            alarm_description="Revenue anomaly detected",
            metric=cloudwatch.Metric(
                namespace="Business/Metrics",
                metric_name="HourlyRevenue",
                dimensions_map={"Environment": "production", "BusinessUnit": "ecommerce"}
            ),
            threshold=1,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_LOWER_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        revenue_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.sns_topics['critical'])
        )
        
        # Response time anomaly alarm
        response_time_alarm = cloudwatch.Alarm(
            self,
            "ResponseTimeAnomalyAlarm",
            alarm_name=f"{self.project_name}-response-time-anomaly",
            alarm_description="API response time anomaly detected",
            metric=cloudwatch.Metric(
                namespace="Business/Metrics",
                metric_name="APIResponseTime",
                dimensions_map={"Environment": "production", "Service": "api-gateway"}
            ),
            threshold=1,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_UPPER_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        response_time_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.sns_topics['warning'])
        )
        
        # Infrastructure health threshold alarm
        infrastructure_alarm = cloudwatch.Alarm(
            self,
            "InfrastructureHealthAlarm",
            alarm_name=f"{self.project_name}-infrastructure-health-low",
            alarm_description="Infrastructure health score below threshold",
            metric=cloudwatch.Metric(
                namespace="Infrastructure/Health",
                metric_name="OverallInfrastructureHealth",
                dimensions_map={"Environment": "production"}
            ),
            threshold=80,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        infrastructure_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.sns_topics['critical'])
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        CfnOutput(
            self,
            "InfrastructureDashboardUrl",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.project_name}-Infrastructure",
            description="Infrastructure monitoring dashboard URL"
        )
        
        CfnOutput(
            self,
            "BusinessDashboardUrl",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.project_name}-Business",
            description="Business metrics dashboard URL"
        )
        
        CfnOutput(
            self,
            "ExecutiveDashboardUrl",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.project_name}-Executive",
            description="Executive summary dashboard URL"
        )
        
        CfnOutput(
            self,
            "OperationsDashboardUrl",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.project_name}-Operations",
            description="Operations runbook dashboard URL"
        )
        
        CfnOutput(
            self,
            "CriticalAlertsTopicArn",
            value=self.sns_topics['critical'].topic_arn,
            description="SNS topic ARN for critical alerts"
        )
        
        CfnOutput(
            self,
            "WarningAlertsTopicArn",
            value=self.sns_topics['warning'].topic_arn,
            description="SNS topic ARN for warning alerts"
        )
        
        CfnOutput(
            self,
            "InfoAlertsTopicArn",
            value=self.sns_topics['info'].topic_arn,
            description="SNS topic ARN for info alerts"
        )


class AdvancedMonitoringApp(cdk.App):
    """CDK application for advanced monitoring solution."""
    
    def __init__(self) -> None:
        super().__init__()
        
        # Get configuration from environment or use defaults
        project_name = os.environ.get("PROJECT_NAME", "advanced-monitoring")
        alert_email = os.environ.get("ALERT_EMAIL", "alerts@example.com")
        
        # Create the monitoring stack
        AdvancedMonitoringStack(
            self,
            "AdvancedMonitoringStack",
            project_name=project_name,
            alert_email=alert_email,
            description="Advanced Multi-Service Monitoring Dashboards with Custom Metrics and Anomaly Detection",
            tags={
                "Project": project_name,
                "Environment": "production",
                "Purpose": "monitoring",
                "Owner": "ops-team"
            }
        )


# Initialize the CDK app
app = AdvancedMonitoringApp()