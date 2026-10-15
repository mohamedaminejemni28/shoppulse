FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY producer.py consumer_to_minio.py ./

CMD ["python", "producer.py"]
