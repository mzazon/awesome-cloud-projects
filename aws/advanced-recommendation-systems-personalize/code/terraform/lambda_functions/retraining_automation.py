import json
import boto3
import os
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
personalize = boto3.client('personalize')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """Automated retraining function for Personalize solutions"""
    
    logger.info(f"Starting automated retraining process at {datetime.now()}")
    
    # Get solution ARNs from environment variables
    solutions = {
        'user_personalization': os.environ.get('USER_PERSONALIZATION_ARN'),
        'similar_items': os.environ.get('SIMILAR_ITEMS_ARN'),
        'trending_now': os.environ.get('TRENDING_NOW_ARN'),
        'popularity': os.environ.get('POPULARITY_ARN')
    }
    
    retraining_results = []
    success_count = 0
    failure_count = 0
    
    for solution_name, solution_arn in solutions.items():
        if solution_arn:
            try:
                logger.info(f"Starting retraining for {solution_name}: {solution_arn}")
                
                # Check if solution exists and is active
                try:
                    solution_response = personalize.describe_solution(solutionArn=solution_arn)
                    solution_status = solution_response['solution']['status']
                    
                    if solution_status != 'ACTIVE':
                        logger.warning(f"Solution {solution_name} is not ACTIVE (status: {solution_status}). Skipping retraining.")
                        retraining_results.append({
                            'solutionName': solution_name,
                            'solutionArn': solution_arn,
                            'status': 'SKIPPED',
                            'reason': f'Solution status is {solution_status}, not ACTIVE'
                        })
                        continue
                        
                except Exception as e:
                    logger.error(f"Error checking solution status for {solution_name}: {str(e)}")
                    retraining_results.append({
                        'solutionName': solution_name,
                        'solutionArn': solution_arn,
                        'status': 'FAILED',
                        'error': f'Failed to check solution status: {str(e)}'
                    })
                    failure_count += 1
                    continue
                
                # Create new solution version for retraining
                response = personalize.create_solution_version(
                    solutionArn=solution_arn,
                    trainingMode='UPDATE'  # Incremental training
                )
                
                solution_version_arn = response['solutionVersionArn']
                
                retraining_results.append({
                    'solutionName': solution_name,
                    'solutionArn': solution_arn,
                    'solutionVersionArn': solution_version_arn,
                    'status': 'INITIATED',
                    'trainingMode': 'UPDATE',
                    'timestamp': datetime.now().isoformat()
                })
                
                success_count += 1
                logger.info(f"Successfully initiated retraining for {solution_name}")
                
                # Send success metric to CloudWatch
                send_retraining_metric(solution_name, 'Success', 1)
                
            except personalize.exceptions.ResourceNotFoundException:
                error_msg = f"Solution not found: {solution_arn}"
                logger.error(error_msg)
                retraining_results.append({
                    'solutionName': solution_name,
                    'solutionArn': solution_arn,
                    'status': 'FAILED',
                    'error': error_msg
                })
                failure_count += 1
                send_retraining_metric(solution_name, 'NotFound', 1)
                
            except personalize.exceptions.InvalidInputException as e:
                error_msg = f"Invalid input for retraining {solution_name}: {str(e)}"
                logger.error(error_msg)
                retraining_results.append({
                    'solutionName': solution_name,
                    'solutionArn': solution_arn,
                    'status': 'FAILED',
                    'error': error_msg
                })
                failure_count += 1
                send_retraining_metric(solution_name, 'InvalidInput', 1)
                
            except personalize.exceptions.ResourceInUseException as e:
                error_msg = f"Solution {solution_name} is currently in use: {str(e)}"
                logger.warning(error_msg)
                retraining_results.append({
                    'solutionName': solution_name,
                    'solutionArn': solution_arn,
                    'status': 'SKIPPED',
                    'reason': error_msg
                })
                send_retraining_metric(solution_name, 'InUse', 1)
                
            except Exception as e:
                error_msg = f"Unexpected error retraining {solution_name}: {str(e)}"
                logger.error(error_msg)
                retraining_results.append({
                    'solutionName': solution_name,
                    'solutionArn': solution_arn,
                    'status': 'FAILED',
                    'error': error_msg
                })
                failure_count += 1
                send_retraining_metric(solution_name, 'UnexpectedError', 1)
        else:
            logger.warning(f"No ARN configured for solution: {solution_name}")
            retraining_results.append({
                'solutionName': solution_name,
                'status': 'FAILED',
                'error': 'Solution ARN not configured in environment variables'
            })
            failure_count += 1
    
    # Send overall metrics
    send_overall_metrics(success_count, failure_count)
    
    # Prepare response
    response_body = {
        'message': 'Retraining process completed',
        'timestamp': datetime.now().isoformat(),
        'summary': {
            'total_solutions': len(solutions),
            'successful_initiations': success_count,
            'failures': failure_count,
            'skipped': len([r for r in retraining_results if r.get('status') == 'SKIPPED'])
        },
        'results': retraining_results
    }
    
    logger.info(f"Retraining process completed. Success: {success_count}, Failures: {failure_count}")
    
    return {
        'statusCode': 200,
        'body': json.dumps(response_body, default=str)
    }

def send_retraining_metric(solution_name, status, value):
    """Send retraining metrics to CloudWatch"""
    try:
        cloudwatch.put_metric_data(
            Namespace='PersonalizeRetraining',
            MetricData=[
                {
                    'MetricName': 'RetrainingAttempts',
                    'Dimensions': [
                        {'Name': 'SolutionName', 'Value': solution_name},
                        {'Name': 'Status', 'Value': status}
                    ],
                    'Value': value,
                    'Unit': 'Count',
                    'Timestamp': datetime.now()
                }
            ]
        )
    except Exception as e:
        logger.error(f"Error sending metric for {solution_name}: {str(e)}")

def send_overall_metrics(success_count, failure_count):
    """Send overall retraining metrics to CloudWatch"""
    try:
        metric_data = []
        
        if success_count > 0:
            metric_data.append({
                'MetricName': 'SuccessfulRetrainings',
                'Value': success_count,
                'Unit': 'Count',
                'Timestamp': datetime.now()
            })
        
        if failure_count > 0:
            metric_data.append({
                'MetricName': 'FailedRetrainings',
                'Value': failure_count,
                'Unit': 'Count',
                'Timestamp': datetime.now()
            })
        
        # Always send total retraining runs
        metric_data.append({
            'MetricName': 'TotalRetrainingRuns',
            'Value': 1,
            'Unit': 'Count',
            'Timestamp': datetime.now()
        })
        
        if metric_data:
            cloudwatch.put_metric_data(
                Namespace='PersonalizeRetraining',
                MetricData=metric_data
            )
            
    except Exception as e:
        logger.error(f"Error sending overall metrics: {str(e)}")

def check_solution_version_status(solution_version_arn):
    """Check the status of a solution version (utility function for monitoring)"""
    try:
        response = personalize.describe_solution_version(solutionVersionArn=solution_version_arn)
        return response['solutionVersion']['status']
    except Exception as e:
        logger.error(f"Error checking solution version status: {str(e)}")
        return None