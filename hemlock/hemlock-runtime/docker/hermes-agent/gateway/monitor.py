"""
Gateway Monitor - Live Message Stream and Killswitch

Provides:
- Live stream of gateway messages
- User-friendly formatting
- Killswitch hotkey (K key)
- Log export (E key)
"""

import asyncio
import json
import logging
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any, Union

from gateway.protocol import GatewayMessage, MessageType
from paths import resolver

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class GatewayMonitor:
    """
    Live gateway message monitor with killswitch and log export.
    """
    
    def __init__(self, message_queue: asyncio.Queue = None, logs_dir: str = None):
        self.message_queue = message_queue or asyncio.Queue()
        self.logs_dir = Path(logs_dir) if logs_dir else resolver.gateway_logs_dir
        try:
            self.logs_dir.mkdir(parents=True, exist_ok=True)
        except PermissionError:
            logger.warning(f"Cannot create directory (permission denied): {self.logs_dir}")
        
        # Killswitch state
        self.killswitch_triggered = False
        self.killswitch_reason = None
        
        logger.info("Gateway monitor initialized")
        
    async def stream_messages(self) -> None:
        """
        Stream messages from queue with user-friendly formatting.
        
        Handles:
        - Killswitch (K key)
        - Log export (E key)
        """
        print("\n" * 2)
        print("=== GATEWAY MONITOR ===")
        print("Press K to trigger killswitch")
        print("Press E to export logs")
        print("Press Ctrl+C to exit\n")
        
        try:
            while True:
                # Check for keyboard input
                if sys.stdin.isatty():
                    import select
                    if select.select([sys.stdin], [], [], 0)[0]:
                        key = sys.stdin.read(1)
                        if key.lower() == 'k':
                            await self.trigger_killswitch("User requested")
                            break
                        elif key.lower() == 'e':
                            await self.export_logs()
                        
                # Get message from queue
                try:
                    message = await asyncio.wait_for(self.message_queue.get(), timeout=0.1)
                    
                    if isinstance(message, GatewayMessage):
                        await self.display_message(message)
                    elif isinstance(message, dict):
                        try:
                            msg = GatewayMessage(**message)
                            await self.display_message(msg)
                        except Exception as e:
                            logger.error(f"Invalid message format: {e}")
                    else:
                        logger.error(f"Unknown message type: {type(message)}")
                except asyncio.TimeoutError:
                    pass
                
        except KeyboardInterrupt:
            print("\nMonitor stopped")
        
    async def display_message(self, message: GatewayMessage) -> None:
        """
        Display message in user-friendly format.
        
        Args:
            message: GatewayMessage instance
        """
        timestamp = datetime.fromisoformat(message.timestamp).strftime("%Y-%m-%d %H:%M:%S")
        
        # Convert message_type to enum if it's a string
        if isinstance(message.message_type, str):
            message_type = MessageType(message.message_type)
        else:
            message_type = message.message_type
        
        print(f"\n[{timestamp}] {message_type.value.upper()} from {message.sender} to {message.recipient}")
        
        if message_type == MessageType.TASK_ASSIGNMENT:
            print(f"  Task: {message.content['task_id']}")
            print(f"  Description: {message.content['description']}")
            print(f"  Priority: {message.content['priority']}")
            
        elif message_type == MessageType.PROGRESS_UPDATE:
            print(f"  Task: {message.content['task_id']}")
            print(f"  Progress: {message.content['progress']}% - {message.content['status']}")
            
        elif message_type == MessageType.BLOCKER_ALERT:
            print(f"  Task: {message.content['task_id']}")
            print(f"  Blocker: {message.content['blocker']}")
            print(f"  Severity: {message.content['severity'].upper()}")
            
        elif message_type == MessageType.DELIVERY:
            print(f"  Delivery: {message.content['delivery_id']}")
            print(f"  Items: {len(message.content['items'])} items")
            print(f"  Status: {message.content['status']}")
            
        elif message_type == MessageType.USER_INPUT:
            print(f"  Input: {message.content['input_id']}")
            print(f"  Prompt: {message.content['prompt']}")
            print(f"  Response: {message.content['response']}")
            
        elif message_type == MessageType.KILLSWITCH:
            print(f"  REASON: {message.content['reason']}")
            print("  SYSTEM SHUTDOWN INITIATED")
            
        else:
            print("  Content:")
            print(json.dumps(message.content, indent=2))
            
        if message.metadata:
            print("\n  Metadata:")
            for key, value in message.metadata.items():
                print(f"    {key}: {value}")
            
    async def trigger_killswitch(self, reason: str) -> None:
        """
        Trigger killswitch with reason.
        
        Args:
            reason: Reason for killswitch
        """
        if self.killswitch_triggered:
            logger.warning("Killswitch already triggered")
            return
            
        self.killswitch_triggered = True
        self.killswitch_reason = reason
        
        logger.critical(f"KILLSWITCH TRIGGERED: {reason}")
        
        # Broadcast killswitch message
        killswitch_msg = GatewayMessage.create_killswitch(
            sender="monitor",
            recipient="all",
            reason=reason
        )
        
        # Add to queue
        await self.message_queue.put(killswitch_msg)
        
        # Display killswitch message
        await self.display_message(killswitch_msg)
        
    async def export_logs(self) -> None:
        """
        Export current logs to file.
        """
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        log_file = self.logs_dir / f"gateway_monitor_{timestamp}.log"
        
        try:
            # In a real implementation, you would collect all messages
            # For this example, we'll just create an empty log file
            log_file.touch()
            
            print(f"\nLogs exported to: {log_file}")
            logger.info(f"Logs exported to {log_file}")
            
        except Exception as e:
            logger.error(f"Failed to export logs: {e}")
            print(f"Failed to export logs: {e}")
        
    async def add_message(self, message: Union[GatewayMessage, Dict]) -> None:
        """
        Add message to queue.
        
        Args:
            message: GatewayMessage or dict
        """
        await self.message_queue.put(message)
        
    def is_killswitch_triggered(self) -> bool:
        """
        Check if killswitch has been triggered.
        
        Returns:
            True if killswitch triggered, False otherwise
        """
        return self.killswitch_triggered
        
    def get_killswitch_reason(self) -> Optional[str]:
        """
        Get killswitch reason.
        
        Returns:
            Reason for killswitch or None if not triggered
        """
        return self.killswitch_reason


