#!/usr/bin/env python3
"""
CDK Application for Custom Entity Recognition and Classification with Amazon Comprehend

This application deploys a complete ML pipeline for training and deploying custom
entity recognition and document classification models using Amazon Comprehend.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_stepfunctions as sfn,
    aws_stepfunctions_tasks as sfn_tasks,
    aws_apigateway as apigateway,
    aws_dynamodb as dynamodb,
    aws_logs as logs,
)
from constructs import Construct


class ComprehendCustomModelsStack(Stack):
    """
    Stack for deploying custom Comprehend entity recognition and classification models
    with automated training pipeline and inference API.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs: Any) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.try_get_context("unique_suffix") or "demo"
        
        # Create S3 bucket for training data and models
        self.training_bucket = s3.Bucket(
            self,
            "TrainingDataBucket",
            bucket_name=f"comprehend-models-{unique_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Create DynamoDB table for storing inference results
        self.results_table = dynamodb.Table(
            self,
            "InferenceResultsTable",
            table_name=f"comprehend-results-{unique_suffix}",
            partition_key=dynamodb.Attribute(
                name="id", type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
        )

        # Create IAM role for Comprehend and Lambda functions
        self.comprehend_role = self._create_comprehend_role()

        # Create Lambda functions
        self.data_preprocessor = self._create_data_preprocessor_function()
        self.model_trainer = self._create_model_trainer_function()
        self.status_checker = self._create_status_checker_function()
        self.inference_api = self._create_inference_api_function()

        # Create Step Functions workflow
        self.training_workflow = self._create_training_workflow()

        # Create API Gateway for inference
        self.api_gateway = self._create_api_gateway()

        # Output important values
        cdk.CfnOutput(
            self,
            "TrainingBucketName",
            value=self.training_bucket.bucket_name,
            description="S3 bucket for training data and models",
        )

        cdk.CfnOutput(
            self,
            "ResultsTableName",
            value=self.results_table.table_name,
            description="DynamoDB table for inference results",
        )

        cdk.CfnOutput(
            self,
            "TrainingWorkflowArn",
            value=self.training_workflow.state_machine_arn,
            description="Step Functions state machine for model training",
        )

        cdk.CfnOutput(
            self,
            "InferenceApiEndpoint",
            value=self.api_gateway.url,
            description="API Gateway endpoint for inference requests",
        )

        cdk.CfnOutput(
            self,
            "ComprehendRoleArn",
            value=self.comprehend_role.role_arn,
            description="IAM role ARN for Comprehend operations",
        )

    def _create_comprehend_role(self) -> iam.Role:
        """Create IAM role with permissions for Comprehend, S3, and other services."""
        role = iam.Role(
            self,
            "ComprehendRole",
            role_name=f"ComprehendCustomRole-{self.node.try_get_context('unique_suffix') or 'demo'}",
            assumed_by=iam.CompositePrincipal(
                iam.ServicePrincipal("comprehend.amazonaws.com"),
                iam.ServicePrincipal("lambda.amazonaws.com"),
                iam.ServicePrincipal("states.amazonaws.com"),
            ),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("ComprehendFullAccess"),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name("AWSStepFunctionsFullAccess"),
            ],
        )

        # Add S3 permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["s3:*"],
                resources=[
                    self.training_bucket.bucket_arn,
                    f"{self.training_bucket.bucket_arn}/*",
                ],
            )
        )

        # Add DynamoDB permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:PutItem",
                    "dynamodb:GetItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:DeleteItem",
                    "dynamodb:Query",
                    "dynamodb:Scan",
                ],
                resources=[self.results_table.table_arn],
            )
        )

        return role

    def _create_data_preprocessor_function(self) -> lambda_.Function:
        """Create Lambda function for data preprocessing and validation."""
        return lambda_.Function(
            self,
            "DataPreprocessorFunction",
            function_name=f"comprehend-data-preprocessor-{self.node.try_get_context('unique_suffix') or 'demo'}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_data_preprocessor_code()),
            timeout=Duration.minutes(5),
            role=self.comprehend_role,
            environment={
                "BUCKET_NAME": self.training_bucket.bucket_name,
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )

    def _create_model_trainer_function(self) -> lambda_.Function:
        """Create Lambda function for initiating model training jobs."""
        return lambda_.Function(
            self,
            "ModelTrainerFunction",
            function_name=f"comprehend-model-trainer-{self.node.try_get_context('unique_suffix') or 'demo'}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_model_trainer_code()),
            timeout=Duration.minutes(1),
            role=self.comprehend_role,
            environment={
                "BUCKET_NAME": self.training_bucket.bucket_name,
                "ROLE_ARN": self.comprehend_role.role_arn,
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )

    def _create_status_checker_function(self) -> lambda_.Function:
        """Create Lambda function for checking training job status."""
        return lambda_.Function(
            self,
            "StatusCheckerFunction",
            function_name=f"comprehend-status-checker-{self.node.try_get_context('unique_suffix') or 'demo'}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_status_checker_code()),
            timeout=Duration.seconds(30),
            role=self.comprehend_role,
            log_retention=logs.RetentionDays.ONE_WEEK,
        )

    def _create_inference_api_function(self) -> lambda_.Function:
        """Create Lambda function for real-time inference API."""
        return lambda_.Function(
            self,
            "InferenceApiFunction",
            function_name=f"comprehend-inference-api-{self.node.try_get_context('unique_suffix') or 'demo'}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_inference_api_code()),
            timeout=Duration.seconds(30),
            role=self.comprehend_role,
            environment={
                "RESULTS_TABLE": self.results_table.table_name,
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )

    def _create_training_workflow(self) -> sfn.StateMachine:
        """Create Step Functions workflow for orchestrating model training."""
        # Define tasks
        preprocess_task = sfn_tasks.LambdaInvoke(
            self,
            "PreprocessData",
            lambda_function=self.data_preprocessor,
            payload=sfn.TaskInput.from_object({
                "bucket": self.training_bucket.bucket_name,
                "entity_training_data": "training-data/entities.csv",
                "classification_training_data": "training-data/classification.csv",
            }),
            result_path="$.preprocessing_result",
        )

        train_entity_task = sfn_tasks.LambdaInvoke(
            self,
            "TrainEntityModel",
            lambda_function=self.model_trainer,
            payload=sfn.TaskInput.from_object({
                "bucket": self.training_bucket.bucket_name,
                "model_type": "entity",
                "project_name": f"comprehend-custom-{self.node.try_get_context('unique_suffix') or 'demo'}",
                "role_arn": self.comprehend_role.role_arn,
                "entity_training_ready": sfn.JsonPath.string_at(
                    "$.preprocessing_result.Payload.entity_training_ready"
                ),
            }),
            result_path="$.entity_training_result",
        )

        train_classification_task = sfn_tasks.LambdaInvoke(
            self,
            "TrainClassificationModel",
            lambda_function=self.model_trainer,
            payload=sfn.TaskInput.from_object({
                "bucket": self.training_bucket.bucket_name,
                "model_type": "classification",
                "project_name": f"comprehend-custom-{self.node.try_get_context('unique_suffix') or 'demo'}",
                "role_arn": self.comprehend_role.role_arn,
                "classification_training_ready": sfn.JsonPath.string_at(
                    "$.preprocessing_result.Payload.classification_training_ready"
                ),
            }),
            result_path="$.classification_training_result",
        )

        wait_task = sfn.Wait(
            self,
            "WaitForTraining",
            time=sfn.WaitTime.duration(Duration.minutes(5)),
        )

        check_entity_status_task = sfn_tasks.LambdaInvoke(
            self,
            "CheckEntityModelStatus",
            lambda_function=self.status_checker,
            payload=sfn.TaskInput.from_object({
                "model_type": "entity",
                "training_job_arn": sfn.JsonPath.string_at(
                    "$.entity_training_result.Payload.training_job_arn"
                ),
            }),
            result_path="$.entity_status_result",
        )

        check_classification_status_task = sfn_tasks.LambdaInvoke(
            self,
            "CheckClassificationModelStatus",
            lambda_function=self.status_checker,
            payload=sfn.TaskInput.from_object({
                "model_type": "classification",
                "training_job_arn": sfn.JsonPath.string_at(
                    "$.classification_training_result.Payload.training_job_arn"
                ),
            }),
            result_path="$.classification_status_result",
        )

        training_complete = sfn.Pass(
            self,
            "TrainingComplete",
            result=sfn.Result.from_string("Training pipeline completed successfully"),
        )

        # Define choice condition
        check_complete_choice = sfn.Choice(
            self, "CheckAllModelsComplete"
        ).when(
            sfn.Condition.and_(
                sfn.Condition.boolean_equals(
                    "$.entity_status_result.Payload.is_complete", True
                ),
                sfn.Condition.boolean_equals(
                    "$.classification_status_result.Payload.is_complete", True
                ),
            ),
            training_complete,
        ).otherwise(wait_task)

        # Build the workflow
        definition = (
            preprocess_task
            .next(train_entity_task)
            .next(train_classification_task)
            .next(wait_task)
            .next(check_entity_status_task)
            .next(check_classification_status_task)
            .next(check_complete_choice)
        )

        return sfn.StateMachine(
            self,
            "TrainingWorkflow",
            state_machine_name=f"comprehend-training-pipeline-{self.node.try_get_context('unique_suffix') or 'demo'}",
            definition=definition,
            role=self.comprehend_role,
            timeout=Duration.hours(6),
        )

    def _create_api_gateway(self) -> apigateway.RestApi:
        """Create API Gateway for inference requests."""
        api = apigateway.RestApi(
            self,
            "InferenceApi",
            rest_api_name=f"comprehend-inference-api-{self.node.try_get_context('unique_suffix') or 'demo'}",
            description="API for Comprehend custom model inference",
            deploy_options=apigateway.StageOptions(
                stage_name="prod",
                throttling_rate_limit=1000,
                throttling_burst_limit=2000,
            ),
        )

        # Create Lambda integration
        inference_integration = apigateway.LambdaIntegration(
            self.inference_api,
            request_templates={"application/json": '{"statusCode": "200"}'},
        )

        # Add inference resource and method
        inference_resource = api.root.add_resource("inference")
        inference_resource.add_method(
            "POST",
            inference_integration,
            request_models={
                "application/json": apigateway.Model(
                    self,
                    "InferenceRequestModel",
                    rest_api=api,
                    content_type="application/json",
                    model_name="InferenceRequest",
                    schema=apigateway.JsonSchema(
                        schema=apigateway.JsonSchemaVersion.DRAFT4,
                        type=apigateway.JsonSchemaType.OBJECT,
                        properties={
                            "text": apigateway.JsonSchema(
                                type=apigateway.JsonSchemaType.STRING,
                                description="Text to analyze",
                            ),
                            "entity_model_arn": apigateway.JsonSchema(
                                type=apigateway.JsonSchemaType.STRING,
                                description="Entity recognition model ARN",
                            ),
                            "classifier_model_arn": apigateway.JsonSchema(
                                type=apigateway.JsonSchemaType.STRING,
                                description="Classification model ARN",
                            ),
                        },
                        required=["text"],
                    ),
                )
            },
        )

        # Add CORS support
        inference_resource.add_cors_preflight(
            allow_origins=["*"],
            allow_methods=["POST", "OPTIONS"],
            allow_headers=["Content-Type", "Authorization"],
        )

        return api

    def _get_data_preprocessor_code(self) -> str:
        """Return the data preprocessor Lambda function code."""
        return '''
import json
import boto3
import csv
from io import StringIO
import re

s3 = boto3.client('s3')

def lambda_handler(event, context):
    bucket = event['bucket']
    entity_key = event['entity_training_data']
    classification_key = event['classification_training_data']
    
    try:
        # Process entity training data
        entity_result = process_entity_data(bucket, entity_key)
        
        # Process classification training data
        classification_result = process_classification_data(bucket, classification_key)
        
        return {
            'statusCode': 200,
            'entity_training_ready': entity_result,
            'classification_training_ready': classification_result,
            'bucket': bucket
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'error': str(e)
        }

def process_entity_data(bucket, key):
    # Download and validate entity training data
    response = s3.get_object(Bucket=bucket, Key=key)
    content = response['Body'].read().decode('utf-8')
    
    # Parse CSV and validate format
    csv_reader = csv.DictReader(StringIO(content))
    rows = list(csv_reader)
    
    # Validate required columns
    required_columns = ['Text', 'File', 'Line', 'BeginOffset', 'EndOffset', 'Type']
    if not all(col in csv_reader.fieldnames for col in required_columns):
        raise ValueError(f"Missing required columns. Expected: {required_columns}")
    
    # Validate entity types and counts
    entity_types = {}
    for row in rows:
        entity_type = row['Type']
        entity_types[entity_type] = entity_types.get(entity_type, 0) + 1
    
    # Check minimum examples per entity type
    min_examples = 10
    insufficient_types = [et for et, count in entity_types.items() if count < min_examples]
    
    if insufficient_types:
        print(f"Warning: Entity types with fewer than {min_examples} examples: {insufficient_types}")
    
    # Save processed data
    processed_key = key.replace('.csv', '_processed.csv')
    s3.put_object(
        Bucket=bucket,
        Key=processed_key,
        Body=content,
        ContentType='text/csv'
    )
    
    return {
        'processed_file': processed_key,
        'entity_types': list(entity_types.keys()),
        'total_examples': len(rows),
        'entity_counts': entity_types
    }

def process_classification_data(bucket, key):
    # Download and validate classification training data
    response = s3.get_object(Bucket=bucket, Key=key)
    content = response['Body'].read().decode('utf-8')
    
    # Parse CSV and validate format
    csv_reader = csv.DictReader(StringIO(content))
    rows = list(csv_reader)
    
    # Validate required columns
    required_columns = ['Text', 'Label']
    if not all(col in csv_reader.fieldnames for col in required_columns):
        raise ValueError(f"Missing required columns. Expected: {required_columns}")
    
    # Validate labels and counts
    label_counts = {}
    for row in rows:
        label = row['Label']
        label_counts[label] = label_counts.get(label, 0) + 1
    
    # Check minimum examples per label
    min_examples = 10
    insufficient_labels = [label for label, count in label_counts.items() if count < min_examples]
    
    if insufficient_labels:
        print(f"Warning: Labels with fewer than {min_examples} examples: {insufficient_labels}")
    
    # Save processed data
    processed_key = key.replace('.csv', '_processed.csv')
    s3.put_object(
        Bucket=bucket,
        Key=processed_key,
        Body=content,
        ContentType='text/csv'
    )
    
    return {
        'processed_file': processed_key,
        'labels': list(label_counts.keys()),
        'total_examples': len(rows),
        'label_counts': label_counts
    }
'''

    def _get_model_trainer_code(self) -> str:
        """Return the model trainer Lambda function code."""
        return '''
import json
import boto3
from datetime import datetime
import uuid

comprehend = boto3.client('comprehend')

def lambda_handler(event, context):
    bucket = event['bucket']
    model_type = event['model_type']  # 'entity' or 'classification'
    
    try:
        if model_type == 'entity':
            result = train_entity_model(event)
        elif model_type == 'classification':
            result = train_classification_model(event)
        else:
            raise ValueError(f"Invalid model type: {model_type}")
        
        return {
            'statusCode': 200,
            'model_type': model_type,
            'training_job_arn': result['EntityRecognizerArn'] if model_type == 'entity' else result['DocumentClassifierArn'],
            'training_status': 'SUBMITTED'
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'error': str(e),
            'model_type': model_type
        }

def train_entity_model(event):
    bucket = event['bucket']
    training_data = event['entity_training_ready']['processed_file']
    
    timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
    recognizer_name = f"{event.get('project_name', 'custom')}-entity-{timestamp}"
    
    # Configure training job
    training_config = {
        'RecognizerName': recognizer_name,
        'DataAccessRoleArn': event['role_arn'],
        'InputDataConfig': {
            'EntityTypes': [
                {'Type': entity_type} 
                for entity_type in event['entity_training_ready']['entity_types']
            ],
            'Documents': {
                'S3Uri': f"s3://{bucket}/training-data/entities_sample.txt"
            },
            'Annotations': {
                'S3Uri': f"s3://{bucket}/training-data/{training_data}"
            }
        },
        'LanguageCode': 'en'
    }
    
    # Start training job
    response = comprehend.create_entity_recognizer(**training_config)
    
    return response

def train_classification_model(event):
    bucket = event['bucket']
    training_data = event['classification_training_ready']['processed_file']
    
    timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
    classifier_name = f"{event.get('project_name', 'custom')}-classifier-{timestamp}"
    
    # Configure training job
    training_config = {
        'DocumentClassifierName': classifier_name,
        'DataAccessRoleArn': event['role_arn'],
        'InputDataConfig': {
            'S3Uri': f"s3://{bucket}/training-data/{training_data}"
        },
        'LanguageCode': 'en'
    }
    
    # Start training job
    response = comprehend.create_document_classifier(**training_config)
    
    return response
'''

    def _get_status_checker_code(self) -> str:
        """Return the status checker Lambda function code."""
        return '''
import json
import boto3

comprehend = boto3.client('comprehend')

def lambda_handler(event, context):
    model_type = event['model_type']
    job_arn = event['training_job_arn']
    
    try:
        if model_type == 'entity':
            response = comprehend.describe_entity_recognizer(
                EntityRecognizerArn=job_arn
            )
            status = response['EntityRecognizerProperties']['Status']
            
        elif model_type == 'classification':
            response = comprehend.describe_document_classifier(
                DocumentClassifierArn=job_arn
            )
            status = response['DocumentClassifierProperties']['Status']
        
        else:
            raise ValueError(f"Invalid model type: {model_type}")
        
        # Determine if training is complete
        is_complete = status in ['TRAINED', 'TRAINING_FAILED', 'STOPPED']
        
        return {
            'statusCode': 200,
            'model_type': model_type,
            'training_job_arn': job_arn,
            'training_status': status,
            'is_complete': is_complete,
            'model_details': response
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'error': str(e),
            'model_type': model_type,
            'training_job_arn': job_arn
        }
'''

    def _get_inference_api_code(self) -> str:
        """Return the inference API Lambda function code."""
        return '''
import json
import boto3
import os
import uuid
from datetime import datetime

comprehend = boto3.client('comprehend')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        # Parse request
        body = json.loads(event.get('body', '{}'))
        text = body.get('text', '')
        entity_model_arn = body.get('entity_model_arn')
        classifier_model_arn = body.get('classifier_model_arn')
        
        if not text:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Text is required'})
            }
        
        results = {}
        
        # Perform entity recognition if model is provided
        if entity_model_arn:
            entity_results = comprehend.detect_entities(
                Text=text,
                EndpointArn=entity_model_arn
            )
            results['entities'] = entity_results['Entities']
        
        # Perform classification if model is provided
        if classifier_model_arn:
            classification_results = comprehend.classify_document(
                Text=text,
                EndpointArn=classifier_model_arn
            )
            results['classification'] = classification_results['Classes']
        
        # Store results (optional)
        if os.environ.get('RESULTS_TABLE'):
            store_results(text, results)
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'text': text,
                'results': results,
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def store_results(text, results):
    table_name = os.environ['RESULTS_TABLE']
    table = dynamodb.Table(table_name)
    
    item = {
        'id': str(uuid.uuid4()),
        'text': text,
        'results': json.dumps(results),
        'timestamp': int(datetime.now().timestamp())
    }
    
    table.put_item(Item=item)
'''


app = cdk.App()

# Get unique suffix from context or generate one
unique_suffix = app.node.try_get_context("unique_suffix")
if not unique_suffix:
    import secrets
    unique_suffix = secrets.token_hex(3)

# Create the stack
ComprehendCustomModelsStack(
    app,
    "ComprehendCustomModelsStack",
    env=cdk.Environment(
        account=os.getenv("CDK_DEFAULT_ACCOUNT"),
        region=os.getenv("CDK_DEFAULT_REGION", "us-east-1"),
    ),
    description="Custom Entity Recognition and Classification with Amazon Comprehend",
)

app.synth()