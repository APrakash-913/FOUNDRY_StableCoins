// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStableCoins} from "../src/DecentralizedStableCoins.sol";
import {DeployDecentralizedStableCoins} from "../script/DeployDecentralizedStableCoins.s.sol";

contract DecentralizedStableCoinsTest is Test {
    DeployDecentralizedStableCoins deployer;
    DecentralizedStableCoins decentralizedStableCoins;

    address USER = makeAddr("USER");
    uint256 public constant MINT_AMOUNT = 1e16;
    uint256 public constant BURN_AMOUNT = 1e16;

    function setUp() external {
        deployer = new DeployDecentralizedStableCoins();
        decentralizedStableCoins = deployer.run();
    }

    function testCorrectNameSetup() public {
        assertEq(decentralizedStableCoins.name(), "DecentralizedStableCoin");
    }

    function testCorrectSymbolSetup() public {
        assertEq(decentralizedStableCoins.symbol(), "DSC");
    }

    function testOnlyOwnerCanMint() public {
        vm.prank(USER);
        vm.expectRevert();
        decentralizedStableCoins.mint(USER, MINT_AMOUNT);
    }

    function testOnlyOwnerCanBurn() public {
        vm.prank(USER);
        vm.expectRevert();
        decentralizedStableCoins.burn(BURN_AMOUNT);
    }

    function testBurnAmountGreaterThanZero() public {
        vm.expectRevert();
        decentralizedStableCoins.burn(0);
    }

    function testMintAmountGreaterThanZero() public {
        vm.expectRevert();
        decentralizedStableCoins.mint(msg.sender, 0);
    }

    function testMintAddressMustBeValid() public {
        vm.expectRevert();
        decentralizedStableCoins.mint(address(0), 0);
    }

    function testBurnAmountLessThanBalance() public {
        vm.prank(USER);
        vm.expectRevert();
        decentralizedStableCoins.burn(1e18);
    }
}