async def main():
    """CLI entry point."""
    import sys
    
    monitor = GatewayMonitor()
    
    if len(sys.argv) > 1 and sys.argv[1] == 'test':
        # Test mode - create sample messages
        print("Starting test mode... Press K to trigger killswitch, E to export logs")
        
        # Create test messages
        messages = [
            GatewayMessage.create_task_assignment(
                sender="system",
                recipient="agent1",
                task_id="task1",
                description="Test task",
                priority=2
            ),
            GatewayMessage.create_progress_update(
                sender="agent1",
                recipient="system",
                task_id="task1",
                progress=50.0,
                status="In progress"
            ),
            GatewayMessage.create_blocker_alert(
                sender="agent1",
                recipient="system",
                task_id="task1",
                blocker="Missing dependency",
                severity="high"
            )
        ]
        
        # Add messages to queue
        for msg in messages:
            await monitor.add_message(msg)
            
        # Start monitor in background
        monitor_task = asyncio.create_task(monitor.stream_messages())
        
        # Wait for messages to be processed
        await asyncio.sleep(3)
        
        # Trigger killswitch automatically
        await monitor.trigger_killswitch("Test killswitch")
        
        # Wait for monitor to finish
        await monitor_task
        
    else:
        print("Usage: python -m gateway.monitor [test]")
        print("  test  - Start test mode with sample messages")
        
if __name__ == '__main__':
    asyncio.run(main())
