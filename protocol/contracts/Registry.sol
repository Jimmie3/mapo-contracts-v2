// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {IRelay} from "./interfaces/IRelay.sol";
import {Utils} from "./libs/Utils.sol";

import {IRegistry, ChainType} from "./interfaces/IRegistry.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BaseImplementation} from "@mapprotocol/common-contracts/contracts/base/BaseImplementation.sol";

contract Registry is BaseImplementation, IRegistry {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.BytesSet;

    uint256 constant MAX_RATE_UNIT = 1_000_000;         // unit is 0.01 bps

    struct FeeRate {
        uint256 lowest;
        uint256 highest;        // 0 will be no highest limit
        uint256 rate;           // unit is parts per million
    }

    struct BaseFee {
        uint256 withSwap;
        uint256 noSwap;
    }

    struct TokenInfo {
        uint8 decimals;
        bool mintable;
        bytes token;
    }


    struct Token {
        uint96 id;
        address tokenAddress;
        // chain_id => decimals
        mapping(uint256 => uint8) decimals;
        // chain_id => token
        mapping(uint256 => bytes) mappingList;
    }

    struct ChainInfo {
        ChainType chainType;
        address gasToken;           // the chain native token address mapped on relay chain
        address baseFeeToken;       // the base fee token address mapped on relay chain
                                    // by default, it will be the chain native token address on relay chain
                                    // like BTC for Bitcoin, ETH for Ethereum, Base, etc.
                                    // but the protocol might not support the chain native token bridge, like Kaia, it will be USDT.
                                    // it will be used when not specify bridge token, such as migration
        bytes router;
        string name;
        // EnumerableSet.BytesSet tokens;
    }

    uint256 public immutable selfChainId = block.chainid;

    IRelay public relay;
    EnumerableSet.UintSet private chainList;
    mapping(uint256 => string) private chainToNames;
    mapping(string => uint256) private nameToChain;
    mapping(uint256 => ChainInfo) private chainInfos;

    // hash(chainId, tokenAddress)
    mapping(bytes32 tokenId => TokenInfo) private tokenInfos;

    mapping(bytes32 tokenId => address) private tokens23;

    // Source chain to Relay chain address
    // [chain_id => [source_token => map_token]]
    mapping(uint256 => mapping(bytes => address)) public tokenMappingList;

    mapping(address => Token) public tokenList;

    mapping(uint256 => address) public mapTokenIdToAddress;

    mapping(uint256 => mapping(bytes => string)) public tokenAddressToNickname;

    mapping(uint256 => mapping(string => bytes)) public tokenNicknameToAddress;

    address private baseFeeReceiver;

    // hash(fromChain,caller,token) => toChain => rate;
    mapping(bytes32 => mapping(uint256 => uint256)) public toChainFeeList;

    // hash(fromChain,caller,token) => rate;
    mapping(bytes32 => uint256) public fromChainFeeList;



    modifier checkAddress(address _address) {
        if (_address == address(0)) revert zero_address();
        _;
    }

    event SetRelay(address _relay);
    event SetBaseFeeReceiver(address _baseFeeReceiver);
    event RegisterToken(uint96 indexed id, address indexed _token);
    event MapToken(address indexed _token, uint256 indexed _fromChain, bytes _fromToken, uint8 _decimals);
    event DeregisterChain(uint256 chain);
    event RegisterChain(uint256 _chain, ChainType _chainType, bytes _router, string _chainName, address _gasToken);
    event UnmapToken(uint256 indexed _fromChain, bytes _fromToken);
    event SetTokenTicker(uint256 _chain, bytes _token, string _nickname);
    event SetBaseFee(address indexed _token, uint256 indexed _toChain, uint256 _withSwap, uint256 _noSwap);
    event SetMaxAmountPerMigrates(uint256 _chain, uint256 _maxAmount);
    event SetToChainTokenFee(
        address indexed _token, uint256 indexed _toChain, uint256 _lowest, uint256 _highest, uint256 _rate
    );
    event SetFromChainTokenFee(
        address indexed _token, uint256 indexed _toChain, uint256 _lowest, uint256 _highest, uint256 _rate
    );

    event SetToChainWhitelistFeeRate(
        address _token, uint256 _fromChain, uint256 _toChain, bytes _caller, uint256 _rate, bool _isWhitelist
    );

    event SetFromChainWhitelistFeeRate(
        address _token, uint256 _fromChain, bytes _caller, uint256 _rate, bool _isWhitelist
    );

    event SetFeeRate(bytes32 key, uint256 highest, uint256 lowest, uint256 rate);

    error invalid_relay_token();
    error invalid_relay_router();
    error invalid_from_token();
    error relay_chain();
    error token_not_registered();
    error invalid_highest_and_lowest();
    error invalid_proportion_value();
    error token_not_matched();
    error unmap_token_first();
    error zero_address();
    error register_chain_first();


    function initialize(address _defaultAdmin) public initializer {
        __BaseImplementation_init(_defaultAdmin);
    }

    function setRelay(address _relay) external restricted checkAddress(_relay) {
        relay = IRelay(_relay);
        emit SetRelay(_relay);
    }

    function registerChain(
        uint256 _chain,
        ChainType _chainType,
        bytes memory _router,
        address _gasToken,
        address _baseToken,
        string memory _chainName
    ) external restricted {
        ChainInfo storage chainInfo = chainInfos[_chain];
        chainInfo.router = _router;

        // check gasToken and baseToken
        if (_chainType != ChainType.CONTRACT) {
            require(_gasToken == _baseToken);
        }
        chainInfo.gasToken = _gasToken;
        chainInfo.baseFeeToken = _baseToken;

        string memory oldName = chainToNames[_chain];
        delete nameToChain[oldName];

        chainInfo.name = _chainName;
        chainInfo.chainType = _chainType;

        nameToChain[_chainName] = _chain;
        chainList.add(_chain);

        emit RegisterChain(_chain, _chainType, _router, _chainName, _gasToken);
    }

    function deregisterChain(uint256 _chain) external restricted {
        ChainInfo storage chainInfo = chainInfos[_chain];
        // if (chainInfo.tokens.values().length != 0) revert unmap_token_first();
        delete nameToChain[chainInfo.name];
        delete chainInfos[_chain];
        chainList.remove(_chain);
        emit DeregisterChain(_chain);
    }

    function registerToken(uint96 _id, address _token)
        external
        restricted
        checkAddress(_token)
    {
        Token storage token = tokenList[_token];
        // address tokenAddress = IVaultToken(_vaultToken).asset();
        // if (_token != tokenAddress) revert invalid_relay_token();
        uint256 chainId = selfChainId;
        token.id = _id;
        token.tokenAddress = _token;
        // token.vaultToken = _vaultToken;
        mapTokenIdToAddress[_id] = _token;
        bytes memory tokenBytes = Utils.toBytes(_token);
        token.mappingList[chainId] = tokenBytes;
        token.decimals[chainId] = IERC20Metadata(_token).decimals();
        // ChainInfo storage chainInfo = chainInfos[chainId];
        // chainInfo.tokens.add(tokenBytes);
        emit RegisterToken(_id, _token);
    }

    function mapToken(address _token, uint256 _fromChain, bytes memory _fromToken, uint8 _decimals)
        external
        restricted
        checkAddress(_token)
    {
        if (Utils.bytesEq(_fromToken, bytes(""))) revert invalid_from_token();
        Token storage token = tokenList[_token];
        if (token.tokenAddress == address(0)) revert invalid_relay_token();
        token.decimals[_fromChain] = _decimals;
        token.mappingList[_fromChain] = _fromToken;
        tokenMappingList[_fromChain][_fromToken] = _token;

        if (!chainList.contains(_fromChain)) revert register_chain_first();
        // ChainInfo storage chainInfo = chainInfos[_fromChain];
        // chainInfo.tokens.add(_fromToken);
        emit MapToken(_token, _fromChain, _fromToken, _decimals);
    }

    function unmapToken(uint256 _fromChain, bytes memory _fromToken) external restricted {
        if (!Utils.bytesEq(_fromToken, bytes(""))) revert invalid_from_token();
        if (_fromChain == selfChainId) revert relay_chain();
        address relayToken = tokenMappingList[_fromChain][_fromToken];
        if (relayToken != address(0)) revert token_not_registered();
        Token storage token = tokenList[relayToken];
        if (token.tokenAddress != address(0)) {
            if (Utils.bytesEq(_fromToken, token.mappingList[_fromChain])) {
                delete token.decimals[_fromChain];
                delete token.mappingList[_fromChain];
                // ChainInfo storage chainInfo = chainInfos[_fromChain];
                // chainInfo.tokens.remove(_fromToken);
            }
        }
        delete tokenMappingList[_fromChain][_fromToken];

        emit UnmapToken(_fromChain, _fromToken);
    }

    function setTokenTicker(uint256 _chain, bytes memory _token, string memory _nickname) external restricted {
        string memory oldNickname = tokenAddressToNickname[_chain][_token];
        delete tokenNicknameToAddress[_chain][oldNickname];
        tokenAddressToNickname[_chain][_token] = _nickname;
        tokenNicknameToAddress[_chain][_nickname] = _token;

        emit SetTokenTicker(_chain, _token, _nickname);
    }

    function setBaseFeeReceiver(address _baseFeeReceiver) external restricted checkAddress(_baseFeeReceiver) {
        baseFeeReceiver = _baseFeeReceiver;
        emit SetBaseFeeReceiver(_baseFeeReceiver);
    }


    // -------------------------------------------------------- view
    // -------------------------------------------
    function getTokenAddressById(uint96 id) external view override returns (address token) {
        token = mapTokenIdToAddress[id];
    }

    function getToChainToken(address _token, uint256 _toChain)
        external
        view
        override
        returns (bytes memory _toChainToken)
    {
        return _getToChainToken(_token, _toChain);
    }

    function getToChainAmount(address _token, uint256 _amount, uint256 _toChain)
        external
        view
        override
        returns (uint256)
    {
        return _getTargetAmount(_token, selfChainId, _toChain, _amount);
    }

    function getRelayChainToken(uint256 _fromChain, bytes memory _fromToken)
        external
        view
        override
        returns (address token)
    {
        return _getRelayChainToken(_fromChain, _fromToken);
    }

    function getRelayChainAmount(bytes memory _fromToken, uint256 _fromChain, uint256 _amount)
        external
        view
        override
        returns (uint256)
    {
        address _token = _getRelayChainToken(_fromChain, _fromToken);
        return _getTargetAmount(_token, _fromChain, selfChainId, _amount);
    }

    function getTargetToken(uint256 _fromChain, uint256 _toChain, bytes memory _fromToken)
        external
        view
        returns (bytes memory toToken, uint8 decimals, uint256 vaultBalance)
    {
        address tokenAddr = _getRelayChainToken(_fromChain, _fromToken);
        (toToken, decimals) = _getTargetToken(_toChain, tokenAddr);
        // vaultBalance = getVaultBalance(tokenAddr, _toChain);
    }

    function getTokenInfo(address _relayToken, uint256 _fromChain)
    external
    view
    override
    returns (bytes memory token, uint8 decimals, bool mintable)
    {

    }

    function _getTargetToken(uint256 _toChain, address _relayToken)
        private
        view
        returns (bytes memory toToken, uint8 decimals)
    {
        Token storage token = tokenList[_relayToken];
        if (token.tokenAddress == address(0)) revert invalid_relay_token();
        toToken = token.mappingList[_toChain];
        decimals = token.decimals[_toChain];
    }

    function getTargetAmount(uint256 _fromChain, uint256 _toChain, bytes memory _fromToken, uint256 _amount)
        external
        view
        returns (uint256 toAmount)
    {
        address tokenAddr = _getRelayChainToken(_fromChain, _fromToken);

        toAmount = _getTargetAmount(tokenAddr, _fromChain, _toChain, _amount);
    }

    function getBaseFeeReceiver() external view returns (address) {
        return baseFeeReceiver;
    }



    function getChains() external view override returns (uint256[] memory) {
        return chainList.values();
    }

    function getChainTokens(uint256 chain) external view override returns (bytes[] memory) {
        // return chainInfos[chain].tokens.values();
    }

    function getChainRouters(uint256 chain) external view override returns (bytes memory) {
        return chainInfos[chain].router;
    }

    function getChainType(uint256 chain) external view override returns (ChainType) {
        return chainInfos[chain].chainType;
    }

    function getChainGasToken(uint256 chain) external view override returns (address) {
        return chainInfos[chain].gasToken;
    }

    function getChainBaseToken(uint256 chain) external view override returns (address) {
        return chainInfos[chain].baseFeeToken;
    }

    function getTokenDecimals(uint256 chain, bytes calldata token) external view override returns (uint256) {
        address relayToken = tokenMappingList[chain][token];
        Token storage t = tokenList[relayToken];
        return t.decimals[chain];
    }

    function getChainName(uint256 chain) external view override returns (string memory) {
        return chainInfos[chain].name;
    }

    function getChainByName(string memory name) external view override returns (uint256) {
        return nameToChain[name];
    }

    function getTokenNickname(uint256 chain, bytes memory token) external view override returns (string memory) {
        return tokenAddressToNickname[chain][token];
    }

    function getTokenAddressByNickname(uint256 chain, string memory nickname)
        external
        view
        override
        returns (bytes memory)
    {
        return tokenNicknameToAddress[chain][nickname];
    }

    // ----------------------------------------------------- view
    // ------------------------------------------------------------

    function _getRelayChainToken(uint256 _fromChain, bytes memory _fromToken) internal view returns (address token) {
        if (_fromChain == selfChainId) {
            token = Utils.fromBytes(_fromToken);
        } else {
            token = tokenMappingList[_fromChain][_fromToken];
        }
        if (token == address(0)) revert token_not_registered();
        // check
        // bytes memory fromToken = tokenList[token].mappingList[_fromChain];
        // if(!Utils.bytesEq(_fromToken, fromToken)) revert token_not_matched();
    }

    function _getToChainToken(address _token, uint256 _toChain) internal view returns (bytes memory token) {
        if (_toChain == selfChainId) {
            token = Utils.toBytes(_token);
        } else {
            token = tokenList[_token].mappingList[_toChain];
        }
    }

    function _getTargetAmount(address _token, uint256 _fromChain, uint256 _toChain, uint256 _amount)
        internal
        view
        returns (uint256)
    {
        if (_toChain == _fromChain) {
            return _amount;
        }
        Token storage token = tokenList[_token];
        if (token.tokenAddress == address(0)) revert invalid_relay_token();

        uint256 decimalsFrom = token.decimals[_fromChain];
        if (decimalsFrom == 0) revert token_not_registered();

        uint256 decimalsTo = token.decimals[_toChain];
        if (decimalsTo == 0) revert token_not_registered();

        if (decimalsFrom == decimalsTo) {
            return _amount;
        }
        return (_amount * (10 ** decimalsTo)) / (10 ** decimalsFrom);
    }


    function _getKey(uint256 _fromChain, bytes memory _caller, address _token) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(_fromChain, _caller, _token));
    }

    function _getTokenId(uint256 _chain, bytes memory _token) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(_chain, _token));
    }
}
