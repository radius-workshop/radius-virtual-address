// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {VirtualAddressRegistry} from "../src/VirtualAddressRegistry.sol";
import {MockUSDC} from "../src/MockUSDC.sol";

contract VirtualAddressTest is Test {
    VirtualAddressRegistry public registry;
    MockUSDC public usdc;
    address merchant = makeAddr("merchant");
    address receiver = makeAddr("receiver");
    address depositor = makeAddr("depositor");
    bytes32 walletId = bytes32(uint256(1));
    bytes32 salt1 = bytes32(uint256(100));
    bytes32 salt2 = bytes32(uint256(200));

    function setUp() public {
        registry = new VirtualAddressRegistry();
        usdc = new MockUSDC();
        usdc.mint(depositor, 10_000e6);
        vm.prank(depositor);
        usdc.approve(address(registry), type(uint256).max);
    }

    function test_registerMaster() public {
        vm.prank(merchant);
        registry.registerMaster(walletId, receiver);
        VirtualAddressRegistry.MasterWallet memory w = registry.getMaster(walletId);
        assertEq(w.owner, merchant);
        assertEq(w.receiver, receiver);
        assertTrue(w.active);
    }

    function test_mapAndResolve() public {
        vm.prank(merchant);
        registry.registerMaster(walletId, receiver);
        registry.mapVirtual(walletId, salt1);

        address virtual_ = registry.computeVirtualAddress(walletId, salt1);
        (bytes32 resolved, address dest) = registry.resolve(virtual_);
        assertEq(resolved, walletId);
        assertEq(dest, receiver);
    }

    function test_deposit_routes_to_receiver() public {
        vm.prank(merchant);
        registry.registerMaster(walletId, receiver);
        registry.mapVirtual(walletId, salt1);

        address virtual_ = registry.computeVirtualAddress(walletId, salt1);
        vm.prank(depositor);
        registry.deposit(virtual_, address(usdc), 500e6, bytes32("INV-001"));

        assertEq(usdc.balanceOf(receiver), 500e6);
    }

    function test_batchMap() public {
        vm.prank(merchant);
        registry.registerMaster(walletId, receiver);

        bytes32[] memory salts = new bytes32[](2);
        salts[0] = salt1;
        salts[1] = salt2;
        registry.mapVirtualBatch(walletId, salts);

        address v1 = registry.computeVirtualAddress(walletId, salt1);
        address v2 = registry.computeVirtualAddress(walletId, salt2);
        assertNotEq(v1, v2);

        (bytes32 r1,) = registry.resolve(v1);
        (bytes32 r2,) = registry.resolve(v2);
        assertEq(r1, walletId);
        assertEq(r2, walletId);
    }

    function test_updateReceiver() public {
        address newReceiver = makeAddr("newReceiver");
        vm.prank(merchant);
        registry.registerMaster(walletId, receiver);
        registry.mapVirtual(walletId, salt1);

        vm.prank(merchant);
        registry.updateReceiver(walletId, newReceiver);

        address virtual_ = registry.computeVirtualAddress(walletId, salt1);
        vm.prank(depositor);
        registry.deposit(virtual_, address(usdc), 100e6, bytes32(0));
        assertEq(usdc.balanceOf(newReceiver), 100e6);
    }

    function test_deactivate_blocks_deposits() public {
        vm.prank(merchant);
        registry.registerMaster(walletId, receiver);
        registry.mapVirtual(walletId, salt1);

        vm.prank(merchant);
        registry.deactivate(walletId);

        address virtual_ = registry.computeVirtualAddress(walletId, salt1);
        vm.prank(depositor);
        vm.expectRevert(VirtualAddressRegistry.WalletInactive.selector);
        registry.deposit(virtual_, address(usdc), 100e6, bytes32(0));
    }

    function test_reverts_unmapped() public {
        vm.expectRevert(VirtualAddressRegistry.VirtualNotMapped.selector);
        registry.resolve(makeAddr("random"));
    }

    function test_reverts_zero_walletId() public {
        vm.prank(merchant);
        vm.expectRevert(VirtualAddressRegistry.ZeroWalletId.selector);
        registry.registerMaster(bytes32(0), receiver);
    }

    function test_reverts_duplicate_register() public {
        vm.prank(merchant);
        registry.registerMaster(walletId, receiver);
        vm.prank(merchant);
        vm.expectRevert(VirtualAddressRegistry.WalletAlreadyExists.selector);
        registry.registerMaster(walletId, receiver);
    }
}
