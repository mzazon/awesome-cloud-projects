#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Duration, RemovalPolicy } from 'aws-cdk-lib';

/**
 * Simple QR Code Generator Stack
 * 
 * This stack creates a serverless QR code generator using:
 * - S3 bucket for storing QR code images
 * - Lambda function for generating QR codes
 * - API Gateway for REST API endpoints
 */
export class SimpleQrGeneratorStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // S3 Bucket for storing QR code images
    const qrBucket = new s3.Bucket(this, 'QrCodeBucket', {
      bucketName: `qr-generator-bucket-${uniqueSuffix}`,
      // Enable public read access for QR code images
      publicReadAccess: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ACLS,
      // Configure CORS for web access
      cors: [
        {
          allowedHeaders: ['*'],
          allowedMethods: [s3.HttpMethods.GET, s3.HttpMethods.HEAD],
          allowedOrigins: ['*'],
          exposedHeaders: ['ETag'],
          maxAge: 3000,
        },
      ],
      // Lifecycle policy to manage costs
      lifecycleRules: [
        {
          id: 'DeleteOldQrCodes',
          enabled: true,
          expiration: Duration.days(30), // Auto-delete QR codes after 30 days
        },
      ],
      // Use DESTROY removal policy for demo purposes (be careful in production)
      removalPolicy: RemovalPolicy.DESTROY,
      // Automatically delete objects when stack is destroyed (demo only)
      autoDeleteObjects: true,
    });

    // CloudWatch Log Group for Lambda function
    const logGroup = new logs.LogGroup(this, 'QrGeneratorLogGroup', {
      logGroupName: `/aws/lambda/qr-generator-function-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    // Lambda function for QR code generation
    const qrGeneratorFunction = new lambda.Function(this, 'QrGeneratorFunction', {
      functionName: `qr-generator-function-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'lambda_function.lambda_handler',
      // Lambda function code
      code: lambda.Code.fromInline(`
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
        if not bucket_name:
            raise Exception('BUCKET_NAME environment variable not set')
        
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
      `),
      timeout: Duration.seconds(30),
      memorySize: 256,
      // Environment variables
      environment: {
        BUCKET_NAME: qrBucket.bucketName,
      },
      // Use the pre-created log group
      logGroup: logGroup,
      // Add layers for Python dependencies (qrcode and PIL)
      layers: [
        // Create a layer with qrcode and PIL dependencies
        new lambda.LayerVersion(this, 'QrCodeLayer', {
          layerVersionName: `qr-code-dependencies-${uniqueSuffix}`,
          code: lambda.Code.fromInline(`
# This represents the Python dependencies
# In a real deployment, you would create a proper layer with:
# pip install qrcode[pil] -t python/lib/python3.12/site-packages/
# zip -r qr-layer.zip python/
          `),
          compatibleRuntimes: [lambda.Runtime.PYTHON_3_12],
          description: 'QR code generation dependencies (qrcode, PIL)',
        }),
      ],
    });

    // Grant Lambda permission to write to S3 bucket
    qrBucket.grantWrite(qrGeneratorFunction);

    // Add additional S3 permissions for object ACL (needed for public access)
    qrGeneratorFunction.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['s3:PutObjectAcl'],
        resources: [`${qrBucket.bucketArn}/*`],
      })
    );

    // API Gateway REST API
    const api = new apigateway.RestApi(this, 'QrGeneratorApi', {
      restApiName: `qr-generator-api-${uniqueSuffix}`,
      description: 'Simple QR Code Generator API',
      // Enable CORS for all origins (customize for production)
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key'],
      },
      // CloudWatch role for API Gateway logging
      cloudWatchRole: true,
      // Deploy the API automatically
      deploy: true,
      deployOptions: {
        stageName: 'prod',
        // Enable access logging
        accessLogDestination: new apigateway.LogGroupLogDestination(
          new logs.LogGroup(this, 'ApiAccessLogGroup', {
            logGroupName: `/aws/apigateway/qr-generator-api-${uniqueSuffix}`,
            retention: logs.RetentionDays.ONE_WEEK,
            removalPolicy: RemovalPolicy.DESTROY,
          })
        ),
        accessLogFormat: apigateway.AccessLogFormat.jsonWithStandardFields(),
        // Enable detailed CloudWatch metrics
        metricsEnabled: true,
        dataTraceEnabled: true,
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
      },
    });

    // Create /generate resource
    const generateResource = api.root.addResource('generate');

    // Lambda integration for POST /generate
    const lambdaIntegration = new apigateway.LambdaIntegration(qrGeneratorFunction, {
      requestTemplates: { 'application/json': '{ "statusCode": "200" }' },
      proxy: true, // Use Lambda proxy integration
    });

    // Add POST method to /generate resource
    generateResource.addMethod('POST', lambdaIntegration, {
      // Add method request validation
      requestValidator: new apigateway.RequestValidator(this, 'RequestValidator', {
        restApi: api,
        requestValidatorName: 'Validate body',
        validateRequestBody: true,
      }),
      requestModels: {
        'application/json': new apigateway.Model(this, 'QrRequestModel', {
          restApi: api,
          modelName: 'QrRequest',
          contentType: 'application/json',
          schema: {
            type: apigateway.JsonSchemaType.OBJECT,
            properties: {
              text: {
                type: apigateway.JsonSchemaType.STRING,
                minLength: 1,
                maxLength: 1000,
              },
            },
            required: ['text'],
          },
        }),
      },
    });

    // Output important values
    new cdk.CfnOutput(this, 'BucketName', {
      value: qrBucket.bucketName,
      description: 'S3 bucket name for QR code storage',
      exportName: `${this.stackName}-BucketName`,
    });

    new cdk.CfnOutput(this, 'BucketDomainName', {
      value: qrBucket.bucketDomainName,
      description: 'S3 bucket domain name',
      exportName: `${this.stackName}-BucketDomainName`,
    });

    new cdk.CfnOutput(this, 'FunctionName', {
      value: qrGeneratorFunction.functionName,
      description: 'Lambda function name',
      exportName: `${this.stackName}-FunctionName`,
    });

    new cdk.CfnOutput(this, 'FunctionArn', {
      value: qrGeneratorFunction.functionArn,
      description: 'Lambda function ARN',
      exportName: `${this.stackName}-FunctionArn`,
    });

    new cdk.CfnOutput(this, 'ApiUrl', {
      value: api.url,
      description: 'API Gateway endpoint URL',
      exportName: `${this.stackName}-ApiUrl`,
    });

    new cdk.CfnOutput(this, 'ApiId', {
      value: api.restApiId,
      description: 'API Gateway REST API ID',
      exportName: `${this.stackName}-ApiId`,
    });

    new cdk.CfnOutput(this, 'GenerateEndpoint', {
      value: `${api.url}generate`,
      description: 'QR code generation endpoint',
      exportName: `${this.stackName}-GenerateEndpoint`,
    });

    // Output test commands
    new cdk.CfnOutput(this, 'TestCommand', {
      value: `curl -X POST ${api.url}generate -H "Content-Type: application/json" -d '{"text": "Hello, World!"}'`,
      description: 'Test command for the API',
    });
  }
}

// CDK App
const app = new cdk.App();

// Create the stack
new SimpleQrGeneratorStack(app, 'SimpleQrGeneratorStack', {
  description: 'Simple QR Code Generator with Lambda, S3, and API Gateway',
  
  // Add tags to all resources
  tags: {
    Project: 'SimpleQrGenerator',
    Environment: 'Demo',
    CreatedBy: 'CDK',
    Recipe: 'simple-qr-generator-lambda-s3',
  },

  // Enable termination protection in production
  // terminationProtection: true,
});

// Synthesize the app
app.synth();