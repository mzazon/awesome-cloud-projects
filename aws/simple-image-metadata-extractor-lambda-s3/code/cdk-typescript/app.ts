#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * CDK Stack for Simple Image Metadata Extractor
 * 
 * This stack creates:
 * - S3 bucket for image storage with encryption and versioning
 * - Lambda function for image metadata extraction
 * - Lambda layer with PIL/Pillow library
 * - IAM role with least privilege permissions
 * - S3 event trigger for automatic processing
 * - CloudWatch logs for monitoring
 */
export class SimpleImageMetadataExtractorStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // S3 Bucket for image storage with enterprise security features
    const imageBucket = new s3.Bucket(this, 'ImageBucket', {
      bucketName: `image-metadata-bucket-${uniqueSuffix}`,
      // Enable versioning for data protection
      versioned: true,
      // Server-side encryption for data at rest
      encryption: s3.BucketEncryption.S3_MANAGED,
      // Block public access for security
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      // Automatically delete bucket contents on stack deletion (for demo purposes)
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      // Enforce SSL requests only
      enforceSSL: true,
      // Intelligent tiering for cost optimization
      intelligentTieringConfigurations: [
        {
          id: 'EntireBucket',
          status: s3.IntelligentTieringStatus.ENABLED,
        },
      ],
    });

    // Lambda Layer for PIL/Pillow image processing library
    // Note: In production, you would build this layer with actual PIL/Pillow dependencies
    const pillowLayer = new lambda.LayerVersion(this, 'PillowLayer', {
      layerVersionName: `pillow-image-processing-${uniqueSuffix}`,
      // Placeholder code - replace with actual layer build in production
      code: lambda.Code.fromInline(`
# Production Lambda Layer Build Instructions:
# 1. Create layer directory: mkdir -p layer/python
# 2. Install Pillow: pip install Pillow -t layer/python/ --platform manylinux2014_x86_64 --implementation cp --python-version 3.12 --only-binary=:all:
# 3. Create zip: cd layer && zip -r pillow-layer.zip python/
# 4. Replace this inline code with: lambda.Code.fromAsset('./pillow-layer.zip')

print("PIL/Pillow layer placeholder - replace with actual build in production")
      `),
      compatibleRuntimes: [
        lambda.Runtime.PYTHON_3_10,
        lambda.Runtime.PYTHON_3_11,
        lambda.Runtime.PYTHON_3_12,
      ],
      compatibleArchitectures: [
        lambda.Architecture.X86_64,
        lambda.Architecture.ARM_64,
      ],
      description: 'PIL/Pillow library for image processing',
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // IAM Role for Lambda with least privilege permissions
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `lambda-s3-metadata-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for image metadata extractor Lambda function',
      managedPolicies: [
        // Basic Lambda execution permissions (CloudWatch Logs)
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        // Custom policy for S3 read access to specific bucket
        S3ReadPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:GetObject', 's3:GetObjectVersion'],
              resources: [imageBucket.arnForObjects('*')],
            }),
          ],
        }),
      },
    });

    // Lambda Function for image metadata extraction
    const metadataExtractorFunction = new lambda.Function(this, 'MetadataExtractorFunction', {
      functionName: `image-metadata-extractor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      architecture: lambda.Architecture.X86_64, // Compatible with PIL/Pillow layer
      handler: 'lambda_function.lambda_handler',
      role: lambdaRole,
      layers: [pillowLayer],
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      description: 'Extract metadata from uploaded images using PIL/Pillow',
      // Enable Lambda Insights for enhanced monitoring
      insightsVersion: lambda.LambdaInsightsVersion.VERSION_1_0_229_0,
      // Lambda function code
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from PIL import Image
from urllib.parse import unquote_plus
import io

# Initialize S3 client outside handler for reuse
s3_client = boto3.client('s3')

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Main Lambda handler for S3 image upload events
    Extracts metadata from uploaded images
    """
    try:
        # Process each S3 event record
        for record in event['Records']:
            # Get bucket and object key from S3 event
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            logger.info(f"Processing image: {key} from bucket: {bucket}")
            
            # Download image from S3
            response = s3_client.get_object(Bucket=bucket, Key=key)
            image_content = response['Body'].read()
            
            # Extract metadata
            metadata = extract_image_metadata(image_content, key)
            
            # Log extracted metadata
            logger.info(f"Extracted metadata for {key}: {json.dumps(metadata, indent=2)}")
            
        return {
            'statusCode': 200,
            'body': json.dumps('Successfully processed images')
        }
        
    except Exception as e:
        logger.error(f"Error processing image: {str(e)}")
        raise

def extract_image_metadata(image_content, filename):
    """
    Extract comprehensive metadata from image content
    """
    try:
        # Open image with PIL
        with Image.open(io.BytesIO(image_content)) as img:
            metadata = {
                'filename': filename,
                'format': img.format,
                'mode': img.mode,
                'size': img.size,
                'width': img.width,
                'height': img.height,
                'file_size_bytes': len(image_content),
                'file_size_kb': round(len(image_content) / 1024, 2),
                'aspect_ratio': round(img.width / img.height, 2) if img.height > 0 else 0
            }
            
            # Extract EXIF data if available using getexif()
            try:
                exif_dict = img.getexif()
                if exif_dict:
                    metadata['has_exif'] = True
                    metadata['exif_tags_count'] = len(exif_dict)
                else:
                    metadata['has_exif'] = False
            except Exception:
                metadata['has_exif'] = False
                
            return metadata
            
    except Exception as e:
        logger.error(f"Error extracting metadata: {str(e)}")
        return {
            'filename': filename,
            'error': str(e),
            'file_size_bytes': len(image_content)
        }
      `),
      environment: {
        BUCKET_NAME: imageBucket.bucketName,
        AWS_LAMBDA_EXEC_WRAPPER: '/opt/python/lambda_insights_wrapper.py', // Lambda Insights wrapper
      },
      // Enable AWS X-Ray tracing for distributed tracing
      tracing: lambda.Tracing.ACTIVE,
    });

    // CloudWatch Log Group with retention policy
    const logGroup = new logs.LogGroup(this, 'MetadataExtractorLogGroup', {
      logGroupName: `/aws/lambda/${metadataExtractorFunction.functionName}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Configure S3 event notifications to trigger Lambda function
    // Support for multiple image formats: JPG, JPEG, PNG, GIF, WEBP
    const imageFormats = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];
    
    imageFormats.forEach((format) => {
      imageBucket.addEventNotification(
        s3.EventType.OBJECT_CREATED,
        new s3n.LambdaDestination(metadataExtractorFunction),
        { suffix: format }
      );
    });

    // Add tags to all resources for better organization
    cdk.Tags.of(this).add('Project', 'SimpleImageMetadataExtractor');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('Recipe', 'simple-image-metadata-extractor-lambda-s3');
    cdk.Tags.of(this).add('CostCenter', 'Development');

    // Stack Outputs for reference and verification
    new cdk.CfnOutput(this, 'ImageBucketName', {
      value: imageBucket.bucketName,
      description: 'Name of the S3 bucket for image uploads',
      exportName: `${this.stackName}-ImageBucketName`,
    });

    new cdk.CfnOutput(this, 'ImageBucketArn', {
      value: imageBucket.bucketArn,
      description: 'ARN of the S3 bucket for image uploads',
      exportName: `${this.stackName}-ImageBucketArn`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: metadataExtractorFunction.functionName,
      description: 'Name of the Lambda function for metadata extraction',
      exportName: `${this.stackName}-LambdaFunctionName`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: metadataExtractorFunction.functionArn,
      description: 'ARN of the Lambda function for metadata extraction',
      exportName: `${this.stackName}-LambdaFunctionArn`,
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: logGroup.logGroupName,
      description: 'CloudWatch Log Group for Lambda function logs',
      exportName: `${this.stackName}-LogGroupName`,
    });

    new cdk.CfnOutput(this, 'TestUploadCommand', {
      value: `aws s3 cp your-image.jpg s3://${imageBucket.bucketName}/test-image.jpg`,
      description: 'Sample command to upload a test image',
    });

    new cdk.CfnOutput(this, 'ViewLogsCommand', {
      value: `aws logs tail ${logGroup.logGroupName} --follow`,
      description: 'Command to view Lambda function logs in real-time',
    });
  }
}

// CDK App instantiation
const app = new cdk.App();

new SimpleImageMetadataExtractorStack(app, 'SimpleImageMetadataExtractorStack', {
  description: 'Simple Image Metadata Extractor using Lambda and S3 - CDK TypeScript Implementation (Recipe: simple-image-metadata-extractor-lambda-s3)',
  env: {
    // Use default AWS account and region from environment
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  // Enable termination protection for production use
  terminationProtection: false, // Set to true for production environments
});

app.synth();