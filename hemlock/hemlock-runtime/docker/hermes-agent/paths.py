"""
PathResolver - Portable Path Resolution for Hemlock Runtime

Eliminates hardcoded paths across the codebase by providing a centralized,
environment-driven path resolution system. Every path is configurable via
environment variables with sensible defaults that adapt to the runtime context
(Docker container vs. local development).

Environment Variables:
    HEMLOCK_ROOT:     Project root directory (default: auto-detected)
    HERMES_HOME:      Hermes runtime home (default: /runtime in Docker, {root}/docker/hermes-agent otherwise)
    HERMES_AGENTS:    Agents directory
    HERMES_CREWS:     Crews directory
    HERMES_PROJECTS:  Projects directory
    HERMES_SKILLS:    Skills root (RO mount)
    HERMES_LOGS:      Logs directory
    HERMES_MEMORY:    Autonomy memory directory
    HERMES_PLUGINS:   Plugins directory
    HERMES_CONFIG:    Config directory
    HERMES_SCRIPTS:   Scripts directory
    HERMES_MODELS:    Models directory
    HERMES_KNOWLEDGE: Knowledge base directory (RO mount)

    Infrastructure paths (Docker/production):
    OPENCLAW_ROOT:       OpenClaw root directory
    OPENCLAW_CONFIG:     OpenClaw config directory
    OPENCLAW_LOGS:       OpenClaw logs directory
    OPENCLAW_RUNTIME:    Framework runtime directory
    OPENCLAW_VOLUMES:    Framework volumes directory
    OPENCLAW_REGISTRY:   MCP registry path

Detection:
    - Running inside Docker: /proc/1/cgroup contains 'docker' or '.dockerenv' exists
    - Project root: walks up from __file__ to find hemlock marker (.hemlock-root or git)
"""

import os
import logging
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

_DOCKER_MARKERS = ['/.dockerenv', '/proc/1/cgroup']
_HEMLOCK_MARKERS = ['.hemlock-root', '.git', 'hemlock.imhere']
_MARKER_DIRS = ['docker', 'skills', 'agents', 'scripts']


class PathResolutionError(Exception):
    """Raised when a required path cannot be resolved."""
    pass


