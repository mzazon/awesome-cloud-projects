#!/usr/bin/env python3
"""
CDK Python application for Machine Learning Pipelines with SageMaker and Step Functions.

This application creates a complete ML pipeline infrastructure including:
- S3 bucket for ML artifacts and data
- IAM roles for SageMaker and Step Functions
- Lambda function for model evaluation
- Step Functions state machine for ML pipeline orchestration
- CloudWatch alarms and SNS notifications for monitoring
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    App,
    Environment,
    aws_s3 as s3,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_stepfunctions as sfn,
    aws_stepfunctions_tasks as tasks,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cw_actions,
    aws_logs as logs,
    Duration,
    RemovalPolicy,
    CfnOutput,
    CfnParameter,
)
from constructs import Construct


class MLPipelineStack(Stack):
    """
    Stack that creates the complete ML pipeline infrastructure.
    
    This stack includes all the resources needed for an end-to-end ML pipeline:
    - Data storage and processing infrastructure
    - IAM roles and permissions
    - Compute resources for training and inference
    - Workflow orchestration and monitoring
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        **kwargs: Any
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters for customization
        self.pipeline_name = CfnParameter(
            self,
            "PipelineName",
            type="String",
            description="Name for the ML pipeline",
            default="ml-pipeline"
        )

        self.notification_email = CfnParameter(
            self,
            "NotificationEmail",
            type="String",
            description="Email address for pipeline notifications",
            default="admin@example.com"
        )

        self.model_performance_threshold = CfnParameter(
            self,
            "ModelPerformanceThreshold",
            type="Number",
            description="Minimum R² score for model deployment",
            default=0.7,
            min_value=0.0,
            max_value=1.0
        )

        # Create core infrastructure
        self.s3_bucket = self._create_s3_bucket()
        self.sagemaker_role = self._create_sagemaker_role()
        self.step_functions_role = self._create_step_functions_role()
        self.lambda_role = self._create_lambda_role()
        self.evaluation_function = self._create_evaluation_function()
        self.sns_topic = self._create_sns_topic()
        self.state_machine = self._create_state_machine()
        self.cloudwatch_alarms = self._create_cloudwatch_alarms()

        # Create outputs
        self._create_outputs()

    def _create_s3_bucket(self) -> s3.Bucket:
        """Create S3 bucket for ML artifacts with proper configuration."""
        bucket = s3.Bucket(
            self,
            "MLPipelineBucket",
            bucket_name=f"{self.pipeline_name.value_as_string}-{self.account}-{self.region}",
            versioning=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    enabled=True,
                    noncurrent_version_expiration=Duration.days(30),
                    abort_incomplete_multipart_upload_after=Duration.days(7)
                )
            ]
        )

        # Create folder structure
        for folder in ["raw-data", "processed-data", "model-artifacts", "code"]:
            s3.BucketDeployment(
                self,
                f"CreateFolder{folder.title().replace('-', '')}",
                sources=[],
                destination_bucket=bucket,
                destination_key_prefix=f"{folder}/",
                retain_on_delete=False
            )

        return bucket

    def _create_sagemaker_role(self) -> iam.Role:
        """Create IAM role for SageMaker with appropriate permissions."""
        role = iam.Role(
            self,
            "SageMakerExecutionRole",
            role_name=f"SageMakerMLPipelineRole-{self.pipeline_name.value_as_string}",
            assumed_by=iam.ServicePrincipal("sagemaker.amazonaws.com"),
            description="Role for SageMaker ML pipeline operations",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSageMakerFullAccess")
            ]
        )

        # Add custom S3 permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket"
                ],
                resources=[
                    self.s3_bucket.bucket_arn,
                    f"{self.s3_bucket.bucket_arn}/*"
                ]
            )
        )

        # Add CloudWatch permissions
        role.add_to_policy(
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
        )

        return role

    def _create_step_functions_role(self) -> iam.Role:
        """Create IAM role for Step Functions with SageMaker integration permissions."""
        role = iam.Role(
            self,
            "StepFunctionsExecutionRole",
            role_name=f"StepFunctionsMLRole-{self.pipeline_name.value_as_string}",
            assumed_by=iam.ServicePrincipal("states.amazonaws.com"),
            description="Role for Step Functions ML pipeline orchestration"
        )

        # Add SageMaker permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "sagemaker:CreateProcessingJob",
                    "sagemaker:CreateTrainingJob",
                    "sagemaker:CreateModel",
                    "sagemaker:CreateEndpointConfig",
                    "sagemaker:CreateEndpoint",
                    "sagemaker:UpdateEndpoint",
                    "sagemaker:DeleteEndpoint",
                    "sagemaker:DescribeProcessingJob",
                    "sagemaker:DescribeTrainingJob",
                    "sagemaker:DescribeModel",
                    "sagemaker:DescribeEndpoint",
                    "sagemaker:ListTags",
                    "sagemaker:AddTags"
                ],
                resources=["*"]
            )
        )

        # Add S3 permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket"
                ],
                resources=[
                    self.s3_bucket.bucket_arn,
                    f"{self.s3_bucket.bucket_arn}/*"
                ]
            )
        )

        # Add IAM pass role permission
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["iam:PassRole"],
                resources=[self.sagemaker_role.role_arn]
            )
        )

        # Add Lambda invoke permission
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["lambda:InvokeFunction"],
                resources=["*"]
            )
        )

        # Add SNS permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["sns:Publish"],
                resources=["*"]
            )
        )

        return role

    def _create_lambda_role(self) -> iam.Role:
        """Create IAM role for Lambda function with S3 read permissions."""
        role = iam.Role(
            self,
            "LambdaExecutionRole",
            role_name=f"LambdaEvaluateModelRole-{self.pipeline_name.value_as_string}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Role for Lambda model evaluation function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )

        # Add S3 read permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:ListBucket"
                ],
                resources=[
                    self.s3_bucket.bucket_arn,
                    f"{self.s3_bucket.bucket_arn}/*"
                ]
            )
        )

        return role

    def _create_evaluation_function(self) -> lambda_.Function:
        """Create Lambda function for model evaluation."""
        function = lambda_.Function(
            self,
            "ModelEvaluationFunction",
            function_name=f"EvaluateModel-{self.pipeline_name.value_as_string}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            memory_size=128,
            description="Evaluates ML model performance metrics",
            environment={
                "S3_BUCKET": self.s3_bucket.bucket_name,
                "PERFORMANCE_THRESHOLD": self.model_performance_threshold.value_as_string
            },
            code=lambda_.Code.from_inline("""
import json
import boto3
import os
from typing import Dict, Any

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    \"\"\"
    Evaluate ML model performance metrics from S3.
    
    Args:
        event: Lambda event containing TrainingJobName and S3Bucket
        context: Lambda context object
    
    Returns:
        Dictionary containing evaluation metrics and deployment decision
    \"\"\"
    s3 = boto3.client('s3')
    
    # Get parameters from event
    training_job_name = event.get('TrainingJobName')
    s3_bucket = event.get('S3Bucket', os.environ['S3_BUCKET'])
    performance_threshold = float(os.environ.get('PERFORMANCE_THRESHOLD', '0.7'))
    
    if not training_job_name:
        return {
            'statusCode': 400,
            'body': {'error': 'TrainingJobName is required'}
        }
    
    try:
        # Download evaluation metrics from S3
        evaluation_key = f"model-artifacts/{training_job_name}/output/evaluation.json"
        
        print(f"Downloading evaluation metrics from s3://{s3_bucket}/{evaluation_key}")
        
        response = s3.get_object(Bucket=s3_bucket, Key=evaluation_key)
        evaluation_data = json.loads(response['Body'].read())
        
        # Add deployment decision based on performance threshold
        test_r2 = evaluation_data.get('test_r2', 0.0)
        evaluation_data['deploy_model'] = test_r2 >= performance_threshold
        evaluation_data['performance_threshold'] = performance_threshold
        
        print(f"Model performance: R² = {test_r2:.4f}, Threshold = {performance_threshold:.4f}")
        print(f"Deployment decision: {'APPROVED' if evaluation_data['deploy_model'] else 'REJECTED'}")
        
        return {
            'statusCode': 200,
            'body': evaluation_data
        }
    
    except Exception as e:
        print(f"Error evaluating model: {str(e)}")
        return {
            'statusCode': 500,
            'body': {'error': str(e)}
        }
""")
        )

        return function

    def _create_sns_topic(self) -> sns.Topic:
        """Create SNS topic for pipeline notifications."""
        topic = sns.Topic(
            self,
            "MLPipelineNotifications",
            topic_name=f"ml-pipeline-notifications-{self.pipeline_name.value_as_string}",
            display_name="ML Pipeline Notifications",
            description="Notifications for ML pipeline events"
        )

        # Add email subscription
        topic.add_subscription(
            sns.Subscription(
                self,
                "EmailSubscription",
                topic=topic,
                endpoint=self.notification_email.value_as_string,
                protocol=sns.SubscriptionProtocol.EMAIL
            )
        )

        return topic

    def _create_state_machine(self) -> sfn.StateMachine:
        """Create Step Functions state machine for ML pipeline orchestration."""
        
        # Define SageMaker container image URI
        sagemaker_image_uri = f"683313688378.dkr.ecr.{self.region}.amazonaws.com/sagemaker-scikit-learn:1.0-1-cpu-py3"
        
        # Data preprocessing step
        preprocessing_step = tasks.SageMakerCreateProcessingJob(
            self,
            "DataPreprocessing",
            processing_job_name=sfn.JsonPath.string_at("$.PreprocessingJobName"),
            role=self.sagemaker_role,
            app_specification=tasks.ProcessingJobAppSpecification(
                image_uri=sagemaker_image_uri,
                container_entrypoint=["python3", "/opt/ml/processing/input/code/preprocessing.py"],
                container_arguments=[
                    "--input-data", "/opt/ml/processing/input/data/train.csv",
                    "--output-data", "/opt/ml/processing/output/train_processed.csv"
                ]
            ),
            processing_inputs=[
                tasks.ProcessingInput(
                    input_name="data",
                    s3_input=tasks.ProcessingS3Input(
                        s3_uri=f"s3://{self.s3_bucket.bucket_name}/raw-data",
                        local_path="/opt/ml/processing/input/data",
                        s3_data_type=tasks.S3DataType.S3_PREFIX
                    )
                ),
                tasks.ProcessingInput(
                    input_name="code",
                    s3_input=tasks.ProcessingS3Input(
                        s3_uri=f"s3://{self.s3_bucket.bucket_name}/code",
                        local_path="/opt/ml/processing/input/code",
                        s3_data_type=tasks.S3DataType.S3_PREFIX
                    )
                )
            ],
            processing_outputs=[
                tasks.ProcessingOutput(
                    output_name="processed_data",
                    s3_output=tasks.ProcessingS3Output(
                        s3_uri=f"s3://{self.s3_bucket.bucket_name}/processed-data",
                        local_path="/opt/ml/processing/output"
                    )
                )
            ],
            cluster_config=tasks.ProcessingClusterConfig(
                instance_count=1,
                instance_type=tasks.ProcessingInstanceType.ML_M5_LARGE,
                volume_size_in_gb=30
            ),
            result_path="$.PreprocessingResult"
        )

        # Model training step
        training_step = tasks.SageMakerCreateTrainingJob(
            self,
            "ModelTraining",
            training_job_name=sfn.JsonPath.string_at("$.TrainingJobName"),
            role=self.sagemaker_role,
            algorithm_specification=tasks.AlgorithmSpecification(
                training_image=tasks.DockerImage.from_registry(sagemaker_image_uri),
                training_input_mode=tasks.InputMode.FILE
            ),
            input_data_config=[
                tasks.Channel(
                    channel_name="train",
                    data_source=tasks.DataSource(
                        s3_data_source=tasks.S3DataSource(
                            s3_data_type=tasks.S3DataType.S3_PREFIX,
                            s3_uri=f"s3://{self.s3_bucket.bucket_name}/processed-data",
                            s3_data_distribution_type=tasks.S3DataDistributionType.FULLY_REPLICATED
                        )
                    )
                ),
                tasks.Channel(
                    channel_name="test",
                    data_source=tasks.DataSource(
                        s3_data_source=tasks.S3DataSource(
                            s3_data_type=tasks.S3DataType.S3_PREFIX,
                            s3_uri=f"s3://{self.s3_bucket.bucket_name}/raw-data",
                            s3_data_distribution_type=tasks.S3DataDistributionType.FULLY_REPLICATED
                        )
                    )
                ),
                tasks.Channel(
                    channel_name="code",
                    data_source=tasks.DataSource(
                        s3_data_source=tasks.S3DataSource(
                            s3_data_type=tasks.S3DataType.S3_PREFIX,
                            s3_uri=f"s3://{self.s3_bucket.bucket_name}/code",
                            s3_data_distribution_type=tasks.S3DataDistributionType.FULLY_REPLICATED
                        )
                    )
                )
            ],
            output_data_config=tasks.OutputDataConfig(
                s3_output_path=f"s3://{self.s3_bucket.bucket_name}/model-artifacts"
            ),
            resource_config=tasks.ResourceConfig(
                instance_type=tasks.TrainingInstanceType.ML_M5_LARGE,
                instance_count=1,
                volume_size_in_gb=30
            ),
            stopping_condition=tasks.StoppingCondition(
                max_runtime=Duration.hours(1)
            ),
            hyperparameters={
                "sagemaker_program": "training.py",
                "sagemaker_submit_directory": "/opt/ml/input/data/code"
            },
            result_path="$.TrainingResult"
        )

        # Model evaluation step
        evaluation_step = tasks.LambdaInvoke(
            self,
            "ModelEvaluation",
            lambda_function=self.evaluation_function,
            payload=sfn.TaskInput.from_object({
                "TrainingJobName": sfn.JsonPath.string_at("$.TrainingJobName"),
                "S3Bucket": self.s3_bucket.bucket_name
            }),
            result_path="$.EvaluationResult"
        )

        # Model performance check
        performance_check = sfn.Choice(
            self,
            "CheckModelPerformance",
            comment="Check if model performance meets threshold"
        )

        # Create SageMaker model
        create_model_step = tasks.SageMakerCreateModel(
            self,
            "CreateModel",
            model_name=sfn.JsonPath.string_at("$.ModelName"),
            role=self.sagemaker_role,
            containers=[
                tasks.ContainerDefinition(
                    image=tasks.DockerImage.from_registry(sagemaker_image_uri),
                    model_data_url=sfn.JsonPath.string_at("$.ModelDataUrl"),
                    environment={
                        "SAGEMAKER_PROGRAM": "inference.py",
                        "SAGEMAKER_SUBMIT_DIRECTORY": "/opt/ml/code"
                    }
                )
            ]
        )

        # Create endpoint configuration
        create_endpoint_config_step = tasks.SageMakerCreateEndpointConfig(
            self,
            "CreateEndpointConfig",
            endpoint_config_name=sfn.JsonPath.string_at("$.EndpointConfigName"),
            production_variants=[
                tasks.ProductionVariant(
                    variant_name="primary",
                    model_name=sfn.JsonPath.string_at("$.ModelName"),
                    initial_instance_count=1,
                    instance_type=tasks.SageMakerInstanceType.ML_T2_MEDIUM,
                    initial_variant_weight=1.0
                )
            ]
        )

        # Create endpoint
        create_endpoint_step = tasks.SageMakerCreateEndpoint(
            self,
            "CreateEndpoint",
            endpoint_name=sfn.JsonPath.string_at("$.EndpointName"),
            endpoint_config_name=sfn.JsonPath.string_at("$.EndpointConfigName")
        )

        # Success notification
        success_notification = tasks.SnsPublish(
            self,
            "SuccessNotification",
            topic=self.sns_topic,
            message=sfn.TaskInput.from_object({
                "Pipeline": "ML Pipeline",
                "Status": "SUCCESS",
                "Message": "Model deployed successfully",
                "EndpointName": sfn.JsonPath.string_at("$.EndpointName")
            }),
            subject="ML Pipeline - Deployment Success"
        )

        # Failure states
        processing_failed = sfn.Fail(
            self,
            "ProcessingJobFailed",
            error="ProcessingJobFailed",
            cause="The data preprocessing job failed"
        )

        training_failed = sfn.Fail(
            self,
            "TrainingJobFailed",
            error="TrainingJobFailed",
            cause="The model training job failed"
        )

        performance_insufficient = sfn.Fail(
            self,
            "ModelPerformanceInsufficient",
            error="ModelPerformanceInsufficient",
            cause="Model performance does not meet the required threshold"
        )

        # Success state
        pipeline_complete = sfn.Succeed(
            self,
            "MLPipelineComplete",
            comment="ML Pipeline completed successfully"
        )

        # Define the state machine workflow
        definition = preprocessing_step \
            .add_catch(processing_failed, errors=["States.ALL"]) \
            .next(training_step
                  .add_catch(training_failed, errors=["States.ALL"])
                  .next(evaluation_step
                        .next(performance_check
                              .when(
                                  sfn.Condition.number_greater_than(
                                      "$.EvaluationResult.Payload.body.test_r2",
                                      self.model_performance_threshold.value_as_number
                                  ),
                                  create_model_step
                                  .next(create_endpoint_config_step
                                        .next(create_endpoint_step
                                              .next(success_notification
                                                    .next(pipeline_complete))))
                              )
                              .otherwise(performance_insufficient))))

        # Create state machine
        state_machine = sfn.StateMachine(
            self,
            "MLPipelineStateMachine",
            state_machine_name=f"{self.pipeline_name.value_as_string}-state-machine",
            definition=definition,
            role=self.step_functions_role,
            logs=sfn.LogOptions(
                destination=logs.LogGroup(
                    self,
                    "StateMachineLogGroup",
                    log_group_name=f"/aws/stepfunctions/{self.pipeline_name.value_as_string}",
                    retention=logs.RetentionDays.ONE_MONTH,
                    removal_policy=RemovalPolicy.DESTROY
                ),
                level=sfn.LogLevel.ALL
            ),
            timeout=Duration.hours(2)
        )

        return state_machine

    def _create_cloudwatch_alarms(self) -> Dict[str, cloudwatch.Alarm]:
        """Create CloudWatch alarms for pipeline monitoring."""
        alarms = {}

        # State machine execution failure alarm
        alarms['execution_failed'] = cloudwatch.Alarm(
            self,
            "ExecutionFailedAlarm",
            alarm_name=f"{self.pipeline_name.value_as_string}-execution-failed",
            alarm_description="ML Pipeline execution failed",
            metric=self.state_machine.metric_failed(
                period=Duration.minutes(5),
                statistic="Sum"
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Add SNS action to alarm
        alarms['execution_failed'].add_alarm_action(
            cw_actions.SnsAction(self.sns_topic)
        )

        # Lambda function error alarm
        alarms['lambda_errors'] = cloudwatch.Alarm(
            self,
            "LambdaErrorAlarm",
            alarm_name=f"{self.pipeline_name.value_as_string}-lambda-errors",
            alarm_description="Lambda function errors in ML Pipeline",
            metric=self.evaluation_function.metric_errors(
                period=Duration.minutes(5),
                statistic="Sum"
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        alarms['lambda_errors'].add_alarm_action(
            cw_actions.SnsAction(self.sns_topic)
        )

        return alarms

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "S3BucketName",
            value=self.s3_bucket.bucket_name,
            description="S3 bucket for ML pipeline artifacts",
            export_name=f"{self.stack_name}-S3Bucket"
        )

        CfnOutput(
            self,
            "StateMachineArn",
            value=self.state_machine.state_machine_arn,
            description="Step Functions state machine ARN",
            export_name=f"{self.stack_name}-StateMachine"
        )

        CfnOutput(
            self,
            "SageMakerRoleArn",
            value=self.sagemaker_role.role_arn,
            description="SageMaker execution role ARN",
            export_name=f"{self.stack_name}-SageMakerRole"
        )

        CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.evaluation_function.function_arn,
            description="Model evaluation Lambda function ARN",
            export_name=f"{self.stack_name}-LambdaFunction"
        )

        CfnOutput(
            self,
            "SNSTopicArn",
            value=self.sns_topic.topic_arn,
            description="SNS topic for notifications",
            export_name=f"{self.stack_name}-SNSTopic"
        )


def main() -> None:
    """Main application entry point."""
    app = App()

    # Get environment configuration
    env = Environment(
        account=os.getenv('CDK_DEFAULT_ACCOUNT'),
        region=os.getenv('CDK_DEFAULT_REGION', 'us-east-1')
    )

    # Create the stack
    MLPipelineStack(
        app,
        "MLPipelineStack",
        env=env,
        description="Complete ML Pipeline with SageMaker and Step Functions",
        tags={
            "Project": "ML-Pipeline",
            "Environment": "Development",
            "Owner": "DataScience-Team"
        }
    )

    app.synth()


if __name__ == "__main__":
    main()