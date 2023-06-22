// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoins} from "../src/DecentralizedStableCoins.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {DeployDSCEngine} from "../script/DeployDSCEngine.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    event CollateralDeposited(
        address indexed depositer,
        address indexed tokenAddressDeposited,
        uint256 indexed amountDeposited
    );

    DSCEngine dscEngine;
    DeployDSCEngine deployer;
    HelperConfig helperConfig;
    DecentralizedStableCoins dsc;

    address weth;
    address wbtc;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;

    address public USER = makeAddr("USER");
    uint256 public constant MINT_VALUE = 1 ether;
    uint256 public constant DEPOSIT_VALUE = 10 ether;
    uint256 public constant STARTING_BALANCE = 1000 ether;

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), STARTING_BALANCE);
        dscEngine.depositCollateral(weth, DEPOSIT_VALUE);
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

    //////////////
    // MINT DSC //
    //////////////

    // ⚠️⚠️ Require seperate Setup.
    function testRevertsIfMintDscIsZero() public depositedCollateral {
        vm.expectRevert(DSCEngine.DSCEngine__RequireMoreThanZero.selector);
        dscEngine.mintDsc(0);
    }

    function testMappingIsPopulatedByMintDsc() public depositedCollateral {
        (uint256 dsc1, uint256 collateral) = dscEngine.getAccountInfo(USER);
        console.log(dsc1, collateral);

        dscEngine.mintDsc(MINT_VALUE);
        // console.log(dsc.balanceOf(USER));
        // console.log(MINT_VALUE);
        // assertEq(MINT_VALUE, dsc.balanceOf(USER));
    }
}
