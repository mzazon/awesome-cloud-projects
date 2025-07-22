#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import {
  aws_s3 as s3,
  aws_iam as iam,
  aws_codecommit as codecommit,
  aws_sagemaker as sagemaker,
  RemovalPolicy,
  CfnOutput,
} from 'aws-cdk-lib';

/**
 * Stack for End-to-End MLOps with SageMaker Pipelines
 * 
 * This stack creates the infrastructure needed for a complete MLOps workflow including:
 * - S3 bucket for data and model artifacts
 * - CodeCommit repository for ML code versioning
 * - IAM roles with appropriate permissions for SageMaker
 * - SageMaker Pipeline for automated ML workflows
 */
export class MlOpsSageMakerPipelinesStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = this.node.tryGetContext('uniqueSuffix') || 
      Math.random().toString(36).substring(2, 8);

    // S3 Bucket for storing training data, model artifacts, and pipeline outputs
    const mlOpsBucket = new s3.Bucket(this, 'MlOpsBucket', {
      bucketName: `sagemaker-mlops-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'DeleteIncompleteMultipartUploads',
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
        },
        {
          id: 'TransitionToIA',
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
          ],
        },
      ],
    });

    // CodeCommit Repository for ML code version control
    const mlOpsRepository = new codecommit.Repository(this, 'MlOpsRepository', {
      repositoryName: `mlops-${uniqueSuffix}`,
      description: 'MLOps pipeline code repository for machine learning workflows',
    });

    // IAM Role for SageMaker execution with comprehensive permissions
    const sageMakerExecutionRole = new iam.Role(this, 'SageMakerExecutionRole', {
      roleName: `SageMakerExecutionRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('sagemaker.amazonaws.com'),
      description: 'Execution role for SageMaker Pipeline operations',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSageMakerFullAccess'),
      ],
      inlinePolicies: {
        S3Access: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket',
                's3:GetBucketLocation',
                's3:ListAllMyBuckets',
              ],
              resources: [
                mlOpsBucket.bucketArn,
                `${mlOpsBucket.bucketArn}/*`,
              ],
            }),
          ],
        }),
        CodeCommitAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'codecommit:GitPull',
                'codecommit:GitPush',
                'codecommit:GetRepository',
                'codecommit:ListRepositories',
                'codecommit:GetBranch',
                'codecommit:ListBranches',
              ],
              resources: [mlOpsRepository.repositoryArn],
            }),
          ],
        }),
        CloudWatchLogsAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
                'logs:DescribeLogStreams',
              ],
              resources: [
                `arn:aws:logs:${this.region}:${this.account}:log-group:/aws/sagemaker/*`,
              ],
            }),
          ],
        }),
        ECRAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ecr:GetDownloadUrlForLayer',
                'ecr:BatchGetImage',
                'ecr:GetAuthorizationToken',
                'ecr:BatchCheckLayerAvailability',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // SageMaker Pipeline for MLOps workflow
    const pipelineName = `mlops-pipeline-${uniqueSuffix}`;
    
    // Pipeline definition using SageMaker Pipelines SDK (simplified version)
    const pipelineDefinition = {
      Version: '2020-12-01',
      Metadata: {},
      Parameters: [
        {
          Name: 'InputData',
          Type: 'String',
          DefaultValue: `s3://${mlOpsBucket.bucketName}/data/train.csv`,
        },
        {
          Name: 'ProcessingInstanceType',
          Type: 'String',
          DefaultValue: 'ml.m5.large',
        },
        {
          Name: 'TrainingInstanceType',
          Type: 'String',
          DefaultValue: 'ml.m5.large',
        },
      ],
      Steps: [
        {
          Name: 'DataProcessing',
          Type: 'Processing',
          Arguments: {
            ProcessingJobName: 'data-preprocessing',
            ProcessingResources: {
              ClusterConfig: {
                InstanceType: 'ml.m5.large',
                InstanceCount: 1,
                VolumeSizeInGB: 30,
              },
            },
            AppSpecification: {
              ImageUri: '382416733822.dkr.ecr.us-east-1.amazonaws.com/xgboost:latest',
              ContainerEntrypoint: ['python3'],
            },
            RoleArn: sageMakerExecutionRole.roleArn,
          },
        },
        {
          Name: 'ModelTraining',
          Type: 'Training',
          Arguments: {
            TrainingJobName: 'model-training',
            RoleArn: sageMakerExecutionRole.roleArn,
            AlgorithmSpecification: {
              TrainingImage: '382416733822.dkr.ecr.us-east-1.amazonaws.com/xgboost:latest',
              TrainingInputMode: 'File',
            },
            ResourceConfig: {
              InstanceType: 'ml.m5.large',
              InstanceCount: 1,
              VolumeSizeInGB: 30,
            },
            StoppingCondition: {
              MaxRuntimeInSeconds: 3600,
            },
          },
        },
        {
          Name: 'ModelEvaluation',
          Type: 'Processing',
          Arguments: {
            ProcessingJobName: 'model-evaluation',
            ProcessingResources: {
              ClusterConfig: {
                InstanceType: 'ml.m5.large',
                InstanceCount: 1,
                VolumeSizeInGB: 30,
              },
            },
            AppSpecification: {
              ImageUri: '382416733822.dkr.ecr.us-east-1.amazonaws.com/xgboost:latest',
              ContainerEntrypoint: ['python3'],
            },
            RoleArn: sageMakerExecutionRole.roleArn,
          },
        },
      ],
    };

    // Note: SageMaker Pipeline creation via CDK requires custom resource or L1 constructs
    // This creates the pipeline configuration that can be used with the SageMaker Python SDK
    const cfnPipeline = new sagemaker.CfnPipeline(this, 'MLOpsPipeline', {
      pipelineName: pipelineName,
      pipelineDefinition: JSON.stringify(pipelineDefinition),
      roleArn: sageMakerExecutionRole.roleArn,
      pipelineDescription: 'End-to-end MLOps pipeline for automated model training and deployment',
      pipelineDisplayName: `MLOps Pipeline - ${uniqueSuffix}`,
      tags: [
        {
          key: 'Environment',
          value: 'Development',
        },
        {
          key: 'Project',
          value: 'MLOps',
        },
        {
          key: 'Owner',
          value: 'DataScience',
        },
      ],
    });

    // CloudWatch Log Group for SageMaker Pipeline logs
    const pipelineLogGroup = new cdk.aws_logs.LogGroup(this, 'PipelineLogGroup', {
      logGroupName: `/aws/sagemaker/pipeline/${pipelineName}`,
      retention: cdk.aws_logs.RetentionDays.ONE_MONTH,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    // Outputs for reference and integration
    new CfnOutput(this, 'S3BucketName', {
      value: mlOpsBucket.bucketName,
      description: 'S3 bucket for storing ML data and artifacts',
      exportName: `${this.stackName}-S3BucketName`,
    });

    new CfnOutput(this, 'S3BucketArn', {
      value: mlOpsBucket.bucketArn,
      description: 'S3 bucket ARN for IAM policies',
      exportName: `${this.stackName}-S3BucketArn`,
    });

    new CfnOutput(this, 'CodeCommitRepositoryName', {
      value: mlOpsRepository.repositoryName,
      description: 'CodeCommit repository for ML code',
      exportName: `${this.stackName}-CodeCommitRepositoryName`,
    });

    new CfnOutput(this, 'CodeCommitRepositoryCloneUrl', {
      value: mlOpsRepository.repositoryCloneUrlHttp,
      description: 'CodeCommit repository clone URL (HTTPS)',
      exportName: `${this.stackName}-CodeCommitRepositoryCloneUrl`,
    });

    new CfnOutput(this, 'SageMakerExecutionRoleArn', {
      value: sageMakerExecutionRole.roleArn,
      description: 'SageMaker execution role ARN',
      exportName: `${this.stackName}-SageMakerExecutionRoleArn`,
    });

    new CfnOutput(this, 'SageMakerPipelineName', {
      value: pipelineName,
      description: 'SageMaker Pipeline name',
      exportName: `${this.stackName}-SageMakerPipelineName`,
    });

    new CfnOutput(this, 'PipelineLogGroupName', {
      value: pipelineLogGroup.logGroupName,
      description: 'CloudWatch log group for pipeline logs',
      exportName: `${this.stackName}-PipelineLogGroupName`,
    });

    // Output deployment commands for easy reference
    new CfnOutput(this, 'DeploymentCommands', {
      value: [
        `export BUCKET_NAME=${mlOpsBucket.bucketName}`,
        `export PIPELINE_NAME=${pipelineName}`,
        `export ROLE_ARN=${sageMakerExecutionRole.roleArn}`,
        `export REPO_NAME=${mlOpsRepository.repositoryName}`,
      ].join(' && '),
      description: 'Environment variables for manual CLI operations',
    });
  }
}

// CDK App
const app = new cdk.App();

// Get deployment context
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT || process.env.AWS_ACCOUNT_ID,
  region: process.env.CDK_DEFAULT_REGION || process.env.AWS_REGION || 'us-east-1',
};

// Deploy the stack
new MlOpsSageMakerPipelinesStack(app, 'MlOpsSageMakerPipelinesStack', {
  env,
  description: 'End-to-End MLOps infrastructure with SageMaker Pipelines, S3, and CodeCommit',
  tags: {
    Project: 'MLOps',
    Environment: 'Development',
    Owner: 'DataScience',
    CostCenter: 'Engineering',
  },
});

// Add stack-level tags
cdk.Tags.of(app).add('Project', 'MLOps');
cdk.Tags.of(app).add('CreatedBy', 'CDK');
cdk.Tags.of(app).add('Repository', 'recipes');