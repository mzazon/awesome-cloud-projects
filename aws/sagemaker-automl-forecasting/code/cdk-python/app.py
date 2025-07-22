#!/usr/bin/env python3
"""
AWS CDK application for SageMaker AutoML for Time Series Forecasting.

This CDK app creates the complete infrastructure for an advanced forecasting solution
that replaces the deprecated Amazon Forecast service with SageMaker AutoML capabilities.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_s3 as s3,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_apigateway as apigw,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    aws_events as events,
    aws_events_targets as targets,
    aws_sns as sns,
    aws_sns_subscriptions as subs,
)
from constructs import Construct


class AutoMLForecastingStack(Stack):
    """
    Stack for AutoML-based forecasting solution using SageMaker.
    
    This stack creates:
    - S3 bucket for data storage and model artifacts
    - IAM roles for SageMaker AutoML operations
    - Lambda functions for real-time forecasting API
    - API Gateway for external access
    - CloudWatch monitoring and alerting
    - SNS notifications for job status
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.try_get_context("uniqueSuffix") or "demo"
        
        # Create S3 bucket for forecasting data and artifacts
        self.data_bucket = self._create_data_bucket(unique_suffix)
        
        # Create IAM roles for SageMaker operations
        self.sagemaker_role = self._create_sagemaker_role()
        self.lambda_role = self._create_lambda_role()
        
        # Create SNS topic for notifications
        self.notification_topic = self._create_notification_topic(unique_suffix)
        
        # Create Lambda functions
        self.forecast_api_function = self._create_forecast_api_function(unique_suffix)
        self.batch_processing_function = self._create_batch_processing_function(unique_suffix)
        self.model_monitoring_function = self._create_model_monitoring_function(unique_suffix)
        
        # Create API Gateway
        self.api_gateway = self._create_api_gateway(unique_suffix)
        
        # Create CloudWatch monitoring
        self._create_cloudwatch_monitoring(unique_suffix)
        
        # Create EventBridge rules for automation
        self._create_eventbridge_rules()
        
        # Create outputs
        self._create_outputs()

    def _create_data_bucket(self, suffix: str) -> s3.Bucket:
        """Create S3 bucket for storing training data and model artifacts."""
        bucket = s3.Bucket(
            self,
            "ForecastingDataBucket",
            bucket_name=f"automl-forecasting-{suffix}",
            versioning=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ModelArtifactsLifecycle",
                    prefix="automl-output/",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ]
                )
            ]
        )
        
        # Add bucket notification for model training completion
        bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            targets.LambdaDestination(self.model_monitoring_function) if hasattr(self, 'model_monitoring_function') else None,
            s3.NotificationKeyFilter(prefix="automl-output/", suffix=".tar.gz")
        )
        
        return bucket

    def _create_sagemaker_role(self) -> iam.Role:
        """Create IAM role for SageMaker AutoML operations."""
        role = iam.Role(
            self,
            "SageMakerAutoMLRole",
            role_name=f"AutoMLForecastingRole-{self.region}",
            assumed_by=iam.ServicePrincipal("sagemaker.amazonaws.com"),
            description="IAM role for SageMaker AutoML forecasting operations",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSageMakerFullAccess"),
            ],
            inline_policies={
                "S3BucketAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:PutObject",
                                "s3:DeleteObject",
                                "s3:ListBucket",
                                "s3:GetBucketLocation"
                            ],
                            resources=[
                                self.data_bucket.bucket_arn,
                                f"{self.data_bucket.bucket_arn}/*"
                            ]
                        )
                    ]
                ),
                "CloudWatchLogs": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents",
                                "logs:DescribeLogStreams"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )
        
        return role

    def _create_lambda_role(self) -> iam.Role:
        """Create IAM role for Lambda functions."""
        role = iam.Role(
            self,
            "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for Lambda functions in forecasting solution",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole"),
            ],
            inline_policies={
                "SageMakerInvoke": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "sagemaker:InvokeEndpoint",
                                "sagemaker:DescribeEndpoint",
                                "sagemaker:DescribeAutoMLJob",
                                "sagemaker:ListAutoMLJobs"
                            ],
                            resources=["*"]
                        )
                    ]
                ),
                "S3Access": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:PutObject",
                                "s3:ListBucket"
                            ],
                            resources=[
                                self.data_bucket.bucket_arn,
                                f"{self.data_bucket.bucket_arn}/*"
                            ]
                        )
                    ]
                ),
                "SNSPublish": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["sns:Publish"],
                            resources=["*"]
                        )
                    ]
                ),
                "CloudWatchMetrics": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "cloudwatch:PutMetricData",
                                "cloudwatch:GetMetricData",
                                "cloudwatch:ListMetrics"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )
        
        return role

    def _create_notification_topic(self, suffix: str) -> sns.Topic:
        """Create SNS topic for forecasting notifications."""
        topic = sns.Topic(
            self,
            "ForecastingNotifications",
            topic_name=f"automl-forecasting-notifications-{suffix}",
            display_name="AutoML Forecasting Notifications",
            description="Notifications for AutoML forecasting operations"
        )
        
        return topic

    def _create_forecast_api_function(self, suffix: str) -> lambda_.Function:
        """Create Lambda function for real-time forecasting API."""
        function = lambda_.Function(
            self,
            "ForecastAPIFunction",
            function_name=f"automl-forecast-api-{suffix}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_forecast_api_code()),
            timeout=Duration.seconds(30),
            memory_size=512,
            role=self.lambda_role,
            environment={
                "FORECAST_BUCKET": self.data_bucket.bucket_name,
                "SNS_TOPIC_ARN": self.notification_topic.topic_arn,
                "LOG_LEVEL": "INFO"
            },
            description="Real-time forecasting API using SageMaker AutoML endpoint",
            log_retention=logs.RetentionDays.ONE_MONTH
        )
        
        return function

    def _create_batch_processing_function(self, suffix: str) -> lambda_.Function:
        """Create Lambda function for batch forecasting operations."""
        function = lambda_.Function(
            self,
            "BatchProcessingFunction",
            function_name=f"automl-batch-forecast-{suffix}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_batch_processing_code()),
            timeout=Duration.minutes(15),
            memory_size=1024,
            role=self.lambda_role,
            environment={
                "FORECAST_BUCKET": self.data_bucket.bucket_name,
                "SNS_TOPIC_ARN": self.notification_topic.topic_arn,
                "LOG_LEVEL": "INFO"
            },
            description="Batch forecasting processing for large-scale operations",
            log_retention=logs.RetentionDays.ONE_MONTH
        )
        
        return function

    def _create_model_monitoring_function(self, suffix: str) -> lambda_.Function:
        """Create Lambda function for model monitoring and alerting."""
        function = lambda_.Function(
            self,
            "ModelMonitoringFunction",
            function_name=f"automl-model-monitoring-{suffix}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_monitoring_code()),
            timeout=Duration.minutes(5),
            memory_size=256,
            role=self.lambda_role,
            environment={
                "FORECAST_BUCKET": self.data_bucket.bucket_name,
                "SNS_TOPIC_ARN": self.notification_topic.topic_arn,
                "LOG_LEVEL": "INFO"
            },
            description="Model performance monitoring and alerting",
            log_retention=logs.RetentionDays.ONE_MONTH
        )
        
        return function

    def _create_api_gateway(self, suffix: str) -> apigw.RestApi:
        """Create API Gateway for external access to forecasting services."""
        api = apigw.RestApi(
            self,
            "ForecastingAPI",
            rest_api_name=f"automl-forecasting-api-{suffix}",
            description="REST API for AutoML forecasting services",
            default_cors_preflight_options=apigw.CorsOptions(
                allow_origins=apigw.Cors.ALL_ORIGINS,
                allow_methods=apigw.Cors.ALL_METHODS,
                allow_headers=["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key"]
            ),
            deploy_options=apigw.StageOptions(
                stage_name="prod",
                throttling_burst_limit=1000,
                throttling_rate_limit=500,
                logging_level=apigw.MethodLoggingLevel.INFO,
                data_trace_enabled=True,
                metrics_enabled=True
            )
        )
        
        # Create forecast resource and methods
        forecast_resource = api.root.add_resource("forecast")
        
        # Real-time forecast endpoint
        realtime_resource = forecast_resource.add_resource("realtime")
        realtime_integration = apigw.LambdaIntegration(
            self.forecast_api_function,
            request_templates={"application/json": '{"statusCode": "200"}'}
        )
        realtime_resource.add_method("POST", realtime_integration)
        
        # Batch forecast endpoint
        batch_resource = forecast_resource.add_resource("batch")
        batch_integration = apigw.LambdaIntegration(
            self.batch_processing_function,
            request_templates={"application/json": '{"statusCode": "200"}'}
        )
        batch_resource.add_method("POST", batch_integration)
        
        # Health check endpoint
        health_resource = api.root.add_resource("health")
        health_integration = apigw.MockIntegration(
            integration_responses=[
                apigw.IntegrationResponse(
                    status_code="200",
                    response_templates={"application/json": '{"status": "healthy", "timestamp": "$context.requestTime"}'}
                )
            ],
            request_templates={"application/json": '{"statusCode": 200}'}
        )
        health_resource.add_method(
            "GET",
            health_integration,
            method_responses=[apigw.MethodResponse(status_code="200")]
        )
        
        return api

    def _create_cloudwatch_monitoring(self, suffix: str) -> None:
        """Create CloudWatch dashboards and alarms for monitoring."""
        # Create dashboard
        dashboard = cloudwatch.Dashboard(
            self,
            "ForecastingDashboard",
            dashboard_name=f"AutoML-Forecasting-{suffix}",
            period_override=cloudwatch.PeriodOverride.AUTO
        )
        
        # Add widgets for Lambda metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Lambda Function Performance",
                left=[
                    self.forecast_api_function.metric_duration(),
                    self.batch_processing_function.metric_duration(),
                    self.model_monitoring_function.metric_duration()
                ],
                right=[
                    self.forecast_api_function.metric_errors(),
                    self.batch_processing_function.metric_errors(),
                    self.model_monitoring_function.metric_errors()
                ]
            )
        )
        
        # Add widget for API Gateway metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="API Gateway Metrics",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/ApiGateway",
                        metric_name="Count",
                        dimensions_map={"ApiName": self.api_gateway.rest_api_name}
                    )
                ],
                right=[
                    cloudwatch.Metric(
                        namespace="AWS/ApiGateway",
                        metric_name="4XXError",
                        dimensions_map={"ApiName": self.api_gateway.rest_api_name}
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/ApiGateway",
                        metric_name="5XXError",
                        dimensions_map={"ApiName": self.api_gateway.rest_api_name}
                    )
                ]
            )
        )
        
        # Create alarms
        # Lambda error rate alarm
        lambda_error_alarm = cloudwatch.Alarm(
            self,
            "LambdaErrorAlarm",
            alarm_name=f"AutoML-Lambda-Errors-{suffix}",
            alarm_description="High error rate in forecasting Lambda functions",
            metric=self.forecast_api_function.metric_errors(period=Duration.minutes(5)),
            threshold=5,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )
        lambda_error_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.notification_topic)
        )
        
        # API Gateway error rate alarm
        api_error_alarm = cloudwatch.Alarm(
            self,
            "APIGatewayErrorAlarm",
            alarm_name=f"AutoML-API-Errors-{suffix}",
            alarm_description="High error rate in API Gateway",
            metric=cloudwatch.Metric(
                namespace="AWS/ApiGateway",
                metric_name="5XXError",
                dimensions_map={"ApiName": self.api_gateway.rest_api_name},
                period=Duration.minutes(5),
                statistic="Sum"
            ),
            threshold=10,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )
        api_error_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.notification_topic)
        )

    def _create_eventbridge_rules(self) -> None:
        """Create EventBridge rules for automation."""
        # Rule for SageMaker job state changes
        sagemaker_rule = events.Rule(
            self,
            "SageMakerJobStateChange",
            description="Trigger when SageMaker AutoML job state changes",
            event_pattern=events.EventPattern(
                source=["aws.sagemaker"],
                detail_type=["SageMaker AutoML Job State Change"],
                detail={
                    "AutoMLJobStatus": ["Completed", "Failed", "Stopped"]
                }
            )
        )
        sagemaker_rule.add_target(
            targets.LambdaFunction(self.model_monitoring_function)
        )
        
        # Scheduled rule for batch processing
        batch_schedule = events.Rule(
            self,
            "BatchForecastSchedule",
            description="Scheduled batch forecasting execution",
            schedule=events.Schedule.cron(hour="2", minute="0")  # Daily at 2 AM
        )
        batch_schedule.add_target(
            targets.LambdaFunction(self.batch_processing_function)
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        CfnOutput(
            self,
            "DataBucketName",
            value=self.data_bucket.bucket_name,
            description="S3 bucket name for forecasting data and artifacts"
        )
        
        CfnOutput(
            self,
            "SageMakerRoleArn",
            value=self.sagemaker_role.role_arn,
            description="IAM role ARN for SageMaker AutoML operations"
        )
        
        CfnOutput(
            self,
            "APIGatewayURL",
            value=self.api_gateway.url,
            description="API Gateway URL for forecasting services"
        )
        
        CfnOutput(
            self,
            "ForecastAPIEndpoint",
            value=f"{self.api_gateway.url}forecast/realtime",
            description="Real-time forecasting API endpoint"
        )
        
        CfnOutput(
            self,
            "BatchForecastEndpoint",
            value=f"{self.api_gateway.url}forecast/batch",
            description="Batch forecasting API endpoint"
        )
        
        CfnOutput(
            self,
            "NotificationTopicArn",
            value=self.notification_topic.topic_arn,
            description="SNS topic ARN for forecasting notifications"
        )
        
        CfnOutput(
            self,
            "CloudWatchDashboardURL",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name=AutoML-Forecasting-{self.node.try_get_context('uniqueSuffix') or 'demo'}",
            description="CloudWatch dashboard URL for monitoring"
        )

    def _get_forecast_api_code(self) -> str:
        """Return Lambda code for real-time forecasting API."""
        return '''
import json
import boto3
import os
import logging
from datetime import datetime
from typing import Dict, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function to provide real-time forecasting API.
    
    Expected request body:
    {
        "item_id": "string",
        "forecast_horizon": 14,
        "endpoint_name": "string"
    }
    """
    try:
        # Parse request
        if 'body' in event:
            body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
        else:
            body = event
            
        item_id = body.get('item_id')
        forecast_horizon = int(body.get('forecast_horizon', 14))
        endpoint_name = body.get('endpoint_name')
        
        if not item_id:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'item_id is required'})
            }
            
        if not endpoint_name:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'endpoint_name is required'})
            }
        
        # Initialize SageMaker runtime
        runtime = boto3.client('sagemaker-runtime')
        
        # Prepare inference request (simplified for demo)
        inference_data = {
            'instances': [
                {
                    'start': '2023-01-01',
                    'target': [100 + i * 0.1 for i in range(365)],  # Mock historical data
                    'item_id': item_id
                }
            ],
            'configuration': {
                'num_samples': 100,
                'output_types': ['mean', 'quantiles'],
                'quantiles': ['0.1', '0.5', '0.9']
            }
        }
        
        logger.info(f"Making prediction for item: {item_id}")
        
        # Make prediction
        response = runtime.invoke_endpoint(
            EndpointName=endpoint_name,
            ContentType='application/json',
            Body=json.dumps(inference_data)
        )
        
        # Parse response
        result = json.loads(response['Body'].read().decode())
        
        # Format response
        forecast_response = {
            'item_id': item_id,
            'forecast_horizon': forecast_horizon,
            'forecast': result.get('predictions', [{}])[0],
            'generated_at': datetime.now().isoformat(),
            'model_type': 'SageMaker AutoML',
            'confidence_intervals': True,
            'status': 'success'
        }
        
        logger.info(f"Successfully generated forecast for item: {item_id}")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(forecast_response)
        }
        
    except Exception as e:
        logger.error(f"Error generating forecast: {str(e)}", exc_info=True)
        
        # Send notification on error
        try:
            sns = boto3.client('sns')
            sns.publish(
                TopicArn=os.environ.get('SNS_TOPIC_ARN'),
                Subject='Forecasting API Error',
                Message=f'Error in real-time forecasting: {str(e)}'
            )
        except:
            pass
            
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': str(e),
                'message': 'Internal server error',
                'status': 'error'
            })
        }
'''

    def _get_batch_processing_code(self) -> str:
        """Return Lambda code for batch forecasting processing."""
        return '''
import json
import boto3
import os
import logging
import pandas as pd
from datetime import datetime
from typing import Dict, Any, List

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function for batch forecasting operations.
    
    Expected request body:
    {
        "input_prefix": "batch-input/",
        "output_prefix": "batch-output/",
        "endpoint_name": "string"
    }
    """
    try:
        # Parse request
        if 'body' in event:
            body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
        else:
            body = event
            
        input_prefix = body.get('input_prefix', 'batch-input/')
        output_prefix = body.get('output_prefix', 'batch-output/')
        endpoint_name = body.get('endpoint_name')
        
        if not endpoint_name:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'endpoint_name is required'})
            }
        
        bucket_name = os.environ['FORECAST_BUCKET']
        
        # Initialize AWS clients
        s3 = boto3.client('s3')
        runtime = boto3.client('sagemaker-runtime')
        
        logger.info(f"Starting batch processing from {input_prefix}")
        
        # List input files
        response = s3.list_objects_v2(
            Bucket=bucket_name,
            Prefix=input_prefix
        )
        
        if 'Contents' not in response:
            return {
                'statusCode': 404,
                'body': json.dumps({'error': 'No input files found'})
            }
        
        batch_results = []
        processed_items = 0
        
        for obj in response['Contents']:
            if obj['Key'].endswith('.csv'):
                logger.info(f"Processing {obj['Key']}")
                
                # Download and read file
                local_file = f"/tmp/{obj['Key'].split('/')[-1]}"
                s3.download_file(bucket_name, obj['Key'], local_file)
                
                try:
                    data = pd.read_csv(local_file)
                    
                    # Process each unique item
                    for item_id in data['item_id'].unique()[:10]:  # Limit for demo
                        item_data = data[data['item_id'] == item_id]
                        
                        # Prepare inference request
                        inference_data = {
                            'instances': [
                                {
                                    'start': item_data['timestamp'].iloc[0] if 'timestamp' in item_data else '2023-01-01',
                                    'target': item_data['target_value'].tolist() if 'target_value' in item_data else [100] * 30,
                                    'item_id': item_id
                                }
                            ],
                            'configuration': {
                                'num_samples': 100,
                                'output_types': ['mean', 'quantiles'],
                                'quantiles': ['0.1', '0.5', '0.9']
                            }
                        }
                        
                        try:
                            # Make prediction
                            pred_response = runtime.invoke_endpoint(
                                EndpointName=endpoint_name,
                                ContentType='application/json',
                                Body=json.dumps(inference_data)
                            )
                            
                            result = json.loads(pred_response['Body'].read().decode())
                            
                            batch_results.append({
                                'item_id': item_id,
                                'forecast': result,
                                'timestamp': datetime.now().isoformat(),
                                'source_file': obj['Key']
                            })
                            
                            processed_items += 1
                            
                        except Exception as e:
                            logger.error(f"Error processing {item_id}: {e}")
                            continue
                
                except Exception as e:
                    logger.error(f"Error reading file {obj['Key']}: {e}")
                    continue
                
                finally:
                    # Clean up local file
                    if os.path.exists(local_file):
                        os.remove(local_file)
        
        # Save batch results
        output_file = f"batch_forecasts_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        output_path = f"/tmp/{output_file}"
        
        with open(output_path, 'w') as f:
            json.dump(batch_results, f, indent=2)
        
        # Upload results to S3
        s3.upload_file(output_path, bucket_name, f"{output_prefix}{output_file}")
        
        # Clean up
        os.remove(output_path)
        
        logger.info(f"Batch processing completed. Processed {processed_items} items")
        
        # Send notification
        sns = boto3.client('sns')
        sns.publish(
            TopicArn=os.environ.get('SNS_TOPIC_ARN'),
            Subject='Batch Forecasting Completed',
            Message=f'Batch forecasting completed successfully. Processed {processed_items} items. Results saved to {output_prefix}{output_file}'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Batch processing completed successfully',
                'processed_items': processed_items,
                'output_file': f"{output_prefix}{output_file}",
                'status': 'success'
            })
        }
        
    except Exception as e:
        logger.error(f"Error in batch processing: {str(e)}", exc_info=True)
        
        # Send error notification
        try:
            sns = boto3.client('sns')
            sns.publish(
                TopicArn=os.environ.get('SNS_TOPIC_ARN'),
                Subject='Batch Forecasting Error',
                Message=f'Error in batch forecasting: {str(e)}'
            )
        except:
            pass
            
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Batch processing failed',
                'status': 'error'
            })
        }
'''

    def _get_monitoring_code(self) -> str:
        """Return Lambda code for model monitoring."""
        return '''
import json
import boto3
import os
import logging
from datetime import datetime, timedelta
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function for model performance monitoring and alerting.
    """
    try:
        logger.info("Starting model monitoring check")
        
        # Initialize AWS clients
        sagemaker = boto3.client('sagemaker')
        cloudwatch = boto3.client('cloudwatch')
        sns = boto3.client('sns')
        
        # Check for recent AutoML jobs
        response = sagemaker.list_auto_ml_jobs(
            SortBy='CreationTime',
            SortOrder='Descending',
            MaxResults=10
        )
        
        monitoring_results = {
            'timestamp': datetime.now().isoformat(),
            'automl_jobs': [],
            'endpoints': [],
            'alerts': []
        }
        
        # Monitor AutoML jobs
        for job in response.get('AutoMLJobSummaries', []):
            job_name = job['AutoMLJobName']
            job_status = job['AutoMLJobStatus']
            
            job_details = sagemaker.describe_auto_ml_job_v2(AutoMLJobName=job_name)
            
            job_info = {
                'name': job_name,
                'status': job_status,
                'creation_time': job['CreationTime'].isoformat(),
                'end_time': job.get('EndTime', '').isoformat() if job.get('EndTime') else None
            }
            
            # Check for failed jobs
            if job_status == 'Failed':
                failure_reason = job_details.get('FailureReason', 'Unknown error')
                monitoring_results['alerts'].append({
                    'type': 'automl_job_failed',
                    'message': f"AutoML job {job_name} failed: {failure_reason}",
                    'severity': 'high'
                })
                
                # Send SNS notification
                sns.publish(
                    TopicArn=os.environ.get('SNS_TOPIC_ARN'),
                    Subject='AutoML Job Failed',
                    Message=f"AutoML job {job_name} failed with reason: {failure_reason}"
                )
            
            # Check for completed jobs
            elif job_status == 'Completed':
                best_candidate = job_details.get('BestCandidate', {})
                if best_candidate:
                    objective_metric = best_candidate.get('FinalAutoMLJobObjectiveMetric', {})
                    metric_value = objective_metric.get('Value', 0)
                    
                    job_info['best_candidate'] = best_candidate.get('CandidateName', '')
                    job_info['objective_score'] = metric_value
                    
                    # Alert on poor performance (MAPE > 20%)
                    if metric_value > 0.2:
                        monitoring_results['alerts'].append({
                            'type': 'poor_model_performance',
                            'message': f"AutoML job {job_name} achieved MAPE of {metric_value:.2%}, which exceeds 20% threshold",
                            'severity': 'medium'
                        })
            
            monitoring_results['automl_jobs'].append(job_info)
        
        # Monitor SageMaker endpoints
        endpoints_response = sagemaker.list_endpoints(
            SortBy='CreationTime',
            SortOrder='Descending',
            MaxResults=10
        )
        
        for endpoint in endpoints_response.get('Endpoints', []):
            endpoint_name = endpoint['EndpointName']
            endpoint_status = endpoint['EndpointStatus']
            
            endpoint_info = {
                'name': endpoint_name,
                'status': endpoint_status,
                'creation_time': endpoint['CreationTime'].isoformat()
            }
            
            # Check endpoint health
            if endpoint_status not in ['InService']:
                monitoring_results['alerts'].append({
                    'type': 'endpoint_unhealthy',
                    'message': f"Endpoint {endpoint_name} is not in service (status: {endpoint_status})",
                    'severity': 'high'
                })
            else:
                # Check endpoint metrics
                end_time = datetime.now()
                start_time = end_time - timedelta(hours=1)
                
                try:
                    # Get invocation count
                    invocation_metrics = cloudwatch.get_metric_statistics(
                        Namespace='AWS/SageMaker/Endpoints',
                        MetricName='Invocations',
                        Dimensions=[
                            {'Name': 'EndpointName', 'Value': endpoint_name}
                        ],
                        StartTime=start_time,
                        EndTime=end_time,
                        Period=3600,
                        Statistics=['Sum']
                    )
                    
                    # Get error count
                    error_metrics = cloudwatch.get_metric_statistics(
                        Namespace='AWS/SageMaker/Endpoints',
                        MetricName='InvocationErrors',
                        Dimensions=[
                            {'Name': 'EndpointName', 'Value': endpoint_name}
                        ],
                        StartTime=start_time,
                        EndTime=end_time,
                        Period=3600,
                        Statistics=['Sum']
                    )
                    
                    invocations = sum([dp['Sum'] for dp in invocation_metrics.get('Datapoints', [])])
                    errors = sum([dp['Sum'] for dp in error_metrics.get('Datapoints', [])])
                    
                    endpoint_info['invocations_last_hour'] = invocations
                    endpoint_info['errors_last_hour'] = errors
                    
                    # Calculate error rate
                    if invocations > 0:
                        error_rate = errors / invocations
                        endpoint_info['error_rate'] = error_rate
                        
                        # Alert on high error rate
                        if error_rate > 0.05:  # 5% threshold
                            monitoring_results['alerts'].append({
                                'type': 'high_error_rate',
                                'message': f"Endpoint {endpoint_name} has error rate of {error_rate:.2%} (threshold: 5%)",
                                'severity': 'medium'
                            })
                
                except Exception as e:
                    logger.warning(f"Could not retrieve metrics for endpoint {endpoint_name}: {e}")
            
            monitoring_results['endpoints'].append(endpoint_info)
        
        # Save monitoring results to S3
        bucket_name = os.environ['FORECAST_BUCKET']
        s3 = boto3.client('s3')
        
        monitoring_file = f"monitoring/monitoring_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        s3.put_object(
            Bucket=bucket_name,
            Key=monitoring_file,
            Body=json.dumps(monitoring_results, indent=2),
            ContentType='application/json'
        )
        
        # Send summary notification if there are alerts
        if monitoring_results['alerts']:
            alert_summary = f"Found {len(monitoring_results['alerts'])} alerts:\\n"
            for alert in monitoring_results['alerts']:
                alert_summary += f"- {alert['severity'].upper()}: {alert['message']}\\n"
            
            sns.publish(
                TopicArn=os.environ.get('SNS_TOPIC_ARN'),
                Subject='Model Monitoring Alerts',
                Message=alert_summary
            )
        
        logger.info(f"Monitoring completed. Found {len(monitoring_results['alerts'])} alerts")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Monitoring completed successfully',
                'alerts_count': len(monitoring_results['alerts']),
                'automl_jobs_checked': len(monitoring_results['automl_jobs']),
                'endpoints_checked': len(monitoring_results['endpoints']),
                'report_location': monitoring_file,
                'status': 'success'
            })
        }
        
    except Exception as e:
        logger.error(f"Error in monitoring: {str(e)}", exc_info=True)
        
        # Send error notification
        try:
            sns = boto3.client('sns')
            sns.publish(
                TopicArn=os.environ.get('SNS_TOPIC_ARN'),
                Subject='Model Monitoring Error',
                Message=f'Error in model monitoring: {str(e)}'
            )
        except:
            pass
            
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Monitoring failed',
                'status': 'error'
            })
        }
'''


class AutoMLForecastingApp(cdk.App):
    """CDK application for AutoML forecasting solution."""
    
    def __init__(self):
        super().__init__()
        
        # Get configuration from context
        env = cdk.Environment(
            account=os.environ.get('CDK_DEFAULT_ACCOUNT'),
            region=os.environ.get('CDK_DEFAULT_REGION', 'us-east-1')
        )
        
        # Create the main stack
        AutoMLForecastingStack(
            self,
            "AutoMLForecastingStack",
            env=env,
            description="Complete AutoML forecasting solution using SageMaker AutoML"
        )


# Create and synthesize the app
app = AutoMLForecastingApp()
app.synth()