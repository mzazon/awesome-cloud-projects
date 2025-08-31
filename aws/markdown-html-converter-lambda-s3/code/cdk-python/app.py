#!/usr/bin/env python3
"""
AWS CDK Python application for Simple Markdown to HTML Converter
Based on AWS recipe: markdown-html-converter-lambda-s3

This application creates a serverless document converter using AWS Lambda and S3
that automatically transforms uploaded Markdown files into formatted HTML.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    aws_s3 as s3,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_s3_notifications as s3n,
    RemovalPolicy,
)
from constructs import Construct


class MarkdownHtmlConverterStack(Stack):
    """
    CDK Stack for Markdown to HTML Converter using Lambda and S3.
    
    This stack creates:
    - Input S3 bucket for Markdown files
    - Output S3 bucket for HTML files  
    - Lambda function for Markdown to HTML conversion
    - IAM roles and policies
    - S3 event triggers
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create input S3 bucket for Markdown files
        self.input_bucket = s3.Bucket(
            self,
            "MarkdownInputBucket",
            bucket_name=f"markdown-input-{self.account}-{self.region}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            versioned=True,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Create output S3 bucket for HTML files
        self.output_bucket = s3.Bucket(
            self,
            "HtmlOutputBucket",
            bucket_name=f"markdown-output-{self.account}-{self.region}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            versioned=True,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Create Lambda execution role
        lambda_role = iam.Role(
            self,
            "MarkdownConverterLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Add S3 permissions to Lambda role
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["s3:GetObject"],
                resources=[f"{self.input_bucket.bucket_arn}/*"],
            )
        )

        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["s3:PutObject"],
                resources=[f"{self.output_bucket.bucket_arn}/*"],
            )
        )

        # Create Lambda function
        self.markdown_converter_function = lambda_.Function(
            self,
            "MarkdownToHtmlConverter",
            function_name="markdown-to-html-converter",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="lambda_function.lambda_handler",
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.seconds(60),
            memory_size=256,
            role=lambda_role,
            environment={
                "OUTPUT_BUCKET_NAME": self.output_bucket.bucket_name,
            },
            description="Converts Markdown files to HTML using markdown2 library",
        )

        # Create S3 event notification to trigger Lambda
        self.input_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3n.LambdaDestination(self.markdown_converter_function),
            s3.NotificationKeyFilter(suffix=".md"),
        )

        # Add tags to all resources
        self._add_tags()

        # Create stack outputs
        self._create_outputs()

    def _get_lambda_code(self) -> str:
        """
        Returns the Lambda function code as a string.
        In production, this should reference an external file or deployment package.
        """
        return '''
import json
import boto3
import urllib.parse
import os
from datetime import datetime

# Initialize S3 client
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    AWS Lambda handler for converting Markdown files to HTML
    Triggered by S3 PUT events on markdown files
    """
    try:
        # Parse S3 event
        for record in event['Records']:
            # Extract bucket and object information
            input_bucket = record['s3']['bucket']['name']
            input_key = urllib.parse.unquote_plus(
                record['s3']['object']['key'], encoding='utf-8'
            )
            
            print(f"Processing file: {input_key} from bucket: {input_bucket}")
            
            # Verify file is a markdown file
            if not input_key.lower().endswith(('.md', '.markdown')):
                print(f"Skipping non-markdown file: {input_key}")
                continue
            
            # Download markdown content from S3
            response = s3.get_object(Bucket=input_bucket, Key=input_key)
            markdown_content = response['Body'].read().decode('utf-8')
            
            # Convert markdown to HTML using markdown2
            html_content = convert_markdown_to_html(markdown_content)
            
            # Generate output filename (replace .md with .html)
            output_key = input_key.rsplit('.', 1)[0] + '.html'
            output_bucket = os.environ['OUTPUT_BUCKET_NAME']
            
            # Upload HTML content to output bucket
            s3.put_object(
                Bucket=output_bucket,
                Key=output_key,
                Body=html_content,
                ContentType='text/html',
                Metadata={
                    'source-file': input_key,
                    'conversion-timestamp': datetime.utcnow().isoformat(),
                    'converter': 'lambda-markdown2'
                }
            )
            
            print(f"Successfully converted {input_key} to {output_key}")
            
    except Exception as e:
        print(f"Error processing file: {str(e)}")
        raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Markdown conversion completed successfully'
        })
    }

def convert_markdown_to_html(markdown_text):
    """
    Convert markdown text to HTML using basic Python string operations
    This is a simplified version for the inline code approach
    """
    # Basic markdown to HTML conversion (simplified)
    html = markdown_text
    
    # Convert headers
    html = html.replace('# ', '<h1>').replace('\\n# ', '</h1>\\n<h1>')
    html = html.replace('## ', '<h2>').replace('\\n## ', '</h2>\\n<h2>')
    html = html.replace('### ', '<h3>').replace('\\n### ', '</h3>\\n<h3>')
    
    # Convert bold and italic
    html = html.replace('**', '<strong>').replace('**', '</strong>')
    html = html.replace('*', '<em>').replace('*', '</em>')
    
    # Convert line breaks
    html = html.replace('\\n\\n', '</p><p>')
    html = html.replace('\\n', '<br>')
    
    # Wrap in basic HTML structure
    full_html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Converted Document</title>
    <style>
        body {{ font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }}
        code {{ background-color: #f4f4f4; padding: 2px 4px; border-radius: 3px; }}
        pre {{ background-color: #f4f4f4; padding: 10px; border-radius: 5px; overflow-x: auto; }}
        table {{ border-collapse: collapse; width: 100%; }}
        th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
        th {{ background-color: #f2f2f2; }}
    </style>
</head>
<body>
<p>{html}</p>
</body>
</html>"""
    
    return full_html
'''

    def _add_tags(self) -> None:
        """Add common tags to all resources in the stack."""
        tags = {
            "Project": "MarkdownHtmlConverter",
            "Environment": "Development",
            "Purpose": "DocumentProcessing",
            "CostCenter": "Engineering",
        }
        
        for key, value in tags.items():
            cdk.Tags.of(self).add(key, value)

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource identifiers."""
        cdk.CfnOutput(
            self,
            "InputBucketName",
            value=self.input_bucket.bucket_name,
            description="Name of the S3 bucket for uploading Markdown files",
            export_name=f"{self.stack_name}-InputBucketName",
        )

        cdk.CfnOutput(
            self,
            "OutputBucketName", 
            value=self.output_bucket.bucket_name,
            description="Name of the S3 bucket containing converted HTML files",
            export_name=f"{self.stack_name}-OutputBucketName",
        )

        cdk.CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.markdown_converter_function.function_name,
            description="Name of the Lambda function that converts Markdown to HTML",
            export_name=f"{self.stack_name}-LambdaFunctionName",
        )

        cdk.CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.markdown_converter_function.function_arn,
            description="ARN of the Lambda function that converts Markdown to HTML", 
            export_name=f"{self.stack_name}-LambdaFunctionArn",
        )


class MarkdownHtmlConverterApp(cdk.App):
    """
    CDK Application for the Markdown to HTML Converter.
    """

    def __init__(self):
        super().__init__()

        # Get environment configuration
        env = cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
        )

        # Create the main stack
        MarkdownHtmlConverterStack(
            self,
            "MarkdownHtmlConverterStack",
            env=env,
            description="Simple Markdown to HTML Converter using Lambda and S3",
        )


def main() -> None:
    """
    Main entry point for the CDK application.
    """
    app = MarkdownHtmlConverterApp()
    app.synth()


if __name__ == "__main__":
    main()