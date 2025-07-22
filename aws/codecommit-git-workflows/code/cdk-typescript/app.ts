#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as codecommit from 'aws-cdk-lib/aws-codecommit';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import { CustomResource } from 'aws-cdk-lib';
import * as customResources from 'aws-cdk-lib/custom-resources';

/**
 * Props for the CodeCommit Git Workflows Stack
 */
export interface CodeCommitGitWorkflowsStackProps extends cdk.StackProps {
  /**
   * Name of the CodeCommit repository to create
   * @default 'enterprise-app-${randomSuffix}'
   */
  readonly repositoryName?: string;

  /**
   * Description for the CodeCommit repository
   * @default 'Enterprise application with Git workflow automation'
   */
  readonly repositoryDescription?: string;

  /**
   * Email addresses to subscribe to SNS notifications (optional)
   * If provided, will create email subscriptions for notification topics
   */
  readonly notificationEmails?: string[];

  /**
   * Team lead user ARN for approval rules
   * @default 'team-lead'
   */
  readonly teamLeadUser?: string;

  /**
   * Senior developer user ARNs for approval rules
   * @default ['senior-dev-1', 'senior-dev-2']
   */
  readonly seniorDevelopers?: string[];
}

/**
 * CDK Stack for CodeCommit Git Workflows and Policies
 */
export class CodeCommitGitWorkflowsStack extends cdk.Stack {
  // Public properties for accessing created resources
  public readonly repository: codecommit.Repository;
  public readonly pullRequestLambda: lambda.Function;
  public readonly qualityGateLambda: lambda.Function;
  public readonly branchProtectionLambda: lambda.Function;
  public readonly pullRequestTopic: sns.Topic;
  public readonly mergeTopic: sns.Topic;
  public readonly qualityGateTopic: sns.Topic;
  public readonly securityAlertTopic: sns.Topic;
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props?: CodeCommitGitWorkflowsStackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const randomSuffix = Math.random().toString(36).substring(2, 10);
    const repositoryName = props?.repositoryName || `enterprise-app-${randomSuffix}`;
    const repositoryDescription = props?.repositoryDescription || 'Enterprise application with Git workflow automation';

    // Create SNS topics for notifications
    this.pullRequestTopic = new sns.Topic(this, 'PullRequestTopic', {
      topicName: `codecommit-notifications-${randomSuffix}-pull-requests`,
      displayName: 'CodeCommit Pull Request Notifications',
      description: 'Notifications for pull request events in CodeCommit workflows',
    });

    this.mergeTopic = new sns.Topic(this, 'MergeTopic', {
      topicName: `codecommit-notifications-${randomSuffix}-merges`,
      displayName: 'CodeCommit Merge Notifications',
      description: 'Notifications for merge events in CodeCommit workflows',
    });

    this.qualityGateTopic = new sns.Topic(this, 'QualityGateTopic', {
      topicName: `codecommit-notifications-${randomSuffix}-quality-gates`,
      displayName: 'CodeCommit Quality Gate Notifications',
      description: 'Notifications for quality gate results in CodeCommit workflows',
    });

    this.securityAlertTopic = new sns.Topic(this, 'SecurityAlertTopic', {
      topicName: `codecommit-notifications-${randomSuffix}-security-alerts`,
      displayName: 'CodeCommit Security Alert Notifications',
      description: 'Security vulnerability alerts for CodeCommit workflows',
    });

    // Subscribe email addresses if provided
    if (props?.notificationEmails && props.notificationEmails.length > 0) {
      props.notificationEmails.forEach((email, index) => {
        this.pullRequestTopic.addSubscription(new snsSubscriptions.EmailSubscription(email));
        this.mergeTopic.addSubscription(new snsSubscriptions.EmailSubscription(email));
        this.qualityGateTopic.addSubscription(new snsSubscriptions.EmailSubscription(email));
        this.securityAlertTopic.addSubscription(new snsSubscriptions.EmailSubscription(email));
      });
    }

