#!/bin/bash

# Startup script for Vertex AI Workbench instance
# This script installs quantum computing libraries and configures the environment

set -e

echo "Starting quantum computing environment setup..."

# Update system packages
apt-get update
apt-get upgrade -y

# Install system dependencies for quantum computing
apt-get install -y \
    build-essential \
    cmake \
    git \
    curl \
    wget \
    python3-dev \
    python3-pip \
    libffi-dev \
    libssl-dev \
    libblas-dev \
    liblapack-dev \
    gfortran \
    pkg-config

# Upgrade pip
python3 -m pip install --upgrade pip setuptools wheel

# Install quantum computing packages
echo "Installing quantum computing libraries..."
python3 -m pip install \
    cirq>=1.3.0 \
    cirq-google>=1.3.0 \
    cirq-rigetti>=0.15.0 \
    qiskit>=0.45.0 \
    tensorflow-quantum>=0.7.3 \
    numpy>=1.21.0 \
    scipy>=1.7.0 \
    pandas>=1.3.0 \
    matplotlib>=3.4.0 \
    seaborn>=0.11.0 \
    scikit-learn>=1.0.0 \
    jupyter>=1.0.0 \
    jupyterlab>=3.0.0

# Install Google Cloud libraries
echo "Installing Google Cloud libraries..."
python3 -m pip install \
    google-cloud-storage>=2.10.0 \
    google-cloud-aiplatform>=1.38.0 \
    google-cloud-bigquery>=3.4.0 \
    google-cloud-monitoring>=2.11.0 \
    google-cloud-logging>=3.2.0 \
    google-cloud-functions>=1.8.0

# Install additional scientific computing packages
echo "Installing scientific computing packages..."
python3 -m pip install \
    sympy>=1.9.0 \
    networkx>=2.6.0 \
    plotly>=5.0.0 \
    dash>=2.0.0 \
    streamlit>=1.10.0 \
    joblib>=1.1.0 \
    dask>=2021.9.0

# Set up environment variables
echo "Setting up environment variables..."
cat >> /home/jupyter/.bashrc << EOF

# Quantum Computing Environment Variables
export PROJECT_ID="${project_id}"
export BUCKET_NAME="${bucket_name}"
export GOOGLE_CLOUD_PROJECT="${project_id}"

# Python path for custom modules
export PYTHONPATH=\$PYTHONPATH:/home/jupyter/custom_modules

# Quantum computing specific settings
export CIRQ_GOOGLE_ENGINE_PROJECT="${project_id}"
export TF_CPP_MIN_LOG_LEVEL=2

# Jupyter configuration
export JUPYTER_ENABLE_LAB=yes

EOF

# Create directories for quantum computing projects
echo "Creating project directories..."
mkdir -p /home/jupyter/quantum_projects
mkdir -p /home/jupyter/quantum_projects/portfolio_optimization
mkdir -p /home/jupyter/quantum_projects/risk_models
mkdir -p /home/jupyter/quantum_projects/data
mkdir -p /home/jupyter/quantum_projects/results
mkdir -p /home/jupyter/custom_modules

