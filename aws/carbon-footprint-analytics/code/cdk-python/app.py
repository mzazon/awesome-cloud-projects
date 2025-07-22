#!/usr/bin/env python3
"""
AWS CDK Python Application for Intelligent Sustainability Dashboards.

This application creates an automated sustainability intelligence platform using
AWS Customer Carbon Footprint Tool, Amazon QuickSight, AWS Cost Explorer, and
AWS Lambda for sustainability analytics and visualization.
"""

import os
from typing import Dict, Any
import aws_cdk as cdk
from constructs import Construct
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_lambda as _lambda,
    aws_iam as iam,
    aws_events as events,
    aws_events_targets as targets,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cw_actions,
    CfnOutput,
    Tags
)


class SustainabilityDashboardStack(Stack):
    """
    CDK Stack for AWS Sustainability Dashboard Infrastructure.
    
    Creates a complete sustainability intelligence platform including:
    - S3 data lake for sustainability analytics
    - Lambda function for automated data processing
    - EventBridge scheduling for regular data collection
    - CloudWatch monitoring and alerting
    - SNS notifications for sustainability thresholds
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[-6:].lower()

        # Create S3 bucket for sustainability data lake
        self.sustainability_bucket = s3.Bucket(
            self, "SustainabilityDataLake",
            bucket_name=f"sustainability-analytics-{unique_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="AnalyticsDataTransition",
                    enabled=True,
                    prefix="sustainability-analytics/",
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.STANDARD_INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.DEEP_ARCHIVE,
                            transition_after=Duration.days(365)
                        )
                    ]
                )
            ]
        )

        # Create IAM role for Lambda function
        self.lambda_role = iam.Role(
            self, "SustainabilityAnalyticsRole",
            role_name=f"SustainabilityAnalyticsRole-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ]
        )

        # Create custom policy for sustainability analytics
        sustainability_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "ce:GetCostAndUsage",
                        "ce:GetUsageForecast", 
                        "ce:GetCostCategories",
                        "ce:GetDimensionValues",
                        "ce:GetRightsizingRecommendation",
                        "cur:DescribeReportDefinitions",
                        "cur:GetClassicReport",
                        "cloudwatch:PutMetricData"
                    ],
                    resources=["*"]
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:GetObject",
                        "s3:PutObject",
                        "s3:ListBucket"
                    ],
                    resources=[
                        self.sustainability_bucket.bucket_arn,
                        f"{self.sustainability_bucket.bucket_arn}/*"
                    ]
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "quicksight:CreateDataSet",
                        "quicksight:UpdateDataSet",
                        "quicksight:CreateDashboard", 
                        "quicksight:UpdateDashboard",
                        "quicksight:DescribeDataSet"
                    ],
                    resources=["*"]
                )
            ]
        )

        self.lambda_role.attach_inline_policy(
            iam.Policy(
                self, "SustainabilityAnalyticsPolicy",
                document=sustainability_policy
            )
        )

        # Create Lambda function for sustainability data processing
        self.sustainability_processor = _lambda.Function(
            self, "SustainabilityDataProcessor",
            function_name=f"sustainability-data-processor-{unique_suffix}",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="sustainability_processor.lambda_handler",
            code=_lambda.Code.from_inline(self._get_lambda_code()),
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=512,
            environment={
                "BUCKET_NAME": self.sustainability_bucket.bucket_name,
                "AWS_REGION": self.region
            },
            description="Processes AWS sustainability and cost data for analytics"
        )

        # Create EventBridge rule for monthly data collection
        self.data_collection_rule = events.Rule(
            self, "SustainabilityDataCollection",
            rule_name=f"sustainability-data-collection-{unique_suffix}",
            description="Monthly sustainability data collection and processing",
            schedule=events.Schedule.rate(Duration.days(30))
        )

        # Add Lambda as target for EventBridge rule
        self.data_collection_rule.add_target(
            targets.LambdaFunction(
                self.sustainability_processor,
                event=events.RuleTargetInput.from_object({
                    "bucket_name": self.sustainability_bucket.bucket_name,
                    "trigger_source": "eventbridge"
                })
            )
        )

        # Create SNS topic for sustainability alerts
        self.alerts_topic = sns.Topic(
            self, "SustainabilityAlerts",
            topic_name=f"sustainability-alerts-{unique_suffix}",
            display_name="Sustainability Analytics Alerts"
        )

        # Create CloudWatch alarms for monitoring
        self._create_cloudwatch_alarms()

        # Create S3 manifest file for QuickSight integration
        self._create_quicksight_manifest()

        # Add resource tags for cost allocation and governance
        self._add_resource_tags()

        # Create stack outputs
        self._create_outputs()

    def _get_lambda_code(self) -> str:
        """
        Returns the Lambda function code for sustainability data processing.
        
        Returns:
            str: The Lambda function source code
        """
        return '''
import json
import boto3
import pandas as pd
from datetime import datetime, timedelta
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process sustainability and cost data to create integrated analytics.
    AWS Customer Carbon Footprint Tool data is retrieved monthly with a 3-month delay.
    This function correlates cost data with carbon footprint insights.
    """
    
    try:
        # Initialize AWS clients
        ce_client = boto3.client('ce')
        s3_client = boto3.client('s3')
        cloudwatch = boto3.client('cloudwatch')
        
        # Get environment variables
        bucket_name = event.get('bucket_name', os.environ.get('BUCKET_NAME'))
        
        # Calculate date range (last 6 months for comprehensive analysis)
        end_date = datetime.now()
        start_date = end_date - timedelta(days=180)
        
        logger.info(f"Processing sustainability data from {start_date.date()} to {end_date.date()}")
        
        # Fetch cost data from Cost Explorer
        cost_response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='MONTHLY',
            Metrics=['UnblendedCost'],
            GroupBy=[
                {'Type': 'DIMENSION', 'Key': 'SERVICE'},
                {'Type': 'DIMENSION', 'Key': 'REGION'}
            ]
        )
        
        # Get cost optimization recommendations
        rightsizing_response = ce_client.get_rightsizing_recommendation(
            Service='AmazonEC2',
            Configuration={
                'BenefitsConsidered': True,
                'RecommendationTarget': 'CROSS_INSTANCE_FAMILY'
            }
        )
        
        # Process cost data for sustainability correlation
        processed_data = {
            'timestamp': datetime.now().isoformat(),
            'data_collection_metadata': {
                'aws_region': os.environ.get('AWS_REGION'),
                'processing_date': datetime.now().isoformat(),
                'analysis_period_days': 180,
                'data_source': 'AWS Cost Explorer API'
            },
            'cost_data': cost_response['ResultsByTime'],
            'optimization_recommendations': rightsizing_response,
            'sustainability_metrics': {
                'cost_optimization_opportunities': len(rightsizing_response.get('RightsizingRecommendations', [])),
                'total_services_analyzed': len(set([
                    group['Keys'][0] for result in cost_response['ResultsByTime']
                    for group in result.get('Groups', [])
                ])),
                'carbon_footprint_notes': 'AWS Customer Carbon Footprint Tool data available with 3-month delay via billing console'
            }
        }
        
        # Save processed data to S3 with date partitioning
        s3_key = f"sustainability-analytics/{datetime.now().strftime('%Y/%m/%d')}/processed_data_{datetime.now().strftime('%H%M%S')}.json"
        
        s3_client.put_object(
            Bucket=bucket_name,
            Key=s3_key,
            Body=json.dumps(processed_data, default=str, indent=2),
            ContentType='application/json',
            Metadata={
                'processing-date': datetime.now().isoformat(),
                'data-type': 'sustainability-analytics'
            }
        )
        
        # Send custom metric to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='SustainabilityAnalytics',
            MetricData=[
                {
                    'MetricName': 'DataProcessingSuccess',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'FunctionName',
                            'Value': context.function_name
                        }
                    ]
                }
            ]
        )
        
        logger.info(f"Successfully processed sustainability data and saved to {s3_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Sustainability data processed successfully',
                's3_location': f's3://{bucket_name}/{s3_key}',
                'metrics': processed_data['sustainability_metrics']
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing sustainability data: {str(e)}")
        
        # Send error metric to CloudWatch
        try:
            cloudwatch = boto3.client('cloudwatch')
            cloudwatch.put_metric_data(
                Namespace='SustainabilityAnalytics',
                MetricData=[
                    {
                        'MetricName': 'DataProcessingError',
                        'Value': 1,
                        'Unit': 'Count'
                    }
                ]
            )
        except Exception as cw_error:
            logger.error(f"Error sending CloudWatch metric: {str(cw_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
'''

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for sustainability monitoring."""
        # Alarm for Lambda processing failures
        lambda_error_alarm = cloudwatch.Alarm(
            self, "SustainabilityDataProcessingFailure",
            alarm_name=f"SustainabilityDataProcessingFailure-{self.node.addr[-6:].lower()}",
            alarm_description="Alert when sustainability data processing fails",
            metric=self.sustainability_processor.metric_errors(
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD
        )

        # Alarm for successful data processing monitoring
        data_processing_success_alarm = cloudwatch.Alarm(
            self, "SustainabilityDataProcessingSuccess",
            alarm_name=f"SustainabilityDataProcessingSuccess-{self.node.addr[-6:].lower()}",
            alarm_description="Monitor successful sustainability data processing",
            metric=cloudwatch.Metric(
                namespace="SustainabilityAnalytics",
                metric_name="DataProcessingSuccess",
                statistic="Sum",
                period=Duration.hours(24)
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.BREACHING
        )

        # Add SNS actions to alarms
        lambda_error_alarm.add_alarm_action(
            cw_actions.SnsAction(self.alerts_topic)
        )
        data_processing_success_alarm.add_alarm_action(
            cw_actions.SnsAction(self.alerts_topic)
        )

    def _create_quicksight_manifest(self) -> None:
        """Create S3 manifest file for QuickSight data source integration."""
        manifest_content = {
            "fileLocations": [
                {
                    "URIPrefixes": [
                        f"s3://{self.sustainability_bucket.bucket_name}/sustainability-analytics/"
                    ]
                }
            ],
            "globalUploadSettings": {
                "format": "JSON",
                "delimiter": ",",
                "textqualifier": '"',
                "containsHeader": "true"
            }
        }

        # Create manifest as S3 object
        from aws_cdk import aws_s3_deployment as s3deploy
        
        # Create manifest deployment
        s3deploy.BucketDeployment(
            self, "QuickSightManifest",
            sources=[
                s3deploy.Source.json_data(
                    "manifests/sustainability-manifest.json",
                    manifest_content
                )
            ],
            destination_bucket=self.sustainability_bucket,
            metadata={
                "purpose": "quicksight-manifest",
                "data-type": "sustainability-analytics"
            }
        )

    def _add_resource_tags(self) -> None:
        """Add standardized tags to all resources for cost allocation and governance."""
        tags_config = {
            "Project": "SustainabilityDashboard",
            "Environment": self.node.try_get_context("environment") or "development", 
            "CostCenter": "Sustainability",
            "Owner": "SustainabilityTeam",
            "DataClassification": "Internal",
            "BackupRequired": "true",
            "MonitoringRequired": "true"
        }

        for key, value in tags_config.items():
            Tags.of(self).add(key, value)

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self, "SustainabilityBucketName",
            value=self.sustainability_bucket.bucket_name,
            description="S3 bucket name for sustainability data lake"
        )

        CfnOutput(
            self, "LambdaFunctionName", 
            value=self.sustainability_processor.function_name,
            description="Lambda function name for sustainability data processing"
        )

        CfnOutput(
            self, "SnsTopicArn",
            value=self.alerts_topic.topic_arn,
            description="SNS topic ARN for sustainability alerts"
        )

        CfnOutput(
            self, "EventBridgeRuleName",
            value=self.data_collection_rule.rule_name,
            description="EventBridge rule name for automated data collection"
        )

        CfnOutput(
            self, "QuickSightManifestLocation",
            value=f"s3://{self.sustainability_bucket.bucket_name}/manifests/sustainability-manifest.json",
            description="S3 location of QuickSight manifest file"
        )


# CDK Application entry point
app = cdk.App()

# Get deployment environment from context
environment = app.node.try_get_context("environment") or "development"

# Create the sustainability dashboard stack
sustainability_stack = SustainabilityDashboardStack(
    app, 
    f"SustainabilityDashboardStack-{environment}",
    env=cdk.Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    ),
    description="AWS Sustainability Dashboard Infrastructure with QuickSight analytics and Lambda processing"
)

# Synthesize the application
app.synth()