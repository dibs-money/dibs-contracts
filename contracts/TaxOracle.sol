// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TaxOracle is Ownable {
    using SafeMath for uint256;

    IERC20 public dibs;
    IERC20 public wbnb;
    address public pair;

    constructor(
        address _dibs,
        address _wbnb,
        address _pair
    ) public {
        require(_dibs != address(0), "dibs address cannot be 0");
        require(_wbnb != address(0), "wbnb address cannot be 0");
        require(_pair != address(0), "pair address cannot be 0");
        dibs = IERC20(_dibs);
        wbnb = IERC20(_wbnb);
        pair = _pair;
    }

    function consult(address _token, uint256 _amountIn) external view returns (uint144 amountOut) {
        require(_token == address(dibs), "token needs to be dibs");
        uint256 dibsBalance = dibs.balanceOf(pair);
        uint256 wbnbBalance = wbnb.balanceOf(pair);
        return uint144(dibsBalance.mul(_amountIn).div(wbnbBalance));
    }

    function getDibsBalance() external view returns (uint256) {
	return dibs.balanceOf(pair);
    }

    function getWbnbBalance() external view returns (uint256) {
	return wbnb.balanceOf(pair);
    }

    function getPrice() external view returns (uint256) {
        uint256 dibsBalance = dibs.balanceOf(pair);
        uint256 wbnbBalance = wbnb.balanceOf(pair);
        return dibsBalance.mul(1e18).div(wbnbBalance);
    }


    function setDibs(address _dibs) external onlyOwner {
        require(_dibs != address(0), "dibs address cannot be 0");
        dibs = IERC20(_dibs);
    }

    function setWbnb(address _wbnb) external onlyOwner {
        require(_wbnb != address(0), "wbnb address cannot be 0");
        wbnb = IERC20(_wbnb);
    }

    function setPair(address _pair) external onlyOwner {
        require(_pair != address(0), "pair address cannot be 0");
        pair = _pair;
    }
}