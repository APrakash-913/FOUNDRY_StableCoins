// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

/**
 * NOTE
 * have Invariants => aka the properties of the system that should always hold true.
 * What are our Invariants?
 *   -> Total supply of DSC should be less then the total value of collateral
 *   -> Getter func should never revert.
 */

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {Handler} from "./Handler.t.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDSCEngine} from "../../script/DeployDSCEngine.s.sol";
import {DecentralizedStableCoins} from "../../src/DecentralizedStableCoins.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Invariant is StdInvariant, Test {
    DecentralizedStableCoins dsc;
    HelperConfig helperConfig;
    DeployDSCEngine deployer;
    DSCEngine dscEngine;
    Handler handler;

    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSCEngine();
        (dscEngine, dsc, helperConfig) = deployer.run();
        (, , weth, wbtc, ) = helperConfig.activeNetworkConfig();
        handler = new Handler(dscEngine, dsc);
        // FOUNDRY go WILD on ⬇️ contract🔥🔥🔥🔥
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // Get the value of all the collateral in the protocol.
        // compare it with protocol's debt(dsc).
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));

        uint256 wethValue = dscEngine._getUSDValueOfTokens(
            weth,
            totalWethDeposited
        );
        uint256 wbtcValue = dscEngine._getUSDValueOfTokens(
            wbtc,
            totalWbtcDeposited
        );

        console.log("weth value: ", wethValue);
        console.log("wbtc value: ", wbtcValue);
        console.log("total supply:", totalSupply);
        console.log("times mint is called:", handler.timeMintIsCalled());

        assert(wbtcValue + wethValue >= totalSupply);
    }

    // function invariant_gettersShouldNotRevert() public view {}
    // ✅
    // dscEngine.getTokenAmountFromUSD(
    //     address collateralAddress,
    //     uint256 amountInUsd
    // )

    // dscEngine.getAccountCollateralValueInUSD(
    //     address user
    // )

    // dscEngine.getPriceFeedArrayData(
    //     address tokensAddress
    // )

    //  dscEngine.getCollateralTokenArrayData(
    //     uint256 index
    // )

    // dscEngine.getAccountInfo(
    //     address user
    // )

    // dscEngine.getAmountOfMintedDsc(address user)

    // dscEngine.getCollateralTokens()

    // dscEngine.getCollateralBalanceOfUser()
    // }
}
