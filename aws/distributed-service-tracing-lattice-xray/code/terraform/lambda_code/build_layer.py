#!/usr/bin/env python3
"""
Build script for creating Lambda layer with X-Ray SDK
This script is included in the layer package for reference
"""

import subprocess
import sys
import os

def build_layer():
    """Build the Lambda layer with required dependencies"""
    print("Building X-Ray SDK Lambda layer...")
    
    # Create python directory structure for Lambda layer
    os.makedirs("python", exist_ok=True)
    
    # Install requirements to python directory
    subprocess.check_call([
        sys.executable, "-m", "pip", "install",
        "-r", "requirements.txt",
        "-t", "python/"
    ])
    
    print("Lambda layer built successfully!")

if __name__ == "__main__":
    build_layer()