# Create sample quantum computing notebook
echo "Creating sample quantum computing notebook..."
cat > /home/jupyter/quantum_projects/quantum_portfolio_demo.ipynb << 'EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Hybrid Quantum-Classical Portfolio Optimization Demo\n",
    "\n",
    "This notebook demonstrates the basic setup and usage of the quantum portfolio optimization system."
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Import required libraries\n",
    "import cirq\n",
    "import cirq_google\n",
    "import numpy as np\n",
    "import pandas as pd\n",
    "import matplotlib.pyplot as plt\n",
    "from google.cloud import storage\n",
    "from google.cloud import aiplatform\n",
    "import os\n",
    "\n",
    "# Display versions\n",
    "print(f\"Cirq version: {cirq.__version__}\")\n",
    "print(f\"NumPy version: {np.__version__}\")\n",
    "print(f\"Pandas version: {pd.__version__}\")\n",
    "\n",
    "# Check environment variables\n",
    "project_id = os.environ.get('PROJECT_ID')\n",
    "bucket_name = os.environ.get('BUCKET_NAME')\n",
    "print(f\"Project ID: {project_id}\")\n",
    "print(f\"Bucket Name: {bucket_name}\")"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Test basic quantum circuit\n",
    "print(\"Testing basic quantum circuit...\")\n",
    "\n",
    "# Create a simple quantum circuit\n",
    "qubit = cirq.GridQubit(0, 0)\n",
    "circuit = cirq.Circuit(\n",
    "    cirq.H(qubit),\n",
    "    cirq.measure(qubit, key='result')\n",
    ")\n",
    "\n",
    "print(\"Circuit:\")\n",
    "print(circuit)\n",
    "\n",
    "# Simulate the circuit\n",
    "simulator = cirq.Simulator()\n",
    "result = simulator.run(circuit, repetitions=1000)\n",
    "\n",
    "print(f\"\\nMeasurement results: {result.measurements['result'][:10]}...\")\n",
    "print(f\"Proportion of 1s: {np.mean(result.measurements['result'])}\")"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Test Google Cloud Storage connectivity\n",
    "print(\"Testing Google Cloud Storage connectivity...\")\n",
    "\n",
    "try:\n",
    "    client = storage.Client(project=project_id)\n",
    "    bucket = client.bucket(bucket_name)\n",
    "    \n",
    "    # List first few objects in bucket\n",
    "    blobs = list(bucket.list_blobs(max_results=5))\n",
    "    print(f\"Found {len(blobs)} objects in bucket (showing first 5)\")\n",
    "    for blob in blobs:\n",
    "        print(f\"  - {blob.name}\")\n",
    "        \n",
    "except Exception as e:\n",
    "    print(f\"Error connecting to storage: {e}\")"
   ]
  },
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "## Next Steps\n",
    "\n",
    "1. Explore the quantum portfolio optimization algorithms\n",
    "2. Load sample financial data from Cloud Storage\n",
    "3. Run hybrid classical-quantum optimization workflows\n",
    "4. Analyze results and performance metrics\n",
    "\n",
    "For more advanced examples, see the quantum_projects directory."
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3",
   "language": "python",
   "name": "python3"
  },
  "language_info": {
   "codemirror_mode": {
    "name": "ipython",
    "version": 3
   },
   "file_extension": ".py",
   "mimetype": "text/x-python",
   "name": "python",
   "nbconvert_exporter": "python",
   "pygments_lexer": "ipython3",
   "version": "3.8.0"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 4
}
EOF

# Create Python module for quantum portfolio optimization
echo "Creating quantum portfolio optimization module..."
cat > /home/jupyter/custom_modules/quantum_portfolio.py << 'EOF'
"""
Quantum Portfolio Optimization Module

This module provides utilities for hybrid quantum-classical portfolio optimization
using Cirq and Google Cloud services.
"""

import cirq
import cirq_google
import numpy as np
from typing import Dict, List, Tuple, Optional
import json
from google.cloud import storage
import os


class QuantumPortfolioOptimizer:
    """Quantum portfolio optimizer using QAOA algorithm."""
    
    def __init__(self, project_id: str, bucket_name: str, processor_id: Optional[str] = None):
        self.project_id = project_id
        self.bucket_name = bucket_name
        self.processor_id = processor_id
        self.client = storage.Client()
        
    def create_portfolio_qubo(self, expected_returns: np.ndarray, 
                            covariance_matrix: np.ndarray, 
                            risk_aversion: float = 1.0) -> np.ndarray:
        """Convert portfolio optimization to QUBO formulation."""
        n_assets = len(expected_returns)
        
        # QUBO matrix: H = μᵀx - λ(xᵀΣx)
        Q = np.outer(expected_returns, expected_returns)
        Q -= risk_aversion * covariance_matrix
        
        return Q
    
    def create_qaoa_circuit(self, qubo_matrix: np.ndarray, 
                          beta: float, gamma: float) -> cirq.Circuit:
        """Create QAOA circuit for portfolio optimization."""
        n_qubits = qubo_matrix.shape[0]
        qubits = cirq.GridQubit.rect(1, n_qubits)
        
        circuit = cirq.Circuit()
        
        # Initial superposition
        circuit.append([cirq.H(q) for q in qubits])
        
        # Problem Hamiltonian (cost function)
        for i in range(n_qubits):
            for j in range(i, n_qubits):
                if i == j:
                    # Single qubit terms
                    circuit.append(cirq.rz(gamma * qubo_matrix[i, j])(qubits[i]))
                else:
                    # Two qubit terms
                    circuit.append(cirq.CNOT(qubits[i], qubits[j]))
                    circuit.append(cirq.rz(gamma * qubo_matrix[i, j])(qubits[j]))
                    circuit.append(cirq.CNOT(qubits[i], qubits[j]))
        
        # Mixer Hamiltonian
        circuit.append([cirq.rx(2 * beta)(q) for q in qubits])
        
        # Measurement
        circuit.append([cirq.measure(q, key=f'q{i}') for i, q in enumerate(qubits)])
        
        return circuit
    
    def save_results(self, results: Dict, filename: str):
        """Save optimization results to Cloud Storage."""
        serializable_results = {
            'weights': results['weights'].tolist() if isinstance(results['weights'], np.ndarray) else results['weights'],
            'cost': float(results['cost']),
            'beta': float(results['beta']),
            'gamma': float(results['gamma'])
        }
        
        bucket = self.client.bucket(self.bucket_name)
        blob = bucket.blob(f'results/{filename}')
        blob.upload_from_string(json.dumps(serializable_results, indent=2))
        
        print(f"Results saved to gs://{self.bucket_name}/results/{filename}")


