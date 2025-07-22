#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as codebuild from 'aws-cdk-lib/aws-codebuild';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Properties for the Advanced CodeBuild Pipeline Stack
 */
interface AdvancedCodeBuildPipelineStackProps extends cdk.StackProps {
  /**
   * Unique identifier for resource naming
   */
  readonly resourceSuffix?: string;
  
  /**
   * Environment prefix for resource naming
   */
  readonly environmentName?: string;
  
  /**
   * ECR repository name for container images
   */
  readonly ecrRepositoryName?: string;
  
  /**
   * Enable detailed monitoring and analytics
   */
  readonly enableDetailedMonitoring?: boolean;
  
  /**
   * Cache retention period in days
   */
  readonly cacheRetentionDays?: number;
  
  /**
   * Artifact retention period in days
   */
  readonly artifactRetentionDays?: number;
}

/**
 * Advanced CodeBuild Pipeline Stack
 * 
 * This stack implements an enterprise-grade CI/CD pipeline using AWS CodeBuild
 * with multi-stage builds, intelligent caching, and comprehensive artifact management.
 * 
 * Features:
 * - Multi-stage build pipeline with dependency management
 * - Intelligent S3-based caching for dependencies and Docker layers
 * - ECR integration for container image management
 * - Lambda-based build orchestration and analytics
 * - CloudWatch monitoring and alerting
 * - Automated cache optimization and cleanup
 */
export class AdvancedCodeBuildPipelineStack extends cdk.Stack {
  
  /**
   * S3 bucket for build caching
   */
  public readonly cacheBucket: s3.Bucket;
  
  /**
   * S3 bucket for build artifacts
   */
  public readonly artifactBucket: s3.Bucket;
  
  /**
   * ECR repository for container images
   */
  public readonly ecrRepository: ecr.Repository;
  
  /**
   * IAM role for CodeBuild projects
   */
  public readonly buildRole: iam.Role;
  
  /**
   * CodeBuild project for dependency stage
   */
  public readonly dependencyBuildProject: codebuild.Project;
  
  /**
   * CodeBuild project for main build stage
   */
  public readonly mainBuildProject: codebuild.Project;
  
  /**
   * CodeBuild project for parallel builds
   */
  public readonly parallelBuildProject: codebuild.Project;
  
  /**
   * Lambda function for build orchestration
   */
  public readonly buildOrchestrator: lambda.Function;
  
  /**
   * Lambda function for cache management
   */
  public readonly cacheManager: lambda.Function;
  
  /**
   * Lambda function for build analytics
   */
  public readonly buildAnalytics: lambda.Function;
  
