# Protocol Contract Deployment & Upgrade
# Usage:
#   make deploy CHAIN=Bsc
#   make upgrade CHAIN=Bsc CONTRACT=Gateway
#   make deploy CHAIN=Mapo VERIFY=false
#   make gen-verify CONTRACT=Gateway

-include .env

CHAIN     ?= Bsc
CONTRACT  ?= Gateway
VERIFY    ?= true
SCRIPT    := scripts/foundry/DeployAndSetUp.s.sol:DeployAndSetUp

# Blockscout chains (Mapo)
BLOCKSCOUT_CHAINS := Mapo Makalu

# Build verify flag
ifeq ($(VERIFY),true)
  ifneq ($(filter $(CHAIN),$(BLOCKSCOUT_CHAINS)),)
    VERIFY_FLAG := --verify --verifier blockscout
  else
    VERIFY_FLAG := --verify
  endif
else
  VERIFY_FLAG :=
endif

.PHONY: deploy upgrade deploy-dry upgrade-dry gen-verify build test

# Deploy all contracts (auto-detects relay vs gateway by chain)
deploy:
	forge script $(SCRIPT) \
		--rpc-url $(CHAIN) --broadcast $(VERIFY_FLAG)

# Upgrade a specific contract
upgrade:
	forge script $(SCRIPT) \
		--sig "upgradeContract(string)" "$(CONTRACT)" \
		--rpc-url $(CHAIN) --broadcast $(VERIFY_FLAG)

# Dry-run deploy (simulate without broadcasting)
deploy-dry:
	forge script $(SCRIPT) \
		--rpc-url $(CHAIN)

# Dry-run upgrade
upgrade-dry:
	forge script $(SCRIPT) \
		--sig "upgradeContract(string)" "$(CONTRACT)" \
		--rpc-url $(CHAIN)

# Generate verification files (standard json input + flatten)
gen-verify:
	zsh scripts/gen-verify.sh $(CONTRACT)

gen-verify-all:
	zsh scripts/gen-verify.sh all

build:
	forge build

test:
	forge test