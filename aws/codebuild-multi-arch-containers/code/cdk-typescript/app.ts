#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as codebuild from 'aws-cdk-lib/aws-codebuild';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * CDK Stack for Multi-Architecture Container Images with CodeBuild
 * 
 * This stack creates the infrastructure needed to build multi-architecture
 * container images (ARM64 and x86_64) using AWS CodeBuild and store them
 * in Amazon ECR.
 */
export class MultiArchContainerImagesStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Parameters for customization
    const projectName = new cdk.CfnParameter(this, 'ProjectName', {
      type: 'String',
      description: 'Name for the CodeBuild project',
      default: 'multi-arch-container-build',
      allowedPattern: '[A-Za-z0-9-_]+',
      constraintDescription: 'Must contain only alphanumeric characters, hyphens, and underscores'
    });

    const ecrRepositoryName = new cdk.CfnParameter(this, 'ECRRepositoryName', {
      type: 'String',
      description: 'Name for the ECR repository',
      default: 'multi-arch-sample-app',
      allowedPattern: '[a-z0-9-_/]+',
      constraintDescription: 'Must contain only lowercase letters, numbers, hyphens, underscores, and forward slashes'
    });

    const computeType = new cdk.CfnParameter(this, 'ComputeType', {
      type: 'String',
      description: 'CodeBuild compute type for multi-architecture builds',
      default: 'BUILD_GENERAL1_MEDIUM',
      allowedValues: [
        'BUILD_GENERAL1_SMALL',
        'BUILD_GENERAL1_MEDIUM',
        'BUILD_GENERAL1_LARGE',
        'BUILD_GENERAL1_2XLARGE'
      ]
    });

    // Create ECR repository for storing multi-architecture images
    const ecrRepository = new ecr.Repository(this, 'ECRRepository', {
      repositoryName: ecrRepositoryName.valueAsString,
      imageScanOnPush: true,
      imageTagMutability: ecr.TagMutability.MUTABLE,
      encryption: ecr.RepositoryEncryption.AES_256,
      lifecycleRules: [
        {
          rulePriority: 1,
          description: 'Keep last 10 images',
          maxImageCount: 10,
          selection: {
            tagStatus: ecr.TagStatus.ANY
          }
        }
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Create S3 bucket for storing source code
    const sourceBucket = new s3.Bucket(this, 'SourceBucket', {
      bucketName: `${projectName.valueAsString}-source-${cdk.Aws.ACCOUNT_ID}-${cdk.Aws.REGION}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioning: true,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(30)
        }
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true
    });

    // Create CloudWatch Log Group for CodeBuild logs
    const logGroup = new logs.LogGroup(this, 'CodeBuildLogGroup', {
      logGroupName: `/aws/codebuild/${projectName.valueAsString}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Create IAM role for CodeBuild with necessary permissions
    const codeBuildRole = new iam.Role(this, 'CodeBuildRole', {
      assumedBy: new iam.ServicePrincipal('codebuild.amazonaws.com'),
      description: 'IAM role for CodeBuild multi-architecture container builds',
      inlinePolicies: {
        CodeBuildMultiArchPolicy: new iam.PolicyDocument({
          statements: [
            // CloudWatch Logs permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents'
              ],
              resources: [
                logGroup.logGroupArn,
                `${logGroup.logGroupArn}:*`
              ]
            }),
            // ECR permissions for multi-architecture image management
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ecr:GetAuthorizationToken'
              ],
              resources: ['*']
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ecr:BatchCheckLayerAvailability',
                'ecr:GetDownloadUrlForLayer',
                'ecr:BatchGetImage',
                'ecr:PutImage',
                'ecr:InitiateLayerUpload',
                'ecr:UploadLayerPart',
                'ecr:CompleteLayerUpload'
              ],
              resources: [ecrRepository.repositoryArn]
            }),
            // S3 permissions for source code access
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:GetObjectVersion'
              ],
              resources: [`${sourceBucket.bucketArn}/*`]
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:ListBucket'
              ],
              resources: [sourceBucket.bucketArn]
            })
          ]
        })
      }
    });

    // Create buildspec content for multi-architecture builds
    const buildSpec = codebuild.BuildSpec.fromObject({
      version: '0.2',
      phases: {
        pre_build: {
          commands: [
            'echo Logging in to Amazon ECR...',
            'aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com',
            'REPOSITORY_URI=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME',
            'COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)',
            'IMAGE_TAG=${COMMIT_HASH:=latest}',
            'echo Repository URI is $REPOSITORY_URI',
            'echo Image tag is $IMAGE_TAG'
          ]
        },
        build: {
          commands: [
            'echo Build started on `date`',
            'echo Building multi-architecture Docker image...',
            '',
            '# Create and use buildx builder for multi-architecture builds',
            'docker buildx create --name multiarch-builder --use --bootstrap',
            'docker buildx inspect --bootstrap',
            '',
            '# Build and push multi-architecture image (ARM64 and x86_64)',
            'docker buildx build \\',
            '  --platform linux/amd64,linux/arm64 \\',
            '  --tag $REPOSITORY_URI:latest \\',
            '  --tag $REPOSITORY_URI:$IMAGE_TAG \\',
            '  --push \\',
            '  --cache-from type=local,src=/tmp/.buildx-cache \\',
            '  --cache-to type=local,dest=/tmp/.buildx-cache-new,mode=max \\',
            '  .',
            '',
            '# Move cache to prevent unbounded growth',
            'rm -rf /tmp/.buildx-cache',
            'mv /tmp/.buildx-cache-new /tmp/.buildx-cache'
          ]
        },
        post_build: {
          commands: [
            'echo Build completed on `date`',
            'echo Pushing multi-architecture Docker images...',
            'docker buildx imagetools inspect $REPOSITORY_URI:latest',
            'printf \'{"ImageURI":"%s"}\' $REPOSITORY_URI:latest > imageDetail.json'
          ]
        }
      },
      artifacts: {
        files: [
          'imageDetail.json'
        ]
      },
      cache: {
        paths: [
          '/tmp/.buildx-cache/**/*'
        ]
      }
    });

    // Create CodeBuild project for multi-architecture builds
    const codeBuildProject = new codebuild.Project(this, 'CodeBuildProject', {
      projectName: projectName.valueAsString,
      description: 'Multi-architecture container image build project using Docker Buildx',
      source: codebuild.Source.s3({
        bucket: sourceBucket,
        path: 'source.zip'
      }),
      artifacts: codebuild.Artifacts.noArtifacts(),
      environment: {
        buildImage: codebuild.LinuxBuildImage.STANDARD_7_0,
        computeType: codebuild.ComputeType[computeType.valueAsString as keyof typeof codebuild.ComputeType],
        privileged: true, // Required for Docker Buildx multi-architecture builds
        environmentVariables: {
          AWS_DEFAULT_REGION: {
            value: cdk.Aws.REGION
          },
          AWS_ACCOUNT_ID: {
            value: cdk.Aws.ACCOUNT_ID
          },
          IMAGE_REPO_NAME: {
            value: ecrRepository.repositoryName
          }
        }
      },
      role: codeBuildRole,
      buildSpec: buildSpec,
      timeout: cdk.Duration.hours(1),
      cache: codebuild.Cache.local(codebuild.LocalCacheMode.DOCKER_LAYER),
      logging: {
        cloudWatch: {
          logGroup: logGroup
        }
      }
    });

    // Add tags to all resources
    const tags = {
      Project: 'MultiArchContainerImages',
      Purpose: 'Multi-architecture container builds',
      Environment: 'Development'
    };

    Object.entries(tags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });

    // Stack outputs
    new cdk.CfnOutput(this, 'ECRRepositoryURI', {
      value: ecrRepository.repositoryUri,
      description: 'URI of the ECR repository for multi-architecture images',
      exportName: `${this.stackName}-ECRRepositoryURI`
    });

    new cdk.CfnOutput(this, 'ECRRepositoryName', {
      value: ecrRepository.repositoryName,
      description: 'Name of the ECR repository',
      exportName: `${this.stackName}-ECRRepositoryName`
    });

    new cdk.CfnOutput(this, 'CodeBuildProjectName', {
      value: codeBuildProject.projectName,
      description: 'Name of the CodeBuild project for multi-architecture builds',
      exportName: `${this.stackName}-CodeBuildProjectName`
    });

    new cdk.CfnOutput(this, 'SourceBucketName', {
      value: sourceBucket.bucketName,
      description: 'Name of the S3 bucket for source code storage',
      exportName: `${this.stackName}-SourceBucketName`
    });

    new cdk.CfnOutput(this, 'CodeBuildRoleArn', {
      value: codeBuildRole.roleArn,
      description: 'ARN of the IAM role used by CodeBuild',
      exportName: `${this.stackName}-CodeBuildRoleArn`
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: logGroup.logGroupName,
      description: 'Name of the CloudWatch Log Group for CodeBuild logs',
      exportName: `${this.stackName}-LogGroupName`
    });

    // Output commands for manual testing
    new cdk.CfnOutput(this, 'StartBuildCommand', {
      value: `aws codebuild start-build --project-name ${codeBuildProject.projectName}`,
      description: 'Command to start a build manually'
    });

    new cdk.CfnOutput(this, 'InspectImageCommand', {
      value: `docker buildx imagetools inspect ${ecrRepository.repositoryUri}:latest`,
      description: 'Command to inspect the multi-architecture image manifest'
    });
  }
}

// CDK App
const app = new cdk.App();

// Deploy the stack
new MultiArchContainerImagesStack(app, 'MultiArchContainerImagesStack', {
  description: 'Infrastructure for building multi-architecture container images with CodeBuild and ECR',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  }
});

// Synthesize the app
app.synth();