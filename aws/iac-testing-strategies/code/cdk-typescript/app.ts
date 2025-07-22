#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as codecommit from 'aws-cdk-lib/aws-codecommit';
import * as codebuild from 'aws-cdk-lib/aws-codebuild';
import * as codepipeline from 'aws-cdk-lib/aws-codepipeline';
import * as codepipeline_actions from 'aws-cdk-lib/aws-codepipeline-actions';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Properties for the Infrastructure Testing Stack
 */
interface InfrastructureTestingStackProps extends cdk.StackProps {
  /**
   * Project name prefix for resource naming
   * @default 'iac-testing'
   */
  readonly projectName?: string;

  /**
   * Repository name for storing IaC code
   * @default 'iac-testing-repo'
   */
  readonly repositoryName?: string;

  /**
   * Whether to enable detailed monitoring
   * @default true
   */
  readonly enableDetailedMonitoring?: boolean;

  /**
   * Build environment compute type
   * @default BUILD_GENERAL1_SMALL
   */
  readonly buildComputeType?: codebuild.ComputeType;
}

/**
 * Infrastructure Testing Stack
 * 
 * This stack creates a comprehensive automated testing pipeline for Infrastructure as Code.
 * It includes:
 * - CodeCommit repository for source control
 * - S3 bucket for build artifacts
 * - CodeBuild project for running tests
 * - CodePipeline for orchestrating the testing workflow
 * - IAM roles with least privilege access
 * - CloudWatch logs for monitoring
 */
export class InfrastructureTestingStack extends cdk.Stack {
  public readonly repository: codecommit.Repository;
  public readonly artifactsBucket: s3.Bucket;
  public readonly buildProject: codebuild.Project;
  public readonly pipeline: codepipeline.Pipeline;

