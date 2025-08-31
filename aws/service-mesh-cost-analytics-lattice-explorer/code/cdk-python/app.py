#!/usr/bin/env python3
"""
AWS CDK Python application for VPC Lattice Cost Analytics Platform.

This application creates a comprehensive cost analytics platform that combines 
VPC Lattice monitoring capabilities with Cost Explorer APIs to provide 
service mesh cost insights and optimization recommendations.

Architecture Components:
- Lambda function for cost data processing
- S3 bucket for analytics data storage
- CloudWatch dashboard for visualization
- EventBridge automation for scheduled analysis
- VPC Lattice resources for demonstration
- IAM roles with least-privilege permissions

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    CfnOutput,
    Tags,
    aws_lambda as _lambda,
    aws_s3 as s3,
    aws_iam as iam,
    aws_events as events,
    aws_events_targets as targets,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    aws_vpclattice as vpclattice,
    aws_sns as sns,
    aws_kms as kms,
)
from constructs import Construct


class VpcLatticeCostAnalyticsStack(Stack):
    """
    CDK Stack for VPC Lattice Cost Analytics Platform.
    
    This stack implements a serverless cost analytics solution that:
    - Processes VPC Lattice cost data using Lambda and Cost Explorer API
    - Stores analytics data in S3 with proper encryption and lifecycle policies
    - Provides real-time visualization through CloudWatch dashboards
    - Automates daily cost analysis using EventBridge scheduling
    - Includes sample VPC Lattice resources for testing and demonstration
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource naming
        random_suffix = self.node.try_get_context("randomSuffix") or "demo"
        
        # Core configuration
        self.project_name = "lattice-cost-analytics"
        self.function_name = f"lattice-cost-processor-{random_suffix}"
        self.bucket_name = f"lattice-analytics-{random_suffix}"
        
        # Create KMS key for encryption
        self.encryption_key = self._create_encryption_key()
        
        # Create S3 bucket for analytics data storage
        self.analytics_bucket = self._create_analytics_bucket()
        
        # Create IAM role for Lambda function
        self.lambda_role = self._create_lambda_execution_role()
        
        # Create Lambda function for cost processing
        self.cost_processor = self._create_cost_processor_lambda()
        
        # Create sample VPC Lattice resources
        self.lattice_resources = self._create_sample_lattice_resources(random_suffix)
        
        # Create CloudWatch dashboard
        self.dashboard = self._create_cost_analytics_dashboard()
        
        # Create EventBridge rule for automation
        self.scheduler_rule = self._create_automated_scheduler()
        
        # Create SNS topic for notifications
        self.notification_topic = self._create_notification_topic()
        
        # Apply common tags to all resources
        self._apply_common_tags()
        
        # Create stack outputs
        self._create_outputs()

    def _create_encryption_key(self) -> kms.Key:
        """Create KMS key for encrypting analytics data."""
        key = kms.Key(
            self, "AnalyticsEncryptionKey",
            description="KMS key for VPC Lattice cost analytics data encryption",
            enable_key_rotation=True,
            removal_policy=cdk.RemovalPolicy.DESTROY,  # For demo purposes
        )
        
        key.add_alias("alias/lattice-cost-analytics")
        
        return key

    def _create_analytics_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for storing cost analytics data with proper 
        security configurations and lifecycle management.
        """
        bucket = s3.Bucket(
            self, "AnalyticsBucket",
            bucket_name=self.bucket_name,
            encryption=s3.BucketEncryption.KMS,
            encryption_key=self.encryption_key,
            versioned=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=cdk.RemovalPolicy.DESTROY,  # For demo purposes
            auto_delete_objects=True,  # For demo purposes
            enforce_ssl=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ArchiveOldReports",
                    enabled=True,
                    expiration=Duration.days(90),
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(60)
                        )
                    ]
                )
            ]
        )
        
        # Create folder structure
        s3.Deployment(
            self, "BucketStructure",
            sources=[s3.Source.data("cost-reports/", "# Cost Reports Directory\n")],
            destination_bucket=bucket,
            destination_key_prefix="cost-reports/"
        )
        
        s3.Deployment(
            self, "MetricsStructure", 
            sources=[s3.Source.data("metrics-data/", "# Metrics Data Directory\n")],
            destination_bucket=bucket,
            destination_key_prefix="metrics-data/"
        )
        
        return bucket

    def _create_lambda_execution_role(self) -> iam.Role:
        """
        Create IAM role for Lambda function with least-privilege permissions
        for Cost Explorer, CloudWatch, VPC Lattice, and S3 access.
        """
        role = iam.Role(
            self, "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for VPC Lattice cost analytics Lambda",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )
        
        # Cost Explorer permissions
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "ce:GetCostAndUsage",
                "ce:GetUsageReport", 
                "ce:ListCostCategoryDefinitions",
                "ce:GetCostCategories",
                "ce:GetRecommendations"
            ],
            resources=["*"]
        ))
        
        # CloudWatch permissions
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "cloudwatch:GetMetricStatistics",
                "cloudwatch:GetMetricData",
                "cloudwatch:ListMetrics",
                "cloudwatch:PutMetricData"
            ],
            resources=["*"]
        ))
        
        # VPC Lattice permissions
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "vpc-lattice:GetService",
                "vpc-lattice:GetServiceNetwork",
                "vpc-lattice:ListServices", 
                "vpc-lattice:ListServiceNetworks"
            ],
            resources=["*"]
        ))
        
        # S3 permissions for analytics bucket
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject"
            ],
            resources=[f"{self.analytics_bucket.bucket_arn}/*"]
        ))
        
        # KMS permissions for bucket encryption
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "kms:Decrypt",
                "kms:GenerateDataKey"
            ],
            resources=[self.encryption_key.key_arn]
        ))
        
        return role

    def _create_cost_processor_lambda(self) -> _lambda.Function:
        """
        Create Lambda function that processes VPC Lattice cost data
        and generates analytics reports.
        """
        
        # Lambda function code for cost analytics processing
        lambda_code = '''
import json
import boto3
import datetime
from decimal import Decimal
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process VPC Lattice cost analytics by combining Cost Explorer data
    with CloudWatch metrics to generate comprehensive cost insights.
    """
    try:
        # Initialize AWS clients
        ce_client = boto3.client('ce')
        cw_client = boto3.client('cloudwatch')
        s3_client = boto3.client('s3')
        lattice_client = boto3.client('vpc-lattice')
        
        bucket_name = os.environ['BUCKET_NAME']
        
        # Calculate date range for cost analysis (last 7 days)
        end_date = datetime.datetime.now().date()
        start_date = end_date - datetime.timedelta(days=7)
        
        logger.info(f"Processing cost analytics for period: {start_date} to {end_date}")
        
        # Get VPC Lattice service networks
        service_networks_response = lattice_client.list_service_networks()
        service_networks = service_networks_response.get('items', [])
        
        logger.info(f"Found {len(service_networks)} VPC Lattice service networks")
        
        # Query Cost Explorer for VPC Lattice related costs
        cost_response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='DAILY',
            Metrics=['BlendedCost', 'UsageQuantity'],
            GroupBy=[
                {'Type': 'DIMENSION', 'Key': 'SERVICE'},
                {'Type': 'DIMENSION', 'Key': 'REGION'}
            ],
            Filter={
                'Or': [
                    {
                        'Dimensions': {
                            'Key': 'SERVICE',
                            'Values': ['Amazon Virtual Private Cloud']
                        }
                    },
                    {
                        'Dimensions': {
                            'Key': 'SERVICE', 
                            'Values': ['VPC Lattice', 'Amazon VPC Lattice']
                        }
                    }
                ]
            }
        )
        
        # Process cost data
        cost_data = {}
        for result in cost_response['ResultsByTime']:
            date = result['TimePeriod']['Start']
            for group in result['Groups']:
                service = group['Keys'][0]
                region = group['Keys'][1]
                amount = float(group['Metrics']['BlendedCost']['Amount'])
                
                cost_data[f"{date}_{service}_{region}"] = {
                    'date': date,
                    'service': service,
                    'region': region,
                    'cost': amount,
                    'currency': group['Metrics']['BlendedCost']['Unit']
                }
        
        logger.info(f"Processed {len(cost_data)} cost data points")
        
        # Get VPC Lattice CloudWatch metrics
        metrics_data = {}
        total_requests = 0
        
        for network in service_networks:
            network_id = network['id']
            network_name = network.get('name', network_id)
            
            try:
                # Get request count metrics for service network
                metric_response = cw_client.get_metric_statistics(
                    Namespace='AWS/VpcLattice',
                    MetricName='TotalRequestCount',
                    Dimensions=[
                        {'Name': 'ServiceNetwork', 'Value': network_id}
                    ],
                    StartTime=datetime.datetime.combine(start_date, datetime.time.min),
                    EndTime=datetime.datetime.combine(end_date, datetime.time.min),
                    Period=86400,  # Daily
                    Statistics=['Sum']
                )
                
                network_requests = sum([point['Sum'] for point in metric_response['Datapoints']])
                total_requests += network_requests
                
                metrics_data[network_id] = {
                    'network_name': network_name,
                    'request_count': network_requests
                }
                
                logger.info(f"Network {network_name}: {network_requests} requests")
                
            except Exception as e:
                logger.warning(f"Could not retrieve metrics for network {network_id}: {str(e)}")
                metrics_data[network_id] = {
                    'network_name': network_name,
                    'request_count': 0
                }
        
        # Calculate summary metrics
        total_cost = sum([item['cost'] for item in cost_data.values()])
        cost_per_request = (total_cost / total_requests) if total_requests > 0 else 0
        
        # Create comprehensive analytics report
        analytics_report = {
            'report_date': end_date.isoformat(),
            'time_period': {
                'start': start_date.isoformat(),
                'end': end_date.isoformat()
            },
            'cost_data': cost_data,
            'metrics_data': metrics_data,
            'summary': {
                'total_cost': total_cost,
                'total_requests': total_requests,
                'cost_per_request': cost_per_request,
                'active_service_networks': len(service_networks)
            },
            'optimization_insights': generate_optimization_insights(
                total_cost, total_requests, len(service_networks)
            )
        }
        
        # Store analytics report in S3
        report_key = f"cost-reports/{end_date.isoformat()}_lattice_analytics.json"
        s3_client.put_object(
            Bucket=bucket_name,
            Key=report_key,
            Body=json.dumps(analytics_report, indent=2, default=str),
            ContentType='application/json',
            ServerSideEncryption='aws:kms'
        )
        
        logger.info(f"Stored analytics report: s3://{bucket_name}/{report_key}")
        
        # Publish CloudWatch custom metrics
        cw_client.put_metric_data(
            Namespace='VPCLattice/CostAnalytics',
            MetricData=[
                {
                    'MetricName': 'TotalCost',
                    'Value': total_cost,
                    'Unit': 'None',
                    'Timestamp': datetime.datetime.now()
                },
                {
                    'MetricName': 'TotalRequests',
                    'Value': total_requests,
                    'Unit': 'Count',
                    'Timestamp': datetime.datetime.now()
                },
                {
                    'MetricName': 'CostPerRequest',
                    'Value': cost_per_request,
                    'Unit': 'None',
                    'Timestamp': datetime.datetime.now()
                },
                {
                    'MetricName': 'ActiveServiceNetworks',
                    'Value': len(service_networks),
                    'Unit': 'Count',
                    'Timestamp': datetime.datetime.now()
                }
            ]
        )
        
        logger.info("Published custom CloudWatch metrics")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost analytics completed successfully',
                'report_location': f's3://{bucket_name}/{report_key}',
                'summary': analytics_report['summary']
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing cost analytics: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def generate_optimization_insights(total_cost, total_requests, network_count):
    """Generate optimization recommendations based on cost and usage data."""
    insights = []
    
    if total_cost > 100:
        insights.append("Consider reviewing VPC Lattice usage patterns for cost optimization opportunities")
    
    if total_requests == 0 and network_count > 0:
        insights.append("Unused service networks detected - consider removing to reduce costs")
    
    if total_requests > 0:
        cost_per_request = total_cost / total_requests
        if cost_per_request > 0.01:
            insights.append("High cost per request detected - review traffic routing efficiency")
    
    if network_count > 5:
        insights.append("Consider consolidating service networks to reduce management overhead")
    
    return insights
