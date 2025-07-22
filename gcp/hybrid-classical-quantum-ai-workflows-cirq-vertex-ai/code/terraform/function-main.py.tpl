"""
Hybrid Quantum-Classical Portfolio Optimization Cloud Function

This Cloud Function orchestrates the hybrid quantum-classical workflow for
portfolio optimization using Cirq and Vertex AI.
"""

import functions_framework
from google.cloud import storage
from google.cloud import aiplatform
from google.cloud import bigquery
import json
import subprocess
import sys
import os
import tempfile
import numpy as np
import logging
from datetime import datetime
from typing import Dict, Any, Optional

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment variables
PROJECT_ID = os.environ.get('PROJECT_ID', '${project_id}')
BUCKET_NAME = os.environ.get('BUCKET_NAME', '${bucket_name}')
DEFAULT_PORTFOLIO_SIZE = int(os.environ.get('DEFAULT_PORTFOLIO_SIZE', '8'))
DEFAULT_RISK_AVERSION = float(os.environ.get('DEFAULT_RISK_AVERSION', '1.0'))
QUANTUM_PROCESSOR_ID = os.environ.get('QUANTUM_PROCESSOR_ID', '')
ENABLE_QUANTUM_PROCESSOR = os.environ.get('ENABLE_QUANTUM_PROCESSOR', 'false').lower() == 'true'


@functions_framework.http
def orchestrate_hybrid_workflow(request):
    """
    Main entry point for hybrid quantum-classical portfolio optimization.
    
    Args:
        request: HTTP request object containing portfolio optimization parameters
        
    Returns:
        JSON response with optimization results
    """
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        if not request_json:
            return {'error': 'No JSON data provided'}, 400
        
        logger.info(f"Received optimization request: {request_json}")
        
        # Initialize clients
        storage_client = storage.Client()
        bq_client = bigquery.Client()
        bucket = storage_client.bucket(BUCKET_NAME)
        
        # Extract parameters
        portfolio_data = request_json.get('portfolio_data', {})
        n_assets = portfolio_data.get('n_assets', DEFAULT_PORTFOLIO_SIZE)
        risk_aversion = portfolio_data.get('risk_aversion', DEFAULT_RISK_AVERSION)
        trigger_type = portfolio_data.get('trigger_type', 'manual')
        
        logger.info(f"Processing portfolio optimization: {n_assets} assets, risk_aversion={risk_aversion}")
        
        # Step 1: Load or generate market data
        market_data = load_or_generate_market_data(bucket, n_assets)
        
        # Step 2: Run classical risk model
        classical_results = run_classical_risk_model(market_data, risk_aversion)
        
        # Step 3: Run quantum optimization
        quantum_results = run_quantum_optimization(
            market_data, 
            classical_results, 
            risk_aversion
        )
        
        # Step 4: Calculate hybrid metrics
        hybrid_metrics = calculate_hybrid_metrics(classical_results, quantum_results)
        
        # Step 5: Store results
        results = {
            'timestamp': datetime.now().isoformat(),
            'trigger_type': trigger_type,
            'portfolio_config': {
                'n_assets': n_assets,
                'risk_aversion': risk_aversion
            },
            'classical_results': classical_results,
            'quantum_results': quantum_results,
            'hybrid_metrics': hybrid_metrics,
            'performance_score': calculate_performance_score(hybrid_metrics)
        }
        
        # Save to Cloud Storage
        save_results_to_storage(bucket, results)
        
        # Save to BigQuery
        save_results_to_bigquery(bq_client, results)
        
        logger.info("Optimization workflow completed successfully")
        
        return {
            'status': 'success',
            'results': results,
            'message': 'Hybrid quantum-classical optimization completed'
        }
        
    except Exception as e:
        logger.error(f"Error in optimization workflow: {str(e)}")
        return {
            'status': 'error',
            'error': str(e),
            'message': 'Optimization workflow failed'
        }, 500


def load_or_generate_market_data(bucket, n_assets: int) -> Dict[str, Any]:
    """
    Load market data from storage or generate synthetic data.
    
    Args:
        bucket: Cloud Storage bucket object
        n_assets: Number of assets in portfolio
        
    Returns:
        Dictionary containing market data
    """
    try:
        # Try to load existing market data
        blob = bucket.blob('data/market_data.json')
        if blob.exists():
            market_data = json.loads(blob.download_as_text())
            logger.info("Loaded existing market data from storage")
        else:
            # Generate synthetic market data
            market_data = generate_synthetic_market_data(n_assets)
            
            # Save generated data
            blob.upload_from_string(json.dumps(market_data, indent=2))
            logger.info("Generated and saved synthetic market data")
        
        return market_data
        
    except Exception as e:
        logger.warning(f"Error loading market data: {e}. Generating synthetic data.")
        return generate_synthetic_market_data(n_assets)


