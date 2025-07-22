#!/usr/bin/env python3
"""
AWS CDK Application for Secrets Manager Recipe
This application deploys a complete secrets management solution using:
- AWS Secrets Manager with KMS encryption
- Lambda function for custom rotation
- IAM roles and policies
- CloudWatch monitoring
- Cross-account access policies
"""

import os
from aws_cdk import (
    App,
    Environment,
    Stack,
    StackProps,
    Duration,
    RemovalPolicy,
    aws_secretsmanager as secretsmanager,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_kms as kms,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    CfnOutput,
    Tags
)
from typing import Dict, Any
import json
from constructs import Construct


class SecretsManagerStack(Stack):
    """
    CDK Stack for AWS Secrets Manager implementation
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.secret_name = f"demo-db-credentials-{self.node.addr[:6]}"
        self.lambda_function_name = f"secret-rotation-{self.node.addr[:6]}"
        
        # Create KMS key for encryption
        self.kms_key = self._create_kms_key()
        
        # Create IAM role for Lambda rotation function
        self.lambda_role = self._create_lambda_role()
        
        # Create the database secret
        self.secret = self._create_database_secret()
        
        # Create Lambda rotation function
        self.rotation_function = self._create_rotation_function()
        
        # Configure automatic rotation
        self._configure_automatic_rotation()
        
        # Create CloudWatch monitoring
        self._create_monitoring()
        
        # Create cross-account access policy
        self._create_cross_account_policy()
        
        # Create stack outputs
        self._create_outputs()

    def _create_kms_key(self) -> kms.Key:
        """Create KMS key for Secrets Manager encryption"""
        key = kms.Key(
            self,
            "SecretsManagerKey",
            description="KMS key for Secrets Manager encryption",
            enable_key_rotation=True,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Create alias for the key
        kms.Alias(
            self,
            "SecretsManagerKeyAlias",
            alias_name=f"alias/secrets-manager-key-{self.node.addr[:6]}",
            target_key=key
        )
        
        return key

    def _create_lambda_role(self) -> iam.Role:
        """Create IAM role for Lambda rotation function"""
        role = iam.Role(
            self,
            "SecretsManagerRotationRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for Secrets Manager rotation Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )
        
        # Add custom policy for Secrets Manager access
        secrets_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret",
                "secretsmanager:PutSecretValue",
                "secretsmanager:UpdateSecretVersionStage"
            ],
            resources=[f"arn:aws:secretsmanager:{self.region}:{self.account}:secret:*"]
        )
        
        kms_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "kms:Decrypt",
                "kms:DescribeKey",
                "kms:Encrypt",
                "kms:GenerateDataKey*",
                "kms:ReEncrypt*"
            ],
            resources=[self.kms_key.key_arn]
        )
        
        role.add_to_policy(secrets_policy)
        role.add_to_policy(kms_policy)
        
        return role

    def _create_database_secret(self) -> secretsmanager.Secret:
        """Create database secret with structured JSON data"""
        # Database credentials structure
        secret_value = {
            "engine": "mysql",
            "host": "demo-database.cluster-abc123.us-east-1.rds.amazonaws.com",
            "username": "admin",
            "password": "ChangeMe123!",  # Will be rotated immediately
            "dbname": "myapp",
            "port": 3306
        }
        
        secret = secretsmanager.Secret(
            self,
            "DatabaseSecret",
            secret_name=self.secret_name,
            description="Database credentials for demo application",
            encryption_key=self.kms_key,
            secret_string_value=secretsmanager.SecretStringValueBase1(
                json.dumps(secret_value)
            )
        )
        
        # Add tags to the secret
        Tags.of(secret).add("Environment", "Demo")
        Tags.of(secret).add("Application", "MyApp")
        
        return secret

    def _create_rotation_function(self) -> lambda_.Function:
        """Create Lambda function for secret rotation"""
        # Lambda function code
        rotation_code = '''
import json
import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to handle secret rotation
    """
    secretsmanager = boto3.client('secretsmanager')
    
    secret_arn = event['SecretId']
    token = event['ClientRequestToken']
    step = event['Step']
    
    logger.info(f"Rotation step: {step} for secret: {secret_arn}")
    
    if step == "createSecret":
        create_secret(secretsmanager, secret_arn, token)
    elif step == "setSecret":
        set_secret(secretsmanager, secret_arn, token)
    elif step == "testSecret":
        test_secret(secretsmanager, secret_arn, token)
    elif step == "finishSecret":
        finish_secret(secretsmanager, secret_arn, token)
    else:
        logger.error(f"Invalid step parameter: {step}")
        raise ValueError(f"Invalid step parameter: {step}")
    
    return {"statusCode": 200, "body": "Rotation completed successfully"}

def create_secret(secretsmanager, secret_arn, token):
    """Create a new secret version"""
    try:
        current_secret = secretsmanager.get_secret_value(
            SecretId=secret_arn,
            VersionStage="AWSCURRENT"
        )
        
        # Parse current secret
        current_data = json.loads(current_secret['SecretString'])
        
        # Generate new password
        new_password = secretsmanager.get_random_password(
            PasswordLength=20,
            ExcludeCharacters='"@/\\\\',
            RequireEachIncludedType=True
        )['RandomPassword']
        
        # Update password in secret data
        current_data['password'] = new_password
        
        # Create new secret version
        secretsmanager.put_secret_value(
            SecretId=secret_arn,
            ClientRequestToken=token,
            SecretString=json.dumps(current_data),
            VersionStages=['AWSPENDING']
        )
        
        logger.info("createSecret: Successfully created new secret version")
        
    except Exception as e:
        logger.error(f"createSecret: Error creating secret: {str(e)}")
        raise

