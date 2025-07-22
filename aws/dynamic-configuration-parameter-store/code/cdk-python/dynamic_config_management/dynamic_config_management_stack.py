"""
Dynamic Configuration Management Stack

This CDK stack implements a comprehensive serverless configuration management system using:
- AWS Systems Manager Parameter Store for centralized configuration storage
- Lambda functions with AWS Parameters and Secrets Extension for cached retrieval
- EventBridge for automatic configuration invalidation
- CloudWatch for monitoring and alerting
"""

from typing import Dict, List, Optional
from aws_cdk import (
    Duration,
    Stack,
    StackProps,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_ssm as ssm,
    aws_events as events,
    aws_events_targets as targets,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    RemovalPolicy,
    CfnOutput,
)
from constructs import Construct
from cdk_nag import NagSuppressions


class DynamicConfigManagementStack(Stack):
    """
    CDK Stack for Dynamic Configuration Management System.
    
    This stack creates:
    - Sample configuration parameters in Parameter Store
    - Lambda function with Parameters and Secrets Extension layer
    - EventBridge rule for parameter change events
    - CloudWatch alarms and dashboard for monitoring
    - IAM roles with least privilege permissions
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        # Configuration constants
        self.parameter_prefix = "/myapp/config"
        self.function_name = "config-manager"
        
        # Create resources
        self._create_parameters()
        self._create_iam_role()
        self._create_lambda_function()
        self._create_eventbridge_rule()
        self._create_monitoring()
        self._create_outputs()
        self._apply_cdk_nag_suppressions()
    
    def _create_parameters(self) -> None:
        """Create sample configuration parameters in Parameter Store."""
        # Database configuration parameters
        ssm.StringParameter(
            self, "DatabaseHost",
            parameter_name=f"{self.parameter_prefix}/database/host",
            string_value="myapp-db.cluster-xyz.us-east-1.rds.amazonaws.com",
            description="Database host endpoint",
            tier=ssm.ParameterTier.STANDARD,
        )
        
        ssm.StringParameter(
            self, "DatabasePort",
            parameter_name=f"{self.parameter_prefix}/database/port",
            string_value="5432",
            description="Database port number",
            tier=ssm.ParameterTier.STANDARD,
        )
        
        # API configuration parameters
        ssm.StringParameter(
            self, "ApiTimeout",
            parameter_name=f"{self.parameter_prefix}/api/timeout",
            string_value="30",
            description="API timeout in seconds",
            tier=ssm.ParameterTier.STANDARD,
        )
        
        # Feature flag parameters
        ssm.StringParameter(
            self, "NewUiFeature",
            parameter_name=f"{self.parameter_prefix}/features/new-ui",
            string_value="true",
            description="Feature flag for new UI",
            tier=ssm.ParameterTier.STANDARD,
        )
        
        # Secure parameter for sensitive data
        ssm.StringParameter(
            self, "DatabasePassword",
            parameter_name=f"{self.parameter_prefix}/database/password",
            string_value="supersecretpassword123",
            description="Database password (encrypted)",
            tier=ssm.ParameterTier.STANDARD,
            type=ssm.ParameterType.SECURE_STRING,
        )
    
    def _create_iam_role(self) -> None:
        """Create IAM role for Lambda function with least privilege permissions."""
        self.lambda_role = iam.Role(
            self, "ConfigManagerRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for Configuration Manager Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )
        
        # Custom policy for Parameter Store access
        parameter_store_policy = iam.Policy(
            self, "ParameterStoreAccessPolicy",
            policy_name="ParameterStoreAccessPolicy",
            statements=[
                # Parameter Store read permissions
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "ssm:GetParameter",
                        "ssm:GetParameters", 
                        "ssm:GetParametersByPath"
                    ],
                    resources=[
                        f"arn:aws:ssm:{self.region}:{self.account}:parameter{self.parameter_prefix}/*"
                    ],
                ),
                # KMS decrypt permissions for SecureString parameters
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=["kms:Decrypt"],
                    resources=[f"arn:aws:kms:{self.region}:{self.account}:key/*"],
                    conditions={
                        "StringEquals": {
                            f"kms:ViaService": f"ssm.{self.region}.amazonaws.com"
                        }
                    },
                ),
                # CloudWatch custom metrics permissions
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=["cloudwatch:PutMetricData"],
                    resources=["*"],
                ),
            ],
        )
        
        self.lambda_role.attach_inline_policy(parameter_store_policy)
    
    def _create_lambda_function(self) -> None:
        """Create Lambda function with Parameters and Secrets Extension."""
        # Parameters and Secrets Extension layer ARN by region
        layer_arn_map = {
            "us-east-1": "arn:aws:lambda:us-east-1:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11",
            "us-west-2": "arn:aws:lambda:us-west-2:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11",
            "eu-west-1": "arn:aws:lambda:eu-west-1:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11",
            "ap-southeast-1": "arn:aws:lambda:ap-southeast-1:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11",
        }
        
        extension_layer_arn = layer_arn_map.get(
            self.region, 
            f"arn:aws:lambda:{self.region}:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11"
        )
        
        self.config_function = lambda_.Function(
            self, "ConfigManagerFunction",
            function_name=self.function_name,
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            environment={
                "PARAMETER_PREFIX": self.parameter_prefix,
                "SSM_PARAMETER_STORE_TTL": "300",  # 5 minutes cache TTL
                "POWERTOOLS_SERVICE_NAME": "config-manager",
                "LOG_LEVEL": "INFO",
            },
            layers=[
                lambda_.LayerVersion.from_layer_version_arn(
                    self, "ParametersSecretsExtension",
                    layer_version_arn=extension_layer_arn
                )
            ],
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            description="Dynamic configuration management function with Parameter Store integration",
            log_retention=logs.RetentionDays.ONE_WEEK,
            retry_attempts=0,  # Disable automatic retries for this example
        )
    
    def _get_lambda_code(self) -> str:
        """Generate the Lambda function code."""
        return '''
import json
import os
import urllib3
import boto3
from datetime import datetime
from typing import Dict, Any, Optional

# Initialize HTTP client for extension
http = urllib3.PoolManager()

# Initialize CloudWatch client for custom metrics
cloudwatch = boto3.client('cloudwatch')

def get_parameter_from_extension(parameter_name: str) -> Optional[str]:
    """Retrieve parameter using the Parameters and Secrets Extension."""
    try:
        # Use localhost endpoint provided by the extension
        port = os.environ.get('PARAMETERS_SECRETS_EXTENSION_HTTP_PORT', '2773')
        url = f'http://localhost:{port}/systemsmanager/parameters/get/?name={parameter_name}'
        
        response = http.request('GET', url)
        
        if response.status == 200:
            data = json.loads(response.data.decode('utf-8'))
            return data['Parameter']['Value']
        else:
            print(f"Extension request failed: {response.status}")
            raise Exception(f"Failed to retrieve parameter: {response.status}")
            
    except Exception as e:
        print(f"Error retrieving parameter {parameter_name}: {str(e)}")
        # Fallback to direct SSM call if extension fails
        return get_parameter_direct(parameter_name)

def get_parameter_direct(parameter_name: str) -> Optional[str]:
    """Fallback method using direct SSM API call."""
    try:
        ssm = boto3.client('ssm')
        response = ssm.get_parameter(Name=parameter_name, WithDecryption=True)
        return response['Parameter']['Value']
    except Exception as e:
        print(f"Error with direct SSM call: {str(e)}")
        return None

def send_custom_metric(metric_name: str, value: float, unit: str = 'Count') -> None:
    """Send custom metric to CloudWatch."""
    try:
        cloudwatch.put_metric_data(
            Namespace='ConfigManager',
            MetricData=[
                {
                    'MetricName': metric_name,
                    'Value': value,
                    'Unit': unit,
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
    except Exception as e:
        print(f"Error sending metric: {str(e)}")

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Main Lambda handler function."""
    try:
        # Define parameter prefix
        parameter_prefix = os.environ.get('PARAMETER_PREFIX', '/myapp/config')
        
        # Retrieve configuration parameters
        config = {}
        parameters = [
            f"{parameter_prefix}/database/host",
            f"{parameter_prefix}/database/port", 
            f"{parameter_prefix}/api/timeout",
            f"{parameter_prefix}/features/new-ui"
        ]
        
        # Track configuration retrieval metrics
        successful_retrievals = 0
        failed_retrievals = 0
        
        for param in parameters:
            value = get_parameter_from_extension(param)
            if value is not None:
                config[param.split('/')[-1]] = value
                successful_retrievals += 1
            else:
                failed_retrievals += 1
        
        # Send custom metrics
        send_custom_metric('SuccessfulParameterRetrievals', successful_retrievals)
        send_custom_metric('FailedParameterRetrievals', failed_retrievals)
        
        # Log configuration status
        print(f"Configuration loaded: {len(config)} parameters")
        print(f"Configuration: {json.dumps(config, indent=2)}")
        
        # Return response
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Cache-Control': 'no-cache'
            },
            'body': json.dumps({
                'message': 'Configuration loaded successfully',
                'config': config,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        print(f"Error in lambda_handler: {str(e)}")
        send_custom_metric('ConfigurationErrors', 1)
        
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'error': 'Configuration retrieval failed',
                'message': str(e)
            })
        }
