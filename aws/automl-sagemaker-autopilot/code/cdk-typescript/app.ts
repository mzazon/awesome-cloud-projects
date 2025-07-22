#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sagemaker from 'aws-cdk-lib/aws-sagemaker';
import * as logs from 'aws-cdk-lib/aws-logs';
import { RemovalPolicy } from 'aws-cdk-lib';

/**
 * CDK Stack for Amazon SageMaker Autopilot AutoML Solution
 * 
 * This stack creates the infrastructure required for automated machine learning
 * using Amazon SageMaker Autopilot. It includes:
 * - S3 bucket for data storage and model artifacts
 * - IAM role with necessary permissions for SageMaker Autopilot
 * - CloudWatch log group for monitoring
 * - Sample dataset upload (optional)
 */
export class AutoMLSageMakerAutopilotStack extends cdk.Stack {
  public readonly s3Bucket: s3.Bucket;
  public readonly sageMakerRole: iam.Role;
  public readonly logGroup: logs.LogGroup;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const randomSuffix = Math.random().toString(36).substring(2, 8);
    const stackName = this.stackName.toLowerCase();

    // Create S3 bucket for SageMaker Autopilot data and artifacts
    this.s3Bucket = new s3.Bucket(this, 'AutopilotS3Bucket', {
      bucketName: `sagemaker-autopilot-${cdk.Aws.ACCOUNT_ID}-${randomSuffix}`,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: true,
      lifecycleRules: [
        {
          id: 'DeleteIncompleteMultipartUploads',
          enabled: true,
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(1),
        },
        {
          id: 'TransitionToIA',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
          ],
        },
      ],
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create IAM role for SageMaker Autopilot
    this.sageMakerRole = new iam.Role(this, 'SageMakerAutopilotRole', {
      roleName: `SageMakerAutopilotRole-${randomSuffix}`,
      assumedBy: new iam.ServicePrincipal('sagemaker.amazonaws.com'),
      description: 'IAM role for SageMaker Autopilot with necessary permissions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSageMakerFullAccess'),
      ],
    });

    // Add inline policy for S3 access
    this.sageMakerRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          's3:GetObject',
          's3:PutObject',
          's3:DeleteObject',
          's3:ListBucket',
          's3:GetBucketLocation',
          's3:ListBucketMultipartUploads',
          's3:ListMultipartUploadParts',
          's3:AbortMultipartUpload',
        ],
        resources: [
          this.s3Bucket.bucketArn,
          `${this.s3Bucket.bucketArn}/*`,
        ],
      })
    );

    // Add CloudWatch Logs permissions
    this.sageMakerRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'logs:CreateLogGroup',
          'logs:CreateLogStream',
          'logs:PutLogEvents',
          'logs:DescribeLogGroups',
          'logs:DescribeLogStreams',
        ],
        resources: [
          `arn:aws:logs:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:log-group:/aws/sagemaker/*`,
        ],
      })
    );

    // Add ECR permissions for container access
    this.sageMakerRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'ecr:GetAuthorizationToken',
          'ecr:BatchCheckLayerAvailability',
          'ecr:GetDownloadUrlForLayer',
          'ecr:BatchGetImage',
        ],
        resources: ['*'],
      })
    );

    // Create CloudWatch Log Group for SageMaker Autopilot
    this.logGroup = new logs.LogGroup(this, 'AutopilotLogGroup', {
      logGroupName: `/aws/sagemaker/autopilot/${stackName}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    // Create sample dataset deployment (optional)
    const sampleDatasetDeployment = new cdk.CustomResource(this, 'SampleDatasetDeployment', {
      serviceToken: this.createSampleDatasetProvider().serviceToken,
      properties: {
        BucketName: this.s3Bucket.bucketName,
        S3Key: 'input/churn_dataset.csv',
        SampleData: this.getSampleDataset(),
      },
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Purpose', 'AutoML-SageMaker-Autopilot');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');

    // Outputs
    new cdk.CfnOutput(this, 'S3BucketName', {
      value: this.s3Bucket.bucketName,
      description: 'Name of the S3 bucket for SageMaker Autopilot data and artifacts',
      exportName: `${stackName}-S3BucketName`,
    });

    new cdk.CfnOutput(this, 'SageMakerRoleArn', {
      value: this.sageMakerRole.roleArn,
      description: 'ARN of the IAM role for SageMaker Autopilot',
      exportName: `${stackName}-SageMakerRoleArn`,
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: this.logGroup.logGroupName,
      description: 'Name of the CloudWatch Log Group for SageMaker Autopilot',
      exportName: `${stackName}-LogGroupName`,
    });

    new cdk.CfnOutput(this, 'SampleAutopilotJobCommand', {
      value: this.getAutopilotJobCommand(),
      description: 'AWS CLI command to create a SageMaker Autopilot job',
    });
  }

  /**
   * Create a Lambda-backed custom resource to deploy sample dataset
   */
  private createSampleDatasetProvider(): cdk.Provider {
    const onEventHandler = new cdk.aws_lambda.Function(this, 'SampleDatasetHandler', {
      runtime: cdk.aws_lambda.Runtime.PYTHON_3_9,
      handler: 'index.handler',
      code: cdk.aws_lambda.Code.fromInline(`
import boto3
import json
import cfnresponse
import csv
import io

def handler(event, context):
    try:
        if event['RequestType'] == 'Create' or event['RequestType'] == 'Update':
            s3_client = boto3.client('s3')
            
            bucket_name = event['ResourceProperties']['BucketName']
            s3_key = event['ResourceProperties']['S3Key']
            sample_data = event['ResourceProperties']['SampleData']
            
            # Upload sample dataset to S3
            s3_client.put_object(
                Bucket=bucket_name,
                Key=s3_key,
                Body=sample_data,
                ContentType='text/csv'
            )
            
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {
                'Message': f'Sample dataset uploaded to s3://{bucket_name}/{s3_key}'
            })
        else:
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
            
    except Exception as e:
        print(f"Error: {str(e)}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {
            'Error': str(e)
        })
      `),
      timeout: cdk.Duration.minutes(5),
    });

    // Grant S3 permissions to the Lambda function
    this.s3Bucket.grantWrite(onEventHandler);

    return new cdk.Provider(this, 'SampleDatasetProvider', {
      onEventHandler,
    });
  }

  /**
   * Get sample dataset content
   */
  private getSampleDataset(): string {
    const sampleData = [
      ['customer_id', 'age', 'tenure', 'monthly_charges', 'total_charges', 'contract_type', 'payment_method', 'churn'],
      ['1', '42', '12', '65.30', '783.60', 'Month-to-month', 'Electronic check', 'Yes'],
      ['2', '35', '36', '89.15', '3209.40', 'Two year', 'Mailed check', 'No'],
      ['3', '28', '6', '45.20', '271.20', 'Month-to-month', 'Electronic check', 'Yes'],
      ['4', '52', '24', '78.90', '1894.80', 'One year', 'Credit card', 'No'],
      ['5', '41', '48', '95.45', '4583.60', 'Two year', 'Bank transfer', 'No'],
      ['6', '29', '3', '29.85', '89.55', 'Month-to-month', 'Electronic check', 'Yes'],
      ['7', '38', '60', '110.75', '6645.00', 'Two year', 'Credit card', 'No'],
      ['8', '33', '18', '73.25', '1318.50', 'One year', 'Bank transfer', 'No'],
      ['9', '45', '9', '55.40', '498.60', 'Month-to-month', 'Electronic check', 'Yes'],
      ['10', '31', '72', '125.30', '9021.60', 'Two year', 'Credit card', 'No'],
      ['11', '27', '4', '35.25', '141.00', 'Month-to-month', 'Electronic check', 'Yes'],
      ['12', '49', '42', '102.65', '4311.30', 'Two year', 'Bank transfer', 'No'],
      ['13', '36', '15', '67.85', '1017.75', 'One year', 'Credit card', 'No'],
      ['14', '43', '8', '52.30', '418.40', 'Month-to-month', 'Electronic check', 'Yes'],
      ['15', '39', '54', '118.75', '6412.50', 'Two year', 'Credit card', 'No'],
      ['16', '32', '5', '41.20', '206.00', 'Month-to-month', 'Electronic check', 'Yes'],
      ['17', '46', '38', '95.15', '3615.70', 'Two year', 'Mailed check', 'No'],
      ['18', '34', '22', '76.45', '1681.90', 'One year', 'Bank transfer', 'No'],
      ['19', '41', '7', '48.75', '341.25', 'Month-to-month', 'Electronic check', 'Yes'],
      ['20', '37', '66', '133.20', '8791.20', 'Two year', 'Credit card', 'No'],
    ];

    return sampleData.map(row => row.join(',')).join('\\n');
  }

  /**
   * Generate AWS CLI command for creating Autopilot job
   */
  private getAutopilotJobCommand(): string {
    return `aws sagemaker create-auto-ml-job-v2 \\
    --auto-ml-job-name "autopilot-job-$(date +%s)" \\
    --auto-ml-job-input-data-config '[{
        "ChannelType": "training",
        "ContentType": "text/csv;header=present",
        "CompressionType": "None",
        "DataSource": {
            "S3DataSource": {
                "S3DataType": "S3Prefix",
                "S3Uri": "s3://${this.s3Bucket.bucketName}/input/"
            }
        }
    }]' \\
    --output-data-config '{
        "S3OutputPath": "s3://${this.s3Bucket.bucketName}/output/"
    }' \\
    --auto-ml-problem-type-config '{
        "TabularJobConfig": {
            "TargetAttributeName": "churn",
            "ProblemType": "BinaryClassification",
            "CompletionCriteria": {
                "MaxCandidates": 10,
                "MaxRuntimePerTrainingJobInSeconds": 3600,
                "MaxAutoMLJobRuntimeInSeconds": 14400
            }
        }
    }' \\
    --role-arn ${this.sageMakerRole.roleArn}`;
  }
}

/**
 * Main CDK application
 */
class AutoMLSageMakerAutopilotApp extends cdk.App {
  constructor() {
    super();

    // Get stack name from context or use default
    const stackName = this.node.tryGetContext('stackName') || 'AutoMLSageMakerAutopilotStack';
    
    // Get environment from context or use default
    const env = {
      account: process.env.CDK_DEFAULT_ACCOUNT,
      region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
    };

    // Create the stack
    const stack = new AutoMLSageMakerAutopilotStack(this, stackName, {
      env,
      description: 'AWS CDK Stack for Amazon SageMaker Autopilot AutoML Solution',
      tags: {
        'Application': 'AutoML-SageMaker-Autopilot',
        'Environment': this.node.tryGetContext('environment') || 'development',
        'Owner': this.node.tryGetContext('owner') || 'cdk-user',
        'Project': 'machine-learning-automation',
      },
    });

    // Add stack-level tags
    cdk.Tags.of(stack).add('StackName', stackName);
    cdk.Tags.of(stack).add('CreatedBy', 'AWS-CDK');
    cdk.Tags.of(stack).add('CreatedOn', new Date().toISOString().split('T')[0]);
  }
}

// Instantiate the app
const app = new AutoMLSageMakerAutopilotApp();

// Add global tags
cdk.Tags.of(app).add('Repository', 'automl-solutions-amazon-sagemaker-autopilot');
cdk.Tags.of(app).add('Framework', 'AWS-CDK-v2');

// Synthesize the application
app.synth();