# Jito Solana Validator Testnet Setup Guide (Cloud Deployment)

## Overview
This guide explains how to deploy a **Jito-Solana validator** on the **Solana testnet**, including setup steps for **AWS/GCP cloud servers**, **testnet SOL funding**, and **integration with Jito block engine and relayer**. It combines official Jito and Solana documentation into one complete, practical walkthrough.

---

## 1. Provision a Cloud Server

**Recommended specs (for testnet):**
- CPU: 12+ cores (x86_64, AVX2 support)
- RAM: 64–128 GB
- Storage: 1–2 TB NVMe SSD
- OS: Ubuntu 22.04+
- Network: 1+ Gbps

Example instance types:
- AWS: `m7i.4xlarge`, `r7i.4xlarge`
- GCP: `n2-standard-16` or `n2d-standard-16`

```bash
sudo apt update && sudo apt upgrade -y
sudo adduser sol
```

---

## 2. Install Solana CLI (Agave Build)

```bash
sh -c "$(curl -sSfL https://release.anza.xyz/stable/install)"
solana config set --url https://api.testnet.solana.com
solana --version
```

---

## 3. Generate Keys Locally

```bash
solana-keygen new -o validator-keypair.json
solana-keygen new -o vote-account-keypair.json
solana-keygen new -o authorized-withdrawer-keypair.json
solana config set --keypair ./validator-keypair.json
```

Keep the **authorized withdrawer** key **offline**.

---

## 4. Fund Your Validator with Testnet SOL

```bash
solana airdrop 1
solana balance
```

If rate-limited, use web faucets such as:
- [Solana Faucet](https://faucet.solana.com) → select “testnet”
- [QuickNode Faucet](https://faucet.quicknode.com/solana/testnet)

---

## 5. Create the Vote Account

```bash
solana create-vote-account -ut   --fee-payer ./validator-keypair.json   ./vote-account-keypair.json   ./validator-keypair.json   ./authorized-withdrawer-keypair.json
```

---

## 6. Build Jito-Solana on the VM

```bash
sudo apt install -y libssl-dev libudev-dev pkg-config zlib1g-dev llvm clang cmake make libprotobuf-dev protobuf-compiler
curl https://sh.rustup.rs -sSf | sh
source $HOME/.cargo/env
rustup update

git clone https://github.com/jito-foundation/jito-solana.git --recurse-submodules
cd jito-solana
export TAG=v1.16.17-jito
git checkout tags/$TAG
CI_COMMIT=$(git rev-parse HEAD) scripts/cargo-install-all.sh --validator-only ~/.local/share/solana/install/releases/"$TAG"
```

---

## 7. Configure and Launch Jito Validator

Create `/home/sol/bin/validator.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

LEDGER=/mnt/ledger
ACCOUNTS=/mnt/accounts
LOG=/home/sol/jito-validator.log
BIN="$HOME/.local/share/solana/install/releases/$TAG/bin"

BLOCK_ENGINE_URL="https://ny.testnet.block-engine.jito.wtf"
RELAYER_URL="nyc.testnet.relayer.jito.wtf:8100"
SHRED_RECEIVER_ADDR="141.98.216.97:1002"

TIP_PAYMENT=GJHtFqM9agxPmkeKjHny6qiRKrXZALvvFGiKf11QE7hy
TIP_DISTRIB=F2Zu7QZiTYUhPd7u9ukRVwxh7B71oA3NMJcHuCHc29P2
MERKLE_AUTH=GZctHpWXmsZC1YHACTGGcHhYxjdRqQvTpYkb9LMvxDib

exec "$BIN/solana-validator"   --identity /home/sol/validator-keypair.json   --vote-account /home/sol/vote-account-keypair.json   --ledger "$LEDGER"   --accounts "$ACCOUNTS"   --log "$LOG"   --rpc-port 8899   --dynamic-port-range 8000-8020   --entrypoint entrypoint.testnet.solana.com:8001   --expected-genesis-hash 4uhcVJyU9pJkvQyS88uRDiswHXSCkY3zQawwpjk2NsNY   --tip-payment-program-pubkey "$TIP_PAYMENT"   --tip-distribution-program-pubkey "$TIP_DISTRIB"   --merkle-root-upload-authority "$MERKLE_AUTH"   --block-engine-url "$BLOCK_ENGINE_URL"   --relayer-url "$RELAYER_URL"   --shred-receiver-address "$SHRED_RECEIVER_ADDR"
```

Run the validator:
```bash
chmod +x ~/bin/validator.sh
nohup ~/bin/validator.sh &
tail -f ~/jito-validator.log
```

---

## 8. Verify the Validator

```bash
PUBKEY=$(solana-keygen pubkey ./validator-keypair.json)
solana gossip | grep "$PUBKEY"
solana validators | grep "$PUBKEY"
solana catchup "$PUBKEY"
```

---

## 9. Update Jito Endpoints (Optional)

You can modify endpoints on the fly via admin RPC:

```bash
solana-validator -l /mnt/ledger set-block-engine-config   --block-engine-url https://ny.testnet.block-engine.jito.wtf
```

---

## 10. Notes & Best Practices

- Keep **withdrawer keys offline**
- Monitor logs for errors and gossip connection
- Use `systemd` or `supervisord` to restart automatically
- Use `solana catchup` regularly to verify sync progress

---

## References

- [Jito Docs](https://docs.jito.wtf/)
- [Jito-Solana GitHub](https://github.com/jito-foundation/jito-solana)
- [Solana Testnet Docs](https://docs.solana.com/clusters#testnet)
- [Helius Blog - Solana Validator Setup](https://www.helius.dev/blog/how-to-set-up-a-solana-validator)
