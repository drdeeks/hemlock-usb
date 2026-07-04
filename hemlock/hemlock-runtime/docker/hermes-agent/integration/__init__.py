"""
OpenClaw-Hermes Integration Package

OpenClaw hosts Hermes cognition without replacing it.
"""

from .openclaw_bridge import (
    OpenClawHermesBridge,
    OpenClawRuntimeHost,
    TransportLayer,
    create_integration_layer
)

__all__ = [
    'OpenClawHermesBridge',
    'OpenClawRuntimeHost',
    'TransportLayer',
    'create_integration_layer'
]
