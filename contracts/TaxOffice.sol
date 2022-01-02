// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./owner/Operator.sol";
import "./interfaces/ITaxable.sol";

/*

  _____  _ _                                            
 |  __ \(_) |                                           
 | |  | |_| |__  ___   _ __ ___   ___  _ __   ___ _   _ 
 | |  | | | '_ \/ __| | '_ ` _ \ / _ \| '_ \ / _ \ | | |
 | |__| | | |_) \__ \_| | | | | | (_) | | | |  __/ |_| |
 |_____/|_|_.__/|___(_)_| |_| |_|\___/|_| |_|\___|\__, |
                                                   __/ |
    https://dibs.money                            |___/ 

*/
contract TaxOffice is Operator {
    address public dibs;

    constructor(address _dibs) public {
        require(_dibs != address(0), "dibs address cannot be 0");
        dibs = _dibs;
    }

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
        return ITaxable(dibs).excludeAddress(_address);
    }

    function includeAddressInTax(address _address) external onlyOperator returns (bool) {
        return ITaxable(dibs).includeAddress(_address);
    }

    function setTaxableDibsOracle(address _dibsOracle) external onlyOperator {
        ITaxable(dibs).setDibsOracle(_dibsOracle);
    }

    function transferTaxOffice(address _newTaxOffice) external onlyOperator {
        ITaxable(dibs).setTaxOffice(_newTaxOffice);
    }
}
