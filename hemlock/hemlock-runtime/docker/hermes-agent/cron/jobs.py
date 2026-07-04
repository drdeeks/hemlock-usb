"""
Hermes cron jobs stub.
External supervisor (OpenClaw) owns scheduling.
"""
import logging

logger = logging.getLogger(__name__)


def list_jobs(include_disabled=False):
    """Return empty list - no jobs managed by Hermes."""
    logger.debug("Cron jobs.list_jobs called but disabled")
    return []


def get_job(job_id):
    """Return None - no jobs managed by Hermes."""
    logger.debug("Cron jobs.get_job called but disabled")
    return None


def create_job(**kwargs):
    """No-op job creation."""
    logger.warning("Hermes cron subsystem disabled; cannot create job")
    return None


def update_job(job_id, **kwargs):
    """No-op job update."""
    logger.warning("Hermes cron subsystem disabled; cannot update job")
    return None


def remove_job(job_id):
    """No-op job removal."""
    logger.warning("Hermes cron subsystem disabled; cannot remove job")
    return None


def pause_job(job_id):
    """No-op job pause."""
    logger.warning("Hermes cron subsystem disabled; cannot pause job")
    return None


def resume_job(job_id):
    """No-op job resume."""
    logger.warning("Hermes cron subsystem disabled; cannot resume job")
    return None


def trigger_job(job_id):
    """No-op job trigger."""
    logger.warning("Hermes cron subsystem disabled; cannot trigger job")
    return None


def parse_schedule(schedule_str):
    """Return identity - scheduling handled externally."""
    logger.debug("Cron jobs.parse_schedule called but disabled")
    return schedule_str
