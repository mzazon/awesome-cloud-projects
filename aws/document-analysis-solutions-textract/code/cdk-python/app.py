#!/usr/bin/env python3
"""
CDK Application for Amazon Textract Document Analysis Solution

This application deploys a complete document analysis pipeline using Amazon Textract,
including S3 buckets, Lambda functions, SNS notifications, and IAM roles.
"""

import os
from aws_cdk import (
    App,
    Environment,
    Stack,
    StackProps,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_lambda as lambda_,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    aws_iam as iam,
    aws_s3_notifications as s3_notifications,
    aws_logs as logs,
)
from constructs import Construct


class TextractDocumentAnalysisStack(Stack):
    """
    CDK Stack for Amazon Textract Document Analysis Solution
    
    This stack creates:
    - S3 buckets for input and output documents
    - Lambda function for document processing
    - SNS topic for notifications
    - IAM roles and policies
    - S3 event triggers
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create S3 bucket for input documents
        self.input_bucket = s3.Bucket(
            self,
            "InputBucket",
            bucket_name=f"textract-input-{self.account}-{self.region}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    noncurrent_version_expiration=Duration.days(30),
                    expired_object_delete_marker=True,
                )
            ],
            cors=[
                s3.CorsRule(
                    allowed_methods=[s3.HttpMethods.GET, s3.HttpMethods.PUT],
                    allowed_origins=["*"],
                    allowed_headers=["*"],
                    max_age=3000,
                )
            ],
        )

        # Create S3 bucket for output documents
        self.output_bucket = s3.Bucket(
            self,
            "OutputBucket",
            bucket_name=f"textract-output-{self.account}-{self.region}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="TransitionToIA",
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30),
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90),
                        ),
                    ],
                )
            ],
        )

        # Create SNS topic for notifications
        self.notification_topic = sns.Topic(
            self,
            "NotificationTopic",
            topic_name=f"textract-notifications-{self.account}-{self.region}",
            display_name="Textract Document Processing Notifications",
            description="SNS topic for Textract document processing notifications",
        )

        # Create IAM role for Lambda function
        self.lambda_role = iam.Role(
            self,
            "TextractLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for Textract document processing Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Add inline policy for Textract, S3, and SNS permissions
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "textract:DetectDocumentText",
                    "textract:AnalyzeDocument",
                    "textract:StartDocumentTextDetection",
                    "textract:StartDocumentAnalysis",
                    "textract:GetDocumentTextDetection",
                    "textract:GetDocumentAnalysis",
                ],
                resources=["*"],
            )
        )

        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:GetObjectVersion",
                ],
                resources=[
                    self.input_bucket.bucket_arn + "/*",
                    self.output_bucket.bucket_arn + "/*",
                ],
            )
        )

        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["sns:Publish"],
                resources=[self.notification_topic.topic_arn],
            )
        )

        # Create Lambda function for document processing
        self.processor_function = lambda_.Function(
            self,
            "TextractProcessor",
            function_name=f"textract-processor-{self.account}-{self.region}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="textract_processor.lambda_handler",
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=512,
            environment={
                "OUTPUT_BUCKET": self.output_bucket.bucket_name,
                "SNS_TOPIC_ARN": self.notification_topic.topic_arn,
                "LOG_LEVEL": "INFO",
            },
            description="Lambda function for processing documents with Amazon Textract",
            log_retention=logs.RetentionDays.ONE_WEEK,
            retry_attempts=2,
        )

        # Create S3 event notification to trigger Lambda
        self.input_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3_notifications.LambdaDestination(self.processor_function),
            s3.NotificationKeyFilter(suffix=".pdf"),
        )

        # Also support common image formats
        for suffix in [".jpg", ".jpeg", ".png", ".tiff", ".tif"]:
            self.input_bucket.add_event_notification(
                s3.EventType.OBJECT_CREATED,
                s3_notifications.LambdaDestination(self.processor_function),
                s3.NotificationKeyFilter(suffix=suffix),
            )

        # Create CloudWatch Log Group for Lambda function
        self.log_group = logs.LogGroup(
            self,
            "ProcessorLogGroup",
            log_group_name=f"/aws/lambda/{self.processor_function.function_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create outputs
        CfnOutput(
            self,
            "InputBucketName",
            value=self.input_bucket.bucket_name,
            description="S3 bucket name for input documents",
            export_name=f"{self.stack_name}-InputBucket",
        )

        CfnOutput(
            self,
            "OutputBucketName",
            value=self.output_bucket.bucket_name,
            description="S3 bucket name for processed documents",
            export_name=f"{self.stack_name}-OutputBucket",
        )

        CfnOutput(
            self,
            "ProcessorFunctionName",
            value=self.processor_function.function_name,
            description="Lambda function name for document processing",
            export_name=f"{self.stack_name}-ProcessorFunction",
        )

        CfnOutput(
            self,
            "NotificationTopicArn",
            value=self.notification_topic.topic_arn,
            description="SNS topic ARN for notifications",
            export_name=f"{self.stack_name}-NotificationTopic",
        )

        CfnOutput(
            self,
            "TestCommand",
            value=f"aws s3 cp test-document.pdf s3://{self.input_bucket.bucket_name}/test-documents/",
            description="Command to test document processing",
        )

    def _get_lambda_code(self) -> str:
        """
        Returns the Lambda function code for document processing.
        
        Returns:
            str: Lambda function code as a string
        """
        return """
