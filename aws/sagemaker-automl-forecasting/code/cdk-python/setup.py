"""
Setup configuration for AutoML Forecasting CDK Python application.

This setup.py file configures the Python package for the CDK application
that deploys the complete AutoML forecasting solution using Amazon SageMaker.
"""

from setuptools import setup, find_packages
import os

# Read the contents of README file
this_directory = os.path.abspath(os.path.dirname(__file__))
try:
    with open(os.path.join(this_directory, 'README.md'), encoding='utf-8') as f:
        long_description = f.read()
except FileNotFoundError:
    long_description = "AutoML Forecasting CDK Python Application"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements = []
    try:
        with open('requirements.txt', 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    # Remove version constraints for setup.py
                    if '>=' in line:
                        package = line.split('>=')[0]
                    elif '==' in line:
                        package = line.split('==')[0]
                    elif '<' in line:
                        package = line.split('<')[0]
                    else:
                        package = line
                    requirements.append(package)
    except FileNotFoundError:
        # Fallback requirements if file doesn't exist
        requirements = [
            'aws-cdk-lib',
            'constructs',
            'boto3',
            'pandas',
            'numpy'
        ]
    return requirements

setup(
    name="automl-forecasting-cdk",
    version="1.0.0",
    description="AWS CDK application for SageMaker AutoML for Time Series Forecasting",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Solutions",
    author_email="aws-solutions@amazon.com",
    url="https://github.com/aws-samples/automl-forecasting-cdk",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/sagemaker/latest/dg/autopilot-automl.html",
        "Source": "https://github.com/aws-samples/automl-forecasting-cdk",
        "Tracker": "https://github.com/aws-samples/automl-forecasting-cdk/issues",
    },
    
    # Package configuration
    packages=find_packages(exclude=['tests*']),
    package_dir={'': '.'},
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        'dev': [
            'pytest>=7.4.0',
            'pytest-cov>=4.1.0',
            'black>=23.0.0',
            'isort>=5.12.0',
            'mypy>=1.7.0',
            'flake8>=6.1.0',
        ],
        'docs': [
            'sphinx>=7.1.0',
            'sphinx-rtd-theme>=1.3.0',
        ],
        'typing': [
            'types-boto3>=1.0.2',
            'boto3-stubs[essential]>=1.34.0',
        ]
    },
    
    # Entry points
    entry_points={
        'console_scripts': [
            'automl-forecasting-deploy=app:main',
        ],
    },
    
    # Package metadata
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: Information Technology",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Installation/Setup",
        "Topic :: Utilities",
        "Topic :: Scientific/Engineering :: Artificial Intelligence",
        "Topic :: Scientific/Engineering :: Information Analysis",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "sagemaker",
        "automl",
        "forecasting",
        "machine-learning",
        "time-series",
        "prediction",
        "analytics",
        "artificial-intelligence"
    ],
    
    # Include additional files
    include_package_data=True,
    zip_safe=False,
    
    # License information
    license="Apache License 2.0",
    license_files=['LICENSE'],
)