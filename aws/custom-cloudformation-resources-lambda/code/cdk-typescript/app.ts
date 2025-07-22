#!/usr/bin/env node

import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cfn from 'aws-cdk-lib/aws-cloudformation';

/**
 * Stack for demonstrating Lambda-backed custom CloudFormation resources
 */
export class CustomResourceStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create S3 bucket for data storage
    const dataBucket = new s3.Bucket(this, 'DataBucket', {
      bucketName: `custom-resource-data-${cdk.Aws.ACCOUNT_ID}-${cdk.Aws.REGION}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: true,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create IAM role for Lambda function
    const lambdaRole = new iam.Role(this, 'CustomResourceLambdaRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        S3AccessPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket',
              ],
              resources: [
                dataBucket.bucketArn,
                dataBucket.arnForObjects('*'),
              ],
            }),
          ],
        }),
      },
    });

    // Create CloudWatch Log Group for Lambda function
    const logGroup = new logs.LogGroup(this, 'CustomResourceLogGroup', {
      logGroupName: `/aws/lambda/custom-resource-handler`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Lambda function code for custom resource handler
    const lambdaCode = `
import json
import boto3
import cfnresponse
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Lambda function to handle custom resource operations
    """
    physical_resource_id = event.get('PhysicalResourceId', 'CustomResourceDemo')
    
    try:
        logger.info(f"Received event: {json.dumps(event, default=str)}")
        
        # Validate required properties
        resource_properties = event.get('ResourceProperties', {})
        required_props = ['BucketName']
        
        for prop in required_props:
            if prop not in resource_properties:
                raise ValueError(f"Missing required property: {prop}")
        
        # Extract event properties
        request_type = event['RequestType']
        
        # Route to appropriate handler
        if request_type == 'Create':
            response_data = handle_create(resource_properties, physical_resource_id)
        elif request_type == 'Update':
            response_data = handle_update(resource_properties, physical_resource_id)
        elif request_type == 'Delete':
            response_data = handle_delete(resource_properties, physical_resource_id)
        else:
            raise ValueError(f"Unknown request type: {request_type}")
        
        # Add standard response data
        response_data['PhysicalResourceId'] = physical_resource_id
        response_data['RequestId'] = event['RequestId']
        response_data['LogicalResourceId'] = event['LogicalResourceId']
        
        logger.info(f"Operation completed successfully: {response_data}")
        cfnresponse.send(event, context, cfnresponse.SUCCESS, response_data, physical_resource_id)
        
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        
        # Send failure response with error details
        error_data = {
            'Error': str(e),
            'RequestId': event.get('RequestId', 'unknown'),
            'LogicalResourceId': event.get('LogicalResourceId', 'unknown')
        }
        cfnresponse.send(event, context, cfnresponse.FAILED, error_data, physical_resource_id)

def handle_create(properties, physical_resource_id):
    """
    Handle resource creation
    """
    bucket_name = properties['BucketName']
    file_name = properties.get('FileName', 'custom-resource-data.json')
    data_content = properties.get('DataContent', {})
    
    # Parse JSON data if string
    if isinstance(data_content, str):
        try:
            data_content = json.loads(data_content)
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON in DataContent: {str(e)}")
    
    # Create comprehensive data object
    data_object = {
        'metadata': {
            'created_at': datetime.utcnow().isoformat(),
            'resource_id': physical_resource_id,
            'operation': 'CREATE',
            'version': '1.0'
        },
        'configuration': data_content,
        'validation': {
            'bucket_accessible': True,
            'data_format': 'valid'
        }
    }
    
    # Upload to S3
    s3.put_object(
        Bucket=bucket_name,
        Key=file_name,
        Body=json.dumps(data_object, indent=2),
        ContentType='application/json',
        Metadata={
            'resource-id': physical_resource_id,
            'operation': 'CREATE'
        }
    )
    
    logger.info(f"Created object {file_name} in bucket {bucket_name}")
    
    return {
        'BucketName': bucket_name,
        'FileName': file_name,
        'DataUrl': f"https://{bucket_name}.s3.amazonaws.com/{file_name}",
        'CreatedAt': data_object['metadata']['created_at'],
        'Status': 'SUCCESS'
    }

def handle_update(properties, physical_resource_id):
    """
    Handle resource updates
    """
    bucket_name = properties['BucketName']
    file_name = properties.get('FileName', 'custom-resource-data.json')
    data_content = properties.get('DataContent', {})
    
    # Parse JSON data if string
    if isinstance(data_content, str):
        try:
            data_content = json.loads(data_content)
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON in DataContent: {str(e)}")
    
    # Get existing data
    existing_data = {}
    try:
        response = s3.get_object(Bucket=bucket_name, Key=file_name)
        existing_data = json.loads(response['Body'].read())
    except s3.exceptions.NoSuchKey:
        logger.warning(f"Object {file_name} not found, creating new one")
    
    # Update data object
    data_object = {
        'metadata': {
            'created_at': existing_data.get('metadata', {}).get('created_at', datetime.utcnow().isoformat()),
            'updated_at': datetime.utcnow().isoformat(),
            'resource_id': physical_resource_id,
            'operation': 'UPDATE',
            'version': '2.0'
        },
        'configuration': data_content,
        'validation': {
            'bucket_accessible': True,
            'data_format': 'valid'
        }
    }
    
    # Upload updated object
    s3.put_object(
        Bucket=bucket_name,
        Key=file_name,
        Body=json.dumps(data_object, indent=2),
        ContentType='application/json',
        Metadata={
            'resource-id': physical_resource_id,
            'operation': 'UPDATE'
        }
    )
    
    logger.info(f"Updated object {file_name} in bucket {bucket_name}")
    
    return {
        'BucketName': bucket_name,
        'FileName': file_name,
        'DataUrl': f"https://{bucket_name}.s3.amazonaws.com/{file_name}",
        'UpdatedAt': data_object['metadata']['updated_at'],
        'Status': 'SUCCESS'
    }

def handle_delete(properties, physical_resource_id):
    """
    Handle resource deletion with cleanup verification
    """
    bucket_name = properties['BucketName']
    file_name = properties.get('FileName', 'custom-resource-data.json')
    
    # Delete object with verification
    try:
        s3.delete_object(Bucket=bucket_name, Key=file_name)
        logger.info(f"Deleted object {file_name} from bucket {bucket_name}")
        
        # Verify deletion
        try:
            s3.head_object(Bucket=bucket_name, Key=file_name)
            logger.warning(f"Object {file_name} still exists after deletion")
        except s3.exceptions.NoSuchKey:
            logger.info(f"Confirmed: Object {file_name} successfully deleted")
            
    except s3.exceptions.NoSuchKey:
        logger.info(f"Object {file_name} does not exist, deletion not needed")
    except Exception as e:
        logger.error(f"Error during deletion: {str(e)}")
        # Don't fail on cleanup errors during deletion
    
    return {
        'BucketName': bucket_name,
        'FileName': file_name,
        'DeletedAt': datetime.utcnow().isoformat(),
        'Status': 'SUCCESS'
    }
`;

    // Create Lambda function for custom resource handler
    const customResourceHandler = new lambda.Function(this, 'CustomResourceHandler', {
      functionName: 'custom-resource-handler',
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(lambdaCode),
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      environment: {
        LOG_LEVEL: 'INFO',
      },
      logGroup: logGroup,
    });

    // Create advanced Lambda function with enhanced error handling
    const advancedLambdaCode = `
import json
import boto3
import cfnresponse
import logging
import traceback
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Advanced Lambda function with comprehensive error handling
    """
    physical_resource_id = event.get('PhysicalResourceId', 'AdvancedCustomResource')
    
    try:
        logger.info(f"Received event: {json.dumps(event, default=str)}")
        
        # Validate required properties
        resource_properties = event.get('ResourceProperties', {})
        required_props = ['BucketName']
        
        for prop in required_props:
            if prop not in resource_properties:
                raise ValueError(f"Missing required property: {prop}")
        
        # Extract event properties
        request_type = event['RequestType']
        
        # Route to appropriate handler
        if request_type == 'Create':
            response_data = handle_create_advanced(resource_properties, physical_resource_id)
        elif request_type == 'Update':
            response_data = handle_update_advanced(resource_properties, physical_resource_id)
        elif request_type == 'Delete':
            response_data = handle_delete_advanced(resource_properties, physical_resource_id)
        else:
            raise ValueError(f"Unknown request type: {request_type}")
        
        # Add standard response data
        response_data['PhysicalResourceId'] = physical_resource_id
        response_data['RequestId'] = event['RequestId']
        response_data['LogicalResourceId'] = event['LogicalResourceId']
        
        logger.info(f"Operation completed successfully: {response_data}")
        cfnresponse.send(event, context, cfnresponse.SUCCESS, response_data, physical_resource_id)
        
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        
        # Send failure response with error details
        error_data = {
            'Error': str(e),
            'RequestId': event.get('RequestId', 'unknown'),
            'LogicalResourceId': event.get('LogicalResourceId', 'unknown')
        }
        cfnresponse.send(event, context, cfnresponse.FAILED, error_data, physical_resource_id)

def handle_create_advanced(properties, physical_resource_id):
    """
    Advanced create handler with validation and error handling
    """
    bucket_name = properties['BucketName']
    file_name = properties.get('FileName', 'advanced-data.json')
    data_content = properties.get('DataContent', {})
    
    # Validate bucket exists
    try:
        s3.head_bucket(Bucket=bucket_name)
    except Exception as e:
        raise ValueError(f"Cannot access bucket {bucket_name}: {str(e)}")
    
    # Parse JSON data if string
    if isinstance(data_content, str):
        try:
            data_content = json.loads(data_content)
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON in DataContent: {str(e)}")
    
    # Create comprehensive data object
    data_object = {
        'metadata': {
            'created_at': datetime.utcnow().isoformat(),
            'resource_id': physical_resource_id,
            'operation': 'CREATE',
            'version': '1.0'
        },
        'configuration': data_content,
        'validation': {
            'bucket_accessible': True,
            'data_format': 'valid'
        }
    }
    
    # Upload to S3 with error handling
    try:
        s3.put_object(
            Bucket=bucket_name,
            Key=file_name,
            Body=json.dumps(data_object, indent=2),
            ContentType='application/json',
            Metadata={
                'resource-id': physical_resource_id,
                'operation': 'CREATE'
            }
        )
    except Exception as e:
        raise RuntimeError(f"Failed to upload to S3: {str(e)}")
    
    return {
        'BucketName': bucket_name,
        'FileName': file_name,
        'DataUrl': f"https://{bucket_name}.s3.amazonaws.com/{file_name}",
        'CreatedAt': data_object['metadata']['created_at'],
        'Status': 'SUCCESS'
    }

def handle_update_advanced(properties, physical_resource_id):
    """
    Advanced update handler
    """
    bucket_name = properties['BucketName']
    file_name = properties.get('FileName', 'advanced-data.json')
    data_content = properties.get('DataContent', {})
    
    # Parse JSON data if string
    if isinstance(data_content, str):
        try:
            data_content = json.loads(data_content)
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON in DataContent: {str(e)}")
    
    # Get existing data
    existing_data = {}
    try:
        response = s3.get_object(Bucket=bucket_name, Key=file_name)
        existing_data = json.loads(response['Body'].read())
    except s3.exceptions.NoSuchKey:
        logger.warning(f"Object {file_name} not found, creating new one")
    
    # Update data object
    data_object = {
        'metadata': {
            'created_at': existing_data.get('metadata', {}).get('created_at', datetime.utcnow().isoformat()),
            'updated_at': datetime.utcnow().isoformat(),
            'resource_id': physical_resource_id,
            'operation': 'UPDATE',
            'version': '2.0'
        },
        'configuration': data_content,
        'validation': {
            'bucket_accessible': True,
            'data_format': 'valid'
        }
    }
    
    # Upload updated object
    s3.put_object(
        Bucket=bucket_name,
        Key=file_name,
        Body=json.dumps(data_object, indent=2),
        ContentType='application/json',
        Metadata={
            'resource-id': physical_resource_id,
            'operation': 'UPDATE'
        }
    )
    
    return {
        'BucketName': bucket_name,
        'FileName': file_name,
        'DataUrl': f"https://{bucket_name}.s3.amazonaws.com/{file_name}",
        'UpdatedAt': data_object['metadata']['updated_at'],
        'Status': 'SUCCESS'
    }

def handle_delete_advanced(properties, physical_resource_id):
    """
    Advanced delete handler with cleanup verification
    """
    bucket_name = properties['BucketName']
    file_name = properties.get('FileName', 'advanced-data.json')
    
    # Delete object with verification
    try:
        s3.delete_object(Bucket=bucket_name, Key=file_name)
        logger.info(f"Deleted object {file_name} from bucket {bucket_name}")
        
        # Verify deletion
        try:
            s3.head_object(Bucket=bucket_name, Key=file_name)
            logger.warning(f"Object {file_name} still exists after deletion")
        except s3.exceptions.NoSuchKey:
            logger.info(f"Confirmed: Object {file_name} successfully deleted")
            
    except s3.exceptions.NoSuchKey:
        logger.info(f"Object {file_name} does not exist, deletion not needed")
    except Exception as e:
        logger.error(f"Error during deletion: {str(e)}")
        # Don't fail on cleanup errors during deletion
    
    return {
        'BucketName': bucket_name,
        'FileName': file_name,
        'DeletedAt': datetime.utcnow().isoformat(),
        'Status': 'SUCCESS'
    }
`;

    // Create advanced Lambda function with enhanced error handling
    const advancedCustomResourceHandler = new lambda.Function(this, 'AdvancedCustomResourceHandler', {
      functionName: 'advanced-custom-resource-handler',
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(advancedLambdaCode),
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      environment: {
        LOG_LEVEL: 'INFO',
      },
    });

    // Create log group for advanced function
    const advancedLogGroup = new logs.LogGroup(this, 'AdvancedCustomResourceLogGroup', {
      logGroupName: `/aws/lambda/${advancedCustomResourceHandler.functionName}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Custom resource that uses the Lambda function
    const customResourceProvider = new cfn.CfnCustomResource(this, 'CustomDataResource', {
      serviceToken: customResourceHandler.functionArn,
    });

    // Set custom resource properties
    customResourceProvider.addPropertyOverride('BucketName', dataBucket.bucketName);
    customResourceProvider.addPropertyOverride('FileName', 'demo-data.json');
    customResourceProvider.addPropertyOverride('DataContent', JSON.stringify({
      environment: 'production',
      version: '1.0',
      features: ['logging', 'monitoring'],
    }));
    customResourceProvider.addPropertyOverride('Version', '1.0');

    // Advanced custom resource with better error handling
    const advancedCustomResource = new cfn.CfnCustomResource(this, 'AdvancedCustomResource', {
      serviceToken: advancedCustomResourceHandler.functionArn,
    });

    // Set advanced custom resource properties
    advancedCustomResource.addPropertyOverride('BucketName', dataBucket.bucketName);
    advancedCustomResource.addPropertyOverride('FileName', 'advanced-data.json');
    advancedCustomResource.addPropertyOverride('DataContent', JSON.stringify({
      environment: 'production',
      version: '2.0',
      features: ['logging', 'monitoring', 'alerting'],
      metadata: {
        created_by: 'CDK',
        stack_name: this.stackName,
      },
    }));
    advancedCustomResource.addPropertyOverride('Version', '2.0');

    // Standard S3 bucket for comparison
    const standardBucket = new s3.Bucket(this, 'StandardBucket', {
      bucketName: `${dataBucket.bucketName}-standard`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Stack outputs
    new cdk.CfnOutput(this, 'DataBucketName', {
      value: dataBucket.bucketName,
      description: 'Name of the S3 bucket for data storage',
      exportName: `${this.stackName}-DataBucket`,
    });

    new cdk.CfnOutput(this, 'StandardBucketName', {
      value: standardBucket.bucketName,
      description: 'Name of the standard S3 bucket',
      exportName: `${this.stackName}-StandardBucket`,
    });

    new cdk.CfnOutput(this, 'CustomResourceHandlerArn', {
      value: customResourceHandler.functionArn,
      description: 'ARN of the custom resource handler Lambda function',
      exportName: `${this.stackName}-CustomResourceHandlerArn`,
    });

    new cdk.CfnOutput(this, 'AdvancedCustomResourceHandlerArn', {
      value: advancedCustomResourceHandler.functionArn,
      description: 'ARN of the advanced custom resource handler Lambda function',
      exportName: `${this.stackName}-AdvancedCustomResourceHandlerArn`,
    });

    new cdk.CfnOutput(this, 'CustomResourceDataUrl', {
      value: customResourceProvider.getAtt('DataUrl').toString(),
      description: 'URL of the data file created by custom resource',
      exportName: `${this.stackName}-DataUrl`,
    });

    new cdk.CfnOutput(this, 'CustomResourceStatus', {
      value: customResourceProvider.getAtt('Status').toString(),
      description: 'Status of the custom resource operation',
      exportName: `${this.stackName}-Status`,
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: logGroup.logGroupName,
      description: 'CloudWatch Log Group for custom resource operations',
      exportName: `${this.stackName}-LogGroup`,
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Recipe', 'CustomCloudFormationResources');
    cdk.Tags.of(this).add('Purpose', 'Demonstration');
    cdk.Tags.of(this).add('Environment', 'Development');
  }
}

/**
 * Production-ready stack with comprehensive features
 */
export class ProductionCustomResourceStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Stack parameters
    const environment = new cdk.CfnParameter(this, 'Environment', {
      type: 'String',
      default: 'production',
      allowedValues: ['development', 'staging', 'production'],
      description: 'Environment name',
    });

    const resourceVersion = new cdk.CfnParameter(this, 'ResourceVersion', {
      type: 'String',
      default: '1.0',
      description: 'Version of the custom resource',
    });

    // Create S3 bucket with production-grade configuration
    const s3Bucket = new s3.Bucket(this, 'S3Bucket', {
      bucketName: `custom-resource-${environment.valueAsString}-${cdk.Aws.ACCOUNT_ID}-${cdk.Aws.REGION}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: true,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create IAM role for Lambda execution
    const customResourceRole = new iam.Role(this, 'CustomResourceRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        CustomResourcePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
              ],
              resources: [s3Bucket.arnForObjects('*')],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:ListBucket'],
              resources: [s3Bucket.bucketArn],
            }),
          ],
        }),
      },
    });

    // Production Lambda function with inline code
    const productionLambdaCode = `
import json
import boto3
import cfnresponse
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    try:
        logger.info(f"Event: {json.dumps(event)}")
        
        request_type = event['RequestType']
        properties = event.get('ResourceProperties', {})
        physical_id = event.get('PhysicalResourceId', 'CustomResourceDemo')
        
        response_data = {}
        
        if request_type == 'Create':
            response_data = {'Message': 'Resource created successfully', 'Timestamp': datetime.utcnow().isoformat()}
        elif request_type == 'Update':
            response_data = {'Message': 'Resource updated successfully', 'Timestamp': datetime.utcnow().isoformat()}
        elif request_type == 'Delete':
            response_data = {'Message': 'Resource deleted successfully', 'Timestamp': datetime.utcnow().isoformat()}
        
        cfnresponse.send(event, context, cfnresponse.SUCCESS, response_data, physical_id)
        
    except Exception as e:
        logger.error(f"Error: {str(e)}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {}, physical_id)
`;

    // Create Lambda function for custom resource
    const customResourceFunction = new lambda.Function(this, 'CustomResourceFunction', {
      functionName: `custom-resource-${environment.valueAsString}-${cdk.Aws.REGION}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(productionLambdaCode),
      role: customResourceRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      environment: {
        ENVIRONMENT: environment.valueAsString,
        LOG_LEVEL: 'INFO',
      },
    });

    // Create CloudWatch Log Group
    const customResourceLogGroup = new logs.LogGroup(this, 'CustomResourceLogGroup', {
      logGroupName: `/aws/lambda/${customResourceFunction.functionName}`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // The actual custom resource
    const customResourceDemo = new cfn.CfnCustomResource(this, 'CustomResourceDemo', {
      serviceToken: customResourceFunction.functionArn,
    });

    // Set properties for the custom resource
    customResourceDemo.addPropertyOverride('Environment', environment.valueAsString);
    customResourceDemo.addPropertyOverride('Version', resourceVersion.valueAsString);
    customResourceDemo.addPropertyOverride('BucketName', s3Bucket.bucketName);

    // Stack outputs
    new cdk.CfnOutput(this, 'CustomResourceArn', {
      value: customResourceFunction.functionArn,
      description: 'ARN of the custom resource Lambda function',
      exportName: `${this.stackName}-CustomResourceArn`,
    });

    new cdk.CfnOutput(this, 'S3BucketName', {
      value: s3Bucket.bucketName,
      description: 'Name of the S3 bucket',
      exportName: `${this.stackName}-S3Bucket`,
    });

    new cdk.CfnOutput(this, 'CustomResourceMessage', {
      value: customResourceDemo.getAtt('Message').toString(),
      description: 'Message from custom resource',
      exportName: `${this.stackName}-Message`,
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Recipe', 'CustomCloudFormationResources');
    cdk.Tags.of(this).add('Purpose', 'Production');
    cdk.Tags.of(this).add('Environment', environment.valueAsString);
  }
}

// Create CDK app and instantiate stacks
const app = new cdk.App();

// Get account and region from environment or use defaults
const account = process.env.CDK_DEFAULT_ACCOUNT || process.env.AWS_ACCOUNT_ID;
const region = process.env.CDK_DEFAULT_REGION || process.env.AWS_REGION || 'us-east-1';

// Create demo stack
new CustomResourceStack(app, 'CustomResourceStack', {
  env: {
    account,
    region,
  },
  description: 'Demonstration of Lambda-backed custom CloudFormation resources',
});

// Create production stack
new ProductionCustomResourceStack(app, 'ProductionCustomResourceStack', {
  env: {
    account,
    region,
  },
  description: 'Production-ready custom CloudFormation resources implementation',
});

// Synthesize the app
app.synth();