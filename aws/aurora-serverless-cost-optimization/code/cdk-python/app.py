#!/usr/bin/env python3
"""
Aurora Serverless v2 Cost Optimization Patterns - CDK Python Application

This CDK application implements intelligent auto-scaling patterns for Aurora Serverless v2
that automatically adjust capacity based on workload demands while incorporating cost 
optimization strategies including automatic pause/resume capabilities, intelligent capacity 
forecasting, and workload-aware scaling policies.

Key Features:
- Aurora Serverless v2 cluster with intelligent scaling configuration
- Lambda functions for cost-aware scaling and auto-pause/resume
- EventBridge schedules for automated scaling triggers  
- CloudWatch monitoring and cost alerting
- SNS notifications for scaling events and cost alerts
- AWS Budgets integration for proactive cost management

Author: AWS CDK Team
Version: 1.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    aws_rds as rds,
    aws_lambda as lambda_,
    aws_events as events,
    aws_events_targets as events_targets,
    aws_iam as iam,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
    aws_budgets as budgets,
    aws_ec2 as ec2,
    Tags,
    Duration,
    RemovalPolicy
)
from constructs import Construct


class AuroraServerlessV2CostOptimizationStack(cdk.Stack):
    """
    CDK Stack for Aurora Serverless v2 Cost Optimization Patterns
    
    This stack creates a complete Aurora Serverless v2 infrastructure with
    intelligent cost optimization capabilities including:
    - Multi-tier scaling configurations
    - Automated pause/resume for development environments
    - Cost monitoring and alerting
    - Performance insights and enhanced monitoring
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters
        self.cluster_name = f"aurora-sv2-cost-opt-{cdk.Aws.ACCOUNT_ID[:8]}"
        self.environment_type = self.node.try_get_context("environment") or "development"
        self.cost_alert_email = self.node.try_get_context("cost_alert_email") or "admin@example.com"
        
        # Create VPC if not provided
        self.vpc = self._create_or_get_vpc()
        
        # Create Aurora cluster parameter group
        self.parameter_group = self._create_cluster_parameter_group()
        
        # Create Aurora Serverless v2 cluster
        self.aurora_cluster = self._create_aurora_cluster()
        
        # Create database instances with different scaling patterns
        self.writer_instance = self._create_writer_instance()
        self.reader_instances = self._create_reader_instances()
        
        # Create Lambda execution role
        self.lambda_role = self._create_lambda_execution_role()
        
        # Create cost-aware scaling Lambda function
        self.cost_scaler_function = self._create_cost_aware_scaler()
        
        # Create auto-pause/resume Lambda function
        self.pause_resume_function = self._create_auto_pause_resume()
        
        # Create EventBridge schedules
        self._create_eventbridge_schedules()
        
        # Create SNS topic for cost alerts
        self.cost_alerts_topic = self._create_cost_alerts_topic()
        
        # Create CloudWatch alarms
        self._create_cloudwatch_alarms()
        
        # Create AWS Budget for cost monitoring
        self._create_cost_budget()
        
        # Add resource tags
        self._add_resource_tags()
        
        # Create stack outputs
        self._create_outputs()

    def _create_or_get_vpc(self) -> ec2.Vpc:
        """Create a new VPC or use existing VPC for Aurora deployment"""
        # Check if VPC ID is provided in context
        vpc_id = self.node.try_get_context("vpc_id")
        
        if vpc_id:
            # Use existing VPC
            return ec2.Vpc.from_lookup(self, "ExistingVpc", vpc_id=vpc_id)
        else:
            # Create new VPC with Aurora-optimized configuration
            return ec2.Vpc(
                self, "AuroraVpc",
                max_azs=3,
                nat_gateways=1,
                subnet_configuration=[
                    ec2.SubnetConfiguration(
                        name="Private",
                        subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                        cidr_mask=24
                    ),
                    ec2.SubnetConfiguration(
                        name="Public",
                        subnet_type=ec2.SubnetType.PUBLIC,
                        cidr_mask=24
                    ),
                    ec2.SubnetConfiguration(
                        name="Database",
                        subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                        cidr_mask=24
                    )
                ]
            )

    def _create_cluster_parameter_group(self) -> rds.ParameterGroup:
        """Create optimized cluster parameter group for cost and performance"""
        return rds.ParameterGroup(
            self, "ClusterParameterGroup",
            engine=rds.DatabaseClusterEngine.aurora_postgres(
                version=rds.AuroraPostgresEngineVersion.VER_15_4
            ),
            description="Aurora Serverless v2 cost optimization parameters",
            parameters={
                # Enable query statistics for intelligent scaling decisions
                "shared_preload_libraries": "pg_stat_statements",
                "track_activity_query_size": "2048",
                "log_statement": "ddl",
                "log_min_duration_statement": "1000",
                # Optimize for serverless scaling
                "max_connections": "LEAST({DBInstanceClassMemory/9531392},5000)",
                "random_page_cost": "1.1",
                "effective_cache_size": "{DBInstanceClassMemory*3/4}",
            }
        )

    def _create_aurora_cluster(self) -> rds.DatabaseCluster:
        """Create Aurora Serverless v2 cluster with optimized scaling settings"""
        
        # Create subnet group for Aurora cluster
        subnet_group = rds.SubnetGroup(
            self, "AuroraSubnetGroup",
            description="Subnet group for Aurora Serverless v2",
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_ISOLATED)
        )
        
        # Create security group for Aurora cluster
        security_group = ec2.SecurityGroup(
            self, "AuroraSecurityGroup",
            vpc=self.vpc,
            description="Security group for Aurora Serverless v2 cluster",
            allow_all_outbound=False
        )
        
        # Allow inbound connections on PostgreSQL port from VPC
        security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(5432),
            description="PostgreSQL access from VPC"
        )
        
        return rds.DatabaseCluster(
            self, "AuroraCluster",
            engine=rds.DatabaseClusterEngine.aurora_postgres(
                version=rds.AuroraPostgresEngineVersion.VER_15_4
            ),
            cluster_identifier=self.cluster_name,
            parameter_group=self.parameter_group,
            serverless_v2_min_capacity=0.5,
            serverless_v2_max_capacity=16,
            vpc=self.vpc,
            subnet_group=subnet_group,
            security_groups=[security_group],
            storage_encrypted=True,
            backup=rds.BackupProps(
                retention=cdk.Duration.days(7),
                preferred_window="03:00-04:00"
            ),
            preferred_maintenance_window="sun:04:00-sun:05:00",
            cloudwatch_logs_exports=["postgresql"],
            monitoring=rds.MonitoringConfig(
                enable_performance_insights=True,
                performance_insights_retention=rds.PerformanceInsightsRetention.DEFAULT
            ),
            deletion_protection=False,  # Enable for production
            removal_policy=RemovalPolicy.DESTROY  # Change to RETAIN for production
        )

    def _create_writer_instance(self) -> rds.DatabaseInstance:
        """Create the primary writer instance"""
        return rds.DatabaseInstance(
            self, "WriterInstance",
            engine=rds.DatabaseInstanceEngine.postgres(
                version=rds.PostgresEngineVersion.VER_15_4
            ),
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.SERVERLESS,
                ec2.InstanceSize.LARGE
            ),
            cluster=self.aurora_cluster,
            enable_performance_insights=True,
            performance_insights_retention=rds.PerformanceInsightsRetention.DEFAULT,
            monitoring_interval=Duration.seconds(60),
            auto_minor_version_upgrade=True,
            deletion_protection=False  # Enable for production
        )

    def _create_reader_instances(self) -> Dict[str, rds.DatabaseInstance]:
        """Create read replica instances with different scaling patterns"""
        
        # Standard scaling reader for production workloads
        reader_standard = rds.DatabaseInstance(
            self, "ReaderStandard",
            engine=rds.DatabaseInstanceEngine.postgres(
                version=rds.PostgresEngineVersion.VER_15_4
            ),
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.SERVERLESS,
                ec2.InstanceSize.LARGE
            ),
            cluster=self.aurora_cluster,
            enable_performance_insights=True,
            performance_insights_retention=rds.PerformanceInsightsRetention.DEFAULT,
            auto_minor_version_upgrade=True
        )
        
        # Aggressive scaling reader for development/analytics
        reader_aggressive = rds.DatabaseInstance(
            self, "ReaderAggressive", 
            engine=rds.DatabaseInstanceEngine.postgres(
                version=rds.PostgresEngineVersion.VER_15_4
            ),
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.SERVERLESS,
                ec2.InstanceSize.LARGE
            ),
            cluster=self.aurora_cluster,
            enable_performance_insights=True,
            performance_insights_retention=rds.PerformanceInsightsRetention.DEFAULT,
            auto_minor_version_upgrade=True
        )
        
        # Add tags to distinguish scaling tiers
        Tags.of(reader_standard).add("ScalingTier", "Standard")
        Tags.of(reader_aggressive).add("ScalingTier", "Aggressive")
        
        return {
            "standard": reader_standard,
            "aggressive": reader_aggressive
        }

    def _create_lambda_execution_role(self) -> iam.Role:
        """Create IAM role for Lambda functions with Aurora management permissions"""
        return iam.Role(
            self, "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "AuroraManagementPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "rds:DescribeDBClusters",
                                "rds:DescribeDBInstances", 
                                "rds:ModifyDBCluster",
                                "rds:ModifyDBInstance",
                                "rds:StartDBCluster",
                                "rds:StopDBCluster",
                                "cloudwatch:GetMetricStatistics",
                                "cloudwatch:PutMetricData",
                                "ce:GetUsageAndCosts",
                                "budgets:ViewBudget",
                                "sns:Publish"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )

    def _create_cost_aware_scaler(self) -> lambda_.Function:
        """Create Lambda function for intelligent cost-aware scaling"""
        
        # Read the cost-aware scaling function code
        cost_scaler_code = '''
import json
import boto3
from datetime import datetime, timedelta
import os

rds = boto3.client('rds')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    cluster_id = os.environ['CLUSTER_ID']
    
    try:
        # Get current cluster configuration
        cluster_response = rds.describe_db_clusters(DBClusterIdentifier=cluster_id)
        cluster = cluster_response['DBClusters'][0]
        
        current_min = cluster['ServerlessV2ScalingConfiguration']['MinCapacity']
        current_max = cluster['ServerlessV2ScalingConfiguration']['MaxCapacity']
        
        # Get CPU utilization and connection metrics
        cpu_metrics = get_cpu_utilization(cluster_id)
        connection_metrics = get_connection_count(cluster_id)
        
        # Calculate optimal scaling configuration
        new_min, new_max = calculate_optimal_scaling(
            cpu_metrics, connection_metrics, current_min, current_max
        )
        
        # Apply scaling if needed
        if new_min != current_min or new_max != current_max:
            update_scaling_configuration(cluster_id, new_min, new_max)
            send_scaling_notification(cluster_id, current_min, current_max, new_min, new_max)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'cluster': cluster_id,
                'previous_scaling': {'min': current_min, 'max': current_max},
                'new_scaling': {'min': new_min, 'max': new_max},
                'cpu_avg': cpu_metrics.get('average', 0),
                'connections_avg': connection_metrics.get('average', 0)
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}

def get_cpu_utilization(cluster_id):
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(hours=1)
    
    try:
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/RDS',
            MetricName='CPUUtilization',
            Dimensions=[{'Name': 'DBClusterIdentifier', 'Value': cluster_id}],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average', 'Maximum']
        )
        
        if response['Datapoints']:
            avg_cpu = sum(dp['Average'] for dp in response['Datapoints']) / len(response['Datapoints'])
            max_cpu = max(dp['Maximum'] for dp in response['Datapoints'])
            return {'average': avg_cpu, 'maximum': max_cpu}
    except Exception as e:
        print(f"Error getting CPU metrics: {e}")
    
    return {'average': 0, 'maximum': 0}

def get_connection_count(cluster_id):
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(hours=1)
    
    try:
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/RDS',
            MetricName='DatabaseConnections',
            Dimensions=[{'Name': 'DBClusterIdentifier', 'Value': cluster_id}],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average', 'Maximum']
        )
        
        if response['Datapoints']:
            avg_conn = sum(dp['Average'] for dp in response['Datapoints']) / len(response['Datapoints'])
            max_conn = max(dp['Maximum'] for dp in response['Datapoints'])
            return {'average': avg_conn, 'maximum': max_conn}
    except Exception as e:
        print(f"Error getting connection metrics: {e}")
    
    return {'average': 0, 'maximum': 0}

def calculate_optimal_scaling(cpu_metrics, conn_metrics, current_min, current_max):
    cpu_avg = cpu_metrics.get('average', 0)
    cpu_max = cpu_metrics.get('maximum', 0)
    conn_avg = conn_metrics.get('average', 0)
    
    # Determine optimal minimum capacity
    if cpu_avg < 20 and conn_avg < 5:
        new_min = 0.5  # Very low utilization - aggressive scale down
    elif cpu_avg < 40 and conn_avg < 20:
        new_min = max(0.5, current_min - 0.5)  # Low utilization - moderate scale down
    elif cpu_avg > 70 or conn_avg > 50:
        new_min = min(8, current_min + 1)  # High utilization - scale up minimum
    else:
        new_min = current_min  # Maintain current minimum
    
    # Determine optimal maximum capacity
    if cpu_max > 80 or conn_avg > 80:
        new_max = min(32, current_max + 4)  # High peak usage - increase max capacity
    elif cpu_max < 50 and conn_avg < 30:
        new_max = max(4, current_max - 2)  # Low peak usage - reduce max capacity
    else:
        new_max = current_max  # Maintain current maximum
    
    # Ensure minimum <= maximum
    new_min = min(new_min, new_max)
    
    return new_min, new_max

def update_scaling_configuration(cluster_id, min_capacity, max_capacity):
    rds.modify_db_cluster(
        DBClusterIdentifier=cluster_id,
        ServerlessV2ScalingConfiguration={
            'MinCapacity': min_capacity,
            'MaxCapacity': max_capacity
        },
        ApplyImmediately=True
    )

def send_scaling_notification(cluster_id, old_min, old_max, new_min, new_max):
    # Calculate cost impact estimate
    cost_impact = calculate_cost_impact(old_min, old_max, new_min, new_max)
    
    # Send custom metric to CloudWatch
    try:
        cloudwatch.put_metric_data(
            Namespace='Aurora/CostOptimization',
            MetricData=[
                {
                    'MetricName': 'ScalingAdjustment',
                    'Dimensions': [
                        {'Name': 'ClusterIdentifier', 'Value': cluster_id},
                        {'Name': 'ScalingType', 'Value': 'MinCapacity'}
                    ],
                    'Value': new_min - old_min,
                    'Unit': 'Count'
                },
                {
                    'MetricName': 'EstimatedCostImpact', 
                    'Dimensions': [{'Name': 'ClusterIdentifier', 'Value': cluster_id}],
                    'Value': cost_impact,
                    'Unit': 'None'
                }
            ]
        )
    except Exception as e:
        print(f"Error sending metrics: {e}")

def calculate_cost_impact(old_min, old_max, new_min, new_max):
    # Simplified cost calculation (ACU hours per month * cost per ACU hour)
    hours_per_month = 730
    cost_per_acu_hour = 0.12  # Approximate cost per ACU hour
    
    # Estimate average usage (simplified model)
    old_avg_usage = (old_min + old_max) / 2
    new_avg_usage = (new_min + new_max) / 2
    
    old_cost = old_avg_usage * hours_per_month * cost_per_acu_hour
    new_cost = new_avg_usage * hours_per_month * cost_per_acu_hour
    
    return new_cost - old_cost
'''
        
        return lambda_.Function(
            self, "CostAwareScaler",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(cost_scaler_code),
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=256,
            environment={
                "CLUSTER_ID": self.aurora_cluster.cluster_identifier
            },
            description="Intelligent cost-aware scaling for Aurora Serverless v2"
        )

    def _create_auto_pause_resume(self) -> lambda_.Function:
        """Create Lambda function for auto-pause/resume functionality"""
        
        # Read the auto-pause/resume function code
        pause_resume_code = '''
import json
import boto3
from datetime import datetime, time, timedelta
import os

rds = boto3.client('rds')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    cluster_id = os.environ['CLUSTER_ID']
    environment = os.environ.get('ENVIRONMENT', 'development')
    
    try:
        # Determine action based on current time and environment
        current_time = datetime.utcnow().time()
        action = determine_action(current_time, environment)
        
        if action == 'pause':
            result = pause_cluster_if_idle(cluster_id)
        elif action == 'resume':
            result = resume_cluster_if_needed(cluster_id)
        else:
            result = {'action': 'no_action', 'reason': 'Outside operating hours'}
        
        # Record action in CloudWatch
        record_pause_resume_metrics(cluster_id, action, result)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'cluster': cluster_id,
                'environment': environment,
                'action': action,
                'result': result,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}

def determine_action(current_time, environment):
    # Define operating hours based on environment
    if environment == 'development':
        # Development: operate 8 AM - 8 PM UTC
        start_hour = time(8, 0)
        end_hour = time(20, 0)
    elif environment == 'staging':
        # Staging: operate 6 AM - 10 PM UTC
        start_hour = time(6, 0)
        end_hour = time(22, 0)
    else:
        # Production: always on
        return 'monitor'
    
    if start_hour <= current_time <= end_hour:
        return 'resume'
    else:
        return 'pause'

def pause_cluster_if_idle(cluster_id):
    # Check if cluster is idle before pausing
    if is_cluster_idle(cluster_id):
        try:
            # Scale down to minimum (0.5 ACU) effectively pausing
            rds.modify_db_cluster(
                DBClusterIdentifier=cluster_id,
                ServerlessV2ScalingConfiguration={
                    'MinCapacity': 0.5,
                    'MaxCapacity': 1
                },
                ApplyImmediately=True
            )
            return {'action': 'paused', 'reason': 'Low activity detected during off-hours'}
        except Exception as e:
            return {'action': 'error', 'reason': f'Failed to pause: {str(e)}'}
    else:
        return {'action': 'not_paused', 'reason': 'Active connections detected'}

def resume_cluster_if_needed(cluster_id):
    try:
        # Get current scaling configuration
        cluster_response = rds.describe_db_clusters(DBClusterIdentifier=cluster_id)
        cluster = cluster_response['DBClusters'][0]
        
        current_min = cluster['ServerlessV2ScalingConfiguration']['MinCapacity']
        current_max = cluster['ServerlessV2ScalingConfiguration']['MaxCapacity']
        
        # Resume to normal operating capacity if currently paused
        if current_min <= 0.5 and current_max <= 1:
            rds.modify_db_cluster(
                DBClusterIdentifier=cluster_id,
                ServerlessV2ScalingConfiguration={
                    'MinCapacity': 0.5,
                    'MaxCapacity': 8
                },
                ApplyImmediately=True
            )
            return {'action': 'resumed', 'reason': 'Operating hours started'}
        else:
            return {'action': 'already_active', 'reason': 'Cluster already in active state'}
            
    except Exception as e:
        return {'action': 'error', 'reason': f'Failed to resume: {str(e)}'}

def is_cluster_idle(cluster_id):
    # Check for database connections in the last 30 minutes
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(minutes=30)
    
    try:
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/RDS',
            MetricName='DatabaseConnections',
            Dimensions=[{'Name': 'DBClusterIdentifier', 'Value': cluster_id}],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Maximum']
        )
        
        if response['Datapoints']:
            max_connections = max(dp['Maximum'] for dp in response['Datapoints'])
            return max_connections <= 1  # Only system connections
    except Exception as e:
        print(f"Error checking cluster idle status: {e}")
    
    return True  # No data means idle

def record_pause_resume_metrics(cluster_id, action, result):
    metric_value = 1 if result.get('action') in ['paused', 'resumed'] else 0
    
    try:
        cloudwatch.put_metric_data(
            Namespace='Aurora/CostOptimization',
            MetricData=[
                {
                    'MetricName': 'AutoPauseResumeActions',
                    'Dimensions': [
                        {'Name': 'ClusterIdentifier', 'Value': cluster_id},
                        {'Name': 'Action', 'Value': action}
                    ],
                    'Value': metric_value,
                    'Unit': 'Count'
                }
            ]
        )
    except Exception as e:
        print(f"Error recording metrics: {e}")
'''
        
        return lambda_.Function(
            self, "AutoPauseResume",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(pause_resume_code),
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=256,
            environment={
                "CLUSTER_ID": self.aurora_cluster.cluster_identifier,
                "ENVIRONMENT": self.environment_type
            },
            description="Auto-pause/resume for Aurora Serverless v2 cost optimization"
        )

    def _create_eventbridge_schedules(self) -> None:
        """Create EventBridge schedules for automated scaling triggers"""
        
        # Schedule for cost-aware scaling (every 15 minutes)
        cost_scaling_rule = events.Rule(
            self, "CostAwareScalingRule",
            schedule=events.Schedule.rate(Duration.minutes(15)),
            description="Trigger cost-aware scaling for Aurora Serverless v2"
        )
        cost_scaling_rule.add_target(events_targets.LambdaFunction(self.cost_scaler_function))
        
        # Schedule for auto-pause/resume (every hour)
        pause_resume_rule = events.Rule(
            self, "AutoPauseResumeRule", 
            schedule=events.Schedule.rate(Duration.hours(1)),
            description="Trigger auto-pause/resume for Aurora Serverless v2"
        )
        pause_resume_rule.add_target(events_targets.LambdaFunction(self.pause_resume_function))

    def _create_cost_alerts_topic(self) -> sns.Topic:
        """Create SNS topic for cost alerts and notifications"""
        topic = sns.Topic(
            self, "CostAlertsTopic",
            display_name="Aurora Serverless v2 Cost Alerts",
            description="Notifications for Aurora Serverless v2 cost optimization events"
        )
        
        # Add email subscription if email is provided
        if self.cost_alert_email != "admin@example.com":
            topic.add_subscription(
                sns.Subscription(
                    self, "EmailSubscription",
                    topic=topic,
                    endpoint=self.cost_alert_email,
                    protocol=sns.SubscriptionProtocol.EMAIL
                )
            )
        
        return topic

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for cost monitoring and alerting"""
        
        # Alarm for high ACU usage
        high_acu_alarm = cloudwatch.Alarm(
            self, "HighACUUsageAlarm",
            metric=cloudwatch.Metric(
                namespace="AWS/RDS",
                metric_name="ServerlessDatabaseCapacity",
                dimensions_map={
                    "DBClusterIdentifier": self.aurora_cluster.cluster_identifier
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=12,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=3,
            alarm_description="Alert when Aurora Serverless v2 ACU usage is high"
        )
        high_acu_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.cost_alerts_topic)
        )
        
        # Alarm for sustained high capacity
        sustained_high_alarm = cloudwatch.Alarm(
            self, "SustainedHighCapacityAlarm",
            metric=cloudwatch.Metric(
                namespace="AWS/RDS",
                metric_name="ServerlessDatabaseCapacity", 
                dimensions_map={
                    "DBClusterIdentifier": self.aurora_cluster.cluster_identifier
                },
                statistic="Average",
                period=Duration.minutes(30)
            ),
            threshold=8,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=4,
            alarm_description="Alert when capacity remains high for extended period"
        )
        sustained_high_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.cost_alerts_topic)
        )

    def _create_cost_budget(self) -> None:
        """Create AWS Budget for Aurora cost monitoring"""
        
        # Create budget for Aurora Serverless v2 costs
        budget = budgets.CfnBudget(
            self, "AuroraServerlessV2Budget",
            budget=budgets.CfnBudget.BudgetDataProperty(
                budget_name="Aurora-Serverless-v2-Monthly",
                budget_limit=budgets.CfnBudget.SpendProperty(
                    amount=200.0,
                    unit="USD"
                ),
                time_unit="MONTHLY",
                budget_type="COST",
                cost_filters=budgets.CfnBudget.CostFiltersProperty(
                    service=["Amazon Relational Database Service"],
                    tag_key=["Application"],
                    tag_value=["AuroraServerlessV2"]
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
                            subscription_type="SNS",
                            address=self.cost_alerts_topic.topic_arn
                        )
                    ]
                ),
                budgets.CfnBudget.NotificationWithSubscribersProperty(
                    notification=budgets.CfnBudget.NotificationProperty(
                        notification_type="FORECASTED",
                        comparison_operator="GREATER_THAN", 
                        threshold=100,
                        threshold_type="PERCENTAGE"
                    ),
                    subscribers=[
                        budgets.CfnBudget.SubscriberProperty(
                            subscription_type="SNS",
                            address=self.cost_alerts_topic.topic_arn
                        )
                    ]
                )
            ]
        )

    def _add_resource_tags(self) -> None:
        """Add consistent tags to all resources for cost allocation and management"""
        Tags.of(self).add("Application", "AuroraServerlessV2")
        Tags.of(self).add("Environment", self.environment_type)
        Tags.of(self).add("CostCenter", "Database")
        Tags.of(self).add("Project", "CostOptimization")
        Tags.of(self).add("ManagedBy", "CDK")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information"""
        
        cdk.CfnOutput(
            self, "ClusterIdentifier",
            value=self.aurora_cluster.cluster_identifier,
            description="Aurora Serverless v2 Cluster Identifier"
        )
        
        cdk.CfnOutput(
            self, "ClusterEndpoint",
            value=self.aurora_cluster.cluster_endpoint.hostname,
            description="Aurora Serverless v2 Cluster Endpoint"
        )
        
        cdk.CfnOutput(
            self, "ClusterReaderEndpoint",
            value=self.aurora_cluster.cluster_read_endpoint.hostname,
            description="Aurora Serverless v2 Reader Endpoint"
        )
        
        cdk.CfnOutput(
            self, "CostAwareScalerFunction",
            value=self.cost_scaler_function.function_name,
            description="Cost-Aware Scaling Lambda Function Name"
        )
        
        cdk.CfnOutput(
            self, "AutoPauseResumeFunction", 
            value=self.pause_resume_function.function_name,
            description="Auto-Pause/Resume Lambda Function Name"
        )
        
        cdk.CfnOutput(
            self, "CostAlertsTopicArn",
            value=self.cost_alerts_topic.topic_arn,
            description="SNS Topic ARN for Cost Alerts"
        )


class AuroraServerlessV2CostOptimizationApp(cdk.App):
    """CDK Application for Aurora Serverless v2 Cost Optimization"""
    
    def __init__(self):
        super().__init__()
        
        # Create the main stack
        AuroraServerlessV2CostOptimizationStack(
            self, "AuroraServerlessV2CostOptimizationStack",
            description="Aurora Serverless v2 Cost Optimization Patterns with intelligent auto-scaling",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
            )
        )


# Create and synthesize the CDK application
if __name__ == "__main__":
    app = AuroraServerlessV2CostOptimizationApp()
    app.synth()