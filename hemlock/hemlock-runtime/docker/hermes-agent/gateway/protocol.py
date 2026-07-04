"""
Gateway Protocol - Structured Message Communication

Implements Option A: structured JSON with metadata headers

Message Types:
- task_assignment
- progress_update
- blocker_alert
- delivery
- user_input
- killswitch
"""

import asyncio
import json
import logging
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Dict, List, Optional, Any, Union

from pydantic import BaseModel, Field, ValidationError

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class MessageType(str, Enum):
    """Enumeration of valid message types."""
    TASK_ASSIGNMENT = "task_assignment"
    PROGRESS_UPDATE = "progress_update"
    BLOCKER_ALERT = "blocker_alert"
    DELIVERY = "delivery"
    USER_INPUT = "user_input"
    KILLSWITCH = "killswitch"
    
    @classmethod
    def values(cls) -> List[str]:
        """Get list of valid message types."""
        return [item.value for item in cls]


class GatewayMessage(BaseModel):
    """
    Base model for all gateway messages.
    
    Attributes:
        message_type: Type of message (from MessageType enum)
        timestamp: ISO format timestamp
        sender: Sender identifier
        recipient: Recipient identifier
        metadata: Additional metadata
        content: Message content
    """
    
    message_type: MessageType = Field(..., description="Type of message")
    timestamp: str = Field(default_factory=lambda: datetime.now().isoformat(),
                        description="ISO format timestamp")
    sender: str = Field(..., description="Sender identifier")
    recipient: str = Field(..., description="Recipient identifier")
    metadata: Dict[str, Any] = Field(default_factory=dict, description="Additional metadata")
    content: Dict[str, Any] = Field(..., description="Message content")
    
    class Config:
        use_enum_values = True
        extra = "forbid"
        
    @classmethod
    def create_task_assignment(cls, sender: str, recipient: str, task_id: str, 
                            description: str, priority: int = 1, 
                            metadata: Optional[Dict] = None) -> 'GatewayMessage':
        """
        Create task assignment message.
        
        Args:
            sender: Sender identifier
            recipient: Recipient identifier
            task_id: Task ID
            description: Task description
            priority: Task priority (1-5)
            metadata: Additional metadata
            
        Returns:
            GatewayMessage instance
        """
        content = {
            "task_id": task_id,
            "description": description,
            "priority": priority
        }
        
        return cls(
            message_type=MessageType.TASK_ASSIGNMENT,
            sender=sender,
            recipient=recipient,
            metadata=metadata or {},
            content=content
        )
        
    @classmethod
    def create_progress_update(cls, sender: str, recipient: str, task_id: str, 
                            progress: float, status: str, 
                            metadata: Optional[Dict] = None) -> 'GatewayMessage':
        """
        Create progress update message.
        
        Args:
            sender: Sender identifier
            recipient: Recipient identifier
            task_id: Task ID
            progress: Progress percentage (0-100)
            status: Current status
            metadata: Additional metadata
            
        Returns:
            GatewayMessage instance
        """
        content = {
            "task_id": task_id,
            "progress": progress,
            "status": status
        }
        
        return cls(
            message_type=MessageType.PROGRESS_UPDATE,
            sender=sender,
            recipient=recipient,
            metadata=metadata or {},
            content=content
        )
        
    @classmethod
    def create_blocker_alert(cls, sender: str, recipient: str, task_id: str, 
                            blocker: str, severity: str, 
                            metadata: Optional[Dict] = None) -> 'GatewayMessage':
        """
        Create blocker alert message.
        
        Args:
            sender: Sender identifier
            recipient: Recipient identifier
            task_id: Task ID
            blocker: Description of blocker
            severity: Severity level (low, medium, high)
            metadata: Additional metadata
            
        Returns:
            GatewayMessage instance
        """
        content = {
            "task_id": task_id,
            "blocker": blocker,
            "severity": severity
        }
        
        return cls(
            message_type=MessageType.BLOCKER_ALERT,
            sender=sender,
            recipient=recipient,
            metadata=metadata or {},
            content=content
        )
        
    @classmethod
    def create_delivery(cls, sender: str, recipient: str, delivery_id: str, 
                        items: List[Dict], status: str, 
                        metadata: Optional[Dict] = None) -> 'GatewayMessage':
        """
        Create delivery message.
        
        Args:
            sender: Sender identifier
            recipient: Recipient identifier
            delivery_id: Delivery ID
            items: List of items being delivered
            status: Delivery status
            metadata: Additional metadata
            
        Returns:
            GatewayMessage instance
        """
        content = {
            "delivery_id": delivery_id,
            "items": items,
            "status": status
        }
        
        return cls(
            message_type=MessageType.DELIVERY,
            sender=sender,
            recipient=recipient,
            metadata=metadata or {},
            content=content
        )
        
    @classmethod
    def create_user_input(cls, sender: str, recipient: str, input_id: str, 
                        prompt: str, response: str, 
                        metadata: Optional[Dict] = None) -> 'GatewayMessage':
        """
        Create user input message.
        
        Args:
            sender: Sender identifier
            recipient: Recipient identifier
            input_id: Input ID
            prompt: User prompt
            response: User response
            metadata: Additional metadata
            
        Returns:
            GatewayMessage instance
        """
        content = {
            "input_id": input_id,
            "prompt": prompt,
            "response": response
        }
        
        return cls(
            message_type=MessageType.USER_INPUT,
            sender=sender,
            recipient=recipient,
            metadata=metadata or {},
            content=content
        )
        
    @classmethod
    def create_killswitch(cls, sender: str, recipient: str, reason: str, 
                        metadata: Optional[Dict] = None) -> 'GatewayMessage':
        """
        Create killswitch message.
        
        Args:
            sender: Sender identifier
            recipient: Recipient identifier
            reason: Reason for killswitch
            metadata: Additional metadata
            
        Returns:
            GatewayMessage instance
        """
        content = {
            "reason": reason
        }
        
        return cls(
            message_type=MessageType.KILLSWITCH,
            sender=sender,
            recipient=recipient,
            metadata=metadata or {},
            content=content
        )
        
    def to_dict(self) -> Dict:
        """Convert message to dictionary."""
        return self.dict()
        
    def to_json(self) -> str:
        """Convert message to JSON string."""
        return self.json()
        
    @classmethod
    def from_json(cls, json_str: str) -> 'GatewayMessage':
        """
        Create message from JSON string.
        
        Args:
            json_str: JSON string
            
        Returns:
            GatewayMessage instance
        """
        try:
            data = json.loads(json_str)
            return cls(**data)
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON: {e}")
            raise
        except ValidationError as e:
            logger.error(f"Validation error: {e}")
            raise
        
    def validate(self) -> bool:
        """
        Validate message content.
        
        Returns:
            True if valid, False otherwise
        """
        try:
            self.__class__(**self.dict())
            return True
        except ValidationError:
            return False
        
    def add_metadata(self, key: str, value: Any) -> None:
        """
        Add metadata to message.
        
        Args:
            key: Metadata key
            value: Metadata value
        """
        self.metadata[key] = value
        
    def get_metadata(self, key: str) -> Any:
        """
        Get metadata value.
        
        Args:
            key: Metadata key
            
        Returns:
            Metadata value or None if not found
        """
        return self.metadata.get(key)


