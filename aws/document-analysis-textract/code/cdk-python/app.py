#!/usr/bin/env python3
"""
CDK Application for Document Analysis with Amazon Textract

This application deploys a comprehensive document analysis solution using Amazon Textract
with automated workflow orchestration through Step Functions, Lambda functions for
processing logic, and S3 for document storage.

Author: AWS CDK Generator
Version: 1.0
"""

import os
from aws_cdk import (
    App,
    Environment,
    Duration,
    RemovalPolicy,
    Stack,
    StackProps,
    aws_s3 as s3,
    aws_lambda as _lambda,
    aws_stepfunctions as sfn,
    aws_stepfunctions_tasks as sfn_tasks,
    aws_dynamodb as dynamodb,
    aws_sns as sns,
    aws_iam as iam,
    aws_s3_notifications as s3n,
)
from constructs import Construct
from typing import Dict, Any


class DocumentAnalysisStack(Stack):
    """
    CDK Stack for Document Analysis with Amazon Textract
    
    This stack creates:
    - S3 buckets for input and output documents
    - Lambda functions for document processing
    - Step Functions workflow for orchestration
    - DynamoDB table for metadata storage
    - SNS topic for notifications
    - IAM roles with appropriate permissions
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource naming
        unique_suffix = self.node.try_get_context("uniqueSuffix") or "dev"
        project_name = f"textract-analysis-{unique_suffix}"

        # Create S3 buckets for document storage
        self._create_storage_resources(project_name)
        
        # Create DynamoDB table for metadata
        self._create_database_resources(project_name)
        
        # Create SNS topic for notifications
        self._create_notification_resources(project_name)
        
        # Create IAM execution role
        self._create_iam_resources(project_name)
        
        # Create Lambda functions
        self._create_lambda_functions(project_name)
        
        # Create Step Functions workflow
        self._create_step_functions_workflow(project_name)
        
        # Configure S3 event notifications
        self._configure_s3_notifications()

    def _create_storage_resources(self, project_name: str) -> None:
        """Create S3 buckets for input and output document storage."""
        
        # Input bucket for document uploads
        self.input_bucket = s3.Bucket(
            self, "InputBucket",
            bucket_name=f"{project_name}-input",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="CleanupRule",
                    enabled=True,
                    expiration=Duration.days(30),
                    noncurrent_version_expiration=Duration.days(7)
                )
            ]
        )

        # Output bucket for processed results
        self.output_bucket = s3.Bucket(
            self, "OutputBucket",
            bucket_name=f"{project_name}-output",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ArchiveRule",
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

    def _create_database_resources(self, project_name: str) -> None:
        """Create DynamoDB table for document metadata storage."""
        
        self.metadata_table = dynamodb.Table(
            self, "MetadataTable",
            table_name=f"{project_name}-metadata",
            partition_key=dynamodb.Attribute(
                name="documentId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES
        )

        # Add GSI for querying by document type
        self.metadata_table.add_global_secondary_index(
            index_name="DocumentTypeIndex",
            partition_key=dynamodb.Attribute(
                name="documentType",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="timestamp",
                type=dynamodb.AttributeType.STRING
            )
        )

    def _create_notification_resources(self, project_name: str) -> None:
        """Create SNS topic for processing notifications."""
        
        self.notification_topic = sns.Topic(
            self, "NotificationTopic",
            topic_name=f"{project_name}-notifications",
            display_name="Document Processing Notifications"
        )

    def _create_iam_resources(self, project_name: str) -> None:
        """Create IAM execution role with appropriate permissions."""
        
        self.execution_role = iam.Role(
            self, "ExecutionRole",
            role_name=f"{project_name}-execution-role",
            assumed_by=iam.CompositePrincipal(
                iam.ServicePrincipal("lambda.amazonaws.com"),
                iam.ServicePrincipal("states.amazonaws.com")
            ),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonTextractFullAccess")
            ]
        )

        # Add custom policy for S3, DynamoDB, and SNS access
        self.execution_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket"
                ],
                resources=[
                    self.input_bucket.bucket_arn,
                    f"{self.input_bucket.bucket_arn}/*",
                    self.output_bucket.bucket_arn,
                    f"{self.output_bucket.bucket_arn}/*"
                ]
            )
        )

        self.execution_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:GetItem",
                    "dynamodb:PutItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:DeleteItem",
                    "dynamodb:Query",
                    "dynamodb:Scan"
                ],
                resources=[
                    self.metadata_table.table_arn,
                    f"{self.metadata_table.table_arn}/index/*"
                ]
            )
        )

        self.execution_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "sns:Publish",
                    "sns:Subscribe",
                    "sns:Unsubscribe"
                ],
                resources=[self.notification_topic.topic_arn]
            )
        )

    def _create_lambda_functions(self, project_name: str) -> None:
        """Create Lambda functions for document processing."""
        
        # Common environment variables
        common_env = {
            "OUTPUT_BUCKET": self.output_bucket.bucket_name,
            "METADATA_TABLE": self.metadata_table.table_name,
            "SNS_TOPIC_ARN": self.notification_topic.topic_arn,
            "EXECUTION_ROLE_ARN": self.execution_role.role_arn
        }

        # Document classifier function
        self.classifier_function = _lambda.Function(
            self, "DocumentClassifier",
            function_name=f"{project_name}-document-classifier",
            runtime=_lambda.Runtime.PYTHON_3_9,
            code=_lambda.Code.from_inline(self._get_classifier_code()),
            handler="index.lambda_handler",
            timeout=Duration.seconds(30),
            memory_size=512,
            role=self.execution_role,
            environment=common_env,
            description="Classifies documents and determines processing type"
        )

        # Textract processor function
        self.processor_function = _lambda.Function(
            self, "TextractProcessor",
            function_name=f"{project_name}-textract-processor",
            runtime=_lambda.Runtime.PYTHON_3_9,
            code=_lambda.Code.from_inline(self._get_processor_code()),
            handler="index.lambda_handler",
            timeout=Duration.minutes(5),
            memory_size=1024,
            role=self.execution_role,
            environment=common_env,
            description="Processes documents using Amazon Textract"
        )

        # Async results processor function
        self.async_processor_function = _lambda.Function(
            self, "AsyncResultsProcessor",
            function_name=f"{project_name}-async-results-processor",
            runtime=_lambda.Runtime.PYTHON_3_9,
            code=_lambda.Code.from_inline(self._get_async_processor_code()),
            handler="index.lambda_handler",
            timeout=Duration.minutes(5),
            memory_size=1024,
            role=self.execution_role,
            environment=common_env,
            description="Processes asynchronous Textract job results"
        )

        # Document query function
        self.query_function = _lambda.Function(
            self, "DocumentQuery",
            function_name=f"{project_name}-document-query",
            runtime=_lambda.Runtime.PYTHON_3_9,
            code=_lambda.Code.from_inline(self._get_query_code()),
            handler="index.lambda_handler",
            timeout=Duration.seconds(30),
            memory_size=512,
            role=self.execution_role,
            environment=common_env,
            description="Queries document processing results"
        )

        # Subscribe async processor to SNS topic
        self.notification_topic.add_subscription(
            sns.LambdaSubscription(self.async_processor_function)
        )

    def _create_step_functions_workflow(self, project_name: str) -> None:
        """Create Step Functions state machine for workflow orchestration."""
        
        # Define the workflow steps
        classify_task = sfn_tasks.LambdaInvoke(
            self, "ClassifyDocument",
            lambda_function=self.classifier_function,
            output_path="$.Payload"
        )

        process_task = sfn_tasks.LambdaInvoke(
            self, "ProcessDocument",
            lambda_function=self.processor_function,
            output_path="$.Payload"
        )

        check_processing_type = sfn.Choice(self, "CheckProcessingType")

        wait_for_async = sfn.Wait(
            self, "WaitForAsyncCompletion",
            time=sfn.WaitTime.duration(Duration.seconds(30))
        )

        check_async_status = sfn_tasks.CallAwsService(
            self, "CheckAsyncStatus",
            service="textract",
            action="getDocumentAnalysis",
            parameters={
                "JobId.$": "$.body.result.jobId"
            },
            iam_resources=["*"]
        )

        is_async_complete = sfn.Choice(self, "IsAsyncComplete")

        processing_complete = sfn.Pass(
            self, "ProcessingComplete",
            result=sfn.Result.from_string("Document processing completed successfully")
        )

        processing_failed = sfn.Fail(
            self, "ProcessingFailed",
            error="DocumentProcessingFailed",
            cause="Textract processing failed"
        )

        # Define the workflow
        definition = classify_task.next(
            process_task.next(
                check_processing_type
                .when(
                    sfn.Condition.string_equals("$.body.processingType", "async"),
                    wait_for_async.next(
                        check_async_status.next(
                            is_async_complete
                            .when(
                                sfn.Condition.string_equals("$.JobStatus", "SUCCEEDED"),
                                processing_complete
                            )
                            .when(
                                sfn.Condition.string_equals("$.JobStatus", "FAILED"),
                                processing_failed
                            )
                            .otherwise(wait_for_async)
                        )
                    )
                )
                .otherwise(processing_complete)
            )
        )

        # Create the state machine
        self.state_machine = sfn.StateMachine(
            self, "DocumentAnalysisWorkflow",
            state_machine_name=f"{project_name}-workflow",
            definition=definition,
            role=self.execution_role,
            timeout=Duration.minutes(30)
        )

    def _configure_s3_notifications(self) -> None:
        """Configure S3 event notifications to trigger the workflow."""
        
        self.input_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3n.LambdaDestination(self.classifier_function),
            s3.NotificationKeyFilter(
                prefix="documents/",
                suffix=".pdf"
            )
        )

    def _get_classifier_code(self) -> str:
        """Return the Lambda code for document classifier."""
        return '''
import json
import boto3
import os
from urllib.parse import unquote_plus

s3 = boto3.client('s3')

def lambda_handler(event, context):
    try:
        # Parse S3 event
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = unquote_plus(event['Records'][0]['s3']['object']['key'])
        
        # Get object metadata
        response = s3.head_object(Bucket=bucket, Key=key)
        file_size = response['ContentLength']
        
        # Determine processing type based on file size and type
        # Files under 5MB for synchronous, larger for asynchronous
        processing_type = 'sync' if file_size < 5 * 1024 * 1024 else 'async'
        
        # Determine document type based on filename
        doc_type = 'invoice' if 'invoice' in key.lower() else 'form' if 'form' in key.lower() else 'general'
        
        return {
            'statusCode': 200,
            'body': {
                'bucket': bucket,
                'key': key,
                'processingType': processing_type,
                'documentType': doc_type,
                'fileSize': file_size
            }
        }
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
'''

    def _get_processor_code(self) -> str:
        """Return the Lambda code for Textract processor."""
        return '''
import json
import boto3
import uuid
import os
from datetime import datetime

textract = boto3.client('textract')
s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')

def lambda_handler(event, context):
    try:
        # Get input parameters
        bucket = event['bucket']
        key = event['key']
        processing_type = event['processingType']
        document_type = event['documentType']
        
        document_id = str(uuid.uuid4())
        
        # Process document based on type
        if processing_type == 'sync':
            result = process_sync_document(bucket, key, document_type)
        else:
            result = process_async_document(bucket, key, document_type)
        
        # Store metadata in DynamoDB
        store_metadata(document_id, bucket, key, document_type, result)
        
        # Send notification
        send_notification(document_id, document_type, result.get('status', 'completed'))
        
        return {
            'statusCode': 200,
            'body': {
                'documentId': document_id,
                'processingType': processing_type,
                'result': result
            }
        }
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def process_sync_document(bucket, key, document_type):
    """Process single-page document synchronously"""
    try:
        # Determine features based on document type
        features = ['TABLES', 'FORMS'] if document_type in ['invoice', 'form'] else ['TABLES']
        
        response = textract.analyze_document(
            Document={'S3Object': {'Bucket': bucket, 'Name': key}},
            FeatureTypes=features
        )
        
        # Extract and structure data
        extracted_data = extract_structured_data(response)
        
        # Save results to S3
        output_key = f"results/{key.split('/')[-1]}-analysis.json"
        s3.put_object(
            Bucket=os.environ['OUTPUT_BUCKET'],
            Key=output_key,
            Body=json.dumps(extracted_data, indent=2),
            ContentType='application/json'
        )
        
        return {
            'status': 'completed',
            'outputLocation': f"s3://{os.environ['OUTPUT_BUCKET']}/{output_key}",
            'extractedData': extracted_data
        }
    except Exception as e:
        print(f"Sync processing error: {str(e)}")
        raise

def process_async_document(bucket, key, document_type):
    """Start asynchronous document processing"""
    try:
        features = ['TABLES', 'FORMS'] if document_type in ['invoice', 'form'] else ['TABLES']
        
        response = textract.start_document_analysis(
            DocumentLocation={'S3Object': {'Bucket': bucket, 'Name': key}},
            FeatureTypes=features,
            NotificationChannel={
                'SNSTopicArn': os.environ['SNS_TOPIC_ARN'],
                'RoleArn': os.environ['EXECUTION_ROLE_ARN']
            }
        )
        
        return {
            'status': 'in_progress',
            'jobId': response['JobId']
        }
    except Exception as e:
        print(f"Async processing error: {str(e)}")
        raise

def extract_structured_data(response):
    """Extract structured data from Textract response"""
    blocks = response['Blocks']
    
    # Extract text lines
    lines = []
    tables = []
    forms = []
    
    for block in blocks:
        if block['BlockType'] == 'LINE':
            lines.append({
                'text': block.get('Text', ''),
                'confidence': block.get('Confidence', 0)
            })
        elif block['BlockType'] == 'TABLE':
            tables.append({
                'id': block['Id'],
                'confidence': block.get('Confidence', 0)
            })
        elif block['BlockType'] == 'KEY_VALUE_SET':
            forms.append({
                'id': block['Id'],
                'confidence': block.get('Confidence', 0)
            })
    
    return {
        'text_lines': lines,
        'tables': tables,
        'forms': forms,
        'document_metadata': response.get('DocumentMetadata', {})
    }

def store_metadata(document_id, bucket, key, document_type, result):
    """Store document metadata in DynamoDB"""
    table = dynamodb.Table(os.environ['METADATA_TABLE'])
    
    table.put_item(
        Item={
            'documentId': document_id,
            'bucket': bucket,
            'key': key,
            'documentType': document_type,
            'processingStatus': result.get('status', 'completed'),
            'jobId': result.get('jobId'),
            'outputLocation': result.get('outputLocation'),
            'timestamp': datetime.utcnow().isoformat()
        }
    )

def send_notification(document_id, document_type, status):
    """Send processing notification"""
    message = {
        'documentId': document_id,
        'documentType': document_type,
        'status': status,
        'timestamp': datetime.utcnow().isoformat()
    }
    
    sns.publish(
        TopicArn=os.environ['SNS_TOPIC_ARN'],
        Message=json.dumps(message),
        Subject=f'Document Processing {status.title()}'
    )
'''

    def _get_async_processor_code(self) -> str:
        """Return the Lambda code for async results processor."""
        return '''
import json
import boto3
import os
from datetime import datetime

textract = boto3.client('textract')
s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        # Parse SNS message
        sns_message = json.loads(event['Records'][0]['Sns']['Message'])
        job_id = sns_message['JobId']
        status = sns_message['Status']
        
        if status == 'SUCCEEDED':
            # Get results from Textract
            response = textract.get_document_analysis(JobId=job_id)
            
            # Process results
            extracted_data = extract_structured_data(response)
            
            # Save to S3
            output_key = f"async-results/{job_id}-analysis.json"
            s3.put_object(
                Bucket=os.environ['OUTPUT_BUCKET'],
                Key=output_key,
                Body=json.dumps(extracted_data, indent=2),
                ContentType='application/json'
            )
            
            # Update DynamoDB
            update_document_metadata(job_id, 'completed', output_key)
            
            print(f"Successfully processed job {job_id}")
        else:
            # Update DynamoDB with failed status
            update_document_metadata(job_id, 'failed', None)
            print(f"Job {job_id} failed")
            
        return {'statusCode': 200}
    except Exception as e:
        print(f"Error: {str(e)}")
        return {'statusCode': 500}

def extract_structured_data(response):
    """Extract structured data from Textract response"""
    blocks = response['Blocks']
    
    lines = []
    tables = []
    forms = []
    
    for block in blocks:
        if block['BlockType'] == 'LINE':
            lines.append({
                'text': block.get('Text', ''),
                'confidence': block.get('Confidence', 0)
            })
        elif block['BlockType'] == 'TABLE':
            tables.append({
                'id': block['Id'],
                'confidence': block.get('Confidence', 0)
            })
        elif block['BlockType'] == 'KEY_VALUE_SET':
            forms.append({
                'id': block['Id'],
                'confidence': block.get('Confidence', 0)
            })
    
    return {
        'text_lines': lines,
        'tables': tables,
        'forms': forms,
        'document_metadata': response.get('DocumentMetadata', {})
    }

def update_document_metadata(job_id, status, output_location):
    """Update document metadata in DynamoDB"""
    table = dynamodb.Table(os.environ['METADATA_TABLE'])
    
    # Find document by job ID
    response = table.scan(
        FilterExpression='jobId = :jid',
        ExpressionAttributeValues={':jid': job_id}
    )
    
    if response['Items']:
        document_id = response['Items'][0]['documentId']
        
        table.update_item(
            Key={'documentId': document_id},
            UpdateExpression='SET processingStatus = :status, outputLocation = :location, completedAt = :timestamp',
            ExpressionAttributeValues={
                ':status': status,
                ':location': output_location,
                ':timestamp': datetime.utcnow().isoformat()
            }
        )
'''

    def _get_query_code(self) -> str:
        """Return the Lambda code for document query function."""
        return '''
import json
import boto3
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    try:
        # Get query parameters
        document_id = event.get('documentId')
        document_type = event.get('documentType')
        
        table = dynamodb.Table(os.environ['METADATA_TABLE'])
        
        if document_id:
            # Query specific document
            response = table.get_item(Key={'documentId': document_id})
            if 'Item' in response:
                return {
                    'statusCode': 200,
                    'body': json.dumps(response['Item'], default=str)
                }
            else:
                return {
                    'statusCode': 404,
                    'body': json.dumps({'error': 'Document not found'})
                }
        
        elif document_type:
            # Query by document type
            response = table.scan(
                FilterExpression='documentType = :dt',
                ExpressionAttributeValues={':dt': document_type}
            )
            return {
                'statusCode': 200,
                'body': json.dumps(response['Items'], default=str)
            }
        
        else:
            # Return all documents
            response = table.scan()
            return {
                'statusCode': 200,
                'body': json.dumps(response['Items'], default=str)
            }
            
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
'''


# CDK Application entry point
app = App()

# Get environment configuration
env = Environment(
    account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
    region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
)

# Create the stack
DocumentAnalysisStack(
    app, "DocumentAnalysisStack",
    env=env,
    description="Document Analysis with Amazon Textract - CDK Python Implementation"
)

app.synth()