def generate_synthetic_market_data(n_assets: int) -> Dict[str, Any]:
    """Generate synthetic market data for demonstration."""
    np.random.seed(42)
    
    # Generate asset returns
    expected_returns = np.random.uniform(0.05, 0.15, n_assets).tolist()
    
    # Generate correlation matrix
    correlation_matrix = np.random.uniform(0.1, 0.7, (n_assets, n_assets))
    correlation_matrix = (correlation_matrix + correlation_matrix.T) / 2
    np.fill_diagonal(correlation_matrix, 1.0)
    
    # Generate volatilities
    volatilities = np.random.uniform(0.1, 0.3, n_assets).tolist()
    
    # Create covariance matrix
    covariance_matrix = np.outer(volatilities, volatilities) * correlation_matrix
    
    return {
        'n_assets': n_assets,
        'expected_returns': expected_returns,
        'volatilities': volatilities,
        'correlation_matrix': correlation_matrix.tolist(),
        'covariance_matrix': covariance_matrix.tolist(),
        'timestamp': datetime.now().isoformat()
    }


def run_classical_risk_model(market_data: Dict[str, Any], risk_aversion: float) -> Dict[str, Any]:
    """
    Run classical risk modeling and portfolio optimization.
    
    Args:
        market_data: Market data dictionary
        risk_aversion: Risk aversion parameter
        
    Returns:
        Classical optimization results
    """
    logger.info("Running classical risk model")
    
    # Extract data
    expected_returns = np.array(market_data['expected_returns'])
    covariance_matrix = np.array(market_data['covariance_matrix'])
    n_assets = len(expected_returns)
    
    # Simple mean-variance optimization (Markowitz)
    # For demonstration, using equal weights with risk adjustment
    base_weights = np.ones(n_assets) / n_assets
    
    # Adjust weights based on expected returns and risk
    risk_adjusted_weights = base_weights * expected_returns
    risk_adjusted_weights = risk_adjusted_weights / np.sum(risk_adjusted_weights)
    
    # Calculate portfolio metrics
    portfolio_return = np.dot(risk_adjusted_weights, expected_returns)
    portfolio_risk = np.sqrt(np.dot(risk_adjusted_weights, np.dot(covariance_matrix, risk_adjusted_weights)))
    sharpe_ratio = portfolio_return / portfolio_risk if portfolio_risk > 0 else 0
    
    return {
        'method': 'classical_markowitz',
        'weights': risk_adjusted_weights.tolist(),
        'expected_return': float(portfolio_return),
        'portfolio_risk': float(portfolio_risk),
        'sharpe_ratio': float(sharpe_ratio),
        'diversification_ratio': float(1.0 / np.sum(risk_adjusted_weights ** 2)),
        'timestamp': datetime.now().isoformat()
    }


def run_quantum_optimization(market_data: Dict[str, Any], 
                           classical_results: Dict[str, Any], 
                           risk_aversion: float) -> Dict[str, Any]:
    """
    Run quantum portfolio optimization using QAOA.
    
    Args:
        market_data: Market data dictionary
        classical_results: Results from classical optimization
        risk_aversion: Risk aversion parameter
        
    Returns:
        Quantum optimization results
    """
    logger.info("Running quantum optimization")
    
    try:
        # Import quantum libraries
        import cirq
        import cirq_google
        
        # Extract data
        expected_returns = np.array(market_data['expected_returns'])
        covariance_matrix = np.array(market_data['covariance_matrix'])
        n_assets = len(expected_returns)
        
        # Create QUBO formulation
        qubo_matrix = create_portfolio_qubo(expected_returns, covariance_matrix, risk_aversion)
        
        # Run QAOA optimization
        best_result = optimize_with_qaoa(qubo_matrix, n_assets)
        
        # Calculate quantum portfolio metrics
        quantum_weights = best_result['weights']
        quantum_return = np.dot(quantum_weights, expected_returns)
        quantum_risk = np.sqrt(np.dot(quantum_weights, np.dot(covariance_matrix, quantum_weights)))
        quantum_sharpe = quantum_return / quantum_risk if quantum_risk > 0 else 0
        
        return {
            'method': 'quantum_qaoa',
            'weights': quantum_weights.tolist(),
            'expected_return': float(quantum_return),
            'portfolio_risk': float(quantum_risk),
            'sharpe_ratio': float(quantum_sharpe),
            'qaoa_cost': best_result['cost'],
            'qaoa_parameters': {
                'beta': best_result['beta'],
                'gamma': best_result['gamma']
            },
            'quantum_advantage': float(quantum_sharpe - classical_results['sharpe_ratio']),
            'processor_used': 'simulator' if not ENABLE_QUANTUM_PROCESSOR else QUANTUM_PROCESSOR_ID,
            'timestamp': datetime.now().isoformat()
        }
        
    except ImportError as e:
        logger.error(f"Quantum libraries not available: {e}")
        # Fallback to classical optimization with quantum-inspired heuristics
        return run_quantum_inspired_optimization(market_data, classical_results, risk_aversion)
    
    except Exception as e:
        logger.error(f"Error in quantum optimization: {e}")
        # Fallback to classical optimization
        return run_quantum_inspired_optimization(market_data, classical_results, risk_aversion)


