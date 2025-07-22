"""
Pipeline Stack for Advanced CodeBuild Pipeline

This stack creates the core pipeline infrastructure:
- Multiple CodeBuild projects for different stages
- Build orchestration Lambda function
- Cache management Lambda function
- EventBridge rules for automation
- Build specifications and configurations
"""

from typing import Dict, List, Optional, Any

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    Stack,
    aws_codebuild as codebuild,
    aws_events as events,
    aws_events_targets as targets,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_logs as logs,
)
from constructs import Construct

from .storage_stack import StorageStack


class AdvancedCodeBuildPipelineStack(Stack):
    """
    Stack containing the core pipeline infrastructure
    
    This stack creates:
    - CodeBuild projects for different pipeline stages
    - Lambda functions for orchestration and cache management
    - EventBridge rules for automation
    - CloudWatch log groups for monitoring
    """
    
    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        storage_stack: StorageStack,
        project_name: str,
        environment: str,
        enable_parallel_builds: bool = True,
        enable_security_scanning: bool = True,
        build_compute_type: str = "BUILD_GENERAL1_LARGE",
        parallel_architectures: List[str] = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        self.storage_stack = storage_stack
        self.project_name = project_name
        self.environment = environment
        self.enable_parallel_builds = enable_parallel_builds
        self.enable_security_scanning = enable_security_scanning
        
        if parallel_architectures is None:
            parallel_architectures = ["amd64", "arm64"]
        self.parallel_architectures = parallel_architectures
        
        # Parse compute type
        self.build_compute_type = getattr(codebuild.ComputeType, build_compute_type, codebuild.ComputeType.BUILD_GENERAL1_LARGE)
        
        # Create CodeBuild projects
        self.dependency_project = self._create_dependency_build_project()
        self.main_project = self._create_main_build_project()
        
        if self.enable_parallel_builds:
            self.parallel_projects = self._create_parallel_build_projects()
        
        # Create Lambda functions
        self.orchestrator_function = self._create_orchestrator_function()
        self.cache_manager_function = self._create_cache_manager_function()
        
        # Create EventBridge rules
        self._create_automation_rules()
        
        # Create outputs
        self._create_outputs()
    
    def _get_buildspec_content(self, stage: str) -> str:
        """
        Get buildspec content for different pipeline stages
        
        Args:
            stage: The build stage (dependency, main, parallel)
            
        Returns:
            Buildspec content as string
        """
        buildspecs = {
            "dependency": """
version: 0.2

env:
  variables:
    CACHE_BUCKET: ""
    NODE_VERSION: "18"
    PYTHON_VERSION: "3.11"

phases:
  install:
    runtime-versions:
      nodejs: $NODE_VERSION
      python: $PYTHON_VERSION
    commands:
      - echo "Installing build dependencies..."
      - apt-get update && apt-get install -y jq curl
      - pip install --upgrade pip
      - npm install -g npm@latest

  pre_build:
    commands:
      - echo "Dependency stage started on $(date)"
      - echo "Checking for cached dependencies..."
      - |
        if aws s3 ls s3://$CACHE_BUCKET/deps/package-lock.json; then
          echo "Found cached package-lock.json"
          aws s3 cp s3://$CACHE_BUCKET/deps/package-lock.json ./package-lock.json || true
        fi

  build:
    commands:
      - echo "Installing Node.js dependencies..."
      - |
        if [ -f "package.json" ]; then
          npm ci --cache /tmp/npm-cache
          echo "Caching node_modules..."
          tar -czf node_modules.tar.gz node_modules/
          aws s3 cp node_modules.tar.gz s3://$CACHE_BUCKET/deps/node_modules-$(date +%Y%m%d).tar.gz
        fi
      - echo "Installing Python dependencies..."
      - |
        if [ -f "requirements.txt" ]; then
          pip install -r requirements.txt --cache-dir /tmp/pip-cache
          echo "Caching Python packages..."
          tar -czf python_packages.tar.gz $(python -c "import site; print(site.getsitepackages()[0])")
          aws s3 cp python_packages.tar.gz s3://$CACHE_BUCKET/deps/python-packages-$(date +%Y%m%d).tar.gz
        fi

  post_build:
    commands:
      - echo "Dependency installation completed"
      - |
        if [ -f "package-lock.json" ]; then
          aws s3 cp package-lock.json s3://$CACHE_BUCKET/deps/package-lock.json
        fi

cache:
  paths:
    - '/tmp/npm-cache/**/*'
    - '/tmp/pip-cache/**/*'
    - 'node_modules/**/*'

artifacts:
  files:
    - '**/*'
  name: dependencies-$(date +%Y-%m-%d)
            """,
            
            "main": """
version: 0.2

env:
  variables:
    CACHE_BUCKET: ""
    ARTIFACT_BUCKET: ""
    ECR_URI: ""
    IMAGE_TAG: "latest"
    DOCKER_BUILDKIT: "1"

phases:
  install:
    runtime-versions:
      docker: 20
      nodejs: 18
      python: 3.11
    commands:
      - echo "Installing build tools..."
      - apt-get update && apt-get install -y jq curl git
      - pip install --upgrade pip pytest pytest-cov black pylint bandit
      - npm install -g eslint prettier jest

  pre_build:
    commands:
      - echo "Main build stage started on $(date)"
      - echo "Logging in to Amazon ECR..."
      - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $ECR_URI
      - export COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)
      - export IMAGE_TAG=${COMMIT_HASH:-latest}
      - echo "Image will be tagged as $IMAGE_TAG"

  build:
    commands:
      - echo "Build started on $(date)"
      - echo "Running code quality checks..."
      - |
        if [ -f "package.json" ]; then
          echo "Running ESLint..."
          npx eslint src/ --ext .js,.jsx,.ts,.tsx --format json > eslint-report.json || true
        fi
      - echo "Running tests..."
      - |
        if [ -f "package.json" ] && grep -q '"test"' package.json; then
          echo "Running Node.js tests..."
          npm test -- --coverage --coverageReporters=json > test-results.json
        fi
      - echo "Building application..."
      - |
        if [ -f "Dockerfile" ]; then
          echo "Building Docker image..."
          docker build --cache-from $ECR_URI:latest -t $ECR_URI:$IMAGE_TAG -t $ECR_URI:latest .
        fi

  post_build:
    commands:
      - echo "Build completed on $(date)"
      - |
        if [ -f "Dockerfile" ]; then
          echo "Pushing Docker image to ECR..."
          docker push $ECR_URI:$IMAGE_TAG
          docker push $ECR_URI:latest
        fi
      - echo "Uploading build artifacts..."
      - |
        cat > build-manifest.json << EOF
        {
          "buildId": "$CODEBUILD_BUILD_ID",
          "commitHash": "$COMMIT_HASH",
          "imageTag": "$IMAGE_TAG",
          "ecrUri": "$ECR_URI",
          "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        }
        EOF
      - aws s3 cp build-manifest.json s3://$ARTIFACT_BUCKET/manifests/build-manifest-$IMAGE_TAG.json

reports:
  test_reports:
    files:
      - 'test-results.json'
    file-format: 'JUNITXML'

cache:
  paths:
    - '/root/.npm/**/*'
    - '/root/.cache/**/*'
    - 'node_modules/**/*'
    - '/var/lib/docker/**/*'

artifacts:
  files:
    - 'build-manifest.json'
    - '**/*'
  name: main-build-$(date +%Y-%m-%d)
            """,
            
            "parallel": """
version: 0.2

env:
  variables:
    CACHE_BUCKET: ""
    ECR_URI: ""
    TARGET_ARCH: "amd64"

phases:
  install:
    runtime-versions:
      docker: 20
    commands:
      - echo "Installing Docker buildx for multi-architecture builds..."
      - docker buildx create --use --name multiarch-builder
      - docker buildx inspect --bootstrap

  pre_build:
    commands:
      - echo "Parallel build for $TARGET_ARCH started on $(date)"
      - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $ECR_URI
      - export COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)
      - export IMAGE_TAG=${COMMIT_HASH:-latest}-$TARGET_ARCH

  build:
    commands:
      - echo "Building for architecture: $TARGET_ARCH"
      - |
        if [ -f "Dockerfile" ]; then
          docker buildx build --platform linux/$TARGET_ARCH --cache-from $ECR_URI:cache-$TARGET_ARCH --cache-to type=registry,ref=$ECR_URI:cache-$TARGET_ARCH,mode=max -t $ECR_URI:$IMAGE_TAG --push .
        fi

  post_build:
    commands:
      - echo "Parallel build for $TARGET_ARCH completed on $(date)"

artifacts:
  files:
    - '**/*'
  name: parallel-build-$TARGET_ARCH-$(date +%Y-%m-%d)
            """
        }
        
        return buildspecs.get(stage, "")
    
    def _create_dependency_build_project(self) -> codebuild.Project:
        """
        Create CodeBuild project for dependency management stage
        
        Returns:
            CodeBuild Project for dependency management
        """
        return codebuild.Project(
            self,
            "DependencyBuildProject",
            project_name=f"{self.project_name}-dependencies-{self.environment}",
            description="Dependency installation and caching stage",
            source=codebuild.Source.s3(
                bucket=self.storage_stack.artifact_bucket,
                path="source/"
            ),
            environment=codebuild.BuildEnvironment(
                build_image=codebuild.LinuxBuildImage.AMAZON_LINUX_2_4,
                compute_type=codebuild.ComputeType.BUILD_GENERAL1_MEDIUM,
                privileged=False,
                environment_variables={
                    "CACHE_BUCKET": codebuild.BuildEnvironmentVariable(
                        value=self.storage_stack.cache_bucket.bucket_name
                    ),
                }
            ),
            cache=codebuild.Cache.s3(
                bucket=self.storage_stack.cache_bucket,
                prefix="dependency-cache"
            ),
            timeout=Duration.minutes(30),
            build_spec=codebuild.BuildSpec.from_object({
                "version": "0.2",
                "phases": {
                    "install": {
                        "runtime-versions": {
                            "nodejs": "18",
                            "python": "3.11"
                        },
                        "commands": [
                            "echo 'Installing build dependencies...'",
                            "apt-get update && apt-get install -y jq curl",
                            "pip install --upgrade pip",
                            "npm install -g npm@latest"
                        ]
                    },
                    "pre_build": {
                        "commands": [
                            "echo 'Dependency stage started on $(date)'",
                            "echo 'Checking for cached dependencies...'"
                        ]
                    },
                    "build": {
                        "commands": [
                            "echo 'Installing dependencies with caching...'"
                        ]
                    }
                },
                "cache": {
                    "paths": [
                        "/tmp/npm-cache/**/*",
                        "/tmp/pip-cache/**/*",
                        "node_modules/**/*"
                    ]
                }
            }),
            artifacts=codebuild.Artifacts.s3(
                bucket=self.storage_stack.artifact_bucket,
                path="dependencies",
                name="dependencies"
            ),
            role=self.storage_stack.codebuild_role,
            logging=codebuild.LoggingOptions(
                cloud_watch=codebuild.CloudWatchLoggingOptions(
                    log_group=logs.LogGroup(
                        self,
                        "DependencyBuildLogGroup",
                        log_group_name=f"/aws/codebuild/{self.project_name}-dependencies-{self.environment}",
                        retention=logs.RetentionDays.ONE_MONTH
                    )
                )
            )
        )
    
    def _create_main_build_project(self) -> codebuild.Project:
        """
        Create CodeBuild project for main build stage
        
        Returns:
            CodeBuild Project for main build
        """
        return codebuild.Project(
            self,
            "MainBuildProject",
            project_name=f"{self.project_name}-main-{self.environment}",
            description="Main build stage with testing and quality checks",
            source=codebuild.Source.s3(
                bucket=self.storage_stack.artifact_bucket,
                path="source/"
            ),
            environment=codebuild.BuildEnvironment(
                build_image=codebuild.LinuxBuildImage.AMAZON_LINUX_2_4,
                compute_type=self.build_compute_type,
                privileged=True,  # Required for Docker builds
                environment_variables={
                    "CACHE_BUCKET": codebuild.BuildEnvironmentVariable(
                        value=self.storage_stack.cache_bucket.bucket_name
                    ),
                    "ARTIFACT_BUCKET": codebuild.BuildEnvironmentVariable(
                        value=self.storage_stack.artifact_bucket.bucket_name
                    ),
                    "ECR_URI": codebuild.BuildEnvironmentVariable(
                        value=self.storage_stack.ecr_repository.repository_uri
                    ),
                }
            ),
            cache=codebuild.Cache.s3(
                bucket=self.storage_stack.cache_bucket,
                prefix="main-cache"
            ),
            timeout=Duration.minutes(60),
            build_spec=codebuild.BuildSpec.from_object({
                "version": "0.2",
                "phases": {
                    "install": {
                        "runtime-versions": {
                            "docker": "20",
                            "nodejs": "18",
                            "python": "3.11"
                        },
                        "commands": [
                            "echo 'Installing build tools...'",
                            "apt-get update && apt-get install -y jq curl git",
                            "pip install --upgrade pip pytest pytest-cov black pylint",
                            "npm install -g eslint prettier jest"
                        ]
                    },
                    "pre_build": {
                        "commands": [
                            "echo 'Main build stage started on $(date)'",
                            "aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $ECR_URI",
                            "export COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)",
                            "export IMAGE_TAG=${COMMIT_HASH:-latest}"
                        ]
                    },
                    "build": {
                        "commands": [
                            "echo 'Build started on $(date)'",
                            "echo 'Running tests and quality checks...'",
                            "echo 'Building application...'"
                        ]
                    },
                    "post_build": {
                        "commands": [
                            "echo 'Build completed on $(date)'",
                            "echo 'Uploading artifacts...'"
                        ]
                    }
                },
                "reports": {
                    "test_reports": {
                        "files": ["test-results.json"],
                        "file-format": "JUNITXML"
                    }
                },
                "cache": {
                    "paths": [
                        "/root/.npm/**/*",
                        "/root/.cache/**/*",
                        "node_modules/**/*",
                        "/var/lib/docker/**/*"
                    ]
                }
            }),
            artifacts=codebuild.Artifacts.s3(
                bucket=self.storage_stack.artifact_bucket,
                path="main-build",
                name="main-build"
            ),
            role=self.storage_stack.codebuild_role,
            logging=codebuild.LoggingOptions(
                cloud_watch=codebuild.CloudWatchLoggingOptions(
                    log_group=logs.LogGroup(
                        self,
                        "MainBuildLogGroup",
                        log_group_name=f"/aws/codebuild/{self.project_name}-main-{self.environment}",
                        retention=logs.RetentionDays.ONE_MONTH
                    )
                )
            )
        )
    
    def _create_parallel_build_projects(self) -> List[codebuild.Project]:
        """
        Create CodeBuild projects for parallel architecture builds
        
        Returns:
            List of CodeBuild Projects for parallel builds
        """
        projects = []
        
        for i, arch in enumerate(self.parallel_architectures):
            project = codebuild.Project(
                self,
                f"ParallelBuildProject{arch.title()}",
                project_name=f"{self.project_name}-parallel-{arch}-{self.environment}",
                description=f"Parallel build for {arch} architecture",
                source=codebuild.Source.s3(
                    bucket=self.storage_stack.artifact_bucket,
                    path="source/"
                ),
                environment=codebuild.BuildEnvironment(
                    build_image=codebuild.LinuxBuildImage.AMAZON_LINUX_2_4,
                    compute_type=codebuild.ComputeType.BUILD_GENERAL1_MEDIUM,
                    privileged=True,
                    environment_variables={
                        "CACHE_BUCKET": codebuild.BuildEnvironmentVariable(
                            value=self.storage_stack.cache_bucket.bucket_name
                        ),
                        "ECR_URI": codebuild.BuildEnvironmentVariable(
                            value=self.storage_stack.ecr_repository.repository_uri
                        ),
                        "TARGET_ARCH": codebuild.BuildEnvironmentVariable(
                            value=arch
                        ),
                    }
                ),
                cache=codebuild.Cache.s3(
                    bucket=self.storage_stack.cache_bucket,
                    prefix=f"parallel-cache-{arch}"
                ),
                timeout=Duration.minutes(45),
                build_spec=codebuild.BuildSpec.from_object({
                    "version": "0.2",
                    "phases": {
                        "install": {
                            "runtime-versions": {
                                "docker": "20"
                            },
                            "commands": [
                                "echo 'Installing Docker buildx...'",
                                "docker buildx create --use --name multiarch-builder",
                                "docker buildx inspect --bootstrap"
                            ]
                        },
                        "pre_build": {
                            "commands": [
                                f"echo 'Parallel build for {arch} started on $(date)'",
                                "aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $ECR_URI"
                            ]
                        },
                        "build": {
                            "commands": [
                                f"echo 'Building for architecture: {arch}'"
                            ]
                        }
                    }
                }),
                artifacts=codebuild.Artifacts.s3(
                    bucket=self.storage_stack.artifact_bucket,
                    path=f"parallel-build-{arch}",
                    name=f"parallel-build-{arch}"
                ),
                role=self.storage_stack.codebuild_role,
                logging=codebuild.LoggingOptions(
                    cloud_watch=codebuild.CloudWatchLoggingOptions(
                        log_group=logs.LogGroup(
                            self,
                            f"ParallelBuildLogGroup{arch.title()}",
                            log_group_name=f"/aws/codebuild/{self.project_name}-parallel-{arch}-{self.environment}",
                            retention=logs.RetentionDays.ONE_MONTH
                        )
                    )
                )
            )
            projects.append(project)
        
        return projects
    
    def _create_orchestrator_function(self) -> lambda_.Function:
        """
        Create Lambda function for build orchestration
        
        Returns:
            Lambda Function for orchestration
        """
        # Create IAM role for orchestrator
        orchestrator_role = iam.Role(
            self,
            "OrchestratorRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ]
        )
        
        # Add CodeBuild permissions
        orchestrator_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "codebuild:StartBuild",
                    "codebuild:BatchGetBuilds",
                    "codebuild:ListBuildsForProject",
                ],
                resources=[
                    self.dependency_project.project_arn,
                    self.main_project.project_arn,
                ] + ([project.project_arn for project in self.parallel_projects] if self.enable_parallel_builds else [])
            )
        )
        
        # Add S3 permissions
        orchestrator_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                ],
                resources=[
                    f"{self.storage_stack.artifact_bucket.bucket_arn}/*"
                ]
            )
        )
        
        # Add CloudWatch permissions
        orchestrator_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudwatch:PutMetricData",
                ],
                resources=["*"]
            )
        )
        
        function = lambda_.Function(
            self,
            "OrchestratorFunction",
            function_name=f"{self.project_name}-orchestrator-{self.environment}",
            description="Orchestrate multi-stage CodeBuild pipeline",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline("""
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
    try:
        logger.info(f"Build orchestration started: {json.dumps(event)}")
        
        build_config = event.get('buildConfig', {})
        source_location = build_config.get('sourceLocation')
        
        if not source_location:
            return {'statusCode': 400, 'body': 'Source location required'}
        
        # Execute build pipeline stages
        pipeline_result = execute_build_pipeline(source_location)
        
        return {
            'statusCode': 200,
            'body': json.dumps(pipeline_result, default=str)
        }
        
    except Exception as e:
        logger.error(f"Error in build orchestration: {str(e)}")
        return {'statusCode': 500, 'body': f'Error: {str(e)}'}

def execute_build_pipeline(source_location):
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
        if dep_result.get('status') == 'SUCCEEDED':
            logger.info("Starting main build stage...")
            main_result = start_build_stage('main', source_location)
            results['stages']['main'] = main_result
        
        results['overallStatus'] = 'SUCCEEDED'
        results['endTime'] = datetime.utcnow().isoformat()
        
        return results
        
    except Exception as e:
        logger.error(f"Pipeline execution failed: {str(e)}")
        results['overallStatus'] = 'FAILED'
        results['error'] = str(e)
        results['endTime'] = datetime.utcnow().isoformat()
        return results

def start_build_stage(stage, source_location):
    import os
    
    project_mapping = {
        'dependencies': os.environ.get('DEPENDENCY_PROJECT'),
        'main': os.environ.get('MAIN_PROJECT'),
    }
    
    project_name = project_mapping.get(stage)
    if not project_name:
        raise ValueError(f"Unknown build stage: {stage}")
    
    try:
        response = codebuild.start_build(
            projectName=project_name,
            sourceLocationOverride=source_location
        )
        
        build_id = response['build']['id']
        logger.info(f"Started {stage} build: {build_id}")
        
        return {
            'stage': stage,
            'buildId': build_id,
            'status': 'STARTED',
            'startTime': datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Error starting {stage} build: {str(e)}")
        return {
            'stage': stage,
            'status': 'FAILED',
            'error': str(e)
        }
            """),
            timeout=Duration.minutes(15),
            memory_size=512,
            environment={
                "DEPENDENCY_PROJECT": self.dependency_project.project_name,
                "MAIN_PROJECT": self.main_project.project_name,
                "CACHE_BUCKET": self.storage_stack.cache_bucket.bucket_name,
                "ARTIFACT_BUCKET": self.storage_stack.artifact_bucket.bucket_name,
            },
            role=orchestrator_role,
            log_retention=logs.RetentionDays.ONE_MONTH
        )
        
        return function
    
    def _create_cache_manager_function(self) -> lambda_.Function:
        """
        Create Lambda function for cache management
        
        Returns:
            Lambda Function for cache management
        """
        # Create IAM role for cache manager
        cache_manager_role = iam.Role(
            self,
            "CacheManagerRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ]
        )
        
        # Add S3 permissions
        cache_manager_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:ListBucket",
                    "s3:GetObject",
                    "s3:DeleteObject",
                ],
                resources=[
                    self.storage_stack.cache_bucket.bucket_arn,
                    f"{self.storage_stack.cache_bucket.bucket_arn}/*"
                ]
            )
        )
        
        function = lambda_.Function(
            self,
            "CacheManagerFunction",
            function_name=f"{self.project_name}-cache-manager-{self.environment}",
            description="Manage and optimize CodeBuild caches",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline("""
import json
import boto3
import logging
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')

def lambda_handler(event, context):
    try:
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
    staleness_rules = {
        'deps/node_modules': 30,
        'deps/python-packages': 30,
        'cache/docker': 14,
        'cache/build': 7,
    }
    
    cache_type = None
    for prefix, max_age in staleness_rules.items():
        if key.startswith(prefix):
            cache_type = prefix
            max_age_days = max_age
            break
    
    if not cache_type:
        max_age_days = 14
    
    threshold_date = datetime.utcnow() - timedelta(days=max_age_days)
    
    if last_modified.tzinfo:
        last_modified = last_modified.replace(tzinfo=None)
    
    return last_modified < threshold_date

import os
            """),
            timeout=Duration.minutes(5),
            memory_size=256,
            environment={
                "CACHE_BUCKET": self.storage_stack.cache_bucket.bucket_name,
            },
            role=cache_manager_role,
            log_retention=logs.RetentionDays.ONE_MONTH
        )
        
        return function
    
    def _create_automation_rules(self) -> None:
        """Create EventBridge rules for automation"""
        
        # Daily cache optimization rule
        cache_rule = events.Rule(
            self,
            "CacheOptimizationRule",
            rule_name=f"{self.project_name}-cache-optimization-{self.environment}",
            description="Daily cache optimization",
            schedule=events.Schedule.rate(Duration.days(1))
        )
        
        # Add cache manager as target
        cache_rule.add_target(
            targets.LambdaFunction(self.cache_manager_function)
        )
        
        # Grant EventBridge permission to invoke Lambda
        self.cache_manager_function.add_permission(
            "AllowEventBridgeInvoke",
            principal=iam.ServicePrincipal("events.amazonaws.com"),
            source_arn=cache_rule.rule_arn
        )
    
    def _create_outputs(self) -> None:
        """Create CloudFormation outputs"""
        
        cdk.CfnOutput(
            self,
            "DependencyProjectName",
            value=self.dependency_project.project_name,
            description="Name of the dependency build project"
        )
        
        cdk.CfnOutput(
            self,
            "MainProjectName",
            value=self.main_project.project_name,
            description="Name of the main build project"
        )
        
        cdk.CfnOutput(
            self,
            "OrchestratorFunctionArn",
            value=self.orchestrator_function.function_arn,
            description="ARN of the build orchestrator function"
        )
        
        if self.enable_parallel_builds:
            for i, project in enumerate(self.parallel_projects):
                cdk.CfnOutput(
                    self,
                    f"ParallelProject{i+1}Name",
                    value=project.project_name,
                    description=f"Name of parallel build project {i+1}"
                )