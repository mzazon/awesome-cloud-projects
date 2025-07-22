#!/usr/bin/env python3
"""
CDK Python Application for Amazon Pinpoint A/B Testing

This application deploys the complete infrastructure for implementing A/B testing
for mobile apps using Amazon Pinpoint, including campaigns, segments, analytics,
and monitoring components.
"""

import os
from typing import Dict, Any, Optional
from aws_cdk import (
    App,
    Stack,
    Environment,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_pinpoint as pinpoint,
    aws_s3 as s3,
    aws_iam as iam,
    aws_kinesis as kinesis,
    aws_cloudwatch as cloudwatch,
    aws_lambda as lambda_,
    aws_logs as logs,
    aws_events as events,
    aws_events_targets as targets,
    aws_kms as kms,
)
from constructs import Construct


class PinpointAbTestingStack(Stack):
    """
    CDK Stack for Amazon Pinpoint A/B Testing Infrastructure
    
    This stack creates:
    - Pinpoint project with A/B testing capabilities
    - S3 bucket for analytics export
    - Kinesis stream for real-time event processing
    - Lambda functions for automated analysis
    - CloudWatch dashboard for monitoring
    - IAM roles and policies
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        project_name: str = "mobile-ab-testing",
        enable_real_time_processing: bool = True,
        enable_automated_analysis: bool = True,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.project_name = project_name
        self.enable_real_time_processing = enable_real_time_processing
        self.enable_automated_analysis = enable_automated_analysis

        # Create KMS key for encryption
        self.kms_key = self._create_kms_key()

        # Create S3 bucket for analytics export
        self.analytics_bucket = self._create_analytics_bucket()

        # Create Kinesis stream for real-time events
        self.kinesis_stream = self._create_kinesis_stream()

        # Create IAM roles
        self.pinpoint_role = self._create_pinpoint_role()
        self.lambda_role = self._create_lambda_role()

        # Create Pinpoint project
        self.pinpoint_project = self._create_pinpoint_project()

        # Create user segments
        self.segments = self._create_user_segments()

        # Create A/B test campaign
        self.ab_test_campaign = self._create_ab_test_campaign()

        # Create Lambda functions for automated analysis
        if self.enable_automated_analysis:
            self.analysis_function = self._create_analysis_function()
            self.winner_selection_function = self._create_winner_selection_function()

        # Create CloudWatch dashboard
        self.dashboard = self._create_cloudwatch_dashboard()

        # Create CloudWatch alarms
        self._create_cloudwatch_alarms()

        # Create outputs
        self._create_outputs()

    def _create_kms_key(self) -> kms.Key:
        """Create KMS key for encryption"""
        return kms.Key(
            self,
            "PinpointKmsKey",
            description="KMS key for Pinpoint A/B testing encryption",
            enable_key_rotation=True,
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _create_analytics_bucket(self) -> s3.Bucket:
        """Create S3 bucket for analytics export"""
        bucket = s3.Bucket(
            self,
            "AnalyticsBucket",
            bucket_name=f"pinpoint-analytics-{self.account}-{self.region}",
            encryption=s3.BucketEncryption.KMS,
            encryption_key=self.kms_key,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="AnalyticsDataLifecycle",
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
                    expiration=Duration.days(365),
                ),
            ],
        )

        # Add bucket policy for Pinpoint access
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("pinpoint.amazonaws.com")],
                actions=["s3:PutObject", "s3:GetBucketLocation"],
                resources=[bucket.bucket_arn, f"{bucket.bucket_arn}/*"],
                conditions={
                    "StringEquals": {
                        "aws:SourceAccount": self.account,
                    },
                },
            )
        )

        return bucket

    def _create_kinesis_stream(self) -> Optional[kinesis.Stream]:
        """Create Kinesis stream for real-time event processing"""
        if not self.enable_real_time_processing:
            return None

        return kinesis.Stream(
            self,
            "PinpointEventStream",
            stream_name=f"pinpoint-events-{self.project_name}",
            shard_count=1,
            retention_period=Duration.days(1),
            encryption=kinesis.StreamEncryption.KMS,
            encryption_key=self.kms_key,
        )

    def _create_pinpoint_role(self) -> iam.Role:
        """Create IAM role for Pinpoint service"""
        role = iam.Role(
            self,
            "PinpointServiceRole",
            assumed_by=iam.ServicePrincipal("pinpoint.amazonaws.com"),
            description="Service role for Amazon Pinpoint A/B testing",
        )

        # Add S3 permissions for analytics export
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:PutObject",
                    "s3:GetBucketLocation",
                    "s3:ListBucket",
                ],
                resources=[
                    self.analytics_bucket.bucket_arn,
                    f"{self.analytics_bucket.bucket_arn}/*",
                ],
            )
        )

        # Add Kinesis permissions for event streaming
        if self.kinesis_stream:
            role.add_to_policy(
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "kinesis:PutRecord",
                        "kinesis:PutRecords",
                        "kinesis:DescribeStream",
                    ],
                    resources=[self.kinesis_stream.stream_arn],
                )
            )

        # Add KMS permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "kms:Encrypt",
                    "kms:Decrypt",
                    "kms:GenerateDataKey",
                    "kms:DescribeKey",
                ],
                resources=[self.kms_key.key_arn],
            )
        )

        return role

    def _create_lambda_role(self) -> iam.Role:
        """Create IAM role for Lambda functions"""
        role = iam.Role(
            self,
            "PinpointLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
            description="Execution role for Pinpoint analysis Lambda functions",
        )

        # Add Pinpoint permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "mobiletargeting:GetCampaign",
                    "mobiletargeting:GetCampaignActivities",
                    "mobiletargeting:GetApplicationSettings",
                    "mobiletargeting:GetSegment",
                    "mobiletargeting:UpdateCampaign",
                ],
                resources=[
                    f"arn:aws:mobiletargeting:{self.region}:{self.account}:apps/*",
                ],
            )
        )

        # Add CloudWatch permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudwatch:PutMetricData",
                    "cloudwatch:GetMetricStatistics",
                ],
                resources=["*"],
            )
        )

        return role

    def _create_pinpoint_project(self) -> pinpoint.CfnApp:
        """Create Pinpoint project (application)"""
        project = pinpoint.CfnApp(
            self,
            "PinpointProject",
            name=self.project_name,
            tags={
                "Purpose": "A/B Testing",
                "Environment": "Production",
                "Project": self.project_name,
            },
        )

        # Configure application settings
        pinpoint.CfnApplicationSettings(
            self,
            "PinpointApplicationSettings",
            application_id=project.ref,
            campaign_hook={
                "mode": "DELIVERY",
            },
            cloud_watch_metrics_enabled=True,
            event_tagging_enabled=True,
            limits={
                "daily": 1000,
                "maximumDuration": 86400,
                "messagesPerSecond": 100,
                "total": 10000,
            },
        )

        return project

    def _create_user_segments(self) -> Dict[str, pinpoint.CfnSegment]:
        """Create user segments for A/B testing"""
        segments = {}

        # Active users segment
        segments["active_users"] = pinpoint.CfnSegment(
            self,
            "ActiveUsersSegment",
            application_id=self.pinpoint_project.ref,
            name="ActiveUsers",
            segment_groups={
                "groups": [
                    {
                        "type": "ALL",
                        "sourceType": "ALL",
                        "dimensions": {
                            "demographic": {
                                "appVersion": {
                                    "dimensionType": "INCLUSIVE",
                                    "values": ["1.0.0", "1.1.0", "1.2.0"],
                                }
                            }
                        },
                    }
                ]
            },
        )

        # High-value users segment
        segments["high_value_users"] = pinpoint.CfnSegment(
            self,
            "HighValueUsersSegment",
            application_id=self.pinpoint_project.ref,
            name="HighValueUsers",
            segment_groups={
                "groups": [
                    {
                        "type": "ALL",
                        "sourceType": "ALL",
                        "dimensions": {
                            "behavior": {
                                "recency": {
                                    "duration": "DAY_7",
                                    "recencyType": "ACTIVE",
                                }
                            },
                            "metrics": {
                                "session_count": {
                                    "comparisonOperator": "GREATER_THAN",
                                    "value": 5.0,
                                }
                            },
                        },
                    }
                ]
            },
        )

        return segments

    def _create_ab_test_campaign(self) -> pinpoint.CfnCampaign:
        """Create A/B test campaign"""
        campaign = pinpoint.CfnCampaign(
            self,
            "AbTestCampaign",
            application_id=self.pinpoint_project.ref,
            name="Push Notification A/B Test",
            description="Testing different push notification messages for user engagement",
            schedule={
                "startTime": "IMMEDIATE",
                "isLocalTime": False,
                "timezone": "UTC",
            },
            segment_id=self.segments["active_users"].ref,
            message_configuration={
                "gcmMessage": {
                    "body": "🎯 Control Message: Check out our new features!",
                    "title": "New Updates Available",
                    "action": "OPEN_APP",
                    "silentPush": False,
                },
                "apnsMessage": {
                    "body": "🎯 Control Message: Check out our new features!",
                    "title": "New Updates Available",
                    "action": "OPEN_APP",
                    "silentPush": False,
                },
            },
            additional_treatments=[
                {
                    "treatmentName": "Personalized",
                    "treatmentDescription": "Personalized message variant",
                    "sizePercent": 45,
                    "messageConfiguration": {
                        "gcmMessage": {
                            "body": "🚀 Hi {{User.FirstName}}, discover features made just for you!",
                            "title": "Personalized Updates",
                            "action": "OPEN_APP",
                            "silentPush": False,
                        },
                        "apnsMessage": {
                            "body": "🚀 Hi {{User.FirstName}}, discover features made just for you!",
                            "title": "Personalized Updates",
                            "action": "OPEN_APP",
                            "silentPush": False,
                        },
                    },
                },
                {
                    "treatmentName": "Urgent",
                    "treatmentDescription": "Urgent tone message variant",
                    "sizePercent": 45,
                    "messageConfiguration": {
                        "gcmMessage": {
                            "body": "⚡ Don't miss out! Limited time features available now!",
                            "title": "Limited Time Offer",
                            "action": "OPEN_APP",
                            "silentPush": False,
                        },
                        "apnsMessage": {
                            "body": "⚡ Don't miss out! Limited time features available now!",
                            "title": "Limited Time Offer",
                            "action": "OPEN_APP",
                            "silentPush": False,
                        },
                    },
                },
            ],
            holdout_percent=10,
            is_paused=True,  # Start paused, activate manually
            tags={
                "TestType": "A/B Test",
                "Channel": "Push Notification",
                "Status": "Active",
            },
        )

        return campaign

    def _create_analysis_function(self) -> lambda_.Function:
        """Create Lambda function for campaign analysis"""
        function = lambda_.Function(
            self,
            "CampaignAnalysisFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.handler",
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=512,
            environment={
                "PINPOINT_PROJECT_ID": self.pinpoint_project.ref,
                "S3_BUCKET": self.analytics_bucket.bucket_name,
            },
            code=lambda_.Code.from_inline("""
