#!/usr/bin/env python3
"""
CDK Python Application for Advanced API Gateway Deployment Strategies
Implements blue-green and canary deployment patterns with monitoring.
"""

import os
import json
from typing import Dict, Any, Optional
from constructs import Construct
from aws_cdk import (
    App,
    Stack,
    StackProps,
    Duration,
    CfnOutput,
    RemovalPolicy,
    aws_lambda as _lambda,
    aws_apigateway as apigw,
    aws_iam as iam,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cw_actions,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
)


class AdvancedApiGatewayDeploymentStack(Stack):
    """
    CDK Stack for Advanced API Gateway Deployment Strategies
    
    This stack implements blue-green and canary deployment patterns using:
    - API Gateway with stages and canary deployments
    - Lambda functions for blue and green environments
    - CloudWatch monitoring and alarms
    - SNS notifications for deployment events
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        # Create IAM role for Lambda functions
        self.lambda_role = self._create_lambda_role()
        
        # Create Lambda functions for blue and green environments
        self.blue_function = self._create_blue_lambda()
        self.green_function = self._create_green_lambda()
        
        # Create API Gateway
        self.api = self._create_api_gateway()
        
        # Create API Gateway resource and method
        self.hello_resource = self._create_api_resources()
        
        # Create deployments and stages
        self.blue_deployment = self._create_blue_deployment()
        self.green_deployment = self._create_green_deployment()
        
        # Create CloudWatch monitoring
        self.monitoring = self._create_monitoring()
        
        # Create SNS topic for notifications
        self.notification_topic = self._create_notification_topic()
        
        # Create CloudWatch alarms
        self._create_alarms()
        
        # Create stack outputs
        self._create_outputs()

    def _create_lambda_role(self) -> iam.Role:
        """Create IAM role for Lambda functions with necessary permissions."""
        return iam.Role(
            self,
            "ApiDeploymentLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for API Gateway deployment Lambda functions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
            inline_policies={
                "CloudWatchLogs": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents",
                            ],
                            resources=["arn:aws:logs:*:*:*"],
                        )
                    ]
                )
            },
        )

    def _create_blue_lambda(self) -> _lambda.Function:
        """Create Lambda function for the blue environment (production)."""
        return _lambda.Function(
            self,
            "BlueLambdaFunction",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=self.lambda_role,
            code=_lambda.Code.from_inline("""
