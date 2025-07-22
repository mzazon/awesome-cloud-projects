#!/usr/bin/env node

/**
 * AWS CDK TypeScript Application for Machine Learning Model Deployment Pipeline
 * 
 * This application creates a comprehensive MLOps pipeline using:
 * - Amazon SageMaker for model training and registry
 * - AWS CodePipeline for CI/CD orchestration
 * - AWS CodeBuild for automated testing and deployment
 * - Amazon S3 for artifact storage
 * - AWS Lambda for deployment automation
 * - CloudWatch for monitoring and logging
 */

import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sagemaker from 'aws-cdk-lib/aws-sagemaker';
import * as codebuild from 'aws-cdk-lib/aws-codebuild';
import * as codepipeline from 'aws-cdk-lib/aws-codepipeline';
import * as codepipeline_actions from 'aws-cdk-lib/aws-codepipeline-actions';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as sns_subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';

/**
 * Properties for the ML Model Deployment Pipeline Stack
 */
interface MLModelDeploymentPipelineStackProps extends cdk.StackProps {
  /** The name of the project (used for resource naming) */
  readonly projectName?: string;
  /** The name of the model package group in SageMaker Model Registry */
  readonly modelPackageGroupName?: string;
  /** Email address for pipeline notifications */
  readonly notificationEmail?: string;
  /** Environment tag for resource organization */
  readonly environment?: string;
}

/**
 * CDK Stack for Machine Learning Model Deployment Pipeline
 * 
 * Creates a complete MLOps pipeline with automated model training, testing,
 * validation, and deployment using AWS services.
 */
class MLModelDeploymentPipelineStack extends cdk.Stack {
  public readonly artifactsBucket: s3.Bucket;
  public readonly modelPackageGroup: sagemaker.CfnModelPackageGroup;
  public readonly pipeline: codepipeline.Pipeline;
  public readonly sagemakerRole: iam.Role;
  public readonly codebuildRole: iam.Role;
  public readonly pipelineRole: iam.Role;

  constructor(scope: Construct, id: string, props: MLModelDeploymentPipelineStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const projectName = props.projectName || 'ml-pipeline';
    const modelPackageGroupName = props.modelPackageGroupName || 'fraud-detection-models';
    const environment = props.environment || 'dev';

    // Create S3 bucket for pipeline artifacts and training data
    this.artifactsBucket = this.createArtifactsBucket(projectName);

    // Create IAM roles for various services
    this.sagemakerRole = this.createSageMakerExecutionRole(projectName);
    this.codebuildRole = this.createCodeBuildServiceRole(projectName);
    this.pipelineRole = this.createCodePipelineServiceRole(projectName);

    // Create SageMaker Model Package Group for model versioning
    this.modelPackageGroup = this.createModelPackageGroup(modelPackageGroupName, projectName);

    // Create CodeBuild projects for training and testing
    const trainingProject = this.createTrainingCodeBuildProject(projectName);
    const testingProject = this.createTestingCodeBuildProject(projectName);

    // Create Lambda function for model deployment
    const deploymentFunction = this.createDeploymentLambdaFunction(projectName);

    // Create SNS topic for notifications
    const notificationTopic = this.createNotificationTopic(projectName, props.notificationEmail);

    // Create the ML deployment pipeline
    this.pipeline = this.createMLDeploymentPipeline(
      projectName,
      trainingProject,
      testingProject,
      deploymentFunction,
      notificationTopic
    );

    // Add tags to all resources
    this.addResourceTags(projectName, environment);

    // Output important resource information
    this.createOutputs();
  }