async def main():
    """CLI entry point."""
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: python -m gateway.protocol [create|validate|convert] <args>")
        print("  create <type> <args>  - Create message of specified type")
        print("  validate <json>        - Validate message JSON")
        print("  convert <json>        - Convert JSON to message")
        sys.exit(1)
        
    command = sys.argv[1]
    
    if command == 'create':
        if len(sys.argv) < 3:
            print("Usage: create <type> <args>")
            print("Message types:")
            for msg_type in MessageType.values():
                print(f"  {msg_type}")
            sys.exit(1)
            
        msg_type = sys.argv[2]
        
        try:
            if msg_type == MessageType.TASK_ASSIGNMENT.value:
                if len(sys.argv) < 7:
                    print("Usage: create task_assignment <sender> <recipient> <task_id> <description> <priority>")
                    sys.exit(1)
                    
                sender = sys.argv[3]
                recipient = sys.argv[4]
                task_id = sys.argv[5]
                description = sys.argv[6]
                priority = int(sys.argv[7]) if len(sys.argv) > 7 else 1
                
                msg = GatewayMessage.create_task_assignment(
                    sender=sender,
                    recipient=recipient,
                    task_id=task_id,
                    description=description,
                    priority=priority
                )
                
            elif msg_type == MessageType.PROGRESS_UPDATE.value:
                if len(sys.argv) < 7:
                    print("Usage: create progress_update <sender> <recipient> <task_id> <progress> <status>")
                    sys.exit(1)
                    
                sender = sys.argv[3]
                recipient = sys.argv[4]
                task_id = sys.argv[5]
                progress = float(sys.argv[6])
                status = sys.argv[7]
                
                msg = GatewayMessage.create_progress_update(
                    sender=sender,
                    recipient=recipient,
                    task_id=task_id,
                    progress=progress,
                    status=status
                )
                
            elif msg_type == MessageType.BLOCKER_ALERT.value:
                if len(sys.argv) < 7:
                    print("Usage: create blocker_alert <sender> <recipient> <task_id> <blocker> <severity>")
                    sys.exit(1)
                    
                sender = sys.argv[3]
                recipient = sys.argv[4]
                task_id = sys.argv[5]
                blocker = sys.argv[6]
                severity = sys.argv[7]
                
                msg = GatewayMessage.create_blocker_alert(
                    sender=sender,
                    recipient=recipient,
                    task_id=task_id,
                    blocker=blocker,
                    severity=severity
                )
                
            elif msg_type == MessageType.DELIVERY.value:
                if len(sys.argv) < 7:
                    print("Usage: create delivery <sender> <recipient> <delivery_id> <items_json> <status>")
                    sys.exit(1)
                    
                sender = sys.argv[3]
                recipient = sys.argv[4]
                delivery_id = sys.argv[5]
                items_json = sys.argv[6]
                status = sys.argv[7]
                
                try:
                    items = json.loads(items_json)
                except json.JSONDecodeError:
                    print("Error: Invalid items JSON")
                    sys.exit(1)
                    
                msg = GatewayMessage.create_delivery(
                    sender=sender,
                    recipient=recipient,
                    delivery_id=delivery_id,
                    items=items,
                    status=status
                )
                
            elif msg_type == MessageType.USER_INPUT.value:
                if len(sys.argv) < 7:
                    print("Usage: create user_input <sender> <recipient> <input_id> <prompt> <response>")
                    sys.exit(1)
                    
                sender = sys.argv[3]
                recipient = sys.argv[4]
                input_id = sys.argv[5]
                prompt = sys.argv[6]
                response = sys.argv[7]
                
                msg = GatewayMessage.create_user_input(
                    sender=sender,
                    recipient=recipient,
                    input_id=input_id,
                    prompt=prompt,
                    response=response
                )
                
            elif msg_type == MessageType.KILLSWITCH.value:
                if len(sys.argv) < 5:
                    print("Usage: create killswitch <sender> <recipient> <reason>")
                    sys.exit(1)
                    
                sender = sys.argv[3]
                recipient = sys.argv[4]
                reason = sys.argv[5]
                
                msg = GatewayMessage.create_killswitch(
                    sender=sender,
                    recipient=recipient,
                    reason=reason
                )
                
            else:
                print(f"Unknown message type: {msg_type}")
                sys.exit(1)
                
            print("Message created successfully:")
            print(json.dumps(msg.to_dict(), indent=2))
            
        except Exception as e:
            print(f"Error creating message: {e}")
            sys.exit(1)
            
    elif command == 'validate':
        if len(sys.argv) < 3:
            print("Usage: validate <json>")
            sys.exit(1)
            
        json_str = sys.argv[2]
        
        try:
            msg = GatewayMessage.from_json(json_str)
            if msg.validate():
                print("Message is valid")
            else:
                print("Message is invalid")
                sys.exit(1)
            
        except Exception as e:
            print(f"Validation error: {e}")
            sys.exit(1)
            
    elif command == 'convert':
        if len(sys.argv) < 3:
            print("Usage: convert <json>")
            sys.exit(1)
            
        json_str = sys.argv[2]
        
        try:
            msg = GatewayMessage.from_json(json_str)
            print("Converted message:")
            print(json.dumps(msg.to_dict(), indent=2))
            
        except Exception as e:
            print(f"Conversion error: {e}")
            sys.exit(1)
            
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == '__main__':
    asyncio.run(main())
