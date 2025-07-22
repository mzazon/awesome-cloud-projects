#!/usr/bin/env python3
"""
AWS CDK Python application for deploying ML models with Amazon SageMaker Endpoints.

This application creates the infrastructure needed to deploy machine learning models
as scalable, managed endpoints using Amazon SageMaker real-time hosting services.
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    RemovalPolicy,
    Duration,
    aws_s3 as s3,
    aws_ecr as ecr,
    aws_iam as iam,
    aws_sagemaker as sagemaker,
    aws_applicationautoscaling as autoscaling,
    aws_logs as logs,
)
from constructs import Construct


class SageMakerMLEndpointStack(Stack):
    """
    Stack that creates the infrastructure for SageMaker ML model endpoints.
    
    This stack includes:
    - ECR repository for custom inference containers
    - S3 bucket for model artifacts
    - SageMaker execution role with necessary permissions
    - SageMaker model, endpoint configuration, and endpoint
    - Auto-scaling configuration for the endpoint
    - CloudWatch log groups for monitoring
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        model_name: Optional[str] = None,
        endpoint_name: Optional[str] = None,
        instance_type: Optional[str] = None,
        initial_instance_count: Optional[int] = None,
        min_capacity: Optional[int] = None,
        max_capacity: Optional[int] = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters with defaults
        self.model_name = model_name or "sklearn-iris-classifier"
        self.endpoint_name = endpoint_name or "iris-prediction-endpoint"
        self.instance_type = instance_type or "ml.t2.medium"
        self.initial_instance_count = initial_instance_count or 1
        self.min_capacity = min_capacity or 1
        self.max_capacity = max_capacity or 5

        # Create ECR repository for custom inference containers
        self.ecr_repository = self._create_ecr_repository()

        # Create S3 bucket for model artifacts
        self.model_bucket = self._create_model_bucket()

        # Create SageMaker execution role
        self.sagemaker_role = self._create_sagemaker_execution_role()

        # Create CloudWatch log group for SageMaker
        self.log_group = self._create_log_group()

        # Create SageMaker model
        self.sagemaker_model = self._create_sagemaker_model()

        # Create endpoint configuration
        self.endpoint_config = self._create_endpoint_configuration()

        # Create SageMaker endpoint
        self.endpoint = self._create_endpoint()

        # Configure auto-scaling
        self._configure_auto_scaling()

        # Create outputs
        self._create_outputs()

    def _create_ecr_repository(self) -> ecr.Repository:
        """Create ECR repository with image scanning enabled."""
        repository = ecr.Repository(
            self,
            "InferenceRepository",
            repository_name="sagemaker-sklearn-inference",
            image_scan_on_push=True,
            lifecycle_rules=[
                ecr.LifecycleRule(
                    description="Keep only the latest 10 images",
                    max_image_count=10,
                    rule_priority=1,
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Grant pull permissions to SageMaker service
        repository.grant_pull(iam.ServicePrincipal("sagemaker.amazonaws.com"))

        return repository

    def _create_model_bucket(self) -> s3.Bucket:
        """Create S3 bucket for storing model artifacts."""
        bucket = s3.Bucket(
            self,
            "ModelArtifactsBucket",
            bucket_name=f"sagemaker-models-{self.account}-{self.region}",
            versioned=True,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    enabled=True,
                    noncurrent_version_expiration=Duration.days(30),
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        return bucket

    def _create_sagemaker_execution_role(self) -> iam.Role:
        """Create IAM role for SageMaker with necessary permissions."""
        role = iam.Role(
            self,
            "SageMakerExecutionRole",
            role_name=f"SageMakerExecutionRole-{self.stack_name}",
            assumed_by=iam.ServicePrincipal("sagemaker.amazonaws.com"),
            description="Execution role for SageMaker model endpoints",
        )

        # Attach AWS managed policies
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSageMakerFullAccess")
        )

        # Add custom permissions for ECR and S3
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ecr:BatchCheckLayerAvailability",
                    "ecr:GetDownloadUrlForLayer",
                    "ecr:BatchGetImage",
                    "ecr:GetAuthorizationToken",
                ],
                resources=["*"],
            )
        )

        # Grant access to the model artifacts bucket
        self.model_bucket.grant_read(role)

        # Add CloudWatch permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                    "logs:DescribeLogStreams",
                ],
                resources=[
                    f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/sagemaker/*"
                ],
            )
        )

        return role

    def _create_log_group(self) -> logs.LogGroup:
        """Create CloudWatch log group for SageMaker endpoint."""
        log_group = logs.LogGroup(
            self,
            "SageMakerLogGroup",
            log_group_name=f"/aws/sagemaker/endpoints/{self.endpoint_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

        return log_group

    def _create_sagemaker_model(self) -> sagemaker.CfnModel:
        """Create SageMaker model with custom container and model artifacts."""
        # Construct the model data URL (will be populated after model upload)
        model_data_url = f"s3://{self.model_bucket.bucket_name}/model.tar.gz"

        # Construct the ECR image URI
        image_uri = f"{self.account}.dkr.ecr.{self.region}.amazonaws.com/{self.ecr_repository.repository_name}:latest"

        model = sagemaker.CfnModel(
            self,
            "SageMakerModel",
            model_name=self.model_name,
            execution_role_arn=self.sagemaker_role.role_arn,
            primary_container=sagemaker.CfnModel.ContainerDefinitionProperty(
                image=image_uri,
                model_data_url=model_data_url,
                environment={
                    "SAGEMAKER_PROGRAM": "predictor.py",
                    "SAGEMAKER_SUBMIT_DIRECTORY": "/opt/ml/code",
                    "SAGEMAKER_CONTAINER_LOG_LEVEL": "20",
                    "SAGEMAKER_ENABLE_CLOUDWATCH_METRICS": "true",
                },
            ),
            tags=[
                cdk.CfnTag(key="Project", value="MLOps"),
                cdk.CfnTag(key="Environment", value="Production"),
                cdk.CfnTag(key="ModelType", value="SklearnClassifier"),
            ],
        )

        return model

    def _create_endpoint_configuration(self) -> sagemaker.CfnEndpointConfig:
        """Create SageMaker endpoint configuration with production variants."""
        endpoint_config = sagemaker.CfnEndpointConfig(
            self,
            "EndpointConfiguration",
            endpoint_config_name=f"{self.model_name}-config",
            production_variants=[
                sagemaker.CfnEndpointConfig.ProductionVariantProperty(
                    variant_name="primary",
                    model_name=self.sagemaker_model.model_name,
                    initial_instance_count=self.initial_instance_count,
                    instance_type=self.instance_type,
                    initial_variant_weight=1.0,
                    accelerator_type=None,  # Set to GPU accelerator if needed
                )
            ],
            data_capture_config=sagemaker.CfnEndpointConfig.DataCaptureConfigProperty(
                enable_capture=True,
                initial_sampling_percentage=20,
                destination_s3_uri=f"s3://{self.model_bucket.bucket_name}/data-capture",
                capture_options=[
                    sagemaker.CfnEndpointConfig.CaptureOptionProperty(
                        capture_mode="Input"
                    ),
                    sagemaker.CfnEndpointConfig.CaptureOptionProperty(
                        capture_mode="Output"
                    ),
                ],
                capture_content_type_header=sagemaker.CfnEndpointConfig.CaptureContentTypeHeaderProperty(
                    json_content_types=["application/json"],
                ),
            ),
            tags=[
                cdk.CfnTag(key="Project", value="MLOps"),
                cdk.CfnTag(key="Environment", value="Production"),
            ],
        )

        # Add dependency on the model
        endpoint_config.add_dependency(self.sagemaker_model)

        return endpoint_config

    def _create_endpoint(self) -> sagemaker.CfnEndpoint:
        """Create SageMaker endpoint for real-time inference."""
        endpoint = sagemaker.CfnEndpoint(
            self,
            "SageMakerEndpoint",
            endpoint_name=self.endpoint_name,
            endpoint_config_name=self.endpoint_config.endpoint_config_name,
            tags=[
                cdk.CfnTag(key="Project", value="MLOps"),
                cdk.CfnTag(key="Environment", value="Production"),
                cdk.CfnTag(key="AutoScaling", value="Enabled"),
            ],
        )

        # Add dependency on the endpoint configuration
        endpoint.add_dependency(self.endpoint_config)

        return endpoint

    def _configure_auto_scaling(self) -> None:
        """Configure auto-scaling for the SageMaker endpoint."""
        # Create scalable target
        scalable_target = autoscaling.ScalableTarget(
            self,
            "EndpointScalableTarget",
            service_namespace=autoscaling.ServiceNamespace.SAGEMAKER,
            resource_id=f"endpoint/{self.endpoint.endpoint_name}/variant/primary",
            scalable_dimension="sagemaker:variant:DesiredInstanceCount",
            min_capacity=self.min_capacity,
            max_capacity=self.max_capacity,
        )

        # Add dependency on the endpoint
        scalable_target.node.add_dependency(self.endpoint)

        # Create target tracking scaling policy
        scalable_target.scale_on_metric(
            "EndpointScalingPolicy",
            metric=autoscaling.predefined_metric.PredefinedMetric.SAGEMAKER_VARIANT_INVOCATIONS_PER_INSTANCE,
            target_value=70.0,
            scale_in_cooldown=Duration.seconds(300),
            scale_out_cooldown=Duration.seconds(300),
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "ECRRepositoryURI",
            value=self.ecr_repository.repository_uri,
            description="ECR repository URI for inference container images",
        )

        CfnOutput(
            self,
            "ModelArtifactsBucketName",
            value=self.model_bucket.bucket_name,
            description="S3 bucket name for storing model artifacts",
        )

        CfnOutput(
            self,
            "SageMakerExecutionRoleArn",
            value=self.sagemaker_role.role_arn,
            description="ARN of the SageMaker execution role",
        )

        CfnOutput(
            self,
            "SageMakerModelName",
            value=self.sagemaker_model.model_name,
            description="Name of the SageMaker model",
        )

        CfnOutput(
            self,
            "EndpointConfigurationName",
            value=self.endpoint_config.endpoint_config_name,
            description="Name of the SageMaker endpoint configuration",
        )

        CfnOutput(
            self,
            "EndpointName",
            value=self.endpoint.endpoint_name,
            description="Name of the SageMaker endpoint for inference",
        )

        CfnOutput(
            self,
            "EndpointURL",
            value=f"https://runtime.sagemaker.{self.region}.amazonaws.com/endpoints/{self.endpoint.endpoint_name}/invocations",
            description="SageMaker endpoint URL for making predictions",
        )

        CfnOutput(
            self,
            "LogGroupName",
            value=self.log_group.log_group_name,
            description="CloudWatch log group for SageMaker endpoint logs",
        )


def main() -> None:
    """Main function to create and deploy the CDK application."""
    app = cdk.App()

    # Get configuration from environment variables or use defaults
    env = cdk.Environment(
        account=os.getenv("CDK_DEFAULT_ACCOUNT"),
        region=os.getenv("CDK_DEFAULT_REGION", "us-east-1"),
    )

    # Create the stack with optional customization parameters
    SageMakerMLEndpointStack(
        app,
        "SageMakerMLEndpointStack",
        env=env,
        description="Infrastructure for deploying ML models with Amazon SageMaker Endpoints",
        # Uncomment and modify these parameters as needed:
        # model_name="custom-model-name",
        # endpoint_name="custom-endpoint-name",
        # instance_type="ml.c5.large",
        # initial_instance_count=2,
        # min_capacity=1,
        # max_capacity=10,
    )

    app.synth()


if __name__ == "__main__":
    main()