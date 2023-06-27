// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

// Handler will narrow down the way we call the function.

/**
 * 1️⃣ Dont call "redeemCollateral()" unless there is collateral to redeem.
 */

import {Test} from "forge-std/Test.sol";

import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {DecentralizedStableCoins} from "../../src/DecentralizedStableCoins.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dscEngine;
    DecentralizedStableCoins dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    // 👻 Ghost Variables
    uint256 public timeMintIsCalled;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;

    // ⚠️ Choosing uint96 becoz this will ensure that FOUDRY doesnt puch any no. that can hit the Boundry of "uint256".
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoins _dsc) {
        dsc = _dsc;
        dscEngine = _dscEngine;

        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(
            dscEngine.getPriceFeedArrayData(address(weth))
        );
    }

    //////////////
    // HANDLERS //
    //////////////

    // 🎯 Deposit Collateral 🎯 \\
    function depositCollateral(
        uint256 collateralSeed, // ~ Fuzz testing
        uint256 amountCollateral
    ) public {
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        // ⚠️ Ensure that the SENDER approves adequate amount of collateral;
        vm.startPrank(msg.sender);
        _getCollateralFromSeed(collateralSeed).mint(
            msg.sender,
            amountCollateral
        );
        _getCollateralFromSeed(collateralSeed).approve(
            address(dscEngine),
            amountCollateral
        );

        dscEngine.depositCollateral(
            address(_getCollateralFromSeed(collateralSeed)),
            amountCollateral
        );
        vm.stopPrank();

        usersWithCollateralDeposited.push(msg.sender);
    }

    // 🎯 Redeem Collateral 🎯 \\
    function redeemCollateral(
        uint256 collateralSeed, // ~ Fuzz testing
        uint256 amountCollateral
    ) public {
        vm.startPrank(msg.sender);
        uint256 maxCollateralToRedeem = dscEngine.getCollateralBalanceOfUser(
            msg.sender,
            address(_getCollateralFromSeed(collateralSeed))
        );
        // bounding "amountCollateral" var.
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }
        dscEngine.redeemCollateral(
            address(_getCollateralFromSeed(collateralSeed)),
            amountCollateral
        );
    }

    // 🎯 Mint DSC 🎯 \\
    // ⚠️ -> getting 5 reverts.
    function mintDsc(uint256 amount, uint256 addressSeed) public {
        // Since, we need 200% collateral for minting a DSC.
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[
            addressSeed % usersWithCollateralDeposited.length
        ];
        (uint256 dscToken, uint256 collateral) = dscEngine.getAccountInfo(
            sender
        );
        int256 bal = (int256(collateral) / 2) -
            int256(dscEngine._getUSDValueOfTokens(address(weth), dscToken));
        if (bal < 0) {
            return;
        }
        amount = bound(amount, 1, uint256(bal));

        vm.startPrank(sender);
        dscEngine.mintDsc(amount);
        vm.stopPrank();
        timeMintIsCalled++;
    }

    // ⚠️ -> this will break our "invariant test" suite.
    // function updareCollateralPrice(uint96 _newPrice) public {
    //     int256 newPrice = int256(uint256(_newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPrice);
    // }

    // ~~~ Helper Functions ~~~ \\
    function _getCollateralFromSeed(
        uint256 _collateralSeed
    ) private view returns (ERC20Mock) {
        if (_collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }

    // function _getDepositorAddressFromSeed(
    //     uint256 _addressSeed
    // ) private view returns (address) {
    //     if (usersWithCollateralDeposited.length == 0) {
    //         return ;
    //     }
    //     uint256 index = _addressSeed % usersWithCollateralDeposited.length;
    //     return usersWithCollateralDeposited[index];
    // }
}
