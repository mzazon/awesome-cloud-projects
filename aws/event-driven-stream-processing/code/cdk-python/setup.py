"""
Setup configuration for Real-Time Data Processing CDK Python Application

This setup.py file configures the Python package for the CDK application,
including metadata, dependencies, and development tools configuration.
"""

import setuptools
from pathlib import Path

# Read the README file for the long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as f:
        requirements = [
            line.strip()
            for line in f.readlines()
            if line.strip() and not line.startswith("#")
        ]
else:
    requirements = [
        "aws-cdk-lib>=2.120.0,<3.0.0",
        "constructs>=10.3.0,<11.0.0",
        "boto3>=1.34.0,<2.0.0",
    ]

# Development dependencies
dev_requirements = [
    "pytest>=7.4.0,<8.0.0",
    "pytest-cov>=4.1.0,<5.0.0",
    "moto>=4.2.0,<5.0.0",
    "black>=23.7.0,<24.0.0",
    "flake8>=6.0.0,<7.0.0",
    "mypy>=1.5.0,<2.0.0",
    "bandit>=1.7.5,<2.0.0",
    "safety>=2.3.0,<3.0.0",
]

setuptools.setup(
    name="real-time-data-processing-cdk",
    version="1.0.0",
    
    # Package metadata
    description="AWS CDK Python application for real-time data processing with Kinesis and Lambda",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS CDK Team",
    author_email="aws-cdk@amazon.com",
    
    # Package URLs
    url="https://github.com/aws/aws-cdk",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Package discovery and dependencies
    packages=setuptools.find_packages(
        exclude=["tests", "tests.*", "*.tests", "*.tests.*"]
    ),
    include_package_data=True,
    
    # Dependencies
    install_requires=requirements,
    extras_require={
        "dev": dev_requirements,
        "test": [
            "pytest>=7.4.0,<8.0.0",
            "pytest-cov>=4.1.0,<5.0.0",
            "moto>=4.2.0,<5.0.0",
        ],
        "lint": [
            "black>=23.7.0,<24.0.0",
            "flake8>=6.0.0,<7.0.0",
            "mypy>=1.5.0,<2.0.0",
        ],
        "security": [
            "bandit>=1.7.5,<2.0.0",
            "safety>=2.3.0,<3.0.0",
        ],
    },
    
    # Entry points for command-line tools
    entry_points={
        "console_scripts": [
            "deploy-real-time-processing=app:main",
        ],
    },
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "kinesis",
        "lambda",
        "dynamodb",
        "real-time",
        "streaming",
        "serverless",
        "data-processing",
        "analytics",
    ],
    
    # Licensing
    license="Apache-2.0",
    
    # Additional metadata
    zip_safe=False,
    
    # Configuration for development tools
    options={
        "bdist_wheel": {
            "universal": False,
        },
    },
)

# Additional configuration for development tools can be added here
# or in separate configuration files like setup.cfg, pyproject.toml, etc.

# Example: Black configuration (can also be in pyproject.toml)
BLACK_CONFIG = {
    "line-length": 88,
    "target-version": ["py38", "py39", "py310", "py311"],
    "include": r"\.pyi?$",
    "exclude": r"""
    /(
        \.eggs
      | \.git
      | \.hg
      | \.mypy_cache
      | \.tox
      | \.venv
      | _build
      | buck-out
      | build
      | dist
      | cdk.out
    )/
    """,
}

# Example: MyPy configuration (can also be in mypy.ini or pyproject.toml)
MYPY_CONFIG = {
    "python_version": "3.8",
    "warn_return_any": True,
    "warn_unused_configs": True,
    "disallow_untyped_defs": True,
    "disallow_incomplete_defs": True,
    "check_untyped_defs": True,
    "disallow_untyped_decorators": True,
    "no_implicit_optional": True,
    "warn_redundant_casts": True,
    "warn_unused_ignores": True,
    "warn_no_return": True,
    "warn_unreachable": True,
    "strict_equality": True,
}

# Example: Pytest configuration (can also be in pytest.ini or pyproject.toml)
PYTEST_CONFIG = {
    "testpaths": ["tests"],
    "python_files": ["test_*.py", "*_test.py"],
    "python_classes": ["Test*"],
    "python_functions": ["test_*"],
    "addopts": [
        "--verbose",
        "--cov=.",
        "--cov-report=term-missing",
        "--cov-report=html:htmlcov",
        "--cov-report=xml:coverage.xml",
        "--junit-xml=junit.xml",
    ],
    "markers": [
        "unit: Unit tests",
        "integration: Integration tests",
        "slow: Slow running tests",
        "aws: Tests that require AWS credentials",
    ],
}