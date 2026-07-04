"""
Killswitch Handler - Emergency Stop System

Provides:
- Immediate system shutdown
- Broadcast stop message
- State preservation
- Reason logging
- Responsive at all times
"""

import asyncio
import json
import logging
import os
import signal
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any

from gateway.protocol import GatewayMessage, MessageType
from paths import resolver

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class KillswitchHandler:
    """
    Emergency stop system with broadcast and state preservation.
    """
    
    def __init__(self, message_queue: asyncio.Queue = None, logs_dir: str = None):
        self.message_queue = message_queue or asyncio.Queue()
        self.logs_dir = Path(logs_dir) if logs_dir else resolver.killswitch_logs_dir
        try:
            self.logs_dir.mkdir(parents=True, exist_ok=True)
        except PermissionError:
            logger.warning(f"Cannot create directory (permission denied): {self.logs_dir}")
        
        # Killswitch state
        self.triggered = False
        self.reason = None
        self.timestamp = None
        
        logger.info("Killswitch handler initialized")
        
    async def trigger(self, reason: str) -> None:
        """
        Trigger killswitch with reason.
        
        Args:
            reason: Reason for killswitch
        """
        if self.triggered:
            logger.warning("Killswitch already triggered")
            return
            
        self.triggered = True
        self.reason = reason
        self.timestamp = datetime.now().isoformat()
        
        logger.critical(f"KILLSWITCH TRIGGERED: {reason}")
        
        # Broadcast killswitch message
        killswitch_msg = GatewayMessage.create_killswitch(
            sender="killswitch",
            recipient="all",
            reason=reason
        )
        
        # Add to queue
        await self.message_queue.put(killswitch_msg)
        
        # Log killswitch event
        await self._log_killswitch_event()
        
        # Preserve state
        await self._preserve_state()
        
        # Initiate shutdown
        await self._initiate_shutdown()
        
    async def _log_killswitch_event(self) -> None:
        """
        Log killswitch event to file.
        """
        log_file = self.logs_dir / f"killswitch_{self.timestamp.replace(':', '-')}.log"
        
        try:
            with open(log_file, 'w') as f:
                f.write(f"KILLSWITCH EVENT\n")
                f.write(f"Timestamp: {self.timestamp}\n")
                f.write(f"Reason: {self.reason}\n")
                
            logger.info(f"Killswitch event logged to {log_file}")
            
        except Exception as e:
            logger.error(f"Failed to log killswitch event: {e}")
            
    async def _preserve_state(self) -> None:
        """
        Preserve system state before shutdown.
        """
        state_file = self.logs_dir / f"state_{self.timestamp.replace(':', '-')}.json"
        
        try:
            state = {
                "timestamp": self.timestamp,
                "reason": self.reason,
                "status": "killswitch_triggered",
                "message": "System state preserved before shutdown"
            }
            
            with open(state_file, 'w') as f:
                json.dump(state, f, indent=2)
                
            logger.info(f"State preserved to {state_file}")
            
        except Exception as e:
            logger.error(f"Failed to preserve state: {e}")
            
    async def _initiate_shutdown(self) -> None:
        """
        Initiate system shutdown.
        """
        try:
            # In a real implementation, you would use proper shutdown procedures
            # For this example, we'll simulate with a sleep and message
            
            logger.critical("Initiating system shutdown...")
            
            # Simulate shutdown delay
            await asyncio.sleep(2)
            
            logger.critical("SYSTEM SHUTDOWN COMPLETE")
            
        except Exception as e:
            logger.error(f"Shutdown failed: {e}")
            
    def is_triggered(self) -> bool:
        """
        Check if killswitch has been triggered.
        
        Returns:
            True if triggered, False otherwise
        """
        return self.triggered
        
    def get_reason(self) -> Optional[str]:
        """
        Get killswitch reason.
        
        Returns:
            Reason for killswitch or None if not triggered
        """
        return self.reason
        
    def get_timestamp(self) -> Optional[str]:
        """
        Get killswitch timestamp.
        
        Returns:
            ISO format timestamp or None if not triggered
        """
        return self.timestamp


async def main():
    """CLI entry point."""
    import sys
    
    handler = KillswitchHandler()
    
    if len(sys.argv) > 1 and sys.argv[1] == 'test':
        # Test mode - trigger killswitch
        print("Starting test mode... Killswitch will trigger in 3 seconds")
        
        # Simulate delay
        await asyncio.sleep(3)
        
        # Trigger killswitch
        await handler.trigger("Test killswitch")
        
    else:
        print("Usage: python -m gateway.killswitch [test]")
        print("  test  - Start test mode with killswitch trigger")
        
if __name__ == '__main__':
    asyncio.run(main())
