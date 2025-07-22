# Data Preparation Lambda Function for Quantum Computing Pipeline
# This function prepares and validates data for quantum optimization algorithms

import json
import boto3
import numpy as np
from datetime import datetime
import os

s3 = boto3.client('s3')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """Prepare and validate data for quantum optimization."""
    try:
        # Extract input parameters
        input_bucket = event.get('input_bucket')
        output_bucket = event.get('output_bucket')
        problem_type = event.get('problem_type', 'optimization')
        problem_size = event.get('problem_size', 4)
        
        print(f"Preparing data for {problem_type} problem of size {problem_size}")
        
        # Generate or load optimization problem data
        if problem_type == 'optimization':
            # Create quadratic optimization problem coefficients
            np.random.seed(42)  # For reproducible results
            linear_coeffs = np.random.uniform(-2, 2, problem_size)
            quadratic_matrix = np.random.uniform(-1, 1, (problem_size, problem_size))
            # Ensure symmetric matrix for valid optimization
            quadratic_matrix = (quadratic_matrix + quadratic_matrix.T) / 2
            
            problem_data = {
                'linear_coefficients': linear_coeffs.tolist(),
                'quadratic_matrix': quadratic_matrix.tolist(),
                'problem_size': problem_size,
                'problem_type': problem_type,
                'created_at': datetime.utcnow().isoformat(),
                'project_name': os.environ.get('PROJECT_NAME', '${project_name}')
            }
        
        elif problem_type == 'chemistry':
            # Molecular Hamiltonian simulation parameters
            problem_data = {
                'molecule': 'H2',
                'bond_length': 0.74,
                'basis_set': 'sto-3g',
                'active_space': [2, 2],  # electrons, orbitals
                'problem_size': problem_size,
                'problem_type': problem_type,
                'created_at': datetime.utcnow().isoformat(),
                'project_name': os.environ.get('PROJECT_NAME', '${project_name}')
            }
        
        # Validate problem constraints
        validation_result = validate_quantum_problem(problem_data)
        if not validation_result['valid']:
            raise ValueError(f"Problem validation failed: {validation_result['error']}")
        
        # Store prepared data in S3
        data_key = f"prepared_data_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.json"
        s3.put_object(
            Bucket=input_bucket,
            Key=data_key,
            Body=json.dumps(problem_data, indent=2)
        )
        
        # Send metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='QuantumPipeline',
            MetricData=[
                {
                    'MetricName': 'ProblemsProcessed',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'ProblemType', 'Value': problem_type},
                        {'Name': 'ProblemSize', 'Value': str(problem_size)}
                    ]
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Data preparation completed successfully',
                'data_key': data_key,
                'problem_type': problem_type,
                'problem_size': problem_size,
                'validation': validation_result
            })
        }
        
    except Exception as e:
        print(f"Error in data preparation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def validate_quantum_problem(problem_data):
    """Validate quantum problem constraints and requirements."""
    try:
        problem_size = problem_data['problem_size']
        problem_type = problem_data['problem_type']
        
        # Check problem size constraints
        if problem_size < 2 or problem_size > 20:
            return {'valid': False, 'error': 'Problem size must be between 2 and 20 qubits'}
        
        # Validate problem-specific constraints
        if problem_type == 'optimization':
            if len(problem_data['linear_coefficients']) != problem_size:
                return {'valid': False, 'error': 'Linear coefficients size mismatch'}
            
            quad_matrix = np.array(problem_data['quadratic_matrix'])
            if quad_matrix.shape != (problem_size, problem_size):
                return {'valid': False, 'error': 'Quadratic matrix dimension mismatch'}
        
        return {'valid': True, 'error': None}
        
    except Exception as e:
        return {'valid': False, 'error': f'Validation error: {str(e)}'}