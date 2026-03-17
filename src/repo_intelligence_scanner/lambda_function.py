import json
import os
import subprocess
import shutil
from collections import defaultdict

# File categories relevant to data engineering and analysis
DATA_EXTENSIONS = {'.csv', '.parquet', '.json', '.jsonl', '.xml', '.yaml', '.yml'}
NOTEBOOK_EXTENSIONS = {'.ipynb'}
DATABASE_EXTENSIONS = {'.sql', '.db', '.sqlite'}
CODE_EXTENSIONS = {'.py', '.r', '.scala', '.java', '.js', '.ts'}
CONFIG_EXTENSIONS = {'.toml', '.cfg', '.ini', '.env'}
INFRASTRUCTURE_EXTENSIONS = {'.tf', '.dockerfile'}
CI_CD_PATHS = {'.github', '.gitlab-ci.yml', 'jenkinsfile', '.circleci'}

# Data engineering technology indicators
DATA_ENGINEERING_INDICATORS = {
    'airflow': 'Apache Airflow (workflow orchestration)',
    'dbt': 'dbt (data transformation)',
    'spark': 'Apache Spark (distributed processing)',
    'kafka': 'Apache Kafka (streaming)',
    'pandas': 'Pandas (data analysis)',
    'pyspark': 'PySpark (distributed Python)',
    'sqlalchemy': 'SQLAlchemy (database ORM)',
    'great_expectations': 'Great Expectations (data quality)',
    'luigi': 'Luigi (pipeline orchestration)',
    'prefect': 'Prefect (workflow orchestration)',
    'dagster': 'Dagster (data orchestration)'
}


def analyze_repository(repo_url):
    """Clones a git repo and returns structured intelligence data."""
    repo_dir = "/tmp/repo"
    if os.path.exists(repo_dir):
        shutil.rmtree(repo_dir)

    try:
        print(f"Cloning repository: {repo_url}")
        subprocess.run(
            ["git", "clone", repo_url, repo_dir],
            check=True,
            capture_output=True,
            text=True
        )
        print("Repository cloned successfully.")

        file_list = []
        extension_counts = defaultdict(int)
        category_counts = defaultdict(int)
        directory_structure = set()
        detected_de_technologies = []
        has_ci_cd = False
        has_tests = False
        has_documentation = False
        max_depth = 0
        requirements_content = []

        for root, dirs, files in os.walk(repo_dir):
            if '.git' in dirs:
                dirs.remove('.git')

            # Check for CI/CD directories
            for d in dirs:
                if d.lower() in CI_CD_PATHS:
                    has_ci_cd = True

            # Track directory depth and top-level structure
            relative_root = os.path.relpath(root, repo_dir)
            if relative_root != '.':
                depth = relative_root.count(os.sep) + 1
                max_depth = max(max_depth, depth)
                top_level_dir = relative_root.split(os.sep)[0]
                directory_structure.add(top_level_dir)

                # Detect test and docs directories
                if top_level_dir.lower() in {'tests', 'test', 'spec'}:
                    has_tests = True
                if top_level_dir.lower() in {'docs', 'documentation', 'wiki'}:
                    has_documentation = True

            for name in files:
                relative_path = os.path.relpath(
                    os.path.join(root, name), repo_dir
                )
                file_list.append(relative_path)

                name_lower = name.lower()
                ext = os.path.splitext(name)[1].lower()

                if ext:
                    extension_counts[ext] += 1

                # Categorize files
                if ext in DATA_EXTENSIONS:
                    category_counts['data_files'] += 1
                elif ext in NOTEBOOK_EXTENSIONS:
                    category_counts['notebooks'] += 1
                elif ext in DATABASE_EXTENSIONS:
                    category_counts['database_files'] += 1
                elif ext in CODE_EXTENSIONS:
                    category_counts['code_files'] += 1
                elif ext in CONFIG_EXTENSIONS:
                    category_counts['config_files'] += 1
                elif ext in INFRASTRUCTURE_EXTENSIONS or name_lower == 'dockerfile':
                    category_counts['infrastructure_files'] += 1

                # Detect CI/CD files
                if any(ci in relative_path.lower() for ci in CI_CD_PATHS):
                    has_ci_cd = True

                # Check test files
                if 'test_' in name_lower or '_test' in name_lower:
                    has_tests = True

                # Read requirements.txt for technology detection
                if name_lower == 'requirements.txt':
                    full_path = os.path.join(root, name)
                    try:
                        with open(full_path, 'r') as f:
                            requirements_content = [
                                line.strip().lower()
                                for line in f.readlines()
                                if line.strip() and not line.startswith('#')
                            ]
                    except Exception as e:
                        print(f"Could not read requirements.txt: {e}")

        # Detect data engineering technologies from requirements
        for req in requirements_content:
            package_name = req.split('==')[0].split('>=')[0].split('<=')[0].strip()
            if package_name in DATA_ENGINEERING_INDICATORS:
                detected_de_technologies.append(
                    DATA_ENGINEERING_INDICATORS[package_name]
                )

        # Calculate project maturity score (0-5)
        maturity_score = 0
        if has_tests:
            maturity_score += 1
        if has_ci_cd:
            maturity_score += 1
        if has_documentation:
            maturity_score += 1
        if category_counts.get('config_files', 0) > 0:
            maturity_score += 1
        if category_counts.get('infrastructure_files', 0) > 0:
            maturity_score += 1

        return {
            "files": file_list,
            "total_file_count": len(file_list),
            "extension_breakdown": dict(extension_counts),
            "category_breakdown": dict(category_counts),
            "top_level_directories": list(directory_structure),
            "max_directory_depth": max_depth,
            "has_ci_cd_pipeline": has_ci_cd,
            "has_tests": has_tests,
            "has_documentation": has_documentation,
            "detected_de_technologies": detected_de_technologies,
            "project_maturity_score": maturity_score,
            "maturity_out_of": 5,
            "repo_url": repo_url
        }

    except subprocess.CalledProcessError as e:
        print(f"Git command failed: {e.stderr}")
        return {"files": [], "error": str(e.stderr)}
    except Exception as e:
        print(f"Unexpected error: {e}")
        return {"files": [], "error": str(e)}


def handler(event, context):
    """Main Lambda handler for the repository intelligence scanner."""
    print(f"Event received: {json.dumps(event)}")

    repo_url = None
    try:
        properties = event['requestBody']['content']['application/json']['properties']
        repo_url = next(
            (prop['value'] for prop in properties if prop['name'] == 'repo_url'),
            None
        )
    except (KeyError, StopIteration):
        print("Error: Could not parse repo_url from event.")

    if not repo_url:
        result = {"files": [], "error": "repo_url parameter is required"}
    else:
        result = analyze_repository(repo_url)

    api_response = {
        'messageVersion': '1.0',
        'response': {
            'actionGroup': event['actionGroup'],
            'apiPath': event['apiPath'],
            'httpMethod': event['httpMethod'],
            'httpStatusCode': 200,
            'responseBody': {
                'application/json': {
                    'body': json.dumps(result)
                }
            }
        }
    }

    return api_response