#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import {
  aws_codecommit as codecommit,
  aws_codeguruprofiler as profiler,
  aws_iam as iam,
  aws_lambda as lambda,
  aws_events as events,
  aws_events_targets as targets,
  aws_logs as logs,
  aws_s3 as s3,
  RemovalPolicy,
  Duration,
  CfnOutput,
  Stack,
  StackProps,
} from 'aws-cdk-lib';

/**
 * Interface for CodeGuru Automation Stack properties
 */
interface CodeGuruAutomationStackProps extends StackProps {
  /**
   * Name prefix for all resources
   * @default 'CodeGuruAutomation'
   */
  readonly resourcePrefix?: string;
  
  /**
   * Repository name for CodeCommit
   * @default Generated unique name
   */
  readonly repositoryName?: string;
  
  /**
   * Profiling group name for CodeGuru Profiler
   * @default Generated unique name
   */
  readonly profilingGroupName?: string;
  
  /**
   * Enable automated quality gates
   * @default true
   */
  readonly enableQualityGates?: boolean;
  
  /**
   * Retention period for logs in days
   * @default 30
   */
  readonly logRetentionDays?: logs.RetentionDays;
}

/**
 * CDK Stack for CodeGuru Code Review Automation
 * 
 * This stack creates:
 * - CodeCommit repository with CodeGuru Reviewer association
 * - CodeGuru Profiler group for runtime analysis
 * - Lambda functions for automation workflows
 * - IAM roles and policies with least privilege access
 * - EventBridge rules for automated triggers
 * - S3 bucket for storing artifacts and reports
 */
export class CodeGuruAutomationStack extends Stack {
  public readonly repository: codecommit.Repository;
  public readonly profilingGroup: profiler.CfnProfilingGroup;
  public readonly qualityGateFunction: lambda.Function;
  public readonly artifactsBucket: s3.Bucket;

