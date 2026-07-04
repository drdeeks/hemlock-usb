"""
Hermes Plugins Package

Plugin management and injection system.
"""

from .plugin_manager import PluginManager, InjectionResult

__all__ = ['PluginManager', 'InjectionResult']
