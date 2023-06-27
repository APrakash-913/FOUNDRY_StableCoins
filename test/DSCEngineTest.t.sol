// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";

import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {DeployDSCEngine} from "../script/DeployDSCEngine.s.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {DecentralizedStableCoins} from "../src/DecentralizedStableCoins.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    event CollateralDeposited(
        address indexed depositer,
        address indexed tokenAddressDeposited,
        uint256 indexed amountDeposited
    );

    event CollateralRedeemed(
        address indexed redeemedFrom,
        uint256 indexed amountCollateral,
        address from,
        address to
    );

    event DSCMinted(address indexed minter, uint256 amountMinted);

    DSCEngine dscEngine;
    DeployDSCEngine deployer;
    HelperConfig helperConfig;
    DecentralizedStableCoins dsc;

    address weth;
    address wbtc;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;

    address public USER = makeAddr("USER");
    uint256 public constant MINT_VALUE = 4 ether;
    uint256 public constant BURN_VALUE = 2 ether;
    uint256 public constant REDEEM_VALUE = 2 ether;
    uint256 public constant DEPOSIT_VALUE = 10 ether;
    uint256 public constant STARTING_BALANCE = 1000 ether;

    address public LIQUIDATOR = makeAddr("LIQUIDATOR");
    uint256 public constant LIQUIDATOR_BALANCE = 1000 ether;
    uint256 public constant LIQUIDATOR_DEPOSIT_VALUE = 900 ether;
    uint256 public constant LIQUIDATOR_MINT_VALUE = 300 ether;
    uint256 public constant USER_MINT_VALUE = 10000e18;

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), STARTING_BALANCE);
        dscEngine.depositCollateral(weth, DEPOSIT_VALUE);
        vm.stopPrank();
        _;
    }

    modifier liquidatorAssets() {
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dscEngine), LIQUIDATOR_BALANCE);
        dscEngine.depositCollateral(weth, LIQUIDATOR_DEPOSIT_VALUE);
        dscEngine.mintDsc(LIQUIDATOR_MINT_VALUE);
        vm.stopPrank();
        _;
    }

    modifier liquidator() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), DEPOSIT_VALUE);
        dscEngine.depositCollateralAndMintDsc(
            weth,
            DEPOSIT_VALUE,
            // dscEngine._getUSDValueOfTokens(weth, USER_MINT_VALUE)
            USER_MINT_VALUE
        );
        vm.stopPrank();

        uint256 oldWethToUsdValue = 2000e8; // 1 ETH = $1000
        int256 newWethToUsdValue = 999e8; // 1 ETH = $1000

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(newWethToUsdValue);
        uint256 userHealthFactor = dscEngine.getHealthFactor(USER);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dscEngine), LIQUIDATOR_BALANCE);
        dscEngine.depositCollateral(weth, LIQUIDATOR_DEPOSIT_VALUE);
        dscEngine.mintDsc(LIQUIDATOR_MINT_VALUE);

        dsc.approve(
            address(dscEngine),
            (USER_MINT_VALUE * 1e10) / oldWethToUsdValue
        );
        dscEngine.liquidate(
            weth,
            USER,
            (USER_MINT_VALUE * 1e10) / oldWethToUsdValue
        ); // We are covering their whole debt
        vm.stopPrank();
        _;
    }

    function setUp() external {
        deployer = new DeployDSCEngine();
        (dscEngine, dsc, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, ) = helperConfig
            .activeNetworkConfig();
        // 🏦 Providing fund to User.
        ERC20Mock(weth).mint(USER, STARTING_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, LIQUIDATOR_BALANCE);
    }

    //////////////////////
    // CONSTRUCTOR TEST //
    //////////////////////
    address[] private tokens;
    address[] private pricefeeds;

    function testRevertsIfTokenLengthNotEqualPricefeedLength() public {
        tokens.push(weth);
        pricefeeds.push(ethUsdPriceFeed);
        pricefeeds.push(btcUsdPriceFeed);

        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeOfSameLength
                .selector
        );
        // Deploy NEW DSCEngine
        new DSCEngine(tokens, pricefeeds, address(dsc));
    }

    function testCorrectlyUpdatePriceFeedMapping() public {
        console.log(dscEngine.getPriceFeedArrayData(weth));
        console.log(ethUsdPriceFeed);
        assertEq(dscEngine.getPriceFeedArrayData(weth), ethUsdPriceFeed);
        assertEq(dscEngine.getPriceFeedArrayData(wbtc), btcUsdPriceFeed);
    }

    function testCorrectlyUpdateTokenAddressArray() public {
        console.log(dscEngine.getCollateralTokenArrayData(0));
        console.log(weth);
        assertEq(dscEngine.getCollateralTokenArrayData(0), weth);
        assertEq(dscEngine.getCollateralTokenArrayData(1), wbtc);
    }

    ///////////////
    // PRICETEST //
    ///////////////

    function testGetUSDValueOfTokens() public {
        uint256 amt = 15e18;
        // (15 * $2000/ETH) = $30000 = 30,000e18
        assertEq(dscEngine._getUSDValueOfTokens(weth, amt), 30000e18);
    }

    function testGetTokenAmountFromUSD() public {
        uint256 amt = 30000e18; //🪙 30000 USD
        // (15 * $2000/ETH) = $30000 = 30,000e18
        assertEq(dscEngine.getTokenAmountFromUSD(weth, amt), 15e18);
    }

    /////////////////////////////
    // DEPOSIT-COLLATERAL TEST //
    /////////////////////////////

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), DEPOSIT_VALUE);
        vm.expectRevert(DSCEngine.DSCEngine__RequireMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    // ⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️
    function testOnlyWethAndWbtcIsAllowed() public {
        // Mint a different type of token. aka -> AP
        ERC20Mock AP = new ERC20Mock();
        // Transfer AP Token to the user
        AP.mint(USER, STARTING_BALANCE);

        // console.log(address(AP)); ||-> 0x2e234DAe75C793f67A35089C9d99245E1C58470b
        // console.log(weth);        ||-> 0xA8452Ec99ce0C64f20701dB7dD3abDb607c00496
        // console.log(wbtc);        ||-> 0xDB8cFf278adCCF9E9b5da745B44E754fC4EE3C76

        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscEngine.depositCollateral(address(AP), DEPOSIT_VALUE);
        vm.stopPrank();
    }

    function testMappingIsCorrectlyPopulated() public depositedCollateral {
        (uint256 totalDscMinted, uint256 totalCollateral) = dscEngine
            .getAccountInfo(USER);
        assertEq(
            totalCollateral,
            dscEngine.getAccountCollateralValueInUSD(USER)
        );
        assertEq(totalDscMinted, 0);
    }

    function testEmitsIfDepositIsSuccesful() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), DEPOSIT_VALUE);
        vm.expectEmit(true, true, true, false, address(dscEngine)); //✨✨✨
        emit CollateralDeposited(USER, weth, DEPOSIT_VALUE);
        dscEngine.depositCollateral(weth, DEPOSIT_VALUE);
        vm.stopPrank();
    }

    function testSuccesfulTransferOfAssets() public depositedCollateral {
        console.log(ERC20Mock(weth).balanceOf(USER)); // 990.000000000000000000
        console.log(STARTING_BALANCE - DEPOSIT_VALUE); // 990.000000000000000000
        console.log(ERC20Mock(weth).balanceOf(address(dscEngine))); // 10.000000000000000000

        assertEq(
            ERC20Mock(weth).balanceOf(USER),
            (STARTING_BALANCE - DEPOSIT_VALUE)
        );
        assertEq(ERC20Mock(weth).balanceOf(address(dscEngine)), DEPOSIT_VALUE);
    }

    ///////////////////
    // MINT DSC TEST //
    ///////////////////

    // ⚠️⚠️ Require seperate Setup.
    // function testRevertsIfMintingIsUnsuccessful() public {

    // }

    function testRevertsIfMintDscIsZero() public depositedCollateral {
        vm.expectRevert(DSCEngine.DSCEngine__RequireMoreThanZero.selector);
        dscEngine.mintDsc(0);
    }

    // function testRevertIfHealthFactorBreaks() public depositedCollateral {
    //     vm.startPrank(USER);
    //     vm.expectRevert();
    //     dscEngine.mintDsc(10 ether);
    //     vm.stopPrank();
    // }

    function testEmitsIfMintingIsSuccessful() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectEmit(true, false, false, false, address(dscEngine));
        emit DSCMinted(USER, MINT_VALUE);
        dscEngine.mintDsc(MINT_VALUE);
        vm.stopPrank();
    }

    function testMappingIsPopulatedByMintDsc() public depositedCollateral {
        (uint256 dsc1, uint256 collateral) = dscEngine.getAccountInfo(USER);
        console.log(collateral); // output: (0,20000.000000000000000000 -> 10ETH)
        console.log(MINT_VALUE);
        console.log(dscEngine._getUSDValueOfTokens(weth, MINT_VALUE));
        console.log(dscEngine.calculateHealthFactor(dsc1, collateral));
        console.log(ERC20Mock(weth).balanceOf(address(dscEngine)));

        vm.startPrank(USER);
        dscEngine.mintDsc(MINT_VALUE);
        vm.stopPrank();
        // console.log(dsc.balanceOf(USER));
        // console.log(MINT_VALUE);
        assertEq(MINT_VALUE, dsc.balanceOf(USER));
    }

    /////////////////
    // REDEEM TEST //
    /////////////////

    function testRevertIfCollateralRedeemIsZero() public depositedCollateral {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__RequireMoreThanZero.selector);
        dscEngine.redeemCollateral(weth, 0);
    }

    ///// _REDEEM TEST
    function testCollateralDepositArrayIsCorrectlyUpdated()
        public
        depositedCollateral
    {
        // (, uint256 collateral) = dscEngine.getAccountInfo(USER);
        // console.log(collateral); // output: (0,20000.000000000000000000) -> $
        // console.log(ERC20Mock(weth).balanceOf(USER));
        vm.prank(USER);
        dscEngine.redeemCollateral(weth, REDEEM_VALUE);
        (, uint256 collateral) = dscEngine.getAccountInfo(USER);
        // console.log(collateral); // output: (0,16000.000000000000000000) -> $
        // console.log(ERC20Mock(weth).balanceOf(USER));

        assertEq(
            ERC20Mock(weth).balanceOf(USER),
            (STARTING_BALANCE - DEPOSIT_VALUE + REDEEM_VALUE)
        );

        assertEq(
            collateral,
            dscEngine._getUSDValueOfTokens(weth, (DEPOSIT_VALUE - REDEEM_VALUE))
        );
    }

    function testEmitAfterRedeemingCollateral() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectEmit(true, false, false, false, address(dscEngine));
        emit CollateralRedeemed(USER, REDEEM_VALUE, USER, USER);
        dscEngine.redeemCollateral(weth, REDEEM_VALUE);
        vm.stopPrank();
    }

    ///////////////////
    // BURN DSC TEST //
    ///////////////////

    function testRevertIfDscBurntIsZero() public depositedCollateral {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__RequireMoreThanZero.selector);
        dscEngine.burnDsc(0);
    }

    function testDscMintedArrayIsCorrectlyPopulated()
        public
        depositedCollateral
    {
        vm.prank(USER);
        dscEngine.mintDsc(MINT_VALUE);

        vm.startPrank(USER);
        dsc.approve(address(dscEngine), MINT_VALUE);
        dscEngine.burnDsc(BURN_VALUE);
        vm.stopPrank();

        (uint256 dsc1, ) = dscEngine.getAccountInfo(USER);
        // console.log(dsc1);
        // console.log((MINT_VALUE - BURN_VALUE));
        // console.log(collateral);
        // console.log(
        //     dscEngine._getUSDValueOfTokens(
        //         weth,
        //         (DEPOSIT_VALUE - MINT_VALUE + BURN_VALUE)
        //     )
        // );
        assertEq(dsc1, (MINT_VALUE - BURN_VALUE));
    }

    ////////////////////////////////////
    // REDEEM_COLLATERAL_FOR_DSC TEST //
    ////////////////////////////////////
    function testBurnDscAndRedeemCollateralAtSameTxn()
        public
        depositedCollateral
    {
        vm.startPrank(USER);
        dscEngine.mintDsc(MINT_VALUE);
        dsc.approve(address(dscEngine), MINT_VALUE);
        dscEngine.redeemCollateralForDsc(weth, REDEEM_VALUE, BURN_VALUE);
        vm.stopPrank();

        (uint256 dsc1, uint256 collateral) = dscEngine.getAccountInfo(USER);
        assertEq(dsc1, (MINT_VALUE - BURN_VALUE));
        console.log(collateral);
        // console.log(DEPOSIT_VALUE - REDEEM_VALUE);
        assertEq(
            collateral,
            dscEngine._getUSDValueOfTokens(weth, (DEPOSIT_VALUE - REDEEM_VALUE))
        );
    }

    //////////////////////////////////////////
    // DEPOSIT_COLLATERAL_AND_MINT_DSC TEST //
    //////////////////////////////////////////

    function testMintDscAndDepositCollateralAtSameTxn() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), STARTING_BALANCE);
        dscEngine.depositCollateralAndMintDsc(weth, DEPOSIT_VALUE, MINT_VALUE);
        vm.stopPrank();

        (uint256 dsc1, uint256 collateral) = dscEngine.getAccountInfo(USER);
        assertEq(dsc1, MINT_VALUE);
        assertEq(
            collateral,
            dscEngine._getUSDValueOfTokens(weth, DEPOSIT_VALUE)
        );
    }

    //////////////////////
    // LIQUIDATION TEST //
    //////////////////////

    function testRevertIfDebtToCoverIsZero() public depositedCollateral {
        vm.prank(LIQUIDATOR);
        vm.expectRevert(DSCEngine.DSCEngine__RequireMoreThanZero.selector);
        dscEngine.liquidate(weth, USER, 0);
    }

    function testRevertIfHealthFactorIsOk() public depositedCollateral {
        vm.startPrank(USER);
        dscEngine.mintDsc(MINT_VALUE);
        vm.stopPrank();

        vm.prank(LIQUIDATOR);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dscEngine.liquidate(weth, USER, MINT_VALUE);
    }

    function testLiquitatorIsAbleToRedeemCollateral() public liquidator {
        // TEST
        // (uint256 dsc1, uint256 collateral) = dscEngine.getAccountInfo(
        //     LIQUIDATOR
        // );
        // console.log(dsc1);
        // console.log(collateral);
        // ⬇️⬇️⬇️
        uint256 wethLiquidatorWillGet = (USER_MINT_VALUE * 110) / 100; // in $
        uint256 wethLiquidatorWillGetInEth = dscEngine.getTokenAmountFromUSD(
            weth,
            (USER_MINT_VALUE * 110) / 100
        ); // in ETH

        uint256 endWethBalLiquidator = ERC20Mock(weth).balanceOf(LIQUIDATOR);

        console.log(endWethBalLiquidator);
        console.log(wethLiquidatorWillGetInEth);
        console.log((LIQUIDATOR_BALANCE - LIQUIDATOR_DEPOSIT_VALUE));
        console.log(LIQUIDATOR_BALANCE);
        console.log(wethLiquidatorWillGet);

        assertEq(
            wethLiquidatorWillGetInEth,
            (endWethBalLiquidator -
                (LIQUIDATOR_BALANCE - LIQUIDATOR_DEPOSIT_VALUE))
        );
    }

    ////////////////////////
    // HEALTH_FACTOR TEST //
    ////////////////////////

    function testCorectlySetMinHealthFactor() public {
        assertEq(dscEngine.getMinHealthFactor(), 1e18);
    }

    function testGetHealthFactor() public depositedCollateral {
        vm.startPrank(USER);
        dscEngine.mintDsc(dscEngine._getUSDValueOfTokens(weth, MINT_VALUE)); // 1.250000000000000000 => 1.25e18
        vm.stopPrank();

        // DEPOSIT_VALUE = 10 ETH  ||  MINT_VALUE = 4 ETH ==> Expected healthFactor = 5/(4) = 1.25e18
        // console.log(dscEngine.getHealthFactor(USER));
        assertEq(125e16, dscEngine.getHealthFactor(USER));
    }

    // _calculateHealthfactor
    function testHealthFactorForZeroDscMint() public depositedCollateral {
        assertEq(dscEngine.getHealthFactor(USER), type(uint256).max);
    }

    function testHealthFactorCanBeLessThanOne() public depositedCollateral {
        vm.startPrank(USER);
        dscEngine.mintDsc(dscEngine._getUSDValueOfTokens(weth, MINT_VALUE));
        vm.stopPrank();

        int256 newConversionRate = 500e8;

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(newConversionRate);
        /**
         * DEPOSIT_VAL_INITIAL = 10 ETH = $ 20000    ||    MINT_VAL_INITIAL = 4 ETH = $ 8000
         * DEPOSIT_VAL_FINAL = 10 ETH = $ 5000       ||    MINT_VAL_INITIAL = 4 ETH = $ 8000
         * Final HF = 2500/8000 = 0.3125e18
         */

        assertEq(3125e14, dscEngine.getHealthFactor(USER));
    }
}
