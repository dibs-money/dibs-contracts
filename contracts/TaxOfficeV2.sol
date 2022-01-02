// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./owner/Operator.sol";
import "./interfaces/ITaxable.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/IERC20.sol";

contract TaxOfficeV2 is Operator {
    using SafeMath for uint256;

    address public dibs = address(0xFd81Ef21EA7CF1dC00e9c6Dd261B4F3BE0341d5c);
    address public weth = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address public uniRouter = address(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    mapping(address => bool) public taxExclusionEnabled;

    function setTaxTiersTwap(uint8 _index, uint256 _value) public onlyOperator returns (bool) {
        return ITaxable(dibs).setTaxTiersTwap(_index, _value);
    }

    function setTaxTiersRate(uint8 _index, uint256 _value) public onlyOperator returns (bool) {
        return ITaxable(dibs).setTaxTiersRate(_index, _value);
    }

    function enableAutoCalculateTax() public onlyOperator {
        ITaxable(dibs).enableAutoCalculateTax();
    }

    function disableAutoCalculateTax() public onlyOperator {
        ITaxable(dibs).disableAutoCalculateTax();
    }

    function setTaxRate(uint256 _taxRate) public onlyOperator {
        ITaxable(dibs).setTaxRate(_taxRate);
    }

    function setBurnThreshold(uint256 _burnThreshold) public onlyOperator {
        ITaxable(dibs).setBurnThreshold(_burnThreshold);
    }

    function setTaxCollectorAddress(address _taxCollectorAddress) public onlyOperator {
        ITaxable(dibs).setTaxCollectorAddress(_taxCollectorAddress);
    }

    function excludeAddressFromTax(address _address) external onlyOperator returns (bool) {
        return _excludeAddressFromTax(_address);
    }

    function _excludeAddressFromTax(address _address) private returns (bool) {
        if (!ITaxable(dibs).isAddressExcluded(_address)) {
            return ITaxable(dibs).excludeAddress(_address);
        }
    }

    function includeAddressInTax(address _address) external onlyOperator returns (bool) {
        return _includeAddressInTax(_address);
    }

    function _includeAddressInTax(address _address) private returns (bool) {
        if (ITaxable(dibs).isAddressExcluded(_address)) {
            return ITaxable(dibs).includeAddress(_address);
        }
    }

    function taxRate() external returns (uint256) {
        return ITaxable(dibs).taxRate();
    }

    function addLiquidityTaxFree(
        address token,
        uint256 amtDibs,
        uint256 amtToken,
        uint256 amtDibsMin,
        uint256 amtTokenMin
    )
        external
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(amtDibs != 0 && amtToken != 0, "amounts can't be 0");
        _excludeAddressFromTax(msg.sender);

        IERC20(dibs).transferFrom(msg.sender, address(this), amtDibs);
        IERC20(token).transferFrom(msg.sender, address(this), amtToken);
        _approveTokenIfNeeded(dibs, uniRouter);
        _approveTokenIfNeeded(token, uniRouter);

        _includeAddressInTax(msg.sender);

        uint256 resultAmtDibs;
        uint256 resultAmtToken;
        uint256 liquidity;
        (resultAmtDibs, resultAmtToken, liquidity) = IUniswapV2Router(uniRouter).addLiquidity(
            dibs,
            token,
            amtDibs,
            amtToken,
            amtDibsMin,
            amtTokenMin,
            msg.sender,
            block.timestamp
        );

        if (amtDibs.sub(resultAmtDibs) > 0) {
            IERC20(dibs).transfer(msg.sender, amtDibs.sub(resultAmtDibs));
        }
        if (amtToken.sub(resultAmtToken) > 0) {
            IERC20(token).transfer(msg.sender, amtToken.sub(resultAmtToken));
        }
        return (resultAmtDibs, resultAmtToken, liquidity);
    }

    function addLiquidityETHTaxFree(
        uint256 amtDibs,
        uint256 amtDibsMin,
        uint256 amtEthMin
    )
        external
        payable
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(amtDibs != 0 && msg.value != 0, "amounts can't be 0");
        _excludeAddressFromTax(msg.sender);

        IERC20(dibs).transferFrom(msg.sender, address(this), amtDibs);
        _approveTokenIfNeeded(dibs, uniRouter);

        _includeAddressInTax(msg.sender);

        uint256 resultAmtDibs;
        uint256 resultAmtEth;
        uint256 liquidity;
        (resultAmtDibs, resultAmtEth, liquidity) = IUniswapV2Router(uniRouter).addLiquidityETH{value: msg.value}(
            dibs,
            amtDibs,
            amtDibsMin,
            amtEthMin,
            msg.sender,
            block.timestamp
        );

        if (amtDibs.sub(resultAmtDibs) > 0) {
            IERC20(dibs).transfer(msg.sender, amtDibs.sub(resultAmtDibs));
        }
        return (resultAmtDibs, resultAmtEth, liquidity);
    }

    function setTaxableDibsOracle(address _dibsOracle) external onlyOperator {
        ITaxable(dibs).setDibsOracle(_dibsOracle);
    }

    function transferTaxOffice(address _newTaxOffice) external onlyOperator {
        ITaxable(dibs).setTaxOffice(_newTaxOffice);
    }

    function taxFreeTransferFrom(
        address _sender,
        address _recipient,
        uint256 _amt
    ) external {
        require(taxExclusionEnabled[msg.sender], "Address not approved for tax free transfers");
        _excludeAddressFromTax(_sender);
        IERC20(dibs).transferFrom(_sender, _recipient, _amt);
        _includeAddressInTax(_sender);
    }

    function setTaxExclusionForAddress(address _address, bool _excluded) external onlyOperator {
        taxExclusionEnabled[_address] = _excluded;
    }

    function _approveTokenIfNeeded(address _token, address _router) private {
        if (IERC20(_token).allowance(address(this), _router) == 0) {
            IERC20(_token).approve(_router, type(uint256).max);
        }
    }
}
