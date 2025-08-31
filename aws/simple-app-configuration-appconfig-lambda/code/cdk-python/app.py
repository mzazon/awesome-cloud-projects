#!/usr/bin/env python3
"""
CDK Python application for Simple Application Configuration with AppConfig and Lambda

This application creates:
- AWS AppConfig application, environment, and configuration profile
- Lambda function with AppConfig integration
- IAM roles with appropriate permissions
- Configuration deployment with immediate strategy
"""

import os
from typing import Dict, Any

from aws_cdk import (
    App,
    Stack,
    StackProps,
    Duration,
    CfnOutput,
    aws_appconfig as appconfig,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_logs as logs,
)
from constructs import Construct


class SimpleAppConfigStack(Stack):
    """
    CDK Stack for Simple Application Configuration with AppConfig and Lambda
    
    This stack demonstrates how to use AWS AppConfig for dynamic configuration
    management with Lambda functions, including proper IAM permissions and
    the AppConfig Lambda extension layer.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resources
        unique_suffix = self.node.try_get_context("unique_suffix") or "demo"
        
        # Create AppConfig Application
        app_config_app = self._create_appconfig_application(unique_suffix)
        
        # Create AppConfig Environment
        environment = self._create_appconfig_environment(app_config_app)
        
        # Create Configuration Profile
        config_profile = self._create_configuration_profile(app_config_app)
        
        # Create initial configuration version
        config_version = self._create_configuration_version(
            app_config_app, config_profile
        )
        
        # Create deployment strategy
        deployment_strategy = self._create_deployment_strategy(unique_suffix)
        
        # Create IAM role for Lambda
        lambda_role = self._create_lambda_role(unique_suffix)
        
        # Create Lambda function
        lambda_function = self._create_lambda_function(
            unique_suffix, lambda_role, app_config_app, environment, config_profile
        )
        
        # Create configuration deployment
        self._create_configuration_deployment(
            app_config_app, environment, config_profile, 
            deployment_strategy, config_version
        )
        
        # Create stack outputs
        self._create_outputs(
            app_config_app, environment, config_profile, 
            lambda_function, deployment_strategy
        )

    def _create_appconfig_application(self, unique_suffix: str) -> appconfig.CfnApplication:
        """Create AppConfig application"""
        return appconfig.CfnApplication(
            self, "AppConfigApplication",
            name=f"simple-config-app-{unique_suffix}",
            description="Simple configuration management demo application"
        )

    def _create_appconfig_environment(self, app: appconfig.CfnApplication) -> appconfig.CfnEnvironment:
        """Create AppConfig environment"""
        return appconfig.CfnEnvironment(
            self, "DevelopmentEnvironment",
            application_id=app.ref,
            name="development",
            description="Development environment for configuration testing"
        )

    def _create_configuration_profile(self, app: appconfig.CfnApplication) -> appconfig.CfnConfigurationProfile:
        """Create AppConfig configuration profile"""
        return appconfig.CfnConfigurationProfile(
            self, "ConfigurationProfile",
            application_id=app.ref,
            name="app-settings",
            description="Application settings configuration profile",
            location_uri="hosted"
        )

    def _create_configuration_version(
        self, 
        app: appconfig.CfnApplication, 
        profile: appconfig.CfnConfigurationProfile
    ) -> appconfig.CfnHostedConfigurationVersion:
        """Create initial configuration version with sample data"""
        
        # Initial configuration data
        config_data = {
            "database": {
                "max_connections": 100,
                "timeout_seconds": 30,
                "retry_attempts": 3
            },
            "features": {
                "enable_logging": True,
                "enable_metrics": True,
                "debug_mode": False
            },
            "api": {
                "rate_limit": 1000,
                "cache_ttl": 300
            }
        }
        
        import json
        return appconfig.CfnHostedConfigurationVersion(
            self, "InitialConfigVersion",
            application_id=app.ref,
            configuration_profile_id=profile.ref,
            content=json.dumps(config_data, indent=2),
            content_type="application/json",
            description="Initial configuration with default settings"
        )

    def _create_deployment_strategy(self, unique_suffix: str) -> appconfig.CfnDeploymentStrategy:
        """Create deployment strategy for immediate deployment"""
        return appconfig.CfnDeploymentStrategy(
            self, "ImmediateDeploymentStrategy",
            name=f"immediate-deployment-{unique_suffix}",
            description="Immediate deployment strategy for testing",
            deployment_duration_in_minutes=0,
            final_bake_time_in_minutes=0,
            growth_factor=100,
            growth_type="LINEAR",
            replicate_to="NONE"
        )

    def _create_lambda_role(self, unique_suffix: str) -> iam.Role:
        """Create IAM role for Lambda function with AppConfig permissions"""
        
        # Create custom policy for AppConfig access
        appconfig_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "appconfig:StartConfigurationSession",
                        "appconfig:GetLatestConfiguration"
                    ],
                    resources=["*"]
                )
            ]
        )
        
        return iam.Role(
            self, "LambdaAppConfigRole",
            role_name=f"lambda-appconfig-role-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "AppConfigAccessPolicy": appconfig_policy
            },
            description="IAM role for Lambda function to access AppConfig"
        )

    def _create_lambda_function(
        self, 
        unique_suffix: str, 
        role: iam.Role,
        app: appconfig.CfnApplication,
        environment: appconfig.CfnEnvironment,
        profile: appconfig.CfnConfigurationProfile
    ) -> lambda_.Function:
        """Create Lambda function with AppConfig integration"""
        
        # Lambda function code
        lambda_code = '''
import json
import urllib3
import os

def lambda_handler(event, context):
    """
    Lambda function handler that retrieves configuration from AppConfig
    and demonstrates usage of dynamic configuration values.
    """
    # AppConfig extension endpoint (local to Lambda execution environment)
    appconfig_endpoint = 'http://localhost:2772'
    
    # AppConfig parameters from environment variables
    application_id = os.environ.get('APPCONFIG_APPLICATION_ID')
    environment_id = os.environ.get('APPCONFIG_ENVIRONMENT_ID')
    configuration_profile_id = os.environ.get('APPCONFIG_CONFIGURATION_PROFILE_ID')
    
    try:
        # Create HTTP connection to AppConfig extension
        http = urllib3.PoolManager()
        
        # Retrieve configuration from AppConfig
        config_url = f"{appconfig_endpoint}/applications/{application_id}/environments/{environment_id}/configurations/{configuration_profile_id}"
        response = http.request('GET', config_url)
        
        if response.status == 200:
            config_data = json.loads(response.data.decode('utf-8'))
            
            # Use configuration in application logic
            max_connections = config_data.get('database', {}).get('max_connections', 50)
            enable_logging = config_data.get('features', {}).get('enable_logging', False)
            rate_limit = config_data.get('api', {}).get('rate_limit', 500)
            debug_mode = config_data.get('features', {}).get('debug_mode', False)
            
            # Log configuration usage if logging is enabled
            if enable_logging:
                print(f"Configuration loaded - Max connections: {max_connections}, Rate limit: {rate_limit}, Debug: {debug_mode}")
            
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json'
                },
                'body': json.dumps({
                    'message': 'Configuration loaded successfully',
                    'timestamp': context.aws_request_id,
                    'config_summary': {
                        'database_max_connections': max_connections,
                        'logging_enabled': enable_logging,
                        'api_rate_limit': rate_limit,
                        'debug_mode': debug_mode
                    },
                    'function_info': {
                        'function_name': context.function_name,
                        'function_version': context.function_version,
                        'remaining_time_ms': context.get_remaining_time_in_millis()
                    }
                })
            }
        else:
            error_msg = f"Failed to retrieve configuration: HTTP {response.status}"
            print(error_msg)
            return {
                'statusCode': 500,
                'headers': {
                    'Content-Type': 'application/json'
                },
                'body': json.dumps({
                    'error': 'Configuration retrieval failed',
                    'details': error_msg
                })
            }
            
    except Exception as e:
        error_msg = f"Error retrieving configuration: {str(e)}"
        print(error_msg)
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'details': error_msg
            })
        }
'''

        # Create Lambda function
        lambda_function = lambda_.Function(
            self, "ConfigDemoFunction",
            function_name=f"config-demo-{unique_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=role,
            timeout=Duration.seconds(30),
            memory_size=256,
            environment={
                "APPCONFIG_APPLICATION_ID": app.ref,
                "APPCONFIG_ENVIRONMENT_ID": environment.ref,
                "APPCONFIG_CONFIGURATION_PROFILE_ID": profile.ref
            },
            description="Lambda function demonstrating AppConfig integration",
            log_retention=logs.RetentionDays.ONE_WEEK
        )
        
        # Add AppConfig Lambda extension layer
        # Use region-specific ARN for the AppConfig extension
        lambda_function.add_layers(
            lambda_.LayerVersion.from_layer_version_arn(
                self, "AppConfigExtensionLayer",
                f"arn:aws:lambda:{self.region}:027255383542:layer:AWS-AppConfig-Extension:207"
            )
        )
        
        return lambda_function

    def _create_configuration_deployment(
        self,
        app: appconfig.CfnApplication,
        environment: appconfig.CfnEnvironment,
        profile: appconfig.CfnConfigurationProfile,
        strategy: appconfig.CfnDeploymentStrategy,
        version: appconfig.CfnHostedConfigurationVersion
    ) -> appconfig.CfnDeployment:
        """Create configuration deployment"""
        return appconfig.CfnDeployment(
            self, "InitialConfigDeployment",
            application_id=app.ref,
            environment_id=environment.ref,
            deployment_strategy_id=strategy.ref,
            configuration_profile_id=profile.ref,
            configuration_version=version.ref,
            description="Initial configuration deployment"
        )

    def _create_outputs(
        self,
        app: appconfig.CfnApplication,
        environment: appconfig.CfnEnvironment,
        profile: appconfig.CfnConfigurationProfile,
        lambda_function: lambda_.Function,
        strategy: appconfig.CfnDeploymentStrategy
    ) -> None:
        """Create CloudFormation outputs for key resources"""
        
        CfnOutput(
            self, "AppConfigApplicationId",
            description="AppConfig Application ID",
            value=app.ref
        )
        
        CfnOutput(
            self, "AppConfigEnvironmentId", 
            description="AppConfig Environment ID",
            value=environment.ref
        )
        
        CfnOutput(
            self, "ConfigurationProfileId",
            description="Configuration Profile ID",
            value=profile.ref
        )
        
        CfnOutput(
            self, "LambdaFunctionName",
            description="Lambda Function Name", 
            value=lambda_function.function_name
        )
        
        CfnOutput(
            self, "LambdaFunctionArn",
            description="Lambda Function ARN",
            value=lambda_function.function_arn
        )
        
        CfnOutput(
            self, "DeploymentStrategyId",
            description="Deployment Strategy ID",
            value=strategy.ref
        )
        
        # Test command output
        CfnOutput(
            self, "TestCommand",
            description="AWS CLI command to test the Lambda function",
            value=f"aws lambda invoke --function-name {lambda_function.function_name} --payload '{{}}' response.json && cat response.json"
        )


def main() -> None:
    """Main application entry point"""
    app = App()
    
    # Create the stack with a unique suffix from context or default
    unique_suffix = app.node.try_get_context("unique_suffix")
    if not unique_suffix:
        import random
        import string
        unique_suffix = ''.join(random.choices(string.ascii_lowercase + string.digits, k=6))
    
    SimpleAppConfigStack(
        app, 
        "SimpleAppConfigStack",
        stack_name=f"simple-appconfig-stack-{unique_suffix}",
        description="Simple Application Configuration with AppConfig and Lambda",
        env={
            'account': os.environ.get('CDK_DEFAULT_ACCOUNT'),
            'region': os.environ.get('CDK_DEFAULT_REGION', 'us-east-1')
        }
    )
    
    app.synth()


if __name__ == "__main__":
    main()