"""
Setup configuration for AWS CDK Python IoT Security Application

This setup.py file configures the Python package for the IoT Security implementation
using AWS CDK. It includes all necessary dependencies and metadata for proper
package management and deployment.
"""

from setuptools import setup, find_packages
import os

# Read the README file for the long description
def read_readme():
    """Read README.md file for package description."""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            return f.read()
    return "AWS CDK Python application for IoT Security with Device Certificates and Policies"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    requirements = []
    if os.path.exists(requirements_path):
        with open(requirements_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    requirements.append(line)
    return requirements

setup(
    name="iot-security-cdk",
    version="1.0.0",
    description="AWS CDK Python application for IoT Certificate Security with X.509 Authentication",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    author="AWS Solutions Architect",
    author_email="architect@example.com",
    url="https://github.com/aws-samples/iot-security-cdk",
    
    # Package discovery
    packages=find_packages(),
    
    # Include non-Python files
    include_package_data=True,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0"
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0"
        ]
    },
    
    # Entry points
    entry_points={
        "console_scripts": [
            "iot-security-deploy=app:main",
        ],
    },
    
    # Classifiers for PyPI
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Security",
        "Topic :: System :: Systems Administration",
        "Topic :: Software Development :: Libraries :: Python Modules",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "iot",
        "security",
        "certificates",
        "device-authentication",
        "x509",
        "device-defender",
        "infrastructure-as-code",
        "cloud-security"
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/iot-security-cdk",
        "Bug Reports": "https://github.com/aws-samples/iot-security-cdk/issues",
        "AWS IoT Core": "https://aws.amazon.com/iot-core/",
        "AWS CDK": "https://aws.amazon.com/cdk/",
    },
    
    # License
    license="Apache-2.0",
    
    # Zip safety
    zip_safe=False,
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
)