"""
Setup configuration for the Blockchain Voting System CDK Python application.
"""

import setuptools
from pathlib import Path

# Read the long description from README.md
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
requirements = []
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as f:
        requirements = [
            line.strip() 
            for line in f.readlines() 
            if line.strip() and not line.startswith("#")
        ]

# Development dependencies
dev_requirements = [
    "pytest>=7.4.0",
    "pytest-cov>=4.1.0",
    "black>=23.0.0",
    "mypy>=1.0.0",
    "flake8>=6.0.0",
    "bandit>=1.7.0",
    "safety>=2.3.0",
    "sphinx>=7.0.0",
    "sphinx-rtd-theme>=1.3.0",
]

setuptools.setup(
    name="blockchain-voting-system",
    version="1.0.0",
    author="Voting System Team",
    author_email="voting-team@example.com",
    description="CDK Python application for a blockchain-based voting system",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/example/blockchain-voting-system",
    project_urls={
        "Documentation": "https://github.com/example/blockchain-voting-system/docs",
        "Source": "https://github.com/example/blockchain-voting-system",
        "Tracker": "https://github.com/example/blockchain-voting-system/issues",
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
    ],
    packages=setuptools.find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    python_requires=">=3.8",
    install_requires=requirements,
    extras_require={
        "dev": dev_requirements,
        "test": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
        "security": [
            "bandit>=1.7.0",
            "safety>=2.3.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "blockchain-voting-deploy=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "blockchain",
        "voting",
        "election",
        "democracy",
        "ethereum",
        "smart-contracts",
        "security",
        "transparency",
    ],
    license="MIT",
    zip_safe=False,
)