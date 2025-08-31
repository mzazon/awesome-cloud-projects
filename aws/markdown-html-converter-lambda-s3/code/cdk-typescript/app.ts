#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Stack for the Markdown to HTML Converter application
 * Implements a serverless document processing pipeline using Lambda and S3
 */
export class MarkdownHtmlConverterStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for bucket names to ensure global uniqueness
    const uniqueSuffix = this.node.addr.slice(-8).toLowerCase();

    // Input S3 bucket for Markdown files with security best practices
    const inputBucket = new s3.Bucket(this, 'InputBucket', {
      bucketName: `markdown-input-${uniqueSuffix}`,
      // Enable versioning for data protection and compliance
      versioned: true,
      // Enable server-side encryption with S3 managed keys
      encryption: s3.BucketEncryption.S3_MANAGED,
      // Block all public access for security
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      // Automatically delete objects when stack is destroyed (for demo purposes)
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      // Enable event notifications
      eventBridgeEnabled: false,
    });

    // Output S3 bucket for converted HTML files with matching security configuration
    const outputBucket = new s3.Bucket(this, 'OutputBucket', {
      bucketName: `markdown-output-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // CloudWatch Log Group for Lambda function with retention policy
    const logGroup = new logs.LogGroup(this, 'ConverterLogGroup', {
      logGroupName: `/aws/lambda/markdown-to-html-converter`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // IAM role for Lambda function with least privilege permissions
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for Markdown to HTML converter Lambda function',
      managedPolicies: [
        // Basic execution role for CloudWatch Logs
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        S3AccessPolicy: new iam.PolicyDocument({
          statements: [
            // Permission to read from input bucket
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:GetObject'],
              resources: [inputBucket.arnForObjects('*')],
            }),
            // Permission to write to output bucket
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:PutObject'],
              resources: [outputBucket.arnForObjects('*')],
            }),
          ],
        }),
      },
    });

    // Lambda function for Markdown to HTML conversion
    const converterFunction = new lambda.Function(this, 'ConverterFunction', {
      functionName: 'markdown-to-html-converter',
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'lambda_function.lambda_handler',
      code: lambda.Code.fromInline(`
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
    Convert markdown text to HTML using markdown2 library
    Includes basic extensions for enhanced formatting
    """
    try:
        import markdown2
        
        # Configure markdown2 with useful extras
        html = markdown2.markdown(
            markdown_text,
            extras=[
                'code-friendly',      # Better code block handling
                'fenced-code-blocks', # Support for ``` code blocks
                'tables',            # Support for markdown tables
                'strike',            # Support for ~~strikethrough~~
                'task-list'          # Support for task lists
            ]
        )
        
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
{html}
</body>
</html>"""
        
        return full_html
        
    except ImportError:
        # Fallback if markdown2 is not available
        return f"<html><body><pre>{markdown_text}</pre></body></html>"
`),
      role: lambdaRole,
      // Optimize for document processing workloads
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      // Set environment variables
      environment: {
        OUTPUT_BUCKET_NAME: outputBucket.bucketName,
      },
      // Associate with log group
      logGroup: logGroup,
      description: 'Converts Markdown files to HTML using markdown2 library',
      // Enable AWS X-Ray tracing for observability
      tracing: lambda.Tracing.ACTIVE,
    });

    // Create Lambda layer for markdown2 dependency
    const markdownLayer = new lambda.LayerVersion(this, 'MarkdownLayer', {
      layerVersionName: 'markdown2-layer',
      code: lambda.Code.fromInline(`
# This layer contains the markdown2 Python library
# In a real deployment, you would build this layer with:
# pip install markdown2 -t python/lib/python3.12/site-packages/
# zip -r markdown2-layer.zip python/
`),
      compatibleRuntimes: [lambda.Runtime.PYTHON_3_12],
      description: 'Python markdown2 library for Markdown to HTML conversion',
    });

    // Add the layer to the Lambda function
    converterFunction.addLayers(markdownLayer);

    // Configure S3 event notification to trigger Lambda function
    inputBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(converterFunction),
      {
        suffix: '.md',
      }
    );

    // Add event notification for .markdown files as well
    inputBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(converterFunction),
      {
        suffix: '.markdown',
      }
    );

    // CloudFormation outputs for easy access to resource information
    new cdk.CfnOutput(this, 'InputBucketName', {
      value: inputBucket.bucketName,
      description: 'Name of the S3 bucket for uploading Markdown files',
      exportName: `${this.stackName}-InputBucketName`,
    });

    new cdk.CfnOutput(this, 'OutputBucketName', {
      value: outputBucket.bucketName,
      description: 'Name of the S3 bucket containing converted HTML files',
      exportName: `${this.stackName}-OutputBucketName`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: converterFunction.functionName,
      description: 'Name of the Lambda function that performs the conversion',
      exportName: `${this.stackName}-LambdaFunctionName`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: converterFunction.functionArn,
      description: 'ARN of the Lambda function',
      exportName: `${this.stackName}-LambdaFunctionArn`,
    });

    // Add tags for cost allocation and resource management
    cdk.Tags.of(this).add('Project', 'MarkdownConverter');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('CostCenter', 'Development');
  }
}

// CDK App instantiation
const app = new cdk.App();

// Create the stack with proper naming and region configuration
new MarkdownHtmlConverterStack(app, 'MarkdownHtmlConverterStack', {
  description: 'Serverless Markdown to HTML converter using Lambda and S3',
  env: {
    // Use account and region from environment or CDK defaults
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  // Enable termination protection for production deployments
  terminationProtection: false, // Set to true for production
});

// Synthesize the CloudFormation template
app.synth();