import json
import boto3
import os
from datetime import datetime, timedelta
from typing import Dict, Any, List

def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    \"\"\"
    Analyze A/B test campaign performance and generate insights
    \"\"\"
    pinpoint = boto3.client('mobiletargeting')
    cloudwatch = boto3.client('cloudwatch')
    
    project_id = os.environ['PINPOINT_PROJECT_ID']
    
    try:
        # Get campaign activities
        response = pinpoint.get_campaign_activities(
            ApplicationId=project_id,
            CampaignId=event.get('campaign_id')
        )
        
        activities = response.get('ActivitiesResponse', {}).get('Item', [])
        
        # Calculate metrics for each treatment
        treatment_metrics = {}
        
        for activity in activities:
            treatment_name = activity.get('TreatmentName', 'Control')
            delivered = activity.get('DeliveredCount', 0)
            opened = activity.get('OpenedCount', 0)
            
            if delivered > 0:
                open_rate = opened / delivered
                treatment_metrics[treatment_name] = {
                    'delivered': delivered,
                    'opened': opened,
                    'open_rate': open_rate
                }
        
        # Send custom metrics to CloudWatch
        for treatment, metrics in treatment_metrics.items():
            cloudwatch.put_metric_data(
                Namespace='Pinpoint/ABTesting',
                MetricData=[
                    {
                        'MetricName': 'OpenRate',
                        'Dimensions': [
                            {
                                'Name': 'Treatment',
                                'Value': treatment
                            },
                            {
                                'Name': 'Campaign',
                                'Value': event.get('campaign_id', 'Unknown')
                            }
                        ],
                        'Value': metrics['open_rate'],
                        'Unit': 'Percent'
                    }
                ]
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Analysis completed successfully',
                'metrics': treatment_metrics
            })
        }
        
    except Exception as e:
        print(f"Error analyzing campaign: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
            """),
            description="Analyze A/B test campaign performance",
        )

        return function

    def _create_winner_selection_function(self) -> lambda_.Function:
        """Create Lambda function for automated winner selection"""
        function = lambda_.Function(
            self,
            "WinnerSelectionFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.handler",
            role=self.lambda_role,
            timeout=Duration.minutes(10),
            memory_size=1024,
            environment={
                "PINPOINT_PROJECT_ID": self.pinpoint_project.ref,
            },
            code=lambda_.Code.from_inline("""
import json
import boto3
import os
import math
from typing import Dict, Any, Optional, Tuple

def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    \"\"\"
    Automated winner selection based on statistical significance
    \"\"\"
    pinpoint = boto3.client('mobiletargeting')
    
    project_id = os.environ['PINPOINT_PROJECT_ID']
    campaign_id = event.get('campaign_id')
    
    try:
        # Get campaign activities
        response = pinpoint.get_campaign_activities(
            ApplicationId=project_id,
            CampaignId=campaign_id
        )
        
        activities = response.get('ActivitiesResponse', {}).get('Item', [])
        
        # Calculate conversion rates and statistical significance
        treatments = []
        for activity in activities:
            treatment_name = activity.get('TreatmentName', 'Control')
            delivered = activity.get('DeliveredCount', 0)
            conversions = activity.get('ConversionsCount', 0)
            
            if delivered > 0:
                conversion_rate = conversions / delivered
                treatments.append({
                    'name': treatment_name,
                    'delivered': delivered,
                    'conversions': conversions,
                    'conversion_rate': conversion_rate
                })
        
        # Find best performing treatment
        best_treatment = max(treatments, key=lambda x: x['conversion_rate'])
        
        # Calculate statistical significance (simplified z-test)
        control_treatment = next(
            (t for t in treatments if t['name'] == 'Control'), 
            treatments[0]
        )
        
        if best_treatment['name'] != control_treatment['name']:
            p_value = calculate_p_value(
                control_treatment['conversions'],
                control_treatment['delivered'],
                best_treatment['conversions'],
                best_treatment['delivered']
            )
            
            is_significant = p_value < 0.05
        else:
            is_significant = False
            p_value = 1.0
        
        result = {
            'winner': best_treatment['name'],
            'winner_conversion_rate': best_treatment['conversion_rate'],
            'is_statistically_significant': is_significant,
            'p_value': p_value,
            'all_treatments': treatments
        }
        
        print(f"Winner selection result: {json.dumps(result, indent=2)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(result)
        }
        
    except Exception as e:
        print(f"Error in winner selection: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }

def calculate_p_value(
    control_conversions: int,
    control_total: int,
    treatment_conversions: int,
    treatment_total: int
) -> float:
    \"\"\"
    Calculate p-value for A/B test using two-proportion z-test
    \"\"\"
    if control_total == 0 or treatment_total == 0:
        return 1.0
    
    p1 = control_conversions / control_total
    p2 = treatment_conversions / treatment_total
    
    # Pooled proportion
    p_pooled = (control_conversions + treatment_conversions) / (control_total + treatment_total)
    
    # Standard error
    se = math.sqrt(p_pooled * (1 - p_pooled) * (1/control_total + 1/treatment_total))
    
    if se == 0:
        return 1.0
    
    # Z-score
    z = (p2 - p1) / se
    
    # Two-tailed p-value (simplified approximation)
    p_value = 2 * (1 - abs(z) / 2.58)  # Approximation for normal distribution
    
    return max(0.0, min(1.0, p_value))
            """),
            description="Automated winner selection with statistical significance testing",
        )

        # Create EventBridge rule to trigger winner selection
        rule = events.Rule(
            self,
            "WinnerSelectionRule",
            description="Trigger winner selection analysis daily",
            schedule=events.Schedule.rate(Duration.days(1)),
        )

        rule.add_target(
            targets.LambdaFunction(
                function,
                event=events.RuleTargetInput.from_object(
                    {"campaign_id": self.ab_test_campaign.ref}
                ),
            )
        )

        return function

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for monitoring"""
        dashboard = cloudwatch.Dashboard(
            self,
            "PinpointAbTestDashboard",
            dashboard_name=f"Pinpoint-AB-Testing-{self.project_name}",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Campaign Delivery Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/Pinpoint",
                                metric_name="DirectMessagesSent",
                                dimensions_map={
                                    "ApplicationId": self.pinpoint_project.ref,
                                },
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/Pinpoint",
                                metric_name="DirectMessagesDelivered",
                                dimensions_map={
                                    "ApplicationId": self.pinpoint_project.ref,
                                },
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                        ],
                        width=12,
                    ),
                ],
                [
                    cloudwatch.GraphWidget(
                        title="Engagement Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/Pinpoint",
                                metric_name="DirectMessagesOpened",
                                dimensions_map={
                                    "ApplicationId": self.pinpoint_project.ref,
                                },
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/Pinpoint",
                                metric_name="DirectMessagesBounced",
                                dimensions_map={
                                    "ApplicationId": self.pinpoint_project.ref,
                                },
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                        ],
                        width=12,
                    ),
                ],
                [
                    cloudwatch.GraphWidget(
                        title="A/B Test Conversion Rates by Treatment",
                        left=[
                            cloudwatch.Metric(
                                namespace="Pinpoint/ABTesting",
                                metric_name="OpenRate",
                                dimensions_map={
                                    "Treatment": "Control",
                                    "Campaign": self.ab_test_campaign.ref,
                                },
                                statistic="Average",
                                period=Duration.minutes(15),
                            ),
                            cloudwatch.Metric(
                                namespace="Pinpoint/ABTesting",
                                metric_name="OpenRate",
                                dimensions_map={
                                    "Treatment": "Personalized",
                                    "Campaign": self.ab_test_campaign.ref,
                                },
                                statistic="Average",
                                period=Duration.minutes(15),
                            ),
                            cloudwatch.Metric(
                                namespace="Pinpoint/ABTesting",
                                metric_name="OpenRate",
                                dimensions_map={
                                    "Treatment": "Urgent",
                                    "Campaign": self.ab_test_campaign.ref,
                                },
                                statistic="Average",
                                period=Duration.minutes(15),
                            ),
                        ],
                        width=12,
                    ),
                ],
            ],
        )

        return dashboard

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for monitoring"""
        # Alarm for high bounce rate
        cloudwatch.Alarm(
            self,
            "HighBounceRateAlarm",
            metric=cloudwatch.Metric(
                namespace="AWS/Pinpoint",
                metric_name="DirectMessagesBounced",
                dimensions_map={
                    "ApplicationId": self.pinpoint_project.ref,
                },
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=100,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            alarm_description="High bounce rate detected in A/B test campaign",
        )

        # Alarm for low delivery rate
        cloudwatch.Alarm(
            self,
            "LowDeliveryRateAlarm",
            metric=cloudwatch.MathExpression(
                expression="delivered / sent * 100",
                using_metrics={
                    "sent": cloudwatch.Metric(
                        namespace="AWS/Pinpoint",
                        metric_name="DirectMessagesSent",
                        dimensions_map={
                            "ApplicationId": self.pinpoint_project.ref,
                        },
                        statistic="Sum",
                        period=Duration.minutes(5),
                    ),
                    "delivered": cloudwatch.Metric(
                        namespace="AWS/Pinpoint",
                        metric_name="DirectMessagesDelivered",
                        dimensions_map={
                            "ApplicationId": self.pinpoint_project.ref,
                        },
                        statistic="Sum",
                        period=Duration.minutes(5),
                    ),
                },
                period=Duration.minutes(5),
            ),
            threshold=90,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            alarm_description="Low delivery rate detected in A/B test campaign",
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs"""
        CfnOutput(
            self,
            "PinpointProjectId",
            value=self.pinpoint_project.ref,
            description="Pinpoint Project ID for A/B testing",
            export_name=f"{self.stack_name}-PinpointProjectId",
        )

        CfnOutput(
            self,
            "CampaignId",
            value=self.ab_test_campaign.ref,
            description="A/B Test Campaign ID",
            export_name=f"{self.stack_name}-CampaignId",
        )

        CfnOutput(
            self,
            "ActiveUsersSegmentId",
            value=self.segments["active_users"].ref,
            description="Active Users Segment ID",
            export_name=f"{self.stack_name}-ActiveUsersSegmentId",
        )

        CfnOutput(
            self,
            "AnalyticsBucketName",
            value=self.analytics_bucket.bucket_name,
            description="S3 bucket for analytics export",
            export_name=f"{self.stack_name}-AnalyticsBucketName",
        )

        if self.kinesis_stream:
            CfnOutput(
                self,
                "KinesisStreamName",
                value=self.kinesis_stream.stream_name,
                description="Kinesis stream for real-time events",
                export_name=f"{self.stack_name}-KinesisStreamName",
            )

        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="CloudWatch Dashboard URL",
            export_name=f"{self.stack_name}-DashboardUrl",
        )

        if self.enable_automated_analysis:
            CfnOutput(
                self,
                "AnalysisFunctionArn",
                value=self.analysis_function.function_arn,
                description="Lambda function for campaign analysis",
                export_name=f"{self.stack_name}-AnalysisFunctionArn",
            )

            CfnOutput(
                self,
                "WinnerSelectionFunctionArn",
                value=self.winner_selection_function.function_arn,
                description="Lambda function for automated winner selection",
                export_name=f"{self.stack_name}-WinnerSelectionFunctionArn",
            )


def main():
    """Main application entry point"""
    app = App()

    # Get configuration from environment variables or context
    project_name = app.node.try_get_context("project_name") or "mobile-ab-testing"
    enable_real_time = app.node.try_get_context("enable_real_time_processing") != "false"
    enable_automation = app.node.try_get_context("enable_automated_analysis") != "false"

    # Create the stack
    PinpointAbTestingStack(
        app,
        "PinpointAbTestingStack",
        project_name=project_name,
        enable_real_time_processing=enable_real_time,
        enable_automated_analysis=enable_automation,
        env=Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
        ),
        description="Amazon Pinpoint A/B Testing Infrastructure for Mobile Apps",
    )

    app.synth()


if __name__ == "__main__":
    main()