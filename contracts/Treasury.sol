// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./lib/Babylonian.sol";
import "./owner/Operator.sol";
import "./utils/ContractGuard.sol";
import "./interfaces/IBasisAsset.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IPiggybank.sol";

contract Treasury is ContractGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========= CONSTANT VARIABLES ======== */

    uint256 public constant PERIOD = 6 hours;

    /* ========== STATE VARIABLES ========== */

    // governance
    address public operator;

    // flags
    bool public initialized = false;

    // epoch
    uint256 public startTime;
    uint256 public epoch = 0;
    uint256 public epochSupplyContractionLeft = 0;

    // exclusions from total supply
    address[] public excludedFromTotalSupply = [
        address(0xEDf83B9939B83cDff224cD093F71bB772c76A603), // BnbGenesisPool
        address(0xBB4b88B836180177c50b69B5343FBBAA59b028E9), // CakeGenesisPool
        address(0xe9aBF38253C6BC768e68B0b311515258B0C6D4C2), // BananaGenesisPool
        address(0xA6B536e578a159c78b216135B1b417a634EA3a01)  // NftartGenesisPool
    ];

    // core components
    address public dibs;
    address public dbond;
    address public dshare;

    address public piggybank;
    address public dibsOracle;

    // price
    uint256 public dibsPriceOne;
    uint256 public dibsPriceCeiling;

    uint256 public seigniorageSaved;

    uint256[] public supplyTiers;
    uint256[] public maxExpansionTiers;

    uint256 public maxSupplyExpansionPercent;
    uint256 public bondDepletionFloorPercent;
    uint256 public seigniorageExpansionFloorPercent;
    uint256 public maxSupplyContractionPercent;
    uint256 public maxDebtRatioPercent;

    // 28 first epochs (1 week) with 3% expansion regardless of DIBS price
    uint256 public bootstrapEpochs;
    uint256 public bootstrapSupplyExpansionPercent;

    /* =================== Added variables =================== */
    uint256 public previousEpochDibsPrice;
    uint256 public maxDiscountRate; // when purchasing bond
    uint256 public maxPremiumRate; // when redeeming bond
    uint256 public discountPercent;
    uint256 public premiumThreshold;
    uint256 public premiumPercent;
    uint256 public mintingFactorForPayingDebt; // print extra DIBS during debt phase

    address public daoFund;
    uint256 public daoFundSharedPercent;

    address public devFund;
    uint256 public devFundSharedPercent;

    /* =================== Events =================== */

    event Initialized(address indexed executor, uint256 at);
    event BurnedBonds(address indexed from, uint256 bondAmount);
    event RedeemedBonds(address indexed from, uint256 dibsAmount, uint256 bondAmount);
    event BoughtBonds(address indexed from, uint256 dibsAmount, uint256 bondAmount);
    event TreasuryFunded(uint256 timestamp, uint256 seigniorage);
    event PiggybankFunded(uint256 timestamp, uint256 seigniorage);
    event DaoFundFunded(uint256 timestamp, uint256 seigniorage);
    event DevFundFunded(uint256 timestamp, uint256 seigniorage);

    /* =================== Modifier =================== */

    modifier onlyOperator() {
        require(operator == msg.sender, "Treasury: caller is not the operator");
        _;
    }

    modifier checkCondition() {
        require(now >= startTime, "Treasury: not started yet");

        _;
    }

    modifier checkEpoch() {
        require(now >= nextEpochPoint(), "Treasury: not opened yet");

        _;

        epoch = epoch.add(1);
        epochSupplyContractionLeft = (getDibsPrice() > dibsPriceCeiling) ? 0 : getDibsCirculatingSupply().mul(maxSupplyContractionPercent).div(10000);
    }

    modifier checkOperator() {
        require(
            IBasisAsset(dibs).operator() == address(this) &&
                IBasisAsset(dbond).operator() == address(this) &&
                IBasisAsset(dshare).operator() == address(this) &&
                Operator(piggybank).operator() == address(this),
            "Treasury: need more permission"
        );

        _;
    }

    modifier notInitialized() {
        require(!initialized, "Treasury: already initialized");

        _;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function isInitialized() public view returns (bool) {
        return initialized;
    }

    // epoch
    function nextEpochPoint() public view returns (uint256) {
        return startTime.add(epoch.mul(PERIOD));
    }

    // oracle
    function getDibsPrice() public view returns (uint256 dibsPrice) {
        try IOracle(dibsOracle).consult(dibs, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult DIBS price from the oracle");
        }
    }

    function getDibsUpdatedPrice() public view returns (uint256 _dibsPrice) {
        try IOracle(dibsOracle).twap(dibs, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult DIBS price from the oracle");
        }
    }

    // budget
    function getReserve() public view returns (uint256) {
        return seigniorageSaved;
    }

    function getBurnableDibsLeft() public view returns (uint256 _burnableDibsLeft) {
        uint256 _dibsPrice = getDibsPrice();
        if (_dibsPrice <= dibsPriceOne) {
            uint256 _dibsSupply = getDibsCirculatingSupply();
            uint256 _bondMaxSupply = _dibsSupply.mul(maxDebtRatioPercent).div(10000);
            uint256 _bondSupply = IERC20(dbond).totalSupply();
            if (_bondMaxSupply > _bondSupply) {
                uint256 _maxMintableBond = _bondMaxSupply.sub(_bondSupply);
                uint256 _maxBurnableDibs = _maxMintableBond.mul(_dibsPrice).div(1e15);
                _burnableDibsLeft = Math.min(epochSupplyContractionLeft, _maxBurnableDibs);
            }
        }
    }

    function getRedeemableBonds() public view returns (uint256 _redeemableBonds) {
        uint256 _dibsPrice = getDibsPrice();
        if (_dibsPrice > dibsPriceCeiling) {
            uint256 _totalDibs = IERC20(dibs).balanceOf(address(this));
            uint256 _rate = getBondPremiumRate();
            if (_rate > 0) {
                _redeemableBonds = _totalDibs.mul(1e15).div(_rate);
            }
        }
    }

    function getBondDiscountRate() public view returns (uint256 _rate) {
        uint256 _dibsPrice = getDibsPrice();
        if (_dibsPrice <= dibsPriceOne) {
            if (discountPercent == 0) {
                // no discount
                _rate = dibsPriceOne;
            } else {
                uint256 _bondAmount = dibsPriceOne.mul(1e18).div(_dibsPrice); // to burn 1 DIBS
                uint256 _discountAmount = _bondAmount.sub(dibsPriceOne).mul(discountPercent).div(10000);
                _rate = dibsPriceOne.add(_discountAmount);
                if (maxDiscountRate > 0 && _rate > maxDiscountRate) {
                    _rate = maxDiscountRate;
                }
            }
        }
    }

    function getBondPremiumRate() public view returns (uint256 _rate) {
        uint256 _dibsPrice = getDibsPrice();
        if (_dibsPrice > dibsPriceCeiling) {
            uint256 _dibsPricePremiumThreshold = dibsPriceOne.mul(premiumThreshold).div(100);
            if (_dibsPrice >= _dibsPricePremiumThreshold) {
                //Price > 1.10
                uint256 _premiumAmount = _dibsPrice.sub(dibsPriceOne).mul(premiumPercent).div(10000);
                _rate = dibsPriceOne.add(_premiumAmount);
                if (maxPremiumRate > 0 && _rate > maxPremiumRate) {
                    _rate = maxPremiumRate;
                }
            } else {
                // no premium bonus
                _rate = dibsPriceOne;
            }
        }
    }

    /* ========== GOVERNANCE ========== */

    function initialize(
        address _dibs,
        address _dbond,
        address _dshare,
        address _dibsOracle,
        address _piggybank,
        uint256 _startTime
    ) public notInitialized {
        dibs = _dibs;
        dbond = _dbond;
        dshare = _dshare;
        dibsOracle = _dibsOracle;
        piggybank = _piggybank;
        startTime = _startTime;

        dibsPriceOne = 10**15; // This is to allow a PEG of 1,000 DIBS per BNB
        dibsPriceCeiling = dibsPriceOne.mul(101).div(100);

        // Dynamic max expansion percent
        supplyTiers = [0 ether, 500_000 ether, 2_000_000 ether, 4_000_000 ether, 8_000_000 ether, 20_000_000 ether];
        maxExpansionTiers = [300, 250, 200, 150, 125, 100];

        maxSupplyExpansionPercent = 400; // Upto 4.0% supply for expansion

        bondDepletionFloorPercent = 10000; // 100% of Bond supply for depletion floor
        seigniorageExpansionFloorPercent = 3500; // At least 35% of expansion reserved for piggybank
        maxSupplyContractionPercent = 300; // Upto 3.0% supply for contraction (to burn DIBS and mint tBOND)
        maxDebtRatioPercent = 4500; // Upto 45% supply of tBOND to purchase

        premiumThreshold = 110;
        premiumPercent = 7000;

        // First 28 epochs with 3% expansion
        bootstrapEpochs = 0;
        bootstrapSupplyExpansionPercent = 300;

        // set seigniorageSaved to it's balance
        seigniorageSaved = IERC20(dibs).balanceOf(address(this));

        initialized = true;
        operator = msg.sender;
        emit Initialized(msg.sender, block.number);
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function setPiggybank(address _piggybank) external onlyOperator {
        piggybank = _piggybank;
    }

    function setDibsOracle(address _dibsOracle) external onlyOperator {
        dibsOracle = _dibsOracle;
    }

    function setDibsPriceCeiling(uint256 _dibsPriceCeiling) external onlyOperator {
        require(_dibsPriceCeiling >= dibsPriceOne && _dibsPriceCeiling <= dibsPriceOne.mul(120).div(100), "out of range"); // [$1.0, $1.2]
        dibsPriceCeiling = _dibsPriceCeiling;
    }

    function setMaxSupplyExpansionPercents(uint256 _maxSupplyExpansionPercent) external onlyOperator {
        require(_maxSupplyExpansionPercent >= 10 && _maxSupplyExpansionPercent <= 1000, "_maxSupplyExpansionPercent: out of range"); // [0.1%, 10%]
        maxSupplyExpansionPercent = _maxSupplyExpansionPercent;
    }

    function setSupplyTiersEntry(uint8 _index, uint256 _value) external onlyOperator returns (bool) {
        require(_index >= 0, "Index has to be higher than 0");
        require(_index < supplyTiers.length, "Index has to be lower than count of tiers");
        if (_index > 0) {
            require(_value > supplyTiers[_index - 1]);
        }
        if (_index < supplyTiers.length - 1) {
            require(_value < supplyTiers[_index + 1]);
        }
        supplyTiers[_index] = _value;
        return true;
    }

    function setMaxExpansionTiersEntry(uint8 _index, uint256 _value) external onlyOperator returns (bool) {
        require(_index >= 0, "Index has to be higher than 0");
        require(_index < maxExpansionTiers.length, "Index has to be lower than count of tiers");
        require(_value >= 10 && _value <= 1000, "_value: out of range"); // [0.1%, 10%]
        maxExpansionTiers[_index] = _value;
        return true;
    }

    function setBondDepletionFloorPercent(uint256 _bondDepletionFloorPercent) external onlyOperator {
        require(_bondDepletionFloorPercent >= 500 && _bondDepletionFloorPercent <= 10000, "out of range"); // [5%, 100%]
        bondDepletionFloorPercent = _bondDepletionFloorPercent;
    }

    function setMaxSupplyContractionPercent(uint256 _maxSupplyContractionPercent) external onlyOperator {
        require(_maxSupplyContractionPercent >= 100 && _maxSupplyContractionPercent <= 1500, "out of range"); // [0.1%, 15%]
        maxSupplyContractionPercent = _maxSupplyContractionPercent;
    }

    function setMaxDebtRatioPercent(uint256 _maxDebtRatioPercent) external onlyOperator {
        require(_maxDebtRatioPercent >= 1000 && _maxDebtRatioPercent <= 10000, "out of range"); // [10%, 100%]
        maxDebtRatioPercent = _maxDebtRatioPercent;
    }

    function setBootstrap(uint256 _bootstrapEpochs, uint256 _bootstrapSupplyExpansionPercent) external onlyOperator {
        require(_bootstrapEpochs <= 120, "_bootstrapEpochs: out of range"); // <= 1 month
        require(_bootstrapSupplyExpansionPercent >= 100 && _bootstrapSupplyExpansionPercent <= 1000, "_bootstrapSupplyExpansionPercent: out of range"); // [1%, 10%]
        bootstrapEpochs = _bootstrapEpochs;
        bootstrapSupplyExpansionPercent = _bootstrapSupplyExpansionPercent;
    }

    function setExtraFunds(
        address _daoFund,
        uint256 _daoFundSharedPercent,
        address _devFund,
        uint256 _devFundSharedPercent
    ) external onlyOperator {
        require(_daoFund != address(0), "zero");
        require(_daoFundSharedPercent <= 3000, "out of range"); // <= 30%
        require(_devFund != address(0), "zero");
        require(_devFundSharedPercent <= 1000, "out of range"); // <= 10%
        daoFund = _daoFund;
        daoFundSharedPercent = _daoFundSharedPercent;
        devFund = _devFund;
        devFundSharedPercent = _devFundSharedPercent;
    }

    function setMaxDiscountRate(uint256 _maxDiscountRate) external onlyOperator {
        maxDiscountRate = _maxDiscountRate;
    }

    function setMaxPremiumRate(uint256 _maxPremiumRate) external onlyOperator {
        maxPremiumRate = _maxPremiumRate;
    }

    function setDiscountPercent(uint256 _discountPercent) external onlyOperator {
        require(_discountPercent <= 20000, "_discountPercent is over 200%");
        discountPercent = _discountPercent;
    }

    function setPremiumThreshold(uint256 _premiumThreshold) external onlyOperator {
        require(_premiumThreshold >= dibsPriceCeiling, "_premiumThreshold exceeds dibsPriceCeiling");
        require(_premiumThreshold <= 150, "_premiumThreshold is higher than 1.5");
        premiumThreshold = _premiumThreshold;
    }

    function setPremiumPercent(uint256 _premiumPercent) external onlyOperator {
        require(_premiumPercent <= 20000, "_premiumPercent is over 200%");
        premiumPercent = _premiumPercent;
    }

    function setMintingFactorForPayingDebt(uint256 _mintingFactorForPayingDebt) external onlyOperator {
        require(_mintingFactorForPayingDebt >= 10000 && _mintingFactorForPayingDebt <= 20000, "_mintingFactorForPayingDebt: out of range"); // [100%, 200%]
        mintingFactorForPayingDebt = _mintingFactorForPayingDebt;
    }

    /* ========== MUTABLE FUNCTIONS ========== */

    function _updateDibsPrice() internal {
        try IOracle(dibsOracle).update() {} catch {}
    }

    function getDibsCirculatingSupply() public view returns (uint256) {
        IERC20 dibsErc20 = IERC20(dibs);
        uint256 totalSupply = dibsErc20.totalSupply();
        uint256 balanceExcluded = 0;
        for (uint8 entryId = 0; entryId < excludedFromTotalSupply.length; ++entryId) {
            balanceExcluded = balanceExcluded.add(dibsErc20.balanceOf(excludedFromTotalSupply[entryId]));
        }
        return totalSupply.sub(balanceExcluded);
    }

    function buyBonds(uint256 _dibsAmount, uint256 targetPrice) external onlyOneBlock checkCondition checkOperator {
        require(_dibsAmount > 0, "Treasury: cannot purchase bonds with zero amount");

        uint256 dibsPrice = getDibsPrice();
        require(dibsPrice == targetPrice, "Treasury: DIBS price moved");
        require(
            dibsPrice < dibsPriceOne, // price < $1
            "Treasury: dibsPrice not eligible for bond purchase"
        );

        require(_dibsAmount <= epochSupplyContractionLeft, "Treasury: not enough bond left to purchase");

        uint256 _rate = getBondDiscountRate();
        require(_rate > 0, "Treasury: invalid bond rate");

        uint256 _bondAmount = _dibsAmount.mul(_rate).div(1e15);
        uint256 dibsSupply = getDibsCirculatingSupply();
        uint256 newBondSupply = IERC20(dbond).totalSupply().add(_bondAmount);
        require(newBondSupply <= dibsSupply.mul(maxDebtRatioPercent).div(10000), "over max debt ratio");

        IBasisAsset(dibs).burnFrom(msg.sender, _dibsAmount);
        IBasisAsset(dbond).mint(msg.sender, _bondAmount);

        epochSupplyContractionLeft = epochSupplyContractionLeft.sub(_dibsAmount);
        _updateDibsPrice();

        emit BoughtBonds(msg.sender, _dibsAmount, _bondAmount);
    }

    function redeemBonds(uint256 _bondAmount, uint256 targetPrice) external onlyOneBlock checkCondition checkOperator {
        require(_bondAmount > 0, "Treasury: cannot redeem bonds with zero amount");

        uint256 dibsPrice = getDibsPrice();
        require(dibsPrice == targetPrice, "Treasury: DIBS price moved");
        require(
            dibsPrice > dibsPriceCeiling, // price > $1.01
            "Treasury: dibsPrice not eligible for bond purchase"
        );

        uint256 _rate = getBondPremiumRate();
        require(_rate > 0, "Treasury: invalid bond rate");

        uint256 _dibsAmount = _bondAmount.mul(_rate).div(1e15);
        require(IERC20(dibs).balanceOf(address(this)) >= _dibsAmount, "Treasury: treasury has no more budget");

        seigniorageSaved = seigniorageSaved.sub(Math.min(seigniorageSaved, _dibsAmount));

        IBasisAsset(dbond).burnFrom(msg.sender, _bondAmount);
        IERC20(dibs).safeTransfer(msg.sender, _dibsAmount);

        _updateDibsPrice();

        emit RedeemedBonds(msg.sender, _dibsAmount, _bondAmount);
    }

    function _sendToPiggybank(uint256 _amount) internal {
        IBasisAsset(dibs).mint(address(this), _amount);

        uint256 _daoFundSharedAmount = 0;
        if (daoFundSharedPercent > 0) {
            _daoFundSharedAmount = _amount.mul(daoFundSharedPercent).div(10000);
            IERC20(dibs).transfer(daoFund, _daoFundSharedAmount);
            emit DaoFundFunded(now, _daoFundSharedAmount);
        }

        uint256 _devFundSharedAmount = 0;
        if (devFundSharedPercent > 0) {
            _devFundSharedAmount = _amount.mul(devFundSharedPercent).div(10000);
            IERC20(dibs).transfer(devFund, _devFundSharedAmount);
            emit DevFundFunded(now, _devFundSharedAmount);
        }

        _amount = _amount.sub(_daoFundSharedAmount).sub(_devFundSharedAmount);

        IERC20(dibs).safeApprove(piggybank, 0);
        IERC20(dibs).safeApprove(piggybank, _amount);
        IPiggybank(piggybank).allocateSeigniorage(_amount);
        emit PiggybankFunded(now, _amount);
    }

    function _calculateMaxSupplyExpansionPercent(uint256 _dibsSupply) internal returns (uint256) {
        for (uint8 tierId = uint8(supplyTiers.length - 1); tierId >= 0; --tierId) {
            if (_dibsSupply >= supplyTiers[tierId]) {
                maxSupplyExpansionPercent = maxExpansionTiers[tierId];
                break;
            }
        }
        return maxSupplyExpansionPercent;
    }

    function allocateSeigniorage() external onlyOneBlock checkCondition checkEpoch checkOperator {
        _updateDibsPrice();
        previousEpochDibsPrice = getDibsPrice();
        uint256 dibsSupply = getDibsCirculatingSupply().sub(seigniorageSaved);
        if (epoch < bootstrapEpochs) {
            // 28 first epochs with 3% expansion
            _sendToPiggybank(dibsSupply.mul(bootstrapSupplyExpansionPercent).div(10000));
        } else {
            if (previousEpochDibsPrice > dibsPriceCeiling) {
                // Expansion ($DIBS Price > 1 $BNB): there is some seigniorage to be allocated
                uint256 bondSupply = IERC20(dbond).totalSupply();
                uint256 _percentage = previousEpochDibsPrice.sub(dibsPriceOne);
                uint256 _savedForBond;
                uint256 _savedForPiggybank;
                uint256 _mse = _calculateMaxSupplyExpansionPercent(dibsSupply).mul(1e14);
                if (_percentage > _mse) {
                    _percentage = _mse;
                }
                if (seigniorageSaved >= bondSupply.mul(bondDepletionFloorPercent).div(10000)) {
                    // saved enough to pay debt, mint as usual rate
                    _savedForPiggybank = dibsSupply.mul(_percentage).div(1e18);
                } else {
                    // have not saved enough to pay debt, mint more
                    uint256 _seigniorage = dibsSupply.mul(_percentage).div(1e18);
                    _savedForPiggybank = _seigniorage.mul(seigniorageExpansionFloorPercent).div(10000);
                    _savedForBond = _seigniorage.sub(_savedForPiggybank);
                    if (mintingFactorForPayingDebt > 0) {
                        _savedForBond = _savedForBond.mul(mintingFactorForPayingDebt).div(10000);
                    }
                }
                if (_savedForPiggybank > 0) {
                    _sendToPiggybank(_savedForPiggybank);
                }
                if (_savedForBond > 0) {
                    seigniorageSaved = seigniorageSaved.add(_savedForBond);
                    IBasisAsset(dibs).mint(address(this), _savedForBond);
                    emit TreasuryFunded(now, _savedForBond);
                }
            }
        }
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        // do not allow to drain core tokens
        require(address(_token) != address(dibs), "dibs");
        require(address(_token) != address(dbond), "bond");
        require(address(_token) != address(dshare), "share");
        _token.safeTransfer(_to, _amount);
    }

    function piggybankSetOperator(address _operator) external onlyOperator {
        IPiggybank(piggybank).setOperator(_operator);
    }

    function piggybankSetLockUp(uint256 _withdrawLockupEpochs, uint256 _rewardLockupEpochs) external onlyOperator {
        IPiggybank(piggybank).setLockUp(_withdrawLockupEpochs, _rewardLockupEpochs);
    }

    function piggybankAllocateSeigniorage(uint256 amount) external onlyOperator {
        IPiggybank(piggybank).allocateSeigniorage(amount);
    }

    function piggybankGovernanceRecoverUnsupported(
        address _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        IPiggybank(piggybank).governanceRecoverUnsupported(_token, _amount, _to);
    }
}
