"""
Session Store with Resurrection Hooks

Provides persistent session storage with automatic restoration capabilities.
"""

import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional, Any, List
from hermes_constants import get_hermes_home

logger = logging.getLogger(__name__)


class SessionStore:
    """Persistent session storage with resurrection support."""
    
    def __init__(self, hermes_home: Optional[Path] = None):
        self.hermes_home = hermes_home or get_hermes_home()
        self.sessions_dir = self.hermes_home / 'sessions'
        self.sessions_dir.mkdir(parents=True, exist_ok=True)
        
    def _session_path(self, session_id: str) -> Path:
        """Get path for session file."""
        return self.sessions_dir / f'{session_id}.json'
        
    def create_session(self, session_id: str, initial_data: Dict[str, Any] = None) -> Dict:
        """Create a new session."""
        session = {
            'id': session_id,
            'created_at': datetime.now().isoformat(),
            'updated_at': datetime.now().isoformat(),
            'messages': [],
            'context': {},
            'metadata': initial_data or {}
        }
        
        self.save_session(session)
        logger.info(f"Created session: {session_id}")
        return session
        
    def save_session(self, session: Dict):
        """Save session to persistent storage."""
        session['updated_at'] = datetime.now().isoformat()
        
        session_path = self._session_path(session['id'])
        with open(session_path, 'w') as f:
            json.dump(session, f, indent=2)
            
    def load_session(self, session_id: str) -> Optional[Dict]:
        """Load session from persistent storage."""
        session_path = self._session_path(session_id)
        
        if not session_path.exists():
            return None
            
        try:
            with open(session_path) as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Failed to load session {session_id}: {e}")
            return None
            
    def get_or_create_session(self, session_id: str) -> Dict:
        """Get existing session or create new one."""
        session = self.load_session(session_id)
        
        if session is None:
            session = self.create_session(session_id)
            
        return session
        
    def add_message(self, session_id: str, message: Dict):
        """Add message to session."""
        session = self.get_or_create_session(session_id)
        session['messages'].append({
            **message,
            'timestamp': datetime.now().isoformat()
        })
        self.save_session(session)
        
    def get_messages(self, session_id: str, limit: int = 50) -> List[Dict]:
        """Get recent messages from session."""
        session = self.load_session(session_id)
        
        if session is None:
            return []
            
        return session['messages'][-limit:]
        
    def update_context(self, session_id: str, context: Dict):
        """Update session context."""
        session = self.get_or_create_session(session_id)
        session['context'].update(context)
        self.save_session(session)
        
    def list_sessions(self) -> List[Dict]:
        """List all sessions."""
        sessions = []
        
        for session_file in self.sessions_dir.glob('*.json'):
            try:
                with open(session_file) as f:
                    session = json.load(f)
                sessions.append({
                    'id': session['id'],
                    'created_at': session['created_at'],
                    'updated_at': session['updated_at'],
                    'message_count': len(session.get('messages', []))
                })
            except Exception as e:
                logger.warning(f"Failed to read session {session_file}: {e}")
                
        return sorted(sessions, key=lambda s: s['updated_at'], reverse=True)
        
    def delete_session(self, session_id: str):
        """Delete session."""
        session_path = self._session_path(session_id)
        
        if session_path.exists():
            session_path.unlink()
            logger.info(f"Deleted session: {session_id}")
            
    def resurrect_sessions(self) -> Dict[str, Dict]:
        """Resurrect all sessions from persistent storage."""
        sessions = {}
        
        for session_data in self.list_sessions():
            session_id = session_data['id']
            full_session = self.load_session(session_id)
            
            if full_session:
                sessions[session_id] = full_session
                logger.info(f"Resurrected session: {session_id} ({session_data['message_count']} messages)")
                
        logger.info(f"Resurrected {len(sessions)} sessions")
        return sessions


class PairingStore:
    """Persistent storage for platform pairings (Telegram, Discord, etc.)."""
    
    def __init__(self, hermes_home: Optional[Path] = None):
        self.hermes_home = hermes_home or get_hermes_home()
        self.pairings_dir = self.hermes_home / 'pairings'
        self.pairings_dir.mkdir(parents=True, exist_ok=True)
        
    def _pairing_path(self, platform: str, user_id: str) -> Path:
        """Get path for pairing file."""
        return self.pairings_dir / f'{platform}_{user_id}.json'
        
    def create_pairing(self, platform: str, user_id: str, session_id: str, metadata: Dict = None):
        """Create a new platform pairing."""
        pairing = {
            'platform': platform,
            'user_id': user_id,
            'session_id': session_id,
            'created_at': datetime.now().isoformat(),
            'updated_at': datetime.now().isoformat(),
            'metadata': metadata or {}
        }
        
        pairing_path = self._pairing_path(platform, user_id)
        with open(pairing_path, 'w') as f:
            json.dump(pairing, f, indent=2)
            
        logger.info(f"Created pairing: {platform}/{user_id}")
        return pairing
        
    def get_pairing(self, platform: str, user_id: str) -> Optional[Dict]:
        """Get existing pairing."""
        pairing_path = self._pairing_path(platform, user_id)
        
        if not pairing_path.exists():
            return None
            
        try:
            with open(pairing_path) as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Failed to load pairing {platform}/{user_id}: {e}")
            return None
            
    def update_pairing(self, platform: str, user_id: str, updates: Dict):
        """Update existing pairing."""
        pairing = self.get_pairing(platform, user_id)
        
        if pairing is None:
            return None
            
        pairing.update(updates)
        pairing['updated_at'] = datetime.now().isoformat()
        
        pairing_path = self._pairing_path(platform, user_id)
        with open(pairing_path, 'w') as f:
            json.dump(pairing, f, indent=2)
            
        return pairing
        
    def resurrect_pairings(self) -> Dict[str, Dict]:
        """Resurrect all pairings from persistent storage."""
        pairings = {}
        
        for pairing_file in self.pairings_dir.glob('*.json'):
            try:
                with open(pairing_file) as f:
                    pairing = json.load(f)
                key = f"{pairing['platform']}_{pairing['user_id']}"
                pairings[key] = pairing
            except Exception as e:
                logger.warning(f"Failed to read pairing {pairing_file}: {e}")
                
        logger.info(f"Resurrected {len(pairings)} pairings")
        return pairings