def set_secret(secretsmanager, secret_arn, token):
    """Set the secret in the service"""
    logger.info("setSecret: In a real implementation, this would update the database user password")
    # In a real implementation, you would connect to the database
    # and update the user's password here

def test_secret(secretsmanager, secret_arn, token):
    """Test the secret"""
    logger.info("testSecret: In a real implementation, this would test database connectivity")
    # In a real implementation, you would test the database connection
    # with the new credentials here

def finish_secret(secretsmanager, secret_arn, token):
    """Finish the rotation"""
    try:
        # Get current version ID
        current_version = get_current_version_id(secretsmanager, secret_arn)
        
        # Move AWSCURRENT to AWSPREVIOUS and AWSPENDING to AWSCURRENT
        secretsmanager.update_secret_version_stage(
            SecretId=secret_arn,
            VersionStage="AWSCURRENT",
            MoveToVersionId=token,
            RemoveFromVersionId=current_version
        )
        
        logger.info("finishSecret: Successfully completed rotation")
        
    except Exception as e:
        logger.error(f"finishSecret: Error finishing rotation: {str(e)}")
        raise

def get_current_version_id(secretsmanager, secret_arn):
    """Get the current version ID"""
    versions = secretsmanager.list_secret_version_ids(SecretId=secret_arn)
    
    for version in versions['Versions']:
        if 'AWSCURRENT' in version['VersionStages']:
            return version['VersionId']
    
    return None
'''
        
        function = lambda_.Function(
            self,
            "RotationFunction",
            function_name=self.lambda_function_name,
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(rotation_code),
            role=self.lambda_role,
            timeout=Duration.seconds(60),
            description="Lambda function for rotating Secrets Manager secrets",
            log_retention=logs.RetentionDays.ONE_WEEK
        )
        
        return function

    def _configure_automatic_rotation(self) -> None:
        """Configure automatic rotation for the secret"""
        # Grant Secrets Manager permission to invoke Lambda
        self.rotation_function.add_permission(
            "SecretsManagerInvokePermission",
            principal=iam.ServicePrincipal("secretsmanager.amazonaws.com"),
            action="lambda:InvokeFunction"
        )
        
        # Configure rotation schedule (every 7 days)
        secretsmanager.RotationSchedule(
            self,
            "SecretRotationSchedule",
            secret=self.secret,
            rotation_lambda=self.rotation_function,
            automatically_after=Duration.days(7)
        )

    def _create_monitoring(self) -> None:
        """Create CloudWatch monitoring for secrets operations"""
        # Create CloudWatch dashboard
        dashboard = cloudwatch.Dashboard(
            self,
            "SecretsManagerDashboard",
            dashboard_name=f"SecretsManager-{self.node.addr[:6]}"
        )
        
        # Add metrics widgets
        rotation_success_metric = cloudwatch.Metric(
            namespace="AWS/SecretsManager",
            metric_name="RotationSucceeded",
            dimensions_map={"SecretName": self.secret_name}
        )
        
        rotation_failed_metric = cloudwatch.Metric(
            namespace="AWS/SecretsManager",
            metric_name="RotationFailed",
            dimensions_map={"SecretName": self.secret_name}
        )
        
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Secret Rotation Status",
                left=[rotation_success_metric, rotation_failed_metric],
                width=12,
                height=6
            )
        )
        
        # Create CloudWatch alarm for rotation failures
        cloudwatch.Alarm(
            self,
            "RotationFailureAlarm",
            alarm_name=f"SecretsManager-RotationFailure-{self.node.addr[:6]}",
            alarm_description="Alert when secret rotation fails",
            metric=rotation_failed_metric,
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD
        )

    def _create_cross_account_policy(self) -> None:
        """Create resource-based policy for cross-account access"""
        # Resource-based policy for cross-account access
        policy_document = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "AllowCrossAccountAccess",
                    "Effect": "Allow",
                    "Principal": {
                        "AWS": f"arn:aws:iam::{self.account}:root"
                    },
                    "Action": "secretsmanager:GetSecretValue",
                    "Resource": "*",
                    "Condition": {
                        "StringEquals": {
                            "secretsmanager:ResourceTag/Environment": "Demo"
                        }
                    }
                }
            ]
        }
        
        # Apply resource policy to secret
        secretsmanager.CfnResourcePolicy(
            self,
            "CrossAccountResourcePolicy",
            secret_id=self.secret.secret_arn,
            resource_policy=policy_document,
            block_public_policy=True
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs"""
        CfnOutput(
            self,
            "SecretArn",
            value=self.secret.secret_arn,
            description="ARN of the created secret"
        )
        
        CfnOutput(
            self,
            "SecretName",
            value=self.secret_name,
            description="Name of the created secret"
        )
        
        CfnOutput(
            self,
            "RotationFunctionArn",
            value=self.rotation_function.function_arn,
            description="ARN of the rotation Lambda function"
        )
        
        CfnOutput(
            self,
            "KMSKeyId",
            value=self.kms_key.key_id,
            description="ID of the KMS key used for encryption"
        )
        
        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name=SecretsManager-{self.node.addr[:6]}",
            description="URL to the CloudWatch dashboard"
        )


def main() -> None:
    """Main application entry point"""
    app = App()
    
    # Get environment from context or use default
    env = Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    )
    
    # Create the stack
    SecretsManagerStack(
        app,
        "SecretsManagerStack",
        env=env,
        description="AWS Secrets Manager implementation with automatic rotation and monitoring"
    )
    
    app.synth()


if __name__ == "__main__":
    main()