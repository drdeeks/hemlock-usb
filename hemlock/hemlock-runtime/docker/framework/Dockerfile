FROM python:3.11-slim

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV HERMES_HOME=/runtime

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        git \
        curl \
        && rm -rf /var/lib/apt/lists/*

# Create runtime directories
RUN mkdir -p \
    /runtime \
    /agents \
    /models \
    /backups \
    /opt/hermes \
    /opt/openclaw-runtime

# Copy Hermes agent runtime
COPY docker/hermes-agent/ /opt/hermes/

# Copy OpenClaw runtime
COPY docker/openclaw-runtime/ /opt/openclaw-runtime/

# Install Python dependencies
RUN pip install --no-cache-dir \
    /opt/openclaw-runtime \
    /opt/hermes \
    pyyaml \
    python-dotenv \
    python-telegram-bot \
    mcp

# Set working directory
WORKDIR /srv/framework

# Health check script
COPY health/imports/imports_validator.py /health/imports/
RUN chmod +x /health/imports/imports_validator.py

# Default command
CMD ["python", "-c", "print('Framework base image ready')"]