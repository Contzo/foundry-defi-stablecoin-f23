-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil 

-include .env

.PHONY: all test deploy

build :; forge build 

test :; forge  test

install :; forge install openzeppelin/openzeppelin-contracts --no-commit && forge install foundry-rs/forge-std --no-commit 

# deploy-anvil :; forge script script/DeployOurToken.s.sol:DeployOutToken --rpc-url $(ANVIL_RPC_URL) --account LocalAnvilWallet --broadcast