  constructor(scope: Construct, id: string, props: CodeGuruAutomationStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const resourcePrefix = props.resourcePrefix ?? 'CodeGuruAutomation';
    const enableQualityGates = props.enableQualityGates ?? true;
    const logRetentionDays = props.logRetentionDays ?? logs.RetentionDays.ONE_MONTH;

    // Generate unique suffixes for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8);
    const repositoryName = props.repositoryName ?? `codeguru-demo-${uniqueSuffix}`;
    const profilingGroupName = props.profilingGroupName ?? `demo-profiler-${uniqueSuffix}`;

    // Create S3 bucket for storing artifacts and reports
    this.artifactsBucket = new s3.Bucket(this, 'ArtifactsBucket', {
      bucketName: `${resourcePrefix.toLowerCase()}-artifacts-${uniqueSuffix}`,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: Duration.days(90),
        },
      ],
    });

    // Create CodeCommit repository
    this.repository = new codecommit.Repository(this, 'CodeRepository', {
      repositoryName,
      description: 'Demo repository for CodeGuru automation and analysis',
      code: codecommit.Code.fromZipFile('initial-code.zip', this.createInitialCode()),
    });

    // Create IAM role for CodeGuru Reviewer
    const codeGuruReviewerRole = new iam.Role(this, 'CodeGuruReviewerRole', {
      roleName: `${resourcePrefix}-CodeGuruReviewer-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('codeguru-reviewer.amazonaws.com'),
      description: 'IAM role for CodeGuru Reviewer service',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonCodeGuruReviewerServiceRolePolicy'),
      ],
    });

    // Create CodeGuru Profiler group
    this.profilingGroup = new profiler.CfnProfilingGroup(this, 'ProfilingGroup', {
      profilingGroupName,
      computePlatform: 'Default',
      agentPermissions: {
        principals: ['*'],
      },
      tags: [
        {
          key: 'Purpose',
          value: 'CodeGuru Automation Demo',
        },
        {
          key: 'Environment',
          value: 'Development',
        },
      ],
    });

    // Create Lambda execution role
    const lambdaExecutionRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `${resourcePrefix}-Lambda-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for CodeGuru automation Lambda functions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        CodeGuruAutomationPolicy: new iam.PolicyDocument({
          statements: [
            // CodeGuru Reviewer permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'codeguru-reviewer:AssociateRepository',
                'codeguru-reviewer:DescribeRepositoryAssociation',
                'codeguru-reviewer:ListRepositoryAssociations',
                'codeguru-reviewer:CreateCodeReview',
                'codeguru-reviewer:DescribeCodeReview',
                'codeguru-reviewer:ListRecommendations',
                'codeguru-reviewer:PutRecommendationFeedback',
              ],
              resources: ['*'],
            }),
            // CodeGuru Profiler permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'codeguru-profiler:DescribeProfilingGroup',
                'codeguru-profiler:ListProfilingGroups',
                'codeguru-profiler:ListProfileTimes',
                'codeguru-profiler:GetProfile',
                'codeguru-profiler:GetRecommendations',
              ],
              resources: [this.profilingGroup.attrArn],
            }),
            // CodeCommit permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'codecommit:GetRepository',
                'codecommit:ListRepositories',
                'codecommit:GetBranch',
                'codecommit:ListBranches',
                'codecommit:GetCommit',
              ],
              resources: [this.repository.repositoryArn],
            }),
            // S3 permissions for artifacts
            new iam.PolicyStatement({
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
            }),
          ],
        }),
      },
    });

    // Create quality gate Lambda function
    this.qualityGateFunction = new lambda.Function(this, 'QualityGateFunction', {
      functionName: `${resourcePrefix}-QualityGate-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(this.getQualityGateLambdaCode()),
      role: lambdaExecutionRole,
      timeout: Duration.minutes(5),
      memorySize: 256,
      description: 'Automated quality gate enforcement for CodeGuru recommendations',
      environment: {
        ARTIFACTS_BUCKET: this.artifactsBucket.bucketName,
        PROFILING_GROUP_NAME: profilingGroupName,
        REPOSITORY_NAME: repositoryName,
      },
      logRetention: logRetentionDays,
    });

    // Create Lambda function for repository association
    const repositoryAssociationFunction = new lambda.Function(this, 'RepositoryAssociationFunction', {
      functionName: `${resourcePrefix}-RepoAssociation-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(this.getRepositoryAssociationLambdaCode()),
      role: lambdaExecutionRole,
      timeout: Duration.minutes(3),
      memorySize: 128,
      description: 'Associates CodeCommit repository with CodeGuru Reviewer',
      environment: {
        REPOSITORY_NAME: repositoryName,
        REPOSITORY_ARN: this.repository.repositoryArn,
      },
      logRetention: logRetentionDays,
    });

    // Create Lambda function for performance monitoring
    const performanceMonitorFunction = new lambda.Function(this, 'PerformanceMonitorFunction', {
      functionName: `${resourcePrefix}-PerfMonitor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(this.getPerformanceMonitorLambdaCode()),
      role: lambdaExecutionRole,
      timeout: Duration.minutes(5),
      memorySize: 256,
      description: 'Monitors CodeGuru Profiler data and generates insights',
      environment: {
        PROFILING_GROUP_NAME: profilingGroupName,
        ARTIFACTS_BUCKET: this.artifactsBucket.bucketName,
      },
      logRetention: logRetentionDays,
    });

    if (enableQualityGates) {
      // Create EventBridge rule for CodeCommit events
      const codeCommitRule = new events.Rule(this, 'CodeCommitRule', {
        ruleName: `${resourcePrefix}-CodeCommit-${uniqueSuffix}`,
        description: 'Triggers quality gate on CodeCommit push events',
        eventPattern: {
          source: ['aws.codecommit'],
          detailType: ['CodeCommit Repository State Change'],
          detail: {
            event: ['referenceCreated', 'referenceUpdated'],
            repositoryName: [repositoryName],
          },
        },
      });

      // Add Lambda target to EventBridge rule
      codeCommitRule.addTarget(new targets.LambdaFunction(this.qualityGateFunction, {
        retryAttempts: 2,
      }));

      // Create EventBridge rule for scheduled performance monitoring
      const performanceMonitorRule = new events.Rule(this, 'PerformanceMonitorRule', {
        ruleName: `${resourcePrefix}-PerfMonitor-${uniqueSuffix}`,
        description: 'Scheduled performance monitoring for CodeGuru Profiler',
        schedule: events.Schedule.rate(Duration.hours(6)),
      });

      // Add Lambda target for performance monitoring
      performanceMonitorRule.addTarget(new targets.LambdaFunction(performanceMonitorFunction, {
        retryAttempts: 2,
      }));
    }

    // Create CloudWatch Log Groups with retention
    new logs.LogGroup(this, 'QualityGateLogGroup', {
      logGroupName: `/aws/lambda/${this.qualityGateFunction.functionName}`,
      retention: logRetentionDays,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    new logs.LogGroup(this, 'RepositoryAssociationLogGroup', {
      logGroupName: `/aws/lambda/${repositoryAssociationFunction.functionName}`,
      retention: logRetentionDays,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    new logs.LogGroup(this, 'PerformanceMonitorLogGroup', {
      logGroupName: `/aws/lambda/${performanceMonitorFunction.functionName}`,
      retention: logRetentionDays,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    // Outputs
    new CfnOutput(this, 'RepositoryName', {
      value: this.repository.repositoryName,
      description: 'Name of the CodeCommit repository',
      exportName: `${this.stackName}-RepositoryName`,
    });

    new CfnOutput(this, 'RepositoryCloneUrl', {
      value: this.repository.repositoryCloneUrlHttp,
      description: 'HTTPS clone URL for the CodeCommit repository',
      exportName: `${this.stackName}-RepositoryCloneUrl`,
    });

    new CfnOutput(this, 'ProfilingGroupName', {
      value: this.profilingGroup.profilingGroupName,
      description: 'Name of the CodeGuru Profiler group',
      exportName: `${this.stackName}-ProfilingGroupName`,
    });

    new CfnOutput(this, 'ArtifactsBucketName', {
      value: this.artifactsBucket.bucketName,
      description: 'Name of the S3 bucket for storing artifacts',
      exportName: `${this.stackName}-ArtifactsBucketName`,
    });

    new CfnOutput(this, 'QualityGateFunctionArn', {
      value: this.qualityGateFunction.functionArn,
      description: 'ARN of the quality gate Lambda function',
      exportName: `${this.stackName}-QualityGateFunctionArn`,
    });

    new CfnOutput(this, 'RepositoryAssociationFunctionArn', {
      value: repositoryAssociationFunction.functionArn,
      description: 'ARN of the repository association Lambda function',
      exportName: `${this.stackName}-RepositoryAssociationFunctionArn`,
    });
  }

  /**
   * Creates initial code content for the repository
   */
  private createInitialCode(): string {
    // This would typically be a zip file with sample code
    // For this example, we'll create a simple structure
    return `# CodeGuru Demo Repository

This repository contains sample code for demonstrating CodeGuru Reviewer and Profiler capabilities.

## Structure

- \`src/main/java/com/example/\` - Java sample applications
- \`src/python/\` - Python sample applications
- \`scripts/\` - Automation scripts
- \`aws-codeguru-reviewer.yml\` - CodeGuru Reviewer configuration

## Getting Started

1. Clone this repository
2. Review the sample code in the src directories
3. Make changes and commit to trigger CodeGuru analysis
4. Run the profiling-enabled applications to generate performance data

## CodeGuru Integration

This repository is automatically associated with CodeGuru Reviewer for:
- Automated code quality analysis
- Security vulnerability detection
- Performance recommendation generation
- Best practice enforcement

For more information, see the AWS CodeGuru documentation.
`;
  }

  /**
   * Returns the Lambda function code for quality gate enforcement
   */
  private getQualityGateLambdaCode(): string {
    return `
import json
import boto3
import logging
import os
from datetime import datetime, timedelta

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
codeguru_reviewer = boto3.client('codeguru-reviewer')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Lambda handler for automated quality gate enforcement
    
    This function:
    1. Triggers CodeGuru Reviewer analysis on code changes
    2. Evaluates recommendations against quality thresholds
    3. Stores results in S3 for reporting
    4. Returns quality gate status
    """
    
    try:
        logger.info(f"Processing event: {json.dumps(event)}")
        
        # Extract repository information from event
        repository_name = os.environ.get('REPOSITORY_NAME')
        artifacts_bucket = os.environ.get('ARTIFACTS_BUCKET')
        
        if 'detail' in event:
            # CodeCommit event
            detail = event['detail']
            repository_name = detail.get('repositoryName', repository_name)
            reference_name = detail.get('referenceName', 'main')
            commit_id = detail.get('commitId', '')
            
            logger.info(f"Processing CodeCommit event for repository: {repository_name}")
            
            # Find repository association
            associations = codeguru_reviewer.list_repository_associations()
            
            association_arn = None
            for association in associations['RepositoryAssociationSummaries']:
                if repository_name in association['RepositoryName']:
                    association_arn = association['AssociationArn']
                    break
            
            if not association_arn:
                logger.error(f"No repository association found for {repository_name}")
                return create_response(400, "Repository not associated with CodeGuru")
            
            # Create code review
            review_name = f"automated-review-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
            
            try:
                response = codeguru_reviewer.create_code_review(
                    Name=review_name,
                    RepositoryAssociationArn=association_arn,
                    Type={
                        'RepositoryAnalysis': {
                            'RepositoryHead': {
                                'BranchName': reference_name.replace('refs/heads/', '')
                            }
                        }
                    }
                )
                
                code_review_arn = response['CodeReview']['CodeReviewArn']
                logger.info(f"Created code review: {code_review_arn}")
                
                # Wait for analysis to complete (simplified - in production, use Step Functions)
                analysis_result = wait_for_analysis(code_review_arn)
                
                # Store results in S3
                if artifacts_bucket:
                    store_analysis_results(artifacts_bucket, code_review_arn, analysis_result)
                
                return create_response(200, {
                    "message": "Quality gate completed",
                    "codeReviewArn": code_review_arn,
                    "qualityGateStatus": analysis_result['status'],
                    "recommendationCount": analysis_result['recommendationCount'],
                    "highSeverityCount": analysis_result['highSeverityCount']
                })
                
            except Exception as e:
                logger.error(f"Error creating code review: {str(e)}")
                return create_response(500, f"Error creating code review: {str(e)}")
        
        else:
            # Manual invocation or testing
            logger.info("Manual invocation - returning success")
            return create_response(200, {"message": "Quality gate function is operational"})
            
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return create_response(500, f"Unexpected error: {str(e)}")

def wait_for_analysis(code_review_arn, max_wait_minutes=5):
    """
    Wait for CodeGuru analysis to complete
    
    Args:
        code_review_arn: ARN of the code review
        max_wait_minutes: Maximum time to wait
    
    Returns:
        Analysis result summary
    """
    import time
    
    max_iterations = max_wait_minutes * 12  # 5-second intervals
    
    for i in range(max_iterations):
        try:
            response = codeguru_reviewer.describe_code_review(
                CodeReviewArn=code_review_arn
            )
            
            state = response['CodeReview']['State']
            logger.info(f"Code review state: {state}")
            
            if state == 'Completed':
                # Get recommendations
                recommendations = codeguru_reviewer.list_recommendations(
                    CodeReviewArn=code_review_arn
                )
                
                high_severity_count = sum(1 for rec in recommendations['RecommendationSummaries'] 
                                        if rec['Severity'] == 'HIGH')
                
                total_count = len(recommendations['RecommendationSummaries'])
                
                # Determine quality gate status
                status = 'PASSED' if high_severity_count == 0 else 'FAILED'
                
                return {
                    'status': status,
                    'recommendationCount': total_count,
                    'highSeverityCount': high_severity_count,
                    'recommendations': recommendations['RecommendationSummaries']
                }
            
            elif state == 'Failed':
                return {
                    'status': 'ERROR',
                    'recommendationCount': 0,
                    'highSeverityCount': 0,
                    'error': 'Code review analysis failed'
                }
            
            time.sleep(5)
            
        except Exception as e:
            logger.error(f"Error checking code review status: {str(e)}")
            break
    
    # Timeout
    return {
        'status': 'TIMEOUT',
        'recommendationCount': 0,
        'highSeverityCount': 0,
        'error': 'Analysis timeout'
    }

def store_analysis_results(bucket_name, code_review_arn, analysis_result):
    """
    Store analysis results in S3 for reporting
    
    Args:
        bucket_name: S3 bucket name
        code_review_arn: ARN of the code review
        analysis_result: Analysis result data
    """
    try:
        timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
        key = f"quality-reports/{timestamp}/analysis-result.json"
        
        report_data = {
            'timestamp': timestamp,
            'codeReviewArn': code_review_arn,
            'analysisResult': analysis_result
        }
        
        s3.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=json.dumps(report_data, indent=2),
            ContentType='application/json'
        )
        
        logger.info(f"Stored analysis results in s3://{bucket_name}/{key}")
        
    except Exception as e:
        logger.error(f"Error storing analysis results: {str(e)}")

def create_response(status_code, body):
    """Create standardized Lambda response"""
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(body) if isinstance(body, dict) else str(body)
    }
`;
  }

  /**
   * Returns the Lambda function code for repository association
   */
  private getRepositoryAssociationLambdaCode(): string {
    return `
import json
import boto3
import logging
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
codeguru_reviewer = boto3.client('codeguru-reviewer')

def lambda_handler(event, context):
    """
    Lambda handler for CodeCommit repository association with CodeGuru Reviewer
    
    This function associates a CodeCommit repository with CodeGuru Reviewer
    to enable automated code analysis.
    """
    
    try:
        repository_name = os.environ.get('REPOSITORY_NAME')
        repository_arn = os.environ.get('REPOSITORY_ARN')
        
        logger.info(f"Associating repository {repository_name} with CodeGuru Reviewer")
        
        # Check if repository is already associated
        associations = codeguru_reviewer.list_repository_associations()
        
        for association in associations['RepositoryAssociationSummaries']:
            if repository_name in association['RepositoryName']:
                logger.info(f"Repository {repository_name} is already associated")
                return create_response(200, {
                    "message": "Repository already associated",
                    "associationArn": association['AssociationArn'],
                    "state": association['State']
                })
        
        # Associate repository
        try:
            response = codeguru_reviewer.associate_repository(
                Repository={
                    'CodeCommit': {
                        'Name': repository_name
                    }
                },
                ClientRequestToken=context.aws_request_id
            )
            
            association_arn = response['RepositoryAssociation']['AssociationArn']
            
            logger.info(f"Successfully associated repository: {association_arn}")
            
            return create_response(200, {
                "message": "Repository associated successfully",
                "associationArn": association_arn,
                "repositoryName": repository_name
            })
            
        except Exception as e:
            logger.error(f"Error associating repository: {str(e)}")
            return create_response(500, f"Error associating repository: {str(e)}")
            
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return create_response(500, f"Unexpected error: {str(e)}")

def create_response(status_code, body):
    """Create standardized Lambda response"""
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json'
        },
        'body': json.dumps(body) if isinstance(body, dict) else str(body)
    }
`;
  }

  /**
   * Returns the Lambda function code for performance monitoring
   */
  private getPerformanceMonitorLambdaCode(): string {
    return `
import json
import boto3
import logging
import os
from datetime import datetime, timedelta

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
codeguru_profiler = boto3.client('codeguruprofiler')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Lambda handler for performance monitoring with CodeGuru Profiler
    
    This function:
    1. Checks for recent profiling data
    2. Retrieves performance recommendations
    3. Stores performance reports in S3
    4. Identifies performance trends
    """
    
    try:
        profiling_group_name = os.environ.get('PROFILING_GROUP_NAME')
        artifacts_bucket = os.environ.get('ARTIFACTS_BUCKET')
        
        logger.info(f"Monitoring performance for profiling group: {profiling_group_name}")
        
        # Check profiling group status
        try:
            group_response = codeguru_profiler.describe_profiling_group(
                profilingGroupName=profiling_group_name
            )
            
            logger.info(f"Profiling group status: {group_response['profilingGroup']['profilingStatus']}")
            
        except Exception as e:
            logger.error(f"Error describing profiling group: {str(e)}")
            return create_response(404, f"Profiling group not found: {str(e)}")
        
        # Get recent profile times
        end_time = datetime.now()
        start_time = end_time - timedelta(hours=24)
        
        try:
            profile_times_response = codeguru_profiler.list_profile_times(
                profilingGroupName=profiling_group_name,
                startTime=start_time,
                endTime=end_time
            )
            
            profile_times = profile_times_response.get('profileTimes', [])
            logger.info(f"Found {len(profile_times)} profiles in the last 24 hours")
            
            if not profile_times:
                logger.info("No recent profiles found")
                return create_response(200, {
                    "message": "No recent profiling data found",
                    "profilingGroupName": profiling_group_name,
                    "profileCount": 0
                })
            
            # Get the most recent profile
            latest_profile = max(profile_times, key=lambda x: x['start'])
            
            # Get performance recommendations (if available)
            recommendations = []
            try:
                recommendations_response = codeguru_profiler.get_recommendations(
                    profilingGroupName=profiling_group_name,
                    startTime=latest_profile['start'],
                    endTime=latest_profile['start'] + timedelta(minutes=5)
                )
                
                recommendations = recommendations_response.get('recommendations', [])
                logger.info(f"Found {len(recommendations)} performance recommendations")
                
            except Exception as e:
                logger.warning(f"Could not retrieve recommendations: {str(e)}")
            
            # Create performance report
            performance_report = {
                'timestamp': datetime.now().isoformat(),
                'profilingGroupName': profiling_group_name,
                'profileCount': len(profile_times),
                'latestProfileTime': latest_profile['start'].isoformat(),
                'recommendationCount': len(recommendations),
                'recommendations': recommendations,
                'profileTimes': [p['start'].isoformat() for p in profile_times[-10:]]  # Last 10 profiles
            }
            
            # Store report in S3
            if artifacts_bucket:
                store_performance_report(artifacts_bucket, performance_report)
            
            return create_response(200, {
                "message": "Performance monitoring completed",
                "profilingGroupName": profiling_group_name,
                "profileCount": len(profile_times),
                "recommendationCount": len(recommendations),
                "latestProfileTime": latest_profile['start'].isoformat()
            })
            
        except Exception as e:
            logger.error(f"Error retrieving profile times: {str(e)}")
            return create_response(500, f"Error retrieving profile data: {str(e)}")
            
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return create_response(500, f"Unexpected error: {str(e)}")

def store_performance_report(bucket_name, report_data):
    """
    Store performance report in S3
    
    Args:
        bucket_name: S3 bucket name
        report_data: Performance report data
    """
    try:
        timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
        key = f"performance-reports/{timestamp}/performance-report.json"
        
        s3.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=json.dumps(report_data, indent=2, default=str),
            ContentType='application/json'
        )
        
        logger.info(f"Stored performance report in s3://{bucket_name}/{key}")
        
    except Exception as e:
        logger.error(f"Error storing performance report: {str(e)}")

def create_response(status_code, body):
    """Create standardized Lambda response"""
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json'
        },
        'body': json.dumps(body, default=str) if isinstance(body, dict) else str(body)
    }
`;
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Get stack configuration from CDK context or environment variables
const stackProps: CodeGuruAutomationStackProps = {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'CodeGuru Code Review Automation Stack - Automated code quality analysis and performance monitoring',
  resourcePrefix: app.node.tryGetContext('resourcePrefix') || 'CodeGuruAutomation',
  enableQualityGates: app.node.tryGetContext('enableQualityGates') !== false,
  logRetentionDays: logs.RetentionDays.ONE_MONTH,
};

// Create the stack
new CodeGuruAutomationStack(app, 'CodeGuruAutomationStack', stackProps);

// Synthesize the CloudFormation template
app.synth();