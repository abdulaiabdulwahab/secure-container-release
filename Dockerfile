# Use a smaller production base image.
FROM python:3.12-slim-trixie

# Prevent creation of .pyc files.
ENV PYTHONDONTWRITEBYTECODE=1

# Send Python output directly to logs.
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Create a dedicated unprivileged user.
RUN groupadd --system appgroup \
    && useradd \
       --system \
       --gid appgroup \
       --create-home \
       appuser

# Copy dependency file first.
COPY requirements.txt .

# Install only required dependencies.
RUN pip install \
    --no-cache-dir \
    -r requirements.txt

# Copy application with correct ownership.
COPY --chown=appuser:appgroup app.py .

# Stop running as root.
USER appuser

EXPOSE 5000

CMD ["python", "app.py"]