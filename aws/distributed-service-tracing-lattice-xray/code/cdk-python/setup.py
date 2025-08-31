#!/usr/bin/env python3
"""
Setup script for Distributed Service Tracing CDK Python Application

This setup script configures the Python package for the AWS CDK application that implements
distributed service tracing with VPC Lattice and X-Ray. It includes all necessary metadata,
dependencies, and configuration for proper packaging and distribution.
"""

from setuptools import setup, find_packages
import os
import sys


def read_requirements():
    """
    Read and parse requirements.txt file to extract package dependencies
    
    Returns:
        list: List of package requirements with version constraints
    """
    requirements_file = os.path.join(os.path.dirname(__file__), 'requirements.txt')
    with open(requirements_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    # Filter out comments, empty lines, and development dependencies
    requirements = []
    for line in lines:
        line = line.strip()
        if line and not line.startswith('#') and not line.startswith('-'):
            # Extract main dependencies, excluding some dev-only packages
            if not any(pkg in line.lower() for pkg in [
                'pytest', 'black', 'flake8', 'mypy', 'sphinx', 'bandit',
                'safety', 'pre-commit', 'commitizen', 'radon', 'mccabe'
            ]):
                requirements.append(line)
    
    return requirements


def read_long_description():
    """
    Read the long description from README.md file
    
    Returns:
        str: Content of README.md file or fallback description
    """
    readme_file = os.path.join(os.path.dirname(__file__), 'README.md')
    if os.path.exists(readme_file):
        with open(readme_file, 'r', encoding='utf-8') as f:
            return f.read()
    else:
        return """
        Distributed Service Tracing CDK Application
        
        This AWS CDK Python application demonstrates comprehensive distributed tracing 
        by combining VPC Lattice service mesh capabilities with AWS X-Ray application-level 
        tracing to create a complete observability solution for microservices architectures.
        
        Features:
        - VPC Lattice service network for inter-service communication
        - Lambda functions with comprehensive X-Ray instrumentation
        - CloudWatch monitoring and alerting
        - IAM roles following least privilege principles
        - Complete observability dashboard
        """


def get_version():
    """
    Get version from environment variable or use default
    
    Returns:
        str: Version string for the package
    """
    return os.environ.get('PACKAGE_VERSION', '1.0.0')


# Ensure we're using Python 3.8 or later
if sys.version_info < (3, 8):
    sys.exit('This application requires Python 3.8 or later.')

setup(
    # Basic package information
    name="distributed-service-tracing-cdk",
    version=get_version(),
    description="AWS CDK application for distributed service tracing with VPC Lattice and X-Ray",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    
    # Author and contact information
    author="AWS Solutions Architecture Team",
    author_email="aws-solutions@amazon.com",
    maintainer="AWS CDK Community",
    maintainer_email="aws-cdk-dev@amazon.com",
    
    # Project URLs and metadata
    url="https://github.com/aws-samples/distributed-service-tracing-cdk",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/distributed-service-tracing-cdk",
        "Tracker": "https://github.com/aws-samples/distributed-service-tracing-cdk/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "VPC Lattice": "https://aws.amazon.com/vpc-lattice/",
        "AWS X-Ray": "https://aws.amazon.com/xray/"
    },
    
    # Package discovery and structure
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    
    # Python version requirements
    python_requires=">=3.8,<4.0",
    
    # Package dependencies
    install_requires=read_requirements(),
    
    # Optional dependencies for development and testing
    extras_require={
        'dev': [
            'pytest>=7.0.0,<8.0.0',
            'pytest-cov>=4.0.0,<5.0.0',
            'black>=23.0.0,<24.0.0',
            'flake8>=6.0.0,<7.0.0',
            'mypy>=1.0.0,<2.0.0',
            'bandit>=1.7.5,<2.0.0',
            'safety>=2.3.0,<3.0.0',
            'pre-commit>=3.6.0,<4.0.0',
            'isort>=5.12.0,<6.0.0',
            'autopep8>=2.0.0,<3.0.0',
        ],
        'docs': [
            'sphinx>=6.0.0,<7.0.0',
            'sphinx-rtd-theme>=1.2.0,<2.0.0',
            'pydoc-markdown>=4.8.0,<5.0.0',
            'mkdocs>=1.5.0,<2.0.0',
            'mkdocs-material>=9.4.0,<10.0.0',
        ],
        'testing': [
            'moto>=4.2.0,<5.0.0',
            'pytest-asyncio>=0.21.0,<1.0.0',
            'pytest-mock>=3.12.0,<4.0.0',
            'coverage>=7.3.0,<8.0.0',
            'factory-boy>=3.3.0,<4.0.0',
        ],
        'monitoring': [
            'datadog>=0.47.0,<1.0.0',
            'newrelic>=9.4.0,<10.0.0',
            'prometheus-client>=0.19.0,<1.0.0',
        ],
        'analytics': [
            'numpy>=1.24.0,<2.0.0',
            'pandas>=2.1.0,<3.0.0',
            'scikit-learn>=1.3.0,<2.0.0',
            'networkx>=3.2.0,<4.0.0',
        ]
    },
    
    # Package classification
    classifiers=[
        # Development status
        "Development Status :: 4 - Beta",
        
        # Intended audience
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "Intended Audience :: Information Technology",
        
        # Topic classification
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Distributed Computing",
        "Topic :: System :: Monitoring",
        "Topic :: System :: Networking",
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
        "Topic :: Software Development :: Quality Assurance",
        
        # License
        "License :: OSI Approved :: Apache Software License",
        
        # Environment
        "Environment :: Console",
        "Environment :: Web Environment",
        
        # Operating systems
        "Operating System :: OS Independent",
        "Operating System :: POSIX :: Linux",
        "Operating System :: MacOS",
        "Operating System :: Microsoft :: Windows",
        
        # Programming language
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Programming Language :: Python :: Implementation :: CPython",
        "Programming Language :: Python :: Implementation :: PyPy",
        
        # Framework
        "Framework :: AWS CDK",
        
        # Natural language
        "Natural Language :: English",
        
        # Typing
        "Typing :: Typed",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws", "cdk", "cloud-development-kit", "infrastructure-as-code",
        "vpc-lattice", "service-mesh", "microservices", "distributed-tracing",
        "x-ray", "observability", "monitoring", "cloudwatch", "lambda",
        "serverless", "networking", "devops", "sre", "reliability"
    ],
    
    # Entry points for command-line interfaces
    entry_points={
        'console_scripts': [
            'deploy-tracing-stack=app:main',
        ],
    },
    
    # Package data and resources
    package_data={
        '': [
            '*.md',
            '*.txt',
            '*.yaml',
            '*.yml',
            '*.json',
            'templates/*',
            'config/*',
            'docs/*',
        ],
    },
    
    # Data files to include in the package
    data_files=[
        ('config', ['cdk.json']),
        ('docs', ['README.md']),
    ],
    
    # Zip safety for package installation
    zip_safe=False,
    
    # License information
    license="Apache-2.0",
    license_files=["LICENSE", "LICENSE.txt"],
    
    # Platform compatibility
    platforms=["any"],
    
    # Package options
    options={
        'build_scripts': {
            'executable': '/usr/bin/env python3',
        },
        'egg_info': {
            'tag_build': '',
            'tag_date': False,
        },
    },
)

# Post-installation message
print("""
===============================================================================
Distributed Service Tracing CDK Application Installation Complete!

Next Steps:
1. Configure AWS credentials: aws configure
2. Bootstrap CDK environment: cdk bootstrap
3. Deploy the stack: cdk deploy
4. View the observability dashboard in CloudWatch
5. Check X-Ray service map for distributed traces

Documentation:
- AWS CDK: https://docs.aws.amazon.com/cdk/
- VPC Lattice: https://docs.aws.amazon.com/vpc-lattice/
- AWS X-Ray: https://docs.aws.amazon.com/xray/

For support and questions:
- GitHub Issues: https://github.com/aws-samples/distributed-service-tracing-cdk/issues
- AWS Forums: https://forums.aws.amazon.com/
- AWS Support: https://aws.amazon.com/support/

Happy building with AWS CDK!
===============================================================================
""")