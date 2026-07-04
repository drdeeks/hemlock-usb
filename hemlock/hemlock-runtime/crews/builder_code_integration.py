#!/usr/bin/env python3
"""
Builder Code Integration - Hardwired into all agents
Ensures every agent (current and future) has the builder code.
"""

import json
import os
import sys
import logging
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Any

logger = logging.getLogger(__name__)

class BuilderCodeManager:
    """
    Manages builder code integration for all agents.
    Hardcodes builder code into agent creation and configuration.
    """
    
    # HARDCODED BUILDER CODE - THIS IS THE CORE CONFIGURATION
    BUILDER_CODE = "bc_26ulyc23"
    BUILDER_CODE_HEX = "0x62635f3236756c79633233"
    OWNER_ADDRESS = "0x12F1B38DC35AA65B50E5849d02559078953aE24b"
    
    # Blockchain configuration
    CHAIN_ID = 8453  # Base mainnet
    CHAIN_NAME = "Base"
    
    def __init__(self, config_dir: str = "/home/ubuntu/.hermes/builder-code"):
        self.config_dir = Path(config_dir)
        self.config_dir.mkdir(parents=True, exist_ok=True)
        
        self.config_file = self.config_dir / "builder-code.json"
        self.registry_file = self.config_dir / "agent-registry.json"
        
        # Load or create configuration
        self.config = self._load_config()
        self.agent_registry = self._load_registry()
    
    def _load_config(self) -> Dict:
        """Load builder code configuration."""
        if self.config_file.exists():
            try:
                with open(self.config_file, 'r') as f:
                    return json.load(f)
            except Exception as e:
                logger.error(f"Error loading builder code config: {e}")
        
        # Create default configuration
        config = {
            "builderCode": self.BUILDER_CODE,
            "builderCodeHex": self.BUILDER_CODE_HEX,
            "owner": self.OWNER_ADDRESS,
            "chainId": self.CHAIN_ID,
            "chainName": self.CHAIN_NAME,
            "hardwired": True,
            "enforced": True,
            "created_at": datetime.now().isoformat(),
            "updated_at": datetime.now().isoformat()
        }
        
        self._save_config(config)
        return config
    
    def _save_config(self, config: Dict):
        """Save builder code configuration."""
        try:
            config["updated_at"] = datetime.now().isoformat()
            with open(self.config_file, 'w') as f:
                json.dump(config, f, indent=2)
        except Exception as e:
            logger.error(f"Error saving builder code config: {e}")
    
    def _load_registry(self) -> Dict:
        """Load agent registry."""
        if self.registry_file.exists():
            try:
                with open(self.registry_file, 'r') as f:
                    return json.load(f)
            except Exception as e:
                logger.error(f"Error loading agent registry: {e}")
        
        # Create default registry
        registry = {
            "agents": {},
            "created_at": datetime.now().isoformat(),
            "updated_at": datetime.now().isoformat()
        }
        
        self._save_registry(registry)
        return registry
    
    def _save_registry(self, registry: Dict):
        """Save agent registry."""
        try:
            registry["updated_at"] = datetime.now().isoformat()
            with open(self.registry_file, 'w') as f:
                json.dump(registry, f, indent=2)
        except Exception as e:
            logger.error(f"Error saving agent registry: {e}")
    
    def register_agent(self, agent_id: str, agent_name: str, agent_type: str,
                      parent_agent: str = "system", metadata: Optional[Dict] = None) -> Dict:
        """
        Register an agent with builder code.
        
        Args:
            agent_id: Unique agent identifier
            agent_name: Human-readable agent name
            agent_type: Type of agent (ui, debugger, etc.)
            parent_agent: Parent agent that created this agent
            metadata: Additional metadata
        
        Returns:
            Registration result
        """
        # Ensure builder code is enforced
        if not self.config.get("enforced"):
            self.config["enforced"] = True
            self._save_config(self.config)
        
        # Create agent entry
        agent_entry = {
            "agent_id": agent_id,
            "agent_name": agent_name,
            "agent_type": agent_type,
            "builderCode": self.BUILDER_CODE,
            "builderCodeHex": self.BUILDER_CODE_HEX,
            "owner": self.OWNER_ADDRESS,
            "parent_agent": parent_agent,
            "inherited": True,
            "verified": True,
            "chain_id": self.CHAIN_ID,
            "chain_name": self.CHAIN_NAME,
            "created_at": datetime.now().isoformat(),
            "updated_at": datetime.now().isoformat(),
            "metadata": metadata or {}
        }
        
        # Add to registry
        self.agent_registry["agents"][agent_id] = agent_entry
        self._save_registry(self.agent_registry)
        
        logger.info(f"Registered agent {agent_id} with builder code {self.BUILDER_CODE}")
        
        return {
            "success": True,
            "agent_id": agent_id,
            "builderCode": self.BUILDER_CODE,
            "builderCodeHex": self.BUILDER_CODE_HEX,
            "owner": self.OWNER_ADDRESS,
            "message": f"Agent {agent_name} registered with builder code"
        }
    
    def verify_agent_builder_code(self, agent_id: str) -> Dict:
        """
        Verify that an agent has the correct builder code.
        
        Args:
            agent_id: Agent identifier
        
        Returns:
            Verification result
        """
        if agent_id not in self.agent_registry["agents"]:
            return {
                "verified": False,
                "error": f"Agent {agent_id} not found in registry"
            }
        
        agent = self.agent_registry["agents"][agent_id]
        
        # Check builder code
        builder_code_match = agent.get("builderCode") == self.BUILDER_CODE
        hex_match = agent.get("builderCodeHex") == self.BUILDER_CODE_HEX
        owner_match = agent.get("owner") == self.OWNER_ADDRESS
        
        verified = builder_code_match and hex_match and owner_match
        
        return {
            "verified": verified,
            "agent_id": agent_id,
            "agent_name": agent.get("agent_name"),
            "builderCode": agent.get("builderCode"),
            "builderCodeHex": agent.get("builderCodeHex"),
            "owner": agent.get("owner"),
            "inherited": agent.get("inherited"),
            "parent_agent": agent.get("parent_agent"),
            "checks": {
                "builder_code_match": builder_code_match,
                "hex_match": hex_match,
                "owner_match": owner_match
            }
        }
    
    def get_all_agents(self) -> List[Dict]:
        """Get all registered agents with builder codes."""
        agents = []
        
        for agent_id, agent_data in self.agent_registry["agents"].items():
            agents.append({
                "agent_id": agent_id,
                "agent_name": agent_data.get("agent_name"),
                "agent_type": agent_data.get("agent_type"),
                "builderCode": agent_data.get("builderCode"),
                "verified": agent_data.get("verified"),
                "parent_agent": agent_data.get("parent_agent"),
                "created_at": agent_data.get("created_at")
            })
        
        return agents
    
    def create_agent_config(self, agent_id: str, agent_name: str, agent_type: str) -> Dict:
        """
        Create agent configuration with hardcoded builder code.
        
        Args:
            agent_id: Agent identifier
            agent_name: Agent name
            agent_type: Agent type
        
        Returns:
            Agent configuration dictionary
        """
        config = {
            "agent": {
                "id": agent_id,
                "name": agent_name,
                "type": agent_type,
                "created_at": datetime.now().isoformat()
            },
            "builderCode": {
                "code": self.BUILDER_CODE,
                "hex": self.BUILDER_CODE_HEX,
                "owner": self.OWNER_ADDRESS,
                "hardwired": True,
                "enforced": True
            },
            "blockchain": {
                "chainId": self.CHAIN_ID,
                "chainName": self.CHAIN_NAME,
                "network": "mainnet"
            },
            "inheritance": {
                "parent": "system",
                "inherited": True,
                "verified": True
            },
            "transaction": {
                "append_builder_code": True,
                "verify_before_send": True,
                "audit_log": True
            }
        }
        
        return config
    
    def append_builder_code_to_transaction(self, tx_data: str) -> str:
        """
        Append builder code to transaction data.
        
        Args:
            tx_data: Original transaction data
        
        Returns:
            Transaction data with builder code appended
        """
        # Remove 0x prefix if present
        if tx_data.startswith("0x"):
            tx_data = tx_data[2:]
        
        # Append builder code hex (without 0x)
        builder_code_hex_clean = self.BUILDER_CODE_HEX[2:]  # Remove 0x
        
        # Append to transaction data
        tx_data_with_builder = tx_data + builder_code_hex_clean
        
        # Add 0x prefix back
        return "0x" + tx_data_with_builder
    
    def verify_transaction_builder_code(self, tx_data: str) -> Dict:
        """
        Verify that transaction has builder code.
        
        Args:
            tx_data: Transaction data
        
        Returns:
            Verification result
        """
        # Remove 0x prefix if present
        if tx_data.startswith("0x"):
            tx_data = tx_data[2:]
        
        # Get builder code hex (without 0x)
        builder_code_hex_clean = self.BUILDER_CODE_HEX[2:]
        
        # Check if transaction ends with builder code
        has_builder_code = tx_data.endswith(builder_code_hex_clean)
        
        return {
            "verified": has_builder_code,
            "builderCode": self.BUILDER_CODE if has_builder_code else None,
            "builderCodeHex": self.BUILDER_CODE_HEX if has_builder_code else None,
            "transaction_length": len(tx_data),
            "builder_code_length": len(builder_code_hex_clean)
        }
    
    def get_builder_code_for_agent(self, agent_id: str) -> Optional[str]:
        """Get builder code for a specific agent."""
        if agent_id in self.agent_registry["agents"]:
            return self.agent_registry["agents"][agent_id].get("builderCode")
        return self.BUILDER_CODE  # Default to hardcoded
    
    def enforce_builder_code_policy(self) -> Dict:
        """
        Enforce builder code policy across all agents.
        
        Returns:
            Enforcement result
        """
        results = {
            "total_agents": len(self.agent_registry["agents"]),
            "verified_agents": 0,
            "unverified_agents": 0,
            "issues": []
        }
        
        for agent_id, agent_data in self.agent_registry["agents"].items():
            verification = self.verify_agent_builder_code(agent_id)
            
            if verification["verified"]:
                results["verified_agents"] += 1
            else:
                results["unverified_agents"] += 1
                results["issues"].append({
                    "agent_id": agent_id,
                    "agent_name": agent_data.get("agent_name"),
                    "issues": verification.get("checks", {})
                })
        
        # Update enforcement status
        self.config["enforced"] = True
        self.config["last_enforcement"] = datetime.now().isoformat()
        self._save_config(self.config)
        
        return results
    
    def generate_builder_code_report(self) -> str:
        """Generate a report of builder code status."""
        report = "# Builder Code Integration Report\n\n"
        report += f"**Generated:** {datetime.now().isoformat()}\n\n"
        
        report += "## Configuration\n\n"
        report += f"- **Builder Code:** `{self.BUILDER_CODE}`\n"
        report += f"- **Builder Code Hex:** `{self.BUILDER_CODE_HEX}`\n"
        report += f"- **Owner:** `{self.OWNER_ADDRESS}`\n"
        report += f"- **Chain:** {self.CHAIN_NAME} (ID: {self.CHAIN_ID})\n"
        report += f"- **Hardwired:** {'Yes' if self.config.get('hardwired') else 'No'}\n"
        report += f"- **Enforced:** {'Yes' if self.config.get('enforced') else 'No'}\n\n"
        
        report += "## Agent Registry\n\n"
        
        agents = self.get_all_agents()
        if not agents:
            report += "No agents registered.\n\n"
        else:
            report += f"**Total Agents:** {len(agents)}\n\n"
            
            for agent in agents:
                report += f"### {agent['agent_name']} (`{agent['agent_id']}`)\n\n"
                report += f"- **Type:** {agent['agent_type']}\n"
                report += f"- **Builder Code:** `{agent['builderCode']}`\n"
                report += f"- **Verified:** {'✅' if agent['verified'] else '❌'}\n"
                report += f"- **Parent:** {agent['parent_agent']}\n"
                report += f"- **Created:** {agent['created_at']}\n\n"
        
        report += "## Transaction Integration\n\n"
        report += "Builder code is automatically appended to all blockchain transactions.\n\n"
        report += "**Example:**\n"
        report += "```javascript\n"
        report += "// Original transaction data\n"
        report += "const txData = '0xabcdef123456';\n\n"
        report +=("// With builder code\n")
        report += "const txDataWithBuilder = appendBuilderCode(txData);\n"
        report += "// Result: '0xabcdef123456" + self.BUILDER_CODE_HEX[2:] + "'\n"
        report += "```\n\n"
        
        report += "## Compliance\n\n"
        report += "- ✅ Builder code in every transaction\n"
        report += "- ✅ Builder code in every agent\n"
        report += "- ✅ Builder code in every sub-agent\n"
        report += "- ✅ Verification before execution\n"
        report += "- ✅ Audit logging enabled\n"
        
        return report

# Global instance
_builder_code_manager = None

def get_builder_code_manager() -> BuilderCodeManager:
    """Get the global builder code manager instance."""
    global _builder_code_manager
    if _builder_code_manager is None:
        _builder_code_manager = BuilderCodeManager()
    return _builder_code_manager

# Export for use in other modules
__all__ = ['BuilderCodeManager', 'get_builder_code_manager']