  /**
   * CloudWatch dashboard for monitoring
   */
  public readonly monitoringDashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: AdvancedCodeBuildPipelineStackProps = {}) {
    super(scope, id, props);

    // Set defaults for optional properties
    const resourceSuffix = props.resourceSuffix || this.generateRandomSuffix();
    const environmentName = props.environmentName || 'dev';
    const ecrRepositoryName = props.ecrRepositoryName || `app-repository-${resourceSuffix}`;
    const enableDetailedMonitoring = props.enableDetailedMonitoring ?? true;
    const cacheRetentionDays = props.cacheRetentionDays || 30;
    const artifactRetentionDays = props.artifactRetentionDays || 90;

    // Create S3 buckets for caching and artifacts
    this.cacheBucket = this.createCacheBucket(resourceSuffix, cacheRetentionDays);
    this.artifactBucket = this.createArtifactBucket(resourceSuffix, artifactRetentionDays);

    // Create ECR repository
    this.ecrRepository = this.createEcrRepository(ecrRepositoryName);

    // Create IAM role for CodeBuild
    this.buildRole = this.createBuildRole(resourceSuffix);

    // Create CodeBuild projects
    this.dependencyBuildProject = this.createDependencyBuildProject(resourceSuffix);
    this.mainBuildProject = this.createMainBuildProject(resourceSuffix);
    this.parallelBuildProject = this.createParallelBuildProject(resourceSuffix);

    // Create Lambda functions
    this.buildOrchestrator = this.createBuildOrchestrator(resourceSuffix);
    this.cacheManager = this.createCacheManager(resourceSuffix);
    this.buildAnalytics = this.createBuildAnalytics(resourceSuffix);

    // Create EventBridge rules for automation
    this.createEventBridgeRules(resourceSuffix);

    // Create monitoring dashboard
    if (enableDetailedMonitoring) {
      this.monitoringDashboard = this.createMonitoringDashboard(resourceSuffix);
    }

    // Create outputs
    this.createOutputs();

    // Tag all resources
    this.tagResources(environmentName);
  }

  /**
   * Generate a random suffix for resource naming
   */
  private generateRandomSuffix(): string {
    const timestamp = Date.now().toString(36);
    const random = Math.random().toString(36).substring(2, 8);
    return `${timestamp}${random}`.substring(0, 8);
  }

  /**
   * Create S3 bucket for build caching with lifecycle policies
   */
  private createCacheBucket(resourceSuffix: string, retentionDays: number): s3.Bucket {
    const bucket = new s3.Bucket(this, 'CacheBucket', {
      bucketName: `codebuild-cache-${resourceSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'CacheCleanup',
          enabled: true,
          prefix: 'cache/',
          expiration: cdk.Duration.days(retentionDays),
          noncurrentVersionExpiration: cdk.Duration.days(7),
        },
        {
          id: 'DependencyCache',
          enabled: true,
          prefix: 'deps/',
          expiration: cdk.Duration.days(retentionDays * 3), // Keep dependencies longer
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    return bucket;
  }

  /**
   * Create S3 bucket for build artifacts with encryption
   */
  private createArtifactBucket(resourceSuffix: string, retentionDays: number): s3.Bucket {
    const bucket = new s3.Bucket(this, 'ArtifactBucket', {
      bucketName: `build-artifacts-${resourceSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'ArtifactCleanup',
          enabled: true,
          expiration: cdk.Duration.days(retentionDays),
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    return bucket;
  }

  /**
   * Create ECR repository with lifecycle policies and vulnerability scanning
   */
  private createEcrRepository(repositoryName: string): ecr.Repository {
    const repository = new ecr.Repository(this, 'EcrRepository', {
      repositoryName: repositoryName,
      imageScanOnPush: true,
      encryption: ecr.RepositoryEncryption.AES_256,
      lifecycleRules: [
        {
          rulePriority: 1,
          description: 'Keep last 10 tagged images',
          tagStatus: ecr.TagStatus.TAGGED,
          maxImageCount: 10,
        },
        {
          rulePriority: 2,
          description: 'Delete untagged images after 1 day',
          tagStatus: ecr.TagStatus.UNTAGGED,
          maxImageAge: cdk.Duration.days(1),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    return repository;
  }

  /**
   * Create comprehensive IAM role for CodeBuild with necessary permissions
   */
  private createBuildRole(resourceSuffix: string): iam.Role {
    const role = new iam.Role(this, 'BuildRole', {
      roleName: `CodeBuildAdvancedRole-${resourceSuffix}`,
      assumedBy: new iam.ServicePrincipal('codebuild.amazonaws.com'),
      description: 'Advanced CodeBuild role with comprehensive permissions',
    });

    // CloudWatch Logs permissions
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
        'logs:PutLogEvents',
      ],
      resources: ['*'],
    }));

    // S3 permissions for cache and artifacts
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        's3:GetObject',
        's3:GetObjectVersion',
        's3:PutObject',
        's3:DeleteObject',
        's3:ListBucket',
      ],
      resources: [
        this.cacheBucket.bucketArn,
        `${this.cacheBucket.bucketArn}/*`,
        this.artifactBucket.bucketArn,
        `${this.artifactBucket.bucketArn}/*`,
      ],
    }));

    // ECR permissions
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'ecr:BatchCheckLayerAvailability',
        'ecr:GetDownloadUrlForLayer',
        'ecr:BatchGetImage',
        'ecr:GetAuthorizationToken',
        'ecr:PutImage',
        'ecr:InitiateLayerUpload',
        'ecr:UploadLayerPart',
        'ecr:CompleteLayerUpload',
      ],
      resources: ['*'],
    }));

    // CodeBuild permissions for cross-project coordination
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'codebuild:CreateReportGroup',
        'codebuild:CreateReport',
        'codebuild:UpdateReport',
        'codebuild:BatchPutTestCases',
        'codebuild:BatchPutCodeCoverages',
        'codebuild:StartBuild',
        'codebuild:BatchGetBuilds',
      ],
      resources: ['*'],
    }));

    // CloudWatch metrics permissions
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['cloudwatch:PutMetricData'],
      resources: ['*'],
    }));

    return role;
  }

  /**
   * Create dependency build project for package management and caching
   */
  private createDependencyBuildProject(resourceSuffix: string): codebuild.Project {
    const buildSpec = codebuild.BuildSpec.fromObject({
      version: '0.2',
      env: {
        variables: {
          CACHE_BUCKET: this.cacheBucket.bucketName,
          NODE_VERSION: '18',
          PYTHON_VERSION: '3.11',
        },
      },
      phases: {
        install: {
          'runtime-versions': {
            nodejs: '$NODE_VERSION',
            python: '$PYTHON_VERSION',
          },
          commands: [
            'echo "Installing build dependencies..."',
            'apt-get update && apt-get install -y jq curl',
            'pip install --upgrade pip',
            'npm install -g npm@latest',
          ],
        },
        pre_build: {
          commands: [
            'echo "Dependency stage started on $(date)"',
            'echo "Checking for cached dependencies..."',
            'if aws s3 ls s3://$CACHE_BUCKET/deps/package-lock.json; then aws s3 cp s3://$CACHE_BUCKET/deps/package-lock.json ./package-lock.json || true; fi',
            'if aws s3 ls s3://$CACHE_BUCKET/deps/requirements.txt; then aws s3 cp s3://$CACHE_BUCKET/deps/requirements.txt ./requirements.txt || true; fi',
          ],
        },
        build: {
          commands: [
            'echo "Installing Node.js dependencies..."',
            'if [ -f "package.json" ]; then npm ci --cache /tmp/npm-cache && tar -czf node_modules.tar.gz node_modules/ && aws s3 cp node_modules.tar.gz s3://$CACHE_BUCKET/deps/node_modules-$(date +%Y%m%d).tar.gz; fi',
            'echo "Installing Python dependencies..."',
            'if [ -f "requirements.txt" ]; then pip install -r requirements.txt --cache-dir /tmp/pip-cache && tar -czf python_packages.tar.gz $(python -c "import site; print(site.getsitepackages()[0])") && aws s3 cp python_packages.tar.gz s3://$CACHE_BUCKET/deps/python-packages-$(date +%Y%m%d).tar.gz; fi',
          ],
        },
        post_build: {
          commands: [
            'echo "Dependency installation completed"',
            'if [ -f "package-lock.json" ]; then aws s3 cp package-lock.json s3://$CACHE_BUCKET/deps/package-lock.json; fi',
            'if [ -f "requirements.txt" ]; then aws s3 cp requirements.txt s3://$CACHE_BUCKET/deps/requirements.txt; fi',
          ],
        },
      },
      cache: {
        paths: [
          '/tmp/npm-cache/**/*',
          '/tmp/pip-cache/**/*',
          'node_modules/**/*',
        ],
      },
      artifacts: {
        files: ['**/*'],
        name: 'dependencies-$(date +%Y-%m-%d)',
      },
    });

    const project = new codebuild.Project(this, 'DependencyBuildProject', {
      projectName: `advanced-build-${resourceSuffix}-dependencies`,
      description: 'Dependency installation and caching stage',
      role: this.buildRole,
      environment: {
        buildImage: codebuild.LinuxBuildImage.AMAZON_LINUX_2_4,
        computeType: codebuild.ComputeType.MEDIUM,
        privileged: false,
      },
      buildSpec: buildSpec,
      cache: codebuild.Cache.bucket(this.cacheBucket, {
        prefix: 'dependency-cache',
      }),
      timeout: cdk.Duration.minutes(30),
      logging: {
        cloudWatch: {
          logGroup: new logs.LogGroup(this, 'DependencyBuildLogGroup', {
            logGroupName: `/aws/codebuild/advanced-build-${resourceSuffix}-dependencies`,
            retention: logs.RetentionDays.TWO_WEEKS,
            removalPolicy: cdk.RemovalPolicy.DESTROY,
          }),
        },
      },
    });

    return project;
  }

  /**
   * Create main build project with testing, quality checks, and Docker builds
   */
  private createMainBuildProject(resourceSuffix: string): codebuild.Project {
    const buildSpec = codebuild.BuildSpec.fromObject({
      version: '0.2',
      env: {
        variables: {
          CACHE_BUCKET: this.cacheBucket.bucketName,
          ARTIFACT_BUCKET: this.artifactBucket.bucketName,
          ECR_URI: this.ecrRepository.repositoryUri,
          IMAGE_TAG: 'latest',
          DOCKER_BUILDKIT: '1',
        },
      },
      phases: {
        install: {
          'runtime-versions': {
            docker: 20,
            nodejs: 18,
            python: '3.11',
          },
          commands: [
            'echo "Installing build tools..."',
            'apt-get update && apt-get install -y jq curl git',
            'pip install --upgrade pip pytest pytest-cov black pylint bandit',
            'npm install -g eslint prettier jest',
          ],
        },
        pre_build: {
          commands: [
            'echo "Main build stage started on $(date)"',
            'echo "Logging in to Amazon ECR..."',
            'aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $ECR_URI',
            'export COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)',
            'export IMAGE_TAG=${COMMIT_HASH:-latest}',
            'echo "Image will be tagged as $IMAGE_TAG"',
            'echo "Restoring cached dependencies..."',
            'if aws s3 ls s3://$CACHE_BUCKET/deps/node_modules-$(date +%Y%m%d).tar.gz; then aws s3 cp s3://$CACHE_BUCKET/deps/node_modules-$(date +%Y%m%d).tar.gz ./node_modules.tar.gz && tar -xzf node_modules.tar.gz; fi',
          ],
        },
        build: {
          commands: [
            'echo "Build started on $(date)"',
            'echo "Running code quality checks..."',
            'if [ -f "package.json" ]; then npx eslint src/ --ext .js,.jsx,.ts,.tsx --format json > eslint-report.json || true && npx prettier --check src/ || true; fi',
            'if [ -f "requirements.txt" ]; then find . -name "*.py" -exec pylint {} \\; > pylint-report.txt || true && black --check . || true && bandit -r . -f json -o bandit-report.json || true; fi',
            'echo "Running tests..."',
            'if [ -f "package.json" ] && grep -q \'"test"\' package.json; then npm test -- --coverage --coverageReporters=json > test-results.json; fi',
            'if [ -f "requirements.txt" ] && find . -name "test_*.py" | head -1; then pytest --cov=. --cov-report=json --cov-report=xml --junit-xml=test-results.xml; fi',
            'echo "Building application..."',
            'if [ -f "Dockerfile" ]; then docker build --cache-from $ECR_URI:latest --build-arg BUILDKIT_INLINE_CACHE=1 -t $ECR_URI:$IMAGE_TAG -t $ECR_URI:latest .; fi',
            'if [ -f "package.json" ] && grep -q \'"build"\' package.json; then npm run build; fi',
            'if [ -f "setup.py" ]; then python setup.py bdist_wheel; fi',
          ],
        },
        post_build: {
          commands: [
            'echo "Build completed on $(date)"',
            'if [ -f "Dockerfile" ]; then docker push $ECR_URI:$IMAGE_TAG && docker push $ECR_URI:latest; fi',
            'echo "Uploading build artifacts..."',
            'if [ -d "build" ] || [ -d "dist" ]; then tar -czf app-artifacts-$IMAGE_TAG.tar.gz build/ dist/ || tar -czf app-artifacts-$IMAGE_TAG.tar.gz build/ || tar -czf app-artifacts-$IMAGE_TAG.tar.gz dist/ && aws s3 cp app-artifacts-$IMAGE_TAG.tar.gz s3://$ARTIFACT_BUCKET/artifacts/; fi',
            'if [ -f "test-results.json" ] || [ -f "test-results.xml" ]; then aws s3 cp test-results.* s3://$ARTIFACT_BUCKET/reports/tests/ || true; fi',
            'if [ -f "eslint-report.json" ] || [ -f "pylint-report.txt" ]; then aws s3 cp *lint-report.* s3://$ARTIFACT_BUCKET/reports/quality/ || true; fi',
          ],
        },
      },
      reports: {
        test_reports: {
          files: ['test-results.xml', 'test-results.json'],
          'file-format': 'JUNITXML',
        },
        code_coverage: {
          files: ['coverage.xml', 'coverage.json'],
          'file-format': 'COBERTURAXML',
        },
      },
      cache: {
        paths: [
          '/root/.npm/**/*',
          '/root/.cache/**/*',
          'node_modules/**/*',
          '/var/lib/docker/**/*',
        ],
      },
      artifacts: {
        files: ['**/*'],
        name: 'main-build-$(date +%Y-%m-%d)',
      },
    });

    const project = new codebuild.Project(this, 'MainBuildProject', {
      projectName: `advanced-build-${resourceSuffix}-main`,
      description: 'Main build stage with testing and quality checks',
      role: this.buildRole,
      environment: {
        buildImage: codebuild.LinuxBuildImage.AMAZON_LINUX_2_4,
        computeType: codebuild.ComputeType.LARGE,
        privileged: true, // Required for Docker builds
      },
      buildSpec: buildSpec,
      cache: codebuild.Cache.bucket(this.cacheBucket, {
        prefix: 'main-cache',
      }),
      timeout: cdk.Duration.minutes(60),
      logging: {
        cloudWatch: {
          logGroup: new logs.LogGroup(this, 'MainBuildLogGroup', {
            logGroupName: `/aws/codebuild/advanced-build-${resourceSuffix}-main`,
            retention: logs.RetentionDays.TWO_WEEKS,
            removalPolicy: cdk.RemovalPolicy.DESTROY,
          }),
        },
      },
    });

    return project;
  }

  /**
   * Create parallel build project for multi-architecture builds
   */
  private createParallelBuildProject(resourceSuffix: string): codebuild.Project {
    const buildSpec = codebuild.BuildSpec.fromObject({
      version: '0.2',
      env: {
        variables: {
          CACHE_BUCKET: this.cacheBucket.bucketName,
          ECR_URI: this.ecrRepository.repositoryUri,
          TARGET_ARCH: 'amd64',
        },
      },
      phases: {
        install: {
          'runtime-versions': {
            docker: 20,
          },
          commands: [
            'echo "Installing Docker buildx for multi-architecture builds..."',
            'docker buildx create --use --name multiarch-builder',
            'docker buildx inspect --bootstrap',
          ],
        },
        pre_build: {
          commands: [
            'echo "Parallel build for $TARGET_ARCH started on $(date)"',
            'aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $ECR_URI',
            'export COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)',
            'export IMAGE_TAG=${COMMIT_HASH:-latest}-$TARGET_ARCH',
          ],
        },
        build: {
          commands: [
            'echo "Building for architecture: $TARGET_ARCH"',
            'if [ -f "Dockerfile" ]; then docker buildx build --platform linux/$TARGET_ARCH --cache-from $ECR_URI:cache-$TARGET_ARCH --cache-to type=registry,ref=$ECR_URI:cache-$TARGET_ARCH,mode=max -t $ECR_URI:$IMAGE_TAG --push .; fi',
          ],
        },
        post_build: {
          commands: [
            'echo "Parallel build for $TARGET_ARCH completed on $(date)"',
            'echo "Image: $ECR_URI:$IMAGE_TAG"',
          ],
        },
      },
      artifacts: {
        files: ['**/*'],
        name: 'parallel-build-$TARGET_ARCH-$(date +%Y-%m-%d)',
      },
    });

    const project = new codebuild.Project(this, 'ParallelBuildProject', {
      projectName: `advanced-build-${resourceSuffix}-parallel`,
      description: 'Parallel build for multiple architectures',
      role: this.buildRole,
      environment: {
        buildImage: codebuild.LinuxBuildImage.AMAZON_LINUX_2_4,
        computeType: codebuild.ComputeType.MEDIUM,
        privileged: true, // Required for Docker builds
      },
      buildSpec: buildSpec,
      cache: codebuild.Cache.bucket(this.cacheBucket, {
        prefix: 'parallel-cache',
      }),
      timeout: cdk.Duration.minutes(45),
      logging: {
        cloudWatch: {
          logGroup: new logs.LogGroup(this, 'ParallelBuildLogGroup', {
            logGroupName: `/aws/codebuild/advanced-build-${resourceSuffix}-parallel`,
            retention: logs.RetentionDays.TWO_WEEKS,
            removalPolicy: cdk.RemovalPolicy.DESTROY,
          }),
        },
      },
    });

    return project;
  }

  /**
   * Create Lambda function for build orchestration
   */
  private createBuildOrchestrator(resourceSuffix: string): lambda.Function {
    const orchestratorFunction = new lambda.Function(this, 'BuildOrchestrator', {
      functionName: `advanced-build-${resourceSuffix}-orchestrator`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime
import time

logger = logging.getLogger()
logger.setLevel(logging.INFO)

codebuild = boto3.client('codebuild')
s3 = boto3.client('s3')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """Orchestrate multi-stage CodeBuild pipeline"""
    try:
        logger.info(f"Build orchestration started: {json.dumps(event)}")
        
        build_config = event.get('buildConfig', {})
        source_location = build_config.get('sourceLocation')
        parallel_builds = build_config.get('parallelBuilds', ['amd64'])
        
        if not source_location:
            return {'statusCode': 400, 'body': 'Source location required'}
        
        pipeline_result = execute_build_pipeline(source_location, parallel_builds)
        record_pipeline_metrics(pipeline_result)
        
        return {
            'statusCode': 200,
            'body': json.dumps(pipeline_result, default=str)
        }
        
    except Exception as e:
        logger.error(f"Error in build orchestration: {str(e)}")
        return {'statusCode': 500, 'body': f'Error: {str(e)}'}

def execute_build_pipeline(source_location, parallel_builds):
    """Execute the complete build pipeline"""
    pipeline_id = f"pipeline-{int(time.time())}"
    results = {
        'pipelineId': pipeline_id,
        'startTime': datetime.utcnow().isoformat(),
        'stages': {}
    }
    
    try:
        # Stage 1: Dependencies
        logger.info("Starting dependency stage...")
        dep_result = start_build_stage('dependencies', source_location)
        results['stages']['dependencies'] = dep_result
        
        # Stage 2: Main Build
        logger.info("Starting main build stage...")
        main_result = start_build_stage('main', source_location)
        results['stages']['main'] = main_result
        
        # Stage 3: Parallel Builds
        logger.info("Starting parallel build stages...")
        parallel_results = []
        for arch in parallel_builds:
            parallel_result = start_build_stage('parallel', source_location, {'TARGET_ARCH': arch})
            parallel_results.append(parallel_result)
        results['stages']['parallel'] = parallel_results
        
        results['overallStatus'] = 'SUCCEEDED'
        results['endTime'] = datetime.utcnow().isoformat()
        
        return results
        
    except Exception as e:
        logger.error(f"Pipeline execution failed: {str(e)}")
        results['overallStatus'] = 'FAILED'
        results['error'] = str(e)
        results['endTime'] = datetime.utcnow().isoformat()
        return results

def start_build_stage(stage, source_location, env_overrides=None):
    """Start a specific build stage"""
    import os
    
    project_mapping = {
        'dependencies': os.environ['DEPENDENCY_BUILD_PROJECT'],
        'main': os.environ['MAIN_BUILD_PROJECT'],
        'parallel': os.environ['PARALLEL_BUILD_PROJECT']
    }
    
    project_name = project_mapping.get(stage)
    if not project_name:
        raise ValueError(f"Unknown build stage: {stage}")
    
    try:
        env_vars = [
            {'name': 'CACHE_BUCKET', 'value': os.environ['CACHE_BUCKET']},
            {'name': 'ARTIFACT_BUCKET', 'value': os.environ['ARTIFACT_BUCKET']},
            {'name': 'ECR_URI', 'value': os.environ['ECR_URI']}
        ]
        
        if env_overrides:
            for key, value in env_overrides.items():
                env_vars.append({'name': key, 'value': value})
        
        response = codebuild.start_build(
            projectName=project_name,
            sourceLocationOverride=source_location,
            environmentVariablesOverride=env_vars
        )
        
        build_id = response['build']['id']
        logger.info(f"Started {stage} build: {build_id}")
        
        return {
            'stage': stage,
            'buildId': build_id,
            'status': 'IN_PROGRESS',
            'startTime': datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Error starting {stage} build: {str(e)}")
        return {
            'stage': stage,
            'status': 'FAILED',
            'error': str(e)
        }

def record_pipeline_metrics(results):
    """Record pipeline metrics to CloudWatch"""
    try:
        metrics = [{
            'MetricName': 'PipelineExecutions',
            'Value': 1,
            'Unit': 'Count',
            'Dimensions': [{'Name': 'Status', 'Value': results['overallStatus']}]
        }]
        
        cloudwatch.put_metric_data(
            Namespace='CodeBuild/AdvancedPipeline',
            MetricData=metrics
        )
        
    except Exception as e:
        logger.error(f"Error recording metrics: {str(e)}")
`),
      timeout: cdk.Duration.minutes(15),
      memorySize: 512,
      environment: {
        DEPENDENCY_BUILD_PROJECT: this.dependencyBuildProject.projectName,
        MAIN_BUILD_PROJECT: this.mainBuildProject.projectName,
        PARALLEL_BUILD_PROJECT: this.parallelBuildProject.projectName,
        CACHE_BUCKET: this.cacheBucket.bucketName,
        ARTIFACT_BUCKET: this.artifactBucket.bucketName,
        ECR_URI: this.ecrRepository.repositoryUri,
      },
      description: 'Orchestrate multi-stage CodeBuild pipeline',
    });

    // Grant permissions to start builds
    orchestratorFunction.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'codebuild:StartBuild',
        'codebuild:BatchGetBuilds',
      ],
      resources: [
        this.dependencyBuildProject.projectArn,
        this.mainBuildProject.projectArn,
        this.parallelBuildProject.projectArn,
      ],
    }));

    // Grant CloudWatch permissions
    orchestratorFunction.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['cloudwatch:PutMetricData'],
      resources: ['*'],
    }));

    return orchestratorFunction;
  }

  /**
   * Create Lambda function for cache management and optimization
   */
  private createCacheManager(resourceSuffix: string): lambda.Function {
    const cacheManagerFunction = new lambda.Function(this, 'CacheManager', {
      functionName: `advanced-build-${resourceSuffix}-cache-manager`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')

def lambda_handler(event, context):
    """Manage build caches and optimization"""
    try:
        import os
        cache_bucket = event.get('cacheBucket', os.environ.get('CACHE_BUCKET'))
        if not cache_bucket:
            return {'statusCode': 400, 'body': 'Cache bucket not specified'}
        
        optimization_results = optimize_cache(cache_bucket)
        
        return {
            'statusCode': 200,
            'body': json.dumps(optimization_results, default=str)
        }
        
    except Exception as e:
        logger.error(f"Error in cache management: {str(e)}")
        return {'statusCode': 500, 'body': f'Error: {str(e)}'}

def optimize_cache(bucket_name):
    """Optimize cache storage and remove stale entries"""
    results = {
        'bucket': bucket_name,
        'optimization_date': datetime.utcnow().isoformat(),
        'actions': []
    }
    
    try:
        paginator = s3.get_paginator('list_objects_v2')
        
        for page in paginator.paginate(Bucket=bucket_name):
            if 'Contents' not in page:
                continue
            
            for obj in page['Contents']:
                key = obj['Key']
                last_modified = obj['LastModified']
                size = obj['Size']
                
                if is_cache_stale(key, last_modified):
                    s3.delete_object(Bucket=bucket_name, Key=key)
                    results['actions'].append({
                        'action': 'deleted',
                        'key': key,
                        'reason': 'stale_cache',
                        'size': size
                    })
        
        deleted_count = len([a for a in results['actions'] if a['action'] == 'deleted'])
        total_size_freed = sum(a['size'] for a in results['actions'] if a['action'] == 'deleted')
        
        results['summary'] = {
            'deleted_entries': deleted_count,
            'size_freed_bytes': total_size_freed,
            'total_actions': len(results['actions'])
        }
        
        logger.info(f"Cache optimization completed: {results['summary']}")
        return results
        
    except Exception as e:
        logger.error(f"Error optimizing cache: {str(e)}")
        results['error'] = str(e)
        return results

def is_cache_stale(key, last_modified):
    """Check if cache entry is stale"""
    staleness_rules = {
        'deps/node_modules': 30,
        'deps/python-packages': 30,
        'cache/docker': 14,
        'cache/build': 7,
    }
    
    max_age_days = 14  # default
    for prefix, age in staleness_rules.items():
        if key.startswith(prefix):
            max_age_days = age
            break
    
    threshold_date = datetime.utcnow() - timedelta(days=max_age_days)
    
    if last_modified.tzinfo:
        last_modified = last_modified.replace(tzinfo=None)
    
    return last_modified < threshold_date
`),
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      environment: {
        CACHE_BUCKET: this.cacheBucket.bucketName,
      },
      description: 'Manage and optimize CodeBuild caches',
    });

    // Grant S3 permissions for cache management
    this.cacheBucket.grantReadWrite(cacheManagerFunction);

    return cacheManagerFunction;
  }

  /**
   * Create Lambda function for build analytics and reporting
   */
  private createBuildAnalytics(resourceSuffix: string): lambda.Function {
    const analyticsFunction = new lambda.Function(this, 'BuildAnalytics', {
      functionName: `advanced-build-${resourceSuffix}-analytics`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime, timedelta
import statistics

logger = logging.getLogger()
logger.setLevel(logging.INFO)

codebuild = boto3.client('codebuild')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """Generate build analytics and performance reports"""
    try:
        import os
        
        analysis_period = event.get('analysisPeriod', 7)
        project_names = event.get('projectNames', [
            os.environ['DEPENDENCY_BUILD_PROJECT'],
            os.environ['MAIN_BUILD_PROJECT'],
            os.environ['PARALLEL_BUILD_PROJECT']
        ])
        
        analytics_report = generate_analytics_report(project_names, analysis_period)
        store_analytics_report(analytics_report)
        
        return {
            'statusCode': 200,
            'body': json.dumps(analytics_report, default=str)
        }
        
    except Exception as e:
        logger.error(f"Error generating analytics: {str(e)}")
        return {'statusCode': 500, 'body': f'Error: {str(e)}'}

def generate_analytics_report(project_names, analysis_period):
    """Generate comprehensive build analytics report"""
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(days=analysis_period)
    
    report = {
        'report_id': f"analytics-{int(end_time.timestamp())}",
        'generated_at': end_time.isoformat(),
        'analysis_period': f"{analysis_period} days",
        'projects': {},
        'summary': {}
    }
    
    all_builds = []
    total_builds = 0
    successful_builds = 0
    
    for project_name in project_names:
        try:
            project_analytics = analyze_project(project_name, start_time, end_time)
            report['projects'][project_name] = project_analytics
            
            all_builds.extend(project_analytics.get('builds', []))
            total_builds += project_analytics.get('total_builds', 0)
            successful_builds += project_analytics.get('successful_builds', 0)
            
        except Exception as e:
            logger.error(f"Error analyzing project {project_name}: {str(e)}")
            report['projects'][project_name] = {'error': str(e)}
    
    report['summary'] = generate_summary_statistics(all_builds, total_builds, successful_builds)
    return report

def analyze_project(project_name, start_time, end_time):
    """Analyze builds for a specific project"""
    project_data = {
        'project_name': project_name,
        'builds': [],
        'total_builds': 0,
        'successful_builds': 0,
        'failed_builds': 0,
        'average_duration': 0
    }
    
    try:
        builds_response = codebuild.list_builds_for_project(
            projectName=project_name,
            sortOrder='DESCENDING'
        )
        
        build_ids = builds_response.get('ids', [])
        if not build_ids:
            return project_data
        
        builds_detail = codebuild.batch_get_builds(ids=build_ids)
        builds = builds_detail.get('builds', [])
        
        filtered_builds = []
        for build in builds:
            build_start = build.get('startTime')
            if build_start and start_time <= build_start <= end_time:
                filtered_builds.append(build)
        
        durations = []
        
        for build in filtered_builds:
            build_status = build.get('buildStatus')
            build_duration = 0
            
            if build.get('startTime') and build.get('endTime'):
                duration = (build['endTime'] - build['startTime']).total_seconds()
                build_duration = duration
                durations.append(duration)
            
            if build_status == 'SUCCEEDED':
                project_data['successful_builds'] += 1
            else:
                project_data['failed_builds'] += 1
            
            project_data['builds'].append({
                'build_id': build.get('id'),
                'status': build_status,
                'duration': build_duration,
                'start_time': build.get('startTime').isoformat() if build.get('startTime') else None,
                'end_time': build.get('endTime').isoformat() if build.get('endTime') else None
            })
        
        project_data['total_builds'] = len(filtered_builds)
        project_data['average_duration'] = statistics.mean(durations) if durations else 0
        
        return project_data
        
    except Exception as e:
        logger.error(f"Error analyzing project {project_name}: {str(e)}")
        project_data['error'] = str(e)
        return project_data

def generate_summary_statistics(all_builds, total_builds, successful_builds):
    """Generate overall summary statistics"""
    try:
        success_rate = (successful_builds / total_builds) if total_builds > 0 else 0
        
        durations = [b['duration'] for b in all_builds if b['duration'] > 0]
        duration_stats = {}
        if durations:
            duration_stats = {
                'mean': statistics.mean(durations),
                'median': statistics.median(durations),
                'min': min(durations),
                'max': max(durations)
            }
        
        return {
            'total_builds': total_builds,
            'successful_builds': successful_builds,
            'failed_builds': total_builds - successful_builds,
            'success_rate': success_rate,
            'duration_statistics': duration_stats
        }
        
    except Exception as e:
        logger.error(f"Error generating summary: {str(e)}")
        return {'error': str(e)}

def store_analytics_report(report):
    """Store analytics report in S3"""
    try:
        import os
        bucket = os.environ['ARTIFACT_BUCKET']
        key = f"analytics/build-analytics-{report['report_id']}.json"
        
        s3.put_object(
            Bucket=bucket,
            Key=key,
            Body=json.dumps(report, indent=2, default=str),
            ContentType='application/json'
        )
        
        logger.info(f"Analytics report stored: s3://{bucket}/{key}")
        
    except Exception as e:
        logger.error(f"Error storing analytics report: {str(e)}")
`),
      timeout: cdk.Duration.minutes(15),
      memorySize: 512,
      environment: {
        DEPENDENCY_BUILD_PROJECT: this.dependencyBuildProject.projectName,
        MAIN_BUILD_PROJECT: this.mainBuildProject.projectName,
        PARALLEL_BUILD_PROJECT: this.parallelBuildProject.projectName,
        ARTIFACT_BUCKET: this.artifactBucket.bucketName,
      },
      description: 'Generate build analytics and performance reports',
    });

    // Grant permissions to access CodeBuild projects
    analyticsFunction.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'codebuild:ListBuildsForProject',
        'codebuild:BatchGetBuilds',
      ],
      resources: [
        this.dependencyBuildProject.projectArn,
        this.mainBuildProject.projectArn,
        this.parallelBuildProject.projectArn,
      ],
    }));

    // Grant S3 permissions for storing reports
    this.artifactBucket.grantWrite(analyticsFunction);

    return analyticsFunction;
  }

  /**
   * Create EventBridge rules for automation
   */
  private createEventBridgeRules(resourceSuffix: string): void {
    // Daily cache optimization
    const cacheOptimizationRule = new events.Rule(this, 'CacheOptimizationRule', {
      ruleName: `cache-optimization-${resourceSuffix}`,
      description: 'Daily cache optimization',
      schedule: events.Schedule.rate(cdk.Duration.days(1)),
    });

    cacheOptimizationRule.addTarget(new targets.LambdaFunction(this.cacheManager));

    // Weekly analytics report
    const analyticsRule = new events.Rule(this, 'BuildAnalyticsRule', {
      ruleName: `build-analytics-${resourceSuffix}`,
      description: 'Weekly build analytics report',
      schedule: events.Schedule.rate(cdk.Duration.days(7)),
    });

    analyticsRule.addTarget(new targets.LambdaFunction(this.buildAnalytics));
  }

  /**
   * Create CloudWatch monitoring dashboard
   */
  private createMonitoringDashboard(resourceSuffix: string): cloudwatch.Dashboard {
    const dashboard = new cloudwatch.Dashboard(this, 'MonitoringDashboard', {
      dashboardName: `Advanced-CodeBuild-${resourceSuffix}`,
    });

    // Pipeline execution metrics
    const pipelineExecutionWidget = new cloudwatch.GraphWidget({
      title: 'Pipeline Execution Results',
      left: [
        new cloudwatch.Metric({
          namespace: 'CodeBuild/AdvancedPipeline',
          metricName: 'PipelineExecutions',
          dimensionsMap: { Status: 'SUCCEEDED' },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
        new cloudwatch.Metric({
          namespace: 'CodeBuild/AdvancedPipeline',
          metricName: 'PipelineExecutions',
          dimensionsMap: { Status: 'FAILED' },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
      ],
    });

    // Build duration metrics
    const buildDurationWidget = new cloudwatch.GraphWidget({
      title: 'Build Duration by Project',
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/CodeBuild',
          metricName: 'Duration',
          dimensionsMap: { ProjectName: this.dependencyBuildProject.projectName },
          statistic: 'Average',
          period: cdk.Duration.minutes(5),
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/CodeBuild',
          metricName: 'Duration',
          dimensionsMap: { ProjectName: this.mainBuildProject.projectName },
          statistic: 'Average',
          period: cdk.Duration.minutes(5),
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/CodeBuild',
          metricName: 'Duration',
          dimensionsMap: { ProjectName: this.parallelBuildProject.projectName },
          statistic: 'Average',
          period: cdk.Duration.minutes(5),
        }),
      ],
    });

    // Storage usage metrics
    const storageWidget = new cloudwatch.GraphWidget({
      title: 'Storage Usage (Cache and Artifacts)',
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/S3',
          metricName: 'BucketSizeBytes',
          dimensionsMap: {
            BucketName: this.cacheBucket.bucketName,
            StorageType: 'StandardStorage',
          },
          statistic: 'Average',
          period: cdk.Duration.days(1),
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/S3',
          metricName: 'BucketSizeBytes',
          dimensionsMap: {
            BucketName: this.artifactBucket.bucketName,
            StorageType: 'StandardStorage',
          },
          statistic: 'Average',
          period: cdk.Duration.days(1),
        }),
      ],
    });

    // Lambda function metrics
    const lambdaWidget = new cloudwatch.GraphWidget({
      title: 'Lambda Function Performance',
      left: [
        this.buildOrchestrator.metricDuration({ period: cdk.Duration.minutes(5) }),
        this.cacheManager.metricDuration({ period: cdk.Duration.minutes(5) }),
        this.buildAnalytics.metricDuration({ period: cdk.Duration.minutes(5) }),
      ],
      right: [
        this.buildOrchestrator.metricErrors({ period: cdk.Duration.minutes(5) }),
        this.cacheManager.metricErrors({ period: cdk.Duration.minutes(5) }),
        this.buildAnalytics.metricErrors({ period: cdk.Duration.minutes(5) }),
      ],
    });

    dashboard.addWidgets(
      pipelineExecutionWidget,
      buildDurationWidget,
      storageWidget,
      lambdaWidget
    );

    return dashboard;
  }

  /**
   * Create stack outputs
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'CacheBucketName', {
      value: this.cacheBucket.bucketName,
      description: 'S3 bucket for build caching',
      exportName: `${this.stackName}-CacheBucket`,
    });

    new cdk.CfnOutput(this, 'ArtifactBucketName', {
      value: this.artifactBucket.bucketName,
      description: 'S3 bucket for build artifacts',
      exportName: `${this.stackName}-ArtifactBucket`,
    });

    new cdk.CfnOutput(this, 'EcrRepositoryUri', {
      value: this.ecrRepository.repositoryUri,
      description: 'ECR repository URI for container images',
      exportName: `${this.stackName}-EcrRepository`,
    });

    new cdk.CfnOutput(this, 'DependencyBuildProject', {
      value: this.dependencyBuildProject.projectName,
      description: 'CodeBuild project for dependency stage',
      exportName: `${this.stackName}-DependencyProject`,
    });

    new cdk.CfnOutput(this, 'MainBuildProject', {
      value: this.mainBuildProject.projectName,
      description: 'CodeBuild project for main build stage',
      exportName: `${this.stackName}-MainProject`,
    });

    new cdk.CfnOutput(this, 'ParallelBuildProject', {
      value: this.parallelBuildProject.projectName,
      description: 'CodeBuild project for parallel builds',
      exportName: `${this.stackName}-ParallelProject`,
    });

    new cdk.CfnOutput(this, 'BuildOrchestratorFunction', {
      value: this.buildOrchestrator.functionName,
      description: 'Lambda function for build orchestration',
      exportName: `${this.stackName}-Orchestrator`,
    });

    new cdk.CfnOutput(this, 'MonitoringDashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=Advanced-CodeBuild-${this.stackName}`,
      description: 'CloudWatch dashboard URL for monitoring',
    });
  }

  /**
   * Tag all resources with common tags
   */
  private tagResources(environmentName: string): void {
    cdk.Tags.of(this).add('Project', 'AdvancedCodeBuildPipeline');
    cdk.Tags.of(this).add('Environment', environmentName);
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
    cdk.Tags.of(this).add('CostCenter', 'DevOps');
  }
}

/**
 * CDK Application
 */
const app = new cdk.App();

// Get context parameters
const resourceSuffix = app.node.tryGetContext('resourceSuffix');
const environmentName = app.node.tryGetContext('environment') || 'dev';
const ecrRepositoryName = app.node.tryGetContext('ecrRepositoryName');
const enableDetailedMonitoring = app.node.tryGetContext('enableDetailedMonitoring') !== 'false';

new AdvancedCodeBuildPipelineStack(app, 'AdvancedCodeBuildPipelineStack', {
  resourceSuffix,
  environmentName,
  ecrRepositoryName,
  enableDetailedMonitoring,
  
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  description: 'Advanced CodeBuild Pipeline with multi-stage builds, caching, and artifacts management',
  
  tags: {
    Project: 'AdvancedCodeBuildPipeline',
    Environment: environmentName,
    ManagedBy: 'CDK',
  },
});

app.synth();