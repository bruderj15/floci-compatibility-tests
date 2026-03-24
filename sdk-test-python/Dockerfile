FROM python:3.12-slim
WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY test_all.py .

ENV FLOCI_ENDPOINT=http://floci:4566

ENTRYPOINT ["python", "test_all.py"]
