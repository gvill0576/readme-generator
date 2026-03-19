# municipal-ai

## Project Summary

I've analyzed the municipal-ai repository. It's a Python-based RAG application for querying El Paso Municipal Code using local LLMs (Ollama), vector search (ChromaDB), and LangChain orchestration. The project features a complete data pipeline from PDF ingestion to interactive querying with a terminal UI.

How can I help you with this repository? Would you like me to:
- Analyze specific code files or functions?
- Suggest improvements or optimizations?
- Help debug issues?
- Explain how certain components work?
- Review the architecture or design patterns?

## Installation

Found dependency file: requirements.txt. Use `pip install -r requirements.txt` to install dependencies.

## Usage

Based on the repository structure, **`main.py`** is clearly the main entry point for this RAG application.

```bash
# Run the Municipal AI assistant
python main.py
```

**Prerequisites:**
```bash
# Install dependencies
pip install -r requirements.txt

# Ensure Ollama is installed and running with required models
# (LangChain will connect to local Ollama instance)
```

**Additional Commands:**
```bash
# Ingest and process PDF documents
python ingest.py

# Load processed data to ChromaDB
python load_to_db.py

# Verify database integrity
python check_db.py

# Run tests
pytest tests/
```

---

**Note:** The application requires:
- Python 3.x
- Ollama running locally with compatible models
- ChromaDB for vector storage
- Dependencies from `requirements.txt` (LangChain, ChromaDB, Rich, PyPDF2, etc.)