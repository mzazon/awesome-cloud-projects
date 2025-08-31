#!/usr/bin/env python3
"""
CDK Application for Simple Configuration Management with Parameter Store and CloudShell

This CDK application creates AWS Systems Manager Parameter Store parameters
for centralized configuration management, demonstrating different parameter types
and hierarchical organization patterns.

Author: AWS CDK Recipe Generator
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_ssm as ssm,
    aws_kms as kms,
    CfnOutput,
    Tags,
)
from constructs import Construct
from typing import Dict, List


class ParameterStoreConfigStack(Stack):
    """
    Stack for creating Parameter Store configuration parameters.
    
    This stack demonstrates different parameter types:
    - String: Standard configuration values
    - SecureString: Encrypted sensitive data
    - StringList: Comma-separated value lists
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Get configuration from context or use defaults
        app_name = self.node.try_get_context("app_name") or "myapp"
        environment = self.node.try_get_context("environment") or "development"
        
        # Create parameter prefix for hierarchical organization
        param_prefix = f"/{app_name}/{environment}"

        # Create KMS key for SecureString parameters (optional - can use default)
        parameter_kms_key = kms.Key(
            self, "ParameterStoreKey",
            description=f"KMS key for {app_name} Parameter Store SecureString parameters",
            enable_key_rotation=True,
        )
        
        # Create alias for the KMS key
        kms.Alias(
            self, "ParameterStoreKeyAlias",
            alias_name=f"alias/{app_name}-parameter-store",
            target_key=parameter_kms_key,
        )

        # Standard String Parameters
        self._create_standard_parameters(param_prefix, app_name)
        
        # SecureString Parameters (encrypted)
        self._create_secure_parameters(param_prefix, app_name, parameter_kms_key)
        
        # StringList Parameters (comma-separated values)
        self._create_stringlist_parameters(param_prefix, app_name)

        # Add tags to all resources in this stack
        Tags.of(self).add("Application", app_name)
        Tags.of(self).add("Environment", environment)
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("Recipe", "simple-configuration-management-parameter-store-cloudshell")

        # Outputs for verification and reference
        self._create_outputs(param_prefix, parameter_kms_key)

    def _create_standard_parameters(self, param_prefix: str, app_name: str) -> None:
        """
        Create standard String parameters for non-sensitive configuration data.
        
        Args:
            param_prefix: The hierarchical prefix for parameters
            app_name: Application name for descriptions
        """
        # Database configuration parameters
        ssm.StringParameter(
            self, "DatabaseUrlParameter",
            parameter_name=f"{param_prefix}/database/url",
            string_value="postgresql://db.example.com:5432/myapp",
            description=f"Database connection URL for {app_name}",
            tier=ssm.ParameterTier.STANDARD,
        )

        ssm.StringParameter(
            self, "DatabasePortParameter",
            parameter_name=f"{param_prefix}/database/port",
            string_value="5432",
            description=f"Database port for {app_name}",
            tier=ssm.ParameterTier.STANDARD,
        )

        # Application configuration parameters
        ssm.StringParameter(
            self, "EnvironmentParameter",
            parameter_name=f"{param_prefix}/config/environment",
            string_value="development",
            description="Application environment setting",
            tier=ssm.ParameterTier.STANDARD,
        )

        ssm.StringParameter(
            self, "DebugModeParameter",
            parameter_name=f"{param_prefix}/features/debug-mode",
            string_value="true",
            description="Debug mode feature flag",
            tier=ssm.ParameterTier.STANDARD,
        )

        ssm.StringParameter(
            self, "LogLevelParameter",
            parameter_name=f"{param_prefix}/config/log-level",
            string_value="INFO",
            description="Application logging level",
            tier=ssm.ParameterTier.STANDARD,
        )

    def _create_secure_parameters(self, param_prefix: str, app_name: str, kms_key: kms.Key) -> None:
        """
        Create SecureString parameters for sensitive configuration data.
        
        Args:
            param_prefix: The hierarchical prefix for parameters
            app_name: Application name for descriptions
            kms_key: KMS key for encryption
        """
        # API key parameter (encrypted)
        ssm.StringParameter(
            self, "ApiKeyParameter",
            parameter_name=f"{param_prefix}/api/third-party-key",
            string_value="api-key-12345-secret-value",
            description=f"Third-party API key for {app_name}",
            type=ssm.ParameterType.SECURE_STRING,
            key_id=kms_key.key_id,
            tier=ssm.ParameterTier.STANDARD,
        )

        # Database password parameter (encrypted)
        ssm.StringParameter(
            self, "DatabasePasswordParameter",
            parameter_name=f"{param_prefix}/database/password",
            string_value="super-secure-password-123",
            description=f"Database password for {app_name}",
            type=ssm.ParameterType.SECURE_STRING,
            key_id=kms_key.key_id,
            tier=ssm.ParameterTier.STANDARD,
        )

        # JWT secret parameter (encrypted)
        ssm.StringParameter(
            self, "JwtSecretParameter",
            parameter_name=f"{param_prefix}/auth/jwt-secret",
            string_value="jwt-super-secret-key-for-signing-tokens",
            description=f"JWT signing secret for {app_name}",
            type=ssm.ParameterType.SECURE_STRING,
            key_id=kms_key.key_id,
            tier=ssm.ParameterTier.STANDARD,
        )

    def _create_stringlist_parameters(self, param_prefix: str, app_name: str) -> None:
        """
        Create StringList parameters for comma-separated value lists.
        
        Args:
            param_prefix: The hierarchical prefix for parameters
            app_name: Application name for descriptions
        """
        # CORS allowed origins list
        ssm.StringListParameter(
            self, "AllowedOriginsParameter",
            parameter_name=f"{param_prefix}/api/allowed-origins",
            string_list_value=[
                "https://app.example.com",
                "https://admin.example.com",
                "https://mobile.example.com"
            ],
            description=f"CORS allowed origins for {app_name}",
            tier=ssm.ParameterTier.STANDARD,
        )

        # Supported regions list
        ssm.StringListParameter(
            self, "SupportedRegionsParameter",
            parameter_name=f"{param_prefix}/deployment/regions",
            string_list_value=[
                "us-east-1",
                "us-west-2",
                "eu-west-1"
            ],
            description="Supported deployment regions",
            tier=ssm.ParameterTier.STANDARD,
        )

        # Feature flags list
        ssm.StringListParameter(
            self, "EnabledFeaturesParameter",
            parameter_name=f"{param_prefix}/features/enabled",
            string_list_value=[
                "user-authentication",
                "data-encryption",
                "audit-logging",
                "rate-limiting"
            ],
            description=f"Enabled features for {app_name}",
            tier=ssm.ParameterTier.STANDARD,
        )

    def _create_outputs(self, param_prefix: str, kms_key: kms.Key) -> None:
        """
        Create CloudFormation outputs for verification and reference.
        
        Args:
            param_prefix: The hierarchical prefix for parameters
            kms_key: KMS key used for encryption
        """
        CfnOutput(
            self, "ParameterPrefix",
            value=param_prefix,
            description="Parameter Store prefix for this application",
            export_name=f"{self.stack_name}-parameter-prefix"
        )

        CfnOutput(
            self, "KmsKeyId",
            value=kms_key.key_id,
            description="KMS Key ID used for SecureString parameters",
            export_name=f"{self.stack_name}-kms-key-id"
        )

        CfnOutput(
            self, "KmsKeyArn",
            value=kms_key.key_arn,
            description="KMS Key ARN used for SecureString parameters",
            export_name=f"{self.stack_name}-kms-key-arn"
        )

        # Sample CLI commands for parameter retrieval
        CfnOutput(
            self, "SampleGetParameterCommand",
            value=f"aws ssm get-parameter --name '{param_prefix}/database/url' --query 'Parameter.Value' --output text",
            description="Sample AWS CLI command to retrieve a parameter"
        )

        CfnOutput(
            self, "SampleGetParametersByPathCommand",
            value=f"aws ssm get-parameters-by-path --path '{param_prefix}' --recursive --with-decryption --output table",
            description="Sample AWS CLI command to retrieve all parameters by path"
        )


class ConfigurationManagementApp(cdk.App):
    """
    CDK Application for Parameter Store Configuration Management.
    
    This application creates a complete Parameter Store configuration
    demonstrating different parameter types and best practices.
    """

    def __init__(self) -> None:
        super().__init__()

        # Create the main stack
        ParameterStoreConfigStack(
            self, "ParameterStoreConfigStack",
            description="Simple Configuration Management with Parameter Store and CloudShell",
            env=cdk.Environment(
                account=self.node.try_get_context("account"),
                region=self.node.try_get_context("region")
            )
        )


def main() -> None:
    """Main entry point for the CDK application."""
    app = ConfigurationManagementApp()
    app.synth()


if __name__ == "__main__":
    main()