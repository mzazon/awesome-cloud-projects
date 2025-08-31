#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import { RemovalPolicy, Duration, CfnOutput } from 'aws-cdk-lib';

/**
 * Stack for Simple Color Palette Generator using Lambda and S3
 * 
 * This stack creates:
 * - S3 bucket for storing color palette JSON files
 * - Lambda function that generates color palettes using color theory algorithms
 * - IAM role with least privilege access for Lambda to S3
 * - Lambda Function URL for HTTP access without API Gateway complexity
 */
export class SimpleColorPaletteGeneratorStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = this.node.addr.substring(0, 6).toLowerCase();

    // Create S3 bucket for storing color palettes
    const palettesBucket = new s3.Bucket(this, 'ColorPalettesBucket', {
      bucketName: `color-palettes-${uniqueSuffix}`,
      // Enable versioning for palette history tracking
      versioned: true,
      // Server-side encryption for data security
      encryption: s3.BucketEncryption.S3_MANAGED,
      // Public read access blocked for security
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      // Lifecycle configuration to optimize costs
      lifecycleRules: [
        {
          id: 'delete-old-versions',
          enabled: true,
          noncurrentVersionExpiration: Duration.days(30),
        },
      ],
      // For development environments, allow easy cleanup
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Lambda function code for color palette generation
    const lambdaCode = `import json
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
    Main Lambda handler for color palette generation
    
    Supports different palette types via query parameter:
    - complementary: Base color and its complement
    - analogous: Colors adjacent on color wheel  
    - triadic: Three colors evenly spaced on color wheel
    - random: Random color combinations
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
        
        # Store palette in S3 with unique identifier
        palette_id = str(uuid.uuid4())[:8]
        s3_key = f"palettes/{palette_id}.json"
        
        palette_data = {
            'id': palette_id,
            'type': palette_type,
            'colors': palette,
            'created_at': datetime.utcnow().isoformat(),
            'hex_colors': [rgb_to_hex(color) for color in palette]
        }
        
        # Store palette data in S3 with proper content type
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
    Generate color palette based on color theory algorithms
    
    Args:
        palette_type: Type of palette to generate
        
    Returns:
        List of RGB color values
    """
    base_hue = random.uniform(0, 1)
    saturation = random.uniform(0.6, 0.9)
    lightness = random.uniform(0.4, 0.8)
    
    colors = []
    
    if palette_type == 'complementary':
        # Base color and its complement (180 degrees apart)
        colors.append(hsv_to_rgb(base_hue, saturation, lightness))
        colors.append(hsv_to_rgb((base_hue + 0.5) % 1, saturation, lightness))
        colors.append(hsv_to_rgb(base_hue, saturation * 0.7, lightness * 1.2))
        colors.append(hsv_to_rgb((base_hue + 0.5) % 1, saturation * 0.7, lightness * 1.2))
        
    elif palette_type == 'analogous':
        # Colors adjacent on color wheel (within 90 degrees)
        for i in range(5):
            hue = (base_hue + (i * 0.08)) % 1
            colors.append(hsv_to_rgb(hue, saturation, lightness))
            
    elif palette_type == 'triadic':
        # Three colors evenly spaced on color wheel (120 degrees apart)
        for i in range(3):
            hue = (base_hue + (i * 0.333)) % 1
            colors.append(hsv_to_rgb(hue, saturation, lightness))
        # Add supporting colors with varied saturation and lightness
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
    """Convert HSV color values to RGB integers"""
    r, g, b = colorsys.hsv_to_rgb(h, s, v)
    return [int(r * 255), int(g * 255), int(b * 255)]

def rgb_to_hex(rgb):
    """Convert RGB values to hex color code"""
    return f"#{rgb[0]:02x}{rgb[1]:02x}{rgb[2]:02x}"`;

    // Create Lambda function for color palette generation
    const paletteGeneratorFunction = new lambda.Function(this, 'PaletteGeneratorFunction', {
      functionName: `palette-generator-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(lambdaCode),
      timeout: Duration.seconds(30),
      memorySize: 256,
      environment: {
        BUCKET_NAME: palettesBucket.bucketName,
      },
      description: 'Generates color palettes using color theory algorithms and stores them in S3',
    });

    // Grant Lambda function permissions to read/write S3 bucket
    palettesBucket.grantReadWrite(paletteGeneratorFunction);

    // Create Function URL for direct HTTP access (simpler than API Gateway)
    const functionUrl = paletteGeneratorFunction.addFunctionUrl({
      authType: lambda.FunctionUrlAuthType.NONE,
      cors: {
        allowCredentials: false,
        allowedMethods: [lambda.HttpMethod.GET, lambda.HttpMethod.POST, lambda.HttpMethod.OPTIONS],
        allowedOrigins: ['*'],
        allowedHeaders: ['Content-Type'],
      },
    });

    // Add tags to all resources for better organization and cost tracking
    cdk.Tags.of(this).add('Application', 'ColorPaletteGenerator');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('CostCenter', 'Engineering');

    // CloudFormation outputs for easy access to important values
    new CfnOutput(this, 'FunctionUrl', {
      value: functionUrl.url,
      description: 'HTTP endpoint for color palette generation',
      exportName: `${this.stackName}-FunctionUrl`,
    });

    new CfnOutput(this, 'BucketName', {
      value: palettesBucket.bucketName,
      description: 'S3 bucket name for stored color palettes',
      exportName: `${this.stackName}-BucketName`,
    });

    new CfnOutput(this, 'LambdaFunctionName', {
      value: paletteGeneratorFunction.functionName,
      description: 'Lambda function name for color palette generation',
      exportName: `${this.stackName}-LambdaFunctionName`,
    });

    new CfnOutput(this, 'ExampleUsage', {
      value: `curl "${functionUrl.url}?type=complementary"`,
      description: 'Example command to test the color palette generator',
    });
  }
}

// CDK Application entry point
const app = new cdk.App();

// Get deployment region from CDK context or environment
const region = app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION || 'us-east-1';
const account = process.env.CDK_DEFAULT_ACCOUNT;

// Create stack with explicit environment configuration
new SimpleColorPaletteGeneratorStack(app, 'SimpleColorPaletteGeneratorStack', {
  env: {
    account: account,
    region: region,
  },
  description: 'Simple Color Palette Generator using AWS Lambda and S3 - Beginner-friendly serverless application',
  tags: {
    Project: 'AWSRecipes',
    Recipe: 'SimpleColorPaletteGenerator',
    Difficulty: 'Beginner',
    Services: 'Lambda,S3',
  },
});

// Add stack-level metadata for better documentation
cdk.Aspects.of(app).add(new class implements cdk.IAspect {
  visit(node: Construct): void {
    if (node instanceof cdk.Stack) {
      node.templateOptions.description = 'AWS CDK Stack for Simple Color Palette Generator - Creates Lambda function and S3 bucket for serverless color palette generation';
    }
  }
});