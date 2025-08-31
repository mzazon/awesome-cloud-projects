#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import { Construct } from 'constructs';

/**
 * Stack for Simple Daily Quote Generator using Lambda and S3
 * This stack creates:
 * - S3 bucket to store quotes data with server-side encryption
 * - Lambda function to serve random quotes from S3
 * - IAM role with minimal permissions for Lambda to read from S3
 * - Function URL for direct HTTP access to the Lambda function
 * - Automated deployment of quotes.json to S3 bucket
 */
export class SimpleDailyQuoteGeneratorStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate a unique suffix for resource names to avoid conflicts
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // Create S3 bucket for storing quote data
    // S3 provides 99.999999999% (11 9's) durability and serves as our data store
    const quotesBucket = new s3.Bucket(this, 'QuotesBucket', {
      bucketName: `daily-quotes-${uniqueSuffix}`,
      // Enable server-side encryption for data security
      encryption: s3.BucketEncryption.S3_MANAGED,
      // Block all public access for security
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      // Enable versioning for data protection
      versioned: true,
      // Configure lifecycle policy to optimize costs
      lifecycleRules: [{
        id: 'delete-incomplete-multipart-uploads',
        abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
      }],
      // Automatically delete bucket contents when stack is destroyed (for demo purposes)
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create IAM role for Lambda function following principle of least privilege
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `lambda-s3-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      // Attach basic Lambda execution policy for CloudWatch Logs
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      // Add inline policy for S3 read access to specific bucket only
      inlinePolicies: {
        S3ReadPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:GetObject'],
              resources: [`${quotesBucket.bucketArn}/*`],
            }),
          ],
        }),
      },
    });

    // Create Lambda function for serving random quotes
    // Uses Python 3.12 runtime for optimal performance and long-term support
    const quoteFunction = new lambda.Function(this, 'QuoteFunction', {
      functionName: 'daily-quote-generator',
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'lambda_function.lambda_handler',
      role: lambdaRole,
      // Inline code for the Lambda function
      code: lambda.Code.fromInline(`
import json
import boto3
import random
import os

def lambda_handler(event, context):
    """
    Lambda function handler that serves random quotes from S3
    
    Args:
        event: Lambda event object (contains request information)
        context: Lambda context object (contains runtime information)
    
    Returns:
        HTTP response with random quote in JSON format
    """
    # Initialize S3 client
    s3 = boto3.client('s3')
    bucket_name = os.environ['BUCKET_NAME']
    
    try:
        # Get quotes from S3
        response = s3.get_object(Bucket=bucket_name, Key='quotes.json')
        quotes_data = json.loads(response['Body'].read().decode('utf-8'))
        
        # Select random quote from the collection
        random_quote = random.choice(quotes_data['quotes'])
        
        # Return successful response with CORS headers
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type',
            },
            'body': json.dumps({
                'quote': random_quote['text'],
                'author': random_quote['author'],
                'timestamp': context.aws_request_id
            })
        }
        
    except Exception as e:
        # Return error response with proper HTTP status code
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
            },
            'body': json.dumps({
                'error': 'Failed to retrieve quote',
                'message': str(e)
            })
        }
`),
      // Set environment variables for the function
      environment: {
        BUCKET_NAME: quotesBucket.bucketName,
      },
      // Configure function settings for optimal performance and cost
      timeout: cdk.Duration.seconds(30),
      memorySize: 128, // Minimal memory for simple operations
      // Enable tracing for monitoring and debugging
      tracing: lambda.Tracing.ACTIVE,
      // Set description for better identification
      description: 'Serves random inspirational quotes from S3 storage',
    });

    // Create Function URL for direct HTTP access
    // This eliminates the need for API Gateway in simple scenarios
    const functionUrl = quoteFunction.addFunctionUrl({
      authType: lambda.FunctionUrlAuthType.NONE,
      cors: {
        allowCredentials: false,
        allowedHeaders: ['*'],
        allowedMethods: [lambda.HttpMethod.GET, lambda.HttpMethod.OPTIONS],
        allowedOrigins: ['*'],
        maxAge: cdk.Duration.hours(24),
      },
    });

    // Deploy quotes data to S3 bucket
    // This automatically uploads the quotes.json file during deployment
    new s3deploy.BucketDeployment(this, 'QuotesDeployment', {
      sources: [
        s3deploy.Source.jsonData('quotes.json', {
          quotes: [
            {
              text: "The only way to do great work is to love what you do.",
              author: "Steve Jobs"
            },
            {
              text: "Innovation distinguishes between a leader and a follower.",
              author: "Steve Jobs"
            },
            {
              text: "Life is what happens to you while you're busy making other plans.",
              author: "John Lennon"
            },
            {
              text: "The future belongs to those who believe in the beauty of their dreams.",
              author: "Eleanor Roosevelt"
            },
            {
              text: "It is during our darkest moments that we must focus to see the light.",
              author: "Aristotle"
            },
            {
              text: "Success is not final, failure is not fatal: it is the courage to continue that counts.",
              author: "Winston Churchill"
            },
            {
              text: "The way to get started is to quit talking and begin doing.",
              author: "Walt Disney"
            },
            {
              text: "Don't let yesterday take up too much of today.",
              author: "Will Rogers"
            },
            {
              text: "You learn more from failure than from success. Don't let it stop you. Failure builds character.",
              author: "Unknown"
            },
            {
              text: "If you are working on something that you really care about, you don't have to be pushed. The vision pulls you.",
              author: "Steve Jobs"
            }
          ]
        })
      ],
      destinationBucket: quotesBucket,
      // Ensure deployment happens after bucket creation
      retainOnDelete: false,
    });

    // Stack Outputs for easy access to created resources
    new cdk.CfnOutput(this, 'BucketName', {
      value: quotesBucket.bucketName,
      description: 'Name of the S3 bucket storing quotes data',
      exportName: `${this.stackName}-BucketName`,
    });

    new cdk.CfnOutput(this, 'FunctionName', {
      value: quoteFunction.functionName,
      description: 'Name of the Lambda function serving quotes',
      exportName: `${this.stackName}-FunctionName`,
    });

    new cdk.CfnOutput(this, 'FunctionUrl', {
      value: functionUrl.url,
      description: 'HTTPS URL for accessing the quote API directly',
      exportName: `${this.stackName}-FunctionUrl`,
    });

    new cdk.CfnOutput(this, 'TestCommand', {
      value: `curl -s ${functionUrl.url}`,
      description: 'Command to test the quote API',
    });
  }
}

// CDK App entry point
const app = new cdk.App();

// Create the stack with proper naming and tagging
new SimpleDailyQuoteGeneratorStack(app, 'SimpleDailyQuoteGeneratorStack', {
  description: 'Simple Daily Quote Generator using AWS Lambda and S3 - CDK TypeScript Implementation',
  env: {
    // Use environment variables for account and region, with fallbacks
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'SimpleDailyQuoteGenerator',
    Environment: 'Demo',
    Framework: 'CDK',
    Language: 'TypeScript',
  },
});

// Add stack-level tags for better resource management
cdk.Tags.of(app).add('CreatedBy', 'AWS-CDK');
cdk.Tags.of(app).add('Purpose', 'Learning-Demo');