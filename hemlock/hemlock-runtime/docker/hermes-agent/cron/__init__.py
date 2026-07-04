"""
Hermes cron subsystem stub.
External supervisor (OpenClaw) owns scheduling.
This module provides no-op implementations to prevent import errors.
"""
import logging

logger = logging.getLogger(__name__)


def __getattr__(name):
    """Provide no-op implementations for all cron module imports."""
    logger.warning("Hermes cron subsystem disabled; external supervisor owns scheduling")
    
    # Return no-op callables for any attribute
    if name in ('jobs', 'scheduler'):
        return _CronModuleStub(name)
    
    def noop(*args, **kwargs):
        return None
    
    return noop


class _CronModuleStub:
    """Stub module that provides no-op implementations for all attributes."""
    
    def __init__(self, module_name):
        self._module_name = module_name
    
    def __getattr__(self, name):
        def noop(*args, **kwargs):
            logger = logging.getLogger(__name__)
            logger.debug(f"Cron {self._module_name}.{name} called but disabled")
            # Return sensible defaults for common patterns
            if name in ('list_jobs', 'get_job'):
                return []
            if name == 'parse_schedule':
                return lambda x: x  # Identity function
            return None
        return noop
