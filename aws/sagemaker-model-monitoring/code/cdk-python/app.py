#!/usr/bin/env python3
"""
AWS CDK Application for SageMaker Model Monitoring and Drift Detection

This CDK application deploys a comprehensive ML monitoring solution using:
- SageMaker Model Monitor for automated drift detection
- CloudWatch alarms for real-time alerting
- Lambda functions for automated response
- SNS topics for notification management
- S3 buckets for data storage and monitoring artifacts

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, Any, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    Duration,
    RemovalPolicy,
    CfnOutput,
)
from aws_cdk import aws_s3 as s3
from aws_cdk import aws_iam as iam
from aws_cdk import aws_lambda as lambda_
from aws_cdk import aws_sns as sns
from aws_cdk import aws_sns_subscriptions as sns_subscriptions
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_cloudwatch_actions as cloudwatch_actions
from aws_cdk import aws_sagemaker as sagemaker
from aws_cdk import aws_logs as logs
from constructs import Construct


class ModelMonitoringStack(Stack):
    """
    CDK Stack for SageMaker Model Monitoring and Drift Detection
    
    This stack creates a complete MLOps monitoring infrastructure including:
    - SageMaker model endpoint with data capture
    - Model monitoring schedules for data quality and model quality
    - CloudWatch alarms and dashboards
    - Lambda-based automated response system
    - SNS notification infrastructure
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        notification_email: Optional[str] = None,
        monitoring_frequency: str = "Hourly",
        **kwargs
    ) -> None:
        """
        Initialize the Model Monitoring Stack
        
        Args:
            scope: CDK App construct
            construct_id: Unique identifier for this stack
            notification_email: Email address for monitoring alerts
            monitoring_frequency: Monitoring schedule frequency (Hourly/Daily)
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration parameters
        self.notification_email = notification_email
        self.monitoring_frequency = monitoring_frequency

        # Create core infrastructure
        self._create_s3_resources()
        self._create_iam_roles()
        self._create_lambda_functions()
        self._create_sns_notifications()
        self._create_sagemaker_model()
        self._create_monitoring_schedules()
        self._create_cloudwatch_resources()
        self._create_outputs()

    def _create_s3_resources(self) -> None:
        """Create S3 buckets for model artifacts and monitoring data"""
        
        # S3 bucket for model monitoring artifacts
        self.monitoring_bucket = s3.Bucket(
            self,
            "ModelMonitoringBucket",
            bucket_name=f"model-monitor-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="MonitoringDataRetention",
                    enabled=True,
                    expiration=Duration.days(90),
                    noncurrent_version_expiration=Duration.days(30),
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Create folder structure for monitoring data
        bucket_objects = [
            "baseline-data/",
            "captured-data/", 
            "monitoring-results/",
            "model-artifacts/"
        ]
        
        for folder in bucket_objects:
            s3.BucketDeployment(
                self,
                f"Create{folder.replace('/', '').replace('-', '').title()}Folder",
                sources=[],
                destination_bucket=self.monitoring_bucket,
                destination_key_prefix=folder,
            )

    def _create_iam_roles(self) -> None:
        """Create IAM roles for SageMaker and Lambda services"""
        
        # IAM role for SageMaker Model Monitor
        self.sagemaker_role = iam.Role(
            self,
            "SageMakerModelMonitorRole",
            assumed_by=iam.ServicePrincipal("sagemaker.amazonaws.com"),
            description="IAM role for SageMaker Model Monitor operations",
            inline_policies={
                "ModelMonitorPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:PutObject",
                                "s3:DeleteObject",
                                "s3:ListBucket",
                            ],
                            resources=[
                                self.monitoring_bucket.bucket_arn,
                                f"{self.monitoring_bucket.bucket_arn}/*",
                            ],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents",
                                "logs:DescribeLogStreams",
                            ],
                            resources=["*"],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "cloudwatch:PutMetricData",
                            ],
                            resources=["*"],
                        ),
                    ]
                )
            },
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSageMakerFullAccess"),
            ],
        )

        # IAM role for Lambda function
        self.lambda_role = iam.Role(
            self,
            "ModelMonitorLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for Model Monitor Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
        )

    def _create_lambda_functions(self) -> None:
        """Create Lambda function for automated monitoring response"""
        
        # Lambda function for handling monitoring alerts
        self.alert_handler = lambda_.Function(
            self,
            "ModelMonitorAlertHandler",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=self.lambda_role,
            description="Handles Model Monitor alerts and automated responses",
            timeout=Duration.minutes(5),
            memory_size=256,
            environment={
                "MONITORING_BUCKET": self.monitoring_bucket.bucket_name,
                "LOG_LEVEL": "INFO",
            },
            code=lambda_.Code.from_inline("""
