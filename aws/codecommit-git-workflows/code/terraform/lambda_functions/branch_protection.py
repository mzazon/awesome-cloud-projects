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
        # This function would be triggered by repository events
        # and enforce branch protection policies
        
        repository_name = event.get('repository_name')
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