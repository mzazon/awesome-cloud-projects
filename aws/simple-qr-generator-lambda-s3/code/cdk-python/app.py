#!/usr/bin/env python3
"""
CDK Python application for Simple QR Code Generator with Lambda and S3.

This application creates:
- S3 bucket for storing generated QR code images
- Lambda function for QR code generation
- API Gateway REST API for HTTP access
- IAM roles and policies for proper permissions

Author: AWS Recipes Team
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_s3 as s3,
    aws_lambda as _lambda,
    aws_apigateway as apigateway,
    aws_iam as iam,
)
from constructs import Construct
import uuid


class QrGeneratorStack(Stack):
    """
    CDK Stack for Simple QR Code Generator with Lambda and S3.
    
    Creates a serverless QR code generator that accepts text input via API Gateway,
    processes it with Lambda to generate QR codes, and stores the images in S3.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate a unique suffix for resource names to avoid conflicts
        unique_suffix = str(uuid.uuid4())[:8]

        # Create S3 bucket for storing QR code images
        qr_bucket = s3.Bucket(
            self, "QrCodeBucket",
            bucket_name=f"qr-generator-bucket-{unique_suffix}",
            versioned=False,
            public_read_access=True,  # Enable public read access for QR codes
            block_public_access=s3.BlockPublicAccess(
                block_public_acls=False,
                block_public_policy=False,
                ignore_public_acls=False,
                restrict_public_buckets=False
            ),
            cors=[s3.CorsRule(
                allowed_methods=[s3.HttpMethods.GET],
                allowed_origins=["*"],
                allowed_headers=["*"],
                max_age=3600
            )],
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldQrCodes",
                    enabled=True,
                    expiration=Duration.days(30),  # Auto-delete QR codes after 30 days
                    abort_incomplete_multipart_upload_after=Duration.days(1)
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,  # Allow CDK to delete bucket on stack destruction
            auto_delete_objects=True  # Automatically delete objects when bucket is destroyed
        )

        # Create IAM role for Lambda function
        lambda_role = iam.Role(
            self, "QrGeneratorLambdaRole",
            role_name=f"qr-generator-role-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ]
        )

        # Grant Lambda permission to write to S3 bucket
        qr_bucket.grant_write(lambda_role)

        # Create Lambda function for QR code generation
        qr_lambda = _lambda.Function(
            self, "QrGeneratorFunction",
            function_name=f"qr-generator-function-{unique_suffix}",
            runtime=_lambda.Runtime.PYTHON_3_12,
            handler="lambda_function.lambda_handler",
            code=_lambda.Code.from_inline("""
import json
import boto3
import qrcode
import io
from datetime import datetime
import uuid
import os

# Initialize S3 client outside handler for connection reuse
s3_client = boto3.client('s3')

def lambda_handler(event, context):
    try:
        # Parse request body
        if 'body' in event:
            body = json.loads(event['body'])
        else:
            body = event
        
        text = body.get('text', '').strip()
        if not text:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Text parameter is required'})
            }
        
        # Limit text length for security and performance
        if len(text) > 1000:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Text too long (max 1000 characters)'})
            }
        
        # Generate QR code
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4,
        )
        qr.add_data(text)
        qr.make(fit=True)
        
        # Create QR code image
        img = qr.make_image(fill_color="black", back_color="white")
        
        # Convert to bytes
        img_buffer = io.BytesIO()
        img.save(img_buffer, format='PNG')
        img_buffer.seek(0)
        
        # Generate unique filename
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        filename = f"qr_{timestamp}_{str(uuid.uuid4())[:8]}.png"
        
        # Get bucket name from environment variable
        bucket_name = os.environ.get('BUCKET_NAME')
        
        # Upload to S3
        s3_client.put_object(
            Bucket=bucket_name,
            Key=filename,
            Body=img_buffer.getvalue(),
            ContentType='image/png',
            CacheControl='max-age=31536000'  # Cache for 1 year
        )
        
        # Generate public URL
        region = boto3.Session().region_name
        url = f"https://{bucket_name}.s3.{region}.amazonaws.com/{filename}"
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'message': 'QR code generated successfully',
                'url': url,
                'filename': filename,
                'text_length': len(text)
            })
        }
        
    except Exception as e:
        # Log error for debugging
        print(f"Error generating QR code: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Internal server error'})
        }
            """),
            role=lambda_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            environment={
                "BUCKET_NAME": qr_bucket.bucket_name
            },
            description="Generates QR codes from text input and stores them in S3"
        )

        # Add Lambda layer for qrcode library (since it's not available in Lambda runtime)
        qr_lambda.add_layers(
            _lambda.LayerVersion.from_layer_version_arn(
                self, "QrCodeLayer",
                # This is a public layer that includes qrcode and PIL libraries
                layer_version_arn=f"arn:aws:lambda:{self.region}:770693421928:layer:Klayers-p312-qrcode:1"
            )
        )

        # Create API Gateway REST API
        api = apigateway.RestApi(
            self, "QrGeneratorApi",
            rest_api_name=f"qr-generator-api-{unique_suffix}",
            description="QR Code Generator API",
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=apigateway.Cors.ALL_ORIGINS,
                allow_methods=apigateway.Cors.ALL_METHODS,
                allow_headers=["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key"]
            ),
            endpoint_types=[apigateway.EndpointType.REGIONAL]
        )

        # Create /generate resource
        generate_resource = api.root.add_resource("generate")

        # Create Lambda integration
        lambda_integration = apigateway.LambdaIntegration(
            qr_lambda,
            proxy=True,
            integration_responses=[
                apigateway.IntegrationResponse(
                    status_code="200",
                    response_headers={
                        "Access-Control-Allow-Origin": "'*'"
                    }
                )
            ]
        )

        # Add POST method to /generate resource
        generate_resource.add_method(
            "POST",
            lambda_integration,
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_headers={
                        "Access-Control-Allow-Origin": True
                    }
                )
            ]
        )

        # Output important values
        CfnOutput(
            self, "ApiUrl",
            value=api.url,
            description="QR Generator API URL"
        )

        CfnOutput(
            self, "ApiEndpoint",
            value=f"{api.url}generate",
            description="QR Generator API Endpoint"
        )

        CfnOutput(
            self, "S3BucketName",
            value=qr_bucket.bucket_name,
            description="S3 Bucket for QR Code Storage"
        )

        CfnOutput(
            self, "LambdaFunctionName",
            value=qr_lambda.function_name,
            description="Lambda Function Name"
        )

        CfnOutput(
            self, "TestCommand",
            value=f'curl -X POST {api.url}generate -H "Content-Type: application/json" -d \'{{"text": "Hello, World!"}}\'',
            description="Test command to generate a QR code"
        )


app = cdk.App()

# Create the stack
QrGeneratorStack(
    app, "QrGeneratorStack",
    description="Simple QR Code Generator with Lambda and S3",
    tags={
        "Project": "QR-Generator",
        "Environment": "Development",
        "Recipe": "simple-qr-generator-lambda-s3"
    }
)

app.synth()