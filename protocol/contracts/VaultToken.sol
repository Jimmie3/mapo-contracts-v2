// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {BaseImplementation} from "@mapprotocol/common-contracts/contracts/base/BaseImplementation.sol";

contract VaultToken is ERC4626Upgradeable, BaseImplementation {

    address public vaultManager;
    uint256 public balance;

    error only_manager_role();

    event FeeCollected(uint256 indexed feeType, uint256 feeAmount, uint256 totalValue);

    function initialize(address _defaultAdmin, address _token, string memory name_, string memory symbol_) public initializer {
        __BaseImplementation_init(_defaultAdmin);
        __ERC4626_init(IERC20(_token));
        __ERC20_init(name_, symbol_);
    }

    function setVaultManager(address _manager) external restricted {
        vaultManager = _manager;
    }


    function collectFee(uint256 assets) external {
        balance += assets;
        // todo: emit
        emit FeeCollected(0, assets, balance);
    }

    function totalAssets() public view override returns (uint256) {
        return balance;
    }


    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        if (caller != vaultManager) {
            revert only_manager_role();
        }
        // SafeERC20.safeTransferFrom(IERC20(asset()), caller, address(this), assets);

        balance += assets;
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @dev Withdraw/redeem common workflow.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        if (caller != vaultManager) {
            revert only_manager_role();
        }

        //if (caller != owner) {
        //    _spendAllowance(owner, caller, shares);
        //}
        _burn(owner, shares);
        // SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);

        balance -= assets;

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

}