class PathResolver:
    """
    Centralized, environment-driven path resolver.

    Resolves all filesystem paths from environment variables, falling back
    to context-aware defaults based on whether running in Docker or locally.

    Usage:
        from paths import resolver

        agents_dir = resolver.agents_dir
        skills_root = resolver.skills_root
        logs_dir = resolver.path('logs')

        # Override for testing
        resolver = PathResolver(root='/tmp/test')
    """

    _instance: Optional['PathResolver'] = None

    def __init__(self, root: Optional[str] = None):
        """
        Initialize PathResolver.

        Args:
            root: Override project root (for testing or custom installs).
                  If not provided, auto-detected from environment or filesystem.
        """
        self._is_docker = self._detect_docker()
        self._root = Path(root) if root else self._detect_root()
        self._cache: dict = {}
        logger.debug(f"PathResolver initialized: root={self._root}, docker={self._is_docker}")

    @classmethod
    def get_instance(cls) -> 'PathResolver':
        """Get or create the singleton PathResolver instance."""
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    @classmethod
    def reset_instance(cls):
        """Reset the singleton (for testing)."""
        cls._instance = None

    @staticmethod
    def _detect_docker() -> bool:
        """Detect if running inside a Docker container."""
        env_val = os.getenv('HEMLOCK_DOCKER', '').lower()
        if env_val in ('1', 'true', 'yes'):
            return True
        if env_val in ('0', 'false', 'no'):
            return False
        for marker in _DOCKER_MARKERS:
            if Path(marker).exists():
                try:
                    if marker == '/proc/1/cgroup':
                        content = Path(marker).read_text()
                        if 'docker' in content or 'containerd' in content:
                            return True
                except (OSError, PermissionError):
                    continue
                return True
        return False

    @staticmethod
    def _detect_root() -> Path:
        """
        Auto-detect project root by walking up from this file.

        Looks for HEMLOCK_ROOT env var first, then walks up from the
        installed module location looking for project markers.
        """
        env_root = os.getenv('HEMLOCK_ROOT')
        if env_root:
            return Path(env_root)

        start = Path(__file__).resolve()
        current = start.parent
        for _ in range(20):
            for marker in _HEMLOCK_MARKERS:
                if (current / marker).exists():
                    return current
            has_dirs = all((current / d).exists() for d in _MARKER_DIRS[:2])
            if has_dirs:
                return current
            parent = current.parent
            if parent == current:
                break
            current = parent

        return Path.cwd()

    def _env(self, key: str, default: str) -> Path:
        """Resolve a path from environment variable or default."""
        value = os.getenv(key)
        if value:
            return Path(value)
        return Path(default)

    def _ensure(self, path: Path) -> Path:
        """Ensure directory exists (lazy creation)."""
        try:
            path.mkdir(parents=True, exist_ok=True)
        except PermissionError:
            logger.warning(f"Cannot create directory (permission denied): {path}")
        return path

    @property
    def is_docker(self) -> bool:
        """Whether running inside a Docker container."""
        return self._is_docker

    @property
    def root(self) -> Path:
        """Project root directory."""
        return self._root

    @property
    def hermes_home(self) -> Path:
        """Hermes runtime home (HERMES_HOME)."""
        if 'hermes_home' not in self._cache:
            default = '/runtime' if self._is_docker else str(self._root / 'docker' / 'hermes-agent')
            self._cache['hermes_home'] = self._env('HERMES_HOME', default)
        return self._cache['hermes_home']

    @property
    def agents_dir(self) -> Path:
        """Agents directory."""
        if 'agents_dir' not in self._cache:
            default = '/data/agents' if self._is_docker else str(self._root / 'agents')
            self._cache['agents_dir'] = self._env('HERMES_AGENTS', default)
        return self._cache['agents_dir']

    @property
    def crews_dir(self) -> Path:
        """Crews directory."""
        if 'crews_dir' not in self._cache:
            default = '/data/crews' if self._is_docker else str(self._root / 'crews')
            self._cache['crews_dir'] = self._env('HERMES_CREWS', default)
        return self._cache['crews_dir']

    @property
    def projects_dir(self) -> Path:
        """Projects directory."""
        if 'projects_dir' not in self._cache:
            default = '/projects' if self._is_docker else str(self._root / 'projects')
            self._cache['projects_dir'] = self._env('HERMES_PROJECTS', default)
        return self._cache['projects_dir']

    @property
    def skills_root(self) -> Path:
        """Skills root (read-only mount)."""
        if 'skills_root' not in self._cache:
            if self._is_docker:
                default = '/skills'
            else:
                local = self._root / 'skills' / 'skills'
                default = str(local) if local.exists() else '/skills'
            self._cache['skills_root'] = self._env('HERMES_SKILLS', default)
        return self._cache['skills_root']

    @property
    def logs_dir(self) -> Path:
        """Logs directory."""
        if 'logs_dir' not in self._cache:
            default = '/logs' if self._is_docker else str(self._root / 'logs')
            self._cache['logs_dir'] = self._env('HERMES_LOGS', default)
        return self._cache['logs_dir']

    @property
    def memory_dir(self) -> Path:
        """Autonomy memory/decisions directory."""
        if 'memory_dir' not in self._cache:
            default = '/memory' if self._is_docker else str(self._root / 'memory')
            self._cache['memory_dir'] = self._env('HERMES_MEMORY', default)
        return self._cache['memory_dir']

    @property
    def plugins_dir(self) -> Path:
        """Plugins directory."""
        if 'plugins_dir' not in self._cache:
            default = '/plugins' if self._is_docker else str(self._root / 'plugins')
            self._cache['plugins_dir'] = self._env('HERMES_PLUGINS', default)
        return self._cache['plugins_dir']

    @property
    def backups_dir(self) -> Path:
        """Backup/archive directory."""
        if 'backups_dir' not in self._cache:
            default = '/data/archive' if self._is_docker else str(self._root / '.archive')
            self._cache['backups_dir'] = self._env('HERMES_BACKUPS', default)
        return self._cache['backups_dir']

    @property
    def config_dir(self) -> Path:
        """Config directory."""
        if 'config_dir' not in self._cache:
            default = '/config' if self._is_docker else str(self._root / 'config')
            self._cache['config_dir'] = self._env('HERMES_CONFIG', default)
        return self._cache['config_dir']

    @property
    def scripts_dir(self) -> Path:
        """Scripts directory."""
        if 'scripts_dir' not in self._cache:
            default = '/scripts' if self._is_docker else str(self._root / 'scripts')
            self._cache['scripts_dir'] = self._env('HERMES_SCRIPTS', default)
        return self._cache['scripts_dir']

    @property
    def models_dir(self) -> Path:
        """Models directory."""
        if 'models_dir' not in self._cache:
            default = '/models' if self._is_docker else str(self._root / 'models')
            self._cache['models_dir'] = self._env('HERMES_MODELS', default)
        return self._cache['models_dir']

    @property
    def knowledge_base_dir(self) -> Path:
        """Knowledge base directory (read-only mount)."""
        if 'knowledge_base_dir' not in self._cache:
            default = '/knowledge_base' if self._is_docker else str(self._root / 'knowledge_base')
            self._cache['knowledge_base_dir'] = self._env('HERMES_KNOWLEDGE', default)
        return self._cache['knowledge_base_dir']

    @property
    def gateway_logs_dir(self) -> Path:
        """Gateway-specific logs directory."""
        return self.logs_dir / 'gateway'

    @property
    def killswitch_logs_dir(self) -> Path:
        """Killswitch-specific logs directory."""
        return self.logs_dir / 'killswitch'

    @property
    def autonomy_memory_dir(self) -> Path:
        """Autonomy protocol memory directory."""
        return self.memory_dir / 'autonomy'

    @property
    def plugin_backups_dir(self) -> Path:
        """Plugin backup directory."""
        return self.backups_dir / 'plugins'

    @property
    def projects_decisions_dir(self) -> Path:
        """Project decisions directory."""
        return self.projects_dir / 'decisions'

    def path(self, name: str) -> Path:
        """
        Resolve a path by name (case-insensitive).

        Args:
            name: One of: root, hermes_home, agents_dir, crews_dir,
                  projects_dir, skills_root, logs_dir, memory_dir,
                  plugins_dir, backups_dir, config_dir, scripts_dir,
                  models_dir, gateway_logs_dir, killswitch_logs_dir,
                  autonomy_memory_dir, plugin_backups_dir, projects_decisions_dir

        Returns:
            Resolved Path object

        Raises:
            PathResolutionError: If name is not recognized
        """
        key = name.lower().replace('-', '_')
        known = {
            'root': self.root,
            'hermes_home': self.hermes_home,
            'agents_dir': self.agents_dir,
            'crews_dir': self.crews_dir,
            'projects_dir': self.projects_dir,
            'skills_root': self.skills_root,
            'logs_dir': self.logs_dir,
            'memory_dir': self.memory_dir,
            'plugins_dir': self.plugins_dir,
            'backups_dir': self.backups_dir,
            'config_dir': self.config_dir,
            'scripts_dir': self.scripts_dir,
            'models_dir': self.models_dir,
            'knowledge_base_dir': self.knowledge_base_dir,
            'gateway_logs_dir': self.gateway_logs_dir,
            'killswitch_logs_dir': self.killswitch_logs_dir,
            'autonomy_memory_dir': self.autonomy_memory_dir,
            'plugin_backups_dir': self.plugin_backups_dir,
            'projects_decisions_dir': self.projects_decisions_dir,
        }
        if key not in known:
            raise PathResolutionError(
                f"Unknown path name: '{name}'. Known paths: {sorted(known.keys())}"
            )
        return known[key]

    def ensure_dirs(self, *names: str) -> None:
        """
        Ensure directories exist for named paths.

        Args:
            *names: Path names to ensure exist. If empty, ensures all.
        """
        if not names:
            names = (
                'agents_dir', 'crews_dir', 'projects_dir', 'skills_root',
                'logs_dir', 'memory_dir', 'plugins_dir', 'backups_dir',
                'config_dir', 'scripts_dir', 'models_dir', 'knowledge_base_dir',
            )
        for name in names:
            resolved = self.path(name)
            self._ensure(resolved)

    def to_dict(self) -> dict:
        """Export all resolved paths as a dictionary."""
        return {
            'root': str(self.root),
            'is_docker': self.is_docker,
            'hermes_home': str(self.hermes_home),
            'agents_dir': str(self.agents_dir),
            'crews_dir': str(self.crews_dir),
            'projects_dir': str(self.projects_dir),
            'skills_root': str(self.skills_root),
            'logs_dir': str(self.logs_dir),
            'memory_dir': str(self.memory_dir),
            'plugins_dir': str(self.plugins_dir),
            'backups_dir': str(self.backups_dir),
            'config_dir': str(self.config_dir),
            'scripts_dir': str(self.scripts_dir),
            'models_dir': str(self.models_dir),
            'knowledge_base_dir': str(self.knowledge_base_dir),
            'gateway_logs_dir': str(self.gateway_logs_dir),
            'killswitch_logs_dir': str(self.killswitch_logs_dir),
            'autonomy_memory_dir': str(self.autonomy_memory_dir),
            'plugin_backups_dir': str(self.plugin_backups_dir),
            'projects_decisions_dir': str(self.projects_decisions_dir),
        }


resolver = PathResolver.get_instance()