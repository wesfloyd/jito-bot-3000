# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

This repository aims to maximally automate the deployment of Jito-Solana validators on testnet using AI-driven automation. The goal is to minimize manual user interactions by creating scripts that handle provisioning, configuration, and deployment of Jito validators.

## Key Documentation

- `jito-solana-validator-testnet-chatgpt.md`: Complete step-by-step manual guide for deploying a Jito validator on testnet, including cloud provisioning, key generation, Jito-Solana compilation, and validator configuration
- Official references:
  - https://docs.jito.wtf/
  - https://github.com/jito-foundation/jito-solana

## Architecture & Deployment Context

### Jito-Solana Validator Stack
The validator deployment involves several components that must be orchestrated:

1. **Infrastructure Layer**: Cloud VM (AWS/GCP) with specific hardware requirements (12+ cores, 64-128GB RAM, 1-2TB NVMe SSD)
2. **Base Layer**: Solana CLI (Agave build) configured for testnet
3. **Key Management**: Multiple keypairs (validator identity, vote account, authorized withdrawer)
4. **Jito-Solana Binary**: Custom-built validator from jito-foundation/jito-solana repository
5. **Jito Integration**: Block engine, relayer, and shred receiver endpoints for MEV integration

### Critical Configuration Parameters
When automating validator setup, these Jito-specific parameters must be configured:
- Block Engine URL: `https://ny.testnet.block-engine.jito.wtf`
- Relayer URL: `nyc.testnet.relayer.jito.wtf:8100`
- Shred Receiver: `141.98.216.97:1002`
- Tip Payment Program: `GJHtFqM9agxPmkeKjHny6qiRKrXZALvvFGiKf11QE7hy`
- Tip Distribution Program: `F2Zu7QZiTYUhPd7u9ukRVwxh7B71oA3NMJcHuCHc29P2`
- Merkle Root Authority: `GZctHpWXmsZC1YHACTGGcHhYxjdRqQvTpYkb9LMvxDib`

### Security Considerations
- Authorized withdrawer keys must remain offline and never be deployed to the validator VM
- All keypairs should be generated locally before cloud deployment
- Validator and vote account keys need to be securely transferred to the VM

## Automation Requirements

Future automation scripts should handle:
1. Cloud infrastructure provisioning (with appropriate specs)
2. System dependency installation
3. Solana CLI installation and configuration
4. Keypair generation and management workflow
5. Testnet SOL funding (via faucet APIs)
6. Vote account creation
7. Jito-Solana source compilation (specific version tags)
8. Validator launch script generation with all Jito parameters
9. Validator health monitoring and verification

The automation should minimize user prompts while maintaining security best practices (especially around key management).
- always stop to prompt me to run any manual steps required before proceeding. I'm happy to run bash shell commands as needed