import json
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Blue environment Lambda handler - represents current production version
    """
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'X-Environment': 'blue'
        },
        'body': json.dumps({
            'message': 'Hello from Blue environment!',
            'version': 'v1.0.0',
            'environment': 'blue',
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'request_id': context.aws_request_id,
            'function_name': context.function_name,
            'function_version': context.function_version,
            'memory_limit': context.memory_limit_in_mb
        })
    }
            """),
            description="Blue environment API function - production version",
            timeout=Duration.seconds(30),
            memory_size=256,
            environment={
                "ENVIRONMENT": "blue",
                "VERSION": "v1.0.0",
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            dead_letter_queue_enabled=True,
            reserved_concurrent_executions=100,
        )

    def _create_green_lambda(self) -> _lambda.Function:
        """Create Lambda function for the green environment (new version)."""
        return _lambda.Function(
            self,
            "GreenLambdaFunction",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=self.lambda_role,
            code=_lambda.Code.from_inline("""
import json
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Green environment Lambda handler - represents new version with enhanced features
    """
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'X-Environment': 'green',
            'X-New-Feature': 'enhanced-response'
        },
        'body': json.dumps({
            'message': 'Hello from Green environment!',
            'version': 'v2.0.0',
            'environment': 'green',
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'request_id': context.aws_request_id,
            'function_name': context.function_name,
            'function_version': context.function_version,
            'memory_limit': context.memory_limit_in_mb,
            'new_feature': 'Enhanced response format with additional metadata',
            'performance_improvements': [
                'Optimized response time',
                'Better error handling',
                'Enhanced logging'
            ]
        })
    }
            """),
            description="Green environment API function - new version with enhancements",
            timeout=Duration.seconds(30),
            memory_size=256,
            environment={
                "ENVIRONMENT": "green",
                "VERSION": "v2.0.0",
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            dead_letter_queue_enabled=True,
            reserved_concurrent_executions=100,
        )

    def _create_api_gateway(self) -> apigw.RestApi:
        """Create API Gateway with proper configuration for deployment strategies."""
        return apigw.RestApi(
            self,
            "AdvancedDeploymentApi",
            rest_api_name="advanced-deployment-api",
            description="API Gateway with advanced deployment strategies (blue-green and canary)",
            deploy=False,  # We'll handle deployments manually
            endpoint_configuration=apigw.EndpointConfiguration(
                types=[apigw.EndpointType.REGIONAL]
            ),
            cloud_watch_role=True,
            cloud_watch_role_removal_policy=RemovalPolicy.DESTROY,
            deploy_options=apigw.StageOptions(
                stage_name="prod",
                throttling_rate_limit=1000,
                throttling_burst_limit=2000,
                logging_level=apigw.MethodLoggingLevel.INFO,
                data_trace_enabled=True,
                metrics_enabled=True,
                tracing_enabled=True,
            ),
            default_cors_preflight_options=apigw.CorsOptions(
                allow_origins=apigw.Cors.ALL_ORIGINS,
                allow_methods=apigw.Cors.ALL_METHODS,
                allow_headers=["Content-Type", "X-Amz-Date", "Authorization"],
            ),
            policy=iam.PolicyDocument(
                statements=[
                    iam.PolicyStatement(
                        effect=iam.Effect.ALLOW,
                        principals=[iam.AnyPrincipal()],
                        actions=["execute-api:Invoke"],
                        resources=["*"],
                    )
                ]
            ),
        )

    def _create_api_resources(self) -> apigw.Resource:
        """Create API Gateway resources and methods."""
        # Create /hello resource
        hello_resource = self.api.root.add_resource("hello")
        
        # Create GET method with blue environment integration (initial)
        blue_integration = apigw.LambdaIntegration(
            handler=self.blue_function,
            proxy=True,
            integration_responses=[
                apigw.IntegrationResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": "'*'"
                    },
                )
            ],
        )
        
        hello_resource.add_method(
            "GET",
            integration=blue_integration,
            method_responses=[
                apigw.MethodResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": True
                    },
                )
            ],
        )
        
        return hello_resource

    def _create_blue_deployment(self) -> apigw.Deployment:
        """Create deployment for blue environment."""
        return apigw.Deployment(
            self,
            "BlueDeployment",
            api=self.api,
            description="Blue environment deployment (production)",
        )

    def _create_green_deployment(self) -> apigw.Deployment:
        """Create deployment for green environment."""
        # Create a separate integration for green environment
        green_integration = apigw.LambdaIntegration(
            handler=self.green_function,
            proxy=True,
        )
        
        # Note: In a real scenario, you would update the integration
        # This is a simplified version for demonstration
        return apigw.Deployment(
            self,
            "GreenDeployment",
            api=self.api,
            description="Green environment deployment (new version)",
        )

    def _create_monitoring(self) -> Dict[str, Any]:
        """Create CloudWatch monitoring resources."""
        # Create log group for API Gateway
        api_log_group = logs.LogGroup(
            self,
            "ApiGatewayLogGroup",
            log_group_name=f"/aws/apigateway/{self.api.rest_api_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Create custom metrics for blue/green environments
        blue_metric = cloudwatch.Metric(
            namespace="AWS/ApiGateway",
            metric_name="Count",
            dimensions_map={
                "ApiName": self.api.rest_api_name,
                "Stage": "production",
                "Environment": "blue",
            },
            statistic="Sum",
            period=Duration.minutes(5),
        )
        
        green_metric = cloudwatch.Metric(
            namespace="AWS/ApiGateway",
            metric_name="Count",
            dimensions_map={
                "ApiName": self.api.rest_api_name,
                "Stage": "production",
                "Environment": "green",
            },
            statistic="Sum",
            period=Duration.minutes(5),
        )
        
        return {
            "log_group": api_log_group,
            "blue_metric": blue_metric,
            "green_metric": green_metric,
        }

    def _create_notification_topic(self) -> sns.Topic:
        """Create SNS topic for deployment notifications."""
        topic = sns.Topic(
            self,
            "DeploymentNotificationTopic",
            topic_name="api-deployment-notifications",
            display_name="API Deployment Notifications",
        )
        
        # Add email subscription if email is provided via context
        email = self.node.try_get_context("notification_email")
        if email:
            topic.add_subscription(
                sns_subscriptions.EmailSubscription(email_address=email)
            )
        
        return topic

    def _create_alarms(self) -> None:
        """Create CloudWatch alarms for monitoring deployment health."""
        # 4XX Error Rate Alarm
        four_xx_alarm = cloudwatch.Alarm(
            self,
            "FourXXErrorAlarm",
            alarm_name=f"{self.api.rest_api_name}-4xx-errors",
            alarm_description="API Gateway 4XX error rate is too high",
            metric=cloudwatch.Metric(
                namespace="AWS/ApiGateway",
                metric_name="4XXError",
                dimensions_map={
                    "ApiName": self.api.rest_api_name,
                    "Stage": "production",
                },
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=10,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        # 5XX Error Rate Alarm
        five_xx_alarm = cloudwatch.Alarm(
            self,
            "FiveXXErrorAlarm",
            alarm_name=f"{self.api.rest_api_name}-5xx-errors",
            alarm_description="API Gateway 5XX error rate is too high",
            metric=cloudwatch.Metric(
                namespace="AWS/ApiGateway",
                metric_name="5XXError",
                dimensions_map={
                    "ApiName": self.api.rest_api_name,
                    "Stage": "production",
                },
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=5,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        # High Latency Alarm
        latency_alarm = cloudwatch.Alarm(
            self,
            "HighLatencyAlarm",
            alarm_name=f"{self.api.rest_api_name}-high-latency",
            alarm_description="API Gateway latency is too high",
            metric=cloudwatch.Metric(
                namespace="AWS/ApiGateway",
                metric_name="Latency",
                dimensions_map={
                    "ApiName": self.api.rest_api_name,
                    "Stage": "production",
                },
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=5000,  # 5 seconds
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        # Add SNS actions to alarms
        four_xx_alarm.add_alarm_action(
            cw_actions.SnsAction(self.notification_topic)
        )
        five_xx_alarm.add_alarm_action(
            cw_actions.SnsAction(self.notification_topic)
        )
        latency_alarm.add_alarm_action(
            cw_actions.SnsAction(self.notification_topic)
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "ApiGatewayUrl",
            value=self.api.url,
            description="API Gateway endpoint URL",
            export_name=f"{self.stack_name}-ApiGatewayUrl",
        )
        
        CfnOutput(
            self,
            "ApiGatewayId",
            value=self.api.rest_api_id,
            description="API Gateway ID",
            export_name=f"{self.stack_name}-ApiGatewayId",
        )
        
        CfnOutput(
            self,
            "BlueLambdaArn",
            value=self.blue_function.function_arn,
            description="Blue Lambda function ARN",
            export_name=f"{self.stack_name}-BlueLambdaArn",
        )
        
        CfnOutput(
            self,
            "GreenLambdaArn",
            value=self.green_function.function_arn,
            description="Green Lambda function ARN",
            export_name=f"{self.stack_name}-GreenLambdaArn",
        )
        
        CfnOutput(
            self,
            "NotificationTopicArn",
            value=self.notification_topic.topic_arn,
            description="SNS topic ARN for deployment notifications",
            export_name=f"{self.stack_name}-NotificationTopicArn",
        )
        
        CfnOutput(
            self,
            "ProductionEndpoint",
            value=f"{self.api.url}hello",
            description="Production API endpoint for testing",
            export_name=f"{self.stack_name}-ProductionEndpoint",
        )


class DeploymentUtilitiesStack(Stack):
    """
    Additional stack for deployment utilities and automation tools.
    Contains Lambda functions for automated deployment management.
    """
    
    def __init__(self, scope: Construct, construct_id: str, api_stack: AdvancedApiGatewayDeploymentStack, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        self.api_stack = api_stack
        
        # Create deployment automation Lambda
        self.deployment_automation = self._create_deployment_automation_lambda()
        
        # Create canary management Lambda
        self.canary_management = self._create_canary_management_lambda()
        
        # Create outputs
        self._create_outputs()

    def _create_deployment_automation_lambda(self) -> _lambda.Function:
        """Create Lambda function for automated deployment management."""
        return _lambda.Function(
            self,
            "DeploymentAutomationLambda",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline("""