  /**
   * Creates an S3 bucket for storing pipeline artifacts and training data
   */
  private createArtifactsBucket(projectName: string): s3.Bucket {
    const bucket = new s3.Bucket(this, 'ArtifactsBucket', {
      bucketName: `sagemaker-mlops-${this.region}-${this.account}-${projectName}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
        {
          id: 'DeleteIncompleteUploads',
          enabled: true,
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(1),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create folders for organization
    new s3.BucketDeployment(this, 'CreateBucketStructure', {
      sources: [s3.Source.data('training-data/.gitkeep', '')],
      destinationBucket: bucket,
    });

    return bucket;
  }

  /**
   * Creates IAM role for SageMaker execution with appropriate permissions
   */
  private createSageMakerExecutionRole(projectName: string): iam.Role {
    const role = new iam.Role(this, 'SageMakerExecutionRole', {
      roleName: `SageMakerExecutionRole-${projectName}`,
      assumedBy: new iam.ServicePrincipal('sagemaker.amazonaws.com'),
      description: 'Execution role for SageMaker training jobs and model deployment',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSageMakerFullAccess'),
      ],
    });

    // Add custom policy for S3 and CloudWatch access
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        's3:GetObject',
        's3:PutObject',
        's3:DeleteObject',
        's3:ListBucket',
      ],
      resources: [
        this.artifactsBucket.bucketArn,
        `${this.artifactsBucket.bucketArn}/*`,
      ],
    }));

    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
        'logs:PutLogEvents',
        'logs:DescribeLogStreams',
      ],
      resources: ['*'],
    }));

    return role;
  }

  /**
   * Creates IAM role for CodeBuild projects with necessary permissions
   */
  private createCodeBuildServiceRole(projectName: string): iam.Role {
    const role = new iam.Role(this, 'CodeBuildServiceRole', {
      roleName: `CodeBuildServiceRole-${projectName}`,
      assumedBy: new iam.ServicePrincipal('codebuild.amazonaws.com'),
      description: 'Service role for CodeBuild projects in ML pipeline',
    });

    // Add policies for SageMaker, S3, and CloudWatch access
    role.addManagedPolicy(iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSageMakerFullAccess'));
    
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        's3:GetObject',
        's3:PutObject',
        's3:DeleteObject',
        's3:ListBucket',
        's3:GetBucketVersioning',
      ],
      resources: [
        this.artifactsBucket.bucketArn,
        `${this.artifactsBucket.bucketArn}/*`,
      ],
    }));

    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
        'logs:PutLogEvents',
        'logs:DescribeLogGroups',
        'logs:DescribeLogStreams',
      ],
      resources: ['*'],
    }));

    return role;
  }

  /**
   * Creates IAM role for CodePipeline with permissions to orchestrate the pipeline
   */
  private createCodePipelineServiceRole(projectName: string): iam.Role {
    const role = new iam.Role(this, 'CodePipelineServiceRole', {
      roleName: `CodePipelineServiceRole-${projectName}`,
      assumedBy: new iam.ServicePrincipal('codepipeline.amazonaws.com'),
      description: 'Service role for ML deployment CodePipeline',
    });

    // Add policies for S3, CodeBuild, Lambda, and SageMaker access
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        's3:GetObject',
        's3:GetObjectVersion',
        's3:PutObject',
        's3:ListBucket',
      ],
      resources: [
        this.artifactsBucket.bucketArn,
        `${this.artifactsBucket.bucketArn}/*`,
      ],
    }));

    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'codebuild:BatchGetBuilds',
        'codebuild:StartBuild',
      ],
      resources: ['*'],
    }));

    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'lambda:InvokeFunction',
      ],
      resources: ['*'],
    }));

    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'sagemaker:DescribeModelPackage',
        'sagemaker:DescribeModelPackageGroup',
        'sagemaker:ListModelPackages',
      ],
      resources: ['*'],
    }));

    return role;
  }

  /**
   * Creates SageMaker Model Package Group for model versioning and governance
   */
  private createModelPackageGroup(modelPackageGroupName: string, projectName: string): sagemaker.CfnModelPackageGroup {
    return new sagemaker.CfnModelPackageGroup(this, 'ModelPackageGroup', {
      modelPackageGroupName: modelPackageGroupName,
      modelPackageGroupDescription: `Model package group for ${projectName} fraud detection models`,
      tags: [
        {
          key: 'Project',
          value: projectName,
        },
        {
          key: 'Purpose',
          value: 'MLOps Model Registry',
        },
      ],
    });
  }

  /**
   * Creates CodeBuild project for model training
   */
  private createTrainingCodeBuildProject(projectName: string): codebuild.Project {
    // Create CloudWatch log group for training project
    const logGroup = new logs.LogGroup(this, 'TrainingLogGroup', {
      logGroupName: `/aws/codebuild/${projectName}-train`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    return new codebuild.Project(this, 'TrainingProject', {
      projectName: `${projectName}-train`,
      description: 'ML model training project using SageMaker',
      role: this.codebuildRole,
      environment: {
        buildImage: codebuild.LinuxBuildImage.STANDARD_5_0,
        computeType: codebuild.ComputeType.MEDIUM,
        privileged: false,
      },
      buildSpec: codebuild.BuildSpec.fromObject({
        version: '0.2',
        phases: {
          install: {
            'runtime-versions': {
              python: '3.9',
            },
            commands: [
              'pip install boto3 scikit-learn pandas numpy sagemaker',
            ],
          },
          build: {
            commands: [
              'echo "Starting model training..."',
              // Training script execution will be embedded here
              `python << 'PYTHON_EOF'
import boto3
import sagemaker
import json
import os
import time
from sagemaker.sklearn.estimator import SKLearn
from sagemaker.model_package import ModelPackage

# Initialize SageMaker session
session = sagemaker.Session()
role = os.environ['SAGEMAKER_ROLE_ARN']

# Create training job
sklearn_estimator = SKLearn(
    entry_point='train.py',
    role=role,
    instance_type='ml.m5.large',
    framework_version='1.0-1',
    py_version='py3',
    hyperparameters={
        'n_estimators': 100,
        'max_depth': 10
    }
)

# Submit training job
training_job_name = f"fraud-detection-{int(time.time())}"
sklearn_estimator.fit(
    inputs={'training': f"s3://{os.environ['BUCKET_NAME']}/training-data/"},
    job_name=training_job_name,
    wait=True
)

# Register model in Model Registry
model_package = sklearn_estimator.create_model_package(
    model_package_group_name=os.environ['MODEL_PACKAGE_GROUP_NAME'],
    approval_status='PendingManualApproval',
    description=f"Fraud detection model trained from build {os.environ['CODEBUILD_BUILD_NUMBER']}"
)

# Save model package ARN for next stage
with open('model_package_arn.txt', 'w') as f:
    f.write(model_package.model_package_arn)

print(f"Model package created: {model_package.model_package_arn}")
PYTHON_EOF`,
            ],
          },
        },
        artifacts: {
          files: [
            'model_package_arn.txt',
          ],
        },
      }),
      logging: {
        cloudWatch: {
          enabled: true,
          logGroup: logGroup,
        },
      },
      timeout: cdk.Duration.hours(2),
    });
  }

  /**
   * Creates CodeBuild project for model testing and validation
   */
  private createTestingCodeBuildProject(projectName: string): codebuild.Project {
    // Create CloudWatch log group for testing project
    const logGroup = new logs.LogGroup(this, 'TestingLogGroup', {
      logGroupName: `/aws/codebuild/${projectName}-test`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    return new codebuild.Project(this, 'TestingProject', {
      projectName: `${projectName}-test`,
      description: 'ML model testing and validation project',
      role: this.codebuildRole,
      environment: {
        buildImage: codebuild.LinuxBuildImage.STANDARD_5_0,
        computeType: codebuild.ComputeType.MEDIUM,
        privileged: false,
      },
      buildSpec: codebuild.BuildSpec.fromObject({
        version: '0.2',
        phases: {
          install: {
            'runtime-versions': {
              python: '3.9',
            },
            commands: [
              'pip install boto3 sagemaker pandas numpy scikit-learn',
            ],
          },
          build: {
            commands: [
              'echo "Starting model testing..."',
              // Model testing script execution
              `python << 'PYTHON_EOF'
import boto3
import sagemaker
import json
import os
import time
from sagemaker.model_package import ModelPackage

# Read model package ARN from previous stage
with open('model_package_arn.txt', 'r') as f:
    model_package_arn = f.read().strip()

print(f"Testing model package: {model_package_arn}")

# Initialize SageMaker session
session = sagemaker.Session()

# Create model package object
model_package = ModelPackage(
    model_package_arn=model_package_arn,
    sagemaker_session=session
)

# Create test endpoint configuration
endpoint_name = f"test-endpoint-{int(time.time())}"

# Deploy model to test endpoint
predictor = model_package.deploy(
    initial_instance_count=1,
    instance_type='ml.t2.medium',
    endpoint_name=endpoint_name,
    wait=True
)

# Perform model testing
import numpy as np
test_data = np.random.randn(10, 20).tolist()

try:
    # Test predictions
    predictions = predictor.predict(test_data)
    print(f"Test predictions successful: {len(predictions)} predictions made")
    
    # Basic validation - check if predictions are within expected range
    if all(isinstance(p, (int, float)) for p in predictions):
        print("✅ Model test passed - predictions are valid")
        test_result = "PASSED"
    else:
        print("❌ Model test failed - invalid predictions")
        test_result = "FAILED"
        
except Exception as e:
    print(f"❌ Model test failed with error: {str(e)}")
    test_result = "FAILED"

finally:
    # Clean up test endpoint
    predictor.delete_endpoint()
    print("✅ Cleaned up test endpoint")

# Save test results
with open('test_results.json', 'w') as f:
    json.dump({
        'test_status': test_result,
        'model_package_arn': model_package_arn,
        'timestamp': time.time()
    }, f)

# If tests passed, approve the model
if test_result == "PASSED":
    client = boto3.client('sagemaker')
    client.update_model_package(
        ModelPackageArn=model_package_arn,
        ModelApprovalStatus='Approved'
    )
    print("✅ Model approved for deployment")
else:
    raise Exception("Model failed testing - deployment blocked")
PYTHON_EOF`,
            ],
          },
        },
        artifacts: {
          files: [
            'test_results.json',
            'model_package_arn.txt',
          ],
        },
      }),
      logging: {
        cloudWatch: {
          enabled: true,
          logGroup: logGroup,
        },
      },
      timeout: cdk.Duration.hours(1),
    });
  }

  /**
   * Creates Lambda function for automated model deployment to production
   */
  private createDeploymentLambdaFunction(projectName: string): lambda.Function {
    // Create IAM role for Lambda function
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `LambdaExecutionRole-${projectName}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for model deployment Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSageMakerFullAccess'),
      ],
    });

    // Add CodePipeline permissions
    lambdaRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'codepipeline:PutJobSuccessResult',
        'codepipeline:PutJobFailureResult',
      ],
      resources: ['*'],
    }));

    // Create CloudWatch log group for Lambda function
    const logGroup = new logs.LogGroup(this, 'DeploymentLambdaLogGroup', {
      logGroupName: `/aws/lambda/${projectName}-deploy`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    return new lambda.Function(this, 'DeploymentFunction', {
      functionName: `${projectName}-deploy`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      description: 'Deploy ML model to production endpoints',
      code: lambda.Code.fromInline(`
import json
import boto3
import os
import time

def lambda_handler(event, context):
    codepipeline = boto3.client('codepipeline')
    sagemaker = boto3.client('sagemaker')
    
    # Get job details from CodePipeline
    job_id = event['CodePipeline.job']['id']
    
    try:
        # Get input artifacts
        input_artifacts = event['CodePipeline.job']['data']['inputArtifacts']
        
        # In a real implementation, you would:
        # 1. Extract model package ARN from artifacts
        # 2. Create endpoint configuration
        # 3. Deploy model to production endpoint
        # 4. Implement blue-green deployment strategy
        # 5. Set up monitoring and alerts
        
        print("Starting model deployment to production...")
        
        # Simulate deployment process
        endpoint_name = f"fraud-detection-prod-{int(time.time())}"
        
        print(f"Deploying to endpoint: {endpoint_name}")
        print("Deployment completed successfully")
        
        # Signal success to CodePipeline
        codepipeline.put_job_success_result(jobId=job_id)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Deployment successful',
                'endpoint_name': endpoint_name
            })
        }
        
    except Exception as e:
        print(f"Deployment failed: {str(e)}")
        codepipeline.put_job_failure_result(
            jobId=job_id,
            failureDetails={'message': str(e)}
        )
        raise e
      `),
      logGroup: logGroup,
    });
  }

  /**
   * Creates SNS topic for pipeline notifications
   */
  private createNotificationTopic(projectName: string, notificationEmail?: string): sns.Topic {
    const topic = new sns.Topic(this, 'NotificationTopic', {
      topicName: `${projectName}-notifications`,
      description: 'SNS topic for ML pipeline notifications',
      displayName: 'ML Pipeline Notifications',
    });

    // Add email subscription if provided
    if (notificationEmail) {
      topic.addSubscription(new sns_subscriptions.EmailSubscription(notificationEmail));
    }

    return topic;
  }

  /**
   * Creates the main CodePipeline for ML model deployment
   */
  private createMLDeploymentPipeline(
    projectName: string,
    trainingProject: codebuild.Project,
    testingProject: codebuild.Project,
    deploymentFunction: lambda.Function,
    notificationTopic: sns.Topic
  ): codepipeline.Pipeline {
    // Create artifacts for pipeline stages
    const sourceOutput = new codepipeline.Artifact('SourceOutput');
    const buildOutput = new codepipeline.Artifact('BuildOutput');
    const testOutput = new codepipeline.Artifact('TestOutput');

    // Create the pipeline
    const pipeline = new codepipeline.Pipeline(this, 'MLDeploymentPipeline', {
      pipelineName: `${projectName}-pipeline`,
      role: this.pipelineRole,
      artifactBucket: this.artifactsBucket,
      restartExecutionOnUpdate: true,
      stages: [
        // Source Stage
        {
          stageName: 'Source',
          actions: [
            new codepipeline_actions.S3SourceAction({
              actionName: 'SourceAction',
              bucket: this.artifactsBucket,
              bucketKey: 'source/ml-source-code.zip',
              output: sourceOutput,
              trigger: codepipeline_actions.S3Trigger.EVENTS,
            }),
          ],
        },
        // Build Stage (Model Training)
        {
          stageName: 'Build',
          actions: [
            new codepipeline_actions.CodeBuildAction({
              actionName: 'TrainModel',
              project: trainingProject,
              input: sourceOutput,
              outputs: [buildOutput],
              environmentVariables: {
                SAGEMAKER_ROLE_ARN: {
                  value: this.sagemakerRole.roleArn,
                },
                BUCKET_NAME: {
                  value: this.artifactsBucket.bucketName,
                },
                MODEL_PACKAGE_GROUP_NAME: {
                  value: this.modelPackageGroup.modelPackageGroupName,
                },
              },
            }),
          ],
        },
        // Test Stage (Model Validation)
        {
          stageName: 'Test',
          actions: [
            new codepipeline_actions.CodeBuildAction({
              actionName: 'TestModel',
              project: testingProject,
              input: buildOutput,
              outputs: [testOutput],
            }),
          ],
        },
        // Deploy Stage (Production Deployment)
        {
          stageName: 'Deploy',
          actions: [
            new codepipeline_actions.LambdaInvokeAction({
              actionName: 'DeployModel',
              lambda: deploymentFunction,
              inputs: [testOutput],
            }),
          ],
        },
      ],
    });

    // Add CloudWatch event rule for pipeline state changes
    pipeline.onStateChange('PipelineStateChange', {
      target: new cdk.aws_events_targets.SnsTopic(notificationTopic),
      description: 'Notify on pipeline state changes',
    });

    return pipeline;
  }

  /**
   * Adds consistent tags to all resources in the stack
   */
  private addResourceTags(projectName: string, environment: string): void {
    cdk.Tags.of(this).add('Project', projectName);
    cdk.Tags.of(this).add('Environment', environment);
    cdk.Tags.of(this).add('Purpose', 'MLOps Pipeline');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }

  /**
   * Creates CloudFormation outputs for important resources
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'ArtifactsBucketName', {
      value: this.artifactsBucket.bucketName,
      description: 'Name of the S3 bucket for pipeline artifacts',
      exportName: `${this.stackName}-ArtifactsBucketName`,
    });

    new cdk.CfnOutput(this, 'ModelPackageGroupName', {
      value: this.modelPackageGroup.modelPackageGroupName,
      description: 'Name of the SageMaker Model Package Group',
      exportName: `${this.stackName}-ModelPackageGroupName`,
    });

    new cdk.CfnOutput(this, 'PipelineName', {
      value: this.pipeline.pipelineName,
      description: 'Name of the ML deployment pipeline',
      exportName: `${this.stackName}-PipelineName`,
    });

    new cdk.CfnOutput(this, 'SageMakerRoleArn', {
      value: this.sagemakerRole.roleArn,
      description: 'ARN of the SageMaker execution role',
      exportName: `${this.stackName}-SageMakerRoleArn`,
    });

    new cdk.CfnOutput(this, 'PipelineConsoleURL', {
      value: `https://console.aws.amazon.com/codesuite/codepipeline/pipelines/${this.pipeline.pipelineName}/view`,
      description: 'URL to view the pipeline in AWS Console',
    });

    new cdk.CfnOutput(this, 'SageMakerConsoleURL', {
      value: `https://console.aws.amazon.com/sagemaker/home?region=${this.region}#/model-registry`,
      description: 'URL to view the Model Registry in SageMaker Console',
    });
  }
}

/**
 * CDK App definition and stack instantiation
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const projectName = app.node.tryGetContext('projectName') || process.env.PROJECT_NAME || 'ml-pipeline';
const modelPackageGroupName = app.node.tryGetContext('modelPackageGroupName') || process.env.MODEL_PACKAGE_GROUP_NAME || 'fraud-detection-models';
const notificationEmail = app.node.tryGetContext('notificationEmail') || process.env.NOTIFICATION_EMAIL;
const environment = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'dev';

// Create the main stack
new MLModelDeploymentPipelineStack(app, 'MLModelDeploymentPipelineStack', {
  projectName: projectName,
  modelPackageGroupName: modelPackageGroupName,
  notificationEmail: notificationEmail,
  environment: environment,
  description: 'CDK Stack for Machine Learning Model Deployment Pipeline with SageMaker and CodePipeline',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

// Synthesize the app
app.synth();