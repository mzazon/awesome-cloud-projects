#!/usr/bin/env python3
"""
CDK Application for Simple Color Palette Generator
Creates a serverless color palette generator using AWS Lambda and S3.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_lambda as _lambda,
    aws_s3 as s3,
    aws_iam as iam,
)
from constructs import Construct


class ColorPaletteGeneratorStack(Stack):
    """
    CDK Stack for the Color Palette Generator application.
    
    This stack creates:
    - S3 bucket for storing generated color palettes
    - Lambda function for generating color palettes
    - IAM role with appropriate permissions
    - Lambda Function URL for HTTP access
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique resource names using stack name
        stack_name = self.stack_name.lower()
        
        # Create S3 bucket for storing color palettes
        self.palette_bucket = s3.Bucket(
            self,
            "ColorPaletteBucket",
            bucket_name=f"color-palettes-{stack_name}-{self.account}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Create Lambda execution role with S3 permissions
        lambda_role = iam.Role(
            self,
            "PaletteGeneratorRole",
            role_name=f"palette-generator-role-{stack_name}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Add S3 permissions to the Lambda role
        self.palette_bucket.grant_read_write(lambda_role)

        # Create Lambda function for color palette generation
        self.palette_function = _lambda.Function(
            self,
            "PaletteGeneratorFunction",
            function_name=f"palette-generator-{stack_name}",
            runtime=_lambda.Runtime.PYTHON_3_12,
            handler="lambda_function.lambda_handler",
            code=_lambda.Code.from_inline(self._get_lambda_code()),
            role=lambda_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            environment={
                "BUCKET_NAME": self.palette_bucket.bucket_name,
            },
            description="Generates color palettes using color theory algorithms",
        )

        # Create Function URL for HTTP access
        function_url = self.palette_function.add_function_url(
            auth_type=_lambda.FunctionUrlAuthType.NONE,
            cors=_lambda.FunctionUrlCorsOptions(
                allow_credentials=False,
                allow_methods=[_lambda.HttpMethod.GET, _lambda.HttpMethod.POST, _lambda.HttpMethod.OPTIONS],
                allow_origins=["*"],
                allow_headers=["Content-Type"],
            ),
        )

        # Output important information
        CfnOutput(
            self,
            "PaletteBucketName",
            value=self.palette_bucket.bucket_name,
            description="S3 bucket name for storing color palettes",
        )

        CfnOutput(
            self,
            "PaletteFunctionName",
            value=self.palette_function.function_name,
            description="Lambda function name for color palette generation",
        )

        CfnOutput(
            self,
            "PaletteFunctionUrl",
            value=function_url.url,
            description="HTTP endpoint for color palette generation",
        )

        CfnOutput(
            self,
            "TestCommand",
            value=f"curl -s '{function_url.url}?type=complementary' | jq '.'",
            description="Command to test the color palette generator",
        )

    def _get_lambda_code(self) -> str:
        """
        Returns the Lambda function code as a string.
        
        Returns:
            str: Complete Lambda function code for color palette generation
        """
        return '''
import json
import random
import colorsys
import boto3
import os
from datetime import datetime
import uuid

# Initialize S3 client
s3_client = boto3.client('s3')

def lambda_handler(event, context):
    """
    AWS Lambda handler for generating color palettes.
    
    Args:
        event: Lambda event containing query parameters
        context: Lambda context object
        
    Returns:
        dict: HTTP response with generated color palette
    """
    # Get bucket name from environment variable
    bucket_name = os.environ.get('BUCKET_NAME')
    if not bucket_name:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Bucket name not configured'})
        }
    
    try:
        # Generate color palette based on requested type
        query_params = event.get('queryStringParameters') or {}
        palette_type = query_params.get('type', 'complementary')
        palette = generate_color_palette(palette_type)
        
        # Store palette in S3
        palette_id = str(uuid.uuid4())[:8]
        s3_key = f"palettes/{palette_id}.json"
        
        palette_data = {
            'id': palette_id,
            'type': palette_type,
            'colors': palette,
            'created_at': datetime.utcnow().isoformat(),
            'hex_colors': [rgb_to_hex(color) for color in palette]
        }
        
        s3_client.put_object(
            Bucket=bucket_name,
            Key=s3_key,
            Body=json.dumps(palette_data, indent=2),
            ContentType='application/json'
        )
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type'
            },
            'body': json.dumps(palette_data)
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': str(e)})
        }

def generate_color_palette(palette_type):
    """
    Generate color palette based on color theory algorithms.
    
    Args:
        palette_type (str): Type of palette to generate
        
    Returns:
        list: List of RGB color values
    """
    base_hue = random.uniform(0, 1)
    saturation = random.uniform(0.6, 0.9)
    lightness = random.uniform(0.4, 0.8)
    
    colors = []
    
    if palette_type == 'complementary':
        # Base color and its complement
        colors.append(hsv_to_rgb(base_hue, saturation, lightness))
        colors.append(hsv_to_rgb((base_hue + 0.5) % 1, saturation, lightness))
        colors.append(hsv_to_rgb(base_hue, saturation * 0.7, lightness * 1.2))
        colors.append(hsv_to_rgb((base_hue + 0.5) % 1, saturation * 0.7, lightness * 1.2))
        
    elif palette_type == 'analogous':
        # Colors adjacent on color wheel
        for i in range(5):
            hue = (base_hue + (i * 0.08)) % 1
            colors.append(hsv_to_rgb(hue, saturation, lightness))
            
    elif palette_type == 'triadic':
        # Three colors evenly spaced on color wheel
        for i in range(3):
            hue = (base_hue + (i * 0.333)) % 1
            colors.append(hsv_to_rgb(hue, saturation, lightness))
        # Add two supporting colors
        colors.append(hsv_to_rgb(base_hue, saturation * 0.5, min(lightness * 1.3, 1.0)))
        colors.append(hsv_to_rgb(base_hue, saturation * 0.3, lightness * 0.9))
        
    else:  # Random palette
        for i in range(5):
            hue = random.uniform(0, 1)
            sat = random.uniform(0.5, 0.9)
            light = random.uniform(0.3, 0.8)
            colors.append(hsv_to_rgb(hue, sat, light))
    
    return colors

def hsv_to_rgb(h, s, v):
    """
    Convert HSV color to RGB.
    
    Args:
        h (float): Hue value (0-1)
        s (float): Saturation value (0-1)
        v (float): Value/brightness (0-1)
        
    Returns:
        list: RGB values as integers (0-255)
    """
    r, g, b = colorsys.hsv_to_rgb(h, s, v)
    return [int(r * 255), int(g * 255), int(b * 255)]

def rgb_to_hex(rgb):
    """
    Convert RGB to hex color code.
    
    Args:
        rgb (list): RGB values as integers
        
    Returns:
        str: Hex color code
    """
    return f"#{rgb[0]:02x}{rgb[1]:02x}{rgb[2]:02x}"
'''


class ColorPaletteGeneratorApp(cdk.App):
    """CDK Application for the Color Palette Generator."""

    def __init__(self) -> None:
        super().__init__()

        # Environment configuration
        env = cdk.Environment(
            account=os.getenv('CDK_DEFAULT_ACCOUNT', os.getenv('AWS_ACCOUNT_ID')),
            region=os.getenv('CDK_DEFAULT_REGION', os.getenv('AWS_REGION', 'us-east-1'))
        )

        # Create the main stack
        ColorPaletteGeneratorStack(
            self,
            "ColorPaletteGeneratorStack",
            env=env,
            description="Simple Color Palette Generator with Lambda and S3",
            tags={
                "Project": "ColorPaletteGenerator",
                "Environment": "Development",
                "ManagedBy": "CDK",
            }
        )


# Create and run the CDK application
if __name__ == "__main__":
    app = ColorPaletteGeneratorApp()
    app.synth()