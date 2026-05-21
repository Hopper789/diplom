FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY boinc_exporter.py .

EXPOSE 9101

CMD ["python", "boinc_exporter.py"]
