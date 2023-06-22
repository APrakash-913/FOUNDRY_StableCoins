// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

/////////////
// IMPORTS //
/////////////
import {DecentralizedStableCoins} from "./DecentralizedStableCoins.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

/**
 * @title DSCEngine
 * @author Abhinav Prakash
 *
 * ✨ The system is designed to be as minimal as possible, and have a token maintain 1 token == $1 peg.
 * This Stable coins has properties:
 *   👉 Exogenous Collateral
 *   👉 Dollar Pegged
 *   👉 Algorithmically Stable
 *
 * 🛅 Our DSC System should always be "overcollateralized". At no point, should the value of all the collateral <= value of all DSC.
 * 🧑‍🏫 Similar to DAI, if DAI has no governance, no fees, and was backed by wETH, wBTC.
 *
 * @notice It handles all the logic for minting & redeeming to depositing & withdrawing collateral.
 */
contract DSCEngine is ReentrancyGuard {
    ////////////
    // ERRORS //
    ////////////
    error DSCEngine__HealthFactorOk();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__DSCMintingFailed();
    error DSCEngine__TransactionFailed();
    error DSCEngine__RequireMoreThanZero();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__BadHealthFactor(uint256 healthFactor);
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeOfSameLength();

    /////////////////////
    // STATE VARIABLES //
    /////////////////////
    uint256 private constant PRECISSION = 1e18;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 💳♻️ 200% collateralized
    uint256 private constant LIQUIDATION_PRECISSION = 100;
    uint256 private constant ADDITIONAL_FEED_PRECISSION = 1e10;

    address[] private s_collateralTokens;
    DecentralizedStableCoins private immutable i_dsc;
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => uint256 amountDSCMinted) private s_DSCMinted;
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited;

    ////////////
    // EVENTS //
    ////////////
    event CollateralDeposited(
        address indexed depositer,
        address indexed tokenAddressDeposited,
        uint256 indexed amountDeposited
    );

    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed tokenAddressDeposited,
        uint256 amountDeposited
    );

    event DSCMinted(address indexed minter, uint256 amountMinted);

    ///////////////
    // MODIFIERS //
    ///////////////
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__RequireMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    /////////////////
    // CONSTRUCTOR //
    /////////////////
    constructor(
        address[] memory tokenAddress,
        address[] memory priceFeedAddress,
        address dscAddress
    ) {
        if (tokenAddress.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeOfSameLength();
        }
        // USD priceFeed needed
        for (uint256 i; i < tokenAddress.length; i++) {
            s_priceFeeds[tokenAddress[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddress[i]);
        }
        i_dsc = DecentralizedStableCoins(dscAddress);
    }

    ////////////////////////
    // EXTERNAL FUNCTIONS //
    ////////////////////////
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        // Update the mapping;
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransactionFailed();
        }
    }

    /**
     *
     * @param amountDscUserWantToMint The amount of decentralized Stablecoin (DSC) to mint
     * @notice User must have more collateral than the minimum threshold
     */
    function mintDsc(
        uint256 amountDscUserWantToMint
    ) public moreThanZero(amountDscUserWantToMint) nonReentrant {
        s_DSCMinted[msg.sender] = amountDscUserWantToMint;
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscUserWantToMint);
        if (!minted) {
            revert DSCEngine__DSCMintingFailed();
        }

        emit DSCMinted(msg.sender, amountDscUserWantToMint);
    }

    /**
     *
     * @param tokenAddress Address of Tokens.
     * @param amountCollateral Amount of token to be deposited.
     * @param dscToBeMinted Amount of DSC to be minted.
     *
     * @notice This function will deposit collateral and mint DSC in one TXN.
     */
    function depositCollateralAndMintDsc(
        address tokenAddress,
        uint256 amountCollateral,
        uint256 dscToBeMinted
    ) external {
        depositCollateral(tokenAddress, amountCollateral);
        mintDsc(dscToBeMinted);
    }

    // redeem + burn at same time.
    /**
     *
     * @param tokenAddress Address of the token to be Redeemed
     * @param amountCollateral Amount of collateral to be Redeemed
     * @param amountOfDscToBeBurnt Amount of DSCUser want to burn.
     * @notice This function burns DSC and Redeem collateral at the same time.
     */
    function redeemCollateralForDsc(
        address tokenAddress,
        uint256 amountCollateral,
        uint256 amountOfDscToBeBurnt
    ) external {
        burnDsc(amountOfDscToBeBurnt);
        // NOTE: redeemCollateral() already checks health factor
        redeemCollateral(tokenAddress, amountCollateral);
    }

    function redeemCollateral(
        address tokenAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(
            msg.sender,
            msg.sender,
            tokenAddress,
            amountCollateral
        );

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDsc(
        uint256 amountOfDscToBeBurnt
    ) public moreThanZero(amountOfDscToBeBurnt) {
        _burnDsc(amountOfDscToBeBurnt, msg.sender, msg.sender); // ⚠️ -> Someone calling BURN() on its own.
        _revertIfHealthFactorIsBroken(msg.sender); // ⚠️ I don't think this is needed.
    }

    /**
     *
     * @param collateral Address of the Collateral to be liquidated
     * @param user Address of the user whom we have to liquidate
     * @param debtToCover user's debt to be covered by liquidator
     * @notice 👉 One cam partially liquidate the user.
     * 		   👉 liquidator will get Liquidation bonusfor taking user funds.
     * 		   👉 Here the function assumes that the debt should be 200% overcollateralized.
     * @notice 👉 A known bug would be that if the protocol is 100% or undercollateralized, the liquidator won't be incentivized.
     */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        if (_healthFactor(user) >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        // Eg; Bad user: $140 ETH, $100 DSC || -> Confiscate $140 and burn $100 DSC
        // Need to figure out $100 DSC = $? ETH => use pricefeeds
        uint256 amountOfDebtToBeCoveredInCollateralTokenTerms = getTokenAmountFromUSD(
                collateral,
                debtToCover
            );
        // We also have to give 10% liquidation bonus
        // 0.5*0.1 = 0.05ETH => Getting 0.55ETH
        uint256 bonusCollateral = (amountOfDebtToBeCoveredInCollateralTokenTerms *
                LIQUIDATION_BONUS) / LIQUIDATION_PRECISSION;

        uint256 collateralToBeRedeemed = bonusCollateral +
            amountOfDebtToBeCoveredInCollateralTokenTerms;

        _redeemCollateral(user, msg.sender, collateral, collateralToBeRedeemed);
        // 🔥 DSC
        _burnDsc(debtToCover, user, msg.sender);
        // If at th end HEALTH_FACTOR doesn't improve then REVERT.
        if (_healthFactor(user) < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorNotImproved();
        }

        // Revert if Liquidator health factor BROKES💔
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view {}

    function getCollateralDeposited(
        address user,
        address tokenAddress
    ) external view returns (uint256) {
        return s_collateralDeposited[user][tokenAddress];
    }

    //////////////////////////////////
    // INTERNAL & PRIVATE FUNCTIONS //
    //////////////////////////////////

    function _redeemCollateral(
        address from,
        address to,
        address tokenAddress,
        uint256 amountCollateral
    ) private {
        s_collateralDeposited[from][tokenAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenAddress, amountCollateral);

        // 📝 contract need to send the Requested_Collateral to the User/Redeemer.
        bool success = IERC20(tokenAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransactionFailed();
        }
    }

    /**
     *
     * @param amountOfDscToBeBurnt Amount of DSC to be burnt
     * @param onBehelfOf Whose DSC will be burnt.
     * @param dscFrom From where that DSC gonna come from.
     *
     * @dev Low-Level internal function, don't call unless the function calling it is checking for health-factor being broken.
     */
    function _burnDsc(
        uint256 amountOfDscToBeBurnt,
        address onBehelfOf,
        address dscFrom
    ) private {
        s_DSCMinted[onBehelfOf] -= amountOfDscToBeBurnt;
        // 📝 User need to transfer DSC -> This contract for burning.
        bool success = i_dsc.transferFrom(
            dscFrom,
            address(this),
            amountOfDscToBeBurnt
        );
        if (!success) {
            revert DSCEngine__TransactionFailed();
        }
        i_dsc.burn(amountOfDscToBeBurnt);
    }

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValueInUSD(user);
    }

    /**
     *
     * @param user Address of User
     * @notice Returns how close the user is to liquidation.
     */
    function _healthFactor(address user) private view returns (uint256) {
        (
            uint256 totalDscMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function _calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) internal pure returns (uint256) {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISSION;
        return (collateralAdjustedForThreshold * 1e18) / totalDscMinted;
    }

    /**
     * @param user Address of the user
     * @dev Do they have enough collateral. If NOT then revert.
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BadHealthFactor(userHealthFactor);
        }
    }

    function _getUSDValueOfTokens(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        (, int256 answer, , , ) = AggregatorV3Interface(s_priceFeeds[token])
            .latestRoundData();
        /**
         * 🧮 answer -> 1e8 form || amount -> 1e18 form
         * to multiply effectivetly, both must have same decimal places.
         * i.e. if 1ETH = $1000
         * => (1000 * 1e8 * 1e10)*(amount*1e18)
         */
        return
            ((uint256(answer) * ADDITIONAL_FEED_PRECISSION) * amount) /
            PRECISSION;
    }

    /////////////////////////////////
    // PUBLIC & EXTERNAL FUNCTIONS //
    /////////////////////////////////
    function getTokenAmountFromUSD(
        address collateralAddress,
        uint256 amountInUsd
    ) public view returns (uint256) {
        (, int256 answer, , , ) = AggregatorV3Interface(
            s_priceFeeds[collateralAddress]
        ).latestRoundData();

        // answer (1e8 format) => $x/ETH = $x/1e18Wei

        return
            (PRECISSION * amountInUsd) /
            (uint256(answer) * ADDITIONAL_FEED_PRECISSION);
    }

    function getAccountCollateralValueInUSD(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 index = 0; index < s_collateralTokens.length; index++) {
            address token = s_collateralTokens[index];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += _getUSDValueOfTokens(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getPriceFeedArrayData(
        address tokensAddress
    ) public view returns (address) {
        return s_priceFeeds[tokensAddress];
    }

    function getCollateralTokenArrayData(
        uint256 index
    ) public view returns (address) {
        return s_collateralTokens[index];
    }

    function getAccountInfo(
        address user
    ) public view returns (uint256, uint256) {
        (
            uint256 totalDscMinted,
            uint256 totalCollateral
        ) = _getAccountInformation(user);
        return (totalDscMinted, totalCollateral);
    }

    function getAmountOfMintedDsc(address user) public view returns (uint256) {
        return s_DSCMinted[user];
    }
}
