// L1TokenBridge.spec

using Auxiliar as aux;
using MessengerMock as l1messenger;
using GemMock as gem;

methods {
    // storage variables
    function wards(address) external returns (uint256) envfree;
    function l1ToL2Token(address) external returns (address) envfree;
    function isOpen() external returns (uint256) envfree;
    function escrow() external returns (address) envfree;
    // immutables
    function otherBridge() external returns (address) envfree;
    function messenger() external returns (address) envfree;
    //
    function gem.allowance(address,address) external returns (uint256) envfree;
    function gem.totalSupply() external returns (uint256) envfree;
    function gem.balanceOf(address) external returns (uint256) envfree;
    function aux.getBridgeMessageHash(address,address,address,address,uint256,bytes) external returns (bytes32) envfree;
    function l1messenger.xDomainMessageSender() external returns (address) envfree;
    function l1messenger.lastTarget() external returns (address) envfree;
    function l1messenger.lastMessageHash() external returns (bytes32) envfree;
    function l1messenger.lastMinGasLimit() external returns (uint32) envfree;
    //
    function _.transferFrom(address,address,uint256) external => DISPATCHER(true);
}

definition addrZero() returns address = 0x0000000000000000000000000000000000000000;

// Verify that each storage layout is only modified in the corresponding functions
rule storageAffected(method f) filtered { f -> f.selector != sig:upgradeToAndCall(address, bytes).selector } {
    env e;

    address anyAddr;

    mathint wardsBefore = wards(anyAddr);
    address l1ToL2TokenBefore = l1ToL2Token(anyAddr);
    mathint isOpenBefore = isOpen();
    address escrowBefore = escrow();

    calldataarg args;
    f(e, args);

    mathint wardsAfter = wards(anyAddr);
    address l1ToL2TokenAfter = l1ToL2Token(anyAddr);
    mathint isOpenAfter = isOpen();
    address escrowAfter = escrow();

    assert wardsAfter != wardsBefore => f.selector == sig:rely(address).selector || f.selector == sig:deny(address).selector || f.selector == sig:initialize().selector, "Assert 1";
    assert l1ToL2TokenAfter != l1ToL2TokenBefore => f.selector == sig:registerToken(address,address).selector, "Assert 2";
    assert isOpenAfter != isOpenBefore => f.selector == sig:close().selector || f.selector == sig:initialize().selector, "Assert 3";
    assert escrowAfter != escrowBefore => f.selector == sig:file(bytes32,address).selector, "Assert 4";
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

// Verify correct storage changes for non reverting file
rule file(bytes32 what, address data) {
    env e;

    file(e, what, data);

    address escrowAfter = escrow();

    assert escrowAfter == data, "Assert 1";
}

// Verify revert rules on file
rule file_revert(bytes32 what, address data) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    file@withrevert(e, what, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    bool revert3 = what != to_bytes32(0x657363726f770000000000000000000000000000000000000000000000000000);

    assert lastReverted <=> revert1 || revert2 || revert3, "Revert rules failed";
}

// Verify correct storage changes for non reverting close
rule close() {
    env e;

    close(e);

    uint256 isOpenAfter = isOpen();

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

// Verify correct storage changes for non reverting bridgeERC20
rule bridgeERC20(address _localToken, address _remoteToken, uint256 _amount, uint32 _minGasLimit, bytes _extraData) {
    env e;

    require _localToken == gem;

    address otherBridge = otherBridge();
    address escrow = escrow();
    require e.msg.sender != escrow;

    bytes32 message = aux.getBridgeMessageHash(_localToken, _remoteToken, e.msg.sender, e.msg.sender, _amount, _extraData);
    uint256 localTokenBalanceOfSenderBefore = gem.balanceOf(e.msg.sender);
    uint256 localTokenBalanceOfEscrowBefore = gem.balanceOf(escrow);
    // ERC20 assumption
    require gem.totalSupply >= localTokenBalanceOfSenderBefore + localTokenBalanceOfEscrowBefore;

    bridgeERC20(e, _localToken, _remoteToken, _amount, _minGasLimit, _extraData);

    address lastTargetAfter = l1messenger.lastTarget();
    bytes32 lastMessageHashAfter = l1messenger.lastMessageHash();
    uint32  lastMinGasLimitAfter = l1messenger.lastMinGasLimit();
    uint256 localTokenBalanceOfSenderAfter = gem.balanceOf(e.msg.sender);
    uint256 localTokenBalanceOfEscrowAfter = gem.balanceOf(escrow);

    assert lastTargetAfter == otherBridge, "Assert 1";
    assert lastMessageHashAfter == message, "Assert 2";
    assert lastMinGasLimitAfter == _minGasLimit, "Assert 3";
    assert localTokenBalanceOfSenderAfter == localTokenBalanceOfSenderBefore - _amount, "Assert 4";
    assert localTokenBalanceOfEscrowAfter == localTokenBalanceOfEscrowBefore + _amount, "Assert 5";
}

// Verify revert rules on bridgeERC20
rule bridgeERC20_revert(address _localToken, address _remoteToken, uint256 _amount, uint32 _minGasLimit, bytes _extraData) {
    env e;

    mathint isOpen = isOpen();
    address l1ToL2TokenLocalToken = l1ToL2Token(_localToken);

    address escrow = escrow();

    uint256 localTokenBalanceOfSender = gem.balanceOf(e.msg.sender);
    uint256 localTokenBalanceOfEscrow = gem.balanceOf(escrow);

    // ERC20 assumption
    require gem.totalSupply() >= localTokenBalanceOfSender + localTokenBalanceOfEscrow;
    // User assumptions
    require localTokenBalanceOfSender >= _amount;
    require gem.allowance(e.msg.sender, currentContract) >= _amount;

    bridgeERC20@withrevert(e, _localToken, _remoteToken, _amount, _minGasLimit, _extraData);

    bool revert1 = e.msg.value > 0;
    bool revert2 = nativeCodesize[e.msg.sender] != 0;
    bool revert3 = isOpen != 1;
    bool revert4 = _remoteToken == addrZero() || l1ToL2TokenLocalToken != _remoteToken;

    assert lastReverted <=> revert1 || revert2 || revert3 ||
                            revert4, "Revert rules failed";
}

// Verify correct storage changes for non reverting bridgeERC20To
rule bridgeERC20To(address _localToken, address _remoteToken, address _to, uint256 _amount, uint32 _minGasLimit, bytes _extraData) {
    env e;

    require _localToken == gem;

    address otherBridge = otherBridge();
    address escrow = escrow();
    require e.msg.sender != escrow;

    bytes32 message = aux.getBridgeMessageHash(_localToken, _remoteToken, e.msg.sender, _to, _amount, _extraData);
    uint256 localTokenBalanceOfSenderBefore = gem.balanceOf(e.msg.sender);
    uint256 localTokenBalanceOfEscrowBefore = gem.balanceOf(escrow);
    // ERC20 assumption
    require gem.totalSupply >= localTokenBalanceOfSenderBefore + localTokenBalanceOfEscrowBefore;

    bridgeERC20To(e, _localToken, _remoteToken, _to, _amount, _minGasLimit, _extraData);

    address lastTargetAfter = l1messenger.lastTarget();
    bytes32 lastMessageHashAfter = l1messenger.lastMessageHash();
    uint32  lastMinGasLimitAfter = l1messenger.lastMinGasLimit();
    uint256 localTokenBalanceOfSenderAfter = gem.balanceOf(e.msg.sender);
    uint256 localTokenBalanceOfEscrowAfter = gem.balanceOf(escrow);

    assert lastTargetAfter == otherBridge, "Assert 1";
    assert lastMessageHashAfter == message, "Assert 2";
    assert lastMinGasLimitAfter == _minGasLimit, "Assert 3";
    assert localTokenBalanceOfSenderAfter == localTokenBalanceOfSenderBefore - _amount, "Assert 4";
    assert localTokenBalanceOfEscrowAfter == localTokenBalanceOfEscrowBefore + _amount, "Assert 5";
}

// Verify revert rules on bridgeERC20To
rule bridgeERC20To_revert(address _localToken, address _remoteToken, address _to, uint256 _amount, uint32 _minGasLimit, bytes _extraData) {
    env e;

    mathint isOpen = isOpen();
    address l1ToL2TokenLocalToken = l1ToL2Token(_localToken);

    address escrow = escrow();

    uint256 localTokenBalanceOfSender = gem.balanceOf(e.msg.sender);
    uint256 localTokenBalanceOfEscrow = gem.balanceOf(escrow);

    // ERC20 assumption
    require gem.totalSupply() >= localTokenBalanceOfSender + localTokenBalanceOfEscrow;
    // User assumptions
    require localTokenBalanceOfSender >= _amount;
    require gem.allowance(e.msg.sender, currentContract) >= _amount;

    bridgeERC20To@withrevert(e, _localToken, _remoteToken, _to, _amount, _minGasLimit, _extraData);

    bool revert1 = e.msg.value > 0;
    bool revert2 = isOpen != 1;
    bool revert3 = _remoteToken == addrZero() || l1ToL2TokenLocalToken != _remoteToken;

    assert lastReverted <=> revert1 || revert2 || revert3, "Revert rules failed";
}

// Verify correct storage changes for non reverting finalizeBridgeERC20
rule finalizeBridgeERC20(address _localToken, address _remoteToken, address _from, address _to, uint256 _amount, bytes _extraData) {
    env e;

    require _localToken == gem;

    address escrow = escrow();

    uint256 localTokenBalanceOfEscrowBefore = gem.balanceOf(escrow);
    uint256 localTokenBalanceOfToBefore = gem.balanceOf(_to);

    // ERC20 assumption
    require gem.totalSupply() >= localTokenBalanceOfEscrowBefore + localTokenBalanceOfToBefore;

    finalizeBridgeERC20(e, _localToken, _remoteToken, _from, _to, _amount, _extraData);

    uint256 localTokenBalanceOfEscrowAfter = gem.balanceOf(escrow);
    uint256 localTokenBalanceOfToAfter = gem.balanceOf(_to);

    assert escrow != _to => localTokenBalanceOfEscrowAfter == localTokenBalanceOfEscrowBefore - _amount, "Assert 1";
    assert escrow != _to => localTokenBalanceOfToAfter == localTokenBalanceOfToBefore + _amount, "Assert 2";
    assert escrow == _to => localTokenBalanceOfEscrowAfter == localTokenBalanceOfEscrowBefore, "Assert 3";
}

// Verify revert rules on finalizeBridgeERC20
rule finalizeBridgeERC20_revert(address _localToken, address _remoteToken, address _from, address _to, uint256 _amount, bytes _extraData) {
    env e;

    require _localToken == gem;

    address messenger = messenger();
    address otherBridge = otherBridge();
    address xDomainMessageSender = l1messenger.xDomainMessageSender();
    address escrow = escrow();

    uint256 localTokenBalanceOfEscrow = gem.balanceOf(escrow);

    // ERC20 assumption
    require gem.totalSupply() >= localTokenBalanceOfEscrow + gem.balanceOf(_to);
    // Bridge assumption
    require localTokenBalanceOfEscrow >= _amount;
    // Set up assumption
    require gem.allowance(escrow, currentContract) == max_uint256;

    finalizeBridgeERC20@withrevert(e, _localToken, _remoteToken, _from, _to, _amount, _extraData);

    bool revert1 = e.msg.value > 0;
    bool revert2 = e.msg.sender != messenger || xDomainMessageSender != otherBridge;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}