import json
import boto3
import os
from typing import Dict, Any

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    '''
    Automated deployment management Lambda function
    Handles canary deployments and blue-green swaps
    '''
    
    api_gateway = boto3.client('apigateway')
    cloudwatch = boto3.client('cloudwatch')
    
    try:
        action = event.get('action')
        api_id = event.get('api_id')
        stage_name = event.get('stage_name', 'production')
        
        if action == 'create_canary':
            return create_canary_deployment(api_gateway, event)
        elif action == 'promote_canary':
            return promote_canary_deployment(api_gateway, event)
        elif action == 'rollback_canary':
            return rollback_canary_deployment(api_gateway, event)
        elif action == 'check_health':
            return check_deployment_health(cloudwatch, event)
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Invalid action specified'})
            }
    
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def create_canary_deployment(api_gateway, event):
    '''Create a canary deployment with specified traffic percentage'''
    api_id = event['api_id']
    deployment_id = event['deployment_id']
    traffic_percentage = event.get('traffic_percentage', 10)
    
    response = api_gateway.create_deployment(
        restApiId=api_id,
        stageName='production',
        description=f'Canary deployment - {traffic_percentage}% traffic',
        canarySettings={
            'percentTraffic': traffic_percentage,
            'deploymentId': deployment_id,
            'useStageCache': False
        }
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Canary deployment created with {traffic_percentage}% traffic',
            'deployment_id': response['id']
        })
    }

