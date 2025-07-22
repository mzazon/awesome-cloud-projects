"""
Setup configuration for EKS Ingress Controllers CDK Python application.

This setup.py file configures the Python package for the CDK application,
including metadata, dependencies, and entry points.
"""

from setuptools import setup, find_packages

# Read the long description from README file
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = """
    AWS CDK Python application for EKS Ingress Controllers with AWS Load Balancer Controller.
    
    This application creates an EKS cluster with the AWS Load Balancer Controller installed,
    along with sample applications and various ingress configurations demonstrating
    ALB and NLB capabilities.
    """

# Read requirements from requirements.txt
def parse_requirements():
    """Parse requirements.txt file and return list of dependencies."""
    requirements = []
    try:
        with open("requirements.txt", "r", encoding="utf-8") as req_file:
            for line in req_file:
                line = line.strip()
                # Skip empty lines and comments
                if line and not line.startswith("#"):
                    # Remove inline comments
                    requirement = line.split("#")[0].strip()
                    if requirement:
                        requirements.append(requirement)
    except FileNotFoundError:
        # Fallback to basic requirements
        requirements = [
            "aws-cdk-lib>=2.100.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0",
        ]
    return requirements

setup(
    name="eks-ingress-controllers-cdk",
    version="1.0.0",
    author="AWS CDK Team",
    author_email="aws-cdk@amazon.com",
    description="AWS CDK Python application for EKS Ingress Controllers with AWS Load Balancer Controller",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    python_requires=">=3.8",
    install_requires=parse_requirements(),
    extras_require={
        "dev": [
            "pytest>=7.0.0,<8.0.0",
            "pytest-cov>=4.0.0,<5.0.0",
            "black>=23.0.0,<24.0.0",
            "flake8>=6.0.0,<7.0.0",
            "mypy>=1.0.0,<2.0.0",
            "isort>=5.0.0,<6.0.0",
            "pre-commit>=3.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.2.0",
        ],
        "security": [
            "bandit>=1.7.0",
            "safety>=2.3.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "eks-ingress-cdk=app:main",
        ],
    },
    classifiers=[
        "Development Status :: 5 - Production/Stable",
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
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
        "Typing :: Typed",
    ],
    keywords=[
        "aws",
        "cdk",
        "eks",
        "kubernetes",
        "ingress",
        "load-balancer",
        "alb",
        "nlb",
        "infrastructure",
        "cloud",
        "devops",
        "containers",
    ],
    platforms=["any"],
    license="Apache-2.0",
    zip_safe=False,
    # Additional metadata for PyPI
    maintainer="AWS CDK Team",
    maintainer_email="aws-cdk@amazon.com",
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    # Data files to include in the package
    data_files=[
        (".", ["requirements.txt"]),
    ],
    # Options for setuptools
    options={
        "build_py": {
            "exclude_patterns": ["tests/*", "*.pyc", "__pycache__/*"]
        }
    },
    # Custom commands
    cmdclass={},
    # Dependency links (if using development versions)
    dependency_links=[],
    # Tests configuration
    test_suite="tests",
    tests_require=[
        "pytest>=7.0.0",
        "pytest-cov>=4.0.0",
        "moto>=4.0.0",  # For mocking AWS services in tests
    ],
)

# Additional setup configuration for development
if __name__ == "__main__":
    import sys
    import os
    
    # Add current directory to Python path for development
    current_dir = os.path.dirname(os.path.abspath(__file__))
    sys.path.insert(0, current_dir)
    
    # Print helpful information
    print("EKS Ingress Controllers CDK Python Application Setup")
    print("=" * 50)
    print(f"Python version: {sys.version}")
    print(f"Setup directory: {current_dir}")
    print("\nTo install the package in development mode:")
    print("  pip install -e .")
    print("\nTo install with development dependencies:")
    print("  pip install -e .[dev]")
    print("\nTo run the CDK application:")
    print("  python app.py")
    print("  # or")
    print("  cdk synth")
    print("  cdk deploy")