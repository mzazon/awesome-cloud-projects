#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';

/**
 * Stack that deploys a JSON to CSV converter using Lambda and S3
 * 
 * This stack creates:
 * - Input S3 bucket for JSON files
 * - Output S3 bucket for CSV files
 * - Lambda function for JSON to CSV conversion
 * - IAM role with least privilege permissions
 * - S3 event notification to trigger Lambda
 */
export class JsonCsvConverterStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // Create input S3 bucket for JSON files
    const inputBucket = new s3.Bucket(this, 'InputBucket', {
      bucketName: `json-input-${uniqueSuffix}`,
      versioned: true, // Enable versioning for data protection
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Allow CDK to delete bucket during cleanup
      autoDeleteObjects: true, // Automatically delete objects when stack is destroyed
      lifecycleRules: [{
        id: 'DeleteIncompleteMultipartUploads',
        abortIncompleteMultipartUploadAfter: cdk.Duration.days(1)
      }],
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED, // Enable server-side encryption
    });

    // Create output S3 bucket for CSV files
    const outputBucket = new s3.Bucket(this, 'OutputBucket', {
      bucketName: `csv-output-${uniqueSuffix}`,
      versioned: true, // Enable versioning for data protection
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Allow CDK to delete bucket during cleanup
      autoDeleteObjects: true, // Automatically delete objects when stack is destroyed
      lifecycleRules: [{
        id: 'DeleteIncompleteMultipartUploads',
        abortIncompleteMultipartUploadAfter: cdk.Duration.days(1)
      }],
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED, // Enable server-side encryption
    });

    // Create Lambda execution role with least privilege permissions
    const lambdaRole = new iam.Role(this, 'LambdaRole', {
      roleName: `json-csv-converter-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for JSON to CSV converter Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        S3AccessPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:GetObject'],
              resources: [inputBucket.arnForObjects('*')],
              sid: 'AllowInputBucketRead'
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:PutObject'],
              resources: [outputBucket.arnForObjects('*')],
              sid: 'AllowOutputBucketWrite'
            })
          ]
        })
      }
    });

    // Create Lambda function for JSON to CSV conversion
    const converterFunction = new lambda.Function(this, 'ConverterFunction', {
      functionName: `json-csv-converter-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12, // Use latest Python runtime
      handler: 'lambda_function.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import csv
import boto3
import urllib.parse
import os
from io import StringIO

s3_client = boto3.client('s3')

def lambda_handler(event, context):
    try:
        # Get bucket and object key from S3 event
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(
            event['Records'][0]['s3']['object']['key'], 
            encoding='utf-8'
        )
        
        print(f"Processing file: {key} from bucket: {bucket}")
        
        # Read JSON file from S3
        response = s3_client.get_object(Bucket=bucket, Key=key)
        json_content = response['Body'].read().decode('utf-8')
        data = json.loads(json_content)
        
        # Convert JSON to CSV
        if isinstance(data, list) and len(data) > 0:
            # Handle array of objects
            csv_buffer = StringIO()
            if isinstance(data[0], dict):
                fieldnames = data[0].keys()
                writer = csv.DictWriter(csv_buffer, fieldnames=fieldnames)
                writer.writeheader()
                writer.writerows(data)
            else:
                # Handle array of simple values
                writer = csv.writer(csv_buffer)
                writer.writerow(['value'])  # Add header for simple values
                for item in data:
                    writer.writerow([item])
        elif isinstance(data, dict):
            # Handle single object
            csv_buffer = StringIO()
            writer = csv.DictWriter(csv_buffer, fieldnames=data.keys())
            writer.writeheader()
            writer.writerow(data)
        else:
            raise ValueError("Unsupported JSON structure")
        
        # Generate output file name
        output_key = key.replace('.json', '.csv')
        
        # Upload CSV to output bucket
        s3_client.put_object(
            Bucket=os.environ['OUTPUT_BUCKET'],
            Key=output_key,
            Body=csv_buffer.getvalue(),
            ContentType='text/csv'
        )
        
        print(f"Successfully converted {key} to {output_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Successfully converted {key} to CSV')
        }
        
    except Exception as e:
        print(f"Error processing file {key}: {str(e)}")
        raise e
      `),
      role: lambdaRole,
      timeout: cdk.Duration.seconds(60), // Set appropriate timeout
      memorySize: 256, // Balance cost and performance
      environment: {
        OUTPUT_BUCKET: outputBucket.bucketName,
      },
      description: 'Converts JSON files to CSV format when uploaded to S3',
      retryAttempts: 0, // Disable automatic retries to prevent duplicate processing
    });

    // Configure S3 event notification to trigger Lambda function
    inputBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(converterFunction),
      {
        suffix: '.json', // Only trigger for JSON files
      }
    );

    // Output important information for users
    new cdk.CfnOutput(this, 'InputBucketName', {
      value: inputBucket.bucketName,
      description: 'Name of the S3 bucket for uploading JSON files',
      exportName: `${this.stackName}-InputBucketName`
    });

    new cdk.CfnOutput(this, 'OutputBucketName', {
      value: outputBucket.bucketName,
      description: 'Name of the S3 bucket where CSV files will be stored',
      exportName: `${this.stackName}-OutputBucketName`
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: converterFunction.functionName,
      description: 'Name of the Lambda function that converts JSON to CSV',
      exportName: `${this.stackName}-LambdaFunctionName`
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: converterFunction.functionArn,
      description: 'ARN of the Lambda function that converts JSON to CSV',
      exportName: `${this.stackName}-LambdaFunctionArn`
    });

    // Add tags to all resources for better organization and cost tracking
    cdk.Tags.of(this).add('Project', 'JSON-CSV-Converter');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('CreatedBy', 'AWS CDK');
    cdk.Tags.of(this).add('Purpose', 'Data Transformation');
  }
}

// Create CDK app and instantiate the stack
const app = new cdk.App();

new JsonCsvConverterStack(app, 'JsonCsvConverterStack', {
  description: 'Simple JSON to CSV converter using Lambda and S3 with event-driven processing',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Application: 'JSON-CSV-Converter',
    ManagedBy: 'AWS CDK'
  }
});

// Synthesize the CloudFormation template
app.synth();