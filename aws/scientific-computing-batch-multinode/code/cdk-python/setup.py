"""
Setup configuration for Distributed Scientific Computing CDK Application

This setup.py file configures the Python package for the AWS CDK application
that deploys infrastructure for distributed scientific computing workloads
using AWS Batch multi-node parallel jobs.
"""

import setuptools

# Read the long description from README if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS CDK application for distributed scientific computing with Batch multi-node jobs"

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

setuptools.setup(
    name="distributed-scientific-computing-cdk",
    version="1.0.0",
    
    author="AWS CDK Python Generator",
    author_email="your-email@example.com",
    description="AWS CDK application for distributed scientific computing with Batch multi-node parallel jobs",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    url="https://github.com/your-org/distributed-scientific-computing-cdk",
    
    packages=setuptools.find_packages(),
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: Science/Research",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Scientific/Engineering",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Distributed Computing",
    ],
    
    python_requires=">=3.8",
    install_requires=requirements,
    
    # Optional dependencies for development and testing
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
        ],
        "security": [
            "cdk-nag>=2.0.0",
        ],
    },
    
    # Entry points for command-line tools (if needed)
    entry_points={
        "console_scripts": [
            "deploy-scientific-computing=app:main",
        ],
    },
    
    # Include additional files in the package
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.yml", "*.yaml", "*.json"],
    },
    
    # Project metadata
    project_urls={
        "Bug Reports": "https://github.com/your-org/distributed-scientific-computing-cdk/issues",
        "Source": "https://github.com/your-org/distributed-scientific-computing-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    keywords=[
        "aws",
        "cdk",
        "batch",
        "multi-node",
        "mpi",
        "scientific-computing",
        "distributed-computing",
        "hpc",
        "infrastructure-as-code",
    ],
    
    # Ensure compatibility with CDK requirements
    zip_safe=False,
)