import json
import boto3
import os
import logging
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    \"\"\"
    Lambda function to handle Model Monitor alerts
    
    Args:
        event: SNS event containing CloudWatch alarm details
        context: Lambda context object
        
    Returns:
        Dictionary with processing status
    \"\"\"
    try:
        sns = boto3.client('sns')
        sagemaker = boto3.client('sagemaker')
        cloudwatch = boto3.client('cloudwatch')
        
        # Parse the CloudWatch alarm from SNS
        for record in event.get('Records', []):
            if 'Sns' in record:
                message = json.loads(record['Sns']['Message'])
                
                alarm_name = message.get('AlarmName', 'Unknown')
                alarm_description = message.get('AlarmDescription', '')
                new_state = message.get('NewStateValue', 'UNKNOWN')
                
                logger.info(f"Processing alarm: {alarm_name} - {new_state}")
                
                # Check if this is a model drift alarm
                if new_state == 'ALARM' and 'ModelMonitor' in alarm_name:
                    logger.warning(f"Model drift detected: {alarm_description}")
                    
                    # Get monitoring schedule details
                    try:
                        # Extract monitoring schedule name from alarm dimensions
                        dimensions = message.get('Trigger', {}).get('Dimensions', [])
                        schedule_name = None
                        
                        for dim in dimensions:
                            if dim.get('name') == 'MonitoringSchedule':
                                schedule_name = dim.get('value')
                                break
                        
                        if schedule_name:
                            response = sagemaker.describe_monitoring_schedule(
                                MonitoringScheduleName=schedule_name
                            )
                            logger.info(f"Monitoring schedule status: {response.get('MonitoringScheduleStatus')}")
                    
                    except Exception as e:
                        logger.error(f"Error getting monitoring schedule details: {str(e)}")
                    
                    # Additional automated actions could be added here:
                    # - Trigger model retraining pipeline
                    # - Update model endpoint configuration
                    # - Send alerts to monitoring systems
                    # - Create support tickets
                    
                    logger.info("Alert processed successfully")
                
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Alerts processed successfully',
                'processed_records': len(event.get('Records', []))
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing alert: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to process alert'
            })
        }
