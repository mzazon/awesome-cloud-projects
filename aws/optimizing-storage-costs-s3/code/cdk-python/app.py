#!/usr/bin/env python3
"""
CDK Application for S3 Storage Cost Optimization

This CDK application demonstrates comprehensive S3 storage cost optimization
using intelligent tiering, lifecycle policies, and monitoring capabilities.
"""

import os
from typing import List, Dict, Any

from aws_cdk import (
    App,
    Stack,
    Environment,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_cloudwatch as cloudwatch,
    aws_budgets as budgets,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_events as events,
    aws_events_targets as targets,
    aws_logs as logs,
)
from constructs import Construct


class StorageCostOptimizationStack(Stack):
    """
    Stack for S3 Storage Cost Optimization
    
    This stack creates:
    - S3 bucket with intelligent tiering and lifecycle policies
    - CloudWatch dashboard for monitoring
    - Cost budgets and alerts
    - Lambda function for automated recommendations
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        bucket_name: str,
        budget_limit: float = 50.0,
        notification_email: str = "admin@example.com",
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Store parameters
        self.bucket_name = bucket_name
        self.budget_limit = budget_limit
        self.notification_email = notification_email

        # Create S3 bucket with optimization features
        self.bucket = self._create_optimized_bucket()
        
        # Create CloudWatch dashboard
        self.dashboard = self._create_monitoring_dashboard()
        
        # Create cost budget
        self.budget = self._create_cost_budget()
        
        # Create Lambda function for recommendations
        self.recommendations_lambda = self._create_recommendations_lambda()
        
        # Create scheduled event to trigger recommendations
        self._create_recommendation_schedule()

        # Create outputs
        self._create_outputs()

    def _create_optimized_bucket(self) -> s3.Bucket:
        """Create S3 bucket with cost optimization features"""
        
        # Create the main bucket
        bucket = s3.Bucket(
            self,
            "OptimizedBucket",
            bucket_name=self.bucket_name,
            versioned=False,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Configure intelligent tiering
        bucket.add_intelligent_tiering_configuration(
            "EntireBucketIntelligentTiering",
            id="EntireBucketIntelligentTiering",
            status=s3.IntelligentTieringStatus.ENABLED,
            prefix="data/",
            archive_access_tier_time=Duration.days(1),
            deep_archive_access_tier_time=Duration.days(90),
        )

        # Configure lifecycle policies for different data types
        self._add_lifecycle_policies(bucket)

        # Configure storage analytics
        self._add_storage_analytics(bucket)

        return bucket

    def _add_lifecycle_policies(self, bucket: s3.Bucket) -> None:
        """Add lifecycle policies for different data access patterns"""
        
        # Policy for frequently accessed data
        bucket.add_lifecycle_rule(
            id="FrequentlyAccessedData",
            prefix="data/frequently-accessed/",
            enabled=True,
            transitions=[
                s3.Transition(
                    storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                    transition_after=Duration.days(30),
                ),
                s3.Transition(
                    storage_class=s3.StorageClass.GLACIER,
                    transition_after=Duration.days(90),
                ),
            ],
        )

        # Policy for infrequently accessed data
        bucket.add_lifecycle_rule(
            id="InfrequentlyAccessedData",
            prefix="data/infrequently-accessed/",
            enabled=True,
            transitions=[
                s3.Transition(
                    storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                    transition_after=Duration.days(1),
                ),
                s3.Transition(
                    storage_class=s3.StorageClass.GLACIER,
                    transition_after=Duration.days(30),
                ),
                s3.Transition(
                    storage_class=s3.StorageClass.DEEP_ARCHIVE,
                    transition_after=Duration.days(180),
                ),
            ],
        )

        # Policy for archive data
        bucket.add_lifecycle_rule(
            id="ArchiveData",
            prefix="data/archive/",
            enabled=True,
            transitions=[
                s3.Transition(
                    storage_class=s3.StorageClass.GLACIER,
                    transition_after=Duration.days(1),
                ),
                s3.Transition(
                    storage_class=s3.StorageClass.DEEP_ARCHIVE,
                    transition_after=Duration.days(30),
                ),
            ],
        )

    def _add_storage_analytics(self, bucket: s3.Bucket) -> None:
        """Add storage analytics configuration"""
        
        # Create analytics configuration for cost optimization insights
        analytics_config = s3.CfnBucket.AnalyticsConfigurationProperty(
            id="StorageAnalytics",
            prefix="data/",
            storage_class_analysis=s3.CfnBucket.StorageClassAnalysisProperty(
                data_export=s3.CfnBucket.DataExportProperty(
                    destination=s3.CfnBucket.DestinationProperty(
                        bucket_arn=bucket.bucket_arn,
                        format="CSV",
                        prefix="analytics-reports/",
                    ),
                    output_schema_version="V_1",
                )
            ),
        )

        # Add analytics configuration to bucket
        cfn_bucket = bucket.node.default_child
        cfn_bucket.add_property_override(
            "AnalyticsConfigurations", [analytics_config]
        )

    def _create_monitoring_dashboard(self) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for storage monitoring"""
        
        dashboard = cloudwatch.Dashboard(
            self,
            "StorageCostDashboard",
            dashboard_name=f"S3-Storage-Cost-Optimization-{self.bucket_name}",
        )

        # Create metrics for different storage classes
        storage_classes = [
            "StandardStorage",
            "StandardIAStorage", 
            "GlacierStorage",
            "DeepArchiveStorage",
        ]

        # Storage size metrics
        storage_metrics = []
        for storage_class in storage_classes:
            metric = cloudwatch.Metric(
                namespace="AWS/S3",
                metric_name="BucketSizeBytes",
                dimensions_map={
                    "BucketName": self.bucket_name,
                    "StorageType": storage_class,
                },
                statistic="Average",
                period=Duration.days(1),
            )
            storage_metrics.append(metric)

        # Add storage size widget
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title=f"S3 Storage by Class - {self.bucket_name}",
                left=storage_metrics,
                width=12,
                height=6,
            )
        )

        # Object count metric
        object_count_metric = cloudwatch.Metric(
            namespace="AWS/S3",
            metric_name="NumberOfObjects",
            dimensions_map={
                "BucketName": self.bucket_name,
                "StorageType": "AllStorageTypes",
            },
            statistic="Average",
            period=Duration.days(1),
        )

        # Add object count widget
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title=f"Total Objects in {self.bucket_name}",
                left=[object_count_metric],
                width=12,
                height=6,
            )
        )

        return dashboard

    def _create_cost_budget(self) -> budgets.CfnBudget:
        """Create cost budget for S3 storage monitoring"""
        
        budget = budgets.CfnBudget(
            self,
            "S3StorageBudget",
            budget=budgets.CfnBudget.BudgetDataProperty(
                budget_name=f"S3-Storage-Cost-Budget-{self.bucket_name}",
                budget_limit=budgets.CfnBudget.SpendProperty(
                    amount=self.budget_limit,
                    unit="USD",
                ),
                time_unit="MONTHLY",
                budget_type="COST",
                cost_filters=budgets.CfnBudget.CostFiltersProperty(
                    service=["Amazon Simple Storage Service"]
                ),
            ),
            notifications_with_subscribers=[
                budgets.CfnBudget.NotificationWithSubscribersProperty(
                    notification=budgets.CfnBudget.NotificationProperty(
                        notification_type="ACTUAL",
                        comparison_operator="GREATER_THAN",
                        threshold=80.0,
                        threshold_type="PERCENTAGE",
                    ),
                    subscribers=[
                        budgets.CfnBudget.SubscriberProperty(
                            subscription_type="EMAIL",
                            address=self.notification_email,
                        )
                    ],
                )
            ],
        )

        return budget

    def _create_recommendations_lambda(self) -> lambda_.Function:
        """Create Lambda function for automated cost optimization recommendations"""
        
        # Create IAM role for Lambda
        lambda_role = iam.Role(
            self,
            "RecommendationsLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
        )

        # Add S3 permissions
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:ListBucket",
                    "s3:GetObject",
                    "s3:HeadObject",
                    "s3:GetObjectAttributes",
                ],
                resources=[
                    self.bucket.bucket_arn,
                    f"{self.bucket.bucket_arn}/*",
                ],
            )
        )

        # Add CloudWatch permissions
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudwatch:GetMetricStatistics",
                    "cloudwatch:ListMetrics",
                ],
                resources=["*"],
            )
        )

        # Create Lambda function
        recommendations_function = lambda_.Function(
            self,
            "RecommendationsFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=lambda_role,
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.minutes(5),
            environment={
                "BUCKET_NAME": self.bucket_name,
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )

        return recommendations_function

    def _get_lambda_code(self) -> str:
        """Get the Lambda function code for cost optimization recommendations"""
        
        return """
import boto3
import json
import os
from datetime import datetime, timedelta
from typing import List, Dict, Any

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function to generate automated cost optimization recommendations
    """
    s3_client = boto3.client('s3')
    cloudwatch_client = boto3.client('cloudwatch')
    
    bucket_name = os.environ['BUCKET_NAME']
    
    recommendations = []
    
    try:
        # Get bucket contents
        response = s3_client.list_objects_v2(Bucket=bucket_name, MaxKeys=1000)
        
        for obj in response.get('Contents', []):
            last_modified = obj['LastModified']
            days_old = (datetime.now(last_modified.tzinfo) - last_modified).days
            
            if days_old > 30:
                # Check current storage class
                head_response = s3_client.head_object(Bucket=bucket_name, Key=obj['Key'])
                storage_class = head_response.get('StorageClass', 'STANDARD')
                
                if storage_class == 'STANDARD':
                    recommendations.append({
                        'type': 'transition_to_ia',
                        'object_key': obj['Key'],
                        'days_old': days_old,
                        'current_storage_class': storage_class,
                        'recommended_action': 'Move to Standard-IA for cost savings',
                        'estimated_savings_percent': 40
                    })
                elif storage_class == 'STANDARD_IA' and days_old > 90:
                    recommendations.append({
                        'type': 'transition_to_glacier',
                        'object_key': obj['Key'],
                        'days_old': days_old,
                        'current_storage_class': storage_class,
                        'recommended_action': 'Move to Glacier for additional cost savings',
                        'estimated_savings_percent': 70
                    })
        
        # Generate cost analysis
        cost_analysis = generate_cost_analysis(cloudwatch_client, bucket_name)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'bucket_name': bucket_name,
                'recommendations': recommendations,
                'total_recommendations': len(recommendations),
                'cost_analysis': cost_analysis,
                'timestamp': datetime.utcnow().isoformat()
            }, indent=2)
        }
        
    except Exception as e:
        print(f"Error generating recommendations: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }

def generate_cost_analysis(cloudwatch_client: Any, bucket_name: str) -> Dict[str, Any]:
    """Generate cost analysis for storage classes"""
    
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(days=30)
    
    storage_classes = ['StandardStorage', 'StandardIAStorage', 'GlacierStorage', 'DeepArchiveStorage']
    cost_analysis = {}
    
    # Approximate pricing per GB per month
    cost_per_gb = {
        'StandardStorage': 0.023,
        'StandardIAStorage': 0.0125,
        'GlacierStorage': 0.004,
        'DeepArchiveStorage': 0.00099
    }
    
    total_cost = 0
    total_size = 0
    
    for storage_class in storage_classes:
        try:
            response = cloudwatch_client.get_metric_statistics(
                Namespace='AWS/S3',
                MetricName='BucketSizeBytes',
                Dimensions=[
                    {'Name': 'BucketName', 'Value': bucket_name},
                    {'Name': 'StorageType', 'Value': storage_class}
                ],
                StartTime=start_time,
                EndTime=end_time,
                Period=86400,
                Statistics=['Average']
            )
            
            if response['Datapoints']:
                avg_size = sum(dp['Average'] for dp in response['Datapoints']) / len(response['Datapoints'])
                avg_size_gb = avg_size / (1024**3)
                estimated_cost = avg_size_gb * cost_per_gb.get(storage_class, 0)
                
                cost_analysis[storage_class] = {
                    'size_gb': round(avg_size_gb, 2),
                    'estimated_monthly_cost': round(estimated_cost, 2)
                }
                
                total_cost += estimated_cost
                total_size += avg_size_gb
                
        except Exception as e:
            print(f"Error getting metrics for {storage_class}: {str(e)}")
    
    cost_analysis['total'] = {
        'size_gb': round(total_size, 2),
        'estimated_monthly_cost': round(total_cost, 2)
    }
    
    return cost_analysis
"""

    def _create_recommendation_schedule(self) -> None:
        """Create scheduled event to trigger recommendations Lambda"""
        
        # Create EventBridge rule for weekly execution
        rule = events.Rule(
            self,
            "RecommendationSchedule",
            schedule=events.Schedule.rate(Duration.days(7)),
        )

        # Add Lambda target
        rule.add_target(
            targets.LambdaFunction(
                self.recommendations_lambda,
                event=events.RuleTargetInput.from_object({
                    "source": "eventbridge-schedule",
                    "bucket_name": self.bucket_name,
                }),
            )
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs"""
        
        CfnOutput(
            self,
            "BucketName",
            value=self.bucket.bucket_name,
            description="Name of the S3 bucket with cost optimization",
        )

        CfnOutput(
            self,
            "BucketArn",
            value=self.bucket.bucket_arn,
            description="ARN of the S3 bucket",
        )

        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="URL to the CloudWatch dashboard",
        )

        CfnOutput(
            self,
            "RecommendationsLambdaArn",
            value=self.recommendations_lambda.function_arn,
            description="ARN of the cost optimization recommendations Lambda function",
        )

        CfnOutput(
            self,
            "BudgetName",
            value=f"S3-Storage-Cost-Budget-{self.bucket_name}",
            description="Name of the cost budget for monitoring",
        )


def main() -> None:
    """Main function to create and deploy the CDK application"""
    
    app = App()
    
    # Get configuration from environment variables or use defaults
    bucket_name = app.node.try_get_context("bucket_name") or "storage-optimization-demo"
    budget_limit = float(app.node.try_get_context("budget_limit") or "50.0")
    notification_email = app.node.try_get_context("notification_email") or "admin@example.com"
    
    # Create the stack
    StorageCostOptimizationStack(
        app,
        "StorageCostOptimizationStack",
        bucket_name=bucket_name,
        budget_limit=budget_limit,
        notification_email=notification_email,
        env=Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
        ),
    )
    
    app.synth()


if __name__ == "__main__":
    main()