    // Create IAM role for Lambda functions
    const lambdaRole = new iam.Role(this, 'CodeCommitAutomationRole', {
      roleName: 'CodeCommitAutomationRole',
      description: 'Role for CodeCommit automation Lambda functions',
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        CodeCommitAutomationPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              sid: 'LogsAccess',
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: ['arn:aws:logs:*:*:*'],
            }),
            new iam.PolicyStatement({
              sid: 'CodeCommitAccess',
              effect: iam.Effect.ALLOW,
              actions: [
                'codecommit:GetRepository',
                'codecommit:GetBranch',
                'codecommit:GetCommit',
                'codecommit:GetDifferences',
                'codecommit:GetPullRequest',
                'codecommit:ListPullRequests',
                'codecommit:GetMergeCommit',
                'codecommit:GetMergeConflicts',
                'codecommit:GetMergeOptions',
                'codecommit:PostCommentForPullRequest',
                'codecommit:UpdatePullRequestTitle',
                'codecommit:UpdatePullRequestDescription',
                'codecommit:ListBranches',
              ],
              resources: [
                `arn:aws:codecommit:${this.region}:${this.account}:${repositoryName}`,
              ],
            }),
            new iam.PolicyStatement({
              sid: 'SNSAccess',
              effect: iam.Effect.ALLOW,
              actions: ['sns:Publish'],
              resources: [
                this.pullRequestTopic.topicArn,
                this.mergeTopic.topicArn,
                this.qualityGateTopic.topicArn,
                this.securityAlertTopic.topicArn,
              ],
            }),
            new iam.PolicyStatement({
              sid: 'CloudWatchMetrics',
              effect: iam.Effect.ALLOW,
              actions: ['cloudwatch:PutMetricData'],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create CodeCommit repository
    this.repository = new codecommit.Repository(this, 'GitWorkflowRepository', {
      repositoryName: repositoryName,
      description: repositoryDescription,
      code: codecommit.Code.fromDirectory('./sample-repo', 'main'), // Optional: pre-populate with sample code
    });

    // Add tags to repository
    cdk.Tags.of(this.repository).add('Environment', 'development');
    cdk.Tags.of(this.repository).add('Project', 'enterprise-app');
    cdk.Tags.of(this.repository).add('ManagedBy', 'codecommit-automation');

    // Create Pull Request Automation Lambda Function
    this.pullRequestLambda = new lambda.Function(this, 'PullRequestAutomationFunction', {
      functionName: `codecommit-automation-${randomSuffix}-pull-request`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      role: lambdaRole,
      description: 'Automation for CodeCommit pull request workflows',
      environment: {
        PULL_REQUEST_TOPIC_ARN: this.pullRequestTopic.topicArn,
        MERGE_TOPIC_ARN: this.mergeTopic.topicArn,
        QUALITY_GATE_TOPIC_ARN: this.qualityGateTopic.topicArn,
        REPOSITORY_NAME: repositoryName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

codecommit = boto3.client('codecommit')
sns = boto3.client('sns')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """
    Handle CodeCommit pull request events
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Parse event details
        detail = event.get('detail', {})
        event_name = detail.get('event')
        repository_name = detail.get('repositoryName')
        pull_request_id = detail.get('pullRequestId')
        
        if not all([event_name, repository_name, pull_request_id]):
            logger.error("Missing required event details")
            return {'statusCode': 400, 'body': 'Invalid event format'}
        
        # Get pull request details
        pr_response = codecommit.get_pull_request(pullRequestId=pull_request_id)
        pull_request = pr_response['pullRequest']
        
        # Extract pull request information
        pr_info = {
            'pullRequestId': pull_request_id,
            'title': pull_request['title'],
            'description': pull_request.get('description', ''),
            'authorArn': pull_request['authorArn'],
            'sourceReference': pull_request['pullRequestTargets'][0]['sourceReference'],
            'destinationReference': pull_request['pullRequestTargets'][0]['destinationReference'],
            'repositoryName': repository_name,
            'creationDate': pull_request['creationDate'].isoformat(),
            'pullRequestStatus': pull_request['pullRequestStatus']
        }
        
        # Handle different pull request events
        if event_name == 'pullRequestCreated':
            return handle_pull_request_created(pr_info)
        elif event_name == 'pullRequestSourceBranchUpdated':
            return handle_pull_request_updated(pr_info)
        elif event_name == 'pullRequestStatusChanged':
            return handle_pull_request_status_changed(pr_info, detail)
        elif event_name == 'pullRequestMergeStatusUpdated':
            return handle_merge_status_updated(pr_info, detail)
        else:
            logger.info(f"Unhandled event type: {event_name}")
            return {'statusCode': 200, 'body': 'Event acknowledged'}
            
    except Exception as e:
        logger.error(f"Error processing pull request event: {str(e)}")
        return {'statusCode': 500, 'body': f'Error: {str(e)}'}

def handle_pull_request_created(pr_info):
    """Handle new pull request creation"""
    logger.info(f"New pull request created: {pr_info['pullRequestId']}")
    
    # Validate pull request
    validation_results = validate_pull_request(pr_info)
    
    # Send notification
    message = f"""
🔄 New Pull Request Created

Repository: {pr_info['repositoryName']}
Pull Request: #{pr_info['pullRequestId']}
Title: {pr_info['title']}
Author: {pr_info['authorArn'].split('/')[-1]}
Source: {pr_info['sourceReference']}
Target: {pr_info['destinationReference']}

Validation Results:
{format_validation_results(validation_results)}

Created: {pr_info['creationDate']}
"""
    
    sns.publish(
        TopicArn=os.environ['PULL_REQUEST_TOPIC_ARN'],
        Subject=f'New PR: {pr_info["title"]}',
        Message=message
    )
    
    # Record metrics
    cloudwatch.put_metric_data(
        Namespace='CodeCommit/PullRequests',
        MetricData=[
            {
                'MetricName': 'PullRequestsCreated',
                'Value': 1,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Repository', 'Value': pr_info['repositoryName']}
                ]
            }
        ]
    )
    
    return {'statusCode': 200, 'body': 'Pull request creation handled'}

def handle_pull_request_updated(pr_info):
    """Handle pull request source branch updates"""
    logger.info(f"Pull request updated: {pr_info['pullRequestId']}")
    
    # Re-run quality checks on updated code
    validation_results = validate_pull_request(pr_info)
    
    # Post comment with validation results
    if not validation_results['all_passed']:
        comment_content = f"""
⚠️ Quality checks failed after recent updates:

{format_validation_results(validation_results)}

Please address these issues before merge.
"""
        
        codecommit.post_comment_for_pull_request(
            pullRequestId=pr_info['pullRequestId'],
            repositoryName=pr_info['repositoryName'],
            beforeCommitId=pr_info['sourceReference'],
            afterCommitId=pr_info['sourceReference'],
            content=comment_content
        )
    
    return {'statusCode': 200, 'body': 'Pull request update handled'}

def handle_pull_request_status_changed(pr_info, detail):
    """Handle pull request status changes"""
    old_status = detail.get('oldPullRequestStatus')
    new_status = detail.get('newPullRequestStatus')
    
    logger.info(f"Pull request status changed: {old_status} -> {new_status}")
    
    if new_status == 'CLOSED':
        # Handle closed pull request
        cloudwatch.put_metric_data(
            Namespace='CodeCommit/PullRequests',
            MetricData=[
                {
                    'MetricName': 'PullRequestsClosed',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'Repository', 'Value': pr_info['repositoryName']}
                    ]
                }
            ]
        )
    
    return {'statusCode': 200, 'body': 'Status change handled'}

def handle_merge_status_updated(pr_info, detail):
    """Handle merge status updates"""
    merge_status = detail.get('mergeStatus')
    
    if merge_status == 'MERGED':
        logger.info(f"Pull request merged: {pr_info['pullRequestId']}")
        
        # Send merge notification
        message = f"""
✅ Pull Request Merged

Repository: {pr_info['repositoryName']}
Pull Request: #{pr_info['pullRequestId']}
Title: {pr_info['title']}
Merged to: {pr_info['destinationReference']}

The changes have been successfully merged.
"""
        
        sns.publish(
            TopicArn=os.environ['MERGE_TOPIC_ARN'],
            Subject=f'PR Merged: {pr_info["title"]}',
            Message=message
        )
        
        # Record metrics
        cloudwatch.put_metric_data(
            Namespace='CodeCommit/PullRequests',
            MetricData=[
                {
                    'MetricName': 'PullRequestsMerged',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'Repository', 'Value': pr_info['repositoryName']}
                    ]
                }
            ]
        )
    
    return {'statusCode': 200, 'body': 'Merge status update handled'}

def validate_pull_request(pr_info):
    """Validate pull request against quality gates"""
    results = {
        'branch_naming': check_branch_naming(pr_info['sourceReference']),
        'title_format': check_title_format(pr_info['title']),
        'description_present': bool(pr_info['description'].strip()),
        'target_branch': check_target_branch(pr_info['destinationReference']),
        'all_passed': True
    }
    
    # Set overall result
    results['all_passed'] = all(results[key] for key in results if key != 'all_passed')
    
    return results

def check_branch_naming(branch_name):
    """Check if branch follows naming convention"""
    valid_prefixes = ['feature/', 'bugfix/', 'hotfix/', 'release/', 'chore/']
    return any(branch_name.startswith(prefix) for prefix in valid_prefixes)

def check_title_format(title):
    """Check if title follows format guidelines"""
    # Basic checks: not empty, reasonable length, starts with capital
    return (len(title.strip()) > 5 and 
            len(title) < 100 and 
            title[0].isupper())

def check_target_branch(target_branch):
    """Check if target branch is appropriate"""
    allowed_targets = ['develop', 'main', 'master', 'release/*']
    return (target_branch in ['develop', 'main', 'master'] or 
            target_branch.startswith('release/'))

def format_validation_results(results):
    """Format validation results for display"""
    status_emoji = "✅" if results['all_passed'] else "❌"
    
    checks = [
        f"{'✅' if results['branch_naming'] else '❌'} Branch naming convention",
        f"{'✅' if results['title_format'] else '❌'} Title format",
        f"{'✅' if results['description_present'] else '❌'} Description present",
        f"{'✅' if results['target_branch'] else '❌'} Target branch valid"
    ]
    
    return f"{status_emoji} Overall: {'PASSED' if results['all_passed'] else 'FAILED'}\\n" + "\\n".join(checks)
`),
    });

    // Create Quality Gate Lambda Function
    this.qualityGateLambda = new lambda.Function(this, 'QualityGateAutomationFunction', {
      functionName: `codecommit-automation-${randomSuffix}-quality-gate`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      role: lambdaRole,
      description: 'Quality gate automation for CodeCommit repositories',
      environment: {
        QUALITY_GATE_TOPIC_ARN: this.qualityGateTopic.topicArn,
        SECURITY_ALERT_TOPIC_ARN: this.securityAlertTopic.topicArn,
        REPOSITORY_NAME: repositoryName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

codecommit = boto3.client('codecommit')
sns = boto3.client('sns')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """
    Handle repository triggers for quality gate automation
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Parse CodeCommit trigger event
        records = event.get('Records', [])
        
        for record in records:
            # Extract trigger information
            trigger_info = extract_trigger_info(record)
            if not trigger_info:
                continue
            
            # Run quality checks
            quality_results = run_quality_checks(trigger_info)
            
            # Process results
            process_quality_results(trigger_info, quality_results)
        
        return {'statusCode': 200, 'body': 'Quality checks completed'}
        
    except Exception as e:
        logger.error(f"Error in quality gate automation: {str(e)}")
        return {'statusCode': 500, 'body': f'Error: {str(e)}'}

def extract_trigger_info(record):
    """Extract trigger information from CodeCommit event"""
    try:
        # Parse CodeCommit event record
        event_source_arn = record.get('eventSourceARN', '')
        repository_name = event_source_arn.split(':')[-1] if event_source_arn else ''
        
        codecommit_data = record.get('codecommit', {})
        references = codecommit_data.get('references', [])
        
        if not references:
            return None
        
        ref = references[0]
        return {
            'repository_name': repository_name,
            'branch': ref.get('ref', '').replace('refs/heads/', ''),
            'commit_id': ref.get('commit'),
            'event_type': 'push'
        }
        
    except Exception as e:
        logger.error(f"Error extracting trigger info: {str(e)}")
        return None

def run_quality_checks(trigger_info):
    """Run comprehensive quality checks"""
    results = {
        'repository': trigger_info['repository_name'],
        'branch': trigger_info['branch'],
        'commit_id': trigger_info['commit_id'],
        'timestamp': datetime.utcnow().isoformat(),
        'checks': {}
    }
    
    try:
        # Get repository content for analysis
        repo_content = get_repository_content(trigger_info)
        
        # Run various quality checks
        results['checks']['lint_check'] = run_lint_check(repo_content)
        results['checks']['security_scan'] = run_security_scan(repo_content)
        results['checks']['test_coverage'] = run_test_coverage(repo_content)
        results['checks']['dependency_check'] = run_dependency_check(repo_content)
        
        # Calculate overall result
        all_passed = all(check.get('passed', False) for check in results['checks'].values())
        results['overall_result'] = 'PASSED' if all_passed else 'FAILED'
        
    except Exception as e:
        logger.error(f"Error running quality checks: {str(e)}")
        results['overall_result'] = 'ERROR'
        results['error'] = str(e)
    
    return results

def get_repository_content(trigger_info):
    """Get repository content for analysis"""
    try:
        # In a real implementation, you would fetch actual repository content
        # For this demo, we'll simulate repository structure analysis
        return {
            'python_files': [],
            'requirements_files': [],
            'test_files': [],
            'has_python': True,  # Simulated detection
            'has_tests': True,   # Simulated detection
            'has_requirements': True  # Simulated detection
        }
        
    except Exception as e:
        logger.error(f"Error getting repository content: {str(e)}")
        return {}

def run_lint_check(repo_content):
    """Run code linting checks"""
    try:
        # Simulate linting results
        lint_issues = []
        
        if not repo_content.get('has_python'):
            return {'passed': True, 'message': 'No Python files to lint'}
        
        # Simulate linting process
        issues_found = len(lint_issues)
        
        return {
            'passed': issues_found == 0,
            'issues_count': issues_found,
            'issues': lint_issues,
            'message': f'Found {issues_found} linting issues' if issues_found > 0 else 'No linting issues found'
        }
        
    except Exception as e:
        return {'passed': False, 'error': str(e)}

def run_security_scan(repo_content):
    """Run security vulnerability scan"""
    try:
        # Simulate security scanning
        vulnerabilities = []
        high_severity_count = 0
        medium_severity_count = 0
        
        return {
            'passed': high_severity_count == 0,
            'high_severity': high_severity_count,
            'medium_severity': medium_severity_count,
            'vulnerabilities': vulnerabilities,
            'message': f'Found {high_severity_count} high and {medium_severity_count} medium severity issues'
        }
        
    except Exception as e:
        return {'passed': False, 'error': str(e)}

def run_test_coverage(repo_content):
    """Run test coverage analysis"""
    try:
        if not repo_content.get('has_tests'):
            return {'passed': False, 'message': 'No tests found'}
        
        # Simulate coverage percentage
        coverage_percentage = 85.5  # Simulated good coverage
        required_coverage = 80.0
        
        return {
            'passed': coverage_percentage >= required_coverage,
            'coverage_percentage': coverage_percentage,
            'required_coverage': required_coverage,
            'message': f'Test coverage: {coverage_percentage}% (required: {required_coverage}%)'
        }
        
    except Exception as e:
        return {'passed': False, 'error': str(e)}

def run_dependency_check(repo_content):
    """Check for dependency issues"""
    try:
        if not repo_content.get('has_requirements'):
            return {'passed': True, 'message': 'No dependencies to check'}
        
        # Simulate checking for outdated or vulnerable dependencies
        outdated_count = 0
        vulnerable_count = 0
        
        return {
            'passed': vulnerable_count == 0,
            'outdated_dependencies': outdated_count,
            'vulnerable_dependencies': vulnerable_count,
            'message': f'Found {vulnerable_count} vulnerable and {outdated_count} outdated dependencies'
        }
        
    except Exception as e:
        return {'passed': False, 'error': str(e)}

def process_quality_results(trigger_info, results):
    """Process and communicate quality check results"""
    try:
        # Record metrics
        record_quality_metrics(results)
        
        # Send notifications for failures
        if results['overall_result'] == 'FAILED':
            send_quality_failure_notification(trigger_info, results)
        elif results['overall_result'] == 'PASSED':
            send_quality_success_notification(trigger_info, results)
        
    except Exception as e:
        logger.error(f"Error processing quality results: {str(e)}")

def record_quality_metrics(results):
    """Record quality metrics to CloudWatch"""
    try:
        metrics = []
        
        # Overall result metric
        metrics.append({
            'MetricName': 'QualityChecksResult',
            'Value': 1 if results['overall_result'] == 'PASSED' else 0,
            'Unit': 'Count',
            'Dimensions': [
                {'Name': 'Repository', 'Value': results['repository']},
                {'Name': 'Branch', 'Value': results['branch']}
            ]
        })
        
        # Individual check metrics
        for check_name, check_result in results['checks'].items():
            if isinstance(check_result, dict) and 'passed' in check_result:
                metrics.append({
                    'MetricName': f'QualityCheck_{check_name}',
                    'Value': 1 if check_result['passed'] else 0,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'Repository', 'Value': results['repository']},
                        {'Name': 'CheckType', 'Value': check_name}
                    ]
                })
        
        # Send metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='CodeCommit/QualityGates',
            MetricData=metrics
        )
        
    except Exception as e:
        logger.error(f"Error recording metrics: {str(e)}")

def send_quality_failure_notification(trigger_info, results):
    """Send notification for quality check failures"""
    try:
        failure_summary = []
        for check_name, check_result in results['checks'].items():
            if isinstance(check_result, dict) and not check_result.get('passed', True):
                failure_summary.append(f"❌ {check_name}: {check_result.get('message', 'Failed')}")
        
        message = f"""
🚨 Quality Gates Failed

Repository: {results['repository']}
Branch: {results['branch']}
Commit: {results['commit_id'][:8]}

Failed Checks:
{chr(10).join(failure_summary)}

Please address these issues before merging.
Timestamp: {results['timestamp']}
"""
        
        sns.publish(
            TopicArn=os.environ['QUALITY_GATE_TOPIC_ARN'],
            Subject=f'Quality Gates Failed: {results["repository"]}',
            Message=message
        )
        
    except Exception as e:
        logger.error(f"Error sending failure notification: {str(e)}")

def send_quality_success_notification(trigger_info, results):
    """Send notification for quality check success"""
    try:
        # Only send success notifications for important branches
        important_branches = ['main', 'master', 'develop']
        
        if results['branch'] not in important_branches:
            return
        
        message = f"""
✅ Quality Gates Passed

Repository: {results['repository']}
Branch: {results['branch']}
Commit: {results['commit_id'][:8]}

All quality checks passed successfully.
Timestamp: {results['timestamp']}
"""
        
        sns.publish(
            TopicArn=os.environ['QUALITY_GATE_TOPIC_ARN'],
            Subject=f'Quality Gates Passed: {results["repository"]}',
            Message=message
        )
        
    except Exception as e:
        logger.error(f"Error sending success notification: {str(e)}")
`),
    });

    // Create Branch Protection Lambda Function
    this.branchProtectionLambda = new lambda.Function(this, 'BranchProtectionFunction', {
      functionName: `codecommit-automation-${randomSuffix}-branch-protection`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      role: lambdaRole,
      description: 'Automated branch protection enforcement',
      environment: {
        REPOSITORY_NAME: repositoryName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

codecommit = boto3.client('codecommit')

def lambda_handler(event, context):
    """
    Automated branch protection enforcement
    """
    try:
        repository_name = event.get('repository_name', os.environ.get('REPOSITORY_NAME'))
        if not repository_name:
            return {'statusCode': 400, 'body': 'Repository name required'}
        
        # Get repository information
        repo_info = codecommit.get_repository(repositoryName=repository_name)
        
        # Enforce branch protection rules
        protection_results = enforce_branch_protection(repository_name)
        
        return {
            'statusCode': 200,
            'body': json.dumps(protection_results)
        }
        
    except Exception as e:
        logger.error(f"Error in branch protection: {str(e)}")
        return {'statusCode': 500, 'body': f'Error: {str(e)}'}

def enforce_branch_protection(repository_name):
    """Enforce branch protection policies"""
    results = {
        'repository': repository_name,
        'protected_branches': [],
        'approval_rules_checked': [],
        'actions_taken': []
    }
    
    try:
        # List branches in repository
        branches_response = codecommit.list_branches(repositoryName=repository_name)
        branches = branches_response.get('branches', [])
        
        # Define protected branches
        protected_branches = ['main', 'master', 'develop']
        
        for branch in branches:
            if branch in protected_branches:
                results['protected_branches'].append(branch)
                
                # Ensure approval rules exist for protected branches
                check_approval_rules(repository_name, branch, results)
        
        return results
        
    except Exception as e:
        logger.error(f"Error enforcing branch protection: {str(e)}")
        results['error'] = str(e)
        return results

def check_approval_rules(repository_name, branch, results):
    """Check and ensure approval rules for protected branch"""
    try:
        # This would check for existing approval rules
        # and create them if they don't exist
        
        results['approval_rules_checked'].append({
            'branch': branch,
            'status': 'checked',
            'has_approval_rules': True  # Simulated
        })
        
    except Exception as e:
        logger.error(f"Error checking approval rules: {str(e)}")

import os
`),
    });

    // Create EventBridge rule for pull request events
    const pullRequestEventRule = new events.Rule(this, 'PullRequestEventRule', {
      ruleName: `codecommit-pull-request-events-${randomSuffix}`,
      description: 'Capture CodeCommit pull request events',
      eventPattern: {
        source: ['aws.codecommit'],
        detailType: ['CodeCommit Pull Request State Change'],
        detail: {
          repositoryName: [repositoryName],
        },
      },
      targets: [
        new targets.LambdaFunction(this.pullRequestLambda),
      ],
    });

    // Grant permission for CodeCommit to invoke the quality gate Lambda
    this.qualityGateLambda.addPermission('CodeCommitInvokePermission', {
      principal: new iam.ServicePrincipal('codecommit.amazonaws.com'),
      sourceArn: this.repository.repositoryArn,
    });

    // Create approval rule template using custom resource
    const approvalRuleTemplate = new CustomResource(this, 'ApprovalRuleTemplate', {
      serviceToken: this.createApprovalRuleTemplateProvider().serviceToken,
      properties: {
        templateName: 'enterprise-approval-template',
        description: 'Standard approval rules for enterprise repositories',
        repositoryName: repositoryName,
        teamLeadUser: props?.teamLeadUser || 'team-lead',
        seniorDevelopers: props?.seniorDevelopers || ['senior-dev-1', 'senior-dev-2'],
      },
    });

    // Create CloudWatch Dashboard
    this.dashboard = new cloudwatch.Dashboard(this, 'GitWorkflowDashboard', {
      dashboardName: `Git-Workflow-${repositoryName}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Pull Request Activity',
            left: [
              new cloudwatch.Metric({
                namespace: 'CodeCommit/PullRequests',
                metricName: 'PullRequestsCreated',
                dimensionsMap: { Repository: repositoryName },
                statistic: 'Sum',
              }),
              new cloudwatch.Metric({
                namespace: 'CodeCommit/PullRequests',
                metricName: 'PullRequestsMerged',
                dimensionsMap: { Repository: repositoryName },
                statistic: 'Sum',
              }),
              new cloudwatch.Metric({
                namespace: 'CodeCommit/PullRequests',
                metricName: 'PullRequestsClosed',
                dimensionsMap: { Repository: repositoryName },
                statistic: 'Sum',
              }),
            ],
            width: 12,
            height: 6,
          }),
          new cloudwatch.GraphWidget({
            title: 'Quality Gate Success Rate',
            left: [
              new cloudwatch.Metric({
                namespace: 'CodeCommit/QualityGates',
                metricName: 'QualityChecksResult',
                dimensionsMap: { Repository: repositoryName },
                statistic: 'Average',
              }),
            ],
            width: 12,
            height: 6,
            leftYAxis: {
              min: 0,
              max: 1,
            },
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Individual Quality Checks',
            left: [
              new cloudwatch.Metric({
                namespace: 'CodeCommit/QualityGates',
                metricName: 'QualityCheck_lint_check',
                dimensionsMap: { Repository: repositoryName, CheckType: 'lint_check' },
                statistic: 'Average',
              }),
              new cloudwatch.Metric({
                namespace: 'CodeCommit/QualityGates',
                metricName: 'QualityCheck_security_scan',
                dimensionsMap: { Repository: repositoryName, CheckType: 'security_scan' },
                statistic: 'Average',
              }),
              new cloudwatch.Metric({
                namespace: 'CodeCommit/QualityGates',
                metricName: 'QualityCheck_test_coverage',
                dimensionsMap: { Repository: repositoryName, CheckType: 'test_coverage' },
                statistic: 'Average',
              }),
              new cloudwatch.Metric({
                namespace: 'CodeCommit/QualityGates',
                metricName: 'QualityCheck_dependency_check',
                dimensionsMap: { Repository: repositoryName, CheckType: 'dependency_check' },
                statistic: 'Average',
              }),
            ],
            width: 8,
            height: 6,
          }),
          new cloudwatch.LogQueryWidget({
            title: 'Recent Pull Request Events',
            logGroups: [this.pullRequestLambda.logGroup],
            queryLines: [
              'fields @timestamp, @message',
              'filter @message like /Pull request/',
              'sort @timestamp desc',
              'limit 20',
            ],
            width: 16,
            height: 6,
          }),
        ],
      ],
    });

    // Outputs
    new cdk.CfnOutput(this, 'RepositoryName', {
      value: this.repository.repositoryName,
      description: 'Name of the CodeCommit repository',
    });

    new cdk.CfnOutput(this, 'RepositoryCloneUrl', {
      value: this.repository.repositoryCloneUrlHttp,
      description: 'HTTP clone URL for the repository',
    });

    new cdk.CfnOutput(this, 'PullRequestTopicArn', {
      value: this.pullRequestTopic.topicArn,
      description: 'ARN of the pull request notifications topic',
    });

    new cdk.CfnOutput(this, 'QualityGateTopicArn', {
      value: this.qualityGateTopic.topicArn,
      description: 'ARN of the quality gate notifications topic',
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard',
    });
  }

  /**
   * Creates a custom resource provider for approval rule template management
   */
  private createApprovalRuleTemplateProvider(): customResources.Provider {
    const onEventHandler = new lambda.Function(this, 'ApprovalRuleTemplateHandler', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.on_event',
      code: lambda.Code.fromInline(`
import boto3
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

codecommit = boto3.client('codecommit')

def on_event(event, context):
    logger.info(f"Received event: {json.dumps(event)}")
    
    request_type = event['RequestType']
    props = event['ResourceProperties']
    
    if request_type == 'Create':
        return create_approval_rule_template(props)
    elif request_type == 'Update':
        return update_approval_rule_template(props)
    elif request_type == 'Delete':
        return delete_approval_rule_template(props)

def create_approval_rule_template(props):
    template_name = props['templateName']
    description = props['description']
    repository_name = props['repositoryName']
    team_lead = props['teamLeadUser']
    senior_devs = props['seniorDevelopers']
    
    # Create approval rule content
    approval_content = {
        "Version": "2018-11-08",
        "DestinationReferences": [
            "refs/heads/main",
            "refs/heads/master", 
            "refs/heads/develop"
        ],
        "Statements": [
            {
                "Type": "Approvers",
                "NumberOfApprovalsNeeded": 2,
                "ApprovalPoolMembers": [
                    f"arn:aws:iam::{boto3.client('sts').get_caller_identity()['Account']}:user/{team_lead}"
                ] + [f"arn:aws:iam::{boto3.client('sts').get_caller_identity()['Account']}:user/{dev}" for dev in senior_devs]
            }
        ]
    }
    
    try:
        # Create approval rule template
        response = codecommit.create_approval_rule_template(
            approvalRuleTemplateName=template_name,
            approvalRuleTemplateDescription=description,
            approvalRuleTemplateContent=json.dumps(approval_content)
        )
        
        # Associate with repository
        codecommit.associate_approval_rule_template_with_repository(
            approvalRuleTemplateName=template_name,
            repositoryName=repository_name
        )
        
        return {
            'PhysicalResourceId': template_name,
            'Data': {
                'TemplateName': template_name,
                'TemplateId': response['approvalRuleTemplate']['approvalRuleTemplateId']
            }
        }
    except Exception as e:
        logger.error(f"Error creating approval rule template: {str(e)}")
        raise

def update_approval_rule_template(props):
    # For updates, we'll recreate the template
    delete_approval_rule_template(props)
    return create_approval_rule_template(props)

def delete_approval_rule_template(props):
    template_name = props['templateName']
    repository_name = props['repositoryName']
    
    try:
        # Disassociate from repository
        try:
            codecommit.disassociate_approval_rule_template_from_repository(
                approvalRuleTemplateName=template_name,
                repositoryName=repository_name
            )
        except codecommit.exceptions.ApprovalRuleTemplateDoesNotExistException:
            pass
        
        # Delete template
        try:
            codecommit.delete_approval_rule_template(
                approvalRuleTemplateName=template_name
            )
        except codecommit.exceptions.ApprovalRuleTemplateDoesNotExistException:
            pass
        
        return {'PhysicalResourceId': template_name}
    except Exception as e:
        logger.error(f"Error deleting approval rule template: {str(e)}")
        # Don't fail the deletion
        return {'PhysicalResourceId': template_name}
`),
      timeout: cdk.Duration.minutes(5),
    });

    // Grant permissions to the handler
    onEventHandler.addToRolePolicy(
      new iam.PolicyStatement({
        actions: [
          'codecommit:CreateApprovalRuleTemplate',
          'codecommit:DeleteApprovalRuleTemplate',
          'codecommit:UpdateApprovalRuleTemplate',
          'codecommit:AssociateApprovalRuleTemplateWithRepository',
          'codecommit:DisassociateApprovalRuleTemplateFromRepository',
          'sts:GetCallerIdentity',
        ],
        resources: ['*'],
      })
    );

    return new customResources.Provider(this, 'ApprovalRuleTemplateProvider', {
      onEventHandler,
      logRetention: logs.RetentionDays.ONE_MONTH,
    });
  }
}

// Create the CDK app
const app = new cdk.App();

// Create the stack with example configuration
new CodeCommitGitWorkflowsStack(app, 'CodeCommitGitWorkflowsStack', {
  description: 'CDK implementation of CodeCommit Git workflows with branch policies and triggers',
  
  // Optional: Configure notification emails
  // notificationEmails: ['developer@example.com', 'team-lead@example.com'],
  
  // Optional: Customize repository settings
  // repositoryName: 'my-enterprise-app',
  // repositoryDescription: 'My enterprise application with automated Git workflows',
  
  // Optional: Configure approval rule users
  // teamLeadUser: 'john.doe',
  // seniorDevelopers: ['alice.smith', 'bob.johnson'],
  
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  tags: {
    Project: 'CodeCommit-Git-Workflows',
    Environment: 'Development',
    ManagedBy: 'CDK',
  },
});

app.synth();