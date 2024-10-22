// L2TokenBridge.spec

using Auxiliar as aux;
using MessengerMock as l2messenger;
using GemMock as gem;

methods {
    // storage variables
    function wards(address) external returns (uint256) envfree;
    function l1ToL2Token(address) external returns (address) envfree;
    function maxWithdraws(address) external returns (uint256) envfree;
    function isOpen() external returns (uint256) envfree;
    // immutables
    function otherBridge() external returns (address) envfree;
    function messenger() external returns (address) envfree;
    //
    function gem.wards(address) external returns (uint256) envfree;
    function gem.allowance(address,address) external returns (uint256) envfree;
    function gem.totalSupply() external returns (uint256) envfree;
    function gem.balanceOf(address) external returns (uint256) envfree;
    function aux.getBridgeMessageHash(address,address,address,address,uint256,bytes) external returns (bytes32) envfree;
    function l2messenger.xDomainMessageSender() external returns (address) envfree;
    function l2messenger.lastTarget() external returns (address) envfree;
    function l2messenger.lastMessageHash() external returns (bytes32) envfree;
    function l2messenger.lastMinGasLimit() external returns (uint32) envfree;
    //
    function _.burn(address,uint256) external => DISPATCHER(true);
    function _.mint(address,uint256) external => DISPATCHER(true);
}

// Verify that each storage layout is only modified in the corresponding functions
rule storageAffected(method f) filtered { f -> f.selector != sig:upgradeToAndCall(address, bytes).selector } {
    env e;

    address anyAddr;

    mathint wardsBefore = wards(anyAddr);
    address l1ToL2TokenBefore = l1ToL2Token(anyAddr);
    mathint maxWithdrawsBefore = maxWithdraws(anyAddr);
    mathint isOpenBefore = isOpen();

    calldataarg args;
    f(e, args);

    mathint wardsAfter = wards(anyAddr);
    address l1ToL2TokenAfter = l1ToL2Token(anyAddr);
    mathint maxWithdrawsAfter = maxWithdraws(anyAddr);
    mathint isOpenAfter = isOpen();

    assert wardsAfter != wardsBefore => f.selector == sig:rely(address).selector || f.selector == sig:deny(address).selector || f.selector == sig:initialize().selector, "Assert 1";
    assert l1ToL2TokenAfter != l1ToL2TokenBefore => f.selector == sig:registerToken(address,address).selector, "Assert 2";
    assert maxWithdrawsAfter != maxWithdrawsBefore => f.selector == sig:setMaxWithdraw(address,uint256).selector, "Assert 3";
    assert isOpenAfter != isOpenBefore => f.selector == sig:close().selector || f.selector == sig:initialize().selector, "Assert 4";
}

// Verify correct storage changes for non reverting rely
rule rely(address usr) {
    env e;

    address other;
    require other != usr;

    mathint wardsOtherBefore = wards(other);

    rely(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);

    assert wardsUsrAfter == 1, "Assert 1";
    assert wardsOtherAfter == wardsOtherBefore, "Assert 2";
}

// Verify revert rules on rely
rule rely_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    rely@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting deny
rule deny(address usr) {
    env e;

    address other;
    require other != usr;

    mathint wardsOtherBefore = wards(other);

    deny(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);

    assert wardsUsrAfter == 0, "Assert 1";
    assert wardsOtherAfter == wardsOtherBefore, "Assert 2";
}

// Verify revert rules on deny
rule deny_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    deny@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting close
rule close() {
    env e;

    close(e);

    mathint isOpenAfter = isOpen();

    assert isOpenAfter == 0, "Assert 1";
}