def promote_canary_deployment(api_gateway, event):
    '''Promote canary deployment to full production'''
    api_id = event['api_id']
    deployment_id = event['deployment_id']
    
    # Remove canary settings and promote to full production
    api_gateway.update_stage(
        restApiId=api_id,
        stageName='production',
        patchOps=[
            {
                'op': 'replace',
                'path': '/deploymentId',
                'value': deployment_id
            },
            {
                'op': 'remove',
                'path': '/canarySettings'
            }
        ]
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Canary deployment promoted to production',
            'deployment_id': deployment_id
        })
    }

def rollback_canary_deployment(api_gateway, event):
    '''Rollback canary deployment'''
    api_id = event['api_id']
    
    # Remove canary settings
    api_gateway.update_stage(
        restApiId=api_id,
        stageName='production',
        patchOps=[
            {
                'op': 'remove',
                'path': '/canarySettings'
            }
        ]
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Canary deployment rolled back'
        })
    }

def check_deployment_health(cloudwatch, event):
    '''Check deployment health metrics'''
    api_name = event['api_name']
    
    # Get error rate metrics
    error_metrics = cloudwatch.get_metric_statistics(
        Namespace='AWS/ApiGateway',
        MetricName='5XXError',
        Dimensions=[
            {'Name': 'ApiName', 'Value': api_name},
            {'Name': 'Stage', 'Value': 'production'}
        ],
        StartTime=datetime.utcnow() - timedelta(minutes=10),
        EndTime=datetime.utcnow(),
        Period=300,
        Statistics=['Sum']
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'health_status': 'healthy' if len(error_metrics['Datapoints']) == 0 else 'unhealthy',
            'error_count': sum(point['Sum'] for point in error_metrics['Datapoints'])
        })
    }
            """),
            description="Lambda function for automated deployment management",
            timeout=Duration.seconds(60),
            memory_size=256,
            environment={
                "API_ID": self.api_stack.api.rest_api_id,
            },
            role=self._create_deployment_lambda_role(),
        )

    def _create_canary_management_lambda(self) -> _lambda.Function:
        """Create Lambda function for canary deployment management."""
        return _lambda.Function(
            self,
            "CanaryManagementLambda",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline("""
import json
import boto3
import os
from datetime import datetime, timedelta
from typing import Dict, Any

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    '''
    Canary deployment management Lambda function
    Handles gradual traffic shifting and monitoring
    '''
    
    api_gateway = boto3.client('apigateway')
    cloudwatch = boto3.client('cloudwatch')
    
    try:
        action = event.get('action')
        
        if action == 'increase_traffic':
            return increase_canary_traffic(api_gateway, event)
        elif action == 'monitor_health':
            return monitor_canary_health(cloudwatch, event)
        elif action == 'auto_promote':
            return auto_promote_canary(api_gateway, cloudwatch, event)
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Invalid action specified'})
            }
    
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def increase_canary_traffic(api_gateway, event):
    '''Gradually increase canary traffic percentage'''
    api_id = event['api_id']
    target_percentage = event['target_percentage']
    
    api_gateway.update_stage(
        restApiId=api_id,
        stageName='production',
        patchOps=[
            {
                'op': 'replace',
                'path': '/canarySettings/percentTraffic',
                'value': str(target_percentage)
            }
        ]
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Canary traffic increased to {target_percentage}%',
            'timestamp': datetime.utcnow().isoformat()
        })
    }

