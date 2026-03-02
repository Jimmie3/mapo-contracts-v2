// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IAffiliateFeeManager {

    struct AffiliateInfo {
        uint16 id;
        uint16 baseRate;
        uint16 maxRate;
        address wallet;
        string nickname;
    }
    function getAffiliatesFee(uint256 amount, bytes calldata feeData) external view returns (uint256 totalFee);

    function collectAffiliatesFee(bytes32 orderId, address token, uint256 amount, bytes calldata feeData)
        external
        returns (uint256 totalFee);

    function getInfoById(uint16 _id) external view returns (AffiliateInfo memory info);

    function getInfoByWallet(address _wallet) external view returns (AffiliateInfo memory info);

    function getInfoByNickname(string calldata _nickname) external view returns (AffiliateInfo memory info);

    function getInfoByShortName(string calldata _shortName) external view returns (AffiliateInfo memory info);

    function getShortNameById(uint16 _id) external view returns (string memory shortName);

    function getShortNameByNickname(string calldata _nickname) external view returns (string memory shortName);

    function getShortNameByWallet(address _wallet) external view returns (string memory shortName);
}
