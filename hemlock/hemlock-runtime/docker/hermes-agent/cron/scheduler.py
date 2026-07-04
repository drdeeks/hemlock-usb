"""
Hermes cron scheduler stub.
External supervisor (OpenClaw) owns scheduling.
"""
import logging

logger = logging.getLogger(__name__)


def tick(verbose=False, adapters=None, loop=None):
    """No-op tick function."""
    logger.warning("Hermes cron subsystem disabled; external supervisor owns scheduling")
    return