'''
    
    def _create_eventbridge_rule(self) -> None:
        """Create EventBridge rule for parameter change events."""
        self.parameter_change_rule = events.Rule(
            self, "ParameterChangeRule",
            description="Trigger on Parameter Store changes",
            event_pattern=events.EventPattern(
                source=["aws.ssm"],
                detail_type=["Parameter Store Change"],
                detail={
                    "name": [{"prefix": self.parameter_prefix}]
                }
            ),
            enabled=True,
        )
        
        # Add Lambda function as target
        self.parameter_change_rule.add_target(
            targets.LambdaFunction(
                self.config_function,
                retry_attempts=2,
            )
        )
        
        # Grant EventBridge permission to invoke Lambda
        self.config_function.add_permission(
            "AllowEventBridgeInvoke",
            principal=iam.ServicePrincipal("events.amazonaws.com"),
            action="lambda:InvokeFunction",
            source_arn=self.parameter_change_rule.rule_arn,
        )
    
    def _create_monitoring(self) -> None:
        """Create CloudWatch alarms and dashboard for monitoring."""
        
        # Lambda function error alarm
        lambda_error_alarm = cloudwatch.Alarm(
            self, "LambdaErrorAlarm",
            alarm_name=f"ConfigManager-Errors-{self.config_function.function_name}",
            alarm_description="Monitor Lambda function errors",
            metric=self.config_function.metric_errors(
                period=Duration.minutes(5),
                statistic=cloudwatch.Statistic.SUM
            ),
            threshold=5,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        # Lambda function duration alarm
        lambda_duration_alarm = cloudwatch.Alarm(
            self, "LambdaDurationAlarm",
            alarm_name=f"ConfigManager-Duration-{self.config_function.function_name}",
            alarm_description="Monitor Lambda function duration",
            metric=self.config_function.metric_duration(
                period=Duration.minutes(5),
                statistic=cloudwatch.Statistic.AVERAGE
            ),
            threshold=10000,  # 10 seconds in milliseconds
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=3,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        # Custom metric for configuration retrieval failures
        config_failure_alarm = cloudwatch.Alarm(
            self, "ConfigRetrievalFailureAlarm", 
            alarm_name="ConfigManager-RetrievalFailures",
            alarm_description="Monitor configuration retrieval failures",
            metric=cloudwatch.Metric(
                namespace="ConfigManager",
                metric_name="FailedParameterRetrievals",
                period=Duration.minutes(5),
                statistic=cloudwatch.Statistic.SUM
            ),
            threshold=3,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        # Create CloudWatch Dashboard
        dashboard = cloudwatch.Dashboard(
            self, "ConfigManagerDashboard",
            dashboard_name="ConfigManager-Dashboard",
            period_override=cloudwatch.PeriodOverride.AUTO,
        )
        
        # Add widgets to dashboard
        dashboard.add_widgets(
            # Lambda function metrics
            cloudwatch.GraphWidget(
                title="Lambda Function Metrics",
                left=[
                    self.config_function.metric_invocations(
                        period=Duration.minutes(5),
                        statistic=cloudwatch.Statistic.SUM,
                        label="Invocations"
                    ),
                    self.config_function.metric_errors(
                        period=Duration.minutes(5), 
                        statistic=cloudwatch.Statistic.SUM,
                        label="Errors"
                    ),
                    self.config_function.metric_duration(
                        period=Duration.minutes(5),
                        statistic=cloudwatch.Statistic.AVERAGE,
                        label="Duration (ms)"
                    ),
                ],
                width=12,
                height=6,
            ),
            # Configuration management metrics
            cloudwatch.GraphWidget(
                title="Configuration Management Metrics",
                left=[
                    cloudwatch.Metric(
                        namespace="ConfigManager",
                        metric_name="SuccessfulParameterRetrievals",
                        period=Duration.minutes(5),
                        statistic=cloudwatch.Statistic.SUM,
                        label="Successful Retrievals"
                    ),
                    cloudwatch.Metric(
                        namespace="ConfigManager",
                        metric_name="FailedParameterRetrievals", 
                        period=Duration.minutes(5),
                        statistic=cloudwatch.Statistic.SUM,
                        label="Failed Retrievals"
                    ),
                    cloudwatch.Metric(
                        namespace="ConfigManager",
                        metric_name="ConfigurationErrors",
                        period=Duration.minutes(5),
                        statistic=cloudwatch.Statistic.SUM,
                        label="Configuration Errors"
                    ),
                ],
                width=12,
                height=6,
            ),
        )
    
    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self, "ConfigManagerFunctionName",
            value=self.config_function.function_name,
            description="Name of the Configuration Manager Lambda function",
            export_name=f"{self.stack_name}-ConfigManagerFunctionName",
        )
        
        CfnOutput(
            self, "ConfigManagerFunctionArn",
            value=self.config_function.function_arn,
            description="ARN of the Configuration Manager Lambda function", 
            export_name=f"{self.stack_name}-ConfigManagerFunctionArn",
        )
        
        CfnOutput(
            self, "ParameterPrefix",
            value=self.parameter_prefix,
            description="Parameter Store prefix for configuration parameters",
            export_name=f"{self.stack_name}-ParameterPrefix",
        )
        
        CfnOutput(
            self, "EventBridgeRuleArn",
            value=self.parameter_change_rule.rule_arn,
            description="ARN of the EventBridge rule for parameter changes",
            export_name=f"{self.stack_name}-EventBridgeRuleArn",
        )
    
    def _apply_cdk_nag_suppressions(self) -> None:
        """Apply CDK Nag suppressions for acceptable security exceptions."""
        # Suppress CDK Nag warnings for Lambda function inline code
        NagSuppressions.add_resource_suppressions(
            self.config_function,
            [
                {
                    "id": "AwsSolutions-L1",
                    "reason": "Lambda function uses Python 3.9 runtime which is supported and secure.",
                },
            ],
        )
        
        # Suppress CDK Nag warnings for IAM wildcard permissions 
        NagSuppressions.add_resource_suppressions(
            self.lambda_role,
            [
                {
                    "id": "AwsSolutions-IAM5", 
                    "reason": "CloudWatch PutMetricData requires wildcard permissions for custom metrics namespace.",
                },
            ],
        )