def generate_sample_data(n_assets: int = 8) -> Tuple[np.ndarray, np.ndarray]:
    """Generate sample portfolio data for testing."""
    np.random.seed(42)
    
    # Generate expected returns
    expected_returns = np.random.uniform(0.05, 0.15, n_assets)
    
    # Generate covariance matrix
    correlation_matrix = np.random.uniform(0.1, 0.7, (n_assets, n_assets))
    correlation_matrix = (correlation_matrix + correlation_matrix.T) / 2
    np.fill_diagonal(correlation_matrix, 1.0)
    
    # Scale to reasonable covariance values
    volatilities = np.random.uniform(0.1, 0.3, n_assets)
    covariance_matrix = np.outer(volatilities, volatilities) * correlation_matrix
    
    return expected_returns, covariance_matrix
EOF

# Create requirements file for custom installations
echo "Creating requirements file..."
cat > /home/jupyter/requirements_custom.txt << 'EOF'
# Additional packages for quantum portfolio optimization
cvxpy>=1.2.0
cvxopt>=1.3.0
mosek>=9.3.0
yfinance>=0.1.70
alpha-vantage>=2.3.1
quandl>=3.7.0
backtrader>=1.9.76
zipline-reloaded>=2.2.0
empyrical>=0.5.5
pyfolio-reloaded>=0.9.0
EOF

# Set proper ownership
chown -R jupyter:jupyter /home/jupyter/quantum_projects
chown -R jupyter:jupyter /home/jupyter/custom_modules
chown jupyter:jupyter /home/jupyter/requirements_custom.txt

# Install additional custom packages
echo "Installing additional custom packages..."
python3 -m pip install -r /home/jupyter/requirements_custom.txt

# Download sample data from Cloud Storage (if available)
echo "Checking for sample data in Cloud Storage..."
gsutil -m cp -r gs://${bucket_name}/sample_data/* /home/jupyter/quantum_projects/data/ 2>/dev/null || echo "No sample data found in Cloud Storage"

# Create Jupyter kernel configuration
echo "Configuring Jupyter kernel..."
python3 -m ipykernel install --user --name quantum --display-name "Quantum Computing"

# Install Jupyter extensions for better development experience
echo "Installing Jupyter extensions..."
jupyter labextension install @jupyter-widgets/jupyterlab-manager
jupyter labextension install @jupyterlab/toc
jupyter labextension install @lckr/jupyterlab_variableinspector

# Start Jupyter Lab service
echo "Starting Jupyter Lab service..."
systemctl enable jupyter.service
systemctl start jupyter.service

# Create completion marker
touch /home/jupyter/.quantum_setup_complete

echo "Quantum computing environment setup completed successfully!"
echo "Access Jupyter Lab at: https://[INSTANCE_IP]:8080"
echo "Default password: Check the Vertex AI Workbench console for connection details"

# Log setup completion
logger "Quantum computing environment setup completed for Vertex AI Workbench"