import json
import boto3
import os
import logging
from datetime import datetime
from typing import Dict, Any, List
from urllib.parse import unquote_plus

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
textract = boto3.client('textract')
s3 = boto3.client('s3')
sns = boto3.client('sns')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for processing documents with Amazon Textract.
    
    Args:
        event: S3 event triggering the function
        context: Lambda context object
        
    Returns:
        Dict containing processing results
    """
    try:
        # Parse S3 event
        s3_event = event['Records'][0]['s3']
        bucket_name = s3_event['bucket']['name']
        object_key = unquote_plus(s3_event['object']['key'])
        
        logger.info(f"Processing document: {object_key} from bucket: {bucket_name}")
        
        # Determine document type and processing features
        file_extension = object_key.lower().split('.')[-1]
        processing_features = get_processing_features(file_extension)
        
        # Analyze document with Textract
        response = textract.analyze_document(
            Document={
                'S3Object': {
                    'Bucket': bucket_name,
                    'Name': object_key
                }
            },
            FeatureTypes=processing_features.get('features', ['TABLES', 'FORMS']),
            QueriesConfig={
                'Queries': [
                    {'Text': 'What is the document type?'},
                    {'Text': 'What is the total amount?'},
                    {'Text': 'What is the date?'},
                    {'Text': 'What is the invoice number?'},
                    {'Text': 'Who is the sender?'},
                    {'Text': 'Who is the recipient?'}
                ]
            } if 'QUERIES' in processing_features.get('features', []) else None
        )
        
        # Extract structured data
        extracted_data = extract_document_data(response, object_key)
        
        # Save results to output bucket
        output_key = f"processed/{datetime.now().strftime('%Y/%m/%d')}/{object_key.split('/')[-1]}.json"
        s3.put_object(
            Bucket=os.environ['OUTPUT_BUCKET'],
            Key=output_key,
            Body=json.dumps(extracted_data, indent=2, default=str),
            ContentType='application/json',
            ServerSideEncryption='AES256'
        )
        
        # Send success notification
        success_message = create_success_message(object_key, output_key, extracted_data)
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=success_message,
            Subject=f'✅ Document Processed Successfully: {object_key.split("/")[-1]}'
        )
        
        logger.info(f"Successfully processed document: {object_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Document processed successfully',
                'input_document': f's3://{bucket_name}/{object_key}',
                'output_location': f's3://{os.environ["OUTPUT_BUCKET"]}/{output_key}',
                'processing_time': datetime.now().isoformat(),
                'confidence_score': extracted_data.get('average_confidence', 0)
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing document {object_key}: {str(e)}")
        
        # Send error notification
        error_message = create_error_message(object_key, str(e))
        try:
            sns.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Message=error_message,
                Subject=f'❌ Document Processing Error: {object_key.split("/")[-1]}'
            )
        except Exception as sns_error:
            logger.error(f"Failed to send error notification: {str(sns_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'document': object_key,
                'timestamp': datetime.now().isoformat()
            })
        }


def get_processing_features(file_extension: str) -> Dict[str, List[str]]:
    """
    Determine Textract processing features based on file type.
    
    Args:
        file_extension: File extension (pdf, jpg, png, etc.)
        
    Returns:
        Dict containing processing features
    """
    feature_map = {
        'pdf': ['TABLES', 'FORMS', 'QUERIES'],
        'jpg': ['TABLES', 'FORMS'],
        'jpeg': ['TABLES', 'FORMS'],
        'png': ['TABLES', 'FORMS'],
        'tiff': ['TABLES', 'FORMS'],
        'tif': ['TABLES', 'FORMS']
    }
    
    return {
        'features': feature_map.get(file_extension, ['TABLES', 'FORMS'])
    }


def extract_document_data(response: Dict[str, Any], object_key: str) -> Dict[str, Any]:
    """
    Extract structured data from Textract response.
    
    Args:
        response: Textract analyze_document response
        object_key: S3 object key
        
    Returns:
        Dict containing extracted data
    """
    blocks = response.get('Blocks', [])
    
    # Calculate confidence scores
    confidence_scores = [
        block.get('Confidence', 0) for block in blocks 
        if 'Confidence' in block
    ]
    average_confidence = sum(confidence_scores) / len(confidence_scores) if confidence_scores else 0
    
    # Extract key-value pairs
    key_value_pairs = extract_key_value_pairs(blocks)
    
    # Extract tables
    tables = extract_tables(blocks)
    
    # Extract queries (if present)
    queries = extract_queries(blocks)
    
    return {
        'document_name': object_key,
        'processed_at': datetime.now().isoformat(),
        'average_confidence': round(average_confidence, 2),
        'total_blocks': len(blocks),
        'key_value_pairs': key_value_pairs,
        'tables': tables,
        'queries': queries,
        'document_metadata': response.get('DocumentMetadata', {}),
        'raw_blocks': blocks  # Include raw blocks for advanced processing
    }


def extract_key_value_pairs(blocks: List[Dict[str, Any]]) -> Dict[str, str]:
    """
    Extract form key-value pairs from Textract blocks.
    
    Args:
        blocks: List of Textract blocks
        
    Returns:
        Dict of key-value pairs
    """
    key_map = {}
    value_map = {}
    block_map = {block['Id']: block for block in blocks}
    
    # Build key and value maps
    for block in blocks:
        if block.get('BlockType') == 'KEY_VALUE_SET':
            if 'KEY' in block.get('EntityTypes', []):
                key_map[block['Id']] = block
            else:
                value_map[block['Id']] = block
    
    # Match keys with values
    key_value_pairs = {}
    for key_id, key_block in key_map.items():
        key_text = get_text_from_block(key_block, block_map)
        value_text = ""
        
        # Find associated value block
        for relationship in key_block.get('Relationships', []):
            if relationship['Type'] == 'VALUE':
                for value_id in relationship['Ids']:
                    if value_id in value_map:
                        value_text = get_text_from_block(value_map[value_id], block_map)
                        break
        
        if key_text:
            key_value_pairs[key_text] = value_text
    
    return key_value_pairs


def extract_tables(blocks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """
    Extract table data from Textract blocks.
    
    Args:
        blocks: List of Textract blocks
        
    Returns:
        List of table data
    """
    tables = []
    block_map = {block['Id']: block for block in blocks}
    
    for block in blocks:
        if block.get('BlockType') == 'TABLE':
            table_data = {
                'table_id': block['Id'],
                'confidence': block.get('Confidence', 0),
                'rows': []
            }
            
            # Extract cells
            cells = {}
            for relationship in block.get('Relationships', []):
                if relationship['Type'] == 'CHILD':
                    for cell_id in relationship['Ids']:
                        if cell_id in block_map:
                            cell_block = block_map[cell_id]
                            if cell_block.get('BlockType') == 'CELL':
                                row_index = cell_block.get('RowIndex', 0)
                                col_index = cell_block.get('ColumnIndex', 0)
                                
                                if row_index not in cells:
                                    cells[row_index] = {}
                                
                                cells[row_index][col_index] = get_text_from_block(cell_block, block_map)
            
            # Convert to ordered rows
            for row_index in sorted(cells.keys()):
                row_data = []
                for col_index in sorted(cells[row_index].keys()):
                    row_data.append(cells[row_index][col_index])
                table_data['rows'].append(row_data)
            
            tables.append(table_data)
    
    return tables


def extract_queries(blocks: List[Dict[str, Any]]) -> List[Dict[str, str]]:
    """
    Extract query results from Textract blocks.
    
    Args:
        blocks: List of Textract blocks
        
    Returns:
        List of query results
    """
    queries = []
    
    for block in blocks:
        if block.get('BlockType') == 'QUERY':
            query_data = {
                'query': block.get('Query', {}).get('Text', ''),
                'confidence': block.get('Confidence', 0)
            }
            queries.append(query_data)
        elif block.get('BlockType') == 'QUERY_RESULT':
            query_result = {
                'answer': block.get('Text', ''),
                'confidence': block.get('Confidence', 0)
            }
            # Find the corresponding query
            if queries:
                queries[-1].update(query_result)
    
    return queries


def get_text_from_block(block: Dict[str, Any], block_map: Dict[str, Dict[str, Any]]) -> str:
    """
    Extract text from a Textract block.
    
    Args:
        block: Textract block
        block_map: Map of block IDs to blocks
        
    Returns:
        Extracted text
    """
    text = ""
    
    if block.get('BlockType') == 'WORD':
        return block.get('Text', '')
    
    for relationship in block.get('Relationships', []):
        if relationship['Type'] == 'CHILD':
            for child_id in relationship['Ids']:
                if child_id in block_map:
                    child_block = block_map[child_id]
                    if child_block.get('BlockType') == 'WORD':
                        text += child_block.get('Text', '') + ' '
    
    return text.strip()


def create_success_message(object_key: str, output_key: str, extracted_data: Dict[str, Any]) -> str:
    """
    Create success notification message.
    
    Args:
        object_key: Input document key
        output_key: Output document key
        extracted_data: Extracted document data
        
    Returns:
        Formatted success message
    """
    return f"""
