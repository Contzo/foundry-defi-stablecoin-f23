-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil 

-include .env

.PHONY: all test deploy

build :; forge build 

test :; forge  test

NO_COMMIT_FLAG := $(shell \
  if forge install --help 2>&1 | grep -- '--no-commit' > /dev/null ; then \
    echo "--no-commit"; \
  else \
    echo ""; \
  fi)

install:
	forge install openzeppelin/openzeppelin-contracts@v4.8.3 $(NO_COMMIT_FLAG)
	forge install foundry-rs/forge-std $(NO_COMMIT_FLAG)
	forge install smartcontractkit/chainlink-brownie-contracts $(NO_COMMIT_FLAG)

# deploy-anvil :; forge script script/DeployOurToken.s.sol:DeployOutToken --rpc-url $(ANVIL_RPC_URL) --account LocalAnvilWallet --broadcast