def monitor_canary_health(cloudwatch, event):
    '''Monitor canary deployment health metrics'''
    api_name = event['api_name']
    
    # Get metrics for the last 10 minutes
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(minutes=10)
    
    # Check error rates
    error_response = cloudwatch.get_metric_statistics(
        Namespace='AWS/ApiGateway',
        MetricName='5XXError',
        Dimensions=[
            {'Name': 'ApiName', 'Value': api_name},
            {'Name': 'Stage', 'Value': 'production'}
        ],
        StartTime=start_time,
        EndTime=end_time,
        Period=300,
        Statistics=['Sum']
    )
    
    # Check latency
    latency_response = cloudwatch.get_metric_statistics(
        Namespace='AWS/ApiGateway',
        MetricName='Latency',
        Dimensions=[
            {'Name': 'ApiName', 'Value': api_name},
            {'Name': 'Stage', 'Value': 'production'}
        ],
        StartTime=start_time,
        EndTime=end_time,
        Period=300,
        Statistics=['Average']
    )
    
    error_count = sum(point['Sum'] for point in error_response['Datapoints'])
    avg_latency = sum(point['Average'] for point in latency_response['Datapoints']) / len(latency_response['Datapoints']) if latency_response['Datapoints'] else 0
    
    health_status = 'healthy'
    if error_count > 5:
        health_status = 'unhealthy'
    elif avg_latency > 5000:
        health_status = 'degraded'
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'health_status': health_status,
            'error_count': error_count,
            'average_latency': avg_latency,
            'timestamp': datetime.utcnow().isoformat()
        })
    }

def auto_promote_canary(api_gateway, cloudwatch, event):
    '''Automatically promote canary based on health metrics'''
    api_id = event['api_id']
    api_name = event['api_name']
    deployment_id = event['deployment_id']
    
    # Check health first
    health_check = monitor_canary_health(cloudwatch, event)
    health_data = json.loads(health_check['body'])
    
    if health_data['health_status'] == 'healthy':
        # Promote to full production
        api_gateway.update_stage(
            restApiId=api_id,
            stageName='production',
            patchOps=[
                {
                    'op': 'replace',
                    'path': '/deploymentId',
                    'value': deployment_id
                },
                {
                    'op': 'remove',
                    'path': '/canarySettings'
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Canary automatically promoted to production',
                'health_status': health_data['health_status'],
                'timestamp': datetime.utcnow().isoformat()
            })
        }
    else:
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Canary promotion skipped due to health issues',
                'health_status': health_data['health_status'],
                'timestamp': datetime.utcnow().isoformat()
            })
        }
            """),
            description="Lambda function for canary deployment management",
            timeout=Duration.seconds(60),
            memory_size=256,
            environment={
                "API_ID": self.api_stack.api.rest_api_id,
                "API_NAME": self.api_stack.api.rest_api_name,
            },
            role=self._create_deployment_lambda_role(),
        )

    def _create_deployment_lambda_role(self) -> iam.Role:
        """Create IAM role for deployment Lambda functions."""
        return iam.Role(
            self,
            "DeploymentLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for deployment management Lambda functions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
            inline_policies={
                "ApiGatewayManagement": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "apigateway:GET",
                                "apigateway:POST",
                                "apigateway:PUT",
                                "apigateway:DELETE",
                                "apigateway:PATCH",
                            ],
                            resources=["*"],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "cloudwatch:GetMetricStatistics",
                                "cloudwatch:ListMetrics",
                                "cloudwatch:PutMetricData",
                            ],
                            resources=["*"],
                        ),
                    ]
                )
            },
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for utility functions."""
        CfnOutput(
            self,
            "DeploymentAutomationLambdaArn",
            value=self.deployment_automation.function_arn,
            description="Deployment automation Lambda function ARN",
            export_name=f"{self.stack_name}-DeploymentAutomationLambdaArn",
        )
        
        CfnOutput(
            self,
            "CanaryManagementLambdaArn",
            value=self.canary_management.function_arn,
            description="Canary management Lambda function ARN",
            export_name=f"{self.stack_name}-CanaryManagementLambdaArn",
        )


def main():
    """Main function to create and deploy the CDK application."""
    app = App()
    
    # Get environment variables
    env_vars = {
        "account": os.environ.get("CDK_DEFAULT_ACCOUNT"),
        "region": os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
    }
    
    # Create main API Gateway deployment stack
    api_stack = AdvancedApiGatewayDeploymentStack(
        app,
        "AdvancedApiGatewayDeploymentStack",
        env=env_vars,
        description="Advanced API Gateway deployment strategies with blue-green and canary patterns",
    )
    
    # Create deployment utilities stack
    utilities_stack = DeploymentUtilitiesStack(
        app,
        "DeploymentUtilitiesStack",
        api_stack=api_stack,
        env=env_vars,
        description="Deployment utilities and automation tools",
    )
    
    # Add dependencies
    utilities_stack.add_dependency(api_stack)
    
    # Add tags to all resources
    app.node.set_context("@aws-cdk/core:enableStackNameDuplicates", True)
    
    # Synth the app
    app.synth()


if __name__ == "__main__":
    main()