Document Processing Complete ✅

Document: {object_key}
Processed at: {extracted_data['processed_at']}
Confidence Score: {extracted_data['average_confidence']}%
Total Blocks: {extracted_data['total_blocks']}
Key-Value Pairs: {len(extracted_data['key_value_pairs'])}
Tables: {len(extracted_data['tables'])}

Output Location: s3://{os.environ['OUTPUT_BUCKET']}/{output_key}

Summary of extracted data:
{json.dumps(extracted_data['key_value_pairs'], indent=2) if extracted_data['key_value_pairs'] else 'No key-value pairs found'}
"""


def create_error_message(object_key: str, error: str) -> str:
    """
    Create error notification message.
    
    Args:
        object_key: Input document key
        error: Error message
        
    Returns:
        Formatted error message
    """
    return f"""
Document Processing Error ❌

Document: {object_key}
Error: {error}
Timestamp: {datetime.now().isoformat()}

Please check the document format and try again.
Supported formats: PDF, JPG, JPEG, PNG, TIFF
"""
"""


def main():
    """
    Main function to deploy the CDK application.
    """
    app = App()
    
    # Get environment from context or use default
    env = Environment(
        account=os.environ.get('CDK_DEFAULT_ACCOUNT'),
        region=os.environ.get('CDK_DEFAULT_REGION', 'us-east-1')
    )
    
    # Create the stack
    TextractDocumentAnalysisStack(
        app,
        "TextractDocumentAnalysisStack",
        env=env,
        description="Amazon Textract Document Analysis Solution - CDK Python Implementation",
        tags={
            "Project": "TextractDocumentAnalysis",
            "Environment": "Development",
            "CreatedBy": "CDK",
            "CostCenter": "Research"
        }
    )
    
    app.synth()


if __name__ == "__main__":
    main()