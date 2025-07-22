#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as codecommit from 'aws-cdk-lib/aws-codecommit';
import * as codebuild from 'aws-cdk-lib/aws-codebuild';
import * as codepipeline from 'aws-cdk-lib/aws-codepipeline';
import * as codepipeline_actions from 'aws-cdk-lib/aws-codepipeline-actions';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Duration } from 'aws-cdk-lib';

/**
 * Stack for Orchestrating Multi-Branch CI/CD Automation with CodePipeline
 * This stack implements automated pipeline creation and management based on branch events
 */
export class MultiBranchCiCdStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const randomSuffix = Math.random().toString(36).substring(2, 8);
    const stackSuffix = `${randomSuffix}`;

    // Create S3 bucket for pipeline artifacts
    const artifactBucket = new s3.Bucket(this, 'ArtifactBucket', {
      bucketName: `multi-branch-artifacts-${stackSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'DeleteOldArtifacts',
          enabled: true,
          expiration: Duration.days(30),
          noncurrentVersionExpiration: Duration.days(7),
        },
      ],
    });

    // Create CodeCommit repository
    const repository = new codecommit.Repository(this, 'Repository', {
      repositoryName: `multi-branch-app-${stackSuffix}`,
      description: 'Multi-branch CI/CD demo application',
    });

    // Create IAM role for CodePipeline
    const pipelineRole = new iam.Role(this, 'PipelineRole', {
      roleName: `CodePipelineMultiBranchRole-${stackSuffix}`,
      assumedBy: new iam.ServicePrincipal('codepipeline.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSCodePipelineFullAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSCodeCommitFullAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSCodeBuildDeveloperAccess'),
      ],
    });

    // Grant pipeline role access to S3 bucket
    artifactBucket.grantReadWrite(pipelineRole);

    // Create IAM role for CodeBuild
    const codeBuildRole = new iam.Role(this, 'CodeBuildRole', {
      roleName: `CodeBuildMultiBranchRole-${stackSuffix}`,
      assumedBy: new iam.ServicePrincipal('codebuild.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchLogsFullAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonS3FullAccess'),
      ],
    });

    // Create CodeBuild project for multi-branch builds
    const buildProject = new codebuild.Project(this, 'BuildProject', {
      projectName: `multi-branch-build-${stackSuffix}`,
      description: 'Build project for multi-branch pipelines',
      role: codeBuildRole,
      source: codebuild.Source.codeCommit({
        repository: repository,
      }),
      environment: {
        buildImage: codebuild.LinuxBuildImage.AMAZON_LINUX_2_3,
        computeType: codebuild.ComputeType.SMALL,
        environmentVariables: {
          AWS_DEFAULT_REGION: {
            value: this.region,
          },
          AWS_ACCOUNT_ID: {
            value: this.account,
          },
        },
      },
      buildSpec: codebuild.BuildSpec.fromObject({
        version: '0.2',
        phases: {
          pre_build: {
            commands: [
              'echo Logging in to Amazon ECR...',
              'aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com',
            ],
          },
          build: {
            commands: [
              'echo Build started on `date`',
              'echo Building the Docker image...',
              'docker build -t $IMAGE_REPO_NAME:$IMAGE_TAG .',
              'docker tag $IMAGE_REPO_NAME:$IMAGE_TAG $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_TAG',
            ],
          },
          post_build: {
            commands: [
              'echo Build completed on `date`',
              'echo Pushing the Docker image...',
              'docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_TAG',
            ],
          },
        },
        artifacts: {
          files: ['**/*'],
        },
      }),
      artifacts: codebuild.Artifacts.s3({
        bucket: artifactBucket,
        includeBuildId: true,
        packageZip: true,
      }),
    });

    // Create IAM role for Lambda function
    const lambdaRole = new iam.Role(this, 'LambdaRole', {
      roleName: `LambdaPipelineManagerRole-${stackSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSCodePipelineFullAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSCodeBuildAdminAccess'),
      ],
    });

    // Create Lambda function for pipeline management
    const pipelineManagerFunction = new lambda.Function(this, 'PipelineManagerFunction', {
      functionName: `pipeline-manager-${stackSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: Duration.minutes(5),
      environment: {
        AWS_ACCOUNT_ID: this.account,
        PIPELINE_ROLE_ARN: pipelineRole.roleArn,
        CODEBUILD_PROJECT_NAME: buildProject.projectName,
        ARTIFACT_BUCKET: artifactBucket.bucketName,
        REPOSITORY_NAME: repository.repositoryName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
import logging
from typing import Dict, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

codepipeline = boto3.client('codepipeline')
codecommit = boto3.client('codecommit')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function to manage multi-branch CI/CD pipelines
    """
    try:
        # Parse EventBridge event
        detail = event.get('detail', {})
        event_name = detail.get('eventName', '')
        repository_name = detail.get('requestParameters', {}).get('repositoryName', '')
        
        logger.info(f"Processing event: {event_name} for repository: {repository_name}")
        
        if event_name == 'CreateBranch':
            return handle_branch_creation(detail, repository_name)
        elif event_name == 'DeleteBranch':
            return handle_branch_deletion(detail, repository_name)
        elif event_name == 'GitPush':
            return handle_git_push(detail, repository_name)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Event processed but no action taken')
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def handle_branch_creation(detail: Dict[str, Any], repository_name: str) -> Dict[str, Any]:
    """Handle branch creation events"""
    branch_name = detail.get('requestParameters', {}).get('branchName', '')
    
    if not branch_name:
        return {'statusCode': 400, 'body': 'Branch name not found'}
    
    # Only create pipelines for feature branches
    if branch_name.startswith('feature/'):
        pipeline_name = f"{repository_name}-{branch_name.replace('/', '-')}"
        
        try:
            create_branch_pipeline(repository_name, branch_name, pipeline_name)
            logger.info(f"Created pipeline {pipeline_name} for branch {branch_name}")
            
            return {
                'statusCode': 200,
                'body': json.dumps(f'Pipeline {pipeline_name} created successfully')
            }
        except Exception as e:
            logger.error(f"Failed to create pipeline: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps(f'Pipeline creation failed: {str(e)}')
            }
    
    return {'statusCode': 200, 'body': 'No pipeline created for this branch type'}

def handle_branch_deletion(detail: Dict[str, Any], repository_name: str) -> Dict[str, Any]:
    """Handle branch deletion events"""
    branch_name = detail.get('requestParameters', {}).get('branchName', '')
    
    if branch_name.startswith('feature/'):
        pipeline_name = f"{repository_name}-{branch_name.replace('/', '-')}"
        
        try:
            # Delete the pipeline
            codepipeline.delete_pipeline(name=pipeline_name)
            logger.info(f"Deleted pipeline {pipeline_name}")
            
            return {
                'statusCode': 200,
                'body': json.dumps(f'Pipeline {pipeline_name} deleted successfully')
            }
        except codepipeline.exceptions.PipelineNotFoundException:
            return {
                'statusCode': 404,
                'body': json.dumps(f'Pipeline {pipeline_name} not found')
            }
        except Exception as e:
            logger.error(f"Failed to delete pipeline: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps(f'Pipeline deletion failed: {str(e)}')
            }
    
    return {'statusCode': 200, 'body': 'No pipeline deleted for this branch type'}

def handle_git_push(detail: Dict[str, Any], repository_name: str) -> Dict[str, Any]:
    """Handle git push events"""
    # For push events, we just log and let the pipeline trigger naturally
    branch_name = detail.get('requestParameters', {}).get('branchName', '')
    logger.info(f"Git push detected on branch {branch_name} in repository {repository_name}")
    
    return {
        'statusCode': 200,
        'body': json.dumps('Git push event processed')
    }

def create_branch_pipeline(repository_name: str, branch_name: str, pipeline_name: str) -> None:
    """Create a new pipeline for the specified branch"""
    
    pipeline_definition = {
        "pipeline": {
            "name": pipeline_name,
            "roleArn": os.environ['PIPELINE_ROLE_ARN'],
            "artifactStore": {
                "type": "S3",
                "location": os.environ['ARTIFACT_BUCKET']
            },
            "stages": [
                {
                    "name": "Source",
                    "actions": [
                        {
                            "name": "SourceAction",
                            "actionTypeId": {
                                "category": "Source",
                                "owner": "AWS",
                                "provider": "CodeCommit",
                                "version": "1"
                            },
                            "configuration": {
                                "RepositoryName": repository_name,
                                "BranchName": branch_name
                            },
                            "outputArtifacts": [
                                {
                                    "name": "SourceOutput"
                                }
                            ]
                        }
                    ]
                },
                {
                    "name": "Build",
                    "actions": [
                        {
                            "name": "BuildAction",
                            "actionTypeId": {
                                "category": "Build",
                                "owner": "AWS",
                                "provider": "CodeBuild",
                                "version": "1"
                            },
                            "configuration": {
                                "ProjectName": os.environ['CODEBUILD_PROJECT_NAME']
                            },
                            "inputArtifacts": [
                                {
                                    "name": "SourceOutput"
                                }
                            ],
                            "outputArtifacts": [
                                {
                                    "name": "BuildOutput"
                                }
                            ]
                        }
                    ]
                }
            ]
        }
    }
    
    # Create the pipeline
    codepipeline.create_pipeline(**pipeline_definition)
      `),
    });

    // Create EventBridge rule for CodeCommit events
    const eventRule = new events.Rule(this, 'CodeCommitBranchEvents', {
      ruleName: `CodeCommitBranchEvents-${stackSuffix}`,
      description: 'Trigger pipeline management for branch events',
      eventPattern: {
        source: ['aws.codecommit'],
        detailType: ['CodeCommit Repository State Change'],
        detail: {
          repositoryName: [repository.repositoryName],
          eventName: ['CreateBranch', 'DeleteBranch', 'GitPush'],
        },
      },
    });

    // Add Lambda function as target for EventBridge rule
    eventRule.addTarget(new targets.LambdaFunction(pipelineManagerFunction));

    // Create main branch pipeline
    const mainSourceOutput = new codepipeline.Artifact();
    const mainBuildOutput = new codepipeline.Artifact();

    const mainPipeline = new codepipeline.Pipeline(this, 'MainPipeline', {
      pipelineName: `${repository.repositoryName}-main`,
      role: pipelineRole,
      artifactBucket: artifactBucket,
      stages: [
        {
          stageName: 'Source',
          actions: [
            new codepipeline_actions.CodeCommitSourceAction({
              actionName: 'SourceAction',
              repository: repository,
              branch: 'main',
              output: mainSourceOutput,
            }),
          ],
        },
        {
          stageName: 'Build',
          actions: [
            new codepipeline_actions.CodeBuildAction({
              actionName: 'BuildAction',
              project: buildProject,
              input: mainSourceOutput,
              outputs: [mainBuildOutput],
            }),
          ],
        },
      ],
    });

    // Create develop branch pipeline
    const developSourceOutput = new codepipeline.Artifact();
    const developBuildOutput = new codepipeline.Artifact();

    const developPipeline = new codepipeline.Pipeline(this, 'DevelopPipeline', {
      pipelineName: `${repository.repositoryName}-develop`,
      role: pipelineRole,
      artifactBucket: artifactBucket,
      stages: [
        {
          stageName: 'Source',
          actions: [
            new codepipeline_actions.CodeCommitSourceAction({
              actionName: 'SourceAction',
              repository: repository,
              branch: 'develop',
              output: developSourceOutput,
            }),
          ],
        },
        {
          stageName: 'Build',
          actions: [
            new codepipeline_actions.CodeBuildAction({
              actionName: 'BuildAction',
              project: buildProject,
              input: developSourceOutput,
              outputs: [developBuildOutput],
            }),
          ],
        },
      ],
    });

    // Create SNS topic for pipeline alerts
    const alertTopic = new sns.Topic(this, 'PipelineAlerts', {
      topicName: `PipelineAlerts-${stackSuffix}`,
      displayName: 'Multi-branch Pipeline Alerts',
    });

    // Create CloudWatch dashboard for pipeline monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'PipelineDashboard', {
      dashboardName: `MultibranchPipelines-${stackSuffix}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Pipeline Execution Results',
            width: 12,
            height: 6,
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/CodePipeline',
                metricName: 'PipelineExecutionSuccess',
                dimensionsMap: {
                  PipelineName: mainPipeline.pipelineName,
                },
                statistic: 'Sum',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/CodePipeline',
                metricName: 'PipelineExecutionFailure',
                dimensionsMap: {
                  PipelineName: mainPipeline.pipelineName,
                },
                statistic: 'Sum',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/CodePipeline',
                metricName: 'PipelineExecutionSuccess',
                dimensionsMap: {
                  PipelineName: developPipeline.pipelineName,
                },
                statistic: 'Sum',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/CodePipeline',
                metricName: 'PipelineExecutionFailure',
                dimensionsMap: {
                  PipelineName: developPipeline.pipelineName,
                },
                statistic: 'Sum',
              }),
            ],
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Build Performance',
            width: 12,
            height: 6,
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/CodeBuild',
                metricName: 'Duration',
                dimensionsMap: {
                  ProjectName: buildProject.projectName,
                },
                statistic: 'Average',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/CodeBuild',
                metricName: 'SucceededBuilds',
                dimensionsMap: {
                  ProjectName: buildProject.projectName,
                },
                statistic: 'Sum',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/CodeBuild',
                metricName: 'FailedBuilds',
                dimensionsMap: {
                  ProjectName: buildProject.projectName,
                },
                statistic: 'Sum',
              }),
            ],
          }),
        ],
      ],
    });

    // Create CloudWatch alarm for pipeline failures
    const pipelineFailureAlarm = new cloudwatch.Alarm(this, 'PipelineFailureAlarm', {
      alarmName: `PipelineFailure-${repository.repositoryName}`,
      alarmDescription: 'Alert when pipeline fails',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/CodePipeline',
        metricName: 'PipelineExecutionFailure',
        dimensionsMap: {
          PipelineName: mainPipeline.pipelineName,
        },
        statistic: 'Sum',
      }),
      threshold: 1,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
    });

    // Add SNS action to alarm
    pipelineFailureAlarm.addAlarmAction(
      new cloudwatch.SnsAction(alertTopic)
    );

    // Create CloudWatch log group for Lambda function
    const logGroup = new logs.LogGroup(this, 'PipelineManagerLogGroup', {
      logGroupName: `/aws/lambda/${pipelineManagerFunction.functionName}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Stack outputs
    new cdk.CfnOutput(this, 'RepositoryCloneUrl', {
      value: repository.repositoryCloneUrlHttp,
      description: 'CodeCommit repository clone URL',
    });

    new cdk.CfnOutput(this, 'ArtifactBucketName', {
      value: artifactBucket.bucketName,
      description: 'S3 bucket for pipeline artifacts',
    });

    new cdk.CfnOutput(this, 'PipelineManagerFunctionName', {
      value: pipelineManagerFunction.functionName,
      description: 'Lambda function for pipeline management',
    });

    new cdk.CfnOutput(this, 'BuildProjectName', {
      value: buildProject.projectName,
      description: 'CodeBuild project for multi-branch builds',
    });

    new cdk.CfnOutput(this, 'MainPipelineName', {
      value: mainPipeline.pipelineName,
      description: 'CodePipeline for main branch',
    });

    new cdk.CfnOutput(this, 'DevelopPipelineName', {
      value: developPipeline.pipelineName,
      description: 'CodePipeline for develop branch',
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch dashboard URL',
    });

    new cdk.CfnOutput(this, 'AlertTopicArn', {
      value: alertTopic.topicArn,
      description: 'SNS topic ARN for pipeline alerts',
    });
  }
}

// CDK App
const app = new cdk.App();

// Get deployment configuration from context or environment
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT || process.env.AWS_ACCOUNT_ID,
  region: process.env.CDK_DEFAULT_REGION || process.env.AWS_REGION || 'us-east-1',
};

// Create stack
new MultiBranchCiCdStack(app, 'MultiBranchCiCdStack', {
  env,
  description: 'Multi-branch CI/CD pipelines with CodePipeline, CodeCommit, CodeBuild, and Lambda',
  tags: {
    Project: 'MultiBranchCiCd',
    Environment: 'Demo',
    ManagedBy: 'CDK',
  },
});

// Synthesize the app
app.synth();