  constructor(scope: Construct, id: string, props: InfrastructureTestingStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const projectName = props.projectName ?? 'iac-testing';
    const repositoryName = props.repositoryName ?? 'iac-testing-repo';
    const enableDetailedMonitoring = props.enableDetailedMonitoring ?? true;
    const buildComputeType = props.buildComputeType ?? codebuild.ComputeType.SMALL;

    // Create S3 bucket for storing build artifacts with security best practices
    this.artifactsBucket = new s3.Bucket(this, 'ArtifactsBucket', {
      bucketName: `${projectName}-artifacts-${cdk.Aws.ACCOUNT_ID}-${cdk.Aws.REGION}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: true,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(30),
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
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
    });

    // Create CodeCommit repository for Infrastructure as Code
    this.repository = new codecommit.Repository(this, 'IaCRepository', {
      repositoryName: repositoryName,
      description: 'Infrastructure as Code Testing Repository - Contains templates, tests, and CI/CD configurations',
      code: codecommit.Code.fromDirectory('./sample-iac-project', 'main'),
    });

    // Create CloudWatch Log Group for CodeBuild
    const buildLogGroup = new logs.LogGroup(this, 'BuildLogGroup', {
      logGroupName: `/aws/codebuild/${projectName}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create IAM role for CodeBuild with least privilege permissions
    const codeBuildRole = new iam.Role(this, 'CodeBuildRole', {
      assumedBy: new iam.ServicePrincipal('codebuild.amazonaws.com'),
      description: 'IAM role for Infrastructure Testing CodeBuild project',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSCodeBuildDeveloperAccess'),
      ],
      inlinePolicies: {
        InfrastructureTestingPolicy: new iam.PolicyDocument({
          statements: [
            // CloudWatch Logs permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: [
                buildLogGroup.logGroupArn,
                `${buildLogGroup.logGroupArn}:*`,
              ],
            }),
            // S3 permissions for artifacts and testing
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket',
                's3:CreateBucket',
                's3:DeleteBucket',
                's3:GetBucketEncryption',
                's3:GetBucketVersioning',
                's3:GetBucketPublicAccessBlock',
              ],
              resources: [
                this.artifactsBucket.bucketArn,
                `${this.artifactsBucket.bucketArn}/*`,
                'arn:aws:s3:::integration-test-*',
                'arn:aws:s3:::integration-test-*/*',
              ],
            }),
            // CloudFormation permissions for integration testing
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudformation:CreateStack',
                'cloudformation:UpdateStack',
                'cloudformation:DeleteStack',
                'cloudformation:DescribeStacks',
                'cloudformation:DescribeStackEvents',
                'cloudformation:DescribeStackResources',
                'cloudformation:ValidateTemplate',
                'cloudformation:GetTemplate',
              ],
              resources: [
                `arn:aws:cloudformation:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:stack/integration-test-*/*`,
              ],
            }),
            // CodeCommit permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'codecommit:GitPull',
                'codecommit:GetBranch',
                'codecommit:GetCommit',
                'codecommit:GetRepository',
                'codecommit:ListBranches',
                'codecommit:ListRepositories',
              ],
              resources: [this.repository.repositoryArn],
            }),
          ],
        }),
      },
    });

    // Create CodeBuild project for infrastructure testing
    this.buildProject = new codebuild.Project(this, 'InfrastructureTestingProject', {
      projectName: projectName,
      description: 'Automated testing for Infrastructure as Code templates',
      source: codebuild.Source.codeCommit({
        repository: this.repository,
        branchOrRef: 'main',
      }),
      environment: {
        buildImage: codebuild.LinuxBuildImage.AMAZON_LINUX_2_5,
        computeType: buildComputeType,
        privileged: false,
        environmentVariables: {
          AWS_DEFAULT_REGION: { value: cdk.Aws.REGION },
          AWS_ACCOUNT_ID: { value: cdk.Aws.ACCOUNT_ID },
          ARTIFACTS_BUCKET: { value: this.artifactsBucket.bucketName },
        },
      },
      artifacts: codebuild.Artifacts.s3({
        bucket: this.artifactsBucket,
        path: 'build-artifacts',
        packageZip: true,
      }),
      role: codeBuildRole,
      logging: {
        cloudWatch: {
          logGroup: buildLogGroup,
          enabled: enableDetailedMonitoring,
        },
      },
      buildSpec: codebuild.BuildSpec.fromObject({
        version: '0.2',
        phases: {
          install: {
            'runtime-versions': {
              python: '3.9',
              nodejs: '18',
            },
            commands: [
              'echo "Installing dependencies..."',
              'pip install --upgrade pip',
              'pip install -r tests/requirements.txt || echo "No requirements.txt found"',
              'npm install -g aws-cdk@latest || echo "CDK installation skipped"',
              'pip install awscli',
            ],
          },
          pre_build: {
            commands: [
              'echo "Pre-build phase started on `date`"',
              'echo "Validating AWS credentials..."',
              'aws sts get-caller-identity',
              'echo "Current working directory: $(pwd)"',
              'echo "Listing project files:"',
              'find . -type f -name "*.yaml" -o -name "*.yml" -o -name "*.py" -o -name "*.json" | head -20',
            ],
          },
          build: {
            commands: [
              'echo "Build phase started on `date`"',
              '',
              '# Run syntax validation',
              'echo "=== Running Syntax Validation ==="',
              'python -c "import yaml, json, os; [yaml.safe_load(open(f)) for f in os.listdir(\"templates\") if f.endswith((\".yaml\", \".yml\"))] if os.path.exists(\"templates\") else print(\"No templates directory found\")"',
              '',
              '# Run unit tests if available',
              'echo "=== Running Unit Tests ==="',
              'if [ -f "tests/test_s3_bucket.py" ]; then',
              '  cd tests && python -m pytest test_s3_bucket.py -v --tb=short',
              '  cd ..',
              'else',
              '  echo "No unit tests found, skipping..."',
              'fi',
              '',
              '# Run security tests',
              'echo "=== Running Security Tests ==="',
              'if [ -f "tests/security_test.py" ]; then',
              '  python tests/security_test.py',
              'else',
              '  echo "No security tests found, skipping..."',
              'fi',
              '',
              '# Run cost analysis',
              'echo "=== Running Cost Analysis ==="',
              'if [ -f "tests/cost_analysis.py" ]; then',
              '  python tests/cost_analysis.py',
              'else',
              '  echo "No cost analysis found, skipping..."',
              'fi',
              '',
              '# Run integration tests (with safety checks)',
              'echo "=== Running Integration Tests ==="',
              'if [ -f "tests/integration_test.py" ]; then',
              '  echo "Running integration tests with automatic cleanup..."',
              '  python tests/integration_test.py',
              'else',
              '  echo "No integration tests found, skipping..."',
              'fi',
              '',
              '# Generate test report',
              'echo "=== Generating Test Report ==="',
              'echo "Infrastructure Testing Report" > test-report.txt',
              'echo "Generated on: $(date)" >> test-report.txt',
              'echo "Project: ${CODEBUILD_PROJECT_NAME}" >> test-report.txt',
              'echo "Build ID: ${CODEBUILD_BUILD_ID}" >> test-report.txt',
              'echo "Region: ${AWS_DEFAULT_REGION}" >> test-report.txt',
              'echo "Account: ${AWS_ACCOUNT_ID}" >> test-report.txt',
            ],
          },
          post_build: {
            commands: [
              'echo "Post-build phase started on `date`"',
              'if [ $CODEBUILD_BUILD_SUCCEEDING -eq 1 ]; then',
              '  echo "✅ All infrastructure tests completed successfully!"',
              '  echo "SUCCESS: All validation checks passed" >> test-report.txt',
              'else',
              '  echo "❌ Infrastructure tests failed!"',
              '  echo "FAILURE: One or more validation checks failed" >> test-report.txt',
              'fi',
              '',
              '# Upload test report to S3',
              'aws s3 cp test-report.txt s3://${ARTIFACTS_BUCKET}/reports/test-report-${CODEBUILD_BUILD_ID}.txt',
              '',
              'echo "=== Build Summary ==="',
              'echo "Build Status: $([ $CODEBUILD_BUILD_SUCCEEDING -eq 1 ] && echo \"SUCCESS\" || echo \"FAILURE\")"',
              'echo "Build Duration: $((SECONDS/60)) minutes"',
              'echo "Artifacts uploaded to: s3://${ARTIFACTS_BUCKET}/"',
            ],
          },
        },
        artifacts: {
          files: [
            '**/*',
            'test-report.txt',
          ],
          'base-directory': '.',
        },
        reports: {
          'infrastructure-tests': {
            files: ['test-report.txt'],
            'file-format': 'SINGLETESTCASEJUNITXML',
          },
        },
      }),
      timeout: cdk.Duration.minutes(60),
    });

    // Create IAM role for CodePipeline
    const pipelineRole = new iam.Role(this, 'PipelineRole', {
      assumedBy: new iam.ServicePrincipal('codepipeline.amazonaws.com'),
      description: 'IAM role for Infrastructure Testing CodePipeline',
      inlinePolicies: {
        PipelinePolicy: new iam.PolicyDocument({
          statements: [
            // S3 permissions for artifacts
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:GetBucketVersioning',
                's3:ListBucket',
              ],
              resources: [
                this.artifactsBucket.bucketArn,
                `${this.artifactsBucket.bucketArn}/*`,
              ],
            }),
            // CodeCommit permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'codecommit:GetBranch',
                'codecommit:GetCommit',
                'codecommit:GetRepository',
                'codecommit:ListBranches',
                'codecommit:ListRepositories',
              ],
              resources: [this.repository.repositoryArn],
            }),
            // CodeBuild permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'codebuild:BatchGetBuilds',
                'codebuild:StartBuild',
              ],
              resources: [this.buildProject.projectArn],
            }),
          ],
        }),
      },
    });

    // Create source and build artifacts
    const sourceOutput = new codepipeline.Artifact('SourceOutput');
    const buildOutput = new codepipeline.Artifact('BuildOutput');

    // Create CodePipeline for end-to-end automation
    this.pipeline = new codepipeline.Pipeline(this, 'InfrastructureTestingPipeline', {
      pipelineName: `${projectName}-pipeline`,
      role: pipelineRole,
      artifactBucket: this.artifactsBucket,
      stages: [
        {
          stageName: 'Source',
          actions: [
            new codepipeline_actions.CodeCommitSourceAction({
              actionName: 'Source',
              repository: this.repository,
              branch: 'main',
              output: sourceOutput,
              trigger: codepipeline_actions.CodeCommitTrigger.EVENTS,
            }),
          ],
        },
        {
          stageName: 'Test',
          actions: [
            new codepipeline_actions.CodeBuildAction({
              actionName: 'RunInfrastructureTests',
              project: this.buildProject,
              input: sourceOutput,
              outputs: [buildOutput],
              environmentVariables: {
                PIPELINE_EXECUTION_ID: {
                  value: codepipeline_actions.CodeBuildAction.pipelineExecutionIdVariable(),
                },
              },
            }),
          ],
        },
      ],
      restartExecutionOnUpdate: true,
    });

    // Add tags to all resources for better organization and cost tracking
    const tags = {
      Project: projectName,
      Purpose: 'Infrastructure Testing',
      Environment: 'Development',
      ManagedBy: 'CDK',
    };

    Object.entries(tags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });

    // CloudFormation outputs for easy reference
    new cdk.CfnOutput(this, 'RepositoryCloneUrlHttp', {
      value: this.repository.repositoryCloneUrlHttp,
      description: 'HTTP clone URL for the CodeCommit repository',
      exportName: `${projectName}-repository-clone-url`,
    });

    new cdk.CfnOutput(this, 'ArtifactsBucketName', {
      value: this.artifactsBucket.bucketName,
      description: 'Name of the S3 bucket storing build artifacts',
      exportName: `${projectName}-artifacts-bucket`,
    });

    new cdk.CfnOutput(this, 'BuildProjectName', {
      value: this.buildProject.projectName,
      description: 'Name of the CodeBuild project for infrastructure testing',
      exportName: `${projectName}-build-project`,
    });

    new cdk.CfnOutput(this, 'PipelineName', {
      value: this.pipeline.pipelineName,
      description: 'Name of the CodePipeline for automated testing',
      exportName: `${projectName}-pipeline`,
    });

    new cdk.CfnOutput(this, 'PipelineConsoleUrl', {
      value: `https://console.aws.amazon.com/codesuite/codepipeline/pipelines/${this.pipeline.pipelineName}/view`,
      description: 'AWS Console URL for the CodePipeline',
    });

    new cdk.CfnOutput(this, 'BuildProjectConsoleUrl', {
      value: `https://console.aws.amazon.com/codesuite/codebuild/projects/${this.buildProject.projectName}`,
      description: 'AWS Console URL for the CodeBuild project',
    });
  }
}

/**
 * CDK App for Infrastructure Testing
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const projectName = app.node.tryGetContext('projectName') || process.env.PROJECT_NAME || 'iac-testing';
const repositoryName = app.node.tryGetContext('repositoryName') || process.env.REPOSITORY_NAME || 'iac-testing-repo';
const enableDetailedMonitoring = app.node.tryGetContext('enableDetailedMonitoring') !== 'false';

// Determine build compute type based on environment
const computeTypeString = app.node.tryGetContext('buildComputeType') || process.env.BUILD_COMPUTE_TYPE || 'SMALL';
const buildComputeType = {
  'SMALL': codebuild.ComputeType.SMALL,
  'MEDIUM': codebuild.ComputeType.MEDIUM,
  'LARGE': codebuild.ComputeType.LARGE,
}[computeTypeString.toUpperCase()] || codebuild.ComputeType.SMALL;

// Create the main stack
new InfrastructureTestingStack(app, 'InfrastructureTestingStack', {
  projectName,
  repositoryName,
  enableDetailedMonitoring,
  buildComputeType,
  description: 'Automated testing infrastructure for Infrastructure as Code templates and deployments',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

// Synthesize the app
app.synth();