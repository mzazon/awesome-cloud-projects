"""
Setup script for the Serverless Container CDK Python application.

This setup.py file configures the Python package for the CDK application
that deploys serverless container applications using AWS Fargate.
"""

from setuptools import setup, find_packages


def read_requirements():
    """Read requirements from requirements.txt file."""
    with open("requirements.txt", "r", encoding="utf-8") as req_file:
        return [
            line.strip()
            for line in req_file
            if line.strip() and not line.startswith("#")
        ]


setup(
    name="serverless-containers-cdk",
    version="1.0.0",
    description="AWS CDK Python application for deploying serverless container applications with Fargate",
    long_description=open("README.md", "r", encoding="utf-8").read() if open("README.md", "r", encoding="utf-8") else "",
    long_description_content_type="text/markdown",
    author="AWS Cloud Solutions",
    author_email="aws-solutions@example.com",
    url="https://github.com/aws-samples/serverless-containers-cdk",
    packages=find_packages(),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Package dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "mypy>=1.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "isort>=5.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    
    # Entry points
    entry_points={
        "console_scripts": [
            "deploy-serverless-containers=app:main",
        ],
    },
    
    # Package classifiers
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "fargate",
        "ecs",
        "containers",
        "serverless",
        "cloud",
        "infrastructure",
        "automation",
        "devops",
    ],
    
    # Include additional files
    include_package_data=True,
    zip_safe=False,
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/serverless-containers-cdk",
        "Tracker": "https://github.com/aws-samples/serverless-containers-cdk/issues",
    },
)