def create_portfolio_qubo(expected_returns: np.ndarray, 
                         covariance_matrix: np.ndarray, 
                         risk_aversion: float) -> np.ndarray:
    """Create QUBO formulation for portfolio optimization."""
    n_assets = len(expected_returns)
    
    # QUBO matrix: H = μᵀx - λ(xᵀΣx)
    Q = np.outer(expected_returns, expected_returns)
    Q -= risk_aversion * covariance_matrix
    
    return Q


def optimize_with_qaoa(qubo_matrix: np.ndarray, n_assets: int) -> Dict[str, Any]:
    """Optimize portfolio using QAOA algorithm."""
    import cirq
    
    best_result = None
    best_cost = float('inf')
    
    # Grid search over QAOA parameters (simplified)
    for beta in np.linspace(0, np.pi/2, 3):  # Reduced for demo
        for gamma in np.linspace(0, np.pi, 3):  # Reduced for demo
            
            # Create QAOA circuit
            circuit = create_qaoa_circuit(qubo_matrix, beta, gamma, n_assets)
            
            # Run simulation
            simulator = cirq.Simulator()
            result = simulator.run(circuit, repetitions=100)  # Reduced for demo
            
            # Extract portfolio weights
            weights = extract_portfolio_weights(result.measurements, n_assets)
            
            # Calculate cost
            cost = calculate_portfolio_cost(weights, qubo_matrix)
            
            if cost < best_cost:
                best_cost = cost
                best_result = {
                    'weights': weights,
                    'cost': cost,
                    'beta': beta,
                    'gamma': gamma
                }
    
    return best_result


def create_qaoa_circuit(qubo_matrix: np.ndarray, beta: float, gamma: float, n_assets: int) -> 'cirq.Circuit':
    """Create QAOA circuit for portfolio optimization."""
    import cirq
    
    qubits = cirq.GridQubit.rect(1, n_assets)
    circuit = cirq.Circuit()
    
    # Initial superposition
    circuit.append([cirq.H(q) for q in qubits])
    
    # Problem Hamiltonian
    for i in range(n_assets):
        for j in range(i, n_assets):
            if i == j:
                circuit.append(cirq.rz(gamma * qubo_matrix[i, j])(qubits[i]))
            else:
                circuit.append(cirq.CNOT(qubits[i], qubits[j]))
                circuit.append(cirq.rz(gamma * qubo_matrix[i, j])(qubits[j]))
                circuit.append(cirq.CNOT(qubits[i], qubits[j]))
    
    # Mixer Hamiltonian
    circuit.append([cirq.rx(2 * beta)(q) for q in qubits])
    
    # Measurement
    circuit.append([cirq.measure(q, key=f'q{i}') for i, q in enumerate(qubits)])
    
    return circuit


def extract_portfolio_weights(measurements: Dict, n_assets: int) -> np.ndarray:
    """Extract normalized portfolio weights from quantum measurements."""
    weights = np.zeros(n_assets)
    
    for i in range(n_assets):
        key = f'q{i}'
        if key in measurements:
            weights[i] = np.mean(measurements[key])
    
    # Normalize weights
    total_weight = np.sum(weights)
    if total_weight > 0:
        weights = weights / total_weight
    else:
        weights = np.ones(n_assets) / n_assets
    
    return weights


def calculate_portfolio_cost(weights: np.ndarray, qubo_matrix: np.ndarray) -> float:
    """Calculate portfolio cost function."""
    return float(np.dot(weights, np.dot(qubo_matrix, weights)))


