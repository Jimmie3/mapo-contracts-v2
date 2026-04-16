# Common Contracts — AuthorityManager Deployment
# Usage:
#   make deploy-authority CHAIN=Bsc
#   make deploy-authority-factory CHAIN=Bsc SALT=mapo_authority
#   make deploy-authority CHAIN=Mapo VERIFY=false

-include .env

CHAIN     ?= Bsc
VERIFY    ?= true
SALT      ?= mapo_authority
SCRIPT    := script/DeployAuthority.s.sol:DeployAuthority

# Blockscout chains
BLOCKSCOUT_CHAINS := Mapo Makalu

ifeq ($(VERIFY),true)
  ifneq ($(filter $(CHAIN),$(BLOCKSCOUT_CHAINS)),)
    VERIFY_FLAG := --verify --verifier blockscout
  else
    VERIFY_FLAG := --verify
  endif
else
  VERIFY_FLAG :=
endif

.PHONY: deploy-authority deploy-authority-factory deploy-authority-dry build test

# Direct deploy
deploy-authority:
	forge script $(SCRIPT) \
		--rpc-url $(CHAIN) --broadcast $(VERIFY_FLAG)

# Factory deploy (deterministic address)
deploy-authority-factory:
	AUTHORITY_SALT=$(SALT) forge script $(SCRIPT) \
		--sig "deployWithFactory()" \
		--rpc-url $(CHAIN) --broadcast $(VERIFY_FLAG)

# Dry-run
deploy-authority-dry:
	forge script $(SCRIPT) \
		--rpc-url $(CHAIN)

build:
	forge build

test:
	forge test
