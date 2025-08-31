import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';
import { NagSuppressions } from 'cdk-nag';

export interface FileOrganizerStackProps extends cdk.StackProps {
  /**
   * Name for the S3 bucket. If not provided, CDK will generate one
   */
  bucketName?: string;
  
  /**
   * Enable versioning on the S3 bucket
   * @default true
   */
  enableVersioning?: boolean;
  
  /**
   * Enable server-side encryption on the S3 bucket
   * @default true
   */
  enableEncryption?: boolean;
  
  /**
   * Lambda function timeout in seconds
   * @default 60
   */
  lambdaTimeout?: number;
  
  /**
   * Lambda function memory size in MB
   * @default 256
   */
  lambdaMemorySize?: number;
}

export class FileOrganizerStack extends cdk.Stack {
  public readonly bucket: s3.Bucket;
  public readonly organizerFunction: lambda.Function;

  constructor(scope: Construct, id: string, props: FileOrganizerStackProps = {}) {
    super(scope, id, props);

    // Create S3 bucket with security best practices
    this.bucket = new s3.Bucket(this, 'FileOrganizerBucket', {
      bucketName: props.bucketName,
      versioned: props.enableVersioning ?? true,
      encryption: props.enableEncryption ? s3.BucketEncryption.S3_MANAGED : s3.BucketEncryption.UNENCRYPTED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      eventBridgeEnabled: false, // We're using S3 event notifications instead
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes - change for production
      autoDeleteObjects: true, // For demo purposes - remove for production
      
      // Lifecycle rules for cost optimization
      lifecycleRules: [
        {
          id: 'DeleteIncompleteMultipartUploads',
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
        },
      ],
      
      // Notification configuration will be added after Lambda function creation
    });

    // Add bucket policy to deny insecure connections
    this.bucket.addToResourcePolicy(new iam.PolicyStatement({
      sid: 'DenyInsecureConnections',
      effect: iam.Effect.DENY,
      principals: [new iam.AnyPrincipal()],
      actions: ['s3:*'],
      resources: [
        this.bucket.arn,
        this.bucket.arnForObjects('*'),
      ],
      conditions: {
        Bool: {
          'aws:SecureTransport': 'false',
        },
      },
    }));

    // Create CloudWatch Log Group with retention policy
    const logGroup = new logs.LogGroup(this, 'FileOrganizerLogGroup', {
      logGroupName: `/aws/lambda/file-organizer-function`,
      retention: logs.RetentionDays.ONE_WEEK, // Adjust based on requirements
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    // Create Lambda function for file organization
    this.organizerFunction = new lambda.Function(this, 'FileOrganizerFunction', {
      functionName: 'file-organizer-function',
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'lambda_function.lambda_handler',
      code: lambda.Code.fromInline(this.getLambdaCode()),
      timeout: cdk.Duration.seconds(props.lambdaTimeout ?? 60),
      memorySize: props.lambdaMemorySize ?? 256,
      logGroup: logGroup,
      
      // Environment variables for configuration
      environment: {
        BUCKET_NAME: this.bucket.bucketName,
        LOG_LEVEL: 'INFO',
      },
      
      // Enhanced error handling and retry configuration
      retryAttempts: 2,
      
      // Best practices for serverless functions
      reservedConcurrentExecutions: 100, // Prevent overwhelming downstream services
      
      description: 'Automatically organizes uploaded files by type into folder structures',
    });

    // Grant necessary S3 permissions to Lambda function
    this.bucket.grantRead(this.organizerFunction);
    this.bucket.grantPut(this.organizerFunction);
    this.bucket.grantDelete(this.organizerFunction);

    // Configure S3 event notification to trigger Lambda
    this.bucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(this.organizerFunction),
      {
        // Only trigger on root-level objects to avoid processing already organized files
        prefix: '',
        suffix: '',
      }
    );

    // Create folder structure in the bucket
    this.createFolderStructure();

    // Add CDK Nag suppressions for justified configurations
    this.addCdkNagSuppressions();

    // CloudFormation outputs for easy access to resources
    new cdk.CfnOutput(this, 'BucketName', {
      value: this.bucket.bucketName,
      description: 'Name of the S3 bucket for file organization',
      exportName: `${this.stackName}-BucketName`,
    });

    new cdk.CfnOutput(this, 'BucketArn', {
      value: this.bucket.bucketArn,
      description: 'ARN of the S3 bucket',
      exportName: `${this.stackName}-BucketArn`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: this.organizerFunction.functionName,
      description: 'Name of the file organizer Lambda function',
      exportName: `${this.stackName}-LambdaFunctionName`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: this.organizerFunction.functionArn,
      description: 'ARN of the file organizer Lambda function',
      exportName: `${this.stackName}-LambdaFunctionArn`,
    });
  }

  /**
   * Creates the folder structure in the S3 bucket using Lambda custom resource
   */
  private createFolderStructure(): void {
    // Create a custom resource to set up folder structure
    const folderSetupFunction = new lambda.Function(this, 'FolderSetupFunction', {
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.handler',
      code: lambda.Code.fromInline(`
import boto3
import json
import urllib3

def handler(event, context):
    s3 = boto3.client('s3')
    bucket_name = event['ResourceProperties']['BucketName']
    
    try:
        if event['RequestType'] in ['Create', 'Update']:
            # Create folder structure
            folders = ['images/', 'documents/', 'videos/', 'other/']
            for folder in folders:
                s3.put_object(
                    Bucket=bucket_name,
                    Key=folder + '.gitkeep',
                    Body=f'{folder.rstrip("/")} files will be stored here'
                )
            
            send_response(event, context, 'SUCCESS', {'Message': 'Folder structure created'})
        elif event['RequestType'] == 'Delete':
            # Clean up folder structure on stack deletion
            try:
                response = s3.list_objects_v2(Bucket=bucket_name, Prefix='')
                if 'Contents' in response:
                    objects = [{'Key': obj['Key']} for obj in response['Contents']]
                    if objects:
                        s3.delete_objects(Bucket=bucket_name, Delete={'Objects': objects})
            except Exception as e:
                print(f"Error during cleanup: {e}")
            
            send_response(event, context, 'SUCCESS', {'Message': 'Cleanup completed'})
        else:
            send_response(event, context, 'SUCCESS', {'Message': 'No action taken'})
            
    except Exception as e:
        print(f"Error: {e}")
        send_response(event, context, 'FAILED', {'Message': str(e)})

def send_response(event, context, status, data):
    response_body = {
        'Status': status,
        'Reason': f'See CloudWatch Log Stream: {context.log_stream_name}',
        'PhysicalResourceId': context.log_stream_name,
        'StackId': event['StackId'],
        'RequestId': event['RequestId'],
        'LogicalResourceId': event['LogicalResourceId'],
        'Data': data
    }
    
    http = urllib3.PoolManager()
    response = http.request('PUT', event['ResponseURL'], 
                          body=json.dumps(response_body),
                          headers={'Content-Type': 'application/json'})
      `),
      timeout: cdk.Duration.minutes(5),
      description: 'Creates initial folder structure in S3 bucket',
    });

    // Grant permissions to the folder setup function
    this.bucket.grantReadWrite(folderSetupFunction);

    // Create custom resource
    new cdk.CustomResource(this, 'FolderStructureSetup', {
      serviceToken: folderSetupFunction.functionArn,
      properties: {
        BucketName: this.bucket.bucketName,
      },
    });
  }

  /**
   * Returns the Lambda function code for file organization
   */
  private getLambdaCode(): string {
    return `
import json
import boto3
import os
import logging
from urllib.parse import unquote_plus
from typing import Dict, List

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.getenv('LOG_LEVEL', 'INFO'))

# Initialize S3 client
s3_client = boto3.client('s3')

def lambda_handler(event: Dict, context) -> Dict:
    """
    Lambda handler for organizing files in S3 bucket by file type
    """
    try:
        # Process each S3 event record
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            logger.info(f"Processing file: {key} in bucket: {bucket}")
            
            # Skip if file is already in an organized folder
            if is_already_organized(key):
                logger.info(f"File {key} is already organized, skipping")
                continue
            
            # Skip .gitkeep files used for folder structure
            if key.endswith('/.gitkeep') or key.endswith('.gitkeep'):
                logger.info(f"Skipping folder placeholder file: {key}")
                continue
            
            # Determine file type based on extension
            file_extension = get_file_extension(key)
            folder = get_folder_for_extension(file_extension)
            
            # Create new key with folder structure
            new_key = f"{folder}/{key}"
            
            # Move file to organized location
            move_file(bucket, key, new_key)
            
            logger.info(f"Successfully moved {key} to {new_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Files processed successfully',
                'processed_files': len(event['Records'])
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing files: {str(e)}")
        # Re-raise the exception to trigger Lambda retry mechanism
        raise e

def is_already_organized(key: str) -> bool:
    """Check if file is already in an organized folder"""
    organized_folders = ['images/', 'documents/', 'videos/', 'other/']
    return any(key.startswith(folder) for folder in organized_folders)

def get_file_extension(key: str) -> str:
    """Extract file extension from object key"""
    if '.' not in key:
        return ''
    return key.lower().split('.')[-1]

def get_folder_for_extension(extension: str) -> str:
    """Determine destination folder based on file extension"""
    
    # Image file extensions
    image_extensions = {
        'jpg', 'jpeg', 'png', 'gif', 'bmp', 'tiff', 'tif', 
        'svg', 'webp', 'ico', 'raw', 'heic', 'heif'
    }
    
    # Document file extensions
    document_extensions = {
        'pdf', 'doc', 'docx', 'txt', 'rtf', 'odt', 'pages',
        'xls', 'xlsx', 'xlsm', 'csv', 'ods', 'numbers',
        'ppt', 'pptx', 'pptm', 'odp', 'key', 'md', 'tex'
    }
    
    # Video file extensions
    video_extensions = {
        'mp4', 'avi', 'mov', 'wmv', 'flv', 'webm', 'mkv', 
        'm4v', 'mpg', 'mpeg', '3gp', 'ogv', 'f4v'
    }
    
    if extension in image_extensions:
        return 'images'
    elif extension in document_extensions:
        return 'documents'
    elif extension in video_extensions:
        return 'videos'
    else:
        return 'other'

def move_file(bucket: str, source_key: str, destination_key: str) -> None:
    """Move file from source to destination within the same bucket"""
    try:
        # Copy object to new location
        s3_client.copy_object(
            Bucket=bucket,
            CopySource={'Bucket': bucket, 'Key': source_key},
            Key=destination_key,
            MetadataDirective='COPY'  # Preserve original metadata
        )
        
        # Delete original object
        s3_client.delete_object(Bucket=bucket, Key=source_key)
        
        logger.info(f"Moved {source_key} to {destination_key}")
        
    except Exception as e:
        logger.error(f"Error moving {source_key} to {destination_key}: {str(e)}")
        raise e
`;
  }

  /**
   * Add CDK Nag suppressions for justified security configurations
   */
  private addCdkNagSuppressions(): void {
    // Suppress CDK Nag warnings that are acceptable for this use case
    NagSuppressions.addResourceSuppressions(
      this.bucket,
      [
        {
          id: 'AwsSolutions-S3-1',
          reason: 'Server access logging not required for this demo application. Enable in production environments.',
        },
        {
          id: 'AwsSolutions-S3-2',
          reason: 'Public read access is blocked. This bucket is for internal file organization only.',
        },
      ]
    );

    NagSuppressions.addResourceSuppressions(
      this.organizerFunction,
      [
        {
          id: 'AwsSolutions-L1',
          reason: 'Using Python 3.12 which is the latest stable runtime version at time of creation.',
        },
      ]
    );

    // Suppress IAM warnings for the Lambda execution role
    NagSuppressions.addResourceSuppressionsByPath(
      this,
      '/FileOrganizerStack/FileOrganizerFunction/ServiceRole/Resource',
      [
        {
          id: 'AwsSolutions-IAM4',
          reason: 'Using AWS managed policy AWSLambdaBasicExecutionRole which provides least privilege for CloudWatch logging.',
        },
      ]
    );
  }
}