'''
        
        function = _lambda.Function(
            self, "CostProcessorFunction",
            function_name=self.function_name,
            runtime=_lambda.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=512,
            environment={
                "BUCKET_NAME": self.analytics_bucket.bucket_name
            },
            description="VPC Lattice cost analytics processor",
            log_retention=logs.RetentionDays.ONE_MONTH,
            tracing=_lambda.Tracing.ACTIVE,
            environment_encryption=self.encryption_key
        )
        
        return function

    def _create_sample_lattice_resources(self, suffix: str) -> Dict[str, Any]:
        """
        Create sample VPC Lattice resources for testing cost analytics.
        These resources generate metrics that can be analyzed by the platform.
        """
        
        # Create VPC Lattice service network
        service_network = vpclattice.CfnServiceNetwork(
            self, "CostDemoServiceNetwork",
            name=f"cost-demo-network-{suffix}",
            auth_type="AWS_IAM",
            tags=[
                cdk.CfnTag(key="Project", value=self.project_name),
                cdk.CfnTag(key="Environment", value="demo"),
                cdk.CfnTag(key="CostCenter", value="engineering")
            ]
        )
        
        # Create sample service
        service = vpclattice.CfnService(
            self, "CostDemoService",
            name=f"demo-service-{suffix}",
            auth_type="AWS_IAM",
            tags=[
                cdk.CfnTag(key="Project", value=self.project_name),
                cdk.CfnTag(key="ServiceType", value="demo")
            ]
        )
        
        # Associate service with service network
        service_association = vpclattice.CfnServiceNetworkServiceAssociation(
            self, "ServiceNetworkAssociation",
            service_network_identifier=service_network.attr_id,
            service_identifier=service.attr_id
        )
        
        # Ensure proper dependency
        service_association.add_dependency(service_network)
        service_association.add_dependency(service)
        
        return {
            "service_network": service_network,
            "service": service,
            "service_association": service_association
        }

    def _create_cost_analytics_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for visualizing VPC Lattice cost metrics
        and traffic patterns in real-time.
        """
        
        dashboard = cloudwatch.Dashboard(
            self, "CostAnalyticsDashboard",
            dashboard_name=f"VPCLattice-CostAnalytics-{self.node.try_get_context('randomSuffix') or 'demo'}",
            default_interval=Duration.hours(24)
        )
        
        # Cost and traffic overview widget
        cost_traffic_widget = cloudwatch.GraphWidget(
            title="VPC Lattice Cost and Traffic Overview",
            left=[
                cloudwatch.Metric(
                    namespace="VPCLattice/CostAnalytics",
                    metric_name="TotalCost",
                    statistic="Sum",
                    period=Duration.days(1)
                )
            ],
            right=[
                cloudwatch.Metric(
                    namespace="VPCLattice/CostAnalytics", 
                    metric_name="TotalRequests",
                    statistic="Sum",
                    period=Duration.days(1)
                )
            ],
            width=12,
            height=6
        )
        
        # Cost efficiency widget
        efficiency_widget = cloudwatch.GraphWidget(
            title="Cost Per Request Efficiency",
            left=[
                cloudwatch.Metric(
                    namespace="VPCLattice/CostAnalytics",
                    metric_name="CostPerRequest",
                    statistic="Average",
                    period=Duration.days(1)
                )
            ],
            width=12,
            height=6
        )
        
        # Service network metrics widget (if we have lattice resources)
        if hasattr(self, 'lattice_resources'):
            service_network_widget = cloudwatch.GraphWidget(
                title="VPC Lattice Service Network Traffic Metrics",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/VpcLattice",
                        metric_name="TotalRequestCount",
                        dimensions_map={
                            "ServiceNetwork": self.lattice_resources["service_network"].attr_id
                        },
                        statistic="Sum",
                        period=Duration.minutes(5)
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/VpcLattice",
                        metric_name="ActiveConnectionCount",
                        dimensions_map={
                            "ServiceNetwork": self.lattice_resources["service_network"].attr_id
                        },
                        statistic="Sum",
                        period=Duration.minutes(5)
                    )
                ],
                width=24,
                height=6
            )
        else:
            service_network_widget = cloudwatch.TextWidget(
                markdown="## VPC Lattice Service Network Metrics\n\nNo active service networks found for monitoring.",
                width=24,
                height=6
            )
        
        # Add widgets to dashboard
        dashboard.add_widgets(cost_traffic_widget, efficiency_widget)
        dashboard.add_widgets(service_network_widget)
        
        return dashboard

    def _create_automated_scheduler(self) -> events.Rule:
        """
        Create EventBridge rule for automated daily cost analysis execution.
        """
        rule = events.Rule(
            self, "CostAnalysisScheduler",
            rule_name=f"lattice-cost-analysis-{self.node.try_get_context('randomSuffix') or 'demo'}",
            schedule=events.Schedule.rate(Duration.days(1)),
            description="Daily VPC Lattice cost analysis trigger",
            enabled=True
        )
        
        # Add Lambda function as target
        rule.add_target(targets.LambdaFunction(self.cost_processor))
        
        return rule

    def _create_notification_topic(self) -> sns.Topic:
        """
        Create SNS topic for cost analytics notifications and alerts.
        """
        topic = sns.Topic(
            self, "CostAnalyticsNotifications",
            topic_name=f"lattice-cost-alerts-{self.node.try_get_context('randomSuffix') or 'demo'}",
            display_name="VPC Lattice Cost Analytics Alerts",
            kms_master_key=self.encryption_key
        )
        
        # Allow Lambda to publish to the topic
        topic.grant_publish(self.lambda_role)
        
        return topic

    def _apply_common_tags(self) -> None:
        """Apply consistent tags across all stack resources."""
        Tags.of(self).add("Project", self.project_name)
        Tags.of(self).add("Environment", "demo")
        Tags.of(self).add("CostCenter", "engineering")
        Tags.of(self).add("Owner", "platform-team")
        Tags.of(self).add("ServiceMesh", "vpc-lattice")
        Tags.of(self).add("ManagedBy", "aws-cdk")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        
        CfnOutput(
            self, "AnalyticsBucketName",
            value=self.analytics_bucket.bucket_name,
            description="S3 bucket name for cost analytics data storage",
            export_name=f"{self.stack_name}-AnalyticsBucketName"
        )
        
        CfnOutput(
            self, "CostProcessorFunctionName",
            value=self.cost_processor.function_name,
            description="Lambda function name for cost processing",
            export_name=f"{self.stack_name}-CostProcessorFunctionName"
        )
        
        CfnOutput(
            self, "DashboardURL",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="CloudWatch dashboard URL for cost analytics visualization",
            export_name=f"{self.stack_name}-DashboardURL"
        )
        
        if hasattr(self, 'lattice_resources'):
            CfnOutput(
                self, "ServiceNetworkId",
                value=self.lattice_resources["service_network"].attr_id,
                description="VPC Lattice service network ID for demo resources",
                export_name=f"{self.stack_name}-ServiceNetworkId"
            )
        
        CfnOutput(
            self, "NotificationTopicArn",
            value=self.notification_topic.topic_arn,
            description="SNS topic ARN for cost analytics notifications",
            export_name=f"{self.stack_name}-NotificationTopicArn"
        )


class VpcLatticeCostAnalyticsApp(cdk.App):
    """
    CDK Application for VPC Lattice Cost Analytics Platform.
    
    This application demonstrates best practices for:
    - Serverless cost analytics architecture
    - AWS service integration patterns
    - Security and encryption configurations
    - Automated monitoring and alerting
    - Infrastructure as Code with CDK
    """
    
    def __init__(self):
        super().__init__()
        
        # Get configuration from context or environment
        account = self.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT")
        region = self.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION")
        
        # Generate random suffix for unique naming
        import secrets
        random_suffix = self.node.try_get_context("randomSuffix") or secrets.token_hex(3)
        self.node.set_context("randomSuffix", random_suffix)
        
        # Create the main stack
        VpcLatticeCostAnalyticsStack(
            self, "VpcLatticeCostAnalyticsStack",
            env=cdk.Environment(account=account, region=region),
            description="VPC Lattice Cost Analytics Platform - Serverless cost monitoring and optimization for service mesh architectures",
            stack_name=f"VpcLatticeCostAnalytics-{random_suffix}"
        )


# Create and run the CDK application
app = VpcLatticeCostAnalyticsApp()
app.synth()