"""),
        )

        # Grant Lambda permissions to access required services
        self.monitoring_bucket.grant_read_write(self.alert_handler)
        
        # Grant Lambda permissions for SageMaker operations
        self.alert_handler.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "sagemaker:DescribeMonitoringSchedule",
                    "sagemaker:DescribeProcessingJob",
                    "sagemaker:DescribeEndpoint",
                ],
                resources=["*"],
            )
        )

    def _create_sns_notifications(self) -> None:
        """Create SNS topic and subscriptions for monitoring alerts"""
        
        # SNS topic for monitoring alerts
        self.alert_topic = sns.Topic(
            self,
            "ModelMonitorAlertTopic",
            topic_name="model-monitor-alerts",
            display_name="Model Monitor Alerts",
            description="SNS topic for SageMaker Model Monitor alerts",
        )

        # Subscribe Lambda function to SNS topic
        self.alert_topic.add_subscription(
            sns_subscriptions.LambdaSubscription(self.alert_handler)
        )

        # Subscribe email if provided
        if self.notification_email:
            self.alert_topic.add_subscription(
                sns_subscriptions.EmailSubscription(self.notification_email)
            )

        # Grant Lambda permission to publish to SNS
        self.alert_handler.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["sns:Publish"],
                resources=[self.alert_topic.topic_arn],
            )
        )

    def _create_sagemaker_model(self) -> None:
        """Create SageMaker model, endpoint configuration, and endpoint"""
        
        # Create a simple demo model for monitoring
        demo_model_data = self.monitoring_bucket.s3_url_for_object("model-artifacts/model.tar.gz")
        
        # SageMaker model
        self.model = sagemaker.CfnModel(
            self,
            "DemoModel",
            model_name="demo-model-for-monitoring",
            execution_role_arn=self.sagemaker_role.role_arn,
            primary_container=sagemaker.CfnModel.ContainerDefinitionProperty(
                image=f"763104351884.dkr.ecr.{self.region}.amazonaws.com/sklearn-inference:0.23-1-cpu-py3",
                model_data_url=demo_model_data,
            ),
        )

        # Endpoint configuration with data capture enabled
        self.endpoint_config = sagemaker.CfnEndpointConfig(
            self,
            "ModelEndpointConfig",
            endpoint_config_name="demo-endpoint-config",
            production_variants=[
                sagemaker.CfnEndpointConfig.ProductionVariantProperty(
                    variant_name="Primary",
                    model_name=self.model.model_name,
                    initial_instance_count=1,
                    instance_type="ml.t2.medium",
                    initial_variant_weight=1.0,
                )
            ],
            data_capture_config=sagemaker.CfnEndpointConfig.DataCaptureConfigProperty(
                enable_capture=True,
                initial_sampling_percentage=100,
                destination_s3_uri=f"{self.monitoring_bucket.s3_url_for_object('captured-data')}",
                capture_options=[
                    sagemaker.CfnEndpointConfig.CaptureOptionProperty(capture_mode="Input"),
                    sagemaker.CfnEndpointConfig.CaptureOptionProperty(capture_mode="Output"),
                ],
            ),
        )

        # SageMaker endpoint
        self.endpoint = sagemaker.CfnEndpoint(
            self,
            "ModelEndpoint",
            endpoint_name="demo-model-endpoint",
            endpoint_config_name=self.endpoint_config.endpoint_config_name,
        )

        # Set dependencies
        self.endpoint_config.add_dependency(self.model)
        self.endpoint.add_dependency(self.endpoint_config)

    def _create_monitoring_schedules(self) -> None:
        """Create SageMaker monitoring schedules for data quality and model quality"""
        
        # Determine schedule expression based on frequency
        schedule_expressions = {
            "Hourly": "cron(0 * * * ? *)",
            "Daily": "cron(0 6 * * ? *)",
            "Weekly": "cron(0 6 ? * MON *)",
        }
        
        data_quality_schedule = schedule_expressions.get(self.monitoring_frequency, "cron(0 * * * ? *)")
        model_quality_schedule = "cron(0 6 * * ? *)"  # Daily for model quality

        # Data Quality Monitoring Schedule
        self.data_quality_schedule = sagemaker.CfnMonitoringSchedule(
            self,
            "DataQualityMonitoringSchedule",
            monitoring_schedule_name="data-quality-monitoring-schedule",
            monitoring_schedule_config=sagemaker.CfnMonitoringSchedule.MonitoringScheduleConfigProperty(
                schedule_config=sagemaker.CfnMonitoringSchedule.ScheduleConfigProperty(
                    schedule_expression=data_quality_schedule
                ),
                monitoring_job_definition=sagemaker.CfnMonitoringSchedule.MonitoringJobDefinitionProperty(
                    monitoring_inputs=[
                        sagemaker.CfnMonitoringSchedule.MonitoringInputProperty(
                            endpoint_input=sagemaker.CfnMonitoringSchedule.EndpointInputProperty(
                                endpoint_name=self.endpoint.endpoint_name,
                                local_path="/opt/ml/processing/input/endpoint",
                                s3_input_mode="File",
                                s3_data_distribution_type="FullyReplicated",
                            )
                        )
                    ],
                    monitoring_output_config=sagemaker.CfnMonitoringSchedule.MonitoringOutputConfigProperty(
                        monitoring_outputs=[
                            sagemaker.CfnMonitoringSchedule.MonitoringOutputProperty(
                                s3_output=sagemaker.CfnMonitoringSchedule.S3OutputProperty(
                                    s3_uri=f"{self.monitoring_bucket.s3_url_for_object('monitoring-results/data-quality')}",
                                    local_path="/opt/ml/processing/output",
                                    s3_upload_mode="EndOfJob",
                                )
                            )
                        ]
                    ),
                    monitoring_resources=sagemaker.CfnMonitoringSchedule.MonitoringResourcesProperty(
                        cluster_config=sagemaker.CfnMonitoringSchedule.ClusterConfigProperty(
                            instance_type="ml.m5.xlarge",
                            instance_count=1,
                            volume_size_in_gb=20,
                        )
                    ),
                    monitoring_app_specification=sagemaker.CfnMonitoringSchedule.MonitoringAppSpecificationProperty(
                        image_uri=f"159807026194.dkr.ecr.{self.region}.amazonaws.com/sagemaker-model-monitor-analyzer:latest"
                    ),
                    baseline_config=sagemaker.CfnMonitoringSchedule.BaselineConfigProperty(
                        statistics_resource=sagemaker.CfnMonitoringSchedule.StatisticsResourceProperty(
                            s3_uri=f"{self.monitoring_bucket.s3_url_for_object('monitoring-results/statistics')}"
                        ),
                        constraints_resource=sagemaker.CfnMonitoringSchedule.ConstraintsResourceProperty(
                            s3_uri=f"{self.monitoring_bucket.s3_url_for_object('monitoring-results/constraints')}"
                        ),
                    ),
                    role_arn=self.sagemaker_role.role_arn,
                ),
            ),
        )

        # Model Quality Monitoring Schedule  
        self.model_quality_schedule = sagemaker.CfnMonitoringSchedule(
            self,
            "ModelQualityMonitoringSchedule",
            monitoring_schedule_name="model-quality-monitoring-schedule",
            monitoring_schedule_config=sagemaker.CfnMonitoringSchedule.MonitoringScheduleConfigProperty(
                schedule_config=sagemaker.CfnMonitoringSchedule.ScheduleConfigProperty(
                    schedule_expression=model_quality_schedule
                ),
                monitoring_job_definition=sagemaker.CfnMonitoringSchedule.MonitoringJobDefinitionProperty(
                    monitoring_inputs=[
                        sagemaker.CfnMonitoringSchedule.MonitoringInputProperty(
                            endpoint_input=sagemaker.CfnMonitoringSchedule.EndpointInputProperty(
                                endpoint_name=self.endpoint.endpoint_name,
                                local_path="/opt/ml/processing/input/endpoint",
                                s3_input_mode="File",
                                s3_data_distribution_type="FullyReplicated",
                            )
                        )
                    ],
                    monitoring_output_config=sagemaker.CfnMonitoringSchedule.MonitoringOutputConfigProperty(
                        monitoring_outputs=[
                            sagemaker.CfnMonitoringSchedule.MonitoringOutputProperty(
                                s3_output=sagemaker.CfnMonitoringSchedule.S3OutputProperty(
                                    s3_uri=f"{self.monitoring_bucket.s3_url_for_object('monitoring-results/model-quality')}",
                                    local_path="/opt/ml/processing/output",
                                    s3_upload_mode="EndOfJob",
                                )
                            )
                        ]
                    ),
                    monitoring_resources=sagemaker.CfnMonitoringSchedule.MonitoringResourcesProperty(
                        cluster_config=sagemaker.CfnMonitoringSchedule.ClusterConfigProperty(
                            instance_type="ml.m5.xlarge",
                            instance_count=1,
                            volume_size_in_gb=20,
                        )
                    ),
                    monitoring_app_specification=sagemaker.CfnMonitoringSchedule.MonitoringAppSpecificationProperty(
                        image_uri=f"159807026194.dkr.ecr.{self.region}.amazonaws.com/sagemaker-model-monitor-analyzer:latest"
                    ),
                    role_arn=self.sagemaker_role.role_arn,
                ),
            ),
        )

        # Set dependencies
        self.data_quality_schedule.add_dependency(self.endpoint)
        self.model_quality_schedule.add_dependency(self.endpoint)

    def _create_cloudwatch_resources(self) -> None:
        """Create CloudWatch alarms and dashboard for monitoring"""
        
        # CloudWatch alarm for constraint violations
        self.constraint_violations_alarm = cloudwatch.Alarm(
            self,
            "ModelMonitorConstraintViolationsAlarm",
            alarm_name="ModelMonitor-ConstraintViolations",
            alarm_description="Alert when model monitor detects constraint violations",
            metric=cloudwatch.Metric(
                namespace="AWS/SageMaker/ModelMonitor",
                metric_name="constraint_violations",
                dimensions_map={
                    "MonitoringSchedule": self.data_quality_schedule.monitoring_schedule_name
                },
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # CloudWatch alarm for monitoring job failures
        self.job_failures_alarm = cloudwatch.Alarm(
            self,
            "ModelMonitorJobFailuresAlarm",
            alarm_name="ModelMonitor-JobFailures",
            alarm_description="Alert when model monitor jobs fail",
            metric=cloudwatch.Metric(
                namespace="AWS/SageMaker/ModelMonitor",
                metric_name="monitoring_job_failures",
                dimensions_map={
                    "MonitoringSchedule": self.data_quality_schedule.monitoring_schedule_name
                },
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Add SNS actions to alarms
        self.constraint_violations_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.alert_topic)
        )
        self.job_failures_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.alert_topic)
        )

        # Create CloudWatch Dashboard
        self.dashboard = cloudwatch.Dashboard(
            self,
            "ModelMonitoringDashboard",
            dashboard_name="ModelMonitoring-Dashboard",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Model Monitor Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/SageMaker/ModelMonitor",
                                metric_name="constraint_violations",
                                dimensions_map={
                                    "MonitoringSchedule": self.data_quality_schedule.monitoring_schedule_name
                                },
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/SageMaker/ModelMonitor", 
                                metric_name="monitoring_job_failures",
                                dimensions_map={
                                    "MonitoringSchedule": self.data_quality_schedule.monitoring_schedule_name
                                },
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                        ],
                        width=12,
                        height=6,
                    )
                ],
                [
                    cloudwatch.LogQueryWidget(
                        title="Model Monitor Logs",
                        log_groups=[
                            logs.LogGroup(
                                self,
                                "ModelMonitorLogGroup", 
                                log_group_name="/aws/sagemaker/ProcessingJobs",
                                retention=logs.RetentionDays.ONE_MONTH,
                            )
                        ],
                        query_lines=[
                            "fields @timestamp, @message",
                            "filter @message like /constraint/",
                            "sort @timestamp desc",
                            "limit 100",
                        ],
                        width=12,
                        height=6,
                    )
                ],
            ],
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources"""
        
        CfnOutput(
            self,
            "MonitoringBucketName",
            value=self.monitoring_bucket.bucket_name,
            description="S3 bucket for model monitoring artifacts",
            export_name=f"{self.stack_name}-MonitoringBucket",
        )

        CfnOutput(
            self,
            "ModelEndpointName", 
            value=self.endpoint.endpoint_name,
            description="SageMaker model endpoint name",
            export_name=f"{self.stack_name}-ModelEndpoint",
        )

        CfnOutput(
            self,
            "AlertTopicArn",
            value=self.alert_topic.topic_arn,
            description="SNS topic ARN for monitoring alerts",
            export_name=f"{self.stack_name}-AlertTopic",
        )

        CfnOutput(
            self,
            "DataQualityScheduleName",
            value=self.data_quality_schedule.monitoring_schedule_name,
            description="Data quality monitoring schedule name",
            export_name=f"{self.stack_name}-DataQualitySchedule",
        )

        CfnOutput(
            self,
            "ModelQualityScheduleName", 
            value=self.model_quality_schedule.monitoring_schedule_name,
            description="Model quality monitoring schedule name",
            export_name=f"{self.stack_name}-ModelQualitySchedule",
        )

        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.alert_handler.function_name,
            description="Lambda function for handling monitoring alerts",
            export_name=f"{self.stack_name}-AlertHandler",
        )

        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="URL to CloudWatch monitoring dashboard",
            export_name=f"{self.stack_name}-DashboardUrl",
        )


def main() -> None:
    """Main function to create and deploy the CDK application"""
    
    app = cdk.App()

    # Get configuration from context or environment variables
    notification_email = app.node.try_get_context("notification_email") or os.environ.get("NOTIFICATION_EMAIL")
    monitoring_frequency = app.node.try_get_context("monitoring_frequency") or "Hourly"
    
    # Create the stack
    ModelMonitoringStack(
        app,
        "ModelMonitoringStack",
        notification_email=notification_email,
        monitoring_frequency=monitoring_frequency,
        description="SageMaker Model Monitoring and Drift Detection Infrastructure",
        env=Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
        ),
    )

    app.synth()


if __name__ == "__main__":
    main()