// Verify revert rules on close
rule close_revert() {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    close@withrevert(e);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting registerToken
rule registerToken(address l1Token, address l2Token) {
    env e;

    registerToken(e, l1Token, l2Token);

    address l1ToL2TokenAfter = l1ToL2Token(l1Token);

    assert l1ToL2TokenAfter == l2Token, "Assert 1";
}

// Verify revert rules on registerToken
rule registerToken_revert(address l1Token, address l2Token) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    registerToken@withrevert(e, l1Token, l2Token);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting setMaxWithdraw
rule setMaxWithdraw(address l2Token, uint256 maxWithdraw) {
    env e;

    setMaxWithdraw(e, l2Token, maxWithdraw);

    mathint maxWithdrawsAfter = maxWithdraws(l2Token);

    assert maxWithdrawsAfter == maxWithdraw, "Assert 1";
}

// Verify revert rules on setMaxWithdraw
rule setMaxWithdraw_revert(address l2Token, uint256 maxWithdraw) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    setMaxWithdraw@withrevert(e, l2Token, maxWithdraw);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting bridgeERC20
rule bridgeERC20(address _localToken, address _remoteToken, uint256 _amount, uint32 _minGasLimit, bytes _extraData) {
    env e;

    require _localToken == gem;

    address otherBridge = otherBridge();

    bytes32 message = aux.getBridgeMessageHash(_localToken, _remoteToken, e.msg.sender, e.msg.sender, _amount, _extraData);
    mathint localTokenTotalSupplyBefore = gem.totalSupply();
    mathint localTokenBalanceOfSenderBefore = gem.balanceOf(e.msg.sender);
    // ERC20 assumption
    require localTokenTotalSupplyBefore >= localTokenBalanceOfSenderBefore;

    bridgeERC20(e, _localToken, _remoteToken, _amount, _minGasLimit, _extraData);

    address lastTargetAfter = l2messenger.lastTarget();
    bytes32 lastMessageHashAfter = l2messenger.lastMessageHash();
    uint32  lastMinGasLimitAfter = l2messenger.lastMinGasLimit();
    mathint localTokenTotalSupplyAfter = gem.totalSupply();
    mathint localTokenBalanceOfSenderAfter = gem.balanceOf(e.msg.sender);

    assert lastTargetAfter == otherBridge, "Assert 1";
    assert lastMessageHashAfter == message, "Assert 2";
    assert lastMinGasLimitAfter == _minGasLimit, "Assert 3";
    assert localTokenTotalSupplyAfter == localTokenTotalSupplyBefore - _amount, "Assert 4";
    assert localTokenBalanceOfSenderAfter == localTokenBalanceOfSenderBefore - _amount, "Assert 5";
}

// Verify revert rules on bridgeERC20
rule bridgeERC20_revert(address _localToken, address _remoteToken, uint256 _amount, uint32 _minGasLimit, bytes _extraData) {
    env e;

    mathint isOpen = isOpen();
    address l1ToL2TokenRemoteToken = l1ToL2Token(_remoteToken);
    mathint maxWithdrawsLocatOken = maxWithdraws(_localToken);

    mathint localTokenTotalSupply = gem.totalSupply();
    mathint localTokenBalanceOfSender = gem.balanceOf(e.msg.sender);
    // ERC20 assumption
    require localTokenTotalSupply >= localTokenBalanceOfSender;
    // User assumptions
    require localTokenBalanceOfSender >= _amount;
    require gem.allowance(e.msg.sender, currentContract) >= _amount;

    bridgeERC20@withrevert(e, _localToken, _remoteToken, _amount, _minGasLimit, _extraData);

    bool revert1 = e.msg.value > 0;
    bool revert2 = nativeCodesize[e.msg.sender] != 0;
    bool revert3 = isOpen != 1;
    bool revert4 = _localToken == 0 || l1ToL2TokenRemoteToken != _localToken;
    bool revert5 = _amount > maxWithdrawsLocatOken;

    assert lastReverted <=> revert1 || revert2 || revert3 ||
                            revert4 || revert5, "Revert rules failed";
}

// Verify correct storage changes for non reverting bridgeERC20To
rule bridgeERC20To(address _localToken, address _remoteToken, address _to, uint256 _amount, uint32 _minGasLimit, bytes _extraData) {
    env e;

    require _localToken == gem;

    address otherBridge = otherBridge();

    bytes32 message = aux.getBridgeMessageHash(_localToken, _remoteToken, e.msg.sender, _to, _amount, _extraData);
    mathint localTokenTotalSupplyBefore = gem.totalSupply();
    mathint localTokenBalanceOfSenderBefore = gem.balanceOf(e.msg.sender);
    // ERC20 assumption
    require localTokenTotalSupplyBefore >= localTokenBalanceOfSenderBefore;

    bridgeERC20To(e, _localToken, _remoteToken, _to, _amount, _minGasLimit, _extraData);

    address lastTargetAfter = l2messenger.lastTarget();
    bytes32 lastMessageHashAfter = l2messenger.lastMessageHash();
    uint32  lastMinGasLimitAfter = l2messenger.lastMinGasLimit();
    mathint localTokenTotalSupplyAfter = gem.totalSupply();
    mathint localTokenBalanceOfSenderAfter = gem.balanceOf(e.msg.sender);

    assert lastTargetAfter == otherBridge, "Assert 1";
    assert lastMessageHashAfter == message, "Assert 2";
    assert lastMinGasLimitAfter == _minGasLimit, "Assert 3";
    assert localTokenTotalSupplyAfter == localTokenTotalSupplyBefore - _amount, "Assert 4";
    assert localTokenBalanceOfSenderAfter == localTokenBalanceOfSenderBefore - _amount, "Assert 5";
}

// Verify revert rules on bridgeERC20To
rule bridgeERC20To_revert(address _localToken, address _remoteToken, address _to, uint256 _amount, uint32 _minGasLimit, bytes _extraData) {
    env e;

    mathint isOpen = isOpen();
    address l1ToL2TokenRemoteToken = l1ToL2Token(_remoteToken);
    mathint maxWithdrawsLocatOken = maxWithdraws(_localToken);

    mathint localTokenTotalSupply = gem.totalSupply();
    mathint localTokenBalanceOfSender = gem.balanceOf(e.msg.sender);
    // ERC20 assumption
    require localTokenTotalSupply >= localTokenBalanceOfSender;
    // User assumptions
    require localTokenBalanceOfSender >= _amount;
    require gem.allowance(e.msg.sender, currentContract) >= _amount;

    bridgeERC20To@withrevert(e, _localToken, _remoteToken, _to, _amount, _minGasLimit, _extraData);

    bool revert1 = e.msg.value > 0;
    bool revert2 = isOpen != 1;
    bool revert3 = _localToken == 0 || l1ToL2TokenRemoteToken != _localToken;
    bool revert4 = _amount > maxWithdrawsLocatOken;

    assert lastReverted <=> revert1 || revert2 || revert3 ||
                            revert4, "Revert rules failed";
}

// Verify correct storage changes for non reverting finalizeBridgeERC20
rule finalizeBridgeERC20(address _localToken, address _remoteToken, address _from, address _to, uint256 _amount, bytes _extraData) {
    env e;

    require _localToken == gem;

    mathint localTokenTotalSupplyBefore = gem.totalSupply();
    mathint localTokenBalanceOfToBefore = gem.balanceOf(_to);
    // ERC20 assumption
    require localTokenTotalSupplyBefore >= localTokenBalanceOfToBefore;

    finalizeBridgeERC20(e, _localToken, _remoteToken, _from, _to, _amount, _extraData);

    mathint localTokenTotalSupplyAfter = gem.totalSupply();
    mathint localTokenBalanceOfToAfter = gem.balanceOf(_to);

    assert localTokenTotalSupplyAfter == localTokenTotalSupplyBefore + _amount, "Assert 1";
    assert localTokenBalanceOfToAfter == localTokenBalanceOfToBefore + _amount, "Assert 2";
}

// Verify revert rules on finalizeBridgeERC20
rule finalizeBridgeERC20_revert(address _localToken, address _remoteToken, address _from, address _to, uint256 _amount, bytes _extraData) {
    env e;

    require _localToken == gem;

    address messenger = messenger();
    address otherBridge = otherBridge();
    address xDomainMessageSender = l2messenger.xDomainMessageSender();

    mathint localTokenTotalSupply = gem.totalSupply();
    mathint localTokenBalanceOfTo = gem.balanceOf(_to);
    // ERC20 assumption
    require localTokenTotalSupply >= localTokenBalanceOfTo;
    // Practical assumption
    require localTokenTotalSupply + _amount <= max_uint256;
    // Set up assumption
    require gem.wards(currentContract) == 1;

    finalizeBridgeERC20@withrevert(e, _localToken, _remoteToken, _from, _to, _amount, _extraData);

    bool revert1 = e.msg.value > 0;
    bool revert2 = e.msg.sender != messenger || xDomainMessageSender != otherBridge;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}
