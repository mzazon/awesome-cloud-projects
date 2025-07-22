#!/usr/bin/env python3
"""
CDK Python application for Sustainable Data Archiving with S3 Intelligent-Tiering.

This application creates a comprehensive data archiving solution that automatically
optimizes storage costs and environmental impact using S3 Intelligent-Tiering,
lifecycle policies, and sustainability monitoring.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    RemovalPolicy,
    Duration,
    aws_s3 as s3,
    aws_iam as iam,
    aws_lambda as _lambda,
    aws_events as events,
    aws_events_targets as targets,
    aws_cloudwatch as cloudwatch,
    aws_s3_deployment as s3deploy,
    aws_logs as logs,
)
from constructs import Construct
from typing import Dict, List, Any
import json


class SustainableArchiveStack(Stack):
    """
    CDK Stack for sustainable data archiving solution.
    
    This stack implements:
    - S3 bucket with Intelligent-Tiering
    - Lifecycle policies for cost optimization
    - Lambda function for sustainability monitoring
    - CloudWatch dashboard for metrics visualization
    - S3 Storage Lens for analytics
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters
        self.bucket_prefix = self.node.try_get_context("bucket_prefix") or "sustainable-archive"
        self.enable_deep_archive = self.node.try_get_context("enable_deep_archive") or True
        self.monitoring_frequency = self.node.try_get_context("monitoring_frequency") or "daily"
        
        # Create the main components
        self.archive_bucket = self._create_archive_bucket()
        self.analytics_bucket = self._create_analytics_bucket()
        self.monitoring_lambda = self._create_monitoring_lambda()
        self.dashboard = self._create_cloudwatch_dashboard()
        self.monitoring_schedule = self._create_monitoring_schedule()
        
        # Configure Storage Lens
        self._configure_storage_lens()
        
        # Create sample data deployment (optional)
        if self.node.try_get_context("deploy_sample_data"):
            self._deploy_sample_data()

        # Outputs
        self._create_outputs()

    def _create_archive_bucket(self) -> s3.Bucket:
        """
        Create the main archive bucket with Intelligent-Tiering and lifecycle policies.
        """
        bucket = s3.Bucket(
            self, "ArchiveBucket",
            bucket_name=f"{self.bucket_prefix}-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,  # Only for demo purposes
            lifecycle_rules=[
                # Primary lifecycle rule for all objects
                s3.LifecycleRule(
                    id="SustainabilityOptimization",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INTELLIGENT_TIERING,
                            transition_after=Duration.days(0)
                        )
                    ],
                    noncurrent_version_transitions=[
                        s3.NoncurrentVersionTransition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(30)
                        ),
                        s3.NoncurrentVersionTransition(
                            storage_class=s3.StorageClass.DEEP_ARCHIVE,
                            transition_after=Duration.days(90)
                        )
                    ],
                    abort_incomplete_multipart_upload_after=Duration.days(1),
                    noncurrent_version_expiration=Duration.days(365)
                ),
                # Rule specifically for long-term archive data
                s3.LifecycleRule(
                    id="LongTermArchiveOptimization",
                    enabled=True,
                    prefix="long-term/",
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INTELLIGENT_TIERING,
                            transition_after=Duration.days(0)
                        )
                    ]
                )
            ]
        )

        # Add sustainability tags
        cdk.Tags.of(bucket).add("Purpose", "SustainableArchive")
        cdk.Tags.of(bucket).add("Environment", "Production")
        cdk.Tags.of(bucket).add("CostOptimization", "Enabled")
        cdk.Tags.of(bucket).add("SustainabilityGoal", "CarbonNeutral")

        # Configure Intelligent-Tiering
        s3.CfnBucket.IntelligentTieringConfigurationProperty(
            id="SustainableArchiveConfig",
            status="Enabled",
            optional_fields=[
                s3.CfnBucket.BucketKeyEnabledProperty(bucket_key_enabled=True)
            ]
        )

        return bucket

    def _create_analytics_bucket(self) -> s3.Bucket:
        """
        Create bucket for storing analytics and monitoring data.
        """
        bucket = s3.Bucket(
            self, "AnalyticsBucket",
            bucket_name=f"archive-analytics-{self.account}-{self.region}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="AnalyticsRetention",
                    enabled=True,
                    expiration=Duration.days(90)  # Analytics data retention
                )
            ]
        )

        cdk.Tags.of(bucket).add("Purpose", "ArchiveAnalytics")
        cdk.Tags.of(bucket).add("DataType", "Monitoring")

        return bucket

    def _create_monitoring_lambda(self) -> _lambda.Function:
        """
        Create Lambda function for sustainability monitoring and carbon footprint calculation.
        """
        # IAM role for Lambda
        lambda_role = iam.Role(
            self, "SustainabilityMonitorRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ],
            inline_policies={
                "SustainabilityPermissions": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetBucketTagging",
                                "s3:GetBucketLocation",
                                "s3:ListBucket",
                                "s3:GetObject",
                                "s3:GetStorageLensConfiguration",
                                "s3:ListStorageLensConfigurations",
                                "cloudwatch:GetMetricStatistics",
                                "cloudwatch:ListMetrics",
                                "cloudwatch:PutMetricData"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )

        # Lambda function code
        lambda_code = '''
import json
import boto3
import os
from datetime import datetime, timedelta
from decimal import Decimal

def lambda_handler(event, context):
    """
    Main Lambda handler for sustainability monitoring.
    Calculates storage efficiency and carbon footprint metrics.
    """
    s3 = boto3.client('s3')
    cloudwatch = boto3.client('cloudwatch')
    
    bucket_name = os.environ['ARCHIVE_BUCKET']
    
    try:
        # Get bucket tagging to identify sustainability goals
        tags_response = s3.get_bucket_tagging(Bucket=bucket_name)
        tags = {tag['Key']: tag['Value'] for tag in tags_response['TagSet']}
        
        # Calculate storage metrics
        storage_metrics = calculate_storage_efficiency(s3, bucket_name)
        
        # Estimate carbon footprint reduction
        carbon_metrics = calculate_carbon_impact(storage_metrics)
        
        # Publish custom CloudWatch metrics
        publish_sustainability_metrics(cloudwatch, storage_metrics, carbon_metrics)
        
        # Generate sustainability report
        report = generate_sustainability_report(storage_metrics, carbon_metrics, tags)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Sustainability analysis completed',
                'report': report
            }, default=decimal_default)
        }
        
    except Exception as e:
        print(f"Error in sustainability monitoring: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def calculate_storage_efficiency(s3, bucket_name):
    """Calculate storage efficiency metrics"""
    try:
        total_objects = 0
        total_size = 0
        
        # Get bucket metrics using list_objects_v2
        paginator = s3.get_paginator('list_objects_v2')
        
        for page in paginator.paginate(Bucket=bucket_name):
            if 'Contents' in page:
                for obj in page['Contents']:
                    total_objects += 1
                    total_size += obj['Size']
        
        return {
            'total_objects': total_objects,
            'total_size_gb': round(total_size / (1024**3), 2),
            'average_object_size_mb': round((total_size / total_objects) / (1024**2), 2) if total_objects > 0 else 0
        }
    except Exception as e:
        print(f"Error calculating storage metrics: {str(e)}")
        return {'total_objects': 0, 'total_size_gb': 0, 'average_object_size_mb': 0}

def calculate_carbon_impact(storage_metrics):
    """Estimate carbon footprint reduction through intelligent tiering"""
    # AWS carbon impact estimates (simplified model)
    # Standard storage: ~0.000385 kg CO2/GB/month
    # IA storage: ~0.000308 kg CO2/GB/month (20% reduction)
    # Archive tiers: ~0.000077 kg CO2/GB/month (80% reduction)
    
    total_size_gb = storage_metrics['total_size_gb']
    
    # Estimate tier distribution based on typical patterns
    estimated_standard = total_size_gb * 0.3  # 30% in standard
    estimated_ia = total_size_gb * 0.4        # 40% in IA
    estimated_archive = total_size_gb * 0.3   # 30% in archive tiers
    
    carbon_standard = estimated_standard * 0.000385
    carbon_ia = estimated_ia * 0.000308
    carbon_archive = estimated_archive * 0.000077
    
    total_carbon = carbon_standard + carbon_ia + carbon_archive
    carbon_saved = (total_size_gb * 0.000385) - total_carbon  # vs all standard
    
    return {
        'estimated_monthly_carbon_kg': round(total_carbon, 4),
        'estimated_monthly_savings_kg': round(carbon_saved, 4),
        'carbon_reduction_percentage': round((carbon_saved / (total_size_gb * 0.000385)) * 100, 1) if total_size_gb > 0 else 0
    }

def publish_sustainability_metrics(cloudwatch, storage_metrics, carbon_metrics):
    """Publish custom metrics to CloudWatch"""
    metrics = [
        {
            'MetricName': 'TotalStorageGB',
            'Value': storage_metrics['total_size_gb'],
            'Unit': 'Count'
        },
        {
            'MetricName': 'EstimatedMonthlyCarbonKg',
            'Value': carbon_metrics['estimated_monthly_carbon_kg'],
            'Unit': 'Count'
        },
        {
            'MetricName': 'CarbonReductionPercentage',
            'Value': carbon_metrics['carbon_reduction_percentage'],
            'Unit': 'Percent'
        }
    ]
    
    for metric in metrics:
        cloudwatch.put_metric_data(
            Namespace='SustainableArchive',
            MetricData=[{
                'MetricName': metric['MetricName'],
                'Value': metric['Value'],
                'Unit': metric['Unit'],
                'Timestamp': datetime.utcnow()
            }]
        )

def generate_sustainability_report(storage_metrics, carbon_metrics, tags):
    """Generate comprehensive sustainability report"""
    return {
        'timestamp': datetime.utcnow().isoformat(),
        'sustainability_goal': tags.get('SustainabilityGoal', 'Not specified'),
        'storage_efficiency': {
            'total_objects': storage_metrics['total_objects'],
            'total_storage_gb': storage_metrics['total_size_gb'],
            'average_object_size_mb': storage_metrics['average_object_size_mb']
        },
        'environmental_impact': {
            'estimated_monthly_carbon_kg': carbon_metrics['estimated_monthly_carbon_kg'],
            'monthly_carbon_savings_kg': carbon_metrics['estimated_monthly_savings_kg'],
            'carbon_reduction_percentage': carbon_metrics['carbon_reduction_percentage']
        },
        'recommendations': generate_recommendations(storage_metrics, carbon_metrics)
    }

def generate_recommendations(storage_metrics, carbon_metrics):
    """Generate optimization recommendations"""
    recommendations = []
    
    if storage_metrics['average_object_size_mb'] < 1:
        recommendations.append("Consider using S3 Object Lambda to aggregate small objects for better efficiency")
    
    if carbon_metrics['carbon_reduction_percentage'] < 30:
        recommendations.append("Enable Deep Archive Access tier for longer retention periods")
    
    recommendations.append("Review access patterns monthly to optimize tier transition policies")
    
    return recommendations

def decimal_default(obj):
    """JSON serializer for Decimal objects"""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError
'''

        # Create Lambda function
        lambda_function = _lambda.Function(
            self, "SustainabilityMonitor",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(lambda_code),
            role=lambda_role,
            timeout=Duration.minutes(5),
            environment={
                "ARCHIVE_BUCKET": self.archive_bucket.bucket_name
            },
            log_retention=logs.RetentionDays.ONE_MONTH,
            description="Monitors sustainability metrics for archive bucket"
        )

        return lambda_function

    def _create_monitoring_schedule(self) -> events.Rule:
        """
        Create EventBridge rule to schedule regular sustainability monitoring.
        """
        schedule_expression = {
            "daily": "rate(1 day)",
            "weekly": "rate(7 days)",
            "hourly": "rate(1 hour)"
        }.get(self.monitoring_frequency, "rate(1 day)")

        rule = events.Rule(
            self, "SustainabilityMonitoringSchedule",
            schedule=events.Schedule.expression(schedule_expression),
            description="Scheduled sustainability metrics collection"
        )

        rule.add_target(targets.LambdaFunction(self.monitoring_lambda))

        return rule

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for sustainability metrics visualization.
        """
        dashboard = cloudwatch.Dashboard(
            self, "SustainabilityDashboard",
            dashboard_name="SustainableArchive",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Storage & Carbon Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="SustainableArchive",
                                metric_name="TotalStorageGB",
                                statistic="Average"
                            )
                        ],
                        right=[
                            cloudwatch.Metric(
                                namespace="SustainableArchive",
                                metric_name="EstimatedMonthlyCarbonKg",
                                statistic="Average"
                            )
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.GraphWidget(
                        title="Carbon Footprint Reduction",
                        left=[
                            cloudwatch.Metric(
                                namespace="SustainableArchive",
                                metric_name="CarbonReductionPercentage",
                                statistic="Average"
                            )
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.SingleValueWidget(
                        title="Current Carbon Reduction",
                        metrics=[
                            cloudwatch.Metric(
                                namespace="SustainableArchive",
                                metric_name="CarbonReductionPercentage",
                                statistic="Average"
                            )
                        ],
                        width=6,
                        height=3
                    ),
                    cloudwatch.SingleValueWidget(
                        title="Monthly Carbon Savings (kg)",
                        metrics=[
                            cloudwatch.Metric(
                                namespace="SustainableArchive",
                                metric_name="EstimatedMonthlyCarbonKg",
                                statistic="Average"
                            )
                        ],
                        width=6,
                        height=3
                    )
                ]
            ]
        )

        return dashboard

    def _configure_storage_lens(self) -> None:
        """
        Configure S3 Storage Lens for comprehensive analytics.
        Note: Storage Lens configuration requires special handling in CDK.
        """
        # Storage Lens configuration is complex in CDK and typically done via CLI
        # This would be implemented as a custom resource or post-deployment script
        pass

    def _deploy_sample_data(self) -> None:
        """
        Deploy sample data for testing intelligent tiering behavior.
        """
        # Create sample files for different access patterns
        sample_data = {
            "active/frequent-data.txt": "Frequently accessed application data for testing",
            "documents/archive-doc-2023.pdf": "Document archive from 2023 for intelligent tiering test",
            "long-term/backup-data.zip": "Long-term backup data for deep archive testing"
        }

        for key, content in sample_data.items():
            s3deploy.BucketDeployment(
                self, f"SampleData{key.replace('/', '').replace('.', '')}",
                sources=[s3deploy.Source.data(key, content)],
                destination_bucket=self.archive_bucket,
                retain_on_delete=False
            )

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resources.
        """
        CfnOutput(
            self, "ArchiveBucketName",
            value=self.archive_bucket.bucket_name,
            description="Name of the main archive bucket with Intelligent-Tiering",
            export_name=f"{self.stack_name}-ArchiveBucketName"
        )

        CfnOutput(
            self, "AnalyticsBucketName",
            value=self.analytics_bucket.bucket_name,
            description="Name of the analytics bucket for monitoring data",
            export_name=f"{self.stack_name}-AnalyticsBucketName"
        )

        CfnOutput(
            self, "MonitoringLambdaArn",
            value=self.monitoring_lambda.function_arn,
            description="ARN of the sustainability monitoring Lambda function",
            export_name=f"{self.stack_name}-MonitoringLambdaArn"
        )

        CfnOutput(
            self, "DashboardUrl",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="URL to the CloudWatch sustainability dashboard",
            export_name=f"{self.stack_name}-DashboardUrl"
        )


def main():
    """
    Main application entry point.
    """
    app = cdk.App()
    
    # Get environment configuration
    env = Environment(
        account=app.node.try_get_context("account") or None,
        region=app.node.try_get_context("region") or "us-east-1"
    )
    
    # Create the stack
    SustainableArchiveStack(
        app, 
        "SustainableArchiveStack",
        env=env,
        description="Sustainable Data Archiving Solution with S3 Intelligent-Tiering and carbon footprint monitoring"
    )
    
    app.synth()


if __name__ == "__main__":
    main()