def run_quantum_inspired_optimization(market_data: Dict[str, Any], 
                                    classical_results: Dict[str, Any], 
                                    risk_aversion: float) -> Dict[str, Any]:
    """Fallback quantum-inspired optimization when quantum computing is unavailable."""
    logger.info("Running quantum-inspired optimization fallback")
    
    # Use classical results as base and apply quantum-inspired perturbations
    classical_weights = np.array(classical_results['weights'])
    
    # Apply random perturbations inspired by quantum superposition
    np.random.seed(42)
    perturbations = np.random.normal(0, 0.1, len(classical_weights))
    quantum_inspired_weights = classical_weights + perturbations
    
    # Ensure non-negative and normalized weights
    quantum_inspired_weights = np.maximum(quantum_inspired_weights, 0)
    quantum_inspired_weights = quantum_inspired_weights / np.sum(quantum_inspired_weights)
    
    # Calculate metrics
    expected_returns = np.array(market_data['expected_returns'])
    covariance_matrix = np.array(market_data['covariance_matrix'])
    
    portfolio_return = np.dot(quantum_inspired_weights, expected_returns)
    portfolio_risk = np.sqrt(np.dot(quantum_inspired_weights, np.dot(covariance_matrix, quantum_inspired_weights)))
    sharpe_ratio = portfolio_return / portfolio_risk if portfolio_risk > 0 else 0
    
    return {
        'method': 'quantum_inspired_fallback',
        'weights': quantum_inspired_weights.tolist(),
        'expected_return': float(portfolio_return),
        'portfolio_risk': float(portfolio_risk),
        'sharpe_ratio': float(sharpe_ratio),
        'quantum_advantage': float(sharpe_ratio - classical_results['sharpe_ratio']),
        'processor_used': 'quantum_inspired_simulation',
        'timestamp': datetime.now().isoformat()
    }


def calculate_hybrid_metrics(classical_results: Dict[str, Any], 
                           quantum_results: Dict[str, Any]) -> Dict[str, Any]:
    """Calculate hybrid performance metrics comparing classical and quantum approaches."""
    
    return {
        'return_improvement': quantum_results['expected_return'] - classical_results['expected_return'],
        'risk_difference': quantum_results['portfolio_risk'] - classical_results['portfolio_risk'],
        'sharpe_improvement': quantum_results['sharpe_ratio'] - classical_results['sharpe_ratio'],
        'quantum_advantage_score': calculate_quantum_advantage_score(classical_results, quantum_results),
        'diversification_comparison': {
            'classical': classical_results['diversification_ratio'],
            'quantum': 1.0 / np.sum(np.array(quantum_results['weights']) ** 2)
        },
        'weight_difference_l2': float(np.linalg.norm(
            np.array(quantum_results['weights']) - np.array(classical_results['weights'])
        ))
    }


def calculate_quantum_advantage_score(classical_results: Dict[str, Any], 
                                    quantum_results: Dict[str, Any]) -> float:
    """Calculate overall quantum advantage score."""
    # Weighted combination of improvements
    return_weight = 0.4
    risk_weight = 0.3
    sharpe_weight = 0.3
    
    return_improvement = (quantum_results['expected_return'] - classical_results['expected_return']) / classical_results['expected_return']
    risk_improvement = (classical_results['portfolio_risk'] - quantum_results['portfolio_risk']) / classical_results['portfolio_risk']
    sharpe_improvement = (quantum_results['sharpe_ratio'] - classical_results['sharpe_ratio']) / max(classical_results['sharpe_ratio'], 0.001)
    
    return float(return_weight * return_improvement + risk_weight * risk_improvement + sharpe_weight * sharpe_improvement)


def calculate_performance_score(hybrid_metrics: Dict[str, Any]) -> float:
    """Calculate overall performance score for the optimization."""
    base_score = 0.5
    
    # Adjust based on improvements
    score_adjustment = hybrid_metrics['quantum_advantage_score'] * 0.3
    
    # Cap between 0 and 1
    return max(0.0, min(1.0, base_score + score_adjustment))


def save_results_to_storage(bucket, results: Dict[str, Any]):
    """Save optimization results to Cloud Storage."""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"optimization_results_{timestamp}.json"
    
    blob = bucket.blob(f'results/{filename}')
    blob.upload_from_string(json.dumps(results, indent=2))
    
    logger.info(f"Results saved to gs://{bucket.name}/results/{filename}")


def save_results_to_bigquery(bq_client, results: Dict[str, Any]):
    """Save optimization results to BigQuery."""
    try:
        dataset_id = f"{PROJECT_ID.replace('-', '_')}_results"
        table_id = "optimization_results"
        
        # Prepare row data
        row_data = {
            'timestamp': results['timestamp'],
            'portfolio_weights': json.dumps(results['quantum_results']['weights']),
            'optimization_cost': results['quantum_results'].get('qaoa_cost', 0.0),
            'quantum_parameters': json.dumps(results['quantum_results'].get('qaoa_parameters', {})),
            'classical_metrics': json.dumps(results['classical_results']),
            'hybrid_score': results['performance_score']
        }
        
        # Insert row
        table_ref = bq_client.dataset(dataset_id).table(table_id)
        table = bq_client.get_table(table_ref)
        
        errors = bq_client.insert_rows_json(table, [row_data])
        
        if errors:
            logger.error(f"Error inserting to BigQuery: {errors}")
        else:
            logger.info("Results saved to BigQuery successfully")
            
    except Exception as e:
        logger.error(f"Error saving to BigQuery: {e}")