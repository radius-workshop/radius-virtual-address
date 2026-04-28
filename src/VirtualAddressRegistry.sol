// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract VirtualAddressRegistry {
    using SafeERC20 for IERC20;

    struct MasterWallet {
        address owner;
        address receiver;
        bool active;
    }

    mapping(bytes32 => MasterWallet) private _wallets;
    mapping(address => bytes32) private _virtualToMaster;

    event MasterRegistered(bytes32 indexed walletId, address indexed owner, address indexed receiver);
    event MasterUpdated(bytes32 indexed walletId, address indexed newReceiver);
    event MasterDeactivated(bytes32 indexed walletId);
    event VirtualResolved(address indexed virtualAddr, bytes32 indexed walletId, address indexed receiver);
    event Deposited(
        address indexed virtualAddr, bytes32 indexed walletId, address indexed token, uint256 amount, bytes32 ref_
    );
    event Swept(address indexed virtualAddr, address indexed token, address indexed receiver, uint256 amount);

    error WalletAlreadyExists();
    error WalletNotFound();
    error WalletInactive();
    error NotWalletOwner();
    error VirtualAlreadyMapped();
    error VirtualNotMapped();
    error ZeroAddress();
    error ZeroWalletId();

    function registerMaster(bytes32 walletId, address receiver) external {
        if (walletId == bytes32(0)) revert ZeroWalletId();
        if (receiver == address(0)) revert ZeroAddress();
        if (_wallets[walletId].owner != address(0)) revert WalletAlreadyExists();
        _wallets[walletId] = MasterWallet({owner: msg.sender, receiver: receiver, active: true});
        emit MasterRegistered(walletId, msg.sender, receiver);
    }

    function updateReceiver(bytes32 walletId, address newReceiver) external {
        MasterWallet storage w = _requireOwner(walletId);
        if (newReceiver == address(0)) revert ZeroAddress();
        w.receiver = newReceiver;
        emit MasterUpdated(walletId, newReceiver);
    }

    function deactivate(bytes32 walletId) external {
        MasterWallet storage w = _requireOwner(walletId);
        w.active = false;
        emit MasterDeactivated(walletId);
    }

    function computeVirtualAddress(bytes32 walletId, bytes32 salt) public pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(walletId, salt)))));
    }

    function mapVirtual(bytes32 walletId, bytes32 salt) external {
        MasterWallet storage w = _wallets[walletId];
        if (w.owner == address(0)) revert WalletNotFound();
        if (!w.active) revert WalletInactive();

        address virtual_ = computeVirtualAddress(walletId, salt);
        if (_virtualToMaster[virtual_] != bytes32(0)) revert VirtualAlreadyMapped();

        _virtualToMaster[virtual_] = walletId;
        emit VirtualResolved(virtual_, walletId, w.receiver);
    }

    function mapVirtualBatch(bytes32 walletId, bytes32[] calldata salts) external {
        MasterWallet storage w = _wallets[walletId];
        if (w.owner == address(0)) revert WalletNotFound();
        if (!w.active) revert WalletInactive();

        for (uint256 i = 0; i < salts.length; i++) {
            address virtual_ = computeVirtualAddress(walletId, salts[i]);
            if (_virtualToMaster[virtual_] != bytes32(0)) revert VirtualAlreadyMapped();
            _virtualToMaster[virtual_] = walletId;
            emit VirtualResolved(virtual_, walletId, w.receiver);
        }
    }

    function deposit(address virtualAddr, address token, uint256 amount, bytes32 ref_)
        external
    {
        bytes32 walletId = _virtualToMaster[virtualAddr];
        if (walletId == bytes32(0)) revert VirtualNotMapped();

        MasterWallet storage w = _wallets[walletId];
        if (!w.active) revert WalletInactive();

        IERC20(token).safeTransferFrom(msg.sender, w.receiver, amount);
        emit Deposited(virtualAddr, walletId, token, amount, ref_);
    }

    function resolve(address virtualAddr) external view returns (bytes32 walletId, address receiver) {
        walletId = _virtualToMaster[virtualAddr];
        if (walletId == bytes32(0)) revert VirtualNotMapped();
        receiver = _wallets[walletId].receiver;
    }

    function getMaster(bytes32 walletId) external view returns (MasterWallet memory) {
        if (_wallets[walletId].owner == address(0)) revert WalletNotFound();
        return _wallets[walletId];
    }

    function _requireOwner(bytes32 walletId) internal view returns (MasterWallet storage w) {
        w = _wallets[walletId];
        if (w.owner == address(0)) revert WalletNotFound();
        if (w.owner != msg.sender) revert NotWalletOwner();
    }
}
