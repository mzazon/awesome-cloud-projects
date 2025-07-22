"""
Lambda function for CodeCommit pull request automation.

This function handles CodeCommit pull request events including creation, updates,
status changes, and merge operations. It provides automated validation, notifications,
and workflow management for enterprise Git processes.
"""

import json
import boto3
import logging
import os
from datetime import datetime
from typing import Dict, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
codecommit = boto3.client('codecommit')
sns = boto3.client('sns')
cloudwatch = boto3.client('cloudwatch')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Handle CodeCommit pull request events.
    
    Args:
        event: EventBridge event containing pull request details
        context: Lambda context object
        
    Returns:
        Response dictionary with status code and message
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


def handle_pull_request_created(pr_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle new pull request creation.
    
    Args:
        pr_info: Dictionary containing pull request information
        
    Returns:
        Response dictionary with processing status
    """
    logger.info(f"New pull request created: {pr_info['pullRequestId']}")
    
    # Validate pull request
    validation_results = validate_pull_request(pr_info)
    
    # Send notification
    message = f"""🔄 New Pull Request Created

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


def handle_pull_request_updated(pr_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle pull request source branch updates.
    
    Args:
        pr_info: Dictionary containing pull request information
        
    Returns:
        Response dictionary with processing status
    """
    logger.info(f"Pull request updated: {pr_info['pullRequestId']}")
    
    # Re-run quality checks on updated code
    validation_results = validate_pull_request(pr_info)
    
    # Post comment with validation results if there are issues
    if not validation_results['all_passed']:
        comment_content = f"""⚠️ Quality checks failed after recent updates:

{format_validation_results(validation_results)}

Please address these issues before merge.
"""
        
        try:
            codecommit.post_comment_for_pull_request(
                pullRequestId=pr_info['pullRequestId'],
                repositoryName=pr_info['repositoryName'],
                beforeCommitId=pr_info['sourceReference'],
                afterCommitId=pr_info['sourceReference'],
                content=comment_content
            )
        except Exception as e:
            logger.warning(f"Failed to post comment: {str(e)}")
    
    return {'statusCode': 200, 'body': 'Pull request update handled'}


def handle_pull_request_status_changed(pr_info: Dict[str, Any], detail: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle pull request status changes.
    
    Args:
        pr_info: Dictionary containing pull request information
        detail: Event detail containing status change information
        
    Returns:
        Response dictionary with processing status
    """
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


def handle_merge_status_updated(pr_info: Dict[str, Any], detail: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle merge status updates.
    
    Args:
        pr_info: Dictionary containing pull request information
        detail: Event detail containing merge status information
        
    Returns:
        Response dictionary with processing status
    """
    merge_status = detail.get('mergeStatus')
    
    if merge_status == 'MERGED':
        logger.info(f"Pull request merged: {pr_info['pullRequestId']}")
        
        # Send merge notification
        message = f"""✅ Pull Request Merged

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


def validate_pull_request(pr_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Validate pull request against quality gates.
    
    Args:
        pr_info: Dictionary containing pull request information
        
    Returns:
        Dictionary containing validation results
    """
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


def check_branch_naming(branch_name: str) -> bool:
    """
    Check if branch follows naming convention.
    
    Args:
        branch_name: Name of the source branch
        
    Returns:
        True if branch name follows convention, False otherwise
    """
    valid_prefixes = ['feature/', 'bugfix/', 'hotfix/', 'release/', 'chore/']
    return any(branch_name.startswith(prefix) for prefix in valid_prefixes)


def check_title_format(title: str) -> bool:
    """
    Check if title follows format guidelines.
    
    Args:
        title: Pull request title
        
    Returns:
        True if title format is valid, False otherwise
    """
    # Basic checks: not empty, reasonable length, starts with capital
    return (len(title.strip()) > 5 and 
            len(title) < 100 and 
            title[0].isupper())


def check_target_branch(target_branch: str) -> bool:
    """
    Check if target branch is appropriate.
    
    Args:
        target_branch: Name of the target branch
        
    Returns:
        True if target branch is valid, False otherwise
    """
    allowed_targets = ['develop', 'main', 'master']
    return (target_branch in allowed_targets or 
            target_branch.startswith('release/'))


def format_validation_results(results: Dict[str, Any]) -> str:
    """
    Format validation results for display.
    
    Args:
        results: Dictionary containing validation results
        
    Returns:
        Formatted string representation of validation results
    """
    status_emoji = "✅" if results['all_passed'] else "❌"
    
    checks = [
        f"{'✅' if results['branch_naming'] else '❌'} Branch naming convention",
        f"{'✅' if results['title_format'] else '❌'} Title format",
        f"{'✅' if results['description_present'] else '❌'} Description present",
        f"{'✅' if results['target_branch'] else '❌'} Target branch valid"
    ]
    
    return f"{status_emoji} Overall: {'PASSED' if results['all_passed'] else 'FAILED'}\n" + "\n".join(checks)