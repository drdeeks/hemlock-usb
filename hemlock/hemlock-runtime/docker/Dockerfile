FROM python:3.11-slim AS builder

WORKDIR /opt/openclaw

# Copy Hermes runtime
COPY docker/hermes-agent /opt/hermes

# Allow root runtime imports
ENV PYTHONPATH="/opt/hermes:${PYTHONPATH}"

# Install editable CLI/runtime bindings
RUN pip install --no-cache-dir -e /opt/hermes/hermes_cli

# Optional OpenClaw runtime installation
COPY docker/openclaw-runtime /opt/openclaw-runtime

RUN pip install --no-cache-dir /opt/openclaw-runtime || true

FROM python:3.11-slim AS framework

WORKDIR /srv/framework

COPY --from=builder /usr/local /usr/local
COPY --from=builder /opt/hermes /opt/hermes

ENV PYTHONPATH="/opt/hermes:${PYTHONPATH}"

CMD ["python", "/srv/framework/runtime/openclaw_supervisor.py"]
